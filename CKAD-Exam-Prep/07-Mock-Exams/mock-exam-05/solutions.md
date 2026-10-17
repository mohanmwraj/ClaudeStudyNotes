# CKAD Mock Exam 05 — Solutions (Advanced, multi-step)

Grade yourself honestly: give a question's points only when its **Verify** commands show the expected result. Partial credit follows each question's points table. These are reference solutions; any approach that reaches the same end state without breaking a "do not change" rule scores the same.

## Domain weights

| Domain | Questions | Weight |
|---|---|---|
| Application Design and Build | 2, 6, 11, 19 | 20% |
| Application Deployment | 1, 7, 12, 17 | 20% |
| Application Observability and Maintenance | 5, 10, 15 | 15% |
| Application Environment, Configuration and Security | 3, 8, 13, 16, 18 | 26% |
| Services and Networking | 4, 9, 14 | 19% |
| **Total** | **19** | **100%** |

Shortcuts used below (put them in `~/.bashrc` on exam day):

```bash
alias k=kubectl
export do="--dry-run=client -o yaml"     # k create deploy x --image=y $do > x.yaml
```

Commands are written with the full `kubectl` so that you can paste them.

---

## Question 1 — Promote a canary (5%)

**Approach:** Service `pricing` selects only `app=pricing`, so the traffic split follows the Pod count. Promotion therefore changes replica counts only: scale the canary up, wait until it is Ready, then scale stable to 0. Leave the Service alone.

```bash
kubectl -n m05-canary get deploy,svc,pods --show-labels
kubectl -n m05-canary get svc pricing -o jsonpath='{.spec.selector}{"\n"}'     # {"app":"pricing"}

kubectl -n m05-canary scale deployment pricing-canary --replicas=4
kubectl -n m05-canary rollout status deployment pricing-canary                 # 4 ready before stable shrinks
kubectl -n m05-canary scale deployment pricing-stable --replicas=0
kubectl -n m05-canary get pods -l track=stable                                  # repeat until "No resources found"

kubectl -n m05-canary get endpointslices -l kubernetes.io/service-name=pricing \
  -o jsonpath='{range .items[*].endpoints[?(@.conditions.ready==true)]}{.addresses[0]}{"\n"}{end}' \
  > ~/ckad-mocks/exam-05/q01/endpoints.txt
```

**Verify**

```bash
kubectl -n m05-canary get deploy pricing-stable pricing-canary
[ "$(kubectl -n m05-canary get svc pricing -o jsonpath='{.metadata.resourceVersion}')" = \
  "$(cat ~/ckad-mocks/exam-05/.state/q01-svc-rv)" ] && echo "Service untouched"
diff <(sort ~/ckad-mocks/exam-05/q01/endpoints.txt) \
     <(kubectl -n m05-canary get pods -l track=canary -o jsonpath='{range .items[*]}{.status.podIP}{"\n"}{end}' | sort) \
  && echo "endpoints OK"
kubectl -n m05-canary exec deploy/pricing-canary -- sh -c 'for i in 1 2 3 4 5 6 7 8; do wget -qO- http://pricing; done' | sort | uniq -c
```

```text
NAME             READY   UP-TO-DATE   AVAILABLE   AGE
pricing-stable   0/0     0            0           31m
pricing-canary   4/4     4            4           31m
Service untouched
endpoints OK
      8 pricing v2
```

**Common mistakes**
- Changing the Service selector to `track: canary`. That works technically, but it breaks the "Service not modified" rule, and you lose the simple replica-count rollback.
- Deleting `pricing-stable`. Scaled to 0 it costs nothing and gives a one-command rollback (`kubectl scale ... --replicas=3`).
- Scaling stable down first. Capacity drops to one Pod until the canary scales up.
- Using `kubectl get endpoints`. The core Endpoints API is deprecated since v1.33 and prints a warning; the task asked for EndpointSlices.
- Writing terminating (not ready) addresses into the file because you read it too early.

| Item | Points |
|---|---|
| `pricing-canary` 4/4 ready | 2 |
| `pricing-stable` exists with 0 replicas | 1 |
| Service `pricing` unchanged (resourceVersion check) | 1 |
| `endpoints.txt` = the 4 canary Pod IPs | 1 |

---

## Question 2 — Indexed Job with a work list (6%)

**Approach:** Generate the Job skeleton imperatively. `kubectl create job` has no flags for completion mode or parallelism, so add those (and the ConfigMap volume) in the YAML.

```bash
kubectl -n m05-batch create configmap shard-list \
  --from-file=shards.txt=$HOME/ckad-mocks/exam-05/q02/shards.txt

kubectl -n m05-batch create job shard-processor --image=busybox:1.36 --dry-run=client -o yaml \
  -- sh -c 'echo "index=${JOB_COMPLETION_INDEX} shard=$(sed -n "$((JOB_COMPLETION_INDEX + 1))p" /config/shards.txt)"' \
  > q02-job.yaml
vim q02-job.yaml        # rename the container, add the fields below
```

```yaml
# q02-job.yaml — kubectl apply -f q02-job.yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: shard-processor
  namespace: m05-batch
spec:
  completionMode: Indexed       # each Pod gets an index 0..completions-1
  completions: 4
  parallelism: 2
  backoffLimit: 2
  template:
    spec:
      restartPolicy: Never
      containers:
      - name: worker
        image: busybox:1.36
        command:
        - sh
        - -c
        - 'echo "index=${JOB_COMPLETION_INDEX} shard=$(sed -n "$((JOB_COMPLETION_INDEX + 1))p" /config/shards.txt)"'
        volumeMounts:
        - name: shards
          mountPath: /config
          readOnly: true
      volumes:
      - name: shards
        configMap:
          name: shard-list
```

```bash
kubectl apply -f q02-job.yaml
kubectl -n m05-batch wait --for=condition=complete job/shard-processor --timeout=120s
# the Job controller labels each Pod with its index (label available since v1.28; the annotation always exists)
kubectl -n m05-batch logs -l job-name=shard-processor,batch.kubernetes.io/job-completion-index=2 \
  > ~/ckad-mocks/exam-05/q02/index-2.log
# fallback: Pod names are <job>-<index>-<random>
#   kubectl -n m05-batch logs $(kubectl -n m05-batch get pods -l job-name=shard-processor -o name | grep -- '-2-')
```

**Verify**

```bash
kubectl -n m05-batch get job shard-processor -o jsonpath='{.spec.completionMode} {.status.succeeded} {.status.completedIndexes}{"\n"}'
kubectl -n m05-batch logs -l job-name=shard-processor --prefix | sort
cat ~/ckad-mocks/exam-05/q02/index-2.log
```

```text
Indexed 4 0-3
[pod/shard-processor-0-x7k2p/worker] index=0 shard=eu-west
[pod/shard-processor-1-b9q4m/worker] index=1 shard=us-east
[pod/shard-processor-2-h3d8s/worker] index=2 shard=ap-south
[pod/shard-processor-3-n5r1t/worker] index=3 shard=sa-east
index=2 shard=ap-south
```

**Common mistakes**
- Wrapping the command in double quotes in your own shell. Your shell then expands `$(...)` and `${JOB_COMPLETION_INDEX}` on your machine before kubectl sees them. Keep the outer single quotes, or use the YAML above.
- `completionMode: Indexed` without `completions`. That is invalid; Indexed Jobs need a fixed completion count.
- Keeping the generated container name `shard-processor` instead of `worker`.
- Setting `ttlSecondsAfterFinished`, so the Job (and its logs) disappear before grading.
- `--from-env-file` for the ConfigMap. The file has no `KEY=value` lines, so you need `--from-file`.

| Item | Points |
|---|---|
| ConfigMap `shard-list` with key `shards.txt` | 1 |
| Indexed, completions 4, parallelism 2, backoffLimit 2 | 2 |
| Container `worker`, `busybox:1.36`, `restartPolicy: Never`, read-only mount at `/config` | 1 |
| Job complete, 4 succeeded | 1 |
| `index-2.log` = `index=2 shard=ap-south` | 1 |

---

## Question 3 — One Secret, consumed two ways (5%)

**Approach:** `--from-env-file` turns every `KEY=value` line into a key. Inject one key with `secretKeyRef`, and project one other key as a file with `items`. Don't use `envFrom`, because it would also leak `API_KEY`.

```bash
kubectl -n m05-secrets create secret generic merchant-creds \
  --from-env-file=$HOME/ckad-mocks/exam-05/q03/merchant.env
kubectl -n m05-secrets get secret merchant-creds -o jsonpath='{.data}{"\n"}'   # API_KEY, DB_PASSWORD, TLS_PIN
kubectl -n m05-secrets run merchant-api --image=nginx:1.27-alpine --dry-run=client -o yaml > q03.yaml
vim q03.yaml
```

```yaml
# q03.yaml — kubectl apply -f q03.yaml
apiVersion: v1
kind: Pod
metadata:
  name: merchant-api
  namespace: m05-secrets
spec:
  containers:
  - name: api                    # kubectl run named it merchant-api: rename
    image: nginx:1.27-alpine
    env:
    - name: DB_PASS
      valueFrom:
        secretKeyRef:
          name: merchant-creds
          key: DB_PASSWORD
    volumeMounts:
    - name: pin
      mountPath: /etc/merchant
      readOnly: true
  volumes:
  - name: pin
    secret:
      secretName: merchant-creds
      items:                     # project only this key ...
      - key: TLS_PIN
        path: pin                # ... as /etc/merchant/pin (relative path!)
```

