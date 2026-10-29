# Domain 2 Drill · Configuration Management and IaC (20 questions)

Original exam-style questions for tasks 2.1–2.3. The notes for this domain are in [02-Configuration-Management-and-IaC](../02-Configuration-Management-and-IaC/).

---

### Q1 · Task 2.1 · Single answer

A CloudFormation stack update changed a property of an `AWS::RDS::DBInstance` that requires replacement. CloudFormation created a new, empty database and deleted the old one, and production data was lost. The team wants to make sure that future updates can't silently replace or delete this database, and that a copy of the data survives if a replacement or deletion ever does happen.

Which solution meets these requirements?

- **A.** Set `DeletionPolicy: Snapshot` and `UpdateReplacePolicy: Snapshot` on the database resource, and apply a stack policy that denies `Update:Replace` and `Update:Delete` on it.
- **B.** Enable termination protection on the stack.
- **C.** Set `DeletionPolicy: Retain` on the database resource only.
- **D.** Enable drift detection on the stack and run it before every update.

<details><summary>Answer</summary>

**Answer: A**

**Why (P3, P4):** A stack policy **blocks** replacing or deleting the protected resource during updates. `UpdateReplacePolicy` and `DeletionPolicy` preserve a snapshot if a replacement or deletion is ever allowed.

- **A** — correct: prevention (the stack policy) plus preservation (snapshots on replacement and deletion).
- **B** — wrong: termination protection blocks deleting the **stack**, not replacing a resource during an update.
- **C** — wrong: `DeletionPolicy` doesn't apply to the old resource during an update **replacement**; that's `UpdateReplacePolicy`. Nothing here prevents the replacement either.
- **D** — wrong: drift detection compares reality with the template. It doesn't preview or block replacements (change sets preview; stack policies block).

**Reference:** <https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/protect-stack-resources.html>

</details>

### Q2 · Task 2.1 · Single answer

A pipeline deploys infrastructure changes with a CloudFormation action in `CREATE_UPDATE` mode. After an incident caused by an unexpected resource replacement, the change advisory board requires a human to review **exactly which resources will be added, modified or replaced** before any production stack change is applied.

How should the DevOps engineer change the pipeline?

- **A.** Add a manual approval action before the existing `CREATE_UPDATE` action.
- **B.** Enable CloudFormation drift detection and have the board review the drift report before approving.
- **C.** Replace the deploy action with a `CHANGE_SET_REPLACE` action, a manual approval action, and a `CHANGE_SET_EXECUTE` action, in that order.
- **D.** Run `cfn-lint` in a CodeBuild action and fail the pipeline if the template changed.

<details><summary>Answer</summary>

**Answer: C**

**Why (P3):** A change set is the preview of exactly what an update will do, including `Replacement: True`. Approving between creating and executing it is the standard review gate.

- **A** — wrong: the approver has no preview of the actual changes.
- **B** — wrong: drift describes past manual changes, not the effect of the upcoming update.
- **C** — correct: preview → approve → execute.
- **D** — wrong: linting checks syntax and best practices, not the effect on the live stack.

**Reference:** <https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/using-cfn-updating-stacks-changesets.html>

</details>

### Q3 · Task 2.1 · Single answer

A CloudFormation template launches an EC2 instance whose user data installs and configures an application, which takes about 6 minutes. Other resources in the stack, and the pipeline's tests, start as soon as the instance reaches `CREATE_COMPLETE`, which happens within seconds of launch. The tests fail because the application isn't ready yet.

What should the DevOps engineer do?

- **A.** Add a `DependsOn` attribute from every other resource to the instance.
- **B.** Add a 10-minute `sleep` command to the beginning of the test stage.
- **C.** Set the instance's `DeletionPolicy` to `Retain` so it isn't recreated during retries.
- **D.** Add a `CreationPolicy` with a `ResourceSignal` count of 1 and a timeout, and call `cfn-signal` with the exit status of the setup at the end of the user data.

<details><summary>Answer</summary>

**Answer: D**

