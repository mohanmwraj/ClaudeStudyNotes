# Chapter 02 — Multi-Account Strategy & Governance (Organizations, Control Tower, RAM)
> **Exam mapping:** D1 Task 1.2, D1 Task 1.4, D1 Task 1.5, D3 Task 3.2 | **Weight signal:** High (multi-account governance shows up in roughly 1 in 6 questions, often as the "frame" around a networking, security or cost question) | **Study time:** ~6 h
> [← Previous](01-Exam-Blueprint-and-Strategy.md) · [Index](00-README-Start-Here.md) · [Next →](03-Identity-and-Access-Management.md)

---

## 1. What the exam really tests here

SAP-C02 assumes you already know what an AWS account and an IAM policy are. What it tests is whether you can **run hundreds of accounts as one governed estate** with the least operational overhead. You'll usually be asked to make one of these decisions:

| Decision you must make | Typical stem signal | What a Professional answer looks like |
|---|---|---|
| **How to structure accounts and OUs** | "Company is growing, teams share one account, blast radius, separate billing" | Account per workload per environment; OUs grouped by **policy need, not org chart**; Security and Infrastructure OUs; a workloads OU split Prod / Non-Prod |
| **Which guardrail type** | "Prevent", "ensure no one can", "detect", "before resources are created", "even for administrators" | Preventive = SCP / RCP / declarative policy; detective = AWS Config rule; proactive = CloudFormation Hook; know which one each stem calls for |
| **Where the guardrail applies** | "Including the root user", "except the security team's role", "management account" | SCPs hit member-account root users but **never** the management account or service-linked roles; use `aws:PrincipalArn` for exceptions |
| **Keeping data inside the org** | "Only principals from our organization", "prevent data exfiltration to personal buckets", "third parties must not access" | Data perimeter: RCP + `aws:PrincipalOrgID` (identity), SCP + `aws:ResourceOrgID` (resource), `aws:SourceVpce` / `aws:SourceIp` (network) |
| **Landing zone automation** | "New accounts must automatically get baseline", "least effort", "Terraform", "existing accounts" | Control Tower + Account Factory; **AFT** when they say Terraform/GitOps; **CfCT** for CloudFormation/SCP customizations; StackSets service-managed with auto-deployment |
| **Sharing instead of duplicating** | "Centralize network", "avoid peering every VPC", "share TGW / subnets / Resolver rules" | AWS RAM, with sharing enabled for Organizations (no invitations); VPC sharing for same-trust-boundary workloads |
| **Delegating away from the management account** | "Minimize use of the management account", "security team operates tools" | **Delegated administrator** for GuardDuty, Security Hub, Config, CloudTrail, IAM Identity Center, StackSets, Firewall Manager and similar services |
| **Cost visibility and chargeback** | "Each business unit sees its own costs", "showback", "RI benefits must stay with the buying BU" | Consolidated billing, cost allocation tags, Cost Categories, RI/SP sharing preferences (including group sharing), Billing Conductor for pro forma rates |

Task 1.4 ("Design a multi-account AWS environment") and 1.5 ("Determine cost optimization and visibility strategies") come straight from this chapter. Task 1.2 (security controls) and 3.2 (improving security) add SCPs, RCPs, centralized logging and delegated security tooling.

---

## 2. Core concepts & services — deep dive

### 2.1 Why multiple accounts at all

The AWS account is the **hard isolation boundary** for security, quotas and billing. A resource in one account can't be reached from another account unless a policy explicitly allows it. AWS's guidance, in the *Organizing Your AWS Environment Using Multiple Accounts* whitepaper, names these reasons for using multiple accounts:

- **Group workloads by business purpose and ownership.** Each team owns its accounts end to end.
- **Apply distinct security controls by environment.** Prod and dev get different guardrails.
- **Constrain access to sensitive data.** PCI, PHI and other regulated data sit in dedicated accounts.
- **Promote innovation and agility.** Sandboxes can be permissive because they're isolated.
- **Limit the scope of impact (blast radius).** A compromised credential or runaway script affects one account.
- **Support multiple IT operating models.** Central IT, decentralized teams or a mix can all work.
- **Manage costs.** The account is the most reliable cost-allocation unit, more reliable than tags.
- **Distribute AWS service quotas and API request rate limits.** Most quotas are per account per Region.

> **Exam heuristic:** if a stem describes several teams in one account fighting over quotas, IAM sprawl or cost attribution, the answer is almost always **more accounts under AWS Organizations**, not more IAM policies or tags.

### 2.2 AWS Organizations — the foundation

**What it is.** AWS Organizations is a free, global service, physically hosted in `us-east-1`. It groups accounts into a hierarchy: one **root**, nested **organizational units (OUs)**, and accounts. On that hierarchy you get **consolidated billing**, **organization policies** and **service integrations** (trusted access and delegated administrators).

**Feature sets**

| Feature set | What you get | Notes |
|---|---|---|
| **Consolidated billing only** | One bill, volume-tier aggregation, RI/SP sharing | No SCPs, RCPs or other policies; limited integrations. Mostly legacy. |
| **All features** (default and recommended) | Everything above, plus all policy types, trusted access and delegated admin | Moving from consolidated billing to all features requires **every invited member account to approve** (a handshake valid for 90 days). Accounts created by the org approve automatically. |

**Entities and key quotas.** The values below are defaults from the Organizations quotas page and were verified in October 2026.

| Item | Value | Adjustable? |
|---|---|---|
| Accounts per organization | **10** default. New orgs can start lower. | Yes, via Service Quotas from the management account. AWS can grant up to 50,000 based on qualification. |
| Roots | 1 | No |
| OUs per organization | 2,000 | — |
| OU nesting depth | **5 levels** of OUs under the root | No |
| Concurrent `CreateAccount` operations | 5 | No |
| Minimum age before a *created* account can be removed | **4 days** (older docs said 7). Invited accounts are exempt. | No |
| Account closures | 20% of member accounts or 250, whichever is higher, capped at 1,000 per rolling 30 days. Only 3 closures can run concurrently. | No |
| Invitation expiry | 15 days | — |
| Tags per root, OU or account | 50 | — |

**Accounts get into an organization in two ways:**
1. **Create.** Call `CreateAccount` from the management account or a delegated admin. Organizations automatically creates the **`OrganizationAccountAccessRole`** in the new account. The role has `AdministratorAccess` and trusts the management account. New accounts come **without root user credentials** if centralized root access is enabled (see below). You still provide a unique root email address.
2. **Invite.** The management account sends an invitation and the existing account accepts it. **No `OrganizationAccountAccessRole` is created automatically.** You must create a cross-account admin role yourself, for example with a StackSet.

#### The management account — best practices (high-yield)

The management account, formerly called the *master* or *payer* account, is special:
- **SCPs and RCPs never apply to it.** It can do anything, including detaching every guardrail.
- It **pays the bill** for the whole organization and is the only account that can invite, remove or close accounts (unless that power is delegated). It's also where many organization-wide features are first enabled.
- **Best practices:**
  - Run **no workloads** in it.
  - Keep the number of human users with access as small as possible, and grant that access through IAM Identity Center.
  - Protect the root user with MFA, use a group-owned email address, and keep break-glass procedures.
  - Use it only for tasks that *require* the management account.
  - Push everything else to **delegated administrator** accounts. Examples: Security Hub and GuardDuty to a Security Tooling (Audit) account, IPAM to the Network account, StackSets to an automation account.
  - Monitor it heavily, for example with an EventBridge rule on root sign-in.

> **Trap:** "Attach an SCP to restrict the management account" never works. The fix is to *not use* the management account and to move capabilities to delegated admins.

#### Trusted access vs delegated administrator

| Concept | What it does | Who does it |
|---|---|---|
| **Trusted access** (`EnableAWSServiceAccess`) | Lets an AWS service create service-linked roles and act in all member accounts. Examples: CloudTrail org trails, Config aggregators, RAM org sharing, Identity Center, StackSets service-managed. | Management account. **Prefer enabling it from the service's own console or API.** The service then performs its own setup; for example, RAM creates its SLR only when you enable sharing from RAM. |
| **Delegated administrator** (`RegisterDelegatedAdministrator`) | Designates a **member account** that administers a service for the whole org | Management account registers it. Many services allow only one delegated admin; **StackSets allows up to 5**. |
| **Organizations delegated administrator** | A *resource-based delegation policy* (up to 40,000 characters) that lets a member account manage Organizations policies or view the structure, for example creating and attaching tag policies or SCPs | Management account |

Remember that **SCPs and RCPs *do* apply to delegated administrator accounts**, because they're ordinary member accounts.

#### Centralized root access management (Nov 2024)

IAM's **centralized root access for member accounts** works only in organizations with all features enabled and needs trusted access for IAM. It lets the management account or an IAM delegated admin do the following:
- **Remove root credentials** (password, access keys, signing certificates, MFA) from member accounts. Accounts created afterwards have no root credentials by default.
- Perform **privileged root tasks** through short-term `sts:AssumeRoot` sessions:
  - Delete an S3 bucket policy that denies all principals.
  - Delete an SQS queue policy that denies all principals.
  - Allow password recovery for a member account's root user.

Pair it with an SCP that denies root actions in member accounts. Deep dive in [Chapter 03](03-Identity-and-Access-Management.md).

#### Moving accounts and leaving the organization

- **Moving between OUs** (`MoveAccount`) is instant. The account immediately inherits the destination OU's policies. If Control Tower governs the OUs, move the account through Control Tower (or with auto-enrollment) to avoid **drift**. Service-managed StackSets with auto-deployment remove the old OU's stacks and add the new OU's stacks.
- **Removing or leaving** (`RemoveAccountFromOrganization` from the management account, or `LeaveOrganization` from the member):
  - The account needs **standalone information first**: a payment method, a support plan, and verified contact details.
  - A *created* account must be at least **4 days** old.
  - It can't be a **delegated administrator** for any service. Deregister it first.
  - After it leaves:
    - No organization policies apply, so the account may suddenly have more permissions.
    - Its tags (Organizations tags on the account) are deleted.
    - It loses access to the org-period cost data.
    - Organization agreements in AWS Artifact stop covering it.
    - The `OrganizationAccountAccessRole` is **not deleted**. Remove it manually.
  - Block unauthorized departures with an SCP that **denies `organizations:LeaveOrganization`**. This is a classic exam answer.
- **Moving an account to another organization:**
  - **Classic method** (what most exam questions assume): remove the account from organization A so it becomes standalone, then accept organization B's invitation.
  - **Direct transfer** (launched **November 2025**): organization B's management account invites the account, and the account accepts *without* first leaving organization A. It keeps consolidated-billing coverage throughout. Constraints:
    - Closed or suspended accounts can't move.
    - A created account must be at least 4 days old.
    - The destination organization must be at least 7 days old.
    - The seller of record must match.
  - **Either way:**
    - AWS RAM shares scoped to the org or an OU stop working once the account is in organization B.
    - SCP protection changes.
    - Delegated-admin registrations must be removed first.
  - A **management account can't move**. You must delete its organization first.
- **Closing accounts** (`CloseAccount`, or from the console in the management account):
  - The account enters a **90-day post-closure period**. It shows as `SUSPENDED` / `CLOSED`, can be **reopened** during that time, and **still counts toward the organization's account quota**.
  - After 90 days AWS permanently closes it and deletes its content (CloudTrail trails excepted). The account ID is never reused.
  - Unpaid RI/SP commitments continue to be billed.
  - With Control Tower, **unmanage** the account first.
  - Best practice: move the account to a **Suspended OU** with a deny-all SCP first. Then close it or remove it from the org to free quota.

### 2.3 Recommended OU structure (whitepaper)

The whitepaper groups OUs into categories. Memorize the names and their purpose. Exam stems use them ("a Policy Staging OU", "a Suspended OU").

| Category | OU | Purpose | Typical accounts |
|---|---|---|---|
| **Foundational** | **Security** | Accounts that apply security, governance and compliance controls across the org. Treat as production; tightly restricted. | **Log Archive** (immutable CloudTrail, Config and VPC Flow Logs); **Security Tooling** / **Audit** (delegated admin for GuardDuty, Security Hub, Inspector, Macie, Detective; cross-account read-only and break-glass roles) |
| | **Infrastructure** | Shared infrastructure and networking services | **Network** (TGW, Direct Connect, inspection VPC, IPAM, Route 53 Resolver endpoints); **Shared Services** (directory, CI tooling, golden AMIs, monitoring) |
| **Application** | **Workloads** | Business workloads, with child OUs **Prod** and **Non-Prod** (or SDLC tiers) | One account per workload per environment |
| **Experimental** | **Sandbox** | Experimentation, disconnected from internal networks and production data | Per-developer or per-team sandboxes with spend limits |
| **Procedural** | **Policy Staging** | Test changes to SCPs, RCPs and other org policies before promoting them | Mirror of the production OU structure with test accounts |
| | **Suspended** | Accounts suspended, closed or quarantined for security reasons; deny-all SCP | Accounts pending closure, compromised accounts |
| | **Exceptions** | Workloads that need policies deviating from the standard (attach the exception at this OU) | Rare; audited |
| | **Transitional** | Temporary home during migration or M&A integration | Accounts newly joined or transferred from another org |
| **Advanced** | **Individual Business Users** | Accounts for individual employees or business units (e.g., marketing tools) | Limited-permission accounts |
| | **Deployments** | CI/CD accounts that deploy into other accounts | Pipeline accounts |
| | **Business Continuity** | DR and backup accounts | Logically air-gapped backup vault accounts |

