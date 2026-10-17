# Labels, Selectors, Annotations and Namespaces

**Why it matters / what the exam expects:** labels are the glue of Kubernetes - Services find Pods by label, Deployments own ReplicaSets by label, NetworkPolicies, PDBs, affinity rules and topology spread all select by label. One wrong label means a Service without endpoints or a NetworkPolicy that matches nothing. Expect tasks such as "add label X to all pods of Y", "list pods with label A but not B into a file", "annotate the deployment", "create namespace N and work in it". Namespaces and contexts are touched in **every** task.

> Conventions: `alias k=kubectl`. Lab file for this page: [yaml/labels-selectors-demo.yaml](yaml/labels-selectors-demo.yaml) (expected results in the [Selector lab](#selector-lab-with-expected-results) below).

---

## Core concepts

### Labels vs annotations vs fields

| | Labels | Annotations | Field selectors |
|---|---|---|---|
| Purpose | identify and **select** objects | attach non-identifying metadata (for tools and humans) | filter on a few built-in fields |
| Queried with | `-l` / `selector:` | not selectable (read them with jsonpath) | `--field-selector` |
| Value rules | max 63 chars, restricted charset, may be empty | any string; all annotations together max 256 KiB | – |
| Used by | Services, workloads, NetworkPolicy, PDB, affinity, topology spread | Ingress controllers, `kubectl rollout history`, operators, Prometheus conventions | kubectl and API LIST/WATCH |

### Label syntax rules

| Part | Rule | Valid | Invalid |
|---|---|---|---|
| Key prefix (optional) | DNS subdomain (lowercase, dots), max 253 chars, followed by `/` | `app.kubernetes.io/name` | `My.Domain/app` |
| Key name (required) | max 63 chars; start and end alphanumeric; `-` `_` `.` allowed inside | `tier`, `release_track`, `env.stage` | `-tier`, `tier-` |
| Value | max 63 chars, may be empty; if not empty start and end alphanumeric; `-` `_` `.` inside | `v1.2.3`, `""`, `blue_green` | `web server` (space), `a/b` (slash), `-x` |
| Reserved prefixes | `kubernetes.io/` and `k8s.io/` belong to Kubernetes core components | `kubernetes.io/hostname` (set by kubelet) | – |

In YAML every label value is a **string**: quote `"true"`, `"1.0"`, `"0123"`, `"yes"` (see [07-yaml-essentials.md](07-yaml-essentials.md)).

### Selector semantics

| Selector (CLI) | Matches | Also matches objects WITHOUT the key? |
|---|---|---|
| `env=dev` (same as `env==dev`) | env equals dev | no |
| `env!=dev` | env is anything except dev | **yes** |
| `env in (dev,qa)` | env is dev or qa | no |
| `env notin (dev,qa)` | env is neither dev nor qa | **yes** |
| `env` | the key exists (any value) | no |
| `!env` | the key does not exist | only those |
| `a=x,b=y` | comma = **AND** | – |

There is no OR across different keys inside one selector - run two queries or restructure the labels. OR on the values of one key is `in (...)`.

### Where selectors live

| Object / field | Selector type |
|---|---|
| Service `spec.selector`, ReplicationController `spec.selector` | plain map, equality only |
| Pod `spec.nodeSelector` | plain map, equality only (against node labels) |
| Deployment / ReplicaSet / StatefulSet / DaemonSet `spec.selector` | `matchLabels` + `matchExpressions`; **immutable**; must match the template labels |
| Job `spec.selector` | generated automatically - normally do not set it |
| NetworkPolicy `podSelector`, `namespaceSelector` | `matchLabels` + `matchExpressions`; `{}` = all |
| PodDisruptionBudget `spec.selector` | `matchLabels` + `matchExpressions` |
| Pod (anti-)affinity and topology spread `labelSelector` | `matchLabels` + `matchExpressions` |
| Node affinity `nodeSelectorTerms[].matchExpressions` | operators `In`, `NotIn`, `Exists`, `DoesNotExist`, `Gt`, `Lt` |

### Recommended labels (`app.kubernetes.io/*`)

| Key | Example | Meaning |
|---|---|---|
| `app.kubernetes.io/name` | `mysql` | name of the application |
| `app.kubernetes.io/instance` | `mysql-abcxyz` | unique instance name |
| `app.kubernetes.io/version` | `5.7.21` | application version |
| `app.kubernetes.io/component` | `database` | role within the architecture |
| `app.kubernetes.io/part-of` | `wordpress` | the higher-level application |
| `app.kubernetes.io/managed-by` | `Helm` | tool managing the object |

Helm charts and many operators set these. Selectors usually use a stable subset (`name` + `instance`) - never `version`, because selectors of Deployments are immutable.

### Annotations - typical uses

| Annotation | Set by / used for |
|---|---|
| `kubernetes.io/change-cause` | you (`k annotate`) - shown in `k rollout history` (replaces the deprecated `--record`) |
| `deployment.kubernetes.io/revision` | Deployment controller - current revision number |
| `kubectl.kubernetes.io/last-applied-configuration` | client-side `k apply` - basis of the 3-way merge |
| `kubectl.kubernetes.io/restartedAt` | `k rollout restart` (changing it in the template triggers the rollout) |
| `kubectl.kubernetes.io/default-container` | you - container used by `k logs`/`k exec` when `-c` is omitted |
| `kubernetes.io/service-account.name` | on a manually created long-lived SA token Secret |
| `nginx.ingress.kubernetes.io/rewrite-target` (and other controller-specific keys) | Ingress controller configuration |
| `prometheus.io/scrape`, `prometheus.io/port` | community convention read by some Prometheus configs (not core Kubernetes) |
| `owner`, `description`, `runbook`, ticket IDs | humans and tooling |

### Namespaces

| Fact | Detail |
|---|---|
| Initial namespaces | `default`, `kube-system` (control-plane add-ons), `kube-public` (readable by all, e.g. cluster-info), `kube-node-lease` (node heartbeats) |
| Name rules | RFC 1123 DNS label: lowercase alphanumerics and `-`, max 63 chars; avoid the `kube-` prefix |
| Automatic label | every namespace gets `kubernetes.io/metadata.name=<name>` (handy in NetworkPolicy `namespaceSelector`) |
| Scope | Pods, Services, Deployments, ConfigMaps, Secrets, PVCs, Roles, ... are namespaced; Nodes, PVs, StorageClasses, Namespaces, ClusterRoles, PriorityClasses, CRDs, IngressClasses are cluster-scoped (`k api-resources --namespaced=false`) |
| DNS | `<svc>.<ns>.svc.cluster.local`; from another namespace `<svc>.<ns>` is enough |
| Per-namespace policy | ResourceQuota, LimitRange, Pod Security Admission labels, RBAC Roles - see [04 chapter](../04-Application-Environment-Configuration-and-Security/README.md) |
| Deletion | `k delete ns x` deletes **everything inside**; the namespace stays `Terminating` until all finalizers finish |
| Isolation | namespaces isolate names, RBAC and quotas - **not network traffic** (that needs NetworkPolicies, see [05 chapter](../05-Services-and-Networking/README.md)) |

---

## Key fields / syntax

### Set-based selector in a workload ([yaml/labels-selectors-demo.yaml](yaml/labels-selectors-demo.yaml))

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: shop
  namespace: selectors-lab
spec:
  replicas: 2
  selector:
    matchLabels:                 # equality requirements
      app: shop
    matchExpressions:            # ANDed with matchLabels and with each other
    - key: tier
      operator: In               # In / NotIn need a non-empty values list
      values: ["frontend", "web"]
    - key: track
      operator: NotIn
      values: ["canary"]
    - key: version
      operator: Exists           # Exists / DoesNotExist take no values
    - key: legacy
      operator: DoesNotExist
  template:
    metadata:
      labels:                    # must satisfy the whole selector
        app: shop
        tier: frontend
        track: stable
        version: "v1"
    spec:
      containers:
      - name: pause
        image: registry.k8s.io/pause:3.10
```

### Service selector (map only)

```yaml
apiVersion: v1
kind: Service
metadata:
  name: web
  namespace: selectors-lab
spec:
  selector:                      # equality-based only; all pairs must match the pod labels
    app: web
  ports:
  - port: 80
    targetPort: 8080
```

### Namespace with labels and annotations ([yaml/namespace.yaml](yaml/namespace.yaml))

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: payments-dev
  labels:
    team: payments
    env: dev
  annotations:
    owner: "payments-team@example.com"
```

---

## Imperative commands

### Labels

```bash
k label pod web env=prod                          # add a label
k label pod web env=dev --overwrite               # change an existing value
k label pod web env-                              # remove the label "env"
k label pods -l app=web tier=frontend             # label every pod matching a selector
k label pods --all -n dev audit=true              # every pod in the namespace
k label node node01 disktype=ssd                  # node labels (for nodeSelector/affinity)
k label ns dev team=payments                      # namespace labels (for namespaceSelector, PSA)
k get pods --show-labels                          # all labels
k get pods -L app,env                             # chosen labels as columns
k label pod web --list                            # labels of one object
```

> **Exam tip:** `k label deploy web tier=fe` labels the **Deployment object only** - its pods do not change. To label the pods, change `spec.template.metadata.labels` (`k edit deploy web` or `k patch`), which triggers a rollout. Never touch `spec.selector` (immutable).

### Selecting with labels

```bash
k get pods -l app=web                             # equality
k get pods -l 'app=web,env!=prod'                 # AND + inequality (also matches pods WITHOUT env)
k get pods -l 'env in (dev,qa)'                   # set-based: quotes needed for parentheses and spaces
k get pods -l 'env notin (prod)'                  # also matches pods WITHOUT env
k get pods -l env                                 # key exists
k get pods -l '!env'                              # key absent - single quotes stop bash history expansion of "!"
k get pods -A -l 'tier=backend,!env'              # across all namespaces
k delete pods -l 'app=web,env=dev'                # selectors work with delete, label, annotate, logs, ...
k logs -l app=web --all-containers --prefix       # logs of every matching pod
k get pods -l app=web -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' > /opt/course/3/pods.txt
```

### Field selectors

```bash
k get pods --field-selector status.phase=Running
k get pods --field-selector metadata.name=web
k get pods -A --field-selector spec.nodeName=node01          # pods on a node
k get pods -A --field-selector 'status.phase!=Running,spec.restartPolicy=Always'   # comma = AND
k get pods -l tier=backend --field-selector status.phase=Running                    # combine with labels
k get events --field-selector involvedObject.name=web,type=Warning
k get secrets --field-selector type=kubernetes.io/tls
k get nodes --field-selector spec.unschedulable=true        # cordoned nodes
k get svc -A --field-selector metadata.namespace!=default
k get svc -A --field-selector spec.type=NodePort             # v1.37; older clusters: k get svc -A | grep NodePort
```

Supported fields (operators `=`, `==`, `!=` only - no `in`/`notin`): **all kinds** `metadata.name`, `metadata.namespace` · **Pod** `spec.nodeName`, `spec.restartPolicy`, `spec.schedulerName`, `spec.serviceAccountName`, `spec.hostNetwork`, `status.phase`, `status.podIP`, `status.nominatedNodeName` · **Event** `involvedObject.*`, `reason`, `reportingComponent`, `source`, `type` · **Secret** `type` · **Namespace** `status.phase` · **ReplicaSet/ReplicationController** `status.replicas` · **Job** `status.successful` · **Node** `spec.unschedulable` · **CSR** `spec.signerName`. **Service** `spec.clusterIP`, `spec.type` - listed for v1.37 (the exam version) but **not** in the v1.35 docs and older, so on older clusters filter Services by type with jsonpath or `grep`. Unsupported fields return an error.

### Annotations

```bash
k annotate deploy web kubernetes.io/change-cause="update image to nginx:1.27-alpine"
k annotate pod web owner=team-a                         # add
k annotate pod web owner=team-b --overwrite             # change
k annotate pod web owner-                               # remove
k annotate pods -l app=web scan=done                    # bulk
k get pod web -o jsonpath='{.metadata.annotations}{"\n"}'                     # all annotations
k get pod web -o jsonpath='{.metadata.annotations.owner}{"\n"}'               # one key
k get deploy web -o jsonpath='{.metadata.annotations.kubernetes\.io/change-cause}{"\n"}'   # dots escaped
k describe pod web | grep -A3 Annotations
```

### Namespaces and contexts

```bash
k create ns dev                                         # create
k create ns dev $do > ns.yaml                           # generate YAML (then add labels)
k get ns --show-labels
k get pods -n dev                                       # one namespace
k get pods -A                                           # all namespaces
k config set-context --current --namespace=dev          # make dev the default for the current context
k config view --minify -o jsonpath='{..namespace}'; echo
k api-resources --namespaced=true -o name               # namespaced kinds
k api-resources --namespaced=false -o name              # cluster-scoped kinds
k delete ns dev                                         # deletes everything inside
k get ns dev -o jsonpath='{.status.phase}{"\n"}'        # Active / Terminating
```

### Selector lab with expected results

```bash
k apply -f yaml/labels-selectors-demo.yaml
k get pods -n selectors-lab -L app,env,tier,track
k config set-context --current --namespace=selectors-lab    # saves typing -n below
```

Pods: `web-dev`, `web-qa`, `web-prod` (app=web, tier=frontend, env=dev/qa/prod), `api-dev`, `api-prod` (app=api, tier=backend), `cache` (tier=backend, **no env**), `legacy` (app=legacy, legacy=true, no env/tier), and 2 `shop-...` pods (app=shop, tier=frontend, track=stable, version=v1, no env).

| # | Query | Expected pods |
|---|---|---|
| 1 | `k get pods -l env=dev` | api-dev, web-dev |
| 2 | `k get pods -l 'env in (dev,qa)'` | api-dev, web-dev, web-qa |
| 3 | `k get pods -l 'env notin (prod)'` | api-dev, cache, legacy, shop-... x2, web-dev, web-qa |
| 4 | `k get pods -l '!env'` | cache, legacy, shop-... x2 |
| 5 | `k get pods -l env` | api-dev, api-prod, web-dev, web-prod, web-qa |
| 6 | `k get pods -l 'app=web,env!=prod'` | web-dev, web-qa |
| 7 | `k get pods -l 'tier=backend,!env'` | cache |
| 8 | `k get pods -l 'app in (web,api),env=prod'` | api-prod, web-prod |
| 9 | `k get pods -l 'tier notin (frontend,backend)'` | legacy |
| 10 | `k get pods -l 'env!=dev'` | api-prod, cache, legacy, shop-... x2, web-prod, web-qa |
| 11 | `k get endpointslices -l kubernetes.io/service-name=web` | 3 endpoints (web-dev, web-qa, web-prod) |

Quarantine trick (take a pod out of its ReplicaSet and out of Service traffic, keep it for debugging):

```bash
POD=$(k get pods -l app=shop -o jsonpath='{.items[0].metadata.name}')
k label pod "$POD" app=shop-debug --overwrite      # no longer matches the RS selector -> RS releases it
k get pods -l 'app in (shop,shop-debug)'           # 2 new/remaining shop pods + the quarantined one
k config set-context --current --namespace=default # switch back when done
k delete ns selectors-lab                          # cleanup
```

---

## Exam traps & tips

> **Exam tip:** always single-quote selectors with `(`, `)`, spaces or `!`: `-l 'env in (dev,qa)'`, `-l '!env'`. Unquoted, bash either errors on the parentheses or tries history expansion on `!`.

> **Exam tip:** `!=` and `notin` also return objects that do not have the key at all. If the task means "has env, but not prod", use `-l 'env,env notin (prod)'` (or `-l 'env,env!=prod'`).

> **Exam tip:** a Service with no endpoints almost always means selector and pod labels differ. Compare `k get svc web -o jsonpath='{.spec.selector}'` with `k get pods --show-labels`, then check `k get endpointslices -l kubernetes.io/service-name=web`.

> **Exam tip:** `-n` is silently ignored for cluster-scoped kinds (`k get nodes -n dev` works and shows all nodes) - do not let it confuse you.

- A Deployment's `spec.selector` is immutable; to change selection logic, delete and re-create the Deployment (pods are recreated).
- Template labels must satisfy the selector; extra template labels are fine.
- Relabelling a pod so it no longer matches its ReplicaSet makes the ReplicaSet create a replacement - powerful for debugging, surprising if done by accident.
- Label values are limited to 63 characters and cannot contain spaces or `/`; put free text into annotations.
- `k delete ns` cannot be undone and takes everything with it - double-check the name.

---

## Architect notes

- Define an organisation-wide label taxonomy (e.g. `app.kubernetes.io/name`, `app.kubernetes.io/instance`, `team`, `env`, `cost-center`) and enforce it with admission policies (ValidatingAdmissionPolicy, Kyverno or Gatekeeper).
- Keep selectors minimal and stable (`name` + `instance`); put mutable facts (version, git SHA) into labels that are *not* part of any selector, or into annotations.
- Namespace-per-team-per-environment is the common tenancy unit: attach RBAC, ResourceQuota, LimitRange, Pod Security Admission labels and a default-deny NetworkPolicy to every namespace from a template.
- Namespaces are a soft boundary: hard multi-tenancy needs separate clusters or virtual clusters (e.g. vCluster) plus node isolation.
- Cost allocation and chargeback tools aggregate by namespace and labels - missing labels mean unattributed spend.
- Annotations are a common integration point (Ingress controllers, service meshes, backup tools); keep their values small and document them, since the total size is capped at 256 KiB.
- Use the automatic `kubernetes.io/metadata.name` label in NetworkPolicy `namespaceSelector` instead of hand-maintained namespace labels.

---

## Docs to bookmark

- Labels and Selectors: https://kubernetes.io/docs/concepts/overview/working-with-objects/labels/
- Field Selectors: https://kubernetes.io/docs/concepts/overview/working-with-objects/field-selectors/
- Annotations: https://kubernetes.io/docs/concepts/overview/working-with-objects/annotations/
- Recommended Labels: https://kubernetes.io/docs/concepts/overview/working-with-objects/common-labels/
- Namespaces: https://kubernetes.io/docs/concepts/overview/working-with-objects/namespaces/
- Well-Known Labels, Annotations and Taints: https://kubernetes.io/docs/reference/labels-annotations-taints/

---

## Quick self-check

1. Which pods does `-l 'tier notin (frontend)'` return besides those with a different tier value?
2. List all pods in all namespaces that have a `team` label but no `owner` label.
3. You ran `k label deploy api version=v2`. Did the pods get the label? How would you label them?
4. Why can a Service not select pods with `env in (dev,qa)`?
5. Remove the annotation `owner` from Deployment `web` and add `kubernetes.io/change-cause=hotfix`.
6. Which label does every namespace carry automatically?

<details><summary>Answers</summary>

1. Every pod that has no `tier` label at all.
2. `k get pods -A -l 'team,!owner'`
3. No - only the Deployment object. Change `spec.template.metadata.labels` (e.g. `k patch deploy api -p '{"spec":{"template":{"metadata":{"labels":{"version":"v2"}}}}}'`), which rolls out new pods.
4. `Service.spec.selector` is a plain map - equality only. Use a common label (e.g. `stage=nonprod`) instead.
5. `k annotate deploy web owner-` and `k annotate deploy web kubernetes.io/change-cause=hotfix`
6. `kubernetes.io/metadata.name=<namespace-name>`

</details>
