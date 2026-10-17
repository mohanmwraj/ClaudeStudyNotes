# Chapter 15 — Observability, Operations & Continuous Improvement (Domain 3)
> **Exam mapping:** D3 Task 3.1 (operational excellence), 3.2 (security), 3.3 (performance), 3.4 (reliability); D1 Task 1.4 (multi-account environment, central logging) & 1.5 (visibility) — cost (3.5) is in Chapter 16 | **Weight signal:** High (Domain 3 = 25 % of the exam; observability shows up in many D1/D2 questions too) | **Study time:** ~7 h
> [← Previous](14-Deployment-DevOps-and-IaC.md) · [Index](00-README-Start-Here.md) · [Next →](16-Cost-Optimization-and-FinOps.md)

> **Status box — service changes you must know (as of 2026-10-17).** The exam was written before some of these changes, so an answer naming an "old" service can still be the intended one. Know both.
> - **AWS Systems Manager Incident Manager** and **Systems Manager Change Manager**: no longer open to new customers since **7 Nov 2025**. Existing customers can keep using them. AWS points new users to **Systems Manager OpsCenter** and to AWS Partner tools for paging. On the exam, "response plans, escalation, on-call engagement" still means Incident Manager.
> - **AWS CloudTrail Lake**: no longer open to new customers since **31 May 2026**. Trails, CloudTrail Insights and aggregated events are not affected. AWS suggests CloudWatch for similar capabilities.
> - **AWS X-Ray SDKs and X-Ray daemon**: in **maintenance mode since 25 Feb 2026**, with **end of support on 25 Feb 2027**. X-Ray (the backend) still accepts traces. The recommended instrumentation is **OpenTelemetry** (AWS Distro for OpenTelemetry, ADOT, or the CloudWatch agent).
> - **AWS Support plans**: Trusted Advisor full checks, the Health API and Trusted Advisor organizational view now list **Business Support+, Enterprise Support or Unified Operations**. Developer, Business and Enterprise On-Ramp are **discontinued on 1 Jan 2027** (they continue in GovCloud). Exam questions say "Business or Enterprise Support". Treat that as the same requirement.
> - **RDS Performance Insights**: the console experience has been retired in favour of **CloudWatch Database Insights**. The Performance Insights API continues. Exam questions still say "Performance Insights".
> - **AWS Security Hub**: the original service is now **Security Hub CSPM**. A new unified **Security Hub** (GA Dec 2025) correlates GuardDuty, Inspector and CSPM findings.
> - Renames: CloudWatch Events → **Amazon EventBridge**; Kinesis Data Firehose → **Amazon Data Firehose**.

---

## 1. What the exam really tests here

Domain 3 questions start from an **existing** workload that is failing in some way: too slow, too fragile, too insecure, too much manual work, or too opaque. You must pick the **smallest, most managed change** that fixes the **actual bottleneck**. Observability services are how you find that bottleneck and prove the fix worked.

Typical scenario shapes:

| Scenario shape | What you must decide |
|---|---|
| "Ops team in a central account must see metrics/logs/traces from 400 accounts" | CloudWatch **cross-account observability** (OAM sink/links via Organizations) vs subscription-based log shipping vs third-party tools |
| "Too many alarms / alert fatigue / false pages at night" | **Composite alarms**, **anomaly detection**, M-out-of-N evaluation, treat-missing-data, SLO-based alerting |
| "Need memory/disk metrics for right-sizing" | **CloudWatch agent** (pushed via Systems Manager), then **Compute Optimizer**, optionally enhanced infrastructure metrics |
| "Centralize logs for audit with 7-year immutable retention" | **Org CloudTrail → S3 in Log Archive account**, S3 Object Lock, lifecycle to Glacier, **Security Lake** for OCSF analytics |
| "React automatically to AWS scheduled maintenance / instance retirement" | **AWS Health** organizational view + delegated admin + **EventBridge** → Systems Manager Automation |
| "Detect and auto-fix non-compliant resources across the org" | **AWS Config** organization rules / conformance packs + **SSM Automation remediation**; aggregator for reporting |
| "App is slow": API latency, DB CPU high, repeated reads | **X-Ray / Application Signals / Database Insights** to locate it, then cache (CloudFront, ElastiCache, DAX), read replicas, RDS Proxy, async processing |
| "Intermittent 502s / 504s / 429s / throttles" | Map the symptom to its root cause (see the troubleshooting table in §4) |
| "Patch compliance across 5,000 instances, reporting to auditors" | **Patch Manager** patch policies (Quick Setup) + compliance + resource data sync → S3/Athena |
| "Prove the architecture follows best practice and track risks" | **Well-Architected Tool** reviews, milestones, improvement plans; Trusted Advisor; Security Hub |

What separates a Professional answer from an Associate one:
- You pick the **organization-wide** mechanism (delegated administrator, org trail, org Config rules, OAM with Organizations, Health organizational view, Trusted Advisor organizational view) over per-account scripts.
- You know which features **require which support plan** and which **cannot do what the distractor claims**. Examples: composite alarms cannot trigger EC2 actions. You cannot change a log group's class after creation. Metric filters do not backfill.
- You **fix the cause, not the symptom**. If DynamoDB throttles on a hot key, raising capacity is the wrong fix. Redesign the key or add caching.

---

## 2. Core concepts & services — deep dive

### 2.1 Observability mental model

```text
 SIGNALS                         ANALYZE                      ACT
 ───────                         ───────                      ───
 Metrics  (CloudWatch, AMP)  ──► Dashboards, alarms,      ──► SNS / chat / ticket
 Logs     (CloudWatch Logs)  ──► Logs Insights, anomaly   ──► EventBridge rule
 Traces   (X-Ray / OTel)     ──► Service map, SLOs        ──► SSM Automation runbook
 Events   (EventBridge,      ──► Config, Health,          ──► Auto Scaling, EC2 action
           CloudTrail)           Security Hub             ──► OpsItem / incident
```

- **Metrics** tell you *that* something is wrong. **Traces** tell you *where*. **Logs** tell you *why*. **Events** (CloudTrail, Config, Health) tell you *what changed*.
- Exam rule of thumb: "which component is slow?" → **X-Ray / Application Signals**. "Who changed it?" → **CloudTrail**. "What did the configuration look like last Tuesday?" → **AWS Config**. "Is AWS itself having a problem in my account?" → **AWS Health**.

### 2.2 Amazon CloudWatch Metrics

**Building blocks**
- **Namespace**: a container that isolates metrics. AWS namespaces follow `AWS/<service>` (for example `AWS/EC2`). Custom namespaces are anything you choose, up to 255 characters. There is no default namespace.
- **Metric**: a time-ordered set of data points, identified by namespace + name + **dimensions**. Metrics are **Regional**. They cannot be deleted; they expire after 15 months with no new data.
- **Dimension**: a name/value pair that is part of the metric's identity, **up to 30 per metric**. Each unique combination of dimensions is a separate metric. CloudWatch does **not** aggregate across dimensions of custom metrics. You can only retrieve the combinations you published, or use the metric math `SEARCH` function.
- **Statistics**: Average, Sum, Min, Max, SampleCount, **percentiles (p90/p99)**, trimmed mean and others. Percentiles need raw data points. A statistic set only supports percentiles in narrow cases.
- **Timestamps**: a data point can be up to 2 weeks in the past or 2 hours in the future.

**Resolution and retention**

| Data-point period | Retention | Notes |
|---|---|---|
| < 60 s (high-resolution custom metrics) | 3 hours | Then rolled up |
| 60 s | 15 days | |
| 300 s | 63 days | |
| 3,600 s | 455 days (15 months) | |

- **Standard resolution** = 1-minute granularity. **High resolution** = 1-second granularity, available for **custom metrics only**. You can read a high-resolution metric at periods of 1, 5, 10 or 30 s or any multiple of 60 s.
- **EC2 basic monitoring** = 5-minute metrics, free. **Detailed monitoring** = 1-minute metrics, paid. Set an alarm period of at least the metric's resolution: ≥ 300 s on basic monitoring, ≥ 60 s on detailed.
- **High-resolution alarms** can use a 10 s or 30 s period, at a higher price. Otherwise alarm periods are multiples of 60 s.
- EC2 **does not publish memory or disk-space utilization**: the hypervisor cannot see inside the guest OS. You need the **CloudWatch agent** (§2.4).

**Publishing custom metrics**

| Method | How | Best for | Gotchas |
|---|---|---|---|
| `PutMetricData` API | Synchronous API call per batch | Simple apps, scripts | Each call is billed. High-resolution metrics multiply calls. Throttling at scale. |
| **Embedded Metric Format (EMF)** | Write structured JSON log lines. CloudWatch extracts metrics **asynchronously** from the logs. | **Lambda**, containers, high-cardinality context | No API calls in the hot path. You keep the full log event for drill-down. Needs a **Standard** log class log group. |
| **Statistic sets** | Pre-aggregate Sum/Min/Max/SampleCount per minute | Very high-frequency data | Percentiles generally lost |
| CloudWatch agent (StatsD/collectd/procstat) | The agent publishes for you | OS and process metrics | Agent config is best stored in SSM Parameter Store |
| OpenTelemetry (OTLP) | The CloudWatch agent or ADOT collector sends OTel metrics | New implementations. AWS now recommends OTel for custom metrics. | OTel metrics use labels (up to 150) instead of dimensions |

**Querying and math**
- **Metric math**: arithmetic, `FILL`, `RATE`, `IF`, `SEARCH`, `ANOMALY_DETECTION_BAND`, `SERVICE_QUOTA`, and more. Example: error rate % = `100 * errors / requests`. You can alarm on a math expression.
- **Metrics Insights**: SQL-like queries over metrics, such as `SELECT AVG(CPUUtilization) FROM "AWS/EC2" GROUP BY InstanceType`. You can alarm on a query, including tag-based grouping when you enable resource tags on telemetry.
- **Metric Streams**: a continuous, near-real-time stream of metrics to **Amazon Data Firehose**, and from there to S3, a data lake or a third-party APM (Datadog, Splunk, New Relic). Formats are JSON or OpenTelemetry. Use this instead of polling `GetMetricData` for exports.

### 2.3 CloudWatch Alarms

**Alarm types**

| Type | Watches | Can do |
|---|---|---|
| **Metric alarm** | One metric or one math expression, including anomaly detection bands | SNS, **EC2 actions** (stop/terminate/reboot/recover), **EC2 Auto Scaling** actions, Systems Manager **OpsItem** or **incident**, start a **CloudWatch investigation** |
| **Composite alarm** | A rule expression over other alarms' states (`ALARM(a) AND (ALARM(b) OR NOT OK(c))`) | SNS, OpsItem, incident, investigation. **No EC2 or Auto Scaling actions.** **Not cross-account.** |
| **Log alarm** (newer) | Results of a scheduled CloudWatch Logs Insights query, M-out-of-N | Detect log patterns without building a metric filter first |
| **PromQL alarm** (newer) | A PromQL query on OTel metrics ingested via the CloudWatch OTLP endpoint | Prometheus-style alerting inside CloudWatch |

**States**: `OK`, `ALARM`, `INSUFFICIENT_DATA`. Actions fire **on state change only**. The exception is Auto Scaling actions, which repeat every minute while the alarm stays in the state. Alarm history is kept for **30 days**. `SetAlarmState` lets you **test** actions.

**Evaluation**: *Period* × *Evaluation periods*, with *Datapoints to alarm* ("M out of N"). For example, 3 of 5 one-minute periods breaching. Using M of N instead of N of N cuts flapping on noisy metrics. Maximum evaluation range: 1 day for periods under 1 hour, 7 days for periods of at least 1 hour.

**Treat missing data**: `missing` (default; keep the current state when all data is missing), `notBreaching` (good for sparse error-count metrics), `breaching` (good for heartbeat metrics: no data = dead), `ignore`. A frequent exam trap is an alarm stuck in `INSUFFICIENT_DATA`. Causes: the metric is not emitted, the **dimensions don't match exactly**, or the period is shorter than the metric's resolution.

**Reducing alarm noise (exam favourite)**
1. **Composite alarms**. Page only when, for example, `HighLatency AND HighErrorRate`, or when the canary fails **and** the ALB 5xx alarm fires. Child alarms can have no actions. **Actions suppression** lets a composite alarm stay quiet while a suppressor alarm (such as `MaintenanceWindowActive`) is in ALARM, with configurable wait and extension periods.
2. **Anomaly detection alarms**. CloudWatch trains a model on the metric's history, including hourly, daily and weekly seasonality, and produces an expected **band** (width set in standard deviations). The alarm fires when the value goes outside, above or below the band. Use it for metrics with seasonality where static thresholds are wrong half the day. You can exclude known abnormal periods from training. The `ANOMALY_DETECTION_BAND` function is **not supported for cross-account alarms**.
3. **SLO-based alerting** with Application Signals (§2.7): alert on error-budget burn rate instead of raw thresholds.
4. M-out-of-N evaluation and correct missing-data treatment.

**EC2 alarm actions**: stop, terminate, reboot, **recover**. Recover moves the instance to new hardware, keeping instance ID, private IPs, Elastic IPs and metadata. It is used with the `StatusCheckFailed_System` metric. Many current instance types also have **simplified automatic recovery** on by default. A **reboot** is the action for `StatusCheckFailed_Instance`, which is an OS-level problem.

**Cross-account alarms**: once cross-account functionality is enabled, a metric alarm can watch a metric in another account. Math expressions are supported except `ANOMALY_DETECTION_BAND`, `INSIGHT_RULE` and `SERVICE_QUOTA`. **Composite alarms cannot be cross-account.**

### 2.4 CloudWatch agent

- A single agent for **Linux, Windows and macOS**, on EC2 **and on-premises** servers (on-premises needs IAM credentials or a Systems Manager hybrid activation).
- It collects **memory, disk space, swap, netstat, processes (procstat)**, **StatsD and collectd** custom metrics, **log files**, Windows Event Logs, and OTel/X-Ray traces (it can replace the X-Ray daemon and power Application Signals).
- **Deploy at scale**: install with Systems Manager (Distributor package `AmazonCloudWatchAgent` via Run Command, or a State Manager association). Store the JSON config in **SSM Parameter Store** and have instances fetch it. You can also bake it into the AMI (EC2 Image Builder).
- IAM: an instance profile with `CloudWatchAgentServerPolicy`. Add `CloudWatchAgentAdminPolicy` only on the instance that writes the config to Parameter Store.
- **Compute Optimizer** uses agent-published memory metrics to make memory-aware EC2 recommendations. It can also ingest memory metrics from Datadog, Dynatrace and similar tools.

