# Implement Probes and Health Checks

**Why it matters:** probes are among the most frequently tested items. Typical tasks: "add a readiness probe that does an HTTP GET on `/ready` port 8080 every 5 s", "the Pod keeps restarting, fix its liveness probe", "protect a slow-starting app with a startup probe". You must write all handlers from memory, know the defaults, and know exactly what each probe does when it fails.

---

## Core concepts

### The three probes

| | startupProbe | livenessProbe | readinessProbe |
|---|---|---|---|
| Question | "Has the app finished starting?" | "Is the process still healthy (not deadlocked)?" | "Can it take traffic **right now**?" |
| Runs | From container start until its **first success**, then never again | After startup succeeded, for the whole container lifetime | After startup succeeded, for the whole container lifetime |
| On failure (after `failureThreshold`) | Container **killed**, then handled by `restartPolicy` | Container **killed**, then restarted per `restartPolicy` (Always/OnFailure → RESTARTS +1) | Container marked **not ready**. Pod `Ready=False`, no traffic from Services. **No restart.** |
| While running | Liveness and readiness are **disabled** until it succeeds | Independent of readiness (it does not wait for readiness) | Independent of liveness |
| `successThreshold` | must be 1 | must be 1 | may be > 1 |
| Typical handler | same endpoint as liveness, generous budget | cheap local check (`/healthz`, TCP port) | endpoint that knows whether the app can serve (`/ready`) |

- No probe configured = the kubelet treats the result as **Success**. A container without a readiness probe is Ready as soon as it is running.
- Before the first readiness check (during `initialDelaySeconds`) readiness counts as **Failure**: the Pod starts not ready.
- A probe result can be **Success**, **Failure** or **Unknown**. Unknown (the diagnostic itself failed) means no action; the kubelet just checks again.

```text
container started
   |
   |-- startupProbe defined? -- yes --> probe every periodSeconds until 1 success
   |                                     \-- failureThreshold failures --> kill --> restartPolicy
   v
startup OK (or no startupProbe)
   |-- livenessProbe  : whole lifetime; failureThreshold failures in a row --> kill + restart
   \-- readinessProbe : whole lifetime; failureThreshold failures   --> Ready=False, out of endpoints
                                        successThreshold successes --> Ready=True, back in endpoints
```

### Handlers (exactly one per probe)

| Handler | Success when | Fields | Notes |
|---|---|---|---|
| `httpGet` | HTTP status **200–399** | `path` (default `/`), `port` (number **or name**), `host` (default Pod IP), `scheme` (`HTTP` default / `HTTPS`), `httpHeaders` (list of name/value) | HTTPS **skips certificate verification**. Kubelet sends `User-Agent: kube-probe/<version>` and `Accept: */*`. Redirects are followed only to the same host. The body is read only up to 10 KiB. |
| `tcpSocket` | TCP connection can be opened | `port` (number or name), `host` | Only proves the port is open. The connection is made from the node, so a Service name cannot be used as `host`. |
| `exec` | command exits **0** | `command` (list) | Runs **inside** the container and is **not a shell**: use `["sh","-c","..."]` for pipes, `&&`, globs or `$VARS`. Forks processes on every run, which is costly at high Pod density. |
| `grpc` | response status `SERVING` | `port` (**number only**), `service` (optional) | Stable since v1.27. The app must implement the gRPC Health Checking Protocol. No named ports, no `host` field. |

> **Exam tip (v1.37):** `kubectl explain` on a v1.37 cluster also lists `httpGet.protocol` (`HTTP2` = h2c, gate `H2CContainerProbe`) and `grpc.mode` (`TLS`, gate `GRPCContainerProbeTLS`). Both are **alpha and disabled by default**: the API server silently drops them unless the gates are enabled. Don't use them in exam answers.

### Timing fields and defaults

| Field | Default | Min | Meaning |
|---|---|---|---|
| `initialDelaySeconds` | 0 | 0 | Wait after container start before the first probe. Liveness/readiness delays begin only after the startup probe succeeded. |
| `periodSeconds` | 10 | 1 | How often to probe. (While a container is not Ready, readiness may be probed more often, to get Ready faster.) |
| `timeoutSeconds` | 1 | 1 | Probe call timeout. Applies to exec probes too. |
| `successThreshold` | 1 | 1 | Consecutive successes needed after a failure. **Must be 1 for liveness and startup.** |
| `failureThreshold` | 3 | 1 | Consecutive failures before the probe "fails" (kill for liveness/startup, unready for readiness) |
| `terminationGracePeriodSeconds` (probe-level) | inherits the Pod's (30 s if unset) | 1 | Grace period used when **this** probe kills the container. Liveness/startup only (stable v1.28). **Rejected on readiness probes.** |

