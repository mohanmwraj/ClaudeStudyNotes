# Mock Paper 1 · 75 Questions · 180 Minutes

**Instructions:**
* Set a timer for **180 minutes** and answer all 75 questions without notes.
* Write your answers on paper or in a text file (for example `1-C, 2-A, …`). For multiple-response questions, select exactly the number requested; there is no partial credit.
* Flag questions you're unsure about and come back to them. Never leave one blank.
* When finished, mark your answers with [07-mock-paper-1-answers.md](07-mock-paper-1-answers.md) and read the explanation for every question you missed **or guessed**.

**Composition** (matches the official DOP-C02 weighting): Domain 1: 17 · Domain 2: 13 · Domain 3: 11 · Domain 4: 11 · Domain 5: 10 · Domain 6: 13. The domain and task labels are shown to help your review. The real exam doesn't label questions.

**Scoring guide:** each question is worth 1 point. **60/75 (80%)** or better means you're ready; 53–59 means review your weak domains and retake; below 53 means study more before booking. AWS reports a scaled score, so these thresholds are a conservative readiness estimate, not a conversion.

---

### Q1 · Domain 1 · Task 1.1 · Single answer

A CodeBuild project was moved into a VPC so that its integration tests can reach a private Amazon RDS instance. Since then, every build fails in the `INSTALL` phase while downloading packages from the internet. The project uses two subnets whose route tables contain only the local route.

What should the DevOps engineer do?

- **A.** Move the project to public subnets that have a route to an internet gateway.
- **B.** Increase the build timeout to 60 minutes.
- **C.** Configure the project to use private subnets whose route tables send `0.0.0.0/0` to a NAT gateway in a public subnet.
- **D.** Remove the VPC configuration and open the RDS security group to the internet.

### Q2 · Domain 3 · Task 3.1 · Single answer

A serverless application uses Lambda functions that connect to an Aurora PostgreSQL cluster. During Aurora failovers, the application sees about a minute of connection errors. At peak, thousands of concurrent Lambda invocations also exhaust the database's connection limit.

Which change addresses both problems?

- **A.** Put Amazon RDS Proxy in front of the cluster and have the functions connect to the proxy endpoint.
- **B.** Increase the Aurora instance size.
- **C.** Add two more Aurora replicas.
- **D.** Set the functions' reserved concurrency to 10.

### Q3 · Domain 6 · Task 6.1 · Single answer

Backup scripts on 200 on-premises Linux servers upload files to S3 using access keys of an IAM user. Security wants these long-term credentials eliminated. The company already runs an internal certificate authority that issues X.509 certificates to every server.

What should the DevOps engineer implement?

- **A.** Rotate the IAM user's access keys every 7 days with a scheduled script.
- **B.** Store the access keys in AWS Secrets Manager and have each server retrieve them at runtime.
- **C.** Create one IAM user per server so that each key can be revoked individually.
- **D.** Configure IAM Roles Anywhere with the company CA as a trust anchor, create a profile mapping to a role with least-privilege S3 permissions, and use the credential helper on each server to obtain temporary credentials.

### Q4 · Domain 4 · Task 4.1 · Single answer

A Lambda function processes 5,000 requests per second. The team wants custom business metrics (order value and payment provider latency, with dimensions) in CloudWatch, without adding synchronous API calls or latency to each invocation.

What should the developers do?

- **A.** Call `PutMetricData` for each metric at the end of each invocation.
- **B.** Write the metrics as structured JSON log lines in CloudWatch Embedded Metric Format, so that CloudWatch Logs extracts them as metrics asynchronously.
- **C.** Write the metrics to a DynamoDB table and aggregate them every minute with another function.
- **D.** Enable Lambda Insights.

### Q5 · Domain 2 · Task 2.1 · Single answer

A network team's CloudFormation stack exports VPC and subnet IDs, and 40 application stacks import them with `Fn::ImportValue`. When the network team tried to replace a subnet, the stack update failed because the export is in use. The network team wants to change these values independently of the application teams.

What should the DevOps engineer recommend?

- **A.** Have the network stack write the values to SSM Parameter Store parameters, and have the application stacks read them through SSM parameter types or dynamic references.
- **B.** Combine all 41 stacks into one nested stack.
- **C.** Hard-code the subnet IDs in every application template.
- **D.** Delete the application stacks whenever the network changes.

### Q6 · Domain 1 · Task 1.4 · Single answer

A team uses CodeDeploy blue/green deployments for an EC2 Auto Scaling group behind an ALB. After a release, a problem often appears only 2–3 hours later. The team wants to be able to switch traffic back to the original instances instantly during the first 4 hours after a deployment.

How should the deployment group be configured?

- **A.** Use an in-place deployment with `CodeDeployDefault.OneAtATime`.
- **B.** Use the `HalfAtATime` deployment configuration so that half the instances keep the old version.
- **C.** Disable automatic rollback so that original instances are never touched.
- **D.** Configure the blue/green deployment to terminate the original instances 4 hours after a successful deployment (instead of immediately), so that they stay deregistered from the load balancer but available for rollback.

### Q7 · Domain 5 · Task 5.1 · Single answer

A bug in an EventBridge-triggered consumer silently discarded order events for 6 hours before it was fixed. The business wants the ability to re-send past events to the fixed consumer in future incidents, without asking producers to re-publish them.

What should the DevOps engineer configure?

- **A.** A dead-letter queue on the rule target.
- **B.** CloudTrail data events for EventBridge.
- **C.** An EventBridge archive for the event bus (filtered to order events, with a retention period), and use replay to re-deliver archived events after a fix.
- **D.** A second rule that duplicates every event to a Lambda function that logs it.

### Q8 · Domain 6 · Task 6.2 · Select TWO

A bucket stores payroll exports. Security requires that every object be encrypted with the company's customer managed KMS key, and that all access to the bucket use TLS.

Which combination of controls meets these requirements? (Select TWO.)

- **A.** Disable object ACLs and grant access with ACLs on each object.
- **B.** Add a bucket policy statement that denies all S3 actions when `aws:SecureTransport` is `false`.
- **C.** Rely on the S3 default SSE-S3 encryption that applies to all new objects.
- **D.** Enable Amazon Macie on the bucket.
- **E.** Configure default bucket encryption as SSE-KMS with the customer managed key (with S3 Bucket Keys), and deny `PutObject` requests that specify a different encryption type or key.

