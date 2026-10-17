# 02 · Reliability and high availability

> **Exam link:** [03 · Observability and Maintenance](../03-Application-Observability-and-Maintenance/README.md) (probes) · [02 · Application Deployment](../02-Application-Deployment/README.md) (rolling updates) · [06 · Cross-Cutting Skills](../06-Cross-Cutting-Skills-and-Bonus-Topics/README.md) (PDB, scheduling, PriorityClass). The exam asks you to write probes and PDBs; production asks whether they are the right ones.

High availability on Kubernetes means surviving two kinds of events without users noticing: the **voluntary disruptions you cause** every day (rollouts, node drains, autoscaler scale-in, cluster upgrades) and the **involuntary ones** (process crash, node loss, zone loss). Most outages come from the first kind, done badly.

## Principles

1. **Started, ready and alive are three different questions.** One probe each, with different checks and thresholds.
2. **Liveness checks only the process itself.** Never a database, a downstream API or anything shared.
3. **Stop receiving traffic before you stop serving it.** Endpoint removal is asynchronous; the app must keep serving for a few seconds after termination starts, then drain.
4. **Redundancy per failure domain.** Replicas across nodes and zones, with spare capacity to absorb the loss of one zone.
5. **Budget voluntary disruptions explicitly** (PodDisruptionBudget) and make rollouts surge-first.
6. **Rollouts should be boring:** small, gated by readiness, observable, halted automatically when unhealthy.
7. **Untested failover is not failover.** Kill pods, drain nodes and take out a zone on purpose.

## Recommended defaults

| Setting | Default to use | Why |
|---|---|---|
| Replicas (user-facing) | >= 3, one per zone (`minReplicas: 3` on the HPA) | 2 replicas are one disruption away from a single point of failure |
| `startupProbe` | present when boot can exceed ~10s; `failureThreshold x periodSeconds` >= 1.5 x P99 boot time | liveness and readiness wait until it succeeds |
| `readinessProbe` | `periodSeconds: 5`, `timeoutSeconds: 2`, `failureThreshold: 3`, dedicated `/readyz` | fast removal from endpoints, no restart |
| `livenessProbe` | `periodSeconds: 10`, `timeoutSeconds: 2`, `failureThreshold: 3`, dedicated `/healthz`, no dependency checks | restarts only a truly stuck process |
| Probe handler | `httpGet` or `grpc` (GA v1.27); avoid `exec` at high pod density | exec forks processes on every probe |
| `preStop` | `sleep` action, 5-15s (GA v1.34; beta, on by default since v1.30) | covers endpoint-removal lag without a shell in the image |
| `terminationGracePeriodSeconds` | preStop + longest request + buffer (e.g. 10 + 30 = 40) | the countdown includes the preStop hook |
| Rolling update | `maxSurge: 25%` (or 1), `maxUnavailable: 0` | capacity never drops during a rollout |
| `minReadySeconds` | 10-30 | catches pods that crash shortly after becoming Ready |
| `progressDeadlineSeconds` | 300-600, plus `kubectl rollout status --timeout` or GitOps health checks | Kubernetes only reports `ProgressDeadlineExceeded`, it does not roll back |
| PDB | `maxUnavailable: 1` + `unhealthyPodEvictionPolicy: AlwaysAllow` (GA v1.31) | drains proceed, broken pods never block them |
| Spread | zone `topologySpreadConstraints` (`ScheduleAnyway`) + preferred host anti-affinity | survives node and zone loss without Pending pods |
| Priority | a small, cluster-wide set of PriorityClasses guarded by quota | critical services win under resource pressure |

## Decision tables / trade-offs

### Probe design

| Probe | Question it answers | On failure | Check | Never |
|---|---|---|---|---|
| `startupProbe` | Has the app finished booting? | container restarted after `failureThreshold x periodSeconds` | same endpoint as liveness | use `initialDelaySeconds` instead of it |
| `readinessProbe` | Should this pod receive traffic now? | removed from EndpointSlices, **not** restarted | listening, warmed up, not overloaded, not shutting down, local sidecar ready | depend on slow checks (it gates every rollout step) |
| `livenessProbe` | Is the process irrecoverably stuck? | container **restarted** | event loop / worker threads alive, no deadlock | check databases or other services; share thresholds with readiness |

