# 06 · Configuration and delivery (GitOps)

> **Exam link:** [02 · Application Deployment](../02-Application-Deployment/README.md) (Helm, Kustomize, rolling updates, blue/green and canary) · [03 · Observability and Maintenance](../03-Application-Observability-and-Maintenance/README.md) (API deprecations) · [04 · Environment, Configuration and Security](../04-Application-Environment-Configuration-and-Security/README.md) (ConfigMaps). The exam has you run `helm` and `kubectl apply -k` by hand; in production nobody should.

Delivery is where reliability is won or lost: most incidents start with a change. The goal is that every change is a reviewed diff, reaches production through the same path as every other change, is released progressively, and can be undone in one step.

## Principles

1. **Git is the source of truth; the cluster converges to it.** Pull-based GitOps: an in-cluster controller applies what is in Git and reports drift.
2. **Build once, promote by digest.** The artifact that passed staging is byte-identical to what runs in production.
3. **Review rendered output,** not just templates: the diff of final manifests is what changes the cluster.
4. **Release progressively, gated by metrics;** roll back by reverting.
5. **Configuration is code:** versioned, reviewed, rolled out and rolled back like code.
6. **Keep templating shallow.** Logic in templates makes output unreviewable.
7. **Shift validation left:** schemas, policies and API deprecations are checked in CI against the target Kubernetes version.

## Recommended defaults

| Area | Default | Why |
|---|---|---|
| Environments | separate prod and non-prod clusters; namespaces for dev/test/preview inside non-prod | test upgrades and cluster-scoped changes before prod |
| Own applications | Kustomize base + overlays (+ components) | plain, reviewable YAML; built into kubectl |
| Third-party software | Helm charts, pinned versions, values in Git | packaging, dependencies, upstream maintenance |
| Deployment mechanism | Argo CD or Flux, automated sync with prune + self-heal | drift correction, audit trail, no cluster credentials in CI |
| Image references | digest per environment overlay, promoted by pull request | immutable promotion |
| Config changes | hash-suffixed generated ConfigMaps / `checksum/config` annotation | every change is a rollout with a rollback point |
| Releases | canary with automated metric analysis (Argo Rollouts or Flagger) for tier-0/1 services | small blast radius, automatic abort |
| Rollback | `git revert` of the promotion commit | auditable; GitOps does not fight it |
| CI validation | render -> `kubeconform -strict` -> policy tests -> `pluto` for the next Kubernetes version | catch removed APIs and typos before merge |

## Decision tables / trade-offs

### Environments: namespaces or clusters?

| Factor | Namespaces in one cluster | Separate clusters |
|---|---|---|
| Blast radius / noisy neighbours | soft isolation | hard isolation |
| Cluster-scoped objects (CRDs, webhooks, operators) | one version shared by all environments | each environment can differ - test before prod |
| Kubernetes upgrades | every environment upgrades at once | upgrade non-prod first |
| Cost and operational effort | lower | higher (control planes, add-ons, observability) |
| Compliance boundary | weak | strong |
| Good for | dev, test, ephemeral preview environments | prod vs non-prod (minimum), regulated workloads |

### Helm, Kustomize or both

| | Helm | Kustomize | Both (render Helm, patch with Kustomize) |
|---|---|---|---|
| Model | Go templates + values; packaged, versioned charts; release history | overlays and patches over plain YAML; no templating | vendor chart plus local patches |
| Best for | distributing software to many consumers; third-party add-ons | your own services with modest environment differences | adopting upstream charts without forking them |
| Strengths | OCI distribution, dependencies, hooks, `helm rollback`, `values.schema.json` | reviewable YAML, `kubectl apply -k`, generators with content hashes, components, `replacements` | no fork; org-specific changes stay small |
| Weaknesses | template complexity, whitespace bugs, values sprawl, CRD limitations | no packaging or lifecycle hooks; limited logic (by design) | two tools to debug; ordering subtleties |
| GitOps support | Argo CD and Flux render charts natively | native in both | Argo CD (Kustomize `--enable-helm`), Flux (`HelmRelease` `postRenderers`) |

Prefer the current Kustomize fields (`resources`, `labels`, `patches`, `replacements`); `bases`, `commonLabels`, `patchesStrategicMerge`, `patchesJson6902` and `vars` are deprecated. Helm 4 (released Nov 2025; 4.3.1 is current as of Oct 2026) keeps the core CLI; check `helm version` and `helm <cmd> --help` before scripting flags.

### Chart design best practices

