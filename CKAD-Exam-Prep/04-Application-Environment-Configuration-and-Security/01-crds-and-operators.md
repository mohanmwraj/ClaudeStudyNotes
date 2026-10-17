# CRDs and Operators

**Competency:** *Discover and use resources that extend Kubernetes (CRD, Operators)*

**Why it matters / what the exam expects:** real clusters are full of extension APIs (cert-manager, Prometheus Operator, Argo CD, CloudNativePG, ...). Expect to **discover** them (`kubectl get crd`, `kubectl api-resources`, `kubectl explain`), **use** them (list, create or modify a custom resource whose CRD already exists), and possibly **create a small CRD** from the docs example. You will never write a controller in the exam.

---

## Core concepts

| Term | What it is | Example |
|---|---|---|
| **CustomResourceDefinition (CRD)** | A cluster-scoped object (`apiextensions.k8s.io/v1`) that registers a new resource type with the API server | `crontabs.stable.example.com` |
| **Custom resource (CR)** | An instance of that new type, stored in etcd like any other object | `kind: CronTab`, name `hourly-cleanup` |
| **Controller** | A loop that watches objects and drives the actual state toward their `spec` | the Deployment controller |
| **Operator** | CRD(s) + a custom controller that encodes the operational knowledge for one application | cert-manager, Prometheus Operator, CloudNativePG |

