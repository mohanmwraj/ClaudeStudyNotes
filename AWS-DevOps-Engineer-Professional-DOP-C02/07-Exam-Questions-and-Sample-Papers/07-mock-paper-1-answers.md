# Mock Paper 1 · Answers and Explanations

Answers for [07-mock-paper-1.md](07-mock-paper-1.md). Every option is explained. Read the explanations for the questions you got right too: you may have been right for the wrong reason.

**Tally your score by domain** using the domain labels in the questions file. A domain below 70% marks the folder to revisit.

---

### Q1 · Answer: C

**Why (P7):** Builds in a VPC get ENIs without public IP addresses, so internet access must go through a NAT gateway from private subnets (or through VPC endpoints for AWS services).

- **A** — wrong: CodeBuild doesn't assign public IPs, so public subnets don't give internet access.
- **B** — wrong: there's no route out, and time doesn't fix routing.
- **C** — correct: the documented VPC configuration for CodeBuild.
- **D** — wrong: exposes the database.

**Reference:** <https://docs.aws.amazon.com/codebuild/latest/userguide/vpc-support.html>

### Q2 · Answer: A

**Why (P7):** RDS Proxy pools and reuses connections, which prevents exhaustion, and it keeps client connections open while it reconnects to the new writer, which shortens the disruption.

- **A** — correct: fixes both connection storms and failover disruption.
- **B** — wrong: raises the connection limit somewhat, but doesn't help failover.
- **C** — wrong: more replicas don't pool connections, and failover behaviour stays the same.
- **D** — wrong: throttles the application.

**Reference:** <https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/rds-proxy.html>

### Q3 · Answer: D

**Why (P14):** IAM Roles Anywhere exchanges X.509 certificates from your CA for temporary STS credentials for workloads outside AWS.

- **A** — wrong: still long-term keys.
- **B** — wrong: the servers still need credentials to read the secret, and the keys remain long-term.
- **C** — wrong: more long-term keys.
- **D** — correct: temporary credentials anchored in the existing PKI.

**Reference:** <https://docs.aws.amazon.com/rolesanywhere/latest/userguide/introduction.html>

### Q4 · Answer: B

**Why (P10):** EMF puts metrics in log lines. CloudWatch extracts them asynchronously, so there are no API calls in the request path and no added latency.

- **A** — wrong: a synchronous call per invocation adds latency, cost and throttling risk.
- **B** — correct: low-overhead custom metrics with dimensions.
- **C** — wrong: custom pipeline and storage.
- **D** — wrong: Lambda Insights provides system metrics, not custom business metrics.

**Reference:** <https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/CloudWatch_Embedded_Metric_Format.html>

### Q5 · Answer: A

**Why (P3):** SSM parameters decouple producers from consumers. Exports lock values while they're imported, but parameters can change at any time, and consumers pick them up at their next update.

- **A** — correct: loose coupling without blocking updates.
- **B** — wrong: couples 41 teams' lifecycles into one stack.
- **C** — wrong: drifts and breaks silently.
- **D** — wrong: destructive and absurd.

**Reference:** <https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/parameters-section-structure.html#aws-ssm-parameter-types>

### Q6 · Answer: D

**Why (P4):** Blue/green rollback is instant only while the original environment still exists. The wait before terminating the original instances is configurable.

- **A** — wrong: in-place deployments have no old fleet to switch back to.
- **B** — wrong: mixed versions, and rollback means redeploying.
- **C** — wrong: rollback settings don't control how long the original instances are kept.
- **D** — correct: keeps the blue fleet for the 4-hour window.

**Reference:** <https://docs.aws.amazon.com/codedeploy/latest/userguide/deployment-groups-create-blue-green.html>

### Q7 · Answer: C

**Why (P1, P9):** EventBridge archives keep events, and replay re-sends them to a bus, so rules and targets process them again.

- **A** — wrong: DLQs only catch delivery failures, not events a consumer accepted and then discarded.
- **B** — wrong: CloudTrail records API calls, not your event payloads for replay.
- **C** — correct: native archive and replay.
- **D** — wrong: logging doesn't give you a way to re-deliver events.

**Reference:** <https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-archive.html>

### Q8 · Answer: B, E

**Why (P11):** Enforce encryption in transit with an `aws:SecureTransport` deny, and encryption at rest with default SSE-KMS under the customer managed key, plus a deny for other encryption.

- **A** — wrong: ACLs are legacy access control and don't enforce either requirement.
- **B** — correct: TLS-only access.
- **C** — wrong: SSE-S3 doesn't use the customer managed key.
- **D** — wrong: Macie classifies data; it doesn't enforce encryption.
- **E** — correct: the required key is enforced by default and by policy.

**Reference:** <https://docs.aws.amazon.com/AmazonS3/latest/userguide/UsingKMSEncryption.html>

