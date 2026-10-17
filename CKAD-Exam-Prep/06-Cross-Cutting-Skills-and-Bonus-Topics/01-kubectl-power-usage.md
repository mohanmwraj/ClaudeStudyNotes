# kubectl Power Usage

**Why it matters / what the exam expects:** every CKAD task is solved with `kubectl` in a live cluster under heavy time pressure (format and timing: [exam overview](../00-Exam-Overview-and-Setup/README.md)). The exam rewards candidates who **generate** YAML instead of typing it, look fields up with `kubectl explain` instead of searching the docs, and know which update command (`apply`, `replace --force`, `edit`, `patch`, `set`) works for which change. None of this is a separate competency, but it decides whether you finish.

> Conventions used in this chapter: `alias k=kubectl` (preconfigured on exam hosts), `export do="--dry-run=client -o yaml"`, `export now="--force --grace-period=0"` (re-export them on each task host - setup: [08-linux-vim-bash-tmux-for-the-exam.md](08-linux-vim-bash-tmux-for-the-exam.md)). Version notes refer to Kubernetes/kubectl **v1.37**, the version the exam currently runs; everything here also applies from v1.33 unless stated. Images are pinned; never use `latest` unless a task says so.

---

## Core concepts

### Three ways to manage objects

| Technique | Example | Strength | Weakness |
|---|---|---|---|
| Imperative command | `k create deploy web --image=nginx:1.27 --replicas=3` | fastest to type | only the fields that have flags |
| Imperative object config | `k create -f web.yaml` · `k replace -f web.yaml` | full control over every field | `create` fails if it exists; `replace` needs the complete object |
| Declarative object config | `k apply -f web.yaml` · `k apply -k dir/` | idempotent, merges changes | stores a `last-applied-configuration` annotation; mixing with `edit` can surprise you |

**Exam workflow:** generate with an imperative command + `$do` → fix in vim → `k apply -f` → verify with `get`/`describe`.

### Which command changes what?

| Command | Object missing | Object exists | Typical exam use |
|---|---|---|---|
| `k create -f x.yaml` | creates | **error** `AlreadyExists` | first creation |
| `k apply -f x.yaml` | creates | 3-way merge patch (file vs live vs last-applied) | create **or** update from a file |
| `k replace -f x.yaml` | **error** `NotFound` | full PUT; fails on immutable fields | rare |
| `k replace --force -f x.yaml` | creates | **deletes, then re-creates** (new UID, pods restart) | change immutable Pod fields |
| `k edit <kind>/<name>` | – | opens live YAML, PUT on save | quick changes to Deployments, Services, ... |
| `k patch <kind>/<name> -p ...` | – | partial update (strategic / merge / json) | precise one-field changes, scripts |
| `k set image\|env\|resources\|serviceaccount\|selector\|subject` | – | targeted change (pod templates trigger a rollout) | fastest for those fields |
| `k scale`, `k label`, `k annotate`, `k taint` | – | one aspect only | as named |

### Immutable fields you will hit

| Object | Immutable after creation | Fix |
|---|---|---|
| Pod | almost all of `spec` - allowed: `containers[*].image`, `initContainers[*].image`, `activeDeadlineSeconds`, `tolerations` (additions only), `terminationGracePeriodSeconds` (narrow case); resources only via the `resize` subresource | `k replace --force -f` (or delete + create) |
| Deployment / ReplicaSet / StatefulSet / DaemonSet | `spec.selector` | delete and re-create the workload |
| Job | `spec.template`, `spec.selector`, `spec.completions` (mostly) | delete and re-create the Job |
| Service | `spec.clusterIP` (once set) | delete and re-create (a new ClusterIP is allocated) |
| PVC | most of `spec` (storage size may only grow, if the StorageClass allows expansion) | new PVC |

---

## Key fields / syntax

### `kubectl explain` - the offline docs

```bash
k explain pod.spec.containers.livenessProbe          # one level: field names, types, descriptions
k explain deploy.spec.strategy.rollingUpdate         # short names work (deploy, po, svc, netpol, ...)
k explain pod.spec --recursive | less                # the whole tree: names + types only
k explain pod.spec --recursive | grep -n -i -A6 '^ *tolerations'   # find where a field lives
k explain netpol.spec.ingress.from                   # how do I nest namespaceSelector/podSelector?
k explain cronjob.spec.jobTemplate.spec.template.spec.restartPolicy
k explain hpa.spec.behavior --api-version=autoscaling/v2   # pin an API version explicitly
k explain <crd-kind>.spec                            # works for CRDs that publish an OpenAPI schema
```