### Q9 · Domain 1 · Task 1.1 · Single answer

A V2 pipeline deploys database migrations, and every merged commit must be deployed, in commit order. When engineers merge several pull requests in quick succession, the default behaviour lets newer executions overtake waiting ones, and some migrations never run.

What should the DevOps engineer change?

- **A.** Add a manual approval to slow down executions.
- **B.** Set the pipeline's execution mode to `QUEUED`.
- **C.** Set the pipeline's execution mode to `PARALLEL`.
- **D.** Disable the transition between the Source and Deploy stages.

### Q10 · Domain 2 · Task 2.2 · Single answer

A company wants to make sure that no principal outside its AWS organization can ever access its S3 buckets or KMS keys, in any account, even if a developer writes a bucket policy or key policy that grants public or cross-organization access. It doesn't want to audit and edit thousands of resource policies.

What should the DevOps engineer implement?

- **A.** A Config rule that detects public buckets.
- **B.** An SCP that denies `s3:PutBucketPolicy`.
- **C.** A resource control policy (RCP), attached at the organization root, that denies access to S3 and KMS resources when the principal isn't from the organization (`aws:PrincipalOrgID`), with exceptions for required AWS service principals.
- **D.** IAM Access Analyzer with automatic archiving of findings.

### Q11 · Domain 3 · Task 3.1 · Single answer

A trading API runs in two Regions behind Network Load Balancers. Clients connect over TCP and cache DNS aggressively, which made a previous DNS-based Regional failover take more than 20 minutes. The business needs failover in seconds and fixed IP addresses that clients can allowlist.

What should the DevOps engineer implement?

- **A.** Route 53 latency-based routing with a TTL of 0.
- **B.** CloudFront in front of the NLBs.
- **C.** Two Elastic IP addresses that are moved between Regions with a script.
- **D.** AWS Global Accelerator with endpoint groups in both Regions, health checks on the NLBs, and the accelerator's static anycast IP addresses given to clients.

### Q12 · Domain 4 · Task 4.2 · Single answer

The security team wants to be alerted automatically when API activity in an account deviates sharply from its normal pattern. For example, a burst of `TerminateInstances` calls, or a spike in the rate of errored API calls. Nobody wants to define a threshold for every API.

What should the DevOps engineer enable?

- **A.** CloudTrail Insights events on the trail, with an EventBridge rule on Insights events that notifies the team.
- **B.** A CloudWatch alarm on the number of CloudTrail log files delivered.
- **C.** AWS Config recording for all resource types.
- **D.** Amazon Inspector.

### Q13 · Domain 1 · Task 1.4 · Select TWO

A team deploys Lambda functions with AWS SAM. New versions must receive traffic in equal 10% increments every minute until all traffic has moved. Before **any** traffic shifts, a smoke test must call the new version and stop the deployment if it fails. A CloudWatch alarm on errors must trigger automatic rollback.

Which combination of settings meets these requirements? (Select TWO.)

- **A.** `DeploymentPreference` with `Type: Linear10PercentEvery1Minute` and the error alarm in `Alarms`.
- **B.** `DeploymentPreference` with `Type: Canary10Percent5Minutes`.
- **C.** Provisioned concurrency on the alias.
- **D.** A `PreTraffic` hook function in `DeploymentPreference.Hooks` that tests the new version and reports `Succeeded` or `Failed` with `PutLifecycleEventHookExecutionStatus`.
- **E.** `DeploymentPreference` with `Type: AllAtOnce` and a manual check of the logs.

### Q14 · Domain 5 · Task 5.2 · Single answer

When the Auto Scaling group scales in, instances are terminated before their last application log files are shipped, and those logs are lost. The team wants each terminating instance to upload its remaining logs to S3 before it's terminated.

What should the DevOps engineer implement?

- **A.** A user data script that uploads logs at boot.
- **B.** A termination lifecycle hook, plus an EventBridge rule on the lifecycle action event that runs an SSM Run Command document on the instance to upload the logs and then calls `CompleteLifecycleAction` with `CONTINUE`.
- **C.** Scale-in protection on all instances.
- **D.** A longer deregistration delay on the target group.

### Q15 · Domain 2 · Task 2.1 · Single answer

Deleting a CloudFormation stack takes exactly one hour and then fails. The stack contains a Lambda-backed custom resource that empties an S3 bucket. The function's logs show that it handled the `Delete` request type by returning early, because the bucket was already empty, without doing anything else.

What is the problem, and how should it be fixed?

- **A.** The bucket needs `DeletionPolicy: Retain`.
- **B.** The function's timeout is too short; increase it to 15 minutes.
- **C.** The stack needs termination protection.
- **D.** The function never sent a response to the CloudFormation pre-signed URL for the `Delete` event, so CloudFormation waited until the custom resource timed out. The handler must always send SUCCESS or FAILED, for example in a `finally` block, for every request type.

### Q16 · Domain 6 · Task 6.1 · Single answer

GuardDuty reports that temporary credentials for an EC2 instance role are being used from an IP address outside AWS. The security team wants to immediately invalidate all credentials issued for that role so far, without breaking new sessions that the instance obtains afterwards.

What should the DevOps engineer do?

- **A.** Revoke the role's active sessions, which attaches an inline policy that denies all actions for credentials with an `aws:TokenIssueTime` earlier than now.
- **B.** Delete the role and recreate it with the same name.
- **C.** Detach every policy from the role permanently.
- **D.** Rotate the instance's SSH key pair.

### Q17 · Domain 1 · Task 1.3 · Single answer

A platform team hosts approved internal Python packages in an AWS CodeArtifact repository in a shared-services account. Build projects in 15 other accounts in the organization must be able to read packages from it, but not publish to it.

What should the DevOps engineer configure?

- **A.** Copy the repository into each account nightly.
- **B.** Make the repository public.
- **C.** A domain policy and a repository policy in the shared-services account that allow the organization's accounts to read (for example `codeartifact:ReadFromRepository` and the domain-level `GetAuthorizationToken`). The build roles in each account need the matching IAM permissions, including `sts:GetServiceBearerToken`.
- **D.** An IAM user in the shared-services account whose keys are distributed to the build projects.

