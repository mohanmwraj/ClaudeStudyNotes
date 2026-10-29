# Mock Paper 2 · 75 Questions · 180 Minutes

**Instructions:**
* Set a timer for **180 minutes** and answer all 75 questions without notes.
* Write your answers on paper or in a text file (for example `1-C, 2-A, …`). For multiple-response questions, select exactly the number requested; there is no partial credit.
* Flag questions you're unsure about and come back to them. Never leave one blank.
* When finished, mark your answers with [08-mock-paper-2-answers.md](08-mock-paper-2-answers.md) and read the explanation for every question you missed **or guessed**.

**Composition** (matches the official DOP-C02 weighting): Domain 1: 17 · Domain 2: 13 · Domain 3: 11 · Domain 4: 11 · Domain 5: 10 · Domain 6: 13. The domain and task labels are shown to help your review. The real exam doesn't label questions.

**Scoring guide:** each question is worth 1 point. **60/75 (80%)** or better means you're ready; 53–59 means review your weak domains and retake; below 53 means study more before booking. AWS reports a scaled score, so these thresholds are a conservative readiness estimate, not a conversion.

---

### Q1 · Domain 3 · Task 3.2 · Single answer

An SQS queue triggers a Lambda function that writes each message to an Amazon RDS for MySQL database. During bursts, Lambda scales to hundreds of concurrent executions and exhausts the database's connections. The team wants to cap the number of concurrent invocations from this queue at 20, without throttling errors and without affecting other functions.

What should the DevOps engineer configure?

- **A.** Reserved concurrency of 20 on the function.
- **B.** A maximum concurrency of 20 on the SQS event source mapping.
- **C.** A smaller batch size on the event source mapping.
- **D.** A longer visibility timeout on the queue.

### Q2 · Domain 1 · Task 1.1 · Single answer

A monorepo on GitHub contains five services. Today a single V2 pipeline per service runs on every push to `main`, so every pipeline runs for every change. Each service's pipeline should run only when files under its own directory (for example `services/payments/**`) change.

What is the MOST operationally efficient solution?

- **A.** Add a CodeBuild step at the start of each pipeline that inspects the changed files and stops the pipeline when they aren't relevant.
- **B.** Split the monorepo into five repositories.
- **C.** Use a Lambda function that receives GitHub webhooks and starts the right pipeline.
- **D.** Configure each pipeline's push trigger with a file path filter that includes only that service's directory.

### Q3 · Domain 6 · Task 6.1 · Single answer

A data-processing role has broad read access to an analytics bucket. A specific nightly job assumes this role but should be able to read only the `exports/finance/` prefix during its session. The role itself must keep its broader permissions for other jobs.

What should the DevOps engineer do?

- **A.** Have the job pass an inline session policy in the `AssumeRole` call that allows `s3:GetObject` only on `exports/finance/*`. The effective permissions are the intersection of the role's policies and the session policy.
- **B.** Create a second bucket for the finance exports.
- **C.** Add a permissions boundary to the role.
- **D.** Add a Deny statement to the role for every other prefix.

### Q4 · Domain 4 · Task 4.1 · Single answer

Operations wants to alarm if the `nginx` process stops running on any web server, and to graph the process's CPU and memory use, with no custom scripts.

What should the DevOps engineer configure?

- **A.** An EC2 status check alarm.
- **B.** A Route 53 health check.
- **C.** The CloudWatch agent's `procstat` plugin to collect metrics for the `nginx` process (for example `procstat_lookup_pid_count`), with an alarm when the PID count is below 1.
- **D.** Detailed monitoring on the instances.

### Q5 · Domain 2 · Task 2.1 · Single answer

Fifteen teams define infrastructure with the AWS CDK. Security wants every S3 bucket and every SQS queue in every CDK application to be encrypted and to block public access, and wants synthesis to fail when a construct violates these rules, before anything is deployed.

What should the DevOps engineer implement?

- **A.** An AWS Config rule that checks deployed buckets.
- **B.** CDK Aspects (for example a rule pack such as cdk-nag, or a custom aspect) applied to every app, which report errors that fail synthesis when a construct violates the rules.
- **C.** A manual code review checklist.
- **D.** An SCP that denies `s3:CreateBucket`.

### Q6 · Domain 1 · Task 1.2 · Select TWO

A team wants integration tests to run for each pull request against a full, isolated copy of the application stack, and that copy to be removed automatically when the pull request is closed or merged, so nothing is left running.

Which combination of steps meets these requirements? (Select TWO.)

- **A.** On pull request created or updated events, start a CodeBuild build that deploys a CloudFormation stack named after the pull request ID and runs the integration tests against its outputs.
- **B.** Run all pull requests' tests against one shared test environment.
- **C.** Ask developers to delete their test stacks manually after merging.
- **D.** Create an EventBridge rule (or webhook) on pull request closed or merged events that starts a build that deletes the pull request's stack.
- **E.** Run the integration tests nightly against `main`.

### Q7 · Domain 5 · Task 5.1 · Single answer

Inventory updates must be delivered to three downstream services. Each service must receive every update, and each must process updates for a given product **in order**. The services consume at different speeds.

What should the DevOps engineer design?

- **A.** One SQS standard queue shared by the three services.
- **B.** An EventBridge rule with three Lambda targets.
- **C.** An SNS FIFO topic with three SQS FIFO queues subscribed, using the product ID as the message group ID.
- **D.** A Kinesis Data Firehose stream with three destinations.

### Q8 · Domain 6 · Task 6.2 · Single answer

Microservices on EKS and EC2 must use mutual TLS with certificates from a private, company-controlled certificate authority. Certificates must be issued and renewed automatically, and the CA's private key must stay in AWS-managed HSMs.

What should the DevOps engineer use?

- **A.** Public ACM certificates.
- **B.** Self-signed certificates generated in each container.
- **C.** Certificates stored in Parameter Store.
- **D.** AWS Private Certificate Authority, issuing private certificates (through ACM for automatic renewal on integrated services, or through Kubernetes integrations such as cert-manager for pods).

