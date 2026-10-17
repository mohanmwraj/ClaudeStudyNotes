# CKAD Mock Exam 01 — Solutions (Foundations)

> Grade only after the 120-minute timer has stopped. For each question, run the **Verify** commands and award the points listed under **Points**. Paths assume the defaults from `setup.sh`. Questions are in [questions.md](questions.md).

## Domain weights in this paper

| Domain | Official weight | Questions | Weight in this paper |
|---|---|---|---|
| Application Design and Build | 20% | Q1, Q2, Q3, Q4 | 21% |
| Application Deployment | 20% | Q5, Q6, Q7, Q8 | 20% |
| Application Observability and Maintenance | 15% | Q9, Q10, Q11 | 14% |
| Application Environment, Configuration and Security | 25% | Q12, Q13, Q14, Q15, Q16 | 25% |
| Services and Networking | 20% | Q17, Q18, Q19 | 20% |
| **Total** | **100%** | **19 questions** | **100%** |

**How to grade:** one point = 1% of the exam. A point counts only when its check passes. Answers that are close but wrong (wrong name, wrong namespace, wrong file content) score 0 for that check, as in the real exam. The pass mark is **66**.

---

## Question 1 — Build and archive a container image (4%)
*Target time: 4 min*

**Approach:** Build from the directory with the exact tag, then `save` the image. docker-archive is podman's default save format; `--format docker-archive` makes it explicit.

```bash
cd ~/ckad-mocks/exam-01/q01
podman build -t m01-webapp:1.0 .            # trailing "." = build context (this directory)
podman save --format docker-archive -o ~/ckad-mocks/exam-01/q01/m01-webapp-1.0.tar m01-webapp:1.0

# docker equivalent
docker build -t m01-webapp:1.0 .
docker save -o ~/ckad-mocks/exam-01/q01/m01-webapp-1.0.tar m01-webapp:1.0
```

**Verify**

```bash
podman images m01-webapp                                          # or: docker images m01-webapp
tar -tf ~/ckad-mocks/exam-01/q01/m01-webapp-1.0.tar | grep -x manifest.json
podman load -i ~/ckad-mocks/exam-01/q01/m01-webapp-1.0.tar        # optional round trip
```

```text
REPOSITORY            TAG    IMAGE ID      CREATED         SIZE
localhost/m01-webapp  1.0    ...           30 seconds ago  ...
manifest.json
Loaded image: localhost/m01-webapp:1.0
```

**Common mistakes**
- `--format oci-archive`. The tarball then contains `index.json` and `oci-layout` but no `manifest.json`, which is the wrong format for this task.
- `podman export`, which exports a *container's* filesystem, not an image.
- Building in the wrong directory, or forgetting the build context `.`.
- On a real exam host you may need `sudo podman ...`. Images built with sudo live in root's storage, so keep using sudo for `save`.

**Points (4)**
- 2: image `m01-webapp:1.0` exists locally.
- 2: `m01-webapp-1.0.tar` exists at the exact path and is a docker-archive (contains `manifest.json`).

---

## Question 2 — Scheduled clean-up job (6%)
*Target time: 6 min*

**Approach:** Generate the CronJob with `kubectl create cronjob`, add the container name and the two history limits, apply it, then trigger it with `kubectl create job --from=cronjob/...`.

```bash
kubectl -n m01-batch create cronjob log-cleaner --image=busybox:1.36 --schedule="*/5 * * * *" \
  --dry-run=client -o yaml -- sh -c 'echo cleaning old logs; date' > q02-cronjob.yaml
vim q02-cronjob.yaml        # container name -> cleaner; add the two history limits
kubectl apply -f q02-cronjob.yaml

kubectl -n m01-batch create job log-cleaner-manual --from=cronjob/log-cleaner
kubectl -n m01-batch wait --for=condition=complete job/log-cleaner-manual --timeout=90s
kubectl -n m01-batch logs job/log-cleaner-manual > ~/ckad-mocks/exam-01/q02/manual.log
```

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: log-cleaner
  namespace: m01-batch
spec:
  schedule: "*/5 * * * *"          # quote it: a value starting with * is a YAML alias otherwise
  successfulJobsHistoryLimit: 2    # CronJob spec level, not jobTemplate
  failedJobsHistoryLimit: 1
  jobTemplate:
    spec:
      template:
        spec:
          restartPolicy: OnFailure # generator default for cronjobs
          containers:
          - name: cleaner
            image: busybox:1.36
            command: ["sh", "-c", "echo cleaning old logs; date"]
```

**Verify**

```bash
kubectl -n m01-batch get cronjob log-cleaner -o jsonpath='{.spec.schedule}|{.spec.successfulJobsHistoryLimit}|{.spec.failedJobsHistoryLimit}|{.spec.jobTemplate.spec.template.spec.containers[0].name}|{.spec.jobTemplate.spec.template.spec.restartPolicy}{"\n"}'
kubectl -n m01-batch get job log-cleaner-manual -o jsonpath='{.metadata.annotations.cronjob\.kubernetes\.io/instantiate}{"\n"}'
cat ~/ckad-mocks/exam-01/q02/manual.log
```

```text
*/5 * * * *|2|1|cleaner|OnFailure
manual
cleaning old logs
Sat Oct 17 09:41:07 UTC 2026
```

**Common mistakes**
- An unquoted schedule in the shell gets glob-expanded. Always quote `"*/5 * * * *"`.
- `--from=log-cleaner` without the `cronjob/` prefix.
- History limits placed under `jobTemplate.spec`, where they are unknown fields.
- Keeping the generated container name (`log-cleaner`) instead of `cleaner`.

**Points (6)**
- 1: CronJob `log-cleaner` with schedule `*/5 * * * *`.
- 1: container `cleaner`, `busybox:1.36`, correct command.
- 1: `restartPolicy: OnFailure`.
- 1: history limits 2 and 1.
- 1: Job `log-cleaner-manual` was created from the CronJob (annotation `cronjob.kubernetes.io/instantiate: manual`) and is Complete.
- 1: `manual.log` contains `cleaning old logs`.

---

## Question 3 — Sidecar log shipper (6%)
*Target time: 7 min*

**Approach:** Generate a one-container Pod, rename the container, add the second container and a shared `emptyDir`. The shipper's mount gets `readOnly: true`.

```bash
kubectl -n m01-sidecar run web-logger --image=busybox:1.36 --dry-run=client -o yaml --command -- \
  sh -c 'while true; do echo "$(date) app heartbeat" >> /var/log/app/app.log; sleep 5; done' > q03-pod.yaml
