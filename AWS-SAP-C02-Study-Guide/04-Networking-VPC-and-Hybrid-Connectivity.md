# Chapter 04 — Networking: Multi-VPC, Hybrid Connectivity & Network Security
> **Exam mapping:** D1 Task 1.1 (network connectivity strategies), D2 Task 2.3 (security controls) & 2.5 (performance), D3 Task 3.3 (performance) & 3.5 (cost) | **Weight signal:** **Very High**. Networking shows up in more SAP-C02 questions than any other topic, often as the hidden constraint in a migration, DR or security question. | **Study time:** ~10–12 h
> [← Previous](03-Identity-and-Access-Management.md) · [Index](00-README-Start-Here.md) · [Next →](05-Edge-DNS-and-Content-Delivery.md)

This chapter follows the structure of the AWS whitepaper *Building a Scalable and Secure Multi-VPC AWS Network Infrastructure*: **(1) network connectivity** (VPC-to-VPC and hybrid), **(2) network security** (centralized egress, inspection, endpoints), and **(3) DNS management**. It also covers VPC fundamentals at Professional depth, monitoring, performance and data-transfer cost.

> **Naming note (2025–2026):** In the docs, *Route 53 Resolver* is now called **Route 53 VPC Resolver**. The API names did not change. Exam questions will almost certainly still say "Route 53 Resolver". **Transit Gateway Network Manager** is now presented as **AWS Global Networks for Transit Gateways**, alongside Cloud WAN in the Network Manager console.

---

## 1. What the exam really tests here

SAP-C02 rarely asks "what is a NAT gateway?". It gives you a company with **dozens to hundreds of accounts and VPCs**, one or more data centers, compliance rules and a cost target. You then pick the connectivity design that meets **all** the constraints. Typical decision points:

| Scenario signal | Decision you must make |
|---|---|
| "Hundreds of VPCs across many accounts, need any-to-any or segmented connectivity" | **Transit Gateway** (Regional hub, route-table segmentation) vs **Cloud WAN** (global, policy-driven) vs peering mesh |
| "Overlapping CIDRs" (M&A, SaaS customers) | **PrivateLink** (service-level), **private NAT gateway**, or VPC Lattice. Peering and TGW **cannot** route overlapping CIDRs. |
| "Inspect all traffic between VPCs and to the internet" | Centralized **inspection VPC** with **Network Firewall** or **GWLB + third-party appliances**, TGW **appliance mode** |
| "Reduce NAT gateway costs across 100 VPCs" | **Centralized egress VPC** via TGW, plus **gateway endpoints** for S3/DynamoDB |
| "Private, consistent, high-bandwidth link to on-prem", "must be encrypted" | **Direct Connect** (+ **MACsec** on 10/100/400G dedicated, or **IPsec VPN over DX**: public VIF or **private IP VPN** over transit VIF) |
| "Resilient hybrid connectivity, 99.99% SLA" | DX **maximum resiliency** model (2 locations × 2 connections), or DX + **VPN backup** |
| "Connect to VPCs in many Regions from one DX" | **Direct Connect gateway** (global) + VGWs or TGWs |
| "On-prem must resolve AWS private zones, and the reverse" | **Route 53 Resolver inbound/outbound endpoints**, forwarding rules **shared via RAM** from a shared-services account |
| "SaaS provider exposes service privately to thousands of customers" | **PrivateLink endpoint service behind NLB** |
| "Troubleshoot why A cannot reach B" / "prove no path from the internet to DBs" | **Reachability Analyzer** / **Network Access Analyzer** |

The exam rewards knowing the **hard limits that rule out options**: peering is non-transitive, gateway endpoints are not reachable from on-prem, a VGW can't do ECMP, a hosted connection has only 1 VIF, and so on. It also rewards knowing the **cost model** (TGW per attachment-hour + per GB, NAT per GB, PrivateLink per AZ-hour + per GB).

---

## 2. Core concepts & services — deep dive

### 2.1 VPC fundamentals at Professional depth

#### CIDR planning and IPAM
- IPv4 VPC CIDR: **/16 to /28**. **5 IPs are reserved per subnet**: network address, +1 (VPC router), +2 (DNS), +3 (reserved), and the last address (broadcast).
- **Secondary IPv4 CIDRs:** default **5 IPv4 CIDR blocks per VPC** (primary included), adjustable up to **50**. Some ranges can't be added, depending on the primary range (check the "IPv4 CIDR block association restrictions" table). **100.64.0.0/10** (RFC 6598) is commonly added as non-routable secondary space, for example for EKS pods.
- **Plan hierarchically.** Summarize by Region, then environment, then business unit, so each Region can be advertised to on-prem as a few aggregates. This matters because the **DX BGP prefix limits** are small: **100 routes per private/transit VIF session from on-prem by default** (up to 1,000 with prefix controls), and **200 prefixes per TGW from AWS to on-prem** over a transit VIF.
- **Amazon VPC IP Address Manager (IPAM):** organization-wide (through a delegated admin account) hierarchical **pools** per Region, environment or BU, with **allocation rules** (allowed netmask lengths, tags). VPCs get CIDRs automatically from a pool, and IPAM **detects overlapping/non-compliant CIDRs** and tracks utilization. It also manages **public IPv4** (Public IP insights, BYOIP, Amazon-provided contiguous blocks). It has Free and Advanced tiers. Choose IPAM whenever the stem says "prevent overlapping CIDRs across hundreds of accounts automatically".

#### IPv6
- A VPC gets an Amazon-provided **/56** (or a BYOIP/IPAM-allocated block). Subnets are **/64**. VPCs can be **dual-stack** or have **IPv6-only subnets**.
- All IPv6 GUAs are globally routable. There is **no NAT for IPv6-to-IPv6**. For outbound-only IPv6 internet access, use an **egress-only internet gateway (EIGW)**: stateful, one per VPC, free (you pay data transfer).
- **NAT64 + DNS64:** IPv6-only workloads reach IPv4 destinations through a NAT gateway (NAT64) and Route 53 Resolver DNS64.
- Why IPv6 matters on the exam: it addresses **IPv4 exhaustion/overlap** and **public IPv4 charges**. AWS charges for every public IPv4 address, in-use or idle.

#### Route tables and longest-prefix match (verified priority order)
1. **Longest prefix match** always wins first.
2. For identical prefixes: **static routes** (IGW, NAT GW, ENI, peering, TGW, gateway endpoint, GWLB endpoint) → **prefix-list routes** → **propagated routes**.
3. Among **VGW-propagated** routes for the same prefix: **Direct Connect BGP** → **VPN static** → **VPN BGP** (shorter AS_PATH wins between BGP VPNs).
- The **local route** covers the VPC CIDR. Since 2021 you can add a route **more specific than the local route** (for example, a subnet CIDR → firewall endpoint) to force intra-VPC traffic through a middlebox.
- **Gateway route tables (ingress routing):** associate a route table with an **IGW or VGW** to steer inbound traffic to an appliance or GWLB endpoint *before* it reaches the subnet. This is the basis of north-south inline inspection in a single VPC.
- Default quotas: **500 non-propagated routes per route table** (up to 1,000), **100 propagated routes** (not adjustable, so advertise summaries or a default route).
- **Managed prefix lists** (customer-managed, shareable via RAM) can be referenced in route tables and SGs. Each counts against quotas by its **max entries**, not its current entries.

#### Security groups vs network ACLs

