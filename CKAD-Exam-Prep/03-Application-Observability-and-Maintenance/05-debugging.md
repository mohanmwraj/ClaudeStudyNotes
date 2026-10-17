# Debugging in Kubernetes

**Why it matters:** "something is broken, make it work" tasks appear in every domain: a Deployment that never becomes available, a Pod stuck in Pending, a Service with no endpoints, an app that crashes on start. The exam rewards a **fast, systematic routine**: read the status, read the events, read the logs, fix the one thing that is wrong, verify. This chapter gives you the routine, a status/exit-code lookup table, and the debugging tools (`exec`, `debug`, `port-forward`, temp pods, `cp`).

---

## Core concepts

### A systematic flow: get → describe → events → logs → exec → debug

| Step | Command | Look for |
|---|---|---|
| 1. Get | `kubectl get pods -o wide` (and `get deploy,rs,svc`) | STATUS, READY `x/y`, RESTARTS, NODE, age |
| 2. Describe | `kubectl describe pod <p>` | State / **Last State** (reason, exit code), Ready, probe config, Conditions, mounts, **Events** at the bottom |
| 3. Events | `kubectl events --for pod/<p>` or `kubectl get events --sort-by=.metadata.creationTimestamp` | FailedScheduling, Failed (pull), FailedMount, Unhealthy, BackOff, Killing, FailedCreate (on the ReplicaSet) |
| 4. Logs | `kubectl logs <p> [-c c] [-p]` | the app's own error (use `-p` after a crash) |
| 5. Exec | `kubectl exec -it <p> -- sh` | config files, env, DNS, `wget localhost:port` |
| 6. Debug | `kubectl debug -it <p> --image=busybox:1.36 --target=<c>` | for images without a shell, or crashing containers (`--copy-to`) |

```text
kubectl get pod <p> -o wide
 |- Pending .............................. describe -> FailedScheduling: resources / taints / selector / PVC
 |- ContainerCreating (stuck) ............ describe -> FailedMount / FailedCreatePodSandBox
 |- ErrImagePull / ImagePullBackOff ...... describe -> image name, tag, registry, imagePullSecrets
 |- CreateContainerConfigError ........... describe -> missing ConfigMap / Secret / key, runAsNonRoot
 |- CrashLoopBackOff / Error ............. logs -p + describe (Last State: reason, exit code)
 |- OOMKilled ............................ describe (Exit Code 137) -> memory limit vs real usage
 |- Init:* ............................... logs -c <init-container>
 |- Running, READY 0/1 ................... describe -> "Readiness probe failed"
 \- Running 1/1 but app "doesn't work" .. logs, exec, port-forward, Service/DNS checks below
```

> **Exam tip:** fix the **owner**, not the Pod. If the Pod belongs to a Deployment, change the Deployment (`kubectl edit deploy`, `kubectl set image|env|resources`). Edits to its Pods are overwritten or lost when they are recreated.

### Pod status / reason reference

