# Mock Paper 3 · Answers and Explanations

Answers for [09-mock-paper-3.md](09-mock-paper-3.md). Every option is explained. Read the explanations for the questions you got right too: you may have been right for the wrong reason.

**Tally your score by domain** using the domain labels in the questions file. A domain below 70% marks the folder to revisit.

---

### Q1 · Answer: B

**Why (P2):** Connections created by API or IaC start in the `PENDING` state, and must be authorized once through the console handshake with the provider.

- **A** — wrong: the Region isn't the issue.
- **B** — correct: completes the authorization.
- **C** — wrong: CodeConnections doesn't use personal access tokens in the action.
- **D** — wrong: polling doesn't fix the authorization.

**Reference:** <https://docs.aws.amazon.com/dtconsole/latest/userguide/connections-update.html>

### Q2 · Answer: C

**Why (P2):** A permissions boundary caps identity-policy permissions. Anything the boundary doesn't allow is implicitly denied.

- **A** — wrong: `AdministratorAccess` allows everything.
- **B** — wrong: no MFA condition is involved.
- **C** — correct: the intersection rule.
- **D** — wrong: unrelated.

**Reference:** <https://docs.aws.amazon.com/IAM/latest/UserGuide/access_policies_boundaries.html>

### Q3 · Answer: A

**Why (P7):** Static stability means surviving an AZ loss without depending on scaling actions (which can be slow, or capacity-constrained, during an event). Any two AZs must hold the full peak.

- **A** — correct: N+1 at the AZ level.
- **B** — wrong: 33% of capacity is lost until replacements arrive.
- **C** — wrong: a single AZ is a single point of failure.
- **D** — wrong: still requires scaling actions during the event.

**Reference:** <https://docs.aws.amazon.com/whitepapers/latest/aws-fault-isolation-boundaries/static-stability.html>

### Q4 · Answer: A, D

**Why (P6, P5):** Region waves in successive stages limit the blast radius. An alarm-based stage condition gates progression automatically.

- **A** — correct: a progressive multi-Region rollout.
- **B** — wrong: maximum blast radius.
- **C** — wrong: manual and uncoordinated.
- **D** — correct: an automatic bake-and-check gate.
- **E** — wrong: everything at once.

**Reference:** <https://docs.aws.amazon.com/codepipeline/latest/userguide/actions-create-cross-region.html>

### Q5 · Answer: D

**Why (P4):** A replacement means CloudFormation creates the new resource first. Two resources can't share a physical name, and key-schema changes create a new, empty table.

- **A** — wrong: unrelated.
- **B** — wrong: unrelated.
- **C** — wrong: doesn't solve the name conflict.
- **D** — correct: allow the replacement, and handle the data migration.

**Reference:** <https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/troubleshooting.html>

### Q6 · Answer: B

**Why (P12):** The Infrequent Access log class lowers ingestion costs for logs that are queried rarely. It still supports Logs Insights, but not metric filters or subscriptions, which aren't used here.

- **A** — wrong: ingestion costs stay the same.
- **B** — correct: the cheapest class that keeps querying.
- **C** — wrong: loses the data needed for investigations.
- **D** — wrong: more expensive for rare queries.

**Reference:** <https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/CloudWatch_Logs_Log_Classes.html>

### Q7 · Answer: A

**Why (P13, P1):** A central bus with an organization-scoped resource policy accepts events from any member account, including new ones. Rules deployed everywhere forward the selected events.

- **A** — correct: org-wide event routing.
- **B** — wrong: no centralized automation.
- **C** — wrong: polling.
- **D** — wrong: unrelated.

**Reference:** <https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-cross-account.html>

### Q8 · Answer: C

**Why (P4, P11):** Code signing verifies the integrity and origin of packages at deployment time. Enforce mode rejects unsigned or tampered code.

- **A** — wrong: versioning doesn't verify provenance.
- **B** — wrong: blocks all deployments.
- **C** — correct: cryptographic deploy-time enforcement.
- **D** — wrong: finds vulnerabilities; doesn't verify provenance.

**Reference:** <https://docs.aws.amazon.com/lambda/latest/dg/configuration-codesigning.html>

### Q9 · Answer: D

**Why (P2):** Service-principal grants should be scoped with `aws:SourceArn` and `aws:SourceAccount`, which prevents the confused-deputy problem.

