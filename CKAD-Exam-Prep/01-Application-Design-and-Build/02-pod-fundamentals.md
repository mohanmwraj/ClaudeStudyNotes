# Pod Fundamentals

**Why it matters:** every workload in this chapter is a Pod template wrapped in a controller. Most exam tasks start with `kubectl run ... --dry-run=client -o yaml`, followed by an edit of `command`/`args`, env, ports, labels, hooks or volumes. You also need to know what you **cannot** change on a running Pod and the fast way around it (`kubectl replace --force`).

What the exam expects:

- generate and edit Pod YAML quickly (`kubectl run` flags, `--command --` vs `--`);
- read Pod phases, container states and the `STATUS` column, and pick the next debugging command;
- configure `restartPolicy`, lifecycle hooks and `terminationGracePeriodSeconds`;
- use labels, annotations and namespaces correctly (deep dive: [../06-Cross-Cutting-Skills-and-Bonus-Topics/README.md](../06-Cross-Cutting-Skills-and-Bonus-Topics/README.md)).

---

## Core concepts

### A Pod in one paragraph

A Pod is the smallest deployable unit: one or more containers that are **scheduled together onto one node** and share a **network namespace** (one IP, a shared port space, and `localhost` between containers), IPC, and any **volumes** declared in the pod. With `shareProcessNamespace` they can also share the PID namespace. A pause (infra) container holds these namespaces. Pods are **disposable**: they are never moved or healed, they are replaced. That is why you almost always run them through a controller (see [03-workload-resources.md](03-workload-resources.md)).

### Pod spec anatomy

