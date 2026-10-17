# 07 · Observability

> **Exam link:** [03 · Observability and Maintenance](../03-Application-Observability-and-Maintenance/README.md) (probes, `kubectl logs`/`top`/`events`, debugging). The exam stops at `kubectl`; production needs signals that survive pod restarts, node loss and 3 a.m.

You cannot operate what you cannot see, and you cannot afford to see everything. Design observability like any other system: decide what questions you must answer during an incident, collect the signals that answer them, correlate them, and control the cost.

## Principles

1. **Symptoms first.** Alert on what users feel (error rate, latency, availability) - causes belong on dashboards and tickets.
2. **Three signals, one context.** Logs, metrics and traces share trace IDs and Kubernetes metadata (namespace, workload, pod, version) so you can pivot between them.
3. **Open standards:** OpenTelemetry for instrumentation and transport, Prometheus exposition for metrics - backends stay replaceable.
4. **Labels are a budget.** High-cardinality labels (user ID, request ID, pod name on business metrics) explode cost; put them in logs/traces instead.
5. **Kubernetes state is a signal:** restarts, `OOMKilled`, throttling, Pending pods, HPA at max, PDBs at zero, Warning events.
6. **Debug without mutating production:** read first, ephemeral containers second, pod copies third, node shells last - all RBAC-gated and audited.
7. **Telemetry must outlive the pod:** ship logs and events off the node quickly; nothing important may exist only in `kubectl logs`.

## Recommended defaults

| Concern | Default | Notes |
|---|---|---|
| App metrics | Prometheus client library or OTel SDK; RED metrics as histograms | expose `/metrics` on a named port `metrics` |
| Cluster metrics | Prometheus (Operator) scraping kubelet/cAdvisor, kube-state-metrics, node-exporter, control plane | Grafana dashboards; long-term storage via Thanos/Cortex/Mimir or a vendor (verify current status) |
| Autoscaling metrics | metrics-server | "meant only for autoscaling purposes" - not a monitoring source |
| Logs | JSON on stdout -> node agent DaemonSet (OTel Collector `filelog`, Fluent Bit or Vector) -> log backend | enrich with Kubernetes metadata in the agent |
| Traces | OTel SDK / auto-instrumentation -> agent -> gateway collector (tail sampling) -> Jaeger, Tempo or a vendor | W3C `traceparent` propagation |
| Correlation | `trace_id`/`span_id` in every log line; exemplars on latency histograms | one click from alert -> trace -> logs |
| Events | exported to the log backend (OTel `k8sobjects` receiver or an event exporter) | the API server keeps events for 1h by default (`--event-ttl`) |
| Alerting | SLO burn-rate alerts page; cause alerts open tickets | every page links a runbook and a dashboard |
| Synthetic checks | external blackbox probes of every public hostname, incl. TLS expiry | probes do not see DNS, TLS or the Gateway |
| Debugging | `kubectl debug` with an explicit `--profile`; RBAC for `pods/ephemeralcontainers` only for on-call | audited break-glass |

## Decision tables / trade-offs

### Logs, metrics, traces

| Signal | Answers | Kubernetes source | Cost driver |
|---|---|---|---|
| Metrics | "Is something wrong, how much, since when?" | app `/metrics`, cAdvisor, kube-state-metrics, node-exporter | number of time series (label cardinality) |
| Logs | "What exactly happened to this request/pod?" | container stdout/stderr files on the node (rotated by the kubelet at 10Mi x 5 files by default) | volume (GB/day), retention, indexing |
| Traces | "Where did the time go across services?" | OTel SDKs, mesh/Gateway spans | span volume - controlled by sampling |
| Events | "What did Kubernetes do (scheduling, probes, evictions, admission)?" | Event API (TTL 1h by default) | small; export them |
| Profiles | "Which code burns CPU/memory?" | continuous profilers (eBPF or SDK) | storage per profile |

### OpenTelemetry Collector deployment patterns

| Pattern | Kubernetes object | Use for | Trade-off |
|---|---|---|---|
| Agent | DaemonSet (one per node) | receive OTLP from local pods, tail node log files (`filelog`), `kubeletstats`, host metrics, add metadata (`k8sattributes`) | needs host log access (`hostPath`), so it lives in a platform namespace with a relaxed PSA level |
| Gateway | Deployment + HPA behind a Service (StatefulSet for trace-aware load balancing) | central batching, retries, auth to backends, PII scrubbing, tail sampling, routing to several backends | an extra hop; size and scale it like a service |
| Sidecar | extra container in each pod | per-tenant isolation, environments that forbid DaemonSets | resources x every replica, more moving parts |
| Cluster receiver | Deployment with 1 replica | `k8s_cluster` metrics, `k8sobjects` (events) | must be a singleton or data is duplicated |
| None (SDK -> backend) | - | tiny setups | no central control, apps coupled to the backend |

