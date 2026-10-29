# Domain 4 Drill · Monitoring and Logging (20 questions)

Original exam-style questions for tasks 4.1–4.3. The notes for this domain are in [04-Monitoring-and-Logging](../04-Monitoring-and-Logging/).

---

### Q1 · Task 4.1 · Single answer

An operations team wants to alarm when **memory utilization** on any instance in an Auto Scaling group exceeds 85%, and when the root volume's **disk usage** exceeds 90%. Detailed monitoring is already enabled on the instances, but neither metric appears in CloudWatch.

What should the DevOps engineer do?

- **A.** Enable enhanced networking on the instances.
- **B.** Enable detailed monitoring at the Auto Scaling group level as well.
- **C.** Install and configure the CloudWatch agent (for example through Systems Manager) to collect `mem_used_percent` and `disk_used_percent`, and attach `CloudWatchAgentServerPolicy` to the instance role.
- **D.** Create a metric math expression based on `CPUUtilization` to estimate memory use.

<details><summary>Answer</summary>

**Answer: C**

**Why (P10):** Memory and file-system usage are only visible inside the guest OS. The CloudWatch agent publishes them, and the instance role must allow it to.

- **A** — wrong: networking performance, unrelated.
- **B** — wrong: detailed monitoring only changes the period of hypervisor-level metrics.
- **C** — correct: the agent plus permissions.
- **D** — wrong: CPU can't stand in for memory.

**Reference:** <https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/metrics-collected-by-CloudWatch-agent.html>

</details>

### Q2 · Task 4.1 · Single answer

An application writes logs to a CloudWatch Logs log group. The team must be paged when the string `OutOfMemoryError` appears more than 3 times within 5 minutes.

What is the MOST operationally efficient solution?

- **A.** Create a metric filter on the log group that matches `OutOfMemoryError` and emits a count to a custom metric, then create a CloudWatch alarm (Sum > 3 over 5 minutes) that notifies an SNS topic.
- **B.** Schedule a Lambda function every 5 minutes that runs a Logs Insights query and publishes to SNS when the count exceeds 3.
- **C.** Export the log group to S3 every 5 minutes and query it with Athena.
- **D.** Create a subscription filter that streams all events to an OpenSearch domain and build a dashboard.

<details><summary>Answer</summary>

**Answer: A**

**Why (P10, P12):** A metric filter turns log matches into a metric with no code, and an alarm on that metric drives notifications.

- **A** — correct: native, near real time, no code.
- **B** — wrong: polling with custom code.
- **C** — wrong: export tasks are batch jobs, and only one can run at a time per account. Unsuitable for alerting.
- **D** — wrong: a dashboard isn't an alert, and OpenSearch costs more.

**Reference:** <https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/MonitoringLogData.html>

</details>

### Q3 · Task 4.1 · Single answer

A company uses a third-party observability platform and must send **all** CloudWatch metrics from its accounts there continuously, with a delay of a few minutes at most. Today a Lambda function calls `GetMetricData` every 10 minutes and often hits API throttling.

What should the DevOps engineer implement?

- **A.** Increase the Lambda function's schedule frequency to every minute.
- **B.** Export CloudWatch Logs to S3 and let the vendor import them.
- **C.** Enable CloudWatch detailed monitoring for all resources.
- **D.** Create a CloudWatch metric stream that delivers the metrics through Amazon Data Firehose to the vendor's HTTP endpoint, or to the vendor's partner integration.

<details><summary>Answer</summary>

**Answer: D**

**Why (P1, P12):** Metric streams **push** metrics continuously to Firehose with low latency, which removes the polling, the throttling and the custom code.

- **A** — wrong: more polling means more throttling.
- **B** — wrong: logs aren't metrics, and an export is a batch job.
- **C** — wrong: changes the metric period. It doesn't deliver metrics anywhere.
- **D** — correct: purpose-built continuous export.

**Reference:** <https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/CloudWatch-Metric-Streams.html>

</details>

### Q4 · Task 4.1 · Select TWO