- **A** — wrong: S3 doesn't use IAM users to publish.
- **B** — wrong: encryption doesn't control who publishes.
- **C** — wrong: unrelated.
- **D** — correct: scoped service access.

**Reference:** <https://docs.aws.amazon.com/IAM/latest/UserGuide/confused-deputy.html>

### Q10 · Answer: A

**Why (P2):** Requests to global services are evaluated against the `us-east-1` Region (or are global), so Region-restriction SCPs must exempt them.

- **A** — correct: the documented Region-deny pattern.
- **B** — wrong: loses the org-wide guardrail.
- **C** — wrong: doesn't fix the global-service problem.
- **D** — wrong: SCPs still cap administrators.

**Reference:** <https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_policies_scps_examples_general.html#example-scp-deny-region>

### Q11 · Answer: C

**Why (P7):** Zonal shift moves load-balancer traffic away from one AZ quickly. Zonal autoshift lets AWS do it when it detects AZ impairments.

- **A** — wrong: Route 53 doesn't route per AZ inside one ALB.
- **B** — wrong: slow and manual.
- **C** — correct: purpose-built AZ evacuation.
- **D** — wrong: slow, and disrupts the group.

**Reference:** <https://docs.aws.amazon.com/r53recovery/latest/dg/arc-zonal-autoshift.html>

### Q12 · Answer: D

**Why (P9):** Kinesis Data Streams supports several independent consumers and replay within the retention period. Firehose has one destination per stream and no replay.

- **A** — wrong: a single destination, no replay.
- **B** — wrong: a single consumer, no replay.
- **C** — wrong: not a supported destination for Logs destinations, and messages are consumed once.
- **D** — correct: fan-out with replay.

**Reference:** <https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/CreateDestination.html>

### Q13 · Answer: A

**Why (P7):** Container health checks run inside the container and use the exit code. ECS replaces tasks whose essential container is unhealthy.

- **A** — correct: an exit-code-based health signal.
- **B** — wrong: CPU doesn't reveal a deadlock.
- **C** — wrong: unrelated.
- **D** — wrong: tracing isn't health checking.

**Reference:** <https://docs.aws.amazon.com/AmazonECS/latest/developerguide/healthcheck.html>

### Q14 · Answer: B

**Why (P1, P3):** The sharing API call is an event. Reacting to it reverts the exposure within minutes, and a Config rule backs it up with continuous detection.

- **A** — wrong: up to a week of exposure.
- **B** — correct: event-driven reversal plus detection.
- **C** — wrong: encryption doesn't stop sharing. (Snapshots encrypted with a customer managed key can't be shared publicly, but that's a separate control.)
- **D** — wrong: blocks backups.

**Reference:** <https://docs.aws.amazon.com/config/latest/developerguide/rds-snapshots-public-prohibited.html>

### Q15 · Answer: B, E

**Why (P4, P5):** A separate green stack keeps blue untouched, and weighted DNS shifts traffic gradually, with an instant rollback by weight.

- **A** — wrong: in place, so no blue/green.
- **B** — correct: an immutable parallel environment.
- **C** — wrong: destroys the rollback target.
- **D** — wrong: ALB DNS names can't be changed.
- **E** — correct: gradual shift and rollback.

**Reference:** <https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/routing-policy-weighted.html>

### Q16 · Answer: A

**Why (P11):** The key policy is the root of access to a KMS key. If it trusts no existing principal, only AWS Support can help restore access. The lockout safety check exists to prevent this.

- **A** — correct: recovery path and prevention.
- **B** — wrong: data encrypted under the old key would be lost, and key IDs can't be reused.
- **C** — wrong: IAM can't grant use of the key without the key policy's delegation.
- **D** — wrong: a different key can't decrypt the data.

**Reference:** <https://docs.aws.amazon.com/kms/latest/developerguide/key-policy-default.html>

### Q17 · Answer: C

**Why (P9):** EventBridge delivers at least once, so consumers must be idempotent. A conditional write keyed on the event identity deduplicates.

- **A** — wrong: duplicates can still arrive.
- **B** — wrong: risks losing events.
- **C** — correct: idempotent processing.
- **D** — wrong: SNS is also at-least-once.

**Reference:** <https://docs.aws.amazon.com/lambda/latest/dg/invocation-retries.html>

### Q18 · Answer: D

**Why (P9):** Scale on the work waiting: backlog per task, with a target derived from acceptable latency.

