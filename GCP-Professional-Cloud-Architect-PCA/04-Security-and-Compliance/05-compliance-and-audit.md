# 04/05 · Designing for Compliance and Audit

**Exam guide:** 3.2 (legislation and regulation: health record privacy, children's privacy, data privacy, ownership, data sovereignty; commercial: credit card data and PII; industry certifications such as SOC 2; audits including logs). **Principles:** P6, P7, P10, P11, P13.

---

## 1. Shared responsibility (and "shared fate")

Google secures the **infrastructure**: data centers, hardware, the global network, the hypervisor, and the managed-service internals. **You** secure what you configure:

* identities and IAM;
* data classification and access;
* network exposure;
* application code;
* key choices;
* logging and retention;
* compliance processes.

The split shifts with the service model. You own more on Compute Engine and less on BigQuery or Cloud Run. Google calls its approach **shared fate**: it provides secure-by-default configurations, blueprints (the enterprise foundations blueprint), Assured Workloads and risk tooling to help you land correctly.

**Exam rule:** a certification Google holds (ISO 27001, SOC 2, PCI DSS as a service provider) **doesn't make your workload compliant**. You still have to configure and operate the workload compliantly.

---

## 2. Regulations → design controls

| Regime | What it protects | Design controls on Google Cloud |
|---|---|---|
| **HIPAA** (US health records) | Protected health information (PHI) | Sign Google's **Business Associate Agreement (BAA)**; use only **HIPAA-covered services** for PHI; least-privilege IAM; **Data Access audit logs**; encryption (default + CMEK if policy requires); VPC SC; **Cloud Healthcare API** (FHIR/HL7v2/DICOM) for health data; de-identify for analytics. Fits **EHR Healthcare** |
| **GDPR** (EU personal data) and similar privacy laws | Personal data of EU residents | Data minimization, purpose limitation, lawful basis (process); **data subject rights** (access, erasure: design data maps and deletion paths; crypto-shredding with CMEK); data residency choices (EU regions, `gcp.resourceLocations`); Google's Cloud Data Processing Addendum; pseudonymization (SDP); breach notification processes. Fits **KnightMotives** |
| **Children's privacy** (for example, COPPA in the US) | Data about children under a threshold age | Verifiable parental consent flows; collect the minimum; no behavioral advertising profiles; age gating (Identity Platform / app logic); strict retention and deletion |
| **Data sovereignty** | Data and operations under a jurisdiction's control | Regional resources and location org policy; **Assured Workloads** (data boundary, personnel access controls); **Cloud EKM** (keys outside Google) with Key Access Justifications; **Access Approval**; partner-operated sovereign offerings; **Google Distributed Cloud air-gapped** for disconnected sovereign workloads |
| **Data ownership** | The customer owns its data | Google's terms commit to processing customer data only per instructions; export paths (open formats, Storage Transfer) prevent lock-in; Access Transparency for visibility |
| **PCI DSS** (credit card data) | Cardholder data environment (CDE) | **Minimize scope**: tokenize card numbers with a payment provider or SDP tokenization so most systems never see a primary account number (PAN); isolate the CDE in **separate projects/VPCs** with strict firewalling and VPC SC; logging and monitoring; vulnerability management; key management. Google Cloud is a PCI DSS-validated service provider for in-scope services |
| **PII generally** (commercial obligation) | Personal data in apps, logs, transcripts | Sensitive Data Protection discovery and de-identification; field-level controls (policy tags, masking); retention limits; Model Armor for AI apps |
| **SOC 2 / SOC 1 / ISO 27001 / 27017 / 27018 / FedRAMP** (certifications) | Assurance about controls | Google provides its reports via **Compliance Reports Manager**. **Your** SOC 2 needs your own controls and evidence (change management, access reviews, logging, incident response) |

---

## 3. Assured Workloads

**Assured Workloads** creates a folder whose resources are constrained to a **compliance regime**. Depending on the regime, it provides:

* **Data residency:** location restrictions enforced.
* **Personnel access controls:** support by personnel meeting criteria such as citizenship or location.
* **Allowed services** limited to those in scope.
* **Encryption requirements** (CMEK / EKM).
* **Monitoring** of violations.

Regimes include **FedRAMP Moderate/High**, **DoD IL2/IL4/IL5**, **CJIS**, **ITAR**, **HIPAA**-aligned controls, **EU Data Boundary / sovereign controls** for the EU and other countries, and more.

**Choose Assured Workloads when** the question names a regime that requires residency **and** personnel or support controls. That's more than an org policy can provide.

---

## 4. Audits and logs

### What to log and keep

| Evidence | Source | Retention approach |
|---|---|---|
| Who changed configuration | **Admin Activity** audit logs (always on) | `_Required` bucket keeps 400 days (not configurable); route copies to a central bucket for longer |
| Who accessed sensitive data | **Data Access** audit logs (enable per service; BigQuery on by default) | `_Default` bucket default 30 days (configurable up to 3,650 days); route to a central bucket |
| Google personnel access | **Access Transparency** logs | Same as above |
| Policy denials | Policy Denied logs | Same |
| Network evidence | VPC Flow Logs, Firewall Rules Logging | Cost-aware sampling; route to BigQuery or a bucket |
| Application events | App logs via Cloud Logging | As policy requires |

### Making logs audit-grade

1. **Aggregated sinks** at the organization or folder level capture every project's logs, including future projects.
2. **Destination:** a **log bucket** in a dedicated logging project with the required **retention**, and **bucket lock** to make retention immutable. Or BigQuery for analytics, or Cloud Storage (Archive class + Bucket Lock) for cheap long-term WORM retention.
3. **Separation of duties:** workload teams can't modify sinks or log buckets. Auditors get read-only access (`roles/logging.viewer`, `roles/logging.privateLogViewer` for Data Access logs, or Log Analytics views).
4. **Log Analytics** (SQL over log buckets) or BigQuery for investigations.
5. **Exclusions** cut noise and cost, but never exclude audit logs required for compliance.

```bash
# Org-level aggregated sink: all audit logs from every project to a central log bucket
gcloud logging sinks create org-audit-sink \
  logging.googleapis.com/projects/central-logging/locations/global/buckets/audit-7y \
  --organization=123456789012 --include-children \
  --log-filter='logName:"cloudaudit.googleapis.com"'
```

(After creating the sink, grant its writer identity permission on the destination bucket, and set the bucket's retention to the required period and lock it.)

---

## 5. Compliance evidence and continuous compliance

| Need | Tooling |
|---|---|
| Google's certifications and reports for your auditors | **Compliance Reports Manager** |
| Continuous checks against benchmarks (CIS, PCI DSS, NIST 800-53, ISO 27001) | **Security Command Center** compliance dashboards and security posture |
| Policy as code and preventive guardrails | Org policies (custom constraints), Policy Controller (GKE), Terraform policy validation in CI |
| Regime boundaries | Assured Workloads violation monitoring |
| Access reviews | IAM Recommender (remove unused permissions), Policy Analyzer ("who can access what"), Policy Troubleshooter |

---

## 6. Worked scenarios

**A. "EHR must retain audit logs for 6 years, immutably, across all current and future projects, at minimum cost."**
An org-level aggregated sink to a central **log bucket** with 6-year retention, **locked**; or a sink to Cloud Storage Archive class with a **retention policy + Bucket Lock**. Auditors get read-only access. Include Data Access logs for PHI services.

**B. "A payments team wants to cut PCI DSS scope for its analytics platform."**
Tokenize PANs at capture (payment provider or SDP format-preserving tokenization). Analytics uses only tokens, so BigQuery and the analytics projects fall out of the CDE. Isolate the remaining CDE in dedicated projects with VPC SC and strict IAM.

**C. "A kids' learning app is launching in the US and EU."**
Children's-privacy and GDPR controls: parental consent, data minimization, no ad profiling, EU data in EU regions (location policy), deletion workflows, de-identified analytics.

**D. "A government agency requires that only citizens of its country can support its workloads, and data stays in-country."**
**Assured Workloads** with the appropriate sovereign or regime controls (personnel and residency), plus Cloud EKM and Access Approval if key custody is also required.

---

## References

* Shared responsibility and shared fate: <https://cloud.google.com/architecture/framework/security/shared-responsibility-shared-fate>
* HIPAA on Google Cloud: <https://cloud.google.com/security/compliance/hipaa>
* GDPR and Google Cloud: <https://cloud.google.com/privacy/gdpr>
* PCI DSS on Google Cloud: <https://cloud.google.com/architecture/pci-dss-compliance-in-gcp>
* Assured Workloads overview: <https://cloud.google.com/assured-workloads/docs/overview>
* Compliance Reports Manager: <https://cloud.google.com/security/compliance/compliance-reports-manager>
* Configure log buckets and retention: <https://cloud.google.com/logging/docs/buckets>
* Aggregated sinks: <https://cloud.google.com/logging/docs/export/aggregated_sinks>