| Rule | Example |
|---|---|
| Path = `TYPE.field.field` using JSON field names (camelCase) | `pod.spec.securityContext.runAsNonRoot` |
| List fields are walked **without** an index | `pod.spec.containers.ports` (not `containers[0]`) |
| Type hints | `<string>`, `<integer>`, `<boolean>`, `<Object>`, `<[]Object>` (list of maps), `<map[string]string>` (labels-like) |
| `-required-` | must be set (e.g. `containers.name`) |
| `--recursive` | names and types of all nested fields; kubectl v1.37 (the exam version) adds `--max-depth=N` to limit the depth (`k explain pod.spec --recursive --max-depth=2`); v1.36 and older do not have that flag |

> **Exam tip:** `k explain` is faster than the docs for "what is the exact field name / where does it go?" (e.g. `allowPrivilegeEscalation` lives in `containers.securityContext`, not in `pod.spec.securityContext`).

### `kubectl api-resources` - names, short names, scope, API group

```bash
k api-resources                          # NAME  SHORTNAMES  APIVERSION  NAMESPACED  KIND
k api-resources --namespaced=false       # cluster-scoped kinds only
k api-resources --api-group=apps         # one group
k api-resources -o wide                  # + VERBS and CATEGORIES columns
k api-resources --verbs=list -o name     # every listable resource, "plural.group" names
k api-resources | grep -i ingress        # quick lookup of group/version/short name
k api-versions                           # every group/version the server serves
```

The ~30 kinds you will meet (verify on your cluster with `k api-resources`):

| Kind | Resource (plural) | Short name | apiVersion | Namespaced |
|---|---|---|---|---|
| Pod | pods | `po` | v1 | yes |
| Service | services | `svc` | v1 | yes |
| Deployment | deployments | `deploy` | apps/v1 | yes |
| ReplicaSet | replicasets | `rs` | apps/v1 | yes |
| DaemonSet | daemonsets | `ds` | apps/v1 | yes |
| StatefulSet | statefulsets | `sts` | apps/v1 | yes |
| Job | jobs | – | batch/v1 | yes |
| CronJob | cronjobs | `cj` | batch/v1 | yes |
| ConfigMap | configmaps | `cm` | v1 | yes |
| Secret | secrets | – | v1 | yes |
| ServiceAccount | serviceaccounts | `sa` | v1 | yes |
| Namespace | namespaces | `ns` | v1 | **no** |
| Node | nodes | `no` | v1 | **no** |
| PersistentVolume | persistentvolumes | `pv` | v1 | **no** |
| PersistentVolumeClaim | persistentvolumeclaims | `pvc` | v1 | yes |
| StorageClass | storageclasses | `sc` | storage.k8s.io/v1 | **no** |
| Ingress | ingresses | `ing` | networking.k8s.io/v1 | yes |
| IngressClass | ingressclasses | – | networking.k8s.io/v1 | **no** |
| NetworkPolicy | networkpolicies | `netpol` | networking.k8s.io/v1 | yes |
| HorizontalPodAutoscaler | horizontalpodautoscalers | `hpa` | autoscaling/v2 | yes |
| PodDisruptionBudget | poddisruptionbudgets | `pdb` | policy/v1 | yes |
| PriorityClass | priorityclasses | `pc` | scheduling.k8s.io/v1 | **no** |
| ResourceQuota | resourcequotas | `quota` | v1 | yes |
| LimitRange | limitranges | `limits` | v1 | yes |
| Endpoints (deprecated since v1.33) | endpoints | `ep` | v1 | yes |
| EndpointSlice | endpointslices | – | discovery.k8s.io/v1 | yes |
| Event | events | `ev` | v1 (also events.k8s.io/v1) | yes |
| Role / RoleBinding | roles / rolebindings | – | rbac.authorization.k8s.io/v1 | yes |
| ClusterRole / ClusterRoleBinding | clusterroles / clusterrolebindings | – | rbac.authorization.k8s.io/v1 | **no** |
| CustomResourceDefinition | customresourcedefinitions | `crd`, `crds` | apiextensions.k8s.io/v1 | **no** |
| ReplicationController (legacy) | replicationcontrollers | `rc` | v1 | yes |
| CertificateSigningRequest | certificatesigningrequests | `csr` | certificates.k8s.io/v1 | **no** |

