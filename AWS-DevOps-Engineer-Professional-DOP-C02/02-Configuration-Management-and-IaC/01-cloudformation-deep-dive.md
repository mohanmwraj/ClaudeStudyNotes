# Domain 2 · 01 · AWS CloudFormation Deep Dive

> **Exam tasks:** 2.1 (IaC templates, StackSets, reusable components, change management), 5.3 (failed CloudFormation deployments), 6.3 (drift detection). **Principles:** P3 (desired state and drift), P4 (replacement), P6 (progressive rollout), P11 (secrets).

CloudFormation is the IaC engine underneath SAM, the CDK and Service Catalog. They all synthesize CloudFormation templates. Once you understand how CloudFormation **creates, updates, rolls back and deletes**, most IaC questions answer themselves.

---

## 1. Mental model: a stack is a transaction over a dependency graph

* A **template** declares resources. CloudFormation builds a **dependency graph** from `Ref`, `Fn::GetAtt`, `Fn::Sub` references and explicit `DependsOn`, and creates independent resources in parallel.
* A **stack** is the unit of lifecycle. Create, update and delete are **all-or-nothing** by default: if any resource fails, CloudFormation **rolls back** to the last stable state.
* The template is the **desired state** (P3). Changing a resource outside CloudFormation causes **drift**; the next update may overwrite it or fail on it.

## 2. Template anatomy (the parts the exam uses)

| Section | Use | Exam detail |
|---|---|---|
| `Parameters` | Inputs | AWS-specific types validate input (`AWS::EC2::KeyPair::KeyName`, `AWS::EC2::Subnet::Id`). **SSM parameter types** (`AWS::SSM::Parameter::Value<AWS::EC2::Image::Id>` with default `/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64`) always resolve the latest AMI. `NoEcho: true` hides values in the console and API but **not** in places you echo them yourself |
| `Mappings` | Static lookup tables (e.g. per-Region values) | `Fn::FindInMap` |
| `Conditions` | Create resources or properties conditionally | `Fn::If`, `AWS::NoValue` to omit a property |
| `Resources` | The only mandatory section | Resource attributes (§4) control lifecycle |
| `Outputs` | Values, and **`Export`** for cross-stack references | `Fn::ImportValue` in other stacks |
| `Transform` | Macros: `AWS::Serverless-2016-10-31` (SAM), `AWS::Include`, custom macros | Needs `CAPABILITY_AUTO_EXPAND` when deploying |
| `Metadata` | `AWS::CloudFormation::Init` for `cfn-init` (§5) | |
| `Rules` | Validate parameter combinations before create or update | |

**Dynamic references** pull values at deploy time without putting them in the template:
* `{{resolve:ssm:/path/param}}`
* `{{resolve:ssm-secure:/path/secret}}` (supported properties only)
* `{{resolve:secretsmanager:MySecret:SecretString:password}}`

This is the correct way to give an RDS master password to a template (or use RDS `ManageMasterUserPassword`, which stores the password in Secrets Manager).

## 3. Updates: change sets, update behaviours, stack policies

**Every property change has an update behaviour,** documented per property:
* **No interruption.**
* **Some interruption:** for example, an EC2 instance type change stops and starts the instance.
* **Replacement:** a new physical resource is created, references move to it, and the old one is deleted. For example, changing an RDS `DBInstanceIdentifier` or a DynamoDB key schema.

**Replacement of stateful resources is how data gets lost.**

| Control | What it does | Use when |
|---|---|---|
| **Change set** | Previews exactly what an update will do, including **`Replacement: True`**, before executing | Always for production; the pipeline pattern is `CHANGE_SET_REPLACE` → manual approval → `CHANGE_SET_EXECUTE` |
| **Stack policy** | A JSON policy on the stack that **denies update actions** (`Update:Modify`, `Update:Replace`, `Update:Delete`, `Update:*`) on chosen resources. Once set, everything is protected unless explicitly allowed | "Prevent accidental replacement or deletion of the production database during stack updates" |
| **`DeletionPolicy`** | What happens to the resource when it's **removed from the template or the stack is deleted**: `Delete` (default for most), `Retain`, `Snapshot` (RDS, EBS, ElastiCache, Neptune, Redshift…), `RetainExceptOnCreate` | Keep data when the stack goes away |
| **`UpdateReplacePolicy`** | What happens to the **old** physical resource when an update **replaces** it: `Delete`, `Retain`, `Snapshot` | Keep a snapshot of the old database if a property change forces replacement |
| **Termination protection** | Stack-level: prevents `DeleteStack` | Production stacks |
| **Rollback configuration** | **Rollback triggers:** up to 5 CloudWatch alarms monitored during the operation and for a **monitoring time** (0–180 minutes) afterwards. Any alarm in ALARM → rollback | "Automatically roll back the infrastructure change if the application's error alarm fires within 30 minutes" |

