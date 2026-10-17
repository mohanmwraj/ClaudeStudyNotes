# Chapter 01 — Exam Blueprint, Question Anatomy & Answering Strategy

> **Exam mapping:** All domains | **Weight signal:** Read first | **Study time:** ~1.5 h (re-read the day before the exam)
> [← Start Here](../00-README-Start-Here.md) · [Index](../00-README-Start-Here.md) · [Next →](../02-Multi-Account-Governance/02-Multi-Account-Governance.md)

This chapter tells you **what AWS will test**, **how the questions are built**, and **how to pick the right answer quickly**. Everything here is based on the official SAP-C02 exam guide (fetched October 2026) and the official sample questions.

---

## 1. Exam facts (official)

| Item | Value |
|---|---|
| Exam code | **SAP-C02** (still the current version on 31 Oct 2026) |
| Questions | **75 total = 65 scored + 10 unscored.** You cannot tell which questions are unscored. |
| Duration | **180 minutes** (non-native English speakers can request the **ESL +30 min** accommodation *before* booking; request it in your AWS Certification account) |
| Question types | **Multiple choice:** 1 correct answer and 3 distractors. **Multiple response:** 2 or more correct answers out of 5 or more options. You must pick **all** the correct options to get credit (no partial credit). |
| Scoring | Scaled score from **100 to 1,000**. **Pass mark is 750.** |
| Scoring model | **Compensatory:** you only need to pass overall, not each domain |
| Guessing | **No penalty.** An unanswered question counts as wrong, so **answer every question.** |
| Cost | USD 300 (check your local price at registration) |
| Delivery | Pearson VUE test centre or OnVUE online proctoring |
| Validity | 3 years |
| Target candidate | **2 or more years** designing and implementing on AWS. Gives expert design guidance *across multiple applications and projects within a complex organization* |
| Out of scope | Front-end mobile development, the 12-factor app methodology, in-depth OS knowledge |

> **Version timeline.** AWS has announced **SAP-C03**. Registration opens 27 Oct 2026, delivery starts 17 Nov 2026, and the **last day for SAP-C02 is 16 Nov 2026**. Your 31 Oct exam is **SAP-C02**. Any certification you earn keeps its normal 3-year validity.

### Emerging topics (unscored pretest questions)
The current SAP-C02 guide says you *might* see pretest questions on **"Design security and responsible AI controls"**:
- Content filtering and regulatory compliance controls for generative AI (for example, **Amazon Bedrock Guardrails**)
- Access controls for generative and agentic AI applications (for example, **AgentCore Identity**)
- Human-oversight workflows with approval steps (for example, **AWS Step Functions** wait-for-task-token approval)

These questions **do not affect your score**. Know the one-line answer for each and move on. See [Chapter 11](../11-Analytics-Streaming-and-AI-ML/11-Analytics-Streaming-and-AI-ML.md) for Bedrock.

---

## 2. Domains and every task statement (official)

| Domain | Weight | ≈ Scored questions (of 65) |
|---|---|---|
| **D1** Design Solutions for Organizational Complexity | **26%** | ~17 |
| **D2** Design for New Solutions | **29%** | ~19 |
| **D3** Continuous Improvement for Existing Solutions | **25%** | ~16 |
| **D4** Accelerate Workload Migration and Modernization | **20%** | ~13 |

The domains describe the *situation* (new design, improving an existing system, migration). The **services** cut across all four domains. That is why this guide's chapters are organized by service area, with each task statement mapped to the chapters below.

### Domain 1 — Design Solutions for Organizational Complexity (26%)

