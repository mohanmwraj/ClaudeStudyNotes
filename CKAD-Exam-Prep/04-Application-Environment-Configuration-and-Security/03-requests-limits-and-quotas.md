# Requests, Limits and Quotas

**Competencies:** *Understand requests, limits, quotas* · *Define resource requirements* (both listed in the current v1.37 CKAD curriculum)

**Why it matters / what the exam expects:** add requests/limits to Pods and Deployments (often "fit into the namespace quota"), create ResourceQuotas and LimitRanges, explain why a Pod is Pending, rejected or OOMKilled, and identify QoS classes.

---

## Core concepts

### Requests vs limits

| | **Request** | **Limit** |
|---|---|---|
| Used by | The **scheduler**: a node fits only if `allocatable - sum(requests of its Pods) >= request` | The **kubelet / container runtime** (cgroups) at run time |
| CPU | Guaranteed share of CPU time when the node is busy | Hard cap - the container is **throttled**, never killed, for CPU |
| Memory | Scheduling and eviction ranking | Hard cap - exceeding it gets the container **OOMKilled** (exit code 137) |
| If omitted | Defaults to the limit if a limit is set; otherwise a LimitRange default or nothing | LimitRange default, else unbounded (up to node capacity) |

- A container may use more than its request (if the node has spare capacity) but never more than its limit.
- Memory above the request is what makes a Pod an eviction candidate when the node runs short of memory.
- `kubectl describe node <n>` -> **Allocated resources** shows the sum of requests/limits on that node; Pods that fit nowhere stay `Pending` with `0/3 nodes are available: 3 Insufficient cpu`.

### Units

| Resource | Notation | Meaning |
|---|---|---|
| CPU | `1`, `0.5` = `500m`, `100m` | Cores (vCPU); `m` = millicores; smallest unit `1m` |
| Memory | `128Mi`, `1Gi`, `512Ki` | Binary units (powers of 2): 1Mi = 1,048,576 bytes |
| Memory | `128M`, `1G` | Decimal units (powers of 10): 1M = 1,000,000 bytes |
| Memory | `128m` | **0.128 bytes** - a classic typo; never use lowercase `m` for memory |
| Ephemeral storage | `ephemeral-storage: 1Gi` | Writable layer, logs, emptyDir (non-memory) |

### Effective Pod request/limit (init containers, sidecars, overhead)

```text
effective init request  = max( request of each init container )            (sidecars started before it are added)
effective Pod request   = Pod overhead + max( sum of app + sidecar containers, effective init request )
```

Example: an init container requests `cpu: 500m`, two app containers request `200m` each -> the Pod is scheduled with `max(500m, 400m) = 500m`. Quotas and LimitRange Pod limits are applied to these effective values. Native sidecars (`initContainers` with `restartPolicy: Always`) count with the app containers because they keep running.

### QoS classes

| QoS class | Rule (cpu and memory only) | Eviction under node memory pressure |
|---|---|---|
| **Guaranteed** | **Every** container (including init) has cpu **and** memory requests **==** limits (setting only limits also works: requests default to limits) | Last |
| **Burstable** | Not Guaranteed, and at least one container has a cpu or memory request or limit | Middle - Pods using more than their requests go first |
| **BestEffort** | No container has any cpu or memory request or limit | First |

The kubelet ranks eviction candidates by (1) usage above requests, (2) Pod priority, (3) how far usage exceeds requests - which in practice gives BestEffort, then Burstable over requests, then the rest. The QoS class is fixed at creation and shown in `.status.qosClass`.

```bash
kubectl get pod web -o jsonpath='{.status.qosClass}{"\n"}'
kubectl get pods -o custom-columns=NAME:.metadata.name,QOS:.status.qosClass
```

Reference Pods: [yaml/pod-qos-guaranteed.yaml](yaml/pod-qos-guaranteed.yaml), [yaml/pod-qos-burstable.yaml](yaml/pod-qos-burstable.yaml), [yaml/pod-qos-besteffort.yaml](yaml/pod-qos-besteffort.yaml).