### Q18 · Domain 3 · Task 3.2 · Select TWO

A batch-processing Auto Scaling group runs only `c5.2xlarge` Spot Instances in one AZ to reduce cost. Several times a week, Spot interruptions remove most of the capacity at once, and jobs miss their deadlines.

Which combination of changes improves availability while keeping Spot cost savings? (Select TWO.)

- **A.** Switch the whole group to On-Demand Instances.
- **B.** Increase the group's minimum size to 50.
- **C.** Use a mixed instances policy with several comparable instance types across multiple AZs, and the `price-capacity-optimized` Spot allocation strategy.
- **D.** Use a larger single instance type.
- **E.** Enable capacity rebalancing, so the group proactively launches replacements when a Spot Instance receives a rebalance recommendation.

### Q19 · Domain 4 · Task 4.1 · Single answer

A company has 25 workload accounts. The operations team wants to search logs, view metrics, see X-Ray traces and create alarms for all of them from one central account, without copying the data and without managing cross-account roles for each dashboard.

What should the DevOps engineer set up?

- **A.** A CloudWatch Logs subscription from every log group to the central account.
- **B.** One IAM user per workload account for the operations team.
- **C.** CloudWatch metric streams from every account to the central account.
- **D.** CloudWatch cross-account observability, with the central account as the monitoring account and the workload accounts linked as source accounts (deployed org-wide).

### Q20 · Domain 1 · Task 1.2 · Single answer

A Python library must be tested on Python 3.10, 3.11 and 3.12, and on both x86 and Arm. Today, six sequential builds take 40 minutes. The team wants all combinations to run in parallel from one buildspec, and to report a single overall result.

What should the DevOps engineer use?

- **A.** Six separate CodeBuild projects started by six pipeline actions.
- **B.** A CodeBuild batch build with a `build-matrix` that defines the Python versions and the compute environments.
- **C.** A single build that loops over the versions in the `build` phase.
- **D.** A Lambda function that starts six builds and polls them.

### Q21 · Domain 2 · Task 2.3 · Single answer

A company with 120 accounts and 6 Regions wants consistent operating-system patching: a scan every day and installation every Sunday, for all EC2 instances, including in accounts created later. It wants to configure this once, centrally.

What should the DevOps engineer use?

- **A.** A Systems Manager Quick Setup patch policy deployed to the organization (all target OUs and Regions), with scan and install schedules.
- **B.** A maintenance window and patch baseline created manually in each account and Region.
- **C.** A cron job on every instance.
- **D.** An EC2 Image Builder pipeline in each account.

### Q22 · Domain 6 · Task 6.3 · Single answer

A company runs Amazon EKS clusters and wants to detect runtime threats inside containers: for example, a container spawning a reverse shell, executing a newly downloaded binary, or running a crypto-miner process. It wants this without deploying and maintaining a third-party agent.

What should the DevOps engineer enable?

- **A.** Amazon Inspector container image scanning.
- **B.** VPC Flow Logs for the cluster subnets.
- **C.** Amazon GuardDuty Runtime Monitoring for EKS, with the GuardDuty-managed security agent (EKS add-on) deployed automatically.
- **D.** AWS Config rules for EKS.

### Q23 · Domain 5 · Task 5.3 · Single answer

After a refactoring, an API Gateway REST API with Lambda proxy integration returns HTTP 502 for every request. The Lambda function's logs show it completes successfully and returns a Python dictionary like `{"result": "ok"}`.

What is the MOST likely cause?

- **A.** The API Gateway stage cache is stale.
- **B.** The function's timeout is longer than 29 seconds.
- **C.** The API needs a usage plan.
- **D.** With proxy integration, the function must return a response object with `statusCode`, `headers` (optional) and a **string** `body`. Returning an arbitrary dictionary is a malformed proxy response, which API Gateway reports as a 502.

### Q24 · Domain 1 · Task 1.4 · Single answer

A team deploys an Amazon ECS service with the rolling update (`ECS`) deployment controller through CodePipeline's standard ECS action. A bad image recently produced tasks that crashed on start, and the service kept trying to launch them for an hour, leaving it under-capacity. The team wants such deployments to stop and revert automatically.

What should the DevOps engineer configure?

- **A.** A Lambda function that watches task events and calls `UpdateService` with the old task definition.
- **B.** A larger `maximumPercent`.
- **C.** The ECS deployment circuit breaker with rollback enabled on the service.
- **D.** A Route 53 health check on the service.

### Q25 · Domain 4 · Task 4.3 · Single answer

A nightly batch job publishes a custom metric `JobSucceeded = 1` when it finishes. When the job hangs or never starts, no data point is published, and the existing alarm (`JobSucceeded < 1`) stays in `INSUFFICIENT_DATA` instead of alerting.

How should the alarm be configured so that a missing run triggers a notification?

- **A.** Change the statistic to `Maximum`.
- **B.** Set the alarm's missing data treatment to `breaching`, with a period and evaluation window that cover the expected run time.
- **C.** Set the missing data treatment to `notBreaching`.
- **D.** Convert the metric to high resolution.

### Q26 · Domain 2 · Task 2.1 · Single answer

EC2 instances created by a CloudFormation stack are configured by `cfn-init` from `AWS::CloudFormation::Init` metadata. When the team updates a configuration file in the metadata and updates the stack, the update succeeds, but the running instances keep the old file. The team doesn't want the instances replaced for configuration changes.

What should the DevOps engineer do?

- **A.** Add a `DependsOn` attribute to the instances.
- **B.** Configure and run the `cfn-hup` daemon on the instances, with a hook that re-runs `cfn-init` when the resource metadata changes.
- **C.** Change the instance type with every configuration change to force a replacement.
- **D.** Enable drift detection on the stack.

### Q27 · Domain 1 · Task 1.1 · Single answer

A pipeline in `us-east-1` has a new CloudFormation deploy action configured for `eu-west-1`. The pipeline update fails with an error saying that there's no artifact store for the action's Region.

What should the DevOps engineer do?

- **A.** Create an S3 bucket in `eu-west-1` (with a KMS key in that Region if a customer managed key is used), and add it to the pipeline's `ArtifactStores` map for `eu-west-1`.
- **B.** Enable S3 Cross-Region Replication on the existing artifact bucket.
- **C.** Move the pipeline to `eu-west-1`.
- **D.** Use a Lambda invoke action that copies artifacts to `eu-west-1`.