**Why (P5):** `CreationPolicy` makes CloudFormation wait for a success signal from the instance before marking it complete. The stack, and everything after it, then reflects real readiness.

- **A** — wrong: `DependsOn` waits for `CREATE_COMPLETE`, which is reached immediately without a signal.
- **B** — wrong: a fixed sleep is brittle and doesn't detect setup failure.
- **C** — wrong: unrelated to readiness.
- **D** — correct: readiness becomes part of the stack's state, and a failed setup fails the stack.

**Reference:** <https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-attribute-creationpolicy.html>

</details>

### Q4 · Task 2.1 · Select TWO

A company uses AWS Organizations. Every account in the `Workloads` OU, including accounts created in the future, must automatically receive a standard IAM role and a set of AWS Config rules defined in one CloudFormation template. The solution must require the LEAST ongoing effort.

Which combination of steps meets these requirements? (Select TWO.)

- **A.** Create a StackSet with self-managed permissions, and create the administration and execution roles in every account.
- **B.** Create a StackSet with service-managed permissions after enabling trusted access for CloudFormation StackSets in Organizations.
- **C.** Create a Lambda function triggered by the `CreateAccount` API that deploys the stack into each new account.
- **D.** Target the `Workloads` OU with the StackSet and enable automatic deployment.
- **E.** Share the template through AWS RAM with every account and ask account owners to deploy it.

<details><summary>Answer</summary>

**Answer: B, D**

**Why (P6, P13):** Service-managed StackSets use Organizations to deploy to an OU, and **automatic deployment** creates stack instances in accounts that join the OU later.

- **A** — wrong: self-managed permissions need roles created in each account manually and don't auto-deploy to new accounts.
- **B** — correct: the prerequisite for OU targeting and automatic deployment.
- **C** — wrong: custom code reimplementing automatic deployment.
- **D** — correct: covers existing and future accounts in the OU.
- **E** — wrong: RAM doesn't share CloudFormation templates for deployment, and the process is manual.

**Reference:** <https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/stacksets-orgs-manage-auto-deployment.html>

</details>

### Q5 · Task 2.1 · Single answer

A platform team updates a StackSet that is deployed to 40 accounts in 6 Regions. A previous update with a mistake broke all 240 stack instances within minutes. The team now wants updates to touch only a few accounts at a time, and the whole operation to stop as soon as more than two accounts fail in a Region.

Which StackSet operation preferences should be used?

- **A.** Maximum concurrent accounts 100%, failure tolerance 0, Regions in parallel.
- **B.** Maximum concurrent accounts 2, failure tolerance 2, Regions processed sequentially.
- **C.** Maximum concurrent accounts 40, failure tolerance 40, Regions processed sequentially.
- **D.** Deploy one StackSet per account so that a failure in one account can't affect the others.

<details><summary>Answer</summary>

**Answer: B**

**Why (P6):** Low concurrency limits how many accounts are changing at once; failure tolerance stops the operation after the allowed number of failures; sequential Regions confine damage to one Region at a time.

- **A** — wrong: maximum blast radius. Everything changes at once.
- **B** — correct: progressive rollout with an automatic stop.
- **C** — wrong: tolerates every account failing, so it never stops.
- **D** — wrong: 40 StackSets to manage, and nothing coordinates the rollout or stops it.

**Reference:** <https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/stacksets-concepts.html>

</details>

### Q6 · Task 2.1 · Single answer

Application teams need to create their own Amazon RDS databases for new projects. The databases must always use approved engine versions, encryption with a company KMS key, Multi-AZ, and mandatory cost-center tags. The application teams must **not** be given IAM permissions to create RDS, KMS or IAM resources directly.

What should the DevOps engineer implement?

- **A.** An AWS Service Catalog product built from a CloudFormation template that encodes the standards, with a launch constraint role that has the RDS and KMS permissions, a template constraint for allowed values, and TagOptions for the cost-center tag.
- **B.** An SCP that denies `rds:CreateDBInstance` unless the request includes the required parameters, plus `rds:*` permissions for the teams.
- **C.** A shared CloudFormation template in an S3 bucket that teams deploy with their own credentials.
- **D.** A Lambda function that teams invoke with parameters, running with an execution role that has administrator access.