### What happens when a container exceeds...

| Situation | Symptom | Where to look |
|---|---|---|
| Memory limit | Container killed and restarted: `OOMKilled`, exit code 137, possibly `CrashLoopBackOff` | `kubectl describe pod` -> Last State: Terminated, Reason: OOMKilled |
| CPU limit | Slow responses, no restart (CFS throttling) | `kubectl top pod` near the limit; throttling metrics |
| Node memory pressure | Pod `Evicted` (Failed phase), rescheduled by its controller | `kubectl get events`, `kubectl describe pod` (Reason: Evicted) |
| Ephemeral-storage limit | Pod evicted | Pod events |
| Request larger than any node | `Pending`, `Insufficient cpu/memory` | `kubectl describe pod` Events |

```bash
kubectl get pod web -o jsonpath='{.status.containerStatuses[0].lastState.terminated.reason}{"\n"}'   # OOMKilled
```

---

## Key fields / syntax

### Container resources

```yaml
spec:
  containers:
  - name: app
    image: nginx:1.27
    resources:
      requests:
        cpu: 250m
        memory: 128Mi
      limits:
        cpu: 500m
        memory: 256Mi
```

### LimitRange (per-namespace defaults and bounds)

Full file: [yaml/limitrange.yaml](yaml/limitrange.yaml). There is **no** `kubectl create limitrange` - copy YAML from the docs.

```yaml
apiVersion: v1
kind: LimitRange
metadata:
  name: dev-limits
  namespace: dev
spec:
  limits:
  - type: Container
    default:              # default LIMITS
      cpu: 500m
      memory: 256Mi
    defaultRequest:       # default REQUESTS
      cpu: 250m
      memory: 128Mi
    min:
      cpu: 50m
      memory: 32Mi
    max:
      cpu: "1"
      memory: 1Gi
    maxLimitRequestRatio:
      cpu: "4"
```

| `type` | Fields allowed | Applies to |
|---|---|---|
| `Container` | `default`, `defaultRequest`, `min`, `max`, `maxLimitRequestRatio` | Each container (and init container) |
| `Pod` | `min`, `max`, `maxLimitRequestRatio` (no defaults) | Sum over the Pod's containers |
| `PersistentVolumeClaim` | `min`, `max` (storage) | PVC `resources.requests.storage` |

Rules (enforced by the **LimitRanger** admission plugin when a Pod is **created**; existing Pods are never changed):

| Container specifies | Result |
|---|---|
| Nothing | Gets `defaultRequest` and `default` |
| Only a request | Limit = `default`; if the request is greater than that default limit the Pod is **rejected** ("must be less than or equal to cpu limit") |
| Only a limit | Request = the limit (API defaulting happens before admission) - **not** `defaultRequest` |
| Values outside `min`/`max` or above `maxLimitRequestRatio` | **Rejected**, e.g. `maximum cpu usage per Container is 1, but limit is 2` |

LimitRange defaulting quirks: if `default` is omitted but `max` is set, the default limit becomes `max`; if `defaultRequest` is omitted it becomes `default`. Keep **one** LimitRange per namespace - with several, which default applies is not deterministic.

### ResourceQuota (per-namespace totals)

Files: [yaml/resourcequota-compute.yaml](yaml/resourcequota-compute.yaml), [yaml/resourcequota-object-count.yaml](yaml/resourcequota-object-count.yaml).

```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: compute-quota
  namespace: dev
spec:
  hard:
    requests.cpu: "2"
    requests.memory: 2Gi
    limits.cpu: "4"
    limits.memory: 4Gi
    pods: "10"
```