### Q28 · Domain 6 · Task 6.2 · Select TWO

Security requires that every new EBS volume in an account is encrypted with the company's customer managed KMS key. After the key was applied, launches by Auto Scaling groups fail with a client error, while engineers can still launch instances manually.

Which combination of steps meets the requirement and fixes the launches? (Select TWO.)

- **A.** Enable EBS encryption by default in each Region used, and set the customer managed key as the default EBS encryption key.
- **B.** Switch the default key to the AWS managed `aws/ebs` key.
- **C.** Update the KMS key policy to allow the Auto Scaling service-linked role (`AWSServiceRoleForAutoScaling`) to use the key and to create grants for AWS resources.
- **D.** Disable encryption in the launch templates.
- **E.** Add `kms:*` to the EC2 instance profile's policy.

### Q29 · Domain 3 · Task 3.1 · Single answer

A Network Load Balancer spans two AZs. The target group has 2 healthy instances in AZ-a and 6 in AZ-b. The AZ-a instances run at 95% CPU while those in AZ-b sit at 30%. Clients resolve the NLB's DNS name and spread evenly across the two AZ IP addresses.

What should the DevOps engineer do to balance the load?

- **A.** Add a second NLB.
- **B.** Enable sticky sessions on the target group.
- **C.** Enable cross-zone load balancing for the NLB (or its target group) so that each NLB node distributes across targets in all AZs.
- **D.** Switch to round-robin DNS with Route 53 multivalue answers.

### Q30 · Domain 4 · Task 4.1 · Single answer

An application occasionally logs customers' email addresses and credit card numbers in debug messages, and those logs go to CloudWatch Logs. Compliance requires that such data be masked for everyone except a small group of auditors, and that occurrences be reported. The fix must not wait for application changes.

What should the DevOps engineer do?

- **A.** Delete the log groups every day.
- **B.** Encrypt the log groups with a customer managed KMS key.
- **C.** Export the logs to S3 and run Amazon Macie on them weekly.
- **D.** Apply a CloudWatch Logs data protection policy that uses managed data identifiers to mask the sensitive data, with audit findings sent to a destination. Grant only the auditors `logs:Unmask`.

### Q31 · Domain 5 · Task 5.1 · Single answer

Messages arrive on an SQS queue. Each message must be filtered (only `type = "order"`), enriched by calling an internal API through a Lambda function, and then used to start a Step Functions execution. Today a custom polling Lambda function does all of this, and the team wants less code to maintain.

What should the DevOps engineer use?

- **A.** An SNS topic subscribed to the queue.
- **B.** An Amazon EventBridge Pipe with the SQS queue as its source, an event filter on `type`, the Lambda function as the enrichment step, and the Step Functions state machine as its target.
- **C.** An EventBridge scheduled rule that runs every minute and reads the queue.
- **D.** A Kinesis Data Firehose delivery stream from the queue.

### Q32 · Domain 1 · Task 1.4 · Single answer

An Elastic Beanstalk environment serves a web application. The team wants each new version deployed to fresh instances, with 10% of client traffic sent to them for 30 minutes. If the new instances stay healthy, all traffic should move; if not, traffic should return automatically.

Which deployment policy should be configured?

- **A.** Traffic splitting, with a 10% traffic split and a 30-minute evaluation time.
- **B.** Rolling with additional batch.
- **C.** Immutable.
- **D.** All at once.

### Q33 · Domain 2 · Task 2.2 · Single answer

In an AWS Control Tower landing zone, an administrator moved an enrolled account from one OU to another using the AWS Organizations console. Control Tower now reports drift for the account, and the new OU's controls aren't being applied to it consistently.

What should the DevOps engineer do?

- **A.** Delete the account and create a new one.
- **B.** Remove all SCPs from the new OU.
- **C.** Disable Control Tower and manage the organization manually.
- **D.** Resolve the drift through Control Tower: update or re-enroll the account (or re-register the OU) so that Control Tower re-applies its baseline and controls. Make future OU moves through Control Tower's Account Factory.

### Q34 · Domain 6 · Task 6.2 · Single answer

A media company's public website on CloudFront and ALBs was hit by a large DDoS attack. The site scaled out, and the AWS bill spiked. The company wants 24/7 access to AWS DDoS experts during attacks, protection against scaling charges caused by DDoS, and automatic application-layer DDoS mitigation.

What should the DevOps engineer recommend?

- **A.** AWS Shield Standard, which is enabled by default.
- **B.** Amazon GuardDuty.
- **C.** AWS Shield Advanced on the CloudFront distributions and ALBs, with automatic application-layer DDoS mitigation through AWS WAF, and Shield Response Team access.
- **D.** Network ACLs that block the attacking IP addresses.

### Q35 · Domain 3 · Task 3.2 · Single answer

A SaaS reporting database on Aurora PostgreSQL is idle most of the day, but receives unpredictable spikes that need 10× the normal capacity for 10–30 minutes. The team now over-provisions a large instance all the time and wants capacity to follow load automatically, without reboots.

What should the DevOps engineer recommend?

- **A.** A scheduled Lambda function that modifies the instance class every hour.
- **B.** Aurora Serverless v2 instances with minimum and maximum ACU limits suited to the workload.
- **C.** Aurora read replicas with Auto Scaling for read traffic, while writes stay on the large writer.
- **D.** A Multi-AZ DB cluster.

### Q36 · Domain 1 · Task 1.3 · Single answer

A production incident happened because a developer pushed a different image under an existing tag (`api:2.4.1`) in Amazon ECR after it had been tested. Production then pulled the untested image. The team wants to guarantee that production always runs exactly the image that was tested.

What should the DevOps engineer do?

- **A.** Use the `latest` tag in production task definitions.
- **B.** Enable ECR basic scanning on push.
- **C.** Restrict who can push using an IAM policy, while keeping mutable tags.
- **D.** Enable tag immutability on the repository, and reference images by digest (`@sha256:...`) in deployment artifacts produced by the build.

### Q37 · Domain 4 · Task 4.1 · Select TWO

Application logs are delivered by Amazon Data Firehose to S3 as compressed JSON, under one flat prefix. Athena queries over a single day of logs scan the entire multi-terabyte dataset, which makes them slow and expensive.

