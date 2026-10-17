# Chapter 03 — Identity, Access Management & Federation
> **Exam mapping:** D1 Task 1.2 (security controls for organizational complexity), D2 Task 2.3 (security controls for new solutions), D3 Task 3.2 (improve security of existing solutions) | **Weight signal:** High. IAM logic shows up in a large share of questions, often as the deciding detail inside a networking, data or migration scenario | **Study time:** ~7 h
> [← Previous](02-Multi-Account-Governance.md) · [Index](00-README-Start-Here.md) · [Next →](04-Networking-VPC-and-Hybrid-Connectivity.md)

---

## 1. What the exam really tests here

SAP-C02 assumes you already know what a user, group, role and policy are. At Professional level the questions check whether you can **reason through the evaluation engine** and **pick the right identity architecture** for an organization with many accounts. In practice that means:

| Skill | Typical scenario signal |
|---|---|
| Predict an allow/deny decision across **SCP + RCP + resource policy + identity policy + boundary + session policy** | "A developer still receives AccessDenied even though the role's policy allows `s3:PutObject`…" |
| Choose **role assumption vs resource-based policy** for cross-account access | "Lambda in account A must read a DynamoDB table / S3 bucket / KMS key in account B" |
| Prevent the **confused deputy** problem | "Third-party SaaS vendor needs access to 300 customer accounts" / "service principal writes to our bucket" |
| Design **delegated administration** without privilege escalation | "Developers must create IAM roles for their Lambda functions but must not grant themselves more access" |
| Scale permissions with **ABAC** instead of hundreds of roles | "New projects are added weekly; the security team wants no policy changes per project" |
| Pick the **workforce identity** design | "5,000 employees in Okta / Entra ID / on-prem AD need SSO to 150 accounts with automatic provisioning" |
| Pick the **customer identity** design | "Mobile app users sign in with Google or Apple and upload directly to S3" |
| Pick the **directory** service | "Windows workloads need AD in three Regions" / "WorkSpaces must use on-prem AD credentials, no sync" |
| Remove **long-term credentials** | "On-prem servers and CI pipelines currently use IAM access keys" |
| Continuously **right-size** access | "Find unused permissions across the organization and block over-permissive policies in CI/CD" |

The usual differentiators between answer options are **"least operational overhead"**, **"no long-term credentials"**, **"centrally managed"** and **"scales to many accounts"**.

---

## 2. Core concepts & services: deep dive

### 2.1 IAM building blocks (quick Professional-level refresher)

| Concept | Key Professional facts |
|---|---|
| **Root user** | Unrestricted, and SCPs *do* restrict member-account root users (but not the management account). Use it only for root-only tasks. With **centralized root access management** (AWS Organizations + IAM), you can delete root credentials in member accounts and run short **privileged root sessions** (`sts:AssumeRoot`) from the management account or an IAM delegated admin to unlock a mis-configured S3 bucket policy or SQS queue policy, or to allow password recovery. New accounts created in Organizations then have no root credentials by default. |
| **IAM user** | Long-term identity (password and/or up to **2 access keys**). Treat as legacy for humans; use for break-glass or for third-party tools that cannot assume roles. |
| **IAM group** | A collection of users only. **Not a principal**, so it cannot appear in a `Principal` element. No nesting. |
| **IAM role** | Identity with no long-term credentials, assumed through STS. Has a **trust policy** (who may assume) and **permissions policies** (what the session may do). Max session duration setting is **1–12 h** (default 1 h). |
| **Role session** | The actual principal that makes requests: `arn:aws:sts::ACCOUNT:assumed-role/ROLE/SESSION`. |
| **Service-linked role (SLR)** | A role predefined and owned by an AWS service (`AWSServiceRoleFor…`). It trusts only that service and you cannot edit its permissions. **SCPs and RCPs do not restrict SLRs.** |
| **Service role** | A role you create that a service assumes (for example a Lambda execution role). You control its permissions, and handing it to the service requires `iam:PassRole`. |
| **Instance profile** | Container that delivers **one** role to an EC2 instance through IMDS. |

**Quotas worth knowing (IAM; verified on the IAM quotas page):**

| Item | Default | Max (auto-approved increase) |
|---|---|---|
| Roles per account | 1,000 | 10,000 |
| Customer managed policies per account | 1,500 | 10,000 |
| Managed policies attached per **role** | 20 | 25 |
| Managed policies attached per **user** | 10 | 20 |
| Managed policies attached per **group** | 10 | 10 |
| Role trust policy length | 2,048 chars | 8,192 chars |
| Managed policy size | 6,144 chars (fixed; whitespace not counted) | — |
| Inline policy aggregate size | user 2,048 · group 5,120 · role 10,240 chars (fixed) | — |
| Session policy | 1 inline JSON + up to **10 managed policy ARNs**, combined plaintext ≤ 2,048 chars | — |
| Session tags | up to **50**; key ≤ 128 chars, value ≤ 256 chars | — |
| External ID | 2–1,224 chars | — |
| STS request rate | 600 req/s per account per Region (shared across AssumeRole, GetCallerIdentity, GetFederationToken, GetSessionToken…) | support ticket |

> When the exam says "the role is hitting the policy size limit", the fix is to **consolidate into customer managed policies** (each 6,144 chars, up to 20/25 per role), use **wildcards/ABAC** to shrink statements, or split responsibilities across roles. Do not answer "increase the inline policy limit": that limit is fixed.

### 2.2 Policy types

| # | Policy type | Attached to | Grants? | Limits? | Notes |
|---|---|---|---|---|---|
| 1 | **Identity-based** (AWS managed, customer managed, inline) | Users, groups, roles | ✅ | — | The main way to grant. |
| 2 | **Resource-based** | Resources (S3 bucket, KMS key, SQS, SNS, Lambda, Secrets Manager, ECR, role **trust policy**, API Gateway, EventBridge bus, Backup vault, etc.) | ✅ | — | Has a `Principal` element. **Enables cross-account access without role assumption.** |
| 3 | **Permissions boundary** | Users, roles (not groups) | ❌ | ✅ | Max permissions for an identity-based grant. Managed policy only. |
| 4 | **SCP** (Organizations) | Root, OU, account | ❌ | ✅ | Limits **principals** in member accounts. Doesn't affect the management account or SLRs. See [Chapter 02](02-Multi-Account-Governance.md). |
| 5 | **RCP** (Organizations) | Root, OU, account | ❌ | ✅ | Limits access **to resources** in member accounts, whoever the caller is (including external principals). Supported for a subset of services (e.g., S3, STS, KMS, SQS, Secrets Manager, and more). See [Chapter 02](02-Multi-Account-Governance.md). |
| 6 | **Session policy** | Passed at `AssumeRole*` / `GetFederationToken` | ❌ | ✅ | Effective permissions = role/user identity policies ∩ session policy. Identity Center profiles and Roles Anywhere profiles use these too. |
| 7 | **ACLs** (S3 ACLs, legacy) | Resources | ✅ | — | Cross-account only, no JSON. With S3 **Object Ownership = Bucket owner enforced** (default for new buckets since April 2023), ACLs are disabled. |
| 8 | **VPC endpoint policies** | Gateway/interface endpoints | ❌ | ✅ | Act as an additional filter on requests that traverse the endpoint (a core data-perimeter control). |

**Key policy-language features that come up on the exam:**

- `NotAction` / `NotResource`: "everything except". Most often seen in **Deny** statements (e.g., region restriction that exempts global services). An `Allow` + `NotAction` is dangerous because it grants every action not listed, including future services.
- `NotPrincipal` with `Deny` is **discouraged**. Use `"Principal": "*"` plus a condition on `aws:PrincipalArn` / `aws:PrincipalAccount` / `aws:PrincipalOrgID`.
- **Condition operators**: `StringEquals`/`StringLike`, `ArnLike`, `IpAddress`, `Bool`, `Null`, `NumericLessThan`, `DateGreaterThan`; the `…IfExists` suffix; and set operators `ForAnyValue:` / `ForAllValues:` for multivalued keys (`aws:TagKeys`, `aws:PrincipalOrgPaths`). **Trap:** `ForAllValues` returns true when the key is *missing*, so pair it with a `Null` check if absence must fail.
- **Policy variables**: `${aws:username}`, `${aws:PrincipalTag/team}`, `${aws:userid}`, `${cognito-identity.amazonaws.com:sub}`, `${saml:sub}`, `${aws:PrincipalAccount}`.
- **Global condition keys you must know**:

| Key | Use |
|---|---|
| `aws:PrincipalOrgID` / `aws:PrincipalOrgPaths` | In resource policies: allow only principals from my org/OU. |
| `aws:ResourceOrgID` / `aws:ResourceAccount` | In identity or endpoint policies: allow only access to resources in my org. |
| `aws:SourceArn` / `aws:SourceAccount` / `aws:SourceOrgID` / `aws:SourceOrgPaths` | When a **service principal** acts on behalf of a resource/account/org (confused-deputy protection). |
| `aws:PrincipalIsAWSService`, `aws:ViaAWSService`, `aws:CalledVia` | Distinguish calls made *by* or *through* AWS services (e.g., exempt CloudFormation from a deny). |
| `aws:SourceIp` | Public source IP only. **Not present for requests through a VPC endpoint.** Use `aws:SourceVpce`, `aws:SourceVpc` or `aws:VpcSourceIp` instead. |
| `aws:RequestedRegion` | Region restriction. |
| `aws:MultiFactorAuthPresent` / `aws:MultiFactorAuthAge` | Require MFA (use `BoolIfExists`/`Null` patterns carefully). |
| `aws:SecureTransport` | Require TLS (classic S3 bucket policy deny). |
| `aws:PrincipalTag/…`, `aws:ResourceTag/…`, `aws:RequestTag/…`, `aws:TagKeys` | ABAC. |
| `aws:PrincipalArn` | Match the *role* ARN behind a session (wildcards allowed), e.g., exempt a break-glass role. |
| `aws:EC2InstanceSourceVPC`, `aws:EC2InstanceSourcePrivateIPv4`, `ec2:RoleDelivery` | Bind EC2 role credentials to the network they were issued in / to IMDSv2. |

### 2.3 Policy evaluation logic (single account)

The IAM User Guide documents this order:

1. **Explicit deny check** across *all* applicable policies (SCPs, RCPs, resource-based, identity-based, boundaries, session policies). Any matching `Deny` gives a final **Deny**.
2. **RCPs**: the resource's account/OU chain must allow it. `RCPFullAWSAccess` is auto-attached and can't be detached, so RCPs in practice act as deny lists.
3. **SCPs**: the principal's account/OU chain must allow it (every level from root to account).
4. **Resource-based policy**: in the **same account**, an allow here can be enough on its own (see the nuances below).
5. **Identity-based policy**: must allow, unless step 4 already granted to the user or session directly.
6. **Permissions boundary**: if present, it must allow.
7. **Session policy**: if present (role session or federated user), it must allow.

> The brief order "explicit deny → SCP → RCP → …" is often taught. The current documentation evaluates **RCPs before SCPs**. The order doesn't change the outcome: both are filters that must allow and neither grants anything.

```text
                         ┌──────────────────────────────┐
  Request ──────────────►│ 1. Any explicit DENY in any   │── yes ──► DENY (final)
                         │    applicable policy?         │
                         └──────────────┬───────────────┘
                                        │ no
                         ┌──────────────▼───────────────┐
                         │ 2. RCPs on resource's account │── no allow ──► DENY
                         │    chain allow?               │
                         └──────────────┬───────────────┘
                                        │ yes (or no RCPs)
                         ┌──────────────▼───────────────┐
                         │ 3. SCPs on principal's account│── no allow ──► DENY
                         │    chain allow? (all levels)  │
                         └──────────────┬───────────────┘
                                        │ yes (or mgmt acct / SLR)
                         ┌──────────────▼───────────────┐
                         │ 4. Resource-based policy      │── allows the USER ARN or
                         │    allows?                    │   the SESSION ARN directly ──► ALLOW
                         └──────────────┬───────────────┘   (same account only)
                                        │ no / allows ROLE ARN (continue)
                         ┌──────────────▼───────────────┐
                         │ 5. Identity-based policy      │── no allow (and no
                         │    allows?                    │   resource-policy allow) ──► DENY
                         └──────────────┬───────────────┘
                                        │ yes (or resource policy allowed role ARN)
                         ┌──────────────▼───────────────┐
                         │ 6. Permissions boundary set?  │── yes, doesn't allow ──► DENY
                         └──────────────┬───────────────┘
                                        │ allows / none
                         ┌──────────────▼───────────────┐
                         │ 7. Session principal with     │── yes, doesn't allow ──► DENY
                         │    session policy?            │
                         └──────────────┬───────────────┘
                                        │ allows / none
                                        ▼
                                      ALLOW
```

