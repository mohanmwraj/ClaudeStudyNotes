# Domain 6 Drill · Security and Compliance (20 questions)

Original exam-style questions for tasks 6.1–6.3. The notes for this domain are in [06-Security-and-Compliance](../06-Security-and-Compliance/).

---

### Q1 · Task 6.1 · Single answer

Developers must be able to create IAM roles for their Lambda functions without waiting for the platform team. Security is worried that a developer could create a role with more permissions than the developer has, for example `iam:*` or access to the billing console.

What should the DevOps engineer implement?

- **A.** An SCP that denies `iam:CreateRole` for all principals.
- **B.** A weekly review of all roles created by developers.
- **C.** A permissions boundary policy that defines the maximum permissions application roles may have, and a developer policy that allows `iam:CreateRole` and policy attachment only when the `iam:PermissionsBoundary` condition equals that boundary. Also deny changing or removing the boundary.
- **D.** AWS-managed policies attached to developer roles only.

<details><summary>Answer</summary>

**Answer: C**

**Why (P2, P14):** A boundary caps the effective permissions of every role developers create. The condition forces them to attach it, and the deny keeps it in place.

- **A** — wrong: blocks the self-service the requirement asks for.
- **B** — wrong: detective and slow; escalation happens before the review.
- **C** — correct: safe delegation of role creation.
- **D** — wrong: doesn't limit what the created roles can do.

**Reference:** <https://docs.aws.amazon.com/IAM/latest/UserGuide/access_policies_boundaries.html>

</details>

### Q2 · Task 6.1 · Single answer

A company has 50 project teams and adds new projects every week. Each team's engineers may start, stop and reboot **only** the EC2 instances that belong to their project. The security team wants to stop writing new IAM policies for every project.

What should the DevOps engineer implement?

- **A.** Attribute-based access control: tag instances and principals with `project`, and use one policy that allows the actions when `aws:ResourceTag/project` equals `${aws:PrincipalTag/project}`. Enforce tagging at creation, and prevent changes to the `project` tag.
- **B.** One IAM group per project, each with a policy listing that project's instance IDs.
- **C.** One AWS account per engineer.
- **D.** An SCP per project attached to the root.

<details><summary>Answer</summary>

**Answer: A**

**Why (P14):** ABAC scales through tags. New projects only need tags, and the single policy never changes.

- **A** — correct: one policy for all projects, now and in future.
- **B** — wrong: RBAC with resource IDs means constant policy updates.
- **C** — wrong: massively over-engineered.
- **D** — wrong: SCPs don't grant, and they apply to whole accounts, not projects.

**Reference:** <https://docs.aws.amazon.com/IAM/latest/UserGuide/introduction_attribute-based-access-control.html>

</details>

### Q3 · Task 6.1 · Single answer

3,000 employees authenticate with Okta. They need console and CLI access to 120 AWS accounts, with permissions based on their Okta group membership. Leavers must lose access as soon as they're disabled in Okta. The solution must require the LEAST ongoing administration.

What should the DevOps engineer implement?

- **A.** Create IAM users in every account, synchronized from Okta by a nightly script.
- **B.** Configure SAML federation separately in each of the 120 accounts.
- **C.** Create one IAM user per employee in the management account, and roles to assume in every other account.
- **D.** Enable IAM Identity Center with Okta as the external identity provider (SAML), turn on SCIM provisioning of users and groups, and assign permission sets to groups for the accounts.

<details><summary>Answer</summary>

**Answer: D**

**Why (P14, P13):** Identity Center centralizes workforce access across the organization. SCIM keeps users and groups in sync, so disabling someone in Okta removes their access, and permission sets become roles in each account.

- **A** — wrong: long-term credentials and fragile synchronization.
- **B** — wrong: 120 separate configurations to maintain.
- **C** — wrong: IAM users with long-term credentials, and a hand-built cross-account setup.
- **D** — correct: central, federated, automatically synchronized.

**Reference:** <https://docs.aws.amazon.com/singlesignon/latest/userguide/provision-automatically.html>

</details>

