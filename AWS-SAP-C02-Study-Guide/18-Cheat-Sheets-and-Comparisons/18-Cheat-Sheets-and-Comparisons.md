# Chapter 18 — Cheat Sheets, Decision Trees & Comparisons
> **Exam mapping:** All domains (D1 26% · D2 29% · D3 25% · D4 20%) | **Weight signal:** High (final-week revision) | **Study time:** ~5 h first pass, then 30–60 min/day until exam day
> [← Previous](../17-Practice-Papers/README.md) · [Index](../00-README-Start-Here.md) · [Next →](../19-Glossary-and-Final-Revision/19-Glossary-and-Final-Revision.md)

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

### 1B. Multi-account & governance → [Chapter 02](../02-Multi-Account-Governance/02-Multi-Account-Governance.md)

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

### 1C. Identity & access → [Chapter 03](../03-Identity-and-Access-Management/03-Identity-and-Access-Management.md)

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

### 1D. Networking & hybrid → [Chapter 04](../04-Networking-VPC-and-Hybrid-Connectivity/04-Networking-VPC-and-Hybrid-Connectivity.md)

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

### 1E. Edge & DNS → [Chapter 05](../05-Edge-DNS-and-Content-Delivery/05-Edge-DNS-and-Content-Delivery.md)

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

### 1F. Security & data protection → [Chapter 06](../06-Security-Data-Protection-and-Threat-Detection/06-Security-Data-Protection-and-Threat-Detection.md)

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

### 1G. Compute & containers → [Chapter 07](../07-Compute-Containers-and-Serverless/07-Compute-Containers-and-Serverless.md)

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

### 1H. Storage & data transfer → [Chapter 08](../08-Storage-and-Data-Transfer/08-Storage-and-Data-Transfer.md)

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

### 1I. Databases & caching → [Chapter 09](../09-Databases-and-Caching/09-Databases-and-Caching.md)

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

### 1J. Integration & event-driven → [Chapter 10](../10-Application-Integration-and-Event-Driven/10-Application-Integration-and-Event-Driven.md)

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

### 1K. Analytics & streaming → [Chapter 11](../11-Analytics-Streaming-and-AI-ML/11-Analytics-Streaming-and-AI-ML.md)

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

### 1L. Resilience & DR → [Chapter 12](../12-Resilience-HA-and-Disaster-Recovery/12-Resilience-HA-and-Disaster-Recovery.md)

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

### 1M. Migration & modernization → [Chapter 13](../13-Migration-and-Modernization/13-Migration-and-Modernization.md)

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

### 1N. Deployment, DevOps & IaC → [Chapter 14](../14-Deployment-DevOps-and-IaC/14-Deployment-DevOps-and-IaC.md)

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

### 1O. Operations & continuous improvement → [Chapter 15](../15-Monitoring-Operations-and-Continuous-Improvement/15-Monitoring-Operations-and-Continuous-Improvement.md)

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

### 1P. Cost → [Chapter 16](../16-Cost-Optimization-and-FinOps/16-Cost-Optimization-and-FinOps.md)

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

## 2. Numbers & limits

> All values checked against AWS documentation in October 2026. **Soft** = default quota you can raise through Service Quotas or Support. **Hard** = fixed. "Exam view" = the older value an exam question may assume. Memorise the **bold** item names first.

### 2A. Serverless & integration

| Item | Value (current) | Soft/Hard | Exam view / note |
|---|---|---|---|
| **Lambda max timeout** | 15 min (900 s) | Hard | Lambda Managed Instances async/ESM can run 90 min (new, not on exam) |
| **Lambda memory** | 128 MB – 10,240 MB (1 vCPU ≈ 1,769 MB) | Hard | CPU scales with memory |
| Lambda `/tmp` | 512 MB – 10,240 MB | Hard | |
| **Lambda concurrency** | 1,000 per Region | **Soft** | New accounts may start lower. Scaling rate: 1,000 execution environments per 10 s per function |
| **Lambda payload** | 6 MB sync (request and response); **1 MB async** | Hard | Exam view async = 256 KB |
| Lambda package | 50 MB zipped upload, 250 MB unzipped (incl. layers); container image 10 GB; 5 layers | Hard | |
| Lambda env vars | 4 KB total | Hard | |
| **API Gateway throttle** | 10,000 RPS + 5,000 burst per account per Region | **Soft** | Lower defaults in some newer Regions |
| **API Gateway integration timeout** | 50 ms – 29 s (REST). Can be raised for **Regional/private REST** APIs (may lower the throttle quota). HTTP API max 30 s. WebSocket 29 s | Soft (REST Regional/private only) | Exam view: hard 29 s → use an async pattern |
| API Gateway payload | 10 MB (REST) | Hard | Larger → S3 presigned URL |
| API Gateway WebSocket | 128 KB message (32 KB frames), 2 h max connection, 10 min idle | Hard | |
| API Gateway cache TTL | Default 300 s, range 0–3,600 s | Hard (max) | |
| **SQS message size** | **1 MiB** (Extended Client → S3 up to 2 GB) | Hard | Exam view 256 KB |
| **SQS retention** | 1 min – 14 days, default 4 days | Hard | |
| SQS visibility timeout | 0 s – 12 h, default 30 s | Hard | |
| SQS delay / long poll | Delay up to 15 min · long poll up to 20 s | Hard | |
| **SQS FIFO throughput** | 300 API calls/s per action (3,000 msg/s with batches of 10); high-throughput mode up to 70,000 TPS in the largest Regions | Soft (HT) | Dedup interval 5 min |
| SQS in-flight | ~120,000 (standard and FIFO) | Soft | |
| **SNS message size** | 256 KiB default, configurable up to **1 MiB** per topic | Hard | Exam view 256 KB |
| SNS subscriptions | 12,500,000 per standard topic; 100 per FIFO topic | Soft | |
| **EventBridge event size** | **1 MB** per PutEvents request | Hard | Exam view 256 KB |
| EventBridge targets / retries | 5 targets per rule; retry up to 24 h / 185 attempts, then DLQ | Hard | |
| EventBridge global endpoints | Failover RTO/RPO ≈ 360 s (max 420 s) | — | |
| **Step Functions duration** | Standard 1 year · **Express 5 min** | Hard | Express: no `.waitForTaskToken`, no `.sync` |
| Step Functions payload / history | 256 KiB per state input/output · 25,000 history events (Standard) | Hard | Store big data in S3, pass a pointer |
| Distributed Map | Up to 10,000 parallel child executions | Hard | |

### 2B. Streaming, NoSQL, relational

| Item | Value (current) | Soft/Hard | Exam view / note |
|---|---|---|---|
| **Kinesis shard write** | 1 MB/s **or** 1,000 records/s | Hard per shard | |
| **Kinesis shard read** | 2 MB/s shared (5 GetRecords/s); **enhanced fan-out 2 MB/s per consumer per shard** | Hard | EFO: up to 20 registered consumers (50 with On-demand Advantage) |
| **Kinesis retention** | 24 h default, up to 365 days | — | |
| Kinesis record size | Up to **10 MiB** | Hard | Exam view 1 MB |
| Kinesis on-demand | Starts at 4 MB/s write; scales automatically (up to 10 GB/s in the largest Regions) | Soft | |
| **DynamoDB item size** | **400 KB** | Hard | Larger → S3 + pointer |
| DynamoDB partition throughput | 3,000 RCU / 1,000 WCU per partition | Hard | Hot keys → write sharding |
| DynamoDB table throughput | 40,000 RCU / 40,000 WCU per table (provisioned and on-demand) | Soft | Account 80k/80k (provisioned) |
| **DynamoDB on-demand** | Instantly handles up to **2× the previous peak** | — | Pre-warm with warm throughput for bigger launches |
| DynamoDB indexes | 20 GSIs (soft) · 5 LSIs (create-time only, hard) | — | |
| DynamoDB transactions | Up to 100 items / 4 MB per transaction | Hard | |
| **DynamoDB PITR** | Restore to any second in a configurable 1–35 day window (latest ≈ 5 min ago); always restores to a new table | — | |
| DynamoDB global tables | MREC: asynchronous (typically ~1 s), last-writer-wins · **MRSC: exactly 3 Regions, RPO 0** | — | |
| **Aurora replicas** | Up to **15** per cluster (16 readers in a global secondary cluster) | Hard | 6 copies of data across 3 AZs |
| **Aurora storage** | Up to **128 TiB** (256 TiB on the newest engine versions) | Hard | |
| **Aurora Global Database** | Up to **10** secondary Regions; replication typically < 1 s; switchover RPO 0; unplanned failover RTO ~1 min | — | Exam view: up to 5 secondary Regions |
| Aurora Serverless v2 | 0 – 256 ACU (0 = auto-pause) | — | v1 end-of-life 31 Mar 2025 |
| Aurora backtrack | Up to 72 h (Aurora MySQL only) | — | Not supported with Global Database |
| **RDS Multi-AZ (instance) failover** | Typically **60–120 s**; synchronous; standby **not readable** | — | |
| RDS Multi-AZ DB cluster | 1 writer + 2 **readable** standbys in 3 AZs, semi-synchronous, faster failover (typically under 35 s) | — | MySQL/PostgreSQL |
| RDS read replicas | Up to 15 per source (engine-dependent) | Soft | Asynchronous; can be cross-Region |
| RDS backups | Automated retention 1–35 days; PITR to ~5 min ago | — | |
| ElastiCache Global Datastore | Up to 2 secondary Regions | Hard | Cross-Region replication typically < 1 s |

### 2C. Storage

