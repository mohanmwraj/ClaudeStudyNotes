# Understand API Deprecations

**Why it matters:** each Kubernetes minor release may stop serving old beta API versions. A manifest that worked two years ago now fails with `no matches for kind "Deployment" in version "extensions/v1beta1"`. The exam expects you to:

1. recognise a removed or deprecated `apiVersion`,
2. find the version the cluster actually serves, and
3. rewrite the manifest, including the **field changes** each migration needs, and apply it.

> **Exam tip:** the fix is often more than "change one line". `apps/v1` needs `spec.selector`. A `networking.k8s.io/v1` Ingress needs `pathType` and the nested `backend.service` format. Validate with `kubectl apply --dry-run=server -f file.yaml` before the real apply.

---

## Core concepts

### Groups, versions, kinds

| Term | Example | Notes |
|---|---|---|
| API group | `apps`, `batch`, `networking.k8s.io`; core group = `""` | The core group has no prefix: `apiVersion: v1` |
| Version | `v1`, `v1beta1`, `v2` | A group can serve several versions at the same time |
| `apiVersion` | `apps/v1`, `v1` | `<group>/<version>`. REST path `/apis/apps/v1/...` (core: `/api/v1/...`) |
| Kind / resource | `Deployment` / `deployments` | `kubectl api-resources` maps one to the other |

