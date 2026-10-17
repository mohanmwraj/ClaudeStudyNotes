# Chapter 14 — Deployment Strategy, CI/CD & Infrastructure as Code
> **Exam mapping:** D2 Task 2.1 (deployment strategy), D3 Task 3.1 (operational excellence), D1 Task 1.4 (multi-account environment) | **Weight signal:** High | **Study time:** ~7 h
> [← Previous](13-Migration-and-Modernization.md) · [Index](00-README-Start-Here.md) · [Next →](15-Monitoring-Operations-and-Continuous-Improvement.md)

---

## 1. What the exam really tests here

SAP-C02 does not ask you to write templates or buildspecs. It gives you an organisation with constraints and asks you to pick the **deployment mechanism, release strategy and governance control** that fits. Typical scenarios:

- **"Deploy the same baseline to every account, including accounts created next month"** → CloudFormation **StackSets with service-managed permissions + automatic deployment to OUs** (or Control Tower customisations / AFT).
- **"Developers must provision approved infrastructure without broad IAM permissions"** → **AWS Service Catalog** portfolios with **launch constraints**.
- **"Release a new version with the least risk / fastest rollback / no downtime / lowest cost"** → choose between all-at-once, rolling, immutable, blue/green, canary, linear, feature flags. You must know the trade-off table cold (§4.1).
- **"Shift 10% of traffic to the new Lambda version, roll back automatically if errors rise"** → **CodeDeploy** Lambda canary deployment config + CloudWatch alarm (often through **AWS SAM** `DeploymentPreference`).
- **"Central pipeline in a tooling account deploys to dev/test/prod accounts"** → CodePipeline with **customer-managed KMS key**, **artifact bucket policy**, and **cross-account roles**.
- **"Prevent non-compliant resources from ever being provisioned"** → **CloudFormation Hooks** / **Guard** / Control Tower proactive controls (vs detective AWS Config rules).
- **"Bring existing manually-created resources under IaC"** → **IaC generator** + resource import, or `cdk migrate`.
- **"Never lose the production database when someone deletes the stack"** → `DeletionPolicy: Retain/Snapshot`, `UpdateReplacePolicy`, stack policy, termination protection.
- **"Patch 5,000 instances across accounts with a weekly window, no SSH"** → Systems Manager **Patch Manager + patch policies (Quick Setup) + maintenance windows**, **Session Manager** instead of bastions.
- **"Toggle a feature for 5% of users without redeploying code"** → **AWS AppConfig feature flags** with a gradual deployment strategy and alarm-based rollback.

The decision axes AWS cares about: **operational overhead**, **blast radius**, **rollback speed**, **downtime**, **cost of duplicate capacity**, **least privilege**, and **multi-account scale**.

---

## 2. Core concepts & services — deep dive

### 2.1 AWS CloudFormation

#### 2.1.1 Template anatomy

