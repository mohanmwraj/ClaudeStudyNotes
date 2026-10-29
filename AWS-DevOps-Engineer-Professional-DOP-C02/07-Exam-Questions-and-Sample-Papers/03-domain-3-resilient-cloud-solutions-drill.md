# Domain 3 Drill · Resilient Cloud Solutions (20 questions)

Original exam-style questions for tasks 3.1–3.3. The notes for this domain are in [03-Resilient-Cloud-Solutions](../03-Resilient-Cloud-Solutions/).

---

### Q1 · Task 3.1 · Single answer

An order system uses a single-AZ Amazon RDS for PostgreSQL instance. The business requires the database to survive the loss of an Availability Zone automatically, with **no loss of committed transactions** and no change to the application's connection string.

What should the DevOps engineer do?

- **A.** Create a read replica in another AZ and promote it manually when the primary fails.
- **B.** Convert the instance to a Multi-AZ deployment.
- **C.** Take automated snapshots every 5 minutes and restore them in another AZ after a failure.
- **D.** Create a cross-Region read replica and update the connection string during failover.

<details><summary>Answer</summary>

**Answer: B**

**Why (P7, P8):** Multi-AZ replicates **synchronously** to a standby in another AZ and fails over automatically. The endpoint DNS name stays the same, so no committed data is lost.

- **A** — wrong: asynchronous replication (possible data loss) and manual promotion.
- **B** — correct: synchronous, automatic, same endpoint.
- **C** — wrong: snapshots can't be taken every 5 minutes, restores take time, and recent data is lost.
- **D** — wrong: asynchronous, manual, and requires changing the connection string.

**Reference:** <https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/Concepts.MultiAZ.html>

</details>

### Q2 · Task 3.1 · Single answer

A gaming company serves players in North America and Europe from `us-east-1` and `eu-west-1`. Player profile writes must be accepted in **both** Regions with low latency, and either Region must keep working if the other becomes unavailable.

Which data-layer design meets these requirements?

- **A.** Amazon RDS Multi-AZ in `us-east-1` with a cross-Region read replica in `eu-west-1`.
- **B.** Amazon DynamoDB in `us-east-1` with on-demand backups copied to `eu-west-1`.
- **C.** Amazon ElastiCache Global Datastore as the system of record.
- **D.** Amazon DynamoDB global tables with replicas in `us-east-1` and `eu-west-1`.

<details><summary>Answer</summary>

**Answer: D**

**Why (P8):** Global tables are multi-active. Each replica Region accepts writes locally and replicates asynchronously to the others.

- **A** — wrong: only one writer Region; European writes cross the Atlantic, and failover needs promotion.
- **B** — wrong: backups give no live second Region.
- **C** — wrong: a cache isn't a durable system of record, and Global Datastore has a single primary Region for writes.
- **D** — correct: local writes in both Regions, each independent of the other.

**Reference:** <https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/GlobalTables.html>

</details>

### Q3 · Task 3.1 · Single answer

An application runs in private subnets in three Availability Zones and calls external payment APIs. All three private route tables point to a single NAT gateway in the first AZ. During an incident in that AZ, the instances in the other two AZs also lost outbound connectivity.

What should the DevOps engineer do to remove this single point of failure?

- **A.** Create a NAT gateway in a public subnet in each AZ, and point each AZ's private route table at the NAT gateway in the same AZ.
- **B.** Replace the NAT gateway with a larger NAT instance with an Elastic IP address.
- **C.** Add a second Elastic IP address to the existing NAT gateway.
- **D.** Move the instances to public subnets so they no longer need a NAT gateway.

<details><summary>Answer</summary>

**Answer: A**

**Why (P7):** A NAT gateway is a **zonal** resource. AZ independence needs one per AZ, with routing that keeps each AZ's traffic within that AZ.

- **A** — correct: removes the cross-AZ dependency (and the cross-AZ data charges).
- **B** — wrong: still a single instance in one AZ, now self-managed.
- **C** — wrong: more IPs don't change its zonal scope.
- **D** — wrong: exposes the instances and changes the security posture.

**Reference:** <https://docs.aws.amazon.com/vpc/latest/userguide/vpc-nat-gateway.html>

</details>

### Q4 · Task 3.1 · Select TWO

A mobile app downloads large configuration bundles from an S3 bucket in `us-east-1` through an Amazon CloudFront distribution. During a recent S3 issue in that Region, downloads failed even though CloudFront was healthy. The company wants downloads to keep working automatically from a second Region, using the same URL and the LEAST operational effort.