### Q9 · Domain 1 · Task 1.4 · Single answer

A team wants blue/green deployments for an Amazon ECS service behind an ALB. They want lifecycle hooks for validation and a "bake time" during which they can roll back instantly after production traffic has moved. They also want to avoid managing a separate CodeDeploy application and deployment group.

What should the DevOps engineer use?

- **A.** The ECS built-in blue/green deployment strategy, with Lambda lifecycle hooks and a configured bake time.
- **B.** The ECS rolling update with `minimumHealthyPercent` of 100.
- **C.** Two ECS services with Route 53 weighted records, switched by hand.
- **D.** An Elastic Beanstalk Docker environment.

### Q10 · Domain 2 · Task 2.2 · Single answer

A company invited an existing standalone AWS account to join its organization. Administrators in the management account can assume `OrganizationAccountAccessRole` in accounts created through Organizations, but not in the invited account.

Why, and what should the DevOps engineer do?

- **A.** Invited accounts can't be administered centrally; recreate the account through Organizations.
- **B.** An SCP is blocking the role.
- **C.** The role is created automatically only for accounts created through Organizations. Create a role in the invited account (for example `OrganizationAccountAccessRole`) that trusts the management account, with the required permissions.
- **D.** Enable all features in the organization again.

### Q11 · Domain 3 · Task 3.1 · Single answer

A company runs an Aurora Global Database with its primary in `us-east-1` and a secondary in `us-west-2`. It needs to move the primary to `us-west-2` for a planned, multi-day maintenance activity in `us-east-1`, with **no data loss**, and keep the global database topology afterwards.

What should the DevOps engineer do?

- **A.** Detach the secondary cluster and promote it as a standalone cluster.
- **B.** Perform an Aurora Global Database switchover (managed planned failover) to the `us-west-2` cluster.
- **C.** Take a snapshot in `us-east-1` and restore it in `us-west-2`.
- **D.** Create a cross-Region read replica and promote it.

### Q12 · Domain 4 · Task 4.2 · Single answer

An application is instrumented with X-Ray using the default sampling rule (1 request per second plus 5%). Investigations of the low-volume but critical `/checkout` path rarely find any traces. The team wants many more `/checkout` requests traced without increasing sampling everywhere.

What should the DevOps engineer do?

- **A.** Disable sampling in the SDK.
- **B.** Add metadata to `/checkout` segments.
- **C.** Enable CloudTrail data events.
- **D.** Create an X-Ray sampling rule with a higher priority that matches the `/checkout` URL path, with a larger reservoir and rate.

### Q13 · Domain 1 · Task 1.4 · Single answer

A REST API in API Gateway is deployed to a `prod` stage. The team wants to send 10% of production requests to a new API deployment, compare its error metrics with the current deployment, and then promote it, all within API Gateway.

What should the DevOps engineer use?

- **A.** A second API with a Route 53 weighted record.
- **B.** A Lambda alias with weighted versions.
- **C.** A canary release on the `prod` stage, with 10% of traffic to the canary deployment, then promote the canary.
- **D.** A usage plan with a 10% quota.

### Q14 · Domain 5 · Task 5.2 · Single answer

Finance wants every new EC2 instance, EBS volume and S3 bucket tagged automatically with the IAM identity that created it, so that untagged costs can be attributed. Developers often forget to tag.

What should the DevOps engineer implement?

- **A.** An EventBridge rule on the CloudTrail events for the relevant create calls (for example `RunInstances`, `CreateVolume`, `CreateBucket`) that invokes a Lambda function to tag the new resources with the caller's identity from `detail.userIdentity`.
- **B.** A weekly script that tags all resources with "unknown".
- **C.** An SCP that denies untagged creates, while keeping the tags developers choose.
- **D.** AWS Cost Explorer.

### Q15 · Domain 2 · Task 2.1 · Single answer

A CloudFormation stack update changes the application's infrastructure. If the application's error alarm fires during the update, or within 30 minutes afterwards, the stack must roll back automatically.

What should the DevOps engineer configure?

- **A.** A stack policy.
- **B.** Termination protection.
- **C.** A `CreationPolicy` on every resource.
- **D.** Stack rollback triggers that reference the error alarm, with a monitoring time of 30 minutes.

### Q16 · Domain 6 · Task 6.1 · Single answer

A mobile app lets signed-in users upload photos directly to S3. Each user must be able to read and write only objects under their own prefix (`users/<their-id>/`), and the app must not embed any AWS credentials.

What should the DevOps engineer implement?

- **A.** One IAM user per app user.
- **B.** Amazon Cognito user pools for sign-in, and identity pools to issue temporary credentials for a role whose policy uses the `${cognito-identity.amazonaws.com:sub}` policy variable to restrict access to each user's prefix.
- **C.** A shared IAM user's access keys embedded in the app.
- **D.** A public bucket with obscure object names.

### Q17 · Domain 1 · Task 1.3 · Single answer

The security team wants hardened base container images (OS updates applied, CIS hardening, a security agent installed) rebuilt automatically every week, tested, and pushed to Amazon ECR for teams to use as their `FROM` image.

What should the DevOps engineer use?

- **A.** An EC2 Image Builder container recipe and pipeline, with build and test components, distributing to the ECR repository on a schedule.
- **B.** A developer's laptop running `docker build` every Friday.
- **C.** ECR basic scanning.
- **D.** Systems Manager Patch Manager.

### Q18 · Domain 3 · Task 3.2 · Select TWO

An Auto Scaling group serves a booking site. Load rises every weekday at 08:30 and falls at 18:00, and instances need 6 minutes to become ready. Separately, a marketing event on a known date will bring 5× the normal peak.

Which combination of actions will have capacity ready in time for both? (Select TWO.)

- **A.** Simple scaling with a 300-second cooldown.
- **B.** Predictive scaling, so capacity launches ahead of the recurring daily pattern.
- **C.** Larger instance types with no scaling.
- **D.** An operator manually raising the desired capacity on the event day.
- **E.** A scheduled action that raises the minimum capacity before the marketing event and lowers it afterwards.

