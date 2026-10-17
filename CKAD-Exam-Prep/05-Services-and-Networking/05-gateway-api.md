# 05 — Gateway API (Bonus / Forward-Looking)

> **Scope note:** Gateway API is **not named in the CKAD curriculum** (the competency is "Use Ingress rules to expose applications"). It is the **successor to Ingress**, the Kubernetes docs recommend it over the frozen Ingress API, and it has been in the **CKA** curriculum since 2025 ("Use the Gateway API to manage Ingress traffic"). The Linux Foundation's allowed-resources page lists `gateway-api.sigs.k8s.io` as allowed for the **CKA only** — in the CKAD you could only use kubernetes.io's own page, https://kubernetes.io/docs/concepts/services-networking/gateway/. Treat this chapter as 🧊 bonus before the exam, and as essential knowledge for production and architecture work.

**Why it matters:** Ingress squeezes everything beyond host/path routing into controller-specific annotations. Gateway API makes those features typed and portable (header matching, weighted traffic splitting, redirects, rewrites, header changes), splits responsibilities between platform and app teams, and makes cross-namespace sharing explicit and safe.

---

## Core concepts

### Resource model and personas

| Resource | Scope | Owned by (persona) | Purpose | API version |
|---|---|---|---|---|
| `GatewayClass` | cluster | Infrastructure provider | Which controller implements Gateways of this class (like IngressClass) | `gateway.networking.k8s.io/v1` |
| `Gateway` | namespace | Cluster operator | A traffic entry point: listeners (port, protocol, hostname, TLS) and which Routes may attach | `v1` |
| `HTTPRoute` | namespace | Application developer | HTTP matching rules → filters → backends | `v1` |
| `GRPCRoute` | namespace | Application developer | gRPC matching by service/method | `v1` |
| `ReferenceGrant` | namespace (the target's) | Owner of the referenced object | Permits cross-namespace references (Route → Service, Gateway → Secret) | `v1beta1` (also served as `v1` since Gateway API v1.5) |
| `TLSRoute`, `ListenerSet` | namespace | – | Standard channel since Gateway API v1.5 | `v1` |
| `TCPRoute`, `UDPRoute` | namespace | – | Experimental channel | `v1alpha2` |

Personas from the docs: **Infrastructure Provider** (runs the infrastructure, e.g. a cloud provider), **Cluster Operator** (policies, network access, permissions), **Application Developer** (application-level routing and Service composition).

```text
GatewayClass "eg" (cluster)        <- implemented by a controller (Envoy Gateway, NGINX Gateway Fabric, Istio, Cilium, Traefik, ...)
      ^ gatewayClassName
Gateway "shared-gw" (ns infra)     listeners: http:80, https:443 (TLS certificateRefs) + allowedRoutes
      ^ parentRefs (+ sectionName)                         ^ the Gateway must ALLOW the Route's namespace
HTTPRoute "shop" (ns shop)         hostnames + rules: matches -> filters -> backendRefs (weights)
      | backendRefs
      v
Service (ns shop)                  or a Service in another namespace, if a ReferenceGrant there allows it
```

Gateway API is a set of **CRDs plus an implementation** — not built into Kubernetes. Its version (v1.x) is independent of the Kubernetes version; resources ship in a **Standard** channel (GA/beta) and an **Experimental** channel.

### Request flow

1. Client resolves the hostname to the Gateway's address and sends the request.
2. The Gateway's proxy picks the listener (port/protocol/hostname) and the attached Route by `Host` header.
3. HTTPRoute rules match on path, headers, query parameters, method.
4. Filters modify the request (headers, rewrites) or answer directly (redirects).
5. The request goes to one of the `backendRefs`, chosen by weight.

### HTTPRoute matches

| Match | Types | Notes |
|---|---|---|
| `path` | `PathPrefix` (default, value `/`), `Exact`, `RegularExpression` | Regex support is implementation-specific |
| `headers[]` | `Exact` (default), `RegularExpression` | header names are case-insensitive |
| `queryParams[]` | `Exact` (default), `RegularExpression` | |
| `method` | `GET`, `POST`, ... | |

- Conditions inside **one** `matches` entry are **ANDed**; several entries in a rule are **ORed**.
- A rule **without** `matches` matches everything (`PathPrefix /`).
- When several rules match, precedence is: Exact path → longest prefix → method → most header matches → most query-param matches; remaining ties go to the oldest Route, then alphabetical `namespace/name`.

```yaml
rules:
- matches:
  - headers:
    - name: x-canary
      value: "true"
  - queryParams:
    - name: version
      value: v2
  backendRefs:
  - name: checkout-v2
    port: 80
```

(header `x-canary: true` **OR** `?version=v2` → v2). Full example: [yaml/gateway-api/httproute-header-match.yaml](yaml/gateway-api/httproute-header-match.yaml).

### Filters

| Filter | Support level | Does |
|---|---|---|
| `RequestHeaderModifier` | Core | `set` / `add` / `remove` request headers |
| `ResponseHeaderModifier` | Extended | same, on responses |
| `RequestRedirect` | Core | redirect (scheme, hostname, port, path, `statusCode` 301/302) — answered by the Gateway, no backend needed |
| `URLRewrite` | Extended | rewrite hostname and/or path (`ReplaceFullPath` or `ReplacePrefixMatch`) before forwarding |
| `RequestMirror` | Extended | copy requests to another backend |
| `CORS` | Standard channel since v1.5 | CORS handling |
| `ExtensionRef` | Implementation-specific | implementation's own filter CRDs |

`RequestRedirect` and `URLRewrite` cannot be combined in one rule. Example: [yaml/gateway-api/httproute-filters.yaml](yaml/gateway-api/httproute-filters.yaml).

### Weighted backends: canary and blue-green

```yaml
rules:
- backendRefs:
  - name: checkout-v1
    port: 80
    weight: 90
  - name: checkout-v2
    port: 80
    weight: 10
```

- Weights are **relative** (default 1; they need not sum to 100). `weight: 0` = no traffic.
- **Canary:** 90/10 → 50/50 → 0/100. **Blue-green:** flip 100/0 → 0/100 in one change.
- No controller-specific canary annotations needed. File: [yaml/gateway-api/httproute-canary-weights.yaml](yaml/gateway-api/httproute-canary-weights.yaml).

### Cross-namespace attachment and references

| Relationship | Who must agree | Mechanism |
|---|---|---|
| Route (ns A) → Gateway (ns B) | Route lists the Gateway in `parentRefs` (with `namespace: B`) **and** the listener's `allowedRoutes.namespaces.from` is `All` or a `Selector` matching ns A | handshake — **no** ReferenceGrant |
| Route (ns A) → Service (ns C) | Owner of ns C creates a **ReferenceGrant** in ns C: `from` HTTPRoute in A, `to` Service | ReferenceGrant |
| Gateway (ns B) → TLS Secret (ns D) | **ReferenceGrant** in ns D: `from` Gateway in B, `to` Secret | ReferenceGrant |

```yaml
apiVersion: gateway.networking.k8s.io/v1beta1
kind: ReferenceGrant
metadata:
  name: allow-shop-httproutes
  namespace: payments          # the namespace of the Service being referenced
spec:
  from:
  - group: gateway.networking.k8s.io
    kind: HTTPRoute
    namespace: shop
  to:
  - group: ""
    kind: Service
```

`allowedRoutes.namespaces.from`: `Same` (default) · `All` · `Selector` (+ `selector` on namespace labels, e.g. `kubernetes.io/metadata.name`). Files: [yaml/gateway-api/gateway.yaml](yaml/gateway-api/gateway.yaml) · [yaml/gateway-api/httproute-basic.yaml](yaml/gateway-api/httproute-basic.yaml) · [yaml/gateway-api/referencegrant.yaml](yaml/gateway-api/referencegrant.yaml).

### Status: how to tell whether it works

| Resource | Look at | Healthy |
|---|---|---|
| GatewayClass | `kubectl get gatewayclass` | `ACCEPTED True` (a controller owns it) |
| Gateway | `kubectl get gateway -n infra` | `PROGRAMMED True`, an `ADDRESS` |
| HTTPRoute | `kubectl describe httproute <r> -n <ns>` → `Status.Parents[].Conditions` | `Accepted True`, `ResolvedRefs True` |

Typical failure reasons: `NotAllowedByListeners` (namespace not allowed), `NoMatchingListenerHostname`, `NoMatchingParent` (wrong `sectionName`/port), `BackendNotFound`, `RefNotPermitted` (missing ReferenceGrant).

---

## Key fields / syntax

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: shared-gw
  namespace: infra
spec:
  gatewayClassName: eg                 # from: kubectl get gatewayclass
  listeners:
  - name: http
    protocol: HTTP                     # HTTP | HTTPS | TLS | TCP | UDP (depends on implementation)
    port: 80
    allowedRoutes:
      namespaces:
        from: All                      # Same (default) | All | Selector
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: shop
  namespace: shop
spec:
  parentRefs:
  - name: shared-gw
    namespace: infra                   # required when the Gateway is in another namespace
    sectionName: http                  # optional: one listener
  hostnames:
  - shop.example.com
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /api
    backendRefs:
    - name: api-svc
      port: 8080                       # required for Service backends
  - backendRefs:                       # no matches = catch-all
    - name: web-svc
      port: 80
```

| File | Shows |
|---|---|
| [yaml/gateway-api/gateway.yaml](yaml/gateway-api/gateway.yaml) | GatewayClass + shared Gateway with HTTP/HTTPS listeners and `allowedRoutes` selector |
| [yaml/gateway-api/httproute-basic.yaml](yaml/gateway-api/httproute-basic.yaml) | Route in its own namespace attached cross-namespace; path rule + catch-all |
| [yaml/gateway-api/httproute-canary-weights.yaml](yaml/gateway-api/httproute-canary-weights.yaml) | 90/10 weighted backends |
| [yaml/gateway-api/httproute-header-match.yaml](yaml/gateway-api/httproute-header-match.yaml) | header / query / method matching, AND vs OR |
| [yaml/gateway-api/httproute-filters.yaml](yaml/gateway-api/httproute-filters.yaml) | RequestRedirect, URLRewrite, RequestHeaderModifier |
| [yaml/gateway-api/referencegrant.yaml](yaml/gateway-api/referencegrant.yaml) | Cross-namespace backend + ReferenceGrant |

---

## Imperative commands

There are no `kubectl create` generators for Gateway API kinds — write YAML. Useful commands:

```bash
kubectl api-resources --api-group=gateway.networking.k8s.io       # are the CRDs installed? which versions?
kubectl get crd | grep gateway.networking.k8s.io
kubectl explain httproute.spec.rules --recursive                   # schema help (CRDs ship OpenAPI schemas)
kubectl get gatewayclass                                           # NAME, CONTROLLER, ACCEPTED
kubectl get gateway -A                                             # CLASS, ADDRESS, PROGRAMMED
kubectl get httproute -A                                           # HOSTNAMES
kubectl describe httproute shop -n shop                            # Accepted / ResolvedRefs + reasons
kubectl get referencegrant -A
GW=$(kubectl get gateway shared-gw -n infra -o jsonpath='{.status.addresses[0].value}')
curl -s -H "Host: shop.example.com" http://$GW/api
```

### Install for practice

```bash
# 1) Gateway API CRDs, Standard channel -- pick a release tag from
#    https://github.com/kubernetes-sigs/gateway-api/releases  (server-side apply: the bundles are large)
kubectl apply --server-side -f https://github.com/kubernetes-sigs/gateway-api/releases/download/<version>/standard-install.yaml

# 2) An implementation -- follow its own quickstart (many install or bundle the CRDs themselves):
#    Envoy Gateway, NGINX Gateway Fabric, Istio, Cilium, Traefik, Kong, ... ; on kind, recent
#    cloud-provider-kind releases implement Gateway API (and Ingress, LoadBalancer) natively.
#    Example shape (Envoy Gateway quickstart, check its docs for the current version):
helm install eg oci://docker.io/envoyproxy/gateway-helm --version <version> \
  -n envoy-gateway-system --create-namespace
kubectl get gatewayclass                                            # use the class it provides
```

From Gateway API v1.5, installing the Experimental CRDs over Standard ones (or downgrading below v1.5) is blocked by a `safe-upgrades` ValidatingAdmissionPolicy — read the release notes before switching channels.

---

## Ingress → Gateway API mapping

| Ingress | Gateway API |
|---|---|
| `IngressClass` | `GatewayClass` |
| Controller entry point (its Service, ports 80/443) | `Gateway` + `listeners` (port, protocol, hostname) |
| `spec.ingressClassName` | `Gateway.spec.gatewayClassName`; Routes use `parentRefs` |
| `spec.rules[].host` | `HTTPRoute.spec.hostnames` (intersected with the listener `hostname`) |
| `pathType: Prefix` / `Exact` | `path.type: PathPrefix` / `Exact` |
| `pathType: ImplementationSpecific` (regex) | `path.type: RegularExpression` (implementation-specific) |
| `backend.service.name` + `port.number` | `backendRefs[].name` + `port` |
| `spec.defaultBackend` | a rule without `matches` (catch-all `PathPrefix /`) |
| `spec.tls[].secretName` | listener `tls.certificateRefs` (TLS config moves to the Gateway owner) |
| `rewrite-target` annotation | `URLRewrite` filter |
| `ssl-redirect` / `force-ssl-redirect` annotations | `RequestRedirect` filter (`scheme: https`) on the HTTP listener's Route |
| canary annotations (`canary-weight`) | `backendRefs[].weight` |
| header-based canary annotations | `matches[].headers` |
| custom header annotations | `RequestHeaderModifier` / `ResponseHeaderModifier` |
| cross-namespace backends — not possible | `ReferenceGrant` + `allowedRoutes` |
| HTTP only | HTTPRoute, GRPCRoute, TLSRoute (+ experimental TCPRoute/UDPRoute) |

### ingress2gateway

`ingress2gateway` (kubernetes-sigs, maintained by the Gateway API subproject) translates Ingresses — plus provider-specific annotations/CRDs (ingress-nginx, Istio, Kong, Cilium, Traefik, GCE, ...) — into Gateway API resources. It does not copy annotations blindly; review the output.

```bash
# install: Go (go install github.com/kubernetes-sigs/ingress2gateway@<release>), Homebrew (brew install ingress2gateway)
# or a release binary from https://github.com/kubernetes-sigs/ingress2gateway/releases
ingress2gateway print --providers=ingress-nginx                      # Ingresses of the current namespace (kubeconfig context)
ingress2gateway print --providers=ingress-nginx -A > gateway.yaml    # all namespaces
ingress2gateway print --providers=ingress-nginx --input-file=ingress.yaml -n shop   # from files instead of a cluster
kubectl apply -f gateway.yaml                                        # after review; run side by side, then move DNS
```

---

## Exam traps & tips

> **Exam tip:** before the CKAD, spend minutes here, not hours — the curriculum names Ingress, not Gateway API. If a Gateway API task ever appears, your only references are `kubectl explain` (it works on the CRDs) and https://kubernetes.io/docs/concepts/services-networking/gateway/ — `gateway-api.sigs.k8s.io` is on the allowed list for the CKA only (exam rules: [00 Exam Overview and Setup](../00-Exam-Overview-and-Setup/README.md)).

> **Exam tip:** a Route in another namespace than the Gateway needs **both** `parentRefs[].namespace` **and** a listener that allows that namespace (`allowedRoutes.namespaces.from: All` or `Selector`). The default `Same` rejects it with `NotAllowedByListeners`.

- `backendRefs[].port` is required for Service backends.
- ReferenceGrant goes in the **target** namespace (where the Service/Secret lives), never in the Route's namespace.
- HTTPRoute `hostnames` must intersect the listener `hostname`, otherwise `NoMatchingListenerHostname`.
- `RequestRedirect` + `URLRewrite` in one rule is invalid.
- Weights are relative; `0` disables a backend.
- Quote header values like `"true"`.

---

## Architect notes

- **Role separation is the point:** platform teams own GatewayClass/Gateway (IPs, TLS, listeners, policies); app teams own Routes in their namespaces. `allowedRoutes` and ReferenceGrant are explicit, reviewable trust boundaries — far safer multi-tenancy than shared Ingress annotations.
- **Portability is measured, not assumed:** features are Core / Extended / Implementation-specific; check an implementation's conformance report before relying on e.g. regex paths, mirroring or CORS.
- **Shared vs dedicated Gateways:** one shared Gateway is cheaper; per-team or per-environment Gateways reduce blast radius. ListenerSet (Standard since v1.5) lets teams add listeners to a shared Gateway.
- **TLS end to end:** listeners terminate (or pass through via TLSRoute); BackendTLSPolicy covers TLS to backends; cert-manager can issue certificates for Gateway listeners.
- **Migration path off ingress-nginx** (retired, no fixes after March 2026): inventory annotations, convert with ingress2gateway, run old and new entry points in parallel, shift DNS gradually, then delete the old controller.
- **CRD lifecycle is yours:** Gateway API versions move independently of Kubernetes; pin the CRD bundle per cluster, upgrade it deliberately, and keep Standard vs Experimental consistent with what your implementation supports.
- **Mesh too:** the GAMMA initiative applies the same Route types to east-west (service mesh) traffic, so one API can describe north-south and east-west routing.

---

## Docs to bookmark

Usable in the CKAD exam (kubernetes.io):

- Gateway API on kubernetes.io: https://kubernetes.io/docs/concepts/services-networking/gateway/

For study, labs and the CKA (`gateway-api.sigs.k8s.io` is allowed in the CKA only):

- Project site (guides, API reference): https://gateway-api.sigs.k8s.io/
- Installing / getting started: https://gateway-api.sigs.k8s.io/guides/
- API overview (attaching Routes, roles): https://gateway-api.sigs.k8s.io/docs/concepts/api-overview/
- HTTPRoute: https://gateway-api.sigs.k8s.io/reference/api-types/httproute/
- ReferenceGrant: https://gateway-api.sigs.k8s.io/reference/api-types/referencegrant/
- Migrating from Ingress: https://gateway-api.sigs.k8s.io/guides/getting-started/migrating-from-ingress
- ingress2gateway: https://github.com/kubernetes-sigs/ingress2gateway
- Ingress NGINX retirement: https://kubernetes.io/blog/2025/11/11/ingress-nginx-retirement/

---

## Quick self-check

1. Which persona typically owns GatewayClass, Gateway and HTTPRoute?
2. An HTTPRoute in namespace `shop` must attach to Gateway `shared-gw` in `infra`. What is needed on each side?
3. The same Route sends `/pay` to Service `payments-api` in namespace `payments`. What else is required, and where?
4. How do you send 20% of traffic to `v2` without annotations?
5. Which filter strips a path prefix, and can it be combined with `RequestRedirect` in one rule?
6. What is the Gateway API equivalent of an Ingress `spec.defaultBackend`?

<details><summary>Answers</summary>

1. Infrastructure provider → GatewayClass; cluster operator → Gateway; application developer → HTTPRoute.
2. Route: `parentRefs: [{name: shared-gw, namespace: infra}]`. Gateway: a listener with `allowedRoutes.namespaces.from: All` or a `Selector` matching `shop`.
3. A ReferenceGrant **in `payments`** allowing `from` HTTPRoute in `shop` `to` kind Service (plus `namespace: payments` in the backendRef).
4. Two `backendRefs` with `weight: 80` and `weight: 20`.
5. `URLRewrite` with `path.type: ReplacePrefixMatch`. No — `RequestRedirect` and `URLRewrite` cannot share a rule.
6. A rule without `matches` (it matches `PathPrefix /`), i.e. a catch-all rule.

</details>
