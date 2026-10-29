# Domain 1 · 02 · CodePipeline Design and Multi-Account Pipelines

> **Exam tasks:** 1.1 (CI/CD pipelines; single- and multi-account deployment patterns), 5.3 (analyzing failed pipelines). **Principles:** P1 (events), P2 (cross-account authorization), P6 (account isolation), P11 (KMS).

This is the single most heavily tested design in Domain 1: **a pipeline in a tooling account that deploys into separate test and production accounts.** Learn the four-piece permission chain in §4 until you can draw it from memory.

---

## 1. Pipeline anatomy

| Concept | What it is | Exam detail |
|---|---|---|
| **Stage** | A group of actions, e.g. Source, Build, Test, Deploy-Prod | Transitions between stages can be **disabled**: a simple "freeze" switch |
| **Action** | A unit of work run by a provider (CodeBuild, CodeDeploy, CloudFormation, ECS, Elastic Beanstalk, S3, Lambda invoke, Step Functions, manual approval, StackSets, Commands) | Actions with the same `runOrder` run **in parallel**; a higher `runOrder` runs after |
| **Artifact** | A zip in the artifact store (S3), passed between actions as named input and output artifacts | The artifact store is per Region; cross-Region actions need a bucket in each Region |
| **Variables** | Action **output** variables (with a namespace, e.g. `#{BuildVars.IMAGE_TAG}`); V2 **pipeline-level** variables set at start | CodeBuild `exported-variables` become action output variables |
| **Execution mode** (V2) | `SUPERSEDED` (default: a newer execution can overtake an older one waiting between stages); `QUEUED` (one at a time, in order); `PARALLEL` (independent executions) | "Every commit must be deployed in order" → QUEUED |
| **Service role** | The IAM role CodePipeline assumes to run actions | Needs `iam:PassRole` for roles it hands to CloudFormation or ECS, and `sts:AssumeRole` for cross-account action roles |

### 1.1 Actions you must know

* **Manual approval:**
  * Optionally publishes to an SNS topic and shows a review URL and comments.
  * If nobody responds within **7 days**, the action fails.
  * IAM controls who can approve (`codepipeline:PutApprovalResult` on that action).
  * Place it **before** production deployment, not after.
* **Lambda invoke:**
  * Runs custom logic: tests, integration with external systems, cache invalidation.
  * The function **must** call `PutJobSuccessResult` or `PutJobFailureResult` with the job ID. Otherwise the action never completes successfully and eventually times out.
* **Step Functions invoke:** for multi-step orchestration inside a stage.
* **CloudFormation deploy:** the action modes are:
  * `CREATE_UPDATE`: create or update directly;
  * `CHANGE_SET_REPLACE` then `CHANGE_SET_EXECUTE`: create a change set, review it (often with a manual approval between the two actions), then execute it;
  * `DELETE_ONLY`;
  * `REPLACE_ON_FAILURE`: delete and recreate a failed stack; dev environments only.

  Inputs: the template path in an artifact, a **template configuration** file (parameters, tags, stack policy per environment), and `RoleArn`, the **CloudFormation service role** that CloudFormation itself uses to create resources.
* **CloudFormation StackSets deploy:** deploys stack instances across accounts and Regions from a pipeline.
* **Amazon ECS (standard) deploy:**
  * Consumes `imagedefinitions.json` (container name → image URI) and performs a **rolling** update of the service.
  * **ECS (blue/green) via CodeDeploy** consumes `appspec.yaml` and `taskdef.json` plus `imageDetail.json`.
  * Mixing up the two file formats is a classic failure.
* **Elastic Beanstalk deploy:** deploys an application version to an environment using the environment's deployment policy.
* **Commands action** (V2): runs shell commands on managed compute without defining a CodeBuild project.

### 1.2 V2-only features worth knowing

* **Triggers with filters:** Git tags, branches, file paths, pull requests.
* **Pipeline-level variables.**
* The **QUEUED** and **PARALLEL** execution modes.
* **Stage rollback:** manual, or automatic on failure, to the last successful source revisions for that stage.
* **Stage conditions:**
  * **entry** conditions, e.g. a deployment window, an alarm that must be OK, or a Lambda check;
  * **on-success** conditions, e.g. after deploying, check a CloudWatch alarm and fail or roll back the stage if it's in ALARM;
  * **on-failure** conditions, e.g. retry or roll back.
* **Automatic stage retry.**

