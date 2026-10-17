# Persistent Volumes, Claims and StorageClasses

**Why it matters:** the persistent half of *"Utilize persistent and ephemeral volumes"*. Classic tasks: create a PV and a PVC that bind, and mount it in a Pod; create a StorageClass with given properties, possibly as the default; find out why a PVC is `Pending`; prove data survives pod deletion. There is no `kubectl create pv/pvc`: you write YAML (copy the skeleton from the docs) and you must know the binding rules exactly.

---

## Core concepts

### The three objects

| Object | Scope | Created by | Purpose |
|---|---|---|---|
| **PersistentVolume (PV)** | **cluster** (no namespace) | an admin (static) or a provisioner (dynamic) | a piece of real storage plus its capacity, access modes, class and reclaim policy |
| **PersistentVolumeClaim (PVC)** | **namespace** | the developer | a request for storage; bound **1:1** to a PV |
| **StorageClass (SC)** | **cluster** | an admin | provisioning profile: provisioner, parameters, reclaimPolicy, volumeBindingMode, allowVolumeExpansion |

The chain is: Pod `volumes[].persistentVolumeClaim.claimName` (same namespace) → PVC → PV → disk, NFS export or cloud volume.

### Lifecycle

1. **Provisioning.** *Static*: an admin creates PVs up front. *Dynamic*: a PVC names a StorageClass (or gets the default one) and its provisioner creates a PV named `pvc-<uid>`.
2. **Binding.** A control loop matches each PVC to a suitable PV and binds them one-to-one (`PV.spec.claimRef` ↔ `PVC.spec.volumeName`). The binding is exclusive.
3. **Using.** Pods mount the PVC. *Storage object in use protection*: a PVC used by a pod (or a bound PV) is not removed on delete. It stays `Terminating` (finalizers `kubernetes.io/pvc-protection` / `kubernetes.io/pv-protection`) until it is no longer in use.
4. **Reclaiming.** When the PVC is deleted, the PV's `persistentVolumeReclaimPolicy` decides what happens.

### Access modes

| Mode | Short | Meaning | Notes |
|---|---|---|---|
| `ReadWriteOnce` | RWO | read-write by a single **node** | several pods **on the same node** can still use it |
| `ReadOnlyMany` | ROX | read-only by many nodes | |
| `ReadWriteMany` | RWX | read-write by many nodes | needs shared storage (NFS, CephFS, cloud file services) |
| `ReadWriteOncePod` | RWOP | read-write by a single **pod** | CSI volumes only; GA v1.29 |

- A volume is mounted with **one** mode at a time, even if it supports several.
- Access modes are used for **matching and attach constraints**. They do not enforce write protection once mounted (use `readOnly` for that).

### Reclaim policies

| Policy | When the PVC is deleted | Default for |
|---|---|---|
| `Retain` | PV goes to `Released` and the data is kept. It is **not** reused automatically: an admin cleans up and then deletes or recreates the PV, or removes `spec.claimRef` to make it `Available` again | manually created PVs |
| `Delete` | the PV **and** the backing storage asset are deleted | dynamically provisioned PVs (inherited from the StorageClass, whose default is `Delete`) |
| `Recycle` | **deprecated**: basic scrub (`rm -rf /vol/*`), then Available. nfs/hostPath only | n/a |

PV phases: `Available` → `Bound` → `Released` (claim deleted) or `Failed` (automatic reclamation failed). PVC phases: `Pending`, `Bound`, `Lost`.

### Binding rules (PVC ↔ PV)

| Criterion | Rule |
|---|---|
| `storageClassName` | must be **equal**. PVC `""` means **no class**: it binds only to PVs without a class and **disables dynamic provisioning**. PVC **omitted** means the default StorageClass is filled in at creation (if one exists; if a default appears later, it is assigned retroactively, GA v1.28). A PV without `storageClassName` has no class |
| `accessModes` | the PV must offer **every** mode the PVC requests |
| capacity | PV `capacity.storage` ≥ PVC `resources.requests.storage`. The smallest suitable PV is chosen, and you get the **whole** PV (500Mi request + 1Gi PV gives 1Gi) |
| `volumeMode` | `Filesystem` (default) and `Block` must match |
| `selector` | the PV's labels must match the PVC's `matchLabels`/`matchExpressions` (ANDed). A PVC with a selector is never dynamically provisioned |
| `volumeName` (PVC) / `claimRef` (PV) | pre-binding to one specific PV or PVC. It skips some matching criteria (e.g. node affinity). If that PV is bound elsewhere, the PVC stays Pending |
| node affinity (`local` PVs) | evaluated during scheduling (use `WaitForFirstConsumer`) |

### StorageClass fields