- **A** — wrong: CPU doesn't track I/O-bound work.
- **B** — wrong: bigger tasks don't add parallelism.
- **C** — wrong: peaks aren't scheduled.
- **D** — correct: a backlog-driven target.

**Reference:** <https://docs.aws.amazon.com/autoscaling/application/userguide/application-auto-scaling-target-tracking-metric-math.html>

### Q19 · Answer: C

**Why (P10):** Composite alarm actions suppression silences actions while a suppressor alarm is active, and the alarms keep evaluating.

- **A** — wrong: risky manual work.
- **B** — wrong: changes evaluation; maintenance isn't missing data.
- **C** — correct: native suppression.
- **D** — wrong: still notifies.

**Reference:** <https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/alarm-suppression.html>

### Q20 · Answer: B

**Why (P2):** Package origin controls decide, per package, whether versions may come from upstream or only from direct publishing. That blocks substitution from the public registry.

- **A** — wrong: breaks access to every public dependency.
- **B** — correct: per-package origin restrictions.
- **C** — wrong: manual and fragile.
- **D** — wrong: unrelated.

**Reference:** <https://docs.aws.amazon.com/codeartifact/latest/ug/package-origin-controls.html>

### Q21 · Answer: B

**Why (P10):** Suppression rules automatically archive matching findings. They stay recorded but don't generate alert noise.

- **A** — wrong: loses detection.
- **B** — correct: targeted, automatic archiving.
- **C** — wrong: destroys the record.
- **D** — wrong: absurd.

**Reference:** <https://docs.aws.amazon.com/guardduty/latest/ug/findings_suppression-rule.html>

### Q22 · Answer: D

**Why (P11):** KMS keys are Regional, so an artifact store must use a key in its own Region, or a multi-Region replica key.

- **A** — wrong: cross-account scenarios need customer managed keys anyway, and this weakens control.
- **B** — wrong: weakens security, and CodePipeline encrypts with a key anyway.
- **C** — wrong: moves the problem.
- **D** — correct: a Region-local key.

**Reference:** <https://docs.aws.amazon.com/codepipeline/latest/userguide/actions-create-cross-region.html>

### Q23 · Answer: B

**Why (P3):** SSM parameter types resolve the current parameter value at each stack operation, which decouples the templates from AMI IDs.

- **A** — wrong: manual.
- **B** — correct: always the latest published value.
- **C** — wrong: manual.
- **D** — wrong: custom code for a native feature.

**Reference:** <https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/parameters-section-structure.html#aws-ssm-parameter-types>

### Q24 · Answer: D

**Why (P4):** With a shared database, both versions must be compatible with the schema during the transition. Expand and contract keeps them compatible.

- **A** — wrong: removes the rollback option.
- **B** — wrong: hard to keep the data consistent.
- **C** — wrong: gives up the safety of blue/green.
- **D** — correct: compatible schema changes.

**Reference:** <https://docs.aws.amazon.com/whitepapers/latest/blue-green-deployments/best-practices-for-managing-data-synchronization-and-schema-changes.html>

### Q25 · Answer: A

**Why (P10):** Metric math expresses a rate that's independent of traffic volume, and an alarm can evaluate the expression.

- **A** — correct: a percentage alarm.
- **B** — wrong: a raw count varies with traffic.
- **C** — wrong: the wrong metric.
- **D** — wrong: not an alarm.

**Reference:** <https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/Create-alarm-on-metric-math-expression.html>

### Q26 · Answer: C

**Why (P14):** SAM policy templates generate least-privilege policies scoped to a named resource, in one line.

- **A** — wrong: breaks the function.
- **B** — wrong: high effort.
- **C** — correct: least privilege with minimal effort.
- **D** — wrong: far too broad.

**Reference:** <https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/serverless-policy-template-list.html>

### Q27 · Answer: A

**Why (P12):** Managed platform updates apply minor and patch platform versions automatically in a maintenance window, using immutable deployments.

- **A** — correct: native, automatic and safe.
- **B** — wrong: manual; the current failure.
- **C** — wrong: Beanstalk manages the platform. Patch the platform version, not the instances.
- **D** — wrong: disruptive.

**Reference:** <https://docs.aws.amazon.com/elasticbeanstalk/latest/dg/environment-platform-update-managed.html>

### Q28 · Answer: B

**Why (P11):** Object Lock in compliance mode is WORM that no user, including root, can shorten or remove during retention.

