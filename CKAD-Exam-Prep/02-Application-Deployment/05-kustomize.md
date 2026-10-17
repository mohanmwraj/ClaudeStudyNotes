# Kustomize

**Why it matters.** "Kustomize" is a competency of its own. It is built into kubectl (`kubectl kustomize`, `kubectl apply -k`), so it is always available on the exam host. A standalone `kustomize` binary may not be. Typical tasks:

- apply or render an existing kustomization (to a file)
- create an overlay that sets a namespace, prefix, labels, replicas or image tag
- add a ConfigMap/Secret generator
- write a strategic-merge or JSON6902 patch
- fix a broken kustomization

## Core concepts

| Concept | Meaning |
|---|---|
| **kustomization.yaml** | Declares input `resources` plus generators and transformers. No templating: inputs and output are plain Kubernetes YAML |
| **Base** | A directory with a kustomization (and manifests) that knows nothing about its users |
| **Overlay** | A kustomization that lists a base in `resources:` and adds environment-specific changes |
| **Generator** | Creates objects: `configMapGenerator`, `secretGenerator` (names get a content hash) |
| **Transformer** | Changes every (matching) object: namespace, prefix/suffix, labels, annotations, images, replicas, patches |
| **Component** | A reusable, optional bundle of changes (`kind: Component`) mixed into overlays |

**Processing order** (verified in the kustomize source, v5.x):

1. Load `resources` (a base is fully built first, recursively).
2. Run generators: ConfigMaps, then Secrets.
3. Run transformers in a fixed order: `patchesStrategicMerge` → `patches` → `namespace` → `namePrefix` → `nameSuffix` → `labels`/`commonLabels` → `commonAnnotations` → `patchesJson6902` → `replicas` → `images` → `replacements`.
4. Update references to renamed objects (prefix, suffix, hash), then print, Namespaces first.

Consequences:

- Patches refer to the **base names** (`web`, not `dev-web`).
- `replicas:` overrides a patch that sets replicas.
- `images:` overrides a patch's image.
- The YAML order of fields in `kustomization.yaml` does not matter.

**Versions**: kubectl v1.37, the exam's version, embeds Kustomize v5.8.1. v1.33 embeds v5.6.0 and v1.35 v5.7.1. `kubectl version --client` prints it. All fields below work in these versions.

## Key fields / syntax

### Every common field in one file

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:                         # files, directories (bases), or remote URLs
- ../../base
- namespace.yaml
namespace: prod                    # sets metadata.namespace on every namespaced object
namePrefix: prod-                  # web -> prod-web (not applied to Namespace/CRD/APIService objects)
nameSuffix: -v2                    # prod-web -> prod-web-v2
labels:
- pairs:
    env: prod
  includeSelectors: true           # default false: metadata.labels only
  includeTemplates: true           # default false (implied by includeSelectors: true)
commonAnnotations:
  team: web-platform               # every object AND Pod templates
images:
- name: nginx                      # image name as written in the manifests (tag ignored when matching)
  newName: registry.example.com/nginx
  newTag: "1.27-alpine"            # or: digest: sha256:<64 hex chars>  (replaces the tag)
replicas:
- name: web                        # Deployment / StatefulSet / ReplicaSet name
  count: 4
configMapGenerator:
- name: web-config
  literals:
  - LOG_LEVEL=warn
  files:
  - nginx.conf                     # key = file name
  - app.properties=config/prod.properties   # key=path
  envs:
  - config/.env                    # each KEY=VALUE line becomes a key
  behavior: create                 # create (default) | merge | replace (modify a base generator)
secretGenerator:
- name: web-secret
  type: Opaque                     # default; e.g. kubernetes.io/tls with files tls.crt / tls.key
  literals:
  - API_TOKEN=change-me            # base64-encoded for you
generatorOptions:
  disableNameSuffixHash: false     # true = stable names (but no automatic rollout on change)
  labels:
    generated-by: kustomize
patches:
- path: patch-resources.yaml       # strategic merge, target from apiVersion/kind/metadata.name
- target:                          # JSON6902: target required
    kind: Deployment
    name: web
  patch: |-
    - op: add
      path: /spec/minReadySeconds
      value: 10