Singular, plural, short and fully-qualified names all work: `k get pod`, `k get pods`, `k get po`, `k get deployments.apps`, `k get deployments.v1.apps`.

### Generating YAML with `--dry-run=client -o yaml`

| Kind | Generator (append `> file.yaml`) |
|---|---|
| Pod | `k run web --image=nginx:1.27 --port=80 --labels=app=web,tier=fe --env=MODE=prod $do` |
| Pod with command | `k run bb --image=busybox:1.36 --restart=Never $do --command -- sh -c 'sleep 3600'` |
| Pod with args only | `k run bb --image=busybox:1.36 $do -- sleep 3600` (keeps the image ENTRYPOINT) |
| Deployment | `k create deploy web --image=nginx:1.27 --replicas=3 --port=80 $do` |
| Service for a workload | `k expose deploy web --port=80 --target-port=8080 --name=web-svc [--type=NodePort] $do` |
| Service standalone | `k create svc clusterip web --tcp=80:8080 $do` (selector becomes `app=web`) |
| NodePort with fixed port | `k create svc nodeport web --tcp=80:8080 --node-port=30080 $do` |
| Job | `k create job hello --image=busybox:1.36 $do -- sh -c 'echo hi'` |
| Job from a CronJob | `k create job manual-1 --from=cronjob/backup` (no dry-run needed) |
| CronJob | `k create cj backup --image=busybox:1.36 --schedule='*/5 * * * *' $do -- sh -c 'date'` |
| ConfigMap | `k create cm cfg --from-literal=MODE=prod --from-file=app.properties $do` |
| Secret | `k create secret generic db --from-literal=password='S3cr3t!' $do` (also `tls`, `docker-registry`) |
| ServiceAccount | `k create sa app-sa $do` |
| Namespace | `k create ns dev $do` |
| Role / ClusterRole | `k create role pod-reader --verb=get,list,watch --resource=pods $do` |
| RoleBinding / ClusterRoleBinding | `k create rolebinding rb --role=pod-reader --serviceaccount=dev:app-sa $do` |
| ResourceQuota | `k create quota q --hard=pods=10,requests.cpu=2,requests.memory=2Gi $do` |
| Ingress | `k create ingress web --class=nginx --rule='web.example.com/*=web-svc:80' $do` |
| PodDisruptionBudget | `k create pdb web-pdb --selector=app=web --min-available=2 $do` |
| PriorityClass | `k create pc high --value=100000 --description='critical' $do` |
| HPA | `k autoscale deploy web --min=2 --max=5 --cpu=70% $do` (kubectl <= v1.33: `--cpu-percent=70`) |
| ServiceAccount token | `k create token app-sa --duration=1h` (prints a token, not YAML) |

**Kinds without a generator** - copy from the docs page or convert a generated Deployment:

| Kind | Fastest route | Docs page to copy from (search the page title on kubernetes.io) |
|---|---|---|
| DaemonSet | `k create deploy ... $do`, then change `kind: DaemonSet`, delete `replicas`, `strategy`, `status` | "DaemonSet" (fluentd-elasticsearch example) |
| StatefulSet | convert a Deployment: `kind: StatefulSet`, add `serviceName:`, delete `strategy`/`status`, add `volumeClaimTemplates` if needed | "StatefulSets" (nginx `web` example with headless Service) |
| PersistentVolume / PVC | copy | "Configure a Pod to Use a PersistentVolume for Storage" |
| NetworkPolicy | copy and trim | "Network Policies" (`test-network-policy`) |
| LimitRange | copy | "Configure Default Memory Requests and Limits for a Namespace" |
| StorageClass | copy | "Storage Classes" |
| HPA with `behavior` | `k autoscale ... $do`, then add `behavior:` | "Horizontal Pod Autoscaling" |
| Probes, volumes, securityContext, affinity, tolerations | generate the Pod/Deployment, then paste the block | the matching task page; `k explain` for field names |

> **Exam tip:** `k <command> -h` prints ready-to-copy examples (`k create ingress -h`, `k create cj -h`, `k expose -h`). It is often faster than the docs.