- **A** — wrong: expiration isn't protection.
- **B** — correct: regulatory WORM.
- **C** — wrong: privileged users can bypass governance mode.
- **D** — wrong: can be edited by administrators, and doesn't cover overwrites with new versions.

**Reference:** <https://docs.aws.amazon.com/AmazonS3/latest/userguide/object-lock.html>

### Q29 · Answer: D

**Why (P12):** Aurora replica auto scaling adds and removes readers based on a target metric.

- **A** — wrong: the readers are the bottleneck.
- **B** — wrong: manual.
- **C** — wrong: pools connections; doesn't add capacity.
- **D** — correct: elastic read capacity.

**Reference:** <https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/Aurora.Integrating.AutoScaling.html>

### Q30 · Answer: C

**Why (P10):** Log anomaly detection learns normal log patterns and flags deviations, without predefined filters.

- **A** — wrong: one pattern only.
- **B** — wrong: API activity, not application logs.
- **C** — correct: pattern-based anomalies.
- **D** — wrong: trace fault anomalies.

**Reference:** <https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/LogsAnomalyDetection.html>

### Q31 · Answer: A

**Why (P12):** DLQ redrive moves messages back to their source queue natively.

- **A** — correct: native redrive.
- **B** — wrong: custom code.
- **C** — wrong: mixes the queues' roles.
- **D** — wrong: impractical, and loses data.

**Reference:** <https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/sqs-configure-dead-letter-queue-redrive.html>

### Q32 · Answer: D

**Why (P12):** V2 pipeline-level variables are provided at execution start and referenced by actions, so one pipeline serves every environment.

- **A** — wrong: duplication.
- **B** — wrong: action output variables come from actions, not from the person starting the run.
- **C** — wrong: mutating the pipeline at runtime is fragile.
- **D** — correct: runtime parameterization.

**Reference:** <https://docs.aws.amazon.com/codepipeline/latest/userguide/tutorials-pipeline-variables.html>

### Q33 · Answer: A, C

**Why (P13):** Organizations sharing makes the portfolio available to the whole OU, including future accounts. TagOptions enforce tag keys and allowed values at launch.

- **A** — correct: org-wide availability.
- **B** — wrong: duplication.
- **C** — correct: controlled tag values.
- **D** — wrong: long-term users in one account.
- **E** — wrong: RAM doesn't share Service Catalog products this way.

**Reference:** <https://docs.aws.amazon.com/servicecatalog/latest/adminguide/catalogs_portfolios_sharing_how-to-share.html>

### Q34 · Answer: A

**Why (P14):** Attributes for access control pass IdP attributes as session tags, so one ABAC permission set covers every project.

- **A** — correct: ABAC at workforce scale.
- **B** — wrong: grows linearly with projects.
- **C** — wrong: long-term users.
- **D** — wrong: SCPs don't grant, and work per account.

**Reference:** <https://docs.aws.amazon.com/singlesignon/latest/userguide/abac.html>

### Q35 · Answer: B

**Why (P9):** Origin Shield adds a central caching layer, so all edge locations fetch through one place, and better cache policies raise the hit ratio.

- **A** — wrong: increases origin load.
- **B** — correct: fewer origin fetches.
- **C** — wrong: scales the origin rather than offloading it.
- **D** — wrong: doesn't cache.

**Reference:** <https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/origin-shield.html>

### Q36 · Answer: C

**Why (P5):** Shift left: a pull-request gate with a non-zero exit code on findings blocks the merge.

- **A** — wrong: too late.
- **B** — wrong: scans S3 data, not source changes.
- **C** — correct: blocks secrets before merge.
- **D** — wrong: mitigates exposure, but doesn't prevent commits.

**Reference:** <https://docs.aws.amazon.com/codebuild/latest/userguide/github-webhook.html>

### Q37 · Answer: D

**Why (P10):** Container Insights provides task- and container-level metrics and dashboards for ECS and EKS, natively.

- **A** — wrong: instance-level only, and useless on Fargate.
- **B** — wrong: request traces, not resource metrics.
- **C** — wrong: network flows only.
- **D** — correct: purpose-built container observability.

**Reference:** <https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/ContainerInsights.html>

### Q38 · Answer: C

**Why (P12, P1):** Schedules with time zones invoke managed runbooks against tagged instances, with no servers or code.

- **A** — wrong: a server to manage.
- **B** — wrong: scheduled actions apply to Auto Scaling groups, not standalone instances.
- **C** — correct: serverless and declarative.
- **D** — wrong: custom polling.