| STATUS / reason | Typical cause | How to confirm | Fix |
|---|---|---|---|
| **Pending** | Not schedulable: insufficient CPU/memory, untolerated taint, nodeSelector/affinity mismatch, missing or unbound PVC, hostPort conflict | `describe` → `FailedScheduling: 0/3 nodes are available: ...`; `-o wide` shows NODE `<none>` | Lower requests, add a toleration, fix labels/selector, create the PVC/StorageClass |
| **ContainerCreating** (stuck) | Volume can't be mounted (missing ConfigMap/Secret **volume**, PVC attach), sandbox/CNI failure, very large image | Events `FailedMount: ... configmap "x" not found`, `FailedCreatePodSandBox`, long `Pulling` | Create the missing object, fix the volume, check the CNI |
| **ErrImagePull** → **ImagePullBackOff** | Wrong image name/tag, private registry without credentials, registry unreachable | Events `Failed to pull image "nginx:1.277": ... not found` / `pull access denied` / `401 Unauthorized` | `kubectl set image ...`, add `imagePullSecrets` (`kubectl create secret docker-registry`) |
| **InvalidImageName** | Malformed reference (uppercase, bad characters) | describe | Fix the image string |
| **CrashLoopBackOff** | Container keeps exiting: app error, missing env/config, wrong command/args, failing liveness/startup probe, OOM. Back-off 10 s, 20 s, 40 s ... capped at 5 min, reset after 10 min of clean running | `kubectl logs -p`, describe **Last State** (`Reason`, `Exit Code`), `Killing` events for probe kills | Fix the cause (env, config, command, probe, limits) |
| **CreateContainerConfigError** | Referenced ConfigMap/Secret or **key** missing (env/envFrom); `runAsNonRoot` with a root image; subPath problems | describe → `Error: configmap "x" not found` / `couldn't find key k in ConfigMap ns/x` / `container has runAsNonRoot and image will run as root` | Create the object/key (the kubelet retries automatically), or fix `securityContext`/image |
| **CreateContainerError** | Runtime could not create the container: no command at all (image has no ENTRYPOINT/CMD and no `command`), name conflict, invalid mount | describe → `Error: ... failed to generate container ... spec ...` (wording varies by runtime) | Set `command`, fix mounts |
| **RunContainerError** | Created but could not start: entrypoint binary not found or not executable. Last State reason `StartError`, exit code 128 | describe → `exec: "/app/server": stat /app/server: no such file or directory` | Correct `command`/`args`/image |
| **OOMKilled** | Memory use exceeded the container's limit (kernel OOM killer) | describe → Last State `Reason: OOMKilled`, `Exit Code: 137`; `kubectl top pod` | Raise the limit (and request) to real usage, or fix the leak. Deployment: `kubectl set resources`. Bare Pod: recreate, or resize in place (stable v1.35, see below) |
| **Error** | Container exited with a non-zero code | `kubectl logs [-p]`, exit code in describe | Fix the app/config. With `restartPolicy: Never` it stays `Error` |
| **Completed** | Main process exited 0. Normal for Jobs. In a Deployment (`restartPolicy: Always`) it restarts and ends in CrashLoopBackOff | describe → `Reason: Completed, Exit Code: 0` | Run a long-lived foreground process (`nginx -g 'daemon off;'`, `sleep`), or use a Job |
| **Terminating** (stuck) | Finalizers, unreachable node, long grace period / slow preStop | `kubectl get pod p -o jsonpath='{.metadata.finalizers}'`, `kubectl get nodes` | Wait. Remove the finalizer only if you own it. Last resort: `kubectl delete pod p --force --grace-period=0` |
| **Evicted** | Node pressure (memory, disk, PIDs) or Pod over its `ephemeral-storage` limit. Phase `Failed`, `.status.reason: Evicted` | `kubectl get pod p -o jsonpath='{.status.reason}: {.status.message}'` → `The node was low on resource: memory...`. STATUS may show `Evicted`, `Error` or `ContainerStatusUnknown` | Set sane requests/limits, reduce disk use (logs, `emptyDir`). Clean up with `kubectl delete pods --field-selector=status.phase=Failed` |
| **Init:Error** / **Init:CrashLoopBackOff** | An init container exits non-zero (repeatedly) | `kubectl logs p -c <init>`, describe → *Init Containers* exit code | Fix the init command or its dependency |
| **Init:0/2** / **PodInitializing** | Init container still running (often waiting for a Service/DNS), or the app containers are starting | `kubectl logs p -c <init> -f` | Create what it waits for |
| **Unknown** | Node lost contact (kubelet not reporting) | `kubectl get nodes` → `NotReady`; `describe node` | Recover the node; the controller replaces Pods elsewhere. Force-delete if needed |
| **Running** but READY `0/1` | Readiness probe failing, or a sidecar/readiness gate not ready | describe → `Readiness probe failed: ...` | Fix the probe or the app ([02](02-probes-and-health-checks.md)) |
| **SchedulingGated** | `spec.schedulingGates` set | `kubectl get pod p -o jsonpath='{.spec.schedulingGates}'` | Remove the gates (normally done by a controller) |

Hands-on files for most rows: [yaml/broken/](yaml/broken/). Each starts with a comment that names the bug and the fix.

### Exit codes

