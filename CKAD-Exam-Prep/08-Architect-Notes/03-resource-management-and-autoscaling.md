# 03 · Resource management and autoscaling

> **Exam link:** [04 · Environment, Configuration and Security](../04-Application-Environment-Configuration-and-Security/README.md) (requests, limits, quotas) · [06 · Cross-Cutting Skills](../06-Cross-Cutting-Skills-and-Bonus-Topics/README.md) (HPA). The exam checks that you can set the fields; production depends on the numbers you put in them.

A request is a promise to the scheduler and the unit you pay for. A limit is a safety net with side effects. Autoscalers multiply whatever sizing mistakes you make, so size first, then scale.

## Principles

1. **Requests are the contract.** They drive scheduling, bin packing, HPA utilization (a percentage *of the request*), node autoscaling and therefore cost. Set them from measurements.
2. **Memory is incompressible: limit = request.** Over-committed memory is resolved by the kernel OOM killer or by node-pressure eviction - unpredictably. Equal values keep failures inside the container's own budget.
3. **CPU is compressible: always request, limit only on purpose.** The failure mode of a CPU limit is throttling (latency), not a crash.
4. **Measure, size, re-measure.** Usage changes with every release; right-sizing is a loop, not a one-off.
5. **Scale on demand signals** (requests per second, queue depth, lag), not only on CPU.
6. **Bound every autoscaler:** min/max, quota, downstream capacity, budget.
7. **Pod and node autoscaling must agree.** Node autoscalers see requests only - "consolidation, like provisioning, only considers Pod resource requests and not real resource usage".

## Recommended defaults

| Setting | Default | Why |
|---|---|---|
| CPU request | P95 of observed usage (steady state incl. peaks) | guaranteed share under contention, honest bin packing |
| CPU limit | none for latency-sensitive services in a trusted cluster; `= request` when you need Guaranteed QoS or hard isolation | no CFS throttling; idle CPU is used |
| Memory request = limit | P99 working set + 10-25% headroom | predictable; no surprise OOM from neighbours |
| Runtime memory flags | JVM `-XX:MaxRAMPercentage=75`, Go `GOMEMLIMIT` ~90% of limit, Node.js `--max-old-space-size` | the runtime respects the container limit |
| QoS | Burstable (memory req = limit, CPU request only) for most services; Guaranteed for databases and latency-critical pinned workloads | see table below |
| Namespace guard rails | ResourceQuota on `requests.*` + `limits.memory`, LimitRange defaults | no BestEffort pods, no unbounded teams |
| HPA | `autoscaling/v2`, CPU 60-75% of request or a demand metric, fast scale-up, slow scale-down | stable, responsive |
| VPA | `updateMode: "Off"` everywhere as an advisor | recommendations without disruption |
| Event-driven / scale to zero | KEDA | queue length, lag, cron, Prometheus queries |
| Nodes | provider-managed autoscaler; Karpenter on AWS | pending pods get capacity in minutes |

## Decision tables / trade-offs

### The CPU-limits debate

| Approach | Pros | Cons | Use when |
|---|---|---|---|
| Requests only (no CPU limit) | no throttling, bursts use idle CPU, best tail latency | performance tests less predictable; a busy neighbour can use *idle* CPU (never your requested share) | default for services in a trusted, single-team or well-governed cluster |
| Limit = request (Guaranteed) | predictable, strict isolation, enables exclusive cores with the static CPU manager policy | throttles on every burst, idle capacity wasted | multi-tenant hard isolation, pinned latency-critical workloads, benchmarks |
| Limit = 2-4x request | bounded bursts | still throttles at the cap; easy to set wrongly | shared clusters that require a limit by policy |

Throttling explained: CFS enforces a CPU limit as a quota per 100 ms period. A container limited to 1 CPU running 4 busy threads uses its quota in ~25 ms and then waits ~75 ms - p99 latency spikes while average CPU looks low. Watch `container_cpu_cfs_throttled_periods_total / container_cpu_cfs_periods_total`. Under contention CPU *requests* are enforced as relative weights, so a pod always gets at least its requested share.

### QoS strategy

| QoS class | How you get it | Under node memory pressure | Use for |
|---|---|---|---|
| Guaranteed | every container: CPU and memory requests == limits | usage never exceeds requests, so evicted last (by priority) | databases, brokers, pinned latency-critical services |
| Burstable | at least one request or limit set | evicted early only if usage exceeds requests | most services (memory req = limit keeps them in the safe group) |
| BestEffort | nothing set | first to go | never in production (LimitRange defaults prevent it) |

