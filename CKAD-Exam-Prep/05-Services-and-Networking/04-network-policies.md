# 04 — NetworkPolicies: Allow-listing Pod Traffic

**Why it matters:** "Demonstrate basic understanding of NetworkPolicies" sounds light, but policy tasks are precise: one wrong `-` turns an AND into an OR, a missing DNS rule breaks everything, and a policy in the wrong namespace does nothing.

**What the exam expects:** write a policy from a sentence ("only Pods X in namespace Y may reach Z on port P"), add default-deny, allow DNS for egress, read existing policies with `kubectl describe`, and — a pattern candidates often describe — make traffic work by **labelling Pods** to fit existing policies without editing the policies.

---

## Core concepts

### The rules of the game

| # | Fact |
|---|---|
| 1 | Enforcement needs a CNI that implements NetworkPolicy (Calico, Cilium, Antrea, ...; kind's default kindnet does too since kind v0.24.0, via kube-network-policies). Without one, policies are accepted and **silently do nothing**. Prove enforcement in a lab with a default-deny test. |
| 2 | By default Pods are **non-isolated**: all ingress and all egress are allowed. |
| 3 | A Pod becomes **isolated for a direction** once **any** policy that selects it lists that direction in `policyTypes`. From then on only traffic that some policy allows for that direction gets through. |
| 4 | **Allow-list only.** No deny rules. Policies are **additive** (a union); order does not matter and they never conflict. |
| 5 | A connection needs **both** sides: egress allowed for the source Pod (if it is egress-isolated) **and** ingress allowed for the destination Pod (if it is ingress-isolated). |
| 6 | **Stateful:** replies to an allowed connection are allowed automatically — no "return path" rules. |
| 7 | **Namespaced:** a policy selects Pods only in its own namespace, and a rule's `podSelector` without a `namespaceSelector` also means "Pods in the policy's namespace". |
| 8 | Traffic to and from the Pod's **own node** is always allowed (kubelet probes keep working). `hostNetwork` Pods: behaviour is undefined; most plugins treat them like node traffic. |
| 9 | Every namespace has the immutable label **`kubernetes.io/metadata.name=<name>`** — select a namespace by name with it. |
| 10 | When egress is restricted, **allow DNS** (UDP **and** TCP 53 to CoreDNS) or every lookup by name fails. |
| 11 | `policyTypes` omitted → `Ingress` is always assumed, `Egress` only if the policy has an `egress` section. Write `policyTypes` explicitly, always. |
| 12 | Policies match **Pods and Pod ports**, not Services: allow the container port (the Service's `targetPort`), not the Service port. |

### Anatomy

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: api-policy
  namespace: prod                   # only Pods in this namespace can be selected
spec:
  podSelector:                      # WHICH Pods the policy applies to ({} = every Pod in the namespace)
    matchLabels:
      app: api
  policyTypes:                      # which directions this policy isolates
  - Ingress
  - Egress
  ingress:                          # list of rules; traffic is allowed if ANY rule matches
  - from:                           # list of peers (ORed)
    - podSelector:                  # peer 1: Pods with app=frontend in namespace prod
        matchLabels:
          app: frontend
    - namespaceSelector:            # peer 2: every Pod in namespaces labelled team=ops
        matchLabels:
          team: ops
    ports:                          # ...AND the destination port is one of these
    - protocol: TCP                 # TCP (default) | UDP | SCTP
      port: 8080                    # number or a container port NAME of the selected Pods
  egress:
  - to:
    - ipBlock:
        cidr: 10.0.0.0/16
        except:
        - 10.0.5.0/24
    ports:
    - protocol: TCP
      port: 5432
      endPort: 5440                 # range 5432-5440 (GA v1.25); port and endPort must be numeric
```

Inside one rule: (any peer in `from`/`to`) **AND** (any entry in `ports`). Missing `from`/`to` = any peer; missing `ports` = all ports. Across rules and across policies: **OR**.

### Selector semantics

| Written as | Selects |
|---|---|
| `spec.podSelector: {}` | every Pod in the policy's namespace |
| `spec.podSelector: {matchLabels: {app: api}}` | Pods `app=api` in the policy's namespace |
| `spec.podSelector` omitted | current API: treated as `{}` (all Pods). Write `{}` explicitly — clearer, and older tooling rejected the omission |
| `- podSelector: {}` (in from/to) | every Pod in the **policy's** namespace (not all namespaces!) |
| `- podSelector: {matchLabels: {app: x}}` | Pods `app=x` in the policy's namespace |
| `- namespaceSelector: {}` | every Pod in **every** namespace |
| `- namespaceSelector: {matchLabels: {kubernetes.io/metadata.name: mon}}` | every Pod in namespace `mon` |
| `- namespaceSelector: {...}` **+** `podSelector: {...}` in the **same** element | Pods matching the podSelector **inside** namespaces matching the namespaceSelector (AND) |
| `- namespaceSelector: {}` + `podSelector: {matchLabels: {app: x}}` (same element) | Pods `app=x` in **any** namespace |
| `- ipBlock: {cidr: ..., except: [...]}` | IP ranges — meant for cluster-external addresses |
| `ingress: [{}]` / `egress: [{}]` (one empty rule) | everything, all ports |
| `ingress: []`, or no `ingress` key while `Ingress` is in policyTypes | nothing (isolate only) |
| rule without `ports` | all ports and protocols |

`matchExpressions` work in all of these selectors too (`operator: In | NotIn | Exists | DoesNotExist`).

### AND vs OR, side by side

AND — **one** element with two selectors (no `-` before `podSelector`):

```yaml
ingress:
- from:
  - namespaceSelector:
      matchLabels:
        team: ops
    podSelector:
      matchLabels:
        app: prometheus
```

Allows: Pods labelled `app=prometheus` **that run in** namespaces labelled `team=ops`.

OR — **two** elements (a second `-`):

```yaml
ingress:
- from:
  - namespaceSelector:
      matchLabels:
        team: ops
  - podSelector:
      matchLabels:
        app: prometheus
```

Allows: **every** Pod in `team=ops` namespaces, **or** Pods labelled `app=prometheus` in the policy's own namespace.

| Client | AND | OR |
|---|---|---|
| `app=prometheus` in a `team=ops` namespace | allowed | allowed |
| `app=grafana` in a `team=ops` namespace | denied | **allowed** |
| `app=prometheus` in another namespace (not `team=ops`) | denied | denied |
| `app=prometheus` in the policy's namespace | denied (unless that namespace is `team=ops`) | allowed |

Lab version of this table: [yaml/netpol-and-vs-or.yaml](yaml/netpol-and-vs-or.yaml) with [yaml/test-pods.yaml](yaml/test-pods.yaml).

### Recipes

Default deny (pick the direction):

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: prod
spec:
  podSelector: {}
  policyTypes:
  - Ingress            # drop this line for egress-only deny
  - Egress             # drop this line for ingress-only deny
```

Allow DNS for every Pod in the namespace (add whenever egress is restricted):

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-dns-egress
  namespace: prod
spec:
  podSelector: {}
  policyTypes:
  - Egress
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: kube-system
      podSelector:
        matchLabels:
          k8s-app: kube-dns
    ports:
    - protocol: UDP
      port: 53
    - protocol: TCP
      port: 53
```

Allow from a whole namespace, selected by name:

```yaml
ingress:
- from:
  - namespaceSelector:
      matchLabels:
        kubernetes.io/metadata.name: monitoring
```

Allow from the Ingress controller (backends behind an Ingress under default-deny):

```yaml
ingress:
- from:
  - namespaceSelector:
      matchLabels:
        kubernetes.io/metadata.name: ingress-nginx
  ports:
  - protocol: TCP
    port: 8080
```

ipBlock with an exception:

```yaml
ingress:
- from:
  - ipBlock:
      cidr: 192.168.0.0/16
      except:
      - 192.168.100.0/24
  ports:
  - protocol: TCP
    port: 80
```

`ipBlock` is for cluster-external IPs: Pod IPs are ephemeral, and NAT (LoadBalancers, NodePorts, egress gateways) can change the source/destination address the plugin sees — whether that happens before or after policy evaluation is implementation-defined.

Egress to the database only (+ DNS), and the matching ingress on the database:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: api-egress-db-only
  namespace: prod
spec:
  podSelector:
    matchLabels:
      app: api
  policyTypes:
  - Egress
  egress:
  - to:
    - podSelector:
        matchLabels:
          app: db
    ports:
    - protocol: TCP
      port: 5432
  - to:
    - namespaceSelector: {}
      podSelector:
        matchLabels:
          k8s-app: kube-dns
    ports:
    - protocol: UDP
      port: 53
    - protocol: TCP
      port: 53
```

| File | Shows |
|---|---|
| [yaml/test-pods.yaml](yaml/test-pods.yaml) | Lab: namespaces, servers (web/api/db) and labelled clients |
| [yaml/netpol-default-deny-ingress.yaml](yaml/netpol-default-deny-ingress.yaml) | Default deny ingress |
| [yaml/netpol-default-deny-egress.yaml](yaml/netpol-default-deny-egress.yaml) | Default deny egress (breaks DNS) |
| [yaml/netpol-default-deny-all.yaml](yaml/netpol-default-deny-all.yaml) | Default deny both directions |
| [yaml/netpol-allow-all-ingress.yaml](yaml/netpol-allow-all-ingress.yaml) | Allow-all ingress / egress |
| [yaml/netpol-allow-from-pods.yaml](yaml/netpol-allow-from-pods.yaml) | Only frontend Pods → api:80 |
| [yaml/netpol-allow-from-namespace.yaml](yaml/netpol-allow-from-namespace.yaml) | Whole namespace by `kubernetes.io/metadata.name` |
| [yaml/netpol-and-vs-or.yaml](yaml/netpol-and-vs-or.yaml) | AND vs OR with an expected-results matrix |
| [yaml/netpol-allow-dns-egress.yaml](yaml/netpol-allow-dns-egress.yaml) | DNS egress to CoreDNS |
| [yaml/netpol-egress-to-db-only.yaml](yaml/netpol-egress-to-db-only.yaml) | api → db only (+ DNS), db ingress from api |
| [yaml/netpol-ipblock.yaml](yaml/netpol-ipblock.yaml) | ipBlock + except, endPort range |

---

## Key fields / syntax

| Field | Notes |
|---|---|
| `metadata.namespace` | Namespace of the **target** Pods |
| `spec.podSelector` | Target Pods; `{}` = all |
| `spec.policyTypes` | `Ingress`, `Egress` or both — be explicit |
| `spec.ingress[].from[]` | Peers: `podSelector`, `namespaceSelector`, both (AND), or `ipBlock` |
| `spec.egress[].to[]` | Same peer types as `from` |
| `ports[].protocol` | `TCP` (default), `UDP`, `SCTP` |
| `ports[].port` | Number or container port name (of the destination Pods) |
| `ports[].endPort` | Upper bound of a numeric range, ≥ `port` (GA v1.25) |
| `ipBlock.cidr` / `ipBlock.except[]` | `except` must lie inside `cidr` |

`kubectl explain networkpolicy.spec.ingress.from --recursive` prints the schema in the exam terminal.

---

## Imperative commands

There is **no** `kubectl create networkpolicy` generator: write YAML (copy a recipe from the docs page or this chapter) and apply it.

```bash
kubectl get netpol -n prod                                   # NAME, POD-SELECTOR
kubectl get netpol -A                                        # every policy in the cluster
kubectl describe netpol -n prod                              # human-readable rules (see below)
kubectl get netpol api-policy -n prod -o yaml                # exact YAML (AND/OR by indentation)
kubectl apply -f policy.yaml                                 # create / update
kubectl delete netpol api-policy -n prod                     # remove (only if the task allows)
kubectl get pods -n prod --show-labels                       # which labels exist
kubectl get ns --show-labels                                 # namespace labels incl. kubernetes.io/metadata.name
kubectl label pod newpod -n prod role=frontend               # fit a Pod to an existing policy
kubectl label ns monitoring team=ops                         # fit a namespace to a namespaceSelector
kubectl explain networkpolicy.spec --recursive               # field reference
```

---

## Testing method

```bash
# 1) Labelled client Pods in the right namespaces (or: kubectl apply -f yaml/test-pods.yaml)
kubectl -n prod run t-frontend --image=busybox:1.36 --labels=app=frontend -- sleep 3600
kubectl -n prod run t-other    --image=busybox:1.36 --labels=app=other    -- sleep 3600
kubectl -n monitoring run t-prom --image=busybox:1.36 --labels=app=prometheus -- sleep 3600

# 2) Baseline BEFORE applying the policy -- must succeed, otherwise you are testing something else
kubectl -n prod exec t-frontend -- wget -qO- --timeout=2 http://api:8080

# 3) Apply, then test one allowed and one denied client (short timeouts!)
kubectl apply -f policy.yaml
kubectl -n prod exec t-frontend -- wget -qO- --timeout=2 http://api:8080       # expect a response
kubectl -n prod exec t-other    -- wget -qO- --timeout=2 http://api:8080       # expect "download timed out"
kubectl -n prod exec t-frontend -- nc -zv -w 2 db 5432                         # non-HTTP port
kubectl -n monitoring exec t-prom -- wget -qO- --timeout=2 http://api.prod:8080
```

| Result | Meaning |
|---|---|
| response / `open` | allowed |
| `download timed out` / `timed out` | dropped — a policy blocks it (or routing is broken) |
| `bad address` / `can't resolve` | DNS failed — check egress DNS rules before blaming the target |
| `Connection refused` | packets **reached** the Pod (policy allowed them) but nothing listens there — check ports |

To separate DNS from policy problems, test by Pod IP: `kubectl -n prod get pod -l app=api -o wide`.

### Reading existing policies with `kubectl describe`

Abridged output for a policy with two ingress peers (one of them AND-combined) and one egress rule:

```text
Name:         api-policy
Namespace:    prod
Spec:
  PodSelector:     app=api
  Allowing ingress traffic:
    To Port: 8080/TCP
    From:
      PodSelector: app=frontend
    From:
      NamespaceSelector: team=ops
      PodSelector: app=prometheus
  Allowing egress traffic:
    To Port: 5432/TCP
    To:
      PodSelector: app=db
  Policy Types: Ingress, Egress
```

| Printed text (current kubectl wording) | Means |
|---|---|
| `PodSelector: <none> (Allowing the specific traffic to all pods in this namespace)` | `spec.podSelector: {}` |
| each `From:` / `To:` block | one peer — blocks are **ORed** |
| two selectors under **one** `From:` | **AND** (above: prometheus Pods in team=ops namespaces) |
| `From: <any> (traffic not restricted by source)` | rule without `from`: any source on the listed ports |
| `To Port: <any> (traffic allowed to all ports)` | rule without `ports` |
| `<none> (Selected pods are isolated for ingress connectivity)` | Ingress isolated with no rules = deny all ingress |
| `Not affecting egress traffic` | `Egress` not in policyTypes |
| `----------` | separator between rules |

---

## Exam pattern: label Pods, don't touch the policies (worked example)

Task style: *"Pod `newpod` in namespace `sn-q7` must be able to reach `web` on port 80 and `db` on port 6379. Do not create, modify or delete any NetworkPolicy."* (Lab: [yaml/practice-setup/q07-netpol-label-pods.yaml](yaml/practice-setup/q07-netpol-label-pods.yaml) — practice Q7.)

```bash
# 1) What exists?
kubectl -n sn-q7 get netpol
#   NAME                POD-SELECTOR
#   db-client-egress    db-access=true
#   db-ingress          app=db
#   default-deny-all    <none>            <- {} = every Pod
#   web-client-egress   web-access=true
#   web-ingress         app=web

# 2) Read the rules: who may talk to web/db, and which Pods get egress?
kubectl -n sn-q7 describe netpol web-ingress db-ingress web-client-egress db-client-egress
#   web-ingress:       From PodSelector web-access=true, To Port 80/TCP
#   db-ingress:        From PodSelector db-access=true,  To Port 6379/TCP
#   web-client-egress: applies to web-access=true -> may reach app=web:80 + DNS
#   db-client-egress:  applies to db-access=true  -> may reach app=db:6379 + DNS

# 3) The current labels of the Pod
kubectl -n sn-q7 get pod newpod --show-labels                  # app=newpod only

# 4) Give the Pod the labels both sides expect (ingress on the target AND egress on the source)
kubectl -n sn-q7 label pod newpod web-access=true db-access=true

# 5) Verify
kubectl -n sn-q7 exec newpod -- wget -qO- --timeout=2 http://web | head -n 4
kubectl -n sn-q7 exec newpod -- nc -zv -w 2 db 6379
```

- Default-deny-all is untouched — the labels make `newpod` match the existing allow rules on **both** ends (and give it DNS egress).
- If the Pod belongs to a Deployment, put the labels in the **Pod template** (`kubectl edit deploy <name>` → `spec.template.metadata.labels`) so replacement Pods keep them; never change the Deployment's `selector`.
- If a policy uses a `namespaceSelector`, the fix may be a namespace label instead: `kubectl label ns <ns> team=ops`.

---

## Exam traps & tips

> **Exam tip:** the `-` decides everything. `namespaceSelector` and `podSelector` in the **same** list item = AND; each with its own `-` = OR. After applying, confirm with `kubectl describe netpol` — two selectors under one `From:` means AND.

> **Exam tip:** create the policy in the namespace of the Pods it protects: `metadata.namespace` (or `-n`). A correct policy in `default` does nothing for Pods in `prod`.

> **Exam tip:** "only X may reach Y" does not need a separate default-deny: a policy selecting Y with `policyTypes: [Ingress]` already isolates Y for ingress. Add default-deny only when the task asks for it.

- Egress policy written without `policyTypes` → `[Ingress, Egress]` is assumed → the Pods are also ingress-isolated with no ingress rules → all incoming traffic is dropped.
- `ingress: []` allows nothing; `ingress: [{}]` (`- {}`) allows everything.
- `podSelector: {}` inside `from` = all Pods of the **policy's** namespace; `namespaceSelector: {}` = all namespaces.
- Use the container port (targetPort) in `ports`, not the Service port.
- Restricting egress? Add DNS (UDP **and** TCP 53) — otherwise names fail even where IPs work.
- Label values in selectors are strings: `"true"`, not `true`. Labels are case-sensitive.
- Select namespaces by name with `kubernetes.io/metadata.name`; don't invent namespace labels unless asked.
- Never delete or "simplify" existing policies unless the task says so.
- Test with timeouts (`--timeout=2`, `-w 2`) — a blocked connection otherwise hangs for minutes.

---

## Architect notes

- **Default-deny per namespace** (ingress and egress) as the baseline, plus explicit allows for each flow and DNS — managed as code (GitOps), reviewed like firewall rules.
- **Design labels for policy:** stable, intent-revealing labels (`app.kubernetes.io/name`, `network.example.com/db-client: "true"`) rather than incidental ones (`pod-template-hash`, versions). Namespaces get team/environment labels.
- **Know the API's limits:** no explicit deny, no logging, no FQDN-based egress, no Service-name targeting, no cluster-wide default. CNI extensions fill gaps (Calico GlobalNetworkPolicy, Cilium L7/HTTP and DNS-aware policies, cluster-wide policies); SIG Network's AdminNetworkPolicy work (alpha CRDs) targets admin-level guardrails.
- **Plan for NAT and special paths:** NodeLocal DNSCache (node-local IP, often 169.254.20.10), the API server (`kubernetes.default` → control-plane IPs: needs `ipBlock` + 443/6443), cloud metadata endpoints (block 169.254.169.254 where possible), egress gateways.
- **Startup races:** a new Pod may start before its allow rules are programmed; make apps retry connections (or use an init container that waits for dependencies).
- **Observability:** use the CNI's flow logs (e.g. Hubble, Calico flow logs) to build and validate policies from real traffic; test connectivity matrices in CI.
- **Ingress controllers and meshes** need explicit allows: controller namespace → backends; mesh sidecars may add ports (and mTLS handles identity at L7 — NetworkPolicy stays the L3/L4 floor).

---

## Docs to bookmark

- Network Policies: https://kubernetes.io/docs/concepts/services-networking/network-policies/
- Declare Network Policy (walk-through): https://kubernetes.io/docs/tasks/administer-cluster/declare-network-policy/
- NetworkPolicy API reference: https://kubernetes.io/docs/reference/kubernetes-api/policy-resources/network-policy-v1/

Related: label selectors in [06 Cross-Cutting Skills](../06-Cross-Cutting-Skills-and-Bonus-Topics/README.md); security context and admission in [04 Configuration and Security](../04-Application-Environment-Configuration-and-Security/README.md).

---

## Quick self-check

1. Policy A allows `app=frontend` → `app=api` on 80. Policy B selects all Pods with `policyTypes: [Ingress]` and no rules. Can frontend reach api:80?
2. A policy has only an `egress:` section and no `policyTypes`. What happens to ingress for the selected Pods?
3. After a default-deny egress policy, `wget http://api` fails with `bad address`. Why, and what is the fix?
4. How do you allow traffic from namespace `monitoring` without adding labels to it?
5. In a `from` element, what is the difference between `podSelector: {}` and `namespaceSelector: {}`?
6. Do you need an egress rule on the server Pod so it can answer allowed clients?

<details><summary>Answers</summary>

1. Yes. Policies are a union: B isolates every Pod for ingress, A allows that specific flow.
2. `policyTypes` defaults to `[Ingress, Egress]` because an egress section exists, so the Pods become ingress-isolated with no ingress rules: all incoming traffic is dropped. Add `policyTypes: [Egress]`.
3. DNS (UDP/TCP 53 to CoreDNS) is blocked too. Add an egress rule for DNS (e.g. [yaml/netpol-allow-dns-egress.yaml](yaml/netpol-allow-dns-egress.yaml)).
4. `namespaceSelector: {matchLabels: {kubernetes.io/metadata.name: monitoring}}`.
5. `podSelector: {}` = all Pods in the policy's own namespace; `namespaceSelector: {}` = all Pods in all namespaces.
6. No. Policies are stateful; replies are allowed implicitly.

</details>