| Item | Value (current) | Soft/Hard | Exam view / note |
|---|---|---|---|
| **S3 request rate** | **3,500** PUT/COPY/POST/DELETE and **5,500** GET/HEAD per second **per prefix** | Scales automatically | Spread keys across prefixes; 503 Slow Down while scaling |
| **S3 max object** | **50 TB** (48.8 TiB) via multipart | Hard | Exam view **5 TB** |
| S3 single PUT | 5 GB | Hard | Use multipart above ~100 MB |
| S3 multipart | Up to 10,000 parts; 5 MiB – 5 GiB per part (last part any size) | Hard | |
| S3 consistency | Strong read-after-write for all operations | — | Since Dec 2020 |
| S3 Replication Time Control | Most objects in seconds; 99.99% within 15 min (design target); SLA covers 99.9% within 15 min | — | |
| S3 minimum storage duration | Standard-IA / One Zone-IA 30 days · Glacier Instant & Flexible 90 days · Deep Archive 180 days | — | |
| S3 Glacier retrieval | Flexible: Expedited 1–5 min, Standard 3–5 h, Bulk 5–12 h · Deep Archive: Standard ≤ 12 h, Bulk ≤ 48 h · Glacier Instant: milliseconds | — | |
| **EBS gp3** | Baseline 3,000 IOPS / 125 MiB/s; max **80,000 IOPS / 2,000 MiB/s / 64 TiB** | — | Exam view 16,000 / 1,000 / 16 TiB |
| EBS gp2 | 3 IOPS/GiB, max 16,000 IOPS, 16 TiB, burst credits | — | |
| **EBS io2 Block Express** | Max **256,000 IOPS / 4,000 MiB/s / 64 TiB**, 99.999% durability, sub-ms latency | — | io1: 64,000 IOPS, 16 TiB |
| EBS st1 / sc1 | 500 / 250 MiB/s max; 125 GiB – 16 TiB; not bootable | — | |
| EBS Multi-Attach | io1/io2 only, up to 16 Nitro instances, same AZ | Hard | Needs a cluster-aware file system |

### 2D. Networking & edge

| Item | Value (current) | Soft/Hard | Exam view / note |
|---|---|---|---|
| **VPN tunnel bandwidth** | Up to **1.25 Gbps** per standard tunnel (140k PPS); **Large Bandwidth Tunnel up to 5 Gbps** (TGW/Cloud WAN only) | Hard | 2 tunnels per VPN connection; ECMP only on TGW with BGP |
| VPN MTU | 1,446 bytes (no jumbo frames) | Hard | |
| VPN routes | VGW: 100 BGP routes from the CGW · TGW: 1,000 | Hard | |
| **DX dedicated speeds** | **1, 10, 100, 400 Gbps** | — | MACsec on supported 10/100/400 Gbps ports |
| DX hosted speeds | 50 Mbps – 25 Gbps (via partner); 1 VIF per hosted connection | Hard | |
| **DX VIFs per dedicated connection** | 50 private/public + up to 4 transit (51 total) | Hard | |
| **DX gateway** | Up to **20 VGWs**, **6 TGWs**, 30 VIFs per DXGW; 20 DXGWs per TGW | Hard | |
| DX BGP prefixes | Private/transit VIF: 100 (raise to 1,000 with prefix controls) · Public VIF: 1,000 | Mixed | Over the limit → BGP session goes down |
| DX LAG | Up to 4 connections (< 100G) or 2 (100G), same speed, same location | Hard | |
| **TGW attachments** | **5,000** per TGW | Soft | 5 TGWs per account per Region (soft) |
| **TGW bandwidth** | Up to **100 Gbps per VPC attachment per AZ** (each direction) | Contact AWS | Exam view **50 Gbps** |
| TGW routes / tables | 10,000 routes total · 20 route tables | Soft | MTU 8,500 (VPN 1,500) |
| TGW peering | 50 peering attachments per TGW; static routes only | Soft | |
| TGW route preference | Static (incl. static VPN) > propagated; among propagated: DX gateway > Connect > VPN | — | A BGP VPN route loses to DX; a static VPN route wins |
| NAT gateway | 5 Gbps, auto-scales to 100 Gbps; 55,000 simultaneous connections per unique destination | — | One per AZ for HA |
| **CloudFront origin response timeout** | 1–120 s (default 30 s) | Soft | |
| CloudFront max cacheable object | 50 GB | Hard | |
| **CloudFront Functions** | Sub-ms runtime, 2 MB memory, 10 KB code, viewer events only, no network access | Hard | |
| **Lambda@Edge** | Viewer triggers: **5 s, 128 MB**, 40 KB generated response · Origin triggers: **30 s**, more memory, 1 MB response. Deploy from us-east-1 | Hard | The CloudFront Developer Guide now lists a single 30 s timeout; the General Reference quota table still shows viewer 5 s / 128 MB. Answer with the viewer/origin split |
| Global Accelerator | 2 static anycast IPv4 addresses (plus 2 IPv6 with dual-stack) | — | |

### 2E. Governance, identity, security, compute