**Formulas you will be asked to apply:**

| What | Formula | Example |
|---|---|---|
| Maximum startup time allowed by a startupProbe | `initialDelaySeconds + failureThreshold × periodSeconds` | `failureThreshold: 30`, `periodSeconds: 10` → 300 s (the official docs example) |
| `failureThreshold` for "allow up to N s of startup" | `ceil(N / periodSeconds)` | 2 min with period 10 s → `failureThreshold: 12` |
| Time from "app hangs" to "container killed" (liveness) | ≈ `failureThreshold × periodSeconds` (+ timeouts) + grace period | defaults: ~30 s + up to 30 s grace |
| Time until unready Pod leaves the endpoints (readiness) | ≈ `failureThreshold × periodSeconds` | `failureThreshold: 2`, `periodSeconds: 5` → ~10 s |

> **Exam tip:** "the app may take up to 3 minutes to start, probe every 10 s" → `startupProbe` with `periodSeconds: 10` and `failureThreshold: 18`. Do not "solve" slow starts with a huge `initialDelaySeconds` on the liveness probe: that delays crash detection on every restart.

### Readiness vs. Service endpoints (how to observe it)

When readiness fails, the **EndpointSlice controller** marks the Pod's endpoint `conditions.ready: false` in every matching Service's EndpointSlices. The docs describe this as removing the Pod's IP from the Service; the address stays listed, but kube-proxy and ingress controllers stop sending it traffic.

```bash
kubectl get pods -l app=readiness-exec                       # READY 0/1 vs 1/1
kubectl get endpointslices -l kubernetes.io/service-name=readiness-exec-svc \
  -o jsonpath='{range .items[*].endpoints[*]}{.addresses[0]}{"  ready="}{.conditions.ready}{"\n"}{end}'
# 10.244.1.12  ready=false
kubectl describe svc readiness-exec-svc | grep Endpoints     # kubectl describe lists READY endpoints only
kubectl get events --field-selector reason=Unhealthy         # "Readiness probe failed: ..."
```

> **Exam tip:** the ENDPOINTS column of `kubectl get endpointslices` lists **all** addresses, including not-ready ones. Check `conditions.ready`, or use `kubectl describe svc`, which shows only ready endpoints. (The deprecated `kubectl get endpoints` also shows only ready addresses.)

Lab: [yaml/probe-readiness-exec.yaml](yaml/probe-readiness-exec.yaml) lets you toggle readiness with `rm` / `touch /tmp/ready` and watch the endpoint flip without a restart.

### Pod readiness gates (brief)

```yaml
spec:
  readinessGates:
  - conditionType: "example.com/load-balancer-registered"
```

- The Pod is Ready only when **all containers are ready AND every listed condition in `status.conditions` is `True`**. A missing condition counts as `False`.
- An external controller (typically a cloud load-balancer controller) sets the condition through the Pod status API. When containers are ready but a gate is not, the Pod has `ContainersReady=True` and `Ready=False`. `kubectl get pod -o wide` shows a READINESS GATES column such as `0/1`.

### Probes on sidecars and init containers

| Container type | Probes allowed? | Effect |
|---|---|---|
| Regular init container | **No.** Validation rejects liveness/readiness/startup probes on init containers without `restartPolicy: Always` | Must simply run to completion |
| **Native sidecar** (`initContainers` + `restartPolicy: Always`, GA v1.33) | Yes, all three | **startupProbe** gates the start of the next init container and of the app containers (the sidecar counts as "started" once it succeeds). **readinessProbe** result is used for the Pod's Ready state. **livenessProbe** restarts only the sidecar. |
| Classic sidecar (2nd entry in `containers`) | Yes | Behaves like any app container: its readiness is part of Pod readiness, and its liveness restarts only that container |

> **Exam tip:** a sidecar with a failing readiness probe takes the **whole Pod** out of the Service, even though the app container is fine. If READY shows `1/2`, check every container's `ready` flag: `kubectl get pod x -o jsonpath='{range .status.containerStatuses[*]}{.name}={.ready}{" "}{end}'` (native sidecars are listed under `.status.initContainerStatuses`).

### Probe design rules (production)

