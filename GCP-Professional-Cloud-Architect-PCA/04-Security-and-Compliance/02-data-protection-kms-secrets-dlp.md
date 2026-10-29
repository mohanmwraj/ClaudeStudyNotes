# 04/02 · Data Protection: Keys, Encryption, Secrets and Sensitive Data

**Exam guide:** 3.1 (data security: key management, encryption, secret management; managing CMEK with Cloud KMS), 3.2 (PII, credit card data). **Principle:** P11.

---

## 1. Encryption layers on Google Cloud

| Layer | Default behavior | Your options |
|---|---|---|
| **At rest** | Always encrypted (AES-256) with Google-managed keys, using envelope encryption: data encryption keys (DEKs) wrapped by key encryption keys (KEKs) | **CMEK** (Cloud KMS), **Cloud HSM**, **Cloud EKM**, CSEK (Cloud Storage and Compute Engine only) |
| **In transit** | TLS from clients to Google front ends; Google encrypts and authenticates traffic between its facilities (ALTS internally) | TLS everywhere in your apps; mTLS with Cloud Service Mesh; MACsec or HA VPN over Interconnect for hybrid links |
| **In use** | Normal VM memory | **Confidential Computing**: Confidential VMs (AMD SEV/SEV-SNP, Intel TDX), Confidential GKE Nodes, Confidential Space (multi-party computation on sensitive data) |

---

## 2. Cloud KMS and key custody

### Key hierarchy

```text
Project (ideally a dedicated security/KMS project)
 └── Key ring (location-bound: region, dual-region, multi-region or global; can't be deleted)
      └── Key (purpose: symmetric encrypt/decrypt, asymmetric sign/decrypt, MAC)
           └── Key versions (rotation creates new versions; old versions still decrypt old data)
```

### Protection levels

| Protection level | Key material lives | Compliance angle |
|---|---|---|
| SOFTWARE | Cloud KMS (software) | Customer-controlled lifecycle |
| **HSM** (Cloud HSM) | FIPS 140-2 Level 3 validated HSMs operated by Google | "Keys must be in hardware security modules" |
| **EXTERNAL** / **EXTERNAL_VPC** (Cloud EKM) | Your external key manager (partner such as Thales, Fortanix), reached over the internet or a VPC | "Keys must never be stored in Google Cloud"; sovereignty; with **Key Access Justifications** you can approve or deny each access by reason |

### CMEK facts the exam tests

* The service (BigQuery, Cloud Storage, Cloud SQL, GKE, Agent Platform, Compute Engine disks, Pub/Sub…) uses **your** KMS key to wrap its DEKs. You control **rotation**, **IAM on key use**, **disable** and **destroy**.
* **Disabling or destroying a key makes the data unreadable** (crypto-shredding). That's useful for revocation, and dangerous for availability.
* **Key location must be compatible with the resource location.** An EU bucket needs a key in a compatible EU location.
* Grant the service's **service agent** `roles/cloudkms.cryptoKeyEncrypterDecrypter` on the key.
* **Automatic rotation** for symmetric keys (for example, every 90 days). Rotation doesn't re-encrypt existing data; old versions remain for decryption.
* **Destruction is scheduled** (default 30 days, configurable) so mistakes can be reversed.
* **Cloud KMS Autokey** automatically creates keys with appropriate settings and assigns CMEK when resources are created. It makes CMEK at scale practical (paired with an org policy requiring CMEK: `gcp.restrictNonCmekServices`).
* **Separation of duties:** key admins (`cloudkms.admin`) are different from key users; keys sit in a separate project from data.

### Choosing the option

| Requirement in the question | Choose |
|---|---|
| "Data must be encrypted at rest" (nothing more) | **Default encryption** (already true) |
| "Company must control key rotation and be able to revoke access" | **CMEK** (Cloud KMS) |
| "Keys must be in FIPS 140-2 Level 3 hardware" | **Cloud HSM** (CMEK with HSM protection) |
| "Keys must be held outside Google; Google must justify every access" | **Cloud EKM + Key Access Justifications** |
| "Many teams create resources; enforce CMEK without manual key creation" | **Autokey** + `gcp.restrictNonCmekServices` org policy |
| "Application must encrypt specific fields before storing" | Client-side envelope encryption using Cloud KMS (or Tink with KMS) |

---

## 3. Secret Manager

| Feature | Use |
|---|---|
| Secrets with **versions** | Rotate by adding versions; pin or use `latest` |
| **IAM per secret** (`roles/secretmanager.secretAccessor`) | Least privilege per workload |
| **Rotation schedules** | Publishes a Pub/Sub notification so a Cloud Run function can rotate the credential |
| Replication | **Automatic** (Google chooses) or **user-managed** (you choose regions, for residency); regional secrets |
| CMEK | Encrypt secret payloads with your keys |
| Integrations | Cloud Run / Cloud Run functions mount secrets as volumes or env vars; GKE Secret Manager add-on / CSI driver; Cloud Build |
| Audit | Every access is logged in Cloud Audit Logs (Data Access) |