Readiness and shared dependencies: the official docs allow a readiness probe to check strict back-end dependencies so traffic does not go to pods that can only return errors. Use that sparingly. When a dependency shared by all replicas fails, every pod goes unready at once, the Service has zero endpoints, and a degraded-but-explained response (fast 503, cached data) becomes connection failures at the load balancer. Check per-pod dependencies (a local proxy, an assigned shard); handle shared ones in code with timeouts, circuit breakers and degraded modes.

Probe pitfalls seen in production:

- Liveness calling the database: a short database blip restarts the whole fleet, which then stampedes the database on start-up (the docs call this cascading failure).
- Liveness and readiness on the same endpoint with the same thresholds: the pod is killed exactly when it should only have been taken out of rotation.
- Default `timeoutSeconds: 1` under GC pauses or CPU throttling: false failures at peak load. Use 2-5s.
- `initialDelaySeconds: 120` to cover a slow boot: delays failure detection after every restart. Use a `startupProbe`.
- Probe-level `terminationGracePeriodSeconds` (GA v1.28) lets a liveness-triggered kill be fast while normal shutdown keeps the long pod-level grace period.

### PodDisruptionBudget shape

| PDB | Use when | Avoid because |
|---|---|---|
| `maxUnavailable: 1` | default for Deployments; works at any replica count, HPA-friendly | - |
| `maxUnavailable: 25%` | large fleets where one-at-a-time drains are too slow | - (PDB percentages round **up**: 25% of 3 pods still allows 1; Deployment `maxUnavailable` rounds down) |
| `minAvailable: <quorum>` (integer) | quorum systems: 3-member etcd/ZooKeeper/Kafka controller -> `minAvailable: 2` | - |
| `minAvailable: 100%` or `maxUnavailable: 0` | never | blocks every drain and cluster upgrade |
| single replica + any PDB | never | node cannot be drained without manual work |

PDBs only govern **evictions** (drain, Cluster Autoscaler, Karpenter, VPA). They do not protect against node crashes, `kubectl delete pod` ignores them, and the Deployment controller's own rollout uses `maxUnavailable`, not the PDB. Preemption respects PDBs only on a best-effort basis.

### Hard versus soft spreading

| Constraint | Effect | Use when | Risk |
|---|---|---|---|
| zone spread, `ScheduleAnyway` | balanced zones when possible | default for stateless services | can skew under capacity pressure |
| zone spread, `DoNotSchedule` + `minDomains` | strict balance across at least N zones | quorum StatefulSets, guaranteed per-zone capacity | pods stay Pending when a zone is down or full |
| host anti-affinity, `preferred...` | at most one per node when possible | default for stateless services | none worth noting |
| host anti-affinity, `required...` | never two on one node | quorum members (ZooKeeper, etcd, brokers) | replicas > nodes means Pending; costly for the scheduler at scale |

Spread details that matter:

- With `DoNotSchedule`, nodes that do not tolerate a taint still count as (empty) domains unless you set `nodeTaintsPolicy: Honor` (GA v1.33; default is `Ignore`). Classic symptom: pods Pending while the only "empty" node is a tainted control-plane node.
- `matchLabelKeys: [pod-template-hash]` (beta, on by default since v1.27) spreads each rollout revision separately, so old pods do not distort the skew during an update.
- Without any constraints the scheduler still applies built-in soft defaults (hostname `maxSkew: 3`, zone `maxSkew: 5`, both `ScheduleAnyway`) - too weak for a 3-replica service.

### Rolling-update tuning