vim q03-pod.yaml            # rename container to app, add log-shipper + volume
kubectl apply -f q03-pod.yaml
```

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: web-logger
  namespace: m01-sidecar
spec:
  volumes:
  - name: logs
    emptyDir: {}
  containers:
  - name: app
    image: busybox:1.36
    command:
    - sh
    - -c
    - while true; do echo "$(date) app heartbeat" >> /var/log/app/app.log; sleep 5; done
    volumeMounts:
    - name: logs
      mountPath: /var/log/app
  - name: log-shipper
    image: busybox:1.36
    command: ["sh", "-c", "tail -n +1 -F /var/log/app/app.log"]   # -F keeps retrying until the file exists
    volumeMounts:
    - name: logs
      mountPath: /var/log/app
      readOnly: true
```

**Verify**

```bash
kubectl -n m01-sidecar get pod web-logger
kubectl -n m01-sidecar logs web-logger -c log-shipper --tail=2
kubectl -n m01-sidecar get pod web-logger -o jsonpath='{range .spec.containers[*]}{.name}{" readOnly="}{.volumeMounts[0].readOnly}{"\n"}{end}'
```

```text
NAME         READY   STATUS    RESTARTS   AGE
web-logger   2/2     Running   0          40s
Sat Oct 17 09:45:01 UTC 2026 app heartbeat
Sat Oct 17 09:45:06 UTC 2026 app heartbeat
app readOnly=
log-shipper readOnly=true
```

**Common mistakes**
- Different volumes or mount paths in the two containers, so the shipper never sees the file.
- Putting the shipper under `initContainers`. A classic init container must exit, so the Pod would hang in `Init:0/1`. The task asks for two regular containers, not a native sidecar.
- `tail -f` instead of `-F`: if the file doesn't exist yet, busybox `tail -f` exits and the container restarts.

**Points (6)**
- 2: Pod `web-logger` has two regular containers named `app` and `log-shipper`, both Running.
- 2: the shared `emptyDir` volume `logs` is mounted at `/var/log/app` in both containers.
- 1: the shipper's mount is read-only.
- 1: `kubectl logs -c log-shipper` shows heartbeat lines.

---

## Question 4 — Static persistent storage (5%)
*Target time: 7 min*

**Approach:** Start from the docs page *Configure a Pod to Use a PersistentVolume for Storage*. Set `storageClassName: manual` on **both** PV and PVC. Without it on the PVC, the cluster's default StorageClass (`standard` on kind) provisions a new volume and your PV stays `Available`.

```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: m01-pv-data               # cluster-scoped: no namespace
spec:
  capacity:
    storage: 1Gi
  accessModes:
  - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: manual
  hostPath:
    path: /tmp/m01-data
    type: DirectoryOrCreate
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: data-claim
  namespace: m01-storage
spec:
  storageClassName: manual        # must match the PV, otherwise the default StorageClass wins
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 500Mi
---
apiVersion: v1
kind: Pod
metadata:
  name: data-writer
  namespace: m01-storage
spec:
  volumes:
  - name: data
    persistentVolumeClaim:
      claimName: data-claim
  containers:
  - name: writer
    image: busybox:1.36
    command: ["sh", "-c", "echo \"persisted at $(date)\" > /data/out.txt; sleep 3600"]
    volumeMounts:
    - name: data
      mountPath: /data
```

```bash
kubectl apply -f q04.yaml
```

**Verify**

```bash
kubectl get pv m01-pv-data
kubectl -n m01-storage get pvc data-claim
kubectl -n m01-storage exec data-writer -- cat /data/out.txt
```

```text
NAME          CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS   CLAIM                    STORAGECLASS   ...
m01-pv-data   1Gi        RWO            Retain           Bound    m01-storage/data-claim   manual         ...
NAME         STATUS   VOLUME        CAPACITY   ACCESS MODES   STORAGECLASS   ...
data-claim   Bound    m01-pv-data   1Gi        RWO            manual         ...
persisted at Sat Oct 17 09:52:13 UTC 2026
```

The claim reports `1Gi`, the size of the PV it bound to, not the `500Mi` it requested.

**Common mistakes**
- PVC without `storageClassName`, so it is dynamically provisioned and `m01-pv-data` stays `Available`. That scores 0 for the binding check.
- PVC/Pod created in `default` because `-n m01-storage` or `metadata.namespace` was forgotten.
- A PVC that asks for more than 1Gi, or a different access mode, stays `Pending`.

**Points (5)**
- 2: PV `m01-pv-data` with every requested field.
- 2: PVC `data-claim` is `Bound` to `m01-pv-data`.
- 1: Pod `data-writer` is Running and `/data/out.txt` exists.

---

## Question 5 — Rolling update and rollback (6%)
*Target time: 5 min*

**Approach:** `kubectl set image`, then annotate the change-cause. You need `--overwrite`, because setup.sh already set a change-cause for revision 1. Save the history, then `rollout undo`.

```bash
kubectl -n m01-rollout set image deployment/frontend nginx=nginx:1.27
kubectl -n m01-rollout annotate deployment/frontend kubernetes.io/change-cause="bump to nginx:1.27" --overwrite
kubectl -n m01-rollout rollout status deployment/frontend
kubectl -n m01-rollout rollout history deployment/frontend > ~/ckad-mocks/exam-01/q05/history.txt

kubectl -n m01-rollout rollout undo deployment/frontend
kubectl -n m01-rollout rollout status deployment/frontend
```

**Verify**

```bash
cat ~/ckad-mocks/exam-01/q05/history.txt
kubectl -n m01-rollout get deployment frontend -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
kubectl -n m01-rollout rollout history deployment/frontend
```

```text
deployment.apps/frontend
REVISION  CHANGE-CAUSE
1         initial release nginx:1.27-alpine
2         bump to nginx:1.27

nginx:1.27-alpine

deployment.apps/frontend
REVISION  CHANGE-CAUSE
2         bump to nginx:1.27
3         initial release nginx:1.27-alpine
```

The rollback re-uses revision 1's Pod template, which becomes revision 3, so revision 1 disappears from the list.

**Common mistakes**
- `kubectl annotate` without `--overwrite` fails with "already has a value", so revision 2 keeps the old text.
- `--record`: deprecated, and it records the command line rather than your text.
- `set image deployment/frontend frontend=...`: the container is named `nginx`, so this fails with "unable to find container named frontend".
- Rolling back with `--to-revision=2` (the bad release) instead of the previous good one.

**Points (6)**
- 2: rolling update performed, and revision 2 shows `bump to nginx:1.27`.
- 2: `history.txt` contains the revision with `bump to nginx:1.27`.
- 2: after the rollback the image is `nginx:1.27-alpine` and the rollout is complete.

---

## Question 6 — Canary release (6%)
*Target time: 6 min*

**Approach:** Read the Service selector first: it needs **both** `app=checkout` and `tier=frontend`. 8 stable + 2 canary = 10 endpoints, so the canary gets 2/10 = 20%. Add `version: v2` to the selector so it can never match v1 Pods.

