# Domain 3 · 01 · High Availability Across AZs and Regions

> **Exam task:** 3.1 (all of it), 3.3 (testing failover; recovering from backend failure behind a load balancer). **Principles:** P6 (isolation), P7 (automatic replacement), P8 (RTO/RPO).

## 1. First principles

1. **Availability is a property of the weakest serial link.**
   * Components in **series** multiply: two 99.9% components → 99.8%.
   * Redundant components in **parallel** combine as `1 − (1 − a)ⁿ`: two independent 99.5% AZs → 99.9975%.

   So HA means (a) removing single points of failure and (b) making each tier redundant across **independent failure domains**.
2. **Redundancy without detection and failover is just cost.** Every redundant tier needs a **health signal** and an **automatic switch**: load-balancer health checks, ASG replacement, RDS failover, Route 53 failover, CloudFront origin failover (P7).
3. **Stateless tiers are easy; state is the hard part.** Compute can be replaced in minutes. Data must be **replicated**, and replication is either **synchronous** (no data loss, same-Region latency only: Multi-AZ) or **asynchronous** (some data loss possible, works across Regions).

## 2. Translating business requirements into resilience

| Business statement | Technical requirement |
|---|---|
| "Must survive the loss of a data centre" | Multi-AZ for every tier (at least 2 AZs, preferably 3) |
| "Must survive the loss of a Region" | Multi-Region: replicated data, deployable compute, DNS or global routing failover |
| "SLA 99.99%" | No single-AZ component anywhere in the request path; managed services with matching SLAs; automated failover |
| "No data loss on infrastructure failure" | Synchronous replication: RDS/Aurora Multi-AZ, DynamoDB, S3, EFS (all multi-AZ by design) |
| "Minimal data loss on a Regional failure" | Asynchronous cross-Region replication with a small RPO: Aurora Global Database, DynamoDB global tables, S3 CRR with RTC |

### 2.1 Single points of failure to look for in a scenario

* **One EC2 instance**, or an ASG confined to one AZ.
* **One NAT gateway** for subnets in several AZs. A NAT gateway is zonal, so use one per AZ, each AZ's route table pointing to its own.
* **A single-AZ RDS instance**, or a self-managed database on one instance.
* An application that stores **sessions or uploads on local disk** (use ElastiCache, DynamoDB or EFS/S3).
* **An Elastic IP moved by hand** as the "failover".
* **One Site-to-Site VPN tunnel or one customer gateway.** Every VPN connection has two tunnels; use both, and ideally two customer gateways.
* **Hard-coded IP addresses or instance endpoints** instead of DNS names or load balancers.
* **A single-Region dependency** for a "Regional outage" requirement (e.g. a Regional SSM parameter or Secrets Manager secret not replicated).

## 3. Compute layer

| Mechanism | Detail |
|---|---|
| **Auto Scaling group across AZs** | Spreads instances evenly across the listed subnets and AZs; rebalances after an AZ recovers. Set `HealthCheckType: ELB` so load-balancer health failures **replace** instances, not just EC2 status-check failures |
| **Elastic Load Balancing** | Health checks per target group (path, interval, thresholds, success codes). **Cross-zone load balancing** is always on for ALB; **off by default for NLB** (configurable). **Deregistration delay** (connection draining) lets in-flight requests finish; **slow start** ramps up new targets |
| **Recovering from backend failure** (task 3.3) | ALB health checks remove failed targets; the ASG replaces them; with **no healthy targets** in a target group, an ALB fails open (routes to all). Route 53 **evaluate target health** on alias records fails over away from an ALB with no healthy targets |
| **ECS services** | The service scheduler keeps the desired count across AZs (spread placement); the load balancer and container health checks replace tasks |
| **Lambda** | Multi-AZ by design in its Region. Regional resilience needs multi-Region deployment |
| **EC2 automatic recovery** | Simplified automatic recovery (default for supported instance types), or a **CloudWatch alarm with the `recover` action** on `StatusCheckFailed_System`. The instance keeps its ID, private IPs, EIPs and EBS volumes; it moves to healthy hardware |

## 4. Data layer

### 4.1 Relational