Which combination of Firehose changes will reduce the data scanned? (Select TWO.)

- **A.** Change compression from GZIP to uncompressed.
- **B.** Enable dynamic partitioning in Firehose so that objects are written under keys such as `year=/month=/day=/` (and an account or application partition).
- **C.** Use S3 Select instead of Athena.
- **D.** Enable record format conversion in Firehose to Apache Parquet (using an AWS Glue table schema), so that Athena reads only the required columns.
- **E.** Increase the Firehose buffer size to the maximum.

### Q38 · Domain 5 · Task 5.2 · Single answer

The operations team wants a single place to triage operational issues from many sources: CloudWatch alarms, EC2 health events and Config non-compliance. Each issue should show related resources and recent changes, and offer one-click runbooks for remediation.

What should the DevOps engineer set up?

- **A.** AWS Systems Manager OpsCenter, with OpsItems created automatically from CloudWatch alarms and EventBridge rules, and the relevant Automation runbooks associated.
- **B.** A shared email inbox subscribed to all SNS topics.
- **C.** A spreadsheet maintained by the on-call engineer.
- **D.** CloudTrail Lake.

### Q39 · Domain 2 · Task 2.3 · Select TWO

A company wants to eliminate bastion hosts and SSH keys for 500 Linux instances, and still let engineers get interactive shells. Every session must be logged to an encrypted S3 bucket for audit, and access must be controlled by IAM per environment tag.

Which combination of steps meets these requirements? (Select TWO.)

- **A.** Use Systems Manager Session Manager, and configure session preferences to log session data to the S3 bucket (and optionally CloudWatch Logs) with KMS encryption.
- **B.** Keep the bastion hosts and install the CloudWatch agent on them.
- **C.** Use EC2 Instance Connect with public IP addresses on all instances.
- **D.** Store the SSH private keys in Secrets Manager.
- **E.** Grant `ssm:StartSession` through IAM policies conditioned on the instances' environment tag, and remove inbound port 22 from the security groups.

### Q40 · Domain 6 · Task 6.1 · Single answer

An automation script runs as role A and assumes role B in another account, which then assumes role C to perform a 4-hour data migration. Role C's maximum session duration is 12 hours, but the script's credentials expire after 1 hour every time.

What is the cause, and what should the engineer do?

- **A.** STS has a hard 1-hour limit for every session; split the migration into hourly chunks.
- **B.** Sessions obtained through role chaining (one assumed role assuming another) are limited to 1 hour. Assume role C directly from credentials that aren't themselves from an assumed role (or restructure the trust so no chaining is needed), and request a 4-hour duration.
- **C.** The trust policy of role C is missing `sts:TagSession`.
- **D.** Role C needs `AdministratorAccess`.

### Q41 · Domain 1 · Task 1.2 · Single answer

After each production deployment, the team watches a CloudWatch alarm on the checkout error rate for 15 minutes, and rolls back by hand if it fires. They want this check automated inside the V2 pipeline, so that the production stage rolls back if the alarm enters ALARM during that window.

What should the DevOps engineer configure?

- **A.** A manual approval action after the deploy action.
- **B.** A CloudWatch alarm action that sends an SNS email.
- **C.** An on-success condition on the production stage, with a CloudWatch alarm rule that monitors the error alarm for 15 minutes, and a result of rollback when the alarm is in ALARM.
- **D.** A CodeBuild action that sleeps for 15 minutes.

### Q42 · Domain 3 · Task 3.3 · Single answer

S3 Cross-Region Replication was configured on a bucket with 2 TB of existing objects. New objects replicate correctly, but none of the existing objects appear in the destination bucket. The DR plan requires all objects in the DR Region.

What should the DevOps engineer do?

- **A.** Run S3 Batch Replication for the existing objects that haven't been replicated.
- **B.** Re-upload all objects from a laptop.
- **C.** Disable and re-enable versioning on the source bucket.
- **D.** Enable S3 Transfer Acceleration.

### Q43 · Domain 4 · Task 4.2 · Single answer

An API's structured JSON access logs are in CloudWatch Logs. During incidents, engineers want to see in real time the top 10 client IP addresses and API keys generating 5xx responses, without writing queries each time.

What should the DevOps engineer configure?

- **A.** A metric filter per IP address.
- **B.** An X-Ray sampling rule.
- **C.** A CloudWatch Contributor Insights rule on the log group that keys on client IP and API key, filtered to 5xx status codes.
- **D.** An Athena table over the log group.

### Q44 · Domain 2 · Task 2.1 · Single answer

An Auto Scaling group is managed by CloudFormation. When its launch template changes, the team wants CloudFormation to create a **completely new** Auto Scaling group, wait for its instances to signal success, and only then delete the old group. If the signals fail, the old group must remain untouched.

Which configuration should the DevOps engineer use?

- **A.** `UpdatePolicy` with `AutoScalingRollingUpdate` and `MaxBatchSize: 1`.
- **B.** `UpdatePolicy` with `AutoScalingReplacingUpdate` (`WillReplace: true`), together with a `CreationPolicy` that requires resource signals.
- **C.** `UpdatePolicy` with `AutoScalingScheduledAction`.
- **D.** `DeletionPolicy: Retain` on the group.

### Q45 · Domain 1 · Task 1.4 · Single answer

A CodeBuild project deploys Helm charts to an Amazon EKS cluster. `kubectl` commands from the build fail with `error: You must be logged in to the server (Unauthorized)`, although the CodeBuild role has `eks:DescribeCluster` and successfully runs `aws eks update-kubeconfig`.

What should the DevOps engineer do?

- **A.** Attach `AdministratorAccess` to the CodeBuild role.
- **B.** Run the build in privileged mode.
- **C.** Make the cluster's API endpoint public.
- **D.** Create an EKS access entry for the CodeBuild role (or map it in the legacy `aws-auth` ConfigMap) with an access policy or Kubernetes RBAC permissions for the target namespaces.

### Q46 · Domain 6 · Task 6.2 · Single answer

A company wants AWS Security Hub (CSPM) enabled in all accounts and all Regions it uses, with the AWS Foundational Security Best Practices and CIS standards turned on, consistently, including for new accounts. Configuration should be managed from one place.

What should the DevOps engineer do?

