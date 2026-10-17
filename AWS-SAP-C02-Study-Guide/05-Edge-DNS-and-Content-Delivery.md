# Chapter 05 — Edge Services: Route 53, CloudFront, Global Accelerator & Edge Compute
> **Exam mapping:** D1 Task 1.1, D1 Task 1.3, D2 Task 2.2, D2 Task 2.4, D2 Task 2.5, D3 Task 3.3 | **Weight signal:** High | **Study time:** ~6 h
> [← Previous](04-Networking-VPC-and-Hybrid-Connectivity.md) · [Index](00-README-Start-Here.md) · [Next →](06-Security-Data-Protection-and-Threat-Detection.md)

---

## 1. What the exam really tests here

SAP-C02 rarely asks "what is CloudFront?". It asks you to **pick the right front door** for a global workload under constraints, and then configure it correctly. Expect scenarios like:

- **Multi-Region resilience (D1 1.3, D2 2.2, D2 2.4):** active-active vs active-passive across Regions, which Route 53 routing policy and which health-check type to use, how to fail over **without depending on a control plane**, and when Route 53 Application Recovery Controller (ARC) is the answer.
- **Migration cutover (D1 1.1, D2 2.2):** lowering TTLs ahead of time, weighted records for canary/blue-green, rollback speed, split-horizon DNS during hybrid periods.
- **Performance (D2 2.5, D3 3.3):** improving cache hit ratio, reducing origin load (Origin Shield, cache policies), accelerating dynamic/API content, TCP/UDP acceleration with Global Accelerator, single-digit-millisecond latency with Local Zones/Wavelength/Outposts.
- **Security at the edge (D1 1.2, D2 2.3 — overlaps ch06):** making the origin reachable **only** through CloudFront (OAC, VPC origins, custom header + WAF, managed prefix list), signed URLs/cookies, field-level encryption, geo restriction, WAF/Shield placement.
- **Choosing between look-alikes:** Global Accelerator vs CloudFront vs Route 53 latency routing; CloudFront Functions vs Lambda@Edge; alias vs CNAME; signed URL vs signed cookie; OAC vs OAI; failover routing vs ARC routing control; Local Zone vs Outposts vs Wavelength.

The decisive words are usually: **static IP / allow-listing**, **UDP**, **non-HTTP**, **zone apex**, **cache hit ratio**, **origin not publicly accessible**, **least operational overhead**, **fails over within seconds / no DNS caching**, **data must stay on premises**, **5G mobile devices**.

---

## 2. Core concepts & services — deep dive

### 2.1 Amazon Route 53 fundamentals

Route 53 is AWS's authoritative DNS, domain registrar, health-checking service and (via Resolver) the recursive DNS for VPCs. Its **data plane** (answering queries, health checks) is globally distributed and has a **100% availability SLA**; its **control plane** (creating/changing records, health checks) is hosted in **us-east-1**. That split matters for DR design: **failover must rely on data-plane mechanisms** (health checks, ARC routing controls) rather than on API calls to change records during a Regional event.

**Hosted zones**
- **Public hosted zone:** answers queries from the internet for a domain you own. You get 4 name servers (a "delegation set"); reusable delegation sets let many zones share the same NS records (useful for white-label/SaaS).
- **Private hosted zone (PHZ):** answers only for queries from associated VPCs (via the Route 53 Resolver at VPC+2). VPCs need `enableDnsSupport` and `enableDnsHostnames` set to true.
- Pricing essentials: per hosted zone per month + per million queries. **Alias queries to AWS resources (ELB, CloudFront, S3 website, API Gateway, etc.) are free**; CNAME queries are charged.

**Record types you must know**

| Type | Purpose | SAP-relevant notes |
|---|---|---|
| A / AAAA | Name → IPv4 / IPv6 | Can be alias records pointing at AWS resources |
| CNAME | Name → another name | **Not allowed at the zone apex** (`example.com`); cannot coexist with other records of the same name; charged per query |
| Alias (Route 53 extension) | Name → AWS resource or another record in the same zone | Works at the apex; free queries to AWS targets; TTL inherited from target; supports **Evaluate Target Health** |
| MX | Mail exchangers | Priority values |
| TXT | Arbitrary text | Domain verification (ACM email/SES), SPF, DKIM |
| NS / SOA | Delegation / zone authority | NS of parent must match your zone's name servers when migrating DNS providers |
| CAA | Which CAs may issue certs | Must permit Amazon if using ACM |
| SRV, PTR, NAPTR, SPF, DS, HTTPS/SVCB | Service location, reverse lookup, DNSSEC chain (DS) etc. | DS record placed in parent zone for DNSSEC |

**Alias vs CNAME — the classic trap**

| | Alias record | CNAME |
|---|---|---|
| Zone apex (`example.com`) | **Yes** | **No** (DNS RFC forbids) |
| Targets | CloudFront, ELB (ALB/NLB/CLB), API Gateway, S3 website endpoint, Global Accelerator, VPC interface endpoint, Elastic Beanstalk, AppSync custom domain, another Route 53 record in same zone | Any DNS name |
| Query cost | Free for AWS-resource targets | Charged |
| TTL | Uses target's TTL (cannot set for AWS targets) | You set it |
| Health | **Evaluate Target Health** (e.g., ALB with no healthy targets → record unhealthy) | Needs a separate health check |
| Can point to EC2 public DNS name? | No | Yes |

> Exam rule: "**Map the naked/apex domain to a load balancer/CloudFront distribution**" → **alias A/AAAA record**.

**TTL strategy for migrations and cutovers**
- Resolvers cache answers for the TTL; you cannot force them to forget. So **lower the TTL well in advance** — at least one *old* TTL period before the change (e.g., old TTL 86,400 s → set to 60 s at least 24–48 h before cutover).
- Also lower TTLs on **NS records** when moving DNS providers (the parent/registrar NS TTL is often 48 h and is outside your control, so keep both old and new providers serving identical records during the transition).
- After a stable cutover, raise TTLs again (lower query cost, better resilience against DNS outages).
- Low TTL ≠ instant: some clients/JVMs/ISPs ignore or extend TTLs (Java historically cached indefinitely with a security manager). This is why **Global Accelerator (static anycast IPs)** wins when the stem says "failover must not depend on client DNS caching".
- Alias records to AWS resources use the resource's TTL (typically 60 s for ELB).

### 2.2 Route 53 routing policies