Recommended: **agent DaemonSet + gateway Deployment + one cluster receiver**; sidecars only by exception. The OpenTelemetry Operator manages collectors (`OpenTelemetryCollector` with `mode: daemonset|deployment|statefulset|sidecar`) and injects auto-instrumentation via annotations such as `instrumentation.opentelemetry.io/inject-java: "true"` (verify current status of CRD versions).

### Who provides which metrics

| Component | Provides | Consumed by | Not for |
|---|---|---|---|
| metrics-server | Resource Metrics API (`metrics.k8s.io`): pod/node CPU and memory, scraped every 15s | HPA, VPA, `kubectl top` | monitoring, alerting, history |
| kube-state-metrics | object state as metrics: replicas, pod phase, restarts, termination reasons, requests/limits, HPA/PDB/Job status | Prometheus alerts and dashboards | resource usage |
| kubelet / cAdvisor | container CPU, memory working set, throttling, filesystem, network | Prometheus | object state |
| node-exporter | node OS: CPU, memory, disk, network | Prometheus | containers |
| Prometheus (+ Operator CRDs `ServiceMonitor`, `PodMonitor`, `PrometheusRule`) | scraping, short-term storage, recording/alerting rules -> Alertmanager | Grafana, on-call | multi-cluster long-term storage on its own |

### RED, USE and Kubernetes health

| Method | For | Signals |
|---|---|---|
| RED | request-driven services | **R**ate, **E**rrors, **D**uration (histograms, not averages) |
| USE | resources (CPU, memory, disks, pools, queues) | **U**tilization, **S**aturation (throttling, queue length, pool waits), **E**rrors |
| Golden signals (Google SRE) | any user-facing system | latency, traffic, errors, saturation |
| Kubernetes health | workloads and platform | restarts, `OOMKilled`, CrashLoopBackOff, Pending > 5 min, HPA at `maxReplicas`, PDB `disruptionsAllowed == 0`, unavailable replicas, failed Jobs, PVC usage, certificate expiry |

### SLOs and alerting on symptoms

| Concept | Example |
|---|---|
| SLI | availability = non-5xx responses / all valid responses, measured at the Gateway; latency = share of requests < 300 ms |
| SLO | 99.9% availability over 30 days |
| Error budget | 0.1% of requests (~43 minutes of full outage per 30 days) |
| Fast-burn page | 2% of the monthly budget in 1h = burn rate 14.4 (confirm with a 5m window) |
| Slow-burn page | 5% in 6h = burn rate 6 (confirm with a 30m window) |
| Ticket | 10% in 3 days = burn rate 1 |

Multi-window, multi-burn-rate alerts (Google SRE Workbook) page only when the budget is really at risk and resolve quickly when the problem stops. Cause alerts (high CPU, a pod restart) become tickets unless they predict imminent user impact (disk full within hours, certificate expiring within days).

### Probes or synthetic checks?

| | Probes | Synthetic checks |
|---|---|---|
| Run by | the kubelet, per container, on the node | an external/blackbox prober (e.g. Prometheus blackbox exporter, uptime services) |
| Tests | local process health | the user path: DNS, TLS, load balancer, Gateway, routing, auth, dependencies |
| Result | restart or endpoint removal | an alert |
| Blind to | DNS, certificates, Gateway/Ingress, NetworkPolicy, cross-zone problems | single bad pods hidden behind the load balancer |

You need both. Run synthetics from several regions, check certificate expiry, and send `x-canary: always` (see [`yaml/gateway-api-canary.yaml`](yaml/gateway-api-canary.yaml)) to probe a canary on purpose.

### Safe production debugging ladder

| Step | Command | Risk | Notes |
|---|---|---|---|
| 1. Read | `kubectl describe`, `kubectl logs --previous`, `kubectl events --types=Warning`, `kubectl top`, traces | none | most incidents end here |
| 2. Ephemeral container | `kubectl debug -it pod/<p> --image=busybox:1.36 --target=app --profile=general` | low: shares namespaces of a live pod; cannot be removed until the pod is deleted | in PSA `restricted` namespaces use `--profile=restricted`; it sets `runAsNonRoot`, so the image must run as non-root - pod-level `runAsUser` covers it, otherwise pass `--custom` with a partial container spec |
| 3. Pod copy | `kubectl debug pod/<p> -it --copy-to=<p>-debug --container=app --set-image=app=<debug-image> -- sh` | low: copy does not keep labels by default (`--keep-labels`), so it receives no Service traffic | change images or commands freely; delete afterwards |
| 4. Node shell | `kubectl debug node/<n> -it --image=busybox:1.36 --profile=sysadmin` (host filesystem at `/host`) | high: host namespaces | run from a dedicated, audited namespace whose PSA level allows it |