### Q19 · Domain 4 · Task 4.1 · Single answer

An application writes JSON logs such as `{"service":"cart","status":503,"latencyMs":812}` to one log group. The team wants a single metric filter that counts 5xx responses **per service**, so that each service can have its own alarm.

What should the DevOps engineer configure?

- **A.** A separate log group per service.
- **B.** A metric filter with the pattern `{ $.status >= 500 }` that emits a value of 1 and uses `$.service` as a metric dimension.
- **C.** A subscription filter to Lambda that publishes metrics.
- **D.** A Logs Insights query scheduled every minute.

### Q20 · Domain 2 · Task 2.2 · Select TWO

A company uses AWS Control Tower Account Factory. Every new account must automatically receive a CloudFormation-based baseline (IAM roles and alarms), and must also be registered in an external CMDB through its REST API, which CloudFormation can't do.

Which combination of steps meets these requirements with the LEAST manual work? (Select TWO.)

- **A.** Have the platform team run a checklist manually after each account creation.
- **B.** Use self-managed StackSets and add each new account manually.
- **C.** Create an EventBridge rule in the management account on the Control Tower `CreateManagedAccount` lifecycle event (status `SUCCEEDED`) that invokes a Lambda function, which calls the CMDB API with the new account's details.
- **D.** Deploy the baseline with a service-managed StackSet that targets the OUs, with automatic deployment enabled.
- **E.** Use AWS RAM to share the baseline template with new accounts.

### Q21 · Domain 1 · Task 1.1 · Single answer

During a two-week holiday change freeze, no change may reach production. However, builds and deployments to the test stage must continue so that work can be validated. The production stage's configuration must not be lost.

What should the DevOps engineer do?

- **A.** Delete the production stage and re-add it after the freeze.
- **B.** Disable the inbound transition to the production stage for the freeze, then enable it afterwards.
- **C.** Stop the pipeline's executions every morning.
- **D.** Remove the production deploy role's permissions.

### Q22 · Domain 6 · Task 6.3 · Single answer

Investigators need to run SQL queries over two years of CloudTrail management and data events from all accounts in the organization, without building or maintaining an S3 + Glue + Athena pipeline.

What should the DevOps engineer set up?

- **A.** CloudTrail Event history.
- **B.** VPC Flow Logs.
- **C.** A CloudTrail Lake organization event data store with the required retention, queried with SQL.
- **D.** A CloudWatch Logs Insights query on each account's log group.

### Q23 · Domain 5 · Task 5.3 · Single answer

A CloudFormation stack that launches EC2 instances into private subnets with no NAT gateway fails with "Received 0 SUCCESS signal(s) out of 1". Instance logs show that `cfn-init` completed successfully, but `cfn-signal` timed out.

What should the DevOps engineer do?

- **A.** Increase the `CreationPolicy` timeout to 2 hours.
- **B.** Remove the `CreationPolicy`.
- **C.** Assign Elastic IP addresses to the instances.
- **D.** Create an interface VPC endpoint for CloudFormation (`com.amazonaws.<region>.cloudformation`) in the VPC, so that `cfn-signal` can reach the CloudFormation API privately.

### Q24 · Domain 1 · Task 1.2 · Single answer

A CodeBuild project runs integration tests that start dependent services with `docker compose`. The build fails with "Cannot connect to the Docker daemon at unix:///var/run/docker.sock".

What should the DevOps engineer change?

- **A.** Enable privileged mode on the CodeBuild project's environment.
- **B.** Increase the compute type.
- **C.** Add the `docker` group to the CodeBuild service role.
- **D.** Use the Lambda compute type.

### Q25 · Domain 4 · Task 4.3 · Single answer

The on-call team wants an immediate notification whenever an ECS task in the production cluster stops because of an error (for example an essential container exiting, or a failed health check), but not for normal stops during deployments or scale-in.

What should the DevOps engineer configure?

- **A.** A CloudWatch alarm on the cluster's CPU utilization.
- **B.** A weekly report from Container Insights.
- **C.** An AWS Config rule for ECS.
- **D.** An EventBridge rule on `ECS Task State Change` events with `lastStatus` `STOPPED` for the cluster, filtered on the `stoppedReason`/`stopCode` values that indicate errors, with an SNS target.

### Q26 · Domain 2 · Task 2.1 · Single answer

Over the years, engineers created about 300 resources through the console in a production account (security groups, IAM roles, S3 buckets, DynamoDB tables). The company now wants these resources managed by CloudFormation without recreating them.

What should the DevOps engineer do?

- **A.** Use the CloudFormation IaC generator to scan the account and generate templates for the selected resources, then import them into stacks (with `DeletionPolicy` set on each imported resource).
- **B.** Delete all the resources and recreate them from new templates.
- **C.** Enable AWS Config and treat the configuration history as the source of truth.
- **D.** Write templates by hand and deploy them as new stacks alongside the existing resources.

### Q27 · Domain 1 · Task 1.4 · Single answer

A CodeDeploy in-place deployment to 90 EC2 instances spread across three AZs must update **one Availability Zone at a time**, wait 15 minutes after each AZ to observe metrics, and keep the other AZs untouched until then.

What should the DevOps engineer configure?

- **A.** `CodeDeployDefault.OneAtATime`.
- **B.** Three separate deployment groups deployed manually.
- **C.** A custom deployment configuration with zonal configuration enabled (one AZ at a time) and a monitor duration of 15 minutes between AZs.
- **D.** `CodeDeployDefault.HalfAtATime`.

### Q28 · Domain 6 · Task 6.2 · Select TWO

A Lambda function in account B must read a database credential stored in AWS Secrets Manager in account A. Security requires the secret to stay in account A only.

Which combination of configurations is required? (Select TWO.)

