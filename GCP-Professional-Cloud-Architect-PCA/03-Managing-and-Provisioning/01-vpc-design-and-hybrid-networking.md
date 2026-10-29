# 03/01 · VPC Design, Hybrid and Multicloud Networking

**Exam guide:** 2.1 (configuring network topologies), 1.3 (cloud-native networking: VPC, peering, firewalls, routing, Shared VPC, Private Service Connect). **Principles:** P1, P2, P6, P7, P14.

Networking is one of the densest areas of the exam. Most questions reduce to five decisions: **VPC layout**, **how VPCs connect**, **how workloads reach Google services privately**, **how on-premises and other clouds connect**, and **which controls filter traffic**.

---

## 1. VPC fundamentals that drive answers

| Fact | Consequence |
|---|---|
| A **VPC network is global**; **subnets are regional** | One VPC can span all regions; cross-region VM traffic uses internal IPs over Google's backbone, with no VPN needed |
| **Custom-mode** VPCs (you define subnets) vs auto-mode (one subnet per region, fixed ranges) | Use **custom mode** in production to control IP planning and avoid overlaps |
| Firewall rules are **stateful**; implied rules **deny all ingress** and **allow all egress** | Open only what's needed; consider egress restrictions for sensitive workloads |
| Routes: system (subnet, default internet), **static**, **dynamic** (Cloud Router BGP) | **Dynamic routing mode**: *regional* (Cloud Router advertises and learns only in its region) vs *global* (learned routes usable in all regions). Global is needed for some HA hybrid designs |
| Projects own VPCs; quotas apply per project/network | Large estates use **Shared VPC** or hub-and-spoke |
| IPv6 dual-stack subnets are supported | Internal or external IPv6 when required |
| **Network Service Tiers**: Premium (default; Google backbone, global LB) vs Standard (enters near the region; cheaper; regional only) | Premium for global performance; Standard only when cost matters more than latency and global LB isn't needed |

---

## 2. Connecting VPCs: Shared VPC vs peering vs PSC vs NCC

