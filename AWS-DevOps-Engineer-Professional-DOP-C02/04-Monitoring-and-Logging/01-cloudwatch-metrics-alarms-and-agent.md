# Domain 4 · 01 · CloudWatch Metrics, Alarms and the CloudWatch Agent

> **Exam tasks:** 4.1 (metrics, custom metrics with the agent, metric streams), 4.2 (alarms, anomaly detection, common metrics, dashboards), 4.3 (alarm actions, health checks, agents). **Principles:** P10 (observe outcomes), P1 (alarms as events), P5 (alarms gate deployments).

## 1. First principles

1. **A metric is a time series identified by namespace + name + dimensions.** Change any dimension and it's a different metric. Alarms, dashboards and math operate on these exact identities.
2. **AWS publishes what the hypervisor and service can see; everything inside the guest is yours to publish.** CPU, network and disk I/O are visible from outside an EC2 instance. **Memory, disk-space usage, processes and application counters are not.** They need the **CloudWatch agent** or your own `PutMetricData` / Embedded Metric Format.
3. **An alarm is a state machine** (`OK` ↔ `ALARM` ↔ `INSUFFICIENT_DATA`). Its **state changes** are the events that drive actions: SNS, Auto Scaling, EC2 actions, EventBridge, deployment rollbacks.

---

## 2. Metrics

| Property | Facts |
|---|---|
| **Namespace** | `AWS/EC2`, `AWS/ApplicationELB`, …; custom ones like `MyApp/Orders` |
| **Dimensions** | Name/value pairs (up to 30 per metric) such as `InstanceId`, `AutoScalingGroupName`, `TargetGroup` |
| **Resolution** | **Standard** = 1-minute granularity. **High-resolution** custom metrics = 1-second granularity (high-resolution alarms at 10 s or 30 s periods) |
| **EC2 monitoring** | **Basic** = 5-minute periods (free); **detailed** = 1-minute periods (paid). Neither adds memory or disk-space metrics |
| **Retention** (automatic roll-up) | Under 60 s data: 3 hours; 60 s: 15 days; 5 min: 63 days; 1 hour: 455 days (15 months) |
| **Statistics** | Average, Sum, Minimum, Maximum, SampleCount, **percentiles** (p50, p90, p99), trimmed mean |
| **Metric math** | Combine metrics (`errors / requests * 100`), and alarm on the result |
| **Custom metrics** | `PutMetricData` (API/SDK/CLI), the **CloudWatch agent** (incl. StatsD and collectd), or **Embedded Metric Format**: structured JSON log lines that CloudWatch Logs turns into metrics asynchronously. Ideal from Lambda: no API calls in the hot path |

### 2.1 The CloudWatch agent

* **Collects:**
  * **system metrics** inside the OS: memory (`mem_used_percent`), disk (`disk_used_percent`), swap, netstat, and **procstat** (per-process);
  * **log files** to CloudWatch Logs;
  * **StatsD and collectd** custom metrics;
  * on Windows, performance counters and Event Log.
* **Runs on** EC2 and **on-premises** servers. On-premises servers need credentials: an IAM role via hybrid activation (SSM) or IAM Roles Anywhere, or a dedicated profile.
* **Configuration:** a JSON file, stored best in **SSM Parameter Store** (`AmazonCloudWatch-<name>`). Install and configure fleet-wide with **Systems Manager**: Distributor package `AmazonCloudWatchAgent`, then the `AmazonCloudWatch-ManageAgent` document, ideally as a **State Manager association** so new instances get it automatically (P3).
* **Permissions:** the instance role needs **`CloudWatchAgentServerPolicy`** (plus `AmazonSSMManagedInstanceCore` for SSM management). Without it, the agent runs but nothing arrives.
* The agent also **appends dimensions** such as `AutoScalingGroupName`, `InstanceId` and `ImageId`, so metrics can be aggregated per ASG for scaling.

### 2.2 Metric streams vs polling