The kubelet ranks evictions by: usage above requests, then priority, then usage relative to requests - "the kubelet does not use the pod's QoS class to determine the eviction order". QoS is a good predictor, not the rule. Exceeding a memory **limit** is different: the kernel OOM-kills the container (`OOMKilled`, container restart), no eviction involved.

### Which autoscaler

| Need | Tool | Notes |
|---|---|---|
| More replicas when CPU/memory per pod rises | HPA `Resource` / `ContainerResource` (GA v1.30) | `ContainerResource` ignores sidecar usage |
| Scale on RPS, latency, business metrics | HPA `Pods` / `Object` via a custom-metrics adapter, or KEDA `prometheus` trigger | KEDA avoids running a separate adapter |
| Scale on queue depth / lag; scale to zero | KEDA `ScaledObject` (or `ScaledJob` for long tasks) | HPA `minReplicas: 0` needs object/external metrics and `HPAScaleToZero` (beta, on by default only from v1.37) |
| Right-size requests | VPA (`Off` -> recommendations) | do not let VPA and HPA act on the same CPU/memory metric |
| Resize running pods without restart | in-place resize (GA v1.35), VPA `InPlaceOrRecreate`/`InPlace` | CPU and memory only; QoS class cannot change |
| More nodes for pending pods | Cluster Autoscaler, Karpenter, provider node auto-provisioning | all decide on requests, not usage |

### HPA metric types (autoscaling/v2)

| Type | Source API | Example | Typical target |
|---|---|---|---|
| `Resource` | metrics.k8s.io (metrics-server) | CPU of all containers | `Utilization` 60-75 |
| `ContainerResource` | metrics.k8s.io | CPU of container `app` only | `Utilization` 70 |
| `Pods` | custom.metrics.k8s.io (adapter) | `http_requests_per_second` per pod | `AverageValue` |
| `Object` | custom.metrics.k8s.io | requests/s on an Ingress or Service | `Value` / `AverageValue` |
| `External` | external.metrics.k8s.io | queue length in SQS/Pub/Sub | `AverageValue` |

With several metrics the HPA computes a replica count per metric and uses the highest. Defaults if you set no `behavior`: scale-up immediately by max(100%, 4 pods) per 15s; scale-down after a 300s stabilization window. The global 10% tolerance can be tuned per HPA with `behavior.scaleUp|scaleDown.tolerance` (alpha v1.33, beta but off by default in v1.35, GA v1.37).

### VPA update modes

| Mode | Behaviour | Use for |
|---|---|---|
| `Off` | recommendations only (in `.status`) | everywhere: sizing advisor, feeds the right-sizing loop |
| `Initial` | sets requests at pod creation, never changes running pods | batch, workloads with natural churn |
| `Recreate` (default) | evicts pods to apply new requests (respects PDBs) | stable singletons tolerant of restarts |
| `InPlaceOrRecreate` | in-place resize, eviction as fallback | clusters with in-place resize (v1.33+ beta, GA v1.35) |
| `InPlace` | in-place only, never evicts | disruption-intolerant workloads |
| `Auto` | deprecated alias of `Recreate` | do not use in new manifests |

Do not run VPA and HPA on the same resource metric. VPA on memory plus HPA on CPU, or VPA plus HPA on custom/external metrics, is supported (restrict VPA with `controlledResources`). Mode list as of the VPA project docs in Oct 2026 (verify current status for your VPA version).

### Cluster Autoscaler versus Karpenter

| | Cluster Autoscaler | Karpenter |
|---|---|---|
| Model | resizes pre-defined node groups (ASG, MIG, VMSS) | launches individual nodes directly, choosing instance types for the pending pods |
| Scale-down | node unneeded for 10 min (default) and below 50% requested utilization (default) | consolidation: delete or replace under-used nodes; drift and expiry handling |
| Instance mix | one shape per node group | NodePool requirements (families, arch, spot/on-demand, zones) |
| Disruption controls | PDBs, `cluster-autoscaler.kubernetes.io/safe-to-evict: "false"` | PDBs, NodePool disruption budgets, `karpenter.sh/do-not-disrupt: "true"` |
| Where | all major clouds; offered as a managed feature on GKE and AKS | AWS (most mature); also behind EKS Auto Mode and AKS node auto-provisioning (verify current status) |

Recommendation: use the provider's managed node autoscaling where it exists; on self-managed AWS prefer Karpenter. Either way it only works if requests are honest, PDBs exist, and singletons that must not move are annotated.

## In-place resize

