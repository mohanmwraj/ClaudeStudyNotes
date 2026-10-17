# Chapter 07 — Compute: EC2, Auto Scaling, Load Balancing, Containers & Lambda
> **Exam mapping:** D2 Task 2.1, 2.4, 2.5, 2.6 · D3 Task 3.3, 3.4, 3.5 · D4 Task 4.3, 4.4 | **Weight signal:** High | **Study time:** ~7 h
> [← Previous](06-Security-Data-Protection-and-Threat-Detection.md) · [Index](00-README-Start-Here.md) · [Next →](08-Storage-and-Data-Transfer.md)

---

## 1. What the exam really tests here

Compute shows up in roughly a third of SAP-C02 questions, often as the "glue" in a bigger scenario. You will rarely be asked "what is an ALB". You will be asked to **pick the compute platform, scaling model, load balancer and purchase option that meets several constraints at once**. Typical decisions:

| Decision | What the stem gives you | What you must decide |
|---|---|---|
| **Platform selection** (D2 2.1, D4 4.3) | Runtime length, statefulness, team skills, "least operational overhead", existing Kubernetes investment, licensing | EC2 vs ECS vs EKS vs Fargate vs Lambda vs Batch vs Beanstalk |
| **Scaling design** (D2 2.4/2.5, D3 3.3) | Traffic pattern (spiky, cyclical, scheduled), boot time, SLA | Target tracking vs step vs scheduled vs predictive; warm pools; provisioned concurrency |
| **Cost** (D2 2.6, D3 3.5) | Interruptible? Steady base load? Licence constraints? | Spot + On-Demand mix, Graviton, Savings Plans, right-sizing, Fargate Spot |
| **Resilience** (D2 2.4, D3 3.4) | Multi-AZ, health checks, deployments without downtime | ELB health checks in ASG, instance refresh, blue/green, capacity reservations |
| **Networking edge** (D1/D2) | Static IPs, client IP preservation, TLS end-to-end, PrivateLink, appliances | ALB vs NLB vs GWLB, Proxy Protocol v2, X-Forwarded-For |
| **Modernization** (D4 4.4) | Monolith on EC2, Windows/.NET, cron servers, batch scripts | Containers, Lambda, Batch, Step Functions; what to refactor vs rehost |
| **Licensing & compliance** | BYOL per-socket/core, single-tenant hardware | Dedicated Hosts vs Dedicated Instances, host affinity, License Manager |

Professional-level twist: the "obvious" answer usually violates one constraint (e.g., Lambda for a 40-minute job, Spot for a stateful database, ALB when a static IP is required, IRSA when the stem says "dozens of clusters, minimize trust-policy management").

---

## 2. Core concepts & services — deep dive

### 2.1 Amazon EC2 fundamentals for architects

#### Instance families (know the letters)

| Family | Letters | Use | Exam signal |
|---|---|---|---|
| General purpose | **M**, **T** (burstable, CPU credits), Mac | Web/app tiers, balanced | T = dev/test, low steady CPU; *unlimited mode* can surprise on cost |
| Compute optimized | **C** | Batch, gaming, ad serving, HPC front ends, video encoding | "CPU-bound" |
| Memory optimized | **R**, **X**, **z** (high frequency), **u-** (High Memory, SAP HANA) | In-memory DBs, SAP, caches | "SAP HANA", "large in-memory" |
| Storage optimized | **I** (NVMe), **D** (dense HDD), **H** | NoSQL, data warehousing, HDFS | "high random IOPS on local disk" — instance store is ephemeral |
| Accelerated | **P** (GPU training), **G** (graphics/inference), **Inf** (Inferentia), **Trn** (Trainium), **F** (FPGA) | ML, rendering | "lowest cost inference" → Inferentia; "training" → Trn/P |
| HPC | **Hpc** (e.g. Hpc7g, Hpc7a) | Tightly coupled MPI | EFA built-in, cluster placement |

Suffixes: **g** = Graviton (Arm), **a** = AMD, **i** = Intel, **d** = local NVMe instance store, **n** = enhanced networking, **e** = extra memory/storage, **flex** = lower-cost variant that does not always deliver full CPU.

**AWS Graviton** (Arm64): AWS-designed processors offering better price-performance than comparable x86 (AWS cites up to ~40% for Graviton2-era comparisons; newer generations improve further). Supported by EC2, Lambda (arm64), Fargate, ECS, EKS, RDS, ElastiCache, OpenSearch, etc. **Caveat:** the workload and all native dependencies must be compiled for Arm64; Windows is not supported on Graviton EC2. For interpreted languages (Python, Node.js, Java) migration is often trivial — a classic "reduce cost with minimal changes" answer.

#### AWS Nitro System

- **Nitro Cards** offload VPC networking, EBS, instance storage and monitoring to dedicated hardware; **Nitro Security Chip** and a lightweight **Nitro Hypervisor** give near-bare-metal performance.
- Enables: bare-metal instances, EBS encryption at no performance penalty, higher ENI/EBS limits, **ENA Express**, **NitroTPM**, IMDS IPv6 endpoint, hibernation on more families.
- **Nitro Enclaves**: isolated VM carved from the parent instance — no persistent storage, no interactive access, no external networking (only a vsock channel to the parent). Cryptographic **attestation** integrates with KMS key policies so only a measured enclave image can decrypt. Exam: "process PII/keys so that even root on the instance cannot read them".
- No AWS operator access to customer memory on Nitro — a common compliance talking point.

#### Enhanced networking: ENA, ENA Express, EFA

| Feature | What it is | When |
|---|---|---|
| **ENA** (Elastic Network Adapter) | SR-IOV enhanced networking on all current-generation instances; tens to hundreds of Gbps depending on size | Default; "higher PPS, lower latency" |
| **ENA Express** | Uses AWS **SRD** (Scalable Reliable Datagram) to raise single-flow TCP/UDP bandwidth (up to 25 Gbps vs 5 Gbps standard) and reduce tail latency between supported instances **in the same AZ** | Single large flows (storage replication, media) |
| **EFA** (Elastic Fabric Adapter) | ENA + **OS-bypass** interface (libfabric) for MPI and NCCL; SRD transport | **Tightly coupled HPC & distributed ML training**. OS-bypass traffic does not cross subnets — keep nodes in one subnet/AZ, usually in a **cluster placement group** |

Single-flow limits worth knowing: outside a cluster placement group a single flow is limited to **5 Gbps**; inside a cluster placement group up to **10 Gbps** (ENA Express up to 25 Gbps). Traffic to the internet or over Direct Connect from a cluster placement group is limited to 5 Gbps per flow.

#### Placement groups (verified limits)

| Strategy | Placement | Limits & rules | Use |
|---|---|---|---|
| **Cluster** | Packed close together in **one AZ**, high-bisection-bandwidth segment | Cannot span AZs; can span **peered VPCs in the same Region**; burstable (T) not supported; launch all instances in **one request**, same instance type, to avoid `InsufficientInstanceCapacity`. Reserve capacity with an **ODCR targeted at the cluster placement group** (zonal RIs cannot). Capacity Blocks for ML do not support placement groups | HPC, low-latency, high-throughput east-west traffic |
| **Partition** | Instances split into partitions, each on its **own set of racks** (separate power/network) | **Max 7 partitions per AZ**; can span multiple AZs in a Region; no instance limit beyond account limits; partition metadata exposed to topology-aware apps; Dedicated Instances limited to 2 partitions; Capacity Reservations do not reserve capacity in partition PGs | HDFS, HBase, Cassandra, Kafka — large replicated systems |
| **Spread** | Each instance on **distinct hardware (rack)** | **Max 7 running instances per AZ per group** (rack-level); can span AZs (e.g., 21 in a 3-AZ Region); host-level spread only on **Outposts**; not supported for Dedicated Instances | Small number of critical instances (e.g., 3 quorum nodes, primary/secondary) |

Trap: "12 critical instances on separate hardware in one AZ" → a single spread group cannot do it (7/AZ max); use multiple spread groups or partition strategy.

(Newer: **precision time placement groups** for microsecond clock accuracy — niche, not core.)

#### Tenancy: Dedicated Hosts vs Dedicated Instances

| | **Dedicated Instance** | **Dedicated Host** |
|---|---|---|
| Hardware | Single-tenant hardware for your account | A **whole physical server** allocated to you |
| Visibility | No visibility of sockets/cores/host ID | **Sockets, physical cores, host ID visible** |
| Billing | Per instance (+ a per-Region dedicated fee) | Per host (On-Demand, Host Reservation, or Savings Plans) |
| Placement control | None | **Host affinity** (instance restarts on the same host), **auto-placement**, targeted launch |
| BYOL | Limited (licences tied to VM/user OK) | **Per-socket / per-core / per-VM licences** (Windows Server, SQL Server, Oracle, RHEL, SUSE) — use with **AWS License Manager** + host resource groups for automated host allocation and licence tracking |
| Compliance | Single tenancy requirement | Single tenancy + licence/server-bound requirements |
| Other | Can mix with shared instances in the VPC | **Host recovery** auto-moves instances to a new host on hardware failure |

Exam rule: **"existing per-core / per-socket licences", "licence mobility tied to physical server", "must keep the instance on the same physical server after stop/start"** → **Dedicated Host with host affinity**. "Just needs single-tenant hardware" → Dedicated Instance (cheaper to operate).

#### Capacity: reservations and purchase options

| Option | Capacity guarantee? | Discount? | Notes |
|---|---|---|---|
| **On-Demand Capacity Reservation (ODCR)** | **Yes**, in a specific AZ, for a specific instance type/platform | No by itself — billed at On-Demand rate **whether used or not**; combine with **Regional RIs or Savings Plans** for discount | No term; create/cancel anytime; share via **AWS RAM**; group into Capacity Reservation groups; "open" vs "targeted" matching; can target a cluster placement group. **Future-dated** ODCRs let you reserve for a start date (with a minimum commitment) |
| **Capacity Blocks for ML** | Yes, GPU/Trainium capacity for a defined window | Priced per block | Reserve future GPU clusters for training runs |
| **Zonal Reserved Instance** | Yes (in the AZ) | Yes | Legacy; 1/3-year |
| **Regional RI / Savings Plans** | **No** | Yes | Compute Savings Plans also apply to **Fargate and Lambda** |
| **Spot** | No — reclaimable with **2-minute notice** | Up to ~90% | Rebalance recommendation signal arrives earlier (best-effort) |

Exam: "guarantee capacity in a specific AZ for a DR event / Black Friday, no long-term commitment" → **ODCR** (pair with Savings Plans for discount). "Discount only" → Savings Plans. Detailed purchase strategy is in the cost chapter.

#### Hibernation

- Saves RAM to the **encrypted EBS root volume**, then stops; on start the RAM is restored and processes resume (warm caches, long-initializing apps).
- Prerequisites (verified): enabled **at launch only**; root must be **EBS** (gp2/gp3/io1/io2), **encrypted**, large enough for RAM; Linux RAM **< 150 GiB**, Windows ≤ 16 GiB; supported families only; no bare metal; Spot supported only with **persistent** requests. An instance cannot stay hibernated indefinitely (AWS documents a 60-day maximum).
- Also used as a **warm pool** state in Auto Scaling.

#### Instance Metadata Service v2 (IMDSv2)

- Session-oriented: client must `PUT` to obtain a **token**, then send it in a header. Mitigates SSRF and open reverse-proxy credential theft (IMDSv1 is a simple GET).
- **Hop limit** (`HttpPutResponseHopLimit`): default 1 for many AMIs; set **2 for containers** on EC2 (the extra hop through the container network namespace), otherwise container SDK calls time out.
- Enforcement levers: launch parameter `HttpTokens=required`; **AMI attribute `imds-support v2.0`** (irreversible on that AMI); **account-level IMDS defaults per Region**, and **account-level enforcement** (launches that do not require IMDSv2 fail); IAM condition `ec2:MetadataHttpTokens`; SCP; and **Organizations declarative policies** for multi-account, multi-Region enforcement. Detect usage with the `MetadataNoToken` CloudWatch metric.

#### AMIs: building, copying, sharing

