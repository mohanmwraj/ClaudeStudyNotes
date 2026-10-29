# Domain 1 · 03 · Deployment Strategies for Instances, Containers and Serverless

> **Exam tasks:** 1.4 (all of it), 1.1 ("determining appropriate deployment strategies"), 5.3 (analyzing failed deployments). **Principles:** P4 (immutable vs mutable), P5 (traffic routing gated by health), P7 (replacement).

Deployment questions are the largest single topic on DOP-C02. Every scenario reduces to three choices:

1. **What gets replaced?** In-place on the same resources (mutable), or new resources (immutable).
2. **How does traffic move?** All at once, in batches, canary (a small slice, then the rest), linear (equal steps), or blue/green (a full switch with the old environment kept).
3. **What signal stops or reverses it?** Deployment failure, health checks, CloudWatch alarms, or validation hooks.

---

## 1. Strategy vocabulary, precisely

| Strategy | Capacity during deploy | Mixed versions serving? | Rollback | Cost |
|---|---|---|---|---|
| **All at once** (in place) | Drops to 0 while updating | No (but downtime) | Redeploy the old version | Lowest |
| **Rolling** (in place, in batches) | Reduced by one batch | Yes | Redeploy the old version, batch by batch | Low |
| **Rolling with additional batch** | Full (an extra batch is launched first) | Yes | Redeploy | Medium |
| **Immutable** | Full + a temporary duplicate fleet | Briefly | Terminate the new fleet | Higher during deploy |
| **Blue/green** | Two full environments | No (switch), or partly (if shifted gradually) | **Route traffic back**; old environment intact | Highest during deploy |
| **Canary** | New version on a slice; the rest on old | Yes, by design | Shift the slice back | Medium |
| **Linear** | Traffic moves in equal steps every N minutes | Yes | Shift back | Medium |

**Mutable vs immutable (P4).** Only immutable and blue/green strategies give *fast, safe* rollback, because the previous version is still running and only the routing changes. With in-place strategies, rollback is a new deployment of the old revision.

---

## 2. AWS CodeDeploy

### 2.1 Building blocks

| Concept | Detail |
|---|---|
| **Application** | Name + compute platform: **EC2/On-premises**, **AWS Lambda** or **Amazon ECS** |
| **Deployment group** | Targets: EC2 tags, on-premises instance tags, ASG names, a Lambda function, or an ECS service. Also: deployment configuration, load balancer, **alarms**, **automatic rollback** settings, SNS **triggers**, and the service role |
| **Revision** | What to deploy. EC2: a zip/tar bundle in S3 (or GitHub) containing `appspec.yml` and files. Lambda and ECS: an AppSpec (YAML/JSON) naming the function version or task definition |
| **Deployment configuration** | How fast and how much at once (§2.3) |
| **CodeDeploy agent** | **Required on EC2 and on-premises instances**, not for Lambda or ECS. Install and keep it updated with **Systems Manager** (Distributor package `AWSCodeDeployAgent`, or a State Manager association) |

### 2.2 The EC2/on-premises AppSpec and its lifecycle hooks

```yaml
version: 0.0
os: linux
files:
  - source: /build
    destination: /var/www/app
permissions:
  - object: /var/www/app
    owner: webapp
    mode: 755
hooks:
  ApplicationStop:
    - location: scripts/stop.sh
      timeout: 60
  BeforeInstall:
    - location: scripts/backup_and_prepare.sh
  AfterInstall:
    - location: scripts/configure.sh
  ApplicationStart:
    - location: scripts/start.sh
  ValidateService:
    - location: scripts/smoke_test.sh
      timeout: 300
```

Hook order for an **in-place** deployment with a load balancer:

```text
BeforeBlockTraffic → [BlockTraffic] → AfterBlockTraffic →
ApplicationStop → [DownloadBundle] → BeforeInstall → [Install] → AfterInstall →
ApplicationStart → ValidateService →
BeforeAllowTraffic → [AllowTraffic] → AfterAllowTraffic
```

