# Practice Paper 2 — Designing New Solutions (Serverless, Containers, Data)
> Original SAP-C02-style questions (not real exam questions). 20 questions · suggested time 48 min (≈2.4 min/question, exam pace).
> Domain mix: D1 ×5, D2 ×6, D3 ×5, D4 ×4
> [← Practice Papers index](README.md) · [Study Guide index](../00-README-Start-Here.md)

**How to use this paper:** Set a 48-minute timer and answer all 20 questions before you open Section 2. On the real exam, a "Select TWO/THREE" question is scored as one item and you get credit only if every choice is right. Score yourself the same way. Then read **every** solution in Section 3, including for the questions you got right. The decisive keywords are the skill the exam is testing.

---

## Section 1 — Questions

### Q1 (Select TWO)
A ticketing startup is building a new public API for flash ticket sales. Traffic is close to zero for most of the week. When a popular event goes on sale, requests rise more than 50-fold within seconds and stay high for 20–40 minutes. Traffic for a new event cannot be forecast, but the marketing team announces the largest on-sales about a week in advance. All data access is key-value (`eventId` + `seatId`). The engineering team has four people and wants no servers or clusters to patch. Leadership wants the lowest possible cost in idle periods and no throttled purchases during announced mega on-sales.

Which combination of actions meets these requirements? **(Select TWO.)**

- A. Run the API on Amazon ECS on AWS Fargate behind an Application Load Balancer with target-tracking auto scaling, and store seat inventory in an Amazon Aurora provisioned cluster with read replicas.
- B. Build the API with Amazon API Gateway and AWS Lambda, and store seat inventory in an Amazon DynamoDB table that uses on-demand capacity mode.
- C. Store seat inventory in a DynamoDB table that uses provisioned capacity with auto scaling at a 70% target utilization, so that it scales up as on-sale traffic arrives.
- D. Set Lambda reserved concurrency to zero on days with no sales, and have an operator raise it by hand shortly before each on-sale starts.
- E. Before each announced mega on-sale, raise the DynamoDB table's warm throughput to the expected peak so that the table can serve it immediately with no ramp-up.

### Q2
A retailer runs a product catalog microservice on Amazon DynamoDB. The service makes about 95% reads (`GetItem` and `Query`) and 5% writes. A new real-time personalization engine calls the service thousands of times for every page render, and it needs read latency in the low microseconds rather than the current single-digit milliseconds. The application already uses the AWS SDK DynamoDB client. The team wants the smallest possible code change and no custom cache-invalidation logic. Product data that is a few seconds stale is acceptable.

Which solution meets these requirements?

- A. Deploy an Amazon ElastiCache (Valkey/Redis OSS) cluster, add cache-aside logic with TTLs to every read path, and invalidate cache keys in the write path.
- B. Switch the table to provisioned capacity with a much higher read capacity, and rely on adaptive capacity to remove hot-partition latency.
- C. Deploy an Amazon DynamoDB Accelerator (DAX) cluster with at least three nodes across Availability Zones, replace the DynamoDB client with the DAX client, and keep eventually consistent reads.
- D. Deploy a DAX cluster, replace the DynamoDB client with the DAX client, and switch all reads to strongly consistent so that every response is served from the up-to-date cache.

### Q3
A payments company is designing a new event-driven ledger service. Each customer's payment events must be applied in exactly the order they were produced. Events for different customers should be processed in parallel to keep up with peaks of a few thousand messages per second. Producers sometimes retry `Send` calls after timeouts, and a duplicate ledger entry would be a serious compliance incident. Consumers are AWS Lambda functions. Events do not need to be replayed after they are processed. The team wants the least operational overhead.

Which design meets these requirements?

- A. Send events to an Amazon SQS FIFO queue with high throughput mode turned on. Set `MessageGroupId` to the customer ID and `MessageDeduplicationId` to the payment ID, and consume the queue with a Lambda event source mapping.
- B. Send events to an Amazon SQS standard queue with the customer ID as a message attribute, and have the Lambda consumer sort each batch by producer timestamp before it writes to the ledger.
- C. Send events to an Amazon Kinesis Data Streams stream with the customer ID as the partition key, consume it with a Lambda event source mapping with a parallelization factor of 10, and rely on the stream to drop producer retries.
- D. Publish events to an Amazon SNS standard topic that fans out to a separate SQS standard queue per customer, which a provisioning Lambda function creates when it sees a new customer ID.

### Q4
A smart-building company is launching a new IoT platform. About 50,000 sensor readings arrive every second through AWS IoT Core. Each reading must go through a four-step workflow: validate the payload, enrich it with a Lambda function, write it to DynamoDB, and publish an alert if a threshold is exceeded. Every step is idempotent, and each workflow finishes in under 2 seconds. The company wants the lowest orchestration cost and needs execution details for troubleshooting. It does not need a durable, exactly-once audit history.

Which approach should the solutions architect choose?

- A. Use AWS Step Functions Standard Workflows started by an AWS IoT rule action, and use the 90-day execution history for troubleshooting.
- B. Use Step Functions Standard Workflows that batch readings every few seconds and process them inside a Distributed Map state.
- C. Use Step Functions Express Workflows, and use a `.waitForTaskToken` task to pause until DynamoDB confirms each write before the alert step runs.
- D. Use asynchronous Step Functions Express Workflows started by an AWS IoT rule action, and send execution logs to Amazon CloudWatch Logs.

### Q5
An insurance company is modernizing an on-premises claims process. Today it runs on cron jobs and a legacy BPM tool that emails adjusters. In the new AWS design, claims above $10,000 need a human adjuster's approval. Adjusters sometimes take up to 10 days to respond, and claims that get no response within 72 hours must be escalated. Auditors need a visual, step-by-step record of every claim's path. Adjusters approve or reject by clicking a link in an email. The company wants the least custom code and no servers to manage.

Which solution meets these requirements?

- A. Use a Step Functions Express Workflow with a Wait state that checks a DynamoDB approval flag every minute until the adjuster responds.
- B. Use a Step Functions Standard Workflow with a Lambda `.waitForTaskToken` task that emails approve/reject links (through API Gateway) containing the task token. The API backend calls `SendTaskSuccess` or `SendTaskFailure`, and a 72-hour task timeout is caught to route the claim to escalation.
- C. Use a Step Functions Standard Workflow with an Activity task, served by a worker application on an Amazon EC2 Auto Scaling group that polls `GetActivityTask` and holds each task until the adjuster replies.
- D. Put each pending claim in an Amazon SQS queue with a 10-day visibility timeout, and have a Lambda function delete the message when the adjuster clicks the approval link.

### Q6 (Select TWO)
A media company runs 120 stateless microservices on Amazon EKS. Today they use managed node groups of On-Demand m5 instances scaled by the Kubernetes Cluster Autoscaler. Average node CPU utilization is 35% because many node groups are sized for different pod shapes. Finance has asked for a large cut in compute cost. The services tolerate losing individual pods, but the platform team insists that pods must not get stuck in Pending when Spot capacity is short. The team also wants fewer node groups to maintain.

Which combination of actions meets these requirements? **(Select TWO.)**

- A. Replace Cluster Autoscaler with Karpenter, and define a NodePool that allows both `spot` and `on-demand` for `karpenter.sh/capacity-type`, permits a broad set of instance families and sizes, and turns on consolidation.
- B. Create a separate Spot managed node group for each instance type, and configure the Cluster Autoscaler priority expander to fall back to the On-Demand node groups.
- C. Buy EC2 Instance Savings Plans for the m5 family that cover the current node count, and keep the existing node groups and Cluster Autoscaler.
- D. Turn on Karpenter interruption handling with the SQS interruption queue that receives EC2 Spot interruption and rebalance events from Amazon EventBridge, and define PodDisruptionBudgets for every service.
- E. Restrict the Karpenter NodePool to the single cheapest Spot instance type in one Availability Zone to get the highest discount.

### Q7
A logistics company runs a customer-facing API on Amazon ECS with AWS Fargate behind an Application Load Balancer, using the rolling update deployment type. Last month a release with a latency regression passed its container health checks and caused a 20-minute partial outage before engineers rolled it back by hand. The company now requires: QA must test each new version on a separate port before it gets production traffic; production traffic must shift 10% first and the rest 15 minutes later; and the deployment must roll back automatically if a 5XX-rate or p99-latency CloudWatch alarm fires. The company wants the least custom code.

Which solution meets these requirements?

- A. Turn on the ECS deployment circuit breaker with rollback for the rolling update, and lower the minimum healthy percent so that new tasks replace old tasks faster.
- B. Run two ECS services behind weighted target groups, and have a scheduled Lambda function shift the weights and query CloudWatch metrics to decide whether to revert.
- C. Switch the service to the CodeDeploy blue/green deployment type with an ALB production listener and test listener, use `CodeDeployDefault.ECSCanary10Percent15Minutes`, and add the two CloudWatch alarms to the deployment group with automatic rollback on alarm.
- D. Run the new version behind a second ALB, shift 10% of traffic with Amazon Route 53 weighted records, and add a manual approval step in AWS CodePipeline before the shift to 100%.

