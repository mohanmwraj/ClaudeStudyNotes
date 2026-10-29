# Mock Paper 2 · Answers and Explanations

Answers for [08-mock-paper-2.md](08-mock-paper-2.md). Every option is explained. Read the explanations for the questions you got right too: you may have been right for the wrong reason.

**Tally your score by domain** using the domain labels in the questions file. A domain below 70% marks the folder to revisit.

---

### Q1 · Answer: B

**Why (P9):** The event source mapping's maximum concurrency limits how many concurrent invocations the queue drives, without the throttling errors and retries that reserved concurrency would cause. Messages simply wait in the queue.

- **A** — wrong: excess invocations are throttled, and messages are retried and can end up in the DLQ.
- **B** — correct: a native per-source concurrency cap.
- **C** — wrong: smaller batches mean more invocations, not fewer.
- **D** — wrong: unrelated to concurrency.

**Reference:** <https://docs.aws.amazon.com/lambda/latest/dg/services-sqs-scaling.html>

### Q2 · Answer: D

**Why (P12):** V2 triggers support file path filters, so each pipeline only starts when its paths change.

- **A** — wrong: every pipeline still starts and spends time and money.
- **B** — wrong: an unnecessary restructuring.
- **C** — wrong: custom code for a native feature.
- **D** — correct: native path-based triggering.

**Reference:** <https://docs.aws.amazon.com/codepipeline/latest/userguide/pipelines-filter.html>

### Q3 · Answer: A

**Why (P2):** Session policies narrow a single session's permissions to the intersection with the role's policies, without changing the role.

- **A** — correct: per-session scoping.
- **B** — wrong: an unnecessary data reorganization.
- **C** — wrong: a boundary would restrict the role for every job.
- **D** — wrong: affects every use of the role.

**Reference:** <https://docs.aws.amazon.com/IAM/latest/UserGuide/access_policies.html#policies_session>

### Q4 · Answer: C

**Why (P10):** The `procstat` plugin publishes per-process metrics, including whether the process exists, without custom code.

- **A** — wrong: an OS status check doesn't see individual processes.
- **B** — wrong: an indirect check, and it doesn't cover internal servers.
- **C** — correct: native process monitoring.
- **D** — wrong: hypervisor metrics only.

**Reference:** <https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/CloudWatch-Agent-procstat-process-metrics.html>

### Q5 · Answer: B

**Why (P3, P5):** Aspects visit every construct during synthesis and can add errors that stop synthesis. Rule packs such as cdk-nag implement common rules.

- **A** — wrong: finds problems after deployment.
- **B** — correct: shift-left enforcement in the CDK itself.
- **C** — wrong: manual and inconsistent.
- **D** — wrong: blocks all buckets.

**Reference:** <https://docs.aws.amazon.com/cdk/v2/guide/aspects.html>

### Q6 · Answer: A, D

**Why (P1, P3):** Event-driven ephemeral environments: create one on pull request events, destroy it on close or merge.

- **A** — correct: isolated stacks per pull request, tested automatically.
- **B** — wrong: no isolation; pull requests interfere with each other.
- **C** — wrong: manual cleanup leaks resources.
- **D** — correct: automatic teardown.
- **E** — wrong: not per pull request.

**Reference:** <https://docs.aws.amazon.com/codecommit/latest/userguide/monitoring-events.html>

### Q7 · Answer: C

**Why (P9):** SNS FIFO fans out to several SQS FIFO queues while keeping order per message group. Each consumer reads at its own pace.

- **A** — wrong: consumers would compete for messages, and there's no ordering.
- **B** — wrong: no ordering guarantees, and no buffering per consumer.
- **C** — correct: ordered fan-out with independent consumers.
- **D** — wrong: Firehose is a delivery service with one destination per stream.

**Reference:** <https://docs.aws.amazon.com/sns/latest/dg/sns-fifo-topics.html>

### Q8 · Answer: D

**Why (P11):** AWS Private CA keeps the CA keys in AWS-managed HSMs and issues private certificates. ACM-integrated services renew them automatically, and Kubernetes issuers can automate pods.

- **A** — wrong: public certificates aren't for internal mTLS identities.
- **B** — wrong: no trust chain or central control.
- **C** — wrong: storage, not issuance or renewal.
- **D** — correct: a managed private PKI.

**Reference:** <https://docs.aws.amazon.com/privateca/latest/userguide/PcaWelcome.html>

### Q9 · Answer: A

