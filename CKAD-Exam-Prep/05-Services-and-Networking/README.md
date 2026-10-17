# 05 — Services and Networking (20% of the exam)

Expose applications inside and outside the cluster, route HTTP(S) with Ingress, and restrict traffic with NetworkPolicies — plus the DNS and port knowledge every one of those tasks depends on.

> **Exam environment:** the exam runs Kubernetes **v1.37**. This chapter is written for v1.33+ behaviour, which remains valid on v1.37. Solutions only use tools guaranteed on exam hosts (kubectl with the `k` alias and completion, yq, curl, wget, man) plus busybox/curl Pods for in-cluster tests. Authoritative exam rules: [00 Exam Overview and Setup](../00-Exam-Overview-and-Setup/README.md). Kit start page: [README](../README.md).

## Official competencies (CKAD curriculum)

**Services and Networking — 20%**

- Demonstrate basic understanding of NetworkPolicies
- Provide and troubleshoot access to applications via services
- Use Ingress rules to expose applications

## Competency → files → exam frequency

| Competency | File(s) | Exam frequency |
|---|---|---|
| Provide and troubleshoot access to applications via services | [01-networking-fundamentals.md](01-networking-fundamentals.md), [02-services.md](02-services.md) | High |
| Use Ingress rules to expose applications | [03-ingress.md](03-ingress.md) | High |
| Demonstrate basic understanding of NetworkPolicies | [04-network-policies.md](04-network-policies.md) | High |
| Gateway API — 🧊 **bonus, not in the CKAD curriculum** (CKA since 2025). In the CKAD only kubernetes.io's [Gateway page](https://kubernetes.io/docs/concepts/services-networking/gateway/) is usable; `gateway-api.sigs.k8s.io` is allowed for the CKA only | [05-gateway-api.md](05-gateway-api.md) | Low (bonus) |

Sub-topics, most frequent first (practice question numbers in brackets):

| Sub-topic | Where | Frequency |
|---|---|---|
| Expose a Deployment/Pod: ClusterIP, NodePort with a fixed nodePort | [02](02-services.md) (Q1, Q2) | High |
| Fix a Service: selector, targetPort, named port | [02](02-services.md) troubleshooting (Q3, Q4) | High |
| NetworkPolicy: allow from labelled Pods, default deny | [04](04-network-policies.md) (Q5, Q6) | High |
| NetworkPolicy: label Pods to fit existing policies | [04](04-network-policies.md) worked example (Q7) | High |
| Ingress: path and host rules with `kubectl create ingress` | [03](03-ingress.md) (Q8) | High |
| Ingress TLS from a Secret | [03](03-ingress.md) (Q9) | High |
| Egress restrictions + DNS | [04](04-network-policies.md) (Q10) | Medium |
| Allow from namespaces; AND vs OR selectors | [04](04-network-policies.md) (Q11, Q18) | Medium |
| Fix a broken Ingress | [03](03-ingress.md) troubleshooting (Q12) | Medium |
| DNS names, headless Services, StatefulSet Pod DNS | [01](01-networking-fundamentals.md), [02](02-services.md) (Q13, Q15) | Medium |
| Multi-port Services, named targetPorts | [02](02-services.md) (Q14) | Medium |
| Ingress default backend, Exact paths, annotations | [03](03-ingress.md) (Q16) | Medium |
| No ready endpoints because readiness fails | [02](02-services.md) troubleshooting (Q17) | Medium |
| ExternalName, LoadBalancer, externalTrafficPolicy | [02](02-services.md) (Q19, Q20) | Medium |
| ipBlock / endPort, selector-less Service + EndpointSlice | [04](04-network-policies.md), [02](02-services.md) (Q21, Q22) | Low |
| Session affinity, traffic policies, trafficDistribution, port-forward | [02](02-services.md) (Q23) | Low |
| ingress-nginx rewrite-target (controller-specific annotations) | [03](03-ingress.md) (Q24) | Low |
| dnsPolicy / dnsConfig, ndots, kube-proxy modes | [01](01-networking-fundamentals.md) (Q25) | Low |
| Gateway API (bonus) | [05](05-gateway-api.md) (Q26, Q27) | Low |

## Must know — cannot skip

