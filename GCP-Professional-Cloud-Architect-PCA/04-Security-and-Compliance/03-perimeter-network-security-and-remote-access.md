# 04/03 · Perimeters, Security Controls and Secure Remote Access

**Exam guide:** 3.1 (security controls: auditing, VPC Service Controls, context-aware access, organization policy, hierarchical firewall policy; secure remote access: Identity-Aware Proxy, service account impersonation, Chrome Enterprise Premium, Workload Identity Federation). **Principles:** P6, P7, P14.

---

## 1. The master table: which control stops which threat

This is the single most useful table for security questions. Read the threat, then pick the control in that row.

| Threat / requirement | Control | Why the others fail |
|---|---|---|
| An authorized insider or stolen credential **copies data from BigQuery/Cloud Storage to a project outside the organization** | **VPC Service Controls** perimeter | IAM already allows the user; firewalls don't see Google API calls |
| Someone grants a role to `gmail.com` accounts | Org policy **domain-restricted sharing** (`iam.allowedPolicyMemberDomains`) | IAM can't stop a project owner granting roles |
| Teams create VMs with public IPs | Org policy `compute.vmExternalIpAccess` | Firewall rules can be changed by project owners |
| Resources created outside the EU | Org policy `gcp.resourceLocations` | IAM controls *who*, not *where* |
| A permission must never be used except by one group, regardless of grants | **IAM deny policy** | Allow policies are additive, so they can't revoke an inherited grant |
| Employees must reach internal web apps **without VPN**, only from managed devices | **IAP** + **context-aware access** (Access Context Manager access levels), part of **Chrome Enterprise Premium** | VPN gives network-level access, not per-app identity and device checks |
| Admins need SSH/RDP to VMs with no public IPs and no bastion | **IAP TCP forwarding** + OS Login | Bastions are extra attack surface; public IPs are exposure |
| Org-wide rule: block a set of ports or ranges in every VPC, unoverridable by projects | **Hierarchical firewall policy** at the org or folder | VPC firewall rules are per-network and owned by project admins |
| East-west **intrusion prevention** with signatures | **Cloud NGFW Enterprise** (IPS) | Basic firewall rules don't inspect payloads |
| L7 attacks (SQL injection, XSS), DDoS, bots at the internet edge | **Cloud Armor** on the external Application LB | Firewall rules are L3/L4; IPS isn't an edge WAF |
| Workloads outside Google Cloud need API access without keys | **Workload Identity Federation** | SA keys are long-lived secrets |
| A human needs temporary elevated rights | **Service account impersonation** or **Privileged Access Manager** | Permanent grants violate least privilege |
| Only verified images may run on GKE | **Binary Authorization** | Vulnerability scanning detects but doesn't enforce |
| Prompt injection or data leakage via an LLM app | **Model Armor** | Firewalls and WAFs don't understand prompts |
| Need to know who changed what | **Cloud Audit Logs** (Admin Activity always on; enable Data Access) | Flow logs don't record API calls |
| Detect misconfigurations and threats across the organization | **Security Command Center** | Point tools lack org-wide correlation |

---

## 2. VPC Service Controls (VPC SC)

**What it is:** a **service perimeter** around projects that restricts Google API access to specified services (BigQuery, Cloud Storage, Agent Platform, Spanner…), so data can only move **within** the perimeter, or across it through explicitly allowed paths. It mitigates **data exfiltration** even when credentials are valid.

| Concept | Meaning |
|---|---|
| **Perimeter** | A set of projects (or VPC networks) and the **restricted services** protected inside |
| **Access levels** (Access Context Manager) | Conditions (IP ranges, device policy, identity, geography) under which requests from **outside** are allowed in |
| **Ingress / egress rules** | Fine-grained exceptions: which identities may call which services or methods across the boundary, to or from which projects |
| **Perimeter bridge** | Lets two perimeters share specific projects (legacy pattern; ingress/egress rules are usually preferred) |
| **Dry-run mode** | Logs what *would* be blocked, so you can roll out without breaking workloads |
| **VPC accessible services** | Limits which services can be reached from the perimeter's VPC networks |
| `restricted.googleapis.com` / PSC `vpc-sc` bundle | Private routing of API traffic to VPC-SC-supported services from VPCs and on-premises |

**Rollout pattern:**

1. Inventory the data flows.
2. Create the perimeter in **dry-run**.
3. Analyze violation logs.
4. Add ingress/egress rules or access levels.
5. Enforce.

**Typical exam uses**

* EHR's patient data projects.
* KnightMotives' data products before sharing.
* Cymbal's customer data.
* Protecting Agent Platform training data and models.

**What VPC SC doesn't do:** it doesn't replace IAM (users still need roles); it doesn't filter VM-to-VM traffic (firewalls do); and it isn't a WAF.

---

## 3. Context-aware access, IAP and Chrome Enterprise Premium

### Identity-Aware Proxy (IAP)

| IAP for… | How |
|---|---|
| **Web apps** behind an external/internal Application LB, App Engine or Cloud Run | IAP authenticates the user (Google identity or Workforce Identity Federation) and checks IAM (`roles/iap.httpsResourceAccessor`) plus access levels **before** traffic reaches the app |
| **On-premises / other-cloud apps** | Put them behind an Application LB with **hybrid connectivity NEGs**, then enable IAP |
| **TCP forwarding** (SSH, RDP, other TCP ports) | `gcloud compute ssh --tunnel-through-iap`. The firewall allows ingress only from IAP's range (35.235.240.0/20); no public IPs needed |

### Context-aware access

**Access Context Manager** defines **access levels**, such as "corporate IP ranges AND device is company-owned, encrypted and up to date". Access levels are enforced by IAP (apps and VMs), VPC SC (APIs) and Google Workspace / console access policies.

