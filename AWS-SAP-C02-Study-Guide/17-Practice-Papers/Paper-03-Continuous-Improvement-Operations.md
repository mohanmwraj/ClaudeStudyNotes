# Practice Paper 3 — Continuous Improvement, Operations & Security Hardening
> Original SAP-C02-style questions (not real exam questions). 20 questions · suggested time 48 min (≈2.4 min/question, exam pace).
> Domain mix: D1 ×5, D2 ×6, D3 ×5, D4 ×4
> [← Practice papers index](README.md) · [Study guide index](../00-README-Start-Here.md)

**How to use this paper:** Set a 48-minute timer and answer all 20 questions in Section 1 without looking anything up. Mark any question you guessed. Then check the **Answer key** (Section 2) and read the **Detailed solutions** (Section 3) for every question, including the ones you got right. On the real exam, a lucky guess and a confident answer score the same, but only one of them will hold up next time.

**Theme:** This paper covers what happens *after* go-live: removing operational noise, tracing latency, patching and remediating at organization scale, closing security gaps, and cutting cost and latency from workloads that are already running or newly migrated. Most stems describe a problem with an existing system, so your job is to choose the **smallest managed change that fixes the root cause**.

---

## Section 1 — Questions

### Question 1
A logistics company is launching a new shipment-tracking API. Amazon API Gateway invokes AWS Lambda functions written in Python that query an Amazon Aurora PostgreSQL provisioned cluster (one writer and two readers, db.r6g.xlarge). The database credentials are already stored in AWS Secrets Manager. During pre-launch load testing at 2,500 concurrent Lambda executions, the database starts rejecting connections with "remaining connection slots are reserved" errors, and writer CPU spikes as thousands of short-lived connections are opened and closed every second. Launch is in three weeks. The team wants to keep the synchronous API contract, avoid rewriting the data-access layer, keep recovery fast during an Aurora failover, and avoid storing database passwords in Lambda environment variables.

Which solution meets these requirements?

- A. Raise the `max_connections` parameter in a custom DB cluster parameter group to 5,000, scale the writer to db.r6g.4xlarge, and set reserved concurrency on each function to 2,500 so that connection demand is predictable.
- B. Rewrite the functions to call the RDS Data API instead of using a PostgreSQL driver, and enable the Data API on the cluster so that the HTTP endpoint handles connection management.
- C. Create an Amazon RDS Proxy for the cluster that uses the existing Secrets Manager secret, enable IAM authentication between the functions and the proxy, point the functions at the proxy endpoints, and open the database connection outside the handler so that it is reused across invocations.
- D. Place an Amazon SQS queue between API Gateway and Lambda, and configure the event source mapping with a maximum concurrency of 50 so that the number of simultaneous database connections stays below the instance limit.

### Question 2
An online retailer runs 22 microservices on Amazon ECS behind Application Load Balancers. Each service team created Amazon CloudWatch alarms on CPU, memory, ALB 5XX count and p99 latency, and every alarm pages the on-call engineer through Amazon SNS. The on-call engineer receives about 400 pages per week, most of which resolve on their own, and during deployments dozens of alarms fire at once. Even so, last month a broken checkout flow went unnoticed for 50 minutes during a low-traffic night because no single metric breached its threshold. Leadership wants fewer and more meaningful pages, proactive detection of broken customer journeys even when traffic is low, and no paging during approved deployment windows, all with minimal custom code.

Which combination of steps should a solutions architect take? **(Select TWO.)**

- A. Create Amazon CloudWatch Synthetics canaries that script the sign-in, search, add-to-cart and checkout journey every 5 minutes, and create an alarm on each canary's `SuccessPercent` metric.
- B. Enable CloudWatch anomaly detection on every existing metric alarm so that thresholds adapt automatically, and keep each alarm's SNS paging action.
- C. Change every alarm's evaluation settings to 15 out of 15 datapoints so that only sustained breaches page the on-call engineer.
- D. Remove the paging actions from the individual metric alarms, create composite alarms with rule expressions such as `ALARM(checkout-canary) OR (ALARM(svc-5xx) AND ALARM(svc-latency))`, page only from the composite alarms, and configure a deployment-window alarm as the composite alarms' actions suppressor.
- E. Route all alarm state changes to Amazon EventBridge, and write an AWS Lambda function that deduplicates notifications within a 30-minute window before forwarding them to the paging system.

### Question 3
A media company broke a monolith into 14 microservices running on Amazon ECS on AWS Fargate and on AWS Lambda. After a recent release, the p99 latency of the "publish article" request rose from 350 ms to 2.4 seconds. No service logs show errors, and Container Insights shows normal CPU and memory. The team needs to find which downstream call (service-to-service, Amazon DynamoDB, Amazon S3 or a third-party API) is responsible, and wants the same visibility for future releases. The platform team requires vendor-neutral instrumentation with long-term support, because the AWS X-Ray SDKs and daemon are in maintenance mode.

Which approach should a solutions architect recommend?

- A. Enable VPC Flow Logs on the task subnets, query them with Amazon Athena to calculate the time between request and response packets for each service pair, and build a latency dashboard in Amazon QuickSight.
- B. Enable Lambda Insights on every function and Container Insights with enhanced observability on the ECS cluster, and create alarms on task-level network and resource metrics for every service.
- C. Add timestamped log statements before and after every outbound call in each service, include a shared request ID, and use CloudWatch Logs Insights queries to join the entries across log groups.
- D. Instrument the services with AWS Distro for OpenTelemetry (ADOT) auto-instrumentation, run the CloudWatch agent or the ADOT Collector as a sidecar in each Fargate task to export traces to AWS X-Ray, add the ADOT Lambda layer to the functions, and analyze the trace map and per-segment timings.

### Question 4
A financial services company has 180 AWS accounts in AWS Organizations across four AWS Regions. Its Amazon EC2 instances run Windows Server and Amazon Linux 2023. Auditors require that (1) every instance is scanned daily for missing patches, (2) Critical and Security patches are installed within 14 days of release, (3) installation happens only in a weekly window starting Sunday at 02:00 UTC, and (4) patch compliance is visible centrally. An internal review found that many instances launched by application teams have no instance profile, or have one without AWS Systems Manager permissions, so they do not appear as managed nodes. The cloud team wants the least operational overhead.

Which combination of actions will meet these requirements? **(Select TWO.)**

- A. From the Systems Manager delegated administrator account, create a Quick Setup patch policy that targets the entire organization, so that the management account is not used for day-to-day operations.
- B. From the organization's management account, create a Quick Setup Patch Manager patch policy that targets the entire organization and the four Regions, with **Scan and install**, a daily scan schedule, a custom CRON install schedule for Sunday 02:00 UTC, rate controls, and custom patch baselines that auto-approve Critical and Security updates 7 days after release.
- C. Use CloudFormation StackSets to create a maintenance window, a patch baseline and an `AWS-RunPatchBaseline` Run Command task in every account and Region, and use an AWS Config aggregator to view patch compliance.
- D. Activate Amazon Inspector across the organization and turn on its automatic remediation so that missing operating system patches are installed when vulnerabilities are detected.
- E. Use Quick Setup to enable Default Host Management Configuration across the organization, and select the patch policy option that adds the required IAM policies to existing instance profiles, so that all instances become managed nodes.

### Question 5
A company has 60 AWS accounts in AWS Organizations. AWS Config is enabled in every account and Region, with an aggregator in a security account that is also the AWS Config delegated administrator. Security reviews found that developers sometimes turn off S3 Block Public Access settings on individual buckets. Two buckets that host public product images are approved exceptions and must stay public until a CloudFront migration finishes next year. The security team requires that any other bucket that becomes public is fixed automatically within minutes, that compliance history is kept for auditors, and that the solution needs the least ongoing operational effort.

What should a solutions architect do?

- A. Enable S3 Block Public Access at the account level in every account by using a CloudFormation StackSet, and add an SCP that denies `s3:PutAccountPublicAccessBlock`.
- B. From the delegated administrator account, deploy an organization conformance pack that contains the `s3-bucket-level-public-access-prohibited` managed rule, with the two approved buckets in its `excludedPublicBuckets` parameter, and an automatic remediation action that runs the `AWSConfigRemediation-ConfigureS3BucketPublicAccessBlock` Automation runbook through an assume role in each account.
- C. Create an Amazon EventBridge rule in each account that matches the `DeleteBucketPublicAccessBlock` and `PutBucketPublicAccessBlock` CloudTrail events and invokes an AWS Lambda function that re-applies Block Public Access to the bucket.
- D. Enable Amazon Macie in all accounts through the delegated administrator, and send findings about publicly accessible buckets to an SNS topic that tells bucket owners to correct the configuration.

### Question 6
A company runs 90 accounts in AWS Organizations, with workloads in five Regions. AWS Security Hub CSPM and Amazon GuardDuty are enabled across the organization, with a security tooling account as the delegated administrator for both. SOC analysts currently sign in to each Region separately to review findings. The CISO wants one place to review findings from all Regions. The CISO also wants any CRITICAL-severity finding about a possibly compromised EC2 instance to start an automated response within minutes that moves the instance into a quarantine security group and snapshots its volumes. The solution must minimize the infrastructure deployed in member accounts and Regions.

Which combination of steps should the architect take? **(Select TWO.)**

- A. Create an AWS Config aggregator in the security tooling account to collect Security Hub findings from all accounts and Regions, and build the response from AWS Config rule evaluations.
- B. Create Security Hub custom actions in every member account so that workload owners can send selected findings to their own EventBridge event buses for response.
- C. In the security tooling account, configure Security Hub cross-Region aggregation with a home (aggregation) Region, and link the other four Regions.
- D. In the home Region of the security tooling account, create an EventBridge rule that matches `Security Hub Findings - Imported` events with CRITICAL severity and an `AwsEc2Instance` resource type, and target an AWS Step Functions workflow that assumes a cross-account role in the affected account and Region to quarantine and snapshot the instance.
- E. In every member account and Region, create EventBridge rules that forward GuardDuty findings to a central event bus in the security account, and process them with a Lambda function deployed in each Region.

