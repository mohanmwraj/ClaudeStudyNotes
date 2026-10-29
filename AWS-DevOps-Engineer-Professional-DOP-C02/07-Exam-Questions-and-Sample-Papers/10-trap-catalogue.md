# Trap Catalogue: the 60 Distractor Patterns of DOP-C02

Reread this list in the final week, and the night before the exam. Each line is a **wrong idea** that shows up again and again as a distractor, followed by the correct principle (P1–P14 from [the mental models](../00-Exam-Strategy-and-First-Principles/02-first-principles-mental-models.md)). Being able to recognize these in a few seconds is worth more than memorizing service limits.

---

## SDLC and deployments

1. **"Poll the repository / bucket / registry for changes."** → Use an EventBridge rule or a V2 trigger (P1).
2. **"Use the AWS managed key for cross-account artifacts."** → AWS managed keys can't be shared. Use a customer managed key, and grant the target role in the key policy (P11).
3. **"Bucket policy alone fixes cross-account AccessDenied."** → You need the bucket policy **and** the KMS key policy **and** the role trust (P2).
4. **"Plaintext CodeBuild environment variables for secrets."** → Use `secrets-manager` or `parameter-store` in the buildspec (P11).
5. **"Test reports fail the build."** → Only exit codes fail builds (P5).
6. **"Run PR tests in the main-branch pipeline."** → Use a PR-triggered build (a webhook filter group, or EventBridge on PR events).
7. **"Install the CodeDeploy agent on Lambda or Fargate."** → The agent is for EC2 and on-premises only.
8. **"Fix ApplicationStop by changing the new revision."** → `ApplicationStop` runs the **previous** revision's script, so ignore the failure once.
9. **"Run integration tests at BeforeInstall in ECS blue/green."** → No replacement task set exists yet. Use `AfterAllowTestTraffic`.
10. **"Automatic rollback without alarms catches bad releases."** → Without alarms it only catches deployment *failures*. Attach alarms (P5).
11. **"Changing the launch template replaces instances."** → It doesn't. Use an instance refresh or an `UpdatePolicy` (P4).
12. **"Rolling deployment gives the fastest rollback."** → Blue/green or immutable does (P4).
13. **"Beanstalk blue/green with the database inside the environment."** → Decouple the database first.
14. **"Use `imagedefinitions.json` for ECS blue/green."** → That file is for rolling. Blue/green uses `appspec.yaml` + `taskdef.json` + `imageDetail.json` (CodeDeploy), or ECS native blue/green.
15. **"`latest` tag in production."** → Use immutable tags or digests (P4).
16. **"CodeArtifact local cache ≈ resilience."** → Use an external connection that retains packages, plus package origin controls.
17. **"Polling or custom code for feature flags."** → Use AppConfig with a deployment strategy and alarm rollback.

## IaC, configuration management, multi-account

18. **"`DeletionPolicy` protects against replacement during updates."** → That's `UpdateReplacePolicy` (plus a stack policy).
19. **"A stack policy prevents stack deletion."** → No. Use termination protection.
20. **"Drift detection fixes drift."** → It only reports. Update the template or revert, or remediate (P3).
21. **"`NoEcho` is a secret store."** → Use dynamic references to Secrets Manager.
22. **"Exports are a fine way to share values that change often."** → Imports lock exports. Use SSM parameters.
23. **"A custom resource that only handles Create."** → It must respond to every request type, or stacks hang for up to an hour.
24. **"Self-managed StackSets auto-deploy to new accounts."** → Only service-managed StackSets with automatic deployment on an OU do.
25. **"StackSets deploy to the management account."** → Service-managed StackSets don't.
26. **"SCPs grant permissions."** → Never. They cap. So do boundaries and RCPs (P2).
27. **"SCPs restrict the management account."** → They don't.
28. **"A Region-deny SCP without global-service exemptions."** → It breaks IAM, Organizations, Support and billing.
29. **"An aggregator enforces Config rules in member accounts."** → Read-only. Deploy rules with conformance packs.
30. **"Run Command keeps a desired state."** → Use State Manager (P3).
31. **"Patch Manager Scan installs patches."** → It only reports.
32. **"OpsWorks for configuration management."** → Retired. Use Systems Manager.
33. **"Invited accounts have `OrganizationAccountAccessRole`."** → Only accounts created by Organizations do.
34. **"Enable security services account by account."** → Use a delegated administrator with org auto-enable (P13).

## Resilience

35. **"RDS Multi-AZ standby serves reads and is cross-Region."** → It's neither. Use read replicas or Aurora.
36. **"Replication = backup."** → Mistakes replicate. Use PITR, versioning, Object Lock or AWS Backup (P8).
37. **"S3 CRR copies existing objects."** → It doesn't. Use Batch Replication.
38. **"Route 53 health checks can reach private IPs."** → Use CloudWatch alarm-based health checks.
39. **"DNS failover is instant."** → Clients cache. Use Global Accelerator or ARC routing controls for speed.
40. **"One NAT gateway is fine for three AZs."** → It's a zonal single point of failure. Use one per AZ.
41. **"ASG health check type EC2 replaces app failures."** → Use type ELB.
42. **"Reserved concurrency only guarantees."** → It also **caps**.
43. **"Provisioned concurrency fixes throttling."** → It fixes cold starts.
44. **"Scale queue workers on CPU."** → Scale on backlog per instance (P9).
45. **"More capacity fixes a DynamoDB hot key."** → Fix the key design.
46. **"Vault Lock governance mode stops admins."** → Only compliance mode is immutable.
47. **"Overbuild DR."** → Choose the cheapest tier that meets both RTO and RPO (P8).

## Monitoring, events, incidents

48. **"Detailed monitoring gives memory metrics."** → Use the CloudWatch agent (P10).
49. **"Export tasks for real-time logs."** → Use subscription filters.
50. **"Metric filters backfill old logs."** → They don't.
51. **"EventBridge sees API calls without a trail."** → A trail with logging is required for `AWS API Call via CloudTrail`.
52. **"SNS topics encrypted with `aws/sns` receive alarms and EventBridge events."** → Use a customer managed key that allows the service principal.
53. **"Two S3 notifications on the same prefix and event."** → Not allowed. Fan out via SNS or EventBridge.
54. **"Terminate the compromised instance."** → Isolate, snapshot and detach first: preserve the evidence.
55. **"ECS task role pulls images and secrets."** → The **execution** role does that. The task role is for the app's API calls.
56. **"A Lambda in a VPC reaches the internet with a public subnet."** → Use NAT from private subnets.

## Security

57. **"IAM users with access keys for CI, on-premises or third parties."** → Use OIDC, Roles Anywhere, or roles with an external ID (P14).
58. **"Encrypt an existing RDS instance or EBS volume in place."** → Snapshot → copy encrypted → restore.
59. **"An ACM certificate for CloudFront in the app's Region."** → It must be in us-east-1.
60. **"Event history is the audit trail."** → 90 days, management events only. Use an organization trail + log validation + a log-archive account (+ data events for object access).