| Category | Keys in `spec.hard` |
|---|---|
| Compute | `requests.cpu` (= `cpu`), `requests.memory` (= `memory`), `limits.cpu`, `limits.memory`, `requests.ephemeral-storage`, `limits.ephemeral-storage`, `requests.<extended>` (e.g. `requests.nvidia.com/gpu`) |
| Storage | `requests.storage`, `persistentvolumeclaims`, `<storageclass>.storageclass.storage.k8s.io/requests.storage`, `<storageclass>.storageclass.storage.k8s.io/persistentvolumeclaims` |
| Object counts (specialized names) | `pods` (non-terminal), `services`, `services.loadbalancers`, `services.nodeports`, `configmaps`, `secrets`, `persistentvolumeclaims`, `replicationcontrollers`, `resourcequotas` |
| Object counts (generic) | `count/<resource>.<group>`, e.g. `count/deployments.apps`, `count/jobs.batch`, `count/cronjobs.batch`, `count/crontabs.stable.example.com`; core group: `count/pods`, `count/secrets` |

| Scope (`spec.scopes` / `scopeSelector`) | Matches Pods that ... |
|---|---|
| `BestEffort` | have BestEffort QoS (tracks only `pods`) |
| `NotBestEffort` | are Burstable or Guaranteed |
| `Terminating` / `NotTerminating` | have / do not have `activeDeadlineSeconds` |
| `PriorityClass` (via `scopeSelector`) | use the listed `priorityClassName` values |
| `CrossNamespacePodAffinity` | use cross-namespace (anti-)affinity terms |

**The key rule:** once a quota limits `requests.cpu`, `limits.memory`, etc., **every new Pod** in that namespace must declare those values (directly or via LimitRange defaults); otherwise it is rejected with `must specify ...`. LimitRanger (mutating) runs before ResourceQuota (validating), so LimitRange defaults count toward the quota. Quotas never evict or change running Pods; lowering a quota below current usage only blocks new objects.

How quota failures surface:

```text
# Direct Pod creation fails immediately:
Error from server (Forbidden): pods "web" is forbidden: exceeded quota: compute-quota, requested: requests.cpu=500m, used: requests.cpu=1800m, limited: requests.cpu=2
Error from server (Forbidden): pods "web" is forbidden: failed quota: compute-quota: must specify limits.cpu for: web; limits.memory for: web; ...
# (exact wording differs slightly between versions - the key phrases are "exceeded quota" and "must specify")

# For a Deployment, `kubectl create`/`apply` SUCCEEDS; the ReplicaSet cannot create Pods:
kubectl get deploy web          ->  READY 1/3
kubectl describe rs -l app=web  ->  Warning  FailedCreate  ... Error creating: pods "web-7d9c-xyz" is forbidden: exceeded quota: ...
kubectl get deploy web -o jsonpath='{.status.conditions[?(@.type=="ReplicaFailure")].message}'
```

### In-place Pod resize

Change CPU/memory of a **running** Pod without recreating it. Beta (on by default) in v1.33-v1.34, **stable since v1.35** - so available on v1.37 exam clusters; `kubectl` v1.32+ is needed for `--subresource resize`. Check the docs for your cluster version.

```yaml
spec:
  containers:
  - name: app
    image: nginx:1.27
    resizePolicy:                  # per resource; default NotRequired
    - resourceName: cpu
      restartPolicy: NotRequired   # apply without restarting the container
    - resourceName: memory
      restartPolicy: RestartContainer
    resources:
      requests:
        cpu: 500m
        memory: 128Mi
      limits:
        cpu: 500m
        memory: 128Mi
```

```bash
kubectl patch pod web --subresource resize --patch \
  '{"spec":{"containers":[{"name":"app","resources":{"requests":{"cpu":"800m"},"limits":{"cpu":"800m"}}}]}}'
kubectl get pod web -o jsonpath='{.status.containerStatuses[0].resources}{"\n"}'   # actual applied values
kubectl get pod web -o jsonpath='{.status.conditions[?(@.type=="PodResizePending")]}{"\n"}'  # Infeasible/Deferred
```

Limits: only cpu and memory; the QoS class cannot change (Guaranteed must stay requests == limits); requests/limits cannot be removed; non-sidecar init containers and ephemeral containers cannot be resized; not on Windows. For Deployments, editing `spec.template` still triggers a normal rolling update.