A security team must collect application log events from CloudWatch Logs in 50 workload accounts into a central log-archive account in near real time, and store them in S3 for 7 years. Workload account administrators must not be able to delete the archived copy.

Which combination of steps meets these requirements? (Select TWO.)

- **A.** Schedule CloudWatch Logs export tasks in each account every night to a bucket in the same account.
- **B.** In the log-archive account, create a CloudWatch Logs destination backed by an Amazon Data Firehose stream that writes to an S3 bucket in that account, with a destination policy that allows the organization's accounts.
- **C.** Create an IAM user in the log-archive account and configure the CloudWatch agent in every account to write directly with its keys.
- **D.** Configure S3 Cross-Region Replication from every workload account's log group to the archive bucket.
- **E.** In each workload account, create subscription filters (or an account-level subscription filter policy) that send the log groups to the log-archive destination.

<details><summary>Answer</summary>

**Answer: B, E**

**Why (P13, P10):** Cross-account log centralization uses a **Logs destination** on the receiving side and **subscription filters** on the sending side. Firehose delivers to S3 in the archive account, out of reach of the workload accounts.

- **A** — wrong: batch, not near real time, and the copy stays in the workload account.
- **B** — correct: the receiving-side destination.
- **C** — wrong: long-term credentials shared across accounts.
- **D** — wrong: log groups aren't S3 buckets, so they can't be replicated with S3 replication.
- **E** — correct: the sending-side streaming.

**Reference:** <https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/CrossAccountSubscriptions.html>

</details>

### Q5 · Task 4.1 · Single answer

To meet a compliance requirement, an engineer tries to associate a customer managed KMS key with a CloudWatch Logs log group. The operation fails with an access-denied error, even though the engineer has `kms:*` permissions in IAM.

What is the cause?

- **A.** CloudWatch Logs only supports AWS managed keys.
- **B.** The KMS key policy doesn't allow the CloudWatch Logs service principal (`logs.<region>.amazonaws.com`) to use the key for that log group.
- **C.** Log groups can be encrypted only at creation time, by the account root user.
- **D.** The key must be a multi-Region key.

<details><summary>Answer</summary>

**Answer: B**

**Why (P11):** CloudWatch Logs itself performs the cryptographic operations, so the **key policy** must grant the Regional Logs service principal (scoped with the `kms:EncryptionContext:aws:logs:arn` condition). The engineer's IAM permissions aren't what's checked.

- **A** — wrong: customer managed keys are supported, and they're the point of the requirement.
- **B** — correct: the key policy is missing the service principal.
- **C** — wrong: you can associate a key with an existing log group, and root isn't required.
- **D** — wrong: no such requirement.

**Reference:** <https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/encrypt-log-data-kms.html>

</details>

### Q6 · Task 4.1 · Single answer

CloudWatch Logs costs are rising because every log group uses the default retention. Application teams query only the last 30 days interactively. Regulations require keeping all logs for 7 years at the lowest possible storage cost.

What should the DevOps engineer do?

- **A.** Change every log group to the Infrequent Access log class and keep the default retention.
- **B.** Export all log groups to S3 manually once a year and then delete them.
- **C.** Set a 30-day retention policy on the log groups, stream the logs through subscription filters and Firehose to S3, and apply S3 lifecycle rules that move objects to S3 Glacier Deep Archive and expire them after 7 years.
- **D.** Set the retention of every log group to 7 years.

<details><summary>Answer</summary>

**Answer: C**

**Why (P10):** Hot data stays in CloudWatch for interactive queries; long-term retention moves to the cheapest S3 storage class, managed by lifecycle rules.

- **A** — wrong: "never expire" retention still keeps 7+ years in CloudWatch, and the IA class loses features without being the cheapest archive.
- **B** — wrong: manual, gappy, and data could be lost between exports.
- **C** — correct: tiered retention by access pattern.
- **D** — wrong: the most expensive way to keep 7 years of logs.

**Reference:** <https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/Working-with-log-groups-and-streams.html>

</details>

### Q7 · Task 4.2 · Single answer