- [ ] `port` vs `targetPort` vs `nodePort` vs `containerPort`; `targetPort` defaults to `port`
- [ ] `kubectl expose deployment|pod <name> --port --target-port [--type=NodePort|LoadBalancer] [--cluster-ip=None]`
- [ ] `kubectl create service clusterip|nodeport|loadbalancer|externalname` — its selector is always `app=<name>`; fix with `kubectl set selector`
- [ ] Fixed nodePort (30000–32767): `kubectl create service nodeport --node-port=...` or `kubectl patch` after `expose`
- [ ] Verify every Service with `kubectl get endpointslices -l kubernetes.io/service-name=<svc>` (core Endpoints API deprecated since v1.33)
- [ ] The Service troubleshooting checklist: selector/labels, readiness, targetPort, app bound to 127.0.0.1, namespace in the DNS name, NetworkPolicy, protocol
- [ ] DNS: `<svc>.<ns>.svc.cluster.local`; short names only in the same namespace; headless/StatefulSet `<pod>.<svc>.<ns>.svc.cluster.local`
- [ ] Test Pods: `kubectl run tmp --rm -it --image=busybox:1.36 --restart=Never -- wget -qO- --timeout=2 http://svc.ns`, `nc -zv -w 2`, `nslookup`; `curlimages/curl:8.10.1`
- [ ] Ingress v1: `ingressClassName`, required `pathType`, `backend.service.name` + `port.number|name` (the **Service** port)
- [ ] `kubectl create ingress --rule="host/path*=svc:port,tls=secret"`: `*` = Prefix, no `*` = Exact; `--default-backend`, `--annotation`, `--class`
- [ ] Path precedence: element-wise Prefix, longest match wins, Exact beats Prefix on a tie; wildcard host = exactly one label
- [ ] TLS: `kubectl create secret tls` in the Ingress's namespace; test with `curl -H "Host: ..."` (HTTP) and `curl -k --resolve` (HTTPS)
- [ ] NetworkPolicy model: isolation per direction once selected, additive allow-lists, both ends must allow, stateful replies
- [ ] AND vs OR in `from`/`to`; `podSelector` vs `namespaceSelector` vs both; `kubernetes.io/metadata.name`
- [ ] Default deny (ingress/egress/all), DNS egress on UDP+TCP 53, always explicit `policyTypes`
- [ ] Make traffic work by labelling Pods (or namespaces) to match existing policies — without editing them

## Nice to know (low frequency, still covered)

- ExternalName caveats (no IPs, Host/SNI), headless Services without selectors, selector-less Services + manual EndpointSlices — [02](02-services.md)
- Session affinity, `externalTrafficPolicy`, `internalTrafficPolicy`, `trafficDistribution` (`PreferSameZone`/`PreferSameNode`), LoadBalancer knobs — [02](02-services.md)
- `dnsPolicy`/`dnsConfig`, ndots, hostNetwork DNS, hostname/subdomain, SRV and Pod A records — [01](01-networking-fundamentals.md)
- kube-proxy modes: iptables (default), nftables (GA v1.33), ipvs (deprecated v1.35) — [01](01-networking-fundamentals.md)
- IngressClass default annotation, resource backends, ingress-nginx annotations (rewrite-target, ssl-redirect, canary) — [03](03-ingress.md)
- `ipBlock` + `except`, `endPort` ranges, node and hostNetwork traffic in policies, `kubectl describe netpol` reading — [04](04-network-policies.md)
- Ingress API frozen, ingress-nginx retired (Nov 2025 announcement, maintenance ended March 2026), Gateway API and ingress2gateway — [03](03-ingress.md), [05](05-gateway-api.md)

## Recommended study order

| # | Step | Time |
|---|---|---|
| 1 | [01-networking-fundamentals.md](01-networking-fundamentals.md) — ports, DNS, test tools | 40 min |
| 2 | [02-services.md](02-services.md) + practice Q1–Q4, Q13–Q15, Q17 | 90 min |
| 3 | [04-network-policies.md](04-network-policies.md) + lab [yaml/test-pods.yaml](yaml/test-pods.yaml) + Q5–Q7, Q10, Q11, Q18 | 100 min |
| 4 | [03-ingress.md](03-ingress.md) + Q8, Q9, Q12, Q16 | 75 min |
| 5 | [commands.md](commands.md) skim + Q19–Q25 | 60 min |
| 6 | [05-gateway-api.md](05-gateway-api.md) + Q26–Q27 — bonus, only with time to spare | 30 min |

Total ≈ 6.5 hours. Re-do the 🔥 questions against the clock the day before the exam.

## Lab prerequisites

- A cluster whose CNI **enforces** NetworkPolicy (setup options in [00](../00-Exam-Overview-and-Setup/README.md)); prove it with [yaml/netpol-default-deny-ingress.yaml](yaml/netpol-default-deny-ingress.yaml) and the test commands in [04](04-network-policies.md).
- An Ingress controller. The examples use IngressClass `nginx` (ingress-nginx is retired but fine for practice); with another controller substitute the class from `kubectl get ingressclass`.
- Optional: Gateway API CRDs + an implementation for [05](05-gateway-api.md).