### Patch types

```bash
# 1) Strategic merge patch (default for built-in kinds): lists such as containers merge by their key ("name")
k patch deploy web -p '{"spec":{"template":{"spec":{"containers":[{"name":"nginx","image":"nginx:1.27-alpine"}]}}}}'

# 2) JSON merge patch (RFC 7386): maps merge, LISTS ARE REPLACED WHOLESALE, null deletes a key
k patch deploy web --type=merge -p '{"spec":{"replicas":4}}'
k patch deploy web --type=merge -p '{"metadata":{"annotations":{"owner":null}}}'      # remove an annotation

# 3) JSON patch (RFC 6902): explicit operations on paths, list indexes allowed
k patch svc web --type=json -p '[{"op":"replace","path":"/spec/ports/0/nodePort","value":30080}]'
k patch deploy web --type=json -p '[{"op":"add","path":"/spec/template/spec/containers/0/env","value":[{"name":"MODE","value":"prod"}]}]'
k patch deploy web --type=json -p '[{"op":"add","path":"/spec/template/spec/containers/0/env/-","value":{"name":"DEBUG","value":"1"}}]'  # append; env must already exist
k patch deploy web --type=json -p '[{"op":"remove","path":"/spec/template/spec/containers/0/livenessProbe"}]'
#    a "/" inside a key is written ~1 :  /metadata/labels/app.kubernetes.io~1name

# Bigger patches from a file (YAML or JSON)
k patch deploy web --patch-file=patch.yaml
```

| Type | Lists | Delete a field | Works on CRDs | Use when |
|---|---|---|---|---|
| strategic (default) | merged by merge key (`name`, `port`, `containerPort`, ...) | `null` or `$patch: delete` | **no** - the request is rejected for custom resources; use `--type=merge` or `json` | everyday changes to built-in kinds |
| `--type=merge` | replaced entirely | `null` | yes | simple scalar/map changes, CRDs |
| `--type=json` | index-addressed (`/0`, `/-` = append) | `{"op":"remove"}` | yes | exact surgery, nodePort, removing a probe |

> Container name gotcha: `k create deploy web --image=nginx:1.27` names the container **`nginx`** (from the image), while `k run web ...` names it **`web`** (from the Pod). Strategic patches and `k set image deploy/web nginx=...` need the right name: `k get deploy web -o jsonpath='{.spec.template.spec.containers[*].name}'`.

### Server-side apply (brief)

```bash
k apply --server-side -f web.yaml                     # API server merges; field ownership tracked in managedFields
k apply --server-side --field-manager=ci -f web.yaml  # name the owner
k apply --server-side --force-conflicts -f web.yaml   # take over fields owned by another manager
k get deploy web -o yaml --show-managed-fields        # who owns which field
```

GA since v1.22. Conflicts look like `Apply failed with 1 conflict: conflict with "kubectl-client-side-apply" ...: .spec.replicas`. No `last-applied-configuration` annotation is needed (so the 256 KiB annotation limit does not bite on huge objects such as big CRDs). Exam: client-side `k apply` is enough; know the flag exists.

### The `kubectl edit` failure flow (immutable fields)

```bash
k edit pod web                      # change e.g. env, command, a volumeMount or resources -> save (:wq)
```

```text
# kubectl re-opens the editor with the reason at the top, e.g.:
# pods "web" was not valid:
# * spec: Forbidden: pod updates may not change fields other than `spec.containers[*].image`, ...
# Just quit again (:q! or :wq) - kubectl then prints:
error: pods "web" is invalid
A copy of your changes has been stored to "/tmp/kubectl-edit-1234567890.yaml"
error: Edit cancelled, no valid changes were saved.
```

```bash
k replace --force -f /tmp/kubectl-edit-1234567890.yaml     # delete + re-create with your changes
k replace $now -f /tmp/kubectl-edit-1234567890.yaml        # same, without waiting for graceful shutdown
k get pod web -o wide                                      # new pod (new UID, restart count 0)
```

The safe manual equivalent: `k get pod web -o yaml > web.yaml` → `vim web.yaml` → `k replace --force -f web.yaml`. Keep `web.yaml` as your backup.

---

## Imperative commands

### Generate -> edit -> apply