API latency for a booking service is normally about 800 ms at peak and about 150 ms overnight. A fixed alarm threshold either pages every night or misses daytime degradations. The team wants an alarm that fires when latency is unusual **for the time of day**.

What should the DevOps engineer configure?

- **A.** Two alarms with different static thresholds, enabled and disabled on a schedule by a Lambda function.
- **B.** A composite alarm that combines a day alarm and a night alarm.
- **C.** A metric math alarm that divides latency by the request count.
- **D.** A CloudWatch anomaly detection alarm on the latency metric.

<details><summary>Answer</summary>

**Answer: D**

**Why (P10):** Anomaly detection learns the metric's expected band, including daily and weekly seasonality, and alarms when the metric leaves the band.

- **A** — wrong: custom scheduling, and still static within each period.
- **B** — wrong: still relies on static thresholds.
- **C** — wrong: changes the metric but doesn't model time-of-day behaviour.
- **D** — correct: built for exactly this.

**Reference:** <https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/CloudWatch_Anomaly_Detection.html>

</details>

### Q8 · Task 4.2 · Single answer

The on-call engineers get paged by an alarm on 5xx errors and a separate alarm on high latency, often for brief blips that resolve themselves. Leadership wants a page only when **both** conditions are true at the same time, while each individual alarm stays visible on dashboards.

What should the DevOps engineer do?

- **A.** Create a composite alarm with the rule `ALARM(5xxAlarm) AND ALARM(LatencyAlarm)`, move the paging action to the composite alarm, and remove the actions from the two child alarms.
- **B.** Increase the evaluation periods of both alarms to 30.
- **C.** Delete the latency alarm.
- **D.** Send both alarms to an SQS queue and have a Lambda function decide whether to page.

<details><summary>Answer</summary>

**Answer: A**

**Why (P10, P12):** Composite alarms combine alarm states with Boolean logic, which reduces noise natively while the child alarms remain visible.

- **A** — correct: native noise reduction.
- **B** — wrong: delays real incidents and doesn't express the AND condition.
- **C** — wrong: loses a signal.
- **D** — wrong: custom correlation logic for something CloudWatch already does.

**Reference:** <https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/Create_Composite_Alarm.html>

</details>

### Q9 · Task 4.2 · Select TWO

A request flows from API Gateway (REST) to a Lambda function and then to an internal service running on Amazon ECS with Fargate. The team wants end-to-end distributed traces in AWS X-Ray covering all three components.

Which combination of steps meets these requirements? (Select TWO.)

- **A.** Enable X-Ray tracing on the API Gateway stage, and enable active tracing on the Lambda function (with an execution role that allows writing to X-Ray).
- **B.** Install the X-Ray daemon on the Lambda function through user data.
- **C.** Enable VPC Flow Logs on the ECS subnets.
- **D.** Add the X-Ray daemon (or an AWS Distro for OpenTelemetry collector) as a sidecar container in the ECS task definition, instrument the service, and grant the task role permission to write to X-Ray.
- **E.** Enable CloudTrail data events for Lambda.

<details><summary>Answer</summary>

**Answer: A, D**

**Why (P10):** API Gateway and Lambda have built-in tracing switches. ECS tasks need a collector (daemon or ADOT) as a sidecar, plus instrumented code and task-role permissions.

- **A** — correct: native tracing for the managed services.
- **B** — wrong: Lambda has no user data and needs no daemon.
- **C** — wrong: network flow records aren't request traces.
- **D** — correct: the container-side collector.
- **E** — wrong: audit records of invocations, not traces.

**Reference:** <https://docs.aws.amazon.com/xray/latest/devguide/xray-daemon-ecs.html>

</details>

### Q10 · Task 4.2 · Single answer

Support engineers need to find the X-Ray traces for requests made by a specific customer ID, and to filter traces for premium-tier customers, during investigations.

How should the developers record these values?

- **A.** As X-Ray metadata on the segment.
- **B.** As X-Ray annotations on the segment, which are indexed for filter expressions.
- **C.** As CloudWatch Logs entries with the trace ID.
- **D.** As custom CloudWatch metrics with the customer ID as a dimension.