**Reference:** <https://docs.aws.amazon.com/scheduler/latest/UserGuide/what-is-scheduler.html>

### Q39 · Answer: B

**Why (P13):** Detective supports organization integration with a delegated administrator, and automatic enrollment of member accounts.

- **A** — wrong: manual.
- **B** — correct: org-wide and automatic.
- **C** — wrong: not the native organization mechanism.
- **D** — wrong: misses the member accounts.

**Reference:** <https://docs.aws.amazon.com/detective/latest/adminguide/accounts-orgs-transition.html>

### Q40 · Answer: D

**Why (P13, P6):** A centralized inspection VPC with Network Firewall, plus Transit Gateway routing (with appliance mode for symmetric flows), inspects all traffic with central rules.

- **A** — wrong: distributed, stateless toward IPS, no domain filtering.
- **B** — wrong: HTTP-layer only, at the ALBs.
- **C** — wrong: stateless and distributed.
- **D** — correct: central stateful inspection.

**Reference:** <https://docs.aws.amazon.com/network-firewall/latest/developerguide/architectures.html>

### Q41 · Answer: B

**Why (P5, P7):** The deregistration delay lets in-flight requests finish, and lifecycle hooks handle application-specific draining before the stop.

- **A** — wrong: worse.
- **B** — correct: graceful deregistration plus application drain.
- **C** — wrong: loses traffic control during the deployment.
- **D** — wrong: unrelated.

**Reference:** <https://docs.aws.amazon.com/elasticloadbalancing/latest/application/load-balancer-target-groups.html#deregistration-delay>

### Q42 · Answer: A

**Why (P13, P6):** Organizations backup policies enforce plans on every account in an OU, including new ones, and copy actions send recovery points to a separate account.

- **A** — correct: central, automatic, isolated.
- **B** — wrong: manual.
- **C** — wrong: custom code.
- **D** — wrong: backups aren't objects you replicate this way.

**Reference:** <https://docs.aws.amazon.com/aws-backup/latest/devguide/manage-cross-account.html>

### Q43 · Answer: B

**Why (P10):** CloudTrail files in S3 cover the full retention period, and Athena queries them with SQL.

- **A** — wrong: unnecessary.
- **B** — correct: fast SQL over the archive.
- **C** — wrong: only 90 days.
- **D** — wrong: Config shows configuration and links to CloudTrail events, but Event history no longer holds this one. The S3 archive is the source of truth.

**Reference:** <https://docs.aws.amazon.com/athena/latest/ug/cloudtrail-logs.html>

### Q44 · Answer: D

**Why (P3, P12):** Distributor packages versioned, multi-platform installers. State Manager keeps them installed and current.

- **A** — wrong: runs only at first boot.
- **B** — wrong: running instances aren't updated.
- **C** — wrong: manual, with no continuous state.
- **D** — correct: managed distribution plus desired state.

**Reference:** <https://docs.aws.amazon.com/systems-manager/latest/userguide/distributor.html>

### Q45 · Answer: A

**Why (P5):** Encode the performance threshold as an exit code in the pipeline, against a stored baseline.

- **A** — correct: an automated performance gate.
- **B** — wrong: manual.
- **C** — wrong: catches regressions only after production exposure.
- **D** — wrong: shows data; doesn't gate.

**Reference:** <https://docs.aws.amazon.com/codepipeline/latest/userguide/action-reference-CodeBuild.html>

### Q46 · Answer: C

**Why (P14):** IAM database authentication replaces passwords with short-lived tokens signed with the role's credentials.

- **A** — wrong: still a password, unencrypted.
- **B** — wrong: excessive privileges.
- **C** — correct: passwordless, IAM-controlled.
- **D** — wrong: baked-in secret.

**Reference:** <https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/UsingWithRDS.IAMDBAuth.html>

### Q47 · Answer: B

**Why (P10):** Exit code 137 means the process was killed (SIGKILL), typically for exceeding the container's memory limit, and memory metrics confirm it.

- **A** — wrong: health-check failures have a different stop reason.
- **B** — correct: out of memory.
- **C** — wrong: the task ran.
- **D** — wrong: would cause API errors, not kills.

**Reference:** <https://docs.aws.amazon.com/AmazonECS/latest/developerguide/stopped-task-errors.html>

### Q48 · Answer: B, D

**Why (P7):** Failover routing sends users to the secondary when the primary's health fails, and a static S3 site serves the maintenance page.

