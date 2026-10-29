# Domain 4 · 02 · Log Pipelines: Collection, Storage, Encryption and Analysis

> **Exam tasks:** 4.1 (secure storage, metric filters, subscriptions, retention and lifecycle, Logs Insights, KMS), 4.2 (real-time streams, Athena), 4.3 (S3 events to process logs). **Principles:** P10 (logs are events), P9 (streams decouple), P11 (encryption), P13 (centralize).

## 1. First principles

1. **A log pipeline has four stages: source → transport → store → query.** Every exam question picks a product at one of these stages, and the right pick depends on two properties: **latency** (real time vs batch) and **retention cost** (hot vs archival).
2. **Real time means streaming.** Subscription filters, Kinesis and Firehose are streams. Export tasks, S3 batch processing and Athena are batch. "Within seconds" never means an export task.
3. **Hot storage is for recent questions; cheap storage is for long retention.** CloudWatch Logs (hot, queryable) with a **retention policy**, plus S3 (cheap, lifecycle to Glacier, Object Lock) queried by **Athena** when needed.
4. **Logs in one place, owned by a separate account** (P13). Producers can write but not delete; the security team can read.

---

## 2. Amazon CloudWatch Logs

### 2.1 Model and settings

| Element | Facts |
|---|---|
| **Log group → log streams → events** | A group per application or component; a stream per instance, container or function instance |
| **Retention** | Per log group: 1 day … 10 years, or **never expire (the default)**. "Logs are growing forever" → set retention |
| **Log classes** | **Standard** (full features) vs **Infrequent Access** (cheaper ingestion; no metric filters, subscription filters, Live Tail or anomaly detection) |
| **Encryption** | Always encrypted at rest. For **your own KMS key**, associate the key with the log group; the **key policy** must allow the `logs.<region>.amazonaws.com` service principal, scoped with the `kms:EncryptionContext:aws:logs:arn` condition |
| **Data protection policies** | Detect and **mask** sensitive data (credentials, PII) in log events as they're ingested; audit findings |
| **Live Tail** | Interactive real-time view of incoming events, for troubleshooting |
| **Log anomaly detection** | Learns patterns per log group and flags unusual events |

### 2.2 Metric filters (logs → metrics → alarms)

* **Pattern syntax:**
  * terms: `ERROR`; `"Payment failed"`; `?ERROR ?FATAL` (OR); `-DEBUG` (exclusion);
  * JSON: `{ $.level = "ERROR" && $.latencyMs > 500 }`;
  * space-delimited: `[ip, user, timestamp, request, status_code = 5*, size]`.
* A metric filter emits a value (often `1`, or a field such as `$.latencyMs`) into a **custom metric**, optionally with dimensions taken from fields, and a default value when nothing matches.
* **Metric filters apply only to events ingested *after* they're created.** There's no backfill. For historical analysis, use Logs Insights.

### 2.3 Subscription filters (real-time delivery)

* Stream matching events in near real time to **Kinesis Data Streams, Amazon Data Firehose, Lambda, or OpenSearch Service** (the console wires OpenSearch through a managed Lambda).
* **Up to two subscription filters per log group.** An **account-level subscription filter policy** applies one to many log groups.
* **Cross-account centralization:**
  1. In the central (receiving) account, create a **CloudWatch Logs destination** backed by Kinesis Data Streams or Firehose, with a **destination access policy** that allows the source accounts (or the organization).
  2. Source accounts create subscription filters that point to the destination's ARN.
  3. Typically, Firehose then writes to S3 in the log-archive account (and/or OpenSearch).

### 2.4 Export to S3 (batch)

* `CreateExportTask` copies a time range of a log group to an S3 bucket in the same Region. It isn't real time, and only one export task per account can be active at a time.
* Use it for an occasional archive. For continuous archiving, use a subscription → Firehose → S3.

### 2.5 CloudWatch Logs Insights

A purpose-built query language over one or many log groups (also cross-account from a monitoring account):

```text
fields @timestamp, @message
| filter level = "ERROR" and service = "checkout"
| stats count(*) as errors by bin(5m), errorCode
| sort errors desc
| limit 20
```

* Use `parse` for unstructured lines and `pattern` to cluster similar messages. Save queries, and add them to dashboards.
* **Insights vs Athena:** Insights for recent data still in CloudWatch Logs; **Athena** for data archived in S3, for very large or old data, and for joins with other datasets.

---

## 3. Log sources and where each one can go

| Source | Destinations | Notes |
|---|---|---|
| **Application on EC2 or on-premises** | CloudWatch Logs via the **CloudWatch agent** | Configure files in the agent JSON (see [01](01-cloudwatch-metrics-alarms-and-agent.md)) |
| **Lambda** | CloudWatch Logs (automatic; the execution role needs `logs:CreateLogStream`/`PutLogEvents`) | JSON log format and log-level filtering are configurable |
| **ECS** | `awslogs` log driver → CloudWatch Logs; **FireLens** (Fluent Bit sidecar) → CloudWatch Logs, Firehose, OpenSearch, third parties, even several at once | FireLens = flexible routing |
| **EKS** | Control-plane logs (api, audit, authenticator, controllerManager, scheduler) → CloudWatch Logs (enable per cluster); app logs via a Fluent Bit DaemonSet / Container Insights | |
| **API Gateway** | **Execution logs** and **access logs** (custom format) → CloudWatch Logs; access logs can also go to Firehose | REST APIs need the account-level **CloudWatch Logs role ARN** set in API Gateway settings |
| **ALB / NLB** | **Access logs → S3 only**, disabled by default | Query with Athena |
| **CloudFront** | Standard logs → S3 (and newer delivery options); **real-time logs → Kinesis Data Streams** | |
| **VPC Flow Logs** | CloudWatch Logs, **S3**, or Firehose; VPC, subnet or ENI level | Accept/reject records, custom fields; a security-investigation source |
| **CloudTrail** | S3 (always, for trails), optionally CloudWatch Logs; **CloudTrail Lake** (managed event data store, SQL) | See [06/03](../06-Security-and-Compliance/03-detection-auditing-and-response.md) |
| **Route 53** | Public DNS query logs → CloudWatch Logs (log group in **us-east-1**); Resolver query logs → CloudWatch Logs, S3 or Firehose | |
| **AWS WAF** | CloudWatch Logs, S3 or Firehose (names must start with **`aws-waf-logs-`**) | |
| **RDS / Aurora** | Engine logs (error, slow query, audit, PostgreSQL) **exported to CloudWatch Logs** | Enable per instance or cluster |
| **S3 access** | Server access logs → S3 (best effort); **CloudTrail data events** (reliable, near real time) | For "who read this object", prefer CloudTrail data events |