components:
- ../../components/monitoring
```

A complete, verified base/overlay set lives in [yaml/kustomize/](yaml/kustomize/README.md).

### Field reference

| Field | What it does | Watch out |
|---|---|---|
| `resources` | Inputs: files, directories with a kustomization, `github.com/org/repo//path?ref=v1.2.3` | A missing file is a hard error. Remote URLs need internet |
| `namespace` | Sets (overrides) `metadata.namespace` on all namespaced objects. A `Namespace` object in `resources` is **renamed** to this value | Does not create the namespace: include a Namespace object or create it first. Check RoleBinding `subjects[].namespace` in the output (in tests it was not changed) |
| `namePrefix` / `nameSuffix` | Renames objects and updates known references: `configMapRef`, `secretRef`, volumes, `serviceAccountName`, Ingress `backend.service.name`, RoleBinding `roleRef`, ... | Strings inside env values, args or URLs are not updated (use `replacements`) |
| `labels` | Adds labels: `includeSelectors: false` (default) → metadata only. `includeTemplates: true` → also Pod templates. `includeSelectors: true` → metadata + selectors + templates | Selectors of an existing Deployment are immutable: changing them breaks `kubectl apply` |
| `commonLabels` (deprecated) | Same as `labels` with `includeSelectors: true` (always touches selectors) | Prints a deprecation warning |
| `commonAnnotations` | Annotations on every object and Pod template | Changing one re-rolls every Deployment |
| `images` | `newName`, `newTag`, `digest` for each container image (containers and initContainers) whose name matches `name` | `name` is the image without its tag (`nginx`, `registry/app`) |
| `replicas` | Sets `spec.replicas` by object name (base name or renamed name) | Runs after patches, so it wins over them |
| `configMapGenerator` / `secretGenerator` | Generate objects named `<name>-<hash>` from `literals`, `files`, `envs`. `behavior: merge` or `behavior: replace` modifies a base's generator of the same name | The old hashed ConfigMap stays in the cluster after apply |
| `generatorOptions` | `disableNameSuffixHash`, `labels`, `annotations`, `immutable` for all generators in this kustomization | Disabling the hash disables hash-driven rollouts |
| `patches` | Strategic-merge or JSON6902 patches, from a file (`path`) or inline (`patch`), with an optional `target` | JSON6902 always needs a `target` |
| `components` | Mix in `kind: Component` directories | `apiVersion: kustomize.config.k8s.io/v1alpha1` |
| `replacements` | Copy a field value from one object into fields of others | Successor of `vars` |

### Generators and the hash suffix (why they trigger rollouts)

```text
configMapGenerator name: web-config  ──►  ConfigMap web-config-758kt8k87t
Deployment envFrom.configMapRef.name: web-config  ──►  rewritten to web-config-758kt8k87t
change LOG_LEVEL  ──►  new hash web-config-k675bbfg64  ──►  Pod template changed  ──►  rolling update
```

Plain Kubernetes doesn't restart Pods when a ConfigMap changes. The hash suffix makes every config change a template change, and that is what starts a rollout. With `disableNameSuffixHash: true` the name stays `web-config`, so after an update you need `kubectl rollout restart`. The previous ConfigMap is not deleted by `kubectl apply -k`. Clean it up, or keep it so a `rollout undo` still finds its config.

Overlay generators modify base generators by name:

```yaml
# overlays/dev/kustomization.yaml (excerpt)
configMapGenerator:
- name: web-config        # must equal the base generator's name (and namespace)
  behavior: merge         # keep base keys, override/add these
  literals:
  - LOG_LEVEL=debug
```

### Patches

**Strategic-merge patch (SMP).** You write a partial object. Kustomize finds the target from `apiVersion`/`kind`/`metadata.name` (or `target:`) and merges using Kubernetes merge keys.

```yaml
# overlays/dev/patch-replicas.yaml: a PARTIAL object (only identity + changed fields)
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web            # the <base> name, before namePrefix
spec:
  replicas: 1
```

```yaml
# overlays/prod/patch-resources.yaml: lists with a merge key are merged element by element
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web            # <base> name
spec:
  template:
    spec:
      containers:
      - name: web      # merge key "name": only this container changes
        resources:
          limits:
            memory: 256Mi
```

SMP list semantics (verified):

| List | Merge key | Patch behaviour |
|---|---|---|
| `containers`, `initContainers`, `volumes`, `env`, `volumeMounts` | `name` (`mountPath` for volumeMounts) | Element-wise merge |
| `ports` (container) | `containerPort` | Element-wise merge |
| `envFrom`, `args`, `command`, `tolerations` | none | **The whole list is replaced** |
| Delete an element | `- name: sidecar` + `$patch: delete` | Removes that element |

