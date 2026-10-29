# Mock Paper 3 · 75 Questions · 180 Minutes

**Instructions:**
* Set a timer for **180 minutes** and answer all 75 questions without notes.
* Write your answers on paper or in a text file (for example `1-C, 2-A, …`). For multiple-response questions, select exactly the number requested; there is no partial credit.
* Flag questions you're unsure about and come back to them. Never leave one blank.
* When finished, mark your answers with [09-mock-paper-3-answers.md](09-mock-paper-3-answers.md) and read the explanation for every question you missed **or guessed**.

**Composition** (matches the official DOP-C02 weighting): Domain 1: 17 · Domain 2: 13 · Domain 3: 11 · Domain 4: 11 · Domain 5: 10 · Domain 6: 13. The domain and task labels are shown to help your review. The real exam doesn't label questions.

**Scoring guide:** each question is worth 1 point. **60/75 (80%)** or better means you're ready; 53–59 means review your weak domains and retake; below 53 means study more before booking. AWS reports a scaled score, so these thresholds are a conservative readiness estimate, not a conversion.

---

### Q1 · Domain 1 · Task 1.1 · Single answer

A DevOps engineer creates an AWS CodeConnections connection to GitHub with a CloudFormation template, and a pipeline that uses it as its source. The first pipeline execution fails at the source action with an error that the connection isn't available.

What should the engineer do?

- **A.** Recreate the connection in a different Region.
- **B.** Complete the connection handshake in the console (Developer Tools → Settings → Connections → Update pending connection) with a GitHub account that can authorize the AWS Connector app, so that the connection moves from `PENDING` to `AVAILABLE`.
- **C.** Add the GitHub personal access token to the pipeline's source action configuration.
- **D.** Switch the pipeline to polling for changes.

### Q2 · Domain 6 · Task 6.1 · Single answer

A developer's IAM role has the `AdministratorAccess` policy attached. The role also has a permissions boundary that allows only `s3:*`, `dynamodb:*` and `logs:*`. The developer can't launch EC2 instances, and the error is an implicit deny. No SCPs restrict EC2.

Why?

- **A.** `AdministratorAccess` excludes EC2.
- **B.** EC2 requires MFA.
- **C.** Effective permissions are the intersection of the identity policy and the permissions boundary. The boundary doesn't allow `ec2:*`, so EC2 actions are implicitly denied.
- **D.** The role needs a service-linked role for EC2.

### Q3 · Domain 3 · Task 3.1 · Single answer

A web tier runs across three Availability Zones with an Auto Scaling group. At peak, it needs 30 instances. The business requires that the loss of an entire AZ cause **no** degradation, even before Auto Scaling can launch replacements.

How should capacity be provisioned?

- **A.** Run enough capacity that any two AZs can carry the full peak: 15 instances per AZ, 45 in total (static stability).
- **B.** Run 10 instances per AZ and rely on Auto Scaling to replace the lost AZ's instances.
- **C.** Run all 30 instances in the largest AZ.
- **D.** Use a warm pool in one AZ.

### Q4 · Domain 1 · Task 1.1 · Select TWO

A global application is deployed with CloudFormation to `us-east-1`, `eu-west-1` and `ap-southeast-2` from one pipeline in `us-east-1`. Releases must go to `us-east-1` first, be observed for 30 minutes with an automatic check of the error alarm, and only then go to the other two Regions (in parallel), limiting the blast radius of a bad release.

Which combination of pipeline features meets these requirements? (Select TWO.)

- **A.** Cross-Region CloudFormation deploy actions in successive stages (stage 1: `us-east-1`; stage 2: `eu-west-1` and `ap-southeast-2` as parallel actions), with an artifact store configured for each Region.
- **B.** One CloudFormation action that deploys to all three Regions at once.
- **C.** Three separate pipelines, created manually in each Region and started manually.
- **D.** An on-success condition on the `us-east-1` stage (or an entry condition on stage 2) that checks the error alarm over 30 minutes and fails or rolls back if it's in ALARM.
- **E.** A StackSet deployment with all Regions in parallel and 100% maximum concurrency.

### Q5 · Domain 2 · Task 2.1 · Single answer

A stack update fails with "CloudFormation cannot update a stack when a custom-named resource requires replacing". The template sets `TableName: orders` on a DynamoDB table, and the update changes the table's key schema.

What should the DevOps engineer do?

- **A.** Retry the update with termination protection disabled.
- **B.** Add `DependsOn` to the table.
- **C.** Set `DeletionPolicy: Retain` and update again.
- **D.** Remove the explicit name (or give the replacement a new name), so that CloudFormation can create the new table alongside the old one, and plan a data migration, because a key-schema change creates a new, empty table.

### Q6 · Domain 4 · Task 4.1 · Single answer

A service writes very verbose debug logs (2 TB per month) to CloudWatch Logs. Engineers query them with Logs Insights only a few times a month during investigations. No metric filters or subscriptions use these log groups. The team wants to cut ingestion costs significantly while keeping occasional querying.

What should the DevOps engineer do?

- **A.** Export the logs to S3 every hour.
- **B.** Create these log groups with the CloudWatch Logs Infrequent Access log class.
- **C.** Disable logging.
- **D.** Send the logs to an OpenSearch cluster.

### Q7 · Domain 5 · Task 5.1 · Single answer

A central operations account must receive selected events (CodePipeline failures, GuardDuty high-severity findings, AWS Health events) from 50 workload accounts on one event bus, to trigger centralized automation. New accounts must be able to send without editing the central bus's policy.

What should the DevOps engineer configure?

- **A.** A central event bus whose resource policy allows `events:PutEvents` from any principal in the organization (`aws:PrincipalOrgID`). In each workload account, EventBridge rules (deployed by StackSets) match the selected events and target the central bus.
- **B.** SNS topics in every account, with emails to the operations team.
- **C.** A Lambda function in the central account that polls every account's events.
- **D.** CloudTrail data events for EventBridge.

### Q8 · Domain 1 · Task 1.3 · Single answer

