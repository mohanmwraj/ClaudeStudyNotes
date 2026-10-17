# ConfigMaps

**Competency:** *Understand ConfigMaps*

**Why it matters / what the exam expects:** one of the most frequent task types. Create a ConfigMap from literals, files, directories or env-files, then consume it as single env vars, all-keys env vars, a mounted directory, selected files, or one file dropped into an existing directory (`subPath`). Know what updates live and what needs a restart.

---

## Core concepts

- A ConfigMap stores **non-confidential** key/value configuration, namespaced; a Pod can only use ConfigMaps from **its own namespace**.
- `data` holds UTF-8 strings, `binaryData` holds base64-encoded bytes; keys may contain letters, digits, `-`, `_`, `.`. Total size limit **1 MiB**.
- It decouples configuration from the image: same image, different ConfigMap per environment.
- Static Pods cannot use ConfigMaps.

| Consumption mode | Pod spec | Live update when the ConfigMap changes? |
|---|---|---|
| One env var per key | `env[].valueFrom.configMapKeyRef` | **No** - restart the Pod |
| All keys as env vars | `envFrom[].configMapRef` (+ `prefix`) | **No** |
| Volume, all keys | `volumes[].configMap.name` | **Yes, eventually** (kubelet sync + cache TTL, up to roughly 1-2 min) |
| Volume, selected keys | `configMap.items[{key, path, mode}]` | Yes, eventually |
| One file via `subPath` | `volumeMounts[].subPath` | **Never** |
| Projected volume | `projected.sources[].configMap` | Yes, eventually |
| Command arguments | `args: ["--mode=$(APP_MODE)"]` (from an env var) | No |
| App reads the API | client library + RBAC `get`/`watch` on configmaps | Yes (watch) |

What happens when something is missing:

| Reference | ConfigMap or key missing, not `optional` | With `optional: true` |
|---|---|---|
| `configMapKeyRef` / `envFrom` | Container stays in `CreateContainerConfigError` (`configmap "x" not found`, `couldn't find key ...`) | Var not set / nothing imported, Pod starts |
| Volume | Pod stuck in `ContainerCreating`, event `FailedMount ... configmap "x" not found` | Empty directory (missing keys are absent) |

**Immutable ConfigMaps** (`immutable: true`): data can never change (delete and recreate); kubelets stop watching them, which reduces API load in big clusters. Use versioned names (`app-config-v2`) and roll Deployments to the new name.

---

## Key fields / syntax

### The object

Full file: [yaml/configmap.yaml](yaml/configmap.yaml).

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config
data:
  APP_MODE: production
  MAX_CONNECTIONS: "100"          # strings only - quote numbers and booleans
  app.properties: |               # file-style key
    server.port=8080
    cache.ttl.seconds=300
binaryData:
  sample.bin: AAECAw==
immutable: false
```

### Env: single keys and all keys

Files: [yaml/pod-configmap-env.yaml](yaml/pod-configmap-env.yaml), [yaml/pod-configmap-envfrom.yaml](yaml/pod-configmap-envfrom.yaml).

```yaml
env:
- name: MODE                      # env var name can differ from the key
  valueFrom:
    configMapKeyRef:
      name: app-config
      key: APP_MODE
      optional: true              # Pod starts even if the map or key is missing
envFrom:
- configMapRef:
    name: app-config              # every key -> env var of the same name
- prefix: CFG_                    # CFG_APP_MODE, CFG_MAX_CONNECTIONS, ...
  configMapRef:
    name: app-config