**Why (P5):** ECS's native blue/green provides hooks and a bake time, with no CodeDeploy resources to manage.

- **A** — correct: native blue/green.
- **B** — wrong: a rolling update has no bake-time rollback.
- **C** — wrong: manual, and DNS-based.
- **D** — wrong: a different platform.

**Reference:** <https://docs.aws.amazon.com/AmazonECS/latest/developerguide/deployment-type-blue-green.html>

### Q10 · Answer: C

**Why (P2):** `OrganizationAccountAccessRole` is created automatically only in accounts created by Organizations. Invited accounts need it created.

- **A** — wrong: invited accounts can be fully managed once the role exists.
- **B** — wrong: the role doesn't exist at all.
- **C** — correct: create the trusted role.
- **D** — wrong: unrelated.

**Reference:** <https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_accounts_access-cross-account-role.html>

### Q11 · Answer: B

**Why (P8):** A switchover changes the primary Region with no data loss and keeps the global topology.

- **A** — wrong: breaks the global database.
- **B** — correct: a planned move without data loss.
- **C** — wrong: slow, loses data written after the snapshot, and breaks the topology.
- **D** — wrong: unnecessary with a global database, and promotion is one-way.

**Reference:** <https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/aurora-global-database-disaster-recovery.html>

### Q12 · Answer: D

**Why (P10):** Sampling rules are matched by priority. A targeted rule increases sampling for one path only, centrally, with no redeployment.

- **A** — wrong: costly, and affects everything.
- **B** — wrong: metadata doesn't influence sampling.
- **C** — wrong: unrelated.
- **D** — correct: targeted sampling.

**Reference:** <https://docs.aws.amazon.com/xray/latest/devguide/xray-console-sampling.html>

### Q13 · Answer: C

**Why (P5):** API Gateway stage canaries split traffic between the current and canary deployments and provide separate metrics, then promote.

- **A** — wrong: a second API plus DNS-level routing.
- **B** — wrong: shifts backend versions, not API deployments.
- **C** — correct: native API canary.
- **D** — wrong: quotas limit requests; they don't route them.

**Reference:** <https://docs.aws.amazon.com/apigateway/latest/developerguide/canary-release.html>

### Q14 · Answer: A

**Why (P1):** CloudTrail create events carry the caller's identity. An EventBridge-triggered function applies tags at creation time.

- **A** — correct: automatic attribution.
- **B** — wrong: no real attribution.
- **C** — wrong: blocks creates but can't record who created what.
- **D** — wrong: reports costs; doesn't tag.

**Reference:** <https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-service-event-cloudtrail.html>

### Q15 · Answer: D

**Why (P5):** Rollback triggers monitor alarms during the stack operation and for a configured monitoring time afterwards, and roll back if any alarm fires.

- **A** — wrong: controls which updates are allowed, not their health.
- **B** — wrong: prevents deletion.
- **C** — wrong: waits for signals at creation; doesn't watch alarms.
- **D** — correct: alarm-gated stack updates.

**Reference:** <https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/using-cfn-rollback-triggers.html>

### Q16 · Answer: B

**Why (P14):** Identity pools exchange user identities for temporary credentials. Policy variables restrict each user to their own prefix.

- **A** — wrong: unscalable, with long-term keys.
- **B** — correct: per-user, least-privilege, temporary credentials.
- **C** — wrong: embedded credentials can be extracted.
- **D** — wrong: no access control.

**Reference:** <https://docs.aws.amazon.com/cognito/latest/developerguide/iam-roles.html>

### Q17 · Answer: A

**Why (P4, P12):** Image Builder container pipelines build, test and distribute hardened images to ECR on a schedule.

- **A** — correct: managed golden container images.
- **B** — wrong: manual and unreliable.
- **C** — wrong: finds vulnerabilities; doesn't rebuild.
- **D** — wrong: patches instances, not images.

**Reference:** <https://docs.aws.amazon.com/imagebuilder/latest/userguide/create-container-recipes.html>

### Q18 · Answer: B, E

**Why (P7):** Predictive scaling covers the recurring daily pattern ahead of time. A scheduled action covers the known one-off event.

- **A** — wrong: reactive; capacity arrives late.
- **B** — correct: forecast-based pre-launching.
- **C** — wrong: wasteful, and still can't absorb 5×.
- **D** — wrong: manual.
- **E** — correct: explicit capacity for the known date.

**Reference:** <https://docs.aws.amazon.com/autoscaling/ec2/userguide/ec2-auto-scaling-scheduled-scaling.html>