## Files in this chapter

| File | Content |
|---|---|
| [01-networking-fundamentals.md](01-networking-fundamentals.md) | Network model, port fields, kube-proxy modes, CoreDNS records, resolv.conf/ndots, dnsPolicy/dnsConfig, test tools |
| [02-services.md](02-services.md) | Service types, EndpointSlices, named/multi ports, affinity, traffic policies, headless, ExternalName, selector-less Services, expose vs create service, port-forward, troubleshooting checklist |
| [03-ingress.md](03-ingress.md) | Ingress vs controller, IngressClass, rules, defaultBackend, path precedence, TLS, nginx annotations, `kubectl create ingress`, testing, troubleshooting, ingress-nginx retirement |
| [04-network-policies.md](04-network-policies.md) | Policy model, anatomy, selector semantics, AND vs OR, recipes, testing method, reading `describe`, label-the-Pods exam pattern |
| [05-gateway-api.md](05-gateway-api.md) | Bonus: resource model, HTTPRoute matches/filters/weights, cross-namespace rules, install, Ingress mapping, ingress2gateway |
| [commands.md](commands.md) | Grouped command reference (create, generate, modify, inspect, verify, DNS, debug, Gateway API, cleanup) |
| [practice-questions.md](practice-questions.md) | 27 exam-style tasks with solutions and verification + must-know summary |

### yaml/ index