<details><summary>Answer</summary>

**Answer: A**

**Why (P14, P12):** Service Catalog's **launch constraint** provisions with its own role, so end users need only Service Catalog permissions. Template constraints and TagOptions enforce the standards.

- **A** — correct: governed self-service without granting the underlying permissions.
- **B** — wrong: requires granting the teams RDS permissions, which the requirement forbids, and SCP conditions can't express all of these settings.
- **C** — wrong: teams would need full RDS, KMS and IAM permissions and could modify the template.
- **D** — wrong: custom code with an administrator role is a privilege-escalation path.

**Reference:** <https://docs.aws.amazon.com/servicecatalog/latest/adminguide/constraints-launch.html>

</details>

### Q7 · Task 2.1 · Single answer

A company manages 800 Linux servers: 500 EC2 instances and 300 on-premises servers. The CloudWatch agent must be installed on all of them, with a standard configuration. Servers whose agent is removed or reconfigured must return to the standard automatically. Some engineers propose AWS OpsWorks.

Which approach should the DevOps engineer choose?

- **A.** AWS OpsWorks Stacks with a Chef recipe that installs and configures the agent.
- **B.** A one-time Systems Manager Run Command execution that installs and configures the agent on all servers.
- **C.** Systems Manager State Manager associations (hybrid activation for on-premises servers) that install the agent package and apply the configuration stored in Parameter Store on a schedule.
- **D.** A cron job on every server that downloads the agent configuration from S3 every hour.

<details><summary>Answer</summary>

**Answer: C**

**Why (P3):** State Manager keeps **desired state**: associations re-apply on a schedule and report compliance. Hybrid activations bring on-premises servers under Systems Manager.

- **A** — wrong: OpsWorks Stacks reached end of life in May 2024; Systems Manager is AWS's replacement.
- **B** — wrong: a one-off command doesn't keep the state when someone changes it later.
- **C** — correct: continuous, fleet-wide, hybrid, managed.
- **D** — wrong: per-server custom scheduling, no compliance reporting, and it doesn't reinstall a removed agent.

**Reference:** <https://docs.aws.amazon.com/systems-manager/latest/userguide/systems-manager-state.html>

</details>

### Q8 · Task 2.1 · Single answer

A CDK Pipelines pipeline in a tooling account (111111111111) must deploy a CDK application to a new production account (222222222222). The deployment fails because the asset bucket and the deploy roles in the target account don't exist.

What should the DevOps engineer do?

- **A.** Synthesize the template with `cdk synth` and deploy it manually in the production account.
- **B.** Add `AdministratorAccess` to the pipeline's CodeBuild role.
- **C.** Create an IAM user in the production account and store its keys in the pipeline.
- **D.** Run `cdk bootstrap aws://222222222222/<region> --trust 111111111111 --cloudformation-execution-policies <policy-arn>` in the production account.

<details><summary>Answer</summary>

**Answer: D**

**Why (P2, P14):** Bootstrapping creates the asset storage and deploy roles. `--trust` lets the tooling account assume them, and the execution policies bound what CloudFormation may create.

- **A** — wrong: manual and outside the pipeline.
- **B** — wrong: tooling-account permissions don't create roles or buckets in another account.
- **C** — wrong: long-term credentials, against least privilege.
- **D** — correct: the documented cross-account bootstrap.

**Reference:** <https://docs.aws.amazon.com/cdk/v2/guide/bootstrapping.html>

</details>

### Q9 · Task 2.1 · Single answer

A CloudFormation template creates an Amazon RDS instance. Today the master password is a template parameter, and the deployment pipeline passes it as a parameter override. Auditors found the password in the pipeline definition and in the stack's parameters.

What should the DevOps engineer do to provide the password securely?