Security requires that only Lambda deployment packages built and approved by the CI pipeline can be deployed to production functions. Packages that have been tampered with, or that come from elsewhere, must be rejected at deployment time.

What should the DevOps engineer implement?

- **A.** S3 bucket versioning on the artifact bucket.
- **B.** An SCP that denies `lambda:UpdateFunctionCode`.
- **C.** AWS Signer signing profiles used by the pipeline to sign packages, and a Lambda code signing configuration on the production functions with the untrusted-artifact policy set to Enforce.
- **D.** Amazon Inspector Lambda scanning.

### Q9 · Domain 6 · Task 6.1 · Single answer

An SNS topic policy allows the `s3.amazonaws.com` service principal to publish to the topic, so that a specific bucket can send event notifications. Security points out that any S3 bucket in **any** AWS account could then publish to the topic.

How should the DevOps engineer fix the policy?

- **A.** Remove the policy and use an IAM user for S3.
- **B.** Encrypt the topic.
- **C.** Make the topic FIFO.
- **D.** Add conditions to the statement: `aws:SourceArn` equal to the bucket's ARN, and `aws:SourceAccount` equal to the bucket owner's account ID.

### Q10 · Domain 2 · Task 2.2 · Single answer

After a new SCP was attached at the root that denies every action outside `eu-west-1` (with a condition on `aws:RequestedRegion`), administrators can no longer manage IAM roles, view the billing console, or use AWS Support, even when working in `eu-west-1`.

What should the DevOps engineer change?

- **A.** Rewrite the SCP to use `NotAction` (or exceptions) for global services such as IAM, AWS Organizations, STS, Route 53, CloudFront, Support and billing, whose requests are evaluated against `us-east-1` or a global endpoint.
- **B.** Detach the SCP and use IAM policies instead.
- **C.** Add `eu-west-1` to the condition again.
- **D.** Grant administrators `AdministratorAccess`.

### Q11 · Domain 3 · Task 3.1 · Single answer

An application behind an ALB runs in three AZs. During a recent partial AZ impairment, instances in that AZ passed health checks but responded slowly, which degraded the whole application. The team wants to move traffic away from an impaired AZ quickly, and to let AWS do it automatically when it detects AZ issues.

What should the DevOps engineer use?

- **A.** Route 53 failover records per AZ.
- **B.** Deregister all targets manually during incidents.
- **C.** Amazon Route 53 Application Recovery Controller zonal shift for the ALB, with zonal autoshift enabled.
- **D.** A Lambda function that changes the ASG's subnets.

### Q12 · Domain 4 · Task 4.1 · Single answer

Centralized security logs from CloudWatch Logs in many accounts must feed three independent consumers in near real time: a SIEM integration, an S3 archive, and a Lambda-based alerting function. Each must be able to replay the last 24 hours after a failure.

What should the CloudWatch Logs destination in the central account be backed by?

- **A.** An Amazon Data Firehose stream delivering to S3.
- **B.** A Lambda function.
- **C.** An SQS queue.
- **D.** An Amazon Kinesis data stream (24-hour or longer retention), consumed independently by the three consumers.

### Q13 · Domain 1 · Task 1.2 · Single answer

An ECS service's application sometimes deadlocks: the process keeps running, but stops serving requests. The ALB eventually removes the task, but ECS doesn't replace it. The team wants ECS itself to detect the condition from an exit code and replace the task.

What should the DevOps engineer configure?

- **A.** A container health check in the task definition (for example `CMD-SHELL, curl -f http://localhost:8080/health || exit 1`) on the essential container, with suitable interval, retries and start period.
- **B.** A CloudWatch alarm on CPU.
- **C.** A larger task size.
- **D.** An X-Ray daemon sidecar.

### Q14 · Domain 5 · Task 5.2 · Single answer

Security discovered that someone shared a manual RDS snapshot publicly. It wants any future public sharing of RDS snapshots reverted within minutes, automatically, with a notification.

What should the DevOps engineer implement?

- **A.** A weekly script that lists snapshot attributes.
- **B.** An EventBridge rule on the CloudTrail event `ModifyDBSnapshotAttribute` (and the cluster equivalent) whose request adds `all` to the `restore` attribute. The rule invokes a Lambda function (or SSM Automation) that removes `all` and notifies the security team. The Config rule `rds-snapshots-public-prohibited` adds continuous detection.
- **C.** RDS encryption at rest.
- **D.** An SCP that denies `rds:CreateDBSnapshot`.

### Q15 · Domain 1 · Task 1.4 · Select TWO

An application's whole environment (ALB, Auto Scaling group, launch template) is defined in one CloudFormation template. The team wants blue/green releases with a gradual traffic shift (10% → 50% → 100%) and instant rollback, without modifying the running environment.

Which combination of steps meets these requirements? (Select TWO.)

- **A.** Update the existing stack in place with the new AMI.
- **B.** Deploy the new version as a separate "green" stack (its own ALB and Auto Scaling group) next to the "blue" stack.
- **C.** Delete the blue stack before creating green, to avoid naming conflicts.
- **D.** Change the blue ALB's DNS name.
- **E.** Use Route 53 weighted alias records for the two ALBs, with health evaluation, and shift the weights 10/50/100. Roll back by setting green's weight to 0.

### Q16 · Domain 6 · Task 6.2 · Single answer

An engineer replaced a KMS key's policy with a statement that grants only a now-deleted IAM role. The default statement that lets the account's IAM policies grant access was removed. Nobody can now use or manage the key, including administrators.

What is the path to regain control, and how should it be prevented in future?

- **A.** Contact AWS Support to regain access to the key. In future, keep the statement that enables IAM policies for the account (the root principal) or a dedicated key administrator, and don't bypass the policy lockout safety check.
- **B.** Delete the key and create a new one with the same ID.
- **C.** Attach `AdministratorAccess` to an IAM user and use the key.
- **D.** Use the AWS managed key instead and decrypt the existing data with it.

### Q17 · Domain 2 · Task 2.3 · Single answer

An EventBridge rule invokes a Lambda function that creates a ticket in an IT service management tool for every GuardDuty finding. Occasionally, duplicate tickets are created for the same finding event.