| File | What it shows |
|---|---|
| [yaml/svc-clusterip.yaml](yaml/svc-clusterip.yaml) | Deployment `web` + ClusterIP Service (base for other Service examples) |
| [yaml/svc-nodeport.yaml](yaml/svc-nodeport.yaml) | NodePort Service with fixed `nodePort: 30080` |
| [yaml/svc-loadbalancer.yaml](yaml/svc-loadbalancer.yaml) | LoadBalancer Service, `externalTrafficPolicy`, LB-specific fields |
| [yaml/svc-externalname.yaml](yaml/svc-externalname.yaml) | ExternalName (DNS CNAME) Service |
| [yaml/svc-headless.yaml](yaml/svc-headless.yaml) | Headless Service + StatefulSet with per-Pod DNS names |
| [yaml/svc-multiport-named-targetport.yaml](yaml/svc-multiport-named-targetport.yaml) | Two-container Deployment, multi-port Service with named targetPorts |
| [yaml/svc-without-selector-endpointslice.yaml](yaml/svc-without-selector-endpointslice.yaml) | Selector-less Service + manually managed EndpointSlice |
| [yaml/svc-affinity-and-traffic-policies.yaml](yaml/svc-affinity-and-traffic-policies.yaml) | sessionAffinity, internalTrafficPolicy, trafficDistribution, externalTrafficPolicy |
| [yaml/pod-dns-config.yaml](yaml/pod-dns-config.yaml) | dnsPolicy + dnsConfig (merge and None), hostNetwork DNS, hostname/subdomain records |
| [yaml/ingress-backends.yaml](yaml/ingress-backends.yaml) | Echo backends `app-svc`, `api-svc`, `fallback-svc` used by all Ingress examples |
| [yaml/ingress-single-backend.yaml](yaml/ingress-single-backend.yaml) | Minimal Ingress: one Prefix `/` rule |
| [yaml/ingress-path-fanout.yaml](yaml/ingress-path-fanout.yaml) | Path fan-out, Prefix vs Exact, longest match, port by name |
| [yaml/ingress-host-based.yaml](yaml/ingress-host-based.yaml) | Name-based virtual hosts incl. wildcard host |
| [yaml/ingress-tls.yaml](yaml/ingress-tls.yaml) | TLS termination with a `kubernetes.io/tls` Secret |
| [yaml/ingress-default-backend.yaml](yaml/ingress-default-backend.yaml) | `spec.defaultBackend` plus a rule |
| [yaml/ingress-nginx-rewrite.yaml](yaml/ingress-nginx-rewrite.yaml) | ingress-nginx rewrite-target with regex capture groups |
| [yaml/ingressclass.yaml](yaml/ingressclass.yaml) | IngressClass with the default-class annotation |
| [yaml/test-pods.yaml](yaml/test-pods.yaml) | NetworkPolicy lab: namespaces, servers and labelled client Pods |
| [yaml/netpol-default-deny-ingress.yaml](yaml/netpol-default-deny-ingress.yaml) | Default deny ingress |
| [yaml/netpol-default-deny-egress.yaml](yaml/netpol-default-deny-egress.yaml) | Default deny egress (also blocks DNS) |
| [yaml/netpol-default-deny-all.yaml](yaml/netpol-default-deny-all.yaml) | Default deny ingress + egress |
| [yaml/netpol-allow-from-pods.yaml](yaml/netpol-allow-from-pods.yaml) | Allow ingress only from labelled Pods on one port |
| [yaml/netpol-allow-from-namespace.yaml](yaml/netpol-allow-from-namespace.yaml) | Allow from a namespace via `kubernetes.io/metadata.name` |
| [yaml/netpol-and-vs-or.yaml](yaml/netpol-and-vs-or.yaml) | AND vs OR selectors with an expected-results matrix |
| [yaml/netpol-allow-dns-egress.yaml](yaml/netpol-allow-dns-egress.yaml) | DNS egress (UDP+TCP 53) to CoreDNS |
| [yaml/netpol-egress-to-db-only.yaml](yaml/netpol-egress-to-db-only.yaml) | Egress only to the DB (+ DNS) and DB ingress only from the API |
| [yaml/netpol-ipblock.yaml](yaml/netpol-ipblock.yaml) | ipBlock with except, endPort port range |
| [yaml/netpol-allow-all-ingress.yaml](yaml/netpol-allow-all-ingress.yaml) | Allow-all ingress and allow-all egress |
| [yaml/gateway-api/gateway.yaml](yaml/gateway-api/gateway.yaml) | GatewayClass + shared Gateway (HTTP/HTTPS listeners, allowedRoutes) |
| [yaml/gateway-api/httproute-basic.yaml](yaml/gateway-api/httproute-basic.yaml) | HTTPRoute attached across namespaces, path rule + catch-all |
| [yaml/gateway-api/httproute-canary-weights.yaml](yaml/gateway-api/httproute-canary-weights.yaml) | Weighted backends for canary / blue-green |
| [yaml/gateway-api/httproute-header-match.yaml](yaml/gateway-api/httproute-header-match.yaml) | Header, query-parameter and method matching |
| [yaml/gateway-api/httproute-filters.yaml](yaml/gateway-api/httproute-filters.yaml) | RequestRedirect, URLRewrite, RequestHeaderModifier |
| [yaml/gateway-api/referencegrant.yaml](yaml/gateway-api/referencegrant.yaml) | ReferenceGrant for a cross-namespace backend |
| [yaml/broken/q03-svc-no-endpoints.yaml](yaml/broken/q03-svc-no-endpoints.yaml) | Practice Q3 setup (intentionally broken Service selector) |
| [yaml/broken/q04-svc-wrong-ports.yaml](yaml/broken/q04-svc-wrong-ports.yaml) | Practice Q4 setup (wrong targetPort and named port) |
| [yaml/broken/q12-ingress-broken.yaml](yaml/broken/q12-ingress-broken.yaml) | Practice Q12 setup (broken Ingress) |
| [yaml/broken/q17-readiness-no-endpoints.yaml](yaml/broken/q17-readiness-no-endpoints.yaml) | Practice Q17 setup (failing readiness probe) |
| [yaml/broken/q18-netpol-or-instead-of-and.yaml](yaml/broken/q18-netpol-or-instead-of-and.yaml) | Practice Q18 setup (OR instead of AND) |
| [yaml/practice-setup/q07-netpol-label-pods.yaml](yaml/practice-setup/q07-netpol-label-pods.yaml) | Practice Q7 setup (existing policies, Pod to label) |
| [yaml/practice-setup/q13-statefulset-no-service.yaml](yaml/practice-setup/q13-statefulset-no-service.yaml) | Practice Q13 setup (StatefulSet without its headless Service) |
| [yaml/practice-setup/q14-shop-deployment.yaml](yaml/practice-setup/q14-shop-deployment.yaml) | Practice Q14 setup (Deployment with named ports) |

## Related chapters

- Probes, debugging, logs: [03 Application Observability and Maintenance](../03-Application-Observability-and-Maintenance/README.md)
- Canary / blue-green with Services and Ingress: [02 Application Deployment](../02-Application-Deployment/README.md)
- Labels, selectors, jsonpath, kubectl speed: [06 Cross-Cutting Skills and Bonus Topics](../06-Cross-Cutting-Skills-and-Bonus-Topics/README.md)
- Production design beyond the exam: [08 Architect Notes](../08-Architect-Notes/README.md)