<details><summary>Answer</summary>

**Answer: B**

**Why (P10):** Annotations are indexed key/value pairs that can be used in filter expressions (`annotation.customerId = "…"`). Metadata isn't indexed.

- **A** — wrong: metadata is stored but can't be searched.
- **B** — correct: searchable trace attributes.
- **C** — wrong: possible, but it doesn't filter traces in X-Ray directly.
- **D** — wrong: high-cardinality dimensions explode metric cost and don't find traces.

**Reference:** <https://docs.aws.amazon.com/xray/latest/devguide/xray-concepts.html>

</details>

### Q11 · Task 4.2 · Single answer

An incident review needs SQL queries over 18 months of Application Load Balancer access logs (several TB) stored in S3 under date-based prefixes. Queries are run occasionally, and costs must stay low.

What should the DevOps engineer use?

- **A.** Load all the logs into an always-on OpenSearch Service domain.
- **B.** Re-ingest the logs into CloudWatch Logs and use Logs Insights.
- **C.** Download the logs and analyze them on an EC2 instance.
- **D.** Amazon Athena with a table over the ALB log location and partition projection on the date, so that queries scan only the relevant days.

<details><summary>Answer</summary>

**Answer: D**

**Why (P10):** Athena queries data in S3 where it already sits, with pay-per-query pricing. Partitioning limits the bytes scanned, and therefore the cost.

- **A** — wrong: an always-on cluster is costly for occasional queries.
- **B** — wrong: re-ingesting costs a lot. Logs Insights is for data already in CloudWatch.
- **C** — wrong: manual and slow.
- **D** — correct: serverless SQL over S3.

**Reference:** <https://docs.aws.amazon.com/athena/latest/ug/application-load-balancer-logs.html>

</details>

### Q12 · Task 4.2 · Single answer

A retailer's checkout flow broke at 02:00 because of an expired third-party certificate. It wasn't noticed until customers arrived at 08:00, because there was no traffic overnight to trigger error alarms.

What should the DevOps engineer implement to detect such failures without real user traffic?

- **A.** CloudWatch RUM on the checkout pages.
- **B.** An alarm on the ALB's `HTTPCode_Target_5XX_Count` metric.
- **C.** A CloudWatch Synthetics canary that runs the checkout journey every 5 minutes, with an alarm on its `SuccessPercent` metric.
- **D.** X-Ray tracing for the checkout service.

<details><summary>Answer</summary>

**Answer: C**

**Why (P10):** Synthetic canaries **generate** traffic on a schedule, so failures are detected even when no users are active.

- **A** — wrong: RUM needs real users.
- **B** — wrong: no traffic means no 5xx errors to count.
- **C** — correct: proactive, user-journey monitoring.
- **D** — wrong: traces only exist for real requests.

**Reference:** <https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/CloudWatch_Synthetics_Canaries.html>

</details>

### Q13 · Task 4.2 · Single answer

Users report HTTP 503 errors from an Application Load Balancer. CloudWatch shows `HTTPCode_ELB_5XX_Count` rising sharply, while `HTTPCode_Target_5XX_Count` stays at zero and `RequestCount` to the targets drops to zero.

What is the MOST likely cause?

- **A.** The target group has no registered targets, for example because the Auto Scaling group scaled in to zero or the instances were deregistered.
- **B.** The application code is throwing exceptions.
- **C.** The database is overloaded.
- **D.** CloudFront is caching error responses.

<details><summary>Answer</summary>

**Answer: A**

**Why (P10):** ELB-generated 5xx errors with zero target 5xx errors mean the load balancer itself produced them. A 503 with no requests reaching any target points to an empty target group.

- **A** — correct: the load balancer has nowhere to send requests.
- **B** — wrong: application errors would appear as target 5xx errors.
- **C** — wrong: would surface as target errors or latency, not ELB-generated 503s with no requests forwarded.
- **D** — wrong: no CloudFront in the scenario, and caching wouldn't change the ALB's metrics.

**Reference:** <https://docs.aws.amazon.com/elasticloadbalancing/latest/application/load-balancer-troubleshooting.html>

