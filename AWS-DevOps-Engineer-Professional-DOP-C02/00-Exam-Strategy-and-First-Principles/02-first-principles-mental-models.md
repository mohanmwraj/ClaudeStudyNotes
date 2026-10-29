# 02 · First-Principles Mental Models

DOP-C02 has hundreds of possible scenarios but only about a dozen underlying mechanisms. If you understand a mechanism, you don't need to memorize the scenarios built on it: you can **derive** the answer, and you can explain why each distractor fails. Every later file in this repo refers back to the principles below by number (P1–P14).

Each principle has four parts: **the mechanism** (how AWS actually works), **the consequence** (what follows from it), **how it appears in questions**, and **the distractor it kills**.

---

## P1 · Every action is an API call, and every API call can be an event

**Mechanism.** Everything in AWS, whether console, CLI, SDK, CloudFormation or another service, is a signed HTTPS request to a service API. CloudTrail records management API calls. Many services also emit their own state-change events (CodePipeline stage changes, EC2 state changes, GuardDuty findings, AWS Health events, CodeBuild build state, ECS task state). All of these arrive on the **EventBridge default event bus**. An EventBridge rule matches an event pattern and sends the event to a target: Lambda, SNS, SQS, Step Functions, SSM Automation, CodePipeline, ECS task, another event bus, and more.

**Consequence.** Automation on AWS is **event → rule → target**. Anything that can be observed can be reacted to within seconds, with no servers and no polling.

**How it appears.** "The pipeline must start as soon as code is pushed", "notify the team when an instance is terminated", "remediate when someone disables CloudTrail". The answer is an EventBridge rule on the native event, or on the CloudTrail-recorded API call for services without native events.

**Distractor killed.** Anything that **polls**: a Lambda on a cron schedule that checks for changes, a periodic pipeline source check, a script that lists resources every 5 minutes. Polling adds latency, cost and code. If an event exists, polling is wrong.

> **Sub-rule (from the [EventBridge docs](https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-service-event-cloudtrail.html)):**
>
> * `AWS API Call via CloudTrail` events reach EventBridge only if **a CloudTrail trail with logging is enabled**. CloudTrail Event history alone isn't enough.
> * The events arrive on the **default event bus** of the Region where the call happened. Calls to global services such as IAM are recorded in us-east-1.
> * Write (mutating) calls match rules in the normal `ENABLED` state. Read-only `Get*/List*/Describe*` calls match only rules in the `ENABLED_WITH_ALL_CLOUDTRAIL_MANAGEMENT_EVENTS` state.

## P2 · Authorization is an intersection, and an explicit deny always wins

**Mechanism.** For a request in one account, AWS evaluates, in effect:

```text
allowed = NOT explicit-deny-anywhere
          AND (SCPs allow)            -- Organizations guardrail on the principal's account
          AND (RCPs allow)            -- Organizations guardrail on the resource's account
          AND (permissions boundary allows, if one is set)
          AND (session policy allows, if one is passed)
          AND (identity policy allows OR resource policy allows)
```