## 4. Resource attributes, the lifecycle levers

| Attribute | Purpose |
|---|---|
| `DependsOn` | Force creation order when there's no reference. Classic case: an EC2 instance that needs internet access must depend on the VPC gateway attachment |
| `CreationPolicy` | Wait for **N success signals** within a **timeout** before marking an EC2 instance or ASG `CREATE_COMPLETE` |
| `UpdatePolicy` | How updates roll out for ASGs, Lambda aliases and some other types (§5.2) |
| `DeletionPolicy`, `UpdateReplacePolicy` | §3 |
| `Condition` | Create the resource only if the condition is true |

## 5. Bootstrapping EC2 and Auto Scaling groups

### 5.1 `cfn-init`, `cfn-signal`, `cfn-hup`

* **User data** runs once at first boot. It's the place to call the helper scripts.
* **`cfn-init`** reads `AWS::CloudFormation::Init` metadata and applies it in order: packages → groups → users → sources → files → commands → services. **configSets** order several configs.
* **`cfn-signal`** sends success or failure (the exit code of `cfn-init`) to CloudFormation for a `CreationPolicy` or `WaitCondition`.
* **`cfn-hup`** is a daemon that watches the metadata for changes and re-runs actions. It lets a **stack update change instance configuration without replacing the instance**.

```yaml
WebServer:
  Type: AWS::EC2::Instance
  CreationPolicy:
    ResourceSignal:
      Count: 1
      Timeout: PT10M
  Metadata:
    AWS::CloudFormation::Init:
      config:
        packages:
          yum:                 # cfn-init package managers: apt, msi, python, rpm, rubygems, yum
            httpd: []
        files:
          /var/www/html/index.html:
            content: "<h1>Deployed by cfn-init</h1>"
        services:
          systemd:
            httpd:
              enabled: true
              ensureRunning: true
  Properties:
    ImageId: !Ref LatestAmiId
    InstanceType: t3.micro
    UserData:
      Fn::Base64: !Sub |
        #!/bin/bash
        dnf install -y aws-cfn-bootstrap
        /opt/aws/bin/cfn-init -v --stack ${AWS::StackName} --resource WebServer --region ${AWS::Region}
        /opt/aws/bin/cfn-signal -e $? --stack ${AWS::StackName} --resource WebServer --region ${AWS::Region}
```

**"Did not receive the required number of signals" — the causes, in order of likelihood:**
1. `cfn-init` failed (read `/var/log/cfn-init.log` and `/var/log/cloud-init-output.log`).
2. The instance can't reach the CloudFormation endpoint: a private subnet with no NAT gateway and no CloudFormation VPC endpoint.
3. The `--resource` name doesn't match the logical ID.
4. The timeout is too short.
5. The helper scripts aren't installed on the AMI.

**`WaitCondition` + `WaitConditionHandle`** is the older, generic mechanism. An external process (not necessarily the instance) signals a presigned URL. Prefer `CreationPolicy` for EC2 and ASGs.

### 5.2 `UpdatePolicy` for Auto Scaling groups

| Policy | Behaviour | Rollback |
|---|---|---|
| `AutoScalingRollingUpdate` | Replaces instances in batches (`MaxBatchSize`), keeping `MinInstancesInService`; with `WaitOnResourceSignals: true` + `PauseTime`, each batch must signal success | Failed signals → stack update rolls back (instances already replaced are replaced again) |
| `AutoScalingReplacingUpdate` (`WillReplace: true`) | Creates a **whole new ASG**; when it's healthy (signals, if configured), deletes the old one | The old ASG is still there, so rollback is fast and clean (immutable, P4) |
| `AutoScalingScheduledAction` (`IgnoreUnmodifiedGroupSizeProperties: true`) | Stops stack updates from resetting min/max/desired that scheduled actions changed | — |

Launch template changes only affect **new** instances. To roll existing instances you need one of these update policies, or an **ASG instance refresh** (see [03-Resilient-Cloud-Solutions/02](../03-Resilient-Cloud-Solutions/02-scalability-and-auto-scaling.md)).

## 6. Extending CloudFormation

| Mechanism | What it is | Use when |
|---|---|---|
| **Custom resource** (`Custom::Name` with a `ServiceToken`) | CloudFormation sends Create/Update/Delete requests to a **Lambda function** (or SNS topic). The handler **must** PUT a response to the presigned S3 URL | Logic or resources CloudFormation doesn't support: look up a value, empty an S3 bucket on delete, call a third-party API |
| **Registry resource types** | First-class resource types (`MyOrg::Service::Thing`) with schema and handlers, published privately or used from public third parties | Reusable, typed extensions across many stacks |
| **Modules** | Reusable template fragments registered as `MyOrg::Pattern::Name::MODULE`; expanded into the template | Standard patterns, e.g. "a compliant S3 bucket", reused by many teams |
| **Macros** | A Lambda that transforms the template before processing (`Transform:`) | Template generation and shorthand. SAM is AWS's macro |
| **Hooks** | Proactive validation run **before** resources are created or updated; can **fail** the operation (e.g. a Guard rule: "all S3 buckets encrypted") | Compliance enforcement at deploy time, even outside pipelines |