### Q4 · Task 6.1 · Select TWO

A third-party SaaS monitoring vendor needs read-only access to CloudWatch metrics and EC2 descriptions in a company's account. The vendor serves many customers from its own AWS account (`999999999999`) and has given the company a unique external ID.

Which combination of steps grants this access securely? (Select TWO.)

- **A.** Create an IAM user for the vendor and send them access keys.
- **B.** Create an IAM role whose trust policy allows `sts:AssumeRole` from account `999999999999`, with a condition that `sts:ExternalId` equals the vendor-provided external ID.
- **C.** Create a role whose trust policy allows `"Principal": "*"` so that the vendor's changing IP addresses work.
- **D.** Attach a least-privilege permissions policy to the role that allows only the required read actions, such as `cloudwatch:GetMetricData`, `cloudwatch:ListMetrics` and `ec2:Describe*`.
- **E.** Share the account's root user credentials with the vendor under an NDA.

<details><summary>Answer</summary>

**Answer: B, D**

**Why (P14, P2):** Cross-account access uses role assumption. The external ID prevents the confused-deputy problem, where another of the vendor's customers tricks the vendor into using your role. Permissions stay minimal.

- **A** — wrong: long-term credentials held by a third party.
- **B** — correct: trust scoped to the vendor, plus the external ID.
- **C** — wrong: anyone could assume the role.
- **D** — correct: least privilege.
- **E** — wrong: never.

**Reference:** <https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_create_for-user_externalid.html>

</details>

### Q5 · Task 6.1 · Single answer

An application connects to Amazon RDS for PostgreSQL with a database user whose password is in Secrets Manager. The password must rotate every 30 days, and the application must not see authentication failures during rotation, even for connections opened mid-rotation.

Which rotation configuration should the DevOps engineer use?

- **A.** Single-user rotation, every 30 days.
- **B.** Alternating-users rotation, in which the rotation function switches between two database users so that the previous credentials remain valid while the application picks up the new secret.
- **C.** A Lambda function that changes the password every 30 days and restarts the application.
- **D.** Store the password in Parameter Store with a 30-day parameter policy.

<details><summary>Answer</summary>

**Answer: B**

**Why (P11):** With alternating users, one set of credentials is always valid. Single-user rotation has a short window in which cached old credentials fail.

- **A** — wrong: allows a brief window of authentication failures.
- **B** — correct: rotation without failures.
- **C** — wrong: custom code, and restarts cause downtime.
- **D** — wrong: parameter policies only notify about expiration; they don't rotate anything.

**Reference:** <https://docs.aws.amazon.com/secretsmanager/latest/userguide/rotation-strategy.html>

</details>

### Q6 · Task 6.1 · Single answer

A Secrets Manager rotation function for an RDS secret runs in the database's private subnets so that it can reach the database. Rotation fails because the function times out when it calls the Secrets Manager API. The VPC has no NAT gateway.

What should the DevOps engineer do?

- **A.** Move the database to a public subnet.
- **B.** Increase the rotation function's timeout to 15 minutes.
- **C.** Disable rotation and change the password manually.
- **D.** Create an interface VPC endpoint for Secrets Manager in the VPC, with a security group that allows HTTPS from the rotation function.

<details><summary>Answer</summary>

**Answer: D**

**Why (P7, P11):** The rotation function needs network paths to **both** the database and the Secrets Manager API. Without NAT, the API path is an interface endpoint.

- **A** — wrong: exposes the database and doesn't fix the function's path to the API.
- **B** — wrong: there's no route, so waiting longer doesn't help.
- **C** — wrong: abandons the requirement.
- **D** — correct: private connectivity to Secrets Manager.

**Reference:** <https://docs.aws.amazon.com/secretsmanager/latest/userguide/troubleshoot_rotation.html>

</details>

### Q7 · Task 6.1 · Single answer

Policy requires that IAM users who sign in to the console can do nothing except set up and manage their own MFA device until they've authenticated with MFA.

Which policy design implements this?