**Verify**

```bash
kubectl -n m05-secrets exec merchant-api -c api -- printenv DB_PASS
kubectl -n m05-secrets exec merchant-api -c api -- ls /etc/merchant
kubectl -n m05-secrets exec merchant-api -c api -- cat /etc/merchant/pin
kubectl -n m05-secrets exec merchant-api -c api -- sh -c 'env | grep -c API_KEY; grep -rl pk_m05 /etc/merchant | wc -l'
```

```text
Sup3r-S3cret-m05
pin
sha256-m05-9d8c7b
0
0
```

**Common mistakes**
- `--from-file=merchant.env`. That creates one key named `merchant.env` that holds the whole file.
- `envFrom: - secretRef:`, which exposes `API_KEY` (and every future key) as environment variables.
- Mounting the whole Secret. All three files appear in `/etc/merchant`.
- `items[].path: /etc/merchant/pin`. The path must be relative to the mount point.
- Using `subPath`. It works, but the file then never receives Secret updates, and it isn't needed here.

| Item | Points |
|---|---|
| Secret with exactly the 3 keys | 1 |
| `DB_PASS` via `secretKeyRef` | 1 |
| Only `pin` in `/etc/merchant`, with the TLS_PIN value | 2 |
| `API_KEY` not exposed (no `envFrom`, no file) | 1 |

---

## Question 4 — A Service without endpoints (5%)

**Approach:** Both Pods are Running, so look at the Service → EndpointSlice → Pod port chain. The Service targets the **port name** `http`, but the container port is named `web-http`. The Service is off limits, so rename the container port in the Deployment.

```bash
kubectl -n m05-svc get endpointslices -l kubernetes.io/service-name=billing
# NAME            ADDRESSTYPE   PORTS     ENDPOINTS               AGE
# billing-8xk2d   IPv4          <unset>   10.244.1.7,10.244.2.9   12m     <- no port could be resolved
kubectl -n m05-svc get svc billing -o jsonpath='{.spec.ports[0].targetPort}{"\n"}'                     # http
kubectl -n m05-svc get deploy billing -o jsonpath='{.spec.template.spec.containers[0].ports}{"\n"}'
# [{"containerPort":80,"name":"web-http","protocol":"TCP"}]

kubectl -n m05-svc patch deployment billing --type=json \
  -p='[{"op":"replace","path":"/spec/template/spec/containers/0/ports/0/name","value":"http"}]'
kubectl -n m05-svc rollout status deployment billing

kubectl -n m05-svc exec client -- wget -qO- -T 3 http://billing | grep -o '<title>.*</title>' \
  > ~/ckad-mocks/exam-05/q04/title.txt
```

The fixed workload, if you prefer `kubectl edit` / `kubectl apply`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: billing
  namespace: m05-svc
  labels:
    app: billing
spec:
  replicas: 2
  selector:
    matchLabels:
      app: billing
  template:
    metadata:
      labels:
        app: billing
    spec:
      containers:
      - name: web
        image: nginx:1.27-alpine
        ports:
        - name: http             # now matches Service targetPort "http"
          containerPort: 80
```

**Verify**

```bash
kubectl -n m05-svc get endpointslices -l kubernetes.io/service-name=billing     # PORTS 80, 2 endpoints
cat ~/ckad-mocks/exam-05/q04/title.txt
[ "$(kubectl -n m05-svc get svc billing -o jsonpath='{.metadata.resourceVersion}')" = \
  "$(cat ~/ckad-mocks/exam-05/.state/q04-svc-rv)" ] && echo "Service untouched"
```

```text
<title>Welcome to nginx!</title>
Service untouched
```

**Common mistakes**
- Changing the Service's `targetPort` to `80` or `web-http`, which breaks the explicit constraint.
- Editing the Pods instead of the Deployment. Container ports of a running Pod can't be changed, and the next rollout would bring the bug back anyway.
- Trusting "Pods are Running". Running isn't the same as being an endpoint: always check `kubectl get endpointslices -l kubernetes.io/service-name=<svc>`.
- Saving the whole HTML page instead of the `<title>` line.

| Item | Points |
|---|---|
| Deployment container port renamed to `http` and rolled out | 2 |
| Service unchanged | 1 |
| EndpointSlice lists 2 endpoints on port 80 | 1 |
| `title.txt` = `<title>Welcome to nginx!</title>` | 1 |

---

## Question 5 — A worker that keeps restarting (5%)

**Approach:** The **waiting** reason of a looping container is `CrashLoopBackOff`. The **termination** reason sits in `lastState.terminated`. Exit code 137 = 128 + 9 (SIGKILL); together with reason `OOMKilled`, it means the container hit its memory limit.

```bash
kubectl -n m05-oom get pods -l app=thumbnailer
# thumbnailer-6b9d...   0/1   CrashLoopBackOff   5 (40s ago)   4m
kubectl -n m05-oom describe pod -l app=thumbnailer | grep -A4 'Last State'
#     Last State:     Terminated
#       Reason:       OOMKilled
#       Exit Code:    137

P=$(kubectl -n m05-oom get pod -l app=thumbnailer -o jsonpath='{.items[0].metadata.name}')
kubectl -n m05-oom get pod "$P" -o jsonpath='{.status.containerStatuses[?(@.name=="resizer")].lastState.terminated.reason}:{.status.containerStatuses[?(@.name=="resizer")].lastState.terminated.exitCode}{"\n"}' \
  > ~/ckad-mocks/exam-05/q05/reason.txt

kubectl -n m05-oom set resources deployment thumbnailer -c resizer --limits=memory=128Mi --requests=memory=64Mi
kubectl -n m05-oom rollout status deployment thumbnailer
```

The resulting Deployment (only `resources.memory` changed):

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: thumbnailer
  namespace: m05-oom
  labels:
    app: thumbnailer
spec:
  replicas: 1
  selector:
    matchLabels:
      app: thumbnailer
  template:
    metadata:
      labels:
        app: thumbnailer
    spec:
      containers:
      - name: resizer
        image: busybox:1.36
        command: ["sh", "-c"]
        args:
        - |
          echo "thumbnailer: loading image cache"
          cache=$(yes 0123456789abcdef | head -c 40000000)
          echo "thumbnailer: cache ready"
          while true; do sleep 30; done
        resources:
          requests:
            cpu: 50m
            memory: 64Mi
          limits:
            cpu: 500m
            memory: 128Mi
```

**Verify**

```bash
cat ~/ckad-mocks/exam-05/q05/reason.txt
kubectl -n m05-oom get deploy thumbnailer -o jsonpath='{.spec.template.spec.containers[0].resources}{"\n"}'
kubectl -n m05-oom get pods -l app=thumbnailer
kubectl -n m05-oom logs deploy/thumbnailer
```

```text
OOMKilled:137
{"limits":{"cpu":"500m","memory":"128Mi"},"requests":{"cpu":"50m","memory":"64Mi"}}
NAME                          READY   STATUS    RESTARTS   AGE
thumbnailer-7f8c6d9b4-q2w9x   1/1     Running   0          70s
thumbnailer: loading image cache
thumbnailer: cache ready
```

The script keeps a ~40 MB string in the shell's memory. With 32Mi that can never fit, and with 128Mi it fits with headroom.

**Common mistakes**
- Writing `CrashLoopBackOff:...`. That is the waiting reason, not the termination reason.
- Reading `.state` instead of `.lastState`. While the container waits, `.state.terminated` is empty.
- Typing `128M` or, worse, `128m` (128 milli-bytes). Use `Mi`.
- Changing the CPU values, or editing the Pod instead of the Deployment.

| Item | Points |
|---|---|
| `reason.txt` = `OOMKilled:137` | 2 |
| limit 128Mi / request 64Mi, CPU and command unchanged | 2 |
| New Pod Running, 0 restarts | 1 |

---

## Question 6 — Init container that waits for a Service (5%)

**Approach:** An init container must exit 0 before app containers start. busybox `nslookup` exits non-zero on NXDOMAIN, so the loop waits until the Service name exists. A ClusterIP Service gets its DNS A record as soon as it is created, even before its endpoints are ready.

```yaml
# q06-exporter.yaml — kubectl apply -f q06-exporter.yaml
apiVersion: v1
kind: Pod
metadata:
  name: exporter
  namespace: m05-init
spec:
  initContainers:
  - name: wait-for-db
    image: busybox:1.36
    command:
    - sh
    - -c
    - until nslookup db.m05-init.svc.cluster.local; do echo waiting for db; sleep 2; done; nslookup db.m05-init.svc.cluster.local > /work/db-dns.txt
    volumeMounts:
    - name: work
      mountPath: /work
  containers:
  - name: export
    image: busybox:1.36
    command:
    - sh
    - -c
    - cat /work/db-dns.txt; sleep 3600
    volumeMounts:
    - name: work
      mountPath: /work
  volumes:
  - name: work
    emptyDir: {}
```

```bash
kubectl apply -f q06-exporter.yaml
kubectl -n m05-init get pod exporter                         # Init:0/1
kubectl -n m05-init logs exporter -c wait-for-db --tail=3     # ... NXDOMAIN / waiting for db
kubectl -n m05-init expose deployment db --name=db --port=5432 --target-port=5432
kubectl -n m05-init get pod exporter -w                       # Init:0/1 -> PodInitializing -> Running (Ctrl-C)
kubectl -n m05-init logs exporter -c export > ~/ckad-mocks/exam-05/q06/export.log
```

