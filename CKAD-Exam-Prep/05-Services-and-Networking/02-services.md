# 02 — Services: Types, EndpointSlices, Traffic Policies and Troubleshooting

**Why it matters:** "Provide and troubleshoot access to applications via services" is the core competency of this domain. Expect to expose workloads with the right type and ports — fast, imperatively — and to repair Services that silently send traffic nowhere.

**What the exam expects:** `kubectl expose` / `kubectl create service` fluency, correct `port` / `targetPort` / `nodePort`, selectors that match Pod labels, and a systematic way to find out *why* a Service does not answer.

---

## Core concepts

### What a Service gives you

- A **stable virtual IP** (ClusterIP) and **DNS name** (`<svc>.<ns>.svc.cluster.local`) in front of a changing set of Pods.
- **L4 load balancing** (TCP/UDP/SCTP) across the **ready** Pods matched by the selector — per connection, not per request: a long-lived connection stays on one Pod.
- A Service only selects Pods in **its own namespace**, by label, no matter which controller created them.

### Service types

| Type | Reachable from | ClusterIP | nodePort | Typical use | Notes |
|---|---|---|---|---|---|
| `ClusterIP` (default) | inside the cluster | yes | no | internal APIs, databases, Ingress/Gateway backends | – |
| `NodePort` | `<anyNodeIP>:<nodePort>` and inside | yes | yes, 30000–32767 | labs, simple external access, behind an external LB | a fixed `nodePort` must be free and in range |
| `LoadBalancer` | external LB address, NodePort and inside | yes | yes (unless `allocateLoadBalancerNodePorts: false`) | production L4 exposure on a cloud | needs an LB implementation; otherwise EXTERNAL-IP stays `<pending>` |
| `ExternalName` | inside, DNS only | no | no | alias for an external DNS name | CoreDNS returns a CNAME; no selector, no proxying |
| Headless (`clusterIP: None`) | inside, DNS only | no (`None`) | no | StatefulSets, peer discovery, client-side load balancing | DNS returns the Pod IPs; kube-proxy ignores it |

`LoadBalancer` builds on `NodePort`, which builds on `ClusterIP`.

**NodePort range:** default 30000–32767 (kube-apiserver `--service-node-port-range`). With the default range, auto-assignment uses the upper band (30086–32767) first, leaving 30000–30085 for static picks; an out-of-range or taken `nodePort` is rejected.

### Selectors → EndpointSlices

```text
Service web (selector app=web) --watched by--> EndpointSlice controller --writes--> EndpointSlice web-x7k2p
                                                (all Pods with app=web       labels: kubernetes.io/service-name=web
                                                 in the namespace)           endpoints: 10.244.1.7  ready=true
                                                                                        10.244.2.4  ready=false
kube-proxy, CoreDNS and Ingress controllers read EndpointSlices; only ready endpoints receive traffic.
```

- The Service selector is **equality-based only** (`app: web`), no `matchExpressions`.
- A Service may have several EndpointSlices (default max 100 endpoints each), linked by the label `kubernetes.io/service-name=<svc>`; controller-managed slices carry `endpointslice.kubernetes.io/managed-by=endpointslice-controller.k8s.io`.
- Endpoint conditions: `ready`, `serving`, `terminating`. Not-ready Pods stay listed with `ready: false` — kube-proxy skips them.
- **The core v1 Endpoints API is deprecated since v1.33.** `kubectl get endpoints` still works but warns, lacks dual-stack and truncates at 1000 endpoints. Use EndpointSlices:

```bash
kubectl get endpointslices -l kubernetes.io/service-name=web
kubectl get endpointslices -l kubernetes.io/service-name=web \
  -o jsonpath='{range .items[*].endpoints[*]}{.addresses[0]}{" ready="}{.conditions.ready}{"\n"}{end}'
```

### Named targetPorts

`targetPort` may be a **containerPort name**. The name is resolved per Pod, so the container port number can change (or differ between Pods during a migration) without touching the Service.

```yaml
# Pod template: spec.containers[].ports
ports:
- name: http-web
  containerPort: 8080
```

```yaml
# Service: spec.ports
ports:
- name: http
  port: 80
  targetPort: http-web      # resolved to 8080 in each selected Pod
```

If no selected Pod has a container port with that name, the Service has no usable endpoint port: traffic fails although the Pods are fine. Container port names are IANA_SVC_NAME: max 15 characters, lowercase alphanumerics and `-`, at least one letter.

