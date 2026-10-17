# DaemonSets and StatefulSets

**Why it matters:** both are part of "choose and use the right workload resource", and neither has a `kubectl create` generator. Under time pressure you must produce valid YAML from a generated Deployment, and know exactly which fields to change. DaemonSet tasks ("run on every node, including the control plane") come up more often than StatefulSet tasks. StatefulSets also test the headless Service and volumeClaimTemplates.

---

## Core concepts: DaemonSet

- Runs **one pod on every eligible node**. Nodes added later get a pod automatically; pods on removed nodes are garbage-collected.
- Typical uses: log shippers, node monitoring exporters, CNI and CSI node plugins, kube-proxy, security agents.
- **Scheduling:** the DaemonSet controller creates one pod per eligible node and gives it a node affinity (`matchFields metadata.name In [<node>]`). The **default scheduler** then binds it, so taints, resources and preemption apply.
- **Which nodes:** all of them by default. Restrict with `.spec.template.spec.nodeSelector` or `affinity`; extend to tainted nodes with **tolerations**.
- **No `replicas` field**, so `kubectl scale ds` does not work. The pod count equals the number of eligible nodes.
- `restartPolicy` must be `Always`. `.spec.selector` is immutable and must match the template labels.

### Tolerations added automatically to DaemonSet pods

| Toleration key | Effect | Why |
|---|---|---|
| `node.kubernetes.io/not-ready` | NoExecute | not evicted from not-ready nodes |
| `node.kubernetes.io/unreachable` | NoExecute | not evicted from unreachable nodes |
| `node.kubernetes.io/disk-pressure` | NoSchedule | scheduled despite disk pressure |
| `node.kubernetes.io/memory-pressure` | NoSchedule | scheduled despite memory pressure |
| `node.kubernetes.io/pid-pressure` | NoSchedule | scheduled despite PID pressure |
| `node.kubernetes.io/unschedulable` | NoSchedule | runs even on cordoned nodes |
| `node.kubernetes.io/network-unavailable` | NoSchedule | only for `hostNetwork: true` pods |

**Not** included: the control-plane taint. To also run on control-plane nodes, add:

```yaml
tolerations:
- key: node-role.kubernetes.io/control-plane
  operator: Exists
  effect: NoSchedule
```

(The old `node-role.kubernetes.io/master` taint is no longer applied by kubeadm. Check what your nodes really have with `kubectl describe node <cp> | grep -i taints`.)

### DaemonSet update strategies

| `updateStrategy.type` | Behaviour |
|---|---|
| `RollingUpdate` (default) | after a template change, old pods are replaced automatically, node by node. `rollingUpdate.maxUnavailable` (default **1**, number or %) and `rollingUpdate.maxSurge` (default **0**). With `maxSurge > 0` the new pod starts **before** the old one is removed on that node. The two cannot both be 0 |
| `OnDelete` | new pods are created only when **you delete** old ones (manual, node-by-node control) |

`minReadySeconds` (default 0) delays "available" during a rollout. `kubectl rollout status|history|undo|restart ds/<name>` all work.

---

## Core concepts: StatefulSet

| Guarantee | How |
|---|---|
| **Stable, ordinal names** | `<sts>-0`, `<sts>-1`, ... `<sts>-(N-1)` (start ordinal configurable with `spec.ordinals.start`, GA v1.31) |
| **Stable network identity** | hostname = pod name; DNS `<pod>.<serviceName>.<ns>.svc.cluster.local` through the **headless Service** named in `spec.serviceName` |
| **Stable storage** | `volumeClaimTemplates` give each pod its own PVC `<template>-<sts>-<ordinal>` (e.g. `www-web-0`), re-attached when the pod is recreated, even on another node |
| **Ordering** (default `OrderedReady`) | scale-up 0 → N-1, each pod Running **and Ready** before the next; scale-down N-1 → 0, each pod fully terminated first |
| **Pod labels** | `statefulset.kubernetes.io/pod-name=<pod>` (lets you target one pod with a Service) and `apps.kubernetes.io/pod-index=<ordinal>` (GA v1.32) |

### StatefulSet fields