- A CRD alone gives you **storage + a REST endpoint + kubectl support + schema validation**. It has **no behaviour**: creating a CronTab does nothing unless a controller watches CronTabs.
- Endpoint: `/apis/<group>/<version>/namespaces/<ns>/<plural>` (Namespaced) or `/apis/<group>/<version>/<plural>` (Cluster).
- CRs support every generic verb: `get`, `describe`, `edit`, `patch`, `delete`, `label`, `-o yaml`, `-w`. RBAC applies as usual: `apiGroups: ["<group>"]`, `resources: ["<plural>"]`.
- Other extension mechanisms (awareness only): API aggregation (`kubectl get apiservices`, e.g. metrics-server's `v1beta1.metrics.k8s.io`), admission webhooks and policies (see [02](02-authentication-authorization-admission.md)), CNI/CSI/CRI plugins, kubectl plugins (`kubectl-<name>` binaries on `PATH`), scheduler plugins.

### The operator pattern: reconcile loop

```text
  CR .spec (desired) --watch--> controller --create/update--> Deployments, Services, Secrets, PVCs,
          ^                     compares desired             external systems (DNS, cloud, DBs)
          |                     with observed                              |
          +------------ .status, conditions, Events <----------------------+
```

The loop is **level-triggered and idempotent**: it re-runs until observed == desired and reports progress in `.status` (conditions) and Events.

### Well-known operators

| Operator | API group | Main kinds | What reconcile does |
|---|---|---|---|
| cert-manager | `cert-manager.io` | Issuer, ClusterIssuer, Certificate, CertificateRequest | Requests and renews certificates; writes them into `kubernetes.io/tls` Secrets |
| Prometheus Operator | `monitoring.coreos.com` | Prometheus, Alertmanager, ServiceMonitor, PodMonitor, PrometheusRule | Runs Prometheus/Alertmanager StatefulSets; builds scrape config from ServiceMonitors |
| CloudNativePG | `postgresql.cnpg.io` | Cluster, Backup, ScheduledBackup, Pooler | Runs HA PostgreSQL: primary + replicas, failover, backups |

---

## Key fields / syntax

### CRD anatomy

Full annotated file: [yaml/crd-crontab.yaml](yaml/crd-crontab.yaml). Minimal version (the docs example, trimmed):

```yaml
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: crontabs.stable.example.com     # <plural>.<group> - anything else is rejected
spec:
  group: stable.example.com
  scope: Namespaced                     # or Cluster
  names:
    plural: crontabs
    singular: crontab
    kind: CronTab
    shortNames: ["ct"]
  versions:
  - name: v1
    served: true
    storage: true
    schema:
      openAPIV3Schema:
        type: object
        properties:
          spec:
            type: object
            properties:
              cronSpec:
                type: string
              image:
                type: string
              replicas:
                type: integer
```

| Field | Meaning | Gotcha |
|---|---|---|
| `metadata.name` | Must be `<spec.names.plural>.<spec.group>` | Typos are rejected at create time |
| `spec.group` | API group, DNS-style | CRs use `apiVersion: <group>/<version>` |
| `spec.names.plural` | Used in URLs and `kubectl get crontabs` | Lowercase |
| `spec.names.singular` | CLI alias; `kubectl explain crontab` | Lowercase |
| `spec.names.kind` | CamelCase type in manifests | `kind: CronTab` |
| `spec.names.shortNames` | `kubectl get ct` | Must not clash with other short names |
| `spec.names.categories` | Groups such as `all` | `categories: ["all"]` puts CRs into `kubectl get all` |
| `spec.scope` | `Namespaced` or `Cluster` | Immutable |
| `spec.versions[].served` | Version is exposed by the API | Several versions may be served |
| `spec.versions[].storage` | Version persisted in etcd | **Exactly one** version has `storage: true` |
| `spec.versions[].schema.openAPIV3Schema` | Structural schema (required in `apiextensions.k8s.io/v1`) | Unknown fields are pruned or rejected |
| `spec.versions[].additionalPrinterColumns` | Extra columns for `kubectl get` (`name`, `type`, `jsonPath`) | `jsonPath` starts with `.` |
| `spec.versions[].subresources.status` | Adds `/status`; spec and status are written separately | Main-resource writes ignore `.status` |
| `spec.versions[].subresources.scale` | Adds `/scale` (`kubectl scale`, HPA) | Needs `specReplicasPath` and `statusReplicasPath` |
| `spec.versions[].deprecated`, `deprecationWarning` | Warn clients that use an old version | |
| `spec.conversion.strategy` | `None` (default) or `Webhook` | A webhook is needed when versions' schemas differ |

### Schema validation keywords

| Keyword | Example |
|---|---|
| `type` | `string`, `integer`, `number`, `boolean`, `object`, `array` |
| `required` | `required: ["cronSpec", "image"]` (set on the parent object) |
| `enum`, `pattern` | `enum: ["Always", "Never"]`, `pattern: '^[a-z]+$'` |
| `minimum` / `maximum`, `minLength` / `maxLength`, `maxItems` | `minimum: 1` |
| `default` | `default: 1` (applied by the API server when the field is omitted) |
| `x-kubernetes-preserve-unknown-fields: true` | Keep arbitrary fields under this node (no pruning) |
| `x-kubernetes-int-or-string: true` | Accept `8080` or `"http"` |
| `x-kubernetes-validations` | CEL rules (GA since v1.29), e.g. `rule: "self.replicas <= 10"` |

Unknown fields: `kubectl apply` uses strict server-side field validation by default (`--validate=strict`), so a typo such as `spec.replica` fails with `unknown field "spec.replica"`. With `--validate=false` the field is silently **pruned** (dropped).

### A custom resource

Full file: [yaml/cr-crontab-instance.yaml](yaml/cr-crontab-instance.yaml).

```yaml
apiVersion: stable.example.com/v1    # <group>/<version> from the CRD
kind: CronTab                        # spec.names.kind
metadata:
  name: hourly-cleanup
spec:
  cronSpec: "0 * * * *"
  image: busybox:1.36
  replicas: 2
```

### Finalizers and ownerReferences (brief)

| Mechanism | Where | Effect |
|---|---|---|
| `metadata.finalizers` | On the object being deleted | `kubectl delete` only sets `deletionTimestamp`; the object stays `Terminating` until a controller finishes cleanup and removes its finalizer |
| `metadata.ownerReferences` | On the dependent (child) | The garbage collector deletes children when the owner is deleted (`--cascade=background` default, `foreground`, or `orphan`) |

```yaml
metadata:
  name: hourly-cleanup
  finalizers:
  - stable.example.com/cleanup-jobs   # controller removes this after cleaning up
  ownerReferences:                    # usually set by controllers, not by hand
  - apiVersion: apps/v1
    kind: Deployment
    name: web
    uid: 4b9f8c1e-1111-2222-3333-444455556666
    controller: true
    blockOwnerDeletion: true
```

Built-in examples: `kubernetes.io/pvc-protection` (a PVC in use is not deleted), the `kubernetes` finalizer on Namespaces, ReplicaSet -> Pod ownerReferences.

### Installing an operator (brief)

| Method | Typical commands | Notes |
|---|---|---|
| Helm chart | `helm repo add <repo> <url>` then `helm install <rel> <repo>/<chart> -n <ns> --create-namespace` | CRDs in a chart's `crds/` folder are installed once and never upgraded or deleted by Helm. See [../02-Application-Deployment/README.md](../02-Application-Deployment/README.md) |
| Plain manifests | `kubectl apply --server-side -f <bundle.yaml>` or `kubectl create -f <bundle.yaml>` | Big CRDs exceed the 256 KiB `last-applied-configuration` annotation used by client-side apply; use server-side apply or `create` |
| OLM (Operator Lifecycle Manager) | `Subscription` + `OperatorGroup` -> `InstallPlan` -> `ClusterServiceVersion` | Default on OpenShift; catalogue at operatorhub.io |

After installing: `kubectl get crd | grep <group>`, `kubectl get pods -n <operator-ns>`, `kubectl api-resources --api-group=<group>`, then create the CRs the operator documents.

> **Warning:** `kubectl delete crd <name>` deletes **every custom resource of that type in every namespace**. There is no undo. Back up first (`kubectl get <plural> -A -o yaml > backup.yaml`).

---

## Imperative commands

There is **no** `kubectl create` generator for CRDs or CRs. Copy the CronTab example from the docs, or export an existing object.

```bash
# --- Discover ---
kubectl get crd                                        # all CRDs (cluster-scoped) with creation time
kubectl get crd | grep -i cert-manager                 # find one extension
kubectl get crd crontabs.stable.example.com -o yaml    # full definition: names, versions, schema
kubectl describe crd crontabs.stable.example.com       # includes conditions (Established, NamesAccepted)
kubectl get crd -o custom-columns=NAME:.metadata.name,GROUP:.spec.group,SCOPE:.spec.scope
kubectl api-resources --api-group=stable.example.com   # NAME SHORTNAMES APIVERSION NAMESPACED KIND
kubectl api-resources | grep -i crontab                # same, by name
kubectl api-resources --namespaced=false               # cluster-scoped kinds (incl. Cluster-scoped CRDs)
kubectl api-versions | grep example.com                # served group/versions
kubectl explain crontab                                # kind description from the CRD schema
kubectl explain crontab.spec                           # fields under spec
kubectl explain crontab --recursive                    # whole field tree
kubectl explain crontab --api-version=stable.example.com/v1   # pick a group/version explicitly

# --- Use ---
kubectl get crontabs -A                                # plural
kubectl get ct                                         # short name
kubectl get crontabs.stable.example.com                # fully qualified (when names clash across groups)
kubectl get ct hourly-cleanup -o yaml > ct.yaml        # "generate" YAML from an existing CR
kubectl apply -f ct.yaml --dry-run=server              # validate against the CRD schema, save nothing
kubectl apply -f ct.yaml
kubectl edit ct hourly-cleanup
kubectl patch ct hourly-cleanup --type=merge -p '{"spec":{"replicas":3}}'
kubectl scale ct hourly-cleanup --replicas=3           # only if subresources.scale is defined
kubectl delete ct hourly-cleanup

# --- Create a CRD and wait until it is usable ---
kubectl apply -f crd-crontab.yaml
kubectl wait --for=condition=Established crd/crontabs.stable.example.com --timeout=60s

# --- Operators ---
kubectl get pods -A | grep -i operator                 # where does the controller run?
kubectl logs -n <operator-ns> deploy/<operator-deploy> # why is a CR not reconciled?
kubectl get <plural> <name> -o jsonpath='{.status}'    # what the controller reported
```

---

## Exam traps & tips

> **Exam tip:** "no matches for kind "CronTab" in version ..." means the CRD is missing, not yet Established, or the `apiVersion` group/version is wrong. Check `kubectl api-resources --api-group=<group>`.

> **Exam tip:** A CR's `apiVersion` is `<group>/<version>` (for example `stable.example.com/v1`), never `apiextensions.k8s.io/v1`.

> **Exam tip:** Unsure of a CR's fields? `kubectl explain <kind>.spec` reads the CRD schema. Then `kubectl apply --dry-run=server -f cr.yaml` validates without creating anything.

> **Exam tip:** Short names can be ambiguous between operators (for example several projects define a `certificates` resource). Use the fully qualified `<plural>.<group>` form when writing results to a file.

> **Exam tip:** Namespaced CRs need `-n <ns>` (or `-A`); Cluster-scoped CRs ignore namespaces.

- `metadata.name` of the CRD must equal `<plural>.<group>`, `kind` is CamelCase, `plural`/`singular` are lowercase.
- A CR stuck in `Terminating`: a finalizer is waiting for a controller that is gone or failing. Fix the operator; removing the finalizer (`kubectl patch <kind> <name> --type=merge -p '{"metadata":{"finalizers":null}}'`) is a last resort that can leak external resources.
- `kubectl get all` does not show CRs unless the CRD lists the `all` category.
- Never delete a CRD to "clean up" one object - it deletes all objects of that kind.

---

## Architect notes

- Treat a CRD as a **public API contract**: version it (`v1alpha1` -> `v1beta1` -> `v1`), keep one storage version, plan conversion webhooks and storage-version migration before changing schemas.
- Prefer **CEL validation** (`x-kubernetes-validations`) and ValidatingAdmissionPolicy over custom webhooks: no extra service to run, no webhook outage risk.
- Choose operators by **maturity** (upgrade path, backup/restore, observability, community, CVE response). An operator is privileged software running in your cluster.
- Operators often request **cluster-wide RBAC**. Prefer namespace-scoped installs (watch only selected namespaces) where the operator supports it, and review its ClusterRoles.
- **CRD lifecycle is separate from app lifecycle**: Helm does not upgrade or delete CRDs in `crds/`. Manage CRDs explicitly (GitOps, a dedicated chart, or server-side apply).
- Expose CRs to teams with the aggregation labels `rbac.authorization.k8s.io/aggregate-to-view|edit|admin: "true"` so the built-in roles cover them (see [yaml/clusterrole.yaml](yaml/clusterrole.yaml)).
- Back up CRs with the rest of the namespace (Velero or GitOps). On restore, **CRDs first, then CRs**, then let operators reconcile.
- Watch etcd and API load: thousands of large CRs and chatty controllers are a common cause of API server pressure. Keep `.status` small and use `maxItems`/`maxLength` in schemas.
- For deletion-sensitive external resources (cloud disks, DNS records), operators should use **finalizers**; platform teams should alert on objects stuck in `Terminating`.

---

## Docs to bookmark

- https://kubernetes.io/docs/tasks/extend-kubernetes/custom-resources/custom-resource-definitions/ (CronTab example to copy)
- https://kubernetes.io/docs/concepts/extend-kubernetes/api-extension/custom-resources/
- https://kubernetes.io/docs/tasks/extend-kubernetes/custom-resources/custom-resource-definition-versioning/
- https://kubernetes.io/docs/concepts/extend-kubernetes/operator/
- https://kubernetes.io/docs/concepts/extend-kubernetes/
- https://kubernetes.io/docs/concepts/overview/working-with-objects/finalizers/
- https://kubernetes.io/docs/concepts/overview/working-with-objects/owners-dependents/

---

## Quick self-check

1. What must `metadata.name` of a CRD with group `shop.example.com` and plural `orders` be?
2. Which command lists every resource type served by the `cert-manager.io` group, with short names?
3. You created a CRD and a CR in the same `kubectl apply`, and the CR failed with "no matches for kind". Why, and how do you avoid it?
4. What happens to existing CronTab objects when you run `kubectl delete crd crontabs.stable.example.com`?
5. A custom resource stays in `Terminating` for ten minutes. What is the most likely cause?
6. What is the difference between a CRD and an operator?

<details><summary>Answers</summary>

1. `orders.shop.example.com`.
2. `kubectl api-resources --api-group=cert-manager.io`.
3. The CRD was not yet Established when the CR was sent. Apply the CRD first and run `kubectl wait --for=condition=Established crd/<name>`, then apply the CR.
4. They are all deleted, in every namespace, irreversibly.
5. A finalizer is still present and the controller responsible for removing it is missing or failing. Check the operator's Pods and logs.
6. A CRD only defines a new API type (storage, REST endpoint, validation). An operator is a CRD plus a controller that watches those objects and reconciles real resources to match them.

</details>
