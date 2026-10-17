# Ephemeral Volumes (and Volume Basics)

**Why it matters:** *"Utilize persistent and ephemeral volumes"* is an official competency, and a shared `emptyDir` underpins nearly every multi-container task. Expect to declare volumes and mounts from memory: `emptyDir` (including `medium: Memory` and `sizeLimit`), `hostPath` with the right `type`, `subPath`, `readOnly`, and to recognise configMap, secret, downwardAPI, projected and generic ephemeral volumes.

---

## Core concepts

### Volumes vs volumeMounts

- `spec.volumes[]` (pod level) **defines** a volume and its source. `spec.containers[].volumeMounts[]` (container level) **mounts** it. They are joined by **name**.
- One volume can be mounted by several containers at different paths, and several times in one container (with `subPath`).
- Mounting at a path **hides** whatever the image had there. Mounting an emptyDir at `/usr/share/nginx/html` hides nginx's `index.html` and you get 403.

### Volume types at a glance

| Type | Lives as long as | Typical use | More |
|---|---|---|---|
| `emptyDir` | the pod (survives container restarts) | scratch space, sharing files between containers, caches | below |
| `emptyDir` + `medium: Memory` | the pod (RAM, tmpfs) | very fast scratch | below |
| `configMap` | the pod (content tracks the ConfigMap) | config files | [chapter 04](../04-Application-Environment-Configuration-and-Security/README.md) |
| `secret` | the pod (tmpfs) | credentials as files | chapter 04 |
| `downwardAPI` | the pod | pod metadata and resources as files | below + chapter 04 |
| `projected` | the pod | configMap + secret + downwardAPI + serviceAccountToken in one directory | below |
| `ephemeral` (generic ephemeral volume) | the pod (its PVC is deleted with the pod) | provisioned scratch with StorageClass features | below |
| `csi` (CSI ephemeral volume) | the pod | driver-specific inline volumes (e.g. a secrets-store driver) | below |
| `image` (image volume) | the pod, read-only | mount an OCI image or artifact as data | below (check feature state) |
| `hostPath` | the **node** (outlives the pod) | node agents, labs | below |
| `persistentVolumeClaim` | independent of any pod | durable data | [08-persistent-volumes.md](08-persistent-volumes.md) |

### emptyDir