Which combination of steps meets these requirements? (Select TWO.)

- **A.** Create a bucket in `us-west-2` with versioning, enable versioning on the source bucket, and configure S3 Cross-Region Replication from `us-east-1` to `us-west-2`.
- **B.** Write a Lambda function that copies new objects to the second bucket every hour.
- **C.** Add the second bucket as an origin, and create a CloudFront origin group with the `us-east-1` bucket as primary and the `us-west-2` bucket as secondary, failing over on 5xx and 403/404 status codes.
- **D.** Create a Route 53 failover record that points directly to the two S3 bucket endpoints, and update the app to use the new domain.
- **E.** Increase the CloudFront cache TTL to 1 year so that no requests reach S3.

<details><summary>Answer</summary>

**Answer: A, C**

**Why (P7, P12):** CRR keeps a second copy continuously. A CloudFront origin group fails over GET requests to the secondary origin per request, behind the same URL.

- **A** — correct: native, continuous replication (versioning is required on both buckets).
- **B** — wrong: custom code, with an RPO of up to an hour.
- **C** — correct: automatic per-request failover with no client change.
- **D** — wrong: requires an app change, and DNS failover is slower and loses CloudFront's caching.
- **E** — wrong: cache misses and new bundles still fail, and stale configuration becomes a risk.

**Reference:** <https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/high_availability_origin_failover.html>

</details>

### Q5 · Task 3.1 · Single answer

An internal API runs on an internal Application Load Balancer in private subnets in two Regions, with Route 53 failover records in a private hosted zone. The team creates a Route 53 HTTP health check against the primary ALB's private IP address, but the health check always reports unhealthy, even when the API is fine.

What should the DevOps engineer do?

- **A.** Open the ALB's security group to `0.0.0.0/0` so that health checkers can reach it.
- **B.** Lower the health check's failure threshold to 1.
- **C.** Create a CloudWatch alarm on the primary ALB's health metrics (for example `UnHealthyHostCount` or a 5xx rate) and use a CloudWatch alarm-based Route 53 health check for the failover record.
- **D.** Replace the failover records with simple records that list both ALBs.

<details><summary>Answer</summary>

**Answer: C**

**Why (P7):** Route 53 health checkers run on the internet and can't reach private IP addresses. For private resources, health checks are based on CloudWatch alarm state.

- **A** — wrong: the checkers still can't route to a private IP, and this is insecure.
- **B** — wrong: doesn't fix reachability.
- **C** — correct: the documented approach for private endpoints.
- **D** — wrong: simple records can't health-check or fail over per value.

**Reference:** <https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/health-checks-types.html>

</details>

### Q6 · Task 3.1 · Single answer

EC2 instances in an Auto Scaling group sit behind an Application Load Balancer. Sometimes the application process hangs: the ALB marks the instance unhealthy and stops sending traffic, but the instance stays in the group indefinitely, and capacity drops.

What should the DevOps engineer change?

- **A.** Set the Auto Scaling group's health check type to `ELB`, with a suitable health check grace period.
- **B.** Enable detailed monitoring on the instances.
- **C.** Add a scheduled action that replaces all instances every night.
- **D.** Increase the ALB's unhealthy threshold so that instances are marked unhealthy less often.

<details><summary>Answer</summary>

**Answer: A**

**Why (P7):** With the `EC2` health check type, the group only replaces instances that fail EC2 status checks. With `ELB`, load-balancer health failures also cause replacement.

- **A** — correct: self-healing on application health.
- **B** — wrong: changes the metric period. It doesn't replace anything.
- **C** — wrong: hung instances stay out of service for up to a day.
- **D** — wrong: hides the failure instead of healing it.

**Reference:** <https://docs.aws.amazon.com/autoscaling/ec2/userguide/ec2-auto-scaling-health-checks.html>

</details>

### Q7 · Task 3.2 · Single answer

Worker instances in an Auto Scaling group process messages from an SQS queue. Each message takes about 2 seconds, and the business accepts up to 60 seconds of queueing delay. The group currently scales on CPU at 70%, but during surges the queue backlog grows for 30 minutes while CPU stays around 40% (the work is I/O-bound).

How should the DevOps engineer configure scaling?