- AMIs are **Regional**. To use in another Region → **CopyImage** (you can encrypt or re-encrypt with a destination-Region KMS key during copy). DR runbooks must copy AMIs ahead of time (or automate via Image Builder distribution / DLM cross-Region copy).
- **Sharing**: with specific accounts, **Organizations or OUs** (ARN-based launch permissions), or public (blocked by **AMI block public access** account setting). Shared users can launch but not modify/delete; they can create their own AMI from a launched instance.
- **Encrypted AMI sharing (verified)**: snapshots must be encrypted with a **customer managed KMS key** — you **cannot share AMIs encrypted with the AWS managed key (`aws/ebs`)**. Grant target accounts use of the key (key policy/grants: `kms:Decrypt`, `kms:DescribeKey`, `kms:CreateGrant`, `kms:ReEncrypt*`, `kms:GenerateDataKey*`). For Auto Scaling in the consumer account, the **ASG service-linked role** needs a grant on the key. Fix for an `aws/ebs`-encrypted AMI: **copy it re-encrypting with a CMK**, then share. Best practice for consumers: copy the shared AMI into their own account with their own key (removes dependency on the producer's key).
- Governance: **AMI deprecation** dates, **deregistration protection**, **Recycle Bin** for AMIs/snapshots, **Allowed AMIs** account setting (restrict which AMI owners can be used), tag-based "golden AMI" approval with Config rules (`approved-amis-by-id/tag`).

#### EC2 Image Builder

Managed pipeline that **builds, hardens, tests and distributes** AMIs and container images on a schedule or on dependency updates.

- **Image recipe** (parent image + **components** — build & test documents, AWS-managed components such as STIG/CIS hardening), **infrastructure configuration** (instance type, subnet, instance profile), **distribution settings** (copy to multiple **Regions**, share with **accounts/OUs**, update **launch templates**, apply KMS keys), **lifecycle policies** (deprecate/delete old images).
- Integrates with **Amazon Inspector** for CVE scanning, **AWS RAM** to share components/recipes, **EventBridge/SNS** for pipeline events, CloudFormation/CDK for IaC.
- Exam: "automatically patch the golden AMI monthly, distribute to 3 Regions and 40 accounts, update launch templates, lowest operational overhead" → **Image Builder pipeline** (not a hand-rolled Lambda + SSM Automation chain, though SSM Automation `AWS-UpdateLinuxAmi` is the older pattern).

#### Golden AMI vs user-data bootstrapping

| | **Golden (baked) AMI** | **Bootstrap (user data / config mgmt)** | **Hybrid (recommended)** |
|---|---|---|---|
| Boot time | Fast — everything pre-installed | Slow — install at boot | Base OS + agents + runtime baked; app config pulled at boot |
| Consistency | Immutable, tested artifact | Drift risk; depends on external repos at boot time | Good |
| Agility | Rebuild/redistribute AMI for every change | Change script, instantly effective | App version via SSM Parameter Store/AppConfig |
| Failure modes | Stale AMIs if no pipeline | Repo outage = scale-out failure | — |
| Best for | Fast scaling, regulated/hardened builds, ASG scale-out | Rarely changing, dev/test | Most production ASGs |

Exam signal: "instances take 15 minutes to become healthy because of software installation during scale-out" → **bake a golden AMI** (Image Builder) and/or **warm pool**.

---

### 2.2 Amazon EC2 Auto Scaling

#### Building blocks

- **Launch template** (versioned; required for mixed instances, newest features — launch configurations are legacy and no longer receive new instance types).
- **Min / desired / max**, subnets across multiple AZs, **AZ rebalancing** (launches new before terminating to keep AZs balanced).
- **Health checks**: **EC2** status checks (default, always on) — detect only hardware/OS-level impairment. Add **ELB health checks** (and optionally **VPC Lattice** or **EBS** health checks) so that an instance whose application fails the target group health check is **replaced**. **Health check grace period** prevents killing instances that are still booting. **Custom health** via `SetInstanceHealth` API.

> Exam favourite: "Instances behind an ALB return HTTP 500, ALB marks them unhealthy but Auto Scaling never replaces them" → **enable ELB health check type on the ASG**.

#### Scaling policies

| Policy | How it works | Use when | Notes |
|---|---|---|---|
| **Target tracking** | Keep a metric at a target (e.g., CPU 50%, `ALBRequestCountPerTarget` 1000). ASG creates and manages CloudWatch alarms | **Default choice**; metric scales linearly with load | Scale-in is more conservative; can disable scale-in; multiple target tracking policies allowed (scale-out if any says so, scale-in only if all agree) |
| **Step scaling** | CloudWatch alarm + steps (add 2 if 60–80%, add 5 if >80%) | Need different responses for different breach sizes; custom metrics with non-linear behaviour | Continues to respond while scaling activity is in progress; uses instance warm-up |
| **Simple scaling** | One alarm → one adjustment → wait **cooldown** | Legacy | Cooldown (default 300 s) blocks further scaling — slow to react |
| **Scheduled** | Set min/max/desired at a time (cron, time zone) | Known events: business hours, month-end batch, marketing launch | Combine with dynamic policies |
| **Predictive** | ML forecast from history (needs **at least 24 h**, better with 14 days); creates **hourly forecasts for the next 48 h** and launches capacity **ahead** of the forecast. **Forecast-only** mode to evaluate first. Scheduling buffer for long boots | Cyclical daily/weekly patterns where boot time makes reactive scaling too late | Only scales out; pair with target tracking for unexpected spikes |

**Instance warm-up vs cooldown**
- **Default instance warm-up** (recommended to set at group level): new instances' metrics are excluded from aggregated metrics until warmed up, preventing over-scaling. Used by target tracking, step scaling and instance refresh.
- **Cooldown**: applies only to **simple scaling** — pause after an activity.

#### Lifecycle hooks

- Hooks on **launch** (`Pending:Wait`) and **terminate** (`Terminating:Wait`). Default heartbeat timeout **1 hour**; extend with `RecordLifecycleActionHeartbeat` (bounded overall — 48 hours max or 100× heartbeat); finish with `CompleteLifecycleAction` (CONTINUE/ABANDON).
- Notifications via **EventBridge** (preferred), SNS or SQS; action runs in Lambda, SSM Run Command/Automation, or a script on the instance.
- Uses: install/validate software before InService; register with external systems (DNS, licence server, Active Directory join); **drain work and copy logs before termination**; deregister from on-prem config management.

#### Warm pools (verified)

- Pool of **pre-initialized** instances kept **Stopped** (pay EBS only — cheapest), **Hibernated** (RAM preserved; pay EBS), or **Running** (discouraged — full cost). Size = max − desired by default, or `MaxGroupPreparedCapacity`; `MinSize` option; **instance reuse policy** returns scaled-in instances to the pool instead of terminating.
- Use lifecycle hooks so instances finish initialization before being stopped.
- **Limitations**: not supported with **instance weighting**; **no Spot** in a warm-pool mixed instances group (On-Demand only); root volume must be EBS; ECS/EKS need special handling to avoid premature registration.
- Exam: "application needs 10+ minutes to boot/initialize caches, traffic spikes unpredictable, minimize cost" → **warm pool (Stopped/Hibernated) + lifecycle hook**. If the stem mentions Spot heavily, warm pool is not the answer.

#### Instance refresh

- Rolling replacement of instances to roll out a **new launch template version/AMI**. Settings: **minimum healthy percentage** (default 90%), **maximum healthy percentage** (up to 200% → launch before terminate, i.e., zero-capacity-loss), **instance warm-up**, **checkpoints** (pause at % for validation), **skip matching** (don't replace instances already on the desired config), **bake time**, **automatic rollback** on failure or on **CloudWatch alarm**. Replaces InService first, then warm pool instances.
- Alternatives for blue/green on EC2: two ASGs behind weighted target groups, CodeDeploy blue/green (copies ASG), or Beanstalk immutable.

#### Mixed instances policy & Spot

- Up to many instance types (or **attribute-based instance type selection**: vCPU/memory ranges — automatically includes new generations) across **On-Demand + Spot** in one ASG.
- `OnDemandBaseCapacity` (first N instances always On-Demand) and `OnDemandPercentageAboveBaseCapacity` (e.g., 20% OD / 80% Spot above the base).
- **On-Demand allocation**: `prioritized` (launch template order — used to consume ODCRs/RIs) or `lowest-price`.
- **Spot allocation strategies**:

| Strategy | Behaviour | Use |
|---|---|---|
| **price-capacity-optimized** | Picks pools with best capacity availability, then lowest price among them | **AWS recommended default** for most Spot workloads |
| **capacity-optimized** | Deepest pools → lowest interruption likelihood | Interruption-sensitive (long jobs, stateful-ish) |
| **capacity-optimized-prioritized** | Capacity-optimized but honours your priority order on a best-effort basis | Prefer certain types (e.g., Graviton first) |
| **lowest-price** | Cheapest pools (optionally across N pools) | Short, highly interruptible jobs only — highest interruption risk |

- **Instance weighting**: assign capacity units (e.g., `m5.xlarge = 1`, `m5.2xlarge = 2`) so desired capacity is in units (vCPU, task slots).
- **Capacity Rebalancing**: on an **EC2 instance rebalance recommendation** (elevated interruption risk), ASG **proactively launches a replacement Spot instance**, then terminates the at-risk one (runs terminate lifecycle hooks). Pair with lifecycle hooks for graceful drain. Without it, you react only to the 2-minute interruption notice.
- Spot best practices: diversify across **many instance types and all AZs**, stateless/fault-tolerant, checkpointing, use the 2-minute notice (EventBridge `EC2 Spot Instance Interruption Warning` / IMDS `spot/instance-action`).

#### Termination policies

Order of evaluation for the **Default** policy: (1) pick the **AZ with the most instances** (keep balance; considering allocation strategy for mixed groups), (2) instances using the **oldest launch template/config** (or allocation strategy alignment for Spot/OD), (3) instances **closest to the next billing hour**, (4) random. Other built-in policies: `OldestInstance`, `NewestInstance`, `OldestLaunchTemplate`, `OldestLaunchConfiguration`, `ClosestToNextInstanceHour`, `AllocationStrategy`; plus a **custom termination policy via Lambda**. **Instance scale-in protection** protects specific instances (e.g., a node running a long job). Termination lifecycle hooks still run.

#### Other ASG features to know

- **Standby** state (troubleshoot without termination), **suspend processes** (`ReplaceUnhealthy`, `AZRebalance`, `HealthCheck`, `Launch`, `Terminate`...).
- **ARC zonal shift / zonal autoshift** integration and **AZ distribution "balanced best effort"** to keep launching in healthy AZs.
- **Capacity Reservations** usage via launch template targeting.
- Scaling ECS on EC2: use **ECS capacity providers with managed scaling** instead of ASG CPU policies.

---

### 2.3 Elastic Load Balancing

#### Application Load Balancer (Layer 7)

- **Listener rules** (priority-ordered) with **conditions**: `host-header`, `path-pattern`, `http-header`, `http-request-method`, `query-string`, `source-ip`. **Actions**: `forward` (single or **weighted target groups** — up to 5 TGs with weights → canary/blue-green at the LB), `redirect` (HTTP→HTTPS), `fixed-response`, `authenticate-oidc`, `authenticate-cognito`.
- **Targets**: instances, IPs (including on-prem over DX/VPN, peered VPCs), **Lambda functions** (request/response converted to JSON; **1 MB** body limit for Lambda targets), and an ALB can itself be the target of an NLB.
- **Authentication**: on HTTPS listeners, offload user login to **Amazon Cognito user pools** (social/SAML via Cognito) or any **OIDC IdP** (Okta, Entra ID, Ping). ALB passes `x-amzn-oidc-*` headers (JWT with claims) to targets. Keeps auth out of the app — common modernization answer.
- **mTLS**: verify mode (ALB validates client certs against a trust store) or passthrough mode (cert chain sent to targets in headers).
- **Slow start** (30–900 s): linearly ramps traffic to a newly registered target (JIT/cache warm-up). Works only with the **round robin** algorithm — it cannot be enabled with least outstanding requests or weighted random. A target only enters slow start if at least one other healthy target is not in slow start.
- **Routing algorithms**: round robin (default), **least outstanding requests** (variable request cost), **weighted random** with optional **Automatic Target Weights** anomaly mitigation (routes away from targets with elevated 5xx/connection errors; needs ≥3 healthy targets; not with stickiness).
- **Stickiness**: duration-based (ALB cookie `AWSALB`, 1 s – 7 days) or **application-based** (your cookie; does not work with weighted target groups). Stickiness at the TG level and also **target group stickiness** across weighted TGs (to keep a user on blue or green during canary). Stickiness requires cross-zone on.
- **Cross-zone**: **always on at the LB level** for ALB (no inter-AZ data charge for ALB); can be turned off per target group.
- **Security**: security groups, **AWS WAF** integration, Shield Advanced, TLS policies (incl. TLS 1.3, FIPS, PQ-hybrid policies), SNI with multiple certificates (ACM).
- HTTP/2 and **gRPC** to targets, WebSockets, `X-Forwarded-For/Proto/Port` headers added automatically. Desync mitigation mode. Header size hard limits (64 KB request headers).
- **Not supported**: static IPs (use NLB-in-front or **Global Accelerator**), UDP, non-HTTP TCP.

#### Network Load Balancer (Layer 4)

- **TCP, UDP, TCP_UDP, TLS** (and newer QUIC) listeners; millions of requests per second; **ultra-low latency** (flow-hash routing, no HTTP processing).
- **One static IP per AZ** automatically; optionally assign **Elastic IPs** (internet-facing) or choose private IPs (internal). → Firewall allowlisting, DNS-less clients, IoT.
- **Client IP preservation (verified defaults)**: **instance** targets → enabled; **IP** targets with UDP/TCP_UDP → enabled (cannot disable); **IP** targets with **TCP/TLS → disabled by default** (enable via `preserve_client_ip.enabled`). Not available through Transit Gateway paths or for PrivateLink traffic; then use **Proxy Protocol v2**. NAT hairpinning fails with client IP preservation enabled.
- **TLS passthrough**: use a **TCP listener on 443** — NLB does not decrypt; targets hold the certificate (end-to-end encryption, mutual TLS at the app). **TLS listener** = NLB terminates TLS with ACM certs (can re-encrypt to TLS target group).
- **AWS PrivateLink**: an **NLB (or GWLB) is required behind a VPC endpoint service**. Source IP seen by targets is the NLB's private IP — use Proxy Protocol v2 (it includes the **VPC endpoint ID** TLV) if you need consumer identity.
- **Security groups**: NLB **now supports security groups** (since 2023) — but you must associate at least one SG **at creation**; an NLB created without SGs cannot have them added later. Option to not evaluate inbound SG rules for PrivateLink traffic.
- **Targets**: instance, IP, **ALB** (NLB → ALB gives static IPs + L7 routing).
- **Cross-zone**: **off by default**; enabling it incurs **inter-AZ data transfer charges**; can be set at LB or target-group level.
- Health checks TCP/HTTP/HTTPS; connection termination on unhealthy targets (default on), unhealthy draining interval; sticky sessions by source IP (not for TLS listeners).
- DNS failover: unhealthy AZ's IP removed from DNS; ARC **zonal shift** supported.

#### Gateway Load Balancer (Layer 3)

- Transparently inserts **third-party virtual appliances** (firewalls, IDS/IPS, DPI) into traffic paths. Listens on all ports; exchanges traffic with appliances using **GENEVE on UDP 6081**; 5-tuple (or 3/2-tuple) flow stickiness so both directions hit the same appliance.
- Consumers send traffic via **Gateway Load Balancer endpoints** (a PrivateLink endpoint type) placed in route tables (ingress routing on IGW, TGW appliance VPC, etc.). Supports centralized inspection VPC architectures across accounts.
- Cross-zone off by default; MTU 8500. Deep networking patterns are in the networking chapter.

#### Cross-cutting ELB behaviours

| Topic | ALB | NLB | GWLB | CLB (legacy) |
|---|---|---|---|---|
| Cross-zone default | **On** (LB level, always), TG override | **Off** | **Off** | Off via API / on via console |
| Inter-AZ data charge when cross-zone on | No | **Yes** | **Yes** | No |
| Static IP / EIP | No | **Yes** | n/a (endpoint) | No |
| Security groups | Yes | Yes (set at creation) | No (appliance SGs) | Yes |
| Client IP to target | `X-Forwarded-For` header | Preserved (per defaults) or **Proxy Protocol v2** | Preserved (transparent) | XFF / Proxy Protocol v1 |
| Lambda target | **Yes** | No | No | No |
| PrivateLink service | No (front with NLB) | **Yes** | **Yes** (GWLBE) | No |
| WAF | **Yes** | No | No | No |

- **Deregistration delay (connection draining)**: default **300 s** (range 0–3600 s); in-flight requests complete before target removal. Shorten for fast deployments of short requests; lengthen for long uploads/websockets. ASG terminations wait for it.
- **X-Forwarded-For vs Proxy Protocol v2**: XFF is an **HTTP header** (ALB/CLB HTTP). Proxy Protocol v2 is a **binary header prepended to the TCP stream** (NLB) — the target software (nginx, HAProxy, Envoy) **must be configured to parse it** or health checks fail with 400s.
- **Pricing**: hourly + **LCU** (ALB), **NLCU** (NLB), **GLCU** (GWLB) — dimensions: new connections, active connections, processed bytes, rule evaluations (ALB).
- Load balancers scale automatically; for sudden extreme spikes (e.g., flash sale) you can use **LCU reservation / pre-warming** request.

---

### 2.4 AWS Lambda — deep dive

#### Invocation models

| Model | Who invokes | Error handling | Examples |
|---|---|---|---|
| **Synchronous** | Caller waits for response | Caller handles retries; throttles return **429 TooManyRequestsException** | API Gateway, ALB, Function URLs, Cognito triggers, SDK `Invoke` (RequestResponse), Lambda@Edge |
| **Asynchronous** | Event placed on Lambda's **internal queue**; 202 returned | Lambda retries **up to 2 times** (configurable 0–2) with backoff; **maximum event age** 60 s – 6 h; throttles/system errors retried up to 6 h; then **on-failure destination** or **DLQ** | S3, SNS, EventBridge, CloudWatch Logs, SES, CodePipeline, SDK `Event` |
| **Event source mapping (poll-based)** | **Lambda service polls** the source and invokes synchronously with batches | Source-specific: SQS — message returns after visibility timeout, redrive to SQS DLQ, **partial batch response** (`ReportBatchItemFailures`); Kinesis/DynamoDB Streams — retries until success or record expiry → **bisect batch**, **maximum retry attempts**, **maximum record age**, **on-failure destination** | SQS (standard/FIFO), Kinesis Data Streams, DynamoDB Streams, Amazon MSK / self-managed Kafka, Amazon MQ, DocumentDB change streams |

- **Destinations** (async & stream ESMs): on success / on failure → SQS, SNS, Lambda, EventBridge, and S3 (on failure). Include **invocation record** (request + response/error context) — richer than a **DLQ** (SQS/SNS, failures only, payload only). Prefer destinations in new designs.
- Kinesis/DynamoDB Streams scaling: one concurrent batch per shard by default; **parallelization factor up to 10** per shard (ordering kept per partition key). Tumbling windows for stateful aggregation.
- SQS ESM: scales up pollers automatically; **maximum concurrency** setting on the ESM caps concurrent invocations for that source (better than reserved concurrency, which causes throttled messages to bounce back to the queue). Set queue **visibility timeout ≥ 6× function timeout** (AWS guidance).
- **Provisioned mode** for Kafka (and SQS) ESMs: pre-provisioned pollers for high, predictable throughput.

#### Concurrency, scaling and throttling

- **Concurrency = requests per second × average duration (s)**. Each execution environment processes one request at a time (standard Lambda).
- **Account concurrency quota**: **1,000 per Region by default** (soft — raise to tens of thousands). New accounts may start lower and are raised automatically with usage.
- **Scaling rate (verified)**: each function can add **1,000 execution environments every 10 seconds** (until account limit). Synchronous request rate is also capped at **10× concurrency** RPS.
- **Reserved concurrency**: carves out a guaranteed slice **and caps** the function at that number. **Free.** Uses: protect critical functions from noisy neighbours; protect downstream (e.g., cap at 50 to protect an RDS instance); **set to 0 to "kill switch"** a function. AWS keeps at least 100 unreserved for other functions.
- **Provisioned concurrency**: **pre-initialized** execution environments on a **version or alias** — eliminates cold starts (double-digit ms). **Charged** for the time configured (plus lower duration rate). Scale with **Application Auto Scaling** (scheduled + target tracking on `ProvisionedConcurrencyUtilization`). Counts against reserved/account concurrency. Spillover beyond provisioned uses on-demand concurrency (cold starts).
- **Throttling behaviour**:
  - Synchronous direct invoke → **429 TooManyRequestsException** (`Rate exceeded`) to the caller.
  - **API Gateway**: its own account/stage/method/usage-plan throttles return **429 Too Many Requests** to clients. A function **error or malformed proxy response → 502 Bad Gateway**; integration timeout (29 s default for REST APIs; can be raised for regional/private REST APIs) → **504**. When the **backend Lambda is throttled**, clients typically see a **5xx (often 500)** rather than API Gateway's own 429 — fix with reserved/provisioned concurrency, quota increase, API Gateway throttling set below Lambda capacity, client exponential backoff, or put **SQS between** API and Lambda for asynchronous buffering.
  - Async → events retried for up to 6 h, then destination/DLQ.
  - ESM → Lambda backs off and retries; SQS messages stay in queue.

#### Cold starts and SnapStart

- Cold start = download code, start runtime, run init code. Mitigations: smaller packages, lazy init, more memory (more CPU), **Graviton**, **provisioned concurrency**, **SnapStart**.
- **SnapStart (verified)**: Lambda initializes the function when you **publish a version**, snapshots the Firecracker microVM memory/disk, and resumes new environments from the snapshot. Supports **Java 11+, Python 3.12+, .NET 8+** (zip and container images built on Lambda base images). **Not supported with provisioned concurrency, EFS, or ephemeral storage > 512 MB**; only on **published versions/aliases** (not `$LATEST`). **No additional cost for Java**; Python/.NET pay caching + restoration charges. Code must handle **uniqueness** (random seeds, unique IDs) and stale connections via runtime hooks.
- Choose: strict, predictable sub-100 ms latency at known volume → **provisioned concurrency**; Java/Python/.NET apps with heavy framework init, cost-sensitive → **SnapStart**.

#### Limits (verified — memorize)

| Limit | Value |
|---|---|
| Timeout | **900 s (15 min)** max |
| Memory | **128 MB – 10,240 MB** (1 MB steps); CPU scales with memory — **1,769 MB ≈ 1 vCPU**, up to 6 vCPUs at max |
| `/tmp` ephemeral storage | **512 MB – 10,240 MB** |
| Sync payload | **6 MB** request and **6 MB** response; **response streaming** up to **200 MB** |
| Async payload | **1 MB** (raised from 256 KB) |
| Deployment package (.zip) | **50 MB zipped** direct upload (larger via S3); **250 MB unzipped** including layers |
| Container image | **10 GB** uncompressed (from ECR, same Region) |
| Layers | **5** per function |
| Environment variables | **4 KB** total |
| Concurrent executions | **1,000** per Region default (soft) |
| ENIs per VPC (Hyperplane) | 3,000 default (shared quota) |
| Resource policy | 20 KB |

Anything longer than 15 min → **Step Functions** (orchestrate), **Fargate/ECS task**, **AWS Batch**, or Lambda durable functions (new). Payload > 6 MB → pass an **S3 pointer** (claim-check pattern) or use presigned URLs.

#### Networking: Lambda in a VPC

- Functions always run in an AWS-owned VPC; attaching to **your VPC** places **Hyperplane ENIs** in your chosen subnets. ENIs are created when the function is **created/updated** (not per invocation) and **shared by all functions with the same subnet + security group combination** — so VPC cold-start penalty is gone and IP consumption is small.
- Execution role needs `ec2:CreateNetworkInterface`, `DescribeNetworkInterfaces`, `DeleteNetworkInterface` (`AWSLambdaVPCAccessExecutionRole`).
- A VPC-attached function **has no public IP** — internet/AWS public endpoints need a **NAT gateway** (private subnet) or **VPC endpoints** (S3/DynamoDB gateway endpoints, interface endpoints for others). Placing the function in a public subnet does **not** give internet access.
- Use multiple subnets across AZs for HA. Account-level control: IAM condition keys `lambda:VpcIds`, `lambda:SubnetIds`, `lambda:SecurityGroupIds` to force VPC attachment.

#### Lambda + relational databases: RDS Proxy

- Problem: thousands of concurrent Lambda environments each opening DB connections → `too many connections`, memory pressure, failover delays.
- **Amazon RDS Proxy**: fully managed connection pooler for RDS (MySQL, PostgreSQL, MariaDB, SQL Server) and Aurora. Multiplexes/reuses connections, **reduces failover time** (up to ~66% per AWS) by bypassing DNS propagation, enforces **IAM authentication** and pulls DB credentials from **Secrets Manager**. Runs in your VPC (function must reach it). Alternative: **Aurora Data API** (HTTP, no connection management) or DynamoDB.
- Also throttle concurrency (reserved concurrency) to protect the DB.

#### Layers, versions, aliases, deployment

- **Layers**: share libraries/runtimes/extensions across functions (and across accounts via layer permissions); count toward the 250 MB unzipped limit.
- **Versions** are immutable; **aliases** point to versions and support **weighted routing** between two versions → **CodeDeploy** canary (`Canary10Percent5Minutes`), linear, all-at-once with CloudWatch alarm rollback and pre/post-traffic hooks (SAM `AutoPublishAlias` + `DeploymentPreference`).
- **Extensions** (monitoring agents, secrets caching), **Function URLs** (dedicated HTTPS endpoint, IAM or no auth; CORS), **response streaming**.
- **Code signing** with AWS Signer to only allow trusted code; **Lambda Insights**, X-Ray, **CloudWatch Application Signals**.
- Lambda@Edge and CloudFront Functions: see [Chapter 05](05-Edge-DNS-and-Content-Delivery.md).

#### Cost model

- **Requests** (per 1M) + **duration** (GB-seconds, billed per **1 ms**) + optional provisioned concurrency, SnapStart (non-Java), ephemeral storage above 512 MB, data transfer. Free tier: 1M requests and 400,000 GB-s per month.
- **arm64 (Graviton)** is priced lower per GB-s and typically faster — AWS cites up to 34% better price-performance.
- **Compute Savings Plans** apply to Lambda (duration & provisioned concurrency).
- Use **AWS Lambda Power Tuning** to find the memory sweet spot — more memory can be *cheaper* if duration falls proportionally.
- Anti-pattern for cost: a constantly busy function at high concurrency 24/7 is often cheaper on Fargate/EC2 — or on **Lambda Managed Instances** (below).

#### Emerging Lambda options (not core to SAP-C02)

- **Lambda Managed Instances**: run Lambda functions on current-generation EC2 instances in your account managed by Lambda via a **capacity provider**; one environment can serve **multiple concurrent invocations**; EC2 pricing incl. Savings Plans/RIs; longer timeouts for async/ESM invocations. Good for steady, high-volume workloads.
- **Lambda durable functions**: checkpointed, long-running multi-step executions with waits/callbacks written in code (a code-first alternative to some Step Functions use cases).
- AWS has also introduced further Lambda variants (e.g., Web Functions, MicroVMs) — expect them on SAP-C03, not SAP-C02.

#### Lambda security model

- **Execution role** (what the function can do) vs **resource-based policy** (who can invoke — e.g., S3, SNS, another account, API Gateway). Cross-account invoke = resource policy on the function + caller's IAM permission.
- Secrets: Secrets Manager/Parameter Store (with caching extension), env vars encrypted with KMS (CMK option).
- Runs in Firecracker microVMs; per-function isolation.

---
### 2.5 Amazon ECS (Elastic Container Service)

#### Core objects

- **Cluster** → logical grouping of capacity. **Task definition** (JSON, versioned "revisions") → up to 10 containers, CPU/memory (task- and container-level), image, port mappings, env/secrets (from **Secrets Manager / SSM Parameter Store**), log driver (`awslogs`, **FireLens** for Fluent Bit routing), volumes (bind, Docker volumes, **EFS**, **FSx for Windows**, EBS volumes attached to tasks), `networkMode`, IAM roles, `requiresCompatibilities`.
- **Task** = running instantiation. **Service** = maintains desired count of tasks, integrates with ELB, service auto scaling, deployments, Service Connect.
- **Standalone tasks / scheduled tasks** (EventBridge Scheduler) for batch-style jobs.

#### Launch types & capacity

| Option | You manage | Notes |
|---|---|---|
| **EC2** (ASG capacity provider) | Instances, AMI (ECS-optimized/Bottlerocket), patching, scaling, bin-packing | Max control, GPUs, daemon tasks, custom AMIs, cheapest at high steady utilization with RIs/SP/Spot |
| **Fargate** | Nothing below the task | Serverless, per-task vCPU/memory billing per second; up to **16 vCPU / 120 GB** per task; ephemeral storage **20 GB default, up to 200 GB**; Linux x86/arm64 and Windows; no GPUs, no privileged containers, no daemon scheduling |
| **Fargate Spot** | Nothing | Up to ~70% off Fargate; tasks can be interrupted with **2-minute warning (SIGTERM)**; for fault-tolerant tasks |
| **ECS Managed Instances** (2025) | Choose instance types/attributes; AWS provisions, patches and scales the EC2 instances | Middle ground: EC2 flexibility (GPU, specific families, Graviton) with Fargate-like operations; supports On-Demand, Spot, Capacity Reservations |
| **ECS Anywhere** | Your on-prem/edge servers or other-cloud VMs (SSM agent + ECS agent) | Control plane in AWS; billed per managed instance-hour; "run containers on-prem with the same tooling", data residency, latency to on-prem systems |

- **Capacity providers** and **capacity provider strategy**: `base` (minimum tasks on a provider) + `weight` (ratio). E.g., `FARGATE base=2 weight=1`, `FARGATE_SPOT weight=3` → first 2 tasks on Fargate, then 1:3 Fargate:Spot. For ASG capacity providers, **managed scaling** sizes the ASG from task demand (`CapacityProviderReservation` metric) and **managed termination protection** prevents scale-in of instances still running tasks.

#### IAM: task role vs task execution role (classic exam trap)

| Role | Used by | Permissions for |
|---|---|---|
| **Task execution role** | The **ECS agent / Fargate infrastructure** | **Pull image from ECR**, write logs to CloudWatch Logs, **fetch secrets** from Secrets Manager/SSM referenced in the task definition, pull private registry credentials |
| **Task role** | **Your application code** inside the container | Calling AWS APIs: S3, DynamoDB, SQS, KMS... (credentials via container credentials endpoint) |
| **Container instance role** (EC2 launch type) | ECS agent on the host | Register with cluster, etc. — don't put app permissions here |
| **Infrastructure role** | ECS for managing related resources | EBS volume attachment, Express Mode, Service Connect TLS |

"Task fails with `CannotPullContainerError` / cannot retrieve secret" → **execution role**. "App gets AccessDenied writing to S3" → **task role**.

#### Networking modes

- **awsvpc** (required on Fargate; recommended on EC2): each task gets its **own ENI, private IP and security groups** → task-level SGs, VPC Flow Logs per task, works with IP target groups. On EC2, ENI density per instance is limited → enable **ENI trunking** (`awsvpcTrunking`) to raise task density. IP exhaustion risk in small subnets.
- **bridge** (Docker virtual network, **dynamic host port mapping** with ALB), **host** (container uses host network directly; one task per port per host), **none**.

#### Service auto scaling

- Via **Application Auto Scaling**: target tracking (`ECSServiceAverageCPUUtilization`, `ECSServiceAverageMemoryUtilization`, **`ALBRequestCountPerTarget`**), step scaling (custom metrics such as **SQS backlog per task**), scheduled scaling, and predictive scaling for services.
- Two layers on EC2: **service auto scaling (tasks)** + **capacity provider managed scaling (instances)**. On Fargate only the first.

#### Service discovery and service-to-service

- **Service Connect** (recommended): ECS-managed Envoy sidecar proxy + **AWS Cloud Map** namespace; short names (`http://orders`), client-side load balancing, retries, outlier detection, **TLS** with AWS Private CA, per-service traffic metrics in CloudWatch — **no ALB needed for east-west**. Works across clusters in the same namespace (and across accounts using shared namespaces).
- **Cloud Map service discovery** (DNS A/SRV records) — simpler, no proxy.
- **AWS App Mesh**: AWS announced end of support on **30 September 2026** — migrate ECS workloads to **Service Connect** (EKS workloads to **VPC Lattice** or open-source meshes). Do not pick App Mesh for new designs.
- **VPC Lattice** for cross-VPC/cross-account service networking (ECS integrates natively).

#### Deployment strategies for ECS services

| Strategy | Mechanics | Rollback | When |
|---|---|---|---|
| **Rolling update** (default, `ECS` controller) | `minimumHealthyPercent` / `maximumPercent` control replacement pace | **Deployment circuit breaker** (auto rollback on failed deployment) + **CloudWatch alarm-based rollback** | Most services |
| **ECS built-in blue/green** (native, since 2025) | ECS stands up green tasks, shifts production traffic via ALB/NLB listener rules (or Service Connect), **bake time** keeps blue alive, **lifecycle hooks** (Lambda) at stages for tests | Instant rollback during bake time | Blue/green without CodeDeploy |
| **ECS built-in linear / canary** (Oct 2025) | Shift traffic in fixed % steps (linear) or small % then remainder (canary), with bake times | Automatic on alarms | Gradual risk-controlled releases |
| **CodeDeploy blue/green** (`CODE_DEPLOY` controller) | Two target groups + production/test listeners; `ECSAllAtOnce`, `ECSLinear10PercentEvery1Minutes`, `ECSCanary10Percent5Minutes`... hooks (`BeforeAllowTraffic`, `AfterAllowTraffic`) | Alarm-based automatic rollback | Existing CodeDeploy/CodePipeline estates; still supported, but ECS docs now recommend native blue/green for new work |
| **External** | Third-party controller manages task sets | — | Custom tooling |

Exam reading: SAP-C02 items written before 2025 answer "blue/green on ECS" with **CodeDeploy**, so recognize that pattern. The current Amazon ECS documentation **recommends native ECS blue/green (and linear/canary) over CodeDeploy-based blue/green** for new deployments: fewer moving parts, no separate CodeDeploy application or deployment group. If an option offers native ECS blue/green and the stem stresses least operational overhead, pick it. Keep CodeDeploy when the stem describes an existing CodeDeploy pipeline with hook scripts.

#### Other ECS features

- **ECS Exec** (SSM-based shell into containers, audited), **Container Insights** (enhanced observability), **task scale-in protection**, **EBS volumes for tasks**, **runtime monitoring** via GuardDuty, **Express Mode** (single API call → Fargate service + ALB + HTTPS + auto scaling; AWS's recommended successor to App Runner; no extra charge).
- Pricing: no ECS control-plane charge (pay for EC2 or Fargate resources; ECS Anywhere per-instance fee).

---

### 2.6 Amazon EKS (Elastic Kubernetes Service)

#### Control plane

- AWS-managed Kubernetes API servers and etcd across **3 AZs** in an AWS-owned VPC; cross-account ENIs into your subnets. Endpoint access: **public**, **private**, or both (restrict public by CIDR).
- Charged per cluster-hour; Kubernetes versions get **standard support** (about 14 months) then **extended support** (about 12 more months) at a higher per-cluster-hour price — upgrade planning is a cost item. **Upgrade insights** flag deprecated APIs.
- **Access management**: **EKS access entries** (IAM principal → Kubernetes permissions via EKS API, access policies) replace the legacy `aws-auth` ConfigMap.
- Secrets envelope encryption with KMS; control plane logs to CloudWatch.

#### Data plane options

| Option | What it is | Pros | Cons / limits |
|---|---|---|---|
| **Self-managed nodes** | Your ASG + AMI | Full control (custom AMIs, kernel) | You patch, upgrade, drain |
| **Managed node groups** | EKS-managed ASG of EKS-optimized (AL2023/Bottlerocket) or custom launch template AMIs; graceful drain on upgrade/scale-in; On-Demand or Spot | Easy upgrades, Spot capacity rebalancing | Still node-level capacity planning; scaling via Cluster Autoscaler |
| **Fargate profiles** | Pods matching namespace/labels run on Fargate (one pod per microVM) | No nodes | **No DaemonSets, no privileged pods, no GPUs, no hostNetwork/hostPort**; EFS for persistence (no EBS); per-pod pricing; slower start; ALB must use **IP targets** |
| **Karpenter** | Open-source node autoscaler: watches **unschedulable pods**, launches **right-sized instances directly via EC2 Fleet** (no node groups), **consolidation** (bin-packs and removes underused nodes), Spot interruption handling, drift replacement, NodePools/NodeClasses | Fast, flexible, cost-efficient, many instance types/Spot | You operate the Karpenter controller (unless Auto Mode) |
| **EKS Auto Mode** (Dec 2024) | AWS runs Karpenter-based compute, pod networking, load balancing (ALB/NLB), DNS, **EBS CSI**, GPU plug-ins and Pod Identity as managed core components; nodes are immutable **Bottlerocket**-based EC2 managed instances, no SSH/SSM, **max node lifetime 21 days** (auto-replaced) | Lowest Kubernetes operational overhead; patching handled; Spot & GPU support | Additional per-instance management fee; less node customization |
| **EKS Hybrid Nodes** (Dec 2024) | **On-prem/edge servers join a cloud EKS control plane** as nodes | Reuse on-prem hardware with managed control plane | Needs private connectivity (DX/VPN) and routable remote node/pod CIDRs |
| **EKS Anywhere** | Run EKS Distro clusters **entirely on your infrastructure** (VMware vSphere, bare metal, Nutanix, etc.) — control plane on-prem | Disconnected/air-gapped capable | You operate everything; optional paid support subscription |
| **EKS on Outposts** | Extended clusters (control plane in Region) or **local clusters** (control plane on Outpost, survives disconnection) | Low latency / data residency | Outposts capacity |

#### Pod networking

- **Amazon VPC CNI**: pods get **VPC IP addresses** from node ENIs → native VPC routing, security groups for pods. IP exhaustion fixes: **prefix delegation** (/28 prefixes per ENI slot), **custom networking** with a secondary CIDR (e.g., `100.64.0.0/10`), **IPv6 clusters**. **Network policies** supported natively by VPC CNI.
- **AWS Load Balancer Controller**: Ingress → **ALB**, Service type LoadBalancer → **NLB**, IP-mode targets.

#### Pod-level IAM: IRSA vs EKS Pod Identity

| | **IRSA** (IAM Roles for Service Accounts) | **EKS Pod Identity** (Nov 2023) |
|---|---|---|
| Mechanism | Cluster **OIDC issuer** registered as an IAM OIDC provider; role trust policy trusts that provider + `sub` = service account; SDK calls `AssumeRoleWithWebIdentity` | **Pod Identity Agent** add-on (DaemonSet); **association** (cluster + namespace + service account → role) created via **EKS API**; role trusts service principal `pods.eks.amazonaws.com` |
| Per-cluster setup | OIDC provider per cluster; **trust policy must list each cluster's OIDC provider** (trust policy size limits with many clusters) | **No OIDC provider**; **same role reusable across clusters without editing the trust policy** |
| ABAC | Limited | **Session tags** (cluster name, namespace, service account) for ABAC |
| Cross-account | Role in other account trusts the OIDC provider | Role chaining / target role support in the association |
| Works on | EKS (incl. Fargate), self-managed Kubernetes, EKS Anywhere, ROSA | EKS on EC2 nodes and Auto Mode; **not Fargate pods** |
| Exam signal | "Existing setup", "Fargate", "non-EKS Kubernetes" | "Many clusters", "simplify", "avoid managing OIDC providers / trust policies", "least operational overhead" |

Never use the **node instance role** for application permissions (every pod on the node inherits it) — block pod access to IMDS (hop limit 1 or network policy) when using IRSA/Pod Identity.

#### EKS add-ons

Managed lifecycle (install, version compatibility, upgrade) for: **VPC CNI, CoreDNS, kube-proxy, EBS CSI driver, EFS CSI driver, Pod Identity Agent, ADOT (OpenTelemetry), CloudWatch Observability agent, GuardDuty runtime agent, Mountpoint for S3 CSI**, plus marketplace/community add-ons.

#### ECS vs EKS (how the exam frames it)

- **ECS**: AWS-native, simpler, deep IAM/ALB/CloudWatch integration, no control-plane fee, smaller learning curve → "least operational overhead", "team has no Kubernetes experience".
- **EKS**: Kubernetes API portability, existing Helm charts/operators/GitOps, hybrid/multi-cloud consistency, large ecosystem → "already running Kubernetes on-prem", "must use Kubernetes tooling", "avoid lock-in at the orchestration layer".

---

### 2.7 Amazon ECR (Elastic Container Registry)

- Private registry per account/Region (plus **ECR Public** / Gallery). Repositories hold images and **OCI artifacts** (Helm charts, signatures, SBOMs).
- **Repository policies** for cross-account pull (e.g., workload accounts pull from a central "shared services" registry). Lambda container images and ECS/EKS can pull cross-account with the right policy.
- **Lifecycle policies**: expire images by rule (`imageCountMoreThan`, `sinceImagePushed`, tag status/prefix/wildcards) — cuts storage cost; test with preview.
- **Tag immutability** (prevent overwriting `:prod`), encryption (AES-256 default or **KMS CMK**), **image signing** (AWS Signer / Notation) + admission verification.
- **Replication** (registry-level configuration): **cross-Region** and **cross-account**, filtered by repository prefix; replicates images pushed **after** configuration (existing images are not back-filled). Destination account must allow it via its **registry policy**. Use for multi-Region DR and low-latency pulls.
- **Image scanning**:

| | **Basic scanning** | **Enhanced scanning** |
|---|---|---|
| Engine | ECR (AWS-native CVE database) | **Amazon Inspector** |
| Scope | OS packages | **OS + programming-language packages** (npm, pip, Maven, Go...) |
| When | **On push** or manual | **Continuous** — rescans when new CVEs are published, plus on push |
| Output | ECR console/API, EventBridge | Inspector findings, **Security Hub**, EventBridge; prioritized risk scores |
| Cost | No charge | Inspector pricing |

- **Pull-through cache**: cache images from upstream registries (**ECR Public, Docker Hub, Quay, GitHub Container Registry, GitLab, Azure Container Registry, Kubernetes registry, and other ECR registries**) into your private ECR → avoids Docker Hub rate limits, works from private subnets via ECR VPC endpoints, applies scanning and lifecycle policies to cached images. Credentials for authenticated upstreams live in Secrets Manager.
- **Repository creation templates** apply settings (encryption, lifecycle, tag immutability, policy) to repositories created automatically by replication or pull-through cache.
- Private access: **interface endpoints** `ecr.api` and `ecr.dkr` **plus an S3 gateway endpoint** (image layers are stored in S3) — classic trap for "Fargate tasks in private subnets without NAT cannot pull images". Add a CloudWatch Logs endpoint for `awslogs`.

---

### 2.8 AWS App Runner (status change — read this)

- Fully managed service that deploys a web app from **source code or a container image** with automatic HTTPS, load balancing, scaling, and a VPC connector for private resources.
- **Availability change (verified):** **App Runner closed to new customers on 30 April 2026.** Existing customers can continue to use it, including creating new services, but **no new features** are planned. AWS recommends **Amazon ECS Express Mode** as the replacement and documents a blue/green migration using DNS weighted routing.
- Exam guidance: SAP-C02 items may still present App Runner as the "least operational overhead" answer for a simple containerized web app/API with no infrastructure team — recognize it. For real-world new designs, choose **ECS Express Mode / Fargate**.

---

### 2.9 AWS Elastic Beanstalk

- PaaS orchestration for web apps and workers (Java, .NET on Windows/Linux, Node.js, Python, PHP, Ruby, Go, Docker). Creates EC2/ASG/ELB/CloudWatch resources **in your account** that you can still see and tune (`.ebextensions`, platform hooks, saved configurations).
- **Good fit**: replatforming a traditional web app (especially **.NET/IIS** or Java Tomcat) where the team wants managed patching (**managed platform updates**), health dashboards and simple deployments without learning containers — a common D4 "replatform with minimal changes" answer. Worker environments pull from SQS.
- **Deployment policies (brief)**: all at once, rolling, rolling with additional batch, **immutable** (new ASG, swap), **traffic splitting** (canary on new instances); **blue/green** via environment clone + **CNAME swap** (or Route 53 weighted). Details in [Chapter 14](14-Deployment-DevOps-and-IaC.md).
- **Not a fit**: microservices at scale, fine-grained infra control, event-driven serverless, Kubernetes standardization. An RDS instance created inside the environment is tied to its lifecycle — decouple the database for production.

---

### 2.10 AWS Batch

- Managed batch scheduler: **job definitions** → **job queues** (priority) → **compute environments** (managed **EC2 On-Demand/Spot**, **Fargate/Fargate Spot**, or **EKS** clusters; or unmanaged). No extra charge beyond resources.
- Managed EC2 environments choose instance types (`optimal` or explicit), scale to zero, and support allocation strategies `BEST_FIT_PROGRESSIVE`, `SPOT_CAPACITY_OPTIMIZED`, **`SPOT_PRICE_CAPACITY_OPTIMIZED`** (recommended for Spot).
- **Array jobs**: one submission fans out to **2–10,000 child jobs** (`AWS_BATCH_JOB_ARRAY_INDEX`) — Monte Carlo, rendering frames, genomics samples. **Job dependencies** (N_TO_N, sequential), retry strategies (e.g., retry on Spot reclamation), timeouts.
- **Multi-node parallel (MNP) jobs**: a single job spanning **multiple EC2 instances** (main node + children) for **tightly coupled MPI / distributed training**, combined with **EFA** and **cluster placement groups**. Runs on EC2 compute environments (not Fargate). Because losing one node fails the whole job, prefer On-Demand for long MNP runs.
- **Fair-share scheduling policies** to share queues across teams; **Step Functions** integration for pipelines; EventBridge triggers.
- Batch vs Lambda vs Step Functions: Batch for **long-running, containerized, compute-heavy** jobs (hours, GPUs, large memory); Lambda for short event-driven tasks; Step Functions orchestrates both.

---

### 2.11 HPC on AWS

| Component | Role |
|---|---|
| **AWS ParallelCluster** | Open-source CLI/UI that builds HPC clusters (Slurm) from a YAML config via CloudFormation; head node + dynamic compute fleets (On-Demand/Spot), EFA, FSx for Lustre, shared EBS/EFS |
| **AWS Parallel Computing Service (PCS)** | **Managed Slurm** service (AWS operates the scheduler/controller) — lower operational overhead than ParallelCluster |
| **EFA** | OS-bypass low-latency interconnect for MPI/NCCL (see 2.1) |
| **Cluster placement group** | Physical proximity for low latency / high bisection bandwidth |
| **Hpc instances** (Hpc7g, Hpc7a, Hpc6id...) | HPC-optimized price-performance with EFA |
| **FSx for Lustre** | Parallel file system, sub-ms latency, very high throughput; **S3 data repository association** (lazy load, export) — see [Chapter 08](08-Storage-and-Data-Transfer.md) |
| **AWS Batch** | Loosely coupled / array workloads and MNP |
| **Amazon DCV** (formerly NICE DCV) | Remote visualization of results |

Patterns: **loosely coupled** (embarrassingly parallel: Batch array jobs, Spot, any AZ) vs **tightly coupled** (MPI: single AZ, cluster PG, EFA, On-Demand/Capacity Reservations, FSx for Lustre scratch). Capacity Blocks for ML for scheduled GPU training windows.

---

### 2.12 Outposts, Local Zones and Wavelength (brief — see [Chapter 05](05-Edge-DNS-and-Content-Delivery.md))

- **AWS Outposts** (racks or servers): AWS infrastructure **in your data centre**, managed by AWS, extending a parent Region's VPC (subnets on the Outpost). Run EC2, EBS, ECS, EKS, RDS, EMR, S3 on Outposts locally. Use for **data residency**, **single-digit ms latency to on-prem systems**, local data processing. Requires service link connectivity to the Region (control plane). Host-level spread placement groups exist only on Outposts.
- **Local Zones**: AWS-operated extensions of a Region in metro areas (media rendering, gaming, real-time apps needing low latency to end users in that city). Opt-in; subset of services (EC2, EBS, ECS, EKS, ALB, some RDS...).
- **Wavelength Zones**: compute at telecom carrier 5G edge for mobile ultra-low latency.
- Exam: "must stay on-prem for regulatory reasons but wants AWS APIs" → **Outposts**; "low latency for users in a specific city without own DC" → **Local Zone**.

---

## 3. Architecture patterns

### Pattern 1 — Classic multi-AZ web tier with Spot-heavy ASG

```text
             Route 53 (alias)
                   |
            [ ALB  (WAF) ]   cross-zone on, HTTPS (ACM), OIDC auth optional
          /        |        \
   AZ-a TG      AZ-b TG     AZ-c TG
   +---------------------------------------------+
   | ASG  (launch template, golden AMI)           |
   |  On-Demand base = 4  | above base 25% OD/75% Spot
   |  Spot: price-capacity-optimized, 10+ types   |
   |  Capacity Rebalancing ON, terminate hook     |
   |  Health check type = ELB, warm-up 180 s      |
   |  Target tracking: ALBRequestCountPerTarget   |
   |  Scheduled: +50% at 08:00 Mon-Fri            |
   +---------------------------------------------+
```
**When:** stateless HTTP apps. **Trade-off:** Spot savings vs. interruption churn; sessions must be externalized (ElastiCache/DynamoDB), not sticky.

### Pattern 2 — Static IPs + Layer-7 routing (NLB → ALB)

```text
 Partner firewalls allow-list 3 EIPs
            |
   [ NLB ]  EIP per AZ, TCP:443   (or Global Accelerator: 2 anycast IPs, global)
            |
   target group type = alb
            |
   [ ALB ]  host/path rules, WAF, Cognito/OIDC auth
     /api/* -> ECS service TG      /static/* -> S3 via CloudFront (separate)
```
**When:** clients need fixed IPs but you need path routing/WAF. Alternative: **Global Accelerator** in front of the ALB (static anycast IPs + fast regional failover) — preferred when multi-Region or global users.

### Pattern 3 — Serverless API with protected database

```text
Client -> API Gateway (throttling, usage plans -> 429 to clients)
            |
          Lambda (alias "live", provisioned concurrency 50 + AAS schedule,
            |      reserved concurrency 300 = ceiling)
            |   Hyperplane ENIs in private subnets (2+ AZs)
            v
        RDS Proxy (IAM auth, Secrets Manager) -> Aurora PostgreSQL (Multi-AZ)
            |
   Async side effects: Lambda -> EventBridge / SQS -> worker Lambda
   Failures -> on-failure destination (SQS) for replay
```
**When:** spiky APIs with relational data. **Key decisions:** reserved concurrency caps DB pressure; RDS Proxy pools connections; provisioned concurrency only for latency-critical paths.

### Pattern 4 — Queue-based load leveling with containers

```text
Producers -> SQS queue --(backlog per task metric)--> ECS service on Fargate
                                                     capacity provider strategy:
                                                       FARGATE       base=2 weight=1
                                                       FARGATE_SPOT  weight=4
                                      Step scaling on ApproximateNumberOfMessagesVisible / running tasks
             DLQ (maxReceiveCount=5)  <- poison messages
```
**When:** work that tolerates seconds-to-minutes latency; absorbs bursts; Spot interruptions only delay processing (message reappears after visibility timeout).

### Pattern 5 — Immutable golden AMI pipeline (multi-account)

```text
 Image Builder pipeline (Tooling account, monthly + on CVE)
   recipe: base AMI + CIS hardening + agents (SSM, CW, Inspector)
   test components -> Inspector scan
   distribution: copy to us-east-1, eu-west-1, ap-southeast-2
                 encrypt with per-Region CMK, share with OU "Workloads"
                 update launch template default version in target accounts
        |
 Workload accounts: ASG Instance Refresh (min healthy 90%, max 110%,
                    checkpoints 20%/50%, alarm-based auto rollback)
```
**When:** regulated fleets, fast scale-out, drift elimination.

### Pattern 6 — Kubernetes platform at scale

```text
           EKS (Auto Mode or Karpenter)   access entries for teams
   NodePool "general": Graviton + x86, On-Demand+Spot, consolidation ON
   NodePool "gpu": g6/p5, taints, Capacity Block / ODCR
   Pod Identity associations -> per-service IAM roles (session tags ABAC)
   AWS LB Controller -> ALB (Ingress) / NLB (Service)
   ECR pull-through cache + enhanced scanning, replication to DR Region
   Hybrid Nodes for on-prem GPU servers (via DX)
```

### Pattern 7 — Tightly coupled HPC

```text
 Users -> ParallelCluster / PCS head node (Slurm)
             |
   Compute queue: hpc7a / c7gn with EFA, ONE subnet, cluster placement group
   ODCR targeted to the placement group (or Capacity Block for GPUs)
             |
   FSx for Lustre (scratch/persistent) <- linked S3 bucket (input/output)
   Loosely coupled post-processing -> AWS Batch array jobs on Spot
```

### Pattern 8 — Centralized inspection with GWLB

```text
 Spoke VPCs --TGW--> Inspection VPC: GWLB endpoints -> GWLB -> firewall ASG (GENEVE 6081)
 Internet ingress: IGW edge route table -> GWLBE -> app ALB
```
Detailed in [Chapter 04](04-Networking-VPC-and-Hybrid-Connectivity.md).

---

## 4. Decision tables

### 4.1 Compute platform chooser

| Criterion | EC2 (+ASG) | ECS on EC2 | ECS/EKS on Fargate | EKS (nodes/Auto Mode) | Lambda | App Runner* / ECS Express | AWS Batch |
|---|---|---|---|---|---|---|---|
| Ops overhead | Highest | Medium | Low | Medium–high (low with Auto Mode) | **Lowest** | Very low | Low |
| Max run time | Unlimited | Unlimited | Unlimited | Unlimited | **15 min** | Unlimited (request timeouts apply) | Unlimited |
| Scale to zero | No (min 0 possible but slow) | Tasks yes, instances via CP | Yes | With Karpenter/Auto Mode | **Yes, instantly** | Partial | **Yes** |
| Startup latency | Minutes | Seconds (on warm hosts) | ~tens of seconds | Seconds–minutes | ms–seconds (cold start) | Seconds | Minutes |
| GPU / special HW | **Yes** | Yes | **No** | Yes | No | No | Yes |
| OS / kernel control | **Full** | Host-level | None | Node-level | None | None | Limited |
| Licensing (BYOL, Dedicated Hosts) | **Yes** | Yes | No | Yes | No | No | Limited |
| Pricing grain | Per-second instances | Instances | vCPU/GB-second per task | Instances + cluster fee | Requests + GB-ms | vCPU/GB | Underlying resources |
| Best for | Legacy, licensed, stateful, custom | Dense steady container fleets | Microservices without servers | Kubernetes standard, portability | Event-driven, spiky, glue | Simple web apps/APIs | Large batch/HPC queues |

\* App Runner is closed to new customers since 30 April 2026.

### 4.2 ALB vs NLB vs GWLB

| Need | Choose |
|---|---|
| Path/host/header/query routing, redirects, fixed responses | **ALB** |
| Authenticate users (Cognito/OIDC) at the LB | **ALB** |
| Lambda as target | **ALB** |
| WAF on the load balancer | **ALB** |
| gRPC / HTTP/2 to targets, WebSockets | **ALB** (NLB for raw TCP websockets is also possible) |
| Static IP / Elastic IP per AZ | **NLB** (or Global Accelerator) |
| UDP (DNS, VoIP, gaming, syslog) | **NLB** |
| TLS passthrough / end-to-end encryption with certs only on targets | **NLB TCP listener** |
| Preserve client source IP at the TCP layer | **NLB** (instance targets / enabled attribute) or Proxy Protocol v2 |
| Expose service via **PrivateLink** to other VPCs/accounts | **NLB** (GWLB for appliances) |
| Millions of RPS, lowest latency, long-lived TCP | **NLB** |
| Insert third-party firewalls/IDS transparently | **GWLB** |
| Static IPs **and** L7 routing | **NLB → ALB target** or **Global Accelerator → ALB** |

### 4.3 Scaling policy chooser

| Situation | Policy |
|---|---|
| Metric proportional to load (CPU, requests per target) | **Target tracking** |
| Need bigger reaction to bigger breaches; custom metric | **Step scaling** |
| Known time-based events | **Scheduled** |
| Recurring daily/weekly pattern + slow boot | **Predictive** (+ target tracking for surprises) |
| Long application initialization | **Warm pool** + lifecycle hook (+ predictive) |
| Queue workers | Target tracking on **backlog per instance/task** (custom metric) |
| Lambda latency-critical with predictable peaks | **Provisioned concurrency** with scheduled + target tracking (Application Auto Scaling) |
| ECS service on EC2 | Service auto scaling + **capacity provider managed scaling** |
| Kubernetes nodes | **Karpenter / Auto Mode** (pods: HPA/KEDA) |

### 4.4 Spot suitability

| Workload | Spot? | Notes |
|---|---|---|
| Stateless web/API behind ELB | **Yes (mix)** | OD base + Spot above; diversify; capacity rebalancing |
| Batch, CI/CD runners, rendering, big data (EMR task nodes) | **Yes** | Checkpoint; retries; array jobs |
| Containers (ECS/EKS) stateless | **Yes** | Fargate Spot / Karpenter Spot; handle SIGTERM |
| Tightly coupled MPI over many nodes | **Risky** | One interruption kills the job — On-Demand/ODCR unless checkpointing |
| Databases, single-instance stateful apps, license servers | **No** | Use On-Demand + RIs/Savings Plans |
| Workloads needing guaranteed capacity at a time | **No** | ODCR / Capacity Blocks |
| Warm pool groups | **No** | Warm pools do not support Spot |

### 4.5 Dedicated options and capacity

| Requirement | Answer |
|---|---|
| BYOL per-socket/per-core, visibility of physical cores | **Dedicated Host** (+ License Manager) |
| Instance must return to same physical host after stop/start | **Dedicated Host with host affinity** |
| Single-tenant hardware only, no licence constraints | **Dedicated Instance** |
| Guaranteed capacity in an AZ, no commitment | **On-Demand Capacity Reservation** |
| Discount without capacity guarantee | **Savings Plans / Regional RIs** |
| GPU cluster for a fixed future window | **Capacity Blocks for ML** |

### 4.6 Lambda concurrency controls

| Goal | Control |
|---|---|
| Eliminate cold starts at a known level | **Provisioned concurrency** (cost) |
| Reduce Java/Python/.NET init latency cheaply | **SnapStart** |
| Guarantee capacity for a critical function | **Reserved concurrency** |
| Cap a function to protect downstream | **Reserved concurrency** (or SQS ESM maximum concurrency) |
| Emergency stop | Reserved concurrency = **0** |
| More than 1,000 concurrent across account | **Service Quotas increase** |

---

## 5. Exam keyword → answer cheat list

- "**Least operational overhead**" + containers → **Fargate** (ECS); + Kubernetes → **EKS Auto Mode** / Fargate; + simple web app → App Runner (legacy) / **ECS Express Mode**.
- "Event-driven, **spiky**, short tasks, pay only when used" → **Lambda**.
- "Job runs **longer than 15 minutes**" → not Lambda → **Fargate task / Batch / Step Functions**.
- "**Tolerate interruption**, minimize cost" → **Spot / Fargate Spot**, price-capacity-optimized, diversified.
- "**Proactively** replace Spot at risk" → **Capacity Rebalancing**.
- "Instances unhealthy in ALB but not replaced" → **ASG health check type ELB**.
- "**Long boot time**, sudden spikes" → **warm pool** + lifecycle hooks; golden AMI.
- "Daily recurring pattern, scale **before** load" → **predictive scaling**.
- "Run script / drain before termination" → **termination lifecycle hook**.
- "Roll out new AMI with zero downtime, auto rollback" → **instance refresh** (checkpoints, alarms, max healthy > 100%).
- "**Static IP**", "allow-list", "**UDP**", "**PrivateLink**", "**TLS passthrough**" → **NLB**.
- "Path-based routing", "authenticate with Cognito/OIDC", "Lambda target", "WAF" → **ALB**.
- "Third-party firewall appliances, transparent" → **GWLB** (GENEVE 6081).
- "Need client IP behind NLB with IP targets / PrivateLink" → **Proxy Protocol v2**; behind ALB → **X-Forwarded-For**.
- "New instances overwhelmed right after registration" → **ALB slow start**.
- "Long-running uploads cut during deployments" → increase **deregistration delay**.
- "**Per-core/per-socket licences**", "host-bound licences" → **Dedicated Hosts**, host affinity, **License Manager**.
- "Lowest latency between nodes", "HPC", "MPI" → **cluster placement group + EFA**.
- "HDFS/Cassandra rack awareness" → **partition placement group**.
- "Few critical instances on separate hardware" → **spread placement group** (max 7/AZ).
- "Guarantee capacity in AZ for DR without commitment" → **ODCR**.
- "Preserve in-memory state across stop" → **hibernation**.
- "Block SSRF credential theft" → **IMDSv2 required**, hop limit; enforce org-wide with **declarative policies**/SCP.
- "Share encrypted AMI cross-account" → **customer managed KMS key** + key policy grant (not `aws/ebs`).
- "Automate AMI build/patch/distribute across Regions/accounts" → **EC2 Image Builder**.
- "Lambda exhausts DB connections" → **RDS Proxy** (+ reserved concurrency).
- "Lambda cold start, Java" → **SnapStart** (cheap) or **provisioned concurrency** (strict).
- "Lambda needs internet from VPC" → **NAT gateway** in public subnet, function in private subnets (or VPC endpoints).
- "Lambda payload > 6 MB" → **S3 pointer / presigned URL**.
- "Asynchronous failure handling with context" → **Lambda destinations** (over DLQ).
- "Container can't pull image / read secret" → **task execution role**; "app can't call S3" → **task role**.
- "Private subnet Fargate pulls from ECR without NAT" → **ecr.api + ecr.dkr interface endpoints + S3 gateway endpoint** (+ logs endpoint).
- "Pods need AWS permissions across many clusters, simplest" → **EKS Pod Identity**; Fargate pods → **IRSA**.
- "Kubernetes node autoscaling, fast, cost-efficient, many instance types" → **Karpenter** / **EKS Auto Mode**.
- "On-prem servers as EKS nodes with AWS-managed control plane" → **EKS Hybrid Nodes**; "fully on-prem, disconnected" → **EKS Anywhere**; ECS equivalent → **ECS Anywhere**.
- "Service-to-service discovery on ECS without ALBs" → **ECS Service Connect** (App Mesh is end-of-support).
- "Blue/green for ECS" → **ECS native blue/green** (now AWS's recommended approach) or **CodeDeploy** (older exam items).
- "Containerize existing Java/.NET apps with a tool" → App2Container appears in older material, but it has been **closed to new customers since 7 Nov 2025**. Recognize it in older-style questions, but don't propose it for new work. Current modernization tooling is covered in [Chapter 13](13-Migration-and-Modernization.md).
- "Avoid Docker Hub rate limits" → **ECR pull-through cache**.
- "Continuous vulnerability scanning incl. language packages" → **ECR enhanced scanning (Inspector)**.
- "Containers images in DR Region" → **ECR cross-Region replication**.
- "Thousands of independent parallel jobs" → **AWS Batch array jobs** (Spot).
- "Managed Slurm" → **AWS PCS**; "build HPC cluster from config" → **ParallelCluster**.
- ".NET/Java web app, replatform, minimal change, managed patching" → **Elastic Beanstalk**.
- "Keep data on-prem, AWS APIs locally" → **Outposts**.

---

## 6. Traps & distractors

1. **"Use a larger instance type" for a scaling problem** — vertical scaling is rarely the SAP answer; look for ASG + decoupling.
2. **Simple scaling with cooldowns** offered as "the" solution for fast spikes — target tracking/step + warm-up is better.
3. **EC2 health checks only** — they don't detect application failure. ELB health checks needed.
4. **Spread placement group for 10 instances in one AZ** — max 7 per AZ per group.
5. **Cluster placement group across AZs** — impossible; cluster = one AZ (it trades availability for performance).
6. **Zonal RIs to reserve capacity in a placement group** — not possible; use ODCR targeted to the cluster PG.
7. **ODCR "saves money"** — no, it's billed at On-Demand; discount comes from Savings Plans/RIs.
8. **Dedicated Instances for per-core BYOL** — no socket/core visibility; need Dedicated Hosts.
9. **Sharing an AMI encrypted with `aws/ebs`** — not possible; re-encrypt with a CMK.
10. **Copying an AMI to share it in another Region** — sharing is Regional; you must copy to the Region and then share (or share then let consumers copy).
11. **ALB for static IPs** — ALB IPs change; use NLB/Global Accelerator.
12. **NLB for path-based routing or WAF** — NLB is L4.
13. **Adding security groups to an existing NLB created without them** — must be set at creation (recreate).
14. **Expecting client IP at targets through PrivateLink/TGW** — use Proxy Protocol v2.
15. **Enabling Proxy Protocol v2 without updating target software** — health checks fail.
16. **Cross-zone on NLB "for free"** — inter-AZ data transfer is charged for NLB/GWLB.
17. **Lambda in a public subnet for internet access** — Lambda ENIs never get public IPs; use NAT.
18. **Raising Lambda timeout above 15 minutes** — impossible for standard functions; redesign (Step Functions, Fargate, Batch).
19. **Reserved concurrency to reduce cold starts** — it doesn't pre-warm; provisioned concurrency does.
20. **Provisioned concurrency + SnapStart together** — unsupported combination.
21. **DLQ for SQS-triggered Lambda configured on the function** — for ESMs, failures are handled by the **SQS queue's redrive policy** (function async DLQ doesn't apply to synchronous ESM invocations).
22. **Putting app permissions on the ECS execution role or EC2 node role** — least privilege violation; use task role / Pod Identity.
23. **Fargate for GPU, DaemonSets, privileged containers** — not supported.
24. **IRSA vs Pod Identity on Fargate** — Pod Identity doesn't support Fargate pods.
25. **App Mesh for a new ECS design** — end of support (30 Sept 2026); choose Service Connect/VPC Lattice.
26. **ECR replication to back-fill old images** — only new pushes replicate.
27. **ECR private access with only interface endpoints** — layers come from S3; the S3 gateway endpoint is also required.
28. **Warm pool with Spot instances** — unsupported.
29. **Elastic Beanstalk-managed RDS for production** — DB lifecycle tied to environment; deleting the env deletes the DB.
30. **Batch MNP or HPC across multiple AZs for "resilience"** — kills latency; EFA OS-bypass doesn't cross subnets.

---

## 7. Professional architect focus

- **Platform selection is an organizational decision**, not just technical. Kubernetes gives portability but needs platform engineering headcount; ECS + Fargate is often the right default for AWS-centric teams. Raise skills, on-call model, and upgrade cadence (EKS versions have a support clock and extended-support cost).
- **Design for statelessness first** — it unlocks Spot, Auto Scaling, blue/green and multi-AZ. Externalize sessions (ElastiCache/DynamoDB), files (S3/EFS), and config (Parameter Store/AppConfig).
- **Cost levers stack**: right-size (Compute Optimizer) → Graviton → Spot for interruptible portions → Savings Plans for the steady base → turn things off (scheduled scaling, scale-to-zero). Always quantify inter-AZ data transfer (NLB cross-zone, chatty microservices).
- **Concurrency is a shared resource**: in multi-team accounts one Lambda can starve others. Use reserved concurrency for critical functions, separate accounts for blast-radius isolation, and quotas planning (Service Quotas + alarms).
- **Protect downstreams**: Lambda and Fargate scale faster than databases and third-party APIs. Use SQS buffering, reserved concurrency caps, RDS Proxy, API Gateway throttling, and circuit breakers.
- **Capacity is not infinite**: for events and DR, pre-reserve (ODCR, Capacity Blocks), diversify instance types (attribute-based selection), and test in game days. Spot-only fleets during a regional event may not get capacity.
- **Immutable infrastructure** beats in-place patching: Image Builder pipelines + instance refresh, container image rebuilds on base-image CVEs (Inspector), and short node lifetimes (Auto Mode 21 days).
- **Security posture**: IMDSv2 everywhere, least-privilege task/pod roles, no SSH (SSM Session Manager/ECS Exec), signed images, private ECR access via endpoints, Nitro Enclaves for sensitive processing.
- **Anti-patterns to call out**: snowflake EC2 "pets"; Lambda monoliths ("Lambda-lith") with 15-minute timeouts; synchronous chains of Lambdas (pay twice, cascade failures — use Step Functions/events); one giant ASG across unrelated apps; sticky sessions masking state problems; using App Runner/App Mesh for new builds despite their status.
- **Stakeholder questions to ask**: Is the workload interruptible? What is the acceptable cold-start/latency? Are licences tied to hardware? What's the team's container/Kubernetes maturity? Is there a data residency or on-prem latency requirement (Outposts/Local Zones/Hybrid Nodes)? What's the RTO for the compute tier, and are AMIs/images replicated to the DR Region?

---

## 8. Skills checklist

- [ ] I can choose between EC2, ECS (EC2/Fargate/Managed Instances), EKS, Lambda, Batch, Beanstalk and ECS Express Mode from a scenario's constraints.
- [ ] I can state placement group limits (cluster = 1 AZ; partition = 7/AZ; spread = 7 running instances/AZ) and their use cases.
- [ ] I can explain Dedicated Host vs Dedicated Instance and when host affinity and License Manager matter.
- [ ] I know ODCRs give capacity, not discounts, and how to combine them with Savings Plans.
- [ ] I can list hibernation prerequisites and IMDSv2 enforcement options (AMI flag, account default/enforcement, declarative policies).
- [ ] I can share an encrypted AMI across accounts and Regions correctly.
- [ ] I can design an Image Builder pipeline and justify golden AMI vs bootstrapping.
- [ ] I can pick target tracking vs step vs scheduled vs predictive scaling and explain warm-up vs cooldown.
- [ ] I can configure warm pools, lifecycle hooks, instance refresh, and termination policies.
- [ ] I can design a mixed instances policy with the right Spot allocation strategy and capacity rebalancing.
- [ ] I can choose ALB vs NLB vs GWLB and explain cross-zone defaults, costs, client IP preservation and Proxy Protocol v2.
- [ ] I can explain Lambda invocation models, retries, destinations vs DLQs, and event source mapping behaviours.
- [ ] I can size Lambda concurrency and choose reserved vs provisioned concurrency vs SnapStart.
- [ ] I can recite Lambda limits (15 min, 10,240 MB, 10 GB /tmp, 6 MB sync, 1 MB async, 50/250 MB, 10 GB image, 1,000 default concurrency).
- [ ] I can design Lambda VPC access with NAT/endpoints and RDS Proxy.
- [ ] I can distinguish ECS task role vs execution role and design capacity provider strategies with Fargate Spot.
- [ ] I can choose an ECS deployment strategy (rolling + circuit breaker, native blue/green/linear/canary, CodeDeploy).
- [ ] I can compare IRSA vs EKS Pod Identity and Karpenter vs managed node groups vs Auto Mode vs Fargate.
- [ ] I can configure ECR lifecycle, replication, enhanced scanning, pull-through cache and private endpoints.
- [ ] I can design loosely vs tightly coupled HPC on AWS (Batch, ParallelCluster/PCS, EFA, FSx for Lustre).

---

## 9. Practice questions

**Q1.** A media company runs a REST API on Amazon API Gateway backed by AWS Lambda functions written in Node.js. The functions query an Amazon Aurora MySQL DB cluster in private subnets. During a marketing campaign, traffic rose from 200 to 4,000 requests per second within minutes. The database began rejecting connections with "Too many connections" errors and CPU on the writer reached 100%, even though most queries are simple key lookups. The company wants to resolve the issue with the least application change and without over-provisioning the database. What should a solutions architect do?

A. Increase the Aurora instance class and raise the `max_connections` parameter to 16,000.
B. Create an Amazon RDS Proxy for the Aurora cluster, configure the Lambda functions to connect through the proxy endpoint using IAM authentication, and set reserved concurrency on the functions to cap peak database load.
C. Move the Lambda functions out of the VPC and connect to the Aurora cluster's public endpoint to remove ENI limits.
D. Configure provisioned concurrency of 4,000 on the Lambda functions so that each execution environment keeps a persistent connection.

**Q2.** A financial services company is migrating 40 Microsoft SQL Server Enterprise and Windows Server workloads to AWS. The company has existing licences without Software Assurance, which are licensed per physical core and must remain on dedicated physical servers. Auditors require proof of the number of sockets and cores used, and the instances must stay on the same physical server after maintenance reboots. The company wants to minimize the effort of tracking licence usage. Which combination of actions meets these requirements? **(Select TWO.)**

A. Launch the instances as Dedicated Instances in a VPC with `dedicated` tenancy.
B. Allocate EC2 Dedicated Hosts and launch instances with host tenancy and host affinity set to `host`.
C. Use AWS License Manager with self-managed licence rules based on cores, associate the rules with the AMIs, and use host resource groups to manage Dedicated Host allocation.
D. Use licence-included Amazon EC2 Windows AMIs with SQL Server Enterprise on shared tenancy.
E. Purchase Compute Savings Plans and an On-Demand Capacity Reservation for each instance type.

**Q3.** An e-commerce company runs a Java application on Amazon EC2 instances in an Auto Scaling group behind an Application Load Balancer. Each new instance needs about 12 minutes to download a product catalogue and warm its in-memory cache before it can serve traffic. Traffic has a strong daily cycle with a morning peak, but flash-sale spikes also occur without warning several times per week. During spikes customers see high latency for 10–15 minutes. The company wants to reduce latency during both peaks and spikes while minimizing cost. Which combination of actions should the solutions architect take? **(Select TWO.)**

A. Add a warm pool to the Auto Scaling group with instances in the Stopped state and a launch lifecycle hook that completes after the cache is loaded.
B. Configure a predictive scaling policy, in addition to the existing target tracking policy, so capacity is launched ahead of the forecast morning peak.
C. Replace the target tracking policy with simple scaling and a 600-second cooldown.
D. Keep the warm pool instances in the Running state so they can join immediately.
E. Change the group's health check type from ELB to EC2 so instances are put in service sooner.

**Q4.** A logistics company exposes an HTTPS API to 300 partner companies. Partner security teams allow outbound traffic only to a fixed list of IP addresses, and partners have asked that the list never change. The API needs path-based routing to three microservices running on Amazon ECS and must be protected by AWS WAF rules. The solution must be deployed in a single AWS Region with the least operational overhead. What should a solutions architect recommend?

A. Create an Application Load Balancer with AWS WAF and give partners the IP addresses that the ALB DNS name currently resolves to.
B. Create a Network Load Balancer with an Elastic IP address in each Availability Zone, register an Application Load Balancer as the target of the NLB using an ALB-type target group, and associate AWS WAF with the ALB.
C. Create a Network Load Balancer with Elastic IP addresses and TLS listeners, configure path-based listener rules on the NLB, and associate AWS WAF with the NLB.
D. Deploy NGINX on EC2 instances with Elastic IP addresses to perform path routing and install a WAF module on each instance.

**Q5.** A company runs a stateless image-processing web tier on an Auto Scaling group of 40 On-Demand `m5.2xlarge` instances. A cost review requires a large reduction in compute cost. The application can tolerate the loss of individual instances, but the company wants to keep at least 8 instances running at all times and to minimize the frequency of interruptions. Which combination of actions will meet these requirements? **(Select THREE.)**

A. Configure a mixed instances policy with an On-Demand base capacity of 8 and 0% On-Demand above the base.
B. Specify at least 10 instance types of similar size across multiple families and generations (or attribute-based instance type selection) and enable the group in all Availability Zones.
C. Use the `price-capacity-optimized` Spot allocation strategy.
D. Use the `lowest-price` Spot allocation strategy with a single instance pool to maximize savings.
E. Set the On-Demand percentage above base capacity to 100% and purchase Spot blocks (defined-duration Spot Instances) for the remaining capacity.
F. Add a warm pool in the Hibernated state to replace interrupted Spot Instances quickly.

**Q6.** A team is moving a containerized order service to Amazon ECS on AWS Fargate in private subnets with no NAT gateway. The task definition references a database password stored in AWS Secrets Manager and an image in a private Amazon ECR repository in the same account. The application writes order documents to an Amazon S3 bucket. After deployment, tasks stop immediately with `ResourceInitializationError: unable to pull secrets or registry auth`. Which solution resolves the problem while following least privilege?

A. Add `secretsmanager:GetSecretValue`, ECR pull and S3 `PutObject` permissions to the task role, and add interface VPC endpoints for Secrets Manager.
B. Grant the task execution role permission to read the specific secret and pull from the ECR repository; create interface endpoints for Secrets Manager, `ecr.api`, `ecr.dkr`, and CloudWatch Logs plus an S3 gateway endpoint; grant S3 `PutObject` on the bucket to the task role.
C. Grant the task execution role permissions for Secrets Manager, ECR and S3 `PutObject`, and launch the tasks in public subnets with public IP addresses.
D. Attach `AdministratorAccess` to the task role temporarily and add a NAT gateway; scope down permissions after the service is stable.

**Q7.** A platform team operates 35 Amazon EKS clusters across several accounts, with clusters frequently created and destroyed by CI pipelines. Application pods need AWS permissions (for example, to Amazon DynamoDB and Amazon SQS). Today the team uses IAM roles for service accounts (IRSA), and every new cluster requires updating the trust policies of dozens of IAM roles, which has started to hit trust policy size limits. All workloads run on EC2-based managed node groups. The team wants the least operational overhead. What should they do?

A. Attach the required permissions to the node instance role used by each managed node group.
B. Install the EKS Pod Identity Agent add-on, update roles to trust the `pods.eks.amazonaws.com` service principal, and create Pod Identity associations for each cluster, namespace and service account.
C. Create one IAM OIDC provider shared by all clusters and reference it in every role's trust policy.
D. Store long-term IAM user access keys in Kubernetes secrets and mount them into the pods.

**Q8.** A bank's customer-facing API runs on AWS Lambda with the Java 21 runtime behind Amazon API Gateway. Cold starts take 6–8 seconds because of Spring Boot initialization; this violates a 2-second p99 latency target during unpredictable bursts. Traffic is highly variable, and the team wants to avoid paying for idle pre-initialized capacity. The functions use 512 MB of ephemeral storage and do not mount file systems. What is the MOST cost-effective solution?

A. Enable provisioned concurrency equal to the peak observed concurrency on the `$LATEST` version.
B. Enable Lambda SnapStart on the function, publish a version, point an alias at it, and update API Gateway to invoke the alias; add runtime hooks to re-establish connections and regenerate unique values after restore.
C. Increase memory to 10,240 MB and the timeout to 15 minutes.
D. Rewrite the functions in Rust and deploy them as 10 GB container images.

**Q9.** A research institute is moving a computational fluid dynamics (CFD) application from an on-premises cluster to AWS. The application uses MPI across 64 nodes, is highly sensitive to inter-node latency, and reads a 40 TB input dataset stored in Amazon S3. Jobs run for 30 hours and cannot checkpoint. The institute wants the best performance with a scheduler that its researchers already know (Slurm). Which combination of actions should a solutions architect recommend? **(Select THREE.)**

A. Launch compute nodes in a cluster placement group in a single subnet, using an instance type that supports Elastic Fabric Adapter (EFA), with On-Demand capacity reserved through an On-Demand Capacity Reservation.
B. Spread compute nodes across three Availability Zones using a spread placement group for resilience.
C. Use Amazon FSx for Lustre linked to the S3 bucket through a data repository association as the shared scratch file system.
D. Use AWS ParallelCluster or AWS Parallel Computing Service to provide a Slurm-based cluster.
E. Run the job with AWS Lambda functions fanned out by AWS Step Functions Distributed Map.
F. Use Spot Instances with the `lowest-price` allocation strategy to minimize cost.

**Q10.** A SaaS company runs containerized services on Amazon EKS in `us-east-1` and is building a warm-standby disaster recovery environment in `us-west-2` in a separate DR account. Images are pushed to Amazon ECR in the production account by CI pipelines. Security requires continuous vulnerability scanning that covers operating system and application language packages and alerts when new CVEs affect images already in production. Storage costs for thousands of untagged CI images must be controlled. Which combination of actions meets these requirements? **(Select TWO.)**

A. Configure ECR registry replication rules to replicate the production repositories to `us-west-2` in the DR account, with a registry policy in the DR account that allows replication from the production account.
B. Enable ECR basic scanning with scan-on-push for all repositories.
C. Enable ECR enhanced scanning with Amazon Inspector in continuous scanning mode, and create ECR lifecycle policies that expire untagged images older than 14 days.
D. Use an ECR pull-through cache rule in the DR account pointing at Docker Hub to obtain the production images.
E. Schedule a nightly AWS Batch job that runs `docker pull` and `docker push` to copy every image to the DR Region.

---

### Answers & explanations

<details><summary>Show answer — Q1</summary>

**Correct: B.**
- **Why:** RDS Proxy pools and multiplexes connections from thousands of short-lived Lambda environments into a small number of database connections, integrates with IAM authentication and Secrets Manager, and needs only an endpoint change. Reserved concurrency caps concurrency so the database is never overwhelmed (excess requests are throttled rather than crashing the DB).
- **A:** Bigger instances and higher `max_connections` treat the symptom, cost more, and memory per connection still exhausts the writer.
- **C:** Exposing Aurora publicly is a security regression and does nothing for connection counts. Hyperplane ENIs are not the bottleneck.
- **D:** Provisioned concurrency of 4,000 still opens 4,000+ connections and adds significant cost; it addresses cold starts, not connection management.
- **References:** https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/rds-proxy.html · https://docs.aws.amazon.com/lambda/latest/dg/configuration-concurrency.html
</details>

<details><summary>Show answer — Q2</summary>

**Correct: B, C.**
- **Why:** Per-core licences without Software Assurance/licence mobility require **Dedicated Hosts**, which expose sockets and physical cores; **host affinity** keeps an instance on the same host after stop/start. **AWS License Manager** with core-based licence configurations and **host resource groups** automates host allocation and tracks licence consumption for auditors.
- **A:** Dedicated Instances provide single-tenant hardware but no socket/core visibility or host affinity.
- **D:** Licence-included AMIs abandon the existing licences and run on shared tenancy, violating the dedicated-server requirement.
- **E:** Savings Plans and ODCRs address discount and capacity, not licensing or host visibility.
- **References:** https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/dedicated-hosts-overview.html · https://docs.aws.amazon.com/license-manager/latest/userguide/host-resource-groups.html
</details>

<details><summary>Show answer — Q3</summary>

**Correct: A, B.**
- **Why:** A **warm pool** keeps pre-initialized instances Stopped (paying only for EBS), so unplanned spikes are served in seconds instead of 12 minutes; the **lifecycle hook** ensures instances are fully warmed before they are stopped. **Predictive scaling** launches capacity ahead of the recurring morning peak, while target tracking still handles surprises.
- **C:** Simple scaling with a long cooldown makes reaction slower.
- **D:** Running warm-pool instances cost the same as in-service instances — AWS discourages it; Stopped meets the requirement more cheaply.
- **E:** EC2 health checks don't make instances serve faster and would stop replacing instances that fail application health checks.
- **References:** https://docs.aws.amazon.com/autoscaling/ec2/userguide/ec2-auto-scaling-warm-pools.html · https://docs.aws.amazon.com/autoscaling/ec2/userguide/ec2-auto-scaling-predictive-scaling.html
</details>

<details><summary>Show answer — Q4</summary>

**Correct: B.**
- **Why:** An NLB provides one static Elastic IP per AZ that never changes. An **ALB-type target group** lets the NLB forward to an ALB, which performs path-based routing to ECS target groups and supports **AWS WAF**. Both are managed services → low operational overhead. (Global Accelerator in front of the ALB is an equally valid pattern, but it was not offered.)
- **A:** ALB IP addresses change as the ALB scales; allow-listing them breaks.
- **C:** NLB is Layer 4 — no path-based rules — and AWS WAF cannot be associated with an NLB.
- **D:** Self-managed proxies add significant operational overhead and single points of failure.
- **References:** https://docs.aws.amazon.com/elasticloadbalancing/latest/network/application-load-balancer-target.html · https://docs.aws.amazon.com/waf/latest/developerguide/waf-chapter.html
</details>

<details><summary>Show answer — Q5</summary>

**Correct: A, B, C.**
- **Why:** On-Demand base capacity of 8 guarantees the minimum, with Spot for everything above it (large savings). Diversifying across many instance types and all AZs and using **price-capacity-optimized** (AWS's recommended strategy) selects deep, low-interruption pools at a low price, minimizing interruptions.
- **D:** `lowest-price` with a single pool maximizes interruption risk and capacity shortfalls.
- **E:** 100% On-Demand above base removes all Spot savings, and Spot blocks (defined-duration Spot) are no longer offered by AWS. (In a real design you would *also* enable Capacity Rebalancing with a drain hook — it reduces the impact of interruptions — but that was not among the options.)
- **F:** Warm pools do not support Spot Instances in mixed instance groups.
- **References:** https://docs.aws.amazon.com/autoscaling/ec2/userguide/ec2-auto-scaling-mixed-instances-groups.html · https://docs.aws.amazon.com/autoscaling/ec2/userguide/allocation-strategies.html
</details>

<details><summary>Show answer — Q6</summary>

**Correct: B.**
- **Why:** The **task execution role** is used by the Fargate agent to retrieve secrets referenced in the task definition and pull images from ECR, so it needs those permissions. With no NAT gateway, Fargate needs **interface endpoints** for Secrets Manager, `ecr.api`, `ecr.dkr` (and CloudWatch Logs for `awslogs`) and an **S3 gateway endpoint** because image layers are stored in S3. The application's S3 writes belong on the **task role**.
- **A:** Secrets and image pulls happen before the container starts — the task role is not used for them; the ECR/S3 endpoints are also missing.
- **C:** Puts application permissions on the execution role (not least privilege) and moves tasks to public subnets unnecessarily.
- **D:** Violates least privilege and adds cost.
- **References:** https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task_execution_IAM_role.html · https://docs.aws.amazon.com/AmazonECR/latest/userguide/vpc-endpoints.html
</details>

<details><summary>Show answer — Q7</summary>

**Correct: B.**
- **Why:** **EKS Pod Identity** removes the per-cluster OIDC provider and the need to edit role trust policies for every new cluster; the role trusts `pods.eks.amazonaws.com` once and is mapped to service accounts through associations created with the EKS API (easily automated in CI). Workloads run on EC2 nodes, so the Pod Identity Fargate limitation doesn't apply.
- **A:** Node roles give every pod on the node the same permissions — violates least privilege.
- **C:** Each EKS cluster has its own OIDC issuer URL; a single shared provider is not possible.
- **D:** Long-term access keys are a security anti-pattern.
- **References:** https://docs.aws.amazon.com/eks/latest/userguide/pod-identities.html · https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html
</details>

<details><summary>Show answer — Q8</summary>

**Correct: B.**
- **Why:** **SnapStart** for Java snapshots the initialized execution environment when a version is published and restores from it, typically giving sub-second starts at **no additional cost for Java**. It requires published versions/aliases (not `$LATEST`) and ephemeral storage ≤ 512 MB (met). Runtime hooks handle connection and uniqueness concerns.
- **A:** Provisioned concurrency cannot be applied to `$LATEST` and charges for idle capacity — against the cost requirement with variable traffic.
- **C:** More memory speeds init somewhat but not from 6–8 s to under 2 s reliably; the timeout is irrelevant.
- **D:** A rewrite is costly and slow; a larger image would not help cold starts.
- **References:** https://docs.aws.amazon.com/lambda/latest/dg/snapstart.html
</details>

<details><summary>Show answer — Q9</summary>

**Correct: A, C, D.**
- **Why:** Tightly coupled MPI needs **EFA** for OS-bypass low latency and a **cluster placement group** in one subnet/AZ; 30-hour non-checkpointing jobs need **On-Demand capacity**, ideally guaranteed with an **ODCR targeted to the placement group**. **FSx for Lustre** linked to S3 gives a high-throughput parallel file system with lazy loading of the 40 TB dataset. **ParallelCluster** or **PCS** provides Slurm.
- **B:** Spreading across AZs destroys inter-node latency, and spread groups allow only 7 instances per AZ.
- **E:** Lambda's 15-minute limit and lack of MPI networking make it unsuitable.
- **F:** One Spot interruption would kill a non-checkpointing 30-hour job; lowest-price raises interruption risk.
- **References:** https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/efa.html · https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/placement-strategies.html · https://docs.aws.amazon.com/fsx/latest/LustreGuide/create-dra-linked-data-repo.html · https://docs.aws.amazon.com/parallelcluster/latest/ug/what-is-aws-parallelcluster.html
</details>

<details><summary>Show answer — Q10</summary>

**Correct: A, C.**
- **Why:** **ECR replication** natively copies images cross-Region and cross-account (the destination registry policy must allow it) — no custom tooling. **Enhanced scanning** with **Amazon Inspector** scans continuously, covers OS and language packages, and rescans when new CVEs are published; **lifecycle policies** expire untagged CI images to control storage cost.
- **B:** Basic scanning covers OS packages only and runs on push/manual, so it won't flag new CVEs in already-pushed images.
- **D:** Pull-through cache is for upstream registries such as Docker Hub — the production images aren't there; the supported ECR-to-ECR caching would add a dependency on the primary Region at DR time anyway.
- **E:** Custom copy jobs add operational overhead and cost compared with native replication.
- **References:** https://docs.aws.amazon.com/AmazonECR/latest/userguide/replication.html · https://docs.aws.amazon.com/AmazonECR/latest/userguide/image-scanning-enhanced.html · https://docs.aws.amazon.com/AmazonECR/latest/userguide/LifecyclePolicies.html
</details>

---

## 10. References

**EC2**
- Amazon EC2 instance types: https://docs.aws.amazon.com/ec2/latest/instancetypes/instance-types.html
- AWS Nitro System: https://docs.aws.amazon.com/whitepapers/latest/security-design-of-aws-nitro-system/security-design-of-aws-nitro-system.html
- Placement strategies: https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/placement-strategies.html
- Enhanced networking (ENA / ENA Express): https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/enhanced-networking.html
- Elastic Fabric Adapter: https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/efa.html
- Dedicated Hosts: https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/dedicated-hosts-overview.html
- Capacity Reservations: https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-capacity-reservations.html
- Hibernation prerequisites: https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/hibernating-prerequisites.html
- IMDS configuration for new instances: https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/configuring-IMDS-new-instances.html
- Share an AMI with specific accounts: https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/sharingamis-explicit.html
- Copy an AMI: https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/CopyingAMIs.html
- EC2 Image Builder: https://docs.aws.amazon.com/imagebuilder/latest/userguide/what-is-image-builder.html
- Spot best practices: https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/spot-best-practices.html
- AWS License Manager: https://docs.aws.amazon.com/license-manager/latest/userguide/license-manager.html

**Auto Scaling**
- EC2 Auto Scaling User Guide: https://docs.aws.amazon.com/autoscaling/ec2/userguide/what-is-amazon-ec2-auto-scaling.html
- Warm pools: https://docs.aws.amazon.com/autoscaling/ec2/userguide/ec2-auto-scaling-warm-pools.html
- Predictive scaling: https://docs.aws.amazon.com/autoscaling/ec2/userguide/ec2-auto-scaling-predictive-scaling.html
- Lifecycle hooks: https://docs.aws.amazon.com/autoscaling/ec2/userguide/lifecycle-hooks.html
- Instance refresh: https://docs.aws.amazon.com/autoscaling/ec2/userguide/asg-instance-refresh.html
- Mixed instances groups / allocation strategies: https://docs.aws.amazon.com/autoscaling/ec2/userguide/allocation-strategies.html
- Capacity Rebalancing: https://docs.aws.amazon.com/autoscaling/ec2/userguide/ec2-auto-scaling-capacity-rebalancing.html
- Termination policies: https://docs.aws.amazon.com/autoscaling/ec2/userguide/ec2-auto-scaling-termination-policies.html

**Elastic Load Balancing**
- How ELB works (cross-zone, routing): https://docs.aws.amazon.com/elasticloadbalancing/latest/userguide/how-elastic-load-balancing-works.html
- ALB target group attributes: https://docs.aws.amazon.com/elasticloadbalancing/latest/application/edit-target-group-attributes.html
- ALB authentication: https://docs.aws.amazon.com/elasticloadbalancing/latest/application/listener-authenticate-users.html
- NLB target group attributes (client IP, Proxy Protocol v2): https://docs.aws.amazon.com/elasticloadbalancing/latest/network/edit-target-group-attributes.html
- Gateway Load Balancer: https://docs.aws.amazon.com/elasticloadbalancing/latest/gateway/introduction.html

**Lambda**
- Lambda quotas: https://docs.aws.amazon.com/lambda/latest/dg/gettingstarted-limits.html
- Concurrency & scaling: https://docs.aws.amazon.com/lambda/latest/dg/lambda-concurrency.html
- Asynchronous invocation & destinations: https://docs.aws.amazon.com/lambda/latest/dg/invocation-async.html
- Event source mappings: https://docs.aws.amazon.com/lambda/latest/dg/invocation-eventsourcemapping.html
- SnapStart: https://docs.aws.amazon.com/lambda/latest/dg/snapstart.html
- VPC networking: https://docs.aws.amazon.com/lambda/latest/dg/configuration-vpc.html
- Lambda Managed Instances: https://docs.aws.amazon.com/lambda/latest/dg/lambda-managed-instances.html
- RDS Proxy: https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/rds-proxy.html

**Containers**
- ECS launch types & capacity providers: https://docs.aws.amazon.com/AmazonECS/latest/developerguide/capacity-launch-type-comparison.html
- ECS task execution role: https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task_execution_IAM_role.html
- ECS task role: https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task-iam-roles.html
- ECS Service Connect: https://docs.aws.amazon.com/AmazonECS/latest/developerguide/service-connect.html
- ECS deployment types: https://docs.aws.amazon.com/AmazonECS/latest/developerguide/deployment-types.html
- ECS Express Mode: https://docs.aws.amazon.com/AmazonECS/latest/developerguide/express-service-overview.html
- EKS Auto Mode: https://docs.aws.amazon.com/eks/latest/userguide/automode.html
- EKS Pod Identity: https://docs.aws.amazon.com/eks/latest/userguide/pod-identities.html
- EKS Hybrid Nodes: https://docs.aws.amazon.com/eks/latest/userguide/hybrid-nodes-overview.html
- EKS Best Practices Guide: https://docs.aws.amazon.com/eks/latest/best-practices/introduction.html
- ECR replication: https://docs.aws.amazon.com/AmazonECR/latest/userguide/replication.html
- ECR image scanning: https://docs.aws.amazon.com/AmazonECR/latest/userguide/image-scanning.html
- ECR pull-through cache: https://docs.aws.amazon.com/AmazonECR/latest/userguide/pull-through-cache.html
- App Runner availability change: https://docs.aws.amazon.com/apprunner/latest/dg/apprunner-availability-change.html
- App Mesh (end-of-support notice): https://docs.aws.amazon.com/app-mesh/latest/userguide/what-is-app-mesh.html

**Other compute**
- Elastic Beanstalk deployment policies: https://docs.aws.amazon.com/elasticbeanstalk/latest/dg/using-features.rolling-version-deploy.html
- AWS Batch User Guide: https://docs.aws.amazon.com/batch/latest/userguide/what-is-batch.html
- AWS ParallelCluster: https://docs.aws.amazon.com/parallelcluster/latest/ug/what-is-aws-parallelcluster.html
- AWS Parallel Computing Service: https://docs.aws.amazon.com/pcs/latest/userguide/what-is-service.html
- AWS Outposts: https://docs.aws.amazon.com/outposts/latest/userguide/what-is-outposts.html
- AWS Local Zones: https://docs.aws.amazon.com/local-zones/latest/ug/what-is-aws-local-zones.html
- Well-Architected Framework — Performance Efficiency Pillar: https://docs.aws.amazon.com/wellarchitected/latest/performance-efficiency-pillar/welcome.html

---
> [← Previous](06-Security-Data-Protection-and-Threat-Detection.md) · [Index](00-README-Start-Here.md) · [Next →](08-Storage-and-Data-Transfer.md)