These features answer questions like "deploy only during the maintenance window" and "automatically roll back the production stage if the error alarm fires after the deployment" ([stage conditions](https://docs.aws.amazon.com/codepipeline/latest/userguide/stage-conditions.html)).

---

## 2. Starting a pipeline (P1)

| Source | Correct trigger |
|---|---|
| CodeCommit | EventBridge rule on `CodeCommit Repository State Change` (`referenceType: branch`, `referenceName: main`) → target CodePipeline (with a role that allows `codepipeline:StartPipelineExecution`) |
| GitHub / GitLab / Bitbucket | CodeConnections. Push and PR webhooks are handled by the connection; V2 trigger filters select branches, tags and paths |
| S3 | EventBridge rule on `Object Created` for the bucket and key (the bucket needs EventBridge notifications enabled, or CloudTrail data events) |
| ECR | EventBridge rule on `ECR Image Action` (`action-type: PUSH`, `result: SUCCESS`, repository, tag) |
| Schedule | EventBridge Scheduler or a scheduled rule → `StartPipelineExecution` (e.g. a nightly build) |

**Never** choose periodic polling (`PollForSourceChanges: true`) when the question asks for responsiveness or efficiency.

## 3. Observing pipelines

* EventBridge receives `CodePipeline Pipeline Execution State Change`, `CodePipeline Stage Execution State Change` and `CodePipeline Action Execution State Change`. Rule on `state: FAILED` → SNS, Chatbot or Lambda.
* **Notification rules** (Developer Tools console) send the same events to SNS or Chatbot without writing patterns.
* For "which change broke the build", look at the execution history: every execution records its source revisions.

---

## 4. The cross-account pipeline: four pieces that must all exist

**Scenario.** A pipeline in a **tooling account (T)** builds an artifact and deploys it with CloudFormation into a **production account (P)**.

```text
 Tooling account (T)                                   Production account (P)
 ┌────────────────────────────────────────────┐       ┌──────────────────────────────────────┐
 │ CodePipeline (service role: PipelineRole)  │       │ CrossAccountDeployRole               │
 │   └─ Deploy action RoleArn ─────────────────┼──────▶│   trust: T's PipelineRole            │
 │                                            │ (1)   │   perms: cloudformation:*, iam:PassRole│
 │ Artifact bucket (S3)                        │       │          s3:GetObject on T's bucket   │
 │   bucket policy allows P's roles  (2)       │◀──────┤          kms:Decrypt on T's key       │
 │ KMS customer-managed key                    │       │                                      │
 │   key policy allows P's roles     (3)       │◀──────┤ CloudFormationExecutionRole (4)      │
 └────────────────────────────────────────────┘       │   trust: cloudformation.amazonaws.com│
                                                       │   perms: create the stack's resources│
                                                       └──────────────────────────────────────┘
```

1. **A cross-account role in P** (`CrossAccountDeployRole`). Its trust policy allows T's pipeline service role to assume it. The deploy action's `RoleArn` points to it, and T's `PipelineRole` has `sts:AssumeRole` on it.
2. **The artifact bucket policy in T** grants P's roles `s3:GetObject*` (and `s3:PutObject*` if P's actions write artifacts).
3. **A customer-managed KMS key in T** encrypts the artifact bucket. Its **key policy** grants P's roles `kms:Decrypt` and `kms:DescribeKey` (plus `kms:Encrypt`/`GenerateDataKey*` if they write). **The AWS-managed `aws/s3` key cannot be used cross-account.** This is the most common root cause of `AccessDenied` in cross-account pipelines.
4. **A CloudFormation execution role in P**, passed by the deploy action. CloudFormation assumes it to create resources. The cross-account role needs `iam:PassRole` for it.

The same chain applies to CodeDeploy, ECS and Elastic Beanstalk actions in another account: role in the target, bucket policy, KMS key policy. The target-side role also needs the artifact permissions.

**Cross-Region** is a separate dimension. Each Region the pipeline acts in needs its own artifact bucket, and its own KMS key if encrypted. CodePipeline copies artifacts there.

### 4.1 Common multi-account pipeline topologies

| Topology | When |
|---|---|
| **One pipeline in tooling, stages per environment account** (dev → test → [approval] → prod) | The classic answer; one artifact promoted through accounts |
| **CDK Pipelines** (self-mutating) | Pipelines defined in CDK. The pipeline first updates itself, then deploys stages to accounts and Regions ("waves" run in parallel) |
| **StackSets action** | The same baseline into many accounts and Regions, with concurrency and failure-tolerance controls |
| **Pipeline per account** | Strong isolation between teams; more to maintain |

## 5. Secrets in pipelines

* **Build-time secrets** go in the buildspec `env.secrets-manager` / `env.parameter-store` ([01-source-build-and-artifacts.md](01-source-build-and-artifacts.md)).
* **Deploy-time secrets** for CloudFormation are **dynamic references** in the template. Never pass a secret as a plaintext parameter override; if you must have a parameter, use `NoEcho: true`, and prefer the dynamic reference.
* **Third-party CI** (GitHub Actions, GitLab CI) deploying to AWS uses **OIDC federation** to an IAM role whose trust policy restricts the `sub` claim to the repository and branch. It does **not** use stored access keys.

---

## 6. Exam traps

* **Cross-account pipeline with the default artifact encryption:** `aws/s3` can't be shared. Use a customer-managed key whose key policy names the target roles.
* **Bucket policy and key policy are both needed.** S3 permission alone fails on decrypt; KMS permission alone fails on get.
* **CloudFormation action without `RoleArn`:** CloudFormation then uses the caller's credentials. The cross-account role would need every resource permission, so give it a **CloudFormation execution role** instead.
* **ECS deploy files:** `imagedefinitions.json` for the standard (rolling) ECS action; `imageDetail.json` + `appspec.yaml` + `taskdef.json` for the CodeDeploy blue/green action.
* **The Lambda invoke action** must report its result or the action hangs until timeout.
* **The manual approval timeout** is 7 days, and then the action fails.
* **"Run unit tests on every pull request before merge":** that's a PR-triggered CodeBuild (webhook filter group or EventBridge on PR events), **not** a stage in the main-branch pipeline.
* **Disable a stage transition** to stop changes reaching production temporarily. Don't delete the stage.

## 7. Hands-on lab (about 30 minutes)

[labs/lab-02-pipeline-s3-eventbridge.yaml](labs/lab-02-pipeline-s3-eventbridge.yaml) creates three things:

* a **V2 pipeline** with an **S3 source**, using a versioned bucket with EventBridge notifications enabled and no polling;
* a CodeBuild stage, then a **manual approval** stage;
* an **EventBridge rule** that starts the pipeline when `source.zip` is uploaded.

```bash
aws cloudformation deploy --stack-name dop-lab-02 \
  --template-file labs/lab-02-pipeline-s3-eventbridge.yaml --capabilities CAPABILITY_NAMED_IAM

# A source bundle that holds just a buildspec
printf 'version: 0.2\nphases:\n  build:\n    commands:\n      - echo built revision $CODEBUILD_RESOLVED_SOURCE_VERSION\n' > buildspec.yml
zip source.zip buildspec.yml
aws s3 cp source.zip s3://$(aws cloudformation describe-stacks --stack-name dop-lab-02 \
  --query "Stacks[0].Outputs[?OutputKey=='SourceBucket'].OutputValue" --output text)/source.zip

# Within seconds, a new execution starts (EventBridge), runs the build, and waits at Approval
aws codepipeline get-pipeline-state --name dop-lab-02 \
  --query 'stageStates[].[stageName,latestExecution.status]' --output table

# Tear down: empty both buckets, then delete the stack
```

**Observe:**
* Upload a second zip while the first execution waits at approval. With the default `SUPERSEDED` mode, the newer execution replaces the waiting one at the stage boundary. Switch the template to `QUEUED` and repeat to see the difference.

## References

* CodePipeline concepts and execution modes — <https://docs.aws.amazon.com/codepipeline/latest/userguide/concepts-how-it-works.html>
* Stage conditions — <https://docs.aws.amazon.com/codepipeline/latest/userguide/stage-conditions.html>
* Create a pipeline that uses resources from another account — <https://docs.aws.amazon.com/codepipeline/latest/userguide/pipelines-create-cross-account.html>
* CloudFormation action configuration — <https://docs.aws.amazon.com/codepipeline/latest/userguide/action-reference-CloudFormation.html>
* Image definitions file reference — <https://docs.aws.amazon.com/codepipeline/latest/userguide/file-reference.html>
* Manual approvals — <https://docs.aws.amazon.com/codepipeline/latest/userguide/approvals.html>
* Invoke Lambda from a pipeline — <https://docs.aws.amazon.com/codepipeline/latest/userguide/actions-invoke-lambda-function.html>
