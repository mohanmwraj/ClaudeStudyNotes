# Domain 4 · 03 · Tracing, Synthetic and Real-User Monitoring, Analytics

> **Exam tasks:** 4.2 (X-Ray for containers, API Gateway and Lambda; anomaly detection; Inspector and Config as monitoring; CloudTrail events; dashboards and Quick Sight; Athena and Logs Insights). **Principles:** P10 (metrics vs logs vs traces vs synthetics).

## 1. First principle: each signal answers a different question

| Signal | Question it answers | AWS tool |
|---|---|---|
| Metric | "How much, how fast, how often?", trends and thresholds | CloudWatch metrics |
| Log | "What exactly happened in this component?" | CloudWatch Logs, S3 + Athena, OpenSearch |
| **Trace** | "Where did **this request** spend its time, and which hop failed?" | **AWS X-Ray** (OpenTelemetry via ADOT) |
| **Synthetic check** | "Can a user complete the journey **right now**, even with no real traffic?" | **CloudWatch Synthetics** canaries |
| **Real-user monitoring** | "What do real browsers experience?" | **CloudWatch RUM** |
| Audit event | "Who did what to which resource?" | CloudTrail (see [06/03](../06-Security-and-Compliance/03-detection-auditing-and-response.md)) |

A question that says "identify which downstream service causes the latency" is a **tracing** question. One that says "detect the outage before customers call, at 3 a.m. with no traffic" is a **synthetics** question.

---

## 2. AWS X-Ray

### 2.1 Concepts

* **Trace:** one request end to end, identified by a trace ID propagated in the `X-Amzn-Trace-Id` header.
* **Segment:** the work done by one service.
* **Subsegments:** downstream calls (AWS SDK calls, HTTP, SQL).
* **Annotations vs metadata:** annotations are key/value pairs **indexed for filter expressions** (`annotation.customerTier = "gold"`); metadata isn't indexed. "Find traces for a specific customer ID" → **annotations**.
* **Sampling rules:** a **reservoir** (fixed requests per second) plus a **rate** (percentage beyond the reservoir), per service, URL or method. Change sampling centrally without redeploying.
* **Service map / trace map:** nodes and edges with latency, error and fault rates.
* **Groups:** filtered views with their own metrics. **X-Ray Insights** detects anomalies in fault rates.

### 2.2 Enabling X-Ray by platform

| Platform | How |
|---|---|
| **Lambda** | Turn on **active tracing** (`TracingConfig: Active`; SAM `Tracing: Active`). No daemon needed. The execution role needs `xray:PutTraceSegments` and `xray:PutTelemetryRecords` (`AWSXRayDaemonWriteAccess`). Instrument the SDK in code to see subsegments |
| **API Gateway** (REST) | Enable **X-Ray tracing on the stage**. API Gateway then starts traces and passes the header to integrations |
| **EC2 / on-premises** | Run the **X-Ray daemon**, or the **AWS Distro for OpenTelemetry (ADOT) collector**, on the instance. It listens on **UDP 2000** and forwards batches to X-Ray. Instance role with X-Ray write permissions |
| **ECS** | Run the daemon or ADOT collector as a **sidecar container** in the task definition; the app sends to it. The **task role** has X-Ray write permissions |
| **EKS** | ADOT collector (add-on) as a DaemonSet or sidecar; IRSA/Pod Identity for permissions |
| **Elastic Beanstalk** | An option setting enables the daemon on the platform |
| **SQS, SNS, Step Functions, EventBridge** | Propagate or record traces natively, so traces link across asynchronous hops |

**Instrumentation:**
* The X-Ray SDKs, or **OpenTelemetry SDKs with ADOT**, which AWS recommends for new instrumentation.
* Auto-instrumentation agents exist for Java, Python, .NET and Node.js.
* **CloudWatch Application Signals** builds on OpenTelemetry instrumentation to give per-service golden signals (volume, latency, faults, errors), a service map and **SLOs**.

## 3. CloudWatch Synthetics and RUM

* **Synthetics canaries:**
  * Scripted checks in Node.js or Python, using Puppeteer, Playwright or Selenium. Blueprints cover heartbeat, API, broken links, visual comparison and GUI workflows.
  * They run on a **schedule** from AWS-managed Lambda, including **inside a VPC** for private endpoints.
  * Results: metrics (`SuccessPercent`, `Duration`), screenshots, HAR files and logs in S3.
  * **Alarm on `SuccessPercent`.** Use canaries to detect outages without real traffic, and to gate or roll back deployments (task 5.3 calls it "CloudWatch synthetic monitoring").
