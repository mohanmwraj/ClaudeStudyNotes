# Domain 3 Drill · Designing for Security and Compliance (20 questions)

Original exam-style questions for objectives 3.1–3.2 (~17.5% of the exam). The notes for this domain are in [04-Security-and-Compliance](../04-Security-and-Compliance/). Keep the "which control stops which threat" table from [04/03](../04-Security-and-Compliance/03-perimeter-network-security-and-remote-access.md) in mind.

---

### Q1 · Task 3.1 · Single answer

The security operations team needs read-only visibility of IAM policies and security-relevant configuration in every project in the organization, including projects created in the future. Team membership changes often.

What should you do?

- **A.** Grant the Viewer basic role to each security engineer on every existing project.
- **B.** Grant the Owner role at the organization node to the security group.
- **C.** Write a script that grants read-only roles to each engineer whenever a new project is created.
- **D.** Grant a predefined read-only security role, such as Security Reviewer, to the security team's Google group at the organization node.

<details><summary>Answer</summary>

**Answer: D**

**Why (P7, P6):** Grants at the organization node are inherited by all current and future projects. Granting to a group handles membership churn, and a predefined read-only role keeps least privilege.

- **A** — wrong: per-project and per-person grants miss future projects, and Viewer is a broad basic role.
- **B** — wrong: Owner is massively over-privileged.
- **C** — wrong: fragile automation that duplicates what inheritance provides for free.
- **D** — correct: inherited, group-based, least privilege.

**Reference:** <https://cloud.google.com/resource-manager/docs/cloud-platform-resource-hierarchy>

</details>

### Q2 · Task 3.1 · Single answer

Developers hold the Editor role on the Development and Production folders. A recent mistake deleted a production Cloud SQL instance. Leadership wants to ensure that **only** the DBA group can delete Cloud SQL instances anywhere in the organization, without redesigning every role binding.

What should you do?

- **A.** Create an IAM deny policy at the organization that denies the `cloudsql.instances.delete` permission to all principals except the DBA group.
- **B.** Remove the Editor role at the folder level and grant it again on each project.
- **C.** Create an organization policy constraint that restricts Cloud SQL instance locations.
- **D.** Enable Cloud SQL deletion protection, and email developers asking them not to disable it.

<details><summary>Answer</summary>

**Answer: A**

**Why (P7, P6):** Allow policies are additive and inherited, so you can't subtract a permission with another allow. A deny policy overrides allows for the named permission, with exceptions for the DBA group.

- **A** — correct: a central, inherited deny with a precise exception.
- **B** — wrong: re-granting Editor per project still allows deletion.
- **C** — wrong: location restrictions don't control who can delete.
- **D** — wrong: deletion protection helps, but Editors can turn it off, and a request by email isn't a control.

**Reference:** <https://cloud.google.com/iam/docs/deny-overview>

</details>

### Q3 · Task 3.1 · Single answer

A GitHub Actions workflow deploys Terraform to production projects. Today it authenticates with a service account JSON key stored as a GitHub secret. Security wants all long-lived keys removed, and only the `main` branch of one repository allowed to deploy.

What should you do?

- **A.** Rotate the JSON key every 30 days and store it in Secret Manager.
- **B.** Create an API key for the deployment project and store it in GitHub.
- **C.** Configure Workload Identity Federation with a GitHub OIDC provider whose attribute condition allows only that repository's `main` branch, and let the workflow impersonate a narrowly scoped deployment service account.
- **D.** Run the deployments manually from an administrator's laptop with personal credentials.

<details><summary>Answer</summary>

**Answer: C**

**Why (P6):** Workload Identity Federation exchanges GitHub's short-lived OIDC token for a short-lived Google credential. Attribute conditions restrict *which* repository and branch can do so, and no key exists anywhere.

- **A** — wrong: still a long-lived key, just rotated.
- **B** — wrong: API keys don't authorize Terraform resource management.
- **C** — correct: keyless, scoped and auditable.
- **D** — wrong: manual, unaudited personal access to production.

**Reference:** <https://cloud.google.com/iam/docs/workload-identity-federation>

</details>

### Q4 · Task 3.1 · Single answer

