# Domain 6 · 03 · Security Monitoring, Auditing and Detection

> **Exam task:** 6.3 (CloudTrail, Config, VPC Flow Logs, drift detection; GuardDuty, Inspector, IAM Access Analyzer; common threats; alerting on anomalous security events; logging; analyzing findings). **Principles:** P1 (events), P13 (org-wide, delegated admin), P10 (signals).

## 1. First principles

1. **Audit = an immutable record of who did what, plus what the state was.**
   * **CloudTrail** answers *who called which API, when, and from where*.
   * **Config** answers *what the resource looked like at that moment*.

   You need both, from **every account and Region**, stored where the audited parties **can't change them**.
2. **Detection = signals + a known-bad pattern or an anomaly.**
   * **Managed detectors:** GuardDuty (threats), Inspector (vulnerabilities), Macie (sensitive data), Access Analyzer (unintended access).
   * **Your own detectors:** CloudTrail-based alarms, Config rules.
   * **Aggregation:** Security Hub.
3. **A finding nobody acts on is just a log entry.** Route findings by **severity** to people and to automation (EventBridge, see [05/02](../05-Incident-and-Event-Response/02-automated-remediation-patterns.md)).

---

## 2. AWS CloudTrail

| Feature | Facts |
|---|---|
| **Event history** | The last **90 days** of **management events** per Region, free, always on, viewable and searchable. Not a long-term audit store, and not the input for EventBridge API-call rules (those need a trail) |
| **Trails** | Deliver events to **S3** (plus optionally **CloudWatch Logs** and SNS notifications of file delivery). A **multi-Region** trail is the default and recommended |
| **Organization trail** | Created in the management account or a **delegated administrator**; logs **every member account**, and members can't modify or delete it |
| **Event types** | **Management events** (control-plane; read and write), **data events** (S3 object-level, Lambda invoke, DynamoDB item-level and more; off by default; extra cost; selected by **advanced event selectors**), **network activity events** (VPC endpoint calls), **Insights events** (unusual API volume or error rates) |
| **Integrity** | **Log file integrity validation:** hourly **digest files** (SHA-256 hashes, signed) let you prove logs weren't modified or deleted (`aws cloudtrail validate-logs`) |
| **Protection** | SSE-KMS with a customer-managed key; a bucket in the **Log Archive account**; a bucket policy allowing only CloudTrail writes; **Object Lock** or MFA delete; an **SCP denying `StopLogging`/`DeleteTrail`/`UpdateTrail`** |
| **CloudTrail Lake** | Managed **event data stores** with SQL queries, long retention, org-wide collection; can also ingest non-AWS activity events |
| **Querying trails in S3** | **Athena** (CloudTrail table DDL, partition projection) |