- **A.** A policy that allows the self-service MFA actions on the user's own identity, and **denies all other actions** (`NotAction` listing the self-service MFA actions) when `aws:MultiFactorAuthPresent` is false (`BoolIfExists`).
- **B.** A password policy that requires a minimum length of 20 characters.
- **C.** An SCP that requires MFA for the management account's root user.
- **D.** A CloudWatch alarm on console sign-ins without MFA.

<details><summary>Answer</summary>

**Answer: A**

**Why (P2):** An explicit deny conditioned on the absence of MFA blocks everything except the actions needed to set MFA up, whatever other allows exist.

- **A** — correct: the documented "force MFA" pattern.
- **B** — wrong: password strength isn't MFA.
- **C** — wrong: SCPs don't affect the management account, and IAM users are the target here.
- **D** — wrong: detective only.

**Reference:** <https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_policies_examples_aws_my-sec-creds-self-manage.html>

</details>

### Q8 · Task 6.2 · Single answer

An audit finds a production Amazon RDS for MySQL instance that was created **without** encryption at rest. It must be encrypted with a customer managed KMS key, with minimal downtime.

What should the DevOps engineer do?

- **A.** Modify the instance and turn on encryption; RDS encrypts the data in place.
- **B.** Enable EBS encryption by default in the account; RDS picks it up after a reboot.
- **C.** Take a snapshot, copy the snapshot with encryption enabled using the customer managed key, restore a new instance from the encrypted copy, and cut the application over (for example with a short write freeze, or with replication to minimize downtime).
- **D.** Create an encrypted read replica of the unencrypted instance and promote it.

<details><summary>Answer</summary>

**Answer: C**

**Why (P11):** RDS encryption is fixed when an instance is created. You get an encrypted copy by copying a snapshot with encryption and restoring from it.

- **A** — wrong: existing unencrypted instances can't be encrypted in place.
- **B** — wrong: the EBS default doesn't affect existing RDS instances.
- **C** — correct: the documented method.
- **D** — wrong: you can't create an encrypted read replica of an unencrypted instance.

**Reference:** <https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/Overview.Encryption.html>

</details>

### Q9 · Task 6.2 · Single answer

A team requests a public ACM certificate for `www.example.com` in `eu-west-1`, where its application runs, and validates it with DNS. When the engineer configures an Amazon CloudFront distribution's alternate domain name, the certificate doesn't appear in the list.

What should the engineer do?

- **A.** Import the certificate's private key into CloudFront.
- **B.** Request (or import) the certificate in ACM in the `us-east-1` Region and select it for the distribution.
- **C.** Wait 24 hours for the certificate to replicate to CloudFront.
- **D.** Use email validation instead of DNS validation.

<details><summary>Answer</summary>

**Answer: B**

**Why (P11):** CloudFront only uses ACM certificates from `us-east-1`, wherever the origin is.

- **A** — wrong: you can't export the private keys of ACM-issued public certificates.
- **B** — correct: the documented requirement.
- **C** — wrong: certificates don't replicate between Regions.
- **D** — wrong: the validation method doesn't matter here.

**Reference:** <https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/cnames-and-https-requirements.html>

</details>

### Q10 · Task 6.2 · Single answer

A company has tens of thousands of S3 buckets across 40 accounts. Compliance requires continuously identifying which buckets contain personal data (names, passport numbers, credit card numbers), across all accounts, and sending findings to the security team's tooling.

What should the DevOps engineer implement?

- **A.** A Lambda function that downloads every object and runs regular expressions.
- **B.** Amazon GuardDuty S3 Protection.
- **C.** S3 Inventory reports in every account.
- **D.** Amazon Macie enabled for the organization through a delegated administrator, with automated sensitive data discovery turned on, and findings sent to EventBridge and Security Hub.

<details><summary>Answer</summary>

**Answer: D**

**Why (P13, P12):** Macie discovers sensitive data in S3 using managed and custom data identifiers, and runs org-wide with automated sampling.

- **A** — wrong: custom, costly, and incomplete.
- **B** — wrong: GuardDuty detects threats and suspicious access, not the content of objects.
- **C** — wrong: lists objects without classifying their content.
- **D** — correct: purpose-built, org-wide, automated.

