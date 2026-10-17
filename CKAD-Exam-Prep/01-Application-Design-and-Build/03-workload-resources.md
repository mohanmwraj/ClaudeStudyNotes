# Choosing the Right Workload Resource

**Why it matters:** the competency is *"Choose and use the right workload resource (Deployment, DaemonSet, CronJob, etc.)"*. Exam tasks often describe a **requirement** ("one pod on every node", "every 15 minutes", "each replica keeps its own data") rather than name the kind. Picking the wrong kind scores zero even if the YAML is perfect. After choosing, you need the fastest way to produce the YAML, and some kinds have no `kubectl create` generator.

---

## Core concepts

### Decision table

| Resource | apiVersion | Use when | Pods and identity | Key fields | Update strategy | Pod `restartPolicy` | Imperative create |
|---|---|---|---|---|---|---|---|
| **Pod** | `v1` | debugging, a one-off test, static pods | 1; no self-healing, no rescheduling | `containers` | most fields immutable → `replace --force` | Always / OnFailure / Never | `kubectl run` |
| **ReplicaSet** | `apps/v1` | N identical pods without rollouts (normally created **by** a Deployment) | N interchangeable, `<rs>-<random>` | `replicas`, `selector`, `template` | none: template edits affect only new pods | Always | none, write YAML |
| **Deployment** | `apps/v1` | stateless apps; rolling update, rollback, scaling | N interchangeable, `<deploy>-<template-hash>-<random>` | `replicas`, `selector`, `template`, `strategy`, `minReadySeconds`, `revisionHistoryLimit`, `progressDeadlineSeconds` | RollingUpdate (25 %/25 %) or Recreate | Always | `kubectl create deployment` |
| **StatefulSet** | `apps/v1` | stable identity, ordered start/stop, **storage per pod** (databases, quorum systems) | N with ordinals `<sts>-0..N-1`, stable DNS via headless Service, own PVC each | `serviceName`, `volumeClaimTemplates`, `podManagementPolicy`, `updateStrategy.rollingUpdate.partition`, `persistentVolumeClaimRetentionPolicy` | RollingUpdate (reverse ordinal, partition) or OnDelete | Always | none, write YAML |
| **DaemonSet** | `apps/v1` | one pod per (selected) node: log/metrics agents, CNI/CSI node plugins, kube-proxy | 1 per eligible node; no `replicas` | `selector`, `template` (+ `nodeSelector`, `tolerations`), `updateStrategy` | RollingUpdate (maxUnavailable 1, maxSurge 0) or OnDelete | Always | none, write YAML |
| **Job** | `batch/v1` | run to **completion**: batch, migration, backup, report | until `completions` pods succeed | `completions`, `parallelism`, `backoffLimit`, `activeDeadlineSeconds`, `ttlSecondsAfterFinished`, `completionMode` | n/a (pod template immutable) | **Never / OnFailure** | `kubectl create job` |
| **CronJob** | `batch/v1` | Jobs on a **schedule** | creates Jobs `<cronjob>-<scheduled-minutes>` | `schedule`, `timeZone`, `concurrencyPolicy`, `startingDeadlineSeconds`, history limits, `suspend`, `jobTemplate` | edits apply from the next Job | **Never / OnFailure** | `kubectl create cronjob` |
| **ReplicationController** | `v1` | **legacy** only: recognise and migrate | like a ReplicaSet | `replicas`, `selector` (plain map), `template` | none (`kubectl rolling-update` removed) | Always | none, write YAML |

### Exam phrasing → resource

| The task says... | Use |
|---|---|
| "N replicas", "rolling update", "roll back", "zero downtime", "stateless web/API" | **Deployment** |
| "on every node", "one per node", "all nodes including the control plane", "node agent", "log collector", "monitoring exporter" | **DaemonSet** (+ control-plane toleration) |
| "stable hostname / network identity", "`app-0`, `app-1`", "ordered startup", "each replica its own volume", "database cluster" | **StatefulSet** + headless Service |
| "run once", "until it succeeds", "batch", "migration", "compute X and exit" | **Job** |
| "6 completions, 2 at a time" | Job `completions: 6`, `parallelism: 2` |
| "each pod processes a different shard / index" | **Indexed** Job (`completionMode: Indexed`) |
| "retry at most 3 times" | Job `backoffLimit: 3` |
| "must not run longer than 60 seconds" | Job `activeDeadlineSeconds: 60` |
| "delete the Job automatically 2 minutes after it finishes" | `ttlSecondsAfterFinished: 120` |
| "every 5 minutes", "nightly at 02:00", "on Mondays" | **CronJob** |
| "a new run must not start while the previous one is still running" | CronJob `concurrencyPolicy: Forbid` |
| "keep exactly N pods; no rollout functionality needed" | ReplicaSet (rare) |
| "temporary pod to test connectivity / run one command" | `kubectl run tmp --rm -it --restart=Never ...` |
| "pod started by the kubelet from a file on the node" | static Pod |