</details>

### Q14 · Task 4.3 · Single answer

A licensed legacy application must run on one specific EC2 instance (EBS-backed), and its private IP address and Elastic IP address must not change. When AWS detects a problem with the underlying host, the instance must recover automatically.

What should the DevOps engineer configure?

- **A.** An Auto Scaling group with a minimum and maximum of 1.
- **B.** A CloudWatch alarm on `StatusCheckFailed_System` with the EC2 **recover** action (or rely on simplified automatic recovery, for supported instance types).
- **C.** A CloudWatch alarm on `StatusCheckFailed_Instance` with the EC2 terminate action.
- **D.** A Lambda function that creates a new instance from the latest snapshot when the instance stops.

<details><summary>Answer</summary>

**Answer: B**

**Why (P7):** Recovery moves the **same** instance (same ID, private IPs, EIP and EBS volumes) to healthy hardware when the system status check fails.

- **A** — wrong: an ASG launches a **new** instance with a new IP address.
- **B** — correct: same instance on new hardware.
- **C** — wrong: an instance check failure is an OS-level problem, and terminating destroys the instance.
- **D** — wrong: a new instance, custom code, and a possibly stale snapshot.

**Reference:** <https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-instance-recover.html>

</details>

### Q15 · Task 4.3 · Single answer

A third-party system uploads application log files to an S3 bucket every few minutes. The security team wants each new file parsed and indexed into an Amazon OpenSearch Service domain within a minute of arrival.

What is the MOST operationally efficient design?

- **A.** A cron job on an EC2 instance that lists the bucket every minute and indexes new files.
- **B.** An Athena query every minute that inserts the results into OpenSearch.
- **C.** A nightly AWS Glue job that loads the files into OpenSearch.
- **D.** An S3 event notification (optionally through SQS for buffering) that invokes a Lambda function to parse each new object and index it into OpenSearch.

<details><summary>Answer</summary>

**Answer: D**

**Why (P1, P9):** Event-driven processing: S3 emits an event per object, and Lambda processes it within seconds. An SQS buffer absorbs bursts and makes retries easier.

- **A** — wrong: polling, plus a server to manage.
- **B** — wrong: Athena isn't an indexing pipeline, and this is still polling.
- **C** — wrong: violates the 1-minute requirement.
- **D** — correct: serverless and event-driven.

**Reference:** <https://docs.aws.amazon.com/AmazonS3/latest/userguide/EventNotifications.html>

</details>

### Q16 · Task 4.3 · Select TWO

The operations team must get a readable notification (for example "Instance i-0abc in prod changed to stopped") whenever any EC2 instance in the production account is stopped or terminated, within a minute.

Which combination of steps meets these requirements with the LEAST effort? (Select TWO.)

- **A.** Schedule a Lambda function that calls `DescribeInstances` every minute and compares the states.
- **B.** Create an AWS Config rule that checks whether instances are running.
- **C.** Create an EventBridge rule that matches `EC2 Instance State-change Notification` events with `state` of `stopped` or `terminated`.
- **D.** Create a CloudTrail trail and search Event history manually every hour.
- **E.** Set an SNS topic as the rule's target, with an input transformer that formats the instance ID and state into a message.

<details><summary>Answer</summary>

**Answer: C, E**

**Why (P1):** EC2 emits state-change events natively. An EventBridge rule plus an SNS target with an input transformer delivers readable notifications without code.

- **A** — wrong: polling with custom code.
- **B** — wrong: Config evaluates compliance; it isn't a state-change notifier, and a stopped instance isn't non-compliant.
- **C** — correct: matches the native event.
- **D** — wrong: manual and hourly.
- **E** — correct: readable delivery without a Lambda.

**Reference:** <https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-transform-target-input.html>

</details>

### Q17 · Task 4.3 · Single answer

A Route 53 health check against a public web server's `/health` endpoint reports the server unhealthy, but the page loads fine from the office network. The server's security group allows HTTP only from the company's office IP range.

What should the DevOps engineer do?