```bash
k create deploy web --image=nginx:1.27 --replicas=3 $do > web.yaml   # generate
vim web.yaml                                                          # add probes/resources/...
k apply -f web.yaml                                                   # create or update
k apply -f web.yaml --dry-run=server                                  # full server validation + admission, nothing persisted
k get deploy web -o yaml > web-live.yaml                              # export the live object to modify later
```

`--dry-run=client` only builds the object locally (nothing is sent for creation, so no server-side field validation, admission or quota checks); `--dry-run=server` runs the complete request path (schema/field validation, admission webhooks, quota) without saving - ideal to check a tricky manifest before the real apply.

### `kubectl run` details

```bash
k run tmp --rm -it --image=busybox:1.36 --restart=Never -- wget -qO- http://web-svc   # throw-away test pod
k run web --image=nginx:1.27 --port=80 --expose            # Pod + ClusterIP Service "web" in one go
k run bb --image=busybox:1.36 --restart=OnFailure $do -- sh -c 'exit 1'
k run sel --image=nginx:1.27 $do --overrides='{"apiVersion":"v1","spec":{"nodeSelector":{"disktype":"ssd"}}}'   # fields without flags
```

`k run` creates **only Pods**. Put `$do` (and every other kubectl flag) **before** `--`: everything after `--` becomes the container command/args.

### Fast deletion

```bash
k delete pod web $now                    # = --force --grace-period=0: returns immediately ("Immediate deletion does not wait ...")
k delete pod web --now                   # grace period 1 s (signals immediate shutdown)
k delete pod web --wait=false            # do not block the terminal while it terminates
k delete pods -l app=web                 # by label
k delete deploy,svc -l app=web           # several kinds at once
k delete pods --all -n scratch           # everything of one kind in a namespace
k delete -f web.yaml                     # whatever the file defines
k delete ns scratch --wait=false         # namespaces take a while (finalizers)
```

> **Exam tip:** force-deleting is fine for exam pods; in production never force-delete StatefulSet pods (the old pod may still be running on a partitioned node).

### `kubectl diff`

```bash
k diff -f web.yaml                       # what would apply change? (server-side dry run, unified diff)
echo $?                                  # 0 = no differences, 1 = differences, >1 = error
KUBECTL_EXTERNAL_DIFF="diff -u --color" k diff -f web.yaml
```

### `kubectl wait`

```bash
k wait --for=condition=Ready pod/web --timeout=60s
k wait --for=condition=Available deploy/web --timeout=120s
k wait --for=condition=complete job/pi --timeout=120s
k wait --for=jsonpath='{.status.phase}'=Running pod/web
k wait --for=delete pod/web --timeout=60s
k wait --for=create secret/db --timeout=30s          # wait until it exists (present in v1.37; older kubectl may lack it: k wait -h)
k wait --for=condition=Ready pods -l app=web --timeout=90s
k rollout status deploy/web --timeout=120s           # the usual way for Deployments
```

### Labels and annotations

```bash
k label pod web env=prod                         # add
k label pod web env=dev --overwrite              # change (without --overwrite: "'env' already has a value (prod), and --overwrite is false")
k label pod web env-                             # remove (trailing minus, no --overwrite needed)
k label pods -l app=web tier=frontend            # bulk, by selector
k label pods --all audit=true                    # every pod in the namespace
k label node node01 disktype=ssd
k label ns dev team=payments
k label pod web --list                           # print the labels
k annotate deploy web kubernetes.io/change-cause="image nginx:1.27-alpine"   # shown by rollout history
k annotate pod web owner='team-a' --overwrite
k annotate pod web owner-                        # remove
```

### Listing flags you will use constantly

```bash
k get pods -A                            # all namespaces (adds a NAMESPACE column)
k get pods -o wide                       # + IP, NODE, NOMINATED NODE, READINESS GATES
k get pods --show-labels                 # + LABELS column
k get pods -L app,env                    # one column per label key
k get pods -l 'env in (dev,qa)'          # label selector (see 03)
k get pods --field-selector status.phase!=Running   # field selector (see 03)
k get pods -w                            # watch (Ctrl-C to stop); --watch-only skips the initial list
k get deploy,rs,pods,svc                 # several kinds in one call
k get pods --sort-by=.metadata.creationTimestamp    # (see 02)
```

### `kubectl get all` caveats