```bash
kubectl -n m01-canary get svc checkout -o jsonpath='{.spec.selector}{"\n"}'   # {"app":"checkout","tier":"frontend"}
kubectl -n m01-canary get pods --show-labels | head -3
kubectl -n m01-canary create deployment checkout-v2 --image=httpd:2.4 --replicas=2 --port=80 \
  --dry-run=client -o yaml > q06-canary.yaml
vim q06-canary.yaml         # labels + selector, container name checkout
kubectl apply -f q06-canary.yaml
```

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: checkout-v2
  namespace: m01-canary
  labels:
    app: checkout
    version: v2
spec:
  replicas: 2                 # 8 (v1) : 2 (v2) = 80/20
  selector:
    matchLabels:
      app: checkout
      tier: frontend
      version: v2             # keeps the selector disjoint from checkout-v1
  template:
    metadata:
      labels:
        app: checkout         # app + tier = what the Service selects
        tier: frontend
        version: v2
    spec:
      containers:
      - name: checkout
        image: httpd:2.4
        ports:
        - containerPort: 80
```

**Verify**

```bash
kubectl -n m01-canary get deploy -L version
kubectl -n m01-canary get endpointslices -l kubernetes.io/service-name=checkout \
  -o jsonpath='{range .items[*].endpoints[*]}{.targetRef.name}{"\n"}{end}' | sort | cut -d- -f1-2 | uniq -c
kubectl -n m01-canary run probe --rm -i --restart=Never --image=busybox:1.36 -- sh -c \
  'for i in $(seq 1 50); do if wget -qO- http://checkout | grep -q "It works"; then echo v2; else echo v1; fi; done | sort | uniq -c'
```

```text
NAME          READY   UP-TO-DATE   AVAILABLE   AGE   VERSION
checkout-v1   8/8     8            8           20m   v1
checkout-v2   2/2     2            2           1m    v2
      8 checkout-v1
      2 checkout-v2
     41 v1
      9 v2
```

kube-proxy picks endpoints at random, so the 50-request split only approximates 80/20.

**Common mistakes**
- v2 Pods labelled only `app=checkout`: the Service also requires `tier=frontend`, so they receive no traffic.
- A v2 selector of `app=checkout,tier=frontend` without `version`: it overlaps the v1 Pods, which the task forbids.
- Scaling `checkout-v1` or editing the Service. Both are forbidden.
- 1 replica gives 1/9 ≈ 11%, which is not 20%.

**Points (6)**
- 2: Deployment `checkout-v2` with `httpd:2.4`, container `checkout`, port 80.
- 2: Pod labels include `app=checkout`, `tier=frontend`, `version=v2`, and the selector includes `version=v2`.
- 2: 2 Ready replicas, so the Service has 10 endpoints, and `checkout-v1` and the Service are unchanged.

---

## Question 7 — Install a Helm chart (5%)
*Target time: 5 min*

**Approach:** Use `helm show values` to find the keys (`replicaCount`, `image.tag`, `fullnameOverride`), then run one `helm install` with `--create-namespace`.

```bash
helm show values ~/ckad-mocks/exam-01/q07/shop-chart | grep -nE '^replicaCount|^  tag:|^fullnameOverride'
helm install m01-shop ~/ckad-mocks/exam-01/q07/shop-chart -n m01-helm --create-namespace \
  --set replicaCount=2 --set image.tag=1.27-alpine --set fullnameOverride=shop-web
helm list -A > ~/ckad-mocks/exam-01/q07/releases.txt
```

**Verify**

```bash
helm -n m01-helm get values m01-shop
kubectl -n m01-helm get deploy shop-web -o jsonpath='{.spec.replicas} {.spec.template.spec.containers[0].image}{"\n"}'
kubectl -n m01-helm rollout status deploy/shop-web
grep m01-shop ~/ckad-mocks/exam-01/q07/releases.txt
```

```text
USER-SUPPLIED VALUES:
fullnameOverride: shop-web
image:
  tag: 1.27-alpine
replicaCount: 2
2 nginx:1.27-alpine
deployment "shop-web" successfully rolled out
m01-shop   m01-helm   1   2026-10-17 10:02:11.4 +0000 UTC   deployed   shop-chart-0.1.0   1.16.0
```

**Common mistakes**
- No `--create-namespace`, which fails with `namespaces "m01-helm" not found`.
- `nameOverride=shop-web` gives a Deployment named `m01-shop-shop-web`. Only `fullnameOverride` replaces the whole name.
- `helm list` without `-A`, which shows only the current namespace.
- A typo in a value key changes nothing, and Helm doesn't complain. Always check `helm get values` and the objects that were created.

**Points (5)**
- 2: release `m01-shop` is `deployed` in `m01-helm`, and the install created the namespace.
- 2: Deployment `shop-web` has 2 Ready replicas running `nginx:1.27-alpine`.
- 1: `releases.txt` lists the releases of all namespaces, including `m01-shop`.

---

## Question 8 — Kustomize: add a resource and a common label (3%)
*Target time: 4 min*

**Approach:** Add `service.yaml` to `resources` and use the `labels` field. It leaves selectors alone by default (`includeSelectors: false`), unlike the deprecated `commonLabels`.

**Docs in the exam:** the Kustomize site is not on the allowed list. The allowed page [kubernetes.io › Declarative Management of Kubernetes Objects Using Kustomize](https://kubernetes.io/docs/tasks/manage-kubernetes-objects/kustomization/) lists `labels` in its feature table ("Add labels without automatically injecting corresponding selectors"). Its example sets `includeSelectors: true`, which you must leave out here.

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- deployment.yaml
- service.yaml
labels:
- pairs:
    app.kubernetes.io/part-of: notes-app   # metadata only; selectors and pod templates untouched
```

```bash
kubectl kustomize ~/ckad-mocks/exam-01/q08 > ~/ckad-mocks/exam-01/q08/rendered.yaml
kubectl apply -k ~/ckad-mocks/exam-01/q08
```

**Verify**

```bash
kubectl -n m01-kustomize get deploy,svc -l app.kubernetes.io/part-of=notes-app
kubectl -n m01-kustomize get deploy notes -o jsonpath='{.spec.selector.matchLabels}{"\n"}'
kubectl -n m01-kustomize get svc notes -o jsonpath='{.spec.selector}{"\n"}'
grep -c 'app.kubernetes.io/part-of: notes-app' ~/ckad-mocks/exam-01/q08/rendered.yaml
```

```text
NAME                    READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/notes   1/1     1            1           20s
NAME            TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)   AGE
service/notes   ClusterIP   10.96.120.17   <none>        80/TCP    20s
{"app":"notes"}
{"app":"notes"}
2
```