### Multi-port Services

- With two or more ports, **every port needs a unique `name`** (lowercase alphanumerics and `-`, starting and ending alphanumeric; `web`, `123-abc` are valid, `123_abc`, `-web` are not).
- Port names feed the SRV records (`_http._tcp.<svc>...`) and Ingress/Gateway backends may refer to them (`port.name: http`).
- `kubectl create service clusterip shop --tcp=80:8080,9090:9090` auto-names the ports `80-8080` and `9090-9090`.

Full example: [yaml/svc-multiport-named-targetport.yaml](yaml/svc-multiport-named-targetport.yaml).

### Session affinity

```yaml
spec:
  sessionAffinity: ClientIP        # None (default) | ClientIP
  sessionAffinityConfig:
    clientIP:
      timeoutSeconds: 600          # default 10800 (3 hours)
```

Same client IP → same Pod until the timeout. Behind NAT or a load balancer many clients may share one IP. `kubectl expose ... --session-affinity=ClientIP` sets it imperatively.

### Traffic policies

| Field | Applies to | Values | Effect |
|---|---|---|---|
| `externalTrafficPolicy` | NodePort, LoadBalancer | `Cluster` (default) · `Local` | `Local`: client source IP preserved, no second hop; only nodes with a **local ready Pod** forward (LoadBalancers health-check nodes via `healthCheckNodePort`). `Cluster`: any node forwards to any Pod, source IP is SNAT-ed |
| `internalTrafficPolicy` | in-cluster traffic | `Cluster` (default) · `Local` | `Local`: clients only reach endpoints on **their own node**; no local endpoint → traffic dropped |
| `trafficDistribution` | in-cluster traffic | see below | a *preference* for topologically close endpoints, falling back cluster-wide |

