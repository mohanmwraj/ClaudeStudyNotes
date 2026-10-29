# Domain 2 · 03 · Multi-Account Automation: Organizations, SCPs and Control Tower

> **Exam tasks:** 2.2 (create, onboard and secure accounts; multi-account IAM; governance at scale), 6.1 (SCPs), 6.2 (controls across accounts and Regions). **Principles:** P2 (guardrails never grant), P6 (account isolation), P13 (centralize and delegate).

## 1. First principles

1. **The account is the blast-radius boundary** (P6). Separate accounts per environment, per workload and per function (security, logging, shared networking).
2. **Guardrails cap, roles grant** (P2). Organization policies (SCPs, RCPs) define the **maximum** permissions possible in an account. IAM policies inside the account grant within that maximum.
3. **New accounts must be secure on day zero, with nobody doing anything.** Every baseline has to be **automatic on account creation**: organization auto-enable for security services, StackSets auto-deployment, Control Tower enrollment, lifecycle-event automation (P13).

---

## 2. AWS Organizations

### 2.1 Structure

* **Management account:** creates the organization and pays the bill. **SCPs don't apply to it.** Keep workloads out of it.
* **Organizational units (OUs):** a hierarchy, up to five levels deep under the root. Policies are inherited down the tree.
* **All features** mode is required for SCPs and other policy types. "Consolidated billing only" mode can't use them.
* **Account creation:** the `CreateAccount` API creates a member account with the **`OrganizationAccountAccessRole`**, which administrators in the management account can assume. **Invited** (existing) accounts don't get that role automatically; you must create it.

### 2.2 Policy types

| Policy | What it controls | Notes |
|---|---|---|
| **Service control policies (SCPs)** | The maximum permissions of **principals** (users and roles, **including the member account's root user**) in member accounts | Don't affect the management account or **service-linked roles**. Never grant. Max 5 attached per root/OU/account; max 5,120 characters each |
| **Resource control policies (RCPs)** (since November 2024) | The maximum permissions on **resources** in member accounts, whoever the caller is, e.g. "no principal outside our organization may access our S3 buckets or KMS keys" | Covers a growing list of services; S3, STS, KMS, SQS and Secrets Manager were the first. A data perimeter without editing every bucket policy |
| **Declarative policies** (since December 2024) | Enforce service *configuration* org-wide (initially EC2: IMDSv2 defaults, block public AMI/snapshot sharing, serial console) | The setting holds even if new APIs are added |
| **Tag policies** | Standardize tag keys and allowed values; report non-compliance (enforcement for chosen resource types) | Pair with SCPs that `Deny` creation without required tags (`aws:RequestTag`) |
| **Backup policies** | Org-wide AWS Backup plans attached to OUs | See [03-Resilient-Cloud-Solutions/03](../03-Resilient-Cloud-Solutions/03-disaster-recovery-and-backup.md) |
| **AI services opt-out policies** | Opt out of content use for service improvement | — |

### 2.3 SCP patterns you must be able to read

**Deny all Regions except two, while exempting global services:**

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Sid": "DenyOutsideApprovedRegions",
    "Effect": "Deny",
    "NotAction": [
      "iam:*", "organizations:*", "sts:*", "route53:*", "cloudfront:*",
      "support:*", "budgets:*", "waf:*", "globalaccelerator:*"
    ],
    "Resource": "*",
    "Condition": {
      "StringNotEquals": { "aws:RequestedRegion": ["eu-west-1", "eu-central-1"] },
      "ArnNotLike": { "aws:PrincipalARN": "arn:aws:iam::*:role/OrgPlatformAdmin" }
    }
  }]
}
```

**Protect security tooling from member-account admins:**

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Sid": "ProtectSecurityServices",
    "Effect": "Deny",
    "Action": [
      "cloudtrail:StopLogging", "cloudtrail:DeleteTrail", "cloudtrail:UpdateTrail",
      "guardduty:DeleteDetector", "guardduty:DisassociateFromMasterAccount", "guardduty:DisassociateFromAdministratorAccount",
      "config:StopConfigurationRecorder", "config:DeleteConfigurationRecorder", "config:DeleteDeliveryChannel",
      "organizations:LeaveOrganization"
    ],
    "Resource": "*",
    "Condition": { "ArnNotLike": { "aws:PrincipalARN": "arn:aws:iam::*:role/SecurityBreakGlass" } }
  }]
}
```

**Two SCP strategies:**
* **Deny list:** keep `FullAWSAccess` attached and add Deny statements. This is the common, maintainable approach.
* **Allow list:** remove `FullAWSAccess` and allow only listed services at each level. It's strict and needs more maintenance, because an allow must exist at **every** level from the root to the account.

**Debugging "the admin can't do X":** check the SCPs on **every** OU from the root down to the account. An action must be allowed at every level and denied at none.

## 3. Cross-account access patterns

| Pattern | Mechanism |
|---|---|
| Human or automation in account A operates in account B | A role in B whose **trust policy** names A (or a specific role in A); A's principal has `sts:AssumeRole` on it |
| A third party (SaaS) assumes a role in your account | Trust policy with a condition on **`sts:ExternalId`** (prevents the confused-deputy problem) |
| A resource policy allowing the whole organization | Condition `aws:PrincipalOrgID` (or `aws:PrincipalOrgPaths` for OUs) instead of listing account IDs. New accounts are included automatically |
| Share resources instead of copying them | **AWS RAM:** subnets (VPC sharing), Transit Gateways, Route 53 Resolver rules, License Manager configurations, Aurora clusters, Network Firewall policies, and more, shared with accounts or the organization |
| Shared KMS-encrypted artifacts | A customer-managed key policy granting the other account (P11) |