### Q8
A B2B SaaS provider is migrating 60 tenant databases from on-premises PostgreSQL servers to AWS. Usage per tenant is unpredictable: some databases sit idle for days, and others jump 20-fold during business hours in different time zones. The on-premises servers are sized for peak, so they are idle most of the time. The new platform must stay PostgreSQL-compatible and be highly available across Availability Zones. Capacity must scale in seconds without dropping connections. A separate set of development databases is unused at night and on weekends, and a few seconds of resume delay is acceptable for them. The company wants to minimize cost.

Which target architecture best meets these requirements?

- A. Amazon Aurora PostgreSQL clusters that use Aurora Serverless v2 for the writer and a reader in promotion tier 0 or 1, with a per-cluster ACU range. Set minimum capacity to 0 ACUs (auto-pause) for the development clusters.
- B. Amazon RDS for PostgreSQL Multi-AZ DB instances with storage autoscaling, plus scheduled Lambda functions that change the DB instance class before and after each tenant's business hours.
- C. Aurora PostgreSQL provisioned clusters sized for each tenant's average load, with Aurora Auto Scaling adding or removing read replicas based on CPU utilization.
- D. Aurora Serverless v1 clusters with auto-pause turned on for every tenant, so that idle tenants scale to zero and busy tenants scale at the next scaling point.

### Q9 (Select TWO)
A startup is building a new mobile video-sharing app. Users sign up with email and password or with Sign in with Apple. Users upload videos of up to 2 GB straight from the device to an Amazon S3 bucket, and the uploads must not pass through the company's backend. Each user may read and write objects only under their own prefix in the bucket. No long-term AWS credentials may be stored on devices. The company wants as little backend code as possible.

Which combination of steps meets these requirements? **(Select TWO.)**

- A. Create one IAM user for the app, embed its access key in the mobile binary, and use the bucket policy to limit that user to the `uploads/` prefix.
- B. Build an Amazon API Gateway REST API with a Lambda proxy integration that accepts the video in the request body and writes it to S3 with the function's role.
- C. Create an Amazon Cognito user pool for sign-up and sign-in, and add Sign in with Apple to the user pool as a social identity provider.
- D. Create an Amazon Cognito identity pool and give its unauthenticated role `s3:PutObject` and `s3:GetObject` on the whole bucket.
- E. Create an Amazon Cognito identity pool that trusts the user pool, and give its authenticated role `s3:PutObject` and `s3:GetObject` on `arn:aws:s3:::bucket/${cognito-identity.amazonaws.com:sub}/*`, plus `s3:ListBucket` with an `s3:prefix` condition on the same variable.

### Q10
A news publisher serves about 8 billion requests a month through an Amazon CloudFront distribution with S3 and ALB origins. A Lambda@Edge function on the viewer request event does four things: normalizes the `Accept-Language` header, redirects some countries to localized paths, adds a `True-Client-IP` header, and validates an HMAC-signed JWT on premium paths. The function makes no network calls and finishes in under a millisecond, yet Lambda@Edge is now a large share of the CDN bill. The security team rotates the HMAC key monthly and does not want it hard-coded in function code. Cached premium content must never be served without a valid token.

What should the solutions architect do to reduce cost while meeting these requirements?

- A. Move the existing Lambda@Edge function to the origin request event so that it runs only on cache misses, which cuts invocations by more than 90%.
- B. Remove the edge function, turn on Lambda as an ALB target, and do the header normalization, redirects, and JWT validation in the origin application.
- C. Rewrite the logic as a CloudFront Function on the viewer request event, and have the function call AWS Secrets Manager at runtime to fetch the current HMAC key.
- D. Rewrite the logic as a CloudFront Function (JavaScript runtime 2.0) on the viewer request event, store the HMAC key in a CloudFront KeyValueStore associated with the function, and update the key there when it rotates.

### Q11
A game studio is launching a real-time multiplayer shooter. Game traffic is UDP. Game servers run on EC2 instances behind Network Load Balancers in us-east-1, eu-west-1, and ap-northeast-1. Several console platform partners and ISPs need a small, fixed set of IP addresses to allowlist. If a Region becomes unhealthy, new player connections must move to the next-closest healthy Region within seconds, not at the speed of DNS TTL expiry. The studio also wants less jitter for players far from a Region.

Which solution meets these requirements?

- A. Use Amazon Route 53 latency-based routing with health checks on each NLB, set a 60-second TTL, and publish the NLB IP addresses to partners for allowlisting.
- B. Use an AWS Global Accelerator standard accelerator with a UDP listener and one endpoint group per Region that contains the NLB, rely on endpoint health checks for failover, and use traffic dials for planned maintenance.
- C. Create an Amazon CloudFront distribution with the three NLBs as origins in an origin group with failover, and give partners the CloudFront IP ranges.
- D. Use an AWS Global Accelerator custom routing accelerator that maps each player to a specific EC2 instance and port in a VPC subnet, so that session placement is deterministic.

### Q12
A documentary producer is building a new ingest platform. Film crews on several continents upload raw footage files of 20–200 GB each to a single Amazon S3 bucket in us-east-1. Long-distance uploads over the public internet are slow, and they often fail partway through, forcing crews to restart from the beginning. The crews use a laptop uploader built on the AWS SDK. The company wants faster, restartable uploads, the least new infrastructure, and no storage cost from abandoned uploads.

Which solution meets these requirements?

- A. Turn on S3 Transfer Acceleration for the bucket and point the uploader at the accelerate endpoint. Use multipart upload with parallel part uploads and per-part retries, and add a lifecycle rule that aborts incomplete multipart uploads after 7 days.
- B. Put an Amazon CloudFront distribution in front of the bucket with PUT allowed and origin access control, and have the uploader send each file as a single PUT request through the distribution.
- C. Create a bucket in each continent for single PUT uploads, and use S3 Cross-Region Replication to copy every object to the us-east-1 bucket.
- D. Deploy an AWS Transfer Family SFTP server in us-east-1 backed by the bucket, and have crews upload with a standard SFTP client that resumes interrupted transfers.

### Q13
A genomics institute is migrating an on-premises HPC cluster that uses a Lustre parallel file system. The 400 TB of input data already lives in an Amazon S3 data lake. Jobs run in bursts of 2–3 days on thousands of EC2 cores and need sub-millisecond latency and hundreds of GB/s of aggregate throughput. Results must end up back in S3. Between bursts, which can be weeks apart, the institute wants to pay nothing for high-performance storage.

Which solution meets these requirements?

- A. Mount an Amazon EFS file system with Elastic throughput on every compute node, and use AWS DataSync to copy the input data from S3 into EFS before each burst.
- B. Install Mountpoint for Amazon S3 on every compute node, and have jobs read and write the data lake prefixes directly as a local file system.
- C. For each burst, create an Amazon FSx for Lustre file system linked to the S3 prefix through a data repository association so that metadata is imported and file data is lazy-loaded on first read. Export results to S3, then delete the file system.
- D. Attach large io2 Block Express EBS volumes with Multi-Attach to the compute instances, and copy the input data from S3 to the volumes before each burst.

### Q14 (Select THREE)
An online retailer runs its storefront in us-east-1: an Application Load Balancer, an EC2 Auto Scaling group, and an Amazon Aurora MySQL cluster. DR today is nightly snapshot copies to us-west-2 with an 8-hour RTO. After an outage, the board now requires an RTO of 15 minutes and an RPO under 1 minute for a Regional failure. The cost must stay well below a full active-active deployment. The solutions architect proposes a warm standby strategy.

Which THREE actions implement this strategy? **(Select THREE.)**

- A. Convert the database to an Aurora global database with a secondary cluster in us-west-2, and fail over to the secondary cluster during a Regional outage.
- B. Use AWS Backup to copy Aurora snapshots to us-west-2 every night, and restore the latest snapshot into a new cluster when a disaster is declared.
- C. Deploy the full application stack in us-west-2, including an ALB and an Auto Scaling group that runs a small number of instances, and scale the group out to production size during failover.
- D. Store AMIs and launch templates in us-west-2 with an Auto Scaling group desired capacity of 0, and create the ALB in us-west-2 only after a disaster is declared.
- E. Use Route 53 latency-based routing to send each Region about half of production traffic all the time, so that both Regions are always serving users.
- F. Create Route 53 failover records: a primary record for the us-east-1 ALB with a health check, and a secondary record for the us-west-2 ALB.