### Q19 · Answer: B

**Why (P10):** JSON metric filters can use fields as dimensions, so one filter produces a separate metric series per service.

- **A** — wrong: restructures logging unnecessarily.
- **B** — correct: per-service metrics from one filter.
- **C** — wrong: custom code.
- **D** — wrong: polling isn't a metric.

**Reference:** <https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/FilterAndPatternSyntax.html>

### Q20 · Answer: C, D

**Why (P1, P13):** Service-managed StackSets cover the CloudFormation baseline automatically. The lifecycle event drives the non-CloudFormation step.

- **A** — wrong: manual.
- **B** — wrong: manual per account.
- **C** — correct: event-driven integration with the CMDB.
- **D** — correct: automatic baseline for new accounts in the OU.
- **E** — wrong: RAM doesn't distribute templates for deployment.

**Reference:** <https://docs.aws.amazon.com/controltower/latest/userguide/lifecycle-events.html>

### Q21 · Answer: B

**Why (P6):** Disabling a stage transition stops executions from entering that stage while keeping its configuration. Earlier stages keep running.

- **A** — wrong: risky and error-prone.
- **B** — correct: a native freeze switch.
- **C** — wrong: stops test deployments too.
- **D** — wrong: causes failures and confusion.

**Reference:** <https://docs.aws.amazon.com/codepipeline/latest/userguide/transitions.html>

### Q22 · Answer: C

**Why (P13):** CloudTrail Lake collects events into managed event data stores, with SQL queries and long retention, organization-wide.

- **A** — wrong: 90 days, and management events only.
- **B** — wrong: network data.
- **C** — correct: managed SQL over long retention.
- **D** — wrong: per account, and needs logs delivered to CloudWatch first.

**Reference:** <https://docs.aws.amazon.com/awscloudtrail/latest/userguide/cloudtrail-lake.html>

### Q23 · Answer: D

**Why (P7):** `cfn-signal` calls the CloudFormation API. In private subnets without NAT, it needs the CloudFormation interface endpoint.

- **A** — wrong: there's no route, so waiting longer doesn't help.
- **B** — wrong: loses the readiness gate.
- **C** — wrong: private subnets have no internet gateway route.
- **D** — correct: a private path to the API.

**Reference:** <https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/vpc-interface-endpoints.html>

### Q24 · Answer: A

**Why (P12):** Running the Docker daemon inside a CodeBuild container requires privileged mode.

- **A** — correct: the documented requirement.
- **B** — wrong: unrelated.
- **C** — wrong: IAM roles have no Linux groups.
- **D** — wrong: Lambda compute doesn't support Docker.

**Reference:** <https://docs.aws.amazon.com/codebuild/latest/userguide/sample-docker.html>

### Q25 · Answer: D

**Why (P1):** ECS emits task state-change events with stop reasons. Filtering on them notifies only on error stops.

- **A** — wrong: unrelated signal.
- **B** — wrong: not real time.
- **C** — wrong: configuration compliance.
- **D** — correct: event-driven and filtered.

**Reference:** <https://docs.aws.amazon.com/AmazonECS/latest/developerguide/ecs_task_events.html>

### Q26 · Answer: A

**Why (P3):** The IaC generator scans existing resources and produces templates. Resource import then brings the resources under stack management without recreating them.

- **A** — correct: adopt existing resources as IaC.
- **B** — wrong: destructive and causes downtime.
- **C** — wrong: Config records configuration; it isn't IaC management.
- **D** — wrong: creates duplicates, or fails on name conflicts.

**Reference:** <https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/generate-IaC.html>

### Q27 · Answer: C

**Why (P6):** Zonal configuration deploys one AZ at a time, with a monitor duration (bake time) before moving to the next.

- **A** — wrong: one instance at a time, not AZ by AZ.
- **B** — wrong: manual coordination.
- **C** — correct: native AZ-by-AZ rollout.
- **D** — wrong: half the fleet at once, across AZs.

**Reference:** <https://docs.aws.amazon.com/codedeploy/latest/userguide/deployment-configurations-create.html>

### Q28 · Answer: B, D

**Why (P2, P11):** Cross-account secret access needs the secret's resource policy **and** a customer managed key that the other account can use, plus IAM allows on the caller's side.

- **A** — wrong: AWS managed keys can't be used cross-account.
- **B** — correct: the resource policy plus the caller's identity policy.
- **C** — wrong: replica secrets are cross-Region within the same account, and the requirement is to keep the secret in account A.
- **D** — correct: decryptable by account B.
- **E** — wrong: long-term credentials.