**Common mistakes**
- `commonLabels:` also rewrites both selectors, which breaks the "no selector change" requirement. On an existing Deployment it fails anyway, because `spec.selector` is immutable.
- Indentation: `pairs` is a map inside a list item (`- pairs:`).
- `kubectl apply -f <dir>` instead of `-k` applies the raw files, without the label and without the kustomization.

**Points (3)**
- 1: the Service is deployed through the kustomization.
- 1: the label is on the metadata of both objects, and the selectors are unchanged.
- 1: `rendered.yaml` was written.

---

## Question 9 — Readiness and liveness probes (5%)
*Target time: 6 min*

**Approach:** `kubectl edit` the Deployment and add two probe blocks under container `api`. The change triggers a rolling update.

```bash
kubectl -n m01-health edit deployment api
```

End state, with only the two probe blocks added:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api
  namespace: m01-health
spec:
  replicas: 2
  selector:
    matchLabels:
      app: api
  template:
    metadata:
      labels:
        app: api
    spec:
      containers:
      - name: api
        image: nginx:1.27-alpine
        ports:
        - containerPort: 80
        readinessProbe:
          httpGet:
            path: /
            port: 80
          initialDelaySeconds: 5
          periodSeconds: 10
        livenessProbe:
          exec:
            command: ["cat", "/usr/share/nginx/html/index.html"]   # argv list, not one string
          initialDelaySeconds: 10
          periodSeconds: 15
          failureThreshold: 3
```

**Verify**

```bash
kubectl -n m01-health rollout status deployment/api
kubectl -n m01-health get deploy api -o jsonpath='{.spec.template.spec.containers[0].readinessProbe}{"\n"}{.spec.template.spec.containers[0].livenessProbe}{"\n"}'
kubectl -n m01-health get pods -l app=api
```

```text
deployment "api" successfully rolled out
{"failureThreshold":3,"httpGet":{"path":"/","port":80,"scheme":"HTTP"},"initialDelaySeconds":5,"periodSeconds":10,"successThreshold":1,"timeoutSeconds":1}
{"exec":{"command":["cat","/usr/share/nginx/html/index.html"]},"failureThreshold":3,"initialDelaySeconds":10,"periodSeconds":15,"successThreshold":1,"timeoutSeconds":1}
NAME                   READY   STATUS    RESTARTS   AGE
api-6d8f7c9b5d-4kq2m   1/1     Running   0          30s
api-6d8f7c9b5d-x7wzt   1/1     Running   0          20s
```

**Common mistakes**
- Probes indented at Pod level or under `spec` of the Deployment. They belong to the container.
- `command: ["cat /usr/share/nginx/html/index.html"]` as one string. It is executed as a single binary name, fails, and the Pod restarts forever.
- Editing a Pod instead of the Deployment, or changing other fields while editing.

**Points (5)**
- 2: readiness probe with the correct handler and timings.
- 2: liveness probe with the correct handler and timings.
- 1: rollout complete, both replicas Ready, nothing else changed.

---

## Question 10 — Migrate a deprecated manifest (4%)
*Target time: 4 min*

**Approach:** The error message names the problem. `kubectl api-resources` shows the served group/version. `apps/v1` additionally **requires** `spec.selector`, and it must match the template labels.

```bash
kubectl apply -f ~/ckad-mocks/exam-01/q10/legacy-deploy.yaml
# error: resource mapping not found ... no matches for kind "Deployment" in version "extensions/v1beta1"
kubectl api-resources | grep -w deployments
# deployments   deploy   apps/v1   true   Deployment
echo "apps/v1" > ~/ckad-mocks/exam-01/q10/api-version.txt
vim ~/ckad-mocks/exam-01/q10/legacy-deploy.yaml     # apiVersion + spec.selector
kubectl apply -f ~/ckad-mocks/exam-01/q10/legacy-deploy.yaml
```

The original lines that matter:

```text
apiVersion: extensions/v1beta1     <- removed in v1.16
spec:
  replicas: 2
  template:                        <- no spec.selector: required in apps/v1
```

The fixed file:

```yaml
# Written for Kubernetes 1.15. It does not apply on current clusters.
apiVersion: apps/v1
kind: Deployment
metadata:
  name: legacy-app
  namespace: m01-legacy
  labels:
    app: legacy-app
spec:
  replicas: 2
  selector:
    matchLabels:
      app: legacy-app        # must equal the template labels
  template:
    metadata:
      labels:
        app: legacy-app
    spec:
      containers:
      - name: legacy-app
        image: nginx:1.27-alpine
        ports:
        - containerPort: 80
```

**Verify**

```bash
cat ~/ckad-mocks/exam-01/q10/api-version.txt
kubectl -n m01-legacy get deploy legacy-app
grep -E 'apiVersion|matchLabels' -A1 ~/ckad-mocks/exam-01/q10/legacy-deploy.yaml
```

```text
apps/v1
NAME         READY   UP-TO-DATE   AVAILABLE   AGE
legacy-app   2/2     2            2           15s
```

**Common mistakes**
- Changing only `apiVersion`, which is rejected with `spec.selector: Required value`.
- A selector that doesn't match the template labels: `selector does not match template labels`.
- Fixing a copy instead of the file in place. Note also that `kubectl convert` is a separate plugin, not installed on exam hosts by default.

**Points (4)**
- 1: `api-version.txt` contains `apps/v1`.
- 2: the file is fixed in place (`apps/v1` plus a matching selector), with everything else unchanged.
- 1: Deployment `legacy-app` is 2/2 Ready.

---

## Question 11 — Resource usage and container logs (5%)
*Target time: 4 min*

**Approach:** `kubectl top pod --sort-by=cpu` (needs metrics-server), `kubectl logs -c` for exactly one container, and `grep -c` for the count.

```bash
kubectl -n m01-monitor top pod --sort-by=cpu
kubectl -n m01-monitor top pod --sort-by=cpu --no-headers | head -1 | awk '{print $1}' > ~/ckad-mocks/exam-01/q11/top-cpu.txt
kubectl -n m01-monitor logs payment -c audit > ~/ckad-mocks/exam-01/q11/audit.log
grep -c DENIED ~/ckad-mocks/exam-01/q11/audit.log > ~/ckad-mocks/exam-01/q11/denied-count.txt
```

**Verify**

```bash
cat ~/ckad-mocks/exam-01/q11/top-cpu.txt ~/ckad-mocks/exam-01/q11/denied-count.txt
head -2 ~/ckad-mocks/exam-01/q11/audit.log
```

```text
NAME       CPU(cores)   MEMORY(bytes)
worker-b   250m         0Mi
worker-c   80m          0Mi
payment    1m           1Mi
worker-a   1m           0Mi