- **A.** Encrypt the secret with the AWS managed key `aws/secretsmanager`.
- **B.** Attach a resource policy to the secret that allows the Lambda execution role from account B to call `secretsmanager:GetSecretValue`, and grant the same action in the role's identity policy.
- **C.** Create a replica of the secret in account B.
- **D.** Encrypt the secret with a customer managed KMS key whose key policy allows account B's role `kms:Decrypt` (through Secrets Manager), and grant `kms:Decrypt` in the role's identity policy.
- **E.** Create an IAM user in account A and store its keys in the Lambda environment.

### Q29 · Domain 3 · Task 3.1 · Single answer

A global application is deployed **active/active** in `us-east-1` and `eu-central-1`, behind an Application Load Balancer in each Region. Users should be routed to the Region that gives them the lowest latency, and away from a Region whose ALB becomes unhealthy.

What should the DevOps engineer configure in Route 53?

- **A.** A simple routing policy with both ALBs.
- **B.** A failover routing policy with `us-east-1` as primary.
- **C.** A geolocation routing policy with a default record.
- **D.** Latency-based alias records for both ALBs, with Evaluate Target Health enabled (and health checks where needed).

### Q30 · Domain 4 · Task 4.2 · Single answer

During an incident, an engineer needs to know within minutes which error codes appeared most often in the last hour across three Lambda functions' log groups, broken down by 5-minute intervals.

What is the FASTEST way to get this?

- **A.** Run a CloudWatch Logs Insights query across the three log groups, for example `filter level="ERROR" | stats count(*) by errorCode, bin(5m)`.
- **B.** Export the logs to S3 and query them with Athena.
- **C.** Download the log streams and use `grep`.
- **D.** Create a new metric filter and wait for data to accumulate.

### Q31 · Domain 5 · Task 5.1 · Single answer

An IoT backend must run a short validation-and-routing workflow (four steps, under 10 seconds) for about 50,000 events per second. At-least-once execution is acceptable. Cost per execution must be minimal.

Which Step Functions workflow type should the DevOps engineer choose?

- **A.** Standard workflows.
- **B.** Express workflows.
- **C.** Activities with workers on EC2.
- **D.** One Standard workflow per device.

### Q32 · Domain 1 · Task 1.3 · Single answer

A team builds an internal Python library in CodeBuild and wants to publish each release to an AWS CodeArtifact repository so that other teams can `pip install` it.

What should the buildspec do?

- **A.** Upload the wheel to an S3 bucket and share the URL.
- **B.** Commit the built wheel back to the Git repository.
- **C.** Use `pip install --upload`.
- **D.** Run `aws codeartifact login --tool twine` for the repository, then `twine upload --repository codeartifact dist/*`. The build role needs `codeartifact:GetAuthorizationToken`, `codeartifact:GetRepositoryEndpoint`, `codeartifact:PublishPackageVersion` and `sts:GetServiceBearerToken`.

### Q33 · Domain 2 · Task 2.2 · Single answer

A company uses IAM Identity Center. A permission set must grant access defined by a **customer managed** IAM policy (company-specific and maintained by the security team), across 60 accounts.

What must be true for the permission set to work in each account?

- **A.** The policy must be pasted inline into the permission set in each account.
- **B.** A customer managed policy with the same name (and path) must exist in each target account, for example deployed with a StackSet, because the permission set references the policy by name.
- **C.** The policy must be attached to the Identity Center instance in the management account only.
- **D.** Customer managed policies can't be used with permission sets.

### Q34 · Domain 6 · Task 6.2 · Single answer

A public login endpoint (`/api/login`) behind an ALB is under a credential-stuffing attack from thousands of IP addresses. Each IP address sends a few hundred requests per 5 minutes. Legitimate users rarely send more than 20.

What should the DevOps engineer configure first?

- **A.** An AWS WAF web ACL on the ALB with a rate-based rule scoped down to the `/api/login` path, blocking IP addresses that exceed a threshold (for example 100 requests per 5 minutes), plus the managed account-takeover prevention rule group if available.
- **B.** A network ACL with all of the attacking IP addresses.
- **C.** A larger ALB.
- **D.** GuardDuty Runtime Monitoring.

### Q35 · Domain 3 · Task 3.2 · Single answer

A public API in API Gateway (REST) serves free-tier and premium customers. Free-tier customers must be limited to 10 requests per second and 10,000 requests per day; premium customers to 100 requests per second with no daily cap. Each customer has an API key.

What should the DevOps engineer configure?

- **A.** Lambda reserved concurrency per customer.
- **B.** Stage-level throttling of 10 requests per second.
- **C.** Two usage plans (free and premium) with throttle and quota settings, and each customer's API key associated with the right plan.
- **D.** AWS WAF rate-based rules per API key.

### Q36 · Domain 1 · Task 1.4 · Single answer

A CodeDeploy in-place deployment to 40 instances must never take more than 25% of the fleet out of service at once. None of the predefined configurations match.

What should the DevOps engineer do?

- **A.** Use `CodeDeployDefault.HalfAtATime`.
- **B.** Create a custom deployment configuration with a minimum healthy hosts value of 75% (fleet percentage).
- **C.** Use `CodeDeployDefault.AllAtOnce` during a maintenance window.
- **D.** Split the fleet into four deployment groups.

### Q37 · Domain 4 · Task 4.2 · Single answer

Customers in some countries complain that a single-page web application is slow, but server-side latency metrics look normal. The team wants page-load timings, JavaScript errors and HTTP errors as experienced in real users' browsers, broken down by country and browser.

What should the DevOps engineer use?

- **A.** CloudWatch Synthetics canaries in one Region.
- **B.** AWS X-Ray on the backend.
- **C.** CloudWatch RUM (real user monitoring), with its web client added to the application.
- **D.** VPC Flow Logs.

### Q38 · Domain 5 · Task 5.2 · Single answer

Only AMIs built by the company's Image Builder pipeline (identified by an `approved=true` tag) may run in production. Instances launched from other AMIs must be stopped automatically, and their owners notified.

What should the DevOps engineer implement?