Profiles in current kubectl: `general` (default), `baseline`, `restricted`, `netadmin`, `sysadmin` (older kubectl versions also had `legacy`). Grant `pods/ephemeralcontainers`, `pods/exec`, `pods/attach` and `nodes/proxy` only to on-call groups, time-bound and audited. Prefer `kubectl port-forward` over exposing debug endpoints.

## Structured logging

- One JSON object per line: `ts` (RFC 3339), `level`, `msg`, `logger`, `trace_id`, `span_id`, `request_id`, `http.method`, `http.route`, `http.status_code`, `duration_ms`, `tenant` (pseudonymised). Never log secrets, tokens or raw personal data.
- Write to stdout/stderr only. The kubelet rotates container logs (`containerLogMaxSize` 10Mi, `containerLogMaxFiles` 5 by default); anything not shipped before rotation or node loss is gone.
- Multi-line stack traces belong inside one JSON field, not across lines.
- Log level adjustable at runtime; sample repetitive debug logs; avoid per-request INFO logs on high-RPS paths unless they are your audit trail.
- Enrich with Kubernetes metadata in the agent (`k8sattributes` processor or the Fluent Bit Kubernetes filter), not in the app.

## Events as signals

| Reason (examples) | Meaning | Action |
|---|---|---|
| `FailedScheduling` | no node fits (requests, affinity, taints, PVC zone) | node autoscaler, requests, constraints |
| `FailedCreate` (ReplicaSet/Job) | admission rejected pods: quota, PSA, policy | read the message; fix manifest or quota |
| `Unhealthy` | probe failures | probe design ([02](02-reliability-and-high-availability.md)) |
| `BackOff` | CrashLoopBackOff / image pull back-off | logs `--previous`, image and pull secrets |
| `FailedMount` / `FailedAttachVolume` | volume problems (zone, permissions, CSI) | storage ([08](08-storage-and-stateful-workloads.md)) |
| `Evicted` | node pressure | requests/limits ([03](03-resource-management-and-autoscaling.md)) |

Events expire (1h default) and are de-duplicated: export them, and alert on a few reasons (`FailedCreate`, long `FailedScheduling`) rather than on all of them.

## Anti-patterns

| Anti-pattern | Consequence | Fix |
|---|---|---|
| Paging on CPU > 80% or every pod restart | alert fatigue, real incidents missed | SLO burn-rate pages; causes as tickets |
| metrics-server as the monitoring backend | no history, no alerting, 15s snapshots | Prometheus + kube-state-metrics |
| Averages for latency | tail latency invisible | histograms + percentiles |
| User IDs or pod names as labels on business metrics | cardinality explosion, cost | put them in logs/traces |
| Logs written to files inside the container | lost on restart; invisible to agents | stdout/stderr |
| Unstructured logs without trace IDs | no correlation across services | JSON + trace context |
| One sidecar collector per pod by default | resources x replicas | agent DaemonSet + gateway |
| `kubectl exec` into production pods as routine | drift, unaudited changes | read-only first, ephemeral containers, RBAC |
| Only probes, no synthetics | "all pods green" while users get TLS errors | external checks per hostname |
| Events not exported | the cause of last night's outage expired after 1h | export events |

## Reference YAML

Scrape a Service's `metrics` port with the Prometheus Operator (requires its CRDs; the `release` label must match your Prometheus `serviceMonitorSelector`):

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: api
  namespace: shop
  labels:
    release: prometheus
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: api
  endpoints:
  - port: metrics                  # named Service port
    interval: 30s
```

Fast-burn SLO alert for 99.9% availability (multi-window, burn rate 14.4):

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: api-slo
  namespace: shop
spec:
  groups:
  - name: api-availability-slo
    rules:
    - alert: APIErrorBudgetFastBurn
      expr: |
        (
          sum(rate(http_requests_total{job="api",code=~"5.."}[1h]))
            / sum(rate(http_requests_total{job="api"}[1h]))
        ) > (14.4 * 0.001)
        and
        (
          sum(rate(http_requests_total{job="api",code=~"5.."}[5m]))
            / sum(rate(http_requests_total{job="api"}[5m]))
        ) > (14.4 * 0.001)
      for: 2m
      labels:
        severity: page
      annotations:
        summary: "api burns its 99.9% error budget 14x faster than sustainable"
        runbook_url: https://runbooks.example.com/shop/api-error-budget
```

