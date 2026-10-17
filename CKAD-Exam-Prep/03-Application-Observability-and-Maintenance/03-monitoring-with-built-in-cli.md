# Use Built-in CLI Tools to Monitor Kubernetes Applications

**Why it matters:** "built-in CLI tools" means kubectl: `get`, `describe`, events, `top`, jsonpath/custom-columns, `wait`, `rollout status`. Exam tasks look like: "write the name of the Pod with the highest CPU usage in namespace X to `/opt/course/3/pod.txt`", "list all Pods that are not Ready", "write the restart count of container Y". They are quick points if you can produce **exactly** the requested output in a file.

---

## Core concepts

### Which tool answers which question

| Tool | Answers | Data source | Prerequisite |
|---|---|---|---|
| `kubectl get` | What exists, status summary (READY, STATUS, RESTARTS, AGE, IP, NODE) | API server (etcd) | none |
| `kubectl describe` | Full detail + related **Events** at the bottom | API server | none |
| `kubectl get events` / `kubectl events` | What happened (scheduling, pulls, probe failures, kills, scaling) | Event objects (kept **1 h** by default, kube-apiserver `--event-ttl`) | none |
| `kubectl top pod/node` | Current CPU / memory **usage** | Metrics API `metrics.k8s.io`, served by **metrics-server** | metrics-server installed |
| `kubectl logs` | What the app printed (stdout/stderr) | kubelet → node log files | see [04-container-logs.md](04-container-logs.md) |
| `kubectl wait` / `kubectl rollout status` | Block until a condition is reached | API server watch | none |

### STATUS column ≠ phase

`kubectl get pods` STATUS is a **computed** string. Pod `status.phase` has only five values:

| Phase | Meaning |
|---|---|
| `Pending` | Accepted, but not all containers are created/running yet: waiting for scheduling, image pulls, volume mounts |
| `Running` | Bound to a node, all containers created, at least one running (or restarting) |
| `Succeeded` | All containers terminated successfully and won't restart |
| `Failed` | All containers terminated, at least one failed (non-zero exit or killed by the system) |
| `Unknown` | State cannot be obtained, usually lost contact with the node |

STATUS shows, in priority order: an init-container problem (`Init:Error`, `Init:CrashLoopBackOff`, `Init:0/2`), else a container's waiting/terminated reason (`CrashLoopBackOff`, `ImagePullBackOff`, `CreateContainerConfigError`, `OOMKilled`, `Error`, `Completed`; with several containers, the first one in spec order that has a reason wins), else the Pod's `status.reason` (for example `Evicted`) or the phase. `Terminating` appears when a deletion is pending. The full table is in [05-debugging.md](05-debugging.md).

### Pod status fields worth knowing

| Field (jsonpath) | Values / meaning |
|---|---|
| `.status.phase` | Pending / Running / Succeeded / Failed / Unknown |
| `.status.conditions[]` | `PodScheduled`, `PodReadyToStartContainers`, `Initialized`, `ContainersReady`, `Ready` (each `True`/`False`) |
| `.status.containerStatuses[]` | per container: `name`, `ready`, `started`, `restartCount`, `image`, `state` (waiting/running/terminated + reason), `lastState` (previous run: `terminated.reason`, `exitCode`, `finishedAt`) |
| `.status.initContainerStatuses[]` | same for init containers **and native sidecars** |
| `.status.qosClass` | `Guaranteed` / `Burstable` / `BestEffort` |
| `.status.podIP`, `.status.hostIP`, `.spec.nodeName`, `.status.startTime` | placement info |

### Usage vs. requests vs. limits

| | What it is | Where you see it |
|---|---|---|
| **requests** | Reserved for scheduling (the guarantee) | Pod spec; `kubectl describe node` → *Allocated resources* (**sum of requests/limits**, not real usage) |
| **limits** | Hard cap: CPU is **throttled**, memory over the limit is **OOM-killed** (exit 137) | Pod spec |
| **usage** | What the container consumes **now** | `kubectl top`. CPU in millicores (rate over a short window), memory = **working set** in Mi |

- `kubectl top node` CPU% and MEMORY% are relative to the node's **allocatable** (use `--show-capacity` for capacity).
- A Pod can use more than its request (up to its limit, or the free node capacity if no limit). Comparing top output with requests tells you who is "over-consuming". Requests and limits are covered in [chapter 04](../04-Application-Environment-Configuration-and-Security/README.md).

### metrics-server (prerequisite for `kubectl top`)

