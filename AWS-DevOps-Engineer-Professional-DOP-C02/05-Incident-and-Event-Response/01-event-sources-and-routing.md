# Domain 5 · 01 · Event Sources, Routing and Event-Driven Architectures

> **Exam task:** 5.1 (event sources: AWS Health, EventBridge, CloudTrail; fan-out, streaming and queuing; event-processing workflows with SQS, Kinesis, SNS, Lambda, Step Functions). **Principles:** P1 (events), P9 (buffers), P11 (KMS on topics and queues).

## 1. First principles

1. **Producers shouldn't know their consumers.** An event says "this happened". Routing decides who cares. That's what makes adding a new reaction (notify, remediate, audit) a configuration change instead of a code change.
2. **Pick the transport by delivery semantics:**

   | Transport | Delivery semantics |
   |---|---|
   | **EventBridge** | Content-based routing to many targets; at-least-once with retries |
   | **SNS** | Push fan-out to subscribers; filtering on attributes or body |
   | **SQS** | Pull-based buffer; each message processed by one consumer; retries via visibility timeout; DLQ |
   | **Kinesis Data Streams** | Ordered per shard; **replayable**; many independent consumers |

3. **At-least-once means duplicates.** Every consumer must be **idempotent**: dedupe by event ID, use conditional writes, or make operations naturally idempotent.

---

## 2. Amazon EventBridge

### 2.1 Building blocks

| Component | Facts |
|---|---|
| **Event buses** | The **default** bus (AWS service events and CloudTrail events land here), **custom** buses (your application events), and **partner** buses (SaaS such as Datadog, PagerDuty, Zendesk) |
| **Rules** | Match an **event pattern** (or a schedule, the legacy way) and send to **up to 5 targets** per rule |
| **Event patterns** | Exact values; prefix/suffix; `anything-but`; numeric ranges; `exists`; `equals-ignore-case`; wildcards; `$or` across fields. Patterns match on **`source`**, **`detail-type`** and fields in **`detail`** |
| **Targets** | Lambda, SNS, SQS, Step Functions, Kinesis, Firehose, ECS tasks, CodePipeline, CodeBuild, **SSM Automation / Run Command / OpsItems**, API destinations (any HTTPS API with auth), another event bus (cross-account or cross-Region), CloudWatch Logs, Batch, and more |
| **Input transformer** | Reshape the event before it reaches the target (e.g. a readable SNS message: `"Instance <id> changed to <state>"`) |
| **Retry and DLQ** | Retries for up to **24 hours / 185 attempts** with backoff; attach an **SQS dead-letter queue per target** for events that still fail |
| **Archive and replay** | Archive events (all, or filtered) and **replay** them later: recovery after a consumer bug, or testing |
| **Cross-account / cross-Region** | A rule targets a bus in another account or Region. The receiving bus needs a **resource policy** allowing the sender (or the whole organization via `aws:PrincipalOrgID`). Pattern: every account forwards security events to a central bus in the security account |
| **EventBridge Pipes** | Point-to-point **source → filter → enrich → target** (sources: SQS, Kinesis, DynamoDB Streams, MSK, MQ…), replacing glue Lambdas |
| **EventBridge Scheduler** | One-time and recurring schedules (cron/rate, **time zones**, flexible windows) invoking 270+ AWS API targets directly; the modern replacement for scheduled rules |
| **Schema registry** | Discovers event schemas; generates code bindings |

### 2.2 The AWS events you'll meet in questions

