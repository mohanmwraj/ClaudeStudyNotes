# 09 · Multi-tenancy and cluster strategy

> **Exam link:** [04 · Environment, Configuration and Security](../04-Application-Environment-Configuration-and-Security/README.md) (quotas, RBAC, ServiceAccounts) · [05 · Services and Networking](../05-Services-and-Networking/README.md) (NetworkPolicies) · [06 · Cross-Cutting Skills](../06-Cross-Cutting-Skills-and-Bonus-Topics/README.md) (namespaces, labels) · [03 · Observability and Maintenance](../03-Application-Observability-and-Maintenance/README.md) (API deprecations). The exam gives you one namespace per task; a platform gives hundreds of teams safe namespaces and keeps the clusters upgraded.

How many clusters, who shares them, and how they stay on supported versions are the most expensive decisions to change later. Make them explicitly and write them down.

## Principles

1. **Name your tenancy model.** Teams of one company (trusted, cooperative) and external customers (untrusted, possibly hostile) need different isolation.
2. **The namespace is the unit of tenancy:** ownership, RBAC, policy, quota and cost. Create namespaces through automation with a baseline, never by hand.
3. **Isolation is layered** - RBAC, PSA, NetworkPolicy, quota, node isolation, control-plane isolation. Choose the level per risk, not per habit.
4. **Fewer, well-run clusters;** add clusters for hard boundaries (prod vs non-prod, compliance, regions, blast radius).
5. **Cluster-scoped objects are shared contracts** (CRDs, webhooks, operators, StorageClasses, PriorityClasses, GatewayClasses): platform-owned, versioned, change-reviewed.
6. **Upgrade continuously.** About three minor releases per year, each supported for roughly 14 months: upgrade debt compounds.
7. **Managed control planes by default;** spend your effort on the platform layer, not on etcd.

## Recommended defaults

| Area | Default | Implemented by |
|---|---|---|
| Tenancy unit | namespace per application (or bounded context) per environment; teams own several namespaces | GitOps "tenants" repo |
| Namespace baseline | PSA labels, ResourceQuota, LimitRange, default-deny + DNS NetworkPolicies, hardened `default` SA, team RoleBindings, ownership labels | [`yaml/namespace-baseline.yaml`](yaml/namespace-baseline.yaml), [`yaml/rbac-namespace-developer.yaml`](yaml/rbac-namespace-developer.yaml) |
| Ownership metadata | labels `team`, `cost-center`, `environment`, `data-classification`; annotations for contact and runbook | admission policy requires them |
| Shared ingress | one Gateway per environment, namespaces opt in by label | [`yaml/gateway-api-canary.yaml`](yaml/gateway-api-canary.yaml) |
| Clusters | per region: separate prod and non-prod clusters at minimum | IaC + GitOps fleet management |
| Versions | stay within the newest three minors; upgrade one minor at a time, non-prod first | upgrade runbook below |
| Control plane | managed (EKS, AKS, GKE or similar) | provider |

## Decision tables / trade-offs

### Isolation per tenant

| Layer | Default per tenant namespace | Stronger option |
|---|---|---|
| API access | RoleBindings to the tenant's groups; no cluster-scoped rights | separate virtual control plane (vcluster) |
| Pod privileges | PSA `restricted` | + user namespaces (`hostUsers: false`), sandboxed `RuntimeClass` |
| Network | default-deny ingress/egress, explicit allows | CNI cluster-wide policies (`ClusterNetworkPolicy`, verify current status), dedicated egress IPs |
| Compute | ResourceQuota + LimitRange; PriorityClass quota | dedicated node pools (taints/tolerations + node affinity) |
| Data | Secrets per namespace, external secret manager paths per tenant | separate KMS keys, separate clusters |
| Control plane | shared | vcluster / hosted control planes / dedicated cluster |

### Self-service tenancy tools

| Tool | What it adds | Status (Oct 2026) |
|---|---|---|
| Plain GitOps (namespace + baseline per PR) | simple, auditable onboarding | recommended starting point |
| Kyverno generate rules (`GeneratingPolicy`) | create quota/NetworkPolicy/RoleBindings automatically when a namespace appears | Kyverno CEL policy types stable since 1.18 |
| Capsule | `Tenant` object grouping namespaces, tenant-owner self-service, enforced policies | CNCF Sandbox |
| vcluster | virtual clusters (own API server, own CRDs) whose pods run on the host cluster | active open-source project (verify current status) |
| Hierarchical Namespace Controller (HNC) | namespace trees with inherited policies | **archived April 2025** (now under `kubernetes-retired`) - do not adopt |