### Ownership: who manages whom

```text
Deployment  --owns-->  ReplicaSet (one per pod-template revision)  --owns-->  Pods
StatefulSet --owns-->  Pods (+ ControllerRevisions); PVCs are created from volumeClaimTemplates
DaemonSet   --owns-->  Pods (+ ControllerRevisions)
CronJob     --owns-->  Jobs  --owns-->  Pods
```

- The child's `metadata.ownerReferences` points to the parent. Deleting the parent **cascades**: `--cascade=background` (default), `foreground`, or `orphan` (keep the children).
- Controllers find their pods by **label selector**. In `apps/v1`, `spec.selector` is **required**, must match `spec.template.metadata.labels`, and is **immutable**.
- ReplicaSets (and Deployments through them) **adopt** existing orphan pods that match the selector and delete surplus ones. Never let selectors of different controllers overlap.

### Update strategies at a glance

| Kind | Strategies | Default | Knobs | `kubectl rollout` |
|---|---|---|---|---|
| Deployment | RollingUpdate, Recreate | RollingUpdate, maxSurge 25 % (rounds up), maxUnavailable 25 % (rounds down) | `minReadySeconds`, `progressDeadlineSeconds` (600), `revisionHistoryLimit` (10) | status, history, undo, restart, pause, resume |
| DaemonSet | RollingUpdate, OnDelete | RollingUpdate, maxUnavailable 1, maxSurge 0 | `minReadySeconds` | status, history, undo, restart |
| StatefulSet | RollingUpdate, OnDelete | RollingUpdate, partition 0, one pod at a time from the highest ordinal | `partition`, `minReadySeconds`, `maxUnavailable` (beta, see [05](05-daemonsets-and-statefulsets.md)) | status, history, undo, restart |
| ReplicaSet / RC | none | template changes affect only newly created pods | delete pods yourself | not supported |
| Job | none | pod template is immutable | delete and recreate the Job | not supported |
| CronJob | none | template changes apply to the **next** Job | | not supported |

Only changes to the **pod template** create a new revision (a new ReplicaSet for Deployments, a new ControllerRevision for DaemonSets and StatefulSets). Scaling does not. Deployment rollouts, rollbacks and blue/green/canary are covered in [../02-Application-Deployment/README.md](../02-Application-Deployment/README.md).

### Restart policy constraints

- Deployment, ReplicaSet, StatefulSet, DaemonSet, ReplicationController: the pod template's `restartPolicy` must be `Always` (or omitted, which defaults to Always).
- Job and CronJob: you **must** set `Never` or `OnFailure`. An omitted value defaults to `Always`, which the API rejects. `kubectl create job` writes `Never` for you.

### Kinds without a `kubectl create` generator

| Target | Generate | Then change |
|---|---|---|
| ReplicaSet | `kubectl create deployment x --image=IMG --dry-run=client -o yaml > rs.yaml` | `kind: ReplicaSet`; delete `strategy: {}` |
| DaemonSet | same | `kind: DaemonSet`; delete `replicas:` and `strategy: {}`; optionally add `updateStrategy` and tolerations |
| StatefulSet | same | `kind: StatefulSet`; delete `strategy: {}`; add `serviceName:`; optionally `volumeClaimTemplates`; create the headless Service |
| ReplicationController | write by hand | plain-map `selector` |

Fields that do not exist for the new kind fail strict validation, for example `strict decoding error: unknown field "spec.strategy"`. Step-by-step conversion: [05-daemonsets-and-statefulsets.md](05-daemonsets-and-statefulsets.md).

---

## Key fields / syntax