Pod-level resources (`spec.resources` on the Pod, shared by its containers) are beta and on by default since v1.34 - awareness only.

---

## Imperative commands

```bash
# Generate a Pod / Deployment with resources (kubectl run has no --requests/--limits flags any more)
kubectl run web --image=nginx:1.27 --dry-run=client -o yaml \
  | kubectl set resources --local -f - --requests=cpu=100m,memory=64Mi --limits=cpu=200m,memory=128Mi -o yaml > pod.yaml
kubectl create deployment web --image=nginx:1.27 --replicas=3 --dry-run=client -o yaml > deploy.yaml
kubectl set resources --local -f deploy.yaml --requests=cpu=100m,memory=128Mi --limits=cpu=250m,memory=256Mi -o yaml > deploy-res.yaml

# Change resources of an existing Deployment (triggers a rollout)
kubectl set resources deploy/web --requests=cpu=100m,memory=128Mi --limits=cpu=250m,memory=256Mi
kubectl set resources deploy/web -c=nginx --limits=memory=512Mi        # one container only

# Quotas
kubectl create quota compute-quota -n dev --hard=requests.cpu=2,requests.memory=2Gi,limits.cpu=4,limits.memory=4Gi,pods=10
kubectl create quota object-counts -n dev --hard=configmaps=10,secrets=10,services=5,count/deployments.apps=5
kubectl create quota best-effort -n dev --hard=pods=3 --scopes=BestEffort
kubectl create quota q -n dev --hard=cpu=1,memory=1Gi --dry-run=client -o yaml > quota.yaml
kubectl get resourcequota -n dev                         # short name: quota
kubectl describe quota -n dev                            # Used vs Hard for every key
kubectl get quota compute-quota -n dev -o jsonpath='{.status.used}{"\n"}'

# LimitRanges (YAML only)
kubectl apply -f limitrange.yaml
kubectl get limitrange -n dev                            # short name: limits
kubectl describe limitrange dev-limits -n dev            # Type / Resource / Min / Max / Default Request / Default Limit

# Inspect usage and placement
kubectl top pod -n dev --containers                      # needs metrics-server
kubectl top node
kubectl describe node <node> | grep -A8 'Allocated resources'
kubectl get pod web -o jsonpath='{.spec.containers[*].resources}{"\n"}'
kubectl get pods -A -o custom-columns=NS:.metadata.namespace,NAME:.metadata.name,QOS:.status.qosClass
```

---

## Exam traps & tips

> **Exam tip:** "Create a Pod in namespace X" fails with `must specify limits.cpu ...`? The namespace has a ResourceQuota. Run `kubectl describe quota -n X` first, then give **every container** requests and limits for each quota-controlled resource and keep the totals under `Hard - Used`.

> **Exam tip:** memory is `Mi`/`Gi`. `memory: 128m` is accepted by the API server (at most with a warning) but means 0.128 bytes, so the container cannot run properly.

> **Exam tip:** a Deployment that shows fewer ready replicas than desired, with no Pods failing, is often a quota problem - `kubectl describe rs` shows `exceeded quota`.

> **Exam tip:** `kubectl set resources` on a Deployment creates a new ReplicaSet (rollout). On a running bare Pod, resources are immutable except through the `resize` subresource; otherwise recreate the Pod (`kubectl replace --force -f pod.yaml`).

> **Exam tip:** quote CPU integers in YAML quotas and limits (`"2"`); unquoted works too, but quoting avoids surprises with values like `0.5` vs `500m`.

- LimitRange and ResourceQuota changes affect only **new** Pods. To apply new defaults, restart the workload (`kubectl rollout restart deploy/<name>`).
- `pods` in a quota counts non-terminal Pods; completed Job Pods do not count.
- Requests > node allocatable -> Pending forever, even if the namespace quota allows it.
- An init container with a large request raises the whole Pod's effective request.
- Guaranteed QoS needs **every** container (including sidecars and init containers) to have equal cpu and memory requests and limits.