**Design principles to quote:**
- Organize OUs by **function and the controls they need**, not by the reporting structure. Re-orgs happen far more often than control changes.
- Apply policies at **OUs**, not individual accounts.
- Keep the hierarchy **shallow**. Five levels is a hard limit, and 2–3 is practical.
- Workload accounts should have **no shared VPCs that span environments**. Prod and non-prod networks stay separate.

### 2.4 Service control policies (SCPs)

**What they are.** SCPs are **authorization policies** that set the **maximum permissions** for IAM users and roles in member accounts. **They never grant permissions.** An action succeeds only if it is allowed by the SCPs at **every level** from the root down to the account **and** by identity- or resource-based policies, and is not denied by any policy.

**Who is affected and who isn't (memorize):**

| Affected by SCPs | NOT affected by SCPs |
|---|---|
| All IAM users and roles in **member accounts** | **Any principal in the management account** |
| The **member account's root user** | **Service-linked roles** (e.g., `AWSServiceRoleForConfig`) |
| Delegated administrator accounts (they're members) | Principals from **outside the organization** accessing your resources through resource-based policies. Use **RCPs** for those. |
| IAM Identity Center permission-set roles (they're IAM roles) | Service principals (e.g., `cloudtrail.amazonaws.com`) |
| | A few root-only tasks, such as registering for Enterprise Support or CloudFront trusted signer keys |

**Evaluation / inheritance:**

```text
             Root  [FullAWSAccess]  [Deny-LeaveOrg]
               │
         OU: Workloads  [FullAWSAccess]  [Deny-Regions]
               │
         OU: Prod  [FullAWSAccess]
               │
         Account 1111  [FullAWSAccess]
```

- **Deny:** an explicit `Deny` attached at **any** level (root, any OU in the path, or the account) applies to the account. Denies are inherited.
- **Allow:** for an action to be possible, it must be allowed **at every level** (root AND each OU AND the account). Allows are *not* inherited in the sense that matters: a child can't widen what a parent didn't allow, but each level must also allow it itself.
- When SCPs are enabled, AWS attaches the AWS-managed **`FullAWSAccess`** SCP (`Allow *:*`) to the root, every OU and every account. Every entity must always have at least one SCP attached.
- If you disable the SCP policy type, all attachments are lost. Re-enabling it reattaches only `FullAWSAccess`.

**Deny-list vs allow-list strategy**

| | **Deny list** (default, recommended) | **Allow list** |
|---|---|---|
| How | Keep `FullAWSAccess` everywhere; add `Deny` statements for what's forbidden | Remove `FullAWSAccess`; attach `Allow` SCPs listing permitted services **at every level** |
| New AWS services | Automatically allowed | Blocked until added |
| Maintenance | Low | High. Every level needs a matching `Allow` |
| Typical use | Most orgs | Highly regulated environments with a strict service allowlist, or a sandbox locked to approved services |
| Gotcha | Size limits once you stack many denies | Forgetting the `Allow` at one OU silently blocks the service even for admins |

**Syntax facts:**
- Supported elements: `Effect`, `Action`/`NotAction`, `Resource`/`NotResource`, `Condition`, `Sid`, `Version`.
- **`Principal` and `NotPrincipal` are not supported.** To target or exempt principals, use the `aws:PrincipalArn` condition.
- In **Allow** statements, `Resource` can only be `"*"`. In Deny statements you can list specific ARNs. `Condition` and `NotAction` now work in both Allow and Deny.

**SCP quotas** (current docs, October 2026):

| Quota | Current value | Older value you may see in practice questions |
|---|---|---|
| Max SCP document size | **10,240 characters** | 5,120 characters (before **May 2026**) |
| SCPs directly attached per root, OU or account | **10** | 5 (before May 2026) |
| SCPs per organization | 10,000 | — |
| Inherited SCPs | Don't count toward the per-entity limit | — |

> SAP-C02 items were written against the old 5 / 5,120 limits. If an answer depends on "you can attach a maximum of 5 SCPs", recognize that it reflects the old quota. The *design* answer (consolidate statements, attach at a higher OU, remove whitespace) is the same either way. Console saves strip whitespace; CLI and SDK saves don't.

**High-yield condition keys in SCPs**

| Key | Use |
|---|---|
| `aws:RequestedRegion` | Region restriction (with `NotAction` exceptions for global services) |
| `aws:PrincipalArn` | Exempt break-glass, pipeline or Control Tower roles: `ArnNotLike` → `arn:aws:iam::*:role/BreakGlass` |
| `aws:PrincipalOrgID` / `aws:PrincipalOrgPaths` | Mostly in resource policies and RCPs, not SCPs (an SCP principal is always in your org) |
| `aws:ResourceOrgID` / `aws:ResourceOrgPaths` / `aws:ResourceAccount` | **Resource perimeter**: my principals may only touch resources owned by my org |
| `aws:SourceIp`, `aws:SourceVpc`, `aws:SourceVpce` | **Network perimeter**: my principals may only call from expected networks |
| `aws:ViaAWSService`, `aws:CalledVia` | Exempt calls that AWS makes on your behalf (forward access sessions), e.g., CloudFormation or Athena |
| `aws:PrincipalTag/...` | Attribute-based exceptions (e.g., `team=security`) |
| `aws:RequestTag/...`, `aws:TagKeys` + `Null` | Require tags on create calls |
| `aws:MultiFactorAuthPresent` | Require MFA for sensitive actions |
| `ec2:InstanceType`, `rds:DatabaseClass`, `s3:x-amz-server-side-encryption`, `ram:RequestedAllowsExternalPrincipals` | Service-specific guardrails (sizes, encryption, no external RAM sharing) |

**Canonical region-deny SCP with global-service and principal exceptions** (abbreviated `NotAction` list; use the full one from the docs):

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Sid": "DenyOutsideApprovedRegions",
    "Effect": "Deny",
    "NotAction": [
      "iam:*", "organizations:*", "sts:*", "account:*",
      "cloudfront:*", "route53:*", "route53domains:*", "globalaccelerator:*",
      "waf:*", "wafv2:*", "shield:*", "support:*", "trustedadvisor:*",
      "health:*", "budgets:*", "ce:*", "cur:*", "aws-portal:*", "pricing:*",
      "directconnect:*", "networkmanager:*", "kms:*", "s3:ListAllMyBuckets",
      "s3:GetAccountPublic*", "s3:PutAccountPublic*", "ec2:DescribeRegions"
    ],
    "Resource": "*",
    "Condition": {
      "StringNotEquals": { "aws:RequestedRegion": ["eu-west-1", "eu-central-1"] },
      "ArnNotLike": { "aws:PrincipalArn": [
        "arn:aws:iam::*:role/BreakGlassAdmin",
        "arn:aws:iam::*:role/AWSControlTowerExecution"
      ]}
    }
  }]
}
```

Why the exceptions matter:
- Global services such as IAM, Organizations, CloudFront, Route 53 and Support have their control plane in `us-east-1`. A plain region deny breaks them.
- `ArnNotLike` on `aws:PrincipalArn` exempts named roles. Multiple condition operators in one statement are **ANDed**, so the deny applies only if the Region isn't approved AND the caller isn't an exempted role.

**Other SCP patterns to know by heart:**
- Deny `organizations:LeaveOrganization`.
- Deny disabling or modifying security services: `cloudtrail:StopLogging`, `cloudtrail:DeleteTrail`, `guardduty:DeleteDetector`, `guardduty:DisassociateFromMasterAccount`, `config:StopConfigurationRecorder`, `securityhub:DisableSecurityHub`, `access-analyzer:DeleteAnalyzer`.
- Deny root user actions in member accounts: `Condition: StringLike aws:PrincipalArn arn:aws:iam::*:root`.
- Protect Control Tower or platform roles from modification: deny `iam:*Role*` on `arn:aws:iam::*:role/PlatformAdmin*` unless the caller is that role.
- Deny creating IAM users and access keys (`iam:CreateUser`, `iam:CreateAccessKey`) to force federation.
- Deny `ec2:RunInstances` unless `ec2:InstanceType` is in an approved list (sandbox cost control).
- Require IMDSv2: deny `ec2:RunInstances` when `ec2:MetadataHttpTokens` ≠ `required`. Declarative policies can now enforce this as a configuration instead.
- Deny `ram:CreateResourceShare` / `ram:UpdateResourceShare` when `ram:RequestedAllowsExternalPrincipals` = `true`.
- Deny everything in the **Suspended OU**: `Deny *:*`.

**Testing SCPs:**
1. Use service last accessed data (IAM Access Advisor at the org/OU level) to find unused services.
2. Attach new SCPs first to a **Policy Staging OU**, then promote them.
3. Never attach an untested SCP to the root.
4. CloudTrail `AccessDenied` events mention *"with an explicit deny in a service control policy"*, which helps troubleshooting.

### 2.5 Resource control policies (RCPs) — Nov 2024

**Why they exist.** SCPs restrict **your principals**. They can't stop an **external principal** (another org, a personal account, a third party) from accessing your S3 bucket or KMS key if a resource policy is misconfigured. **RCPs restrict what can be done to your resources, no matter who is calling.** They're the organization-wide preventive control for the **identity perimeter** on resources.

| Property | RCP |
|---|---|
| Category | Authorization policy (like SCPs). Never grants permissions. |
| Applies to | **Resources** in member accounts, for supported services, **including access by principals outside your org** and by root users |
| Does NOT apply to | Resources in the **management account**; calls by **service-linked roles**; **AWS managed KMS keys**; `kms:RetireGrant` |
| Default | **`RCPFullAWSAccess`** auto-attached to root, every OU and every account when enabled. **It can't be detached** and counts toward the per-entity limit. |
| Evaluation | Like SCPs: an explicit deny at any level wins; access must be permitted at every level |
| Limits | 5,120 characters per RCP; **5** per root, OU or account; 2,000 per org |
| Typical statements | Deny-only, with `aws:PrincipalOrgID`, `aws:SourceOrgID`, `aws:PrincipalIsAWSService`, `aws:SecureTransport`, `aws:SourceVpce` |
| Services | Launched with **S3, STS, KMS, SQS, Secrets Manager**. The list has since grown to dozens, including DynamoDB, ECR, CloudWatch Logs, Cognito, OpenSearch Serverless, Data Firehose, EventBridge, CodeBuild and more. Check the current list. |

**Canonical RCP: only my org (plus AWS services acting for my org) may access my S3, KMS, SQS, Secrets Manager and STS resources:**

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Sid": "EnforceOrgIdentities",
    "Effect": "Deny",
    "Principal": "*",
    "Action": ["s3:*", "sqs:*", "kms:*", "secretsmanager:*", "sts:AssumeRole"],
    "Resource": "*",
    "Condition": {
      "StringNotEqualsIfExists": {
        "aws:PrincipalOrgID": "o-exampleorg",
        "aws:ResourceTag/dp:exclude:identity": "true"
      },
      "BoolIfExists": { "aws:PrincipalIsAWSService": "false" }
    }
  }]
}
```

Notes on this policy:
- RCPs **do** use `"Principal": "*"`, unlike SCPs. Only `"*"` is allowed.
- Use `aws:PrincipalIsAWSService` to exempt service principals such as `cloudtrail.amazonaws.com`. Then add a second statement with `aws:SourceOrgID` so services can only write on behalf of *your* org. This mitigates the confused-deputy problem.
- Exceptions for known third-party accounts go in a condition (`aws:PrincipalAccount`) or a resource-tag escape hatch.

**Other RCP patterns:**
- Require TLS on all requests (`aws:SecureTransport` = `false` → Deny).
- Require S3 SSE-KMS.
- Restrict `sts:AssumeRole` on your roles to org principals, which prevents trust policies that trust external accounts.
- Require that S3 access arrives through your VPC endpoints (`aws:SourceVpce`), with exceptions for AWS services.

### 2.6 Data perimeter (identity, resource, network)

A data perimeter is a set of preventive guardrails ensuring that **only trusted identities** access **trusted resources** from **expected networks**. The *Building a Data Perimeter on AWS* whitepaper maps each perimeter to policy types:

| Perimeter | Control objective | Primary policy type | Key condition keys |
|---|---|---|---|
| **Identity** | Only trusted identities can access *my resources* | **RCP** (org-wide), resource-based policies | `aws:PrincipalOrgID`, `aws:PrincipalOrgPaths`, `aws:PrincipalAccount`, `aws:PrincipalIsAWSService`, `aws:SourceOrgID` |
| | Only trusted identities are allowed from *my networks* | **VPC endpoint policies** | `aws:PrincipalOrgID` |
| **Resource** | *My identities* can access only trusted resources | **SCP** | `aws:ResourceOrgID`, `aws:ResourceOrgPaths`, `aws:ResourceAccount` |
| | Only trusted resources can be reached from *my networks* | **VPC endpoint policies** | `aws:ResourceOrgID` (or explicit resource ARNs) |
| **Network** | *My identities* can access resources only from expected networks | **SCP** | `aws:SourceIp`, `aws:SourceVpc`, `aws:SourceVpce`, exempting `aws:ViaAWSService` |
| | *My resources* can be accessed only from expected networks | **RCP**, resource-based policies | `aws:SourceIp`, `aws:SourceVpce`, `aws:SourceVpc`, exempting `aws:PrincipalIsAWSService` and `aws:ViaAWSService` |

Common exceptions:
- AWS-owned buckets: Amazon Linux repos, SSM agent and CloudFormation wait-condition presigned URLs. Allow them in **VPC endpoint policies** and exempt them in the resource-perimeter SCP using `NotAction`.
- Services acting on your behalf: use `aws:ViaAWSService` / `aws:CalledVia`.
- Service principals: use `aws:PrincipalIsAWSService` plus `aws:SourceOrgID`.

Sharing APIs bypass the `aws:ResourceOrgID` check, because the resource is yours but the target isn't. Control them separately:
- `ec2:ModifyImageAttribute` (AMI sharing) and `ec2:ModifySnapshotAttribute` (EBS snapshot sharing): SCP deny, or declarative policies for block-public-access.
- `rds:ModifyDBSnapshotAttribute`: SCP deny.
- RAM sharing outside the org: SCP deny with `ram:RequestedAllowsExternalPrincipals`.
- CloudWatch Logs subscription filters and EventBridge cross-account targets: SCP deny or detective control.

> The exam loves **"prevent employees from copying data to a personal S3 bucket"**. Answer: an **SCP (or VPC endpoint policy) with `aws:ResourceOrgID`**. A bucket policy can't do it, because you don't own the personal bucket. **"Prevent anyone outside the organization from accessing our buckets even if a bucket policy is misconfigured"** → **RCP with `aws:PrincipalOrgID`**. Before RCPs existed, the expected answer was bucket policies with `aws:PrincipalOrgID` on every bucket, plus Config rules and IAM Access Analyzer to detect misconfiguration.

### 2.7 Declarative policies (Dec 2024) and other management policy types

Organizations groups policies into **authorization policies** (SCPs, RCPs) and **declarative policies**. AWS now files all the "management" policy types (tag, backup, AI opt-out, chat applications and others) under the declarative category. Unlike SCPs and RCPs, **declarative/management policies DO affect the management account** and support viewing the **effective policy** for an account.

**Amazon EC2 declarative policies (often just called "declarative policies")**
- Enforce a desired **service configuration** in the EC2 control plane, rather than denying API calls.
- **"Set once and forget":**
  - The configuration holds even when the service adds new APIs or features.
  - It applies to new accounts as they join, and to new principals and resources.
  - It applies to **service-linked roles** too.
- **Detaching rolls the attribute back** to its previous state.
- **Account status report**: shows the current state of supported attributes across accounts before you enforce.
- **Custom error messages**: point users to your internal wiki.
- Supported EC2 attributes include:
  - **VPC Block Public Access** (block IGW traffic org-wide, with exclusions)
  - **EC2 serial console access**
  - **AMI block public access**
  - **Allowed AMIs** (only images from specified owners/providers can be discovered and launched)
  - **Instance metadata defaults** (e.g., IMDSv2 required)
  - **EBS snapshot block public access**

| | SCP | RCP | Declarative policy |
|---|---|---|---|
| Controls | Max permissions of *principals* | Max permissions on *resources* | *Configuration* of a service |
| Mechanism | API authorization | API authorization | Service control plane enforcement |
| Governs SLRs? | No | No | **Yes** |
| Affects management account? | No | No | **Yes** |
| New API added by AWS | May need SCP update | May need update | Configuration still enforced |
| Example | Deny leaving the org | Deny non-TLS access to resources | Block public AMIs org-wide |

**Other management policy types** (all need *all features* enabled; inheritance uses operators such as `@@assign`, `@@append`, `@@remove`, and child-control operators `@@operators_allowed_for_child_policies`):

| Policy | What it does | Key facts |
|---|---|---|
| **Tag policies** | Standardize tag **key capitalization** and **allowed values**. Optionally **enforce** (block non-compliant tagging operations) on listed resource types. | **Don't prevent creating untagged resources.** Untagged resources, and tags not defined in the policy, aren't evaluated. To *require* tags, use an **SCP** with `aws:RequestTag` + `Null`, or proactive controls (CloudFormation Hooks). Compliance is reported through Resource Groups / Tag Editor, and org-wide from the management account. Max 10 per entity, 10,000 characters. |
| **Backup policies** | Deploy **AWS Backup plans** (schedule, lifecycle, vault, cross-Region/cross-account copy) to accounts, selecting resources by tag | Cross-account management must be enabled in AWS Backup. Pairs with **logically air-gapped vaults** (shareable via RAM) and a delegated admin for Backup. |
| **AI services opt-out policies** | Opt every account out of AWS using content from AI services (e.g., Rekognition, Comprehend, Transcribe, Lex) for service improvement | Max **5** per entity, **2,500 characters** |
| **Chat applications policies** (formerly *chatbot* policies) | Control which chat platforms (Slack, Microsoft Teams, Amazon Chime) and workspaces can access accounts through **Amazon Q Developer in chat applications** (formerly AWS Chatbot), plus channel guardrails | Max 5 per entity |
| **Security Hub, Inspector, GuardDuty, Bedrock, S3, upgrade rollout policies** (2025–2026 additions) | Centrally enable or configure those services: Security Hub coverage, Inspector or GuardDuty enablement, Bedrock Guardrails on all inference calls, S3 settings, staggered auto-upgrades | Newer than most SAP-C02 items. Recognize them, but expect classic answers (delegated admin + auto-enable). |

> **Emerging / SAP-C03 preview (not core):** Amazon Bedrock policies enforce **Bedrock Guardrails** on every model invocation across an OU, which is exactly the kind of central AI governance control C03 adds.

### 2.8 AWS Control Tower

**What it is.** Control Tower is a managed **landing zone** service that orchestrates Organizations, IAM Identity Center, CloudTrail, Config, Service Catalog, CloudFormation StackSets and Security Hub. It builds a well-architected multi-account baseline and keeps governing it. It is **the "least operational overhead" answer for setting up and governing a new multi-account environment**.

**What setup creates (classic landing zone, versions 3.x):**
- **Management account.** Your existing org's management account, or a new one.
- **Security OU** containing:
  - **Log Archive account**: S3 buckets for the **organization CloudTrail trail** and **Config** history, with lifecycle and access logging.
  - **Audit account**: a security-team account with cross-account **read-only and admin roles** into all enrolled accounts, SNS topics for Config compliance and drift notifications, and often the delegated admin for Security Hub and GuardDuty.
  - You can only designate *existing* accounts as Log Archive or Audit **during initial setup**.
- An additional OU (often **Sandbox**) for workloads.
- **IAM Identity Center** with preconfigured groups and permission sets. Since 2023 you can opt out and self-manage identity.
- An **organization-level CloudTrail trail**, on by default since landing zone 3.0.
- **AWS Config** recorders in governed accounts and Regions, with a central aggregator in the Audit account.
- **Mandatory controls**, plus an optional **Region deny** setting and optional **AWS Backup** integration (central backup vault and backup administrator accounts; landing zone 3.3+).
- **Account Factory**: an AWS Service Catalog product for vending accounts.

> **Newer behaviour (landing zone 4.0):**
> - AWS Config, CloudTrail, SecurityRoles and Backup integrations are **optional and toggleable**.
> - Control Tower no longer forces creation of a Security OU.
> - Drift notifications go to **EventBridge** instead of SNS.
> - Mandatory controls are no longer applied by default.
> - A service-linked Config aggregator replaces the org aggregator.
>
> SAP-C02 questions describe the classic 3.x model above. Answer with it.

**Controls (formerly "guardrails")**

| Behavior | Implemented with | Status values | Example |
|---|---|---|---|
| **Preventive** | **SCPs**, **RCPs**, **declarative policies** | Enforced / Not enabled | Disallow changes to CloudTrail config; disallow public AMIs |
| **Detective** | **AWS Config rules** (Control Tower-managed or Security Hub service-managed standard) | Clear / In violation / Not enabled | Detect unencrypted EBS volumes; detect S3 public read |
| **Proactive** | **CloudFormation Hooks** (evaluate resources *before* CloudFormation provisions them) | PASS / FAIL / SKIP | Require S3 buckets to have versioning in CFN templates |

| Guidance | Meaning |
|---|---|
| **Mandatory** | Always on (in 3.x), protect Control Tower's own resources. Examples: disallow deleting the Log Archive bucket, disallow changes to CT-created CloudTrail, Config and IAM roles. You can't disable them. |
| **Strongly recommended** | Best practice for multi-account environments. Examples: disallow creation of root user access keys, detect whether MFA is enabled for the root user, detect public read access to S3 buckets. Enabled per OU. |
| **Elective** | Commonly restricted actions. Examples: disallow S3 delete without MFA, Region deny per OU (`CT.MULTISERVICE.PV.1`). Enabled per OU. |

Facts about controls:
- Controls apply to **OUs** (all accounts in the OU), not individual accounts.
- The **management account is exempt**, but its actions are still logged to Log Archive.
- The **Control Catalog** is the unified library and API (`controlcatalog`) of controls across Control Tower, Security Hub and Config. You can enable controls through the Control Tower APIs (`EnableControl`) or CloudFormation. Up to 100 control operations can be in flight, with 10 executing at once.
- Detective controls work only in Control Tower **governed Regions**. Preventive controls work in all Regions.

**Region deny**
- **Landing-zone-wide** `AWS-GR_REGION_DENY` is set in landing zone settings. It denies actions outside the governed Regions, with built-in exemptions for global services such as IAM and Organizations. **You can't deny the home Region.**
- **OU-level** `CT.MULTISERVICE.PV.1` is an elective control. It allows a per-OU list of Regions, **exempt IAM principal ARNs** and exempt actions.
- Before enabling either, make sure no resources exist in the Regions you're denying.

**Account Factory, vending and customization options**

| Option | What it is | Choose when |
|---|---|---|
| **Account Factory (console / Service Catalog)** | Vend accounts into a registered OU with a standard baseline and optional VPC configuration | Small scale, manual requests, simple baseline |
| **Account Factory Customization (AFC)** | Attach a **blueprint** (a Service Catalog product backed by CloudFormation, or Terraform in one Region) applied at vending time | Per-account-type customizations without building pipelines |
| **Account Factory for Terraform (AFT)** | Open-source framework deployed into a **dedicated AFT management account**. Account requests are Terraform files in a Git repo (CodeCommit, GitHub, Bitbucket, GitLab through CodeConnections). A **GitOps pipeline** (CodePipeline/CodeBuild, Step Functions, Lambda, DynamoDB) creates accounts through Account Factory and applies **global and account-specific customizations** (Terraform or Python hooks), plus optional **feature options**: delete default VPCs, enable CloudTrail data events, enroll in Enterprise Support. Supports Terraform OSS, Terraform Cloud and Terraform Enterprise. | Stem says **"Terraform"**, "GitOps", "pipeline-based account requests", "hundreds of accounts with customizations" |
| **Customizations for Control Tower (CfCT)** | AWS Solution. A **manifest file** (`manifest.yaml`) plus CloudFormation templates and **SCP/RCP JSON** in S3 or CodeCommit. A CodePipeline deploys them as **StackSets and Organizations policies**, triggered by changes and by Control Tower **lifecycle events** (e.g., `CreateManagedAccount`) so new accounts get customized automatically. | Stem says **CloudFormation** customizations, custom SCPs, "automatically apply to new accounts when they're vended" |
| **Landing Zone Accelerator on AWS (LZA)** | AWS Solution (CDK-based) that layers on Control Tower to deploy a comprehensive, compliance-oriented baseline (networking, security services) from config files | Regulated industries (e.g., FedRAMP, CMMC, TSE), "comprehensive compliance baseline" |
| **Control Tower APIs / CloudFormation** | `CreateLandingZone`, `EnableBaseline`, `EnableControl` | IaC management of the landing zone itself |

Concurrency limits:
- Account Factory runs up to **5** account operations (provision, update, enroll) concurrently.
- Other landing-zone operations run one at a time.
- Control Tower supports up to **10,000 accounts**.
- OUs with **more than 1,000 directly nested accounts** can't be registered.

