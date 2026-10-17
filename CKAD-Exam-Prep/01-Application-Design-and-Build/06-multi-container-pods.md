# Multi-Container Pod Design Patterns

**Why it matters:** the competency is *"Understand multi-container Pod design patterns (e.g. sidecar, init and others)"*. Typical tasks: add an **init container** that prepares a file or waits for a dependency; add a **sidecar** that streams a log file to stdout; turn a sidecar into a **native sidecar** so a Job can complete; build an **adapter** or **ambassador**; or debug a pod stuck in `Init:CrashLoopBackOff`. You must know how containers in a pod share network and storage, the start and stop ordering, and the `-c` flag.

---

## Core concepts

### What containers in one Pod share

| Shared | Consequence |
|---|---|
| **Network namespace** | one IP; containers reach each other on `localhost:<port>`; ports must not collide |
| **Volumes** | any pod volume (typically `emptyDir`) can be mounted by several containers, each at its own path |
| **IPC namespace** | SysV IPC / POSIX shared memory |
| **PID namespace** (only with `shareProcessNamespace: true`) | see and signal each other's processes; `/proc/<pid>/root` exposes another container's filesystem |
| **Lifecycle and node** | scheduled, started and deleted together, on the same node |
| Not shared | the container filesystem (image), resources (each container has its own requests and limits), restart counts |

### The patterns

| Pattern | What it does | Implemented as | Example |
|---|---|---|---|
| **Init container** | runs **before** the app, **sequentially**, each to **successful completion** | `spec.initContainers[]` (no `restartPolicy`) | wait for a DB, run migrations, render config, fix volume permissions, clone a repo |
| **Native sidecar** (GA v1.33) | helper that starts **before** the app, runs **for the pod's lifetime**, stops **after** it | `spec.initContainers[]` with `restartPolicy: Always` | log shipper, service-mesh proxy, secrets/config reloader, Job helpers |
| **Classic sidecar** | helper running **alongside** the app | a second entry in `spec.containers[]` | log tailer, content syncer (works on every version) |
| **Ambassador** | proxy that represents a **remote** service on `localhost` | a container (or native sidecar) the app talks to on localhost | DB proxy, sharding router, auth/TLS-terminating egress proxy |
| **Adapter** | converts the app's **output** to a standard format | a container reading the app's files or endpoints | log format → JSON, app stats → Prometheus format |

### Init containers in detail

- They run **one at a time, in order**. The next starts only after the previous one **exits 0**. App containers start only after all have succeeded.
- On failure the kubelet restarts the init container (back-off) **unless** the pod has `restartPolicy: Never`, in which case the whole pod fails. With pod `restartPolicy: Always`, init containers behave as `OnFailure`.
- Regular init containers do **not** support `lifecycle`, `livenessProbe`, `readinessProbe` or `startupProbe`.
- They re-run whenever the **pod** restarts (e.g. infra container restart), so make them **idempotent**.
- Resources: effective init request = the **max** over init containers. Pod request = max(sum of app + sidecar containers, effective init request).
- Pod `activeDeadlineSeconds` includes init time.
- Status while running: `Init:0/2`, `Init:1/2`, `Init:Error`, `Init:CrashLoopBackOff`, then `PodInitializing`, then `Running`.

### Native vs classic sidecar

| | Native sidecar (`initContainers` + `restartPolicy: Always`) | Classic sidecar (`containers`) |
|---|---|---|
| Availability | beta (on by default) v1.29, **GA v1.33** | always |
| Start order | started in `initContainers` order, **before** the app containers. The next container waits until the sidecar is *started*, or until its **startupProbe** succeeds | started together with the app (no guarantee) |
| Runs | for the whole pod life; restarted independently if it exits | for the whole pod life; restart follows the pod `restartPolicy` |
| Shutdown | stopped **after** all app containers exit, in **reverse** declaration order | receives SIGTERM at the **same time** as the app (may die first and lose the last logs) |
| Jobs | **does not block** Job completion | keeps the pod Running, so the Job **never completes** |
| Probes | startup, readiness, liveness supported; readiness counts toward pod Ready | all probes supported |
| `kubectl get pod` READY | counted (e.g. `2/2`) | counted |
| Changing its image | restarts that container only | restarts that container only |

### Startup and shutdown order (all features together)