### Question 7
A company has 250 accounts in AWS Organizations and creates 5–10 new accounts every week through AWS Control Tower Account Factory. Workloads run in six Regions. Some teams enabled Amazon GuardDuty in their own accounts, but nobody reviews those findings. The security team must make sure that GuardDuty, including S3 Protection and EKS/Runtime Monitoring, is enabled for every existing and future account in all six Regions, that findings are managed centrally in the security tooling account, and that member accounts cannot disable GuardDuty or disassociate from the administrator.

Which approach meets these requirements with the LEAST operational overhead?

- A. From the management account, designate the security tooling account as the GuardDuty delegated administrator in each of the six Regions. In the delegated administrator account, set the organization auto-enable preference to all accounts (`ALL`) for GuardDuty and for the required protection plans in each Region.
- B. From the management account, designate the security tooling account as the GuardDuty delegated administrator in us-east-1 only, because the designation applies to all Regions, and set the auto-enable preference to new accounts (`NEW`).
- C. Designate the organization's management account as the GuardDuty delegated administrator in each Region, and set the auto-enable preference to `NEW` so that new accounts are covered while existing detectors stay under team control.
- D. Use a CloudFormation StackSet to create a GuardDuty detector in every account and Region, and have each member account accept an invitation from the security tooling account to become a GuardDuty member account.

### Question 8
A company is building a new container platform. AWS CodePipeline builds container images with AWS CodeBuild, pushes them to Amazon ECR and deploys them to Amazon EKS clusters. A separate fleet of Amazon EC2 instances runs legacy batch agents. The security requirements are: images with CRITICAL vulnerabilities must never be pushed to ECR; images already in ECR and the EC2 fleet must be re-evaluated automatically whenever a new CVE is published, without scheduled rescans; findings must be centralized across the organization's accounts; and no third-party scanners may be used.

Which solution meets these requirements with the LEAST operational overhead?

- A. Enable ECR basic scanning with scan on push, use an EventBridge schedule to call `StartImageScan` nightly for every image, and run Systems Manager Patch Manager scans on the EC2 fleet daily.
- B. Activate Amazon Inspector with ECR enhanced scanning configured for scan on push only, and add an EventBridge rule that deletes any pushed image that has a CRITICAL finding.
- C. Activate Amazon Inspector across the organization through a delegated administrator, with ECR enhanced scanning in continuous mode and EC2 scanning, and add an Amazon Inspector scan step (SBOM Generator plus the Inspector Scan API) to the build stage that fails the pipeline before the push when CRITICAL vulnerabilities are found.
- D. Enable Amazon GuardDuty EKS Runtime Monitoring and Malware Protection, and configure a Kubernetes admission controller that blocks pods whose images have GuardDuty findings.

### Question 9
A data analytics company runs Amazon EMR and Amazon EC2 processing clusters in private subnets across three Availability Zones in one VPC in eu-west-1. Each AZ has its own NAT gateway. Cost Explorer shows NAT gateway data processing charges of about $38,000 per month. VPC Flow Logs analysis shows that about 85% of the bytes through the NAT gateways go to Amazon S3 buckets and Amazon DynamoDB tables in eu-west-1. The rest goes to third-party SaaS APIs on the internet. Security policy forbids public IP addresses on processing nodes. The company wants the largest cost reduction with minimal application change.

Which combination of actions should the architect take? **(Select TWO.)**

- A. Create a gateway VPC endpoint for Amazon S3, associate it with the route tables of the private subnets, and attach an endpoint policy that allows access only to the company's buckets.
- B. Create interface VPC endpoints for Amazon S3 in each AZ, and enable private DNS so that the clusters resolve S3 to the interface endpoints.
- C. Create a gateway VPC endpoint for Amazon DynamoDB, and associate it with the route tables of the private subnets.
- D. Consolidate the three NAT gateways into a single NAT gateway in one AZ, and route all private subnets through it.
- E. Move the processing nodes into public subnets that route to an internet gateway, and use security groups to block all inbound traffic.

### Question 10
A healthcare company has finished moving 900 TB of archive data from an on-premises tape library into a single Amazon S3 bucket in S3 Standard by using AWS DataSync. The bucket holds about 2.5 billion objects. About 1.8 billion are application log fragments smaller than 32 KB (about 2% of total bytes); the rest are imaging studies that average 1.5 GB. Regulations require 7-year retention. Retrieval is rare, and a 48-hour retrieval time is acceptable. A `/staging/` prefix holds files that are overwritten or deleted 30–60 days after creation. An engineer proposes one lifecycle rule that transitions every object in the bucket to S3 Glacier Deep Archive after 1 day, and sets the transition default minimum object size to `varies_by_storage_class` so that the small log fragments also transition.

Which approach will result in the LOWEST total cost while meeting the requirements?

- A. Implement the engineer's proposal as written, because S3 Glacier Deep Archive has the lowest per-GB storage price of any S3 storage class.
- B. Transition all objects to S3 Glacier Flexible Retrieval after 30 days and then to S3 Glacier Deep Archive after 120 days, so that recently migrated data stays quickly retrievable at first.
- C. Move all objects to S3 Intelligent-Tiering, and activate the Deep Archive Access tier so that objects are archived automatically after 180 consecutive days without access.
- D. Scope a lifecycle rule to the archive prefixes only, with an object size filter so that only the large imaging objects transition to S3 Glacier Deep Archive after 1 day. Batch the small log fragments into large aggregated objects before archiving them, and keep `/staging/` in S3 Standard with an expiration rule.

### Question 11
Six months ago, a company rehosted 400 Linux application servers to Amazon EC2 by using AWS Application Migration Service (now AWS Transform MGN). The instances were sized to match the on-premises hardware, mostly m5.4xlarge. Average CPU utilization is 9–15%, but the quarter-end financial close drives heavy load for about 5 days every 3 months. The applications are Java and Python services built in a CI pipeline. The CFO wants data-driven rightsizing recommendations that account for the quarter-end peak and that evaluate a move to AWS Graviton instances for better price performance, before the company commits to Savings Plans.

Which approach should the architect take?

- A. Use Cost Explorer rightsizing recommendations with default settings, change the instance type of each running instance to the recommended Graviton type during the next maintenance window, and immediately buy a 3-year Compute Savings Plan.
- B. Opt in to AWS Compute Optimizer for the organization, activate enhanced infrastructure metrics so that recommendations use a 93-day lookback, install the CloudWatch agent to publish memory utilization, and include Graviton instance families in the preferred-instance recommendation preferences. Then rebuild the services as arm64 artifacts and AMIs, test them, and buy Savings Plans after rightsizing.
- C. Use the AWS Trusted Advisor low-utilization Amazon EC2 instances check to find idle instances, stop them, and buy 3-year Standard Reserved Instances for the m5 family to lock in savings before rightsizing.
- D. Opt in to AWS Compute Optimizer with the no-cost 32-day lookback period, apply the CPU-based recommendations without collecting memory metrics, and move to Graviton instance types only for the services that Compute Optimizer shows as low migration effort.

### Question 12
A genomics research company is designing a new nightly analysis pipeline. Each night, about 3,000 independent jobs run for 2–6 hours each on compute-optimized instances. The application writes a checkpoint to Amazon S3 every 10 minutes and can resume from the latest checkpoint on any instance. All jobs must finish by 06:00, but individual jobs can be delayed or restarted. The first design uses an Auto Scaling group of On-Demand c5.9xlarge instances. The company wants to minimize compute cost and still meet the deadline.

Which combination of design choices should the architect recommend? **(Select TWO.)**

- A. Use Spot Instances in the Auto Scaling group, restricted to c5.9xlarge in a single AZ, with the `lowest-price` allocation strategy so that the cheapest Spot pool is always used.
- B. Use an Auto Scaling group with a mixed instances policy (or attribute-based instance type selection) that spans many compute-optimized instance types, sizes and generations across all AZs, with Spot capacity and the `price-capacity-optimized` allocation strategy.
- C. Request Spot Instances with a defined duration (Spot blocks) of 6 hours so that the jobs run without interruption at a discounted price.
- D. Enable Capacity Rebalancing on the Auto Scaling group, and use a lifecycle hook together with rebalance recommendation and interruption notices to write an immediate checkpoint, stop taking new jobs, and let a replacement instance resume from the last checkpoint.
- E. Buy a Compute Savings Plan sized for the peak nightly vCPU count to get a discount on On-Demand c5 instances.

### Question 13
A retailer rehosted its product catalog web application to Amazon EC2 with Amazon RDS for MySQL 8.0 (db.r5.4xlarge with three read replicas). Reads make up 95% of database calls, and a few thousand product pages receive most of the traffic. The read replicas run at 80% CPU, and replica lag sometimes shows outdated prices. The business accepts catalog data up to 5 minutes old, except that a price change made by a merchandiser must be visible within seconds. As part of its modernization, the company wants to cut database cost and page latency, with limited code changes kept inside the data-access layer.

Which solution should the architect recommend?

- A. Deploy an Amazon ElastiCache (Valkey or Redis OSS) cluster and implement cache-aside (lazy loading) in the data-access layer with a 300-second TTL on product keys. Have the price-update path write to the database and then delete the affected cache keys, and reduce the number of read replicas after the cache warms.
- B. Add two more read replicas, and put Amazon RDS Proxy in front of the database so that reads are spread across five replicas through the proxy's read-only endpoint.
- C. Deploy Amazon DynamoDB Accelerator (DAX) in front of the RDS for MySQL instance to cache query results with microsecond latency, and set the item TTL to 300 seconds.
- D. Enable the MySQL query cache on each read replica by setting `query_cache_type` and `query_cache_size` in the DB parameter group, and reduce the replica instance size.

