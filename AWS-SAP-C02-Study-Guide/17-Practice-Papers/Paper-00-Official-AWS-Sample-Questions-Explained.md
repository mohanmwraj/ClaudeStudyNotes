# Practice Paper 00 — Official AWS Sample Questions (Explained)

> A walkthrough of AWS's 10 **official** SAP-C02 sample questions: paraphrased scenarios, AWS's answer key, and deeper explanations in my own words. The question text is **not reproduced here**. Read the original in the AWS PDF.
> **Source:** [AWS Certified Solutions Architect – Professional (SAP-C02) Sample Exam Questions (PDF)](https://d1.awsstatic.com/training-and-certification/docs-sa-pro/AWS-Certified-Solutions-Architect-Professional_Sample-Questions.pdf), © 2022 Amazon Web Services.
> 10 questions · Q3, Q7, Q8 and Q10 are **Select TWO** · Q9 is **Select THREE** · suggested time 25 min (exam pace is about 2.4 min per question).
> [← Practice Papers index](README.md) · [Study Guide start page](../00-README-Start-Here.md)

---

## How to use this paper

1. **Try the original PDF first, under exam conditions.** Open the [official sample questions PDF](https://d1.awsstatic.com/training-and-certification/docs-sa-pro/AWS-Certified-Solutions-Architect-Professional_Sample-Questions.pdf), set a 25-minute timer, and write down your answers **before** you look at page 6 of the PDF or at this file. These 10 questions are the only ones AWS has published with an official key. They show you the exam's style better than any third-party material.
2. Then read each section below. The scenario summaries are short on purpose: they tell you what is being asked, not the exact wording. Answers sit inside collapsible blocks so you can't see them by accident.
3. Finish with **[Lessons from the official sample](#lessons-from-the-official-sample)**. These patterns repeat across the real exam.

> **Note on domain mapping.** AWS does not say which domain or task each sample question belongs to. The mappings below are my assessment against the official SAP-C02 exam guide (D1 26%, D2 29%, D3 25%, D4 20%).

> **Age of the sample.** The PDF dates from 2022 and uses some older names: "AWS Single Sign-On" is now **IAM Identity Center**, and "Aurora Serverless" today means **Aurora Serverless v2** (v1 reached end of life). Since 30 April 2026, **AWS App Runner (used in Q9) no longer accepts new customers**. Existing customers can keep using it, and AWS points new workloads to Amazon ECS Express Mode ([App Runner availability change](https://docs.aws.amazon.com/apprunner/latest/dg/apprunner-availability-change.html)). None of this changes the reasoning AWS is testing.

---

## Quick answer key

| Q | Type | AWS answer | Domain / Task (my mapping) | Topic |
|---|---|---|---|---|
| 1 | Single | **C** | D1 Task 1.5 (cost & visibility) | Spend alerting without taking control from account owners |
| 2 | Single | **D** | D1 Task 1.4 (multi-account) / 1.2 (security controls) | Cross-account read-only role for a third party, deployed with StackSets |
| 3 | Select TWO | **D, E** | D2 Task 2.1 / D3 Task 3.3 | CORS on API Gateway + S3 static website hosting |
| 4 | Single | **A** | D3 Task 3.4 (reliability) | 502 errors during surges = Lambda concurrency limit |
| 5 | Single | **C** | D3 Task 3.2 (security) / 3.1 (operational excellence) | Manage instances with no inbound ports: Systems Manager Run Command |
| 6 | Single | **D** | D1 Task 1.2 / 1.4 | Cross-account IAM role from dev to prod |
| 7 | Select TWO | **B, D** | D3 Task 3.5 (cost) | Kinesis shard right-sizing + Lambda instead of an idle ASG |
| 8 | Select TWO | **B, D** | D2 Task 2.4 (reliability) / D3 Task 3.4 | SQS buffering + Lambda concurrency limit to protect a downstream system |
| 9 | Select THREE | **A, D, F** | D2 Task 2.2 (business continuity) / D1 Task 1.3 | Two-Region active-active with the least change |
| 10 | Select TWO | **B, C** | D4 Task 4.4 (modernization) / 4.3 | ALB in front of the web tier + Aurora Serverless; Graviton ruled out by Windows |

---

## Question 1: Preventing runaway spend in accounts the business groups control

**Scenario (paraphrased).** Business groups each own an AWS account. An attacker took over one account and launched many instances, which ran up a large bill. The architect must protect **every** account from excessive spending, but each business group insists on **keeping full control of its own account**. The options are: an Organizations SCP that blocks expensive instance types; a per-account IAM group policy that blocks expensive instance types; billing alerts with CloudWatch billing alarms that notify through SNS; and regular manual review of Cost Explorer.

<details><summary>Show answer & explanation</summary>

**AWS answer: C.** Turn on billing alerts in each account and create CloudWatch billing alarms that notify the account administrator through SNS when spend passes a threshold.

**Why C is correct**
- The deciding constraint is **"each business group wants to retain full control."** Billing alarms detect and notify. They take no control away from anyone.
- CloudWatch billing alarms use the `EstimatedCharges` metric. Billing metric data lives in **us-east-1**, and you must turn on billing alerts (Billing preferences) before the metric appears. The alarm fires near real time, so it catches a compromise quickly, unlike a monthly review.

**Why the distractors fail**
- **A (SCP limiting instance types):** SCPs are a **central** guardrail that account administrators cannot override, which takes away the full control the stem says they want. It also doesn't solve the problem: an attacker can still launch **many** allowed instance types. SCPs filter actions, not spend.
- **B (IAM group policy limiting instance types):** This also restricts what account users can do. It only covers users in that group, so a compromised role or root user bypasses it. Like A, it does not cap quantity.
- **D (Cost Explorer reviews):** This is manual and after the fact. It gives no immediate alert.

**Concept tested.** Pick the control type that fits: **detective/alerting** (alarms, budgets) when owners keep autonomy, versus **preventive** (SCPs, permission boundaries) when central governance is acceptable.

**How to recognize the pattern elsewhere**
- "Teams must keep full control" or "must not restrict developers" → choose **notification/detective** controls (CloudWatch billing alarms, **AWS Budgets** alerts, Cost Anomaly Detection), not SCPs.
- "Must prevent X in all accounts, centrally" → SCP or RCP.
- In newer questions, **AWS Budgets** (with Budget Actions) and **Cost Anomaly Detection** are the modern equivalents of billing alarms. Budget Actions can apply restrictions automatically, so watch whether the stem allows automated restriction.

**References:** [Create a billing alarm to monitor estimated charges](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/monitor_estimated_charges_with_cloudwatch.html) · [AWS Budgets](https://docs.aws.amazon.com/cost-management/latest/userguide/budgets-managing-costs.html) · [AWS Cost Anomaly Detection](https://docs.aws.amazon.com/cost-management/latest/userguide/manage-ad.html)

</details>

---

## Question 2: Read-only access across all accounts for a third-party monitoring tool

**Scenario (paraphrased).** An organization in AWS Organizations already uses AWS SSO (now IAM Identity Center), linked to on-premises Active Directory, for human access. A third-party monitoring product runs **in its own AWS account** and needs **read-only access to every account**. The options are: an SSO user with a read-only permission set whose username and password go to the vendor; an IAM role in the management account only that the vendor's account can assume; inviting the vendor's account into the organization; and a CloudFormation template defining an IAM role that trusts the vendor's account, deployed to all accounts with a **stack set**.

<details><summary>Show answer & explanation</summary>

**AWS answer: D.** Define the role in a template whose trust policy names the vendor's account, then deploy it to every member account in one operation with **CloudFormation StackSets**.

**Why D is correct**
- Machine-to-machine cross-account access should use an **IAM role that the external account assumes** with STS `AssumeRole`. The vendor gets short-lived credentials automatically, and no long-term secrets are shared.
- **StackSets** deploy the same resource to many accounts and Regions at once. With service-managed permissions and automatic deployment, new accounts that join an OU get the role too.

**Why the distractors fail**
- **A (SSO user + password):** IAM Identity Center issues **temporary** session credentials for human sign-in, so an automated tool would keep losing access and need to sign in again. Sharing a human-style username and password with a vendor is also a security anti-pattern.
- **B (role in the management account only):** This grants access to **one** account, the management account. Roles don't reach across the organization. It also puts a third party into the most privileged account.
- **C (invite the vendor into the org):** Joining an organization grants **no** access to other member accounts. It also hands your governance boundary to an outsider.

**Concept tested.** Cross-account access for a third party uses a **role with a trust policy**. Multi-account rollout uses **StackSets**.

**Professional-level additions (not in the options, but expected knowledge)**
- Third-party trust policies should require an **external ID** (`sts:ExternalId` condition) to prevent the **confused deputy** problem.
- Scope it with the `ReadOnlyAccess` or `ViewOnlyAccess` managed policy, or a tighter custom policy.

**How to recognize the pattern elsewhere**
- "Third party / SaaS / partner needs access to our accounts" → **IAM role + trust policy (+ external ID)**. Never IAM users or access keys, and never SSO credentials.
- "Deploy the same IAM role, Config rule or baseline to all accounts, including new ones" → **CloudFormation StackSets** (service-managed, auto-deploy to OUs), or Control Tower customizations.
- "Joining the organization" never grants data-plane access by itself.

**References:** [Working with CloudFormation StackSets](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/what-is-cfnstacksets.html) · [Access for AWS accounts owned by third parties](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_common-scenarios_third-party.html) · [The confused deputy problem](https://docs.aws.amazon.com/IAM/latest/UserGuide/confused-deputy.html)

</details>

---

## Question 3: An S3-hosted HTML form can't post to API Gateway (Select TWO)

**Scenario (paraphrased).** A static HTML form in a public S3 bucket uses JavaScript to POST to an API Gateway endpoint backed by Lambda. Each method works when tested in the API Gateway console. Which **two** steps make the form work from the browser? The options are: enable CORS on the S3 bucket; move the form to EC2; request an API Gateway quota increase; enable CORS in API Gateway; configure the S3 bucket for static website hosting.

<details><summary>Show answer & explanation</summary>

**AWS answer: D and E.**

**Why D is correct (CORS on API Gateway)**
- The page loads from the S3 website origin (`bucket.s3-website-<region>.amazonaws.com`), and the script calls `api-id.execute-api.<region>.amazonaws.com`. That is a **different origin**, so the browser enforces CORS. The **API** must return `Access-Control-Allow-Origin` (and answer the `OPTIONS` preflight for a JSON POST).
- Console tests worked because the console doesn't run in a browser cross-origin context. That clue tells you this is a **CORS** problem, not a backend problem.
- With **Lambda proxy integration**, the Lambda function itself must return the CORS headers on its actual responses. Enabling CORS in the console only sets up the `OPTIONS` method and the non-proxy responses. This is a common real-world gotcha.

**Why E is correct (S3 website hosting)**
- AWS's key says static website hosting is needed for the form to be served through a **website endpoint**, which gives index documents and HTML served as a web page from the website origin.

**Why the distractors fail**
- **A (CORS on the S3 bucket):** S3 CORS controls which **other** origins can call S3. Here the browser calls the **API**, so the CORS headers must come from the API's response. The bucket is the caller's origin, not the target.
- **B (move to EC2):** This adds servers and gains nothing. It would still be cross-origin.
- **C (quota increase):** Nothing points to throttling. AWS's key notes API Gateway's **default account-level throttle of 10,000 requests per second per Region** (a soft quota, with a 5,000-request burst). A single form is nowhere near it.

**Concept tested.** Browser same-origin policy. **CORS headers belong on the server being called.**

**How to recognize the pattern elsewhere**
- "Works in the console, Postman or curl but fails from the browser" → **CORS**.
- "SPA on S3/CloudFront calling an API on another domain" → enable CORS on the **API**. An alternative is to serve both behind **one CloudFront distribution** (one origin, path-based behaviours), which removes the cross-origin call entirely.
- Distractors that request a quota increase without any sign of throttling (no 429s, no load surge) are almost always wrong.

**References:** [Enabling CORS for a REST API resource](https://docs.aws.amazon.com/apigateway/latest/developerguide/how-to-cors.html) · [Configuring CORS for an HTTP API](https://docs.aws.amazon.com/apigateway/latest/developerguide/http-api-cors.html) · [Hosting a static website on Amazon S3](https://docs.aws.amazon.com/AmazonS3/latest/userguide/WebsiteHosting.html) · [API Gateway quotas](https://docs.aws.amazon.com/apigateway/latest/developerguide/limits.html)

</details>

---

## Question 4: Intermittent 502 Bad Gateway during traffic surges

**Scenario (paraphrased).** A serverless mobile backend (API Gateway, Lambda, Cognito, DynamoDB) fails intermittently during big traffic surges, and API Gateway returns **HTTP 502** to valid requests. Which change fixes it? The options are: raise the Lambda concurrency quota and alarm on `ConcurrentExecutions`; alarm on the API Gateway TPS quota and use a Lambda function to raise it automatically; shard Cognito user pools across Regions; switch DynamoDB to strongly consistent reads.

<details><summary>Show answer & explanation</summary>

**AWS answer: A.** Increase the Lambda concurrency quota and alarm on `ConcurrentExecutions` as it approaches the limit.

**Why A is correct**
- During a surge, Lambda reaches its account concurrency limit (default **1,000 concurrent executions per Region**, a soft quota you can raise) or the function's reserved concurrency. Lambda then throttles invocations. API Gateway can't get a valid response from the integration and returns a **5xx**. AWS's key says this case gives intermittent **502 Bad Gateway** errors.
- "Intermittent" plus "during large surges" means a capacity limit, not a code bug.

**Why the distractors fail**
- **B (API Gateway TPS quota):** If **API Gateway** were throttling, the client would get **429 Too Many Requests**, not 502. Also, you don't raise service quotas instantly from a Lambda function during an incident. Quota increases go through Service Quotas and aren't immediate.
- **C (multi-Region Cognito):** The errors come from the API endpoint, not from authentication. Latency isn't the symptom.
- **D (strongly consistent reads):** Stale data doesn't produce a Bad Gateway error. Strongly consistent reads also cost twice the read capacity.

**Concept tested.** **Read the HTTP status code.** It tells you which layer failed.

| Code | Where it comes from | Typical exam meaning |
|---|---|---|
| **429** | API Gateway throttling (account, stage or method limits, usage plans) | The front door is throttling. Raise API Gateway limits, add caching or usage plans |
| **502** | The integration returned something invalid or failed (Lambda throttled or errored, bad proxy response format) | Backend capacity or response-format problem. Check **Lambda concurrency** and the proxy response shape |
| **503** | Service unavailable | Backend unavailable |
| **504** | The integration timed out (API Gateway's default integration timeout is 29 s) | Backend too slow. Go **asynchronous** (SQS, Step Functions) or optimize |

**How to recognize the pattern elsewhere**
- "502 during spikes" with Lambda behind it → **Lambda concurrency**. The fixes are a quota increase, provisioned concurrency for latency, or an **SQS buffer** for asynchronous work.
- "429" → API Gateway throttling. "504" → timeout, so redesign for async.
- Answers that "automatically raise a quota when it is hit" are a recurring wrong-answer pattern.

**References:** [API Gateway error handling](https://docs.aws.amazon.com/apigateway/api-reference/handling-errors/) · [Lambda concurrency](https://docs.aws.amazon.com/lambda/latest/dg/lambda-concurrency.html) · [Investigating spikes in Lambda concurrency (AWS Compute Blog)](https://aws.amazon.com/blogs/compute/investigating-spikes-in-aws-lambda-function-concurrency/) · [API Gateway throttling](https://docs.aws.amazon.com/apigateway/latest/developerguide/api-gateway-request-throttling.html)

</details>

---

## Question 5: Managing 100 ECS container instances when only HTTPS inbound is allowed

**Scenario (paraphrased).** An ECS cluster runs on 100 EC2 instances. Policy says the instances' security group must **block all inbound traffic except 443**. How do operators manage the instances? The options are: move SSH to port 2222 and SSH in; move SSH to 2222 and manage through Trusted Advisor; launch without key pairs and use **Systems Manager Run Command**; launch without key pairs and manage through Trusted Advisor.

<details><summary>Show answer & explanation</summary>

**AWS answer: C.**

**Why C is correct**
- The SSM Agent makes **outbound** HTTPS connections to the Systems Manager endpoints. Security groups allow all outbound traffic by default, so you need **no inbound port**. Run Command then runs scripts across the whole fleet by tag, with IAM-based authorization and logging to CloudTrail, S3 or CloudWatch.
- No key pairs means no SSH keys to rotate or leak.

**Why the distractors fail**
- **A and B:** Moving SSH to 2222 still opens an inbound port other than 443, which breaks the policy. Changing the port is security through obscurity.
- **B and D:** **Trusted Advisor** checks your account against best practices (cost, security, limits). It cannot manage or run commands on instances.

**Concept tested.** **Agent-based outbound management** (Systems Manager) replaces inbound SSH or RDP and bastion hosts.

**How to recognize the pattern elsewhere**
- "No inbound ports / no bastion / no SSH keys / audit every session" → **Session Manager** for interactive shells, **Run Command** for fleet commands, **Patch Manager** for patching. For instances with no internet path, add **VPC interface endpoints** (`ssm`, `ssmmessages`, `ec2messages`).
- For shells into ECS **containers** (rather than hosts), the modern answer is **ECS Exec**, which also uses SSM.
- Prerequisites the exam sometimes probes: the instance profile has `AmazonSSMManagedInstanceCore`, the agent is installed and running, and there is a network path to the SSM endpoints.

**References:** [Run Command on ECS container instances](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/ec2-run-command.html) · [AWS Systems Manager Run Command](https://docs.aws.amazon.com/systems-manager/latest/userguide/run-command.html) · [Session Manager](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager.html)

</details>

---

## Question 6: Developers in dev only, operators in dev and prod, one set of credentials each

**Scenario (paraphrased).** There are two accounts, production and development. Developers create and delete infrastructure in **dev only** and must have **no access to prod**. Operators work in **both**. **Every user must have a single set of credentials.** The four options differ in where IAM users, groups and roles live: separate IAM users for operators in each account; putting dev-account users into a group in the prod account; a "shared role" in the **dev** account meant to act on prod; or a role in the **prod** account that trusts the dev account, which only the operators' group in dev may assume.

<details><summary>Show answer & explanation</summary>

**AWS answer: D.**

**Why D is correct**
- All users live in **one** account (dev), so each person has one set of credentials.
- The role that manages prod lives **in the prod account**. Its trust policy trusts the dev account, and in dev only the **operations group** has `sts:AssumeRole` permission on that role ARN. Developers have no such permission, so they can't reach prod.
- This is AWS's standard cross-account delegation pattern: the trusting account defines the role and its trust, and the trusted account's administrators decide which principals can assume it.

**Why the distractors fail**
- **A:** Operators get IAM users in **both** accounts, which is two sets of credentials.
- **B:** You **can't add an IAM user to a group in another account**. IAM groups and users are account-scoped.
- **C:** A role grants permissions only in **the account where it exists**. A role in dev can't directly manage prod resources.

**Concept tested.** Cross-account access = **role in the resource account + trust policy + `sts:AssumeRole` permission in the caller's account.** Both sides must allow it.

**How to recognize the pattern elsewhere**
- "Single set of credentials / single sign-on across accounts" → in modern designs, **IAM Identity Center** permission sets, which are roles provisioned in each account. In IAM-only scenarios, use a **hub (identity) account** with users plus roles in the spoke accounts.
- Any option that puts an IAM principal into another account's group, or a role that acts on another account's resources, is wrong.
- Remember that **resource-based policies** (S3, KMS, SQS, SNS, Lambda) give a second route to cross-account access without role assumption. When the service supports one, watch for it.

**References:** [Cross-account access using roles (IAM tutorial)](https://docs.aws.amazon.com/IAM/latest/UserGuide/tutorial_cross-account-with-roles.html) · [Access to an IAM user in another AWS account that you own](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_common-scenarios_aws-accounts.html) · [IAM Identity Center](https://docs.aws.amazon.com/singlesignon/latest/userguide/what-is.html)

</details>

---

## Question 7: Cutting cost on a Kinesis + Lambda + Athena + ASG pipeline (Select TWO)

**Scenario (paraphrased).** Hundreds of devices stream into Kinesis Data Streams with the **device ID as the partition key, giving one shard per device**. Each device sends **50–450 KB/s**. Lambda processes the records into S3. An hourly Lambda function runs Athena to find outliers (about **10 per hour**) and sends them to SQS, where a **two-instance Auto Scaling group** handles each one with a 30-second job. Which **two** changes **most** reduce cost? The options are: smaller instance types; replace the ASG with Lambda triggered by SQS; 10 devices per shard; 2 devices per shard; shrink the ASG to one instance.

<details><summary>Show answer & explanation</summary>

**AWS answer: B and D.**

**Why B is correct (Lambda replaces the ASG)**
- The actual work is 10 outliers × 30 s = **300 seconds of compute per hour**. EC2 instances run 3,600 s per hour, so they sit idle about 92% of the time. **Lambda with an SQS event source** charges only for those ~300 s of execution, so it cuts the most cost.

**Why D is correct (2 devices per shard)**
- Kinesis provisioned mode charges **per shard-hour**. Each shard accepts **1 MB/s or 1,000 records/s of writes** (and 2 MB/s of reads).
- Worst case, 2 devices × 450 KB/s = 900 KB/s, which **fits under 1 MB/s**. That halves the shard count.

**Why the distractors fail**
- **C (10 devices per shard):** 10 × 450 KB/s = 4.5 MB/s, far above a shard's 1 MB/s write limit. Writes would be throttled (`ProvisionedThroughputExceededException`) and data lost or delayed.
- **A (smaller instances) and E (one instance):** These do save money, but you still pay for mostly idle EC2. They save less than B. One instance also removes the multi-AZ redundancy.

**Concept tested.** **Cost optimization with arithmetic.** Work out the real utilization, compare it with the billing unit (instance-hours, shard-hours, request-based), and right-size **within hard service limits**.

**How to recognize the pattern elsewhere**
- "MOST reduce costs" + spiky or tiny workload on always-on EC2 → **Lambda / event-driven**.
- Kinesis sizing questions: **ingest MB/s ÷ 1 MB/s** and **records/s ÷ 1,000** → required shards. Also look at **on-demand capacity mode** when traffic is unpredictable. Partition-key design (hot shards) is a common trap.
- When two options both "reduce cost", the exam wants the one that removes the waste, not the one that shrinks it.

**References:** [Kinesis Data Streams quotas and limits](https://docs.aws.amazon.com/streams/latest/dev/service-sizes-and-limits.html) · [Using Lambda with Amazon SQS](https://docs.aws.amazon.com/lambda/latest/dg/with-sqs.html) · [Kinesis Data Streams pricing](https://aws.amazon.com/kinesis/data-streams/pricing/)

</details>

---

## Question 8: The app scaled, but the third-party affiliate API was overwhelmed (Select TWO)

**Scenario (paraphrased).** An e-commerce app on an ALB and a multi-AZ ASG posts every completed order to an external affiliate's tracking API. During a promotion, the ASG scaled from 2 to 20 instances. The app was fine, but the **affiliate couldn't keep up** and requests failed. Which **two** changes make the whole flow work under load? The options are: move the affiliate call into Lambda invoked asynchronously; move it into Lambda **fed from an SQS queue**; raise the Lambda timeout; **lower the Lambda reserved concurrency**; raise the Lambda memory.

<details><summary>Show answer & explanation</summary>

**AWS answer: B and D.**

**Why B is correct (SQS + Lambda)**
- The queue **decouples** order processing from the slow downstream system. Orders are stored durably while the affiliate catches up. If a call fails, the message returns to the queue after the visibility timeout and is retried, and a **dead-letter queue** catches messages that keep failing.

**Why D is correct (lower reserved concurrency)**
- Reserved concurrency caps how many copies of the function run at once. That caps the **request rate to the affiliate**: the queue absorbs the burst, and Lambda drains it at a pace the affiliate can handle. This is **throttling to protect a downstream dependency**.

**Why the distractors fail**
- **A (async Lambda invoke without a queue):** This takes load off EC2 but **doesn't reduce the number or rate of calls** to the affiliate. Lambda would scale out and flood it just the same.
- **C (longer timeout):** The function waits longer, but the affiliate gets no less load.
- **E (more memory):** This makes the function's compute faster. The bottleneck is the external system.

**Concept tested.** **Load-levelling queue + concurrency control** to protect a fragile downstream system.

**Professional-level additions**
- AWS now offers **maximum concurrency on the SQS event source mapping**. It limits concurrent invocations from that queue without the throttling side effects of low reserved concurrency (messages bouncing back and landing in the DLQ early). Expect to see it in newer questions.
- Set the queue's visibility timeout to at least 6× the function timeout (AWS guidance for SQS event sources), and configure a DLQ or redrive policy.
- Make the consumer **idempotent**, because SQS standard queues are at-least-once.

**How to recognize the pattern elsewhere**
- "Downstream / third-party / legacy system overwhelmed when we scale" → **SQS buffer + limited consumer concurrency** (or API Gateway usage plans, or Step Functions with rate control).
- "Must not lose orders/messages" → durable queue + DLQ, not fire-and-forget async invokes.
- Options that tweak compute settings (memory, timeout) are wrong when the bottleneck is another system.

**References:** [Using Lambda with Amazon SQS](https://docs.aws.amazon.com/lambda/latest/dg/with-sqs.html) · [Lambda scaling behaviour](https://docs.aws.amazon.com/lambda/latest/dg/lambda-concurrency.html) · [Amazon SQS Developer Guide](https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/welcome.html)

</details>

---

## Question 9: Two-Region active-active with the LEAST change to the architecture (Select THREE)

**Scenario (paraphrased).** A ticketing web app runs on **App Runner**, with images in **ECR**, data in **Aurora MySQL**, and DNS in **Route 53**. It must run **active-active across two Regions** with the **least architectural change**. The options are: ECR cross-Region replication; a VPC endpoint to reach the ECR repository from the other Region; adding a second-Region "deployment target" in the App Runner configuration; deploying App Runner in the second Region with Route 53 latency-based routing; moving to DynamoDB global tables; an Aurora global database with write forwarding in the secondary Region.

<details><summary>Show answer & explanation</summary>

**AWS answer: A, D, F.**

**Why these are correct**
- **A — ECR cross-Region replication:** This copies images to the second Region automatically. It is a registry-level replication rule, so the second Region's service pulls images locally.
- **D — second App Runner service + Route 53 latency-based routing:** App Runner is a Regional service, so you deploy a second service. Route 53 latency records (ideally with health checks) send each user to the closest healthy Region. Both Regions serve traffic, which is what active-active means.
- **F — Aurora global database + write forwarding:** The secondary Region gets a read-only copy, replicated at the storage layer with typical lag under a second. **Write forwarding** lets the app in the secondary Region send writes to it, and Aurora forwards them to the primary writer. The application keeps one connection pattern in both Regions, with **no engine change**.

**Why the distractors fail**
- **B (VPC endpoint to ECR in another Region):** VPC interface endpoints are Regional. They don't give access to a repository in another Region, and they aren't a replication method.
- **C (second deployment target in App Runner):** App Runner has no multi-Region deployment-target setting.
- **E (DynamoDB global tables):** This could work technically, but moving from relational Aurora MySQL to DynamoDB is a **major re-architecture**. It loses on "least change."

**Concept tested.** **Multi-Region active-active building blocks**: replicate artifacts (ECR replication), replicate data (Aurora Global Database, DynamoDB global tables, S3 CRR), and route users (Route 53 latency, geoproximity or failover routing, or Global Accelerator).

**How to recognize the pattern elsewhere**
- "LEAST change" → **keep the same engine or service** (Aurora → Aurora Global Database, not DynamoDB).
- "Active-active, writes in both Regions, relational" → Aurora Global Database **with write forwarding** (writes still go to one primary). For true multi-writer, look at **DynamoDB global tables** (multi-Region, last-writer-wins) or **Aurora DSQL**, if the stem tolerates the change.
- "Active-passive / DR" → Aurora Global Database with **managed failover or switchover**, plus Route 53 **failover** routing.
- Any "deployment target in another Region" or "cross-Region VPC endpoint" option is invented. Reject it.

**References:** [Private image replication in Amazon ECR](https://docs.aws.amazon.com/AmazonECR/latest/userguide/replication.html) · [Aurora global database write forwarding](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/aurora-global-database-write-forwarding.html) · [Route 53 latency-based routing](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/routing-policy-latency.html) · [Disaster recovery options in the cloud (whitepaper)](https://docs.aws.amazon.com/whitepapers/latest/disaster-recovery-workloads-on-aws/disaster-recovery-options-in-the-cloud.html) · [App Runner availability change](https://docs.aws.amazon.com/apprunner/latest/dg/apprunner-availability-change.html)

</details>

---

## Question 10: Modernizing a three-tier app for performance with minimal operational overhead (Select TWO)

**Scenario (paraphrased).** A multi-tier app has a **Windows** web tier on EC2 instances with Elastic IPs, a **Linux** app tier behind an ALB using path-based routing, and **MySQL self-managed on a Linux EC2 instance**. Everything runs on Intel x86. The goal is **better performance** with **minimal operational overhead**. The options are: run MySQL on several EC2 instances; put the web tier behind an ALB; migrate MySQL to **Aurora Serverless**; move **all** instances to Graviton2; replace the app-tier ALB with a self-managed load balancer.

<details><summary>Show answer & explanation</summary>

**AWS answer: B and C.**

**Why these are correct**
- **B — ALB in front of the web tier:** Clients stop pointing at individual Elastic IPs. The ALB spreads traffic across instances, health-checks them, and lets the web tier sit in an Auto Scaling group across AZs. You get better availability and scaling with a managed service.
- **C — Aurora Serverless:** A managed, MySQL-compatible engine replaces a self-run database on EC2. AWS handles patching, backups, storage scaling and Multi-AZ, and capacity scales automatically, so both performance and operational overhead improve.

**Why the distractors fail**
- **A (MySQL on multiple EC2 instances):** You now run replication and failover yourself, which means **more** operational overhead.
- **D (all instances to Graviton2):** **Windows isn't supported on Graviton (Arm64) instances**, and the word "all" includes the Windows web tier. Graviton is a good price/performance move for the **Linux** tiers, but "all" makes this option wrong.
- **E (self-managed load balancer):** This adds overhead. It is the opposite of what the stem asks for.

**Concept tested.** **Modernize with managed services** when "minimize operational overhead" appears, and check every word for a disqualifier (here, "all" + Windows).

**How to recognize the pattern elsewhere**
- "Minimal operational overhead" → managed or serverless (RDS/Aurora, ALB, Fargate, Lambda) over self-managed EC2.
- **Graviton traps:** Windows workloads, x86-only binaries or commercial software, and "all instances" wording. Graviton is correct for Linux, containers, managed services (RDS, ElastiCache, OpenSearch) and Lambda arm64.
- The modern product is **Aurora Serverless v2**. v1 has reached end of life, so if a newer question mentions "Serverless", assume v2 behaviour (scales in fine-grained ACUs, supports Multi-AZ and read replicas).

**References:** [What is an Application Load Balancer?](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/introduction.html) · [Amazon Aurora Serverless](https://aws.amazon.com/rds/aurora/serverless/) · [Aurora Serverless v2 User Guide](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/aurora-serverless-v2.html) · [AWS Graviton](https://aws.amazon.com/ec2/graviton/)

</details>

---

## Lessons from the official sample

These are the recurring reasoning patterns these 10 questions teach. Expect the same patterns, in different settings, throughout the real exam.

| # | Pattern | What to do on the exam | Seen in |
|---|---|---|---|
| 1 | **Read the HTTP status code to find the failing layer** | **429** = API Gateway throttling. **502** = integration or backend failure (for example Lambda concurrency throttling or a bad proxy response). **504** = integration timeout (29 s default), so go async | Q4 |
| 2 | **Autonomy constraints rule out preventive controls** | "Teams keep full control" → detective/alerting (billing alarms, AWS Budgets, Cost Anomaly Detection), not SCPs or IAM denies | Q1 |
| 3 | **Third parties get roles, not credentials** | Cross-account IAM role + trust policy (+ external ID). Never share IAM users or access keys, and never SSO usernames and passwords. SSO/Identity Center credentials are **temporary human sessions**, unsuitable for a long-running tool | Q2 |
| 4 | **Same thing in every account = StackSets** | CloudFormation StackSets (service-managed, auto-deploy to OUs) for org-wide roles and baselines | Q2 |
| 5 | **Cross-account access needs both sides** | Role in the **resource** account, trust policy naming the caller, and `sts:AssumeRole` permission in the caller's account. Users and groups never span accounts | Q2, Q6 |
| 6 | **Org membership grants no access** | Joining an organization adds governance, not data-plane permissions | Q2 |
| 7 | **"Works in the console, fails in the browser" = CORS on the API** | The called server returns the CORS headers. With Lambda proxy, the function returns them | Q3 |
| 8 | **A quota-increase option needs a throttling symptom** | No 429s or limit errors → the quota answer is a distractor. Self-healing "auto-raise the quota" designs are wrong | Q3, Q4 |
| 9 | **No inbound ports = Systems Manager** | Run Command, Session Manager and Patch Manager over outbound HTTPS. Trusted Advisor only advises; it never manages instances | Q5 |
| 10 | **Do the math on cost questions** | Compute real utilization (300 s/h versus 3,600 s/h) and service unit limits (1 MB/s per shard) before choosing. Remove waste rather than shrink it | Q7 |
| 11 | **Protect fragile downstream systems with a queue and a concurrency cap** | SQS buffer + limited Lambda concurrency (reserved concurrency, or SQS event source maximum concurrency) + DLQ | Q8 |
| 12 | **Tuning compute doesn't fix an external bottleneck** | Memory or timeout changes are distractors when another system is saturated | Q8 |
| 13 | **"LEAST change" = keep the same engine or service** | Aurora → Aurora Global Database, not a DynamoDB rewrite. Replicate artifacts (ECR replication) and route with Route 53 | Q9 |
| 14 | **Spot invented features** | "Cross-Region VPC endpoint to ECR", "App Runner second-Region deployment target". If a feature sounds convenient but you've never seen it in the docs, it probably doesn't exist | Q9 |
| 15 | **"Minimal operational overhead" = managed services** | ALB over a self-managed load balancer, Aurora/RDS over databases on EC2 | Q10 |
| 16 | **One disqualifying word sinks an option** | "**All** instances to Graviton" fails because of Windows. Read every qualifier: all, only, single, immediately, without downtime | Q10 |
| 17 | **Multi-select options are judged one by one** | In "Select TWO/THREE", each correct option must be independently true and needed. Reject any option that adds an unneeded component or breaks a constraint | Q3, Q7–Q10 |

**How these map to the exam's style**
- Most stems hinge on **one constraint phrase**: "retain full control", "least change", "most reduce costs", "minimize operational overhead", "single set of credentials", "only port 443". Find it first, then rule out options against it.
- Distractors are usually **technically possible but break the constraint** (DynamoDB in Q9, SCPs in Q1, smaller EC2 in Q7), or **technically impossible** (cross-account IAM groups, cross-Region VPC endpoints, Trusted Advisor managing instances).

---

## Other legitimate official practice resources

Use only AWS-official or reputable original-content materials. **Avoid "brain dumps"**: they break the AWS Certification Program Agreement and can get your certification revoked.

| Resource | What it is | Cost / access |
|---|---|---|
| **Official sample questions (this paper's source)** | 10 questions with AWS's answer key and short rationale | Free: [PDF](https://d1.awsstatic.com/training-and-certification/docs-sa-pro/AWS-Certified-Solutions-Architect-Professional_Sample-Questions.pdf) |
| **AWS Certification Official Practice Question Set: Solutions Architect – Professional (SAP-C02)** | Exam-style questions written by AWS, with feedback and recommended resources. Enroll on AWS Skill Builder: open the catalog, filter by Exam Preparation, and search for the SAP-C02 practice question set | **Free** with an AWS Skill Builder account. [AWS overview page](https://training.resources.awscloud.com/get-certified-solutions-architect-professional/solutions-architect-official-practice-questions) |
| **Exam Prep Standard Course: AWS Certified Solutions Architect – Professional (SAP-C02)** | About 5 hours of instructor videos walking through each domain, with exam-style questions | **Free** on AWS Skill Builder. An **Enhanced** version with extra questions, flashcards and labs comes with a Skill Builder subscription |
| **Exam Prep Official Practice Exam: AWS Certified Solutions Architect – Professional (SAP-C02)** | Full-length simulation: 75 questions, 180 minutes, per-option feedback and resource links | **Skill Builder subscription** required |
| **SAP-C02 4-step Exam Prep Plan (Skill Builder)** | AWS's curated path tying the above together | [skillbuilder.aws SAP-C02 exam prep plan](https://skillbuilder.aws/category/exam-prep/solutions-architect-professional-SAP-C02) |
| **Official exam guide** | The authoritative list of domains, task statements and in-scope services | [SAP-C02 exam guide](https://docs.aws.amazon.com/aws-certification/latest/solutions-architect-professional-02/solutions-architect-professional-02.html) |
| **Certification prep hub** | AWS overview of free and subscription prep content | [aws.amazon.com/certification/certification-prep](https://aws.amazon.com/certification/certification-prep/) · [SAP certification page](https://aws.amazon.com/certification/certified-solutions-architect-professional/) |

> Names checked against AWS's certification page and Skill Builder listings in October 2026. The certification page names the Official Practice Question Set and Official Practice Exam but gives no direct catalog links. Skill Builder course URLs change often, so search for the names above in the Skill Builder catalog rather than relying on deep links.
>
> **Timing note:** SAP-C02's last exam day is **16 November 2026**, and SAP-C03 registration opens on 27 October 2026. Make sure any practice product you buy is the **SAP-C02** version.

**Suggested order before 31 October:** (1) this official sample, cold → (2) the free Official Practice Question Set → (3) the study-guide practice papers in this folder → (4) the Official Practice Exam as a full timed run about 5–7 days before the exam → (5) targeted review of weak domains.

---

[← Practice Papers index](README.md) · [Study Guide start page](../00-README-Start-Here.md)