- The API server **stores** each object once in etcd (in the group's *storage version*) and **converts** it to whatever version a client asks for. Objects must round-trip between versions without losing information (deprecation policy, Rule #2).
- So removing a version never deletes objects. Existing objects stay readable through the newer version. What breaks are your **manifests, Helm charts, scripts and API clients**.
- Try it: the same HPA can be read as `kubectl get hpa.v1.autoscaling web -o yaml` and as `kubectl get hpa.v2.autoscaling web -o yaml`.

### Current versions of the kinds you will meet (v1.33–v1.37; the exam runs v1.37, see [00](../00-Exam-Overview-and-Setup/README.md))

| apiVersion | Kinds |
|---|---|
| `v1` | Pod, Service, ConfigMap, Secret, Namespace, ServiceAccount, PersistentVolume, PersistentVolumeClaim, ResourceQuota, LimitRange, Endpoints (deprecated since v1.33) |
| `apps/v1` | Deployment, ReplicaSet, DaemonSet, StatefulSet |
| `batch/v1` | Job, CronJob |
| `networking.k8s.io/v1` | Ingress, IngressClass, NetworkPolicy |
| `policy/v1` | PodDisruptionBudget |
| `autoscaling/v2` | HorizontalPodAutoscaler (`autoscaling/v1` is still served, CPU only) |
| `rbac.authorization.k8s.io/v1` | Role, ClusterRole, RoleBinding, ClusterRoleBinding |
| `storage.k8s.io/v1` | StorageClass, CSIDriver, CSINode, VolumeAttachment |
| `apiextensions.k8s.io/v1` | CustomResourceDefinition |
| `scheduling.k8s.io/v1` | PriorityClass |
| `discovery.k8s.io/v1` | EndpointSlice |
| `admissionregistration.k8s.io/v1` | Validating/MutatingWebhookConfiguration, ValidatingAdmissionPolicy (+Binding, stable v1.30) |
| `gateway.networking.k8s.io/v1` | GatewayClass, Gateway, HTTPRoute, GRPCRoute (CRDs; ReferenceGrant is still `v1beta1`) |
| `kustomize.config.k8s.io/v1beta1` | Kustomization (a kustomize file, not a cluster API) |

### Maturity levels

| Level | Name pattern | Enabled by default? | Promise | Lifetime |
|---|---|---|---|---|
| **Alpha** | `v1alpha1` | No. Built-in alpha APIs must be enabled with `--runtime-config` on kube-apiserver | May be buggy, may change incompatibly, may be dropped without notice | Can be removed in any release without prior deprecation |
| **Beta** | `v1beta1`, `v2beta2` | No. Built-in beta APIs are off by default, except beta versions of APIs introduced before v1.22, which were on | Well tested; the schema may still change in a later beta/GA version (with migration instructions) | Deprecated no more than **9 months or 3 minor releases** after introduction, no longer served **9 months or 3 minor releases** after deprecation (whichever is longer, both times) |
| **GA / stable** | `v1`, `v2` | Yes | Stable | May be deprecated, but **never removed within a major version** (Kubernetes 1.x) |

### The deprecation policy in eight lines

| Rule | Meaning (paraphrased from the official policy) |
|---|---|
| #1 | API elements may only be removed by **incrementing the version** of the API group. Once added to a version, an element cannot be removed from it. |
| #2 | Objects must **round-trip** between API versions in a release without information loss (except whole resources that don't exist in some versions). |
| #3 | A version may not be deprecated in favour of a **less stable** one. GA replaces beta/alpha; beta replaces older beta/alpha but never GA. |
| #4a | Lifetime by level: GA is never removed within the major version; beta follows the 9-months-or-3-releases windows; alpha has no notice period. |
| #4b | The *preferred* and *storage* version may only advance after a release that supports **both** the new and the previous version. |
| #5a | Deprecated **kubectl** (user-facing CLI) elements keep working for at least 12 months or 2 releases (GA), and 3 months or 1 release (beta). |
| #6 | Deprecated CLI elements **must emit warnings** when used. |
| #7 | Deprecated behaviours must keep working for at least **1 year** after the announcement. |

### Deprecated vs. removed

| State | What happens | What you see |
|---|---|---|
| **Deprecated** (still served) | Works. Since v1.19 the API server adds a `Warning` response header, which kubectl prints to stderr | `Warning: policy/v1beta1 PodDisruptionBudget is deprecated in v1.21+, unavailable in v1.25+; use policy/v1 PodDisruptionBudget` |
| **Removed** (no longer served) | Request rejected; kubectl cannot even map the kind | `error: resource mapping not found for name: "web" namespace: "" from "web.yaml": no matches for kind "Deployment" in version "extensions/v1beta1"` followed by `ensure CRDs are installed first` |

The warning text is built from the type's metadata: `<group/version> <Kind> is deprecated in vX.Y+[, unavailable in vX.Z+][; use <replacement>]`.

### Removed APIs and what changes in the manifest

Source: the official *Deprecated API Migration Guide* (current docs, v1.37). The guide lists **no removals after v1.32**, so no built-in API version was removed in v1.33–v1.37. Every removed version below fails on the exam's v1.37 cluster.

| Removed in | Kind(s) | Old apiVersion(s) | New apiVersion | What changes in the manifest |
|---|---|---|---|---|
| **v1.16** | Deployment | `extensions/v1beta1`, `apps/v1beta1`, `apps/v1beta2` | `apps/v1` | `spec.selector` **required**, must match the template labels, and is immutable. `spec.rollbackTo` removed. New defaults: `progressDeadlineSeconds` 600, `revisionHistoryLimit` 10, `maxSurge`/`maxUnavailable` 25% |
| v1.16 | DaemonSet | `extensions/v1beta1`, `apps/v1beta2` | `apps/v1` | `spec.selector` required. `spec.templateGeneration` removed. `updateStrategy.type` now defaults to `RollingUpdate` (was `OnDelete`) |
| v1.16 | StatefulSet | `apps/v1beta1`, `apps/v1beta2` | `apps/v1` | `spec.selector` required. `updateStrategy.type` now defaults to `RollingUpdate` |
| v1.16 | ReplicaSet | `extensions/v1beta1`, `apps/v1beta1`, `apps/v1beta2` | `apps/v1` | `spec.selector` required and immutable |
| v1.16 | NetworkPolicy | `extensions/v1beta1` | `networking.k8s.io/v1` | apiVersion only |
| v1.16 | PodSecurityPolicy | `extensions/v1beta1` | `policy/v1beta1` (itself removed in v1.25) | Replaced by Pod Security Admission today |
| **v1.22** | Ingress | `extensions/v1beta1`, `networking.k8s.io/v1beta1` | `networking.k8s.io/v1` | `pathType` **required** (`Prefix`/`Exact`/`ImplementationSpecific`). `serviceName` becomes `service.name`, numeric `servicePort` becomes `service.port.number`, string `servicePort` becomes `service.port.name`. `spec.backend` becomes `spec.defaultBackend`. Use `spec.ingressClassName` instead of the deprecated `kubernetes.io/ingress.class` annotation |
| v1.22 | IngressClass | `networking.k8s.io/v1beta1` | `networking.k8s.io/v1` | apiVersion only |
| v1.22 | CustomResourceDefinition | `apiextensions.k8s.io/v1beta1` | `apiextensions.k8s.io/v1` | `spec.scope` required. `spec.version`, `validation`, `subresources` and `additionalPrinterColumns` move under `spec.versions[*]`. `schema.openAPIV3Schema` is required and must be structural. `JSONPath` becomes `jsonPath` |
| v1.22 | Role, ClusterRole, RoleBinding, ClusterRoleBinding | `rbac.authorization.k8s.io/v1beta1` | `rbac.authorization.k8s.io/v1` | apiVersion only |
| v1.22 | Mutating/ValidatingWebhookConfiguration | `admissionregistration.k8s.io/v1beta1` | `admissionregistration.k8s.io/v1` | `sideEffects` and `admissionReviewVersions` required. Defaults change: `failurePolicy: Fail`, `matchPolicy: Equivalent`, `timeoutSeconds: 10` |
| v1.22 | PriorityClass | `scheduling.k8s.io/v1beta1` | `scheduling.k8s.io/v1` | apiVersion only |
| v1.22 | StorageClass, CSIDriver, CSINode, VolumeAttachment | `storage.k8s.io/v1beta1` | `storage.k8s.io/v1` | apiVersion only |
| v1.22 | CertificateSigningRequest | `certificates.k8s.io/v1beta1` | `certificates.k8s.io/v1` | `spec.signerName` and `spec.usages` required |
| v1.22 | Lease | `coordination.k8s.io/v1beta1` | `coordination.k8s.io/v1` | apiVersion only |
| v1.22 | APIService, TokenReview, SubjectAccessReview & co. | `apiregistration.k8s.io/v1beta1`, `authentication.k8s.io/v1beta1`, `authorization.k8s.io/v1beta1` | `.../v1` | (Local)SubjectAccessReview: `spec.group` renamed to `spec.groups` |
| **v1.25** | CronJob | `batch/v1beta1` | `batch/v1` | apiVersion only. `spec.timeZone` (stable v1.27) exists only in `batch/v1` |
| v1.25 | PodDisruptionBudget | `policy/v1beta1` | `policy/v1` | apiVersion. An **empty** selector `{}` now selects **all** Pods in the namespace (v1beta1: none) |
| v1.25 | PodSecurityPolicy | `policy/v1beta1` | — (removed entirely) | Use Pod Security Admission namespace labels ([chapter 04](../04-Application-Environment-Configuration-and-Security/README.md)) |
| v1.25 | HorizontalPodAutoscaler | `autoscaling/v2beta1` | `autoscaling/v2` | `targetAverageUtilization: N` becomes `target: {type: Utilization, averageUtilization: N}` |
| v1.25 | EndpointSlice | `discovery.k8s.io/v1beta1` | `discovery.k8s.io/v1` | Per-endpoint `nodeName`/`zone` replace `topology` (now read-only `deprecatedTopology`) |
| v1.25 | Event | `events.k8s.io/v1beta1` | `events.k8s.io/v1` | `involvedObject` becomes `regarding`. `type` limited to Normal/Warning. Old timestamps/count are renamed `deprecated*` |
| v1.25 | RuntimeClass | `node.k8s.io/v1beta1` | `node.k8s.io/v1` | apiVersion only |
| **v1.26** | HorizontalPodAutoscaler | `autoscaling/v2beta2` | `autoscaling/v2` | Same schema as v2: only `apiVersion` changes |
| v1.26 | FlowSchema, PriorityLevelConfiguration | `flowcontrol.apiserver.k8s.io/v1beta1` | `.../v1beta2` then (today) `.../v1` | — |
| **v1.27** | CSIStorageCapacity | `storage.k8s.io/v1beta1` | `storage.k8s.io/v1` | apiVersion only |
| **v1.29** | FlowSchema, PriorityLevelConfiguration | `flowcontrol.apiserver.k8s.io/v1beta2` | `flowcontrol.apiserver.k8s.io/v1` | `assuredConcurrencyShares` renamed `nominalConcurrencyShares` |
| **v1.32** | FlowSchema, PriorityLevelConfiguration | `flowcontrol.apiserver.k8s.io/v1beta3` | `flowcontrol.apiserver.k8s.io/v1` | An explicit `nominalConcurrencyShares: 0` is no longer changed to 30 |

> **Exam tip:** the five migrations that matter for CKAD are Deployment → `apps/v1`, Ingress → `networking.k8s.io/v1`, CronJob → `batch/v1`, PDB → `policy/v1`, HPA → `autoscaling/v2`. Each has a walk-through below and a before/after pair in [yaml/deprecated/](yaml/deprecated/) and [yaml/migrated/](yaml/migrated/).

---

## Key fields / syntax

### 1. Discover the right version

```bash
kubectl api-resources | grep -E '^(cronjobs|ingresses|poddisruptionbudgets|horizontalpodautoscalers) '
# (columns: NAME  SHORTNAMES  APIVERSION  NAMESPACED  KIND)
# cronjobs                   cj           batch/v1               true         CronJob
# horizontalpodautoscalers   hpa          autoscaling/v2         true         HorizontalPodAutoscaler
# ingresses                  ing          networking.k8s.io/v1   true         Ingress
# poddisruptionbudgets       pdb          policy/v1              true         PodDisruptionBudget

kubectl api-resources --api-group=apps          # everything in one group
kubectl api-resources --namespaced=false        # cluster-scoped kinds only
kubectl api-resources -o wide                   # adds VERBS and CATEGORIES columns
kubectl api-versions | grep autoscaling         # every served group/version: autoscaling/v1, autoscaling/v2

kubectl explain cronjob | head -3               # header shows GROUP / KIND / VERSION
# GROUP:      batch
# KIND:       CronJob
# VERSION:    v1
kubectl explain hpa --api-version=autoscaling/v1           # explain a specific (non-preferred) version
kubectl explain ingress.spec.rules.http.paths.backend.service
kubectl explain deployment.spec.selector

kubectl get --raw /apis/autoscaling             # APIGroup JSON: all versions + preferredVersion
kubectl get deployments.v1.apps                 # fully qualified <resource>.<version>.<group>
```

- The APIVERSION column of `api-resources` and the `kubectl explain` header show the **preferred** version. Write that one in new manifests.
- `kubectl explain` reads the cluster's own OpenAPI schema, so it always matches what this API server serves. It is the fastest way to check a field's exact spelling in the new version.

### 2. Deprecation warnings

```text
$ kubectl get endpoints web -n app
Warning: v1 Endpoints is deprecated in v1.33+; use discovery.k8s.io/v1 EndpointSlice
NAME   ENDPOINTS        AGE
web    10.244.1.7:80    3m
```

```bash
kubectl apply -f app.yaml --warnings-as-errors   # CI-friendly: any server warning -> non-zero exit code
kubectl apply -f app.yaml --dry-run=server       # full server-side validation without persisting
```

### 3. `kubectl convert` (plugin, installed separately): a lab and real-world convenience

> **Exam route:** migrate **by hand** with `kubectl explain` and the Deprecated API Migration Guide (an allowed docs page). The `kubectl-convert` plugin is not among the tools guaranteed on exam hosts (kubectl with the `k` alias and completion, yq, curl, wget, man; see [00](../00-Exam-Overview-and-Setup/README.md)). Use the plugin in your lab and in real projects.

`kubectl convert` used to be built into kubectl. Today it is the `kubectl-convert` plugin, a separate download from the Kubernetes release binaries. kubectl finds it as a plugin once it is on your `PATH`.

```bash
# Linux x86-64 install (official docs). Use the same version as your kubectl.
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl-convert"
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl-convert.sha256"
echo "$(cat kubectl-convert.sha256) kubectl-convert" | sha256sum --check
sudo install -o root -g root -m 0755 kubectl-convert /usr/local/bin/kubectl-convert
kubectl convert --help                                   # no error = installed

# Usage: works locally (no API call needed)
kubectl convert -f old-deploy.yaml --output-version apps/v1 > new-deploy.yaml
kubectl convert -f old-ingress.yaml --output-version networking.k8s.io/v1 > new-ingress.yaml
```

- The plugin's built-in scheme still knows the old versions (the v1.35 plugin registers `extensions/v1beta1`, `apps/v1beta1/2`, `batch/v1beta1`, `policy/v1beta1` and `autoscaling/v2beta1/2`), so it can read very old files.
- The output applies the **old API's defaults**. An `extensions/v1beta1` Deployment comes out with `selector` copied from the template labels and `maxSurge: 1` / `maxUnavailable: 1` instead of 25%. It also contains `creationTimestamp: null`, `status: {}` and other noise. The docs warn that conversion "may use non-ideal default values". Review and trim the result.
- Check `kubectl convert --help` before relying on it. If the plugin isn't installed (expect that in the exam), migrate by hand as shown below. Manual migration is the skill that is actually tested.

### 4. Manual migration walk-throughs

General workflow:

```bash
kubectl apply --dry-run=server -f old.yaml          # 1. see the error (no matches for kind ...)
kubectl explain <kind> | head -3                    # 2. find the served group/version
vim old.yaml                                        # 3. change apiVersion + required field changes
kubectl apply --dry-run=server -f old.yaml          # 4. validate against the live API
kubectl apply -f old.yaml                           # 5. apply (in the namespace the task names)
kubectl get <resource>.<version>.<group> <name>     # 6. verify
```

One-line edits for the apiVersion itself, when only that line changes (CronJob, PDB, HPA v2beta2):

```bash
sed -i 's#^apiVersion: batch/v1beta1#apiVersion: batch/v1#' cronjob.yaml    # works everywhere
yq --version                                         # yq is on the exam hosts; syntax depends on the flavour:
yq -i '.apiVersion = "batch/v1"' cronjob.yaml        #   mikefarah yq v4
```

For multi-document files, check every `---` document.

#### 4.1 Deployment `extensions/v1beta1` → `apps/v1` (add the selector)

```diff
-apiVersion: extensions/v1beta1
+apiVersion: apps/v1
 kind: Deployment
 metadata:
   name: legacy-web
 spec:
   replicas: 3
+  selector:                  # REQUIRED in apps/v1, immutable after creation
+    matchLabels:             # must match the template labels
+      app: legacy-web
+      tier: frontend
   template:
     metadata:
       labels:
         app: legacy-web
         tier: frontend
```

- If the object already exists in the cluster (created long ago through the old API), its selector was defaulted to **all** template labels. Because the selector is immutable, re-applying with a *different* selector fails with `field is immutable`. Copy the full template label set, as the migration guide recommends.
- Remove `spec.rollbackTo` if present. Use `kubectl rollout undo` instead.
- Files: [deprecated](yaml/deprecated/deployment-extensions-v1beta1.yaml) → [migrated](yaml/migrated/deployment-apps-v1.yaml). The same rule (add `selector`) applies to DaemonSet, ReplicaSet and StatefulSet.

#### 4.2 Ingress `networking.k8s.io/v1beta1` → `networking.k8s.io/v1`

```diff
-apiVersion: networking.k8s.io/v1beta1
+apiVersion: networking.k8s.io/v1
 kind: Ingress
 metadata:
   name: shop
-  annotations:
-    kubernetes.io/ingress.class: nginx
 spec:
-  backend:
-    serviceName: default-http
-    servicePort: 80
+  ingressClassName: nginx
+  defaultBackend:
+    service:
+      name: default-http
+      port:
+        number: 80
   rules:
   - host: shop.example.com
     http:
       paths:
       - path: /api
+        pathType: Prefix
         backend:
-          serviceName: api-svc
-          servicePort: 8080
+          service:
+            name: api-svc
+            port:
+              number: 8080
       - path: /
+        pathType: Prefix
         backend:
-          serviceName: web-svc
-          servicePort: http
+          service:
+            name: web-svc
+            port:
+              name: http        # string ports go to port.name
```

- `pathType` choices: `Prefix` (what most tasks mean by "/api and everything below"), `Exact`, or `ImplementationSpecific` (reproduces the old undefined v1beta1 behaviour).
- Files: [deprecated](yaml/deprecated/ingress-v1beta1.yaml) → [migrated](yaml/migrated/ingress-v1.yaml). Shortcut for a new Ingress: `kubectl create ingress shop --class=nginx --rule="shop.example.com/api*=api-svc:8080" --dry-run=client -o yaml`.

#### 4.3 CronJob `batch/v1beta1` → `batch/v1`

```diff
-apiVersion: batch/v1beta1
+apiVersion: batch/v1
 kind: CronJob
 metadata:
   name: report
 spec:
   schedule: "*/5 * * * *"
+  timeZone: "Etc/UTC"          # optional; only exists in batch/v1
```

- "No notable changes": the schema is identical. Check that the pod template's `restartPolicy` is `Never` or `OnFailure`.
- Files: [deprecated](yaml/deprecated/cronjob-v1beta1.yaml) → [migrated](yaml/migrated/cronjob-batch-v1.yaml). Test immediately with `kubectl create job report-now --from=cronjob/report`.

#### 4.4 PodDisruptionBudget `policy/v1beta1` → `policy/v1`

```diff
-apiVersion: policy/v1beta1
+apiVersion: policy/v1
 kind: PodDisruptionBudget
 metadata:
   name: legacy-web-pdb
 spec:
   minAvailable: 2
   selector:
     matchLabels:
       app: legacy-web
```

- Semantics trap: `selector: {}` selects **every Pod in the namespace** in `policy/v1` (none in v1beta1). An unset selector selects nothing in both versions.
- Files: [deprecated](yaml/deprecated/pdb-v1beta1.yaml) → [migrated](yaml/migrated/pdb-policy-v1.yaml). Imperative: `kubectl create pdb legacy-web-pdb --selector=app=legacy-web --min-available=2`.

#### 4.5 HPA `autoscaling/v2beta2` → `autoscaling/v2` (and the v2beta1 style)

```diff
-apiVersion: autoscaling/v2beta2
+apiVersion: autoscaling/v2
 kind: HorizontalPodAutoscaler
 metadata:
   name: legacy-web-hpa
 spec:
   scaleTargetRef:
     apiVersion: apps/v1
     kind: Deployment
     name: legacy-web
   minReplicas: 2
   maxReplicas: 6
   metrics:
   - type: Resource
     resource:
       name: cpu
       target:
         type: Utilization
         averageUtilization: 70
```

If the file is in the even older **v2beta1** style, also rewrite the metric block:

```diff
   - type: Resource
     resource:
       name: cpu
-      targetAverageUtilization: 70
+      target:
+        type: Utilization
+        averageUtilization: 70
```

- Files: [deprecated](yaml/deprecated/hpa-v2beta2.yaml) → [migrated](yaml/migrated/hpa-autoscaling-v2.yaml). kubectl v1.33+ `kubectl autoscale` generates an `autoscaling/v2` object when the server serves it.

### 5. Find deprecated API usage in a running cluster

```bash
# 1) API server metric: set to 1 for every deprecated group/version/resource requested since it started
kubectl get --raw /metrics | grep apiserver_requested_deprecated_apis
#   apiserver_requested_deprecated_apis{group="",removed_release="",resource="endpoints",subresource="",version="v1"} 1
#   (labels: group, version, resource, subresource, removed_release)

# 2) Your own manifests / charts
grep -rnE '^apiVersion: *(extensions/|apps/v1beta|batch/v1beta1|policy/v1beta1|autoscaling/v2beta|networking.k8s.io/v1beta1)' ./manifests
helm get manifest <release> -n <ns> | grep -n apiVersion
```

- Audit logs: requests to deprecated APIs carry the audit annotation `"k8s.io/deprecated": "true"`. Use them to identify **which client** is calling.
- Prometheus join (from the official docs): `apiserver_requested_deprecated_apis{removed_release="1.22"} * on(group,version,resource,subresource) group_right() apiserver_request_total`.
- Architect tooling (not on the exam): **pluto** (Fairwinds) and **kubent** (kube-no-trouble) scan files, Helm releases and live clusters for deprecated/removed APIs. The Helm **mapkubeapis** plugin rewrites removed apiVersions stored inside Helm release records.

### 6. Endpoints → EndpointSlice (core v1 Endpoints deprecated in v1.33)

- Since v1.33 the core `v1` **Endpoints** API is deprecated in favour of `discovery.k8s.io/v1` **EndpointSlice**. Reads and writes return the warning shown above. Endpoints is GA, so it will probably never be removed, but new Service features (dual-stack, traffic distribution) exist only in EndpointSlices. Migrate scripts and monitoring now.
- A Service can have **several** EndpointSlices: one per IP family, one per port set, and up to 100 endpoints per slice by default. Their names are generated, so select them by label:

```bash
kubectl get endpointslices -l kubernetes.io/service-name=web
# NAME        ADDRESSTYPE   PORTS   ENDPOINTS                AGE
# web-7vzhx   IPv4          80      10.244.1.7,10.244.2.4    5m
kubectl get endpointslices -l kubernetes.io/service-name=web -o yaml | grep -A3 conditions
```

- Each endpoint carries `conditions.ready`, `serving` and `terminating`. Endpoints used to split addresses into `addresses` / `notReadyAddresses` instead.

---

## Imperative commands

There is no generator for "migrate", but these cover the whole workflow:

```bash
kubectl api-resources | grep -i <kind>                          # current group/version of a kind
kubectl explain <kind> | head -3                                # GROUP / KIND / VERSION header
kubectl explain <kind>.<field.path> --api-version=<group/ver>   # field docs for one version
kubectl apply --dry-run=server -f fixed.yaml                    # validate the migrated file
kubectl convert -f old.yaml --output-version apps/v1 > new.yaml # lab only: needs the kubectl-convert plugin
# Regenerate a clean manifest from scratch instead of fixing old YAML:
kubectl create deployment legacy-web --image=nginx:1.27 --replicas=3 --dry-run=client -o yaml > deploy.yaml
kubectl create cronjob report --image=busybox:1.36 --schedule="*/5 * * * *" --dry-run=client -o yaml -- sh -c 'date' > cj.yaml
kubectl create pdb legacy-web-pdb --selector=app=legacy-web --min-available=2 --dry-run=client -o yaml > pdb.yaml
kubectl create ingress shop --class=nginx --rule="shop.example.com/*=web-svc:80" --dry-run=client -o yaml > ing.yaml
kubectl autoscale deployment legacy-web --min=2 --max=6 --cpu=70% --dry-run=client -o yaml > hpa.yaml
```

`--cpu=70%` targets average utilization; `--cpu=500m` or `--memory=200Mi` target an average value. The old form `--cpu-percent=70` has been deprecated since kubectl v1.34. It still works on v1.37 but prints a deprecation warning.

> **Exam tip:** if the legacy manifest is long, generating a fresh skeleton with `--dry-run=client -o yaml` and copying the business values (names, image, ports, schedule) into it is often faster and safer than editing the old file line by line.

---

## Exam traps & tips

> **Exam tip:** keep everything the task did not ask you to change: names, labels, replicas, images, ports, namespace. Change the apiVersion **and** the fields the new version requires.

> **Exam tip:** `apps/v1` + no selector gives `spec.selector: Required value`. A selector that doesn't match the template labels gives `selector does not match template labels`. Fix both in the same edit.

> **Exam tip:** Ingress v1 port syntax: a number goes to `port.number`, a named port (`http`) goes to `port.name`, never both. A missing `pathType` is rejected.

> **Exam tip:** `kubectl apply --dry-run=client` does **not** catch everything; `--dry-run=server` runs real validation and admission without saving. Use the server form to prove a migration.

> **Exam tip:** if the task says "save the fixed manifest to /path/file.yaml", write the file **and** apply it if asked. Graders often check both the file content and the live object.

> **Exam tip:** HPA `autoscaling/v1` is still served. A task that says "use the current API" wants `autoscaling/v2` (the preferred version in `kubectl api-resources`).

---

## Architect notes

- **Make API hygiene part of every upgrade runbook.** Before each minor upgrade, scan Git (pluto/kubent or `kubeconform` with the target version's schemas), the live cluster (the `apiserver_requested_deprecated_apis` metric, audit `k8s.io/deprecated`) and Helm release records.
- **Clients matter as much as manifests.** Operators, CI jobs, Terraform providers and dashboards call APIs too. The metric and the audit annotation reveal them. Pin client-go/SDK versions that support the target cluster.
- **Gate CI on warnings.** Use `kubectl apply --dry-run=server --warnings-as-errors` against a staging cluster on the next Kubernetes version, so a deprecation fails a pipeline long before it fails production.
- **Avoid beta APIs in long-lived platforms.** Built-in beta APIs are now off by default and have a bounded lifetime. If you enable one, record an owner and an exit plan.
- **Helm charts serving many cluster versions:** branch on `.Capabilities.APIVersions.Has "policy/v1/PodDisruptionBudget"` instead of hard-coding one version. Run `helm mapkubeapis` before upgrading clusters that hold releases rendered with removed APIs.
- **CRD authors** should mark old versions `deprecated: true` with a custom `deprecationWarning`, serve several versions with a conversion webhook, and migrate the storage version before dropping a version from `spec.versions`.
- **Endpoints → EndpointSlices:** move scripts, service meshes and monitoring that read `v1/Endpoints` to EndpointSlices (label `kubernetes.io/service-name`) and expect several slices per Service.
- **Upgrade one minor version at a time** and test with the old API disabled (`--runtime-config=<group>/<version>=false` on a test API server) to simulate the removal.

---

## Docs to bookmark

- Deprecated API Migration Guide: https://kubernetes.io/docs/reference/using-api/deprecation-guide/
- Kubernetes Deprecation Policy: https://kubernetes.io/docs/reference/using-api/deprecation-policy/
- API Overview (versioning, groups, `--runtime-config`): https://kubernetes.io/docs/reference/using-api/
- Install the kubectl convert plugin: https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/#install-kubectl-convert-plugin
- `kubectl api-resources`: https://kubernetes.io/docs/reference/kubectl/generated/kubectl_api-resources/
- `kubectl explain`: https://kubernetes.io/docs/reference/kubectl/generated/kubectl_explain/
- Blog, *Warning: Helpful Warnings Ahead* (warnings, metric, audit): https://kubernetes.io/blog/2020/09/03/warnings/
- Blog, *Continuing the transition from Endpoints to EndpointSlices*: https://kubernetes.io/blog/2025/04/24/endpoints-deprecation/

---

## Quick self-check

1. Which two changes turn an `extensions/v1beta1` Deployment into a valid `apps/v1` Deployment?
2. Where do you see the served group and version of `CronJob` in one command?
3. An Ingress v1beta1 path has `servicePort: http`. What does it become in v1?
4. What does `selector: {}` select in a `policy/v1` PodDisruptionBudget?
5. Can the core `v1` Endpoints API be removed in Kubernetes 1.40?
6. What is the difference between `kubectl apply --dry-run=client` and `--dry-run=server` for validating a migration?

<details><summary>Answers</summary>

1. `apiVersion: apps/v1`, plus a `spec.selector.matchLabels` that matches the Pod template labels (ideally all of them, if the object already exists).
2. `kubectl explain cronjob | head -3` (GROUP `batch`, VERSION `v1`) or `kubectl api-resources | grep -i cronjob` (APIVERSION column).
3. `backend.service.name: <svc>` + `backend.service.port.name: http`, and the path needs a `pathType`.
4. All Pods in the namespace (in v1beta1 it selected none).
5. No. It is a GA API. GA versions may be deprecated (v1.33) but must not be removed within a major version.
6. Client dry-run only builds the object locally (it still needs the kind to be known). Server dry-run sends it to the API server for full schema validation, defaulting and admission without persisting, which proves the new version is accepted.

</details>
