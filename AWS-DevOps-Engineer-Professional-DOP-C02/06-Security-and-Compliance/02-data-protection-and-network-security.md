# Domain 6 · 02 · Data Protection and Network Security Automation

> **Exam task:** 6.2 (network security components; certificates and PKI; data classification and encryption; automating controls across accounts and Regions; defense in depth; Macie; KMS, CloudHSM, ACM). **Principles:** P11 (encryption and keys), P13 (org-wide controls), P2 (guardrails).

## 1. First principles

1. **Encryption is easy; key access is the control.** Who can **use** the key (decrypt) is the real access boundary for encrypted data. A leaked snapshot encrypted with a key the attacker can't use is useless to them.
2. **Defense in depth means independent layers,** each of which would stop or detect the attack on its own: edge → network → host → identity → data → detection.
3. **Controls must apply to every account and Region automatically** (P13). An org-level mechanism beats per-account configuration.

---

## 2. AWS KMS

| Concept | Facts |
|---|---|
| **Key types** | **AWS owned** (invisible, used by services), **AWS managed** (`aws/s3`, `aws/ebs`, …: visible, policy not editable, **not usable cross-account**), **customer managed** (you control policy, rotation, grants, deletion) |
| **Key policy** | The primary control. The default policy has a statement that lets the account's **IAM policies** grant access; without it, IAM can't grant use of the key |
| **Grants** | Programmatic, delegable permissions (services like EBS and RDS use them); revocable |
| **Encryption context** | Non-secret key/value pairs bound to the ciphertext (additional authenticated data); logged in CloudTrail; usable in policy conditions |
| **Rotation** | Automatic rotation for symmetric customer-managed keys (period configurable, 1 year by default) plus **on-demand** rotation; old key material is kept for decryption, so there's nothing to re-encrypt |
| **Multi-Region keys** | Same key ID and material in several Regions. Decrypt in Region B what was encrypted in Region A (DR, global tables, cross-Region copies) |
| **Deletion** | Scheduled with a **7–30 day** waiting period; **disable** first to test impact. Deleting a key makes its data unrecoverable |
| **Custom key stores** | **CloudHSM-backed** (keys in your dedicated HSMs) or **external key store** (keys outside AWS) |
| **Envelope encryption** | KMS encrypts **data keys**; data is encrypted locally with the data key. That's why large objects work and why KMS request quotas matter (S3 **Bucket Keys** reduce KMS calls) |

