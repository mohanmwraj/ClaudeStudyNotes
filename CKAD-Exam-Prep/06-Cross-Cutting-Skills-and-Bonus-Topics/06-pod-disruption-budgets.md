# PodDisruptionBudgets (PDB)

**Why it matters / what the exam expects:** PDBs are CKA territory and rare in CKAD, but "make sure at least 2 pods of `web` stay available during voluntary disruptions" is a 30-second task with `kubectl create pdb` - easy points if you know the flags and what `ALLOWED DISRUPTIONS` means. Architects need PDBs for every multi-replica production service. Frequency: 🧊 Low.

> Conventions: `alias k=kubectl`, `export do="--dry-run=client -o yaml"`.

---

## Core concepts

### Voluntary vs involuntary disruptions

| Disruption | Kind | Does a PDB protect against it? |
|---|---|---|
| Node hardware failure, VM deleted by the cloud, kernel panic, network partition | involuntary | no |
| kubelet node-pressure eviction (memory/disk), container OOMKilled | involuntary | no |
| `kubectl drain` (uses the **Eviction API**) | voluntary | **yes** |
| Cluster Autoscaler / Karpenter scale-down or consolidation (evictions) | voluntary | **yes** |
| VPA updater (`Recreate`), Descheduler, any tool calling the Eviction API | voluntary | **yes** |
| Scheduler preemption | voluntary | best effort only |
| `kubectl delete pod`, deleting the Deployment, scaling down | voluntary | **no** - plain DELETE bypasses PDBs |
| Deployment / StatefulSet rolling update | voluntary | **no** - governed by `maxUnavailable`/`maxSurge` / `partition`, not by the PDB |

A PDB is checked **only** when something calls the Eviction API (`pods/<name>/eviction`).

### Spec and status