### Q9 · Answer: B

**Why (P5):** `QUEUED` mode processes executions one at a time, in order, so no commit is skipped.

- **A** — wrong: doesn't change superseding behaviour.
- **B** — correct: ordered, complete processing.
- **C** — wrong: executions would run concurrently, in no guaranteed order.
- **D** — wrong: blocks deployments entirely.

**Reference:** <https://docs.aws.amazon.com/codepipeline/latest/userguide/concepts-how-it-works.html>

### Q10 · Answer: C

**Why (P2):** RCPs cap access **to resources** across the organization, whatever their resource policies say, which gives a data perimeter without editing each policy.

- **A** — wrong: detective only, and covers S3 only.
- **B** — wrong: stops legitimate policy management, and existing permissive policies stay.
- **C** — correct: a central preventive control on resource access.
- **D** — wrong: reports; doesn't prevent.

**Reference:** <https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_policies_rcps.html>

### Q11 · Answer: D

**Why (P7):** Global Accelerator's static anycast IPs don't change during failover, and its health-based routing shifts traffic between Regions in seconds, independent of DNS caching.

- **A** — wrong: clients ignore low TTLs, which is the original problem.
- **B** — wrong: CloudFront is for HTTP(S), not raw TCP trading connections, and doesn't provide this static-IP failover model.
- **C** — wrong: Elastic IPs are Regional and can't move between Regions.
- **D** — correct: static IPs plus fast, health-based Regional failover.

**Reference:** <https://docs.aws.amazon.com/global-accelerator/latest/dg/introduction-how-it-works.html>

### Q12 · Answer: A

**Why (P10):** CloudTrail Insights learns normal API call volumes and error rates, and emits Insights events when activity deviates.

- **A** — correct: anomaly detection on API activity without per-API thresholds.
- **B** — wrong: file counts say nothing about the activity in them.
- **C** — wrong: records configuration, not API anomalies.
- **D** — wrong: vulnerabilities.

**Reference:** <https://docs.aws.amazon.com/awscloudtrail/latest/userguide/logging-insights-events-with-cloudtrail.html>

### Q13 · Answer: A, D

**Why (P5):** A linear configuration shifts equal increments, alarms drive rollback, and the `PreTraffic` hook validates the new version before any shift.

- **A** — correct: equal 10% steps every minute, plus alarm rollback.
- **B** — wrong: canary means 10% followed by everything else, not equal increments.
- **C** — wrong: unrelated to traffic shifting.
- **D** — correct: gates the start of the deployment.
- **E** — wrong: no gradual shift, no automatic gate.

**Reference:** <https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/automating-updates-to-serverless-apps.html>

### Q14 · Answer: B

**Why (P1, P7):** Termination lifecycle hooks pause the instance in `Terminating:Wait`. Automation does the work, then completes the action.

- **A** — wrong: logs written later are still lost.
- **B** — correct: the documented graceful-shutdown pattern.
- **C** — wrong: blocks scale-in instead of handling it.
- **D** — wrong: drains connections, but doesn't run anything on the instance.

**Reference:** <https://docs.aws.amazon.com/autoscaling/ec2/userguide/lifecycle-hooks.html>

### Q15 · Answer: D

**Why (P3):** CloudFormation waits for the custom resource to PUT a response to its pre-signed URL. No response means waiting until the custom resource times out, by default one hour.

- **A** — wrong: unrelated to the hang.
- **B** — wrong: the function finished; it just never responded.
- **C** — wrong: would block deletion entirely.
- **D** — correct: respond for every event type, including no-op deletes.

**Reference:** <https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/crpg-ref-responses.html>

### Q16 · Answer: A

**Why (P14):** Revoking sessions denies credentials issued before the revocation time. New sessions, issued afterwards, keep working.

- **A** — correct: invalidates exactly the leaked credentials.
- **B** — wrong: disruptive, and existing credentials may keep working until they expire, because they're tied to the role's unique ID.
- **C** — wrong: breaks the workload permanently.
- **D** — wrong: unrelated to IAM credentials.

**Reference:** <https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_use_revoke-sessions.html>

### Q17 · Answer: C

**Why (P2):** Cross-account CodeArtifact access needs resource policies (domain and repository) on the owning side, and IAM permissions on the consuming side.

- **A** — wrong: duplicates storage and goes stale.
- **B** — wrong: CodeArtifact repositories can't be made public, and that would expose internal packages anyway.
- **C** — correct: both sides of cross-account authorization.
- **D** — wrong: long-term shared credentials.

**Reference:** <https://docs.aws.amazon.com/codeartifact/latest/ug/repo-policies.html>

### Q18 · Answer: C, E

**Why (P7):** Diversifying instance types and AZs with `price-capacity-optimized` reduces interruptions, and capacity rebalancing replaces at-risk instances proactively.