**Same-account resource-based policy nuances (popular in tricky questions):**

| Resource policy names… | Is the grant limited by an implicit deny in identity policy / boundary / session policy? |
|---|---|
| **IAM user ARN** | Not limited by identity policy or boundary. The resource policy alone grants. |
| **Role session ARN** (`assumed-role/…/session`) | Not limited. Granted directly to the session. |
| **Role ARN** (`role/…`) or `aws:PrincipalArn` condition | **Limited by boundary and session policy** (the requester is the session, not the role). |
| **Federated user ARN** (`federated-user/…`, from GetFederationToken) | Not limited. |
| **Account** (`arn:aws:iam::111122223333:root`) | Delegates to the account, so the identity policy must also allow. |

**Exceptions:** **IAM role trust policies and KMS key policies** must explicitly allow the principal, even within the same account. For KMS, the key policy must allow either the principal directly or the account (`:root`, which "enables IAM policies"). An IAM policy alone never grants KMS access unless the key policy delegates to the account.

### 2.4 Cross-account evaluation

For a request from principal in **trusted account A** to a resource in **trusting account B**, AWS runs **two evaluations** and both must return Allow:

- **Account A** (principal side): SCPs on A, identity policies, permissions boundary, session policy. **The identity policy must explicitly allow the action on B's resource ARN.**
- **Account B** (resource side): RCPs on B, plus the **resource-based policy** that must explicitly allow A's principal (or account).

```text
  Account A (trusted)                         Account B (trusting)
  ┌────────────────────────────┐              ┌────────────────────────────┐
  │ SCPs on A's OU chain        │              │ RCPs on B's OU chain        │
  │ Identity policy  ──allow──┐ │   request    │ Resource policy ──allow──┐  │
  │ Permissions boundary      │ │ ───────────► │ (Principal = A role/acct)│  │
  │ Session policy            │ │              │ KMS key policy if SSE-KMS│  │
  └───────────────────────────┼─┘              └──────────────────────────┼──┘
                              └──────────── BOTH must Allow ──────────────┘
```

| Aspect | Same account | Cross-account |
|---|---|---|
| Resource policy alone sufficient? | Yes for user/session principals (except role trust and KMS) | **No.** The caller's identity policy must also allow |
| Identity policy alone sufficient? | Yes (resource policy optional for most services) | **No.** The resource needs a resource policy, or the caller assumes a role in B |
| SCPs considered | Principal's account | Principal's account (A). B's SCPs **don't** apply to A's principals |
| RCPs considered | Resource's account | Resource's account (B), even for external callers |
| Permissions used after role assumption | n/a | Only the **assumed role's** permissions. Caller gives up its own (important for "copy from A's bucket to B's bucket") |

### 2.5 Cross-account access patterns

**Pattern A: Role assumption (trust policy).** A principal in A calls `sts:AssumeRole` on a role in B. Both sides must allow:
1. B's role **trust policy** names A (account root, a specific role, or uses `aws:PrincipalOrgID`).
2. A's principal has `sts:AssumeRole` on B's role ARN in its identity policy.

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Sid": "TrustOpsRoleFromToolingAccount",
    "Effect": "Allow",
    "Principal": { "AWS": "arn:aws:iam::111111111111:role/ops-automation" },
    "Action": ["sts:AssumeRole", "sts:TagSession", "sts:SetSourceIdentity"],
    "Condition": {
      "StringEquals": { "aws:PrincipalOrgID": "o-a1b2c3d4e5" }
    }
  }]
}
```

> **Trap:** if a trust policy names a specific role ARN and that role is **deleted and recreated**, the trust breaks. IAM stores the principal's unique ID (`AROA…`), and the policy then shows the ID instead of the ARN. Re-save the trust policy.
> If you trust `arn:aws:iam::111111111111:root`, you trust **every principal in A that A's admins allow** to call `sts:AssumeRole`. That is fine for your own accounts but too broad for third parties.

**Pattern B: Resource-based policy.** B attaches a policy to the resource that names A's principal. The caller **keeps its own identity and permissions**, which matters when one process must read from A's resource and write to B's resource in the same operation (e.g., S3 copy, or SQS consume and S3 write). Services include S3, KMS, SQS, SNS, Lambda (function policy), Secrets Manager, ECR, EventBridge, Glue Data Catalog, Backup vaults, OpenSearch, API Gateway, CloudWatch Logs destinations, and others.

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Sid": "OrgReadOnlyToSharedArtifacts",
    "Effect": "Allow",
    "Principal": "*",
    "Action": ["s3:GetObject", "s3:ListBucket"],
    "Resource": [
      "arn:aws:s3:::corp-shared-artifacts",
      "arn:aws:s3:::corp-shared-artifacts/*"
    ],
    "Condition": {
      "StringEquals": { "aws:PrincipalOrgID": "o-a1b2c3d4e5" }
    }
  }]
}
```

**Pattern C: AWS RAM sharing.** For resources that don't use resource policies, such as subnets (VPC sharing), Transit Gateways, Route 53 Resolver rules, License Manager configurations, Aurora clusters (cloning), Private CA, and IPAM pools. Covered in chapters 02 and 04.

**When each is needed**

| Need | Use |
|---|---|
| Console access to another account | **Role** (Switch Role / Identity Center) |
| Caller must use its own permissions on two accounts' resources at once | **Resource-based policy** |
| Service has no resource policy (EC2, RDS APIs, CloudFormation) | **Role** |
| Thousands of external accounts, simple grant (e.g., public dataset, org-wide bucket) | Resource policy with `aws:PrincipalOrgID` |
| Third-party SaaS | **Role + ExternalId** |
| Share network/infra objects | **AWS RAM** |

**S3 cross-account object ownership.** Historically, an object uploaded by account A into B's bucket was **owned by A**. B could not read it unless A granted access through an ACL (`bucket-owner-full-control`). Today:
- **Bucket owner enforced** (default for new buckets since April 2023): ACLs disabled, the bucket owner owns every object, and access is controlled only by policies. Switching an existing bucket to this setting makes the bucket owner the owner of existing objects too. **This is the recommended fix for "account B can't read objects that account A wrote".**
- **Bucket owner preferred**: the bucket owner takes ownership if the uploader sends the `bucket-owner-full-control` ACL. Uploaders can be forced to send it through a bucket policy condition on `s3:x-amz-acl`.
- **Object writer**: legacy behaviour.

**KMS cross-account requires both sides.** Key-policy details are in [Chapter 06](06-Security-Data-Protection-and-Threat-Detection.md).
1. **Key policy in the key-owning account** allows the external account or role.
2. **IAM policy in the external account** allows the KMS actions on the **key ARN** (aliases don't work cross-account in policy resources).

```json
{
  "Sid": "AllowAccountBUseOfKey",
  "Effect": "Allow",
  "Principal": { "AWS": "arn:aws:iam::222222222222:root" },
  "Action": ["kms:Decrypt", "kms:DescribeKey", "kms:GenerateDataKey*", "kms:ReEncrypt*"],
  "Resource": "*"
}
```
```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": ["kms:Decrypt", "kms:DescribeKey", "kms:GenerateDataKey*"],
    "Resource": "arn:aws:kms:eu-west-1:111111111111:key/1234abcd-12ab-34cd-56ef-1234567890ab"
  }]
}
```

> **Classic trap:** resources encrypted with an **AWS managed key** (`aws/s3`, `aws/ebs`, `aws/rds`) **cannot be shared cross-account**, because you can't edit that key's policy. To share an encrypted EBS/RDS snapshot or an SSE-KMS S3 object cross-account, encrypt (or re-encrypt/copy) with a **customer managed key** and share the key.

### 2.6 External ID and the confused-deputy problem

**Cross-account confused deputy:** a SaaS vendor ("deputy") assumes roles in many customer accounts. Customer X discovers customer Y's role ARN (ARNs are not secrets), registers it with the vendor as its own, and the vendor unknowingly accesses Y's account. **Fix:** the vendor generates a **unique External ID per customer** (the vendor controls it, not the customer) and always passes it in `AssumeRole`. The customer's trust policy requires it:

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Sid": "AllowVendorWithExternalId",
    "Effect": "Allow",
    "Principal": { "AWS": "arn:aws:iam::999988887777:role/VendorIngestionRole" },
    "Action": "sts:AssumeRole",
    "Condition": {
      "StringEquals": { "sts:ExternalId": "c7f1e2a4-5b9d-4e8a-9f3c-0d2b6a1e7c55" }
    }
  }]
}
```

Notes:
- External ID is **not a secret** or a password. Its purpose is to make the deputy act in the right context.
- It's for **third parties**. Within your own organization, use `aws:PrincipalOrgID` / specific role ARNs instead.
- Deploy the role to many accounts with **CloudFormation StackSets** (service-managed, auto-deploy to new accounts in the OU).

**Cross-service confused deputy:** when you grant an **AWS service principal** (e.g., `cloudtrail.amazonaws.com`, `s3.amazonaws.com`, `sns.amazonaws.com`, `config.amazonaws.com`) access to your resource, the policy authorizes the *service*, not the customer who configured it. Anyone could point their own trail or bucket notification at your resource. Restrict it with:

| Key | Restricts the service to act on behalf of… |
|---|---|
| `aws:SourceArn` | a specific resource (trail, bucket, topic, fleet) |
| `aws:SourceAccount` | a specific account |
| `aws:SourceOrgID` | any account in your organization |
| `aws:SourceOrgPaths` | a specific OU path |

```json
{
  "Sid": "AllowS3EventsFromOurBucketOnly",
  "Effect": "Allow",
  "Principal": { "Service": "s3.amazonaws.com" },
  "Action": "sns:Publish",
  "Resource": "arn:aws:sns:us-east-1:111122223333:uploads-topic",
  "Condition": {
    "ArnLike":      { "aws:SourceArn": "arn:aws:s3:::uploads-bucket-prod" },
    "StringEquals": { "aws:SourceAccount": "111122223333" }
  }
}
```

> S3 bucket ARNs contain **no account ID**, so always add `aws:SourceAccount` alongside `aws:SourceArn` when the source is a bucket.
> **At scale:** apply an **RCP** that denies service-principal access unless `aws:SourceOrgID` equals your org, conditioned on `aws:PrincipalIsAWSService = true` and `aws:SourceAccount` being present. This gives one control for all S3 buckets in member accounts. **An SCP cannot do this**, because SCPs don't apply to service principals.

### 2.7 ABAC vs RBAC

| | **RBAC** (role-based) | **ABAC** (attribute-based) |
|---|---|---|
| Model | A role/policy per job function per resource set | Policies compare **principal tags** with **resource tags** |
| Growth | New project → new roles/policies | New project → just tag resources and users |
| Policy count | Grows with projects × functions | Small, static |
| Granularity | Resource ARNs | Tags (need consistent tagging) |
| Best for | Small, stable environments; services without tag-based auth | Fast-growing orgs, many teams, federated identities with directory attributes |
| Weakness | Policy sprawl, size limits | Requires tag governance (tag policies, deny re-tagging), and not every action supports `aws:ResourceTag` |

**Sources of principal tags:**
- IAM role/user tags (`aws:PrincipalTag`).
- **Session tags** passed through `AssumeRole` (`Tags`), SAML (`https://aws.amazon.com/SAML/Attributes/PrincipalTag:<key>`), OIDC JWT (`https://aws.amazon.com/tags` claim), Identity Center *attributes for access control*, Cognito identity pools (*attributes for access control*), and Roles Anywhere (certificate subject/issuer/SAN mapped to tags).
- The trust policy must allow **`sts:TagSession`**. Without it, assumption fails when tags are passed.
- Session tags **override** role tags with the same key. Up to 50 per session. Single-valued only.
- **Transitive tags** (`TransitiveTagKeys`) persist through **role chaining** and can't be overridden later in the chain. Use them to carry `department`/`project` from a SAML login through a jump role into a workload role.