- Cluster add-on that scrapes every kubelet's resource-metrics endpoint periodically (the official manifest sets `--metric-resolution=15s`) and serves the aggregated `metrics.k8s.io` API. It keeps no history: it is not a monitoring system, it feeds `kubectl top`, HPA and VPA.
- Not installed: `error: Metrics API not available`. Just installed, or Pod too new: `error: metrics not available yet`. Wait a minute.
- Check it: `kubectl get apiservices | grep metrics` (AVAILABLE must be `True`) and `kubectl -n kube-system get deploy metrics-server`.
- Current metrics-server releases (0.9.x, for Kubernetes 1.34+) serve `metrics.k8s.io/v1beta1`. The Kubernetes v1.37 docs describe the Metrics API as stable `v1`, so check what your cluster serves with `kubectl api-versions | grep metrics`. `kubectl top` handles either version. Lab install (kind/minikube needs `--kubelet-insecure-tls`): see [../00-Exam-Overview-and-Setup/README.md](../00-Exam-Overview-and-Setup/README.md).

---

## Key fields / syntax

### jsonpath for status (copy-paste table)

| Want | Command |
|---|---|
| Phase | `kubectl get pod web -o jsonpath='{.status.phase}'` |
| Ready condition | `kubectl get pod web -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}'` |
| Restart count (first container) | `kubectl get pod web -o jsonpath='{.status.containerStatuses[0].restartCount}'` |
| Restart count of a named container | `kubectl get pod web -o jsonpath='{.status.containerStatuses[?(@.name=="app")].restartCount}'` |
| Why the last run ended | `kubectl get pod web -o jsonpath='{.status.containerStatuses[0].lastState.terminated.reason}'` (`OOMKilled`, `Error`, `Completed`) |
| Exit code of the last run | `kubectl get pod web -o jsonpath='{.status.containerStatuses[0].lastState.terminated.exitCode}'` |
| Current waiting reason | `kubectl get pod web -o jsonpath='{.status.containerStatuses[0].state.waiting.reason}'` |
| QoS class | `kubectl get pod web -o jsonpath='{.status.qosClass}'` |
| Node / IP | `kubectl get pod web -o jsonpath='{.spec.nodeName} {.status.podIP}'` |
| Images of all containers | `kubectl get pod web -o jsonpath='{.spec.containers[*].image}'` |
| One line per Pod | `kubectl get pods -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.phase}{"\n"}{end}'` |
| Last element of a list | `kubectl get events -o jsonpath='{.items[-1:].message}'` (negative slices are supported) |

### custom-columns and sorting

```bash
kubectl get pods -o custom-columns='NAME:.metadata.name,STATUS:.status.phase,RESTARTS:.status.containerStatuses[0].restartCount,NODE:.spec.nodeName,QOS:.status.qosClass'
kubectl get pods --no-headers -o custom-columns=:metadata.name           # names only, one per line
kubectl get pods --sort-by='.status.containerStatuses[0].restartCount'     # ascending
kubectl get pods --sort-by=.metadata.creationTimestamp                   # oldest first
kubectl get pods --sort-by=.status.startTime
```

---

## Imperative commands

### `kubectl get`

```bash
kubectl get pods -o wide                    # + IP, NODE, NOMINATED NODE, READINESS GATES
kubectl get pods -w                         # watch changes (Ctrl-C to stop)
kubectl get pods -w --output-watch-events   # + ADDED/MODIFIED/DELETED column
kubectl get pods --show-labels              # all labels in one column
kubectl get pods -L app,tier                # chosen labels as columns
kubectl get pods -l 'app=web,tier!=cache'   # label selector
kubectl get pods --field-selector=status.phase!=Running           # field selector
kubectl get pods -A --field-selector=spec.nodeName=worker-1       # everything on one node
kubectl get deploy,rs,pods,svc -n app                             # several kinds at once
kubectl get all -n app                                            # common kinds (not ConfigMaps/Secrets/Ingress)
kubectl get pods -o name                                          # pod/web-1 (kind/name)
```

### `kubectl describe`

```bash
kubectl describe pod web                    # read: State / Last State / Ready / Restart Count / probes / Events
kubectl describe pod web | tail -20         # just the Events section
kubectl describe deploy web                 # Replicas line, Conditions (Available, Progressing), Events
kubectl describe rs <rs-name>               # why Pods are NOT created (quota, PSA, admission errors)
kubectl describe node worker-1              # Conditions, Taints, Allocatable, Allocated resources, Events
kubectl describe svc web                    # Selector, TargetPort, Endpoints (ready endpoints only)
```

### Events