| Option | Replication | Failover | Readable standby? | Cross-Region? |
|---|---|---|---|---|
| **RDS Multi-AZ (instance)** | **Synchronous** to one standby in another AZ | Automatic, typically **60–120 s**; the endpoint DNS name stays the same | No | No |
| **RDS Multi-AZ DB cluster** (MySQL, PostgreSQL) | Semi-synchronous to **two readable standbys** | Automatic, typically under 35 s | Yes (reader endpoint) | No |
| **RDS read replica** | **Asynchronous** | **Manual promotion** (becomes standalone; replication breaks) | Yes | **Yes**: cross-Region read replicas for DR and read scaling |
| **Aurora** | Storage: 6 copies across 3 AZs; up to 15 replicas share the storage | Automatic to a replica (priority tiers), typically about 30 s; the cluster endpoint follows the writer | Yes (reader endpoint) | Via Global Database |
| **Aurora Global Database** | Storage-level replication to secondary Regions, typically **under 1 second of lag** | **Switchover** (planned, no data loss) or **failover** (unplanned: promote a secondary; RPO = replication lag) | Yes, in the secondaries; **write forwarding** sends writes from a secondary to the primary | Yes |

**RDS Proxy** pools connections and shortens application-visible failover time, because it keeps client connections and reconnects to the new writer. It's the answer to "reduce failover disruption" and "too many connections from Lambda".

**Testing failover:**
* RDS: **reboot with failover**.
* Aurora: `failover-db-cluster`.
* Global Database: a managed switchover in a game day.
* AWS FIS can inject these faults too.

### 4.2 Non-relational and storage