* **Metric streams:** continuous, near-real-time delivery of selected namespaces to **Amazon Data Firehose** (→ S3, OpenSearch, Splunk, HTTP endpoints, partners), in JSON or OpenTelemetry format. The answer to "send all CloudWatch metrics to a third-party observability tool or data lake in near real time".
* **`GetMetricData` polling:** pull-based. Fine for small integrations; laggy and API-heavy at scale.

### 2.3 Cross-account observability

* **CloudWatch cross-account observability:** a **monitoring account** links to **source accounts** (an Observability Access Manager *sink* and *links*, deployable org-wide). Metrics, logs, traces and Application Signals data from source accounts can then be searched, graphed and **alarmed on** in the monitoring account.
* Older alternative: cross-account cross-Region **dashboards** with a sharing role.

## 3. Alarms

| Setting | Meaning |
|---|---|
| **Period** | Aggregation window per data point (10 s, 30 s or multiples of 60 s) |
| **Evaluation periods** (N) and **datapoints to alarm** (M) | "M out of N" breaching data points → ALARM. Smooths out blips (e.g. 3 out of 5) |
| **Treat missing data** | `missing` (default), `notBreaching`, `breaching`, `ignore`. A heartbeat-style alarm ("the job didn't report") uses **`breaching`** |
| **Anomaly detection** | Alarm when the metric leaves a **band** learned from history (seasonality, trend). For metrics without a fixed "good" threshold |
| **Metric math alarm** | Alarm on an expression (error rate %, sums across instances) |
| **Composite alarm** | Combines other alarms with `AND` / `OR` / `NOT`, e.g. "page only if 5xx is high **and** latency is high". Reduces noise; **actions suppression** silences child-alarm actions while a suppressor alarm (e.g. maintenance) is active |

**Alarm actions:**
* **SNS** topic (email, SMS, HTTPS, Chatbot, Lambda subscribers).
* **Lambda** function (directly).
* **EC2 actions** on per-instance alarms: **stop, terminate, reboot, recover**. `recover` uses `StatusCheckFailed_System`.
* **Auto Scaling** policy (step and simple scaling).
* **Systems Manager:** create an **OpsItem** (OpsCenter) or start an incident.
* **EventBridge:** every state change is an event (`CloudWatch Alarm State Change`), so any EventBridge target works.

**Alarms as deployment gates (P5):** CodeDeploy deployment groups, SAM `DeploymentPreference.Alarms`, ECS deployment alarms, CloudFormation rollback triggers, AppConfig environments, CodePipeline V2 stage conditions and FIS stop conditions all **consume alarms**. Build the alarm once and wire it everywhere.

## 4. Metrics the exam names

| Service | Metric | Why it matters |
|---|---|---|
| EC2 | `CPUUtilization`; `StatusCheckFailed_System` (AWS hardware or host) vs `StatusCheckFailed_Instance` (your OS) | System failure → `recover`; instance failure → `reboot` or replace |
| ALB | `HTTPCode_ELB_5XX_Count` (the **load balancer** generated it, e.g. no healthy targets) vs **`HTTPCode_Target_5XX_Count`** (your app returned it); `TargetResponseTime`; `UnHealthyHostCount`; `RequestCountPerTarget` | Distinguish LB problems from app problems; scaling metric |
| SQS | `ApproximateNumberOfMessagesVisible`; **`ApproximateAgeOfOldestMessage`** | Backlog scaling; a stuck-consumer alarm |
| RDS | `CPUUtilization`, `FreeStorageSpace`, `DatabaseConnections`, `ReplicaLag`, `ReadLatency`/`WriteLatency`, **`DiskQueueDepth`** (outstanding I/O, "queue length") | Storage auto scaling; I/O bottleneck |
| Lambda | `Errors`, **`Throttles`**, `Duration`, `ConcurrentExecutions`, **`IteratorAge`** (stream consumers falling behind) | Rollback alarms; stream lag |
| DynamoDB | `ThrottledRequests`, `ReadThrottleEvents`/`WriteThrottleEvents`, `ConsumedRead/WriteCapacityUnits` | Capacity and hot keys |
| API Gateway | `5XXError`, `4XXError`, `Latency` vs `IntegrationLatency` | Gateway overhead vs backend time |
| ECS | Service `CPUUtilization`/`MemoryUtilization`; **Container Insights** for task-level detail | Service auto scaling |
| Route 53 | `HealthCheckStatus` (**us-east-1** only) | Health-check alarms |

