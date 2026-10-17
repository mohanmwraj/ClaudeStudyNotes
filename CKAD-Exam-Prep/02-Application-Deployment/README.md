# 02: Application Deployment (20%)

**Exam weight: 20%.** This domain covers getting a new version of an app into the cluster safely: Deployments and their rollouts, blue/green and canary with plain Kubernetes objects, installing and managing packaged apps with Helm, and per-environment manifests with Kustomize.

The content targets Kubernetes **v1.37**, the exam's version. It is also valid for v1.33+. Exam format, rules and allowed docs are in [../00-Exam-Overview-and-Setup/README.md](../00-Exam-Overview-and-Setup/README.md).

## Official competencies (CNCF curriculum)

- Use Kubernetes primitives to implement common deployment strategies (e.g. blue/green or canary)
- Understand Deployments and how to perform rolling updates
- Use the Helm package manager to deploy existing packages
- Kustomize

## Competency → files → exam frequency

| Competency | File(s) | Exam frequency |
|---|---|---|
| Understand Deployments and how to perform rolling updates | [01-deployments-and-replicasets.md](01-deployments-and-replicasets.md), [02-rolling-updates-and-rollbacks.md](02-rolling-updates-and-rollbacks.md) | High |
| Use Kubernetes primitives to implement common deployment strategies (e.g. blue/green or canary) | [03-deployment-strategies.md](03-deployment-strategies.md), [yaml/blue-green/](yaml/blue-green/README.md), [yaml/canary/](yaml/canary/README.md) | High (canary), Medium (blue/green) |
| Use the Helm package manager to deploy existing packages | [04-helm.md](04-helm.md), [yaml/helm/](yaml/helm/README.md) | High |
| Kustomize | [05-kustomize.md](05-kustomize.md), [yaml/kustomize/](yaml/kustomize/README.md) | Medium |
| All of the above | [commands.md](commands.md), [practice-questions.md](practice-questions.md) | |

Frequency is an estimate based on the curriculum and on task patterns candidates describe publicly. Real exam questions are confidential.

## Must know: cannot skip

- [ ] Create a Deployment imperatively (`kubectl create deployment ... --replicas --port --dry-run=client -o yaml`) and scale it
- [ ] Update an image with `kubectl set image deploy/<n> <container>=<image>`, after checking the container name
- [ ] Record the change-cause with `kubectl annotate ... kubernetes.io/change-cause="..." --overwrite`, **after** the change (`--record` is deprecated)
- [ ] `kubectl rollout status | history [--revision=N] | undo [--to-revision=N] | pause | resume | restart`
- [ ] A rollback creates a **new** revision. Only `spec.template` changes create revisions
- [ ] maxSurge rounds up, maxUnavailable rounds down (defaults 25%/25%). Compute max Pods and min available Pods for any replica count
- [ ] Switch to `Recreate` by removing `rollingUpdate`. Know why selectors are immutable and how to recreate the Deployment
- [ ] Detect a failed rollout: `rollout status` exit code and `ProgressDeadlineExceeded`. Undo it
- [ ] Blue/green: second Deployment with a colour label, switch the Service selector, verify the EndpointSlices, roll back by switching back
- [ ] Canary: shared Service label plus a distinct `track` label, replica ratio arithmetic ("keep N Pods in total"), promote and roll back
- [ ] Helm: `repo add/update`, `search repo --versions`, `show values`, `install -n --create-namespace -f --set --version`, `upgrade --reuse-values`, `rollback`, `uninstall`, `list -A`, `history`, `get values [--all]`, `template`, `pull --untar`
- [ ] Helm values precedence (chart < parent < `-f` files left→right < `--set`) and the `helm upgrade` value-reuse rules
- [ ] Unstick a `pending-*` release, and remove `failed` releases
- [ ] Kustomize: `kubectl kustomize`, `kubectl apply -k`, overlay with `resources`, `namespace`, `namePrefix`, `labels`, `images`, `replicas`, `configMapGenerator`, `patches` (strategic merge + JSON6902)

## Nice to know (low frequency, still covered)

- DaemonSet and StatefulSet rollouts: `updateStrategy`, `OnDelete`, `partition`, ControllerRevisions ([02](02-rolling-updates-and-rollbacks.md))
- Deployment conditions in detail, including `ReplicaFailure/FailedCreate` and `terminatingReplicas` ([01](01-deployments-and-replicasets.md))
- Blue/green via the Ingress backend. A/B and shadow traffic concepts. Gateway API weighted routing ([03](03-deployment-strategies.md))
- Helm chart anatomy, templates, release Secrets and statuses, OCI registries, Helm 3 vs 4 flag differences ([04](04-helm.md))
- Kustomize generators `behavior: merge|replace`, `generatorOptions`, components, replacements, deprecated fields, standalone `kustomize edit` ([05](05-kustomize.md))

