# Domain 2 · 04 · AWS Systems Manager and AWS Config: Automation at Scale

> **Exam tasks:** 2.3 (inventory, configuration and patch automation; Lambda/Step Functions automation; desired state; software compliance), 4.3 (Config remediation; agents), 5.2 (configuration changes in response to events). **Principles:** P1 (events), P3 (desired state), P12 (managed features).

Systems Manager **acts on** fleets. AWS Config **observes and judges** resource configuration. The exam's favourite combination joins them: a **Config rule detects** non-compliance and an **SSM Automation runbook remediates** it.

---

## 1. Systems Manager foundations: becoming a "managed node"

For any SSM capability to work on a machine, three things must be true:
1. **The SSM Agent is running.** It's preinstalled on Amazon Linux, Ubuntu, Windows and other AWS-provided AMIs.
2. **The node has permission to talk to SSM:**
   * an **instance profile** with `AmazonSSMManagedInstanceCore`; or
   * **Default Host Management Configuration** (an account-level setting that lets EC2 instances register without an instance profile); or
   * for **on-premises** and other clouds, a **hybrid activation** (an activation code and ID), which gives `mi-` node IDs.
3. **The node can reach the SSM endpoints:**
   * through the internet (NAT); or
   * **through VPC interface endpoints** `ssm`, `ssmmessages` and `ec2messages` (plus `s3` and `logs` endpoints if output goes there).

"The instance doesn't show up in Fleet Manager" is a failure of one of these three. Check them in that order.

## 2. The capabilities and when each one is the answer

| Capability | What it does | Choose it when the question says |
|---|---|---|
| **Run Command** | Runs a Command document (e.g. `AWS-RunShellScript`, `AWS-RunPowerShellScript`) on targets selected by IDs, **tags** or resource groups, with **rate control**: max concurrency and **error threshold** | "Run a one-time command on 500 instances; stop if more than 5% fail" |
| **State Manager** | **Associations** that keep nodes in a defined state on a schedule (e.g. install and configure the CloudWatch agent; ensure a service runs; join a domain); reports compliance | "Ensure continuously", "every new instance must automatically get X", desired-state configuration (P3) |
| **Automation** | Multi-step **runbooks** (Automation documents) that call AWS APIs (`aws:executeAwsApi`), run commands (`aws:runCommand`), branch, wait, **ask for approval** (`aws:approve`) and run scripts (`aws:executeScript`); rate control; **multi-account and multi-Region** execution | "Automate a multi-step operational procedure", golden-AMI creation, **Config remediation**, EventBridge-triggered responses |
| **Patch Manager** | Scans for or installs patches according to **patch baselines** (predefined or custom, with auto-approval delays and approved/rejected lists); **patch groups** by tag; runs `AWS-RunPatchBaseline` (Scan or Install) in **maintenance windows**, or by **patch policies** (Quick Setup) across accounts and Regions | "Patch the fleet automatically in a weekly window", "report patch compliance" |
| **Maintenance Windows** | Time windows with registered targets and tasks (Run Command, Automation, Lambda, Step Functions) | "Changes only during approved windows" |
| **Inventory** | Collects OS, application, network, file and Windows-registry data from nodes; **Resource Data Sync** writes it to S3 across accounts and Regions, for Athena or QuickSight | "Report which instances run software version X across all accounts" |
| **Session Manager** | Interactive shell or port forwarding with **no SSH keys, no open inbound ports, no bastion**; IAM-controlled; sessions logged to S3 or CloudWatch Logs; KMS-encrypted | "Remove bastion hosts", "audit all interactive sessions" |
| **Parameter Store** | Hierarchical configuration and secrets (`SecureString` with KMS); versions and labels; the advanced tier adds larger values and **parameter policies** (expiration notifications) | Configuration values; the AMI ID public parameters `/aws/service/ami-amazon-linux-latest/...` |
| **Distributor** | Packages software (including the CloudWatch agent and CodeDeploy agent packages) for install and update with Run Command or State Manager | "Install and keep the agent updated on all nodes" |
| **Fleet Manager** | Console UI for nodes: file system, performance, users | — |
| **OpsCenter** | **OpsItems** (operational issues) created from EventBridge rules or CloudWatch alarms, with related resources and runbooks attached | Central triage of operational issues. AWS's recommended replacement for Incident Manager use cases |
| **Explorer** | Org-wide operational data dashboard (OpsData) | Overview across accounts |
| **Quick Setup** | Org-wide configuration of common setups (host management, patch policies, DHMC, Config recording) through StackSets underneath | "Configure SSM best practices across the organization with the least effort" |
| **Compliance** | Patch and State Manager association compliance data, aggregated | Compliance reporting |
| **Incident Manager / Change Manager** | Incident response plans and on-call; change requests with approvals | **Maintenance:** closed to new customers since 2025-11-07. Recognize them; OpsCenter is the incident-tracking alternative |