**Reference:** <https://docs.aws.amazon.com/macie/latest/user/discovery-asdd.html>

</details>

### Q11 · Task 6.2 · Select TWO

Security requires that every Application Load Balancer and CloudFront distribution in every account of the organization (including future ones) is protected by AWS WAF with the AWS managed core rule set and a rate-based rule. Non-compliant resources must be fixed automatically.

Which combination of steps meets these requirements with the LEAST effort? (Select TWO.)

- **A.** Designate an AWS Firewall Manager administrator account in the organization, and make sure AWS Config is enabled in the member accounts.
- **B.** Create a Firewall Manager AWS WAF policy containing the managed core rule set and a rate-based rule, scoped to ALBs and CloudFront distributions across the organization, with automatic remediation.
- **C.** Write a Lambda function, triggered by `CreateLoadBalancer`, that associates a web ACL.
- **D.** Rely on AWS Shield Standard.
- **E.** Add network ACL rules that block suspicious IP addresses in every VPC.

<details><summary>Answer</summary>

**Answer: A, B**

**Why (P13, P12):** Firewall Manager applies WAF policies across accounts, and automatically to newly created in-scope resources. It requires Organizations, a Firewall Manager administrator, and AWS Config.

- **A** — correct: the prerequisites.
- **B** — correct: central policy with automatic remediation.
- **C** — wrong: custom per-event code, and it misses CloudFront and existing resources.
- **D** — wrong: Shield Standard is DDoS protection, not WAF rules.
- **E** — wrong: NACLs aren't application-layer protection, and this is manual.

**Reference:** <https://docs.aws.amazon.com/waf/latest/developerguide/fms-chapter.html>

</details>

### Q12 · Task 6.2 · Single answer

A regulator requires that a bank's encryption keys for S3 and EBS data be generated and stored in single-tenant HSMs that the bank controls exclusively and that are validated to FIPS 140-3 Level 3. The bank still wants to use the native KMS integration of S3 and EBS.

What should the DevOps engineer implement?

- **A.** An AWS KMS custom key store backed by an AWS CloudHSM cluster, with KMS keys created in that key store.
- **B.** KMS customer managed keys with automatic rotation.
- **C.** Imported key material in standard KMS keys.
- **D.** Client-side encryption with keys stored in Parameter Store.

<details><summary>Answer</summary>

**Answer: A**

**Why (P11):** A CloudHSM-backed custom key store keeps key material in the bank's dedicated HSMs while still exposing standard KMS keys to integrated services.

- **A** — correct: dedicated HSMs plus native integration.
- **B** — wrong: standard KMS uses multi-tenant HSMs that AWS manages.
- **C** — wrong: the material still lives in AWS-managed KMS HSMs.
- **D** — wrong: breaks the native integration and weakens key protection.

**Reference:** <https://docs.aws.amazon.com/kms/latest/developerguide/keystore-cloudhsm.html>

</details>

### Q13 · Task 6.2 · Single answer

Threat intelligence identifies a malicious IP range that's scanning a company's web and SSH services in one VPC. The security team wants **all** traffic from that range blocked at the subnet boundary immediately, while other traffic is unaffected.

What should the DevOps engineer do?

- **A.** Remove the range from the security groups' allow rules.
- **B.** Enable GuardDuty.
- **C.** Add a network ACL **deny** rule for the range, with a lower rule number than the existing allow rules, on the affected subnets' NACLs.
- **D.** Add a WAF IP set rule on the ALB.

<details><summary>Answer</summary>

**Answer: C**

**Why (P2):** NACLs support explicit **deny** rules, evaluated in rule-number order, for all protocols at the subnet boundary. Security groups can only allow.

- **A** — wrong: security groups can't deny, and the range may be covered by broader allow rules.
- **B** — wrong: detects but doesn't block.
- **C** — correct: an immediate subnet-level block for all protocols.
- **D** — wrong: covers only HTTP(S) through the ALB, not SSH.