- **A.** Enable Security Hub manually in each account and Region.
- **B.** Use a Config conformance pack to enable Security Hub.
- **C.** Create an SCP that requires Security Hub.
- **D.** Designate a delegated administrator for Security Hub and use central configuration, with configuration policies that enable the chosen standards for all accounts and Regions, and new accounts covered automatically.

### Q47 · Domain 5 · Task 5.3 · Single answer

Workers process SQS messages that take up to 2 minutes each. Customers report receiving duplicate confirmation emails, and logs show the same message processed by two workers. The queue's visibility timeout is 30 seconds.

What should the DevOps engineer do?

- **A.** Switch to long polling.
- **B.** Reduce the batch size to 1.
- **C.** Increase the visibility timeout above the maximum processing time (and make processing idempotent as a safeguard).
- **D.** Add a dead-letter queue.

### Q48 · Domain 3 · Task 3.3 · Single answer

A customer-facing order system needs an RPO of 5 minutes and an RTO of 15 minutes for a Regional disaster. Leadership accepts moderate standing costs, but rejects running a full duplicate of production.

Which DR strategy fits best?

- **A.** Backup and restore.
- **B.** Pilot light with compute launched from IaC during failover.
- **C.** Multi-site active/active.
- **D.** Warm standby: a scaled-down but running copy of the full stack in the DR Region, with continuous data replication, which is scaled up and receives traffic on failover.

### Q49 · Domain 1 · Task 1.1 · Single answer

A pipeline's Lambda invoke action runs a database schema check. The function's logs show it finishes in 3 seconds with no errors, yet the pipeline action stays "In progress" and eventually fails.

What is the cause?

- **A.** The function doesn't call `PutJobSuccessResult` (or `PutJobFailureResult`) with the job ID from the event, so CodePipeline never learns the result.
- **B.** The function's memory is too low.
- **C.** Lambda invoke actions only support Node.js runtimes.
- **D.** The pipeline's artifact bucket is in a different Region.

### Q50 · Domain 4 · Task 4.2 · Single answer

A platform team runs dozens of Amazon EKS clusters. Developers already know PromQL and Grafana dashboards. The team wants managed Prometheus-compatible metric storage, dashboards with single sign-on, and no Prometheus servers or Grafana instances to operate.

What should the DevOps engineer implement?

- **A.** Self-managed Prometheus and Grafana on EC2 in each cluster's VPC.
- **B.** Amazon Managed Service for Prometheus (with managed collectors or ADOT scraping the clusters), and Amazon Managed Grafana workspaces with IAM Identity Center authentication.
- **C.** CloudWatch Logs Insights.
- **D.** Amazon Quick Sight on Athena.

### Q51 · Domain 2 · Task 2.2 · Select TWO

Finance requires every new EC2 instance and RDS database in every account to carry a `CostCenter` tag whose value comes from an approved list. Resources without the tag must not be creatable, and tag values must be standardized organization-wide.

Which combination of controls meets these requirements? (Select TWO.)

- **A.** An AWS Config `required-tags` rule that emails the owners of non-compliant resources.
- **B.** An AWS Organizations tag policy that defines the `CostCenter` key and its allowed values (with enforcement for the relevant resource types).
- **C.** A nightly Lambda function that deletes untagged resources.
- **D.** An SCP that denies `ec2:RunInstances` and `rds:CreateDBInstance` when `aws:RequestTag/CostCenter` is null.
- **E.** IAM policies in each account that grant tagging permissions.

### Q52 · Domain 1 · Task 1.4 · Select TWO

A team runs an Elastic Beanstalk application with an Amazon RDS database that was created **inside** the Beanstalk environment. They want blue/green releases with instant rollback, and terminating the old environment must never delete the database.

Which combination of steps should the DevOps engineer take? (Select TWO.)

- **A.** Keep the database inside the environment and use the rolling deployment policy.
- **B.** Use the rolling deployment policy and redeploy the old version if there are problems.
- **C.** Decouple the database: run it outside the environment (for example, restore from a snapshot to a standalone instance) and pass its endpoint and credentials through configuration (environment properties or Secrets Manager).
- **D.** Delete the blue environment as soon as the green environment is deployed.
- **E.** For each release, clone the environment, deploy the new version to the clone, test it, and use Swap environment URLs. Keep the old environment until the release is proven.

### Q53 · Domain 5 · Task 5.1 · Single answer

AWS periodically schedules EC2 instance retirements because of degraded hardware. These events reach the company's accounts, but nobody reads the emails, and instances have been stopped at inconvenient times. The team wants an automatic, controlled response for EBS-backed instances.

What should the DevOps engineer implement?

- **A.** An EventBridge rule that matches AWS Health events for scheduled EC2 instance retirement, and starts a Systems Manager Automation (or creates an OpsItem with an attached runbook) that stops and starts the instance during the next maintenance window, moving it to healthy hardware.
- **B.** A weekly manual review of the AWS Health Dashboard.
- **C.** A CloudWatch alarm on CPU utilization.
- **D.** Instance scale-in protection.

### Q54 · Domain 6 · Task 6.1 · Single answer

Developers submit IAM policy changes through a CI/CD pipeline. Security wants the pipeline to block any policy change that grants new access compared with the currently approved policy, or that grants specific sensitive actions such as `s3:DeleteBucket` or `iam:PassRole` on `*`, before deployment.

What should the DevOps engineer add to the pipeline?

- **A.** `cfn-lint` with default rules.
- **B.** A manual review of every policy by the security team.
- **C.** IAM Access Analyzer custom policy checks (`CheckNoNewAccess` against the reference policy, and `CheckAccessNotGranted` for the sensitive actions), run in a CodeBuild step that fails the build on a failed check.
- **D.** Amazon Inspector Lambda code scanning.

### Q55 · Domain 3 · Task 3.2 · Single answer

An EKS platform uses Cluster Autoscaler with 15 managed node groups for different instance types. Pending pods often wait several minutes for nodes, nodes are poorly bin-packed, and the team spends a lot of time managing node groups.

What should the DevOps engineer recommend?

- **A.** Increase the node groups' minimum sizes.
- **B.** Replace the Horizontal Pod Autoscaler with the Vertical Pod Autoscaler.
- **C.** Move all workloads to one large instance type.
- **D.** Adopt Karpenter, which provisions right-sized nodes directly from pending pods' requirements and consolidates under-used nodes.