**AWS CloudHSM:** single-tenant, FIPS 140-3 Level 3 validated HSMs in your VPC, in a cluster across AZs, where **you** exclusively control the keys (AWS can't access them). Choose it when "the company must have exclusive control of the HSM", or for custom key stores, SSL/TLS offload, Oracle TDE and PKCS#11 applications.

### 2.1 Encryption at rest, service by service

| Service | Key facts |
|---|---|
| **S3** | **SSE-S3 by default for all new objects** (since January 2023); SSE-KMS (+ Bucket Keys); DSSE-KMS (dual layer); SSE-C; client-side. Enforce KMS with default bucket encryption and/or a bucket policy that denies `PutObject` without the right `s3:x-amz-server-side-encryption` |
| **EBS** | **Encryption by default** is a per-Region account setting. To encrypt an existing unencrypted volume: snapshot → **copy the snapshot with encryption** → create a volume → swap |
| **RDS / Aurora** | Encryption is chosen **at creation**. To encrypt an existing database: snapshot → **copy with encryption** → **restore** a new instance → cut over. Read replicas use the same encryption state as the source |
| **DynamoDB** | Always encrypted; choose an AWS owned, AWS managed or customer-managed key |
| **EFS** | Encryption at rest is chosen at creation; in transit via the mount helper's TLS option |
| **CloudWatch Logs, SNS, SQS, Secrets Manager, Parameter Store SecureString** | KMS; customer-managed keys need key-policy permissions for the **service principals** that use them (see [05/01 §5](../05-Incident-and-Event-Response/01-event-sources-and-routing.md#5-encryption-gotcha-kms-encrypted-topics-and-queues)) |

### 2.2 Encryption in transit and certificates

* **AWS Certificate Manager (ACM):**
  * Free public certificates with **automatic renewal** (DNS validation recommended).
  * Certificates are **Regional**: an ALB or API Gateway uses a certificate from its own Region; **CloudFront requires the certificate in us-east-1**.
  * **Imported** certificates aren't renewed by ACM; monitor expiry via events or the Config rule `acm-certificate-expiration-check`.
* **AWS Private CA:** a private PKI for internal TLS and mTLS, issuing via ACM (auto-renewing private certificates) or directly.
* **Enforce TLS:**
  * a bucket policy denying `aws:SecureTransport = false`;
  * ALB HTTP → HTTPS redirect listener; CloudFront **viewer protocol policy** "Redirect HTTP to HTTPS";
  * TLS security policies with modern minimum versions;
  * RDS `rds.force_ssl` / `require_secure_transport`;
  * Config rules `alb-http-to-https-redirection-check`, `s3-bucket-ssl-requests-only`.

## 3. Data classification and discovery: Amazon Macie

* Discovers **sensitive data in S3** (PII, financial data, credentials) with managed and **custom data identifiers** (regex plus keywords), and evaluates **bucket security posture** (public, unencrypted, shared).
* **Automated sensitive data discovery** samples continuously across the estate; **sensitive data discovery jobs** run targeted scans.
* Org-wide through a **delegated administrator**; findings go to EventBridge and Security Hub, enabling automated response (e.g. tag the bucket, restrict access, notify the data owner).
* Classification also lives in **tags** (`data-classification=confidential`) that drive ABAC, backup and encryption policies.

## 4. Network security components

| Layer | Component | Facts |
|---|---|---|
| Edge | **AWS Shield Standard** | Automatic, free L3/L4 DDoS protection |
| | **AWS Shield Advanced** | Paid: enhanced detection, **Shield Response Team** access, **cost protection** for scaling during attacks, L7 protection with WAF, health-based detection, protection for EIPs, ELB, CloudFront, Global Accelerator, Route 53 |
| | **AWS WAF** | Web ACLs on CloudFront, ALB, API Gateway, AppSync, Cognito user pools, App Runner, Verified Access. **Managed rule groups** (core rule set, known bad inputs, SQL injection, IP reputation, **Bot Control**, account-takeover prevention), **rate-based rules**, geo match, custom rules; logging to CloudWatch Logs, S3 or Firehose |
| VPC | **Security groups** | **Stateful**, allow rules only, at the ENI; reference other security groups (tiered architectures) |
| | **Network ACLs** | **Stateless** (allow return traffic on ephemeral ports), numbered rules evaluated in order, **allow and deny**, at the subnet. "Block a specific malicious IP range" → NACL deny (or WAF for HTTP) |
| | **AWS Network Firewall** | Managed stateful/stateless firewall with Suricata-compatible rules, **domain allow/deny lists** (egress filtering), IPS; deployed in firewall subnets; centralized inspection VPC behind **Transit Gateway** |
| | **Route 53 Resolver DNS Firewall** | Block or allow DNS queries to domains (managed threat lists) from VPCs |
| | **VPC endpoints + endpoint policies** | Keep traffic to AWS services private (gateway endpoints for S3/DynamoDB; interface endpoints via PrivateLink); endpoint policies restrict which resources are reachable; `aws:SourceVpce` conditions in bucket policies |
| | **VPC Flow Logs** | Visibility (accept/reject); detection input for GuardDuty |
| Access | **AWS Verified Access**, Client VPN, Site-to-Site VPN, Session Manager | Zero-trust app access; remote users; on-premises links; shell access without inbound ports |

### 4.1 Automating network and edge controls org-wide: AWS Firewall Manager

* Requires Organizations and **AWS Config**, with a Firewall Manager **administrator account** (delegated).
* Centrally deploys and enforces across accounts and **new resources automatically**:
  * **WAF** web ACLs/rules (e.g. the core rule set on every ALB and CloudFront distribution);
  * **Shield Advanced** protections;
  * **security group** policies (common SGs, audit for overly permissive rules, unused SGs);
  * **Network Firewall** and **DNS Firewall** policies;
  * third-party firewalls.
* **The answer to:** "ensure every current and future ALB in all accounts has the WAF managed rules attached, with the least effort".

## 5. Automating security controls across accounts and Regions

| Mechanism | What it automates |
|---|---|
| **Security Hub (CSPM) central configuration** | Enable Security Hub and chosen **standards** (AWS Foundational Security Best Practices, CIS, PCI DSS, NIST 800-53) and controls in all accounts and Regions from the delegated admin, with **cross-Region aggregation** |
| **Control Tower controls** | Preventive (SCP/RCP), detective (Config) and proactive (Hooks) controls per OU |
| **Config conformance packs (org)** | Rules plus remediation everywhere |
| **Firewall Manager** | WAF, SG, Network Firewall, Shield, DNS Firewall policies |
| **SCPs / RCPs / declarative policies** | Organization-wide prevention (e.g. deny disabling EBS default encryption; deny unencrypted S3 uploads; require IMDSv2) |
| **Systems Manager** | Patch policies, State Manager, Automation runbooks across accounts and Regions |
| **StackSets** | Any baseline resource (KMS keys, alarms, roles) everywhere, including new accounts |

### 5.1 Defense in depth: an example stack

| Layer | Control |
|---|---|
| Edge | CloudFront + Shield (+ Advanced) + WAF managed rules and rate limiting; ACM TLS in us-east-1 |
| Load balancer | ALB in public subnets, HTTPS only, WAF; SG allowing 443 from the CloudFront managed prefix list only |
| Compute | Private subnets; SG allowing only the ALB's SG; no SSH (Session Manager); Inspector scanning; patching via SSM; IMDSv2 required |
| Data | RDS in isolated subnets, SG allowing only the app SG; KMS customer-managed key; Secrets Manager rotation; backups in a separate account with Vault Lock |
| Network | NACLs for coarse blocks; Network Firewall for egress domain filtering; VPC endpoints |
| Identity | Roles only; least privilege; boundaries; SCPs |
| Detection | GuardDuty, Security Hub, Config, CloudTrail org trail, Macie, Detective; automated response |

## 6. Exam traps

* **CloudFront certificate in the wrong Region:** it must be in **us-east-1**.
* **"Encrypt an existing RDS instance / EBS volume":** snapshot → **copy with encryption** → restore or create. You can't flip a switch on the running resource.
* **Security groups can't deny;** NACLs can. NACLs are stateless, so remember return traffic.
* **WAF protects HTTP(S) at L7;** Shield protects against DDoS; Network Firewall is VPC traffic inspection. Don't swap them.
* **"Exclusive control of the keys / the HSM"** → CloudHSM (or a CloudHSM-backed custom key store).
* **AWS-managed keys** can't be shared cross-account, and their policies can't be edited. That breaks SNS/SQS publishing from services and cross-account artifact access.

## References

* AWS KMS concepts — <https://docs.aws.amazon.com/kms/latest/developerguide/concepts.html>
* Key policies — <https://docs.aws.amazon.com/kms/latest/developerguide/key-policies.html>
* Multi-Region keys — <https://docs.aws.amazon.com/kms/latest/developerguide/multi-region-keys-overview.html>
* Rotating KMS keys — <https://docs.aws.amazon.com/kms/latest/developerguide/rotate-keys.html>
* AWS CloudHSM — <https://docs.aws.amazon.com/cloudhsm/latest/userguide/introduction.html>
* S3 default encryption — <https://docs.aws.amazon.com/AmazonS3/latest/userguide/default-encryption-faq.html>
* EBS encryption — <https://docs.aws.amazon.com/ebs/latest/userguide/ebs-encryption.html>
* Encrypting RDS resources — <https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/Overview.Encryption.html>
* ACM certificates with CloudFront (us-east-1) — <https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/cnames-and-https-requirements.html>
* Amazon Macie — <https://docs.aws.amazon.com/macie/latest/user/what-is-macie.html>
* AWS Firewall Manager — <https://docs.aws.amazon.com/waf/latest/developerguide/fms-chapter.html>
* AWS Network Firewall — <https://docs.aws.amazon.com/network-firewall/latest/developerguide/what-is-aws-network-firewall.html>
* Shield Advanced — <https://docs.aws.amazon.com/waf/latest/developerguide/shield-chapter.html>
* Security Hub central configuration — <https://docs.aws.amazon.com/securityhub/latest/userguide/central-configuration-intro.html>