A company stores customer data in BigQuery and Cloud Storage. Its contracts require that the company controls key rotation, and that it can make all copies of a customer's data unreadable on demand if the customer relationship ends.

What should you implement?

- **A.** Rely on Google's default encryption at rest.
- **B.** Customer-managed encryption keys (CMEK) in Cloud KMS, held in a dedicated key project, with automatic rotation and the ability to disable or destroy key versions.
- **C.** Customer-supplied encryption keys (CSEK) for both BigQuery and Cloud Storage.
- **D.** Encrypt fields in the application with an AES key stored in the source code repository.

<details><summary>Answer</summary>

**Answer: B**

**Why (P11):** CMEK gives the customer control over rotation and revocation. Disabling or destroying the key renders the data unreadable (crypto-shredding).

- **A** — wrong: Google manages default keys, so the customer can't control rotation or revoke them.
- **B** — correct: customer-controlled lifecycle, on services that support CMEK.
- **C** — wrong: BigQuery doesn't support CSEK (it's limited to Cloud Storage and Compute Engine), and CSEK is operationally heavy.
- **D** — wrong: keys in source code are a severe security flaw.

**Reference:** <https://cloud.google.com/kms/docs/cmek>

</details>

### Q5 · Task 3.1 · Single answer

A European bank's regulator requires that encryption keys for its Google Cloud data are never stored in Google's infrastructure, and that the bank can refuse any key-access request based on its stated reason.

What should you recommend?

- **A.** CMEK with Cloud HSM keys in an EU region.
- **B.** CMEK with software-protected Cloud KMS keys and automatic rotation.
- **C.** Customer-supplied encryption keys for every service.
- **D.** Cloud External Key Manager (Cloud EKM) with keys held in a supported external key manager, combined with Key Access Justifications.

<details><summary>Answer</summary>

**Answer: D**

**Why (P11):** Only Cloud EKM keeps key material outside Google. Key Access Justifications attach a reason to each key request, so the bank's policy can approve or deny it.

- **A** — wrong: Cloud HSM keys reside in Google-operated HSMs.
- **B** — wrong: software keys are stored in Cloud KMS.
- **C** — wrong: CSEK isn't supported by most services and doesn't provide justification-based control.
- **D** — correct: external custody plus per-request justification control.

**Reference:** <https://cloud.google.com/kms/docs/ekm>

</details>

### Q6 · Task 3.1 · Select TWO

A data platform holds sensitive data in BigQuery and Cloud Storage. The CISO requires that (1) data can't be copied to projects outside the organization, even by users with valid IAM permissions, and (2) access to the data APIs is allowed only from the corporate network and managed devices.

Which two actions should you take? (Select TWO.)

- **A.** Create a VPC Service Controls perimeter around the data projects that restricts the BigQuery and Cloud Storage APIs.
- **B.** Create VPC firewall rules that deny all egress traffic from the data projects' networks.
- **C.** Remove all IAM role bindings from the data projects.
- **D.** Define an Access Context Manager access level for corporate IP ranges and managed devices, and use it in the perimeter's ingress rules.
- **E.** Set the `gcp.resourceLocations` organization policy on the data projects.

<details><summary>Answer</summary>

**Answer: A, D**

**Why (P6):** VPC Service Controls blocks API-level data movement across the perimeter regardless of IAM. Access levels add context, such as network and device, for requests entering the perimeter.

- **A** — correct: mitigates exfiltration by authorized identities.
- **B** — wrong: firewall rules don't govern Google API calls (for example, a BigQuery copy to another project).
- **C** — wrong: breaks legitimate use and doesn't meet the "even with valid permissions" requirement.
- **D** — correct: context-aware conditions for allowed access.
- **E** — wrong: controls where resources are created, not data movement.

**Reference:** <https://cloud.google.com/vpc-service-controls/docs/overview>

</details>

### Q7 · Task 3.1 · Single answer

Administrators need SSH access to Linux VMs that have no external IP addresses. The security team rejects bastion hosts and VPN clients, and wants access controlled by IAM and fully audited.

What should you configure?