### Cluster strategy

| Model | Pros | Cons | Use when |
|---|---|---|---|
| One shared cluster for every environment | cheapest | upgrades and CRD changes hit prod first; noisy neighbours; weak compliance story | small, non-critical estates |
| **Prod + non-prod per region** | upgrades and cluster-scoped changes are tested before prod; smaller blast radius | add-ons run twice | the recommended minimum |
| Cluster per environment (dev, staging, prod) | staging can mirror prod exactly | more cost and operations | critical or regulated systems |
| Cells: several identical prod clusters, each serving a slice of users | bounded blast radius; cluster-level blue/green | fleet automation and global routing required | large scale, tier-0 services |
| Cluster per team | autonomy | sprawl, drift, duplicated platform work | only with strong fleet tooling (Cluster API, GitOps fleet) |
| Cluster per customer | hard isolation | cost per tenant | SaaS with hostile or regulated tenants |

## Upgrade strategy

Release facts: Kubernetes ships about **three minor releases per year**; each minor gets roughly **14 months** of patch support (12 months standard + a 2-month maintenance mode), and the project maintains the three most recent minors. As of 2026-10-17 the latest release is **v1.37.1** (2026-09-15); **v1.38** is expected around 2026-12-16; end-of-life dates: v1.34 on 2026-10-27, v1.35 on 2027-02-28, v1.36 on 2027-06-28, v1.37 on 2027-10-28.

Version skew rules that shape the plan: upgrade the control plane **one minor at a time**; kubelets may be up to **three minors older** than the API server, so node pools can lag briefly; `kubectl` is supported within **one minor** of the API server.

Runbook per minor upgrade:

1. **Read** the release notes and the deprecated API migration guide for the target version.
2. **Scan** for removed APIs: CI runs `kubeconform`/`pluto` against the target ([06](06-configuration-and-delivery-gitops.md)); in the live cluster check `apiserver_requested_deprecated_apis` and `pluto detect-helm`.
3. **Check add-on compatibility:** CNI, CSI drivers, Gateway implementation, cert-manager, mesh, GitOps controller, node autoscaler, policy engine, observability agents.
4. **Upgrade non-prod first** and soak for one to two weeks with smoke tests and a small chaos run.
5. **Upgrade the control plane, then node pools** (surge or blue/green node pools). Drains must succeed: check PDBs (`disruptionsAllowed`), `safe-to-evict`/`do-not-disrupt` annotations, single-replica workloads.
6. **Bump PSA `enforce-version`** deliberately after reviewing warnings at `latest`.
7. **Track** versions per cluster on a dashboard and alert well before end of life.

For high-risk jumps or major platform changes (new CNI, new cluster layout), prefer **blue/green clusters**: build the new cluster, sync it from Git, shift traffic gradually - this requires stateless workloads or replicated data.

## Managed Kubernetes considerations

| Topic | EKS | AKS | GKE |
|---|---|---|---|
| Version support | 14 months standard support, then 12 months extended support at extra cost (enabled by default) | one year of community support plus one year of opt-in long-term support (LTS; pricing tier: verify current status) | release channels (Rapid, Regular, Stable, Extended - Extended keeps a minor up to 24 months) |
| Workload identity | EKS Pod Identity or IRSA | Microsoft Entra Workload ID | Workload Identity Federation for GKE |
| Node autoscaling | Karpenter, EKS Auto Mode, or Cluster Autoscaler | cluster autoscaler, node auto-provisioning | cluster autoscaler, node auto-provisioning, Autopilot |
| Gateway API | AWS Load Balancer Controller / AWS Gateway API Controller (VPC Lattice) | Application Gateway for Containers | GKE Gateway controller |

Rows other than version support are summaries of provider documentation as of Oct 2026 (verify current status). Provider-independent checks:

- Shared responsibility: the provider runs the control plane; you own nodes (unless you use a fully managed mode), add-ons, workloads, upgrade scheduling and data.
- Private API endpoints, control-plane audit log export, and the paid control-plane SLA tier for production.
- IP address planning: VPC-native pod networking can exhaust subnets; size CIDRs for the maximum pod count.
- Maintenance windows and auto-upgrade settings that match your change process.
- Extended support is a bill for upgrade debt: budget engineering time instead.

## Anti-patterns

