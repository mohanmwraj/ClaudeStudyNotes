# 05 · Networking and traffic management

> **Exam link:** [05 · Services and Networking](../05-Services-and-Networking/README.md) (Services, Ingress, NetworkPolicies) · [02 · Application Deployment](../02-Application-Deployment/README.md) (blue/green and canary). The exam uses Ingress and Services; new production designs should start from Gateway API.

Networking decisions are hard to reverse: every public hostname, certificate and load balancer becomes a contract with clients. Keep the edge shared and platform-owned, keep routing in the hands of the teams, and design for traffic shifting from day one.

## Principles

1. **Internal by default.** Services are `ClusterIP`; exposure happens through one shared, platform-owned edge, not one cloud load balancer per Service.
2. **Separate infrastructure from routing.** The platform owns Gateways, addresses and certificates; app teams own their routes (Gateway API roles).
3. **Prefer standard APIs over controller annotations** - portability is a feature during the next migration.
4. **Encrypt at the edge always; east-west when the data or the threat model requires it** (mesh mTLS or CNI encryption).
5. **Few hops, measured latency.** Every proxy, sidecar and cross-zone hop costs latency and money.
6. **DNS is a production dependency:** tune it, cache it, monitor it.
7. **Releases are traffic shifts.** Weighted and header-based routing make canaries and blue/green cheap.

## Recommended defaults

| Area | Default | Why |
|---|---|---|
| Service type | `ClusterIP`, named ports, `targetPort` by name | internal, stable, refactor-safe |
| Stateful peers | headless Service (`clusterIP: None`) + StatefulSet `serviceName` | stable per-pod DNS names |
| North-south HTTP | Gateway API: shared `Gateway` per environment, `HTTPRoute` per app | role separation, native weights and matches |
| Existing Ingress | keep only on a maintained controller; plan migration | ingress-nginx is retired (below) |
| TLS | cert-manager issuing listener certificates; HTTP -> HTTPS redirect at the Gateway | automatic renewal, no manual secrets |
| East-west security | NetworkPolicy everywhere; mesh mTLS only when identity-based policy/encryption is required | cost/benefit |
| DNS | NodeLocal DNSCache, CoreDNS autoscaled, FQDNs with trailing dot for external names | fewer lookups, fewer timeouts |
| Zonal traffic | `trafficDistribution: PreferSameZone` (GA v1.35; `PreferClose` on v1.33-v1.34) where replicas are evenly spread | lower cross-zone cost and latency |

## Decision tables / trade-offs

### Service types

| Type / setting | Use when | Watch out |
|---|---|---|
| `ClusterIP` | default for everything internal | - |
| Headless (`clusterIP: None`) | StatefulSet peer discovery; client-side load balancing (gRPC) | clients must re-resolve DNS; no virtual IP |
| `NodePort` | backing a load balancer that targets nodes; labs | exposes a port on every node; quota it to 0 in app namespaces |
| `LoadBalancer` | non-HTTP TCP/UDP services; the Gateway's own data plane | one cloud LB (and bill) per Service; separate TLS/WAF; use `loadBalancerClass` and internal-LB annotations deliberately |
| `ExternalName` | DNS alias to an external host | CNAME only: no proxying, no port mapping; TLS hostname mismatches |
| `externalTrafficPolicy: Local` | preserve client source IP, avoid a second hop | uneven load across nodes; health checks per node |
| `internalTrafficPolicy: Local` | talk only to the agent on the same node (DaemonSets) | no fallback if the local pod is down |
| `externalIPs` | never | deprecated since v1.36; historical security issues |

gRPC and HTTP/2 caveat: kube-proxy balances **connections**, not requests. Long-lived HTTP/2 connections pin clients to a few pods, so new replicas get no traffic. Use client-side balancing over a headless Service, an L7 proxy (Gateway/mesh), or periodic connection recycling.

### Ingress or Gateway API

| Criterion | Ingress (`networking.k8s.io/v1`) | Gateway API (`gateway.networking.k8s.io/v1`) |
|---|---|---|
| Status | GA, **frozen** (no new features); no plans to remove it | the recommended API for new work; Standard channel GA since v1.0 (Oct 2023); current release v1.6.3 (Oct 2026) |
| Role separation | one object mixes infrastructure and routing | GatewayClass (provider), Gateway (platform), Routes (app teams) |
| Traffic splitting | controller-specific annotations | native `weight` on `backendRefs` |
| Matching | host + path | host, path, headers, query params, method |
| Cross-namespace | backend must be in the same namespace | Routes attach to a shared Gateway via `allowedRoutes`; cross-namespace backends/certs via `ReferenceGrant` |
| Protocols | HTTP(S) | HTTP, gRPC (`GRPCRoute`), TLS/TCP/UDP routes (channel varies, check your release), mesh (GAMMA) |
| Portability | low: behaviour lives in annotations | high: conformance tests, core vs extended features |
| Policy attachment | annotations | typed policies (e.g. `BackendTLSPolicy`) and implementation-specific policy CRDs |