| Practice | Why |
|---|---|
| Ship `values.schema.json` | validated on `install`, `upgrade`, `lint` and `template`: typos fail fast |
| Names and labels from named templates in `_helpers.tpl`; selector labels never contain the version | `spec.selector` is immutable - a version in it breaks upgrades |
| `required` for mandatory values; documented, camelCase keys; shallow nesting | predictable `--set` overrides, self-documenting charts |
| No secrets in values; accept `existingSecret` or create an `ExternalSecret` | values end up in Git and in the release Secret (`sh.helm.release.v1.<release>.v<rev>`) |
| `checksum/config` annotation on the pod template | pods roll when the ConfigMap changes |
| CRDs managed outside the chart's `crds/` directory for anything you will upgrade | Helm installs `crds/` only on install - never upgrades or deletes them |
| Avoid `lookup` and random functions | `helm template` (used by GitOps renderers) returns empty `lookup` results; random output causes perpetual diffs |
| Version the chart (`version`) separately from the app (`appVersion`); publish to an OCI registry | reproducible, signed artifacts |
| CI: `helm lint --strict`, `helm template \| kubeconform -strict`, chart tests | catch errors before a cluster does |

### Argo CD or Flux

| | Argo CD | Flux |
|---|---|---|
| Model | `Application` / `ApplicationSet` (generators for clusters, environments, PRs) | sources (`GitRepository`, `OCIRepository`, `HelmRepository`) + `Kustomization` / `HelmRelease` |
| Ordering | sync waves (`argocd.argoproj.io/sync-wave`, lowest first) and hooks (`PreSync`, `Sync`, `PostSync`, `SyncFail`) | `dependsOn`, `wait`, health checks |
| Drift | OutOfSync status; `selfHeal: true` reverts manual changes; `prune: true` deletes removed objects | reconciles every `interval`; server-side apply dry-run detects and corrects drift; `prune: true` |
| Multi-tenancy | AppProjects restrict repos, destinations and resource kinds | per-tenant ServiceAccount impersonation |
| UX | rich web UI, SSO, RBAC | CLI and Kubernetes-native APIs |
| Project | CNCF graduated | CNCF graduated |

Both are solid; pick one per organisation. Protect the GitOps repository like production access (branch protection, CODEOWNERS, required reviews) - **write access to it is write access to the cluster.**

### Progressive delivery

| | Argo Rollouts | Flagger |
|---|---|---|
| Object | `Rollout` (replaces a Deployment, or references one via `workloadRef`) | `Canary` (wraps an existing Deployment; creates primary/canary copies) |
| Strategies | canary steps (`setWeight`, `pause`, `analysis`), blue/green (active/preview Services) | canary, A/B (header/cookie), blue/green |
| Traffic | ingress controllers, meshes, Gateway API via the `argoproj-labs/gatewayAPI` plugin | meshes and ingress controllers; Gateway API `HTTPRoute` natively |
| Analysis | `AnalysisTemplate` (Prometheus, Datadog, web, Job, ...) | built-in success-rate/latency checks + custom metric templates, webhooks |

Gate every step on **canary-vs-baseline** comparisons (error rate, p99 latency, saturation), not on "no alerts fired". Feature flags (for example via OpenFeature) complement this: deploying code and releasing a feature become separate decisions.

### Rolling out configuration changes

| Mechanism | Rollout? | Rollback? | Notes |
|---|---|---|---|
| Edit a ConfigMap in place | no restart; env never updates; mounted files update eventually; `subPath` never | none | different pods see different config for a while |
| Hash-suffixed name (Kustomize `configMapGenerator`) | yes, new ReplicaSet | yes, via Git revert | GitOps prune deletes old ConfigMaps, so `kubectl rollout undo` to an old ReplicaSet can break - revert in Git instead |
| `checksum/config` annotation (Helm) | yes | `helm rollback` / Git revert | same idea for Helm |
| Reloader-style controller | restart on change | no | convenient, but not a rollout you can review |
| App hot-reload of mounted files | no restart | no | must handle the atomic symlink swap; good for feature toggles |

### Rollback strategy

| Method | Use when | Caveat |
|---|---|---|
| `git revert` of the promotion commit | default | also reverts config; fully audited |
| Abort in Argo Rollouts / automatic Flagger rollback | during a progressive release | needs good metrics |
| `kubectl rollout undo` | emergency, with auto-sync paused | creates drift; GitOps re-applies Git unless you revert there too |
| `helm rollback <release> <rev>` | Helm releases not managed by GitOps | values come from the old revision |
| Database | never roll back schemas; forward-only expand/contract migrations | app N must run against schema N and N+1 |

## API-deprecation hygiene in CI