---

## Architect notes (sizing guidance)

- **Requests are your capacity plan.** Set them from observed usage (around P50-P90 from metrics or a VPA recommendation). Inflated requests waste nodes; deflated ones cause noisy neighbours and evictions.
- **Memory: limit equal (or close) to request.** Memory is incompressible; overcommitting it trades efficiency for OOM kills. Make runtimes container-aware (`-XX:MaxRAMPercentage` for the JVM, `GOMEMLIMIT` for Go, `--max-old-space-size` for Node.js).
- **CPU limits are a trade-off.** CFS throttling hurts tail latency; many platforms set CPU requests on everything but omit CPU limits for latency-sensitive services, while enforcing them in multi-tenant namespaces. Guaranteed QoS plus the static CPU manager gives exclusive cores where it matters.
- **HPA scales on utilization of requests** - without CPU requests there is no CPU-based autoscaling, and wrong requests mean wrong scaling.
- **Per-team namespaces get both:** a ResourceQuota (compute, storage, object counts, `services.loadbalancers: "0"` unless approved) and a LimitRange with sane defaults so developers are not blocked by "must specify" errors.
- **Object-count quotas protect the control plane** (etcd size, watch load): cap Secrets, ConfigMaps, Jobs and CRs per namespace in shared clusters.
- Reserve capacity for critical workloads with **PriorityClasses** plus quota `scopeSelector`, and keep them Guaranteed.
- Set `ephemeral-storage` requests/limits and `emptyDir.sizeLimit` - a full node disk evicts everything on it.
- Re-size continuously: VPA (recommendation mode), cost tooling, and in-place resize (stable since v1.35) to adjust vertically without restarts.
- Remember node allocatable: system and kube reservations mean Pods never get a node's full capacity.

---

## Docs to bookmark

- https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/
- https://kubernetes.io/docs/concepts/workloads/pods/pod-qos/
- https://kubernetes.io/docs/concepts/policy/limit-range/
- https://kubernetes.io/docs/concepts/policy/resource-quotas/
- https://kubernetes.io/docs/tasks/administer-cluster/manage-resources/memory-default-namespace/
- https://kubernetes.io/docs/tasks/administer-cluster/manage-resources/quota-memory-cpu-namespace/
- https://kubernetes.io/docs/tasks/configure-pod-container/assign-memory-resource/
- https://kubernetes.io/docs/tasks/configure-pod-container/assign-cpu-resource/
- https://kubernetes.io/docs/tasks/configure-pod-container/resize-container-resources/
- https://kubernetes.io/docs/concepts/scheduling-eviction/node-pressure-eviction/

---

## Quick self-check

1. A container has `limits: {cpu: 500m, memory: 256Mi}` and no requests. What are its requests, and what QoS class does a single-container Pod get?
2. Namespace `dev` has a quota on `requests.cpu` and a LimitRange with `defaultRequest.cpu: 250m`. A Pod without resources is created. Is it admitted?
3. What happens when a container exceeds its CPU limit? Its memory limit?
4. A Deployment's Pods stay at 2 of 5 and no Pod shows an error. Where do you look?
5. Which LimitRange `type` can set default requests?
6. Why can a Pod with an init container requesting 2 CPUs stay Pending on 1-CPU nodes even though its app container requests 100m?

<details><summary>Answers</summary>

1. Requests default to the limits (500m / 256Mi), so the Pod is **Guaranteed**.
2. Yes - LimitRanger fills in the request (and the default limit) before ResourceQuota checks it, and the defaults count against the quota.
3. CPU: throttled, keeps running. Memory: OOMKilled (exit code 137) and restarted according to the restart policy.
4. `kubectl describe rs -l <selector>` (FailedCreate events such as `exceeded quota`) and `kubectl describe quota`.
5. Only `type: Container` (`default` and `defaultRequest`).
6. The effective Pod request is `max(init request, sum of app requests)` = 2 CPUs; no node can satisfy it.

</details>