Across accounts, **both** sides must allow: the caller's identity policy must allow the action on the foreign resource, **and** the resource's policy (or the target role's trust policy) must allow the caller.

**Consequence.** SCPs, RCPs, permission boundaries and session policies **never grant** anything. They only cap. A missing allow is an implicit deny; an explicit deny overrides every allow.

**How it appears.** "A developer has AdministratorAccess but can't create resources in eu-west-3" (an SCP denies that Region). "Delegate IAM role creation to developers without letting them escalate privileges" (a permissions boundary plus a condition that requires it on every role they create). "A Lambda in account A can't read a bucket in account B" (the bucket policy or KMS key policy in account B doesn't allow it).

**Distractor killed.** "Attach a policy that allows X" when an SCP or explicit deny blocks X. Adding allows never beats a deny. Also killed: "Use an SCP to grant access."

## P3 · Desired state, drift and convergence

**Mechanism.** Infrastructure as code (CloudFormation, CDK, SAM), State Manager associations, Config rules and AppConfig all express **desired state**. Reality can diverge (drift) through manual changes, failures or time. Tools differ in whether they **detect** drift (CloudFormation drift detection, Config rules) or **converge** back to the desired state (State Manager re-applies on a schedule; Config remediation runs an SSM Automation document; a stack update re-applies the template).

**Consequence.** Changing a resource outside its owning tool creates drift, and the next stack update may revert or fail on it. The fix for drift is to change the **source of truth** and redeploy, or to remediate automatically.

**How it appears.** "Ensure all instances keep the CloudWatch agent running with the approved configuration" (State Manager association). "Detect and fix security groups that allow 0.0.0.0/0 on port 22" (Config managed rule + automatic remediation). "Someone changed a resource created by CloudFormation" (drift detection, then update the template).

**Distractor killed.** "Log in and fix it" or "run a one-time script". One-time actions don't hold a desired state.

## P4 · Immutable beats mutable when you need safe rollback

**Mechanism.** A **mutable** deployment changes running resources in place: CodeDeploy in-place, Elastic Beanstalk rolling, `yum update` on a live fleet. An **immutable** deployment creates new resources from a versioned artifact and moves traffic: new AMI and new ASG, new ECS task set, new Lambda version, Elastic Beanstalk immutable or blue/green. The old resources stay intact until the new ones are proven.

**Consequence.** With immutable deployments, rollback means **routing traffic back**, which takes seconds and is safe. With mutable ones, rollback means **redeploying the previous version**, which takes minutes, and the fleet is mixed and possibly broken in between. Immutable needs more temporary capacity and a versioned artifact (AMI, image tag, Lambda version).

**How it appears.** "Minimize impact if the new version fails", "fastest rollback", "no reduced capacity during deployment", "the instances must be patched with a new golden AMI" (EC2 Image Builder + ASG instance refresh or launch-template update).

**Distractor killed.** In-place or rolling options when the requirement is "fastest rollback" or "no impact on capacity".

## P5 · A deployment strategy is really a traffic-routing strategy, gated by health

**Mechanism.** Blue/green, canary and linear differ only in **how traffic moves** from old to new, and that movement happens in a routing layer:

| Routing layer | Who moves the traffic |
|---|---|
| ALB listener rules / target groups | CodeDeploy (EC2 blue/green, ECS blue/green), ECS native blue/green, Elastic Beanstalk |
| Lambda alias weights | CodeDeploy (`Canary10Percent5Minutes`, `Linear10PercentEvery1Minute`, ...), via SAM `DeploymentPreference` |
| Route 53 weighted records | You, or a pipeline step (classic blue/green between two stacks or environments) |
| CNAME swap | Elastic Beanstalk "swap environment URLs" |
| API Gateway stage canary | API Gateway canary settings |
| CloudFront | Continuous deployment with a staging distribution |

Progression is gated by **health**: CloudWatch alarms attached to the deployment (CodeDeploy, SAM, CloudFormation rollback triggers, CodePipeline V2 stage conditions), plus validation hooks such as CodeDeploy `BeforeAllowTraffic`/`AfterAllowTraffic` Lambda functions.

**Consequence.** "Automatic rollback" requires a **health signal wired to the deployment mechanism**: an alarm on errors or latency, attached to the deployment group or stack. A deployment with no alarms only rolls back on deployment *failure*, not on *bad behaviour*.

**How it appears.** "Shift 10% of traffic, wait, then the rest, and roll back automatically if errors increase" (canary deployment configuration + CloudWatch alarm on the deployment group or `DeploymentPreference.Alarms`). DNS-based shifting is slow to drain because clients cache DNS; that's why load-balancer or alias-based shifting is preferred.

**Distractor killed.** "Monitor the dashboard and manually roll back" when the question says automatically. Also DNS weighted routing when instant, exact percentages matter.

## P6 · Isolation limits blast radius: account > Region > AZ > cell

**Mechanism.** An **AWS account** is the strongest isolation boundary: separate IAM, quotas, billing and blast radius. Regions are fully independent; Availability Zones are independent failure domains within a Region. AWS Organizations groups accounts into OUs with SCPs; Control Tower builds a governed landing zone on top.

**Consequence.** Separate workloads and environments (dev, test, prod) into accounts. Centralize logging and security in dedicated accounts. Roll changes out progressively: one account or Region first, then widen. StackSets "maximum concurrent accounts" and "failure tolerance" settings, and pipeline stages per environment, implement exactly this.

**How it appears.** "A misconfiguration in dev must never affect production" (separate accounts). "Deploy a baseline to every new account automatically" (StackSets with service-managed permissions and automatic deployment on an OU, or Control Tower customizations). "Limit the impact of a bad deployment across 30 Regions" (StackSets with low concurrency and failure tolerance, or Region-by-Region pipeline stages).

**Distractor killed.** One shared account with IAM-only separation, or one-shot global deployments.

## P7 · Failure is normal, so design for automatic replacement

**Mechanism.** Health checks plus a controller that replaces unhealthy members: an EC2 Auto Scaling group replaces instances that fail EC2 or ELB health checks (when the ASG health check type is ELB); the ECS service scheduler replaces tasks; Route 53 health checks remove failed endpoints; RDS Multi-AZ fails over to the standby; EC2 automatic recovery restarts an instance on new hardware. Self-healing requires **statelessness at the compute layer**: state lives in RDS, DynamoDB, S3, EFS or ElastiCache.

**Consequence.** Instances are cattle. Configure them from launch templates and user data or AMIs, never by hand.

**How it appears.** "Instances behind an ALB are failing but the ASG doesn't replace them" (the ASG health check type is EC2, not ELB). "A single EC2 instance must recover automatically from a host failure" (a CloudWatch alarm with the recover action, or an ASG of min=max=1). "Remove single points of failure."

**Distractor killed.** Manual replacement, or "increase instance size".

## P8 · RTO and RPO price the disaster-recovery strategy

**Mechanism.** **RPO** is how much data you can lose, measured in time and set by replication or backup frequency. **RTO** is how long recovery may take, set by what is already running in the recovery Region.

| Strategy | What runs in the DR Region | Typical RPO | Typical RTO | Cost |
|---|---|---|---|---|
| Backup and restore | Nothing; backups are copied there | Hours (backup interval) | Hours | Lowest |
| Pilot light | Data replicated live (for example Aurora Global Database or DynamoDB global tables); compute **off**, only defined in IaC or as AMIs | Seconds to minutes | Tens of minutes | Low |
| Warm standby | A scaled-down but **running** full stack | Seconds to minutes | Minutes | Medium |
| Multi-site active/active | A full stack serving traffic in both Regions | Near zero | Near zero | Highest |

Cross-Region replication is **asynchronous**, so RPO is greater than zero, only small (Aurora Global Database typically under a second of lag; S3 Replication Time Control guarantees 99.99% of objects within 15 minutes).

**Consequence.** Choose the **cheapest** strategy that meets both numbers. "RPO 15 minutes, RTO 4 hours, cost-sensitive" doesn't need warm standby.

**How it appears.** Almost every Domain 3.3 question gives RTO, RPO and a cost hint.

**Distractor killed.** Over-engineering (multi-site for a 4-hour RTO) and under-engineering (backup and restore for a 15-minute RTO).

## P9 · Decouple with buffers, and scale on the backlog

**Mechanism.** A queue (SQS) or stream (Kinesis) between producer and consumer absorbs bursts, so the consumer can scale independently and failures retry. SQS gives at-least-once delivery, visibility timeouts and dead-letter queues; FIFO queues add ordering and deduplication. SNS fans out to many subscribers, and SNS → multiple SQS queues is the durable fan-out. EventBridge routes by content.

**Consequence.** Scale consumers on **backlog per instance** (ApproximateNumberOfMessagesVisible ÷ running instances) with target tracking, not on CPU. Make consumers **idempotent**, because messages can arrive twice.

**How it appears.** "Orders are lost when the processing tier is overloaded" (put SQS in between). "Scale workers based on queue depth" (a custom backlog-per-instance metric with target tracking). "Two systems both need every S3 event" (S3 → SNS → two SQS queues, or S3 → EventBridge with two rules).

**Distractor killed.** Bigger instances, or synchronous retries in the producer.

## P10 · Observe outcomes: metrics for trends, logs for detail, traces for causality

**Mechanism.**
* **Metrics** are numeric time series identified by namespace, name and dimensions. EC2 doesn't publish memory or disk-space metrics; you need the **CloudWatch agent**.
* **Alarms** evaluate a metric (or a metric-math expression, or anomaly band) and trigger actions: SNS, Auto Scaling, EC2 actions, SSM OpsItems/incidents.
* **Logs** are events. **Metric filters** turn log patterns into metrics. **Subscription filters** stream logs in near real time to Lambda, Kinesis Data Streams, Firehose or OpenSearch.
* **Traces** (X-Ray) follow one request across services.
* **Synthetic canaries** measure what a user sees, and **RUM** measures real users' browsers.

**Consequence.** Alarm on **symptoms** (error rate, latency, failed health checks) for rollback and paging; use metric math and composite alarms to cut noise. Put logs into a central account; store them cheaply in S3 with lifecycle policies; query with Logs Insights for recent data and Athena for S3-archived data.

**How it appears.** "Alert when the application logs ERROR more than 5 times in a minute" (metric filter + alarm). "Memory utilization" (CloudWatch agent). "Find which downstream call is slow" (X-Ray). "Detect an unusual spike without a fixed threshold" (anomaly detection alarm).

**Distractor killed.** "Enable detailed monitoring to get memory metrics": detailed monitoring only changes the period from 5 minutes to 1 minute.

## P11 · Encrypt by default; the key policy is the root of KMS access; secrets are fetched, never stored

**Mechanism.** Every KMS key has a **key policy**, the primary access control. IAM policies only work for a KMS key if the key policy allows the account to delegate to IAM (the default key policy does this). Cross-account use needs the key policy to allow the other account, **plus** an IAM allow in that account. AWS-managed keys (`aws/s3` and similar) **can't be shared cross-account**; use a customer-managed key. Secrets Manager stores secrets encrypted, controls access with IAM and resource policies, and **rotates** them automatically with a rotation Lambda; managed rotation exists for RDS, Redshift and DocumentDB, and some other services. Parameter Store `SecureString` is encrypted with KMS but has no built-in rotation.

**Consequence.** Cross-account artifact sharing (pipelines, AMIs, snapshots) needs a customer-managed key. Applications should read secrets at runtime (SDK call, ECS `secrets`, CodeBuild `env.secrets-manager`, Lambda extension), never from code, AMIs or plaintext environment variables.

**How it appears.** "A cross-account pipeline fails with AccessDenied when decrypting artifacts" (the artifact bucket uses the default `aws/s3` key; switch to a customer-managed key whose policy allows the target account's role). "Rotate the database password every 30 days automatically" (Secrets Manager rotation).

**Distractor killed.** "Store the password in a Parameter Store String parameter", "encrypt with the AWS-managed key and share it".

## P12 · Prefer the managed, native feature: "MOST operationally efficient" means less of your code

**Mechanism.** AWS keeps adding native features that replace custom glue: Config managed rules with SSM remediation, StackSets automatic deployment, Backup plans with cross-Region copy, ECR replication, CodeBuild test reports, CloudWatch anomaly detection, S3 Replication.

**Consequence.** When two options both work, the one with **fewer moving parts you own** (no Lambda to write, no cron, no servers to patch) is the answer to "LEAST operational overhead", "MOST operationally efficient" or "with the LEAST effort".

**How it appears.** Almost every question has one native option and two or three "write a Lambda that…" options.

**Distractor killed.** Custom Lambda or cron scripts that re-implement a native feature. Caveat: if no native feature exists for the requirement, a Lambda behind an EventBridge rule is exactly right (P1).

## P13 · Centralize at the organization level and delegate administration

**Mechanism.** Most security and governance services have an **organization mode** with a **delegated administrator** account:
* CloudTrail organization trail;
* Config aggregator, and organization-wide Config rules and conformance packs;
* GuardDuty, Security Hub, Inspector, Macie and Detective, auto-enabled for new member accounts;
* Firewall Manager;
* CloudFormation StackSets with service-managed permissions;
* AWS Backup policies;
* AWS Health organizational view;
* IAM Access Analyzer with the organization as the zone of trust;
* CloudWatch cross-account observability.

**Consequence.** Turn each service on **once**, for the whole organization, from a dedicated security or tooling account. New accounts are covered automatically, and the management account stays empty of workloads.

**How it appears.** "Ensure every current **and future** account has GuardDuty enabled" (organization integration + delegated admin + auto-enable). "Aggregate findings from 50 accounts and 3 Regions" (Security Hub delegated admin + cross-Region aggregation).

**Distractor killed.** "Write a script that enables the service in each account" or "Use StackSets to enable GuardDuty" when native organization auto-enable exists.

## P14 · Least privilege is built from roles, temporary credentials and guardrails

**Mechanism.**
* Humans federate (IAM Identity Center or SAML/OIDC) into **roles**.
* Machines use **roles**: EC2 instance profiles, ECS task roles, Lambda execution roles, IRSA or EKS Pod Identity, and OIDC federation for GitHub Actions.
* STS issues temporary credentials that expire.
* Long-term IAM user access keys are a liability, and the exam treats them as one.
* ABAC (tags on principals and resources, `aws:PrincipalTag`, `aws:ResourceTag`) scales permissions without editing policies for every new resource.

**Consequence.** For any "how should X authenticate" question, the answer is a **role** with temporary credentials. For "developers can create roles but must not escalate", the answer is a **permissions boundary**.

**How it appears.** "An on-premises server needs to call AWS APIs" (IAM Roles Anywhere, or SSM hybrid activation for managed-node functionality). "A third-party CI system deploys to AWS" (OIDC federation to a role with a constrained trust policy, not stored access keys).

**Distractor killed.** "Create an IAM user and store its access keys in…", in any form.

---

## The decoder: requirement phrase → principle → typical answer

| Phrase in the question | Principle | Typical answer shape |
|---|---|---|
| "as soon as", "in near real time", "automatically when" | P1 | EventBridge rule on the native or CloudTrail event → target |
| "LEAST operational overhead", "MOST operationally efficient" | P12 | The native managed feature; no custom code |
| "must not be able to", "prevent", "regardless of IAM permissions" | P2 | SCP or RCP (org-wide), permissions boundary, or an explicit Deny in a resource policy |
| "detect and remediate", "non-compliant", "drift" | P3 | Config rule + automatic remediation (SSM Automation), or State Manager |
| "fastest rollback", "no downtime", "minimize impact of a bad release" | P4, P5 | Immutable or blue/green + alarm-based automatic rollback |
| "gradually shift", "10% of traffic first" | P5 | Canary or linear deployment configuration (CodeDeploy, SAM, ECS, API Gateway canary) |
| "every new account", "all accounts in the organization" | P6, P13 | Organizations integration with auto-enable, StackSets service-managed auto-deployment, Control Tower |
| "self-healing", "replace unhealthy", "single point of failure" | P7 | ASG with ELB health checks; Multi-AZ; Route 53 health checks |
| "RPO of X, RTO of Y, cost-effective" | P8 | The cheapest DR tier that meets both numbers |
| "spikes", "messages lost", "scale workers" | P9 | SQS buffer; scale on backlog per instance; DLQ |
| "memory", "disk space", "custom application metric" | P10 | CloudWatch agent or `PutMetricData`/Embedded Metric Format |
| "rotate", "credentials in code", "cross-account decrypt" | P11 | Secrets Manager rotation; customer-managed KMS key with a key policy |
| "temporary credentials", "third-party access", "on-premises" | P14 | Roles via STS: OIDC federation, Roles Anywhere, external ID for third parties |