- **A.** A bastion host with a public IP address and SSH keys distributed to administrators.
- **B.** A client VPN connection for each administrator into the VPC.
- **C.** IAP TCP forwarding, with a firewall rule allowing IAP's source range on port 22, and OS Login to tie SSH access to IAM.
- **D.** A firewall rule allowing SSH from 0.0.0.0/0, with strong passwords on each VM.

<details><summary>Answer</summary>

**Answer: C**

**Why (P6, P14):** IAP authenticates and authorizes every connection with IAM, without public IPs or bastions. OS Login replaces metadata SSH keys with IAM-governed, audited access.

- **A** — wrong: a bastion is extra attack surface and key management, and security rejected it.
- **B** — wrong: VPN clients were rejected, and they grant network-level access.
- **C** — correct: identity-aware, private and audited.
- **D** — wrong: exposes SSH to the internet.

**Reference:** <https://cloud.google.com/iap/docs/using-tcp-forwarding>

</details>

### Q8 · Task 3.1 · Single answer

An automaker's dealers and contract mechanics need access to several internal web applications from a mix of managed and unmanaged devices. The company wants per-application access decisions based on identity and device posture, protection against data leakage through the browser, and no VPN.

What should you recommend?

- **A.** Site-to-site VPNs from every dealership to Google Cloud.
- **B.** Chrome Enterprise Premium, using IAP with context-aware access levels and browser-based data protection.
- **C.** A public external load balancer with HTTP basic authentication on each application.
- **D.** Attach each dealer's project to the company's Shared VPC.

<details><summary>Answer</summary>

**Answer: B**

**Why (P6):** Zero-trust access with per-application identity and device checks, plus browser DLP, is what Chrome Enterprise Premium (formerly BeyondCorp Enterprise) provides, with no VPN.

- **A** — wrong: network-level access, hardware and operational burden at every dealer.
- **B** — correct: context-aware, application-level zero-trust access with data protection.
- **C** — wrong: weak authentication and no device posture checks.
- **D** — wrong: Shared VPC is for networking inside one organization, not partner user access.

**Reference:** <https://cloud.google.com/chrome-enterprise-premium/docs/overview>

</details>

### Q9 · Task 3.1 · Single answer

A payments company must guarantee that only container images built by its CI pipeline, and free of critical vulnerabilities, can run on its production GKE clusters.

What should you implement?

- **A.** Binary Authorization in enforcement mode on the production clusters, requiring attestations created by the CI pipeline after the build and after a vulnerability-scan gate passes.
- **B.** Weekly Artifact Analysis vulnerability scans that email the security team about critical findings.
- **C.** A naming convention that requires developers to tag approved images with `-approved`.
- **D.** Restrict `kubectl` access to cluster administrators only.

<details><summary>Answer</summary>

**Answer: A**

**Why (P12, P6):** Scanning *detects* problems. Only an admission-time policy *enforces* that every deployed image carries the required signed attestations.

- **A** — correct: deploy-time enforcement of provenance and vulnerability gates.
- **B** — wrong: detection after the fact, with no prevention.
- **C** — wrong: tags are mutable and unverified.
- **D** — wrong: admins could still deploy unverified images, and CI deploys bypass the restriction.

**Reference:** <https://cloud.google.com/binary-authorization/docs/overview>

</details>

### Q10 · Task 3.1 · Single answer

A retailer is launching a customer-facing shopping assistant built on Gemini. Security wants to block prompt-injection and jailbreak attempts, and to stop the assistant from returning other customers' personal data in its responses.

What should you add to the architecture?

- **A.** A Cloud Armor security policy with preconfigured OWASP rules on the load balancer.
- **B.** A VPC Service Controls perimeter around the project, with no other changes.
- **C.** A higher model temperature, so responses vary more.
- **D.** Model Armor templates that screen prompts and responses for prompt injection, jailbreaks and sensitive data, applied inline in the assistant's request flow.

<details><summary>Answer</summary>

**Answer: D**

**Why (P16, P11):** LLM-specific threats require LLM-aware screening. Model Armor inspects prompt and response content, including sensitive-data detection backed by Sensitive Data Protection.

