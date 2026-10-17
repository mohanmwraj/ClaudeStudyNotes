# Chapter 19 — Glossary, Final-Week Revision & Exam-Day Playbook
> **Exam mapping:** All domains | **Weight signal:** High (last 7 days) | **Study time:** ~3 h to read once; then use daily
> [← Previous](../18-Cheat-Sheets-and-Comparisons/18-Cheat-Sheets-and-Comparisons.md) · [Index](../00-README-Start-Here.md) · [Next →](../00-README-Start-Here.md)

> **What this chapter is for.** Days 8–14 of the plan in [00-README-Start-Here.md](../00-README-Start-Here.md). It has four parts:
> 1. **A–Z glossary** (~210 terms). SAP stems are dense with vocabulary. If a term slows you down for even five seconds, it costs time on a 2.4-minute question.
> 2. **Top 150 facts to know cold**, each linked to its chapter.
> 3. **Final 7-day revision plan** (Sat 24 Oct → Fri 30 Oct 2026) for the exam on **Sat 31 Oct 2026**.
> 4. **Exam-day playbook**: timing, elimination, multi-select tactics, online vs test-center checklist, and mental/physical preparation.
>
> Values that changed recently are shown as "Current (exam view)". See [Chapter 18 §2](../18-Cheat-Sheets-and-Comparisons/18-Cheat-Sheets-and-Comparisons.md#2-numbers--limits) for the full verified numbers table.

---

## Contents
1. [A–Z glossary](#1-az-glossary)
2. [Top 150 facts to know cold](#2-top-150-facts-to-know-cold)
3. [Final 7-day revision plan](#3-final-7-day-revision-plan-sat-24-oct--fri-30-oct-2026)
4. [Exam-day playbook](#4-exam-day-playbook)
5. [Final checklist](#5-final-checklist)
6. [References](#6-references)

---

## 1. A–Z glossary

> Format: **Term** — one-line definition *(chapter)*. Chapter numbers refer to: [02](../02-Multi-Account-Governance/02-Multi-Account-Governance.md) governance · [03](../03-Identity-and-Access-Management/03-Identity-and-Access-Management.md) IAM · [04](../04-Networking-VPC-and-Hybrid-Connectivity/04-Networking-VPC-and-Hybrid-Connectivity.md) networking · [05](../05-Edge-DNS-and-Content-Delivery/05-Edge-DNS-and-Content-Delivery.md) edge/DNS · [06](../06-Security-Data-Protection-and-Threat-Detection/06-Security-Data-Protection-and-Threat-Detection.md) security · [07](../07-Compute-Containers-and-Serverless/07-Compute-Containers-and-Serverless.md) compute · [08](../08-Storage-and-Data-Transfer/08-Storage-and-Data-Transfer.md) storage · [09](../09-Databases-and-Caching/09-Databases-and-Caching.md) databases · [10](../10-Application-Integration-and-Event-Driven/10-Application-Integration-and-Event-Driven.md) integration · [11](../11-Analytics-Streaming-and-AI-ML/11-Analytics-Streaming-and-AI-ML.md) analytics · [12](../12-Resilience-HA-and-Disaster-Recovery/12-Resilience-HA-and-Disaster-Recovery.md) resilience · [13](../13-Migration-and-Modernization/13-Migration-and-Modernization.md) migration · [14](../14-Deployment-DevOps-and-IaC/14-Deployment-DevOps-and-IaC.md) deployment · [15](../15-Monitoring-Operations-and-Continuous-Improvement/15-Monitoring-Operations-and-Continuous-Improvement.md) operations · [16](../16-Cost-Optimization-and-FinOps/16-Cost-Optimization-and-FinOps.md) cost.

### A
- **ABAC (attribute-based access control)** — Permissions granted by matching tags, e.g. `aws:PrincipalTag/project` = `aws:ResourceTag/project`, so new projects need no new policies *(03)*.
- **Access Analyzer (IAM)** — Finds resources shared outside your zone of trust, unused access, and validates/generates least-privilege policies *(03)*.
- **Account Factory** — Control Tower feature that provisions new accounts with baseline settings. AFT is the Terraform variant *(02)*.
- **ACM (AWS Certificate Manager)** — Free public TLS certificates with auto-renewal for integrated services. Certificates for CloudFront must be in us-east-1 *(05)*.
- **ACU (Aurora capacity unit)** — Unit of Aurora Serverless v2 capacity (≈ 2 GiB memory plus matching CPU and networking). Range 0–256; 0 means auto-pause *(09)*.
- **ADOT (AWS Distro for OpenTelemetry)** — AWS-supported OpenTelemetry distribution for traces/metrics; now the recommended way to instrument for X-Ray *(15)*.
- **Alias record** — Route 53 record that points to an AWS resource (ELB, CloudFront, S3 website, another record). Works at the zone apex; queries to AWS targets are free *(05)*.
- **Anycast** — One IP address announced from many locations; traffic goes to the nearest. Used by Global Accelerator, CloudFront and Route 53 *(05)*.
- **API destination** — EventBridge target that calls any HTTP API with managed auth and rate limiting *(10)*.
- **Appliance mode** — Transit Gateway VPC-attachment setting that keeps both directions of a flow on the same AZ's appliance, so stateful inspection works *(04)*.
- **ARC (Amazon Application Recovery Controller)** — Recovery service (formerly Route 53 ARC): routing controls, zonal shift/autoshift and Region switch, using highly available data-plane actions *(12)*.
- **ASFF** — AWS Security Finding Format, used by Security Hub CSPM. The new Security Hub uses OCSF *(06)*.
- **AssumeRole** — STS call that returns temporary credentials for a role. Trust policy says who may assume; permissions policy says what they get *(03)*.
- **At-least-once delivery** — A message may arrive more than once; consumers must be idempotent (SQS Standard, Kinesis, SNS standard) *(10)*.
- **Aurora Global Database** — One primary Region plus up to 10 read-only secondary Regions with storage-level replication, typically < 1 s *(09, 12)*.
- **Auto Scaling warm pool** — Pre-initialised stopped/hibernated instances that join an ASG quickly, cutting scale-out time *(07)*.
- **AWS Transform** — AWS's agentic AI migration/modernisation service (discovery, wave planning, VMware, .NET, mainframe); replaces Migration Hub and ADS for new customers *(13)*.
- **AZ ID** — Consistent AZ identifier across accounts (e.g., `use1-az1`); AZ names like `us-east-1a` are mapped differently per account *(04)*.

### B
- **Backtrack** — Aurora MySQL feature that rewinds a cluster in place to an earlier time (up to 72 h) without restoring from backup *(09)*.
- **Backup policy** — Organizations policy that deploys AWS Backup plans across accounts *(02, 12)*.
- **Bastion host** — Hardened jump server for SSH/RDP. Usually replaced on the exam by SSM Session Manager *(15)*.
- **BGP (Border Gateway Protocol)** — Dynamic routing protocol used on Direct Connect and dynamic VPN. AS_PATH prepending and local preference communities steer traffic *(04)*.
- **Blast radius** — Scope of impact when something fails or is compromised. Reduced with multiple accounts, cells, AZs and least privilege *(02, 12)*.
- **Blue/green deployment** — Two identical environments; switch traffic to green and switch back instantly to roll back *(14)*.
- **Break-glass access** — Emergency, tightly monitored credentials used only when normal access (e.g., Identity Center) fails *(03)*.
- **Bucket Key (S3)** — Bucket-level data key that reduces SSE-KMS calls to KMS (and their cost) by up to 99% *(06, 08)*.
- **Burst balance / credits** — Accumulated performance credits on gp2, st1/sc1 and T-family instances *(07, 08)*.
- **BYOIP** — Bring your own public IP ranges to AWS (EIPs, Global Accelerator) to keep allow-listed addresses *(04)*.

### C
- **Canary deployment** — Send a small share of traffic to the new version first, then shift the rest if alarms stay green *(14)*.
- **Capacity Rebalancing** — ASG feature that launches a replacement when a Spot instance gets a rebalance recommendation, before the 2-minute notice *(07)*.
- **CDC (change data capture)** — Streaming ongoing changes from a source database's logs (DMS CDC, DynamoDB Streams) *(13)*.
- **Cell-based architecture** — Workload split into independent, identical cells, each serving a subset of customers, to contain failures *(12)*.
- **Change set** — Preview of what a CloudFormation stack update will add, modify or replace *(14)*.
- **Circuit breaker** — Pattern (and ECS deployment feature) that stops calls or rolls back when failures exceed a threshold *(12, 14)*.
- **Cloud WAN** — Managed global network with a core network, segments and a JSON policy; connects VPCs, VPNs, DX and SD-WAN *(04)*.
- **Cluster placement group** — Instances packed close together in one AZ for low latency and high throughput (HPC) *(07)*.
- **Cold start** — Latency when Lambda creates a new execution environment. Fix with provisioned concurrency or SnapStart *(07)*.
- **Compensating transaction** — Undo step in a saga when a later step fails *(10)*.
- **Confused deputy** — A trusted service is tricked into acting for the wrong party. Prevented with External ID, `aws:SourceArn` and `aws:SourceAccount` *(03)*.
- **Conformance pack** — Collection of AWS Config rules and remediations deployed as one unit, organisation-wide if needed *(15)*.
- **Consolidated billing** — One payer for the organisation; usage is pooled for volume tiers and RI/Savings Plan sharing *(16)*.
- **Control (Control Tower)** — Guardrail implemented as an SCP/RCP (preventive), Config rule (detective) or CloudFormation hook (proactive) *(02)*.
- **Cost allocation tag** — Activated tag that appears in billing data for chargeback *(16)*.
- **Cost Category** — Billing rule grouping costs by account, tag or service, with split charges for shared costs *(16)*.
- **Cross-zone load balancing** — LB distributes evenly across targets in all AZs. On by default for ALB; off by default for NLB/GWLB *(07)*.
- **CUR 2.0** — Cost and Usage Report delivered via Data Exports; line-item billing data for Athena/QuickSight *(16)*.

### D
- **Data perimeter** — Set of guardrails (SCP, RCP, endpoint policies) ensuring only trusted identities access trusted resources from expected networks *(02, 06)*.
- **Dead-letter queue (DLQ)** — Queue that holds messages that failed processing after max retries (SQS, SNS, Lambda async, EventBridge) *(10)*.
- **Declarative policy** — Organizations policy that enforces a service configuration baseline (e.g., EC2 IMDSv2, block public AMI sharing) at the service level *(02)*.
- **Dedicated Host** — Physical server for your use; gives socket/core visibility for BYOL *(07, 16)*.
- **Delegated administrator** — Member account allowed to manage an AWS service org-wide, so the management account stays clean *(02)*.
- **Deregistration delay** — Time an ELB keeps sending in-flight requests to a target being removed (connection draining) *(07)*.
- **Detective control** — Finds noncompliance after it happens (Config rules, GuardDuty), as opposed to preventive controls *(02, 06)*.
- **DNSSEC** — Signs DNS responses to prevent spoofing. Route 53 supports signing and validation *(05)*.
- **Drift** — Difference between a CloudFormation stack's template and the real resource configuration *(14)*.
- **DX gateway** — Global Direct Connect object that links VIFs to VGWs (up to 20) or TGWs (up to 6) in any Region except China *(04)*.
- **DX location** — Colocation facility where you cross-connect to the AWS network *(04)*.
- **DynamoDB Streams** — Time-ordered item-level change log kept 24 h; triggers Lambda; feeds global tables *(09)*.

### E
- **ECMP (equal-cost multi-path)** — Spreading traffic over several equal routes, e.g., multiple VPN tunnels on a TGW to exceed 1.25 Gbps *(04)*.
- **Edge location** — CloudFront/Route 53/Global Accelerator point of presence *(05)*.
- **EFA (Elastic Fabric Adapter)** — Network interface for HPC/ML with OS-bypass and low latency *(07)*.
- **Egress-only internet gateway** — Outbound-only IPv6 internet access *(04)*.
- **Elastic IP** — Static public IPv4 address you own in a Region *(04)*.
- **Enhanced fan-out** — Kinesis consumer mode with a dedicated 2 MB/s per shard push pipe *(11)*.
- **Envelope encryption** — Encrypt data with a data key, then encrypt the data key with a KMS key. Avoids the 4 KB limit and network round trips *(06)*.
- **Event sourcing** — Store state as an append-only sequence of events (Kinesis, DynamoDB Streams) *(10)*.
- **Eventual consistency** — Reads may briefly return stale data (DynamoDB default reads, replicas) *(09)*.
- **Exactly-once processing** — SQS FIFO with deduplication guarantees a message is processed once within the 5-minute window; Step Functions Standard executes exactly once *(10)*.
- **Express workflow** — Step Functions type for high-volume runs ≤ 5 min; no callbacks or `.sync` *(10)*.
- **External ID** — Secret-like value a third party must pass when assuming your role; stops confused-deputy attacks *(03)*.

### F
- **Failover routing** — Route 53 policy returning the secondary record when the primary's health check fails *(05)*.
- **Fan-out** — One message delivered to many consumers (SNS → many SQS queues) *(10)*.
- **Fault isolation boundary** — Scope that contains a failure: AZ, Region, account, cell, partition *(12)*.
- **FinOps** — Practice of shared financial accountability for cloud spend: inform → optimise → operate *(16)*.
- **Firewall Manager** — Central management of WAF, Shield Advanced, security groups, Network Firewall and DNS Firewall policies across the organisation *(06)*.
- **Flow logs** — Metadata records of IP traffic for VPC/subnet/ENI (no payload) *(04, 15)*.

### G
- **GENEVE** — Encapsulation protocol (UDP 6081) Gateway Load Balancer uses to pass packets to appliances unchanged *(04)*.
- **Geolocation routing** — Route 53 answers by where the user is (country/continent) *(05)*.
- **Geoproximity routing** — Route 53 answers by distance to resources, adjustable with bias *(05)*.
- **Global tables** — DynamoDB multi-Region, multi-active replication (MREC or MRSC) *(09)*.
- **Golden AMI** — Pre-hardened, pre-patched image used as the baseline for all instances (EC2 Image Builder) *(14)*.
- **Graviton** — AWS Arm-based processors; typically better price-performance *(07, 16)*.
- **Guardrail** — Preventive or detective control applied across accounts *(02)*.
- **GWLB endpoint** — VPC endpoint used as a route target to send traffic through a Gateway Load Balancer *(04)*.

### H
- **Health check (ELB vs Route 53)** — ELB health checks remove unhealthy targets; Route 53 health checks remove unhealthy DNS records *(05, 07)*.
- **Hosted connection** — Direct Connect link provisioned by a partner, 50 Mbps–25 Gbps, one VIF *(04)*.
- **Hosted zone** — Route 53 container for records. Public = internet; private = associated VPCs *(05)*.
- **Hot partition** — One partition key getting disproportionate traffic, causing throttling *(09)*.
- **Hyperplane** — AWS's internal distributed network function platform behind NLB, NAT gateway, PrivateLink and TGW *(04)*.
- **Hybrid DNS** — DNS resolution between on-prem and VPCs via Route 53 Resolver endpoints *(04)*.

### I
- **Idempotency** — Repeating an operation has the same effect as doing it once. Essential with at-least-once delivery and retries *(10)*.
- **IMDSv2** — Session-token-based instance metadata service that blocks SSRF-style credential theft *(06)*.
- **Immutable deployment** — Deploy to brand-new instances, then swap; never patch in place *(14)*.
- **Inbound / outbound endpoint** — Route 53 Resolver ENIs for on-prem→AWS and AWS→on-prem DNS queries *(04)*.
- **Inspection VPC** — Central VPC with firewalls that all inter-VPC/egress traffic is routed through via TGW *(04)*.
- **Instance store** — Ephemeral block storage physically attached to the host; data lost on stop/terminate *(08)*.
- **Interface endpoint** — PrivateLink ENI giving private access to a service; reachable from on-prem *(04)*.
- **IPAM** — VPC IP Address Manager: plan, allocate and audit CIDRs across the organisation *(04)*.

### J
- **Jumbo frames** — Ethernet frames up to 9,001 bytes inside a VPC; TGW supports 8,500; VPN and internet 1,500 *(04)*.
- **JWT** — JSON Web Token issued by Cognito user pools/OIDC IdPs, validated by API Gateway or ALB *(03)*.

### K
- **Key policy** — Resource policy on a KMS key; every key must have one, and cross-account use needs it to allow the other account *(06)*.
- **Key rotation (KMS)** — Automatic rotation of customer managed key material (configurable period, default yearly); old material kept for decryption *(06)*.
- **KPL / KCL** — Kinesis Producer Library (batching, aggregation) and Client Library (checkpointing via DynamoDB, shard leasing) *(11)*.

### L
- **LAG (link aggregation group)** — Bundle of same-speed DX connections at one location acting as one link *(04)*.
- **Lambda@Edge** — Lambda functions run at CloudFront Regional edge caches on viewer/origin events *(05)*.
- **Landing zone** — Well-architected multi-account baseline: OUs, log archive, audit/security account, networking, identity *(02)*.
- **Latency-based routing** — Route 53 sends users to the Region with the lowest measured latency *(05)*.
- **Least privilege** — Grant only the permissions required, nothing more *(03)*.
- **Lifecycle policy** — S3 rules that transition or expire objects by age; also EBS/ECR lifecycle *(08)*.
- **Local Zone** — AWS infrastructure in a metro area for single-digit-ms latency to users *(07)*.
- **Log archive account** — Dedicated account that stores immutable org-wide CloudTrail/Config logs *(02)*.
- **Long polling** — SQS ReceiveMessage waits up to 20 s for messages, reducing empty responses and cost *(10)*.

### M
- **MACsec** — IEEE 802.1AE layer-2 encryption on supported Direct Connect dedicated connections *(04)*.
- **Management account** — Account that created the organisation; pays the bill; not restricted by SCPs/RCPs. Keep workloads out *(02)*.
- **MAP (Migration Acceleration Program)** — AWS programme with assess → mobilise → migrate-and-modernise phases, funding and tooling *(13)*.
- **Message group ID** — SQS FIFO key; order is guaranteed within a group, and groups process in parallel *(10)*.
- **MREC / MRSC** — DynamoDB global tables modes: multi-Region eventual consistency (any number of Regions, last-writer-wins) / multi-Region strong consistency (exactly 3 Regions, RPO 0) *(09)*.
- **Multi-AZ** — Redundant deployment across AZs within one Region for HA *(09, 12)*.
- **Multi-Region key** — KMS keys with the same key ID and material in several Regions, for cross-Region decrypt without re-encryption *(06)*.
- **Multi-site active/active** — DR strategy with full production in two or more Regions serving traffic *(12)*.
- **MTU** — Largest packet size on a link (VPC 9,001; TGW 8,500; VPN 1,446 with overhead) *(04)*.
- **mTLS** — Mutual TLS: both client and server present certificates (API Gateway, ALB, CloudFront support it) *(06)*.

### N
- **NACL** — Stateless subnet-level firewall with numbered allow and deny rules *(04)*.
- **NAT gateway** — Managed, AZ-scoped outbound IPv4 translation for private subnets; one per AZ for HA *(04)*.
- **Noisy neighbour** — One tenant/workload degrading others on shared resources; mitigated with cells and shuffle sharding *(12)*.

### O
- **OAC (Origin Access Control)** — CloudFront's signed (SigV4) access to S3/other origins so the bucket can block all other access; supersedes OAI *(05)*.
- **OCSF** — Open Cybersecurity Schema Framework; used by Security Lake and the new Security Hub *(06)*.
- **ODCR (On-Demand Capacity Reservation)** — Reserves capacity for an instance type in one AZ; billed whether used or not *(07, 16)*.
- **OIDC** — OpenID Connect; identity layer on OAuth 2.0 used for federation (e.g., GitHub Actions → IAM role) *(03)*.
- **Organizational unit (OU)** — Container of accounts in Organizations to which policies attach; up to 5 levels deep *(02)*.
- **Origin group** — CloudFront primary + secondary origin with failover on specified HTTP errors *(05)*.
- **Origin Shield** — Extra CloudFront caching layer in one Region that reduces origin load *(05)*.
- **Outposts** — AWS-managed racks/servers running AWS services in your data centre *(07)*.

### P
- **Partition key** — DynamoDB/Kinesis attribute hashed to choose a partition/shard; high cardinality spreads load *(09, 11)*.
- **Permission set** — IAM Identity Center template of policies, provisioned as a role in each assigned account *(03)*.
- **Permissions boundary** — Managed policy that caps the maximum permissions of a user/role; grants nothing *(03)*.
- **Pilot light** — DR strategy where data is replicated and core infrastructure is minimal or off until failover *(12)*.
- **PITR (point-in-time recovery)** — Restore to any second in a retention window (DynamoDB 1–35 days; RDS within backup retention) *(09, 12)*.
- **Placement group** — Cluster (low latency), spread (separate hardware, max 7 per AZ) or partition (separate racks for HDFS/Cassandra) *(07)*.
- **Prefix list** — Named set of CIDRs reusable in security groups and route tables, shareable via RAM *(04)*.
- **PrivateLink** — Private, one-way, consumer-initiated access to a service via interface endpoints; supports overlapping CIDRs *(04)*.
- **Proactive control** — Control Tower control that checks CloudFormation resources before provisioning (CloudFormation Hooks) *(02)*.
- **Provisioned concurrency** — Pre-initialised Lambda environments that remove cold starts *(07)*.
- **Public VIF** — DX virtual interface to AWS public endpoints *(04)*.
- **Purpose-built database** — Choosing a database engine to fit the access pattern rather than one database for everything *(09)*.

### Q
- **Quorum** — Minimum number of nodes that must agree; Aurora writes need 4 of 6 copies and reads need 3 of 6 *(09)*.
- **Queue-based load levelling** — Put a queue between tiers so consumers process at a steady rate; scale on backlog per instance *(10)*.

### R
- **RAM (Resource Access Manager)** — Shares resources (subnets, TGWs, Resolver rules, prefix lists, IPAM pools, etc.) across accounts or the organisation *(02)*.
- **RCP (resource control policy)** — Organizations policy that sets maximum permissions on *resources* in member accounts (e.g., deny access from outside the org) *(02)*.
- **Read replica** — Asynchronously replicated, readable copy; can be promoted; cross-Region possible *(09)*.
- **Rebalance recommendation** — Early signal that a Spot instance is at elevated risk of interruption *(07)*.
- **Region switch** — ARC capability that orchestrates multi-Region failover plans *(12)*.
- **Replatform** — Migrate with small optimisations (e.g., self-managed DB → RDS) *(13)*.
- **Resilience Hub** — Assesses applications against RTO/RPO targets and recommends improvements *(12)*.
- **Resource-based policy** — Policy attached to a resource that names principals (S3 bucket policy, KMS key policy, SQS policy) *(03)*.
- **Retry with exponential backoff and jitter** — Increasing, randomised delays between retries to avoid thundering herds *(10, 12)*.
- **Role chaining** — Using a role's credentials to assume another role; session limited to 1 hour *(03)*.
- **Route propagation** — Automatic insertion of VGW/TGW-learned routes into route tables *(04)*.
- **RPO (recovery point objective)** — Maximum acceptable data loss, measured in time *(12)*.
- **RTO (recovery time objective)** — Maximum acceptable time to restore service *(12)*.
- **RTC (S3 Replication Time Control)** — S3 replication option with a 15-minute replication target, metrics and SLA *(08)*.

### S
- **Saga** — Sequence of local transactions with compensating actions instead of a distributed transaction (Step Functions) *(10)*.
- **SAML 2.0** — XML federation standard used by enterprise IdPs with Identity Center or IAM *(03)*.
- **SCIM** — Protocol to automatically provision users and groups from an IdP into Identity Center *(03)*.
- **SCP (service control policy)** — Organizations policy that sets maximum permissions for principals in member accounts; never grants *(02)*.
- **Security group** — Stateful, allow-only firewall on ENIs; can reference other security groups *(04)*.
- **Service-linked role** — Predefined role a service assumes to act for you; not restricted by SCPs *(03)*.
- **Session policy** — Inline/managed policy passed at AssumeRole that further limits that session *(03)*.
- **Session tags** — Key-value tags passed during AssumeRole/federation, used for ABAC *(03)*.
- **Shared VPC** — VPC whose subnets are shared via RAM; participants launch resources into owner-managed subnets *(02, 04)*.
- **Shuffle sharding** — Assign each customer a random subset of workers so one bad customer affects only a small fraction of others *(12)*.
- **SNI** — TLS Server Name Indication; lets many certificates share one IP (CloudFront, ALB) *(05)*.
- **SnapStart** — Lambda feature that snapshots an initialised environment to cut cold starts (Java, Python, .NET) *(07)*.
- **Spot Instance** — Spare EC2 capacity at up to 90% discount; reclaimed with a 2-minute notice *(07, 16)*.
- **Static stability** — System keeps working during a dependency or control-plane failure without needing to make changes (e.g., pre-provisioned capacity in each AZ) *(12)*.
- **Sticky sessions** — ELB session affinity via cookies *(07)*.
- **Strangler fig** — Incrementally replace parts of a monolith by routing features to new services *(13)*.
- **STS (Security Token Service)** — Issues temporary credentials (AssumeRole, AssumeRoleWithSAML, AssumeRoleWithWebIdentity) *(03)*.

### T
- **Tag policy** — Organizations policy standardising tag keys/values; can enforce on supported resource types *(02, 16)*.
- **Target tracking** — Auto Scaling policy that holds a metric at a target value (e.g., 50% CPU) *(07)*.
- **Throttling** — Service rejecting requests above a quota (HTTP 429/ThrottlingException); retry with backoff *(10)*.
- **Token bucket** — Rate-limiting algorithm with a refill rate and burst capacity (API Gateway, Step Functions) *(10)*.
- **Transit VIF** — DX virtual interface connecting to a DX gateway associated with TGWs or Cloud WAN *(04)*.
- **TGW route table** — Per-attachment association and propagation control; used for segmentation (e.g., prod vs dev) *(04)*.
- **TTL** — Time to live: DNS caching duration, or DynamoDB item expiry (deletion typically within a few days) *(05, 09)*.

### U
- **User pool (Cognito)** — Managed user directory for sign-up/sign-in, MFA and federation; issues JWTs *(03)*.
- **Unscored questions** — 10 of the 75 exam questions are unscored pretest items; you can't tell which *(01)*.

### V
- **Vault Lock (AWS Backup)** — WORM protection for backup vaults; compliance mode can't be removed by anyone after the grace period *(12)*.
- **VGW (virtual private gateway)** — VPC-side VPN/DX endpoint for a single VPC *(04)*.
- **VPC endpoint policy** — Resource policy on an endpoint limiting which principals/resources can be reached through it *(04, 06)*.
- **VPC Lattice** — Application-layer service network connecting services across VPCs and accounts with IAM auth policies *(04)*.
- **VPC peering** — Private, non-transitive 1:1 connection between two VPCs (same or cross-Region/account) *(04)*.
- **Visibility timeout** — Period a received SQS message stays hidden; must exceed processing time (default 30 s, max 12 h) *(10)*.

### W
- **WAF web ACL** — Ordered set of AWS WAF rules (managed, custom, rate-based) attached to CloudFront, ALB, API Gateway and others *(06)*.
- **Warm standby** — DR strategy with a scaled-down but fully functional copy running in another Region *(12)*.
- **Weighted routing** — Route 53 splits traffic by assigned weights *(05)*.
- **Well-Architected Framework** — Six pillars: operational excellence, security, reliability, performance efficiency, cost optimisation, sustainability *(01)*.
- **Write forwarding** — Aurora Global Database (and some Aurora replicas) forwarding writes from a secondary to the primary writer *(09)*.
- **Write sharding** — Adding a random/calculated suffix to a hot partition key to spread writes *(09)*.

### X
- **X-Ray** — Distributed tracing service (service maps, segments). Use ADOT for instrumentation *(15)*.
- **XKS (External Key Store)** — KMS keys backed by an HSM you run outside AWS *(06)*.

### Z
- **Zero trust** — Never trust network location alone; authenticate and authorise every request (Verified Access, VPC Lattice auth, IAM) *(06)*.
- **Zonal autoshift** — ARC feature where AWS automatically shifts traffic away from an impaired AZ for enrolled resources *(12)*.
- **Zonal shift** — ARC action that moves load balancer traffic away from one AZ temporarily *(12)*.

---

## 2. Top 150 facts to know cold

> Read this list aloud once a day from Tuesday onward. Each fact is the *rule* behind a typical correct answer. Recently changed numbers are shown as "current (exam view)".

### Exam mechanics ([01](../01-Exam-Blueprint-and-Strategy/01-Exam-Blueprint-and-Strategy.md))
1. SAP-C02: 75 questions (65 scored + 10 unscored), 180 minutes, scaled 100–1,000, pass 750, compensatory scoring, no penalty for wrong answers.
2. Domains: D1 26%, D2 29%, D3 25%, D4 20%. D2 (new solutions) is the largest.
3. Multi-select questions say exactly how many to choose ("Select TWO"); all must be correct for credit.

### Governance & multi-account ([02](../02-Multi-Account-Governance/02-Multi-Account-Governance.md))
4. SCPs and RCPs never grant permissions; they only set maximums. An explicit Deny anywhere wins.
5. SCPs do not affect the management account or service-linked roles.
6. SCPs restrict principals (identity side); RCPs restrict resources (resource side) for supported services such as S3, STS, KMS, SQS and Secrets Manager.
7. SCP size limit: 10,240 characters and 10 per entity now (exam view: 5,120 characters, 5 per entity). RCP: 5,120 characters, 5 per entity.
8. OUs can be nested 5 levels deep under the root.
9. Control Tower = Organizations + landing zone (log archive + audit accounts) + Account Factory + preventive/detective/proactive controls.
10. Keep workloads out of the management account; use delegated administrators for security services.
11. StackSets with service-managed permissions deploy automatically to new accounts in target OUs.
12. RAM shares subnets (shared VPC), TGWs, Resolver rules, prefix lists, IPAM pools and more.
13. Tag policies standardise tags; an SCP with `aws:RequestTag` conditions is what *blocks* untagged creation broadly.
14. `aws:PrincipalOrgID` in a resource policy = "only identities from my organization".
15. A central log archive account with S3 Object Lock and an org trail is the standard immutable audit pattern.

### Identity ([03](../03-Identity-and-Access-Management/03-Identity-and-Access-Management.md))
16. Policy evaluation order (IAM docs): explicit Deny anywhere → RCPs → SCPs → resource-based policies → identity-based policies → permissions boundaries → session policies. Default is implicit deny.
17. Cross-account access needs both sides: the trust/resource policy in the target and an identity policy in the source.
18. Third-party access = cross-account role + External ID (confused-deputy protection).
19. IAM Identity Center + permission sets + SCIM is the default answer for workforce access across many accounts.
20. Cognito user pool = authentication (JWT). Identity pool = temporary AWS credentials.
21. Permissions boundaries let developers create roles without escalating privileges.
22. ABAC uses `aws:PrincipalTag` and `aws:ResourceTag`; session tags come from the IdP.
23. Role sessions last 15 min–12 h (role setting); role chaining is limited to 1 hour.
24. IAM Roles Anywhere gives on-prem workloads temporary credentials using X.509 certificates.
25. EKS Pod Identity (or IRSA) gives each pod its own IAM role.
26. IAM Access Analyzer finds external sharing and unused access, and generates least-privilege policies.

### Networking ([04](../04-Networking-VPC-and-Hybrid-Connectivity/04-Networking-VPC-and-Hybrid-Connectivity.md))
27. VPC peering is non-transitive and doesn't support overlapping CIDRs.
28. Transit Gateway: transitive hub, 5,000 attachments, route tables for segmentation, up to 100 Gbps per VPC attachment per AZ (exam view 50 Gbps).
29. TGW appliance mode keeps flows symmetric through stateful inspection appliances.
30. Cloud WAN = global network managed by a policy, with segments; uses TGW-like attachments.
31. PrivateLink exposes one service to many consumers, supports overlapping CIDRs and is consumer-initiated only.
32. Gateway endpoints (S3, DynamoDB) are free but not reachable from on-prem or peered VPCs; interface endpoints are.
33. A standard VPN tunnel gives up to 1.25 Gbps; use ECMP on TGW (BGP) or Large Bandwidth Tunnels (5 Gbps) for more. VGW doesn't support ECMP.
34. DX dedicated: 1/10/100/400 Gbps. Hosted: 50 Mbps–25 Gbps via partner, 1 VIF.
35. DX is not encrypted by default: MACsec (supported dedicated ports) or IPsec VPN over DX.
36. DX gateway connects to up to 20 VGWs or 6 TGWs, across Regions and accounts.
37. Private VIF → VPC; public VIF → public AWS endpoints; transit VIF → TGW/Cloud WAN.
38. Maximum DX resiliency: two connections at each of two DX locations, on separate devices.
39. On a TGW, static routes beat propagated routes; among propagated routes, DX beats VPN.
40. On-prem → Route 53 private zone = Resolver inbound endpoint. VPC → on-prem names = outbound endpoint + forwarding rules shared by RAM.
41. Centralised egress: NAT gateways in an egress VPC via TGW; one NAT gateway per AZ for HA.
42. Gateway Load Balancer uses GENEVE on UDP 6081 to insert third-party appliances transparently.
43. Security groups are stateful and allow-only; NACLs are stateless and can deny.
44. Overlapping CIDRs: private NAT gateway or PrivateLink — not peering or TGW.
45. VPC Reachability Analyzer explains path problems; Flow Logs record traffic metadata; Traffic Mirroring captures packets.

### Edge & DNS ([05](../05-Edge-DNS-and-Content-Delivery/05-Edge-DNS-and-Content-Delivery.md))
46. Global Accelerator: 2 static anycast IPs, TCP/UDP, fast health-based failover, no caching.
47. CloudFront: HTTP(S)/WebSocket caching CDN; OAC locks S3 to CloudFront; signed URLs (one file) vs signed cookies (many files).
48. CloudFront Functions: sub-ms, viewer events only, no network. Lambda@Edge: viewer 5 s/128 MB, origin 30 s, network access, deployed from us-east-1.
49. ACM certificates for CloudFront must be in us-east-1.
50. Route 53 alias records work at the zone apex and are free for AWS targets.
51. Latency routing = performance; geolocation = compliance/localisation; weighted = canary/migration; failover = active-passive.
52. CloudFront origin groups fail over on configured error codes; Origin Shield reduces origin load.

### Security & data protection ([06](../06-Security-Data-Protection-and-Threat-Detection/06-Security-Data-Protection-and-Threat-Detection.md))
53. KMS encrypts up to 4 KB directly; anything larger uses envelope encryption (GenerateDataKey).
54. Cross-account KMS use needs the key policy to allow the other account and an IAM policy in that account.
55. Multi-Region KMS keys share key material and key ID across Regions for DR and global tables.
56. CloudHSM = single-tenant HSMs you control. XKS = keys kept outside AWS.
57. S3 Bucket Keys reduce SSE-KMS request costs by up to 99%.
58. Secrets Manager rotates credentials natively; Parameter Store doesn't.
59. GuardDuty = threat detection; Inspector = vulnerabilities; Macie = PII in S3; Detective = investigation; Security Hub CSPM = posture and aggregation; Config = configuration compliance.
60. WAF works at L7 (SQLi, XSS, rate-based rules, geo); Shield Advanced adds DDoS response team, cost protection and L7 auto-mitigation.
61. Firewall Manager applies WAF/Shield/SG/Network Firewall/DNS Firewall policies org-wide (needs Organizations and Config).
62. S3 Object Lock compliance mode: nobody, including root, can delete before retention ends. Governance mode can be bypassed with permission.
63. AWS Backup Vault Lock gives WORM backups; copy to a separate account protects against account compromise.
64. Config rule + SSM Automation = automatic remediation.
65. IMDSv2 protects instance credentials from SSRF; enforce it org-wide with a declarative policy or SCP.

### Compute ([07](../07-Compute-Containers-and-Serverless/07-Compute-Containers-and-Serverless.md))
66. Lambda: 15 min max, 128 MB–10,240 MB memory, 10,240 MB `/tmp`, 1,000 default concurrency (soft), 6 MB sync payload, 1 MB async (exam view 256 KB).
67. Lambda + RDS connection exhaustion → RDS Proxy.
68. Cold starts → provisioned concurrency or SnapStart.
69. Fargate removes server management for ECS/EKS; ECS is simpler than EKS.
70. Spot gives up to 90% off with a 2-minute notice; use diversified instance types, price-capacity-optimized allocation and Capacity Rebalancing.
71. Capacity is guaranteed only by On-Demand Capacity Reservations (or zonal RIs), not by Savings Plans.
72. Placement groups: cluster = low latency; spread = max 7 instances per AZ on distinct hardware; partition = rack isolation for big data.
73. ALB: L7 routing, WAF, OIDC auth, Lambda targets. NLB: static IP per AZ, UDP, PrivateLink, preserves source IP. GWLB: inline appliances.
74. App Runner closed to new customers on 30 Apr 2026; ECS Express Mode is AWS's suggested alternative.
75. Dedicated Hosts are the answer for per-socket/per-core BYOL licensing.

### Storage ([08](../08-Storage-and-Data-Transfer/08-Storage-and-Data-Transfer.md))
76. S3 performance: 3,500 writes and 5,500 reads per second per prefix; parallelise across prefixes.
77. S3 max object 50 TB now (exam view 5 TB); single PUT max 5 GB; multipart for large objects.
78. S3 is strongly consistent for all reads after writes.
79. S3 minimum storage duration: IA classes 30 days, Glacier Instant/Flexible 90 days, Deep Archive 180 days.
80. Glacier Flexible retrieval: expedited 1–5 min, standard 3–5 h, bulk 5–12 h. Deep Archive: standard ≤ 12 h, bulk ≤ 48 h.
81. S3 Replication needs versioning on both buckets; existing objects need S3 Batch Replication; RTC adds a 15-minute target and SLA.
82. EBS volumes are AZ-scoped; move across AZs/Regions via snapshots.
83. gp3: 3,000 IOPS/125 MiB/s baseline, configurable to 80,000 IOPS/2,000 MiB/s (exam view 16,000/1,000).
84. io2 Block Express: up to 256,000 IOPS, 99.999% durability; Multi-Attach for io1/io2 only.
85. EFS = multi-AZ NFS for Linux; FSx for Windows = SMB + AD; FSx for Lustre = HPC; FSx for ONTAP = multi-protocol + NetApp features.
86. S3 File Gateway = NFS/SMB to S3; Tape Gateway = virtual tapes; Volume Gateway = iSCSI.
87. DataSync = online bulk/scheduled transfer with integrity checks; Transfer Family = managed SFTP/FTPS/FTP/AS2.
88. Snow Family is closed to new customers (Nov 2025); offline transfer for new customers → AWS Data Transfer Terminal.

### Databases ([09](../09-Databases-and-Caching/09-Databases-and-Caching.md))
89. RDS Multi-AZ (instance): synchronous standby, not readable, failover typically 60–120 s.
90. RDS Multi-AZ DB cluster: 2 readable standbys, semi-synchronous, faster failover.
91. Read replicas are asynchronous, readable, can be cross-Region and can be promoted.
92. Aurora: 6 copies across 3 AZs, up to 15 replicas, storage auto-grows to 128 TiB (256 TiB on newest versions).
93. Aurora Global Database: up to 10 secondary Regions (exam view 5), lag typically < 1 s, switchover RPO 0, failover RTO ~1 min, write forwarding.
94. Aurora Serverless v2: 0–256 ACU (0 = auto-pause). v1 is end-of-life.
95. DynamoDB item max 400 KB; partition max 3,000 RCU/1,000 WCU; on-demand absorbs up to 2× previous peak instantly.
96. DynamoDB global tables: MREC = active-active, last-writer-wins; MRSC = strong consistency across exactly 3 Regions with RPO 0.
97. DynamoDB PITR: restore to any second in a 1–35 day window, always to a new table.
98. DAX = microsecond cache for DynamoDB only; ElastiCache = general cache; MemoryDB = durable in-memory primary database.
99. ElastiCache Global Datastore supports up to 2 secondary Regions.
100. RDS Proxy pools connections and cuts failover time for Aurora/RDS.

### Integration ([10](../10-Application-Integration-and-Event-Driven/10-Application-Integration-and-Event-Driven.md))
101. SQS: message 1 MiB now (exam view 256 KB), retention 1 min–14 days (default 4), visibility up to 12 h, long polling up to 20 s, delay up to 15 min.
102. SQS FIFO: strict order per message group, exactly-once processing (5-min dedup), 300 TPS per action (3,000 with batching), higher in high-throughput mode.
103. SNS → SQS fan-out is the classic durable pub/sub pattern; SNS FIFO → SQS FIFO keeps order.
104. EventBridge: content-based routing, 5 targets per rule, cross-account buses, archive and replay, retries up to 24 h/185 attempts, then DLQ.
105. Step Functions Standard: up to 1 year, exactly-once, callbacks. Express: up to 5 min, no `.waitForTaskToken`/`.sync`.
106. Amazon MQ for JMS/AMQP/MQTT lift-and-shift; MSK for Kafka.
107. API Gateway: 10,000 RPS/5,000 burst (soft), 29 s integration timeout (raisable for Regional/private REST), 10 MB payload.
108. Long-running API requests → async pattern: API → SQS/Step Functions → poll or callback/WebSocket.
109. Idempotency keys plus retries with exponential backoff and jitter make at-least-once systems safe.

### Analytics ([11](../11-Analytics-Streaming-and-AI-ML/11-Analytics-Streaming-and-AI-ML.md))
110. Kinesis shard: 1 MB/s or 1,000 records/s in; 2 MB/s out shared; enhanced fan-out 2 MB/s per consumer per shard.
111. Kinesis retention: 24 h default, up to 365 days; records up to 10 MiB now (exam view 1 MB).
112. Firehose = near-real-time delivery to S3/Redshift/OpenSearch/Splunk/HTTP, with Lambda transforms and Parquet conversion.
113. Managed Service for Apache Flink = real-time stream processing (formerly Kinesis Data Analytics).
114. Athena charges per data scanned: partition, compress and use Parquet/ORC to cut cost.
115. Redshift for repeated, complex BI; Spectrum queries S3 directly; RA3/Serverless separate storage from compute.
116. Lake Formation gives row/column/cell-level permissions and cross-account data sharing for the data lake.
117. Glue = serverless ETL + Data Catalog; EMR = full control of big-data frameworks.

### Resilience & DR ([12](../12-Resilience-HA-and-Disaster-Recovery/12-Resilience-HA-and-Disaster-Recovery.md))
118. DR spectrum: backup & restore (hours) → pilot light (tens of minutes) → warm standby (minutes) → multi-site active/active (near zero).
119. RPO = how much data you can lose; RTO = how long you can be down.
120. Elastic Disaster Recovery (DRS) gives block-level replication for servers with RPO in seconds and RTO in minutes.
121. Static stability: pre-provision capacity so failover doesn't depend on control-plane actions.
122. Use data-plane operations (Route 53 health checks, ARC routing controls) for failover, not control-plane changes.
123. Multi-AZ protects against AZ failure; multi-Region protects against Region failure and is costlier.
124. Test DR regularly: game days, AWS FIS experiments, Resilience Hub assessments.
125. Cell-based architecture and shuffle sharding limit blast radius.

### Migration ([13](../13-Migration-and-Modernization/13-Migration-and-Modernization.md))
126. 7 Rs: retire, retain, rehost, relocate, repurchase, replatform, refactor.
127. Rehost servers with AWS Transform MGN (formerly Application Migration Service): continuous replication → test → cutover.
128. Discovery and wave planning: AWS Transform now; Application Discovery Service + Migration Hub on older exams.
129. DMS full load + CDC = minimal downtime; heterogeneous needs schema conversion (DMS Schema Conversion/SCT).
130. VMware estates: Amazon EVS (relocate) or MGN (rehost to EC2).
131. Strangler fig pattern modernises a monolith incrementally behind API Gateway/ALB routing.
132. MAP phases: assess → mobilise → migrate & modernise.
133. Migration timeline drives the R: tight deadline → rehost first, optimise later.

### Deployment & IaC ([14](../14-Deployment-DevOps-and-IaC/14-Deployment-DevOps-and-IaC.md))
134. Blue/green = instant rollback; canary/linear = gradual with alarm-based rollback; immutable = new instances.
135. CloudFormation change sets preview updates; drift detection finds manual changes; `DeletionPolicy: Retain/Snapshot` protects data.
136. CDK and SAM synthesise CloudFormation; Service Catalog gives governed self-service with launch constraints.
137. Cross-account CI/CD: pipeline in a tooling account assumes deployment roles in target accounts; artifact bucket and KMS key shared cross-account.
138. CodeCommit is generally available again (Nov 2025); CodeDeploy supports EC2/on-prem, ECS and Lambda traffic shifting.

### Operations ([15](../15-Monitoring-Operations-and-Continuous-Improvement/15-Monitoring-Operations-and-Continuous-Improvement.md))
139. CloudTrail = who did what (API); Config = what resources looked like and compliance; CloudWatch = metrics, logs, alarms.
140. Session Manager replaces bastions and SSH keys, with full audit logging.
141. Patch Manager + maintenance windows patches EC2 and on-prem fleets.
142. EventBridge + SSM Automation (or Lambda) = event-driven auto-remediation.
143. Compute Optimizer recommends right-sizing for EC2, ASG, EBS, Lambda, ECS on Fargate and RDS.
144. Centralised logging: subscription filters → Firehose → S3 in the log archive account.

### Cost ([16](../16-Cost-Optimization-and-FinOps/16-Cost-Optimization-and-FinOps.md))
145. Compute Savings Plan (~66%) covers EC2 any family/Region, Fargate and Lambda; EC2 Instance SP (~72%) is locked to a family in a Region.
146. Savings Plans and RIs give a discount but not guaranteed capacity (except zonal RIs); ODCR gives capacity.
147. Budgets actions can apply SCPs/IAM policies or stop instances automatically when thresholds are crossed.
148. Cost Anomaly Detection catches unexpected spend; Cost Categories + tags + CUR 2.0 enable chargeback.
149. S3 gateway endpoints remove NAT gateway processing charges for S3 traffic.
150. Graviton, Spot, right-sizing, lifecycle tiers and serverless for spiky loads are the standard cost levers — but never at the expense of a stated RTO/RPO or compliance requirement.

---

## 3. Final 7-day revision plan (Sat 24 Oct → Fri 30 Oct 2026)

> This is days 8–14 of the plan in [00-README-Start-Here.md](../00-README-Start-Here.md). The **main track** finishes the remaining chapters and papers. The **revision layer** (45–60 min a day) uses [Chapter 18](../18-Cheat-Sheets-and-Comparisons/18-Cheat-Sheets-and-Comparisons.md) and this chapter. If you finish all chapters early, do only the revision layer plus your error log.
>
> **Error log rule:** for every missed question, write one line: *topic → why I chose wrong → rule to remember*. Re-read the whole log every evening.

| Day | Date | Main track | Revision layer (Ch 18 / Ch 19) | Target / output |
|---|---|---|---|---|
| 1 | **Sat 24 Oct** | [10 Integration](../10-Application-Integration-and-Event-Driven/10-Application-Integration-and-Event-Driven.md) → [11 Analytics/AI](../11-Analytics-Streaming-and-AI-ML/11-Analytics-Streaming-and-AI-ML.md) → **[Paper 2](../17-Practice-Papers/Paper-02-New-Solutions-Serverless-Data.md)** timed (48 min) | Ch 18 §1A–1C phrase drill (cover the answers); Ch 18 §3.1–3.6 tables; glossary A–D | Paper 2 ≥ 14/20. Messaging tree (§4.6) drawn from memory |
| 2 | **Sun 25 Oct** | [13 Migration](../13-Migration-and-Modernization/13-Migration-and-Modernization.md) → **[Paper 4](../17-Practice-Papers/Paper-04-Migration-Modernization.md)** timed | Ch 18 §1D–1H; §4.5 migration tree; §5 rename table (all rows); glossary E–L | 7 Rs + tool-per-source table memorised. Rename table: 100% |
| 3 | **Mon 26 Oct** | [14 Deployment/IaC](../14-Deployment-DevOps-and-IaC/14-Deployment-DevOps-and-IaC.md) → [15 Operations](../15-Monitoring-Operations-and-Continuous-Improvement/15-Monitoring-Operations-and-Continuous-Improvement.md) | Ch 18 §2 numbers (bold rows), §3.25–3.29; glossary M–R; Facts 1–50 aloud | Numbers quiz on bold rows ≥ 90% |
| 4 | **Tue 27 Oct** | [16 Cost](../16-Cost-Optimization-and-FinOps/16-Cost-Optimization-and-FinOps.md) → **[Paper 3](../17-Practice-Papers/Paper-03-Continuous-Improvement-Operations.md)** timed | Ch 18 §1I–1P; §3.26–3.27; glossary S–Z; Facts 51–100 aloud | Paper 3 ≥ 14/20 |
| 5 | **Wed 28 Oct** | **[Paper 5 (hardest)](../17-Practice-Papers/Paper-05-Full-Mixed-Hard.md)** under full exam conditions → re-study your 2 weakest chapters (by error log) | Ch 18 §4.1–4.4 trees from memory on blank paper; Facts 101–150 aloud | Paper 5 ≥ 13/20. Weak-area list ≤ 5 items |
| 6 | **Thu 29 Oct** | Redo **every** question you missed across [Paper 00](../17-Practice-Papers/Paper-00-Official-AWS-Sample-Questions-Explained.md), [Paper 1](../17-Practice-Papers/Paper-01-Governance-Networking-Hybrid.md)–[Paper 5](../17-Practice-Papers/Paper-05-Full-Mixed-Hard.md) and chapter questions, without looking at answers first | Whole of Ch 18 once at speed (≈ 2 h); X vs Y "decisive difference" lines only | Every redo correct, with the reason stated |
| 7 | **Fri 30 Oct** | Light day: this chapter §2 (Top 150) once, §4 playbook twice, [01](../01-Exam-Blueprint-and-Strategy/01-Exam-Blueprint-and-Strategy.md) §3–5 (question anatomy, answering method, distractor patterns) | Error log one final pass. **No new material, no full paper.** Prepare ID, room/route, system test | **Stop by 7 pm. Sleep 8 h** |
| — | **Sat 31 Oct** | **EXAM** | 20 min max: glance at the Ch 18 §2 bold numbers and your error log. Nothing else | Follow §4 below |

**If you are behind schedule:** drop the remaining depth reading, not the papers. The priority order is: Paper 5 → redo misses → Ch 18 §1 + §3 → Top 150 → remaining chapters' "Exam keyword → answer" and "Traps & distractors" sections only.

**If a paper score is below target:** use that paper's *Score interpretation* section to pick chapters. Spend the next morning on the "Traps & distractors" and "Decision tables" sections of those chapters, not a full re-read.

---

## 4. Exam-day playbook

### 4.1 Time management (180 min, 75 questions ≈ 2.4 min each)

| Checkpoint | Question # | Elapsed time | Time left |
|---|---|---|---|
| Start | 1 | 0:00 | 3:00 |
| ⅓ | 25 | ≤ 0:55 | ≥ 2:05 |
| ⅔ | 50 | ≤ 1:50 | ≥ 1:10 |
| End of first pass | 75 | ≤ 2:40 | ≥ 0:20 |
| Review flagged | — | 2:40 – 2:55 | 0:05 buffer |

- Your first pass target is **~2 min per question**, leaving ~20 minutes to review flagged questions.
- **Two-pass method.** Pass 1: answer every question. If you are not confident within ~2.5 min, choose your best answer, **flag it**, and move on. Never leave a question blank on pass 1, in case time runs out. Pass 2: revisit flagged questions only.
- **Hard stop rule:** if a question passes 4 minutes, pick the best remaining option, flag, and move on. One question is worth the same as any other.
- Don't revisit unflagged questions. First instincts are usually right unless you find a concrete reason (a missed constraint) to change.
- Watch for fatigue around questions 45–60. Take a 20-second pause: eyes closed, three slow breaths, shoulders down.

### 4.2 Reading long SAP stems

1. **Read the last sentence first.** It holds the actual question and the deciding constraint ("MOST cost-effective", "LEAST operational overhead", "meets the RTO", "Select TWO").
2. **Read the stem and mark constraints.** On the whiteboard, write short tokens: `RTO 15m`, `RPO 1m`, `$`, `ops↓`, `no code chg`, `compliance: in-Region`, `timeline 2 wk`, `existing: Oracle/VMware/DX`.
3. **Classify the domain:** governance, network, DR, migration, data, cost? This brings up the right decision tree from [Chapter 18 §4](../18-Cheat-Sheets-and-Comparisons/18-Cheat-Sheets-and-Comparisons.md#4-decision-trees).
4. **Predict the answer before reading the options.** Then look for the option that matches your prediction.
5. **Compare options by their differences.** SAP options often share 70% of their text. Spot the 1–2 words that differ (e.g., "gateway endpoint" vs "interface endpoint", "Standard" vs "Express") and decide on those.

### 4.3 Elimination technique

Eliminate any option that:
- **Breaks a hard limit:** Lambda > 15 min, Express workflow with callbacks, DynamoDB item > 400 KB, VPC peering used transitively, gateway endpoint used from on-prem, SCP that "grants" access.
- **Ignores a stated constraint:** single-AZ for an HA requirement, backup-and-restore for a 5-minute RTO, internet path when the stem says "must not traverse the internet".
- **Adds avoidable operational overhead:** self-managed EC2/cron/custom scripts when a managed feature exists (unless the stem forbids the managed service).
- **Uses long-term credentials:** access keys on instances, shared IAM users for third parties.
- **Solves a different problem:** e.g., Inspector for "detect crypto-mining" (that's GuardDuty), CloudTrail for "configuration history" (that's Config).
- **Is over-engineered for the requirement:** multi-site active/active when warm standby meets the RTO at lower cost; Cloud WAN for 3 VPCs in one Region.
- **Uses a retired service when a current one is offered** (e.g., QLDB, App Runner for new customers, OpsWorks). See [Chapter 18 §5](../18-Cheat-Sheets-and-Comparisons/18-Cheat-Sheets-and-Comparisons.md#5-service-renames-and-retired--limited-availability-services).

If two options remain: choose the one that is **more managed, more secure by default, and meets the constraint with fewer moving parts**.

### 4.4 Multi-select tactics ("Select TWO/THREE")

- Treat each option as **true/false on its own** against the stem. Don't hunt for a "pair" first.
- The correct options usually solve **different parts** of the requirement (e.g., one for data replication, one for traffic failover). Two options doing the same job are often one right + one distractor, or both wrong.
- If one option is clearly correct, look for its **natural complement** (e.g., "Resolver inbound endpoint" + "conditional forwarder on on-prem DNS"; "SCP deny" + "move accounts to OU").
- Beware options that are true statements but don't address the question.
- Select **exactly** the number asked. There is no partial credit.

### 4.5 Guessing rules

- **Answer every question.** No penalty for wrong answers; a blank is a guaranteed zero.
- 10 questions are unscored, and you can't tell which. Don't let a strange question shake you; it may not even count.
- When guessing, eliminate what you can, then prefer the managed/serverless, least-privilege, multi-AZ, data-plane-based option that fits the main constraint.

### 4.6 Online-proctored (Pearson VUE OnVUE) vs test-center checklist

> Rules summarised from the AWS Certification "During testing" policy page (checked October 2026). Re-read your confirmation email and the Pearson VUE OnVUE requirements: they are the binding rules for your appointment.

| Item | Online (OnVUE) | Test center |
|---|---|---|
| Arrive / launch | Launch up to **30 min before** the appointment. **More than 15 min late = no-show, fee forfeited** | Arrive **15–30 min early** |
| ID | **One** primary ID: original, unexpired, government-issued, name in Roman characters matching your AWS Certification account, photo + signature | **Two** IDs: two primary, or one primary + one secondary; names must match |
| System check | Run the OnVUE **system test** on the **same computer, network and room** in advance. Corporate laptops/VPNs/proxies often block it — use a personal machine if possible | Not needed |
| Breaks | **None.** You may not leave the camera view or stand up for any reason, including restroom | No scheduled breaks. Unscheduled breaks allowed, but the **clock keeps running** and you can't leave the building |
| Environment | Quiet, private, closed room; clear desk; no other people; phone out of reach (the proctor may ask you to show it); no second monitor; webcam shows you the whole time | Lockers for belongings; center provides noteboard/whiteboard |
| Notes | Use the on-screen whiteboard/notes tool provided; don't use paper unless your appointment rules explicitly allow it | Erasable noteboard provided |
| Behaviour | Keep eyes on screen; don't read aloud or cover your mouth; avoid looking away repeatedly | Normal exam-room rules |
| Problems | Use the OnVUE chat to contact the proctor; for disputes, contact AWS Certification support (Pearson VUE can't review AWS proctoring decisions) | Tell the test administrator immediately |

**Night-before setup (online):** reboot; close all apps; disable notifications and auto-updates; plug in the laptop; wired network if possible; remove extra monitors; clear the desk and walls near you; put your ID on the desk; keep a glass of water only if your appointment rules allow it.

**Non-native English speakers:** AWS offers an **ESL +30 minutes** accommodation for exams taken in English. It is requested once in your AWS Certification account (exam accommodations) *before registering* for an exam, and then applies to future registrations. AWS's policy page doesn't describe adding it to an appointment that is already booked. If you're eligible and haven't requested it, ask AWS Certification support today whether rescheduling is needed, and weigh that against the exam-date rules.

### 4.7 Mental & physical preparation

- **Sleep** 7–9 hours on Thursday and Friday nights. Sleep matters more than one more paper.
- **Eat** a normal meal 1–2 hours before. Avoid heavy food and too much caffeine (no breaks online).
- **Restroom** right before check-in, especially online.
- **Warm-up (10 min):** read 5 rows of Ch 18 §1 and redraw the DR tree. Don't attempt new questions.
- **During the exam:** if you feel stuck or anxious, flag, take three slow breaths, and move on. Expect several questions you can't answer with certainty. That is normal at Professional level, and 750 doesn't require perfection.
- **Mindset:** you're not hunting for a perfect architecture. You're picking the **best of four** under the stated constraints.

### 4.8 After the exam

- Results are posted to your AWS Certification account within **five business days** (longer if held for review).
- If you don't pass, the score report shows performance by domain. AWS requires a **14-calendar-day** wait before a retake, and you pay the full fee again. Remember SAP-C02's last exam date is **16 Nov 2026**; SAP-C03 starts 17 Nov 2026.

---

## 5. Final checklist

**Knowledge (tick by Friday):**
- [ ] I can recite the DR spectrum with typical RTO/RPO and AWS services for each.
- [ ] I can draw hub-and-spoke TGW + inspection VPC + DX gateway + Resolver endpoints from memory.
- [ ] I know when SCP vs RCP vs permissions boundary vs resource policy applies.
- [ ] I can name the decisive difference for every table in [Chapter 18 §3](../18-Cheat-Sheets-and-Comparisons/18-Cheat-Sheets-and-Comparisons.md#3-x-vs-y-comparison-tables).
- [ ] I know every **bold** number in [Chapter 18 §2](../18-Cheat-Sheets-and-Comparisons/18-Cheat-Sheets-and-Comparisons.md#2-numbers--limits), including the exam-view values.
- [ ] I know the old and new names of renamed services and which services are retired or closed.
- [ ] My error log is reviewed and every missed question has been redone correctly.

**Logistics (tick by Friday 7 pm):**
- [ ] Appointment time and time zone confirmed in the confirmation email.
- [ ] ID(s) checked: original, unexpired, name matches the AWS Certification account exactly.
- [ ] Online: system test passed on the exam machine and network; room prepared; phone away.
- [ ] Test center: route, travel time and parking checked; plan to arrive 30 min early.
- [ ] Alarm set; meal and water planned; restroom before check-in.

---

## 6. References

- AWS Certified Solutions Architect – Professional (SAP-C02) exam guide: https://docs.aws.amazon.com/aws-certification/latest/solutions-architect-professional-02/solutions-architect-professional-02.html
- AWS Certification exam page (SAP): https://aws.amazon.com/certification/certified-solutions-architect-professional/
- AWS Certification policies — during testing: https://aws.amazon.com/certification/policies/during-testing/
- AWS Certification policies — before testing (accommodations, ESL +30): https://aws.amazon.com/certification/policies/before-testing/
- AWS Certification policies — after testing (results, retakes): https://aws.amazon.com/certification/policies/after-testing/
- AWS Training & Certification blog — tips for online proctored exams: https://aws.amazon.com/blogs/training-and-certification/5-tips-for-a-successful-online-proctored-aws-certification-exam/
- AWS Well-Architected Framework: https://docs.aws.amazon.com/wellarchitected/latest/framework/welcome.html
- Disaster recovery of workloads on AWS (whitepaper): https://docs.aws.amazon.com/whitepapers/latest/disaster-recovery-workloads-on-aws/disaster-recovery-workloads-on-aws.html
- Organizing your AWS environment using multiple accounts (whitepaper): https://docs.aws.amazon.com/whitepapers/latest/organizing-your-aws-environment/organizing-your-aws-environment.html
- IAM policy evaluation logic: https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_policies_evaluation-logic.html
- AWS service quotas (General Reference): https://docs.aws.amazon.com/general/latest/gr/aws_service_limits.html
- AWS lifecycle changes (maintenance / sunset / shutdown): https://docs.aws.amazon.com/general/latest/gr/service-lifecycle.html

---

> [← Previous: Cheat Sheets & Comparisons](../18-Cheat-Sheets-and-Comparisons/18-Cheat-Sheets-and-Comparisons.md) · [Index](../00-README-Start-Here.md) · [Next →: Back to the start](../00-README-Start-Here.md)
>
> **Good luck on Saturday 31 October.** Read the last sentence first, mark the constraints, eliminate what breaks them, and pick the most managed option that meets them all.