### Q15
A bank runs a payments application active/passive in us-east-1 and us-west-2. The application is managed from a central resilience account in AWS Organizations. Regulators require that a Regional failover is always a deliberate operator decision and never triggered automatically by flapping health checks. The failover action must still work if control-plane APIs in either Region are impaired. A safeguard must stop operators from accidentally turning both Regions off at once.

Which solution meets these requirements?

- A. Use Route 53 failover records with health checks on each ALB, and have operators invert a health check in the Route 53 console during an incident to force failover.
- B. Deploy a Lambda function in us-west-2 that calls the Route 53 `ChangeResourceRecordSets` API to repoint the application record when an operator runs the failover runbook.
- C. Put an AWS Global Accelerator in front of both Regions, and have operators set the us-east-1 endpoint group's traffic dial to 0% to fail over.
- D. Create Amazon Application Recovery Controller (ARC) routing controls in a cluster, attach routing control health checks to Route 53 failover records, and add an assertion safety rule that at least one routing control is On. Operators change state with the ARC data plane API through any of the cluster's five Regional endpoints.

### Q16
A healthcare company runs an application in eu-west-1 with DR in eu-central-1. The database is an Aurora PostgreSQL global database. The application's database credentials are stored in AWS Secrets Manager in eu-west-1. Security policy requires automatic rotation every 30 days with no failed logins during rotation. Applications in eu-central-1 must be able to get the current credentials even if eu-west-1 is unavailable. The company wants the least custom code and the fewest moving parts.

Which solution meets these requirements?

- A. Turn on the RDS-managed master user password integration with Secrets Manager on the global database's primary cluster, replicate that managed secret to eu-central-1, and have applications use the master user.
- B. Configure rotation on the primary secret with a Secrets Manager rotation function that uses the alternating-users strategy. Replicate the secret to eu-central-1 as a replica secret encrypted with a KMS key in that Region, and have the DR applications read the local replica.
- C. Create independent secrets in each Region for the same database user, each with its own rotation function on the same 30-day schedule, and have each Region's applications read the local secret.
- D. Replicate the secret to eu-central-1, and turn on rotation separately for the primary and the replica so that each Region keeps rotating even if the other Region is down.

### Q17 (Select TWO)
A retail group runs 40 AWS accounts in AWS Organizations, with public applications on Amazon CloudFront and Application Load Balancers. Last week an HTTP flood from roughly 10,000 botnet IP addresses hit several applications, along with credential stuffing against `/login`. The CISO requires all of the following: automatic layer 7 DDoS mitigation, 24/7 access to AWS DDoS response experts, protection from scaling charges caused by attacks, the same baseline protections in every current and future account, and a limit of 100 requests per 5 minutes per client IP on `/login`. The company has Enterprise Support.

Which combination of actions meets these requirements? **(Select TWO.)**

- A. Rely on AWS Shield Standard, which is turned on automatically for CloudFront and ALBs, and ask AWS Support for help during each attack.
- B. Subscribe to AWS Shield Advanced, protect the CloudFront distributions and ALBs, turn on automatic application layer DDoS mitigation, and associate Route 53 health checks for health-based detection and proactive engagement.
- C. Add network ACL deny rules to the ALB subnets, using a Lambda function that parses VPC Flow Logs every minute and blocks the noisiest source IP addresses.
- D. From a Firewall Manager delegated administrator account, deploy an AWS WAF policy to all accounts with AWS managed rule groups and a rate-based rule (300-second window, limit 100, IP aggregation, scope-down on URI path `/login`), plus a Shield Advanced policy that protects new resources automatically.
- E. In each account, have the application team manually create a web ACL with a rate-based rule for `/login`, and review the rules every quarter for consistency.

### Q18
A B2B SaaS company is designing tenant isolation for a new platform. Its 30 enterprise tenants are contractually entitled to dedicated infrastructure, their own KMS keys, and a blast radius separate from other tenants. Its roughly 5,000 small-business tenants are cost-sensitive and share infrastructure. Tenant data is stored in DynamoDB with the tenant ID as the partition key. Security requires that a bug in application code must not let one pooled tenant read another tenant's items. The platform team wants to keep the number of IAM roles small.

Which design meets these requirements?

- A. Pool all tenants in shared DynamoDB tables and enforce isolation in application code by adding a tenant ID filter to every query, with code reviews and automated tests to catch mistakes.
- B. Give every tenant, including all 5,000 small-business tenants, a dedicated AWS account created through AWS Control Tower Account Factory, with a full stack deployed per account.
- C. Create one IAM role per small-business tenant, each with a policy that hard-codes that tenant's partition key value, and have the application assume the matching role on every request.
- D. Use a bridge model. Give enterprise tenants silo accounts in a tenant OU, each with its own KMS key. Pool the small-business tenants in shared tables, where services assume one shared role with a `TenantID` session tag, and the role's policy restricts `dynamodb:LeadingKeys` to `${aws:PrincipalTag/TenantID}`.

### Q19 (Select TWO)
An enterprise keeps its data lake in a central data account: Amazon S3 storage plus the AWS Glue Data Catalog. Analysts in a Marketing account and a Finance account query it with Amazon Athena. Marketing must never see the PII columns (`email`, `phone`, `dob`) of the `customers` table, and may see only rows where `region = 'EU'`. Finance can see all columns and rows. The governance team wants permissions managed centrally and able to scale to hundreds of tables, no copies of the data, and no per-consumer S3 bucket policies.

Which combination of actions meets these requirements? **(Select TWO.)**

- A. Run a nightly AWS Glue ETL job that writes a copy of `customers` without PII columns to a separate bucket, and grant Marketing access to it through a bucket policy.
- B. In the data account, register the S3 locations with AWS Lake Formation, tag columns with LF-Tags (for example `sensitivity=pii|public`), grant Marketing cross-account access through LF-Tag-based access control limited to `public` columns, and add a data filter with a row filter for `region = 'EU'`.
- C. In each consumer account, have the data lake administrator accept the AWS RAM share if needed, create resource links to the shared databases or tables, and grant Lake Formation permissions to the analyst roles that Athena uses.
- D. Write S3 bucket policies in the data account that give the Marketing account `s3:GetObject` only on the object prefixes that don't contain PII columns.
- E. Create Athena workgroups in the data account and attach IAM policies to Marketing's roles that deny `SELECT` on the PII column names.

### Q20
A retailer is modernizing an on-premises clickstream pipeline in which Flume agents write JSON logs to HDFS and nightly Hive jobs produce reports. The new design must make clickstream data queryable in Amazon Athena within about 5 minutes, at the lowest possible scan cost per query. A new real-time fraud-detection consumer must read the same events with sub-second latency and be able to replay the last 7 days after a bug fix. The company wants managed services with the least operational overhead.

Which solution meets these requirements?

- A. Have producers write to Amazon Kinesis Data Streams in on-demand mode with retention extended to 7 days, and attach the fraud consumer through enhanced fan-out. Add an Amazon Data Firehose stream with the Kinesis stream as its source that converts JSON to Apache Parquet using a Glue Data Catalog schema and delivers date-partitioned objects to S3 for Athena.
- B. Have producers write directly to an Amazon Data Firehose stream that delivers GZIP-compressed JSON to S3, and have the fraud consumer process S3 event notifications for each new object.
- C. Have producers write to Kinesis Data Streams, and have a Lambda consumer write each record to S3 as a separate small JSON object. Run an hourly Glue crawler, and have the fraud consumer read the same stream.
- D. Have producers write to an Amazon MSK provisioned cluster, and run self-managed Kafka Connect workers on EC2 that write Parquet files to S3. Run the fraud consumer as a Kafka consumer group on EC2.

---

## Section 2 — Answer key

| Q | Answer | Domain / Task | Topic |
|---|---|---|---|
| 1 | **B, E** | D2 / 2.6 Cost-optimized new solution | API Gateway + Lambda + DynamoDB on-demand + warm throughput |
| 2 | **C** | D3 / 3.3 Improve performance | DAX vs ElastiCache for DynamoDB |
| 3 | **A** | D2 / 2.4 Reliability | SQS FIFO message groups vs Kinesis partition keys |
| 4 | **D** | D2 / 2.6 Cost | Step Functions Express vs Standard |
| 5 | **B** | D4 / 4.4 Modernization | Step Functions task-token human approval |
| 6 | **A, D** | D3 / 3.5 Cost improvement | EKS + Karpenter + Spot with On-Demand fallback |
| 7 | **C** | D3 / 3.1 Operational excellence | ECS blue/green with CodeDeploy, alarm rollback |
| 8 | **A** | D4 / 4.3 New architecture | Aurora Serverless v2 for SaaS tenants |
| 9 | **C, E** | D2 / 2.3 Security controls | Cognito user pool + identity pool, per-user S3 prefix |
| 10 | **D** | D3 / 3.3 Performance / cost | CloudFront Functions + KeyValueStore vs Lambda@Edge |
| 11 | **B** | D2 / 2.5 Performance | Global Accelerator for UDP gaming |
| 12 | **A** | D2 / 2.5 Performance | S3 multipart + Transfer Acceleration |
| 13 | **C** | D4 / 4.3 New architecture | FSx for Lustre linked to S3 for HPC |
| 14 | **A, C, F** | D3 / 3.4 Improve reliability | Warm standby DR |
| 15 | **D** | D1 / 1.3 Resilient architectures | Route 53 ARC routing controls |
| 16 | **B** | D1 / 1.2 Security controls | Secrets Manager rotation + multi-Region replica |
| 17 | **B, D** | D1 / 1.2 Security controls | WAF rate-based rules + Shield Advanced + Firewall Manager |
| 18 | **D** | D1 / 1.4 Multi-account environment | SaaS silo/pool/bridge + ABAC |
| 19 | **B, C** | D1 / 1.4 Multi-account environment | Lake Formation cross-account column/row security |
| 20 | **A** | D4 / 4.4 Modernization | Kinesis Data Streams → Firehose → Parquet → Athena |