| File | Shows |
|---|---|
| [yaml/deployment.yaml](yaml/deployment.yaml) | Deployment with strategy, revisionHistoryLimit, change-cause, probe |
| [yaml/replicaset.yaml](yaml/replicaset.yaml) | ReplicaSet with `matchLabels` + `matchExpressions` |
| [yaml/replicationcontroller-legacy.yaml](yaml/replicationcontroller-legacy.yaml) | legacy RC with a map selector |
| [yaml/daemonset.yaml](yaml/daemonset.yaml) | DaemonSet with control-plane toleration and updateStrategy |
| [yaml/statefulset-with-headless-svc.yaml](yaml/statefulset-with-headless-svc.yaml) | StatefulSet + headless Service + volumeClaimTemplates |
| [yaml/job.yaml](yaml/job.yaml), [yaml/job-parallel-indexed.yaml](yaml/job-parallel-indexed.yaml) | Job fields, Indexed Job |
| [yaml/cronjob.yaml](yaml/cronjob.yaml) | CronJob with every important field |
| [yaml/static-pod.yaml](yaml/static-pod.yaml) | static pod |

The skeleton shared by every `apps/v1` controller (Deployment shown):

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api
spec:
  replicas: 3                  # not for DaemonSet
  selector:
    matchLabels:
      app: api                 # must equal ...
  template:
    metadata:
      labels:
        app: api               # ... these labels
    spec:
      containers:
      - name: api
        image: nginx:1.27
```

Job and CronJob nesting (`template` → `jobTemplate.spec.template`):

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: tick
spec:
  schedule: "*/10 * * * *"
  jobTemplate:
    spec:                      # = Job spec
      template:
        spec:                  # = Pod spec
          restartPolicy: OnFailure
          containers:
          - name: tick
            image: busybox:1.36
            command: ["sh", "-c", "date"]
```

---

## Imperative commands

```bash
# Generators (always via --dry-run=client -o yaml when you need to edit)
kubectl create deployment api --image=nginx:1.27 --replicas=3 --port=80 --dry-run=client -o yaml > deploy.yaml
kubectl create job once --image=busybox:1.36 --dry-run=client -o yaml -- sh -c 'echo hi' > job.yaml
kubectl create cronjob tick --image=busybox:1.36 --schedule="*/10 * * * *" --dry-run=client -o yaml -- date > cj.yaml
kubectl create deployment agent --image=busybox:1.36 --dry-run=client -o yaml -- sleep 3600 > ds.yaml   # then convert

# Day-2 operations
kubectl scale deployment api --replicas=5                 # also: sts, rs, rc (NOT daemonset)
kubectl set image deployment/api nginx=nginx:1.27-alpine  # container=image; also ds/, sts/
kubectl rollout status deployment/api                     # also ds/, sts/
kubectl rollout restart deployment/api                    # new pods, same template (ds/, sts/ too)
kubectl rollout history deployment/api
kubectl rollout undo deployment/api [--to-revision=2]

# Inspect relationships
kubectl get deploy,rs,pods -l app=api
kubectl get pod <pod> -o jsonpath='{.metadata.ownerReferences[0].kind}/{.metadata.ownerReferences[0].name}{"\n"}'
kubectl get all -n <ns>                                   # pods, svc, deploy, rs, sts, ds, jobs, cronjobs (not PVC/CM/Secret/Ingress)
kubectl api-resources --api-group=apps                    # kinds + short names (deploy, rs, ds, sts)

# Delete
kubectl delete deployment api                             # cascades to RS and pods
kubectl delete deployment api --cascade=orphan            # keep the pods (e.g. to change an immutable selector)
```

---

## Exam traps & tips

> **Exam tip:** Read the requirement verbs. "On each node" means DaemonSet, not a Deployment with `replicas` equal to the node count. "Every N minutes" means CronJob, not a Job with a loop.

> **Exam tip:** `kubectl run` creates only Pods (the old `--generator`/`--replicas` flags are gone). For a Deployment, use `kubectl create deployment`.

> **Exam tip:** `spec.selector` is immutable. If you must change the labels it matches, delete the controller (optionally `--cascade=orphan`) and recreate it. Make sure the template labels still match the new selector.

> **Exam tip:** Job pods need `restartPolicy: Never` or `OnFailure` set explicitly. A hand-written Job without it is rejected with `Unsupported value: "Always"`.

