# Autoscaling: HorizontalPodAutoscaler (plus VPA, KEDA, node autoscalers)

**Why it matters / what the exam expects:** the HPA is not named in the CKAD curriculum, but "autoscale deployment X between 2 and 5 replicas at 70 % CPU" is a one-minute task that candidates report, and an `autoscaling/v2` manifest with `behavior` is a plausible follow-up. The classic traps are a missing metrics-server, missing CPU requests and the **kubectl flag change** (`--cpu-percent` → `--cpu`; the exam's kubectl v1.37 uses `--cpu=70%`). Frequency: `kubectl autoscale` ⚡, behavior/VPA/KEDA 🧊.

> Conventions: `alias k=kubectl`, `export do="--dry-run=client -o yaml"`.

---

## Core concepts

### How the HPA works

```text
every 15 s (kube-controller-manager --horizontal-pod-autoscaler-sync-period)
  read metrics  ->  metrics.k8s.io (metrics-server) for cpu/memory
                     custom.metrics.k8s.io / external.metrics.k8s.io via an adapter (Prometheus Adapter, KEDA, ...)
  desiredReplicas = ceil( currentReplicas * currentMetricValue / targetValue )
  several metrics -> compute each, take the HIGHEST
  clamp to [minReplicas, maxReplicas], apply behavior (rate limits, stabilization)
  write spec.replicas of the target through its /scale subresource
```

Example: 4 replicas at 90 % average CPU with a 60 % target → `ceil(4 × 90 / 60) = 6`. No scaling while the ratio is within the **10 % tolerance** (0.9-1.1).

| Item | Detail |
|---|---|
| API | `autoscaling/v2` (stable since v1.23). `autoscaling/v1` is still served but CPU-only (`targetCPUUtilizationPercentage`). `v2beta1` was removed in v1.25, `v2beta2` in v1.26 |
| Scalable targets | Deployment, StatefulSet, ReplicaSet, any custom resource with a `scale` subresource - **not** DaemonSets |
| `minReplicas` / `maxReplicas` | min optional (default 1), max required |
| Ownership | once an HPA exists it owns `spec.replicas`; `k scale` gets overwritten on the next sync |

### Requirements (the usual reasons for `<unknown>`)

| Requirement | Check | Symptom when missing |
|---|---|---|
| metrics-server (or another `metrics.k8s.io` provider) | `k top pods` works; `k get apiservices v1beta1.metrics.k8s.io` is Available | TARGETS `<unknown>`; events like `failed to get cpu utilization: unable to get metrics for resource cpu` |
| **Requests** on every container of the target (for `Utilization`) | `k get deploy web -o jsonpath='{.spec.template.spec.containers[*].resources}'` | `<unknown>`; event `failed to get cpu utilization: missing request for cpu ...` |
| Ready pods | `k get pods` | unready/starting pods are treated conservatively (initialization periods) |

### Metric types and target types

| `metrics[].type` | Source | Allowed target types |
|---|---|---|
| `Resource` | cpu/memory of the whole pod (sum of containers) | `Utilization` (% of requests), `AverageValue` |
| `ContainerResource` | cpu/memory of **one named container** (ignore the sidecar) - GA since v1.30 | `Utilization`, `AverageValue` |
| `Pods` | a per-pod custom metric (e.g. `http_requests_per_second`) | `AverageValue` |
| `Object` | a metric of another object (e.g. Ingress requests) | `Value`, `AverageValue` |
| `External` | a metric outside the cluster (queue length, cloud monitoring) | `Value`, `AverageValue` |

| Target type | Field | Meaning | Needs requests? |
|---|---|---|---|
| `Utilization` | `averageUtilization: 70` | average usage as **% of the request** | **yes** |
| `AverageValue` | `averageValue: 500m` / `200Mi` | absolute average per pod | no |
| `Value` | `value: "100"` | total value of an Object/External metric | no |

---

## Key fields / syntax

### CPU utilization HPA ([yaml/hpa-cpu.yaml](yaml/hpa-cpu.yaml))

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: hpa-demo
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: hpa-demo
  minReplicas: 1
  maxReplicas: 5
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 50
```

### Memory as an absolute value, and one container only

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: api-mem
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: api
  minReplicas: 2
  maxReplicas: 8
  metrics:
  - type: Resource
    resource:
      name: memory
      target:
        type: AverageValue
        averageValue: 300Mi           # absolute per-pod average
  - type: ContainerResource
    containerResource:
      name: cpu
      container: httpd                # only this container counts (sidecars ignored)
      target:
        type: Utilization
        averageUtilization: 60
```

This is an alternative to the HPA in [yaml/hpa-behavior.yaml](yaml/hpa-behavior.yaml) for the same Deployment - never attach two HPAs to one target (they fight; the status reports `AmbiguousSelector`).

### Behavior ([yaml/hpa-behavior.yaml](yaml/hpa-behavior.yaml))

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: api
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: api
  minReplicas: 2
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
  behavior:
    scaleUp:
      stabilizationWindowSeconds: 0     # react at once
      selectPolicy: Max                 # the policy allowing the biggest change wins
      policies:
      - type: Percent
        value: 100
        periodSeconds: 15
      - type: Pods
        value: 4
        periodSeconds: 15
    scaleDown:
      stabilizationWindowSeconds: 300   # use the highest recommendation of the last 5 min
      selectPolicy: Min                 # the policy allowing the smallest change wins
      policies:
      - type: Pods
        value: 1
        periodSeconds: 60
```

| Field | Meaning | Default |
|---|---|---|
| `policies[].type` | `Pods` (absolute count) or `Percent` (of current replicas) | - |
| `policies[].periodSeconds` | window the policy applies to (max 1800) | - |
| `selectPolicy` | `Max` (biggest change), `Min` (smallest change), `Disabled` (never scale in this direction) | `Max` |
| `stabilizationWindowSeconds` | look back this long and use the most conservative recommendation (max 3600) | up: `0`, down: `300` |
| Defaults when `behavior` is omitted | scale-up: max(100 % or 4 pods) per 15 s, no stabilization; scale-down: 100 % per 15 s after a 300 s window | - |
| `tolerance` (per direction, e.g. `behavior.scaleUp.tolerance: 0.05`) | custom tolerance instead of the global 10 %: introduced as alpha in v1.33 (feature gate `HPAConfigurableTolerance`), **stable in v1.37** (the exam version) - on older clusters check the feature state first | 10 % |

To freeze scale-down temporarily: `behavior.scaleDown.selectPolicy: Disabled` (or set `minReplicas` = `maxReplicas`).

---

## Imperative commands

### `kubectl autoscale` (check your version first)

```bash
k version --client                 # kubectl minor version decides the flag
k autoscale -h | grep -E -- '--cpu|--memory'

# kubectl v1.34 and newer
k autoscale deploy web --min=2 --max=5 --cpu=70%                 # Utilization target
k autoscale deploy web --min=2 --max=5 --cpu=500m                # AverageValue target (500 millicores)
k autoscale deploy web --min=2 --max=8 --cpu=60% --memory=70%    # two metrics
k autoscale deploy web --min=3 --max=6 --cpu=500m --memory=200Mi

# kubectl v1.33 and older (flag deprecated since v1.34: still accepted, prints a warning, hidden from --help)
k autoscale deploy web --min=2 --max=5 --cpu-percent=70

# generate YAML instead of creating, e.g. to add behavior
k autoscale deploy web --min=2 --max=5 --cpu=70% $do > hpa.yaml
k autoscale deploy web --max=5 --name=web-hpa                    # custom HPA name (default = target name)
```

`--cpu-percent` and `--cpu` are mutually exclusive. kubectl creates an `autoscaling/v2` object (it falls back to v1 only if v2 is unavailable). Generated YAML (trimmed):

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: web
spec:
  maxReplicas: 5
  minReplicas: 2
  metrics:
  - resource:
      name: cpu
      target:
        averageUtilization: 70
        type: Utilization
    type: Resource
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: web
```

### Observe and debug

```bash
k get hpa                          # NAME REFERENCE TARGETS MINPODS MAXPODS REPLICAS AGE
k get hpa web -w                   # watch TARGETS (e.g. "cpu: 12%/70%"; older API servers print just "12%/70%") and REPLICAS
k describe hpa web                 # Metrics, Conditions (AbleToScale, ScalingActive, ScalingLimited), Events
k get hpa web -o jsonpath='{.status.currentReplicas}{" -> "}{.status.desiredReplicas}{"\n"}'
k top pods -l app=web              # what the HPA sees (needs metrics-server)
k get apiservices v1beta1.metrics.k8s.io   # metrics API available?
k get --raw /apis/metrics.k8s.io/v1beta1/namespaces/default/pods | head -c 400; echo
k delete hpa web                   # replicas stay at the last value
```

### Load-generation test (lab)

```bash
k apply -f yaml/hpa-cpu.yaml
k run load --rm -it --image=busybox:1.36 --restart=Never -- \
  sh -c 'while true; do wget -q -O- http://hpa-demo >/dev/null; done'     # terminal 1 (Ctrl-C to stop)
k get hpa hpa-demo -w                                                      # terminal 2 (second window or tmux pane)
# expect TARGETS to rise above 50 % and REPLICAS to grow; after stopping the load,
# replicas shrink only after the 300 s scale-down stabilization window
```

The official walkthrough uses a dedicated CPU-burning image (`registry.k8s.io/hpa-example`); with nginx you may need two or three load pods.

### metrics-server in a practice lab

```bash
k apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
# kind/kubeadm labs with self-signed kubelet certificates also need:
k -n kube-system patch deploy metrics-server --type=json \
  -p '[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'
k -n kube-system rollout status deploy/metrics-server
k top nodes
# minikube: minikube addons enable metrics-server
```

Lab setup in general: [00-Exam-Overview-and-Setup](../00-Exam-Overview-and-Setup/README.md).

---

## Beyond the HPA (architect overview)

### Vertical Pod Autoscaler (VPA) - add-on, `autoscaling.k8s.io/v1`

```yaml
apiVersion: autoscaling.k8s.io/v1
kind: VerticalPodAutoscaler
metadata:
  name: web-vpa
spec:
  targetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: web
  updatePolicy:
    updateMode: "Off"          # quoted! unquoted Off is a YAML boolean (see 07)
  resourcePolicy:
    containerPolicies:
    - containerName: "*"
      minAllowed:
        cpu: 50m
        memory: 64Mi
      maxAllowed:
        cpu: "1"
        memory: 1Gi
```

| `updateMode` | Effect |
|---|---|
| `Off` | only computes recommendations (`k describe vpa`) - the safe way to right-size requests |
| `Initial` | sets requests when pods are created, never changes running pods |
| `Recreate` | evicts pods whose requests differ significantly (respects PDBs) |
| `InPlaceOrRecreate` | tries an in-place resize first, falls back to eviction (newer VPA releases) |
| `InPlace` | in-place only, never evicts (newest VPA releases) |
| `Auto` | deprecated; currently behaves like `Recreate` |

Do not let HPA and VPA act on the **same** CPU/memory signal - they fight. Common pattern: VPA in `Off`/`Initial` mode for sizing, HPA on CPU or on custom metrics for scaling.

### KEDA - event-driven autoscaling (CNCF graduated)

```yaml
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: worker
spec:
  scaleTargetRef:
    name: worker               # Deployment name
  minReplicaCount: 0           # scale to zero when idle
  maxReplicaCount: 20
  triggers:
  - type: prometheus
    metadata:
      serverAddress: http://prometheus.monitoring.svc:9090
      query: 'sum(rate(http_requests_total{app="worker"}[1m]))'
      threshold: "50"
```

KEDA creates and manages an HPA (`keda-hpa-<name>`) and feeds it external metrics (queues, Kafka lag, cron, Prometheus, cloud services). It handles 0 ↔ 1 itself; `ScaledJob` starts Jobs per event. Native HPA scale-to-zero (`minReplicas: 0`) is beta and on by default in v1.37 (`HPAScaleToZero`), but only together with at least one Object or External metric - which needs a metrics adapter - so CPU/memory HPAs still need `minReplicas >= 1`. Unlikely in an exam task; KEDA remains the common production route.

### Node autoscaling

| Tool | How it works | Notes |
|---|---|---|
| Cluster Autoscaler | grows/shrinks pre-defined node groups (ASG, MIG, VMSS) when pods are Pending for lack of resources / nodes are underused | respects PDBs and `cluster-autoscaler.kubernetes.io/safe-to-evict`; mature, multi-cloud |
| Karpenter | provisions right-sized nodes directly from pending pods' requirements (no fixed groups), consolidates under-used nodes | `NodePool`/`NodeClaim` CRDs; strongest on AWS, also Azure; part of SIG Autoscaling |

Chain of events in production: load ↑ → HPA adds pods → pods Pending → node autoscaler adds nodes → pods start. Scale-out latency = HPA sync + node boot + image pull + readiness.

### Relation to in-place pod resize

In-place resize of container CPU/memory (`k patch pod web --subresource resize -p '{"spec":{"containers":[{"name":"web","resources":{"requests":{"cpu":"800m"}}}]}}'`, kubectl ≥ v1.32) is beta and on by default in v1.33 and **GA in v1.35**. It changes requests/limits of a running pod without recreating it (per-container `resizePolicy`: `NotRequired` or `RestartContainer`). That is *vertical* scaling - VPA's `InPlaceOrRecreate` mode uses it; the HPA keeps scaling *horizontally*. The details belong to resource management ([04 chapter](../04-Application-Environment-Configuration-and-Security/README.md)).

---

## Exam traps & tips

> **Exam tip:** the exam runs v1.37, so write `--cpu=70%`; `--cpu-percent=70` still works there but prints a deprecation warning. Only on kubectl v1.33 and older (e.g. an old practice machine) is `--cpu-percent` the only option - `k version --client` tells you. When in doubt, generate YAML with `$do` and set `averageUtilization` yourself.

> **Exam tip:** TARGETS `<unknown>/70%` = no metrics. Check `k top pods` (metrics-server) and that every container of the target has a **CPU request**. The task may expect you to add requests with `k set resources deploy web --requests=cpu=100m`.

> **Exam tip:** the HPA name defaults to the target's name. If the task names the HPA differently, use `--name=<hpa-name>` or edit the generated YAML.

- `averageUtilization` is relative to **requests**, not limits.
- Several metrics → the highest desired replica count wins.
- Scale-down waits 300 s by default; do not wait for it in the exam - verify the HPA object instead.
- `k scale` on an HPA-managed Deployment is reverted on the next sync.
- DaemonSets cannot be autoscaled by the HPA (no scale subresource).
- `autoscaling/v2beta2` manifests from old blog posts fail on current clusters - change to `autoscaling/v2`.

---

## Architect notes

- Right-size requests first (VPA `Off` recommendations, load tests); HPA percentages are meaningless when requests are fiction.
- CPU is a decent signal for stateless CPU-bound services; for queue consumers and I/O-bound apps scale on demand signals (RPS, queue depth, lag) via KEDA or a Prometheus adapter.
- Tune `behavior`: scale up fast, scale down slowly (stabilization 5-10 min, `Pods`/`Percent` caps) to avoid flapping and cold-start storms.
- `maxReplicas` is a cost and blast-radius guardrail; pair it with ResourceQuota and alerts on `ScalingLimited`.
- Startup CPU spikes can trigger false scale-ups; good readiness/startup probes and the controller's CPU initialization period (5 min default) mitigate this.
- Remove `spec.replicas` from GitOps manifests of HPA-managed workloads, or let the GitOps tool ignore that field.
- Combine HPA with PDBs and topology spread so that scale-down and node consolidation do not remove too many replicas from one zone at once.
- Plan node-autoscaler headroom (over-provisioning with low-priority placeholder pods) when scale-out latency matters.

---

## Docs to bookmark

- Horizontal Pod Autoscaling (concept, algorithm, behavior): https://kubernetes.io/docs/concepts/workloads/autoscaling/horizontal-pod-autoscale/
- HorizontalPodAutoscaler Walkthrough (load test): https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale-walkthrough/
- Autoscaling Workloads (overview incl. VPA, event-driven): https://kubernetes.io/docs/concepts/workloads/autoscaling/
- kubectl autoscale reference: https://kubernetes.io/docs/reference/kubectl/generated/kubectl_autoscale/
- Resize CPU and Memory Resources assigned to Containers: https://kubernetes.io/docs/tasks/configure-pod-container/resize-container-resources/

---

## Quick self-check

1. Create an HPA for Deployment `api`: 3-10 replicas, 65 % CPU, with the exam's kubectl v1.37 - and with an old kubectl v1.30.
2. `k get hpa` shows `<unknown>/65%`. List two causes.
3. Current 5 replicas, average CPU 30 %, target 60 %. What does the HPA want (ignoring behavior)?
4. Which `behavior` setting stops all scale-down?
5. What is the difference between `Utilization` and `AverageValue`?

<details><summary>Answers</summary>

1. v1.37: `k autoscale deploy api --min=3 --max=10 --cpu=65%`. v1.30: `k autoscale deploy api --min=3 --max=10 --cpu-percent=65`.
2. metrics-server missing/unhealthy (`k top pods` fails); a container of the target has no CPU request (also: pods not yet Ready / just started).
3. `ceil(5 × 30 / 60) = ceil(2.5) = 3` replicas (scale-down subject to the 300 s stabilization window).
4. `behavior.scaleDown.selectPolicy: Disabled`.
5. `Utilization` = average usage as a percentage of the pods' requests (requests required); `AverageValue` = absolute average per pod (e.g. `500m`, `200Mi`), independent of requests.

</details>