### Q56 · Domain 4 · Task 4.2 · Single answer

The security team already runs Athena queries over CloudTrail and ALB logs in S3. Executives want an interactive, shareable dashboard of the weekly trends (failed logins by country, top denied API calls), refreshed automatically.

What should the DevOps engineer build?

- **A.** An Amazon Quick Sight dashboard with Athena as the data source and scheduled dataset refreshes.
- **B.** A CloudWatch dashboard with metric widgets.
- **C.** An email of CSV query results from a scheduled Lambda function.
- **D.** Amazon Managed Grafana with a Prometheus data source.

### Q57 · Domain 2 · Task 2.2 · Single answer

A company uses AWS Control Tower and standardizes on Terraform. It wants account requests, account customizations and baselines to be defined as code in Git and applied through a pipeline (GitOps), not through the console.

What should the DevOps engineer implement?

- **A.** CloudFormation StackSets only.
- **B.** AWS Control Tower Account Factory for Terraform (AFT).
- **C.** Manual account creation in the Organizations console.
- **D.** AWS Service Catalog with self-managed products.

### Q58 · Domain 1 · Task 1.1 · Single answer

CodeBuild builds fail intermittently with `toomanyrequests: You have reached your pull rate limit` when pulling base images from Docker Hub. The security team also wants every third-party base image to be scanned before use, and available even if Docker Hub is down.

What should the DevOps engineer do?

- **A.** Retry failed builds automatically three times.
- **B.** Run builds in privileged mode.
- **C.** Create an ECR pull-through cache rule for Docker Hub (with Docker Hub credentials stored in Secrets Manager), enable scanning in the registry, and change the Dockerfiles to pull base images through the private ECR cache.
- **D.** Commit the base images to the source repository as tar files.

### Q59 · Domain 5 · Task 5.2 · Select TWO

An audit found unencrypted EBS volumes. The company wants new unencrypted volumes to be impossible in every account and Region it uses, and wants any remaining unencrypted volumes reported continuously.

Which combination of steps meets these requirements? (Select TWO.)

- **A.** Enable EBS encryption by default in every account and Region used (for example through Systems Manager Quick Setup, StackSets or an organization-wide policy).
- **B.** Write a Lambda function that encrypts existing volumes in place.
- **C.** Enable Amazon GuardDuty.
- **D.** Deploy the AWS Config managed rule `encrypted-volumes` organization-wide, with notifications through EventBridge.
- **E.** Enable Amazon Macie.

### Q60 · Domain 6 · Task 6.2 · Single answer

A data bucket must be accessible only through a specific S3 gateway endpoint in the analytics VPC. Workloads in that VPC must only be able to reach the company's own buckets through the endpoint, to prevent data exfiltration to other buckets.

What should the DevOps engineer configure?

- **A.** Security group rules that allow the S3 prefix list.
- **B.** A bucket policy that denies access unless `aws:SourceVpce` equals the endpoint ID, and an endpoint policy that allows access only to the company's buckets.
- **C.** A network ACL that blocks the internet.
- **D.** An IAM policy on every role that allows `s3:*`.

### Q61 · Domain 3 · Task 3.3 · Single answer

A bank runs active/passive across two Regions. Regulators want failover to be a deliberate, operator-controlled action that works even if the primary Region's AWS control plane is impaired, with safeguards that stop both Regions being turned off at once.

What should the DevOps engineer implement?

- **A.** A Lambda function in the primary Region that updates Route 53 records.
- **B.** Manual edits to DNS records in the Route 53 console during the incident.
- **C.** Amazon Route 53 Application Recovery Controller routing controls (with safety rules), wired to Route 53 health checks on the failover records, and toggled through the highly available data-plane endpoints.
- **D.** A CloudFront origin group.

### Q62 · Domain 2 · Task 2.3 · Single answer

A remediation must run in all 200 accounts of an organization: assume a role, delete unused IAM access keys, and record the results. Failures must be retried with backoff, no more than 20 accounts may be processed at once, and the whole run must be visible in one execution history.

What should the DevOps engineer build?

- **A.** One Lambda function that loops over all accounts sequentially.
- **B.** A cron job on an EC2 instance.
- **C.** 200 EventBridge scheduled rules.
- **D.** A Step Functions state machine that lists the accounts (Organizations `ListAccounts`) and uses a Map state with `MaxConcurrency` 20. Each iteration assumes the account's role and performs the cleanup, with Retry and Catch policies.

### Q63 · Domain 4 · Task 4.3 · Single answer

Policy requires every CloudWatch Logs log group in all accounts to have a retention of at least 90 days. Teams keep creating log groups with the default "never expire" setting, or with 7 days. Non-compliant log groups must be fixed automatically.

What should the DevOps engineer implement?

- **A.** A monthly email reminder to teams.
- **B.** An SCP that denies `logs:CreateLogGroup`.
- **C.** The AWS Config managed rule `cw-loggroup-retention-period-check` (minimum 90 days), deployed org-wide, with an automatic remediation that runs an Automation runbook calling `PutRetentionPolicy`.
- **D.** CloudTrail Insights.

### Q64 · Domain 1 · Task 1.2 · Select TWO

A team uses AWS CodeCommit. Pull requests into `main` must not be mergeable until an automated build and test of the PR's source commit has passed.

Which combination of steps meets this requirement? (Select TWO.)

- **A.** Add a CodeBuild test stage to the `main` branch pipeline.
- **B.** Create an approval rule template, associated with the repository, that requires one approval from the build-automation IAM role for pull requests targeting `main`.
- **C.** Run a nightly build of all branches.
- **D.** Create an SCP that denies `codecommit:GitPush`.
- **E.** Create an EventBridge rule on pull request created and updated events that starts a CodeBuild build of the source commit. On a successful build, a function approves the pull request as the automation role (`UpdatePullRequestApprovalState`).

### Q65 · Domain 6 · Task 6.3 · Single answer

To meet the CIS AWS Foundations Benchmark, the security team must be alerted on console sign-ins without MFA, on unauthorized API calls, and on changes to CloudTrail configuration. CloudTrail is already logging to S3.

What should the DevOps engineer implement?