- **A.** A weekly manual audit.
- **B.** An IAM policy that allows `ec2:RunInstances` for everyone.
- **C.** Amazon Inspector scanning.
- **D.** The AWS Config managed rule `approved-amis-by-tag`, with an automatic remediation that runs `AWS-StopEC2Instance`, and an EventBridge rule on the compliance change that notifies the owners.

### Q39 · Domain 2 · Task 2.3 · Select TWO

Patching 1,000 instances at once once caused an outage, because a bad patch broke an application. The company now wants patches applied first to a small canary group on Tuesday and to everything else on Thursday, and wants each run to stop automatically if too many instances fail.

Which combination of steps meets these requirements? (Select TWO.)

- **A.** Tag instances into waves (for example `PatchWave=canary` and `PatchWave=main`) and create two maintenance windows (Tuesday and Thursday) targeting those tags, each running `AWS-RunPatchBaseline` with `Install`.
- **B.** Patch all instances in a single maintenance window.
- **C.** Set rate controls on the maintenance window tasks: a maximum concurrency (for example 10%) and a maximum error threshold (for example 5%) so the run stops on failures.
- **D.** Rebuild AMIs with EC2 Image Builder instead.
- **E.** Disable reboots after patching.

### Q40 · Domain 6 · Task 6.1 · Single answer

An audit shows that many IAM roles have permissions that haven't been used for months, and some roles haven't been used at all. Security wants a continuously updated list of unused roles, access keys and unused service permissions across the organization, to drive least-privilege cleanups.

What should the DevOps engineer enable?

- **A.** AWS Trusted Advisor.
- **B.** CloudTrail Insights.
- **C.** AWS Config's `iam-policy-no-statements-with-admin-access` rule.
- **D.** IAM Access Analyzer unused access analysis for the organization.

### Q41 · Domain 1 · Task 1.4 · Single answer

A content management system runs on an Auto Scaling group behind an ALB. Users upload images through the web servers. After every blue/green deployment, images uploaded before the deployment disappear, because they were stored on the old instances' EBS volumes.

What should the DevOps engineer change?

- **A.** Store the uploaded content on a shared Amazon EFS file system (or in S3) mounted or used by all instances, so that content is independent of instance lifecycles.
- **B.** Snapshot the EBS volumes before each deployment and attach them to the new instances.
- **C.** Switch to in-place deployments.
- **D.** Use larger EBS volumes.

### Q42 · Domain 3 · Task 3.3 · Single answer

Compliance requires that an Amazon RDS for PostgreSQL database can be restored to any point within the last 7 days **in a second Region**, if the primary Region is unavailable. The team doesn't need a running replica.

What should the DevOps engineer enable?

- **A.** A Multi-AZ deployment.
- **B.** Cross-Region automated backup replication for the instance, with a 7-day retention, to the DR Region.
- **C.** Daily manual snapshots, kept in the primary Region.
- **D.** An Aurora Global Database.

### Q43 · Domain 4 · Task 4.1 · Single answer

Whenever an application logs a `FraudSuspected` event, the security team must be notified within seconds. The notification must include the customer's account tier, which has to be looked up from a DynamoDB table.

What should the DevOps engineer implement?

- **A.** A metric filter and an alarm on `FraudSuspected`.
- **B.** A nightly export to S3 and an Athena query.
- **C.** A Logs Insights query run every minute by a cron job.
- **D.** A CloudWatch Logs subscription filter on `FraudSuspected` that invokes a Lambda function, which enriches the event from DynamoDB and publishes to SNS.

### Q44 · Domain 2 · Task 2.1 · Select TWO

Security wants two things for all CloudFormation deployments across the organization:
* Any stack that would create an S3 bucket without encryption, or a security group open to `0.0.0.0/0` on port 22, must be blocked **before** the resources are created, even when engineers deploy from their laptops.
* Any such resources that already exist must be detected.

Which combination of controls meets these requirements? (Select TWO.)

- **A.** Run `cfn-lint` in one team's pipeline.
- **B.** Proactive controls: CloudFormation Hooks (for example a Guard hook, or AWS Control Tower proactive controls) activated in the accounts, which fail stack operations that violate the rules.
- **C.** A manual review of every template.
- **D.** An SCP that denies `cloudformation:CreateStack`.
- **E.** Detective controls: AWS Config rules (for example `s3-bucket-server-side-encryption-enabled` and `restricted-ssh`) deployed org-wide.

### Q45 · Domain 1 · Task 1.4 · Single answer

A company wants to use CodeDeploy to deploy to 50 on-premises Linux servers, alongside its EC2 fleets, from the same pipeline.

What must the DevOps engineer do?

- **A.** Convert the servers to EC2 instances with VM Import first.
- **B.** Use Systems Manager Run Command instead; CodeDeploy only supports AWS compute.
- **C.** Install the CodeDeploy agent on each server, give it IAM credentials (preferably through an IAM session ARN using temporary credentials), register the servers with CodeDeploy, tag them, and target the tags in a deployment group.
- **D.** Open inbound port 443 from CodeDeploy to the servers.

### Q46 · Domain 6 · Task 6.3 · Single answer

The security team wants to detect suspicious access patterns to sensitive S3 data, such as an IAM principal suddenly listing and downloading large amounts of data from unusual locations, or access from known malicious IP addresses. It doesn't want to build its own analytics on CloudTrail data events.

What should the DevOps engineer enable?

- **A.** Amazon Macie automated discovery.
- **B.** Amazon GuardDuty S3 Protection.
- **C.** S3 server access logging.
- **D.** AWS Config S3 rules.

### Q47 · Domain 5 · Task 5.3 · Single answer

An Auto Scaling group configured for one instance type (`m5.4xlarge`) in one subnet fails to scale out during a regional demand spike. The activity history shows `InsufficientInstanceCapacity`.

What should the DevOps engineer do to make scale-out more reliable?

- **A.** Configure a mixed instances policy with several suitable instance types, and add subnets in multiple Availability Zones to the group.
- **B.** Request a vCPU service quota increase.
- **C.** Increase the group's maximum size.
- **D.** Lengthen the health check grace period.