- **A** — wrong: abandons the cost savings.
- **B** — wrong: more instances in the same Spot pool are interrupted together.
- **C** — correct: diversification across Spot pools.
- **D** — wrong: concentrates the risk in one pool.
- **E** — correct: proactive replacement.

**Reference:** <https://docs.aws.amazon.com/autoscaling/ec2/userguide/ec2-auto-scaling-capacity-rebalancing.html>

### Q19 · Answer: D

**Why (P13):** Cross-account observability lets a monitoring account search, graph and alarm on linked source accounts' telemetry without copying it.

- **A** — wrong: copies logs only, and costs more.
- **B** — wrong: long-term credentials, and no single view.
- **C** — wrong: metrics only, and metric streams deliver through Firehose, not into another account's CloudWatch.
- **D** — correct: unified, org-wide, no copies.

**Reference:** <https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/CloudWatch-Unified-Cross-Account.html>

### Q20 · Answer: B

**Why (P12):** Batch builds with a `build-matrix` fan out over versions and environments in parallel, under one batch result.

- **A** — wrong: six projects to maintain.
- **B** — correct: native parallel matrix.
- **C** — wrong: still sequential.
- **D** — wrong: custom orchestration.

**Reference:** <https://docs.aws.amazon.com/codebuild/latest/userguide/batch-build-buildspec.html>

### Q21 · Answer: A

**Why (P13, P12):** Quick Setup patch policies configure patch scanning and installation once, across OUs and Regions, and cover new accounts.

- **A** — correct: central and org-wide.
- **B** — wrong: per-account manual setup.
- **C** — wrong: unmanaged, with no compliance view.
- **D** — wrong: builds images; doesn't patch running instances.

**Reference:** <https://docs.aws.amazon.com/systems-manager/latest/userguide/quick-setup-patch-manager.html>

### Q22 · Answer: C

**Why (P12):** GuardDuty Runtime Monitoring observes OS-level runtime events (processes, files, network) through a GuardDuty-managed agent, and can deploy that agent automatically as an EKS add-on.

- **A** — wrong: finds vulnerabilities in images, not runtime behaviour.
- **B** — wrong: network metadata only.
- **C** — correct: managed runtime threat detection.
- **D** — wrong: checks configuration, not runtime.

**Reference:** <https://docs.aws.amazon.com/guardduty/latest/ug/runtime-monitoring.html>

### Q23 · Answer: D

**Why (P10):** A proxy integration needs a specific response shape; anything else is a malformed Lambda proxy response, which API Gateway reports as 502.

- **A** — wrong: caching doesn't produce 502s for every request.
- **B** — wrong: a timeout would give a 504, and the function completes quickly anyway.
- **C** — wrong: usage plans govern throttling and API keys.
- **D** — correct: fix the response format.

**Reference:** <https://docs.aws.amazon.com/apigateway/latest/developerguide/set-up-lambda-proxy-integrations.html>

### Q24 · Answer: C

**Why (P5, P12):** The circuit breaker detects deployments whose tasks can't reach a steady state, and rolls back to the last completed deployment automatically.

- **A** — wrong: custom code for a native feature.
- **B** — wrong: launches more failing tasks.
- **C** — correct: native automatic rollback.
- **D** — wrong: unrelated to ECS deployments.

**Reference:** <https://docs.aws.amazon.com/AmazonECS/latest/developerguide/deployment-circuit-breaker.html>

### Q25 · Answer: B

**Why (P10):** For a heartbeat-style metric, **no data means failure**. Treating missing data as breaching makes the alarm fire when the job doesn't report.

- **A** — wrong: the statistic doesn't matter when there are no data points.
- **B** — correct: missing reports raise the alarm.
- **C** — wrong: hides the failure.
- **D** — wrong: unrelated.

**Reference:** <https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/AlarmThatSendsEmail.html#alarms-and-missing-data>

### Q26 · Answer: B

**Why (P3):** `cfn-hup` detects changes to the resource's metadata and runs hooks, typically re-running `cfn-init`, so configuration converges without replacing the instance.

- **A** — wrong: affects creation order, not configuration updates.
- **B** — correct: the documented mechanism.
- **C** — wrong: replacement is exactly what the team wants to avoid.
- **D** — wrong: detects differences but changes nothing.

**Reference:** <https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/cfn-hup.html>

### Q27 · Answer: A

**Why (P6):** Cross-Region actions need an artifact store in each Region they use. CodePipeline copies artifacts there.

- **A** — correct: declare a per-Region artifact store.
- **B** — wrong: CodePipeline manages artifact copying itself; it needs a registered store in the Region.
- **C** — wrong: moves the problem to the other Region.
- **D** — wrong: custom code for a native feature.

**Reference:** <https://docs.aws.amazon.com/codepipeline/latest/userguide/actions-create-cross-region.html>