Distribution check (single-answer questions): A ×4, B ×3, C ×3, D ×4.

---

## Section 3 — Detailed solutions

### Q1 — Answer: **B, E**
**Decisive keywords:** "close to zero for most of the week", "50-fold within seconds", "cannot be forecast", "largest on-sales announced a week in advance", "key-value", "no servers or clusters to patch", "lowest cost in idle periods", "no throttled purchases".

**Why B is correct:** API Gateway, Lambda, and DynamoDB on-demand all charge per request, so an idle week costs almost nothing, and there is nothing to patch. On-demand mode instantly serves traffic up to **double the previous peak** on a table, and it is AWS's recommended default for unpredictable workloads. Key-value access by `eventId`/`seatId` is a natural DynamoDB partition/sort-key design.

**Why E is correct:** On-demand has one documented edge case. If traffic goes **above double the previous peak within 30 minutes**, requests can be throttled. AWS recommends **pre-warming** with *warm throughput* (or spreading the growth over 30 minutes). A 50-fold jump for an announced mega on-sale is exactly this case. Because the on-sales are announced, the team can raise warm throughput ahead of time. This is the one bit of "capacity planning" the scenario needs.

**Why the others are wrong:**
- **A:** Fargate tasks and a provisioned Aurora cluster cost money even when idle, and a scaling policy that reacts over minutes can't absorb a 50-fold jump in seconds. Aurora is also not needed for key-value access.
- **C:** Provisioned capacity with auto scaling reacts to CloudWatch metrics over minutes, so sudden spikes are throttled. It is also the wrong model for traffic that is "near zero most of the week".
- **D:** Manual concurrency changes add operational toil and risk, and they do nothing for database throughput. Concurrency set to zero also blocks every request, including non-sale traffic.

**Concept to remember:** On-demand handles up to 2× the previous peak instantly. For known launches above 2×, pre-warm with warm throughput.

**References:**
- https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/on-demand-capacity-mode.html
- https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/warm-throughput.html
- https://docs.aws.amazon.com/lambda/latest/dg/lambda-concurrency.html

---

### Q2 — Answer: **C**
**Decisive keywords:** "DynamoDB", "95% reads", "low microseconds", "already uses the AWS SDK DynamoDB client", "smallest possible code change", "no custom cache-invalidation logic", "a few seconds stale is acceptable".

**Why C is correct:** DAX is an in-memory, **write-through** cache built for DynamoDB. It is API-compatible, so the code change is swapping the client. It delivers microsecond reads for cached items. DAX keeps an **item cache** (for `GetItem`/`BatchGetItem`) and a **query cache** (for `Query`/`Scan`), and writes made through DAX update the item cache automatically. A cluster of at least three nodes across AZs is the recommended HA configuration. Eventually consistent reads are what DAX serves from cache, which matches "a few seconds stale is acceptable".

**Why the others are wrong:**
- **A:** ElastiCache can be just as fast, but you must write the cache-aside and invalidation logic yourself, which breaks two stated constraints. Pick ElastiCache when you cache data from several sources, need rich data structures (sorted sets, pub/sub), or the source isn't DynamoDB.
- **B:** More provisioned capacity prevents throttling but doesn't change DynamoDB's single-digit-millisecond latency. Adaptive capacity handles hot partitions. It doesn't cache.
- **D:** DAX **passes strongly consistent reads (and `TransactGetItems`) through to DynamoDB and does not cache the results**, so this option removes the latency benefit completely.

**Concept to remember:** DAX means microseconds, a drop-in client, write-through, and eventually consistent reads only. Strongly consistent reads bypass the cache.

**References:**
- https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/DAX.html
- https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/DAX.consistency.html

---

### Q3 — Answer: **A**
**Decisive keywords:** "exactly the order they were produced" (per customer), "different customers … in parallel", "producers sometimes retry", "duplicate ledger entry would be a serious compliance incident", "no replay", "least operational overhead".

**Why A is correct:** In SQS FIFO queues, ordering is enforced **per message group ID**. Messages with the same group ID are delivered in strict order, and different groups can be consumed in parallel. Customer ID as the group ID gives exactly the required ordering semantics. The **message deduplication ID** (here, the payment ID) makes producer retries within the 5-minute deduplication interval safe: no duplicates and no reordering. The Lambda event source mapping for FIFO preserves per-group ordering. **High throughput mode** for FIFO raises the per-queue throughput limits to handle peaks of thousands of messages per second. There are no shards to manage.

**Why the others are wrong:**
- **B:** Standard queues give at-least-once, best-effort ordering. Sorting each batch can't fix ordering across batches, and duplicates are still possible.
- **C:** Kinesis keeps order per partition key (and a parallelization factor still keeps per-key ordering), but **Kinesis does not deduplicate producer retries**. A retried `PutRecord` creates a second record, so you would need your own idempotency layer. You also take on shard/capacity management and pay for retention and replay that the scenario says it doesn't need.
- **D:** SNS standard and SQS standard give no ordering or deduplication guarantees. Creating thousands of per-customer queues on the fly is an operational anti-pattern.

**Concept to remember:** For per-entity ordering plus deduplication with no replay, use SQS FIFO with `MessageGroupId` = the entity. Choose Kinesis when you need replay or multiple consumers, and handle idempotency yourself.

**References:**
- https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/FIFO-queues-understanding-logic.html
- https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/high-throughput-fifo.html
- https://docs.aws.amazon.com/streams/latest/dev/key-concepts.html

---

### Q4 — Answer: **D**
**Decisive keywords:** "50,000 … every second", "idempotent", "under 2 seconds", "lowest orchestration cost", "does not need a durable, exactly-once audit history".

**Why D is correct:** **Express Workflows** are designed for high-volume event processing such as IoT ingestion. They run for up to **5 minutes** and are billed by **number of executions, duration, and memory**, not by state transition. They have **no limit on state transition rate**. Asynchronous Express uses **at-least-once** semantics, which is fine because every step is idempotent. Express doesn't keep execution history in Step Functions, so you turn on **CloudWatch Logs** logging for troubleshooting. AWS IoT rules have a Step Functions action that can start executions directly.

**Why the others are wrong:**
- **A:** Standard Workflows are billed **per state transition** and have start-rate and state-transition throttling quotas. At 50,000 executions per second this is costly and quota-bound. You would pay for exactly-once durability and 90-day history that the scenario explicitly doesn't need.
- **B:** Batching into a Distributed Map adds latency and complexity, and you still pay Standard state-transition pricing. Distributed Map is meant for large-scale parallel processing of datasets (for example, millions of S3 objects), not as a cost workaround for event streams.
- **C:** Express Workflows **don't support** the `.waitForTaskToken` (callback) or `.sync` patterns. Only Request Response is supported. A DynamoDB `PutItem` task already returns synchronously anyway.

**Concept to remember:** Express is for high volume, at most 5 minutes, idempotent work, and per-execution pricing. Standard is for workflows up to 1 year, exactly-once execution, callbacks and `.sync`, and auditable history.

**References:**
- https://docs.aws.amazon.com/step-functions/latest/dg/choosing-workflow-type.html
- https://docs.aws.amazon.com/step-functions/latest/dg/connect-to-resource.html
- https://docs.aws.amazon.com/iot/latest/developerguide/stepfunctions-rule-action.html

---

### Q5 — Answer: **B**
**Decisive keywords:** "human adjuster's approval", "up to 10 days", "escalated after 72 hours", "visual, step-by-step record", "click a link in an email", "least custom code and no servers".

**Why B is correct:** This is the textbook **callback (wait-for-task-token)** pattern. A Standard Workflow task with `.waitForTaskToken` passes `$$.Task.Token` to Lambda, which sends the email. Each link calls an API Gateway endpoint whose backend calls **`SendTaskSuccess`** or **`SendTaskFailure`** with the token. The execution pauses at no compute cost until then. A waiting task can wait up to the execution's **one-year** maximum, so 10 days is fine. `TimeoutSeconds` (or `HeartbeatSeconds`) raises `States.Timeout`, which a `Catch` routes to an escalation branch. Standard Workflows give the visual execution history auditors want, retained for 90 days by default, and you can export events or logs for longer retention.