**JSON6902 patch (RFC 6902).** A list of operations on JSON-pointer paths. It needs a `target`, and it is precise for lists without merge keys, appends and deletions.

```yaml
# inline under patches: (or in a separate file referenced by path:)
- op: replace                                   # change an existing value
  path: /spec/strategy/rollingUpdate/maxUnavailable
  value: 0
- op: add                                       # add a key (creates or overwrites it)
  path: /spec/minReadySeconds
  value: 10
- op: add                                       # append to an EXISTING list ("-" = end)
  path: /spec/template/spec/containers/0/env/-
  value: {name: ENVIRONMENT, value: production}
- op: remove
  path: /spec/template/spec/containers/0/resources/limits/cpu
- op: add                                       # "/" inside a key is written ~1
  path: /metadata/annotations/example.com~1owner
  value: team-a
```

Wiring it in (file variant). The target can match several objects at once:

```yaml
patches:
- path: patch-json6902.yaml
  target:
    group: apps
    version: v1
    kind: Deployment
    name: web                      # regex allowed, e.g. "web-.*"
- path: patch-tolerations.yaml
  target:
    kind: Deployment
    labelSelector: "tier=frontend" # every matching Deployment
```

JSON6902 pitfalls (verified):

- `add .../env/-` fails with `doc is missing path` when `env` doesn't exist. Add the whole list instead (`path: .../env`, `value: [ ... ]`).
- `replace` fails when a parent path is missing. Use `add` for keys that may not exist.

### Components (brief)

```yaml
# components/monitoring/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1alpha1
kind: Component
commonAnnotations:
  prometheus.io/scrape: "true"
```

An overlay opts in with `components: [../../components/monitoring]`. Components are like mixins: several overlays can share one optional feature without building a base chain.

### Deprecated fields (still work, print a warning)

| Deprecated | Use instead | Warning printed by kubectl kustomize (verified) |
|---|---|---|
| `bases:` | `resources:` | `# Warning: 'bases' is deprecated. Please use 'resources' instead. Run 'kustomize edit fix' ...` |
| `commonLabels:` | `labels:` (with `includeSelectors` as needed) | `# Warning: 'commonLabels' is deprecated. Please use 'labels' instead. ...` |
| `patchesStrategicMerge:` | `patches:` | `# Warning: 'patchesStrategicMerge' is deprecated. Please use 'patches' instead. ...` |
| `patchesJson6902:` | `patches:` (with `target`) | `# Warning: 'patchesJson6902' is deprecated. Please use 'patches' instead. ...` |
| `vars:` | `replacements:` | `# Warning: 'vars' is deprecated. Please use 'replacements' instead. ...` |
| `imageTags:` | `images:` | `# Warning: 'imageTags' is deprecated. Please use 'images' instead. ...` |

`kustomize edit fix` (standalone binary) rewrites a kustomization to the new fields. If you meet a deprecated field in the exam, it still works. Don't spend time migrating it unless the task asks.

### Base / overlay layout

```text
yaml/kustomize/
├── base/                     kustomization.yaml, deployment.yaml, service.yaml (+ configMapGenerator)
└── overlays/
    ├── dev/                  namespace dev, prefix dev-, env=dev, replicas 1 (SMP), LOG_LEVEL=debug (merge)
    └── prod/                 namespace prod, prefix prod-, env=prod, 4 replicas, nginx:1.27-alpine,
                              resources (SMP), maxUnavailable 0 + env + envFrom secret (JSON6902), secretGenerator
```

Files: [base/kustomization.yaml](yaml/kustomize/base/kustomization.yaml) · [overlays/dev/kustomization.yaml](yaml/kustomize/overlays/dev/kustomization.yaml) · [overlays/dev/patch-replicas.yaml](yaml/kustomize/overlays/dev/patch-replicas.yaml) · [overlays/prod/kustomization.yaml](yaml/kustomize/overlays/prod/kustomization.yaml) · [overlays/prod/patch-resources.yaml](yaml/kustomize/overlays/prod/patch-resources.yaml).

## Imperative commands