- **A.** Mark the parameter `NoEcho: true` and keep passing it from the pipeline definition.
- **B.** Store the password in Secrets Manager and reference it in the template with a dynamic reference such as `{{resolve:secretsmanager:prod/db:SecretString:password}}`, or let RDS manage the master password in Secrets Manager.
- **C.** Base64-encode the password in the pipeline definition.
- **D.** Store the password in a plaintext file in the template's S3 bucket and read it with `Fn::Transform`.

<details><summary>Answer</summary>

**Answer: B**

**Why (P11):** Dynamic references resolve the secret at deploy time without storing it in the template, the parameters or the pipeline. RDS-managed master passwords also rotate automatically.

- **A** — wrong: `NoEcho` masks the value in CloudFormation output, but it still sits in the pipeline definition.
- **B** — correct: the secret is fetched, never stored in configuration.
- **C** — wrong: encoding isn't encryption.
- **D** — wrong: a plaintext secret in S3, and a misuse of transforms.

**Reference:** <https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/dynamic-references.html>

</details>

### Q10 · Task 2.2 · Single answer

A security policy says no AWS account in the organization may leave the organization or disable Amazon GuardDuty, including principals with `AdministratorAccess` and the member accounts' root users. A dedicated security-automation role must still be able to manage GuardDuty.

What should the DevOps engineer implement?

- **A.** An SCP attached at the organization root that denies `organizations:LeaveOrganization` and the GuardDuty disable, delete and disassociate actions, with a condition that excludes the security-automation role's ARN.
- **B.** An IAM policy in every account that denies these actions, attached to all users and roles.
- **C.** A permissions boundary on every administrator role in every account.
- **D.** An AWS Config rule that detects when GuardDuty is disabled and sends an email.

<details><summary>Answer</summary>

**Answer: A**

**Why (P2):** SCPs cap every principal in member accounts, including root and administrators, and can't be overridden from inside the account. A condition exempts the automation role.

- **A** — correct: preventive, org-wide, applies to new accounts automatically.
- **B** — wrong: administrators could detach or edit these policies, and root isn't covered.
- **C** — wrong: boundaries don't apply to the root user, and administrators could remove them without other controls.
- **D** — wrong: detective and after the fact; it doesn't prevent anything.

**Reference:** <https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_policies_scps.html>

</details>

### Q11 · Task 2.2 · Single answer

A company plans to create about 10 new AWS accounts per month. Each account must be created in the right OU with standard network settings, centralized logging, SSO access and preventive and detective guardrails, through a request process that the platform team doesn't have to script.

Which solution requires the LEAST development effort?

- **A.** A Step Functions workflow that calls `CreateAccount`, then deploys CloudFormation stacks for networking, logging and access.
- **B.** A CloudFormation template that creates `AWS::Organizations::Account` resources for each requested account.
- **C.** Set up an AWS Control Tower landing zone and use Account Factory to provision accounts into the target OUs, with controls enabled on those OUs.
- **D.** A shell script, run by an administrator, that creates accounts with the CLI and then enables services one by one.

<details><summary>Answer</summary>

**Answer: C**

**Why (P13, P12):** Control Tower provides the landing zone (log archive, audit, IAM Identity Center), controls per OU, and **Account Factory** for governed account vending, all managed.

- **A** — wrong: works, but you build and maintain the whole vending machine yourself.
- **B** — wrong: creates accounts without the baseline, guardrails or access setup.
- **C** — correct: managed account vending with governance built in.
- **D** — wrong: manual and error-prone.

**Reference:** <https://docs.aws.amazon.com/controltower/latest/userguide/account-factory.html>

</details>

### Q12 · Task 2.2 · Select TWO

The security team works from a dedicated security account. It must manage Amazon GuardDuty and AWS Security Hub for all 60 accounts in the organization, including accounts created in the future, without using the management account for daily work.

Which combination of steps meets these requirements? (Select TWO.)