### Q28 · Answer: A, C

**Why (P11):** Encryption by default enforces the key for new volumes. Auto Scaling launches instances through its service-linked role, which the key policy must allow, including grant creation.

- **A** — correct: default encryption with the required key.
- **B** — wrong: violates the requirement to use the company key.
- **C** — correct: fixes the failed launches.
- **D** — wrong: violates the requirement, and encryption by default overrides it anyway.
- **E** — wrong: the instance profile isn't the principal that creates the volumes.

**Reference:** <https://docs.aws.amazon.com/autoscaling/ec2/userguide/key-policy-requirements-EBS-encryption.html>

### Q29 · Answer: C

**Why (P7):** With cross-zone load balancing off (the default for NLBs), each AZ's node only sends traffic to targets in its own AZ, so the 2 instances in AZ-a get half the traffic.

- **A** — wrong: doesn't change the per-AZ distribution.
- **B** — wrong: stickiness doesn't rebalance load across AZs.
- **C** — correct: spreads traffic across all targets.
- **D** — wrong: loses the NLB's features and doesn't fix the distribution.

**Reference:** <https://docs.aws.amazon.com/elasticloadbalancing/latest/network/network-load-balancers.html#cross-zone-load-balancing>

### Q30 · Answer: D

**Why (P11, P12):** Data protection policies mask sensitive data at ingestion using managed identifiers, and report findings. Only principals with `logs:Unmask` see the original values.

- **A** — wrong: destroys logs that may be needed.
- **B** — wrong: encryption doesn't hide data from authorized readers.
- **C** — wrong: weekly and after the fact, and exposure in CloudWatch continues.
- **D** — correct: immediate masking with a managed feature.

**Reference:** <https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/mask-sensitive-log-data.html>

### Q31 · Answer: B

**Why (P12):** EventBridge Pipes connects a source to a target with filtering and enrichment built in, which removes the custom polling glue.

- **A** — wrong: SNS can't subscribe to SQS.
- **B** — correct: source → filter → enrich → target.
- **C** — wrong: polling with code.
- **D** — wrong: Firehose doesn't read from SQS and isn't a workflow trigger.

**Reference:** <https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-pipes.html>

### Q32 · Answer: A

**Why (P5):** Traffic splitting is Beanstalk's canary policy: a share of traffic goes to new instances for an evaluation period, with automatic rollback if health degrades.

- **A** — correct: canary with evaluation and rollback.
- **B** — wrong: no traffic split or evaluation window.
- **C** — wrong: no percentage-based traffic exposure.
- **D** — wrong: downtime and no canary.

**Reference:** <https://docs.aws.amazon.com/elasticbeanstalk/latest/dg/using-features.rolling-version-deploy.html>

### Q33 · Answer: D

**Why (P3):** Control Tower manages the governed state. Changes made outside it cause drift, which you resolve through Control Tower's update, re-enroll and re-register mechanisms.

- **A** — wrong: destructive and unnecessary.
- **B** — wrong: removes guardrails.
- **C** — wrong: abandons governance.
- **D** — correct: repair through the owning tool, and use it for future moves.

**Reference:** <https://docs.aws.amazon.com/controltower/latest/userguide/drift.html>

### Q34 · Answer: C

**Why (P12):** Shield Advanced adds DDoS cost protection, Shield Response Team access and automatic L7 mitigation with WAF, beyond Shield Standard's L3/L4 protection.

- **A** — wrong: no cost protection or expert access.
- **B** — wrong: threat detection, not DDoS mitigation.
- **C** — correct: every requirement covered.
- **D** — wrong: impractical against distributed attacks, and offers none of the other features.

**Reference:** <https://docs.aws.amazon.com/waf/latest/developerguide/ddos-advanced-summary.html>

### Q35 · Answer: B

**Why (P12, P9):** Aurora Serverless v2 scales capacity in fine-grained ACUs within seconds, without reboots, following the load.

- **A** — wrong: changing the instance class causes downtime and can't react to spikes.
- **B** — correct: automatic, seamless capacity scaling.
- **C** — wrong: the writer is still over-provisioned, and the spikes may be writes.
- **D** — wrong: adds availability, not elastic capacity.

**Reference:** <https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/aurora-serverless-v2.html>

### Q36 · Answer: D

**Why (P4):** Immutable tags prevent overwrites, and digests identify exact image content, so the tested artifact is the deployed artifact.

- **A** — wrong: `latest` is the most mutable tag of all.
- **B** — wrong: scanning doesn't stop tags being overwritten.
- **C** — wrong: helps, but anyone with push rights can still overwrite a tag.
- **D** — correct: immutable, content-addressed deployment.

**Reference:** <https://docs.aws.amazon.com/AmazonECR/latest/userguide/image-tag-mutability.html>

### Q37 · Answer: B, D