### 2.5 Amazon CloudWatch Logs

**Structure**: log **group** (the unit for retention, KMS key, class, metric filters, subscriptions and data protection) → log **stream** (one source, such as an instance or container) → log **events**.

**Retention**: **Never expire by default**. Configurable from 1 day to 10 years per log group. Not setting retention is one of the most common hidden costs. Enforce it with a Config rule (`cw-loggroup-retention-period-check`), IaC defaults, or an automated Lambda.

**Encryption**: always encrypted at rest. You can associate a **customer managed KMS key** per log group, which needs a key policy granting the `logs.<region>.amazonaws.com` principal.

**Metric filters**
- Turn matching log events into CloudWatch metrics. Examples: count of `ERROR`, latency values extracted from JSON, CloudTrail `ConsoleLogin` without MFA.
- They **only apply to events ingested after the filter is created**. No backfill.
- Classic pattern: CloudTrail → CloudWatch Logs → metric filter → alarm → SNS for security events (root login, IAM policy change, security group change: the CIS benchmark alarms).

**Subscription filters (real-time streaming)**
- Deliver matching events, usually in under 3 minutes, base64-encoded and gzip-compressed, to **Kinesis Data Streams, Amazon Data Firehose, Lambda, or OpenSearch Service** (OpenSearch via a Lambda-based integration).
- **Up to 5 subscription filters per log group**, plus **one account-level subscription filter per Region**. The account-level filter covers all log groups. Use selection criteria to exclude the destination's own log group and avoid recursion.
- **Cross-account / cross-Region**: the receiving account creates a **destination** resource that wraps a **Kinesis Data Streams or Firehose** stream, with a **destination access policy**. You can grant the whole organization with `aws:PrincipalOrgID`. The source log group and the destination must be in the **same Region**; the stream behind the destination can be in another Region.
- Delivery is at-least-once (duplicates possible). Retryable errors are retried for up to 24 h.
- **Standard log class only.**

**Cross-account cross-Region log centralization** (launched Sept 2025)
- **Centralization rules** defined through AWS Organizations, scoped to the org, OUs or accounts, **copy** log data from source accounts and Regions into log groups in a central account. You can add an optional **backup Region**.
- Events gain `@aws.account` and `@aws.region` fields. Only **new** data is centralized: no history.
- It is the managed alternative to building subscription-filter pipelines purely for log consolidation.

**Analysis features**

| Feature | What it does | Notes |
|---|---|---|
| **Logs Insights** | Interactive query language (also OpenSearch PPL/SQL) across many log groups, including cross-account via OAM | Billed per GB scanned. **Field indexes** cut the data scanned. Saved and scheduled queries (results to S3 or EventBridge). |
| **Live Tail** | Real-time streaming view of incoming events with filtering, for interactive troubleshooting | Standard class only. Billed per session-minute. |
| **Log anomaly detection** | ML pattern detection on log groups that surfaces new or unusual patterns | Standard class only |
| **Contributor Insights** | Top-N contributors from structured logs (top talkers, top error-producing URLs, top IPs) | Also exists for DynamoDB (hot keys) |
| **Export to S3** | `CreateExportTask` batch export | **Not real-time.** For continuous delivery use subscription → Firehose → S3. |
| **Transformation / pipelines** | Parse and normalize logs at ingestion | Subscription filter patterns match the **transformed** event |

**Data protection (masking)**
- A **data protection policy** at **account level** (applies to existing and future log groups) and/or **log group level**. Managed data identifiers cover credentials, financial data, PII, PHI and device IDs; custom identifiers use regex.
- Sensitive data is **masked at ingestion** for all egress: the console, Logs Insights, metric filters and subscriptions. Only principals with **`logs:Unmask`** can see the original.
- Data ingested **before** the policy is not masked. Findings emit the free `LogEventsWithFindings` metric. Audit reports can go to S3, Firehose or another log group.
- Supported in both Standard and Infrequent Access classes.

**Log classes** (a frequent cost question)

| Feature | **Standard** | **Infrequent Access (IA)** |
|---|---|---|
| Price difference | — | **Lower ingestion price per GB**. Storage and Logs Insights charges are the same. |
| Logs Insights queries | Yes | Yes (most commands) |
| Cross-account (OAM), KMS, export to S3, data protection masking | Yes | Yes |
| **Metric filters, subscription filters, Live Tail, EMF, anomaly detection, Container/Lambda Insights ingestion** | Yes | **No** |
| `GetLogEvents` / `FilterLogEvents` | Yes | **No** (query with Logs Insights) |
| Change class later | — | **No. The class is fixed at log group creation.** |

There is also a **Delivery** class used only to route Lambda logs to S3 or Firehose (2-day fixed retention, no rich features).

> **Exam pattern:** "Large volume of debug/audit logs, queried only ad hoc for forensics, no alarms or streaming needed, reduce cost, keep the ability to query" → **new log groups in the Infrequent Access class** with appropriate retention. If the logs need metric filters or subscriptions, they must stay **Standard**.

### 2.6 Cross-account observability and dashboards

**CloudWatch cross-account observability (Observability Access Manager, OAM)**
- **Monitoring account**: a central account that **creates a sink**, one per Region. **Source accounts** **create links** to the sink. Links are managed by the source account; sinks by the monitoring account.
- Shareable telemetry: **metrics** (all or filtered namespaces), **log groups** (all or filtered), **X-Ray traces**, **Application Signals services and SLOs**, **Application Insights** applications, and **Internet Monitor** monitors.
- Limits: a monitoring account can link **up to 100,000 source accounts**. A source account can share with **up to 5 monitoring accounts**. The scope is **within a Region**: set it up in each Region you operate in.
- **Use AWS Organizations** (CloudFormation template or StackSets for an org or OU) so **new accounts are onboarded automatically**.
- An account can be both monitoring and source. It then forwards **only its own** data, not data from its sources: no transitive relay.
- **Cost**: no extra charge for sharing logs and metrics or Application Signals, and the first trace copy is free. Data is not copied; the monitoring account queries it in place.
- In the monitoring account you can search, graph, run Logs Insights, build dashboards and create alarms on source-account data.

**Older "cross-account cross-Region CloudWatch console"** (pre-OAM): it uses a sharing IAM role (`CloudWatch-CrossAccountSharingRole`) in each source account so that a monitoring account can switch context and build **cross-account, cross-Region dashboards**. It still matters for **cross-Region** dashboards, because OAM is per-Region.

**Dashboards**
- Dashboards are **global**: a dashboard can show widgets from **multiple Regions and accounts**. Widgets cover metrics, Logs Insights results, alarms, text, and custom widgets backed by Lambda.
- **Automatic dashboards** per service. **Sharing**: publicly, with specific email addresses (via Cognito), or through SSO (IAM Identity Center/SAML), with no AWS console access needed.
- Use dashboard **variables** to switch between instances or Regions.

### 2.7 Application and infrastructure insight features

| Feature | What it gives you | Exam trigger words |
|---|---|---|
| **Container Insights** | Cluster/service/task/pod/node metrics (CPU, memory, network, restarts) and performance logs (EMF) for **ECS, EKS, Kubernetes on EC2**, with **enhanced observability** for EKS and ECS | "container-level CPU/memory per task/pod", "which pod is restarting" |
| **Lambda Insights** | System-level Lambda metrics (memory used, CPU time, init/cold-start duration, network) via a **Lambda extension layer** | "Lambda memory usage", "cold starts", "right-size Lambda memory" |
| **Database Insights** (replaces the Performance Insights console) | DB load by **wait events, top SQL, hosts, users**; fleet view across RDS/Aurora. **Advanced mode** gives 15 months of retention and execution plans. | "which SQL statement is causing high DB load", "Performance Insights" |
| **Application Signals** | **Automatic APM** for Java, Python, Node.js, .NET on EKS/ECS/EC2/Lambda (via OTel / CloudWatch agent): volume, latency, faults, errors per service/operation/dependency; application map; **SLOs/SLIs**; change events from CloudTrail | "define SLOs", "error budget", "latency SLI", "service map with health", "no code changes APM" |
| **CloudWatch Synthetics** | **Canaries**: scripted Lambda-based checks (Node.js with Puppeteer/Playwright, Python with Selenium) on a schedule. Blueprints: heartbeat, API, broken-link checker, visual monitoring, GUI workflow. Screenshots and HAR files go to S3. Can run **inside a VPC**. | "detect issues before customers do", "test the login flow every 5 minutes", "monitor an internal endpoint" |
| **CloudWatch RUM** | **Real user monitoring**: a JavaScript snippet collects page-load timing, Core Web Vitals, JS errors, HTTP errors and user sessions by browser/device/geography | "actual end-user experience", "client-side errors", "page load by country" |
| **Internet Monitor** | Uses AWS's global network data to measure **internet availability and performance between your users' locations/ISPs (ASNs) and your resources** (VPCs, NLBs, CloudFront distributions, WorkSpaces directories). Suggests better Regions or edge setups. | "ISP outage affecting users in one city", "is it us or the internet?" |
| **Network Flow Monitor** | Lightweight **eBPF agents on EC2/EKS** collect TCP statistics (RTT, retransmissions, timeouts, bytes) between your workloads, AZs, Regions and AWS services, plus a **network health indicator** that tells you whether AWS's network contributed | "packet loss between microservices", "is AWS's network the cause?" |
| **Network Synthetic Monitor** | Active probes from AWS to **on-premises** IPs over Direct Connect/VPN, measuring latency and packet loss | "hybrid connection quality" |
| **Contributor Insights** | Top-N analysis on logs | "top 10 IPs causing 4xx" |
| **CloudWatch Application Insights** | Automatically sets up monitors, alarms and problem detection for common stacks (.NET, SQL Server, IIS, Java, SAP) | "Windows/.NET app, set up monitoring with minimal expertise" |
| **CloudWatch investigations** (AI-assisted, newer) | Generates hypotheses and correlates telemetry during an incident. Can be started from an alarm action. | Emerging, not core for SAP-C02 |

**Application Signals SLOs**: an SLO pairs an **SLI** (a metric such as p99 latency < 300 ms, or availability = 1 − faults/requests) with an **attainment goal** (such as 99.9 %) over a rolling or calendar interval. Application Signals tracks **error budget** and attainment, and you can **alarm on SLO breach and burn rate**. SLOs can be shared across accounts via OAM.

### 2.8 AWS X-Ray and OpenTelemetry (ADOT)

**X-Ray concepts**
- **Segment**: work done by one service for a request, up to 64 KB. **Subsegments** record downstream calls (AWS SDK calls, HTTP, SQL). Services that don't send segments, such as DynamoDB or S3, show up as **inferred nodes**.
- **Trace**: all segments for one request, linked by the **`X-Amzn-Trace-Id`** header that the first instrumented service adds (ALB, API Gateway, Lambda and others propagate it).
- **Service graph / trace map**: nodes and edges with latency, error (4xx), fault (5xx) and throttle (429) rates. **Service graph and trace data are retained for 30 days.**
- **Sampling**: by default the first request each second plus **5 %** of additional requests (a reservoir plus a fixed rate). **Centralized sampling rules** in the console let you trace 100 % of payment calls and 1 % of health checks without redeploying.
- **Annotations** are indexed key-value pairs, **up to 50 per trace**, usable in **filter expressions** and groups (for example `annotation.customer_tier = "gold"`). **Metadata** is not indexed: any type of value, for context only. Exam: "search traces by customer ID" → **annotation**, not metadata.
- **Groups**: a filter expression that gets its own service graph and CloudWatch metrics. **X-Ray Insights** detects anomalies in fault rates and opens insights automatically.
- **Integrations**: Lambda (**active tracing** checkbox), API Gateway (enable tracing per stage), ECS/EKS (sidecar or daemonset collector), Elastic Beanstalk, SNS/SQS (trace header propagation), Step Functions, App Runner. **ALB does not send segments to X-Ray**, but it adds the trace ID header.
- **Cross-account**: share traces through OAM.

**Transaction Search** (CloudWatch): ingest **100 % of spans** as structured logs in the `aws/spans` log group in OTel format, and **index a configurable percentage** as X-Ray trace summaries. You get complete trace search (traces of up to 10,000 spans) without paying to index everything. Metric filters, subscriptions and masking work on spans.

**Direction of travel: X-Ray → OpenTelemetry**
- **AWS Distro for OpenTelemetry (ADOT)** is AWS's supported distribution of OTel SDKs, auto-instrumentation agents (Java, Python, .NET, Node.js), Lambda layers and the **collector**. One instrumentation exports to **X-Ray, CloudWatch (metrics/EMF), Amazon Managed Service for Prometheus**, and third-party backends.
- The **CloudWatch agent** also accepts OTLP and is the collector used by Application Signals.
- The **X-Ray SDKs and daemon** entered **maintenance on 25 Feb 2026, with end of support on 25 Feb 2027**. Existing apps keep working, but new instrumentation should use OpenTelemetry. Exam answers may still say "instrument with the X-Ray SDK". That is correct for SAP-C02 but legacy in practice.

### 2.9 Amazon Managed Service for Prometheus (AMP) and Amazon Managed Grafana

**AMP**
- A serverless, **Prometheus-compatible** metrics store and query engine (**PromQL**). It runs a highly available setup across 3 AZs, with **workspaces** as the unit of isolation.
- Ingestion: Prometheus `remote_write` from a self-managed Prometheus server, the **ADOT collector**, or the **AMP managed collector** (agentless scraper for EKS).
- Retention: **150 days by default, configurable up to 1,095 days (3 years)**. Active series default of **50 M per workspace** (adjustable, up to 1.5 B). Managed **recording rules** and **Alertmanager** (alerts to SNS).
- Security: **IAM SigV4** for ingest and query, VPC interface endpoints, KMS (customer managed keys supported).
- Use it for "**existing Prometheus/Kubernetes monitoring, PromQL dashboards, high-cardinality container metrics, reduce operational overhead of self-managed Prometheus/Thanos**".

**Amazon Managed Grafana (AMG)**
- Managed Grafana **workspaces** (current versions include Grafana 12.x). Authentication via **IAM Identity Center or SAML**. Grafana roles are Admin, Editor and Viewer.
- Data sources: **CloudWatch, AMP, X-Ray, OpenSearch, Athena, Redshift, Timestream, IoT SiteWise**, and others. Enterprise plugins (Splunk, Datadog, ServiceNow and more) need an additional license.
- **Cross-account**: workspace data sources can assume roles in other accounts, or use **Organizations** integration to provision access to OUs.
- **VPC connectivity** to private data sources. Customer managed KMS keys (2026). Grafana alerting.
- Use it for "**single pane of glass across CloudWatch, Prometheus and third-party data sources; teams already use Grafana; SSO users without AWS console access**".