### Q48 · Domain 3 · Task 3.3 · Single answer

Auditors ask for regular proof that backups of EBS volumes, RDS databases and DynamoDB tables can actually be restored, with the time each restore takes, without engineers doing restores by hand.

What should the DevOps engineer implement?

- **A.** A quarterly manual restore exercise documented in a wiki.
- **B.** AWS Backup Audit Manager only.
- **C.** AWS Backup restore testing plans that automatically restore selected recovery points on a schedule, validate them, record the restore duration, and clean up.
- **D.** Daily snapshots of the backups.

### Q49 · Domain 1 · Task 1.1 · Single answer

A CodeBuild project in a tooling account builds container images that must be pushed to an Amazon ECR repository in a production account. Pushes fail with an access-denied error.

What should the DevOps engineer configure?

- **A.** Make the production repository public.
- **B.** Enable ECR replication from the production account to the tooling account.
- **C.** Store production IAM user keys in the build.
- **D.** A repository policy on the production repository that allows the tooling account's CodeBuild role the push actions (`ecr:PutImage`, `ecr:InitiateLayerUpload`, `ecr:UploadLayerPart`, `ecr:CompleteLayerUpload`, `ecr:BatchCheckLayerAvailability`), matching IAM permissions on the CodeBuild role, and a docker login to the production registry.

### Q50 · Domain 4 · Task 4.2 · Single answer

A product team wants to define a service-level objective ("99.9% of checkout requests succeed with latency under 500 ms over 28 days"), see the remaining error budget, and be alerted when the budget is burning too fast, with minimal custom work. The services are instrumented with OpenTelemetry.

What should the DevOps engineer use?

- **A.** A CloudWatch dashboard with an average latency widget.
- **B.** CloudWatch Application Signals with SLOs defined on the checkout operation, and burn-rate alarms.
- **C.** AWS X-Ray groups.
- **D.** A custom Lambda function that computes the SLO from logs every hour.

### Q51 · Domain 2 · Task 2.1 · Single answer

The cloud center of excellence has a standard, compliant pattern for an encrypted S3 bucket with logging, lifecycle rules and a restrictive bucket policy. Thirty teams copy and paste it into their CloudFormation templates, and the copies drift apart. The CCoE wants teams to reuse one versioned, centrally maintained definition inside their own templates.

What should the DevOps engineer use?

- **A.** Nested stacks stored in each team's repository.
- **B.** A wiki page with the latest snippet.
- **C.** A CloudFormation module (for example `Company::Storage::SecureBucket::MODULE`) registered in the CloudFormation registry and shared with the teams' accounts, so that templates reference it as a resource type.
- **D.** An SCP that denies `s3:CreateBucket` unless encryption is specified.

### Q52 · Domain 1 · Task 1.4 · Select TWO

During rolling updates of a Kubernetes Deployment on Amazon EKS behind an ALB (managed by the AWS Load Balancer Controller), users see bursts of HTTP 502 errors. Pods receive traffic before the application is ready, and terminating pods are killed while they still have in-flight requests.

Which combination of changes eliminates the errors? (Select TWO.)

- **A.** Add a readiness probe to the pods, so that pods are registered as healthy targets only when the application is ready.
- **B.** Delete all pods manually before each deployment.
- **C.** Add a liveness probe only.
- **D.** Scale the Deployment to zero before each rollout.
- **E.** Set the rolling update strategy to `maxUnavailable: 0` with a suitable `maxSurge`, and add a `preStop` hook (for example a short sleep) longer than the target group's deregistration delay, so that in-flight requests drain before the container stops.

### Q53 · Domain 5 · Task 5.1 · Single answer

A maintenance automation (an SSM Automation runbook) must run **once**, at 02:00 Europe/Berlin local time on a specific date, correctly handling daylight-saving time, and then never run again. The team wants no infrastructure and no cleanup.

What should the DevOps engineer use?

- **A.** A cron job on an EC2 instance set to UTC.
- **B.** An EventBridge Scheduler one-time schedule with the Europe/Berlin time zone that targets the Automation runbook, configured to delete itself after completion.
- **C.** An EventBridge rule with a rate expression of 1 day.
- **D.** A Lambda function that sleeps until the right time.

### Q54 · Domain 6 · Task 6.1 · Single answer

Security deploys IAM roles with the path `/security/` to every account; security tooling uses them. Account administrators, including those with `AdministratorAccess`, must not be able to modify, delete or change the trust policies of these roles. A dedicated break-glass role must still be able to.

What should the DevOps engineer implement?

- **A.** Permissions boundaries on the security roles.
- **B.** A Config rule that detects changes to the security roles.
- **C.** Tags on the roles stating "do not modify".
- **D.** An SCP that denies IAM write actions (for example `iam:UpdateAssumeRolePolicy`, `iam:DeleteRole`, `iam:PutRolePolicy`, `iam:AttachRolePolicy`, `iam:DetachRolePolicy`) on `arn:aws:iam::*:role/security/*`, unless `aws:PrincipalARN` is the break-glass role.

### Q55 · Domain 3 · Task 3.1 · Single answer

An application reads and writes objects in S3 buckets in two Regions, kept in sync by replication. It needs one global endpoint, and during a Regional S3 problem, operators must be able to send all requests to the other Region's bucket within minutes, without changing the application.

What should the DevOps engineer use?

- **A.** An S3 Multi-Region Access Point over the two buckets, with failover controls (active/passive routing) and bidirectional replication rules.
- **B.** Route 53 failover records pointing to the bucket endpoints.
- **C.** CloudFront with an origin group.
- **D.** A Lambda function that copies requests to both buckets.

### Q56 · Domain 4 · Task 4.3 · Single answer

A target tracking policy on average CPU keeps a group near 60%, but sudden traffic spikes push CPU from 50% to 95% in two minutes, and the group adds capacity too gradually. The team wants a much larger response the further CPU rises above target.

What should the DevOps engineer add?