```bash
# Built into kubectl (always available)
kubectl kustomize overlays/prod                      # render to stdout (no cluster changes)
kubectl kustomize overlays/prod > /opt/out.yaml      # save the rendered manifest
kubectl apply -k overlays/prod                       # build + apply
kubectl apply -k overlays/prod --dry-run=server      # validate against the API server, change nothing
kubectl diff -k overlays/prod                        # exit 0 = no diff, 1 = differences
kubectl get -k overlays/prod                         # the live objects this kustomization manages
kubectl describe -k overlays/prod
kubectl delete -k overlays/prod
kubectl version --client                             # shows the embedded Kustomize version

# Standalone kustomize binary (if installed): edits kustomization.yaml in the CURRENT directory
kustomize create --autodetect                        # new kustomization.yaml listing local manifests
kustomize create --resources ../../base --namespace prod --nameprefix prod-
kustomize edit add resource service.yaml
kustomize edit set image nginx=nginx:1.27-alpine     # -> images: [{name: nginx, newName: nginx, newTag: 1.27-alpine}]
kustomize edit set image nginx=*:1.27-alpine         # "*" keeps the existing name, sets only the tag
kustomize edit set namespace prod
kustomize edit set nameprefix prod-
kustomize edit set namesuffix -- -v2                 # "--" because the value starts with "-"
kustomize edit set replicas web=4
kustomize edit add configmap web-config --from-literal=LOG_LEVEL=warn
kustomize edit add secret web-secret --from-literal=API_TOKEN=x
kustomize edit add patch --path patch-resources.yaml --kind Deployment --name web
kustomize edit add label env:prod --without-selector # plain "add label" writes deprecated commonLabels
kustomize edit add annotation team:web-platform
kustomize edit add component ../../components/monitoring
kustomize edit fix                                   # migrate deprecated fields
kustomize build overlays/prod                        # same as kubectl kustomize
```

No standalone binary? Write the file directly. This is the fastest exam route:

```bash
mkdir -p overlays/staging && cat > overlays/staging/kustomization.yaml <<'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- ../../base
namespace: staging
namePrefix: staging-
images:
- name: nginx
  newTag: "1.27-alpine"
replicas:
- name: web
  count: 2
EOF
kubectl kustomize overlays/staging | grep -E 'name:|image:|replicas:|namespace:'
```

## Helm vs Kustomize

| | Helm | Kustomize |
|---|---|---|
| Model | Go-template **packages** + values | Template-free **overlays/patches** on plain YAML |
| Install | Separate `helm` binary | Built into kubectl (`-k`) |
| Parameters | `values.yaml`, `-f`, `--set` | Patches, generators, transformers |
| Release state | Yes: revisions in Secrets, `history`, `rollback`, `uninstall` | None: it's just `kubectl apply`. Roll back by re-applying an older version (git) |
| Distribution | Repos and OCI registries, versioned charts, dependencies | Git directories / remote URLs |
| Rendering check | `helm template` | `kubectl kustomize` |
| Strength | Shareable, configurable third-party apps | Per-environment variants of your own manifests, no template syntax |
| Weakness | Template complexity, values sprawl | No packaging, versioning or lifecycle hooks |
| Exam verbs | repo add/update, search, show values, install, upgrade, rollback, uninstall, list, history, template, pull | kustomize, apply -k, diff -k, delete -k, write kustomization.yaml/patches |

They also combine: Kustomize can inflate charts (`helmCharts:`, needs `--enable-helm`), and Helm can post-render through Kustomize.

## Exam traps & tips

> **Exam tip:** `-k` takes a **directory**, not a file: `kubectl apply -k overlays/prod`. With `-f kustomization.yaml` kubectl tries to create a "Kustomization" object and fails.

> **Exam tip:** Patch targets use the **original (base) names**. A patch for `prod-web` that names `prod-web` won't match. Name `web`.

> **Exam tip:** `namespace:` in a kustomization does not create the namespace. Add a Namespace manifest to `resources` or `kubectl create ns` first, or `apply -k` fails with `namespaces "x" not found`.

> **Exam tip:** `labels` with `includeSelectors: true` (or `commonLabels`) on an overlay for an **already deployed** Deployment changes its immutable selector, and `kubectl apply -k` fails. Use `includeSelectors: false` for existing workloads.

> **Exam tip:** A strategic-merge patch that sets `envFrom`, `args`, `command` or `tolerations` **replaces** the whole list. To append, use a JSON6902 `add` with `/-`.

> **Exam tip:** Quote numeric-looking tags in `images: newTag:` (e.g. `"1.20"`). Unquoted `1.20` is a YAML number and the build fails: `cannot unmarshal number into Go struct field Kustomization.images.0.newTag of type string` (verified).

