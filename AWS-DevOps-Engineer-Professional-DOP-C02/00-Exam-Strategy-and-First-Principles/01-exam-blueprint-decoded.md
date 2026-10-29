# 01 · The Exam Blueprint, Decoded

This file restates every official task statement for DOP-C02 and adds what the exam actually tests behind each one, plus where this repo covers it. The task statements come from the [official exam guide](https://docs.aws.amazon.com/aws-certification/latest/devops-engineer-professional-02/devops-engineer-professional-02.html), checked on 2026-10-29.

**How to read the "What it really tests" column:** these are the decisions that scenario questions turn on. If you can make each decision and explain why the alternatives lose, you are ready for that task.

---

## Format and scoring, and what they imply

* **75 questions in 180 minutes.** That is 2 minutes 24 seconds each. Professional-level stems are long, often 100–200 words with 4–6 options of 2–4 lines each. Reading is the bottleneck, not knowledge. See [03-decoding-questions-and-elimination.md](03-decoding-questions-and-elimination.md).
* **10 of the 75 are unscored and unmarked.** A weird question may be one of them. Don't let it shake you; answer it and move on.
* **Scaled score 750 of 1,000, compensatory.** A weak domain can be offset by a strong one, so don't over-invest in your best domain at the expense of the largest ones (Domain 1 is 22%).
* **No penalty for guessing.** Every question gets an answer, even if it's a flag-and-guess.
* **Multiple response** questions say "Select TWO" or "Select THREE". You must pick exactly that many, and there is no partial credit. Treat each option as a true/false statement against the requirements.

---

## Domain 1 · SDLC Automation (22%)

| Task | Official skills (condensed) | What it really tests | Where |
|---|---|---|---|
| **1.1** Implement CI/CD pipelines | Code, image and artifact repositories; version control integrated with pipelines; build processes (CodeBuild); build and deployment secrets (Secrets Manager, Parameter Store); deployment strategies (CodeDeploy); single- and multi-account pipeline patterns | Event-driven pipeline triggers (EventBridge, never polling); cross-account pipelines (KMS customer-managed key + artifact bucket policy + cross-account roles); secrets injected at build time from Secrets Manager or Parameter Store, never in source or plaintext environment variables; manual approval placement | [01-SDLC-Automation/01](../01-SDLC-Automation/01-source-build-and-artifacts.md), [02](../01-SDLC-Automation/02-codepipeline-design-and-multi-account.md) |
| **1.2** Integrate automated testing | Test types and their place in the pipeline; builds on pull requests and merges; load/stress tests; health from exit codes; unit tests and coverage; invoking AWS services for testing | Fast tests early (unit, static analysis, security scan on PR), slow tests later (integration, load); a non-zero exit code fails a CodeBuild phase, which fails the action; CodeBuild test reports; Lambda or Step Functions invoked from a pipeline for custom tests | [01-SDLC-Automation/04](../01-SDLC-Automation/04-testing-in-pipelines.md) |
| **1.3** Build and manage artifacts | Artifact repositories (CodeArtifact, S3, ECR); build tools that produce artifacts; automated EC2 and container image builds (EC2 Image Builder) | CodeArtifact upstreams and external connections (a proxy for npm/PyPI/Maven); ECR lifecycle policies, image scanning, cross-Region/cross-account replication, immutable tags; Image Builder pipelines producing golden AMIs on a schedule or on a parent-image update; S3 lifecycle for old artifacts | [01-SDLC-Automation/01](../01-SDLC-Automation/01-source-build-and-artifacts.md) |
| **1.4** Deployment strategies for instance, container and serverless | EC2/ECS/EKS/Lambda methodologies; storage patterns (EFS, S3, EBS); mutable vs immutable; distribution tools (CodeDeploy, Image Builder); repository permissions; deployment agents (CodeDeploy agent); troubleshooting; blue/green and canary | CodeDeploy deployment configurations and lifecycle hooks per platform; automatic rollback on CloudWatch alarms; Elastic Beanstalk deployment policies; Lambda alias traffic shifting (SAM `DeploymentPreference`); ECS blue/green with two target groups and a test listener; ASG + CodeDeploy integration | [01-SDLC-Automation/03](../01-SDLC-Automation/03-deployment-strategies.md) |

## Domain 2 · Configuration Management and IaC (17%)

| Task | Official skills (condensed) | What it really tests | Where |
|---|---|---|---|
| **2.1** Define infrastructure and reusable components | IaC templates (SAM, CloudFormation, CDK); StackSets across accounts and Regions; choosing configuration-management services (OpsWorks, Systems Manager, Config, AppConfig); governance in reusable templates (Service Catalog, modules, CDK) | Change sets before updates; `DeletionPolicy`/`UpdateReplacePolicy` for stateful resources; stack policies; `cfn-init` + `cfn-signal` + `CreationPolicy`; custom resources; drift detection; StackSets service-managed permissions with automatic deployment to new accounts in an OU; Service Catalog for self-service with guardrails | [02-Configuration-Management-and-IaC/01](../02-Configuration-Management-and-IaC/01-cloudformation-deep-dive.md), [02](../02-Configuration-Management-and-IaC/02-cdk-sam-and-service-catalog.md) |
| **2.2** Automate account creation, onboarding and security | Account structures; creating and managing accounts (Organizations, Control Tower); IAM for multi-account (SCPs, role assumption); governance and security at scale (Config, Control Tower, Security Hub, Detective, GuardDuty, Service Catalog, SCPs) | Control Tower Account Factory (and Account Factory for Terraform); OU design; SCPs as guardrails that never grant; delegated administrators for security services; automatic enrollment of new accounts | [02-Configuration-Management-and-IaC/03](../02-Configuration-Management-and-IaC/03-multi-account-organizations-control-tower.md) |
| **2.3** Automate complex tasks at scale | Inventory, configuration and patching (Systems Manager, Config); Lambda automations (SDKs, Lambda, Step Functions); desired-state configuration (OpsWorks, State Manager); software compliance (Systems Manager) | Patch Manager baselines, patch groups and maintenance windows (or patch policies via Quick Setup); State Manager associations; Automation runbooks with approvals and rate control; Run Command concurrency and error thresholds; Inventory + Resource Data Sync to S3 + Athena | [02-Configuration-Management-and-IaC/04](../02-Configuration-Management-and-IaC/04-systems-manager-and-config.md) |

## Domain 3 · Resilient Cloud Solutions (15%)

| Task | Official skills (condensed) | What it really tests | Where |
|---|---|---|---|
| **3.1** Highly available solutions | Multi-AZ and multi-Region for the compute and data layers; SLAs; replication and failover for stateful services; turning business requirements into resilience; removing single points of failure; cross-Region features (DynamoDB, RDS, Route 53, S3, CloudFront); cross-AZ load balancing | RDS Multi-AZ vs read replicas vs Aurora Global Database; DynamoDB global tables; S3 Cross-Region Replication (+ Replication Time Control); Route 53 failover/latency routing with health checks; CloudFront origin groups | [03-Resilient-Cloud-Solutions/01](../03-Resilient-Cloud-Solutions/01-high-availability.md) |
| **3.2** Scalable solutions | Scaling metrics; loosely coupled and serverless architectures; containers; remediating scaling issues; auto scaling, load balancing and caching; ECS/EKS; multi-Region; API Gateway, Lambda, Fargate | Target tracking vs step vs predictive scaling; scaling on SQS backlog per instance; lifecycle hooks, warm pools, instance refresh; ECS service auto scaling and capacity providers; Lambda reserved and provisioned concurrency | [03-Resilient-Cloud-Solutions/02](../03-Resilient-Cloud-Solutions/02-scalability-and-auto-scaling.md) |
| **3.3** Automated recovery for RTO/RPO | DR concepts; AWS Backup and DR strategies (pilot light, warm standby); recovery procedures; testing Multi-AZ and multi-Region failover; cross-Region backup; recovering from backend failure behind a load balancer | Matching RTO/RPO to backup-restore, pilot light, warm standby or multi-site; AWS Backup plans with cross-Region and cross-account copy and Vault Lock; Elastic Disaster Recovery; testing failover (RDS reboot with failover, FIS) | [03-Resilient-Cloud-Solutions/03](../03-Resilient-Cloud-Solutions/03-disaster-recovery-and-backup.md) |

## Domain 4 · Monitoring and Logging (15%)

| Task | Official skills (condensed) | What it really tests | Where |
|---|---|---|---|
| **4.1** Collect, aggregate and store logs and metrics | Namespaces, dimensions, resolution; real-time ingestion; encryption of logs and metrics; IAM for collection; metric filters; metric streams (Firehose); custom metrics (CloudWatch agent); retention and lifecycle; subscriptions (Kinesis, Lambda, OpenSearch); filter syntax and Logs Insights; KMS for log groups | The CloudWatch agent for memory/disk metrics and log files; metric filters → alarms; subscription filters → Firehose → S3 for central storage; cross-account log aggregation; KMS key policy for CloudWatch Logs | [04-Monitoring-and-Logging/01](../04-Monitoring-and-Logging/01-cloudwatch-metrics-alarms-and-agent.md), [02](../04-Monitoring-and-Logging/02-logs-pipelines-and-analysis.md) |
| **4.2** Audit, monitor and analyze | Anomaly-detection alarms; common metrics; Inspector; Config rules; CloudTrail events; dashboards and Quick Sight; alarms on standard and custom metrics; X-Ray for containers, API Gateway and Lambda; real-time stream analysis; Athena and Logs Insights | Anomaly detection bands; composite alarms; X-Ray daemon/sidecar vs active tracing; Athena over CloudTrail and ALB logs; cross-account observability | [04-Monitoring-and-Logging/03](../04-Monitoring-and-Logging/03-tracing-dashboards-and-analytics.md) |
| **4.3** Automate monitoring and event management | Event-driven patterns (S3/EventBridge → SNS/Lambda); auto scaling across services; alarm actions (SNS, Lambda, EC2 recovery); health checks (ALB, Route 53); Config remediation; agents (SSM Agent, CloudWatch agent) | Alarm actions (EC2 recover/reboot/stop/terminate); EventBridge rule patterns; Route 53 health checks on CloudWatch alarms for private resources; Config auto-remediation with SSM Automation | [04-Monitoring-and-Logging/01](../04-Monitoring-and-Logging/01-cloudwatch-metrics-alarms-and-agent.md), [05-Incident-and-Event-Response/02](../05-Incident-and-Event-Response/02-automated-remediation-patterns.md) |

## Domain 5 · Incident and Event Response (14%)

| Task | Official skills (condensed) | What it really tests | Where |
|---|---|---|---|
| **5.1** Manage event sources | Event sources (AWS Health, EventBridge, CloudTrail); event-driven architectures (fan-out, streaming, queuing); event processing workflows (SQS, Kinesis, SNS, Lambda, Step Functions) | Which events exist natively and which only via CloudTrail; AWS Health organizational view; SNS fan-out to SQS; DLQs; Step Functions for multi-step remediation with waits and retries | [05-Incident-and-Event-Response/01](../05-Incident-and-Event-Response/01-event-sources-and-routing.md) |
| **5.2** Configuration changes in response to events | Fleet management (Systems Manager, Auto Scaling); configuration management (Config); applying changes; modifying infrastructure in response to events; remediating undesired state | Config rule → automatic remediation; EventBridge → SSM Automation; ASG lifecycle hooks for custom actions; State Manager to re-converge | [05-Incident-and-Event-Response/02](../05-Incident-and-Event-Response/02-automated-remediation-patterns.md) |
| **5.3** Troubleshoot failures | CloudWatch, X-Ray; AWS Health, CloudWatch, OpsCenter; root-cause analysis; failed deployments (CodePipeline, CodeBuild, CodeDeploy, CloudFormation, Synthetics); failed processes (auto scaling, ECS, EKS) | Reading the failure signal: CodeDeploy agent logs, `UPDATE_ROLLBACK_FAILED`, ASG activity history, ECS stopped-task reasons, failed health checks | [05-Incident-and-Event-Response/03](../05-Incident-and-Event-Response/03-troubleshooting-playbook.md) |

## Domain 6 · Security and Compliance (17%)

| Task | Official skills (condensed) | What it really tests | Where |
|---|---|---|---|
| **6.1** Identity and access at scale | IAM entities for humans and machines; federation (identity providers, IAM Identity Center); permissions boundaries; SCPs; least privilege; role- and attribute-based access control; credential rotation (Secrets Manager); MFA, STS, instance profiles | The policy evaluation logic; permission boundaries for safe delegation; ABAC with tags; Identity Center permission sets; Secrets Manager automatic rotation | [06-Security-and-Compliance/01](../06-Security-and-Compliance/01-iam-at-scale.md) |
| **6.2** Automate security controls and data protection | Network security (security groups, NACLs, Network Firewall, WAF, Shield); PKI and certificates; data classification and encryption; controls across accounts and Regions (Security Hub, Organizations, Control Tower, Systems Manager); defense in depth; Macie; KMS, CloudHSM, ACM | KMS key policies and grants; multi-Region keys; ACM certificate renewal and its Regional scope (CloudFront needs us-east-1); WAF managed rules via Firewall Manager; Macie automated discovery | [06-Security-and-Compliance/02](../06-Security-and-Compliance/02-data-protection-and-network-security.md) |
| **6.3** Security monitoring and auditing | CloudTrail, Config, VPC Flow Logs, CloudFormation drift; GuardDuty, Inspector, IAM Access Analyzer, Config; common threats (insecure traffic, exposed keys, public or unencrypted S3); alerting; logging; analyzing findings | Organization trail with log-file validation into a locked-down log-archive account; GuardDuty findings → EventBridge → remediation; Access Analyzer for external access and unused access; S3 Block Public Access at the account/org level | [06-Security-and-Compliance/03](../06-Security-and-Compliance/03-detection-auditing-and-response.md) |

---

## Explicitly out of scope (per the exam guide)

The exam guide says the candidate is **not** expected to:

* have advanced networking knowledge (routing algorithms, failover techniques);
* give deep-level security recommendations to developers;
* design, query or performance-tune databases;
* develop full-stack application code.

**What that means in practice:** when an option hinges on BGP tuning, SQL query plans or application refactoring, it is rarely the answer. The DOP answer is almost always an **AWS-native operational mechanism**: a pipeline feature, a deployment configuration, an IaC construct, an event rule, a managed remediation or a policy.

---

## Technologies and concepts listed by the guide

Application deployment · application integration · application pipelines · automation · code repository best practices · cost optimization · deployment requirements · hybrid deployments · IAM policies · metrics, monitoring, alarms and logging · network ACL and security group design · operational best practices · **rollback procedures**.

"Rollback procedures" is in that list for a reason. A large share of DOP questions turn on **how a change is undone automatically**. Every deployment mechanism in folder 01 is described together with its rollback.
