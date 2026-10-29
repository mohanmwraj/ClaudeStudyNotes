# Domain 6 · 01 · Identity and Access Management at Scale

> **Exam task:** 6.1 (IAM entities for humans and machines, federation, permissions boundaries, SCPs, least privilege, RBAC/ABAC, credential rotation, MFA, STS, instance profiles); also 2.2 (multi-account IAM). **Principles:** P2 (the authorization intersection), P14 (roles and temporary credentials).

## 1. First principles

1. **Every request is authenticated, then authorized by evaluating every applicable policy.** Explicit deny wins; otherwise you need an allow, **within** every guardrail that applies (P2).
2. **Identities should be temporary.** Humans federate into roles; machines get roles. The credentials are short-lived STS tokens. Long-term access keys are the exception you have to justify (P14).
3. **Scale permissions with structure, not with more policies.** Use groups and permission sets for humans, **tags (ABAC)** for resources, **boundaries** for delegation, and **SCPs/RCPs** for organization limits.

---

## 2. The policy types

| Policy | Attached to | Grants? | Typical use |
|---|---|---|---|
| **Identity-based** (AWS-managed, customer-managed, inline) | Users, groups, roles | Yes | What a principal may do |
| **Resource-based** | S3 buckets, KMS keys, SQS, SNS, Lambda, Secrets Manager, ECR, EventBridge buses, … and **role trust policies** | Yes (incl. **cross-account**) | Who may access this resource |
| **Permissions boundary** | Users, roles | No (caps identity policies) | Safe delegation of IAM administration |
| **SCP / RCP** | Organization root, OU, account | No (caps principals / resources) | Organization guardrails |
| **Session policy** | Passed on `AssumeRole*` / `GetFederationToken` | No (caps the session) | Narrow a broad role for one task |
| **VPC endpoint policy** | Interface or gateway endpoint | No (caps what passes through the endpoint) | "Only our buckets via this endpoint" |
| ACLs (S3, legacy) | Buckets and objects | Yes | Avoid; disable with **Object Ownership: bucket owner enforced** |

### 2.1 Evaluation logic

```text
1. Any explicit Deny in any applicable policy?             → DENY
2. SCPs (principal's account) and RCPs (resource's account) allow?   no → DENY
3. Resource-based policy allows this principal?            (same account: can be enough on its own*)
4. Identity-based policy allows?                           neither 3 nor 4 → DENY
5. Permissions boundary (if any) allows?                   no → DENY
6. Session policy (if any) allows?                         no → DENY
                                                           → ALLOW
```

\* Within one account, a resource policy that names an IAM **user or role ARN** can grant access even without an identity-policy allow (boundaries and session policies still apply in the documented ways). **Across accounts, both sides must allow:** the caller's identity policy **and** the resource policy or trust policy.

**KMS is different:** the **key policy** must allow access, either directly or by enabling IAM policies via the root-account statement. An IAM allow alone doesn't work if the key policy doesn't delegate to IAM.

## 3. Identities: who should use what

| Who | Use | Not |
|---|---|---|
| Workforce humans | **IAM Identity Center** (with your IdP via SAML + SCIM) → permission sets → roles in accounts; or SAML 2.0 federation directly to IAM roles | IAM users with passwords in every account |
| Customers of your app | **Amazon Cognito** user pools (sign-up/sign-in) + identity pools (temporary AWS credentials) | IAM users |
| EC2 workloads | **Instance profile** (role), with **IMDSv2** required | Access keys in files, user data or AMIs |
| ECS / EKS / Lambda workloads | **Task role** / **IRSA or EKS Pod Identity** / **execution role** | Node-wide instance roles for app permissions |
| On-premises servers and workloads in other clouds | **IAM Roles Anywhere** (X.509 certificates from your CA → temporary credentials); SSM hybrid activation for managed-node functionality | Long-term keys |
| External CI/CD (GitHub Actions, GitLab) | **OIDC identity provider** + role with a trust condition on `sub` (repo and branch) and `aud` | Stored access keys |
| Third-party SaaS accessing your account | Cross-account role + **`sts:ExternalId`** condition | Sharing your keys |
| AWS services acting for you | Service roles (you pass them with `iam:PassRole`) and service-linked roles | — |
| Emergency | A break-glass role or user with strong MFA, monitored | Daily root use |

