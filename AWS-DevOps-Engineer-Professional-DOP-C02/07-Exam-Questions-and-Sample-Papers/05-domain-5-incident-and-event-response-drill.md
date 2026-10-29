# Domain 5 Drill · Incident and Event Response (20 questions)

Original exam-style questions for tasks 5.1–5.3. The notes for this domain are in [05-Incident-and-Event-Response](../05-Incident-and-Event-Response/).

---

### Q1 · Task 5.1 · Single answer

AWS has emailed a company twice to say that IAM access keys from its account were found in public code repositories. The security team wants every future occurrence handled within minutes, automatically: the exposed key deactivated, its recent API activity summarized, and the team notified.

What should the DevOps engineer implement?

- **A.** A daily Lambda function that scans public GitHub repositories for the company's key IDs.
- **B.** An EventBridge rule that matches AWS Health events with the event type code `AWS_RISK_CREDENTIALS_EXPOSED` and starts a Step Functions workflow that deactivates the key, queries CloudTrail for its recent activity, and notifies the team.
- **C.** A CloudWatch alarm on the `AccessDenied` error count in CloudTrail logs.
- **D.** An AWS Config rule that checks whether access keys are older than 90 days.

<details><summary>Answer</summary>

**Answer: B**

**Why (P1):** AWS Health publishes an exposed-credentials event to EventBridge. A Step Functions workflow orchestrates the containment steps in order.

- **A** — wrong: custom scanning duplicates AWS's detection, and only daily.
- **B** — correct: event-driven, multi-step, automatic.
- **C** — wrong: an attacker's successful calls don't produce access-denied errors.
- **D** — wrong: key age has nothing to do with exposure.

**Reference:** <https://docs.aws.amazon.com/health/latest/ug/cloudwatch-events-health.html>

</details>

### Q2 · Task 5.1 · Single answer

When a file is uploaded to an S3 bucket, two independent systems must each process it: a virus scanner and a thumbnail generator. Each must be able to retry independently, and neither may lose events if it's down for an hour.

Which design meets these requirements?

- **A.** Two S3 event notifications for the same event type and prefix, each invoking a different Lambda function.
- **B.** One Lambda function that calls both systems synchronously.
- **C.** A scheduled job that lists new objects every 5 minutes and calls both systems.
- **D.** An S3 event notification to an SNS topic, with two SQS queues subscribed (one per system), each consumed by its own worker.

<details><summary>Answer</summary>

**Answer: D**

**Why (P9):** SNS fans the event out, and each SQS queue durably buffers its consumer's copy. Retries and outages stay independent. (S3 → EventBridge with two rules targeting two queues also works.)

- **A** — wrong: S3 rejects overlapping notification configurations for the same event type and prefix.
- **B** — wrong: couples the systems, so one failure blocks or retries the other.
- **C** — wrong: polling.
- **D** — correct: durable fan-out.

**Reference:** <https://docs.aws.amazon.com/sns/latest/dg/sns-common-scenarios.html>

</details>

### Q3 · Task 5.1 · Single answer

A Lambda function consumes an Amazon Kinesis data stream. One malformed record makes the function throw an error, and processing of that shard stops for hours while the same batch is retried. Other records in the shard keep piling up.

What should the DevOps engineer configure on the event source mapping?

- **A.** Bisect batch on function error, a maximum retry attempts value, a maximum record age, and an on-failure destination (an SQS queue or SNS topic) for records that still fail.
- **B.** A larger batch size.
- **C.** Reserved concurrency of 1 on the function.
- **D.** A longer Lambda timeout.

<details><summary>Answer</summary>

**Answer: A**

**Why (P9):** For stream sources, a failing batch blocks its shard. Bisect isolates the bad record, the retry and age limits bound the blocking, and the destination keeps the failed record for later analysis.

- **A** — correct: the documented error-handling controls.
- **B** — wrong: larger batches make the blocking worse.
- **C** — wrong: limits throughput and doesn't stop the retries.
- **D** — wrong: the record fails deterministically, so time doesn't help.

**Reference:** <https://docs.aws.amazon.com/lambda/latest/dg/with-kinesis.html>

</details>

### Q4 · Task 5.1 · Select TWO