| | Security group | Network ACL |
|---|---|---|
| Level | ENI (instance, endpoint, LB…) | Subnet |
| State | **Stateful** (return traffic allowed automatically) | **Stateless** (allow ephemeral return ports explicitly, e.g., 1024–65535) |
| Rules | Allow only | Allow **and deny**, numbered, first match wins |
| Default quotas | 60 inbound + 60 outbound rules per SG, 5 SGs per ENI (up to 16; rules × SGs ≤ 1,000) | 20 rules each direction (max 40) |
| References | Other SGs (same VPC, **peered VPC in same Region**, **same TGW with SG referencing enabled, inbound only**), prefix lists | CIDRs only |
| Typical exam use | Micro-segmentation, "allow only from app tier SG" | **Block a specific malicious IP/CIDR quickly** (SGs can't deny) |

#### NAT gateway (verified 2026 facts)
- **Zonal NAT gateway** (classic): lives in **one AZ**, redundant within that AZ. **Deploy one per AZ** and route each AZ's private subnets to its local NAT GW. If one NAT GW is shared and its AZ fails, other AZs lose egress, and you also pay cross-AZ data charges.
- **Regional NAT gateway** (launched late 2025): a single NAT ID that **automatically expands and contracts across AZs** where you have ENIs. It needs **no public subnet**, has its own route table pre-wired to the IGW, and supports up to **32 IPs per AZ**. It **does not support private NAT**, so use zonal for private connectivity. Expansion to a new AZ can take up to ~60 min, and traffic is processed cross-zone until then.
- **Performance:** 5 Gbps, auto-scaling to **100 Gbps**. 1 M pps, scaling to **10 M pps**. **55,000 simultaneous connections per IP per unique destination** (dest IP + port + protocol). Add up to **8 IPs** (zonal) to raise this. "ErrorPortAllocation" in CloudWatch means you need more IPs.
- **No security groups** on a NAT GW. Use NACLs on its subnet.
- **Public vs private connectivity type:**
  - *Public* NAT GW: has an EIP, sends traffic to the IGW. It can also send traffic to a TGW/VGW, but then the source is its **private** IP.
  - *Private* NAT GW: no EIP. Translates to its own private IP toward a **TGW or VGW**. This is **the overlapping-CIDR tool**: workloads in a non-routable (overlapping) secondary CIDR are NATed to a small routable subnet. If traffic goes to an IGW, the IGW drops it.
- **Routing restrictions:** you **can't send traffic into a NAT GW through VPC peering**, nor from **VPN/DX through a VGW**. Traffic *from* VPN/DX **through a TGW** to a NAT GW is supported, which is what makes centralized egress for on-prem possible.
- **Cost:** hourly plus **per-GB processed** (roughly $0.045/GB in many Regions; check pricing), in addition to data transfer. S3/DynamoDB traffic through NAT is a classic cost trap. Use **gateway endpoints**.

#### VPC sharing (AWS RAM)
- The **owner account** creates the VPC and shares **subnets** with other accounts or **OUs in the same AWS Organization**. Participants launch their own resources (EC2, RDS, Lambda, ALB…) into the shared subnets.
- **Owner** controls the VPC, subnets, route tables, NACLs, IGW/NAT/TGW attachments. **Participants** own and pay for their resources and **their own security groups**. They can't modify other accounts' resources or the VPC networking. They can reference SGs of other participants' resources.
- Billing: the VPC owner pays VPC-level components (NAT GW hours, TGW attachment, VGW). Participants pay for their resources and related data transfer.
- Quotas: **100 participant accounts per VPC** and **100 subnets shared with an account** (both adjustable).
- Why it's on the exam: **fewer VPCs means fewer TGW attachments, fewer NAT gateways and less IP waste**, while keeping **account-level isolation for billing and IAM**. It's the classic answer to "reduce cost/complexity of many small VPCs while keeping separate accounts". Limitation: participants share one network blast radius, and only owners can create peering connections.

#### Other recent VPC features to recognise
- **VPC Block Public Access (BPA):** account/Region-wide switch that blocks IGW traffic (bidirectional or ingress-only) with per-VPC/subnet exclusions. It can be applied org-wide with declarative policies.
- **VPC Route Server:** BGP inside the VPC to dynamically update route tables for appliance failover.
- **Emerging / SAP-C03 preview:** **VPC Encryption Controls** (Nov 2025, paid since Mar 2026) audit (*monitor* mode) or enforce (*enforce* mode) encryption in transit within and across VPCs in a Region, and can be applied org-wide with declarative policies. Not core for SAP-C02.

---

### 2.2 VPC peering
- **1:1, non-transitive**, private connection between two VPCs: same or different account, **same or different Region** (inter-Region traffic is encrypted on the AWS backbone).
- **No overlapping CIDRs.** If *any* IPv4 CIDR on either side overlaps, peering fails, even if you only intend to use the non-overlapping blocks.
- **No edge-to-edge routing:** VPC B **can't** use VPC A's IGW, NAT GW, VPN, DX, or **gateway endpoint**.
- **Quotas:** **50 active peerings per VPC** (adjustable up to **125**). Only one peering between any two VPCs. Requests expire after 7 days.
- **MTU:** **9001** intra-Region, **8500** inter-Region.
- **SG referencing:** only for peers in the **same Region**.
- **DNS:** enable "DNS resolution support" to resolve the peer's public DNS hostnames to private IPs. This is required for inter-Region peering.
- **Cost:** **no hourly charge** and no per-GB processing charge. You pay only standard data transfer: **free within the same AZ**, cross-AZ and inter-Region rates otherwise. So peering is the **cheapest and lowest-latency** option for a few high-volume VPC pairs. It also has **no bandwidth bottleneck** beyond instance limits.
- **Scaling problem:** a full mesh needs n(n-1)/2 links (100 VPCs = 4,950 peerings, each with route entries). That is why TGW exists.

---

### 2.3 AWS Transit Gateway (TGW) — in depth

A **Regional, highly available, horizontally scaled Layer-3 router** that you share across accounts with **RAM**.

**Attachment types:** **VPC**, **Site-to-Site VPN**, **VPN Concentrator** (new, many small sites), **Direct Connect gateway** (via transit VIF), **Connect** (GRE + BGP for SD-WAN appliances, over a VPC or DX transport attachment), **peering** (to another TGW intra-/inter-Region, or to a Cloud WAN core network edge), and **network function** (AWS Network Firewall attached natively).

**Key quotas and numbers (verified):**

| Item | Value |
|---|---|
| Attachments per TGW | 5,000 (adjustable) |
| TGWs per account per Region | 5 (adjustable). A VPC can attach to up to 5 TGWs. |
| TGW route tables per TGW | 20 (adjustable) |
| Total routes across all TGW route tables | 10,000 |
| Bandwidth per VPC attachment per AZ | up to **100 Gbps** each direction, 7.5 M pps |
| DXGW / peering attachment bandwidth per AZ | up to 100 Gbps each direction |
| **VPN tunnel** | **up to 1.25 Gbps** / 140k pps (standard). **Large Bandwidth Tunnel: up to 5 Gbps** / 400k pps (TGW or Cloud WAN only) |
| Connect peer (GRE) | up to 5 Gbps. 4 peers per Connect attachment means up to 20 Gbps per attachment |
| Peering attachments per TGW | 50. Only **1 peering between the same two TGWs** |
| DXGWs per TGW / TGWs per DXGW | 20 / 6 |
| MTU | **8500** between VPC, DX, Connect, peering. **VPN traffic 1500** (VPN tunnel itself supports 1446). |

**Route tables: association vs propagation (the #1 TGW concept)**
- **Association** decides *which route table is consulted for traffic **entering** the TGW from that attachment*. **Each attachment is associated with exactly one route table.**
- **Propagation** decides *which route tables **learn routes to** that attachment* (VPC CIDRs, BGP routes from VPN/DX/Connect). **An attachment can propagate to many route tables.**
- **Static routes** override propagated routes with the same prefix. **Blackhole routes** drop matching traffic. They are used to stop spokes reaching each other through a shared default route (e.g., egress VPC).
- TGW peering supports **static routes only**. There is no BGP over TGW peering.
- Default behaviour: a **default route table** with auto-association and auto-propagation means every attachment can reach every other attachment (flat network). For segmentation, **disable defaults** and design route tables yourself.

**TGW route evaluation order (verified, for the same prefix):** static (including static VPN) → prefix-list → **VPC-propagated** → **DX-gateway-propagated** → Connect → VPN-over-DX (private IP VPN) → **VPN-propagated** → VPN Concentrator → Client VPN → peering-propagated (Cloud WAN). Then BGP attributes: shorter AS_PATH, lower MED.
> **Exam consequence:** with DX + VPN on the same TGW advertising the same prefix, the TGW prefers **DX** over **BGP VPN**. If the VPN uses **static routes**, the **static VPN route wins over DX**, which is a classic trap. Use **BGP (dynamic) VPN** for the backup path.

**Segmentation pattern (prod / dev / shared services / on-prem):**

| Route table | Associated attachments | Propagations installed (what they can reach) |
|---|---|---|
| `RT-Prod` | Prod VPCs | Shared-services VPC, on-prem (DXGW/VPN), [optionally other prod VPCs] |
| `RT-Dev` | Dev VPCs | Shared-services VPC, [on-prem if allowed], other dev VPCs |
| `RT-Shared` | Shared-services VPC | Prod VPCs, Dev VPCs, on-prem |
| `RT-OnPrem` | DXGW / VPN attachments | Prod VPCs, Shared-services VPC (not Dev, if policy says so) |

Because there is no prod↔dev propagation, prod and dev cannot route to each other even though both reach shared services.

**Appliance mode:** set on the **VPC attachment of the inspection/appliance VPC**. It makes the TGW keep **both directions of a flow on the same AZ ENI** in that VPC (flow-hash based), which avoids **asymmetric routing that stateful firewalls drop**. Without it, the TGW keeps traffic in the source AZ, so return traffic from another AZ hits a different firewall and is dropped. Requirements: only **VPC attachments**, and **one TGW per appliance VPC** for guaranteed stickiness. **Native Network Firewall TGW attachments enable appliance mode automatically.**

**Other TGW features:**
- **ECMP**: across VPN tunnels (requires **BGP**), across Connect peers, and across DXGW attachments with identical prefix/AS_PATH. **No ECMP across different attachment types** and no AS-path relax across different ASNs.
- **Inter-Region peering**: static routes, encrypted, no ECMP, **no SG referencing across peering**. Data processing is charged only on the sending TGW.
- **Multicast**: must be enabled when you **create** the TGW. Multicast domains, IGMPv2 or static members. Limits include 1 Gbps per flow and 20 Gbps aggregate per AZ, and AWS warns it may not suit HFT/latency-critical workloads.
- **Security group referencing** (inbound rules only) across VPCs on the same TGW. It doesn't work through GWLB/Network Firewall inspection or across peering.
- **TGW Flow Logs**, and the **Global Networks / Network Manager** topology and route analyzer.
- **No DNS resolution of private hosted zones across attachments by itself.** Use Route 53 Resolver or PHZ associations (section 2.10).
- **Overlapping CIDRs:** TGW won't propagate a CIDR that overlaps an existing one.

**Cost model (verified):**
- **Per attachment-hour.** VPC attachment billed to the VPC owner. VPN and Connect attachments billed to the TGW owner. DX attachment billed to the DXGW owner. Peering billed to each side.
- **Per GB processed** for data **sent into** the TGW from VPC, DX, VPN or Network Firewall. **No processing charge for data arriving from a peering attachment.** Connect and private IP VPN have no extra charge beyond the underlying transport.
- Illustration from the pricing page (US East Ohio): **$0.05 per VPC attachment-hour, $0.02/GB processed**. Inter-Region peering adds standard inter-Region data transfer.
- **Implication:** TGW adds a per-GB charge that peering doesn't have. For a small number of **very high-volume** VPC pairs, adding **peering alongside TGW** (longest prefix wins) can cut cost.

---

### 2.4 AWS Cloud WAN
A **managed global WAN** built on the same core technology as TGW, configured with a **declarative JSON core network policy**.
- **Global network** (container) → **core network** (the AWS-managed part) → **core network edges (CNEs)**: one per Region listed in the policy. CNEs are **automatically full-mesh peered**.
- **Segments** are global routing domains, like **globally consistent VRFs**. Attachments in the same segment can talk (optionally isolated from each other). **Segment actions** `share` routes between segments, or send traffic via security functions.
- **Attachment policies** map attachments to segments **by tag** (e.g., `segment=prod`), optionally requiring **approval**. This enables self-service onboarding across accounts. The core network is shared via **RAM**: the core network owner controls the policy, and attachment owners can only create attachments and tags.
- **Attachments:** VPC, Site-to-Site VPN, Connect (SD-WAN), **TGW route table attachments** (over TGW peering, for coexistence/migration), and **DX gateway** attachments.
- **Network function groups / service insertion:** declare in the policy which segment pairs must go *through* firewalls (`send-via`/`send-to`). Cloud WAN steers intra- and inter-Region traffic automatically without static routes.
- **Home Region** for the console/telemetry is **US West (Oregon)**.
- **When to use Cloud WAN instead of TGW:** many Regions plus on-prem branches, **global segmentation** you'd otherwise rebuild with many TGW peering static routes, a central network team wanting **policy-as-code** with tag-based onboarding, and dynamic routing between Regions. **TGW** stays the right answer for **single-Region or few-Region** hubs, when you need fine-grained manual route-table control, or for the lowest unit cost and most mature feature set (multicast, etc.).

---

### 2.5 AWS PrivateLink, interface endpoints and gateway endpoints

#### Interface VPC endpoints (PrivateLink)
- Creates **ENIs with private IPs in your subnets** (one per AZ you choose). Clients reach AWS services, **endpoint services** (your own or partner/SaaS) or Marketplace services privately.
- **Private DNS** (if enabled) makes the service's public hostname (e.g., `sqs.us-east-1.amazonaws.com`) resolve to the endpoint IPs **inside that VPC**.
- **Unidirectional:** only the consumer can initiate. Consumer and provider **CIDRs can overlap**, because there's no routing between the VPCs, only the endpoint ENI. **This is the canonical overlapping-CIDR solution.**
- **Reachable from on-prem** (via DX/VPN) and from **peered/TGW-connected VPCs**. On-prem needs DNS to resolve to the endpoint IPs (inbound Resolver endpoint plus a PHZ or the endpoint-specific DNS names).
- **Security:** endpoint SGs, and **endpoint policies** (resource-style IAM policy limiting which principals/actions/resources can be used *through* the endpoint).
- **Performance:** 10 Gbps per AZ per endpoint, auto-scaling to **100 Gbps** per AZ. MTU 8500. Default quota of **50 interface + GWLB endpoints per VPC**.
- **Cost:** **per endpoint per AZ per hour + per GB processed**. With dozens of services × hundreds of VPCs × 3 AZs this adds up, which leads to the **centralized endpoints** pattern (section 3.5).

#### Endpoint services (be the provider)
- Put your service behind a **Network Load Balancer** (or **GWLB**, for GWLB endpoints), create an **endpoint service**, **allow-list principals** (accounts, roles, Org), and optionally **require acceptance**.
- Consumers in **any account** create interface endpoints to it. The provider sees traffic from the NLB, and can get the client's original IP and endpoint ID through **Proxy Protocol v2**.
- Supports **private DNS names** for the service (domain ownership verified with a TXT record).
- **SaaS provider pattern:** one endpoint service, thousands of customer VPCs with overlapping CIDRs, no peering, no exposure to the internet.
- **Cross-Region PrivateLink** (Nov 2024 for endpoint services, Nov 2025 for selected AWS services such as S3, ECR, Route 53): consumers can create interface endpoints to services in **another Region** of the same partition. The provider must enable the Regions it supports, and inter-Region data transfer applies. Only interface endpoints are supported. Before this, the pattern was "inter-Region peering/TGW to a VPC in the provider's Region, then the endpoint there".
- **Resource endpoints / VPC Lattice resource configurations** (Dec 2024): expose a specific **resource** (e.g., an RDS database, an IP or a domain name) through a **resource gateway** without an NLB. Good to recognise.

#### Gateway endpoints (S3 and DynamoDB only)
- **Free** (no hourly or per-GB charge). Implemented as a **route table entry** whose destination is the service's **AWS-managed prefix list**, so traffic doesn't need an IGW or NAT.
- **Same Region only.** **Not reachable from on-prem, peered VPCs or over TGW** (no edge-to-edge). For on-prem → S3 privately, use an **S3 interface endpoint** (supports DX/VPN), or a public VIF.
- **Endpoint policy** plus **bucket policy conditions**: `aws:SourceVpce` (specific endpoint) or `aws:SourceVpc`. This is how you do **"bucket accessible only from our VPC/endpoint"** (data-perimeter pattern, see Chapter 03). Caveat: `aws:SourceIp` doesn't work for traffic through a VPC endpoint, because the source is a private IP.
- Exam reflex: **"Reduce NAT gateway data-processing cost for S3/DynamoDB traffic" → gateway endpoint.**

| | Gateway endpoint | Interface endpoint (S3 or other services) |
|---|---|---|
| Services | S3, DynamoDB | 100+ AWS services, endpoint services, SaaS |
| Mechanism | Route table + prefix list | ENI + private IP + DNS |
| Cost | **Free** | Per AZ-hour + per GB |
| On-prem / peered / TGW access | **No** | **Yes** |
| Security | Endpoint policy | Endpoint policy + **security groups** |
| Cross-Region | No | Yes (cross-Region PrivateLink, supported services) |

---

### 2.6 Centralized network security — egress, inspection, firewalls

#### Gateway Load Balancer (GWLB)
- **Layer 3** "bump-in-the-wire": listens on **all IP packets on all ports**, load-balances to a target group of **virtual appliances** (firewalls, IDS/IPS, DPI) using **GENEVE encapsulation on UDP 6081**. The original packet is preserved, so it's transparent.
- **Flow stickiness**: 5-tuple (default), 3-tuple or 2-tuple, so both directions hit the same appliance. Health checks remove failed appliances.
- **GWLB endpoints (GWLBE)** are PrivateLink endpoints used as a **route-table next hop**. Appliances can live in a central security account/VPC while being inserted into many VPCs' routing.
- Use GWLB when the requirement is **"use our existing third-party firewall vendor"** (Palo Alto, Fortinet, Check Point…). Use AWS Network Firewall when the requirement is **"managed, AWS-native, least operational overhead"**.

#### AWS Network Firewall
- **Managed, stateful, HA firewall and IDS/IPS** (GWLB under the hood). It creates **firewall endpoints in dedicated firewall subnets per AZ**, and you steer traffic with route tables. It can also attach **natively to a TGW** as a **network function attachment** (mid-2025), which **removes the need for a self-managed inspection VPC**. That attachment supports only static routing on TGW and enables appliance mode automatically.
- **Rule engines:**
  - **Stateless** rule groups: 5-tuple, evaluated per packet in priority order. Actions: pass, drop, or **forward to stateful**.
  - **Stateful** rule groups: **Suricata-compatible IPS rules**, **domain list** rules (allow/deny by **HTTP Host header** and **TLS SNI**, e.g., allow only `.amazonaws.com` and `.github.com`), and standard 5-tuple stateful rules. Evaluation is **strict order** (recommended) or default action order.
  - **AWS managed rule groups**: threat signatures, malware/botnet domain lists.
- **TLS inspection**: decrypt, inspect, re-encrypt. **Inbound** uses your server certificates in ACM. **Outbound** uses a CA certificate (e.g., from AWS Private CA) that clients must trust. One TLS inspection configuration per policy.
- **Limits:** **100 Gbps per firewall per AZ** (traffic over this is dropped), 30,000 stateful rules per policy, 5 firewalls per account per Region (adjustable).
- **Logging:** alert, flow and TLS logs to **S3, CloudWatch Logs or Data Firehose**.
- **Deployment models:** **distributed** (a firewall in each VPC: simple, no TGW cost, but many firewalls to pay for and manage), **centralized** (an inspection VPC/attachment on the TGW for east-west and north-south traffic), and **combined** (centralized for east-west and on-prem traffic, distributed at internet-facing VPCs for ingress).
- **Cost:** per firewall-endpoint-hour plus per GB processed. When a NAT GW is used with Network Firewall, the NAT GW's hourly and per-GB processing charges are discounted (check current pricing).

#### North-south vs east-west inspection

| | North-south | East-west |
|---|---|---|
| Traffic | VPC ↔ internet, VPC ↔ on-prem | VPC ↔ VPC (same or different Region) |
| Typical place | Egress/ingress VPC, IGW ingress routing, distributed firewall in internet-facing VPC | Inspection VPC on TGW (appliance mode) or native TGW firewall attachment, or Cloud WAN service insertion |
| Tools | Network Firewall, GWLB + appliances, AWS WAF (for L7 HTTP ingress), Shield | Network Firewall, GWLB + appliances |

#### AWS Firewall Manager
- **Org-wide central policy management** (requires **AWS Organizations**, a **Firewall Manager administrator account**, and **AWS Config** enabled in member accounts). Policy types: **AWS WAF**, **Shield Advanced**, **VPC security groups** (common/audit/usage-cleanup), **Network Firewall**, **Route 53 Resolver DNS Firewall**, **third-party firewalls** (e.g., Palo Alto Cloud NGFW, Fortigate CNF), and **network ACLs**.
- **Auto-remediates** new accounts and resources in scope (by OU, tags, account). Exam signal: **"ensure every new account/VPC automatically gets the baseline firewall rules"** → Firewall Manager.

---

### 2.7 AWS Direct Connect (DX) — deep dive

A **private, dedicated network connection** from your network to AWS at a **Direct Connect location** (colocation facility). It gives **consistent latency and throughput** and **lower data-transfer-out rates** than the internet. **DX is not encrypted by default.**

#### Connection types (verified)

| | Dedicated connection | Hosted connection |
|---|---|---|
| Ordered from | AWS (console/API), you get an **LOA-CFA** for the cross-connect | An **AWS Direct Connect Partner** provisions it in their port, and you **accept** it |
| Speeds | **1, 10, 100, 400 Gbps** | **50, 100, 200, 300, 400, 500 Mbps, 1, 2, 5, 10, 25 Gbps** (≥1 Gbps only from qualified partners, 25 Gbps only where 100G ports exist) |
| VIFs | **50 private/public VIFs + up to 4 transit VIFs (max 51 total)** | **1 VIF** (private, public or transit) |
| MACsec | **Yes on 10/100/400 Gbps** at selected locations | **No** |
| LAG | Yes | No |
| Speed change | No, you order a new connection | Partner can change it |

- **Hosted VIF** (≠ hosted connection): the owner of a dedicated connection creates a VIF and gives it to another account.
- **Lead time:** AWS reviews a port request in up to **72 business hours**, but the **cross-connect and carrier circuit typically take weeks to months**. Billing starts when the port is active or 90 days after the LOA is issued. **Exam reflex:** "need connectivity *next week*" → **Site-to-Site VPN now**, DX later. For bulk data with a deadline shorter than DX lead time, use online transfer (DataSync) over existing links or an offline transfer option (see [Chapter 13](13-Migration-and-Modernization.md) and [Chapter 08](08-Storage-and-Data-Transfer.md)).

#### Virtual interfaces (VIFs)

| VIF | Connects to | Notes |
|---|---|---|
| **Private VIF** | A **VGW** (one VPC, same Region) or a **Direct Connect gateway** (VGWs in many Regions/accounts) | Private IPs. Jumbo **MTU 9001** supported |
| **Public VIF** | **AWS public endpoints in all public Regions** (S3, DynamoDB, public service APIs, your EIPs) | You advertise **public prefixes you own** (or AWS-provided). AWS advertises all its public prefixes with **NO_EXPORT**. Scope communities `7224:9100/9200/9300`. **Not internet access.** |
| **Transit VIF** | A **Direct Connect gateway → Transit Gateway(s) or Cloud WAN** | Jumbo **MTU 8500**. Up to 4 per dedicated connection |

#### Direct Connect gateway (DXGW)
- A **global** resource (all commercial Regions plus GovCloud, **not China**). It works as a **distributed BGP route reflector** that sits outside the data path, so you don't need several for HA.
- Associate it with **VGWs (up to 20)**, **TGWs (up to 6)**, or a **Cloud WAN core network**. **Up to 30 private or transit VIFs per DXGW**, and **a DXGW carries one VIF type** (private *or* transit).
- **Multi-account:** other accounts send **association proposals**, the DXGW owner accepts and controls **allowed prefixes** (what is advertised to on-prem).
- **No transit between associations:** VGW↔VGW (VPC-to-VPC) traffic through the DXGW isn't allowed (except the documented supernet hairpin case through on-prem), and **on-prem↔on-prem between DX locations isn't allowed unless you use SiteLink**.
- **DXGW + TGW** is the standard enterprise design: **one transit VIF per DX connection → DXGW → TGW in each Region → hundreds of VPCs**. Remember the **200 prefixes per TGW toward on-prem** limit and summarize.

#### Resiliency models (DX Resiliency Toolkit)

| Model | Topology | Protects against | SLA |
|---|---|---|---|
| **Maximum resiliency** | **2 DX locations × 2 connections each** (separate devices) | Device, connection **and complete location** failure | **99.99%** |
| **High resiliency** | **1 connection at each of 2 locations** | Device/fiber failure and location failure (single connection per location) | **99.9%** |
| **Development and test** | **2 connections at 1 location**, on separate devices | Device failure only, **not location failure** | — (non-critical) |
| DX + **VPN backup** | 1+ DX plus a Site-to-Site VPN over the internet | DX failure, at lower bandwidth | Cost-effective for moderate needs |

Use the **Failover Test** feature to bring BGP sessions down and validate failover.

#### LAG (Link Aggregation Group)
- Bundles dedicated connections of **the same speed at the same DX location** using LACP, so they act as one logical link. Up to **4 connections (<100G) or 2 (100G/400G)**. Set **minimum links** so the LAG goes down (and BGP fails over) if too many members fail.
- A LAG increases bandwidth. **It isn't location-resilient**, because all members are in one location.

#### Encryption options over DX

| Option | Layer | Requirements | Notes |
|---|---|---|---|
| **MACsec** | L2, hop-by-hop between your router and the AWS DX device | **Dedicated 10/100/400 Gbps** at MACsec-capable locations, MACsec-capable router, CKN/CAK (static CAK, 256-bit) | Line-rate, no throughput penalty. Not on hosted connections |
| **Site-to-Site VPN over a public VIF** | IPsec L3 | Public VIF reaching the VPN public endpoints | Each tunnel limited to ~1.25 Gbps. Exposes public endpoints |
| **Private IP VPN** over a transit VIF | IPsec L3 with **private IPs** | **TGW + DXGW + transit VIF**, TGW CIDR block | No public IPs. Higher route scale (5,000 out / 1,000 in). Can run encrypted and unencrypted traffic side by side |
| Application-level TLS | L7 | — | Often sufficient. Ask whether "encrypt in transit" really means network-layer encryption |

#### BGP traffic engineering over DX (verified communities)
- **AWS → on-prem path selection (outbound from AWS) on private/transit VIFs:** longest prefix → **local preference communities** you attach to your advertised prefixes: **`7224:7100` low, `7224:7200` medium, `7224:7300` high** → AS_PATH length → MED. By default AWS prefers DX locations associated with the same Region.
  - **Active/passive:** tag primary prefixes `7224:7300` and backup `7224:7100`, or advertise **more-specific prefixes** on the primary.
  - **Active/active (ECMP):** same prefixes, same community and AS_PATH on both.
- **On-prem → AWS (inbound to AWS):** you control it with your own **local preference** on routes learned from AWS. For public VIFs, AWS tags routes `7224:8100` (same Region) and `7224:8200` (same continent).
- **AS_PATH prepending:** influences AWS's choice when local pref is equal. On a **public VIF with a private ASN**, prepending is stripped (AWS replaces your ASN with 7224).
- **BFD (Bidirectional Forwarding Detection):** asynchronous BFD is enabled on the AWS side, so configure it on your router. Without BFD, failover waits for the **BGP hold timer (90 s by default)**. With BFD it takes sub-second to a few seconds.
- **Routes:** default **100 prefixes per BGP session** on private/transit VIFs from on-prem (up to 1,000 with prefix controls). Exceeding it puts the session into **idle/DOWN**, which is a classic outage cause. 1,000 on a public VIF.

#### SiteLink
- Lets **on-prem sites connected to different DX locations talk to each other over the AWS backbone**, bypassing Regions. It's a "global private WAN" replacement for MPLS between data centers.
- Enabled per **private or transit VIF**. Those VIFs must attach to the **same DXGW**, and you need at least two locations. It isn't supported on VIFs attached directly to a VGW, or on public VIFs. Pricing is an hourly SiteLink charge per VIF plus per-GB SiteLink data transfer.

#### DX data-transfer pricing essentials
- Port-hours (dedicated) or partner fees (hosted), plus **DTO over DX** at **lower rates than internet DTO**. Data in is free. The DX DTO rate depends on the DX location and the source Region.
- A big data-egress workload (e.g., 500 TB/month back to on-prem) is often **cheaper over DX** than over the internet. That's a common cost-optimization answer.

---

### 2.8 AWS Site-to-Site VPN
- An **IPsec** VPN between a **customer gateway (CGW)** device and either a **VGW** (single VPC) or a **TGW** / Cloud WAN.
- **Each VPN connection has 2 tunnels** terminating on different AWS endpoints. Configure **both** for HA. AWS maintenance can take one tunnel down.
- **Routing:** **static** or **dynamic (BGP)**. Use **BGP** for automatic failover, ECMP on TGW, and correct preference against DX. **ECMP is not supported with static routing.**
- **Bandwidth:** **up to 1.25 Gbps per standard tunnel** (140k pps). **Large Bandwidth Tunnels** go **up to 5 Gbps** (TGW/Cloud WAN only, not VGW, not accelerated, new connections only). **VGW: no ECMP**, so ~1.25 Gbps is effectively the ceiling for one active tunnel. **TGW + BGP + ECMP:** aggregate many tunnels/connections (e.g., 4 connections × 2 tunnels ≈ 10 Gbps at 1.25 Gbps per tunnel).
- **MTU:** max **1446 bytes** (MSS 1406), **no jumbo frames, no PMTUD**.
- **Accelerated VPN:** uses **Global Accelerator** edge locations to get onto the AWS backbone close to the CGW. Better for distant or unreliable internet paths. **TGW only**, must be chosen at creation, NAT-T required, not usable over a DX public VIF.
- **VPN Concentrator** (Nov 2025): **TGW-only** attachment aggregating **up to 100 low-bandwidth sites (≤100 Mbps each, ~5 Gbps aggregate)** with **BGP only**. Cheaper than one VPN attachment per branch. Good for many small branches/stores.
- **Quotas to know:** 10 VPN connections per VGW (adjustable), 100 BGP routes from CGW to a VGW VPN versus **1,000 to a TGW VPN**.
- **VPN as DX backup:** advertise the same prefixes over both using BGP. Both on **VGW** and on **TGW**, **DX-learned routes are preferred over BGP VPN routes** for the same prefix. You can also make the VPN less preferred with **longer AS_PATH**. Watch out: **static VPN routes beat DX on a TGW** and **beat VPN BGP on a VGW**.
- **VPN CloudHub:** several sites, each with a CGW using a **unique BGP ASN**, connect to the **same VGW**. The VGW re-advertises routes so **sites can reach each other** (hub-and-spoke over the internet). It's a low-cost branch-to-branch backup. Today a TGW, Cloud WAN or SiteLink usually replaces it for scale.

### 2.9 AWS Client VPN
- A managed **OpenVPN-based remote-access** (user-to-network) VPN.
- **Authentication:** **mutual certificate**, **Active Directory** (via Directory Service), or **SAML 2.0 federation** (IAM Identity Center, Okta…). Combinations are allowed.
- **Target network associations** are subnets, each creating an ENI. Client traffic is **source-NATed to the ENI IP**. **Authorization rules** decide which groups reach which CIDRs. **Route table** entries extend reach to peered VPCs, TGW-connected VPCs, on-prem or the internet.
- **Split tunnel** (only VPC routes through the VPN) vs full tunnel. Use **client connect handler** Lambda for posture checks.
- **Pricing:** per **subnet-association-hour + per active connection-hour**.
- Exam: "remote employees need secure access to private VPC resources, with SSO via IdP" → **Client VPN with SAML**. Alternative for zero-trust app access without VPN clients: **AWS Verified Access**.

---

### 2.10 Hybrid DNS with Route 53 Resolver (VPC Resolver)
- Every VPC has the **Amazon-provided DNS (Route 53 Resolver)** at **VPC base + 2** (and `169.254.169.253`). It resolves public names, VPC names, and **private hosted zones (PHZs) associated with that VPC**. **Each ENI can send 1,024 packets/s to it** (hard limit), so very high-volume DNS clients need caching.
- **Inbound endpoint**: ENIs (≥2 AZs) that **on-prem DNS servers forward to**, so on-prem can resolve PHZs and VPC names.
- **Outbound endpoint + forwarding rules**: Resolver forwards queries for, e.g., `corp.example.com` to **on-prem DNS IPs** through the outbound endpoint ENIs. **System rules** override forwarding for subdomains (e.g., keep `aws.corp.example.com` resolved in AWS).
- **Quotas:** 4 endpoints per Region per account (adjustable), up to 6 IPs per endpoint (adjustable), **~10,000 UDP QPS per endpoint IP** (can be as low as ~1,500 with connection tracking), 1,000 rules per Region.
- **Centralized hybrid DNS (whitepaper pattern):** create the inbound and outbound endpoints **once in a shared-services (network) account VPC**. **Share the forwarding rules through AWS RAM** with the Organization, and associate them with every spoke VPC. Spokes resolve on-prem names through the central outbound endpoint (over TGW), **without their own endpoints**. On-prem forwards AWS zones to the central inbound endpoint.
- **PHZ association across accounts:** in the PHZ owner account, run `create-vpc-association-authorization`. Then, from the VPC's account, run `associate-vpc-with-hosted-zone` (CLI/API/SDK, not console). Up to **300 VPCs per PHZ**. Beyond that, or for simpler management, use **Route 53 Profiles**.
- **Route 53 Profiles** (2024): bundle **PHZs, Resolver rules, DNS Firewall rule groups and query-logging configs**, share the Profile via **RAM**, and associate it with up to 1,000 VPCs per Profile. This is the modern "one DNS configuration for all VPCs" answer.
- **Resolver DNS Firewall:** domain lists (custom or **AWS managed** malware/botnet lists) with ALLOW / BLOCK (NODATA, NXDOMAIN, override) / ALERT actions. It blocks **DNS-based data exfiltration** and malicious-domain lookups for queries through the VPC Resolver, with a configurable **fail-open vs fail-closed** setting. It's managed org-wide with **Firewall Manager**. It doesn't apply if instances use a custom DNS server that bypasses the Resolver.
- **Resolver query logging** to CloudWatch Logs, S3 or Firehose, shareable via RAM.
- **DNSSEC validation** can be enabled on the Resolver.
- (Emerging) **Route 53 Global Resolver** (preview, Nov 2025): an internet-reachable anycast resolver for clients outside VPCs. Not SAP-C02 core.

---

### 2.11 Network monitoring and troubleshooting

| Tool | What it does | Use when |
|---|---|---|
| **VPC Flow Logs** | **Metadata** (5-tuple, bytes, packets, ACCEPT/REJECT, plus custom fields such as `pkt-srcaddr`, `tcp-flags`, `flow-direction`, `traffic-path`) for **VPC/subnet/ENI** and **TGW**. Published to **CloudWatch Logs, S3 or Data Firehose**. **No payload.** Doesn't log traffic to the Resolver at +2, instance metadata (169.254.169.254), DHCP, Time Sync, or Windows license activation | Security analytics (Athena), "who talked to whom", rejected-traffic troubleshooting, GuardDuty source |
| **Traffic Mirroring** | **Copies full packets** from an ENI (Nitro) to a target (**ENI, NLB, or GWLB endpoint**), **VXLAN**-encapsulated, with filters | **IDS/IPS, forensics, deep packet inspection**: "need packet payload", "out-of-band" |
| **Reachability Analyzer** | **Static configuration analysis** (sends no packets) of a path between a source and destination (instances, ENIs, IGW, TGW, peering, endpoints…). Hop-by-hop result with the **blocking component** (SG, NACL, route) | "Why can't A reach B?", validate connectivity after changes, **cross-account with Organizations** |
| **Network Access Analyzer** | Evaluates **Network Access Scopes** (e.g., "no path from IGW to DB subnets", "only prod VPCs reach on-prem") and reports **unintended access paths** | Compliance and continuous verification of segmentation |
| **Network Manager / Global Networks for TGW** and **Cloud WAN dashboard** | Global topology, **route analyzer**, events, and on-prem site/device/link registration (SD-WAN integration) | Multi-Region TGW visibility |
| **Infrastructure Performance** (Network Manager) | AWS-published latency between Regions/AZs | Choosing Regions, latency baselines |
| **CloudWatch Network Monitoring**: Network Synthetic Monitor, Internet Monitor, Network Flow Monitor | Probes for hybrid paths (DX/VPN latency and loss), internet impact on your users, flow-level performance between workloads | Hybrid SLA monitoring, "detect degradation of DX" |
| **DX CloudWatch metrics** (ConnectionState, BPS, PPS, light levels) and **VPN TunnelState** | Alarm on link or tunnel down | Operational alerting |

---

### 2.12 Network performance
- **Enhanced networking:** **ENA** (Elastic Network Adapter), up to hundreds of Gbps on the latest instance types. SR-IOV gives higher PPS and lower latency. **EFA** (Elastic Fabric Adapter) adds OS-bypass for **HPC/ML MPI and NCCL** workloads. **ENA Express** (SRD protocol) raises single-flow bandwidth and reduces tail latency between supported instances in the same AZ.
- **Per-flow limits:** a single 5-tuple flow is limited (about **5 Gbps** between instances not in the same cluster placement group, higher within one). Exam takeaway: **"single TCP stream is slow even on a 100 Gbps instance" → use multiple flows, a cluster placement group or ENA Express.**
- **MTU cheat sheet:**

| Path | Max MTU |
|---|---|
| Within a VPC, intra-Region VPC peering | **9001** (jumbo) |
| TGW (VPC, DX, Connect, peering), inter-Region peering, VPC endpoints (PrivateLink), NAT GW | **8500** |
| DX private VIF / transit VIF | 9001 / 8500 (jumbo must be enabled on the VIF) |
| Site-to-Site VPN | **1446** (no jumbo, no PMTUD) |
| Internet (IGW), outside the VPC | **1500** |

- **Placement groups** (brief): **cluster** (one AZ, lowest latency and highest per-flow throughput, for HPC), **spread** (max 7 running instances per AZ per group, for critical instances on distinct hardware), **partition** (up to 7 partitions per AZ, rack-aware, for HDFS/Cassandra/Kafka).
- **Hybrid performance:** DX for consistent latency. **Accelerated VPN** or **Global Accelerator** when users or sites are far from the Region. Large Bandwidth Tunnels or ECMP for VPN throughput.

### 2.13 Amazon VPC Lattice (application-layer service networking)
- A **fully managed application networking service** for **service-to-service** connectivity across VPCs and accounts, **without TGW, peering or routing**, and it **tolerates overlapping CIDRs**.
- Building blocks: a **service network** (logical boundary, shared via RAM) that VPCs associate with. **Services** have listeners (HTTP/HTTPS/gRPC/TLS/TCP), rules and **target groups** (EC2, IP, **Lambda**, **ALB**, ECS tasks, **EKS pods** via the Gateway API controller). **Resource configurations + resource gateways** cover TCP resources such as **RDS** or domain names.
- **Security:** **auth policies** (IAM, SigV4-signed requests) at the service-network and service level, plus SGs on the VPC association. This is **zero-trust, identity-based, per request**.
- **Service network VPC endpoints** (PrivateLink) allow access **from on-prem** through DX/VPN, or through TGW/peering.
- **No inter-AZ data transfer charges** within Lattice. Pricing is per service-hour + per GB + per request.
- **When to choose it:** "microservices across many accounts and VPCs owned by different teams, want IAM-based auth between services and minimal network plumbing, overlapping CIDRs" → **VPC Lattice**. For L3 any-to-any connectivity (databases, legacy protocols, on-prem ranges) → TGW/Cloud WAN. *(Lattice is listed as emerging/SAP-C03-heavy, but it can appear on SAP-C02 as a correct modern option.)*

### 2.14 Data transfer cost implications (what moves the bill)

| Flow | Cost driver (directional; check current pricing) |
|---|---|
| Internet → AWS | Free |
| Same AZ, private IP | Free (also free across a **same-AZ VPC peering**) |
| **Cross-AZ** | ~$0.01/GB **each direction** (also applies to cross-AZ NAT GW or endpoint use) |
| Inter-Region | Per GB charged on the sending side (varies by Region pair) |
| AWS → internet | Tiered DTO rates (highest unit cost) |
| AWS → on-prem over **DX** | **Lower DX DTO rate** + port-hours |
| **NAT gateway** | Per hour + **per GB processed** (plus DTO) |
| **Transit Gateway** | Per attachment-hour + **per GB processed** (sending side) |
| **PrivateLink interface endpoint** | Per AZ-hour + per GB processed |
| **Gateway endpoint** | **Free** |
| **VPC peering** | No hourly or processing fee, only data transfer |
| Network Firewall / GWLB | Per endpoint-hour + per GB |

**Cost levers the exam loves:** gateway endpoints instead of NAT for S3/DynamoDB. NAT GW **per AZ** to avoid cross-AZ charges (and keep AZ independence). **Centralized egress** to cut NAT-hour count (but it adds TGW per-GB). **Peering for high-volume pairs** next to TGW. **VPC sharing** to reduce the number of VPCs and attachments. **DX** for heavy egress to on-prem. Keep chatty tiers **in the same AZ**. Also note that **public IPv4 addresses are charged**, so consider IPv6, fewer EIPs, or centralized NAT.

---

## 3. Architecture patterns

### 3.1 Hub-and-spoke Transit Gateway with segmentation (multi-account)

```text
                       Network account (owns TGW, shares via RAM)
                     +-------------------------------------------+
                     |              Transit Gateway              |
                     |  RT-Prod   RT-Dev   RT-Shared   RT-OnPrem |
                     +---^--------^---------^------------^-------+
          assoc RT-Prod  |        | assoc   | assoc      | assoc RT-OnPrem
                         |        | RT-Dev  | RT-Shared  |
   +-----------+  +-----------+  +-----------+  +-------------------+
   | Prod VPC 1|  | Dev VPC 1 |  | Shared    |  | DXGW (transit VIF)|
   | Prod VPC 2|  | Dev VPC 2 |  | Services  |  |  + S2S VPN (BGP)  |
   | (acct P)  |  | (acct D)  |  | VPC (AD,  |  +---------+---------+
   +-----------+  +-----------+  | DNS, CI)  |            |
                                 +-----------+       On-prem DC

  Propagations:  Prod  -> RT-Shared, RT-OnPrem
                 Dev   -> RT-Shared            (NOT RT-Prod, NOT RT-OnPrem)
                 Shared-> RT-Prod, RT-Dev, RT-OnPrem
                 OnPrem-> RT-Prod, RT-Shared
  Result: Prod <-> Dev blocked; both reach Shared; only Prod + Shared reach on-prem.
```
**When:** tens to thousands of VPCs in one Region, with central control by the network team. **Trade-offs:** per-attachment and per-GB charges, and a 10,000-route budget. Multi-Region needs TGW peering with **static** routes, or Cloud WAN.

### 3.2 Centralized egress (NAT) through TGW

```text
 Spoke VPC A (10.1/16)        Spoke VPC B (10.2/16)
 private subnets              private subnets
 0.0.0.0/0 -> TGW             0.0.0.0/0 -> TGW
        \                         /
         \                       /
       +---v---------------------v---+
       |        Transit Gateway      |
       | RT-Spokes: 0.0.0.0/0 -> Egress attachment (static)
       |            10.0.0.0/8 -> blackhole  (stops spoke<->spoke via egress)
       | RT-Egress: 10.1/16, 10.2/16 propagated (return path)
       +--------------+--------------+
                      |
          +-----------v------------------------------+
          | Egress VPC (100.64.x or small CIDR)      |
          |  TGW attachment subnets (per AZ)         |
          |    0.0.0.0/0 -> NAT GW (same AZ)          |
          |  Public subnets: NAT GW per AZ (EIPs)    |
          |    0.0.0.0/0 -> IGW                       |
          |    10.0.0.0/8 -> TGW   (return traffic)   |
          +-----------------+------------------------+
                            |
                         Internet
```
**Why:** fewer NAT gateways and EIPs (one set per AZ for the whole Region instead of per VPC), **one place to allow-list egress IPs** with partners, and a natural place to add inspection. **Cost caution:** every GB now pays **TGW processing + NAT processing**. For heavy egress VPCs a local NAT might be cheaper. **Must add:** gateway endpoints in spokes for S3/DynamoDB so bulk data doesn't hairpin through TGW + NAT. **HA:** NAT GW per AZ, with the TGW attachment in every AZ.

### 3.3 Centralized inspection VPC (east-west + north-south) with GWLB or Network Firewall

```text
   Spoke VPCs (prod/dev)            On-prem (DX/VPN)
        |   0.0.0.0/0 -> TGW               |
        v                                  v
  +--------------------------------------------------------+
  |                      Transit Gateway                    |
  |  RT-Spokes  (assoc: spokes, DX/VPN): 0.0.0.0/0 -> Inspection att. |
  |  RT-Firewall(assoc: Inspection att.): spoke + on-prem CIDRs propagated, |
  |                                       0.0.0.0/0 -> Egress VPC     |
  +--------------------------+-----------------------------+
                             |  ** APPLIANCE MODE ON **
            +----------------v---------------------------+
            | Inspection VPC                             |
            |  TGW subnet (AZ-a)     TGW subnet (AZ-b)   |
            |   0/0 -> FW/GWLBE-a     0/0 -> FW/GWLBE-b  |
            |  Firewall subnet: Network Firewall endpoint|
            |   or GWLB endpoint -> GWLB -> appliances   |
            |   (GENEVE 6081, 5-tuple stickiness)        |
            |   0/0 -> TGW (back to TGW after inspection)|
            +--------------------------------------------+
   Alternative (2025+): Network Firewall **native TGW attachment** (network
   function attachment) replaces the self-managed inspection VPC; appliance
   mode is enabled automatically.
```
**Key points:** **Appliance mode on the inspection VPC attachment** (or symmetric flows break). Use two TGW route tables ("pre-inspection" for spokes, "post-inspection" for the firewall attachment). North-south egress can be combined in the same VPC (firewall → NAT → IGW). East-west traffic between two spokes goes spoke → TGW → firewall → TGW → spoke.

### 3.4 Distributed ingress inspection in an internet-facing VPC (IGW ingress routing)

```text
 Internet
    |
  [IGW]  <- gateway route table: 10.0.1.0/24 (ALB subnet) -> FW endpoint (vpce-...)
    |
 [Firewall subnet: Network Firewall endpoint / GWLBE]
    |        route: 0/0 -> IGW
 [Public ALB subnet]   route: 0/0 -> FW endpoint (symmetric return)
    |
 [Private app subnets]
```
Use it for per-VPC internet ingress inspection (often combined with **AWS WAF on the ALB** for L7). Route symmetry must be maintained per AZ.

### 3.5 Centralized interface endpoints (shared services VPC)

```text
  Spoke VPCs  --(TGW)-->  Endpoint/Shared-services VPC
  (associated with          Interface endpoints: sts, ssm, kms, ecr.api,...
   the PHZs below)          (Private DNS DISABLED on the endpoints)
                            Route 53 PHZ "ssm.us-east-1.amazonaws.com"
                              alias -> endpoint regional DNS name
                            PHZs associated with all spoke VPCs
                            (cross-account authorization or Route 53 Profiles)
```
**Why:** you pay endpoint-hours **once** instead of per VPC. **Trade-offs:** TGW per-GB charge, a shared blast radius, and the endpoint policy must cover all consumers. Not applicable to **gateway endpoints** (they can't be reached through TGW). **Break-even:** for low-traffic, many-VPC estates centralization wins. For heavy per-VPC traffic (e.g., ECR pulls at scale) local endpoints can be cheaper.

### 3.6 Direct Connect with VPN backup via DXGW + TGW (multi-Region)

```text
       On-prem DC (BGP ASN 65010)
       |                     \
  [DX location 1]       Internet
   dedicated 10G            \
   transit VIF               \  Site-to-Site VPN (BGP, 2 tunnels,
       |                      \  ECMP across connections)
  +----v-------------+         \
  | Direct Connect   |          \
  | gateway (global) |           \
  +---+----------+---+            \
      |          |                 \
  [TGW us-east-1] [TGW eu-west-1] <-+  (VPN attaches to the TGW)
      |               |
   VPCs...          VPCs...

  Path selection on the TGW for the same on-prem prefix:
   DX-gateway-propagated  >  VPN-propagated (BGP)       -> DX active, VPN standby
   !! a STATIC VPN route would win over DX -> use BGP for the VPN !!
  On-prem side: prefer DX-learned routes (higher local-pref) for symmetric return.
```
For a **99.99% design**, replace the VPN with a second DX location (maximum resiliency: 2 locations × 2 connections). Enable **BFD** for fast failover.

### 3.7 DX maximum resiliency

```text
   DC-1 router A ---- DX Location X, device 1 --\
   DC-1 router B ---- DX Location X, device 2 ---+--> DXGW --> TGWs / VGWs
   DC-2 router C ---- DX Location Y, device 1 ---+
   DC-2 router D ---- DX Location Y, device 2 --/
   (each a separate dedicated connection; BGP + BFD on all; local-pref
    communities 7224:7300 / 7224:7100 for active/passive, or same tag for ECMP)
```

### 3.8 Hybrid DNS (centralized in a shared-services account)

```text
                 On-prem DNS (corp.example.com)
                   |  conditional forwarder: aws.example.com,
                   |  *.amazonaws.com (endpoints) -> Inbound endpoint IPs
                   v
  +-----------------------------------------------------------+
  | Shared-services VPC (Network account)                     |
  |  Route 53 Resolver INBOUND endpoint  (ENIs in 2+ AZs)     |
  |  Route 53 Resolver OUTBOUND endpoint (ENIs in 2+ AZs)     |
  |  Forwarding rule: corp.example.com -> on-prem DNS IPs     |
  |      shared via AWS RAM to the Organization               |
  +-----------------------------+-----------------------------+
                                | TGW / DX
     Spoke VPCs (any account): rule associated with VPC
       -> query corp.example.com -> VPC Resolver (.2)
       -> forwarded via central OUTBOUND endpoint -> on-prem DNS
     Spoke PHZs (aws.example.com) associated cross-account with the
       shared-services VPC so the INBOUND endpoint can answer on-prem.
```
**Modern variant:** use a **Route 53 Profile** containing the rules, PHZs and DNS Firewall rule groups, shared via RAM and associated with every VPC.

### 3.9 Overlapping CIDRs: three escape hatches

```text
 (a) PrivateLink                 (b) Private NAT gateway               (c) VPC Lattice
 Consumer VPC 10.0/16            VPC: 10.0/16 (overlapping, non-routable)  Service network
  [Interface EP ENI] ---->        + 100.64.10.0/24 (routable secondary)    (RAM-shared)
  NLB -> service                  workloads in 10.0/16 -> private NAT GW    VPCs with ANY
 Provider VPC 10.0/16             in 100.64.10.0/24 -> TGW -> other nets    CIDR associate;
 (no routing between VPCs)        inbound: ALB/NLB in routable subnet       service-level
                                                                            HTTP/TCP access
```
Peering and TGW **cannot** route between overlapping CIDRs. Re-IP is the long-term fix (IPAM helps prevent recurrence).

### 3.10 SaaS provider via PrivateLink

```text
 Customer A VPC (10.0/16) --[Interface EP]--\
 Customer B VPC (10.0/16) --[Interface EP]---+--> Endpoint service --> NLB --> SaaS fleet
 Customer C (on-prem via DX to its VPC EP)--/   (allow-listed principals,
                                                 acceptance required,
                                                 Proxy Protocol v2 for client identity,
                                                 private DNS name verified via TXT)
```

---

## 4. Decision tables / "X vs Y"

### 4.1 VPC-to-VPC connectivity

| Requirement | VPC peering | Transit Gateway | Cloud WAN | PrivateLink | VPC Lattice | VPC sharing |
|---|---|---|---|---|---|---|
| Transitive / hub routing | ❌ | ✅ | ✅ | n/a (service only) | n/a (service only) | n/a (same VPC) |
| Overlapping CIDRs | ❌ | ❌ | ❌ | ✅ | ✅ | n/a |
| Scale | ≤125 peers/VPC, mesh pain | 5,000 attachments/Region | Global, policy-driven | Thousands of consumers | Many services/accounts | 100 participant accounts/VPC |
| Multi-Region | Inter-Region peering | TGW peering (static) | Native (CNE full mesh) | Cross-Region PrivateLink | Regional | Single Region |
| Cost | DT only (cheapest) | Attachment-hour + per GB | CNE-hour + attachment + per GB | Endpoint AZ-hour + per GB | Service-hour + GB + requests | No extra |
| Bandwidth | No aggregate limit | 100 Gbps per VPC attachment per AZ | Similar to TGW | 100 Gbps per AZ per endpoint | Managed | Native |
| Best for | Few VPCs, high volume, lowest latency | Regional hub, segmentation, hybrid | Global multi-Region WAN, policy-as-code | Expose one service privately, SaaS, overlapping | Service-to-service with IAM auth | Fewer VPCs, account isolation |

### 4.2 TGW vs Cloud WAN

| Factor | Transit Gateway | Cloud WAN |
|---|---|---|
| Scope | Regional (peer for multi-Region) | Global (Regions defined in policy) |
| Config | Route tables, associations, propagations (imperative) | JSON **core network policy** (declarative), versioned with rollback |
| Segmentation | Per-TGW route tables, replicated manually per Region | **Global segments**, consistent everywhere |
| Inter-Region routing | **Static** routes over peering | **Dynamic**, automatic full mesh |
| Onboarding | Attach + associate/propagate (automate with IaC/Lambda) | **Tag-based attachment policies** + optional approval |
| Inspection insertion | Inspection VPC / native NFW attachment + route tables | **Service insertion** (network function groups, send-via) |
| Pick when | 1–3 Regions, mature tooling, multicast, granular control | Many Regions + branches, central policy, minimal per-Region ops |

### 4.3 Hybrid connectivity

| Need | Choose |
|---|---|
| Fast to set up (hours), encrypted, ≤ ~1.25 Gbps per tunnel | **Site-to-Site VPN** |
| Higher VPN throughput | **TGW + BGP + ECMP** across tunnels/connections, or **5 Gbps Large Bandwidth Tunnels** |
| Distant site with a poor internet path | **Accelerated VPN** (TGW) |
| Consistent latency, high bandwidth, lower DTO | **Direct Connect** (weeks of lead time) |
| Encrypted at 10/100/400G line rate | **DX + MACsec** (dedicated) |
| Encrypted, no public IPs, via TGW | **Private IP VPN over DX transit VIF** |
| Access AWS public services (S3) over DX | **Public VIF** (or private VIF + S3 interface endpoint) |
| One DX to VPCs in multiple Regions/accounts | **DX gateway** |
| Hundreds of VPCs over DX | **Transit VIF → DXGW → TGW** |
| Small bandwidth (<1 Gbps) DX without own colocation port | **Hosted connection** via partner |
| Branch-to-branch over AWS | **SiteLink** (DX), **Cloud WAN**, or **VPN CloudHub** (low-cost legacy) |
| Many small branches (≤100 Mbps each) | **VPN Concentrator** on TGW |
| Remote users | **Client VPN** (or Verified Access for app-level zero trust) |

### 4.4 DX VIF types

| | Private VIF | Transit VIF | Public VIF |
|---|---|---|---|
| Target | VGW or DXGW→VGWs | DXGW→TGWs / Cloud WAN | AWS public endpoints (all Regions) |
| Scale | 1 VPC per VGW (20 VGWs per DXGW) | Up to 6 TGWs per DXGW → thousands of VPCs | n/a |
| MTU | 9001 | 8500 | 1500 |
| Per dedicated connection | up to 50 (shared with public) | up to 4 | up to 50 (shared with private) |

### 4.5 Endpoint types

| | Gateway endpoint | Interface endpoint | GWLB endpoint | Resource / service-network endpoint |
|---|---|---|---|---|
| For | S3, DynamoDB | AWS services, endpoint services | Inline appliances (route target) | Lattice resources / service networks |
| Cost | Free | AZ-hour + GB | AZ-hour + GB | Hourly + GB |
| On-prem reachable | No | Yes | n/a | Yes |

### 4.6 Inspection options

| Need | Choose |
|---|---|
| Managed, least ops, Suricata IPS, FQDN filtering | **AWS Network Firewall** |
| Keep existing third-party firewall vendor / features | **GWLB + vendor appliances** (Auto Scaling) |
| Block malicious **DNS lookups** / DNS exfiltration | **Route 53 Resolver DNS Firewall** |
| L7 HTTP attacks (SQLi/XSS, bots) on ALB/CloudFront/API GW | **AWS WAF** |
| Org-wide enforcement of all of the above | **AWS Firewall Manager** |
| Instance-level allow rules | **Security groups** |
| Explicit deny of a CIDR at subnet level | **NACL** |

### 4.7 Troubleshooting tools

| Question | Tool |
|---|---|
| "Is there a configured path from A to B, and what blocks it?" | **Reachability Analyzer** |
| "Prove no unintended access exists (internet → DB)" | **Network Access Analyzer** |
| "Which IPs talked, accepted/rejected?" | **VPC Flow Logs** (+ Athena) |
| "Need packet payloads for IDS/forensics" | **Traffic Mirroring** |
| "Monitor DX/VPN latency and packet loss to on-prem" | **CloudWatch Network Synthetic Monitor** |
| "Global TGW topology and routes" | **Network Manager (Global Networks) / Cloud WAN dashboard** |

---

## 5. Exam keyword → answer cheat list

- "**Hundreds of VPCs**, many accounts, **transitive** routing" → **Transit Gateway** shared via **RAM**.
- "**Multiple Regions**, global segments, **policy-based**, tag onboarding" → **Cloud WAN**.
- "**Overlapping CIDR** + expose a service" → **PrivateLink (NLB endpoint service)**. Overlap + need routed outbound access → **private NAT gateway**. Overlap + microservices → **VPC Lattice**.
- "**Isolate dev from prod** but both reach shared services" → **TGW with separate route tables** (association/propagation), **blackhole** routes.
- "**Stateful firewall drops return traffic** in a centralized inspection VPC" → enable **TGW appliance mode**.
- "**Third-party virtual appliances**, transparent, scale out" → **Gateway Load Balancer** (GENEVE 6081).
- "**Managed** firewall, **FQDN allow-list** for egress, **Suricata** rules" → **AWS Network Firewall**.
- "Apply firewall rules **automatically to all new accounts**" → **Firewall Manager**.
- "**Reduce NAT cost** for S3/DynamoDB" → **gateway VPC endpoint**.
- "**Reduce number of NAT gateways / EIPs** across many VPCs" → **centralized egress VPC** via TGW.
- "On-prem needs **private access to S3**" → **S3 interface endpoint** (gateway endpoints aren't reachable from on-prem) or a **public VIF**.
- "**Restrict bucket** to our VPC" → bucket policy `aws:SourceVpce` / `aws:SourceVpc` + endpoint policy.
- "**Encrypt DX** at **100 Gbps**" → **MACsec**. "Encrypt DX, any speed, with **private IPs**" → **private IP VPN over transit VIF**. "Encrypt DX" on a **hosted** connection → **IPsec VPN** (MACsec isn't available).
- "**99.99%** DX availability" → **two DX locations, two connections each** (maximum resiliency).
- "**Cost-effective** backup for DX" → **Site-to-Site VPN with BGP**.
- "**Fast failover** on DX" → **BFD**.
- "Prefer **one DX path** (active/passive)" → **local preference communities 7224:7300/7224:7100** or **more-specific prefixes**. AS_PATH prepending applies when local pref is equal.
- "**One DX**, VPCs in **multiple Regions/accounts**" → **Direct Connect gateway**.
- "Need DX in **2 weeks**" → not realistic. **VPN now**, DX later.
- "**> 1.25 Gbps over VPN**" → **TGW + ECMP (BGP)** or **5 Gbps Large Bandwidth Tunnels** (TGW/Cloud WAN).
- "**Branch offices communicate with each other** via AWS" → **VPN CloudHub** (VGW, unique ASNs), **Cloud WAN**, or **DX SiteLink**.
- "**Remote workforce**, SSO" → **Client VPN with SAML**.
- "On-prem resolves **AWS private hosted zones**" → **Resolver inbound endpoint**. "AWS resolves **on-prem names**" → **outbound endpoint + forwarding rule**. "**Many accounts**" → share rules with **RAM** / **Route 53 Profiles**.
- "Associate a PHZ with a **VPC in another account**" → **create-vpc-association-authorization** + **associate-vpc-with-hosted-zone** (CLI/API).
- "**Block DNS exfiltration** / malicious domains" → **Route 53 Resolver DNS Firewall**.
- "Why can't instance A reach B?" → **Reachability Analyzer**. "Packet capture" → **Traffic Mirroring**.
- "**Jumbo frames** to on-prem over VPN" → impossible (1446 MTU). Use DX (private VIF 9001 / transit VIF 8500).
- "**Lowest latency** HPC between instances" → **cluster placement group + EFA/ENA**.
- "Fewer VPCs, keep **separate accounts/billing**" → **VPC sharing (RAM)**.
- "**Prevent overlapping CIDRs** org-wide, automate allocation" → **VPC IPAM**.
- "IPv6 instances need **outbound-only** internet" → **egress-only internet gateway**.
- "**Microservices** across accounts, **IAM auth between services**, no network plumbing" → **VPC Lattice**.

---

## 6. Traps & distractors

1. **"Use VPC peering to give VPC B internet access through VPC A's NAT/IGW."** Wrong: there's no edge-to-edge routing. The same goes for **VPN/DX and gateway endpoints** through a peer.
2. **"Peer A↔B and B↔C so A can reach C."** Wrong: peering is non-transitive.
3. **"Peering or TGW between VPCs with overlapping CIDRs."** Neither works (TGW silently won't propagate the overlapping route). Use PrivateLink, private NAT or Lattice.
4. **"Access S3 from on-prem through the VPC's gateway endpoint."** Not possible. Use an S3 interface endpoint or a public VIF.
5. **"Static VPN routes as DX backup on a TGW."** Static beats propagated, so traffic would prefer the VPN over DX. Use BGP VPN.
6. **"VGW with ECMP across multiple VPN connections for 5 Gbps."** A VGW doesn't support ECMP. Use TGW, or 5 Gbps Large Bandwidth Tunnels on TGW.
7. **"Accelerated VPN on a VGW."** It's TGW only, and can't be enabled on an existing connection.
8. **"MACsec on a hosted 1 Gbps connection."** MACsec needs dedicated 10/100/400G.
9. **"A LAG across two DX locations for resiliency."** LAG members must be at the same location. Use separate connections at separate locations.
10. **"Single DX connection = highly available."** One connection is a single point of failure. You need at least two (dev/test model), and two locations for HA.
11. **"Direct Connect gateway lets VPC A talk to VPC B" or "lets DC1 talk to DC2."** No transit between associations, and no site-to-site without **SiteLink**.
12. **"Centralized inspection without appliance mode."** It causes asymmetric routing and dropped flows.
13. **"Security groups on a NAT gateway"** (not supported) or **"SG deny rules"** (SGs are allow-only, use NACLs).
14. **"One NAT gateway for all AZs to save money."** It's an AZ single point of failure and adds cross-AZ data charges. (The regional NAT gateway mode solves both, but not for private NAT.)
15. **"TGW resolves private hosted zones across attached VPCs."** It doesn't. Use Resolver endpoints/rules or PHZ associations.
16. **"Interface endpoint for DynamoDB/S3 is always better."** Gateway endpoints are **free**. Use interface endpoints only when on-prem, cross-Region or TGW-connected access is required.
17. **"Jumbo frames end-to-end through a TGW at 9001."** TGW supports 8500, and VPN 1446.
18. **"A public VIF gives internet access."** It only reaches AWS public prefixes.
19. **"Exceed 100 prefixes on a private VIF."** The BGP session goes down. Summarize, or raise the limit with prefix controls.
20. **"Use Reachability Analyzer for packet capture"** (it's static analysis) or **"Flow Logs show payload"** (they don't).
21. **"Network Firewall blocks SQL injection on the ALB."** That's AWS WAF's job (L7 HTTP). Network Firewall can do IPS signatures, but the managed, intended answer for web-app attacks is WAF.
22. **"Cloud WAN is always better than TGW."** For a single Region with simple segmentation, TGW is simpler and cheaper.

---

## 7. Professional architect focus

- **IP plan first.** Overlap is the most expensive mistake to undo. Reserve non-overlapping RFC 1918 space per Region and environment, adopt **IPAM** with allocation rules, and plan for **IPv6 dual-stack** to escape IPv4 scarcity and public-IPv4 charges. For M&A, budget for PrivateLink, private NAT or re-IP.
- **Account and network ownership model:** a **Network account** owns the TGW/Cloud WAN, DXGW, egress/inspection VPCs and Resolver endpoints, and shares through **RAM** (TGW, subnets, prefix lists, Resolver rules, Route 53 Profiles, Cloud WAN core network). Use **SCPs** to stop workload accounts creating IGWs, peering or VPNs that bypass inspection (e.g., deny `ec2:CreateInternetGateway`, `ec2:AttachInternetGateway`, `ec2:CreateVpcPeeringConnection`). VPC Block Public Access is a newer alternative.
- **Blast radius vs cost:** centralizing egress, endpoints and inspection reduces fixed costs and operations, but **adds per-GB TGW charges and a shared failure domain**. Model traffic volumes before choosing. Hybrid answers (central for most VPCs, local NAT/endpoints for heavy hitters) are often right.
- **AZ independence:** keep NAT, firewall endpoints and TGW attachments **in every AZ**, and route per AZ. Appliance mode trades AZ locality for symmetry, so understand the cross-AZ cost.
- **Hybrid resilience is a business decision:** map RTO and availability targets to DX resiliency models. Dual DX locations cost more than a VPN backup, but a VPN backup may not carry peak load (1.25 Gbps per tunnel). Test failover (DX Failover Test), use BFD, and document the BGP policy (communities, prepends) on both sides.
- **Encryption expectations:** clarify whether "encrypted in transit" is satisfied by TLS at the application layer. Network-layer encryption over DX (MACsec or IPsec) adds cost and complexity, and may reduce throughput with IPsec.
- **DNS is the hidden dependency** in every hybrid design. Centralize the Resolver endpoints and size them (QPS per ENI). Avoid circular forwarding (on-prem → AWS → on-prem loops) and decide on fail-open vs fail-closed for DNS Firewall.
- **Observability baseline:** VPC and TGW Flow Logs to a central log-archive bucket, Athena tables, Network Access Analyzer scopes for compliance, and CloudWatch alarms on DX ConnectionState / VPN TunnelState, NAT ErrorPortAllocation and firewall drop metrics.
- **Stakeholder questions to raise:** expected growth in VPCs, Regions and bandwidth. Partner IP allow-listing needs (static egress IPs). Regulatory inspection mandates (east-west?). On-prem router capabilities (BGP, BFD, MACsec, ECMP). Lead times for DX circuits. Data-transfer budget.

---

## 8. Skills checklist

- [ ] I can design a TGW route-table scheme (association vs propagation, blackholes) that isolates prod/dev and shares services and on-prem selectively.
- [ ] I can explain TGW and VPC route priority, and why static VPN routes override DX on a TGW.
- [ ] I can choose between peering, TGW, Cloud WAN, PrivateLink, Lattice and VPC sharing from constraints (scale, overlap, Regions, cost).
- [ ] I can solve overlapping-CIDR scenarios three ways (PrivateLink, private NAT GW, Lattice).
- [ ] I can draw centralized egress and centralized inspection VPCs, including appliance mode and return routes.
- [ ] I know when to use Network Firewall vs GWLB + appliances vs DNS Firewall vs WAF, and how Firewall Manager enforces them org-wide.
- [ ] I can state DX connection types, speeds, VIF types and limits (50+4 VIFs, 1 VIF hosted, 100 prefixes, 200 TGW prefixes, 6 TGWs/DXGW, 20 VGWs/DXGW, 30 VIFs/DXGW).
- [ ] I can map availability targets to DX resiliency models (dev/test, high 99.9%, maximum 99.99%) and use BGP communities, prepending, more-specifics and BFD.
- [ ] I can pick the right DX encryption (MACsec vs VPN over public VIF vs private IP VPN).
- [ ] I know VPN limits (2 tunnels, 1.25 Gbps standard / 5 Gbps LBT, ECMP only on TGW with BGP, accelerated VPN TGW-only, MTU 1446).
- [ ] I can design centralized hybrid DNS with Resolver endpoints, RAM-shared rules, cross-account PHZ association and Route 53 Profiles.
- [ ] I know which monitoring tool answers which question (Flow Logs, Traffic Mirroring, Reachability Analyzer, Network Access Analyzer, Network Manager).
- [ ] I can recite the MTU per path and explain per-flow bandwidth limits and placement groups.
- [ ] I can estimate and reduce network data-transfer costs (gateway endpoints, per-AZ NAT, peering for heavy pairs, DX DTO, VPC sharing).

---

## 9. Practice questions

> Original SAP-C02-style questions written for this guide (not real exam questions).

**Q1.** A financial services company runs 140 VPCs across 60 accounts in us-east-1, all attached to a single transit gateway owned by a central network account. The TGW uses its default route table with auto-association and auto-propagation. An audit finding says development workloads can reach production databases. The company needs: production and development VPCs must not communicate; both must reach a shared-services VPC (Active Directory, CI/CD); only production and shared services may reach the on-premises data center through the existing Direct Connect gateway attachment. The solution must scale as new VPCs are added, with minimal ongoing effort. Which solution meets these requirements?

- A. Keep the default route table and add blackhole routes for every development CIDR in it, then update security groups in production VPCs to deny development CIDRs.
- B. Create TGW route tables for prod, dev, shared and on-prem. Associate each attachment with the route table for its type. Propagate prod attachments to the shared and on-prem tables, dev attachments to the shared table only, the shared-services attachment to the prod, dev and on-prem tables, and the DXGW attachment to the prod and shared tables. Disable default association and propagation.
- C. Create a second transit gateway for development VPCs, peer it with the production transit gateway, and use NACLs in the shared-services VPC to filter traffic.
- D. Replace the transit gateway with VPC peering between each workload VPC and the shared-services VPC, and attach a VGW to each production VPC for on-premises access.

**Q2.** A SaaS company hosts a multi-tenant API in its own VPC (10.0.0.0/16) behind EC2 instances in an Auto Scaling group. More than 400 enterprise customers want private access from their own VPCs, and many of them also use 10.0.0.0/16. Customers must not be able to reach anything in the provider VPC except the API, and traffic must not traverse the internet. Some customers want to reach the API from their on-premises networks over their existing Direct Connect links to their own VPCs. Which solution should the SaaS company implement?

- A. Create a transit gateway, share it with every customer through AWS RAM, and have each customer attach their VPC.
- B. Put the API behind a Network Load Balancer, create a VPC endpoint service, allow-list customer AWS account principals with acceptance required, and have customers create interface VPC endpoints in their VPCs.
- C. Create VPC peering connections to each customer VPC and use security groups to restrict access to the API port.
- D. Put the API behind an Application Load Balancer with AWS WAF, publish it through Amazon CloudFront, and restrict access with IP allow-lists per customer.

**Q3.** A healthcare company is ordering AWS Direct Connect to connect its two data centers to VPCs in us-east-1 and us-west-2. The security policy says all traffic between on-premises and AWS must be encrypted at the network layer, and that the design must survive the complete loss of a Direct Connect location. The company needs 10 Gbps of capacity and expects to grow to 100 Gbps. Its edge routers support MACsec. Which combination of actions will meet these requirements? **(Select TWO.)**

- A. Order 10 Gbps dedicated connections at two different Direct Connect locations (two connections per location), terminating on separate devices.
- B. Order four 10 Gbps hosted connections from a Direct Connect Partner at a single Direct Connect location and bundle them in a LAG.
- C. Enable MACsec on the dedicated connections by associating a CKN/CAK pair, and configure the routers in must_encrypt mode.
- D. Enable MACsec on the Direct Connect gateway so that traffic is encrypted end to end to the VPCs.
- E. Create public VIFs and rely on TLS on every application to satisfy the network-layer encryption requirement.

**Q4.** A company built a centralized inspection VPC containing third-party stateful firewalls behind a Gateway Load Balancer in two Availability Zones. All spoke VPCs route 0.0.0.0/0 to a transit gateway, whose spoke route table sends all traffic to the inspection VPC attachment. Traffic between instances in the same AZ works, but many connections between a spoke instance in AZ-a and a spoke instance in AZ-b time out. Firewall logs show SYN packets on one appliance and SYN-ACK packets on a different appliance. What should the solutions architect do to fix the issue with the least operational effort?

- A. Enable appliance mode on the transit gateway VPC attachment for the inspection VPC.
- B. Enable cross-zone load balancing on the Gateway Load Balancer and change flow stickiness to 2-tuple.
- C. Deploy a separate transit gateway for each Availability Zone and attach each one to the inspection VPC.
- D. Replace the Gateway Load Balancer with a Network Load Balancer that has client IP preservation enabled.

**Q5.** An enterprise has 300 VPCs across 80 accounts in one Region, connected through a transit gateway to an on-premises data center over Direct Connect. On-premises DNS servers are authoritative for `corp.example.com`. Each application team creates Route 53 private hosted zones under `aws.example.com` in its own account. Requirements: all VPCs must resolve `corp.example.com`; on-premises clients must resolve records in the application teams' private hosted zones; the number of Resolver endpoints to manage must be minimized. Which combination of steps meets these requirements? **(Select TWO.)**

- A. Create Route 53 Resolver inbound and outbound endpoints in a VPC in a central shared-services account. Create a forwarding rule for `corp.example.com` targeting the on-premises DNS servers, share the rule with the organization through AWS RAM, and associate it with every VPC.
- B. Create Resolver outbound endpoints in every VPC and a forwarding rule in each account.
- C. Associate each application team's private hosted zone with the shared-services VPC by creating a VPC association authorization in the zone owner's account and associating the VPC from the shared-services account. Configure on-premises DNS to conditionally forward `aws.example.com` to the inbound endpoint IP addresses.
- D. Configure the transit gateway to enable DNS support so on-premises servers can query the Amazon-provided DNS server of each VPC directly.
- E. Replace the private hosted zones with public hosted zones that use split-horizon records restricted by source IP.

**Q6.** A media company runs 25 VPCs, each with three private subnets in three AZs and a single NAT gateway in AZ-a. Monthly costs show high NAT gateway data-processing charges and inter-AZ data transfer charges. Most outbound traffic is from EC2 instances reading and writing large objects in Amazon S3 in the same Region, plus calls to DynamoDB. A smaller amount goes to third-party APIs on the internet. An AZ-a outage last quarter cut off internet access for all instances. Which combination of changes reduces cost and improves resilience? **(Select TWO.)**

- A. Create gateway VPC endpoints for Amazon S3 and Amazon DynamoDB in each VPC and add them to the private subnets' route tables.
- B. Create interface VPC endpoints for Amazon S3 and Amazon DynamoDB in every AZ of each VPC.
- C. Deploy a NAT gateway in each AZ (or use a regional-mode NAT gateway) and route each private subnet to NAT in its own AZ.
- D. Replace the NAT gateways with NAT instances on Spot Instances to cut hourly charges.
- E. Move all instances into AZ-a to eliminate inter-AZ data transfer.

**Q7.** A retail company connects its data center to a transit gateway in eu-west-1 through a 10 Gbps Direct Connect connection (transit VIF → Direct Connect gateway → TGW). As a backup, it created a Site-to-Site VPN attachment on the same transit gateway with **static routes** for the on-premises prefixes 172.16.0.0/16 and 172.17.0.0/16. Since the VPN was added, VPC-to-on-premises throughput has dropped to about 1.2 Gbps, and network engineers see the traffic leaving AWS over the VPN tunnels even though the DX connection is up. What should the solutions architect do so that traffic uses Direct Connect while it is available and fails over to the VPN automatically?

- A. Add AS_PATH prepending to the routes advertised over Direct Connect so the transit gateway prefers DX.
- B. Recreate the VPN connection with dynamic (BGP) routing, advertise the same prefixes over BGP, and remove the static routes so the transit gateway prefers the Direct Connect gateway-propagated routes.
- C. Advertise 0.0.0.0/0 over the VPN and the specific /16 prefixes over DX.
- D. Enable ECMP on the transit gateway so traffic is load-balanced across DX and VPN.

**Q8.** A global manufacturer is expanding to eight AWS Regions with VPCs in more than 200 accounts, plus 40 branch sites connected through SD-WAN appliances. The network team wants to define production, development and partner segments once and have them applied consistently in every Region. VPCs should join the right segment automatically based on an AWS tag. Inter-Region routing should be dynamic, and traffic between the partner and production segments must pass through a firewall. The team wants to minimize per-Region configuration. Which solution best meets these requirements?

- A. Deploy a transit gateway in each Region, create matching route tables in each, peer all transit gateways in a full mesh, and maintain static routes with a Lambda function triggered by tag changes.
- B. Deploy AWS Cloud WAN with a core network policy that defines edge locations in the eight Regions, the three segments, attachment policies mapping a `segment` tag to segments, and a service-insertion (send-via) action through a network function group for partner-to-production traffic. Attach the SD-WAN appliances with Connect attachments.
- C. Use VPC peering between all VPCs that need to communicate and AWS Direct Connect SiteLink for branches.
- D. Use VPC Lattice service networks per segment and share them across Regions with AWS RAM.

**Q9.** A security team at a large company has three requirements for its multi-account AWS network: (1) continuously identify any network path that would allow traffic from an internet gateway to reach subnets tagged `tier=database` in any account; (2) capture full packet payloads from a set of suspicious EC2 instances and send them to an IDS appliance fleet for analysis; (3) let operations engineers quickly find which route table, security group or NACL is blocking connectivity between two specific instances after a change. Which combination of AWS capabilities should be used? **(Select THREE.)**

- A. Amazon VPC Network Access Analyzer with a Network Access Scope that matches paths from internet gateways to the database subnets.
- B. VPC Traffic Mirroring from the instances' ENIs to a Network Load Balancer or Gateway Load Balancer endpoint in front of the IDS fleet.
- C. VPC Reachability Analyzer path analysis between the two instances.
- D. VPC Flow Logs with the `pkt-srcaddr` field to capture packet payloads.
- E. AWS Config conformance packs to send packet captures to the IDS.
- F. Transit gateway flow logs to identify which security group blocked the traffic.

**Q10.** A company has 350 VPCs across many accounts in two Regions, all connected with transit gateways. A new regulation requires that all internet-bound traffic from every VPC be restricted to an approved list of fully qualified domain names (for example, `*.amazonaws.com`, `api.partner.com`), that non-approved HTTPS connections be blocked based on the TLS SNI, and that controls apply automatically to newly created VPCs. The company wants a managed AWS solution with the least operational overhead and no third-party appliances. Which solution should the solutions architect recommend?

- A. Deploy AWS Network Firewall centrally for each Region (an inspection/egress VPC with appliance mode, or the native transit gateway network-function attachment) with a stateful domain-list rule group allowing only the approved FQDNs (HTTP Host and TLS SNI), route all spoke 0.0.0.0/0 traffic through it to centralized NAT gateways, and use AWS Firewall Manager to manage the policy across the organization.
- B. Create Route 53 Resolver DNS Firewall rules that allow only the approved domains and block everything else, and associate them with every VPC.
- C. Use security groups with outbound rules referencing the approved domain names in each VPC.
- D. Deploy squid proxy instances in an Auto Scaling group in each VPC and configure all applications to use the proxy.

---

### Answers & explanations

<details><summary>Q1 — Show answer</summary>

**Answer: B.**
- **Why B:** TGW segmentation works through **association** (which table an attachment's ingress traffic uses) and **propagation** (which tables learn routes to the attachment). The dev route table has no routes to prod (and the prod table none to dev), so they can't communicate. Both reach shared services, and only prod and shared reach the DXGW. Disabling default association and propagation stops new attachments joining the flat table. New VPCs only need an association plus propagations, which is easy to automate.
- **A:** Blackholing every dev CIDR in a shared table doesn't scale (every new VPC needs edits), and SGs can't contain deny rules.
- **C:** A second TGW adds peering with static routes, cost and complexity. NACL filtering in shared services doesn't stop prod↔dev traffic.
- **D:** 140 peerings plus a VGW (and DX association) per production VPC adds heavy operational overhead, loses central routing control, and runs into DXGW limits (20 VGWs per DXGW). It also abandons the existing TGW investment.
- **Reference:** https://docs.aws.amazon.com/vpc/latest/tgw/how-transit-gateways-work.html

</details>

<details><summary>Q2 — Show answer</summary>

**Answer: B.**
- **Why B:** **PrivateLink** (NLB-backed endpoint service + interface endpoints) gives **service-level, unidirectional** access, **works with overlapping CIDRs** (no routing between VPCs), keeps traffic on the AWS network, and scales to thousands of consumers with principal allow-listing and acceptance. Interface endpoints are reachable from customers' on-prem networks over their DX/VPN into their own VPC.
- **A:** TGW can't route overlapping CIDRs and would expose network-level reachability between tenants and the provider.
- **C:** Peering fails with overlapping CIDRs, is limited to 125 peerings per VPC, and gives network-level access.
- **D:** CloudFront is internet-facing, so it violates "must not traverse the internet".
- **Reference:** https://docs.aws.amazon.com/vpc/latest/privatelink/privatelink-share-your-services.html

</details>

<details><summary>Q3 — Show answer</summary>

**Answer: A and C.**
- **Why A:** Surviving the **loss of a whole DX location** requires connections in **at least two locations**. Two connections per location on separate devices is the **maximum resiliency** model (99.99% SLA). Dedicated connections are required for MACsec and allow later 100G ports.
- **Why C:** **MACsec** gives line-rate L2 encryption on **dedicated 10/100/400 Gbps** connections. `must_encrypt` ensures no traffic flows unencrypted (the default is `should_encrypt`, which can fall back to cleartext).
- **B:** Hosted connections don't support MACsec or LAGs, and a single location doesn't survive a location failure.
- **D:** MACsec is configured on connections or LAGs (hop-by-hop between the router and the DX device), not on a Direct Connect gateway.
- **E:** Application TLS isn't network-layer encryption, and public VIFs reach public endpoints, not the VPCs.
- **References:** https://docs.aws.amazon.com/directconnect/latest/UserGuide/MACsec.html · https://docs.aws.amazon.com/directconnect/latest/UserGuide/resilency_toolkit.html

</details>

<details><summary>Q4 — Show answer</summary>

**Answer: A.**
- **Why A:** Without **appliance mode**, the TGW keeps traffic in the **originating AZ**. The request (from AZ-a) goes to the AZ-a appliance and the response (from AZ-b) goes to the AZ-b appliance, so the stateful firewall drops it. Appliance mode makes the TGW pick **one AZ ENI per flow (flow hash) for both directions** in the inspection VPC. It's a single attachment setting.
- **B:** GWLB stickiness works within the GWLB, but the TGW is sending the two directions to **different GWLB endpoints in different AZs**. Cross-zone or 2-tuple doesn't fix TGW AZ selection.
- **C:** Multiple TGWs attached to the same appliance VPC *break* flow stickiness (TGWs don't share flow state), and add cost.
- **D:** An NLB isn't a transparent L3 gateway for appliances and doesn't solve asymmetric AZ routing.
- **Reference:** https://docs.aws.amazon.com/vpc/latest/tgw/tgw-vpc-attachments.html (Appliance mode)

</details>

<details><summary>Q5 — Show answer</summary>

**Answer: A and C.**
- **Why A:** One pair of **inbound/outbound endpoints in a central account** plus a **forwarding rule shared via RAM** and associated with all VPCs lets every VPC resolve `corp.example.com` through the central outbound endpoint (reachable over the TGW). This minimizes the number of endpoints.
- **Why C:** The inbound endpoint answers with what the **shared-services VPC's Resolver** can see. Associating every team's PHZ with that VPC (**cross-account association authorization + association**) and conditionally forwarding `aws.example.com` from on-prem to the inbound endpoint lets on-prem resolve all PHZs. Route 53 Profiles is an alternative for large-scale association.
- **B:** Endpoints in every VPC multiply cost and management, which contradicts the requirement.
- **D:** A TGW doesn't resolve PHZs, and the VPC's +2 resolver isn't reachable from on-prem.
- **E:** Public zones expose internal names. Route 53 has no source-IP-restricted split horizon of that kind.
- **References:** https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/resolver.html · https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/hosted-zone-private-associate-vpcs-different-accounts.html

</details>

<details><summary>Q6 — Show answer</summary>

**Answer: A and C.**
- **Why A:** **Gateway endpoints** for S3 and DynamoDB are **free** and remove that traffic from the NAT gateway (no per-GB NAT processing) and from cross-AZ hops to the single NAT.
- **Why C:** A **NAT gateway per AZ** with per-AZ routing (or a **regional NAT gateway**, which spans AZs automatically) removes the AZ-a single point of failure and the inter-AZ data transfer to the NAT.
- **B:** Interface endpoints work but cost per AZ-hour plus per GB. They're unnecessary when gateway endpoints meet the need, and DynamoDB interface endpoints are mainly for on-prem/cross-network access.
- **D:** NAT instances on Spot add operational burden and interruption risk, and they don't fix the S3 traffic path.
- **E:** Concentrating everything in one AZ destroys resilience.
- **References:** https://docs.aws.amazon.com/vpc/latest/privatelink/gateway-endpoints.html · https://docs.aws.amazon.com/vpc/latest/userguide/nat-gateway-basics.html

</details>

<details><summary>Q7 — Show answer</summary>

**Answer: B.**
- **Why B:** In TGW route evaluation, for the same prefix, **static routes (including static VPN routes) have the highest priority**, ahead of Direct Connect gateway-propagated routes. That's why traffic prefers the VPN. With **BGP-propagated VPN routes**, the TGW prefers **DXGW-propagated over VPN-propagated** routes, so DX is active and the VPN takes over automatically when DX routes are withdrawn. On-prem should also prefer DX-learned routes for symmetric return traffic.
- **A:** AS_PATH only matters between routes of the same attachment type and doesn't override a static route. Prepending DX would also make DX *less* preferred.
- **C:** A default route over the VPN doesn't remove the static /16 routes, which still win over DX for those prefixes.
- **D:** The TGW doesn't do ECMP across different attachment types (DX vs VPN).
- **Reference:** https://docs.aws.amazon.com/vpc/latest/tgw/how-transit-gateways-work.html (Route evaluation order)

</details>

<details><summary>Q8 — Show answer</summary>

**Answer: B.**
- **Why B:** **Cloud WAN** provides **global segments** defined once in a **declarative core network policy**, CNEs in each listed Region with **automatic full-mesh dynamic routing**, **tag-based attachment policies** for automatic segment membership across accounts (shared via RAM), **service insertion** to force partner↔prod traffic through firewalls, and **Connect attachments** for SD-WAN. This minimizes per-Region configuration.
- **A:** It works, but needs per-Region route tables, static routes over a TGW peering mesh (28 peerings for 8 Regions) and custom automation, which is high operational overhead.
- **C:** Peering doesn't scale, isn't transitive, and has no segmentation or firewall insertion. SiteLink covers DX-to-DX site traffic, not SD-WAN branches over the internet.
- **D:** Lattice is for application-layer service-to-service connectivity, not L3 WAN segmentation, and service networks are Regional.
- **Reference:** https://docs.aws.amazon.com/network-manager/latest/cloudwan/what-is-cloudwan.html

</details>

<details><summary>Q9 — Show answer</summary>

**Answer: A, B and C.**
- **A:** **Network Access Analyzer** evaluates **Network Access Scopes** to find unintended paths (IGW → database subnets) across accounts. It suits continuous compliance checks.
- **B:** **Traffic Mirroring** copies **full packets** (VXLAN-encapsulated) from ENIs to an NLB, GWLB endpoint or ENI target such as an IDS fleet.
- **C:** **Reachability Analyzer** performs static path analysis between two resources and identifies the **blocking component** (route table, SG, NACL).
- **D:** Flow logs carry **metadata only**. `pkt-srcaddr` is the original source IP, not the payload.
- **E:** AWS Config evaluates resource configuration and can't capture packets.
- **F:** TGW flow logs show flows through the TGW but don't identify which SG/NACL blocked traffic.
- **References:** https://docs.aws.amazon.com/vpc/latest/network-access-analyzer/what-is-network-access-analyzer.html · https://docs.aws.amazon.com/vpc/latest/mirroring/what-is-traffic-mirroring.html · https://docs.aws.amazon.com/vpc/latest/reachability/what-is-reachability-analyzer.html

</details>

<details><summary>Q10 — Show answer</summary>

**Answer: A.**
- **Why A:** **AWS Network Firewall** stateful **domain list** rules filter on **HTTP Host and TLS SNI**, which meets "block non-approved HTTPS by SNI". It's managed (no third-party appliances), deploys centrally per Region (inspection VPC with appliance mode, or the native TGW attachment), and **Firewall Manager** applies policies across the organization, including new accounts and VPCs.
- **B:** DNS Firewall controls **DNS resolution** through the VPC Resolver only. Clients that connect by IP or use other resolvers bypass it, and it can't inspect TLS SNI. It's a good complement but doesn't meet the requirement alone.
- **C:** Security groups can't reference domain names, only CIDRs, prefix lists and SGs.
- **D:** Self-managed proxies in 350 VPCs are high operational overhead and need application changes.
- **References:** https://docs.aws.amazon.com/network-firewall/latest/developerguide/what-is-aws-network-firewall.html · https://docs.aws.amazon.com/vpc/latest/tgw/tgw-nf-fw.html

</details>

---

## 10. References

- Whitepaper — Building a Scalable and Secure Multi-VPC AWS Network Infrastructure: https://docs.aws.amazon.com/whitepapers/latest/building-scalable-secure-multi-vpc-network-infrastructure/welcome.html
- Whitepaper — Amazon VPC Connectivity Options: https://docs.aws.amazon.com/whitepapers/latest/aws-vpc-connectivity-options/introduction.html
- Amazon VPC User Guide: https://docs.aws.amazon.com/vpc/latest/userguide/what-is-amazon-vpc.html
- Amazon VPC quotas: https://docs.aws.amazon.com/vpc/latest/userguide/amazon-vpc-limits.html
- Route priority: https://docs.aws.amazon.com/vpc/latest/userguide/route-tables-priority.html
- NAT gateways (incl. regional NAT gateways): https://docs.aws.amazon.com/vpc/latest/userguide/vpc-nat-gateway.html
- VPC sharing: https://docs.aws.amazon.com/vpc/latest/userguide/vpc-sharing.html
- Amazon VPC IP Address Manager: https://docs.aws.amazon.com/vpc/latest/ipam/what-it-is-ipam.html
- VPC peering guide: https://docs.aws.amazon.com/vpc/latest/peering/what-is-vpc-peering.html
- AWS Transit Gateway guide: https://docs.aws.amazon.com/vpc/latest/tgw/what-is-transit-gateway.html
- Transit Gateway quotas: https://docs.aws.amazon.com/vpc/latest/tgw/transit-gateway-quotas.html
- Transit Gateway pricing: https://aws.amazon.com/transit-gateway/pricing/
- AWS Cloud WAN: https://docs.aws.amazon.com/network-manager/latest/cloudwan/what-is-cloudwan.html
- AWS PrivateLink guide: https://docs.aws.amazon.com/vpc/latest/privatelink/what-is-privatelink.html
- PrivateLink quotas: https://docs.aws.amazon.com/vpc/latest/privatelink/vpc-limits-endpoints.html
- Gateway endpoints: https://docs.aws.amazon.com/vpc/latest/privatelink/gateway-endpoints.html
- Gateway Load Balancer: https://docs.aws.amazon.com/elasticloadbalancing/latest/gateway/introduction.html
- AWS Network Firewall: https://docs.aws.amazon.com/network-firewall/latest/developerguide/what-is-aws-network-firewall.html
- Transit Gateway network function attachments: https://docs.aws.amazon.com/vpc/latest/tgw/tgw-nf-fw.html
- AWS Firewall Manager: https://docs.aws.amazon.com/waf/latest/developerguide/fms-chapter.html
- AWS Direct Connect User Guide: https://docs.aws.amazon.com/directconnect/latest/UserGuide/Welcome.html
- Direct Connect quotas: https://docs.aws.amazon.com/directconnect/latest/UserGuide/limits.html
- Direct Connect gateways: https://docs.aws.amazon.com/directconnect/latest/UserGuide/direct-connect-gateways-intro.html
- Direct Connect routing policies and BGP communities: https://docs.aws.amazon.com/directconnect/latest/UserGuide/routing-and-bgp.html
- Direct Connect Resiliency Toolkit: https://docs.aws.amazon.com/directconnect/latest/UserGuide/resilency_toolkit.html
- MACsec on Direct Connect: https://docs.aws.amazon.com/directconnect/latest/UserGuide/MACsec.html
- Whitepaper — Hybrid Connectivity: https://docs.aws.amazon.com/whitepapers/latest/hybrid-connectivity/hybrid-connectivity.html
- AWS Site-to-Site VPN quotas: https://docs.aws.amazon.com/vpn/latest/s2svpn/vpn-limits.html
- Accelerated Site-to-Site VPN: https://docs.aws.amazon.com/vpn/latest/s2svpn/accelerated-vpn.html
- Private IP VPN over Direct Connect: https://docs.aws.amazon.com/vpn/latest/s2svpn/private-ip-dx.html
- VPN Concentrators: https://docs.aws.amazon.com/vpn/latest/s2svpn/vpn-concentrator.html
- AWS Client VPN: https://docs.aws.amazon.com/vpn/latest/clientvpn-admin/what-is.html
- Route 53 VPC Resolver: https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/resolver.html
- Route 53 Profiles: https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/profiles.html
- Route 53 quotas: https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/DNSLimitations.html
- VPC Flow Logs: https://docs.aws.amazon.com/vpc/latest/userguide/flow-logs.html
- Traffic Mirroring: https://docs.aws.amazon.com/vpc/latest/mirroring/what-is-traffic-mirroring.html
- Reachability Analyzer: https://docs.aws.amazon.com/vpc/latest/reachability/what-is-reachability-analyzer.html
- Network Access Analyzer: https://docs.aws.amazon.com/vpc/latest/network-access-analyzer/what-is-network-access-analyzer.html
- EC2 network MTU: https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/network_mtu.html
- Placement groups: https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/placement-groups.html
- Amazon VPC Lattice: https://docs.aws.amazon.com/vpc-lattice/latest/ug/what-is-vpc-lattice.html