- **A.** A scheduled action.
- **B.** A simple scaling policy with a 600-second cooldown.
- **C.** A step scaling policy driven by a CloudWatch alarm on CPU, with step adjustments, for example +20% capacity at 70–85% and +50% above 85%.
- **D.** A larger instance type.

### Q57 · Domain 2 · Task 2.2 · Single answer

A network team centrally manages VPCs in a network account. Application teams in 30 workload accounts must launch their EC2 instances and RDS databases into these centrally managed subnets, but must not be able to change the route tables, NAT gateways or network ACLs.

What should the DevOps engineer implement?

- **A.** Share the subnets from the network account with the workload accounts (or OUs) through AWS Resource Access Manager (VPC sharing).
- **B.** Create VPC peering connections from every workload VPC to the network account's VPC.
- **C.** Give the application teams IAM roles in the network account with `ec2:*`.
- **D.** Recreate identical VPCs in each workload account with StackSets.

### Q58 · Domain 5 · Task 5.2 · Select TWO

GuardDuty reports that an IAM user's access key is being used from an unusual country to enumerate resources. The incident response policy requires containing the credentials immediately, while preserving the user and its configuration for the investigation.

Which combination of actions should the response automation perform first? (Select TWO.)

- **A.** Delete the account's CloudTrail trails to stop the attacker's access.
- **B.** Deactivate the user's access keys (`UpdateAccessKey` to `Inactive`), and disable the user's console password.
- **C.** Attach an explicit deny-all policy to the user (for example `AWSDenyAll`), which also blocks any temporary credentials derived from the user.
- **D.** Delete the IAM user immediately.
- **E.** Change the root user's password.

### Q59 · Domain 6 · Task 6.2 · Single answer

Policy requires the key material of customer managed KMS keys to be rotated every year. Data encrypted under older key material must stay decryptable without re-encryption, and applications must not change key IDs.

What should the DevOps engineer do?

- **A.** Create a new key every year, re-encrypt all data, and update the applications.
- **B.** Enable automatic key rotation on the customer managed keys, with a rotation period of 365 days.
- **C.** Delete and recreate the keys each year with the same alias.
- **D.** Import new key material into the existing keys every year.

### Q60 · Domain 1 · Task 1.2 · Single answer

Security wants CloudFormation templates checked against company rules before deployment ("every RDS instance must be encrypted and Multi-AZ", "no security group may allow 0.0.0.0/0 on port 22"), with a pipeline failure on violation. The rules must be written in a policy-as-code language that the security team owns.

What should the DevOps engineer add to the pipeline?

- **A.** A manual approval for the security team.
- **B.** CloudTrail Insights.
- **C.** Amazon Inspector scanning of templates.
- **D.** A CodeBuild action that runs AWS CloudFormation Guard (`cfn-guard validate`) with the security team's rule files, and fails on any violation.

### Q61 · Domain 3 · Task 3.3 · Select TWO

A company chooses a **pilot light** DR strategy for a web application (EC2 Auto Scaling, Aurora MySQL) in a second Region. The goals are an RPO under 1 minute, an RTO under 1 hour, and minimal standing cost.

Which combination of measures implements a pilot light? (Select TWO.)

- **A.** Replicate the data continuously to the DR Region (for example an Aurora Global Database secondary cluster), and copy the application AMIs and container images to the DR Region.
- **B.** Run a full-size application fleet in the DR Region behind its own load balancer at all times.
- **C.** Take nightly snapshots and copy them to the DR Region.
- **D.** Keep the application infrastructure defined as code in the DR Region (for example an Auto Scaling group with a desired capacity of 0, or templates ready to deploy). During failover, promote the database, scale out the application tier, and switch Route 53 to the DR Region.
- **E.** Document the manual rebuild steps in a runbook.

### Q62 · Domain 2 · Task 2.3 · Single answer

Every Linux instance must have the `auditd` package installed and running, with a company audit configuration. If someone stops the service or edits the configuration, it must be corrected within 30 minutes, and compliance must be reportable.

What should the DevOps engineer implement?

- **A.** A one-time Run Command.
- **B.** A user data script.
- **C.** An EC2 Image Builder component.
- **D.** A Systems Manager State Manager association (for example running a document that installs and configures `auditd`, and ensures the service is running) on a 30-minute schedule, targeted by tag, with compliance reporting.

### Q63 · Domain 4 · Task 4.1 · Single answer

The security team queries VPC Flow Logs with Athena and wants lower query costs and faster queries. Today the flow logs go to S3 in the default plain-text format under a flat prefix.

What should the DevOps engineer change in the flow log configuration?

- **A.** Send the flow logs to CloudWatch Logs instead.
- **B.** Deliver the flow logs to S3 in Apache Parquet format, with Hive-compatible S3 prefixes and hourly partitions.
- **C.** Increase the aggregation interval to 10 minutes.
- **D.** Enable flow logs only on public subnets.

### Q64 · Domain 6 · Task 6.2 · Single answer

An Amazon EFS file system holds regulated data. Compliance requires encryption at rest and that every client connection be encrypted in transit, enforced by the file system itself.

What should the DevOps engineer do?

- **A.** Enable EBS encryption by default.
- **B.** Use security groups that allow only port 2049.
- **C.** Use an EFS file system created with encryption at rest, mount it with the EFS mount helper's TLS option (`-o tls`), and add a file system policy that denies access when `aws:SecureTransport` is false.
- **D.** Enable S3 Block Public Access.

### Q65 · Domain 5 · Task 5.3 · Single answer

A CodeBuild build compiles successfully, but then fails with `CLIENT_ERROR: no matching artifact paths found`. The application is built into `target/app.jar`, and the buildspec's artifacts section lists `files: [ build/*.jar ]`.

What should the DevOps engineer fix?

- **A.** The `artifacts` section, so that `files` (and, if needed, `base-directory`) match where the build writes its output, for example `target/*.jar`.
- **B.** The CodeBuild service role's S3 permissions.
- **C.** The compute type.
- **D.** The source provider.