| Policy | How it decides | Typical use | Health checks? | PHZ? |
|---|---|---|---|---|
| **Simple** | One record, may return multiple values (random order, client chooses) | Single resource | No (cannot attach) — multiple values are all returned even if unhealthy | Yes |
| **Weighted** | Proportional to weight (0–255) per record of the same name/type | Canary, blue/green, A/B, gradual migration (e.g., 90/10 on-prem/AWS) | Yes; weight 0 = no traffic unless all are 0 | Yes |
| **Latency** | Lowest measured latency between the **resolver's/client's network** and the **AWS Region** you tag the record with | Multi-Region active-active performance | Yes — unhealthy Region skipped | Yes |
| **Failover** | Primary served while healthy; secondary when primary unhealthy | Active-passive DR (pilot light / warm standby), static "sorry" site on S3 | **Required** on primary (health check or Evaluate Target Health) | Yes |
| **Geolocation** | Continent / country / US state of the user (most specific match wins) | Compliance (content per country), localisation, licensing restrictions | Yes | Yes |
| **Geoproximity** | Distance between user and resource (AWS Region, Local Zone group, or lat/long), adjusted by **bias** | Shift traffic between Regions geographically; gradual expansion to a new Region | Yes | Yes |
| **Multivalue answer** | Returns **up to 8 healthy** records chosen at random | Client-side load spreading with health filtering for simple fleets | Yes (that's the point vs simple) | Yes |
| **IP-based** | Client source IP (or EDNS0 client subnet) matched against **CIDR collections** you upload | Route specific ISPs/enterprise networks to specific endpoints; optimise for known network topology; reduce egress costs | Yes | **Public only** |

Key details:
- **Geolocation** needs a **Default** record; otherwise users from unmapped locations get **no answer**. Geolocation is about *where the user is* (compliance); latency is about *speed*.
- **Geoproximity bias:** `biased distance = actual distance × (1 − bias/100)`. Positive bias **1 to 99** expands the area routed to that resource; negative **−1 to −99** shrinks it. Change bias in small steps. Geoproximity records can now be created directly, and visually with **Traffic Flow** (traffic policies; billed per policy record per month).
- **Latency routing** uses Route 53's historical latency measurements per Region, not a live probe to your endpoint. Two endpoints in the same Region need a second level (e.g., latency → weighted alias tree).
- **EDNS0 Client Subnet:** Route 53 uses it (when the resolver sends it) for geolocation/latency/geoproximity/IP-based accuracy; otherwise it uses the resolver's IP.
- **Combining policies:** build trees with alias records pointing to other records — e.g., **failover (primary = latency set, secondary = S3 static site)**, or **latency → weighted** for per-Region canaries. Set **Evaluate Target Health = Yes** on alias records in the tree so health propagates.
- **Weighted** records with health checks: unhealthy records are removed; if *all* are unhealthy, Route 53 returns all of them (fail open). Same fail-open behaviour exists for other policies — "all unhealthy → treat all as healthy".
- **Multivalue is not a load balancer** — no session affinity, no connection draining, no Layer 7 logic.

### 2.3 Route 53 health checks

**Types**
1. **Endpoint health checks** — HTTP, HTTPS, TCP against an IP or domain name.
   - Health checkers in multiple global locations (you can choose which); **interval 30 s (standard) or 10 s (fast, extra cost)**; **failure threshold** consecutive checks (default 3).
   - Endpoint is **healthy if > 18% of health checkers report healthy**.
   - HTTP/HTTPS: TCP connect within **4 s**, then **2xx/3xx within 2 s**. TCP: connect within **10 s**. HTTPS checks do **not** validate the certificate.
   - **String matching:** the string must appear entirely within the **first 5,120 bytes** of the body (useful for "deep" health pages that return 200 even when degraded — put a token like `STATUS:OK`).
   - Optional **latency graphs**, inversion, SNS notification via CloudWatch metric `HealthCheckStatus` (metrics live in **us-east-1**).
   - Your firewall/security groups must allow Route 53 health-checker IP ranges (published in `ip-ranges.json`, service `ROUTE53_HEALTHCHECKS`).
2. **Calculated health checks** — a parent combining up to **255 child** checks with "healthy if at least N children healthy" (or AND/OR logic). Use to say "Region healthy only if web tier AND API tier AND DB replica are healthy".
3. **CloudWatch alarm–based health checks** — health follows the **data stream** of a CloudWatch alarm (OK → healthy, ALARM → unhealthy, insufficient data → configurable: healthy / unhealthy / last known).
   - **The only way to health-check private resources** (internal ALB, RDS, on-prem via VPN, records in a **private hosted zone**) because Route 53 health checkers live on the internet and cannot reach private IPs.
   - Also lets you fail over on business metrics (e.g., error rate, queue depth, DynamoDB replication latency).
   - Same account only (no cross-account alarms). You cannot force status with `SetAlarmState`.

**Evaluate Target Health (ETH)** — on alias records only. For an ALB alias, the record is healthy if the ALB has at least one healthy target in its target groups. No separate health check cost. You **cannot** enable ETH when the alias target is a **CloudFront distribution** — attach an explicit health check to the record if you need one. ETH between records in your own zone (alias → alias) is how health propagates up a routing tree.

**Gotchas**
- A new health check is considered **healthy until proven otherwise**.
- Health checks attached to records are evaluated in the data plane — failover happens automatically, no API call required. This is the **recommended DR pattern** (vs a Lambda that rewrites records — which depends on the us-east-1 control plane).
- Health checking the **ALB DNS name** with HTTP checks tests the full path; ETH tests only target-group health.

### 2.4 Private hosted zones, cross-account and split-horizon DNS

- **Association:** a PHZ can be associated with many VPCs, across Regions and **across accounts**. Cross-account association is done via CLI/SDK/API (not the console):
  1. In the **PHZ-owning account**: `create-vpc-association-authorization` (hosted zone ID + VPC ID/Region).
  2. In the **VPC-owning account**: `associate-vpc-with-hosted-zone`.
  3. Optionally delete the authorization afterwards (the association remains).
- **Route 53 Profiles** (newer): bundle PHZs, Resolver rules and DNS Firewall rule groups into a Profile and **share it via AWS RAM** to accounts/OUs, then associate the Profile with VPCs — far less operational overhead at scale than per-VPC authorizations. Expect this as the "least operational overhead" answer for hundreds of VPCs.
- **Overlapping namespaces:** if a PHZ and a Resolver forwarding rule both match a name, the **forwarding rule wins**; between overlapping PHZs (e.g., `example.com` and `dev.example.com`) the **most specific** wins. If a PHZ matches the name but doesn't contain the record, Resolver returns NXDOMAIN — it does not fall back to public DNS.
- **Split-horizon (split-view) DNS:** create a **public** and a **private** hosted zone with the **same name**. VPC clients get private answers (internal ALB, private IPs); internet clients get public answers. Classic use: `app.example.com` resolves to a private endpoint inside the VPC and to CloudFront externally. On-premises clients get the private view only if they forward to a Route 53 Resolver **inbound endpoint** (see [Chapter 04](04-Networking-VPC-and-Hybrid-Connectivity.md) for Resolver inbound/outbound endpoints, forwarding rules, rule sharing via RAM, and DNS Firewall).
- **Interface VPC endpoints** with private DNS rely on AWS-managed PHZs; in hub-and-spoke designs you disable private DNS on spoke endpoints and create your own PHZ for the service name associated to all VPCs (covered in ch04).

### 2.5 DNSSEC

- Route 53 supports **DNSSEC signing** for **public** hosted zones and **DNSSEC validation** on Route 53 Resolver for VPCs.
- **Key-signing key (KSK)** is backed by a **customer managed KMS asymmetric key (ECC_NIST_P256) in us-east-1**; Route 53 manages the **zone-signing key (ZSK)** automatically.
- Establish the chain of trust by adding the **DS record** to the parent zone (via Route 53 Registrar or your registrar).
- Operational musts: lower TTLs before enabling, create CloudWatch alarms on `DNSSECInternalFailure` and `DNSSECKeySigningKeysNeedingAction`, and **never delete/disable the KMS key** while signing is enabled — the zone would become unresolvable for validating resolvers. To disable, remove the DS record from the parent first, wait for TTL, then disable signing.
- DNSSEC protects against **spoofing/cache poisoning** (integrity/authenticity); it does **not** encrypt queries.

### 2.6 Route 53 Resolver (pointer)

Resolver (VPC+2) answers for PHZs, VPC DNS and public names. **Inbound endpoints** let on-prem resolve AWS private names; **outbound endpoints + forwarding rules** let VPCs resolve on-prem names; rules are shared via RAM; **Resolver DNS Firewall** filters outbound DNS (exfiltration control); **Resolver query logging** to CloudWatch Logs/S3/Firehose. Full treatment: [Chapter 04](04-Networking-VPC-and-Hybrid-Connectivity.md).

### 2.7 Amazon Application Recovery Controller (ARC) — formerly Route 53 ARC

ARC provides **multi-AZ** and **multi-Region** recovery tooling. On the exam it appears as "Route 53 Application Recovery Controller"; current docs call it **Amazon Application Recovery Controller (ARC)**.

**Multi-Region capabilities**
- **Routing control:** highly reliable **on/off switches** that drive special **routing control health checks** attached to Route 53 failover (or other) records. Flipping a switch changes DNS answers through the Route 53 **data plane** — no control-plane change to records.
  - **Cluster** = a data plane of endpoints in **five AWS Regions**; you call any cluster endpoint to change state (the API is designed so you can succeed even if some Regions are impaired). A cluster is a fixed hourly cost, so organisations typically share one cluster across many applications.
  - **Control panels** group routing controls.
  - **Safety rules:** **assertion rules** (e.g., "at least one Region must be ON" — prevents failing everything off) and **gating rules** (a master switch that must be ON before others can change — e.g., an approval gate).
  - Use the **CLI/API against cluster endpoints** during an event (recommended), not the console, and keep runbooks/credentials ready outside the impaired Region.
- **Readiness check:** continuously audits that replicas are scaled/configured alike (quotas, capacity, Auto Scaling, DynamoDB capacity, routing). **Not in the critical path** of failover. **Closed to new customers from 30 April 2026** (existing customers can continue); AWS recommends **Region switch plan evaluation** instead.
- **Region switch** (newer): orchestrated, cross-account **multi-Region recovery plans** with execution blocks (e.g., scale up standby, promote Aurora global database, update ARC routing controls / Route 53 records, run custom Lambda/SSM steps) and continuous plan evaluation. Treat as an *SAP-C03 preview* topic; on SAP-C02 the expected answer is still routing controls + Route 53 health checks.

**Multi-AZ capabilities**
- **Zonal shift:** manually shift traffic for a supported resource (ALB, NLB, EC2 Auto Scaling groups, EKS and others) **away from one impaired AZ** within the Region, for a temporary, extendable period of **up to 3 days**. Great for "gray failures" and bad deployments in one AZ.
- **Zonal autoshift:** you authorise **AWS** to shift traffic away from an AZ when AWS telemetry detects an impairment. **Practice runs are required** (weekly ~30-minute shifts) and you must **pre-scale** so remaining AZs can absorb the load — autoshift does not wait for Auto Scaling.

> **When ARC is the answer:** "multi-Region active-passive/active-active with **manual, highly reliable, human-approved** failover", "avoid split-brain / ensure only one Region is active" (safety rules), "do not depend on the Route 53 control plane", "verify the standby has capacity" (readiness check — historically), "AZ impairment / gray failure" (zonal shift/autoshift).
>
> **When plain Route 53 failover is enough:** automatic failover based on endpoint health, lower cost, RTO of minutes acceptable.

### 2.8 Amazon CloudFront — architecture and origins

CloudFront is a global CDN and reverse proxy with **hundreds of edge locations (POPs)** plus **Regional edge caches (RECs)** — a mid-tier cache that holds less-popular objects longer. Request path: viewer → nearest POP (TLS terminated, WAF evaluated, CloudFront Function runs) → REC (on a cache miss) → **Origin Shield** (optional) → origin, all over the AWS backbone with persistent, tuned connections to the origin.

**Distribution** = configuration unit: domain `dxxxx.cloudfront.net`, up to **100 alternate domain names (CNAMEs)** by default, one TLS certificate, origins (default quota 100), cache behaviors, WAF web ACL, logging, price class, geo restriction. Config changes deploy globally in minutes. Default soft quotas worth knowing: **150 Gbps** and **250,000 requests/s per distribution** (request increases for large events).

**Origins**

| Origin type | Notes |
|---|---|
| **S3 bucket (REST endpoint)** | Use **Origin Access Control (OAC)**; bucket stays private (Block Public Access on). Supports SSE-KMS (KMS key policy must allow the CloudFront service principal), PUT/POST uploads. |
| **S3 static website endpoint** | Treated as a **custom origin** (HTTP only to origin, needs a publicly readable bucket) — **cannot use OAC/OAI**. Choose it only if you need S3 website features (redirect rules); otherwise use the REST endpoint + OAC + a CloudFront Function for `index.html` rewrites in subfolders. |
| **Custom origin (HTTP server)** | ALB, NLB, EC2, API Gateway, on-premises servers, other clouds. Must be publicly resolvable/reachable unless using VPC origins. Tune origin protocol policy, ports, response timeout (1–120 s by default; increase via quota), keep-alive (1–300 s), connection attempts (1–3) and connection timeout (1–10 s) — these drive how fast origin failover kicks in. |
| **VPC origins** | **Private** ALB, NLB or EC2 instance in **private subnets**; CloudFront reaches it through a service-managed ENI. The VPC must have an internet gateway attached (marks it as able to receive internet traffic; not used for routing). Origin SG allows the CloudFront origin-facing managed prefix list or the service-managed SG `CloudFront-VPCOrigins-Service-SG` (more restrictive). Shareable across accounts (console or AWS RAM). Restrictions: no gRPC, **no Lambda@Edge origin-request/origin-response triggers**, NLBs with TLS listeners not supported, GWLB not supported. No additional charge. **Best answer for "the ALB must not be internet-facing" with least overhead.** |
| **AWS Elemental MediaPackage v2** | Live/VOD packaging origin (HLS/DASH/CMAF); OAC supported. |
| **AWS Elemental MediaStore** | Legacy low-latency media origin. **AWS discontinued MediaStore on 13 Nov 2025**; AWS points to S3 (simple live origination) or MediaPackage (advanced, cross-Region failover). Older exam questions may still list it as the live-video origin. |
| **Lambda function URL** | OAC supported (SigV4 signing) — serverless origin without API Gateway. |
| **S3 Multi-Region Access Point** | OAC-signed requests to an MRAP for multi-Region active-active buckets. |

**Origin Access Control (OAC) vs legacy Origin Access Identity (OAI)**

| | OAC (recommended) | OAI (legacy) |
|---|---|---|
| Signing | SigV4, short-term credentials, configurable signing behavior | Special CloudFront identity principal |
| S3 objects encrypted with **SSE-KMS** | **Yes** | No |
| All Regions incl. opt-in Regions launched after Dec 2022 | **Yes** | No |
| Dynamic requests (PUT, POST, DELETE) to S3 | **Yes** | Limited |
| Other origin types | MediaPackage v2, Lambda URLs, MRAP | S3 only |
| Bucket policy principal | `cloudfront.amazonaws.com` with condition `AWS:SourceArn` = distribution ARN | OAI ARN / canonical user |

> Migration path: create the OAC, add a bucket-policy statement for it while keeping the OAI statement, switch the origin to the OAC, verify, then remove the OAI statement.

### 2.9 CloudFront caching — behaviors, policies, keys, TTLs

**Cache behaviors** map **path patterns** (`/api/*`, `/static/*`, `*.jpg`) to an origin (or origin group) plus settings: viewer protocol policy (e.g., redirect HTTP→HTTPS), allowed methods, cache policy, origin request policy, response headers policy, function associations, restrict viewer access (trusted key groups), field-level encryption, compression, real-time log config. Evaluated **in order**; the **default behavior (`*`)** catches everything else. Default quota **75 behaviors per distribution**.

**Cache policy vs origin request policy vs response headers policy**

| Policy | Controls | Key point |
|---|---|---|
| **Cache policy** | The **cache key** (which headers, cookies, query strings are part of it) + **TTLs** (min/default/max) + Gzip/Brotli normalisation | Everything in the cache key is **also forwarded** to the origin |
| **Origin request policy** | Extra values forwarded to the origin **without** being in the cache key (e.g., `User-Agent`, session cookies, `CloudFront-Viewer-Country`, all query strings) | Gives the origin what it needs while keeping the cache key small |
| **Response headers policy** | Headers CloudFront adds/removes in responses: CORS, security headers (HSTS, CSP, X-Frame-Options), custom headers, Server-Timing | No origin code changes |

Managed policies to recognise: **CachingOptimized** (no headers/cookies/query strings in the key), **CachingDisabled** (APIs/dynamic content), **AllViewer** and **AllViewerExceptHostHeader** origin request policies (the latter for API Gateway/Lambda URL origins that reject a foreign `Host` header), **CORS-S3Origin**. Default quotas: 20 custom cache policies and 20 custom origin request policies per account; 10 headers/cookies/query strings each per policy.

**Cache hit ratio optimisation (a D3 3.3 favourite)**
1. **Minimise the cache key**: include only the headers/cookies/query strings that actually change the response. Putting `Authorization`, all cookies, or `User-Agent` in the key explodes the number of variants.
2. Use **origin request policies** to forward values the origin needs but that don't vary the content.
3. **Normalise** with a **CloudFront Function** (lowercase paths, sort query strings, strip `utm_*` tracking parameters, collapse device detection into a small set of values).
4. Prefer CloudFront-generated headers (`CloudFront-Viewer-Country`, `CloudFront-Is-Mobile-Viewer`) over raw headers.
5. Set long TTLs via `Cache-Control: max-age`/`s-maxage` at the origin for static assets and use **versioned file names** for changes.
6. Enable **Origin Shield** for multi-Region/multi-CDN or high-fan-out origins.
7. Split static and dynamic paths into separate behaviors.
8. Enable compression through the cache policy (it normalises `Accept-Encoding`) rather than adding the raw header to the key.
9. Monitor `CacheHitRate`, the cache statistics and popular-objects reports, and **real-time logs** to find `Miss`/`RefreshHit` patterns.

**TTLs and invalidation**
- TTL resolution: origin `Cache-Control max-age`/`s-maxage`/`Expires` are honoured **within** the policy's **min and max TTL**; the **default TTL** applies when the origin sends nothing. CachingOptimized: min 1 s, default 86,400 s (1 day), max 31,536,000 s (1 year).
- **Invalidation** removes objects from edge caches before expiry. First **1,000 paths per month are free**, then charged per path; a wildcard (`/images/*`) counts as one path. Throughput is quota-limited (paths per second, one wildcard invalidation per second). Completes in seconds to minutes — it's an emergency tool, not a deployment strategy.
- **Versioned object names** (`app.3f9c1.js`, `/v42/logo.png`) are the **best practice**: instant, atomic, free, allow very long TTLs, and old versions keep working for cached HTML pages that still reference them. Exam: "frequently updated assets; avoid invalidation cost and delay" → **versioned file names**.
- **Invalidation by cache tags** (newer) invalidates groups of objects tagged by the origin.

**Origin Shield**
- An extra, centralised caching layer in **one AWS Region** you choose (the Region with the lowest latency to the origin). All RECs funnel through it → **higher overall cache hit ratio, fewer origin requests, collapsed simultaneous requests** for the same object.
- Ideal for: origins with limited capacity, on-premises origins, **multi-CDN** setups, **live/VOD streaming** with just-in-time packaging, on-the-fly image transformation.
- Charged per request that goes to Origin Shield.

**Origin groups (origin failover)**
- Primary + secondary origin; CloudFront retries the secondary when the primary returns the status codes you choose (**400, 403, 404, 416, 500, 502, 503, 504**) or on connection failure/timeout.
- Only for **GET, HEAD, OPTIONS** requests (not writes). Per-request failover — no health checks, no failback timer.
- Classic pattern: S3 bucket in Region A (primary) + **S3 Cross-Region Replication** replica in Region B (secondary), both behind OAC. For write-heavy multi-Region S3 use **S3 Multi-Region Access Points**.
- Default quota: 10 origin groups per distribution. Lower connection timeout/attempts to fail over faster.

### 2.10 CloudFront security features

**HTTPS, SNI and ACM**
- The viewer certificate from **ACM must be in us-east-1 (N. Virginia)**, regardless of where your origin is. (ALB/regional API Gateway certificates live in their own Region.) One certificate per distribution — use SAN/wildcard certificates for multiple names.
- **SNI** (default, free) vs **dedicated IP** custom SSL (only for legacy clients without SNI; significant monthly fee per distribution).
- **Viewer protocol policy**: HTTP and HTTPS / Redirect HTTP to HTTPS / HTTPS only. **Origin protocol policy**: HTTP only / HTTPS only / match viewer. End-to-end TLS requires the origin certificate to be from a trusted CA and to match the origin domain (or forwarded Host header) — **self-signed origin certificates fail**.
- **Security policy** sets the minimum viewer TLS version/ciphers (e.g., `TLSv1.2_2021`). HTTP/2 and **HTTP/3 (QUIC)** supported for viewers; **mutual TLS (mTLS)** viewer authentication with trust stores is available.

**Signed URLs vs signed cookies (private content)**

| | Signed URL | Signed cookies |
|---|---|---|
| Scope | **One file** per URL (custom policy can use a wildcard resource) | **Many files** (all HLS/DASH segments, a whole premium area) |
| Client | Works where cookies aren't supported (native apps, download managers) | Browsers/players that handle cookies; **existing URLs don't change** |
| Policy | Canned (expiry only) or custom (start time, expiry, **source IP range**, wildcard resource) | Same canned/custom options |

- **Signers:** use **trusted key groups** (public keys uploaded to CloudFront, managed via IAM; default 5 public keys per key group, 4 key groups per behavior). **Trusted signers (CloudFront key pairs that only the root user can create)** are legacy; any answer requiring root credentials for routine operations is wrong.
- Your application (e.g., a Lambda behind login) signs with the **private key** (keep it in Secrets Manager); CloudFront verifies with the public key.
- Signed URLs/cookies **do not stop anyone bypassing CloudFront** — combine with OAC/VPC origins.
- S3 **presigned URLs** are different: direct-to-S3 access using the signer's IAM credentials, no CDN caching — right for direct uploads to S3 or one-off downloads where a CDN isn't needed.

**Field-level encryption (FLE)**
- CloudFront encrypts specific **POST form fields** (card number, SSN) at the edge with your **RSA public key**; only applications holding the private key can decrypt — the data stays encrypted through ALB, web tier, logs and queues. Limits: up to **10 fields** per request, **16 KB** per field, request body ≤ **1 MB**. Requires HTTPS.
- Use when "only the payment microservice may ever see the card number, even though the request traverses several tiers".

**Geo restriction**
- Country-level **allow list or block list** per distribution; CloudFront returns **403** (customisable error page). Based on a third-party GeoIP database.
- Finer control (per path, per US state, custom responses, combined with other conditions) → **AWS WAF geo-match** rule, or a CloudFront Function reading `CloudFront-Viewer-Country`.
- Geo restriction ≠ data residency. It's correct for **content licensing**; "data must not leave country X" needs a Regional architecture decision.

**Protecting the origin (make CloudFront the only path)**
1. **S3** → OAC + bucket policy with `AWS:SourceArn` condition.
2. **Private ALB/NLB/EC2** → **VPC origins** (strongest, least effort).
3. **Public ALB / custom origin** (layered):
   - Origin SG inbound from the **AWS-managed prefix list `com.amazonaws.global.cloudfront.origin-facing`** (it consumes many SG rule entries — check your rules-per-SG quota; an IPv6 list exists too).
   - CloudFront adds a **secret custom origin header** (e.g., `X-Origin-Verify: <random>`); an ALB listener rule or **WAF web ACL on the ALB** allows only requests carrying it (otherwise fixed 403). Rotate it with **Secrets Manager + a rotation Lambda** that updates CloudFront and the WAF/ALB rule while accepting both values during rotation.
   - The prefix list alone is not enough — every CloudFront customer shares those IPs; the header proves the request came via *your* distribution.
4. **API Gateway** → **regional** endpoint behind your CloudFront distribution plus a custom header/WAF check, or a private API. Avoid placing your own distribution in front of an edge-optimized API (double CloudFront hop).

### 2.11 CloudFront observability, deployment and pricing

- **Standard (access) logs:** to S3, CloudWatch Logs or Data Firehose (v2 logging); minutes of delay.
- **Real-time logs:** to **Kinesis Data Streams** within seconds, with configurable **sampling rate** and fields; typical pipeline → Data Firehose → OpenSearch/S3 for live dashboards. Charged per log line.
- **CloudWatch metrics** (published in us-east-1): requests, bytes, 4xx/5xx error rates; **additional metrics** (cache hit rate, origin latency, per-status error rates) for an extra charge.
- **Continuous deployment:** a **staging distribution** plus a **continuous deployment policy** on the primary. Route a share of production traffic to staging by **weight** (capped at 15%) with optional **session stickiness** (cookie; idle duration 300–3,600 s) or by **header** (header name must start with `aws-cf-cd-`). Primary and staging **do not share a cache**. **Promote** copies the staging config to the primary. Use for testing cache policies, functions, new origins (e.g., moving to VPC origins) on real traffic — blue/green for the CDN configuration itself.
- **Price classes:** **All** (every edge location, best performance), **200** (excludes the most expensive locations), **100** (North America, Europe, Israel — cheapest). Viewers outside the class are still served, from an included location with higher latency.
- **Pricing essentials:** data transfer out to internet per GB by geography, per-10,000-request fees, **no charge for data transfer from AWS origins to CloudFront**, invalidations beyond 1,000 free paths/month, function invocations, Origin Shield requests, real-time logs, dedicated-IP SSL. **CloudFront Security Savings Bundle** (1-year commitment, savings plus WAF usage credit) and newer **flat-rate pricing plans** (bundled CDN + WAF + DDoS protection for a fixed monthly fee) can cut cost.
- **Anycast static IPs** for CloudFront exist for customers that must allow-list or zero-rate traffic — rarely the exam answer (Global Accelerator usually is).

### 2.12 Dynamic content acceleration, WebSockets, gRPC

- CloudFront accelerates **non-cacheable** traffic too: TLS termination near the user, **persistent reused connections** to the origin, TCP optimisations, AWS backbone. Use **CachingDisabled** + **AllViewer**(ExceptHostHeader) for API behaviors and allow all methods (GET, HEAD, OPTIONS, PUT, POST, PATCH, DELETE).
- **WebSockets** work natively (HTTP Upgrade); the connection is closed if the origin sends no bytes for 10 minutes.
- **gRPC** over HTTP/2 is supported (not via VPC origins).
- Only GET/HEAD (optionally OPTIONS) responses are cached; POST/PUT are proxied. Max cacheable GET response: 50 GB.

### 2.13 Edge compute — CloudFront Functions vs Lambda@Edge

| | **CloudFront Functions** | **Lambda@Edge** |
|---|---|---|
| Runs at | Every edge location (POP) | Regional edge caches (Lambda in the nearest AWS Region) |
| Runtime | JavaScript (ECMAScript 5.1 compliant; runtime 2.0 adds newer features) | Node.js, Python |
| Triggers | **Viewer request, viewer response** only | Viewer request, viewer response, **origin request, origin response** |
| Duration | **Sub-millisecond** | Up to 30 s per current docs (older material and many exam questions use **5 s for viewer triggers / 30 s for origin triggers**) |
| Memory | 2 MB | 128 MB for viewer triggers; up to 10,240 MB for origin triggers |
| Code size | **10 KB** (not adjustable) | 50 MB compressed per current docs (older material: **1 MB viewer / 50 MB origin**) |
| Generated response size | — | 40 KB viewer triggers / 1 MB origin triggers |
| Scale | Millions of requests/s | Up to 10,000 requests/s per Region (concurrency shared with Lambda in that Region) |
| **Network access** | **No** | **Yes** (DynamoDB, S3, external APIs, AWS SDK) |
| File system / request body | No / No | Yes / Yes |
| Geolocation & device data | Yes | Origin triggers only |
| KeyValueStore | **Yes** (runtime 2.0) | No |
| Deploy/test | Build and test entirely inside CloudFront | Author in **us-east-1**, publish a numbered version, replicated globally; logs land in CloudWatch in each executing Region |
| Price | Roughly one-sixth of Lambda@Edge per invocation, no duration charge | Requests + GB-seconds |
| Typical uses | Cache-key normalisation, header add/remove (HSTS, True-Client-IP), URL rewrites/redirects (`/about/` → `/about/index.html`), A/B bucketing by cookie, **JWT validation** with a secret from KVS, simple geo/device redirects | Auth that needs a lookup (OIDC/Cognito token exchange), **dynamic origin selection** by header/cookie, image resizing in origin response, generating responses from a database, SEO pre-rendering, body inspection |

**CloudFront KeyValueStore (KVS):** a global, low-latency key-value datastore read from CloudFront Functions — change config (redirect maps, feature flags, A/B weights, allowed API keys) **without redeploying function code**. Limits: **5 MB per store**, key ≤ 512 bytes, value ≤ 1 KB, one KVS per function. Updated via API; changes propagate to the edge within seconds.

> Heuristic: lightweight, high-volume, viewer-side, no network → **CloudFront Functions**. Needs network/SDK/body/origin-side triggers or > 10 KB of code → **Lambda@Edge**. Heavy logic that doesn't need to run at the edge → a regular Regional Lambda/API behind CloudFront.

### 2.14 AWS Global Accelerator

A **network-layer (Layer 4) accelerator**. Clients connect to **two static anycast IPv4 addresses** (four for dual-stack: 2 IPv4 + 2 IPv6), each served from a separate **network zone** so clients can retry on the other. Traffic enters the AWS network at the nearest edge location and rides the backbone to the optimal healthy Regional endpoint. **No caching**; any application protocol over **TCP or UDP**.

**Components**
- **Accelerator** (standard or custom routing) → **listeners** (port or port range; **TCP, UDP, or both**) → **endpoint groups** (one per **Region**) → **endpoints** (ALB — internet-facing or **internal**, NLB, EC2 instances, Elastic IPs).
- **Traffic dial** (per endpoint group, 0–100%): the share of traffic destined for that Region that is allowed to go there; the remainder goes to other endpoint groups. Use for **Regional blue/green**, maintenance (dial to 0), and gradual Region launches.
- **Endpoint weights** (0–255): proportional distribution among endpoints inside one Region (e.g., blue/green ALBs in the same Region).
- **Client affinity:** **None** (default; 5-tuple hash — source IP, source port, destination IP, destination port, protocol) or **Source IP** (2-tuple) for stateful applications that need the same endpoint across connections.
- **Client IP preservation:** supported for ALB and EC2 endpoints (and NLB endpoints in supported configurations) — backends see the real client IP; security groups must then allow client IPs.
- **Health checks:** for ALB/NLB endpoints Global Accelerator uses **ELB target-group health** (ALB healthy if every target group has at least one healthy target); for EC2/EIP endpoints it runs its own checks (configurable port/protocol/interval/threshold; UDP listeners are health-checked over TCP). If **no** endpoint is healthy, traffic goes to **all** endpoints (fail open).
- **Fast Regional failover:** clients keep the same anycast IPs; failover is a routing decision inside AWS — typically **within seconds** and **not subject to DNS TTLs or client DNS caching**. This is the key differentiator from Route 53.
- **BYOIP:** bring your own IPv4 address range so partners' existing allow-lists keep working.
- **DDoS:** Shield Standard included; eligible for Shield Advanced. Anycast spreads volumetric attacks across many edge locations.
- **Pricing:** fixed hourly fee per accelerator + **Data Transfer-Premium** per GB (dominant direction; varies by source/destination geography).

**Custom routing accelerators**
- Deterministically map each **listener port** to a specific **EC2 private IP + port** in **VPC subnet** endpoints. A matchmaking service tells the client "connect to `<static IP>:<port N>`", which always lands on game server X.
- Use cases: **multiplayer game session servers**, VoIP/real-time media with user-to-instance assignment.
- No load balancing or health-based rerouting — traffic goes to the mapped destination (you allow/deny destinations). No dual-stack.

### 2.15 Edge security: AWS WAF and AWS Shield (brief — details in ch06)

- **AWS WAF** attaches to **CloudFront** (web ACL in **Global** scope, managed from us-east-1) and, in Regional scope, to **ALB, API Gateway REST APIs, AppSync, Cognito user pools, App Runner, Verified Access**. Rules: AWS Managed Rules (core rule set, known bad inputs, SQLi, IP reputation, **Bot Control**, **account takeover / account creation fraud prevention**), rate-based rules, geo match, IP sets, regex, header checks, CAPTCHA/Challenge. WAF on CloudFront blocks attacks at the edge before they consume origin capacity. **Firewall Manager** enforces WAF/Shield policies across an Organization. See [Chapter 06](06-Security-Data-Protection-and-Threat-Detection.md).
- **Shield Standard:** automatic, free L3/L4 protection for all customers; strongest on CloudFront, Route 53 and Global Accelerator because of their edge footprint.
- **Shield Advanced:** paid subscription per Organization (monthly fee with a 1-year commitment, plus data-transfer usage fees) for **CloudFront, Route 53 hosted zones, Global Accelerator, ELB and EC2 Elastic IPs**: enhanced detection, **automatic application-layer DDoS mitigation** (it manages WAF rules for you), **Shield Response Team (SRT)** 24/7, **cost protection** (credits for scaling charges caused by a DDoS event), health-based detection with Route 53 health checks, WAF fees included for protected resources.
- Phrasing: "protection from **DDoS-driven cost spikes** and **24/7 expert response**" → **Shield Advanced**. "Block SQL injection/XSS/bots at the edge" → **WAF on CloudFront**.

### 2.16 Edge infrastructure: Local Zones, Wavelength, Outposts

| | **AWS Local Zones** | **AWS Wavelength** | **AWS Outposts** |
|---|---|---|---|
| What | AWS-operated infrastructure in a **metro area**, an extension of a parent Region | AWS compute/storage **inside telecom carriers' 5G networks** | **AWS-owned, AWS-managed hardware in your data center/site** |
| Latency target | **Single-digit ms** to end users in that metro | Single-digit ms to **mobile/5G devices** (traffic stays in the carrier network) | **Lowest latency to on-premises systems**; local data processing |
| Networking | Opt in to the zone group; add a Local Zone subnet to your VPC | Wavelength Zone subnet + **carrier gateway** (carrier IPs) | **Service link** to the parent Region (required for management) + **local gateway (LGW)** to your on-prem network |
| Services | Subset: EC2, EBS, ECS/EKS, ALB, FSx, some RDS, Direct Connect in some zones | Subset: EC2, EBS, ECS/EKS | **Racks (42U):** EC2, EBS, S3 on Outposts, ECS/EKS, RDS, ElastiCache, EMR, ALB. **Servers (1U/2U):** EC2, ECS, IoT Greengrass on instance storage — for space-constrained sites (retail stores, branches, factory floors) |
| Data residency | Helps where a Local Zone exists in-country/metro (also **Dedicated Local Zones** for sovereignty-sensitive customers) | Not a residency tool | **Data stays on premises** — strongest residency answer |
| Facility | AWS | Carrier | Yours (you provide space, power, network uplink) |
| Commercials | Pay-as-you-go/Savings Plans (usually a premium over the parent Region) | Pay-as-you-go | Typically a 3-year term (all/partial/no upfront) |
| Typical scenario | VFX rendering for artists in LA, real-time gaming, live broadcast production, migrating latency-sensitive apps out of a metro DC | AR/VR, connected vehicles, live video analytics, ML inference for mobile apps | Manufacturing MES, hospital systems, low-latency trading, regulated data that cannot leave the site, local data processing with AWS APIs |

Key gotchas:
- **Outposts needs connectivity** to its parent Region for the control plane and is **not designed for disconnected operation**: running instances continue during a service-link outage, but you cannot launch or modify resources. AWS Snow Family devices were historically the "disconnected/rugged edge" answer, but **AWS Snowball Edge is no longer available to new customers** (existing customers unaffected); AWS now points new customers to **Outposts** for edge compute and to DataSync / AWS Data Transfer Terminal for data movement. Older exam questions may still offer Snowball Edge for disconnected edge compute.
- Local Zone and Wavelength subnets are part of your VPC — same security groups, route tables, IAM.
- Route 53 **geoproximity** can target Local Zone groups; ALB/EC2 in a Local Zone can sit behind Route 53 latency/geoproximity records.
- "AWS services with single-digit ms latency to an **on-premises application** whose data must stay on site" → **Outposts**. "Users in a specific **city** need single-digit ms" → **Local Zone**. "**Mobile devices on 5G**" → **Wavelength**.

---

## 3. Architecture patterns

### Pattern A — Secure static website: S3 + CloudFront + OAC

```text
 Users ──HTTPS──> Route 53 (alias A/AAAA, apex + www)
                    │
                    ▼
            CloudFront distribution  ◄── ACM cert (us-east-1), WAF web ACL (global)
            │  default behavior: CachingOptimized, redirect HTTP->HTTPS
            │  viewer-request CloudFront Function: /path/ -> /path/index.html
            │  response headers policy: HSTS, CSP
            ▼  (SigV4 via Origin Access Control)
      S3 bucket (REST endpoint, Block Public Access ON, SSE-KMS)
      bucket policy: Allow s3:GetObject to cloudfront.amazonaws.com
                     Condition AWS:SourceArn = arn:...:distribution/EXXXX
```

- **When:** SPAs, marketing sites, documentation, downloads.
- **Why:** no servers, bucket never public, edge TLS, WAF, cheap DTO, versioned assets with long TTLs; `index.html` with a short TTL.
- **Trade-offs:** subfolder index documents need a function (S3 website endpoint would need a public bucket); SPA deep links → custom error response mapping 403/404 to `/index.html` with 200.
- **Variants:** premium area with **signed cookies** (key group); uploads through CloudFront with OAC (PUT) or direct with S3 presigned URLs; multi-Region resilience with an **origin group** (CRR replica bucket).

### Pattern B — Multi-Region active-active with latency routing + health checks

```text
                         Route 53: api.example.com
                 latency alias (us-east-1)   latency alias (eu-west-1)
                 + Evaluate Target Health    + Evaluate Target Health
                 + calculated health check   + calculated health check
                        │                           │
                        ▼                           ▼
                 ALB (us-east-1)             ALB (eu-west-1)
                 ECS/EKS/ASG (multi-AZ)      ECS/EKS/ASG (multi-AZ)
                        │                           │
                        └──── DynamoDB global tables / Aurora Global DB ────┘
                              (write-local or write-forwarding design)
```

- Each Region's record uses **latency** routing; health = **calculated health check** (children: HTTPS deep-health endpoint with string match + CloudWatch-alarm check on error rate/replication lag).
- On a Regional failure, the health check fails → Route 53 stops returning that Region within (interval × threshold) + TTL.
- **Data layer is the hard part:** DynamoDB global tables (multi-active, last-writer-wins; newer multi-Region strong consistency option) or Aurora Global Database (single writer; secondary promotion/switchover, write forwarding). Design for idempotency and conflict avoidance.
- **Optional upgrades:** put **Global Accelerator** in front (static IPs, failover in seconds, no DNS caching) or **CloudFront** (HTTP caching + edge TLS; origin = Route 53 latency record or origin groups). Add **ARC routing controls** for a human-controlled "drain Region" switch.
- **Trade-offs:** cost of 2× capacity, data consistency complexity, need for pre-scaled capacity to absorb a failed Region's traffic.

### Pattern C — Active-passive DR with failover routing (and ARC)

```text
  Route 53 failover record  app.example.com
     PRIMARY  -> alias ALB us-east-1   (health check: HTTPS /health + string match)
     SECONDARY-> alias ALB us-west-2   (warm standby)  or  S3/CloudFront "maintenance" site

  Optional ARC layer:
     ARC cluster (5 Regional endpoints)
        control panel "app"
          routing control "us-east-1"  ON   ──> routing control health check -> PRIMARY record
          routing control "us-west-2"  OFF  ──> routing control health check -> SECONDARY record
        safety rule (assertion): exactly/at least one ON
```

- Plain failover: automatic, cheap, data-plane-driven.
- **With ARC routing controls:** operators (or automation) flip state using cluster endpoints; avoids flapping and split-brain; doesn't require changing records through the us-east-1 control plane. Use **Region switch** plans (newer) to orchestrate scaling the standby, promoting the database and flipping traffic.
- Combine with **zonal shift/autoshift** for AZ-level impairments inside each Region.

### Pattern D — Blue/green (or canary) DNS cutover with weighted records

```text
   T-48h : lower TTL of app.example.com from 3600 -> 60
   T0    : weighted  blue (v1 ALB) = 100   green (v2 ALB) = 0
   T+1   : blue 90 / green 10   (watch CloudWatch, error budgets)
   T+2   : blue 50 / green 50
   T+3   : blue 0  / green 100   (keep blue warm for rollback)
   T+n   : decommission blue, raise TTL back
```

- Rollback = change weights back (bounded by TTL + client caching).
- Same pattern for **migration from on-premises** (weighted: on-prem IP vs AWS ALB) or **between AWS accounts**.
- **Better alternatives when DNS caching is a problem:** ALB **weighted target groups** (instant, same DNS name), **Global Accelerator traffic dials/endpoint weights**, **CloudFront continuous deployment** (for CDN config), CodeDeploy blue/green for ECS/Lambda.
- Trade-off: DNS-based shifting is coarse (resolvers aggregate many users) and sticky clients may ignore TTL.

### Pattern E — Global multiplayer gaming over UDP with Global Accelerator

```text
 Players (worldwide, UDP)
     │  connect to 2 static anycast IPs (allow-listed by console/ISP partners)
     ▼
 AWS edge location (nearest) ──AWS backbone──┐
                                             ▼
       Standard accelerator: UDP listener 7777-7787
         endpoint group us-west-2 (dial 100%) -> NLB -> game fleet
         endpoint group eu-central-1 (dial 100%) -> NLB -> game fleet
         endpoint group ap-northeast-1 (dial 100%) -> NLB -> game fleet

 Session servers needing deterministic placement:
       Custom routing accelerator: port N -> EC2 10.0.3.15:7777 in subnet X
```

- **Why not CloudFront:** UDP is not supported; nothing to cache. **Why not Route 53 latency:** no static IPs, failover bounded by DNS caching, no backbone path from the first mile.
- Add **GameLift** (or self-managed fleets) for matchmaking; use **custom routing** when the matchmaker assigns a player to a specific server.
- Shield Advanced for DDoS-prone games.

### Pattern F — Media streaming (VOD and live)

```text
 VOD:  S3 (mezzanine) -> MediaConvert -> S3 (HLS/DASH/CMAF) --OAC--> CloudFront
 Live: encoder -> MediaLive -> MediaPackage v2 (origin, DRM, time-shift)
                                     │
                              Origin Shield (Region near origin)
                                     │
                              CloudFront (signed cookies for subscribers,
                                          geo restriction for licensing,
                                          real-time logs -> Kinesis -> dashboards)
```

- **Signed cookies** (not URLs) because a stream is hundreds of segment files; **geo restriction** for rights; **Origin Shield** to protect the packager from request storms on live events; separate cache behaviors for manifests (short TTL, a few seconds) and segments (long TTL).
- Request quota increases (Gbps/RPS per distribution) before big live events; consider multi-CDN with Origin Shield as the single egress point.
- MediaStore was the historical low-latency live origin — now discontinued; use MediaPackage or S3.

### Pattern G — Private ALB behind CloudFront (VPC origins) with WAF at the edge

```text
 Users -> CloudFront (+WAF, +Shield Adv) -> VPC origin ENI -> internal ALB (private subnets)
                                                              SG: allow CloudFront-VPCOrigins-Service-SG
          No IGW route to ALB, no public IP, no secret header to rotate
```

- Replaces the older "public ALB + prefix list + secret header + WAF rule" pattern; keep the header approach for origins VPC origins can't serve (e.g., when Lambda@Edge origin triggers are required, or for on-prem/other-cloud origins).

### Pattern H — Hybrid split-horizon DNS during migration

```text
 On-prem DNS ──conditional forward aws.example.com──> Route 53 Resolver inbound endpoint
 VPC Resolver ──forwarding rule corp.example.com──> outbound endpoint ──> on-prem DNS
 app.example.com: PHZ (private ALB IP)  +  public zone (CloudFront)  = split view
```

- Lets internal users hit private endpoints over Direct Connect/VPN while the public reaches CloudFront. Share rules/PHZs organisation-wide via **RAM / Route 53 Profiles**. Details in ch04.

---

## 4. Decision tables

### 4.1 Global Accelerator vs CloudFront vs Route 53 latency routing

| Criterion | **Global Accelerator** | **CloudFront** | **Route 53 latency routing** |
|---|---|---|---|
| OSI layer | L4 (TCP/UDP proxy) | L7 (HTTP/HTTPS/WebSocket/gRPC reverse proxy) | DNS (no data path) |
| Protocols | **TCP, UDP** — any app protocol (MQTT, SIP, gaming, custom TCP, HTTP) | HTTP(S), WebSocket, gRPC | Any (it only answers DNS) |
| Caching | No | **Yes** | No |
| Entry point | **2 static anycast IPs** (BYOIP option) | DNS name (anycast static IPs as a special option) | Your endpoints' own IPs/names |
| Failover speed | **Seconds**, independent of DNS TTL | Per-request origin failover (origin groups) | Health-check detection + **TTL + client caching** |
| Path | Enters AWS backbone at nearest edge | Enters at nearest edge; TLS terminated at edge | Public internet to the chosen Region |
| Traffic control | Traffic dials per Region, endpoint weights, client affinity | Cache behaviors, functions, continuous deployment | Weights, geolocation, geoproximity bias, health |
| Client IP visible | Preserved (ALB/EC2, NLB in supported configs) | `X-Forwarded-For` / `CloudFront-Viewer-Address` | N/A (direct) |
| Edge logic | None | Functions, Lambda@Edge, WAF, signed URLs, FLE | None |
| DDoS | Shield Std/Adv | Shield Std/Adv + WAF | Shield Std/Adv for hosted zone |
| Cost | Hourly + DT-Premium per GB | DTO per GB + requests (often reduces total DTO cost) | Per zone + per query (cheapest) |
| Best for | Gaming, VoIP, IoT, non-HTTP, static IP allow-listing, fast multi-Region failover, deterministic routing | Websites, APIs, video, downloads, edge security, dynamic site acceleration | Simple multi-Region steering where DNS caching is acceptable |

### 4.2 Route 53 routing policy chooser

| Requirement | Policy |
|---|---|
| Single endpoint | Simple |
| Send 10% to new version / gradual migration | Weighted |
| Lowest latency across Regions | Latency |
| Active-passive DR | Failover (+ health checks or ARC routing controls) |
| Show content/legal terms by **country**; block unlicensed countries at DNS | Geolocation (with Default record) |
| Route by distance and **shift boundaries** between Regions | Geoproximity (bias) |
| Return several healthy IPs for client-side spreading | Multivalue answer |
| Route specific **ISPs / corporate CIDRs** to specific endpoints | IP-based (CIDR collections) |
| Mix of the above | Alias record trees with Evaluate Target Health |

### 4.3 Health-check type chooser

| Target | Health check |
|---|---|
| Public web endpoint | HTTP/HTTPS endpoint check (string match for deep health) |
| ALB/NLB alias | Evaluate Target Health (free) or explicit HTTP check for full-path testing |
| Private resource / PHZ record / on-prem via VPN | **CloudWatch alarm–based** |
| "Region healthy only if all tiers healthy" | **Calculated** |
| Manual, highly reliable switch | **ARC routing control** health check |
| Business metric (error rate, replica lag) | CloudWatch alarm–based |

### 4.4 Signed URL vs signed cookie vs S3 presigned URL vs OAC

| Need | Use |
|---|---|
| Single file, client can't do cookies | CloudFront **signed URL** |
| Many files (video segments, members area), keep URLs | CloudFront **signed cookies** |
| Direct upload/download to S3 without CDN | **S3 presigned URL** |
| Stop direct S3 access, force CloudFront | **OAC** (always, in addition to the above) |

### 4.5 Where to run edge logic

| Requirement | Choice |
|---|---|
| Rewrite URL, add security headers, normalise cache key, validate JWT locally | CloudFront Functions (+ KVS for config) |
| Security headers only | Response headers policy (no code) |
| Call an external service / DynamoDB at the edge, inspect body, choose origin dynamically, resize images | Lambda@Edge |
| Block SQLi/XSS/bots, rate limiting | AWS WAF |
| Country block for licensing | Geo restriction (or WAF geo match for finer rules) |

### 4.6 Edge infrastructure chooser

| Constraint | Choice |
|---|---|
| Single-digit ms latency to users in a metro, no on-prem constraint | Local Zone |
| Ultra-low latency to 5G mobile devices | Wavelength |
| Data must remain on premises / low latency to on-prem systems / AWS APIs on site | Outposts (rack for scale, server for small sites) |
| Global users, cacheable HTTP content | CloudFront |
| Global users, TCP/UDP, static IPs | Global Accelerator |

### 4.7 Failover mechanism chooser

| Mechanism | Scope | Speed | Notes |
|---|---|---|---|
| Route 53 failover + health checks | Region / endpoint | Minutes (detection + TTL) | Automatic, cheap |
| ARC routing controls | Region | Minutes (DNS) but highly reliable, operator-controlled | Safety rules, 5-Region cluster, fixed cost |
| Global Accelerator | Region / endpoint | Seconds | Static IPs, L4 |
| CloudFront origin groups | Origin | Per request | GET/HEAD/OPTIONS only |
| ARC zonal shift / autoshift | AZ | Minutes | ALB/NLB/ASG/EKS; pre-scale |
| ALB/NLB health checks | Target | Seconds | Inside a Region |

---

## 5. Exam keyword → answer cheat list

- "**Zone apex** / naked domain → ALB/CloudFront" → **Route 53 alias record**.
- "**Static IP addresses** for allow-listing, global users" → **Global Accelerator** (BYOIP if they must keep existing IPs).
- "**UDP** / gaming / VoIP / IoT MQTT over TCP, global, low latency" → **Global Accelerator**.
- "Deterministically route a user to a **specific EC2 game server**" → **Global Accelerator custom routing accelerator**.
- "Failover in **seconds**, **not affected by DNS caching**" → **Global Accelerator**.
- "Cache static and dynamic web content globally, reduce origin load" → **CloudFront** (+ Origin Shield).
- "Improve **cache hit ratio**" → trim cache key with **cache policy**, move forwarded values to **origin request policy**, normalise with CloudFront Functions, Origin Shield.
- "S3 content only via CloudFront, **SSE-KMS** objects" → **OAC** (not OAI).
- "ALB must **not be publicly accessible** behind CloudFront" → **CloudFront VPC origins**.
- "Ensure requests to a public ALB come only from **our** distribution" → **custom header + WAF/listener rule** + **managed prefix list**.
- "Premium video subscribers, many segment files" → **signed cookies** with **trusted key groups**.
- "Single downloadable file, mobile app without cookie support" → **signed URL**.
- "Encrypt **credit card field** end-to-end through multiple tiers" → **CloudFront field-level encryption**.
- "Block countries for **licensing**" → **CloudFront geo restriction** (or WAF geo match).
- "Frequent asset updates, avoid invalidation cost" → **versioned file names**.
- "Test new CDN config on **5% of production traffic**" → **CloudFront continuous deployment (staging distribution)**.
- "URL rewrite / header manipulation / JWT check at **millions RPS**, lowest cost" → **CloudFront Functions** (+ **KeyValueStore** for config without redeploys).
- "Edge logic needs **network calls** / third-party libraries / origin-response modification" → **Lambda@Edge**.
- "Live dashboard of CDN requests within seconds" → **CloudFront real-time logs → Kinesis Data Streams**.
- "Reduce CloudFront cost, users only in US/Europe" → **Price Class 100**.
- "TLS certificate for CloudFront" → **ACM in us-east-1**.
- "Health check a **private** resource / PHZ record" → **CloudWatch alarm–based health check**.
- "Region considered healthy only if multiple components are healthy" → **calculated health check**.
- "Health page returns 200 even when broken" → **string matching** health check.
- "Route traffic by **user's country** for compliance" → **geolocation** (with a Default record).
- "Gradually move more users to a new Region based on geography" → **geoproximity with bias**.
- "Route a **specific ISP's** users to a specific endpoint" → **IP-based routing**.
- "Return multiple healthy IPs, simple" → **multivalue answer**.
- "Canary / blue-green DNS / migrate 10% to AWS" → **weighted records** (lower TTL in advance).
- "**Same DNS name**, different answers inside VPC vs internet" → **split-horizon** (public + private hosted zone, same name).
- "Share PHZ with VPC in another account" → **create-vpc-association-authorization + associate-vpc-with-hosted-zone**; at scale → **Route 53 Profiles via RAM**.
- "Protect against DNS spoofing" → **DNSSEC signing** (KSK in KMS us-east-1) + **Resolver DNSSEC validation**.
- "Highly reliable, manual multi-Region failover with **guardrails** against both Regions active" → **ARC routing controls + safety rules**.
- "Shift traffic away from an **impaired AZ**" → **ARC zonal shift**; "let AWS do it automatically" → **zonal autoshift** (practice runs required, pre-scale).
- "DDoS **cost protection** + 24/7 response team" → **Shield Advanced**.
- "Single-digit ms for users in a **city**" → **Local Zone**; "**5G** devices" → **Wavelength**; "data **must stay on premises**" → **Outposts**.
- "Least operational overhead for global static site" → **S3 + CloudFront + OAC** (or Amplify Hosting).

---

## 6. Traps & distractors

- **CNAME at the apex** — invalid DNS. Use alias.
- **"Lower the TTL at cutover time"** — too late; resolvers already cached the old long TTL. Lower it at least one old-TTL period in advance.
- **Route 53 endpoint health checks against private IPs** — health checkers are on the internet; use CloudWatch alarm–based checks.
- **Lambda that rewrites DNS records during an outage** — depends on the Route 53 control plane (us-east-1) and on the impaired Region; prefer data-plane failover (health checks, ARC routing controls).
- **Multivalue answer as a "load balancer"** — no Layer 7, no draining, max 8 records. Use ELB.
- **Geolocation without a Default record** — users from unmapped locations get no answer.
- **Latency routing ≠ geolocation** — the nearest Region isn't always the lowest latency, and latency routing can't enforce compliance.
- **CloudFront for UDP or non-HTTP TCP** — unsupported; Global Accelerator.
- **Global Accelerator to "cache content"** — it doesn't cache.
- **Global Accelerator in front of S3/CloudFront** — not supported endpoint types (endpoints are ALB, NLB, EC2, EIP).
- **ACM certificate in the origin's Region for CloudFront** — must be us-east-1.
- **OAI with SSE-KMS buckets or new opt-in Regions** — OAI can't; use OAC.
- **OAC with the S3 website endpoint** — website endpoints are custom origins; OAC doesn't apply.
- **Prefix list alone protects the ALB** — any CloudFront distribution (including an attacker's) uses those IPs; add the custom header check, or use VPC origins.
- **Signed URLs "prevent direct S3 access"** — no; OAC does. Signed URLs control *who* can fetch via CloudFront.
- **S3 presigned URLs to protect CloudFront content** — wrong mechanism; CloudFront signed URLs/cookies with key groups.
- **Trusted signers (root key pairs)** — legacy; key groups are recommended (IAM-managed, no root).
- **Invalidation on every deployment as the strategy** — slow and costly at scale; versioned names.
- **Forwarding all headers/cookies to "fix" a dynamic page** — destroys cache hit ratio; use origin request policy and separate behaviors.
- **Lambda@Edge for simple header rewrites at very high RPS** — overkill and pricier; CloudFront Functions.
- **CloudFront Functions calling DynamoDB** — no network access; Lambda@Edge (or KVS for small config).
- **Lambda@Edge origin triggers with VPC origins** — not supported.
- **Origin groups for POST/PUT failover** — only GET/HEAD/OPTIONS.
- **Geo restriction for data residency** — it only blocks viewers; caches are global.
- **CloudFront price class "blocks" users outside the class** — no, they're served from included locations with higher latency.
- **Cross-account CloudWatch alarm health check** — not supported; the alarm must be in the same account.
- **ARC readiness check in the failover critical path** — it's for continuous auditing, and it's closed to new customers since 30 Apr 2026.
- **Zonal autoshift without pre-scaling** — autoshift doesn't wait for Auto Scaling; remaining AZs can be overloaded.
- **Outposts for disconnected sites** — it needs a service link; it isn't designed to run disconnected.
- **Local Zones to keep data on the customer's premises** — Local Zones are AWS facilities; Outposts is on-prem.
- **Shield Advanced for SQL injection** — that's WAF.
- **WAF web ACL for CloudFront created in a regional scope** — must be global (CloudFront) scope.

---

## 7. Professional architect focus

- **DNS is a shared, slow-moving dependency.** Treat TTLs as part of RTO math: RTO ≈ detection (interval × failure threshold) + DNS TTL + client cache behaviour + application warm-up. If the business needs sub-minute failover for non-browser clients, Global Accelerator or client-side retry with multiple endpoints is safer than DNS.
- **Data plane vs control plane.** Design failover so that during an event you only *read* state (health checks) or flip highly available switches (ARC routing controls). Don't plan on creating resources, changing records or calling IAM in an impaired Region. Rehearse failovers (game days, ARC practice runs, AWS FIS).
- **Static stability.** Pre-provision standby capacity sized for failover load (or accept a longer RTO). Zonal autoshift explicitly requires this; so does Regional active-active.
- **Health checks must reflect user experience but avoid cascading failure.** A deep health check that fails when a shared dependency (database) fails can remove *every* Region at once → Route 53 fails open and sends traffic everywhere. Use calculated checks carefully; separate liveness from dependency health.
- **Cache key discipline is a cost lever.** A 10-point cache-hit improvement can cut origin compute and DTO meaningfully. Push teams to send correct `Cache-Control` headers and version assets; govern cache policies centrally.
- **Origin protection is defence in depth:** WAF at edge, OAC/VPC origins, minimal SGs, Shield Advanced for high-value targets, and logging (standard + real-time) into a security account.
- **Multi-account DNS governance:** central networking account owns public zones and Resolver endpoints; app accounts get delegated subdomains (NS delegation) and PHZs shared via Route 53 Profiles/RAM. Use SCPs to stop teams creating conflicting public zones for the corporate domain; restrict `route53:ChangeResourceRecordSets` on apex records.
- **Certificates:** centralise ACM in us-east-1 for CloudFront; automate DNS validation; watch expiry of imported certs (ACM doesn't renew imported certificates).
- **Cost conversations:** Global Accelerator's DT-Premium vs CloudFront's DTO; price classes; Security Savings Bundle/flat-rate plans; free alias queries; health checks (fast interval and string matching cost more); ARC cluster fixed cost (share across apps); Shield Advanced is per Organization, not per account.
- **Stakeholder questions to raise:** What RTO/RPO per tier? Do clients honour DNS TTL (IoT firmware, Java, embedded devices)? Do partners allow-list IPs? Which countries are licensed? Is data residency about *storage*, *processing* or *transit*? Who approves a Regional failover (ARC gating rules can encode this)?
- **Emerging / SAP-C03 preview (not core for SAP-C02):** ARC **Region switch** plans with plan evaluation; AWS FIS for resilience testing; AWS Resilience Hub assessments; VPC Lattice for service-to-service networking; CloudFront flat-rate plans, mTLS and multi-tenant distributions.

---

## 8. Skills checklist

- [ ] I can explain why a CNAME can't be at the zone apex and when an alias record is required.
- [ ] I can plan a TTL-lowering timeline for a migration cutover and calculate realistic DNS failover time.
- [ ] I can choose among simple, weighted, latency, failover, geolocation, geoproximity (with bias), multivalue and IP-based routing for a scenario.
- [ ] I can build a routing tree (failover → latency → weighted) with Evaluate Target Health.
- [ ] I can pick endpoint, string-matching, calculated or CloudWatch-alarm-based health checks, and explain why private resources need alarms.
- [ ] I can associate a private hosted zone with a VPC in another account and explain Route 53 Profiles.
- [ ] I can design split-horizon DNS for hybrid users.
- [ ] I can describe DNSSEC signing requirements (KMS key in us-east-1, DS record, alarms).
- [ ] I can explain ARC routing controls, safety rules, clusters, zonal shift and zonal autoshift (and the readiness check availability change).
- [ ] I can design a CloudFront distribution with multiple behaviors, cache/origin request/response headers policies.
- [ ] I can improve cache hit ratio and decide between invalidation and versioned names.
- [ ] I can choose OAC vs OAI, VPC origins vs custom header + prefix list.
- [ ] I can choose signed URLs vs signed cookies vs S3 presigned URLs and configure key groups.
- [ ] I can explain Origin Shield, origin groups and their limits.
- [ ] I can pick CloudFront Functions vs Lambda@Edge and use KeyValueStore.
- [ ] I can design Global Accelerator with traffic dials, weights, client affinity and know when custom routing is required.
- [ ] I can compare Global Accelerator, CloudFront and Route 53 latency routing on protocol, caching, IPs and failover speed.
- [ ] I can place WAF and Shield Advanced correctly.
- [ ] I can choose Local Zones vs Wavelength vs Outposts for latency and residency constraints.

---

## 9. Practice questions

> Original SAP-C02-style questions written for this guide (not real exam questions).

**Q1.** A retailer is migrating its customer-facing web application from an on-premises data center to an Application Load Balancer in `us-east-1`. The public record `shop.example.com` is hosted in Route 53 as an A record pointing to the on-premises load balancer IP with a TTL of 86,400 seconds. The business wants to move 10% of users to AWS first, increase gradually over a week, and be able to roll back to on-premises within about five minutes at any stage. The cutover starts in three days. Which combination of actions should the solutions architect take? **(Select TWO.)**

- A. Immediately reduce the TTL of the existing `shop.example.com` record to 60 seconds.
- B. On the cutover day, reduce the TTL to 60 seconds and simultaneously create the new records.
- C. Replace the record with two weighted records of the same name — one for the on-premises IP and one alias to the ALB — and adjust weights to shift traffic.
- D. Create a geolocation record set that sends 10% of countries to the ALB.
- E. Create a multivalue answer record containing both the on-premises IP and the ALB IP addresses.

**Q2.** A media company serves its web application through CloudFront with an internet-facing Application Load Balancer as the origin. A security review requires that the ALB no longer be reachable from the internet at all, that CloudFront remain the only entry point, and that the solution minimise ongoing operational effort such as secret rotation. The application uses CloudFront Functions for URL rewrites but no Lambda@Edge. What should the solutions architect do?

- A. Keep the ALB internet-facing, restrict its security group to the `com.amazonaws.global.cloudfront.origin-facing` prefix list, and add a custom header checked by an AWS WAF rule on the ALB, rotated by Secrets Manager.
- B. Recreate the ALB as internal in private subnets and configure it as a CloudFront VPC origin, allowing inbound traffic only from the CloudFront service-managed security group.
- C. Place a Network Load Balancer with an Elastic IP in a public subnet in front of the internal ALB and configure the NLB as the CloudFront origin.
- D. Configure Origin Access Control on the ALB origin and add a resource policy to the ALB that allows only the CloudFront service principal.

**Q3.** A game studio runs session-based multiplayer servers on EC2 in three AWS Regions. The game client uses a proprietary UDP protocol. Several console platform partners and mobile carriers require a small, fixed set of IP addresses to allow-list. When a Region is impaired, players must reconnect to another Region within seconds, regardless of how their devices cache DNS. Additionally, the matchmaking service must be able to send a group of players to one specific server instance. Which solution meets these requirements?

- A. Route 53 latency-based records with health checks pointing to Network Load Balancers in each Region, with a TTL of 10 seconds.
- B. A CloudFront distribution with origin groups pointing to NLBs in each Region and Anycast static IPs enabled.
- C. A Global Accelerator custom routing accelerator whose endpoints are the VPC subnets hosting the game servers, with the matchmaker mapping players to the accelerator's static IP and destination port.
- D. A standard Global Accelerator with a UDP listener and endpoint groups containing NLBs in each Region, with client affinity set to Source IP.

**Q4.** A financial services company runs an active-passive trading platform in `us-east-1` (primary) and `us-west-2` (standby, warm). Regulators require that a Regional failover be a deliberate, human-approved decision, that both Regions must never serve traffic simultaneously, and that the failover mechanism must not depend on modifying DNS records through a control plane during an event. Which approach best meets these requirements?

- A. Route 53 failover records with HTTPS health checks on each Region's ALB; operators disable the primary health check during an incident.
- B. An EventBridge rule that triggers a Lambda function in `us-west-2` to call `ChangeResourceRecordSets` and swap the record values after an operator approves in Systems Manager.
- C. Amazon Application Recovery Controller routing controls in a cluster, with routing control health checks attached to Route 53 failover records and an assertion safety rule allowing only one Region's routing control to be on; operators change state through the cluster endpoints.
- D. Global Accelerator with endpoint groups in both Regions; operators set the traffic dial of the primary to 0% and the standby to 100% during an incident.

**Q5.** A company uses a Route 53 private hosted zone `corp.internal` associated with VPCs in two Regions. `orders.corp.internal` must fail over from an internal Application Load Balancer in `eu-west-1` to an internal ALB in `eu-central-1` if the primary application's error rate exceeds a threshold or if the primary ALB has no healthy targets. Which configuration meets this requirement?

- A. Create Route 53 HTTPS endpoint health checks against the private IP addresses of the primary ALB and attach them to failover records.
- B. Create a CloudWatch alarm on the primary ALB's `HTTPCode_Target_5XX_Count` and `HealthyHostCount` metrics (composite alarm), create a Route 53 health check based on that alarm, and attach it to the primary failover record in the private hosted zone.
- C. Use a multivalue answer record with both ALBs and rely on clients to retry the second address.
- D. Use latency-based records with Evaluate Target Health so the private hosted zone automatically removes the unhealthy ALB.

**Q6.** An e-commerce site behind CloudFront reports a cache hit ratio of 18% for its product catalogue pages, which are identical for all users except for language (selected via an `Accept-Language`-derived `lang` query string). Investigation shows the behavior uses a legacy configuration forwarding all headers, all cookies and all query strings, because the origin needs the session cookie to log analytics and the `User-Agent` header for device statistics. The origin is a fleet of EC2 instances in one Region that is frequently overloaded during promotions. Which actions will MOST improve the cache hit ratio and reduce origin load? **(Select THREE.)**

- A. Create a cache policy whose cache key includes only the `lang` query string, with no headers or cookies.
- B. Create an origin request policy that forwards the session cookie and `User-Agent` header to the origin without adding them to the cache key.
- C. Enable CloudFront Origin Shield in the Region closest to the origin.
- D. Increase the number of cache behaviors to one per product category, each with the legacy forward-all settings.
- E. Switch the distribution to Price Class 100 to concentrate requests in fewer edge locations.
- F. Invalidate `/*` after every product update so that caches are always warm.

**Q7.** A news publisher wants to run logic at the edge for every request (around 400,000 requests per second at peak): validate a JWT in the `Authorization` header using an HMAC secret, redirect users to a regional edition based on country, and assign users to A/B test cohorts whose percentages the marketing team changes several times a day without developer involvement. Cost must be minimised. Which solution should the solutions architect recommend?

- A. A Lambda@Edge viewer-request function in Node.js that reads cohort percentages from a DynamoDB global table.
- B. A CloudFront Function (JavaScript runtime 2.0) on viewer request that reads the HMAC secret and cohort percentages from a CloudFront KeyValueStore updated by the marketing tool through the API.
- C. A CloudFront Function on origin request that calls AWS AppConfig for cohort percentages.
- D. An AWS WAF web ACL with a custom rule that validates JWTs and a Lambda@Edge origin-response function for redirects.

**Q8.** A company has a central networking account that owns a Route 53 private hosted zone `shared.example.internal`. Two hundred workload VPCs in 60 accounts across an AWS Organization must resolve records in this zone, and new accounts are created weekly by Account Factory. The networking team also wants to apply the same Resolver forwarding rules for on-premises domains and DNS Firewall rule groups to every VPC. Which approach provides this with the LEAST operational overhead?

- A. For each VPC, run `create-vpc-association-authorization` in the networking account and `associate-vpc-with-hosted-zone` in the workload account, and share Resolver rules with RAM individually.
- B. Create a Route 53 Profile in the networking account containing the private hosted zone, the Resolver rules and the DNS Firewall rule groups, share it with the Organization through AWS RAM, and associate it with each VPC as part of the account baseline.
- C. Create a duplicate private hosted zone with the same name in each workload account and synchronise records with a Lambda function.
- D. Create a public hosted zone for `shared.example.internal` and restrict queries with a Route 53 Resolver DNS Firewall rule.

**Q9.** A hospital group is modernising a radiology imaging application. Patient images are generated by on-site scanners and, by regulation, must be stored and processed within the hospital's own facility. Clinicians require single-digit-millisecond access to the application from the hospital network, and the IT team wants to use the same AWS APIs, EC2 instance types, EBS volumes and S3 APIs as in the Region, managed through the AWS console. Which solution meets these requirements?

- A. Deploy the application in the nearest AWS Local Zone and connect the hospital with AWS Direct Connect.
- B. Deploy AWS Outposts racks in the hospital data center, using EC2, EBS and S3 on Outposts, with a service link to the parent Region.
- C. Deploy the application in an AWS Wavelength Zone in the hospital's mobile carrier network.
- D. Deploy the application in the parent Region behind CloudFront with geo restriction limited to the hospital's country.

**Q10.** A training company is building a video course platform. Course videos (HLS, thousands of segment files per course) are stored in an S3 bucket encrypted with SSE-KMS using a customer managed key in `ap-southeast-4` (an opt-in Region). Only paying subscribers may stream videos; free users may browse the public catalogue on the same domain. Videos must never be downloadable directly from S3. The team wants to avoid using root-user credentials for any operational task. Which combination of steps should the solutions architect take? **(Select THREE.)**

- A. Create a CloudFront Origin Access Control for the S3 origin, update the bucket policy to allow `s3:GetObject` to the CloudFront service principal conditioned on the distribution ARN, and allow the CloudFront service principal to use the KMS key in the key policy.
- B. Create a CloudFront Origin Access Identity and grant it `kms:Decrypt` in the key policy.
- C. Create a trusted key group with a public key, configure the `/courses/*` cache behavior to restrict viewer access with that key group, and have the application issue signed cookies to subscribers after login.
- D. Create CloudFront key pairs using the root user and configure them as trusted signers on the distribution.
- E. Keep the public catalogue on the default cache behavior without viewer access restriction.
- F. Generate S3 presigned URLs for every segment and embed them in the HLS manifest.

---

### Answers & explanations

<details><summary>Show answer — Q1</summary>

**Correct: A, C.**

- **A** — Resolvers can keep the old answer for up to the old TTL (24 h). Lowering the TTL **now**, three days ahead, guarantees that by cutover every resolver honours a 60-second TTL, enabling the five-minute rollback requirement.
- **C** — Weighted records of the same name give proportional traffic splitting (e.g., 90/10, then 50/50, then 0/100) and instant rollback by changing weights. The ALB side can be an alias record (free queries, Evaluate Target Health).
- **B** is wrong: lowering TTL at cutover time leaves the old 86,400 s value cached across resolvers for up to a day, so neither the gradual shift nor fast rollback works.
- **D** is wrong: geolocation splits by location, not percentage, and can't produce a controllable 10%.
- **E** is wrong: multivalue returns up to 8 random healthy values; you can't control proportions, and ALB IPs change (you can't put ALB IPs in a record — use alias).

References: [Choosing a routing policy](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/routing-policy.html), [Weighted routing](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/routing-policy-weighted.html), [Blue/Green Deployments on AWS whitepaper](https://docs.aws.amazon.com/whitepapers/latest/blue-green-deployments/welcome.html)
</details>

<details><summary>Show answer — Q2</summary>

**Correct: B.**

- **B** — CloudFront **VPC origins** support internal ALBs in private subnets. The ALB has no internet exposure, CloudFront reaches it through a service-managed ENI, and allowing only the `CloudFront-VPCOrigins-Service-SG` restricts traffic to your distributions. No secret to rotate. The app uses no Lambda@Edge origin triggers (which VPC origins don't support).
- **A** is wrong: it is the older pattern; the ALB remains internet-facing (fails the requirement) and needs ongoing secret rotation.
- **C** is wrong: it reintroduces a public entry point (the NLB EIP) reachable from the internet, adding cost and exposure.
- **D** is wrong: OAC applies to S3, MediaPackage v2, Lambda function URLs and MRAP — not to ALBs, and ALBs don't support resource policies.

References: [Restrict access with VPC origins](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/private-content-vpc-origins.html)
</details>

<details><summary>Show answer — Q3</summary>

**Correct: C.**

- **C** — A **custom routing accelerator** provides static anycast IPs (allow-listable), supports UDP, routes over the AWS backbone, and deterministically maps a static IP + port to a specific EC2 instance and port in a subnet — exactly what the matchmaker needs to place a group of players on one server. Clients connect by IP, so behaviour is independent of DNS caching; the matchmaker reassigns players to servers in a healthy Region when one is impaired.
- **A** is wrong: no static IPs; DNS failover is subject to client/resolver caching even with low TTLs; can't target a specific instance.
- **B** is wrong: CloudFront doesn't support UDP or arbitrary non-HTTP protocols.
- **D** is wrong: a standard accelerator load-balances across endpoints; Source IP affinity keeps one client on one endpoint but can't send a *group* of players to a chosen server instance.

References: [Global Accelerator components](https://docs.aws.amazon.com/global-accelerator/latest/dg/introduction-components.html), [What is Global Accelerator?](https://docs.aws.amazon.com/global-accelerator/latest/dg/what-is-global-accelerator.html)
</details>

<details><summary>Show answer — Q4</summary>

**Correct: C.**

- **C** — ARC **routing controls** are on/off switches hosted on a highly available **cluster of five Regional endpoints**; their state drives **routing control health checks** attached to Route 53 records, so traffic moves through the Route 53 data plane without editing records. An **assertion safety rule** enforces "only one Region on" (prevents split-brain), and changing state is an explicit operator action (human approval; gating rules can add approval gates).
- **A** is wrong: health-check failover is automatic (not a deliberate decision) and "disabling" a health check is an API change to the Route 53 control plane; nothing prevents both Regions being active.
- **B** is wrong: it explicitly modifies records through the control plane during the event and has no safety guardrails.
- **D** is wrong: traffic dials work and are fast, but nothing enforces mutual exclusivity, and the question's DNS-based architecture plus regulatory guardrails point to ARC; Global Accelerator configuration changes are also made through its control plane (us-west-2).

References: [Routing control in ARC](https://docs.aws.amazon.com/r53recovery/latest/dg/routing-control.html), [What is ARC?](https://docs.aws.amazon.com/r53recovery/latest/dg/what-is-route53-recovery.html)
</details>

<details><summary>Show answer — Q5</summary>

**Correct: B.**

- **B** — Route 53 health checkers run on the internet and cannot reach private IPs. For records in a **private hosted zone** and for internal resources, use a **CloudWatch alarm–based health check**. A composite alarm on 5XX count and `HealthyHostCount` captures both conditions (error rate and no healthy targets). Failover routing is supported in PHZs.
- **A** is wrong: endpoint health checks against private IPs fail (unreachable), so the primary would always look unhealthy.
- **C** is wrong: multivalue still needs health checks to filter, and pushes failover logic onto clients; it doesn't implement primary/secondary.
- **D** is wrong: latency routing is for performance, not active-passive; Evaluate Target Health wouldn't cover the error-rate condition.

References: [How Route 53 determines health check status](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/dns-failover-determining-health-of-endpoints.html), [Configuring DNS failover](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/dns-failover.html)
</details>

<details><summary>Show answer — Q6</summary>

**Correct: A, B, C.**

- **A** — The page varies only by `lang`; a cache key with just that query string collapses thousands of variants into a handful, dramatically raising the hit ratio.
- **B** — An **origin request policy** still forwards the session cookie and `User-Agent` for analytics without fragmenting the cache key.
- **C** — **Origin Shield** adds a central caching layer so misses from many Regional edge caches collapse into one origin fetch — directly reducing load on a capacity-constrained origin during promotions.
- **D** is wrong: more behaviors with forward-all settings keep the same fragmented cache key.
- **E** is wrong: price class affects which edge locations serve viewers (cost/latency), not cache-key fragmentation; it doesn't meaningfully fix the hit ratio.
- **F** is wrong: invalidating everything empties caches and *increases* origin load; use versioned names or targeted invalidations.

References: [Control the cache key with a policy](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/controlling-the-cache-key.html), [Control origin requests with a policy](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/controlling-origin-requests.html), [Use Amazon CloudFront Origin Shield](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/origin-shield.html)
</details>

<details><summary>Show answer — Q7</summary>

**Correct: B.**

- **B** — All three tasks are lightweight viewer-request logic: HMAC JWT validation, country-based redirect (CloudFront Functions get `CloudFront-Viewer-Country`), and cookie-based cohort assignment. CloudFront Functions scale to millions of RPS at a fraction of Lambda@Edge cost. **KeyValueStore** lets marketing update cohort percentages (and the secret) via API without redeploying code.
- **A** is wrong: works functionally but costs far more at 400k RPS, and Lambda@Edge's per-Region request rate quota (10,000 RPS default) and network round trips to DynamoDB add latency and risk.
- **C** is wrong: CloudFront Functions don't run on origin request and have no network access to call AppConfig.
- **D** is wrong: WAF can't cryptographically validate JWT signatures with a custom HMAC secret, and redirects belong in viewer request, not origin response.

References: [Differences between CloudFront Functions and Lambda@Edge](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/edge-functions-choosing.html), [Amazon CloudFront KeyValueStore](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/kvs-with-functions.html)
</details>

<details><summary>Show answer — Q8</summary>

**Correct: B.**

- **B** — **Route 53 Profiles** bundle private hosted zones, Resolver rules and DNS Firewall rule groups into one shareable unit. Sharing via **AWS RAM** to the Organization and associating the Profile in the account baseline (e.g., Account Factory customisation) scales to hundreds of VPCs with one place to manage changes.
- **A** is wrong: it works but requires two API calls per VPC across accounts plus separate rule sharing — high, ongoing operational overhead for weekly new accounts.
- **C** is wrong: duplicated zones with sync scripts are fragile and inconsistent.
- **D** is wrong: a public hosted zone exposes internal names on the internet; DNS Firewall filters outbound queries from VPCs, it doesn't make a public zone private.

References: [Route 53 Profiles](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/profiles.html), [Associating a private hosted zone with VPCs in different accounts](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/hosted-zone-private-associate-vpcs-different-accounts.html)
</details>

<details><summary>Show answer — Q9</summary>

**Correct: B.**

- **B** — **Outposts racks** put AWS-managed infrastructure inside the hospital's facility, so data is stored and processed on site, with single-digit-ms access from the local network via the local gateway. They support EC2, EBS and **S3 on Outposts**, managed with the same APIs and console via the service link to the parent Region.
- **A** is wrong: Local Zones are AWS facilities in a metro area — data would leave the hospital's own facility.
- **C** is wrong: Wavelength targets 5G mobile devices inside carrier networks; data would reside in the carrier's facility.
- **D** is wrong: data would be in the AWS Region, and geo restriction only filters viewers by country.

References: [What is AWS Outposts?](https://docs.aws.amazon.com/outposts/latest/userguide/what-is-outposts.html), [What is AWS Local Zones?](https://docs.aws.amazon.com/local-zones/latest/ug/what-is-aws-local-zones.html), [What is AWS Wavelength?](https://docs.aws.amazon.com/wavelength/latest/developerguide/what-is-wavelength.html)
</details>

<details><summary>Show answer — Q10</summary>

**Correct: A, C, E.**

- **A** — **OAC** is required because the bucket uses **SSE-KMS** and sits in an **opt-in Region launched after December 2022** — OAI supports neither. The bucket policy (with `AWS:SourceArn`) blocks direct access; the KMS key policy must allow the CloudFront service principal to decrypt.
- **C** — **Signed cookies** suit HLS (thousands of segments under one path) without rewriting URLs. **Trusted key groups** are managed with IAM — no root user needed.
- **E** — Separate cache behaviors let the public catalogue remain unrestricted on the same domain, while `/courses/*` requires signed cookies.
- **B** is wrong: OAI can't serve SSE-KMS objects or new opt-in Regions.
- **D** is wrong: CloudFront key pairs require the root user (legacy trusted signers), violating the requirement.
- **F** is wrong: S3 presigned URLs bypass CloudFront caching, expose S3 directly, and are impractical to embed for thousands of segments per manifest.

References: [Restrict access to an Amazon S3 origin](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/private-content-restricting-access-to-s3.html), [Serve private content with signed URLs and signed cookies](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/PrivateContent.html)
</details>

---

## 10. References

**Route 53**
- [Amazon Route 53 Developer Guide](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/Welcome.html)
- [Choosing a routing policy](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/routing-policy.html)
- [Geoproximity routing](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/routing-policy-geoproximity.html)
- [Choosing between alias and non-alias records](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/resource-record-sets-choosing-alias-non-alias.html)
- [Configuring DNS failover](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/dns-failover.html)
- [How Route 53 determines whether a health check is healthy](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/dns-failover-determining-health-of-endpoints.html)
- [Associating a private hosted zone with VPCs in different accounts](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/hosted-zone-private-associate-vpcs-different-accounts.html)
- [Route 53 Profiles](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/profiles.html)
- [Configuring DNSSEC signing](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/dns-configuring-dnssec.html)

**Application Recovery Controller**
- [What is ARC?](https://docs.aws.amazon.com/r53recovery/latest/dg/what-is-route53-recovery.html)
- [Routing control in ARC](https://docs.aws.amazon.com/r53recovery/latest/dg/routing-control.html)
- [Zonal autoshift in ARC](https://docs.aws.amazon.com/r53recovery/latest/dg/arc-zonal-autoshift.html)
- [Readiness check availability change](https://docs.aws.amazon.com/r53recovery/latest/dg/arc-readiness-availability-change.html)

**CloudFront**
- [Amazon CloudFront Developer Guide](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/Introduction.html)
- [CloudFront quotas](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/cloudfront-limits.html)
- [Restrict access to an Amazon S3 origin (OAC)](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/private-content-restricting-access-to-s3.html)
- [Restrict access with VPC origins](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/private-content-vpc-origins.html)
- [Serve private content with signed URLs and signed cookies](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/PrivateContent.html)
- [Control the cache key with a policy](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/controlling-the-cache-key.html)
- [Control origin requests with a policy](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/controlling-origin-requests.html)
- [Use Amazon CloudFront Origin Shield](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/origin-shield.html)
- [Optimize high availability with CloudFront origin failover](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/high_availability_origin_failover.html)
- [Use field-level encryption](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/field-level-encryption.html)
- [Real-time access logs](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/real-time-logs.html)
- [Continuous deployment](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/continuous-deployment.html)
- [Differences between CloudFront Functions and Lambda@Edge](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/edge-functions-choosing.html)
- [Amazon CloudFront KeyValueStore](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/kvs-with-functions.html)
- [CloudFront price classes](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/PriceClass.html)
- [Locations and IP ranges of CloudFront edge servers (managed prefix list)](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/LocationsOfEdgeServers.html)

**Global Accelerator**
- [What is AWS Global Accelerator?](https://docs.aws.amazon.com/global-accelerator/latest/dg/what-is-global-accelerator.html)
- [Global Accelerator components](https://docs.aws.amazon.com/global-accelerator/latest/dg/introduction-components.html)
- [Health check options](https://docs.aws.amazon.com/global-accelerator/latest/dg/about-endpoint-groups-health-check-options.html)

**Edge security and infrastructure**
- [AWS WAF, Firewall Manager and Shield Advanced Developer Guide](https://docs.aws.amazon.com/waf/latest/developerguide/what-is-aws-waf.html)
- [What is AWS Local Zones?](https://docs.aws.amazon.com/local-zones/latest/ug/what-is-aws-local-zones.html)
- [What is AWS Wavelength?](https://docs.aws.amazon.com/wavelength/latest/developerguide/what-is-wavelength.html)
- [What is AWS Outposts?](https://docs.aws.amazon.com/outposts/latest/userguide/what-is-outposts.html)
- [Snowball Edge availability change](https://docs.aws.amazon.com/snowball/latest/developer-guide/snowball-edge-availability-change.html)

**Whitepapers**
- [Disaster Recovery of Workloads on AWS](https://docs.aws.amazon.com/whitepapers/latest/disaster-recovery-workloads-on-aws/disaster-recovery-workloads-on-aws.html)
- [Blue/Green Deployments on AWS](https://docs.aws.amazon.com/whitepapers/latest/blue-green-deployments/welcome.html)
- [AWS Best Practices for DDoS Resiliency](https://docs.aws.amazon.com/whitepapers/latest/aws-best-practices-ddos-resiliency/aws-best-practices-ddos-resiliency.html)

---
[← Previous](04-Networking-VPC-and-Hybrid-Connectivity.md) · [Index](00-README-Start-Here.md) · [Next →](06-Security-Data-Protection-and-Threat-Detection.md)