```bash
kubectl get events -n app                                         # columns: LAST SEEN TYPE REASON OBJECT MESSAGE
kubectl get events -n app --sort-by=.metadata.creationTimestamp   # reliable time order (oldest first)
kubectl get events -n app --sort-by=.lastTimestamp                # classic idiom; some events only have eventTime
kubectl get events -n app --field-selector type=Warning
kubectl get events -n app --field-selector involvedObject.name=web-7d4b9c-x2kq,involvedObject.kind=Pod
kubectl get events -n app --field-selector reason=FailedScheduling
kubectl get events -A --field-selector type=Warning -w            # stream warnings cluster-wide
kubectl events -n app                                             # newer command, already sorted by time
kubectl events -n app --for pod/web-7d4b9c-x2kq                   # events of one object
kubectl events -n app --types=Warning                             # only warnings (Normal,Warning)
kubectl events -A --types=Warning -w
```

Common event reasons: `Scheduled`, `FailedScheduling`, `Pulling`, `Pulled`, `Failed` (image pull), `BackOff`, `Created`, `Started`, `Killing`, `Unhealthy` (probe failures), `FailedMount`, `FailedCreatePodSandBox`, `Evicted`, `SystemOOM` (node event from the kubelet), `ScalingReplicaSet` (Deployment), `SuccessfulCreate` / `FailedCreate` (ReplicaSet/Job), `Completed` / `BackoffLimitExceeded` (Job).

> **Exam tip:** events are deleted after one hour by default. If a Pod has been broken for longer, `describe` may show `Events: <none>`. Rely on `.status.containerStatuses[].lastState` and the logs instead.

### `kubectl top` (needs metrics-server)

```bash
kubectl top node                                  # NAME CPU(cores) CPU(%) MEMORY(bytes) MEMORY(%)
kubectl top node --sort-by=memory --no-headers
kubectl top node --show-capacity                  # percentages vs capacity instead of allocatable
kubectl top pod -n obs-top                        # NAME CPU(cores) MEMORY(bytes)
kubectl top pod -n obs-top --sort-by=cpu          # highest first
kubectl top pod -n obs-top --sort-by=memory --containers   # POD NAME CPU MEMORY per container
kubectl top pod -A --sort-by=memory               # first column becomes NAMESPACE
kubectl top pod -l app=web --sum                  # totals line at the end
kubectl top pod web-7d4b9c-x2kq --containers
```

### `kubectl wait` and rollout status

```bash
kubectl wait --for=condition=Ready pod/web --timeout=60s               # default timeout 30s
kubectl wait --for=condition=Ready pod -l app=web --timeout=120s       # every matching Pod
kubectl wait --for=condition=Available deployment/web --timeout=120s
kubectl wait --for=condition=Complete job/report --timeout=120s
kubectl wait --for=condition=Failed job/report --timeout=60s
kubectl wait --for=jsonpath='{.status.phase}'=Running pod/web
kubectl wait --for=jsonpath='{.status.readyReplicas}'=3 deployment/web
kubectl wait --for=delete pod/web --timeout=60s
kubectl wait --for=create secret/web-tls --timeout=30s
kubectl rollout status deployment/web --timeout=2m
```

### Writing results to files exactly as asked

```bash
mkdir -p /opt/course/3

# Pod with the highest CPU in a namespace -> name only
kubectl top pod -n obs-top --sort-by=cpu --no-headers | head -1 | awk '{print $1}' > /opt/course/3/pod.txt

# Same across all namespaces: column 1 is NAMESPACE, the name is column 2
kubectl top pod -A --sort-by=memory --no-headers | head -1 | awk '{print $2}' > /opt/course/3/pod-all.txt

# Node with the highest memory usage
kubectl top node --sort-by=memory --no-headers | head -1 | awk '{print $1}' > /opt/course/3/node.txt

# Names of Pods that are not Ready
kubectl get pods -n app -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.status.conditions[?(@.type=="Ready")].status}{"\n"}{end}' \
  | awk '$2!="True"{print $1}' > /opt/course/3/not-ready.txt

# Names only, one per line (no "pod/" prefix)
kubectl get pods -n app --no-headers -o custom-columns=:metadata.name > /opt/course/3/pods.txt

# "Write the command" tasks: store the command itself, not its output
echo 'kubectl top pod -A --sort-by=cpu' > /opt/course/3/cmd.sh

cat /opt/course/3/pod.txt                                  # ALWAYS check the file
```

> **Exam tip:** "name only" means `web-7d4b9c-x2kq`, not `pod/web-7d4b9c-x2kq` and not the header line. Use `--no-headers`, `awk '{print $1}'`, or `-o jsonpath='{.metadata.name}'`.