| Exit code | Meaning | Typical situation |
|---|---|---|
| **0** | Success | `Completed`. In a Deployment the container restarts, so a process that "finishes" causes CrashLoopBackOff |
| **1** | Generic application error | App failed a check or threw an exception (reason `Error`) |
| **2** | Misuse of shell builtin / bad usage | Wrong CLI arguments, shell syntax error |
| **126** | Command found but **not executable** | Missing `+x`, a directory, a `noexec` mount |
| **127** | **Command not found** (reported by a shell) | Typo inside `sh -c "..."`, binary missing from `PATH` |
| **128** | Runtime could not start the process (`StartError`) | `command` points to a non-existent binary (exec'd directly, no shell) |
| **128 + n** | Killed by signal *n* | — |
| **130** | SIGINT (2) | Ctrl-C in an attached session |
| **134** | SIGABRT (6) | `abort()`, failed assertion |
| **137** | **SIGKILL (9)** | **OOMKilled** when the reason says so. Otherwise killed after the grace period expired (the app ignored SIGTERM on delete or after a liveness failure) |
| **139** | **SIGSEGV (11)** | Segmentation fault, wrong-architecture or broken native library |
| **143** | **SIGTERM (15)** | Graceful stop that the app honoured: Pod deletion, rollout, liveness-probe kill |

```bash
kubectl get pod p -o jsonpath='{.status.containerStatuses[0].lastState.terminated.exitCode} {.status.containerStatuses[0].lastState.terminated.reason}{"\n"}'
```

> Nice to know (v1.35+, beta, on by default): a container can override the Pod's `restartPolicy` with its own `restartPolicy` and `restartPolicyRules`, for example "restart only on exit code 42". If a container restarts (or doesn't) contrary to the Pod-level policy, check `spec.containers[].restartPolicy`.

---

## Key fields / syntax: the debugging tools

### `kubectl exec`

```bash
kubectl exec web -- ls /usr/share/nginx/html               # one-off command (first/default container)
kubectl exec -it web -c app -- sh                          # interactive shell in a chosen container
kubectl exec deploy/web -- env                             # a Pod of the Deployment
kubectl exec web -- sh -c 'echo $HOSTNAME; cat /etc/resolv.conf'   # shell features need sh -c
kubectl exec web -- wget -qO- -T 2 http://localhost:80/    # is the app answering inside the Pod?
```

`exec` needs the binary inside the image. Distroless and `pause`-like images have no shell, so use `kubectl debug`.

### `kubectl debug`: ephemeral containers (stable since v1.25)

```bash
kubectl debug -it web --image=busybox:1.36 --target=app            # add a debug container, attach
kubectl debug -it web --image=busybox:1.36 --target=app -c dbg -- sh
kubectl debug web --image=busybox:1.36 --target=app -c psdump -- ps   # non-interactive ...
kubectl logs web -c psdump                                           # ... read its output afterwards
kubectl get pod web -o jsonpath='{.spec.ephemeralContainers[*].name}'
```

- An ephemeral container is added to a **running** Pod without restarting it. It shares the Pod's network (and volumes if you mount them). It cannot have ports, probes or resources, never restarts, and cannot be removed: it stays in `spec.ephemeralContainers` until the Pod is deleted.
- `--target=<container>` joins that container's **process namespace** (if the runtime supports it), so `ps` shows its processes and `/proc/<pid>/root/` exposes its filesystem. Without `--target` you see only your own processes (unless the Pod has `shareProcessNamespace: true`).
- `kubectl exec` into a running ephemeral container works too: `kubectl exec -it web -c dbg -- sh`.

### `kubectl debug`: copy of the Pod

```bash
# Copy + add a debug container sharing processes (default --share-processes=true with --copy-to)
kubectl debug web -it --copy-to=web-debug --image=busybox:1.36 --share-processes
# Copy + replace the command of a crashing container so it stays up for inspection
kubectl debug crashy -it --copy-to=crashy-debug --container=crashy -- sh
# Copy + change images (name=image pairs, * = all containers)
kubectl debug web --copy-to=web-debug --set-image=app=busybox:1.36,sidecar=busybox:1.36
kubectl debug web --copy-to=web-debug --set-image='*=busybox:1.36'
# Useful extras: --same-node, --replace (delete the original), --keep-labels, --keep-liveness, --keep-readiness
kubectl delete pod web-debug crashy-debug                           # always clean up copies
```

- `--container=<name> -- <cmd>` changes **that** container's command. Without `--container`, kubectl adds a **new** container running `<cmd>`.
- Copies don't keep the original's labels by default (with the `legacy` and `general` profiles), so they don't receive Service traffic or get adopted by the ReplicaSet.
- With `general` (the v1.37 default) the copy also **drops the probes**, so a liveness probe cannot kill your `sleep`/`sh` debug session. With `legacy` the probes stay, so add `--profile=general` on older kubectl.

### `kubectl debug`: node