```

Since v1.32 (beta, GA v1.34) env var names may contain any printable ASCII except `=`, so `envFrom` imports keys like `app.properties` as-is. Older clusters skip such keys and record an `InvalidEnvironmentVariableNames` event. An explicit `env` entry wins over `envFrom`.

### Volume: whole map, selected keys, subPath

File: [yaml/pod-configmap-volume.yaml](yaml/pod-configmap-volume.yaml).

```yaml
spec:
  containers:
  - name: nginx
    image: nginx:1.27
    volumeMounts:
    - name: config-all
      mountPath: /etc/app                         # whole directory REPLACED by the keys
      readOnly: true
    - name: config-selected
      mountPath: /etc/app-selected
    - name: nginx-conf
      mountPath: /etc/nginx/conf.d/default.conf   # a single file ...
      subPath: default.conf                       # ... rest of conf.d kept; no live updates
  volumes:
  - name: config-all
    configMap:
      name: app-config
  - name: config-selected
    configMap:
      name: app-config
      defaultMode: 0440                           # octal in YAML (decimal 288 in JSON); default 0644
      items:
      - key: app.properties
        path: application.properties              # file name inside the mount
        mode: 0400                                # per-file override
  - name: nginx-conf
    configMap:
      name: nginx-conf
```

Inside a ConfigMap volume each key is a symlink to `..data/<key>`, and `..data` is itself a symlink to a hidden, timestamped directory. On updates the kubelet writes a new timestamped directory and swaps `..data` atomically - which is exactly why `subPath` mounts, bound to the old file, never update.

---

## Imperative commands

```bash
# --- Create ---
kubectl create configmap app-config --from-literal=APP_MODE=production --from-literal=LOG_LEVEL=info
kubectl create configmap app-props --from-file=app.properties                        # key = file name
kubectl create configmap app-props --from-file=application.properties=conf/app.properties   # custom key
kubectl create configmap app-dir --from-file=conf/                                   # one key per regular file (subdirs/symlinks ignored)
kubectl create configmap app-env --from-env-file=app.env                            # one key per KEY=VALUE line
kubectl create configmap app-env2 --from-env-file=a.env --from-env-file=b.env        # several env-files (v1.23+)
kubectl create configmap app-config --from-literal=APP_MODE=dev --dry-run=client -o yaml > cm.yaml   # generate YAML
kubectl create configmap app-config-v2 --from-literal=APP_MODE=prod --append-hash    # name gets a content-hash suffix

# --- Update (create refuses to overwrite: "already exists") ---
kubectl create configmap app-props --from-file=app.properties --dry-run=client -o yaml | kubectl apply -f -
kubectl edit configmap app-config
kubectl patch configmap app-config --type=merge -p '{"data":{"LOG_LEVEL":"debug"}}'
kubectl rollout restart deploy/web                       # env-var consumers only see new values after a restart

# --- Consume imperatively ---
kubectl set env deploy/web --from=configmap/app-config                     # one configMapKeyRef per key
kubectl set env deploy/web --from=configmap/app-config --prefix=CFG_ --keys=APP_MODE,LOG_LEVEL
kubectl set env deploy/web --list                                          # show resulting env

# --- Inspect ---
kubectl get configmaps                                   # short name: cm
kubectl describe cm app-config
kubectl get cm app-config -o yaml
kubectl get cm app-config -o jsonpath='{.data.APP_MODE}{"\n"}'
kubectl get cm app-props -o jsonpath='{.data.app\.properties}'             # escape dots in key names
kubectl exec web -- ls -la /etc/app                      # keys as files (symlinks to ..data)
kubectl exec web -- env | grep -i app_

# --- Delete ---
kubectl delete cm app-config
```

Env-file rules: one `KEY=VALUE` per line, lines starting with `#` and blank lines are ignored, quotes are **kept** as part of the value. `--from-env-file` cannot be combined with `--from-literal` or `--from-file` in one command. Files that are not valid UTF-8 go to `binaryData` automatically.

```text
# app.env
APP_MODE=production
LOG_LEVEL=info
# comment lines and blank lines are ignored
GREETING="hello"
```

Result: three keys; `GREETING` is stored as `"hello"` **including** the quote characters.

### Generate with Kustomize (built into kubectl)

A `configMapGenerator` appends a content hash to the name and rewrites references, so every config change rolls the Deployment automatically. Details: [../02-Application-Deployment/README.md](../02-Application-Deployment/README.md).

```yaml
# kustomization.yaml  ->  kubectl apply -k .   (preview: kubectl kustomize .)
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- deployment.yaml
configMapGenerator:
- name: app-config
  literals:
  - APP_MODE=production
  files:
  - app.properties
```

---

## Exam traps & tips