- `InPlacePodVerticalScaling`: beta and on by default in v1.33-v1.34, **GA in v1.35**. Resize through the `resize` subresource (kubectl >= v1.32), per-resource `resizePolicy` (`NotRequired` default, or `RestartContainer`), progress in pod conditions `PodResizePending` / `PodResizeInProgress`.
- Limits (v1.37 docs): CPU and memory only; the QoS class cannot change; memory decreases are best-effort; no Windows pods; not with static CPU/memory manager policies.
- Resizing a Deployment's pods by hand drifts from the template (the next rollout resets it). The real use is VPA `InPlaceOrRecreate`/`InPlace`, and "start-up boost" patterns (generous CPU while a JVM boots, smaller afterwards).
- Pod-level `spec.resources` (one budget shared by all containers of a pod) is beta and on by default since v1.34 - useful for pods with several sidecars (verify current status before relying on it).

## Cost visibility

- **Requests drive cost.** The scheduler packs by requests, node autoscalers buy nodes for requests, and requested-but-idle capacity is paid waste. Usage only matters for limits and eviction.
- Report requested vs used per namespace and team (labels such as `team`, `cost-center`); tools: OpenCost (CNCF incubating), Kubecost, or the cloud's cost allocation for Kubernetes (verify current status).
- Biggest levers, in order: right-size requests; scale non-prod to zero at night (KEDA `cron` trigger or a CronJob); spot/preemptible nodes for stateless pods with PDBs and diverse instance types; one shared Gateway instead of a load balancer per Service; topology-aware routing to cut cross-zone traffic ([05](05-networking-and-traffic-management.md)); ARM nodes where images are multi-arch.

## Right-sizing loop

1. **Instrument:** Prometheus scraping cAdvisor (usage) and kube-state-metrics (requests/limits).
2. **Observe 7-14 days** including peaks (month-end, campaigns, batch windows).
3. **Compute** P95 CPU and P99 memory working set per container; efficiency = usage / request.
4. **Propose** new requests (VPA `Off` recommendations or the queries below); memory limit = new request.
5. **Ship via Git**, canary first; watch throttling, `OOMKilled`, latency SLO and HPA behaviour - changing a request changes the HPA's utilization math.
6. **Repeat** every release train or quarter; alert on `OOMKilled`, sustained throttling, and requests used < 30% for a week.

```text
# P95 CPU usage over 14 days per container (cores)
quantile_over_time(0.95, rate(container_cpu_usage_seconds_total{namespace="shop",container!=""}[5m])[14d:5m])

# P99 memory working set over 14 days per container (bytes)
quantile_over_time(0.99, container_memory_working_set_bytes{namespace="shop",container!=""}[14d])

# Requested CPU per container (kube-state-metrics)
kube_pod_container_resource_requests{namespace="shop",resource="cpu"}

# CPU throttling ratio per container
rate(container_cpu_cfs_throttled_periods_total{namespace="shop"}[5m]) / rate(container_cpu_cfs_periods_total{namespace="shop"}[5m])
```

## Anti-patterns

| Anti-pattern | Consequence | Fix |
|---|---|---|
| No requests (BestEffort) | first evicted; scheduler packs blindly; HPA utilization undefined | LimitRange defaults + quota |
| Requests copied from a template (`500m/512Mi` everywhere) | waste or OOM, HPA scaling on fiction | measure and right-size |
| Memory limit >> request | node over-commit; random OOM/evictions under pressure | memory limit = request |
| Tight CPU limits on latency-sensitive services | p99 latency spikes from throttling at low average CPU | remove CPU limit or raise it; watch throttling |
| HPA on memory for GC'd runtimes | memory never drops, never scales down | scale on CPU or a demand metric |
| HPA and VPA both on CPU | autoscalers fight (VPA raises requests, HPA utilization falls) | VPA `Off`, or split metrics |
| `replicas` in Git plus an HPA | every sync resets the replica count | omit `spec.replicas` |
| Your own HPA plus a KEDA ScaledObject on the same target | two controllers own replicas | let KEDA create its HPA |
| Quota on `limits.cpu` while advocating no CPU limits | every pod must declare a CPU limit | quota `requests.cpu` instead |
| `maxReplicas` sized without the database in mind | scale-out overloads the shared dependency | cap by downstream capacity; use connection pools |

## Reference YAML

- Requests/limits, HPA with `behavior`: [`yaml/production-deployment-template.yaml`](yaml/production-deployment-template.yaml)
- ResourceQuota + LimitRange: [`yaml/namespace-baseline.yaml`](yaml/namespace-baseline.yaml)
- KEDA queue worker with scale to zero: [`yaml/keda-scaledobject-example.yaml`](yaml/keda-scaledobject-example.yaml)

