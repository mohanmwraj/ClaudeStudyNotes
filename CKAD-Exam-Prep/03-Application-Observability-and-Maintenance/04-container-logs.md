# Utilize Container Logs

**Why it matters:** logs are the first thing you read when an app misbehaves, and the exam asks for them directly: "write the logs of container `sidecar` in Pod `web` to `/opt/course/4/logs.txt`", "save the logs of the previous (crashed) instance", "find the error message and fix the app". You need every useful `kubectl logs` flag and to know which container's logs you are reading.

---

## Core concepts

### Logging architecture (node level)

```text
 app process --(stdout / stderr)--> container runtime (containerd / CRI-O)
                                        |  writes CRI-format lines
                                        v
   /var/log/pods/<namespace>_<pod>_<pod-uid>/<container>/<restart-count>.log        (on the node)
   /var/log/containers/<pod>_<namespace>_<container>-<container-id>.log  -> symlink to the file above
                                        ^
 kubectl logs --> kube-apiserver --> kubelet (reads the file) --'
```

- Only **stdout and stderr** are captured. A file the app writes inside the container (for example `/var/log/app.log`) is invisible to `kubectl logs`. Use the sidecar streaming pattern below.
- Each line is stored in CRI format: `<RFC3339Nano timestamp> <stdout|stderr> <F|P> <message>` (`P` = partial line). `kubectl logs` shows the message and, with `--timestamps`, the timestamp. stdout and stderr are interleaved in one stream. (Splitting the streams is an alpha feature since v1.32.)
- **Rotation is done by the kubelet**: `containerLogMaxSize` (default **10Mi**) and `containerLogMaxFiles` (default **5**) per container. `containerLogMaxWorkers` and `containerLogMonitorInterval` tune how rotation runs. **Only the latest log file is served by `kubectl logs`**: if the app wrote 40 MiB and rotation happens at 10 MiB, you get at most 10 MiB.
- **Retention:** after a restart the kubelet keeps **one** terminated container with its logs (`--previous`). Deleting or evicting the Pod deletes its logs, unless a cluster-level logging agent shipped them.
- Container logs live on the node's disk and count toward the Pod's ephemeral-storage usage.
- System components: the kubelet and container runtime log to journald on systemd hosts (`journalctl -u kubelet`). Control-plane static Pods are read with `kubectl logs -n kube-system kube-apiserver-<node>`. That is mostly CKA territory.

### Which container am I reading?

| Situation | Command |
|---|---|
| Single-container Pod | `kubectl logs web` |
| Multi-container Pod | `kubectl logs web -c sidecar`. Without `-c` kubectl uses the `kubectl.kubernetes.io/default-container` annotation or the first container, and prints `Defaulted container "app" out of: app, sidecar` |
| All containers of the Pod | `kubectl logs web --all-containers --prefix` |
| Init container (finished or failed) | `kubectl logs web -c init-db` |
| Native sidecar (`initContainers` + `restartPolicy: Always`) | `kubectl logs web -c log-shipper` |
| Ephemeral debug container | `kubectl logs web -c debugger-x7k2p` |
| Previous instance (after a crash/restart) | `kubectl logs web -p` (`--previous`), add `-c` as needed |
| One Pod of a workload | `kubectl logs deploy/web`, `kubectl logs job/report`, `kubectl logs sts/db` (kubectl picks one Pod) |
| All Pods of a workload | `kubectl logs deploy/web --all-pods` (kubectl v1.31+, implies `--prefix`) |
| All Pods matching a label | `kubectl logs -l app=web --prefix`. **Default `--tail=10` per Pod** with a selector |

### Every useful flag

| Flag | Meaning | Default / note |
|---|---|---|
| `-c, --container` | Pick the container | default container / first one |
| `--all-containers` | All containers in the Pod(s) | false |
| `-p, --previous` | Previous terminated instance of the container | errors if there is none |
| `-f, --follow` | Stream new lines | Ctrl-C to stop |
| `--since=1h` | Only lines newer than a relative duration (`5s`, `2m`, `3h`) | all |
| `--since-time=2026-10-17T08:00:00Z` | Only lines after an RFC3339 time | only one of since / since-time |
| `--tail=50` | Last N lines | `-1` (all); **10** when `-l` is used |
| `--timestamps` | Prefix each line with its RFC3339Nano timestamp | false |
| `-l, --selector` | Pods by label | `--max-log-requests` caps concurrent streams |
| `--prefix` | Prefix lines with `[pod/<name>/<container>]` | false |
| `--max-log-requests=10` | Max concurrent streams with `-l` / `-f` | 5 |
| `--all-pods` | All Pods of the given workload | v1.31+ |
| `--limit-bytes=500` | Cap the output size | no limit |
| `--pod-running-timeout=20s` | Wait for a Pod to be running | 20s |
| `--ignore-errors` | Keep following if a stream fails | false |
| `--insecure-skip-tls-verify-backend` | Ignore an expired kubelet serving cert | false |