| Field | Default | Meaning |
|---|---|---|
| `provisioner` | required | volume plugin or CSI driver (`rancher.io/local-path` in kind, `k8s.io/minikube-hostpath` in minikube, `ebs.csi.aws.com`, ..., `kubernetes.io/no-provisioner` = static only) |
| `parameters` | none | provisioner-specific (type, iops, fsType, ...) |
| `reclaimPolicy` | `Delete` | copied to every PV the class provisions (`Delete` or `Retain`) |
| `volumeBindingMode` | `Immediate` | `WaitForFirstConsumer` delays binding and provisioning until a pod that uses the PVC is scheduled (topology-aware; required for `local` PVs) |
| `allowVolumeExpansion` | false | lets PVCs of this class grow (never shrink) |
| `mountOptions` | none | e.g. `["discard"]`; not validated; a bad option makes the mount fail |
| `allowedTopologies` | none | restrict provisioning to zones or nodes |
| annotation `storageclass.kubernetes.io/is-default-class: "true"` | none | default class for PVCs that omit `storageClassName`. If several are marked, the newest wins. Keep exactly one |

`provisioner`, `parameters`, `reclaimPolicy` and `volumeBindingMode` are **immutable**: delete and recreate the class (existing PVs are not affected). Annotations and `allowVolumeExpansion` can be changed.

### `volumeBindingMode` in practice

| Mode | PVC right after creation | Risk / benefit |
|---|---|---|
| `Immediate` | `Bound` within seconds (provisioned or matched) | the volume may land in a zone or node where the pod cannot run |
| `WaitForFirstConsumer` | **`Pending`**, event *"waiting for first consumer to be created before binding"*. **This is normal** | provisioned where the pod is scheduled |

### Expanding a PVC

1. The StorageClass must have `allowVolumeExpansion: true`, and the driver must support expansion.
2. Increase `spec.resources.requests.storage` on the **PVC** (not the PV). Shrinking is rejected.
3. Watch `kubectl get pvc` / `describe` (conditions such as `FileSystemResizePending`). Most CSI drivers expand online; some need a pod restart.

### PVC `Pending` troubleshooting

| Symptom (`kubectl describe pvc`) | Cause | Fix |
|---|---|---|
| `waiting for first consumer to be created before binding` | WaitForFirstConsumer class, no pod yet | create the pod: **not an error** |
| `no persistent volumes available for this claim and no storage class is set` | `storageClassName: ""` or no default class, and no matching PV | create a matching PV, or set or omit the class to use dynamic provisioning |
| `storageclass.storage.k8s.io "<name>" not found` | typo or missing class | fix `storageClassName` (PVC spec is immutable, so delete and recreate the PVC) |
| `waiting for a volume to be created ... by external provisioner "<x>"` for a long time | provisioner or CSI driver not running or failing | check the provisioner pods and their logs |
| PV `Available` but PVC stays Pending | mismatch in class, accessModes, capacity (PV too small), volumeMode or selector labels | compare `kubectl get pv,pvc -o yaml` field by field |
| PV `Released`, new PVC Pending | Retain policy; old `claimRef` still set | clean the data, then `kubectl patch pv <pv> -p '{"spec":{"claimRef":null}}'` |
| Pod Pending: `pod has unbound immediate PersistentVolumeClaims` | PVC not bound | fix the PVC first |
| Pod ContainerCreating: `Multi-Attach error` / `FailedAttachVolume` | RWO volume still attached to another node | wait or remove the old pod; use RWX if several nodes need it |
| PVC stuck `Terminating` | `pvc-protection`: a pod still uses it | delete the pod (or its controller) |

### Verify that data persists

```bash
kubectl exec pvc-pod -- sh -c 'echo "persist-test $(date)" > /data/test.txt'   # 1. write
kubectl delete pod pvc-pod                                                       # 2. delete the pod
kubectl apply -f pvc-pod.yaml                                                    # 3. recreate (same claimName)
kubectl exec pvc-pod -- cat /data/test.txt                                       # 4. data is still there
```

For a StatefulSet: write into `web-0`, `kubectl delete pod web-0`, wait for the new `web-0`, read again. It re-binds the same PVC `<claim>-web-0` ([05](05-daemonsets-and-statefulsets.md)).

### `local` PersistentVolume (node-local disk, with node affinity)

```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: local-pv-1
spec:
  capacity:
    storage: 10Gi
  accessModes: ["ReadWriteOnce"]
  persistentVolumeReclaimPolicy: Retain
  storageClassName: local-storage        # a no-provisioner class with WaitForFirstConsumer
  local:
    path: /mnt/disks/ssd1                # must exist on the node
  nodeAffinity:                          # required for local PVs
    required:
      nodeSelectorTerms:
      - matchExpressions:
        - key: kubernetes.io/hostname
          operator: In
          values: ["<node-name>"]
```

---

## Key fields / syntax

