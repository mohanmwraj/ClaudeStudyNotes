# 08 · Architect Notes - production-grade Kubernetes design

> **Exam link:** this folder extends every exam chapter - [00](../00-Exam-Overview-and-Setup/README.md) · [01](../01-Application-Design-and-Build/README.md) · [02](../02-Application-Deployment/README.md) · [03](../03-Application-Observability-and-Maintenance/README.md) · [04](../04-Application-Environment-Configuration-and-Security/README.md) · [05](../05-Services-and-Networking/README.md) · [06](../06-Cross-Cutting-Skills-and-Bonus-Topics/README.md). Start with the [kit README](../README.md); exam logistics live in [00](../00-Exam-Overview-and-Setup/README.md).

The exam chapters teach **how**: fields, commands, speed. These notes teach **which, when and why**: defaults you can defend in a design review, the trade-offs behind them, the anti-patterns that cause outages, reference YAML, and a production readiness checklist. They are opinionated on purpose - deviate when you have a reason, and write the reason down.

## How this folder complements the exam chapters

| | Exam chapters (01-07) | Architect notes (08) |
|---|---|---|
| Question answered | "How do I create/fix this object quickly?" | "Should we build it this way, and what breaks in production?" |
| Style | fields, imperative commands, practice tasks, traps | principles, defaults, decision tables, anti-patterns, checklists |
| Tools | kubectl, Helm, Kustomize, podman/docker | plus Gateway API, cert-manager, KEDA, VPA, Karpenter, Argo CD/Flux, Argo Rollouts/Flagger, OpenTelemetry, Prometheus, Velero, Kyverno, cosign, Falco |
| When to read | before the exam | after the exam, or as a break |

**Exam week (exam on 2026-10-21):** CKAD does not test tool choices, so do not let this folder eat study time. Worth a quick read now because they reinforce exam fields: the *Recommended defaults* tables in [02](02-reliability-and-high-availability.md) (probes, PDBs, rolling updates), [03](03-resource-management-and-autoscaling.md) (requests, limits, HPA) and [04](04-security-architecture.md) (securityContext, RBAC, NetworkPolicy). Everything else: after the exam.

## Version stance and conventions

- Checked on **2026-10-17**: upstream Kubernetes **v1.37.1** is the latest release (v1.38 expected around 2026-12-16); this kit and its exam material target **v1.33-v1.35** behaviour. Feature maturity is given as "GA v1.xx" / "beta v1.xx" so you can map it to your cluster version.
- Ecosystem versions seen on the same day: Gateway API v1.6.3, Helm 4.3.1, kind v0.33.0, KEDA 2.21, Kyverno 1.19 (legacy `ClusterPolicy` deprecated).
- **"verify current status"** marks tool or version claims that move faster than this kit; re-check them before you rely on them.
- `registry.example.com/...` stands for your own images; digests in examples are fake. Runnable examples use public pinned images (`nginx:1.27-alpine`, `busybox:1.36`, `postgres:16`).
- Every topic file follows: Principles -> Recommended defaults -> Decision tables / trade-offs -> Anti-patterns -> Reference YAML -> Checklist -> References (official docs).

## Reading order

| # | File | Focus | Time |
|---|---|---|---|
| 1 | [01-application-design-principles.md](01-application-design-principles.md) | 12-factor on Kubernetes, workload choice, config/secret separation, tags vs digests, sidecars, init vs start-up work | 30 min |
| 2 | [02-reliability-and-high-availability.md](02-reliability-and-high-availability.md) | probe design, graceful shutdown, PDBs, spreading, rollout tuning, priorities, multi-zone, chaos | 45 min |
| 3 | [03-resource-management-and-autoscaling.md](03-resource-management-and-autoscaling.md) | sizing, CPU-limit debate, QoS, quotas, HPA/VPA/KEDA, node autoscaling, in-place resize, cost | 40 min |
| 4 | [04-security-architecture.md](04-security-architecture.md) | PSA, securityContext, RBAC, ServiceAccounts, NetworkPolicy, secrets, supply chain, runtime, tenancy levels | 60 min |
| 5 | [05-networking-and-traffic-management.md](05-networking-and-traffic-management.md) | Services, Ingress vs Gateway API, ingress-nginx retirement, cert-manager, mesh, DNS, egress, topology routing | 45 min |
| 6 | [06-configuration-and-delivery-gitops.md](06-configuration-and-delivery-gitops.md) | environments, Helm vs Kustomize, chart design, Argo CD/Flux, progressive delivery, rollback, deprecation CI | 40 min |
| 7 | [07-observability.md](07-observability.md) | logs/metrics/traces, OpenTelemetry patterns, Prometheus stack, SLOs, events, safe debugging | 30 min |
| 8 | [08-storage-and-stateful-workloads.md](08-storage-and-stateful-workloads.md) | StorageClass design, databases on Kubernetes, backups/DR, RWX, data locality | 30 min |
| 9 | [09-multi-tenancy-and-cluster-strategy.md](09-multi-tenancy-and-cluster-strategy.md) | tenancy model, cluster strategy, upgrade cadence, managed Kubernetes | 30 min |
| 10 | [10-production-readiness-checklist.md](10-production-readiness-checklist.md) | 59-item printable go-live checklist | 15 min |

