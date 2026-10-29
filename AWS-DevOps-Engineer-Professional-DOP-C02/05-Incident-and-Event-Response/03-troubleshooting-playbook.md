# Domain 5 · 03 · Troubleshooting Playbook: Symptom → Signal → Root Cause → Fix

> **Exam task:** 5.3 (root-cause analysis; failed deployments in CodePipeline, CodeBuild, CodeDeploy, CloudFormation and synthetic monitoring; failed processes in auto scaling, ECS and EKS). **Principles:** P10 (signals), P2 (permissions), P7 (health and replacement).

## 1. First principles of root-cause analysis on AWS

1. **Find the first failure, not the loudest one.** Rollbacks, retries and cascades produce many errors. The root cause is the earliest one in time:
   * the first `*_FAILED` stack event;
   * the first failed lifecycle hook;
   * the first stopped task.
2. **Most failures are one of four things:**
   * **permissions** (an IAM, resource, KMS or SCP denial);
   * **network path** (no route, NAT or endpoint; a security group or NACL);
   * **health checks** (wrong path or port, a grace period too short);
   * **capacity or quotas.**

   Test those four in that order.
3. **Use the service's own failure record before anything else:**
   * stack events;
   * CodeDeploy lifecycle-event logs;
   * ASG activity history;
   * ECS `stoppedReason`;
   * CodeBuild phase details;
   * Kubernetes events.
4. **Then correlate across services:**
   * **CloudTrail:** who changed what, and when.
   * **Config timeline:** what the configuration was.
   * **X-Ray:** which hop failed.
   * **AWS Health:** is it AWS?
   * **OpsCenter:** related OpsItems and runbooks.

---

## 2. Pipelines and builds

| Symptom | Where to look | Common root causes |
|---|---|---|
| Pipeline doesn't start on commit | EventBridge rule and its target role; source action configuration | No EventBridge rule (polling disabled); the rule's role lacks `codepipeline:StartPipelineExecution`; wrong branch in the pattern; a CodeConnections connection in `PENDING`; V2 trigger filters exclude the change |
| Source action fails | Action details | S3 bucket versioning disabled; object key mismatch; the connection lacks repository access |
| Cross-account deploy action: `AccessDenied` | Action error message | KMS key policy or artifact bucket policy missing the target role; `aws/s3` key used; the pipeline role can't `sts:AssumeRole` the target role (see [01/02 §4](../01-SDLC-Automation/02-codepipeline-design-and-multi-account.md#4-the-cross-account-pipeline-four-pieces-that-must-all-exist)) |
| CodeBuild fails in `DOWNLOAD_SOURCE` / `PROVISIONING` | Build phase details | Role can't read source or artifacts; secrets or parameters not readable; VPC build with no route to S3 or the source |
| CodeBuild fails in `BUILD` | Build logs | A test command exited non-zero (intended); Docker without privileged mode; dependency download blocked (VPC without NAT, or CodeArtifact token expired) |
| Lambda invoke action hangs until timeout | Function logs | The function never called `PutJobSuccessResult` / `PutJobFailureResult` |
| Manual approval failed after 7 days | Action history | Nobody approved within the 7-day limit |

## 3. Deployments