- **A.** From the management account, register the security account as the delegated administrator for GuardDuty and Security Hub.
- **B.** From the security account, send invitations to all 60 accounts and ask each account owner to accept them.
- **C.** In the delegated administrator account, turn on auto-enable for new organization accounts in GuardDuty, and use Security Hub central configuration to enable it in all accounts and Regions.
- **D.** Create the `OrganizationAccountAccessRole` in every account and give the security team permission to assume it.
- **E.** Deploy a GuardDuty detector and Security Hub to every account with a StackSet and update it when new accounts are created.

<details><summary>Answer</summary>

**Answer: A, C**

**Why (P13):** Delegated administration moves daily management out of the management account. Org-level auto-enable and central configuration cover current and future accounts.

- **A** — correct: the delegated admin is the prerequisite.
- **B** — wrong: invitations are the legacy, manual method, and they don't cover new accounts automatically.
- **C** — correct: automatic coverage of existing and new accounts.
- **D** — wrong: gives broad access to every account and still requires per-account work.
- **E** — wrong: possible, but more effort than native organization integration, and the member/administrator relationship still needs handling.

**Reference:** <https://docs.aws.amazon.com/guardduty/latest/ug/guardduty_organizations.html>

</details>

### Q13 · Task 2.2 · Single answer

A developer in a member account has the `AdministratorAccess` managed policy. They can launch EC2 instances in `eu-west-1`, but every API call in `ap-south-1` fails with an explicit-deny access-denied error. No permissions boundary or session policy is involved.

What is the MOST likely cause?

- **A.** The developer's IAM policy doesn't include `ec2:*` for `ap-south-1`.
- **B.** The account has reached its EC2 instance quota in `ap-south-1`.
- **C.** `ap-south-1` is an opt-in Region that needs a service-linked role.
- **D.** An SCP attached to the account or one of its parent OUs denies actions when `aws:RequestedRegion` is outside an approved list.

<details><summary>Answer</summary>

**Answer: D**

**Why (P2):** An **explicit deny** despite administrator permissions points to a guardrail above IAM. A Region-restriction SCP is the classic case.

- **A** — wrong: `AdministratorAccess` allows all actions in all Regions, and a missing allow gives an implicit deny, not an explicit one.
- **B** — wrong: quota errors are `InstanceLimitExceeded`, not access denied.
- **C** — wrong: a disabled opt-in Region gives a different error, and no service-linked role is involved.
- **D** — correct: check the SCPs on every level from the root to the account.

**Reference:** <https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_policies_scps_examples_general.html>

</details>

### Q14 · Task 2.2 · Single answer

A central S3 bucket in a shared-services account holds deployment artifacts. Every account in the organization, including future ones, must be able to read the artifacts. Accounts outside the organization must not. The account list changes every month.

How should the bucket policy grant access with the LEAST maintenance?

- **A.** List every account ID as a principal and update the policy when accounts are added.
- **B.** Allow `s3:GetObject` to `Principal: "*"` with a condition that `aws:PrincipalOrgID` equals the organization ID.
- **C.** Make the bucket public and rely on obscure object names.
- **D.** Create an IAM user in the shared-services account and distribute its access keys to all accounts.

<details><summary>Answer</summary>

**Answer: B**

**Why (P2, P13):** `aws:PrincipalOrgID` matches any principal from any account in the organization, so new accounts are included automatically.

- **A** — wrong: constant maintenance, and you'd hit policy size limits eventually.
- **B** — correct: an organization-scoped grant with zero maintenance. (Readers in other accounts also need an IAM allow, and KMS access if the objects use a customer managed key.)
- **C** — wrong: exposes the artifacts to the world.
- **D** — wrong: long-term shared credentials.

**Reference:** <https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_policies_condition-keys.html#condition-keys-principalorgid>

</details>

### Q15 · Task 2.3 · Single answer

300 Amazon Linux instances must receive security patches every Sunday at 02:00 UTC, reboot if required, and show their patch compliance in one place. Critical patches must be approved automatically 3 days after release.

What should the DevOps engineer configure?