- **A.** Configure the trail to also send events to a CloudWatch Logs log group, create metric filters for each pattern (for example `$.errorCode = "*UnauthorizedOperation"`), and alarms on the metrics that notify an SNS topic.
- **B.** Enable Amazon Inspector.
- **C.** Run weekly Athena queries over the S3 logs.
- **D.** Enable S3 server access logging on the trail bucket.

### Q66 · Domain 5 · Task 5.3 · Single answer

An Elastic Beanstalk deployment fails with "Instance deployment failed. ... Command failed on instance" right after the team added an `.ebextensions` configuration file that installs a package and runs a command. The environment rolls back.

What should the DevOps engineer do first to find the root cause?

- **A.** Recreate the environment.
- **B.** Switch the deployment policy to immutable.
- **C.** Increase the instance size.
- **D.** Review the environment events, then request the full instance logs (for example `eb-engine.log` and `cfn-init-cmd.log`) to see which `.ebextensions` command failed, and why.

### Q67 · Domain 3 · Task 3.1 · Single answer

A web application behind an ALB stores user sessions in the memory of each EC2 instance and uses sticky sessions. When the Auto Scaling group scales in or replaces an instance, its users are logged out. The business wants instance loss to be invisible to users.

What should the DevOps engineer do?

- **A.** Increase the stickiness duration to 7 days.
- **B.** Store sessions in an external, highly available store such as Amazon ElastiCache (Redis OSS or Valkey) with Multi-AZ, or DynamoDB, so that any instance can serve any user.
- **C.** Disable scale-in.
- **D.** Use larger instances so that fewer are needed.

### Q68 · Domain 2 · Task 2.1 · Single answer

The platform team works from a dedicated platform account and must create and manage service-managed StackSets that target OUs across the organization. Security forbids daily work in the management account.

What should the DevOps engineer do?

- **A.** Register the platform account as a delegated administrator for CloudFormation StackSets from the management account, and create the stack sets with `--call-as DELEGATED_ADMIN`.
- **B.** Share the management account's root credentials with the platform team.
- **C.** Use self-managed StackSets from the management account.
- **D.** Create IAM users for the platform team in the management account.

### Q69 · Domain 6 · Task 6.3 · Single answer

An auditor asks for a list, within the hour, of all unencrypted EBS volumes across 80 accounts and 4 Regions, with account ID and volume ID. AWS Config is recording in all accounts.

What is the FASTEST way to produce the list?

- **A.** Log in to each account and Region and use the EC2 console filter.
- **B.** Write a script that assumes a role in every account and calls `DescribeVolumes` in every Region.
- **C.** Enable Amazon Macie.
- **D.** Run an AWS Config advanced query (SQL) against an organization-wide aggregator, filtering `resourceType = 'AWS::EC2::Volume'` and `configuration.encrypted = false`.

### Q70 · Domain 5 · Task 5.3 · Single answer

A pod in Amazon EKS uses IAM roles for service accounts (IRSA). The pod's AWS SDK calls fail with `AccessDenied` from `AssumeRoleWithWebIdentity`, although the role's permissions policy is correct. The service account is `payments-sa` in namespace `payments`, and the role's trust policy has a condition on `oidc...:sub` equal to `system:serviceaccount:default:payments-sa`.

What should the DevOps engineer fix?

- **A.** Attach the policy to the node instance role instead.
- **B.** Correct the trust policy condition to `system:serviceaccount:payments:payments-sa`, and confirm that the service account is annotated with the role ARN and that the cluster's OIDC provider exists in IAM.
- **C.** Add `AdministratorAccess` to the role.
- **D.** Recreate the cluster.

### Q71 · Domain 4 · Task 4.3 · Single answer

A DynamoDB table in provisioned capacity mode throttles every morning as traffic ramps up, and sits mostly idle at night. The team wants capacity to follow traffic automatically, while keeping provisioned-mode pricing for the predictable base load.

What should the DevOps engineer configure?

- **A.** A Lambda function that updates the capacity every hour.
- **B.** A DAX cluster.
- **C.** Global tables.
- **D.** DynamoDB auto scaling with target tracking (for example 70% utilization) and suitable minimum and maximum capacity for reads and writes.

### Q72 · Domain 6 · Task 6.3 · Single answer

A company wants continuous vulnerability scanning of all EC2 instances across its organization (OS and application packages), with no scanner agents beyond what's already installed (the SSM Agent), and all findings centralized with its other security findings.

What should the DevOps engineer enable?

- **A.** Amazon GuardDuty Malware Protection.
- **B.** AWS Config rules for EC2.
- **C.** Amazon Inspector for the organization through a delegated administrator, with EC2 scanning enabled (using the SSM Agent, or agentless scanning), and the findings integrated into AWS Security Hub.
- **D.** Amazon Macie.

### Q73 · Domain 3 · Task 3.3 · Single answer

An architecture review board wants each critical application assessed against its target RTO and RPO for AZ, Region and application failures, with recommendations, and wants to catch resilience regressions whenever the application's CloudFormation stacks change.

What should the DevOps engineer use?

- **A.** AWS Resilience Hub, with a resiliency policy per application and assessments run on each release (for example from the pipeline).
- **B.** AWS Trusted Advisor.
- **C.** AWS Config conformance packs.
- **D.** CloudWatch dashboards.

### Q74 · Domain 2 · Task 2.3 · Single answer

The compliance team maintains a set of 40 AWS Config rules with remediation actions that represent the company's baseline. It must be deployed and kept identical in all current and future member accounts, managed from the security account.

What should the DevOps engineer use?

- **A.** A Config aggregator in the security account.
- **B.** Manual deployment in each account.
- **C.** Systems Manager State Manager.
- **D.** An organization conformance pack deployed from the Config delegated administrator (security) account.

### Q75 · Domain 1 · Task 1.3 · Single answer

A pipeline's artifact bucket has versioning enabled. Storage costs have grown steadily because every build overwrites objects, which leaves noncurrent versions forever. Artifacts older than 30 days are never needed.

What should the DevOps engineer do?

- **A.** Disable versioning on the bucket.
- **B.** Add an S3 lifecycle rule that expires noncurrent versions 30 days after they become noncurrent (and cleans up expired delete markers and incomplete multipart uploads).
- **C.** Delete the bucket and create a new one every month.
- **D.** Move the bucket to S3 One Zone-IA.