**Reference:** <https://docs.aws.amazon.com/secretsmanager/latest/userguide/auth-and-access_examples_cross.html>

### Q29 · Answer: D

**Why (P7):** Latency-based routing picks the Region with the lowest latency for each user. Health evaluation removes an unhealthy Region automatically.

- **A** — wrong: no latency awareness and no health checks.
- **B** — wrong: active/passive, not active/active.
- **C** — wrong: location isn't the same as latency.
- **D** — correct: latency routing plus health.

**Reference:** <https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/routing-policy-latency.html>

### Q30 · Answer: A

**Why (P10):** Logs Insights queries several log groups ad hoc in seconds, with aggregation and time binning.

- **A** — correct: immediate and flexible.
- **B** — wrong: slow to set up.
- **C** — wrong: manual and slow.
- **D** — wrong: metric filters don't backfill past data.

**Reference:** <https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/AnalyzingLogData.html>

### Q31 · Answer: B

**Why (P9):** Express workflows are designed for high-volume, short-duration, event-processing workloads with at-least-once semantics, at lower cost.

- **A** — wrong: costs more per execution, and has throughput limits unsuited to 50,000 per second.
- **B** — correct: built for exactly this.
- **C** — wrong: servers to manage.
- **D** — wrong: misuse.

**Reference:** <https://docs.aws.amazon.com/step-functions/latest/dg/concepts-standard-vs-express.html>

### Q32 · Answer: D

**Why (P12):** `codeartifact login` configures twine with a token and the endpoint. Publishing needs the publish permission plus the token-related permissions.

- **A** — wrong: not a package repository.
- **B** — wrong: binaries in Git, and pip can't install from it properly.
- **C** — wrong: no such option.
- **D** — correct: the native publish flow.

**Reference:** <https://docs.aws.amazon.com/codeartifact/latest/ug/python-configure-twine.html>

### Q33 · Answer: B

**Why (P13):** Permission sets reference customer managed policies **by name**. Identity Center attaches the policy that exists in each account, so it must exist there.

- **A** — wrong: inline policies are a different option, and you can't paste them per account.
- **B** — correct: deploy the policy everywhere, then reference it.
- **C** — wrong: permissions take effect in each account.
- **D** — wrong: they're supported.

**Reference:** <https://docs.aws.amazon.com/singlesignon/latest/userguide/permissionsetcustom.html>

### Q34 · Answer: A

**Why (P2):** WAF rate-based rules automatically block IP addresses that exceed a request rate. Scoping the rule to the login path avoids affecting other traffic.

- **A** — correct: automatic, adaptive blocking at L7.
- **B** — wrong: thousands of changing IPs exceed NACL limits.
- **C** — wrong: absorbs the attack instead of stopping it.
- **D** — wrong: detection inside containers, not edge protection.

**Reference:** <https://docs.aws.amazon.com/waf/latest/developerguide/waf-rule-statement-type-rate-based.html>

### Q35 · Answer: C

**Why (P12):** Usage plans attach throttle and quota limits to API keys, which gives per-customer tiers.

- **A** — wrong: unrelated to per-customer API limits.
- **B** — wrong: applies to everyone equally.
- **C** — correct: tiered throttling and quotas.
- **D** — wrong: not a quota mechanism, and not tier-aware.

**Reference:** <https://docs.aws.amazon.com/apigateway/latest/developerguide/api-gateway-api-usage-plans.html>

### Q36 · Answer: B

**Why (P5):** Custom deployment configurations express the health constraint directly: at least 75% healthy means at most 25% are updated at once.

- **A** — wrong: 50% at a time.
- **B** — correct: exactly the 25% constraint.
- **C** — wrong: all instances at once.
- **D** — wrong: manual coordination.

**Reference:** <https://docs.aws.amazon.com/codedeploy/latest/userguide/deployment-configurations-create.html>

### Q37 · Answer: C

**Why (P10):** RUM collects telemetry from real users' browsers, including page timings and errors, by geography and browser.

- **A** — wrong: synthetic traffic from one location.
- **B** — wrong: server side only.
- **C** — correct: real-user client-side monitoring.
- **D** — wrong: network metadata.

**Reference:** <https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/CloudWatch-RUM.html>

### Q38 · Answer: D

**Why (P3):** A Config rule detects instances from unapproved AMIs, automatic remediation stops them, and the compliance event drives notification.