**The root user:** MFA on, no access keys, used only for the few root-only tasks. Alarm on any root activity (see [03-detection-auditing-and-response.md](03-detection-auditing-and-response.md)). With Organizations you can **centrally manage root access**: remove root credentials from member accounts, and perform root-only actions from the management account.

## 4. STS and temporary credentials

| API | For |
|---|---|
| `AssumeRole` | Cross-account and same-account role use (sessions 15 minutes up to the role's maximum, ≤ 12 hours; **role chaining** limits sessions to 1 hour) |
| `AssumeRoleWithSAML` | SAML federation |
| `AssumeRoleWithWebIdentity` | OIDC (EKS IRSA, GitHub Actions, Cognito) |
| `GetSessionToken` | MFA-backed temporary credentials for an IAM user (MFA-protected API access) |
| `GetFederationToken` | A custom identity broker (legacy) |

**MFA enforcement in policies:** use `aws:MultiFactorAuthPresent` (`Bool`) and `aws:MultiFactorAuthAge`. A common pattern denies everything except managing your own MFA unless `aws:MultiFactorAuthPresent` is true.

**Revoking a role's sessions:** attach a Deny with `aws:TokenIssueTime` earlier than now (the console's "Revoke active sessions"). Existing credentials keep working until expiry otherwise.

## 5. Delegation with permissions boundaries

**Problem:** let developers create IAM roles for their Lambda functions, without letting them create a role more powerful than themselves (privilege escalation).

**Pattern:**
1. Write a boundary policy `DevBoundary` that allows only what applications may ever do, e.g. specific services, no IAM, no Organizations.
2. Give developers permission to create and modify roles **only if** the new role carries that boundary:

```json
{
  "Effect": "Allow",
  "Action": ["iam:CreateRole", "iam:AttachRolePolicy", "iam:PutRolePolicy"],
  "Resource": "arn:aws:iam::111122223333:role/app/*",
  "Condition": { "StringEquals": { "iam:PermissionsBoundary": "arn:aws:iam::111122223333:policy/DevBoundary" } }
}
```

3. Deny changing or removing the boundary (`iam:DeleteRolePermissionsBoundary`, editing the `DevBoundary` policy), and restrict `iam:PassRole` to `role/app/*`.

Whatever policy a developer attaches, the role's effective permissions are capped at `DevBoundary`.

## 6. RBAC vs ABAC

* **RBAC:** permissions per job function (role, group, permission set). Simple, but grows linearly: a new project means new policies.
* **ABAC:** one policy compares tags, e.g. `aws:PrincipalTag/project` = `aws:ResourceTag/project`. New projects need no new policy, only tags. Prerequisites:
  * principals carry tags: session tags from the IdP or Identity Center attributes;
  * resources are tagged at creation: enforce with `aws:RequestTag` and `aws:TagKeys` conditions, plus SCPs;
  * users can't change the tags that grant access (deny `TagResource`/`UntagResource` on those keys).

```json
{
  "Effect": "Allow",
  "Action": ["ec2:StartInstances", "ec2:StopInstances"],
  "Resource": "*",
  "Condition": { "StringEquals": { "aws:ResourceTag/project": "${aws:PrincipalTag/project}" } }
}
```

## 7. Least privilege in practice

* **IAM Access Analyzer:**
  * **external-access findings:** resources shared outside your zone of trust, the account or the organization;
  * **unused-access findings:** unused roles, access keys, passwords and permissions;
  * **policy generation** from CloudTrail activity;
  * **policy validation** (100+ checks);
  * **custom policy checks** (`CheckNoNewAccess`, `CheckAccessNotGranted`) in a pipeline to block over-permissive policy changes.