| Item | Value (current) | Soft/Hard | Exam view / note |
|---|---|---|---|
| **SCP size / count** | **10,240 characters; up to 10 SCPs per root/OU/account** (raised May 2026) | Hard | **Exam view 5,120 characters, 5 SCPs** |
| RCP size / count | 5,120 characters; 5 per entity (RCPFullAWSAccess counts as 1) | Hard | Current IAM docs evaluate RCPs before SCPs |
| Organizations accounts | Default 10 accounts per organization | **Soft** | Raise via Service Quotas from the management account |
| OU nesting | 5 levels under the root; 2,000 OUs | Hard | |
| Tag / backup / declarative policies | 10,000 characters; 10 per entity | Hard | |
| **IAM managed policy size** | 6,144 characters | Hard | |
| IAM inline policies | Role 10,240 · user 2,048 · group 5,120 characters (aggregate) | Hard | |
| IAM managed policies per role | 20 default, up to 25 | Soft | Exam view 10 (up to 20) |
| Role trust policy | 2,048 characters default, up to 8,192 | Soft | |
| **Role session duration** | 15 min – 12 h (role's max setting); default 1 h; **role chaining max 1 h** | Hard | |
| STS request rate | 600 RPS per account per Region (shared) | Soft | |
| External ID | 2–1,224 characters | Hard | |
| **KMS direct encrypt** | Up to **4 KB** plaintext | Hard | Larger → envelope encryption |
| KMS request quota | Symmetric crypto: 10,000 / 20,000 / 100,000 RPS depending on Region | Soft | Throttling → S3 Bucket Keys, data-key caching |
| Secrets Manager secret | 64 KB | Hard | |
| Parameter Store | Standard 4 KB (10,000 params, free) · Advanced 8 KB (100,000 params, policies, paid) | — | |
| **Spot interruption notice** | **2 minutes** (plus an earlier rebalance recommendation) | — | |
| Savings Plans / RIs (max discount) | Compute SP up to 66% · EC2 Instance SP up to 72% · Standard RI up to 72% · Convertible RI up to 66% · Database SP up to 35% · Spot up to 90% | — | Database SP: 1-year, no upfront |
| CloudWatch metrics | Kept 15 months; high-resolution down to 1 s | — | |
| CloudTrail event history | 90 days of management events, free | — | Longer → trail to S3 |
| Route 53 health checks | Interval 30 s (standard) or 10 s (fast); default failure threshold 3 | — | |

> **Exam technique for numbers.** If an option relies on something that *exceeds* a hard limit (a 20-minute Lambda, a 1 GB DynamoDB item, an Express workflow waiting for human approval, transitive peering), eliminate it immediately. That is usually the point of the distractor.

---

## 3. X vs Y comparison tables

> Each table ends with the **decisive difference** in one line. That line is what the exam tests.

### 3.1 SCP vs RCP vs IAM identity policy vs permissions boundary vs resource policy vs session policy

| | SCP | RCP | Identity policy | Permissions boundary | Resource-based policy | Session policy |
|---|---|---|---|---|---|---|
| Attached to | Root / OU / account | Root / OU / account | User, group, role | User or role | Resource (S3 bucket, KMS key, SQS…) | Passed at AssumeRole/federation |
| Grants access? | **No** (filter only) | **No** (filter only) | Yes | **No** (cap) | Yes (incl. cross-account) | No (cap) |
| Limits | Principals in member accounts (not management account; not service-linked roles) | Resources in member accounts, for supported services (S3, STS, KMS, SQS, Secrets Manager, …) | The principal | The principal | Who can access this resource | That session |
| Typical use | Region lockdown, deny leaving org, protect security tooling | Block external access to org resources (data perimeter) | Normal job permissions | Safe delegation of role creation | Cross-account access, bucket policies | Down-scope a federated session |

**Decisive difference:** SCPs and RCPs are org-level *maximums*; an explicit Deny anywhere wins. Within one account, access needs an Allow in the identity **or** resource policy, and no guardrail blocking it. Cross-account access needs both sides to allow.

### 3.2 Organizations vs Control Tower (vs Landing Zone Accelerator)

| | AWS Organizations | AWS Control Tower | Landing Zone Accelerator (LZA) |
|---|---|---|---|
| What | Account hierarchy, consolidated billing, policies (SCP/RCP/tag/backup/declarative) | Opinionated landing zone built on Organizations: log archive + audit accounts, Account Factory, controls (preventive, detective, proactive), dashboard | Open-source solution deploying a comprehensive, compliance-oriented (e.g., regulated/government) baseline via CDK |
| Effort | You design everything | Pre-built best practice; extend with AFT/CfCT/AFC | Config-file driven; works with or without Control Tower |
| Pick when | Simple org, custom approach, billing only | "Quickly set up a governed multi-account environment" | Strict compliance frameworks, highly customised baselines |

**Decisive difference:** Control Tower = Organizations + automated guardrails + account vending + centralized logging.

### 3.3 Transit Gateway vs VPC peering vs Cloud WAN vs PrivateLink vs VPC Lattice

| | VPC peering | Transit Gateway | Cloud WAN | PrivateLink | VPC Lattice |
|---|---|---|---|---|---|
| Layer | L3 network | L3 hub-and-spoke | L3 global managed WAN | L4 service endpoint | L7 (and TCP) service network |
| Transitive | **No** | Yes | Yes | N/A (one service) | N/A (service-to-service) |
| Overlapping CIDRs | No | No | No | **Yes** | **Yes** |
| Scale | 1:1 (125 peers/VPC max) | 5,000 attachments, Regional (peer for inter-Region) | Multi-Region, segments, policy-as-JSON | Thousands of consumers | Many services/accounts via RAM |
| Cost | Data transfer only | Hourly per attachment + per GB | Core network edge + attachments + per GB | Endpoint hourly + per GB | Per service hourly + per request/GB |
| Pick when | Few VPCs, max throughput, lowest cost | Many VPCs + on-prem in a Region | Global network, central segmentation policy | Expose a service privately, provider/consumer model | Microservices across accounts with IAM auth, no network plumbing |

**Decisive difference:** "transitive / many VPCs" → TGW; "global + policy-based segmentation" → Cloud WAN; "overlapping CIDRs / expose one service" → PrivateLink; "app-layer service-to-service with auth" → Lattice.

### 3.4 Direct Connect vs Site-to-Site VPN (vs VPN over DX)

| | Direct Connect | Site-to-Site VPN | VPN over DX |
|---|---|---|---|
| Path | Private fiber via DX location | Encrypted IPsec over internet | IPsec inside DX (public or transit VIF) |
| Bandwidth | 1/10/100/400 Gbps dedicated; 50 Mbps–25 Gbps hosted | 1.25 Gbps/tunnel (5 Gbps large tunnel) | DX bandwidth, IPsec limits per tunnel |
| Encryption | No (add MACsec or VPN) | Yes | Yes |
| Setup time | Weeks–months | Minutes–hours | Weeks |
| Latency | Consistent | Variable | Consistent |
| HA pattern | 2 connections at 2 locations (max resiliency: 2 devices at each of 2 locations) | 2 tunnels, 2 CGWs | |
| Pick when | Large, steady, latency-sensitive transfers | Fast setup, low cost, DX backup | Compliance needs encryption over DX |

**Decisive difference:** DX = consistent and private but slow to provision and unencrypted; VPN = encrypted and fast to deploy but internet-variable.

### 3.5 DX virtual interface types & connection types

| VIF | Reaches | Via |
|---|---|---|
| Private VIF | VPC private IPs | VGW, or DX gateway → VGWs (up to 20) |
| Public VIF | AWS public endpoints (S3, DynamoDB public IPs, etc.) in all Regions | Directly; use with VPN for encryption |
| Transit VIF | Transit Gateways / Cloud WAN | DX gateway → TGWs (up to 6) |

| | Dedicated connection | Hosted connection |
|---|---|---|
| Ordered from | AWS | DX Partner |
| Speeds | 1/10/100/400 Gbps | 50 Mbps – 25 Gbps |
| VIFs | 50 + 4 transit | 1 |
| MACsec | Supported speeds/locations | No |

### 3.6 Gateway endpoint vs Interface endpoint vs GWLB endpoint

| | Gateway endpoint | Interface endpoint (PrivateLink) | GWLB endpoint |
|---|---|---|---|
| Services | **S3, DynamoDB only** | Most AWS services, partner/own services | Traffic to a Gateway Load Balancer (inspection) |
| Mechanism | Prefix-list route in route table | ENI with private IP in subnet + private DNS | Route-table target |
| Cost | **Free** | Hourly per AZ + per GB | Hourly + per GB |
| Reachable from on-prem / peered VPC | **No** | **Yes** | — |
| Security | Endpoint policy | Endpoint policy + security groups | — |

**Decisive difference:** on-prem or cross-VPC access to S3 → interface endpoint; in-VPC access to S3 at lowest cost → gateway endpoint.

### 3.7 CloudFront vs Global Accelerator

| | CloudFront | Global Accelerator |
|---|---|---|
| Protocols | HTTP/HTTPS, WebSocket, gRPC | TCP and **UDP** |
| Caching | Yes | **No** |
| IPs | Dynamic (Anycast static IPs are an option) | **2 static anycast IPs** |
| Failover | Origin groups (on error codes) | Health-based endpoint failover in seconds, no DNS caching |
| Edge compute | CloudFront Functions, Lambda@Edge | None |
| Pick when | Web content, APIs, video, caching | Gaming, VoIP, IoT, static IP allow-listing, fast Regional failover for non-HTTP |

### 3.8 ALB vs NLB vs GWLB (vs CLB)

| | ALB | NLB | GWLB | CLB |
|---|---|---|---|---|
| Layer | 7 (HTTP/HTTPS/gRPC) | 4 (TCP/UDP/TLS) | 3 (IP, GENEVE 6081) | 4/7 legacy |
| Routing | Path, host, header, query, method | Port | Transparent to appliances | Basic |
| Static IP | No (front with GA or NLB) | **Yes** (EIP per AZ) | — | No |
| Targets | Instances, IPs, **Lambda**, containers | Instances, IPs, **ALB** | Appliance instances/IPs | Instances |
| Extras | WAF, OIDC/Cognito auth, mTLS | PrivateLink provider, preserve source IP, ultra-low latency | Firewall insertion with symmetric flows | Avoid |

**Decisive difference:** content-based routing/WAF/auth → ALB; static IP, UDP, PrivateLink, extreme performance → NLB; inline third-party appliances → GWLB.

### 3.9 RDS Multi-AZ instance vs Multi-AZ DB cluster vs read replica vs Aurora replica

| | Multi-AZ DB instance | Multi-AZ DB cluster | RDS read replica | Aurora replica |
|---|---|---|---|---|
| Purpose | HA | HA + read scale | Read scale, cross-Region DR | Read scale + HA |
| Replication | Synchronous | Semi-synchronous | Asynchronous | Shared storage (ms lag) |
| Readable | **No** | Yes (2 standbys) | Yes | Yes (up to 15) |
| Failover | Automatic, 60–120 s | Automatic, typically < 35 s | Manual promotion | Automatic, priority tiers (~30 s) |
| Cross-Region | No | No | Yes | Via Global Database |

### 3.10 Aurora Global Database vs RDS cross-Region read replica

| | Aurora Global Database | Cross-Region read replica |
|---|---|---|
| Replication | Storage-level, dedicated infra, typically < 1 s | Engine (binlog/WAL) async; lag varies with load |
| Regions | Up to 10 secondaries | Several replicas per source (engine-dependent) |
| Failover | Managed switchover (RPO 0) / failover (RTO ~1 min); global writer endpoint | Manual promotion; repoint app |
| Writes in secondary | Write forwarding | No |
| Pick when | Strict cross-Region RPO/RTO, global reads | Cheaper DR for RDS engines, looser RPO |

### 3.11 DynamoDB global tables vs Aurora Global Database

| | DynamoDB global tables | Aurora Global Database |
|---|---|---|
| Model | NoSQL key-value | Relational SQL |
| Writes | **Active-active in every Region** | Single writer Region (write forwarding from secondaries) |
| Consistency | MREC: eventual, last-writer-wins. MRSC: strong, 3 Regions, RPO 0 | Primary is strongly consistent; secondaries lag < 1 s |
| Failover | None needed (MREC); app routes to any Region | Switchover/failover operation |
| Pick when | Global, always-writable, simple access patterns | Relational/SQL needs, global reads, DR |

### 3.12 DAX vs ElastiCache

| | DAX | ElastiCache (Valkey/Redis OSS/Memcached) |
|---|---|---|
| Works with | **DynamoDB only** (API-compatible, write-through) | Any data source (RDS, APIs, sessions) |
| App change | Swap to DAX client | Cache-aside/write-through logic in code |
| Latency | Microseconds | Sub-millisecond |
| Pick when | Read-heavy DynamoDB, minimal code change | RDS caching, sessions, leaderboards, pub/sub |

### 3.13 SQS vs SNS vs EventBridge vs Kinesis Data Streams vs MSK vs Amazon MQ

| | SQS | SNS | EventBridge | Kinesis Data Streams | MSK | Amazon MQ |
|---|---|---|---|---|---|---|
| Pattern | Queue (pull) | Pub/sub (push) | Event bus, content routing | Ordered stream, replay | Kafka streams | Traditional broker |
| Consumers | One consumer group per message | Many subscribers | Many rules/targets (5 per rule) | Many apps reading same data | Many consumer groups | Queues/topics |
| Ordering | FIFO queues | FIFO topics | No ordering guarantee | Per shard | Per partition | Per queue |
| Retention | Up to 14 days | None (deliver-or-retry) | Archive & replay | 24 h – 365 days | Configurable (tiered storage) | Broker storage |
| Protocols | AWS API | AWS API, HTTP, email, SMS | AWS API, SaaS partners, API destinations | AWS API/KPL | Kafka | JMS, AMQP, MQTT, STOMP, OpenWire |
| Pick when | Decoupling, buffering, work queues | Simple fan-out, notifications | Event-driven routing, SaaS, cross-account | Real-time analytics, replay, multiple readers | Existing Kafka apps | Lift-and-shift of broker apps |

### 3.14 SQS Standard vs SQS FIFO

| | Standard | FIFO |
|---|---|---|
| Throughput | Nearly unlimited | 300 TPS/action (3,000 msg/s batched); high-throughput mode much higher |
| Delivery | At-least-once (occasional duplicates) | **Exactly-once processing** (5-min dedup window) |
| Ordering | Best effort | Strict within message group ID |
| Name | Any | Must end in `.fifo` |
| SNS fan-out | Standard topics | FIFO topics → FIFO queues |

### 3.15 Step Functions Standard vs Express

| | Standard | Express |
|---|---|---|
| Max duration | 1 year | 5 minutes |
| Semantics | Exactly-once execution | At-least-once (async) / at-most-once (sync) |
| History | 90 days in console, 25,000 events | CloudWatch Logs only |
| Callback / `.sync` | Yes | **No** |
| Pricing | Per state transition | Per request + duration/memory |
| Pick when | Long-running, human approval, auditable business processes | High-volume, short (IoT ingestion, streaming transforms, microservice orchestration) |

### 3.16 Kinesis Data Streams vs Amazon Data Firehose vs Managed Service for Apache Flink

| | Kinesis Data Streams | Amazon Data Firehose | Managed Service for Apache Flink |
|---|---|---|---|
| Role | Durable ordered stream store | Delivery pipe to destinations | Stream processing (SQL/Java/Python) |
| Latency | Real-time (~70 ms with EFO) | Near-real-time (buffered) | Real-time |
| Consumers | Custom apps, Lambda, Flink, Firehose | N/A (destination only: S3, Redshift, OpenSearch, Splunk, HTTP, Iceberg) | Reads KDS/MSK |
| Replay | Yes (retention) | No | From source |
| Capacity | Shards or on-demand | Fully automatic | KPUs (auto-scaling) |
| Transform | In consumer | Lambda transform, format conversion to Parquet/ORC | Windowed aggregations, joins |

### 3.17 EBS vs EFS vs FSx vs S3

| | EBS | EFS | FSx for Windows | FSx for Lustre | FSx for NetApp ONTAP | FSx for OpenZFS | S3 |
|---|---|---|---|---|---|---|---|
| Type | Block | File (NFS) | File (SMB) | File (Lustre) | File (NFS/SMB/iSCSI) | File (NFS) | Object |
| Access | One instance (Multi-Attach io1/io2) in one AZ | Thousands of Linux clients, multi-AZ | Windows clients, AD | HPC/ML clients | Mixed clients | Linux clients | HTTP API |
| Scope | AZ | Regional (or One Zone) | Single/Multi-AZ | Single AZ | Single/Multi-AZ | Single/Multi-AZ | Regional |
| Key feature | Lowest latency for one host | Elastic, pay per use | DFS, AD, shadow copies | S3 data repository link, 100s GB/s | Snapshots, SnapMirror, dedup, multi-protocol | Snapshots, clones, low latency | 11 nines, lifecycle, unlimited |

### 3.18 S3 storage classes (cheat sheet)

| Class | Access | AZs | Min duration | Retrieval |
|---|---|---|---|---|
| Standard | Frequent | ≥3 | — | ms |
| Intelligent-Tiering | Unknown/changing | ≥3 | — (monitoring fee) | ms (archive tiers optional) |
| Standard-IA | Infrequent | ≥3 | 30 days | ms + per-GB fee |
| One Zone-IA | Infrequent, re-creatable | 1 | 30 days | ms + per-GB fee |
| Express One Zone | Ultra-low latency, single AZ, directory buckets | 1 | — | single-digit ms |
| Glacier Instant Retrieval | Quarterly, needs ms | ≥3 | 90 days | ms |
| Glacier Flexible Retrieval | Yearly | ≥3 | 90 days | 1–5 min / 3–5 h / 5–12 h |
| Glacier Deep Archive | Rare, compliance | ≥3 | 180 days | ≤ 12 h / ≤ 48 h |

### 3.19 Storage Gateway types

| Type | Protocol on-prem | Backed by | Use |
|---|---|---|---|
| S3 File Gateway | NFS / SMB | S3 objects (one file = one object) | File shares into S3, data lake ingest, backups |
| FSx File Gateway | SMB | FSx for Windows | Low-latency on-prem cache of FSx shares (**closed to new customers Oct 2024**) |
| Volume Gateway — cached | iSCSI | S3 (primary data), local cache | Expand on-prem storage |
| Volume Gateway — stored | iSCSI | Local primary, async snapshots to S3 (EBS snapshots) | Low-latency full local dataset with cloud backup |
| Tape Gateway | iSCSI VTL | S3 → Glacier/Deep Archive | Replace physical tapes with existing backup software |

### 3.20 DataSync vs Transfer Family vs Snow vs DMS vs S3 Transfer Acceleration

| | DataSync | Transfer Family | Snowball Edge | DMS | S3 Transfer Acceleration |
|---|---|---|---|---|---|
| Moves | Files/objects (NFS, SMB, HDFS, object, other clouds) | Files via SFTP/FTPS/FTP/AS2 | Bulk data offline | Database rows (full load + CDC) | Objects to S3 over long distance |
| Online? | Yes (agent) | Yes | **No** (shipped device) | Yes | Yes |
| Typical | One-time migration or scheduled sync, with verification | Partners keep SFTP clients | Hundreds of TB with poor bandwidth | Database migration with minimal downtime | Global uploads to one bucket |
| Note | Encrypts in transit, bandwidth throttling | Managed endpoints, custom IdP | Closed to new customers (Nov 2025) → Data Transfer Terminal / DataSync | Pair with SCT/DMS Schema Conversion | Uses CloudFront edge |

### 3.21 MGN vs DRS vs AWS Backup

| | AWS Transform MGN (Application Migration Service) | Elastic Disaster Recovery (DRS) | AWS Backup |
|---|---|---|---|
| Purpose | **Migrate** servers (rehost) | **DR** for servers into AWS (and failback) | Policy-based **backup** of AWS resources |
| Mechanism | Continuous block replication → test → cutover | Continuous block replication → staging → launch on drill/failover | Scheduled snapshots/backups, cross-account/Region copy |
| RPO / RTO | N/A (one-time cutover) | RPO seconds, RTO minutes | RPO = backup frequency; RTO = restore time (hours) |
| Pick when | "Migrate VMs with minimal changes" | "DR for on-prem or EC2 servers, low RPO, low cost" | "Central backup compliance across accounts" |

### 3.22 Secrets Manager vs SSM Parameter Store

| | Secrets Manager | Parameter Store |
|---|---|---|
| Rotation | **Built-in** (RDS, Redshift, DocumentDB; Lambda for custom) | None built in |
| Cross-account | Resource policy | Advanced parameters can be shared via RAM |
| Multi-Region | Replica secrets | No |
| Size | 64 KB | 4 KB standard / 8 KB advanced |
| Cost | Per secret per month + API calls | Standard free; advanced paid |
| Pick when | Credentials needing rotation | Config, feature flags, cheap encrypted strings |

### 3.23 KMS vs CloudHSM

| | AWS KMS | AWS CloudHSM |
|---|---|---|
| Tenancy | Multi-tenant managed service (FIPS 140-3 Level 3 HSMs) | **Single-tenant** HSM cluster in your VPC |
| Key control | AWS manages HSMs; you control policies | **You** own users and keys; AWS can't access |
| Integration | Native with almost all AWS services | Via KMS custom key store, or PKCS#11/JCE/CNG apps |
| Ops | None | Cluster sizing, HA across AZs, backups |
| Pick when | Default for encryption at rest | Contractual sole control, SSL offload, Oracle TDE, custom crypto |

Related: **XKS** = keys in an external HSM outside AWS. **Multi-Region keys** = same key material in several Regions. **Imported key material** = you supply material, can set expiry.

### 3.24 GuardDuty vs Inspector vs Macie vs Detective vs Security Hub vs Config

| Service | Answers the question | Data source |
|---|---|---|
| GuardDuty | "Is something malicious happening?" | CloudTrail, VPC Flow Logs, DNS logs, EKS/RDS/S3/Lambda/runtime signals |
| Inspector | "Which workloads have CVEs or network exposure?" | EC2 (SSM agent or agentless), ECR images, Lambda code |
| Macie | "Where is sensitive data (PII) in S3?" | S3 objects |
| Detective | "What happened and what is the blast radius?" | Behaviour graph from GuardDuty, CloudTrail, Flow Logs |
| Security Hub (CSPM) | "What is our overall posture against CIS/FSBP, all findings in one place?" | Findings from the above plus partners (ASFF) |
| AWS Config | "Is this resource configured compliantly, and what changed?" | Resource configuration recordings |

### 3.25 CloudTrail vs Config vs CloudWatch

| | CloudTrail | AWS Config | CloudWatch |
|---|---|---|---|
| Records | **API calls** (who, what, when, from where) | **Resource configuration state** and history | **Metrics, logs, alarms**, dashboards |
| Question | "Who terminated the instance?" | "Was the SG open last week? Is it compliant now?" | "Is CPU high? Alarm and scale" |
| Org-wide | Organization trail | Aggregator, conformance packs | Cross-account observability |

### 3.26 Savings Plans vs Reserved Instances

| | Compute SP | EC2 Instance SP | Standard RI | Convertible RI | Database SP |
|---|---|---|---|---|---|
| Max discount | ~66% | ~72% | ~72% | ~66% | ~35% |
| Flexibility | Any family, size, Region, OS, tenancy; EC2 + Fargate + Lambda | Size/OS/tenancy within one family in one Region | Fixed attributes (size flexible for Linux regional) | Exchange for other attributes | Any supported DB engine, instance family, Region (serverless + provisioned) |
| Capacity reservation | No | No | Zonal RI only | Zonal RI only | No |
| Sell on Marketplace | No | No | Yes | No | No |

### 3.27 On-Demand vs Spot vs Capacity Reservations vs Dedicated

| | On-Demand | Spot | On-Demand Capacity Reservation | Dedicated Instances | Dedicated Hosts |
|---|---|---|---|---|---|
| Cost | Baseline | Up to 90% off | On-Demand price (combine with SP/RI for discount) | Premium | Premium per host |
| Interruptible | No | **Yes (2-min notice)** | No | No | No |
| Capacity guaranteed | No | No | **Yes (specific AZ)** | No | Yes (host) |
| Pick when | Short, unpredictable | Stateless, fault-tolerant, flexible | DR / events / regulatory capacity | Isolated hardware | BYOL per core/socket, host affinity |

### 3.28 CloudFormation vs CDK vs SAM vs Service Catalog (vs StackSets)

| | CloudFormation | CDK | SAM | Service Catalog | StackSets |
|---|---|---|---|---|---|
| What | Declarative YAML/JSON IaC | Imperative code → CloudFormation | Serverless shorthand → CloudFormation | Governed self-service portfolio of approved products | Deploy one template to many accounts/Regions |
| Audience | Platform teams | Developers | Serverless developers | End users without broad IAM | Central platform/security teams |
| Key feature | Drift detection, change sets, stack policies | Constructs, loops, testing | `sam local`, Globals | Launch constraints (launch role), TagOptions | Service-managed permissions, auto-deploy to new accounts |

### 3.29 Deployment strategies

| Strategy | Downtime | Rollback | Cost | Notes |
|---|---|---|---|---|
| All at once (in-place) | Yes | Redeploy | Lowest | Dev only |
| Rolling | No (reduced capacity) | Slow redeploy | Low | |
| Rolling with additional batch | No (full capacity) | Slow | Low+ | Elastic Beanstalk option |
| Immutable | No | Fast (terminate new ASG) | Double during deploy | New instances in new ASG |
| Blue/green | No | **Instant** (switch back) | Double | Route 53 weighted, ALB target groups, CodeDeploy, ECS |
| Canary | No | Fast, small blast radius | Low | e.g., 10% for 5 min then 100% |
| Linear | No | Fast | Low | e.g., +10% every minute |
| Traffic splitting (EB) | No | Fast | Medium | Canary for Elastic Beanstalk |

### 3.30 Cognito user pools vs identity pools

| | User pool | Identity pool |
|---|---|---|
| Purpose | **Authentication** (sign-up/sign-in, MFA, hosted UI, social/SAML/OIDC federation) | **Authorization to AWS** (temporary IAM credentials) |
| Output | JWT tokens (ID, access, refresh) | AWS credentials via STS |
| Use with | API Gateway/ALB authorizers, apps | Direct S3/DynamoDB access from the client, guest access |

### 3.31 IAM Identity Center vs IAM SAML federation vs IAM users

| | IAM Identity Center | IAM SAML/OIDC federation (per account) | IAM users |
|---|---|---|---|
| Scope | All accounts in the org, central | One account per IdP config | One account |
| Permissions | Permission sets → roles provisioned in each account | Roles you create per account | Policies on users |
| Provisioning | SCIM from IdP; ABAC attributes | Manual | Manual |
| Pick when | Workforce multi-account access (default answer) | Single account, legacy, or app-specific needs | Break-glass / exceptional programmatic cases |

### 3.32 AWS Managed Microsoft AD vs AD Connector vs Simple AD

| | Managed Microsoft AD | AD Connector | Simple AD |
|---|---|---|---|
| What | Real Windows Server AD run by AWS (2 DCs, multi-AZ) | **Proxy** to on-prem AD, no directory data in AWS | Samba-based basic AD-compatible directory |
| Trusts with on-prem | Yes (forest/external trusts) | N/A (uses on-prem AD directly) | No |
| Schema extensions, GPO, MFA | Yes | Uses on-prem features; RADIUS MFA | Limited |
| Multi-Region / sharing | Multi-Region replication (Enterprise), share across accounts | No | No |
| Pick when | AD-aware apps in AWS, FSx for Windows, RDS SQL Server Windows auth | Use existing on-prem AD for WorkSpaces/console/Identity Center, no sync | Small, basic needs — **closed to new customers (2026)**; AWS points to Managed AD or AD Connector |

### 3.33 Lambda vs Fargate vs EC2 (vs ECS Express Mode)

| | Lambda | Fargate (ECS/EKS) | EC2 |
|---|---|---|---|
| Max run time | 15 min | Unlimited | Unlimited |
| Scaling | Per request, ms | Per task, seconds–minutes | ASG, minutes |
| Control | None of OS | Container | Full OS, GPUs, special hardware |
| Cost model | Per request + GB-s | Per vCPU/GB-s of task | Per instance-second (SP/RI/Spot) |
| Pick when | Event-driven, spiky, short | Long-running containers without servers | Specialised hardware, licensing, steady high utilisation |

ECS Express Mode (2025) = container image + IAM roles → ECS service on Fargate behind an ALB with scaling: AWS's suggested replacement for App Runner.

### 3.34 ECS vs EKS

| | ECS | EKS |
|---|---|---|
| Orchestrator | AWS-native | Kubernetes (CNCF conformant) |
| Learning curve | Lower | Higher |
| Portability | AWS-specific | Multi-cloud/on-prem (EKS Anywhere, Hybrid Nodes) |
| Control plane cost | None | Per cluster hour |
| Pick when | "Least operational overhead", AWS-only | Existing K8s skills/tooling, Helm, operators |

### 3.35 Athena vs Redshift vs EMR (vs Glue)

| | Athena | Redshift | EMR | Glue |
|---|---|---|---|---|
| Model | Serverless SQL on S3 | MPP data warehouse (provisioned RA3 or Serverless) | Managed Hadoop/Spark/Presto clusters (or Serverless, on EKS) | Serverless Spark ETL + Data Catalog |
| Best for | Ad-hoc queries, logs | Repeated complex BI on structured data, high concurrency | Custom big-data frameworks, full control | ETL pipelines, catalog, crawlers |
| Cost | Per TB scanned (or capacity) | Per node-hour / RPU-hour | Per instance-hour | Per DPU-hour |

### 3.36 WAF vs Shield vs Network Firewall vs Security Groups vs NACLs vs Firewall Manager

| | AWS WAF | Shield Standard | Shield Advanced | Network Firewall | Security group | NACL | Firewall Manager |
|---|---|---|---|---|---|---|---|
| Layer | L7 | L3/L4 | L3/L4/L7 | L3–L7 (stateful, IPS, domain filtering) | L4 instance/ENI | L4 subnet | Central policy manager |
| State | — | — | — | Stateful + stateless | **Stateful** | **Stateless** | — |
| Rules | Allow/block/count/CAPTCHA, managed rules, rate-based | Automatic | DRT/SRT, cost protection, health-based detection | Suricata rules, TLS inspection | Allow only | Allow and **deny**, numbered order | Deploys WAF, Shield, SG, Network Firewall, DNS Firewall policies org-wide |
| Attach to | CloudFront, ALB, API GW, AppSync, Cognito, App Runner, Verified Access | All | CloudFront, Route 53 hosted zones, Global Accelerator, ALB, CLB, Elastic IPs (e.g., EC2, NLB) | VPC (firewall endpoints in subnets) | ENIs | Subnets | Organization |

**Decisive difference:** block a specific IP fast → NACL deny (SGs can't deny) or WAF IP set; SQLi/XSS → WAF; VPC-wide egress domain filtering/IPS → Network Firewall.

### 3.37 Route 53 routing policies

| Policy | Use |
|---|---|
| Simple | One record, no health checks (multiple values returned randomly) |
| Weighted | A/B, gradual migration, blue/green |
| Latency | Lowest latency Region |
| Failover | Active-passive with health checks |
| Geolocation | By continent/country/state (compliance, localisation); define a default |
| Geoproximity | By distance with bias (Traffic Flow) |
| Multivalue answer | Up to 8 healthy records, client-side load spreading |
| IP-based | By client CIDR (e.g., ISP-specific routing) |

### 3.38 Route 53 Resolver inbound vs outbound endpoints (hybrid DNS)

| | Inbound endpoint | Outbound endpoint |
|---|---|---|
| Direction | On-prem → AWS | AWS → on-prem |
| Use | On-prem resolves private hosted zones / VPC names | VPC resources resolve `corp.example.com` |
| Config | On-prem DNS conditional forwarders → endpoint IPs | Forwarding rules (share via RAM to other accounts' VPCs) |

Also: **Route 53 Resolver DNS Firewall** filters outbound DNS queries (block known-bad domains). **Profiles** share DNS settings across VPCs/accounts.

### 3.39 DR strategies

| Strategy | RPO | RTO | Running in DR Region | Cost |
|---|---|---|---|---|
| Backup & restore | Hours | Hours–days (24 h typical) | Backups only | $ |
| Pilot light | Minutes | Tens of minutes–hours | Data replication; core infra off/minimal | $$ |
| Warm standby | Seconds–minutes | Minutes | Full stack scaled down, serving or ready | $$$ |
| Multi-site active/active | Near zero | Near zero | Full stack serving traffic | $$$$ |

### 3.40 AWS Backup vs native snapshots vs Data Lifecycle Manager

| | AWS Backup | Native snapshots/backups | Amazon Data Lifecycle Manager |
|---|---|---|---|
| Scope | Many services (EC2, EBS, RDS, Aurora, DynamoDB, EFS, FSx, S3, Storage Gateway, more) | One service each | EBS snapshots and EBS-backed AMIs |
| Org-wide policies | **Yes** (backup policies) | No | No |
| Cross-account/Region copy | Yes | Manual/per service | Cross-Region copy, cross-account share |
| Immutability | **Vault Lock** (governance/compliance), logically air-gapped vaults | No | No |

### 3.41 ElastiCache Valkey/Redis OSS vs Memcached

| | Valkey / Redis OSS | Memcached |
|---|---|---|
| Data types | Rich (lists, sets, sorted sets, streams) | Strings |
| Persistence / backup | Snapshots, AOF (engine-dependent) | No |
| Replication / failover | Replicas, Multi-AZ, Global Datastore | No |
| Threads | Mostly single-threaded per shard (cluster mode for scale) | Multi-threaded |
| Pick when | HA cache, sessions, leaderboards, pub/sub | Simple, horizontally scaled, disposable cache |

### 3.42 Systems Manager capabilities

| Capability | Does |
|---|---|
| Session Manager | Browser/CLI shell, no SSH/bastion, audited |
| Run Command | Run scripts across fleets on demand |
| State Manager | Keep instances in a defined state on a schedule |
| Patch Manager | Patch baselines + maintenance windows (EC2 + on-prem) |
| Automation | Runbooks (e.g., AMI baking, remediation, start/stop) |
| Parameter Store | Config/secrets storage |
| Inventory / Compliance | Software inventory, patch/association compliance |
| Distributor | Package distribution |
| Fleet Manager | Remote management console |

(Incident Manager and Change Manager closed to new customers Nov 2025.)

### 3.43 Observability: CloudWatch vs X-Ray vs Managed Prometheus/Grafana

| | CloudWatch | X-Ray / Application Signals | Amazon Managed Service for Prometheus + Managed Grafana |
|---|---|---|---|
| Signals | Metrics, logs, alarms, dashboards, Synthetics, RUM | Distributed traces, service maps | Prometheus metrics (containers/K8s), Grafana dashboards |
| Pick when | Default AWS monitoring | Latency root-cause across microservices | Existing Prometheus/Grafana practice, EKS |

X-Ray SDKs/daemon are in maintenance (Feb 2026); instrument with **AWS Distro for OpenTelemetry (ADOT)**.

### 3.44 S3 encryption options

| Option | Keys managed by | Audit of key use | Notes |
|---|---|---|---|
| SSE-S3 | S3 | No | Default for all new objects |
| SSE-KMS | KMS (AWS managed or customer managed) | **Yes** (CloudTrail) | Key policy control, cross-account needs CMK; Bucket Keys cut cost |
| DSSE-KMS | KMS, two layers | Yes | Dual-layer for compliance |
| SSE-C | Customer supplies key on each request | No | HTTPS required; S3 doesn't store key |
| Client-side | Customer | Customer | Data encrypted before upload |

### 3.45 The 7 Rs of migration

| R | Meaning | Example tool/approach |
|---|---|---|
| Retire | Decommission | Discovery shows no usage |
| Retain | Keep on-prem for now | Recent upgrade, compliance, latency |
| Rehost | Lift-and-shift | MGN |
| Relocate | Move hypervisor-level, no changes | VMware → Amazon EVS |
| Repurchase | Move to SaaS | CRM → SaaS product |
| Replatform | Lift-tinker-shift | DB → RDS, app → Elastic Beanstalk/containers |
| Refactor / re-architect | Rebuild cloud-native | Microservices, serverless |

### 3.46 DMS vs SCT / DMS Schema Conversion

| | DMS (replication) | SCT / DMS Schema Conversion |
|---|---|---|
| Moves | Data (full load, CDC) | Schema, code objects (procedures, views) |
| Needed for | Homogeneous and heterogeneous | **Heterogeneous** only (e.g., Oracle → PostgreSQL) |
| Deployment | Replication instance or DMS Serverless | SCT desktop app, or managed DMS Schema Conversion in console |

### 3.47 Cost tools

| Tool | Use |
|---|---|
| Cost Explorer | Visualise/forecast, RI/SP recommendations and utilisation/coverage |
| AWS Budgets | Thresholds + alerts + **actions** |
| CUR 2.0 / Data Exports | Line-item billing data to S3 for Athena/QuickSight |
| Cost Anomaly Detection | ML-detected spend spikes |
| Cost Categories / cost allocation tags | Group costs for chargeback (split charges) |
| Billing Conductor | Pro forma billing / custom rates for resellers and chargeback |
| Compute Optimizer | Right-size EC2, ASG, EBS, Lambda, ECS on Fargate, RDS |
| Trusted Advisor / Cost Optimization Hub | Idle and underused resources, consolidated recommendations |

### 3.48 Protecting S3 content behind CloudFront

| Mechanism | Purpose |
|---|---|
| OAC (Origin Access Control) | Only CloudFront can read the bucket; supports SSE-KMS, all Regions, PUT/DELETE. **Use this** |
| OAI (Origin Access Identity) | Legacy predecessor of OAC |
| Signed URLs | Restrict access to individual files, RTMP-like single-object links |
| Signed cookies | Restrict access to many files without changing URLs |
| Geo restriction | Allow/deny by country |
| Field-level encryption | Encrypt specific POST fields at edge |

### 3.49 Ordering & exactly-once: SQS FIFO vs Kinesis vs DynamoDB Streams

| | SQS FIFO | Kinesis Data Streams | DynamoDB Streams |
|---|---|---|---|
| Order scope | Message group | Shard (partition key) | Item (per partition key) |
| Duplicates | Exactly-once processing (dedup) | At-least-once (consumer must be idempotent) | Exactly once in stream, records appear once |
| Retention | Up to 14 days | 24 h – 365 days | 24 h |
| Multiple consumers | One logical consumer | Many | Up to 2 readers per shard recommended |

---

## 4. Decision trees

> Read top to bottom. The first "yes" usually wins. Then sanity-check cost and operational overhead against the stem.

### 4.1 Choose a DR strategy (by RTO / RPO)

```text
START: What are the RTO and RPO?
│
├─ RPO ≈ 0 and RTO ≈ 0 (no visible outage, writes in 2+ Regions)?
│     └─ YES → MULTI-SITE ACTIVE/ACTIVE
│              data: DynamoDB global tables (MRSC if RPO must be 0) / Aurora Global + write forwarding
│              traffic: Route 53 latency/weighted + health checks, or Global Accelerator
│              recovery control: ARC routing controls / Region switch
│
├─ RTO minutes, RPO seconds?
│     └─ YES → WARM STANDBY
│              scaled-down full stack in DR Region, Aurora Global / DynamoDB global tables,
│              scale out ASG/ECS on failover (pre-provisioned capacity → static stability)
│
├─ RTO tens of minutes to a few hours, RPO minutes?
│     └─ YES → PILOT LIGHT
│              data replicated continuously (Aurora Global, cross-Region replicas, S3 CRR),
│              app tier as AMIs/IaC, launched on failover. For servers: Elastic Disaster Recovery (DRS)
│
└─ RTO hours–days, RPO hours acceptable, lowest cost?
      └─ YES → BACKUP & RESTORE
               AWS Backup with cross-Region (and cross-account) copy, Vault Lock,
               IaC to rebuild, test restores regularly
```

Exam add-ons: "on-prem servers to AWS for DR" → **DRS**. "Must survive compromise of the production account" → cross-**account** backup copy + Vault Lock. "Prove it works" → scheduled DR drills, FIS, Resilience Hub.

### 4.2 Choose a database

```text
START: What is the data model and access pattern?
│
├─ Relational (joins, transactions, SQL)?
│   ├─ Need multi-Region DR with RPO ~1 s / global reads?  → Aurora Global Database
│   ├─ Unpredictable or intermittent load / scale to zero? → Aurora Serverless v2
│   ├─ Need commercial engine features (Oracle/SQL Server) or OS access?
│   │       → RDS for Oracle/SQL Server (RDS Custom for OS access)
│   ├─ Write scale beyond one writer, PostgreSQL?          → Aurora Limitless Database (sharded)
│   ├─ Serverless distributed SQL, active-active multi-Region? → Aurora DSQL (emerging, not core)
│   └─ Otherwise                                           → Aurora (MySQL/PostgreSQL) or RDS Multi-AZ
│
├─ Key-value / document at any scale, single-digit ms?
│   ├─ Global active-active writes?                        → DynamoDB global tables
│   ├─ Microsecond reads?                                  → + DAX
│   └─ MongoDB API compatibility?                          → DocumentDB
│
├─ In-memory?
│   ├─ Cache in front of a DB / sessions?                  → ElastiCache (Valkey/Redis OSS; Memcached for simple)
│   └─ Durable primary in-memory DB?                       → MemoryDB
│
├─ Relationships / graph traversal?                        → Neptune
├─ Time-series?                                            → Timestream for InfluxDB
├─ Wide-column, Cassandra (CQL)?                           → Keyspaces
├─ Full-text search / log analytics?                       → OpenSearch Service
├─ Analytics / data warehouse (OLAP)?                      → Redshift (or Athena on S3)
└─ Immutable ledger?                                       → (QLDB retired 2025) Aurora PostgreSQL with audit/history tables
```

### 4.3 Choose storage

```text
START: How will the data be accessed?
│
├─ Block device for one EC2 instance?
│   ├─ Very high IOPS, sub-ms, 99.999% durability?   → EBS io2 Block Express
│   ├─ General purpose (boot, most DBs)?              → EBS gp3
│   ├─ Large sequential throughput, cheap?            → st1 (cold → sc1)
│   └─ Temporary scratch, highest speed, data loss OK? → Instance store
│
├─ Shared file system?
│   ├─ Linux, NFS, elastic, multi-AZ?                 → EFS (One Zone for cheaper dev)
│   ├─ Windows SMB, AD, DFS?                          → FSx for Windows File Server
│   ├─ HPC/ML, hundreds of GB/s, S3-linked?           → FSx for Lustre
│   ├─ NetApp features / multi-protocol / SnapMirror? → FSx for NetApp ONTAP
│   └─ ZFS migration, low-latency NFS?                → FSx for OpenZFS
│
├─ Object storage (HTTP API, unlimited, lifecycle)?
│   ├─ Known frequent access                          → S3 Standard
│   ├─ Unknown pattern                                → S3 Intelligent-Tiering
│   ├─ Infrequent, ms access                          → Standard-IA (re-creatable: One Zone-IA)
│   ├─ Archive, ms access                             → Glacier Instant Retrieval
│   ├─ Archive, minutes–hours                         → Glacier Flexible Retrieval
│   ├─ Archive, ≤ 12–48 h, cheapest                   → Glacier Deep Archive
│   └─ Single-digit-ms, same-AZ compute               → S3 Express One Zone
│
└─ On-prem apps need cloud storage?
    ├─ NFS/SMB → S3                                   → S3 File Gateway
    ├─ iSCSI block                                    → Volume Gateway (cached/stored)
    └─ Backup software with tapes                     → Tape Gateway
```

### 4.4 Choose hybrid connectivity

```text
START: What does on-prem need?
│
├─ Connectivity needed within days, or a backup path?
│     └─ Site-to-Site VPN (2 tunnels; BGP; on TGW for many VPCs)
│          └─ > 1.25 Gbps? → ECMP across tunnels on TGW, or Large Bandwidth Tunnels (5 Gbps)
│
├─ Consistent latency / high throughput / lower data-transfer-out cost?
│     └─ Direct Connect
│          ├─ Need < 1 Gbps or fast provisioning via partner?  → Hosted connection
│          ├─ Reach VPCs in many Regions/accounts?             → DX gateway
│          │     ├─ Many VPCs with transitive needs?           → Transit VIF → DXGW → TGW
│          │     └─ Few VPCs                                   → Private VIF → DXGW → VGWs
│          ├─ Reach public AWS endpoints (S3 public IPs)?      → Public VIF
│          ├─ Must be encrypted?                               → MACsec (L2) or IPsec VPN over DX
│          └─ Resiliency?
│                ├─ Critical prod: 2 locations × 2 connections (maximum resiliency)
│                ├─ High: 1 connection at each of 2 locations
│                └─ Dev/test or budget: 1 DX + VPN backup
│
├─ Access S3/other AWS services privately from on-prem?
│     └─ Interface endpoints (PrivateLink) over DX/VPN (gateway endpoints don't work from on-prem)
│
├─ DNS across both sides?
│     ├─ On-prem resolves AWS private zones → Resolver INBOUND endpoint
│     └─ AWS resolves on-prem names         → Resolver OUTBOUND endpoint + rules (share via RAM)
│
└─ Many branch offices, SD-WAN, global?
      └─ Cloud WAN (or TGW Connect with GRE/BGP for SD-WAN appliances)
```

### 4.5 Choose a migration tool

```text
START: What are you moving?
│
├─ Discovery & planning (what do we have, dependencies, waves, TCO)?
│     └─ AWS Transform (assessment/discovery), Migration Evaluator
│        (Application Discovery Service + Migration Hub on older exams; closed to new customers Nov 2025)
│
├─ Whole servers / VMs, minimal change?
│     ├─ Physical, VMware, Hyper-V, other clouds → AWS Transform MGN (Application Migration Service)
│     └─ Entire VMware estate, keep VMware tools → Amazon EVS
│
├─ Databases?
│     ├─ Same engine → DMS (or DMS homogeneous migrations / native tools)
│     ├─ Different engine → DMS Schema Conversion or SCT + DMS
│     └─ Minimal downtime → DMS full load + CDC, then cutover
│
├─ Files?
│     ├─ Online NFS/SMB/HDFS/object, TB scale, verified → DataSync
│     ├─ Partners push via SFTP/FTPS/AS2               → Transfer Family
│     └─ Hybrid ongoing access (not one-time)          → Storage Gateway
│
├─ Huge datasets, little bandwidth (weeks to copy online)?
│     └─ Offline: Snowball Edge (existing customers) / AWS Data Transfer Terminal
│
├─ Applications to containers?
│     └─ AWS Transform (for .NET, VMware), App2Container (legacy answer)
│
└─ Mainframe?
      └─ AWS Transform for mainframe, AWS Mainframe Modernization (refactor/replatform)
```

### 4.6 Choose messaging / integration

```text
START: What is the communication pattern?
│
├─ One producer → one worker pool, buffer load, retries?
│     ├─ Strict order or no duplicates?  → SQS FIFO
│     └─ Otherwise                       → SQS Standard (+ DLQ)
│
├─ One message → many subscribers?
│     ├─ Simple fan-out, push (email/SMS/HTTP/SQS/Lambda) → SNS (often SNS → SQS)
│     └─ Content-based routing, SaaS sources, cross-account, schema registry → EventBridge
│
├─ High-volume ordered stream, multiple readers, replay?
│     ├─ AWS-native                      → Kinesis Data Streams
│     ├─ Existing Kafka                  → MSK
│     └─ Just land it in S3/Redshift     → Amazon Data Firehose
│
├─ Existing JMS/AMQP/MQTT/STOMP apps?    → Amazon MQ
│
├─ Multi-step process with state, retries, branching?
│     ├─ Long-running / human approval / exactly-once → Step Functions Standard
│     └─ High-volume < 5 min                          → Step Functions Express
│
└─ Point-to-point source → filter/enrich → target, no code? → EventBridge Pipes
   Scheduled one-time or recurring invocations?            → EventBridge Scheduler
```

### 4.7 Choose compute

```text
START: What does the workload look like?
│
├─ Event-driven, < 15 min, spiky?          → Lambda (+ provisioned concurrency if latency-critical)
│
├─ Containerised?
│   ├─ Want no servers?                     → Fargate (ECS or EKS)
│   │     └─ Simplest "image → HTTPS URL"   → ECS Express Mode (App Runner on older exams)
│   ├─ Kubernetes required?                 → EKS (managed node groups / Karpenter / Fargate / Auto Mode)
│   └─ Need GPUs, daemon sets, max cost control → ECS/EKS on EC2 (Spot where tolerant)
│
├─ Batch jobs?
│   └─ AWS Batch (Spot + On-Demand compute environments); Step Functions for orchestration
│
├─ Traditional server app / full OS control / special licensing?
│   ├─ BYOL per socket/core               → Dedicated Hosts
│   ├─ Steady 24×7                        → EC2 + Savings Plans
│   ├─ Fault-tolerant, flexible           → EC2 Spot (diversified, price-capacity-optimized)
│   └─ Need guaranteed AZ capacity        → On-Demand Capacity Reservations
│
├─ HPC, tightly coupled?                  → Cluster placement group + EFA (+ FSx for Lustre, ParallelCluster)
│
└─ Ultra-low latency to end users / on-prem?
      ├─ Metro areas                      → Local Zones
      ├─ 5G mobile edge                   → Wavelength
      └─ On-premises data residency       → Outposts
```

### 4.8 Bonus: choose a cross-account access mechanism

```text
Human users across many accounts?          → IAM Identity Center (permission sets)
Third party / vendor?                      → Cross-account role + External ID
AWS service in account A → resource in B?  → Resource-based policy (bucket/key/queue) with aws:SourceAccount/SourceArn
                                             or role in B assumed by A
Share infrastructure (subnets, TGW, rules)? → AWS RAM
Expose an API/service privately?            → PrivateLink / VPC Lattice
App end users needing AWS credentials?      → Cognito identity pool
Workloads outside AWS?                      → IAM Roles Anywhere
```

---

## 5. Service renames and retired / limited-availability services

### 5.1 Rename table (old → new)

> Exam stems written before a rename use the old name. Treat both names as the same service.

| Old name (may appear on exam) | Current name | When | Notes |
|---|---|---|---|
| AWS Single Sign-On (AWS SSO) | **AWS IAM Identity Center** | Jul 2022 | Same service |
| AWS Application Migration Service (MGN), and earlier CloudEndure Migration | **AWS Transform MGN** | 8 Jun 2026 | Same APIs and replication engine. Now the rehost engine behind AWS Transform |
| CloudEndure Disaster Recovery | **AWS Elastic Disaster Recovery (DRS)** | 2021 | |
| Amazon Kinesis Data Firehose | **Amazon Data Firehose** | Feb 2024 | |
| Amazon Kinesis Data Analytics (for Apache Flink) | **Amazon Managed Service for Apache Flink** | Aug 2023 | Kinesis Data Analytics for SQL fully shut down 27 Jan 2026 |
| Amazon SageMaker (ML service) | **Amazon SageMaker AI** | Dec 2024 | "SageMaker" now names the unified data + AI platform (SageMaker Unified Studio) |
| Amazon CloudWatch Events | **Amazon EventBridge** | 2019 | Same API underneath. Scheduled rules → EventBridge Scheduler preferred |
| Amazon Elasticsearch Service | **Amazon OpenSearch Service** | Sep 2021 | |
| ACM Private Certificate Authority | **AWS Private CA** | 2022 | |
| S3 Glacier (storage class) | **S3 Glacier Flexible Retrieval** | Nov 2021 | Plus new Glacier Instant Retrieval |
| AWS Personal Health Dashboard | **AWS Health Dashboard** | 2022 | |
| Route 53 Application Recovery Controller | **Amazon Application Recovery Controller (ARC)** | Recent (2025–26) | Readiness checks closed to new customers 2026 |
| Route 53 Resolver | Route 53 Resolver (docs now also call it "Route 53 VPC Resolver") | 2025–2026 | Inbound/outbound endpoints unchanged |
| AWS Security Hub (original) | **AWS Security Hub CSPM** | Jun 2025 | A new, broader "Security Hub" (exposure findings, attack paths, OCSF) took the old name |
| AWS Chatbot | **Amazon Q Developer in chat applications** | 2025 | |
| Amazon CodeWhisperer | **Amazon Q Developer** | Apr 2024 | Q Developer IDE plugins now in sunset (end Apr 2027) |
| Amazon QuickSight | **Amazon Quick Suite** (BI part: "Quick Sight") | Oct 2025 | Existing QuickSight APIs still work |
| AWS Application Composer | **AWS Infrastructure Composer** | Oct 2024 | Itself in sunset (end Sep 2027) |
| Amazon MemoryDB for Redis / ElastiCache for Redis | **Amazon MemoryDB** / **ElastiCache** (Valkey, Redis OSS, Memcached) | 2024 | Valkey support added |
| AWS Cost and Usage Report (legacy CUR) | **CUR 2.0 via AWS Data Exports** | Nov 2023 | |
| Amazon Inspector Classic | **Amazon Inspector** | 2021 | Inspector Classic fully shut down 20 May 2026 |
| AWS WAF Classic | **AWS WAF** (v2) | 2019 | WAF Classic end of support 7 Oct 2026 |
| Amazon Macie Classic | **Amazon Macie** | 2020 | |
| AWS Landing Zone (solution) | **AWS Control Tower** / Landing Zone Accelerator | 2019+ | |
| AWS Server Migration Service (SMS) | Retired → **MGN** | Ended 1 Apr 2023 | |
| Amazon EC2 Systems Manager | **AWS Systems Manager** | 2017 | |

### 5.2 Retired or limited-availability services the exam might still mention

> "Maintenance" = closed to new customers; existing customers continue. "Sunset" = end-of-support date announced. "Shut down" = gone. **Exam strategy:** if an option uses a service that is closed to new customers, it can still be the *intended* answer in an older question. Pick it only when no current alternative is offered among the options.

| Service | Status (as of Oct 2026) | Date | Current alternative |
|---|---|---|---|
| **AWS App Runner** | Closed to new customers | 30 Apr 2026 | **Amazon ECS Express Mode** |
| **AWS Snow Family** (Snowball Edge Storage/Compute Optimized) | Closed to new customers | 7 Nov 2025 | DataSync (online), **AWS Data Transfer Terminal** (physical), Outposts (edge compute) |
| AWS Snowcone | Discontinued | Orders ended 12 Nov 2024; support ended 12 Nov 2025 | As above |
| AWS Snowmobile | Retired | 2024 | As above |
| **AWS CodeCommit** | **Back to full GA** (was closed to new customers Jul 2024) | GA again 24 Nov 2025 | Valid answer again |
| **AWS Cloud9** | Closed to new customers | 25 Jul 2024 | IDE Toolkits, CloudShell |
| **Amazon QLDB** | Shut down | 31 Jul 2025 | Aurora PostgreSQL |
| **AWS Server Migration Service** | Shut down | 1 Apr 2023 | AWS Transform MGN |
| **Aurora Serverless v1** | End of life | 31 Mar 2025 (no new clusters from 8 Jan 2025) | Aurora Serverless v2 |
| **AWS OpsWorks** (Stacks, Chef Automate, Puppet Enterprise) | Shut down | 2024 | Systems Manager, Chef/Puppet SaaS |
| **AWS Proton** | End of support | 7 Oct 2026 | CloudFormation Git sync, Service Catalog, CDK pipelines |
| AWS App Mesh | End of support | 30 Sep 2026 | ECS Service Connect, VPC Lattice |
| ARC readiness checks | Closed to new customers | 30 Apr 2026 | ARC routing controls, Region switch, Resilience Hub |
| AWS Migration Hub | Closed to new customers | 7 Nov 2025 | AWS Transform |
| AWS Application Discovery Service | Closed to new customers | 7 Nov 2025 | AWS Transform |
| AWS App2Container | Closed to new customers | 7 Nov 2025 | AWS Transform |
| AWS Mainframe Modernization (managed runtime) | Closed to new customers | 7 Nov 2025 | AWS Transform for mainframe |
| Amazon Glacier (original vault-based service, "S3 Glacier Direct") | Closed to new customers | 15 Dec 2025 | S3 Glacier storage classes (unchanged) |
| S3 Select / S3 Glacier Select | Closed to new customers | 25 Jul 2024 | Athena, client-side filtering, S3 Tables/Iceberg |
| S3 Object Lambda | Closed to new customers | 7 Nov 2025 | CloudFront + Lambda, application-side transforms |
| Amazon FSx File Gateway | Closed to new customers | 28 Oct 2024 | FSx for Windows File Server directly (over DX/VPN) |
| Storage Gateway hardware appliance | No longer sold | 12 May 2025 | VM/EC2 gateway |
| AWS Directory Service Simple AD | Closed to new customers | Jun 2026 | Managed Microsoft AD, AD Connector |
| AWS Systems Manager Incident Manager / Change Manager | Closed to new customers | 7 Nov 2025 | Third-party ITSM, PagerDuty, SSM Automation + Change Calendar |
| AWS CloudTrail Lake | Closed to new customers | 31 May 2026 | CloudTrail → S3 + Athena, Security Lake, CloudWatch Logs |
| AWS Audit Manager | Closed to new customers | 30 Apr 2026 | Config conformance packs, Security Hub, Control Tower controls |
| Amazon CloudWatch Evidently | Shut down | Oct 2025 | AWS AppConfig feature flags |
| Amazon Timestream for LiveAnalytics | Closed to new customers | 20 Jun 2025 | Timestream for InfluxDB |
| Kinesis Data Analytics for SQL | Shut down | 27 Jan 2026 | Managed Service for Apache Flink |
| Amazon Forecast | Closed to new customers | Jul 2024 | SageMaker Canvas |
| Amazon Fraud Detector | Closed to new customers | 7 Nov 2025 | SageMaker AI, partner solutions |
| Amazon CloudSearch | Closed to new customers | Jul 2024 | OpenSearch Service |
| AWS Data Pipeline | Closed to new customers | 2024 | Glue, Step Functions, MWAA |
| Amazon Elastic Transcoder | Shut down | 13 Nov 2025 | AWS Elemental MediaConvert |
| AWS Elemental MediaStore | Shut down | Nov 2025 | S3 + CloudFront, MediaPackage |
| Amazon WorkDocs | Shut down | 25 Apr 2025 | Third-party file collaboration |
| AWS CodeStar | Shut down | 25 Jul 2024 | CodeCatalyst (itself closed to new customers Nov 2025), CodePipeline |
| Amazon Inspector Classic | Shut down | 20 May 2026 | Amazon Inspector |
| AWS DMS Fleet Advisor | Shut down | 20 May 2026 | AWS Transform / DMS Schema Conversion assessments |
| AWS WAF Classic | End of support | 7 Oct 2026 | AWS WAF |
| Amazon Pinpoint | End of support | 30 Oct 2026 | AWS End User Messaging, Amazon Connect |
| Lake Formation governed tables | Shut down | 31 Dec 2024 | Apache Iceberg tables (S3 Tables / Glue) |
| X-Ray SDKs and daemon | Maintenance | 25 Feb 2026 | AWS Distro for OpenTelemetry (ADOT) |
| VMware Cloud on AWS (AWS resale) | AWS stopped reselling | 30 Apr 2024 | Amazon EVS (GA Aug 2025) |
| EFS Max I/O performance mode | Previous generation | — | General Purpose mode + Elastic throughput |

---

## 6. References

- AWS Certified Solutions Architect – Professional exam guide: https://docs.aws.amazon.com/aws-certification/latest/solutions-architect-professional-02/solutions-architect-professional-02.html
- AWS service quotas (General Reference): https://docs.aws.amazon.com/general/latest/gr/aws_service_limits.html
- Lambda quotas: https://docs.aws.amazon.com/lambda/latest/dg/gettingstarted-limits.html
- API Gateway quotas: https://docs.aws.amazon.com/apigateway/latest/developerguide/limits.html and REST API quotas: https://docs.aws.amazon.com/apigateway/latest/developerguide/api-gateway-execution-service-limits-table.html
- SQS message quotas: https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/quotas-messages.html
- SNS quotas: https://docs.aws.amazon.com/general/latest/gr/sns.html
- EventBridge quotas: https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-quota.html
- Step Functions quotas: https://docs.aws.amazon.com/step-functions/latest/dg/service-quotas.html
- Kinesis Data Streams quotas: https://docs.aws.amazon.com/streams/latest/dev/service-sizes-and-limits.html
- DynamoDB quotas: https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/ServiceQuotas.html · PITR: https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/PointInTimeRecovery_Howitworks.html
- Aurora quotas: https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/CHAP_Limits.html · Aurora Global Database: https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/aurora-global-database.html
- RDS Multi-AZ failover: https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/Concepts.MultiAZ.Failover.html · Multi-AZ DB clusters: https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/multi-az-db-clusters-concepts.html
- S3 performance: https://docs.aws.amazon.com/AmazonS3/latest/userguide/optimizing-performance.html · multipart limits: https://docs.aws.amazon.com/AmazonS3/latest/userguide/qfacts.html
- EBS volume types: https://docs.aws.amazon.com/ebs/latest/userguide/ebs-volume-types.html
- Site-to-Site VPN quotas: https://docs.aws.amazon.com/vpn/latest/s2svpn/vpn-limits.html
- Direct Connect quotas: https://docs.aws.amazon.com/directconnect/latest/UserGuide/limits.html
- Transit Gateway quotas: https://docs.aws.amazon.com/vpc/latest/tgw/transit-gateway-quotas.html
- Organizations quotas: https://docs.aws.amazon.com/organizations/latest/userguide/orgs_reference_limits.html
- IAM and STS quotas: https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_iam-quotas.html
- CloudFront quotas: https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/cloudfront-limits.html · General Reference CloudFront quotas: https://docs.aws.amazon.com/general/latest/gr/cf_region.html
- AWS lifecycle pages — services in maintenance: https://docs.aws.amazon.com/general/latest/gr/maintenance_services.html · sunset: https://docs.aws.amazon.com/general/latest/gr/sunset_services.html · full shutdown: https://docs.aws.amazon.com/general/latest/gr/full_shutdown_services.html
- App Runner availability change: https://docs.aws.amazon.com/apprunner/latest/dg/apprunner-availability-change.html
- Snowball Edge availability change: https://docs.aws.amazon.com/snowball/latest/developer-guide/snowball-edge-availability-change.html
- Migration Hub availability change: https://docs.aws.amazon.com/migrationhub/latest/ug/migrationhub-availability-change.html
- AWS Transform MGN rename: https://aws.amazon.com/about-aws/whats-new/2026/06/aws-transform-mgn-rebrand/
- CodeCommit returns to GA: https://aws.amazon.com/blogs/devops/aws-codecommit-returns-to-general-availability/
- AWS Proton end of support: https://docs.aws.amazon.com/proton/latest/userguide/proton-end-of-support.html
- Simple AD availability change: https://docs.aws.amazon.com/directoryservice/latest/admin-guide/simple-ad-availability-change.html
- Disaster recovery whitepaper: https://docs.aws.amazon.com/whitepapers/latest/disaster-recovery-workloads-on-aws/disaster-recovery-workloads-on-aws.html
- Hybrid connectivity whitepaper: https://docs.aws.amazon.com/whitepapers/latest/hybrid-connectivity/hybrid-connectivity.html
- Building a scalable multi-VPC network infrastructure: https://docs.aws.amazon.com/whitepapers/latest/building-scalable-secure-multi-vpc-network-infrastructure/welcome.html

---

> [← Previous: Practice Papers](../17-Practice-Papers/README.md) · [Index](../00-README-Start-Here.md) · [Next →: Glossary & Final Revision](../19-Glossary-and-Final-Revision/19-Glossary-and-Final-Revision.md)