- **A.** Lower the CPU target to 30%.
- **B.** Add a scheduled action that doubles capacity every morning.
- **C.** Publish a custom "backlog per instance" metric (`ApproximateNumberOfMessagesVisible` ÷ InService instances) and use target tracking with a target of 30 messages per instance.
- **D.** Switch to step scaling on `ApproximateAgeOfOldestMessage` with a single step that adds 1 instance.

<details><summary>Answer</summary>

**Answer: C**

**Why (P9):** Scale on the work waiting. Acceptable backlog per instance = 60 s acceptable latency ÷ 2 s per message = 30.

- **A** — wrong: CPU doesn't track this I/O-bound work.
- **B** — wrong: surges aren't tied to the time of day.
- **C** — correct: the documented SQS scaling pattern.
- **D** — wrong: age is a lagging signal, and one-instance steps respond too slowly to surges.

**Reference:** <https://docs.aws.amazon.com/autoscaling/ec2/userguide/as-using-sqs-queue.html>

</details>

### Q8 · Task 3.2 · Single answer

An application's instances need about 8 minutes to become ready after launch, because they load a large in-memory cache. Traffic surges arrive unpredictably and peak within 2 minutes. Target tracking scaling launches instances, but they arrive too late.

What should the DevOps engineer do to reduce the time to add capacity?

- **A.** Use a larger instance type.
- **B.** Configure a warm pool of pre-initialized (stopped or hibernated) instances for the Auto Scaling group, with a lifecycle hook that warms the cache when instances enter the warm pool.
- **C.** Enable predictive scaling.
- **D.** Increase the default instance warmup so that the group waits longer before scaling again.

<details><summary>Answer</summary>

**Answer: B**

**Why (P7):** Warm pools move the slow initialization **before** the surge. Scale-out then moves a ready instance into service quickly.

- **A** — wrong: doesn't shorten the cache load.
- **B** — correct: removes most of the boot-plus-initialization delay from the scale-out path.
- **C** — wrong: predictive scaling needs recurring patterns. These surges are unpredictable.
- **D** — wrong: slows scaling further.

**Reference:** <https://docs.aws.amazon.com/autoscaling/ec2/userguide/ec2-auto-scaling-warm-pools.html>

</details>

### Q9 · Task 3.2 · Single answer

A Lambda function that processes uploads returns throttling errors (`TooManyRequestsException`) during busy periods. CloudWatch shows that account-level concurrency use never exceeds 300 of the 1,000 available. The function's configuration shows reserved concurrency set to 10.

What should the DevOps engineer do?

- **A.** Request a quota increase for account concurrency.
- **B.** Configure provisioned concurrency of 10 on the function.
- **C.** Increase the function's memory to make each invocation faster.
- **D.** Raise or remove the function's reserved concurrency so it can scale with demand.

<details><summary>Answer</summary>

**Answer: D**

**Why (P9):** Reserved concurrency both reserves **and caps** a function's concurrency. A cap of 10 throttles the 11th concurrent request, whatever the account has free.

- **A** — wrong: the account limit isn't the constraint.
- **B** — wrong: provisioned concurrency addresses cold starts. Concurrency stays capped at 10.
- **C** — wrong: may help slightly, but the cap still throttles bursts.
- **D** — correct: removes the self-imposed ceiling.

**Reference:** <https://docs.aws.amazon.com/lambda/latest/dg/configuration-concurrency.html>

</details>

### Q10 · Task 3.2 · Select TWO

An Amazon ECS service runs on an ECS cluster backed by an Auto Scaling group of EC2 instances. During peaks, the service's desired count is raised by hand, and new tasks stay in `PROVISIONING` because no instance has room. The team wants tasks **and** instances to scale automatically with load.

Which combination of steps meets these requirements? (Select TWO.)

- **A.** Increase the instance type of the Auto Scaling group to the largest size available.
- **B.** Configure ECS service auto scaling with a target tracking policy (for example on average CPU or `ALBRequestCountPerTarget`).
- **C.** Add a scheduled action that sets the desired task count to the expected peak every day.
- **D.** Enable instance scale-in protection on all instances so that tasks are never stopped.
- **E.** Create an Auto Scaling group capacity provider with managed scaling, and use it in the service's capacity provider strategy.

<details><summary>Answer</summary>

**Answer: B, E**

**Why (P7, P12):** Service auto scaling changes the task count. Capacity provider managed scaling grows the instance group to fit the pending tasks.