## Exam topic -> architect file

| Exam domain | Competency (official curriculum) | Exam chapter | Architect file(s) |
|---|---|---|---|
| Application Design and Build (20%) | Define, build and modify container images | [01](../01-Application-Design-and-Build/README.md) | [01](01-application-design-principles.md) (tags vs digests), [04](04-security-architecture.md) (supply chain) |
| | Choose and use the right workload resource (Deployment, DaemonSet, CronJob, etc.) | [01](../01-Application-Design-and-Build/README.md) | [01](01-application-design-principles.md), [08](08-storage-and-stateful-workloads.md) (StatefulSets vs operators) |
| | Understand multi-container Pod design patterns (e.g. sidecar, init and others) | [01](../01-Application-Design-and-Build/README.md) | [01](01-application-design-principles.md) (native sidecars, init vs start-up) |
| | Utilize persistent and ephemeral volumes | [01](../01-Application-Design-and-Build/README.md) | [08](08-storage-and-stateful-workloads.md) |
| Application Deployment (20%) | Use Kubernetes primitives to implement common deployment strategies (e.g. blue/green or canary) | [02](../02-Application-Deployment/README.md) | [05](05-networking-and-traffic-management.md) (Gateway API weights), [06](06-configuration-and-delivery-gitops.md) (progressive delivery) |
| | Understand Deployments and how to perform rolling updates | [02](../02-Application-Deployment/README.md) | [02](02-reliability-and-high-availability.md) (rollout tuning) |
| | Use the Helm package manager to deploy existing packages | [02](../02-Application-Deployment/README.md) | [06](06-configuration-and-delivery-gitops.md) (Helm vs Kustomize, chart design) |
| | Kustomize | [02](../02-Application-Deployment/README.md) | [06](06-configuration-and-delivery-gitops.md), [01](01-application-design-principles.md) (generators, digests) |
| Application Observability and Maintenance (15%) | Understand API deprecations | [03](../03-Application-Observability-and-Maintenance/README.md) | [06](06-configuration-and-delivery-gitops.md) (CI hygiene), [09](09-multi-tenancy-and-cluster-strategy.md) (upgrades) |
| | Implement probes and health checks | [03](../03-Application-Observability-and-Maintenance/README.md) | [02](02-reliability-and-high-availability.md) (probe design) |
| | Use built-in CLI tools to monitor Kubernetes applications | [03](../03-Application-Observability-and-Maintenance/README.md) | [07](07-observability.md) |
| | Utilize container logs | [03](../03-Application-Observability-and-Maintenance/README.md) | [07](07-observability.md) (structured logging) |
| | Debugging in Kubernetes | [03](../03-Application-Observability-and-Maintenance/README.md) | [07](07-observability.md) (safe production debugging) |
| Application Environment, Configuration and Security (25%) | Discover and use resources that extend Kubernetes (CRD, Operators) | [04](../04-Application-Environment-Configuration-and-Security/README.md) | [08](08-storage-and-stateful-workloads.md) (database operators), [03](03-resource-management-and-autoscaling.md) (KEDA, VPA), [06](06-configuration-and-delivery-gitops.md) (GitOps controllers) |
| | Understand authentication, authorization and admission control | [04](../04-Application-Environment-Configuration-and-Security/README.md) | [04](04-security-architecture.md) (RBAC, PSA, admission policies) |
| | Understand requests, limits, quotas | [04](../04-Application-Environment-Configuration-and-Security/README.md) | [03](03-resource-management-and-autoscaling.md), [09](09-multi-tenancy-and-cluster-strategy.md) |
| | Understand ConfigMaps | [04](../04-Application-Environment-Configuration-and-Security/README.md) | [01](01-application-design-principles.md), [06](06-configuration-and-delivery-gitops.md) (config rollout) |
| | Create & consume Secrets | [04](../04-Application-Environment-Configuration-and-Security/README.md) | [04](04-security-architecture.md) (secrets management) |
| | Understand ServiceAccounts | [04](../04-Application-Environment-Configuration-and-Security/README.md) | [04](04-security-architecture.md) (ServiceAccount hygiene) |
| | Understand Application Security (SecurityContexts, Capabilities, etc.) | [04](../04-Application-Environment-Configuration-and-Security/README.md) | [04](04-security-architecture.md) (securityContext baseline) |
| Services and Networking (20%) | Demonstrate basic understanding of NetworkPolicies | [05](../05-Services-and-Networking/README.md) | [04](04-security-architecture.md), [05](05-networking-and-traffic-management.md) |
| | Provide and troubleshoot access to applications via services | [05](../05-Services-and-Networking/README.md) | [05](05-networking-and-traffic-management.md) (Service design, DNS) |
| | Use Ingress rules to expose applications | [05](../05-Services-and-Networking/README.md) | [05](05-networking-and-traffic-management.md) (Ingress vs Gateway API, ingress-nginx retirement) |
| Cross-cutting | HPA, PDB, scheduling, labels, namespaces | [06](../06-Cross-Cutting-Skills-and-Bonus-Topics/README.md) | [02](02-reliability-and-high-availability.md), [03](03-resource-management-and-autoscaling.md), [09](09-multi-tenancy-and-cluster-strategy.md) |