1. **Liveness checks only the process itself.** Never check a database or downstream API in liveness. A dependency outage would restart every replica at once and cause a cascading failure.
2. **Readiness may check what the Pod needs to serve.** If every replica fails readiness at the same time, the Service has zero endpoints, so prefer degraded responses for non-critical dependencies.
3. **Use a startupProbe for slow or variable starts** instead of a large liveness `initialDelaySeconds`.
4. **Liveness should be more tolerant than readiness.** The same cheap endpoint with a higher `failureThreshold` means the Pod is pulled from rotation before it is killed.
5. **Respect `timeoutSeconds`.** The 1 s default is aggressive for JVMs, GC pauses and CPU-throttled containers, and false liveness failures cause restart storms. Tune it, and avoid tight CPU limits on latency-sensitive apps.
6. **Prefer httpGet/tcpSocket/grpc over exec** at high density, because exec forks processes on every probe.
7. **Health endpoints must be cheap**: no auth, no heavy queries, small bodies. The kubelet stops reading after 10 KiB.
8. **Listen on the Pod IP.** HTTP/TCP probes go to the Pod IP, so an app bound to `127.0.0.1` fails them.
9. **Graceful shutdown needs no readiness trick.** On deletion the endpoint becomes not ready automatically. Add a short `preStop` sleep so load balancers catch up before the process exits.

---

## Key fields / syntax

```yaml
# httpGet: liveness on a named port with a custom header
livenessProbe:
  httpGet:
    path: /healthz
    port: http                 # containerPort name, or a number
    scheme: HTTP               # or HTTPS (no cert verification)
    httpHeaders:
    - name: X-Probe
      value: liveness
  initialDelaySeconds: 5
  periodSeconds: 10
  timeoutSeconds: 2
  failureThreshold: 3
```

```yaml
# exec: readiness (not a shell -> wrap in sh -c when you need shell features)
readinessProbe:
  exec:
    command: ["sh", "-c", "test -f /tmp/ready && grep -q ok /tmp/ready"]
  periodSeconds: 5
  successThreshold: 2          # allowed for readiness only
```

```yaml
# tcpSocket: liveness for a non-HTTP server
livenessProbe:
  tcpSocket:
    port: 6379
  initialDelaySeconds: 15
  periodSeconds: 20
```

```yaml
# grpc: number-only port, optional service name
readinessProbe:
  grpc:
    port: 9090
    service: readiness         # optional; the server must report this service name (omit = whole server)
  periodSeconds: 5
```

```yaml
# startupProbe + liveness sharing one endpoint (the official docs pattern)
startupProbe:
  httpGet:
    path: /healthz
    port: liveness-port
  failureThreshold: 30         # 30 x 10s = 300s to start
  periodSeconds: 10
livenessProbe:
  httpGet:
    path: /healthz
    port: liveness-port
  failureThreshold: 1
  periodSeconds: 10
  terminationGracePeriodSeconds: 60   # probe-level override (liveness/startup only)
```

Complete, runnable files:

| File | Shows |
|---|---|
| [yaml/probe-liveness-http.yaml](yaml/probe-liveness-http.yaml) | httpGet liveness, named port, header, every timing field |
| [yaml/probe-readiness-exec.yaml](yaml/probe-readiness-exec.yaml) | exec readiness + Service; toggle readiness and watch endpoints |
| [yaml/probe-tcp.yaml](yaml/probe-tcp.yaml) | tcpSocket readiness/liveness on Redis |
| [yaml/probe-startup.yaml](yaml/probe-startup.yaml) | startupProbe budget for a 30 s start |
| [yaml/probe-grpc.yaml](yaml/probe-grpc.yaml) | gRPC liveness/readiness (etcd, docs example) |
| [yaml/probes-all-in-one-deployment.yaml](yaml/probes-all-in-one-deployment.yaml) | All three probes + probe-level grace period + native sidecar with probes |
| [yaml/broken/wrong-probe-pod.yaml](yaml/broken/wrong-probe-pod.yaml) | Wrong port + wrong path, to diagnose and fix |

---

## Imperative commands