**Verify**

```bash
kubectl -n m05-init get svc db -o jsonpath='{.spec.type} {.spec.ports[0].port}->{.spec.ports[0].targetPort} {.spec.selector}{"\n"}'
kubectl -n m05-init get pod exporter
cat ~/ckad-mocks/exam-05/q06/export.log
```

```text
ClusterIP 5432->5432 {"app":"db"}
NAME       READY   STATUS    RESTARTS   AGE
exporter   1/1     Running   0          3m
Server:		10.96.0.10
Address:	10.96.0.10:53

Name:	db.m05-init.svc.cluster.local
Address: 10.96.87.141
```

(IP addresses differ per cluster.)

**Common mistakes**
- Mounting the `emptyDir` in only one container. Then the file written by the init container is invisible to `export`, which fails with `cat: can't open`.
- Shortening the name to `db.m05-init`. The `nslookup` of current busybox versions (such as 1.36) applies search domains only to names **without** a dot, so `db.m05-init` never resolves. The bare `db` or the FQDN work.
- Creating a **headless** Service. Its DNS record lists only ready endpoints, so it can stay empty for a while.
- Creating the Service in another namespace or under another name.

| Item | Points |
|---|---|
| Pod with init container + app container, commands exactly as given | 2 |
| Shared `emptyDir` `work` mounted at `/work` in both | 1 |
| ClusterIP Service `db` 5432→5432 selecting the db Pod | 1 |
| `export.log` contains the resolved name | 1 |

---

## Question 7 — Helm: pull, customise, install, upgrade, roll back (5%)

**Approach:** `helm pull --untar` gives you an editable chart directory. Install from the **directory**, so that your edited `values.yaml` becomes the chart default. On upgrade, `--reuse-values` keeps the previous release's user-supplied values (`ui.message=blue`) and merges the new `--set` on top. Check `helm version`: the commands below are the same in Helm 3 and 4, but verify any other flag with `helm <cmd> --help`.

```bash
helm version
helm repo add m05-podinfo https://stefanprodan.github.io/podinfo
helm repo update
helm pull m05-podinfo/podinfo --untar --untardir ~/ckad-mocks/exam-05/q07
ls ~/ckad-mocks/exam-05/q07/podinfo                  # Chart.yaml  values.yaml  templates/ ...

sed -i 's/^replicaCount: .*/replicaCount: 2/' ~/ckad-mocks/exam-05/q07/podinfo/values.yaml
grep -n '^replicaCount' ~/ckad-mocks/exam-05/q07/podinfo/values.yaml   # replicaCount: 2

helm install web ~/ckad-mocks/exam-05/q07/podinfo -n m05-helm --set ui.message=blue
helm upgrade web ~/ckad-mocks/exam-05/q07/podinfo -n m05-helm --reuse-values --set ui.color='#00aa00'
helm rollback web 1 -n m05-helm
helm history web -n m05-helm > ~/ckad-mocks/exam-05/q07/history.txt
```

**Verify**

```bash
cat ~/ckad-mocks/exam-05/q07/history.txt
helm get values web -n m05-helm
helm get values web -n m05-helm --revision 2
kubectl -n m05-helm get deploy
kubectl -n m05-helm get deploy web-podinfo \
  -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="PODINFO_UI_MESSAGE")].value}{"\n"}'
```

```text
REVISION  UPDATED                   STATUS      CHART           APP VERSION  DESCRIPTION
1         Sat Oct 17 10:12:01 2026  superseded  podinfo-6.x.y   6.x.y        Install complete
2         Sat Oct 17 10:13:30 2026  superseded  podinfo-6.x.y   6.x.y        Upgrade complete
3         Sat Oct 17 10:14:05 2026  deployed    podinfo-6.x.y   6.x.y        Rollback to 1
USER-SUPPLIED VALUES:
ui:
  message: blue
USER-SUPPLIED VALUES:
ui:
  color: '#00aa00'
  message: blue
NAME          READY   UP-TO-DATE   AVAILABLE   AGE
web-podinfo   2/2     2            2           2m
blue
```

