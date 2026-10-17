# Scheduling and Placement

**Why it matters / what the exam expects:** the CKAD curriculum does not list scheduling as a competency (it is CKA material), but placement shows up inside other tasks - "run this pod on the control-plane node", "only on nodes labelled `disktype=ssd`", "never two replicas on one node" - and every "why is my pod Pending?" troubleshooting task needs you to read scheduler messages. None of these fields have imperative flags: generate the Pod/Deployment YAML and add the block (copy it from the docs or [yaml/](yaml/)). Frequency: nodeSelector and taints/tolerations ⚡, affinity ⚡/🧊, topology spread and PriorityClass 🧊.

> Conventions: `alias k=kubectl`, `export do="--dry-run=client -o yaml"`.

---

## Core concepts

### How kube-scheduler places a Pod

1. **Filter** - drop nodes that cannot run the pod: not enough allocatable CPU/memory for the **requests**, nodeSelector / required node affinity mismatch, untolerated `NoSchedule`/`NoExecute` taints, required pod (anti-)affinity, `DoNotSchedule` topology spread, host ports, volume topology, cordoned nodes.
2. **Score** - rank the remaining nodes: preferred affinities (weights), `ScheduleAnyway` spread, `PreferNoSchedule` taints, resource balance, image locality.
3. **Bind** the pod to the best node. No feasible node → pod stays `Pending` with a `FailedScheduling` event; if it has a higher priority, **preemption** may evict lower-priority pods.

`spec.nodeName` skips the scheduler entirely: `NoSchedule` taints are not checked, but the kubelet still rejects pods that do not fit (e.g. `OutOfcpu`, node affinity mismatch) and `NoExecute` taints still evict.

### Which mechanism for which requirement?

| Requirement | Use | Hard / soft |
|---|---|---|
| "Run on node X" (no questions asked) | `nodeName: X` or `nodeSelector: {kubernetes.io/hostname: X}` | hard |
| "Only on nodes with label L" | `nodeSelector` | hard |
| "Label in a set / not in a set / numeric compare" | node affinity `required...` | hard |
| "Prefer nodes with L" | node affinity `preferred...` (weight 1-100) | soft |
| "Keep ordinary pods off node X" | **taint** the node | `NoSchedule` hard, `PreferNoSchedule` soft, `NoExecute` also evicts |
| "Dedicated nodes for team/GPU" | taint + toleration **+** nodeSelector/affinity | hard |
| "Next to pod P" | `podAffinity` + `topologyKey` | hard or soft |
| "Never two replicas on the same node/zone" | `podAntiAffinity` required, `topologyKey: kubernetes.io/hostname` | hard |
| "Spread evenly across zones/nodes" | `topologySpreadConstraints` | `DoNotSchedule` hard, `ScheduleAnyway` soft |
| "More important than other pods" | `priorityClassName` | ordering + preemption |

### Combination rules

| Rule | Effect |
|---|---|
| `nodeSelector` **and** `nodeAffinity` both set | both must match |
| several `nodeSelectorTerms` | **ORed** - one term matching is enough |
| several `matchExpressions` inside one term | **ANDed** |
| several required `podAffinity` / `podAntiAffinity` terms | all must be satisfied |
| several `topologySpreadConstraints` | all must be satisfied (soft ones only score) |
| taints on a node | the pod must tolerate **every** `NoSchedule`/`NoExecute` taint |
| `...IgnoredDuringExecution` | checked at scheduling time only - relabelling a node later does not evict running pods (only `NoExecute` taints evict) |

### Well-known node labels

| Label | Example value | Set by |
|---|---|---|
| `kubernetes.io/hostname` | `node01` | kubelet |
| `kubernetes.io/os` / `kubernetes.io/arch` | `linux` / `amd64` | kubelet |
| `topology.kubernetes.io/zone` / `topology.kubernetes.io/region` | `eu-west-1a` / `eu-west-1` | cloud provider (often missing on kind/minikube) |
| `node.kubernetes.io/instance-type` | `m5.large` | cloud provider |
| `node-role.kubernetes.io/control-plane` | `""` (empty) | kubeadm |