- **A.** Change the health check to TCP.
- **B.** Increase the health check's request interval to 30 seconds.
- **C.** Allow inbound HTTP from the Route 53 health checker IP ranges (published in AWS's IP ranges file) on the server's security group, or put the check behind a CloudWatch alarm-based health check.
- **D.** Disable the health check and use a simple routing policy.

<details><summary>Answer</summary>

**Answer: C**

**Why (P7):** Route 53 health checkers connect from AWS's published health-check IP ranges, and the security group is blocking them.

- **A** — wrong: TCP checks are also blocked by the security group.
- **B** — wrong: doesn't change reachability.
- **C** — correct: allow the checkers, or check an alarm instead.
- **D** — wrong: removes failover protection.

**Reference:** <https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/route-53-ip-addresses.html>

</details>

### Q18 · Task 4.3 · Single answer

An Amazon RDS for MySQL instance occasionally runs out of storage after unpredictable bulk imports, which causes outages. The team wants storage to grow automatically, within a cost ceiling, without downtime.

What should the DevOps engineer do?

- **A.** Schedule a Lambda function that adds 100 GB every week.
- **B.** Enable RDS storage autoscaling with a maximum storage threshold.
- **C.** Create a read replica with more storage.
- **D.** Alarm on `FreeStorageSpace` and modify the storage manually when it fires.

<details><summary>Answer</summary>

**Answer: B**

**Why (P12):** RDS storage autoscaling increases allocated storage when free space runs low, up to the maximum you set. It's native and happens online.

- **A** — wrong: grows regardless of need, and is custom code.
- **B** — correct: automatic and capped.
- **C** — wrong: replicas don't add storage to the primary.
- **D** — wrong: manual and slow during an incident.

**Reference:** <https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_PIOPS.Autoscaling.html>

</details>

### Q19 · Task 4.2 · Single answer

A Lambda function consumes records from an Amazon Kinesis data stream. Occasionally the dashboards that depend on the stream show data that's 20–40 minutes old, and nobody notices until users complain.

Which metric should the DevOps engineer alarm on to detect this early?

- **A.** The Lambda `IteratorAge` metric (Maximum) for the function's event source mapping.
- **B.** The Lambda `Invocations` metric.
- **C.** The Kinesis `IncomingRecords` metric.
- **D.** The Lambda `Duration` metric (Average).

<details><summary>Answer</summary>

**Answer: A**

**Why (P10):** `IteratorAge` measures how old the last record processed is, so it's exactly the consumer's lag behind the stream.

- **A** — correct: a direct measure of staleness.
- **B** — wrong: invocations can stay steady while lag grows.
- **C** — wrong: measures input, not consumption.
- **D** — wrong: an indirect signal that misses blocked shards and retries.

**Reference:** <https://docs.aws.amazon.com/lambda/latest/dg/monitoring-metrics-types.html>

</details>

### Q20 · Task 4.3 · Single answer

To meet an encryption requirement, a team encrypted the SNS topic used by its CloudWatch alarms with the AWS managed key `aws/sns`. Since then, alarms change state but no notifications arrive. The topic must stay encrypted.

What should the DevOps engineer do?

- **A.** Add an IAM policy to the alarms that allows `kms:Decrypt`.
- **B.** Turn off encryption on the topic.
- **C.** Encrypt the topic with a customer managed KMS key whose key policy allows the CloudWatch service principal (`cloudwatch.amazonaws.com`) to use `kms:GenerateDataKey*` and `kms:Decrypt`.
- **D.** Recreate the alarms in another Region.

<details><summary>Answer</summary>

**Answer: C**

**Why (P11):** An AWS managed key's policy can't be edited to let a service publish. A customer managed key with a key policy that grants the service principal fixes it while keeping encryption.

- **A** — wrong: alarms don't have IAM policies or roles for publishing.
- **B** — wrong: violates the encryption requirement.
- **C** — correct: the documented fix.
- **D** — wrong: the problem moves with the key choice.

**Reference:** <https://docs.aws.amazon.com/sns/latest/dg/sns-key-management.html>

</details>