### Q66 · Domain 1 · Task 1.3 · Single answer

A SAM application's template references local code directories (`CodeUri: src/orders/`). The team wants its pipeline to produce a deployable artifact for a CloudFormation deploy action in later stages, with the Lambda code stored in S3.

What should the CodeBuild stage do?

- **A.** Zip the repository and pass it to the CloudFormation action directly.
- **B.** Deploy with `sam sync` from CodeBuild.
- **C.** Run `sam build` followed by `sam package` (with an S3 bucket), which uploads the function code to S3 and writes a packaged template with S3 URIs. Output the packaged template as the artifact for the CloudFormation action.
- **D.** Copy the code into the template inline.

### Q67 · Domain 3 · Task 3.2 · Single answer

A provisioned-mode Kinesis data stream throttles producers with `ProvisionedThroughputExceededException` during unpredictable bursts, and the team spends time resharding by hand. It wants the stream to accommodate traffic automatically.

What should the DevOps engineer do?

- **A.** Increase the retention period.
- **B.** Add enhanced fan-out consumers.
- **C.** Switch producers to SQS.
- **D.** Switch the stream to on-demand capacity mode.

### Q68 · Domain 2 · Task 2.3 · Single answer

A company wants to patch, inventory and run commands on 400 on-premises Windows and Linux servers, with the same Systems Manager tooling it uses for EC2.

What should the DevOps engineer do?

- **A.** Install the CloudWatch agent on the servers.
- **B.** Create a hybrid activation (with an IAM service role), install the SSM Agent with the activation code and ID on each server, and manage them as managed nodes (`mi-` IDs).
- **C.** Open inbound RDP and SSH from AWS to the servers.
- **D.** Migrate all the servers to EC2 first.

### Q69 · Domain 6 · Task 6.3 · Single answer

Connections from an application tier to a database tier intermittently fail after a network change. The team suspects a security group or network ACL is blocking some traffic, and needs evidence of which flows are being rejected, and where.

What should the DevOps engineer use?

- **A.** VPC Flow Logs on the relevant subnets or ENIs, analyzing `REJECT` records (with Logs Insights or Athena) to identify the blocked source, destination and ports. VPC Reachability Analyzer can confirm the blocking component.
- **B.** CloudTrail data events.
- **C.** Amazon Inspector.
- **D.** AWS X-Ray.

### Q70 · Domain 5 · Task 5.3 · Single answer

A CloudWatch Synthetics canary that tests an internal ALB (in private subnets) fails every run with a connection timeout, although the application works for internal users.

What should the DevOps engineer do?

- **A.** Make the ALB internet-facing.
- **B.** Increase the canary's timeout.
- **C.** Configure the canary to run inside the VPC (with subnets and a security group allowed by the ALB), with a NAT gateway or VPC endpoints so that it can still write results to S3 and CloudWatch.
- **D.** Switch to CloudWatch RUM.

### Q71 · Domain 3 · Task 3.3 · Single answer

A company needs daily snapshots of tagged EBS volumes, kept for 14 days locally, with a copy in another Region kept for 30 days, and no custom scripts.

What should the DevOps engineer use?

- **A.** A cron job that calls `CreateSnapshot` and `CopySnapshot`.
- **B.** An Amazon Data Lifecycle Manager policy that targets the tag, with a daily schedule, 14-day retention, and a cross-Region copy rule with 30-day retention (or an equivalent AWS Backup plan).
- **C.** EBS Multi-Attach.
- **D.** S3 Cross-Region Replication.

### Q72 · Domain 6 · Task 6.3 · Select TWO

A company wants to make sure that no S3 bucket in any account can be made public, and to have continuous evidence of compliance for auditors.

Which combination of measures meets these requirements? (Select TWO.)

- **A.** Enable Amazon Macie in every account.
- **B.** Enable Amazon GuardDuty.
- **C.** Enable S3 Block Public Access at the account level in every account, and use an SCP that denies `s3:PutAccountPublicAccessBlock` so that it can't be turned off.
- **D.** Review bucket ACLs manually every quarter.
- **E.** Deploy the AWS Config managed rules `s3-bucket-public-read-prohibited` and `s3-bucket-public-write-prohibited` org-wide (for example in a conformance pack), with results in Security Hub or an aggregator.

### Q73 · Domain 4 · Task 4.2 · Single answer

An alarm on the **average** `TargetResponseTime` of an ALB never fires, but 2% of users experience 6-second responses during incidents. The team wants alerts that reflect the slowest user experiences.

What should the DevOps engineer change?

- **A.** Alarm on the p99 (or p95) percentile statistic of `TargetResponseTime`.
- **B.** Alarm on the `Sum` statistic.
- **C.** Change the period from 1 minute to 1 hour.
- **D.** Alarm on `RequestCount`.

### Q74 · Domain 2 · Task 2.2 · Single answer

A company with 300 member accounts doesn't want to secure and manage a root password and MFA device for every member account. It still needs to perform rare root-only tasks, such as deleting a bucket policy that locks everyone out of a bucket.

What should the DevOps engineer implement?

- **A.** Store all root passwords in a shared spreadsheet.
- **B.** Delete the member accounts' root users.
- **C.** Use an SCP that denies all actions to root users, with no other change.
- **D.** Enable centralized root access management for the organization. Remove root credentials from member accounts, and perform the privileged root tasks from the management account (or a delegated administrator) through short-term root sessions.

### Q75 · Domain 1 · Task 1.1 · Single answer

Release approvers say they miss pending approvals in CodePipeline and have to search for what changed. The team wants approvers emailed when an approval is pending, with a link to the release notes and a description of what to check.

What should the DevOps engineer configure?

- **A.** A CloudWatch dashboard of pipeline states.
- **B.** The manual approval action with an SNS topic ARN (with the approvers subscribed), a URL for review (`ExternalEntityLink`) pointing to the release notes, and `CustomData` describing what to check.
- **C.** A Lambda function that polls pipeline state every minute and sends emails.
- **D.** A weekly summary email.
