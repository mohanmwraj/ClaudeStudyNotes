# 01 — Networking Fundamentals: Pod Network, Ports, kube-proxy and DNS

**Why it matters:** every Services, Ingress and NetworkPolicy task quietly tests these basics: which port number goes in which field, which DNS name works from which namespace, and how to prove connectivity from inside the cluster in seconds. A wrong port or DNS name can cost you a whole task.

**What the exam expects:** pick the right port fields, reach Services by name across namespaces, run a throwaway client Pod (busybox or curl) to test HTTP, TCP and DNS, and read `/etc/resolv.conf` when name resolution fails.

---

## Core concepts

### The Kubernetes network model

| Rule | Consequence |
|---|---|
| Every Pod gets its own IP address (IP-per-Pod) | No port mapping between Pods; two Pods can both listen on :80 |
| Containers in one Pod share one network namespace | They talk over `localhost`; their ports must not clash inside the Pod |
| Every Pod can reach every other Pod, on any node, without NAT (flat network) | The default is **allow all**; NetworkPolicies are the built-in way to restrict it |
| Node agents (kubelet, system daemons) can reach all Pods on their node | Probes keep working even under default-deny NetworkPolicies |
| Pod IPs are ephemeral | Never hard-code them; use Services and DNS |

The model is a contract. The **CNI plugin** (Calico, Cilium, Flannel, kindnet, cloud VPC CNIs, ...) implements Pod networking and, depending on the plugin, enforces NetworkPolicies.

Three separate address ranges — keep them apart:

| Range | Example | Set by | Used for |
|---|---|---|---|
| Node IPs | `172.18.0.2` | infrastructure | NodePort access, kubelet, SSH |
| Pod CIDR | `10.244.0.0/16` | cluster / CNI config (`--cluster-cidr`) | Pod IPs (each node usually gets a slice) |
| Service CIDR | `10.96.0.0/12` | kube-apiserver `--service-cluster-ip-range` | ClusterIPs — virtual, no interface owns them |

### Who implements what

| Concern | API object | Implemented by |
|---|---|---|
| Pod-to-Pod connectivity | – | CNI plugin |
| Stable virtual IP + L4 load balancing | Service | kube-proxy (iptables / ipvs / nftables) or a CNI that replaces it (eBPF) |
| Name resolution | Service and Pod DNS records | CoreDNS (Deployment `coredns`, Service `kube-dns`, namespace `kube-system`) |
| L7 HTTP(S) routing into the cluster | Ingress / Gateway API | Ingress controller / Gateway implementation |
| L3/L4 traffic filtering | NetworkPolicy | the CNI plugin, if it supports policies |

### Ports: containerPort vs port vs targetPort vs nodePort

```text
  from outside the cluster                         from inside the cluster
  http://<any-node-IP>:30080                       http://web.prod.svc.cluster.local:80   or   http://<ClusterIP>:80
            |  nodePort (30000-32767)                          |  port
            |  (NodePort / LoadBalancer only)                  |
            +---------------------------+----------------------+
                                        v
                      Service "web"  -- kube-proxy DNAT to ONE ready endpoint
                                        |  targetPort (number or containerPort NAME)
                                        v
                      Pod 10.244.1.7:8080   <- the app must LISTEN here, on 0.0.0.0 (not 127.0.0.1)
                                        ^
          containerPort: 8080 (name: http) = documentation + a name usable as "targetPort: http";
                                             it does NOT open, publish or restrict anything
```

| Field | Lives in | Meaning | Default / range |
|---|---|---|---|
| `containerPort` | Pod `spec.containers[].ports[]` | Informational list of ports the container listens on; supplies **names** for named targetPorts | Optional — omitting it does not block traffic |
| `port` | Service `spec.ports[]` | Port on the ClusterIP / DNS name — what clients call | Required |
| `targetPort` | Service `spec.ports[]` | Port on the Pod (number or containerPort name) | Defaults to `port` |
| `nodePort` | Service `spec.ports[]` | Port opened on every node | Random from 30000–32767 if omitted |
| `hostPort` | Pod `spec.containers[].ports[]` | Binds a port on the node that runs the Pod | Avoid — limits scheduling |