- **A** — wrong: Cloud Armor understands HTTP attacks, not natural-language prompt manipulation.
- **B** — wrong: VPC SC protects APIs from exfiltration. It doesn't inspect prompts or responses.
- **C** — wrong: temperature affects randomness, not safety.
- **D** — correct: purpose-built prompt and response protection.

**Reference:** <https://cloud.google.com/security-command-center/docs/model-armor-overview>

</details>

### Q11 · Task 3.1 · Single answer

Auditors flagged that the same group can both manage Cloud KMS keys and decrypt the data those keys protect. The data pipeline's service account also holds broad KMS permissions. The company must enforce separation of duties.

What should you do?

- **A.** Grant the Owner role on the data projects to both the key administrators and the pipeline service account.
- **B.** Put key administration and data access in one "crypto" group, to simplify audits.
- **C.** Keep keys in a dedicated KMS project; grant Cloud KMS Admin only to the key administrators' group, and grant the CryptoKey Encrypter/Decrypter role only to the pipeline's service account (or the service agent) on the specific keys it needs.
- **D.** Grant Cloud KMS Admin to the pipeline service account, so it can rotate keys itself.

<details><summary>Answer</summary>

**Answer: C**

**Why (P6, P11):** Separating key management from key use, and keeping keys in their own project, means no single identity can both control keys and read data.

- **A** — wrong: Owner grants everything.
- **B** — wrong: combines the duties that must be separated.
- **C** — correct: role separation plus project separation, scoped to specific keys.
- **D** — wrong: gives the workload management power over its own keys.

**Reference:** <https://cloud.google.com/kms/docs/separation-of-duties>

</details>

### Q12 · Task 3.1 · Single answer

A company wants to stop service account key creation across its organization. One legacy project still depends on a key for an on-premises application, and will be migrated to Workload Identity Federation within three months.

What should you do?

- **A.** Leave the constraint unenforced until the legacy project is migrated.
- **B.** Enforce the `iam.disableServiceAccountKeyCreation` constraint at the organization, override it for the legacy project only with a documented review date, and track the migration to Workload Identity Federation.
- **C.** Create an IAM deny policy that blocks all API calls from the legacy project.
- **D.** Delete the legacy project, so the constraint can be enforced everywhere today.

<details><summary>Answer</summary>

**Answer: B**

**Why (P7, P6):** Organization policies are inherited, and can be overridden at a lower node when justified. That protects everything else immediately while the exception is time-bound.

- **A** — wrong: leaves the whole organization exposed for months.
- **B** — correct: org-wide protection with a narrow, governed exception.
- **C** — wrong: breaks the legacy application entirely.
- **D** — wrong: destroys a production dependency.

**Reference:** <https://cloud.google.com/resource-manager/docs/organization-policy/org-policy-constraints>

</details>

### Q13 · Task 3.1 · Select THREE

A team is building a new GKE platform for a payment application. Which three measures follow Google-recommended security practices? (Select THREE.)

- **A.** Store database passwords in Kubernetes ConfigMaps, so pods can read them easily.
- **B.** Store credentials in Secret Manager, accessed by pods through Workload Identity Federation for GKE.
- **C.** Use private nodes with no external IP addresses, and restrict control-plane access.
- **D.** Grant every developer `cluster-admin` on the production cluster, to speed up troubleshooting.
- **E.** Run the nodes as the default Compute Engine service account with the Editor role.
- **F.** Enforce Binary Authorization on the production cluster.

<details><summary>Answer</summary>

**Answer: B, C, F**

**Why (P6, P11, P12):** Defense in depth: keyless workload identity with managed secrets, a private network surface, and supply-chain enforcement at deploy time.

- **A** — wrong: ConfigMaps aren't for secrets, and values are stored in plain text.
- **B** — correct: managed secrets with per-workload, keyless access.
- **C** — correct: reduces exposure of nodes and the control plane.
- **D** — wrong: violates least privilege on a payments cluster.
- **E** — wrong: an over-privileged default identity on every node.
- **F** — correct: only attested images run in production.

**Reference:** <https://cloud.google.com/kubernetes-engine/docs/how-to/hardening-your-cluster>

</details>