**Exam patterns:**
* "Ensure no one, not even account administrators, can disable or tamper with audit logging in any account" → organization trail + SCP + Log Archive bucket with restrictive policy and Object Lock + log file validation.
* "Prove logs weren't altered" → **log file integrity validation**.
* "Who deleted this S3 object?" → **data events** must be enabled for that bucket (management events don't capture object-level operations).

## 3. AWS Config for auditing

* **Configuration history and timeline** per resource, with the **CloudTrail events that changed it**.
* An **organization aggregator** in the audit or security account gives a single view of configuration and compliance across all accounts and Regions.
* **Conformance packs** map to frameworks (CIS, PCI DSS, NIST) and produce audit evidence. **AWS Audit Manager** can collect Config, CloudTrail and Security Hub evidence for audits.
* **Drift:** the Config rule `cloudformation-stack-drift-detection-check` turns CloudFormation drift into a compliance signal (see [02/01 §9](../02-Configuration-Management-and-IaC/01-cloudformation-deep-dive.md#9-drift-detection)).

## 4. The detection services and how they differ

| Service | Detects | Inputs | Org-wide | Output |
|---|---|---|---|---|
| **Amazon GuardDuty** | **Threats:** compromised instances or credentials, reconnaissance, crypto-mining, data exfiltration, malware, anomalous behaviour | **CloudTrail management events, VPC Flow Logs, DNS logs** (analyzed automatically, without enabling them yourself), plus protection plans: **S3 Protection** (data events), **EKS** audit logs, **Runtime Monitoring** (EKS/ECS/EC2 agent), **Malware Protection** (EBS volumes; S3 uploads), **RDS Protection** (login activity), **Lambda Protection** (network activity) | Delegated admin + **auto-enable** for new accounts, per Region | Findings with severity → EventBridge, Security Hub, Detective |
| **Amazon Inspector** | **Vulnerabilities:** software CVEs and network reachability | EC2 (SSM Agent or agentless), **ECR images** (enhanced scanning, continuous), **Lambda** (packages and code) | Delegated admin, auto-enable | Findings with risk scores → EventBridge, Security Hub; SBOM export |
| **Amazon Macie** | **Sensitive data** in S3; bucket posture | S3 objects and bucket metadata | Delegated admin | Findings → EventBridge, Security Hub |
| **IAM Access Analyzer** | **Unintended external access** to resources (S3, KMS, IAM roles, Lambda, SQS, SNS, Secrets Manager, snapshots, ECR, EFS, DynamoDB, …) and **unused access** | Resource and IAM policies (logic-based reasoning), plus activity for unused access | Organization as the zone of trust | Findings → EventBridge, Security Hub |
| **AWS Config** | **Configuration non-compliance** against rules | Configuration items | Org rules, conformance packs, aggregator | Compliance → EventBridge, Security Hub |
| **Amazon Detective** | Not a detector: an **investigation** tool. Behaviour graphs to pivot from a finding to related entities, IPs and activity over time | CloudTrail, VPC Flow Logs, GuardDuty findings, EKS audit logs | Delegated admin | Visual investigation |
| **AWS Security Hub (CSPM)** | **Aggregates** findings (ASFF) from all of the above plus partners; runs **security standards** checks (AWS FSBP, CIS, PCI DSS, NIST) | Integrations and Config-based controls | Delegated admin, central configuration, **cross-Region aggregation** | Prioritized findings, automation rules, custom actions → EventBridge |

**Mnemonic:**
* GuardDuty = **threats**;
* Inspector = **vulnerabilities**;
* Macie = **sensitive data**;
* Access Analyzer = **who outside can get in** (and what's unused);
* Config = **configuration rules**;
* Detective = **investigate**;
* Security Hub = **aggregate and score**.

> **2025 note:** AWS launched a new, unified **Security Hub** (general availability 2025-12-02) that correlates GuardDuty, Inspector and CSPM signals into risks, and renamed the original service **Security Hub CSPM**. Exam questions describe the original service's capabilities above.

## 5. Common cloud security threats: detect and respond

| Threat (named in the exam guide) | Detect | Prevent or respond |
|---|---|---|
| **Exposed AWS access keys** | AWS Health `AWS_RISK_CREDENTIALS_EXPOSED`; GuardDuty anomalous-credential findings; Access Analyzer unused keys | Deactivate the key automatically (EventBridge → Step Functions); move to roles, OIDC, Roles Anywhere |
| **S3 bucket with public access** | Config `s3-bucket-public-read-prohibited` / `…-write-…`; Access Analyzer; Macie posture; Security Hub control | **S3 Block Public Access at account level** (and an SCP preventing changes to it); auto-remediation |
| **S3 bucket with encryption disabled / unencrypted uploads** | Config `s3-bucket-server-side-encryption-enabled`; Security Hub | Default encryption (SSE-S3 is now automatic; enforce SSE-KMS by bucket policy or SCP) |
| **Insecure web traffic (HTTP)** | Config `alb-http-to-https-redirection-check`, `s3-bucket-ssl-requests-only`, CloudFront viewer protocol checks | HTTPS redirect listeners; viewer protocol policy; `aws:SecureTransport` deny |
| **Root user activity** | CloudTrail → EventBridge rule on `userIdentity.type = Root`, or a metric filter + alarm (a CIS benchmark control) | MFA on root; no root access keys; centrally managed root access |
| **Unusual API activity** | CloudTrail Insights; GuardDuty | Investigate with Detective |
| **Compromised EC2** (mining, C2 traffic) | GuardDuty (`CryptoCurrency:EC2/…`, `Backdoor:EC2/…`) | Isolate, snapshot, investigate (see [05/02](../05-Incident-and-Event-Response/02-automated-remediation-patterns.md)) |
| **Vulnerable packages and images** | Inspector | Patch (SSM), rebuild images; block deployment in the pipeline |
| **Overly permissive security groups** | Config `restricted-ssh`, `vpc-sg-open-only-to-authorized-ports`; Firewall Manager audit; Security Hub | Auto-remediation; Firewall Manager common SGs |

## 6. Alerting on anomalous security events

* **Route findings by severity:** an EventBridge rule on `GuardDuty Finding` with `detail.severity >= 7` (high) → SNS/PagerDuty; medium → a ticket; everything → Security Hub.
* **CIS-style CloudTrail alarms:** send the trail to CloudWatch Logs, then add **metric filters + alarms** for:
  * unauthorized API calls (`errorCode = AccessDenied*`);
  * console sign-in without MFA;
  * root usage;
  * IAM policy changes;
  * CloudTrail configuration changes;
  * console authentication failures;
  * disabling or deleting KMS keys;
  * S3 bucket policy changes;
  * Config changes;
  * security group, NACL, gateway, route-table and VPC changes.

  Security Hub's CIS standard checks that these alarms exist.
* **Central notification:** forward findings from all Regions to the aggregation Region (Security Hub cross-Region aggregation, or EventBridge cross-Region rules), then a single routing configuration.
* **GuardDuty finding updates:** new findings are published to EventBridge within about 5 minutes. **Updated** occurrences follow the configurable frequency (15 minutes, 1 hour or 6 hours).

## 7. Reference audit architecture (multi-account)

```text
Management account ──(delegates)──▶ Security/Audit account                      Log Archive account
  Organizations, SCPs,                 GuardDuty / Inspector / Macie admin          S3: org CloudTrail logs
  org CloudTrail (or delegated)        Security Hub admin + cross-Region agg.         (KMS CMK, Object Lock,
                                       Config org aggregator                          log validation)
                                       Access Analyzer (org zone of trust)          S3: Config history
                                       Detective admin                              Central CloudWatch Logs
                                       EventBridge → response automation              via Firehose
Every member account: GuardDuty/Inspector/Macie/Security Hub auto-enabled; Config recorder (StackSets/Control Tower);
                      SCP prevents disabling any of it.
```

## 8. Exam traps

* **Event history (90 days, management events only) isn't an audit archive.** Create an organization trail.
* **Object-level S3 access** isn't in management events. Enable **data events** (or S3 server access logs).
* **GuardDuty doesn't need you to enable VPC Flow Logs or DNS logging;** it reads those sources independently.
* **GuardDuty and Inspector are Regional:** enable them in **every Region in use** (with org auto-enable per Region).
* **Detective doesn't produce detections;** it investigates.
* **Security Hub needs AWS Config** enabled for its standards' Config-based controls.
* **"Tamper-proof audit trail":** log file validation + a separate account + SCP + Object Lock, not just "enable CloudTrail".

## 9. Hands-on lab: GuardDuty → EventBridge → SNS with sample findings (about 20 minutes)

[labs/lab-09-guardduty-eventbridge-sns.yaml](labs/lab-09-guardduty-eventbridge-sns.yaml) creates three things:
* an EventBridge rule on `GuardDuty Finding` with **severity ≥ 4** (numeric matching);
* an **input transformer** producing a readable message;
* an SNS topic with a policy allowing EventBridge.

Set `CreateDetector=true` only if GuardDuty isn't already enabled in the Region.

```bash
aws cloudformation deploy --stack-name dop-lab-09 \
  --template-file labs/lab-09-guardduty-eventbridge-sns.yaml \
  --parameter-overrides NotificationEmail=you@example.com CreateDetector=false
DET=$(aws guardduty list-detectors --query 'DetectorIds[0]' --output text)
aws guardduty create-sample-findings --detector-id $DET --finding-types "Recon:EC2/PortProbeUnprotectedPort"
# Within minutes an email arrives: "GuardDuty (sev 5.x) Recon:EC2/PortProbeUnprotectedPort in account …"
aws cloudformation delete-stack --stack-name dop-lab-09
# If CreateDetector=true was used, GuardDuty is disabled again when the stack is deleted (its 30-day trial is per account).
```

## References

* CloudTrail concepts (management, data, Insights events) — <https://docs.aws.amazon.com/awscloudtrail/latest/userguide/cloudtrail-concepts.html>
* Organization trails — <https://docs.aws.amazon.com/awscloudtrail/latest/userguide/creating-trail-organization.html>
* Log file integrity validation — <https://docs.aws.amazon.com/awscloudtrail/latest/userguide/cloudtrail-log-file-validation-intro.html>
* CloudTrail Lake — <https://docs.aws.amazon.com/awscloudtrail/latest/userguide/cloudtrail-lake.html>
* GuardDuty foundational data sources — <https://docs.aws.amazon.com/guardduty/latest/ug/guardduty_data-sources.html>
* GuardDuty finding types — <https://docs.aws.amazon.com/guardduty/latest/ug/guardduty_finding-types-active.html>
* Amazon Inspector — <https://docs.aws.amazon.com/inspector/latest/user/what-is-inspector.html>
* Amazon Detective — <https://docs.aws.amazon.com/detective/latest/userguide/what-is-detective.html>
* Security Hub CIS controls (CloudWatch) — <https://docs.aws.amazon.com/securityhub/latest/userguide/cloudwatch-controls.html>
* Security Hub cross-Region aggregation — <https://docs.aws.amazon.com/securityhub/latest/userguide/finding-aggregation.html>
* IAM Access Analyzer findings — <https://docs.aws.amazon.com/IAM/latest/UserGuide/access-analyzer-findings.html>