### 2.1 Patch Manager details the exam probes

* **Predefined baselines** (e.g. `AWS-AmazonLinux2023DefaultPatchBaseline`) auto-approve security patches after a delay. **Custom baselines** set approval rules (classification, severity, **auto-approve after N days**), explicit approved/rejected patches, and compliance severity.
* **Patch groups:** the tag key `Patch Group` (or `PatchGroup`) on instances maps them to a baseline. One group = one baseline per OS.
* **Operation `Scan` vs `Install`:** scan only reports compliance; install applies patches and **reboots if needed** (`RebootIfNeeded` by default, configurable).
* **Patch policies** (Quick Setup) define scan and install schedules across accounts and Regions in one place.
* **Patching a golden AMI** (immutable, with EC2 Image Builder) vs **patching running instances** (mutable, Patch Manager). Read which one the question wants.

### 2.2 Automation runbook anatomy

```yaml
schemaVersion: "0.3"
description: Stop non-compliant instances after an approval
assumeRole: "{{ AutomationAssumeRole }}"
parameters:
  InstanceId:
    type: String
  AutomationAssumeRole:
    type: String
mainSteps:
  - name: approve
    action: aws:approve
    inputs:
      Approvers: ["arn:aws:iam::111122223333:role/OpsLead"]
      MinRequiredApprovals: 1
  - name: stopInstance
    action: aws:changeInstanceState
    inputs:
      InstanceIds: ["{{ InstanceId }}"]
      DesiredState: stopped
```

* **`AutomationAssumeRole`** is the IAM role the runbook runs as. Remediation from Config **requires** it, and the role must trust `ssm.amazonaws.com`.
* **AWS-provided runbooks** (`AWS-*`, `AWSConfigRemediation-*`, `AWSSupport-*`) cover common fixes: `AWS-DisablePublicAccessForSecurityGroup`, `AWS-ConfigureS3BucketVersioning`, `AWS-EnableS3BucketEncryption`, `AWSConfigRemediation-EnableCloudTrailLogFileValidation`, `AWS-UpdateLinuxAmi`, `AWSSupport-ExecuteEC2Rescue`, and many more. **Check for a managed runbook before writing a Lambda** (P12).

---

## 3. AWS Config

### 3.1 How it works

* **Configuration recorder:** records **configuration items** (CIs) for supported resource types, either all types or a selected set. Recording frequency is **continuous** or **daily (periodic)**. There is one recorder per account per Region.
* **Delivery channel:** configuration history and snapshots go to **S3**; notifications go to **SNS**. Config events also go to **EventBridge**.
* **Timeline:** for each resource, Config shows its configuration over time, its **relationships** (an instance → its ENI, SG, volume), and **the CloudTrail events that changed it**. Together these answer "who changed this, and what was it before?"
* **Advanced queries:** SQL over current configuration state, across accounts with an aggregator.

### 3.2 Rules