- `all` is a **category**, not everything: pods, services, deployments, replicasets, statefulsets, daemonsets, jobs, cronjobs, horizontalpodautoscalers, replicationcontrollers.
- **Not included:** ConfigMaps, Secrets, PVCs, PVs, Ingresses, NetworkPolicies, ServiceAccounts, Roles/RoleBindings, PDBs, ResourceQuotas, LimitRanges, EndpointSlices, Events.
- It lists the current namespace only (add `-n` or `-A`). `k delete all -l app=web` therefore leaves ConfigMaps/Secrets/PVCs behind.
- Truly everything in a namespace (note `kubectl`, not the alias, inside `xargs`):

```bash
k api-resources --verbs=list --namespaced -o name | xargs -n 1 kubectl get --show-kind --ignore-not-found -n dev
```

### `kubectl cp`

```bash
k cp dev/web:/etc/nginx/nginx.conf ./nginx.conf                  # pod -> local   (<ns>/<pod>:<path>)
k cp ./index.html dev/web:/usr/share/nginx/html/index.html -c nginx   # local -> pod, choose the container
k exec -n dev web -- cat /etc/nginx/nginx.conf > nginx.conf      # alternative when the image has no tar
```

`kubectl cp` needs `tar` inside the container (distroless/scratch images fail). A warning such as `tar: Removing leading '/' from member names` is harmless.

### Contexts and namespaces

```bash
ssh <task-host>                                  # if the task names a host: connect first; `exit` when done (no nested ssh)
k config get-contexts                            # * marks the current context
k config use-context k8s-c2                      # if the task names a context: run it FIRST (copy it from the task)
k config current-context
k config set-context --current --namespace=dev   # default namespace for the current context
k config view --minify -o jsonpath='{..namespace}'; echo   # which namespace am I in? (empty = default)
k get pods -n dev --context=k8s-c1               # one-off command against another context
```

### kubectl user preferences: kuberc (brief)

`~/.kube/kuberc` (or `--kuberc <file>` / `KUBERC=<file>`) holds **aliases** and **default flag values** separately from kubeconfig. Feature state: alpha in v1.33 (opt-in with `KUBECTL_KUBERC=true`, `v1alpha1` with slightly different field names), **beta and on by default since v1.34**. Disable with `KUBECTL_KUBERC=false` or `KUBERC=off`. kubectl v1.37 also ships `kubectl kuberc view|set` (check `k kuberc -h`). Exam relevance: none. Bash aliases are enough; do not spend exam time on it.

```bash
mkdir -p ~/.kube
cat > ~/.kube/kuberc <<'EOF'
apiVersion: kubectl.config.k8s.io/v1beta1
kind: Preference
defaults:                  # default flag values per command
- command: delete
  options:
  - name: interactive      # ask before deleting
    default: "true"
aliases:                   # new sub-commands
- name: getw
  command: get
  options:
  - name: output
    default: wide
EOF
kubectl getw pods          # = kubectl get pods -o wide
KUBERC=off kubectl delete pod web   # bypass kuberc for one command
```

---

## Exam traps & tips

> **Exam tip:** every task names where to work - a host to `ssh` into and/or a context. Run that line from the task header **before anything else**, every task, and `exit` back to the base machine when the task is done (nested ssh is not supported). Working on the wrong host or cluster scores zero for that task. Details: [00-Exam-Overview-and-Setup](../00-Exam-Overview-and-Setup/README.md).

> **Exam tip:** `$do` must come **before** `--` in `k run`, `k create job` and `k create cj`. After `--` everything is passed to the container.

> **Exam tip:** "Update the pod" when the field is immutable means `k replace --force -f` (or delete + create). If the task says "do not delete", use a field that can be changed in place (image) or change the owning Deployment instead.

> **Exam tip:** `k apply` on an object that was made with `k create` prints `Warning: resource ... is missing the kubectl.kubernetes.io/last-applied-configuration annotation` - harmless, it patches the annotation in.

> **Exam tip:** `k replace --force` really deletes the object: a re-created **Service** gets a new UID (and a new ClusterIP unless the file still contains `spec.clusterIP`), a re-created Pod starts with restart count 0 - fine in the exam, surprising in production.

> **Exam tip:** Prefer `-n <ns>` on every command over relying on the context default; it also makes your shell history reusable for the next task.