`trafficDistribution` (brief — version-dependent, check the docs for your cluster's version):

| Value | Status |
|---|---|
| `PreferClose` | field GA in v1.33 ("prefer topologically close", in practice same zone); current docs list it as a **deprecated alias** of `PreferSameZone` |
| `PreferSameZone`, `PreferSameNode` | added by KEP-3015: alpha v1.33, beta (on by default) v1.34, GA v1.35 — use these on current clusters such as the exam's v1.37. `PreferSameNode` falls back to same zone, then cluster-wide |

The older annotation-based mechanism is Topology Aware Routing (`service.kubernetes.io/topology-mode: Auto`).

Examples: [yaml/svc-affinity-and-traffic-policies.yaml](yaml/svc-affinity-and-traffic-policies.yaml) · [yaml/svc-loadbalancer.yaml](yaml/svc-loadbalancer.yaml).

### Headless Services

- `clusterIP: None` — no virtual IP, no kube-proxy load balancing; DNS answers with the Pod IPs (clients choose).
- **With a selector:** EndpointSlices are created; A/AAAA records point at each **ready** Pod; a StatefulSet with `serviceName: <svc>` gets per-Pod names `<pod>.<svc>.<ns>.svc.cluster.local`.
- **Without a selector:** no EndpointSlices are created for you; DNS serves A/AAAA records for the ready endpoints of EndpointSlices *you* create. `port` must equal `targetPort` here.
- `publishNotReadyAddresses: true` publishes not-ready Pods too (cluster bootstrap / peer discovery).
- `clusterIP` is **immutable**: you cannot turn an existing ClusterIP Service into a headless one — recreate it.

Example: [yaml/svc-headless.yaml](yaml/svc-headless.yaml).

### ExternalName

```yaml
spec:
  type: ExternalName
  externalName: db.example.com
```

- Pure DNS: `my-db.<ns>.svc.cluster.local` → CNAME `db.example.com`. No selector, ClusterIP, EndpointSlices or ports needed.
- An IP address in `externalName` is treated as a DNS name made of digits and is **not resolved** — use a selector-less Service + EndpointSlice for IPs.
- HTTP `Host` headers and TLS SNI still carry the name the client used, which the external server may reject.

Example: [yaml/svc-externalname.yaml](yaml/svc-externalname.yaml).

### Services without selectors + a manual EndpointSlice

Use this to give a stable in-cluster name to something Kubernetes does not manage (VM, external DB, migration target) **by IP**:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: legacy-db
spec:
  ports:
  - name: postgres
    port: 5432
    targetPort: 5432
---
apiVersion: discovery.k8s.io/v1
kind: EndpointSlice
metadata:
  name: legacy-db-1
  labels:
    kubernetes.io/service-name: legacy-db                  # the link to the Service
    endpointslice.kubernetes.io/managed-by: cluster-admins # anything except the controller's value
addressType: IPv4
ports:
- name: postgres                                           # must match the Service port name
  protocol: TCP
  port: 5432
endpoints:
- addresses:
  - "10.10.0.15"
```

Endpoint IPs must not be loopback (127.0.0.0/8, ::1), link-local (169.254.0.0/16, 224.0.0.0/24, fe80::/64) or another Service's ClusterIP. Full file: [yaml/svc-without-selector-endpointslice.yaml](yaml/svc-without-selector-endpointslice.yaml).

### LoadBalancer specifics

- The address appears in `status.loadBalancer.ingress[]` (`kubectl get svc` EXTERNAL-IP). On kind/minikube/bare metal it stays `<pending>` until something implements LoadBalancers (cloud-provider-kind, `minikube tunnel`, MetalLB, ...). The Service still works as a NodePort meanwhile.
- `spec.loadBalancerIP` is **deprecated since v1.24** — use the provider's annotations.
- `loadBalancerClass` selects a non-default implementation (immutable); `loadBalancerSourceRanges` restricts client CIDRs (where supported); `allocateLoadBalancerNodePorts: false` skips nodePorts.

---

## Key fields / syntax

```yaml
apiVersion: v1
kind: Service
metadata:
  name: web
  namespace: prod
spec:
  type: ClusterIP                  # ClusterIP | NodePort | LoadBalancer | ExternalName
  selector:                        # equality-based; omit it => you manage EndpointSlices yourself
    app: web
  ports:
  - name: http                     # required when there is more than one port
    protocol: TCP                  # TCP (default) | UDP | SCTP
    appProtocol: http              # optional hint for LBs / meshes
    port: 80                       # Service port (clients)
    targetPort: http               # Pod port: number or containerPort name; default = port
    # nodePort: 30080              # NodePort / LoadBalancer only
  # clusterIP: None                # headless (immutable; set at creation only)
  # sessionAffinity: ClientIP
  # externalTrafficPolicy: Local   # NodePort / LoadBalancer only
  # internalTrafficPolicy: Local
  # publishNotReadyAddresses: true
```

| File | Shows |
|---|---|
| [yaml/svc-clusterip.yaml](yaml/svc-clusterip.yaml) | Deployment `web` + ClusterIP Service (base for the other examples) |
| [yaml/svc-nodeport.yaml](yaml/svc-nodeport.yaml) | NodePort with a fixed `nodePort: 30080` |
| [yaml/svc-loadbalancer.yaml](yaml/svc-loadbalancer.yaml) | LoadBalancer, `externalTrafficPolicy`, LB knobs |
| [yaml/svc-externalname.yaml](yaml/svc-externalname.yaml) | ExternalName CNAME |
| [yaml/svc-headless.yaml](yaml/svc-headless.yaml) | Headless Service + StatefulSet DNS |
| [yaml/svc-multiport-named-targetport.yaml](yaml/svc-multiport-named-targetport.yaml) | Two named ports, named targetPorts |
| [yaml/svc-without-selector-endpointslice.yaml](yaml/svc-without-selector-endpointslice.yaml) | Selector-less Service + manual EndpointSlice |
| [yaml/svc-affinity-and-traffic-policies.yaml](yaml/svc-affinity-and-traffic-policies.yaml) | sessionAffinity, internal/externalTrafficPolicy, trafficDistribution |

---

## Imperative commands

### `kubectl expose` vs `kubectl create service`

| | `kubectl expose <kind> <name>` | `kubectl create service <type> <name>` |
|---|---|---|
| Needs an existing object | yes: pod, deployment, replicaset, service, replicationcontroller | no |
| Selector | **copied** from the object (Pod labels / Deployment `matchLabels`); override with `--selector` | **always `app=<service-name>`** — fix it if your Pods are labelled differently |
| Ports | `--port`, `--target-port` (if `--port` is omitted it is copied from the object's container ports) | `--tcp=<port>:<targetPort>[,...]`, auto-named `80-8080` |
| Type | `--type=ClusterIP\|NodePort\|LoadBalancer` | subcommand: `clusterip`, `nodeport`, `loadbalancer`, `externalname` |
| Fixed nodePort | not possible — patch afterwards | `--node-port=30080` (nodeport only) |
| Headless | `--cluster-ip=None` | `clusterip --clusterip=None` |
| ExternalName | – | `externalname --external-name=db.example.com` |

```bash
# expose: selector comes from the object
kubectl expose deployment web --port=80 --target-port=8080                      # ClusterIP "web"
kubectl expose deployment web --name=web-np --type=NodePort --port=80 --target-port=8080
kubectl expose deployment web --name=web-lb --type=LoadBalancer --port=80 --target-port=8080
kubectl expose deployment web --name=web-hl --cluster-ip=None --port=80 --target-port=8080
kubectl expose deployment web --name=web-sticky --port=80 --target-port=8080 --session-affinity=ClientIP
kubectl expose pod nginx --name=nginx-svc --port=80                              # selector = the Pod's labels
kubectl run nginx --image=nginx:1.27 --port=80 --expose                          # Pod + ClusterIP Service (selector run=nginx)

# create service: selector is app=<name>
kubectl create service clusterip web --tcp=80:8080
kubectl create service clusterip web-hl --clusterip=None --tcp=80:8080
kubectl create service nodeport web-np --tcp=80:8080 --node-port=30080
kubectl create service loadbalancer web-lb --tcp=80:8080
kubectl create service externalname my-db --external-name=db.example.com

# Generate YAML first when you need fields the flags cannot set
kubectl expose deployment web --port=80 --target-port=8080 --dry-run=client -o yaml > svc.yaml
kubectl create service nodeport web-np --tcp=80:8080 --node-port=30080 --dry-run=client -o yaml > svc-np.yaml
```

Generated by `kubectl create service clusterip web --tcp=80:8080 --dry-run=client -o yaml` (trimmed):

```yaml
apiVersion: v1
kind: Service
metadata:
  labels:
    app: web
  name: web
spec:
  ports:
  - name: 80-8080
    port: 80
    protocol: TCP
    targetPort: 8080
  selector:
    app: web            # <- app=<service name>, whatever your Pods are labelled
  type: ClusterIP
```

### Modify

```bash
kubectl patch svc web-np -p '{"spec":{"ports":[{"port":80,"nodePort":30080}]}}'   # set nodePort (ports merge on "port")
kubectl patch svc web -p '{"spec":{"type":"NodePort"}}'                            # ClusterIP -> NodePort (random nodePort)
kubectl set selector svc web app=web,tier=frontend                                 # replace the whole selector
kubectl patch svc web --type=json -p '[{"op":"replace","path":"/spec/ports/0/targetPort","value":8080}]'
kubectl edit svc web                                                               # anything else
kubectl get svc web -o yaml > svc.yaml && kubectl replace --force -f svc.yaml      # immutable fields (clusterIP)
```

### port-forward

```bash
kubectl port-forward svc/web 8080:80                       # localhost:8080 -> Service port 80 -> ONE Pod's targetPort
kubectl port-forward deploy/web 8080:80                    # picks one Pod of the Deployment
kubectl port-forward pod/web-7d9c-abcde 8080:8080          # a specific Pod (container port)
kubectl port-forward svc/web 8080:80 --address 0.0.0.0     # listen on all local interfaces, not only 127.0.0.1
curl -s http://127.0.0.1:8080
```

`port-forward` tunnels through the API server and kubelet into **one** Pod and connects to the port on the Pod's localhost. It bypasses Service load balancing, session affinity and NetworkPolicies — a working port-forward does **not** prove the Service works. TCP only.

---

## Troubleshooting checklist

Work top to bottom; each step has the command that confirms or rules out the cause.

```text
client Pod --DNS--> Service exists? right port? --> EndpointSlice has READY addresses?
   --> selector matches Pod labels? --> Pods Ready? --> targetPort = port the app listens on (0.0.0.0)?
   --> protocol right? --> NetworkPolicy allows client -> Pod:targetPort?
```

| # | Cause | Typical symptom | Confirm with | Fix |
|---|---|---|---|---|
| 1 | **Selector ≠ Pod labels** (typo, extra key, wrong value) | refused at once (no endpoints) | `kubectl get svc web -o wide` (SELECTOR) → `kubectl get pods -l app=web --show-labels` returns nothing; `kubectl get endpointslices -l kubernetes.io/service-name=web` shows no addresses | `kubectl set selector svc web app=web` or edit |
| 2 | **No ready endpoints: readiness probe fails** | Pods `0/1 READY`; refused | `kubectl get pods`; `kubectl describe pod <pod>` → Events `Readiness probe failed`; endpoint jsonpath above shows `ready=false` | fix the probe (port/path) or the app |
| 3 | **Wrong targetPort** (number, or a name no container has) | refused; endpoints look fine | `kubectl get svc web -o jsonpath='{.spec.ports}'` vs `kubectl get pod <pod> -o jsonpath='{.spec.containers[*].ports}'`; `kubectl get endpointslices -l kubernetes.io/service-name=web -o yaml` (`ports:`) | patch `targetPort` |
| 4 | **App listens on 127.0.0.1** | refused via Pod IP and Service, yet port-forward works | `kubectl debug -it <pod> --image=busybox:1.36 -- netstat -tln` shows `127.0.0.1:8080` instead of `0.0.0.0:8080` / `:::8080`; `kubectl exec client -- wget -qO- --timeout=2 http://<podIP>:8080` fails | configure the app to bind `0.0.0.0` |
| 5 | **Wrong namespace in the DNS name** | `bad address` / NXDOMAIN | `kubectl exec client -- cat /etc/resolv.conf` (first search domain = client's namespace); `kubectl get svc -A \| grep web` | use `web.<ns>` or the FQDN |
| 6 | **NetworkPolicy blocks the client** | **timeout** (not refused), often only for some clients | `kubectl get netpol -n <ns>`; `kubectl describe netpol -n <ns>`; repeat the test from a Pod with the allowed labels | adjust policy or client labels — see [04](04-network-policies.md) |
| 7 | **Wrong protocol** (Service TCP, app UDP or vice versa) | no reply at all | `kubectl get svc web -o jsonpath='{.spec.ports[*].protocol}'` vs `kubectl get pod <pod> -o jsonpath='{.spec.containers[*].ports[*].protocol}'` | set `protocol: UDP` (per port) |
| 8 | **Client uses the wrong port** (targetPort or nodePort against the ClusterIP) | refused / timeout | `kubectl get svc web` → PORT(S) `80:30080/TCP` = port:nodePort | call `port` in-cluster, `nodePort` on node IPs |
| 9 | **Wrong type for the access path** | works inside, not outside | `kubectl get svc web` TYPE, EXTERNAL-IP `<pending>` | NodePort / LoadBalancer / Ingress |
| 10 | **Cluster plumbing** (rare in the exam) | nothing works anywhere | `kubectl -n kube-system get pods -l k8s-app=kube-dns`; `kubectl -n kube-system get ds kube-proxy` | escalate / fix CoreDNS, kube-proxy |

Rules of thumb: **refused** = something answered "nothing here" (no endpoints — kube-proxy rejects those — or a closed port); **timeout** = packets dropped (NetworkPolicy, routing). And a Service selecting the wrong Pods also "works" — compare the endpoint count with the Pods you expect.

---

## Exam traps & tips

> **Exam tip:** `kubectl create service ... <name>` sets the selector to `app=<name>`. If the Deployment's Pods are `app=backend` and you named the Service `api`, the Service has zero endpoints. Prefer `kubectl expose`, or fix with `kubectl set selector`.

> **Exam tip:** always check `kubectl get endpointslices -l kubernetes.io/service-name=<svc>` right after creating a Service. No addresses → selector or readiness problem; stop and fix before testing anything else.

> **Exam tip:** `kubectl expose` cannot set `nodePort`. Either patch it afterwards or use `kubectl create service nodeport --node-port` and fix the selector.

- `targetPort` defaults to `port`; omitting `--target-port` is the most common silent bug.
- `kubectl expose deployment web` without `--port` fails if the Pod template declares no `containerPort` (nothing to copy).
- A multi-port Service without port names is rejected by the API.
- Named `targetPort` must match a `containerPort` **name** in the Pod template — names are case-sensitive and max 15 characters.
- `clusterIP` (including `None`) is immutable → `kubectl replace --force -f` with an edited manifest.
- `nodePort` outside 30000–32767 (default range) is rejected; one already used by another Service too.
- On kind / Docker Desktop the node IP may not be reachable from your laptop — test the NodePort from a Pod: `curl http://<nodeInternalIP>:30080`.
- EXTERNAL-IP `<pending>` is normal without an LB implementation; the task may only want the Service object.
- ExternalName with an IP does not work; headless + manual EndpointSlice (or selector-less Service) does.
- `kubectl get endpoints` prints a deprecation warning on v1.33+ — that is not your error.

---

## Architect notes

- **HTTP goes through L7:** ClusterIP Services behind one Ingress/Gateway instead of one cloud LoadBalancer per Service (cost, IP sprawl, TLS in one place).
- **`externalTrafficPolicy: Local`** preserves client IPs (audit, rate limiting, geo) and removes a hop — pair it with Pods spread across nodes (topology spread constraints) or traffic concentrates on few nodes.
- **Long-lived connections** (gRPC, HTTP/2, WebSockets) are balanced once per connection by a Service; use L7 balancing (Gateway/mesh) or headless + client-side load balancing.
- **Zone-aware routing** (`trafficDistribution`) cuts cross-zone data-transfer cost and latency, but can overload a zone with few replicas — keep replicas per zone balanced.
- **Graceful shutdown:** terminating endpoints are drained via EndpointSlice conditions; add a short `preStop` sleep so load balancers and kube-proxy catch up before the process exits.
- **Migrate tooling off Endpoints** (deprecated v1.33): scripts, operators and monitors should read EndpointSlices (dual-stack, no 1000-endpoint truncation).
- **`spec.externalIPs` is a security risk** (CVE-2020-8554: traffic interception); block it with the `DenyServiceExternalIPs` admission plugin or a ValidatingAdmissionPolicy.
- **Selector-less Services + EndpointSlices** are a clean way to model external dependencies, so apps keep using cluster DNS names while the backend moves into the cluster later.

---

## Docs to bookmark

- Service: https://kubernetes.io/docs/concepts/services-networking/service/
- EndpointSlices: https://kubernetes.io/docs/concepts/services-networking/endpoint-slices/
- Virtual IPs and Service proxies (traffic policies, session affinity): https://kubernetes.io/docs/reference/networking/virtual-ips/
- Debug Services: https://kubernetes.io/docs/tasks/debug/debug-application/debug-service/
- Using source IP (externalTrafficPolicy): https://kubernetes.io/docs/tutorials/services/source-ip/
- Topology Aware Routing: https://kubernetes.io/docs/concepts/services-networking/topology-aware-routing/
- Port forwarding: https://kubernetes.io/docs/tasks/access-application-cluster/port-forward-access-application-cluster/
- `kubectl expose`: https://kubernetes.io/docs/reference/kubectl/generated/kubectl_expose/
- `kubectl create service nodeport`: https://kubernetes.io/docs/reference/kubectl/generated/kubectl_create/kubectl_create_service_nodeport/

Related: probes and debugging in [03 Observability and Maintenance](../03-Application-Observability-and-Maintenance/README.md); labels/selectors and jsonpath in [06 Cross-Cutting Skills](../06-Cross-Cutting-Skills-and-Bonus-Topics/README.md).

---

## Quick self-check

1. `kubectl create service clusterip api --tcp=80:8080` is meant for Deployment `backend` (Pods `app=backend`). Why are there no endpoints, and what is the one-command fix?
2. Which Service types get a ClusterIP?
3. What do you gain and what do you risk with `externalTrafficPolicy: Local`?
4. How do you create a headless Service with `kubectl expose`? Can you convert an existing ClusterIP Service in place?
5. How does kube-proxy learn the backends of a Service that has no selector?
6. A port-forward to the Service works, but `wget` from another Pod is refused. Name two likely causes.

<details><summary>Answers</summary>

1. `create service` set the selector to `app=api`. Fix: `kubectl set selector svc api app=backend`.
2. ClusterIP, NodePort and LoadBalancer. Not ExternalName, not headless (`clusterIP: None`).
3. Gain: client source IP preserved, no extra hop. Risk: only nodes with a local ready Pod serve traffic; uneven Pod spread means uneven load (and NodePort access via a node without a Pod fails).
4. `kubectl expose deployment web --name=web-hl --cluster-ip=None --port=80`. No — `clusterIP` is immutable; delete and recreate (`kubectl replace --force`).
5. From EndpointSlices you create, labelled `kubernetes.io/service-name=<svc>`, with port names matching the Service.
6. The app binds `127.0.0.1` (port-forward connects to the Pod's localhost), or a NetworkPolicy blocks the client (port-forward bypasses policies). A wrong `targetPort` is also possible if you port-forwarded to a Pod port directly.

</details>