What should the DevOps engineer do?

- **A.** Set reserved concurrency to 1.
- **B.** Turn off the rule's retry policy.
- **C.** Make the function idempotent: use the event's unique ID (or the finding ID plus its updated-at time) as an idempotency key, with a DynamoDB conditional write (for example with the Powertools idempotency utility), so that duplicate deliveries create no new ticket.
- **D.** Switch the target to SNS.

### Q18 · Domain 3 · Task 3.2 · Single answer

An ECS service on Fargate processes jobs from an SQS queue. CPU stays low because the work is I/O-bound, so CPU-based scaling never adds tasks, and the backlog grows to hours during peaks.

How should the DevOps engineer configure scaling?

- **A.** Lower the CPU target to 10%.
- **B.** Increase the task size.
- **C.** Add a scheduled action at midnight.
- **D.** Use target tracking on a custom metric of backlog per task: metric math of `ApproximateNumberOfMessagesVisible` divided by the service's running task count, with a target derived from the acceptable latency.

### Q19 · Domain 4 · Task 4.2 · Single answer

During planned maintenance windows, a composite alarm that pages the on-call engineer fires because its child alarms react to the expected downtime. The team wants paging suppressed automatically during maintenance, while alarms still record their states.

What should the DevOps engineer configure?

- **A.** Delete the alarms before maintenance and recreate them afterwards.
- **B.** Set the child alarms' missing data treatment to `notBreaching`.
- **C.** Configure actions suppression on the composite alarm, with a "maintenance" suppressor alarm (for example driven by a metric that the maintenance automation sets), so the composite alarm's actions are suppressed while the suppressor is in ALARM.
- **D.** Change the SNS topic to email only.

### Q20 · Domain 1 · Task 1.3 · Single answer

The company publishes internal npm packages under `@corp/*` to an AWS CodeArtifact repository, which also has an upstream connection to the public npm registry. Security fears a dependency-confusion attack, in which someone publishes a higher-versioned `@corp/utils` to the public registry and builds pull it.

What should the DevOps engineer configure?

- **A.** Remove the external connection entirely.
- **B.** CodeArtifact package origin controls on the internal packages (for example allowing direct publishing, but blocking upstream ingestion for `@corp/*`), so that versions can't be pulled from the public registry for those names.
- **C.** Pin every dependency version in each project manually.
- **D.** Enable Amazon Inspector.

### Q21 · Domain 6 · Task 6.3 · Single answer

An authorized internal vulnerability scanner runs every night and causes GuardDuty `Recon:EC2/Portscan`-style findings on many instances. The security team wants these expected findings archived automatically so that they don't create alert noise, while still keeping a record.

What should the DevOps engineer configure?

- **A.** Disable GuardDuty at night.
- **B.** A GuardDuty suppression rule (filter) that automatically archives findings matching the scanner's source IP address and the finding type.
- **C.** Delete the findings every morning with a script.
- **D.** An SCP that denies GuardDuty.

### Q22 · Domain 5 · Task 5.3 · Single answer

A pipeline in `us-east-1` with a cross-Region deploy action to `eu-west-1` fails in the `eu-west-1` action with a KMS error. The engineer configured the `eu-west-1` artifact store with the ARN of the customer managed KMS key that encrypts the `us-east-1` artifact store.

What should the engineer do?

- **A.** Use the AWS managed key in both Regions.
- **B.** Disable encryption for the `eu-west-1` artifact store.
- **C.** Move the pipeline to `eu-west-1`.
- **D.** Configure the `eu-west-1` artifact store with a KMS key **in `eu-west-1`** (a key in that Region, or a multi-Region replica key), and grant the pipeline and action roles access to it.

### Q23 · Domain 2 · Task 2.1 · Single answer

An EC2 Image Builder pipeline publishes a new golden AMI ID to the Parameter Store parameter `/golden/al2023/latest` every week. Application CloudFormation stacks must use the latest golden AMI each time they're updated, without editing templates.

How should the templates reference the AMI?

- **A.** Hard-code the AMI ID and update it weekly.
- **B.** Use a template parameter of type `AWS::SSM::Parameter::Value<AWS::EC2::Image::Id>` with the default `/golden/al2023/latest`, so that CloudFormation resolves the current value on each stack update.
- **C.** Use `Fn::FindInMap` with a mapping updated by hand.
- **D.** Use a custom resource that calls `DescribeImages` with filters.

### Q24 · Domain 1 · Task 1.4 · Single answer

A team uses blue/green deployments for an application that shares one Amazon RDS database between blue and green. A release renames a column. During the last release, the blue environment broke as soon as green's migration ran.

How should the team handle schema changes?

- **A.** Run migrations only after deleting the blue environment.
- **B.** Use a separate database for each environment and copy the data at cut-over.
- **C.** Stop using blue/green deployments.
- **D.** Use backward-compatible "expand and contract" migrations: add the new column and write to both (expand), deploy, switch traffic, and only remove the old column in a later release (contract). That way blue and green both work against the same schema during the transition.

### Q25 · Domain 4 · Task 4.3 · Single answer

The team wants an alarm when the percentage of 5xx responses from an ALB exceeds 1% of requests over 5 minutes. Raw counts aren't useful, because traffic varies 50× between night and day.

What should the DevOps engineer configure?

- **A.** A CloudWatch alarm on a metric math expression such as `100 * (m1 / m2)`, where `m1` is `HTTPCode_Target_5XX_Count` (Sum) and `m2` is `RequestCount` (Sum), with a threshold of 1.
- **B.** An alarm on `HTTPCode_Target_5XX_Count` > 100.
- **C.** An anomaly detection alarm on `RequestCount`.
- **D.** A Logs Insights query every 5 minutes.

### Q26 · Domain 2 · Task 2.1 · Single answer

In a SAM template, a function that reads from one DynamoDB table has `Policies: AmazonDynamoDBFullAccess`. Security asks for least privilege with minimal template effort.

What should the DevOps engineer change?