- **A** — wrong: custom code.
- **B** — correct: the health-checked primary.
- **C** — wrong: sends half the users to maintenance all the time.
- **D** — correct: the static secondary.
- **E** — wrong: slows failover.

**Reference:** <https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/dns-failover-configuring.html>

### Q49 · Answer: C

**Why (P12):** The AppConfig Agent extension caches configuration locally, polls for updates, and serves it over localhost.

- **A** — wrong: per-invocation API calls, and loses AppConfig's deployment safety.
- **B** — wrong: requires redeploying for every change.
- **C** — correct: efficient, automatically refreshed configuration.
- **D** — wrong: per-invocation reads.

**Reference:** <https://docs.aws.amazon.com/appconfig/latest/userguide/appconfig-integration-lambda-extensions.html>

### Q50 · Answer: A

**Why (P10):** High-resolution metrics (1-second storage resolution) support alarm periods of 10 or 30 seconds.

- **A** — correct: sub-minute alarms.
- **B** — wrong: still 1-minute granularity.
- **C** — wrong: not possible with standard resolution.
- **D** — wrong: not an alarm.

**Reference:** <https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/publishingMetrics.html#high-resolution-metrics>

### Q51 · Answer: B

**Why (P13, P12):** Automation supports multi-account and multi-Region runs, with central targeting, concurrency and error thresholds, and one execution history.

- **A** — wrong: no central control or rate limiting.
- **B** — correct: native, rate-controlled fan-out.
- **C** — wrong: manual, per account.
- **D** — wrong: deploys rules; doesn't run ad hoc remediations.

**Reference:** <https://docs.aws.amazon.com/systems-manager/latest/userguide/running-automations-multiple-accounts-regions.html>

### Q52 · Answer: A, C

**Why (P10):** Memory metrics come from the agent, aggregated per Auto Scaling group. Target tracking can use customized metrics.

- **A** — correct: publishes a group-level memory metric.
- **B** — wrong: detailed monitoring doesn't include memory.
- **C** — correct: scales on that metric.
- **D** — wrong: not load-driven.
- **E** — wrong: the wrong signal.

**Reference:** <https://docs.aws.amazon.com/autoscaling/ec2/userguide/as-scaling-target-tracking.html#target-tracking-custom-metrics>

### Q53 · Answer: A

**Why (P2):** `aws:ResourceOrgID` matches the owning organization of the resource accessed, which limits the endpoint to the company's own buckets.

- **A** — correct: an organization-scoped data perimeter.
- **B** — wrong: allows any bucket.
- **C** — wrong: blocks legitimate use, and doesn't scope by owner.
- **D** — wrong: source IP isn't meaningful through a gateway endpoint, and doesn't restrict destinations.

**Reference:** <https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_policies_condition-keys.html#condition-keys-resourceorgid>

### Q54 · Answer: D

**Why (P8):** Global Datastore secondaries can be promoted to primary when the primary Region fails.

- **A** — wrong: loses the recent sessions.
- **B** — wrong: unnecessary.
- **C** — wrong: that Region is down.
- **D** — correct: cross-Region promotion.

**Reference:** <https://docs.aws.amazon.com/AmazonElastiCache/latest/dg/Redis-Global-Datastores-Console.html>

### Q55 · Answer: C

**Why (P9):** Enhanced fan-out gives each registered consumer dedicated throughput per shard, with HTTP/2 push for low latency.

- **A** — wrong: shared throughput per shard still gets split between consumers.
- **B** — wrong: increases latency.
- **C** — correct: dedicated, low-latency reads.
- **D** — wrong: custom duplication.

**Reference:** <https://docs.aws.amazon.com/streams/latest/dev/enhanced-consumers.html>

### Q56 · Answer: B

**Why (P3):** CDK Pipelines self-mutate. The pipeline first updates its own definition from source, then deploys.

- **A** — wrong: manual.
- **B** — correct: the pipeline itself is managed as code automatically.
- **C** — wrong: custom polling.
- **D** — wrong: absurd.

**Reference:** <https://docs.aws.amazon.com/cdk/v2/guide/cdk_pipeline.html>

### Q57 · Answer: C

**Why (P2, P6):** A deny-all SCP on a dedicated OU neutralizes accounts while keeping them in the organization for audit.

- **A** — wrong: roles and root remain.
- **B** — wrong: loses organizational control, and the requirement says keep them.
- **C** — correct: org-wide neutralization.
- **D** — wrong: unrelated.