```text
start:  init-1 -> init-2 (each must exit 0) -> sidecar-A started/startupProbe OK -> sidecar-B ...
        -> app containers start (in spec order, without waiting for each other*)
stop:   app containers get SIGTERM (preStop hooks first) -> exit
        -> native sidecars stopped in REVERSE order (B, then A)
        -> grace period expired? SIGKILL whatever is left (sidecar exit codes != 0 here are normal)
```

\* An app container's `postStart` hook delays the start of the **next** container in the list. This used to be a hack to order sidecars; native sidecars replace it.

Init and sidecar entries are interleaved exactly as you list them: an init container listed after a sidecar runs while that sidecar is already up (useful when the init container needs the proxy).

---

## Key fields / syntax

| File | Shows |
|---|---|
| [yaml/init-container.yaml](yaml/init-container.yaml) | two init containers: wait for a Service, then write content into a shared emptyDir |
| [yaml/sidecar-native.yaml](yaml/sidecar-native.yaml) | native sidecar with startupProbe + readinessProbe |
| [yaml/sidecar-classic-logging.yaml](yaml/sidecar-classic-logging.yaml) | classic log-tailing sidecar |
| [yaml/job-with-native-sidecar.yaml](yaml/job-with-native-sidecar.yaml) | a Job that completes despite a running sidecar |
| [yaml/ambassador.yaml](yaml/ambassador.yaml) | app → `localhost:8081` → nginx ambassador → remote Service |
| [yaml/adapter.yaml](yaml/adapter.yaml) | adapter converting `key=value` logs into JSON lines |
| [yaml/pod-shared-process-namespace.yaml](yaml/pod-shared-process-namespace.yaml) | `shareProcessNamespace: true` |

### Init container (prepare data, one-way hand-off through emptyDir)

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: web-init
spec:
  initContainers:
  - name: prepare
    image: busybox:1.36
    command: ["sh", "-c", "echo 'prepared by init' > /work/index.html"]
    volumeMounts:
    - name: html
      mountPath: /work
  containers:
  - name: web
    image: nginx:1.27
    volumeMounts:
    - name: html
      mountPath: /usr/share/nginx/html
  volumes:
  - name: html
    emptyDir: {}
```

Wait-for-dependency loops (use FQDNs with busybox `nslookup`, which can mishandle short names):

```bash
until nslookup mydb.$(cat /var/run/secrets/kubernetes.io/serviceaccount/namespace).svc.cluster.local; do echo waiting; sleep 2; done
until wget -q -T 2 -O /dev/null http://backend:80; do echo waiting; sleep 2; done   # waits for a READY backend, not just DNS
```

### Native sidecar

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: app-with-sidecar
spec:
  initContainers:
  - name: log-shipper
    image: busybox:1.36
    restartPolicy: Always            # <- makes it a sidecar
    command: ["sh", "-c", "tail -n +1 -F /var/log/app/app.log"]
    volumeMounts:
    - name: logs
      mountPath: /var/log/app
  containers:
  - name: app
    image: busybox:1.36
    command: ["sh", "-c", "while true; do date >> /var/log/app/app.log; sleep 5; done"]
    volumeMounts:
    - name: logs
      mountPath: /var/log/app
  volumes:
  - name: logs
    emptyDir: {}
```

### Classic sidecar (same pod, sidecar under `containers`)

```yaml
spec:
  containers:
  - name: app
    image: busybox:1.36
    command: ["sh", "-c", "while true; do date >> /var/log/app/app.log; sleep 5; done"]
    volumeMounts:
    - name: logs
      mountPath: /var/log/app
  - name: log-tailer
    image: busybox:1.36
    command: ["sh", "-c", "tail -n +1 -F /var/log/app/app.log"]
    volumeMounts:
    - name: logs
      mountPath: /var/log/app
  volumes:
  - name: logs
    emptyDir: {}
```

### Ambassador and adapter in one sentence each

- **Ambassador:** the app calls `localhost:8081`; the ambassador (nginx, envoy, a DB proxy) forwards to the real backend, which can be swapped per environment. See [yaml/ambassador.yaml](yaml/ambassador.yaml).
- **Adapter:** the app writes its own format; the adapter reads it (shared volume or localhost endpoint) and re-emits a standard format on stdout or an HTTP endpoint. See [yaml/adapter.yaml](yaml/adapter.yaml).

---

## Imperative commands

There is no generator for multi-container pods. Generate one container, then add the rest in vi:

```bash
kubectl run app --image=busybox:1.36 --dry-run=client -o yaml --command -- sh -c 'sleep 3600' > pod.yaml
kubectl create deployment app --image=busybox:1.36 --image=nginx:1.27 --dry-run=client -o yaml > d.yaml  # several --image = several containers
```

Working with containers inside a pod:

```bash
kubectl get pod app -o jsonpath='{.spec.initContainers[*].name}{" | "}{.spec.containers[*].name}{"\n"}'   # container names
kubectl logs app -c log-shipper                      # one container (init/sidecar names work too)
kubectl logs app -c log-shipper -f --tail=20         # follow
kubectl logs app --all-containers --prefix           # every container, lines prefixed with [pod/container]
kubectl logs app -c init-db --previous               # crashed init container's previous attempt
kubectl logs deploy/web -c sidecar                   # through the controller (picks one pod)
kubectl exec -it app -c app -- sh                    # shell in a specific container
kubectl exec app -c app -- cat /var/log/app/app.log  # read the shared file from the writer's side
kubectl describe pod app                             # "Init Containers:" section, states, restart counts
kubectl get pod app -o jsonpath='{range .status.initContainerStatuses[*]}{.name}{"="}{.ready}{" "}{end}{"\n"}'
kubectl debug -it app --image=busybox:1.36 --target=app   # temporary ephemeral container sharing app's PID namespace
```

Adding a container to an **existing** pod is not allowed (the container list is immutable): `kubectl edit`, then `kubectl replace --force -f /tmp/kubectl-edit-*.yaml`. For a Deployment, just edit the template (`kubectl edit deploy web`) and the rollout replaces the pods.

---

## Exam traps & tips

### Common exam tasks