A company has 30 accounts and uses 4 AWS Regions. The security operations team wants every GuardDuty finding, from every account and Region, delivered to **one** event bus in `us-east-1` in the security account. Automation will be built against that bus.

Which combination of steps meets these requirements? (Select TWO.)

- **A.** In each Region in use, designate the security account as the GuardDuty delegated administrator with auto-enable, so that member findings in that Region are aggregated in the security account.
- **B.** Turn on email notifications from the GuardDuty console in every account.
- **C.** In the security account, create EventBridge rules in each of the other three Regions that match `GuardDuty Finding` events and forward them to the event bus in `us-east-1`. That bus's resource policy allows the sending rules.
- **D.** Enable CloudTrail data events for GuardDuty.
- **E.** Run a Lambda function every 5 minutes that calls `ListFindings` in every account and Region.

<details><summary>Answer</summary>

**Answer: A, C**

**Why (P13, P1):** GuardDuty aggregates **per Region** in the delegated administrator account. EventBridge cross-Region rules then bring all Regions onto one bus.

- **A** — correct: org-wide collection in each Region.
- **B** — wrong: no central bus, and it doesn't scale.
- **C** — correct: cross-Region event forwarding to the central bus.
- **D** — wrong: GuardDuty findings aren't CloudTrail data events.
- **E** — wrong: polling with custom code across 120 account-Region combinations.

**Reference:** <https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-cross-region.html>

</details>

### Q5 · Task 5.1 · Single answer

A payment service publishes events (authorized, captured, refunded) that must be processed **in order for each customer**, and each event must be processed exactly once. Different customers' events may be processed in parallel.

Which messaging design should the DevOps engineer choose?

- **A.** An SQS standard queue with a Lambda consumer.
- **B.** An SNS standard topic with an HTTPS subscriber.
- **C.** An SQS FIFO queue, using the customer ID as the message group ID and content-based or explicit deduplication IDs.
- **D.** An EventBridge rule targeting a Lambda function.

<details><summary>Answer</summary>

**Answer: C**

**Why (P9):** FIFO queues preserve order **within a message group** and deduplicate within the deduplication window. Different groups are processed in parallel.

- **A** — wrong: best-effort ordering and at-least-once delivery.
- **B** — wrong: standard topics don't guarantee order.
- **C** — correct: per-customer ordering with parallelism across customers.
- **D** — wrong: EventBridge doesn't guarantee ordering.

**Reference:** <https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/FIFO-queues.html>

</details>

### Q6 · Task 5.1 · Single answer

A security response has five steps:
1. Snapshot a volume.
2. Wait for the snapshot to complete (which can take up to an hour).
3. Call a third-party ticketing API, retrying with backoff on failure.
4. Wait for an analyst to approve in the ticketing tool, which can take up to 2 days.
5. Then quarantine the instance.

What should orchestrate this workflow?

- **A.** An AWS Step Functions Standard workflow, using retries with backoff, wait or polling states, and a callback task (`.waitForTaskToken`) for the analyst's approval.
- **B.** A single Lambda function that performs every step in order.
- **C.** An SQS queue with a Lambda consumer that sleeps between steps.
- **D.** An EventBridge rule with five targets.

<details><summary>Answer</summary>

**Answer: A**

**Why (P12):** Standard workflows run for up to a year, with built-in retries, waits and callback-based human approval, plus full execution history.

- **A** — correct: purpose-built orchestration.
- **B** — wrong: Lambda's 15-minute maximum can't cover hours or days of waiting.
- **C** — wrong: sleeping consumers waste money and still hit timeouts.
- **D** — wrong: rule targets run in parallel with no sequencing or waiting.

**Reference:** <https://docs.aws.amazon.com/step-functions/latest/dg/connect-to-resource.html#connect-wait-token>

</details>

### Q7 · Task 5.1 · Single answer

An EventBridge rule invokes a Lambda function asynchronously for every order event. When a downstream API was unavailable for 3 hours, events that failed after Lambda's retries were lost, and the team had no way to reprocess them.

What should the DevOps engineer configure so that failed events are kept for reprocessing?

- **A.** Increase the function's memory.
- **B.** Set the function's reserved concurrency to 0 during outages.
- **C.** Enable X-Ray tracing on the function.
- **D.** An on-failure destination (or a DLQ) on the function's asynchronous invocation configuration, and a dead-letter queue on the EventBridge rule's target, so that events failing delivery or processing are kept in SQS.