- **A.** Remove all policies so the function has no permissions.
- **B.** Write a custom IAM role with inline JSON for every function.
- **C.** Use the SAM policy template `DynamoDBReadPolicy` with `TableName: !Ref OrdersTable`.
- **D.** Attach `ReadOnlyAccess`.

### Q27 · Domain 1 · Task 1.4 · Single answer

An Elastic Beanstalk environment falls behind on platform versions, and engineers forget to apply security patches to the platform. The company wants minor and patch platform updates applied automatically during a weekly maintenance window, without downtime.

What should the DevOps engineer configure?

- **A.** Enable managed platform updates for the environment, with a weekly maintenance window and the update level set to minor and patch. Beanstalk applies them using an immutable deployment.
- **B.** A monthly reminder to update the platform manually.
- **C.** A Systems Manager Patch Manager baseline for the Beanstalk instances.
- **D.** Recreate the environment every week.

### Q28 · Domain 6 · Task 6.2 · Single answer

A financial regulator requires trade records written to S3 to be retained unmodified for 7 years. No one, including the root user and administrators, may delete or overwrite them before then.

What should the DevOps engineer configure?

- **A.** An S3 Lifecycle rule that expires objects after 7 years.
- **B.** S3 Object Lock in compliance mode with a 7-year default retention period, on a bucket created with Object Lock enabled (versioning on).
- **C.** S3 Object Lock in governance mode.
- **D.** A bucket policy that denies `s3:DeleteObject`.

### Q29 · Domain 3 · Task 3.2 · Single answer

An Aurora MySQL cluster's reader endpoint serves reporting queries. Read traffic varies from 2 to 20 times the baseline during month-end, and the readers' CPU hits 95%. The team wants reader capacity to follow demand automatically.

What should the DevOps engineer configure?

- **A.** A larger writer instance.
- **B.** Manually added replicas each month.
- **C.** RDS Proxy.
- **D.** Aurora Auto Scaling for Aurora Replicas, with a target tracking policy on average reader CPU (or connections) and minimum and maximum replica counts.

### Q30 · Domain 4 · Task 4.2 · Single answer

A team wants to be told when its application's logs start showing unusual patterns (new error types, sudden changes in message frequency) without writing a metric filter for every possible error.

What should the DevOps engineer enable?

- **A.** A metric filter for the word `ERROR`.
- **B.** CloudTrail Insights.
- **C.** CloudWatch Logs anomaly detection on the log groups, alerting on detected anomalies.
- **D.** X-Ray Insights.

### Q31 · Domain 5 · Task 5.1 · Single answer

A consumer bug sent 40,000 messages to an SQS dead-letter queue over a weekend. The bug is now fixed and deployed. The messages must be reprocessed by the normal consumer, in the source queue.

What is the MOST operationally efficient approach?