- Created **empty** when the pod is assigned to a node. Every container of the pod can read and write it. It survives **container** crashes and restarts, and is **deleted when the pod leaves the node** (pod deleted, evicted, node lost).
- `medium: ""` (default): backed by the node's disk (kubelet directory). `medium: Memory`: **tmpfs** in RAM.
- `sizeLimit`:
  - disk-backed: the kubelet **evicts** the pod when usage exceeds the limit. The space comes from node ephemeral storage, so it can run out earlier if the node is full.
  - memory-backed: the tmpfs is sized from it (without a limit it is sized to the node's allocatable memory). Every byte written **counts against the writing container's memory limit**, so exceeding it means an OOMKill.
- Disk-backed emptyDir usage also counts toward the container's `ephemeral-storage` requests and limits (chapter 04).
- v1.37 adds an **alpha** `emptyDir.mode` field (permission bits, off by default). Ignore it for the exam.

### hostPath

Mounts a file or directory **from the node**. The data stays on that node, so a rescheduled pod on another node sees different data.

| `type` | Before mounting, the kubelet... |
|---|---|
| `""` (default) | does no checks (backwards compatible) |
| `DirectoryOrCreate` | creates an empty directory (mode 0755, kubelet ownership) if nothing exists |
| `Directory` | requires an existing directory |
| `FileOrCreate` | creates an empty file (0644) if nothing exists. It does **not** create missing parent directories |
| `File` | requires an existing file |
| `Socket` | requires an existing UNIX socket |
| `CharDevice` | requires an existing character device (Linux) |
| `BlockDevice` | requires an existing block device (Linux) |

Security caveats:

- Host access can expose kubelet credentials, the **container runtime socket** (full node takeover) and system files. A read-write mount lets the pod tamper with the host.
- Pod Security Standards **baseline** and **restricted** forbid hostPath, so such pods are rejected in namespaces that enforce them.
- hostPath usage is **not** counted as ephemeral storage, so you have to watch disk usage yourself.
- For node-local persistent data use a **`local` PersistentVolume** (with node affinity) instead ([08](08-persistent-volumes.md)).

### configMap, secret, downwardAPI and projected (overview)

| Volume | Files | Updates | Notes |
|---|---|---|---|
| `configMap` | one file per key (or pick with `items: [{key, path}]`) | auto-updated after a short delay, **except `subPath` mounts** | always read-only; `defaultMode`; `optional: true` |
| `secret` | one file per key, on **tmpfs** | same | `defaultMode` (e.g. `0400`); never written to node disk |
| `downwardAPI` | `fieldRef` (`metadata.name`, `namespace`, `uid`, `labels`, `annotations`) and `resourceFieldRef` (`limits.cpu`, `requests.memory`, ... with `divisor`) | labels and annotations update | env-var form also has `spec.nodeName`, `status.podIP`, ... |
| `projected` | several sources merged into **one** directory: `configMap`, `secret`, `downwardAPI`, `serviceAccountToken` (`audience`, `expirationSeconds` ≥ 600, `path`) | as above | the default ServiceAccount token mount is itself a projected volume |

Full ConfigMap, Secret and ServiceAccount coverage: [../04-Application-Environment-Configuration-and-Security/README.md](../04-Application-Environment-Configuration-and-Security/README.md). Example: [yaml/projected-volume.yaml](yaml/projected-volume.yaml).

### Generic ephemeral volumes (GA v1.23)

- `volumes[].ephemeral.volumeClaimTemplate` holds a normal PVC spec **inline in the pod**. The control plane creates a PVC named **`<pod-name>-<volume-name>`**, owned by the pod, and **deletes it with the pod**.
- You get real provisioned storage (size, StorageClass, snapshots, cloning, resizing and capacity tracking, if the driver supports them) with pod lifetime. It works with `WaitForFirstConsumer` classes.
- Normal PVC quotas still apply. Anyone who can create pods can indirectly create PVCs this way.

### CSI ephemeral volumes (brief)

`volumes[].csi: {driver: ..., volumeAttributes: {...}}`: an inline volume provided by a CSI driver that supports the ephemeral mode (for example a secrets-store driver). Node-local and pod-lifetime. It is not counted toward pod storage limits.

### Image volumes (nice to know: check the feature state)

```yaml
volumes:
- name: model
  image:
    reference: quay.io/crio/artifact:v2   # any OCI image/artifact
    pullPolicy: IfNotPresent              # Always | Never | IfNotPresent (defaults like imagePullPolicy)
```

- Mounts the image content **read-only** into the pod (data, models, static assets shipped as OCI artifacts).
- Feature history (`ImageVolume` gate): alpha v1.31; beta but **off by default** v1.33–v1.34; on by default v1.35; **stable v1.36**. The v1.37 exam cluster's API therefore accepts it, but the node's container runtime must also support image volumes. `subPath`/`subPathExpr` are supported from v1.33.
- Low exam priority: recognise the syntax, and use it only if a task asks for it.

### `volumeMounts` options

| Field | Meaning |
|---|---|
| `name` | must equal a `spec.volumes[].name` (otherwise the API rejects the pod) |
| `mountPath` | absolute path in the container; created if missing; **hides** existing content |
| `subPath` | mount only this file or sub-directory of the volume, e.g. one ConfigMap key as one file. **No live updates** for configMap/secret/downwardAPI |
| `subPathExpr` | like `subPath` but expands `$(VAR)` from the container env (e.g. `$(POD_NAME)`); mutually exclusive with `subPath` |
| `readOnly` | this container cannot write through this mount. Not recursive: read-write submounts below it stay writable unless `recursiveReadOnly` is set |
| `recursiveReadOnly` | `Disabled` (default) \| `IfPossible` \| `Enabled`: make submounts read-only too (GA v1.33; needs `readOnly: true`) |
| `mountPropagation` | `None` (default) \| `HostToContainer` \| `Bidirectional` (privileged containers only) |

---

## Key fields / syntax

| File | Shows |
|---|---|
| [yaml/emptydir.yaml](yaml/emptydir.yaml) | two containers sharing a disk-backed emptyDir with `sizeLimit` |
| [yaml/emptydir-memory.yaml](yaml/emptydir-memory.yaml) | `medium: Memory` + `sizeLimit` + memory limits |
| [yaml/hostpath.yaml](yaml/hostpath.yaml) | `DirectoryOrCreate`, `FileOrCreate`, `File` types |
| [yaml/pod-subpath.yaml](yaml/pod-subpath.yaml) | `subPath` (one ConfigMap key as a file) and `subPathExpr` |
| [yaml/projected-volume.yaml](yaml/projected-volume.yaml) | projected configMap + secret + downwardAPI + serviceAccountToken |
| [yaml/generic-ephemeral-volume.yaml](yaml/generic-ephemeral-volume.yaml) | generic ephemeral volume |

Shared emptyDir (the most-typed volume in the exam):

```yaml
spec:
  containers:
  - name: writer
    image: busybox:1.36
    command: ["sh", "-c", "while true; do date >> /data/out.log; sleep 5; done"]
    volumeMounts:
    - name: shared
      mountPath: /data
  - name: reader
    image: busybox:1.36
    command: ["sh", "-c", "tail -F /input/out.log"]
    volumeMounts:
    - name: shared
      mountPath: /input
      readOnly: true
  volumes:
  - name: shared
    emptyDir: {}
```

Memory-backed with a cap:

```yaml
volumes:
- name: cache
  emptyDir:
    medium: Memory
    sizeLimit: 64Mi
```

hostPath:

```yaml
volumes:
- name: node-logs
  hostPath:
    path: /var/log
    type: Directory
```

Generic ephemeral volume:

```yaml
volumes:
- name: scratch
  ephemeral:
    volumeClaimTemplate:
      spec:
        accessModes: ["ReadWriteOnce"]
        resources:
          requests:
            storage: 1Gi
```

---

## Imperative commands

There is no `kubectl` flag for volumes. Generate the pod, then add `volumes` and `volumeMounts` in vi.

```bash
kubectl run app --image=busybox:1.36 --dry-run=client -o yaml --command -- sh -c 'sleep 3600' > pod.yaml
kubectl explain pod.spec.volumes.emptyDir                  # medium, sizeLimit
kubectl explain pod.spec.volumes.hostPath                  # path, type
kubectl explain pod.spec.volumes.ephemeral.volumeClaimTemplate.spec
kubectl explain pod.spec.containers.volumeMounts           # subPath, subPathExpr, readOnly, ...

# Verify
kubectl exec app -c writer -- ls -la /data                 # files the other container wrote
kubectl exec app -- df -h /cache                           # "tmpfs" for medium: Memory
kubectl exec app -- sh -c 'mount | grep -E "/data|/cache"' # mount type and ro/rw flags
kubectl get pod app -o jsonpath='{.spec.volumes}{"\n"}'    # what is declared
kubectl describe pod app | grep -A12 -i "^Volumes:"        # volumes as the API sees them
kubectl get pvc                                            # generic ephemeral PVCs: <pod>-<volume>
kubectl get pod app -o jsonpath='{.spec.nodeName}{"\n"}'   # which node holds the hostPath data
```

---

## Exam traps & tips

> **Exam tip:** Volume **name** in `volumeMounts` must match `volumes`. The **paths** are per container and may differ. Check the task for the exact `mountPath` in **each** container.

> **Exam tip:** "Shared between the containers of the pod" or "temporary" means `emptyDir`. "In memory" or "RAM-backed" means `medium: Memory`. "Stored on the node at /x" means `hostPath`. "Must survive pod deletion" means a PVC.

> **Exam tip:** `FileOrCreate` will not create parent directories. If `/data/app/log.txt` must be created and `/data/app` does not exist, the pod fails to start. Mount the directory with `DirectoryOrCreate` instead, or pick an existing parent.

> **Exam tip:** Mounting a single ConfigMap key over an existing directory hides everything else in it. Use `subPath` with a file `mountPath` to drop in just one file (and accept that it will not auto-update).

- A memory-backed emptyDir without memory limits can consume node memory up to its size. Always set `sizeLimit` and a container memory limit.
- `readOnly: true` on the mount, not on the volume (`emptyDir` has no readOnly field). For a PVC there is also `persistentVolumeClaim.readOnly`.
- Data in an emptyDir is lost when the pod is deleted, including by `kubectl replace --force` and by every Deployment rollout.
- hostPath in multi-node clusters: the pod may land elsewhere next time. Pin it with `nodeName`/`nodeSelector` if the task insists.
- A Pod Security baseline or restricted namespace rejects hostPath pods (`violates PodSecurity`). Read the error; do not fight it unless the task says so.

---

## Architect notes

- **emptyDir is not storage.** Use it for caches, scratch and hand-offs only. Anything that must survive a rollout belongs in a PVC or an external service.
- **Bound your ephemeral usage:** `sizeLimit` on emptyDirs and `ephemeral-storage` requests and limits per container protect nodes from disk-pressure evictions that hit neighbours.
- **Memory-backed volumes are memory.** Account for them in limits, and in VPA or HPA calculations.
- **hostPath is a privilege escalation vector.** Block it with Pod Security (baseline or above) everywhere except vetted system namespaces. Use `local` PVs, CSI drivers or DaemonSets with read-only, narrowly scoped mounts.
- **Generic ephemeral volumes** are the clean answer for large scratch data (build caches, ML shards) that should not sit on the node root disk. You get provisioned, quota-governed, auto-cleaned volumes.
- **Config via projected volumes** (with bound ServiceAccount tokens and custom audiences) is the modern pattern for workload identity and external API auth. Avoid long-lived token Secrets.
- **Image volumes** (stable in v1.36) decouple large read-only data (models, assets) from the app image. Version them in the registry, cache them on nodes, and keep app images small.

---

## Docs to bookmark

- Volumes (all types, subPath, hostPath types): <https://kubernetes.io/docs/concepts/storage/volumes/>
- Ephemeral volumes (generic + CSI): <https://kubernetes.io/docs/concepts/storage/ephemeral-volumes/>
- Projected volumes: <https://kubernetes.io/docs/concepts/storage/projected-volumes/>
- Configure a pod to use a volume (emptyDir walkthrough): <https://kubernetes.io/docs/tasks/configure-pod-container/configure-volume-storage/>
- Share data between containers via a volume: <https://kubernetes.io/docs/tasks/access-application-cluster/communicate-containers-same-pod-shared-volume/>
- Downward API volume: <https://kubernetes.io/docs/tasks/inject-data-application/downward-api-volume-expose-pod-information/>
- Image volumes: <https://kubernetes.io/docs/tasks/configure-pod-container/image-volumes/>
- Pod Security Standards (hostPath restrictions): <https://kubernetes.io/docs/concepts/security/pod-security-standards/>

---

## Quick self-check

1. Two containers must exchange files, and the data may disappear with the pod. Which volume? Where does the data physically live by default?
2. What changes with `medium: Memory`, and what is the risk without limits?
3. Which hostPath `type` creates a missing directory, and which fails if the file is missing?
4. You mount a ConfigMap key with `subPath`. The ConfigMap changes. Does the file in the container change?
5. What is the PVC name of generic ephemeral volume `scratch` in pod `etl-7`, and when is it deleted?
6. Why is hostPath rejected in some namespaces?

<details><summary>Answers</summary>

1. `emptyDir`. On the node's disk in the kubelet's pod directory (`/var/lib/kubelet/pods/<pod-uid>/volumes/kubernetes.io~empty-dir/<name>`).
2. It becomes a tmpfs in RAM: fast and never on disk, but written data counts toward the container's memory limit. Without `sizeLimit` and limits it can use memory up to node allocatable, putting the node and neighbours at risk (OOM, evictions).
3. `DirectoryOrCreate` creates it. `File` (and `Directory`, `Socket`, ...) fail if the object is missing.
4. No. `subPath` mounts do not receive ConfigMap or Secret updates. Restart the pod, or mount the whole volume as a directory.
5. `etl-7-scratch`. It is deleted (garbage-collected) when the pod is deleted, because the pod owns it.
6. Pod Security **baseline** and **restricted** forbid hostPath volumes, so namespaces labelled `pod-security.kubernetes.io/enforce: baseline|restricted` reject such pods.

</details>