**Why the others are wrong:**
- **A:** Express Workflows run for at most **5 minutes**, so a 10-day wait is impossible. Polling every minute is also wasteful.
- **C:** Activities work, but you must run, scale, and patch a worker fleet that holds tasks open for days. That contradicts "no servers". The callback pattern replaces it.
- **D:** The maximum SQS visibility timeout is **12 hours**, so a 10-day timeout can't be set. A queue also gives no visual workflow history or escalation logic.

**Concept to remember:** For human approval, use a Standard Workflow with `.waitForTaskToken`, `SendTaskSuccess`/`SendTaskFailure`, and a timeout or heartbeat for escalation.

**References:**
- https://docs.aws.amazon.com/step-functions/latest/dg/connect-to-resource.html
- https://docs.aws.amazon.com/step-functions/latest/dg/choosing-workflow-type.html
- https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/sqs-visibility-timeout.html

---

### Q6 — Answer: **A, D**
**Decisive keywords:** "35% utilization", "many node groups sized for different pod shapes", "large cut in compute cost", "tolerate losing individual pods", "must not get stuck in Pending when Spot capacity is short", "fewer node groups".

**Why A is correct:** Karpenter provisions right-sized nodes directly from pending pods' requirements. **One flexible NodePool** replaces dozens of node groups. When a NodePool allows both `spot` and `on-demand` capacity types, Karpenter prefers Spot and **falls back to On-Demand when Spot capacity isn't available**, so pods don't stay Pending. For Spot it uses the **price-capacity-optimized** allocation strategy, and a broad instance-type list deepens the Spot pools it can draw from. **Consolidation** repacks pods onto fewer or cheaper nodes, which directly fixes the 35% utilization.

**Why D is correct:** Spot gives a 2-minute interruption notice. Karpenter's **native interruption handling** reads an **SQS queue fed by EventBridge** (Spot interruption, rebalance recommendation, scheduled maintenance, and instance state-change events). It then cordons and drains the node and launches a replacement **before** the instance is reclaimed. PodDisruptionBudgets keep enough replicas running during drains and consolidation. This is what makes Spot safe for production stateless services.

**Why the others are wrong:**
- **B:** One node group per instance type is exactly the sprawl the team wants to remove, and Cluster Autoscaler doesn't fix poor bin-packing.
- **C:** Savings Plans discount whatever you run, including 65% idle capacity. Instance Savings Plans also lock you into the m5 family, which blocks moving to Graviton or other families. Commit only *after* you right-size.
- **E:** A single instance type in a single AZ maximizes Spot interruption and insufficient-capacity risk. AWS guidance is to keep Karpenter flexible across many types and AZs.

**Concept to remember:** For Spot cost savings without Pending pods: Karpenter, a NodePool with `spot` + `on-demand`, broad instance types, consolidation, and interruption handling through an SQS queue.

**References:**
- https://docs.aws.amazon.com/eks/latest/best-practices/karpenter.html
- https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/spot-best-practices.html
- https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-fleet-allocation-strategy.html

---