**Reference:** <https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_policies_scps_examples.html>

### Q58 · Answer: D

**Why (P13):** Cross-Region aggregation brings findings from linked Regions into one aggregation Region.

- **A** — wrong: still several consoles.
- **B** — wrong: notification, not triage.
- **C** — wrong: unrelated.
- **D** — correct: a single pane for all Regions.

**Reference:** <https://docs.aws.amazon.com/securityhub/latest/userguide/finding-aggregation.html>

### Q59 · Answer: A

**Why (P8):** PITR covers per-second restore points for 35 days. AWS Backup covers long-term retention and the cross-Region copy.

- **A** — correct: both requirements met.
- **B** — wrong: replication isn't backup.
- **C** — wrong: custom work, with no restore tooling.
- **D** — wrong: manual and coarse.

**Reference:** <https://docs.aws.amazon.com/aws-backup/latest/devguide/advanced-ddb-backup.html>

### Q60 · Answer: B

**Why (P12):** Automation rules update findings automatically based on criteria (accounts, controls, severity), consistently and centrally.

- **A** — wrong: loses the control in production.
- **B** — correct: targeted suppression.
- **C** — wrong: findings regenerate, and this is custom code.
- **D** — wrong: a different service.

**Reference:** <https://docs.aws.amazon.com/securityhub/latest/userguide/automation-rules.html>

### Q61 · Answer: C

**Why (P12):** Image Builder lifecycle policies manage AMI deprecation and deletion, including the associated snapshots, by age or count, with exclusion rules.

- **A** — wrong: manual.
- **B** — wrong: snapshots aren't objects in a bucket you manage.
- **C** — correct: native image lifecycle management.
- **D** — wrong: manages volume snapshots, not AMI lifecycle.

**Reference:** <https://docs.aws.amazon.com/imagebuilder/latest/userguide/manage-image-lifecycles.html>

### Q62 · Answer: C, E

**Why (P13, P10):** The Config rule plus aggregator gives a compliance view and change events. Resource Data Sync centralizes detailed patch data for SQL reporting.

- **A** — wrong: manual.
- **B** — wrong: vulnerability findings aren't patch-baseline compliance.
- **C** — correct: continuous compliance and notifications.
- **D** — wrong: unrelated.
- **E** — correct: central, SQL-queryable data.

**Reference:** <https://docs.aws.amazon.com/config/latest/developerguide/ec2-managedinstance-patch-compliance-status-check.html>

### Q63 · Answer: D

**Why (P1):** ACM emits expiration events for certificates, including imported ones. Routing them to SNS gives an automatic early warning, and the Config rule tracks compliance.

- **A** — wrong: manual, and already failed.
- **B** — wrong: doesn't solve renewal of imported certificates.
- **C** — wrong: ALBs use ACM certificates, and this doesn't add monitoring.
- **D** — correct: event-driven expiry alerts.

**Reference:** <https://docs.aws.amazon.com/acm/latest/userguide/supported-events.html>

### Q64 · Answer: B

**Why (P8):** FIS scenarios simulate a complete AZ failure, including power interruption across compute, data and networking, safely, with stop conditions.

- **A** — wrong: covers only part of the failure, and is uncontrolled.
- **B** — correct: a realistic, controlled AZ failure.
- **C** — wrong: not possible with resources in it, and not representative.
- **D** — wrong: monitoring, not fault injection.

**Reference:** <https://docs.aws.amazon.com/fis/latest/userguide/az-availability-scenario.html>

### Q65 · Answer: D

**Why (P1):** Config emits compliance-change events. An EventBridge rule filters for `NON_COMPLIANT` and routes to the chat integration.

- **A** — wrong: not immediate.
- **B** — wrong: aggregated, and slow.
- **C** — wrong: polling.
- **D** — correct: real-time and filtered.

**Reference:** <https://docs.aws.amazon.com/config/latest/developerguide/monitor-config-with-cloudwatchevents.html>

### Q66 · Answer: A

**Why (P9):** Reserved concurrency guarantees capacity for critical functions, and caps noisy ones, within the account limit.

- **A** — correct: isolation of concurrency.
- **B** — wrong: doesn't limit concurrency.
- **C** — wrong: provisioned concurrency still counts against the account limit, so throttling remains without reservations.
- **D** — wrong: unrelated.