worker-b
3
AUDIT txn=1001 user=alice result=APPROVED
AUDIT txn=1002 user=bob   result=DENIED reason=limit
```

**Common mistakes**
- `kubectl logs payment` without `-c`. kubectl prints `Defaulted container "app"` and you capture the wrong container, whose log also contains one `DENIED`, so the count comes out as 1.
- Writing the whole `top` table instead of only the name.
- Running `kubectl top` seconds after setup gives "metrics not available yet". Wait about 60 s.

**Points (5)**
- 2: `top-cpu.txt` contains `worker-b`.
- 2: `audit.log` holds the `audit` container's log only.
- 1: `denied-count.txt` contains `3`.

---

## Question 12 — ConfigMap and Secret for an application (7%)
*Target time: 8 min*

**Approach:** Two imperative `create` commands, then a generated Pod manifest. Add `valueFrom` env vars and a `configMap` volume to it.

```bash
kubectl -n m01-config create configmap shop-config --from-literal=APP_COLOR=blue \
  --from-file=$HOME/ckad-mocks/exam-01/q12/app.properties      # key = file name: app.properties
kubectl -n m01-config create secret generic shop-db --from-literal=password='S3cure-Pa55'
kubectl -n m01-config run shop --image=nginx:1.27-alpine --dry-run=client -o yaml > q12-pod.yaml
vim q12-pod.yaml
kubectl apply -f q12-pod.yaml
```

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: shop
  namespace: m01-config
spec:
  containers:
  - name: shop
    image: nginx:1.27-alpine
    env:
    - name: APP_COLOR
      valueFrom:
        configMapKeyRef:
          name: shop-config
          key: APP_COLOR
    - name: DB_PASSWORD            # env var name differs from the Secret key
      valueFrom:
        secretKeyRef:
          name: shop-db
          key: password
    volumeMounts:
    - name: config
      mountPath: /etc/shop
      readOnly: true
  volumes:
  - name: config
    configMap:
      name: shop-config
```

**Verify**

```bash
kubectl -n m01-config get pod shop
kubectl -n m01-config exec shop -- printenv APP_COLOR DB_PASSWORD
kubectl -n m01-config exec shop -- cat /etc/shop/app.properties
```

```text
NAME   READY   STATUS    RESTARTS   AGE
shop   1/1     Running   0          20s
blue
S3cure-Pa55
shop.currency=EUR
shop.max-cart-items=25
shop.payment.provider=sandbox
```

**Common mistakes**
- `--from-file=~/ckad-mocks/...`. Bash doesn't expand `~` after `--from-file=`, so use `$HOME/...` or a relative path.
- `--from-env-file` creates one key per line instead of a single `app.properties` key.
- `envFrom` with the Secret produces a variable called `password`, not `DB_PASSWORD`.
- Creating the Pod before the ConfigMap/Secret. It sits in `CreateContainerConfigError` until they exist.

**Points (7)**
- 2: ConfigMap `shop-config` with keys `APP_COLOR` and `app.properties`.
- 1: Secret `shop-db` with key `password`.
- 1: `APP_COLOR` env var via `configMapKeyRef`.
- 2: `DB_PASSWORD` env var via `secretKeyRef`.
- 1: ConfigMap volume at `/etc/shop`, and the Pod is Running.

---

## Question 13 — RBAC for a ServiceAccount (6%)
*Target time: 5 min*

**Approach:** Three imperative creates, then `auth can-i` with `--as=system:serviceaccount:<ns>:<sa>`.

```bash
kubectl -n m01-rbac create serviceaccount pod-reader-sa
kubectl -n m01-rbac create role pod-reader --verb=get,list,watch --resource=pods
kubectl -n m01-rbac create rolebinding pod-reader-binding --role=pod-reader --serviceaccount=m01-rbac:pod-reader-sa
kubectl -n m01-rbac auth can-i list pods   --as=system:serviceaccount:m01-rbac:pod-reader-sa > ~/ckad-mocks/exam-01/q13/can-list.txt
kubectl -n m01-rbac auth can-i delete pods --as=system:serviceaccount:m01-rbac:pod-reader-sa > ~/ckad-mocks/exam-01/q13/can-delete.txt
```

`auth can-i` exits with code 1 when the answer is `no`, but it still writes `no` to the file.

Declarative equivalent:

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: pod-reader-sa
  namespace: m01-rbac
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: pod-reader
  namespace: m01-rbac
rules:
- apiGroups: [""]               # "" = core API group (pods)
  resources: ["pods"]
  verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: pod-reader-binding
  namespace: m01-rbac
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: pod-reader
subjects:
- kind: ServiceAccount
  name: pod-reader-sa
  namespace: m01-rbac
```

**Verify**

```bash
cat ~/ckad-mocks/exam-01/q13/can-list.txt ~/ckad-mocks/exam-01/q13/can-delete.txt
kubectl -n m01-rbac get role pod-reader -o jsonpath='{.rules}{"\n"}'
kubectl auth can-i list pods -n default --as=system:serviceaccount:m01-rbac:pod-reader-sa   # no: a Role is namespaced
```

```text
yes
no
[{"apiGroups":[""],"resources":["pods"],"verbs":["get","list","watch"]}]
no
```

**Common mistakes**
- `--serviceaccount=pod-reader-sa` without the `namespace:` prefix, which is rejected.
- `--as=pod-reader-sa` impersonates a *user* of that name, and the answer is always `no`.
- Forgetting `-n m01-rbac` on `can-i`, which checks `default` and answers `no`.

**Points (6)**
- 1: ServiceAccount `pod-reader-sa` exists.
- 2: Role `pod-reader` with exactly get/list/watch on pods.
- 1: RoleBinding `pod-reader-binding` binds the Role to the ServiceAccount.
- 1: `can-list.txt` contains `yes`.
- 1: `can-delete.txt` contains `no`.

---

## Question 14 — Security context (4%)
*Target time: 5 min*

**Approach:** User, group and fsGroup go in the **Pod-level** `securityContext`. `allowPrivilegeEscalation` and `capabilities` exist only at **container** level.

```bash
kubectl -n m01-secure run secure-app --image=busybox:1.36 --dry-run=client -o yaml --command -- sh -c 'sleep 3600' > q14-pod.yaml
vim q14-pod.yaml            # container name app, security contexts, volume
kubectl apply -f q14-pod.yaml
```

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: secure-app
  namespace: m01-secure
spec:
  securityContext:              # Pod level
    runAsUser: 1000
    runAsGroup: 3000
    fsGroup: 2000               # volumes are group-owned by 2000
  volumes:
  - name: data
    emptyDir: {}
  containers:
  - name: app
    image: busybox:1.36
    command: ["sh", "-c", "sleep 3600"]
    volumeMounts:
    - name: data
      mountPath: /data
    securityContext:            # container level
      allowPrivilegeEscalation: false
      capabilities:
        add: ["NET_ADMIN", "SYS_TIME"]   # no CAP_ prefix
```