Policy reminder: beta APIs are deprecated at most 9 months or 3 minor releases after introduction and stop being served 9 months or 3 minor releases after deprecation (whichever is longer). Removed APIs you will still meet in old charts: `extensions/v1beta1` and `apps/v1beta1|2` (v1.16), `networking.k8s.io/v1beta1` Ingress (v1.22), `batch/v1beta1` CronJob, `policy/v1beta1` PDB and PodSecurityPolicy (v1.25), `autoscaling/v2beta2` (v1.26), `flowcontrol.apiserver.k8s.io/v1beta3` (v1.32).

```bash
#!/usr/bin/env bash
set -euo pipefail
TARGET=1.35.0                     # the version you run
NEXT=v1.36.0                      # the version you will upgrade to next

# 1. Render exactly what GitOps will apply
kubectl kustomize overlays/prod > rendered.yaml
helm template shop charts/shop -f values/prod.yaml >> rendered.yaml

# 2. Schema validation (unknown fields, wrong types, removed APIs) incl. CRDs
kubeconform -strict -summary -kubernetes-version "$TARGET" \
  -schema-location default \
  -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json' \
  rendered.yaml

# 3. Deprecated/removed apiVersions for the NEXT upgrade
pluto detect-files -d . --target-versions k8s="$NEXT"
```

In live clusters: `pluto detect-helm -owide` for Helm release manifests, `kubectl` deprecation warnings, the API server metric `apiserver_requested_deprecated_apis`, and audit annotations. Convert old manifests with the `kubectl convert` plugin (not installed by default).

## Anti-patterns

| Anti-pattern | Consequence | Fix |
|---|---|---|
| `kubectl apply` / `helm upgrade` from laptops or CI with cluster-admin | no audit trail, credential sprawl, drift | GitOps pull model |
| Rebuilding images per environment | prod runs untested bits | promote the digest |
| `:latest` or mutable tags in Git | "same" manifest, different code | digests |
| Secrets in values files or Git | leakage via history and forks | ESO/CSI/SOPS ([04](04-security-architecture.md)) |
| One mega-chart with hundreds of values | unreviewable output, fragile upgrades | small charts or Kustomize; review rendered diffs |
| Templates with `lookup`, random values, timestamps | perpetual diffs in GitOps | deterministic rendering |
| CRDs in a chart's `crds/` directory expected to upgrade | stale CRDs, broken controllers | separate CRD lifecycle (own chart, first sync wave) |
| Manual hotfix with `kubectl edit` while self-heal is on | the fix is reverted minutes later | change Git (or pause sync deliberately) |
| Canary "analysis" = waiting 10 minutes | regressions ship anyway | metric-based canary vs baseline |
| Database migration coupled to app rollback | rollback impossible or destructive | expand/contract, forward-only |
| Ignoring deprecation warnings until upgrade week | blocked upgrades | CI check against the next version |

## Reference YAML

Repository layout for one service (Kustomize):

```text
shop-deploy/
├── base/                    deployment.yaml, service.yaml, hpa.yaml, pdb.yaml, kustomization.yaml
├── components/
│   └── canary/              optional HTTPRoute weights / Rollout
└── overlays/
    ├── dev/                 kustomization.yaml: images[].digest, replicas/limits patches, config literals
    ├── staging/
    └── prod/
```

Argo CD Application with automated sync, prune and self-heal (requires Argo CD):

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: shop-prod
  namespace: argocd
spec:
  project: shop                      # AppProject limits repos, destinations, kinds
  source:
    repoURL: https://git.example.com/shop/shop-deploy.git
    targetRevision: main
    path: overlays/prod
  destination:
    server: https://kubernetes.default.svc
    namespace: shop
  syncPolicy:
    automated:
      prune: true                    # delete objects removed from Git
      selfHeal: true                 # revert manual drift
    syncOptions:
    - ServerSideApply=true
    - PruneLast=true
```

Ordering with sync waves (annotation on any resource; lowest wave first):

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: shop
  annotations:
    argocd.argoproj.io/sync-wave: "-2"   # namespaces/CRDs first, then config (-1), apps (0), smoke tests (PostSync hook)
```

Flux equivalent: a Git source plus a Flux `Kustomization` (a Flux CRD, not the `kustomization.yaml` file) with an explicit dependency (requires Flux; replace `<git-host>`):

```yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: GitRepository
metadata:
  name: shop-deploy
  namespace: flux-system
spec:
  interval: 1m
  url: https://<git-host>/shop/shop-deploy.git
  ref:
    branch: main
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: shop-prod
  namespace: flux-system
spec:
  interval: 5m
  path: ./overlays/prod
  prune: true
  wait: true                         # healthy before dependants reconcile
  timeout: 5m
  sourceRef:
    kind: GitRepository
    name: shop-deploy
  dependsOn:
  - name: platform-crds
```