**Bringing an existing organization or existing accounts under Control Tower**
- **Register an OU / extend governance.** Control Tower enrolls every account in the OU. Each account needs the `AWSControlTowerExecution` role (an admin role trusting the management account). Accounts are baselined with StackSets (CloudTrail, Config, roles).
- **Enroll an individual account** into a registered OU, from Account Factory or the console. Prerequisites:
  - **Remove any existing AWS Config recorder and delivery channel**, or follow the documented procedure for accounts with existing Config resources.
  - Create `AWSControlTowerExecution` (for invited accounts).
  - Check that existing SCPs don't block CT roles.
  - Delete existing account-level trails to avoid duplicate CloudTrail charges.
- Enrollment **doesn't delete existing VPCs**. Newly vended accounts get the default VPC removed and a CT VPC created, unless you configure Account Factory for "no VPC".
- **Auto-enrollment** (newer): accounts moved into a registered OU are enrolled automatically.

**Drift**
- Drift means the landing zone no longer matches what Control Tower deployed. Causes include:
  - Moving an account between OUs outside Control Tower.
  - Removing an account from the org.
  - Modifying or detaching a Control Tower-managed SCP.
  - Deleting a registered OU.
  - Changing CT-managed roles.
- Notifications go to the Audit account SNS topic in 3.x, and to EventBridge in 4.0.
- **Repair:**
  - **Reset the landing zone** (Landing zone settings → Repair) for landing-zone drift.
  - **Re-register the OU** for OU or control drift.
  - **Update the account** in Account Factory for account drift.
- Prevent drift by managing the CT-governed structure **only through Control Tower** and by protecting CT roles with SCPs. The mandatory controls do this.

### 2.9 AWS Resource Access Manager (RAM)

**What it is.** RAM is a free **Regional** service that shares resources you own with other accounts, OUs, the whole organization, or (for some types) IAM roles, IAM users and service principals. You **share the resource, not a copy**. The owner keeps control, quotas and billing for the resource itself.

**Sharing within Organizations:**
- Enable it **from the RAM console or `enable-sharing-with-aws-organization`** in the management account. Enabling trusted access from the Organizations console instead doesn't create the RAM service-linked role, and org sharing won't work.
- Shares to the org, an OU or an org account are **accepted automatically, with no invitation**.
- Shares to **external accounts** need an **invitation** that the recipient accepts:
  - 12 hours for most resource types.
  - 7 days for some, including subnets, TGWs, prefix lists, Resolver forwarding rules, License Manager configurations, capacity reservations, dedicated hosts and Aurora clusters.
- **Membership is dynamic.** New accounts in a shared OU get access automatically. Accounts that leave the org lose access, unless the share was created with `RetainSharingOnAccountLeaveOrganization` (account-to-account shares only).
- Some resource types can be shared **only within the organization**, e.g., **VPC subnets**, Outposts and Cloud Map namespaces.
- **Managed permissions** define what consumers can do. Choose AWS-managed permissions, or **customer managed permissions** for supported types (e.g., read-only on an IPAM pool).
- Prevent external sharing org-wide with an SCP on `ram:RequestedAllowsExternalPrincipals`, or by choosing "Allow sharing only within your organization" on each share.
- Global resources (e.g., Cloud WAN core networks) are shared and viewed from `us-east-1`.

**Resource types you must know for SAP-C02**

| Service | Shareable resource | Typical exam use |
|---|---|---|
| **Amazon VPC** | **Subnets** (VPC sharing), **transit gateways**, **prefix lists**, **IPAM pools**, **security groups** (to participants of a shared VPC), TGW multicast domains, traffic mirror targets, Verified Access groups, customer-owned IP pools | Central network account owns TGW and shared VPCs; workload accounts attach or launch into them. IPAM pools enforce CIDR allocation. |
| **Route 53 Resolver** | **Resolver forwarding rules**, query logging configurations, **DNS Firewall rule groups**, **Route 53 Profiles** | Hybrid DNS: create outbound endpoint + forwarding rules once in the Network account, share them org-wide, and associate them with every VPC. |
| **AWS Network Firewall** | Firewall policies, rule groups, firewalls | Central rule management |
| **AWS Cloud WAN** | Core network | Multi-account global WAN |
| **EC2** | **Capacity reservations** (ODCRs), **dedicated hosts**, placement groups | Share reserved capacity or BYOL dedicated hosts |
| **AWS License Manager** | **License configurations** | Enforce BYOL license limits across accounts |
| **Aurora** | DB clusters | Cross-account **clone** |
| **AWS Glue / Lake Formation** | Catalogs, databases, tables (Lake Formation uses RAM under the hood) | Cross-account data mesh |
| **AWS Private CA** | Private CAs | Central PKI issuing certs in all accounts |
| **AWS Backup** | **Logically air-gapped vaults** | Cyber-resilient recovery from a separate account |
| **Systems Manager** | Documents, Parameter Store advanced parameters; Incident Manager contacts and response plans | Shared runbooks and config |
| **VPC Lattice** | Service networks, services, resource configurations | Cross-account service-to-service connectivity |
| **EC2 Image Builder** | Images, recipes, components | Golden AMI pipeline outputs |
| **Others** | Outposts, Resource Groups, CodeBuild projects, App Mesh, EventBridge custom event bus, Marketplace entities, CloudFront VPC origins, Bedrock custom models, Billing views | Recognize them |

#### VPC sharing — owner vs participant (high-yield)

VPC sharing lets multiple accounts **launch resources into the same VPC subnets**. Accounts stay separate for billing and IAM while the network is centralized. Rules:
- Owner and participants must be in the **same organization**, with RAM org sharing enabled.
- **Subnets of the default VPC can't be shared.**
- Use **AZ IDs** (e.g., `use1-az1`), not AZ names, because names map differently per account.

| Responsibility | **VPC owner** (e.g., Network account) | **Participant** (workload account) |
|---|---|---|
| VPC, subnets, route tables, NACLs, IGW, NAT GW, VGW, TGW attachments, endpoints, Resolver endpoints, peering | **Creates and manages** | Can **describe** most of them, **can't modify** them. Can't create or describe NAT gateways. |
| Security groups | Owns the default SG. **Can describe** participant SGs but can't modify them. Can **share SGs** with participants. | **Creates and manages its own SGs.** Can reference other accounts' SGs as `account-id/sg-id`. **Can't use the owner's default SG.** |
| ENIs and instances | Can describe participant ENIs but can't modify them | Owns its own EC2, RDS, Lambda ENIs and so on. **Can't see or modify other participants' resources.** |
| Flow logs | Subnet- and VPC-level flow logs, plus logs for ENIs it doesn't own | Flow logs only for **its own ENIs** |
| Quotas | VPC-level quotas | Resources count toward **the participant's** quotas |
| Tags | VPC and subnet tags are **not visible** to participants | — |

| Billing | Who pays |
|---|---|
| EC2, RDS, Lambda and other application resources | **Participant** |
| Inter-AZ data transfer, peering, IGW egress, DX gateway data transfer | **Participant** |
| **NAT gateway, VGW, TGW, PrivateLink / VPC endpoint** hourly and processing charges | **Owner** |
| Public IPv4 addresses in shared VPCs | **Owner** |
| Same-AZ (same AZ ID) traffic | Free, regardless of account |

> When to choose VPC sharing over a VPC per account + TGW:
> - Workloads are in the **same trust boundary** and need dense intra-VPC connectivity.
> - You want **fewer VPCs and IPs to manage** and no TGW per-GB processing for intra-VPC traffic.
> - Central network control matters (participants can't open IGWs).
>
> Don't share across Prod and Non-Prod. More in [Chapter 04](04-Networking-VPC-and-Hybrid-Connectivity.md).

### 2.10 CloudFormation StackSets with service-managed permissions

StackSets deploy one CloudFormation template to **many accounts and Regions**. There are two permission models:

| | **Self-managed** | **Service-managed** |
|---|---|---|
| Roles | You create `AWSCloudFormationStackSetAdministrationRole` (admin account) and `AWSCloudFormationStackSetExecutionRole` (each target) | StackSets creates the SLRs via **trusted access with Organizations** |
| Targets | Account IDs | **OUs or the entire org** (plus optional account filters) |
| **Automatic deployment** | No | **Yes.** New accounts added to, or moved into, a target OU get the stack automatically. Accounts removed get stacks **deleted or retained** (`RetainStacksOnAccountRemoval`). Moving between target OUs deletes the old stack set's stack and creates the new one. |
| Who administers | Any account | **Management account** or up to **5 delegated administrator** member accounts |
| Works outside the org? | Yes | No |
| Management account as target | Yes | **No.** Service-managed StackSets don't deploy to the management account. |

More facts:
- Auto-deployment is set at the stack set level and **ignores account-level filters** for future accounts.
- Parameter overrides apply only to *current* accounts.
- StackSet dependencies: up to 10 per StackSet.
- Enable **managed execution** for concurrency.

Typical exam answer: "Deploy an IAM role, Config rule, GuardDuty setting or VPC flow-log configuration to every current **and future** account in the Workloads OU with minimal effort" → **service-managed StackSet targeting the OU with automatic deployment enabled**.

### 2.11 AWS Config at organization scale

- **Aggregators** collect configuration and compliance data from multiple accounts and Regions into one **aggregator account** (Audit or Security Tooling). An **organization aggregator** created in the management account or a **Config delegated admin** automatically includes all accounts, current and future, without per-account authorization. Aggregators are **read-only views**: they don't deploy rules, and member accounts still need recorders.
- **Organization Config rules** and **organization conformance packs** are deployed from the management account or delegated admin to all accounts (with exclusions). Member accounts **can't modify or delete** them. Conformance packs bundle rules and remediation actions as YAML, e.g., "Operational Best Practices for PCI DSS".
- Remediation runs through **SSM Automation** documents, auto or manual.
- Use **Config advanced queries** (SQL) across the aggregator for inventory, e.g., "all unencrypted EBS volumes in the org".
- Control Tower deploys recorders and an aggregator for you. Don't create conflicting recorders in enrolled accounts.

### 2.12 Centralized logging

```text
 Member accounts (all Regions)                Log Archive account (Security OU)
 ┌────────────────────────┐                   ┌──────────────────────────────────────┐
 │ Org CloudTrail trail   │──── S3 PUT ──────▶│ s3://org-cloudtrail-<id>/AWSLogs/     │
 │ (copy; read-only)      │                   │    o-orgid/<account-id>/...          │
 │ Config delivery channel│──── S3 PUT ──────▶│ s3://org-config-<id>/                │
 │ VPC Flow Logs / R53 QL │──── S3/Firehose ─▶│ Object Lock (compliance), versioning │
 └────────────────────────┘                   │ SSE-KMS (key policy: CT/Config svc)  │
                                              │ Bucket policy: deny delete, deny     │
 Security Tooling account ◀── read via role ──│ non-TLS, aws:SourceOrgID check       │
 (Athena / Security Lake / SIEM)              └──────────────────────────────────────┘
```

**Organization trail facts:**
- Created by the **management account or a CloudTrail delegated admin**.
- Logs **management and member accounts**.
- Member accounts see a read-only copy. They **can't stop, delete or modify** it, even as admins.
- New accounts are added automatically. Removed accounts' historical logs stay in the bucket.
- The S3 prefix includes the **org ID** and **account ID**.
- A console-created org trail is **multi-Region** by default.
- Data events for member resources can be logged without cross-account setup.
- **Event history** in each account shows only that account's last 90 days of management events.

**Hardening:**
- **S3 Object Lock** (compliance mode) or a **deny-delete bucket policy**, plus versioning.
- MFA delete is optional.
- SSE-KMS with a key in Log Archive.
- **CloudTrail log file integrity validation** (digest files).
- An SCP denying `cloudtrail:StopLogging`, `DeleteTrail` and `UpdateTrail` for anything not covered by the org trail.
- Restricted read access through roles from Security Tooling.
- Lifecycle to S3 Glacier tiers.

**Analysis options:**
- **CloudTrail Lake**: an org event data store with SQL queries and long retention.
- **Amazon Security Lake**: OCSF normalization across org accounts and Regions, with a delegated admin.
- Athena over the S3 bucket.
- Centralized CloudWatch Logs through cross-account subscriptions or **CloudWatch cross-account observability** (monitoring account / source accounts linked by org or OU).
- Detail in [Chapter 06](06-Security-Data-Protection-and-Threat-Detection.md) and [Chapter 15](15-Monitoring-Operations-and-Continuous-Improvement.md).

### 2.13 IAM Identity Center at organization level (brief)

- IAM Identity Center (successor to AWS SSO) is the **recommended workforce access** method for multi-account organizations.
- It connects to an external IdP (Entra ID, Okta, Google Workspace) via **SAML 2.0 + SCIM**, or to AD via AWS Managed Microsoft AD or AD Connector.
- **Permission sets** are provisioned as IAM roles (`AWSReservedSSO_...`) into the accounts you assign. Those roles **are subject to SCPs**.
- An **organization instance** lives in the management account. Best practice is a **delegated administrator** (e.g., a Shared Services or Identity account) for day-to-day administration. Permission sets that target the management account can only be managed from the management account.
- **Account instances** exist for isolated, app-specific use. They're not for multi-account workforce access.
- Supports **ABAC** through attributes for access control.
- An organization instance has one **primary Region**. Since early 2026, organization instances can be **replicated to additional Regions** for account access during a Regional outage. This needs a multi-Region customer managed KMS key, and assignments are still managed in the primary Region. It's newer than SAP-C02 content.
- Full coverage in [Chapter 03](03-Identity-and-Access-Management.md).

### 2.14 Billing governance (Task 1.5)

| Capability | What it does | Exam-relevant facts |
|---|---|---|
| **Consolidated billing** | One payer (management account), one invoice | **Volume pricing tiers aggregate** across accounts (S3 GB, data transfer). No extra cost. Each account still sees its own charges. |
| **RI / Savings Plans sharing** | Unused RI and SP discounts float to other accounts in the org | Benefit applies **to the purchasing account first**, then to others. The management account can **turn sharing off per account**. Both the purchaser and the receiver must have sharing on. **Group sharing** (2025): *Prioritized* (group first, then org) or *Restricted* (only within the group), with groups defined by **Cost Categories** (accounts dimension). The month's final bill uses the preference in effect at 23:59:59 UTC on the last day. Classic exam answer: "BU must keep its own RI benefit" → **disable RI/SP sharing for that account**, or use restricted group sharing. |
| **Cost allocation tags** | User-defined tags (and AWS-generated ones like `aws:createdBy`) appear as columns in billing reports **after activation** in the management account | Not retroactive (backfill of up to 12 months can be requested). Combine with tag policies and SCP tag enforcement. |
| **Cost Categories** | Rules that map costs (by account, tag, service, charge type and more) into business groupings, e.g., "BU = Retail", with split charges for shared costs | Show up in Cost Explorer, Budgets and CUR. Back RI/SP group sharing. |
| **AWS Billing Conductor** | **Pro forma** billing. Billing groups get **custom pricing rules** (markups, discounts, credits) and custom line items. | Doesn't change the real AWS invoice. For **showback/chargeback at negotiated internal rates**, resellers and MSPs. |
| **AWS Budgets** | Cost, usage, RI/SP coverage and utilization budgets with alerts. **Budget actions** can apply an **SCP** or IAM policy, or stop EC2/RDS, when a threshold is hit. | Per-account or org-wide (from the management account, filtered by linked account). Common for **sandbox spend control**. |
| **Cost Anomaly Detection, Cost Explorer, CUR 2.0 / Data Exports, Billing views** | Org-wide analysis. **Billing views** (shareable via RAM) give BU owners scoped cost data without management account access. | Deep dive in [Chapter 16](16-Cost-Optimization-and-FinOps.md) |
| **Billing transfer** (2025) | Lets an organization transfer billing responsibility to another org's management account (e.g., a partner or a parent company's payer) | New. Recognize the term only. |