| Task | What AWS lists (knowledge / skills) | Study in |
|---|---|---|
| **1.1 Architect network connectivity strategies** | Global infrastructure; VPC, Direct Connect, VPN, **transitive routing**, container networking; **hybrid DNS (Route 53 Resolver)**; segmentation and IP addressing; traffic monitoring. *Skills:* evaluate multi-VPC connectivity; on-prem, co-location and cloud integration; pick Regions/AZs for latency; **troubleshoot traffic flows with AWS tools**; use service endpoints | [04](../04-Networking-VPC-and-Hybrid-Connectivity/04-Networking-VPC-and-Hybrid-Connectivity.md), [05](../05-Edge-DNS-and-Content-Delivery/05-Edge-DNS-and-Content-Delivery.md) |
| **1.2 Prescribe security controls** | IAM and **IAM Identity Center**; route tables, SGs, NACLs; **KMS, ACM**; CloudTrail, **IAM Access Analyzer**, Security Hub, Inspector. *Skills:* **cross-account access**; **third-party IdP integration**; encryption at rest and in transit; **centralized security event notification and auditing** | [03](../03-Identity-and-Access-Management/03-Identity-and-Access-Management.md), [06](../06-Security-Data-Protection-and-Threat-Detection/06-Security-Data-Protection-and-Threat-Detection.md), [02](../02-Multi-Account-Governance/02-Multi-Account-Governance.md) |
| **1.3 Design reliable and resilient architectures** | **RTO/RPO**; DR strategies (**Elastic Disaster Recovery**, pilot light, warm standby, multi-site); backup and restore. *Skills:* DR to meet RTO/RPO; auto-recovery; scale-up vs scale-out; backup strategy | [12](../12-Resilience-HA-and-Disaster-Recovery/12-Resilience-HA-and-Disaster-Recovery.md), [08](../08-Storage-and-Data-Transfer/08-Storage-and-Data-Transfer.md) |
| **1.4 Design a multi-account AWS environment** | **Organizations and Control Tower**; multi-account event notifications; resource sharing (RAM). *Skills:* account structure; **central logging and event notifications**; governance model | [02](../02-Multi-Account-Governance/02-Multi-Account-Governance.md) |
| **1.5 Determine cost optimization and visibility strategies** | Trusted Advisor, Pricing Calculator, Cost Explorer, Budgets; RIs, Savings Plans, Spot; **Compute Optimizer, S3 Storage Lens**. *Skills:* monitor cost; **tagging strategy that maps cost to business units**; how purchasing options affect cost and performance | [16](../16-Cost-Optimization-and-FinOps/16-Cost-Optimization-and-FinOps.md) |

### Domain 2 — Design for New Solutions (29%, the largest domain)

| Task | What AWS lists | Study in |
|---|---|---|
| **2.1 Deployment strategy** | IaC (CloudFormation), CI/CD, change management, Systems Manager. *Skills:* upgrade paths; **rollback mechanisms**; **adopt managed services to cut provisioning and patching overhead**; delegate complex work to AWS | [14](../14-Deployment-DevOps-and-IaC/14-Deployment-DevOps-and-IaC.md) |
| **2.2 Business continuity** | Global infrastructure, Route 53 routing, RTO/RPO, DR scenarios. *Skills:* configure DR; **data and database replication**; **DR testing**; automated, cost-effective multi-AZ/multi-Region backup; centralized monitoring for proactive recovery | [12](../12-Resilience-HA-and-Disaster-Recovery/12-Resilience-HA-and-Disaster-Recovery.md), [09](../09-Databases-and-Caching/09-Databases-and-Caching.md) |
| **2.3 Security controls** | IAM, SG/NACL, encryption, **service endpoints**, credential management, **Shield, WAF, GuardDuty, Security Hub**. *Skills:* least privilege; inbound/outbound flows; **attack mitigation for large-scale web apps**; encryption; endpoints; **patch-management strategy** | [03](../03-Identity-and-Access-Management/03-Identity-and-Access-Management.md), [06](../06-Security-Data-Protection-and-Threat-Detection/06-Security-Data-Protection-and-Threat-Detection.md), [04](../04-Networking-VPC-and-Hybrid-Connectivity/04-Networking-VPC-and-Hybrid-Connectivity.md) |
| **2.4 Reliability** | Storage replication (S3, RDS, ElastiCache), multi-AZ/multi-Region, auto scaling, **SNS/SQS/Step Functions**, **service quotas**. *Skills:* HA design; design for failure; **loose coupling**; app and DB failovers; **Route 53 routing policies** | [12](../12-Resilience-HA-and-Disaster-Recovery/12-Resilience-HA-and-Disaster-Recovery.md), [10](../10-Application-Integration-and-Event-Driven/10-Application-Integration-and-Event-Driven.md), [07](../07-Compute-Containers-and-Serverless/07-Compute-Containers-and-Serverless.md) |
| **2.5 Performance** | Monitoring, storage options, instance families, **purpose-built databases**. *Skills:* large-scale access patterns; elasticity; **caching, buffering, replicas**; choosing purpose-built services; rightsizing | [07](../07-Compute-Containers-and-Serverless/07-Compute-Containers-and-Serverless.md), [08](../08-Storage-and-Data-Transfer/08-Storage-and-Data-Transfer.md), [09](../09-Databases-and-Caching/09-Databases-and-Caching.md) |
| **2.6 Cost optimization** | Cost Explorer, Trusted Advisor, Pricing Calculator; RIs/SPs; **storage tiering; data transfer costs**; managed services. *Skills:* rightsizing; pricing models; **data transfer modelling**; expenditure controls | [16](../16-Cost-Optimization-and-FinOps/16-Cost-Optimization-and-FinOps.md) |