---

## Exam traps & tips

> **Exam tip:** `kubectl top` with `-A` shifts the columns (NAMESPACE first). With `--containers` the columns are `POD NAME CPU MEMORY`. Pick the right `awk` field.

> **Exam tip:** `--sort-by=cpu|memory` for `top` sorts **descending** (highest first), while `kubectl get --sort-by=<jsonpath>` sorts **ascending**. Use `tail -1` or `tac` with `get`.

> **Exam tip:** `top` values change at every scrape. Run the command once, save the answer, and don't over-think a tie.

> **Exam tip:** `kubectl get pods` READY `1/2` means one container isn't ready. STATUS can still be `Running`. Look at `containerStatuses[*].ready` and the probes.

> **Exam tip:** if a Deployment shows `0/3` READY and **no Pods exist**, the problem is above the Pods. `kubectl describe rs` shows `FailedCreate` (quota exceeded, Pod Security violation, missing ServiceAccount).

> **Exam tip:** on Windows terminals jsonpath needs double quotes. In the exam (Linux bash), single quotes around jsonpath are correct.

---

## Architect notes

- **metrics-server ≠ monitoring.** It holds only the latest sample. Production uses Prometheus (or a managed equivalent), kube-state-metrics (object state such as restarts, readiness, desired vs available replicas), node-exporter, and dashboards/alerts in Grafana.
- **Alert on symptoms first**: SLO burn (error rate, latency) at the Service level. Then on causes: restarts (`kube_pod_container_status_restarts_total`), `kube_deployment_status_replicas_unavailable`, OOM kills, throttling (`container_cpu_cfs_throttled_periods_total`), PVC usage.
- **Events are short-lived** (1 h TTL). Ship them with an event exporter to your log store if you want post-mortems.
- **Right-size from usage data.** Compare `kubectl top` or Prometheus usage percentiles with requests. Under-requested Pods get evicted or throttled; over-requested ones waste nodes. VPA in recommendation mode helps.
- **HPA depends on the Metrics API and on CPU/memory requests** (utilization is a percentage of the request). A broken metrics-server silently stops autoscaling. Monitor the `v1beta1.metrics.k8s.io` APIService.
- **Watch API load:** `kubectl get -w` and tight `kubectl wait` loops in CI are cheap, but thousands of polling scripts are not. Prefer watches/informers in controllers.
- **Standardise labels** (`app.kubernetes.io/name`, `part-of`, `version`) so every selector-based query (`-l`, top, logs, dashboards) works the same way across teams.

---

## Docs to bookmark

- kubectl Quick Reference (sorting, jsonpath, events, top): https://kubernetes.io/docs/reference/kubectl/quick-reference/
- JSONPath support: https://kubernetes.io/docs/reference/kubectl/jsonpath/
- `kubectl top pod`: https://kubernetes.io/docs/reference/kubectl/generated/kubectl_top/kubectl_top_pod/
- `kubectl events`: https://kubernetes.io/docs/reference/kubectl/generated/kubectl_events/
- `kubectl wait`: https://kubernetes.io/docs/reference/kubectl/generated/kubectl_wait/
- Resource metrics pipeline (metrics-server, working set): https://kubernetes.io/docs/tasks/debug/debug-cluster/resource-metrics-pipeline/
- Pod Lifecycle (phases, conditions, container states): https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/

---

## Quick self-check

1. `kubectl top pod` returns `error: Metrics API not available`. What is missing and how do you confirm it?
2. Write a command that puts only the name of the Pod using the most memory in namespace `shop` into `/opt/course/1/pod.txt`.
3. Which jsonpath returns why the previous run of the first container ended?
4. Where do you look when a Deployment has 0 Pods at all?
5. Which `kubectl wait` condition do you use for a Deployment, and which for a Job?

<details><summary>Answers</summary>

1. metrics-server (the `metrics.k8s.io` API). `kubectl get apiservices | grep metrics` and `kubectl -n kube-system get deploy metrics-server`.
2. `kubectl top pod -n shop --sort-by=memory --no-headers | head -1 | awk '{print $1}' > /opt/course/1/pod.txt`
3. `{.status.containerStatuses[0].lastState.terminated.reason}` (plus `.exitCode` for the code).
4. The ReplicaSet's events: `kubectl describe rs -l app=<label>` or `kubectl get events --field-selector reason=FailedCreate`. Quota, admission or Pod Security rejections show up there.
5. `--for=condition=Available` for Deployments, `--for=condition=Complete` (or `Failed`) for Jobs.

</details>