**Why (P10):** Athena cost depends on the data scanned. Partitions prune whole days, and a columnar format prunes columns.

- **A** — wrong: increases the data scanned.
- **B** — correct: partition pruning.
- **C** — wrong: S3 Select works on one object at a time and isn't the fix for dataset-wide queries.
- **D** — correct: column pruning plus efficient compression.
- **E** — wrong: affects object size, not the amount scanned per query.

**Reference:** <https://docs.aws.amazon.com/firehose/latest/dev/dynamic-partitioning.html>

### Q38 · Answer: A

**Why (P12):** OpsCenter aggregates OpsItems with related resources, events and runbooks for central triage and remediation.

- **A** — correct: purpose-built operational issue management.
- **B** — wrong: unstructured and noisy.
- **C** — wrong: manual.
- **D** — wrong: queries API events; it isn't issue management.

**Reference:** <https://docs.aws.amazon.com/systems-manager/latest/userguide/OpsCenter.html>

### Q39 · Answer: A, E

**Why (P14):** Session Manager gives IAM-authorized shells with no inbound ports or keys, and logs sessions to S3 or CloudWatch Logs with encryption.

- **A** — correct: audited shell access.
- **B** — wrong: keeps the bastion and the keys.
- **C** — wrong: requires public exposure.
- **D** — wrong: still SSH keys and open ports.
- **E** — correct: tag-based authorization, and port 22 closed.

**Reference:** <https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-logging.html>

### Q40 · Answer: B

**Why (P14):** Role chaining caps the session duration at 1 hour, whatever the role's maximum session duration.

- **A** — wrong: sessions that aren't chained can last up to the role's maximum (12 hours).
- **B** — correct: avoid chaining for long sessions.
- **C** — wrong: unrelated to duration.
- **D** — wrong: permissions don't affect session length.

**Reference:** <https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_terms-and-concepts.html#iam-term-role-chaining>

### Q41 · Answer: C

**Why (P5):** V2 on-success stage conditions can check a CloudWatch alarm for a duration after the stage succeeds, and roll the stage back when it fires.

- **A** — wrong: still manual.
- **B** — wrong: notifies; doesn't roll back.
- **C** — correct: an automated post-deployment gate with rollback.
- **D** — wrong: waiting without checking anything.

**Reference:** <https://docs.aws.amazon.com/codepipeline/latest/userguide/stage-conditions.html>

### Q42 · Answer: A

**Why (P8):** Replication rules apply to new objects only. S3 Batch Replication replicates existing objects, and failed ones.

- **A** — correct: the native tool.
- **B** — wrong: manual, slow, and loses metadata.
- **C** — wrong: doesn't trigger replication of existing objects.
- **D** — wrong: speeds up uploads; unrelated to replication.

**Reference:** <https://docs.aws.amazon.com/AmazonS3/latest/userguide/s3-batch-replication-batch.html>

### Q43 · Answer: C

**Why (P10):** Contributor Insights continuously computes top-N contributors from structured logs.

- **A** — wrong: you'd need one filter per IP address, which is unbounded.
- **B** — wrong: sampling for traces.
- **C** — correct: real-time top contributors.
- **D** — wrong: Athena queries S3, not CloudWatch log groups directly, and needs queries anyway.

**Reference:** <https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/ContributorInsights.html>

### Q44 · Answer: B

**Why (P4):** A replacing update creates a whole new group and keeps the old one until the new one succeeds, so rollback is clean.

- **A** — wrong: replaces instances inside the existing group.
- **B** — correct: an immutable group replacement gated by signals.
- **C** — wrong: only protects scheduled-action sizes.
- **D** — wrong: unrelated to update behaviour.

**Reference:** <https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-attribute-updatepolicy.html>

### Q45 · Answer: D

**Why (P2):** IAM authentication to EKS succeeds, but Kubernetes authorization needs the IAM principal mapped to permissions: access entries, or `aws-auth`.

- **A** — wrong: IAM permissions don't grant Kubernetes RBAC.
- **B** — wrong: for Docker builds; unrelated.
- **C** — wrong: the endpoint is already reachable (the error is from the server).
- **D** — correct: map the role to cluster permissions.

**Reference:** <https://docs.aws.amazon.com/eks/latest/userguide/access-entries.html>

### Q46 · Answer: D

**Why (P13):** Central configuration from the delegated administrator applies consistent Security Hub settings and standards across accounts and Regions, including new accounts.

- **A** — wrong: manual, and drifts.
- **B** — wrong: conformance packs deploy Config rules; they don't configure Security Hub.
- **C** — wrong: SCPs can't enable services.
- **D** — correct: org-wide, central and automatic.

**Reference:** <https://docs.aws.amazon.com/securityhub/latest/userguide/central-configuration-intro.html>

### Q47 · Answer: C