---

## Key fields / syntax

### nodeName and nodeSelector ([yaml/node-selector-pod.yaml](yaml/node-selector-pod.yaml))

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: ssd-pod
spec:
  nodeSelector:
    disktype: ssd              # all pairs must match node labels (k label node node01 disktype=ssd)
  containers:
  - name: nginx
    image: nginx:1.27
```

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: pinned
spec:
  nodeName: node01             # bypasses the scheduler; node must exist
  containers:
  - name: nginx
    image: nginx:1.27
```

### Node affinity ([yaml/node-affinity-pod.yaml](yaml/node-affinity-pod.yaml))

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: affinity-ssd
spec:
  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:                 # ORed
        - matchExpressions:                # ANDed
          - key: disktype
            operator: In
            values: ["ssd", "nvme"]
      preferredDuringSchedulingIgnoredDuringExecution:
      - weight: 80                         # 1-100
        preference:
          matchExpressions:
          - key: topology.kubernetes.io/zone
            operator: In
            values: ["zone-a"]
  containers:
  - name: nginx
    image: nginx:1.27
```

| Operator | Meaning | Values | Node affinity | Pod affinity |
|---|---|---|---|---|
| `In` | label value is in the list | non-empty list | yes | yes |
| `NotIn` | label value not in the list (or label missing) | non-empty list | yes | yes |
| `Exists` | label key present | none | yes | yes |
| `DoesNotExist` | label key absent | none | yes | yes |
| `Gt` / `Lt` | label value parsed as integer is greater / less | exactly one integer, as a string `["3"]` | **yes** | **no** |

`NotIn` and `DoesNotExist` give node *anti*-affinity. A non-integer `Gt`/`Lt` value means the pod never schedules.

### Pod affinity and anti-affinity ([yaml/pod-affinity-anti-affinity.yaml](yaml/pod-affinity-anti-affinity.yaml))

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web-store
spec:
  replicas: 2
  selector:
    matchLabels:
      app: web-store
  template:
    metadata:
      labels:
        app: web-store
    spec:
      affinity:
        podAffinity:                       # be NEAR pods labelled app=cache ...
          requiredDuringSchedulingIgnoredDuringExecution:
          - labelSelector:
              matchLabels:
                app: cache
            topologyKey: kubernetes.io/hostname    # ... on the same node
        podAntiAffinity:                   # be AWAY from other web-store pods (soft)
          preferredDuringSchedulingIgnoredDuringExecution:
          - weight: 100
            podAffinityTerm:               # extra level in preferred rules
              labelSelector:
                matchLabels:
                  app: web-store
              topologyKey: kubernetes.io/hostname
      containers:
      - name: nginx
        image: nginx:1.27
```

| Field | Notes |
|---|---|
| `topologyKey` | node label that defines the domain: `kubernetes.io/hostname` (node), `topology.kubernetes.io/zone` (zone). Required and must not be empty. Every node should carry the label. |
| `labelSelector` | selects the *other* pods (`matchLabels` / `matchExpressions`) |
| `namespaces` / `namespaceSelector` | where to look for those pods. Default: the pod's own namespace. `namespaceSelector: {}` = all namespaces. The term applies to the union of both fields. |
| `matchLabelKeys` / `mismatchLabelKeys` | take label values from the incoming pod (e.g. `pod-template-hash`) - **GA since v1.33** |
| required anti-affinity | the `LimitPodHardAntiAffinityTopology` admission plugin (if enabled) restricts `topologyKey` to `kubernetes.io/hostname` |
| performance | inter-pod affinity is expensive; the docs advise against it in clusters larger than several hundred nodes (use topology spread instead) |