- **A** — wrong: bigger instances still run out of room, and nothing scales automatically.
- **B** — correct: the task count follows load.
- **C** — wrong: fixed schedules don't follow actual load.
- **D** — wrong: blocks scale-in entirely and doesn't add capacity. Managed termination protection is the targeted version.
- **E** — correct: instance capacity follows task demand.

**Reference:** <https://docs.aws.amazon.com/AmazonECS/latest/developerguide/cluster-auto-scaling.html>

</details>

### Q11 · Task 3.2 · Single answer

A DynamoDB table in on-demand mode stores IoT readings with the device type as the partition key. One device type accounts for 70% of writes, and the table returns throttling errors for that partition key even though overall throughput is far below the table's limits.

What should the DevOps engineer recommend?

- **A.** Change the key design to spread writes, for example by adding a calculated suffix (write sharding) to the partition key, or by using device ID as the key.
- **B.** Switch the table to provisioned capacity with a very high write capacity.
- **C.** Add a DAX cluster in front of the table.
- **D.** Enable DynamoDB global tables to add a second Region.

<details><summary>Answer</summary>

**Answer: A**

**Why (P9):** Throughput per partition is limited, so a hot key can't be fixed by adding table capacity. Writes must be spread across more partition-key values.

- **A** — correct: removes the hot partition.
- **B** — wrong: per-partition limits still apply to one hot key.
- **C** — wrong: DAX caches reads. It doesn't help a write hot spot.
- **D** — wrong: each Region would still have the same hot key, and it adds cost.

**Reference:** <https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/bp-partition-key-sharding.html>

</details>

### Q12 · Task 3.2 · Single answer

A REST API in Amazon API Gateway, backed by Lambda, returns a product catalog that changes at most once an hour. Identical requests make up 90% of traffic and drive heavy load on the downstream database. The team can't change application code this sprint.

What should the DevOps engineer do?

- **A.** Add an ElastiCache cluster and update the Lambda function to read from it.
- **B.** Enable API Gateway caching on the stage, with a TTL of up to 3,600 seconds and cache keys on the relevant query parameters.
- **C.** Increase the Lambda function's reserved concurrency.
- **D.** Add an RDS read replica and point the Lambda function at it.

<details><summary>Answer</summary>

**Answer: B**

**Why (P12):** API Gateway stage caching serves repeated requests without invoking the backend, and it's a configuration change only.

- **A** — wrong: requires code changes.
- **B** — correct: no code change, and it absorbs the identical requests.
- **C** — wrong: increases pressure on the database.
- **D** — wrong: requires code or configuration changes, and still queries the database for every request.

**Reference:** <https://docs.aws.amazon.com/apigateway/latest/developerguide/api-gateway-caching.html>

</details>

### Q13 · Task 3.2 · Single answer

A latency-sensitive API runs on Lambda (Java runtime). Cold starts add up to 2 seconds of latency during the business-hours traffic ramp at 08:00, which violates the 300 ms p99 objective. Overnight traffic is near zero, and the team doesn't want to pay for idle capacity at night.

What should the DevOps engineer do?

- **A.** Increase the function's timeout.
- **B.** Set reserved concurrency to 100.
- **C.** Invoke the function every minute with a scheduled EventBridge rule to keep one instance warm.
- **D.** Configure provisioned concurrency on the function's alias, with Application Auto Scaling scheduled actions that raise it before 08:00 and lower it in the evening.

<details><summary>Answer</summary>

**Answer: D**

**Why (P12):** Provisioned concurrency keeps execution environments initialized, which eliminates cold starts. Scheduled scaling keeps it only when needed.

- **A** — wrong: unrelated to cold starts.
- **B** — wrong: reserved concurrency doesn't pre-initialize anything.
- **C** — wrong: keeps at most one environment warm. A ramp needs many concurrent environments.
- **D** — correct: pre-initialized capacity, scheduled to match demand.

**Reference:** <https://docs.aws.amazon.com/lambda/latest/dg/provisioned-concurrency.html>

</details>

### Q14 · Task 3.3 · Single answer

An internal reporting application (EC2, EBS and RDS) has an RPO of 4 hours and an RTO of 24 hours for a Regional disaster. Management wants the LOWEST-cost DR strategy that meets these targets.

What should the DevOps engineer implement?

- **A.** A warm standby in a second Region with a scaled-down Auto Scaling group and a cross-Region read replica.
- **B.** A multi-site active/active deployment with Route 53 latency routing.
- **C.** AWS Backup plans that back up the EC2/EBS and RDS resources every 4 hours and copy the recovery points to a vault in a second Region, plus IaC to rebuild the stack there.
- **D.** A pilot light with Aurora Global Database and pre-provisioned load balancers.