### 2.10 Centralized logging architectures, retention and cost

**The landing-zone baseline (D1 Task 1.4)**

| Log source | Recommended destination | Mechanism |
|---|---|---|
| **CloudTrail** management (and selected data) events | **S3 bucket in the Log Archive account** | **Organization trail** created from the management account or a **delegated administrator**. Member accounts cannot modify or delete it. |
| AWS Config history and snapshots | Central S3 bucket (Log Archive) + **aggregator** in the Audit/Security account | Delivery channel per account (Control Tower sets this up) |
| VPC Flow Logs | S3 (cheapest, Parquet option, Hive partitions) or CloudWatch Logs (for metric filters/alarms) | Flow log per VPC/subnet/ENI, centrally enforced via Config/IaC |
| ALB/NLB/CloudFront access logs, S3 server access logs, WAF logs | S3 (WAF also supports CloudWatch Logs and Firehose) | Per-resource settings, enforced via Config rules |
| Application logs | CloudWatch Logs, then **centralization rules** or subscription → **Firehose** → S3/OpenSearch/Splunk | CloudWatch agent / FireLens / Lambda native |
| Security findings and normalized logs | **Amazon Security Lake** (delegated admin in the Audit account) | OCSF + Parquet in S3 you own |

**CloudTrail essentials for this chapter**
- **Event history**: 90 days of management events per Region, free, viewable in the console. A **trail** is needed for long-term retention.
- **Log file integrity validation**: SHA-256 hash digest files, so you can prove logs were not altered. Combine with **S3 Object Lock (compliance mode)**, MFA delete, a restrictive bucket policy and SCPs that deny `cloudtrail:StopLogging` / `DeleteTrail`.
- **CloudTrail Insights**: detects unusual API call rates or error rates on management events.
- **CloudTrail → CloudWatch Logs**: for metric-filter alarms on security events. The org trail can deliver to a log group in the management account.
- **CloudTrail Lake**: a managed SQL-queryable event data store. **Closed to new customers since 31 May 2026.** For new designs, query trail logs in S3 with **Athena**, or use CloudWatch.

**Amazon Security Lake**
- Automatically centralizes security data from **CloudTrail management and data events (S3, Lambda), VPC Flow Logs, Route 53 Resolver query logs, Security Hub CSPM findings, EKS audit logs, and AWS WAF logs**, plus **custom and third-party sources**. Data is stored in **S3 in your account**, converted to **Apache Parquet** and the **OCSF** schema.
- Multi-account, multi-Region through a **delegated administrator**, with **rollup Regions** for data residency.
- **Subscribers** get **data access** (S3 notifications) or **query access** (Lake Formation tables, queried via Athena/Redshift). Lifecycle and retention are managed for you.
- Use it for "**normalize security logs from AWS and third parties into an open schema for SIEM/analytics, least operational overhead**".

**Classic streaming pipeline**

```text
 Source accounts                     Log Archive / Logging account
 ┌────────────────┐  subscription   ┌───────────────────────────────────────────┐
 │ CW Logs groups │ ──────────────► │ CWL Destination ─► Firehose ─► S3 (Parquet│
 │ (account-level │  (destination   │   (policy:            │       partitioned, │
 │  subscription  │   policy w/     │    PrincipalOrgID)    │       lifecycle →  │
 │  filter)       │   OrgID)        │                       │       Glacier)     │
 └────────────────┘                 │                       └─► OpenSearch (hot  │
                                    │                            search, 30 days)│
                                    └───────────────────────────────────────────┘
```

**Retention and cost levers**
- Set **CloudWatch Logs retention** on every log group (the default is never expire). Keep hot data short (for example 30–90 days) and archive to **S3 with lifecycle** to Glacier Instant Retrieval / Flexible Retrieval / Deep Archive for multi-year compliance.
- Use the **Infrequent Access log class** for ad-hoc forensic logs. Send **VPC Flow Logs to S3** instead of CloudWatch Logs when you don't need alarms.
- Ingestion is usually the largest CloudWatch Logs cost: **filter at source** (log levels, sampling of debug logs).
- **Logs Insights is billed per GB scanned**: use field indexes, narrow time ranges and specific log groups.
- **OpenSearch**: use UltraWarm/cold storage for older indices, or OpenSearch Serverless for spiky search.
- **Athena on S3**: store as Parquet with partitions to cut scan costs.

### 2.11 AWS Config — configuration history, change tracking and compliance

- The **configuration recorder** records **configuration items (CIs)** for supported resource types: attributes, relationships, and links to the related CloudTrail events. Recording frequency is **continuous** or **periodic (daily)**. Use daily for high-churn types to cut cost. You can include or exclude resource types.
- The **delivery channel** sends configuration history files and snapshots to **S3** (often the Log Archive bucket) and notifications to **SNS**. Configuration changes also go to **EventBridge**.
- **Config rules**: **AWS managed rules** (hundreds) or **custom rules** (Lambda, or **Guard** custom policy rules). Triggers are **configuration change** and/or **periodic**. Evaluation modes are **detective** and **proactive** (evaluate a resource before it is created, for example from CloudFormation hooks).
- **Conformance packs**: a YAML bundle of rules and remediation actions deployed as one unit. Sample packs exist for CIS, PCI DSS, HIPAA, NIST, and others. **Organization conformance packs / organization Config rules** are deployed from the management account or a **delegated administrator** to all accounts.
- **Remediation**: a rule links to a **Systems Manager Automation runbook**, either **manual** (button) or **automatic**, with retry attempts. Examples: `AWS-DisableS3BucketPublicReadWrite`, enabling encryption, or attaching a required tag.
- **Aggregator**: a **read-only** multi-account, multi-Region view of compliance and inventory, org-wide via Organizations. You **cannot remediate from an aggregator**: remediation runs in the source account. **Advanced queries** use SQL-like `SELECT` syntax over current configuration state, including across an aggregator. Example: "all EBS volumes not encrypted across the org".
- **Configuration timeline**: "What did this security group look like before the outage, and who changed it?" The timeline shows each CI version with links to the CloudTrail event.
- Pricing: per CI recorded, per rule evaluation, and per conformance pack evaluation. Watch costs for high-churn resources such as ephemeral containers' ENIs, and use periodic recording or exclusions.
- **Config vs CloudTrail**: Config = **what** the resource looks like and whether it's compliant. CloudTrail = **who** called **which API** and when. They complement each other.

### 2.12 Amazon EventBridge for operational automation

EventBridge is the **event router** that turns signals into actions. AWS services emit events to the **default event bus** in each account and Region.

| Event (source / detail-type) | Typical automated response |
|---|---|
| `aws.health` / **AWS Health Event** (such as `AWS_EC2_INSTANCE_RETIREMENT_SCHEDULED`, scheduledChange, issue) | SSM Automation to stop/start the instance onto new hardware, open a ticket, notify the owner by tag |
| `aws.ec2` / **EC2 Instance State-change Notification** | Update a CMDB, deregister from DNS, clean up |
| `aws.config` / **Config Rules Compliance Change** | Notify or trigger remediation workflows (Step Functions) |
| `aws.guardduty` / **GuardDuty Finding** | Isolate the instance (swap its security group), snapshot EBS, revoke credentials |
| `aws.securityhub` / **Security Hub Findings - Imported** | Route to Jira/ServiceNow, auto-remediate |
| `aws.autoscaling` lifecycle events | Drain connections, run configuration |
| `aws.trustedadvisor` check refresh (in us-east-1) | Notify about exposed access keys or quota thresholds |
| `aws.cloudwatch` / **CloudWatch Alarm State Change** | Fan-out beyond SNS: Step Functions, SSM, Lambda |
| **AWS API Call via CloudTrail** (`aws.<service>` with detail-type `AWS API Call via CloudTrail`) | React to a specific API call, such as `PutBucketPolicy` or `AuthorizeSecurityGroupIngress` |
| **Scheduled rules / EventBridge Scheduler** | Nightly stop of dev instances, periodic reports |

- **Targets**: Lambda, **SSM Automation**, SSM Run Command, Step Functions, SNS, SQS, ECS tasks, Kinesis, Firehose, API destinations (SaaS webhooks), and **event buses in other accounts/Regions**.
- **Cross-account**: send events to a **central event bus** in an Ops/Security account. The bus's resource policy can allow the whole org via `aws:PrincipalOrgID`.
- **Archive and replay**, **input transformers**, DLQs and retry policies on targets. **EventBridge Pipes** for point-to-point source → enrichment → target.

### 2.13 AWS Health — Health Dashboard, Health API and organizational view