---

## Key fields / syntax

### Sidecar log streaming (file → stdout)

When an app can only log to files, add a sidecar that tails the file from a shared `emptyDir` and prints it to its own stdout. Then `kubectl logs -c <sidecar>` and node-level agents can read it. Full file with classic and native variants: [yaml/logging-sidecar.yaml](yaml/logging-sidecar.yaml).

```yaml
# Native sidecar (GA v1.33): starts before the app, stops after it, never blocks Job completion
spec:
  initContainers:
  - name: log-streamer
    image: busybox:1.36
    restartPolicy: Always                  # makes it a sidecar
    command: ["sh", "-c", "tail -n+1 -F /var/log/app/app.log"]
    volumeMounts:
    - name: logs
      mountPath: /var/log/app
      readOnly: true
  containers:
  - name: app
    image: busybox:1.36
    command: ["sh", "-c", "while true; do echo \"$(date) INFO tick\" >> /var/log/app/app.log; sleep 2; done"]
    volumeMounts:
    - name: logs
      mountPath: /var/log/app
  volumes:
  - name: logs
    emptyDir: {}
```

- `tail -F` (capital F) keeps retrying until the file exists and follows rotation. `-n+1` starts from the first line.
- Classic variant: put the same container under `spec.containers`. It works everywhere, but its start/stop order is not guaranteed. Exam tasks that say "add a sidecar container" accept either unless they name one explicitly.
- Real-world variant: the [probes-all-in-one-deployment.yaml](yaml/probes-all-in-one-deployment.yaml) sidecar tails nginx's `access.log` (mounting an `emptyDir` over `/var/log/nginx` replaces the image's `/dev/stdout` symlinks with real files).

### Termination messages (when logs are not enough)

```yaml
containers:
- name: app
  image: busybox:1.36
  terminationMessagePolicy: FallbackToLogsOnError   # default: File (/dev/termination-log)
```

With `FallbackToLogsOnError`, if the container fails and wrote nothing to `/dev/termination-log`, the kubelet copies the **last log chunk** (up to 2048 bytes or 80 lines) into `status.containerStatuses[].lastState.terminated.message`. Messages are truncated at 4096 bytes per container.

```bash
kubectl get pod web -o jsonpath='{.status.containerStatuses[0].lastState.terminated.message}'
```

---

## Imperative commands

```bash
# Basic
kubectl logs web                                        # snapshot
kubectl logs web -c sidecar                             # one container
kubectl logs web --all-containers --prefix              # every container, lines prefixed
kubectl logs web -f --tail=20                           # follow, starting with the last 20 lines
kubectl logs web --since=10m --timestamps               # last 10 minutes with timestamps
kubectl logs web --since-time=2026-10-17T08:00:00Z

# Crashes and restarts
kubectl logs web -p                                     # previous instance (why it crashed)
kubectl logs web -c app --previous --tail=50

# Init containers / sidecars / debug containers: they are containers, so use -c
kubectl logs web -c init-db
kubectl logs web -c log-shipper

# Workloads and selectors
kubectl logs deploy/web                                 # one Pod of the Deployment
kubectl logs deploy/web --all-pods --tail=20            # every Pod of the Deployment (v1.31+)
kubectl logs deploy/web -c nginx
kubectl logs job/report                                 # first Pod of the Job
kubectl logs -l app=web --prefix --tail=100             # all matching Pods (default tail is 10!)
kubectl logs -l app=web -f --max-log-requests=10        # follow more than 5 Pods
kubectl logs -l batch.kubernetes.io/job-name=report     # every Pod of a Job (also label job-name=report)

# Save to files exactly as asked
mkdir -p /opt/course/4
kubectl logs web -c sidecar > /opt/course/4/sidecar.log
kubectl logs web -p > /opt/course/4/previous.log
kubectl logs web | grep -i error > /opt/course/4/errors.log
kubectl logs web --all-containers --prefix > /opt/course/4/all.log
kubectl logs -l app=web --tail=-1 --prefix > /opt/course/4/all-pods.log  # all lines, not just 10
wc -l /opt/course/4/*.log && head -3 /opt/course/4/sidecar.log            # verify

# Raw API (what kubectl does under the hood)
kubectl get --raw "/api/v1/namespaces/default/pods/web/log?container=sidecar&tailLines=5"
```

Messages you will meet:

| Message | Meaning | What to do |
|---|---|---|
| `Defaulted container "app" out of: app, sidecar` | You did not pass `-c` | Add `-c <name>` |
| `a container name must be specified for pod web, choose one of: [app sidecar]` | Ambiguous container (the API server's answer to raw API calls or old clients; current kubectl defaults instead) | Add `-c` or `--all-containers` |
| `previous terminated container "app" in pod "web" not found` | No restart has happened yet | Read the current logs |
| `container "web" in pod "x" is waiting to start: trying and failing to pull image` | The container never started, so there are no logs | `kubectl describe pod` / events |
| `container "app" in pod "x" is waiting to start: CreateContainerConfigError` | Config error before start | `describe`: missing ConfigMap/Secret/key |
| Empty output for a CrashLoopBackOff Pod | Current instance just (re)started | `kubectl logs -p` |

---

## Exam traps & tips

> **Exam tip:** with `-l` the default `--tail` is **10 lines per Pod**. If the task says "all logs", add `--tail=-1`.

> **Exam tip:** a CrashLoopBackOff container's useful output is in the **previous** instance: `kubectl logs <pod> -p`. The current one may be empty or just "starting...".

> **Exam tip:** redirect only stdout (`> file`). kubectl's own warnings, such as "Defaulted container", go to stderr and must not end up in the answer file. The app's stderr is already part of the log stream.

> **Exam tip:** init containers and native sidecars are read with `-c <name>`. `--all-containers` includes them.

> **Exam tip:** `kubectl logs deploy/web` reads **one** Pod. "Logs of all Pods of the Deployment" means `-l <selector>` (check it with `kubectl get deploy web -o jsonpath='{.spec.selector.matchLabels}'`) or `--all-pods`.

> **Exam tip:** Pods that never started (Pending, ImagePullBackOff, CreateContainerConfigError) have **no logs**. Go to `describe` and events.

---

## Architect notes (cluster-level logging)

- **Kubernetes stores no logs centrally.** The usual design is a **node-level agent DaemonSet** (Fluent Bit, Vector, the OpenTelemetry Collector or Fluentd). It tails `/var/log/containers/*.log`, enriches lines with Pod metadata (namespace, labels), and ships them to a backend (Loki, Elasticsearch/OpenSearch, a cloud logging service). Apps need no changes.
- **Streaming sidecars** are a bridge for apps that can only write files. They roughly double node disk use for those logs. **Agent-in-sidecar** (for example fluent-bit per Pod) is flexible but costly, and its output does not appear in `kubectl logs`. Prefer "log to stdout" plus a node agent.
- **Structured JSON logs** with request/trace IDs make logs joinable with traces and metrics. Agree a schema (timestamp, level, service, trace_id). Never log secrets or tokens.
- **Size rotation and retention deliberately.** Tune kubelet `containerLogMaxSize`/`containerLogMaxFiles` for chatty workloads. Logs fill node disks and can trigger DiskPressure evictions. Set log-volume quotas per tenant in the backend.
- **Events and audit logs are logs too.** Export Kubernetes events (1 h TTL) and API audit logs to the same platform for incident timelines and security investigations.
- **Termination messages** (`FallbackToLogsOnError`) give a crash reason in Pod status that survives log rotation and is easy to alert on.
- **`kubectl logs` is a debugging tool, not an archive.** Access goes through the `pods/log` subresource, so grant it deliberately in RBAC (it can expose sensitive data).

---

## Docs to bookmark

- Logging Architecture (node logging, rotation, sidecar patterns): https://kubernetes.io/docs/concepts/cluster-administration/logging/
- `kubectl logs` reference (all flags): https://kubernetes.io/docs/reference/kubectl/generated/kubectl_logs/
- Determine the reason for Pod failure (termination messages): https://kubernetes.io/docs/tasks/debug/debug-application/determine-reason-pod-failure/
- Debug Init Containers: https://kubernetes.io/docs/tasks/debug/debug-application/debug-init-containers/
- kubectl Quick Reference (logs section): https://kubernetes.io/docs/reference/kubectl/quick-reference/

---

## Quick self-check

1. A Pod is in CrashLoopBackOff and `kubectl logs` shows only "starting...". Where is the error message?
2. How do you save the logs of all Pods labelled `app=api`, every line, each prefixed with its Pod name?
3. An app writes to `/var/log/app/access.log` inside the container. Why is `kubectl logs` empty, and what is the standard fix?
4. Where on the node do container log files live, and who rotates them?
5. What does `kubectl logs deploy/api` return for a Deployment with 3 replicas?

<details><summary>Answers</summary>

1. In the previous instance: `kubectl logs <pod> --previous` (add `-c` for multi-container Pods).
2. `kubectl logs -l app=api --tail=-1 --prefix > file` (without `--tail=-1` you get only 10 lines per Pod).
3. Only stdout/stderr are captured. Write to stdout (for example symlink the file to `/dev/stdout`), or add a sidecar that runs `tail -F` on the file from a shared `emptyDir` and prints it to its own stdout.
4. `/var/log/pods/<ns>_<pod>_<uid>/<container>/N.log`, with symlinks in `/var/log/containers/`. The kubelet rotates them (`containerLogMaxSize` 10Mi, `containerLogMaxFiles` 5).
5. The logs of **one** of its Pods (chosen by kubectl). Use `-l <selector>` or `--all-pods` for all of them.

</details>