### Question 14
A SaaS company is designing a new Amazon Aurora MySQL cluster for a multi-tenant platform. The cluster will have a writer and four db.r6g.2xlarge Aurora Replicas for OLTP reads, plus two db.r6g.8xlarge replicas with large memory for long-running reporting queries. Aurora Auto Scaling will add db.r6g.2xlarge replicas during OLTP peaks. The requirements are: reporting queries must never run on the OLTP replicas; OLTP reads must never land on the reporting replicas; replicas added by Auto Scaling must serve OLTP reads automatically; and a failover should promote an OLTP-sized replica rather than a reporting replica.

Which design meets these requirements?

- A. Send OLTP reads to the cluster reader endpoint, and send reporting queries to the instance endpoints of the two reporting replicas with client-side round-robin.
- B. Create two custom endpoints, each with a static list: one listing the four OLTP replicas and one listing the two reporting replicas. Set all replicas to promotion tier 1.
- C. Create an Aurora clone of the cluster every night for reporting, and use the cluster reader endpoint for OLTP reads during the day.
- D. Create a `READER` custom endpoint with a static list that contains the two reporting replicas, and a `READER` custom endpoint with an exclusion list that excludes the two reporting replicas for OLTP reads. Give the OLTP replicas high-priority promotion tiers (for example, tiers 0–1) and the reporting replicas a low-priority tier (for example, tier 15).

### Question 15
A brokerage is designing the web tier for a new market-analytics application on Amazon EC2 instances in an Auto Scaling group behind an Application Load Balancer. Each instance needs about 12 minutes to become ready because it downloads 40 GB of reference data to an EBS volume and warms a JVM cache. Traffic ramps sharply at 08:00 local time on weekdays, is low at night and on weekends, and has occasional unpredictable spikes during major news. Latency must stay within the SLO during the morning ramp and during spikes. Instances must be On-Demand. The company wants to minimize cost.

Which combination of actions should the architect recommend? **(Select TWO.)**

- A. Create a scheduled action that sets desired capacity to the expected peak at 07:45 every weekday and back to the minimum at 18:00, and remove the dynamic scaling policies to avoid conflicts.
- B. Add a warm pool with instances kept in the `Running` state so that they can receive traffic immediately when the group scales out.
- C. Add a predictive scaling policy, evaluated first in forecast-only mode, to launch capacity ahead of the daily ramp, and keep a target tracking policy on ALB request count per target to respond to unpredictable spikes.
- D. Replace the target tracking policy with a step scaling policy that uses 1-minute detailed monitoring and adds 50% capacity per step.
- E. Add a warm pool with instances kept in the `Stopped` (or `Hibernated`) state, with a launch lifecycle hook that holds each new instance until the reference data download and cache warm-up finish before the instance is stopped, and enable instance reuse on scale-in.

### Question 16
A news publisher is preparing to launch a redesigned global website. Amazon CloudFront sits in front of an Application Load Balancer origin. In pre-launch load testing, the cache hit ratio is only 18% and origin load is far above plan. The distribution uses legacy cache settings that forward all headers, all cookies and all query strings to the origin. Analysis shows that pages vary only by the `lang` cookie and by the `page` and `section` query string parameters. Marketing links add `utm_*` parameters, every visitor carries unique analytics cookies, and browsers send many different `Accept-Encoding` values. The origin needs `User-Agent` and all cookies for logging but does not use them to build content.

Which change will MOST improve the cache hit ratio while still serving correct content?

- A. Keep the legacy settings, raise the default TTL to 24 hours, and enable Origin Shield in the Region closest to the origin.
- B. Create a cache policy that includes all cookies and the `User-Agent` header in the cache key but excludes all query strings, and enable Gzip compression.
- C. Create a cache policy that includes only the `lang` cookie and the `page` and `section` query strings in the cache key and enables Gzip and Brotli support (which normalizes `Accept-Encoding`). Attach an origin request policy that forwards `User-Agent` and all cookies to the origin without adding them to the cache key.
- D. Associate a Lambda@Edge viewer request function that removes all cookies, query strings and headers, so that each URL path is cached as a single object.

### Question 17
A company's production account (Account A) stores regulated documents in an S3 bucket in us-east-1, encrypted with SSE-KMS using a customer managed key. For backup isolation, the objects must be replicated to a bucket in a separate backup account (Account B) in us-west-2 and encrypted there with a customer managed key that Account B owns. The replication rule uses an IAM role in Account A, has `SseKmsEncryptedObjects` enabled, and names Account B's key ARN as `ReplicaKmsKeyID`. The replication role's policy currently allows `kms:Decrypt` on the source key only. The destination bucket policy allows the replication role, and a test object without SSE-KMS replicated successfully. However, SSE-KMS objects show a replication status of FAILED, and CloudTrail in Account B shows `AccessDenied` for `kms:Encrypt` calls made by Account A's replication role.

Which actions should the architect take to fix this? **(Select TWO.)**

- A. Update the key policy of Account B's customer managed key to allow Account A's replication role (or Account A) to use `kms:Encrypt` on the key.
- B. Change the destination bucket's default encryption to the AWS managed key `aws/s3` in Account B, and remove `ReplicaKmsKeyID` from the replication rule.
- C. Create a grant on Account A's source key that allows Account B's root principal to use `kms:Decrypt`.
- D. Enable S3 Bucket Keys on the destination bucket so that S3 no longer needs to call AWS KMS for each replicated object.
- E. Add a statement to the replication role's IAM policy in Account A that allows `kms:Encrypt` on Account B's key ARN, alongside the existing `kms:Decrypt` on the source key.

### Question 18
A company has 70 accounts in AWS Organizations. A recent audit found that most workload IAM roles still have the `AdministratorAccess` policy from an early migration, that some roles have not been used in months, and that some IAM users have old access keys. Auditors require the company to (1) continuously identify unused roles, unused access keys and passwords, and unused permissions across all accounts, and (2) replace broad policies on active roles with policies based on the actions those roles actually used over the last 90 days. CloudTrail trails log management events in every account. The security team wants to minimize custom tooling.

What should the architect do?

- A. Designate the security account as the IAM Access Analyzer delegated administrator, create an organization-level unused access analyzer, and act on its findings. For active roles, use IAM Access Analyzer policy generation with the CloudTrail trail and a 90-day range to create fine-grained policies, then add resource ARNs and validate the policies before replacing `AdministratorAccess`.
- B. Create an organization-level external access analyzer in IAM Access Analyzer from the delegated administrator account, and use its findings to remove the permissions that roles have not used in the last 90 days.
- C. Deploy a Lambda function to every account through StackSets that downloads the IAM credential report and calls `GenerateServiceLastAccessedDetails` weekly, writes the results to Amazon S3, and builds least-privilege policies with a custom script.
- D. Turn on the AWS Trusted Advisor IAM checks in every account through the organizational view, and use the results to identify roles with excessive permissions and to generate replacement policies.

### Question 19
A software company gives each developer their own AWS account in a Sandbox OU (120 accounts). Last month, leaked access keys in one sandbox account were used to launch GPU instances that cost $90,000 over a weekend before anyone noticed. FinOps wants three things: ML-based detection of unusual spend per account without maintaining static thresholds for every service; alerts in the team's Slack channel within minutes of detection; and, when a sandbox account's monthly forecasted or actual spend goes over $2,000, automatic prevention of further resource provisioning in that account without human approval.

Which solution meets these requirements?

- A. Create CloudWatch billing alarms on `EstimatedCharges` in us-east-1 for each linked account with a static threshold, and invoke a Lambda function that terminates all EC2 instances in the account when an alarm fires.
- B. In the management account, create an AWS Cost Anomaly Detection linked-account monitor with an alert subscription that sends individual (immediate) alerts to an SNS topic connected to Slack through Amazon Q Developer in chat applications (formerly AWS Chatbot). Create an AWS Budgets budget for each sandbox account, with a budget action that automatically applies a deny SCP (for example, denying `ec2:RunInstances`) to that account when the threshold is exceeded.
- C. In the management account, create an AWS Cost Anomaly Detection monitor with daily summary emails, and create AWS Budgets budgets with actions that stop the EC2 and RDS instances running in each sandbox member account directly from the management account.
- D. Turn on AWS Trusted Advisor cost optimization checks with weekly email summaries, and deploy the AWS Config managed rule `desired-instance-type` to the sandbox accounts to flag GPU instance types.

### Question 20
A company rehosted a legacy Java order-management application to Amazon EC2 instances in an Auto Scaling group, and migrated its database to Amazon RDS for SQL Server. The application reads a connection string with a plaintext password from a properties file that is baked into the AMI, and the same file is in the Git repository. Security now requires that hard-coded credentials be eliminated, that the database password rotate automatically every 30 days without failed logins or downtime, that access to the credential be auditable, and that the solution use managed services with minimal ongoing operations.

Which combination of steps should the architect recommend? **(Select THREE.)**

- A. Store the password as a `String` parameter in AWS Systems Manager Parameter Store, and use a cron job on one instance to change the database password and update the parameter every 30 days.
- B. Store the credentials in an AWS Secrets Manager secret encrypted with a customer managed KMS key, and grant the instances' IAM role `secretsmanager:GetSecretValue` on that secret only (plus `kms:Decrypt` on the key), with CloudTrail recording each access.
- C. Encrypt the properties file with AWS KMS, keep it in the AMI, decrypt it at startup with the instance role, and rebuild the AMI each time the password changes.
- D. Turn on Secrets Manager automatic rotation every 30 days with the AWS-provided rotation function for RDS for SQL Server, using the alternating users strategy and a separate superuser secret for the rotation function.
- E. Turn on Secrets Manager automatic rotation every 30 days with the single user strategy, and have the application cache the credential for 24 hours without retrying on login failure.
- F. Change the application to retrieve the secret at runtime with the AWS SDK and a Secrets Manager client-side caching library, refreshing the cached value when a login fails. Then remove the password from the AMI and the Git history, and change the exposed password immediately.