- `k get all` does not show ConfigMaps, Secrets, PVCs, Ingresses or NetworkPolicies - list them explicitly.
- `k label` fails on an existing key without `--overwrite`; removing uses `key-` and never needs `--overwrite`.
- JSON merge patches replace whole lists - patching `containers` with `--type=merge` drops every other container field you did not repeat.
- `k edit` uses `KUBE_EDITOR`, then `EDITOR`, then `vi`; set `export KUBE_EDITOR=vim` if the default is unfamiliar.
- `kubectl cp` fails without `tar` in the image; use `k exec ... -- cat` instead.

---

## Architect notes

- In production, changes flow through Git (Argo CD / Flux) or CI pipelines; imperative `kubectl edit/patch` is for break-glass only and creates drift that the next sync reverts.
- Standardise on **server-side apply** for controllers and GitOps tools: field managers make shared ownership (HPA owns `replicas`, Git owns the rest) explicit instead of silently fighting.
- Run `kubectl diff` (or `--dry-run=server`) in CI to preview changes and to exercise admission webhooks and policies before merge.
- Keep kubectl within one minor version of the API server (official version-skew policy); pin the version in CI images.
- In scripts always pass `--context` and `-n` explicitly; never depend on a human's current-context. Separate kubeconfigs per environment reduce "prod by accident" incidents.
- Remove `spec.replicas` from manifests of HPA-managed workloads; otherwise every apply resets the replica count.
- Large objects (CRDs, big ConfigMaps) can exceed the 256 KiB annotation limit with client-side apply - server-side apply avoids the `last-applied-configuration` annotation.
- kuberc gives teams shared safe defaults (for example `delete --interactive`) and, beta in v1.35, an allowlist for credential plugins.

---

## Docs to bookmark

- kubectl Quick Reference (cheat sheet): https://kubernetes.io/docs/reference/kubectl/quick-reference/
- kubectl reference overview (output options, operations): https://kubernetes.io/docs/reference/kubectl/
- kubectl usage conventions (generators, dry-run): https://kubernetes.io/docs/reference/kubectl/conventions/
- Object management techniques: https://kubernetes.io/docs/concepts/overview/working-with-objects/object-management/
- Update API objects in place using kubectl patch: https://kubernetes.io/docs/tasks/manage-kubernetes-objects/update-api-object-kubectl-patch/
- Server-Side Apply: https://kubernetes.io/docs/reference/using-api/server-side-apply/
- kubectl wait: https://kubernetes.io/docs/reference/kubectl/generated/kubectl_wait/
- Kubectl user preferences (kuberc): https://kubernetes.io/docs/reference/kubectl/kuberc/

---

## Quick self-check

1. You edited a running Pod's `env` with `k edit` and kubectl refused. What exactly do you do next?
2. Which kinds have no `kubectl create` generator, and what is the fastest route for a DaemonSet?
3. What is the difference between `--type=merge` and the default strategic merge patch when you patch `containers`?
4. Write the command that sets the default namespace of the current context to `prod`.
5. Why might `k delete all -l app=shop` leave objects behind?
6. Where must `$do` go in `k run bb --image=busybox:1.36 ... -- sleep 3600`?

<details><summary>Answers</summary>

1. Quit the re-opened editor; kubectl prints `A copy of your changes has been stored to "/tmp/kubectl-edit-XXXX.yaml"`. Run `k replace --force -f /tmp/kubectl-edit-XXXX.yaml` (optionally with `--grace-period=0`).
2. DaemonSet, StatefulSet, PV, PVC, NetworkPolicy, LimitRange, StorageClass (and most CRDs). DaemonSet: `k create deploy x --image=... $do > ds.yaml`, change `kind: DaemonSet`, delete `replicas`, `strategy` and `status`.
3. Strategic merge merges list items by their merge key (`name`), so you can send only the changed container; JSON merge replaces the entire list with exactly what you send.
4. `k config set-context --current --namespace=prod`
5. `all` only covers pods, services, deployments, replicasets, statefulsets, daemonsets, jobs, cronjobs, HPAs and replication controllers - ConfigMaps, Secrets, PVCs, Ingresses, NetworkPolicies etc. survive.
6. Before the `--`: `k run bb --image=busybox:1.36 $do -- sleep 3600`.

</details>