| Aspect | Options |
|---|---|
| Rule type | **Managed** (hundreds, e.g. `restricted-ssh`, `s3-bucket-public-read-prohibited`, `encrypted-volumes`, `required-tags`, `cloudtrail-enabled`, `iam-root-access-key-check`, `approved-amis-by-id`, `ec2-managedinstance-patch-compliance-status-check`, `cloudformation-stack-drift-detection-check`) or **custom** (a **Lambda** function, or **Guard** policy-as-code) |
| Trigger | **Configuration change** (evaluated when a resource in scope changes) or **periodic** (every 1, 3, 6, 12 or 24 hours) |
| Evaluation mode | **Detective** (deployed resources) and/or **proactive** (resource configurations evaluated *before* deployment, e.g. by CloudFormation Hooks or the API) |
| Scope | Resource types, tags or specific IDs |

Compliance results: `COMPLIANT`, `NON_COMPLIANT`, `NOT_APPLICABLE`, `INSUFFICIENT_DATA`. Changes in compliance emit **`Config Rules Compliance Change`** events to EventBridge.

### 3.3 Remediation

* **Remediation actions** attach an **SSM Automation document** to a rule.
  * **Manual:** someone clicks "Remediate".
  * **Automatic:** runs for each non-compliant resource, with retries (`MaximumAutomaticAttempts`, `RetryAttemptSeconds`).
* Parameters map **`RESOURCE_ID`** from the non-compliant resource into the document (e.g. `BucketName`, `GroupId`), plus static values such as the `AutomationAssumeRole` ARN.
* **Org-wide:** deploy rules and remediations with **conformance packs** at the organization level, or with StackSets.

### 3.4 Conformance packs and aggregators

| Feature | What it is | Common confusion |
|---|---|---|
| **Conformance pack** | A YAML bundle of Config rules **plus remediation actions**, deployed as one unit to an account, or **org-wide from the management or delegated-admin account**. Sample packs map to frameworks (CIS, PCI DSS, NIST, Operational Best Practices for…) | It's the deployment unit for "apply this set of compliance checks everywhere" |
| **Aggregator** | A **read-only, multi-account, multi-Region view** of configuration and compliance data in one account (authorization per source account, or **organization-wide**) | **Aggregators don't deploy or evaluate rules** in source accounts. They only collect results |

## 4. Lambda and Step Functions for complex automation

Use them when no managed capability fits (P12).

| Use **Lambda** when | Use **Step Functions** when |
|---|---|
| One reaction to one event; under 15 minutes; simple logic | Multiple steps, **waits** (`Wait` state, up to a year), **retries with backoff** and catch (`Retry`/`Catch`), human approval (**callback with a task token**), parallel branches, **`Map` over many items** (e.g. every account in the organization) |
| An EventBridge target that tags, notifies or quarantines | Orchestrating Lambda, SSM, ECS tasks and SDK integrations (direct calls to 200+ services, no Lambda glue) |

Design rules:
* **Idempotency:** events can arrive twice (P9).
* **Least-privilege execution roles.**
* **Cross-account:** the automation **assumes a role** in each target account.
* **Failures:** a DLQ or on-failure destination for async Lambda invocations.

## 5. Requirement → answer

| Requirement | Answer |
|---|---|
| Keep the CloudWatch agent installed and configured on all current and future instances | State Manager association (`AWS-ConfigureAWSPackage` for the agent + `AmazonCloudWatch-ManageAgent` with the configuration in Parameter Store), targeted by tag |
| Patch all Linux instances every Sunday 02:00 and report compliance | Patch baseline + patch group tag + maintenance window running `AWS-RunPatchBaseline` (Install), or a Quick Setup patch policy |
| Find all instances running a vulnerable package version in 40 accounts | SSM Inventory + Resource Data Sync to a central S3 bucket + Athena (or Inspector for CVEs) |
| Automatically close SSH open to the world | Config `restricted-ssh` + automatic remediation `AWS-DisablePublicAccessForSecurityGroup` |
| Remove bastion hosts while keeping audited shell access | Session Manager + session logging to S3 or CloudWatch Logs + IAM policies |
| Run a multi-step operational procedure with a manager's approval | SSM Automation runbook with `aws:approve` |
| Apply the same Config rules and remediations to all accounts | An organization conformance pack from the delegated admin |
| See the compliance of all accounts and Regions in one place | A Config aggregator (organization) |