### Domain 3 — Continuous Improvement for Existing Solutions (25%)

| Task | What AWS lists | Study in |
|---|---|---|
| **3.1 Operational excellence** | Alerting and **auto-remediation**; DR planning; CloudWatch; CI/CD and deployment strategies (blue/green, all-at-once, rolling); Systems Manager. *Skills:* logging and monitoring strategy; improve deployments; **prioritize automation**; config-management automation; **failure-scenario exercises (game days)** | [15](../15-Monitoring-Operations-and-Continuous-Improvement/15-Monitoring-Operations-and-Continuous-Improvement.md), [14](../14-Deployment-DevOps-and-IaC/14-Deployment-DevOps-and-IaC.md) |
| **3.2 Security** | Data retention, sensitivity and regulation; **Config rules**; **Secrets Manager / Parameter Store**; least privilege; patching; backups. *Skills:* secrets strategy; **audit for least privilege**; security at every layer; **traceability of users and services**; automated response to vulnerabilities; patch, backup and remediation processes | [06](../06-Security-Data-Protection-and-Threat-Detection/06-Security-Data-Protection-and-Threat-Detection.md), [03](../03-Identity-and-Access-Management/03-Identity-and-Access-Management.md) |
| **3.3 Performance** | Auto scaling, **instance fleets, placement groups**; **Global Accelerator, CloudFront, edge**; CloudWatch; SLAs/KPIs. *Skills:* turn business requirements into metrics; test fixes; adopt new managed services; rightsizing; **find bottlenecks** | [15](../15-Monitoring-Operations-and-Continuous-Improvement/15-Monitoring-Operations-and-Continuous-Improvement.md), [05](../05-Edge-DNS-and-Content-Delivery/05-Edge-DNS-and-Content-Delivery.md), [07](../07-Compute-Containers-and-Serverless/07-Compute-Containers-and-Serverless.md) |
| **3.4 Reliability** | Data replication, scaling, HA, DR tools, **quotas**. *Skills:* growth trends; find unreliable areas; **remove single points of failure**; replication, self-healing, elasticity | [12](../12-Resilience-HA-and-Disaster-Recovery/12-Resilience-HA-and-Disaster-Recovery.md) |
| **3.5 Cost optimization** | Spot, scaling policies, rightsizing; RIs/SPs; **networking and data transfer cost**; alerting and reporting. *Skills:* find under- and over-utilized resources; find unused resources; **billing alarms**; **granular CUR analysis**; tagging for cost allocation | [16](../16-Cost-Optimization-and-FinOps/16-Cost-Optimization-and-FinOps.md) |

### Domain 4 — Accelerate Workload Migration and Modernization (20%)