- **A.** A cron job on each instance that runs `dnf update -y` on Sunday at 02:00.
- **B.** An EC2 Image Builder pipeline that rebuilds the AMI every Sunday.
- **C.** A custom patch baseline that auto-approves critical security patches after 3 days, a patch group tag on the instances, and a maintenance window on Sunday 02:00 that runs `AWS-RunPatchBaseline` with the `Install` operation.
- **D.** A Systems Manager Run Command execution of `AWS-RunPatchBaseline` with the `Scan` operation every Sunday.

<details><summary>Answer</summary>

**Answer: C**

**Why (P3, P12):** Patch Manager does baseline-driven approval (including auto-approval delays), scheduled installation in maintenance windows, and compliance reporting.

- **A** — wrong: no approval rules, no compliance view, and unmanaged per-instance configuration.
- **B** — wrong: a new AMI doesn't patch the 300 running instances unless they're replaced, which the question doesn't describe.
- **C** — correct: baseline + patch group + window + `Install`.
- **D** — wrong: `Scan` only reports; it doesn't install.

**Reference:** <https://docs.aws.amazon.com/systems-manager/latest/userguide/patch-manager.html>

</details>

### Q16 · Task 2.3 · Single answer

An auditor needs a weekly report of which instances, across 30 AWS accounts and 4 Regions, have a particular version of OpenSSL installed. The DevOps team wants to query the data with SQL from one place, without logging in to each account.

What is the MOST operationally efficient solution?

- **A.** Enable Systems Manager Inventory on the instances, create a Resource Data Sync in each account and Region that writes to a central S3 bucket, and query the data with Amazon Athena.
- **B.** Run a Run Command every week that prints the OpenSSL version, and collect the outputs by hand.
- **C.** Write a Lambda function that SSHes into every instance and records the version in DynamoDB.
- **D.** Enable an AWS Config aggregator and query the instances' installed packages with Config advanced queries.

<details><summary>Answer</summary>

**Answer: A**

**Why (P12, P13):** Inventory collects installed software; Resource Data Sync centralizes it across accounts and Regions in S3, where Athena queries it.

- **A** — correct: managed collection, centralized, SQL-queryable.
- **B** — wrong: manual aggregation.
- **C** — wrong: custom code, SSH access and key management.
- **D** — wrong: Config records resource configuration. It can record SSM inventory as `AWS::SSM::ManagedInstanceInventory`, but the documented pattern for software-inventory reporting across accounts is Resource Data Sync + Athena.

**Reference:** <https://docs.aws.amazon.com/systems-manager/latest/userguide/inventory-create-resource-data-sync.html>

</details>

### Q17 · Task 2.3 · Select TWO

Across all accounts in an organization, any security group rule that allows inbound SSH (port 22) from `0.0.0.0/0` must be detected and removed automatically within minutes. Security wants this to also apply to accounts created later.

Which combination of steps meets these requirements with the LEAST custom code? (Select TWO.)

- **A.** Enable Amazon GuardDuty and remove the rules mentioned in its findings manually.
- **B.** Schedule a Lambda function every 5 minutes that lists all security groups in all accounts and revokes matching rules.
- **C.** Deploy the AWS Config managed rule `restricted-ssh` org-wide (for example through an organization conformance pack).
- **D.** Enable Amazon Inspector network reachability findings.
- **E.** Attach an automatic remediation to the rule that runs the `AWS-DisablePublicAccessForSecurityGroup` Automation runbook with an appropriate `AutomationAssumeRole`.

<details><summary>Answer</summary>

**Answer: C, E**

**Why (P3, P12, P13):** A Config managed rule detects the non-compliant state when it's created. Automatic remediation with an AWS-provided runbook fixes it, and organization deployment covers future accounts.

- **A** — wrong: GuardDuty detects threats, not configuration, and the fix is manual.
- **B** — wrong: polling with custom code.
- **C** — correct: detection everywhere, including new accounts.
- **D** — wrong: reports exposure but doesn't remediate.
- **E** — correct: the managed fix, run automatically.

**Reference:** <https://docs.aws.amazon.com/config/latest/developerguide/remediation.html>

</details>

### Q18 · Task 2.3 · Single answer