**Reference:** <https://docs.aws.amazon.com/vpc/latest/userguide/vpc-network-acls.html>

</details>

### Q14 · Task 6.2 · Single answer

Workloads in private subnets may make outbound HTTPS connections **only** to an approved list of domains (for example `*.amazonaws.com` and `api.partner.com`), and the decision must use the destination domain name, not IP addresses. Traffic leaves through a central egress VPC.

What should the DevOps engineer use?

- **A.** Security group outbound rules listing the partner's IP addresses.
- **B.** Network ACL outbound rules.
- **C.** AWS WAF on the NAT gateway.
- **D.** AWS Network Firewall in the egress path, with a stateful domain allowlist rule group (matching on TLS SNI and HTTP Host) and a default drop for everything else.

<details><summary>Answer</summary>

**Answer: D**

**Why (P2):** Network Firewall supports stateful domain-list filtering for egress traffic, centrally.

- **A** — wrong: IP-based, and IPs change.
- **B** — wrong: IP-based and stateless.
- **C** — wrong: WAF can't be attached to NAT gateways, and it inspects inbound web requests.
- **D** — correct: managed, domain-aware egress filtering.

**Reference:** <https://docs.aws.amazon.com/network-firewall/latest/developerguide/stateful-rule-groups-domain-names.html>

</details>

### Q15 · Task 6.3 · Single answer

Auditors require audit logs of API activity from all 70 accounts that member-account administrators can't disable or alter, and that can be **proven** unaltered during audits.

What should the DevOps engineer implement?

- **A.** A trail in each account, written to a bucket in that account.
- **B.** An organization trail (all Regions) that delivers to an S3 bucket in a dedicated log-archive account, with log file integrity validation enabled, a restrictive bucket policy (with Object Lock if required), and an SCP that denies `cloudtrail:StopLogging`, `DeleteTrail` and `UpdateTrail`.
- **C.** CloudTrail Event history in each account.
- **D.** VPC Flow Logs in every VPC.

<details><summary>Answer</summary>

**Answer: B**

**Why (P13, P6):** four controls work together:
* Organization trails cover every account and can't be changed by members.
* A separate account isolates the logs from the people being audited.
* Digest files prove integrity.
* The SCP blocks tampering with the trail.

- **A** — wrong: local administrators can stop or delete their own trails and logs.
- **B** — correct: tamper-resistant and provable.
- **C** — wrong: only 90 days of management events, with no integrity proof.
- **D** — wrong: network metadata, not API activity.

**Reference:** <https://docs.aws.amazon.com/awscloudtrail/latest/userguide/cloudtrail-log-file-validation-intro.html>

</details>

### Q16 · Task 6.3 · Single answer

A sensitive S3 bucket's objects were downloaded unexpectedly. The investigation needs to know which IAM principals called `GetObject` on which objects, and when. The account has a multi-Region trail with default settings.

What must be enabled to capture this in future?

- **A.** CloudTrail data events (S3 object-level, read events) for that bucket on the trail.
- **B.** CloudTrail Insights events.
- **C.** S3 Inventory.
- **D.** AWS Config recording for S3 buckets.

<details><summary>Answer</summary>

**Answer: A**

**Why (P10):** Object-level operations such as `GetObject` are **data events**, which trails don't record by default. Management events cover bucket-level configuration only.

- **A** — correct: records who read which object.
- **B** — wrong: detects unusual API volumes; it doesn't record per-object access.
- **C** — wrong: lists objects, not who accessed them.
- **D** — wrong: records configuration, not access.

**Reference:** <https://docs.aws.amazon.com/awscloudtrail/latest/userguide/logging-data-events-with-cloudtrail.html>

</details>

### Q17 · Task 6.3 · Select TWO

The security team must be alerted within minutes whenever the **root user** performs any action in any account of the organization.

Which combination of steps meets this requirement? (Select TWO.)