### Taints and tolerations ([yaml/taints-tolerations-pod.yaml](yaml/taints-tolerations-pod.yaml))

```bash
k taint nodes node01 dedicated=gpu:NoSchedule       # add   key=value:Effect
k taint nodes node01 dedicated=gpu:NoSchedule-      # remove that exact taint (trailing -)
k taint nodes node01 dedicated-                     # remove ALL taints with key "dedicated"
k taint nodes node01 dedicated=ml:NoSchedule --overwrite   # change the value
k taint nodes -l pool=gpu dedicated=gpu:NoSchedule  # many nodes by label
k describe node node01 | grep -i -A3 taints         # show taints
```

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: gpu-job
spec:
  tolerations:
  - key: dedicated
    operator: Equal          # default; key + value + effect must match
    value: gpu
    effect: NoSchedule
  - key: maintenance
    operator: Exists         # any value; no "value" field allowed
    effect: NoExecute
    tolerationSeconds: 60    # NoExecute only: stay 60 s after the taint appears, then be evicted
  nodeSelector:
    dedicated: gpu           # the toleration only PERMITS; this ATTRACTS
  containers:
  - name: worker
    image: busybox:1.36
    command: ["sh", "-c", "sleep 3600"]
```

| Effect | New pods without toleration | Running pods without toleration |
|---|---|---|
| `NoSchedule` | not scheduled | stay |
| `PreferNoSchedule` | avoided if possible (soft) | stay |
| `NoExecute` | not scheduled | **evicted immediately**; tolerating pods stay forever, or for `tolerationSeconds` |

| Toleration rule | Detail |
|---|---|
| Matching | same key and same effect, and (`operator: Exists`) or (`operator: Equal` and same value) |
| Empty `key` + `operator: Exists` | tolerates every taint (still matched against `effect` if set) |
| Empty `effect` | matches all effects of that key |
| Built-in taints | `node.kubernetes.io/not-ready`, `unreachable`, `memory-pressure`, `disk-pressure`, `pid-pressure`, `network-unavailable`, `unschedulable`; `node.cloudprovider.kubernetes.io/uninitialized` |
| Automatic tolerations | every pod gets `not-ready` and `unreachable` `NoExecute` tolerations with `tolerationSeconds: 300` (5 min) unless set explicitly; DaemonSet pods get extra ones automatically |
| Control-plane taint | `node-role.kubernetes.io/control-plane:NoSchedule` (kubeadm) |
| Numeric `Gt`/`Lt` operators for tolerations | **alpha since v1.35**, feature gate `TaintTolerationComparisonOperators`, disabled by default - do not rely on it |

### Topology spread constraints ([yaml/topology-spread-deployment.yaml](yaml/topology-spread-deployment.yaml))

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: spread-web
spec:
  replicas: 6
  selector:
    matchLabels:
      app: spread-web
  template:
    metadata:
      labels:
        app: spread-web
    spec:
      topologySpreadConstraints:
      - maxSkew: 1
        topologyKey: kubernetes.io/hostname
        whenUnsatisfiable: DoNotSchedule
        labelSelector:
          matchLabels:
            app: spread-web
        matchLabelKeys: ["pod-template-hash"]
        nodeTaintsPolicy: Honor
      - maxSkew: 1
        topologyKey: topology.kubernetes.io/zone
        whenUnsatisfiable: ScheduleAnyway
        labelSelector:
          matchLabels:
            app: spread-web
      containers:
      - name: nginx
        image: nginx:1.27
```