## Recommended study order

| # | Step | Time |
|---|---|---|
| 1 | [01-deployments-and-replicasets.md](01-deployments-and-replicasets.md) + apply [yaml/deployment-rolling-update.yaml](yaml/deployment-rolling-update.yaml) | 40 min |
| 2 | [02-rolling-updates-and-rollbacks.md](02-rolling-updates-and-rollbacks.md). Do the update / history / undo cycle by hand | 60 min |
| 3 | [03-deployment-strategies.md](03-deployment-strategies.md) + labs [yaml/blue-green/](yaml/blue-green/README.md), [yaml/canary/](yaml/canary/README.md) | 60 min |
| 4 | [04-helm.md](04-helm.md) + lab [yaml/helm/](yaml/helm/README.md) | 75 min |
| 5 | [05-kustomize.md](05-kustomize.md) + lab [yaml/kustomize/](yaml/kustomize/README.md) | 60 min |
| 6 | [practice-questions.md](practice-questions.md): all 🔥 first, then ⚡, then 🧊 | 2.5–3 h |
| 7 | Skim [commands.md](commands.md) the evening before the exam | 20 min |

## Files in this chapter

| File | Content |
|---|---|
| [01-deployments-and-replicasets.md](01-deployments-and-replicasets.md) | Controller hierarchy, pod-template-hash, spec fields and defaults, status/conditions, what triggers a rollout, selector immutability, scaling |
| [02-rolling-updates-and-rollbacks.md](02-rolling-updates-and-rollbacks.md) | maxSurge/maxUnavailable math (3/4/10 replicas), update methods, change-cause, history/undo semantics, pause/resume, restart, failed rollouts, DaemonSet/StatefulSet |
| [03-deployment-strategies.md](03-deployment-strategies.md) | Recreate, rolling, blue/green (Service and Ingress switch), canary ratio arithmetic, promotion/rollback, A/B, shadow, weighted routing |
| [04-helm.md](04-helm.md) | Helm 3 vs 4, concepts, chart structure, values precedence, full command set, release storage, stuck releases, exam workflows |
| [05-kustomize.md](05-kustomize.md) | kustomization fields, generators and hash rollouts, SMP/JSON6902 patches, components, deprecated fields, commands, Helm vs Kustomize |
| [commands.md](commands.md) | Every command of the chapter, grouped, one-line comments |
| [practice-questions.md](practice-questions.md) | 27 exam-style tasks with solutions and verification + must-know summary |

## yaml/ index

