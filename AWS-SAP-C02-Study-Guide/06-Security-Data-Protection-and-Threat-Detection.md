# Chapter 06 — Security: Encryption, Secrets, Edge Protection, Detection & Compliance
> **Exam mapping:** D1 Task 1.2, D2 Task 2.3, D3 Task 3.2 | **Weight signal:** High | **Study time:** ~7 h
> [← Previous](05-Edge-DNS-and-Content-Delivery.md) · [Index](00-README-Start-Here.md) · [Next →](07-Compute-Containers-and-Serverless.md)

---

## Contents
1. [What the exam really tests here](#1-what-the-exam-really-tests-here)
2. [Core concepts & services — deep dive](#2-core-concepts--services--deep-dive)
   - 2.1 [AWS KMS](#21-aws-kms--the-centre-of-everything)
   - 2.2 [Encrypting existing resources & sharing encrypted snapshots](#22-encrypting-existing-resources--sharing-encrypted-snapshots)
   - 2.3 [AWS CloudHSM](#23-aws-cloudhsm)
   - 2.4 [Secrets Manager & SSM Parameter Store](#24-secrets-manager--ssm-parameter-store)
   - 2.5 [ACM & AWS Private CA](#25-aws-certificate-manager-acm--aws-private-ca)
   - 2.6 [S3 encryption & data in transit](#26-s3-encryption-choices-and-data-in-transit)
   - 2.7 [AWS WAF, Shield, Firewall Manager](#27-perimeter-aws-waf-shield-firewall-manager)
   - 2.8 [Detection: GuardDuty, Security Hub, Inspector, Macie, Detective, Security Lake](#28-detection-services)
   - 2.9 [AWS Config & CloudTrail](#29-aws-config-and-aws-cloudtrail)
   - 2.10 [Compliance & immutability](#210-compliance--immutability)
   - 2.11 [Data perimeter overview](#211-data-perimeter-overview)
3. [Architecture patterns](#3-architecture-patterns)
4. [Decision tables](#4-decision-tables--x-vs-y)
5. [Exam keyword → answer cheat list](#5-exam-keyword--answer-cheat-list)
6. [Traps & distractors](#6-traps--distractors)
7. [Professional architect focus](#7-professional-architect-focus)
8. [Skills checklist](#8-skills-checklist)
9. [Practice questions](#9-practice-questions)
10. [References](#10-references)

---

## 1. What the exam really tests here

Security is woven into almost every SAP-C02 question. Even a "migration" or "cost" stem often hides the deciding factor in a security constraint ("must remain encrypted with keys the company controls", "auditors require tamper-evident logs"). At Professional level you are rarely asked *what* a service does. You are asked to **pick the combination of controls that meets a constraint across many accounts and Regions with the least operational overhead**.

What you must be able to do:

| Skill | Typical scenario |
|---|---|
| **Design key management for multi-account and multi-Region** | Share an encrypted RDS snapshot with a DR account in another Region; let a central data lake account decrypt objects written by 200 producer accounts; let DynamoDB global tables use client-side encryption in two Regions. |
| **Choose the right key custody model** | KMS (AWS managed HSMs) vs CloudHSM (single tenant, you own the users) vs custom key store vs external key store (keys never inside AWS) vs imported key material. |
| **Know KMS authorization in depth** | The key policy is the primary control; IAM only works if the key policy lets it; grants; `kms:ViaService`; encryption context. Cross-account needs **both** sides. |
| **Fix "it's not encrypted" after the fact** | You cannot flip encryption on for an existing EBS volume or RDS instance: snapshot → encrypted copy → restore, or RDS blue/green. |
| **Pick a secrets store** | Secrets Manager (rotation, cross-account, multi-Region replicas) vs Parameter Store (cheap config, hierarchical). |
| **Protect the edge** | WAF managed rules / rate-based / Bot Control / Fraud Control (ATP, ACFP); Shield Advanced for DDoS response team (SRT) access and cost protection; Firewall Manager to enforce it across the organization. |
| **Detect and respond automatically** | GuardDuty → EventBridge → Step Functions / Lambda / SSM Automation; isolate EC2, snapshot for forensics, revoke credentials. Org-wide delegated administrator setup. |
| **Prove compliance** | Config rules + conformance packs + auto-remediation; Security Hub CSPM standards; CloudTrail org trail with integrity validation; WORM with S3 Object Lock / Backup Vault Lock. |

**Mindset:** the exam rewards **preventive** controls (SCP, key policy, bucket policy) over detective ones where both work, and **managed, org-wide, auto-enabled** solutions over per-account scripts. When the stem says "detect" use detective services; when it says "prevent" or "ensure" use guardrails.

---

## 2. Core concepts & services — deep dive

### 2.1 AWS KMS — the centre of everything

AWS KMS is a Regional, multi-tenant, managed key service. Key material is generated and used inside KMS hardware security modules (HSMs) validated at **FIPS 140-3 Security Level 3**. Plaintext key material for KMS keys never leaves the HSMs unencrypted. Every API call is logged in CloudTrail (except AWS owned keys, which you can't see).

#### Key ownership types

| Type | Who creates/manages | Visible in your account? | Key policy editable? | Rotation | Cost | Cross-account use |
|---|---|---|---|---|---|---|
| **AWS owned key** | The AWS service, shared across many accounts | No | No | Decided by the service | Free | N/A (transparent) |
| **AWS managed key** (`aws/s3`, `aws/ebs`, `aws/rds`…) | AWS on your behalf, one per service per Region | Yes | **No** | Automatic every year (fixed) | No monthly fee; API usage may be charged | **No.** You can't grant other accounts access, so snapshots encrypted with them **can't be shared** |
| **Customer managed key (CMK)** | You | Yes | **Yes** | Optional automatic (90–2,560 days, default 365) + on-demand | ~$1/month per key (+$1/month for each of the first two rotations, then capped); requests ~$0.03 per 10,000 symmetric (us-east-1 list) | **Yes**, through the key policy (plus IAM in the other account) |

> Exam reflex: "share across accounts", "control who can use the key", "disable the key to crypto-shred", "custom rotation" → **customer managed key**.

#### Key specs

| Spec | Use | Notes |
|---|---|---|
| **Symmetric** (`SYMMETRIC_DEFAULT`, AES-256-GCM) | Encrypt/decrypt, data keys, all AWS service integrations | The default and the only kind most services accept for encryption at rest. `Encrypt` takes **at most 4 KB** of plaintext, so anything bigger uses envelope encryption. |
| **Asymmetric RSA** | Encrypt/decrypt *or* sign/verify | Public key downloadable (`GetPublicKey`), so parties outside AWS can encrypt or verify without calling KMS. |
| **Asymmetric ECC** | Sign/verify, or key agreement (`DeriveSharedSecret`) | Code signing, JWT signing. |
| **ML-DSA** (post-quantum) | Sign/verify | *Emerging / SAP-C03 preview.* Not core for SAP-C02. |
| **HMAC** (224/256/384/512) | `GenerateMac`/`VerifyMac` | Tokens, message integrity; symmetric, so it shares the symmetric request quota. |

#### Envelope encryption & data keys

```text
 GenerateDataKey(KeyId)                    Decrypt(encrypted data key)
 ┌──────────┐  plaintext DK + encrypted DK  ┌──────────┐ plaintext DK
 │ AWS KMS  │ ────────────────────────────▶ │  Client  │ ◀────────── KMS
 └──────────┘                               └────┬─────┘
           1. encrypt data locally with plaintext DK (AES-GCM)
           2. discard plaintext DK from memory
           3. store ciphertext + encrypted DK together
```

- **Why:** KMS never sees your bulk data, there's no 4 KB limit, it's fast (local AES) and costs one KMS call per data key, not per byte.
- `GenerateDataKeyWithoutPlaintext` is for a component that stores the encrypted key now and decrypts it later (for example a producer that pre-provisions keys).
- **AWS Encryption SDK** implements envelope encryption, multi-keyring (encrypt under keys in several Regions) and **data key caching**, which cuts KMS calls and throttling.
- **Encryption context** = non-secret key/value pairs bound into the ciphertext as additional authenticated data (AAD). The same context must be supplied to decrypt. It is logged in CloudTrail and can be used in policy conditions (`kms:EncryptionContext:<key>`). S3 uses `aws:s3:arn`; EBS uses the volume ID; Secrets Manager uses the secret ARN.

#### Key policies: the root of authorization

- **Every KMS key has exactly one key policy** (max 32 KB). Unlike almost every other AWS resource, **IAM policies alone cannot grant access to a KMS key**. The key policy must allow it, either directly or by delegating to IAM.
- **Default key policy** (created by the API/CLI when you don't supply one) contains one statement:

```json
{
  "Sid": "Enable IAM User Permissions",
  "Effect": "Allow",
  "Principal": { "AWS": "arn:aws:iam::111122223333:root" },
  "Action": "kms:*",
  "Resource": "*"
}
```

- The `:root` principal here means **the account**, not the root user. It does two things: (1) it lets IAM policies in account 111122223333 grant KMS permissions on this key, and (2) it stops the key becoming unmanageable. If you remove it and no other admin statement exists, only AWS Support can help you recover the key.
- The console's default policy adds statements for **key administrators** (manage, not use) and **key users** (cryptographic operations and grant creation for AWS resources, `kms:GrantIsForAWSResource`).
- **Separation of duties:** admins can change the policy but can't encrypt/decrypt; users can use the key but can't change the policy.

**Authorization evaluation, in short:**

| Scenario | Required |
|---|---|
| Same account, key policy grants principal directly | Key policy alone is enough |
| Same account, key policy delegates to account (`:root`) | Key policy **and** an IAM policy allowing the action |
| **Cross-account** | Key policy in the owning account allows the external account or role **and** an IAM policy in the external account allows the principal to use that key ARN. An explicit deny anywhere (SCP, RCP, permission boundary, key policy) wins. |

Cross-account callers must reference the key by **key ARN or alias ARN**, not by a bare alias name. Cross-account requests count against the **caller's** request quota, not the key owner's.

#### Grants

- A grant is a delegation of a subset of permissions on one key to a grantee principal (for example `Decrypt`, `GenerateDataKey`, `CreateGrant`). It can be **constrained by encryption context** and has a **retiring principal**.
- **Used heavily by AWS services**: EBS, RDS, Redshift and others create grants so they can use your key in the background for the life of the resource. That is why key users need `kms:CreateGrant` with the condition `kms:GrantIsForAWSResource: true`.
- Grants are good for **temporary, programmatic, fine-grained** access without editing the key policy (which has a size limit and change control). Revoke with `RevokeGrant`/`RetireGrant`.
- Eventual consistency: a new grant can take a moment to propagate. Use the **grant token** returned by `CreateGrant` for immediate use.

#### Important condition keys

| Condition key | Use |
|---|---|
| `kms:ViaService` | Allow the key only when the request comes **through** a specific service in a specific Region, for example `s3.eu-west-1.amazonaws.com` or `rds.us-east-1.amazonaws.com`. Stops a principal calling `Decrypt` directly to pull data keys. |
| `kms:CallerAccount` | Combine with `kms:ViaService` to allow all principals in an account to use the key **only through** a given service. This is how AWS managed keys are scoped. |
| `kms:EncryptionContext:<k>` / `kms:EncryptionContextKeys` | Require or limit encryption context, for example a tenant ID for multi-tenant isolation with one key. |
| `kms:GrantIsForAWSResource` | Allow `CreateGrant` only when an integrated AWS service asks for it. |
| `kms:RotationPeriodInDays` | Restrict the rotation periods principals can set. |
| `aws:PrincipalOrgID` | In a key policy, allow every principal in your organization without listing accounts. |

#### Rotation

| Mechanism | Supported on | Details |
|---|---|---|
| **Automatic** | Symmetric customer managed keys with KMS-generated material (`AWS_KMS` origin) | Optional. Period **90–2,560 days, default 365**. Old material is kept forever, so old ciphertext still decrypts. **Key ID, ARN, aliases and policy don't change**, so no app changes. |
| **On-demand** (`RotateKeyOnDemand`) | Symmetric CMKs with `AWS_KMS` origin **and** symmetric keys with **imported** material | Immediate. **Up to 25 per key.** Doesn't change the automatic schedule. |
| **AWS managed keys** | — | Rotated **every year** automatically; you can't change it. |
| **Manual** | Asymmetric, HMAC and custom key store keys (no automatic or on-demand) | Create a new key and **repoint the alias**. Old key must be kept to decrypt old data. |

- Rotation does **not re-encrypt data** and does **not** rotate data keys. If a *data key* leaked, rotation doesn't help; re-encrypt the data.
- Multi-Region keys: enable or trigger rotation **on the primary**. KMS syncs material to replicas before any of them use it.

#### Imported key material (BYOK)

- Create a key with origin `EXTERNAL`, download a wrapping public key and import token (`GetParametersForImport`), wrap your material in your own HSM, then `ImportKeyMaterial`.
- **You are responsible for durability.** Keep a copy, because AWS can't regenerate it. You can **set an expiration** or **delete the material** (`DeleteImportedKeyMaterial`) for instant crypto-shredding, then reimport the **same** material to restore access.
- No automatic rotation. On-demand rotation is supported after you import new material.
- Use when policy says "keys must be generated in our HSM" but you still want native KMS integration and availability. If policy says keys must **never** be in AWS, use XKS.

#### Multi-Region keys (MRKs)

- A set of interoperable keys (a **primary** and **replicas**, key IDs begin `mrk-`) in different Regions with the **same key ID and key material**. Ciphertext from one can be decrypted by any related key **without a cross-Region call**.
- **Shared properties** (synced): key material, key spec, key usage, rotation. **Independent** (per Region): key policy, grants, aliases, tags, enabled state. Each replica is billed as a separate key.
- **They are not global keys.** Each is a Regional resource. You can promote a replica to primary (`UpdatePrimaryRegion`).
- **Use cases:** DR (decrypt backups or replicated data in the DR Region even if the source Region is down); **client-side encryption with DynamoDB global tables / S3 CRR** (encrypt in one Region, decrypt locally in another); active-active apps; **digital signing** in multiple Regions with one public key.
- **Not needed** for server-side encryption by AWS services. S3 CRR, Aurora global database and DynamoDB global tables **re-encrypt** with a key in the destination Region, and those services treat MRKs like single-Region keys. Prefer single-Region keys unless you need the interoperability: AWS says MRKs make it harder to keep data Regionally contained.
- MRKs **cannot** be created in custom key stores (CloudHSM or XKS).

#### Custom key stores

| | **AWS CloudHSM key store** | **External key store (XKS)** |
|---|---|---|
| Where the key material lives | In **your CloudHSM cluster** (single-tenant, in your VPC) | In **your external key manager outside AWS** (on premises or another cloud), behind an **XKS proxy** you run |
| Why | Regulation says keys must be in single-tenant HSMs you control; you want to see an audit trail in the HSM; you still want native KMS integration with S3, EBS, RDS and others | "Hold your own key" (HYOK) / digital sovereignty: keys must never be in AWS, and you must be able to **revoke AWS's access instantly** by disconnecting the proxy |
| Connectivity | KMS ↔ cluster managed by AWS (cluster needs **≥ 2 active HSMs in different AZs**) | Public endpoint over the internet, or **VPC endpoint service** (proxy in a VPC, or outside AWS with the VPC used only for connectivity) |
| Crypto | HSM performs the operation | **Double encryption**: KMS encrypts with KMS material, then your external key manager encrypts. Neither side alone can decrypt. |
| Who owns availability, latency, durability | **You** (cluster sizing, HSM count, backups) | **You** (proxy, network, external HSM). AWS warns availability and latency risk usually outweigh the benefit. Aim for < 35 ms round trip. |
| Request quota | **1,800 req/s per key store, not adjustable** (also counts against the account's symmetric quota) | 1,800 req/s per key store, not adjustable |
| Unsupported | Asymmetric, HMAC, imported material, automatic rotation, multi-Region keys | Same |
| Limit | Up to **10 custom key stores** per account per Region (both kinds combined) | |

#### Quotas and throttling

- **Symmetric cryptographic request quota is shared** across `Encrypt`, `Decrypt`, `GenerateDataKey*`, `ReEncrypt`, `GenerateMac`/`VerifyMac`, `GenerateRandom`. Current documented defaults per account per Region: **10,000 req/s**, **20,000** in some Regions (for example us-east-2, eu-central-1, ap-southeast-1), **100,000** in us-east-1, us-west-2 and eu-west-1. They're **adjustable** through Service Quotas. (Older material quotes 5,500/10,000/50,000; the numbers have grown, so treat any number as "check Service Quotas".)
- RSA and ECC operations have separate, much lower shared quotas (1,000 req/s by default).
- **Requests that AWS services make on your behalf count** (every SSE-KMS S3 PUT is a `GenerateDataKey`, every GET a `Decrypt`). **AWS owned keys don't count.**
- `ThrottlingException` fixes, in order: **S3 Bucket Keys**; **data key caching** (Encryption SDK); exponential backoff; **request a quota increase**; spread across accounts (quota is per account). Moving to a custom key store **lowers** your ceiling to 1,800 req/s.

#### Other KMS facts worth knowing

- **Key deletion**: `ScheduleKeyDeletion` with a 7–30 day waiting period (default 30). Deleting the key makes the data unrecoverable. Prefer **disable** first, and alarm on any `Decrypt` attempts during the waiting period.
- **Aliases** are per Region; repoint an alias for manual rotation. An alias can be used in policy conditions (`kms:RequestAlias`, `kms:ResourceAliases`).
- **VPC interface endpoint** for KMS (PrivateLink) keeps calls off the internet. Restrict with an endpoint policy and `aws:SourceVpce` in the key policy.
- **Resource quotas** (keys per account and so on) are separate from request quotas.

### 2.2 Encrypting existing resources & sharing encrypted snapshots

**You cannot enable encryption in place** on an existing unencrypted EBS volume or RDS instance, and you can't remove encryption once it's on.

| Resource | Encrypt an existing unencrypted resource | Change key | Gotchas |
|---|---|---|---|
| **EBS** | Snapshot → **copy snapshot with encryption** (or create a volume from the snapshot with `Encrypted=true`) → create volume → swap (stop instance, detach, attach). For a root volume: create AMI → copy AMI encrypted → launch. | Copy snapshot with new key | **EBS encryption by default** is a per-account, per-Region setting. Turn it on everywhere (automate across the org) so new volumes and snapshot copies are encrypted. |
| **RDS (non-Aurora)** | Manual snapshot → **copy snapshot with encryption + CMK** → **restore** new instance → cut over (downtime + data drift). For minimal downtime: **RDS blue/green deployment** to an encrypted green environment, or AWS DMS / native replication into an encrypted instance. | Same snapshot-copy approach, or blue/green | You can't have an encrypted read replica of an unencrypted instance (or the reverse). Cross-Region copies and replicas must name a **KMS key in the destination Region**. |
| **Aurora** | **Restore the unencrypted snapshot to a new cluster** (specify a KMS key; with no key it now gets the default AWS owned key), or use a **blue/green deployment** to an encrypted green cluster, or DMS / logical replication | Restore with the new key, or blue/green | **New Aurora clusters created on or after 18 Feb 2026 are encrypted at rest by default** (AWS owned key). Clusters created earlier without encryption stay unencrypted, along with their clones, replicas and snapshots. Choose a **CMK** if you'll ever share snapshots cross-account or need key control. |
| **DynamoDB** | Always encrypted at rest. You can switch between AWS owned, AWS managed and customer managed keys **in place**. | In place | — |
| **S3** | Since Jan 2023 all new objects are encrypted with SSE-S3 by default. To re-encrypt existing objects with SSE-KMS use **S3 Batch Operations** (copy in place) | Batch copy | Changing default encryption doesn't re-encrypt existing objects |
| **EFS** | Encryption at rest is chosen at creation. To encrypt, create a new encrypted file system and copy (DataSync). | — | — |

#### Sharing encrypted snapshots cross-account (and cross-Region)

```text
 Source account (A)                                Target account (B), Region 2
 ┌─────────────────────────────────────┐          ┌──────────────────────────────────┐
 │ RDS/EBS encrypted with aws/rds  ✗   │          │                                  │
 │   │ 1. copy snapshot, re-encrypt    │          │                                  │
 │   ▼    with CMK-A                   │          │                                  │
 │ snapshot (CMK-A)                    │ 3.share  │ 4. copy shared snapshot,         │
 │ 2. key policy CMK-A: allow acct B   │ ───────▶ │    re-encrypt with CMK-B         │
 │    kms:Decrypt, DescribeKey,        │          │    (own key, own Region)         │
 │    CreateGrant, ReEncrypt*          │          │ 5. restore / create volume       │
 └─────────────────────────────────────┘          └──────────────────────────────────┘
```

Rules to memorize:
1. **Snapshots encrypted with an AWS managed key can't be shared**, because you can't edit that key's policy. Re-encrypt with a **customer managed key** first.
2. The key policy must allow the target account; the target account's IAM must allow its principals to use that key ARN.
3. The target should **copy** the shared snapshot and **re-encrypt with its own key**. Otherwise its restored resource depends on the source account's key, and disabling that key would break it.
4. Cross-Region copy: always specify a destination-Region key (KMS keys are Regional, unless you're using MRKs).
5. AWS Backup cross-account / cross-Region copy follows the same rules: the source vault key must be a CMK shared with the destination, and the destination vault re-encrypts with its own key.

### 2.3 AWS CloudHSM

- **What:** dedicated, **single-tenant** HSMs in a **cluster** inside a VPC that AWS manages (ENIs placed in your subnets). AWS handles hardware, firmware, patching and backups. **You** own HSM users (crypto officer / crypto user), keys and access. **AWS has no access to your keys.** If you lose all credentials, the keys are gone.
- **Compliance:** current `hsm2m.medium` HSMs are **FIPS 140-3 Level 3** validated. The older `hsm1.medium` (FIPS 140-2 L3) reached end of life on 1 December 2025. Exam stems may still say "FIPS 140-2 Level 3"; both point to CloudHSM if the stem also needs single-tenancy or customer-exclusive control. KMS's own HSMs are also FIPS 140-3 L3, so **"FIPS validated" alone doesn't decide it**. **Single-tenant / customer-only access / industry-standard APIs** does.
- **APIs:** PKCS#11, Java JCE, Microsoft CNG/KSP, OpenSSL Dynamic Engine. Apps call the HSM directly, unlike KMS's AWS API.
- **HA:** spread HSMs across **at least 2 AZs**. The client load-balances and keys sync across HSMs in the cluster. Automatic backups (encrypted) can be **copied cross-Region** to build a DR cluster.
- **Pricing:** hourly per HSM, no upfront cost. Two HSMs in production is a material monthly cost, versus about $1/month per KMS key.
- **Classic use cases:**
  - **SSL/TLS offload**: private keys for NGINX/Apache/IIS kept in the HSM.
  - **Oracle TDE** master key for self-managed Oracle on EC2.
  - **Windows Server CA** private key, **code signing**, PKI root.
  - **Asymmetric key operations or algorithms KMS doesn't support**, very high throughput crypto, or keys exportable under your control.
  - **Backing a KMS custom key store** so S3/EBS/RDS can use HSM-held keys.

### 2.4 Secrets Manager & SSM Parameter Store

#### AWS Secrets Manager
- Stores secrets (up to 64 KB), always **encrypted with KMS** (`aws/secretsmanager` or a CMK). Versioning with **staging labels** `AWSCURRENT`, `AWSPENDING`, `AWSPREVIOUS`.
- **Rotation:**
  - **Managed rotation** for some services (for example RDS / Aurora master passwords that RDS manages in Secrets Manager), with no Lambda to maintain.
  - **Lambda rotation functions** (AWS-provided templates for RDS, Aurora, Redshift, DocumentDB, or custom code for anything, such as API keys). Steps: `createSecret` → `setSecret` → `testSecret` → `finishSecret`.
  - Strategies: **single user** (simpler; brief window where connections can fail) vs **alternating users** (two users, zero-downtime).
  - The rotation Lambda needs **network reach** to the database (in-VPC) **and** to the Secrets Manager endpoint (VPC interface endpoint or NAT). A common exam failure cause.
  - Schedules from **every 4 hours** up to the frequency you choose (rate or cron).
- **Cross-account access:** attach a **resource-based policy** to the secret allowing the other account's role, **and** encrypt the secret with a **customer managed key** whose key policy allows that account `kms:Decrypt`. The consumer also needs IAM permissions. **The AWS managed key `aws/secretsmanager` can't be used cross-account.** Block public sharing with `BlockPublicPolicy` validation.
- **Multi-Region replica secrets:** replicate a secret to other Regions (kept in sync, including rotation). For DR, **promote** a replica to a standalone secret. Each replica is billed as a secret. Use an MRK or per-Region CMKs for encryption.
- **Integrations:** RDS/Aurora/Redshift native integration, ECS/EKS (Secrets Store CSI driver), Lambda extension for caching, CloudFormation dynamic references (`{{resolve:secretsmanager:...}}`), CodeBuild.
- **Pricing:** about **$0.40 per secret per month** + **$0.05 per 10,000 API calls**. Replicas count as secrets.

#### SSM Parameter Store
- Hierarchical key/value store (`/prod/app/db-url`). Types: `String`, `StringList`, **`SecureString`** (KMS-encrypted).
- **Standard tier:** free, up to 10,000 parameters, **4 KB** values, no parameter policies.
- **Advanced tier:** up to 100,000 parameters, **8 KB** values, **parameter policies** (expiration, expiration notification, no-change notification), **sharing with other accounts through AWS RAM**, about $0.05 per advanced parameter per month.
- **Throughput:** standard throughput by default. Higher throughput is configurable for a per-API-interaction charge.
- **No built-in rotation.** You'd build it with EventBridge + Lambda.
- Can **reference Secrets Manager secrets** via `/aws/reference/secretsmanager/<secret-name>`, so apps use one API.
- Typical use: config values, AMI IDs, feature flags, non-rotating secrets on a budget. CloudFormation dynamic references `{{resolve:ssm:...}}` / `{{resolve:ssm-secure:...}}`.

### 2.5 AWS Certificate Manager (ACM) & AWS Private CA

- **Public certificates** from ACM are **free** when used with **integrated services**: ELB (ALB/NLB/CLB), CloudFront, API Gateway, App Runner, Elastic Beanstalk (via ELB) and others. DNS or email validation. **DNS validation** (CNAME) gives fully automatic **managed renewal**.
- **Regional:** a certificate lives in one Region. **CloudFront requires the certificate in `us-east-1`** (as do edge-optimized API Gateway endpoints, since they use CloudFront). Regional ALBs and API Gateway Regional endpoints need a certificate **in their own Region**, so a multi-Region app needs one certificate per Region.
- **Validity and renewal (changed 2026):** from 18 Feb 2026, new and renewed ACM public certificates are valid for **198 days** (previously 395), in line with the CA/Browser Forum's 200-day maximum from 15 Mar 2026. ACM renews managed certificates automatically (about 45 days before expiry for the new validity). Shorter lifetimes make **automated renewal mandatory in practice**, which strengthens the "use ACM-integrated endpoints" answer.
- **Exportable public certificates (since June 2025):** ACM can now issue **exportable** public certificates (private key exported, protected by a passphrase) for use anywhere, such as EC2 web servers, containers or on-prem. They're **paid per FQDN / wildcard at issuance and renewal** (reduced in Feb 2026 to about $7 per FQDN and $79 per wildcard for 198-day certs). Older exam material says "you cannot export ACM public certificates": that was true for standard certificates and **still is** (you can't export a non-exportable public certificate). Exportability must be chosen **at request time**. If an older-style question insists on a cert *on EC2* with no ALB, the classic answers were an imported third-party cert or putting an ALB/CloudFront in front. Today, an exportable ACM public certificate is also valid.
- **Imported certificates** (third-party CA): supported in integrated services, but **ACM does not renew them**. Monitor with the `DaysToExpiry` CloudWatch metric, EventBridge expiry events, or the Config rule `acm-certificate-expiration-check`.
- **AWS Private CA:** managed private certificate authority hierarchy (root/subordinate) for internal TLS, mTLS, IoT, service mesh and code signing. **Private certificates are exportable.** Share a CA cross-account with **AWS RAM**. Priced per CA per month (general-purpose mode is significantly more expensive than short-lived certificate mode) plus per certificate. Use it for "issue certificates to internal services / devices", "mTLS between microservices", or "private hosted zone names".

### 2.6 S3 encryption choices and data in transit

| Option | Who manages key | Audit of key use | Notes |
|---|---|---|---|
| **SSE-S3** (AES-256, S3-managed) | S3 | No KMS CloudTrail events | **Default for all new objects since Jan 2023.** No extra cost. |
| **SSE-KMS** | KMS (AWS managed `aws/s3` or CMK) | Every key use in CloudTrail | Separation of duties: the reader needs `s3:GetObject` **and** `kms:Decrypt`. Cross-account requires a CMK. Subject to KMS quotas and costs, which **S3 Bucket Keys** fix. |
| **DSSE-KMS** | KMS | Yes | **Dual-layer** server-side encryption for standards that require two independent layers (for example CNSSP 15). Higher cost. **Bucket Keys aren't supported.** |
| **SSE-C** | **You** supply the key with every request (HTTPS only) | S3 stores only a salted HMAC of the key | **Since April 2026, SSE-C is disabled by default on new general purpose buckets** (and on existing buckets in accounts with no SSE-C objects). Re-enable per bucket via `BlockedEncryptionTypes`. Lose the key and you lose the data. |
| **Client-side** | You (often with KMS + Encryption SDK) | Depends | S3 never sees plaintext. Required when "data must be encrypted before leaving the corporate network / application". |

**S3 Bucket Keys:** S3 gets a short-lived **bucket-level key** from KMS and derives per-object data keys from it locally. This cuts KMS requests (and costs) by **up to 99%** and removes throttling risk. Side effects: the CloudTrail encryption context becomes the **bucket ARN** rather than the object ARN, so key policies or conditions keyed on object ARN need updating. Enable it on the bucket default encryption setting; copy objects to apply it to existing data.

**Enforcing encryption with bucket policies.** Now that SSE-S3 is the default, "ensure every object is encrypted" is automatically true. Exam stems therefore ask for **"ensure SSE-KMS with a specific key"**:
1. Set **default encryption = SSE-KMS with CMK X (+ Bucket Key)**, so uploads without headers get CMK X automatically.
2. Add a bucket policy **denying `s3:PutObject` when `s3:x-amz-server-side-encryption` is present and not `aws:kms`**, or when `s3:x-amz-server-side-encryption-aws-kms-key-id` is not CMK X. Denying when the header is *absent* (a `Null` condition) also works but forces every client to send headers, overriding the convenience of default encryption.
3. Optionally deny SSE-C via `BlockedEncryptionTypes`.

**Data in transit:**
- Enforce TLS on S3 with a bucket policy: `Deny` all `s3:*` when `"Bool": {"aws:SecureTransport": "false"}`. Set a minimum version with `s3:TlsVersion` (`NumericLessThan 1.2`).
- The same `aws:SecureTransport` pattern applies to SNS topics, SQS queues and other resource policies.
- **ALB/NLB/CloudFront TLS policies** control protocol and ciphers. CloudFront viewer protocol policy `redirect-to-https` / `https-only`, and origin protocol policy `https-only` for end-to-end encryption.
- **RDS:** `rds.force_ssl=1` (PostgreSQL/SQL Server) or `require_secure_transport=ON` (MySQL/MariaDB).
- **Inter-node/physical:** AWS encrypts traffic between AZs and across Regions on the AWS backbone, and Nitro instances can encrypt instance-to-instance traffic automatically. "Must encrypt in transit inside the VPC" still often means TLS at the application level, or **VPC Lattice / service mesh mTLS**.
- **Hybrid:** Site-to-Site VPN (IPsec), or **Direct Connect + MACsec** (dedicated 10/100 Gbps at supported locations) or VPN over DX for encryption on the private link. See [Chapter 04](04-Networking-VPC-and-Hybrid-Connectivity.md).

### 2.7 Perimeter: AWS WAF, Shield, Firewall Manager

#### AWS WAF
- A Layer 7 web application firewall. A **web ACL** holds ordered **rules** and **rule groups**, each with an action: **Allow, Block, Count, CAPTCHA, Challenge**. Custom responses and request header insertion are supported.
- **Where you attach it:** CloudFront (global scope, managed from us-east-1), **ALB**, **API Gateway REST APIs**, AppSync GraphQL, Cognito user pools, App Runner, Verified Access, Amplify. **Not** NLB, and **not** directly on EC2. For L3/L4 filtering use security groups, NACLs or Network Firewall.
- **Capacity:** rules consume WCUs (web ACL capacity units). The base web ACL allowance is **1,500 WCUs**; more (up to 5,000) incurs extra fees.
- **Statement types:** IP sets (IPv4/IPv6 CIDRs, up to 10,000 addresses per set), geo match, regex pattern sets, string/size/SQLi/XSS match, label match (rules can add labels that later rules evaluate), scope-down statements.
- **Managed rule groups:**
  - *AWS Managed Rules baseline:* Core rule set (OWASP-style), Known bad inputs, SQL database, Linux/Windows/POSIX OS, PHP, WordPress, **Amazon IP reputation list**, **Anonymous IP list** (VPNs, Tor, hosting providers).
  - *Marketplace* rule groups from security vendors.
  - Override individual rule actions to **Count** for testing before enforcing.
- **Rate-based rules:** count requests per aggregation key (source IP, forwarded IP header, or **custom keys** such as header, cookie, query arg, label, HTTP method, URI path, JA3/JA4 fingerprint) over an **evaluation window of 1, 2, 5 (default) or 10 minutes**. **Minimum limit 10 requests.** Action can be anything except Allow. Use a scope-down statement to rate-limit only `/login` or `/api/*`.
- **Intelligent threat mitigation (extra cost):**
  - **Bot Control**: *Common* level (self-identifying bots, verified good bots such as search engines, categories) and *Targeted* level (sophisticated bots via browser interrogation, fingerprinting, client tokens, ML).
  - **Fraud Control: Account Takeover Prevention (ATP)**: protects the **login** endpoint. Checks submitted credentials against a stolen-credential database, detects volumetric and distributed credential stuffing, and on CloudFront can **inspect responses** to count failed logins.
  - **Fraud Control: Account Creation Fraud Prevention (ACFP)**: protects the **sign-up** endpoint against fake or bulk account creation.
  - **Anti-DDoS managed rule group**: Layer 7 DDoS mitigation inside WAF.
  - The **client application integration SDKs** (JavaScript and mobile) acquire tokens up front, which makes CAPTCHA/Challenge and the targeted protections more accurate.
- **Logging:** full logs to **CloudWatch Logs, S3, or Data Firehose** (destination name must start with `aws-waf-logs-`), with field redaction and log filtering. **Sampled requests** and CloudWatch metrics per rule are available without logging enabled.
- **Pricing:** per web ACL per month, per rule per month, per million requests, plus intelligent threat mitigation fees.

#### AWS Shield Standard vs Shield Advanced

| | **Shield Standard** | **Shield Advanced** |
|---|---|---|
| Cost | Free, automatic for every customer | **$3,000/month per organization (payer)**, **1-year commitment**, plus data transfer out usage fees for protected resources |
| Protection | Common L3/L4 attacks (SYN/UDP floods, reflection), strongest on CloudFront, Route 53, Global Accelerator | Enhanced detection and mitigation for **CloudFront, Route 53 hosted zones, Global Accelerator, ALB, CLB, EC2 Elastic IPs** (which also covers NLBs and EC2 behind EIPs) |
| L7 | — | **Automatic application-layer DDoS mitigation**: Shield creates and manages WAF rules in the associated web ACL |
| People | — | **Shield Response Team (SRT)**, 24/7, formerly the DRT. **Requires a Business or Enterprise Support plan** (or the newer support tiers that include it). You can authorize SRT (via an IAM role) to deploy WAF mitigations on your behalf. |
| **Proactive engagement** | — | SRT contacts **you** when a **Route 53 health check** associated with a protected resource becomes unhealthy during an event (health-based detection is a prerequisite) |
| **Cost protection** | — | Service credits for scaling charges (CloudFront, ELB, EC2, Route 53, Global Accelerator) caused by a DDoS attack on protected resources |
| WAF | Paid separately | **WAF fees for protected resources are included** (up to 50 billion requests/month at the default 1,500 WCU; Bot/Fraud Control and Marketplace rules still billed) |
| Visibility | — | Attack diagnostics, CloudWatch metrics, global threat dashboard, **protection groups** |

> Exam reflex: "24/7 access to AWS DDoS experts", "reimbursement for scaling costs during an attack", "proactive notification" → **Shield Advanced**. "Protect an NLB / EC2 from DDoS" → Shield Advanced on the **Elastic IP**.

#### AWS Firewall Manager (FMS)
- Central, **organization-wide** policy enforcement. You define a policy once and FMS applies it to all in-scope accounts and resources (by account, OU or **tag**), **including new accounts and resources** as they appear, with optional auto-remediation.
- **Policy types:** **AWS WAF** (web ACLs with first/last rule groups that account owners can't remove, so accounts can still add their own rules in between), **Shield Advanced** (subscribe accounts, protect resources, enable automatic L7 mitigation), **VPC security groups** (common SG policy, content audit, **usage audit** to clean up unused or redundant SGs), **network ACLs**, **AWS Network Firewall** (deploy firewalls and policies in VPCs, distributed or centralized), **Route 53 Resolver DNS Firewall**, and **third-party firewalls** (Palo Alto Cloud NGFW, Fortinet FortiGate CNF).
- **Prerequisites (classic exam item):**
  1. **AWS Organizations with all features enabled.**
  2. A **Firewall Manager administrator account** designated from the management account (a delegated account, which can also be scoped).
  3. **AWS Config enabled** (recording the relevant resource types) in **every member account and Region** you want to protect.
  4. For Shield Advanced policies, a Shield Advanced subscription.
- Pricing: a monthly fee per policy per Region, plus the underlying WAF, Config, Network Firewall and Shield charges.
- Findings and compliance status can flow to **Security Hub CSPM**.

### 2.8 Detection services

#### Amazon GuardDuty: managed threat detection
- **Foundational data sources** are analysed without you enabling or storing them: **CloudTrail management events**, **VPC Flow Logs**, **Route 53 Resolver DNS query logs**. GuardDuty reads independent streams, so there's no performance impact and no need to turn on flow logs yourself. It uses threat intel, anomaly ML and attack-pattern detection.
- **Protection plans** (optional, each billed):

| Plan | What it watches |
|---|---|
| **S3 Protection** | CloudTrail S3 **data events** (suspicious access, exfiltration, disabling of logging) |
| **EKS Protection** | EKS **audit logs** (control-plane activity) |
| **Runtime Monitoring** | OS-level process, file and network behaviour via a managed agent, for **EKS**, **ECS (Fargate and EC2)** and **EC2** |
| **Malware Protection for EC2** | **Agentless** scan of EBS volume snapshots, triggered by a GuardDuty finding or on demand |
| **Malware Protection for S3** | Scans **newly uploaded objects** in chosen buckets and tags them. **Can be used without enabling GuardDuty** (for example a file upload pipeline). |
| **RDS Protection** | Anomalous **login activity** on Aurora (and supported RDS engines) |
| **Lambda Protection** | Network activity of Lambda functions (for example crypto-mining callbacks) |
| **AI Protection** | Bedrock / SageMaker AI data events (anomalous model invocation, prompt injection). *Emerging.* |

- **Extended Threat Detection:** **on by default, no extra cost.** It correlates signals over a 24-hour rolling window into a single **Critical** "attack sequence" finding, for example `AttackSequence:IAM/CompromisedCredentials`, `AttackSequence:S3/CompromisedData`, `AttackSequence:EKS/CompromisedCluster`, `AttackSequence:ECS/CompromisedCluster`, `AttackSequence:EC2/CompromisedInstanceGroup`. More protection plans enabled means more sequence types detected.
- **Multi-account:** designate a **delegated administrator** (usually the Security Tooling account) from the management account. **Auto-enable** for all existing and new member accounts and chosen protection plans. **GuardDuty is Regional**, so enable it in **every Region** (including unused ones, to spot an attacker spinning up resources there), typically via the delegated admin or Control Tower / CloudFormation StackSets.
- **Operations:** findings go to **EventBridge** automatically (in each Region), Security Hub, and optionally an S3 export (KMS-encrypted). Use **suppression rules** to auto-archive expected findings, **trusted IP lists** and **threat lists**. There's a 30-day free trial per account. Pricing is based on events and GB analysed.
- **Key point:** GuardDuty **detects**. It does not block. Response comes through EventBridge automation (Pattern 3).

#### AWS Security Hub CSPM (formerly "Security Hub") and the new AWS Security Hub
- **Naming (2025):** the original service was renamed **AWS Security Hub CSPM** (cloud security posture management). A **new AWS Security Hub** (GA Dec 2025) sits on top of it and correlates GuardDuty, Inspector, Macie, IAM Access Analyzer and CSPM signals into prioritized **exposure findings** with an **attack path graph**, using **OCSF** format and Jira / ServiceNow ticketing integration. Exam questions written for SAP-C02 mean what is now **Security Hub CSPM**.
- **What CSPM does:**
  - Runs **automated control checks** (implemented through **AWS Config rules, so AWS Config must be recording**) against **standards**: **AWS Foundational Security Best Practices (FSBP)**, **CIS AWS Foundations Benchmark** (several versions), **PCI DSS**, **NIST SP 800-53 Rev. 5**, **NIST SP 800-171 Rev. 2**, AWS Resource Tagging, the AI Security Best Practices standard, CRI Profile, and service-managed standards (Control Tower).
  - **Aggregates findings** in AWS Security Finding Format (**ASFF**) from GuardDuty, Inspector, Macie, Firewall Manager, IAM Access Analyzer, Config, Health and many partner tools.
  - Produces a **security score** per standard.
- **Multi-account / multi-Region:** delegated administrator + **central configuration** (configuration policies that enable Security Hub, standards and controls across accounts, OUs and Regions from one place). **Cross-Region aggregation** links Regions to a **home (aggregation) Region**, giving one pane of glass.
- **Automation:**
  - **Automation rules**: update or suppress findings automatically, for example raise severity when the resource is tagged `prod`, or set workflow status to SUPPRESSED for a known exception.
  - **EventBridge**: every new or updated finding is emitted as a `Security Hub Findings - Imported` event. **Custom actions** send selected findings to EventBridge on demand.
  - The AWS solution "Automated Security Response on AWS" provides ready-made playbooks using Step Functions and SSM Automation.
- **Consolidated control findings**: one finding per control even if several standards include it. Turn it on to reduce noise.

#### Amazon Inspector: vulnerability management
- **Continuous, automated** scanning for software vulnerabilities (CVEs) and unintended network exposure:
  - **EC2**: agent-based via the **SSM Agent**, or **agentless** (EBS snapshot) in hybrid mode. Package CVEs plus **network reachability** findings.
  - **ECR container images**: **enhanced scanning** (on push and continuously re-evaluated as new CVEs appear). This replaces ECR "basic" scanning.
  - **Lambda**: *standard* scanning (package dependencies) and *code* scanning (code vulnerabilities such as injection, hard-coded secrets).
  - **CIS Benchmark assessments** for EC2 operating systems (on demand or scheduled).
  - **Code security** (2025): SAST, SCA and IaC scanning of connected source repositories. *Emerging.*
- An **Inspector risk score** adjusts CVSS with network reachability and exploitability. Export an **SBOM** (CycloneDX/SPDX). Findings go to Security Hub and EventBridge. Delegated administrator with org-wide auto-enable.
- Exam reflex: "find CVEs / unpatched software in EC2, containers, Lambda" → **Inspector**, then remediate with **SSM Patch Manager** or a pipeline rebuild.

#### Amazon Macie: sensitive data discovery in S3
- **S3 only.** Uses **managed data identifiers** (PII, financial, credentials, health data) and **custom data identifiers** (regex + keywords), with **allow lists** for false positives.
- **Automated sensitive data discovery** samples objects across the estate continuously and cheaply. **Sensitive data discovery jobs** do targeted, scheduled or one-time full scans.
- Also produces **policy findings** about bucket posture: public, unencrypted, shared externally.
- Findings go to EventBridge and Security Hub. Detailed discovery results are written to an S3 bucket (KMS-encrypted). Delegated administrator for the organization.
- Exam reflex: "identify buckets containing PII / credit card numbers" → **Macie**. Macie does **not** scan RDS, DynamoDB or EBS. For that, export to S3 first or use other tools.

#### Amazon Detective: investigation
- Builds a **behaviour graph** from CloudTrail, VPC Flow Logs, **GuardDuty findings**, EKS audit logs and Security Hub findings. It keeps up to a year of aggregated history and visualizes entity behaviour (IP, role, user, instance) and **finding groups** that cluster related findings.
- Used **after** a finding, to answer "what else did this principal or IP do, and when did it start?" (root-cause analysis). Requires GuardDuty to be enabled. Delegated administrator for the organization.

#### Amazon Security Lake
- A **security data lake** in **your account's S3**, managed by AWS. It normalizes logs into **OCSF** (Open Cybersecurity Schema Framework) in **Apache Parquet**.
- **Sources:** CloudTrail management and data events, VPC Flow Logs, Route 53 Resolver query logs, Security Hub findings, EKS audit logs, WAF logs, plus custom and third-party sources.
- **Rollup Regions** consolidate data. **Subscribers** (SIEMs, Athena/OpenSearch, partners) get **data access** (S3 / notifications) or **query access** (Lake Formation-shared tables). Delegated administrator for the organization.
- Exam reflex: "centralize security logs from all accounts and Regions in an open, normalized format for a third-party SIEM / long-term analytics" → **Security Lake**.

### 2.9 AWS Config and AWS CloudTrail

#### AWS Config
- **Configuration recorder** captures configuration items (CIs) and relationships for supported resource types, giving a **configuration timeline** ("what did this security group look like last Tuesday, and who changed it?", linked to CloudTrail). Recording can be **continuous or periodic (daily)**; periodic lowers cost for noisy resource types.
- **Rules:**
  - **AWS managed rules** (hundreds, for example `encrypted-volumes`, `s3-bucket-ssl-requests-only`, `restricted-ssh`, `cloudtrail-enabled`, `rds-storage-encrypted`, `acm-certificate-expiration-check`).
  - **Custom Lambda rules** and **custom policy rules** written in **CloudFormation Guard**.
  - Triggers: **configuration change** and/or **periodic**.
  - **Proactive** evaluation mode checks resource configurations *before* deployment for supported rules.
- **Remediation:** associate an **SSM Automation runbook** (AWS-provided, for example `AWS-DisableS3BucketPublicReadWrite` or `AWS-EnableS3BucketEncryption`, or your own). Run it **manually or automatically**, with retries. Runbooks assume an IAM role.
- **Conformance packs:** YAML bundles of rules + remediations (sample packs map to CIS, PCI DSS, HIPAA, NIST and others) deployed per account or as **organization conformance packs** from the management or delegated admin account. **This is AWS's suggested replacement for Audit Manager evidence collection.**
- **Aggregators:** collect compliance and configuration data from **multiple accounts and Regions** (or the whole organization) into one aggregator account. **Read-only**: aggregators don't deploy rules. **Advanced queries** (SQL-like) work across the aggregator.
- **Organization Config rules** deploy a rule to every account from a delegated admin.
- Config is a **prerequisite** for Security Hub CSPM controls and Firewall Manager. Control Tower uses it for detective controls.
- Pricing: per configuration item recorded + per rule evaluation + per conformance pack evaluation.

#### AWS CloudTrail

| Event type | What | Default | Cost |
|---|---|---|---|
| **Management events** | Control-plane API calls (CreateBucket, RunInstances, PutKeyPolicy, ConsoleLogin…), read and write | **Event history keeps 90 days** of management events in each Region automatically, viewable and searchable | Event history is free. The first copy of management events delivered to S3 by a trail is free; additional copies are charged. |
| **Data events** | Data-plane, high volume: S3 object-level (`GetObject`/`PutObject`), Lambda `Invoke`, DynamoDB item operations, and more | **Off.** Enable per trail with (advanced) event selectors and filter by resource ARN, event name and so on. | Per 100,000 events |
| **Network activity events** | API calls **made through VPC endpoints** to supported services (S3, KMS, EC2, Secrets Manager, CloudTrail, STS, DynamoDB, Lambda…), including **`VpceAccessDenied`** when an endpoint policy blocks a call. Lets the endpoint owner see, for example, outside credentials trying to use their endpoint. | **Off** | Charged |
| **Insights events** | Anomalies in **API call rate** or **error rate** on write management events (for example a sudden burst of `TerminateInstances` or AccessDenied) | Off | Charged |

- **Trails:** a multi-Region trail (recommended) delivers to S3, optionally to CloudWatch Logs (metric filters and alarms, such as the CIS root-login alarm) and EventBridge.
- **Organization trail:** created in the **management account** (or a CloudTrail **delegated administrator**). It logs every member account; members can see it but **can't modify or delete it**. The usual destination is an S3 bucket in the **Log Archive** account, with prefixes per account ID.
- **Log file integrity validation:** CloudTrail writes an hourly **digest file** that holds SHA-256 hashes of every log file, signed with **SHA-256 with RSA**. Validate with `aws cloudtrail validate-logs`. This **proves** whether logs were modified or deleted (tamper-*evident*). For tamper-*proof*, add **S3 Object Lock (compliance)**, a bucket policy, **SSE-KMS** and a separate log-archive account.
- **CloudTrail Lake** (managed event data store queried with SQL, long retention): **closed to new customers from 31 May 2026**. Existing customers keep it; it receives only critical fixes. AWS recommends **Amazon CloudWatch** for new designs, and Athena over the S3 trail logs remains the classic answer. Older exam questions may still offer CloudTrail Lake as "query CloudTrail events with SQL without managing infrastructure". It's acceptable as an answer on an SAP-C02 question, but know its status. Trails, Insights and event history are unaffected.
- **Delivery latency:** log files typically arrive within minutes, so CloudTrail-to-S3 is **not real time**. Real-time reaction to API calls uses the **EventBridge "AWS API Call via CloudTrail"** events.

### 2.10 Compliance & immutability

#### S3 Object Lock (WORM)
- Requires **versioning**. Can be enabled on **new or existing** buckets (existing buckets via the console or API; once enabled it can't be disabled). Locks **object versions**.
- **Retention modes:**
  - **Governance**: users with `s3:BypassGovernanceRetention` (and the `x-amz-bypass-governance-retention:true` header) can shorten or remove retention or delete. Use it for testing retention settings, or to protect against most users while allowing a break-glass role.
  - **Compliance**: **no one, including the root user, can delete the object version or shorten retention** until the retain-until date passes. Retention can only be extended. This is the answer for **SEC 17a-4 / FINRA / CFTC** (assessed by Cohasset).
- **Retention period**: per object version (retain-until date) or a **bucket default** (days/years).
- **Legal hold**: independent on/off flag with **no expiry**. Prevents deletion until removed (`s3:PutObjectLegalHold`). It works alongside retention; use it for litigation.
- **Nuance:** a simple DELETE (no version ID) still adds a **delete marker**, because the locked version is preserved, not hidden from deletion attempts. Lifecycle can't expire locked versions. Replication supports Object Lock (the destination must have it enabled).

#### Glacier Vault Lock (legacy vault-based Amazon Glacier)
- A **vault lock policy** (an IAM-style policy, for example "deny delete for archives younger than 365 days") is initiated (`InitiateVaultLock`). You have **24 hours** to test and `CompleteVaultLock`, after which the policy is **immutable**.
- **Status:** the original vault-based **Amazon Glacier service stopped accepting new customers on 15 Dec 2025**. Existing customers are unaffected. For new designs use **S3 Glacier storage classes + S3 Object Lock**. Exam questions may still describe Glacier Vault Lock as the WORM answer for archives.

#### AWS Backup Vault Lock
- **WORM for backups** in a backup vault (all supported services: EBS, RDS, Aurora, DynamoDB, EFS, FSx, S3, EC2…).
  - **Governance mode**: can be removed by users with sufficient IAM permissions.
  - **Compliance mode**: after a **grace time ("cooling-off") of at least 72 hours (3 days)** the lock becomes **immutable**. **No user, not even root, and not AWS** can delete recovery points before their retention ends, or remove the lock.
- **Min/max retention** settings make backup or copy jobs that violate them fail. Also assessed for SEC 17a-4. No extra charge for the lock itself.
- **Logically air-gapped vault**: a specialized vault type whose backups are held in AWS-owned storage, **locked by default in compliance mode**, and **shareable via AWS RAM** so a separate recovery account can restore even if the source account is compromised. This is the modern ransomware-resilience answer alongside cross-account copy.
- **AWS Backup Audit Manager** (a feature of Backup, different from AWS Audit Manager) reports whether resources are in backup plans with vault lock, cross-Region copy and so on.

#### AWS Artifact
- Self-service portal for **AWS compliance reports** (SOC 1/2/3, PCI DSS AOC, ISO certifications, FedRAMP packages, C5…) and **agreements** (for example the **HIPAA BAA**, NDA). The management account can accept agreements **on behalf of the whole organization**.
- Exam reflex: "auditor needs AWS's SOC 2 report / PCI attestation" → **Artifact**. Artifact is evidence about **AWS's** side of the shared responsibility model, not your workload.

#### AWS Audit Manager
- Continuously collected evidence mapped to frameworks (prebuilt: SOC 2, PCI DSS, HIPAA, GDPR, CIS…), producing assessment reports.
- **Status:** **closed to new customers from 30 April 2026 (maintenance mode)**. Existing customers continue. AWS points customers to **AWS Config conformance packs** (prebuilt framework templates with evidence export). On SAP-C02, "continuously collect evidence for auditors with minimal effort" may still point to Audit Manager. In real designs, prefer Config conformance packs + Security Hub CSPM standards.

### 2.11 Data perimeter overview

A **data perimeter** ensures *only trusted identities* access *trusted resources* from *expected networks*. It's built with three policy types and a small set of global condition keys. Full treatment is in [Chapter 02](02-Multi-Account-Governance.md) and [Chapter 03](03-Identity-and-Access-Management.md).

| Perimeter | Control | Key conditions |
|---|---|---|
| **Identity** (only my principals access my resources) | **Resource-based policies** and **RCPs** (resource control policies, org-wide caps on resource policies for S3, KMS, STS, SQS, Secrets Manager and others) | `aws:PrincipalOrgID`, `aws:PrincipalIsAWSService` |
| **Resource** (my principals only access my resources) | **SCPs**, **VPC endpoint policies** | `aws:ResourceOrgID`, `aws:ResourceAccount` |
| **Network** (access only from expected networks) | Resource policies / RCPs, SCPs | `aws:SourceVpc`, `aws:SourceVpce`, `aws:SourceIp`, `aws:ViaAWSService` (exempts service-to-service calls) |

The security services in this chapter **monitor** the perimeter: CloudTrail **network activity events** (`VpceAccessDenied`), IAM Access Analyzer external access findings, GuardDuty credential exfiltration findings (`UnauthorizedAccess:IAMUser/InstanceCredentialExfiltration.OutsideAWS`), and Config rules on public resources.

---

## 3. Architecture patterns

### Pattern 1 — Organization security baseline (delegated admin model)

```text
                AWS Organizations (all features)          Management account: billing, SCP/RCP only,
                         │                                designates delegated admins, NO workloads
   ┌─────────────────────┼──────────────────────────────────────────┐
   ▼                     ▼                                          ▼
 Security OU                                                   Workload OUs (Prod / Dev / ...)
 ┌───────────────────────────────┐  ┌──────────────────────────┐   ┌───────────────────────────┐
 │ Security Tooling account      │  │ Log Archive account      │   │ Member accounts (auto-    │
 │  delegated admin for:         │  │  S3: org CloudTrail       │   │ enrolled in every Region) │
 │  GuardDuty, Security Hub CSPM,│  │  (Object Lock, SSE-KMS,   │   │  Config recorder          │
 │  Inspector, Macie, Detective, │  │  validation on), Config   │   │  GuardDuty/Inspector/Macie│
 │  Firewall Manager, Config     │  │  delivery, VPC Flow Logs, │   │  members                  │
 │  aggregator, Security Lake    │  │  Security Lake (or here)  │   │  FMS-enforced WAF/SG      │
 │  EventBridge → IR automation  │  └──────────────────────────┘   └───────────────────────────┘
 └───────────────────────────────┘
```
- **When:** any multi-account estate. Control Tower sets up most of this (Log Archive + Audit accounts, org trail, Config).
- **Why:** separation of duties (security team owns findings, workload teams can't disable tools), one pane of glass, auto-enrol new accounts.
- **Remember:** most of these services are **Regional**. Enable them in every Region, and use Security Hub cross-Region aggregation to see everything in one Region.

### Pattern 2 — Central data lake with cross-account KMS

```text
 Producer acct A ─┐  PutObject (SSE-KMS, CMK-Lake)       Data Lake account
 Producer acct B ─┼────────────────────────────────▶ ┌─────────────────────────────┐
 Producer acct N ─┘                                  │ S3 bucket, default SSE-KMS  │
                                                     │ CMK-Lake + Bucket Key       │
   Key policy (CMK-Lake):                            │ Bucket policy:              │
   - Allow GenerateDataKey/Encrypt to                │  aws:PrincipalOrgID = o-xxx │
     aws:PrincipalOrgID = o-xxx                      │  deny non-TLS               │
     with kms:ViaService = s3.<region>.amazonaws.com │  deny wrong KMS key         │
   - Decrypt only for analytics roles                └─────────────────────────────┘
```
- Using `kms:ViaService` means producers can only use the key **through S3**, not call `Decrypt` directly. `aws:PrincipalOrgID` avoids listing 200 accounts. **Bucket Keys** keep the KMS request rate and cost low.
- Alternatively, set S3 **Object Ownership = bucket owner enforced** so the lake account owns every object (ACLs disabled).

### Pattern 3 — Automated EC2 incident response (GuardDuty → EventBridge → Step Functions)

```text
 GuardDuty finding (e.g. CryptoCurrency:EC2/BitcoinTool.B!DNS, Backdoor:EC2/C&CActivity)
      │  (member accounts → delegated admin; EventBridge in admin account, each Region)
      ▼
 EventBridge rule: source=aws.guardduty, detail.type prefix + severity >= 7
      ▼
 Step Functions state machine (or SSM Automation runbook / Lambda)
  1. Tag instance  "quarantine=true", capture metadata
  2. Enable termination protection; detach from ASG (or set to Standby); deregister from target groups
  3. Replace all security groups with ISOLATION SG (no inbound, no outbound)
     (+ NACL deny if existing tracked connections must be cut immediately)
  4. Snapshot all EBS volumes (forensics), optionally capture memory via SSM Run Command
  5. Revoke instance-profile role sessions (deny policy with aws:TokenIssueTime condition)
  6. Notify SNS / ticketing; investigate with Detective; forensic analysis in a separate account
```
- **Don't terminate first.** Evidence (memory, disk) would be lost. Isolate, preserve, then investigate.
- **Why swap the security group:** it's instant and reversible. But changing SGs **doesn't break existing tracked connections**. If the stem says "immediately cut all traffic including established sessions", add a NACL deny, or rely on an isolation SG with no rules plus the knowledge that tracked flows age out.
- **Compromised IAM credentials variant:** deactivate the access key, attach an explicit deny (`AWSRevokeOlderSessions`-style policy using `aws:TokenIssueTime`), rotate secrets, then review CloudTrail / Detective for what the key did.
- Cross-account: the delegated admin's EventBridge sees all members' findings. The automation assumes a role in the member account.

### Pattern 4 — Config detect-and-remediate loop

```text
 Resource change ──▶ Config rule (e.g. s3-bucket-public-read-prohibited / encrypted-volumes)
                         │ NON_COMPLIANT
                         ├──▶ Auto-remediation: SSM Automation runbook (assume remediation role)
                         ├──▶ Security Hub CSPM control finding → EventBridge → SNS/ticket
                         └──▶ Org aggregator dashboard in Security Tooling account
 Prevent recurrence: SCP / RCP / S3 Block Public Access at account/org level / EBS encryption by default
```
- **Detective + corrective**, paired with a **preventive** guardrail so the problem can't recur. The exam likes the answer that has all three.

### Pattern 5 — Layered edge protection

```text
 Users ─▶ Route 53 (Shield Adv) ─▶ CloudFront (WAF web ACL: AWS managed CRS, IP reputation,
                                   rate-based /login, Bot Control, ATP; Shield Advanced;
                                   geo restriction; TLS1.2+)
                                      │ origin: custom header secret + managed prefix list
                                      ▼
                                   ALB (SG allows only CloudFront origin-facing prefix list;
                                        WAF rule blocks requests lacking the secret header)
                                      ▼
                                   App in private subnets
 Firewall Manager (org admin) enforces the WAF policy + Shield Advanced on every CloudFront/ALB
```
- Stops attackers bypassing CloudFront and hitting the ALB directly. Use the **CloudFront managed prefix list** in the ALB security group, and/or a secret header checked by WAF on the ALB. Alternatively use **CloudFront VPC origins** to keep the ALB private (see [Chapter 05](05-Edge-DNS-and-Content-Delivery.md)).

### Pattern 6 — Tamper-evident and tamper-proof audit logging

```text
 Org trail (all Regions, mgmt + selected data events, log file validation ON)
        │
        ▼
 Log Archive account S3 bucket ── SSE-KMS (CMK in Log Archive; key policy allows
        │                         cloudtrail.amazonaws.com with aws:SourceArn = org trail)
        ├─ Object Lock COMPLIANCE, default retention (e.g. 7 years)
        ├─ Bucket policy: only CloudTrail may write; deny delete; deny non-TLS
        ├─ SCP: deny cloudtrail:StopLogging/DeleteTrail/UpdateTrail for all but security role
        └─ Lifecycle → S3 Glacier Flexible/Deep Archive for cost
```

### Pattern 7 — Ransomware-resilient backups

```text
 Workload accounts ──AWS Backup plan (org backup policy)──▶ local vault (CMK)
        │ cross-account + cross-Region copy
        ▼
 Backup/Recovery account: vault with Vault Lock COMPLIANCE (grace ≥72h),
 min/max retention; or logically air-gapped vault shared via RAM to a clean recovery account
 SCP: deny backup:DeleteRecoveryPoint, backup:PutBackupVaultAccessPolicy … to all except break-glass
```

### Pattern 8 — Multi-Region client-side encryption with MRKs

```text
 Region A app ── AWS Database Encryption SDK ── MRK primary (mrk-1234, Region A)
       │ writes encrypted attributes to DynamoDB global table
       ▼  replication (ciphertext)
 Region B app ── decrypts locally with MRK replica (mrk-1234, Region B)  ← no call to Region A
```
- Without MRKs, Region B would have to call KMS in Region A (a cross-Region dependency that fails during a Regional outage), or re-encrypt everything.

---

## 4. Decision tables / "X vs Y"

### Key custody: KMS vs CloudHSM vs custom key stores vs imported material

| Requirement in the stem | Answer |
|---|---|
| Encrypt AWS service data, least ops, audit key use, control access | **KMS customer managed key** |
| Keys generated in **our** HSM / we must be able to delete key material instantly / key material must be exportable or escrowed by us | **KMS with imported key material** |
| **Single-tenant** HSM, customer has **exclusive control**, AWS must have no access, **and** native S3/EBS/RDS integration | **KMS custom key store backed by CloudHSM** |
| Keys must **never be stored in AWS**, sovereignty, ability to **cut off AWS's access** instantly from on premises | **KMS external key store (XKS)** |
| App needs **PKCS#11 / JCE / CNG**, SSL/TLS offload, Oracle TDE on EC2, Windows CA, custom algorithms, very high crypto throughput | **CloudHSM directly** |
| FIPS 140-3 Level 3 validated HSMs (and nothing about tenancy) | **KMS is enough** (its HSMs are FIPS 140-3 L3). Choose CloudHSM only if single-tenancy / customer-managed HSM users is also required. |

| | **KMS** | **CloudHSM** |
|---|---|---|
| Tenancy | Multi-tenant (logically isolated) | **Single-tenant** cluster in your VPC |
| Who controls keys / users | AWS service under your IAM / key policies | **You** (HSM users). AWS can't recover lost credentials. |
| Access | AWS API (SigV4, IAM) | PKCS#11, JCE, CNG/KSP, OpenSSL |
| Integration with AWS services | Native (100+ services) | Only via a KMS custom key store (or your app code) |
| Availability | Managed, Regional, highly available | **You** size it: ≥2 HSMs across AZs |
| Key types | Symmetric, RSA, ECC, HMAC, ML-DSA | Broad: symmetric, asymmetric, more algorithms, exportable keys under your control |
| Cost | ~$1/key/month + requests | Hourly per HSM (significant), no per-key fee |
| Validation | FIPS 140-3 L3 HSMs | FIPS 140-3 L3 (hsm2m.medium) |

### Secrets Manager vs Parameter Store

| Need | Secrets Manager | Parameter Store |
|---|---|---|
| **Automatic rotation** | **Yes**: managed rotation or Lambda templates (RDS, Aurora, Redshift, DocumentDB, custom) | No (DIY with EventBridge + Lambda) |
| Cross-account access | **Resource policy** + CMK | Advanced tier parameters shareable via **AWS RAM** |
| Multi-Region | **Replica secrets** (synced, promotable) | No native replication |
| Max size | 64 KB | 4 KB standard / 8 KB advanced |
| Cost | ~$0.40/secret/month + $0.05 per 10K calls | **Standard free**; advanced ~$0.05/param/month; high throughput charged |
| Hierarchy / config data | Possible, not its purpose | **Yes**: hierarchies, labels, versions, `String`/`StringList` |
| Generate random passwords | Yes (`GetRandomPassword`, built into rotation) | No |
| Best for | DB credentials, API keys needing rotation, cross-account or DR secrets, compliance | App config, feature flags, AMI IDs, non-rotating secrets on a budget |

### Detection & compliance services: which one?

| Question in stem | Service | Not to be confused with |
|---|---|---|
| "Detect **malicious activity / compromised instances or credentials / crypto-mining / unusual API calls**" | **GuardDuty** | Inspector (vulnerabilities, not activity) |
| "Find **software vulnerabilities / CVEs / unpatched packages** in EC2, ECR images, Lambda; CIS OS benchmark" | **Inspector** | Config (configuration, not CVEs) |
| "Discover **PII / sensitive data in S3**" | **Macie** | GuardDuty S3 Protection (access behaviour) |
| "**Investigate** root cause, visualize what an IP/role did over time" | **Detective** | Security Hub (aggregation, not investigation) |
| "**Aggregate** findings, score against **CIS / FSBP / PCI / NIST**, one dashboard across accounts and Regions" | **Security Hub CSPM** | Config (raw rules) |
| "Correlate exposures/threats, attack path, prioritized risk" (2025+) | **new Security Hub** | — |
| "Record **configuration history**, evaluate **resource compliance** with rules, **auto-remediate**" | **AWS Config** | CloudTrail (who called which API) |
| "**Who** did what, when, from where (API audit)" | **CloudTrail** | Config (what the resource looked like) |
| "Centralize security logs in **OCSF** for SIEM / long-term" | **Security Lake** | CloudTrail Lake (CloudTrail only; closed to new customers) |
| "Unintended **external/public access** to resources, unused access" | **IAM Access Analyzer** | Macie policy findings (S3 only) |
| "AWS's **SOC/PCI reports**, BAA" | **Artifact** | Audit Manager (your evidence) |
| "Continuously collect **evidence** for an audit framework" | **Audit Manager** (maintenance) / **Config conformance packs** | Artifact |

### Perimeter controls

| Need | Use |
|---|---|
| L7 filtering (SQLi, XSS, bad bots, rate limiting, geo) on CloudFront/ALB/API GW/AppSync/Cognito | **AWS WAF** |
| DDoS expert response, cost protection, L7 auto-mitigation, NLB/EIP DDoS protection | **Shield Advanced** |
| Enforce WAF/Shield/SG/Network Firewall/DNS Firewall **across all accounts automatically** | **Firewall Manager** |
| Stateful L3–L7 inspection of VPC traffic (IDS/IPS, domain allow lists for egress, Suricata rules) | **AWS Network Firewall** ([Chapter 04](04-Networking-VPC-and-Hybrid-Connectivity.md)) |
| Block DNS queries to malicious domains from VPCs | **Route 53 Resolver DNS Firewall** |
| Instance-level stateful allow rules | Security groups |
| Subnet-level stateless allow/**deny** (block specific IPs at subnet) | NACLs |

### Immutability options

| Need | Use |
|---|---|
| WORM for **S3 objects** (records, logs), regulator-grade | **S3 Object Lock, compliance mode** (+ legal hold as needed) |
| WORM but allow privileged override | S3 Object Lock **governance** / Backup Vault Lock **governance** |
| WORM for **backups across services** (EBS, RDS, DynamoDB, EFS…) | **AWS Backup Vault Lock, compliance** (grace ≥ 72 h) / logically air-gapped vault |
| Legacy Glacier vault archives | Glacier Vault Lock (24 h to complete; service closed to new customers) |
| Prove logs weren't altered | **CloudTrail log file integrity validation** (+ Object Lock to prevent alteration) |

### S3 encryption decision

| Requirement | Choice |
|---|---|
| Just encrypted at rest, zero effort/cost | SSE-S3 (default) |
| Audit every key use, separate permission to decrypt, cross-account control, crypto-shred by disabling key | **SSE-KMS with CMK + Bucket Key** |
| Two independent layers of encryption mandated | **DSSE-KMS** |
| Company must supply its own key per request and AWS must not store it | SSE-C (now must be explicitly unblocked on the bucket) |
| Data must be encrypted before it leaves the client | **Client-side** (Encryption SDK / S3 Encryption Client with KMS) |

---

## 5. Exam keyword → answer cheat list

| Keyword / phrase in stem | Lean towards |
|---|---|
| "Share encrypted snapshot/AMI with another account" | Re-encrypt with **CMK**, update **key policy**, share; target copies with its own key |
| "Encrypted with the default `aws/rds` / `aws/ebs` key, needs sharing" | **Copy with a customer managed key** first |
| "Enable encryption on existing RDS / EBS" | Snapshot → **encrypted copy** → restore / new volume; RDS & Aurora **blue/green** for low downtime |
| "Ensure all new EBS volumes are encrypted" | **EBS encryption by default** (per Region) + SCP `ec2:Encrypted` condition + Config rule |
| "Keys stored outside AWS / revoke AWS access at any time" | **XKS** |
| "Single-tenant HSM, customer-exclusive control" | **CloudHSM** (custom key store if AWS services must use it) |
| "Import our own key material / set expiry" | KMS **imported key material** |
| "Decrypt in the DR Region even if primary Region unavailable" (client-side) | **Multi-Region keys** |
| "Rotate KMS key immediately" | **On-demand rotation** (symmetric; max 25/key) |
| "Rotate every 90 days automatically" | Automatic rotation with **custom period (90–2,560 days)** |
| "KMS ThrottlingException from S3" | **S3 Bucket Keys**; quota increase |
| "Use key only from S3 / only through RDS" | **`kms:ViaService`** |
| "Tenant isolation with a single key" | **Encryption context** condition |
| "Rotate DB credentials automatically" | **Secrets Manager** (managed / Lambda rotation) |
| "Cheapest way to store config/parameters" | **Parameter Store standard** |
| "Secret needed in another account" | Secrets Manager **resource policy + CMK** (not `aws/secretsmanager`) |
| "Secret must survive Regional outage" | Secrets Manager **replica secret** |
| "Certificate for CloudFront" | ACM cert in **us-east-1** |
| "ACM cert on EC2 / on-prem server" | **Exportable ACM public cert** (paid) or third-party/imported; or put ALB/CloudFront in front |
| "Internal TLS / mTLS between services / private domain" | **AWS Private CA** |
| "Imported certificate expiring" | ACM doesn't renew imported certs → **EventBridge/Config expiry check** |
| "Block SQL injection / XSS" | **WAF** managed rule groups |
| "Credential stuffing on login page" | **WAF Fraud Control ATP** + rate-based rule on `/login` |
| "Fake account sign-ups" | **WAF ACFP** |
| "Scrapers / bots" | **WAF Bot Control** (targeted for sophisticated bots) |
| "Rate limit per IP / per API key" | **WAF rate-based rule** (custom aggregation key) |
| "24/7 DDoS response team, cost protection" | **Shield Advanced** |
| "Apply WAF rules to all ALBs in all accounts incl. future ones" | **Firewall Manager** (requires Organizations + Config + admin account) |
| "Detect crypto-mining / compromised EC2 / anomalous API" | **GuardDuty** |
| "Scan uploaded S3 files for malware" | **GuardDuty Malware Protection for S3** |
| "Container runtime threat detection" | **GuardDuty Runtime Monitoring** |
| "CVE scanning of ECR images / EC2 / Lambda" | **Inspector** |
| "PII in S3" | **Macie** |
| "Root-cause investigation" | **Detective** |
| "Single dashboard + CIS/PCI/FSBP compliance score across org" | **Security Hub CSPM** with **central configuration** + **cross-Region aggregation** |
| "Suppress/escalate findings automatically" | Security Hub **automation rules** |
| "Auto-remediate non-compliant resources" | **Config rule + SSM Automation** remediation |
| "Deploy a set of compliance rules org-wide" | **Organization conformance pack** |
| "View compliance across accounts & Regions" | **Config aggregator** |
| "Who deleted the bucket?" | **CloudTrail** (event history 90 days / trail) |
| "Log S3 object-level reads" | CloudTrail **data events** |
| "Calls through VPC endpoints / denied by endpoint policy" | CloudTrail **network activity events** |
| "Detect unusual API volume" | **CloudTrail Insights** |
| "Prove logs weren't tampered with" | **Log file integrity validation** |
| "Org-wide trail members can't disable" | **Organization trail** |
| "WORM, even root can't delete" | **Object Lock compliance** / **Backup Vault Lock compliance** |
| "Litigation hold, indefinite" | **S3 Object Lock legal hold** |
| "AWS SOC 2 report / BAA" | **AWS Artifact** |
| "Enforce HTTPS to S3" | Bucket policy deny `aws:SecureTransport = false` |
| "Least operational overhead, org-wide" | **Delegated admin + auto-enable** for the security service |

---

## 6. Traps & distractors

1. **"Attach an IAM policy granting kms:Decrypt"** to give another account access. IAM alone never works for KMS. The **key policy** must allow the account (and the other account's IAM must allow the principal).
2. **"Share the snapshot encrypted with the AWS managed key and grant the other account access to `aws/rds`".** Impossible: you can't modify AWS managed key policies. Re-encrypt with a CMK.
3. **"Enable encryption on the running RDS instance / EBS volume (modify)".** Not possible. The only routes are snapshot copy or restore, or blue/green.
4. **"Use a multi-Region key so S3 replication / Aurora global database works".** Those services re-encrypt in the destination with a destination-Region key. MRKs are for **client-side** or **app-level** interoperability.
5. **"Enable automatic rotation on the asymmetric / HMAC / CloudHSM-store key".** Not supported. Rotate manually by creating a new key and repointing the alias.
6. **"Rotating the KMS key re-encrypts existing data" or "mitigates a leaked data key".** It does neither.
7. **"CloudHSM because the requirement says FIPS 140 Level 3".** KMS HSMs are FIPS 140-3 L3 too. Pick CloudHSM only for single-tenancy or customer-exclusive control, or for app-level PKCS#11/JCE.
8. **"Move to a CloudHSM custom key store to solve KMS throttling".** It lowers the ceiling to 1,800 req/s per store.
9. **"Store DB passwords in Parameter Store SecureString with automatic rotation".** There's no native rotation. Use Secrets Manager.
10. **"Use `aws/secretsmanager` and a resource policy for cross-account".** Also needs a CMK; the AWS managed key isn't usable cross-account.
11. **"Request the ACM certificate in eu-west-1 for the CloudFront distribution".** It must be in us-east-1.
12. **"ACM will renew the imported certificate".** It won't. Only ACM-issued certificates renew (and DNS-validated ones do so automatically).
13. **"Associate AWS WAF with the NLB / EC2 instance".** Not supported. Use Shield Advanced (EIP), Network Firewall or SGs, or put ALB/CloudFront in front.
14. **"Shield Standard provides the SRT / cost protection".** Only Shield Advanced does, and SRT access needs Business/Enterprise-level support.
15. **"Firewall Manager without AWS Config".** Config must be enabled in member accounts; Organizations with all features is required too.
16. **"GuardDuty will block the attack".** It only detects. Response requires EventBridge automation.
17. **"Enable VPC Flow Logs so GuardDuty can analyse network traffic".** Unnecessary. GuardDuty consumes its own independent stream.
18. **"Inspector to find PII" / "Macie to find CVEs" / "Detective to detect threats".** Classic swaps. See the decision table.
19. **"Security Hub detects threats itself".** Security Hub CSPM runs **configuration** checks (via Config) and aggregates. Threat detection is GuardDuty's job.
20. **"Use CloudTrail to see the previous configuration of a resource".** That's Config. CloudTrail shows the API call.
21. **"CloudTrail log file validation prevents deletion".** It only **detects** tampering. Pair it with Object Lock and SCPs.
22. **"Terminate the compromised instance immediately".** It destroys forensic evidence. Isolate and snapshot first.
23. **"Changing the security group instantly kills the attacker's established session".** Tracked connections persist. Use a NACL if you must cut them now.
24. **"Object Lock governance mode for SEC 17a-4".** Governance can be bypassed. Compliance is required.
25. **"Glacier Vault Lock / CloudTrail Lake / Audit Manager for a brand-new customer design".** All three are closed to new customers (as of 2026). On an SAP-C02 question they may still be the "intended" answer if nothing better is offered. In practice use S3 Object Lock, CloudWatch/Athena/Security Lake, and Config conformance packs.
26. **"Deny PutObject unless header `x-amz-server-side-encryption` exists"** while relying on bucket default encryption. This breaks clients that rely on default encryption. Prefer default SSE-KMS + deny *wrong* values.
27. **"SSE-C keeps working on new buckets".** Since April 2026 it's blocked by default on new general purpose buckets.

---

## 7. Professional architect focus

- **Key hierarchy design.** Don't create one CMK per resource (cost, quota and policy sprawl) or one key for everything (blast radius, coarse audit). A common middle ground is **one CMK per data classification per application per environment per Region**, with encryption context for finer separation. Document key owners and admins.
- **Key policy hygiene.** Always keep an account-root admin statement or a dedicated key-admin role. Use `aws:PrincipalOrgID` instead of account lists. Use `kms:ViaService` to stop direct decrypts. Put an **SCP/RCP** in place to deny `kms:ScheduleKeyDeletion` and `kms:PutKeyPolicy` to everyone except the key-admin role. Alarm on `DisableKey` / `ScheduleKeyDeletion` (EventBridge on CloudTrail).
- **Crypto-shredding as a feature.** With CMKs (or imported material / XKS), "delete all data for tenant X" can be implemented by destroying a tenant key. Discuss this with legal/privacy stakeholders (GDPR erasure).
- **XKS is a trade-off conversation, not a default.** You take on availability, latency and durability. If your proxy or HSM is down, S3 GETs and EBS volume attaches fail. Insist on a multi-site external key manager and CloudWatch alarms. Many "sovereignty" requirements are met by KMS + imported material or the AWS European Sovereign Cloud instead.
- **Cost awareness.** Shield Advanced is $36k/year minimum. Justify it with revenue at risk, cost protection and SRT. KMS costs grow with request volume, so Bucket Keys and data-key caching matter at scale. GuardDuty S3 Protection and Runtime Monitoring cost scales with volume; turn on what your threat model needs. Config periodic recording can cut CI charges for noisy resource types.
- **Detection without response is theatre.** Every high-severity finding type needs an owner, a runbook and preferably automation (EventBridge → Step Functions). Test with **GuardDuty sample findings** and game days. Make sure automations are idempotent and can't be weaponized (for example an attacker triggering mass isolation).
- **Separation of duties.** Security tooling and logs live in accounts workload teams can't administer. Protect the log archive and the backup vault with SCPs, Object Lock and Vault Lock. Ensure break-glass procedures exist and are audited.
- **Regional coverage.** Attackers love unused Regions. Either deny them with an SCP (`aws:RequestedRegion`) or monitor them with GuardDuty / Config / CloudTrail in all Regions.
- **Service lifecycle awareness (2025–2026).** CloudTrail Lake, Audit Manager and Glacier vaults are closed to new customers. Security Hub has split into Security Hub and Security Hub CSPM. ACM certificate lifetimes are shrinking (198 days, trending lower through 2029). Aurora encrypts new clusters by default. S3 blocks SSE-C by default. Raise these when reviewing older architectures.
- **Shared responsibility for encryption in transit.** "Encrypt everything in transit" still means TLS at the application, even though AWS encrypts the physical network. Plan certificate distribution (ACM/Private CA) and rotation as part of the platform.

---

## 8. Skills checklist

- [ ] I can explain AWS owned vs AWS managed vs customer managed keys and when each blocks cross-account sharing.
- [ ] I can write (from memory) a key policy statement allowing another account to use a key **only through S3** with `kms:ViaService`.
- [ ] I can explain why the default key policy's `:root` principal enables IAM policies.
- [ ] I can describe envelope encryption, data keys, encryption context and the 4 KB `Encrypt` limit.
- [ ] I know which keys support automatic rotation (period 90–2,560 days), on-demand rotation (max 25) and which must be rotated manually.
- [ ] I can choose between imported key material, CloudHSM key store, XKS and CloudHSM direct.
- [ ] I can explain multi-Region key use cases and why S3 CRR / Aurora global database don't need them.
- [ ] I can fix KMS throttling (Bucket Keys, caching, quota increase) and know the custom key store 1,800 req/s limit.
- [ ] I can encrypt an existing unencrypted RDS/EBS/Aurora resource and share an encrypted snapshot cross-account and cross-Region.
- [ ] I can compare Secrets Manager and Parameter Store, set up cross-account secret access, and configure rotation networking.
- [ ] I know ACM's Regional rule, the us-east-1 CloudFront rule, the imported-cert renewal gap, exportable public certs and the 198-day validity.
- [ ] I can enforce SSE-KMS with a specific key and enforce TLS via bucket policy.
- [ ] I can design WAF rules (managed groups, rate-based with scope-down, Bot Control, ATP/ACFP) and know where WAF can attach.
- [ ] I can list Shield Advanced benefits and prerequisites (SRT needs Business/Enterprise support; proactive engagement needs health checks).
- [ ] I know Firewall Manager prerequisites and policy types.
- [ ] I can set up GuardDuty, Security Hub CSPM, Inspector, Macie and Detective org-wide with a delegated admin across Regions.
- [ ] I can design an automated EC2 isolation and forensics workflow.
- [ ] I can design Config rules + conformance packs + SSM auto-remediation + aggregator.
- [ ] I can distinguish CloudTrail management, data, network activity and Insights events, and set up an org trail with integrity validation.
- [ ] I can choose between S3 Object Lock modes, legal hold, Backup Vault Lock and Glacier Vault Lock.
- [ ] I know which services are closed to new customers (CloudTrail Lake, Audit Manager, Glacier vaults) and their replacements.

---

## 9. Practice questions

> Original SAP-C02-style questions written for this guide. They are not real exam questions.

**Q1.** A financial services company runs a production Amazon RDS for PostgreSQL DB instance in `us-east-1` in its Production account. The instance was created with storage encryption using the default AWS managed key (`aws/rds`). A new regulation requires a daily copy of the database to be kept in a separate DR account in `us-west-2`, encrypted with a key that the DR account controls. The source account's security team must be able to disable its own key without affecting the DR copies. What should a solutions architect do?

- A. Share the daily automated snapshot directly with the DR account and add the DR account to the `aws/rds` key policy so it can copy the snapshot to `us-west-2`.
- B. Copy the daily snapshot in the Production account and re-encrypt it with a customer managed key whose key policy allows the DR account. Share the copy with the DR account. In the DR account, copy the shared snapshot to `us-west-2` and encrypt it with a customer managed key owned by the DR account.
- C. Create a multi-Region customer managed key in the Production account with a replica in `us-west-2`. Share the snapshot encrypted with `aws/rds` with the DR account and let it restore using the replica key.
- D. Enable a cross-Region read replica in `us-west-2` encrypted with the `aws/rds` key, then promote the replica in the DR account each day and take a snapshot.

**Q2.** A media company ingests about 25,000 small objects per second into an S3 bucket in `us-east-2`. Objects are encrypted with SSE-KMS using a customer managed key. A separate microservice in the same account encrypts each message it publishes with the AWS Encryption SDK, calling `GenerateDataKey` for every message. Both workloads are now intermittently failing with KMS `ThrottlingException` errors. The company wants to resolve the issue with the least ongoing cost and operational effort, without weakening its encryption posture. Which combination of actions should the solutions architect recommend? **(Select TWO.)**

- A. Enable S3 Bucket Keys on the bucket's default encryption configuration and copy existing objects only if needed.
- B. Configure data key caching in the AWS Encryption SDK with appropriate limits on age and messages per data key.
- C. Move the customer managed key into an AWS CloudHSM custom key store to obtain dedicated cryptographic capacity.
- D. Switch the bucket to DSSE-KMS so that S3 uses two layers of encryption and spreads the KMS load.
- E. Replace the customer managed key with a multi-Region key and replicate it to `us-west-2` so requests are split between two Regions.

**Q3.** A European bank is moving a core analytics platform to AWS. Data will be stored in Amazon S3, Amazon EBS and Amazon Redshift. A regulator requires that the encryption keys protecting this data are generated, stored and used only in the bank's own HSMs in its data centres. The bank must be able to immediately and unilaterally prevent AWS from decrypting any of the data, without deleting data in AWS. The bank prefers native integration with AWS services. Which solution meets these requirements?

- A. Create AWS KMS customer managed keys with imported key material generated in the bank's HSMs and set the key material to expire after 24 hours.
- B. Create an AWS CloudHSM cluster in two Availability Zones, create a KMS custom key store backed by the cluster, and use KMS keys from that store with each service.
- C. Create a KMS external key store that connects through an external key store proxy to the bank's on-premises HSMs, and use KMS keys in that store with each service.
- D. Use SSE-C for Amazon S3 and client-side encryption for Amazon EBS and Amazon Redshift with keys retrieved from the on-premises HSMs at runtime.

**Q4.** A company with 150 AWS accounts in AWS Organizations has enabled Amazon GuardDuty in all accounts and Regions, with a delegated administrator in a Security Tooling account. The security team wants an automated response when GuardDuty reports high-severity findings indicating that an EC2 instance is communicating with a known command-and-control server or mining cryptocurrency. The response must contain the threat quickly, preserve evidence for forensic analysis, and require minimal per-account setup. Which combination of steps should the solutions architect take? **(Select THREE.)**

- A. In the Security Tooling account, create an Amazon EventBridge rule in each Region that matches the relevant GuardDuty finding types with severity of 7 or higher and starts an AWS Step Functions state machine.
- B. Have the state machine assume a response role in the affected member account, detach the instance from its Auto Scaling group and target groups, and replace its security groups with an isolation security group that allows no traffic.
- C. Have the state machine create snapshots of all attached EBS volumes, tag the instance and snapshots with the finding ID, and notify the incident response team through Amazon SNS.
- D. Have the state machine terminate the instance immediately and launch a replacement from the latest AMI to minimise attacker dwell time.
- E. Configure GuardDuty in each member account to block traffic to the malicious IP addresses automatically by enabling GuardDuty threat lists.
- F. Create an AWS Config rule in each member account that detects the GuardDuty finding and runs an SSM Automation document to stop the instance.

**Q5.** An application team stores the master credentials for an Amazon Aurora PostgreSQL cluster. Security policy requires that the credentials rotate automatically every 30 days. A reporting application in a separate Analytics account must read the credentials. The credentials must remain retrievable in `eu-west-1` if `eu-central-1` (the primary Region) becomes unavailable. Which solution meets these requirements with the least operational overhead?

- A. Store the credentials as an SSM Parameter Store advanced SecureString encrypted with the AWS managed key, share the parameter with the Analytics account through AWS RAM, and schedule an EventBridge rule that invokes a Lambda function to rotate the password every 30 days.
- B. Store the credentials in AWS Secrets Manager encrypted with the `aws/secretsmanager` key, enable rotation every 30 days, and add a resource policy that allows the Analytics account role to call `GetSecretValue`.
- C. Store the credentials in AWS Secrets Manager encrypted with a customer managed multi-Region KMS key. Enable managed rotation every 30 days. Add a resource policy allowing the Analytics account role, and allow that role `kms:Decrypt` in the key policy. Replicate the secret to `eu-west-1`.
- D. Store the credentials in an encrypted S3 bucket with cross-Region replication to `eu-west-1`, and use a bucket policy to grant the Analytics account read access. Rotate the password with a scheduled Lambda function.

**Q6.** A retail company operates 40 AWS accounts under AWS Organizations. Each account hosts customer-facing web applications behind Application Load Balancers. Over the past month the login endpoints have been hit by credential-stuffing attacks from thousands of residential IP addresses, each sending a low number of requests. The security team wants a consistent protection that is automatically applied to every existing and future ALB in the organization, while letting application teams add their own WAF rules. Which combination of actions should the solutions architect take? **(Select TWO.)**

- A. Designate a Firewall Manager administrator account, ensure AWS Config is enabled in all member accounts, and create a Firewall Manager AWS WAF policy scoped to ALBs across the organization with auto-remediation enabled.
- B. In the Firewall Manager WAF policy, add the AWS WAF Fraud Control account takeover prevention (ATP) managed rule group configured for the login path as a first rule group, together with a rate-based rule scoped down to the login path.
- C. Subscribe to AWS Shield Advanced in every account and rely on automatic application layer DDoS mitigation to block the credential-stuffing traffic.
- D. Add network ACL deny entries for the attacking IP addresses in every VPC using a Lambda function that parses ALB access logs every hour.
- E. Enable Amazon GuardDuty in all accounts and create suppression rules for the login endpoint findings.

**Q7.** A healthcare company uses AWS Backup to protect Amazon RDS, Amazon EFS and Amazon EBS resources across 30 accounts. After a ransomware incident at a peer organisation, the board requires that backups be retained for 7 years and that no one, including administrators with root credentials in any of the company's accounts, can delete or shorten the retention of backups. The solution must be operationally simple. What should the solutions architect do?

- A. Copy all backups to a dedicated backup account and configure the destination vault with AWS Backup Vault Lock in governance mode with a minimum retention of 7 years.
- B. Copy all backups to a dedicated backup account and configure the destination vault with AWS Backup Vault Lock in compliance mode with a minimum retention of 7 years, after validating the configuration during the grace period.
- C. Export all backups to an S3 bucket with S3 Object Lock in governance mode and a 7-year default retention, and apply an SCP that denies `s3:BypassGovernanceRetention`.
- D. Archive all backups to an Amazon Glacier vault and apply a Glacier Vault Lock policy that denies deletion for 7 years.

**Q8.** A company's security team discovered unencrypted EBS volumes in several of its 300 AWS accounts. The team must report on all unencrypted volumes across accounts and Regions from a single place, and must prevent anyone from creating new unencrypted volumes in the future. Which combination of actions will meet these requirements with the least operational overhead? **(Select TWO.)**

- A. Deploy the `encrypted-volumes` AWS Config rule to all accounts through an organization conformance pack and create an organization-wide Config aggregator in the Security Tooling account.
- B. Attach an SCP to the organization root that denies `ec2:CreateVolume` and `ec2:RunInstances` when the `ec2:Encrypted` condition key is `false`, and enable EBS encryption by default in every account and Region.
- C. Enable Amazon Inspector in all accounts to scan for unencrypted EBS volumes and send findings to Security Hub.
- D. Use an SSM Automation document to call `ModifyVolume` with the `Encrypted` parameter set to `true` on every existing unencrypted volume.
- E. Enable Amazon Macie in all accounts to discover unencrypted EBS volumes containing sensitive data.

**Q9.** An auditor requires that a company's AWS API activity logs for all 80 accounts be retained for 7 years. The company must prove that log files have not been modified since delivery, and logs must not be deletable by anyone, including administrators of the member accounts or the logging account. Member account administrators must not be able to stop logging. Which solution meets these requirements?

- A. Enable CloudTrail event history in each account and export the events monthly to an S3 bucket in each account with versioning enabled.
- B. Create an organization trail from the management account that logs all Regions to an S3 bucket in a dedicated Log Archive account. Enable log file integrity validation. Configure the bucket with S3 Object Lock in compliance mode with a 7-year default retention and SSE-KMS encryption.
- C. Create a trail in each member account that delivers to a central S3 bucket with MFA Delete enabled, and use Amazon Macie to detect any modification of log files.
- D. Create an organization trail and configure CloudWatch Logs as the only destination with a 7-year retention setting and a metric filter alarm on `DeleteLogGroup`.

**Q10.** A gaming company runs an active-active application in `us-east-1` and `eu-west-1` using Amazon DynamoDB global tables. Some attributes contain player payment tokens that must be encrypted on the client side before being written. Each Regional application stack must be able to decrypt any item written in either Region, even if the other Region is completely unavailable. The company wants to keep using AWS KMS. Which solution meets these requirements?

- A. Create a single-Region KMS key in `us-east-1` and have the `eu-west-1` application call KMS in `us-east-1` to decrypt data keys.
- B. Create separate single-Region KMS keys in each Region and use the AWS Database Encryption SDK with a keyring containing only the local key.
- C. Create a KMS multi-Region primary key in `us-east-1` and a replica key in `eu-west-1`, and configure each application's AWS Database Encryption SDK keyring to use its local multi-Region key.
- D. Rely on DynamoDB encryption at rest with a customer managed key in each Region, because global tables re-encrypt replicated items automatically.

---

### Answers & explanations

<details><summary><strong>Q1</strong> Show answer</summary>

**Correct: B**

- **Why:** Snapshots encrypted with an AWS managed key can't be shared, because you can't edit that key's policy. The fix is to copy the snapshot and re-encrypt it with a **customer managed key**, add the DR account to that key's policy, and share the copy. The DR account then **copies** the snapshot cross-Region and re-encrypts with **its own** key in `us-west-2` (keys are Regional). Its copy no longer depends on the Production key, so the source team can disable its key without affecting DR.
- **A:** AWS managed key policies can't be modified, and snapshots encrypted with them can't be shared.
- **C:** The snapshot is still encrypted with `aws/rds`, so it can't be shared. Using a Production-owned MRK would also keep the dependency on a key the source team controls.
- **D:** Read replicas stay in the same account. Promoting daily is operationally heavy, and the replica would still use an AWS managed key in the source account.
- **References:** [RDS encryption limitations](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/Overview.Encryption.html) · [Sharing a DB snapshot](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_ShareSnapshot.html) · [Copying a DB snapshot](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_CopySnapshot.html)
</details>

<details><summary><strong>Q2</strong> Show answer</summary>

**Correct: A, B**

- **Why:** The symmetric cryptographic quota is shared by all callers in the account and Region, including S3 calling KMS on your behalf. **S3 Bucket Keys** let S3 derive per-object keys from a bucket-level key, cutting KMS requests by up to 99%. **Data key caching** in the Encryption SDK reuses data keys within limits, cutting `GenerateDataKey` calls. Both are cheap and need no infrastructure. (A quota increase is also possible, but it wasn't offered and it doesn't reduce cost.)
- **C:** Custom key store operations are capped at 1,800 req/s per store, which isn't adjustable. That makes things worse, and adds HSM cost.
- **D:** DSSE-KMS doesn't support Bucket Keys and costs more. It won't reduce KMS calls.
- **E:** Quotas are per Region. Splitting traffic would require the workloads to run in two Regions; an MRK doesn't move this traffic anywhere.
- **References:** [KMS request quotas](https://docs.aws.amazon.com/kms/latest/developerguide/requests-per-second.html) · [S3 Bucket Keys](https://docs.aws.amazon.com/AmazonS3/latest/userguide/bucket-key.html) · [Encryption SDK data key caching](https://docs.aws.amazon.com/encryption-sdk/latest/developer-guide/data-key-caching.html)
</details>

<details><summary><strong>Q3</strong> Show answer</summary>

**Correct: C**

- **Why:** A KMS **external key store (XKS)** keeps key material in the bank's own external key manager. KMS reaches it only through an XKS proxy that the bank operates, so the key never exists in AWS (hold your own key). Disconnecting the proxy or external key immediately blocks every decrypt (apart from short-lived data key caches in some services) without deleting data. Any service that supports symmetric customer managed keys, including S3, EBS and Redshift, works with XKS keys.
- **A:** Imported key material **is stored and used inside AWS KMS HSMs**, which breaks "used only in the bank's own HSMs". Expiring every 24 hours would also cause outages.
- **B:** CloudHSM is single-tenant, but the HSMs are **in AWS**, not in the bank's data centres.
- **D:** SSE-C and client-side encryption don't give native integration. EBS and Redshift don't support SSE-C-style customer-supplied keys this way, and the operational burden is high.
- **References:** [External key stores](https://docs.aws.amazon.com/kms/latest/developerguide/keystore-external.html) · [Choosing a key store](https://docs.aws.amazon.com/kms/latest/developerguide/key-store-overview.html)
</details>

<details><summary><strong>Q4</strong> Show answer</summary>

**Correct: A, B, C**

- **Why:** GuardDuty findings from member accounts flow to the delegated administrator, and from there to EventBridge in each Region. One rule per Region in the Security Tooling account (**A**) avoids per-account setup. The state machine then **contains** the threat: it isolates the instance with an isolation SG and removes it from the ASG and load balancers (**B**). It **preserves evidence** with EBS snapshots, tagging and notification (**C**).
- **D:** Terminating destroys volatile and disk evidence. Isolate and preserve first.
- **E:** GuardDuty is detection-only. Threat lists add custom indicators for **detection**; they don't block traffic.
- **F:** Config evaluates resource configuration, not GuardDuty findings. It would also need per-account rules, and stopping the instance loses memory evidence.
- **References:** [GuardDuty with EventBridge](https://docs.aws.amazon.com/guardduty/latest/ug/guardduty_findings_eventbridge.html) · [Remediating a compromised EC2 instance](https://docs.aws.amazon.com/guardduty/latest/ug/compromised-ec2.html) · [AWS Security Incident Response Guide](https://docs.aws.amazon.com/whitepapers/latest/aws-security-incident-response-guide/aws-security-incident-response-guide.html)
</details>

<details><summary><strong>Q5</strong> Show answer</summary>

**Correct: C**

- **Why:** **Secrets Manager** gives **managed rotation** for Aurora with no custom code. Cross-account access needs both a **resource policy** on the secret **and** a **customer managed key** whose key policy allows the other account to decrypt. **Replica secrets** keep the secret available in `eu-west-1`. A multi-Region key (or a CMK in each Region) encrypts the replica.
- **A:** Parameter Store has no native rotation, so you'd maintain a custom Lambda. It also has no cross-Region replication, and the AWS managed key can't be used cross-account.
- **B:** The `aws/secretsmanager` AWS managed key can't be used cross-account, and the secret isn't replicated to `eu-west-1`.
- **D:** S3 isn't a secrets manager. It adds custom rotation and coordination code, and exposure risk.
- **References:** [Cross-account access to secrets](https://docs.aws.amazon.com/secretsmanager/latest/userguide/auth-and-access_examples_cross.html) · [Replicate secrets across Regions](https://docs.aws.amazon.com/secretsmanager/latest/userguide/create-manage-multi-region-secrets.html) · [Rotation](https://docs.aws.amazon.com/secretsmanager/latest/userguide/rotating-secrets.html)
</details>

<details><summary><strong>Q6</strong> Show answer</summary>

**Correct: A, B**

- **Why:** **Firewall Manager** applies a WAF policy to every in-scope ALB in the organization, including future accounts and resources. Its prerequisites are Organizations with all features, an FMS administrator account, and Config enabled in member accounts. FMS policies define first and last rule groups and let account teams add their own rules in between. **ATP** detects credential stuffing (stolen credential checks, and distributed low-and-slow attempts across many IPs), and a scoped **rate-based rule** adds volumetric control on the login path.
- **C:** Shield Advanced's L7 mitigation targets DDoS floods, not low-volume distributed credential stuffing. It's also $3,000/month and still needs WAF rules.
- **D:** NACLs have a small rule limit and can't track thousands of rotating residential IPs. Hourly log parsing is too slow and operationally heavy.
- **E:** GuardDuty doesn't inspect HTTP login requests, and suppression rules hide findings rather than block attacks.
- **References:** [Firewall Manager prerequisites](https://docs.aws.amazon.com/waf/latest/developerguide/fms-prereq.html) · [AWS WAF Fraud Control ATP](https://docs.aws.amazon.com/waf/latest/developerguide/waf-atp.html) · [Rate-based rules](https://docs.aws.amazon.com/waf/latest/developerguide/waf-rule-statement-type-rate-based.html)
</details>

<details><summary><strong>Q7</strong> Show answer</summary>

**Correct: B**

- **Why:** **AWS Backup Vault Lock in compliance mode** becomes immutable once the grace time ends (at least 72 hours). After that, **no user, not even root, and not AWS** can delete recovery points early or remove the lock. Copying to a dedicated backup account adds blast-radius isolation. It works natively for RDS, EFS and EBS with no custom export.
- **A:** Governance mode can be removed by users with sufficient IAM permissions, so it doesn't meet "no one, including administrators".
- **C:** You can't natively "export" RDS, EFS or EBS backups to S3 objects for restore in the same way, which adds heavy operational effort. Governance mode plus an SCP still leaves the management account (which SCPs don't restrict) able to bypass retention.
- **D:** Glacier vaults aren't an AWS Backup target for these services, and the vault-based Glacier service stopped accepting new customers on 15 Dec 2025.
- **References:** [AWS Backup Vault Lock](https://docs.aws.amazon.com/aws-backup/latest/devguide/vault-lock.html) · [Cross-account backup](https://docs.aws.amazon.com/aws-backup/latest/devguide/create-cross-account-backup.html)
</details>

<details><summary><strong>Q8</strong> Show answer</summary>

**Correct: A, B**

- **Why:** An **organization conformance pack** (or organization Config rule) deploys `encrypted-volumes` everywhere, and an **organization aggregator** gives one view across all accounts and Regions (the *detect/report* requirement). An **SCP** using the `ec2:Encrypted` condition key, plus **EBS encryption by default**, *prevents* new unencrypted volumes. Encryption by default means users don't even have to remember the flag.
- **C:** Inspector scans for software vulnerabilities and network reachability, not EBS encryption configuration.
- **D:** You can't encrypt an existing volume in place with `ModifyVolume`. It requires snapshot → encrypted copy → new volume.
- **E:** Macie scans S3 objects only.
- **References:** [Config managed rule encrypted-volumes](https://docs.aws.amazon.com/config/latest/developerguide/encrypted-volumes.html) · [Conformance packs](https://docs.aws.amazon.com/config/latest/developerguide/conformance-packs.html) · [EBS encryption by default](https://docs.aws.amazon.com/ebs/latest/userguide/encryption-by-default.html) · [SCP examples](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_policies_scps_examples.html)
</details>

<details><summary><strong>Q9</strong> Show answer</summary>

**Correct: B**

- **Why:** An **organization trail** covers every account, and member accounts can't modify or stop it. **Log file integrity validation** produces signed digest files that prove whether logs changed (tamper-evident). **S3 Object Lock in compliance mode** with a 7-year default retention makes logs undeletable by anyone, including root in the Log Archive account (tamper-proof). SSE-KMS adds access control and auditing.
- **A:** Event history covers only 90 days of management events, exports are manual, and each account could delete its own bucket.
- **C:** Per-account trails can be stopped by member admins. MFA Delete doesn't stop someone with root MFA, and Macie doesn't detect log file modification.
- **D:** CloudWatch Logs retention doesn't prevent deletion of the log group by privileged users, and there's no integrity validation.
- **References:** [Organization trails](https://docs.aws.amazon.com/awscloudtrail/latest/userguide/creating-trail-organization.html) · [Log file integrity validation](https://docs.aws.amazon.com/awscloudtrail/latest/userguide/cloudtrail-log-file-validation-intro.html) · [S3 Object Lock](https://docs.aws.amazon.com/AmazonS3/latest/userguide/object-lock.html)
</details>

<details><summary><strong>Q10</strong> Show answer</summary>

**Correct: C**

- **Why:** **Multi-Region keys** share key material and key ID across Regions. Data encrypted with the primary in `us-east-1` can be decrypted with the replica in `eu-west-1` (and vice versa) using **only the local KMS endpoint**, so neither Region depends on the other. This is the canonical MRK use case for client-side encryption with DynamoDB global tables.
- **A:** This creates a cross-Region dependency. If `us-east-1` is unavailable, `eu-west-1` can't decrypt.
- **B:** Items written in one Region would be encrypted under a key the other Region's keyring doesn't contain, so they couldn't be decrypted locally.
- **D:** Server-side encryption at rest doesn't meet the **client-side** requirement. The tokens would be visible in plaintext to anyone with DynamoDB read access.
- **References:** [Multi-Region keys](https://docs.aws.amazon.com/kms/latest/developerguide/multi-region-keys-overview.html) · [AWS Database Encryption SDK](https://docs.aws.amazon.com/database-encryption-sdk/latest/devguide/what-is-database-encryption-sdk.html)
</details>

---

## 10. References

**KMS & encryption**
- [AWS KMS Developer Guide](https://docs.aws.amazon.com/kms/latest/developerguide/overview.html)
- [Key policies in AWS KMS](https://docs.aws.amazon.com/kms/latest/developerguide/key-policies.html) · [Default key policy](https://docs.aws.amazon.com/kms/latest/developerguide/key-policy-default.html)
- [Allowing users in other accounts to use a KMS key](https://docs.aws.amazon.com/kms/latest/developerguide/key-policy-modifying-external-accounts.html)
- [Grants in AWS KMS](https://docs.aws.amazon.com/kms/latest/developerguide/grants.html)
- [AWS KMS condition keys (kms:ViaService, encryption context)](https://docs.aws.amazon.com/kms/latest/developerguide/conditions-kms.html)
- [Rotate AWS KMS keys](https://docs.aws.amazon.com/kms/latest/developerguide/rotate-keys.html) · [On-demand rotation](https://docs.aws.amazon.com/kms/latest/developerguide/rotating-keys-on-demand.html)
- [Importing key material](https://docs.aws.amazon.com/kms/latest/developerguide/importing-keys.html)
- [Multi-Region keys](https://docs.aws.amazon.com/kms/latest/developerguide/multi-region-keys-overview.html)
- [Key stores overview](https://docs.aws.amazon.com/kms/latest/developerguide/key-store-overview.html) · [External key stores](https://docs.aws.amazon.com/kms/latest/developerguide/keystore-external.html) · [AWS CloudHSM key stores](https://docs.aws.amazon.com/kms/latest/developerguide/keystore-cloudhsm.html)
- [KMS request quotas](https://docs.aws.amazon.com/kms/latest/developerguide/requests-per-second.html)
- [AWS KMS pricing](https://aws.amazon.com/kms/pricing/)
- [AWS Encryption SDK](https://docs.aws.amazon.com/encryption-sdk/latest/developer-guide/introduction.html)
- [RDS encryption](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/Overview.Encryption.html) · [Aurora encryption](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/Overview.Encryption.html)
- [EBS encryption](https://docs.aws.amazon.com/ebs/latest/userguide/ebs-encryption.html)

**CloudHSM, secrets, certificates**
- [AWS CloudHSM User Guide](https://docs.aws.amazon.com/cloudhsm/latest/userguide/introduction.html) · [CloudHSM FIPS validation](https://docs.aws.amazon.com/cloudhsm/latest/userguide/fips-validation.html)
- [AWS Secrets Manager User Guide](https://docs.aws.amazon.com/secretsmanager/latest/userguide/intro.html)
- [AWS Systems Manager Parameter Store](https://docs.aws.amazon.com/systems-manager/latest/userguide/systems-manager-parameter-store.html)
- [AWS Certificate Manager User Guide](https://docs.aws.amazon.com/acm/latest/userguide/acm-overview.html) · [ACM pricing](https://aws.amazon.com/certificate-manager/pricing/)
- [ACM exportable public certificates announcement (June 2025)](https://aws.amazon.com/about-aws/whats-new/2025/06/aws-certificate-manager-public-certificates-use-anywhere)
- [ACM default validity change (Feb 2026)](https://aws.amazon.com/about-aws/whats-new/2026/02/aws-certificate-manager-updates-default)
- [AWS Private CA User Guide](https://docs.aws.amazon.com/privateca/latest/userguide/PcaWelcome.html)

**S3 data protection**
- [Protecting data with encryption (S3)](https://docs.aws.amazon.com/AmazonS3/latest/userguide/UsingEncryption.html)
- [S3 Bucket Keys](https://docs.aws.amazon.com/AmazonS3/latest/userguide/bucket-key.html)
- [Default SSE-C setting for new buckets FAQ](https://docs.aws.amazon.com/AmazonS3/latest/userguide/default-s3-c-encryption-setting-faq.html)
- [S3 Object Lock](https://docs.aws.amazon.com/AmazonS3/latest/userguide/object-lock.html)
- [S3 security best practices](https://docs.aws.amazon.com/AmazonS3/latest/userguide/security-best-practices.html)

**Perimeter**
- [AWS WAF Developer Guide](https://docs.aws.amazon.com/waf/latest/developerguide/waf-chapter.html) · [Intelligent threat mitigation](https://docs.aws.amazon.com/waf/latest/developerguide/waf-managed-protections.html)
- [AWS Shield Advanced](https://docs.aws.amazon.com/waf/latest/developerguide/shield-chapter.html) · [Shield pricing](https://aws.amazon.com/shield/pricing/)
- [AWS Firewall Manager](https://docs.aws.amazon.com/waf/latest/developerguide/fms-chapter.html) · [Firewall Manager prerequisites](https://docs.aws.amazon.com/waf/latest/developerguide/fms-prereq.html)
- [AWS Best Practices for DDoS Resiliency (whitepaper)](https://docs.aws.amazon.com/whitepapers/latest/aws-best-practices-ddos-resiliency/aws-best-practices-ddos-resiliency.html)

**Detection, response, compliance**
- [Amazon GuardDuty User Guide](https://docs.aws.amazon.com/guardduty/latest/ug/what-is-guardduty.html) · [Extended Threat Detection](https://docs.aws.amazon.com/guardduty/latest/ug/guardduty-extended-threat-detection.html)
- [AWS Security Hub (new)](https://docs.aws.amazon.com/securityhub/latest/userguide/what-is-securityhub-v2.html) · [Security Hub CSPM standards reference](https://docs.aws.amazon.com/securityhub/latest/userguide/standards-reference.html)
- [Amazon Inspector User Guide](https://docs.aws.amazon.com/inspector/latest/user/what-is-inspector.html)
- [Amazon Macie User Guide](https://docs.aws.amazon.com/macie/latest/user/what-is-macie.html)
- [Amazon Detective User Guide](https://docs.aws.amazon.com/detective/latest/userguide/detective-investigation-about.html)
- [Amazon Security Lake User Guide](https://docs.aws.amazon.com/security-lake/latest/userguide/what-is-security-lake.html)
- [AWS Config Developer Guide](https://docs.aws.amazon.com/config/latest/developerguide/WhatIsConfig.html) · [Remediation](https://docs.aws.amazon.com/config/latest/developerguide/remediation.html) · [Conformance packs](https://docs.aws.amazon.com/config/latest/developerguide/conformance-packs.html) · [Aggregators](https://docs.aws.amazon.com/config/latest/developerguide/aggregate-data.html)
- [AWS CloudTrail User Guide](https://docs.aws.amazon.com/awscloudtrail/latest/userguide/cloudtrail-user-guide.html) · [Network activity events](https://docs.aws.amazon.com/awscloudtrail/latest/userguide/logging-network-events-with-cloudtrail.html) · [CloudTrail Lake availability change](https://docs.aws.amazon.com/awscloudtrail/latest/userguide/cloudtrail-lake-service-availability-change.html)
- [AWS Backup Vault Lock](https://docs.aws.amazon.com/aws-backup/latest/devguide/vault-lock.html)
- [AWS Artifact](https://docs.aws.amazon.com/artifact/latest/ug/what-is-aws-artifact.html)
- [AWS Audit Manager availability change](https://docs.aws.amazon.com/audit-manager/latest/userguide/audit-manager-availability-change.html)
- [AWS Service Availability Updates, March 2026](https://aws.amazon.com/about-aws/whats-new/2026/03/aws-service-availability)
- [AWS Security Incident Response Guide](https://docs.aws.amazon.com/whitepapers/latest/aws-security-incident-response-guide/aws-security-incident-response-guide.html)
- [AWS Security Reference Architecture (Prescriptive Guidance)](https://docs.aws.amazon.com/prescriptive-guidance/latest/security-reference-architecture/welcome.html)
- [Building a data perimeter on AWS (whitepaper)](https://docs.aws.amazon.com/whitepapers/latest/building-a-data-perimeter-on-aws/building-a-data-perimeter-on-aws.html)

---
[← Previous: Chapter 05 — Edge](05-Edge-DNS-and-Content-Delivery.md) · [Index](00-README-Start-Here.md) · [Next: Chapter 07 — Compute →](07-Compute-Containers-and-Serverless.md)