| Field | Default | Notes |
|---|---|---|
| `serviceName` | none | name of the **headless** Service (`clusterIP: None`) that governs pod DNS. Create the Service yourself. Current API docs no longer mark it required, but without it there are no per-pod DNS names |
| `replicas` | 1 | |
| `selector`, `template` | required | `restartPolicy` must be `Always` |
| `volumeClaimTemplates[]` | none | each entry is a PVC template; its `metadata.name` must match a `volumeMounts[].name` |
| `podManagementPolicy` | `OrderedReady` | `Parallel` = create or delete all pods at once (scaling only; rolling updates stay one at a time unless `maxUnavailable` is used) |
| `updateStrategy.type` | `RollingUpdate` | reverse ordinal order, one pod at a time, each Ready before the next. `OnDelete` = manual. (v1.37 adds an **alpha** `Recreate` type, off by default: ignore it for the exam) |
| `updateStrategy.rollingUpdate.partition` | 0 | only pods with ordinal **≥ partition** get the new template (canary or staged rollout). If partition > replicas, nothing updates |
| `updateStrategy.rollingUpdate.maxUnavailable` | 1 | **beta**. On by default in v1.37, the exam version (the `MaxUnavailableStatefulSet` gate was switched off again in later v1.35 patch releases and in v1.36). Use it only when a task asks for faster StatefulSet rollouts |
| `persistentVolumeClaimRetentionPolicy.whenDeleted` / `whenScaled` | `Retain` / `Retain` | `Delete` removes the PVCs when the StatefulSet is deleted / when a scale-down removes the pod. GA v1.32 |
| `minReadySeconds` | 0 | GA v1.25 |
| `revisionHistoryLimit` | 10 | ControllerRevisions kept for rollback |

**Immutable after creation:** everything except `replicas`, `ordinals`, `template`, `updateStrategy`, `revisionHistoryLimit`, `persistentVolumeClaimRetentionPolicy` and `minReadySeconds`. So `serviceName`, `volumeClaimTemplates`, `podManagementPolicy` and `selector` cannot be changed. Delete with `--cascade=orphan` and recreate.

### Limitations to remember

- Deleting or scaling down a StatefulSet **does not delete its PVCs** (unless the retention policy says `Delete`). Delete them explicitly if asked.
- Deleting a StatefulSet gives **no ordering guarantee** for pod termination. Scale to 0 first if you need ordered shutdown.
- With `OrderedReady`, a bad template can **stall** the rollout. Reverting the template is not enough; you must also delete the pods that were created from the bad revision.
- Storage must come from a provisioner (StorageClass) or pre-created PVs. A `Pending` PVC blocks pod 0, and with OrderedReady also every later pod.

---

## Key fields / syntax

| File | Shows |
|---|---|
| [yaml/daemonset.yaml](yaml/daemonset.yaml) | control-plane toleration, updateStrategy RollingUpdate, downward API node name, read-only hostPath |
| [yaml/statefulset-with-headless-svc.yaml](yaml/statefulset-with-headless-svc.yaml) | headless Service, serviceName, OrderedReady, partition, retention policy, init container seeding a PVC, volumeClaimTemplates |

### Why there is no `kubectl create daemonset/statefulset`

kubectl only has generators for a few kinds. For these two you **generate a Deployment and convert it**:

```bash
kubectl create deployment node-agent --image=busybox:1.36 --dry-run=client -o yaml -- sleep 3600 > ds.yaml
```

```yaml
apiVersion: apps/v1
kind: Deployment          # (1) change to DaemonSet / StatefulSet
metadata:
  labels:
    app: node-agent
  name: node-agent
spec:
  replicas: 1             # (2) DaemonSet: DELETE   | StatefulSet: keep
  selector:
    matchLabels:
      app: node-agent
  strategy: {}            # (3) DELETE for both (DaemonSet/StatefulSet use updateStrategy)
  template:
    metadata:
      labels:
        app: node-agent
    spec:
      containers:
      - command:
        - sleep
        - "3600"
        image: busybox:1.36
        name: busybox
        resources: {}
status: {}
```

| Change | DaemonSet | StatefulSet |
|---|---|---|
| `kind` | `DaemonSet` | `StatefulSet` |
| `spec.replicas` | **delete** (unknown field) | keep |
| `spec.strategy: {}` | **delete** (unknown field); optionally add `updateStrategy` | **delete**; optionally add `updateStrategy` |
| `spec.serviceName` | not applicable | **add**, and create the headless Service |
| `spec.volumeClaimTemplates` | not applicable | add if per-pod storage is required |
| tolerations / nodeSelector | add if the task requires control-plane or a node subset | as needed |
| `status: {}`, `creationTimestamp: null`, `resources: {}` | harmless; delete for tidiness | harmless |

Forgetting (2) or (3) gives `strict decoding error: unknown field "spec.replicas"` / `unknown field "spec.strategy"`.

One-liner for the DaemonSet case (check the result with `cat ds.yaml` before applying):