- **A** — wrong: manual and slow.
- **B** — wrong: allows everything.
- **C** — wrong: scans for vulnerabilities; doesn't enforce AMI provenance.
- **D** — correct: detect, act, notify.

**Reference:** <https://docs.aws.amazon.com/config/latest/developerguide/approved-amis-by-tag.html>

### Q39 · Answer: A, C

**Why (P6):** Waves limit the blast radius, and rate controls stop a run when the error threshold is reached.

- **A** — correct: a canary wave first.
- **B** — wrong: the original problem.
- **C** — correct: an automatic stop on failures.
- **D** — wrong: a different strategy that doesn't patch running instances.
- **E** — wrong: patches may not take effect.

**Reference:** <https://docs.aws.amazon.com/systems-manager/latest/userguide/maintenance-windows.html>

### Q40 · Answer: D

**Why (P14):** Access Analyzer's unused access findings continuously identify unused roles, keys, passwords and permissions across the organization.

- **A** — wrong: limited checks; no per-permission usage analysis.
- **B** — wrong: detects unusual API volume.
- **C** — wrong: checks for admin statements, not usage.
- **D** — correct: purpose-built for unused access.

**Reference:** <https://docs.aws.amazon.com/IAM/latest/UserGuide/access-analyzer-findings.html>

### Q41 · Answer: A

**Why (P7, P4):** Immutable deployments replace instances, so shared, durable content belongs in shared storage (EFS or S3), not on instance volumes.

- **A** — correct: content outlives instances.
- **B** — wrong: fragile, and volumes are tied to one AZ.
- **C** — wrong: gives up safe rollback.
- **D** — wrong: irrelevant.

**Reference:** <https://docs.aws.amazon.com/efs/latest/ug/whatisefs.html>

### Q42 · Answer: B

**Why (P8):** Cross-Region automated backup replication copies snapshots and transaction logs to another Region, which enables point-in-time restores there.

- **A** — wrong: stays in the same Region.
- **B** — correct: point-in-time recovery in the DR Region.
- **C** — wrong: stays in the same Region, and only daily points.
- **D** — wrong: a different engine and a running replica, which isn't needed.

**Reference:** <https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_ReplicateBackups.html>

### Q43 · Answer: D

**Why (P1, P10):** Subscription filters stream matching events in near real time to Lambda, which can enrich them and notify.

- **A** — wrong: alarms can't carry per-event enrichment.
- **B** — wrong: not real time.
- **C** — wrong: polling.
- **D** — correct: real-time, enriched alerts.

**Reference:** <https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/SubscriptionFilters.html>

### Q44 · Answer: B, E

**Why (P3):** Proactive controls (Hooks) block non-compliant resources during stack operations, wherever they're deployed from. Detective controls (Config) find existing ones.

- **A** — wrong: one pipeline is easily bypassed.
- **B** — correct: deploy-time enforcement.
- **C** — wrong: manual.
- **D** — wrong: blocks all IaC.
- **E** — correct: detection of existing resources.

**Reference:** <https://docs.aws.amazon.com/cloudformation-cli/latest/hooks-userguide/what-is-cloudformation-hooks.html>

### Q45 · Answer: C

**Why (P12):** CodeDeploy supports on-premises instances: install the agent, give it credentials, register, tag, and target the tags. The agent connects outbound.

- **A** — wrong: unnecessary.
- **B** — wrong: CodeDeploy supports on-premises servers.
- **C** — correct: the documented on-premises flow.
- **D** — wrong: the agent polls outbound; no inbound ports are needed.

**Reference:** <https://docs.aws.amazon.com/codedeploy/latest/userguide/instances-on-premises.html>

### Q46 · Answer: B

**Why (P12):** GuardDuty S3 Protection analyzes S3 data-plane events for anomalous and malicious access patterns, with no custom analytics.

- **A** — wrong: classifies data content; doesn't detect access anomalies.
- **B** — correct: threat detection for S3 access.
- **C** — wrong: raw logs, no detection.
- **D** — wrong: configuration rules.

**Reference:** <https://docs.aws.amazon.com/guardduty/latest/ug/s3-protection.html>

### Q47 · Answer: A

**Why (P7):** Capacity errors are specific to an instance type in an AZ. Diversifying types and AZs gives the group alternatives.

- **A** — correct: diversification.
- **B** — wrong: a quota error is different from a capacity error.
- **C** — wrong: the group can't launch even within its current maximum.
- **D** — wrong: unrelated.

