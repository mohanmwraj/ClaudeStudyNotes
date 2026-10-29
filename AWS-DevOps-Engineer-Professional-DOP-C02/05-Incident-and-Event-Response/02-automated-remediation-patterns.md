# Domain 5 · 02 · Automated Remediation Patterns

> **Exam tasks:** 5.2 (configuration changes in response to events; remediating non-desired state; fleet management), 4.3 (Config remediation, alarm actions), 6.2/6.3 (automated security response). **Principles:** P1, P3, P12.

## 1. First principles

Every remediation pattern has the same three parts:

```text
DETECT  ─────────────▶  DECIDE  ─────────────▶  ACT
(signal)                (rule / filter)         (managed action > runbook > custom code)
Config rule             EventBridge pattern     SSM Automation runbook (AWS-provided first)
CloudWatch alarm        Config remediation      Alarm action (EC2 recover, ASG policy)
GuardDuty finding       Security Hub automation Lambda / Step Functions
Health event            rule                    State Manager re-apply
CloudTrail API call
```

**Design rules:**
* Prefer managed actions (P12).
* Make actions **idempotent** and **rate-limited**.
* Use an **approval** for destructive actions when the question requires a human.
* **Prevent loops,** e.g. a remediation that changes a resource and re-triggers the rule.
* **Leave an audit trail:** OpsCenter OpsItems, SNS notifications, CloudTrail.

---

## 2. The pattern catalogue

### Pattern 1: Non-compliant configuration → AWS Config auto-remediation

* **Detect:** a Config managed rule (e.g. `restricted-ssh`, `s3-bucket-public-read-prohibited`, `s3-bucket-server-side-encryption-enabled`, `cloudtrail-enabled`, `vpc-flow-logs-enabled`).
* **Act:** an **automatic remediation** with an AWS-provided runbook (`AWS-DisablePublicAccessForSecurityGroup`, `AWS-EnableS3BucketEncryption`, `AWSConfigRemediation-EnableCloudTrailLogFileValidation`, `AWS-EnableFlowLogs`, …), with an `AutomationAssumeRole`, retries and a rate.
* **Scale:** an organization conformance pack, or StackSets.
* **Answer to:** "detect and automatically correct", "continuously".

### Pattern 2: A specific API call → immediate reaction

* **Detect:** an EventBridge rule on `AWS API Call via CloudTrail`, e.g. `eventName: StopLogging`, `DeleteFlowLogs`, `PutBucketAcl`, `AuthorizeSecurityGroupIngress` with `0.0.0.0/0`.
* **Act:** Lambda or SSM Automation reverts the change (`StartLogging`, revoke the ingress rule) and notifies.
* **Better still:** **prevent** it with an SCP where possible (P2), and keep the event rule as defense in depth.

### Pattern 3: GuardDuty finding → isolate and preserve