**Verify**

```bash
kubectl -n m01-secure exec secure-app -- id
kubectl -n m01-secure exec secure-app -- ls -ld /data
kubectl -n m01-secure get pod secure-app -o jsonpath='{.spec.securityContext}{"\n"}{.spec.containers[0].securityContext}{"\n"}'
```

```text
uid=1000 gid=3000 groups=2000,3000
drwxrwsrwx    2 root     2000          4096 Oct 17 10:20 /data
{"fsGroup":2000,"runAsGroup":3000,"runAsUser":1000}
{"allowPrivilegeEscalation":false,"capabilities":{"add":["NET_ADMIN","SYS_TIME"]}}
```

The exact `groups=` list depends on the container runtime, but it must include 2000. For a non-root user, added capabilities land in the bounding set but not the effective set (`grep Cap /proc/1/status`). The task, like the exam, checks the spec.

**Common mistakes**
- `fsGroup` under the container `securityContext`. Strict field validation rejects the unknown field.
- `capabilities` at Pod level, which is also an unknown field.
- `CAP_NET_ADMIN` instead of `NET_ADMIN`.

**Points (4)**
- 2: Pod-level runAsUser 1000, runAsGroup 3000 and fsGroup 2000.
- 1: container-level `allowPrivilegeEscalation: false` plus the added `NET_ADMIN` and `SYS_TIME`.
- 1: emptyDir `data` mounted at `/data`, and the Pod is Running.

---

## Question 15 — Quota troubleshooting (5%)
*Target time: 6 min*

**Approach:** No Pods exist, so look one level up, at the ReplicaSet events or the Deployment's `ReplicaFailure` condition. Admission rejects the Pods because the ResourceQuota requires requests and limits. Fix the template with `kubectl set resources`.

```bash
kubectl -n m01-quota get deploy,rs,pods
kubectl -n m01-quota get events --field-selector reason=FailedCreate | tail -1
# ... pods "reporting-7c9d8f6b5-x" is forbidden: failed quota: team-quota: must specify limits.cpu for: reporter;
#     limits.memory for: reporter; requests.cpu for: reporter; requests.memory for: reporter
echo team-quota > ~/ckad-mocks/exam-01/q15/blocker.txt
kubectl -n m01-quota set resources deployment/reporting -c reporter \
  --requests=cpu=250m,memory=256Mi --limits=cpu=500m,memory=512Mi
kubectl -n m01-quota rollout status deployment/reporting
```

Resulting container section, shown as the full object:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: reporting
  namespace: m01-quota
spec:
  replicas: 2
  selector:
    matchLabels:
      app: reporting
  template:
    metadata:
      labels:
        app: reporting
    spec:
      terminationGracePeriodSeconds: 2
      containers:
      - name: reporter
        image: busybox:1.36
        command: ["sh", "-c", "while true; do echo generating report; sleep 30; done"]
        resources:
          requests:
            cpu: 250m
            memory: 256Mi        # Mi, never m, for memory
          limits:
            cpu: 500m
            memory: 512Mi
```

**Verify**

```bash
cat ~/ckad-mocks/exam-01/q15/blocker.txt
kubectl -n m01-quota get deploy reporting
kubectl -n m01-quota describe resourcequota team-quota
```

```text
team-quota
NAME        READY   UP-TO-DATE   AVAILABLE   AGE
reporting   2/2     2            2           25m
Name:            team-quota
Namespace:       m01-quota
Resource         Used   Hard
--------         ----   ----
limits.cpu       1      2
limits.memory    1Gi    2Gi
requests.cpu     500m   1
requests.memory  512Mi  1Gi
```

**Common mistakes**
- Looking only at Pods. There are none, and the error lives on the ReplicaSet, in its events.
- Editing or deleting the quota, which the task forbids.
- `256m` as a memory value means 0.256 bytes. Use `Mi`.
- Values too large for 2 replicas: requests are summed across Pods, so 2 × 250m = 500m ≤ 1 CPU.

**Points (5)**
- 1: `blocker.txt` contains `team-quota`.
- 2: requests and limits on container `reporter` exactly as specified.
- 2: `reporting` is 2/2 Ready, and the quota is unchanged.

---

## Question 16 — Use a custom resource (3%)
*Target time: 3 min*

**Approach:** Find the served version and fields (`kubectl api-resources`, `kubectl explain`), then apply a small manifest.

```bash
kubectl api-resources --api-group=m01.example.com
# NAME      SHORTNAMES   APIVERSION           NAMESPACED   KIND
# backups   bkp          m01.example.com/v1   true         Backup
kubectl explain backup.spec
kubectl apply -f - <<'EOF'
apiVersion: m01.example.com/v1
kind: Backup
metadata:
  name: nightly-db
  namespace: m01-crd
spec:
  schedule: "0 2 * * *"
  retentionDays: 7          # integer per the CRD schema, so no quotes
  target: postgres-main
EOF
```

**Verify**

```bash
kubectl -n m01-crd get backups
kubectl -n m01-crd get bkp nightly-db -o jsonpath='{.spec}{"\n"}'
```

```text
NAME         SCHEDULE    RETENTION   TARGET          AGE
nightly-db   0 2 * * *   7           postgres-main   10s
{"retentionDays":7,"schedule":"0 2 * * *","target":"postgres-main"}
```

**Common mistakes**
- `retentionDays: "7"` (a string) is rejected by the CRD's schema validation (`must be of type integer`).
- `apiVersion: m01.example.com` without the version.
- Creating it outside `m01-crd`. The resource is namespaced.

**Points (3)**
- 1: Backup `nightly-db` exists in `m01-crd` with the correct apiVersion and kind.
- 2: all three spec values correct (`retentionDays` stored as an integer).

---

## Question 17 — Expose an application with Services (6%)
*Target time: 5 min*

**Approach:** `kubectl expose deployment` copies the Deployment's selector (`app=catalog,tier=api`). That excludes the `catalog-admin` Pod, which also carries `app=catalog`.

```bash
kubectl -n m01-svc get deploy catalog -o jsonpath='{.spec.selector.matchLabels}{"\n"}'    # {"app":"catalog","tier":"api"}
kubectl -n m01-svc expose deployment catalog --name=catalog-svc --port=8080 --target-port=80
kubectl -n m01-svc expose deployment catalog --name=catalog-nodeport --type=NodePort --port=80 --target-port=80
kubectl -n m01-svc get svc catalog-nodeport -o jsonpath='{.spec.ports[0].nodePort}' > ~/ckad-mocks/exam-01/q17/nodeport.txt
```

Equivalent manifests:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: catalog-svc
  namespace: m01-svc
spec:
  type: ClusterIP
  selector:
    app: catalog
    tier: api                  # without tier the catalog-admin Pod is selected too
  ports:
  - port: 8080
    targetPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: catalog-nodeport
  namespace: m01-svc
spec:
  type: NodePort
  selector:
    app: catalog
    tier: api
  ports:
  - port: 80
    targetPort: 80             # nodePort omitted: allocated from 30000-32767
```