**Reference:** <https://docs.aws.amazon.com/lambda/latest/dg/configuration-concurrency.html>

### Q67 · Answer: D

**Why (P12):** Step Functions orchestrates multi-step tests with waits, retries and guaranteed cleanup (Catch → cleanup), and CodePipeline can invoke it.

- **A** — wrong: brittle, with weak cleanup guarantees and no visibility.
- **B** — wrong: manual.
- **C** — wrong: duration limits and no orchestration.
- **D** — correct: robust test orchestration.

**Reference:** <https://docs.aws.amazon.com/codepipeline/latest/userguide/action-reference-StepFunctions.html>

### Q68 · Answer: A

**Why (P5, P3):** AppConfig validates configuration before deployment, rolls it out gradually, and rolls it back on alarms, with no code deployment.

- **A** — correct: safe configuration delivery.
- **B** — wrong: no validation, gradual rollout or automatic rollback.
- **C** — wrong: requires redeploying.
- **D** — wrong: no safety mechanisms.

**Reference:** <https://docs.aws.amazon.com/appconfig/latest/userguide/appconfig-creating-configuration-and-profile-validators.html>

### Q69 · Answer: B

**Why (P12):** Archive rules automatically archive findings that match expected access, now and in future, so active findings show only the unexpected access.

- **A** — wrong: loses detection.
- **B** — correct: noise reduction with no blind spots.
- **C** — wrong: breaks the legitimate partnership.
- **D** — wrong: absurd.

**Reference:** <https://docs.aws.amazon.com/IAM/latest/UserGuide/access-analyzer-archive-rules.html>

### Q70 · Answer: C

**Why (P7):** One Zone file systems store data in a single AZ. AZ resilience needs a Regional file system.

- **A** — wrong: One Zone file systems can't span AZs.
- **B** — wrong: cost tiering only.
- **C** — correct: migrate to Regional storage.
- **D** — wrong: recovery would take time, so this isn't AZ-resilient availability.

**Reference:** <https://docs.aws.amazon.com/efs/latest/ug/storage-classes.html>

### Q71 · Answer: A, E

**Why (P10, P9):** Traces pinpoint the slow hop (DynamoDB throttling retries), and fixing the capacity removes the cause.

- **A** — correct: root-cause identification.
- **B** — wrong: the function isn't the bottleneck.
- **C** — wrong: unrelated.
- **D** — wrong: hides the latency instead of fixing it.
- **E** — correct: the fix.

**Reference:** <https://docs.aws.amazon.com/xray/latest/devguide/xray-console-servicemap.html>

### Q72 · Answer: A

**Why (P4, P7):** A minimum of 100% healthy with a 200% maximum starts replacements first, so capacity never drops.

- **A** — correct: zero-downtime rolling deployments.
- **B** — wrong: with a 0% minimum, everything can still stop at once.
- **C** — wrong: the wrong controller, and all at once anyway.
- **D** — wrong: unrelated.

**Reference:** <https://docs.aws.amazon.com/AmazonECS/latest/developerguide/deployment-type-ecs.html>

### Q73 · Answer: C

**Why (P3):** StackSet drift detection finds drifted instances and resources. Updating the stack set re-applies the desired state, and guardrails prevent recurrence.

- **A** — wrong: destructive.
- **B** — wrong: manual.
- **C** — correct: detect, then re-converge.
- **D** — wrong: unrelated.

**Reference:** <https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/stacksets-drift.html>

### Q74 · Answer: B

**Why (P14):** CloudWatch dashboard sharing supports SSO through Cognito with an external IdP, so specified users get read-only access without IAM users.

- **A** — wrong: long-term credentials for outsiders.
- **B** — correct: federated, scoped sharing.
- **C** — wrong: manual and stale.
- **D** — wrong: exposes the data to anyone.

**Reference:** <https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/cloudwatch-dashboard-sharing.html>

### Q75 · Answer: B, D

**Why (P1):** IAM is a global service whose CloudTrail events are delivered in `us-east-1`. EventBridge rules match them, and an active trail is required.

- **A** — wrong: GuardDuty detects threats; it doesn't notify on every policy change.
- **B** — correct: event-driven notification on the IAM API calls.
- **C** — wrong: vulnerabilities.
- **D** — correct: the prerequisite trail.
- **E** — wrong: S3 data classification.

**Reference:** <https://docs.aws.amazon.com/IAM/latest/UserGuide/cloudtrail-integration.html>