> **Exam tip:** "Mount the ConfigMap so that key X appears as file Y in directory Z" -> `items: [{key: X, path: Y}]` with `mountPath: Z`. "Add file Y to an existing directory without hiding the other files" -> `subPath`.

> **Exam tip:** mounting a ConfigMap volume at an existing directory (e.g. `/etc/nginx`) **hides everything** that was there. nginx then fails because `nginx.conf` and `mime.types` are gone. Mount to `conf.d/` or use `subPath`.

> **Exam tip:** changed a ConfigMap used via env vars? Nothing happens until the Pods are recreated: `kubectl rollout restart deploy/<name>`.

> **Exam tip:** in YAML `data:` every value must be a string. `PORT: 8080` or `DEBUG: true` makes the apply fail; write `"8080"` and `"true"`.

> **Exam tip:** volume field names differ: ConfigMap volumes use `configMap.name`, Secret volumes use `secret.secretName`, projected sources use `name` for both.

- `kubectl create configmap` on an existing name fails - regenerate with `--dry-run=client -o yaml | kubectl apply -f -`.
- ConfigMaps are namespaced: create them in the Pod's namespace (`-n`).
- `kubectl describe cm` shows values (unlike Secrets); `-o jsonpath` needs `\.` for keys containing dots.
- `defaultMode: 0644` is octal in YAML; in JSON patches use decimal (`420`).
- Apps that read config only at start-up need a restart even with volume mounts.

---

## Architect notes

- **Configuration as code:** generate ConfigMaps with Kustomize/Helm so a content hash in the name drives automatic rollouts and clean rollbacks; avoid `kubectl edit` in production.
- **Immutable + versioned** ConfigMaps are safer (no half-applied edits) and scale better (no kubelet watches); garbage-collect old versions.
- **Never store secrets in ConfigMaps** - the built-in `view` role can read ConfigMaps but not Secrets.
- **Hot reload is an application concern:** volume files change, but the app must notice (inotify/polling). Otherwise prefer a deliberate rolling restart (or a controller such as Stakater Reloader) for predictable behaviour.
- Keep ConfigMaps small: the 1 MiB limit and etcd/watch costs make them a poor fit for large data sets; ship big static content in the image or fetch it from object storage.
- Validate configuration before rollout (schema checks in CI, `kubectl apply --dry-run=server`, readiness probes that fail on bad config).
- Use `optional: true` only when absence is really acceptable - otherwise it turns a loud failure into silent misconfiguration.
- For frequently changing feature flags, use a dedicated feature-flag service rather than Pod restarts.

---

## Docs to bookmark

- https://kubernetes.io/docs/concepts/configuration/configmap/
- https://kubernetes.io/docs/tasks/configure-pod-container/configure-pod-configmap/ (every creation and consumption mode with examples)
- https://kubernetes.io/docs/tasks/manage-kubernetes-objects/kustomization/
- https://kubernetes.io/docs/reference/kubectl/generated/kubectl_create/kubectl_create_configmap/
- https://kubernetes.io/docs/reference/kubectl/generated/kubectl_set/kubectl_set_env/

---

## Quick self-check

1. Which command creates a ConfigMap whose key is `nginx.conf` from the file `./conf/web.conf`?
2. You updated a ConfigMap. Which consumers see the change without a restart?
3. How do you put only `default.conf` into `/etc/nginx/conf.d/` without hiding the other files there?
4. A Pod is stuck in `CreateContainerConfigError`. What is a likely ConfigMap-related cause?
5. What is the effect of `immutable: true` and how do you change such a ConfigMap?

<details><summary>Answers</summary>

1. `kubectl create configmap <name> --from-file=nginx.conf=./conf/web.conf`.
2. Only volume mounts without `subPath` (after the kubelet sync delay), and apps that watch the API. Env vars and subPath files never change.
3. Mount with `mountPath: /etc/nginx/conf.d/default.conf` and `subPath: default.conf`.
4. The referenced ConfigMap or key does not exist (and the reference is not `optional`) - `kubectl describe pod` shows the exact message.
5. Its data can never be modified; delete and recreate it (better: create a new versioned name and roll the workload to it).

</details>