**Verify**

```bash
kubectl -n m01-svc get svc
kubectl -n m01-svc get endpointslices -l kubernetes.io/service-name=catalog-svc \
  -o jsonpath='{range .items[*].endpoints[*]}{.targetRef.name}{"\n"}{end}'
kubectl -n m01-svc run tmp --rm -i --restart=Never --image=busybox:1.36 -- wget -qO- -T 3 http://catalog-svc:8080 | grep '<title>'
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
kubectl -n m01-svc run tmp2 --rm -i --restart=Never --image=busybox:1.36 -- \
  wget -qO- -T 3 "http://${NODE_IP}:$(cat ~/ckad-mocks/exam-01/q17/nodeport.txt)" | grep '<title>'
```

```text
NAME               TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)        AGE
catalog-nodeport   NodePort    10.96.44.10    <none>        80:31742/TCP   1m
catalog-svc        ClusterIP   10.96.201.3    <none>        8080/TCP       1m
catalog-7b9c6d5f8-2xkqp
catalog-7b9c6d5f8-v8m4n
<title>Welcome to nginx!</title>
<title>Welcome to nginx!</title>
```

**Common mistakes**
- `kubectl create service clusterip catalog-svc --tcp=8080:80` sets the selector `app=catalog-svc`, so the Service gets no endpoints.
- A hand-written selector `app: catalog` only also matches the `catalog-admin` (httpd) Pod, so responses alternate with "It works!".
- `--port` and `--target-port` swapped.

**Points (6)**
- 3: `catalog-svc` is ClusterIP, 8080 → 80, and its endpoints are exactly the 2 `catalog` Pods.
- 2: `catalog-nodeport` is NodePort, 80 → 80, with the same selector.
- 1: `nodeport.txt` matches the allocated port.

---

## Question 18 — Path-based Ingress (7%)
*Target time: 6 min*

**Approach:** `kubectl create ingress`. A trailing `*` in the path means `pathType: Prefix`; without it you get `Exact`.

```bash
kubectl -n m01-ingress create ingress shop-ingress --class=nginx \
  --rule="shop.m01.local/*=web-svc:80" \
  --rule="shop.m01.local/api*=api-svc:8080" \
  --dry-run=client -o yaml > q18-ingress.yaml
kubectl apply -f q18-ingress.yaml
```

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: shop-ingress
  namespace: m01-ingress
spec:
  ingressClassName: nginx
  rules:
  - host: shop.m01.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: web-svc
            port:
              number: 80
      - path: /api               # Prefix matches /api, /api/, /api/orders (not /apis)
        pathType: Prefix
        backend:
          service:
            name: api-svc
            port:
              number: 8080
```

**Verify**

```bash
kubectl -n m01-ingress get ingress shop-ingress
# kind lab (host port 8080 -> ingress controller):
curl -s -H 'Host: shop.m01.local' http://localhost:8080/
curl -s -H 'Host: shop.m01.local' http://localhost:8080/api/orders
# minikube: curl -s -H 'Host: shop.m01.local' http://$(minikube ip)/api/orders
# any lab, from inside the cluster:
kubectl -n m01-ingress run tmp --rm -i --restart=Never --image=busybox:1.36 -- \
  wget -qO- --header 'Host: shop.m01.local' http://ingress-nginx-controller.ingress-nginx.svc/api/orders
```

```text
NAME           CLASS   HOSTS            ADDRESS     PORTS   AGE
shop-ingress   nginx   shop.m01.local   localhost   80      1m
storefront: /
orders-api: /api/orders
orders-api: /api/orders
```

**Common mistakes**
- `--rule="shop.m01.local/api=api-svc:8080"` without `*` produces `Exact`, so `/api/orders` lands on `web-svc`.
- No `ingressClassName`: no controller picks the Ingress up unless a default IngressClass exists.
- Backend port `80` for `api-svc`. The Service port is 8080; 80 is only its targetPort.
- Testing without the `Host` header gets a 404 from the controller's default backend.

**Points (7)**
- 2: Ingress `shop-ingress` with class `nginx` and host `shop.m01.local`.
- 2: `/api` (Prefix) routes to `api-svc:8080`.
- 2: `/` (Prefix) routes to `web-svc:80`.
- 1: routing works end-to-end (curl/wget).

---

## Question 19 — Restrict access with a NetworkPolicy (7%)
*Target time: 6 min*

**Approach:** Select the backend Pods and use policyType `Ingress` only. Allow one `from` entry with a bare `podSelector`, which matches the policy's own namespace only, and add the port.

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: backend-allow-frontend
  namespace: m01-netpol
spec:
  podSelector:
    matchLabels:
      app: backend
  policyTypes:
  - Ingress                     # egress stays unrestricted
  ingress:
  - from:
    - podSelector:              # no namespaceSelector = same namespace only
        matchLabels:
          app: frontend
    ports:
    - protocol: TCP
      port: 80
```

```bash
kubectl apply -f q19-netpol.yaml
```

**Verify**

```bash
kubectl -n m01-netpol exec frontend -- wget -qO- -T 3 http://backend | grep '<title>'
kubectl -n m01-netpol exec other -- wget -qO- -T 3 http://backend
kubectl -n m01-netpol-ext exec frontend -- wget -qO- -T 3 http://backend.m01-netpol
```

```text
<title>Welcome to nginx!</title>
wget: download timed out
command terminated with exit code 1
wget: download timed out
command terminated with exit code 1
```

**Common mistakes**
- Adding `namespaceSelector: {}`, which admits `app=frontend` Pods from every namespace (the trap Pod in `m01-netpol-ext`).
- `policyTypes: [Ingress, Egress]` with no egress rules cuts the backend's outgoing traffic, which the task says must stay open.
- `from` written as two list items (`- podSelector` and `- namespaceSelector`), which ORs them and opens far more than intended.
- A lab whose CNI doesn't enforce NetworkPolicy. The policy is accepted, but traffic still flows (see setup.sh's warning).

**Points (7)**
- 2: policy selects `app=backend` with policyTypes `Ingress` only.
- 2: the `from` is `podSelector app=frontend`, same namespace only.
- 1: TCP port 80.
- 2: `frontend` is allowed, while `other` and the `frontend` Pod in `m01-netpol-ext` are blocked.

---

## Scoring table