### Q14 · Task 3.1 · Single answer

A company manages 5,000 employees in Okta. It wants employees to use the Google Cloud console and `gcloud` with their Okta credentials and Okta groups, and it doesn't want to create or synchronize user accounts in Cloud Identity.

What should you configure?

- **A.** Workforce Identity Federation with a workforce pool and an Okta provider (OIDC or SAML), mapping Okta groups to IAM principals.
- **B.** Managed Service for Microsoft Active Directory, joined to Okta.
- **C.** Manually created Google accounts for each employee, with Okta passwords copied over.
- **D.** Workload Identity Federation with an Okta provider for each employee's laptop.

<details><summary>Answer</summary>

**Answer: A**

**Why (P6):** Workforce Identity Federation lets an external IdP authenticate *people* directly to Google Cloud, with attribute and group mapping and no account synchronization.

- **A** — correct: federated workforce access without duplicate identities.
- **B** — wrong: Managed Microsoft AD serves workloads that need AD, not console sign-in.
- **C** — wrong: duplicate accounts and copied passwords are insecure and unmanageable.
- **D** — wrong: Workload Identity Federation is for *workloads*, not human users.

**Reference:** <https://cloud.google.com/iam/docs/workforce-identity-federation>

</details>

### Q15 · Task 3.2 · Single answer

A US telehealth startup will store protected health information (PHI) in Google Cloud. The CEO believes that because Google Cloud holds ISO 27001 and SOC 2 certifications, the startup is automatically HIPAA compliant.

What should the architect advise?

- **A.** Agree. Google's certifications make every workload on Google Cloud HIPAA compliant.
- **B.** Keep all PHI on-premises, because cloud providers can't support HIPAA workloads.
- **C.** Store PHI in any Google Cloud service, as long as default encryption is enabled.
- **D.** Sign Google's Business Associate Agreement, process PHI only in HIPAA-covered services, and implement the startup's own controls: least-privilege IAM, Data Access audit logging, encryption and key choices, and monitoring.

<details><summary>Answer</summary>

**Answer: D**

**Why (P6, P13):** Under shared responsibility, Google's certifications cover its side. The customer must sign the BAA, stay within covered services and operate its own controls.

- **A** — wrong: certifications don't transfer compliance to customer workloads.
- **B** — wrong: Google Cloud supports HIPAA workloads under a BAA.
- **C** — wrong: not every service is covered, and encryption alone isn't compliance.
- **D** — correct: the BAA, covered services and customer-side controls.

**Reference:** <https://cloud.google.com/security/compliance/hipaa>

</details>

### Q16 · Task 3.2 · Single answer

A payment processor wants to run fraud analytics in BigQuery on transaction data, and keep the analytics environment **out of** PCI DSS scope.

What should you recommend?

- **A.** Treat every system, including the analytics environment, as part of the cardholder data environment.
- **B.** Tokenize primary account numbers at capture, for example with a payment provider or Sensitive Data Protection format-preserving tokenization, so BigQuery holds only tokens, and isolate the remaining cardholder data environment in separate projects.
- **C.** Store the full card numbers in BigQuery encrypted with CMEK, and declare the environment out of scope.
- **D.** Mask card numbers only in Looker dashboards, while storing them in clear text in BigQuery.

<details><summary>Answer</summary>

**Answer: B**

**Why (P11, P7):** PCI scope follows cardholder data. If analytics never receives real PANs, it falls out of scope. Isolating what remains reduces audit surface.

- **A** — wrong: maximizes scope, cost and risk.
- **B** — correct: scope reduction through tokenization and segmentation.
- **C** — wrong: encrypted PANs in the environment keep it in scope.
- **D** — wrong: clear-text storage stays in scope, and masking only at display time is cosmetic.

**Reference:** <https://cloud.google.com/architecture/pci-dss-compliance-in-gcp>

</details>

### Q17 · Task 3.2 · Single answer

To meet EU data-protection obligations, a company must ensure that every resource holding EU customers' personal data is created only in EU locations. EU workloads live in a dedicated folder, and teams create projects there through self-service.

What should you do?