---

## Section 2 — Answer key

| Q | Answer | Domain / Task | Topic |
|---|---|---|---|
| 1 | C | D2 / 2.4 Reliability | Lambda exhausting Aurora connections → RDS Proxy |
| 2 | A, D | D3 / 3.1 Operational excellence | CloudWatch Synthetics + composite alarms with action suppression |
| 3 | D | D3 / 3.3 Performance | ADOT/OpenTelemetry tracing to X-Ray for microservice latency |
| 4 | B, E | D1 / 1.4 Multi-account environment | Quick Setup patch policies + Default Host Management Configuration |
| 5 | B | D3 / 3.2 Security | Config rule + SSM Automation auto-remediation (organization conformance pack) |
| 6 | C, D | D1 / 1.2 Security controls | Security Hub CSPM cross-Region aggregation → EventBridge → automated response |
| 7 | A | D1 / 1.2 Security controls | GuardDuty delegated admin per Region + auto-enable ALL |
| 8 | C | D2 / 2.3 Security controls | Amazon Inspector continuous ECR/EC2 scanning + CI/CD scan gate |
| 9 | A, C | D3 / 3.5 Cost | NAT gateway data processing → S3/DynamoDB gateway endpoints |
| 10 | D | D4 / 4.3 New architecture | S3 lifecycle to Deep Archive: small-object, transition-request and minimum-duration traps |
| 11 | B | D4 / 4.4 Modernization | Compute Optimizer (93-day lookback, memory) + Graviton migration |
| 12 | B, D | D2 / 2.6 Cost | Diversified Spot + Capacity Rebalancing + checkpointing |
| 13 | A | D4 / 4.3 New architecture | ElastiCache cache-aside with TTL + invalidation for read-heavy RDS |
| 14 | D | D2 / 2.5 Performance | Aurora custom endpoints (static vs exclusion lists) + promotion tiers |
| 15 | C, E | D2 / 2.4 Reliability | Predictive scaling + target tracking + warm pools (Stopped/Hibernated) |
| 16 | C | D2 / 2.5 Performance | CloudFront cache policy vs origin request policy, normalized cache key |
| 17 | A, E | D1 / 1.2 Security controls | Cross-account SSE-KMS replication: key policy + IAM policy |
| 18 | A | D3 / 3.2 Security | IAM Access Analyzer unused access + policy generation |
| 19 | B | D1 / 1.5 Cost & visibility | Cost Anomaly Detection + Budgets actions (SCP) |
| 20 | B, D, F | D4 / 4.4 Modernization | Secrets Manager + alternating-users rotation + runtime retrieval with caching |

**Single-answer distribution:** A ×3 (Q7, Q13, Q18), B ×3 (Q5, Q11, Q19), C ×3 (Q1, Q8, Q16), D ×3 (Q3, Q10, Q14). Eight questions are multi-select (Q2, Q4, Q6, Q9, Q12, Q15, Q17, Q20).

---

## Section 3 — Detailed solutions

### Q1 — Answer: **C**
**Decisive keywords:** "2,500 concurrent Lambda executions", "thousands of short-lived connections", "avoid rewriting the data-access layer", "fast recovery during failover", "no passwords in environment variables".

**Why C is correct:** Amazon RDS Proxy keeps a pool of database connections and multiplexes many client connections onto far fewer database connections. That removes both the connection-slot exhaustion and the CPU cost of constant connection setup and teardown. The proxy reads database credentials from the existing Secrets Manager secret, and Lambda can authenticate to the proxy with IAM, so no password goes into environment variables. The functions keep their PostgreSQL driver and only change the endpoint. During an Aurora failover, the proxy keeps client connections open and sends traffic to the new writer, which shortens failover time for applications compared with waiting for DNS to change. Opening the connection outside the handler lets warm execution environments reuse it.

**Why the others are wrong:**
- **A:** `max_connections` is limited by instance memory. Raising it and scaling up the writer costs more and only moves the ceiling. Connection churn and CPU overhead stay, and reserved concurrency set to 2,500 *guarantees* 2,500 possible connections instead of limiting them.
- **B:** The RDS Data API does remove driver-level connection handling, but it means rewriting every query call to an HTTP/JSON API. The stem explicitly rules out rewriting the data-access layer.
- **D:** An SQS buffer makes a synchronous API asynchronous, which breaks the API contract. Capping concurrency at 50 would also throttle a real-time API.

**Concept to remember:** Serverless compute plus relational database plus connection storms points to **RDS Proxy** (connection pooling, IAM auth, Secrets Manager, faster failover). Watch for *session pinning* (session-level SET statements, temporary tables and similar), which reduces multiplexing.