**ABAC example: Secrets Manager scoped by `project` tag:**

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "UseSecretsOfMyProject",
      "Effect": "Allow",
      "Action": ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret",
                 "secretsmanager:PutSecretValue", "secretsmanager:UpdateSecret"],
      "Resource": "*",
      "Condition": { "StringEquals": { "aws:ResourceTag/project": "${aws:PrincipalTag/project}" } }
    },
    {
      "Sid": "CreateOnlyWithMyProjectTag",
      "Effect": "Allow",
      "Action": ["secretsmanager:CreateSecret", "secretsmanager:TagResource"],
      "Resource": "*",
      "Condition": {
        "StringEquals": { "aws:RequestTag/project": "${aws:PrincipalTag/project}" },
        "ForAllValues:StringEquals": { "aws:TagKeys": ["project", "cost-center", "Name"] }
      }
    },
    {
      "Sid": "NoRetaggingOtherProjectsResources",
      "Effect": "Deny",
      "Action": ["secretsmanager:TagResource", "secretsmanager:UntagResource"],
      "Resource": "*",
      "Condition": {
        "ForAnyValue:StringEquals": { "aws:TagKeys": ["project"] },
        "Null": { "aws:ResourceTag/project": "false" },
        "StringNotEquals": { "aws:ResourceTag/project": "${aws:PrincipalTag/project}" }
      }
    }
  ]
}
```

ABAC hygiene: (1) principals must not be able to change their **own** tags. Deny `iam:TagRole`/`iam:UntagRole`/`iam:TagUser` and source tags from the IdP. (2) Enforce tag keys/values with **tag policies** and require tags on create (`aws:RequestTag` + `Null`). (3) Check that the actions you need support `aws:ResourceTag` in the Service Authorization Reference.

### 2.8 Permissions boundaries and delegated administration

A **permissions boundary** is a managed policy set on a user or role that defines the **maximum** permissions its identity-based policies can grant. Effective permissions = identity policy ∩ boundary (∩ SCP ∩ session policy). A boundary grants nothing on its own.

**The classic exam pattern:** *"Developers must be able to create IAM roles for their Lambda functions/EC2 instances but must not be able to create roles more powerful than allowed or escalate their own privileges."*

The ingredients:
1. A boundary policy (`AppWorkloadBoundary`) listing the maximum allowed services/actions.
2. The developer's identity policy allows `iam:CreateRole` (and related policy changes) **only when** `iam:PermissionsBoundary` equals that boundary's ARN.
3. Developers can create/modify only roles under a **path** (e.g., `/app/`) and can **pass** only those roles (`iam:PassRole`).
4. Explicit denies stop developers from editing/deleting the boundary policy or removing boundaries.
5. The developer's own role sits outside `/app/` and is managed by the platform team, so they can't modify it.

Boundary for workload roles:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "MaxWorkloadPermissions",
      "Effect": "Allow",
      "Action": ["s3:*", "dynamodb:*", "sqs:*", "sns:*", "logs:*",
                 "cloudwatch:PutMetricData", "xray:Put*", "kms:Decrypt", "kms:GenerateDataKey"],
      "Resource": "*"
    },
    {
      "Sid": "StayInApprovedRegions",
      "Effect": "Deny",
      "Action": "*",
      "Resource": "*",
      "Condition": { "StringNotEquals": { "aws:RequestedRegion": ["eu-west-1", "eu-central-1"] } }
    }
  ]
}
```