An engineer needs to run a configuration script once on 1,000 managed instances tagged `env=prod`. No more than 50 instances may run it at the same time, and the operation must stop if more than 5% of the targets fail.

What should the engineer use?

- **A.** A State Manager association that runs every 30 minutes.
- **B.** A CloudFormation stack update that replaces the instances.
- **C.** An SSH loop from a bastion host that runs the script sequentially.
- **D.** Systems Manager Run Command targeting the `env=prod` tag, with a concurrency of 50 and an error threshold of 5%.

<details><summary>Answer</summary>

**Answer: D**

**Why (P12):** Run Command is the one-off fleet execution tool, with built-in **rate control** for concurrency and error thresholds.

- **A** — wrong: for continuous desired state, not a one-time run, and it would keep re-running.
- **B** — wrong: disproportionate for a script.
- **C** — wrong: manual, slow, needs SSH, and has no automatic stop on errors.
- **D** — correct: targeted by tag, rate-controlled, auditable.

**Reference:** <https://docs.aws.amazon.com/systems-manager/latest/userguide/send-commands-velocity.html>

</details>

### Q19 · Task 2.3 · Single answer

An operations procedure for an application has five steps:
1. Remove an instance from its target group.
2. Wait for connections to drain.
3. Run a maintenance script.
4. Have an operations lead approve the result.
5. Return the instance to service.

The team wants the procedure automated, auditable and reusable for any instance ID.

What should the DevOps engineer build?

- **A.** A wiki page with the CLI commands for each step.
- **B.** A Systems Manager Automation runbook with steps that call the ELB APIs (`aws:executeAwsApi`), wait (`aws:sleep`), run the script (`aws:runCommand`), request approval (`aws:approve`), and re-register the instance, taking the instance ID as a parameter.
- **C.** A CloudWatch alarm whose action runs the maintenance script.
- **D.** A cron job on the instance that performs the steps at night.

<details><summary>Answer</summary>

**Answer: B**

**Why (P12, P3):** Automation runbooks orchestrate multi-step operations across AWS APIs and instances, with built-in approval steps, parameters and execution history.

- **A** — wrong: a manual procedure with no audit trail.
- **B** — correct: codified, parameterized, approved and auditable.
- **C** — wrong: alarms react to metrics. They can't orchestrate multi-step procedures with approvals.
- **D** — wrong: an instance can't reliably drain itself from its target group and wait for a human approval.

**Reference:** <https://docs.aws.amazon.com/systems-manager/latest/userguide/automation-actions.html>

</details>

### Q20 · Task 2.3 · Select TWO

A company wants every EC2 instance in its accounts to be manageable by Systems Manager: Session Manager, Patch Manager and Inventory. That includes instances launched by teams who forget to attach an instance profile. The instances run in private subnets with no NAT gateway. The AMIs already include the SSM Agent.

Which combination of steps meets these requirements? (Select TWO.)

- **A.** Open inbound port 22 from the corporate network so that Systems Manager can connect.
- **B.** Enable Default Host Management Configuration in each account and Region, so instances get Systems Manager permissions without an instance profile (IMDSv2 required).
- **C.** Create an IAM user with Systems Manager permissions and put its access keys in the AMI.
- **D.** Create interface VPC endpoints for `ssm`, `ssmmessages` and `ec2messages` in the VPCs.
- **E.** Install the SSM Agent again from user data on every launch.

<details><summary>Answer</summary>

**Answer: B, D**

**Why (P7, P14):** Being a managed node needs agent + permissions + network path. DHMC supplies the permissions account-wide, and the interface endpoints supply a private network path.

- **A** — wrong: Systems Manager doesn't connect inbound; the agent connects out to the endpoints.
- **B** — correct: removes the dependency on teams attaching instance profiles.
- **C** — wrong: long-term credentials baked into an image.
- **D** — correct: private connectivity without NAT.
- **E** — wrong: the agent is already present. The missing pieces are permissions and network.

**Reference:** <https://docs.aws.amazon.com/systems-manager/latest/userguide/fleet-manager-default-host-management-configuration.html>

</details>