<details><summary>Answer</summary>

**Answer: C**

**Why (P8):** With an RPO of hours and an RTO of a day, backup and restore is enough, and it's the cheapest tier.

- **A** — wrong: meets the targets, but costs more than necessary.
- **B** — wrong: far exceeds the requirements, at the highest cost.
- **C** — correct: the cheapest strategy that meets both numbers.
- **D** — wrong: costs more than necessary, and migrating to Aurora isn't required.

**Reference:** <https://docs.aws.amazon.com/whitepapers/latest/disaster-recovery-workloads-on-aws/disaster-recovery-options-in-the-cloud.html>

</details>

### Q15 · Task 3.3 · Single answer

An e-commerce platform on Aurora MySQL and EC2 needs an RPO of under 1 minute and an RTO of 30 minutes for a Regional outage. The CFO wants to minimize the cost of resources running in the DR Region.

Which strategy best meets the requirements?

- **A.** Pilot light: an Aurora Global Database secondary cluster in the DR Region, AMIs and container images replicated there, and IaC ready to launch the application tier and switch DNS during failover.
- **B.** Backup and restore with daily snapshots copied to the DR Region.
- **C.** Multi-site active/active with full-size Auto Scaling groups in both Regions.
- **D.** A cross-Region read replica created from a snapshot when the disaster is declared.

<details><summary>Answer</summary>

**Answer: A**

**Why (P8):** Aurora Global Database replicates with typically sub-second lag (RPO under 1 minute). Launching compute from IaC fits within 30 minutes, and only the data tier runs continuously.

- **A** — correct: meets both numbers at minimum standing cost.
- **B** — wrong: RPO of up to 24 hours.
- **C** — wrong: meets the targets but at maximum cost.
- **D** — wrong: building a replica after the disaster violates both RPO and RTO, and the source Region may be unavailable.

**Reference:** <https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/aurora-global-database.html>

</details>

### Q16 · Task 3.3 · Select TWO

After a ransomware incident at a competitor, a bank requires that backups of its production workloads be kept for 7 years, that they can't be deleted or shortened by anyone (including administrators of the production account and the root user), and that they survive a full compromise of the production account.

Which combination of steps meets these requirements? (Select TWO.)

- **A.** Copy AWS Backup recovery points to a backup vault in a separate, dedicated backup account in the organization.
- **B.** Enable S3 versioning on the buckets in the production account.
- **C.** Attach an IAM policy in the production account that denies `backup:DeleteRecoveryPoint` to all users.
- **D.** Apply AWS Backup Vault Lock in compliance mode, with a 7-year minimum retention, on the destination vault.
- **E.** Apply AWS Backup Vault Lock in governance mode on the production account's vault.

<details><summary>Answer</summary>

**Answer: A, D**

**Why (P6, P8):** A separate account isolates the backups from a compromised production account. Vault Lock in **compliance** mode makes the retention immutable for everyone, once the cooling-off period has passed.

- **A** — correct: blast-radius isolation.
- **B** — wrong: doesn't cover all resource types, and production admins could still delete versions.
- **C** — wrong: a compromised administrator, or the root user, can remove it.
- **D** — correct: WORM retention nobody can override.
- **E** — wrong: governance mode can be removed by sufficiently privileged users, and the vault is still in the compromised account.

**Reference:** <https://docs.aws.amazon.com/aws-backup/latest/devguide/vault-lock.html>

</details>

### Q17 · Task 3.3 · Single answer

A company runs 40 on-premises VMware virtual machines, including databases on Windows and Linux. It needs disaster recovery into AWS with an RPO of seconds and an RTO of minutes, and doesn't want to pay for full-size servers running in AWS all the time.

What should the DevOps engineer propose?

- **A.** AWS Backup for VMware with a daily backup plan.
- **B.** A nightly export of VM images to S3 and conversion with VM Import when needed.
- **C.** Rebuilding the applications on AWS with CloudFormation and replicating the databases manually.
- **D.** AWS Elastic Disaster Recovery, which replicates the servers continuously to a low-cost staging area and launches recovery instances on demand.

<details><summary>Answer</summary>

**Answer: D**

**Why (P8):** Elastic Disaster Recovery does block-level continuous replication (RPO in seconds) into lightweight staging resources, and launches full instances only during recovery or drills (RTO in minutes).