- **AWS Health Dashboard** has two views: **Service health** (public status of all services and Regions) and **Your account health** (events **affecting your account's resources**, such as an EBS volume on degraded hardware, instance retirement, RDS maintenance or certificate expiry). Event categories: **issue**, **scheduledChange**, **accountNotification**, **investigation**.
- **Health API**: needs **Business Support+, Enterprise Support or Unified Operations** (until the transition, legacy Business, Enterprise On-Ramp and Enterprise plans also work). Otherwise you get `SubscriptionRequiredException`. The API is active-passive across **us-east-1 (active)** and **us-east-2 (passive)** behind a **global endpoint** you resolve through DNS.
- **Organizational view**: enabled from the **management account** (Organizations with all features). It aggregates events across all accounts. Organizational events are kept **90 days**, a hard limit.
- **Delegated administrator**: register **up to 5 member accounts** (`RegisterDelegatedAdministrator`, principal `health.amazonaws.com`). They can use the organizational view in the console and through the API with the right support plan. This is the best practice: keep the management account locked down.
- **EventBridge with organizational view**: when organizational view is on, the **management account or delegated administrator receives a single feed of Health events from all accounts** in EventBridge. One rule there can route every account's events, with no per-account rules to deploy. Per-account rules keep working too.
- Also: **AWS User Notifications** for Health event notifications, and the "AWS Health Aware" open-source reference solution for Slack/Teams/email routing.

### 2.14 AWS Trusted Advisor

- **Check categories**: **Cost optimization, Performance, Security, Fault tolerance, Service limits (quotas), Operational excellence**. Some checks are powered by **AWS Config** or **Security Hub CSPM** controls, and some cost checks by **Compute Optimizer**.
- **Support-plan requirements**:
  - **Basic**: all **Service Limits** checks plus **selected Security and Fault tolerance** checks (S3 bucket permissions, security groups with unrestricted ports, IAM use, MFA on root, EBS public snapshots, RDS public snapshots, and so on). Security checks need a manual refresh.
  - **All checks, automatic weekly refresh, Trusted Advisor API, EventBridge integration**: **Business Support+, Enterprise Support or Unified Operations**. The exam says "Business or Enterprise Support".
- **Organizational view**: aggregate check results across all accounts. Requires Organizations with all features and a **management account on one of those plans**. It enables trusted access and creates the `AWSServiceRoleForTrustedAdvisorReporting` role. Reports in JSON/CSV (up to 50 kept) can be queried with Athena or QuickSight. Each member account still only gets checks matching **its own** support plan.
- **Trusted Advisor Priority**: prioritized, context-aware recommendations from your **AWS account team** and from services (Trusted Advisor, Security Hub CSPM, Well-Architected). Requires **Enterprise Support or Unified Operations**, an organization with trusted access, and **up to 5 delegated administrators**. Recommendations move through acknowledge → resolve/dismiss.
- Exam: "check whether we're near **service quotas** across accounts" → Trusted Advisor service limits checks / **Service Quotas** (with CloudWatch alarms on usage metrics). "**Exposed access keys** on GitHub" → Trusted Advisor (exposed access keys check) + Health event, automated with EventBridge.

### 2.15 AWS Compute Optimizer

- An ML-based **right-sizing and idle-resource** service. You must **opt in**, either standalone or as the **management account for the whole org** (delegated admin supported).
- **Supported resources** (verified Oct 2026): **EC2 instances, EC2 Auto Scaling groups, EBS volumes, Lambda functions, ECS services on Fargate, commercial software licenses, Aurora and RDS databases, NAT gateways, DynamoDB, ElastiCache, MemoryDB, DocumentDB, WorkSpaces, SageMaker AI**. Older exam material lists only EC2, ASG, EBS and Lambda, sometimes ECS on Fargate.
- **Lookback**: **14 days** of CloudWatch metrics by default. **Enhanced infrastructure metrics** (paid) extend it to **93 days**. That matters for monthly or quarterly cycles such as month-end batch.
- **Memory**: EC2 memory recommendations need memory metrics from the **CloudWatch agent** (or ingestion from Datadog/Dynatrace). Without them, recommendations are CPU/network/disk-only and flagged with lower confidence.
- **Preferences**: CPU/memory headroom and thresholds, lookback period, preferred instance families (for example "Graviton only"), and **savings estimation mode** that accounts for RIs/Savings Plans discounts.
- Findings: **Under-provisioned, Over-provisioned, Optimized**, plus **idle**. Up to 3 options per resource with projected utilization and **performance risk**. Export to S3. Findings also surface in **Cost Optimization Hub** (Chapter 16).

### 2.16 AWS Systems Manager — operations features

| Capability | What it does | Status / notes |
|---|---|---|
| **Explorer** | Customizable **ops dashboard** aggregating OpsData (OpsItems, patch compliance, inventory, Config compliance, Trusted Advisor, Security Hub CSPM findings) **across accounts and Regions** via **resource data sync**, with a delegated admin for the org | Available |
| **OpsCenter** | Central place to view, investigate and resolve **OpsItems** (operational issues). OpsItems are created automatically from **CloudWatch alarms, EventBridge rules, Config compliance changes, Security Hub CSPM findings, DevOps Guru**. Deduplication, related resources, linked runbooks, multi-account via delegated admin. | Available. **AWS's recommended alternative to Incident Manager** for new customers. |
| **Automation** | **Runbooks** (AWS-owned such as `AWS-RestartEC2Instance`, `AWS-CreateSnapshot`, `AWSSupport-*` troubleshooting runbooks, or custom YAML/JSON with `aws:executeScript` Python/PowerShell steps). **Approval steps, rate control (concurrency/error thresholds), multi-account/multi-Region execution.** Triggered by EventBridge, Config remediation, OpsItems, Maintenance Windows, State Manager. | Available. The engine behind "operations as code". |
| **Incident Manager** | Response plans, on-call **contacts and escalation plans**, engagement (SMS/voice/email), chat channel, timeline, **post-incident analysis** templates, runbook auto-start, cross-Region replication set | **Closed to new customers since 7 Nov 2025.** Existing customers continue; no new features. Expect it in exam answers for "automated incident response with escalation". |
| **Change Manager** | Change templates, approvals, integration with Change Calendar | **Closed to new customers since 7 Nov 2025** |
| **Change Calendar** | **Open/closed** calendars (business events, freeze periods). Automation runbooks and Maintenance Windows can check the calendar state and **block changes during freezes**. | Available |
| **Maintenance Windows** | Scheduled windows that run Run Command, Automation, Lambda or Step Functions tasks against targets | Available |
| **Patch Manager** | **Patch baselines** (predefined or custom; auto-approval delays; approved/rejected lists), **patch policies** via **Quick Setup** across the **org and Regions**, `Scan` vs `Scan and install`, **compliance reporting** (Compliance dashboard; **resource data sync → S3 → Athena/QuickSight**; Security Hub CSPM integration). Linux, Windows and macOS. | Available |
| **Inventory** | Collects OS, applications, files, network config, Windows updates, services and custom inventory from managed nodes. Query across accounts with resource data sync + Athena. | Available |
| **State Manager** | Associations that **enforce desired state** on a schedule (install the agent, configure settings) and correct drift | Available |
| **Session Manager / Run Command / Fleet Manager** | Shell access without SSH/bastion (logged to S3/CloudWatch), ad-hoc commands at scale, node management UI | Available |

> **Exam mapping of Systems Manager to the Operational Excellence pillar:** runbook as code → **Automation**. "Who's on call and how do we escalate?" → **Incident Manager** (legacy) or a partner tool + **OpsCenter**. Freeze periods → **Change Calendar**. Patch compliance evidence → **Patch Manager + resource data sync**. Ops dashboard across accounts → **Explorer**.

### 2.17 Well-Architected Tool and the Operational Excellence pillar

**AWS Well-Architected Tool** (free)
- Define a **workload**, answer the pillar questions against **lenses** (the Framework, Serverless, SaaS, Financial Services, Generative AI and others, plus your own **custom lenses**). It identifies **high-risk issues (HRIs) and medium-risk issues (MRIs)**.
- Generate an **improvement plan**, save **milestones** to track progress over time, **share** workloads and lenses with other accounts or the org, and use **profiles** (business context that prioritizes questions) and **review templates**.
- Integrations: **Trusted Advisor** checks linked to questions, **Jira** sync of improvement items, and an API for automation. Prioritized items can also appear in Trusted Advisor Priority.

**Operational Excellence design principles (current framework)**
1. **Organize teams around business outcomes**
2. **Implement observability for actionable insights**
3. **Safely automate where possible** (operations as code, with guardrails such as rate control, error thresholds and approvals)
4. **Make frequent, small, reversible changes**
5. **Refine operations procedures frequently**
6. **Anticipate failure** (pre-mortems, game days, chaos engineering)
7. **Learn from all operational events and metrics**
8. **Use managed services**

Best-practice areas: **Organization, Prepare, Operate, Evolve**.

**Terms the exam uses**
- **Runbook**: a predefined procedure that achieves a **specific known outcome**, such as "rotate the certificate" or "fail over the database". It should be automated: an **SSM Automation runbook**.
- **Playbook**: an investigative guide to **find the cause** of an issue, such as "API latency high: check X, then Y". Playbooks often invoke runbooks once the cause is known.
- **Post-incident analysis** (Amazon calls it **Correction of Errors, COE**): blameless, uses **5 Whys**, produces action items with owners. The goal is to fix the **systemic** cause, for example by adding automation, guardrails or alarms, not to retrain a person.
- **Game days**: scheduled simulations of failures or events (with **AWS Fault Injection Service**: stop instances, inject API errors, AZ power interruption scenarios) to test runbooks, alarms and team response.
- **Operational readiness reviews (ORR)**: a checklist before go-live.
- **Deployment safety** ties to Chapter 14: canary/linear deployments with **CloudWatch alarm-based automatic rollback** (CodeDeploy, Lambda aliases, ECS blue/green), feature flags (AppConfig).

> **Emerging / SAP-C03 preview (not core):** AWS Fault Injection Service scenario library (AZ power interruption, cross-Region connectivity), **AWS Resilience Hub** (resilience scores against RTO/RPO policies, recommended alarms/SOPs/FIS experiments), and **CloudWatch investigations** (AI-assisted root-cause hypotheses).

---

## 3. Architecture patterns

### Pattern 1 — Organization-wide central observability (monitoring account)

```text
                   AWS Organizations (all features)
   ┌──────────────────────────────────────────────────────────────────┐
   │  Workload OU accounts (source)            Ops/Monitoring account │
   │  ┌───────────────┐   OAM link              ┌───────────────────┐ │
   │  │ metrics, logs │ ─────────────────────►  │ OAM SINK (per     │ │
   │  │ traces, SLOs  │   (deployed by          │ Region)           │ │
   │  └───────────────┘    StackSets / org      │  • dashboards     │ │
   │  ┌───────────────┐    template; new        │  • alarms         │ │
   │  │ account N...  │ ─► accounts auto-link)  │  • Logs Insights  │ │
   │  └───────────────┘                         │  • trace map/SLOs │ │
   │                                            │  • Managed Grafana│ │
   │                                            └───────────────────┘ │
   └──────────────────────────────────────────────────────────────────┘
```
- **When to use it**: a central SRE/NOC team, many accounts, and a need to query data in place without copying it.
- **Trade-offs**: it is per-Region, so repeat it in every Region. There is no transitive relay. Composite alarms can't span accounts. Data stays subject to each source account's retention. If you need **long-term, immutable, consolidated copies**, add Pattern 2.

### Pattern 2 — Centralized logging and audit archive

```text
 Management acct ──► ORG CLOUDTRAIL ───────────────┐
 (or delegated admin)                              ▼
 Every account: Config delivery ─────► LOG ARCHIVE ACCOUNT
 Every VPC: Flow Logs (S3) ──────────► ┌──────────────────────────────┐
 ALB/CloudFront/WAF logs ────────────► │ S3 buckets: SSE-KMS, Object  │
                                       │ Lock (compliance), lifecycle │
 CW Logs (apps) ── centralization ───► │ → Glacier Deep Archive; deny │
        rules / subscription→Firehose  │ delete via bucket policy+SCP │
                                       └────────────┬─────────────────┘
                                                    │ Athena / Glue
 AUDIT/SECURITY ACCOUNT (delegated admins)          ▼
   Security Lake (OCSF/Parquet) · Security Hub · GuardDuty · Config aggregator
```
- **When to use it**: compliance (PCI, SOX, HIPAA), forensic readiness, 1–10-year retention.
- **Key controls**:
  - A separate Log Archive account with very limited human access.
  - **SCPs that deny** `cloudtrail:StopLogging`, `DeleteTrail`, `config:StopConfigurationRecorder`, and `logs:DeleteLogGroup` on protected groups.
  - **Log file integrity validation** and S3 **Object Lock**.
- **Trade-offs**: S3 + Athena is cheapest for rare queries. OpenSearch gives interactive search but is costly at scale. Security Lake gives normalized security analytics and SIEM subscribers.

### Pattern 3 — Alarm → automated remediation (operations as code)

```text
 CloudWatch alarm ──► (state change event) ──► EventBridge rule
   (metric / composite / anomaly)                   │
        │                                           ├─► SSM Automation runbook
        └─► alarm action: OpsItem in OpsCenter ◄────┤    (rate control, approval,
             (runbook linked; humans if needed)     │     Change Calendar check)
                                                    └─► SNS → chat / pager
```
- **Examples**: disk > 85 % → a runbook expands the EBS volume and filesystem. JVM heap alarm → restart the service with Run Command. `StatusCheckFailed_System` → the EC2 **recover** action directly.
- **Guardrails**: idempotent runbooks, concurrency and error thresholds, approval steps for destructive actions, freeze windows via Change Calendar, and an audit trail in CloudTrail.

### Pattern 4 — AWS Health organizational event routing

```text
 All member accounts' Health events
          │ (organizational view enabled in management account)
          ▼
 Delegated admin (Ops account) ── EventBridge rule (source aws.health,
          │                        eventTypeCategory = scheduledChange)
          ├─► Lambda: look up resource owner tag → create ticket
          ├─► SSM Automation: stop/start instance before retirement date
          └─► SNS / Slack (AWS User Notifications / Chatbot)
```
- **When to use it**: to handle **instance retirements, RDS/ElastiCache maintenance, certificate expiry and operational issues** proactively across hundreds of accounts.
- **Note**: organizational view feeds EventBridge in the management or delegated-admin account, so you do **not** need to deploy rules into every account with StackSets. That older approach still works but carries more overhead.

### Pattern 5 — Continuous compliance with AWS Config

```text
 Delegated admin (Security acct)
   └─ Organization conformance pack (rules + remediation) ──► all accounts
        Non-compliant resource ─► Config rule NON_COMPLIANT
              ├─► auto-remediation: SSM Automation (in the member account)
              └─► EventBridge "Config Rules Compliance Change" → Security Hub / ticket
   └─ Config aggregator (org-wide, all Regions) ─► advanced queries, dashboards
```
- **When to use it**: "detect and automatically correct drift from the security baseline across the org".
- **Trade-offs**: Config is **detective**: it acts minutes after the change. For **preventive** controls, use SCPs/RCPs, IAM permission boundaries, and Control Tower proactive controls (CloudFormation hooks). See Chapter 3.

### Pattern 6 — Patch compliance at scale

```text
 Quick Setup patch policy (org / OUs / Regions)
    ├─ Patch baselines (OS-specific, auto-approve after N days)
    ├─ Schedule: Scan daily, Install in Maintenance Window (Change Calendar aware)
    └─ Compliance data ─► Resource Data Sync ─► central S3 ─► Athena / QuickSight
                                            └─► Security Hub CSPM / Explorer
```

### Pattern 7 — End-to-end user-experience monitoring

```text
 Users ─► CloudFront ─► ALB ─► ECS services ─► Aurora / DynamoDB
   ▲          │                 │ (OTel auto-instrumentation via CW agent)
   │ RUM      │ Internet Monitor│ Application Signals: service map, SLOs
   │ (browser)│ (ISP/city)      │ X-Ray traces / Transaction Search
 Synthetics canaries (24x7 scripted login/checkout, from multiple Regions)
          └─► Composite alarm: (canary failing AND SLO burn rate high) → page
```

---

## 4. Continuous-improvement scenario playbook

### 4.1 "The existing application is slow"

**Step 1 — Find the bottleneck. Measure before you change anything.**

| Layer | Where to look | Signals |
|---|---|---|
| End user / edge | CloudWatch **RUM**, **Synthetics**, CloudFront metrics (`CacheHitRate`, `OriginLatency`), **Internet Monitor** | Slow only for one geography or ISP → edge or internet. Slow everywhere → backend. |
| Load balancer | ALB `TargetResponseTime` (p99), `RequestCount`, `HTTPCode_Target_5XX_Count` | High target response time → app or DB |
| Application | **X-Ray / Application Signals** trace map and segment timelines, **Lambda Insights**, **Container Insights** | Which downstream call dominates latency; cold starts; CPU throttling in containers |
| Compute | CPU, memory (agent), `CPUCreditBalance` (T family), **Compute Optimizer** "under-provisioned" findings | Saturation or credit exhaustion |
| Database | **Database Insights / Performance Insights** (DB load by wait event, top SQL), `ReadLatency`, `DatabaseConnections`, `ReplicaLag`, DynamoDB `ThrottledRequests`, **Contributor Insights** (hot keys) | Expensive queries, lock waits, connection storms, hot partitions |
| Storage | EBS `VolumeQueueLength`, `BurstBalance` (gp2), throughput vs volume limit; EFS `PercentIOLimit`, burst credits | IOPS or throughput ceiling |

**Step 2 — Apply the matching fix.**

| Bottleneck found | Preferred fix (managed, least change) |
|---|---|
| Origin serves static or cacheable content | **CloudFront** (cache policies, Origin Shield), with an S3 origin for static assets |
| Repeated identical reads on a relational DB | **ElastiCache** (Valkey / Redis OSS / Memcached) with lazy loading or write-through; **Aurora Replicas / RDS read replicas** behind the reader endpoint |
| Repeated DynamoDB reads that need microsecond latency | **DAX** (API-compatible, minimal code change) |
| Heavy SQL or missing indexes | Tune queries using top SQL; add indexes; move to Aurora (higher throughput); larger instance class; **Aurora Serverless v2** for spiky load |
| Too many DB connections (Lambda fan-out) | **RDS Proxy** (pooling; also faster failover) |
| CPU-bound fleet saturating | Scale out (**ASG target tracking**); right-size via Compute Optimizer; **Graviton** (better price-performance); newer instance generation |
| Long-running synchronous work in the request path | **Go asynchronous**: SQS / SNS / EventBridge with workers, or Step Functions. Return 202 and let the client poll or use a WebSocket. |
| Slow Lambda | Increase memory (CPU scales with memory); Provisioned Concurrency or SnapStart for cold starts; reuse connections outside the handler |
| DynamoDB hot partition | Better partition key or write sharding; on-demand mode; DAX for reads |
| Users in other Regions far from the app | CloudFront, **Global Accelerator**, multi-Region read replicas (Aurora Global Database, DynamoDB global tables) |
| EBS IOPS ceiling | gp2 → **gp3** (provision IOPS and throughput independently), or io2 Block Express; an EBS-optimized instance with enough bandwidth |
| Network between instances | Cluster placement groups, ENA/EFA, instances with more bandwidth; confirm with Network Flow Monitor |

### 4.2 "The existing application has outages"

| Weakness | Fix |
|---|---|
| Single instance / single AZ | **Multi-AZ**: ASG across 2–3 AZs behind an ALB; RDS Multi-AZ or Aurora with replicas in other AZs; one NAT gateway per AZ |
| Unhealthy instances keep receiving traffic | ALB **health checks** on a meaningful path (weigh deep vs shallow checks); ASG uses the **ELB health check type** with a suitable grace period |
| Instance hardware failure | EC2 **auto recovery** (alarm action or simplified automatic recovery); ASG replacement |
| Tight coupling, so downstream failures cascade | **Decouple** with SQS/SNS/EventBridge; **retries with exponential backoff and jitter**; **circuit breakers**; timeouts; bulkheads; idempotent consumers; DLQs |
| Overload during spikes | Auto Scaling (target tracking plus **predictive scaling**); throttling at API Gateway (usage plans); load shedding; queue-based load leveling |
| Bad deployments cause outages | Blue/green or canary with **automatic rollback on CloudWatch alarms**; small, reversible changes; feature flags |
| Regional dependency | A multi-Region DR strategy that matches RTO/RPO (Chapters 7 and 9): pilot light, warm standby, active-active; Route 53 failover / ARC |
| Unknown failure modes | **Game days with FIS**; Resilience Hub assessments; ORRs |
| DNS or certificate expiry | ACM managed renewal plus Health/EventBridge notifications; Route 53 health checks |

### 4.3 "Security findings are increasing"

| Problem | Fix |
|---|---|
| No single view of findings | **Security Hub** (CSPM standards: AWS FSBP, CIS, PCI, NIST) aggregated in a delegated-admin account across the org and Regions; the new **Security Hub** for correlated risk |
| Config drift / misconfigurations | **Config** org conformance packs with **automatic remediation** (SSM Automation); preventive **SCPs/RCPs** and Control Tower controls to stop recurrence |
| Over-permissive IAM / external access | **IAM Access Analyzer**: external access findings, **unused access** findings, policy validation, custom policy checks in CI/CD; least privilege based on last-accessed data |
| Unpatched instances / vulnerable images | **Patch Manager** patch policies; **Amazon Inspector** continuous scanning (EC2, ECR images, Lambda); golden AMIs via Image Builder |
| Threats / compromised credentials | **GuardDuty** org-wide (plus S3, EKS, RDS, Lambda, Malware Protection, Runtime Monitoring) → EventBridge → automated containment |
| Sensitive data exposure | **Macie** on S3; CloudWatch Logs **data protection** masking; KMS encryption by default |
| Too many findings, no prioritization | Security Hub automation rules (suppress or raise severity), Trusted Advisor Priority, Detective for investigation |

### 4.4 "Operational toil is high"

| Toil | Fix |
|---|---|
| Manual patching / SSH into boxes | Patch Manager, **Session Manager** (no bastion), Run Command, State Manager |
| Manual responses to alarms | **SSM Automation runbooks** triggered by EventBridge or alarms; OpsCenter with linked runbooks |
| Self-managed databases, brokers, Kafka, Elasticsearch or Prometheus | **Managed services**: RDS/Aurora, Amazon MQ, MSK, OpenSearch Service, AMP/AMG |
| EC2 fleet for a simple web app or API | Containers on **Fargate**, App Runner, or **Lambda** + API Gateway |
| Snowflake environments | **IaC** (CloudFormation/CDK/Terraform), StackSets, Service Catalog, Control Tower Account Factory (Chapter 14) |
| Manual compliance evidence | Config conformance packs, **Audit Manager**, Security Hub, resource data sync reports |
| Manual scaling and right-sizing | Auto Scaling, Compute Optimizer recommendations, Aurora Serverless v2, DynamoDB on-demand |

---

## 5. Troubleshooting common symptoms (root cause → fix)

| Symptom / metric | Likely root cause(s) | Fix |
|---|---|---|
| **ALB HTTP 502** (`HTTPCode_ELB_502_Count`) | The target sent a TCP RST/FIN while a request was outstanding, usually because the **target's keep-alive timeout is shorter than the ALB idle timeout** (default 60 s). Also: malformed response, or response headers > 32 KB; deregistration delay too short during a deploy; Lambda target error/throttle/timeout or response > 1 MB; TLS handshake error to the target. | Set the app keep-alive **longer than the ALB idle timeout**; fix app responses; lengthen the deregistration delay; fix Lambda errors or concurrency; correct the target certificate/ciphers |
| **ALB HTTP 503** | The target group has **no registered targets** (or all are in the `unused` state). Examples: the ASG scaled to zero, a deployment deregistered everything, or a listener rule points to an empty target group. If all targets are *unhealthy*, the ALB fails open and still routes to them. | Register targets; fix ASG minimum capacity; fix listener rules or the deployment process |
| **ALB HTTP 504** | The target didn't respond within the **idle timeout**, or couldn't be reached within the 10 s connection timeout; a NACL blocks return traffic on **ephemeral ports 1024–65535**; a long-running request | Optimize the request or make it async; raise the idle timeout if justified; fix NACLs/SGs; scale targets |
| **ALB HTTP 460** | The client closed the connection before the ALB idle timeout (client timeout shorter than backend processing time) | Speed up the backend or align the client timeout |
| `HTTPCode_Target_5XX_Count` rising (not `ELB_5XX`) | Application errors | App logs and X-Ray; roll back the recent deployment |
| **API Gateway 429 Too Many Requests** | The account-level per-Region throttle (default 10,000 rps steady / 5,000 burst, soft quota), stage/method throttling, or an API key exceeding its **usage plan** rate or quota | Request a quota increase; tune stage/method limits; enable API caching; per-client usage plans; clients retry with **exponential backoff + jitter** |
| **API Gateway 502** | The Lambda proxy integration returned a malformed response (not the required JSON shape), or a Lambda error | Fix the response format; handle errors |
| **API Gateway 504** | Integration timeout: 29 s default for REST APIs. Regional and private REST APIs can raise it with a quota request. | Async pattern (SQS/Step Functions with polling or WebSocket); optimize the backend |
| **Lambda throttles** (`Throttles`, `TooManyRequestsException` / 429) | The Regional concurrency quota (default 1,000, soft) is exhausted; **reserved concurrency** set too low on the function; other functions consuming the pool; burst scaling rate | Request a concurrency increase; set reserved concurrency for critical functions; **Provisioned Concurrency**; buffer with **SQS** and set maximum concurrency on the event source mapping |
| Lambda high `Duration` / timeouts | Slow downstream; memory too low (CPU scales with memory); new connections on every invocation; cold starts | Increase memory (use Lambda Insights / Power Tuning); reuse clients; RDS Proxy; Provisioned Concurrency / SnapStart |
| **DynamoDB `ProvisionedThroughputExceededException`** / `ThrottledRequests` | Under-provisioned table or GSI; **hot partition key**; an under-provisioned GSI back-pressuring the base table; an on-demand table exceeding about 2× its previous peak quickly | Auto scaling or **on-demand**; better key design or write sharding; provision GSIs adequately; **DAX** for read-heavy load; **Contributor Insights** to find hot keys; SDK retries with backoff |
| **RDS "too many connections"** / `DatabaseConnections` at maximum | Lambda fan-out, or the app opening a connection per request; connection leaks; `max_connections` (derived from memory) too small | **RDS Proxy**; connection pooling; fix leaks; larger instance class; limit Lambda concurrency |
| RDS high CPU / read latency | Expensive queries, missing indexes, read-heavy load | Database Insights top SQL; indexes; **read replicas**; **ElastiCache**; scale up |
| RDS `FreeStorageSpace` low | Data growth, logs, temp tables | **Storage autoscaling**; archive data; clean up binlogs |
| Aurora/RDS `ReplicaLag` high | Write-heavy primary, under-sized replica, long transactions | Size replicas like the writer; reduce long transactions; Aurora (storage-level replication, typically lower lag) |
| **SQS backlog growing** (`ApproximateNumberOfMessagesVisible` and `ApproximateAgeOfOldestMessage` rising) | Too few or slow consumers; consumer errors causing redelivery; poison messages; visibility timeout too short (duplicate processing) | Scale consumers on **backlog per instance** (target tracking on a custom metric); a **DLQ** with `maxReceiveCount`; fix errors; visibility timeout ≥ processing time (for a Lambda event source mapping AWS recommends ≥ 6× the function timeout); batch processing |
| **Kinesis** `ReadProvisionedThroughputExceeded` / `IteratorAgeMilliseconds` rising | Too many consumers per shard; too few shards; slow Lambda | **Enhanced fan-out**; add shards or use on-demand mode; Lambda **parallelization factor** and batch size |
| **NAT gateway port exhaustion** (`ErrorPortAllocation` > 0) | More than **55,000 simultaneous connections to the same destination (IP + port + protocol)** per NAT IP address | **Add secondary IPv4 addresses (up to 8 per NAT gateway)**; split workloads across subnets with **separate NAT gateways**; connection reuse/pooling; **VPC endpoints** for AWS services (gateway endpoints for S3/DynamoDB) |
| NAT gateway `PacketsDropCount` | Exceeding the maximum of 100 Gbps / 10 M pps per NAT gateway | Spread traffic across multiple NAT gateways and subnets |
| Instances in a private subnet can't reach the internet | Route table lacks 0.0.0.0/0 → NAT; NAT placed in a private subnet; NACL blocks ephemeral return ports; the NAT's subnet has no IGW route | Fix routes and NACLs; place the NAT in a public subnet |
| EC2 `StatusCheckFailed_System` | Problem with the underlying host hardware or network | **Recover** action, or stop-start (moves to a new host) |
| EC2 `StatusCheckFailed_Instance` | OS-level problem: kernel panic, full disk, bad network config | Reboot; fix the OS; EC2Rescue / `AWSSupport-*` runbooks |
| T-family instance slows after a while | `CPUCreditBalance` exhausted (standard mode) | Unlimited mode, or move to the M/C family; right-size |
| gp2 volume slows after a burst | `BurstBalance` depleted | Migrate to **gp3** (3,000 IOPS baseline, provision more as needed) |
| ASG instances terminated repeatedly right after launch | ELB health check fails before the app is ready; **health check grace period** too short; bad user data | Increase the grace period; lifecycle hooks; fix bootstrap; check the health check path |
| ECS tasks stuck in PENDING or failing to start | Insufficient cluster capacity; image pull failure (no NAT, or missing **ECR VPC endpoints + S3 gateway endpoint**); secrets retrieval failure | Capacity providers / Fargate; add endpoints; fix the task execution role |
| CloudFront high origin load / low cache hit ratio | Cache key includes unnecessary headers, cookies or query strings; short TTLs | Tune the cache policy; Origin Shield; versioned object names |
| Route 53 health check reports unhealthy but the endpoint is fine | A security group or firewall blocks the **Route 53 health checker IP ranges**; private endpoint not reachable from the internet | Allow health checker ranges; for private resources, use health checks based on CloudWatch alarms |
| "Rate exceeded" / `ThrottlingException` from your automation's AWS API calls | API request rate quota | Exponential backoff with jitter (SDK retry modes); cache describe calls; request a quota increase |
| CloudWatch alarm stuck in `INSUFFICIENT_DATA` | Metric not published, dimension mismatch, period shorter than resolution, sparse metric | Verify exact dimensions; correct the period; treat missing data appropriately |
| Metric filter shows no data for past errors | Metric filters don't backfill | Expected behaviour; use Logs Insights for history |

---

## 6. Decision tables — "X vs Y"

### 6.1 Which tool answers which question?

| Question | Tool |
|---|---|
| Is a resource performing within thresholds right now? | CloudWatch metrics and alarms |
| Which microservice or dependency adds the latency? | X-Ray / Application Signals |
| Which SQL statement is loading the DB? | Database Insights (Performance Insights) |
| Who deleted the security group rule, and from which IP? | CloudTrail |
| What did the resource configuration look like before, and is it compliant? | AWS Config |
| Is AWS having an issue affecting my resources, or is maintenance scheduled? | AWS Health |
| Are we following best practices for cost/security/limits? | Trusted Advisor; Well-Architected Tool for design reviews |
| Is this instance/Lambda/EBS/RDS the right size? | Compute Optimizer |
| Are our users' ISPs having trouble reaching us? | Internet Monitor |
| Is AWS's network causing packet loss between my workloads? | Network Flow Monitor |
| Does the checkout flow work right now, from outside? | Synthetics canary |
| What do real users experience in their browsers? | CloudWatch RUM |
| Are our hosts patched? | Patch Manager compliance |
| Where are the threats and vulnerabilities? | GuardDuty, Inspector, Security Hub, Macie |

### 6.2 Cross-account observability vs log shipping vs centralization rules

| Need | **OAM cross-account observability** | **Subscription filter → destination (Kinesis/Firehose)** | **Logs centralization rules** | **Org CloudTrail / S3 archive** |
|---|---|---|---|---|
| Data copied? | No (queried in place) | Yes (streamed) | Yes (copied log groups) | Yes (S3 objects) |
| Telemetry types | Metrics, logs, traces, SLOs, Application Insights, Internet Monitor | Logs only | Logs only | API events (and other logs you send) |
| Real-time | Yes | Near real time (< ~3 min) | Near real time | Minutes (CloudTrail ~5 min batches) |
| Transform / route to third party / SIEM | No | **Yes** (Lambda/Firehose transform, Splunk, OpenSearch) | No (stays in CloudWatch Logs) | Via S3 events / Security Lake |
| Long-term immutable retention | No (source retention applies) | Yes (S3 with Object Lock) | CloudWatch retention in the central account | **Yes** |
| Scope | Per Region | Same-Region destination, target stream can be in another Region | Cross-Region, cross-account, optional backup Region | Multi-Region trail |
| Ops overhead | Lowest | Highest | Low | Low |

### 6.3 Metric filter vs subscription filter vs Logs Insights vs EMF

| Need | Choose |
|---|---|
| Alarm on the count of a log pattern going forward | **Metric filter** → alarm (or a **log alarm** on a scheduled Insights query) |
| Stream logs in real time to another system or account | **Subscription filter** |
| Ad-hoc investigation over historical logs | **Logs Insights** |
| Emit high-cardinality custom metrics from Lambda/containers without API calls | **EMF** |
| Watch a deployment's logs live | **Live Tail** |

### 6.4 Composite alarm vs anomaly detection vs metric math alarm

| Problem | Best fit |
|---|---|
| Many related alarms page together for one root cause | **Composite alarm** (page only on the parent) |
| Static threshold wrong because traffic is seasonal | **Anomaly detection** alarm |
| Need a ratio (error %) rather than a raw count | **Metric math** alarm |
| Suppress pages during planned maintenance | Composite alarm **actions suppression** (or disable alarm actions in automation) |
| Detect too few requests (traffic drop) | Anomaly detection (lower band) or a threshold with `breaching` missing-data treatment |

### 6.5 Trusted Advisor vs Compute Optimizer vs Cost Optimization Hub vs Well-Architected Tool

| | Trusted Advisor | Compute Optimizer | Cost Optimization Hub (Ch16) | Well-Architected Tool |
|---|---|---|---|---|
| Purpose | Best-practice checks across 6 categories | ML right-sizing and idle detection | Consolidated, deduplicated savings opportunities | Structured architecture review |
| Input | Account configuration and usage | 14 days of CloudWatch metrics (93 with enhanced) | Compute Optimizer, RI/SP recommendations | Your answers + lenses |
| Org scope | Organizational view (paid support plan) | Org opt-in via management account / delegated admin | Org-wide | Shared workloads |
| Cost | Basic subset free; full checks need a paid plan | Free (enhanced metrics paid) | Free | Free |

### 6.6 CloudWatch vs Amazon Managed Service for Prometheus vs Managed Grafana

| Requirement | Choose |
|---|---|
| AWS-native metrics, alarms with AWS actions (ASG, EC2, SSM) | **CloudWatch** |
| Kubernetes workloads already instrumented with Prometheus exporters, PromQL skills, avoid running Prometheus HA | **AMP** |
| Unified dashboards across CloudWatch, AMP, X-Ray and third parties for SSO users | **Managed Grafana** |
| OTel-native pipeline to several backends | **ADOT collector** / CloudWatch agent (OTLP) |

### 6.7 AWS Config vs CloudTrail vs Security Hub

| | AWS Config | CloudTrail | Security Hub (CSPM) |
|---|---|---|---|
| Records | Resource **state** over time | API **calls** | **Findings** (from its own controls and integrated services) |
| Answers | "Is it compliant? What changed in its configuration?" | "Who did what, when, from where?" | "What is our security posture? What's most critical?" |
| Acts | Remediation via SSM Automation | — (pair with EventBridge) | Automation rules, EventBridge |
| Note | Security Hub CSPM controls **depend on Config** being enabled | Org trail to Log Archive | Delegated admin + cross-Region aggregation |

### 6.8 Runbook vs playbook vs post-incident analysis

| Artifact | Purpose | AWS implementation |
|---|---|---|
| **Runbook** | Known procedure → specific outcome | SSM Automation runbook |
| **Playbook** | Investigation to find the cause | Documented steps + Logs Insights saved queries + dashboards; OpsCenter |
| **Post-incident analysis (COE)** | Learn from the event and prevent recurrence | Incident Manager analysis template (legacy), or your own COE process; action items tracked in OpsCenter/Jira |
| **Game day** | Practice and validate | AWS FIS experiments + runbooks |

---

## 7. Exam keyword → answer cheat list

| Keyword / phrase in the stem | Likely answer |
|---|---|
| "Memory utilization" / "disk space" metrics for EC2 | **CloudWatch agent** (deployed via Systems Manager) |
| "Central monitoring account", "view metrics/logs/traces across accounts", "least overhead" | **CloudWatch cross-account observability** (OAM) with Organizations |
| "Single dashboard across Regions and accounts" | CloudWatch dashboard (global) with cross-account cross-Region enabled, or Managed Grafana |
| "Reduce alarm noise", "only notify when both…" | **Composite alarm** |
| "Seasonal / variable traffic", "no static threshold" | **Anomaly detection alarm** |
| "Sub-minute metrics" | **High-resolution custom metric** (1 s) with a 10 s/30 s alarm |
| "Custom metrics from Lambda at high volume / cardinality" | **Embedded Metric Format** |
| "Stream logs in near real time to another account / Splunk / OpenSearch" | **Subscription filter** → Kinesis Data Streams / **Firehose** (cross-account destination) |
| "Consolidate logs from all accounts and Regions into one account, managed" | **CloudWatch Logs centralization rules** (or an org trail for API logs) |
| "Mask PII in logs", "only privileged users see raw values" | CloudWatch Logs **data protection policy** + `logs:Unmask` |
| "Rarely queried logs, lower cost, still queryable" | **Infrequent Access log class** (new log group) |
| "Search traces by customer ID / order ID" | X-Ray **annotations** |
| "Identify which downstream service causes latency" | **X-Ray / Application Signals** service map |
| "Vendor-neutral instrumentation", "send traces to X-Ray and a third party" | **AWS Distro for OpenTelemetry** |
| "Define SLOs / error budgets" | CloudWatch **Application Signals** SLOs |
| "Detect broken user journeys before customers report them" | **Synthetics canaries** |
| "Measure actual end-user page performance / JS errors" | **CloudWatch RUM** |
| "Internet/ISP problems affecting users in a city" | **Internet Monitor** |
| "PromQL", "Prometheus on EKS without managing servers" | **Amazon Managed Service for Prometheus** |
| "Grafana dashboards with SSO" | **Amazon Managed Grafana** |
| "Who made the change?" | **CloudTrail** |
| "Configuration history / compliance over time" | **AWS Config** (timeline, rules, aggregator) |
| "Automatically remediate non-compliant resources" | Config rule + **SSM Automation remediation** |
| "Org-wide compliance view" | Config **aggregator** (+ advanced queries) |
| "Normalize security logs to OCSF / security data lake" | **Amazon Security Lake** |
| "Immutable audit logs for 7 years" | **Org CloudTrail → S3 (Log Archive) + Object Lock + lifecycle to Glacier Deep Archive** + integrity validation |
| "Scheduled maintenance / instance retirement across all accounts → automate" | **AWS Health organizational view + delegated admin + EventBridge** → SSM Automation |
| "Programmatic access to Health events" | **Health API** (needs Business Support+/Enterprise/Unified Ops; legacy Business) |
| "Check service quota usage / best-practice checks across org" | **Trusted Advisor organizational view** (+ Service Quotas alarms) |
| "Account team prioritized recommendations" | **Trusted Advisor Priority** (Enterprise / Unified Operations) |
| "Right-size EC2/Lambda/EBS/RDS/ECS Fargate" | **Compute Optimizer** |
| "Right-sizing needs to cover monthly/quarterly patterns" | Compute Optimizer **enhanced infrastructure metrics** (93 days) |
| "Ops dashboard of OpsItems, patch and Config compliance across accounts" | **Systems Manager Explorer** |
| "Track and resolve operational issues with linked runbooks" | **Systems Manager OpsCenter** |
| "Incident response plan, on-call escalation, engagement" | **Incident Manager** (exam); now closed to new customers → OpsCenter + partner tool |
| "Prevent changes during business-critical periods" | **Change Calendar** |
| "Patch compliance report for auditors across accounts" | **Patch Manager** + resource data sync → S3 → Athena/QuickSight |
| "Operations as code" | **SSM Automation**, IaC, EventBridge-driven automation |
| "Practice failure response" | **Game days** with **AWS FIS** |
| "Learn from incidents" | Blameless **post-incident analysis** / COE with action items |
| "Evaluate workload against best practices, track improvements" | **Well-Architected Tool** (milestones, improvement plan) |
| "Too many DB connections from Lambda" | **RDS Proxy** |
| "Read-heavy DynamoDB, microsecond latency" | **DAX** |
| "NAT gateway ErrorPortAllocation" | Secondary IPs on the NAT gateway / more NAT gateways / VPC endpoints |

---

## 8. Traps & distractors

1. **"Enable detailed monitoring to get memory metrics."** Detailed monitoring only changes the frequency to 1 minute. Memory and disk space need the **CloudWatch agent**.
2. **"Use a composite alarm to stop/terminate the instance or scale the ASG."** Composite alarms can't perform EC2 or Auto Scaling actions. They also **can't be cross-account**.
3. **"Create a metric filter to count last month's errors."** Metric filters don't backfill. Use Logs Insights.
4. **"Change the existing log group to Infrequent Access."** The class is fixed at creation. Create new log groups, and remember IA has **no subscriptions, metric filters, Live Tail or EMF**.
5. **"Subscription filter directly to S3."** Not a destination. Use **Firehose** → S3. Also, **CreateExportTask** is batch, not real-time.
6. **"Use CloudWatch Logs export for continuous replication to the central account."** Use subscription filters/destinations or **centralization rules**.
7. **"OAM gives cross-Region visibility from one sink."** Sinks are **per Region**. Cross-Region dashboards use the cross-account cross-Region console feature.
8. **"Store trace search fields in metadata."** Only **annotations** are indexed.
9. **"Use the Config aggregator to remediate."** Aggregators are read-only. Remediation runs in member accounts (organization rules/conformance packs).
10. **"CloudTrail tells you whether the resource is compliant / its configuration at a point in time."** That's **Config**. And **Config doesn't tell you the source IP** of the caller; CloudTrail does.
11. **"Call the Health API from every account on the Basic plan."** You get `SubscriptionRequiredException`. Use the organizational view with a delegated admin on a qualifying plan.
12. **"Deploy an EventBridge rule in every account with StackSets to centralize Health events."** It works, but with organizational view enabled, one rule in the delegated-admin account receives events for all accounts. That is less overhead.
13. **"Trusted Advisor org view shows full checks for every account."** Each member account's checks depend on **its own** support plan.
14. **"Compute Optimizer gives memory-aware EC2 recommendations out of the box."** It needs memory metrics (CloudWatch agent or external ingestion).
15. **"Raise DynamoDB capacity" for a hot partition.** Fix the key design / write sharding, or cache with DAX. More capacity is spread across partitions and may not help.
16. **"ALB 503 means targets are unhealthy."** 503 usually means **no registered targets**. With all targets unhealthy, the ALB fails open.
17. **"Increase NAT gateway bandwidth" for ErrorPortAllocation.** Bandwidth scales automatically. The problem is connections per destination per IP: add IPs or NAT gateways.
18. **"Put a security group on the NAT gateway."** Not supported. Use NACLs and instance security groups.
19. **"Use a gateway VPC endpoint for a third-party API."** Gateway endpoints exist only for **S3 and DynamoDB**. Third-party SaaS needs PrivateLink if the vendor offers it, otherwise NAT.
20. **"Use X-Ray to find which SQL query is slow inside the DB engine."** X-Ray shows the call's latency. Database Insights / Performance Insights shows top SQL and wait events.
21. **"Install the X-Ray daemon for a new project" in a real-world design.** It's legacy since Feb 2026. Prefer ADOT / the CloudWatch agent. On the exam, an X-Ray SDK answer can still be correct.
22. **"Use Incident Manager" for a brand-new customer in a real-world design.** It's closed to new customers. On the exam it's still valid.
23. **Self-managed ELK/Prometheus/Grafana on EC2** when the stem says "least operational overhead". Choose OpenSearch Service, AMP and AMG.
24. **Over-engineering**: Lambda functions that poll `GetMetricData` to export metrics, where **Metric Streams** exist; custom scripts to collect inventory, where **SSM Inventory** exists.
25. **"Alarm period 60 s on EC2 basic monitoring."** Basic metrics arrive every 5 minutes, so the alarm flaps to `INSUFFICIENT_DATA`. Use ≥ 300 s or enable detailed monitoring.

---

## 9. Professional architect focus

- **Start from SLOs, not dashboards.** Agree with the business on the user journeys that matter, their SLIs (availability, latency percentiles) and their targets. Alert on **symptoms** (SLO burn, canary failure) that page humans. Send **causes** (CPU, queue depth) to dashboards and tickets. This is the most effective cure for alert fatigue.
- **Percentiles over averages.** p99 latency shows the experience of your heaviest users. Averages hide tail latency. Use `TargetResponseTime` p99, not Average.
- **Telemetry cost is real.** CloudWatch Logs ingestion, high-cardinality custom metrics (each unique dimension combination is billed as a metric), and indexed traces can rival compute cost.
  - Set **retention on every log group** and use the IA class where it fits.
  - Sample debug logs, and archive to S3 with lifecycle.
  - Control cardinality: don't put request IDs in dimensions. Put them in EMF properties or logs.
  - Use Transaction Search to ingest all spans but index a fraction.
- **Central vs federated ownership.** A central platform team owns the landing-zone telemetry (org trail, Config, Security Lake, OAM sinks). Application teams own their dashboards, alarms and runbooks, built as IaC modules. Raise RACI questions early: who gets paged, and who pays for logs?
- **Automate safely.** Automation without guardrails turns incidents into outages. Use rate control, error thresholds, approvals for destructive steps, Change Calendar freezes, and canary rollouts of runbooks themselves.
- **Mind the service lifecycle.** For new builds in late 2026, avoid services closed to new customers (Incident Manager, Change Manager, CloudTrail Lake) and the X-Ray SDK/daemon. Choose OpsCenter + a partner paging tool, CloudWatch/Athena for event queries, and OpenTelemetry for instrumentation. Flag this to stakeholders who reference older blueprints.
- **Support-plan dependencies.** The Health API, Trusted Advisor full checks/org view and Trusted Advisor Priority need specific plans. AWS's 2026–2027 support-plan transition (Business Support+, Enterprise, Unified Operations) can affect budget and automation. Check before designing around them.
- **Detective vs preventive.** Config and Security Hub find problems after the fact. Pair them with SCPs/RCPs, Control Tower proactive controls and IaC policy checks so findings trend down instead of being remediated forever.
- **Close the loop.** Every significant incident should produce a post-incident analysis with tracked actions. Every quarter, run a Well-Architected review milestone and a game day. Measure toil and drive it down: that is the "continuous" in continuous improvement.

---

## 10. Skills checklist

- [ ] I can explain namespaces, dimensions, resolution and retention, and why EC2 memory metrics need the CloudWatch agent.
- [ ] I can choose between `PutMetricData`, EMF, statistic sets and OTel for custom metrics.
- [ ] I can design alarms with M-of-N evaluation, correct missing-data treatment, metric math, anomaly detection and composite alarms (including their limitations).
- [ ] I know which alarm actions exist (SNS, EC2, Auto Scaling, OpsItem, incident, investigation) and which alarm types support them.
- [ ] I can configure CloudWatch Logs retention, KMS, metric filters, subscription filters (limits, cross-account destinations), data protection, and choose a log class.
- [ ] I can set up CloudWatch cross-account observability with Organizations and explain its per-Region scope and limits.
- [ ] I can match Container Insights, Lambda Insights, Database Insights, Application Signals, Synthetics, RUM, Internet Monitor and Network Flow Monitor to scenarios.
- [ ] I can explain X-Ray segments, sampling, annotations vs metadata, groups, Transaction Search, and the move to OpenTelemetry/ADOT.
- [ ] I know when to use AMP and Managed Grafana instead of CloudWatch.
- [ ] I can design an org-wide centralized logging and audit architecture with immutable retention and cost controls, including Security Lake.
- [ ] I can use AWS Config rules, conformance packs, remediation, aggregators and advanced queries across an organization.
- [ ] I can build EventBridge automations for Health, EC2 state, Config compliance and security findings.
- [ ] I can enable the AWS Health organizational view with a delegated admin and route events centrally.
- [ ] I know Trusted Advisor categories, support-plan requirements, organizational view and Trusted Advisor Priority.
- [ ] I know Compute Optimizer's supported resources, lookback periods and memory-metric dependency.
- [ ] I can map Systems Manager Explorer, OpsCenter, Automation, Change Calendar, Patch Manager and Inventory to operational needs, and I know the status of Incident Manager and Change Manager.
- [ ] I can apply the Operational Excellence design principles, and distinguish runbooks, playbooks, post-incident analysis and game days.
- [ ] I can diagnose 502/503/504/460 at ALB, 429 at API Gateway, Lambda throttles, DynamoDB throttling, RDS connection exhaustion, SQS backlog, Kinesis iterator age and NAT port exhaustion.
- [ ] I can work through "slow", "outages", "security findings" and "toil" scenarios to the most managed, least-change fix.

---

## 11. Practice questions

> Original SAP-C02-style questions. They are not real exam questions.

**Q1.** A media company runs 320 AWS accounts in AWS Organizations with all features enabled. Workloads run in us-east-1 and eu-west-1. A new central SRE team works from a dedicated Ops account. They need to search CloudWatch metrics, run CloudWatch Logs Insights queries, view X-Ray trace maps, and create alarms on data from any workload account, without switching roles. New accounts are created weekly through Control Tower Account Factory, and the SRE team must not have to onboard them by hand. The solution must have the least operational overhead and must not duplicate log storage costs. What should a solutions architect do?

- A. In every workload account, create a CloudWatch Logs subscription filter that sends all log groups to a Kinesis Data Streams destination in the Ops account. Create an IAM role that the SRE team assumes in each account for metrics and traces.
- B. Configure the Ops account as a CloudWatch cross-account observability monitoring account by creating a sink in us-east-1 and eu-west-1. Use the AWS Organizations-based CloudFormation template (deployed with StackSets to the organization) to create links from all accounts to each sink, sharing metrics, log groups and traces.
- C. Enable the CloudWatch cross-account cross-Region console feature in each workload account with the `CloudWatch-CrossAccountSharingRole`. Create a cross-account dashboard per workload in the Ops account.
- D. Create CloudWatch Logs centralization rules that copy all log groups from all accounts into the Ops account. Use CloudWatch Metric Streams to send all metrics to the Ops account through Amazon Data Firehose.

**Q2.** An online payments platform has more than 200 CloudWatch alarms on its checkout service. During a recent database failover, the on-call engineer received 63 pages in 4 minutes. Separately, a static `RequestCount < 500` alarm intended to detect traffic drops fires every night between 01:00 and 05:00, when traffic is normally low, and is now ignored. The team wants fewer, more meaningful pages and wants to catch real traffic drops at any hour. Which combination of actions will meet these requirements? (Select TWO.)

- A. Remove actions from the component alarms. Create a composite alarm that goes into ALARM only when the checkout canary alarm and the ALB 5xx-rate alarm are both in ALARM, and send pages only from the composite alarm.
- B. Change all alarms to use a 10-second period with high-resolution metrics so that transient conditions are detected and cleared faster.
- C. Replace the static `RequestCount` alarm with a CloudWatch anomaly detection alarm that triggers when the metric falls below the lower band of the expected range.
- D. Configure the composite alarm to stop the database instance and trigger an EC2 Auto Scaling policy when it enters ALARM.
- E. Set `TreatMissingData` to `breaching` on all alarms so that alarms stay in ALARM until an engineer resets them.

**Q3.** A company runs 1,800 Amazon EC2 instances (Linux and Windows) in 40 accounts. Finance wants to right-size the fleet. The current AWS Compute Optimizer recommendations show many instances as "Optimized" or flag them with low confidence. Application owners complain that downsizing based on CPU alone caused out-of-memory errors last year. Several workloads also run heavy month-end and quarter-end batch jobs that the current recommendations do not appear to consider. Which actions should a solutions architect take to produce more accurate recommendations with minimal operational effort? (Select TWO.)

- A. Enable EC2 detailed monitoring on all instances so that Compute Optimizer receives memory metrics every minute.
- B. Use AWS Systems Manager to install and configure the unified CloudWatch agent on all instances (configuration stored in Parameter Store) so that memory utilization is published to CloudWatch.
- C. Activate the Compute Optimizer enhanced infrastructure metrics recommendation preference for the organization so that the lookback period covers 93 days.
- D. Export VPC Flow Logs to Amazon S3 and use Amazon Athena to calculate per-instance memory pressure.
- E. Use AWS Trusted Advisor low-utilization EC2 checks instead of Compute Optimizer, because Trusted Advisor considers memory utilization.

**Q4.** A retail company has 150 accounts in AWS Organizations and an Enterprise Support plan. Over the last quarter, several production EC2 instances were retired by AWS after scheduled retirement notices went unnoticed in individual accounts' AWS Health Dashboards. The cloud operations team works from a dedicated Operations account. Security policy prohibits using the management account for day-to-day operations. The company wants every `scheduledChange` Health event across all accounts to automatically create a ticket that is routed to the resource owner, with the least ongoing operational overhead. What should a solutions architect recommend?

- A. Use CloudFormation StackSets to deploy an EventBridge rule for `aws.health` events in every account and every Region. Forward the events to a central event bus in the Operations account, where a Lambda function creates tickets.
- B. Enable AWS Health organizational view from the management account and register the Operations account as a delegated administrator for AWS Health. In the Operations account, create an EventBridge rule that matches `aws.health` events with `eventTypeCategory` of `scheduledChange` and invokes a Lambda function that looks up owner tags and creates tickets.
- C. Enable an organization trail in AWS CloudTrail and create a CloudWatch Logs metric filter that matches Health events. Configure an alarm that notifies the ticketing system through Amazon SNS.
- D. Enable AWS Trusted Advisor organizational view and schedule a weekly report export. Use a Lambda function to parse the report for instance retirement entries and create tickets.

**Q5.** A ticketing company migrated its booking API to AWS Lambda behind Amazon API Gateway. The API uses an Amazon RDS for PostgreSQL db.r6g.large instance. During on-sales, Lambda concurrency climbs to 1,500. The database then logs `FATAL: remaining connection slots are reserved` and `sorry, too many clients already`. API latency spikes, and some requests fail. CPU on the database stays below 40 %. The company wants to fix the problem quickly with minimal code changes and maintain availability during database failovers. What should a solutions architect do?

- A. Increase the DB instance class to db.r6g.4xlarge to raise `max_connections` and set Lambda reserved concurrency to 1,500.
- B. Create an Amazon RDS Proxy for the database, configure the Lambda functions to connect through the proxy endpoint using IAM authentication with credentials in Secrets Manager, and tune the proxy's maximum connections percentage.
- C. Add two RDS read replicas and change the Lambda functions to randomly choose an endpoint for every query.
- D. Put an Amazon SQS queue between API Gateway and Lambda so that all booking requests are processed asynchronously by a single Lambda function with a reserved concurrency of 1.

**Q6.** An e-commerce company runs its storefront on EC2 instances in an Auto Scaling group behind an Application Load Balancer, with an Amazon Aurora MySQL cluster (one writer, no replicas). During flash sales, p99 page latency rises from 400 ms to 6 s. AWS X-Ray traces show that about 70 % of request time is spent in repeated, identical `SELECT` queries for product details and prices that change only a few times per day. Database Insights shows the writer at 95 % CPU, dominated by these read queries. Product images and JavaScript bundles are served from the EC2 instances, and web-tier CPU averages 35 %. Which combination of actions will MOST improve performance during sales? (Select THREE.)

- A. Add Aurora Replicas and direct read-only product queries to the cluster reader endpoint.
- B. Implement a lazy-loading cache for product details in Amazon ElastiCache with a TTL aligned to the price update frequency.
- C. Move images and JavaScript bundles to Amazon S3 and serve them, and cacheable pages, through Amazon CloudFront.
- D. Increase the Auto Scaling group's maximum capacity and lower the CPU target-tracking value to 20 %.
- E. Enable DynamoDB Accelerator (DAX) in front of the Aurora cluster to cache the product queries.
- F. Convert the Aurora cluster to use Aurora I/O-Optimized storage to remove the CPU bottleneck.

**Q7.** After a company moved its Node.js API from a self-managed NGINX load balancer to an Application Load Balancer, the operations team sees a small but steady rate of HTTP 502 errors in `HTTPCode_ELB_502_Count`. The rate rises when traffic is low to moderate and is not linked to deployments. `HTTPCode_Target_5XX_Count` is near zero. Targets are healthy. ALB access logs show the errored requests with `target_status_code` of `-` and a short `target_processing_time`. The ALB idle timeout is the default. The Node.js HTTP server uses its default `keepAliveTimeout` of 5 seconds. What is the MOST likely cause and fix?

- A. The ALB idle timeout is too long. Reduce it to 4 seconds so that connections are closed before the target closes them.
- B. The target closes idle keep-alive connections before the ALB does, so the ALB sometimes sends a request on a connection the target has just closed. Configure the Node.js server's keep-alive timeout to be longer than the ALB idle timeout.
- C. The target group has no registered targets during scale-in events. Increase the Auto Scaling group's minimum capacity.
- D. The security group on the targets blocks ephemeral ports from the ALB. Add an inbound rule for ports 1024–65535 from the ALB security group.

**Q8.** A fintech company runs 400 containerized workers in private subnets in a single VPC. All outbound traffic goes through one NAT gateway in each of three Availability Zones. Each worker opens many short-lived HTTPS connections to a single third-party payment API endpoint (one IP address and port). During peak batch runs, transactions fail with connection timeouts, and the NAT gateways' `ErrorPortAllocation` metric is non-zero. Bandwidth on the NAT gateways is below 3 Gbps. Which actions will resolve the issue? (Select TWO.)

- A. Associate additional secondary private IPv4 addresses (with Elastic IPs, if the vendor allowlists source IPs) with each NAT gateway, up to the per-NAT-gateway maximum.
- B. Create a gateway VPC endpoint for the third-party payment API and update the route tables.
- C. Configure the workers to reuse HTTPS connections (connection pooling and keep-alive) instead of opening a new connection per transaction.
- D. Request a bandwidth increase for the NAT gateways through AWS Support.
- E. Attach a security group to each NAT gateway that allows more concurrent outbound connections.

**Q9.** A healthcare company with 90 accounts in AWS Organizations must ensure that no S3 bucket allows public read or write access and that all EBS volumes are encrypted. Non-compliant S3 buckets must be corrected automatically within minutes. The compliance team, working from a Security account, needs a single view of compliance status across all accounts and Regions. They also need ad-hoc SQL-like queries such as "list unencrypted EBS volumes in all accounts". Which combination of steps meets these requirements with the least operational overhead? (Select TWO.)

- A. Register the Security account as the AWS Config delegated administrator. Deploy an organization conformance pack that includes the S3 public access rules with automatic remediation using the `AWS-DisableS3BucketPublicReadWrite` Systems Manager Automation runbook, and the EBS encryption rule.
- B. Create an organization-wide AWS Config aggregator in the Security account and use advanced queries for ad-hoc compliance questions.
- C. Configure the Config aggregator in the Security account to run remediation actions directly against non-compliant resources in member accounts.
- D. Use Amazon Macie in each account to detect public buckets and invoke a Lambda function that deletes the public bucket policy.
- E. Create a CloudTrail organization trail and a Lambda function that scans the trail every hour for `PutBucketAcl` calls and reverts them.

**Q10.** A logistics company sends about 45 TB per month of verbose application debug and audit logs from 300 microservices to Amazon CloudWatch Logs Standard log groups. The logs are used only for occasional forensic investigations with CloudWatch Logs Insights. No metric filters, subscription filters or alarms use them. The security team recently found customer phone numbers and email addresses in the logs and requires them to be masked for everyone except a small investigations group. CloudWatch Logs is now the largest line item on the AWS bill. The company wants to reduce cost significantly with the least effort while keeping Logs Insights query capability. What should a solutions architect do?

- A. Change the log class of the existing log groups from Standard to Infrequent Access, and attach a data protection policy to each log group.
- B. Create new log groups in the Infrequent Access log class with appropriate retention periods, point the services' log configuration at the new log groups, and create an account-level data protection policy with managed data identifiers for phone numbers and email addresses. Grant `logs:Unmask` only to the investigations group.
- C. Create subscription filters that stream the logs to Amazon Data Firehose and on to Amazon S3, and set log group retention to 1 day. Use Amazon Athena for investigations and Amazon Macie for masking.
- D. Keep the Standard log class, and configure a daily `CreateExportTask` to Amazon S3 Glacier Deep Archive with a 1-day log group retention. Restore and query the data with Athena when needed.

---

### Answers & explanations

<details><summary>Show answer — Q1</summary>

**Correct: B.**

- **Why B is correct:** CloudWatch cross-account observability (OAM) lets a monitoring account search metrics, run Logs Insights, view traces, and create alarms on source-account data **in place**, with no data copied. Using the **Organizations-based template** means new accounts in the org/OU are linked automatically. Sinks are **per Region**, so you create one in each of us-east-1 and eu-west-1. Sharing logs and metrics has no extra charge.
- **Why the others are wrong:**
  - **A**: subscription pipelines copy logs, which duplicates storage and adds Kinesis cost. They need per-account setup, and role switching is exactly what the team wants to avoid.
  - **C**: the older console sharing role supports dashboards and switching but needs per-account work and gives less integrated querying than OAM.
  - **D**: centralization rules and Metric Streams duplicate data and cost, add pipeline overhead, and don't cover traces.
- **Reference:** [CloudWatch cross-account observability](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/CloudWatch-Unified-Cross-Account.html)
</details>

<details><summary>Show answer — Q2</summary>

**Correct: A, C.**

- **Why A is correct:** a **composite alarm** combines symptoms, so one root cause produces one page. Removing actions from child alarms stops the paging storm.
- **Why C is correct:** an **anomaly detection** alarm learns daily and weekly seasonality, so low overnight traffic is "expected". A real drop below the lower band at any hour still alarms.
- **Why the others are wrong:**
  - **B**: high-resolution periods increase sensitivity and cost and would add noise.
  - **D**: composite alarms **cannot perform EC2 or Auto Scaling actions**, and stopping the DB is harmful anyway.
  - **E**: `breaching` treats missing data as failures, which creates more false alarms. Alarms also don't need manual resets.
- **References:** [Composite alarms](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/Create_Composite_Alarm.html) · [Anomaly detection](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/CloudWatch_Anomaly_Detection.html)
</details>

<details><summary>Show answer — Q3</summary>

**Correct: B, C.**

- **Why B is correct:** EC2 doesn't publish memory metrics. The **CloudWatch agent** does. Deploying it through Systems Manager (Distributor/Run Command or State Manager, with the config in Parameter Store) scales across accounts. Compute Optimizer then makes **memory-aware** recommendations.
- **Why C is correct:** the default lookback is **14 days**. **Enhanced infrastructure metrics** extend it to **93 days**, which captures month-end and quarter-end peaks.
- **Why the others are wrong:**
  - **A**: detailed monitoring only increases frequency. It does not add memory metrics.
  - **D**: Flow Logs contain network metadata, not memory.
  - **E**: Trusted Advisor's low-utilization check is CPU/network-based and does not replace Compute Optimizer.
- **References:** [Compute Optimizer](https://docs.aws.amazon.com/compute-optimizer/latest/ug/what-is-compute-optimizer.html) · [Enhanced infrastructure metrics](https://docs.aws.amazon.com/compute-optimizer/latest/ug/enhanced-infrastructure-metrics.html) · [CloudWatch agent](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/Install-CloudWatch-Agent.html)
</details>

<details><summary>Show answer — Q4</summary>

**Correct: B.**

- **Why B is correct:** with **organizational view** enabled, the management account or a **delegated administrator** (up to 5) receives a single feed of Health events from all accounts, including in **EventBridge**. One rule in the Operations account covers the whole org, and the management account is not used day to day.
- **Why the others are wrong:**
  - **A**: works, but means deploying and maintaining rules in every account and Region. That is more overhead than B.
  - **C**: Health events are not CloudTrail API events, so a metric filter won't catch them.
  - **D**: Trusted Advisor doesn't report instance-retirement Health events, and weekly is too slow.
- **References:** [Aggregating Health events with organizational view and delegated admin](https://docs.aws.amazon.com/health/latest/ug/aggregating-health-events.html) · [Delegated administrator for organizational view](https://docs.aws.amazon.com/health/latest/ug/delegated-administrator-organizational-view.html)
</details>

<details><summary>Show answer — Q5</summary>

**Correct: B.**

- **Why B is correct:** the database is out of **connections**, not CPU. **RDS Proxy** pools and multiplexes connections from thousands of Lambda environments. It needs only an endpoint change in the code. It also reduces failover time by keeping client connections open and routing them to the new primary. It integrates with Secrets Manager and IAM authentication.
- **Why the others are wrong:**
  - **A**: scaling up raises `max_connections` but wastes money (CPU is fine), and it still can't absorb unbounded Lambda concurrency.
  - **C**: replicas don't help writes (bookings), and per-query endpoint selection is a significant code change.
  - **D**: concurrency of 1 destroys throughput and changes the API contract.
- **Reference:** [Amazon RDS Proxy](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/rds-proxy.html)
</details>

<details><summary>Show answer — Q6</summary>

**Correct: A, B, C.**

- **Why A is correct:** Aurora Replicas behind the **reader endpoint** offload read queries from the saturated writer.
- **Why B is correct:** **ElastiCache** lazy loading removes the repeated identical reads entirely. The data changes rarely, so a TTL keeps it fresh enough.
- **Why C is correct:** **CloudFront + S3** offloads static assets and cacheable pages from the origin and cuts user latency.
- **Why the others are wrong:**
  - **D**: the web tier isn't the bottleneck (35 % CPU). More instances add more DB load.
  - **E**: **DAX works only with DynamoDB.**
  - **F**: I/O-Optimized changes I/O pricing. It does not reduce CPU consumed by queries.
- **References:** [Aurora replicas and endpoints](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/Aurora.Overview.Endpoints.html) · [ElastiCache caching strategies](https://docs.aws.amazon.com/AmazonElastiCache/latest/dg/Strategies.html) · [X-Ray concepts](https://docs.aws.amazon.com/xray/latest/devguide/xray-concepts.html)
</details>

<details><summary>Show answer — Q7</summary>

**Correct: B.**

- **Why B is correct:** the ALB reuses back-end keep-alive connections for up to its idle timeout (default 60 s). Node.js closes idle connections after 5 s. When the ALB sends a request on a connection the target has just closed, it gets a TCP RST/FIN and returns **502**. A missing target status code fits this. The fix is to set the target keep-alive timeout **longer than** the ALB idle timeout. AWS documents this cause explicitly.
- **Why the others are wrong:**
  - **A**: a 4 s idle timeout would break legitimate longer requests and client connections. The correct fix is on the target side.
  - **C**: an empty target group produces **503**, not 502.
  - **D**: blocked return traffic generally shows up as **504** timeouts or failed health checks, and targets here are healthy.
- **Reference:** [Troubleshoot your Application Load Balancers — HTTP 502](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/load-balancer-troubleshooting.html)
</details>

<details><summary>Show answer — Q8</summary>

**Correct: A, C.**

- **Why A is correct:** each NAT gateway IPv4 address supports up to **55,000 simultaneous connections to each unique destination** (IP, port, protocol). With one destination, adding secondary IPs (up to 8 addresses per NAT gateway) multiplies the available ports. Splitting workloads across more NAT gateways is an alternative.
- **Why C is correct:** **connection reuse** cuts the number of concurrent connections needed, attacking the root cause.
- **Why the others are wrong:**
  - **B**: gateway endpoints exist only for **S3 and DynamoDB**.
  - **D**: bandwidth isn't the constraint, and NAT bandwidth scales automatically up to 100 Gbps.
  - **E**: you **can't attach security groups to NAT gateways**.
- **Reference:** [NAT gateway basics](https://docs.aws.amazon.com/vpc/latest/userguide/nat-gateway-basics.html)
</details>

<details><summary>Show answer — Q9</summary>

**Correct: A, B.**

- **Why A is correct:** a **delegated administrator** deploying an **organization conformance pack** rolls out the rules and **automatic remediation** (SSM Automation runs in each member account) to all accounts, including new ones.
- **Why B is correct:** an **organization aggregator** gives the single multi-account, multi-Region compliance view, and **advanced queries** answer SQL-like questions such as unencrypted EBS volumes.
- **Why the others are wrong:**
  - **C**: aggregators are **read-only** and can't remediate.
  - **D**: Macie discovers sensitive data and evaluates bucket security, but deleting policies through custom Lambda functions per account is more overhead and not the managed compliance path. It also doesn't cover EBS.
  - **E**: hourly scanning isn't "within minutes", and it is custom code.
- **References:** [Conformance packs](https://docs.aws.amazon.com/config/latest/developerguide/conformance-packs.html) · [Remediation](https://docs.aws.amazon.com/config/latest/developerguide/remediation.html) · [Aggregators](https://docs.aws.amazon.com/config/latest/developerguide/aggregate-data.html) · [Advanced queries](https://docs.aws.amazon.com/config/latest/developerguide/querying-AWS-resources.html)
</details>

<details><summary>Show answer — Q10</summary>

**Correct: B.**

- **Why B is correct:** the **Infrequent Access** log class has a lower ingestion price and still supports **Logs Insights** and **data protection masking**. These logs don't need the features IA lacks (metric filters, subscriptions, Live Tail). The **class can't be changed after creation**, so new log groups are required. An **account-level data protection policy** masks the identifiers at ingestion for all log groups. Only principals with `logs:Unmask` see raw values. Retention controls storage cost.
- **Why the others are wrong:**
  - **A**: you can't change an existing log group's class.
  - **C**: subscription filters still incur Standard ingestion, and Athena + Macie loses Logs Insights and doesn't mask in place.
  - **D**: Standard ingestion cost remains, export tasks are batch, and Deep Archive restores take hours. Investigations would slow down and effort would go up.
- **References:** [Log classes](https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/CloudWatch_Logs_Log_Classes.html) · [Masking sensitive log data](https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/mask-sensitive-log-data.html)
</details>

---

## 12. References

**CloudWatch**
- [Amazon CloudWatch User Guide — metrics concepts](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/cloudwatch_concepts.html)
- [Publish custom metrics (PutMetricData / EMF)](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/publishingMetrics.html)
- [Embedded metric format](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/CloudWatch_Embedded_Metric_Format.html)
- [Using CloudWatch alarms](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/CloudWatch_Alarms.html) · [Composite alarms](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/Create_Composite_Alarm.html) · [Anomaly detection](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/CloudWatch_Anomaly_Detection.html)
- [CloudWatch agent](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/Install-CloudWatch-Agent.html)
- [CloudWatch cross-account observability](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/CloudWatch-Unified-Cross-Account.html) · [Cross-account cross-Region console](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/Cross-Account-Cross-Region.html)
- [Application Signals](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/CloudWatch-Application-Monitoring-Sections.html) · [SLOs](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/CloudWatch-ServiceLevelObjectives.html)
- [Synthetics canaries](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/CloudWatch_Synthetics_Canaries.html) · [CloudWatch RUM](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/CloudWatch-RUM.html) · [Internet Monitor](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/CloudWatch-InternetMonitor.html) · [Network Flow Monitor](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/CloudWatch-NetworkFlowMonitor.html)
- [Container Insights](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/ContainerInsights.html) · [Lambda Insights](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/Lambda-Insights.html) · [Database Insights](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/Database-Insights.html)
- [Transaction Search](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/CloudWatch-Transaction-Search.html)

**CloudWatch Logs**
- [Log classes](https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/CloudWatch_Logs_Log_Classes.html)
- [Subscriptions](https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/Subscriptions.html) · [Cross-account cross-Region subscriptions](https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/CrossAccountSubscriptions.html)
- [Cross-account cross-Region log centralization](https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/CloudWatchLogs_Centralization.html)
- [Masking sensitive log data](https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/mask-sensitive-log-data.html)
- [Logs Insights](https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/AnalyzingLogData.html) · [Live Tail](https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/CloudWatchLogs_LiveTail.html)

**Tracing, Prometheus, Grafana**
- [AWS X-Ray concepts](https://docs.aws.amazon.com/xray/latest/devguide/xray-concepts.html) · [X-Ray SDK and daemon support timeline](https://docs.aws.amazon.com/xray/latest/devguide/xray-sdk-daemon-timeline.html)
- [AWS Distro for OpenTelemetry](https://aws.amazon.com/otel/) · [Migrating from X-Ray instrumentation to OpenTelemetry](https://docs.aws.amazon.com/xray/latest/devguide/xray-sdk-migration.html)
- [Amazon Managed Service for Prometheus](https://docs.aws.amazon.com/prometheus/latest/userguide/what-is-Amazon-Managed-Service-Prometheus.html) · [AMP quotas](https://docs.aws.amazon.com/prometheus/latest/userguide/AMP_quotas.html)
- [Amazon Managed Grafana](https://docs.aws.amazon.com/grafana/latest/userguide/what-is-Amazon-Managed-Service-Grafana.html)

**Logging, audit, compliance**
- [CloudTrail organization trails](https://docs.aws.amazon.com/awscloudtrail/latest/userguide/creating-trail-organization.html) · [CloudTrail Lake availability change](https://docs.aws.amazon.com/awscloudtrail/latest/userguide/cloudtrail-lake-service-availability-change.html)
- [Amazon Security Lake](https://docs.aws.amazon.com/security-lake/latest/userguide/what-is-security-lake.html)
- [AWS Config Developer Guide](https://docs.aws.amazon.com/config/latest/developerguide/WhatIsConfig.html) · [Conformance packs](https://docs.aws.amazon.com/config/latest/developerguide/conformance-packs.html) · [Aggregators](https://docs.aws.amazon.com/config/latest/developerguide/aggregate-data.html)
- [AWS Security Reference Architecture (Prescriptive Guidance)](https://docs.aws.amazon.com/prescriptive-guidance/latest/security-reference-architecture/welcome.html)

**Events, Health, advisors**
- [Amazon EventBridge User Guide](https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-what-is.html)
- [AWS Health API](https://docs.aws.amazon.com/health/latest/ug/health-api.html) · [Aggregating Health events (organizational view)](https://docs.aws.amazon.com/health/latest/ug/aggregate-events.html) · [Registering a delegated administrator](https://docs.aws.amazon.com/health/latest/ug/register-a-delegated-administrator.html)
- [AWS Trusted Advisor](https://docs.aws.amazon.com/awssupport/latest/user/trusted-advisor.html) · [Organizational view](https://docs.aws.amazon.com/awssupport/latest/user/organizational-view.html) · [Trusted Advisor Priority](https://docs.aws.amazon.com/awssupport/latest/user/trusted-advisor-priority.html)
- [AWS Compute Optimizer](https://docs.aws.amazon.com/compute-optimizer/latest/ug/what-is-compute-optimizer.html)

**Systems Manager**
- [Systems Manager Explorer](https://docs.aws.amazon.com/systems-manager/latest/userguide/Explorer.html) · [OpsCenter](https://docs.aws.amazon.com/systems-manager/latest/userguide/OpsCenter.html) · [Automation](https://docs.aws.amazon.com/systems-manager/latest/userguide/systems-manager-automation.html)
- [Incident Manager availability change](https://docs.aws.amazon.com/incident-manager/latest/userguide/incident-manager-availability-change.html) · [Change Manager availability change](https://docs.aws.amazon.com/systems-manager/latest/userguide/change-manager-availability-change.html)
- [Change Calendar](https://docs.aws.amazon.com/systems-manager/latest/userguide/systems-manager-change-calendar.html) · [Patch Manager](https://docs.aws.amazon.com/systems-manager/latest/userguide/patch-manager.html) · [Inventory](https://docs.aws.amazon.com/systems-manager/latest/userguide/systems-manager-inventory.html)

**Operational Excellence and troubleshooting**
- [Well-Architected Framework — Operational Excellence design principles](https://docs.aws.amazon.com/wellarchitected/latest/framework/oe-design-principles.html) · [Operational Excellence Pillar whitepaper](https://docs.aws.amazon.com/wellarchitected/latest/operational-excellence-pillar/welcome.html)
- [AWS Well-Architected Tool](https://docs.aws.amazon.com/wellarchitected/latest/userguide/intro.html)
- [AWS Fault Injection Service](https://docs.aws.amazon.com/fis/latest/userguide/what-is.html)
- [Troubleshoot Application Load Balancers](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/load-balancer-troubleshooting.html) · [NAT gateway basics](https://docs.aws.amazon.com/vpc/latest/userguide/nat-gateway-basics.html) · [Amazon RDS Proxy](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/rds-proxy.html)

---
[← Previous: Chapter 14 — Deployment, DevOps & IaC](14-Deployment-DevOps-and-IaC.md) · [Index](00-README-Start-Here.md) · [Next: Chapter 16 — Cost Optimization & FinOps →](16-Cost-Optimization-and-FinOps.md)