| Field | Default | Production choice | Notes |
|---|---|---|---|
| `maxSurge` | 25% (rounds up) | 25% or 1 | needs headroom in quota and cluster capacity |
| `maxUnavailable` | 25% (rounds down) | 0 for user-facing services | 10 replicas, defaults: up to 3 extra and 2 unavailable at once |
| `minReadySeconds` | 0 | 10-30 | a pod counts as available only after staying Ready this long |
| `progressDeadlineSeconds` | 600 | 300-600 | condition `Progressing=False`, reason `ProgressDeadlineExceeded`; no automatic rollback |
| `revisionHistoryLimit` | 10 | 5-10 | with GitOps, Git is the real history |
| `strategy: Recreate` | - | only when two versions cannot coexist (RWO volume, exclusive lock) | causes downtime by design |

Surge plus a long grace period temporarily means up to roughly twice the pods (new pods plus still-terminating old ones), so capacity and quota must allow it. Deployment `status.terminatingReplicas` (beta v1.35) makes those terminating pods visible.

### Priority tiers

| PriorityClass (example) | Value | `preemptionPolicy` | For |
|---|---|---|---|
| `platform-critical` | 1000000 | PreemptLowerPriority | ingress/gateway data plane, DNS add-ons, observability agents |
| `business-critical` | 100000 | PreemptLowerPriority | revenue-path services |
| `standard` (`globalDefault: true`) | 1000 | PreemptLowerPriority | everything else |
| `batch-low` | 100 | Never | batch that may queue but never evicts others |
| `overprovisioning` | -10 | Never | "balloon" pause pods that reserve headroom (Cluster Autoscaler FAQ pattern) |

User-defined values must be at most 1000000000; `system-cluster-critical` and `system-node-critical` are reserved for system components. Guard high classes with a `ResourceQuota` `scopeSelector` on `PriorityClass`, otherwise every team marks itself critical.

### Multi-zone and multi-cluster

| Option | Protects against | Cost / complexity | Recommendation |
|---|---|---|---|
| One cluster, 3 zones | node and zone loss | low; cross-zone traffic is billed by most clouds | default for production |
| Two+ clusters in one region | cluster-level failure (bad upgrade, control-plane or CNI incident), blast radius | medium: GitOps fan-out, duplicated add-ons | for tier-0 services and for blue/green cluster upgrades |
| Clusters in several regions | region loss, latency, data residency | high: global load balancing, data replication (RPO/RTO) | only with a clear business requirement; data is the hard part |

Capacity rule for 3 zones: to survive the loss of one zone, the other two must carry 100% of the load, so run each zone at no more than about 66% of what it could serve. Multi-cluster building blocks: Argo CD ApplicationSets or Flux for fan-out, the Multi-Cluster Services API (`ServiceExport`/`ServiceImport`), Cilium ClusterMesh, Istio multi-cluster, cloud multi-cluster gateways (verify current status for each).

## Graceful shutdown

```text
t=0s    Pod gets a deletionTimestamp ("Terminating")
        |- kubelet runs the preStop hook (sleep 10)
        |                                   |- EndpointSlice: endpoint becomes ready=false, terminating=true
        |                                   |- kube-proxy on every node reprograms rules       (async)
        |                                   '- Ingress/Gateway proxies, cloud LBs deregister   (async, seconds)
t=10s   preStop finished -> SIGTERM (or the image's STOPSIGNAL) to PID 1 of each container
        app: stop accepting, finish in-flight requests, close keep-alives, flush buffers, exit 0
t=40s   terminationGracePeriodSeconds expires -> SIGKILL (one-off 2s extension if preStop still runs)
```