| Event (`detail-type`) | Typical automation |
|---|---|
| `EC2 Instance State-change Notification` | Notify on stop/terminate of production instances; record to a CMDB |
| `EC2 Instance Launch Successful` / `Terminate Successful`, **`EC2 Instance-launch Lifecycle Action`** / **`EC2 Instance-terminate Lifecycle Action`** (Auto Scaling) | Lifecycle-hook processing (see [03/02](../03-Resilient-Cloud-Solutions/02-scalability-and-auto-scaling.md#22-lifecycle-hooks)) |
| `CodePipeline Pipeline/Stage/Action Execution State Change`, `CodeBuild Build State Change`, `CodeDeploy Deployment State-change Notification` | Chat notifications, ticket creation, metrics |
| `CodeCommit Repository State Change`, `CodeCommit Pull Request State Change` | Start pipelines and PR builds |
| `ECS Task State Change`, `ECS Service Action` | Alert on tasks stopping with an error `stoppedReason` |
| **`GuardDuty Finding`**, **`Security Hub Findings - Imported`**, `Inspector2 Finding`, `Macie Finding` | Security response (see [02-automated-remediation-patterns.md](02-automated-remediation-patterns.md)) |
| **`Config Rules Compliance Change`**, `Config Configuration Item Change` | Notify or remediate on non-compliance |
| **`AWS Health Event`** | Scheduled maintenance, service issues, **exposed credentials** |
| `CloudWatch Alarm State Change` | Route alarms to many targets |
| `AWS API Call via CloudTrail` | React to any write API call, e.g. `StopLogging`, `PutBucketPolicy`, `AuthorizeSecurityGroupIngress` (needs a trail; see the [P1 sub-rule](../00-Exam-Strategy-and-First-Principles/02-first-principles-mental-models.md#p1--every-action-is-an-api-call-and-every-api-call-can-be-an-event)) |
| `ACM Certificate Approaching Expiration` | Renewal or notification for imported certificates (ACM-issued ones auto-renew) |
| `Object Created` / `Object Deleted` (S3, with EventBridge notifications enabled on the bucket) | Pipelines, processing, audit |
| `Parameter Store Change`, `KMS Key Rotation`, `Backup Job State Change`, `Step Functions Execution Status Change` | Operational notifications |

## 3. AWS Health

* **Account-specific events:** scheduled changes (EC2 instance **retirement**, host maintenance, RDS maintenance), issues affecting **your** resources, and **account notifications**. One of these is **`AWS_RISK_CREDENTIALS_EXPOSED`**: AWS detected your access key exposed publicly, e.g. on GitHub.
* **Public events:** Regional service issues.
* **Delivery:** Health events go to **EventBridge** in the Region concerned (global events to us-east-1). The **AWS Health API** needs a Business, Enterprise On-Ramp or Enterprise Support plan.
* **Organizational view:** aggregate Health events for all accounts, viewable from the management account or a **delegated administrator** (P13).
* **Exam patterns:**
  * "Automatically respond when AWS reports an exposed access key" → EventBridge rule on the Health event `AWS_RISK_CREDENTIALS_EXPOSED` → Step Functions/Lambda: deactivate the key, look up recent API calls in CloudTrail, notify.
  * "Get notified of scheduled EC2 retirements across all accounts" → Health organizational view + EventBridge → SNS, or an SSM Automation that stops and starts the instance to move it to new hardware during a maintenance window.

## 4. Event-driven architecture patterns

### 4.1 Fan-out

* **SNS → several SQS queues:** every consumer gets its own durable copy and processes at its own pace. The classic answer when an S3 bucket's events must feed two systems. **S3 event notifications allow only one destination per event type and prefix overlap**, so fan out through SNS or EventBridge.
* **EventBridge rule with several targets,** or several rules: content-based routing to different consumers.
* **SNS message filtering:** subscription filter policies on message attributes or the body, so each subscriber gets only relevant messages.

### 4.2 Queuing (SQS)

* **Standard queues** (at-least-once, best-effort order, near-unlimited throughput) vs **FIFO queues** (ordered per message group, exactly-once processing within a deduplication window, throughput limits).
* **Visibility timeout** must exceed the processing time, or messages are processed twice. For Lambda consumers, AWS recommends **6 × the function timeout** on the queue.
* **DLQ via redrive policy** (`maxReceiveCount`). Alarm on DLQ depth; **redrive** the messages back after a fix.
* **Long polling** reduces empty receives.

### 4.3 Streaming (Kinesis Data Streams, DynamoDB Streams)

* **Ordered per shard** (partition key); **replay** within the retention window; several consumers (enhanced fan-out for dedicated throughput).
* **Lambda event source mapping on streams:**
  * A failing batch **blocks its shard** until it succeeds or expires.
  * Use **bisect batch on error**, **maximum retry attempts**, **maximum record age**, and an **on-failure destination** (SQS/SNS) so that one bad record doesn't stall the shard.
  * Watch **`IteratorAge`**.

### 4.4 Orchestration vs choreography

* **Choreography:** services react to each other's events through EventBridge. Loosely coupled, harder to see end to end.
* **Orchestration (Step Functions):** one state machine coordinates steps with **retries, catches, timeouts, waits, parallel and Map states, and human approval** (`.waitForTaskToken` callbacks).
  * **Standard workflows:** long-running (up to 1 year), exactly-once state transitions, full history.
  * **Express workflows:** high-volume, short (up to 5 minutes), at-least-once.

### 4.5 Lambda asynchronous invocation

* Async invokes (from S3, SNS, EventBridge) retry **twice** on function errors by default (configurable 0–2), with a maximum event age of up to 6 hours.
* Configure **destinations** (on-success / on-failure → SQS, SNS, Lambda, EventBridge) or a **DLQ** (SQS/SNS) so failed events are kept.
* Destinations carry more context (the response and error), so prefer them over the DLQ.

## 5. Encryption gotcha: KMS-encrypted topics and queues

If an SNS topic or SQS queue is encrypted with the **AWS-managed key** (`aws/sns`, `aws/sqs`), **AWS services can't publish to it.** That covers CloudWatch alarms, EventBridge and S3 event notifications, because you can't edit an AWS-managed key's policy to allow them. Use a **customer-managed KMS key** whose key policy allows the service principal (`events.amazonaws.com`, `cloudwatch.amazonaws.com`, `s3.amazonaws.com`) `kms:GenerateDataKey*` and `kms:Decrypt`. "Alarm fires but no notification arrives" on an encrypted topic is this problem (P11).

## 6. Exam traps

* **Polling for state** (a scheduled Lambda calling `Describe*`) when an event exists (P1).
* **S3 event notifications with two Lambda targets for the same events:** not allowed with overlapping prefixes. Fan out via SNS or EventBridge.
* **Health API calls** need Business support or higher. EventBridge delivery of Health events doesn't.
* **SQS visibility timeout shorter than processing time** → duplicate processing.
* **A poison record on a Kinesis shard** stalls the Lambda consumer. Use bisect, max retries and an on-failure destination.
* **A cross-account EventBridge target** needs the target bus's **resource policy**, plus a role on the sending rule for cross-account bus targets.

## References

* EventBridge event patterns — <https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-event-patterns.html>
* EventBridge targets — <https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-targets.html>
* Cross-account event delivery — <https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-cross-account.html>
* Archive and replay — <https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-archive.html>
* EventBridge Pipes — <https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-pipes.html>
* AWS Health with EventBridge — <https://docs.aws.amazon.com/health/latest/ug/cloudwatch-events-health.html>
* AWS Health organizational view — <https://docs.aws.amazon.com/health/latest/ug/aggregate-events.html>
* SQS visibility timeout — <https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/sqs-visibility-timeout.html>
* Lambda with Kinesis (error handling) — <https://docs.aws.amazon.com/lambda/latest/dg/with-kinesis.html>
* Lambda asynchronous invocation and destinations — <https://docs.aws.amazon.com/lambda/latest/dg/invocation-async.html>
* SNS message filtering — <https://docs.aws.amazon.com/sns/latest/dg/sns-message-filtering.html>
* Step Functions workflow types — <https://docs.aws.amazon.com/step-functions/latest/dg/concepts-standard-vs-express.html>