(The chart version is whatever is current in the repository. The chart's fullname helper combines the release name `web` and the chart name into the Deployment name `web-podinfo`, and it passes `ui.message` to the container as the env var `PODINFO_UI_MESSAGE`.)

**Common mistakes**
- `helm install web m05-podinfo/podinfo`. That installs from the repository, so your edited `values.yaml` is ignored and you get 1 replica.
- Upgrading with `--set ui.color=...` but without `--reuse-values`. The upgrade then starts from the chart defaults and silently drops `ui.message=blue`.
- Forgetting `-n m05-helm` on `history`/`rollback`/`get values`, which gives `Error: release: not found`.
- Expecting `helm rollback` to restore revision 1 *as* revision 1. It creates a **new** revision (3) with revision 1's manifest and values.

| Item | Points |
|---|---|
| Repo added, chart pulled and unpacked to `q07/podinfo` | 1 |
| `replicaCount: 2` in values.yaml, installed from the directory with `ui.message=blue` | 1.5 |
| Revision 2 = upgrade with `--reuse-values` + `ui.color` (both values in rev 2) | 1.5 |
| Revision 3 = rollback to 1, `history.txt` written | 1 |

---

## Question 8 — Narrow RBAC for a debugging ServiceAccount (7%)

**Approach:** `resourceNames` restrict a rule to named objects, and subresources are written `pods/log` and `pods/exec`. `list`/`watch` can't be limited by name, so the SA gets no list access. The SA-level `automountServiceAccountToken: false` is a default that a Pod can override with its own `automountServiceAccountToken: true`.

```bash
kubectl -n m05-rbac create serviceaccount log-reader --dry-run=client -o yaml > q08.yaml
kubectl -n m05-rbac create role app-1-debug --verb=get --resource=pods,pods/log --resource-name=app-1 \
  --dry-run=client -o yaml >> q08.yaml          # then add the exec rule by hand (below)
vim q08.yaml
```

```yaml
# q08.yaml — kubectl apply -f q08.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: log-reader
  namespace: m05-rbac
automountServiceAccountToken: false      # SA-level default: no token
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: app-1-debug
  namespace: m05-rbac
rules:
- apiGroups: [""]
  resources: ["pods", "pods/log"]
  resourceNames: ["app-1"]
  verbs: ["get"]
- apiGroups: [""]
  resources: ["pods/exec"]
  resourceNames: ["app-1"]
  verbs: ["create"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: app-1-debug
  namespace: m05-rbac
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: app-1-debug
subjects:
- kind: ServiceAccount
  name: log-reader
  namespace: m05-rbac
---
apiVersion: v1
kind: Pod
metadata:
  name: log-agent
  namespace: m05-rbac
spec:
  serviceAccountName: log-reader
  automountServiceAccountToken: true     # Pod-level setting overrides the SA default
  containers:
  - name: agent
    image: curlimages/curl:8.10.1
    command: ["sleep", "3600"]
```

The RoleBinding imperatively: `kubectl -n m05-rbac create rolebinding app-1-debug --role=app-1-debug --serviceaccount=m05-rbac:log-reader`.

Fill the matrix. `kubectl auth can-i` prints `yes`/`no` and accepts `TYPE/NAME` plus `--subresource`:

```bash
SA=system:serviceaccount:m05-rbac:log-reader
c() { kubectl auth can-i "$@" --as="$SA" -n m05-rbac 2>/dev/null; }
cat > ~/ckad-mocks/exam-05/q08/can-i.txt <<EOF
get pods app-1 = $(c get pods/app-1)
get pods app-2 = $(c get pods/app-2)
get pods/log app-1 = $(c get pods/app-1 --subresource=log)
get pods/log app-2 = $(c get pods/app-2 --subresource=log)
create pods/exec app-1 = $(c create pods/app-1 --subresource=exec)
list pods = $(c list pods)
delete pods app-1 = $(c delete pods/app-1)
EOF
```

**Verify**

```bash
cat ~/ckad-mocks/exam-05/q08/can-i.txt
kubectl -n m05-rbac get sa log-reader -o jsonpath='automount={.automountServiceAccountToken}{"\n"}'
kubectl -n m05-rbac exec log-agent -- ls /var/run/secrets/kubernetes.io/serviceaccount
# optional proof with the token itself (app-2 would answer 403):
kubectl -n m05-rbac exec log-agent -- sh -c 'T=/var/run/secrets/kubernetes.io/serviceaccount; curl -s --cacert $T/ca.crt -H "Authorization: Bearer $(cat $T/token)" "https://kubernetes.default.svc/api/v1/namespaces/m05-rbac/pods/app-1/log?tailLines=2"'
```

```text
get pods app-1 = yes
get pods app-2 = no
get pods/log app-1 = yes
get pods/log app-2 = no
create pods/exec app-1 = yes
list pods = no
delete pods app-1 = no
automount=false
ca.crt
namespace
token
Sat Oct 17 10:20:01 UTC 2026 app-1 heartbeat
Sat Oct 17 10:20:06 UTC 2026 app-1 heartbeat
```

**Common mistakes**
- Running `can-i` without `-n m05-rbac`. It then checks the default namespace and every answer is `no`.
- `--as=log-reader`. That impersonates a *user* called log-reader; ServiceAccounts are `system:serviceaccount:<ns>:<name>`.
- One rule with verbs `[get, create]` over `pods`, `pods/log` and `pods/exec`. That is broader than asked: it also grants `create` on `pods/log` and `get` on `pods/exec`.
- Putting `automountServiceAccountToken: false` on the Pod, or forgetting `true` on the Pod. Either way `log-agent` has no token.
- `serviceAccount:` (deprecated field name) instead of `serviceAccountName:`.

> **Exam tip:** `kubectl exec` needs `get` on the Pod plus `create` on `pods/exec`. Newer kubectl versions stream exec over WebSockets (an HTTP GET), and on some cluster versions that request is authorised as `get` on `pods/exec`. If `kubectl exec --as=...` is refused while `can-i create` says yes, also grant `get` on `pods/exec`.

| Item | Points |
|---|---|
| SA `log-reader` with `automountServiceAccountToken: false` | 1 |
| Role: get pods+pods/log, create pods/exec, all limited to `app-1` | 2 |
| RoleBinding to the SA | 1 |
| `can-i.txt` all 7 answers correct (yes, no, yes, no, yes, no, no) | 2 |
| `log-agent` runs as `log-reader` and has a token | 1 |

---

## Question 9 — Egress allow-list for an API Pod (7%)

**Approach:** Write the policy, then **test** it. NetworkPolicies are additive: the existing `allow-all-egress` selects every Pod and allows all egress, so your restrictive policy changes nothing while that one exists. Delete it (no other egress policy selects `db`/`cache`, so they stay unrestricted), or narrow it so that it no longer selects `api`.

```bash
kubectl -n m05-netpol get netpol
kubectl -n m05-netpol describe netpol allow-all-egress     # PodSelector: <none> (all Pods), Allowing egress traffic: To: <any>
kubectl -n m05-netpol exec api -- nc -zv -w 3 cache 6379   # "open" - the leak you must close
```

```yaml
# q09-api-egress.yaml — kubectl apply -f q09-api-egress.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: api-egress
  namespace: m05-netpol
spec:
  podSelector:
    matchLabels:
      app: api
  policyTypes:
  - Egress                     # Ingress NOT listed -> incoming traffic stays unrestricted
  egress:
  - to:
    - podSelector:
        matchLabels:
          app: db
    ports:
    - protocol: TCP
      port: 5432
  - to:
    - namespaceSelector:       # ONE element with both selectors = AND
        matchLabels:
          kubernetes.io/metadata.name: kube-system
      podSelector:
        matchLabels:
          k8s-app: kube-dns
    ports:
    - protocol: UDP
      port: 53
    - protocol: TCP
      port: 53
```

```bash
kubectl apply -f q09-api-egress.yaml
kubectl -n m05-netpol delete netpol allow-all-egress
```

Alternative to deleting: keep the legacy policy but stop it from selecting `api`:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-all-egress
  namespace: m05-netpol
spec:
  podSelector:
    matchExpressions:
    - key: app
      operator: NotIn
      values: ["api"]
  policyTypes:
  - Egress
  egress:
  - {}
```

**Verify**

```bash
kubectl -n m05-netpol exec api -- nc -zv -w 3 db 5432
kubectl -n m05-netpol exec api -- nc -zv -w 3 cache 6379; echo "exit=$?"
kubectl -n m05-netpol exec api -- nslookup db.m05-netpol.svc.cluster.local | tail -2
kubectl -n m05-netpol exec db -- bash -c 'echo > /dev/tcp/cache/6379 && echo "db egress still open"'
```

```text
db (10.96.41.7:5432) open
nc: cache (10.96.200.3:6379): Connection timed out
exit=1
Name:	db.m05-netpol.svc.cluster.local
Address: 10.96.41.7
db egress still open
```

(The exact `nc` error text differs between versions. What matters is "open" for db, and a failure after about 3 s for cache.)

**Common mistakes**
- Not checking existing policies, so `cache:6379` stays reachable through `allow-all-egress`.
- Writing the DNS peer as two list items (`- namespaceSelector: ...` and `- podSelector: ...`). That is an **OR**: any Pod in kube-system, or kube-dns-labelled Pods in m05-netpol.
- Allowing only UDP 53. Large DNS answers and some resolvers use TCP.
- Adding `Ingress` to `policyTypes`, which silently denies all incoming traffic to `api`.
- Thinking a policy on `db` is needed. Egress is controlled at the source; nothing restricts `db`'s ingress here.

| Item | Points |
|---|---|
| Policy selects `app=api`, `policyTypes: [Egress]` only | 1 |
| Egress to `app=db` on TCP 5432 | 2 |
| DNS egress UDP+TCP 53 to kube-dns Pods in kube-system (AND-ed selectors) | 2 |
| Permissive `allow-all-egress` deleted or narrowed (cache unreachable from api) | 1 |
| `db`/`cache` egress still unrestricted | 1 |

---

## Question 10 — Probes for a slow-starting store (5%)

**Approach:** A startupProbe suspends liveness and readiness until it succeeds. Its budget is `failureThreshold × periodSeconds`, so 90 s ÷ 5 s = **18**. Edit the Deployment, not the Pod.

```bash
kubectl -n m05-probes get pods -l app=session-store                 # RESTARTS climbing
kubectl -n m05-probes describe pod -l app=session-store | grep -E 'Liveness|Unhealthy|Killing' | head -4
kubectl -n m05-probes edit deployment session-store
```

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: session-store
  namespace: m05-probes
  labels:
    app: session-store
spec:
  replicas: 1
  selector:
    matchLabels:
      app: session-store
  template:
    metadata:
      labels:
        app: session-store
    spec:
      containers:
      - name: redis
        image: redis:7.2
        command: ["sh", "-c"]
        args: ["echo 'session-store warming up (40s)'; sleep 40; exec redis-server"]
        ports:
        - containerPort: 6379
        startupProbe:
          tcpSocket:
            port: 6379
          periodSeconds: 5
          failureThreshold: 18        # 18 x 5 s = 90 s to start
        livenessProbe:
          exec:
            command: ["redis-cli", "ping"]
          periodSeconds: 10
          failureThreshold: 3
        readinessProbe:
          tcpSocket:
            port: 6379
          periodSeconds: 5
```

**Verify**

```bash
kubectl -n m05-probes rollout status deployment session-store --timeout=150s
kubectl -n m05-probes get pod -l app=session-store \
  -o jsonpath='{range .items[*]}{.metadata.name} ready={.status.containerStatuses[0].ready} restarts={.status.containerStatuses[0].restartCount}{"\n"}{end}'
kubectl -n m05-probes get deploy session-store -o jsonpath='{.spec.template.spec.containers[0].startupProbe}{"\n"}'
```

```text
deployment "session-store" successfully rolled out
session-store-5c8d7f6b9-k4mzq ready=true restarts=0
{"failureThreshold":18,"periodSeconds":5,"successThreshold":1,"tcpSocket":{"port":6379},"timeoutSeconds":1}
```

**Common mistakes**
- `failureThreshold: 9`, which divides by the liveness period (10 s) instead of the startup period (5 s).
- Keeping `initialDelaySeconds: 5` on liveness, or "fixing" the problem with a huge `initialDelaySeconds`. That wasn't asked, and it delays failure detection on every restart.
- `command: "redis-cli ping"` as a single string. `exec.command` is a list.
- Judging too early. The new Pod becomes Ready only after about 40–45 s. During the rollout the *old* Pod is still crash-looping, so look at the new one.

| Item | Points |
|---|---|
| startupProbe tcpSocket 6379, period 5, failureThreshold 18 | 2 |
| livenessProbe exec `redis-cli ping`, period 10, threshold 3, no initial delay | 1 |
| readinessProbe tcpSocket 6379, period 5 | 1 |
| Rollout complete, new Pod Ready with 0 restarts | 1 |

---

## Question 11 — Prove that data survives a Pod (5%)

**Approach:** Both kind (`standard`, local-path) and minikube ship a default StorageClass, so a PVC without `storageClassName` is provisioned dynamically. With `WaitForFirstConsumer`, the claim stays `Pending` until a Pod uses it. That is normal. `Recreate` avoids two Pods fighting over a ReadWriteOnce volume during updates.

```yaml
# q11.yaml — kubectl apply -f q11.yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: journal-data
  namespace: m05-storage
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 100Mi
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: journal
  namespace: m05-storage
spec:
  replicas: 1
  strategy:
    type: Recreate
  selector:
    matchLabels:
      app: journal
  template:
    metadata:
      labels:
        app: journal
    spec:
      containers:
      - name: writer
        image: busybox:1.36
        command:
        - sh
        - -c
        - echo "boot $(hostname) $(date)" >> /data/journal.log; sleep 3600
        volumeMounts:
        - name: data
          mountPath: /data
      volumes:
      - name: data
        persistentVolumeClaim:
          claimName: journal-data
```

Imperative start: `kubectl -n m05-storage create deployment journal --image=busybox:1.36 $do -- sh -c '...'`, then rename the container to `writer` and add the strategy and the volume.

```bash
kubectl apply -f q11.yaml
kubectl -n m05-storage rollout status deployment journal
kubectl -n m05-storage delete pod -l app=journal
kubectl -n m05-storage get pods -l app=journal -w        # wait until only the NEW Pod is Running (Ctrl-C)
kubectl -n m05-storage exec deploy/journal -- cat /data/journal.log > ~/ckad-mocks/exam-05/q11/journal.txt
```

**Verify**

```bash
kubectl -n m05-storage get pvc journal-data -o jsonpath='{.status.phase} {.spec.storageClassName}{"\n"}'
cat ~/ckad-mocks/exam-05/q11/journal.txt
awk '{print $2}' ~/ckad-mocks/exam-05/q11/journal.txt | sort -u | wc -l
```

```text
Bound standard
boot journal-6d5f7c9b8-abcde Sat Oct 17 10:31:02 UTC 2026
boot journal-6d5f7c9b8-fghij Sat Oct 17 10:33:44 UTC 2026
2
```

**Common mistakes**
- `storageClassName: ""`. An empty string means "no dynamic provisioning", so the claim stays Pending forever.
- Deciding the PVC is broken because it is Pending before any Pod uses it.
- Using `emptyDir`. Its data dies with the Pod, which is exactly what this task disproves.
- Reading the file before the replacement Pod has started.

| Item | Points |
|---|---|
| PVC `journal-data` Bound via the default StorageClass | 1 |
| Deployment `journal`: Recreate, container `writer`, mount at `/data`, exact command | 2 |
| `journal.txt` has two `boot` lines from two Pods | 2 |

---

## Question 12 — Kustomize: labels that leave selectors alone, plus a JSON 6902 patch (5%)

**Approach:** `labels:` with `includeSelectors: false` + `includeTemplates: true` labels metadata and Pod templates but leaves selectors alone. The deprecated `commonLabels` (or `includeSelectors: true`) would rewrite `spec.selector`, which is **immutable**, so `apply -k` would fail. JSON 6902 patches go under `patches:` with a `target`.

```yaml
# ~/ckad-mocks/exam-05/q12/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: m05-kustomize
resources:
- deployment.yaml
- service.yaml
labels:
- pairs:
    team: logistics
    env: staging
  includeSelectors: false      # never touch spec.selector / Service selector
  includeTemplates: true       # but do label the Pod template
patches:
- target:
    group: apps
    version: v1
    kind: Deployment
    name: warehouse
  patch: |-
    - op: replace
      path: /spec/replicas
      value: 3
    - op: add
      path: /spec/template/spec/containers/0/env
      value:
      - name: MODE
        value: readonly
```

```bash
cd ~/ckad-mocks/exam-05/q12
kubectl kustomize . > rendered.yaml
kubectl diff -k .               # optional preview; exit code 1 just means "there are differences"
kubectl apply -k .
kubectl -n m05-kustomize rollout status deployment warehouse
```

**Verify**

```bash
kubectl -n m05-kustomize get deploy warehouse -o jsonpath='{.spec.selector.matchLabels}{"\n"}{.metadata.labels}{"\n"}{.spec.template.metadata.labels}{"\n"}{.spec.replicas}{"\n"}'
kubectl -n m05-kustomize get svc warehouse -o jsonpath='{.spec.selector}{"\n"}{.metadata.labels}{"\n"}'
kubectl -n m05-kustomize exec deploy/warehouse -- printenv MODE
grep -c 'team: logistics' ~/ckad-mocks/exam-05/q12/rendered.yaml
```

```text
{"app":"warehouse"}
{"app":"warehouse","env":"staging","team":"logistics"}
{"app":"warehouse","env":"staging","team":"logistics"}
3
{"app":"warehouse"}
{"app":"warehouse","env":"staging","team":"logistics"}
readonly
3
```

**Common mistakes**
- `commonLabels:`. The apply fails with `spec.selector: Invalid value: ... field is immutable`, and the Service would select differently.
- Leaving out `includeTemplates: true`, so the Pod template stays unlabelled.
- `op: add` with path `/spec/template/spec/containers/0/env/-` when the container has no `env` yet. JSON patch can't append to a missing list, so add the whole list.
- Editing `deployment.yaml` (forbidden by the task) or applying `rendered.yaml` instead of `-k`.

> **Exam tip:** The Kustomize reference site (kubectl.docs.kubernetes.io) is **not** an allowed exam resource. The allowed page is *Declarative Management of Kubernetes Objects Using Kustomize* under kubernetes.io/docs/tasks/manage-kubernetes-objects/kustomization/. It shows `patches`, generators and labels, so practise from that page.

| Item | Points |
|---|---|
| Labels on metadata + Pod template, selectors unchanged | 2 |
| JSON 6902 patch: replicas 3 and `MODE=readonly` | 2 |
| `rendered.yaml` written and kustomization applied | 1 |

---

## Question 13 — Admission says no (6%)

**Approach:** With no Pods there are no Pod events. The ReplicaSet records `FailedCreate` with the admission error. The first error comes from **LimitRanger** (limit 512Mi > max 256Mi). The trap is that when a container sets only limits, the API server copies them into requests. After you lower the limit to 256Mi, the requests become 3 × 256Mi = 768Mi, which exceeds the quota's `requests.memory: 512Mi`, so set an explicit memory request ≤ 170Mi.

```bash
kubectl -n m05-quota get deploy,rs,pods
kubectl -n m05-quota describe rs -l app=analytics | grep -m1 FailedCreate
# Warning  FailedCreate ... Error creating: pods "analytics-7c6d9f8b5d-x2k4q" is forbidden:
#          maximum memory usage per Container is 256Mi, but limit is 512Mi
echo LimitRanger > ~/ckad-mocks/exam-05/q13/rejected-by.txt

kubectl -n m05-quota describe limitrange container-limits
kubectl -n m05-quota describe resourcequota team-quota
kubectl -n m05-quota set resources deployment analytics -c etl --limits=memory=256Mi --requests=memory=128Mi
kubectl -n m05-quota rollout status deployment analytics
```

If you change only the limit, the third Pod fails with:

```text
Error creating: pods "analytics-..." is forbidden: exceeded quota: team-quota, requested: requests.memory=256Mi, used: requests.memory=512Mi, limited: requests.memory=512Mi
```

The fixed Deployment:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: analytics
  namespace: m05-quota
  labels:
    app: analytics
spec:
  replicas: 3
  selector:
    matchLabels:
      app: analytics
  template:
    metadata:
      labels:
        app: analytics
    spec:
      containers:
      - name: etl
        image: nginx:1.27-alpine
        resources:
          requests:
            memory: 128Mi      # 3 x 128Mi = 384Mi <= quota 512Mi
          limits:
            cpu: 300m          # unchanged (its request still defaults to 300m)
            memory: 256Mi      # LimitRange max
```

Admission plugins: the kube-apiserver is a static Pod. Its manifest lives on the control-plane node, and its mirror Pod shows the same command line.

```bash
# fastest, from anywhere kubectl works:
kubectl -n kube-system get pod -l component=kube-apiserver -o yaml \
  | grep -o -- '--enable-admission-plugins=[^"[:space:]]*' | head -1 | cut -d= -f2 \
  > ~/ckad-mocks/exam-05/q13/admission-plugins.txt

# reading the manifest file itself:
docker exec ckad-control-plane grep -- --enable-admission-plugins /etc/kubernetes/manifests/kube-apiserver.yaml   # kind (cluster "ckad"; podman provider: podman exec)
minikube ssh -- sudo grep -- --enable-admission-plugins /etc/kubernetes/manifests/kube-apiserver.yaml             # minikube
sudo grep -- --enable-admission-plugins /etc/kubernetes/manifests/kube-apiserver.yaml                             # on a control-plane host you are logged in to
```

On the real exam you `ssh` to the host that the task names and `exit` afterwards (nested ssh is not supported). The `kubectl -n kube-system get pod -l component=kube-apiserver -o yaml` route works from any host that has kubectl, so it is the safest first choice.

**Verify**

```bash
cat ~/ckad-mocks/exam-05/q13/rejected-by.txt ~/ckad-mocks/exam-05/q13/admission-plugins.txt
kubectl -n m05-quota get deploy analytics
kubectl -n m05-quota get resourcequota team-quota -o jsonpath='{.status.used}{"\n"}'
```

```text
LimitRanger
NodeRestriction
NAME        READY   UP-TO-DATE   AVAILABLE   AGE
analytics   3/3     3            3           2m
{"limits.cpu":"900m","limits.memory":"768Mi","pods":"3","requests.cpu":"900m","requests.memory":"384Mi"}
```

`NodeRestriction` is the kubeadm/kind value; minikube passes a longer explicit list. Plugins that are on by default (NamespaceLifecycle, LimitRanger, ServiceAccount, ResourceQuota, PodSecurity, …) are **not** listed in the flag. `kubectl -n kube-system exec kube-apiserver-ckad-control-plane -- kube-apiserver -h | grep -A3 'enable-admission-plugins'` shows the default set.

**Common mistakes**
- Answering `ResourceQuota` in step 1. The quota error appears only after you have fixed the limit.
- Raising only the limit, which gives 2/3 Pods.
- Editing the LimitRange or the quota.
- Running `kubectl describe deployment` and finding no reason. The detail is on the ReplicaSet; the Deployment only shows `ReplicaFailure`.
- Looking for `/etc/kubernetes/manifests` on your workstation. It is on the control-plane node.

| Item | Points |
|---|---|
| `rejected-by.txt` = `LimitRanger` | 1 |
| memory limit 256Mi, CPU unchanged | 1 |
| memory request ≤ 170Mi, 3/3 Pods running, quota/LimitRange untouched | 2 |
| `admission-plugins.txt` = the flag value of your cluster | 2 |

---

## Question 14 — Multi-host Ingress with a default backend (7%)

**Approach:** Generate the Ingress with `kubectl create ingress`. A `*` at the end of the path means `Prefix`, without it the path is `Exact`. Named Service ports work in both `--rule` and `--default-backend`. Test with `curl -H 'Host: …'` against the controller.

```bash
kubectl -n m05-ingress get svc
kubectl -n m05-ingress create ingress edge --class=nginx \
  --rule="docs.m05.local/*=docs:80" \
  --rule="status.m05.local/api*=status-api:http" \
  --default-backend=fallback:80 \
  --dry-run=client -o yaml > q14-edge.yaml
kubectl apply -f q14-edge.yaml
```

```yaml
# q14-edge.yaml (what the command above generates, tidied)
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: edge
  namespace: m05-ingress
spec:
  ingressClassName: nginx
  defaultBackend:
    service:
      name: fallback
      port:
        number: 80
  rules:
  - host: docs.m05.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: docs
            port:
              number: 80
  - host: status.m05.local
    http:
      paths:
      - path: /api
        pathType: Prefix
        backend:
          service:
            name: status-api
            port:
              name: http          # Service port 8080, referenced by name
```

```bash
ING=http://localhost:8080        # kit kind lab; minikube: http://$(minikube ip)
# any cluster: kubectl -n ingress-nginx port-forward svc/ingress-nginx-controller 8080:80 &
curl -s -H 'Host: docs.m05.local'   $ING/guide      > ~/ckad-mocks/exam-05/q14/docs.txt
curl -s -H 'Host: status.m05.local' $ING/api/health > ~/ckad-mocks/exam-05/q14/status.txt
curl -s -H 'Host: status.m05.local' $ING/about      > ~/ckad-mocks/exam-05/q14/default.txt
```

**Verify**

```bash
kubectl -n m05-ingress describe ingress edge | sed -n '/Default backend/,/Annotations/p'
head ~/ckad-mocks/exam-05/q14/*.txt
```

```text
Default backend:  fallback:80 (10.244.2.14:80)
Rules:
  Host              Path  Backends
  ----              ----  --------
  docs.m05.local
                    /     docs:80 (10.244.1.20:80)
  status.m05.local
                    /api  status-api:http (10.244.2.15:80)
Annotations:        <none>
==> /home/you/ckad-mocks/exam-05/q14/default.txt <==
fallback: no route

==> /home/you/ckad-mocks/exam-05/q14/docs.txt <==
docs: ok

==> /home/you/ckad-mocks/exam-05/q14/status.txt <==
status-api: ok
```

> **Exam tip:** `spec.defaultBackend` catches requests that match no path on the Ingress's hosts, and everything when an Ingress has no rules at all. With ingress-nginx, a request whose **Host** matches no rule goes to the controller's own default backend (404), not to your `spec.defaultBackend`. Other controllers differ, so test unmatched paths, as this task does.

**Common mistakes**
- `--rule="status.m05.local/api=..."` without `*`, which gives pathType `Exact`. Then `/api/health` falls through to the default backend.
- Port `80` for `status-api`. The Service port is 8080, so the controller answers 503.
- Leaving out `--class=nginx` / `ingressClassName`. The controller then ignores the Ingress (unless a default IngressClass exists).
- `curl http://status.m05.local/...` without a hosts-file entry. Use `-H 'Host: ...'` against the controller address.

| Item | Points |
|---|---|
| Ingress `edge`, class nginx, docs rule `/` Prefix → docs:80 | 2 |
| status rule `/api` Prefix → status-api by **port name** | 2 |
| `defaultBackend` → fallback:80 | 1 |
| Three response files correct | 2 |

---

## Question 15 — Logs, events and API discovery (5%)

**Approach:** `kubectl logs` with a selector shows only the **last 10 lines per container** unless you pass `--tail` explicitly. `--all-containers` and `--prefix` cover the rest. Events: sort by `.metadata.creationTimestamp`. API discovery: `kubectl api-resources` lists the group/version the cluster serves for each kind.

```bash
kubectl -n m05-logs logs -l app=dispatch --all-containers --prefix --since=5m --tail=-1 \
  > ~/ckad-mocks/exam-05/q15/dispatch.log

kubectl -n m05-logs get events --sort-by=.metadata.creationTimestamp > ~/ckad-mocks/exam-05/q15/events.txt
#   (kubectl events -n m05-logs is a newer alternative that also lists oldest -> newest)

kubectl apply -f ~/ckad-mocks/exam-05/q15/priorityclass.yaml
# error: resource mapping not found ... no matches for kind "PriorityClass" in version "scheduling.k8s.io/v1beta1"
kubectl api-resources | grep -i priorityclass > ~/ckad-mocks/exam-05/q15/api.txt
sed -i 's#^apiVersion: scheduling.k8s.io/v1beta1#apiVersion: scheduling.k8s.io/v1#' ~/ckad-mocks/exam-05/q15/priorityclass.yaml
kubectl apply -f ~/ckad-mocks/exam-05/q15/priorityclass.yaml
```

The fixed file:

```yaml
apiVersion: scheduling.k8s.io/v1      # v1beta1 was removed in v1.22
kind: PriorityClass
metadata:
  name: m05-batch-critical
  labels:
    ckad-mock: exam-05
value: 100000
globalDefault: false
description: "Batch jobs that must not be preempted by best-effort work"
```

**Verify**

```bash
cut -d' ' -f1 ~/ckad-mocks/exam-05/q15/dispatch.log | sort | uniq -c   # 4 sources, far more than 10 lines each
head -3 ~/ckad-mocks/exam-05/q15/events.txt
cat ~/ckad-mocks/exam-05/q15/api.txt
kubectl get priorityclass m05-batch-critical
```

```text
    150 [pod/dispatch-6f7d8c9b5-abcde/router]
    100 [pod/dispatch-6f7d8c9b5-abcde/auditor]
    150 [pod/dispatch-6f7d8c9b5-fghij/router]
    100 [pod/dispatch-6f7d8c9b5-fghij/auditor]
LAST SEEN   TYPE      REASON      OBJECT                          MESSAGE
31m         Normal    Scheduled   pod/dispatch-6f7d8c9b5-abcde   Successfully assigned m05-logs/dispatch-...
31m         Normal    Pulling     pod/dispatch-6f7d8c9b5-abcde   Pulling image "busybox:1.36"
priorityclasses                     pc           scheduling.k8s.io/v1                   false        PriorityClass
NAME                 VALUE    GLOBAL-DEFAULT   AGE
m05-batch-critical   100000   false            20s
```

**Common mistakes**
- Leaving out `--tail=-1`, so a selector gives only 10 lines per container.
- Leaving out `--all-containers`. kubectl then uses the default container (`router`) and prints `Defaulted container ...`.
- `kubectl logs deploy/dispatch`. That reads **one** Pod only.
- Changing more than the apiVersion in the PriorityClass file, or creating the object with `kubectl create priorityclass` instead of from the fixed file.

| Item | Points |
|---|---|
| `dispatch.log`: all containers, all Pods, prefixed, last 5 min, not truncated | 2 |
| `events.txt` sorted by creation time | 1 |
| `api.txt` = the PriorityClass line (`scheduling.k8s.io/v1`) | 1 |
| PriorityClass created from the fixed file | 1 |

---

## Question 16 — A CustomResourceDefinition with validation (4%)

**Approach:** Copy the CRD example from the docs (Tasks → Extend Kubernetes → Custom Resources) and adapt names and schema. `required` belongs to the **object** that owns the fields. Quote the cron string, because an unquoted `*` starts a YAML alias.

```yaml
# q16-crd.yaml — kubectl apply -f q16-crd.yaml
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: maintenancewindows.ops.m05.ckad.io      # must be plural + "." + group
  labels:
    ckad-mock: exam-05
spec:
  group: ops.m05.ckad.io
  scope: Namespaced
  names:
    kind: MaintenanceWindow
    plural: maintenancewindows
    singular: maintenancewindow
    shortNames:
    - mw
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
            required:
            - start
            - durationMinutes
            properties:
              start:
                type: string
              durationMinutes:
                type: integer
                minimum: 15
                maximum: 240
              mode:
                type: string
                enum:
                - drain
                - cordon
---
apiVersion: ops.m05.ckad.io/v1
kind: MaintenanceWindow
metadata:
  name: saturday-night
  namespace: m05-crd
spec:
  start: "0 2 * * 6"
  durationMinutes: 120
  mode: drain
```

```bash
kubectl apply -f q16-crd.yaml
#   if the CR is rejected with "no matches for kind": the CRD was not established yet - apply again, or:
kubectl wait --for condition=established crd/maintenancewindows.ops.m05.ckad.io --timeout=30s
kubectl apply -f ~/ckad-mocks/exam-05/q16/too-long.yaml 2> ~/ckad-mocks/exam-05/q16/rejected.txt
```

**Verify**

```bash
kubectl -n m05-crd get mw
kubectl get crd maintenancewindows.ops.m05.ckad.io -o jsonpath='{.spec.names.shortNames} {.metadata.labels}{"\n"}'
cat ~/ckad-mocks/exam-05/q16/rejected.txt
kubectl explain mw.spec.durationMinutes
```

```text
NAME             AGE
saturday-night   40s
["mw"] {"ckad-mock":"exam-05"}
The MaintenanceWindow "marathon" is invalid: spec.durationMinutes: Invalid value: 480: spec.durationMinutes in body should be less than or equal to 240
GROUP:      ops.m05.ckad.io
KIND:       MaintenanceWindow
VERSION:    v1

FIELD: durationMinutes <integer>
...
```

**Common mistakes**
- `metadata.name` that isn't `<plural>.<group>`. The API rejects the CRD.
- `type: int`. OpenAPI uses `integer`.
- Putting `required: true` on a field (Swagger 2 style). In OpenAPI v3 schemas, `required` is a list on the parent object.
- `start: 0 2 * * 6` without quotes, which fails with a YAML parse error (`*` is an alias indicator).

| Item | Points |
|---|---|
| CRD names, group, version, scope, short name, label | 1.5 |
| Schema: required fields, integer bounds, enum | 1.5 |
| CR `saturday-night` created | 0.5 |
| `rejected.txt` holds the validation error | 0.5 |

---

## Question 17 — Detect and recover a stalled rollout (5%)

**Approach:** `progressDeadlineSeconds` (default 600) only **reports** a stuck rollout: the controller sets the `Progressing` condition to `False` with reason `ProgressDeadlineExceeded`, and `kubectl rollout status` exits non-zero. It never rolls back by itself, so you do that.

```bash
kubectl -n m05-rollout rollout status deployment quotes --timeout=10s   # "Waiting ... 1 out of 3 new replicas have been updated..."
kubectl -n m05-rollout get rs -l app=quotes                             # new RS: 1 Pod, 0 ready
kubectl -n m05-rollout describe pod -l app=quotes | grep -m1 'Readiness probe failed'   # HTTP probe failed with statuscode: 404

kubectl -n m05-rollout patch deployment quotes -p '{"spec":{"progressDeadlineSeconds":30}}'
kubectl -n m05-rollout rollout status deployment quotes                 # error: deployment "quotes" exceeded its progress deadline
kubectl -n m05-rollout get deployment quotes \
  -o jsonpath='{.status.conditions[?(@.type=="Progressing")].reason}{"\n"}' > ~/ckad-mocks/exam-05/q17/condition.txt

kubectl -n m05-rollout rollout history deployment quotes
kubectl -n m05-rollout rollout undo deployment quotes
kubectl -n m05-rollout rollout status deployment quotes
kubectl -n m05-rollout annotate deployment quotes kubernetes.io/change-cause='rollback: readiness /healthz 404' --overwrite
kubectl -n m05-rollout rollout history deployment quotes > ~/ckad-mocks/exam-05/q17/history.txt
```

**Verify**

```bash
cat ~/ckad-mocks/exam-05/q17/condition.txt ~/ckad-mocks/exam-05/q17/history.txt
kubectl -n m05-rollout get deployment quotes \
  -o jsonpath='{.spec.progressDeadlineSeconds} {.status.readyReplicas}/{.spec.replicas} {.spec.template.spec.containers[0].readinessProbe.httpGet.path}{"\n"}'
```

```text
ProgressDeadlineExceeded
deployment.apps/quotes
REVISION  CHANGE-CAUSE
2         v2: release 2.0
3         rollback: readiness /healthz 404

30 3/3 /
```

Revision 1 disappears from the list: `undo` re-uses revision 1's ReplicaSet, which becomes revision 3.

**Common mistakes**
- Fixing the probe path instead of rolling back. The end state looks healthy, but the task asked for a rollback (and a new revision 3 with revision 2's env var would be wrong).
- Setting `progressDeadlineSeconds` inside the Pod template, where it is an unknown field.
- Writing the condition too early. Before the deadline the reason is still `ReplicaSetUpdated`.
- `kubectl annotate` without `--overwrite`. `undo` copied revision 1's change-cause back, so the annotation already exists.
- Using `--record`, which is deprecated.

| Item | Points |
|---|---|
| `progressDeadlineSeconds: 30` (template untouched) | 1 |
| `condition.txt` = `ProgressDeadlineExceeded` | 1 |
| Rolled back: 3/3 ready, probe path `/`, no `RELEASE` env | 1.5 |
| Change-cause set and `history.txt` written | 1.5 |

---

## Question 18 — Least-privilege securityContext, proven from /proc (4%)

**Approach:** `runAsUser`/`runAsGroup`/`runAsNonRoot`/`seccompProfile` can go at Pod level. `allowPrivilegeEscalation`, `readOnlyRootFilesystem` and `capabilities` exist **only** at container level. Capability names have no `CAP_` prefix.

```yaml
# q18.yaml — kubectl apply -f q18.yaml
apiVersion: v1
kind: Pod
metadata:
  name: hardened
  namespace: m05-sec
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
    runAsGroup: 3000
    seccompProfile:
      type: RuntimeDefault
  containers:
  - name: app
    image: busybox:1.36
    command: ["sleep", "3600"]
    securityContext:
      allowPrivilegeEscalation: false
      readOnlyRootFilesystem: true
      capabilities:
        drop: ["ALL"]
        add: ["NET_BIND_SERVICE"]
```

```bash
kubectl apply -f q18.yaml
kubectl -n m05-sec exec hardened -c app -- grep -E '^(Uid|CapEff|CapBnd|NoNewPrivs|Seccomp):' /proc/1/status \
  > ~/ckad-mocks/exam-05/q18/status.txt
```

**Verify**

```bash
cat ~/ckad-mocks/exam-05/q18/status.txt
```

```text
Uid:	1000	1000	1000	1000
CapEff:	0000000000000000
CapBnd:	0000000000000400
NoNewPrivs:	1
Seccomp:	2
```

| Line | Meaning |
|---|---|
| `Uid: 1000 …` | real/effective/saved/fs UID are non-root |
| `CapBnd: …400` | bounding set = bit 10 only = `CAP_NET_BIND_SERVICE` (drop ALL worked) |
| `CapEff: 0…0` | for a non-root process the kernel doesn't keep added capabilities in the effective set without file capabilities |
| `NoNewPrivs: 1` | `allowPrivilegeEscalation: false` |
| `Seccomp: 2` | seccomp filter mode, so the RuntimeDefault profile is active |

**Common mistakes**
- `capabilities` or `allowPrivilegeEscalation` under the Pod-level `securityContext`. The API rejects these as unknown fields.
- `CAP_NET_BIND_SERVICE` with the prefix.
- `runAsNonRoot: true` without `runAsUser` on an image that runs as root (busybox). The kubelet refuses to start it (`CreateContainerConfigError`).
- `grep Seccomp`. That also matches `Seccomp_filters:`; anchor with `^Seccomp:`.

| Item | Points |
|---|---|
| Pod-level runAsNonRoot/runAsUser/runAsGroup/seccomp | 1.5 |
| Container-level APE false, read-only root FS, drop ALL + add NET_BIND_SERVICE | 1.5 |
| `status.txt` with the 5 lines | 1 |

---

## Question 19 — Modify, build and run an image (4%)

**Approach:** With an exec-form `ENTRYPOINT`, `CMD` supplies the default arguments, and anything after the image name in `podman run` replaces `CMD`. `-e` options go **before** the image name.

```dockerfile
# ~/ckad-mocks/exam-05/q19/Dockerfile
FROM busybox:1.36
ENV BUILD_ID=m05-q19
COPY greet.sh /usr/local/bin/greet.sh
USER 65534
ENTRYPOINT ["/bin/sh", "/usr/local/bin/greet.sh"]
CMD ["CKAD"]
```

```bash
cd ~/ckad-mocks/exam-05/q19
podman build -t localhost/m05-greeter:1.1 .
podman run --name m05-greeter -e GREETING=Howdy localhost/m05-greeter:1.1 Kubernetes
podman logs m05-greeter > ~/ckad-mocks/exam-05/q19/run.log
podman image inspect --format '{{.Config.User}}' localhost/m05-greeter:1.1 > ~/ckad-mocks/exam-05/q19/user.txt
# docker: the same commands with "docker" instead of "podman" (docker image inspect --format '{{.Config.User}}' ...)
```

**Verify**

```bash
podman images localhost/m05-greeter
podman ps -a --filter name=m05-greeter --format '{{.Names}} {{.Status}}'
cat ~/ckad-mocks/exam-05/q19/run.log ~/ckad-mocks/exam-05/q19/user.txt
podman run --rm localhost/m05-greeter:1.1          # defaults: CMD = CKAD, no GREETING
```

```text
REPOSITORY              TAG   IMAGE ID      CREATED        SIZE
localhost/m05-greeter   1.1   3c1f0e2a9b7d  2 minutes ago  4.5 MB
m05-greeter Exited (0) 2 minutes ago
Howdy, Kubernetes! (build m05-q19, uid 65534)
65534
Hello, CKAD! (build m05-q19, uid 65534)
```

**Common mistakes**
- `CMD CKAD` (shell form). With an exec-form ENTRYPOINT the arguments become `/bin/sh -c CKAD`, so greet.sh prints `Hello, -c!`.
- `podman run localhost/m05-greeter:1.1 -e GREETING=Howdy Kubernetes`. Everything after the image name is an argument, so the script greets `-e`.
- `--entrypoint` or `sh greet.sh ...` overrides, which the task forbids.
- `USER nobody` instead of `65534`. Kubernetes `runAsNonRoot` can only verify **numeric** users, so prefer UIDs in images.

| Item | Points |
|---|---|
| Dockerfile: base, ENV, CMD exec form, USER 65534, ENTRYPOINT unchanged | 1.5 |
| Image `localhost/m05-greeter:1.1` built | 1 |
| `run.log` = `Howdy, Kubernetes! (build m05-q19, uid 65534)` | 1 |
| `user.txt` = `65534` | 0.5 |

---

## Bonus — Gateway API traffic split (unscored)

Gateway API is not in the CKAD curriculum, so this task sits outside the 100% and outside the coverage matrix. It's here because Gateway API is the recommended successor of Ingress for new designs.

**Approach:** HTTPRoute `backendRefs[].weight` values are relative: 90 and 10 give 90% and 10%. `parentRefs` attaches the route to the Gateway, which only admits routes from its own namespace here (`from: Same`).

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: rates-split
  namespace: m05-gateway
spec:
  parentRefs:
  - name: m05-gateway
  hostnames:
  - rates.m05.local
  rules:
  - backendRefs:
    - name: rates-v1
      port: 80
      weight: 90
    - name: rates-v2
      port: 80
      weight: 10
```

**Verify**

```bash
kubectl -n m05-gateway get httproute rates-split \
  -o jsonpath='{range .spec.rules[0].backendRefs[*]}{.name}={.weight} {end}{"\n"}'
# rates-v1=90 rates-v2=10
kubectl -n m05-gateway get httproute rates-split -o jsonpath='{.status.parents[0].conditions[?(@.type=="Accepted")].status}{"\n"}'
# True only if a Gateway implementation (e.g. cloud-provider-kind) programs m05-gateway
# With an implementation: GW=$(kubectl -n m05-gateway get gateway m05-gateway -o jsonpath='{.status.addresses[0].value}')
#   for i in $(seq 100); do curl -s -H 'Host: rates.m05.local' http://$GW/; done | sort | uniq -c   # ~90 v1 / ~10 v2
```

**Common mistakes:** weights written as `"90%"` (they're integers); leaving out `port` in a Service `backendRef`; a hostname that doesn't match the `Host` header you test with.

---

## Scoring table

| Question | Topic | Weight | Your score |
|---|---|---|---|
| 1 | Canary promotion | 5 | |
| 2 | Indexed Job + ConfigMap | 6 | |
| 3 | Secret from env file | 5 | |
| 4 | Named targetPort | 5 | |
| 5 | OOMKilled | 5 | |
| 6 | Init container + Service DNS | 5 | |
| 7 | Helm pull/install/upgrade/rollback | 5 | |
| 8 | RBAC resourceNames + SA automount | 7 | |
| 9 | Egress NetworkPolicy | 7 | |
| 10 | Startup/liveness/readiness probes | 5 | |
| 11 | PVC persistence | 5 | |
| 12 | Kustomize labels + JSON 6902 | 5 | |
| 13 | LimitRange/quota + admission plugins | 6 | |
| 14 | Multi-host Ingress + default backend | 7 | |
| 15 | Logs, events, api-resources | 5 | |
| 16 | CRD with validation | 4 | |
| 17 | Stalled rollout | 5 | |
| 18 | securityContext + /proc | 4 | |
| 19 | Image modify/build/run | 4 | |
| **Total** | | **100** | |
| Bonus | Gateway API split | — | (not counted) |

Pass mark: **66**. Below 66, find the weakest domain in the table above and use the study map below.

## If you missed it → study

| Missed question(s) | Revise | Where |
|---|---|---|
| 19 | Dockerfile ENTRYPOINT/CMD/USER, podman build/run/inspect | [01 — Application Design and Build](../../01-Application-Design-and-Build/README.md) |
| 2 | Jobs: Indexed completion mode, parallelism, backoffLimit | [01 — Application Design and Build](../../01-Application-Design-and-Build/README.md) |
| 6 | Init containers, shared emptyDir, Service DNS | [01 — Application Design and Build](../../01-Application-Design-and-Build/README.md) · [05 — Services and Networking](../../05-Services-and-Networking/README.md) |
| 11 | PVC, default StorageClass, WaitForFirstConsumer, Recreate | [01 — Application Design and Build](../../01-Application-Design-and-Build/README.md) |
| 1 | Canary by replica ratio | [02 — Application Deployment](../../02-Application-Deployment/README.md) |
| 17 | Rollouts, progressDeadlineSeconds, undo, change-cause | [02 — Application Deployment](../../02-Application-Deployment/README.md) |
| 7 | Helm pull/untar, install from a directory, --reuse-values, rollback | [02 — Application Deployment](../../02-Application-Deployment/README.md) |
| 12 | Kustomize labels/includeSelectors, JSON 6902 patches | [02 — Application Deployment](../../02-Application-Deployment/README.md) |
| 5, 13 | Termination reasons, ReplicaSet events, debugging Pending/absent Pods | [03 — Application Observability and Maintenance](../../03-Application-Observability-and-Maintenance/README.md) |
| 10 | startupProbe sizing, tcpSocket/exec probes | [03 — Application Observability and Maintenance](../../03-Application-Observability-and-Maintenance/README.md) |
| 15 | `kubectl logs -l` flags, events, api-resources, removed APIs | [03 — Application Observability and Maintenance](../../03-Application-Observability-and-Maintenance/README.md) |
| 3 | Secrets from env files, `secretKeyRef`, `items` | [04 — Application Environment, Configuration and Security](../../04-Application-Environment-Configuration-and-Security/README.md) |
| 8 | Roles, resourceNames, subresources, `auth can-i --as`, SA automount | [04 — Application Environment, Configuration and Security](../../04-Application-Environment-Configuration-and-Security/README.md) |
| 13 | LimitRange vs ResourceQuota, admission plugins | [04 — Application Environment, Configuration and Security](../../04-Application-Environment-Configuration-and-Security/README.md) |
| 16 | CRD schema, short names | [04 — Application Environment, Configuration and Security](../../04-Application-Environment-Configuration-and-Security/README.md) |
| 18 | securityContext levels, capabilities, seccomp | [04 — Application Environment, Configuration and Security](../../04-Application-Environment-Configuration-and-Security/README.md) |
| 4 | Service → EndpointSlice → named ports | [05 — Services and Networking](../../05-Services-and-Networking/README.md) |
| 9 | Egress policies, AND vs OR selectors, DNS egress, additive policies | [05 — Services and Networking](../../05-Services-and-Networking/README.md) |
| 14 | Ingress rules, pathType, named ports, defaultBackend | [05 — Services and Networking](../../05-Services-and-Networking/README.md) |
| any jsonpath / speed issue | jsonpath, custom-columns, `$do`, label selectors | [06 — Cross-Cutting Skills and Bonus Topics](../../06-Cross-Cutting-Skills-and-Bonus-Topics/README.md) |
| "why would I do it this way?" | canary/rollback design, RBAC least privilege, probes in production | [08 — Architect Notes](../../08-Architect-Notes/README.md) |
| Bonus (not on the exam) | Gateway API HTTPRoute weights | [06 — Cross-Cutting Skills and Bonus Topics](../../06-Cross-Cutting-Skills-and-Bonus-Topics/README.md) |

## Coverage matrix

All 24 competencies of the official curriculum are exercised. The unscored Gateway API bonus is deliberately left out.

| Domain | Competency | Questions |
|---|---|---|
| Application Design and Build | Define, build and modify container images | 19 |
| | Choose and use the right workload resource (Deployment, DaemonSet, CronJob, etc.) | 2 (Indexed Job), 11 (Deployment + Recreate), 6 (bare Pod with init) |
| | Understand multi-container Pod design patterns (e.g. sidecar, init and others) | 6 (init container), 15 (two-container Pod) |
| | Utilize persistent and ephemeral volumes | 11 (PVC), 6 (emptyDir), 2 & 3 (ConfigMap/Secret volumes) |
| Application Deployment | Use Kubernetes primitives to implement common deployment strategies (e.g. blue/green or canary) | 1 |
| | Understand Deployments and how to perform rolling updates | 17, 4, 10 |
| | Use the Helm package manager to deploy existing packages | 7 |
| | Kustomize | 12 |
| Application Observability and Maintenance | Understand API deprecations | 15 |
| | Implement probes and health checks | 10, 17 |
| | Use built-in CLI tools to monitor Kubernetes applications | 15 (events), 17 (rollout status, conditions), 1 (EndpointSlices) |
| | Utilize container logs | 15, 6 |
| | Debugging in Kubernetes | 5, 4, 13 |
| Application Environment, Configuration and Security | Discover and use resources that extend Kubernetes (CRD, Operators) | 16 |
| | Understand authentication, authorization and admission control | 8 (RBAC), 13 (admission plugins) |
| | Define resource requirements | 5 (memory request/limit), 13 (request sized to fit the quota) |
| | Understand requests, limits, quotas | 13, 5 |
| | Understand ConfigMaps | 2 |
| | Create & consume Secrets | 3 |
| | Understand ServiceAccounts | 8 |
| | Understand Application Security (SecurityContexts, Capabilities, etc.) | 18 |
| Services and Networking | Demonstrate basic understanding of NetworkPolicies | 9 |
| | Provide and troubleshoot access to applications via services | 4, 6, 1 |
| | Use Ingress rules to expose applications | 14 |