- The endpoint-removal lag is the reason for the `preStop` sleep: without it, some proxies keep sending new requests to a process that is already shutting down, and users see 502/connection resets on every rollout.
- PID 1 must receive the signal. `CMD ["sh", "-c", "java -jar app.jar"]` makes the shell PID 1, which may not forward SIGTERM, so the app is SIGKILLed at the deadline. Use exec form, `exec` inside scripts, or a minimal init (tini).
- The app must implement draining: Go `signal.NotifyContext` + `http.Server.Shutdown`, Spring Boot `server.shutdown=graceful`, Node.js `process.on('SIGTERM')` + `server.close()`. nginx drains on SIGQUIT, which its official image sets as `STOPSIGNAL`.
- Long-lived connections (WebSockets, gRPC streams, HTTP/2 keep-alive) need explicit draining (GOAWAY, `Connection: close`) and clients that reconnect with jitter.
- Native sidecars are stopped after the app containers, so a mesh proxy outlives the app it serves. A custom per-container stop signal (`lifecycle.stopSignal`) exists only as alpha (v1.33, `ContainerStopSignals`); rely on the image `STOPSIGNAL`.
- Queue workers: `terminationGracePeriodSeconds` must cover the longest message; ack only after processing; make processing idempotent.

## Chaos testing

1. Define steady state as an SLO (e.g. 99.9% of requests < 300 ms), not as "pods are Running".
2. Start with built-in operations during business hours with people watching: delete pods during peak, `kubectl drain` a node during a rollout, cordon and drain every node of one zone, scale CoreDNS down, expire a certificate in staging, exhaust a namespace quota.
3. Automate with Chaos Mesh or LitmusChaos (both CNCF incubating) or a cloud fault-injection service; inject latency and errors through the mesh or Gateway where supported.
4. Verify that running workloads keep serving while the API server is unavailable: data-plane traffic must not depend on the control plane.
5. Turn every finding into a fix plus a regression experiment.

## Anti-patterns

| Anti-pattern | Consequence | Fix |
|---|---|---|
| Liveness probe checks the database | fleet-wide restart loop on a database blip | liveness = process health only |
| No readiness probe | traffic hits pods that are still booting; rollouts proceed blindly | dedicated `/readyz` |
| No `preStop` delay | 502s and resets on every rollout and drain | `preStop` sleep 5-15s + drain on SIGTERM |
| Grace period shorter than preStop + drain | SIGKILL mid-request | size `terminationGracePeriodSeconds` from measurements |
| 1-2 replicas for a "critical" service | outage during the next drain or rollout | >= 3 across zones |
| PDB `minAvailable` equal to replicas | node drains and cluster upgrades blocked | `maxUnavailable: 1` |
| Required anti-affinity everywhere | Pending pods when nodes are few or a zone is down | preferred anti-affinity + soft zone spread |
| `maxUnavailable: 25%` on a 4-replica service at 80% load | the remaining pods overload during every rollout | `maxUnavailable: 0`, surge first |
| Everything marked high priority | priority means nothing; batch evicts nothing or everything | few tiers, quota-guarded |
| "We are multi-AZ" without zonal capacity headroom | zone loss becomes cluster-wide overload | run each of 3 zones at <= ~66% |

## Reference YAML

Complete example with probes, preStop, grace period, spread, PDB and HPA: [`yaml/production-deployment-template.yaml`](yaml/production-deployment-template.yaml).

Probe set for a slow-booting JVM service (fragment of a container spec):

```yaml
startupProbe:
  httpGet:
    path: /actuator/health/liveness
    port: http
  periodSeconds: 5
  failureThreshold: 36             # up to 3 minutes to boot; liveness waits for this
readinessProbe:
  httpGet:
    path: /actuator/health/readiness
    port: http
  periodSeconds: 5
  timeoutSeconds: 3
  failureThreshold: 3
livenessProbe:
  httpGet:
    path: /actuator/health/liveness
    port: http
  periodSeconds: 10
  timeoutSeconds: 3
  failureThreshold: 3
  terminationGracePeriodSeconds: 10   # probe-level: a stuck process is killed fast
lifecycle:
  preStop:
    sleep:
      seconds: 10
```

Priority tiers guarded by quota:

```yaml
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: business-critical
value: 100000
preemptionPolicy: PreemptLowerPriority
globalDefault: false
description: "Revenue-path services. Usage is limited per namespace by ResourceQuota."
---
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: batch-low
value: 100
preemptionPolicy: Never            # may wait in the queue, never evicts others
description: "Batch and reports."
---
apiVersion: v1
kind: ResourceQuota
metadata:
  name: business-critical-pods
  namespace: shop
spec:
  hard:
    pods: "20"                     # at most 20 business-critical pods in this namespace
  scopeSelector:
    matchExpressions:
    - scopeName: PriorityClass
      operator: In
      values: ["business-critical"]
```

