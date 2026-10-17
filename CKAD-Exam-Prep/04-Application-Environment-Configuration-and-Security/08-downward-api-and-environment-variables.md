# Downward API and Environment Variables

**Competencies supported:** *Understand ConfigMaps*, *Create & consume Secrets* and application configuration in general (env vars are how most config reaches a container).

**Why it matters / what the exam expects:** inject Pod metadata (name, namespace, IP, node, labels, resource limits) into a container through env vars or files, compose variables with `$(VAR)`, know which source wins when names collide, and use `kubectl set env` and `kubectl exec -- env` quickly.

---

## Core concepts

### Every way to set an env var

| Form | YAML | Source |
|---|---|---|
| Literal | `env: [{name: MODE, value: "prod"}]` | The manifest |
| Pod field | `valueFrom.fieldRef.fieldPath` | Downward API (metadata, spec, status) |
| Container resources | `valueFrom.resourceFieldRef {containerName, resource, divisor}` | Downward API (requests/limits) |
| ConfigMap key | `valueFrom.configMapKeyRef {name, key, optional}` | [04](04-configmaps.md) |
| Secret key | `valueFrom.secretKeyRef {name, key, optional}` | [05](05-secrets.md) |
| All keys | `envFrom: [{configMapRef: {name}}, {secretRef: {name}, prefix: "DB_"}]` | ConfigMap / Secret |

Values must be **strings** (`value: "8443"`, not `8443`). Env vars are fixed at container start.

### Downward API fields: env vs volume

| Field | `env` (`fieldRef`) | `downwardAPI` volume | Notes |
|---|---|---|---|
| `metadata.name` | Yes | Yes | Pod name |
| `metadata.namespace` | Yes | Yes | |
| `metadata.uid` | Yes | Yes | |
| `metadata.labels['<key>']` | Yes | Yes | One label |
| `metadata.annotations['<key>']` | Yes | Yes | One annotation |
| `metadata.labels` | **No** | Yes | All labels, one `key="value"` per line |
| `metadata.annotations` | **No** | Yes | All annotations |
| `spec.nodeName` | Yes | **No** | Node the Pod runs on |
| `spec.serviceAccountName` | Yes | **No** | |
| `status.podIP` / `status.podIPs` | Yes | **No** | `podIPs` = dual-stack list |
| `status.hostIP` / `status.hostIPs` | Yes | **No** | Node IP(s) |

`resourceFieldRef` works in both (in a volume `containerName` is **required**): `limits.cpu`, `requests.cpu`, `limits.memory`, `requests.memory`, `limits.ephemeral-storage`, `requests.ephemeral-storage`, `limits.hugepages-*`, `requests.hugepages-*`.

- `divisor` scales the value: `1m` -> CPU in millicores, `1Mi` -> memory in MiB. The default divisor `1` **rounds CPU up** to whole cores (`250m` -> `1`).
- If no limit is set, `limits.cpu` / `limits.memory` report the **node's allocatable** value.
- A `downwardAPI` volume refreshes when labels/annotations change (not with `subPath`); env vars never change.

### Composition and precedence

- **`$(VAR)` expansion** works in `env[].value`, `command` and `args`, and is done by Kubernetes, not the shell. In `env`, only variables defined **earlier** in the list (or from `envFrom`) can be referenced; an unresolved reference stays as the literal text `$(VAR)`. `$$(VAR)` escapes to a literal `$(VAR)`. In `command`/`args` all of the container's variables are available.
- **Precedence** (highest first): `env` entries > `envFrom` sources (a later source wins over an earlier one) > Service-link variables > the image's `ENV`.
- Duplicate names inside `env`: the **last** one wins (newer API servers also return a warning).
- Every container also gets Service variables: `KUBERNETES_SERVICE_HOST` / `KUBERNETES_SERVICE_PORT` always, plus `<SVC>_SERVICE_HOST` / `<SVC>_SERVICE_PORT` for each Service in the Pod's namespace that existed when the Pod started. `enableServiceLinks: false` (Pod spec) drops the per-Service ones.

---

## Key fields / syntax

Files: [yaml/pod-downward-api-env.yaml](yaml/pod-downward-api-env.yaml), [yaml/pod-downward-api-volume.yaml](yaml/pod-downward-api-volume.yaml), [yaml/pod-env-dependent-vars.yaml](yaml/pod-env-dependent-vars.yaml), [yaml/pod-projected-volume.yaml](yaml/pod-projected-volume.yaml).

```yaml
env:
- name: POD_NAME
  valueFrom:
    fieldRef:
      fieldPath: metadata.name
- name: POD_IP
  valueFrom:
    fieldRef:
      fieldPath: status.podIP
- name: APP_LABEL
  valueFrom:
    fieldRef:
      fieldPath: metadata.labels['app']
- name: MEM_LIMIT_MIB
  valueFrom:
    resourceFieldRef:
      containerName: app          # optional for env (defaults to this container)
      resource: limits.memory
      divisor: 1Mi
- name: LOG_FILE
  value: "/var/log/$(POD_NAME).log"   # composes an earlier variable
```

```yaml
volumes:
- name: podinfo
  downwardAPI:
    items:
    - path: labels
      fieldRef:
        fieldPath: metadata.labels    # whole map: volume only
    - path: cpu_limit_millicores
      resourceFieldRef:
        containerName: app            # required in volumes
        resource: limits.cpu
        divisor: 1m
```

```yaml
command: ["/app/server"]
args: ["--listen=$(POD_IP):8080", "--name=$(POD_NAME)"]   # Kubernetes expands these, no shell needed
```