| Symptom | Where to look | Common root causes |
|---|---|---|
| CodeDeploy: instances "Pending", never start | Deployment group targets; agent status | Agent not installed or running; instance has no route to CodeDeploy (no NAT or VPC endpoint); wrong tags or ASG in the deployment group |
| CodeDeploy fails at `DownloadBundle` | Lifecycle event log on the instance | Instance profile lacks S3 or KMS access to the revision |
| Fails at `ApplicationStop` every time | Event log | The **previous** revision's stop script fails → redeploy once with "ignore ApplicationStop failures" |
| Fails at `ValidateService` / `AfterAllowTraffic` | Script output in `/opt/codedeploy-agent/deployment-root/deployment-logs/` | The application doesn't start; a smoke test detected a real failure (good) |
| ECS blue/green deployment fails at a hook | Hook Lambda logs | Validation failed, or the hook never reported its status (1-hour timeout) |
| Lambda canary rolled back | CodeDeploy deployment, alarm history | An alarm attached to the deployment fired, so the new version really errors (good), or the alarm is too sensitive |
| Elastic Beanstalk environment "Severe"/"Degraded" | **Enhanced health** dashboard, environment events, **request logs** (bundle or tail) | Application crash, failing health-check URL, or `.ebextensions` command failure during deployment |
| CloudFormation `CREATE_FAILED` / rollback | **First** failed event in stack events | Missing IAM capability; resource limits; invalid property; a dependency not ready (add `DependsOn`); signal timeout (see [02/01 §5.1](../02-Configuration-Management-and-IaC/01-cloudformation-deep-dive.md#51-cfn-init-cfn-signal-cfn-hup)) |
| CloudFormation `UPDATE_ROLLBACK_FAILED` | Stack events | A resource was changed or deleted outside CloudFormation → fix, or `ContinueUpdateRollback` with `ResourcesToSkip` |
| Synthetics canary failing after a deployment | Canary run screenshots, HAR files and logs | A real regression (roll back), a changed selector, or a canary that can't reach a private endpoint (needs VPC configuration) |

## 4. Auto scaling and EC2

| Symptom | Where to look | Common root causes |
|---|---|---|
| ASG doesn't launch instances | **ASG activity history** (status reason) | Invalid launch template (AMI deregistered, wrong subnet, missing instance profile permission); `InsufficientInstanceCapacity`; vCPU quota; KMS key for encrypted EBS not usable by the Auto Scaling **service-linked role** |
| Instances launch then terminate in a loop | Activity history + ELB target health | ELB health checks failing before the app is ready (grace period too short); wrong health-check path or port; security group blocks the load balancer → targets |
| ASG doesn't scale out despite load | Scaling policy alarms; max size | Max size reached; alarm metric wrong (e.g. CPU while the bottleneck is the queue); cooldown/warm-up |
| Unhealthy targets not replaced | ASG health check type | Health check type `EC2` instead of `ELB` |
| Instances stuck in `Pending:Wait` / `Terminating:Wait` | Lifecycle hooks | Automation never called `CompleteLifecycleAction` (waits until the heartbeat timeout) |
| Instance unreachable after a reboot | EC2 status checks, system log, screenshot | OS-level failure (instance status check) → EC2Rescue / `AWSSupport-ExecuteEC2Rescue` runbook |
| Instance not in Systems Manager | SSM Agent, role/DHMC, network | Missing `AmazonSSMManagedInstanceCore`; no endpoints or NAT; agent stopped |

## 5. Containers

### 5.1 Amazon ECS: read the stopped task's `stoppedReason`

| `stoppedReason` / symptom | Root cause | Fix |
|---|---|---|
| `CannotPullContainerError` | No network path to ECR (private subnet without NAT or the **`ecr.api`, `ecr.dkr` interface endpoints plus the S3 gateway endpoint**); or the **task execution role** lacks ECR permissions; or the image tag doesn't exist | Add endpoints or NAT; fix the execution role; push the image |
| `ResourceInitializationError: unable to pull secrets` | The **task execution role** can't read the Secrets Manager secret or SSM parameter (or KMS decrypt); or no network path to those endpoints | Grant `secretsmanager:GetSecretValue` / `ssm:GetParameters` / `kms:Decrypt` to the **execution** role |
| Essential container exited (exit code 1, 137…) | The application crashed (logs); **137 = killed**, often **out of memory** (task or container memory limit) | Check the awslogs/FireLens logs; raise the memory limit; fix the app |
| `Task failed ELB health checks` | Wrong health-check path or port, the app too slow to start, or the security group blocks the ALB | Fix the target-group health check; set the service's **health check grace period**; allow ALB → task traffic |
| Service can't place tasks (`unable to place a task`) | No capacity, or port conflicts in bridge mode | Capacity provider with managed scaling; Fargate; `awsvpc` mode |
| Deployment rolls back automatically | **Deployment circuit breaker** or **deployment alarms** | Read the failed tasks' reasons above |
| Application gets `AccessDenied` calling AWS | The **task role** (not the execution role) lacks permissions | Task role = the app's permissions; execution role = the agent's permissions to pull images, write logs and fetch secrets |

### 5.2 Amazon EKS

| Symptom | Root cause |
|---|---|
| Pods `Pending` | Insufficient node capacity (Cluster Autoscaler/Karpenter not scaling: check its logs and node group limits); unschedulable constraints; no Fargate profile matching the namespace and labels |
| `ImagePullBackOff` | Registry access (node role lacks ECR read; private subnets without endpoints); wrong image |
| `CrashLoopBackOff` | App crash; failing liveness probe; config or secret missing |
| Pods get `AccessDenied` from AWS APIs | IRSA/Pod Identity misconfigured: wrong service account annotation or association, or the role trust policy doesn't match the OIDC provider and service account |
| CodeBuild/CI can't `kubectl apply` | The CI role isn't mapped in **access entries** (or `aws-auth`) to an RBAC group |
| Nodes `NotReady` / not joining | Node role missing from access entries; the bootstrap can't reach the API endpoint (private endpoint without routes) |

## 6. Serverless and integration

| Symptom | Root cause |
|---|---|
| Lambda `Task timed out` | Downstream slow; a function in a VPC calling the internet without NAT (or AWS services without endpoints) |
| Lambda throttles | Reserved concurrency too low; account concurrency exhausted |
| API Gateway **502** | Lambda proxy integration returned a malformed response (must include `statusCode` and a string `body`), or the function errored |
| API Gateway **504** | Integration exceeded the timeout (29 s by default for REST) |
| API Gateway **403** | Missing or invalid auth, WAF block, resource policy, or calling a private API from outside its VPC endpoint |
| SQS messages processed repeatedly | Visibility timeout shorter than processing time; consumer doesn't delete after success |
| DLQ filling up | Poison messages; see the consumer errors; redrive after fixing |
| Kinesis consumer lagging (`IteratorAge` ↑) | Errors blocking a shard (poison record); too few shards or too small a batch; slow function |
| SNS notifications from alarms or EventBridge not delivered on an encrypted topic | AWS-managed KMS key used; needs a customer-managed key whose policy allows the service |

## 7. Networking quick checks (when "it can't connect")

1. **Route:** NAT or IGW for the internet; VPC endpoints for AWS services; Transit Gateway / peering routes.
2. **Security groups:** stateful; check the **source security group** references. A **Route 53 health checker** needs inbound from the health-checker IP ranges.
3. **NACLs:** stateless, so check the return traffic on **ephemeral ports**.
4. **DNS:** private hosted zone associations; Resolver rules; `enableDnsSupport`/`enableDnsHostnames` for interface endpoints' private DNS.
5. **VPC Flow Logs:** `REJECT` entries locate the blocking layer. **Reachability Analyzer** checks a path without sending traffic.

## 8. Root-cause analysis tools

| Tool | Use |
|---|---|
| CloudWatch metrics and alarms | When it started, and which metric moved first |
| CloudWatch Logs Insights | Errors and stack traces across log groups |
| **X-Ray / Application Signals** | Which service or call in the chain failed or slowed |
| **CloudTrail** (Event history, Lake) | Who changed what just before the incident |
| **AWS Config timeline** | The configuration before and after |
| **AWS Health Dashboard** | AWS-side events affecting your resources |
| **Systems Manager OpsCenter** | OpsItems aggregating related resources, events and runbooks; run remediation runbooks from the OpsItem |
| **Amazon Detective** | Security investigations: behaviour graphs from CloudTrail, VPC Flow Logs and GuardDuty |

## 9. Exam traps

* **ECS execution role vs task role** comes up in many questions. Pull, logs and secrets use the execution role; the application's API calls use the task role.
* **"Fix the immediate failure" vs "prevent recurrence":** the best answers often do both, e.g. continue the rollback **and** remove the manual change by using drift detection or SCPs.
* **Don't jump to scaling up** when the cause is permissions, a network path or a health check.

## References

* ECS stopped task errors — <https://docs.aws.amazon.com/AmazonECS/latest/developerguide/stopped-task-errors.html>
* ECS task execution role — <https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task_execution_IAM_role.html>
* Troubleshooting CodeDeploy — <https://docs.aws.amazon.com/codedeploy/latest/userguide/troubleshooting.html>
* Troubleshooting CodePipeline — <https://docs.aws.amazon.com/codepipeline/latest/userguide/troubleshooting.html>
* Troubleshooting EC2 Auto Scaling — <https://docs.aws.amazon.com/autoscaling/ec2/userguide/CHAP_Troubleshooting.html>
* Elastic Beanstalk enhanced health — <https://docs.aws.amazon.com/elasticbeanstalk/latest/dg/health-enhanced.html>
* EKS troubleshooting — <https://docs.aws.amazon.com/eks/latest/userguide/troubleshooting.html>
* API Gateway REST API errors and quotas — <https://docs.aws.amazon.com/apigateway/latest/developerguide/limits.html>
* VPC Reachability Analyzer — <https://docs.aws.amazon.com/vpc/latest/reachability/what-is-reachability-analyzer.html>