| Anti-pattern | Consequence | Fix |
|---|---|---|
| Namespaces created by hand without ownership labels | orphaned resources, unknown costs, no on-call | namespace-as-a-service via GitOps + required labels |
| Tenants with cluster-scoped rights (CRDs, webhooks, ClusterRoles) in a shared cluster | one tenant can break or own all others | platform owns cluster scope; vcluster if tenants need it |
| Namespaces as the only boundary for hostile tenants | kernel/node escape exposes everyone | sandboxed runtimes, node isolation or separate clusters |
| Prod and experiments in one cluster | experiments break prod (CRDs, quotas, upgrades) | separate prod and non-prod clusters |
| Upgrading only when forced | multi-version jumps, extended-support fees, removed APIs found in a hurry | upgrade every release or two, non-prod first |
| Snowflake clusters configured by hand | drift, unreproducible DR | IaC + GitOps for every cluster |
| Cluster per team without fleet tooling | sprawl, inconsistent security | shared clusters with strong tenancy, or real fleet management |
| Adopting HNC in a new design | archived project | GitOps, Kyverno generation, or Capsule |

## Reference YAML

- Tenant namespace baseline: [`yaml/namespace-baseline.yaml`](yaml/namespace-baseline.yaml)
- Tenant team RBAC: [`yaml/rbac-namespace-developer.yaml`](yaml/rbac-namespace-developer.yaml)

Tenants repository layout for GitOps onboarding:

```text
platform-tenants/
├── base/                         namespace-baseline + rbac (as in yaml/), parameterised via Kustomize replacements
├── tenants/
│   ├── shop-prod/                kustomization.yaml: namespace "shop", team groups, quota overrides
│   ├── shop-staging/
│   └── payments-prod/
└── cluster-scoped/               PriorityClasses, StorageClasses, GatewayClass, admission policies (platform only)
```

Upgrade readiness checks:

```bash
kubectl version                                                    # client/server versions (skew)
kubectl get nodes -o custom-columns=NAME:.metadata.name,KUBELET:.status.nodeInfo.kubeletVersion
kubectl get --raw /metrics | grep apiserver_requested_deprecated_apis       # deprecated APIs still being called
pluto detect-helm -owide --target-versions k8s=v1.38.0                       # Helm releases using APIs removed by the target
kubectl get pdb -A -o custom-columns=NS:.metadata.namespace,NAME:.metadata.name,ALLOWED:.status.disruptionsAllowed
```

## Checklist

- [ ] Tenancy model documented (who shares what, trust level, isolation level per tenant type).
- [ ] Namespaces created only via automation with the full baseline and ownership labels.
- [ ] Tenants have no cluster-scoped permissions; cluster-scoped objects are platform-owned and reviewed.
- [ ] Prod and non-prod run in separate clusters (per region at minimum).
- [ ] Every cluster is reproducible from IaC + GitOps.
- [ ] All clusters within the three supported minors; upgrade runbook rehearsed; EOL dates tracked.
- [ ] Removed-API scans run in CI against the next version and in clusters before upgrades.
- [ ] Node-pool upgrades succeed without manual intervention (PDBs and annotations reviewed).
- [ ] Managed-provider settings reviewed: private endpoint, audit logs, SLA tier, IP capacity, maintenance windows.

## References

- Multi-tenancy: https://kubernetes.io/docs/concepts/security/multi-tenancy/
- Namespaces: https://kubernetes.io/docs/concepts/overview/working-with-objects/namespaces/
- Resource quotas: https://kubernetes.io/docs/concepts/policy/resource-quotas/
- Limit ranges: https://kubernetes.io/docs/concepts/policy/limit-range/
- Releases (current versions, EOL dates): https://kubernetes.io/releases/
- Patch releases and support period: https://kubernetes.io/releases/patch-releases/
- Release cycle: https://kubernetes.io/releases/release/
- Version skew policy: https://kubernetes.io/releases/version-skew-policy/
- Upgrading a cluster: https://kubernetes.io/docs/tasks/administer-cluster/cluster-upgrade/
- Deprecated API migration guide: https://kubernetes.io/docs/reference/using-api/deprecation-guide/
- Capsule: https://projectcapsule.dev/
- vcluster: https://www.vcluster.com/docs
- Hierarchical Namespace Controller (archived): https://github.com/kubernetes-retired/hierarchical-namespaces
- Cluster API: https://cluster-api.sigs.k8s.io/
- Amazon EKS Kubernetes versions: https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions.html
- AKS supported Kubernetes versions: https://learn.microsoft.com/en-us/azure/aks/supported-kubernetes-versions
- GKE release channels: https://cloud.google.com/kubernetes-engine/docs/concepts/release-channels