| File | Shows |
|---|---|
| [yaml/pv-pvc-pod-static.yaml](yaml/pv-pvc-pod-static.yaml) | hostPath PV + PVC (class `manual`, selector) + Pod |
| [yaml/storageclass.yaml](yaml/storageclass.yaml) | SC with Retain / WaitForFirstConsumer / allowVolumeExpansion; no-provisioner class |
| [yaml/pvc-dynamic.yaml](yaml/pvc-dynamic.yaml) | PVC using the default class + Pod |
| [yaml/statefulset-with-headless-svc.yaml](yaml/statefulset-with-headless-svc.yaml) | volumeClaimTemplates (one PVC per pod) |
| [yaml/generic-ephemeral-volume.yaml](yaml/generic-ephemeral-volume.yaml) | pod-lifetime PVC (for contrast) |

PV, PVC and Pod (static):

```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: pv-data
spec:
  storageClassName: manual
  capacity:
    storage: 1Gi
  accessModes:
  - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  hostPath:
    path: /mnt/data
    type: DirectoryOrCreate
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: pvc-data
  namespace: storage
spec:
  storageClassName: manual
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 500Mi
---
apiVersion: v1
kind: Pod
metadata:
  name: pvc-pod
  namespace: storage
spec:
  containers:
  - name: app
    image: busybox:1.36
    command: ["sh", "-c", "sleep 3600"]
    volumeMounts:
    - name: data
      mountPath: /data
  volumes:
  - name: data
    persistentVolumeClaim:
      claimName: pvc-data
```

StorageClass:

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: fast
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: rancher.io/local-path
reclaimPolicy: Retain
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
```

---

## Imperative commands

```bash
# Inspect
kubectl get pv                                            # CAPACITY ACCESS MODES RECLAIM POLICY STATUS CLAIM STORAGECLASS
kubectl get pvc -A                                        # STATUS VOLUME CAPACITY ACCESS MODES STORAGECLASS
kubectl get sc                                            # default class shows "(default)"
kubectl describe pvc pvc-data                             # Events explain Pending
kubectl get pv pv-data -o jsonpath='{.status.phase} {.spec.claimRef.namespace}/{.spec.claimRef.name}{"\n"}'
kubectl get pvc pvc-data -o jsonpath='{.status.phase} {.spec.volumeName} {.status.capacity.storage}{"\n"}'
kubectl get pv -o custom-columns=NAME:.metadata.name,CLASS:.spec.storageClassName,STATUS:.status.phase,CLAIM:.spec.claimRef.name
kubectl explain pv.spec --recursive | less                # field names (hostPath, local, nfs, csi, nodeAffinity...)
kubectl api-resources | grep -E 'persistentvolume|storageclass'   # pv/pvc/sc short names and scope

# Default StorageClass
kubectl patch storageclass standard -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}'
kubectl patch storageclass fast -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'

# Change reclaim policy of an existing PV
kubectl patch pv pv-data -p '{"spec":{"persistentVolumeReclaimPolicy":"Retain"}}'

# Expand a PVC (class must allow it)
kubectl patch pvc pvc-data -p '{"spec":{"resources":{"requests":{"storage":"2Gi"}}}}'

# Make a Released (Retain) PV Available again - after cleaning the data
kubectl patch pv pv-data -p '{"spec":{"claimRef":null}}'

# Which pod uses a PVC?
kubectl get pods -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.spec.volumes[*].persistentVolumeClaim.claimName}{"\n"}{end}'