HPA on the app container's CPU and a per-pod request rate (the `Pods` metric needs a custom-metrics adapter such as Prometheus Adapter):

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: web
  namespace: shop
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: web
  minReplicas: 3
  maxReplicas: 30
  metrics:
  - type: ContainerResource          # ignores sidecar CPU (GA v1.30)
    containerResource:
      name: cpu
      container: app
      target:
        type: Utilization
        averageUtilization: 70
  - type: Pods
    pods:
      metric:
        name: http_requests_per_second
      target:
        type: AverageValue
        averageValue: "50"           # each pod should handle ~50 req/s
  behavior:
    scaleDown:
      stabilizationWindowSeconds: 300
```

VPA as a sizing advisor (requires the VPA components; recommendations appear in `kubectl describe vpa api -n shop`):

```yaml
apiVersion: autoscaling.k8s.io/v1
kind: VerticalPodAutoscaler
metadata:
  name: api
  namespace: shop
spec:
  targetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: api
  updatePolicy:
    updateMode: "Off"                # recommend only
  resourcePolicy:
    containerPolicies:
    - containerName: app
      controlledResources: ["cpu", "memory"]
      minAllowed:
        cpu: 50m
        memory: 64Mi
      maxAllowed:
        cpu: "2"
        memory: 2Gi
```

In-place resize of one pod (v1.33+; kubectl >= v1.32):

```bash
kubectl -n shop patch pod api-7d9c5b6f4-x2k8q --subresource resize --patch \
  '{"spec":{"containers":[{"name":"app","resources":{"requests":{"cpu":"500m"}}}]}}'
kubectl -n shop get pod api-7d9c5b6f4-x2k8q -o jsonpath='{.status.conditions[*].type}'   # PodResizePending / PodResizeInProgress while it runs
```

## Checklist

- [ ] Every container has CPU and memory requests based on measured P95/P99 usage.
- [ ] Memory limit = memory request; CPU limit only by explicit decision (isolation, Guaranteed QoS).
- [ ] Runtime memory settings follow the container limit (JVM, Go, Node.js).
- [ ] Namespaces have ResourceQuota (`requests.*`, `limits.memory`, object counts) and LimitRange defaults.
- [ ] HPA on `autoscaling/v2` with `behavior`; `minReplicas` >= 3 for HA services; no `replicas` in Git.
- [ ] Demand-based scaling (KEDA or custom metrics) where CPU is a poor proxy; `maxReplicas` respects downstream capacity.
- [ ] VPA in `Off` mode (or equivalent queries) feeds a recurring right-sizing review.
- [ ] Node autoscaling in place; PDBs and `safe-to-evict`/`do-not-disrupt` annotations reviewed.
- [ ] Dashboards for requested vs used, throttling ratio, `OOMKilled`, cost per namespace.

## References

- Resource management for pods and containers: https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/
- Pod QoS classes: https://kubernetes.io/docs/concepts/workloads/pods/pod-qos/
- Node-pressure eviction: https://kubernetes.io/docs/concepts/scheduling-eviction/node-pressure-eviction/
- LimitRange: https://kubernetes.io/docs/concepts/policy/limit-range/
- ResourceQuota: https://kubernetes.io/docs/concepts/policy/resource-quotas/
- Autoscaling workloads (overview): https://kubernetes.io/docs/concepts/workloads/autoscaling/
- Horizontal Pod Autoscaling: https://kubernetes.io/docs/concepts/workloads/autoscaling/horizontal-pod-autoscale/
- HPA walkthrough: https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale-walkthrough/
- Vertical Pod Autoscaling: https://kubernetes.io/docs/concepts/workloads/autoscaling/vertical-pod-autoscale/
- Node autoscaling: https://kubernetes.io/docs/concepts/cluster-administration/node-autoscaling/
- Resize CPU and memory in place: https://kubernetes.io/docs/tasks/configure-pod-container/resize-container-resources/
- Pod-level resources: https://kubernetes.io/docs/tasks/configure-pod-container/assign-pod-level-resources/
- CPU management policies: https://kubernetes.io/docs/tasks/administer-cluster/cpu-management-policies/
- Resource metrics pipeline (metrics-server): https://kubernetes.io/docs/tasks/debug/debug-cluster/resource-metrics-pipeline/
- VPA project: https://github.com/kubernetes/autoscaler/tree/master/vertical-pod-autoscaler
- Cluster Autoscaler: https://github.com/kubernetes/autoscaler/tree/master/cluster-autoscaler
- Karpenter: https://karpenter.sh/docs/
- KEDA: https://keda.sh/docs/latest/scalers/
- OpenCost: https://opencost.io/