### 2.15 Account vending, sandbox guardrails and account lifecycle

**Account vending pipeline (typical Professional design):**
1. A request arrives (ServiceNow, a Git pull request to the AFT repo, or a Service Catalog product).
2. Approval, then **Account Factory / AFT** creates the account in the right OU. OU membership gives it SCPs, RCPs, declarative policies and CT controls.
3. The baseline is applied automatically by CT baselines, **service-managed StackSets with auto-deployment**, CfCT or AFT customizations. A typical baseline:
   - IAM roles
   - Delete default VPCs
   - Attach the VPC to the TGW, or share subnets via RAM
   - Associate Resolver rules
   - Enable GuardDuty, Security Hub and Inspector (auto-enabled by delegated admins)
   - Budgets
   - Tagging
4. Identity Center assignments are made for the owning team.
5. The account is registered in a CMDB, and cost allocation tags or Cost Categories are applied.

**Sandbox guardrails:**
- Separate **Sandbox OU** with **no connectivity to the corporate network**: no TGW attachment, or an SCP denying `ec2:CreateTransitGatewayVpcAttachment` and VPN/DX actions.
- SCPs restricting Regions and expensive services or instance types. Deny marketplace subscriptions and RI/SP purchases (`ec2:PurchaseReservedInstancesOffering`, `savingsplans:CreateSavingsPlan`).
- **AWS Budgets with budget actions**: apply a deny SCP at 100% of budget, or alert at 80%.
- Time-boxed leases with automated cleanup: **Innovation Sandbox on AWS** solution, or aws-nuke-style cleanup and account recycling.
- No production data. RCPs and data perimeter keep sandbox principals away from prod resources.

**Account decommissioning:**
1. Move the account to the **Suspended OU** (deny-all SCP).
2. Back up anything required (snapshots, logs are already in Log Archive).
3. Unmanage it from Control Tower.
4. Remove its delegated-admin roles.
5. **Close** it from the management account (90-day post-closure, reopenable), or remove it from the org.
6. Watch the **closure quota**. Closed accounts count against the account quota until permanently closed. Update the root email first if you want to reuse the address.

**Multi-account networking.** The Network account owns TGW, Cloud WAN, DX, inspection VPCs and IPAM. It shares through RAM and attaches workload VPCs, often automated by tag-based attachment workflows. Full coverage in [Chapter 04](04-Networking-VPC-and-Hybrid-Connectivity.md).

**Delegated security services pattern.** The Security Tooling account is delegated admin for GuardDuty, Security Hub CSPM, Inspector, Macie, Detective, IAM Access Analyzer (org analyzer), Firewall Manager and Config. Each is set to **auto-enable for new org accounts**. Details in [Chapter 06](06-Security-Data-Protection-and-Threat-Detection.md).

---

## 3. Architecture patterns

### Pattern A — Reference multi-account landing zone (Control Tower + whitepaper OUs)

```text
                                  ┌──────────────────────────────┐
                                  │  Management account          │  Org, billing, CT, Identity Center (org instance)
                                  │  (no workloads)              │  Delegates everything else ↓
                                  └──────────────┬───────────────┘
                                                 │ Root  (SCP: FullAWSAccess, Deny-LeaveOrg, Deny-Root-Actions)
     ┌───────────────┬──────────────────┬────────┴─────────┬──────────────────┬───────────────┬──────────────┐
     ▼               ▼                  ▼                  ▼                  ▼               ▼              ▼
 Security OU    Infrastructure OU   Workloads OU        Sandbox OU      Policy Staging OU  Suspended OU  Exceptions OU
 ├ Log Archive  ├ Network           ├ Prod OU           (Budgets +      (test SCP/RCP)     (Deny *:*)    (audited)
 └ Audit /      │  (TGW, DX, IPAM,  │  ├ app1-prod       Region/service
   Security     │   Resolver, NFW)  │  └ app2-prod       SCPs; no TGW)
   Tooling      └ Shared Services   └ Non-Prod OU
   (delegated     (CI, AD, AMIs)       ├ app1-dev/test
   admin: GD,                          └ app2-dev/test
   SecHub, Config,
   Macie, Inspector)
```

- **When to use it:** almost always. It's the default answer for "design a multi-account environment".
- **Trade-offs:** Control Tower adds opinionated baselines and some constraints, such as Config recorder ownership and drift handling. Very large or unusual orgs sometimes use plain Organizations with their own IaC (LZA, or custom StackSets and Terraform).

### Pattern B — Hub-and-spoke shared networking via RAM

```text
   Network account (Infrastructure OU)                         Workload accounts
   ┌──────────────────────────────────────────┐                ┌──────────────────────┐
   │ Transit Gateway ──── RAM share (org) ────┼──────────────▶ │ VPC attachment        │
   │ Route 53 Resolver outbound endpoint      │                │ (accepted auto in org)│
   │ Resolver forwarding rules ── RAM share ──┼──────────────▶ │ Associate rules w/VPC │
   │ IPAM pools ─────────────── RAM share ────┼──────────────▶ │ Allocate CIDR from    │
   │ Shared VPC (Prod) subnets ─ RAM share ───┼──────────────▶ │ pool / launch into    │
   │ Direct Connect GW, Inspection VPC + NFW  │                │ shared subnets        │
   └──────────────────────────────────────────┘                └──────────────────────┘
```

- **Use it** for central control of connectivity, DNS and IP space. Accounts in the org get the shares **without invitations**.
- **Trade-offs:** the Network account becomes critical infrastructure. By default, TGW attachment-hour charges go to the TGW owner and data processing goes to the sending attachment's owner. **Flexible Cost Allocation** (November 2025) lets the TGW owner choose who is metered for data processing; see [Chapter 04](04-Networking-VPC-and-Hybrid-Connectivity.md). VPC sharing reduces TGW processing charges but puts several accounts in one trust zone.

### Pattern C — Layered preventive guardrails (defense in depth)

```text
  Request ──▶ [SCP: is MY principal allowed? region? resource in my org?]       (member principals)
          ──▶ [RCP: may THIS principal touch MY resource? org-only? TLS?]       (member resources)
          ──▶ [Permissions boundary] ──▶ [Identity policy] ──▶ [Resource policy]
          ──▶ [VPC endpoint policy: only my principals / my resources via my network]
  Config  ──▶ [Declarative policy: service configuration enforced in control plane — block public AMIs, VPC BPA]
  Deploy  ──▶ [Proactive control: CloudFormation Hook rejects non-compliant template]
  Runtime ──▶ [Detective: Config rules / Security Hub → EventBridge → SSM Automation remediation]
```

- **Use it** when the stem asks for "prevent" **and** "detect and remediate", or for "multiple layers".
- **Trade-offs:** policy-size quotas, the risk of locking yourself out, and testing effort. Mitigate with a Policy Staging OU and break-glass role exceptions.

### Pattern D — Automated account vending with AFT (GitOps)

```text
 Developer PR ──▶ account-request repo (Terraform module: email, OU, tags, SSO user)
                      │ merge
                      ▼
 AFT management account: CodePipeline → Step Functions → Account Factory (Service Catalog in CT mgmt acct)
                      │ account created in target OU (inherits SCP/RCP/CT controls)
                      ▼
 Global customizations (all accounts) → Account customizations (per type) → feature options
 (delete default VPCs, CloudTrail data events, Enterprise Support enrollment)
```

- **Use it** when the customer standardizes on Terraform, wants auditable request history, or vends at scale.
- **Alternatives:** use CfCT for CloudFormation shops. Use service-managed StackSets plus Account Factory for the lightest-weight setup.

### Pattern E — Organization-wide data perimeter

```text
  SCP  (all member principals): Deny s3:*,... if aws:ResourceOrgID != o-xxx  (except AWS-owned resource actions)
                                Deny * if aws:SourceIp/aws:SourceVpc not corporate/VPC  (except aws:ViaAWSService)
  RCP  (all member resources):  Deny if aws:PrincipalOrgID != o-xxx AND NOT aws:PrincipalIsAWSService
                                Deny service principals if aws:SourceOrgID != o-xxx
  VPCE policies:                Allow only aws:PrincipalOrgID = o-xxx AND aws:ResourceOrgID = o-xxx (+ AWS repos)
  SCP:                          Deny ram shares with external principals, deny AMI/snapshot public sharing
```