# Delete
kubectl delete pvc pvc-data                               # Terminating until no pod uses it
kubectl delete pv pv-data
```

---

## Exam traps & tips

> **Exam tip:** **`storageClassName: ""` is not "use the default".** Empty string means "no class" (static binding only, no dynamic provisioning). Omitting the field means "use the default class". This is a frequently reported exam mistake.

> **Exam tip:** PVs and StorageClasses are cluster-scoped (no `namespace:`). PVCs are namespaced and must be in the **same namespace as the pod**. Put `namespace:` on the PVC (or use `-n`).

> **Exam tip:** A PVC `Pending` with *"waiting for first consumer"* is **correct** for `WaitForFirstConsumer` classes. Create the pod, then check again. Do not "fix" it.

> **Exam tip:** PVC specs are immutable apart from growing `resources.requests.storage` (and a few fields like `volumeAttributesClassName`). To change class, access mode or size downwards: delete and recreate the PVC (and the pod using it).

> **Exam tip:** The docs page "Configure a Pod to Use a PersistentVolume for Storage" has a ready PV/PVC/Pod trio (`storageClassName: manual`, hostPath). Copy it and adapt names, sizes and paths.

- The PV must offer **all** requested access modes. RWO PV + RWX PVC never binds.
- A bigger PV binds to a smaller request (you get the whole PV); a smaller PV never binds.
- `Released` PVs never rebind by themselves (Retain). Remove `claimRef` only if the task allows reusing the data.
- With `Delete` reclaim (the dynamic default), deleting the PVC **destroys the data**.
- hostPath PVs in multi-node clusters: the pod may run on a node where the directory is empty. Use node affinity, or a single-node lab.
- Two classes marked default → the newest is used, which is confusing. Un-default the old one when making a new default.
- `kubectl get pv` CLAIM shows `namespace/pvc-name`: a quick way to prove a binding.

---

## Architect notes

- **Dynamic provisioning through CSI** is the norm. Static PVs are for special cases (pre-existing NFS exports, local disks, imported volumes).
- **Use `WaitForFirstConsumer`** for zonal block storage so volumes follow pod placement. Combine it with topology spread so stateful replicas land in different zones.
- **Pick the reclaim policy per data class:** `Retain` (or snapshots and backups) for anything you cannot recreate; `Delete` for caches and CI. Changing a PV to `Retain` before risky operations is cheap insurance.
- **Access modes drive architecture.** RWX shared filesystems are convenient but often slower and harder to make consistent. Prefer RWO or RWOP per replica (StatefulSet) plus app-level replication, or object storage.
- **Capacity governance:** ResourceQuota on `requests.storage` and `persistentvolumeclaims` (also per class: `<class>.storageclass.storage.k8s.io/requests.storage`), and LimitRange min/max for PVC sizes.
- **Day-2 operations:** enable `allowVolumeExpansion` from the start, monitor PVC usage (`kubelet_volume_stats_*`), and use VolumeSnapshots (snapshot CRDs + CSI) for backups and clones. VolumeAttributesClass (GA v1.34) lets you change IOPS or throughput tiers without migrating.
- **Data gravity:** a pod bound to a zonal RWO volume cannot move zones. Plan DR with backups, replication or regional storage, not with "the scheduler will move it".

---

## Docs to bookmark

- Persistent Volumes (binding, access modes, reclaim, expansion): <https://kubernetes.io/docs/concepts/storage/persistent-volumes/>
- Storage Classes: <https://kubernetes.io/docs/concepts/storage/storage-classes/>
- Dynamic provisioning: <https://kubernetes.io/docs/concepts/storage/dynamic-provisioning/>
- Configure a Pod to use a PersistentVolume (copy-paste PV/PVC/Pod): <https://kubernetes.io/docs/tutorials/configuration/configure-persistent-volume-storage/>
- Change the default StorageClass: <https://kubernetes.io/docs/tasks/administer-cluster/change-default-storage-class/>
- Volume snapshots: <https://kubernetes.io/docs/concepts/storage/volume-snapshots/>
- API reference, PV / PVC / StorageClass: <https://kubernetes.io/docs/reference/kubernetes-api/core/persistent-volume-v1/>, <https://kubernetes.io/docs/reference/kubernetes-api/core/persistent-volume-claim-v1/>, <https://kubernetes.io/docs/reference/kubernetes-api/storage/storage-class-v1/>

---

## Quick self-check

1. PVC A has `storageClassName: ""`; PVC B has no `storageClassName`; the cluster has a default class. What does each bind to?
2. A PV offers RWO and 1Gi with class `manual`. Which of these PVCs bind: (a) RWO 2Gi manual, (b) RWX 500Mi manual, (c) RWO 500Mi manual, (d) RWO 500Mi with class omitted?
3. A dynamically provisioned PVC is deleted. What happens to the data, and how could you have prevented it?
4. Your PVC is `Pending` with "waiting for first consumer to be created before binding". What do you do?
5. How do you make a `Released` PV with `Retain` bindable again?
6. How do you switch the default StorageClass from `standard` to `fast`?

<details><summary>Answers</summary>

1. A binds only to a PV **without** a class (static, no provisioning). B gets the default class written into it, so it is dynamically provisioned (or binds to a PV of that class).
2. Only (c). (a) is too big; (b) asks for RWX, which the PV lacks; (d) gets the default class, which is not `manual`.
3. The StorageClass reclaim policy defaults to `Delete`, so the PV and the backing volume are deleted. Prevent it with `reclaimPolicy: Retain` on the class, or patch the PV's `persistentVolumeReclaimPolicy` to `Retain` before deleting (and keep backups or snapshots).
4. Nothing is wrong: create (or wait for) the pod that uses the PVC. Binding and provisioning happen when that pod is scheduled.
5. Clean up the data as required, then remove the old claim reference: `kubectl patch pv <pv> -p '{"spec":{"claimRef":null}}'`. The PV becomes `Available`. Alternatively delete it and recreate it with the same spec.
6. Annotate `standard` with `storageclass.kubernetes.io/is-default-class: "false"` and `fast` with `"true"` (two `kubectl patch sc` commands), then verify that `kubectl get sc` shows `(default)` only on `fast`.

</details>