| Field | Meaning |
|---|---|
| `maxSkew` | max allowed difference between the number of matching pods in a domain and the global minimum (must be > 0) |
| `topologyKey` | node label defining the domains (`kubernetes.io/hostname`, `topology.kubernetes.io/zone`) |
| `whenUnsatisfiable` | required: `DoNotSchedule` (hard filter) or `ScheduleAnyway` (soft, only scoring) |
| `labelSelector` | which pods are counted - should match the pod's own labels, otherwise it does not count itself |
| `minDomains` | with `DoNotSchedule` only: treat the global minimum as 0 until this many domains exist (stable, no feature gate since v1.30) |
| `matchLabelKeys` | add the incoming pod's values for these keys to the selector, e.g. `pod-template-hash` = per rollout revision (beta, on by default) |
| `nodeAffinityPolicy` | `Honor` (default): only nodes matching the pod's nodeSelector/affinity count; `Ignore`: all nodes count |
| `nodeTaintsPolicy` | `Ignore` (default): tainted nodes count as domains too; `Honor`: only untainted or tolerated nodes count |

Without any constraint the scheduler applies built-in soft defaults (`maxSkew: 3` per hostname, `maxSkew: 5` per zone, both `ScheduleAnyway`) to pods owned by a Service/ReplicaSet/StatefulSet. Spread is only enforced at scheduling time - scale-down can leave pods unbalanced (the Descheduler can rebalance).

> **Exam tip:** with `DoNotSchedule` on `topology.kubernetes.io/zone`, nodes **without** that label cannot take the pod (event: `didn't match pod topology spread constraints (missing required label)`). kind/minikube nodes usually have no zone label - use `kubernetes.io/hostname` there.

### PriorityClass and preemption ([yaml/priorityclass.yaml](yaml/priorityclass.yaml))

```yaml
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: high-priority
value: 1000000
globalDefault: false
preemptionPolicy: PreemptLowerPriority
description: "Business-critical services"
---
apiVersion: v1
kind: Pod
metadata:
  name: critical-api
spec:
  priorityClassName: high-priority
  containers:
  - name: nginx
    image: nginx:1.27
```

| Fact | Detail |
|---|---|
| Scope | cluster-scoped, `scheduling.k8s.io/v1`, short name `pc` |
| `value` | 32-bit integer, user classes up to 1,000,000,000; larger values are reserved |
| Built-in classes | `system-cluster-critical` (2000000000) and `system-node-critical` (2000001000) - for cluster components |
| `globalDefault: true` | at most one class; used for **new** pods without `priorityClassName`; without it, such pods get priority 0 |
| `preemptionPolicy` | `PreemptLowerPriority` (default) or `Never` (higher in the queue, never evicts others) |
| Pod side | `spec.priorityClassName`; the admission plugin fills `spec.priority`; an unknown class name is rejected |
| Preemption | a pending higher-priority pod may evict lower-priority pods on one node (graceful termination); it records `status.nominatedNodeName` while waiting. PDBs are respected on a best-effort basis only. |
| Deleting a class | existing pods keep their priority; new pods cannot use the name |

---

## Imperative commands

```bash
# Inspect nodes
k get nodes --show-labels
k get nodes -L kubernetes.io/hostname,topology.kubernetes.io/zone,disktype
k get nodes -o custom-columns='NAME:.metadata.name,TAINTS:.spec.taints[*].key,EFFECTS:.spec.taints[*].effect'
k describe node node01 | grep -A8 -i 'allocated resources'   # requested vs allocatable

# Labels and taints
k label node node01 disktype=ssd
k label node node01 disktype-
k taint nodes node01 dedicated=gpu:NoSchedule
k taint nodes node01 dedicated=gpu:NoSchedule-
k cordon node01 ; k uncordon node01                           # unschedulable flag (drain: see 06)

# No flags for affinity/tolerations: generate, then add the block
k run gpu --image=busybox:1.36 $do -- sleep 3600 > gpu.yaml   # then add tolerations/affinity in vim
k run sel --image=nginx:1.27 $do --overrides='{"apiVersion":"v1","spec":{"nodeSelector":{"disktype":"ssd"}}}' > sel.yaml

# Add placement to an existing Deployment (rolls out new pods)
k patch deploy web -p '{"spec":{"template":{"spec":{"nodeSelector":{"disktype":"ssd"}}}}}'
k patch deploy web --type=json -p '[{"op":"add","path":"/spec/template/spec/tolerations","value":[{"key":"dedicated","operator":"Equal","value":"gpu","effect":"NoSchedule"}]}]'

# PriorityClass
k create priorityclass high-priority --value=1000000 --description="critical apps" $do > pc.yaml
k create priorityclass batch-low --value=1000 --preemption-policy=Never
k get pc
k get pods -o custom-columns=NAME:.metadata.name,CLASS:.spec.priorityClassName,PRIORITY:.spec.priority

# Where did it land / why not?
k get pods -o wide
k describe pod web | sed -n '/Events:/,$p'
k get events --field-selector reason=FailedScheduling
```