### Chrome Enterprise Premium (formerly BeyondCorp Enterprise)

Google's **zero-trust access** offering:

* **Context-aware access** to web apps, SaaS and Google Cloud resources (built on IAP and Access Context Manager).
* **Threat and data protection in the Chrome browser**: DLP for uploads, downloads and copy-paste; malware scanning; URL filtering.
* Device trust signals from endpoint verification.

**Exam pattern:** "Remote employees, contractors or dealers (KnightMotives) must securely access internal web apps from unmanaged or managed devices **without VPN**, with device posture checks and data-loss controls" → **Chrome Enterprise Premium** (IAP plus context-aware access).

---

## 4. Organization policy and hierarchical firewall: guardrails at the top

* **Organization policies** constrain configuration across the hierarchy. The list of constraints is in [04/01 §6](01-iam-and-resource-hierarchy.md#6-organization-policies-constraints-that-appear-in-questions).
* **Hierarchical firewall policies** enforce network rules at org or folder level, before any VPC rule. Use them for global denies (for example, block RDP from the internet everywhere), always-allow rules for security scanners, or a `goto_next` delegation to project-level rules.
* Both are **preventive** controls. Pair them with **detective** controls: SCC findings and audit logs.

---

## 5. Security Command Center and Google Security Operations

| Product | Role |
|---|---|
| **Security Command Center** (Standard / Premium / Enterprise tiers) | Org-wide **security posture**: misconfiguration findings (Security Health Analytics), vulnerability findings, **threat detection** (Event Threat Detection on logs, Container Threat Detection, VM Threat Detection), **attack path simulation** and toxic-combination findings, compliance reporting (CIS, PCI DSS, NIST, ISO), **security posture** management; Model Armor and AI protection integrations |
| SCC **Enterprise** | Adds multicloud coverage (AWS, Azure) and integrated SIEM/SOAR case management built on Google SecOps |
| **Google Security Operations** (SecOps; formerly Chronicle) | Cloud-scale **SIEM** (ingest and search security telemetry), **SOAR** (playbook automation for incident response), threat intelligence (Mandiant, VirusTotal) |
| **Web Security Scanner** | Scans App Engine, GKE and Compute Engine web apps for common vulnerabilities |
| **Cloud IDS** | Managed network intrusion detection (Palo Alto Networks threat signatures) via packet mirroring. Detection only; NGFW Enterprise provides prevention |
| **Google Cloud Fraud Defense** (formerly reCAPTCHA Enterprise) | Bot and fraud protection for sites and apps; integrates with Cloud Armor |

**KnightMotives pattern:** past breaches plus an incident response plan → SCC (posture and threats) feeding **Google SecOps** (SIEM/SOAR playbooks), plus a documented IR plan and tabletop exercises.

---

## 6. Auditing (control and evidence)

| Log type | Default | Contains |
|---|---|---|
| **Admin Activity** audit logs | **Always on**, can't be disabled, no charge | Configuration and metadata changes (create a VM, set an IAM policy) |
| **System Event** logs | Always on | Google-initiated system actions |
| **Data Access** audit logs | **Off by default** (except BigQuery) | Reads of metadata and user data (who read which object or row). Enable for sensitive services; volume and cost increase |
| **Policy Denied** logs | On (can be excluded) | Access denied by VPC SC or similar policies |
| **Access Transparency** logs | Enable (eligible support levels) | Google personnel access to your content |

Route audit logs with an **aggregated sink** to a central, locked log bucket (and/or BigQuery) for retention and analysis. See [04/05](05-compliance-and-audit.md) and [07/01](../07-Operations-Excellence/01-observability-monitoring-logging.md).

---

## 7. Worked scenarios

**A. "Data scientists must work with patient data in BigQuery and Agent Platform; data must never leave the approved projects, even via a notebook copying to a personal bucket."**
A VPC SC perimeter around the data and ML projects (BigQuery, Cloud Storage, Agent Platform restricted), with ingress allowed only from the corporate access level. Least-privilege IAM, CMEK if required, and Data Access logs.

**B. "Contractors need access to one internal web app; the company doesn't want to give them VPN or accounts in the corporate directory."**
IAP on the app's load balancer with Workforce Identity Federation (the contractor's IdP) or Cloud Identity external accounts in a contractor group, plus context-aware access for device posture (Chrome Enterprise Premium).

**C. "Prevent anyone from opening SSH to the internet in any VPC across the organization."**
A hierarchical firewall policy at the org denying 0.0.0.0/0 on port 22 (allowing the IAP range), plus OS Login and IAP for access.

**D. "Detect cryptomining on GKE and compromised service account keys across all projects."**
Security Command Center Premium/Enterprise (Container Threat Detection, Event Threat Detection, anomalous IAM grants), with findings exported to SecOps or Pub/Sub for response.

---

## References

* VPC Service Controls overview: <https://cloud.google.com/vpc-service-controls/docs/overview>
* Access Context Manager: <https://cloud.google.com/access-context-manager/docs/overview>
* IAP overview: <https://cloud.google.com/iap/docs/concepts-overview>
* IAP TCP forwarding: <https://cloud.google.com/iap/docs/using-tcp-forwarding>
* Chrome Enterprise Premium: <https://cloud.google.com/chrome-enterprise-premium/docs/overview>
* Hierarchical firewall policies: <https://cloud.google.com/firewall/docs/firewall-policies>
* Security Command Center: <https://cloud.google.com/security-command-center/docs/security-command-center-overview>
* Cloud Audit Logs: <https://cloud.google.com/logging/docs/audit>