```bash
kubectl create deployment node-agent --image=busybox:1.36 --dry-run=client -o yaml -- sleep 3600 \
  | sed -e 's/^kind: Deployment/kind: DaemonSet/' -e '/^  replicas:/d' -e '/^  strategy: {}/d' > ds.yaml
```

Headless Service for a StatefulSet (generated, then checked):

```bash
kubectl create service clusterip web --clusterip="None" --tcp=80:80 --dry-run=client -o yaml > svc.yaml
# selector becomes app=web, so the StatefulSet template labels must include app: web
```

### StatefulSet core (what the exam checks)

```yaml
apiVersion: v1
kind: Service
metadata:
  name: web
spec:
  clusterIP: None
  selector:
    app: web
  ports:
  - name: http
    port: 80
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: web
spec:
  serviceName: web
  replicas: 3
  selector:
    matchLabels:
      app: web
  template:
    metadata:
      labels:
        app: web
    spec:
      containers:
      - name: nginx
        image: nginx:1.27
        ports:
        - containerPort: 80
          name: http
        volumeMounts:
        - name: data
          mountPath: /usr/share/nginx/html
  volumeClaimTemplates:
  - metadata:
      name: data
    spec:
      accessModes: ["ReadWriteOnce"]
      resources:
        requests:
          storage: 100Mi
```

---

## Imperative commands

```bash
# DaemonSet
kubectl get ds -A                                          # DESIRED / CURRENT / READY / UP-TO-DATE / AVAILABLE / NODE SELECTOR
kubectl get pods -l app=node-agent -o wide                 # one per node? check the NODE column
kubectl describe node <control-plane> | grep -i taints     # what the toleration must match
kubectl set image ds/node-agent agent=busybox:1.37         # triggers a rolling update
kubectl rollout status ds/node-agent
kubectl rollout history ds/node-agent
kubectl rollout undo ds/node-agent
kubectl get ds node-agent -o jsonpath='{.status.desiredNumberScheduled} {.status.numberReady}{"\n"}'

# StatefulSet
kubectl get sts web ; kubectl get pods -l app=web -w       # watch ordered creation web-0, web-1, web-2
kubectl get pvc                                            # data-web-0, data-web-1, data-web-2
kubectl scale sts web --replicas=5                         # adds web-3, web-4 (in order)
kubectl scale sts web --replicas=2                         # removes web-4, web-3, web-2 (PVCs stay by default)
kubectl run dns --rm -i --image=busybox:1.36 --restart=Never -- nslookup web-0.web.default.svc.cluster.local
kubectl exec web-0 -- sh -c 'echo "$(hostname)" > /usr/share/nginx/html/index.html'   # write per-pod data
kubectl delete pod web-0 && kubectl get pod web-0 -w       # same name and same PVC come back
kubectl exec web-0 -- cat /usr/share/nginx/html/index.html # data persisted

# Staged / canary update with partition
kubectl patch sts web -p '{"spec":{"updateStrategy":{"type":"RollingUpdate","rollingUpdate":{"partition":2}}}}'
kubectl set image sts/web nginx=nginx:1.27-alpine          # only web-2 (ordinal >= 2) is updated
kubectl get pods -l app=web -o custom-columns=NAME:.metadata.name,IMAGE:.spec.containers[0].image
kubectl patch sts web -p '{"spec":{"updateStrategy":{"rollingUpdate":{"partition":0}}}}'   # finish the rollout
kubectl rollout status sts/web

# Changing an immutable field (e.g. volumeClaimTemplates, serviceName)
kubectl delete sts web --cascade=orphan                    # pods keep running
kubectl apply -f sts-new.yaml                              # new StatefulSet adopts the pods by label
kubectl delete pvc -l app=web                              # only if the task says the data may go
```

---

## Exam traps & tips

> **Exam tip:** DaemonSet YAML from a Deployment: remove `replicas` **and** `strategy`, otherwise the API rejects the manifest. Keep `selector.matchLabels` equal to the template labels.

> **Exam tip:** "Also on control-plane nodes" means a toleration for `node-role.kubernetes.io/control-plane:NoSchedule`. Verify with `kubectl get pods -o wide` that a pod runs on the control-plane node.

> **Exam tip:** StatefulSet pods only get DNS names if `serviceName` points to an existing **headless** Service whose selector matches the pods. `nslookup <pod>.<svc>` from a busybox pod proves it. Use the FQDN, because busybox `nslookup` can mishandle short names.

> **Exam tip:** A StatefulSet stuck at `web-0 Pending` almost always means an unbound PVC (no default StorageClass, wrong class name, no matching PV). Run `kubectl describe pvc data-web-0`.