### Reading "0/3 nodes are available" messages

```text
Warning  FailedScheduling  8s  default-scheduler  0/3 nodes are available: 1 node(s) had untolerated taint
{node-role.kubernetes.io/control-plane: }, 2 node(s) didn't match Pod's node affinity/selector. preemption: 0/3
nodes are available: 3 Preemption is not helpful for scheduling.
```

Read it as: 3 nodes in total, 0 feasible; each node is rejected for the reason listed (the counts add up to 3). The `preemption:` part says whether evicting lower-priority pods could help. Wording varies slightly between versions.

| Fragment | Cause | Fix |
|---|---|---|
| `Insufficient cpu` / `Insufficient memory` | requests do not fit the remaining allocatable capacity | lower the requests, free capacity, check `k describe node` → Allocated resources |
| `didn't match Pod's node affinity/selector` | nodeSelector / required node affinity matches no node | `k get nodes --show-labels`, fix the typo or label a node |
| `had untolerated taint {key: value}` | taint without matching toleration | add the toleration (or remove the taint) |
| `node(s) were unschedulable` | node is cordoned | `k uncordon <node>` |
| `didn't match pod anti-affinity rules` | a matching pod already occupies that domain | more nodes, fewer replicas, or a preferred rule |
| `didn't satisfy existing pods anti-affinity rules` | another pod's anti-affinity rejects this pod | review the other pod's rules |
| `didn't match pod affinity rules` | no node runs the pods this pod must be near | check labels/namespace of the target pods |
| `didn't match pod topology spread constraints` | placing it would exceed `maxSkew` with `DoNotSchedule` | `ScheduleAnyway`, raise `maxSkew`, add domains |
| `... (missing required label)` | node lacks the `topologyKey` label | label nodes or use another key |
| `didn't have free ports for the requested pod ports` | `hostPort` already used | remove `hostPort` or pick another |
| `pod has unbound immediate PersistentVolumeClaims` | PVC is Pending | fix PVC / StorageClass |
| `had volume node affinity conflict` | the PV is bound to another zone/node | use `WaitForFirstConsumer`, match the zone |
| `Too many pods` | node reached its max-pods limit | more nodes |
| `No preemption victims found for incoming pod` | nothing of lower priority to evict | - |

---

## Exam traps & tips

> **Exam tip:** a toleration alone does not move a pod to the tainted node - it only allows it. "Run on the control plane" = toleration for `node-role.kubernetes.io/control-plane:NoSchedule` **plus** `nodeSelector: {node-role.kubernetes.io/control-plane: ""}` (or `nodeName`).

> **Exam tip:** removing a taint needs the trailing minus on the full spec: `k taint nodes node01 key=value:NoSchedule-`. `k taint nodes node01 key-` removes every effect of that key.

> **Exam tip:** in preferred rules the pod term sits under `podAffinityTerm:` and node terms under `preference:`; in required rules they sit directly in the list. Copy the structure from the docs or from [yaml/](yaml/) instead of typing it.

> **Exam tip:** `kubectl explain pod.spec.affinity.podAntiAffinity --recursive` shows the exact nesting when you forget it.