```bash
kubectl debug node/worker-1 -it --image=busybox:1.36
#   pod "node-debugger-worker-1-xxxxx" runs in the host IPC/network/PID namespaces, node root fs at /host
#   / # ls /host/var/log/pods ; cat /host/etc/resolv.conf ; ps
kubectl debug node/worker-1 -it --image=busybox:1.36 --profile=sysadmin   # privileged, e.g. for chroot /host
kubectl delete pod node-debugger-worker-1-xxxxx                           # clean up
```

### Debug profiles (`--profile`)

| Profile | Ephemeral (`--target`) | Copy (`--copy-to`) | Node (`node/x`) |
|---|---|---|---|
| `legacy` | no changes | removes labels | host namespaces + host `/` at `/host` |
| `general` | adds `SYS_PTRACE` | removes labels, annotations, probes; adds `SYS_PTRACE`; shares process namespace | host namespaces + `/host`; clears securityContext |
| `baseline` | clears securityContext | removes labels/annotations/probes; shares process namespace | **no** host namespaces, no `/host` |
| `restricted` | `runAsNonRoot`, drop `ALL`, no privilege escalation, seccomp `RuntimeDefault` | same + removals | same restrictions |
| `netadmin` | adds `NET_ADMIN` + `NET_RAW` | same + removals | host namespaces + `NET_ADMIN`/`NET_RAW` |
| `sysadmin` | **privileged** | privileged + removals | privileged + host namespaces + `/host` |

