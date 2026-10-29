# 03/02 · Load Balancing and the Edge

**Exam guide:** 2.1 ("VPC design and load balancing (access to cloud, internet, and cloud adjacent services)"), 1.3 (load balancers). **Principles:** P1, P2, P6.

---

## 1. Four questions select the load balancer

1. **Protocol?** HTTP(S)/HTTP2/gRPC/WebSocket → **Application Load Balancer** (L7). TCP/UDP/other → **Network Load Balancer** (L4).
2. **Clients external or internal?** Internet-facing vs inside VPC/hybrid.
3. **Global or regional?** Users and backends in many regions with one anycast IP → global. Data-residency or single-region → regional.
4. **Proxy or passthrough?** Proxy terminates the connection (TLS offload, Cloud Armor, CDN). Passthrough **preserves the client source IP** and supports UDP/ESP/ICMP.

## 2. The family

| Load balancer | Layer | Scope | Typical use |
|---|---|---|---|
| **Global external Application LB** | L7 proxy | Global (anycast, Premium Tier) | Internet-facing web/API with users worldwide; **Cloud CDN**, **Cloud Armor**, **IAP**, cross-region failover, traffic splitting |
| Regional external Application LB | L7 proxy | One region | Internet-facing web/API that must stay in one region (residency), or Standard Tier |
| Classic Application LB | L7 proxy | Global | Legacy version; migrate to global external ALB |
| **Cross-region internal Application LB** | L7 proxy | Global internal | Internal HTTP services with backends in multiple regions and failover |
| **Regional internal Application LB** | L7 proxy | One region | Internal microservices, hybrid back ends |
| Global external proxy Network LB | L4 proxy (TCP, optional SSL offload) | Global | Non-HTTP TCP services worldwide with TLS offload |
| Regional external / internal proxy Network LB | L4 proxy | Region | TCP proxying in a region |
| **External passthrough Network LB** | L4 passthrough (TCP, UDP, ESP, GRE, ICMP) | Region | Gaming (UDP), preserve client IP, non-proxyable protocols |
| **Internal passthrough Network LB** | L4 passthrough | Region | Internal TCP/UDP (database proxies, legacy apps, next-hop for appliances) |

**Backends** can be:

* managed/unmanaged instance groups;
* **zonal NEGs** (GKE pods via container-native load balancing);
* **serverless NEGs** (Cloud Run, Cloud Run functions, App Engine);
* **internet NEGs** (external origins);
* **hybrid connectivity NEGs** (on-premises or other-cloud endpoints over Interconnect/VPN);
* **PSC NEGs** (published services).

---

## 3. Decision table

| Scenario | Choose |
|---|---|
| Global e-commerce site, single IP, lowest latency worldwide, WAF, cache images | Global external Application LB + Cloud CDN + Cloud Armor |
| Same, but traffic must terminate only in EU regions | Regional external Application LB in an EU region (or global with EU-only backends, if residency allows edge termination; check the requirement) |
| Multiplayer game servers on UDP, need client IP | External passthrough Network LB |
| Cloud Run services in 3 regions behind one URL | Global external Application LB with **serverless NEGs** per region |
| Internal REST microservices on GKE in one region | Regional internal Application LB (via the **GKE Gateway** controller) |
| Internal services that fail over across regions | Cross-region internal Application LB |
| Gradually move traffic from on-premises back ends to cloud back ends | Application LB with **hybrid connectivity NEGs** + weighted traffic splitting |
| Route `/api/*` to GKE and `/static/*` to a bucket | Application LB **URL map** with a **backend bucket** for static content |
| Protect against L7 DDoS and OWASP Top 10 attacks | **Cloud Armor** security policy on the external Application LB (preconfigured WAF rules, rate limiting, Adaptive Protection) |
| Zero-trust access for employees to an internal web app | **IAP** enabled on the Application LB backend (plus context-aware access) |

---

## 4. Edge and content delivery

| Product | Use |
|---|---|
| **Cloud CDN** | Cache HTTP(S) content at Google's edge for Application LB back ends (instance groups, buckets, NEGs); signed URLs/cookies; cache modes |
| **Media CDN** | Large-scale video streaming and large file delivery (uses YouTube's edge infrastructure). Fits Altostrat-style media delivery |
| **Cloud Armor** | WAF (OWASP CRS), DDoS protection, rate limiting, bot management (reCAPTCHA integration), geo and IP rules, named IP lists; Cloud Armor Enterprise adds Adaptive Protection and DDoS response support |
| **Certificate Manager** / Google-managed certificates | Automatic TLS certificates at scale |
| **Cloud DNS** routing policies | DNS-level steering and failover for non-LB scenarios |

---

## 5. Features the exam likes

| Feature | What it does |
|---|---|
| **Health checks** | Remove unhealthy back ends; also drive MIG autohealing (use separate, more conservative checks for autohealing) |
| **Connection draining** | Lets in-flight requests finish before a backend is removed |
| **Session affinity** (client IP, generated cookie, header) | Sticky routing. Use only when state can't be externalized (prefer P3) |
| **Traffic splitting / weighted backends** | Canary releases and migrations |
| **Header- and path-based routing** | Advanced URL maps for microservices and A/B tests |
| **Outlier detection, circuit breaking, retries** | Resilience with advanced traffic management |
| **Container-native load balancing (NEGs)** | LB sends traffic directly to pod IPs. Better latency, accurate health checks |
| **GKE Gateway API** | Kubernetes-native configuration of Google load balancers, including **multi-cluster Gateways** across a fleet |
| **mTLS** (frontend) | Client certificate authentication at the LB |

---

## 6. Traps

* **Regional LB for a "single global IP, worldwide users" requirement.**
* **Proxy LB when the app needs the client source IP at L4**: use passthrough, or read `X-Forwarded-For` at L7.
* **Cloud Armor on an internal passthrough LB** (it attaches to external Application LBs and certain proxy LBs).
* **Building your own HAProxy/Nginx fleet on VMs** when a managed LB fits (P5).
* **Session affinity to fix lost sessions** when the real fix is externalizing state.
* **Cloud CDN for dynamic, personalized responses** without cache-key design. CDN helps static and cacheable content.

---

## References

* Choose a load balancer: <https://cloud.google.com/load-balancing/docs/choosing-load-balancer>
* Load balancing overview: <https://cloud.google.com/load-balancing/docs/load-balancing-overview>
* Serverless NEGs: <https://cloud.google.com/load-balancing/docs/negs/serverless-neg-concepts>
* Hybrid connectivity NEGs: <https://cloud.google.com/load-balancing/docs/negs/hybrid-neg-concepts>
* Cloud Armor overview: <https://cloud.google.com/armor/docs/cloud-armor-overview>
* Media CDN: <https://cloud.google.com/media-cdn/docs/overview>