Mnemonic: clients call **port**, Pods receive on **targetPort**, outsiders use **nodePort**, **containerPort** is a label on the box.

### kube-proxy modes (brief)

kube-proxy runs on every node (usually a DaemonSet) and programs the node so that traffic to `ClusterIP:port` or `NodeIP:nodePort` is translated (DNAT) to one ready endpoint.

| Mode | Platform | Notes |
|---|---|---|
| `iptables` | Linux | Default mode in current releases; one rule chain per Service/endpoint; random backend choice |
| `ipvs` | Linux | Kernel IPVS load balancer with several scheduling algorithms; **deprecated since v1.35** |
| `nftables` | Linux, kernel ≥ 5.13 | iptables successor with better scaling; **GA in v1.33**; not the default yet (the docs say a future release will switch the default) |
| `kernelspace` | Windows | Windows HNS based |

The old `userspace` mode was removed (v1.26). Some CNIs (for example Cilium's kube-proxy replacement) do Service translation themselves with eBPF.

> **Exam tip:** a ClusterIP is virtual. `ping <ClusterIP>` usually fails even when the Service works perfectly — always test with TCP or HTTP (`nc`, `wget`, `curl`).

### DNS with CoreDNS

CoreDNS runs as Deployment `coredns` (Pods labelled `k8s-app=kube-dns`) behind Service `kube-dns` in `kube-system` — the legacy names are kept for compatibility. It watches Services and EndpointSlices and answers for the cluster domain (default `cluster.local`).

| Object | DNS name | Answer |
|---|---|---|
| Service (ClusterIP / NodePort / LoadBalancer) | `<svc>.<ns>.svc.cluster.local` | A/AAAA: the ClusterIP |
| Headless Service (`clusterIP: None`) | `<svc>.<ns>.svc.cluster.local` | A/AAAA: the IPs of all **ready** Pods (no virtual IP) |
| Named Service port | `_<port-name>._<protocol>.<svc>.<ns>.svc.cluster.local`, e.g. `_http._tcp.web.prod.svc.cluster.local` | SRV: port number + `<svc>.<ns>.svc.cluster.local`; for a headless Service one answer per Pod with target `<pod-hostname>.<svc>.<ns>.svc.cluster.local` |
| StatefulSet Pod (governing headless Service) | `<pod-name>.<svc>.<ns>.svc.cluster.local`, e.g. `web-sts-0.web-hl.prod.svc.cluster.local` | A: that Pod's IP |
| Pod with `hostname` + `subdomain` (= name of a headless Service in the same namespace) | `<hostname>.<subdomain>.<ns>.svc.cluster.local` | A: that Pod's IP |
| Any Pod, by IP | `<a-b-c-d>.<ns>.pod.cluster.local`, e.g. `10-244-1-7.prod.pod.cluster.local` | A: the Pod IP (needs CoreDNS `pods insecure`/`verified`; kubeadm's default Corefile uses `pods insecure`) |
| Pod behind a Service (CoreDNS) | `<a-b-c-d>.<svc>.<ns>.svc.cluster.local` | A: the Pod IP |
| ExternalName Service | `<svc>.<ns>.svc.cluster.local` | CNAME: `spec.externalName` |

- Pods get DNS records only while **Ready**, unless the Service sets `publishNotReadyAddresses: true`.
- The cluster domain is configurable (kubelet `clusterDomain`). When in doubt, read the `search` line of `/etc/resolv.conf`.

### /etc/resolv.conf, search domains and ndots

With the default `dnsPolicy: ClusterFirst`, kubelet writes this into every container of a Pod in namespace `prod`:

```text
nameserver 10.96.0.10                                    # ClusterIP of kube-system/kube-dns
search prod.svc.cluster.local svc.cluster.local cluster.local
options ndots:5
```

Resolution from a Pod in `prod`:

| Name typed | Result | Why |
|---|---|---|
| `db` | `db.prod.svc.cluster.local` | 1st search domain = own namespace |
| `db.staging` | `db.staging.svc.cluster.local` | 2nd search domain `svc.cluster.local` |
| `db.staging.svc` | `db.staging.svc.cluster.local` | 3rd search domain `cluster.local` |
| `db.staging.svc.cluster.local` | itself | already fully qualified |
| `db` (meaning the one in `staging`) | the **prod** `db`, or NXDOMAIN | short names resolve only in your own namespace |

`ndots:5`: a name with fewer than 5 dots is first tried with every search suffix, so `api.example.com` costs several failed lookups before the absolute query. A trailing dot (`api.example.com.`) makes a name absolute. Pods with heavy external lookups can lower `ndots` via `dnsConfig`.

### dnsPolicy and dnsConfig

| `dnsPolicy` | Behaviour |
|---|---|
| `ClusterFirst` (**default**) | Cluster DNS (CoreDNS); names outside the cluster domain are forwarded upstream |
| `Default` | Inherit the **node's** resolver config — despite the name it is NOT the default |
| `ClusterFirstWithHostNet` | For `hostNetwork: true` Pods that still need cluster DNS (with `ClusterFirst` they silently fall back to `Default`) |
| `None` | Ignore the cluster's DNS settings; everything comes from `dnsConfig` (at least one nameserver) |

`dnsConfig` is merged into what the policy generates, or is the whole configuration with `None`:

| Field | Limits / notes |
|---|---|
| `nameservers` | up to 3 IP addresses |
| `searches` | up to 32 domains, 2048 characters in total; duplicates removed |
| `options` | list of `name` + optional **string** `value` (`ndots`, `edns0`, `timeout`, ...) |

```yaml
spec:
  dnsPolicy: "None"
  dnsConfig:
    nameservers:
    - 192.0.2.53
    searches:
    - corp.example.com
    options:
    - name: ndots
      value: "2"
    - name: edns0
```

Result inside the container:

```text
nameserver 192.0.2.53
search corp.example.com
options ndots:2 edns0
```

Full examples (merge with ClusterFirst, `None`, hostNetwork, hostname/subdomain): [yaml/pod-dns-config.yaml](yaml/pod-dns-config.yaml).

### Testing tools

| Tool | Image | Command (inside the Pod) | Good for |
|---|---|---|---|
| `wget` | `busybox:1.36` | `wget -qO- --timeout=2 http://web.prod` | HTTP body with a fast failure |
| `wget --spider` | `busybox:1.36` | `wget --spider --timeout=2 http://web.prod` | reachability only |
| `nc` | `busybox:1.36` | `nc -zv -w 2 db.prod 5432` | is a TCP port open (non-HTTP services) |
| `nslookup` | `busybox:1.36` | `nslookup web.prod.svc.cluster.local` | A / CNAME answers; `-type=srv` for SRV |
| `curl` | `curlimages/curl:8.10.1` | `curl -sS -m 3 http://web.prod` | status codes, headers, `-H "Host: ..."`, `--resolve`, TLS |
| `cat` | any | `cat /etc/resolv.conf` | search domains, nameserver, ndots |
| `nslookup` / `dig` | `registry.k8s.io/e2e-test-images/agnhost:2.39` (the docs' `dnsutils` Pod) | `nslookup kubernetes.default` | deeper DNS debugging |

Throwaway one-liners (`--rm` deletes the Pod when the command ends):

```bash
kubectl run tmp --rm -it --image=busybox:1.36 --restart=Never -- wget -qO- --timeout=2 http://web.prod
kubectl run tmp --rm -it --image=busybox:1.36 --restart=Never -- nslookup web.prod.svc.cluster.local
kubectl run tmp --rm -it --image=busybox:1.36 --restart=Never -- nc -zv -w 2 db.prod 5432
kubectl run tmp --rm -it --image=curlimages/curl:8.10.1 --restart=Never -- curl -sS -m 3 http://web.prod
```

`-n <ns>` and `--labels=...` on the test Pod matter: its namespace drives short-name resolution, and its labels decide which NetworkPolicies let it through.

Busybox `nslookup` output can be noisy (extra NXDOMAIN or AAAA lines). The answer is the `Name:` / `Address:` pair; use the FQDN to remove any doubt.

---

## Key fields / syntax

Pod side — name your ports so Services can refer to them by name:

```yaml
spec:
  containers:
  - name: app
    image: nginx:1.27
    ports:
    - name: http              # IANA_SVC_NAME: max 15 chars, lowercase letters/digits/'-', at least one letter
      containerPort: 80
      protocol: TCP           # default
```

Service side:

```yaml
spec:
  selector:
    app: web
  ports:
  - name: http
    port: 80                  # what clients call
    targetPort: http          # the Pod port: name or number (defaults to port)
    # nodePort: 30080         # only for type NodePort / LoadBalancer
```

Reference files: [yaml/svc-clusterip.yaml](yaml/svc-clusterip.yaml) · [yaml/svc-nodeport.yaml](yaml/svc-nodeport.yaml) · [yaml/svc-headless.yaml](yaml/svc-headless.yaml) · [yaml/pod-dns-config.yaml](yaml/pod-dns-config.yaml) · [yaml/test-pods.yaml](yaml/test-pods.yaml)

---

## Imperative commands

```bash
# A reusable client Pod (labels matter for NetworkPolicy tests) -- generate, then apply
kubectl run client --image=busybox:1.36 --labels=role=client --dry-run=client -o yaml -- sleep 3600 > client.yaml
kubectl apply -f client.yaml

# Test from it (kubectl exec output is clean: safe to redirect into a file)
kubectl exec client -- wget -qO- --timeout=2 http://web
kubectl exec client -- nc -zv -w 2 db 5432
kubectl exec client -- nslookup web.default.svc.cluster.local
kubectl exec client -- cat /etc/resolv.conf

# Where things are
kubectl get pods -o wide                                  # Pod IPs and nodes
kubectl get svc -A -o wide                                # ClusterIPs, ports, selectors
kubectl get endpointslices -l kubernetes.io/service-name=web
kubectl get nodes -o wide                                 # node InternalIPs (for NodePort tests)

# Cluster DNS
kubectl -n kube-system get svc kube-dns                   # the nameserver IP in resolv.conf
kubectl -n kube-system get pods -l k8s-app=kube-dns       # CoreDNS Pods healthy?
kubectl -n kube-system logs -l k8s-app=kube-dns --tail=50 # CoreDNS errors
kubectl -n kube-system get configmap coredns -o yaml      # Corefile: cluster domain, forwarders

# kube-proxy mode (kubeadm-style clusters; mode: "" = the platform default, iptables on Linux)
kubectl -n kube-system get configmap kube-proxy -o yaml | grep -i "mode"
kubectl -n kube-system logs ds/kube-proxy | grep -iE "proxier|proxy mode|using (iptables|ipvs|nftables)"
```

---

## Exam traps & tips

> **Exam tip:** test from a Pod in the namespace the task names, with the labels the task names. A test from `default` with no labels proves nothing about a NetworkPolicy that allows `role=frontend` in `prod`.

> **Exam tip:** `targetPort` defaults to `port`. `kubectl expose deploy web --port=80` for an app listening on 8080 creates a Service that refuses connections — always pass `--target-port`.

> **Exam tip:** `kubectl run tmp --rm -i ... > file` may also capture kubectl's own `pod "tmp" deleted` message. For output files, run a long-lived client Pod and use `kubectl exec ... > file`, then `cat` the file.

- A missing `containerPort` never blocks traffic; it only matters when a Service uses a **named** targetPort.
- Short Service names work only inside the same namespace; across namespaces use at least `<svc>.<ns>`.
- App images often lack `wget`/`curl`/`nc`. Use a busybox or curl test Pod, or `kubectl debug -it <pod> --image=busybox:1.36` (an ephemeral container shares the Pod's network namespace).
- When egress is restricted, DNS breaks first. Test by IP (`kubectl get pod -o wide`) to separate "DNS blocked" from "port blocked".
- `kubectl port-forward` is TCP-only.
- A `hostNetwork: true` Pod uses the node's IP and, without `dnsPolicy: ClusterFirstWithHostNet`, the node's DNS.
- `dnsConfig.options[].value` is a string: write `"2"`, not `2`.

---

## Architect notes

- **CNI choice drives everything else:** NetworkPolicy support (Flannel alone does not enforce it), eBPF dataplane vs iptables, encryption (WireGuard/IPsec), overlay vs native/VPC routing, IPAM and IP exhaustion behaviour, observability (flow logs).
- **IP planning:** size the Pod CIDR for max nodes x per-node block, and the Service CIDR for growth. Multiple Service CIDRs (ServiceCIDR, GA v1.33) let you extend Service IP space later, but planning up front is cheaper.
- **Overlay MTU:** encapsulation (VXLAN/Geneve) eats bytes; mismatched MTU causes "small requests work, large ones hang".
- **DNS at scale:** CoreDNS replicas sized to the cluster (autoscaling), NodeLocal DNSCache to cut latency and conntrack pressure, lower `ndots` or FQDNs with trailing dots for chatty external clients.
- **kube-proxy mode:** consider `nftables` for large Service counts; `ipvs` is deprecated (v1.35), so plan migrations; or let an eBPF CNI replace kube-proxy entirely.
- **Dual-stack:** Services choose families with `ipFamilyPolicy` (`SingleStack` / `PreferDualStack` / `RequireDualStack`) and `ipFamilies`; EndpointSlices are per address family.
- **Debuggability is a feature:** standardise a "netshoot-style" debug image and an ephemeral-container runbook so on-call engineers can test DNS/TCP from inside any namespace.

---

## Docs to bookmark

- Services, Load Balancing, and Networking (network model): https://kubernetes.io/docs/concepts/services-networking/
- Cluster networking: https://kubernetes.io/docs/concepts/cluster-administration/networking/
- DNS for Services and Pods: https://kubernetes.io/docs/concepts/services-networking/dns-pod-service/
- Virtual IPs and Service proxies (kube-proxy modes, traffic policies): https://kubernetes.io/docs/reference/networking/virtual-ips/
- Debugging DNS resolution: https://kubernetes.io/docs/tasks/administer-cluster/dns-debugging-resolution/
- Debug Services: https://kubernetes.io/docs/tasks/debug/debug-application/debug-service/

Related chapters: [06 Cross-Cutting Skills](../06-Cross-Cutting-Skills-and-Bonus-Topics/README.md) (labels, selectors, jsonpath) · [00 Exam Overview and Setup](../00-Exam-Overview-and-Setup/README.md) (lab setup).

---

## Quick self-check

1. A Service has `port: 80` and no `targetPort`; the app listens on 8080. What happens and how do you fix it?
2. From namespace `dev`, which names reach Service `db` in namespace `prod`?
3. What DNS name does Pod 1 of StatefulSet `kafka` (headless Service `kafka-hl`, namespace `data`) get?
4. Which `dnsPolicy` is the default, and what does `dnsPolicy: Default` do?
5. A `hostNetwork: true` Pod cannot resolve Service names. What is the fix?
6. Does removing `containerPort` from a Pod spec stop traffic to that port?

<details><summary>Answers</summary>

1. `targetPort` defaults to `port` (80), so traffic hits a closed port: connection refused. Set `targetPort: 8080` (or the container port name).
2. `db.prod`, `db.prod.svc`, `db.prod.svc.cluster.local` — not `db` (that searches `dev` first).
3. `kafka-1.kafka-hl.data.svc.cluster.local`.
4. `ClusterFirst` is the default. `Default` inherits the node's resolver configuration (no cluster DNS).
5. Set `dnsPolicy: ClusterFirstWithHostNet`.
6. No. `containerPort` is informational; only a named `targetPort` that refers to it would break.

</details>