| Service | Built-in AZ resilience | Cross-Region option |
|---|---|---|
| **DynamoDB** | Data replicated across 3 AZs | **Global tables:** multi-active, every replica Region accepts writes, asynchronous replication, last-writer-wins conflict resolution (the multi-Region *strong* consistency mode is an option for 3-Region setups); point-in-time recovery for backups |
| **S3** | Standard classes store data across at least 3 AZs (One Zone-IA doesn't) | **Cross-Region Replication** (versioning required on **both** buckets; replicates **new** objects; existing objects need **S3 Batch Replication**; delete markers replicate only if enabled; **Replication Time Control** = 99.99% of objects within 15 minutes, with metrics and events). **Multi-Region Access Points** give one global endpoint with failover controls |
| **EFS** | Regional file systems span AZs (mount targets per AZ) | **EFS replication** to another Region (read-only until failover) |
| **ElastiCache (Redis OSS / Valkey)** | Multi-AZ with automatic failover to a replica | **Global Datastore** |
| **EBS** | Replicated **within one AZ** only | Snapshots (Regional, copyable cross-Region); multi-AZ needs application-level replication, or restoring snapshots in another AZ |

## 5. DNS and global routing

### 5.1 Route 53 routing policies

| Policy | Use |
|---|---|
| Simple | One record (multiple values returned in random order; no health checks per value) |
| **Failover** | Active-passive: the primary is returned while healthy, otherwise the secondary |
| **Weighted** | Split by weight: blue/green, canary between stacks |
| **Latency** | Route to the Region with the lowest latency for the user; with health checks, fails over to the next best |
| Geolocation / geoproximity | Route by user location (compliance, localization) / by distance with bias |
| Multivalue answer | Up to 8 healthy records returned (client-side load spreading) |
| IP-based | Route by client CIDR |

### 5.2 Health checks

* **Endpoint health checks** (HTTP/HTTPS/TCP, string matching, from many checker locations) for public endpoints.
* **Calculated health checks** combine others with AND/OR/threshold.
* **CloudWatch alarm-based health checks** are the way to health-check **private** resources: checkers on the internet can't reach a private IP, so check an alarm instead. **Health-check metrics are in us-east-1**, so alarms on `HealthCheckStatus` must be created there.
* **Alias records with Evaluate Target Health** inherit the health of AWS targets (ALB, CloudFront, another record set) without a separate health check.
* **DNS TTL matters:** failover is only as fast as clients' caches expire. Use low TTLs (e.g. 60 s) on failover records.

### 5.3 Faster or more controlled global failover

* **Global Accelerator:** two static anycast IPs. Health-based failover between Regional endpoints takes **seconds** and **doesn't depend on DNS caching**. Use it for "fastest Regional failover", TCP/UDP, and static IPs.
* **CloudFront origin groups:** a primary and a secondary origin. CloudFront fails over **per request** when the primary returns configured status codes (e.g. 500, 502, 503, 504, 403, 404) or times out. This applies to **GET, HEAD and OPTIONS** requests. Typical pairing: S3 buckets in two Regions with CRR.
* **Route 53 Application Recovery Controller (ARC):**
  * **routing controls**: highly available on/off switches for failover, independent of the failing Region's control plane;
  * **readiness checks**;
  * **zonal shift / zonal autoshift**: move traffic away from an impaired AZ for ALB/NLB.

## 6. Multi-Region application patterns

* **Active-passive:** data replicated (Aurora Global Database, DynamoDB global tables, S3 CRR); compute pre-deployed (warm) or deployable from IaC (pilot light); Route 53 failover or ARC routing controls.
* **Active-active:** both Regions serve. Requires multi-writer data (DynamoDB global tables) or partitioned ownership (users homed to one Region), and idempotent, conflict-tolerant writes.
* **Deploying the same stack to several Regions:** StackSets, or a pipeline with cross-Region actions (per-Region artifact buckets). Replicate **secrets** (Secrets Manager replica secrets), **KMS keys** (multi-Region keys), **container images** (ECR replication) and **AMIs** (copy, or Image Builder distribution).

## 7. Exam traps

* **RDS Multi-AZ standby isn't readable** and isn't cross-Region. Read replicas are asynchronous and need manual promotion.
* **S3 CRR doesn't copy existing objects** (use Batch Replication), and it needs versioning on both buckets plus an IAM role.
* **Route 53 health checks can't reach private IPs.** Use CloudWatch alarm-based health checks.
* **One NAT gateway** is a hidden SPOF and also causes cross-AZ data charges.
* **"Fastest failover, unaffected by DNS caching"** → Global Accelerator (or ARC routing controls with low TTLs), not plain DNS failover.
* **ASG health check type EC2** doesn't replace instances that fail application (ELB) health checks.
* **CloudFront origin failover** covers only GET/HEAD/OPTIONS. It isn't a write-path failover.

## 8. Hands-on lab: Route 53 failover with a health check (about 30 minutes)

You need a public hosted zone you control, and two endpoints, e.g. two small web servers or S3 website endpoints in two Regions. [labs/lab-06-route53-failover.yaml](labs/lab-06-route53-failover.yaml) creates:
* an HTTP health check on the primary;
* `PRIMARY` and `SECONDARY` failover records with a 60 s TTL;
* a CloudWatch alarm on the health check status.

**Deploy it in us-east-1:** Route 53 health-check metrics only exist there.

```bash
aws cloudformation deploy --region us-east-1 --stack-name dop-lab-06 \
  --template-file labs/lab-06-route53-failover.yaml \
  --parameter-overrides HostedZoneId=Z123... RecordName=app.example.com \
    PrimaryEndpoint=primary.example.net SecondaryEndpoint=secondary.example.net
dig +short app.example.com           # → primary
# Stop the primary web server; within about 1-2 minutes the health check fails:
dig +short app.example.com           # → secondary (after the 60 s TTL)
aws cloudformation delete-stack --region us-east-1 --stack-name dop-lab-06
```

## References

* RDS Multi-AZ deployments — <https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/Concepts.MultiAZ.html>
* Aurora Global Database — <https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/aurora-global-database.html>
* DynamoDB global tables — <https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/GlobalTables.html>
* S3 replication — <https://docs.aws.amazon.com/AmazonS3/latest/userguide/replication.html>
* S3 Replication Time Control — <https://docs.aws.amazon.com/AmazonS3/latest/userguide/replication-time-control.html>
* Route 53 routing policies — <https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/routing-policy.html>
* Route 53 health checks for private resources (CloudWatch alarms) — <https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/health-checks-types.html>
* CloudFront origin failover — <https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/high_availability_origin_failover.html>
* AWS Global Accelerator — <https://docs.aws.amazon.com/global-accelerator/latest/dg/what-is-global-accelerator.html>
* Route 53 ARC zonal shift — <https://docs.aws.amazon.com/r53recovery/latest/dg/arc-zonal-shift.html>
* EC2 instance recovery — <https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-instance-recover.html>
