# Chapter 18 — Cheat Sheets, Decision Trees & Comparisons
> **Exam mapping:** All domains (D1 26% · D2 29% · D3 25% · D4 20%) | **Weight signal:** High (final-week revision) | **Study time:** ~5 h first pass, then 30–60 min/day until exam day
> [← Previous](17-Practice-Papers/README.md) · [Index](00-README-Start-Here.md) · [Next →](19-Glossary-and-Final-Revision.md)

> **How to use this chapter.** This is a *compression* of chapters 02–16, not a replacement. Read it after you have worked through the topic chapters. Use it four ways:
> 1. **Phrase drill (§1):** cover the right-hand column and say the answer out loud. Any row you hesitate on → re-read the linked chapter section.
> 2. **Numbers (§2):** memorise the **bold** rows. The rest are for recognising a distractor that breaks a limit.
> 3. **X vs Y (§3):** for each table, be able to name the *one decisive difference*. SAP options usually differ in exactly that detail.
> 4. **Decision trees (§4):** redraw each tree from memory on a blank sheet. On exam day, do the same on the whiteboard for the question in front of you.
>
> **"Exam view vs Current".** Several quotas changed during 2025–2026 (SCP size, S3 max object, gp3, SQS message size and others). Exam questions were written earlier and may assume the older value. Where a value changed, this chapter shows both. Answer from the *principle* the question tests ("needs more than one shard", "exceeds the SCP limit") rather than from an exact number.

---