| Field | Meaning |
|---|---|
| `spec.selector` | label selector for the protected pods; in `policy/v1` an empty selector `{}` matches **every pod in the namespace** |
| `spec.minAvailable` | pods that must stay healthy - integer or percentage string (`"50%"`) |
| `spec.maxUnavailable` | pods that may be unavailable - integer or percentage string |
| (exactly one of the two) | `minAvailable` and `maxUnavailable` are mutually exclusive |
| `spec.unhealthyPodEvictionPolicy` | `IfHealthyBudget` (default) or `AlwaysAllow` - **GA since v1.31** |
| `status.expectedPods` | pods the budget is computed against (from the owning controller's scale) |
| `status.currentHealthy` / `status.desiredHealthy` | healthy (Ready) pods now / pods that must stay healthy |
| `status.disruptionsAllowed` | `currentHealthy - desiredHealthy` (never below 0) = `ALLOWED DISRUPTIONS` column |

```text
$ kubectl get pdb
NAME      MIN AVAILABLE   MAX UNAVAILABLE   ALLOWED DISRUPTIONS   AGE
pdb-web   2               N/A               1                     40s
```

### Rounding and worked examples

Percentages are **rounded up** for both fields: `minAvailable: "50%"` of 7 pods → 4 must stay; `maxUnavailable: "25%"` of 5 pods → 2 may go (so a disruption can exceed the stated percentage).

| Replicas (all healthy) | PDB | desiredHealthy | ALLOWED DISRUPTIONS |
|---|---|---|---|
| 3 | `minAvailable: 2` | 2 | 1 |
| 3 | `maxUnavailable: 1` | 2 | 1 |
| 7 | `minAvailable: "50%"` | 4 | 3 |
| 4 | `maxUnavailable: "25%"` | 3 | 1 |
| 5 | `maxUnavailable: "25%"` | 3 | 2 |
| 1 | `minAvailable: 1` | 1 | **0** - every drain of that node blocks forever |
| 1 | `maxUnavailable: 1` | 0 | 1 - the single replica may go (100 % downtime) |
| 3 | `minAvailable: 3` or `maxUnavailable: 0` | 3 | **0** - blocks all evictions |

### unhealthyPodEvictionPolicy

| Policy | Running-but-not-Ready pods (e.g. CrashLoopBackOff) |
|---|---|
| `IfHealthyBudget` (default) | may be evicted only if the application is currently not disrupted (`currentHealthy >= desiredHealthy`) - a broken app can block node drains |
| `AlwaysAllow` | may always be evicted - drains are never blocked by unhealthy pods; recommended for most apps |

Pods in `Pending`, `Succeeded` or `Failed` phase can always be evicted.

### Restrictions

- With bare pods or pods owned by non-scalable controllers: only `minAvailable`, and only as an **integer** (Kubernetes cannot know the expected total). `maxUnavailable` and percentages need a Deployment, ReplicaSet, StatefulSet, ReplicationController or a custom resource with a `scale` subresource.
- A pod covered by **more than one** PDB cannot be evicted at all - avoid overlapping selectors.
- `policy/v1beta1` PodDisruptionBudget was removed in v1.25 (and its empty selector meant "nothing", the opposite of v1).

---

## Key fields / syntax

### minAvailable ([yaml/pdb-min-available.yaml](yaml/pdb-min-available.yaml))

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: pdb-web
spec:
  minAvailable: 2
  selector:
    matchLabels:
      app: pdb-web
```

### maxUnavailable with percentage and AlwaysAllow ([yaml/pdb-max-unavailable.yaml](yaml/pdb-max-unavailable.yaml))

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: pdb-cache
spec:
  maxUnavailable: "25%"                     # quoted: percentages are strings
  unhealthyPodEvictionPolicy: AlwaysAllow
  selector:
    matchLabels:
      app: pdb-cache
```

---

## Imperative commands

```bash
# Create
k create pdb web-pdb --selector=app=web --min-available=2 $do > pdb.yaml     # generate
k create pdb web-pdb --selector=app=web --min-available=2                    # create directly
k create pdb web-pdb --selector=app=web --max-unavailable=1
k create pdb web-pdb --selector=app=web --min-available=50%
k patch pdb web-pdb --type=merge -p '{"spec":{"unhealthyPodEvictionPolicy":"AlwaysAllow"}}'   # no flag for it

# Inspect
k get pdb                                             # short name for poddisruptionbudgets
k describe pdb web-pdb                                # selector, allowed disruptions, events
k get pdb web-pdb -o jsonpath='{.status.currentHealthy}/{.status.desiredHealthy} allowed={.status.disruptionsAllowed}{"\n"}'
k get pods -l app=web --show-labels                   # does the selector really match?

# Exercise it: drain = cordon + evict
k drain node01 --ignore-daemonsets --delete-emptydir-data                    # whole node
k drain node01 --ignore-daemonsets --pod-selector=app=web --timeout=60s      # only these pods (safe in labs)
k uncordon node01                                                            # make it schedulable again
```

When the budget is exhausted, drain keeps retrying:

```text
evicting pod default/pdb-web-7d9c8b6f5-abcde
error when evicting pods/"pdb-web-7d9c8b6f5-abcde" -n "default" (will retry after 5s): Cannot evict pod as it would violate the pod's disruption budget.
```

| `kubectl drain` flag | Why |
|---|---|
| `--ignore-daemonsets` | required when DaemonSet pods run on the node (they are not evicted) |
| `--delete-emptydir-data` | allow evicting pods with `emptyDir` volumes (data is lost) |
| `--force` | also delete pods without a controller (bare pods are gone for good) |
| `--pod-selector=<sel>` | only evict matching pods |
| `--grace-period=<s>` / `--timeout=<d>` | per-pod termination grace / give up after this long |
| `--disable-eviction` | use DELETE instead of eviction - **bypasses PDBs**, use with care |
| `--dry-run=client` | show what would be evicted |

Calling the Eviction API directly (what drain does per pod; HTTP 429 means the PDB refused):

```bash
POD=$(k get pods -l app=pdb-web -o jsonpath='{.items[0].metadata.name}')
cat <<EOF | k create --raw /api/v1/namespaces/default/pods/$POD/eviction -f -
{"apiVersion":"policy/v1","kind":"Eviction","metadata":{"name":"$POD","namespace":"default"}}
EOF
```

### Interaction with rolling updates

- The Deployment controller replaces pods with normal deletes, so a PDB does **not** slow or block a rollout - `strategy.rollingUpdate.maxUnavailable` / `maxSurge` do that job.
- During a rollout, pods that are not Ready reduce `currentHealthy`, so a drain running at the same time may be blocked until the rollout finishes.
- Keep both consistent: e.g. Deployment `maxUnavailable: 1` and PDB `maxUnavailable: 1`.

### Sizing rules

| Workload | Suggested PDB |
|---|---|
| Stateless, 2+ replicas | `maxUnavailable: 1` (or `"25%"` for large/HPA-managed fleets) |
| Quorum system with 3 members (etcd, ZooKeeper, Kafka controllers) | `maxUnavailable: 1` (= `minAvailable: 2`) |
| Quorum system with 5 members | `maxUnavailable: 1`, or `minAvailable: 3` |
| Single replica | no PDB (or `maxUnavailable: 1`) - a `minAvailable: 1` PDB just blocks maintenance; fix the replica count instead |
| Apps that may crash-loop | add `unhealthyPodEvictionPolicy: AlwaysAllow` |

---

## Exam traps & tips

> **Exam tip:** you cannot test a PDB with `kubectl delete pod` - deletes ignore it. Use `kubectl drain` (with `--pod-selector` in a shared cluster) or the eviction call above.

> **Exam tip:** `ALLOWED DISRUPTIONS 0` with a selector typo looks "protective" but protects nothing - check `k describe pdb` (expected pods 0) and compare the selector with `k get pods --show-labels`.

> **Exam tip:** in YAML, percentages must be strings: `minAvailable: "50%"`. With `kubectl create pdb --min-available=50%` kubectl handles it.

- `minAvailable` and `maxUnavailable` together is invalid.
- `k create pdb --selector` accepts only equality-based selectors (`app=web,tier=fe`); for `matchExpressions` generate with `$do` and edit the YAML.
- `kubectl drain` without `--ignore-daemonsets` fails as soon as a DaemonSet pod is on the node.
- Draining the only node of a lab cluster evicts CoreDNS too - use `--pod-selector`, then `k uncordon`.
- `policy/v1beta1` manifests from old tutorials fail on v1.25+; use `policy/v1`.

---

## Architect notes

- Every production service with 2+ replicas should ship a PDB in its Helm chart / Kustomize base; platform teams can enforce this with admission policies.
- Prefer `maxUnavailable` over `minAvailable`: it keeps working when the HPA changes the replica count.
- A `minAvailable` equal to the replica count (or `maxUnavailable: 0`) blocks node upgrades and autoscaler consolidation indefinitely - flag it in policy checks; managed Kubernetes upgrades may wait or eventually force their way through.
- Use `unhealthyPodEvictionPolicy: AlwaysAllow` by default so a crash-looping app cannot stall cluster maintenance.
- PDBs do not protect against zone outages - combine them with topology spread across zones and enough replicas per zone.
- Cluster Autoscaler and Karpenter honour PDBs during scale-down; tight PDBs reduce bin-packing efficiency and raise cost.
- For stateful quorum systems, also make sure the operator or StatefulSet update strategy matches the PDB (one member at a time).

---

## Docs to bookmark

- Disruptions (concepts, voluntary vs involuntary): https://kubernetes.io/docs/concepts/workloads/pods/disruptions/
- Specifying a Disruption Budget for your Application: https://kubernetes.io/docs/tasks/run-application/configure-pdb/
- API-initiated Eviction: https://kubernetes.io/docs/concepts/scheduling-eviction/api-eviction/
- Safely Drain a Node: https://kubernetes.io/docs/tasks/administer-cluster/safely-drain-node/

---

## Quick self-check

1. Create a PDB `api-pdb` that allows at most one `app=api` pod to be unavailable.
2. Deployment with 5 replicas, PDB `minAvailable: "60%"`. How many pods may a drain evict at once?
3. Why did a rolling update take the Deployment below `minAvailable` even though a PDB exists?
4. A drain hangs with "Cannot evict pod as it would violate the pod's disruption budget". Name two safe ways forward.
5. What does an empty selector mean in a `policy/v1` PDB?

<details><summary>Answers</summary>

1. `k create pdb api-pdb --selector=app=api --max-unavailable=1`
2. 60 % of 5 = 3 must stay (exactly 3, no rounding needed) → 2 may be evicted.
3. Rollouts use normal deletes, not the Eviction API; they are limited by the Deployment's `maxUnavailable`/`maxSurge`, not by PDBs.
4. Scale the workload up (or wait until new pods are Ready elsewhere) so `disruptionsAllowed` > 0; or adjust the PDB (e.g. `maxUnavailable: 1`, `unhealthyPodEvictionPolicy: AlwaysAllow` for crash-looping pods). Last resort: `--disable-eviction` (bypasses the budget).
5. It matches every pod in the PDB's namespace.

</details>