The bracketed events are **reserved** for the agent; they can't run scripts. The traffic hooks run only if a load balancer is configured on the deployment group.

Facts the exam builds questions on (from the [hooks reference](https://docs.aws.amazon.com/codedeploy/latest/userguide/reference-appspec-file-structure-hooks.html)):

* **`ApplicationStop` runs the scripts of the *previously deployed* revision.** It doesn't run on the first deployment to an instance. A broken stop script in the old revision makes every new deployment fail at `ApplicationStop`. Fix it by deploying with `--ignore-application-stop-failures` (or the console option), then fix the script.
* **`ValidateService`** is where smoke tests go: a non-zero exit fails the instance's deployment.
* **Default script timeout is 3,600 s**, which is also the maximum per lifecycle event.
* **Environment variables available to scripts:** `APPLICATION_NAME`, `DEPLOYMENT_ID`, `DEPLOYMENT_GROUP_NAME`, `DEPLOYMENT_GROUP_ID`, `LIFECYCLE_EVENT` (plus `BUNDLE_*` for S3 bundles). Use `DEPLOYMENT_GROUP_NAME` to vary behaviour per environment *without* rebuilding the artifact.
* **Agent logs:** `/var/log/aws/codedeploy-agent/codedeploy-agent.log`; per-deployment script output under `/opt/codedeploy-agent/deployment-root/deployment-logs/`.

### 2.3 Deployment configurations

| Platform | Predefined configurations | Custom |
|---|---|---|
| **EC2/on-premises** | `CodeDeployDefault.AllAtOnce`, `CodeDeployDefault.HalfAtATime`, `CodeDeployDefault.OneAtATime` | **Minimum healthy hosts** as a count or a percentage. Optional **zonal configuration**: deploy one AZ at a time with a bake period |
| **Lambda** (alias traffic shifting) | `CodeDeployDefault.LambdaAllAtOnce`; `LambdaCanary10Percent5Minutes` (also 10, 15 and 30 minutes); `LambdaLinear10PercentEvery1Minute` (also every 2, 3 and 10 minutes) | Canary or linear with your own percentage and interval |
| **ECS** (blue/green task sets) | `CodeDeployDefault.ECSAllAtOnce`; `ECSCanary10Percent5Minutes`, `ECSCanary10Percent15Minutes`; `ECSLinear10PercentEvery1Minutes`, `ECSLinear10PercentEvery3Minutes` | Canary or linear |

**Minimum healthy hosts** is a health constraint. If a deployment would drop healthy instances below it, CodeDeploy stops the deployment (`HEALTH_CONSTRAINTS`). `OneAtATime` is the safest in-place option: it stops at the first failed instance, except that the last instance is allowed to fail if all the others succeeded.

### 2.4 EC2 blue/green with CodeDeploy

* **Replacement instances:** CodeDeploy can **copy the Auto Scaling group** (the usual answer) or use instances you provisioned with tags.
* **Traffic:** rerouted at the load balancer from the original to the replacement instances, either immediately or when you choose (a manual reroute window).
* **Original instances:** terminated after a configurable wait (default 1 hour), or kept running.
* **Hooks:**
  * Original instances run the **block-traffic** hooks.
  * Replacement instances run the install hooks and the **allow-traffic** hooks.
  * On rollback, the original instances run the allow-traffic hooks again.

### 2.5 Lambda deployments

CodeDeploy shifts traffic on a **Lambda alias** between two **versions**. Versions are immutable snapshots; an alias is a pointer that can split traffic by weight. Hooks: `BeforeAllowTraffic` and `AfterAllowTraffic`, each a **Lambda validation function**. Each must call `PutLifecycleEventHookExecutionStatus` with `Succeeded` or `Failed` **within one hour**, or the deployment fails.

In practice you define this in **AWS SAM**:

```yaml
MyFunction:
  Type: AWS::Serverless::Function
  Properties:
    Handler: app.handler
    Runtime: python3.12
    CodeUri: src/
    AutoPublishAlias: live                 # publish a version on every code change, move alias "live"
    DeploymentPreference:
      Type: Canary10Percent5Minutes        # CodeDeploy configuration
      Alarms:
        - !Ref ErrorsAlarm                 # any alarm in ALARM → automatic rollback
      Hooks:
        PreTraffic: !Ref PreTrafficCheckFunction
        PostTraffic: !Ref PostTrafficCheckFunction
```

SAM creates the CodeDeploy application, deployment group and role.

### 2.6 ECS blue/green with CodeDeploy

* **Load balancer:** the service is created with `deploymentController: CODE_DEPLOY` and **two target groups** behind an ALB or NLB. There is a **production listener** and an optional **test listener** (for example port 8080).
* **The deployment:** CodeDeploy creates a **replacement task set**, routes the test listener to it, runs hooks, then shifts the production listener (all at once, canary or linear).
* **Afterwards:** the original task set is kept for a termination wait period, so rollback is instant.
* **Hook order** (each hook is a Lambda function):

  ```text
  BeforeInstall → [Install] → AfterInstall → [AllowTestTraffic] → AfterAllowTestTraffic →
  BeforeAllowTraffic → [AllowTraffic] → AfterAllowTraffic
  ```

  `AfterAllowTestTraffic` is where you run integration tests against the test listener **before** any production traffic moves.
* **Pipeline integration:** the CodePipeline action `CodeDeployToECS`, with `appspec.yaml`, `taskdef.json` and `imageDetail.json`.

### 2.7 Rollback in CodeDeploy

* **Automatic rollback** can be enabled for:
  1. **deployment failure;**
  2. **CloudWatch alarm thresholds met**: alarms on the deployment group, such as 5xx count, latency or custom error metrics.
* A rollback is a **new deployment** (new ID) of the **last known good revision**. For blue/green, traffic is rerouted back to the original environment if it still exists.
* **Without alarms,** CodeDeploy only notices failures that make hooks or health checks fail. A version that returns wrong answers but passes health checks **won't** roll back. **Wire alarms to the deployment group** (P5).

### 2.8 CodeDeploy with Auto Scaling groups

* CodeDeploy installs an **ASG lifecycle hook**. Instances launched by a scale-out get the **last successfully deployed revision** before going InService.
* **Race condition:** if a scale-out happens *during* a deployment, the new instance may get the **previous** revision. CodeDeploy then starts a follow-up deployment to it, but for safety you can **suspend** the ASG scaling processes during deployments, or redeploy afterwards.
* **Termination deployments** (optional) run the block-traffic and `ApplicationStop` hooks when the ASG scales in, for graceful draining.

### 2.9 Troubleshooting CodeDeploy (Domain 5.3)

| Symptom | Cause / fix |
|---|---|
| Deployment stuck "Pending", instances never contacted | Agent not installed or not running; wrong instance tags; instance can't reach CodeDeploy. Private subnets without NAT need **both** interface endpoints, `codedeploy` and `codedeploy-commands-secure`, plus `:enable_auth_policy: true` in the agent configuration and `codedeploy-commands-secure:*` permissions on the instance profile |
| Fails at `DownloadBundle` | The instance profile lacks `s3:GetObject` on the revision bucket, or there's a KMS decrypt problem |
| Fails at `ApplicationStop` on every deployment | The **old** revision's stop script is broken → `--ignore-application-stop-failures` once |
| `HEALTH_CONSTRAINTS` | Too many instances failed for the minimum-healthy-hosts setting. Read the per-instance event logs |
| Deployment succeeds but users see errors | No alarms on the deployment group, so nothing told CodeDeploy to roll back |
| Lambda deployment fails after 1 hour at a hook | The validation function never called `PutLifecycleEventHookExecutionStatus` |

---

## 3. AWS Elastic Beanstalk deployment policies

| Policy | Mechanism | Capacity | Downtime | Rollback |
|---|---|---|---|---|
| **All at once** | Updates every instance at the same time | Drops | **Yes** | Redeploy |
| **Rolling** | Batches of existing instances | Reduced by one batch | No | Redeploy (manual) |
| **Rolling with additional batch** | Launches an extra batch first, then rolls | Full | No | Redeploy |
| **Immutable** | Launches a **new temporary ASG** with new instances; when healthy, moves them into the original ASG and terminates the old ones | Full (double during deploy) | No | **Terminate the new instances**: fastest and safest |
| **Traffic splitting** | Canary: new instances get a configured **percentage of client traffic** for an **evaluation time**, then a full cut-over | Full | No | Automatic if health checks fail during evaluation |
| **Blue/green** (not a policy; a procedure) | **Clone** the environment, deploy to the clone, **Swap environment URLs** (CNAME swap) | Two environments | No | Swap back |

Exam specifics:
* **Blue/green with an RDS database:** don't create the database **inside** the Beanstalk environment, because it's tied to that environment's lifecycle. Create it separately and pass the endpoint in configuration. Then both environments use it and terminating blue doesn't delete the data.
* **The CNAME swap is DNS,** so clients that cache DNS keep hitting the old environment for a while. Route 53 weighted records give gradual control.
* **Configuration:**
  * `.ebextensions/*.config`: option settings, resources, commands;
  * `.platform/hooks/` and `.platform/confighooks/`: platform hook scripts on Amazon Linux 2+;
  * saved configurations;
  * environment variables via option settings, or secrets fetched at runtime.
* **Worker environments** consume an SQS queue (the daemon posts messages to your app). `cron.yaml` defines periodic tasks.
* **Managed platform updates** apply minor and patch platform versions in a maintenance window, using immutable deployment.

---

## 4. Amazon ECS and Amazon EKS deployments

### 4.1 ECS rolling update (deployment controller `ECS`)

* `minimumHealthyPercent` and `maximumPercent` bound the task count during replacement. For example, 100/200 means start new tasks before stopping old ones, with full capacity maintained.
* The **deployment circuit breaker** (`enable: true, rollback: true`) stops a deployment whose tasks keep failing to reach steady state, and rolls back to the last completed deployment.
* **CloudWatch alarm-based rollback:** a `deploymentConfiguration.alarms` list with `rollback: true` rolls back when an alarm fires during the deployment.
* **Choosing:** the circuit breaker catches "tasks won't start"; alarms catch "tasks start but behave badly".

### 4.2 ECS blue/green

* **Via CodeDeploy** (§2.6). This is the version most exam questions describe.
* **Native ECS blue/green** (since July 2025), with **canary and linear** strategies added in October 2025. ECS itself shifts traffic between the blue and green service revisions, with **Lambda lifecycle hooks** at stages such as pre-scale-up, test-traffic shift and production-traffic shift. A **bake time** keeps blue available for instant rollback before it's removed ([AWS News Blog](https://aws.amazon.com/blogs/aws/accelerate-safe-software-releases-with-new-built-in-blue-green-deployments-in-amazon-ecs/)).
* If an exam option offers either mechanism, both satisfy "blue/green on ECS". Pick based on the other constraints.

### 4.3 Amazon EKS

* **Kubernetes Deployments** do rolling updates natively (`maxSurge`, `maxUnavailable`), and readiness probes gate them. Rollback: `kubectl rollout undo`.
* **Canary/blue-green on EKS:** an ALB managed by the AWS Load Balancer Controller with weighted target groups, or progressive-delivery controllers. A pipeline runs `kubectl`/`helm` from CodeBuild.
* **Pod permissions:** **IAM roles for service accounts (IRSA)** or **EKS Pod Identity**. Never node-wide instance roles for app permissions.
* **CodeBuild access** to the cluster: an **EKS access entry** (or the legacy `aws-auth` ConfigMap) maps the build role to a Kubernetes RBAC group.

---

## 5. Other traffic-shifting mechanisms

| Mechanism | How | Use when |
|---|---|---|
| **API Gateway canary release** | Stage canary settings: a percentage of traffic goes to a canary deployment, with stage-variable overrides; promote or delete the canary | Testing a new API deployment on a slice of callers |
| **Route 53 weighted records** | Two records with weights (e.g. 90/10) pointing at blue and green load balancers; health checks remove unhealthy targets | Blue/green between whole stacks or Regions; tolerant of DNS caching delays |
| **CloudFront continuous deployment** | A staging distribution receives a weight or header-selected subset of traffic; promote its configuration | Testing CDN configuration changes |
| **ALB weighted target groups** | One listener rule forwards to two target groups with weights | Custom blue/green on EC2 without CodeDeploy |

## 6. AWS AppConfig: deploying configuration and feature flags safely

* Treats **configuration as a deployment:**
  * **Configuration profiles** are freeform data (stored in AppConfig, S3, Parameter Store, Secrets Manager or SSM documents) or **feature flags**.
  * **Validators** check before deploying: JSON Schema, or a Lambda function.
  * **Deployment strategies** control the rollout: `AppConfig.AllAtOnce`, `AppConfig.Linear50PercentEvery30Seconds`, `AppConfig.Canary10Percent20Minutes`, or custom linear or exponential growth with a **bake time**.
  * **CloudWatch alarms** on the environment trigger **automatic rollback**.
* **Applications retrieve configuration** with the AppConfig Agent (a Lambda extension, ECS/EKS sidecar, or an agent on EC2), which polls and caches.
* **Exam angle:**
  * "Turn a feature on for 10% of traffic and roll back automatically if errors rise, without redeploying code" → AppConfig feature flag + a canary deployment strategy + an alarm.
  * Parameter Store alone has no validation, gradual rollout or rollback.

## 7. Storage patterns that affect deployments

| Pattern | Deployment implication |
|---|---|
| **EBS** (per-instance) | Anything written to local disk is lost when an immutable deployment replaces the instance. Bake software into the AMI; keep state elsewhere |
| **EFS** (shared, multi-AZ) | Shared content across instances (uploads, CMS media); survives instance replacement. Mount via launch template user data or the EFS mount helper |
| **S3** | Static assets and build artifacts. Use versioned or content-hashed keys so old and new app versions can run side by side during blue/green |
| **Instance store** | Ephemeral; scratch data only |

## 8. Choosing a strategy: requirement → answer

| Requirement | Answer |
|---|---|
| Zero downtime, full capacity, cheapest, rollback can be slow | Rolling with additional batch (Beanstalk), or a custom minimum-healthy-hosts setting at 100% plus extra capacity |
| Fastest possible rollback, no impact if the new version is bad | Blue/green (CodeDeploy, ECS, Beanstalk swap) or immutable |
| Expose the new version to a small share of users first, automatic rollback | Canary: CodeDeploy Lambda/ECS canary with alarms, Beanstalk traffic splitting, API Gateway canary, AppConfig for flags |
| Gradual, equal steps | Linear deployment configuration |
| Test the new ECS version on a separate port before production traffic | CodeDeploy ECS blue/green with a **test listener** + an `AfterAllowTestTraffic` hook |
| Only one instance at a time may be down | `CodeDeployDefault.OneAtATime`, or a minimum-healthy-hosts percentage |
| Deploy one AZ at a time | CodeDeploy zonal configuration |
| Database schema changes with blue/green | Backward-compatible (expand/contract) migrations so blue and green work on the same database |

## 9. Exam traps

* **"Automatically roll back if the error rate increases"** needs **CloudWatch alarms attached** to the deployment (CodeDeploy group, SAM `Alarms`, ECS `alarms`, AppConfig environment). Deployment-failure rollback alone isn't enough.
* **The CodeDeploy agent is only for EC2 and on-premises.** An option to "install the CodeDeploy agent on the Lambda function or Fargate tasks" is nonsense.
* **The `ApplicationStop` failure loop** comes from the *old* revision's script.
* **Beanstalk immutable vs rolling:** immutable is the one whose rollback is "terminate the new ASG".
* **Beanstalk blue/green with a database inside the environment** risks data loss when the old environment is terminated.
* **ECS rolling vs blue/green:**
  * The standard ECS deploy action (`imagedefinitions.json`) does **rolling**.
  * Blue/green needs either CodeDeploy (`appspec.yaml` + `taskdef.json` + `imageDetail.json`) or ECS native blue/green.
* **Lambda "versions" vs "aliases":** you shift traffic on an **alias** between **versions**. `$LATEST` can't be weighted.

## 10. Hands-on lab: Lambda canary with automatic alarm rollback (about 30 minutes)

[labs/lab-03-sam-canary-rollback.yaml](labs/lab-03-sam-canary-rollback.yaml) is a SAM template with these parts:

* A function with `AutoPublishAlias: live` and `DeploymentPreference: Canary10Percent5Minutes`.
* An **alarm on the alias's `Errors` metric** wired for rollback.
* A `FAIL_RATE` parameter to inject failures.

```bash
sam deploy --template-file labs/lab-03-sam-canary-rollback.yaml --stack-name dop-lab-03 \
  --capabilities CAPABILITY_IAM --resolve-s3 --parameter-overrides FailRate=0
# Deploy version 2 that fails 50% of the time:
sam deploy --template-file labs/lab-03-sam-canary-rollback.yaml --stack-name dop-lab-03 \
  --capabilities CAPABILITY_IAM --resolve-s3 --parameter-overrides FailRate=50
# While the canary runs, invoke the alias in a loop:
for i in $(seq 1 200); do aws lambda invoke --function-name dop-lab-03-fn:live /dev/null >/dev/null; done
# Watch the CodeDeploy deployment roll back when the alarm fires:
aws deploy list-deployments --application-name <from stack resources> --query 'deployments[0]'
sam delete --stack-name dop-lab-03
```

**Observe:**
* CodeDeploy moves 10% of the alias traffic to version 2.
* The `Errors` alarm goes to ALARM.
* CodeDeploy stops and shifts 100% back to version 1.

That's P5 end to end.

## References

* AppSpec hooks reference — <https://docs.aws.amazon.com/codedeploy/latest/userguide/reference-appspec-file-structure-hooks.html>
* Deployment configurations — <https://docs.aws.amazon.com/codedeploy/latest/userguide/deployment-configurations.html>
* Redeploy and roll back with CodeDeploy — <https://docs.aws.amazon.com/codedeploy/latest/userguide/deployments-rollback-and-redeploy.html>
* CodeDeploy and Auto Scaling — <https://docs.aws.amazon.com/codedeploy/latest/userguide/integrations-aws-auto-scaling.html>
* Elastic Beanstalk deployment policies — <https://docs.aws.amazon.com/elasticbeanstalk/latest/dg/using-features.rolling-version-deploy.html>
* Elastic Beanstalk blue/green — <https://docs.aws.amazon.com/elasticbeanstalk/latest/dg/using-features.CNAMESwap.html>
* ECS deployment circuit breaker — <https://docs.aws.amazon.com/AmazonECS/latest/developerguide/deployment-circuit-breaker.html>
* ECS blue/green with CodeDeploy — <https://docs.aws.amazon.com/AmazonECS/latest/developerguide/deployment-type-bluegreen.html>
* SAM gradual deployments — <https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/automating-updates-to-serverless-apps.html>
* API Gateway canary releases — <https://docs.aws.amazon.com/apigateway/latest/developerguide/canary-release.html>
* AppConfig deployment strategies — <https://docs.aws.amazon.com/appconfig/latest/userguide/appconfig-creating-deployment-strategy.html>