## 4. Delegated administration (P13)

Most security and operations services let the management account register a **delegated administrator** member account. That account then manages the service organization-wide. Examples:
* GuardDuty, Security Hub, Inspector, Macie, Detective;
* Config (aggregators, organization rules and conformance packs);
* Firewall Manager;
* IAM Access Analyzer;
* CloudFormation StackSets;
* AWS Backup;
* Systems Manager (Explorer, OpsCenter);
* CloudTrail (organization trail management);
* IAM Identity Center.

**Exam pattern:** "The security team must manage service X for all accounts without using the management account" → register the security account as delegated administrator.

## 5. AWS Control Tower

### 5.1 What it sets up

* **A landing zone:** a well-architected multi-account baseline.
  * **Management account.**
  * **Security OU** with two accounts:
    * **Log Archive**: the organization CloudTrail and Config logs in S3;
    * **Audit**: cross-account read and security roles, and aggregated notifications.
  * **IAM Identity Center** for single sign-on.
  * A **Sandbox** OU (optional additional OUs).
  * **Region deny** settings.
* **Controls** (formerly "guardrails"):

| Kind | Implemented as | Example |
|---|---|---|
| **Preventive** | SCPs (and RCPs) | Disallow deleting the Log Archive bucket; deny Regions |
| **Detective** | AWS Config rules | Detect S3 buckets with public read access |
| **Proactive** | CloudFormation **Hooks** | Block a CloudFormation stack that creates an unencrypted resource |

  Guidance levels: **mandatory** (always on), **strongly recommended**, **elective**.
* **Account Factory:** a Service Catalog product that vends new accounts into a chosen OU with network and baseline settings.
* **Account Factory for Terraform (AFT):** a GitOps account-vending pipeline using Terraform.
* **Account Factory Customization (AFC):** apply a **blueprint** (a Service Catalog product) when vending or updating accounts.
* **Customizations for Control Tower (CfCT):** a solution that uses a pipeline and a manifest to apply SCPs and StackSets to accounts and OUs, triggered by Control Tower lifecycle events.
* **Landing zone drift:** manual changes to Control Tower-managed resources (moving accounts between OUs outside Control Tower, editing managed SCPs) cause drift. Fix it with **Repair landing zone** or re-registering the OU.
* **Enrollment:** existing accounts can be **enrolled**, which applies baselines and controls.

### 5.2 Account onboarding automation, end to end

```text
Account Factory / AFT  ──▶ new account in target OU
        │
        ├─ Control Tower lifecycle event  "CreateManagedAccount" (EventBridge, management account)
        │        └─▶ Lambda / Step Functions / CfCT pipeline: custom baseline
        ├─ StackSets (service-managed, auto-deployment on the OU): roles, Config rules, alarms
        ├─ Org auto-enable: GuardDuty, Security Hub, Inspector, Macie (delegated admin)
        ├─ Organization CloudTrail + Config already cover the account
        └─ IAM Identity Center assignments (permission sets → groups → new account)
```

**Exam rule of thumb:** "automate creating **and** baselining new accounts with the least effort" → Control Tower **Account Factory** (or AFT if the company uses Terraform), plus lifecycle-event-driven customizations or StackSets auto-deployment.

## 6. AWS IAM Identity Center (human access at scale)

* **Identity source:** the built-in directory, AWS Managed Microsoft AD / AD Connector, or an **external IdP** (Okta, Entra ID, …) via SAML with **SCIM** provisioning of users and groups.
* **Permission sets:** templates of policies (AWS-managed, customer-managed by name, inline, plus a permissions boundary). Assigning a permission set to a group for an account **creates an IAM role** in that account.
* **ABAC:** pass user attributes as session tags and use them in policies (`aws:PrincipalTag/CostCenter`).
* **Exam angle:** "single sign-on for 2,000 employees across 80 accounts with least effort" → IAM Identity Center + external IdP + permission sets assigned to groups. Not IAM users in each account.

## 7. Exam traps

* **SCPs don't grant.** An allow-list SCP plus no IAM allow means no access.
* **SCPs don't apply to the management account,** and don't restrict service-linked roles.
* **SCPs do restrict the member account's root user.**
* **Invited accounts** lack `OrganizationAccountAccessRole` until you create it.
* **StackSets service-managed** doesn't deploy to the management account.
* **Region-deny SCPs must exempt global services** (IAM, STS, Organizations, Route 53, CloudFront, Support…), or they break the console and IAM.
* **Control Tower controls are SCPs, RCPs, Config rules and Hooks underneath.** "Detect" means detective (Config); "prevent" means preventive (SCP) or proactive (Hook).
* **"Any principal from our organization" in a bucket policy:** use `aws:PrincipalOrgID`, not a list of account IDs.

## References

* AWS Organizations policies — <https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_policies.html>
* SCPs — <https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_policies_scps.html>
* Resource control policies — <https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_policies_rcps.html>
* Declarative policies — <https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_policies_declarative.html>
* Services that work with Organizations (delegated admin) — <https://docs.aws.amazon.com/organizations/latest/userguide/orgs_integrate_services_list.html>
* AWS Control Tower controls — <https://docs.aws.amazon.com/controltower/latest/controlreference/controls.html>
* Control Tower lifecycle events — <https://docs.aws.amazon.com/controltower/latest/userguide/lifecycle-events.html>
* Account Factory for Terraform — <https://docs.aws.amazon.com/controltower/latest/userguide/aft-overview.html>
* IAM Identity Center permission sets — <https://docs.aws.amazon.com/singlesignon/latest/userguide/permissionsetsconcept.html>
* AWS RAM shareable resources — <https://docs.aws.amazon.com/ram/latest/userguide/shareable.html>
