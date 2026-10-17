# 10 · Production readiness checklist

> **Exam link:** every exam chapter feeds this list - [01](../01-Application-Design-and-Build/README.md) · [02](../02-Application-Deployment/README.md) · [03](../03-Application-Observability-and-Maintenance/README.md) · [04](../04-Application-Environment-Configuration-and-Security/README.md) · [05](../05-Services-and-Networking/README.md) · [06](../06-Cross-Cutting-Skills-and-Bonus-Topics/README.md). Each line names the field or tool that implements it; the "why" lives in files [01](01-application-design-principles.md)-[09](09-multi-tenancy-and-cluster-strategy.md) of this folder.

How to use: print it, or paste it into the pull-request template of a new service. Tick every line, or record an exception with a reason, an owner and an expiry date. Reference implementation: [`yaml/`](yaml/).

**Service:** ____________ **Namespace:** ____________ **Owner/on-call:** ____________ **Reviewer:** ____________ **Date:** ____________

## Workload

- [ ] Workload kind chosen deliberately (Deployment / StatefulSet / DaemonSet / Job / CronJob); no bare Pods - `kind`
- [ ] Image from the approved registry, pinned by digest, never `:latest` - `image: registry/app@sha256:...`
- [ ] Recommended labels on every object - `app.kubernetes.io/name`, `app.kubernetes.io/version`, `app.kubernetes.io/part-of`, `team`
- [ ] Dedicated ServiceAccount; API token only if the app calls the API - `serviceAccountName`, `automountServiceAccountToken: false`
- [ ] Helpers run as native sidecars with ordered start - `initContainers[].restartPolicy: Always` + `startupProbe`
- [ ] Configuration and credentials injected, not baked into the image - ConfigMap / Secret volumes

## Reliability

- [ ] At least 3 replicas for user-facing services - HPA `minReplicas: 3` (or `spec.replicas`)
- [ ] Slow boots protected - `startupProbe` with `failureThreshold x periodSeconds` >= 1.5 x P99 boot time
- [ ] Traffic gated on a dedicated readiness endpoint - `readinessProbe.httpGet.path: /readyz`
- [ ] Liveness checks only the process, never dependencies; realistic timeout - `livenessProbe`, `timeoutSeconds: 2+`
- [ ] Graceful shutdown covers endpoint-removal lag and drain - `lifecycle.preStop.sleep`, `terminationGracePeriodSeconds`, SIGTERM handler
- [ ] Voluntary disruptions budgeted - `PodDisruptionBudget` `maxUnavailable: 1`, `unhealthyPodEvictionPolicy: AlwaysAllow`
- [ ] Replicas spread over zones and nodes - `topologySpreadConstraints` (zone) + `podAntiAffinity` (hostname)
- [ ] Rollouts never reduce capacity and fail visibly - `maxUnavailable: 0`, `maxSurge`, `minReadySeconds`, `progressDeadlineSeconds`

## Resources

- [ ] Requests set from measured P95 CPU / P99 memory - `resources.requests`
- [ ] Memory limit equals memory request; CPU limit only by explicit decision - `resources.limits.memory`
- [ ] Autoscaling bounded and tuned - HPA `autoscaling/v2` with `behavior` and `maxReplicas`, or KEDA `ScaledObject`
- [ ] Replica count owned by one controller - no `spec.replicas` in Git when an HPA/KEDA manages the workload
- [ ] Namespace guard rails present - `ResourceQuota` (`requests.*`, `limits.memory`), `LimitRange` defaults
- [ ] Critical services prioritised - `priorityClassName` (quota-guarded PriorityClass)

## Security

- [ ] Namespace enforces the restricted profile - label `pod-security.kubernetes.io/enforce: restricted` + pinned `enforce-version`
- [ ] Runs as non-root - `securityContext.runAsNonRoot: true`, `runAsUser`
- [ ] No privilege escalation, no capabilities - `allowPrivilegeEscalation: false`, `capabilities.drop: ["ALL"]`
- [ ] Immutable container filesystem - `readOnlyRootFilesystem: true` + `emptyDir` (`sizeLimit`) for scratch
- [ ] Syscalls filtered - `seccompProfile.type: RuntimeDefault`
- [ ] Least-privilege RBAC for people and CI, reviewed - namespaced `Role`/`RoleBinding` to groups; `kubectl auth can-i --list`
- [ ] Secrets from an external manager, mounted as files, encrypted at rest - External Secrets Operator / Secrets Store CSI; KMS v2
- [ ] Images scanned, signed and verified at admission - cosign + Kyverno `ImageValidatingPolicy` / policy-controller; `ValidatingAdmissionPolicy`
- [ ] Cloud access without static keys - workload identity (EKS Pod Identity/IRSA, GKE Workload Identity Federation, Azure Workload Identity)