## yaml/ index

| File | What it shows | Requires |
|---|---|---|
| [`yaml/namespace-baseline.yaml`](yaml/namespace-baseline.yaml) | Namespace `shop` with PSA labels (enforce `restricted`, pinned version), ResourceQuota, LimitRange, token-less `default` SA, default-deny NetworkPolicy + allow-DNS | a policy-enforcing CNI for the NetworkPolicies |
| [`yaml/rbac-namespace-developer.yaml`](yaml/rbac-namespace-developer.yaml) | least-privilege `developer` Role, group RoleBindings (incl. built-in `view`), CI ServiceAccount | namespace-baseline |
| [`yaml/production-deployment-template.yaml`](yaml/production-deployment-template.yaml) | hardened Deployment (probes, resources, securityContext, zone spread, anti-affinity, preStop, safe rollout) + ConfigMap, Service, PDB, HPA | namespace-baseline; metrics-server for the HPA |
| [`yaml/networkpolicy-three-tier.yaml`](yaml/networkpolicy-three-tier.yaml) | gateway -> frontend -> api -> db allow-list, Prometheus scrape, CIDR egress | namespace-baseline; policy-enforcing CNI |
| [`yaml/gateway-api-canary.yaml`](yaml/gateway-api-canary.yaml) | platform-owned Gateway, HTTP->HTTPS redirect, app-owned HTTPRoute with 90/10 weights and header override | Gateway API CRDs + an implementation; TLS Secret or cert-manager |
| [`yaml/keda-scaledobject-example.yaml`](yaml/keda-scaledobject-example.yaml) | queue worker scaled 0..30 on RabbitMQ queue length, TriggerAuthentication, broker egress policy | KEDA; a RabbitMQ connection Secret |

All files parse, pass the kit QA lint and validate against the strict Kubernetes v1.33 and v1.35 JSON schemas (Gateway API and KEDA objects against their CRD schemas).

Try them on a lab cluster in this order:

```bash
kubectl apply -f yaml/namespace-baseline.yaml
kubectl apply -f yaml/rbac-namespace-developer.yaml
kubectl apply -f yaml/production-deployment-template.yaml
kubectl -n shop rollout status deploy/api
kubectl apply -f yaml/networkpolicy-three-tier.yaml
# Optional - needs KEDA installed:
kubectl apply -f yaml/keda-scaledobject-example.yaml
# Optional - needs Gateway API CRDs and a Gateway implementation:
kubectl apply --server-side -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.6.3/standard-install.yaml
kubectl apply -f yaml/gateway-api-canary.yaml
# Clean up
kubectl delete namespace shop infra-gateway --ignore-not-found
```

Lab notes: NetworkPolicies are only enforced by a CNI that supports them (Calico, Cilium, ...); check whether your local cluster's default CNI does. The HPA needs metrics-server. Zone spreading is soft (`ScheduleAnyway`), so the template also schedules on a single-node cluster.