- **A.** Train the teams and ask them to choose EU regions.
- **B.** Create a VPC Service Controls perimeter around the EU folder's projects.
- **C.** Set the `gcp.resourceLocations` organization policy on the EU folder to allow only EU locations.
- **D.** Require a `region=eu` label on every resource.

<details><summary>Answer</summary>

**Answer: C**

**Why (P7, P10):** A resource-location constraint at the folder is inherited by every current and future project, and prevents non-EU resources from being created at all.

- **A** — wrong: guidance isn't enforcement.
- **B** — wrong: VPC SC controls data movement through APIs, not resource locations.
- **C** — correct: preventive, inherited residency control.
- **D** — wrong: labels are metadata, with no enforcement.

**Reference:** <https://cloud.google.com/resource-manager/docs/organization-policy/defining-locations>

</details>

### Q18 · Task 3.2 · Single answer

Regulators require a company to keep all Cloud Audit Logs from every project, including future projects, for 7 years in a form that can't be altered or deleted early. Logs are rarely read, and cost must be minimized.

What should you implement?

- **A.** An aggregated log sink at the organization that routes audit logs to a Cloud Storage bucket in Archive class, with a 7-year retention policy locked by Bucket Lock.
- **B.** A script that creates a separate sink in each project when the project is created.
- **C.** A 7-year retention period on the `_Default` log bucket in each project.
- **D.** A monthly Cloud Run job that exports the previous month's logs to a bucket.

<details><summary>Answer</summary>

**Answer: A**

**Why (P13, P10, P9):** One aggregated sink covers all current and future projects. A locked retention policy makes the logs immutable, and Archive class minimizes cost for rarely read data.

- **A** — correct: complete coverage, immutability and lowest cost.
- **B** — wrong: fragile per-project automation that's easy to miss.
- **C** — wrong: per-project settings that project owners can change, and Data Access and other logs may need central control.
- **D** — wrong: a batch export leaves gaps and is self-managed.

**Reference:** <https://cloud.google.com/logging/docs/export/aggregated_sinks>

</details>

### Q19 · Task 3.2 · Select TWO

A company is launching a learning app for children under 13 in the United States. Which two design decisions best address children's privacy requirements? (Select TWO.)

- **A.** Build behavioral advertising profiles from children's in-app activity.
- **B.** Collect full birth dates and precise location by default, in case they're useful later.
- **C.** Obtain verifiable parental consent before collecting personal information from a child.
- **D.** Retain children's data indefinitely for future analytics.
- **E.** Collect only the data the app needs, and enforce retention limits and deletion on request.

<details><summary>Answer</summary>

**Answer: C, E**

**Why (P10):** Children's-privacy rules center on parental consent, data minimization and limited retention.

- **A** — wrong: behavioral advertising to children is exactly what such rules restrict.
- **B** — wrong: violates minimization.
- **C** — correct: parental consent is a core requirement.
- **D** — wrong: violates retention limits.
- **E** — correct: minimization plus retention and deletion controls.

**Reference:** <https://www.ftc.gov/business-guidance/privacy-security/childrens-privacy>

</details>

### Q20 · Task 3.2 · Single answer

A national government agency requires that its workload data stays in-country, and that only personnel meeting citizenship and location criteria can provide support. The agency also needs continuous monitoring for violations of these controls.

What should you recommend?

- **A.** A `gcp.resourceLocations` organization policy on the agency's folder.
- **B.** A VPC Service Controls perimeter around the agency's projects.
- **C.** CMEK on all of the agency's resources.
- **D.** Assured Workloads with the compliance regime that matches the agency's requirements.

<details><summary>Answer</summary>

**Answer: D**

**Why (P7, P11):** Personnel-access restrictions, residency and violation monitoring for a named regime are what Assured Workloads adds beyond plain organization policies.

- **A** — wrong: covers residency only, not personnel controls or regime monitoring.
- **B** — wrong: an exfiltration control, with no residency or personnel guarantees.
- **C** — wrong: key control, not residency or support-personnel restrictions.
- **D** — correct: regime-based controls for data location, personnel and monitoring.

**Reference:** <https://cloud.google.com/assured-workloads/docs/overview>

</details>