Kubernetes health queries (kube-state-metrics and cAdvisor):

```text
# Containers restarted in the last hour
increase(kube_pod_container_status_restarts_total{namespace="shop"}[1h]) > 0

# Last termination was an OOM kill
kube_pod_container_status_last_terminated_reason{namespace="shop",reason="OOMKilled"} == 1

# HPA pinned at its maximum (capacity or limit problem)
kube_horizontalpodautoscaler_status_current_replicas == kube_horizontalpodautoscaler_spec_max_replicas

# PDB currently allows no disruption (drains will block)
kube_poddisruptionbudget_status_pod_disruptions_allowed == 0

# Deployments with unavailable replicas
kube_deployment_status_replicas_unavailable > 0

# p99 latency per route from a histogram
histogram_quantile(0.99, sum by (le, route) (rate(http_request_duration_seconds_bucket{job="api"}[5m])))
```

Debugging commands:

```bash
kubectl -n shop events --types=Warning                              # recent warnings in the namespace
kubectl -n shop logs deploy/api --since=15m --all-containers        # recent logs
kubectl -n shop logs api-7d9c5b6f4-x2k8q --previous                 # logs of the crashed instance
kubectl -n shop debug -it pod/api-7d9c5b6f4-x2k8q --image=busybox:1.36 --target=app --profile=restricted
kubectl -n shop debug pod/api-7d9c5b6f4-x2k8q -it --copy-to=api-debug --container=app -- sh
kubectl -n shop delete pod api-debug                                # clean up the copy
```

## Checklist

- [ ] RED metrics (histograms) for every service; USE metrics for pools/queues; Kubernetes health alerts.
- [ ] Prometheus + kube-state-metrics + node-exporter; metrics-server only for autoscaling.
- [ ] JSON logs on stdout with trace IDs; node agent ships logs off the node; retention defined.
- [ ] OTel instrumentation; agent DaemonSet + gateway collectors; sampling strategy documented.
- [ ] SLOs defined for user-facing services; burn-rate alerts page; every page has a runbook.
- [ ] External synthetic checks per hostname, incl. TLS expiry.
- [ ] Kubernetes events exported and selectively alerted on.
- [ ] Debug access (ephemeral containers, exec, node debug) restricted to on-call, audited.
- [ ] Cardinality budget reviewed; dashboards per service (RED) and per namespace (resources, cost).

## References

- Logging architecture: https://kubernetes.io/docs/concepts/cluster-administration/logging/
- Metrics for Kubernetes system components: https://kubernetes.io/docs/concepts/cluster-administration/system-metrics/
- Traces for Kubernetes system components: https://kubernetes.io/docs/concepts/cluster-administration/system-traces/
- Resource metrics pipeline: https://kubernetes.io/docs/tasks/debug/debug-cluster/resource-metrics-pipeline/
- Debug running pods: https://kubernetes.io/docs/tasks/debug/debug-application/debug-running-pod/
- Ephemeral containers: https://kubernetes.io/docs/concepts/workloads/pods/ephemeral-containers/
- `kubectl debug` reference: https://kubernetes.io/docs/reference/kubectl/generated/kubectl_debug/
- `kubectl events` reference: https://kubernetes.io/docs/reference/kubectl/generated/kubectl_events/
- Event API: https://kubernetes.io/docs/reference/kubernetes-api/core/event-v1/
- kube-apiserver flags (`--event-ttl`): https://kubernetes.io/docs/reference/command-line-tools-reference/kube-apiserver/
- Probes: https://kubernetes.io/docs/concepts/workloads/pods/probes/
- OpenTelemetry Collector deployment: https://opentelemetry.io/docs/collector/deployment/
- OpenTelemetry Kubernetes components: https://opentelemetry.io/docs/platforms/kubernetes/collector/components/
- OpenTelemetry Operator: https://opentelemetry.io/docs/platforms/kubernetes/operator/
- Prometheus: https://prometheus.io/docs/introduction/overview/
- kube-state-metrics: https://github.com/kubernetes/kube-state-metrics
- metrics-server: https://github.com/kubernetes-sigs/metrics-server
- Google SRE Workbook, alerting on SLOs: https://sre.google/workbook/alerting-on-slos/