- **A** — wrong: a daily backup gives an RPO of up to 24 hours, and the restore time is longer.
- **B** — wrong: the RPO is a day, and VM import is slow.
- **C** — wrong: a re-architecture project, not a DR service.
- **D** — correct: purpose-built for this case.

**Reference:** <https://docs.aws.amazon.com/drs/latest/userguide/what-is-drs.html>

</details>

### Q18 · Task 3.3 · Single answer

Auditors require evidence, every quarter, that the production RDS Multi-AZ database fails over successfully and that the application recovers within its RTO. The team wants this test automated, repeatable and stopped automatically if customer-facing errors exceed a threshold.

What should the DevOps engineer implement?

- **A.** A runbook document that tells an engineer to stop the primary instance.
- **B.** An AWS FIS experiment template that uses the `aws:rds:reboot-db-instances` action with `forceFailover` set to true, with a stop condition on a CloudWatch alarm for the application error rate, scheduled quarterly.
- **C.** Deleting the standby instance and recreating it.
- **D.** Modifying the instance class during business hours, which triggers a failover.

<details><summary>Answer</summary>

**Answer: B**

**Why (P5, P8):** FIS runs controlled, repeatable faults, records the experiment for evidence, and halts automatically on a stop-condition alarm.

- **A** — wrong: manual, and stopping a Multi-AZ primary isn't the same as failing it over.
- **B** — correct: an automated failover test with guardrails and an audit trail.
- **C** — wrong: you can't delete the standby on its own, and doing so wouldn't test failover.
- **D** — wrong: an uncontrolled change with no automatic stop.

**Reference:** <https://docs.aws.amazon.com/fis/latest/userguide/fis-actions-reference.html>

</details>

### Q19 · Task 3.3 · Single answer

A team uses DynamoDB global tables in two Regions and considers that its backup strategy. A faulty deployment deleted thousands of items, and the deletions replicated to both Regions within seconds. The data couldn't be recovered.

What should the DevOps engineer implement to prevent this outcome in future?

- **A.** Add a third replica Region.
- **B.** Enable DynamoDB Streams and archive every change to S3 with a Lambda function.
- **C.** Enable point-in-time recovery on the table replicas, so that the table can be restored to any second within the retention window.
- **D.** Switch the table to provisioned capacity mode.

<details><summary>Answer</summary>

**Answer: C**

**Why (P8):** Replication isn't backup, because mistakes replicate too. PITR provides restorable points in time.

- **A** — wrong: one more copy of the same deletions.
- **B** — wrong: custom code that rebuilds a backup feature DynamoDB already has.
- **C** — correct: a native, continuous backup for recovering from logical errors.
- **D** — wrong: unrelated to recovery.

**Reference:** <https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/Point-in-time-recovery.html>

</details>

### Q20 · Task 3.3 · Select TWO

During a DR test in `us-west-2`, the application couldn't start. It couldn't read its database credentials (stored in Secrets Manager in `us-east-1`), and it couldn't decrypt EBS snapshots that had been encrypted with a customer managed KMS key in `us-east-1` and copied across. The team wants these dependencies ready in the DR Region in advance, with no manual steps during a disaster.

Which combination of steps meets these requirements? (Select TWO.)

- **A.** Export the secrets to an encrypted file in S3 and download it during failover.
- **B.** Configure the Secrets Manager secrets with replica secrets in `us-west-2`.
- **C.** Share the AWS managed EBS key (`aws/ebs`) with the DR Region.
- **D.** Recreate the KMS key manually in `us-west-2` after a disaster is declared.
- **E.** Use KMS multi-Region keys, with a replica key in `us-west-2`, for the encryption that DR copies depend on.

<details><summary>Answer</summary>

**Answer: B, E**

**Why (P11, P8):** Replica secrets keep the secret available and in sync in the DR Region. Multi-Region keys let the DR Region decrypt data encrypted under the same key material.

- **A** — wrong: a manual, fragile process that copies secrets out of the service.
- **B** — correct: native secret replication.
- **C** — wrong: AWS managed keys are Regional and can't be shared or replicated.
- **D** — wrong: a new key can't decrypt data encrypted under the old one, and it's a manual step.
- **E** — correct: the same key material is available in the DR Region.

**Reference:** <https://docs.aws.amazon.com/kms/latest/developerguide/multi-region-keys-overview.html>

</details>