**Custom-resource failure modes:**
* If the Lambda **never responds** (crash, timeout, or missing response code), the stack waits for the custom resource **timeout** (one hour by default) before failing. The same hang can happen again during rollback.
* Always send a response in a `try/finally`, and handle `Delete` (including deletes during rollback of a failed create).
* Returning a **different `PhysicalResourceId`** on Update makes CloudFormation treat it as a replacement and send a `Delete` for the old ID afterwards.

## 7. Composing stacks

| Pattern | Coupling | Notes |
|---|---|---|
| **Nested stacks** (`AWS::CloudFormation::Stack`) | Parent owns children; deployed and updated together | Reuse a component template; get past the per-template resource limit. Pass values through parameters and outputs |
| **Cross-stack references** (`Export` / `Fn::ImportValue`) | Loose, but **locked**: you can't delete or change an export while any stack imports it | Network stack exports VPC and subnet IDs; app stacks import them. Exports are per Region |
| **SSM Parameter Store** | Loosest: the producer writes a parameter; consumers read it with an SSM parameter type or dynamic reference | Changing the value doesn't block updates; consumers pick it up at their next update |

## 8. StackSets: one template, many accounts and Regions

| Concept | Self-managed permissions | Service-managed permissions |
|---|---|---|
| Prerequisite | You create `AWSCloudFormationStackSetAdministrationRole` in the admin account and `AWSCloudFormationStackSetExecutionRole` in **every** target account | Organizations with **trusted access** for StackSets enabled; CloudFormation creates the roles |
| Targets | Account IDs | **OUs** (or accounts), so all accounts in the OU are covered |
| New accounts | You must add them | **Automatic deployment:** stack instances are created when an account joins the OU, and optionally deleted (or retained) when it leaves |
| Who can administer | The account that owns the roles | The management account or a **delegated administrator** member account |

**Operation preferences** implement progressive rollout (P6):
* **Maximum concurrent accounts** (count or %).
* **Failure tolerance** (count or %): stop the operation once this many accounts fail in a Region.
* **Region concurrency:** sequential or parallel.
* **Region order.**
* The **concurrency mode:** strict failure tolerance, or soft failure tolerance.

Facts:
* With service-managed permissions, the stack set **does not deploy to the management account**, even if it's in a targeted OU.
* **Parameter overrides** per account or Region allow small differences.
* **Drift detection** works on stack sets too.
* Exam pattern: "Deploy an IAM role, Config rule or CloudTrail setting to every existing **and future** account in an OU, with the least effort" → StackSets, **service-managed**, **automatic deployment enabled**. Control Tower uses StackSets underneath.

## 9. Drift detection

* **Detects** differences between the template's **expected** property values and the **actual** ones, for supported resource types and for properties **explicitly set** in the template.
* States: `IN_SYNC`, `MODIFIED`, `DELETED`, `NOT_CHECKED`.
* Run it on demand (console, API), on a schedule, or **continuously** through the AWS Config managed rule `cloudformation-stack-drift-detection-check`, which alerts or remediates.
* **Drift detection doesn't fix anything.** Remediation means updating the template to match and redeploying, or reverting the manual change. **Resource import** brings existing resources under a stack (`IMPORT` change set; the resource needs a `DeletionPolicy`).
* **IaC generator** scans existing resources in an account and produces a template, which is useful for bringing click-ops resources under IaC.

## 10. Troubleshooting stack states (Domain 5.3)

| State / error | Meaning | What to do |
|---|---|---|
| `CREATE_FAILED` → `ROLLBACK_COMPLETE` | The first creation failed and everything was rolled back | Read the stack **events** for the first failure; **delete the stack** before recreating it. A stack in `ROLLBACK_COMPLETE` can't be updated |
| `UPDATE_ROLLBACK_FAILED` | Rollback couldn't restore a resource (e.g. it was changed or deleted outside CloudFormation) | Fix the resource manually, or **`ContinueUpdateRollback`** with **`ResourcesToSkip`** |
| `DELETE_FAILED` | A resource couldn't be deleted (non-empty S3 bucket, an export in use, a security group still attached elsewhere) | Fix the dependency, or delete again **retaining** the failed resource |
| "Did not receive N signals" | CreationPolicy timeout | §5.1 causes |
| `Requires capabilities: [CAPABILITY_NAMED_IAM]` | The template creates IAM resources with custom names (or uses macros → `CAPABILITY_AUTO_EXPAND`) | Acknowledge the capability in the deploy call or pipeline action |
| "Cannot update a stack when a custom-named resource requires replacing" | A replacement would need a second resource with the same physical name | Change the name, or let CloudFormation generate names |
| "Export … cannot be deleted as it is in use by …" | A cross-stack import exists | Remove the importing references first |
| Operation stuck "in progress" for an hour on a custom resource | The handler never responded | Fix the handler; it must always send SUCCESS or FAILED |