| File | What it shows |
|---|---|
| [yaml/deployment-rolling-update.yaml](yaml/deployment-rolling-update.yaml) | Deployment with every rollout field annotated (maxSurge 1 / maxUnavailable 0, minReadySeconds, progressDeadlineSeconds, revisionHistoryLimit, change-cause) |
| [yaml/deployment-recreate.yaml](yaml/deployment-recreate.yaml) | Recreate strategy (no rollingUpdate block) |
| [yaml/daemonset-statefulset-updates.yaml](yaml/daemonset-statefulset-updates.yaml) | DaemonSet `updateStrategy` (maxUnavailable/maxSurge), StatefulSet `partition` + headless Service |
| [yaml/blue-green/README.md](yaml/blue-green/README.md) | Blue/green lab: deploy, switch, verify, roll back (Service and Ingress variants) |
| [yaml/blue-green/blue-deployment.yaml](yaml/blue-green/blue-deployment.yaml) | `shop-blue` (app=shop, version=blue) |
| [yaml/blue-green/green-deployment.yaml](yaml/blue-green/green-deployment.yaml) | `shop-green` (app=shop, version=green) |
| [yaml/blue-green/service.yaml](yaml/blue-green/service.yaml) | Service `shop`, selector with the colour label |
| [yaml/blue-green/ingress-switch.yaml](yaml/blue-green/ingress-switch.yaml) | One Service per colour + Ingress backend switch |
| [yaml/canary/README.md](yaml/canary/README.md) | Canary lab: ratios, measuring the split, promotion and rollback |
| [yaml/canary/stable-deployment.yaml](yaml/canary/stable-deployment.yaml) | `web-stable` (app=web, track=stable), 4 replicas |
| [yaml/canary/canary-deployment.yaml](yaml/canary/canary-deployment.yaml) | `web-canary` (app=web, track=canary), 1 replica = 20% |
| [yaml/canary/service.yaml](yaml/canary/service.yaml) | Service `web`, selector `app=web` only |
| [yaml/canary/httproute-weighted.yaml](yaml/canary/httproute-weighted.yaml) | Gateway API HTTPRoute 90/10 + header override (architect variant) |
| [yaml/helm/README.md](yaml/helm/README.md) | Offline Helm lab: lint, template, install, upgrade, rollback, stuck release, public repo |
| [yaml/helm/values-override.yaml](yaml/helm/values-override.yaml) | User values file for `-f` |
| [yaml/helm/sample-chart/webapp/Chart.yaml](yaml/helm/sample-chart/webapp/Chart.yaml) | Chart metadata (version vs appVersion) |
| [yaml/helm/sample-chart/webapp/values.yaml](yaml/helm/sample-chart/webapp/values.yaml) | Chart defaults |
| [yaml/helm/sample-chart/webapp/templates/_helpers.tpl](yaml/helm/sample-chart/webapp/templates/_helpers.tpl) | Named templates (names, labels, selector labels) |
| [yaml/helm/sample-chart/webapp/templates/deployment.yaml](yaml/helm/sample-chart/webapp/templates/deployment.yaml) | Deployment template with the checksum annotation |
| [yaml/helm/sample-chart/webapp/templates/service.yaml](yaml/helm/sample-chart/webapp/templates/service.yaml) | Service template (optional nodePort) |
| [yaml/helm/sample-chart/webapp/templates/configmap.yaml](yaml/helm/sample-chart/webapp/templates/configmap.yaml) | ConfigMap page driven by `message` |
| [yaml/helm/sample-chart/webapp/templates/NOTES.txt](yaml/helm/sample-chart/webapp/templates/NOTES.txt) | Post-install notes |
| [yaml/kustomize/README.md](yaml/kustomize/README.md) | Kustomize lab: render, diff, apply, hash-triggered rollout |
| [yaml/kustomize/base/kustomization.yaml](yaml/kustomize/base/kustomization.yaml) | Base: resources, labels (no selectors), configMapGenerator |
| [yaml/kustomize/base/deployment.yaml](yaml/kustomize/base/deployment.yaml) | Base Deployment (envFrom the generated ConfigMap) |
| [yaml/kustomize/base/service.yaml](yaml/kustomize/base/service.yaml) | Base Service |
| [yaml/kustomize/overlays/dev/kustomization.yaml](yaml/kustomize/overlays/dev/kustomization.yaml) | Dev overlay: namespace, namePrefix, labels + selectors, SMP patch, generator merge |
| [yaml/kustomize/overlays/dev/namespace.yaml](yaml/kustomize/overlays/dev/namespace.yaml) | Namespace `dev` |
| [yaml/kustomize/overlays/dev/patch-replicas.yaml](yaml/kustomize/overlays/dev/patch-replicas.yaml) | Strategic-merge patch: replicas 1 |
| [yaml/kustomize/overlays/prod/kustomization.yaml](yaml/kustomize/overlays/prod/kustomization.yaml) | Prod overlay: commonAnnotations, images, replicas, SMP + inline JSON6902, secretGenerator |
| [yaml/kustomize/overlays/prod/namespace.yaml](yaml/kustomize/overlays/prod/namespace.yaml) | Namespace `prod` |
| [yaml/kustomize/overlays/prod/patch-resources.yaml](yaml/kustomize/overlays/prod/patch-resources.yaml) | Strategic-merge patch: container resources |

All manifests were validated against the Kubernetes 1.33, 1.35 and 1.37 schemas. The chart was rendered with Helm v3.22.1 and v4.3.1, and the overlays with Kustomize v5.8.3 (kubectl v1.37 embeds v5.8.1).

## Related chapters

- Workload types (DaemonSet, StatefulSet, Job): [../01-Application-Design-and-Build/README.md](../01-Application-Design-and-Build/README.md)
- Probes, which make rollouts safe: [../03-Application-Observability-and-Maintenance/README.md](../03-Application-Observability-and-Maintenance/README.md)
- ConfigMaps, Secrets, ServiceAccounts: [../04-Application-Environment-Configuration-and-Security/README.md](../04-Application-Environment-Configuration-and-Security/README.md)
- Services, Ingress, Gateway API: [../05-Services-and-Networking/README.md](../05-Services-and-Networking/README.md)
- Labels/selectors, HPA, PDB, jsonpath: [../06-Cross-Cutting-Skills-and-Bonus-Topics/README.md](../06-Cross-Cutting-Skills-and-Bonus-Topics/README.md)
- Production rollout design: [../08-Architect-Notes/README.md](../08-Architect-Notes/README.md)