| Task wording | What to do | Practice |
|---|---|---|
| "Add a container that makes the log file visible via `kubectl logs`" | sidecar running `tail -n +1 -F <file>` + shared emptyDir (classic, or native if ordering is required) | [Q12](practice-questions.md#q12-classic-logging-sidecar-for-an-existing-pod-keeping-its-name), [Q5](practice-questions.md#q5-add-a-native-sidecar-to-an-existing-deployment) |
| "Before the app starts, create/download/prepare file X" | init container writing into an emptyDir that the app mounts | [Q6](practice-questions.md#q6-init-container-prepares-the-content-nginx-serves) |
| "The pod must wait until service X is available" | init container with an `until ...; do sleep 2; done` loop | [yaml/init-container.yaml](yaml/init-container.yaml) |
| "The helper must start before / stop after the app" or "the Job must complete" | native sidecar (`initContainers` + `restartPolicy: Always`) | [Q22](practice-questions.md#q22-a-job-that-never-completes-make-its-sidecar-native) |
| "Convert the app's output to format Y" | adapter container reading the shared volume | [Q13](practice-questions.md#q13-adapter-container-that-converts-the-apps-output) |
| "The app connects to localhost:PORT; forward to service Z" | ambassador proxy container configured from a ConfigMap | [Q14](practice-questions.md#q14-ambassador-container-in-front-of-a-remote-service) |
| "Pod stuck in Init: find and fix" | `kubectl logs <pod> -c <init>`, fix the command, `replace --force` | [Q17](practice-questions.md#q17-fix-a-pod-stuck-in-initcrashloopbackoff) |
| "Add a sidecar to an existing pod and keep its name" | export, edit, `kubectl replace --force -f` | [Q12](practice-questions.md#q12-classic-logging-sidecar-for-an-existing-pod-keeping-its-name) |

> **Exam tip:** "The sidecar must start **before** the main container" or "must not prevent the Job from completing" means a **native sidecar**: put it under `initContainers` with `restartPolicy: Always`. A sidecar under `containers` satisfies neither.

> **Exam tip:** Without `-c`, `kubectl logs`/`exec` on a multi-container pod uses the **default container** (the first app container, or the one named in the annotation `kubectl.kubernetes.io/default-container`) and prints a hint. Always pass `-c <name>` in the exam.

> **Exam tip:** Both containers must mount the **same volume name**. The mount paths can differ. A typo in `volumeMounts[].name` is rejected; a different `mountPath` than expected silently "loses" the files.

> **Exam tip:** A pod stuck in `Init:0/1` waits for the first init container. Read **its** logs: `kubectl logs <pod> -c <init-name>`. `kubectl logs <pod>` alone shows the (not yet started) app container.

- Never add `restartPolicy: Always` to an init container that must **finish** (migration, file preparation). It turns it into a sidecar that never completes; the next init container then starts as soon as it is *started*, not after it has finished its work.
- Two containers listening on the same port crash: one gets `address already in use` (shared network namespace).
- A classic log sidecar using `tail -f` on a not-yet-existing file exits. Use `tail -F` (retry) or create the file first.
- Init containers cannot talk to the app containers (those have not started yet). Data passing is one-way, e.g. via `emptyDir`.
- Changing an init container's command on a running pod requires a recreate (only the `image` is mutable).

---

## Architect notes

- **Prefer native sidecars** for anything the app depends on at startup or shutdown (mesh proxies, auth agents, log shippers). They fix the two classic bugs: the app starting before the proxy, and the proxy dying before the app drains. They also make sidecars work in Jobs.
- **Every sidecar costs per pod:** CPU and memory requests are multiplied by the replica count. Measure them; consider node-level agents (DaemonSet) or ambient or sidecar-less mesh modes when the per-pod cost dominates.
- **Logging architecture:** best is stdout/stderr collected by a node agent (DaemonSet). Use a streaming sidecar only for apps that can only write files; avoid sidecars that ship logs straight to a backend from every pod.
- **Init containers as a security boundary:** do privileged setup (permissions, sysctls, iptables) in a short-lived init container so the long-running app container can stay unprivileged and non-root.
- **Keep init work bounded and idempotent:** add timeouts to wait loops, and consider readiness and backoff in the app itself instead of hard startup dependencies (it avoids cascading startup deadlocks).
- **Ambassador vs Service mesh:** a hand-rolled ambassador is fine for one dependency; at scale, a mesh or a client library gives retries, mTLS and telemetry consistently.
- **`shareProcessNamespace`** weakens isolation (processes and filesystems become visible across containers). Enable it only where needed; prefer `kubectl debug --target` for ad-hoc debugging.

---

## Docs to bookmark

- Init containers: <https://kubernetes.io/docs/concepts/workloads/pods/init-containers/>
- Configure pod initialization (example): <https://kubernetes.io/docs/tasks/configure-pod-container/configure-pod-initialization/>
- Debug init containers: <https://kubernetes.io/docs/tasks/debug/debug-application/debug-init-containers/>
- Sidecar containers: <https://kubernetes.io/docs/concepts/workloads/pods/sidecar-containers/>
- Adopting sidecar containers (tutorial): <https://kubernetes.io/docs/tutorials/configuration/pod-sidecar-containers/>
- Communicate between containers in the same pod using a shared volume: <https://kubernetes.io/docs/tasks/access-application-cluster/communicate-containers-same-pod-shared-volume/>
- Share process namespace: <https://kubernetes.io/docs/tasks/configure-pod-container/share-process-namespace/>
- Logging architecture (sidecar patterns): <https://kubernetes.io/docs/concepts/cluster-administration/logging/>
- Blog, native sidecars: <https://kubernetes.io/blog/2023/08/25/native-sidecar-containers/>

---

## Quick self-check

1. How do you declare a native sidecar, and what are three behavioural differences from a classic sidecar?
2. A pod is `Init:CrashLoopBackOff`. Which command shows the failure?
3. Pod `restartPolicy: Never` and the init container exits 1. What happens?
4. Which pattern fits "the app expects metrics in format A, the monitoring system scrapes format B"? And "the app should connect to `localhost:6379`, but Redis runs elsewhere"?
5. Why might a Job with a log-shipping container never complete, and what is the fix?
6. Can you add a sidecar to a running bare pod with `kubectl edit`?

<details><summary>Answers</summary>

1. As an entry in `spec.initContainers` with `restartPolicy: Always`. Differences: it starts before the app (gated by its startupProbe), it is stopped after the app containers in reverse order, and it does not block Job completion. It is also restarted independently.
2. `kubectl logs <pod> -c <init-container> --previous` (plus `kubectl describe pod <pod>` for the exit code and events).
3. The pod goes to `Failed`: no retry, and the app containers never start.
4. Adapter. Ambassador.
5. A classic sidecar in `containers` runs forever, so the pod never terminates and the Job never reaches its completions. Make the sidecar a native sidecar (`initContainers` + `restartPolicy: Always`). The Job's pod template is immutable, so recreate the Job.
6. No. The container list of a pod is immutable. Save the edited copy and use `kubectl replace --force -f`, or edit the owning controller's template instead.

</details>