<details><summary>Answer</summary>

**Answer: D**

**Why (P9):** Asynchronous invocations retry, then discard, unless a destination or DLQ is set. The rule target's DLQ catches events EventBridge couldn't deliver.

- **A** — wrong: doesn't help with an unavailable downstream.
- **B** — wrong: throttling everything drops or delays events with no durable store.
- **C** — wrong: observability doesn't keep anything.
- **D** — correct: failed events land in durable queues for redrive.

**Reference:** <https://docs.aws.amazon.com/lambda/latest/dg/invocation-async-retain-records.html>

</details>

### Q8 · Task 5.2 · Single answer

An EC2 Image Builder pipeline publishes a new hardened AMI each week. The production Auto Scaling group must automatically move to each new AMI: gradually, at full capacity, and with automatic rollback if the 5xx alarm fires. No manual steps.

What should the DevOps engineer implement?

- **A.** A Systems Manager Patch Manager maintenance window on the existing instances.
- **B.** An EventBridge rule on the Image Builder image state change (AVAILABLE) that invokes a Lambda function, which creates a new launch template version with the new AMI ID and starts an instance refresh with checkpoints, a minimum healthy percentage of 100%, and alarm-based automatic rollback.
- **C.** A weekly email to the operations team with the new AMI ID.
- **D.** Terminate all instances when the AMI is published, so the group relaunches them with the new AMI.

<details><summary>Answer</summary>

**Answer: B**

**Why (P1, P4):** The AMI publication is an event. The response is an immutable, gradual, alarm-guarded fleet replacement.

- **A** — wrong: mutable patching, and it doesn't adopt the AMI.
- **B** — correct: event → launch template version → instance refresh with rollback.
- **C** — wrong: manual.
- **D** — wrong: drops all capacity, and terminating doesn't change the launch template.

**Reference:** <https://docs.aws.amazon.com/autoscaling/ec2/userguide/instance-refresh-rollback.html>

</details>

### Q9 · Task 5.2 · Single answer

GuardDuty reports `CryptoCurrency:EC2/BitcoinTool.B!DNS` for an instance in an Auto Scaling group. The security team requires an automated response that stops the malicious activity **and preserves forensic evidence**. The Auto Scaling group must not terminate the instance.

What should the response automation do?