* **Last-accessed information** and the **credential report** (users, key age, MFA status).
* **Conditions** that narrow access:
  * `aws:SourceIp`, `aws:SourceVpce`, `aws:SourceVpc` (network origin);
  * `aws:RequestedRegion`;
  * `aws:PrincipalOrgID`;
  * **`aws:SourceArn` / `aws:SourceAccount`** in resource policies for service principals, which **prevents the confused-deputy problem** (e.g. the SNS topic policy accepts only *your* S3 bucket's events);
  * `aws:CalledVia` (only through CloudFormation).

## 8. Automating credential rotation for machine identities

| Credential | Rotation mechanism |
|---|---|
| Database passwords (RDS, Aurora, Redshift, DocumentDB) | **Secrets Manager rotation:** **managed rotation** for supported services, or a rotation **Lambda** (AWS templates). Strategies: **single user** (brief window where connections with the old password fail) or **alternating users** (two users, no downtime). The rotation Lambda needs a **network path to the database** and **to the Secrets Manager endpoint** (a VPC endpoint or NAT) |
| RDS master password | `ManageMasterUserPassword` stores and **rotates** it in Secrets Manager automatically |
| Avoid DB passwords entirely | **RDS IAM database authentication** (15-minute auth tokens from the role) |
| API keys and third-party tokens | Secrets Manager with a custom rotation Lambda |
| IAM access keys (if unavoidable) | Config rule `access-keys-rotated` + automation; better, replace with roles, Roles Anywhere or OIDC |
| TLS certificates | ACM automatic renewal (ACM-issued); Private CA for internal |
| Applications reading rotated secrets | Fetch at runtime and **cache with a TTL** (Secrets Manager caching clients, the Parameters and Secrets Lambda Extension, ECS `secrets` injected at task start, so restart tasks to pick up a rotation) |

## 9. Exam traps

* **IAM users with access keys** for workloads or CI. Almost always wrong: use roles, OIDC or Roles Anywhere.
* **An SCP can't grant;** a boundary can't grant. Both only cap.
* **Cross-account:** remember **both** policies (identity in the caller's account + resource/trust policy in the target account), **plus** the KMS key policy if the data is encrypted.
* **AWS-managed KMS keys can't be used cross-account.**
* **Role chaining caps the session at 1 hour.**
* **`iam:PassRole`** is needed to give a role to a service (EC2, Lambda, ECS, CloudFormation). It's a common missing permission.
* **Secrets Manager rotation fails** when the rotation Lambda in a VPC can't reach the Secrets Manager API (no endpoint or NAT) or the database (security group).

## References

* Policy evaluation logic — <https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_policies_evaluation-logic.html>
* Cross-account policy evaluation — <https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_policies_evaluation-logic-cross-account.html>
* Permissions boundaries — <https://docs.aws.amazon.com/IAM/latest/UserGuide/access_policies_boundaries.html>
* ABAC for AWS — <https://docs.aws.amazon.com/IAM/latest/UserGuide/introduction_attribute-based-access-control.html>
* IAM Roles Anywhere — <https://docs.aws.amazon.com/rolesanywhere/latest/userguide/introduction.html>
* OIDC identity providers — <https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_providers_create_oidc.html>
* The confused deputy problem — <https://docs.aws.amazon.com/IAM/latest/UserGuide/confused-deputy.html>
* IAM Access Analyzer — <https://docs.aws.amazon.com/IAM/latest/UserGuide/what-is-access-analyzer.html>
* Secrets Manager rotation — <https://docs.aws.amazon.com/secretsmanager/latest/userguide/rotating-secrets.html>
* Centrally manage root access — <https://docs.aws.amazon.com/IAM/latest/UserGuide/id_root-user.html>