**Reference:** <https://docs.aws.amazon.com/autoscaling/ec2/userguide/ec2-auto-scaling-mixed-instances-groups.html>

### Q48 · Answer: C

**Why (P8):** Restore testing automates scheduled restores and validation, records the restore times, and cleans up, which provides audit evidence.

- **A** — wrong: manual.
- **B** — wrong: audits backup configuration, but doesn't test restores.
- **C** — correct: automated proof of restorability.
- **D** — wrong: meaningless.

**Reference:** <https://docs.aws.amazon.com/aws-backup/latest/devguide/restore-testing.html>

### Q49 · Answer: D

**Why (P2):** Cross-account ECR push needs the repository policy (resource side) plus IAM permissions (caller side), and authentication to the target registry.

- **A** — wrong: exposes the images.
- **B** — wrong: replicates in the wrong direction, and doesn't let the tooling account push.
- **C** — wrong: long-term credentials.
- **D** — correct: both sides of cross-account authorization.

**Reference:** <https://docs.aws.amazon.com/AmazonECR/latest/userguide/repository-policy-examples.html>

### Q50 · Answer: B

**Why (P10):** Application Signals provides service-level metrics from OpenTelemetry instrumentation, SLO definitions with error budgets, and burn-rate alarms.

- **A** — wrong: an average isn't an SLO, and there's no error budget.
- **B** — correct: managed SLOs.
- **C** — wrong: groups filter traces; they don't define SLOs.
- **D** — wrong: custom and coarse.

**Reference:** <https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/CloudWatch-ServiceLevelObjectives.html>

### Q51 · Answer: C

**Why (P3, P12):** Registry modules are versioned, reusable template fragments that teams reference like a resource type. One definition, maintained centrally.

- **A** — wrong: per-repository copies still drift.
- **B** — wrong: still copy and paste.
- **C** — correct: central, versioned reuse.
- **D** — wrong: enforces one property; doesn't provide the pattern.

**Reference:** <https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/modules.html>

### Q52 · Answer: A, E

**Why (P5, P7):** Readiness probes gate traffic to ready pods. Surge-first updates and draining before shutdown prevent killing in-flight requests.

- **A** — correct: no traffic before ready.
- **B** — wrong: causes an outage.
- **C** — wrong: liveness restarts stuck pods; it doesn't gate traffic.
- **D** — wrong: guarantees downtime.
- **E** — correct: graceful replacement.

**Reference:** <https://docs.aws.amazon.com/eks/latest/best-practices/load-balancing.html>

### Q53 · Answer: B

**Why (P12):** EventBridge Scheduler supports one-time schedules with IANA time zones (handling daylight-saving time), direct API targets, and automatic deletion after completion.

- **A** — wrong: a server, and UTC cron ignores daylight-saving time.
- **B** — correct: serverless, time-zone aware, one-off.
- **C** — wrong: recurring.
- **D** — wrong: Lambda's 15-minute limit.

**Reference:** <https://docs.aws.amazon.com/scheduler/latest/UserGuide/schedule-types.html>

### Q54 · Answer: D

**Why (P2):** An SCP caps every principal in member accounts, including administrators, and can exempt one ARN.

- **A** — wrong: boundaries limit what the roles can do, not who can modify them.
- **B** — wrong: detective only.
- **C** — wrong: tags don't enforce anything on their own.
- **D** — correct: preventive and org-wide.

**Reference:** <https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_policies_scps_examples_general.html>

### Q55 · Answer: A

**Why (P7):** Multi-Region Access Points give one global endpoint, and their failover controls switch routing between buckets within minutes without application changes.

- **A** — correct: purpose-built multi-Region S3 access.
- **B** — wrong: S3 requests are signed for a specific bucket endpoint, so DNS failover between buckets doesn't work cleanly.
- **C** — wrong: covers GET/HEAD/OPTIONS reads only, not writes.
- **D** — wrong: custom code.

**Reference:** <https://docs.aws.amazon.com/AmazonS3/latest/userguide/MultiRegionAccessPointFailover.html>

### Q56 · Answer: C

**Why (P7):** Step scaling adds capacity in proportion to how far the alarm metric breaches, which gives aggressive responses to big spikes.

- **A** — wrong: spikes aren't scheduled.
- **B** — wrong: a slow, single adjustment.
- **C** — correct: graduated, aggressive scaling.
- **D** — wrong: doesn't scale.

**Reference:** <https://docs.aws.amazon.com/autoscaling/ec2/userguide/as-scaling-simple-step.html>