- **A.** Terminate the instance immediately and let the Auto Scaling group replace it.
- **B.** Reboot the instance to stop the mining process.
- **C.** Detach the instance from the Auto Scaling group (so a replacement launches and the instance isn't terminated), snapshot its EBS volumes, replace its security groups with an isolation security group that allows no traffic, and tag it for investigation.
- **D.** Delete the instance's IAM role.

<details><summary>Answer</summary>

**Answer: C**

**Why (P7, P6):** Containment and evidence come before cleanup. Detaching keeps the group from replacing and terminating the instance, snapshots preserve disk state, and the isolation security group cuts network access.

- **A** — wrong: destroys the evidence.
- **B** — wrong: the miner may come back, and volatile evidence is lost.
- **C** — correct: isolate and preserve.
- **D** — wrong: may break other workloads that use the role, and doesn't stop the network activity.

**Reference:** <https://docs.aws.amazon.com/guardduty/latest/ug/compromised-ec2.html>

</details>

### Q10 · Task 5.2 · Select TWO

Twice, someone with administrator access in a member account turned off the account-level S3 Block Public Access setting. The company wants this to be impossible in future and, as defense in depth, any change to be reverted automatically within minutes.

Which combination of steps meets these requirements? (Select TWO.)

- **A.** Attach an SCP that denies `s3:PutAccountPublicAccessBlock` to all principals except a designated security role.
- **B.** Ask Amazon Macie to review the buckets every day.
- **C.** Run a periodic AWS Config rule every 24 hours and email the results.
- **D.** Send a monthly reminder to account administrators.
- **E.** Create an EventBridge rule on the CloudTrail event `PutAccountPublicAccessBlock` that invokes an automation (Lambda or SSM Automation) to re-enable all four Block Public Access settings and notify the security team.

<details><summary>Answer</summary>

**Answer: A, E**

**Why (P2, P1):** The SCP prevents the change outright. The event-driven reversal covers anyone exempted, or any missed path, within minutes.

- **A** — correct: preventive guardrail.
- **B** — wrong: Macie finds sensitive data. It doesn't enforce account settings.
- **C** — wrong: daily and notification-only.
- **D** — wrong: not a control.
- **E** — correct: detective plus corrective, in near real time.

**Reference:** <https://docs.aws.amazon.com/AmazonS3/latest/userguide/access-control-block-public-access.html>

</details>

### Q11 · Task 5.2 · Single answer

A standalone EC2 instance running a legacy agent occasionally hangs inside the OS. The instance status check (`StatusCheckFailed_Instance`) fails, but the system status check passes. A reboot always fixes it. The team wants this to happen automatically.

What should the DevOps engineer configure?

- **A.** A CloudWatch alarm on `StatusCheckFailed_Instance` with the EC2 reboot action.
- **B.** A CloudWatch alarm on `StatusCheckFailed_System` with the EC2 recover action.
- **C.** An Auto Scaling group with a minimum of 1.
- **D.** A Lambda function, invoked every minute, that checks the status and reboots the instance.

<details><summary>Answer</summary>

**Answer: A**

**Why (P7, P12):** An instance-level (OS) failure is fixed by rebooting, and CloudWatch alarms can run the reboot action directly.

- **A** — correct: native and targeted.
- **B** — wrong: the system check passes, so this alarm never fires, and recovery is for host failures.
- **C** — wrong: replaces the instance, losing its identity and state, and only reacts to failed health checks.
- **D** — wrong: custom polling.

**Reference:** <https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/UsingAlarmActions.html>

</details>

### Q12 · Task 5.2 · Single answer

Security analysts triage findings in AWS Security Hub. For some finding types, they want to select findings in the console and trigger a standard remediation (for example, revoking an overly permissive security-group rule) with one click, not automatically for every finding.

What should the DevOps engineer implement?

- **A.** A Security Hub automation rule that suppresses those findings.
- **B.** A daily report of the findings, emailed to the analysts.
- **C.** An AWS Config conformance pack.
- **D.** A Security Hub custom action, plus an EventBridge rule that matches the `Security Hub Findings - Custom Action` event for that action and invokes the remediation Lambda function or SSM Automation runbook.

<details><summary>Answer</summary>

**Answer: D**

**Why (P1):** Custom actions send the selected findings to EventBridge as an event, which can trigger any remediation. The human decides; the automation executes.

- **A** — wrong: automation rules update findings (suppress, change severity). They don't remediate resources.
- **B** — wrong: no remediation.
- **C** — wrong: deploys checks; there's no analyst-triggered action.
- **D** — correct: analyst-initiated, automated execution.

**Reference:** <https://docs.aws.amazon.com/securityhub/latest/userguide/securityhub-cwe-custom-actions.html>

</details>

### Q13 · Task 5.2 · Single answer

An EventBridge rule matches the CloudTrail event `AuthorizeSecurityGroupIngress` and invokes a Lambda function that revokes any new inbound rule allowing `0.0.0.0/0`. The network team's approved automation role sometimes legitimately adds such rules on public load balancer security groups, and the Lambda function keeps reverting them.

What is the BEST way to fix this?

- **A.** Disable the rule whenever the network team deploys.
- **B.** Add an `anything-but` condition on `detail.userIdentity.sessionContext.sessionIssuer.arn` to the event pattern, excluding the approved automation role, and keep remediating everything else.
- **C.** Delete the Lambda function and rely on weekly manual reviews.
- **D.** Grant the network team's role permission to call `RevokeSecurityGroupIngress`.

<details><summary>Answer</summary>

**Answer: B**

**Why (P1):** Event patterns can filter on who made the call. Excluding the approved actor fixes the false positives while keeping the control for everyone else.

- **A** — wrong: manual, and creates windows with no protection.
- **B** — correct: precise filtering at the routing layer.
- **C** — wrong: removes the control.
- **D** — wrong: doesn't stop the Lambda function from reverting the approved changes.

**Reference:** <https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-event-patterns-content-based-filtering.html>

</details>

### Q14 · Task 5.3 · Single answer

A pipeline with a CodeCommit source was recreated from a CloudFormation template in a new account. Pushes to `main` no longer start the pipeline, but starting it manually works. The source action has `PollForSourceChanges: false`.

What is the MOST likely cause?

- **A.** The CodeCommit repository has no approval rule template.
- **B.** The pipeline's artifact bucket isn't versioned.
- **C.** The template doesn't create the EventBridge rule (and its role with `codepipeline:StartPipelineExecution`) that starts the pipeline on `CodeCommit Repository State Change` events for `main`.
- **D.** The pipeline is a V1 type and can't be triggered by commits.

<details><summary>Answer</summary>

**Answer: C**

**Why (P1):** With polling disabled, change detection relies on an EventBridge rule. The console creates it automatically, but IaC must declare it explicitly.

- **A** — wrong: approval rules govern pull requests, not pipeline triggers.
- **B** — wrong: bucket versioning matters for S3 **sources**, not the artifact store, and wouldn't stop a trigger.
- **C** — correct: the missing event rule.
- **D** — wrong: V1 pipelines can be started by EventBridge rules.

**Reference:** <https://docs.aws.amazon.com/codepipeline/latest/userguide/pipelines-trigger-source-repo-changes-cfn.html>

</details>

### Q15 · Task 5.3 · Single answer

ECS tasks on Fargate in private subnets fail to start with `CannotPullContainerError: ... i/o timeout` when pulling from Amazon ECR in the same account. The VPC has no NAT gateway, by design. The task execution role has the `AmazonECSTaskExecutionRolePolicy` managed policy.

What should the DevOps engineer do?

- **A.** Create interface VPC endpoints for `com.amazonaws.<region>.ecr.api` and `com.amazonaws.<region>.ecr.dkr`, and a gateway endpoint for S3 (plus a CloudWatch Logs endpoint if the tasks use `awslogs`).
- **B.** Attach `AmazonEC2ContainerRegistryFullAccess` to the task role.
- **C.** Enable public IP assignment on the tasks while they stay in private subnets.
- **D.** Make the ECR repository public.

<details><summary>Answer</summary>

**Answer: A**

**Why (P7):** An i/o timeout means there's no network path. Pulling from ECR privately needs the ECR API and Docker endpoints, plus S3, where the image layers are stored.

- **A** — correct: the documented private-pull setup.
- **B** — wrong: the permissions are already sufficient, and image pulls use the execution role, not the task role.
- **C** — wrong: public IPs need an internet gateway route, which private subnets don't have.
- **D** — wrong: exposes the images and still needs a network path.

**Reference:** <https://docs.aws.amazon.com/AmazonECR/latest/userguide/vpc-endpoints.html>

</details>

### Q16 · Task 5.3 · Select TWO

An ECS service's new task definition fails in two ways. Tasks fail to start with `ResourceInitializationError: unable to pull secrets` for a Secrets Manager secret referenced in the container definition. When started without the secret, the application logs `AccessDeniedException` when it calls DynamoDB.

Which combination of changes fixes both problems with least privilege? (Select TWO.)

- **A.** Grant the task **execution** role access to the DynamoDB table.
- **B.** Grant the task **execution** role `secretsmanager:GetSecretValue` on the secret (and `kms:Decrypt` if a customer managed key encrypts it).
- **C.** Grant the task **role** `secretsmanager:GetSecretValue` on the secret.
- **D.** Grant the task **role** the required DynamoDB actions on the table.
- **E.** Attach `AdministratorAccess` to both roles.

<details><summary>Answer</summary>

**Answer: B, D**

**Why (P14):** The **execution role** is used by the ECS agent to pull images, write logs and inject secrets at start. The **task role** is what the application's AWS SDK calls use.

- **A** — wrong: the application doesn't use the execution role's credentials.
- **B** — correct: secret injection happens with the execution role.
- **C** — wrong: the task role isn't used to inject secrets at startup.
- **D** — correct: the application's permissions belong on the task role.
- **E** — wrong: violates least privilege.

**Reference:** <https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task_execution_IAM_role.html>

</details>

### Q17 · Task 5.3 · Single answer

A CloudFormation stack update failed, and the automatic rollback then failed too. The stack is now in `UPDATE_ROLLBACK_FAILED`. The events show that rollback couldn't restore an Amazon SNS subscription that someone had deleted manually last week.

What should the DevOps engineer do to return the stack to a working state?

- **A.** Delete the stack and recreate it from scratch.
- **B.** Run drift detection, which repairs drifted resources automatically.
- **C.** Update the stack again with the same template.
- **D.** Run `ContinueUpdateRollback`, specifying the SNS subscription's logical ID in `ResourcesToSkip`, and then reconcile the template and the resource.

<details><summary>Answer</summary>

**Answer: D**

**Why (P3):** `UPDATE_ROLLBACK_FAILED` is resolved by continuing the rollback, optionally skipping resources that can't be rolled back. That gets the stack to `UPDATE_ROLLBACK_COMPLETE`.

- **A** — wrong: destructive and unnecessary.
- **B** — wrong: drift detection only reports. It doesn't repair anything.
- **C** — wrong: a stack in `UPDATE_ROLLBACK_FAILED` can't be updated until the rollback completes.
- **D** — correct: the documented recovery path.

**Reference:** <https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/using-cfn-updating-stacks-continueupdaterollback.html>

</details>

### Q18 · Task 5.3 · Single answer

After a new release, instances in an Auto Scaling group launch, run for about 2 minutes, and are terminated as unhealthy, over and over. The activity history shows "ELB health check failed". The new version needs about 4 minutes to start (it runs database migrations). The health check path itself is correct.

What should the DevOps engineer change?

- **A.** Change the group's health check type to `EC2` permanently.
- **B.** Increase the Auto Scaling group's health check grace period to cover the startup time (for example 300 seconds), and consider moving the migrations out of instance startup.
- **C.** Increase the group's maximum size.
- **D.** Remove the instances from the load balancer.

<details><summary>Answer</summary>

**Answer: B**

**Why (P7):** The grace period tells the group not to act on health checks until an instance has had time to start. Here it's shorter than the startup time.

- **A** — wrong: hides real application failures from then on.
- **B** — correct: matches the grace period to reality (and migrations belong in a deployment step).
- **C** — wrong: more instances get terminated in the same loop.
- **D** — wrong: removes all traffic.

**Reference:** <https://docs.aws.amazon.com/autoscaling/ec2/userguide/health-check-grace-period.html>

</details>

### Q19 · Task 5.3 · Single answer

A Lambda function was attached to a VPC so that it can reach a private RDS database. Since then, its calls to a public third-party API time out. The function's subnets are private, and their route table has only the local route.

What should the DevOps engineer do?

- **A.** Assign a public IP address to the Lambda function's ENI.
- **B.** Increase the function's timeout to 15 minutes.
- **C.** Add a NAT gateway in a public subnet, and a default route (`0.0.0.0/0`) from the function's private subnets to the NAT gateway.
- **D.** Move the function into a public subnet with an internet gateway route.

<details><summary>Answer</summary>

**Answer: C**

**Why (P7):** Lambda functions in a VPC have no public IP address, so internet access goes through NAT from private subnets.

- **A** — wrong: Lambda ENIs can't have public IPs.
- **B** — wrong: the call never connects, however long it waits.
- **C** — correct: the documented pattern.
- **D** — wrong: VPC-attached Lambda functions don't get public IPs, even in public subnets, so this doesn't give internet access.

**Reference:** <https://docs.aws.amazon.com/lambda/latest/dg/configuration-vpc-internet.html>

</details>

### Q20 · Task 5.3 · Single answer

During an outage, the payment service lost connectivity to its database at 14:02. The team suspects a configuration change. It needs to find out quickly **who** changed **which** resource, and what the configuration looked like **before** the change.

Which combination of tools gives this information most directly?

- **A.** VPC Flow Logs and X-Ray.
- **B.** AWS CloudTrail (the API call, the caller and the time) together with the AWS Config resource timeline (the configuration before and after, linked to the CloudTrail event).
- **C.** CloudWatch metrics and dashboards.
- **D.** Amazon Inspector findings.

<details><summary>Answer</summary>

**Answer: B**

**Why (P10):** CloudTrail answers "who did what, and when". Config answers "what changed, from what to what". Together they give the root cause of a configuration change.

- **A** — wrong: these show traffic and requests, not the actor or the change.
- **B** — correct: actor plus configuration history.
- **C** — wrong: show symptoms, not changes.
- **D** — wrong: vulnerability findings.

**Reference:** <https://docs.aws.amazon.com/config/latest/developerguide/view-manage-resource-console.html>

</details>
