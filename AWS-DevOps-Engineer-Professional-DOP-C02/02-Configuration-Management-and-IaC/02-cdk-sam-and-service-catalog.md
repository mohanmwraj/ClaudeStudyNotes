# Domain 2 · 02 · AWS CDK, AWS SAM and AWS Service Catalog

> **Exam tasks:** 2.1 (composing and deploying templates with SAM, CDK and CloudFormation; reusable governed components with Service Catalog, modules and CDK). **Principles:** P3 (desired state), P12 (managed), P14 (least privilege via launch roles).

## 1. First principle: everything compiles to CloudFormation

The CDK, SAM, Service Catalog products, Copilot and Elastic Beanstalk all end up as **CloudFormation stacks**. Two things follow:
* Everything in [01-cloudformation-deep-dive.md](01-cloudformation-deep-dive.md) still applies: change sets, rollback, drift, `DeletionPolicy`, StackSets.
* The difference between the tools is **how you author** templates and **who is allowed to launch them**.

| Tool | Authoring model | Pick it when the question says |
|---|---|---|
| **CloudFormation** | YAML/JSON, declarative | "declarative template", StackSets, the broadest compatibility |
| **AWS CDK** | Real programming languages (TypeScript, Python, Java, C#, Go) → synthesized CloudFormation | "developers want to use familiar programming languages", loops and abstractions, unit-testable infrastructure, **reusable constructs** shared as libraries |
| **AWS SAM** | CloudFormation + a transform with serverless shorthand; CLI for local testing | "serverless application", local testing of Lambda/API Gateway, **gradual Lambda deployments** |
| **AWS Service Catalog** | Approved CloudFormation (or Terraform) products in portfolios, launched by end users | "allow teams to self-provision **approved** configurations without giving them permissions to the underlying services" |
| **AWS Copilot** | CLI that builds ECS/Fargate and App Runner apps and pipelines | Quick container apps on ECS |
| **AWS App Runner** | Fully managed container or source-to-service | A simple web service with no infrastructure to manage |

## 2. AWS CDK

### 2.1 Concepts

* **Constructs** are the building blocks:
  * **L1:** `Cfn*`, a 1:1 mapping to CloudFormation;
  * **L2:** an intent-based API with safe defaults and helper methods, e.g. `bucket.grantRead(role)` writes a least-privilege policy;
  * **L3 / patterns:** whole architectures, e.g. `ApplicationLoadBalancedFargateService`.
* **App → Stacks → Constructs.** `cdk synth` produces CloudFormation templates in `cdk.out`; `cdk diff` shows the change, like a change set; `cdk deploy` deploys through CloudFormation.
* **Assets:** local files (Lambda code) and Docker images are uploaded to the **bootstrap** S3 bucket and ECR repository during deployment.
* **Bootstrapping** (`cdk bootstrap aws://ACCOUNT/REGION`) creates the `CDKToolkit` stack: a staging S3 bucket, an ECR repository, and IAM roles for deploy, file publishing, image publishing, lookup and CloudFormation execution. **Every account and Region you deploy to must be bootstrapped.** For cross-account deployments, bootstrap the target with `--trust <tooling-account>` so the pipeline account may assume the deploy roles.
* **Context and lookups:** `Vpc.fromLookup()` queries the account at synth time and caches the result in `cdk.context.json`. Commit that file so synthesis is deterministic.
* **Aspects** visit every construct and can enforce or modify, e.g. "every bucket must have encryption", or tagging. **cdk-nag** is a widely used aspect pack for compliance rules.
* **Testing:** the `assertions` module supports fine-grained assertions ("the template has a bucket with versioning") and snapshot tests. This is IaC unit testing in the CodeBuild stage.
* **Escape hatches:** when an L2 doesn't expose a property, reach the underlying L1 (`node.defaultChild`) and add overrides.

### 2.2 CDK Pipelines

* A construct that creates a CodePipeline. The pipeline **updates itself first** (the self-mutation stage), then publishes assets, then deploys **stages**, each a set of stacks for one account and Region.
* **Waves** deploy several stages in parallel, e.g. many Regions at once.
* `pre`/`post` steps add tests (`ShellStep`) and approvals (`ManualApprovalStep`).
* Exam angle: "a pipeline that deploys the CDK app to test and production accounts and updates its own definition when the pipeline code changes" → CDK Pipelines + targets bootstrapped with `--trust`.

## 3. AWS SAM

* `Transform: AWS::Serverless-2016-10-31` turns resources such as these into full CloudFormation:
  * `AWS::Serverless::Function`, `::Api`, `::HttpApi`;
  * `::SimpleTable`, `::StateMachine`, `::LayerVersion`;
  * `::Application`, which nests an app from the **Serverless Application Repository**.
* **`Globals`** sets shared function properties (runtime, timeout, tracing, environment).
* **Policy templates** (`DynamoDBCrudPolicy`, `S3ReadPolicy`, `SQSPollerPolicy`, …) give least-privilege access to one named resource.
* **Gradual deployments:** `AutoPublishAlias` + `DeploymentPreference` (canary or linear, alarms, pre/post-traffic hooks) generate the CodeDeploy application and deployment group. See [01-SDLC-Automation/03](../01-SDLC-Automation/03-deployment-strategies.md#25-lambda-deployments).
* **CLI:**
  * `sam build`;
  * `sam local invoke` / `sam local start-api` for local testing in Docker containers;
  * `sam deploy --guided`;
  * `sam sync`: fast incremental sync for **development only**, because it bypasses CloudFormation for code changes;
  * `sam pipeline init` generates CI/CD pipeline templates.
* **Serverless Application Repository (SAR):** publish and share SAM apps (private, shared with accounts or organizations, or public), and consume them via `AWS::Serverless::Application`.

## 4. AWS Service Catalog: governed self-service

### 4.1 Model

* **Product:** a CloudFormation template (or Terraform configuration), with **versions**.
* **Portfolio:** a collection of products, plus access (IAM principals) and **constraints**.
* **Provisioned product:** what a user launched, i.e. a stack.

### 4.2 Constraints are the exam's favourite part

| Constraint | Effect |
|---|---|
| **Launch constraint** | An **IAM role that Service Catalog assumes** to provision the product. End users need permission only to Service Catalog, **not** to EC2, RDS or IAM, so they can launch approved stacks without broad rights (P14). |
| **Template constraint** | Restricts parameter values (e.g. only `t3.micro`/`t3.small`, only certain VPCs) with rules |
| **Notification constraint** | Sends stack events to an SNS topic |
| **Tag update constraint** | Whether users may update tags after provisioning |
| **StackSet constraint** | Lets a product be deployed across accounts and Regions as a stack set |

* **TagOptions** enforce tag key/value choices at launch.
* **Sharing:** a hub account shares portfolios with spoke accounts or with an **organization or OU**. In the spoke account the portfolio is imported, and local users are granted access to it.
* **Updates:** publish a new product version; users update their provisioned product, or you can deprecate old versions.
* **Control Tower's Account Factory is itself a Service Catalog product.** That's why "vend accounts through Service Catalog" appears in multi-account questions.

### 4.3 When Service Catalog is the answer

* "Developers must be able to create approved, compliant environments **without** permissions to create the underlying resources."
* "Standardize the configurations teams can launch across accounts, and update them centrally."
* "Restrict instance types and enforce tags at launch time."

## 5. Configuration-management choices (task 2.1)

| Need | Service |
|---|---|
| Keep OS and agent configuration in a desired state on fleets (EC2, on-premises) | **Systems Manager State Manager** (associations), Run Command, Automation, Patch Manager, Distributor. See [04-systems-manager-and-config.md](04-systems-manager-and-config.md) |
| Record configuration history and evaluate compliance rules | **AWS Config** |
| Application configuration and feature flags with validated, gradual rollout | **AWS AppConfig** |
| Managed Chef/Puppet | **AWS OpsWorks**: **retired** (OpsWorks Stacks end of life 2024-05-26). On the exam, recognize it as "configuration management with Chef/Puppet"; AWS's migration path is Systems Manager |

## 6. Exam traps

* **CDK deployments to a new account or Region fail with "Is this account bootstrapped?"** Run `cdk bootstrap`. Cross-account needs `--trust`.
* **`sam sync` / CDK hotswap in production:** they bypass CloudFormation's safety. Use them in development only.
* **Service Catalog without a launch constraint:** users need permissions for every underlying resource, which defeats the purpose.
* **Choosing CDK vs CloudFormation:** the CDK still deploys with CloudFormation, so drift detection, change sets and StackSets all still apply.
* **Reusable governance:**
  * CloudFormation **modules** and registry types: template building blocks.
  * **CDK constructs and aspects:** code libraries and policy checks.
  * **Service Catalog:** governed products for end users.
  * **Hooks / Guard:** enforcement at deploy time.

## References

* AWS CDK concepts — <https://docs.aws.amazon.com/cdk/v2/guide/core_concepts.html>
* CDK bootstrapping — <https://docs.aws.amazon.com/cdk/v2/guide/bootstrapping.html>
* CDK Pipelines — <https://docs.aws.amazon.com/cdk/v2/guide/cdk_pipeline.html>
* AWS SAM resource and property reference — <https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/sam-specification-resources-and-properties.html>
* SAM policy templates — <https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/serverless-policy-templates.html>
* Service Catalog constraints — <https://docs.aws.amazon.com/servicecatalog/latest/adminguide/constraints.html>
* Service Catalog launch constraints — <https://docs.aws.amazon.com/servicecatalog/latest/adminguide/constraints-launch.html>
* Service Catalog portfolio sharing — <https://docs.aws.amazon.com/servicecatalog/latest/adminguide/catalogs_portfolios_sharing.html>