**Why (P9):** If processing outlasts the visibility timeout, the message becomes visible again and a second worker takes it. Idempotency protects against the duplicates that remain possible.

- **A** — wrong: reduces empty receives; doesn't affect visibility.
- **B** — wrong: each message still exceeds the timeout.
- **C** — correct: matches the timeout to processing time.
- **D** — wrong: catches poison messages, not duplicates.

**Reference:** <https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/sqs-visibility-timeout.html>

### Q48 · Answer: D

**Why (P8):** A 15-minute RTO needs compute already running. Warm standby provides that at reduced size, so it costs less than active/active.

- **A** — wrong: hours of RTO and RPO.
- **B** — wrong: launching the whole application tier from IaC is risky to fit in 15 minutes.
- **C** — wrong: meets the targets, but leadership rejects the cost of a full duplicate.
- **D** — correct: balances the RTO against the cost.

**Reference:** <https://docs.aws.amazon.com/whitepapers/latest/disaster-recovery-workloads-on-aws/disaster-recovery-options-in-the-cloud.html>

### Q49 · Answer: A

**Why (P5):** CodePipeline waits for the function to report the job result through the CodePipeline API.

- **A** — correct: report success or failure with the job ID.
- **B** — wrong: the function finishes fine.
- **C** — wrong: any runtime works.
- **D** — wrong: unrelated.

**Reference:** <https://docs.aws.amazon.com/codepipeline/latest/userguide/actions-invoke-lambda-function.html>

### Q50 · Answer: B

**Why (P12):** Managed Prometheus stores PromQL-queryable metrics, and Managed Grafana provides dashboards with SSO. Both are serverless to operate.

- **A** — wrong: self-managed servers.
- **B** — correct: managed, compatible, SSO-integrated.
- **C** — wrong: a log query tool, not Prometheus metrics with PromQL.
- **D** — wrong: business intelligence, not operational metrics dashboards.

**Reference:** <https://docs.aws.amazon.com/prometheus/latest/userguide/what-is-Amazon-Managed-Service-Prometheus.html>

### Q51 · Answer: B, D

**Why (P2, P13):** Tag policies standardize keys and allowed values across the organization. An SCP with an `aws:RequestTag` null condition makes creating resources without the tag impossible.

- **A** — wrong: detective only; non-compliant resources still get created.
- **B** — correct: standardized values everywhere.
- **C** — wrong: destructive custom code.
- **D** — correct: preventive enforcement of the tag's presence.
- **E** — wrong: grants permissions; doesn't require tags.

**Reference:** <https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_policies_tag-policies.html>

### Q52 · Answer: C, E

**Why (P4):** A database inside a Beanstalk environment is deleted with it. Decouple it, then do blue/green with clone + URL swap, keeping blue until the release is proven.

- **A** — wrong: no blue/green, and the coupling risk remains.
- **B** — wrong: slow rollback, and doesn't fix the coupling.
- **C** — correct: the database's lifecycle no longer depends on an environment.
- **D** — wrong: removes the instant rollback.
- **E** — correct: Beanstalk blue/green.

**Reference:** <https://docs.aws.amazon.com/elasticbeanstalk/latest/dg/AWSHowTo.RDS.html>

### Q53 · Answer: A

**Why (P1):** Health events are EventBridge events. Routing them to automation (or to OpsItems with runbooks) gives a controlled response inside your maintenance windows.

- **A** — correct: event-driven and controlled.
- **B** — wrong: manual; it's what already failed.
- **C** — wrong: unrelated signal.
- **D** — wrong: Auto Scaling protection doesn't affect AWS retirements.

**Reference:** <https://docs.aws.amazon.com/health/latest/ug/cloudwatch-events-health.html>

### Q54 · Answer: C

**Why (P14, P5):** Access Analyzer custom policy checks reason formally about policies and return pass or fail, which makes them ideal pipeline gates.

- **A** — wrong: checks template syntax, not effective access.
- **B** — wrong: manual and slow.
- **C** — correct: automated least-privilege gates.
- **D** — wrong: finds code vulnerabilities, not IAM grants.

**Reference:** <https://docs.aws.amazon.com/IAM/latest/UserGuide/access-analyzer-checks-validating-policies.html>

### Q55 · Answer: D

**Why (P12):** Karpenter provisions nodes directly from pod requirements, which is faster and right-sized, and it consolidates nodes without managing many node groups.

- **A** — wrong: costs more and doesn't fix bin-packing.
- **B** — wrong: VPA changes pod requests, not node provisioning.
- **C** — wrong: inflexible and still slow to scale.
- **D** — correct: faster, more efficient node scaling.

**Reference:** <https://docs.aws.amazon.com/eks/latest/best-practices/karpenter.html>

### Q56 · Answer: A

