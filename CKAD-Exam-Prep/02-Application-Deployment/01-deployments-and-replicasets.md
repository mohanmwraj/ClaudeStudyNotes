# Deployments and ReplicaSets

**Why it matters.** A Deployment is the standard way to run a stateless app, and almost every exam domain touches one. You are expected to:

- create a Deployment in seconds (imperatively or from generated YAML), and scale it
- read its status and conditions
- know which edits start a rollout and which don't
- know that the selector can never be changed in place

Rolling updates and rollbacks are covered in [02-rolling-updates-and-rollbacks.md](02-rolling-updates-and-rollbacks.md).

## Core concepts

### Controller hierarchy

```text
Deployment  web                          desired state: replicas + selector + Pod template + strategy
├── ReplicaSet web-6d4b9f8c7d            current revision (e.g. revision 3), owns 3 Pods
│   ├── Pod web-6d4b9f8c7d-2xk9p         labels: app=web, pod-template-hash=6d4b9f8c7d
│   ├── Pod web-6d4b9f8c7d-8m4qz
│   └── Pod web-6d4b9f8c7d-tq7lw
├── ReplicaSet web-7f9c5b6d48            old revision 2, scaled to 0, kept for rollback
└── ReplicaSet web-58c7d9b4f6            old revision 1, scaled to 0
```

| Layer | Controller does | You normally touch it? |
|---|---|---|
| Deployment | Creates one ReplicaSet per distinct Pod template, scales new up and old down (the rollout), keeps `revisionHistoryLimit` old ReplicaSets | Yes, always |
| ReplicaSet | Keeps exactly `replicas` Pods matching its selector running (self-healing) | No: "Do not manage ReplicaSets owned by a Deployment" |
| Pod | Runs containers. Carries an `ownerReferences` entry pointing to its ReplicaSet | Only to inspect or debug |

- **`pod-template-hash`**: the Deployment controller hashes the Pod template and adds the hash as a label to the ReplicaSet selector, the ReplicaSet's Pod template, and every Pod. The ReplicaSet is named `<deployment>-<hash>`, and its Pods are `<deployment>-<hash>-<5 random chars>`. The label keeps the ReplicaSets of one Deployment from overlapping. Never change it.
- **Revision**: every ReplicaSet carries the annotation `deployment.kubernetes.io/revision: "N"`. The Deployment shows the current number in the same annotation. `kubectl rollout history` reads these ReplicaSets.
- **Ownership and deletion**: Pod → ReplicaSet → Deployment via `metadata.ownerReferences`. `kubectl delete deploy web` cascades to its ReplicaSets and Pods (background by default). `--cascade=orphan` deletes only the Deployment and leaves the ReplicaSet and Pods running.
- **Adoption**: a ReplicaSet adopts any Pod that matches its selector and has no controller owner. A hand-made Pod with label `app=web` next to a *standalone* ReplicaSet selecting `app=web` gets adopted, and may be deleted as "surplus". Deployment-owned ReplicaSets also require the `pod-template-hash` label, so they rarely adopt strays. Keep selectors specific.

### Workload objects compared

| Object | API | Self-healing | Rolling update / rollback | When to use |
|---|---|---|---|---|
| Pod | `v1` | No (container restarts only, same node) | No | One-off tasks, debugging |
| ReplicationController | `v1` | Yes | No (legacy) | Never for new work |
| ReplicaSet | `apps/v1` | Yes | No | Created for you by Deployments |
| Deployment | `apps/v1` | Yes (through ReplicaSets) | Yes (revisions, undo, pause) | Stateless apps: the default |
| StatefulSet / DaemonSet | `apps/v1` | Yes | Yes (`updateStrategy`, ControllerRevisions) | Stable identity / one Pod per node: see [../01-Application-Design-and-Build/README.md](../01-Application-Design-and-Build/README.md) |

### Spec fields you must know

| Field | Default | Notes |
|---|---|---|
| `spec.replicas` | `1` | Scaling. Changing it does **not** create a revision. If an HPA targets the Deployment, the HPA owns this value |
| `spec.selector` | (required) | Must match `spec.template.metadata.labels`. **Immutable** after creation in `apps/v1` |
| `spec.template` | (required) | The Pod template. **Any** change in here creates a new ReplicaSet (revision) |
| `spec.strategy.type` | `RollingUpdate` | Or `Recreate` (kill all, then create; downtime) |
| `spec.strategy.rollingUpdate.maxSurge` | `25%` | Pods allowed above `replicas` during an update. Integer or %, % rounds **up** |
| `spec.strategy.rollingUpdate.maxUnavailable` | `25%` | Pods allowed below `replicas`. % rounds **down**. Both can't be 0 |
| `spec.minReadySeconds` | `0` | A new Pod must be Ready this long before it counts as Available |
| `spec.revisionHistoryLimit` | `10` | Old ReplicaSets kept. `0` = cleaned up immediately, so rollback is impossible |
| `spec.progressDeadlineSeconds` | `600` | Seconds without progress before `Progressing=False / ProgressDeadlineExceeded`. Must be > `minReadySeconds` |
| `spec.paused` | `false` | `true`: template changes are stored but not rolled out |