- **A.** Create an EventBridge rule that matches CloudTrail events where `detail.userIdentity.type` is `Root` (in each account, or forwarded to a central event bus) and targets an SNS topic.
- **B.** Generate GuardDuty sample findings every day.
- **C.** Enable the AWS Config rule `iam-root-access-key-check`.
- **D.** Make sure a CloudTrail trail (for example an organization trail covering all Regions) is logging, so that root API activity is recorded and delivered to EventBridge.
- **E.** Enable Amazon Inspector.

<details><summary>Answer</summary>

**Answer: A, D**

**Why (P1):** EventBridge receives CloudTrail API-call events only when a trail is logging. A rule on the root identity type then notifies within minutes.

- **A** — correct: real-time matching and notification.
- **B** — wrong: sample findings are fake test data.
- **C** — wrong: checks whether root access keys **exist**, not whether root is used.
- **D** — correct: the prerequisite for API-call events.
- **E** — wrong: vulnerability scanning.

**Reference:** <https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-service-event-cloudtrail.html>

</details>

### Q18 · Task 6.3 · Single answer

The security team wants a continuously updated list of resources, such as S3 buckets, KMS keys, IAM roles, Lambda functions and SQS queues, in any account of the organization that grant access to principals **outside** the organization.

What should the DevOps engineer enable?

- **A.** AWS Trusted Advisor.
- **B.** Amazon GuardDuty.
- **C.** IAM Access Analyzer with the organization as the zone of trust, created in the management account or a delegated administrator account.
- **D.** Amazon Inspector.

<details><summary>Answer</summary>

**Answer: C**

**Why (P13):** Access Analyzer reasons over resource policies and reports access granted outside the zone of trust, and an organization zone covers every account.

- **A** — wrong: limited checks, and not an external-access analysis across these resource types.
- **B** — wrong: detects threats in activity, not policy grants.
- **C** — correct: purpose-built external-access findings.
- **D** — wrong: vulnerabilities, not access policies.

**Reference:** <https://docs.aws.amazon.com/IAM/latest/UserGuide/what-is-access-analyzer.html>

</details>

### Q19 · Task 6.3 · Single answer

GuardDuty raised a high-severity finding that an EC2 instance is communicating with a known command-and-control server. The analysts need to see the instance's network and API activity over the previous weeks, which IAM roles it used, and which other resources it interacted with, visually, without building queries.

What should they use?

- **A.** CloudWatch Logs Insights over VPC Flow Logs.
- **B.** AWS Config's resource timeline.
- **C.** Amazon Inspector.
- **D.** Amazon Detective, pivoting from the GuardDuty finding into the behaviour graph for the instance.

<details><summary>Answer</summary>

**Answer: D**

**Why (P10):** Detective builds behaviour graphs from CloudTrail, VPC Flow Logs and GuardDuty data for visual investigation, and links directly from findings.

- **A** — wrong: possible, but manual queries over one data source only.
- **B** — wrong: shows configuration changes, not behaviour.
- **C** — wrong: vulnerabilities, not investigation.
- **D** — correct: purpose-built investigation.

**Reference:** <https://docs.aws.amazon.com/detective/latest/userguide/what-is-detective.html>

</details>

### Q20 · Task 6.3 · Single answer

A company pushes container images to Amazon ECR and deploys them for months. It wants to know about vulnerabilities in images that are already deployed when **new** CVEs are published after the push, including vulnerabilities in language packages (for example Python and Java libraries), not just OS packages.

What should the DevOps engineer enable?

- **A.** ECR basic scanning on push.
- **B.** ECR enhanced scanning with Amazon Inspector in continuous mode.
- **C.** AWS Config rules for ECR.
- **D.** Docker Content Trust image signing.

<details><summary>Answer</summary>

**Answer: B**

**Why (P12):** Enhanced scanning re-evaluates images continuously as new CVEs are published, and covers both OS and programming-language packages.

- **A** — wrong: on-push and manual scans only, and OS packages only.
- **B** — correct: continuous, with broader coverage.
- **C** — wrong: checks configuration, not vulnerabilities.
- **D** — wrong: signing proves integrity. It doesn't find vulnerabilities.

**Reference:** <https://docs.aws.amazon.com/AmazonECR/latest/userguide/image-scanning-enhanced.html>

</details>