## 6. Exam traps

* **An aggregator ≠ enforcement.** It doesn't deploy rules.
* **Config detects, and remediation is a separate configuration.** "Detect and automatically fix" needs both the rule and an automatic remediation with an `AutomationAssumeRole`.
* **Run Command is one-off; State Manager is continuous.** "Every new instance" means State Manager (or user data, or the AMI).
* **An instance missing from SSM:** check the agent, the role or DHMC, and the network path (endpoints or NAT).
* **Patch Manager `Scan` doesn't install.**
* **Session Manager doesn't need port 22 open** or a key pair. Options that open SSH "for Session Manager" are wrong.
* **OpsWorks** in an option means managed Chef/Puppet, which is retired. The modern equivalent is State Manager or Automation.

## 7. Hands-on lab: Config rule + automatic remediation (about 30 minutes)

**Prerequisite:** AWS Config recording is on in the Region (console → AWS Config → *1-click setup*).

[labs/lab-05-config-auto-remediation.yaml](labs/lab-05-config-auto-remediation.yaml) creates:
* the managed rule `s3-bucket-versioning-enabled`;
* an **automatic remediation** with `AWS-ConfigureS3BucketVersioning`;
* the remediation role;
* a deliberately **unversioned** test bucket.

```bash
aws cloudformation deploy --stack-name dop-lab-05 \
  --template-file labs/lab-05-config-auto-remediation.yaml --capabilities CAPABILITY_IAM
# Within a few minutes the rule flags the test bucket NON_COMPLIANT, remediation runs, and
# the bucket shows versioning Enabled:
aws configservice get-compliance-details-by-config-rule --config-rule-name dop-lab-05-s3-versioning
aws s3api get-bucket-versioning --bucket <TestBucket output>
# Tear down: empty the test bucket (all versions), then delete the stack
```

**Observe:**
* The chain: change → CI recorded → rule evaluated → `NON_COMPLIANT` → automation execution (Systems Manager → Automation → executions) → re-evaluated `COMPLIANT`. That is P3 and P12 together.

## References

* Setting up Systems Manager managed nodes — <https://docs.aws.amazon.com/systems-manager/latest/userguide/systems-manager-setting-up-ec2.html>
* Default Host Management Configuration — <https://docs.aws.amazon.com/systems-manager/latest/userguide/fleet-manager-default-host-management-configuration.html>
* State Manager — <https://docs.aws.amazon.com/systems-manager/latest/userguide/systems-manager-state.html>
* Patch Manager — <https://docs.aws.amazon.com/systems-manager/latest/userguide/patch-manager.html>
* Patch policies (Quick Setup) — <https://docs.aws.amazon.com/systems-manager/latest/userguide/quick-setup-patch-manager.html>
* Automation runbook actions — <https://docs.aws.amazon.com/systems-manager/latest/userguide/automation-actions.html>
* Resource Data Sync — <https://docs.aws.amazon.com/systems-manager/latest/userguide/inventory-create-resource-data-sync.html>
* AWS Config rules — <https://docs.aws.amazon.com/config/latest/developerguide/evaluate-config.html>
* Remediating non-compliant resources — <https://docs.aws.amazon.com/config/latest/developerguide/remediation.html>
* Conformance packs — <https://docs.aws.amazon.com/config/latest/developerguide/conformance-packs.html>
* Multi-account multi-Region aggregation — <https://docs.aws.amazon.com/config/latest/developerguide/aggregate-data.html>