**Never** store secrets in source code, container images, instance metadata or plain environment variables in IaC. Don't store service account keys in Secret Manager as a "secure" alternative to federation; eliminate the key.

**Certificate Authority Service** issues private certificates (internal mTLS, device identities) with managed CAs. **Certificate Manager** handles public TLS certificates for load balancers.

---

## 4. Sensitive Data Protection (formerly Cloud DLP)

| Capability | What it does | Example |
|---|---|---|
| **Discovery** (data profiles) | Continuously scans BigQuery, Cloud Storage, Cloud SQL and others at org/folder/project level; reports sensitivity and risk | "Find where PII lives across 300 projects" |
| **Inspection** | Detects 150+ built-in infoTypes (credit card numbers, SSNs, emails, health identifiers) plus custom infoTypes | Scan support transcripts |
| **De-identification** | **Redaction**, **masking**, **replacement**, **bucketing**, **date shifting**, **tokenization / pseudonymization** with **deterministic encryption** or **format-preserving encryption (FPE)** using KMS-wrapped keys (reversible with the key) | Remove card numbers from chat logs; pseudonymize patient IDs for analytics while allowing authorized re-identification |
| **Re-identification risk analysis** | k-anonymity, l-diversity, k-map, δ-presence | Before sharing a dataset externally (KnightMotives data monetization) |
| Integrations | Inline API calls, Dataflow templates (de-identify on ingest), BigQuery remote functions, Security Command Center, Model Armor (sensitive data filters for AI) | |

**Pattern:** ingest → Dataflow with Sensitive Data Protection de-identification → BigQuery (analytics on pseudonymized data). Raw data goes to a restricted project with CMEK and VPC SC; re-identification keys are held by a separate team.

---

## 5. Google-side access controls (trust and sovereignty)

| Control | What it gives you |
|---|---|
| **Access Transparency** | Near-real-time logs of actions Google personnel take on your content (with justification) |
| **Access Approval** | You must explicitly approve Google personnel access requests (for supported services) |
| **Key Access Justifications** (with Cloud EKM) | Every request to use your externally held key carries a reason, and your policy can refuse it |
| **Assured Workloads** | Applies compliance-regime controls (data residency, personnel access restrictions, allowed services, CMEK requirements) to a folder: FedRAMP, IL4/IL5, CJIS, HIPAA-aligned controls, EU Data Boundary / sovereign controls, and more |

---

## 6. Database and analytics data protection

| Need | Control |
|---|---|
| Column-level restriction (only HR sees salary) | BigQuery **policy tags** (column-level access control), **dynamic data masking** |
| Row-level restriction (EU analysts see EU rows) | BigQuery **row access policies** |
| Share a subset without exposing base tables | **Authorized views** / authorized datasets / authorized functions |
| Database credentials | **IAM database authentication** (Cloud SQL, AlloyDB), connectors, Secret Manager for remaining passwords |
| Encryption with your keys | CMEK on Cloud SQL, AlloyDB, Spanner, BigQuery, Bigtable, Firestore |
| Prevent exfiltration | VPC Service Controls |

---

## 7. Worked scenarios

**A. "A healthcare company must be able to make all copies of a patient dataset unreadable on demand."**
CMEK on every store holding the dataset (BigQuery, Cloud Storage, Cloud SQL), with keys in a separate project; disable or destroy the key version to crypto-shred. Document availability risk and protect the key with SoD.

**B. "Call recordings and transcripts contain card numbers; analysts need the transcripts."**
Sensitive Data Protection de-identification (redact or mask card numbers, tokenize customer IDs) in the ingestion pipeline before data reaches BigQuery. Keep raw data restricted or don't store it, to minimize PCI scope.

**C. "EU regulator requires that Google can't access encryption keys without the customer's approval."**
Cloud EKM with Key Access Justifications (keys held by an external partner in the EU), plus Assured Workloads EU controls and Access Approval where supported.

**D. "Database passwords are in a config file in the repository."**
Move them to Secret Manager with per-service IAM and rotation; better, switch to IAM database authentication to eliminate passwords where supported.

---

## References

* Default encryption at rest: <https://cloud.google.com/docs/security/encryption/default-encryption>
* Cloud KMS overview: <https://cloud.google.com/kms/docs/key-management-service>
* CMEK: <https://cloud.google.com/kms/docs/cmek>
* Cloud KMS Autokey: <https://cloud.google.com/kms/docs/autokey-overview>
* Cloud EKM: <https://cloud.google.com/kms/docs/ekm>
* Secret Manager overview: <https://cloud.google.com/secret-manager/docs/overview>
* Sensitive Data Protection: <https://cloud.google.com/sensitive-data-protection/docs/sensitive-data-protection-overview>
* Access Transparency: <https://cloud.google.com/assured-workloads/access-transparency/docs/overview>