kubectl has **no flag or `set` subcommand for probes** (`set probe` exists only in OpenShift's `oc`). Generate the skeleton, then add the probe in vim:

```bash
# Pod skeleton
kubectl run web --image=nginx:1.27 --port=80 --dry-run=client -o yaml > web-pod.yaml
# Deployment skeleton
kubectl create deployment web --image=nginx:1.27 --port=80 --replicas=2 --dry-run=client -o yaml > web-deploy.yaml
vim web-deploy.yaml            # add livenessProbe/readinessProbe under the container
kubectl apply -f web-deploy.yaml

# Field reference without leaving the terminal
kubectl explain pod.spec.containers.livenessProbe
kubectl explain pod.spec.containers.readinessProbe.httpGet
kubectl explain pod.spec.containers.startupProbe --recursive
```

Add a probe to an **existing Deployment** (rolls out a new ReplicaSet):

```bash
kubectl edit deployment web                               # interactive

# strategic-merge patch: containers are merged by name
kubectl patch deployment web -p '{"spec":{"template":{"spec":{"containers":[{"name":"nginx","readinessProbe":{"httpGet":{"path":"/","port":80},"initialDelaySeconds":5,"periodSeconds":10}}]}}}}'

# JSON patch by index
kubectl patch deployment web --type=json -p='[{"op":"add","path":"/spec/template/spec/containers/0/livenessProbe","value":{"tcpSocket":{"port":80},"periodSeconds":20}}]'
kubectl rollout status deployment web
```

Add or fix a probe on a **bare Pod** (probes are immutable on a running Pod):

```bash
kubectl edit pod web          # save -> rejected; kubectl stores your copy in /tmp/kubectl-edit-XXXX.yaml
kubectl replace --force -f /tmp/kubectl-edit-XXXX.yaml    # deletes and recreates the Pod
# or: kubectl get pod web -o yaml > web.yaml; vim web.yaml; kubectl replace --force -f web.yaml
```

Inspect and verify:

```bash
kubectl describe pod web | grep -E 'Liveness|Readiness|Startup'        # effective probe settings
kubectl get pod web -o jsonpath='{.spec.containers[0].livenessProbe}{"\n"}'
kubectl get events --field-selector involvedObject.name=web,reason=Unhealthy
kubectl get pod web -o jsonpath='{.status.containerStatuses[0].restartCount}{"\n"}'
kubectl get pod web -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}{"\n"}'
```

---

## Fixing broken probes

| Symptom in `describe` / events | Likely cause | Fix |
|---|---|---|
| `Liveness probe failed: Get "http://10.244.1.7:8080/": dial tcp 10.244.1.7:8080: connect: connection refused` then `Container web failed liveness probe, will be restarted` | Wrong port, app not listening yet, or app bound to 127.0.0.1 | Correct `port` (or the named port). Add a startupProbe if the app is just slow |
| `Readiness probe failed: HTTP probe failed with statuscode: 404` | Wrong `path` | Correct the path (`/`, `/healthz`, `/ready` ...) |
| `... statuscode: 503` / `500` | App really unhealthy or a dependency is down | Fix the app or dependency. Reconsider what the probe checks |
| `... context deadline exceeded (Client.Timeout exceeded while awaiting headers)` | Endpoint slower than `timeoutSeconds` (default 1 s) | Raise `timeoutSeconds`, make the endpoint cheaper |
| `Liveness probe failed: cat: can't open '/tmp/healthy': No such file or directory` | Exec probe checks a file that isn't there | Create the file / fix the path or command |
| Exec probe with `\|`, `&&`, `*` or `$VAR` always fails | `command` is not run in a shell | `command: ["sh", "-c", "..."]` |
| Restarts right after start; logs show the app was still booting | Liveness starts too early | Add a startupProbe (or `initialDelaySeconds`) |
| `Startup probe failed ...` then `failed startup probe, will be restarted` in a loop | Startup budget shorter than the real start time | Raise `failureThreshold × periodSeconds` |
| HTTP probe against an HTTPS port fails (often status 400) | Scheme mismatch | `scheme: HTTPS` |
| `Running` but READY `0/1`, no probe failures | A readiness gate or a sidecar is not ready | `kubectl get pod -o wide` (READINESS GATES), per-container `ready` flags |
| API rejects the Pod: `must be 1` / readiness `terminationGracePeriodSeconds` forbidden | `successThreshold > 1` on liveness/startup, or a probe-level grace period on readiness | Use `successThreshold: 1`; remove the grace period from readiness |

Practice file: [yaml/broken/wrong-probe-pod.yaml](yaml/broken/wrong-probe-pod.yaml).

---

## Exam traps & tips

> **Exam tip:** read the numbers in the task twice: port **number vs name**, path, `initialDelaySeconds` vs `periodSeconds`. Graders check the exact values.

> **Exam tip:** the probe goes under the **container** (`spec.containers[].livenessProbe`), not under `spec`. In a Deployment it is `spec.template.spec.containers[]`. kubectl's default strict field validation rejects a probe at the wrong level (`unknown field`), but a probe placed under the **wrong container** is valid and silently probes the wrong thing. Verify with `kubectl get ... -o jsonpath`.

> **Exam tip:** a readiness failure **never** restarts the container. If a task says "the container should be restarted when ...", it is a liveness probe.

> **Exam tip:** a named port in a probe must exist in that container's `ports[].name`. gRPC probes cannot use names at all.

> **Exam tip:** changing probes on a bare Pod needs a recreate (`kubectl replace --force -f`). On a Deployment, editing the template triggers a rollout. Wait for `kubectl rollout status` before checking.

> **Exam tip:** for an exec probe on a file such as `/tmp/healthy`, make sure the container command creates it, or the probe fails forever.

---

## Architect notes

- **Probes are part of your SLO design.** Readiness controls who receives traffic. Liveness is a last-resort self-healing hammer. Wrong liveness probes are a classic cause of outages that spread across all replicas.
- **Separate endpoints:** `/livez` (process alive, no dependencies), `/readyz` (able to serve, includes critical dependencies and warm-up), and startup handled by a startupProbe on `/livez` with a generous budget.
- **Capacity under load:** an overloaded Pod that fails liveness gets restarted, which removes capacity and overloads the rest. Prefer readiness shedding plus HPA over aggressive liveness thresholds.
- **Rolling updates depend on readiness.** Without a readiness probe a new Pod counts as available as soon as it starts, and `maxUnavailable`/`minReadySeconds` cannot protect you. Readiness plus `minReadySeconds` gives safe rollouts.
- **Probe-level `terminationGracePeriodSeconds`** lets a stuck container be killed quickly (for example 10 s) while normal shutdowns keep a long Pod-level grace period for draining.
- **Sidecars (service mesh, log shippers) need probes too.** Native sidecars' startup probes guarantee the proxy is up before the app starts. Their readiness feeds Pod readiness.
- **Observe probe health.** Alert on `Unhealthy` events and on restart rates (`kube_pod_container_status_restarts_total` in kube-state-metrics) rather than discovering restart loops by accident.
- **gRPC services:** use native `grpc` probes (stable v1.27) instead of shipping `grpc-health-probe` binaries for exec probes.

---

## Docs to bookmark

- Configure Liveness, Readiness and Startup Probes (task, examples): https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/
- Liveness, Readiness, and Startup Probes (concepts, all fields): https://kubernetes.io/docs/concepts/configuration/liveness-readiness-startup-probes/
- Pod Lifecycle: container probes, Pod conditions, readiness gates: https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/
- Sidecar containers (probes on sidecars): https://kubernetes.io/docs/concepts/workloads/pods/sidecar-containers/
- Probe API reference: https://kubernetes.io/docs/reference/kubernetes-api/workload-resources/pod-v1/#Probe

---

## Quick self-check

1. A readiness probe fails 3 times in a row. What happens to the container and to the Service?
2. You need to allow an app up to 150 s to start, probing every 5 s. Which probe and which `failureThreshold`?
3. Why does `exec: command: ["cat /tmp/ready | grep ok"]` always fail?
4. Which probe fields are invalid for a liveness probe: `successThreshold: 3`, `terminationGracePeriodSeconds: 10`, `timeoutSeconds: 5`?
5. Can you reference a named port in a gRPC probe?
6. A Pod with an app container and a native sidecar shows READY `1/2`. The app is healthy. What should you check?

<details><summary>Answers</summary>

1. The container keeps running (no restart). The Pod's Ready condition becomes False and its endpoint is marked `ready: false` in the Service's EndpointSlice, so it gets no traffic until the probe succeeds again (`successThreshold` times).
2. A `startupProbe` with `periodSeconds: 5` and `failureThreshold: 30` (150 / 5).
3. exec does not use a shell. The whole string is treated as one executable name. Use `["sh", "-c", "cat /tmp/ready | grep ok"]`.
4. `successThreshold: 3` is invalid (must be 1 for liveness/startup). The probe-level grace period and `timeoutSeconds: 5` are valid.
5. No. gRPC probes take a numeric `port` only (and no `host`).
6. The sidecar's readiness probe and status (`.status.initContainerStatuses[*].ready` for a native sidecar). A sidecar's readiness counts toward Pod readiness.

</details>