Full annotated file: [yaml/deployment-rolling-update.yaml](yaml/deployment-rolling-update.yaml).

### Status: what the columns mean

```text
$ kubectl get deploy web -o wide
NAME   READY   UP-TO-DATE   AVAILABLE   AGE   CONTAINERS   IMAGES       SELECTOR
web    3/3     3            3           12m   web          nginx:1.27   app=web
```

| Column / field | Meaning |
|---|---|
| `READY` (`status.readyReplicas` / `spec.replicas`) | Pods passing their readiness probe / desired |
| `UP-TO-DATE` (`status.updatedReplicas`) | Pods already running the **latest** template |
| `AVAILABLE` (`status.availableReplicas`) | Ready for at least `minReadySeconds` |
| `status.unavailableReplicas` | Desired minus available |
| `status.observedGeneration` | Equal to `metadata.generation` once the controller has processed the latest spec change |
| `status.terminatingReplicas` | Terminating Pods (feature gate `DeploymentReplicaSetTerminatingReplicas`, beta and on by default since v1.35). They are not counted as available |

`kubectl get rs` shows `DESIRED  CURRENT  READY` per ReplicaSet. During a rollout you see the new ReplicaSet growing and the old one shrinking.

### Conditions (`kubectl describe deploy` or `-o yaml` → `status.conditions`)

| type | status | reason | Meaning |
|---|---|---|---|
| `Progressing` | True | `NewReplicaSetCreated`, `FoundNewReplicaSet`, `ReplicaSetUpdated` | Rollout in progress (new ReplicaSet created or scaled, old scaled down, new Pods became available) |
| `Progressing` | True | `NewReplicaSetAvailable` | Rollout **complete** |
| `Progressing` | False | `ProgressDeadlineExceeded` | No progress for `progressDeadlineSeconds`: the rollout **failed** (Kubernetes does not roll back by itself) |
| `Progressing` | False | `ReplicaSetCreateError` | The new ReplicaSet could not be created |
| `Progressing` | Unknown | `DeploymentPaused` / `DeploymentResumed` | Paused (the deadline is not checked while paused) / just resumed |
| `Available` | True / False | `MinimumReplicasAvailable` / `MinimumReplicasUnavailable` | At least `replicas - maxUnavailable` Pods available, or not |
| `ReplicaFailure` | True | `FailedCreate` | Pods can't be created. Typical causes: quota exceeded, admission (Pod Security, missing ServiceAccount). The message has the API error |

```yaml
# kubectl get deploy web -o yaml   (status excerpt of a FAILED rollout)
status:
  conditions:
  - type: Available
    status: "True"
    reason: MinimumReplicasAvailable
  - type: Progressing
    status: "False"
    reason: ProgressDeadlineExceeded
    message: ReplicaSet "web-5b8d6c9f7" has timed out progressing.
```

### What triggers a rollout and what does not

| Change | New ReplicaSet / revision? | Note |
|---|---|---|
| Image (`kubectl set image`) | **Yes** | The classic rollout |
| Env vars, command/args, ports, probes, resources, volumes in the template | **Yes** | `kubectl set env`, `kubectl set resources`, edit, apply, patch |
| Pod template labels or annotations | **Yes** | Includes `kubectl rollout restart` (adds `kubectl.kubernetes.io/restartedAt`) |
| `kubectl set serviceaccount` | **Yes** | It edits `spec.template.spec.serviceAccountName` |
| `spec.replicas` (scale, HPA) | No | Pods are added or removed in the current ReplicaSet |
| `strategy`, `minReadySeconds`, `revisionHistoryLimit`, `progressDeadlineSeconds` | No | Affect how the **next** rollout behaves |
| Deployment `metadata.labels` / `metadata.annotations` (incl. change-cause) | No | Not part of the template |
| `spec.paused: true` | No | Template edits are kept and rolled out on resume |
| Content of a referenced ConfigMap or Secret | **No** | Pods keep the old env values. Run `kubectl rollout restart` (or use a hash-suffixed name: Kustomize generators, Helm checksum annotation) |
| Changing back to an earlier template | Re-uses the old ReplicaSet | It gets a new, higher revision number |

### Selector immutability

```text
$ kubectl patch deploy web -p '{"spec":{"selector":{"matchLabels":{"app":"web2"}}}}'
The Deployment "web" is invalid: spec.selector: Invalid value: ...: field is immutable
```

To change a selector, recreate the Deployment:

- `kubectl replace --force -f web.yaml`: deletes and recreates, so Pods restart (brief downtime)
- or `kubectl delete deploy web --cascade=orphan` followed by `kubectl apply -f web.yaml`: the old Pods keep serving. Clean up the orphaned ReplicaSet afterwards

Adding a label to the template is fine. Changing or removing a label that the selector uses makes the template stop matching, which is rejected.

### Scaling

| Method | Command |
|---|---|
| Imperative | `kubectl scale deployment web --replicas=5` |
| Conditional | `kubectl scale deployment web --current-replicas=3 --replicas=5` (fails if it's not currently 3) |
| Declarative | Edit `replicas:` and `kubectl apply -f`, or `kubectl edit deploy web` |
| Patch | `kubectl patch deploy web -p '{"spec":{"replicas":5}}'` |
| Autoscaling | HPA (`autoscaling/v2`): see [../06-Cross-Cutting-Skills-and-Bonus-Topics/README.md](../06-Cross-Cutting-Skills-and-Bonus-Topics/README.md) |

If you scale during a rollout, the controller spreads the extra replicas proportionally across the new and old ReplicaSets, biased towards the larger one. This is called proportional scaling.

## Key fields / syntax

A complete Deployment with every rollout-relevant field. The same file is at [yaml/deployment-rolling-update.yaml](yaml/deployment-rolling-update.yaml):

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web
  labels:
    app: web                      # labels of the Deployment object itself (not used for selection)
  annotations:
    kubernetes.io/change-cause: "initial release nginx:1.27"
spec:
  replicas: 3
  revisionHistoryLimit: 10
  minReadySeconds: 5
  progressDeadlineSeconds: 120
  selector:
    matchLabels:
      app: web                    # must be a subset of the template labels; immutable
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0
  template:
    metadata:
      labels:
        app: web
    spec:
      containers:
      - name: web                 # the name used by `kubectl set image deploy/web web=...`
        image: nginx:1.27
        ports:
        - containerPort: 80
```

`matchExpressions` also works. All requirements of `matchLabels` and `matchExpressions` are ANDed:

```yaml
selector:
  matchLabels:
    app: web
  matchExpressions:
  - key: tier
    operator: In
    values: ["frontend"]
```

For a Recreate example, see [yaml/deployment-recreate.yaml](yaml/deployment-recreate.yaml).

## Imperative commands

```bash
# Create (fastest exam route)
kubectl create deployment web --image=nginx:1.27 --replicas=3 --port=80
kubectl create deployment web --image=nginx:1.27 -n team-a                  # into a namespace
kubectl create deployment multi --image=nginx:1.27 --image=redis:7.2        # 2 containers (named nginx, redis)
kubectl create deployment sleeper --image=busybox:1.36 -- sh -c 'while true; do date; sleep 5; done'

# Generate YAML, edit, apply (anything the flags can't set: probes, resources, strategy, labels, ...)
kubectl create deployment web --image=nginx:1.27 --replicas=3 --port=80 --dry-run=client -o yaml > web.yaml
vim web.yaml && kubectl apply -f web.yaml

# Scale
kubectl scale deployment web --replicas=5
kubectl scale deployment web --current-replicas=5 --replicas=2

# Modify the template (each starts a rollout)
kubectl set image deployment/web web=nginx:1.27-alpine                     # <container>=<image>
kubectl set env deployment/web LOG_LEVEL=debug
kubectl set resources deployment/web -c web --requests=cpu=100m,memory=64Mi --limits=memory=128Mi
kubectl set serviceaccount deployment/web app-sa

# Expose it
kubectl expose deployment web --port=80 --target-port=80 --name=web        # ClusterIP Service

# Inspect
kubectl get deploy web -o wide
kubectl get rs -l app=web                                                  # ReplicaSets of this app
kubectl get pods -l app=web --show-labels                                  # see pod-template-hash
kubectl describe deploy web                                                # conditions + events
kubectl get deploy web -o jsonpath='{.spec.template.spec.containers[*].image}{"\n"}'
kubectl get deploy web -o jsonpath='{.status.conditions[?(@.type=="Progressing")].reason}{"\n"}'
kubectl get deploy web -o jsonpath='{.metadata.annotations.deployment\.kubernetes\.io/revision}{"\n"}'
kubectl get rs -l app=web -o custom-columns='NAME:.metadata.name,REV:.metadata.annotations.deployment\.kubernetes\.io/revision,DESIRED:.spec.replicas,IMAGE:.spec.template.spec.containers[0].image'
kubectl explain deployment.spec.strategy.rollingUpdate                     # offline field docs
```

`kubectl create deployment` names the container after the image (`nginx:1.27` → container `nginx`). Check with `kubectl get deploy web -o jsonpath='{.spec.template.spec.containers[*].name}'` before running `kubectl set image`.

## Exam traps & tips

> **Exam tip:** Read the task's namespace first and put `-n <ns>` on every command (or switch the context namespace). A correct Deployment in the wrong namespace scores zero.

> **Exam tip:** `kubectl run` creates only Pods. For a Deployment use `kubectl create deployment`. The flags exist only for image, replicas, port and command; generate YAML for everything else.

> **Exam tip:** `kubectl set image deployment/web nginx=...` fails with `unable to find container named "nginx"` if the container is called `web`. Get the container name first.

> **Exam tip:** Selector ≠ template labels → `selector does not match template labels`. A selector change on an existing Deployment → `field is immutable`. Recreate it (`kubectl replace --force -f`).

> **Exam tip:** Scaling, changing the strategy, or annotating the Deployment does not create a revision. Don't expect `rollout history` to show them.

> **Exam tip:** A ConfigMap or Secret change does not restart Pods. If the task says "make the Pods pick up the new config", run `kubectl rollout restart deployment/<name>`.

> **Exam tip:** `READY 3/3` but `UP-TO-DATE 1` means the rollout is still running or stuck. Check `kubectl rollout status` and `kubectl get rs` before you call it done.

## Architect notes

- **Selectors are forever.** Design labels up front: stable selector labels (`app.kubernetes.io/name`, `app.kubernetes.io/instance`) plus free metadata labels (version, team). Helm and Kustomize follow this split.
- **Overlapping selectors** between controllers (two Deployments selecting `app=web`) make them fight over Pods. Every controller selector must include a distinguishing key.
- **Leave `replicas` out of the manifest when an HPA manages the Deployment.** Otherwise every `kubectl apply` or GitOps sync resets it.
- **`revisionHistoryLimit`**: each old ReplicaSet is an object in etcd. 3–5 is plenty for most apps. Never 0 if you want `rollout undo`.
- **Readiness probes and `minReadySeconds` are what make "Available" mean something.** Without them a Pod is Available as soon as its process starts. See [../03-Application-Observability-and-Maintenance/README.md](../03-Application-Observability-and-Maintenance/README.md).
- **Watch `observedGeneration`**: in automation, wait for `status.observedGeneration == metadata.generation` before trusting the other status fields. `kubectl rollout status` does this for you.
- **PodDisruptionBudgets** protect availability during node drains, not during rollouts. Rollout safety comes from `maxUnavailable`. You need both.
- **Pod template hygiene**: put a version label in the template for observability, but never in the selector.

## Docs to bookmark

- Deployments: https://kubernetes.io/docs/concepts/workloads/controllers/deployment/
- ReplicaSet: https://kubernetes.io/docs/concepts/workloads/controllers/replicaset/
- Deployment API reference: https://kubernetes.io/docs/reference/kubernetes-api/apps/deployment-v1/
- `kubectl create deployment`: https://kubernetes.io/docs/reference/kubectl/generated/kubectl_create/kubectl_create_deployment/
- `kubectl scale`: https://kubernetes.io/docs/reference/kubectl/generated/kubectl_scale/
- kubectl quick reference: https://kubernetes.io/docs/reference/kubectl/quick-reference/
- Labels and selectors: https://kubernetes.io/docs/concepts/overview/working-with-objects/labels/

## Quick self-check

1. You change `spec.replicas` from 3 to 6 and then `spec.minReadySeconds` from 0 to 10. How many new revisions appear in `rollout history`?
2. What is the name format of a Deployment's ReplicaSets and Pods, and where does the middle part come from?
3. A Deployment shows `Progressing=False` with reason `ProgressDeadlineExceeded`. What does Kubernetes do about it?
4. You must change a Deployment's selector from `app=web` to `app=shop`. What is the fastest correct approach?
5. Which condition and reason do you see when Pod creation is blocked by a ResourceQuota?
6. A ConfigMap used via `envFrom` was updated. Why do the Pods still show the old value, and how do you fix it?

<details><summary>Answers</summary>

1. Zero. Neither field is in `spec.template`.
2. ReplicaSet `<deployment>-<pod-template-hash>`, Pod `<deployment>-<pod-template-hash>-<random>`. The hash is computed from the Pod template and added as the `pod-template-hash` label.
3. Nothing automatic. It only reports the condition, and `kubectl rollout status` exits non-zero. You must fix the cause or `kubectl rollout undo`.
4. Edit the YAML (selector and template labels) and run `kubectl replace --force -f deploy.yaml`, or delete and recreate. The selector is immutable.
5. `ReplicaFailure=True`, reason `FailedCreate`, with an "exceeded quota" message. The Deployment usually also shows `Available=False` or a stuck rollout.
6. Env vars are read only at container start, and a ConfigMap change does not alter the Pod template. Run `kubectl rollout restart deployment/<name>`.

</details>