- **Default profile:** `general` from kubectl v1.36, so **`general` on the exam's v1.37**. kubectl v1.33–v1.35 default to `legacy` and print `--profile=legacy is deprecated and will be removed in the future`. `legacy` is still accepted with that warning and is planned for removal in v1.39. Pass `--profile=general` explicitly to get the same behaviour on every version.
- Custom profile (stable v1.32): `--custom=profile.yaml` holds a partial container spec (env, securityContext, ...) merged into the debug container. You cannot change its name, image, command, lifecycle or volumeDevices.
- In a namespace that enforces Pod Security `baseline`/`restricted`, an ephemeral container that adds capabilities (such as `general`'s `SYS_PTRACE`) is rejected. Use `--profile=baseline` or `--profile=restricted` there.

### `kubectl port-forward`

```bash
kubectl port-forward pod/web 8080:80             # localhost:8080 -> Pod port 80
kubectl port-forward svc/web 8080:80             # resolves the Service's targetPort, picks ONE Pod
kubectl port-forward deploy/web 8080:80
kubectl port-forward pod/web :80                 # random local port
kubectl port-forward --address 0.0.0.0 pod/web 8080:80
kubectl port-forward svc/web 8080:80 >/dev/null 2>&1 &  sleep 2; curl -s localhost:8080 | head -3; kill %1
```

Port-forward tunnels through the API server and kubelet straight into the Pod's network namespace. It bypasses the Service VIP, kube-proxy and NetworkPolicies. If port-forward works but the Service does not, the bug is in the Service, its endpoints or a policy, not the app.

### Temporary client Pods

```bash
kubectl run tmp --rm -it --image=busybox:1.36 --restart=Never -- wget -qO- -T 2 http://web.app.svc.cluster.local
kubectl run tmp --rm -it --image=busybox:1.36 --restart=Never -- nslookup web.app.svc.cluster.local
kubectl run tmp --rm -it --image=curlimages/curl:8.10.1 --restart=Never -- curl -sS -m 3 http://web.app:80/healthz
kubectl run tmp --rm -it --image=busybox:1.36 --restart=Never -- sh            # interactive toolbox
kubectl run tmp -n app --rm -i -q --image=busybox:1.36 --restart=Never -- wget -qO- -T 2 http://web > /opt/course/9/out.txt
```

- `--rm` needs an attached session (`-i`/`-it`). `--restart=Never` makes a plain Pod that is not restarted.
- When **redirecting output to a file**, drop `-t` (a TTY adds `\r`) and add `-q`. Otherwise `pod "tmp" deleted` and prompt messages land in the file.
- Run the client in the **same namespace** for short names, or use `svc.ns` / the FQDN. busybox `nslookup` can be quirky with search domains, so test with the FQDN.
- Use `-T 2` (wget) or `-m 3` (curl) timeouts so a broken Service doesn't hang your terminal.

### `kubectl cp`

```bash
kubectl cp app/web:/etc/nginx/nginx.conf ./nginx.conf                 # Pod -> local (needs tar in the image)
kubectl cp ./index.html app/web:/usr/share/nginx/html/index.html -c nginx
kubectl exec -n app web -- cat /etc/nginx/nginx.conf > nginx.conf     # no tar? stream with cat instead
```

### Service and DNS debugging steps

```bash
# 1. Service spec: selector, port, targetPort, type
kubectl get svc web -n app -o wide
kubectl describe svc web -n app                    # Selector, TargetPort, Endpoints (ready only)
# 2. Endpoints exist? (EndpointSlices; `get endpoints` is deprecated since v1.33)
kubectl get endpointslices -n app -l kubernetes.io/service-name=web
# 3. Empty -> compare the selector with the Pod labels
kubectl get pods -n app --show-labels
kubectl get pods -n app -l app=web                 # use the Service's exact selector
# 4. Pods selected but not ready? Not-ready Pods get no traffic
kubectl get endpointslices -n app -l kubernetes.io/service-name=web -o jsonpath='{range .items[*].endpoints[*]}{.addresses[0]} ready={.conditions.ready}{"\n"}{end}'
# 5. targetPort = the port the container really listens on? (a named targetPort must match ports[].name)
kubectl get pod <pod> -n app -o jsonpath='{.spec.containers[*].ports}'
# 6. Test the Pod directly, then the Service, from inside the cluster
kubectl run tmp -n app --rm -it --image=busybox:1.36 --restart=Never -- wget -qO- -T 2 http://<pod-ip>:<containerPort>
kubectl run tmp -n app --rm -it --image=busybox:1.36 --restart=Never -- wget -qO- -T 2 http://web:<port>
# 7. DNS
kubectl run tmp -n app --rm -it --image=busybox:1.36 --restart=Never -- nslookup web.app.svc.cluster.local
kubectl get pods -n kube-system -l k8s-app=kube-dns                  # CoreDNS running?
# 8. NetworkPolicies selecting the Pods (ingress) or the client (egress, incl. DNS port 53)
kubectl get networkpolicy -n app
```

Typical root causes, most frequent first: selector/label typo, wrong `targetPort`, Pods not ready, client in another namespace using the short name, a NetworkPolicy blocking traffic or DNS. More on Services in [chapter 05](../05-Services-and-Networking/README.md).

### RBAC errors

```text
Error from server (Forbidden): pods is forbidden: User "system:serviceaccount:app:reader" cannot list resource "pods" in API group "" in the namespace "app"
```

```bash
kubectl auth can-i list pods -n app --as=system:serviceaccount:app:reader     # yes / no
kubectl auth can-i --list -n app --as=system:serviceaccount:app:reader        # everything it may do
kubectl auth whoami                                                           # who am I right now
kubectl get pod <pod> -n app -o jsonpath='{.spec.serviceAccountName}'         # which SA the app uses
kubectl get rolebindings,clusterrolebindings -A -o wide | grep reader         # what is bound to it
kubectl create role pod-reader -n app --verb=get,list,watch --resource=pods
kubectl create rolebinding reader-binding -n app --role=pod-reader --serviceaccount=app:reader
```

The message tells you the **user** (or SA), **verb**, **resource**, **API group** and **namespace**: everything you need for the Role. Details in [chapter 04](../04-Application-Environment-Configuration-and-Security/README.md).

### Scheduling failures (Pending)

| FailedScheduling message (abridged) | Cause | Fix |
|---|---|---|
| `0/3 nodes are available: 3 Insufficient cpu` / `Insufficient memory` | Requests bigger than any node's free allocatable | Lower requests, free capacity, add nodes |
| `... node(s) had untolerated taint {node-role.kubernetes.io/control-plane: }` | Taint without matching toleration | Add a toleration or target other nodes |
| `... node(s) didn't match Pod's node affinity/selector` | nodeSelector/affinity labels match no node | Label a node or fix the selector |
| `persistentvolumeclaim "data" not found` | Pod references a missing PVC | Create the PVC / fix `claimName` |
| `pod has unbound immediate PersistentVolumeClaims` | PVC Pending (no matching PV, no default StorageClass) | Fix the PVC/StorageClass ([chapter 01](../01-Application-Design-and-Build/README.md)) |
| `... node(s) didn't have free ports for the requested pod ports` | hostPort already used | Drop `hostPort` (use a Service) |
| *(no Pod at all)* ReplicaSet `FailedCreate: ... exceeded quota` / `violates PodSecurity` | Admission rejected the Pod | Fit the quota / LimitRange / Pod Security level |

```bash
kubectl describe node <node> | grep -A8 "Allocated resources"     # requested vs allocatable
kubectl get nodes -o custom-columns=NAME:.metadata.name,TAINTS:.spec.taints
kubectl get nodes --show-labels
```

### Node-level checks (brief, mostly CKA)

```bash
kubectl get nodes -o wide                          # Ready / NotReady / SchedulingDisabled
kubectl describe node worker-1                     # Conditions: MemoryPressure, DiskPressure, PIDPressure, Ready; Taints; Events
kubectl top node                                   # real usage (metrics-server)
kubectl debug node/worker-1 -it --image=busybox:1.36   # look at /host/var/log, /host/etc
# On the node itself (CKA territory): journalctl -u kubelet, crictl ps, crictl logs <id>
```

---

## Imperative commands: 60-second triage kit

```bash
kubectl config current-context && kubectl config view --minify -o jsonpath='{..namespace}'   # right cluster/ns?
kubectl get pods -o wide -n <ns>                                     # what is broken
kubectl describe pod <pod> -n <ns> | sed -n '/State:/,/Ready:/p;/Events:/,$p'   # states + events
kubectl logs <pod> -n <ns> --previous --tail=30                       # last crash output
kubectl get events -n <ns> --field-selector type=Warning --sort-by=.metadata.creationTimestamp | tail
kubectl get deploy,rs -n <ns> && kubectl describe rs -n <ns> | grep -A5 Events   # Pods not even created?
kubectl get pod <pod> -n <ns> -o yaml > /tmp/pod.yaml                # snapshot before you change things
```

Fixing patterns:

```bash
kubectl set image deploy/web nginx=nginx:1.27 -n <ns>                 # wrong image
kubectl set env deploy/web DB_HOST=db -n <ns>                         # missing env var
kubectl set resources deploy/web -c=nginx --requests=cpu=100m,memory=64Mi --limits=memory=128Mi -n <ns>
kubectl edit deploy/web -n <ns>                                       # probes, command, volumes
kubectl get pod p -o yaml > p.yaml && vim p.yaml && kubectl replace --force -f p.yaml   # bare Pod fields
kubectl rollout status deploy/web -n <ns>                             # verify
kubectl rollout undo deploy/web -n <ns>                               # bad rollout? go back
```

In-place resize of a **bare Pod's** CPU/memory, without recreating it (stable since v1.35, kubectl v1.32+). The QoS class must stay the same: a Burstable Pod must not end up with requests == limits for both CPU and memory.

```bash
kubectl patch pod oom-demo --subresource resize -p '{"spec":{"containers":[{"name":"app","resources":{"requests":{"memory":"96Mi"},"limits":{"memory":"128Mi"}}}]}}'
kubectl edit pod oom-demo --subresource resize                        # interactive alternative
kubectl get pod oom-demo -o jsonpath='{.status.containerStatuses[0].resources}{"\n"}'   # what is applied
```

---

## Exam traps & tips

> **Exam tip:** switch to the context the task names first. Half of all "it doesn't work" moments in the exam are the wrong cluster or namespace.

> **Exam tip:** CrashLoopBackOff is a *symptom*. The reason is in `Last State` (exit code) and `kubectl logs -p`. Exit 137 + `OOMKilled` is memory. 1 or 2 is the app or its args. 127 is a typo in the command. 128 + `StartError` is a missing binary.

> **Exam tip:** most Pod fields are **immutable** (env, probes, volumes, command, ports). You can change `image` in place, and CPU/memory only through the `resize` subresource. Everything else on a bare Pod needs `kubectl replace --force -f` (delete + create). Keep the name and namespace exactly.

> **Exam tip:** CreateContainerConfigError from a missing ConfigMap/Secret **key** fixes itself once you create the key. The kubelet retries, so no Pod recreation is needed.

> **Exam tip:** Deployment `READY 0/3` with **no Pods** → describe the **ReplicaSet** (quota, LimitRange, Pod Security, missing ServiceAccount). Pod-level commands show nothing.

> **Exam tip:** a Service with no endpoints is almost always a selector/label mismatch. A Service with endpoints that refuses connections is almost always a wrong `targetPort` (or Pods not ready).

> **Exam tip:** `kubectl debug` copies and temp Pods are extra objects. Delete them when done unless the task says to keep them.

---

## Architect notes

- **Design for debuggability.** Use small images, but have a debugging path: ephemeral containers with a vetted toolbox image (pinned, from your registry), RBAC that grants `pods/ephemeralcontainers` only to on-call roles, and an audit trail of who attached to what.
- **Distroless + ephemeral containers** is the modern pattern. No shell in production images, tools injected on demand. Pod Security levels decide which debug profiles are usable (`baseline`/`restricted` in hardened namespaces).
- **Make failures self-describing:** meaningful exit codes, `terminationMessagePolicy: FallbackToLogsOnError`, structured logs, readiness probes that report *why* (in the body/logs), and events your operators emit.
- **Runbooks per status.** Encode the status table above into alerts with links: CrashLoopBackOff, ImagePullBackOff, Pending > 5 min, OOMKilled, evictions, Deployment unavailable. kube-state-metrics exposes all of them.
- **Prevent the classics with admission policy** (ValidatingAdmissionPolicy/Kyverno/Gatekeeper): require resource requests/limits, forbid `:latest`, require probes, enforce label conventions that Service selectors rely on.
- **Capacity and scheduling visibility:** track requested vs allocatable per node pool. Pending Pods with `Insufficient cpu` are a cluster-autoscaler or quota signal, not an app bug.
- **Node debugging is privileged access.** `kubectl debug node/` with `sysadmin` equals root on the node. Restrict it like SSH, and prefer node-problem-detector and centralized node logs.
- **Post-incident evidence disappears fast** (events in 1 h, logs on Pod deletion). Ship events and logs centrally, and snapshot `kubectl get pod -o yaml` before deleting broken objects.

---

## Docs to bookmark

- Debug Pods: https://kubernetes.io/docs/tasks/debug/debug-application/debug-pods/
- Debug Running Pods (exec, ephemeral containers, copies, node shell, profiles): https://kubernetes.io/docs/tasks/debug/debug-application/debug-running-pod/
- Debug Services: https://kubernetes.io/docs/tasks/debug/debug-application/debug-service/
- Debug Init Containers: https://kubernetes.io/docs/tasks/debug/debug-application/debug-init-containers/
- Determine the Reason for Pod Failure: https://kubernetes.io/docs/tasks/debug/debug-application/determine-reason-pod-failure/
- Debugging Kubernetes Nodes With Kubectl: https://kubernetes.io/docs/tasks/debug/debug-cluster/kubectl-node-debug/
- Debugging DNS Resolution: https://kubernetes.io/docs/tasks/administer-cluster/dns-debugging-resolution/
- `kubectl debug` reference: https://kubernetes.io/docs/reference/kubectl/generated/kubectl_debug/
- Pod Lifecycle (restart back-off, states): https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/
- Node-pressure Eviction: https://kubernetes.io/docs/concepts/scheduling-eviction/node-pressure-eviction/

---

## Quick self-check

1. A Pod shows `CrashLoopBackOff` with Last State `Reason: Error, Exit Code: 127`. What is the likely cause?
2. `kubectl exec -it app -- sh` fails with `executable file not found`. How do you get a shell next to the app's processes?
3. A Deployment is `0/2` READY and `kubectl get pods` shows nothing for it. Where do you look?
4. What is the difference between exit code 137 with reason `OOMKilled` and exit code 143?
5. A Service has an endpoint, but `wget` to it gets `connection refused`. What do you check first?
6. Which `kubectl debug` option lets you restart a crashing container with `sleep 1d` so you can inspect it?

<details><summary>Answers</summary>

1. A command typed inside a shell script (`sh -c`) does not exist: a typo or a binary missing from the image. Check `kubectl logs -p` for `not found`.
2. `kubectl debug -it app --image=busybox:1.36 --target=<container>` adds an ephemeral container in the target's process namespace.
3. The ReplicaSet: `kubectl describe rs -l <selector>` (or warning events with `reason=FailedCreate`), typically a quota, LimitRange or Pod Security rejection.
4. 137 + `OOMKilled`: SIGKILL by the kernel because the memory limit was exceeded. 143: SIGTERM, a graceful stop (deletion, rollout, or liveness kill that the app honoured).
5. The Service's `targetPort` vs the port the container actually listens on (and whether the endpoint is ready).
6. `kubectl debug <pod> -it --copy-to=<copy> --container=<name> -- sleep 1d` (or `-- sh` for a shell).

</details>