## 4. Transport and processing: streaming services

| Service | Role in a log pipeline |
|---|---|
| **Kinesis Data Streams** | Durable, ordered, replayable stream (24 h to 365 days retention); **multiple consumers** (Lambda, Managed Service for Apache Flink, KCL apps); real-time analytics such as anomaly detection, alerting or counting per window |
| **Amazon Data Firehose** (formerly Kinesis Data Firehose) | **Delivery** to S3, Redshift, OpenSearch, Splunk or HTTP endpoints; **buffering** (size/time); **Lambda transformation**; **format conversion** to Parquet/ORC; **dynamic partitioning** (e.g. `account/region/yyyy/mm/dd/`) for efficient Athena queries; no consumers to manage |
| **Lambda** | Light per-event processing: enrich, filter, forward, alert |
| **OpenSearch Service** | Full-text search, dashboards (OpenSearch Dashboards) and near-real-time log analytics |

**Pattern: S3 events to process log files** (task 4.3). Logs land in S3 (ALB logs, application batch uploads) → **S3 Event Notification** (or EventBridge) → **Lambda** parses them → writes to OpenSearch, CloudWatch Logs (`PutLogEvents`) or DynamoDB. For heavy volume, put **SQS** between S3 and Lambda (P9).

## 5. Long-term storage, lifecycle and protection

* **S3 lifecycle rules:** Standard → Standard-IA (30 days) → Glacier Instant/Flexible Retrieval → **Glacier Deep Archive**; expire after the retention period; expire noncurrent versions.
* **Integrity and immutability:**
  * **S3 Object Lock** (compliance mode) for regulatory WORM.
  * **CloudTrail log-file validation** (digest files) to prove logs weren't altered.
  * Bucket policies that deny `s3:DeleteObject` except for a break-glass role.
  * A separate **log-archive account**.
* **Encryption:**
  * **At rest:** SSE-KMS with a customer-managed key on log buckets; KMS on log groups.
  * **In transit:** TLS everywhere (bucket policies that `Deny` when `aws:SecureTransport` is false).
  * **Client-side encryption:** if the requirement says data must be encrypted before it leaves the producer.
* **IAM for collection:** producers get only `logs:PutLogEvents` / `firehose:PutRecord` (write-only); analysts get read access to the archive. Nobody in the workload accounts can delete the archive.

## 6. Querying archived logs with Athena

* Define tables over S3 prefixes. AWS documents ready-made DDL for **CloudTrail, ALB, CloudFront and VPC Flow Logs**.
* Use **partition projection** (date and account partitions computed from the path) so new partitions need no `MSCK REPAIR`.
* **Cost = data scanned.** Use **Parquet** (Firehose format conversion), partitioning and column selection.
* **Visualize** with Amazon Quick Sight on Athena.

## 7. Exam traps

* **"Real-time" processing of CloudWatch Logs** → a **subscription filter**, not an export task.
* **A third subscription filter on a log group** isn't allowed (the maximum is two). Fan out downstream, e.g. Kinesis Data Streams with several consumers.
* **Metric filters don't backfill.**
* **ALB access logs go only to S3** and must be enabled.
* **Log-group KMS encryption fails** if the key policy doesn't allow the CloudWatch Logs service principal for that Region.
* **Cross-account log centralization** uses a **Logs destination** (receiving side) + subscription filters (sending side), or a central Firehose. Not IAM users in every account.
* **Log retention "never expire" by default** quietly grows cost. Set retention on every log group (enforce it with Config rule `cw-loggroup-retention-period-check`).

## References

* Filter and pattern syntax — <https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/FilterAndPatternSyntax.html>
* Subscription filters — <https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/Subscriptions.html>
* Cross-account log data sharing with subscriptions — <https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/CrossAccountSubscriptions.html>
* Encrypt log data with AWS KMS — <https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/encrypt-log-data-kms.html>
* Log classes — <https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/CloudWatch_Logs_Log_Classes.html>
* Logs Insights query syntax — <https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/CWL_QuerySyntax.html>
* Amazon Data Firehose dynamic partitioning — <https://docs.aws.amazon.com/firehose/latest/dev/dynamic-partitioning.html>
* ALB access logs — <https://docs.aws.amazon.com/elasticloadbalancing/latest/application/load-balancer-access-logs.html>
* Querying AWS service logs with Athena — <https://docs.aws.amazon.com/athena/latest/ug/querying-aws-service-logs.html>
* ECS FireLens — <https://docs.aws.amazon.com/AmazonECS/latest/developerguide/using_firelens.html>