## Networking

- [ ] Default deny in both directions, DNS allowed - `NetworkPolicy` `podSelector: {}`, `policyTypes: [Ingress, Egress]`, UDP+TCP 53
- [ ] Every allowed hop explicit, on pod ports - NetworkPolicy egress (caller) + ingress (callee)
- [ ] Internal Service with named ports - `type: ClusterIP`, `targetPort: <name>`
- [ ] Exposed through the shared Gateway with TLS; not on ingress-nginx - `Gateway` / `HTTPRoute`, cert-manager
- [ ] Timeouts and retry budgets defined end to end - client timeouts; Gateway/mesh timeouts where supported
- [ ] External lookups cheap - FQDN with trailing dot or `dnsConfig.options` `ndots`; NodeLocal DNSCache

## Configuration

- [ ] Environment differences live in overlays/values only - Kustomize overlays / Helm values in Git
- [ ] Config changes trigger a rollout - Kustomize `configMapGenerator` hash or Helm `checksum/config` annotation
- [ ] No secrets in Git, values files or env literals - `ExternalSecret` / SOPS; chart `existingSecret`
- [ ] Configuration validated before it runs - `values.schema.json`; app validates config at start-up

## Delivery

- [ ] Deployed only by GitOps with drift correction - Argo CD `Application` / Flux `Kustomization`, prune + self-heal
- [ ] Same digest promoted dev -> staging -> prod by pull request - Kustomize `images[].digest`
- [ ] Progressive release gated by metrics - Argo Rollouts / Flagger, `HTTPRoute` weights
- [ ] Rollback is `git revert`; schema changes backward compatible - expand/contract migrations as a pre-deploy `Job`
- [ ] CI validates rendered manifests for the current and next Kubernetes version - `kubeconform -strict`, `pluto detect-files`

## Observability

- [ ] RED metrics exposed and scraped - `/metrics` on port `metrics` + `ServiceMonitor` or OTel Collector
- [ ] Structured JSON logs on stdout with trace IDs - node log agent (DaemonSet)
- [ ] Distributed tracing with context propagation - OpenTelemetry SDK, W3C `traceparent`
- [ ] SLOs defined; burn-rate alerts page with a runbook link - `PrometheusRule`
- [ ] Kubernetes health alerts - restarts, `OOMKilled`, HPA at max, PDB `disruptionsAllowed == 0` (kube-state-metrics)
- [ ] External synthetic checks per hostname, including TLS expiry - blackbox exporter or uptime service

## Storage

- [ ] Production volumes survive PVC deletion and bind in the right zone - StorageClass `reclaimPolicy: Retain`, `volumeBindingMode: WaitForFirstConsumer`, `allowVolumeExpansion: true`
- [ ] StatefulSet volume lifecycle explicit - `persistentVolumeClaimRetentionPolicy`
- [ ] Off-site backups with tested restores and known RPO/RTO - Velero `Schedule`, database-native PITR
- [ ] Volume usage alerting - `kubelet_volume_stats_used_bytes / kubelet_volume_stats_capacity_bytes`

## Operations

- [ ] Owner, on-call rotation and runbook recorded on the namespace - labels `team`, `cost-center`; owner/runbook annotations
- [ ] Debug access gated and audited - RBAC on `pods/exec`, `pods/ephemeralcontainers`; `kubectl debug --profile=restricted`
- [ ] Cluster on a supported minor with a rehearsed upgrade runbook - newest three minors (v1.37.1 latest as of 2026-10-17)
- [ ] Failure drills run and tracked - pod kill, node drain, zone loss (Chaos Mesh / LitmusChaos)
- [ ] Cost visible per team - requested vs used per namespace (OpenCost or provider tooling), `cost-center` label

## Exceptions

| Item | Reason | Owner | Expires |
|---|---|---|---|
| | | | |