| Task | What AWS lists | Study in |
|---|---|---|
| **4.1 Select workloads for migration** | Migration Hub; portfolio assessment; asset planning; **wave planning**. *Skills:* migration assessment; **evaluate apps against the 7 Rs**; **TCO** | [13](../13-Migration-and-Modernization/13-Migration-and-Modernization.md) |
| **4.2 Migration approach** | **DataSync, Transfer Family, Snow Family, S3 Transfer Acceleration**; **Application Discovery Service, Application Migration Service (MGN)**; DX, VPN, Route 53; IAM Identity Center, Directory Service; **DMS, SCT**; Control Tower, Organizations. *Skills:* pick the database, application and data transfer mechanism; **secure migration tools**; governance model | [13](../13-Migration-and-Modernization/13-Migration-and-Modernization.md), [08](../08-Storage-and-Data-Transfer/08-Storage-and-Data-Transfer.md) |
| **4.3 New architecture for existing workloads** | EC2, Elastic Beanstalk; ECS/EKS/Fargate/ECR; EBS/EFS/FSx/S3/**Storage Gateway Volume Gateway**; DynamoDB, OpenSearch, RDS, **self-managed DB on EC2**. *Skills:* choose compute, container platform, storage and database | [07](../07-Compute-Containers-and-Serverless/07-Compute-Containers-and-Serverless.md), [08](../08-Storage-and-Data-Transfer/08-Storage-and-Data-Transfer.md), [09](../09-Databases-and-Caching/09-Databases-and-Caching.md) |
| **4.4 Modernization opportunities** | Lambda; containers; S3/EFS; **DynamoDB, Aurora Serverless, ElastiCache**; **SQS, SNS, EventBridge, Step Functions**. *Skills:* **decouple**; go serverless; pick container service; purpose-built DBs; pick integration service | [13](../13-Migration-and-Modernization/13-Migration-and-Modernization.md), [10](../10-Application-Integration-and-Event-Driven/10-Application-Integration-and-Event-Driven.md) |

---

## 3. How SAP-C02 questions are built

A typical question:

```text
┌──────────────────────────────────────────────────────────────────────┐
│ CONTEXT (60–120 words): company, current architecture, numbers       │
│   "A company has 300 accounts in AWS Organizations ... on-premises   │
│    data center connected with a 10 Gbps Direct Connect ..."          │
│ PROBLEM / GOAL: "The company wants to ..."                           │
│ CONSTRAINTS ← this is where the answer is decided                    │
│   "...with the LEAST operational overhead"                           │
│   "...MOST cost-effective"  "...RTO of 15 minutes, RPO of 1 minute"  │
│   "...without modifying the application"  "...within 2 weeks"        │
│ QUESTION: "Which solution will meet these requirements?"             │
│           "Which combination of steps ...? (Select THREE.)"          │
├──────────────────────────────────────────────────────────────────────┤
│ OPTIONS: 4–6 long, similar-looking architectures. Often 2 options    │
│ share 80% of their text and differ in ONE decisive detail.           │
└──────────────────────────────────────────────────────────────────────┘
```

### The constraint words, and what they usually point to

| Phrase in stem | What the right answer usually looks like |
|---|---|
| **LEAST operational overhead / effort / management** | Fully managed or serverless; native features over custom scripts; one service over a combination; *no* EC2 you have to patch; *no* custom Lambda if a built-in feature exists |
| **MOST cost-effective / lowest cost** | Spot, Savings Plans, S3 tiering, serverless for spiky traffic, gateway endpoints instead of NAT, removing idle resources. It must *still meet every other requirement* |
| **MOST secure / least privilege** | Roles and temporary credentials, resource policies with conditions, KMS CMKs, private connectivity (PrivateLink/endpoints), deny-by-default |
| **Highly available** | Multi-AZ at minimum; ASG + ELB; managed multi-AZ DBs |
| **Survive a Region failure / business continuity** | Multi-Region: DR strategy matched to RTO/RPO |
| **RTO/RPO in seconds or minutes** | Pilot light / warm standby / active-active; Aurora Global, DynamoDB global tables, DRS |
| **RTO in hours, cost critical** | Backup & restore (AWS Backup cross-Region copies + IaC) |
| **Without code changes / as-is** | Rehost (MGN), Relocate (VMware), configuration-only fixes |
| **Quickly / within weeks** | Rehost or replatform, not refactor |
| **Decouple / absorb spikes** | SQS (buffer), SNS/EventBridge (fan-out), Step Functions (orchestration) |
| **Real-time / ordering** | Kinesis (per shard key), SQS FIFO (per message group) |
| **Centrally / across all accounts** | Organizations feature + delegated admin; StackSets (service-managed); Control Tower; Firewall Manager; RAM |
| **Audit / traceability** | CloudTrail (org trail), Config, Access Analyzer |
| **Third party needs access** | Cross-account IAM role + **external ID** |

### Recurring patterns in the official sample questions
(Full explanations are in [Paper 00](../17-Practice-Papers/Paper-00-Official-AWS-Sample-Questions-Explained.md).)
- **Intermittent 5xx (502 in the official sample) during traffic surges from API Gateway → Lambda.** AWS's answer is the **Lambda concurrency limit**, not API Gateway throttling. API Gateway's own throttling returns **429**. Rule of thumb: 429 = API Gateway throttle / usage plan; 502 = bad or failed Lambda response (including throttled or errored invocations); 504 = integration timeout.
- **Deploy the same IAM role into every account** → **CloudFormation StackSets**. A role only in the management account covers one account.
- **Third-party read-only access** → a cross-account IAM role trusting the third party's account. IAM Identity Center is the wrong tool for an external system's programmatic access.
- **Billing alerts per account** → billing alarms / Budgets. SCPs don't *alert* on cost.
- **Multi-Region active-active** = ECR cross-Region replication + Route 53 latency routing + Aurora Global Database (or DynamoDB global tables).
- **Over-provisioned Kinesis shards or ASG** → right-size shards and replace polling EC2 consumers with Lambda.

---

## 4. Answering method (use on every question)

1. **Read the last sentence first.** Is it single or multi-select ("Select TWO")? Is the goal cost, effort, security or speed?
2. **Underline the constraints:** numbers (RTO/RPO, TB, Mbps, weeks), "least", "most", "without", "must".
3. **Predict the answer category** before reading the options (for example "this is DX gateway + transit VIF").
4. **Eliminate hard-constraint violators first.** An option that breaks *any* explicit requirement is wrong, however elegant it is. Common violators:
   - It works, but is not "least overhead" (custom EC2 script vs native feature).
   - It is cheaper, but misses the RTO.
   - It is technically impossible: VPC peering is not transitive; SCPs don't grant permissions; gateway endpoints are not reachable from on-prem; ACM public certs for CloudFront must be in us-east-1; you can't encrypt an existing unencrypted RDS instance in place.
   - It uses the wrong scope: a single-account fix for an org-wide problem, or a single-AZ fix for a Region requirement.
5. **Between the final two options, look at the one differing detail.** It is usually the decisive fact (for example *transit* VIF vs *private* VIF, *interface* vs *gateway* endpoint, *Standard* vs *Express* workflow).
6. **Prefer native, managed and minimal.** When two options both work, AWS usually wants the one with fewer moving parts and more managed services.
7. **Multi-select:** each option is usually an independent true/false statement. Pick exactly the number asked for. Options that are steps of one coherent solution go together; watch for an option that contradicts another.
8. **Flag and move on if it takes more than about 3 minutes.** Come back in pass 2.

### Time plan (180 min, 75 questions ≈ 2.4 min each)

| Checkpoint | Target |
|---|---|
| 60 min | Question 25–28 |
| 120 min | Question 52–55 |
| 150 min | Pass 1 complete (all 75 answered, about 10–15 flagged) |
| 150–175 min | Review flagged questions |
| 175 min | Make sure **nothing is blank** |

Long stems are tiring. Take a 20-second mental reset (close your eyes, breathe) every 25 questions.

---

## 5. Typical distractor patterns

| Distractor type | Example | Why it's wrong |
|---|---|---|
| **Works but over-engineered** | Lambda + DynamoDB + custom code to rotate secrets | Secrets Manager rotates natively |
| **Right service, wrong feature** | *Private* VIF to reach many VPCs across Regions via TGW | Needs a **transit** VIF to a DX gateway attached to TGW |
| **Wrong scope** | Configure GuardDuty in each account manually | Use delegated admin with org-wide auto-enable |
| **Impossible feature** | "Enable transitive routing on VPC peering" | Peering is never transitive |
| **Old/legacy approach** | Origin Access Identity, AWS SSO, SMS, Kinesis Data Firehose naming | The answer may use *either* name. Know both, but OAC beats OAI for new designs |
| **Too slow for the RTO** | Restore from snapshots for a 5-minute RTO | Needs warm standby or active-active |
| **Too expensive for the requirement** | Multi-site active-active when RTO is 24 h | Backup & restore is enough |
| **Breaks "no code changes"** | Refactor to Lambda | Rehost/replatform |
| **Security anti-pattern** | Long-term access keys stored in an app config; sharing root credentials | Use roles / IAM Roles Anywhere / Secrets Manager |
| **Monitoring instead of preventing** | Config rule that detects a public bucket, when the requirement is "prevent" | SCP / S3 Block Public Access (account-level) prevents |

**Detect vs prevent vs remediate**, a classic SAP split:
- *Prevent* → SCP / RCP / IAM / permissions boundary / S3 Block Public Access / Control Tower preventive or proactive controls
- *Detect* → AWS Config rules / Security Hub / GuardDuty / Control Tower detective controls / Access Analyzer
- *Remediate* → Config auto-remediation (SSM Automation), EventBridge + Lambda, Security Hub automation rules

---

## 6. What a Professional architect is expected to think about

The Associate exam asks "which service does X?". The Professional exam asks **"which complete design best balances X, Y and Z for *this* organization?"** Train yourself to always weigh:

1. **Blast radius and isolation:** accounts, VPCs, cells, Regions.
2. **Scale of the organization:** hundreds of accounts, central teams, delegated admins, automation over click-ops.
3. **Trade-offs explicitly:** cost vs RTO, consistency vs latency, speed of migration vs modernization.
4. **Operations over time:** who patches it, who rotates it, how it is monitored, how it is rolled back.
5. **Governance as code:** SCPs, Control Tower controls, Config conformance packs, StackSets, Service Catalog.
6. **Data gravity and transfer cost:** where data lives, egress, inter-AZ, NAT processing.
7. **Migrate first, modernize second:** unless the stem forces refactor.

---

## 7. Practice question

**Q.** A company uses AWS Organizations with 150 accounts. The security team must be notified within minutes when any IAM role in any account is granted access to principals outside the organization. The solution must work automatically for new accounts and require the LEAST operational effort. What should the solutions architect do?

- A. Deploy a Lambda function in every account using StackSets that parses CloudTrail logs for `UpdateAssumeRolePolicy` events and emails the team.
- B. Enable IAM Access Analyzer with the organization as the zone of trust from a delegated administrator account, and route findings through EventBridge to an SNS topic.
- C. Create an AWS Config custom rule in each account that evaluates role trust policies daily.
- D. Use an SCP that denies `iam:UpdateAssumeRolePolicy` for all accounts.

<details><summary>Show answer</summary>

**B.** An org-level Access Analyzer with the organization as the zone of trust flags any resource shared outside the org. A delegated admin keeps it out of the management account, and findings go to EventBridge → SNS within minutes. New accounts are covered automatically.
- A works but is custom code in every account, so it is not least effort.
- C is daily, not "within minutes", and custom.
- D *prevents* all trust-policy changes, which breaks legitimate operations, and the requirement was to *notify*.

Ref: https://docs.aws.amazon.com/IAM/latest/UserGuide/what-is-access-analyzer.html
</details>

---

## References
- Exam guide: https://docs.aws.amazon.com/aws-certification/latest/solutions-architect-professional-02/solutions-architect-professional-02.html
- Domain pages: https://docs.aws.amazon.com/aws-certification/latest/solutions-architect-professional-02/solutions-architect-professional-02-domain1.html (domain2, domain3 and domain4 follow the same URL pattern)
- In-scope services: https://docs.aws.amazon.com/aws-certification/latest/solutions-architect-professional-02/sap-02-in-scope-services.html
- Official sample questions (PDF): https://d1.awsstatic.com/training-and-certification/docs-sa-pro/AWS-Certified-Solutions-Architect-Professional_Sample-Questions.pdf
- Certification page: https://aws.amazon.com/certification/certified-solutions-architect-professional/
- SAP-C03 announcement (Sept 2026 offerings): https://aws.amazon.com/blogs/training-and-certification/september-2026-new-offerings/
- AWS Well-Architected Framework: https://docs.aws.amazon.com/wellarchitected/latest/framework/welcome.html