| Q | Task | Domain | Weight | Your score |
|---|---|---|---|---|
| 1 | Build and archive an image | Design & Build | 4 | |
| 2 | CronJob + manual Job | Design & Build | 6 | |
| 3 | Sidecar log shipper | Design & Build | 6 | |
| 4 | PV + PVC + Pod | Design & Build | 5 | |
| 5 | Rolling update + rollback | Deployment | 6 | |
| 6 | Canary 80/20 | Deployment | 6 | |
| 7 | Helm install with values | Deployment | 5 | |
| 8 | Kustomize resources + labels | Deployment | 3 | |
| 9 | Readiness + liveness probes | Observability | 5 | |
| 10 | Deprecated Deployment manifest | Observability | 4 | |
| 11 | `kubectl top` + container logs | Observability | 5 | |
| 12 | ConfigMap + Secret consumption | Env/Config/Security | 7 | |
| 13 | SA + Role + RoleBinding + can-i | Env/Config/Security | 6 | |
| 14 | securityContext + capabilities | Env/Config/Security | 4 | |
| 15 | Quota troubleshooting | Env/Config/Security | 5 | |
| 16 | Custom resource instance | Env/Config/Security | 3 | |
| 17 | ClusterIP + NodePort Services | Services & Networking | 6 | |
| 18 | Path-based Ingress | Services & Networking | 7 | |
| 19 | NetworkPolicy frontend → backend | Services & Networking | 7 | |
| | **Total** (pass mark 66) | | **100** | |

## If you missed it → study

| Missed | Topic to revise | Chapter |
|---|---|---|
| Q1 | podman/docker build, tag, save formats | [01 — Application Design and Build](../../01-Application-Design-and-Build/README.md) |
| Q2 | CronJob fields, Jobs from CronJobs | [01 — Application Design and Build](../../01-Application-Design-and-Build/README.md) |
| Q3 | Multi-container Pods, shared emptyDir | [01 — Application Design and Build](../../01-Application-Design-and-Build/README.md) |
| Q4 | PV/PVC binding, storageClassName | [01 — Application Design and Build](../../01-Application-Design-and-Build/README.md) |
| Q5 | Rolling updates, change-cause, rollout undo | [02 — Application Deployment](../../02-Application-Deployment/README.md) |
| Q6 | Canary with labels and replica ratios | [02 — Application Deployment](../../02-Application-Deployment/README.md) |
| Q7 | `helm show values`, `helm install --set`, `--create-namespace` | [02 — Application Deployment](../../02-Application-Deployment/README.md) |
| Q8 | Kustomize `resources` and `labels` | [02 — Application Deployment](../../02-Application-Deployment/README.md) |
| Q9 | Probe handlers and timing fields | [03 — Application Observability and Maintenance](../../03-Application-Observability-and-Maintenance/README.md) |
| Q10 | Removed APIs, apps/v1 selector rule | [03 — Application Observability and Maintenance](../../03-Application-Observability-and-Maintenance/README.md) |
| Q11 | `kubectl top`, `kubectl logs -c` | [03 — Application Observability and Maintenance](../../03-Application-Observability-and-Maintenance/README.md) |
| Q12 | ConfigMaps and Secrets as env vars and volumes | [04 — Application Environment, Configuration and Security](../../04-Application-Environment-Configuration-and-Security/README.md) |
| Q13 | RBAC, ServiceAccounts, `auth can-i --as` | [04 — Application Environment, Configuration and Security](../../04-Application-Environment-Configuration-and-Security/README.md) |
| Q14 | securityContext levels, capabilities | [04 — Application Environment, Configuration and Security](../../04-Application-Environment-Configuration-and-Security/README.md) |
| Q15 | ResourceQuota, requests/limits, finding FailedCreate events | [04 — Application Environment, Configuration and Security](../../04-Application-Environment-Configuration-and-Security/README.md) · [03 — Observability](../../03-Application-Observability-and-Maintenance/README.md) |
| Q16 | CRDs: discovery and custom resources | [04 — Application Environment, Configuration and Security](../../04-Application-Environment-Configuration-and-Security/README.md) |
| Q17 | Service types, selectors, ports | [05 — Services and Networking](../../05-Services-and-Networking/README.md) |
| Q18 | Ingress rules, pathType | [05 — Services and Networking](../../05-Services-and-Networking/README.md) |
| Q19 | NetworkPolicy selectors | [05 — Services and Networking](../../05-Services-and-Networking/README.md) |
| Ran out of time | Imperative commands, jsonpath, vim speed | [06 — Cross-Cutting Skills](../../06-Cross-Cutting-Skills-and-Bonus-Topics/README.md) · [00 — Exam strategy](../../00-Exam-Overview-and-Setup/README.md) |

## Coverage matrix

| Domain | Competency (official wording) | Questions |
|---|---|---|
| Design & Build | Define, build and modify container images | Q1 |
| Design & Build | Choose and use the right workload resource (Deployment, DaemonSet, CronJob, etc.) | Q2, Q4, Q10 |
| Design & Build | Understand multi-container Pod design patterns (e.g. sidecar, init and others) | Q3, Q11 |
| Design & Build | Utilize persistent and ephemeral volumes | Q4 (PV/PVC), Q3 and Q14 (emptyDir), Q12 (configMap volume) |
| Deployment | Use Kubernetes primitives to implement common deployment strategies (e.g. blue/green or canary) | Q6 |
| Deployment | Understand Deployments and how to perform rolling updates | Q5, Q9 |
| Deployment | Use the Helm package manager to deploy existing packages | Q7 |
| Deployment | Kustomize | Q8 |
| Observability | Understand API deprecations | Q10 |
| Observability | Implement probes and health checks | Q9 |
| Observability | Use built-in CLI tools to monitor Kubernetes applications | Q11 (`top`), Q5 (`rollout status/history`), Q15 (events) |
| Observability | Utilize container logs | Q11, Q2, Q3 |
| Observability | Debugging in Kubernetes | Q15, Q10 |
| Env/Config/Security | Discover and use resources that extend Kubernetes (CRD, Operators) | Q16 |
| Env/Config/Security | Understand authentication, authorization and admission control | Q13 (RBAC, impersonation), Q15 (ResourceQuota admission) |
| Env/Config/Security | Understand requests, limits, quotas | Q15 (ResourceQuota admission), Q11 (CPU limits cap the usage you see in `top`) |
| Env/Config/Security | Define resource requirements | Q15 (requests and limits on container `reporter`) |
| Env/Config/Security | Understand ConfigMaps | Q12, Q18 |
| Env/Config/Security | Create & consume Secrets | Q12 |
| Env/Config/Security | Understand ServiceAccounts | Q13 |
| Env/Config/Security | Understand Application Security (SecurityContexts, Capabilities, etc.) | Q14 |
| Services & Networking | Demonstrate basic understanding of NetworkPolicies | Q19 |
| Services & Networking | Provide and troubleshoot access to applications via services | Q17, Q6 |
| Services & Networking | Use Ingress rules to expose applications | Q18 |