### Q7 — Answer: **C**
**Decisive keywords:** "passed its container health checks" (so a health-based check won't catch it), "test on a separate port", "10% first and the rest 15 minutes later", "roll back automatically if … CloudWatch alarm fires", "least custom code".

**Why C is correct:** The CodeDeploy blue/green deployment type for ECS creates a **replacement (green) task set**. It routes the **test listener** to green for validation, and lifecycle-hook Lambda functions can run automated tests. It then shifts production traffic according to the deployment configuration. **`CodeDeployDefault.ECSCanary10Percent15Minutes`** shifts 10% first and the remaining 90% 15 minutes later. CloudWatch alarms attached to the deployment group stop the deployment and **roll back automatically** to the blue task set, which is still running.

**Note:** Amazon ECS now also offers **native ECS blue/green deployments**. They provide bake time, lifecycle hooks (Lambda or pause), test traffic, and alarm-based rollback without CodeDeploy, and the ECS documentation now recommends them for new services. On the exam, either "ECS blue/green with canary/linear traffic shifting and alarm rollback" or the CodeDeploy version is the right *pattern*. Option C is the only listed option that delivers it.

**Why the others are wrong:**
- **A:** The deployment circuit breaker rolls back when **tasks fail to reach steady state** (failing to start or failing health checks). This release *passed* its health checks. A rolling update has no test listener and no 10% canary.
- **B:** This rebuilds CodeDeploy by hand. It's a lot of custom code, and it's fragile.
- **D:** DNS weighting is subject to client and resolver caching, needs a duplicate ALB, and a manual approval is not an automatic alarm-based rollback.

**Concept to remember:** Use a canary/linear blue/green deployment with CloudWatch alarm rollback for regressions that health checks miss. The circuit breaker only catches tasks that can't start or stay healthy.

**References:**
- https://docs.aws.amazon.com/AmazonECS/latest/developerguide/deployment-type-bluegreen.html
- https://docs.aws.amazon.com/AmazonECS/latest/developerguide/deployment-type-blue-green.html
- https://docs.aws.amazon.com/AmazonECS/latest/developerguide/deployment-circuit-breaker.html
- https://docs.aws.amazon.com/codedeploy/latest/userguide/deployment-configurations.html

---

### Q8 — Answer: **A**
**Decisive keywords:** "unpredictable", "idle for days … jump 20-fold", "PostgreSQL-compatible", "highly available across Availability Zones", "scale in seconds without dropping connections", "development … unused at night … a few seconds of resume delay is acceptable", "minimize cost".

**Why A is correct:** Aurora Serverless v2 scales each writer and reader in place in increments as small as **0.5 ACU**. Scaling doesn't wait for a quiet point and doesn't disrupt open connections or transactions. You pay per ACU-second for the capacity you actually use. Readers in **promotion tiers 0–1** track the writer's capacity, so a failover target is always large enough, which gives Multi-AZ HA. Recent engine versions support a **0 ACU minimum (automatic pause and resume)**, which suits dev databases that are idle at night and can accept a short resume delay. The supported range is 0–256 ACUs, depending on engine and platform version.

**Why the others are wrong:**
- **B:** Changing the DB instance class causes downtime (a Multi-AZ failover) and only works on a schedule. It can't handle *unpredictable* 20-fold spikes in seconds.
- **C:** Aurora Auto Scaling adds or removes **read replicas**. It doesn't scale the writer, and adding a replica takes minutes. Sizing for the average under-provisions the peaks.
- **D:** Aurora Serverless v1 is a **deprecated** product with a different architecture. Its scaling waited for a "scaling point", and it lacked the reader-based Multi-AZ design of v2. Don't choose v1 for new designs.

**Concept to remember:** For unpredictable relational load, use Aurora Serverless v2: seconds-level non-disruptive scaling, tier 0/1 readers for HA, and min 0 ACU (auto-pause) for idle environments.

**References:**
- https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/aurora-serverless-v2.how-it-works.html
- https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/aurora-serverless-v2-auto-pause.html

---

### Q9 — Answer: **C, E**
**Decisive keywords:** "email and password or Sign in with Apple", "upload … straight from the device", "must not pass through the company's backend", "only under their own prefix", "no long-term AWS credentials on devices", "as little backend code as possible".

**Why C is correct:** A Cognito **user pool** is the user directory. It handles sign-up, sign-in, MFA, and **federation with social IdPs such as Apple**, and returns JWTs. Authentication is managed with no backend code.

**Why E is correct:** A Cognito **identity pool** exchanges the user-pool token for **temporary AWS credentials** (STS) for an IAM role. The `${cognito-identity.amazonaws.com:sub}` policy variable resolves to each user's **identity ID**, so a single authenticated role grants every user access only to `bucket/<their-identity-id>/*`. The app can then upload directly to S3, using multipart upload for 2 GB files. The role's trust policy must include the `cognito-identity.amazonaws.com:aud` condition (the identity pool ID) and should limit `amr` to `authenticated`.

**Why the others are wrong:**
- **A:** A long-term access key embedded in an app binary can be extracted. It violates the requirement outright and gives every user the same permissions.
- **B:** Sending video through API Gateway and Lambda breaks "must not pass through the backend". It also runs into payload limits (about 10 MB for API Gateway and 6 MB for a synchronous Lambda invocation), so 2 GB uploads aren't possible this way.
- **D:** Unauthenticated (guest) identities with access to the whole bucket allow anonymous users to read and overwrite everyone's content.

**Concept to remember:** User pool = authentication (who you are). Identity pool = AWS credentials (what you can access). Use `${cognito-identity.amazonaws.com:sub}` for per-user S3 prefixes.

**References:**
- https://docs.aws.amazon.com/cognito/latest/developerguide/iam-roles.html
- https://docs.aws.amazon.com/cognito/latest/developerguide/cognito-identity.html
- https://docs.aws.amazon.com/cognito/latest/developerguide/cognito-user-pools-social-idp.html

---

### Q10 — Answer: **D**
**Decisive keywords:** "8 billion requests a month", "viewer request", "header normalization / redirects / add header / JWT validation", "no network calls", "under a millisecond", "Lambda@Edge is now a large share of the CDN bill", "key rotated monthly, not hard-coded", "cached premium content must never be served without a valid token".

**Why D is correct:** CloudFront Functions are built for exactly this list of jobs: **cache-key normalization, header manipulation, URL redirects/rewrites, and request authorization such as validating hashed JWTs**. They run on viewer request and response events with **sub-millisecond** duration, scale to millions of requests per second, and cost much less per invocation than Lambda@Edge. They can read **geolocation headers** for the country redirects. **CloudFront KeyValueStore** (which needs JavaScript runtime 2.0) gives the function a key-value lookup at the edge. You update the HMAC key there without redeploying the function code. Running on **viewer request** means the token is checked on every request, including cache hits.

**Why the others are wrong:**
- **A:** Origin request functions run **only on cache misses**. Cached premium objects would be served to anyone, which is an authorization bypass. Viewer-side auth has to run on viewer request.
- **B:** The JWT check would happen only at the origin, so cached premium content would again be served without validation, and the redirects would add origin round trips.
- **C:** CloudFront Functions have **no network access**, so they can't call Secrets Manager. That's what KeyValueStore is for. If you truly needed network calls, you would keep Lambda@Edge.

**Concept to remember:** For lightweight header, redirect, or JWT work on every request, use CloudFront Functions (+ KeyValueStore). Use Lambda@Edge only when you need network or file access, the request body, longer runtime, or origin events.

**References:**
- https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/edge-functions-choosing.html
- https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/kvs-with-functions.html
- https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/cloudfront-functions.html

---

### Q11 — Answer: **B**
**Decisive keywords:** "UDP", "small, fixed set of IP addresses to allowlist", "next-closest healthy Region within seconds, not at the speed of DNS TTL expiry", "less jitter".

**Why B is correct:** A Global Accelerator **standard accelerator** gives you **two static anycast IPv4 addresses** (four with dual-stack) that never change while the accelerator exists, which solves allowlisting. It supports **TCP and UDP** listeners. Players enter the AWS global network at the nearest edge location, which reduces jitter and packet loss. GA **health-checks endpoints continuously** and sends new connections to the next healthy endpoint group without any DNS change. **Traffic dials** drain a Region for maintenance. Note that the UDP idle timeout is 30 seconds, so existing flows stay on their endpoint until they time out.

**Why the others are wrong:**
- **A:** Failover depends on DNS TTLs and resolver caching. Also, NLB IP addresses change if you rebuild or add Regions, so you would have to update partners' allowlists.
- **C:** CloudFront is an HTTP(S)/WebSocket CDN. It doesn't proxy arbitrary UDP game traffic.
- **D:** Custom routing accelerators map users to specific instance/port destinations deterministically. **They don't use health checks and don't fail over.** That fails the "move to the next-closest healthy Region" requirement.

**Concept to remember:** Non-HTTP (UDP/TCP) traffic + static IPs + fast health-based failover = Global Accelerator standard accelerator. If HTTP caching is needed, use CloudFront.

**References:**
- https://docs.aws.amazon.com/global-accelerator/latest/dg/introduction-how-it-works.html
- https://docs.aws.amazon.com/global-accelerator/latest/dg/about-endpoint-groups-traffic-dial.html

---

### Q12 — Answer: **A**
**Decisive keywords:** "several continents", "20–200 GB", "single bucket in us-east-1", "fail partway through … restart from the beginning", "AWS SDK uploader", "least new infrastructure", "no storage cost from abandoned uploads".

**Why A is correct:** **Transfer Acceleration** sends uploads to the nearest CloudFront edge location, and from there over the AWS backbone to the bucket's Region. This is designed for long-distance transfers into one bucket and only needs a bucket setting plus an endpoint change. **Multipart upload** splits each file into parts (up to 10,000 parts of 5 MiB–5 GiB each) that upload in parallel and retry individually, so a network blip costs one part, not the whole file. Multipart is *required* here anyway, because a single PUT is limited to 5 GB. A lifecycle rule with **`AbortIncompleteMultipartUpload`** removes orphaned parts, which are otherwise billed as storage.

**Why the others are wrong:**
- **B:** A single PUT can't exceed 5 GB, so 20–200 GB files fail. There is also no part-level restart.
- **C:** This adds buckets in several Regions, plus replication cost and lag, and single PUTs still can't carry files over 5 GB.
- **D:** Transfer Family is a managed SFTP/FTPS/FTP endpoint for partners that need those protocols. It doesn't accelerate long-haul transfers or parallelize parts, and it adds per-hour endpoint cost.

**Concept to remember:** Large files over long distances to one bucket = multipart (parallel parts, per-part retry) + Transfer Acceleration + a lifecycle rule to abort incomplete uploads.

**References:**
- https://docs.aws.amazon.com/AmazonS3/latest/userguide/qfacts.html
- https://docs.aws.amazon.com/AmazonS3/latest/userguide/mpuoverview.html
- https://docs.aws.amazon.com/AmazonS3/latest/userguide/transfer-acceleration.html
- https://docs.aws.amazon.com/AmazonS3/latest/userguide/mpu-abort-incomplete-mpu-lifecycle-config.html

---

### Q13 — Answer: **C**
**Decisive keywords:** "Lustre parallel file system", "data already lives in S3", "thousands of cores", "sub-millisecond latency, hundreds of GB/s", "results … back in S3", "pay nothing for high-performance storage between bursts".

**Why C is correct:** FSx for Lustre is the managed version of the file system the institute already uses. It delivers sub-millisecond latency and throughput that scales to hundreds of GB/s. A **data repository association (DRA)** links a file-system directory to an S3 bucket or prefix. Metadata is imported, file contents are **lazy-loaded on first access**, and new or changed files can be **exported to S3** automatically or with export tasks. Because S3 stays the system of record, the file system can be created for each burst and deleted afterwards, so there is no cost between bursts. (DRAs aren't available on Lustre 2.10 or Scratch 1 file systems. Choose a current deployment type: Scratch 2 for short-lived bursts, Persistent 2 if the file system must survive longer or needs HA.)

**Why the others are wrong:**
- **A:** EFS is a general-purpose NFS file system. It isn't designed for HPC parallel I/O at this scale and latency, and copying 400 TB in with DataSync before each burst wastes days.
- **B:** Mountpoint for Amazon S3 is good for high-throughput sequential reads of large objects, but it doesn't provide full POSIX semantics (for example, in-place edits or renames) or the latency and metadata performance that tightly coupled HPC jobs expect.
- **D:** EBS Multi-Attach works only for io1/io2 volumes in a **single AZ**, for a **limited number of Nitro instances**, and needs a cluster-aware file system. It can't serve thousands of cores. Copying 400 TB is also slow.

**Concept to remember:** HPC + S3 data lake = FSx for Lustre linked to S3 (DRA with lazy load and export). Create it for the burst, delete it afterwards.

**References:**
- https://docs.aws.amazon.com/fsx/latest/LustreGuide/create-dra-linked-data-repo.html
- https://docs.aws.amazon.com/fsx/latest/LustreGuide/what-is.html
- https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ebs-volumes-multi.html

---

### Q14 — Answer: **A, C, F**
**Decisive keywords:** "RTO of 15 minutes", "RPO under 1 minute", "well below a full active-active deployment", "warm standby".

**Why A is correct:** An Aurora global database replicates at the storage layer to the secondary Region with **lag typically under one second**, which meets the RPO. A managed cross-Region **failover** (or switchover for planned events) promotes the secondary to primary in minutes.

**Why C is correct:** **Warm standby** means a *scaled-down but fully functional* copy of production is always running in the DR Region. That includes the ALB and an ASG with a small number of instances, so it can be tested continuously and only needs to **scale out** during failover. That is what makes a 15-minute RTO achievable.

**Why F is correct:** Route 53 **failover routing** with a health check on the primary sends traffic to the secondary ALB when the primary is unhealthy. This uses the Route 53 data plane (health checks and DNS answers), not control-plane changes. Keep TTLs low (60–120 seconds).

**Why the others are wrong:**
- **B:** Nightly snapshot copies give an RPO of up to 24 hours, and restoring a large cluster takes too long for a 15-minute RTO. This is the backup-and-restore strategy they are moving away from.
- **D:** No running instances and no ALB until a disaster is declared is **pilot light**, not warm standby. Creating infrastructure during the incident adds risk and time.
- **E:** Serving production from both Regions all the time is **active-active (multi-site)**. That breaks the cost constraint and needs a multi-writer data design.

**Concept to remember:** Warm standby = scaled-down live stack + continuous data replication (Aurora Global Database) + DNS failover + scale out on failover. Pilot light = data replicated with the core off or idle. Multi-site = full active-active.

**References:**
- https://docs.aws.amazon.com/whitepapers/latest/disaster-recovery-workloads-on-aws/disaster-recovery-options-in-the-cloud.html
- https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/aurora-global-database.html
- https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/dns-failover-configuring.html

---

### Q15 — Answer: **D**
**Decisive keywords:** "deliberate operator decision … never triggered automatically by flapping health checks", "must still work if control-plane APIs in either Region are impaired", "stop operators from accidentally turning both Regions off".

**Why D is correct:** ARC **routing controls** are on/off switches hosted on a **cluster: a highly reliable data plane with endpoints in five AWS Regions**. Each routing control drives a **routing control health check** attached to Route 53 failover records, so flipping a switch changes DNS answers through the Route 53 data plane. Failover happens only when an operator changes state. AWS best practice is to use the **data plane API (`UpdateRoutingControlState`)** against any of the five Regional cluster endpoints, not the console, with retries across endpoints. **Safety rules** prevent dangerous states. An **assertion rule** such as "at least one routing control On" stops both Regions from being switched off, and gating rules act as a master switch.

**Why the others are wrong:**
- **A:** Health-check-driven failover is automatic and can flap. Editing health checks is a Route 53 control-plane action, which isn't the most resilient path during an incident.
- **B:** `ChangeResourceRecordSets` is a Route 53 **control-plane** API (hosted in us-east-1). Recovery that depends on a control plane is exactly what the scenario forbids.
- **C:** Traffic dials work, but changing them is a Global Accelerator **control-plane** call (the GA configuration API is served from the US West (Oregon) Region). It also has no safety rules to stop both endpoint groups being dialed to 0%.

**Emerging / SAP-C03 preview (not core):** ARC also offers **Region switch** plans to orchestrate multi-Region recovery steps, and **zonal shift** for AZ-level evacuation. Know that they exist, but routing controls are the classic SAP-C02 answer for "operator-controlled, data-plane-only multi-Region failover".

**Concept to remember:** For deliberate multi-Region failover that relies on the data plane only, use ARC routing controls (five-Region cluster) with safety rules, operated through the data plane API.

**References:**
- https://docs.aws.amazon.com/r53recovery/latest/dg/routing-control.html
- https://docs.aws.amazon.com/r53recovery/latest/dg/route53-arc-best-practices.regional.html
- https://docs.aws.amazon.com/r53recovery/latest/dg/routing-control.safety-rules.html

---

### Q16 — Answer: **B**
**Decisive keywords:** "Aurora PostgreSQL global database", "automatic rotation every 30 days", "no failed logins during rotation", "current credentials even if eu-west-1 is unavailable", "least custom code … fewest moving parts".

**Why B is correct:** **Replica secrets** copy the encrypted secret value and metadata to other Regions, encrypted with a KMS key in each replica Region. **Rotation is configured on the primary secret, and each new value propagates to all replicas automatically.** You don't manage rotation per replica. DR applications read the local replica, which keeps working during an eu-west-1 outage, and a replica can be **promoted to a standalone secret** if needed. The **alternating-users** strategy keeps two valid database users and rotates them in turn. AWS describes it as suited to applications that need high availability, because an application that fetches the secret mid-rotation still gets valid credentials. Because database users replicate through the global database, the single rotated secret is correct in both Regions.

**Why the others are wrong:**
- **A:** AWS documents that **Secrets Manager integration (RDS-managed master user password) isn't supported for Aurora Global Database**. You must turn it off before adding a Region. Applications also shouldn't use the master user (least privilege).
- **C:** Two independent rotations of the *same* database user overwrite each other's password, because the user lives in one replicated database. Credentials go out of sync and logins fail.
- **D:** Replicas aren't rotated independently. Rotation runs on the primary and replicates. Any design that rotates in two places again fights over one password.

**Concept to remember:** For multi-Region secrets, rotate once on the primary and replicate to read-only replicas. Use the alternating-users strategy for zero-downtime rotation.

**References:**
- https://docs.aws.amazon.com/secretsmanager/latest/userguide/create-manage-multi-region-secrets.html
- https://docs.aws.amazon.com/secretsmanager/latest/userguide/rotation-strategy.html
- https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/aurora-global-database.html

---

### Q17 — Answer: **B, D**
**Decisive keywords:** "40 AWS accounts", "automatic layer 7 DDoS mitigation", "24/7 access to AWS DDoS response experts", "protection from scaling charges", "same baseline protections in every current and future account", "100 requests per 5 minutes per client IP on `/login`", "Enterprise Support".

**Why B is correct:** **Shield Advanced** adds: **automatic application layer DDoS mitigation**, where Shield creates and manages WAF rules in your web ACL during an attack; **health-based detection** using Route 53 health checks, which is required for **proactive engagement**; **24/7 Shield Response Team (SRT)** access, which requires Business or Enterprise Support (they have it); and **cost protection** in the form of service credits for attack-related scaling spikes. Standard WAF fees for protected resources are covered by the subscription.

**Why D is correct:** **Firewall Manager** (which needs Organizations, AWS Config, and an administrator account) deploys **WAF policies and Shield Advanced protection policies** across all accounts and applies them **automatically to new accounts and resources**. That meets the consistency requirement. A **rate-based rule** with a **300-second evaluation window** (valid windows are 60, 120, 300, and 600 seconds; the minimum limit is 10), a limit of 100, IP aggregation, and a **scope-down statement** on `/login` implements the credential-stuffing limit exactly. AWS managed rule groups (IP reputation, known bad inputs, and so on) provide the baseline.

**Why the others are wrong:**
- **A:** Shield Standard protects against common **layer 3/4** attacks at no cost. It has no automatic L7 mitigation, no SRT, and no cost protection.
- **C:** NACLs are limited in rule count, are stateless, don't protect CloudFront, and a log-parsing Lambda function is slow and fragile against 10,000 rotating IP addresses.
- **E:** Manual web ACLs in 40 accounts can't guarantee consistency or cover future accounts. That's exactly the gap Firewall Manager closes.

**Concept to remember:** For DDoS protection across many accounts: Shield Advanced (L7 auto-mitigation, SRT, cost protection) + Firewall Manager (org-wide WAF and Shield policies) + WAF rate-based rules with scope-down.

**References:**
- https://docs.aws.amazon.com/waf/latest/developerguide/ddos-advanced-summary-capabilities.html
- https://docs.aws.amazon.com/waf/latest/developerguide/waf-rule-statement-type-rate-based-high-level-settings.html
- https://docs.aws.amazon.com/waf/latest/developerguide/fms-chapter.html

---

### Q18 — Answer: **D**
**Decisive keywords:** "contractually entitled to dedicated infrastructure, own KMS keys, separate blast radius" (enterprise tenants), "cost-sensitive and share infrastructure" (small-business tenants), "tenant ID as the partition key", "a bug in application code must not let one pooled tenant read another", "keep the number of IAM roles small".

**Why D is correct:** The **bridge (hybrid) model** combines both isolation models. **Silo** (an account per tenant in a dedicated OU) gives enterprise tenants dedicated infrastructure, per-tenant KMS keys, and account-level blast-radius isolation. **Pool** serves the long tail cheaply. In the pool, **ABAC** enforces isolation *outside* application logic. A service assumes **one** shared role and passes the tenant ID as a **session tag**, and the policy condition `dynamodb:LeadingKeys` = `${aws:PrincipalTag/TenantID}` lets the credentials touch only items whose partition key matches. Even buggy code can't read another tenant's items, and the role count stays at one instead of 5,000.

**Why the others are wrong:**
- **A:** Isolation that relies only on application code is exactly what security has ruled out. One missed filter leaks data.
- **B:** 5,000 accounts with full stacks is very expensive and operationally heavy for cost-sensitive tenants. Silo-for-all ignores the tiering.
- **C:** One role per tenant hits IAM role quotas and becomes unmanageable. ABAC with session tags achieves the same isolation with a single role.

**Concept to remember:** SaaS isolation: silo for premium tenants, pool for the long tail (bridge = both). Enforce pooled isolation with ABAC session tags + `dynamodb:LeadingKeys`.

**References:**
- https://docs.aws.amazon.com/wellarchitected/latest/saas-lens/saas-lens.html
- https://docs.aws.amazon.com/whitepapers/latest/saas-tenant-isolation-strategies/saas-tenant-isolation-strategies.html
- https://docs.aws.amazon.com/IAM/latest/UserGuide/id_session-tags.html
- https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/specifying-conditions.html

---

### Q19 — Answer: **B, C**
**Decisive keywords:** "central data account", "Athena in other accounts", "must never see the PII columns", "only rows where `region = 'EU'`", "managed centrally and able to scale to hundreds of tables", "no copies", "no per-consumer bucket policies".

**Why B is correct:** **Lake Formation** centralizes fine-grained permissions on Data Catalog resources: database, table, **column**, **row**, and **cell** level, the last two through **data filters**. **LF-Tag-based access control (LF-TBAC)** is AWS's recommended method for sharing at scale. You tag columns once, grant by tag expression, and new tables inherit governance. Cross-account grants are shared through **AWS RAM**. A data filter with a row filter expression restricts Marketing to EU rows. Data isn't copied, and Lake Formation vends temporary credentials to Athena, so there are no bucket policies per consumer.

**Why C is correct:** In each consumer account, the **data lake administrator** accepts the RAM invitation if the account is outside the organization, creates **resource links**, which integrated services such as Athena need in order to query shared tables, and **grants permissions to local principals** (the analyst roles). Cross-account sharing in Lake Formation is a two-step process: producer grants, then consumer re-grants.

**Why the others are wrong:**
- **A:** Copying data is explicitly forbidden, it doubles storage, and it creates sync problems. It also doesn't solve row filtering.
- **D:** S3 policies work on objects and prefixes, not columns or rows inside Parquet/CSV files. Columns can't be removed this way.
- **E:** IAM policies can't express column-level `SELECT` restrictions on Glue tables. Column, row, and cell security comes from Lake Formation, not Athena workgroups.

**Emerging / SAP-C03 preview (not core):** Lake Formation also governs Apache Iceberg tables (including S3 Tables integration). Expect this in future exam versions.

**Concept to remember:** For cross-account column and row security without copies: Lake Formation LF-Tags + data filters → RAM share → consumer resource links + local grants.

**References:**
- https://docs.aws.amazon.com/lake-formation/latest/dg/cross-account-permissions.html
- https://docs.aws.amazon.com/lake-formation/latest/dg/data-filtering.html
- https://docs.aws.amazon.com/lake-formation/latest/dg/tag-based-access-control.html
- https://docs.aws.amazon.com/lake-formation/latest/dg/resource-links-about.html

---

### Q20 — Answer: **A**
**Decisive keywords:** "queryable in Athena within about 5 minutes", "lowest possible scan cost", "real-time fraud consumer … sub-second", "replay the last 7 days", "managed services with the least operational overhead", "modernizing" a Flume/HDFS/Hive pipeline.

**Why A is correct:**
- **Kinesis Data Streams** gives durable, ordered, **replayable** storage. Retention defaults to 24 hours and can be extended up to 365 days, so set it to 7 days. On-demand mode removes shard planning.
- **Enhanced fan-out** gives the fraud consumer dedicated read throughput with sub-second (push-based) latency.
- **Amazon Data Firehose** (formerly Kinesis Data Firehose) reads the same stream. Its **record format conversion** turns JSON into **Apache Parquet** using a schema from the **Glue Data Catalog**. Firehose needs a deserializer, a schema, and a serializer for this; non-JSON input must first be transformed with Lambda.
- Firehose buffers and delivers within minutes, and date partitioning (or dynamic partitioning) lets Athena prune partitions.
- Parquet's columnar format plus partitioning cuts the bytes Athena scans, and so the cost, dramatically.

**Why the others are wrong:**
- **B:** Firehose isn't a replayable stream. The fraud consumer would wait for buffered S3 objects (minutes, not sub-second) and couldn't replay the last 7 days. GZIP JSON also scans far more data than Parquet.
- **C:** One S3 object per record creates the **small-files problem**: huge request costs and slow Athena queries. An hourly crawler misses the 5-minute freshness target, and you maintain custom code.
- **D:** MSK provisioned plus self-managed Kafka Connect and consumers on EC2 is the most operationally heavy option. It's a lift-and-shift of complexity, not modernization with managed services.

**Concept to remember:** For clickstream: KDS (replay + real-time consumers) → Firehose (JSON→Parquet via Glue schema, partitioned) → S3 → Athena.

**References:**
- https://docs.aws.amazon.com/firehose/latest/dev/record-format-conversion.html
- https://docs.aws.amazon.com/firehose/latest/dev/dynamic-partitioning.html
- https://docs.aws.amazon.com/streams/latest/dev/kinesis-extended-retention.html
- https://docs.aws.amazon.com/streams/latest/dev/enhanced-consumers.html
- https://docs.aws.amazon.com/athena/latest/ug/columnar-storage.html

---

## Score interpretation

Count a multi-select question as correct only if every choice is right, as on the real exam.

| Score | What it means | What to do next |
|---|---|---|
| **≥ 16 / 20** | **Ready** for this material at exam level. | Move on to the next paper. Reread "Concept to remember" for anything you guessed. |
| **13–15 / 20** | Close, but you have weak domains. | Group your misses by domain/task (Section 2) and review only the matching chapters below. Then retake the missed questions in 48 hours. |
| **< 13 / 20** | Not ready yet on new-solution design. | Re-study the linked chapters in full, do their end-of-chapter questions, then retake this paper. |

**Where to re-study, by question:**

| If you missed… | Re-study |
|---|---|
| Q1, Q6, Q7, Q8 (serverless/containers, Aurora Serverless v2) | [07 — Compute, Containers & Serverless](../07-Compute-Containers-and-Serverless/07-Compute-Containers-and-Serverless.md) · [09 — Databases & Caching](../09-Databases-and-Caching/09-Databases-and-Caching.md) · [14 — Deployment, DevOps & IaC](../14-Deployment-DevOps-and-IaC/14-Deployment-DevOps-and-IaC.md) · [16 — Cost Optimization & FinOps](../16-Cost-Optimization-and-FinOps/16-Cost-Optimization-and-FinOps.md) |
| Q2, Q8, Q16 (DAX, Aurora, secrets) | [09 — Databases & Caching](../09-Databases-and-Caching/09-Databases-and-Caching.md) · [06 — Security, Data Protection & Threat Detection](../06-Security-Data-Protection-and-Threat-Detection/06-Security-Data-Protection-and-Threat-Detection.md) |
| Q3, Q4, Q5 (SQS FIFO, Kinesis, Step Functions) | [10 — Application Integration & Event-Driven](../10-Application-Integration-and-Event-Driven/10-Application-Integration-and-Event-Driven.md) · [13 — Migration & Modernization](../13-Migration-and-Modernization/13-Migration-and-Modernization.md) |
| Q9, Q18 (Cognito, SaaS tenant isolation, ABAC) | [03 — Identity & Access Management](../03-Identity-and-Access-Management/03-Identity-and-Access-Management.md) · [02 — Multi-Account Governance](../02-Multi-Account-Governance/02-Multi-Account-Governance.md) |
| Q10, Q11, Q17 (CloudFront Functions, Global Accelerator, WAF/Shield) | [05 — Edge, DNS & Content Delivery](../05-Edge-DNS-and-Content-Delivery/05-Edge-DNS-and-Content-Delivery.md) · [06 — Security, Data Protection & Threat Detection](../06-Security-Data-Protection-and-Threat-Detection/06-Security-Data-Protection-and-Threat-Detection.md) · [04 — Networking, VPC & Hybrid Connectivity](../04-Networking-VPC-and-Hybrid-Connectivity/04-Networking-VPC-and-Hybrid-Connectivity.md) |
| Q12, Q13 (S3 uploads, FSx for Lustre) | [08 — Storage & Data Transfer](../08-Storage-and-Data-Transfer/08-Storage-and-Data-Transfer.md) · [13 — Migration & Modernization](../13-Migration-and-Modernization/13-Migration-and-Modernization.md) |
| Q14, Q15 (warm standby, Route 53 ARC) | [12 — Resilience, HA & Disaster Recovery](../12-Resilience-HA-and-Disaster-Recovery/12-Resilience-HA-and-Disaster-Recovery.md) · [05 — Edge, DNS & Content Delivery](../05-Edge-DNS-and-Content-Delivery/05-Edge-DNS-and-Content-Delivery.md) · [15 — Monitoring, Operations & Continuous Improvement](../15-Monitoring-Operations-and-Continuous-Improvement/15-Monitoring-Operations-and-Continuous-Improvement.md) |
| Q19, Q20 (Lake Formation, streaming → Parquet → Athena) | [11 — Analytics, Streaming & AI/ML](../11-Analytics-Streaming-and-AI-ML/11-Analytics-Streaming-and-AI-ML.md) · [02 — Multi-Account Governance](../02-Multi-Account-Governance/02-Multi-Account-Governance.md) |

> [← Practice Papers index](README.md) · [Study Guide index](../00-README-Start-Here.md)