Verdict: **new designs use Gateway API.** Existing Ingress estates can stay on a maintained controller while you migrate service by service.

### ingress-nginx retirement - facts and options

Facts (Kubernetes SIG Network and Security Response Committee, announced 2025-11-11): best-effort maintenance continued until **March 2026**; after that there are no releases, no bug fixes and no security patches; the repositories are read-only; existing deployments keep working and artifacts stay downloadable. The planned successor InGate was retired too. A joint Steering Committee + Security Response Committee statement (2026-01-29) adds: staying on Ingress NGINX after retirement "leaves you and your users vulnerable to attack", and **none of the alternatives is a drop-in replacement** - migration needs planning and engineering time. The **Ingress API itself remains GA (feature-frozen) and supported**, with no plans to remove it - only this controller is retired. (For CKAD practice labs ingress-nginx still works fine.)

Find it in a cluster: `kubectl get pods --all-namespaces --selector app.kubernetes.io/name=ingress-nginx`. Because existing deployments keep working, you will not notice you are affected unless you check.

| Path | When | Notes |
|---|---|---|
| Gateway API implementation (Envoy Gateway, Istio, Cilium, NGINX Gateway Fabric, Traefik, Kong, kgateway, GKE Gateway, AWS Load Balancer Controller, ...) | default for new and migrating workloads | pick by conformance report and the extended features you need |
| A maintained Ingress controller (e.g. F5 NGINX Ingress Controller, which is a different project from ingress-nginx; Traefik, HAProxy, Kong, Contour, cloud LB controllers) | many Ingress objects, short timeline | annotations are not compatible; treat as an intermediate step |
| Keep ingress-nginx | only temporarily, not internet-facing, with compensating controls | unpatched vulnerabilities accumulate |

Migration runbook:

1. Inventory Ingress objects and annotations (rewrites, auth, rate limits, canary annotations, and especially `*-snippet` annotations).
2. Choose an implementation; check its conformance report for every feature on your list.
3. Run it **side by side** with ingress-nginx (it gets its own address) and validate without touching production traffic.
4. Convert with `ingress2gateway` (v1.0 released; `ingress2gateway print --providers=ingress-nginx`), then review by hand.
5. Shift traffic per hostname (weighted DNS or LB), watch error rates and latency, then remove the old Ingress objects and controller.

### Service mesh: worth it?

| You need | Mesh? | Lighter alternative |
|---|---|---|
| mTLS with workload identity, L7 authorization between services | yes | - |
| Uniform retries, timeouts, circuit breaking across many services | yes | libraries per language, Gateway timeouts at the edge |
| Fine-grained traffic shifting/mirroring for east-west calls | yes | Gateway API for north-south canaries |
| Only encryption in transit inside the cluster | maybe | CNI transparent encryption (e.g. WireGuard in Cilium/Calico, verify current status) |
| A few services, small team | usually no | NetworkPolicy + good client libraries |

| Mesh | Data plane | Notes |
|---|---|---|
| Istio (sidecar mode) | Envoy per pod | richest feature set; per-pod overhead; mesh upgrades restart pods |
| Istio ambient (GA since Istio 1.24) | ztunnel per node (L4 mTLS) + optional waypoint proxies (L7) | no sidecars; pay for L7 only where used |
| Linkerd | Rust micro-proxy sidecar | simple and light; open-source project publishes edge releases, stable releases come from vendor distributions such as Buoyant Enterprise for Linkerd (verify current status) |
| Cilium service mesh | eBPF + per-node Envoy | sidecar-less, integrated with Cilium CNI and Gateway API |

Gateway API also covers east-west routing (GAMMA: an `HTTPRoute` whose parent is a Service); Istio and Cilium are listed as conformant mesh implementations. Retries need budgets: retry only idempotent requests, with timeouts and jitter, or a partial outage becomes a retry storm.

### DNS performance