- `tolerationSeconds` is only valid with `effect: NoExecute`.
- Values for `Gt`/`Lt` and for labels in YAML are strings: `values: ["3"]`, `value: "true"`.
- Changing node labels does not move running pods (`IgnoredDuringExecution`); delete the pods or roll out the Deployment.
- Adding a `NoExecute` taint evicts every pod that does not tolerate it - including your other exam pods on that node.
- A pod pinned with `nodeName` to a node that does not exist never runs (and may be deleted automatically).

---

## Architect notes

- Prefer **topology spread constraints** (zone first, then hostname) over pod anti-affinity for HA - cheaper for the scheduler and flexible with `maxSkew`/`minDomains`.
- Dedicated node pools (GPU, licensed software, PCI workloads) = taint + toleration + node affinity, ideally enforced by admission policy so nobody can sneak in with a toleration alone.
- Requests drive scheduling: without realistic CPU/memory requests every placement rule is built on sand. Enforce them with LimitRange defaults and policies.
- Keep `nodeName` out of production manifests; it bypasses scheduling, quotas on node resources and future rebalancing.
- Define 3-5 PriorityClasses cluster-wide (e.g. platform-critical, business-critical, default via `globalDefault`, batch with `preemptionPolicy: Never`) and limit who may use the high ones with ResourceQuota `scopeSelector` on PriorityClass.
- Node autoscalers (Cluster Autoscaler, Karpenter) simulate scheduling with these same rules - zone-spread constraints across empty node groups need an autoscaler that understands topology.
- The Descheduler can evict pods that violate spread/affinity after scale events so the scheduler can place them again.

---

## Docs to bookmark

- Assigning Pods to Nodes (nodeSelector, affinity, nodeName): https://kubernetes.io/docs/concepts/scheduling-eviction/assign-pod-node/
- Assign Pods to Nodes using Node Affinity (task): https://kubernetes.io/docs/tasks/configure-pod-container/assign-pods-nodes-using-node-affinity/
- Taints and Tolerations: https://kubernetes.io/docs/concepts/scheduling-eviction/taint-and-toleration/
- Pod Topology Spread Constraints: https://kubernetes.io/docs/concepts/scheduling-eviction/topology-spread-constraints/
- Pod Priority and Preemption: https://kubernetes.io/docs/concepts/scheduling-eviction/pod-priority-preemption/
- Kubernetes Scheduler overview: https://kubernetes.io/docs/concepts/scheduling-eviction/kube-scheduler/
- Well-Known Labels, Annotations and Taints: https://kubernetes.io/docs/reference/labels-annotations-taints/

---

## Quick self-check

1. Node `node01` has taint `env=prod:NoSchedule` and label `env=prod`. Write the pod fields that make a pod run **only** there.
2. What is the difference between `NoSchedule` and `NoExecute` for pods already running on the node?
3. Which node affinity operators are not allowed in pod affinity?
4. A Deployment with required pod anti-affinity on `kubernetes.io/hostname` has 4 replicas on a 3-node cluster. What happens?
5. A pod is Pending with `0/2 nodes are available: 2 Insufficient memory`. Name two fixes.
6. What does `preemptionPolicy: Never` change?

<details><summary>Answers</summary>

1. `tolerations: [{key: env, operator: Equal, value: prod, effect: NoSchedule}]` plus `nodeSelector: {env: prod}` (or required node affinity on `env In [prod]`).
2. `NoSchedule` leaves running pods alone; `NoExecute` evicts running pods that do not tolerate it (tolerating pods stay forever or for `tolerationSeconds`).
3. `Gt` and `Lt`.
4. Three pods run (one per node); the fourth stays Pending with `didn't match pod anti-affinity rules`.
5. Lower the pod's memory request, free or add capacity (scale down other workloads, add nodes) - check `k describe node` → Allocated resources.
6. Pods of that class are queued ahead of lower-priority pods but never preempt (evict) running pods.

</details>