**Why (P12):** Quick Sight is the business-intelligence and dashboard tool for Athena-queryable data, with sharing and scheduled refreshes.

- **A** — correct: an executive-ready, interactive dashboard.
- **B** — wrong: shows metrics, not log-derived business analysis.
- **C** — wrong: static and not interactive.
- **D** — wrong: no Prometheus data here.

**Reference:** <https://docs.aws.amazon.com/quicksight/latest/user/create-a-data-set-athena.html>

### Q57 · Answer: B

**Why (P3, P12):** AFT is Control Tower's GitOps account-vending pipeline built on Terraform.

- **A** — wrong: not account vending.
- **B** — correct: Terraform-native account factory.
- **C** — wrong: manual.
- **D** — wrong: not GitOps-based, and Terraform isn't the authoring tool here.

**Reference:** <https://docs.aws.amazon.com/controltower/latest/userguide/aft-overview.html>

### Q58 · Answer: C

**Why (P12):** A pull-through cache serves upstream images from your private ECR registry. That removes the rate limits and the dependency on Docker Hub's availability, and the images get scanned.

- **A** — wrong: retries still hit the limits.
- **B** — wrong: unrelated.
- **C** — correct: cached, scanned, private.
- **D** — wrong: bloats the repository and isn't maintainable.

**Reference:** <https://docs.aws.amazon.com/AmazonECR/latest/userguide/pull-through-cache.html>

### Q59 · Answer: A, D

**Why (P3, P13):** Encryption by default prevents new unencrypted volumes. A Config rule continuously reports the existing ones.

- **A** — correct: prevention.
- **B** — wrong: volumes can't be encrypted in place; you copy a snapshot with encryption instead.
- **C** — wrong: threat detection.
- **D** — correct: continuous detection.
- **E** — wrong: S3 data classification.

**Reference:** <https://docs.aws.amazon.com/ebs/latest/userguide/encryption-by-default.html>

### Q60 · Answer: B

**Why (P2):** The bucket policy restricts *where requests come from* (the endpoint). The endpoint policy restricts *what can be reached* through the endpoint, which stops exfiltration.

- **A** — wrong: allows all S3 buckets.
- **B** — correct: two-sided control.
- **C** — wrong: gateway endpoints don't use the internet anyway, and this restricts nothing about buckets.
- **D** — wrong: broadens access.

**Reference:** <https://docs.aws.amazon.com/AmazonS3/latest/userguide/example-bucket-policies-vpc-endpoint.html>

### Q61 · Answer: C

**Why (P8):** ARC routing controls are highly available on/off switches operated through a data plane that's independent of the impaired Region. Safety rules prevent unsafe states, such as both Regions off.

- **A** — wrong: depends on the impaired Region.
- **B** — wrong: control-plane dependent and error-prone.
- **C** — correct: deliberate, resilient, guarded failover.
- **D** — wrong: per-request origin failover for HTTP content, not operator-controlled Regional failover.

**Reference:** <https://docs.aws.amazon.com/r53recovery/latest/dg/routing-control.html>

### Q62 · Answer: D

**Why (P12):** Step Functions Map states fan out over items with concurrency limits, retries and catches, with a single execution history.

- **A** — wrong: Lambda's 15-minute limit and no built-in retry orchestration.
- **B** — wrong: a server to manage, and no orchestration.
- **C** — wrong: unmanageable.
- **D** — correct: controlled, observable fan-out.

**Reference:** <https://docs.aws.amazon.com/step-functions/latest/dg/state-map.html>

### Q63 · Answer: C

**Why (P3):** A Config managed rule detects non-compliant log groups, and automatic remediation sets the retention.

- **A** — wrong: not enforcement.
- **B** — wrong: blocks logging entirely.
- **C** — correct: detect and fix.
- **D** — wrong: unrelated.

**Reference:** <https://docs.aws.amazon.com/config/latest/developerguide/cw-loggroup-retention-period-check.html>

### Q64 · Answer: B, E

**Why (P5, P1):** The approval rule requires the automation's approval, and the event-driven build supplies it only when the tests pass.

- **A** — wrong: runs after the merge.
- **B** — correct: merging is gated on the automation's approval.
- **C** — wrong: not tied to the PR.
- **D** — wrong: blocks all pushes.
- **E** — correct: builds the PR and approves it on success.

**Reference:** <https://docs.aws.amazon.com/codecommit/latest/userguide/approval-rule-templates.html>

### Q65 · Answer: A

**Why (P10):** CIS monitoring controls are implemented as metric filters and alarms on the CloudTrail log group.

- **A** — correct: real-time alerts on each pattern.
- **B** — wrong: vulnerability scanning.
- **C** — wrong: weekly isn't alerting.
- **D** — wrong: logs bucket access, not the account's API activity.

**Reference:** <https://docs.aws.amazon.com/securityhub/latest/userguide/cloudwatch-controls.html>