### Q57 · Answer: A

**Why (P6, P13):** VPC sharing through RAM lets participant accounts use shared subnets while the owner keeps control of the network.

- **A** — correct: central control and distributed use.
- **B** — wrong: workloads would still run in their own VPCs.
- **C** — wrong: excessive permissions.
- **D** — wrong: not central management.

**Reference:** <https://docs.aws.amazon.com/vpc/latest/userguide/vpc-sharing.html>

### Q58 · Answer: B, C

**Why (P2, P14):** Deactivating the keys stops new use. An explicit deny on the user blocks everything, including sessions derived from the user, while keeping the user for the investigation.

- **A** — wrong: destroys evidence and doesn't stop the attacker.
- **B** — correct: immediate containment of the credentials.
- **C** — correct: quarantine without deletion.
- **D** — wrong: destroys investigation context.
- **E** — wrong: unrelated to this user's keys.

**Reference:** <https://docs.aws.amazon.com/guardduty/latest/ug/compromised-creds.html>

### Q59 · Answer: B

**Why (P11):** Automatic rotation creates new key material on schedule, keeps old material for decryption, and leaves the key ID unchanged.

- **A** — wrong: manual rotation with high effort.
- **B** — correct: native and transparent.
- **C** — wrong: data encrypted under the deleted keys becomes unrecoverable.
- **D** — wrong: KMS can't automatically rotate keys with imported key material, and you can't import different material into an existing key.

**Reference:** <https://docs.aws.amazon.com/kms/latest/developerguide/rotate-keys.html>

### Q60 · Answer: D

**Why (P5):** CloudFormation Guard evaluates templates against rules written in its policy-as-code language, and returns a failing exit code on violations.

- **A** — wrong: manual.
- **B** — wrong: unrelated.
- **C** — wrong: Inspector doesn't evaluate CloudFormation templates against custom rules.
- **D** — correct: policy as code in the pipeline.

**Reference:** <https://docs.aws.amazon.com/cfn-guard/latest/ug/what-is-guard.html>

### Q61 · Answer: A, D

**Why (P8):** Pilot light means data is live in the DR Region while compute is off but ready to be created or scaled quickly.

- **A** — correct: the "pilot light" itself, meaning live data and ready images.
- **B** — wrong: that's warm standby or active/active, with higher cost.
- **C** — wrong: backup and restore (RPO of up to 24 hours).
- **D** — correct: the ready-to-ignite infrastructure.
- **E** — wrong: slow and error-prone.

**Reference:** <https://docs.aws.amazon.com/whitepapers/latest/disaster-recovery-workloads-on-aws/disaster-recovery-options-in-the-cloud.html>

### Q62 · Answer: D

**Why (P3):** State Manager re-applies the desired state on a schedule and reports compliance, so it fixes drift within the interval.

- **A** — wrong: one-off.
- **B** — wrong: runs only at first boot.
- **C** — wrong: affects new images, not drift on running instances.
- **D** — correct: continuous desired state.

**Reference:** <https://docs.aws.amazon.com/systems-manager/latest/userguide/state-manager-about.html>

### Q63 · Answer: B

**Why (P10):** Parquet plus partitioned prefixes cut the data Athena scans.

- **A** — wrong: Athena queries S3, not CloudWatch Logs.
- **B** — correct: columnar and partitioned delivery.
- **C** — wrong: less granularity without much less data to scan.
- **D** — wrong: loses visibility.

**Reference:** <https://docs.aws.amazon.com/vpc/latest/userguide/flow-logs-s3.html>

### Q64 · Answer: C

**Why (P11):** Encryption at rest is set at creation. The TLS mount option encrypts in transit, and the file system policy enforces it.

- **A** — wrong: EBS, not EFS.
- **B** — wrong: port filtering doesn't mean encryption.
- **C** — correct: encrypted at rest and in transit, with enforcement.
- **D** — wrong: unrelated.

**Reference:** <https://docs.aws.amazon.com/efs/latest/ug/encryption-in-transit.html>

### Q65 · Answer: A

**Why (P10):** The artifact paths in the buildspec must match the files the build produces.

- **A** — correct: fix the `files` and `base-directory` patterns.
- **B** — wrong: the error is about missing paths, not permissions.
- **C** — wrong: unrelated.
- **D** — wrong: unrelated.

**Reference:** <https://docs.aws.amazon.com/codebuild/latest/userguide/build-spec-ref.html#build-spec.artifacts>

### Q66 · Answer: C