| Field | Purpose | Notes |
|---|---|---|
| `apiVersion: v1`, `kind: Pod` | type | |
| `metadata.name` / `namespace` | identity | name: DNS subdomain, unique per namespace |
| `metadata.labels` / `annotations` | selectable / non-selectable metadata | see [Labels & annotations](#labels-and-annotations-basics) |
| `spec.containers[]` | app containers (**required**, at least 1) | |
| `spec.initContainers[]` | setup containers and native sidecars | [06-multi-container-pods.md](06-multi-container-pods.md) |
| `spec.volumes[]` | pod-level volume definitions | [07](07-ephemeral-volumes.md), [08](08-persistent-volumes.md) |
| `spec.restartPolicy` | `Always` (default) \| `OnFailure` \| `Never` | applies to all containers of the pod |
| `spec.terminationGracePeriodSeconds` | shutdown budget (default **30**) | see the [graceful shutdown](#graceful-shutdown-sequence) section |
| `spec.activeDeadlineSeconds` | kill the pod after N seconds (phase Failed, reason DeadlineExceeded) | counts init containers too |
| `spec.nodeName`, `nodeSelector`, `affinity`, `tolerations` | placement | chapter 06 |
| `spec.serviceAccountName`, `automountServiceAccountToken`, `securityContext` | identity and security | chapter 04 |
| `spec.imagePullSecrets` | registry credentials | [01-container-images.md](01-container-images.md) |
| `spec.hostname`, `spec.subdomain` | pod DNS name under a headless Service | |
| `spec.dnsPolicy` | `ClusterFirst` (default) | |
| `spec.shareProcessNamespace` | shared PID namespace | [06-multi-container-pods.md](06-multi-container-pods.md) |
| `spec.hostNetwork`, `hostPID`, `hostIPC` | host namespaces | security risk; blocked by Pod Security baseline |
| `spec.os.name` | `linux` \| `windows` | |
| `status` | phase, conditions, containerStatuses, podIP, hostIP, qosClass | written by the system |

### Container fields

| Field | Purpose |
|---|---|
| `name`, `image`, `imagePullPolicy` | identity and image ([01](01-container-images.md)) |
| `command`, `args` | override ENTRYPOINT / CMD ([mapping table](01-container-images.md#entrypointcmd--pod-commandargs)) |
| `workingDir` | overrides the image WORKDIR |
| `ports[]` (`containerPort`, `name`, `protocol`, `hostPort`) | mostly informational; **named ports** can be used by Services and probes; `hostPort` binds on the node |
| `env[]` (`value`, `valueFrom.fieldRef / resourceFieldRef / configMapKeyRef / secretKeyRef`) | environment variables (all values are strings) |
| `envFrom[]` (`configMapRef`, `secretRef`, `prefix`) | import all keys ([chapter 04](../04-Application-Environment-Configuration-and-Security/README.md)) |
| `resources.requests / limits` | scheduling and enforcement (chapter 04) |
| `volumeMounts[]` | mount pod volumes ([07](07-ephemeral-volumes.md)) |
| `livenessProbe`, `readinessProbe`, `startupProbe` | health ([chapter 03](../03-Application-Observability-and-Maintenance/README.md)) |
| `lifecycle.postStart`, `lifecycle.preStop` | hooks (below) |
| `securityContext` | container-level security (chapter 04) |
| `stdin`, `tty` | keep stdin open / allocate a TTY (interactive containers) |
| `terminationMessagePolicy` | `File` (default) or `FallbackToLogsOnError` (last log lines become the termination message) |
| `restartPolicy` (container level) | `Always` on an **init container** = native sidecar. Per-container `restartPolicy`/`restartPolicyRules` for regular containers (`ContainerRestartRules`) are beta and on by default since v1.35, including on v1.37: nice to know |

### `restartPolicy`

| Value | Restarts the container when it... | Used by |
|---|---|---|
| `Always` (default) | exits for any reason, even exit code 0 | Deployment, ReplicaSet, StatefulSet, DaemonSet (the only allowed value there) |
| `OnFailure` | exits non-zero | Jobs, CronJobs |
| `Never` | never | Jobs, one-shot pods (`kubectl run --restart=Never`) |

- Restarts happen **in place** (same pod, same node) with exponential back-off of 10 s, 20 s, 40 s and so on, **capped at 5 min**. The timer resets after 10 min of healthy running. While waiting, STATUS shows `CrashLoopBackOff`.
- The `RESTARTS` column counts container restarts. `kubectl logs <pod> --previous` shows the crashed instance.

### Pod phases (`.status.phase`)

| Phase | Meaning |
|---|---|
| `Pending` | accepted, but not all containers are running yet: waiting for scheduling, image pulls, volumes, init containers |
| `Running` | bound to a node, all containers created, at least one running (or restarting) |
| `Succeeded` | all containers exited 0 and will not restart |
| `Failed` | all containers terminated, at least one failed |
| `Unknown` | state cannot be obtained (usually node communication lost) |

**Container states** (`.status.containerStatuses[*].state`): `waiting` (with `reason`), `running` (`startedAt`), `terminated` (`exitCode`, `reason`, `finishedAt`). The previous run is in `lastState`.

**Pod conditions:** `PodScheduled` → `PodReadyToStartContainers` → `Initialized` (init containers done) → `ContainersReady` → `Ready` (receives Service traffic).

### The `STATUS` column, and what to run next

| STATUS | Meaning | Next command |
|---|---|---|
| `Pending` | not scheduled (resources, nodeSelector/taints, unbound PVC) or waiting | `kubectl describe pod` → Events |
| `ContainerCreating` | scheduled; sandbox, volumes or image pull in progress | `describe` (FailedMount, image pulling) |
| `Init:0/2`, `Init:1/2` | init containers running | `kubectl logs <pod> -c <init>` |
| `Init:Error`, `Init:CrashLoopBackOff` | an init container failed | `kubectl logs <pod> -c <init> --previous` |
| `PodInitializing` | init done, app containers starting | wait |
| `Running` | at least one container running; check READY x/y | `kubectl get pod -o wide` |
| `Completed` | all containers exited 0 (phase Succeeded) | `kubectl logs` |
| `Error` | a container exited non-zero | `kubectl logs --previous` |
| `CrashLoopBackOff` | crashing repeatedly; kubelet backing off | `kubectl logs --previous`, `describe` (exit code) |
| `ErrImagePull`, `ImagePullBackOff` | image name/tag wrong, private registry, no network | `describe` → Events |
| `ErrImageNeverPull` | `imagePullPolicy: Never` and the image is absent | fix policy or load the image |
| `CreateContainerConfigError` | missing ConfigMap/Secret (key), or non-numeric `USER` with `runAsNonRoot` | `describe` |
| `RunContainerError` / `StartError` | runtime could not start the process (e.g. executable not found) | `describe` → Last State message |
| `OOMKilled` (in Last State) | memory limit exceeded (exit 137) | raise the limit / fix the leak |
| `Terminating` | deletion in progress (preStop, grace period, finalizers) | wait, or force delete if allowed |
| `Evicted` | node pressure / ephemeral-storage limit | `describe` |

Exit codes: `0` ok · `1` app error · `126` not executable · `127` command not found (shell) · `128` StartError (runtime could not exec) · `137` SIGKILL (OOM, or grace period expired) · `139` segfault · `143` SIGTERM.

### Lifecycle hooks

| Hook | Runs | Handlers | If it fails |
|---|---|---|---|
| `postStart` | right after the container is created, **concurrently** with the ENTRYPOINT (no ordering guarantee). The container is not `Running` until the hook finishes | `exec`, `httpGet`, `sleep` | container is killed and restarted per `restartPolicy` (event `FailedPostStartHook`) |
| `preStop` | before the stop signal, when the pod is deleted or the container is stopped (liveness failure, preemption, ...) | `exec`, `httpGet`, `sleep` | event `FailedPreStopHook`; termination continues |

- **`sleep` action:** `preStop: {sleep: {seconds: 5}}`. Beta and on by default v1.30–v1.33, **GA v1.34**. It needs no `sleep` binary in the image (it works on distroless). A zero-second sleep is allowed since v1.34.
- `exec` runs inside the container; `httpGet`, `sleep` and the deprecated `tcpSocket` run from the kubelet.
- Each hook takes **one** handler. Hooks are delivered at least once, so make them idempotent.
- Container `lifecycle.stopSignal` (overrides the image STOPSIGNAL; requires `spec.os.name`) is **alpha** since v1.33 and still alpha in v1.37. Not for the exam.

### Graceful shutdown sequence

```text
kubectl delete pod web                         (default grace = terminationGracePeriodSeconds = 30 s)
 t=0   API marks the pod Terminating (deletionTimestamp + grace period); the countdown starts NOW
       in parallel: EndpointSlices mark the endpoint ready=false / terminating -> Services stop
       sending NEW traffic (eventually consistent: proxies/ingress take a moment)
 t=0   kubelet runs preStop hooks (they consume the grace period)
 t=p   preStop finished -> runtime sends the stop signal (SIGTERM, or the image STOPSIGNAL) to PID 1
       of each container; the app should drain and exit
 t=30  anything still running gets SIGKILL (exit 137); if preStop is still running at expiry the
       kubelet grants a one-time 2 s extension
       native sidecars are stopped after the app containers, in reverse declaration order
 end   pod object removed from the API
```

- `kubectl delete pod web --grace-period=5` uses a custom budget. `--grace-period=0 --force` removes the API object **immediately**, but the containers may keep running on the node for a while. Only do it when asked, or for throwaway pods.
- A shell-form ENTRYPOINT (`sh -c app`) usually does not forward SIGTERM, so the app always dies by SIGKILL after the full grace period. Use exec form.

### Labels and annotations basics

| | Labels | Annotations |
|---|---|---|
| Purpose | identify and **select** (Services, controllers, `-l`) | attach non-identifying metadata (tools, change-cause, descriptions) |
| Key format | optional `prefix/` (DNS subdomain ≤253) + name ≤63 chars `[a-z0-9A-Z-_.]`, starting and ending alphanumeric | same key rules |
| Value | ≤63 chars, same character set, may be empty | any string (total size of all annotations ≤256 KiB) |
| Selectable | yes: equality `=`, `==`, `!=`; set-based `in`, `notin`, `key`, `!key` | no |

Recommended labels: `app.kubernetes.io/name`, `app.kubernetes.io/instance`, `app.kubernetes.io/version`, `app.kubernetes.io/component`, `app.kubernetes.io/part-of`, `app.kubernetes.io/managed-by`. Prefixes `kubernetes.io/` and `k8s.io/` are reserved.

### Namespaces basics

- They are virtual clusters for **names, RBAC, quotas, limits and NetworkPolicies**. Initial namespaces: `default`, `kube-system`, `kube-public`, `kube-node-lease`.
- **Namespaced** objects (Pod, Deployment, Service, PVC, ConfigMap, Secret, ...) vs **cluster-scoped** objects (Node, Namespace, PersistentVolume, StorageClass, ClusterRole, ...): `kubectl api-resources --namespaced=false`.
- Every namespace carries the label `kubernetes.io/metadata.name=<name>`. Service DNS is `<svc>.<ns>.svc.cluster.local`.
- Deleting a namespace deletes everything in it.

### Static Pods (brief)

- The kubelet runs manifests from its `staticPodPath` directory (kubeadm: `/etc/kubernetes/manifests`) **without the API server** deciding anything. This is how kubeadm runs the control plane.
- The API shows a read-only **mirror Pod** named `<pod>-<node-name>`. Deleting it does not stop the static pod; **remove or move the file** instead. Editing the file makes the kubelet recreate the pod.
- Static pods cannot reference ServiceAccounts, ConfigMaps or Secrets, and are not managed by controllers. Example: [yaml/static-pod.yaml](yaml/static-pod.yaml).

### What can you change on a running Pod?

| Field | Mutable in place? |
|---|---|
| `metadata.labels`, `metadata.annotations` | yes (`kubectl label`, `kubectl annotate`) |
| `spec.containers[*].image`, `spec.initContainers[*].image` | yes: the container restarts with the new image (`kubectl set image pod/x c=img`) |
| `spec.activeDeadlineSeconds` | set if unset, or **decrease** only |
| `spec.tolerations` | **add** entries only |
| `spec.schedulingGates` | **remove** entries only |
| `spec.terminationGracePeriodSeconds` | only from a negative value to 1 (treat it as immutable) |
| `resources` | only through the `resize` subresource (in-place resize: beta and on by default v1.33, GA v1.35) |
| ephemeral containers | added through the `ephemeralcontainers` subresource (`kubectl debug`) |
| **everything else**: command, args, env, ports, volumes, volumeMounts, probes, securityContext, serviceAccountName, nodeSelector, adding/removing containers, ... | **no**: delete and recreate (`kubectl replace --force -f`) |

---

## Key fields / syntax

| File | Shows |
|---|---|
| [yaml/pod-basic.yaml](yaml/pod-basic.yaml) | labels, annotations, named port, env + downward API, resources, restartPolicy, grace period |
| [yaml/pod-command-args.yaml](yaml/pod-command-args.yaml) | args-only, command-only, command+args, `$(VAR)` expansion, nginx args |
| [yaml/pod-lifecycle-hooks.yaml](yaml/pod-lifecycle-hooks.yaml) | postStart exec, preStop sleep action, grace period |
| [yaml/static-pod.yaml](yaml/static-pod.yaml) | static pod manifest |

Minimal pod you should be able to type blind:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: web
  labels:
    app: web
spec:
  containers:
  - name: web
    image: nginx:1.27
    ports:
    - containerPort: 80
```

Hooks and the shutdown budget:

```yaml
spec:
  terminationGracePeriodSeconds: 45
  containers:
  - name: app
    image: nginx:1.27
    lifecycle:
      postStart:
        exec:
          command: ["sh", "-c", "echo started > /usr/share/nginx/html/started.txt"]
      preStop:
        sleep:
          seconds: 10
```

Env from the downward API (pod metadata as env vars):

```yaml
env:
- name: POD_NAME
  valueFrom:
    fieldRef:
      fieldPath: metadata.name          # also: metadata.namespace, metadata.uid, spec.nodeName,
- name: POD_IP                          #       spec.serviceAccountName, status.podIP, status.hostIP
  valueFrom:
    fieldRef:
      fieldPath: status.podIP
```

---

## Imperative commands

### `kubectl run` patterns (creates **only** Pods)

| Goal | Command |
|---|---|
| Basic pod (adds label `run=<name>`) | `kubectl run web --image=nginx:1.27` |
| Port, labels, env (repeat `--env`) | `kubectl run web --image=nginx:1.27 --port=80 --labels=app=web,tier=fe --env=MODE=prod --env=DEBUG=false` |
| Pod **plus** a ClusterIP Service with the same name (selector = pod labels) | `kubectl run web --image=nginx:1.27 --port=80 --expose` |
| Replace CMD (**args**) | `kubectl run bb --image=busybox:1.36 -- sleep 3600` |
| Replace ENTRYPOINT (**command**) | `kubectl run bb --image=busybox:1.36 --command -- sh -c 'echo hi; sleep 3600'` |
| One-shot pod (ends `Completed`) | `kubectl run once --image=busybox:1.36 --restart=Never -- date` |
| Interactive throwaway shell, deleted on exit | `kubectl run tmp --rm -it --image=busybox:1.36 --restart=Never -- sh` |
| Single test command, output only | `kubectl run tmp --rm -i --image=curlimages/curl:8.10.1 --restart=Never -- curl -s -m 5 http://web` |
| Restart only on failure (still a Pod, not a Job) | `kubectl run retry --image=busybox:1.36 --restart=OnFailure -- sh -c 'exit 1'` |
| Pull policy / annotations / namespace | `--image-pull-policy=IfNotPresent --annotations=owner=team-a -n dev` |
| Field without a flag (e.g. ServiceAccount) | `--overrides='{"apiVersion":"v1","spec":{"serviceAccountName":"build-bot"}}'`, or edit the YAML |
| YAML only | add `--dry-run=client -o yaml > pod.yaml` (flags go **before** `--`) |

`kubectl run` has no `--replicas`, `--requests`, `--limits` or `--serviceaccount` flags. Use YAML, `--overrides`, or the `kubectl create` / `kubectl set` commands on controllers.

### Generate, edit, apply

```bash
kubectl run web --image=nginx:1.27 --port=80 --labels=app=web --dry-run=client -o yaml > web.yaml
vi web.yaml                                       # add env, resources, hooks, volumes ...
kubectl apply -f web.yaml
kubectl explain pod.spec.containers.lifecycle.preStop --recursive   # field names without the browser
```

Generated output (note the defaults you can delete or keep):

```yaml
apiVersion: v1
kind: Pod
metadata:
  labels:
    app: web
  name: web
spec:
  containers:
  - image: nginx:1.27
    name: web
    ports:
    - containerPort: 80
    resources: {}
  dnsPolicy: ClusterFirst
  restartPolicy: Always
status: {}
```

### Change a running Pod

```bash
kubectl set image pod/web web=nginx:1.27-alpine        # allowed in place (container restarts)
kubectl label pod web env=prod                          # add a label (--overwrite to change one)
kubectl label pod web env-                              # remove a label
kubectl annotate pod web description="frontend"         # add an annotation

# Immutable change (env, command, ports, volumes...):
kubectl edit pod web                                    # save -> rejected; kubectl stores a copy:
#   A copy of your changes has been stored to "/tmp/kubectl-edit-1234.yaml"
kubectl replace --force -f /tmp/kubectl-edit-1234.yaml  # delete + recreate with your changes

# Same idea without edit:
kubectl get pod web -o yaml > web.yaml && vi web.yaml
kubectl replace --force -f web.yaml                     # add --grace-period=0 to skip the graceful wait
```

### Inspect

```bash
kubectl get pods -o wide --show-labels                  # node, IP, labels
kubectl get pods -l app=web -L tier                     # filter by label, show tier as a column
kubectl describe pod web                                # events, state, last state, exit codes
kubectl get pod web -o jsonpath='{.status.phase}{"\n"}'
kubectl get pod web -o jsonpath='{.status.containerStatuses[0].restartCount}{"\n"}'
kubectl get pod web -o jsonpath='{.status.containerStatuses[0].lastState.terminated.reason}{"\n"}'
kubectl logs web [-c container] [--previous] [-f] [--tail=50]
kubectl exec -it web -- sh                              # or: -- cat /etc/os-release
kubectl get events --sort-by=.lastTimestamp             # recent events in the namespace
```

### Delete

```bash
kubectl delete pod web                                  # graceful (terminationGracePeriodSeconds)
kubectl delete pod web --grace-period=5                 # shorter budget
kubectl delete pod web --grace-period=0 --force         # immediate API removal (use with care)
kubectl delete pods -l app=web                          # by label
```

---

## Exam traps & tips

> **Exam tip:** Flags for `kubectl run` go **before** `--`. Everything after `--` is the container's args (or its command with `--command`). `kubectl run x --image=busybox:1.36 -- sh -c "sleep 3600" --dry-run=client -o yaml` passes `--dry-run` to the container.

> **Exam tip:** `kubectl run` defaults to `--restart=Always`. For a test pod that should finish, add `--restart=Never`. With `--rm`, you must also attach (`-i` or `-it`).

> **Exam tip:** When a change to a Pod is rejected, do not hand-type the pod again. Use the `/tmp/kubectl-edit-*.yaml` copy with `kubectl replace --force -f`. Keep the same name if the task demands it.

> **Exam tip:** postStart runs **concurrently** with the main process. Do not rely on it running first; use an init container for "before the app starts".

> **Exam tip:** preStop time counts **inside** `terminationGracePeriodSeconds`. A 60 s preStop with the default 30 s grace means the app is SIGKILLed before it ever sees SIGTERM. Raise the grace period.

- `env` values must be strings: `value: "3"` and `value: "true"`, not `3` or `true` (the API rejects non-strings).
- Two containers in one pod cannot listen on the same port (shared network namespace).
- `kubectl delete pod` on a pod owned by a Deployment just produces a new pod. Delete or scale the **controller**.
- A pod name must be unique in its namespace. `replace --force` waits for the old pod to terminate first.
- `kubectl get pod x -o yaml` includes `status`, `uid`, `resourceVersion` and `managedFields`. `replace --force` copes with them, but strip them if you build a new manifest from that output.
- Static pod "won't delete"? It is a mirror pod. Remove the manifest file on that node.

---

## Architect notes

- **Never run bare Pods in production.** Use a controller for self-healing, rollout and scaling. Bare pods are for debugging and one-off tasks.
- **Graceful shutdown is a contract:** handle SIGTERM (exec-form ENTRYPOINT, or an init process like `tini` for shell wrappers), add a small `preStop` sleep to absorb endpoint propagation lag, and size `terminationGracePeriodSeconds` to your longest in-flight request or drain.
- **Use a consistent label taxonomy** (`app.kubernetes.io/*`) across teams. Selectors, NetworkPolicies, cost allocation and observability all depend on it. Use annotations for tool metadata.
- **Namespaces are the unit of tenancy** for RBAC, ResourceQuota, LimitRange, NetworkPolicy and Pod Security labels. Design them per team or app and environment, not per individual.
- **postStart is not a startup gate.** Use init containers, startupProbes or native sidecars for ordering; hooks are for small, idempotent side effects.
- **Prefer the downward API over calling the API server** for pod metadata (name, namespace, labels, resources). It is cheaper and needs no RBAC.
- **Plan for in-place resize** (GA v1.35): vertical scaling without restarts changes how you think about VPA and right-sizing, but check the `resizePolicy` per resource.

---

## Docs to bookmark

- Pods: <https://kubernetes.io/docs/concepts/workloads/pods/>
- Pod lifecycle (phases, restart policy, termination): <https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/>
- Container lifecycle hooks: <https://kubernetes.io/docs/concepts/containers/container-lifecycle-hooks/>
- Attach handlers to lifecycle events (example YAML): <https://kubernetes.io/docs/tasks/configure-pod-container/attach-handler-lifecycle-event/>
- `kubectl run` reference: <https://kubernetes.io/docs/reference/kubectl/generated/kubectl_run/>
- kubectl quick reference: <https://kubernetes.io/docs/reference/kubectl/quick-reference/>
- Labels and selectors: <https://kubernetes.io/docs/concepts/overview/working-with-objects/labels/>
- Annotations: <https://kubernetes.io/docs/concepts/overview/working-with-objects/annotations/>
- Namespaces: <https://kubernetes.io/docs/concepts/overview/working-with-objects/namespaces/>
- Static pods: <https://kubernetes.io/docs/tasks/configure-pod-container/static-pod/>
- Downward API: <https://kubernetes.io/docs/concepts/workloads/pods/downward-api/>
- Resize container resources in place: <https://kubernetes.io/docs/tasks/configure-pod-container/resize-container-resources/>

---

## Quick self-check

1. Write the `kubectl run` command that creates pod `bb` from `busybox:1.36` whose **command** is `sh -c 'sleep 3600'`, and saves YAML only to `bb.yaml`.
2. A pod shows `Completed`, then `CrashLoopBackOff`, but its logs show no error. What is the likely cause?
3. You need to add an env var to a running bare pod `api` and keep its name. Which commands?
4. A pod has `terminationGracePeriodSeconds: 30` and a preStop hook that sleeps 40 s. What happens on `kubectl delete pod`?
5. Which three fields of a running pod's spec can you change with a normal update?
6. How do you stop a static pod?

<details><summary>Answers</summary>

1. `kubectl run bb --image=busybox:1.36 --dry-run=client -o yaml --command -- sh -c 'sleep 3600' > bb.yaml`
2. The main process exits 0 (for example `command` dropped the CMD, or the program daemonizes). With `restartPolicy: Always` even a successful exit is restarted, which leads to back-off. Keep the process in the foreground.
3. `kubectl edit pod api` (rejected, copy saved to `/tmp/kubectl-edit-*.yaml`), then `kubectl replace --force -f /tmp/kubectl-edit-*.yaml`. Or `kubectl get pod api -o yaml > api.yaml`, edit it, then `kubectl replace --force -f api.yaml`.
4. The grace countdown starts before preStop. At 30 s the hook is still running, so the kubelet grants a one-time 2 s extension, then SIGKILLs. The app may never get SIGTERM. Fix it by raising `terminationGracePeriodSeconds`.
5. Container (and init container) `image`, `activeDeadlineSeconds` (set or decrease), `tolerations` (add only). Also `schedulingGates` (remove only), plus labels and annotations in metadata.
6. Remove (or move) its manifest from the node's `staticPodPath` (kubeadm: `/etc/kubernetes/manifests`). Deleting the mirror pod does not stop it.

</details>