- `kubectl scale daemonset ...` fails: DaemonSets have no replicas. Restrict nodes with `nodeSelector`/affinity instead.
- Deleting the ReplicaSet of a Deployment, or a pod of any controller, just triggers recreation. Act on the top-level owner.
- The pod template of a Job cannot be edited. Delete the Job and recreate it (`kubectl replace --force -f job.yaml`).
- A bare pod with labels matching a ReplicaSet's selector is adopted and may be deleted as surplus.
- `kubectl get all` hides PVCs, ConfigMaps, Secrets, Ingresses and ServiceAccounts. Query them explicitly.

---

## Architect notes

- **Default to Deployments.** Keep services stateless and push state to managed databases, caches or object storage. Choose a StatefulSet only when the app needs stable identity or per-replica storage, and prefer a mature **Operator** for complex stateful systems (backups, failover, upgrades).
- **DaemonSets cost every node.** Give them small, accurate requests and limits, an appropriate PriorityClass (node agents are often `system-node-critical`), and `maxSurge` for agents that must never be absent during upgrades.
- **Batch design:** make Jobs idempotent (retries and duplicate CronJob runs happen), set `ttlSecondsAfterFinished` or history limits to keep etcd lean, and use Indexed Jobs or a work queue for parallel processing. For multi-tenant batch at scale, look at queueing layers such as Kueue.
- **Availability primitives belong with the workload:** PodDisruptionBudgets for Deployments and StatefulSets, topology spread constraints or anti-affinity for zone resilience, and an HPA on the scale subresource (Deployment, StatefulSet, ReplicaSet; never a DaemonSet). See [../06-Cross-Cutting-Skills-and-Bonus-Topics/README.md](../06-Cross-Cutting-Skills-and-Bonus-Topics/README.md).
- **Rollout safety:** `maxUnavailable: 0` + `maxSurge: 1` + readiness probes + `minReadySeconds` gives conservative zero-downtime rollouts. `progressDeadlineSeconds` surfaces stuck rollouts to your CD tooling.
- **Avoid ReplicationControllers and bare ReplicaSets** in new manifests. Flag them in reviews as tech debt.

---

## Docs to bookmark

- Workload management overview: <https://kubernetes.io/docs/concepts/workloads/controllers/>
- Deployments: <https://kubernetes.io/docs/concepts/workloads/controllers/deployment/>
- ReplicaSet: <https://kubernetes.io/docs/concepts/workloads/controllers/replicaset/>
- StatefulSets: <https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/>
- DaemonSet: <https://kubernetes.io/docs/concepts/workloads/controllers/daemonset/>
- Jobs: <https://kubernetes.io/docs/concepts/workloads/controllers/job/>
- CronJob: <https://kubernetes.io/docs/concepts/workloads/controllers/cron-jobs/>
- ReplicationController: <https://kubernetes.io/docs/concepts/workloads/controllers/replicationcontroller/>
- Garbage collection and cascading deletion: <https://kubernetes.io/docs/concepts/architecture/garbage-collection/>
- Managing workloads (scale, update, labels): <https://kubernetes.io/docs/concepts/workloads/management/>

---

## Quick self-check

1. "Run exactly one `fluent-bit` pod on every node, including control-plane nodes." Which kind, and which extra field?
2. "Generate a monthly report; the report pod must be removed 10 minutes after finishing." Which kind and fields?
3. Which `apps/v1` kinds have no `kubectl create` generator, and how do you produce their YAML quickly?
4. You need to change `spec.selector.matchLabels` of a Deployment. Why does `kubectl apply` fail, and what is the fix?
5. Which kinds support `kubectl rollout undo`?

<details><summary>Answers</summary>

1. A DaemonSet with a toleration for `node-role.kubernetes.io/control-plane` (`operator: Exists`, `effect: NoSchedule`).
2. A CronJob (e.g. `schedule: "0 0 1 * *"` or `@monthly`) with `jobTemplate.spec.ttlSecondsAfterFinished: 600` and pod `restartPolicy: Never|OnFailure`.
3. ReplicaSet, DaemonSet and StatefulSet. Generate a Deployment with `kubectl create deployment ... --dry-run=client -o yaml`, change `kind`, and remove or add the kind-specific fields (`replicas`/`strategy`/`serviceName`).
4. `spec.selector` is immutable in apps/v1. Delete the Deployment (`--cascade=orphan` if the pods must survive briefly), then apply the new manifest with matching template labels.
5. Deployment, DaemonSet and StatefulSet.

</details>