## Contents
1. [Exam phrase → likely answer (180+ rows)](#1-exam-phrase--likely-answer)
2. [Numbers & limits (verified, soft quotas marked)](#2-numbers--limits)
3. [X vs Y comparison tables (49 tables)](#3-x-vs-y-comparison-tables)
4. [ASCII decision trees](#4-decision-trees)
5. [Service renames and retired / limited-availability services](#5-service-renames-and-retired--limited-availability-services)
6. [References](#6-references)

---

## 1. Exam phrase → likely answer

> These are **tendencies**, not laws. They tell you which option to look at first. Then check that the option meets *every* constraint in the stem (RTO/RPO, cost, overhead, compliance, timeline).

### 1A. Constraint words (they decide between two otherwise-valid answers)

| Phrase in the stem | Likely answer | Why / watch-out |
|---|---|---|
| "Least operational overhead" / "minimal management" | Managed or serverless service (Lambda, Fargate, DynamoDB, Aurora Serverless v2, S3, managed AD, Transfer Family) | Removes self-managed EC2, cron scripts and custom code. Native features beat custom Lambda glue |
| "Most cost-effective" / "lowest cost" | Cheapest option that still meets *all* other constraints | Usually Spot, S3 lifecycle tiers, Savings Plans, serverless for spiky load, backup-and-restore DR. Never pick a cheap option that breaks RTO/RPO |
| "Minimize downtime" during a migration | Continuous replication + short cutover (MGN, DMS CDC, DataSync incremental) | Not offline Snowball copy or a one-time dump |
| "As quickly as possible" (timeline) | Rehost/replatform with managed tooling | Not a refactor |
| "Without changing application code" | Infrastructure-level fix: RDS Proxy, ElastiCache via config, ALB, Auto Scaling, Global Accelerator, MGN | Ignore options that need SDK changes |
| "Near real-time" | Firehose (buffered), EventBridge, DynamoDB Streams | "Real-time / sub-second" → Kinesis Data Streams or MSK |
| "Highly available" (one Region) | Multi-AZ everything: ASG across ≥2 AZs, RDS Multi-AZ, Aurora replicas, NAT GW per AZ | A single NAT gateway or single instance is the trap |
| "Fault tolerant" | No impact on failure: active-active, over-provisioned across AZs | Stronger than HA |
| "Must not be lost" (messages/data) | Durable queue (SQS) + DLQ, S3, replication | Plain SNS → HTTP with no retry/DLQ is the trap |
| "Securely" without more detail | Least privilege + encryption + private connectivity (endpoints, PrivateLink) | Avoid public IPs, long-term keys and open SGs |
| "Scalable" + unpredictable load | Serverless / on-demand modes (DynamoDB on-demand, Lambda, Aurora Serverless v2) | Provisioned capacity with manual scaling is the trap |
| "Centrally" / "across all accounts" | Organizations-level control: SCP/RCP, delegated administrator, StackSets, Firewall Manager, org trails, AWS Config aggregator | Per-account scripts are the trap |

### 1B. Multi-account & governance → [Chapter 02](02-Multi-Account-Governance.md)

| Phrase in the stem | Likely answer | Why / watch-out |
|---|---|---|
| "Prevent any account from leaving the organization / disabling CloudTrail / using unapproved Regions" | **SCP** with Deny (`organizations:LeaveOrganization`, `cloudtrail:StopLogging`, `aws:RequestedRegion`) | SCPs never grant. They don't apply to the management account |
| "Prevent external principals from accessing our S3 buckets / KMS keys even if a bucket policy allows it" | **RCP** (resource control policy) with `aws:PrincipalOrgID` condition | RCP = resource-side perimeter. SCP = identity-side |
| "Data perimeter: only trusted identities, trusted resources, expected networks" | SCP + RCP + VPC endpoint policies, using `aws:PrincipalOrgID`, `aws:ResourceOrgID`, `aws:SourceVpce` | Know which control covers which direction |
| "New accounts automatically get baseline guardrails, logging, SSO" | **Control Tower** (Account Factory, controls) | Organizations alone doesn't give a landing zone |
| "Customise account provisioning beyond Account Factory" | Account Factory Customization (AFC) / Account Factory for Terraform (AFT) / Customizations for Control Tower (CfCT) | Pick AFT if they say Terraform |
| "Deploy the same stack to every account and Region, including new accounts" | **CloudFormation StackSets** with service-managed permissions + automatic deployment | Self-managed permissions need roles created manually |
| "Share subnets / TGW / Resolver rules / License Manager configs with other accounts" | **AWS RAM** | VPC sharing: participants launch into owner's subnets |
| "Let the security team run GuardDuty/Security Hub/Config for the whole org without using the management account" | **Delegated administrator** | Keep workloads out of the management account |
| "Enforce consistent tags / tag values" | **Tag policies** (+ SCP `aws:RequestTag` Deny to *enforce* on create) | Tag policies report noncompliance. They block only for enforced resource types |
| "Centrally configure EC2/VPC settings so they cannot be changed (e.g., block public AMI sharing, IMDSv2)" | **Declarative policies** (Organizations) | Newer policy type. Enforced by the service, survives new APIs |
| "Separate billing per business unit with consolidated discounts" | Organizations consolidated billing + Cost Categories / cost allocation tags | Separate orgs lose RI/SP sharing |
| "Restrict the root user of member accounts" | SCP (applies to member root) + centralised root access management | Management-account root is not affected by SCPs |
| "Auditor needs read-only access to all accounts' configuration" | AWS Config **aggregator** (org-wide) + cross-account read-only role | |
| "Log archive cannot be deleted even by admins" | Central log archive account + S3 Object Lock (compliance) + SCP Deny on delete | |

### 1C. Identity & access → [Chapter 03](03-Identity-and-Access-Management.md)

| Phrase in the stem | Likely answer | Why / watch-out |
|---|---|---|
| "Temporary access for a third party / SaaS vendor to our account" | **Cross-account IAM role with External ID** in the trust policy | External ID prevents the *confused deputy* problem. Never share access keys |
| "Workforce SSO to many accounts using corporate IdP (Entra ID/Okta)" | **IAM Identity Center** + permission sets + SCIM | Per-account IAM SAML federation is the older, higher-overhead answer |
| "Mobile/web app users sign up and sign in" | **Cognito user pool** | |
| "App users need temporary AWS credentials to call S3/DynamoDB directly" | **Cognito identity pool** (federated identities) | User pool authenticates. Identity pool authorises to AWS |
| "On-premises servers need AWS credentials without long-term keys" | **IAM Roles Anywhere** (X.509 certs) | Or SSM hybrid activation for managed instances |
| "Delegate admin to developers but stop privilege escalation" | **Permissions boundary** on roles they create | Boundary caps max permissions. It grants nothing |
| "Access based on tags / scale permissions without new policies per project" | **ABAC** (`aws:PrincipalTag` = `aws:ResourceTag`) | Session tags from IdP feed ABAC |
| "Find resources shared outside the org / unused access" | **IAM Access Analyzer** (external + unused access analyzers) | Also validates policies and generates least-privilege policies from CloudTrail |
| "EC2 app needs to call AWS APIs" | **Instance profile (IAM role)** | Never store keys on the instance |
| "Containers in EKS need distinct AWS permissions per pod" | **EKS Pod Identity** (or IRSA) | Node role is the over-privileged trap |
| "Users on AD should log in to the AWS console" | Identity Center with AD (AD Connector or Managed AD) as identity source | |
| "Service in account A must use KMS key in account B" | Key policy in B allows A + IAM policy in A allows key use | **Both** sides required for cross-account KMS |

### 1D. Networking & hybrid → [Chapter 04](04-Networking-VPC-and-Hybrid-Connectivity.md)

| Phrase in the stem | Likely answer | Why / watch-out |
|---|---|---|
| "Transitive routing between many VPCs (and on-prem)" | **Transit Gateway** | VPC peering is non-transitive |
| "Few VPCs, lowest cost, highest bandwidth, no transitive need" | **VPC peering** | No hourly attachment fee. Same-AZ data transfer over peering is free |
| "Global network across many Regions with central policy / segments" | **AWS Cloud WAN** | TGW + inter-Region peering is the manual alternative |
| "Expose one service to hundreds of consumer VPCs / accounts with overlapping CIDRs" | **PrivateLink** (NLB/GWLB endpoint service) | One-directional, consumer-initiated. Works across overlapping CIDRs |
| "Service-to-service connectivity across VPCs/accounts with auth policies, no network plumbing" | **VPC Lattice** | Application layer (HTTP/HTTPS/gRPC, TCP). IAM auth policies |
| "On-prem DNS must resolve Route 53 private hosted zone" | **Route 53 Resolver inbound endpoint** | On-prem forwarders → inbound endpoint IPs |
| "VPC workloads must resolve on-prem domain names" | **Resolver outbound endpoint + forwarding rules** (share rules via RAM) | |
| "Private connection to S3/DynamoDB from VPC, no NAT cost" | **Gateway endpoint** | Free. Route-table based. Not reachable from on-prem |
| "On-prem must reach S3 privately over DX/VPN" | **S3 interface endpoint** (PrivateLink) | Gateway endpoints can't be used from on-prem |
| "Consistent, private, high-bandwidth hybrid link" | **Direct Connect** | Takes weeks to provision |
| "Need connectivity this week / backup for DX" | **Site-to-Site VPN** (as backup to DX) | |
| "Encrypt traffic over Direct Connect" | **MACsec** (supported dedicated ports) or **VPN over DX** (public VIF or transit VIF) | DX is not encrypted by default |
| "Connect one DX to VPCs in many Regions/accounts" | **DX gateway** (+ transit VIF to TGW, or private VIF to VGWs) | |
| "More than 1.25 Gbps over VPN" | **ECMP across multiple VPN tunnels on TGW** (BGP) or **Large Bandwidth Tunnels (up to 5 Gbps)** on TGW/Cloud WAN | VGW does not support ECMP |
| "Inspect all east-west and north-south traffic centrally" | **Inspection VPC** with **Network Firewall** or **GWLB + appliances**, TGW **appliance mode** on | Appliance mode keeps flows symmetric |
| "Third-party firewall appliances, scale transparently" | **Gateway Load Balancer** (GENEVE, port 6081) | |
| "Instances in private subnet need outbound internet" | **NAT gateway** (one per AZ for HA) | NAT instance = more overhead |
| "IPv6 outbound only" | **Egress-only internet gateway** | |
| "Overlapping CIDRs must communicate" | **Private NAT gateway** or PrivateLink | TGW/peering can't route overlapping CIDRs |
| "Troubleshoot why instance A can't reach B (config)" | **VPC Reachability Analyzer** | Flow Logs show traffic, not path reasons |
| "Audit accepted/rejected traffic" | **VPC Flow Logs** | No packet payload. Use **Traffic Mirroring** for payload |

### 1E. Edge & DNS → [Chapter 05](05-Edge-DNS-and-Content-Delivery.md)

| Phrase in the stem | Likely answer | Why / watch-out |
|---|---|---|
| "Static IP addresses + UDP / non-HTTP / gaming / IoT" | **Global Accelerator** | CloudFront is HTTP(S)/WebSocket only |
| "Allow-list two fixed IPs at customer firewalls" | **Global Accelerator** (2 static anycast IPs) | Or NLB with Elastic IPs (Regional) |
| "Cache static + dynamic web content globally" | **CloudFront** | |
| "S3 origin must only be reachable through CloudFront" | **Origin Access Control (OAC)** + bucket policy | OAI is legacy. OAC supports SSE-KMS |
| "Restrict premium content to paying users" | **CloudFront signed URLs** (one file) / **signed cookies** (many files) | |
| "Lightweight header rewrite / redirect at edge, sub-ms" | **CloudFront Functions** | Lambda@Edge for network calls, body access, longer runtime |
| "Route users to the Region with lowest latency" | Route 53 **latency-based** routing | Geolocation = by user location (compliance/content) |
| "Shift traffic gradually between two stacks" | Route 53 **weighted** routing | |
| "Active-passive failover by DNS" | Route 53 **failover** routing + health checks | |
| "Route by user's location for legal/content reasons" | Route 53 **geolocation** | Geoproximity = shift by bias around resources |

### 1F. Security & data protection → [Chapter 06](06-Security-Data-Protection-and-Threat-Detection.md)

| Phrase in the stem | Likely answer | Why / watch-out |
|---|---|---|
| "Rotate database credentials automatically" | **Secrets Manager** (native rotation) | Parameter Store has no built-in rotation |
| "Store config values cheaply, some encrypted" | **SSM Parameter Store** (SecureString) | |
| "FIPS 140-3 Level 3, single-tenant HSM, customer has exclusive control" | **CloudHSM** (or KMS custom key store backed by CloudHSM) | KMS itself is FIPS 140-3 Level 3 validated but multi-tenant |
| "Keys must be stored outside AWS" | **KMS External Key Store (XKS)** | |
| "Encrypt data larger than 4 KB with KMS" | **Envelope encryption** (GenerateDataKey) | |
| "Same key usable in multiple Regions for DR / global tables" | **KMS multi-Region keys** | Not a "global" key: replicas are independent resources |
| "Reduce SSE-KMS request cost on S3" | **S3 Bucket Keys** | |
| "Detect compromised instances, crypto-mining, anomalous API calls" | **GuardDuty** | |
| "Find software vulnerabilities in EC2/ECR/Lambda" | **Amazon Inspector** | |
| "Discover PII in S3" | **Macie** | |
| "Investigate root cause of a GuardDuty finding" | **Detective** | |
| "Aggregate findings / CIS & FSBP compliance scores across accounts" | **Security Hub** (CSPM) | |
| "Block SQL injection / XSS / rate limit / geo block at L7" | **AWS WAF** (on CloudFront, ALB, API GW, AppSync, Cognito, App Runner, Verified Access) | |
| "DDoS protection with cost protection and SRT 24/7 support" | **Shield Advanced** | Shield Standard is free, automatic L3/L4 |
| "Apply WAF/SG/Network Firewall rules across all accounts" | **Firewall Manager** | Requires Organizations + Config |
| "Immutable backups / WORM for compliance" | **S3 Object Lock (compliance mode)** / **AWS Backup Vault Lock** | Governance mode can be bypassed with permission |
| "Remediate noncompliant resources automatically" | **AWS Config rule + SSM Automation remediation** | |

### 1G. Compute & containers → [Chapter 07](07-Compute-Containers-and-Serverless.md)

| Phrase in the stem | Likely answer | Why / watch-out |
|---|---|---|
| "Run containers without managing servers" | **ECS on Fargate** (or EKS on Fargate) | |
| "Already use Kubernetes / need K8s API portability" | **EKS** | |
| "Short event-driven tasks < 15 min" | **Lambda** | > 15 min → Fargate/ECS task, Batch, Step Functions |
| "Lambda cold starts hurt latency" | **Provisioned concurrency** (or SnapStart for Java/Python/.NET) | |
| "Too many DB connections from Lambda" | **RDS Proxy** | |
| "Fault-tolerant batch, lowest cost" | **Spot** (diversified, price-capacity-optimized) / **AWS Batch** with Spot | |
| "Low-latency HPC node-to-node" | **Cluster placement group** + EFA | Spread = isolate failures. Partition = HDFS/Cassandra |
| "Licensing per socket/core, BYOL" | **Dedicated Hosts** | Dedicated Instances don't give socket visibility |
| "Ensure capacity in a specific AZ for an event" | **On-Demand Capacity Reservation** (+ Savings Plan for discount) | Regional RIs don't reserve capacity |
| "Simple web app, minimal ops, container image → URL" | **ECS Express Mode** (App Runner closed to new customers 30 Apr 2026) | Exam may still show App Runner as the answer |

### 1H. Storage & data transfer → [Chapter 08](08-Storage-and-Data-Transfer.md)

| Phrase in the stem | Likely answer | Why / watch-out |
|---|---|---|
| "Managed SFTP/FTPS/FTP/AS2 into S3 or EFS" | **AWS Transfer Family** | Keep partners' SFTP clients unchanged |
| "Shared POSIX file system for Linux, many instances, multi-AZ" | **EFS** | |
| "Windows SMB shares, AD integration, DFS" | **FSx for Windows File Server** | |
| "HPC scratch / ML training, high throughput, S3-linked" | **FSx for Lustre** | |
| "NetApp features, multi-protocol NFS/SMB/iSCSI, SnapMirror" | **FSx for NetApp ONTAP** | |
| "Migrate ZFS / low-latency NFS" | **FSx for OpenZFS** | |
| "On-prem apps need NFS/SMB access to S3 with local cache" | **S3 File Gateway** | FSx File Gateway closed to new customers (Oct 2024) |
| "Replace tape backup with virtual tapes" | **Tape Gateway** | |
| "Online transfer of TBs from NFS/SMB/HDFS to S3/EFS/FSx, scheduled, verified" | **DataSync** | |
| "Upload to S3 from far-away clients faster" | **S3 Transfer Acceleration** / multipart upload | |
| "Hundreds of TB, limited bandwidth, offline" | Snowball Edge (existing customers) / **AWS Data Transfer Terminal** for new customers | Snow devices closed to new customers 7 Nov 2025 — exam may still expect Snowball |
| "Infrequently accessed, unknown pattern" | **S3 Intelligent-Tiering** | |
| "Retain 7–10 years, rare access, cheapest" | **S3 Glacier Deep Archive** (retrieval ≤ 12 h standard, ≤ 48 h bulk) | Need minutes? → Glacier Instant/Flexible |
| "Replicate objects to another Region with predictable SLA" | **S3 CRR + Replication Time Control** | |

### 1I. Databases & caching → [Chapter 09](09-Databases-and-Caching.md)

| Phrase in the stem | Likely answer | Why / watch-out |
|---|---|---|
| "Multi-Region, active-active writes, NoSQL" | **DynamoDB global tables** | MREC = last-writer-wins. MRSC = strong consistency, exactly 3 Regions, RPO 0 |
| "Relational, global reads, cross-Region DR with RPO ~1 s, RTO ~1 min" | **Aurora Global Database** | Writes in secondaries via write forwarding |
| "Microsecond reads on DynamoDB, no app logic change beyond client" | **DAX** | |
| "Cache for RDS / session store / leaderboards" | **ElastiCache (Valkey/Redis OSS)** | Memcached = simple, multi-threaded, no persistence |
| "Durable in-memory primary database" | **MemoryDB** | |
| "Unpredictable relational load, scale to zero dev DBs" | **Aurora Serverless v2** (0–256 ACU, 0 = auto-pause) | v1 is end-of-life |
| "Read-heavy relational, offload reporting" | **Read replicas** (RDS) / Aurora replicas | Multi-AZ standby (instance) is not readable |
| "Fast failover, readable standbys, RDS MySQL/PostgreSQL" | **RDS Multi-AZ DB cluster** (1 writer + 2 readable standbys) | |
| "Graph relationships (fraud rings, social)" | **Neptune** | |
| "Time-series IoT metrics" | **Timestream for InfluxDB** | Timestream for LiveAnalytics closed to new customers (Jun 2025) |
| "MongoDB-compatible managed" | **DocumentDB** | |
| "Cassandra-compatible, serverless" | **Amazon Keyspaces** | |
| "Ledger / immutable journal" | QLDB was shut down 31 Jul 2025 → **Aurora PostgreSQL** (AWS's recommended path) | Older questions may still answer QLDB |

### 1J. Integration & event-driven → [Chapter 10](10-Application-Integration-and-Event-Driven.md)

| Phrase in the stem | Likely answer | Why / watch-out |
|---|---|---|
| "Ordering + exactly-once processing" | **SQS FIFO** (message group ID + dedup ID) | Kinesis = per-shard order, at-least-once |
| "Decouple producer and consumer, buffer spikes" | **SQS standard** | |
| "Fan-out one message to many subscribers" | **SNS → SQS fan-out** | |
| "Route events by content to many targets, SaaS sources, cross-account bus" | **EventBridge** | |
| "Replay events after a bug fix" | **EventBridge archive & replay** / Kinesis retention / SNS FIFO archive | |
| "Orchestrate multi-step workflow with retries, human approval, long waits" | **Step Functions Standard** (`.waitForTaskToken`) | Express can't do callbacks or > 5 min |
| "High-volume short workflows (IoT/streaming), < 5 min" | **Step Functions Express** | |
| "Migrate on-prem app using JMS/AMQP/MQTT with no code change" | **Amazon MQ** (ActiveMQ/RabbitMQ) | |
| "Kafka with no code change" | **Amazon MSK** (or MSK Serverless) | |
| "Point-to-point integration SQS → enrich → target without Lambda" | **EventBridge Pipes** | |
| "Schedule millions of one-time tasks" | **EventBridge Scheduler** | |

### 1K. Analytics & streaming → [Chapter 11](11-Analytics-Streaming-and-AI-ML.md)

| Phrase in the stem | Likely answer | Why / watch-out |
|---|---|---|
| "Ad-hoc SQL on S3, pay per query" | **Athena** (partition + Parquet to cut cost) | |
| "Petabyte data warehouse, complex joins, BI" | **Redshift** (RA3 / Serverless) | |
| "Query S3 from Redshift without loading" | **Redshift Spectrum** | |
| "Spark/Hadoop, custom frameworks" | **EMR** (EMR Serverless for no cluster mgmt) | |
| "Serverless ETL + data catalog" | **AWS Glue** | |
| "Fine-grained (row/column) access to the data lake across accounts" | **Lake Formation** | |
| "Load streaming data into S3/Redshift/OpenSearch with no code" | **Amazon Data Firehose** | |
| "Real-time analytics on streams with SQL/Java" | **Managed Service for Apache Flink** | KDA for SQL shut down Jan 2026 |
| "BI dashboards for business users" | **QuickSight** (now Amazon Quick Suite — "Quick Sight") | |

### 1L. Resilience & DR → [Chapter 12](12-Resilience-HA-and-Disaster-Recovery.md)

| Phrase in the stem | Likely answer | Why / watch-out |
|---|---|---|
| "Near-zero RTO and RPO" | **Multi-site active/active** | Most expensive |
| "RTO minutes, RPO seconds, scaled-down copy running" | **Warm standby** | |
| "RTO tens of minutes/hours, core (DB) replicating, app off" | **Pilot light** | |
| "RTO hours/days, lowest cost" | **Backup and restore** | |
| "Replicate servers block-level to AWS for DR, RPO seconds" | **AWS Elastic Disaster Recovery (DRS)** | |
| "Centrally manage backups across accounts/Regions with policies" | **AWS Backup** + backup policies (Organizations) | |
| "Prove recovery works / test failover regularly" | DR drills, **AWS FIS** (chaos experiments), **Resilience Hub** | |
| "Fail over application across Regions with routing control, independent of a failing Region's control plane" | **Amazon Application Recovery Controller (ARC)** routing controls / Region switch | Data-plane operations for recovery (static stability) |
| "Recover from AZ impairment quickly" | ARC **zonal shift** / zonal autoshift | |
| "Restore DynamoDB to any second in last 35 days" | **PITR** (1–35 day window) | |

### 1M. Migration & modernization → [Chapter 13](13-Migration-and-Modernization.md)

| Phrase in the stem | Likely answer | Why / watch-out |
|---|---|---|
| "Migrate VMs with minimal changes / lift-and-shift at scale" | **MGN** (now **AWS Transform MGN**) | SMS retired 2023 |
| "Discover on-prem servers, dependencies, plan waves" | **AWS Transform** (discovery/assessment); older answer: Application Discovery Service + Migration Hub | ADS & Migration Hub closed to new customers 7 Nov 2025 |
| "Migrate database with minimal downtime" | **DMS** (full load + CDC) | |
| "Heterogeneous DB (Oracle → Aurora PostgreSQL)" | **DMS Schema Conversion** / **SCT** + DMS | |
| "Homogeneous DB using native tools, managed" | **DMS homogeneous data migrations** or native dump/restore, replicas | |
| "VMware workloads, keep VMware tooling" | **Amazon EVS** (Elastic VMware Service) | AWS stopped reselling VMware Cloud on AWS (Apr 2024) |
| "Decompose monolith incrementally" | **Strangler fig** pattern (+ API Gateway / ALB routing, Refactor Spaces) | |
| "Retire / retain / rehost / relocate / repurchase / replatform / refactor" | **7 Rs** | Repurchase = SaaS. Relocate = VMware to EVS/VMC |
| "Move Windows/.NET to Linux containers" | AWS Transform for .NET / App2Container (closed to new customers Nov 2025) | |
| "Mainframe modernisation" | **AWS Transform for mainframe**, Mainframe Modernization (refactor/replatform) | Managed runtime closed to new customers Nov 2025 |
| "Large-scale migration program governance" | AWS **MAP** (assess → mobilize → migrate & modernize) | |
| "Cost estimate before migrating" | **Migration Evaluator** / AWS Transform assessment / Pricing Calculator | |

### 1N. Deployment, DevOps & IaC → [Chapter 14](14-Deployment-DevOps-and-IaC.md)

| Phrase in the stem | Likely answer | Why / watch-out |
|---|---|---|
| "Zero-downtime, instant rollback" | **Blue/green** | |
| "Release to 10% of users first, auto-rollback on alarm" | **Canary** (CodeDeploy, Lambda alias traffic shifting, API GW canary) | |
| "Self-service approved products for developers" | **Service Catalog** (portfolios, constraints, launch roles) | |
| "Define infra in TypeScript/Python" | **AWS CDK** | Synthesizes CloudFormation |
| "Serverless app IaC with simple syntax, local testing" | **AWS SAM** | |
| "Detect manual changes to stacks" | **CloudFormation drift detection** | |
| "Preview changes before update" | **Change sets** | |
| "Prevent stack deletion of a DB" | `DeletionPolicy: Retain/Snapshot` + stack termination protection + stack policy | |

### 1O. Operations & continuous improvement → [Chapter 15](15-Monitoring-Operations-and-Continuous-Improvement.md)

| Phrase in the stem | Likely answer | Why / watch-out |
|---|---|---|
| "Patch fleet of EC2 + on-prem" | **SSM Patch Manager** (patch baselines, maintenance windows) | |
| "Shell access without SSH/bastion/open port 22" | **SSM Session Manager** | Logs to S3/CloudWatch |
| "Run a runbook automatically on alarm/event" | **SSM Automation** via EventBridge | |
| "Trace latency across microservices" | **X-Ray** / CloudWatch Application Signals | |
| "Who deleted the resource?" | **CloudTrail** | |
| "What did the resource look like last Tuesday?" | **AWS Config** (configuration history) | |
| "Centralise logs from all accounts" | CloudWatch Logs cross-account / org-level subscription → Firehose → S3 (log archive) | |
| "Right-size EC2/Lambda/EBS" | **Compute Optimizer** | |

### 1P. Cost → [Chapter 16](16-Cost-Optimization-and-FinOps.md)

| Phrase in the stem | Likely answer | Why / watch-out |
|---|---|---|
| "Steady usage across EC2, Fargate, Lambda; may change family/Region" | **Compute Savings Plan** | |
| "Steady usage, fixed family in one Region, max discount" | **EC2 Instance Savings Plan** (or Standard RI) | |
| "Steady RDS/Aurora/DynamoDB usage, flexible engine/Region" | **Database Savings Plans** (Dec 2025) or RDS RIs | Exam may only know RIs |
| "Stop dev accounts exceeding budget automatically" | **AWS Budgets actions** (apply SCP/IAM policy, stop instances) | |
| "Detect unexpected spend spikes" | **Cost Anomaly Detection** | |
| "Chargeback by team" | Cost allocation tags + **Cost Categories** + CUR 2.0 / Athena | |
| "Reduce NAT gateway data processing cost to S3" | **S3 gateway endpoint** | |
| "Reduce inter-AZ data transfer" | Keep chatty tiers same-AZ where HA allows, VPC endpoints, caching | |
| "Unused EBS volumes, idle instances" | Trusted Advisor / Compute Optimizer / Cost Optimization Hub | |
| "Pay-per-use for spiky API" | API Gateway + Lambda + DynamoDB on-demand | |

---