**Container Insights** (ECS, EKS), **Lambda Insights** and **CloudWatch Application Signals** (APM: request rate, errors, latency per service, plus **SLOs**) add curated metrics and dashboards on top.

## 5. Dashboards and visualization

* **CloudWatch dashboards:** metrics, logs and alarm widgets across **accounts and Regions**; automatic service dashboards; can be shared.
* **Amazon Managed Grafana:** Grafana with AWS data sources (CloudWatch, **Amazon Managed Service for Prometheus**, X-Ray, OpenSearch, Athena, Timestream) and IAM Identity Center sign-in. The answer when teams already standardize on Grafana or Prometheus (PromQL).
* **Amazon Quick Sight:** business-intelligence dashboards, typically over **Athena** queries of logs in S3. "Visualize the CloudTrail/ALB log analysis for managers" → Athena + Quick Sight.

## 6. Exam traps

* **"Enable detailed monitoring to see memory"** is wrong. Detailed monitoring only changes the period. Memory needs the agent.
* **The agent installed but no metrics:** the instance role lacks `CloudWatchAgentServerPolicy`, or there's no network path to the CloudWatch endpoint (private subnet without NAT or VPC endpoints).
* **`HTTPCode_ELB_5XX` vs `HTTPCode_Target_5XX`:** know which side failed.
* **Alarm stuck in `INSUFFICIENT_DATA`** for a sparse metric: set **treat missing data** properly.
* **Route 53 health-check alarms** must be created in **us-east-1**.
* **Third-party export of metrics at scale** → metric streams + Firehose, not a polling Lambda.

## 7. Hands-on lab: agent via State Manager + metric filter + alarm (about 40 minutes)

[labs/lab-08-cloudwatch-agent-alarm.yaml](labs/lab-08-cloudwatch-agent-alarm.yaml) creates:
* an instance with SSM and CloudWatch agent permissions;
* the agent configuration in **Parameter Store**;
* **two State Manager associations** (install the agent package; configure it from the parameter) targeting the instance's tag;
* a log group with **30-day retention**;
* a **metric filter** for `ERROR`;
* an **alarm** (≥ 5 errors in 1 minute) → SNS.

```bash
aws cloudformation deploy --stack-name dop-lab-08 \
  --template-file labs/lab-08-cloudwatch-agent-alarm.yaml --capabilities CAPABILITY_IAM \
  --parameter-overrides NotificationEmail=you@example.com
# After a few minutes: CWAgent namespace shows mem_used_percent and disk_used_percent.
# Generate errors through Session Manager (no SSH needed):
aws ssm start-session --target <instance-id>
for i in $(seq 1 10); do echo "$(date) ERROR payment failed" | sudo tee -a /var/log/app/app.log; done
# The metric filter counts them, the alarm fires, and the email arrives.
aws cloudformation delete-stack --stack-name dop-lab-08
```

## References

* CloudWatch concepts — <https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/cloudwatch_concepts.html>
* Install the CloudWatch agent with Systems Manager — <https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/installing-cloudwatch-agent-ssm.html>
* Metrics collected by the CloudWatch agent — <https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/metrics-collected-by-CloudWatch-agent.html>
* Embedded Metric Format — <https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/CloudWatch_Embedded_Metric_Format.html>
* Metric streams — <https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/CloudWatch-Metric-Streams.html>
* Cross-account observability — <https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/CloudWatch-Unified-Cross-Account.html>
* Alarm concepts (M out of N, missing data) — <https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/AlarmThatSendsEmail.html>
* Anomaly detection — <https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/CloudWatch_Anomaly_Detection.html>
* Composite alarms — <https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/Create_Composite_Alarm.html>
* ALB CloudWatch metrics — <https://docs.aws.amazon.com/elasticloadbalancing/latest/application/load-balancer-cloudwatch-metrics.html>