- **A.** Use SQS dead-letter queue redrive (for example `StartMessageMoveTask`, or the console's "Start DLQ redrive") to move the messages back to the source queue.
- **B.** Write a script that receives each message and re-sends it.
- **C.** Point the consumer at the DLQ permanently.
- **D.** Delete the DLQ messages and ask producers to resend.

### Q32 · Domain 1 · Task 1.1 · Single answer

A single V2 pipeline deploys the same application to `dev`, `qa` or `perf` environments. The environment is chosen by whoever starts the pipeline. Today the team keeps three copies of the pipeline.

What should the DevOps engineer do?

- **A.** Keep three pipelines and synchronize them with a script.
- **B.** Use action output variables from the Source stage.
- **C.** Use a Lambda function that edits the pipeline before each run.
- **D.** Define a pipeline-level variable (for example `TARGET_ENV`, with a default), supply its value when starting an execution, and reference it in actions such as `#{variables.TARGET_ENV}`.

### Q33 · Domain 2 · Task 2.1 · Select TWO

A central IT account owns an AWS Service Catalog portfolio of approved products. All accounts in the `Workloads` OU, now and in future, must be able to launch these products, and every provisioned product must carry an `Environment` tag chosen from `dev`, `test` or `prod`.

Which combination of steps meets these requirements? (Select TWO.)

- **A.** Share the portfolio with the `Workloads` OU using AWS Organizations sharing, so that member accounts (including new ones) can import it, and grant principals access in each account.
- **B.** Copy each product into each account.
- **C.** Attach a TagOption for `Environment` with the values `dev`, `test` and `prod` to the portfolio (or products).
- **D.** Create IAM users in the central account for every developer.
- **E.** Share the CloudFormation templates through AWS RAM.

### Q34 · Domain 6 · Task 6.1 · Single answer

Engineers sign in through IAM Identity Center, federated with the company IdP. Access to project resources must follow each user's `project` attribute in the IdP, without a separate permission set per project.

What should the DevOps engineer configure?

- **A.** Enable attributes for access control in IAM Identity Center, mapping the IdP's `project` attribute to a session tag, and use one permission set whose policies compare `aws:PrincipalTag/project` with `aws:ResourceTag/project`.
- **B.** Create one permission set per project.
- **C.** Create IAM users per project in each account.
- **D.** Use SCPs per project.

### Q35 · Domain 3 · Task 3.2 · Single answer

A CloudFront distribution serves a global audience from a single origin (an ALB). Origin load keeps rising as traffic grows, because each edge location requests the same objects from the origin separately.

What should the DevOps engineer do to reduce origin load?

- **A.** Disable caching for static assets.
- **B.** Enable CloudFront Origin Shield in the Region closest to the origin, and tune cache policies (cache keys and TTLs) to improve the cache hit ratio.
- **C.** Add a second ALB in the same Region.
- **D.** Use a Global Accelerator in front of CloudFront.

### Q36 · Domain 1 · Task 1.2 · Single answer

Developers have accidentally committed AWS access keys and database passwords to repositories several times. The company wants any pull request containing a secret to be blocked before merge.

What should the DevOps engineer implement?

- **A.** A monthly scan of all repositories.
- **B.** Amazon Macie on the build artifact bucket.
- **C.** A pull request build (CodeBuild triggered on pull request events) that runs a secrets scanner (for example `git-secrets` or a similar tool) on the changes, fails on findings, and is required to pass before merge.
- **D.** Rotate all credentials weekly.

### Q37 · Domain 4 · Task 4.1 · Single answer

An ECS cluster runs 200 services. The team needs task- and container-level CPU, memory, network and storage metrics, plus automatic dashboards, to find noisy services, with no custom agents to maintain.

What should the DevOps engineer enable?

- **A.** EC2 detailed monitoring.
- **B.** X-Ray tracing.
- **C.** VPC Flow Logs.
- **D.** CloudWatch Container Insights (with enhanced observability) for the cluster.

### Q38 · Domain 5 · Task 5.2 · Single answer

Development environments (tagged `env=dev`) must stop every weekday at 20:00 and start at 07:00 local time, to save money. The team wants no servers and no custom scheduling code.

What should the DevOps engineer implement?

- **A.** A cron job on a management instance.
- **B.** Auto Scaling scheduled actions for standalone instances.
- **C.** EventBridge Scheduler schedules, with time zones, that start SSM Automation runbooks (for example `AWS-StopEC2Instance` and `AWS-StartEC2Instance`) targeting instances by the `env=dev` tag. Alternatively, Systems Manager Quick Setup Resource Scheduler.
- **D.** A Lambda function invoked every minute that checks the time.

### Q39 · Domain 2 · Task 2.2 · Single answer

The security team wants Amazon Detective enabled for all current and future accounts, so that analysts can investigate GuardDuty findings across the organization from the security account.

What should the DevOps engineer do?

- **A.** Enable Detective manually in each account.
- **B.** From the management account, designate the security account as the Detective delegated administrator, and enable automatic enrollment of organization accounts in the behaviour graph.
- **C.** Create a StackSet that enables Detective.
- **D.** Enable Detective in the management account only.

### Q40 · Domain 6 · Task 6.2 · Single answer

A company has 40 VPCs connected through AWS Transit Gateway. All traffic between VPCs and to the internet must be inspected centrally by stateful firewall rules (IPS signatures and domain filtering), managed in one place.

What should the DevOps engineer design?

- **A.** Security groups in each VPC.
- **B.** AWS WAF on every ALB.
- **C.** Network ACLs in each VPC.
- **D.** A centralized inspection VPC with AWS Network Firewall endpoints, attached to the Transit Gateway (with appliance mode enabled), and Transit Gateway route tables that send inter-VPC and egress traffic through the inspection VPC.

### Q41 · Domain 1 · Task 1.4 · Single answer

During CodeDeploy in-place deployments behind an ALB, instances are deregistered while long-running requests (up to 90 seconds) are still in flight, and users see errors. The application also needs to flush a local queue before it stops.

What should the DevOps engineer do?

- **A.** Use `CodeDeployDefault.AllAtOnce`.
- **B.** Set the target group's deregistration delay to at least 90 seconds, and add a `BeforeBlockTraffic` / `ApplicationStop` hook script that flushes the queue before shutting down.
- **C.** Disable the load balancer in the deployment group.
- **D.** Increase the instance size.

### Q42 · Domain 3 · Task 3.3 · Single answer

A company wants every production account's backups (EC2, EBS, RDS, DynamoDB) to follow a standard plan, and to be copied automatically to a vault in a separate central backup account. Accounts created in the future must be covered automatically.

What should the DevOps engineer implement?

- **A.** AWS Backup policies in AWS Organizations, attached to the production OU, that define the backup plan, tag-based selection, and a copy action to the central backup account's vault (with cross-account backup enabled in the organization).
- **B.** A backup plan created manually in each account.
- **C.** Daily snapshots by a Lambda function in each account.
- **D.** S3 replication of the backups.

### Q43 · Domain 4 · Task 4.2 · Single answer

An S3 bucket was deleted 5 months ago, and auditors want to know who deleted it. The organization trail delivers logs to S3. CloudTrail Event history only covers the last 90 days.

What is the FASTEST way to answer?

- **A.** Ask AWS Support.
- **B.** Query the CloudTrail logs in S3 with Amazon Athena (a CloudTrail table with partition projection), filtering on `eventName = 'DeleteBucket'` and the bucket name.
- **C.** Search CloudTrail Event history.
- **D.** Check AWS Config's resource timeline for the bucket, which will show the deleter's identity.

### Q44 · Domain 2 · Task 2.3 · Single answer

A company has a proprietary monitoring agent with different installers for Windows and Linux, and new versions every quarter. It needs to install the agent on 3,000 managed nodes, upgrade it in a controlled way, and keep it installed.

What should the DevOps engineer use?

- **A.** User data on all instances.
- **B.** Commit the installers to each AMI.
- **C.** Run Command with an inline script, run by hand each quarter.
- **D.** A Systems Manager Distributor custom package (versioned installers per platform), deployed and kept current with a State Manager association using `AWS-ConfigureAWSPackage`.

### Q45 · Domain 1 · Task 1.2 · Single answer

Performance regressions keep reaching production. The team wants the pipeline to run a 10-minute load test against staging after each deployment, and to fail the release if p95 latency is more than 10% worse than the stored baseline.

What should the DevOps engineer implement?

- **A.** A CodeBuild action in the staging stage that runs the load test, retrieves p95 from CloudWatch (or from the test tool), compares it with a baseline stored in Parameter Store, and exits non-zero if the regression exceeds 10%.
- **B.** A manual performance review before every release.
- **C.** Production canaries only.
- **D.** A CloudWatch dashboard comparing releases.

### Q46 · Domain 6 · Task 6.1 · Single answer

An application on EC2 connects to Amazon RDS for PostgreSQL with a password stored in a configuration file. Security wants no database passwords at all for this application, while access stays controlled by IAM.

What should the DevOps engineer implement?

- **A.** Store the password in Parameter Store as a String.
- **B.** Use the master user for the application.
- **C.** Enable IAM database authentication on the instance, create a database user mapped to IAM authentication, grant the instance role `rds-db:connect` for that user, and have the application generate short-lived authentication tokens (over TLS).
- **D.** Embed the password in the AMI.

### Q47 · Domain 5 · Task 5.3 · Single answer

An ECS task stops repeatedly during traffic peaks. The stopped reason shows the essential container exited with code 137. CloudWatch shows memory approaching the container's limit just before each stop.

What is the cause, and what's the fix?

- **A.** A failing health check; lengthen the health check interval.
- **B.** The container is killed for exceeding its memory limit (out of memory). Raise the container or task memory (or fix the leak), and alarm on memory utilization.
- **C.** The image is missing; push it again.
- **D.** The task role is missing permissions.

### Q48 · Domain 3 · Task 3.3 · Select TWO

When a website's application tier in one Region fails completely, users should be sent automatically to a static "we'll be back soon" page hosted in S3, rather than getting errors. The domain is hosted in Route 53.

Which combination of steps meets this requirement? (Select TWO.)

- **A.** A Lambda function that rewrites DNS records when errors are detected.
- **B.** A primary failover alias record pointing to the application's ALB, with Evaluate Target Health (or an attached health check).
- **C.** Weighted records with 50/50 weights between the ALB and S3.
- **D.** A secondary failover alias record pointing to a static S3 website bucket (or a CloudFront distribution in front of it) that serves the maintenance page.
- **E.** A 24-hour TTL on the records.

### Q49 · Domain 1 · Task 1.4 · Single answer

Lambda functions read feature settings from AWS AppConfig on every invocation, which adds latency and many API calls. The team wants configuration retrieved efficiently, cached locally, and refreshed automatically when new configurations are deployed.

What should the DevOps engineer use?

- **A.** Call `GetParameter` from Parameter Store on every invocation.
- **B.** Environment variables updated by redeploying the function.
- **C.** The AWS AppConfig Agent Lambda extension, which retrieves and caches configuration and serves it to the function from a local endpoint.
- **D.** An S3 object read on every invocation.

### Q50 · Domain 4 · Task 4.1 · Single answer

A trading system needs an alarm that evaluates a custom latency metric every 10 seconds, because 1-minute granularity is too coarse to catch short spikes.

What should the DevOps engineer do?

- **A.** Publish the metric as a high-resolution custom metric (`StorageResolution` of 1 second), and create a high-resolution alarm with a 10-second period.
- **B.** Enable detailed monitoring.
- **C.** Use a 1-minute standard metric with a 10-second alarm period.
- **D.** Use CloudWatch Logs Insights.

### Q51 · Domain 2 · Task 2.3 · Single answer

A remediation runbook (SSM Automation) must run in 120 accounts and 4 Regions. It must process at most 10 accounts at a time, stop if more than 5% of targets fail, and be launched and tracked from one central account.

What should the DevOps engineer use?

- **A.** A Lambda function in each account invoked by EventBridge.
- **B.** Systems Manager Automation multi-account and multi-Region execution from the delegated administrator (or management) account, with the target accounts or OUs and Regions, a maximum concurrency and an error threshold, and the execution role deployed to every account.
- **C.** Run Command from each account's console.
- **D.** An AWS Config conformance pack.

### Q52 · Domain 4 · Task 4.3 · Select TWO

An in-memory caching tier on an EC2 Auto Scaling group is limited by **memory**, not CPU. It should scale out when average memory utilization across the group exceeds 70%.

Which combination of steps meets this requirement? (Select TWO.)

- **A.** Install the CloudWatch agent (through Systems Manager) to publish `mem_used_percent` with the `AutoScalingGroupName` dimension aggregated (`append_dimensions` and `aggregation_dimensions`).
- **B.** Enable detailed monitoring for memory metrics.
- **C.** Create a target tracking scaling policy with a customized metric specification that uses the group-level `mem_used_percent` metric with a target of 70.
- **D.** Create scheduled scaling actions every hour.
- **E.** Scale on CPU utilization at 70%.

### Q53 · Domain 6 · Task 6.2 · Single answer

Workloads in private subnets reach S3 through a gateway endpoint. To prevent data exfiltration, security wants the endpoint to permit access **only to S3 buckets owned by accounts in the company's organization**, without listing every bucket.

What should the endpoint policy contain?

- **A.** An Allow statement for S3 actions on all resources, with a condition that `aws:ResourceOrgID` equals the organization ID.
- **B.** An Allow statement for `s3:*` on `*` with no condition.
- **C.** A Deny statement for `s3:GetObject`.
- **D.** An Allow statement with `aws:SourceIp` set to the VPC CIDR.

### Q54 · Domain 3 · Task 3.1 · Single answer

A session store runs on Amazon ElastiCache (Redis OSS) with a Global Datastore: the primary cluster is in `us-east-1` and the secondary in `us-west-2`. `us-east-1` has an extended outage, and the application must keep writing sessions in `us-west-2`.

What should the DevOps engineer do?

- **A.** Restore the cluster from yesterday's backup in `us-west-2`.
- **B.** Create a new Global Datastore.
- **C.** Point the application at the `us-east-1` endpoint again.
- **D.** Promote the secondary cluster in `us-west-2` to primary in the Global Datastore, and point the application's writes there.

### Q55 · Domain 5 · Task 5.1 · Single answer

Five independent applications consume the same Kinesis data stream. Each needs the full read throughput of every shard, and sub-200 ms propagation. With shared throughput, they compete and fall behind.

What should the DevOps engineer configure?

- **A.** Add shards until reads stop competing.
- **B.** Have each consumer poll less often.
- **C.** Register the five applications as enhanced fan-out consumers, so that each gets a dedicated 2 MB/s per shard pushed through `SubscribeToShard`.
- **D.** Copy the stream into five streams with Lambda.

### Q56 · Domain 1 · Task 1.1 · Single answer

A team defines its delivery pipeline with the AWS CDK. When developers add a new deployment stage or change the pipeline's structure in code, the change must take effect automatically on the next commit, with no one running `cdk deploy` for the pipeline by hand.

What should the DevOps engineer use?

- **A.** A CloudFormation pipeline template that is updated manually.
- **B.** CDK Pipelines (`pipelines.CodePipeline`), whose self-mutation stage updates the pipeline from the latest synthesized code before deploying the application stages.
- **C.** A Lambda function that compares pipeline definitions every hour.
- **D.** One pipeline per developer.

### Q57 · Domain 2 · Task 2.2 · Single answer

When projects end, the company closes their accounts. Before closure, and during the 90-day post-closure period, no resources in these accounts may be used, while the accounts remain in the organization for audit.

What should the DevOps engineer implement?

- **A.** Delete all IAM users in the account.
- **B.** Remove the account from the organization immediately.
- **C.** Move the account into a `Suspended` OU that has an SCP denying all actions (`"Effect": "Deny", "Action": "*"`) except a break-glass role, then close the account.
- **D.** Disable billing alerts.

### Q58 · Domain 6 · Task 6.3 · Single answer

Security Hub is enabled in 4 Regions in every account, through a delegated administrator. Analysts must see and act on findings from all Regions in one Region's console and API.

What should the DevOps engineer configure?

- **A.** Duplicate the Security Hub configuration in each Region.
- **B.** An EventBridge rule in every Region that emails findings.
- **C.** CloudTrail Lake.
- **D.** Security Hub cross-Region aggregation in the delegated administrator account, with one aggregation Region and the other Regions linked.

### Q59 · Domain 3 · Task 3.3 · Single answer

A regulated workload on DynamoDB must be restorable to any second in the last 35 days, and must also keep monthly backups for one year in a second Region.

What should the DevOps engineer configure?

- **A.** Enable point-in-time recovery on the table, and create an AWS Backup plan with a monthly rule (12-month retention) that copies recovery points to a vault in the second Region.
- **B.** Global tables only.
- **C.** DynamoDB Streams to S3.
- **D.** Manual exports to S3 every month.

### Q60 · Domain 5 · Task 5.2 · Single answer

Security Hub produces thousands of low-severity findings for a control that doesn't apply to sandbox accounts. Analysts want those findings suppressed automatically and consistently, while production accounts keep the same findings at their original severity.

What should the DevOps engineer configure?

- **A.** Disable the control everywhere.
- **B.** A Security Hub automation rule that matches the control ID and the sandbox account IDs, and sets the findings' workflow status to `SUPPRESSED`.
- **C.** A daily Lambda function that deletes the findings.
- **D.** GuardDuty suppression rules.

### Q61 · Domain 1 · Task 1.3 · Single answer

An EC2 Image Builder pipeline creates a new AMI every week. After a year there are hundreds of AMIs and snapshots, and the old ones are never used. Policy says: keep the latest 4 AMIs, deprecate older ones, and delete AMIs (and their snapshots) older than 90 days, unless they're tagged `retain=true`.

What should the DevOps engineer configure?

- **A.** A monthly manual cleanup.
- **B.** An S3 lifecycle rule on the snapshot bucket.
- **C.** EC2 Image Builder lifecycle policies that deprecate and delete AMIs and their snapshots by count or age, with tag-based exclusion rules.
- **D.** Amazon Data Lifecycle Manager EBS snapshot policies on the instances.

### Q62 · Domain 2 · Task 2.3 · Select TWO

Auditors want an organization-wide view of patch compliance for all managed instances, notifications when instances fall out of compliance, and the ability to report on it with SQL.

Which combination of steps meets these requirements? (Select TWO.)

- **A.** Collect screenshots of each account's Patch Manager dashboard.
- **B.** Rely on Amazon Inspector findings only.
- **C.** Deploy the AWS Config managed rule `ec2-managedinstance-patch-compliance-status-check` org-wide, with an organization aggregator and an EventBridge notification on compliance changes.
- **D.** Enable CloudTrail data events.
- **E.** Configure a Systems Manager Resource Data Sync from all accounts and Regions to a central S3 bucket (including patch compliance data), and query it with Athena (or view it in Systems Manager Explorer).

### Q63 · Domain 6 · Task 6.2 · Single answer

A company uses imported third-party TLS certificates in ACM on several ALBs. One expired last month and caused an outage. ACM can't renew imported certificates. The team wants an automatic warning well before expiry, for every imported certificate in every Region used.

What should the DevOps engineer implement?

- **A.** A calendar reminder.
- **B.** Replace the ALBs with CloudFront.
- **C.** Move the certificates to Secrets Manager.
- **D.** An EventBridge rule on the ACM `ACM Certificate Approaching Expiration` event, which ACM emits daily starting 45 days before expiry, targeting an SNS topic in each Region (with the expiry window configurable through the ACM account configuration), plus the Config rule `acm-certificate-expiration-check` for continuous compliance.

### Q64 · Domain 3 · Task 3.3 · Single answer

A company wants to verify that its multi-AZ application really tolerates the loss of an entire Availability Zone. That includes compute, database failover, and the loss of network connectivity to the AZ, in a controlled experiment with automatic stop conditions.

What should the DevOps engineer use?

- **A.** Terminate random instances by hand.
- **B.** The AWS Fault Injection Service AZ availability scenario (power interruption), from the scenario library, with stop conditions on CloudWatch alarms, run in a pre-production environment.
- **C.** Deleting a subnet.
- **D.** CloudWatch Synthetics.

### Q65 · Domain 4 · Task 4.3 · Single answer

The compliance team wants a notification in a Slack channel (through an SNS topic and Amazon Q Developer in chat applications / AWS Chatbot) every time any AWS Config rule in the account changes a resource's compliance to `NON_COMPLIANT`.

What should the DevOps engineer configure?

- **A.** A daily Config compliance report email.
- **B.** A CloudWatch alarm on `NumberOfNonCompliantRules` with a 1-day period.
- **C.** A Lambda function that polls Config every hour.
- **D.** An EventBridge rule matching `Config Rules Compliance Change` events with `newEvaluationResult.complianceType` of `NON_COMPLIANT`, targeting the SNS topic connected to the chat integration.

### Q66 · Domain 5 · Task 5.3 · Single answer

A batch Lambda function occasionally scales to 900 concurrent executions, using most of the account's 1,000-execution concurrency limit. At those times, the customer-facing API's Lambda functions are throttled.

What should the DevOps engineer do?

- **A.** Configure reserved concurrency for the customer-facing functions (guaranteeing their capacity), and cap the batch function with its own reserved concurrency (or the event source's maximum concurrency). Request a concurrency quota increase if needed.
- **B.** Increase the batch function's memory.
- **C.** Move the API to provisioned concurrency only.
- **D.** Delete the batch function's DLQ.

### Q67 · Domain 1 · Task 1.2 · Single answer

An integration test suite needs fixtures created (a DynamoDB table, seeded data and a test user), the tests run, a 2-minute wait for asynchronous processing, assertions, and guaranteed cleanup even if a step fails. The team wants this orchestrated inside CodePipeline with retries and visible step status.

What should the DevOps engineer use?

- **A.** A single CodeBuild action with a long shell script.
- **B.** A manual approval while engineers run the tests.
- **C.** A Lambda invoke action that does everything in one invocation.
- **D.** A Step Functions invoke action in the pipeline, with a state machine for setup, tests, wait and assertions, using Retry and Catch so that a cleanup state always runs.

### Q68 · Domain 2 · Task 2.1 · Single answer

Configuration for a payment service (timeouts, routing weights, limits) changes several times a week. A recent typo in a JSON value caused an outage. The team wants configuration changes validated before deployment, rolled out gradually, and rolled back automatically on alarms, without application deployments.

What should the DevOps engineer use?

- **A.** AWS AppConfig with a configuration profile that has JSON Schema and/or Lambda validators, a gradual deployment strategy with bake time, and CloudWatch alarm monitors on the environment.
- **B.** Parameter Store with manual review.
- **C.** Environment variables updated by redeploying.
- **D.** A configuration file in S3 read at startup.

### Q69 · Domain 6 · Task 6.3 · Single answer

IAM Access Analyzer (organization zone of trust) reports dozens of findings for buckets and roles that intentionally grant access to a trusted partner's AWS account. Analysts want only **unexpected** external access to show as active findings, now and in future.

What should the DevOps engineer configure?

- **A.** Delete the analyzer.
- **B.** Archive rules on the analyzer that automatically archive findings whose principal is the trusted partner's account ID (and the expected resource types).
- **C.** Remove the partner's access.
- **D.** An SCP that denies Access Analyzer.

### Q70 · Domain 3 · Task 3.1 · Single answer

A production application stores shared files on an EFS file system that was created with the One Zone storage class to save cost. The availability requirements now include surviving the loss of an Availability Zone.

What should the DevOps engineer do?

- **A.** Add mount targets in other AZs to the One Zone file system.
- **B.** Enable EFS lifecycle management.
- **C.** Migrate the data to an EFS file system with the Regional (multi-AZ) storage class, with mount targets in each AZ used, for example by using EFS replication or AWS DataSync, then cut over.
- **D.** Take daily AWS Backup copies of the One Zone file system.

### Q71 · Domain 5 · Task 5.3 · Select TWO

An API (API Gateway → Lambda → DynamoDB) intermittently shows p99 latency of 3 seconds. The team must find the root cause and fix it.

Which combination of steps should the DevOps engineer take? (Select TWO.)

- **A.** Use X-Ray traces and the service map to locate where the latency occurs. Here, the DynamoDB subsegments show retries after `ProvisionedThroughputExceededException`.
- **B.** Increase the Lambda function's memory to 10 GB.
- **C.** Add more API Gateway stages.
- **D.** Increase the Lambda timeout.
- **E.** Fix the throttling: enable DynamoDB auto scaling with appropriate targets (or switch to on-demand capacity), and review the key design for hot partitions.

### Q72 · Domain 1 · Task 1.4 · Single answer

An ECS service with 4 tasks behind an ALB has a deployment configuration of `minimumHealthyPercent: 0` and `maximumPercent: 100`. Every deployment causes a short full outage.

What should the DevOps engineer change?

- **A.** Set `minimumHealthyPercent` to 100 and `maximumPercent` to 200, so that new tasks start and become healthy before old ones stop (capacity permitting).
- **B.** Increase the task count to 8.
- **C.** Use the `AllAtOnce` CodeDeploy configuration.
- **D.** Increase the ALB idle timeout.

### Q73 · Domain 2 · Task 2.1 · Single answer

Engineers sometimes change resources that a StackSet manages, such as an IAM role in a few member accounts, directly in those accounts. The platform team wants to find which stack instances have drifted, and to restore the defined state.

What should the DevOps engineer do?

- **A.** Delete and recreate the StackSet.
- **B.** Compare the accounts by hand.
- **C.** Run drift detection on the StackSet to identify drifted stack instances and resources, then update the StackSet (re-applying the template to the drifted instances), and restrict direct changes with SCPs or IAM.
- **D.** Enable CloudTrail Insights.

### Q74 · Domain 4 · Task 4.2 · Single answer

Business stakeholders without AWS accounts need read-only access to a CloudWatch operational dashboard (order volume, error rates) through their corporate identity provider, without anyone creating IAM users for them.

What should the DevOps engineer do?

- **A.** Create IAM users with read-only access.
- **B.** Use CloudWatch dashboard sharing with SSO (through an Amazon Cognito user pool federated with the corporate IdP), so that specified users can view the dashboard without AWS accounts.
- **C.** Take screenshots every hour.
- **D.** Make the dashboard public on the internet.

### Q75 · Domain 6 · Task 6.3 · Select TWO

Security must be notified within minutes whenever any IAM policy is created, changed or attached, or any role's trust policy is modified, in any account.

Which combination of steps meets this requirement? (Select TWO.)

- **A.** Enable Amazon GuardDuty.
- **B.** Create EventBridge rules (in `us-east-1`, where IAM events are delivered) matching CloudTrail events with `eventSource` `iam.amazonaws.com` and event names such as `CreatePolicy`, `CreatePolicyVersion`, `PutRolePolicy`, `AttachRolePolicy` and `UpdateAssumeRolePolicy`, targeting SNS. Forward them to a central bus if needed.
- **C.** Enable Amazon Inspector.
- **D.** Make sure an organization CloudTrail trail is logging, including global service events, so that IAM API calls are recorded and delivered to EventBridge.
- **E.** Enable Amazon Macie.