| Mechanism | What it gives | Transitive? | Overlapping IPs? | Admin model | Choose when |
|---|---|---|---|---|---|
| **Shared VPC** | One VPC in a **host project** used by many **service projects** | N/A (single network) | N/A | Central network team owns subnets, firewall and routes; app teams deploy in service projects with **Network User** on specific subnets | **Same organization**, centralized network governance (the default enterprise answer) |
| **VPC Network Peering** | Private connectivity between two VPCs (any project or organization) | **No** (A↔B, B↔C doesn't give A↔C) | **Not allowed** | Each side administers its own network | A few VPCs, low latency, no overlapping ranges, separate admin domains |
| **Private Service Connect (PSC)** | A consumer reaches a **specific service** via an internal IP endpoint in its own VPC | Service-level, not network-level | **Allowed** (endpoints use consumer IPs) | Producer publishes a **service attachment**; consumer creates an endpoint | SaaS/B2B, managed services, cross-organization access to one service, overlapping IPs |
| **Network Connectivity Center (NCC)** | **Hub-and-spoke** for VPC spokes and hybrid spokes (VPN, Interconnect, router appliances) | **Yes**, through the hub (as configured) | Private NAT helps with overlaps | Central hub managed by the network team | Many VPCs and sites; replace peering meshes; site-to-site over Google's backbone |
| Cloud VPN between VPCs | Encrypted tunnels | Via Cloud Router | No | — | Rarely the best answer inside Google Cloud |

**Shared VPC details tested**

* The org-level **Shared VPC Admin** role enables host projects and attaches service projects.
* Grant **Compute Network User** at the **subnet** level to limit which subnets a team can use.
* Resources in service projects (VMs, GKE clusters, Cloud Run with Direct VPC egress) use the host's subnets.
* Typical layout: one host project per environment (prod / non-prod), connected to on-premises via Interconnect in the host.

---

## 3. Reaching Google services and managed services privately

| Need | Mechanism | Notes |
|---|---|---|
| VMs without external IPs call Google APIs (Cloud Storage, BigQuery…) | **Private Google Access** (subnet setting) | Uses Google's default domains or private VIPs |
| Force API traffic to VPC-SC-compatible endpoints | `restricted.googleapis.com` VIP (199.36.153.4/30) + DNS | Used with **VPC Service Controls** |
| Private VIP for all supported APIs | `private.googleapis.com` (199.36.153.8/30) | |
| Use your own internal IP for Google APIs (and reach it from on-premises) | **PSC endpoint for Google APIs** (`all-apis` or `vpc-sc` bundle) | Clean hybrid design; advertise the IP to on-premises |
| On-premises hosts reach Google APIs privately | Private Google Access for on-premises hosts (VIP routes over Interconnect/VPN) or a PSC endpoint | Advertise the routes via Cloud Router |
| Managed services with private IPs (Cloud SQL, Memorystore, AlloyDB, etc.) | **Private services access** (peering-based allocated range) or **PSC** (where supported) | PSA uses a peering, so its routes aren't transitive to on-premises unless you export custom routes |
| Serverless (Cloud Run) reaching private IPs in a VPC | **Direct VPC egress** or Serverless VPC Access connector | Direct VPC egress is the newer, simpler option |
| Outbound internet for private instances | **Cloud NAT** (regional, managed, no VMs) | Public NAT; **Private NAT** for VPC-to-VPC with overlapping ranges via NCC |
| Admin SSH/RDP without public IPs or bastions | **IAP TCP forwarding** | Firewall allow from 35.235.240.0/20 to port 22/3389 |

---

## 4. Hybrid connectivity

### 4.1 The options

| Option | Bandwidth | Encryption | SLA | Lead time | Choose when |
|---|---|---|---|---|---|
| **HA VPN** | ~3 Gbps per tunnel (scale with multiple tunnels) | IPsec | **99.99%** with two interfaces/tunnels correctly configured | Minutes–hours | Quick start, moderate bandwidth, interim or backup link, encryption required over the internet |
| Classic VPN | Similar per tunnel | IPsec | 99.9% | — | Legacy; prefer HA VPN |
| **Dedicated Interconnect** | 10 / 100 / **400 Gbps** circuits (bundle multiple); VLAN attachments 50 Mbps–400 Gbps | Not encrypted by default; add **MACsec** or **HA VPN over Interconnect** | 99.9% or 99.99% depending on topology | Weeks (cross-connect at a colocation facility) | High, sustained bandwidth; you're (or can be) in a supported colocation facility |
| **Partner Interconnect** | VLAN attachments **50 Mbps–50 Gbps** via a service provider (L2 or L3) | As above | 99.9% / 99.99% with provider redundancy | Days–weeks | Not in a Google colocation facility, or need less than 10 Gbps |
| **Cross-Cloud Interconnect** | 10 / 100 / 400 Gbps to **AWS, Azure, OCI, Alibaba** | MACsec support | 99.9% / 99.99% | Weeks | Dedicated multicloud links managed by Google |
| Partner Cross-Cloud Interconnect for AWS | On-demand transport to AWS | — | — | Fast | Managed, on-demand Google Cloud ↔ AWS connectivity |
| Direct / Carrier Peering | Public Google edge | — | **No SLA** | — | Access to Google Workspace / public Google services; **not** for private VPC access |

### 4.2 Interconnect SLA topologies (memorize)

| Target | Topology |
|---|---|
| **99.9%** | At least **2 connections in the same metro**, in **different edge availability domains** (zone 1 and zone 2), with one Cloud Router |
| **99.99%**: multi-region | At least **4 connections across 2 metros** (2 per metro, both edge availability domains in each), VLAN attachments in **2 regions**, **at least 2 Cloud Routers** (one per region), VPC in **global dynamic routing mode** |
| **99.99%**: single-region (GA June 2026) | At least **4 connections in one supported metro** (2 in each of two facility/edge-availability-domain combinations), ordered as a **connection group** with intended capability **`PRODUCTION_CRITICAL`**, attachments in the metro's region, at least 1 Cloud Router; regional or global routing |
| No SLA | A single connection (development/testing only) |

On-premises routers must advertise the **same prefixes** over all BGP sessions for failover to work.

### 4.3 Design patterns

* **Interconnect primary + HA VPN backup:** VPN routes get lower priority (higher MED / lower local preference on-premises).
* **HA VPN over Interconnect:** encrypts traffic on the private link when policy requires end-to-end IPsec.
* **MACsec for Cloud Interconnect:** L2 encryption on Dedicated/Cross-Cloud links, with near line-rate performance.
* **Interim VPN while Interconnect is provisioned:** standard migration practice.
* **Hub-and-spoke with NCC:** hybrid spokes (Interconnect/VPN) at the hub, plus **site-to-site data transfer** to connect branches through Google's backbone where supported (KnightMotives plants to HQ).

### 4.4 Sizing quick reference

| Requirement | Answer |
|---|---|
| 500 Mbps, encrypted, needed this week | HA VPN |
| 5 Gbps sustained, no colocation presence | Partner Interconnect (redundant attachments) |
| 40 Gbps sustained, in a colocation facility, 99.99% | Dedicated Interconnect, 99.99% topology (multi-metro, or single-region critical in a supported metro) |
| Dedicated private link to AWS for 20 Gbps of replication traffic | Cross-Cloud Interconnect |
| Encrypt traffic over Interconnect | MACsec or HA VPN over Interconnect |

---

## 5. Hybrid and multicloud DNS

| Need | Cloud DNS feature |
|---|---|
| Cloud workloads resolve on-premises names | **Forwarding zone** to on-premises DNS servers (over Interconnect/VPN) |
| On-premises resolves Cloud private zones | **Inbound server policy** (inbound forwarder IPs in the VPC) |
| Share private zones across VPCs | **DNS peering** or binding zones to multiple networks |
| Override answers (block or redirect) | **Response policies** |
| Traffic steering and failover | **Routing policies**: weighted round robin, geolocation, failover (with health checks) |
| Integrity | **DNSSEC** for public zones |

---

## 6. Traffic security controls

| Control | Layer | Scope | Use |
|---|---|---|---|
| **VPC firewall rules** | L3/L4, stateful | Per VPC | Basic allow/deny by IP range, protocol/port, **network tags** or **service accounts** |
| **Network firewall policies** (global/regional) | L3/L4 (+ L7 with NGFW tiers) | Attach to VPCs | Group rules; use **IAM-governed secure tags** (Resource Manager tags) as targets |
| **Hierarchical firewall policies** | L3/L4 | **Organization / folder** | Org-wide guardrails evaluated *before* VPC rules; can `goto_next` to delegate |
| **Cloud NGFW Standard** | Adds FQDN objects, geolocation, threat-intelligence lists | Policies | Egress allow-lists by domain; block known-bad IPs |
| **Cloud NGFW Enterprise** | **Intrusion prevention (IPS)** via firewall endpoints, **TLS inspection** | Zonal endpoints | "Intrusion protection" requirement for east-west/north-south traffic |
| **Cloud Armor** | L7 WAF + DDoS at the load balancer edge | External LBs | OWASP rules, rate limiting, geo/IP allow/deny, bot management, Adaptive Protection |
| **VPC Service Controls** | Google API perimeter | Projects | Data exfiltration from Google-managed services ([04/03](../04-Security-and-Compliance/03-perimeter-network-security-and-remote-access.md)) |
| **IAP** | Identity-aware access | Apps and VMs | Replace VPN/bastions for user access |

**Rule evaluation order**: hierarchical policies (org → folder) → VPC firewall rules and network firewall policies (order configurable) → implied rules.

**Network tags vs secure tags vs service accounts as targets**

* **Network tags** can be set by anyone who can edit the instance, so they're weak for security boundaries.
* **Service-account targets** and **secure tags** are IAM-controlled, so they're stronger.

---

## 7. Network observability and troubleshooting

| Tool | Answers |
|---|---|
| **VPC Flow Logs** | Who talked to whom (sampled flow records) for forensics, capacity and cost analysis |
| **Firewall Rules Logging** | Which rule allowed or denied a connection |
| **Connectivity Tests** (Network Intelligence Center) | "Why can't A reach B?" Configuration analysis plus live data-plane checks |
| Network Topology, Performance Dashboard, **Firewall Insights** | Visualize traffic; find shadowed or unused rules |
| **Packet Mirroring** | Full packet capture to an IDS/collector |
| **Cloud IDS** / NGFW Enterprise IPS | Threat detection or prevention on traffic |

---

## 8. Reference topology (enterprise landing zone network)

```text
                   On-premises DC(s) ─── Dedicated Interconnect (99.99%) ───┐
                   Branches ──────────── HA VPN ───────────────────────────┤
                   Other cloud ───────── Cross-Cloud Interconnect ─────────┤
                                                                           ▼
                                   NCC hub (or hub VPC) with Cloud Routers (BGP)
                                       │                     │
              ┌────────────────────────┘                     └───────────────────────┐
     Prod Shared VPC (host project)                              Non-prod Shared VPC (host)
     ├─ subnets per region (custom mode)                         ├─ subnets per region
     ├─ service projects: app-a-prod, app-b-prod                 ├─ service projects
     ├─ Cloud NAT, Private Google Access / PSC endpoint (APIs)   └─ ...
     ├─ Hierarchical FW policy (org) → network FW policy (VPC)
     ├─ VPC Service Controls perimeter (data projects)
     └─ Cloud DNS: private zones, forwarding to on-prem, inbound policy
   Public entry: Global external Application LB + Cloud Armor + Cloud CDN → backends (private)
```

---

## 9. Traps

* **Assuming peering is transitive**, or proposing peering with overlapping CIDRs.
* **A VPN to connect two regions of the same VPC** (unnecessary; the VPC is global).
* **Direct or Carrier Peering for private VPC access** (no; those are public edge, with no SLA).
* **One Interconnect connection for production HA.**
* **Partner Interconnect for 100 Gbps** (its attachments top out at 50 Gbps; Dedicated scales higher).
* **Network tags as a security boundary** when IAM-governed targets exist.
* **Firewall rules to stop BigQuery or Cloud Storage exfiltration** (use VPC SC).
* **Public IPs plus SSH from the internet** when IAP TCP forwarding exists.

---

## References

* VPC overview: <https://cloud.google.com/vpc/docs/vpc>
* Shared VPC: <https://cloud.google.com/vpc/docs/shared-vpc>
* Private Service Connect: <https://cloud.google.com/vpc/docs/private-service-connect>
* Choosing a Network Connectivity product: <https://cloud.google.com/network-connectivity/docs/how-to/choose-product>
* Dedicated Interconnect 99.99% topologies: <https://docs.cloud.google.com/network-connectivity/docs/interconnect/tutorials/dedicated-creating-9999-availability>
* Interconnect release notes (400 Gbps, single-region SLA): <https://docs.cloud.google.com/network-connectivity/docs/interconnect/release-notes>
* HA VPN: <https://cloud.google.com/network-connectivity/docs/vpn/concepts/topologies>
* Cloud NGFW overview: <https://cloud.google.com/firewall/docs/about-firewalls>
* Network Connectivity Center: <https://cloud.google.com/network-connectivity/docs/network-connectivity-center/concepts/overview>