Argo Rollouts canary driving the HTTPRoute weights from [`yaml/gateway-api-canary.yaml`](yaml/gateway-api-canary.yaml) (requires Argo Rollouts and its Gateway API plugin; `success-rate` is an `AnalysisTemplate` you define with your Prometheus query):

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Rollout
metadata:
  name: web
  namespace: shop
spec:
  replicas: 6
  revisionHistoryLimit: 3
  selector:
    matchLabels:
      app.kubernetes.io/name: web
  template:
    metadata:
      labels:
        app.kubernetes.io/name: web
    spec:
      containers:
      - name: web
        image: registry.example.com/shop/web:2.3.0
        ports:
        - name: http
          containerPort: 8080
  strategy:
    canary:
      stableService: web-stable
      canaryService: web-canary
      trafficRouting:
        plugins:
          argoproj-labs/gatewayAPI:
            httpRoute: web           # the HTTPRoute whose backendRefs weights are managed
            namespace: shop
      steps:
      - setWeight: 10
      - pause: {duration: 5m}
      - analysis:
          templates:
          - templateName: success-rate
      - setWeight: 50
      - pause: {duration: 10m}
      - setWeight: 100
```

Helm: roll pods on config change (template fragment - Helm syntax, not plain YAML):

```yaml
spec:
  template:
    metadata:
      annotations:
        checksum/config: {{ include (print $.Template.BasePath "/configmap.yaml") . | sha256sum }}
```

## Checklist

- [ ] Prod and non-prod are separate clusters; non-prod uses namespaces for dev/test/preview.
- [ ] Own apps in Kustomize (or small charts); third-party software via pinned Helm charts with values in Git.
- [ ] Charts ship `values.schema.json`, contain no secrets, keep selectors version-free, manage CRDs separately.
- [ ] GitOps controller (Argo CD/Flux) applies everything; humans and CI have no standing write access to clusters.
- [ ] Sync ordering explicit (waves / `dependsOn`); prune and self-heal on; GitOps repo protected.
- [ ] Images promoted by digest through PRs; nothing rebuilt per environment.
- [ ] Config changes produce new rollouts (hash suffix or checksum).
- [ ] Tier-0/1 services release via metric-gated canaries; rollback = `git revert`.
- [ ] Database migrations are backward compatible (expand/contract).
- [ ] CI renders manifests and runs kubeconform (strict, target version) and pluto (next version).

## References

- Helm docs: https://helm.sh/docs/
- Helm chart best practices: https://helm.sh/docs/chart_best_practices/
- Helm values best practices: https://helm.sh/docs/chart_best_practices/values/
- Helm charts (schema files, CRD limitations): https://helm.sh/docs/topics/charts/
- Helm tips and tricks (checksum annotation): https://helm.sh/docs/howto/charts_tips_and_tricks/
- Kustomize in kubectl: https://kubernetes.io/docs/tasks/manage-kubernetes-objects/kustomization/
- Deprecated API migration guide: https://kubernetes.io/docs/reference/using-api/deprecation-guide/
- Kubernetes deprecation policy: https://kubernetes.io/docs/reference/using-api/deprecation-policy/
- Helpful API warnings (deprecated API metric): https://kubernetes.io/blog/2020/09/03/warnings/
- Argo CD sync phases and waves: https://argo-cd.readthedocs.io/en/stable/user-guide/sync-waves/
- Argo CD automated sync: https://argo-cd.readthedocs.io/en/stable/user-guide/auto_sync/
- Argo CD Kustomize (with Helm): https://argo-cd.readthedocs.io/en/stable/user-guide/kustomize/
- Argo CD ApplicationSet: https://argo-cd.readthedocs.io/en/stable/operator-manual/applicationset/
- Argo CD Image Updater: https://argocd-image-updater.readthedocs.io/en/stable/
- Flux: https://fluxcd.io/flux/
- Flux Kustomization: https://fluxcd.io/flux/components/kustomize/kustomizations/
- Flux HelmRelease: https://fluxcd.io/flux/components/helm/helmreleases/
- Flux image update automation: https://fluxcd.io/flux/guides/image-update/
- Argo Rollouts: https://argo-rollouts.readthedocs.io/en/stable/
- Argo Rollouts analysis: https://argo-rollouts.readthedocs.io/en/stable/features/analysis/
- Argo Rollouts Gateway API plugin: https://rollouts-plugin-trafficrouter-gatewayapi.readthedocs.io/en/latest/
- Flagger: https://docs.flagger.app/
- Flagger with Gateway API: https://docs.flagger.app/tutorials/gatewayapi-progressive-delivery
- kubeconform: https://github.com/yannh/kubeconform
- Pluto: https://pluto.docs.fairwinds.com/
- OpenFeature: https://openfeature.dev/