- DaemonSet pods not on a node? Check that node's taints, `nodeSelector`/affinity, and its allocatable resources (the scheduler still has to place them).
- `kubectl scale ds` is invalid; the DaemonSet's pod count follows the nodes.
- PVCs survive `kubectl delete sts`. Re-creating the StatefulSet with the same names re-attaches the **old data**, which can be surprising in tests.
- The `volumeClaimTemplates` storage class or size cannot be changed in place. Expand the existing PVCs (if the class allows it), or orphan-delete and recreate.
- `podManagementPolicy: Parallel` speeds up scaling but gives up ordering. Choose it only when the app does not need ordered bootstrap.

---

## Architect notes

- **DaemonSets are cluster-wide taxes.** Each one costs requests × nodes. Keep them lean, set `priorityClassName` (e.g. `system-node-critical` for networking and storage agents), and use `maxSurge` (with `maxUnavailable: 0`) for agents whose absence breaks the node (CNI, CSI).
- **Target node pools explicitly** with nodeSelector or affinity (GPU exporters only on GPU nodes) and match the taints you use for dedicated pools.
- **StatefulSet is a building block, not a database platform.** Replication, failover, backup and version upgrades need application logic. Prefer a proven **Operator** (CloudNativePG, Strimzi, etc.) or a managed service.
- **Storage topology:** use `WaitForFirstConsumer` StorageClasses so a PV is created in the zone where the pod lands, and spread replicas across zones (topology spread constraints, pod anti-affinity) with a PDB (`maxUnavailable: 1`).
- **Decide the PVC lifecycle** deliberately: `persistentVolumeClaimRetentionPolicy` (`whenScaled: Delete` for caches, `Retain` for databases) plus a backup or snapshot strategy (VolumeSnapshots).
- **Rollouts of quorum systems:** use `partition` for staged upgrades and keep `OrderedReady` for systems that need sequential bootstrap. Remember the forced-rollback caveat (delete the broken pods after reverting the template).
- **Per-pod Services:** the `statefulset.kubernetes.io/pod-name` label lets you expose a single member (e.g. a primary) with its own Service.

---

## Docs to bookmark

- DaemonSet: <https://kubernetes.io/docs/concepts/workloads/controllers/daemonset/>
- Perform a rolling update on a DaemonSet: <https://kubernetes.io/docs/tasks/manage-daemon/update-daemon-set/>
- Rollback a DaemonSet: <https://kubernetes.io/docs/tasks/manage-daemon/rollback-daemon-set/>
- StatefulSets: <https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/>
- StatefulSet basics tutorial: <https://kubernetes.io/docs/tutorials/stateful-application/basic-stateful-set/>
- Scale / delete a StatefulSet: <https://kubernetes.io/docs/tasks/run-application/scale-stateful-set/>, <https://kubernetes.io/docs/tasks/run-application/delete-stateful-set/>
- Taints and tolerations: <https://kubernetes.io/docs/concepts/scheduling-eviction/taint-and-toleration/>
- StatefulSet API reference: <https://kubernetes.io/docs/reference/kubernetes-api/apps/stateful-set-v1/>

---

## Quick self-check

1. Which two fields must you delete when converting generated Deployment YAML into a DaemonSet?
2. A DaemonSet runs on the workers but not on the control-plane node. What do you add?
3. StatefulSet `db` with `serviceName: db-hl` in namespace `prod`: what is the DNS name of the second pod, and the PVC name for claim template `data`?
4. You set `partition: 2` on a 4-replica StatefulSet and change the image. Which pods update?
5. You delete a StatefulSet and create it again with the same name. What happens to the data?
6. Why can't you `kubectl scale` a DaemonSet, and how do you limit it to some nodes?

<details><summary>Answers</summary>

1. `spec.replicas` and `spec.strategy` (also change `kind`). Optionally add `spec.updateStrategy`.
2. A toleration `key: node-role.kubernetes.io/control-plane`, `operator: Exists`, `effect: NoSchedule` in the pod template.
3. `db-1.db-hl.prod.svc.cluster.local`; PVC `data-db-1`.
4. Ordinals ≥ 2, so `db-2` and `db-3` (updated in reverse order: 3, then 2). `db-0` and `db-1` keep the old template, even if they are deleted.
5. The PVCs were retained (default policy), so the new pods with the same ordinals re-bind to the same PVCs and the old data is back.
6. A DaemonSet has no `replicas`; it runs one pod per eligible node. Limit it with `nodeSelector`/node affinity in the pod template (and taints/tolerations).

</details>