Debugging aid: **`--disable-rollback`** on create (or "preserve successfully provisioned resources" on failure) keeps failed resources around so you can inspect them.

## 11. Exam traps

* **`DeletionPolicy` is not the same as `UpdateReplacePolicy`.** Removal or deletion of the stack vs replacement during an update. Protecting a database fully needs both, or a stack policy.
* **A stack policy doesn't stop stack deletion** (use termination protection), and doesn't stop changes made outside CloudFormation (use IAM or SCPs).
* **Change sets show the effect; they don't prevent it.** Add an approval between creating and executing the change set.
* **AWS-managed vs service-managed StackSets:** only service-managed auto-deploys to new accounts in an OU.
* **Cross-stack exports block changes.** Use SSM parameters when producers must change values independently.
* **`NoEcho` isn't a secret store.** Use dynamic references to Secrets Manager.
* **New launch template version ≠ new instances.** You need an `UpdatePolicy` or an instance refresh.

## 12. Hands-on lab: `cfn-init` + `cfn-signal` + change set + drift (about 40 minutes)

[labs/lab-04-cfn-init-signal-drift.yaml](labs/lab-04-cfn-init-signal-drift.yaml) creates three things:

* an instance in the default VPC, bootstrapped by `cfn-init`;
* a `CreationPolicy` that waits for `cfn-signal`;
* an instance profile for Session Manager, so you need no SSH key.

```bash
aws cloudformation deploy --stack-name dop-lab-04 \
  --template-file labs/lab-04-cfn-init-signal-drift.yaml --capabilities CAPABILITY_IAM

# 1) Change set: change the page text parameter and preview (no replacement expected)
aws cloudformation create-change-set --stack-name dop-lab-04 --change-set-name v2 \
  --use-previous-template --capabilities CAPABILITY_IAM \
  --parameters ParameterKey=PageText,ParameterValue="version two" ParameterKey=InstanceType,UsePreviousValue=true
aws cloudformation describe-change-set --stack-name dop-lab-04 --change-set-name v2 \
  --query 'Changes[].ResourceChange.[LogicalResourceId,Action,Replacement]'
# Now try InstanceType=t3.small instead: observe "Replacement: False" but "Some interruption" (stop/start)

# 2) Drift: add an inbound rule by hand, then detect drift
SG=$(aws cloudformation describe-stack-resource --stack-name dop-lab-04 --logical-resource-id WebSecurityGroup \
  --query StackResourceDetail.PhysicalResourceId --output text)
aws ec2 authorize-security-group-ingress --group-id $SG --protocol tcp --port 22 --cidr 10.0.0.0/8
aws cloudformation detect-stack-drift --stack-name dop-lab-04
aws cloudformation describe-stack-resource-drifts --stack-name dop-lab-04 \
  --query 'StackResourceDrifts[].[LogicalResourceId,StackResourceDriftStatus]'

aws cloudformation delete-stack --stack-name dop-lab-04
```

**Observe:**
* The stack stays `CREATE_IN_PROGRESS` until the signal arrives. Break the `cfn-init` config (e.g. a non-existent package) to see a failed signal and a rollback.
* Execute change set `v2`. The stack update succeeds, but **the web page still says "version one"**. Only the instance *metadata* changed, and nothing re-ran `cfn-init`. That's exactly the gap **`cfn-hup`** fills: it polls the metadata and re-runs `cfn-init` on change. The alternative is to make the change force a replacement (immutable, P4).
* The security group shows `MODIFIED` after your manual change: that's drift (P3).

## References

* Update behaviours of stack resources — <https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/using-cfn-updating-stacks-update-behaviors.html>
* Change sets — <https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/using-cfn-updating-stacks-changesets.html>
* Stack policies — <https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/protect-stack-resources.html>
* DeletionPolicy attribute — <https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-attribute-deletionpolicy.html>
* UpdatePolicy attribute — <https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-attribute-updatepolicy.html>
* Rollback triggers — <https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/using-cfn-rollback-triggers.html>
* Helper scripts reference — <https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/cfn-helper-scripts-reference.html>
* Custom resources — <https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/template-custom-resources.html>
* StackSets concepts — <https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/stacksets-concepts.html>
* Detect drift — <https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/using-cfn-stack-drift.html>
* Troubleshooting CloudFormation — <https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/troubleshooting.html>