**References:** [Amazon RDS Proxy](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/rds-proxy.html) · [Avoiding pinning](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/rds-proxy-pinning.html) · [Using Lambda with Amazon RDS](https://docs.aws.amazon.com/lambda/latest/dg/services-rds.html)

---

### Q2 — Answer: **A, D**
**Decisive keywords:** "400 pages per week", "low-traffic night… no single metric breached", "broken customer journeys", "no paging during approved deployment windows", "minimal custom code".

**Why A and D are correct:**
- **A:** CloudWatch Synthetics canaries are scripted, scheduled user journeys (Node.js or Python, using Puppeteer, Playwright or Selenium). They create their own traffic, so they catch a broken checkout even at 3 a.m. when real traffic is too light to move any metric. `SuccessPercent` gives a direct, customer-centric signal.
- **D:** Composite alarms combine many alarms with `AND`, `OR` and `NOT` into one signal. Moving the paging action to the composite alarm (and leaving the underlying alarms without actions) cuts noise sharply. **Composite alarm action suppression** lets you name a *suppressor alarm*, such as one that is in ALARM during a deployment window. While the suppressor is in ALARM, the composite alarm takes no actions. `WaitPeriod` and `ExtensionPeriod` handle timing edge cases. All of this is configuration, not code.

**Why the others are wrong:**
- **B:** Anomaly detection can improve individual thresholds, but every alarm still pages on its own. Noise stays the same or grows, and nothing detects a broken journey when traffic is too low to be anomalous.
- **C:** Requiring 15 of 15 datapoints delays detection of real incidents by 15 minutes or more and still doesn't catch a silent functional failure.
- **E:** A custom deduplication Lambda is extra code to own, doesn't add journey-level detection, and doesn't understand deployment windows.

**Concept to remember:** **Synthetics** catches what metrics miss (proactive, journey-level checks), and **composite alarms plus a suppressor alarm** cut the noise (page on symptoms, not causes).

**References:** [CloudWatch Synthetics canaries](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/CloudWatch_Synthetics_Canaries.html) · [Create a composite alarm](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/Create_Composite_Alarm.html) · [Alarm suppression](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/alarm-suppression.html)

---

### Q3 — Answer: **D**
**Decisive keywords:** "which downstream call", "14 microservices on Fargate and Lambda", "vendor-neutral, long-term support", "X-Ray SDKs and daemon in maintenance mode".

**Why D is correct:** Distributed tracing is the only option that shows end-to-end request paths with a timed segment or span for every hop, including AWS SDK calls to DynamoDB and S3 and HTTP calls to third parties. AWS put the X-Ray SDKs and daemon into maintenance mode on 25 February 2026, with end of support scheduled for 25 February 2027, and recommends OpenTelemetry instead. In practice that means ADOT or OpenTelemetry SDKs, with the CloudWatch agent or an OpenTelemetry Collector replacing the X-Ray daemon. X-Ray still accepts and displays the traces. On Fargate, the collector runs as a sidecar container in each task. For Lambda, the ADOT layer provides the instrumentation. The trace map and trace timelines show exactly which segment grew from milliseconds to seconds. CloudWatch Application Signals builds on the same OpenTelemetry data to add service-level dashboards and SLOs.

**Why the others are wrong:**
- **A:** Flow logs record IP-level flow metadata over aggregation windows. They don't show per-request latency or application-level call paths, and they can't see inside TLS to a third-party API.
- **B:** Lambda Insights and Container Insights give resource and runtime metrics, which the stem already says look normal. They don't link a slow request to a specific downstream call.
- **C:** Hand-built log correlation is high effort, easy to get wrong, hard to keep up across 14 services, and is a homemade version of tracing.

**Concept to remember:** "Which hop is slow across microservices" points to **distributed tracing**. As of 2026, the strategic choice is **OpenTelemetry (ADOT) to X-Ray / Application Signals**, not new X-Ray SDK work.

**References:** [Migrating from X-Ray instrumentation to OpenTelemetry](https://docs.aws.amazon.com/xray/latest/devguide/xray-sdk-migration.html) · [X-Ray SDK and daemon end-of-support timeline](https://docs.aws.amazon.com/xray/latest/devguide/xray-daemon-eos.html) · [AWS Distro for OpenTelemetry](https://aws.amazon.com/otel/) · [CloudWatch application monitoring](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/CloudWatch-Application-Monitoring-Sections.html)

---

### Q4 — Answer: **B, E**
**Decisive keywords:** "180 accounts… four Regions", "daily scan", "within 14 days", "Sunday 02:00 UTC window", "not managed nodes", "least operational overhead".

**Why B and E are correct:**
- **B:** A Quick Setup **patch policy** defines the patch schedule and baselines for all accounts and Regions in an organization, or for selected OUs and Regions, from a single configuration. You choose **Scan** or **Scan and install**, a scan schedule (the default is daily), and an install schedule (a CRON expression meets the Sunday 02:00 UTC window). It also has rate controls for concurrency and error threshold, and optional reboot. A custom baseline that auto-approves Critical and Security patches after 7 days satisfies the 14-day SLA with room for testing. Patch policies run through State Manager associations, and the patching status appears centrally in Quick Setup and Patch Manager. **For an organization, you must create the patch policy from the management account.** The documentation says it can't be created from the delegated administrator account or a member account.
- **E:** Patch Manager can only patch **managed nodes**. Default Host Management Configuration (DHMC) lets Systems Manager manage EC2 instances without an instance profile, using an account-level role. Its prerequisites are a current SSM Agent and IMDSv2. Quick Setup can enable DHMC across the whole organization from the management account. The patch policy option to *add required IAM policies to existing instance profiles* covers instances that already have a profile but lack the permissions.

**Why the others are wrong:**
- **A:** It looks like good practice, but Quick Setup patch policies for an organization must be created from the management account. It also doesn't fix the unmanaged-instance problem.
- **C:** It works, but you build and maintain a maintenance window, baseline and task in every account and Region (720 account-Region pairs), which is much more overhead than one patch policy. Classic maintenance windows are still the right tool when you need complex pre- and post-patch task sequences for a specific workload.
- **D:** Amazon Inspector *finds* vulnerabilities. It doesn't install OS patches.

**Concept to remember:** Org-wide patching with the least overhead points to a **Quick Setup patch policy from the management account**. Unmanaged instances point to **DHMC** or fixing the instance profile.

**References:** [Quick Setup patch policies](https://docs.aws.amazon.com/systems-manager/latest/userguide/quick-setup-patch-manager.html) · [Patch policy configurations](https://docs.aws.amazon.com/systems-manager/latest/userguide/patch-manager-policies.html) · [Default Host Management Configuration](https://docs.aws.amazon.com/systems-manager/latest/userguide/managed-instances-default-host-management.html) · [DHMC for an organization with Quick Setup](https://docs.aws.amazon.com/systems-manager/latest/userguide/quick-setup-default-host-management-configuration.html)

---

### Q5 — Answer: **B**
**Decisive keywords:** "two approved exceptions must stay public", "fixed automatically within minutes", "compliance history", "60 accounts", "least ongoing effort".

**Why B is correct:** AWS Config is the service that keeps a compliance **history**, which is the auditor requirement. The managed rule `s3-bucket-level-public-access-prohibited` evaluates bucket-level Block Public Access settings when a bucket's configuration changes. Its `excludedPublicBuckets` parameter is how the two approved exceptions are handled. A conformance pack template can contain both `AWS::Config::ConfigRule` and `AWS::Config::RemediationConfiguration`, so the delegated administrator can deploy the rule and an **automatic** remediation to every account in one step. The remediation runs the `AWSConfigRemediation-ConfigureS3BucketPublicAccessBlock` Systems Manager Automation runbook, which turns the four bucket-level settings back on. Rules deployed through conformance packs must have their remediation declared in the template. You can't add it afterward with `PutRemediationConfigurations`.

**Why the others are wrong:**
- **A:** Account-level Block Public Access overrides bucket settings and would immediately break the two approved public buckets. Account-level BPA plus an SCP is the right *preventive* control once the CloudFront migration is done.
- **C:** Custom EventBridge and Lambda code in 60 accounts is more effort to maintain and keeps no compliance history. It would also need its own exception logic.
- **D:** Macie is for discovering sensitive data, and its bucket-posture findings only notify. A notification isn't an automatic fix.

**Concept to remember:** Detect, record history and auto-fix at organization scale points to a **Config rule with automatic SSM Automation remediation**, deployed by an **organization conformance pack**. Exceptions belong in rule parameters. Preventive guardrails (account BPA, SCPs) come once there are no exceptions left.

**References:** [s3-bucket-level-public-access-prohibited](https://docs.aws.amazon.com/config/latest/developerguide/s3-bucket-level-public-access-prohibited.html) · [AWSConfigRemediation-ConfigureS3BucketPublicAccessBlock](https://docs.aws.amazon.com/systems-manager-automation-runbooks/latest/userguide/automation-aws-block-public-s3-bucket.html) · [Remediating noncompliant resources](https://docs.aws.amazon.com/config/latest/developerguide/remediation.html) · [Conformance packs](https://docs.aws.amazon.com/config/latest/developerguide/conformance-packs.html)

---

### Q6 — Answer: **C, D**
**Decisive keywords:** "one place for all Regions", "automated response within minutes", "minimize infrastructure in member accounts and Regions".

**Why C and D are correct:**
- **C:** Security Hub CSPM **cross-Region aggregation** brings findings, finding updates, insights, control statuses and security scores from linked Regions into one **home Region** (older documentation and some API operations call it the *aggregation Region*). Aggregation has no added cost. Combined with the organization delegated administrator, it gives one view of all accounts and Regions.
- **D:** Every new or updated finding is sent to EventBridge as a `Security Hub Findings - Imported` event. In the home Region, that event stream includes findings from linked Regions in near real time. So a **single** EventBridge rule in a single account and Region can filter on severity and resource type and start a Step Functions workflow. The workflow assumes a role in the affected account, calls EC2 in the finding's Region to swap the security group and create snapshots, and can tag the instance for forensics.

**Why the others are wrong:**
- **A:** AWS Config aggregators collect Config configuration and compliance data, not Security Hub findings. Config rule evaluations aren't a threat-response trigger.
- **B:** Custom actions are for manually sending a finding to EventBridge. Putting them in every member account spreads ownership out and isn't automatic.
- **E:** It works, but it puts rules and Lambda functions in up to 450 account-Region pairs. That's the opposite of minimizing member infrastructure, and Security Hub already centralizes the GuardDuty findings.

**Concept to remember:** Central automated security response points to **Security Hub (CSPM) delegated admin, cross-Region aggregation to a home Region, and one EventBridge rule**, with a cross-account role for the remediation step. (AWS now calls the original service *Security Hub CSPM*. Exam questions written for SAP-C02 simply say "Security Hub".)

**References:** [Cross-Region aggregation in Security Hub CSPM](https://docs.aws.amazon.com/securityhub/latest/userguide/finding-aggregation.html) · [Security Hub CSPM event types in EventBridge](https://docs.aws.amazon.com/securityhub/latest/userguide/securityhub-cwe-integration-types.html)

---

### Q7 — Answer: **A**
**Decisive keywords:** "every existing **and** future account", "six Regions", "protection plans", "members cannot disable or disassociate", "least overhead".

**Why A is correct:** A GuardDuty delegated administrator is **Regional**. The management account must designate it in every Region where you want GuardDuty, and it must be the **same account in all Regions**. Setting the organization auto-enable preference to **`ALL`** turns GuardDuty (and the selected protection plans) on for existing members *and* for accounts added later. Accounts managed through AWS Organizations can't disassociate themselves from the delegated administrator, unlike invitation-based members. One delegated administrator can manage up to 50,000 member accounts.

**Why the others are wrong:**
- **B:** The designation doesn't apply across Regions; GuardDuty is a Regional service. `NEW` also leaves out every existing account.
- **C:** AWS doesn't recommend making the management account the delegated administrator (least privilege), and `NEW` again skips the existing 250 accounts.
- **D:** Invitation-based membership is the legacy model. It needs manual acceptance, doesn't scale to weekly account creation, and gives weaker central control.

**Concept to remember:** Org-wide security services such as GuardDuty, Security Hub, Inspector and Macie use a **delegated admin in each Region** with **auto-enable `ALL`** for existing and new accounts. `NEW` covers only future accounts.

**References:** [Managing GuardDuty accounts with AWS Organizations](https://docs.aws.amazon.com/guardduty/latest/ug/guardduty_organizations.html) · [Setting organization auto-enable preferences](https://docs.aws.amazon.com/guardduty/latest/ug/set-guardduty-auto-enable-preferences.html)

---

### Q8 — Answer: **C**
**Decisive keywords:** "never be **pushed** to ECR", "re-evaluated automatically whenever a new CVE is published", "EC2 fleet", "centralized", "no third-party scanners".

**Why C is correct:** Three separate needs map to three Inspector features:
1. **Before the push (shift left):** The Amazon Inspector CI/CD integration runs the **Inspector SBOM Generator** on the image in the build stage and sends the CycloneDX SBOM to the **Inspector Scan API**. There are plugins and actions for CodePipeline, Jenkins, TeamCity, GitHub Actions and GitLab. The build fails on CRITICAL findings, so the image never reaches ECR.
2. **After the push:** ECR **enhanced scanning** with Inspector in **continuous** mode re-evaluates stored images automatically when new CVEs are published, without scheduled rescans.
3. **EC2:** Inspector EC2 scanning (agent-based through SSM, or agentless) re-evaluates hosts continuously, and an organization delegated administrator centralizes the findings.

**Why the others are wrong:**
- **A:** Basic scanning doesn't scan continuously, and nightly `StartImageScan` calls are a scheduled-rescan workaround. Patch Manager reports missing OS patches, not application or package CVEs in containers. It also doesn't stop vulnerable images from being pushed.
- **B:** The image is already pushed before it's scanned, which breaks the "never pushed" rule. Scan on push without continuous mode also misses CVEs published later.
- **D:** GuardDuty detects threats (runtime behavior, malware). It isn't a CVE vulnerability scanner.

**Concept to remember:** **Inspector** handles CVEs: **CI/CD SBOM scan** before the push, **ECR enhanced continuous** scanning after the push, and **EC2/Lambda** scanning in production. **GuardDuty** handles threats.

**References:** [Integrating Inspector scans into CI/CD](https://docs.aws.amazon.com/inspector/latest/user/scanning-cicd.html) · [Inspector Scan actions with CodePipeline](https://docs.aws.amazon.com/inspector/latest/user/cicd-inspector-codepipeline-actions.html) · [Scanning ECR images with Inspector](https://docs.aws.amazon.com/inspector/latest/user/scanning-ecr.html) · [ECR enhanced scanning](https://docs.aws.amazon.com/AmazonECR/latest/userguide/image-scanning-enhanced.html)

---

### Q9 — Answer: **A, C**
**Decisive keywords:** "NAT gateway **data processing** charges", "85% to S3 and DynamoDB in the same Region", "no public IPs", "largest cost reduction".

**Why A and C are correct:** Gateway VPC endpoints exist only for **Amazon S3 and Amazon DynamoDB**. They work by adding prefix-list routes to route tables and have **no hourly or data processing charge**. Traffic to same-Region S3 and DynamoDB then bypasses the NAT gateway entirely, removing about 85% of the NAT data-processing cost with no application change, because the SDKs keep using the same public endpoints. An endpoint policy on the S3 gateway endpoint also narrows data-exfiltration paths. Only the SaaS traffic still goes through the NAT gateways.

**Why the others are wrong:**
- **B:** Interface endpoints for S3 work and support private DNS, but they charge per AZ-hour plus per GB processed. Gateway endpoints are free, so B saves less than A. Use S3 interface endpoints when you need access from on premises, from peered or other VPCs, or from another Region.
- **D:** One NAT gateway reduces hourly charges, but **data processing is charged per GB no matter how many gateways** you have. It also adds cross-AZ data transfer and a single-AZ point of failure.
- **E:** This breaks the security policy against public IPs.

**Concept to remember:** A high NAT gateway bill with same-Region S3 or DynamoDB traffic points to **gateway endpoints**, which are free. Gateway endpoints only work within the same Region and can't be reached from on premises or across peering.

**References:** [Gateway endpoints](https://docs.aws.amazon.com/vpc/latest/privatelink/gateway-endpoints.html) · [NAT gateway pricing](https://docs.aws.amazon.com/vpc/latest/userguide/nat-gateway-pricing.html) · [Amazon VPC pricing](https://aws.amazon.com/vpc/pricing/)

---

### Q10 — Answer: **D**
**Decisive keywords:** "1.8 billion objects < 32 KB (2% of bytes)", "`varies_by_storage_class`", "`/staging/`… deleted 30–60 days", "LOWEST total cost".

**Why D is correct:** Archiving tiny objects costs money in three ways:
1. **Transition requests:** Each object moved to Glacier Flexible Retrieval or Deep Archive is billed as one lifecycle transition request. At list prices on the order of $0.05 per 1,000 Deep Archive transitions (check the [S3 pricing page](https://aws.amazon.com/s3/pricing/) for your Region), 1.8 billion objects cost roughly $90,000 one time. That's to move about 18 TB, which only costs a few hundred dollars a month to keep in S3 Standard, so the payback period runs well past the 7-year retention.
2. **Per-object overhead:** Every archived object gets **40 KB of metadata**: 8 KB billed at S3 Standard rates and 32 KB at the archive rate. For a 20 KB fragment, that's more overhead than data.
3. **Minimum storage duration:** Deep Archive bills a **180-day minimum**, so objects deleted after 30–60 days pay a prorated early-deletion charge for the rest of the period.

That's why S3 now **blocks objects smaller than 128 KB from transitioning by default** (since September 2024). The engineer's `varies_by_storage_class` setting deliberately turns that protection off. Option D sends only the large imaging objects to Deep Archive (the 48-hour retrieval SLA fits Standard and Bulk retrievals), aggregates the small fragments into large archive files first, and leaves `/staging/` in S3 Standard, which has no minimum duration, with an expiration rule.

**Why the others are wrong:**
- **A:** It pays billions of transition requests, 40 KB of overhead per object and 180-day early-deletion charges on `/staging/`.
- **B:** It pays transition requests **twice**, adds a 90-day minimum on Glacier Flexible Retrieval, and delays the cheaper tier for no business reason, since retrieval is rare and 48 hours is fine.
- **C:** Objects smaller than 128 KB are never auto-tiered by Intelligent-Tiering; they stay in the Frequent Access tier, so they save nothing. Large objects pay a per-object monitoring fee and only reach the Deep Archive Access tier after 180 days without access. With a known access pattern, a direct lifecycle transition is cheaper.

**Concept to remember:** Glacier-class traps are **transition requests per object, 40 KB overhead per object, minimum durations (Glacier Instant Retrieval and Flexible Retrieval 90 days, Deep Archive 180 days, Standard-IA and One Zone-IA 30 days), and the 128 KB small-object default**. Aggregate small files before you archive them.

**References:** [Transitioning objects using S3 Lifecycle](https://docs.aws.amazon.com/AmazonS3/latest/userguide/lifecycle-transition-general-considerations.html) · [Comparing S3 storage classes](https://docs.aws.amazon.com/AmazonS3/latest/userguide/storage-class-intro.html) · [S3 Intelligent-Tiering](https://docs.aws.amazon.com/AmazonS3/latest/userguide/intelligent-tiering-overview.html) · [Amazon S3 pricing](https://aws.amazon.com/s3/pricing/)

---

### Q11 — Answer: **B**
**Decisive keywords:** "quarter-end peak… every 3 months", "evaluate Graviton", "data-driven", "before committing to Savings Plans".

**Why B is correct:**
- **Lookback:** Compute Optimizer offers a 14-day lookback (the default), a 32-day lookback (no extra cost) and a 93-day lookback. Only the 93-day window covers a full quarter including the 5-day close, and it requires the paid **enhanced infrastructure metrics** preference, which you can activate at organization, account or resource level.
- **Memory:** EC2 memory utilization isn't a default metric. Without the **CloudWatch agent** (or external metrics ingestion), Compute Optimizer can't safely recommend smaller memory footprints.
- **Graviton:** Recommendation preferences let you include Graviton families (for example m7g, c7g and r7g) as candidates. Moving from x86 to arm64 is a **re-platform**, not an instance-type flip. Java and Python usually port easily, but native dependencies, container images (multi-arch builds) and AMIs must be rebuilt for arm64 and tested.
- **Commitments after rightsizing:** Buying Savings Plans after rightsizing avoids committing to spend you're about to eliminate. A Compute Savings Plan also covers both x86 and Graviton instance families.

**Why the others are wrong:**
- **A:** You can't change an existing x86 instance to a Graviton type in place, because the AMI and binaries are x86_64. A 3-year commitment before rightsizing locks in waste. The default lookback also misses the quarterly peak.
- **C:** "Idle" instances may be the ones that peak at quarter-end. Buying 3-year m5 Standard RIs first locks the family and size before rightsizing and blocks the Graviton move.
- **D:** 32 days can't see a once-a-quarter peak, and CPU-only recommendations without memory data are risky for Java heaps.

**Concept to remember:** For rightsizing with Compute Optimizer: **match the lookback to the business cycle (14, 32 or 93 days; 93 needs paid enhanced metrics), collect memory with the CloudWatch agent, treat Graviton as an arm64 rebuild, and commit only after rightsizing.**

**References:** [Enhanced infrastructure metrics](https://docs.aws.amazon.com/compute-optimizer/latest/ug/enhanced-infrastructure-metrics.html) · [Rightsizing recommendation preferences](https://docs.aws.amazon.com/compute-optimizer/latest/ug/rightsizing-preferences.html) · [AWS Graviton](https://aws.amazon.com/ec2/graviton/)

---

### Q12 — Answer: **B, D**
**Decisive keywords:** "independent jobs", "checkpoint every 10 minutes… resume on any instance", "can be delayed or restarted", "minimize compute cost", "deadline".

**Why B and D are correct:**
- **B:** Spot is the cheapest fit for fault-tolerant, checkpointed batch work. Spreading across **many instance types, sizes, generations and AZs** gives Auto Scaling many Spot capacity pools to choose from. **`price-capacity-optimized`** chooses pools with the lowest interruption risk and then the lowest price, which is AWS's recommended strategy for most Spot workloads. Attribute-based instance type selection keeps the list current automatically.
- **D:** **Capacity Rebalancing** acts on the EC2 *rebalance recommendation*, which often arrives before the 2-minute interruption notice. Auto Scaling launches a replacement first, waits for it to pass health checks, and then terminates the at-risk instance (temporarily going up to 10% over max capacity if needed). A lifecycle hook gives the job time to write a final checkpoint and stop taking new work. At worst, a job loses about 10 minutes of progress.

**Why the others are wrong:**
- **A:** One instance type in one AZ is a single Spot pool, which gives the highest interruption risk and the most capacity shortages. AWS specifically warns against `lowest-price` with Capacity Rebalancing because replacements may land in pools that are about to be interrupted.
- **C:** Spot Instances with a defined duration (Spot blocks) are no longer offered, so this is a retired option used as a distractor.
- **E:** Savings Plans charge for the commitment around the clock. For a workload that runs only part of each night and tolerates interruption, Spot gives deeper savings with no commitment.

**Concept to remember:** For interruptible, checkpointed batch work: **diversified Spot, `price-capacity-optimized`, Capacity Rebalancing plus lifecycle hooks, and checkpoints to S3.**

**References:** [Capacity Rebalancing](https://docs.aws.amazon.com/autoscaling/ec2/userguide/ec2-auto-scaling-capacity-rebalancing.html) · [Allocation strategies for multiple instance types](https://docs.aws.amazon.com/autoscaling/ec2/userguide/allocation-strategies.html) · [Spot best practices](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/spot-best-practices.html)

---

### Q13 — Answer: **A**
**Decisive keywords:** "95% reads", "same few thousand pages", "up to 5 minutes stale is fine", "price change visible within seconds", "changes concentrated in the data-access layer".

**Why A is correct:** **Cache-aside (lazy loading)** suits read-heavy, skewed access. The application reads the cache first, and on a miss reads from RDS and fills the cache. Hot product pages are served from memory in under a millisecond, which takes most read load off the replicas and lets you remove replicas to save cost. A **300-second TTL** encodes the 5-minute staleness tolerance, so the cache refreshes itself. **Deleting the key on update**, after writing to the database, makes merchandiser price changes visible on the next read. Because the change sits in the data-access layer, it matches the limited-code-change constraint. Valkey and Redis OSS are both offered as ElastiCache engines.

**Why the others are wrong:**
- **B:** More replicas cost more and still use database CPU for every read. RDS Proxy pools connections but doesn't cache query results.
- **C:** DAX works only with Amazon DynamoDB, not RDS for MySQL.
- **D:** The MySQL query cache was **removed in MySQL 8.0**, so those parameters don't exist on an RDS for MySQL 8.0 instance.

**Concept to remember:** Read-heavy relational workloads with tolerable staleness point to **ElastiCache cache-aside plus a TTL matching the staleness tolerance, plus invalidate-on-write** for data that must be fresh.

**References:** [ElastiCache caching strategies](https://docs.aws.amazon.com/AmazonElastiCache/latest/dg/Strategies.html) · [Caching best practices](https://aws.amazon.com/caching/best-practices/)

---

### Q14 — Answer: **D**
**Decisive keywords:** "never on OLTP replicas / never on reporting replicas", "Auto Scaling replicas must serve OLTP automatically", "failover should promote an OLTP-sized replica".

**Why D is correct:** Aurora **custom endpoints** (up to five per cluster) load-balance connections across a set of instances that you define. Each endpoint uses either a **static list** (only the named instances) or an **exclusion list** (every eligible instance *except* the named ones, **including instances added later**, such as Aurora Auto Scaling replicas). So:
- The reporting endpoint uses a static list of the two large replicas, so nothing else joins it.
- The OLTP endpoint uses an exclusion list that excludes the two large replicas, so every new auto-scaled replica joins it automatically.
- Type `READER` (settable through the CLI or API; console-created endpoints are type `ANY`) means membership adjusts automatically if a replica is promoted to writer.
- Failover promotes the replica with the **highest priority (lowest tier number, 0 is highest)**, so tiers 0–1 on the OLTP replicas and tier 15 on the reporting replicas keep the large reporting instances out of the writer role.

**Why the others are wrong:**
- **A:** The cluster reader endpoint balances across **all** readers, including the reporting replicas, so OLTP reads would land on them.
- **B:** With static lists, auto-scaled replicas are **not** added to the OLTP endpoint. Equal promotion tiers also leave the failover target to Aurora's tie-breaking, which prefers the largest replica, so a reporting replica could become writer.
- **C:** A nightly clone serves day-old data and adds operational work. It also does nothing for failover or for the auto-scaling requirement.

**Concept to remember:** Separating workloads inside one Aurora cluster points to **custom endpoints**. Use a **static list** for a fixed special-purpose group and an **exclusion list** to pick up future replicas, and control failover with **promotion tiers**.

**References:** [Aurora custom endpoints](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/Aurora.Endpoints.Custom.html) · [Custom endpoint considerations and membership rules](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/Aurora.Endpoints.Custom.Considerations.html) · [Aurora high availability and failover](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/Concepts.AuroraHighAvailability.html)

---

### Q15 — Answer: **C, E**
**Decisive keywords:** "12 minutes to become ready", "sharp ramp at 08:00 on weekdays", "unpredictable spikes", "On-Demand", "minimize cost".

**Why C and E are correct:**
- **C:** **Predictive scaling** learns daily and weekly patterns from history and launches capacity *before* the forecast load arrives. AWS names cyclical traffic and long initialization times as the cases it's built for. Running it in **forecast-only** mode first lets you check accuracy before it acts. Predictive scaling doesn't react to unforecast events, so keep **target tracking** alongside it for news spikes; the two work together.
- **E:** A **warm pool** keeps pre-initialized instances next to the group. In the **Stopped** state you pay only for EBS volumes and attached Elastic IPs, not for compute. **Hibernated** also keeps RAM contents, such as the warmed JVM, if the instances meet hibernation prerequisites. A **launch lifecycle hook** is essential: without it, Auto Scaling may stop the instance before the 40 GB download finishes. **Instance reuse** returns instances to the pool on scale-in instead of terminating them. Warm pools need On-Demand capacity, because they don't support Spot in mixed instances groups, and the stem already says On-Demand.

**Why the others are wrong:**
- **A:** A fixed schedule can't adapt to changing patterns, and removing dynamic scaling leaves no response to unpredictable spikes.
- **B:** A warm pool kept in the `Running` state pays full instance cost for idle capacity. AWS explicitly discourages it.
- **D:** Any reactive policy still waits about 12 minutes for each new instance, so latency breaches during the ramp. Step scaling alone doesn't fix boot time.

**Concept to remember:** Slow boot plus predictable ramps points to **predictive scaling (pre-launch) plus target tracking (spikes) plus a warm pool in Stopped or Hibernated state with lifecycle hooks**.

**References:** [Predictive scaling](https://docs.aws.amazon.com/autoscaling/ec2/userguide/ec2-auto-scaling-predictive-scaling.html) · [How predictive scaling works](https://docs.aws.amazon.com/autoscaling/ec2/userguide/predictive-scaling-policy-overview.html) · [Warm pools](https://docs.aws.amazon.com/autoscaling/ec2/userguide/ec2-auto-scaling-warm-pools.html)

---

### Q16 — Answer: **C**
**Decisive keywords:** "cache hit ratio 18%", "legacy settings forward all headers, cookies, query strings", "pages vary only by `lang`, `page`, `section`", "origin needs User-Agent and cookies for logging only".

**Why C is correct:** CloudFront caches a separate object for every unique **cache key**. Forwarding everything through legacy settings puts every header, cookie and query string *in the cache key*, so unique analytics cookies and `utm_*` values make nearly every request a miss. A **cache policy** limits the cache key to the values that really change content (`lang`, `page`, `section`). Turning on **Gzip and Brotli** in the cache policy makes CloudFront normalize `Accept-Encoding`, so dozens of browser variants collapse into a few cache entries. An **origin request policy** sends extra values (`User-Agent`, all cookies) to the origin **without** adding them to the cache key, so origin logging still works.

**Why the others are wrong:**
- **A:** A longer TTL doesn't help when nearly every request has a unique cache key. Origin Shield reduces origin fetches from multiple edge caches but can't fix a fragmented cache key.
- **B:** Unique analytics cookies and the high-cardinality `User-Agent` header still fragment the cache. Excluding all query strings serves the **wrong content**, because `page` and `section` change the response.
- **D:** Stripping everything breaks the `lang` variation, pagination and origin logging, so users get incorrect pages.

**Concept to remember:** **Cache policy = what goes in the cache key (keep it small). Origin request policy = what the origin receives (doesn't affect hits).** Enable Gzip/Brotli to normalize `Accept-Encoding`.

**References:** [Control the cache key with a policy](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/controlling-the-cache-key.html) · [Control origin requests with a policy](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/controlling-origin-requests.html) · [Increase the proportion of requests served from CloudFront caches](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/cache-hit-ratio.html)

---

### Q17 — Answer: **A, E**
**Decisive keywords:** "cross-account", "customer managed key owned by Account B", "role policy allows kms:Decrypt on the source key only", "AccessDenied for kms:Encrypt in Account B".

**Why A and E are correct:** Cross-account use of a KMS key needs permission on **both** sides:
- **A (key owner side):** Account B's **key policy** must allow Account A's replication role, or Account A as a whole, to use `kms:Encrypt`. The S3 documentation says that if the KMS keys belong to another account, the key owner must grant those permissions to the account that owns the IAM role.
- **E (caller side):** Account A's replication role needs an IAM policy statement allowing `kms:Encrypt` on Account B's key ARN, ideally limited with `kms:ViaService` and the destination bucket's encryption context. The stem says the role currently has only `kms:Decrypt` on the source key.

The rest of the configuration is already right: `SseKmsEncryptedObjects` is enabled (SSE-KMS objects aren't replicated by default), `ReplicaKmsKeyID` points to a key **in the destination Region**, and S3 permissions are proven by the successful test object.

**Why the others are wrong:**
- **B:** **AWS managed keys (`aws/s3`) can't be used across accounts**, so cross-account SSE-KMS replication must use a customer managed key.
- **C:** The source key is owned by Account A and used by Account A's own role. Account B never decrypts source objects, so this grant fixes nothing.
- **D:** S3 Bucket Keys reduce how many KMS requests are made but don't remove the need for permission on the key. With Bucket Keys, the replica key policy also needs `kms:Decrypt` for the calling principal, and IAM conditions must use the **bucket** ARN as the encryption context.

**Concept to remember:** Cross-account KMS needs both **the key policy (owner grants)** and **the IAM policy (caller allowed)**. SSE-KMS replication also needs **`SseKmsEncryptedObjects` plus `ReplicaKmsKeyID` in the destination Region plus a customer managed key**, never `aws/s3`.

**References:** [Replicating encrypted objects](https://docs.aws.amazon.com/AmazonS3/latest/userguide/replication-config-for-kms-objects.html) · [Allowing users in other accounts to use a KMS key](https://docs.aws.amazon.com/kms/latest/developerguide/key-policy-modifying-external-accounts.html)

---

### Q18 — Answer: **A**
**Decisive keywords:** "continuously identify unused roles, access keys, passwords, permissions", "across all accounts", "policies based on actions actually used over 90 days", "minimize custom tooling".

**Why A is correct:** IAM Access Analyzer has three kinds of analysis:
- **Unused access analyzer (paid, priced per IAM role and user analyzed each month):** It continuously reports **unused roles, unused access keys and passwords, and unused service- and action-level permissions** across the organization when created from the **delegated administrator** account. That covers requirement 1.
- **Policy generation:** It reads a CloudTrail trail for a period of **up to 90 days** and produces a policy template containing the actions that the role actually used, with action-level detail for supported services and service-level detail otherwise. You then add resource ARNs and conditions, check the policy with policy validation, and attach it. That covers requirement 2. Points to know: `iam:PassRole` and data events aren't captured, and AWS Control Tower-created trails aren't supported for policy generation.
- **External and internal access analyzers** answer *who can reach a resource*, not *what is unused*.

**Why the others are wrong:**
- **B:** An **external access** analyzer reports resources shared outside the zone of trust, such as public or cross-account access. It doesn't report unused permissions.
- **C:** This works but is exactly the custom tooling the stem wants to avoid, and Access Analyzer already provides it as a managed feature.
- **D:** Trusted Advisor has only a few IAM hygiene checks. It doesn't analyze unused permissions in depth or generate policies.

**Concept to remember:** **Unused access analyzer** finds what to remove. **Policy generation (CloudTrail, up to 90 days)** builds the least-privilege replacement. **External access analyzer** finds unintended sharing.

**References:** [IAM Access Analyzer findings (external, internal, unused)](https://docs.aws.amazon.com/IAM/latest/UserGuide/access-analyzer-findings.html) · [Policy generation](https://docs.aws.amazon.com/IAM/latest/UserGuide/access-analyzer-policy-generation.html) · [Delegated administrator for IAM Access Analyzer](https://docs.aws.amazon.com/IAM/latest/UserGuide/access-analyzer-delegated-administrator.html)

---

### Q19 — Answer: **B**
**Decisive keywords:** "ML-based detection… no static thresholds", "Slack within minutes", "automatic prevention of further provisioning without human approval", "Sandbox OU".

**Why B is correct:**
- **Cost Anomaly Detection** uses machine learning to learn each monitor's spending pattern and flag unusual spend without fixed thresholds. A **linked-account** monitor in the management account covers the member accounts. **Individual (immediate) alerts** are delivered through **SNS**, and **Amazon Q Developer in chat applications** (the new name for AWS Chatbot) forwards SNS notifications to Slack.
- **AWS Budgets actions** can run **automatically or after approval**. They can apply an IAM policy or an SCP, or target specific EC2 or RDS instances. From the management account, a budget action **can apply an SCP to another account**, for example denying `ec2:RunInstances` and other provisioning APIs, which stops further provisioning in that sandbox.

**Why the others are wrong:**
- **A:** Billing alarms use static thresholds (the opposite of ML detection), and estimated-charges metrics update only a few times a day. Terminating every instance with custom code is a blunt, risky response.
- **C:** Daily summaries aren't "within minutes". Budget actions configured in the management account **can't target EC2 or RDS instances in another account**; only SCP actions work across accounts. Stopping instances would need budgets created inside each member account.
- **D:** Trusted Advisor gives weekly optimization advice, and a Config rule only flags instance types. Neither detects anomalies quickly or blocks spend.

**Concept to remember:** **Cost Anomaly Detection (ML, SNS for immediate alerts) + Budgets actions (auto-apply SCP or IAM policy; instance actions only in the same account)** turn FinOps detection into an automatic response.

**References:** [AWS Cost Anomaly Detection](https://docs.aws.amazon.com/cost-management/latest/userguide/manage-ad.html) · [Configuring budget actions](https://docs.aws.amazon.com/cost-management/latest/userguide/budgets-controls.html) · [Amazon Q Developer in chat applications](https://docs.aws.amazon.com/chatbot/latest/adminguide/what-is.html)

---

### Q20 — Answer: **B, D, F**
**Decisive keywords:** "hard-coded password in AMI and Git", "rotate every 30 days **without failed logins or downtime**", "auditable", "managed services".

**Why B, D and F are correct:**
- **B:** Secrets Manager stores the credential encrypted with KMS. A least-privilege instance role scoped to that one secret (plus `kms:Decrypt` on the customer managed key) controls access, and CloudTrail logs every `GetSecretValue` call for auditing.
- **D:** Built-in rotation runs a Lambda function on a schedule. With the **alternating users** strategy, the function clones the user and alternates which user's password it changes, so **both the current and previous credentials stay valid** after each rotation. That's the strategy AWS recommends for applications that need high availability. It needs a separate superuser secret so the function can manage the clone. AWS provides rotation templates for RDS for SQL Server.
- **F:** The application must fetch the secret at runtime instead of reading a baked-in file. The caching client reduces API calls and latency, and refreshing on authentication failure handles the moment just after rotation. Because the password was exposed in Git, it must be changed now and removed from history; deleting the file alone doesn't help, since the old value stays in the repository history.

**Why the others are wrong:**
- **A:** A `String` parameter stores the password in plaintext. (`SecureString` would encrypt it, but Parameter Store still has no native rotation.) A cron job on one instance is a homemade rotation process with a single point of failure.
- **C:** The password is still static and stored in the AMI. Every rotation would mean an AMI rebuild and redeploy, which is the opposite of automatic rotation without downtime.
- **E:** The single user strategy has a short window during rotation in which the database can reject the new credentials. A 24-hour cache with no retry on login failure guarantees failed logins after each rotation. AWS says single user rotation fits most cases *with a retry strategy*, but this option removes the retry.

**Concept to remember:** Migrating hard-coded credentials means **Secrets Manager plus least-privilege IAM plus runtime retrieval with caching and refresh-on-failure**. For zero-downtime rotation, use the **alternating users** strategy. (For the RDS master user, RDS can also manage the password in Secrets Manager for you.)

**References:** [Rotate Secrets Manager secrets](https://docs.aws.amazon.com/secretsmanager/latest/userguide/rotating-secrets.html) · [Lambda rotation strategies](https://docs.aws.amazon.com/secretsmanager/latest/userguide/rotation-strategy.html) · [Retrieve secrets (including caching)](https://docs.aws.amazon.com/secretsmanager/latest/userguide/retrieving-secrets.html)

---

## Score interpretation

| Score | What it means | What to do next |
|---|---|---|
| **≥ 16 / 20** | Ready. You're picking the managed, least-overhead fix and spotting the traps. | Do a timed full-length mixed paper next, and review only the questions you guessed. |
| **13–15 / 20** | Nearly there, but there are gaps in one or two domains. | Sort your misses by domain using the answer key, and review those chapters (below) before your next paper. |
| **< 13 / 20** | Gaps in core services, not just exam technique. | Re-study the linked chapters, rebuild the decision tables in your own words, then retake this paper in 48 minutes. |

**Re-study map: missed question → chapter**

| If you missed… | Re-study |
|---|---|
| Q4 (patch policies, DHMC), Q7 (GuardDuty org), Q19 (Budgets SCP actions) | [02 — Multi-Account Governance](../02-Multi-Account-Governance.md) |
| Q17 (cross-account KMS), Q18 (Access Analyzer), Q20 (IAM for secrets) | [03 — Identity and Access Management](../03-Identity-and-Access-Management.md) |
| Q9 (gateway endpoints vs NAT gateway) | [04 — Networking, VPC and Hybrid Connectivity](../04-Networking-VPC-and-Hybrid-Connectivity.md) |
| Q16 (CloudFront cache and origin request policies) | [05 — Edge, DNS and Content Delivery](../05-Edge-DNS-and-Content-Delivery.md) |
| Q5 (Config remediation), Q6 (Security Hub automation), Q7 (GuardDuty), Q8 (Inspector), Q17 (KMS), Q20 (Secrets Manager) | [06 — Security, Data Protection and Threat Detection](../06-Security-Data-Protection-and-Threat-Detection.md) |
| Q1 (Lambda and RDS Proxy), Q11 (Graviton), Q12 (Spot), Q15 (Auto Scaling) | [07 — Compute, Containers and Serverless](../07-Compute-Containers-and-Serverless.md) |
| Q10 (S3 lifecycle and Glacier traps) | [08 — Storage and Data Transfer](../08-Storage-and-Data-Transfer.md) |
| Q1 (RDS Proxy), Q13 (ElastiCache), Q14 (Aurora custom endpoints) | [09 — Databases and Caching](../09-Databases-and-Caching.md) |
| Q6 (EventBridge-driven response) | [10 — Application Integration and Event-Driven](../10-Application-Integration-and-Event-Driven.md) |
| Q15 (warm pools, predictive scaling for availability) | [12 — Resilience, HA and Disaster Recovery](../12-Resilience-HA-and-Disaster-Recovery.md) |
| Q10, Q11, Q13, Q20 (post-migration optimization) | [13 — Migration and Modernization](../13-Migration-and-Modernization.md) |
| Q8 (pipeline scan gates) | [14 — Deployment, DevOps and IaC](../14-Deployment-DevOps-and-IaC.md) |
| Q2 (Synthetics, composite alarms), Q3 (OpenTelemetry tracing), Q4 (Patch Manager), Q5 (auto-remediation) | [15 — Monitoring, Operations and Continuous Improvement](../15-Monitoring-Operations-and-Continuous-Improvement.md) |
| Q9, Q10, Q11, Q12, Q19 (cost levers) | [16 — Cost Optimization and FinOps](../16-Cost-Optimization-and-FinOps.md) |

**Patterns to take away from this paper**
1. **Fix the root cause with the smallest managed change:** RDS Proxy rather than a bigger database, gateway endpoints rather than fewer NAT gateways, cache policies rather than longer TTLs.
2. **Organization-scale security uses a delegated admin in each Region with auto-enable `ALL`**, plus one central aggregation point. Watch for the exceptions where the **management account** is required, such as Quick Setup patch policies for an organization and DHMC.
3. **Know the "renamed or retired" traps:** X-Ray SDKs and daemon are in maintenance mode (use OpenTelemetry/ADOT), Spot blocks are gone, the MySQL 8.0 query cache is gone, AWS Chatbot is now Amazon Q Developer in chat applications, and the original Security Hub is now Security Hub CSPM.
4. **Know the cost traps:** per-object transition requests and 40 KB of overhead, minimum storage durations, committing to Savings Plans or RIs before rightsizing, and keeping a warm pool in the `Running` state.

> [← Practice papers index](README.md) · [Study guide index](../00-README-Start-Here.md)