* **Detect:** the `GuardDuty Finding` event, filtered by `type` (e.g. `UnauthorizedAccess:EC2/…`, `CryptoCurrency:EC2/BitcoinTool.B`) and `severity >= 7`.
* **Act** (Step Functions for a multi-step response):
  1. Snapshot the instance's EBS volumes (forensics).
  2. Replace its security groups with an **isolation security group** (no inbound or outbound). Existing tracked connections may persist, so pair it with NACL changes if total isolation is needed.
  3. Detach it from its ASG (`DetachInstances`, so it isn't terminated and replaced before investigation) and deregister it from target groups.
  4. Tag the instance, notify, and open an OpsItem or ticket.
* **Credentials findings** (e.g. `UnauthorizedAccess:IAMUser/InstanceCredentialExfiltration`): revoke the role's active sessions (an inline Deny with an `aws:TokenIssueTime` condition, i.e. "revoke sessions") and rotate credentials.

### Pattern 4: Security Hub → automated response at org scale

* Security Hub (CSPM) aggregates findings from GuardDuty, Inspector, Macie, Config, IAM Access Analyzer, Firewall Manager and partners, across accounts and Regions, in the delegated-admin account.
* **Automation rules** update findings automatically (suppress, change severity, add notes) based on criteria.
* **Custom actions:** an analyst selects findings → `Security Hub Findings - Custom Action` event → EventBridge → a remediation Lambda or runbook. That's "one-click remediation".
* **Fully automatic:** an EventBridge rule on `Security Hub Findings - Imported` with filters → remediation. AWS publishes an "Automated Security Response on AWS" solution with ready playbooks.

### Pattern 5: CloudWatch alarm → direct action

| Alarm on | Action |
|---|---|
| `StatusCheckFailed_System` (single instance) | EC2 **recover** action |
| `StatusCheckFailed_Instance` | EC2 **reboot** action |
| Low CPU for hours (dev instances) | EC2 **stop** action |
| Queue backlog / CPU | **Auto Scaling** policy |
| Anything operational | SNS → on-call; **Systems Manager OpsItem** with an attached runbook; or EventBridge → SSM Automation |

### Pattern 6: Exposed credentials (AWS Health)

* **Detect:** the Health event `AWS_RISK_CREDENTIALS_EXPOSED`. GuardDuty also flags anomalous use of credentials.
* **Act** (Step Functions):
  1. `UpdateAccessKey` → `Inactive`.
  2. Summarize the key's recent API calls (CloudTrail `LookupEvents`).
  3. Notify the security team.
  4. Look for unauthorized resources.
* **Prevention:** no long-term keys (P14); IAM Access Analyzer unused-access findings.

### Pattern 7: Scheduled maintenance (AWS Health) → controlled action

* **Detect:** `AWS Health Event` with `eventTypeCode` such as `AWS_EC2_INSTANCE_RETIREMENT_SCHEDULED` or `AWS_EC2_PERSISTENT_INSTANCE_RETIREMENT_SCHEDULED`.
* **Act:** an SSM Automation (`AWS-RestartEC2Instance`, i.e. stop/start to migrate an EBS-backed instance to new hardware) inside a **maintenance window**, or create an OpsItem for the owner team.

### Pattern 8: Golden AMI updated → roll the fleet

* **Detect:** an EC2 Image Builder pipeline completes (the `EC2 Image Builder Image State Change` event with `state AVAILABLE`), or an SNS notification.
* **Act:** a Lambda updates the **launch template** (new default version), then starts an **ASG instance refresh** with checkpoints and auto rollback. Image Builder distribution can update the launch template itself.
* **Answer to:** "automatically replace all instances with the newly patched AMI with no downtime".

### Pattern 9: Fleet drift → State Manager re-converges

* State Manager associations re-apply on a schedule (P3), e.g. agent configuration, required packages, security settings.
* "Something changed configuration on some instances; return them to the standard and keep them there" → an association with compliance reporting, not a one-off Run Command.

### Pattern 10: Unapproved resources → stop or quarantine

* **Detect:** Config `approved-amis-by-id` / `approved-amis-by-tag`, `desired-instance-type`, `required-tags`.
* **Act:** an automatic remediation that stops the instance or tags it for review (runbook `AWS-StopEC2Instance`).
* **Prevent:** an SCP condition on `ec2:ImageId` or tags (`aws:RequestTag`) at `RunInstances`.

### Pattern 11: Certificates expiring

* **ACM-issued** certificates **renew automatically** if validation still works. DNS validation is best: the CNAME stays in place.
* **Imported** certificates don't renew. The `ACM Certificate Approaching Expiration` event (daily, from 45 days before expiry) plus the Config rule `acm-certificate-expiration-check` → notify and renew.

### Pattern 12: Failing container tasks

* **Detect:** `ECS Task State Change` with `lastStatus: STOPPED` and an abnormal `stoppedReason` or exit code. On EKS, Container Insights alarms.
* **Act:** notify. Deployment rollback is handled by the **ECS deployment circuit breaker** (no custom code needed).

---

## 3. Choosing the "Act" component

| Requirement | Choose |
|---|---|
| A managed fix exists | AWS-provided SSM runbook via Config remediation or EventBridge |
| Single API call or simple logic | Lambda (EventBridge target) |
| Several steps, waits, retries, human approval, parallel work across accounts | **Step Functions** (or an SSM Automation with `aws:approve` and branching) |
| Apply to many instances with rate control and an error threshold | Run Command (one-off) / State Manager (continuous) / Automation with rate control |
| Infrastructure change (scale, replace) | Auto Scaling policy, instance refresh, CloudFormation stack update |

## 4. Safety checklist for automated remediation

1. **Least-privilege role** for the remediation, scoped to the actions it performs.
2. **Idempotent:** running twice causes no harm.
3. **Rate control and a circuit breaker:** a maximum number of resources per execution; stop on errors.
4. **Loop prevention:** the remediation's own change must not re-trigger the rule endlessly. Check the actor (the `userIdentity` of the CloudTrail event), or exempt the remediation role.
5. **Human in the loop** for destructive actions when required: `aws:approve`, a Step Functions task-token callback, or a Security Hub custom action.
6. **Audit:** every action recorded (CloudTrail), a notification sent, an OpsItem for follow-up.
7. **Test:** run against a test account; use FIS for failure scenarios.

## 5. Exam traps

* **Remediation that needs a server or a cron job** when an event-driven managed path exists.
* **Terminating a compromised instance immediately** destroys evidence. Isolate and snapshot first.
* **Isolating with security groups only** may leave tracked connections open. Know the NACL complement.
* **An ASG replaces an isolated instance** if it stays in the group and fails health checks, and termination may destroy the evidence. Detach it first (or set scale-in protection and suspend `ReplaceUnhealthy`).
* **Config remediation without `AutomationAssumeRole`** fails to execute.
* **A Lambda to rotate RDS passwords** when **Secrets Manager rotation** does it natively.

## References

* Remediating with Config rules — <https://docs.aws.amazon.com/config/latest/developerguide/remediation.html>
* GuardDuty findings with EventBridge — <https://docs.aws.amazon.com/guardduty/latest/ug/guardduty_findings_eventbridge.html>
* GuardDuty remediation guidance — <https://docs.aws.amazon.com/guardduty/latest/ug/guardduty_remediate.html>
* Security Hub automation rules — <https://docs.aws.amazon.com/securityhub/latest/userguide/automation-rules.html>
* Security Hub custom actions — <https://docs.aws.amazon.com/securityhub/latest/userguide/securityhub-cwe-custom-actions.html>
* Automated Security Response on AWS — <https://aws.amazon.com/solutions/implementations/automated-security-response-on-aws/>
* Using alarm actions to stop, terminate, reboot or recover — <https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/UsingAlarmActions.html>
* Systems Manager OpsCenter — <https://docs.aws.amazon.com/systems-manager/latest/userguide/OpsCenter.html>
* ACM managed renewal — <https://docs.aws.amazon.com/acm/latest/userguide/managed-renewal.html>
* Revoking IAM role temporary credentials — <https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_use_revoke-sessions.html>