> **Exam tip:** Render before applying (`kubectl kustomize dir | less`). It's the fastest way to check prefix, namespace, labels and patches. If the task wants the output saved, redirect it to the requested path.

## Architect notes

- **Base = the contract, overlays = the environments.** Keep bases minimal and environment-neutral. Put cross-cutting optional features in `components` instead of deep base chains.
- **Selector labels**: decide them once in the base. Add environment labels with `includeSelectors: false` unless an overlay creates brand-new workloads.
- **Generators give config versioning for free.** Hash-suffixed ConfigMaps/Secrets roll Pods on change and let a rollback find the old config. Plan garbage collection (`kubectl apply --prune` with an applyset, or GitOps pruning).
- **Secrets**: `secretGenerator` literals in git are plain text. Pair Kustomize with SOPS/KSOPS, Sealed Secrets or External Secrets.
- **GitOps fit**: Argo CD and Flux build kustomizations natively. Rollback = `git revert`. Pin remote bases with `?ref=<tag>`.
- **`replacements` over hard-coded names**: when a value must follow a renamed object (a Service name in an env var or URL), use `replacements` so prefixes and suffixes propagate.
- **Validate the output, not the inputs**: run `kubectl kustomize ... | kubeconform` (or `kubectl apply --dry-run=server`) in CI. Patch files are partial objects and fail schema linters by design.

## Docs to bookmark

In the exam only kubernetes.io/docs, kubernetes.io/blog and helm.sh/docs are allowed. Kustomize's own sites (kubectl.docs.kubernetes.io, kustomize.io, GitHub) are **not**. Bookmark the kubernetes.io page. It covers generators, generatorOptions, cross-cutting fields (namespace, prefix/suffix, labels, annotations), patches (SMP and JSON6902 with `target`), images, replacements, bases/overlays, the `-k` commands and the field list. It does **not** show `behavior: merge|replace`, so memorise that from this chapter.

- Declarative management with Kustomize: https://kubernetes.io/docs/tasks/manage-kubernetes-objects/kustomization/
  - Generators: https://kubernetes.io/docs/tasks/manage-kubernetes-objects/kustomization/#generating-resources
  - Cross-cutting fields: https://kubernetes.io/docs/tasks/manage-kubernetes-objects/kustomization/#setting-cross-cutting-fields
  - Patches, images, replacements: https://kubernetes.io/docs/tasks/manage-kubernetes-objects/kustomization/#customizing
  - Bases and overlays: https://kubernetes.io/docs/tasks/manage-kubernetes-objects/kustomization/#bases-and-overlays
  - Field list: https://kubernetes.io/docs/tasks/manage-kubernetes-objects/kustomization/#kustomize-feature-list
- `kubectl kustomize` reference: https://kubernetes.io/docs/reference/kubectl/generated/kubectl_kustomize/
- For study only (not allowed in the exam): the Kustomize field reference at https://kubectl.docs.kubernetes.io/references/kustomize/kustomization/

## Quick self-check

1. Base Deployment `web`, overlay with `namePrefix: dev-`. What `metadata.name` does your patch file use?
2. You change a `configMapGenerator` literal and run `kubectl apply -k`. Why do the Pods restart, and what is left behind?
3. You want `env=prod` on every object, but the Deployment already runs in the cluster. Which `labels` setting do you use, and why?
4. Write the JSON6902 op that appends env var `TIER=web` to the first container, assuming `env` already exists.
5. An overlay must change only the tag of image `nginx` to `1.27-alpine`. Which field?
6. Name the replacement for `bases`, `commonLabels`, `patchesStrategicMerge` and `vars`.

<details><summary>Answers</summary>

1. `web`. Patches match the original (base) name.
2. The ConfigMap gets a new hash name, the reference in the Pod template is rewritten, and a template change triggers a rolling update. The old `web-config-<oldhash>` ConfigMap stays in the cluster.
3. `labels: [{pairs: {env: prod}, includeSelectors: false}]` (optionally `includeTemplates: true`). Selectors are immutable, so changing them would make `apply` fail.
4. `- op: add` / `path: /spec/template/spec/containers/0/env/-` / `value: {name: TIER, value: web}`.
5. `images: [{name: nginx, newTag: "1.27-alpine"}]`.
6. `resources`, `labels`, `patches`, `replacements`.

</details>