| Problem | Cause | Fix |
|---|---|---|
| 4-10 queries per external lookup | pod `resolv.conf` has `ndots:5` + 3 cluster search domains; `api.example.com` has fewer than 5 dots | trailing dot (`api.example.com.`), or `dnsConfig` `ndots: "2"` for pods calling many external hosts |
| Sporadic 5s DNS timeouts | UDP/conntrack races, overloaded CoreDNS | NodeLocal DNSCache (DaemonSet on a link-local IP), CoreDNS replicas scaled with the cluster |
| Stale endpoints after scaling | client-side DNS caching of headless records | short TTLs, client re-resolution |
| Pods on `hostNetwork` cannot resolve Services | default policy uses node DNS | `dnsPolicy: ClusterFirstWithHostNet` |

### Egress control

| Requirement | Mechanism |
|---|---|
| Deny all except known destinations | default-deny egress NetworkPolicy + `ipBlock`/namespace rules |
| Allow by DNS name (SaaS APIs) | CNI-specific FQDN policies (e.g. Cilium `toFQDNs`) or an egress HTTP proxy with an allow-list |
| Fixed source IP for partner allow-lists | egress gateway (CNI or mesh) or cloud NAT per node pool |
| Audit outbound connections | CNI flow logs or mesh telemetry |

### Topology-aware routing

| Option | Status | Behaviour | Use when |
|---|---|---|---|
| `spec.trafficDistribution: PreferSameZone` | GA v1.35 (beta v1.34) | prefer endpoints in the client's zone, fall back to others | replicas spread evenly; clients spread evenly |
| `spec.trafficDistribution: PreferClose` | GA v1.33; now a deprecated alias of `PreferSameZone` | same | clusters on v1.33-v1.34 |
| `spec.trafficDistribution: PreferSameNode` | GA v1.35 | prefer an endpoint on the same node | node-local caches/agents with fallback |
| annotation `service.kubernetes.io/topology-mode: Auto` | GA v1.33 (topology aware hints) | allocates endpoints per zone proportionally; disables itself when safeguards fail | older approach; needs >= 3 endpoints per zone |

Risk: if most traffic originates in one zone, or a zone has fewer pods, that zone's endpoints overload while the HPA (which averages across all pods) sees moderate load. Combine with zone topology spread and enough replicas per zone, and watch per-zone latency.

## Anti-patterns

| Anti-pattern | Consequence | Fix |
|---|---|---|
| One `LoadBalancer` Service per microservice | cost, IP and certificate sprawl, inconsistent TLS/WAF | one shared Gateway; quota `services.loadbalancers: 0` |
| Business logic in ingress annotations (`*-snippet`) | controller lock-in; injection risk (a reason ingress-nginx became unmaintainable) | Gateway API filters, app code |
| Staying on ingress-nginx after March 2026 | unpatched internet-facing proxy ("vulnerable to attack" per the Steering/SRC statement) | migrate (runbook above) |
| Certificates copied by hand into Secrets | outages on expiry | cert-manager + expiry alerts |
| Mesh adopted "for observability" only | sidecar/ops cost for metrics you could get from OTel | instrument apps; adopt a mesh for security/traffic needs |
| Unbounded retries at several layers | retry storms amplify outages | one retry layer, budgets, timeouts |
| `ndots:5` with chatty external calls | DNS load and latency | FQDNs with trailing dot, NodeLocal DNSCache |
| gRPC behind a ClusterIP with few long connections | hot pods, idle new replicas | client-side LB / L7 proxy |
| Topology routing with uneven replicas | one zone overloaded | spread evenly, >= 3 endpoints per zone |

## Reference YAML

- Shared Gateway, HTTP->HTTPS redirect, weighted canary with header override: [`yaml/gateway-api-canary.yaml`](yaml/gateway-api-canary.yaml)
- Default-deny + DNS, three-tier allows: [`yaml/namespace-baseline.yaml`](yaml/namespace-baseline.yaml), [`yaml/networkpolicy-three-tier.yaml`](yaml/networkpolicy-three-tier.yaml)

Headless Service for a StatefulSet (stable names such as `pg-0.pg.data.svc.cluster.local`):

```yaml
apiVersion: v1
kind: Service
metadata:
  name: pg
  namespace: data
spec:
  clusterIP: None                  # headless: DNS returns pod IPs, no virtual IP
  publishNotReadyAddresses: true   # peers can find each other while bootstrapping
  selector:
    app.kubernetes.io/name: pg
  ports:
  - name: postgres
    port: 5432
    targetPort: 5432
```

Zone-local routing for an evenly spread service:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: catalog
  namespace: shop
spec:
  selector:
    app.kubernetes.io/name: catalog
  ports:
  - name: http
    port: 80
    targetPort: http
  trafficDistribution: PreferSameZone   # v1.35 GA; use PreferClose on v1.33-v1.34