| Section | Required? | Purpose / exam relevance |
|---|---|---|
| `AWSTemplateFormatVersion` | No | Only valid value `2010-09-09`. |
| `Description` | No | ≤ 1,024 bytes. |
| `Metadata` | No | `AWS::CloudFormation::Interface` (console parameter grouping), `AWS::CloudFormation::Init` (lives under a resource's Metadata, used by cfn-init). |
| `Parameters` | No | Runtime inputs. Max **200**. Types: `String`, `Number`, `List<Number>`, `CommaDelimitedList`, AWS-specific (`AWS::EC2::VPC::Id`, `AWS::EC2::KeyPair::KeyName`…), and **SSM parameter types** (`AWS::SSM::Parameter::Value<AWS::EC2::Image::Id>` — the classic "always latest AMI" pattern). `NoEcho` masks values (but use dynamic references for real secrets). `AllowedValues`, `AllowedPattern`, `Min/MaxLength`. |
| `Rules` | No | Validate parameter combinations before stack create/update (e.g., "prod requires m5.large or bigger"). |
| `Mappings` | No | Static lookup tables (`Fn::FindInMap`), e.g., Region → AMI, Env → instance size. Max 200. |
| `Conditions` | No | `Fn::Equals/If/And/Or/Not`; conditionally create resources/properties/outputs (e.g., create a NAT gateway only in prod). |
| `Transform` | No | Macros: `AWS::Serverless-2016-10-31` (SAM), `AWS::Include` (snippets from S3), `AWS::LanguageExtensions` (`Fn::ForEach`, `Fn::Length`, `Fn::ToJsonString`, intrinsic in `DeletionPolicy`). |
| `Resources` | **Yes** | Max **500** resources per template. |
| `Outputs` | No | Max 200. `Export` makes a value importable by other stacks in the **same account and Region**. |

**Key quotas** (from the CloudFormation quotas page): template body **51,200 bytes** inline, **1 MB** from S3; 500 resources; 200 parameters/outputs/mappings; **2,000 stacks** per account per Region (adjustable); 60 dynamic references per template; cfn-signal and custom-resource response data ≤ **4,096 bytes**; 1,000 StackSets per administrator account; 100,000 stack instances per StackSet; nested stack operations ≤ 2,500 resources per operation.

**Intrinsic functions you must recognise:** `Ref` (logical ID → physical ID or parameter value), `Fn::GetAtt` (attributes such as `Arn`, `DNSName`), `Fn::Sub` (string interpolation, `${AWS::Region}`), `Fn::Join`, `Fn::Split`, `Fn::Select`, `Fn::FindInMap`, `Fn::ImportValue`, `Fn::GetAZs`, `Fn::Cidr`, `Fn::Base64` (UserData), `Fn::If` and condition functions, `Fn::Transform`.
**Pseudo parameters:** `AWS::AccountId`, `AWS::Region`, `AWS::StackName`, `AWS::StackId`, `AWS::Partition` (write partition-agnostic ARNs for GovCloud/China), `AWS::URLSuffix`, `AWS::NoValue` (remove a property conditionally), `AWS::NotificationARNs`.

#### 2.1.2 Stack lifecycle: change sets, rollback, drift, import

- **Change sets** — preview a stack update before executing it. Shows per resource: Add/Modify/Remove/Import and **Replacement: True / False / Conditional**. Replacement is the dangerous one (new physical resource → data loss for stateful resources). Change sets can include nested stacks. Production pipelines should **create change set → manual approval → execute change set**.
- **Update behaviours** per property: *No interruption*, *Some interruption*, *Replacement*. Changing an RDS `DBInstanceIdentifier` or a DynamoDB key schema forces replacement.
- **Rollback** — default on create/update failure. Options: `--disable-rollback` / **preserve successfully provisioned resources** (debugging), `--retain-except-on-create`. If an update rollback fails (`UPDATE_ROLLBACK_FAILED`), use **ContinueUpdateRollback** with `ResourcesToSkip`.
- **Rollback triggers** — up to **5** CloudWatch alarms (metric or **composite**), monitoring period **0–180 minutes** after resources are deployed. If any alarm goes to `ALARM` during the operation or monitoring window, the whole operation rolls back. `INSUFFICIENT_DATA` does **not** trigger unless the alarm treats missing data as breaching. For updates, old resources are not cleaned up until the monitoring period expires.
- **Drift detection** — compares current resource configuration with the template's *expected* properties (only properties explicitly defined in the template, and only for resource types that support drift detection). Statuses: `IN_SYNC`, `MODIFIED`, `DELETED`, `NOT_CHECKED`. Works on stacks and StackSets. Drift detection **reports**; it does not remediate — you fix by updating the template or reverting the change (or re-import). Combine with AWS Config rule `cloudformation-stack-drift-detection-check` for continuous checking.
- **Resource import** — bring existing resources into a stack via an `IMPORT` change set; each imported resource must have a `DeletionPolicy` in the template. Use to move resources between stacks or adopt manual resources. **Stack refactoring** (2025) lets you move resources between stacks or rename logical IDs without replacement.
- **IaC generator** — scans an account/Region (scan valid for 30 days, up to 100,000 resources) and generates a CloudFormation template (≤ 500 resources per template) for resources **not already managed by CloudFormation**; you then import them into a stack or run **`cdk migrate`** to create a CDK app. Only supports resource types supported by Cloud Control API. Exam keyword: *"bring existing console-created resources under IaC with least effort."*
- **Git sync** — CloudFormation can watch a Git repo (via CodeConnections) and update a stack when the template or deployment file changes — a lightweight GitOps option without CodePipeline.

#### 2.1.3 Protecting resources and stacks

| Mechanism | Scope | What it protects against | Notes |
|---|---|---|---|
| `DeletionPolicy: Retain` | Resource | Stack deletion / resource removal from template deletes the physical resource | Resource is orphaned and kept (you pay for it). |
| `DeletionPolicy: Snapshot` | Resource (EBS volume, RDS DB instance/cluster, Neptune, DocumentDB, ElastiCache, Redshift) | Data loss on delete | Final snapshot taken then resource deleted. **Default for `AWS::RDS::DBCluster` and for `AWS::RDS::DBInstance` without `DBClusterIdentifier` is Snapshot**; most other types default to Delete. |
| `DeletionPolicy: RetainExceptOnCreate` | Resource | Keeps resource on delete except when the stack *creation* rolls back | Avoids orphaned debris from failed creates. |
| `UpdateReplacePolicy` (Retain/Snapshot/Delete) | Resource | The *old* physical resource when an update forces **replacement** | `DeletionPolicy` does **not** cover replacement — you need both. |
| **Stack policy** | Stack (JSON, resource-level Allow/Deny on `Update:Modify`, `Update:Replace`, `Update:Delete`, `Update:*`) | Unintended **updates** to critical resources | Once a stack policy is set, all resources are protected by default (implicit deny) unless allowed. Cannot be removed, only replaced; can be **temporarily overridden** for one update. Does **not** prevent stack deletion. |
| **Termination protection** | Stack | Stack **deletion** | Enabled on root stack applies to nested stacks. |
| IAM / SCP | Principal | Who can call `DeleteStack`/`UpdateStack` | e.g., SCP denying deletion of stacks tagged `critical`. |
| Service role (`RoleArn`) | Stack | Users needing broad permissions | CloudFormation uses the role for all operations; users only need `iam:PassRole` + CFN permissions. Basis of least-privilege IaC. |

#### 2.1.4 Bootstrapping EC2: CreationPolicy, WaitCondition, cfn-init, cfn-signal, cfn-hup

- **`AWS::CloudFormation::Init`** metadata (keys: `packages`, `groups`, `users`, `sources`, `files`, `commands`, `services`; ordered via `configSets`) is read by **cfn-init** on the instance (invoked from UserData). Declarative and idempotent — better than long UserData scripts.
- **cfn-signal** sends success/failure back to CloudFormation. Paired with:
  - **`CreationPolicy`** with `ResourceSignal: {Count, Timeout}` on `AWS::EC2::Instance` or `AWS::AutoScaling::AutoScalingGroup` (plus `AutoScalingCreationPolicy.MinSuccessfulInstancesPercent`). Max timeout 12 hours (`PT12H`). Without a signal before timeout → resource fails → stack rolls back. **Use this for "stack must not report CREATE_COMPLETE until the app is actually installed."**
  - **`AWS::CloudFormation::WaitCondition` + `WaitConditionHandle`** — older/more general; use for signals from **outside** the stack resource (e.g., an external process) or to coordinate ordering. AWS recommends CreationPolicy for EC2/ASG.
- **cfn-hup** — daemon that polls resource metadata (default every 15 minutes) and runs hooks when `AWS::CloudFormation::Init` changes, so a stack update can reconfigure running instances **without replacement**.
- **`UpdatePolicy`** for ASGs: `AutoScalingRollingUpdate` (batch size, `MinInstancesInService`, `PauseTime`, `WaitOnResourceSignals`), `AutoScalingReplacingUpdate` (`WillReplace: true` → new ASG, immutable-style, old one kept until new succeeds), `AutoScalingScheduledAction`. Also `CodeDeployLambdaAliasUpdate` (used by SAM), `UseOnlineResharding` (ElastiCache), `EnableVersionUpgrade` (OpenSearch).

#### 2.1.5 Extensibility: custom resources, macros, modules, registry, Hooks, Guard

- **Custom resources** (`AWS::CloudFormation::CustomResource` or `Custom::Name`) — `ServiceToken` points to a **Lambda function** or **SNS topic**. CloudFormation sends Create/Update/Delete events with a pre-signed S3 URL; the provider must PUT a SUCCESS/FAILED response (≤ 4,096 bytes). If the function crashes without responding, the stack waits until the timeout (historically 1 hour; a `ServiceTimeout` property now lets you shorten it). Uses: look up values (latest AMI from a non-SSM source), call third-party APIs, empty an S3 bucket before deletion, create resources CloudFormation doesn't support, cross-Region/cross-account lookups. **Always handle Delete** and send a response in `finally`.
- **Macros** — Lambda-backed template transforms (`Transform`). Note: StackSets with **service-managed permissions do not support templates containing macros/transforms** (including SAM) — a documented limitation.
- **Modules** — reusable, versioned template fragments registered in the private registry (`Org::Service::Thing::MODULE`). Encapsulate best practice (e.g., a compliant S3 bucket). Max 100 modules per account/Region.
- **Registry** — public extensions (AWS and third-party resource types such as Datadog, MongoDB Atlas; you **activate** them), private extensions you register (resource types built with the CloudFormation CLI; max 50 private resource types per account/Region). Third-party types let one template manage non-AWS resources.
- **CloudFormation Hooks** — **proactive** controls invoked **before** create/update/delete of resources, stacks, change sets, or Cloud Control API operations. Implementation options: **AWS Control Tower proactive controls** (managed), **Guard rule hooks**, **Lambda hooks**, or custom hooks written with the CloudFormation CLI. Failure mode **FAIL** (block) or **WARN** (allow + log). Max 100 hooks per account/Region.
- **AWS CloudFormation Guard (cfn-guard)** — open-source policy-as-code DSL to validate templates (JSON/YAML, also Terraform plans/K8s manifests) in a CI step (`cfn-guard validate`), or server-side via Guard hooks. Shift-left compliance: fails the pipeline *before* deploy.
- **cfn-lint** — syntax/best-practice linting; **cfn-nag** / **cdk-nag** — security linting (community/AWS Labs).

> **Proactive vs detective vs preventive:** SCPs/RCPs = preventive (API-level deny); Hooks/Guard/proactive controls = proactive (block non-compliant IaC before provisioning); AWS Config rules = detective (find after the fact, optional auto-remediation via SSM Automation).

#### 2.1.6 Dynamic references (secrets in templates)

- `{{resolve:ssm:/path/param:version}}` — SSM Parameter Store plaintext (String/StringList).
- `{{resolve:ssm-secure:/path/param:version}}` — SecureString; supported only in specific resource properties (e.g., RDS `MasterUserPassword`, IAM user password).
- `{{resolve:secretsmanager:secret-id:SecretString:json-key:version-stage}}` — Secrets Manager; works in any property.
- Values are resolved at deploy time and **not stored/displayed** in the template or stack events (unlike default parameter values). Better still: RDS `ManageMasterUserPassword: true` lets RDS create and rotate the secret in Secrets Manager.
- Max 60 dynamic references per template. Dynamic references are **not re-resolved** unless the stack is updated (rotating a secret doesn't update resources automatically).

#### 2.1.7 Composing stacks: nested stacks vs cross-stack references

| | **Nested stacks** (`AWS::CloudFormation::Stack`) | **Cross-stack references** (`Export` + `Fn::ImportValue`) |
|---|---|---|
| Relationship | Parent/child; deployed and updated **together** as one unit | Independent stacks with **separate lifecycles** |
| Typical use | Reuse components (standard ALB, VPC template) inside one application; get past 500-resource limit | Shared layers owned by different teams (network stack exports subnet IDs; app stacks import) |
| Ownership | Single team | Multiple teams |
| Coupling gotcha | Updating the parent updates children; rollback is whole tree | You **cannot delete** the exporting stack or **change/remove** an export while any stack imports it |
| Scope | Same account/Region (templates from S3) | **Same account and Region only**; export names unique per account/Region |
| Cross-account/Region alternative | StackSets | Store values in SSM Parameter Store (shared via RAM for advanced parameters / read cross-account), or CDK `crossRegionReferences` (uses SSM + custom resource) |

#### 2.1.8 StackSets (multi-account, multi-Region)

A StackSet (a **Regional** resource in the administrator account) deploys **stack instances** of one template to many **accounts × Regions**.

| | **Self-managed permissions** | **Service-managed permissions** |
|---|---|---|
| Targets | Any account IDs (inside or outside an Organization) | Accounts in AWS Organizations, targeted by **OU** (or org root) |
| IAM setup | You create `AWSCloudFormationStackSetAdministrationRole` in the admin account and `AWSCloudFormationStackSetExecutionRole` in every target account | StackSets creates the roles for you (requires **trusted access** with Organizations) |
| Automatic deployment | No | **Yes** — new accounts added to a target OU get the stack automatically; accounts removed can have stacks deleted or **retained** |
| Who administers | Any account | **Management account** or up to **five delegated administrator** member accounts (`CallAs: DELEGATED_ADMIN`) |
| Management account | Can be targeted | **Not deployed to the management account**, even if it sits in a targeted OU |
| Macros/transforms | Supported | **Not supported** |

**Operation options** (exam loves these):
- **Maximum concurrent accounts** (number or %) — how many accounts per Region at once.
- **Failure tolerance** (number or %) — failures allowed **per Region** before CloudFormation stops the operation (and does not proceed to later Regions).
- **Concurrency mode** — *Strict failure tolerance* (concurrency reduced as failures occur; max concurrent ≤ failure tolerance + 1) vs *Soft failure tolerance* (keeps concurrency at the configured level regardless of failures — faster).
- **Region concurrency** — *Sequential* (default, in the Region order you specify — deploy to a canary Region first) or *Parallel*.
- **Retain stacks** on delete — disassociate stacks from the StackSet but keep them running.
- Parameter **overrides** per account/Region; **drift detection** across stack instances; import existing stacks into a StackSet.
- Quotas: 10,000 concurrent stack-instance operations per Region per admin account; queued operations up to 10,000.

**Exam patterns:** "deploy GuardDuty/Config/IAM roles to every existing and future account" → service-managed StackSet with auto-deployment targeting the root or OUs. "Security tooling account should manage StackSets, not the management account" → register it as **delegated administrator**. "Roll out safely" → sequential Regions, low max concurrency, failure tolerance 0.

### 2.2 AWS CDK

- Open-source framework: define infrastructure in TypeScript, Python, Java, C#/.NET, Go; **`cdk synth`** produces a **cloud assembly** (CloudFormation templates + assets) and **`cdk deploy`** deploys via CloudFormation. Everything CloudFormation can do (change sets, rollback, drift) still applies.
- **Constructs:**
  - **L1** (`Cfn*` classes) — 1:1 with CloudFormation resource types, auto-generated, no defaults.
  - **L2** — intent-based, sensible secure defaults, helper methods (`bucket.grantRead(role)`, `fn.addEventSource()`), auto-generated least-privilege IAM.
  - **L3 / patterns** — multi-resource architectures, e.g., `ApplicationLoadBalancedFargateService`, `LambdaRestApi`.
- **App → Stages → Stacks → Constructs.** Stacks have explicit `env` (account/Region). **Bootstrapping** (`cdk bootstrap`) creates the `CDKToolkit` stack per account/Region: staging S3 bucket, ECR repo, and deployment roles; `--trust <tooling-account>` lets a pipeline account deploy into it (cross-account).
- **Assets** — Lambda code and Docker images are packaged and uploaded automatically.
- **Aspects** — visitors applied to all constructs (e.g., enforce encryption, tagging); **cdk-nag** applies rule packs (AWS Solutions, HIPAA, NIST 800-53).
- **CDK Pipelines** (`pipelines.CodePipeline`) — opinionated L3 construct that builds a CodePipeline which is **self-mutating** (an `UpdatePipeline` stage updates the pipeline itself when you change pipeline code), publishes assets, and deploys **Stages** to multiple accounts/Regions in **waves**, with pre/post steps (`ShellStep`, `ManualApprovalStep`). Cross-account works through bootstrapped trust.
- `cdk diff` (preview), `cdk watch`/hotswap (dev only — bypasses CloudFormation, never for prod), `cdk import`, `cdk migrate` (from template/IaC generator/deployed stack).

### 2.3 AWS SAM

- CloudFormation **transform** (`Transform: AWS::Serverless-2016-10-31`) with shorthand types: `AWS::Serverless::Function`, `Api`, `HttpApi`, `SimpleTable`, `LayerVersion`, `StateMachine`, `Application` (Serverless Application Repository), `Connector` (generates IAM permissions between resources), `GraphQLApi`.
- **SAM CLI:** `sam build`, `sam local invoke/start-api` (Docker-based local testing), `sam deploy --guided`, `sam sync` (rapid dev sync), `sam pipeline init` (bootstraps multi-stage pipelines for CodePipeline, GitHub Actions, GitLab, Jenkins…).
- **Safe Lambda deployments built in:**

```yaml
MyFunction:
  Type: AWS::Serverless::Function
  Properties:
    AutoPublishAlias: live
    DeploymentPreference:
      Type: Canary10Percent5Minutes      # or Linear10PercentEvery1Minute, AllAtOnce...
      Alarms: [!Ref ErrorsAlarm]
      Hooks:
        PreTraffic: !Ref PreTrafficCheckFn
        PostTraffic: !Ref PostTrafficCheckFn
```

  SAM creates a CodeDeploy application/deployment group, publishes a new version, and shifts the alias with automatic rollback on alarm. This is the canonical answer to *"serverless app, gradual traffic shifting, automatic rollback, least effort."*

### 2.4 Terraform on AWS

- HashiCorp Terraform (BSL-licensed; OpenTofu is the open-source fork) uses the AWS provider (and `awscc` provider via Cloud Control API).
- **Remote state in S3** with bucket **versioning**, SSE-KMS encryption, Block Public Access, and a restrictive bucket policy; **state locking** traditionally with a **DynamoDB table**; newer Terraform versions support **native S3 locking** (`use_lockfile = true`) and HashiCorp has marked DynamoDB-based locking **deprecated**. Expect either answer on SAP-C02; "S3 + DynamoDB" is the classic exam phrasing.
- Multi-account: a central state bucket per environment/account; Terraform assumes roles per target account via provider `assume_role`.
- **Account Factory for Terraform (AFT)** — Control Tower solution that provisions and customises accounts via a GitOps pipeline (account request repo → CodePipeline/CodeBuild in the AFT management account). Covered in [Chapter 02](02-Multi-Account-Governance.md).
- Service Catalog supports Terraform via **Terraform Cloud** and **External** product types (Terraform Open Source product type is deprecated for new products).
- Exam angle: Terraform is a valid answer when the stem says "the company already standardises on Terraform" or "multi-cloud"; otherwise AWS-native (CloudFormation/CDK) is usually the "least operational overhead" answer.

### 2.5 AWS Service Catalog

Governed self-service: administrators curate approved IaC products; end users launch them without needing permissions to the underlying services.

- **Product** — a CloudFormation template (or Terraform Cloud/External config) with **versions** (provisioning artifacts). Versions can be deprecated; **guidance** marks a recommended version.
- **Portfolio** — collection of products + **access** (IAM users/groups/roles, or **principal name sharing** so the same role name works in every shared account) + **constraints**.
- **Constraints** (applied per product-in-portfolio):
  - **Launch constraint** — IAM **role Service Catalog assumes** to provision/update/terminate. End users need only Service Catalog end-user permissions (e.g., `AWSServiceCatalogEndUserFullAccess`), **not** EC2/RDS/IAM permissions. Specify a **local role name** (not ARN) so the constraint works in every account the portfolio is shared to. This is *the* answer to "developers must launch EC2/RDS without being granted those permissions."
  - **Template constraint** — restrict parameter values (e.g., only `t3.*` instance types in dev) using rules JSON — without editing the product template.
  - **Notification constraint** — SNS topic for stack events.
  - **StackSet constraint** — provision product across accounts/Regions as a StackSet.
  - **Tag update constraint** — allow/deny users updating tags on provisioned products.
- **TagOptions** — admin-defined key/value pairs attached to portfolios/products; users choose from allowed values → consistent cost allocation tagging enforced at launch.
- **Sharing** — account-to-account sharing (recipient *imports* the portfolio; admin updates propagate) or **AWS Organizations sharing** to the whole org, an OU or accounts (from management account or a **delegated administrator**). Recipients can add their own local constraints/users. Imported products cannot be edited by the recipient.
- **Service actions** — SSM Automation documents end users can run against provisioned products (e.g., restart, back up) without direct permissions.
- **Provisioned product updates** — users update to a new version; admins can see all provisioned products (copy, change owner).
- **AWS Service Catalog AppRegistry** — repository of **applications** and **attribute groups** associating stacks/resources with business metadata (owner, cost centre, criticality); underpins the console's **myApplications** view and cost/ops reporting by application.
- Integrations: Control Tower Account Factory is itself a Service Catalog product; Service Catalog products can be launched from CodePipeline (deploy action) and ServiceNow/Jira connectors.

**Self-service governed provisioning pattern:**

```text
 Central IT / CCoE (hub account, delegated admin for Service Catalog)
 ┌─────────────────────────────────────────────────────────┐
 │ Products (CFN templates, Guard-validated in CI)         │
 │ Portfolio "Dev-Approved" ── TagOptions (CostCenter=...) │
 │   ├─ Launch constraint: role name SCLaunchRole          │
 │   └─ Template constraint: instance types t3.* only      │
 └──────────────┬──────────────────────────────────────────┘
                │ Organizations share → OU=Workloads/Dev
                ▼
 Spoke account (Dev)   SCLaunchRole (pre-created via StackSet)
   Developer role: servicecatalog:* end-user only  ──launch──► CloudFormation stack
                                                     (created as SCLaunchRole)
```

### 2.6 CI/CD services

#### 2.6.1 AWS CodePipeline

- Orchestrates **stages** (sequential) containing **actions** (run in parallel or sequence by `runOrder`). Action categories: **Source, Build, Test, Deploy, Approval, Invoke**, plus Compute (Commands action).
- **Source providers:** CodeCommit, S3, ECR, and **GitHub / GitHub Enterprise Server / GitLab / Bitbucket via CodeConnections** (formerly CodeStar Connections).
- **Deploy providers:** CloudFormation (create/update stack, create/replace/execute change set, **StackSets**), CodeDeploy, ECS (rolling and blue/green via CodeDeploy), Elastic Beanstalk, S3, Service Catalog, AppConfig, Lambda, EC2, EKS, Alexa, etc.
- **Pipeline types:**

| | V1 | V2 |
|---|---|---|
| Pricing | $1 per active pipeline/month | Per **action-execution minute** ($0.002; manual approvals and custom actions not billed) |
| Triggers with filters on Git tags, branches, PRs, file paths | No | **Yes** |
| Pipeline-level variables at runtime | No | Yes |
| Execution modes | SUPERSEDED only | **SUPERSEDED, QUEUED, PARALLEL** |
| Stage rollback, stage conditions (entry/on-success/on-failure, e.g., check a CloudWatch alarm), automatic retry | No | Yes |
| Source revision overrides, Commands action | No | Yes |

- **Manual approval** action — optionally SNS notification + URL for review; times out after **7 days** if not approved. Use IAM to control who can approve (`codepipeline:PutApprovalResult`).
- **Artifacts** — stored in an S3 **artifact store** per Region, encrypted with KMS (AWS managed key `aws/s3` by default).
- **Cross-Region actions** — a pipeline can run actions in other Regions; CodePipeline needs an **artifact store (S3 bucket) in each Region** where actions run (console creates them) and a KMS key per Region if using CMKs.
- **Cross-account actions** — requirements (memorise the trio):
  1. **Customer-managed KMS key** in the pipeline Region encrypting artifacts, with key policy granting the target account/role decrypt (the AWS managed default key cannot be shared cross-account).
  2. **Artifact bucket policy** granting the target account role access.
  3. **Cross-account IAM role** in the target account that the pipeline's service role can assume (`roleArn` on the action) — plus for CloudFormation actions a **CloudFormation deployment role** in the target account passed as the action's `RoleArn`.
  An artifact can only move between accounts via the pipeline account. Cross-account pipelines are edited with CLI/IaC (console can't add cross-account actions).
- **Event-driven** — triggers via EventBridge (CodeCommit/S3/ECR changes) or webhooks (CodeConnections); pipeline state changes emit EventBridge events (notify Slack via AWS Chatbot / Amazon Q Developer in chat applications).

#### 2.6.2 AWS CodeBuild

- Fully managed build service; you pay per build minute by compute type. Builds run in ephemeral containers (Linux, Windows, ARM, GPU) or **Lambda compute**; **reserved capacity fleets** for always-warm/custom AMIs. Build timeout 5 minutes–**36 hours** (default 60 min).
- **buildspec.yml** phases: `install`, `pre_build`, `build`, `post_build`; plus `env` (variables, **Parameter Store** and **Secrets Manager** references), `artifacts`, `reports` (test/coverage), `cache` (S3 or local).
- **VPC support** to reach private resources (RDS, internal artifact repos) — needs NAT or VPC endpoints for internet/AWS APIs.
- **Batch builds** (build matrix/graph), **webhooks** (GitHub/GitLab/Bitbucket direct), self-hosted **GitHub Actions runners** on CodeBuild.
- Security: service role per project; artifacts encrypted with KMS; privileged mode for Docker builds.
- Run security tools (SAST, cfn-guard, cfn-nag, Inspector SBOM, Trivy) as build/test actions.

#### 2.6.3 AWS CodeDeploy

Deploys application revisions to **EC2/on-premises**, **Lambda**, and **ECS**. Components: application → **deployment group** (targets by tags/ASG, deployment config, alarms, triggers, rollback settings) → **revision** (S3 bundle/GitHub for EC2; AppSpec for Lambda/ECS).

| Compute platform | Deployment types | Traffic control | Predefined configs |
|---|---|---|---|
| **EC2/On-premises** (needs CodeDeploy agent) | **In-place** (stop app, install, restart on existing instances; optional LB deregistration) or **Blue/green** (EC2 only — new instances/ASG copy, reroute LB traffic, then terminate or keep blue) | Load balancer (ALB/NLB/CLB) | `CodeDeployDefault.OneAtATime` (default), `HalfAtATime`, `AllAtOnce`; custom by **minimum healthy hosts** (number/%), optional **per-AZ (zonal)** configuration |
| **Lambda** | Always "blue/green" style: shifts **alias** weights between versions | Alias routing | `LambdaCanary10Percent{5,10,15,30}Minutes`, `LambdaLinear10PercentEvery{1,2,3,10}Minute(s)`, `LambdaAllAtOnce`; custom canary/linear |
| **ECS** | Blue/green via replacement **task set** behind ALB/NLB with production and optional **test listener** | ALB/NLB listener rules | `ECSCanary10Percent{5,15}Minutes`, `ECSLinear10PercentEvery{1,3}Minutes`, `ECSAllAtOnce` (NLB supports only AllAtOnce) |

- **Canary** = two steps (X% then 100% after N min). **Linear** = equal increments every N min. **All-at-once** = immediate.
- **AppSpec lifecycle hooks:**
  - EC2/on-prem in-place: `ApplicationStop → DownloadBundle → BeforeInstall → Install → AfterInstall → ApplicationStart → ValidateService` (with LB: `BeforeBlockTraffic/BlockTraffic/AfterBlockTraffic` and `BeforeAllowTraffic/AllowTraffic/AfterAllowTraffic`). Scripts you supply run at the non-reserved hooks.
  - ECS: `BeforeInstall`, `AfterInstall`, `AfterAllowTestTraffic`, `BeforeAllowTraffic`, `AfterAllowTraffic` (Lambda functions as hooks — e.g., run integration tests against the test listener).
  - Lambda: `BeforeAllowTraffic`, `AfterAllowTraffic` (validation Lambda functions).
- **Automatic rollback** — on deployment failure and/or when a **CloudWatch alarm** attached to the deployment group fires (up to 10 alarms per group). Rollback = a *new* deployment of the last known good revision (EC2 in-place rollback redeploys; blue/green rollback reroutes to the original environment — much faster).
- **Notes:** CodeDeploy integrates with ASG lifecycle hooks so newly launched instances get the latest revision (scale-out during deployment can deploy old revision — known gotcha; CodeDeploy redeploys later). On-premises instances register with IAM user/role credentials (or IAM Roles Anywhere-style session).
- **Amazon ECS native deployments (2025):** ECS now supports **built-in blue/green** (July 2025) and **built-in linear and canary** (Oct 2025) strategies with lifecycle hooks and bake time, without CodeDeploy. Exam questions written earlier will still say "CodeDeploy blue/green for ECS"; both are correct mechanisms. ECS's classic **rolling update** uses `minimumHealthyPercent`/`maximumPercent` and the **deployment circuit breaker** (auto-rollback on failed deployments).

#### 2.6.4 Source control: CodeCommit and CodeConnections

- **AWS CodeCommit status (verified 2026):** In July 2024 AWS stopped onboarding new customers to CodeCommit. In **November 2025 AWS reversed this and returned CodeCommit to full general availability** — new accounts can create repositories again, with roadmap items such as Git LFS. SAP-C02 questions may still use CodeCommit as a source; it's a valid answer. Key features: private Git, IAM auth (HTTPS GRC, git-remote-codecommit), KMS encryption at rest, approval rule templates for PRs, triggers to SNS/Lambda, EventBridge events, cross-account access via IAM role.
- **AWS CodeConnections** (renamed from CodeStar Connections in 2024) — managed OAuth/app connection to **GitHub, GitHub Enterprise Server, GitLab (SaaS and self-managed), Bitbucket Cloud** for CodePipeline, CodeBuild, CloudFormation Git sync, Service Catalog sync etc. Self-managed providers need a **host** resource (can be configured with VPC access). A connection is created once (the OAuth handshake is done in the console by someone with rights on the Git provider) and referenced by ARN; grant `codeconnections:UseConnection` to the pipeline/build role. Typically created in the tooling account that runs the pipelines.

#### 2.6.5 AWS CodeArtifact

- Managed artifact repository for **npm, PyPI, Maven/Gradle, NuGet, Swift, Ruby gems, Cargo, generic** packages.
- **Domain** (shared storage, dedup, single KMS key, cross-account via domain policy) → **repositories** (resource policies) with **upstream repositories** and **external connections** to public registries (npmjs, PyPI, Maven Central). Pattern: one org-wide domain in a shared-services account, a curated repo that proxies public registries; builds in a VPC reach it via **VPC endpoints** (no internet).
- **Package origin controls** block dependency-confusion attacks (prevent public versions of an internal package name).
- Auth via short-lived tokens (`aws codeartifact login`, max 12 h).

#### 2.6.6 Amazon Q Developer (brief)

Generative-AI assistant for the SDLC: code suggestions in IDEs, security scanning, `/dev` feature implementation agents, code transformation (Java version upgrades, .NET porting — see Chapter 13), CLI completions, console troubleshooting, and **Amazon Q Developer in chat applications** (formerly AWS Chatbot) for Slack/Teams ChatOps. On SAP-C02 it appears at most as a "developer productivity / modernisation accelerator" distractor or answer; not core.

#### 2.6.7 AWS Proton — discontinued

AWS Proton (platform-engineering templates for environments and services) stopped accepting new customers on **7 October 2025** and **reached end of support on 7 October 2026** — the console and Proton resources are no longer accessible (deployed infrastructure remains). AWS's migration guidance points to **CloudFormation Git sync, CodePipeline + CodeBuild, GitHub Actions, or Harmonix on AWS** (Backstage-based). If an older-style question offers Proton for "platform team publishes standard templates; developers self-serve", today's equivalents are **Service Catalog**, CDK construct libraries/modules, or an internal developer portal. Don't pick Proton as a forward-looking design.

### 2.7 Deployment strategies — mechanics

| Strategy | How it works | Where on AWS |
|---|---|---|
| **All-at-once / in-place** | Update every target simultaneously | EB *All at once*; CodeDeploy `AllAtOnce`; Lambda `AllAtOnce` |
| **Rolling** | Update in batches; capacity reduced by one batch during deploy | EB *Rolling*; CodeDeploy `OneAtATime/HalfAtATime`; ASG rolling update / instance refresh; ECS rolling (`minimumHealthyPercent`) |
| **Rolling with additional batch** | Launch an extra batch first so full capacity is maintained | EB *Rolling with additional batch*; ECS `maximumPercent` > 100 |
| **Immutable** | Launch a full new set of instances (new temporary ASG), shift in, terminate old | EB *Immutable*; CFN `AutoScalingReplacingUpdate`; ASG instance refresh with new launch template version |
| **Traffic splitting (EB canary)** | New instances receive a % of client traffic for an evaluation period | EB *Traffic splitting* (requires ALB) |
| **Blue/green** | Full parallel environment; switch traffic (DNS, LB, alias) all at once; keep blue for rollback | EB **swap environment URLs**; CodeDeploy EC2/ECS blue/green; Route 53 weighted; ALB weighted target groups; RDS Blue/Green |
| **Canary** | Small % first, then the rest after a bake period | CodeDeploy Lambda/ECS canary; ECS native canary; API Gateway canary release; CloudFront continuous deployment (≤ 15% weight, or header-based); AppConfig `Canary10Percent20Minutes` |
| **Linear** | Equal increments at fixed intervals | CodeDeploy linear; ECS native linear; AppConfig linear |
| **Shadow / dark launch** | Mirror real traffic to the new version; responses discarded | Application-level request mirroring; SageMaker AI shadow tests for models (VPC Traffic Mirroring is packet capture for inspection, not a release mechanism) |
| **Feature flags** | Ship code dark; enable features at runtime per segment | **AWS AppConfig** feature flags (+ AppConfig Agent). CloudWatch Evidently has been retired in favour of AppConfig |

### 2.8 AWS Elastic Beanstalk deployment policies

| Policy | Downtime | Capacity during deploy | Extra cost | Rollback | Deploy time |
|---|---|---|---|---|---|
| **All at once** | **Yes** (brief) | Zero during cutover | None | Manual redeploy of previous version | Fastest |
| **Rolling** | No | **Reduced** by batch size | None | Manual redeploy (slow; mixed versions) | Medium |
| **Rolling with additional batch** | No | Full | Small (one batch) | Manual redeploy | Medium-long |
| **Immutable** | No | Full (double during deploy) | High (temporary 2× instances) | **Fast** — terminate new temporary ASG | Long |
| **Traffic splitting** | No | Full (double during evaluation) | High (temporary) | **Fast** — reroute and terminate new instances; automatic if health fails | Long |
| **Blue/green (swap URLs)** | No (subject to DNS caching) | Two complete environments | Highest (full second environment) | **Fast** — swap CNAMEs back | Long |

- **Blue/green in EB** isn't a deployment policy: you **clone** the environment, deploy to the clone, test, then **Swap environment URLs** (swaps CNAMEs). Keep the **RDS database outside** the EB environment. An RDS instance created inside the environment is tied to the environment's lifecycle and is deleted with it.
- `.ebextensions` / `.platform` hooks customise instances. **Managed platform updates** apply patch/minor platform versions in a weekly window using an immutable deployment.

### 2.9 DNS-based vs load-balancer-based blue/green

| | **Route 53 weighted records** | **ALB weighted target groups** | **CodeDeploy / ECS-managed** |
|---|---|---|---|
| Granularity | Weight 0–255 per record | Weights per target group in one forward action (multiple TGs) | Predefined or custom canary/linear |
| Speed of switch | **Subject to DNS TTL and client/resolver caching** (some clients ignore TTL; JVMs cache DNS), so old traffic has a "long tail" | **Immediate**: listener rule change, no DNS involved | Immediate (listener) |
| Scope | Any endpoints, across Regions, accounts, even on-premises; whole-stack swaps | Both environments behind the **same ALB** | ECS/EC2/Lambda only |
| Rollback | Change weights back (still TTL-bound) | Instant | Automatic on alarm |
| Health | Route 53 health checks | ALB target health | Alarms + hooks |
| Stickiness | None (DNS) | Optional target-group-level stickiness keeps a user on one version during the shift | n/a |

**Exam rule:** if the question complains that "some users still hit the old version for hours after switching", the cause is DNS caching. Fix it by **lowering the TTL well before the cutover**, or switch at the **load balancer** layer instead. If blue and green are in different Regions or accounts, or you are swapping an entire stack including the load balancer, use Route 53.

### 2.10 Lambda versions and aliases

- **Version** = immutable snapshot of code + configuration (`:1`, `:2`). `$LATEST` is mutable. Publish a version per release.
- **Alias** = named pointer (`live`, `prod`) to a version, with optional **weighted routing to a second version** (for example 90% v5 / 10% v6). Callers (API Gateway, event source mappings, Step Functions) reference the alias ARN, so changing the alias is the release.
- CodeDeploy shifts alias weights (canary/linear) with `BeforeAllowTraffic`/`AfterAllowTraffic` hooks and alarms. SAM `AutoPublishAlias` + `DeploymentPreference` automate it.
- **Provisioned concurrency** is configured on a version or alias. Pre-warm the new version before shifting traffic to it.
- A weighted alias cannot point to `$LATEST`.

### 2.11 Databases in blue/green: schema changes

The hardest part of blue/green is **state**. Usually the blue and green application fleets share **one database**, so:

1. **Use backward-compatible migrations (expand/contract, also called parallel change):**
   - *Expand*: add new tables and nullable columns. Never rename or drop in the same release.
   - Deploy code that writes both the old and new shapes and reads with fallback.
   - Backfill data.
   - Switch reads to the new shape. Once blue is retired and the rollback window has passed, *contract*: drop old columns in a later release.
2. Run migrations as a **separate pipeline step before** shifting traffic (CodeBuild job, ECS task, Lambda custom resource) and make them idempotent (Flyway, Liquibase).
3. Rolling back app code is cheap; **rolling back destructive schema changes is not**. That is why expand/contract exists.

**Amazon RDS Blue/Green Deployments** (RDS for MySQL, MariaDB and PostgreSQL; Aurora MySQL and Aurora PostgreSQL have their own equivalent):
- Creates a **green** copy of the production topology (including read replicas and Multi-AZ) kept in sync by replication (binlog for MySQL/MariaDB; physical or, under some conditions, **logical** replication for PostgreSQL).
- Use it for **major/minor engine upgrades, parameter group changes, instance class/storage changes, and replication-compatible schema changes**. Green is **read-only by default**; writing to green risks replication conflicts.
- **Switchover** typically takes **under one minute**, has built-in **guardrails** (it checks replication health and long-running transactions), loses **no data**, and swaps names and endpoints so applications need **no connection string changes**. The old environment is renamed `-old1` and kept for regression testing.
- RDS Proxy and the AWS "smart" JDBC drivers reduce downtime by detecting the topology change faster than DNS.
- It is not a traffic-shifting canary. It is an all-at-once switchover for the database tier.

### 2.12 Immutable infrastructure & golden AMIs — EC2 Image Builder

- **Immutable infrastructure**: never patch in place. Build a new image, roll it out, and discard old instances. Benefits: no configuration drift, reproducible builds, easy rollback (previous AMI), faster scale-out (less configuration at boot).
- **EC2 Image Builder** (no extra charge; you pay for the underlying resources):
  - **Components** (build and test steps in YAML; AWS-managed components include hardening and the CloudWatch agent) → **image recipe** (parent image + components + storage) or **container recipe** (Docker images pushed to ECR).
  - **Infrastructure configuration**: instance type, subnet, security group, instance profile, SNS topic, logs to S3.
  - **Distribution settings**: copy AMIs to multiple **Regions**, share with **accounts, OUs or the organization**, re-encrypt with KMS keys, update **launch templates**, publish the AMI ID to SSM Parameter Store.
  - **Image pipeline**: runs on a schedule (cron) or when the parent image or dependencies update. Optional **Amazon Inspector** vulnerability scanning; **image lifecycle policies** to deprecate, disable or delete old images and snapshots; **workflows** for custom build/test sequences.
- **Golden AMI rollout:** Image Builder writes the new AMI ID to an SSM parameter such as `/golden/linux/latest` → the launch template references it (`resolve:ssm:`) → **ASG instance refresh** (minimum healthy %, checkpoints, auto-rollback on alarm) or CloudFormation `AutoScalingReplacingUpdate`.
- **Governing AMI usage:** AWS Config rules `approved-amis-by-id` / `approved-amis-by-tag`, the EC2 **Allowed AMIs** account setting, or SCP conditions on the image ID or AMI owner.

### 2.13 AWS Systems Manager for deployment & configuration

| Capability | What it does | Exam trigger |
|---|---|---|
| **Run Command** | Runs SSM documents (shell/PowerShell, AWS-managed docs) on fleets selected by tag or resource group; **rate control** (concurrency, error threshold); output to S3/CloudWatch Logs; audited in CloudTrail | "Execute a script on 2,000 instances without SSH or a bastion" |
| **State Manager** | **Associations** that enforce desired state on a schedule (install an agent, join a domain, configure software); applied automatically to new instances that match | "Keep configuration compliant / auto-apply to new instances" |
| **Automation** | **Runbooks**: multi-step workflows (API calls, scripts, `aws:approve`, branching); rate control; **multi-account and multi-Region execution** from a central account; a target for Config remediation and EventBridge rules | "Automate AMI patching", "auto-remediate non-compliant resources", "stop instances on a schedule" |
| **Parameter Store** | Hierarchical config and secrets (`String`, `StringList`, `SecureString` with KMS). **Standard** tier: free, up to 10,000 parameters per account per Region, 4 KB values. **Advanced** tier: charged, up to 100,000 parameters, 8 KB values, **parameter policies** (expiration, notifications), shareable cross-account via **AWS RAM** | "Central config values, cheap". Choose Secrets Manager instead when **automatic rotation** is needed |
| **Distributor** | Packages and publishes software (agents) to managed nodes; install once or on a schedule via State Manager | "Distribute a third-party agent to all instances" |
| **Patch Manager** | **Patch baselines** (AWS predefined per OS, or custom with auto-approval delay, classification/severity filters, approved/rejected lists); `AWS-RunPatchBaseline` scans or installs; target with **patch groups** (tag) or org-wide **patch policies** via Quick Setup; compliance reporting | "Patch the fleet monthly; approve critical patches after 7 days" |
| **Maintenance Windows** | Schedule (cron/rate), duration, cutoff; registered targets; task types are Run Command, Automation, Lambda, Step Functions | "Patch only during Sunday 02:00–04:00" |
| **Session Manager** | Browser/CLI shell and **port forwarding** to instances with **no inbound ports, no bastion, no SSH keys**; access controlled by IAM; session logs to S3/CloudWatch Logs; KMS-encrypted; works from private subnets through VPC interface endpoints (`ssm`, `ssmmessages`, and `ec2messages`) | "Replace bastion hosts", "audit all interactive sessions" |
| **Fleet Manager** | Console UI for node management (file system, processes, users, Windows registry, RDP through Session Manager) | "GUI administration of Windows instances without opening RDP" |
| **Change Manager** | Change requests, templates, approvals, change calendar integration. **Closed to new customers since 7 November 2025**; existing customers can keep using it | Older questions: "approval workflow before running Automation in prod". Today also consider Change Calendar + Automation `aws:approve` |
| **Change Calendar** | Open/closed periods; Automation can check the calendar before it runs | "Block changes during a freeze period" |
| **Quick Setup** | Org-wide configuration across OUs and Regions: host management, **Default Host Management Configuration (DHMC)**, patch policies, Config, DevOps Guru, Distributor, Resource Scheduler | "Enable SSM management for all accounts with least effort" |
| **Inventory / Compliance / Explorer / OpsCenter** | Software inventory (Resource Data Sync to S3 + Athena), compliance dashboards, OpsItem aggregation | "Report which instances lack a patch or agent across the org" |

- A node becomes **managed** when the SSM Agent runs, can reach Systems Manager endpoints, and has permissions — through an instance profile (`AmazonSSMManagedInstanceCore`) or **DHMC** (an account-level role, so no instance profile is needed). On-premises and other-cloud servers register with **hybrid activations**.
- Multi-account: delegated administrator for Systems Manager features; Resource Data Sync aggregates inventory into one S3 bucket; Automation runs cross-account using an execution role in each target account.

### 2.14 AWS AppConfig

- A Systems Manager capability that deploys **configuration and feature flags** to applications **without a code deployment**, with safety controls.
- Model: **Application → Environment** (with **CloudWatch alarms** for rollback) → **Configuration profile** (type **Feature flags** or **Freeform**). Freeform sources: AppConfig hosted store, S3, Parameter Store, Secrets Manager, SSM documents, CodePipeline.
- **Validators**: **JSON Schema** (syntactic) and **Lambda** (semantic) run before deployment, so invalid configuration never ships.
- **Deployment strategies**: linear or exponential growth, deployment time, and **bake time** (alarm monitoring after reaching 100%). Predefined strategies: `AppConfig.Linear20PercentEvery6Minutes` (AWS-recommended for prod: 30-minute deployment, 30-minute bake), `AppConfig.Canary10Percent20Minutes` (exponential, 10-minute bake), `AppConfig.AllAtOnce` (10-minute bake), `AppConfig.Linear50PercentEvery30Seconds` (testing only).
- **Automatic rollback** if an environment alarm fires during deployment or bake time. You can also stop or roll back manually.
- **Feature flags**: boolean flags with attributes and constraints; **multi-variant flags** with targeting rules (serve a variant by user or segment). The **AppConfig Agent** (Lambda extension, ECS/EKS sidecar, EC2) caches configuration locally, polls in the background, and supports **entity-based gradual deployment** (a user stays on the same version for the whole rollout).
- Extensions notify EventBridge/SNS/SQS, integrate with Jira, back up configurations, and so on.
- **Why it matters:** it separates **deploy** (code shipped dark) from **release** (flag flipped). That gives the fastest rollback of any strategy (flip the flag, seconds) at almost no infrastructure cost.

---

## 3. Architecture patterns

### Pattern A — Multi-account CI/CD from a central tooling account

```text
           Developers ── git push ──► GitHub / GitLab / CodeCommit
                                            │ (CodeConnections / EventBridge)
 ┌──────────────────────── Tooling (CI/CD) account ───────────────────────┐
 │ CodePipeline V2 ─► CodeBuild (unit tests, cfn-guard, SAST, synth)      │
 │      │                                                                 │
 │      │  Artifact S3 bucket (bucket policy → dev/test/prod roles)       │
 │      │  Customer-managed KMS key (key policy → dev/test/prod accounts) │
 │      ▼                                                                 │
 │  Deploy-Dev ──► Deploy-Test ──► [Manual approval] ──► Deploy-Prod      │
 └─────┬─────────────────┬──────────────────────────────────┬─────────────┘
       │ sts:AssumeRole   │                                  │
       ▼                  ▼                                  ▼
 Dev account         Test account                       Prod account
  CodePipelineCrossAccountRole (trusts tooling pipeline role; S3 + KMS access)
  CloudFormationExecutionRole  (passed as RoleArn; permissions to create resources)
  → change set create/execute; CodeDeploy deployment group; ECS service
```

- **Why:** separation of duties; pipelines and build credentials are isolated from workloads; the prod account has no human write access.
- **Requirements:** a CMK, a bucket policy, and two roles per target account (one that CodePipeline assumes, one that CloudFormation assumes). For deployments to multiple Regions, add an artifact bucket (and KMS key) per Region.
- **Variants:** CDK Pipelines (bootstrap the targets with `--trust`), the StackSets deploy action for org-wide stacks, GitHub Actions with OIDC federation to IAM roles (no long-lived keys).

### Pattern B — Org-wide baseline with StackSets + Service Catalog

```text
 Management acct ── trusted access ──► CloudFormation StackSets
        │  register delegated admin (≤5)
        ▼
 Security/Platform acct (delegated admin)
   StackSet "baseline" (service-managed, auto-deploy ON, retain=false)
     targets: Root or OUs ▸ Regions: us-east-1 → eu-west-1 (sequential)
     max concurrent 10%, failure tolerance 0
        │
        ├─► every existing account: IAM roles, Config recorder, SC launch role
        └─► any NEW account moved into OU → stack instance created automatically
 Service Catalog portfolio shared via Organizations to OUs → teams self-serve
```

### Pattern C — Serverless canary with automatic rollback

```text
 CodePipeline ─► CodeBuild (sam build/package) ─► CloudFormation deploy (SAM)
                                                       │
            AutoPublishAlias: live → publishes v7      ▼
   CodeDeploy (LambdaCanary10Percent5Minutes)
     PreTraffic hook Lambda (smoke test v7)
     alias live: v6 90% / v7 10%  ── 5 min ──► v7 100%
     CloudWatch alarms (Errors, Duration p99, custom business metric)
        └─ ALARM → automatic rollback: alias back to v6 100%
```

### Pattern D — ECS blue/green with test listener

```text
           ALB  :443 (prod listener) ──► TG-Blue  (task set v1)
                :8443 (test listener) ─► TG-Green (task set v2)
  CodeDeploy (or ECS native blue/green):
   1 create green task set
   2 AfterAllowTestTraffic hook runs integration tests on :8443
   3 shift prod listener (canary 10% → 100% / linear / all-at-once)
   4 bake, alarms monitored → terminate blue after wait time (or reroute back)
```

### Pattern E — Golden AMI pipeline with immutable rollout

```text
 Image Builder pipeline (weekly + on parent image update)
   recipe: AL2023 + hardening + CW agent + app runtime
   test components ─► Inspector scan ─► distribute: 3 Regions, share to OU=Workloads
        │
        └─► SSM Parameter /golden/al2023/latest (in each Region/account)
               │ EventBridge "image available"
               ▼
   Launch template (resolve:ssm AMI) ─► ASG Instance Refresh
        MinHealthy 90%, checkpoints 20%/50%, auto-rollback on alarm
 Old AMIs → lifecycle policy deprecates after 90 days
```

### Pattern F — Feature-flag release decoupled from deployment

```text
 Code with flag "new-checkout" (default off) deployed everywhere (rolling, low risk)
 AppConfig: profile=FeatureFlags  env=prod (alarms: 5xx rate, checkout errors)
   deploy flag on → Linear20PercentEvery6Minutes, bake 30 min
   alarm fires → AppConfig rolls the flag back automatically (seconds)
 AppConfig Agent / Lambda extension caches flags locally (no per-request API cost)
```

### Pattern G — Patching & access without bastions

```text
 Quick Setup (org): DHMC + patch policy (OU=Prod, all Regions)
   Patch baseline: Security/Critical auto-approve after 7 days
   Maintenance window: Sun 02:00, 3h, cutoff 1h, concurrency 10%, error 5%
 Session Manager: VPC endpoints ssm/ssmmessages/ec2messages, logs → S3 (KMS) + CW Logs
 IAM: ssm:StartSession limited by tag (Env=Dev); no port 22 open anywhere
```

### Pattern H — Governed self-service with Service Catalog

See the diagram in §2.5. Products live in Git, are validated with cfn-guard/cfn-lint in CodePipeline, and are published as new product versions (Service Catalog deploy action). Portfolios are shared to OUs. Launch constraints remove the need for broad IAM permissions, TagOptions enforce cost tags, and AppRegistry links provisioned stacks to applications.

---

## 4. Decision tables / "X vs Y"

### 4.1 Deployment strategies compared (memorise)

| Strategy | Downtime | Rollback speed | Extra cost | Risk / blast radius | Mixed versions live? | Best for |
|---|---|---|---|---|---|---|
| All-at-once | **Yes** | Slow (redeploy) | None | **Highest**: all users hit at once | No | Dev/test, cost-sensitive, downtime acceptable |
| Rolling | No (reduced capacity) | Slow (redeploy in batches) | None | Medium | **Yes** | Fleets that tolerate reduced capacity |
| Rolling + additional batch | No | Slow | Low | Medium | Yes | Prod needing full capacity, cost-aware |
| Immutable | No | **Fast** (kill new ASG) | High (temporary 2×) | Low: new instances only | Briefly | Prod; avoid partial failures on existing instances |
| Traffic splitting (EB) | No | Fast | High (temporary) | Low: % of users | Yes (by design) | Canary testing on EB |
| Blue/green | No* | **Fastest infrastructure rollback** (switch back) | **Highest** (full duplicate environment) | Low–medium (cutover hits all users unless weighted) | No (after switch) | Major releases, platform changes, fast-rollback requirement |
| Canary | No | Fast (automatic on alarm) | Low–medium | **Very low**: small % first | Yes | Prod releases validated with real traffic |
| Linear | No | Fast (automatic on alarm) | Low–medium | Low: gradual | Yes | Slow, metric-driven rollouts |
| Shadow | No | Not applicable (users unaffected) | High (duplicate processing) | **None to users** | Not applicable | Validating performance/correctness of rewrites, ML models |
| Feature flags | No | **Seconds** (flip the flag) | Minimal | Very low, per segment | Code yes; behaviour controlled | Decoupling deploy from release, A/B tests, kill switches |

*DNS-based blue/green can leave a tail of clients on the old environment because of caching.

### 4.2 Nested stacks vs cross-stack references vs StackSets vs SSM parameters

| Need | Choose |
|---|---|
| Reuse a component inside one app, deploy as a unit, exceed 500 resources | **Nested stacks** |
| Share outputs between independently managed stacks in the same account/Region | **Exports / `Fn::ImportValue`** |
| Same stack in many accounts/Regions | **StackSets** |
| Share values across accounts/Regions, or loosely couple stacks | **SSM Parameter Store** (+ dynamic references / SSM parameter types) |
| Reusable vetted fragment across many templates | **CloudFormation modules** (or CDK constructs) |

### 4.3 StackSets permission models

| Requirement | Self-managed | Service-managed |
|---|---|---|
| Target accounts outside the Organization | Yes | No |
| Auto-deploy to new accounts in an OU | No | **Yes** |
| No manual IAM role creation | No | **Yes** |
| Template uses macros/transforms (e.g., SAM) | Yes | No |
| Deploy into the management account | Yes | No |
| Administer from a member account | Yes (any account) | Yes (delegated admin, up to 5) |

### 4.4 IaC tool selection

| | CloudFormation | CDK | SAM | Terraform | Service Catalog |
|---|---|---|---|---|---|
| Authoring | YAML/JSON | Programming languages | YAML shorthand (CFN superset) | HCL | Wraps CFN/Terraform products |
| State | Managed by AWS | CloudFormation | CloudFormation | **You manage it** (S3 + locking) | CloudFormation / engine |
| Multi-cloud | No (third-party registry types are partial) | No | No | **Yes** | No |
| Best for | Baselines, StackSets, governance | Developer-centric teams, complex logic, reusable constructs | Serverless apps, safe Lambda deploys, local testing | Existing Terraform shops, multi-cloud | End-user self-service with guardrails |

### 4.5 CodeDeploy EC2: in-place vs blue/green

| | In-place | Blue/green |
|---|---|---|
| Instances | Same instances updated | New instances (copy of ASG, or pre-provisioned) |
| Capacity during deploy | Reduced (per deployment config) | Full |
| Rollback | Redeploy old revision (slow) | Reroute traffic to original instances (fast, if kept) |
| On-premises support | **Yes** | **No** (EC2 only) |
| Cost | None extra | Temporary duplicate fleet |

### 4.6 Proactive vs detective compliance for IaC

| Control | When | Blocks? | Example |
|---|---|---|---|
| cfn-guard / cfn-lint / cdk-nag in CI | Pre-deploy (pipeline) | Fails the build | "S3 buckets must have encryption" |
| CloudFormation Hooks (Guard/Lambda/custom/Control Tower proactive) | At provisioning, server-side | Yes (FAIL) or warn | Any CFN or Cloud Control call, even outside the pipeline |
| SCP / RCP | At API call | Yes | Deny `ec2:RunInstances` without a tag |
| AWS Config rules (+ SSM Automation remediation) | After the change | No (detects, then remediates) | Detect a public bucket and auto-fix it |

### 4.7 Parameter Store vs Secrets Manager vs AppConfig

| | Parameter Store | Secrets Manager | AppConfig |
|---|---|---|---|
| Primary use | Config values, simple secrets | Credentials that need **rotation** | Dynamic config and feature flags with safe rollout |
| Rotation | No native rotation | **Built-in** (Lambda; managed rotation for RDS, Redshift, DocumentDB) | Not applicable |
| Cross-account | Advanced parameters via RAM | Resource policy | Per account |
| Validation & gradual rollout | No | No | **Yes** (validators, strategies, alarm rollback) |
| Cost | Standard tier free | Per secret per month + API calls | Per configuration request/received |

### 4.8 Where to switch traffic

| Situation | Switch at |
|---|---|
| Same Region, same ALB, need instant cutover or weights | ALB weighted target groups |
| Cross-Region, whole-environment swap, different load balancers | Route 53 weighted/failover records (lower TTL beforehand) |
| Lambda | Alias weights (CodeDeploy) |
| ECS service | CodeDeploy, or ECS native blue/green/canary/linear |
| API Gateway REST API | Stage **canary release** settings |
| CloudFront configuration change | **Continuous deployment** staging distribution |
| Database engine upgrade | **RDS/Aurora Blue/Green** switchover |
| Behaviour within code | AppConfig feature flag |

---

## 5. Exam keyword → answer cheat list

| Stem says… | Think… |
|---|---|
| "Deploy to all current **and future** accounts in an OU" | Service-managed **StackSets + automatic deployment** |
| "Management account should not be used for daily operations" | **Delegated administrator** (StackSets, Service Catalog, Systems Manager) |
| "Users must launch resources **without permissions** to the underlying services" | **Service Catalog launch constraint** |
| "Restrict the instance types users can select in a product" | **Template constraint** |
| "Enforce consistent cost tags at launch" | **TagOptions** (+ tag policies) |
| "Preview the impact before updating the production stack" | **Change set** (+ manual approval) |
| "Prevent accidental replacement of the DB during stack updates" | **Stack policy** denying `Update:Replace` + `UpdateReplacePolicy: Snapshot/Retain` |
| "Keep the data if the stack is deleted" | `DeletionPolicy: Retain` or `Snapshot` |
| "Prevent stack deletion" | **Termination protection** |
| "Roll back the stack update if the error rate rises after deploy" | **Rollback triggers** with CloudWatch alarms + monitoring time |
| "Stack shows complete before the software is installed" | **CreationPolicy + cfn-signal** (with cfn-init) |
| "Update instance config on stack update without replacement" | **cfn-hup** |
| "Resource type not supported by CloudFormation / call an external API" | **Lambda-backed custom resource** (or a registry resource type) |
| "Block non-compliant resources before provisioning" | **CloudFormation Hooks** / Guard / Control Tower proactive controls |
| "Generate templates from existing resources" | **IaC generator** (then import, or `cdk migrate`) |
| "Manual console changes need to be detected" | **Drift detection** |
| "Secret must not appear in the template or console" | **Dynamic reference** to Secrets Manager / `ssm-secure` |
| "Developers prefer TypeScript/Python for infrastructure" | **CDK** (L2/L3 constructs) |
| "Pipeline should update itself when the pipeline code changes" | **CDK Pipelines** (self-mutating) |
| "Serverless app; gradual traffic shifting; automatic rollback; minimal effort" | **SAM DeploymentPreference** (CodeDeploy canary/linear) |
| "Existing Terraform; shared state; prevent concurrent applies" | **S3 backend + locking** (DynamoDB, or the native S3 lockfile) |
| "Pipeline in one account deploys into others" | Cross-account roles + **CMK** + **bucket policy** |
| "Start the pipeline only on release tags / when specific folders change" | **CodePipeline V2 triggers** with filters |
| "Manual sign-off before prod" | **Manual approval** action (SNS notification) |
| "No downtime, fastest rollback, cost not a concern" | **Blue/green** |
| "No downtime, minimal extra cost, can tolerate reduced capacity" | **Rolling** |
| "Full capacity maintained, minimal extra cost" | **Rolling with additional batch** |
| "If the deployment fails, it must not affect existing instances" | **Immutable** |
| "Test the new version with a small % of real users first" | **Canary** (CodeDeploy / EB traffic splitting / API Gateway canary) |
| "Users still reach the old version after cutover" | **DNS caching/TTL** → lower the TTL beforehand, or use ALB weighted target groups |
| "Turn features on/off without redeploying, per segment" | **AppConfig feature flags** |
| "Validate configuration before rollout; roll back on alarm" | **AppConfig validators + deployment strategy + alarms** |
| "Upgrade the DB engine major version with minimal downtime and quick rollback" | **RDS Blue/Green Deployments** |
| "Standardised hardened AMIs across accounts/Regions, scanned for CVEs" | **EC2 Image Builder** (distribution + Inspector + lifecycle policies) |
| "Run a script across thousands of instances, no SSH" | **SSM Run Command** (rate controls) |
| "Keep config enforced on new instances automatically" | **State Manager association** |
| "Replace bastion hosts; audit sessions" | **Session Manager** (+ S3/CloudWatch Logs) |
| "Patch during a specific window, with an approval delay" | **Patch Manager baseline + maintenance window** (patch policy for the org) |
| "Enable SSM on all instances org-wide quickly, no instance profiles" | **Quick Setup + DHMC** |
| "Store and proxy npm/PyPI packages privately, block dependency confusion" | **CodeArtifact** (upstreams, package origin controls, VPC endpoints) |
| "Git repos in GitHub/GitLab/Bitbucket as the pipeline source" | **CodeConnections** |
| "Platform team templates for developer self-service (Proton)" | Proton is **discontinued (end of support Oct 2026)** → Service Catalog / CDK constructs / Git sync |

---

## 6. Traps & distractors

1. **"Use nested stacks to share a VPC across teams' independent stacks."** Nested stacks couple lifecycles. Independent team stacks use **exports** or **SSM parameters**.
2. **"Use exports to share values with another Region or account."** Exports work in the **same account and Region only**.
3. **"DeletionPolicy protects against replacement."** No. Replacement needs **`UpdateReplacePolicy`**; protection from updates needs a **stack policy**.
4. **"A stack policy prevents deletion."** No. Use **termination protection** and IAM/SCPs.
5. **"Self-managed StackSets auto-deploy to new accounts."** Only **service-managed** StackSets support automatic deployment.
6. **"Service-managed StackSets deploy to the management account."** They don't. Manage that account separately.
7. **"Use the default AWS managed KMS key for cross-account pipeline artifacts."** AWS managed key policies can't be edited to grant other accounts. You need a **customer-managed key**.
8. **"Give developers AdministratorAccess so they can launch Service Catalog products."** The point of a **launch constraint** is that they don't need it.
9. **"A Route 53 weighted switch gives instant rollback."** DNS caching makes it gradual and uncertain. Switching at the ALB is instant.
10. **"CodeDeploy blue/green for on-premises servers."** Blue/green is **EC2 only**; on-premises is in-place only.
11. **"Lambda canary via Route 53 weighted records."** Lambda traffic shifting uses **alias weights**.
12. **"EB rolling deployment gives the fastest rollback."** Rollback means redeploying. **Immutable** and **blue/green** roll back fastest.
13. **"Use all-at-once to save cost in production with a zero-downtime requirement."** All-at-once causes downtime.
14. **"Blue/green solves database schema changes automatically."** A shared DB needs **backward-compatible** migrations. RDS Blue/Green handles engine/parameter changes and only replication-compatible schema changes.
15. **"Rebuild instances with UserData on each deploy to avoid drift"** when the stem asks for fastest scale-out. Use a **golden AMI** ("bake, don't fry").
16. **"Open SSH from a bastion for patching."** Use **Session Manager / Patch Manager**, with no inbound ports.
17. **"Store the DB password as a NoEcho parameter default."** Defaults are visible in the template. Use **dynamic references** or `ManageMasterUserPassword`.
18. **"An AWS Config rule prevents the resource from being created."** Config is **detective**. Prevention means SCPs, Hooks or Guard.
19. **"Use AWS Proton / CodeStar / Cloud9 for a new platform."** Proton reached end of support in Oct 2026, CodeStar was discontinued in 2024, and Cloud9 closed to new customers in 2024. Don't choose them for new designs. (CodeCommit, by contrast, is **GA again since Nov 2025**.)
20. **"Drift detection automatically fixes drift."** It only reports.
21. **"CDK deploys directly via API calls."** CDK synthesises CloudFormation (hotswap is for dev only).
22. **"Use cfn-hup to signal stack completion."** cfn-hup handles metadata updates; **cfn-signal** sends the signal.
23. **"Manual approval waits indefinitely."** It times out after **7 days**.
24. **"Rollback triggers fire on INSUFFICIENT_DATA."** Only if the alarm treats missing data as breaching.

---

## 7. Professional architect focus

- **Deploy ≠ release.** Use feature flags to ship continuously and release deliberately; it is the cheapest way to reduce blast radius. Combine with canary for infrastructure-level risk.
- **Rollback is a design requirement, not an afterthought.** Ask stakeholders, "What is the acceptable time to recover from a bad release?" That answer picks the strategy: seconds → flags/alias weights; minutes → blue/green or canary; hours → rolling.
- **Stateful components dominate the risk.** Enforce expand/contract migration discipline, separate DB migration steps, set `DeletionPolicy`/`UpdateReplacePolicy` on every stateful resource, and keep AWS Backup independent of IaC.
- **Pipelines are production systems.** Put them in a dedicated tooling account; use OIDC and short-lived credentials, least-privilege deployment roles per stage, signed artifacts (AWS Signer for Lambda code signing and container image signing), and SBOMs. Require human approvals only where they add value; automate gates first (tests, Guard, alarms, bake times).
- **Policy as code at three layers:** CI (Guard/cdk-nag), provisioning (Hooks/proactive controls), runtime (Config + SCP/RCP). Stem phrases like "before provisioning" vs "detect" tell you the layer.
- **Multi-account scale:** use StackSets, Quick Setup and Service Catalog sharing with delegated admins; avoid per-account snowflakes. Plan **Region order** and failure tolerance for org-wide rollouts, because one bad StackSet update can break every account.
- **Immutable everything:** golden AMIs and containers built with Image Builder, instance refresh for rollout, Session Manager for break-glass access only. Measure drift (Config, drift detection) and treat drift as an incident.
- **Choose the simplest managed option:** SAM over hand-wired CodeDeploy for Lambda; Elastic Beanstalk for small teams that want managed policies; ECS native deployments when CodeDeploy adds nothing.
- **Watch service lifecycle announcements:** Proton (end of support Oct 2026), Change Manager (closed to new customers Nov 2025), CloudWatch Evidently (feature flags → AppConfig), CodeCommit (back to GA). Re-validate tooling choices every year.
- **Cost conversations:** blue/green doubles capacity during the overlap; canary and flags are cheaper; CodePipeline V2 per-minute pricing favours many infrequently run pipelines; Image Builder itself is free.

> **Emerging / SAP-C03 preview (not core for SAP-C02):** AWS **Fault Injection Service** experiments as a pipeline stage (chaos testing before prod), **Resilience Hub** policy checks in CI/CD, agentic coding assistants in the SDLC, and **Route 53 ARC** for controlled Regional cutovers.

---

## 8. Skills checklist

- [ ] I can name every CloudFormation template section and pick the right one for a need (Mappings vs Parameters vs Conditions vs Rules).
- [ ] I can explain change sets, replacement behaviour, rollback triggers and ContinueUpdateRollback.
- [ ] I can choose between DeletionPolicy, UpdateReplacePolicy, stack policy and termination protection.
- [ ] I can explain CreationPolicy/cfn-signal vs WaitCondition, and the roles of cfn-init and cfn-hup.
- [ ] I know when to use a Lambda-backed custom resource vs a registry resource type vs a module vs a macro.
- [ ] I can describe Hooks, Guard and Control Tower proactive controls and how they differ from Config rules and SCPs.
- [ ] I can use IaC generator, resource import and drift detection to bring existing resources under control.
- [ ] I can compare nested stacks, exports, StackSets and SSM parameters for sharing values.
- [ ] I can configure StackSets: self- vs service-managed, auto-deployment, delegated admin, concurrency, failure tolerance, Region order, retain stacks.
- [ ] I can explain CDK construct levels, bootstrapping and CDK Pipelines, and SAM DeploymentPreference.
- [ ] I can set up Terraform remote state with S3 and locking.
- [ ] I can design a Service Catalog portfolio with launch/template constraints, TagOptions and org sharing.
- [ ] I can design a cross-account, cross-Region CodePipeline (CMK, bucket policy, roles, regional artifact stores).
- [ ] I know the CodePipeline V2 features (triggers/filters, variables, execution modes, stage conditions/rollback).
- [ ] I know CodeDeploy deployment types and configs for EC2, ECS and Lambda, the lifecycle hooks, and alarm-based rollback.
- [ ] I can fill in the deployment-strategy comparison table from memory (downtime, rollback, cost, risk).
- [ ] I know the EB deployment policies and how URL-swap blue/green works.
- [ ] I can explain DNS- vs ALB-based traffic shifting and the DNS caching caveat.
- [ ] I can plan backward-compatible schema migrations and use RDS Blue/Green.
- [ ] I can build a golden AMI pipeline with Image Builder and roll it out with instance refresh.
- [ ] I can map Systems Manager capabilities (Run Command, State Manager, Automation, Parameter Store, Distributor, Patch Manager, Maintenance Windows, Session Manager, Fleet Manager, Quick Setup) to scenarios.
- [ ] I can design AppConfig feature-flag rollouts with validators, strategies and alarm rollback.
- [ ] I know the current status of CodeCommit (GA), Proton (end of support) and Change Manager (closed to new customers).

---

## 9. Practice questions

> Original SAP-C02-style questions (not real exam questions). Answers are in the next subsection.

**Q1.** A financial services company runs 240 AWS accounts in AWS Organizations, grouped into OUs by business unit. The security team must deploy a standard set of IAM roles, an AWS Config conformance pack and an Amazon EventBridge rule to every account in two Regions. New accounts are created weekly through AWS Control Tower and must receive the baseline within an hour, without anyone from the security team taking action. Company policy forbids using the management account for routine operational tasks. The security team works from a dedicated security tooling account. Which solution meets these requirements with the LEAST operational overhead?

- A. Create a CloudFormation StackSet with self-managed permissions in the security tooling account. Use a StackSet to create `AWSCloudFormationStackSetExecutionRole` in every account, and use an EventBridge rule on `CreateManagedAccount` events to invoke a Lambda function that adds stack instances for new accounts.
- B. Activate trusted access for CloudFormation StackSets in Organizations, register the security tooling account as a delegated administrator, and create a StackSet with service-managed permissions that targets the relevant OUs with automatic deployment enabled.
- C. In the management account, create a StackSet with service-managed permissions targeting the organization root with automatic deployment enabled, and grant the security team a cross-account role in the management account to manage it.
- D. Publish the baseline as an AWS Service Catalog product, share the portfolio with all OUs, and require each account owner to launch the product as part of account onboarding.

**Q2.** A company's platform team runs AWS CodePipeline in a central tooling account (111111111111) in `us-east-1`. The pipeline must deploy CloudFormation stacks into a production account (222222222222) in the same Region. The first test run fails: the CloudFormation action in the production account cannot read the input artifact from the pipeline's S3 artifact bucket, which uses the default encryption configuration of the pipeline. Which combination of actions will allow the pipeline to deploy to the production account? **(Select THREE.)**

- A. Create a customer managed AWS KMS key in the tooling account, configure the pipeline's artifact store to use it, and grant the production account's roles permission to use the key in the key policy.
- B. Add a statement to the artifact bucket policy in the tooling account that allows the production account's cross-account role to get and put objects.
- C. Create an IAM role in the production account that trusts the pipeline's service role, has access to the artifact bucket and KMS key, and set it as the `roleArn` of the deploy action; pass a CloudFormation deployment role in the production account as the action's `RoleArn`.
- D. Edit the key policy of the AWS managed `aws/s3` key in the tooling account to allow the production account to decrypt artifacts.
- E. Enable S3 Cross-Region Replication from the artifact bucket to a new bucket in the production account and point the deploy action at the replicated bucket.
- F. Create a VPC peering connection between the tooling and production accounts so that the deploy action can reach the artifact bucket privately.

**Q3.** A media company runs an API built from 35 AWS Lambda functions behind Amazon API Gateway, defined in AWS SAM templates and deployed by AWS CodePipeline. Recent releases caused elevated 5XX errors that took 40 minutes to notice and roll back manually. The company wants each function release to receive 10% of production traffic first, then the remainder after 10 minutes if no errors are detected, with automatic rollback when error alarms fire. The solution must require the LEAST custom development. What should a solutions architect recommend?

- A. Publish a new Lambda version on each release and create Route 53 weighted records that send 10% of traffic to an API Gateway stage that invokes the new versions.
- B. Add `AutoPublishAlias` and a `DeploymentPreference` of type `Canary10Percent10Minutes` with CloudWatch alarms on errors to each function in the SAM template, and have API Gateway integrate with the alias.
- C. Configure API Gateway canary release settings on the production stage to send 10% of requests to a canary stage, and write a Step Functions workflow that monitors CloudWatch metrics and promotes or deletes the canary.
- D. Use AWS AppConfig feature flags to route 10% of invocations to the new code path inside each function and configure an AppConfig deployment strategy with alarm-based rollback.

**Q4.** A global retailer wants application teams in 60 accounts to provision standard environments (an Auto Scaling group behind an ALB and an Amazon RDS database) on demand. The cloud center of excellence (CCoE) requires that developers do not receive IAM permissions to create EC2, RDS, or IAM resources directly; that only `m6i` and `r6i` instance families can be selected in non-production; and that every provisioned environment carries a `CostCenter` tag whose value is chosen from an approved list. The CCoE manages everything from a shared services account that is a delegated administrator for AWS Service Catalog. Which combination of steps meets these requirements? **(Select THREE.)**

- A. Add a launch constraint to each product in the portfolio that specifies a local IAM role name, and deploy that role to every member account with a StackSet.
- B. Add a template constraint to the products in the non-production portfolio that restricts the instance type parameter to the `m6i` and `r6i` families.
- C. Create TagOptions for `CostCenter` with the approved values and associate them with the portfolio.
- D. Attach the `PowerUserAccess` managed policy to the developer roles so they can create the resources defined in the product templates.
- E. Use an SCP to deny `ec2:RunInstances` unless the instance type is `m6i` or `r6i` in all accounts.
- F. Share the CloudFormation templates through an S3 bucket and require developers to deploy them with their own credentials using the AWS CLI.

**Q5.** A healthcare company manages a production stack with AWS CloudFormation. The stack contains an Amazon RDS for PostgreSQL DB instance, Auto Scaling groups and Lambda functions. During a recent update, an engineer changed a property that forced replacement of the DB instance; the change was caught in review only by chance. The company needs guardrails so that (1) stack updates can never replace or delete the database unless a senior engineer explicitly overrides the protection for that update, and (2) if the database is ever replaced or removed from the template, a final copy of the data is preserved. Which combination of actions should a solutions architect take? **(Select TWO.)**

- A. Apply a stack policy that denies `Update:Replace` and `Update:Delete` on the DB instance's logical ID and allows `Update:*` on all other resources; senior engineers can supply a temporary overriding stack policy during an update.
- B. Set `DeletionPolicy: Snapshot` and `UpdateReplacePolicy: Snapshot` on the DB instance resource.
- C. Enable termination protection on the stack.
- D. Configure a rollback trigger with a CloudWatch alarm on the `DatabaseConnections` metric.
- E. Enable drift detection on the stack and schedule it to run daily.

**Q6.** A company runs a customer-facing web application on AWS Elastic Beanstalk with 20 instances. Requirements for the deployment process are: no reduction in serving capacity during deployments; a failed deployment must not leave any existing instance running a partially installed version; rollback after a failed deployment must be quick; and cost must be lower than maintaining a second full environment for days. Releases happen twice a week. Which deployment policy should the company use?

- A. Rolling
- B. Rolling with additional batch
- C. Immutable
- D. Blue/green deployment with a cloned environment and Swap environment URLs, keeping the old environment for one week

**Q7.** An e-commerce company performs blue/green releases by deploying a new stack (new Application Load Balancer and Auto Scaling group) for each release and changing a Route 53 alias record from the old ALB to the new ALB. The record has a TTL of 300 seconds on the CNAME used by partners. After each cutover, a significant share of traffic continues to reach the old environment for several hours, and when a release must be rolled back, it takes just as long for traffic to return. Both environments are in the same Region and VPC. The company wants traffic shifts and rollbacks to take effect immediately and also wants the option to send a small percentage of traffic to the new version first. Which solution meets these requirements?

- A. Lower the record TTL to 0 seconds and keep switching the alias record between the two ALBs.
- B. Use a single long-lived ALB with two target groups (blue and green) and shift traffic with weighted forward actions on the listener rule.
- C. Replace the alias record with Route 53 weighted records pointing to both ALBs and adjust weights during releases.
- D. Place Amazon CloudFront in front of both ALBs and use origin failover to move traffic to the new environment.

**Q8.** A SaaS provider runs Amazon RDS for MySQL 8.0 Multi-AZ with two read replicas supporting a 24/7 application. The company must upgrade to a newer major version and change several parameters. Requirements: test the upgraded database with production-like data before cutover, keep the database endpoints unchanged so that no application configuration changes are needed, limit write downtime to about a minute, and be able to compare against the old environment after cutover. Which approach meets these requirements with the LEAST operational effort?

- A. Take a snapshot, restore it to a new DB instance on the new version, use AWS DMS for ongoing replication, and update the application's connection strings at cutover.
- B. Create an Amazon RDS Blue/Green Deployment specifying the new engine version and parameter group, test the green environment, and perform a switchover.
- C. Promote one read replica, upgrade it in place, and repoint the application to the promoted instance.
- D. Modify the primary DB instance to the new major version during a maintenance window; Multi-AZ will keep downtime under a minute.

**Q9.** A manufacturing company operates 3,000 Amazon EC2 instances (Windows and Linux) across 45 accounts and four Regions. Administrators currently connect through bastion hosts with SSH and RDP, and patching is performed manually. The security team requires removing all inbound management ports, logging every interactive session to a central location, and applying security patches automatically during a weekly window, with critical patches approved seven days after release. Many instances were launched without an instance profile. Which combination of steps meets these requirements with the LEAST operational overhead? **(Select TWO.)**

- A. Use Systems Manager Quick Setup from the delegated administrator account to enable Default Host Management Configuration and create a patch policy across the organization that uses a custom patch baseline with a seven-day auto-approval delay and a weekly schedule.
- B. Use AWS Systems Manager Session Manager (and Fleet Manager for RDP) for interactive access, configure session logging to an encrypted central S3 bucket and CloudWatch Logs, add VPC endpoints for private subnets, and remove inbound SSH/RDP rules.
- C. Create an Image Builder pipeline that produces patched AMIs weekly and replace every instance weekly by terminating it.
- D. Deploy EC2 Instance Connect Endpoint in every VPC and keep the bastion security groups for RDP.
- E. Write a Lambda function in each account that runs weekly, describes instances, and sends patch commands through SSH using keys stored in Secrets Manager.

**Q10.** A ride-sharing company wants to release a new pricing algorithm. The code is deployed to all containers but must stay disabled until product managers enable it. They want to enable it gradually, for 20% of users every 6 minutes, keep a given rider on the same experience throughout the rollout, validate that the configuration document is well formed before it is deployed, and automatically revert within seconds if a CloudWatch alarm on failed ride requests fires. Which solution meets these requirements with the LEAST operational overhead?

- A. Store the flag in Systems Manager Parameter Store and have each container poll the parameter every minute; use a Lambda function to update the parameter in steps and revert it when an alarm fires.
- B. Use AWS AppConfig feature flags with a JSON Schema validator, the `AppConfig.Linear20PercentEvery6Minutes` deployment strategy, a CloudWatch alarm attached to the environment, and the AppConfig Agent with entity-based gradual deployment.
- C. Deploy two ECS services (with and without the feature) and use CodeDeploy linear traffic shifting of 10% every 3 minutes with alarm-based rollback.
- D. Use Route 53 weighted records to send 20% of riders to a separate environment with the feature enabled, increasing the weight every 6 minutes.

### Answers & explanations

<details><summary>Show answer — Q1</summary>

**Correct: B.**

- **Why B:** Service-managed permissions with **automatic deployment** to target OUs deploy the baseline to every existing account and to any new account added to those OUs, with no human action. Registering the security tooling account as a **delegated administrator** (up to five are allowed) lets the team manage org-wide StackSets without using the management account. StackSets creates the required IAM roles itself.
- **A:** Self-managed StackSets don't support automatic deployment. You would have to build and run custom automation (EventBridge + Lambda) and manage execution roles yourself, which is more overhead.
- **C:** Technically works, but it violates the policy against using the management account for routine operations.
- **D:** Service Catalog depends on each account owner taking action, so it fails "without anyone taking action" and the one-hour SLA.
- **Reference:** https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/stacksets-orgs-delegated-admin.html · https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/stacksets-concepts.html
</details>

<details><summary>Show answer — Q2</summary>

**Correct: A, B, C.**

- **Why:** Cross-account CodePipeline actions need three things: (1) a **customer managed KMS key** for the artifact store, with a key policy that lets the other account use it; (2) an **artifact bucket policy** that grants the other account's role access; and (3) a **cross-account role** in the target account that the pipeline service role can assume (`roleArn` on the action). For CloudFormation actions, add a deployment role in the target account that CloudFormation itself assumes (`RoleArn`).
- **D:** The key policy of an AWS managed key can't be modified, so it can't be shared cross-account. That's why a customer managed key is needed.
- **E:** Replication adds cost and complexity and doesn't fix the KMS permissions. CodePipeline reads artifacts from its own artifact store.
- **F:** S3 access is not a network-routing problem, and VPC peering doesn't grant IAM, bucket policy or KMS permissions.
- **Reference:** https://docs.aws.amazon.com/codepipeline/latest/userguide/pipelines-create-cross-account.html
</details>

<details><summary>Show answer — Q3</summary>

**Correct: B.**

- **Why B:** SAM's `AutoPublishAlias` publishes a new version on each deploy. `DeploymentPreference` creates a CodeDeploy deployment that shifts the alias with the predefined `Canary10Percent10Minutes` configuration and rolls back automatically when the listed CloudWatch alarms fire. API Gateway invokes the alias ARN. It's declarative, with no custom code.
- **A:** Route 53 weights apply to DNS endpoints, not to Lambda versions. DNS caching makes the split imprecise, and nothing rolls back automatically.
- **C:** API Gateway canary releases work at the stage level, but the promotion/rollback logic would be custom (a Step Functions workflow), which is more development. It also covers all 35 functions as one unit rather than per function.
- **D:** Feature flags need code changes in every function to branch on the flag. That's a different problem (releasing features), not version traffic shifting, and it's more development.
- **Reference:** https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/automating-updates-to-serverless-apps.html · https://docs.aws.amazon.com/codedeploy/latest/userguide/deployment-configurations.html
</details>

<details><summary>Show answer — Q4</summary>

**Correct: A, B, C.**

- **A:** A **launch constraint** makes Service Catalog assume a launch role to provision the product, so developers need only Service Catalog end-user permissions. Specifying a **local role name** rather than an ARN makes the constraint work in every account the portfolio is shared with, as long as a role with that name exists in each account (deployed with a StackSet).
- **B:** A **template constraint** restricts parameter values (instance types) per portfolio without changing the product template.
- **C:** **TagOptions** give users a controlled list of tag keys and values that are applied to provisioned products.
- **D:** PowerUserAccess grants exactly the direct permissions the CCoE wants to avoid.
- **E:** An SCP applied to all accounts would also restrict production and other teams. It's a blunt control that doesn't address self-service provisioning or tagging.
- **F:** Developers deploying with their own credentials need broad permissions, and nothing is governed.
- **Reference:** https://docs.aws.amazon.com/servicecatalog/latest/adminguide/constraints-launch.html · https://docs.aws.amazon.com/servicecatalog/latest/adminguide/catalogs_constraints_template-constraints.html · https://docs.aws.amazon.com/servicecatalog/latest/adminguide/tagoptions.html
</details>

<details><summary>Show answer — Q5</summary>

**Correct: A, B.**

- **A:** A **stack policy** blocks the update actions you specify (`Update:Replace`, `Update:Delete`) on specific resources during stack updates. It can be overridden for a single update by supplying a temporary policy, which is the "senior engineer explicit override".
- **B:** `UpdateReplacePolicy: Snapshot` keeps a snapshot of the old instance if a replacement ever happens. `DeletionPolicy: Snapshot` takes a final snapshot if the resource is removed from the template or the stack is deleted. You need both, because DeletionPolicy alone does not cover replacement.
- **C:** Termination protection stops the **stack** from being deleted. It does nothing about updates that replace or delete individual resources.
- **D:** Rollback triggers react to alarms after resources change. A replaced database would already have been recreated, and the trigger is unrelated to preventing replacement.
- **E:** Drift detection reports out-of-band changes. It doesn't prevent template-driven replacement.
- **Reference:** https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/protect-stack-resources.html · https://docs.aws.amazon.com/AWSCloudFormation/latest/TemplateReference/aws-attribute-updatereplacepolicy.html · https://docs.aws.amazon.com/AWSCloudFormation/latest/TemplateReference/aws-attribute-deletionpolicy.html
</details>

<details><summary>Show answer — Q6</summary>

**Correct: C.**

- **Why C:** An **immutable** deployment launches a full set of new instances in a temporary Auto Scaling group, so capacity is never reduced and existing instances are never modified. If the deployment fails, Elastic Beanstalk terminates the new instances, which is a fast rollback. The extra cost lasts only for the duration of the deployment.
- **A:** Rolling reduces capacity during deployment and updates existing instances in place. A failure leaves mixed or partially installed versions, and rollback needs another deployment.
- **B:** Rolling with an additional batch keeps capacity, but it still updates existing instances in place in later batches, so a failure can leave existing instances partially updated. Rollback is a redeploy.
- **D:** Blue/green meets the technical needs, but keeping a second full environment for a week twice a week means paying for nearly two environments all the time, which contradicts the cost requirement.
- **Reference:** https://docs.aws.amazon.com/elasticbeanstalk/latest/dg/using-features.rolling-version-deploy.html · https://docs.aws.amazon.com/elasticbeanstalk/latest/dg/environmentmgmt-updates-immutable.html
</details>

<details><summary>Show answer — Q7</summary>

**Correct: B.**

- **Why B:** With **weighted target groups** on one ALB listener, the traffic split changes the moment the rule is updated. DNS isn't involved, so resolver and client caching don't matter, and rollback is equally instant. Weights also allow canary-style percentages (for example 95/5), and target group stickiness can keep users on one version during the shift.
- **A:** Many resolvers and clients (for example JVM DNS caches) don't honour very low TTLs, so the long tail stays. A TTL of 0 also increases query volume and cost. It still can't do percentage shifts.
- **C:** Weighted records allow percentages, but they are still DNS-based and subject to the same caching delays for shifts and rollbacks.
- **D:** CloudFront origin failover is triggered by origin errors. It is not a controlled, weighted release mechanism.
- **Reference:** https://docs.aws.amazon.com/elasticloadbalancing/latest/application/load-balancer-listeners.html · https://docs.aws.amazon.com/whitepapers/latest/blue-green-deployments/welcome.html
</details>

<details><summary>Show answer — Q8</summary>

**Correct: B.**

- **Why B:** **RDS Blue/Green Deployments** copy the full topology (Multi-AZ and read replicas) into a green environment with the new engine version and parameter group, kept in sync through replication. You test green, then **switch over**: typically under a minute, guarded by built-in checks, with names and endpoints swapped so applications need no changes. The old environment is kept (renamed `-old1`) for comparison.
- **A:** This works, but it is far more effort (DMS tasks, monitoring) and requires changing connection strings, which violates a requirement.
- **C:** Promoting a replica breaks replication, loses writes made after promotion unless you take extra steps, requires repointing the application, and doesn't preserve the topology.
- **D:** An in-place major version upgrade takes both Multi-AZ instances down for the upgrade (Multi-AZ doesn't hide major upgrades), downtime can be long, there is no pre-cutover test with live data, and rollback means a snapshot restore.
- **Reference:** https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/blue-green-deployments-overview.html
</details>

<details><summary>Show answer — Q9</summary>

**Correct: A, B.**

- **A:** Quick Setup can enable **Default Host Management Configuration**, which makes instances managed nodes without an instance profile, and create an org-wide **patch policy** with a custom baseline (seven-day auto-approval for critical/security patches) and a weekly schedule across accounts and Regions. That is the lowest-overhead way to automate patching.
- **B:** **Session Manager** gives shell and port-forwarding access, and **Fleet Manager** gives RDP, with no inbound ports or bastions. Sessions are logged to S3/CloudWatch Logs centrally and encrypted. VPC interface endpoints support private subnets.
- **C:** Weekly AMI rebuilds and wholesale instance replacement are a valid immutable pattern, but much heavier for 3,000 mixed and possibly stateful instances. They also don't address interactive access or session logging.
- **D:** EC2 Instance Connect Endpoint helps with SSH/RDP without public IPs, but keeping bastion rules contradicts "remove all inbound management ports". It doesn't log sessions the way Session Manager does, and it doesn't patch.
- **E:** Custom Lambda over SSH needs open ports, key management, and code in 45 accounts. It's high overhead and less secure.
- **Reference:** https://docs.aws.amazon.com/systems-manager/latest/userguide/quick-setup-patch-manager.html · https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager.html · https://docs.aws.amazon.com/systems-manager/latest/userguide/fleet-manager.html
</details>

<details><summary>Show answer — Q10</summary>

**Correct: B.**

- **Why B:** AppConfig **feature flags** let you ship code dark and enable it at runtime. A **validator** (JSON Schema) blocks malformed configuration. The predefined **`AppConfig.Linear20PercentEvery6Minutes`** strategy matches the rollout cadence. An environment **CloudWatch alarm** triggers automatic rollback during deployment and bake time. The **AppConfig Agent's entity-based gradual deployment** keeps a rider on the same version for the whole rollout. All of this is managed, with no custom code.
- **A:** Parameter Store has no validation, gradual rollout, per-user consistency or alarm rollback, so all of it would be custom Lambda logic.
- **C:** It requires two services and traffic shifting at the request level, so the same rider could hit different versions. The cadence doesn't match the requirement, and this is a deployment strategy rather than a feature release.
- **D:** DNS weighting has caching delays, doesn't give per-user consistency or validation, and rollback isn't "within seconds".
- **Reference:** https://docs.aws.amazon.com/appconfig/latest/userguide/appconfig-creating-deployment-strategy-predefined.html · https://docs.aws.amazon.com/appconfig/latest/userguide/appconfig-creating-deployment-strategy.html
</details>

---

## 10. References

**CloudFormation**
- CloudFormation User Guide: https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/Welcome.html
- Quotas: https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/cloudformation-limits.html
- Change sets: https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/using-cfn-updating-stacks-changesets.html
- Rollback triggers: https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/using-cfn-rollback-triggers.html
- Drift detection: https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/using-cfn-stack-drift.html
- Protect stack resources (stack policies): https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/protect-stack-resources.html
- DeletionPolicy: https://docs.aws.amazon.com/AWSCloudFormation/latest/TemplateReference/aws-attribute-deletionpolicy.html
- UpdateReplacePolicy: https://docs.aws.amazon.com/AWSCloudFormation/latest/TemplateReference/aws-attribute-updatereplacepolicy.html
- CreationPolicy: https://docs.aws.amazon.com/AWSCloudFormation/latest/TemplateReference/aws-attribute-creationpolicy.html
- cfn-signal / helper scripts: https://docs.aws.amazon.com/AWSCloudFormation/latest/TemplateReference/cfn-helper-scripts-reference.html
- Dynamic references: https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/dynamic-references.html
- Nested stacks: https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/using-cfn-nested-stacks.html
- Cross-stack references: https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/walkthrough-crossstackref.html
- StackSets concepts: https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/stacksets-concepts.html
- StackSets delegated administrator: https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/stacksets-orgs-delegated-admin.html
- Modules: https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/modules.html
- Registry: https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/registry.html
- IaC generator: https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/generate-IaC.html
- CloudFormation Hooks: https://docs.aws.amazon.com/cloudformation-cli/latest/hooks-userguide/what-is-cloudformation-hooks.html
- CloudFormation Guard: https://docs.aws.amazon.com/cfn-guard/latest/ug/what-is-guard.html

**CDK / SAM / Terraform**
- AWS CDK Developer Guide: https://docs.aws.amazon.com/cdk/v2/guide/home.html
- CDK Pipelines: https://docs.aws.amazon.com/cdk/v2/guide/cdk-pipeline.html
- AWS SAM Developer Guide: https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/what-is-sam.html
- SAM gradual deployments: https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/automating-updates-to-serverless-apps.html
- Terraform on AWS (Prescriptive Guidance): https://docs.aws.amazon.com/prescriptive-guidance/latest/terraform-aws-provider-best-practices/introduction.html

**Service Catalog**
- Administrator Guide: https://docs.aws.amazon.com/servicecatalog/latest/adminguide/introduction.html
- Launch constraints: https://docs.aws.amazon.com/servicecatalog/latest/adminguide/constraints-launch.html
- Template constraints: https://docs.aws.amazon.com/servicecatalog/latest/adminguide/catalogs_constraints_template-constraints.html
- TagOptions: https://docs.aws.amazon.com/servicecatalog/latest/adminguide/tagoptions.html
- Portfolio sharing: https://docs.aws.amazon.com/servicecatalog/latest/adminguide/catalogs_portfolios_sharing.html
- AppRegistry: https://docs.aws.amazon.com/servicecatalog/latest/arguide/intro-app-registry.html

**CI/CD**
- CodePipeline pipeline types: https://docs.aws.amazon.com/codepipeline/latest/userguide/pipeline-types-planning.html
- CodePipeline cross-account: https://docs.aws.amazon.com/codepipeline/latest/userguide/pipelines-create-cross-account.html
- CodePipeline cross-Region actions: https://docs.aws.amazon.com/codepipeline/latest/userguide/actions-create-cross-region.html
- CodePipeline quotas: https://docs.aws.amazon.com/codepipeline/latest/userguide/limits.html
- CodeBuild User Guide: https://docs.aws.amazon.com/codebuild/latest/userguide/welcome.html
- CodeDeploy deployment configurations: https://docs.aws.amazon.com/codedeploy/latest/userguide/deployment-configurations.html
- CodeDeploy AppSpec hooks: https://docs.aws.amazon.com/codedeploy/latest/userguide/reference-appspec-file-structure-hooks.html
- CodeDeploy automatic rollback: https://docs.aws.amazon.com/codedeploy/latest/userguide/deployments-rollback-and-redeploy.html
- Amazon ECS services (deployment options): https://docs.aws.amazon.com/AmazonECS/latest/developerguide/ecs_services.html
- Amazon ECS blue/green with CodeDeploy: https://docs.aws.amazon.com/AmazonECS/latest/developerguide/deployment-type-bluegreen.html
- Amazon ECS built-in linear and canary deployments (What's New): https://aws.amazon.com/about-aws/whats-new/2025/10/amazon-ecs-built-in-linear-canary-deployments/
- CodeCommit returns to GA (AWS DevOps Blog): https://aws.amazon.com/blogs/devops/aws-codecommit-returns-to-general-availability/
- CodeConnections: https://docs.aws.amazon.com/dtconsole/latest/userguide/welcome-connections.html
- CodeArtifact: https://docs.aws.amazon.com/codeartifact/latest/ug/welcome.html
- AWS Proton end of support: https://docs.aws.amazon.com/proton/latest/userguide/proton-end-of-support.html

**Deployment strategies**
- Blue/Green Deployments on AWS whitepaper: https://docs.aws.amazon.com/whitepapers/latest/blue-green-deployments/welcome.html
- Practicing CI/CD on AWS whitepaper: https://docs.aws.amazon.com/whitepapers/latest/practicing-continuous-integration-continuous-delivery/welcome.html
- Elastic Beanstalk deployment policies: https://docs.aws.amazon.com/elasticbeanstalk/latest/dg/using-features.rolling-version-deploy.html
- Elastic Beanstalk blue/green (URL swap): https://docs.aws.amazon.com/elasticbeanstalk/latest/dg/using-features.CNAMESwap.html
- Lambda aliases: https://docs.aws.amazon.com/lambda/latest/dg/configuration-aliases.html
- API Gateway canary release: https://docs.aws.amazon.com/apigateway/latest/developerguide/canary-release.html
- CloudFront continuous deployment: https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/continuous-deployment.html
- RDS Blue/Green Deployments: https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/blue-green-deployments-overview.html
- EC2 Image Builder: https://docs.aws.amazon.com/imagebuilder/latest/userguide/what-is-image-builder.html
- EC2 Auto Scaling instance refresh: https://docs.aws.amazon.com/autoscaling/ec2/userguide/asg-instance-refresh.html

**Systems Manager & AppConfig**
- Systems Manager User Guide: https://docs.aws.amazon.com/systems-manager/latest/userguide/what-is-systems-manager.html
- Patch Manager: https://docs.aws.amazon.com/systems-manager/latest/userguide/patch-manager.html
- Session Manager: https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager.html
- Quick Setup: https://docs.aws.amazon.com/systems-manager/latest/userguide/systems-manager-quick-setup.html
- Change Manager availability change: https://docs.aws.amazon.com/systems-manager/latest/userguide/change-manager-availability-change.html
- AWS AppConfig User Guide: https://docs.aws.amazon.com/appconfig/latest/userguide/what-is-appconfig.html
- AppConfig predefined deployment strategies: https://docs.aws.amazon.com/appconfig/latest/userguide/appconfig-creating-deployment-strategy-predefined.html