**Why (P4):** `sam package` turns local code references into S3 artifacts and produces a deployable template. Build once, deploy that artifact to many stages.

- **A** — wrong: CloudFormation can't resolve local paths.
- **B** — wrong: `sam sync` is for development and bypasses the pipeline's controls.
- **C** — correct: packaged, immutable deployment artifact.
- **D** — wrong: inline code has size limits and doesn't scale.

**Reference:** <https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/sam-cli-command-reference-sam-package.html>

### Q67 · Answer: D

**Why (P12):** On-demand capacity mode scales a stream's throughput automatically, with no shard management.

- **A** — wrong: unrelated to throughput.
- **B** — wrong: improves reads, not writes.
- **C** — wrong: a different service and semantics.
- **D** — correct: automatic capacity.

**Reference:** <https://docs.aws.amazon.com/streams/latest/dev/how-do-i-size-a-stream.html>

### Q68 · Answer: B

**Why (P13):** Hybrid activations register servers outside AWS as managed nodes, so all Systems Manager capabilities apply.

- **A** — wrong: monitoring only.
- **B** — correct: the documented approach.
- **C** — wrong: insecure, and Systems Manager doesn't connect inbound.
- **D** — wrong: unnecessary.

**Reference:** <https://docs.aws.amazon.com/systems-manager/latest/userguide/activations.html>

### Q69 · Answer: A

**Why (P10):** Flow logs record accepted and rejected flows. Rejected records pinpoint the blocked traffic, and Reachability Analyzer explains which component blocks it.

- **A** — correct: network evidence.
- **B** — wrong: API calls, not packets.
- **C** — wrong: vulnerabilities.
- **D** — wrong: application traces, not network blocks.

**Reference:** <https://docs.aws.amazon.com/vpc/latest/userguide/flow-log-records.html>

### Q70 · Answer: C

**Why (P7):** By default, canaries run outside your VPC. To reach private endpoints they must run in the VPC, and still have a path to S3 and CloudWatch.

- **A** — wrong: exposes an internal service.
- **B** — wrong: there's no route.
- **C** — correct: VPC-attached canaries.
- **D** — wrong: RUM needs real users.

**Reference:** <https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/CloudWatch_Synthetics_Canaries_VPC.html>

### Q71 · Answer: B

**Why (P12):** Data Lifecycle Manager (or AWS Backup) automates EBS snapshot schedules, retention and cross-Region copies.

- **A** — wrong: custom scripts.
- **B** — correct: native policy-driven snapshots.
- **C** — wrong: unrelated feature.
- **D** — wrong: S3, not EBS.

**Reference:** <https://docs.aws.amazon.com/ebs/latest/userguide/snapshot-lifecycle.html>

### Q72 · Answer: C, E

**Why (P2, P3, P13):** Account-level Block Public Access, protected by an SCP, prevents public buckets. Org-wide Config rules provide continuous compliance evidence.

- **A** — wrong: Macie classifies data and reports public buckets, but doesn't prevent them.
- **B** — wrong: threat detection.
- **C** — correct: prevention.
- **D** — wrong: manual.
- **E** — correct: continuous evidence.

**Reference:** <https://docs.aws.amazon.com/AmazonS3/latest/userguide/access-control-block-public-access.html>

### Q73 · Answer: A

**Why (P10):** Averages hide the tail. Percentile statistics capture the slowest users' experience.

- **A** — correct: tail-latency alerting.
- **B** — wrong: meaningless for latency.
- **C** — wrong: dilutes spikes even more.
- **D** — wrong: traffic volume, not latency.

**Reference:** <https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/cloudwatch_concepts.html#Percentiles>

### Q74 · Answer: D

**Why (P13, P14):** Centralized root access management removes long-term root credentials from member accounts and allows scoped privileged root actions centrally.

- **A** — wrong: insecure.
- **B** — wrong: the root user can't simply be deleted.
- **C** — wrong: blocks the rare required tasks with no alternative.
- **D** — correct: no credentials to manage, and the tasks are still possible.

**Reference:** <https://docs.aws.amazon.com/IAM/latest/UserGuide/id_root-user.html>

### Q75 · Answer: B

**Why (P12):** The manual approval action natively supports SNS notifications, a review URL and custom instructions.

- **A** — wrong: passive.
- **B** — correct: native notification with context.
- **C** — wrong: custom polling.
- **D** — wrong: too late.

**Reference:** <https://docs.aws.amazon.com/codepipeline/latest/userguide/approvals-action-add.html>