### Q66 · Answer: D

**Why (P10):** Find the first failure in the service's own record. Beanstalk events point to the instance, and the engine and `cfn-init` logs show the failing command.

- **A** — wrong: loses the evidence, and the same configuration will fail again.
- **B** — wrong: doesn't fix the failing command.
- **C** — wrong: unrelated.
- **D** — correct: root cause from the logs.

**Reference:** <https://docs.aws.amazon.com/elasticbeanstalk/latest/dg/using-features.logging.html>

### Q67 · Answer: B

**Why (P7):** Stateless compute is what makes instance loss invisible. Session state belongs in a replicated external store.

- **A** — wrong: the session still lives in one instance's memory.
- **B** — correct: any instance can serve any request.
- **C** — wrong: blocks elasticity, and failures still lose sessions.
- **D** — wrong: doesn't remove the dependency on the instance.

**Reference:** <https://docs.aws.amazon.com/AmazonElastiCache/latest/dg/WhatIs.html>

### Q68 · Answer: A

**Why (P13):** StackSets supports delegated administrators that create and manage service-managed stack sets on behalf of the organization.

- **A** — correct: org-wide administration from the member account.
- **B** — wrong: never share root credentials.
- **C** — wrong: requires management-account use, and per-account roles.
- **D** — wrong: work still happens in the management account.

**Reference:** <https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/stacksets-orgs-delegated-admin.html>

### Q69 · Answer: D

**Why (P13):** An aggregator already holds configuration data for every account and Region, and advanced queries answer the question in seconds.

- **A** — wrong: 320 manual checks.
- **B** — wrong: works, but takes far longer to build and run.
- **C** — wrong: S3 data classification.
- **D** — correct: one SQL query.

**Reference:** <https://docs.aws.amazon.com/config/latest/developerguide/querying-AWS-resources.html>

### Q70 · Answer: B

**Why (P14, P2):** IRSA trust policies must match the exact `sub` claim, `system:serviceaccount:<namespace>:<name>`. A namespace mismatch denies the assume-role call.

- **A** — wrong: grants the permissions to every pod on the node.
- **B** — correct: fix the trust condition and the annotation.
- **C** — wrong: the role is never assumed, so its permissions are irrelevant.
- **D** — wrong: unnecessary.

**Reference:** <https://docs.aws.amazon.com/eks/latest/userguide/associate-service-account-role.html>

### Q71 · Answer: D

**Why (P12):** DynamoDB auto scaling (Application Auto Scaling target tracking) adjusts provisioned capacity to follow utilization.

- **A** — wrong: custom code with coarse reaction.
- **B** — wrong: caches reads, but write throttling remains.
- **C** — wrong: replication, not scaling.
- **D** — correct: native, utilization-based scaling.

**Reference:** <https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/AutoScaling.html>

### Q72 · Answer: C

**Why (P13):** Inspector scans EC2 continuously, using the SSM Agent or agentless scanning, org-wide through a delegated administrator, and sends findings to Security Hub.

- **A** — wrong: malware scanning, not vulnerability management.
- **B** — wrong: configuration rules.
- **C** — correct: continuous, organization-wide vulnerability findings.
- **D** — wrong: S3 data.

**Reference:** <https://docs.aws.amazon.com/inspector/latest/user/scanning-ec2.html>

### Q73 · Answer: A

**Why (P8):** Resilience Hub assesses applications against RTO and RPO policies, recommends improvements, and can run on each release to catch regressions.

- **A** — correct: purpose-built resilience assessment.
- **B** — wrong: general best-practice checks, without RTO/RPO policies.
- **C** — wrong: configuration rules.
- **D** — wrong: visualization only.

**Reference:** <https://docs.aws.amazon.com/resilience-hub/latest/userguide/what-is.html>

### Q74 · Answer: D

**Why (P13):** Organization conformance packs deploy and maintain one set of rules and remediations across all member accounts from the delegated administrator.

- **A** — wrong: aggregators only collect results.
- **B** — wrong: manual and drifts.
- **C** — wrong: configures instances, not Config rules.
- **D** — correct: org-wide, consistent and automatic.

**Reference:** <https://docs.aws.amazon.com/config/latest/developerguide/conformance-pack-organization-apis.html>

### Q75 · Answer: B

**Why (P12):** Lifecycle rules for noncurrent versions control the storage that versioning keeps accumulating.

- **A** — wrong: suspending versioning doesn't remove the noncurrent versions already stored, and it gives up recovery from accidental overwrites.
- **B** — correct: automatic cleanup of noncurrent versions.
- **C** — wrong: disruptive.
- **D** — wrong: lower durability, and the versions still accumulate.

**Reference:** <https://docs.aws.amazon.com/AmazonS3/latest/userguide/lifecycle-configuration-examples.html>