```

cert-manager ClusterIssuer solving HTTP-01 through the shared Gateway (requires cert-manager with `config.gatewayAPI.enabled=true`; wildcard names need a DNS-01 solver instead):

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: platform-team@example.com
    privateKeySecretRef:
      name: letsencrypt-prod-account-key
    solvers:
    - http01:
        gatewayHTTPRoute:
          parentRefs:
          - name: prod-gateway
            namespace: infra-gateway
            kind: Gateway
```

Fewer DNS lookups for a pod that calls many external APIs (fragment of a pod spec):

```yaml
dnsConfig:
  options:
  - name: ndots
    value: "2"                     # names with >= 2 dots are tried as absolute first
```

## Checklist

- [ ] Services are `ClusterIP` with named ports; no `LoadBalancer`/`NodePort` in app namespaces (quota = 0).
- [ ] North-south traffic through a shared, platform-owned Gateway; HTTPRoutes owned by app teams; namespaces opt in by label.
- [ ] No ingress-nginx in production (or a dated migration plan); ingress2gateway used as the starting point.
- [ ] TLS everywhere at the edge with cert-manager; HTTP redirects to HTTPS; certificate-expiry alerts.
- [ ] Canary/blue-green possible via `HTTPRoute` weights and header matches.
- [ ] Mesh adopted only with a stated need (mTLS identity, L7 policy, traffic control) and an owner.
- [ ] DNS: NodeLocal DNSCache or equivalent, CoreDNS scaled and monitored, FQDNs for external calls.
- [ ] Egress restricted; FQDN or proxy-based control for internet destinations.
- [ ] Zone-aware routing only where replicas and clients are evenly spread.
- [ ] gRPC/HTTP2 services load-balanced at L7 or client-side.

## References

- Services: https://kubernetes.io/docs/concepts/services-networking/service/
- Ingress (frozen API): https://kubernetes.io/docs/concepts/services-networking/ingress/
- Ingress controllers: https://kubernetes.io/docs/concepts/services-networking/ingress-controllers/
- Gateway API in the Kubernetes docs: https://kubernetes.io/docs/concepts/services-networking/gateway/
- Gateway API: https://gateway-api.sigs.k8s.io/
- Installing Gateway API: https://gateway-api.sigs.k8s.io/guides/getting-started/introduction/
- Roles and personas: https://gateway-api.sigs.k8s.io/docs/concepts/roles-and-personas/
- Security model: https://gateway-api.sigs.k8s.io/docs/concepts/security/
- Traffic splitting: https://gateway-api.sigs.k8s.io/guides/user-guides/traffic-splitting/
- Cross-namespace routing: https://gateway-api.sigs.k8s.io/guides/user-guides/multiple-ns/
- HTTP redirects and rewrites: https://gateway-api.sigs.k8s.io/guides/user-guides/http-redirect-rewrite/
- Implementations and conformance: https://gateway-api.sigs.k8s.io/docs/implementations/list/
- Migrating from Ingress: https://gateway-api.sigs.k8s.io/guides/getting-started/migrating-from-ingress/
- Guide for ingress-nginx users: https://gateway-api.sigs.k8s.io/guides/getting-started/migrating-from-ingress-nginx/
- GAMMA (Gateway API for service mesh): https://gateway-api.sigs.k8s.io/docs/mesh/gamma/
- Ingress NGINX retirement announcement: https://kubernetes.io/blog/2025/11/11/ingress-nginx-retirement/
- Steering + Security Response Committee statement on Ingress NGINX: https://kubernetes.io/blog/2026/01/29/ingress-nginx-statement/
- ingress2gateway: https://github.com/kubernetes-sigs/ingress2gateway
- cert-manager with Gateway API: https://cert-manager.io/docs/usage/gateway/
- cert-manager ACME HTTP-01: https://cert-manager.io/docs/configuration/acme/http01/
- DNS for Services and Pods: https://kubernetes.io/docs/concepts/services-networking/dns-pod-service/
- NodeLocal DNSCache: https://kubernetes.io/docs/tasks/administer-cluster/nodelocaldns/
- Debugging DNS resolution: https://kubernetes.io/docs/tasks/administer-cluster/dns-debugging-resolution/
- Topology aware routing: https://kubernetes.io/docs/concepts/services-networking/topology-aware-routing/
- Network policies: https://kubernetes.io/docs/concepts/services-networking/network-policies/
- Istio ambient mode: https://istio.io/latest/docs/ambient/overview/
- Linkerd releases: https://linkerd.io/releases/
- Cilium: https://cilium.io/