---

## Imperative commands

```bash
# Set / change env on workloads (triggers a rollout for Deployments)
kubectl set env deploy/web MODE=prod LOG_LEVEL=info
kubectl set env deploy/web -c nginx MODE=prod                     # one container only
kubectl set env deploy/web LOG_LEVEL-                              # remove a variable (trailing dash)
kubectl set env deploy/web --from=configmap/app-config            # one configMapKeyRef per key
kubectl set env deploy/web --from=secret/db-credentials --prefix=DB_ --keys=username,password
kubectl set env deploy/web --list                                  # show env (as KEY=value lines)
kubectl set env deploy/web --list --resolve                        # also resolve ConfigMap/Secret references
kubectl set env pods --all --list                                  # every Pod in the namespace
kubectl set env deploy/web MODE=staging --dry-run=client -o yaml   # preview the change
kubectl set env deploy/web --overwrite=false MODE=x                # refuse to overwrite an existing value

# Create with env directly
kubectl run tmp --image=busybox:1.36 --env=MODE=dev --env=REGION=eu --rm -it --restart=Never -- env
kubectl create deployment web --image=nginx:1.27 --dry-run=client -o yaml > web.yaml   # no --env flag; add env in YAML or use set env

# Generate a Pod, then add fieldRef/resourceFieldRef entries in vi
kubectl run info --image=busybox:1.36 --dry-run=client -o yaml -- sh -c 'env; sleep 3600' > info.yaml

# Inspect inside the container
kubectl exec web -- env | sort
kubectl exec web -- printenv POD_IP NODE_NAME
kubectl exec web -- sh -c 'echo $POD_NAME'                         # single quotes: expanded inside the container
kubectl exec web -- cat /etc/podinfo/labels
kubectl get pod web -o jsonpath='{.spec.containers[0].env}{"\n"}'  # what the spec declares
```

---

## Exam traps & tips

> **Exam tip:** `status.podIP`, `spec.nodeName` and `spec.serviceAccountName` work only as **env vars**; the whole `metadata.labels`/`metadata.annotations` maps work only in a **downwardAPI volume**.

> **Exam tip:** `resourceFieldRef` inside a `downwardAPI` volume needs `containerName`; for env it is optional.

> **Exam tip:** `kubectl exec web -- echo $POD_NAME` expands `$POD_NAME` in **your** shell (usually empty). Use `kubectl exec web -- printenv POD_NAME` or `sh -c '...'` with single quotes.

> **Exam tip:** `kubectl set env` is meant for objects with a Pod template (Deployment, StatefulSet, DaemonSet, ReplicaSet, CronJob). A running Pod's env is immutable - recreate the Pod.

- Quote numeric and boolean env values in YAML: `value: "3"`, `value: "true"`.
- `$(VAR)` referring to a variable defined later in `env` is **not** expanded.
- CPU via `resourceFieldRef` without a divisor gives whole cores rounded up; use `divisor: 1m` for millicores.
- Without limits, `limits.memory` reports node allocatable memory - surprising if the app sizes its heap from it.

---

## Architect notes

- Give applications their **identity** (Pod name, namespace, node, labels) through the Downward API for log/trace attributes - no API calls, no RBAC needed.
- Size runtimes from limits: pass `limits.memory` (divisor `1Mi`) to heap settings, or better use container-aware runtime flags.
- Env vars for non-sensitive settings, **files for secrets** (env leaks via process listings, crash dumps and child processes).
- Set `enableServiceLinks: false` in namespaces with many Services: hundreds of injected variables slow start-up and can collide with app variables.
- Fail fast: apps should validate required variables at start-up and exit with a clear error rather than run misconfigured.
- Keep env var names to portable C identifiers (`[A-Z_][A-Z0-9_]*`) even though Kubernetes now accepts almost any printable ASCII (GA v1.34).
- Prefer a mounted config file over dozens of env vars for complex configuration - easier to diff, validate and reload.

---

## Docs to bookmark

- https://kubernetes.io/docs/concepts/workloads/pods/downward-api/ (the field availability table)
- https://kubernetes.io/docs/tasks/inject-data-application/environment-variable-expose-pod-information/
- https://kubernetes.io/docs/tasks/inject-data-application/downward-api-volume-expose-pod-information/
- https://kubernetes.io/docs/tasks/inject-data-application/define-environment-variable-container/
- https://kubernetes.io/docs/tasks/inject-data-application/define-interdependent-environment-variables/
- https://kubernetes.io/docs/reference/kubectl/generated/kubectl_set/kubectl_set_env/

---

## Quick self-check

1. Which Downward API fields can you expose as env vars but not as files?
2. How do you expose all of a Pod's labels to the container, and do they update when labels change?
3. A container has `limits.cpu: 250m`. What does `resourceFieldRef: {resource: limits.cpu}` return without and with `divisor: 1m`?
4. In `env`, `A` is defined as `"$(B)-x"` and `B` is defined after `A`. What is the value of `A`?
5. The same variable is set by `envFrom` (ConfigMap) and by `env`. Which value does the container see?

<details><summary>Answers</summary>

1. `spec.nodeName`, `spec.serviceAccountName`, `status.podIP(s)`, `status.hostIP(s)`.
2. A `downwardAPI` volume item with `fieldRef.fieldPath: metadata.labels`; yes, the file is refreshed (env vars would not be).
3. `1` (rounded up to whole cores) and `250`.
4. The literal string `$(B)-x` - `B` was not yet defined at that point.
5. The `env` value; explicit `env` entries override `envFrom`.

</details>