Quorum StatefulSet spreading (fragment of `spec.template.spec` plus its PDB):

```yaml
affinity:
  podAntiAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
    - topologyKey: kubernetes.io/hostname    # never two members on one node
      labelSelector:
        matchLabels:
          app.kubernetes.io/name: zookeeper
topologySpreadConstraints:
- maxSkew: 1
  topologyKey: topology.kubernetes.io/zone
  whenUnsatisfiable: DoNotSchedule
  minDomains: 3                              # requires three zones
  nodeTaintsPolicy: Honor                    # ignore nodes the pod cannot run on
  labelSelector:
    matchLabels:
      app.kubernetes.io/name: zookeeper
```

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: zookeeper
  namespace: data
spec:
  minAvailable: 2                  # quorum of 3
  selector:
    matchLabels:
      app.kubernetes.io/name: zookeeper
```

## Checklist

- [ ] `startupProbe` for slow boots; readiness and liveness on separate endpoints with separate thresholds.
- [ ] Liveness never checks dependencies; readiness checks shared dependencies only by explicit decision.
- [ ] `preStop` sleep (5-15s) and `terminationGracePeriodSeconds` sized from measured drain time.
- [ ] App drains on SIGTERM/STOPSIGNAL; PID 1 receives signals (exec form or tini).
- [ ] >= 3 replicas across zones; zonal capacity headroom (each of 3 zones <= ~66%).
- [ ] PDB `maxUnavailable: 1` (or quorum `minAvailable`) with `unhealthyPodEvictionPolicy: AlwaysAllow`.
- [ ] Zone topology spread + preferred host anti-affinity; hard constraints only with `nodeTaintsPolicy: Honor` and planned capacity.
- [ ] `maxUnavailable: 0`, `maxSurge` set, `minReadySeconds` >= 10, rollout status checked in CI/GitOps.
- [ ] PriorityClasses defined cluster-wide and guarded by quota.
- [ ] Failure experiments (pod kill, drain, zone loss) run regularly and tracked.

## References

- Pod lifecycle and termination: https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/
- Container lifecycle hooks: https://kubernetes.io/docs/concepts/containers/container-lifecycle-hooks/
- Probes (concept): https://kubernetes.io/docs/concepts/workloads/pods/probes/
- Configure liveness, readiness and startup probes: https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/
- Disruptions: https://kubernetes.io/docs/concepts/workloads/pods/disruptions/
- Specifying a disruption budget: https://kubernetes.io/docs/tasks/run-application/configure-pdb/
- Pod topology spread constraints: https://kubernetes.io/docs/concepts/scheduling-eviction/topology-spread-constraints/
- Assigning pods to nodes (affinity): https://kubernetes.io/docs/concepts/scheduling-eviction/assign-pod-node/
- Deployments (rolling update, progress deadline): https://kubernetes.io/docs/concepts/workloads/controllers/deployment/
- Pod priority and preemption: https://kubernetes.io/docs/concepts/scheduling-eviction/pod-priority-preemption/
- Resource quotas (scopes): https://kubernetes.io/docs/concepts/policy/resource-quotas/
- Running in multiple zones: https://kubernetes.io/docs/setup/best-practices/multiple-zones/
- Safely drain a node: https://kubernetes.io/docs/tasks/administer-cluster/safely-drain-node/
- Multi-Cluster Services API (SIG Multicluster): https://multicluster.sigs.k8s.io/
- Cluster Autoscaler FAQ (overprovisioning): https://github.com/kubernetes/autoscaler/blob/master/cluster-autoscaler/FAQ.md
- Chaos Mesh: https://chaos-mesh.org/ · LitmusChaos: https://litmuschaos.io/