- **Use it** in regulated environments and for "prevent data exfiltration" or "prevent access from outside the organization".
- **Trade-offs:** exceptions for third-party integrations (vendors' accounts, SaaS) need **tags or account allowlists**, plus ongoing tuning with CloudTrail and IAM Access Analyzer.

### Pattern F — Centralized security and logging with delegated administrators

```text
 Management account ──registers──▶ Security Tooling (delegated admin: GuardDuty, Security Hub,
                                   Inspector, Macie, Detective, Config aggregator, Access Analyzer,
                                   Firewall Manager*, CloudTrail Lake)   *FMS admin
                      ──org trail──▶ Log Archive (Object Lock, KMS, deny-delete)
 Every new account ──auto-enable──▶ findings flow to Security Tooling → EventBridge → SOAR / tickets
```

- **Use it** for "minimize use of the management account", "security team must see all findings", and "automatically cover new accounts".

### Pattern G — M&A / org consolidation

```text
 Acquired org (Org B) accounts ──▶ [prepare: deregister delegated admins, inventory RAM shares,
                                    plan SCP impact, add standalone billing info if classic path]
                                ──▶ invite from Org A (direct transfer, or leave-then-join)
                                ──▶ land in **Transitional OU** (lighter SCPs, extra monitoring)
                                ──▶ enroll in Control Tower / remediate → move to Workloads OU
 Org B management account: becomes a member only after Org B is deleted.
```

---

## 4. Decision tables / "X vs Y"

### Guardrail type selection

| Requirement | Best tool | Not this |
|---|---|---|
| Stop *our* principals (including member root users) from doing X in member accounts | **SCP** | IAM policy in every account; permissions boundary |
| Stop *anyone, including external principals*, from accessing our resources unless conditions hold | **RCP** (supported services) | SCP (doesn't affect external principals) |
| Enforce a service *configuration* that survives new APIs (block public AMIs/snapshots, VPC BPA, IMDSv2 default, allowed AMIs) | **Declarative policy (EC2)** | SCP chasing every new API |
| Reject non-compliant resources **before** CloudFormation deploys them | **Proactive control / CloudFormation Hook** | Detective Config rule (after the fact) |
| Find and auto-fix non-compliant resources | **Config rule + SSM Automation remediation**, conformance packs | SCP (can't remediate) |
| Standardize tag keys and values | **Tag policy** | SCP alone (can't normalize case) |
| *Require* a tag on creation | **SCP** with `aws:RequestTag` + `Null`, or proactive control | Tag policy alone |
| Standard backup plans everywhere | **Backup policy** | Per-account backup plans |
| Opt out of AI service data use org-wide | **AI services opt-out policy** | Support case per account |

### SCP vs RCP vs permissions boundary vs IAM policy

| | SCP | RCP | Permissions boundary | Identity policy |
|---|---|---|---|---|
| Scope | Member accounts' principals | Member accounts' resources | One IAM user or role | One IAM principal |
| Grants permission? | No | No | No | **Yes** |
| Managed by | Org admins | Org admins | Account admins (delegation) | Account admins |
| Typical use | Org-wide guardrails | Org-wide resource perimeter | Let devs create roles safely | Day-to-day permissions |
| Affects management account | No | No | Yes (if attached) | Yes |

### Control Tower vs plain Organizations vs LZA

| Criteria | **Control Tower** | **Organizations + custom IaC** | **Landing Zone Accelerator** |
|---|---|---|---|
| Setup effort | Lowest | Highest | Medium (config-driven) |
| Ongoing governance (drift, controls dashboard) | Built in | Build it yourself | Built on CT, plus pipeline |
| Flexibility | Opinionated | Total | High, compliance-oriented |
| Best for | "Least operational overhead", new environments | Unusual constraints, existing mature tooling | Regulated workloads needing a broad baseline |

### Account vending/customization tools

| Need | Pick |
|---|---|
| Few accounts, console clicks OK | **Account Factory** |
| Terraform, GitOps, per-account customization at scale | **AFT** |
| CloudFormation + custom SCPs/RCPs applied on lifecycle events | **CfCT** |
| Simple blueprint per account type at vend time | **Account Factory Customization (AFC)** |
| Deploy a template to every current and future account in an OU (with or without CT) | **Service-managed StackSet + auto-deployment** |

### Sharing / connectivity mechanisms

| Need | Pick | Why not the others |
|---|---|---|
| Many accounts use one central network; same trust zone; minimize VPC count | **VPC sharing (RAM subnets)** | TGW per VPC adds cost and complexity |
| Many VPCs need transitive routing with isolation via route tables | **TGW shared via RAM** | VPC peering isn't transitive and doesn't scale (n² links) |
| One service exposed to many consumer accounts, overlapping CIDRs | **PrivateLink / VPC Lattice** | TGW needs non-overlapping CIDRs |
| On-prem DNS resolution from all VPCs | **Resolver rules shared via RAM** | An outbound endpoint per VPC is costly |
| BYOL license enforcement org-wide | **License Manager configs via RAM** | Spreadsheets |

### RI/SP sharing options

| Requirement | Configuration |
|---|---|
| Maximize total org savings | Org-wide sharing on (default) |
| BU A's commitments must benefit only BU A | **Disable sharing for BU A's accounts**, or **Restricted group sharing** with a Cost Category group for BU A |
| BU A first, leftovers to the rest of the org | **Prioritized group sharing** |
| Chargeback at internal rates different from AWS prices | **Billing Conductor** pricing plans |

---

## 5. Exam keyword → answer cheat list

| Stem keyword / phrase | Likely answer |
|---|---|
| "Least operational overhead to set up governed multi-account environment" | **AWS Control Tower** landing zone |
| "New accounts must automatically receive baseline / roles / config" | Control Tower Account Factory + **service-managed StackSets with auto-deployment**, CfCT, or AFT |
| "Terraform" + account vending | **AFT** |
| "Prevent any user, including administrators and root, in member accounts" | **SCP** |
| "Prevent the management account from…" | Not possible with SCPs. **Don't use the management account**; delegate. |
| "Restrict to approved Regions" | SCP `aws:RequestedRegion` with **NotAction for global services** + `aws:PrincipalArn` exceptions, or the **CT Region deny** control |
| "Only principals from our organization can access the bucket/key" | **RCP** (org-wide) or bucket/key policy with **`aws:PrincipalOrgID`** |
| "Prevent copying data to buckets outside the company" | SCP / VPC endpoint policy with **`aws:ResourceOrgID`** |
| "Only via our VPC endpoint" | `aws:SourceVpce` in a resource policy or RCP |
| "Block public AMI/snapshot sharing org-wide, even for future APIs" | **Declarative policy (EC2)** |
| "Prevent accounts leaving the organization" | SCP deny `organizations:LeaveOrganization` |
| "Security team must manage GuardDuty/Security Hub; minimize management account use" | **Delegated administrator** in a Security Tooling account + auto-enable |
| "Centralize and protect CloudTrail logs for all accounts" | **Organization trail** → Log Archive S3 with **Object Lock**, KMS, deny-delete policy |
| "Org-wide compliance view" | **Config organization aggregator** in the delegated admin account; **org conformance packs** |
| "Share TGW / subnets / Resolver rules without invitations" | **RAM with sharing enabled for Organizations** |
| "Participants must not modify routing" | **VPC sharing**: only the owner manages route tables, NACLs and gateways |
| "Standardize tag case and values" | **Tag policy** (enforce for resource types) |
| "Resources must be tagged at creation" | **SCP** `Null`/`aws:RequestTag`, or proactive control |
| "Business unit must keep RI discount" | **Disable RI/SP sharing** for that account, or restricted group sharing |
| "Showback with custom rates / markup" | **Billing Conductor** |
| "Group costs by BU across accounts and tags" | **Cost Categories** |
| "Stop sandbox spend at threshold automatically" | **AWS Budgets action** applying an SCP or stopping instances |
| "Test SCP before org-wide rollout" | **Policy Staging OU** |
| "Quarantine a compromised account" | Move to **Suspended OU** with deny-all SCP |
| "Existing accounts with their own Config recorders must join Control Tower" | Remove the existing recorder/delivery channel, deploy `AWSControlTowerExecution`, then **enroll** / register the OU |
| "Account moved via Organizations console now shows drift" | Re-register the OU / update the account in Control Tower; move accounts through CT |

---

## 6. Traps & distractors

1. **"Attach an SCP to the management account / root to restrict the management account."** SCPs never affect the management account.
2. **"Use an SCP to grant S3 access to the analytics team."** SCPs never grant. An `Allow` SCP only permits identity policies to grant.
3. **"Use an SCP to block an external partner's access to our bucket."** SCPs don't affect principals outside the org. Use an **RCP** or the bucket policy.
4. **Region-deny SCP without global-service exceptions.** It breaks IAM, Organizations, Route 53, CloudFront, Support and STS. The right answer has `NotAction` or exemptions.
5. **Allow-list SCP attached at only one OU.** It must also be allowed at the root and at every OU in the path. `FullAWSAccess` removed at an intermediate OU blocks everything not explicitly allowed there.
6. **"Service-linked role actions are blocked by our SCP."** They aren't. SCPs and RCPs don't restrict SLRs. Declarative policies *do* govern them.
7. **"Tag policy ensures every resource has a CostCenter tag."** Tag policies don't evaluate untagged resources and don't block creation without tags.
8. **"Enable trusted access for RAM from the Organizations console."** The RAM SLR isn't created. Enable sharing from **RAM**.
9. **"VPC participants can add a route to the NAT gateway / create an IGW."** Only the owner manages routing and gateways.
10. **"Share default VPC subnets"**, or "share subnets with an account in another org". Neither is allowed.
11. **"Service-managed StackSets will also deploy to the management account."** They don't. Deploy separately (e.g., a self-managed stack).
12. **"Remove the account from the organization to stop it being billed immediately after closure."** Close vs remove are different. Closed accounts stay in the org (counting toward quota) for 90 days.
13. **"Invite existing accounts and assume `OrganizationAccountAccessRole` exists."** It's only auto-created for accounts *created* by Organizations.
14. **"Use AWS Config to prevent the action."** Config is detective (with remediation after the fact). Prevention needs an SCP, RCP, declarative policy or proactive hook.
15. **"Create IAM users in each account for central admins."** Use IAM Identity Center permission sets or cross-account roles.
16. **"Use consolidated billing to restrict services."** Consolidated-billing-only orgs have no policies. Enable **all features**.
17. **"CloudTrail organization trail can be deleted by member account administrators."** It can't, which is why it's preferred over per-account trails.
18. **"Use RAM to share an S3 bucket / KMS key."** These use resource-based policies, not RAM. RAM shares *specific supported types*.
19. **"Disable RI sharing on the purchasing account to give everyone the discount."** That's backwards. Disabling sharing keeps benefits inside that account.
20. **"Enroll an existing account as the Log Archive account after setup."** Only possible during initial landing zone setup.

---

## 7. Professional architect focus

- **Design OUs for policy, not people.** Ask stakeholders: "Which accounts need *different guardrails*?" That question defines the OUs. Reporting lines belong in tags and Cost Categories.
- **Treat the management account like a domain controller.** Very few humans, no workloads, alarms on any sign-in, and everything delegated. Many real breaches turn into org-wide incidents because the management account was used for convenience.
- **Guardrail lifecycle is software delivery.** SCPs and RCPs live in Git, go through a pipeline, deploy to **Policy Staging** first, and have rollback. Keep a **break-glass role** exempted through `aws:PrincipalArn`, store its credentials offline, and alarm on its use.
- **Quotas and size limits drive design.** Consolidate statements and attach at the highest sensible OU. Prefer deny lists with `NotAction`. RCPs are limited to 5 per entity, including the mandatory `RCPFullAWSAccess`, so effectively 4 custom RCPs per entity.
- **Data perimeter rollout is iterative.** Run in "audit" mode first (CloudTrail + Access Analyzer + Athena on `aws:PrincipalOrgID` mismatches). Build exceptions for SaaS vendors and AWS service principals, *then* enforce. Communicate with app teams, because third-party integrations will break.
- **Control Tower trade-offs to raise.** You give up some freedom (Config recorder, CT roles, OU moves only through CT) in exchange for drift detection and a controls dashboard. Pin your landing zone version, test upgrades in a separate org or sandbox, and keep customizations in CfCT or AFT, never by hand.
- **VPC sharing vs account-level VPCs.** VPC sharing simplifies IP management and cuts TGW cost, but it creates a **shared fate**. NACL or route changes by the owner affect everyone, and it blurs per-account quotas. Use it within an environment and business domain, not across them.
- **Cost governance.** Push **account-level ownership** (every account has an owner, a cost center and a budget). Activate cost allocation tags early, because they aren't retroactive beyond the backfill window. Use Cost Categories for BU rollups. Decide RI/SP sharing policy explicitly with finance, because central purchasing with org-wide sharing maximizes savings but complicates chargeback.
- **Account lifecycle hygiene.** Automate decommissioning (Suspended OU → close). Track the closure quota. Reuse email aliases carefully: change the root email before closure if you want to reuse it. Remember closed accounts still count toward org quota for 90 days.
- **M&A.** Plan RAM share breakage, SCP shock (the acquired accounts suddenly face your guardrails), Identity Center reassignment, Savings Plans that won't follow the account's old payer, and delegated-admin deregistration. Use a **Transitional OU**.

---

## 8. Skills checklist

- [ ] I can draw the whitepaper OU structure (Security, Infrastructure, Workloads, Sandbox, Policy Staging, Suspended, Exceptions, Transitional, Deployments, Individual Business Users, Business Continuity) and place Log Archive, Audit/Security Tooling, Network and Shared Services accounts.
- [ ] I can explain why the management account is excluded from SCPs and RCPs and what to delegate away from it.
- [ ] I can evaluate an SCP hierarchy, deny-list vs allow-list, and predict whether an action succeeds.
- [ ] I can write a region-deny SCP with `NotAction` global-service exceptions and an `aws:PrincipalArn` break-glass exception.
- [ ] I can state current SCP and RCP limits (SCP 10 per entity, 10,240 characters; RCP 5 per entity, 5,120 characters), recognize the older SCP values (5 / 5,120), and name the things SCPs don't affect.
- [ ] I can explain RCPs, `RCPFullAWSAccess`, and when to use an RCP instead of an SCP.
- [ ] I can map identity, resource and network perimeters to SCP, RCP and VPC endpoint policies, with `aws:PrincipalOrgID`, `aws:ResourceOrgID`, `aws:SourceVpce`, `aws:PrincipalIsAWSService` and `aws:ViaAWSService`.
- [ ] I can explain declarative policies and how they differ from SCPs (configuration vs authorization, SLRs, management account).
- [ ] I know what tag, backup, AI opt-out and chat applications policies do, including the tag policy untagged-resources caveat.
- [ ] I can describe what Control Tower deploys, the three control behaviors and three guidance categories, and how drift arises and is repaired.
- [ ] I can choose between Account Factory, AFC, AFT, CfCT, LZA and service-managed StackSets.
- [ ] I can list the prerequisites for enrolling an existing account into Control Tower.
- [ ] I can list key RAM-shareable resources and explain sharing within the org without invitations.
- [ ] I can split VPC sharing responsibilities and billing between owner and participant.
- [ ] I can configure service-managed StackSets with auto-deployment and explain the account removal behavior.
- [ ] I can design org-wide Config aggregation and conformance packs, and an org CloudTrail trail to Log Archive with immutability.
- [ ] I can explain RI/SP sharing (including group sharing), cost allocation tags, Cost Categories, Billing Conductor and Budgets actions.
- [ ] I can describe an account vending pipeline, sandbox guardrails and the account closure lifecycle (90 days, quota).
- [ ] I can describe how to move an account between OUs and between organizations, and its consequences.

---

## 9. Practice questions

> Original SAP-C02-style questions written for this guide. Not real exam questions.

**Q1.** A global insurer runs 240 AWS accounts in AWS Organizations with all features enabled. Data residency rules require all workloads to run only in eu-west-1 and eu-central-1. The cloud platform team must keep using IAM, AWS Organizations, Amazon Route 53, Amazon CloudFront and AWS Support, and its `PlatformBreakGlass` role must work in any Region during incidents. The security team wants the control to apply to member account root users and to require the least ongoing maintenance. Which solution meets these requirements?

A. Create an IAM policy that denies all actions when `aws:RequestedRegion` isn't one of the two approved Regions, and deploy it to every IAM role in every account with a service-managed StackSet.
B. Attach an SCP to the organization root that denies all actions using `NotAction` for the required global services, with a `StringNotEquals` condition on `aws:RequestedRegion` for the two approved Regions and an `ArnNotLike` condition on `aws:PrincipalArn` that exempts the `PlatformBreakGlass` role.
C. Attach an SCP to the organization root that allows only actions where `aws:RequestedRegion` equals one of the two approved Regions, and remove the `FullAWSAccess` SCP from the root.
D. Use AWS Config rules in every Region to detect resources created outside the approved Regions, and invoke an AWS Lambda function to delete them.

**Q2.** A healthcare company stores PHI in Amazon S3 buckets and AWS KMS keys spread across 90 member accounts. An audit found that two buckets had bucket policies granting access to an external analytics vendor's account, which was never approved. The CISO wants an organization-wide preventive control that stops any principal outside the organization from accessing S3 objects or using KMS keys in member accounts, even if a resource-based policy allows it. AWS services such as CloudTrail must still be able to deliver logs to buckets on behalf of the organization. Which solution meets these requirements with the least operational overhead?

A. Attach an SCP to the root that denies `s3:*` and `kms:*` when `aws:PrincipalOrgID` doesn't equal the organization ID.
B. Attach a resource control policy to the root that denies `s3:*` and `kms:*` when `aws:PrincipalOrgID` doesn't equal the organization ID, unless `aws:PrincipalIsAWSService` is true, with an additional statement that requires `aws:SourceOrgID` to equal the organization ID for service principals.
C. Use IAM Access Analyzer in each account to detect external access and an EventBridge rule to invoke a Lambda function that removes offending bucket policy statements.
D. Create an AWS Config organization conformance pack with the `s3-bucket-policy-not-more-permissive` rule and automatic remediation through Systems Manager Automation.

**Q3.** A retailer is moving to a centralized network model. The network team owns a VPC in the Network account and shares private subnets with 30 application accounts in the same organization by using AWS RAM. Application teams will deploy Amazon EC2 instances and Amazon RDS databases into the shared subnets. Which statements are correct about this design? **(Select TWO.)**

A. Application accounts can create and manage their own security groups in the shared VPC and attach them to their own resources.
B. Application accounts can modify the route tables associated with the shared subnets to add routes to their own VPC endpoints.
C. The Network account pays the hourly and data processing charges for NAT gateways in the shared VPC, and the application accounts pay for their EC2 instances and RDS databases.
D. Application accounts can view and modify EC2 instances launched by other application accounts in the same shared subnets.
E. The network team can share the subnets of the default VPC as long as RAM sharing with AWS Organizations is enabled.

**Q4.** A fintech company is adopting AWS Control Tower. Its platform team manages all infrastructure with Terraform Cloud and requires that every new account request be submitted as a pull request, peer reviewed, and recorded in version control. After an account is created, a Terraform-defined baseline must be applied to all accounts, and additional Terraform modules must be applied only to accounts tagged as `data-platform`. The team wants to avoid building and maintaining a custom account-vending pipeline. What should a solutions architect recommend?

A. Use Customizations for AWS Control Tower (CfCT) with a manifest file that references Terraform modules stored in Amazon S3.
B. Deploy AWS Control Tower Account Factory for Terraform (AFT) in a dedicated AFT management account, store account requests in a Git repository, and use global customizations and account customizations for the baseline and data-platform modules.
C. Use the Control Tower Account Factory console to create accounts, and run Terraform from a CI server that polls the Organizations API for new accounts.
D. Create a service-managed CloudFormation StackSet with automatic deployment that invokes Terraform through a custom resource in each new account.

**Q5.** A conglomerate has three business units (BUs) under one AWS organization. BU-Retail bought a large number of Compute Savings Plans from its own member accounts. The CFO says that BU-Retail's commitments must first cover BU-Retail's accounts, and any unused commitment must be shared only with the other accounts of BU-Retail, never with BU-Media or BU-Energy. Other BUs' commitments should keep sharing across the organization. The finance team wants a native solution with no custom scripting. What should the solutions architect do?

A. Turn off RI and Savings Plans discount sharing for all accounts in the organization.
B. Create a Cost Category that groups BU-Retail's accounts, and configure RI and Savings Plans discount sharing with restricted group sharing for that group.
C. Move BU-Retail's accounts into a dedicated OU and attach an SCP that denies `savingsplans:*` to the other BUs' OUs.
D. Use AWS Billing Conductor to create a billing group for BU-Retail so that its Savings Plans apply only within the billing group.

**Q6.** A media company's security team operates from a Security Tooling account. Today, Amazon GuardDuty and AWS Security Hub are administered from the organization's management account, and several engineers have broad access to that account. The company wants to reduce use of the management account, ensure that every new account is automatically covered by both services, and keep the security team in control of findings across all accounts. Which actions should a solutions architect take? **(Select TWO.)**

A. Register the Security Tooling account as the delegated administrator for GuardDuty and Security Hub from the management account.
B. Configure the delegated administrator to auto-enable GuardDuty and Security Hub for all existing and new member accounts in the organization.
C. Attach an SCP to the management account that denies GuardDuty and Security Hub administrative actions.
D. Create IAM users for the security engineers in each member account so they can review findings locally.
E. Send an invitation from the Security Tooling account to each member account and accept it manually in every account.

**Q7.** A bank must retain AWS API activity for all current and future accounts in its organization for 7 years. Logs must be immutable: no one, including administrators of the log account or of the account that generated the events, may delete or alter them during the retention period. Administrators in member accounts must not be able to disable logging. Which combination of steps meets these requirements? **(Select THREE.)**

A. Create an AWS CloudTrail organization trail from the management account (or a CloudTrail delegated administrator) that delivers to an S3 bucket in a dedicated Log Archive account.
B. Enable S3 Object Lock in compliance mode with a 7-year default retention period on the Log Archive bucket.
C. Create an individual CloudTrail trail in each member account by using a self-managed StackSet.
D. Enable CloudTrail log file integrity validation on the organization trail.
E. Enable S3 Object Lock in governance mode, and grant the security team `s3:BypassGovernanceRetention`.
F. Configure S3 Lifecycle rules to transition logs to S3 Glacier Flexible Retrieval after 30 days and expire them after 7 years, without any other bucket protections.

**Q8.** A company uses AWS Organizations without AWS Control Tower. Every account in the Workloads OU and its child OUs needs an IAM role that a third-party monitoring vendor assumes, plus a VPC Flow Logs configuration. Accounts are frequently created or moved into the Workloads OU, and when an account moves out of the OU the role must be removed. The operations team wants no manual steps. What should a solutions architect do?

A. Create a self-managed CloudFormation StackSet that targets the account IDs in the Workloads OU, and update the target list weekly.
B. Create a service-managed CloudFormation StackSet that targets the Workloads OU with automatic deployment enabled and account removal behavior set to delete stacks.
C. Create an EventBridge rule in each account that detects new VPCs and invokes a Lambda function to create the role.
D. Attach an SCP to the Workloads OU that creates the IAM role in each account.

**Q9.** A SaaS company must ensure that every Amazon EC2 instance and Amazon EBS volume created in its workload accounts has a `CostCenter` tag. Values must be one of an approved list with consistent capitalization (for example, `CC-1001`, not `cc-1001`). Today, many resources are created without the tag, and others use inconsistent values. Which combination of actions meets these requirements? **(Select TWO.)**

A. Create a tag policy that defines the `CostCenter` key with the approved values and capitalization, and enforce it for `ec2:instance` and `ec2:volume`.
B. Rely on the tag policy alone, because enforced tag policies block creation of resources that don't include the `CostCenter` tag.
C. Attach an SCP that denies `ec2:RunInstances` and `ec2:CreateVolume` for the relevant resource ARNs when the `aws:RequestTag/CostCenter` key is null.
D. Activate `CostCenter` as a cost allocation tag, which automatically adds the tag to untagged resources.
E. Configure AWS Budgets to send an alert when untagged resources are created.

**Q10.** A company uses an allow-list SCP strategy. The root has an SCP that allows `ec2:*`, `s3:*`, `rds:*`, `lambda:*`, `iam:*` and `sts:*`. The Workloads OU has `FullAWSAccess` attached. A new child OU named Analytics was created under Workloads, and the platform team attached an SCP to Analytics that allows `athena:*`, `glue:*`, `s3:*`, `iam:*` and `sts:*`. The account `analytics-prod`, which has `FullAWSAccess` attached directly, is in the Analytics OU. An administrator in `analytics-prod` with the `AdministratorAccess` IAM policy reports that Athena queries fail with an access denied error that references a service control policy. What is the cause, and how should it be fixed?

A. `AdministratorAccess` doesn't include Athena permissions. Attach the `AmazonAthenaFullAccess` managed policy to the administrator.
B. SCP allows must exist at every level in the path. Athena and Glue are not allowed by the root SCP, so add `athena:*` and `glue:*` to the root SCP (or to an SCP on the root).
C. The `FullAWSAccess` policy attached to the account overrides parent SCPs. Detach it so the Analytics OU SCP takes effect.
D. The Analytics OU SCP must be attached directly to the `analytics-prod` account because SCPs on OUs are not inherited.

---

### Answers & explanations

<details><summary>Show answer — Q1</summary>

**Correct: B.**
- **Why it's right:** A deny-list SCP at the root covers every member account, including root users, with one policy to maintain. `NotAction` exempts global services whose control planes live in `us-east-1`. `aws:RequestedRegion` enforces the approved Regions. `ArnNotLike` on `aws:PrincipalArn` exempts the break-glass role. Conditions are ANDed, so the deny applies only to non-exempt principals outside the approved Regions.
- **A:** IAM policies don't apply to member account root users. They must be maintained on every role, and account admins can remove them.
- **C:** An allow-list SCP with a Region condition would block global services, and it doesn't exempt the break-glass role. Removing `FullAWSAccess` from the root also requires allow statements at every level. It's high maintenance and risky.
- **D:** Detective and reactive only. It doesn't prevent creation, and deleting production resources automatically is dangerous.
- **Reference:** [SCP examples — deny access based on Region](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_policies_scps_examples_general.html), [SCP syntax](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_policies_scps_syntax.html)
</details>

<details><summary>Show answer — Q2</summary>

**Correct: B.**
- **Why it's right:** RCPs restrict access to *resources* in member accounts no matter who the principal is, including principals outside the organization, and they override overly permissive resource policies. S3 and KMS were among the first RCP-supported services. `aws:PrincipalIsAWSService` exempts service principals such as `cloudtrail.amazonaws.com`. `aws:SourceOrgID` ensures services act only on behalf of your org, which prevents the confused deputy problem. This is one policy at the root.
- **A:** SCPs apply only to principals *in* the organization. They can't restrict an external vendor's principals.
- **C:** Detective and reactive, with a window of exposure. It also needs per-account setup and custom code.
- **D:** Detective. Automatic remediation runs after exposure and depends on rule coverage. It's not a preventive guarantee.
- **Reference:** [Resource control policies](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_policies_rcps.html), [Data perimeter — perimeter implementation](https://docs.aws.amazon.com/whitepapers/latest/building-a-data-perimeter-on-aws/perimeter-implementation.html)
</details>

<details><summary>Show answer — Q3</summary>

**Correct: A, C.**
- **A:** Participants can create, modify and delete security groups they own in a shared VPC and use them with their own ENIs and instances.
- **C:** The VPC owner pays NAT gateway, VGW, TGW, PrivateLink and VPC endpoint hourly and processing charges, plus public IPv4 addresses. Participants pay for their application resources and for some data transfer, such as inter-AZ traffic.
- **B:** Only the owner can create, modify or associate route tables. Participants can only describe them.
- **D:** Participants can't view, modify or delete resources belonging to other participants or to the owner.
- **E:** Subnets in a default VPC can't be shared.
- **Reference:** [Responsibilities and permissions for owners and participants](https://docs.aws.amazon.com/vpc/latest/userguide/vpc-share-limitations.html), [Billing for owners and participants](https://docs.aws.amazon.com/vpc/latest/userguide/vpc-share-billing.html)
</details>

<details><summary>Show answer — Q4</summary>

**Correct: B.**
- **Why it's right:** AFT is the AWS-provided GitOps account-vending framework for Control Tower and supports Terraform OSS, Terraform Cloud and Terraform Enterprise. Account requests are Terraform files in a repo, so you get PR review and history. AFT provides **global customizations** for all accounts and **account customizations** selected per account request, and it runs in a dedicated AFT management account. No custom pipeline is needed.
- **A:** CfCT deploys CloudFormation templates and SCPs/RCPs, not Terraform modules, and it doesn't provide Git-based account requests.
- **C:** Console vending lacks PR-based requests. The polling CI server is a custom pipeline to build and maintain.
- **D:** StackSets deploy CloudFormation. Invoking Terraform through custom resources is fragile, custom, and doesn't handle account requests.
- **Reference:** [AWS Control Tower Account Factory for Terraform (AFT)](https://docs.aws.amazon.com/controltower/latest/userguide/aft-overview.html)
</details>

<details><summary>Show answer — Q5</summary>

**Correct: B.**
- **Why it's right:** RI and Savings Plans discount sharing supports **group sharing** with account groups defined by **Cost Categories** (accounts dimension). *Restricted group sharing* applies commitments to the owner account first, then only within the defined group, never outside it. Other accounts can keep organization-wide sharing. It's native and needs no scripts.
- **A:** Turning off sharing for everyone stops BU-Retail's commitments from covering its own other accounts. It also removes sharing benefits for the other BUs, which contradicts the requirement.
- **C:** SCPs control API permissions, not how billing discounts are applied. Denying `savingsplans:*` only stops purchases.
- **D:** Billing Conductor produces *pro forma* billing data for showback and chargeback. It doesn't change how discounts apply on the actual AWS bill.
- **Classic SAP-C02 variant:** if group sharing isn't offered, the expected answer is to *turn off sharing for BU-Retail's accounts*. That keeps each account's commitments with the purchasing account.
- **Reference:** [Reserved Instances and Savings Plans discount sharing](https://docs.aws.amazon.com/awsaccountbilling/latest/aboutv2/ri-turn-off.html)
</details>

<details><summary>Show answer — Q6</summary>

**Correct: A, B.**
- **A:** Registering a delegated administrator moves day-to-day administration of GuardDuty and Security Hub to the Security Tooling account. That reduces management account use, and the security team sees findings org-wide.
- **B:** With Organizations integration, the delegated admin can automatically enable the services for new accounts (and existing ones), so coverage stays complete with no manual steps.
- **C:** SCPs never affect the management account. It also wouldn't move administration anywhere.
- **D:** IAM users in every account are an anti-pattern (long-term credentials, sprawl) and don't centralize findings.
- **E:** Invitation-based administration is the legacy, manual model. It doesn't auto-cover new accounts and adds overhead.
- **Reference:** [Managing GuardDuty accounts with AWS Organizations](https://docs.aws.amazon.com/guardduty/latest/ug/guardduty_organizations.html), [Security Hub — integrating with AWS Organizations](https://docs.aws.amazon.com/securityhub/latest/userguide/designate-orgs-admin-account.html)
</details>

<details><summary>Show answer — Q7</summary>

**Correct: A, B, D.**
- **A:** An organization trail automatically covers the management account and all current and future member accounts. Member account administrators can't stop, delete or modify it, which meets "can't disable logging".
- **B:** Object Lock in **compliance mode** prevents any user, including the root user of the Log Archive account, from deleting or overwriting object versions until retention expires.
- **D:** Integrity validation produces signed digest files, so you can prove logs weren't altered. This supports the immutability and audit requirement.
- **C:** Per-account trails can be stopped or deleted by member admins (unless separately guarded). They also add cost and duplication.
- **E:** Governance mode lets users with `s3:BypassGovernanceRetention` delete objects, which violates "no one".
- **F:** Lifecycle alone gives no protection against deletion or modification.
- **Reference:** [Creating a trail for an organization](https://docs.aws.amazon.com/awscloudtrail/latest/userguide/creating-trail-organization.html), [S3 Object Lock](https://docs.aws.amazon.com/AmazonS3/latest/userguide/object-lock.html), [CloudTrail log file integrity validation](https://docs.aws.amazon.com/awscloudtrail/latest/userguide/cloudtrail-log-file-validation-intro.html)
</details>

<details><summary>Show answer — Q8</summary>

**Correct: B.**
- **Why it's right:** Service-managed StackSets target OUs, including their child OUs. With **automatic deployment**, CloudFormation deploys stacks to accounts added to or moved into the target OU. With **account removal behavior = delete stacks**, it removes them when accounts leave. It works without Control Tower and has no manual steps.
- **A:** Self-managed StackSets target account IDs and need execution roles in each account. Weekly manual updates violate "no manual steps".
- **C:** Per-account rules must themselves be deployed. This is custom code, and it doesn't handle removal when an account leaves the OU.
- **D:** SCPs can't create resources. They only limit permissions.
- **Reference:** [Enable or disable automatic deployments for StackSets](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/stacksets-orgs-manage-auto-deployment.html)
</details>

<details><summary>Show answer — Q9</summary>

**Correct: A, C.**
- **A:** A tag policy standardizes allowed values and capitalization for the `CostCenter` key. Enforcing it for `ec2:instance` and `ec2:volume` blocks non-compliant tagging operations on those types.
- **C:** Tag policies don't evaluate untagged resources and don't require tags. An SCP with a `Null` condition on `aws:RequestTag/CostCenter` denies creation calls that omit the tag. Together, A and C give "always present" plus "correct value".
- **B:** Wrong. Untagged resources aren't evaluated by tag policies, so creation without the tag isn't blocked.
- **D:** Activating a cost allocation tag only makes it appear in billing data. It doesn't tag resources.
- **E:** Budgets track spend and usage. They don't detect or enforce tagging.
- **Reference:** [Tag policies](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_policies_tag-policies.html), [SCP examples — require tags](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_policies_scps_examples_tagging.html)
</details>

<details><summary>Show answer — Q10</summary>

**Correct: B.**
- **Why it's right:** For an action to be available in an account, an SCP must allow it at **every** level of the path: root → Workloads → Analytics → account. The root allow-list doesn't include `athena:*` or `glue:*`, so they're implicitly denied at the root level. Allows on lower OUs can't widen that. Add the services to the root-level allow SCP. Console messages for an implicit SCP deny still identify a service control policy as the cause.
- **A:** `AdministratorAccess` grants `*:*`. The block comes from SCPs.
- **C:** SCPs don't override each other. Effective permissions are the intersection across levels, and detaching `FullAWSAccess` at the account would block even more.
- **D:** SCPs on OUs *do* apply to all accounts beneath them. The problem is the missing allow at the root.
- **Reference:** [SCP evaluation](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_policies_scps_evaluation.html)
</details>

---

## 10. References

- [Organizing Your AWS Environment Using Multiple Accounts (whitepaper)](https://docs.aws.amazon.com/whitepapers/latest/organizing-your-aws-environment/organizing-your-aws-environment.html) and [Recommended OUs and accounts](https://docs.aws.amazon.com/whitepapers/latest/organizing-your-aws-environment/recommended-ous-and-accounts.html)
- [AWS Organizations User Guide](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_introduction.html) · [Quotas](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_reference_limits.html) · [Best practices for the management account](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_best-practices_mgmt-acct.html)
- [Managing organization policies (policy types)](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_policies.html)
- [Service control policies](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_policies_scps.html) · [SCP evaluation](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_policies_scps_evaluation.html) · [SCP syntax](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_policies_scps_syntax.html) · [SCP examples](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_policies_scps_examples.html)
- [Resource control policies](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_policies_rcps.html)
- [Declarative policies](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_policies_declarative.html) · [Tag policies](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_policies_tag-policies.html) · [Backup policies](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_policies_backup.html) · [AI services opt-out policies](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_policies_ai-opt-out.html) · [Chat applications policies](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_policies_chatbot.html)
- [Removing a member account](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_accounts_remove.html) · [Migrating an account to another organization](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_account_migration.html) · [Closing an AWS account](https://docs.aws.amazon.com/accounts/latest/reference/manage-acct-closing.html)
- [Centrally manage root access for member accounts](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_root-user.html)
- [Building a Data Perimeter on AWS (whitepaper)](https://docs.aws.amazon.com/whitepapers/latest/building-a-data-perimeter-on-aws/building-a-data-perimeter-on-aws.html)
- [AWS Control Tower User Guide](https://docs.aws.amazon.com/controltower/latest/userguide/what-is-control-tower.html) · [Controls reference — behavior and guidance](https://docs.aws.amazon.com/controltower/latest/controlreference/control-behavior.html) · [Region deny](https://docs.aws.amazon.com/controltower/latest/userguide/region-deny.html) · [Enrolling existing accounts](https://docs.aws.amazon.com/controltower/latest/userguide/enroll-account.html) · [Limitations and quotas](https://docs.aws.amazon.com/controltower/latest/userguide/limits.html) · [Landing zone 4.0 key changes](https://docs.aws.amazon.com/controltower/latest/userguide/key-changes-lz-v4.html)
- [Account Factory for Terraform (AFT)](https://docs.aws.amazon.com/controltower/latest/userguide/aft-overview.html) · [Customizations for AWS Control Tower](https://docs.aws.amazon.com/controltower/latest/userguide/cfct-overview.html)
- [AWS RAM — Sharing your resources](https://docs.aws.amazon.com/ram/latest/userguide/getting-started-sharing.html) · [Shareable resources](https://docs.aws.amazon.com/ram/latest/userguide/shareable.html)
- [VPC sharing](https://docs.aws.amazon.com/vpc/latest/userguide/vpc-sharing.html) · [Owner and participant responsibilities](https://docs.aws.amazon.com/vpc/latest/userguide/vpc-share-limitations.html) · [Billing](https://docs.aws.amazon.com/vpc/latest/userguide/vpc-share-billing.html)
- [StackSets with AWS Organizations — delegated administrator](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/stacksets-orgs-delegated-admin.html) · [Automatic deployments](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/stacksets-orgs-manage-auto-deployment.html)
- [AWS Config multi-account multi-Region data aggregation](https://docs.aws.amazon.com/config/latest/developerguide/aggregate-data.html) · [Conformance packs](https://docs.aws.amazon.com/config/latest/developerguide/conformance-packs.html)
- [Creating a CloudTrail trail for an organization](https://docs.aws.amazon.com/awscloudtrail/latest/userguide/creating-trail-organization.html)
- [IAM Identity Center — organization instances](https://docs.aws.amazon.com/singlesignon/latest/userguide/organization-instances-identity-center.html)
- [Consolidated billing](https://docs.aws.amazon.com/awsaccountbilling/latest/aboutv2/consolidated-billing.html) · [RI and Savings Plans discount sharing](https://docs.aws.amazon.com/awsaccountbilling/latest/aboutv2/ri-turn-off.html) · [Cost allocation tags](https://docs.aws.amazon.com/awsaccountbilling/latest/aboutv2/cost-alloc-tags.html) · [Cost Categories](https://docs.aws.amazon.com/cost-management/latest/userguide/manage-cost-categories.html) · [AWS Billing Conductor](https://docs.aws.amazon.com/billingconductor/latest/userguide/what-is-billingconductor.html) · [Budgets actions](https://docs.aws.amazon.com/cost-management/latest/userguide/budgets-controls.html)
- [AWS Security Reference Architecture (Prescriptive Guidance)](https://docs.aws.amazon.com/prescriptive-guidance/latest/security-reference-architecture/welcome.html)

---
[← Previous: 01 Exam Blueprint & Strategy](01-Exam-Blueprint-and-Strategy.md) · [Index](00-README-Start-Here.md) · [Next: 03 Identity & Access Management →](03-Identity-and-Access-Management.md)