* **CloudWatch RUM:** a JavaScript snippet collects page-load times, JavaScript errors and HTTP errors from real browsers, with Cognito identity for authorization.

## 4. Other detection features

| Feature | What it is |
|---|---|
| **Anomaly detection** (metrics) | Learned expected bands; alarm outside the band (see [01](01-cloudwatch-metrics-alarms-and-agent.md)) |
| **Contributor Insights** | Top-N contributors from structured logs, e.g. "top 10 IPs by 5xx", "the heaviest DynamoDB partition keys" |
| **Log anomaly detection** | Unusual log patterns per log group |
| **Container Insights / Lambda Insights** | Curated performance metrics and logs for ECS/EKS and Lambda |
| **CloudTrail Insights** | Detects unusual **API call volume or error rates** (e.g. a sudden burst of `TerminateInstances`) |
| **Amazon Inspector** | Continuous vulnerability findings for EC2 (via the SSM Agent), ECR images and Lambda. "Assessment templates" belong to the retired Inspector Classic; current Inspector needs no templates, because scanning is automatic once enabled |
| **AWS Config rules** | Configuration compliance as a monitoring signal; compliance-change events go to EventBridge |
| **AWS Health** | Service events and scheduled changes affecting your resources (see [05/01](../05-Incident-and-Event-Response/01-event-sources-and-routing.md)) |

## 5. Analysis tool chooser

| Need | Tool |
|---|---|
| Ad-hoc query of recent application logs in CloudWatch | **CloudWatch Logs Insights** |
| SQL over months of CloudTrail, ALB, VPC Flow or CloudFront logs in S3 | **Athena** (partition projection, Parquet) |
| Full-text search, log exploration dashboards, near real time | **OpenSearch Service** (fed by Firehose or a subscription) |
| Real-time stream computations (windows, aggregations) | **Kinesis Data Streams + Managed Service for Apache Flink**, or Lambda |
| Business or management dashboards on log analytics | **Amazon Quick Sight** on Athena |
| Prometheus metrics from Kubernetes, PromQL | **Amazon Managed Service for Prometheus** + **Amazon Managed Grafana** |
| Operational dashboards of AWS metrics across accounts | **CloudWatch dashboards** (cross-account observability) |
| SQL over CloudTrail events without building a pipeline | **CloudTrail Lake** |
| Large-scale batch processing of log archives (Spark) | **Amazon EMR** |

## 6. Exam traps

* **Lambda tracing doesn't need the X-Ray daemon.** EC2 and ECS do (or ADOT).
* **On ECS the daemon is a sidecar container,** not something installed on the host via user data (and Fargate has no host).
* **Filter traces by business attributes with annotations, not metadata.**
* **Synthetics canaries generate traffic** (they detect outages during quiet hours); RUM needs real users.
* **Inspector "assessment templates"** are Inspector Classic terminology. Modern Inspector scans automatically once enabled (via the organization's delegated administrator).
* **Athena vs Logs Insights** comes down to **where the data lives** (S3 vs CloudWatch Logs).

## References

* AWS X-Ray concepts — <https://docs.aws.amazon.com/xray/latest/devguide/xray-concepts.html>
* X-Ray sampling rules — <https://docs.aws.amazon.com/xray/latest/devguide/xray-console-sampling.html>
* Lambda and X-Ray — <https://docs.aws.amazon.com/lambda/latest/dg/services-xray.html>
* X-Ray on Amazon ECS — <https://docs.aws.amazon.com/xray/latest/devguide/xray-daemon-ecs.html>
* API Gateway X-Ray tracing — <https://docs.aws.amazon.com/apigateway/latest/developerguide/apigateway-xray.html>
* AWS Distro for OpenTelemetry — <https://aws-otel.github.io/docs/introduction>
* CloudWatch Application Signals — <https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/CloudWatch-Application-Monitoring-Sections.html>
* CloudWatch RUM — <https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/CloudWatch-RUM.html>
* Contributor Insights — <https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/ContributorInsights.html>
* CloudTrail Insights — <https://docs.aws.amazon.com/awscloudtrail/latest/userguide/logging-insights-events-with-cloudtrail.html>
* Amazon Managed Grafana — <https://docs.aws.amazon.com/grafana/latest/userguide/what-is-Amazon-Managed-Service-Grafana.html>