Developer identity policy (attached to the developer role/permission set):

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "CreateAndChangeAppRolesOnlyWithBoundary",
      "Effect": "Allow",
      "Action": ["iam:CreateRole", "iam:PutRolePermissionsBoundary",
                 "iam:AttachRolePolicy", "iam:DetachRolePolicy",
                 "iam:PutRolePolicy", "iam:DeleteRolePolicy"],
      "Resource": "arn:aws:iam::111122223333:role/app/*",
      "Condition": {
        "StringEquals": { "iam:PermissionsBoundary": "arn:aws:iam::111122223333:policy/AppWorkloadBoundary" }
      }
    },
    {
      "Sid": "ManageAppRoles",
      "Effect": "Allow",
      "Action": ["iam:GetRole", "iam:ListRolePolicies", "iam:ListAttachedRolePolicies",
                 "iam:TagRole", "iam:UpdateAssumeRolePolicy", "iam:DeleteRole"],
      "Resource": "arn:aws:iam::111122223333:role/app/*"
    },
    {
      "Sid": "PassOnlyAppRoles",
      "Effect": "Allow",
      "Action": "iam:PassRole",
      "Resource": "arn:aws:iam::111122223333:role/app/*"
    },
    {
      "Sid": "ProtectTheBoundaryPolicy",
      "Effect": "Deny",
      "Action": ["iam:CreatePolicyVersion", "iam:DeletePolicy",
                 "iam:DeletePolicyVersion", "iam:SetDefaultPolicyVersion"],
      "Resource": "arn:aws:iam::111122223333:policy/AppWorkloadBoundary"
    },
    {
      "Sid": "NeverRemoveBoundaries",
      "Effect": "Deny",
      "Action": ["iam:DeleteRolePermissionsBoundary", "iam:DeleteUserPermissionsBoundary"],
      "Resource": "*"
    }
  ]
}
```

| Control | Limits | Where it's set | Typical use |
|---|---|---|---|
| **SCP** | Principals in an account/OU | Organizations | Org-wide guardrails (regions, disable services, protect security tooling) |
| **RCP** | Access to resources in an account/OU | Organizations | Data perimeter, so external identities can't reach resources |
| **Permissions boundary** | One user/role | IAM, per entity | Delegated IAM admin inside an account |
| **Session policy** | One session | At assume time | Broker/vending app narrows a broad role per request |

### 2.9 AWS STS: APIs, durations and chaining

| API | Who calls | Duration (min / default / max) | MFA | Session policy | Notes |
|---|---|---|---|---|---|
| **AssumeRole** | IAM user or role session | 15 m / 1 h / role's max (1–12 h) | ✅ (SerialNumber+TokenCode) | ✅ | Cross-account, privilege elevation, custom brokers. Supports ExternalId, session tags, SourceIdentity. |
| **AssumeRoleWithSAML** | Anyone with a valid SAML assertion (unsigned call) | 15 m / 1 h / role's max | via IdP | ✅ | Direct SAML 2.0 federation to IAM roles. Assertion ≤ 100,000 chars base64. |
| **AssumeRoleWithWebIdentity** | Anyone with a valid OIDC JWT (unsigned call) | 15 m / 1 h / role's max | via IdP | ✅ | GitHub Actions, EKS IRSA, Google, Cognito identity pools (basic flow). |
| **GetFederationToken** | IAM user (or root) | IAM user: 15 m / 12 h / **36 h**. Root: max 1 h | ❌ | ✅ (needed to grant anything) | Legacy custom broker. Resulting creds **can't call IAM** (API/CLI) or STS except `GetCallerIdentity`. Can't chain roles. |
| **GetSessionToken** | IAM user (or root) | IAM user: 15 m / 12 h / 36 h. Root: max 1 h | ✅ | ❌ | Get MFA-flagged creds for a user. Can't call IAM unless MFA was included. |
| **AssumeRoot** | Mgmt account / IAM delegated admin (centralized root access) | short-lived (task-scoped) | — | Task policy | Privileged root tasks in member accounts. |
| **GetWebIdentityToken** (outbound federation) | AWS principals with `sts:GetWebIdentityToken` | 60 s–3,600 s (default 300 s) | — | — | Mints a signed JWT for **external** (non-AWS) services. Must be enabled per account. Not usable for `AssumeRoleWithWebIdentity` into AWS. |

**Role chaining:** using role-session credentials to assume another role. **The chained session is limited to a maximum of 1 hour**, whatever the target role's max session duration. Requesting more (`DurationSeconds` > 3600) fails. Examples that count as chaining: EC2 instance role → AssumeRole into another account; Identity Center session → Switch Role in console; Lambda execution role → AssumeRole. Fixes: let the SDK **auto-refresh** credentials, grant access through **resource-based policies** so no second hop is needed, or redesign so the first hop is the federated one (SAML/OIDC → target role directly, up to 12 h).

**Source identity** (`sts:SetSourceIdentity`): a value (e.g., the corporate username) set at the first assumption. It **persists through role chaining and can't be changed**, and it appears in CloudTrail, so it gives you attribution across shared roles. Can be required with `sts:SourceIdentity` conditions.

**STS endpoints:** prefer **Regional endpoints** (lower latency, Regional isolation). Credentials obtained from a Regional endpoint work in all Regions. The quota is per account per Region.

**Revoking active sessions:** temporary credentials can't be "deleted". Use **Revoke active sessions** on the role, which attaches an inline deny on `aws:TokenIssueTime` earlier than now. Then rotate/fix the root cause.


### 2.10 AWS IAM Identity Center (successor to AWS SSO)

Exam questions may say "AWS SSO" or "AWS Single Sign-On". It's the same service, now called **IAM Identity Center**. It is AWS's recommended **workforce** identity front door for multi-account access and AWS-managed applications.

**Instance types**
- **Organization instance**: enabled in the Organizations **management account**, one per organization. It is the only type that can grant **multi-account AWS access**. Register a **delegated administrator** (a member account) so day-to-day admin happens outside the management account. The delegated admin **cannot manage permission sets provisioned to the management account**; those stay with the management account.
- **Account instance**: standalone, bound to a single account. Supports **AWS managed applications only**, *not* AWS account access. It exists for isolated app use or for teams without org access.

**Identity source: exactly one at a time**

| Identity source | How users/groups get there | Authentication | When |
|---|---|---|---|
| **Identity Center directory** (built-in) | Created in Identity Center | Identity Center (supports MFA) | Small orgs, no corporate IdP, sandbox |
| **Active Directory**: AWS Managed Microsoft AD, or self-managed AD through **AD Connector** (or a two-way trust from Managed AD) | **Configurable AD sync** of selected users/groups | Against AD | Corporate AD is the source of truth |
| **External IdP** (Okta, Microsoft Entra ID, Ping, OneLogin, Google Workspace, …) | **SCIM 2.0** automatic provisioning (or manual creation with matching usernames) | **SAML 2.0** at the IdP | Most enterprises. Recommended when a cloud IdP exists |

> **SAML authenticates, SCIM provisions.** Answers that say "SAML will create the users and groups automatically" are wrong for Identity Center. You need **SCIM** (or AD sync) so groups exist and can be assigned before first login.
> Changing the identity source can remove existing users/groups and their assignments. Plan migrations carefully.

**Permission sets and account assignments**
- A **permission set** is a template: AWS managed policies, **customer managed policy references** (by name/path; the policy must already exist in every target account, typically deployed with StackSets), an inline policy, an optional **permissions boundary**, a **session duration** (1–12 h, default 1 h), and an optional relay state URL.
- An **account assignment** = (user or group) + permission set + AWS account. When assigned, Identity Center **provisions an IAM role** named `AWSReservedSSO_<PermissionSet>_<hash>` in that account. Don't edit these roles directly. Change the permission set and re-provision.
- Assign **groups**, not users. Automate assignments with the API, CloudFormation, or Terraform from the delegated admin account.
- Users sign in through the **AWS access portal**, getting console access or short-term CLI credentials (`aws configure sso`, with automatic refresh).
- **Resource policies** that must reference Identity Center users should match the role with an `aws:PrincipalArn` wildcard such as `arn:aws:iam::*:role/aws-reserved/sso.amazonaws.com/*AWSReservedSSO_DataAnalyst_*`. The hash suffix is not predictable, so don't hard-code the full role ARN.

**ABAC in Identity Center ("attributes for access control")**
- Map user attributes (from the Identity Center store, AD, or the IdP's SAML assertion through `https://aws.amazon.com/SAML/Attributes/AccessControl:<key>`) to **session tags**.
- Permission-set policies then reference `${aws:PrincipalTag/costCenter}` etc. One permission set serves every team: **fewer permission sets, same least privilege**.

**Trusted identity propagation (TIP)**
- Carries the **end user's identity** (not just a role) from a client application to AWS data services such as Amazon Redshift, Athena, EMR, Lake Formation, **S3 Access Grants**, Amazon Quick (QuickSight) and Amazon Q Business.
- Gives per-user authorization in the data layer (e.g., Lake Formation grants to directory groups) and **user-level CloudTrail auditing**.
- Exam signal: "auditors must see which corporate user queried the data, not just the shared IAM role", or "grant S3 prefix access to directory groups".

**Resilience:** an organization instance is homed in one primary Region. Since 2026, Identity Center can **replicate an organization instance to additional Regions**, each with its own access portal endpoint. It requires a **multi-Region customer managed KMS key**, and administration (assignments, group memberships) stays in the primary Region. Even with replication, keep **break-glass IAM principals** (MFA, credentials in a safe, alarms on use) in case Identity Center or the IdP is unavailable. *(This is a newer feature, unlikely to be core on SAP-C02.)*

### 2.11 Direct SAML 2.0 federation to IAM (legacy, still tested)

Before Identity Center, enterprises set up **an IAM SAML identity provider in every account** plus roles trusting it:

```text
 User ──► Corporate IdP (AD FS / Okta) ──SAML assertion (Role + Provider ARN pairs)──►
     https://signin.aws.amazon.com/saml ──► STS AssumeRoleWithSAML ──► console / credentials
```

- The trust policy principal is `{"Federated": "arn:aws:iam::ACCOUNT:saml-provider/ADFS"}`, action `sts:AssumeRoleWithSAML`, with condition `SAML:aud = https://signin.aws.amazon.com/saml`.
- The assertion lists permitted roles (`https://aws.amazon.com/SAML/Attributes/Role`) and can pass `RoleSessionName`, `SessionDuration`, `PrincipalTag:*`, `TransitiveTagKeys` and `SourceIdentity`.
- **Still valid when:** a single account, a specific per-account need, or an existing estate that hasn't migrated. **For many accounts, Identity Center wins** (one IdP integration, central assignments, CLI support, no per-account IdP setup).
- **Custom identity broker (very legacy):** an app authenticates users against a corporate directory, then calls `AssumeRole` or `GetFederationToken`, and optionally builds a console sign-in URL through the federation endpoint. Choose it only when SAML/OIDC is impossible.

**OIDC federation for workloads (modern, high-value):** CI/CD systems such as GitHub Actions, GitLab and Azure DevOps, and Kubernetes (EKS IRSA), exchange their OIDC tokens for role credentials, so there are **no stored access keys**.

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "Federated": "arn:aws:iam::111122223333:oidc-provider/token.actions.githubusercontent.com" },
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": {
        "token.actions.githubusercontent.com:aud": "sts.amazonaws.com",
        "token.actions.githubusercontent.com:sub": "repo:example-org/payments-api:ref:refs/heads/main"
      }
    }
  }]
}
```

> Always constrain `sub` (repo/branch/environment). A trust policy that only checks `aud` lets **any** GitHub repository assume your role.
> EKS: **EKS Pod Identity** (`pods.eks.amazonaws.com` principal, `sts:AssumeRole` + `sts:TagSession`) is simpler than IRSA. There's no OIDC provider per cluster and roles can be reused across clusters.

### 2.12 Amazon Cognito: user pools vs identity pools

| | **User pools** | **Identity pools** (federated identities) |
|---|---|---|
| What | **User directory + OIDC/OAuth 2.0 IdP** for your app's customers | **Credential broker**: exchanges identity tokens for **temporary AWS credentials** (STS) |
| Output | JWTs: ID token, access token, refresh token | Temporary AWS credentials for an IAM role |
| Sign-in sources | Native username/password, passwordless, social (Google, Facebook, Apple, Amazon), **SAML** and **OIDC** enterprise IdPs | Cognito user pools, social IdPs, any OIDC or SAML provider, **developer-authenticated identities**, and **guest (unauthenticated)** access |
| Use to call | Your APIs: API Gateway Cognito authorizer, ALB authentication, AppSync, your own backend, Verified Permissions | AWS services directly from the client: S3, DynamoDB, IoT, Kinesis, Location, etc. |
| Notable features | Managed login/hosted UI, MFA, Lambda triggers (pre-sign-up, pre-token-generation, user migration…), groups (with IAM roles), custom attributes, M2M client-credentials grant, threat protection on the **Plus** tier (feature tiers: Lite / Essentials / Plus) | Role mapping, ABAC through principal tags, guest role |

**When to use which**
- **Sign-in for a web/mobile app calling your own API** → **user pool** only.
- **App must call AWS services directly** (upload to S3, write to DynamoDB) → **identity pool** (usually with a user pool as the IdP).
- **Guest browsing with limited AWS access** → identity pool **unauthenticated role**.
- **Enterprise customers bring their own SAML IdP into your SaaS app** → user pool with a SAML IdP per tenant.
- **Workforce SSO into AWS accounts** → **not Cognito**; use **IAM Identity Center**.

**Identity pool role selection**
- **Default authenticated role** and **unauthenticated (guest) role**.
- **Rules-based mapping**: match a token claim (`Equals`, `NotEqual`, `StartsWith`, `Contains`) to a role. Up to **25 rules per provider** (not adjustable), first match wins.
- **Token-based**: use `cognito:preferred_role` / `cognito:roles` from **user pool groups** (group precedence decides the preferred role).
- **Ambiguous role resolution**: use the default authenticated role, or deny the request.
- Role trust policies use `"Principal": {"Federated": "cognito-identity.amazonaws.com"}`, `sts:AssumeRoleWithWebIdentity`, and conditions `cognito-identity.amazonaws.com:aud = <identity pool ID>` and `cognito-identity.amazonaws.com:amr = authenticated` (or `unauthenticated`).
- **Per-user S3 prefix:** `"Resource": "arn:aws:s3:::app-bucket/private/${cognito-identity.amazonaws.com:sub}/*"`.
- Authentication flows: **enhanced (simplified)** = `GetId` → `GetCredentialsForIdentity` (recommended). **Basic (classic)** = `GetId` → `GetOpenIdToken` → `AssumeRoleWithWebIdentity` (off by default).
- Never map **user-modifiable attributes** to privileged roles.

### 2.13 AWS Directory Service

| | **AWS Managed Microsoft AD** | **AD Connector** | **Simple AD** |
|---|---|---|---|
| What | Real Windows Server AD managed by AWS (2 DCs in 2 AZs by default; add DCs to scale) | **Proxy** to your existing self-managed AD. Stores no directory data in AWS | Samba 4 AD-*compatible* directory |
| Size | Standard ≈ 30,000 objects (~5,000 users). Enterprise ≈ 500,000 objects | Small / Large | Small ≤ 500 users (~2,000 objects). Large ≤ 5,000 users (~20,000 objects) |
| Trusts with other domains | ✅ one-way/two-way **forest or external trusts** with on-prem AD | n/a (it *is* your AD) | ❌ |
| MFA | ✅ RADIUS | ✅ RADIUS (your existing MFA) | ❌ |
| Multi-Region replication | ✅ **Enterprise Edition only**. The primary Region must be a default (non-opt-in) Region. Replicates users, groups, GPOs, trusts and schema with the same directory ID | ❌ (deploy per Region; depends on on-prem DCs) | ❌ |
| Share across accounts | ✅ **Directory sharing** (Organizations or handshake) for seamless domain join | ❌ (one per account/VPC) | ❌ |
| RDS for SQL Server / FSx for Windows | ✅ | ❌ (RDS for SQL Server not supported) | ❌ |
| Schema extensions, LDAPS, gMSA, recycle bin | ✅ | n/a | ❌ |
| IAM Identity Center identity source | ✅ | ✅ | ❌ |
| WorkSpaces, Amazon Quick, console access | ✅ | ✅ | ✅ |
| Availability note | — | — | **No longer open to new customers.** Existing customers keep full functionality |

- **AWS Managed Microsoft AD (Hybrid Edition)** (launched August 2025): extends your **existing self-managed domain** into AWS. AWS-managed DCs join your domain and replicate with on-prem DCs, keeping the same forest. Prerequisites include single forest/single domain and network connectivity. It's an alternative to a separate domain plus trust.
- **Decision rules:**
  - "Use existing on-prem AD credentials for WorkSpaces/console/EC2 domain join, no directory data in AWS, minimal cost" → **AD Connector** (needs VPN/DX to on-prem DCs; if the link fails, authentication fails).
  - "AWS-side directory for workloads, plus on-prem users reaching AWS apps with existing credentials" → **Managed Microsoft AD + forest trust**. Logons by on-prem users through a trust still need on-prem DCs to be reachable.
  - "On-prem users must still authenticate in AWS when the on-prem DCs are unreachable" → put DCs of the **same domain** in AWS: **Hybrid Edition** or self-managed DCs on EC2.
  - "Global Windows workloads, local AD latency in several Regions, managed" → **Managed Microsoft AD Enterprise + multi-Region replication**.
  - "RDS for SQL Server Windows authentication" → **Managed Microsoft AD** (directly, or with a trust to on-prem).
  - "Full control of AD (Enterprise/Schema Admin rights, unsupported features)" → **self-managed AD on EC2**.

### 2.14 IAM Access Analyzer

| Capability | What it does | Scope / cost notes |
|---|---|---|
| **External access analyzer** | Uses automated reasoning on **resource-based policies** to flag resources shared **outside the zone of trust** (account or organization): S3 buckets & directory buckets, IAM role trust policies, KMS keys, Lambda functions/layers, SQS, SNS, Secrets Manager, EBS & RDS snapshots, ECR, EFS, DynamoDB tables/streams | **Regional**, so create one in **every Region in use**. Org-wide analyzers run from the management account or **delegated admin**. No charge. Archive rules handle expected findings |
| **Internal access analyzer** | For selected critical resources (S3, RDS snapshots, DynamoDB…), shows which principals **inside** your org/account can access them | Charged per resource monitored |
| **Unused access analyzer** | Finds **unused roles, unused access keys, unused passwords**, plus unused services/actions on active roles/users over a tracking period you choose | Charged per role/user analyzed per month. Findings don't depend on Region, so one analyzer is enough |
| **Policy validation** | Grammar and best-practice checks (security warnings, errors, suggestions) in the console/API/CLI | No charge |
| **Custom policy checks** | `CheckNoNewAccess` (does the new version grant more than the reference?), `CheckAccessNotGranted` (does it allow these critical actions/resources?), `CheckNoPublicAccess` (can this resource policy grant public access?). Built for **CI/CD gates** on CloudFormation/Terraform templates | Charged per check |
| **Policy generation** | Reads **CloudTrail** for a user/role over **up to 90 days** and generates a least-privilege policy template | Action-level detail for many services. **No data events** (e.g., S3 object-level) and no `iam:PassRole`. Can use an org trail in another account with extra bucket/KMS permissions |
| **Access preview** | Preview findings for a proposed resource policy before applying it | No charge |

**Related IAM tooling**
- **Last accessed information**: service-level (and action-level for many services) last-accessed timestamps for users, roles, groups and policies. In Organizations, last accessed for an **OU/account** helps you write SCPs safely.
- **Credential report**: account-level CSV of all IAM users with password/key/MFA status and last-used/rotation dates. Regenerated at most every 4 hours.
- **IAM policy simulator**: test identity policies, boundaries and SCP effects.

### 2.15 IAM Roles Anywhere (on-premises and multicloud workloads)

Gives workloads **outside AWS** (on-prem servers, containers, other clouds) **temporary credentials** using **X.509 certificates** from your PKI, replacing long-term access keys.

```text
 On-prem server (certificate + private key from corporate CA or AWS Private CA)
      │ aws_signing_helper (credential_process) signs CreateSession
      ▼
 IAM Roles Anywhere ── validates chain against TRUST ANCHOR (external CA bundle or AWS Private CA)
      │                 checks imported CRL, PROFILE (roles + session policy + duration)
      ▼
 Assumes target role (trusts rolesanywhere.amazonaws.com) ──► temporary credentials
```

- **Trust anchor**: references AWS Private CA or an external CA certificate. **Profile**: the roles that may be assumed and an optional session policy (managed or inline). Resources are **Regional** and must be in the same account and Region.
- **The trust boundary is the account**: a certificate from any trust anchor in the account can assume any role that trusts Roles Anywhere **unless the trust policy has conditions**. Always add `aws:SourceArn` (trust anchor ARN) and certificate-attribute conditions (Roles Anywhere maps subject/issuer/SAN fields to principal tags):

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "Service": "rolesanywhere.amazonaws.com" },
    "Action": ["sts:AssumeRole", "sts:TagSession", "sts:SetSourceIdentity"],
    "Condition": {
      "ArnEquals": { "aws:SourceArn": "arn:aws:rolesanywhere:eu-west-1:111122223333:trust-anchor/1a2b3c4d-5e6f-7a8b-9c0d-1e2f3a4b5c6d" },
      "StringEquals": { "aws:PrincipalTag/x509Subject/OU": "payments-batch" }
    }
  }]
}
```

- Revocation: import a **CRL**, and disable the trust anchor/profile in an emergency.
- **Roles Anywhere vs SSM hybrid activation:** Roles Anywhere gives **application credentials** for any AWS API. SSM hybrid activation registers servers as **managed nodes** for Systems Manager (patching, Run Command, Session Manager). They can coexist.
- IoT devices with certificates use the **AWS IoT Core credentials provider** instead.

### 2.16 Service-linked roles, service roles and `iam:PassRole`

- **Service-linked role**: created by the service (or through `iam:CreateServiceLinkedRole`). Permissions are fixed by AWS and the trust is locked to the service. It can be deleted only after the service's resources are cleaned up. **Not restricted by SCPs/RCPs.** Examples: `AWSServiceRoleForAutoScaling`, `AWSServiceRoleForOrganizations`, `AWSServiceRoleForSSO`, `AWSServiceRoleForConfig`.
- **Service role**: you own the trust and permissions (Lambda execution role, ECS task role, CodeBuild role, Glue role).
- **`iam:PassRole`** is the escalation choke point. Anyone who can pass an admin role to EC2/Lambda/CloudFormation effectively becomes admin. Scope it to specific role paths/ARNs, optionally with the `iam:PassedToService` condition. It isn't an API call, so it has no CloudTrail event of its own.

### 2.17 EC2 instance profiles and IMDSv2

- The instance profile delivers role credentials through the **Instance Metadata Service** (`169.254.169.254`). Credentials **rotate automatically**, and the SDKs refresh them.
- **IMDSv2** is session-oriented: `PUT /latest/api/token` (token TTL up to 6 h), then `GET` with the `X-aws-ec2-metadata-token` header. It mitigates **SSRF**, open reverse proxies and misconfigured WAF/relays. The **PUT response hop limit** (API default 1, though some AMIs/launch templates set 2) stops tokens being forwarded off the instance. Set it to **2** when containers on the host must reach IMDS.
- **Enforce IMDSv2** with launch templates/AMIs (`HttpTokens=required`), the account-level default IMDS settings per Region, and an SCP/IAM guardrail:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "RequireImdsV2AtLaunch",
      "Effect": "Deny",
      "Action": "ec2:RunInstances",
      "Resource": "arn:aws:ec2:*:*:instance/*",
      "Condition": { "StringNotEquals": { "ec2:MetadataHttpTokens": "required" } }
    },
    {
      "Sid": "DenyCredentialsDeliveredViaImdsV1",
      "Effect": "Deny",
      "Action": "*",
      "Resource": "*",
      "Condition": { "NumericLessThan": { "ec2:RoleDelivery": "2.0" } }
    }
  ]
}
```

- **Detect stolen credentials:** GuardDuty `UnauthorizedAccess:IAMUser/InstanceCredentialExfiltration.OutsideAWS` (and `.InsideAWS`). Prevent off-instance use with `aws:EC2InstanceSourceVPC` / `aws:EC2InstanceSourcePrivateIPv4` conditions in a data-perimeter policy.
- Containers: **ECS task roles** and **EKS Pod Identity/IRSA** give each task/pod its own role. Don't rely on the node's instance profile, and keep pods away from node IMDS (hop limit 1) when they have their own roles.

### 2.18 Amazon Verified Permissions and AWS Verified Access (brief)

- **Amazon Verified Permissions**: managed, fine-grained **authorization for your own applications**, using the **Cedar** policy language (open source, formally analyzable). Policy store + schema + policies (RBAC and ABAC), e.g. `permit (principal in Group::"managers", action == Action::"approveExpense", resource) when { resource.amount < 10000 };`. Identity sources are **Cognito user pools** or **OIDC** IdPs. APIs: `IsAuthorized`, `IsAuthorizedWithToken` (and batch variants). Exam signal: *"externalize authorization logic from application code; consistent, auditable permissions for application users"*. It complements Cognito (authentication). It doesn't replace IAM for AWS API access.
- **AWS Verified Access**: **zero-trust, VPN-less** access to corporate applications. Each request is evaluated against **Cedar** policies using **identity** (IAM Identity Center or an OIDC IdP) and **device posture** (e.g., CrowdStrike, Jamf, JumpCloud). Originally for HTTP(S) apps (ALB/ENI endpoints). Support for **non-HTTP(S)** resources (TCP, SSH, RDP) through a connectivity client became generally available in 2025. Exam signal: *"replace the client VPN; give contractors access to internal web apps based on identity and device health"*.

### 2.19 Credential best practices

| Practice | Implementation |
|---|---|
| **No long-term credentials for humans** | Identity Center (federated) for console/CLI. Remove IAM users. Delete root access keys. Centralize root access and delete member-account root credentials |
| **No long-term credentials for workloads** | EC2 instance profiles, ECS task roles, EKS Pod Identity/IRSA, Lambda execution roles, **Roles Anywhere** (on-prem), **OIDC federation** (CI/CD), Cognito identity pools (apps), outbound identity federation (calling external services) |
| **If keys must exist** (legacy third-party tool) | Least privilege. **Rotate** (create the 2nd key → deploy → deactivate the old one → delete). Store in Secrets Manager. Restrict with `aws:SourceIp`/`aws:SourceVpce` conditions. Ideally the user can only assume a role |
| **MFA everywhere** | Root (MFA enforced by default; up to 8 MFA devices per user/root), Identity Center (FIDO2/passkeys preferred), `aws:MultiFactorAuthPresent` on sensitive roles |
| **Find stale access** | **Credential report**, **last accessed info**, **unused access analyzer**, AWS Config rules (`access-keys-rotated`, `iam-user-unused-credentials-check`, `root-account-mfa-enabled`), Security Hub controls |
| **Detect misuse** | CloudTrail (organization trail), GuardDuty (anomalous IAM behaviour, credential exfiltration), EventBridge rule on root sign-in |
| **Respond to leaked keys** | Deactivate the key → investigate in CloudTrail → **revoke active sessions** of roles the key could assume → rotate → remove the user if possible |
| **Break-glass** | 1–2 IAM principals outside the IdP, hardware MFA, credentials in a safe, alarms on use, tested regularly |


---

## 3. Architecture patterns

### Pattern 1: Centralized workforce access (hub-and-spoke federation)

```text
 Okta / Entra ID ──SAML 2.0 (authn)──►┐
        │                              │
        └──SCIM 2.0 (users/groups)────►│  IAM Identity Center (org instance)
                                       │  delegated admin: Security-Tooling account
                                       │  permission sets: Admin, PowerUser, ReadOnly,
                                       │  DataAnalyst(ABAC: costCenter, project)
                                       ▼
       ┌───────────────┬──────────────┼───────────────┬────────────────┐
   Prod OU accts   Non-prod OU    Sandbox OU      Log Archive     Security acct
   AWSReservedSSO_* roles provisioned per assignment (group → permset → account)
   SCPs/RCPs from Organizations bound everything (Chapter 02)
```
**When:** any multi-account org. **Trade-offs:** single dependency on the IdP and Identity Center (mitigate with break-glass roles and multi-Region replication). Customer managed policy references need the policy in every account (StackSets).

### Pattern 2: Third-party SaaS access at scale

```text
 Vendor account 999988887777                 Customer accounts (300, via StackSets → OU)
 ┌───────────────────────────┐   AssumeRole   ┌───────────────────────────────────────┐
 │ VendorIngestionRole        │ ─────────────► │ Role "VendorReadOnly"                  │
 │ passes ExternalId = <cust> │  + ExternalId  │ trust: Principal = vendor role ARN     │
 └───────────────────────────┘                │        Condition sts:ExternalId = <id> │
                                              │ perms: ReadOnly / scoped               │
                                              └───────────────────────────────────────┘
```
**When:** monitoring, cost tools, backup SaaS. **Never** give the vendor IAM user access keys. Combine with **IAM Access Analyzer** (external access findings show the vendor trust, then archive as expected) and an **RCP/SCP** that limits what any vendor role can do.

### Pattern 3: Delegated IAM administration with permissions boundaries

```text
 Platform team ──creates──► DeveloperRole (identity policy: iam:CreateRole only with
                                          iam:PermissionsBoundary = AppWorkloadBoundary,
                                          only on role/app/*, PassRole only role/app/*)
 Developer ──creates──► role/app/orders-lambda  (boundary = AppWorkloadBoundary)
                         effective = its policy ∩ AppWorkloadBoundary ∩ SCPs
```
**When:** "developers need autonomy to create roles without escalation". **Trade-off:** boundaries are per-entity and easy to forget, so enforce them through the condition, and audit with Config/Access Analyzer.

### Pattern 4: ABAC for fast-growing teams

```text
 IdP attribute project=atlas ─► session tag aws:PrincipalTag/project=atlas
 Resources tagged project=atlas (enforced by tag policy + RequestTag condition on create)
 One policy: allow when aws:ResourceTag/project == ${aws:PrincipalTag/project}
 New project "zephyr" → zero IAM changes, just new IdP group attribute + tags
```

### Pattern 5: Workload identity without keys

```text
 EC2 ─ instance profile (IMDSv2) ─┐
 ECS ─ task role ─────────────────┤
 EKS ─ Pod Identity / IRSA ───────┤──► STS temporary credentials ──► AWS APIs
 Lambda ─ execution role ─────────┤
 GitHub Actions ─ OIDC ───────────┤   (AssumeRoleWithWebIdentity, sub-scoped)
 On-prem server ─ X.509 ──────────┘   (IAM Roles Anywhere, trust anchor + profile)
 AWS workload → external SaaS: outbound identity federation (sts:GetWebIdentityToken → JWT)
```

### Pattern 6: Customer identity for web/mobile apps

```text
 Mobile app ──sign-in──► Cognito User Pool (native + Google/Apple + SAML for B2B)
     │                        │ JWT (ID/access)
     │                        ▼
     ├──► API Gateway (Cognito authorizer) ──► Lambda ──► Verified Permissions (Cedar) IsAuthorized
     │
     └──► Cognito Identity Pool ──► authenticated role (S3 prefix private/${sub}/*)
                                └─► unauthenticated role (read public catalog only)
```

### Pattern 7: Hybrid Active Directory

```text
 On-prem AD forest corp.example.com ◄──two-way forest trust──► AWS Managed Microsoft AD
         ▲  (DX/VPN)                                             (Enterprise, eu-west-1)
         │                                                        │ multi-Region replication
   AD Connector (per account/VPC, for WorkSpaces/console           ▼
   when no AWS-side directory wanted)                         us-east-1 DCs (same dir ID)
                                                    shared to app accounts via directory sharing
                                                    RDS SQL Server / FSx Windows join locally
```

### Pattern 8: Org-wide confused-deputy and data-perimeter controls

```text
 RCP (all member accounts): Deny s3:*, sqs:*, kms:*, secretsmanager:*, sts:AssumeRole …
    when principal not in org (aws:PrincipalOrgID) AND not an AWS service
    and, for service principals, when aws:SourceOrgID != o-xxxx
 SCP: Deny actions on resources outside org (aws:ResourceOrgID) except allow-listed
 VPC endpoint policies: only org principals → only org resources
```
Details in [Chapter 02](02-Multi-Account-Governance.md).

---

## 4. Decision tables / "X vs Y"

### 4.1 Cross-account mechanism

| Requirement | Role assumption | Resource-based policy | AWS RAM |
|---|---|---|---|
| Caller keeps own permissions/identity | ❌ (swaps to role) | ✅ | ✅ |
| Works for any AWS API | ✅ | Only services with resource policies | Only RAM-shareable types |
| Console access | ✅ | ❌ | partial (shared resources visible) |
| Third-party with confused-deputy risk | ✅ + ExternalId | ⚠️ (no ExternalId equivalent) | ❌ |
| Org-wide share with one statement | ⚠️ (trust `aws:PrincipalOrgID`) | ✅ `aws:PrincipalOrgID` | ✅ share to org/OU |
| Audit trail | CloudTrail shows AssumeRole + session | CloudTrail in both accounts | RAM + CloudTrail |

### 4.2 Workforce identity options

| Option | Use when | Avoid when |
|---|---|---|
| **IAM Identity Center + external IdP (SAML+SCIM)** | Enterprise with Okta/Entra/Ping, many accounts | Never avoid for workforce multi-account access |
| **IAM Identity Center + AD (Managed AD / AD Connector)** | AD is the source of truth, no cloud IdP | You want no network dependency on on-prem (AD Connector) |
| **IAM Identity Center directory** | Small team, no IdP | Large enterprise with an existing IdP |
| **Direct IAM SAML federation per account** | 1–few accounts, legacy | Many accounts (setup sprawl) |
| **IAM users** | Break-glass, tools that can't federate | Everyday human access |

### 4.3 Cognito user pool vs identity pool vs Identity Center vs Verified Permissions

| Need | Service |
|---|---|
| Authenticate app end-users, get JWTs | **Cognito user pool** |
| Give app end-users temporary AWS credentials (incl. guests) | **Cognito identity pool** |
| Employees into AWS accounts & AWS apps | **IAM Identity Center** |
| Fine-grained app-level authorization decisions | **Verified Permissions** |
| Zero-trust access to internal apps without VPN | **Verified Access** |

### 4.4 Limiting permissions: which control?

| Goal | Control |
|---|---|
| Nobody in OU may use Region X / disable CloudTrail | **SCP** |
| No external identity may reach our S3/KMS/SQS regardless of resource policies | **RCP** |
| Developer-created roles can't exceed a ceiling | **Permissions boundary** |
| A broker narrows a broad role per request | **Session policy** |
| Specific resource accessible only from VPC endpoint | **Resource policy** with `aws:SourceVpce` (+ endpoint policy) |
| Only org principals may use a resource | Resource policy with `aws:PrincipalOrgID` (at scale: RCP) |

### 4.5 STS API selection

| Scenario | API |
|---|---|
| Cross-account / elevate with MFA | `AssumeRole` (SerialNumber/TokenCode) |
| Corporate IdP via SAML directly to IAM role | `AssumeRoleWithSAML` |
| GitHub Actions / EKS IRSA / Google token / Cognito basic flow | `AssumeRoleWithWebIdentity` |
| Legacy proxy issuing creds for many users from one IAM user, up to 36 h | `GetFederationToken` |
| IAM user wants MFA-authenticated creds for CLI | `GetSessionToken` |
| Short privileged root task in a member account | `AssumeRoot` (centralized root access) |
| AWS workload proves identity to non-AWS service | `GetWebIdentityToken` (outbound federation) |

### 4.6 Directory choice (summary)

| Requirement | Pick |
|---|---|
| Real AD in AWS, trusts, RDS SQL Server, FSx, multi-account sharing | **Managed Microsoft AD** (Standard ≤ ~30k objects, Enterprise ≤ ~500k) |
| AD in several Regions, managed | **Managed Microsoft AD Enterprise + multi-Region replication** |
| Use on-prem AD as-is, no AWS directory copy | **AD Connector** |
| Extend the *same* on-prem domain with AWS-managed DCs | **Managed Microsoft AD Hybrid Edition** |
| Cheap basic LDAP/Samba directory (existing customers only) | **Simple AD** |
| Full admin control | Self-managed AD on EC2 |

---

## 5. Exam keyword → answer cheat list

| Stem keyword / phrase | Likely answer |
|---|---|
| "third party", "vendor", "SaaS needs access to our account" | IAM role + **External ID**, trust vendor's account/role |
| "confused deputy" + AWS service writes to bucket/topic | `aws:SourceArn` + `aws:SourceAccount` (org scale: **RCP** with `aws:SourceOrgID`) |
| "only accounts in our organization" on a bucket/key/queue | `aws:PrincipalOrgID` in resource policy |
| "developers create roles but must not escalate" | **Permissions boundary** + `iam:PermissionsBoundary` condition + restricted `iam:PassRole` |
| "new projects weekly; no policy changes" / "scale permissions" | **ABAC** with `aws:PrincipalTag` = `aws:ResourceTag`, session tags from IdP |
| "SSO to multiple accounts", "central workforce access" | **IAM Identity Center** (old name AWS SSO) |
| "automatically provision users and groups from Okta/Entra" | **SCIM** with Identity Center |
| "reduce number of permission sets" | Identity Center **attributes for access control (ABAC)** |
| "audit which corporate user ran the query" | **Trusted identity propagation** |
| "mobile users sign in with Google/Apple" | **Cognito user pool** (social IdP) |
| "app uploads directly to S3 / guest access to AWS resources" | **Cognito identity pool** (authenticated / unauthenticated roles) |
| "externalize application authorization", "Cedar" | **Amazon Verified Permissions** |
| "replace VPN for internal web apps, device posture" | **AWS Verified Access** |
| "on-prem servers need AWS credentials, existing PKI" | **IAM Roles Anywhere** |
| "CI/CD pipeline currently stores access keys" (GitHub/GitLab) | **OIDC federation** → `AssumeRoleWithWebIdentity` |
| "WorkSpaces with on-prem AD credentials, no sync" | **AD Connector** |
| "AD in multiple Regions", "global Windows apps" | **Managed Microsoft AD Enterprise** multi-Region replication |
| "trust with on-prem forest" | **Managed Microsoft AD** (not AD Connector, not Simple AD) |
| "find resources shared externally" | **IAM Access Analyzer external access analyzer** (each Region) |
| "find unused permissions/roles across org" | **Access Analyzer unused access analyzer** (+ last accessed) |
| "block over-permissive policies in pipeline" | Access Analyzer **custom policy checks** (`CheckAccessNotGranted`, `CheckNoNewAccess`, `CheckNoPublicAccess`) |
| "generate least-privilege policy from activity" | Access Analyzer **policy generation** (CloudTrail, ≤ 90 days) |
| "role chaining", "session expires after 1 hour despite 12-hour max" | Role-chaining **1-hour** cap. Refresh or remove the second hop |
| "SSRF stole instance credentials" | Enforce **IMDSv2**, hop limit, `ec2:RoleDelivery`, GuardDuty |
| "cross-account encrypted snapshot/object" | **Customer managed KMS key** + key policy + IAM policy in other account |
| "account B can't read objects uploaded by account A" | S3 **Object Ownership = Bucket owner enforced** |
| "revoke credentials of a compromised role immediately" | **Revoke active sessions** (deny on `aws:TokenIssueTime`) |
| "remove root credentials from member accounts" | **Centralized root access management** |

---

## 6. Traps & distractors

1. **"Attach an SCP to grant access."** SCPs and RCPs **never grant**. They only filter.
2. **"An SCP in account B blocks principals from account A."** SCPs apply only to principals in the accounts they're attached to. To protect B's resources from outsiders, use **RCPs** or resource policies.
3. **"SCPs restrict the management account / service-linked roles."** They restrict neither. Keep workloads out of the management account.
4. **"Use an SCP to stop AWS services writing to our buckets on behalf of others."** Service principals aren't governed by SCPs. Use resource policies with `aws:SourceArn`/`aws:SourceAccount` or an **RCP**.
5. **"The identity policy in account A allows `s3:GetObject` on B's bucket, so it works."** Cross-account also needs B's **bucket policy** (or a role in B). With SSE-KMS it also needs the **key policy** in the key's account.
6. **"Share an EBS snapshot encrypted with `aws/ebs`."** Not possible. Re-encrypt with a customer managed key.
7. **"Increase the target role's max session duration to 12 h"** to fix a chained session. The role-chaining cap is **1 hour** regardless.
8. **"Use GetFederationToken from an EC2 instance role."** Only IAM users (or root) can call it.
9. **"External ID is a secret like a password, generated by the customer."** It's not secret, and the **vendor** generates a unique one per customer.
10. **"SAML federation into Identity Center auto-creates groups."** You need **SCIM** (or AD sync).
11. **"Use Cognito for employee SSO to AWS accounts."** Use **IAM Identity Center**.
12. **"Simple AD with a trust to on-prem AD."** Simple AD supports **no trusts**, no MFA, no RDS SQL Server, and is closed to new customers.
13. **"AD Connector for RDS for SQL Server Windows auth."** Not supported. Use Managed Microsoft AD (optionally trusting on-prem).
14. **"Standard Edition with multi-Region replication."** Multi-Region requires **Enterprise Edition**.
15. **"One Access Analyzer external access analyzer covers all Regions."** External access analyzers are **Regional**. Unused access analyzers aren't.
16. **"Permissions boundary grants the permissions the role needs."** Boundaries only cap. The role still needs an identity policy.
17. **"Permissions boundary on a group."** Not supported. Boundaries are for users and roles only.
18. **"Use `aws:SourceIp` to restrict to our VPC."** Requests through VPC endpoints carry private IPs; use `aws:SourceVpce`/`aws:SourceVpc`/`aws:VpcSourceIp`.
19. **"`NotPrincipal` with Deny to exempt an admin role."** Fragile and discouraged. Use a `Principal: *` deny with `ArnNotLike aws:PrincipalArn` conditions.
20. **"Hard-code the AWSReservedSSO role ARN in a bucket policy."** Its suffix changes and isn't predictable. Use an `aws:PrincipalArn` wildcard match.
21. **"Trust policy only checks `aud` for GitHub OIDC."** Any repository could assume it. Constrain `sub`.
22. **"Roles Anywhere certificates are scoped automatically to one role."** By default any trust anchor in the account can reach any role trusting Roles Anywhere. Add `aws:SourceArn` and certificate-attribute conditions.
23. **"Delete the access key to kill existing sessions it created."** Temporary credentials obtained earlier stay valid until expiry. **Revoke sessions** on assumed roles.
24. **"Policy generation will include S3 object-level actions."** Data events aren't analyzed, and `iam:PassRole` isn't included.
25. **"Resource policy granting the role ARN bypasses the permissions boundary."** Granting the **role ARN** is still limited by boundary/session policy. Only grants to the **session ARN** or **user ARN** aren't (same account).

---

## 7. Professional architect focus

- **Identity is the perimeter, but layer it.** Combine identity policies (least privilege), boundaries (delegation), SCPs/RCPs (org guardrails), resource policies (data perimeter) and network conditions (`aws:SourceVpce`). The exam rewards answers that use the **right layer for the scope** (org vs account vs entity vs session).
- **Design for one workforce identity source.** Pick one IdP as the source of truth, wire it to Identity Center with SCIM, and govern access as **group → permission set → account** in code (IaC + pull-request review). Ask stakeholders who owns joiner/mover/leaver processes; that's where the risk is.
- **Prefer ABAC where tags can be governed.** It removes policy sprawl and the 20/25 managed-policy-per-role ceilings, but it needs mature tagging (tag policies, deny re-tagging, tags sourced from HR attributes). Hybrid RBAC+ABAC is normal: RBAC for coarse job function (permission set), ABAC for project scoping.
- **Eliminate long-term keys.** Inventory with the credential report and unused-access findings, then migrate category by category: humans → Identity Center; CI → OIDC; on-prem → Roles Anywhere; vendors → roles with External ID. Track "IAM users with active keys" as a KPI.
- **Plan break-glass and IdP outages.** Identity Center and the corporate IdP are critical dependencies. Document emergency access (IAM role/user with hardware MFA, alerting), test it, and consider Identity Center multi-Region replication if your Region strategy needs it.
- **Least privilege is a process.** Start broad-but-bounded in sandboxes, use policy generation and last-accessed data to tighten, and gate changes with Access Analyzer custom checks in CI/CD. Run unused-access analysis org-wide from a delegated admin account.
- **Cross-account defaults:** within your org, use `aws:PrincipalOrgID`/`aws:PrincipalOrgPaths` rather than listing account IDs. For third parties, use roles with External ID, scoped permissions, Access Analyzer monitoring, and contractual review.
- **Anti-patterns to call out:** shared IAM users, access keys in code or AMIs, `iam:PassRole` on `*`, `Allow` + `NotAction`, wildcard principals without conditions, permission sets granting `AdministratorAccess` to large groups in production, KMS key policies that grant `kms:*` to `*` without conditions, editing `AWSReservedSSO_*` roles by hand.
- **Questions to raise with stakeholders:** Who is the authoritative identity source? What is the joiner/mover/leaver SLA? Which data needs user-level audit (TIP)? Which vendors have access, and are their roles reviewed? What is the emergency-access procedure? Is regulatory evidence (access reviews) automated?

---

## 8. Skills checklist

- [ ] I can walk the full evaluation flow (explicit deny → RCP → SCP → resource → identity → boundary → session) and predict the outcome of a scenario.
- [ ] I can explain the same-account difference between a resource policy that names a user/session ARN and one that names a role ARN.
- [ ] I can state what both accounts must allow in a cross-account request, including KMS.
- [ ] I can choose between role assumption, resource-based policy and AWS RAM for a given cross-account need.
- [ ] I can write a trust policy with `sts:ExternalId` and explain the confused-deputy problem for vendors and for service principals.
- [ ] I know when to use `aws:SourceArn`, `aws:SourceAccount`, `aws:SourceOrgID`, `aws:PrincipalOrgID`, `aws:ResourceOrgID`.
- [ ] I can build an ABAC policy with `aws:PrincipalTag`, `aws:ResourceTag`, `aws:RequestTag`, `aws:TagKeys` and protect against re-tagging.
- [ ] I can explain session tags, `sts:TagSession`, and transitive tags in role chaining.
- [ ] I can design the "developers create roles without escalation" permissions-boundary pattern.
- [ ] I know the STS APIs, who can call them, their durations (1 h default, 12 h role max, 36 h federation token, 1 h role chaining).
- [ ] I can design IAM Identity Center with an external IdP (SAML + SCIM), delegated admin, permission sets, ABAC, and break-glass.
- [ ] I know what trusted identity propagation is for.
- [ ] I can choose between Cognito user pools and identity pools and configure role mapping and guest access.
- [ ] I can choose between Managed Microsoft AD (Standard/Enterprise/Hybrid), AD Connector and Simple AD.
- [ ] I can map each IAM Access Analyzer capability to a requirement (external, internal, unused, validation, custom checks, generation).
- [ ] I can design keyless access for on-prem (Roles Anywhere), CI/CD (OIDC), EC2 (IMDSv2), containers (task roles / Pod Identity).
- [ ] I can describe Verified Permissions vs Verified Access.
- [ ] I can list credential best practices, including centralized root access and session revocation.


---

## 9. Practice questions

> Original questions written in SAP-C02 style. They are not real exam questions.

**Q1.** A financial services company runs 320 AWS accounts in AWS Organizations. It has signed a contract with a third-party cost-optimization SaaS provider that must read billing, EC2, RDS, and CloudWatch metadata in every account. The provider serves thousands of other AWS customers from a single AWS account. The security team requires that no long-term credentials leave the company, that the provider cannot be tricked into using the company's access on behalf of another customer, and that new accounts automatically get the same access. Which solution meets these requirements with the LEAST operational overhead?

- A. Create an IAM user with read-only permissions in each account, store the access keys in AWS Secrets Manager, and share the secret with the provider's account by using a resource policy.
- B. Use CloudFormation StackSets with service-managed permissions and automatic deployment to the organization root to create a read-only IAM role in every account. The role's trust policy trusts the provider's AWS account and requires the `sts:ExternalId` condition with the unique value the provider issued to the company.
- C. Use CloudFormation StackSets to create a read-only IAM role in every account whose trust policy trusts the provider's account and requires `aws:PrincipalOrgID` equal to the company's organization ID.
- D. Create a single read-only role in the management account that trusts the provider's account with an External ID, and allow that role to read all member accounts through an SCP.

**Q2.** A platform team wants application developers to create and manage IAM roles for their own AWS Lambda functions in a shared development account. Developers must not be able to create a role with more permissions than an approved set of services (DynamoDB, S3, SQS, CloudWatch Logs), must not be able to modify their own developer role, and must not be able to remove the restriction from roles they create. Which combination of actions will meet these requirements? **(Select TWO.)**

- A. Create a managed policy `AppWorkloadBoundary` that allows only the approved services. In the developer role's identity policy, allow `iam:CreateRole`, `iam:AttachRolePolicy`, and `iam:PutRolePolicy` on `role/app/*` only when `iam:PermissionsBoundary` equals the `AppWorkloadBoundary` ARN, and allow `iam:PassRole` only on `role/app/*`.
- B. Attach an SCP to the development account that denies `iam:CreateRole` unless the role name begins with `app-`.
- C. In the developer role's identity policy, explicitly deny `iam:DeleteRolePermissionsBoundary`, and deny `iam:CreatePolicyVersion`, `iam:SetDefaultPolicyVersion`, and `iam:DeletePolicy` on the `AppWorkloadBoundary` policy.
- D. Require developers to pass a session policy that lists the approved services whenever they assume the developer role.
- E. Enable an IAM Access Analyzer unused access analyzer to delete any roles that have permissions outside the approved services.

**Q3.** An analytics application runs on Amazon EC2 in account A (111111111111). It must read objects from an S3 bucket in account B (222222222222). The objects are encrypted with SSE-KMS by a customer managed key in account B. The bucket policy in account B allows `s3:GetObject` for the EC2 instance role from account A, and the instance role's identity policy allows `s3:GetObject` on the bucket. Requests fail with `AccessDenied`. Which combination of changes will resolve the issue? **(Select TWO.)**

- A. Add a statement to the KMS key policy in account B that allows the account A instance role (or account A) to use `kms:Decrypt`.
- B. Add `kms:Decrypt` on the key's ARN in account B to the instance role's identity policy in account A.
- C. Change the bucket's default encryption to the AWS managed key `aws/s3` so that account A can decrypt the objects automatically.
- D. Create a KMS grant in account A for the instance role on the account B key alias.
- E. Add an SCP to account B that allows `kms:Decrypt` for principals in account A.

**Q4.** A retailer with 140 AWS accounts uses Microsoft Entra ID as its identity provider for 9,000 employees. Today each account has its own IAM SAML provider and roles, and on-boarding a new team takes weeks. The company wants centralized access to all accounts, users and groups that appear automatically when HR adds employees, and far fewer permission definitions even though hundreds of projects are scoped by a `project` attribute that already exists in Entra ID. Administration must not be performed from the management account. Which solution meets these requirements?

- A. Enable IAM Identity Center in a member account as an account instance, connect Entra ID through SAML 2.0, and create one permission set per project.
- B. Enable IAM Identity Center in the management account, register a security account as delegated administrator, configure Entra ID as an external identity provider with SAML 2.0 and SCIM provisioning, enable attributes for access control that map the `project` attribute, and create a small number of permission sets whose policies compare `aws:PrincipalTag/project` with `aws:ResourceTag/project`.
- C. Keep the per-account IAM SAML providers, and use CloudFormation StackSets to deploy one IAM role per project to every account with a trust policy for the SAML provider.
- D. Deploy AWS Managed Microsoft AD, synchronize Entra ID users to it, and use AD Connector as the IAM Identity Center identity source with one permission set per project.

**Q5.** A media startup is building a mobile app. Users sign in with Google, Apple, or an email address and password. Signed-in users must upload videos directly to S3, each user only into their own prefix. Users who are not signed in must be able to browse a public catalog stored in DynamoDB with read-only access. The team wants a fully managed solution with no custom authentication code. Which combination of steps will meet these requirements? **(Select TWO.)**

- A. Create an Amazon Cognito user pool with Google and Apple as federated identity providers and native email sign-in.
- B. Create an Amazon Cognito identity pool that uses the user pool as an identity provider. Configure an authenticated role whose policy allows `s3:PutObject` on `arn:aws:s3:::media-uploads/private/${cognito-identity.amazonaws.com:sub}/*`, and enable guest access with an unauthenticated role that allows only DynamoDB read actions on the catalog table.
- C. Create an IAM user for each app user during sign-up and return access keys to the device through an AWS Lambda function.
- D. Use IAM Identity Center with Google Workspace as the identity source, and assign app users to a permission set that allows S3 uploads.
- E. Configure the S3 bucket policy to allow `s3:PutObject` from any principal when the `aws:Referer` header matches the app's domain.

**Q6.** A manufacturing company has 400 on-premises Linux servers that run batch jobs which write results to Amazon S3 and read parameters from AWS Systems Manager Parameter Store. Today each server uses an IAM user access key embedded in a configuration file. The company has a mature internal PKI that issues X.509 certificates to every server, and a security audit requires removing all long-term AWS credentials within 30 days. Different server groups (identified by the certificate's OU field) must get different permissions. Which solution should a solutions architect recommend?

- A. Register the servers with Systems Manager hybrid activations and use the managed-instance role for the batch jobs' S3 access.
- B. Configure IAM Roles Anywhere with a trust anchor for the corporate CA, create a profile per server group, and create roles whose trust policies allow `rolesanywhere.amazonaws.com` with conditions on `aws:SourceArn` for the trust anchor and on `aws:PrincipalTag/x509Subject/OU`. Use the credential helper on each server.
- C. Rotate the IAM user access keys every 7 days by using AWS Secrets Manager rotation, and distribute keys through a configuration management tool.
- D. Create an OIDC identity provider in IAM that points to the corporate PKI and call `AssumeRoleWithWebIdentity` from each server by using the certificate.

**Q7.** A global insurance company runs .NET applications, Amazon RDS for SQL Server, and Amazon FSx for Windows File Server in eu-west-1, us-east-1, and ap-southeast-2. All workloads need Windows authentication with low-latency access to domain controllers in each Region. Application service accounts and server objects must live in a directory hosted in AWS so that the workloads keep working if the on-premises data centre becomes unreachable. Employees, who are mastered in the on-premises AD forest, must also be able to reach the AWS workloads with their existing credentials. The company wants to minimize the operational effort of running domain controllers. Which solution meets these requirements?

- A. Deploy AD Connector in each Region pointing to on-premises domain controllers, and join RDS and FSx to the AD Connector.
- B. Deploy AWS Managed Microsoft AD Standard Edition in eu-west-1 and enable multi-Region replication to the other two Regions. Create a forest trust with on-premises AD.
- C. Deploy AWS Managed Microsoft AD Enterprise Edition in eu-west-1, enable multi-Region replication to us-east-1 and ap-southeast-2, and create a two-way forest trust with the on-premises forest.
- D. Deploy Simple AD in each Region and configure a trust relationship with the on-premises forest.

**Q8.** A security team for an organization with 250 accounts needs to (1) identify IAM roles and access keys that have not been used in 90 days and permissions that roles never use, (2) give application teams a least-privilege policy based on what their roles actually did last quarter, and (3) stop pull requests that add IAM policies granting `iam:PassRole` on all resources or making S3 bucket policies public. The solution must be centrally managed. Which combination of actions will meet these requirements? **(Select THREE.)**

- A. Create an organization-level IAM Access Analyzer unused access analyzer from a delegated administrator account with a 90-day tracking period.
- B. Use IAM Access Analyzer policy generation against the organization CloudTrail trail for each role to produce policy templates from up to 90 days of activity.
- C. Add IAM Access Analyzer custom policy checks (`CheckAccessNotGranted` for `iam:PassRole` on `*`, and `CheckNoPublicAccess` for S3 bucket policies) to the CI/CD pipeline that deploys the infrastructure-as-code templates.
- D. Download the IAM credential report from the management account to find unused roles across all member accounts.
- E. Enable AWS Trusted Advisor IAM checks in every account to generate least-privilege policies.
- F. Create an external access analyzer in us-east-1 only to find unused permissions across all Regions.

**Q9.** A data pipeline runs on an Amazon EC2 instance in account A. Its instance profile role assumes a role in account B to read a large dataset from an S3 bucket (SSE-KMS with a customer managed key in account B) and write results back to a bucket in account A. The job runs for 5 hours. The developers set `DurationSeconds=18000` and raised account B role's maximum session duration to 12 hours, but the `AssumeRole` call fails. When they omit `DurationSeconds`, the job fails after 1 hour with expired credentials. Which actions will resolve the issue? **(Select TWO.)**

- A. Configure the AWS SDK to use an assume-role credential provider with the instance profile as the source, so that the chained 1-hour credentials refresh automatically before they expire.
- B. Remove the second hop: grant the account A instance role access directly through account B's bucket policy and KMS key policy, and add the matching permissions to the instance role's identity policy.
- C. Call `GetFederationToken` from the instance role with a 36-hour duration and use those credentials to access account B.
- D. Raise account B role's maximum session duration further by requesting a service quota increase to 24 hours.
- E. Create an IAM user in account B with access keys and store them on the instance so the job can use `GetSessionToken` for 36 hours.

**Q10.** A company with 400 accounts in AWS Organizations centralizes CloudTrail, AWS Config, and VPC Flow Logs delivery into S3 buckets spread across many member accounts. The security team found that several bucket policies grant `s3:PutObject` to AWS service principals without conditions, which would let other AWS customers configure their own services to write into the company's buckets. The team wants one preventive control across all member accounts that blocks service principals from accessing the company's S3 buckets on behalf of accounts outside the organization, without editing hundreds of bucket policies. Which solution meets this requirement?

- A. Attach an SCP to the organization root that denies `s3:PutObject` when `aws:PrincipalOrgID` is not the company's organization ID.
- B. Attach an RCP to the organization root that denies `s3:*` when `aws:SourceOrgID` is not the company's organization ID, scoped to requests where `aws:PrincipalIsAWSService` is true and the `aws:SourceAccount` key is present.
- C. Enable IAM Access Analyzer external access analyzers in every Region and auto-remediate findings with AWS Lambda.
- D. Update every bucket policy with a `Deny` statement that uses `NotPrincipal` to exclude the organization's accounts.

---

### Answers & explanations

<details><summary>Q1 — Show answer</summary>

**Correct: B.**

- **Why:** a third-party SaaS provider serving many customers is the textbook **cross-account confused-deputy** case. The role's trust policy should trust the provider's account and require the provider-issued, customer-unique **External ID**. **StackSets with service-managed permissions and automatic deployment** creates the role in every existing and future account with no manual work. No long-term credentials are shared.
- **A:** shares long-term access keys, which violates the requirement and adds heavy rotation overhead.
- **C:** the provider's account is **not** in the company's organization, so `aws:PrincipalOrgID` would never match, and the condition does nothing against confused deputy.
- **D:** SCPs never grant access, and a role in the management account can't read member accounts without assuming roles in each one. It also puts third-party access in the most sensitive account.
- **References:** https://docs.aws.amazon.com/IAM/latest/UserGuide/confused-deputy.html · https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_common-scenarios_third-party.html · https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/stacksets-orgs-manage-auto-deployment.html
</details>

<details><summary>Q2 — Show answer</summary>

**Correct: A, C.**

- **Why:** A implements the **permissions boundary delegation** pattern. Developers can create or modify roles only under `/app/` and only when the boundary is attached, so the created roles' effective permissions can't exceed the boundary. Restricting `iam:PassRole` to `/app/*` stops them passing more powerful roles to Lambda. Their own developer role isn't under `/app/`, so they can't modify it. C closes the escape routes: rewriting the boundary policy (new version / set default / delete) or removing the boundary from a role.
- **B:** a name prefix doesn't limit permissions, and SCPs can't express "permissions ≤ X" for the roles created.
- **D:** session policies limit the developer's own session, not the roles they create. They are also voluntary unless enforced elsewhere.
- **E:** Access Analyzer detects. It doesn't prevent, and it doesn't delete roles.
- **References:** https://docs.aws.amazon.com/IAM/latest/UserGuide/access_policies_boundaries.html · https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_policies_iam-condition-keys.html
</details>

<details><summary>Q3 — Show answer</summary>

**Correct: A, B.**

- **Why:** cross-account use of a KMS key needs **both** the **key policy** in the key-owning account (B) to allow the external principal or account, **and** an **IAM policy** in the caller's account (A) allowing `kms:Decrypt` on the **key ARN**. The S3 permissions are already correct. The missing piece is KMS on both sides.
- **C:** AWS managed keys (`aws/s3`) **can't be used cross-account** because you can't edit their key policy. It would make things worse.
- **D:** grants are created in the key's account by a principal with `kms:CreateGrant` on that key. "A grant in account A on an alias" isn't how grants work, and aliases can't be used cross-account in this way.
- **E:** SCPs never grant permissions, and account B's SCPs don't apply to account A's principals.
- **References:** https://docs.aws.amazon.com/kms/latest/developerguide/key-policy-modifying-external-accounts.html · https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_policies_evaluation-logic-cross-account.html
</details>

<details><summary>Q4 — Show answer</summary>

**Correct: B.**

- **Why:** an **organization instance** of IAM Identity Center (enabled in the management account) is required for multi-account access. A **delegated administrator** keeps daily admin out of the management account. **SAML 2.0** handles authentication and **SCIM** provisions users/groups automatically from Entra ID. **Attributes for access control** turn the `project` attribute into a session tag, so a few ABAC permission sets replace hundreds of per-project definitions.
- **A:** account instances **can't grant AWS account access**. One permission set per project also defeats the goal.
- **C:** keeps the per-account SAML sprawl and creates hundreds of roles × 140 accounts.
- **D:** synchronizing Entra ID into Managed AD adds infrastructure and a second copy of identities. AD Connector is meant for self-managed AD (Managed AD would connect to Identity Center directly). Per-project permission sets also don't reduce definitions.
- **References:** https://docs.aws.amazon.com/singlesignon/latest/userguide/provision-automatically.html · https://docs.aws.amazon.com/singlesignon/latest/userguide/attributesforaccesscontrol.html · https://docs.aws.amazon.com/singlesignon/latest/userguide/delegated-admin.html
</details>

<details><summary>Q5 — Show answer</summary>

**Correct: A, B.**

- **Why:** a **Cognito user pool** provides sign-in with social providers and native accounts with no custom code. A **Cognito identity pool** exchanges user pool tokens for **temporary AWS credentials**. The `${cognito-identity.amazonaws.com:sub}` policy variable gives each user a private prefix. **Guest access** (unauthenticated role) gives signed-out users read-only DynamoDB access.
- **C:** creating IAM users and handing out long-term keys is an anti-pattern and doesn't scale (IAM user quotas, key leakage).
- **D:** IAM Identity Center is for **workforce** access to AWS accounts and applications, not consumer mobile apps.
- **E:** `aws:Referer` is easily spoofed, gives no per-user isolation, and makes the bucket effectively public for writes.
- **References:** https://docs.aws.amazon.com/cognito/latest/developerguide/cognito-identity.html · https://docs.aws.amazon.com/cognito/latest/developerguide/role-based-access-control.html · https://docs.aws.amazon.com/cognito/latest/developerguide/identity-pools.html
</details>

<details><summary>Q6 — Show answer</summary>

**Correct: B.**

- **Why:** **IAM Roles Anywhere** exchanges X.509 certificates from an existing PKI (registered as a **trust anchor**) for temporary credentials, which removes long-term keys. Profiles and role trust conditions on `aws:SourceArn` and certificate attributes (`aws:PrincipalTag/x509Subject/OU`) give each server group different permissions. The `aws_signing_helper` plugs into the SDK/CLI through `credential_process`.
- **A:** hybrid activations register servers as Systems Manager managed nodes. The role is meant for the SSM Agent's operations, not as a general-purpose application credential, and it doesn't use the PKI or the OU-based separation.
- **C:** still uses long-term credentials, so it fails the audit requirement.
- **D:** X.509 certificates aren't OIDC JWTs. An IAM OIDC provider can't validate client certificates.
- **References:** https://docs.aws.amazon.com/rolesanywhere/latest/userguide/introduction.html · https://docs.aws.amazon.com/rolesanywhere/latest/userguide/trust-model.html
</details>

<details><summary>Q7 — Show answer</summary>

**Correct: C.**

- **Why:** **AWS Managed Microsoft AD Enterprise Edition** supports **multi-Region replication**, which puts AWS-managed DCs in each Region with the same directory. RDS for SQL Server and FSx for Windows integrate with it in each Region. Service accounts and computer objects live in the AWS-hosted directory, so workloads keep authenticating if on-prem is unreachable. A **two-way forest trust** lets on-prem employees use their existing credentials. Note that employee logons through the trust still need on-prem DCs to be reachable. Operational effort is minimal compared with self-managed DCs.
- **A:** AD Connector is a proxy. Authentication fails when on-prem is unreachable, and RDS for SQL Server doesn't support AD Connector.
- **B:** multi-Region replication requires **Enterprise Edition**, not Standard.
- **D:** Simple AD supports no trusts and no RDS SQL Server/FSx integration, and it's closed to new customers.
- **References:** https://docs.aws.amazon.com/directoryservice/latest/admin-guide/ms_ad_configure_multi_region_replication.html · https://docs.aws.amazon.com/directoryservice/latest/admin-guide/what_is.html
</details>

<details><summary>Q8 — Show answer</summary>

**Correct: A, B, C.**

- **Why:** (1) an **organization-level unused access analyzer** (run from a delegated admin) finds unused roles, keys, passwords and unused services/actions across all accounts. (2) **Policy generation** builds least-privilege templates from CloudTrail activity (up to 90 days), and it can read an organization trail stored in another account with extra permissions. (3) **Custom policy checks** (`CheckAccessNotGranted`, `CheckNoPublicAccess`, `CheckNoNewAccess`) are designed for CI/CD gates.
- **D:** the credential report covers **IAM users in one account** only, not roles, and not the whole org.
- **E:** Trusted Advisor doesn't generate least-privilege policies.
- **F:** external access analyzers find **external sharing**, not unused permissions, and they are Regional.
- **References:** https://docs.aws.amazon.com/IAM/latest/UserGuide/what-is-access-analyzer.html · https://docs.aws.amazon.com/IAM/latest/UserGuide/access-analyzer-policy-generation.html · https://docs.aws.amazon.com/IAM/latest/UserGuide/access-analyzer-custom-policy-checks.html
</details>

<details><summary>Q9 — Show answer</summary>

**Correct: A, B.**

- **Why:** assuming a role with credentials from another role (here the instance profile) is **role chaining**, capped at **1 hour** whatever the target role's maximum. So `DurationSeconds=18000` is rejected. Option A keeps 1-hour sessions but lets the SDK refresh them automatically, which suits long jobs. Option B removes the chain: S3 and KMS both support resource-based policies, so account B can grant the instance role directly. The instance role then keeps its own identity and can read B's bucket and write A's bucket in the same process.
- **C:** `GetFederationToken` can be called only by IAM users (or root), not by role sessions.
- **D:** the role maximum is 12 hours and isn't a quota you can raise. It also wouldn't affect the chaining cap.
- **E:** introduces long-term credentials, which is an anti-pattern.
- **References:** https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles.html · https://docs.aws.amazon.com/IAM/latest/UserGuide/id_credentials_sts-comparison.html · https://docs.aws.amazon.com/sdkref/latest/guide/feature-assume-role-credentials.html
</details>

<details><summary>Q10 — Show answer</summary>

**Correct: B.**

- **Why:** **RCPs** restrict access to resources in member accounts and apply to any caller, including **AWS service principals**. Denying requests where `aws:SourceOrgID` isn't the company's org, scoped to service principals (`aws:PrincipalIsAWSService = true`) with `aws:SourceAccount` present, gives org-wide **cross-service confused-deputy** protection without touching bucket policies. Scoping it this way avoids breaking the company's own principals and service integrations that don't send source keys.
- **A:** SCPs don't apply to AWS service principals (or to external principals), and `aws:PrincipalOrgID` isn't populated for service principals.
- **C:** Access Analyzer is detective and remediation runs after the fact. It isn't one preventive control.
- **D:** means editing hundreds of policies, and `NotPrincipal` with Deny is discouraged and error-prone (service principals and role sessions are easy to get wrong).
- **References:** https://docs.aws.amazon.com/IAM/latest/UserGuide/confused-deputy.html · https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_policies_rcps.html
</details>

---

## 10. References

- IAM policy evaluation logic: https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_policies_evaluation-logic.html
- How the enforcement code evaluates requests: https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_policies_evaluation-logic_policy-eval-denyallow.html
- Cross-account policy evaluation logic: https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_policies_evaluation-logic-cross-account.html
- Policies and permissions (policy types): https://docs.aws.amazon.com/IAM/latest/UserGuide/access_policies.html
- AWS global condition context keys: https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_policies_condition-keys.html
- IAM and STS quotas: https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_iam-quotas.html
- The confused deputy problem: https://docs.aws.amazon.com/IAM/latest/UserGuide/confused-deputy.html
- Third-party access with External ID: https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_common-scenarios_third-party.html
- ABAC for AWS: https://docs.aws.amazon.com/IAM/latest/UserGuide/introduction_attribute-based-access-control.html
- Session tags: https://docs.aws.amazon.com/IAM/latest/UserGuide/id_session-tags.html
- Permissions boundaries: https://docs.aws.amazon.com/IAM/latest/UserGuide/access_policies_boundaries.html
- Compare AWS STS credentials: https://docs.aws.amazon.com/IAM/latest/UserGuide/id_credentials_sts-comparison.html
- Request temporary security credentials: https://docs.aws.amazon.com/IAM/latest/UserGuide/id_credentials_temp_request.html
- Centralized root access: https://docs.aws.amazon.com/IAM/latest/UserGuide/id_root-user.html
- Outbound identity federation: https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_providers_outbound.html
- IAM Identity Center User Guide: https://docs.aws.amazon.com/singlesignon/latest/userguide/what-is.html
- Identity Center attributes for access control: https://docs.aws.amazon.com/singlesignon/latest/userguide/attributesforaccesscontrol.html
- Identity Center trusted identity propagation: https://docs.aws.amazon.com/singlesignon/latest/userguide/trustedidentitypropagation.html
- Identity Center Regional behaviour and multi-Region: https://docs.aws.amazon.com/singlesignon/latest/userguide/resiliency-regional-behavior.html
- SAML 2.0 federation: https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_providers_saml.html
- OIDC federation: https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_providers_oidc.html
- Amazon Cognito Developer Guide: https://docs.aws.amazon.com/cognito/latest/developerguide/what-is-amazon-cognito.html
- Cognito identity pool role-based access control: https://docs.aws.amazon.com/cognito/latest/developerguide/role-based-access-control.html
- AWS Directory Service Administration Guide: https://docs.aws.amazon.com/directoryservice/latest/admin-guide/what_is.html
- Managed Microsoft AD multi-Region replication: https://docs.aws.amazon.com/directoryservice/latest/admin-guide/ms_ad_configure_multi_region_replication.html
- Simple AD availability changes: https://docs.aws.amazon.com/directoryservice/latest/admin-guide/simple-ad-availability-change.html
- IAM Access Analyzer: https://docs.aws.amazon.com/IAM/latest/UserGuide/what-is-access-analyzer.html
- Access Analyzer policy generation: https://docs.aws.amazon.com/IAM/latest/UserGuide/access-analyzer-policy-generation.html
- Access Analyzer custom policy checks: https://docs.aws.amazon.com/IAM/latest/UserGuide/access-analyzer-custom-policy-checks.html
- IAM Roles Anywhere User Guide: https://docs.aws.amazon.com/rolesanywhere/latest/userguide/introduction.html
- Service-linked roles: https://docs.aws.amazon.com/IAM/latest/UserGuide/using-service-linked-roles.html
- IMDSv2 / instance metadata: https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/configuring-instance-metadata-service.html
- Amazon Verified Permissions: https://docs.aws.amazon.com/verifiedpermissions/latest/userguide/what-is-avp.html
- AWS Verified Access: https://docs.aws.amazon.com/verified-access/latest/ug/what-is-verified-access.html
- IAM security best practices: https://docs.aws.amazon.com/IAM/latest/UserGuide/best-practices.html
- KMS key policies and cross-account access: https://docs.aws.amazon.com/kms/latest/developerguide/key-policy-modifying-external-accounts.html
- S3 Object Ownership: https://docs.aws.amazon.com/AmazonS3/latest/userguide/about-object-ownership.html
- Resource control policies: https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_policies_rcps.html

---
[← Previous](02-Multi-Account-Governance.md) · [Index](00-README-Start-Here.md) · [Next →](04-Networking-VPC-and-Hybrid-Connectivity.md)
