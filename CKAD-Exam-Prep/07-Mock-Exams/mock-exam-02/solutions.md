# CKAD Mock Exam 02 — Solutions (Foundations+)

> Grade only after the 120-minute timer has stopped. For each question, run the **Verify** commands and award the points listed under **Points**. Paths assume the defaults from `setup.sh`. Questions are in [questions.md](questions.md).

## Domain weights in this paper

| Domain | Official weight | Questions | Weight in this paper |
|---|---|---|---|
| Application Design and Build | 20% | Q1, Q2, Q3, Q4 | 21% |
| Application Deployment | 20% | Q5, Q6, Q7, Q8 | 20% |
| Application Observability and Maintenance | 15% | Q9, Q10, Q11, Q12 | 15% |
| Application Environment, Configuration and Security | 25% | Q13, Q14, Q15, Q16 | 24% |
| Services and Networking | 20% | Q17, Q18, Q19 | 20% |
| **Total** | **100%** | **19 questions** | **100%** |

**How to grade:** one point = 1% of the exam. A point counts only when its check passes. If you changed an object the task said not to modify, the task's last point is lost. The pass mark is **66**.

---

## Question 1 — Modify, rebuild and export an image (5%)
*Target time: 6 min*

**Approach:** Change three Dockerfile instructions (`FROM`, `ENV`, plus a new `USER`), rebuild, and save with `--format oci-archive`.

```dockerfile
FROM busybox:1.36
ENV APP_ENV=production
WORKDIR /app
COPY report.sh /app/report.sh
USER 1001
CMD ["sh", "/app/report.sh"]
```

```bash
cd ~/ckad-mocks/exam-02/q01
vim Dockerfile
podman build -t m02-report:2.0 .
podman save --format oci-archive -o ~/ckad-mocks/exam-02/q01/m02-report-2.0.tar m02-report:2.0

# docker: docker build -t m02-report:2.0 . && docker save -o ~/ckad-mocks/exam-02/q01/m02-report-2.0.tar m02-report:2.0
#   docker save has no --format flag; Docker Engine 25+ writes an OCI image layout (index.json, oci-layout) into the tar.
```

**Verify**

```bash
grep -E '^(FROM|ENV|USER)' ~/ckad-mocks/exam-02/q01/Dockerfile
podman image inspect m02-report:2.0 --format '{{.Config.User}} {{.Config.Env}}'
podman run --rm m02-report:2.0
tar -tf ~/ckad-mocks/exam-02/q01/m02-report-2.0.tar | grep -E '^(oci-layout|index.json)$'
```

```text
FROM busybox:1.36
ENV APP_ENV=production
USER 1001
1001 [PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin APP_ENV=production]
report generator: env=production uid=1001
oci-layout
index.json
```

**Common mistakes**
- Saving without `--format oci-archive`, which gives podman's default docker-archive.
- Editing the Dockerfile but saving an image that wasn't rebuilt, or that was built with a different tag.
- `ENV APP_ENV production` (the legacy space form) still works but is deprecated. Use `KEY=value`.
- Mixing `sudo podman build` with a plain `podman save`. The two use different image stores, so you get "image not known".

**Points (5)**
- 1: `FROM busybox:1.36`.
- 1: `APP_ENV=production`.
- 1: `USER 1001`.
- 1: image `m02-report:2.0` was built from the modified file (inspect shows user 1001).
- 1: the archive at the exact path is in OCI format.

---

## Question 2 — Parallel batch Job (5%)
*Target time: 5 min*

**Approach:** Generate the Job with `kubectl create job`, which already sets `restartPolicy: Never`. Add the four Job-level fields and rename the container.

```bash
kubectl -n m02-jobs create job batch-processor --image=busybox:1.36 --dry-run=client -o yaml \
  -- sh -c 'echo "processing chunk on $(hostname)"; sleep 5' > ~/ckad-mocks/exam-02/q02/job.yaml
vim ~/ckad-mocks/exam-02/q02/job.yaml
kubectl apply -f ~/ckad-mocks/exam-02/q02/job.yaml
kubectl -n m02-jobs wait --for=condition=complete job/batch-processor --timeout=180s
```

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: batch-processor
  namespace: m02-jobs
spec:
  completions: 6                 # 6 successful Pods
  parallelism: 2                 # at most 2 at a time
  backoffLimit: 3                # 3 retries, then Failed
  ttlSecondsAfterFinished: 1800  # deleted 30 min after it finishes
  template:
    spec:
      restartPolicy: Never       # failed Pod -> new Pod, no in-place restart
      containers:
      - name: processor
        image: busybox:1.36
        command: ["sh", "-c", "echo \"processing chunk on $(hostname)\"; sleep 5"]
```

**Verify**

```bash
kubectl -n m02-jobs get job batch-processor
kubectl -n m02-jobs get job batch-processor -o jsonpath='{.spec.completions} {.spec.parallelism} {.spec.backoffLimit} {.spec.ttlSecondsAfterFinished} {.spec.template.spec.restartPolicy}{"\n"}'
kubectl -n m02-jobs logs job/batch-processor
```

```text
NAME              STATUS     COMPLETIONS   DURATION   AGE
batch-processor   Complete   6/6           24s        1m
6 2 3 1800 Never
processing chunk on batch-processor-4xk2p
```

If you grade more than 30 minutes after the Job finished, the TTL has already deleted it. That is correct behaviour; grade the saved `job.yaml` instead.

**Common mistakes**
- `restartPolicy: OnFailure` restarts the container in place, which the task forbids.
- `ttlSecondsAfterFinished: 30m`. The field takes an integer number of seconds.
- Putting `completions`/`parallelism` inside `template.spec`.

**Points (5)**
- 1: completions 6 and parallelism 2.
- 1: backoffLimit 3.
- 1: ttlSecondsAfterFinished 1800.
- 1: `restartPolicy: Never`, plus the container name, image and command.
- 1: the Job completed 6/6 and the manifest is saved in `job.yaml`.

---

## Question 3 — Init container prepares web content (5%)
*Target time: 6 min*

**Approach:** One `emptyDir`, mounted at `/work` in the init container and at `/usr/share/nginx/html` in nginx.

```bash
kubectl -n m02-init run welcome --image=nginx:1.27-alpine --port=80 --dry-run=client -o yaml > q03-pod.yaml
vim q03-pod.yaml            # rename container to web, add initContainers + volume
kubectl apply -f q03-pod.yaml
```

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: welcome
  namespace: m02-init
spec:
  volumes:
  - name: html
    emptyDir: {}
  initContainers:
  - name: prepare
    image: busybox:1.36
    command: ["sh", "-c", "echo '<h1>Welcome to CKAD mock 02</h1>' > /work/index.html"]
    volumeMounts:
    - name: html
      mountPath: /work
  containers:
  - name: web
    image: nginx:1.27-alpine
    ports:
    - containerPort: 80
    volumeMounts:
    - name: html
      mountPath: /usr/share/nginx/html
```

**Verify**

```bash
kubectl -n m02-init get pod welcome
kubectl -n m02-init exec welcome -c web -- wget -qO- http://localhost
kubectl -n m02-init get pod welcome -o jsonpath='{.status.initContainerStatuses[0].state.terminated.reason}{"\n"}'
```

```text
NAME      READY   STATUS    RESTARTS   AGE
welcome   1/1     Running   0          20s
<h1>Welcome to CKAD mock 02</h1>
Completed
```

**Common mistakes**
- The init container writing to `/usr/share/nginx/html/...` when its mount is at `/work`. The file then lands in its own filesystem and is lost.
- An empty volume mounted over nginx's html directory makes nginx return 403 Forbidden.
- Running `echo ... > file` without `sh -c`, so the redirection is passed to `echo` as an argument.

**Points (5)**
- 2: init container `prepare` (busybox) writes `index.html` into emptyDir `html` mounted at `/work`.
- 2: container `web` (nginx:1.27-alpine, port 80) mounts `html` at `/usr/share/nginx/html`.
- 1: `wget` inside `web` returns the line.

---

## Question 4 — From a bare Pod to a Deployment (6%)
*Target time: 7 min*

**Approach:** Read the Pod, generate a Deployment, and copy across the labels plus the container's name, image, env, ports and resources. Add `serviceAccountName`, and disable token automounting on the ServiceAccount.

```bash
kubectl -n m02-convert get pod inventory -o yaml | less          # labels, env, resources
kubectl -n m02-convert create serviceaccount inventory-sa --dry-run=client -o yaml > /tmp/sa.yaml
echo "automountServiceAccountToken: false" >> /tmp/sa.yaml        # top-level field
kubectl apply -f /tmp/sa.yaml
kubectl -n m02-convert create deployment inventory --image=nginx:1.27-alpine --replicas=3 --port=80 \
  --dry-run=client -o yaml > ~/ckad-mocks/exam-02/q04/inventory-deploy.yaml
vim ~/ckad-mocks/exam-02/q04/inventory-deploy.yaml
kubectl apply -f ~/ckad-mocks/exam-02/q04/inventory-deploy.yaml
kubectl -n m02-convert rollout status deployment/inventory
kubectl -n m02-convert delete pod inventory
```

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: inventory-sa
  namespace: m02-convert
automountServiceAccountToken: false     # no token volume for Pods using this SA
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: inventory
  namespace: m02-convert
  labels:
    app: inventory
spec:
  replicas: 3
  selector:
    matchLabels:
      app: inventory
      tier: backend
  template:
    metadata:
      labels:                     # same labels as the old Pod
        app: inventory
        tier: backend
    spec:
      serviceAccountName: inventory-sa
      containers:
      - name: inventory
        image: nginx:1.27-alpine
        env:
        - name: INVENTORY_MODE
          value: "readonly"
        ports:
        - containerPort: 80
        resources:
          requests:
            cpu: 50m
            memory: 64Mi
```

**Verify**

```bash
kubectl -n m02-convert get deploy inventory
kubectl -n m02-convert get pods -l app=inventory -o custom-columns=NAME:.metadata.name,SA:.spec.serviceAccountName,OWNER:.metadata.ownerReferences[0].kind
kubectl -n m02-convert exec deploy/inventory -- ls /var/run/secrets/kubernetes.io/serviceaccount
kubectl -n m02-convert get sa inventory-sa -o jsonpath='{.automountServiceAccountToken}{"\n"}'
```

```text
NAME        READY   UP-TO-DATE   AVAILABLE   AGE
inventory   3/3     3            3           1m
NAME                         SA             OWNER
inventory-6c9f8d7b4d-8kq2x   inventory-sa   ReplicaSet
inventory-6c9f8d7b4d-f4m7p   inventory-sa   ReplicaSet
inventory-6c9f8d7b4d-zt9wq   inventory-sa   ReplicaSet
ls: /var/run/secrets/kubernetes.io/serviceaccount: No such file or directory
command terminated with exit code 1
false
```

**Common mistakes**
- `automountServiceAccountToken` put under `metadata` of the ServiceAccount. It is a top-level field. Alternatively, set it to `false` in the Pod template spec, where it overrides the SA setting.
- `serviceAccountName` placed at the Deployment `spec` level instead of the Pod template `spec`.
- Dropping the env var or the resource requests while converting.
- Deleting the bare Pod before the Deployment is available, which causes a short outage.

**Points (6)**
- 1: ServiceAccount `inventory-sa` with automounting disabled.
- 2: Deployment `inventory` is 3/3 with the same labels and container (name, image, env, port, resources).
- 2: the Pods run as `inventory-sa` and have no token mounted.
- 1: the bare Pod is deleted and the manifest is saved.

---

## Question 5 — Blue/green switch (4%)
*Target time: 4 min*

**Approach:** Bring green up, wait for it, then switch the Service selector in one atomic change. Blue stays at 0 replicas as the rollback path.

```bash
kubectl -n m02-bluegreen scale deployment store-green --replicas=3
kubectl -n m02-bluegreen rollout status deployment/store-green
kubectl -n m02-bluegreen patch service store -p '{"spec":{"selector":{"app":"store","version":"green"}}}'
# or: kubectl -n m02-bluegreen set selector service store 'app=store,version=green'
kubectl -n m02-bluegreen scale deployment store-blue --replicas=0
```

**Verify**

```bash
kubectl -n m02-bluegreen get svc store -o jsonpath='{.spec.selector}{"\n"}'
kubectl -n m02-bluegreen get deploy
kubectl -n m02-bluegreen run tmp --rm -i --restart=Never --image=busybox:1.36 -- \
  sh -c 'for i in 1 2 3 4 5; do wget -qO- http://store; done'
```

```text
{"app":"store","version":"green"}
NAME          READY   UP-TO-DATE   AVAILABLE   AGE
store-blue    0/0     0            0           30m
store-green   3/3     3            3           30m
store version: green
store version: green
store version: green
store version: green
store version: green
```

**Common mistakes**
- Switching before green is Ready leaves the Service with no endpoints for a while.
- A selector of just `app=store` sends traffic to both colours.
- Deleting `store-blue`. Keep it, because rolling back is just switching the selector again.

**Points (4)**
- 1: `store-green` is 3/3 Ready.
- 2: the Service selector is `app=store,version=green`.
- 1: `store-blue` is at 0 replicas, still exists, and neither Pod template changed.

---

## Question 6 — Tune the update strategy (5%)
*Target time: 6 min*

**Approach:** "At most one extra Pod, none unavailable" translates to `maxSurge: 1` and `maxUnavailable: 0`. "Old and new never together" translates to `Recreate`. When you switch to `Recreate`, you must also **remove** `rollingUpdate`.

```bash
kubectl -n m02-strategy patch deployment catalog \
  -p '{"spec":{"strategy":{"type":"RollingUpdate","rollingUpdate":{"maxSurge":1,"maxUnavailable":0}}}}'
kubectl -n m02-strategy set image deployment/catalog catalog=nginx:1.27
kubectl -n m02-strategy rollout status deployment/catalog

kubectl -n m02-strategy patch deployment ledger \
  -p '{"spec":{"strategy":{"type":"Recreate","rollingUpdate":null}}}'     # null deletes the field
kubectl -n m02-strategy set env deployment/ledger -c ledger LEDGER_MODE=strict
kubectl -n m02-strategy rollout status deployment/ledger
```

End state of both Deployments:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: catalog
  namespace: m02-strategy
spec:
  replicas: 4
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0
  selector:
    matchLabels:
      app: catalog
  template:
    metadata:
      labels:
        app: catalog
    spec:
      containers:
      - name: catalog
        image: nginx:1.27
        ports:
        - containerPort: 80
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ledger
  namespace: m02-strategy
spec:
  replicas: 1
  strategy:
    type: Recreate              # no rollingUpdate block allowed
  selector:
    matchLabels:
      app: ledger
  template:
    metadata:
      labels:
        app: ledger
    spec:
      terminationGracePeriodSeconds: 2
      containers:
      - name: ledger
        image: busybox:1.36
        command:
        - sh
        - -c
        - while true; do echo "ledger running mode=${LEDGER_MODE:-default}"; sleep 10; done
        env:
        - name: LEDGER_MODE
          value: strict
```

**Verify**

```bash
kubectl -n m02-strategy get deploy catalog -o jsonpath='{.spec.strategy}{"\n"}{.spec.template.spec.containers[0].image}{"\n"}'
kubectl -n m02-strategy get deploy ledger -o jsonpath='{.spec.strategy}{"\n"}{.spec.template.spec.containers[0].env}{"\n"}'
kubectl -n m02-strategy logs deploy/ledger --tail=1
```

```text
{"rollingUpdate":{"maxSurge":1,"maxUnavailable":0},"type":"RollingUpdate"}
nginx:1.27
{"type":"Recreate"}
[{"name":"LEDGER_MODE","value":"strict"}]
ledger running mode=strict
```

**Common mistakes**
- Patching only `"type":"Recreate"` is rejected with `spec.strategy.rollingUpdate: Forbidden: may not be specified when strategy type is 'Recreate'`. In `kubectl edit`, delete the whole `rollingUpdate:` block.
- Swapping the two values (`maxSurge: 0, maxUnavailable: 1`).
- Updating the image before changing the strategy, so the rollout uses the old defaults (25%/25%).

**Points (5)**
- 2: `catalog` has maxSurge 1 and maxUnavailable 0.
- 1: `catalog` is rolled out on `nginx:1.27`.
- 1: `ledger` strategy is `Recreate`.
- 1: `ledger` has `LEDGER_MODE=strict`.

---

## Question 7 — Kustomize production overlay (5%)
*Target time: 6 min*

**Approach:** The overlay is a single `kustomization.yaml`. It references the base two levels up and applies four built-in transformers.

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- ../../base
namespace: m02-prod
namePrefix: prod-
images:
- name: nginx          # matches the image name, whatever its current tag
  newTag: "1.27"       # quote tags: 1.30 unquoted would become 1.3
replicas:
- name: api            # the base name of the Deployment
  count: 3
```

```bash
vim ~/ckad-mocks/exam-02/q07/overlays/prod/kustomization.yaml
kubectl kustomize ~/ckad-mocks/exam-02/q07/overlays/prod > ~/ckad-mocks/exam-02/q07/prod-rendered.yaml
kubectl apply -k ~/ckad-mocks/exam-02/q07/overlays/prod
```

**Docs in the exam:** the Kustomize site is not on the allowed list. The allowed page [kubernetes.io › Declarative Management of Kubernetes Objects Using Kustomize](https://kubernetes.io/docs/tasks/manage-kubernetes-objects/kustomization/) documents `namespace`, `namePrefix` and `images`, but **not** the `replicas` field; it changes replicas with a patch. If you don't remember `replicas`, the docs-backed version below gives the same result. The patch names the **base** Deployment (`api`, no namespace), because patches are applied before the prefix and namespace transformers:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- ../../base
namespace: m02-prod
namePrefix: prod-
images:
- name: nginx
  newTag: "1.27"
patches:
- patch: |-
    apiVersion: apps/v1
    kind: Deployment
    metadata:
      name: api
    spec:
      replicas: 3
```

**Verify**

```bash
kubectl -n m02-prod get deploy,svc
kubectl -n m02-prod get deploy prod-api -o jsonpath='{.spec.replicas} {.spec.template.spec.containers[0].image}{"\n"}'
grep -E 'name: prod-api|namespace: m02-prod|image:' ~/ckad-mocks/exam-02/q07/prod-rendered.yaml
```

```text
NAME                       READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/prod-api   3/3     3            3           30s
NAME               TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)   AGE
service/prod-api   ClusterIP   10.96.55.140   <none>        80/TCP    30s
3 nginx:1.27
  name: prod-api
  namespace: m02-prod
  name: prod-api
  namespace: m02-prod
      - image: nginx:1.27
```

kustomize prints keys in alphabetical order, which is why `image` comes first in the container entry.

**Common mistakes**
- `resources: - ../base`. The overlay is at `overlays/prod`, so the base is `../../base`.
- Editing files in `base/`, which is forbidden, or applying the base itself, which puts the objects in the current namespace.
- `kubectl apply -f overlays/prod` instead of `-k`.
- Relying on kustomize to create the namespace. It only sets `metadata.namespace`; the Namespace object must already exist (it does here) or be listed as a resource.

**Points (5)**
- 1: the overlay uses the base and namespace `m02-prod`.
- 1: `namePrefix: prod-`.
- 1: the image tag is `1.27`.
- 1: replicas is 3.
- 1: `prod-rendered.yaml` was written, `prod-api` (Deployment 3/3 and Service) exists in `m02-prod`, and the base is unchanged.

---

## Question 8 — Helm release management (6%)
*Target time: 7 min*

**Approach:** `helm list -A` finds the old release's namespace. `helm template` renders locally without touching the cluster. `helm get values` prints only the user-supplied values.

```bash
helm list -A | grep m02-legacy                         # NAMESPACE column -> m02-tools
helm uninstall m02-legacy -n m02-tools
helm show values ~/ckad-mocks/exam-02/q08/webapp | grep -nE '^replicaCount|^  tag:|^service:|^  type:'
helm template m02-web ~/ckad-mocks/exam-02/q08/webapp -n m02-helm \
  --set replicaCount=3 --set image.tag=1.27-alpine --set service.type=NodePort \
  > ~/ckad-mocks/exam-02/q08/m02-web-rendered.yaml
helm install m02-web ~/ckad-mocks/exam-02/q08/webapp -n m02-helm \
  --set replicaCount=3 --set image.tag=1.27-alpine --set service.type=NodePort
helm get values m02-web -n m02-helm > ~/ckad-mocks/exam-02/q08/values.txt
```

**Verify**

```bash
helm list -A | grep -E 'm02-(web|legacy)'
cat ~/ckad-mocks/exam-02/q08/values.txt
grep -E 'replicas:|type: NodePort|image: "nginx' ~/ckad-mocks/exam-02/q08/m02-web-rendered.yaml   # helm template also renders the busybox test hook
kubectl -n m02-helm get deploy,svc
```

```text
m02-web   m02-helm   1   2026-10-17 10:40:02 +0000 UTC   deployed   webapp-0.1.0   1.16.0
USER-SUPPLIED VALUES:
image:
  tag: 1.27-alpine
replicaCount: 3
service:
  type: NodePort
  type: NodePort
  replicas: 3
          image: "nginx:1.27-alpine"
NAME                             READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/m02-web-webapp   3/3     3            3           40s
NAME                     TYPE       CLUSTER-IP     EXTERNAL-IP   PORT(S)        AGE
service/m02-web-webapp   NodePort   10.96.87.201   <none>        80:30512/TCP   40s
```

`m02-legacy` no longer appears. The chart names its objects `<release>-<chart>`, hence `m02-web-webapp`.

**Common mistakes**
- `helm uninstall m02-legacy` without `-n m02-tools` fails with `release: not found`, because Helm only looks in the current namespace.
- `helm install --dry-run` instead of `helm template`. It still needs the cluster and prints extra headers and notes.
- `helm get values --all`, which writes the computed values too; the task asks for user-supplied values only.
- Value typos (`replicacount`) are silently ignored. Check the rendered file.

**Points (6)**
- 1: `m02-legacy` is uninstalled.
- 2: the rendered file reflects all three values, and the render installed nothing.
- 2: release `m02-web` is `deployed` in `m02-helm` with 3 Ready replicas and a NodePort Service.
- 1: `values.txt` shows exactly the user-supplied values.

---

## Question 9 — Startup probe for a slow application (5%)
*Target time: 5 min*

**Approach:** Confirm the cause (liveness kills the container), then add a `startupProbe`. Liveness and readiness probes start only after the startup probe has succeeded, so the app gets up to 10 s × 12 = 120 s to start.

```bash
kubectl -n m02-probes get pods -l app=slow-app                               # RESTARTS keeps growing
kubectl -n m02-probes describe pod -l app=slow-app | grep -E 'Unhealthy|Killing' | tail -2
# Warning  Unhealthy  ... Liveness probe failed: Get "http://10.244.1.7:8080/": dial tcp ... connect: connection refused
# Normal   Killing    ... Container app failed liveness probe, will be restarted
kubectl -n m02-probes edit deployment slow-app                               # add startupProbe
```

End state, with only `startupProbe` added:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: slow-app
  namespace: m02-probes
spec:
  replicas: 1
  selector:
    matchLabels:
      app: slow-app
  template:
    metadata:
      labels:
        app: slow-app
    spec:
      terminationGracePeriodSeconds: 2
      containers:
      - name: app
        image: busybox:1.36
        command:
        - sh
        - -c
        - |
          echo "warming up caches (about 60s)..."
          sleep 60
          mkdir -p /www && echo "slow-app ready" > /www/index.html
          echo "serving on :8080"
          exec httpd -f -p 8080 -h /www
        ports:
        - name: http
          containerPort: 8080
        startupProbe:              # added
          httpGet:
            path: /
            port: 8080
          periodSeconds: 10
          failureThreshold: 12
        livenessProbe:             # unchanged
          httpGet:
            path: /
            port: 8080
          periodSeconds: 10
          failureThreshold: 3
```

**Verify**

```bash
kubectl -n m02-probes rollout status deployment/slow-app --timeout=180s
kubectl -n m02-probes get pods -l app=slow-app
kubectl -n m02-probes get deploy slow-app -o jsonpath='{.spec.template.spec.containers[0].startupProbe}{"\n"}{.spec.template.spec.containers[0].livenessProbe}{"\n"}'
```

```text
deployment "slow-app" successfully rolled out
NAME                        READY   STATUS    RESTARTS   AGE
slow-app-5b7c9d8f6c-q2w8e   1/1     Running   0          2m
{"failureThreshold":12,"httpGet":{"path":"/","port":8080,"scheme":"HTTP"},"periodSeconds":10,"successThreshold":1,"timeoutSeconds":1}
{"failureThreshold":3,"httpGet":{"path":"/","port":8080,"scheme":"HTTP"},"periodSeconds":10,"successThreshold":1,"timeoutSeconds":1}
```

**Common mistakes**
- Raising the liveness probe's `initialDelaySeconds` instead. The task forbids it, and it would also delay real failure detection on every start.
- A startup probe on port 80 (nothing listens there), so the Pod never starts.
- Judging too early. The new Pod needs about 60–70 s before it turns Ready.

**Points (5)**
- 3: startupProbe is HTTP GET `/` on 8080 with period 10 and failureThreshold 12.
- 1: the liveness probe is unchanged.
- 1: the new Pod is Ready with 0 restarts two minutes later.

---

## Question 10 — CrashLoopBackOff (5%)
*Target time: 5 min*

**Approach:** `logs --previous` shows why the last run died. Compare the script path in the command with the keys of the mounted ConfigMap: the command runs `tick.sh`, but the key is `ticker.sh`.

```bash
kubectl -n m02-debug get pods -l app=ticker
POD=$(kubectl -n m02-debug get pods -l app=ticker -o jsonpath='{.items[0].metadata.name}')
kubectl -n m02-debug logs "$POD" -c ticker --previous > ~/ckad-mocks/exam-02/q10/previous.log
cat ~/ckad-mocks/exam-02/q10/previous.log
kubectl -n m02-debug describe configmap ticker-script | head -8                  # Data: ticker.sh
kubectl -n m02-debug get deploy ticker -o jsonpath='{.spec.template.spec.containers[0].command}{"\n"}'
kubectl -n m02-debug edit deployment ticker                                     # tick.sh -> ticker.sh
```

```text
booting ticker v2
sh: can't open '/opt/ticker/tick.sh': No such file or directory
```

End state, with only the command changed:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ticker
  namespace: m02-debug
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ticker
  template:
    metadata:
      labels:
        app: ticker
    spec:
      terminationGracePeriodSeconds: 2
      containers:
      - name: ticker
        image: busybox:1.36
        command: ["sh", "-c", "echo 'booting ticker v2'; exec sh /opt/ticker/ticker.sh"]
        volumeMounts:
        - name: script
          mountPath: /opt/ticker
      volumes:
      - name: script
        configMap:
          name: ticker-script
```

**Verify**

```bash
kubectl -n m02-debug rollout status deployment/ticker
kubectl -n m02-debug get pods -l app=ticker
kubectl -n m02-debug logs deploy/ticker | head -3
```

```text
deployment "ticker" successfully rolled out
NAME                      READY   STATUS    RESTARTS   AGE
ticker-6f5d8c7b9d-m4x2k   1/1     Running   0          40s
booting ticker v2
ticker started
tick 10:31:05
```

**Common mistakes**
- Renaming the ConfigMap key to `tick.sh`. The task forbids modifying the ConfigMap.
- Deleting the Pod over and over. The ReplicaSet recreates exactly the same broken Pod.
- Capturing `kubectl logs` of a freshly restarted container instead of `--previous`. The file must contain the error line.

**Points (5)**
- 2: `previous.log` contains the `can't open '/opt/ticker/tick.sh'` error.
- 2: the Deployment command points to `/opt/ticker/ticker.sh`, and the ConfigMap is unchanged.
- 1: the Pod is Running without new restarts and logs `tick` lines.

---

## Question 11 — Deprecated PodDisruptionBudget (3%)
*Target time: 3 min*

**Approach:** `policy/v1beta1` PodDisruptionBudget was removed in v1.25. `policy/v1` has the same fields for this manifest, so changing the apiVersion line is enough.

```bash
kubectl apply -f ~/ckad-mocks/exam-02/q11/pdb.yaml
# error: resource mapping not found ... no matches for kind "PodDisruptionBudget" in version "policy/v1beta1"
kubectl api-resources | grep -i poddisruptionbudgets       # pdb   policy/v1   true   PodDisruptionBudget
sed -i 's#^apiVersion: policy/v1beta1#apiVersion: policy/v1#' ~/ckad-mocks/exam-02/q11/pdb.yaml
kubectl apply -f ~/ckad-mocks/exam-02/q11/pdb.yaml
kubectl -n m02-pdb get pdb web-pdb -o jsonpath='{.status.disruptionsAllowed}' > ~/ckad-mocks/exam-02/q11/allowed.txt
```

```yaml
# PodDisruptionBudget for Deployment web, written for Kubernetes 1.20
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: web-pdb
  namespace: m02-pdb
spec:
  minAvailable: 2
  selector:
    matchLabels:
      app: web
```

**Verify**

```bash
kubectl -n m02-pdb get pdb web-pdb
cat ~/ckad-mocks/exam-02/q11/allowed.txt; echo
```

```text
NAME      MIN AVAILABLE   MAX UNAVAILABLE   ALLOWED DISRUPTIONS   AGE
web-pdb   2               N/A               1                     20s
1
```

One behaviour change to know: in `policy/v1` an **empty** selector (`{}`) matches every Pod in the namespace, whereas in `v1beta1` it matched none.

**Common mistakes**
- Changing `minAvailable` or the selector while migrating.
- Reading the value while some `web` Pods are not Ready, which gives `0`.
- Writing the whole table instead of the number.

**Points (3)**
- 1: the file uses `policy/v1` and is otherwise unchanged.
- 1: the PDB is applied.
- 1: `allowed.txt` contains `1`.

---

## Question 12 — Cluster health snapshot (2%)
*Target time: 3 min*

**Approach:** `kubectl top nodes` with `--sort-by` and `--no-headers` for the single name. Events support field selectors on `type`; sort them by creation time.

```bash
kubectl top nodes > ~/ckad-mocks/exam-02/q12/nodes.txt
kubectl top nodes --sort-by=memory --no-headers | head -1 | awk '{print $1}' > ~/ckad-mocks/exam-02/q12/top-node.txt
kubectl -n m02-debug get events --field-selector type=Warning --sort-by=.metadata.creationTimestamp \
  > ~/ckad-mocks/exam-02/q12/warnings.txt
```

**Verify**

```bash
cat ~/ckad-mocks/exam-02/q12/nodes.txt ~/ckad-mocks/exam-02/q12/top-node.txt
head -3 ~/ckad-mocks/exam-02/q12/warnings.txt
```

```text
NAME                 CPU(cores)   CPU(%)   MEMORY(bytes)   MEMORY(%)
ckad-control-plane   182m         4%       812Mi           10%
ckad-worker          95m          2%       640Mi           8%
ckad-worker2         60m          1%       410Mi           5%
ckad-control-plane
LAST SEEN   TYPE      REASON    OBJECT                       MESSAGE
12m         Warning   BackOff   pod/ticker-7d4b9c6f5-k2x8p   Back-off restarting failed container ticker in pod ...
```

**Common mistakes**
- `--field-selector type=warning`. Field selector values are case-sensitive, so this matches nothing.
- `--sort-by=.lastTimestamp`. Events written through the newer events API may have no `lastTimestamp`, so `.metadata.creationTimestamp` is the reliable key.
- Using `kubectl top pods` instead of nodes.

**Points (2)**
- 1: `nodes.txt` holds the `top nodes` table.
- 1: `top-node.txt` names the right node, and `warnings.txt` lists only the Warning events of `m02-debug`.

---

## Question 13 — Discover and use custom resources (5%)
*Target time: 6 min*

**Approach:** Discover the group's CRDs, their served version (`v1alpha1`) and the short name (`mdb`) with `kubectl api-resources`. Use `kubectl explain` to see the field types; `version` is a string.

```bash
kubectl get crd -o jsonpath='{range .items[?(@.spec.group=="m02.example.com")]}{.metadata.name}{"\n"}{end}' \
  > ~/ckad-mocks/exam-02/q13/crds.txt
kubectl api-resources --api-group=m02.example.com
# NAME        SHORTNAMES   APIVERSION                 NAMESPACED   KIND
# caches      mch          m02.example.com/v1alpha1   true         Cache
# databases   mdb          m02.example.com/v1alpha1   true         Database
kubectl explain database.spec
kubectl apply -f - <<'EOF'
apiVersion: m02.example.com/v1alpha1
kind: Database
metadata:
  name: orders-db
  namespace: m02-crd
spec:
  engine: postgres
  version: "16"          # string in the schema, so quote it
  storageGB: 10
---
apiVersion: m02.example.com/v1alpha1
kind: Database
metadata:
  name: users-db
  namespace: m02-crd
spec:
  engine: mysql
  version: "8.4"
  storageGB: 5
EOF
kubectl -n m02-crd get mdb > ~/ckad-mocks/exam-02/q13/databases.txt
```

**Verify**

```bash
cat ~/ckad-mocks/exam-02/q13/crds.txt ~/ckad-mocks/exam-02/q13/databases.txt
```

```text
caches.m02.example.com
databases.m02.example.com
NAME        ENGINE     VERSION   STORAGE-GB   AGE
orders-db   postgres   16        10           20s
users-db    mysql      8.4       5            20s
```

**Common mistakes**
- `version: 16` unquoted is rejected with `spec.version in body must be of type string: "integer"`.
- `apiVersion: m02.example.com/v1`. This group serves `v1alpha1`, which `api-resources` shows.
- Guessing the short name `db`. Read it from `kubectl api-resources`.
- Using `kubectl get crd -o name`, which writes `customresourcedefinition.apiextensions.k8s.io/...` prefixes into the file.

**Points (5)**
- 1: `crds.txt` lists exactly the two CRDs.
- 1: `orders-db` is correct.
- 1: `users-db` is correct.
- 2: `databases.txt` was produced with the short name `mdb` and lists both objects.

---

## Question 14 — Update configuration safely (6%)
*Target time: 6 min*

**Approach:** Merge-patch one key, which leaves the other keys alone. Environment variables are read only at container start, so run a `rollout restart`; it adds a `restartedAt` annotation to the template for you. Then add the top-level field `immutable: true` to the new ConfigMap.

```bash
kubectl -n m02-config patch configmap api-settings -p '{"data":{"LOG_LEVEL":"debug"}}'
kubectl -n m02-config rollout restart deployment/api
kubectl -n m02-config rollout status deployment/api

kubectl -n m02-config create configmap feature-flags --from-literal=FEATURE_X=on --from-literal=FEATURE_Y=off \
  --dry-run=client -o yaml > q14-flags.yaml
echo "immutable: true" >> q14-flags.yaml          # top-level field, column 0
kubectl apply -f q14-flags.yaml
```

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: feature-flags
  namespace: m02-config
immutable: true
data:
  FEATURE_X: "on"        # quoted: unquoted on/off are YAML 1.1 booleans
  FEATURE_Y: "off"
```

**Verify**

```bash
kubectl -n m02-config get cm api-settings -o jsonpath='{.data}{"\n"}'
kubectl -n m02-config logs deploy/api --tail=1
kubectl -n m02-config get deploy api -o jsonpath='{.spec.template.metadata.annotations}{"\n"}'
kubectl -n m02-config get cm feature-flags -o jsonpath='{.immutable} {.data}{"\n"}'
kubectl -n m02-config patch cm feature-flags -p '{"data":{"FEATURE_X":"off"}}'
```

```text
{"CACHE_TTL":"60","DB_POOL_SIZE":"10","LOG_LEVEL":"debug"}
LOG_LEVEL=debug CACHE_TTL=60 DB_POOL_SIZE=10
{"kubectl.kubernetes.io/restartedAt":"2026-10-17T10:52:40Z"}
true {"FEATURE_X":"on","FEATURE_Y":"off"}
The ConfigMap "feature-flags" is invalid: data: Forbidden: field is immutable when `immutable` is set
```

**Common mistakes**
- Updating the ConfigMap without restarting. Running Pods keep `LOG_LEVEL=info`, because env vars never refresh. Mounted ConfigMap files do refresh, unless mounted with `subPath`.
- Re-creating `api-settings` from only `LOG_LEVEL` drops `CACHE_TTL` and `DB_POOL_SIZE`.
- Hand-written YAML with `FEATURE_X: on` fails to decode: `cannot unmarshal bool into ... of type string`.
- `immutable: true` placed under `metadata` or `data`.

**Points (6)**
- 2: `LOG_LEVEL` is `debug` and the other keys are intact.
- 2: a rolling restart was performed, the Pods print `LOG_LEVEL=debug`, and the template wasn't hand-edited.
- 2: `feature-flags` is immutable and has both keys.

---

## Question 15 — Secret as a read-only file (5%)
*Target time: 5 min*

**Approach:** `--from-file=<key>=<path>` sets the key name. `defaultMode: 0400` on the secret volume sets the file mode; YAML reads a leading `0` as octal.

```bash
kubectl -n m02-secret create secret generic api-key --from-file=token=$HOME/ckad-mocks/exam-02/q15/api-key.txt
kubectl -n m02-secret run api-client --image=busybox:1.36 --dry-run=client -o yaml --command -- sh -c 'sleep 3600' > q15-pod.yaml
vim q15-pod.yaml            # container name client, volume + mount
kubectl apply -f q15-pod.yaml
```

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: api-client
  namespace: m02-secret
spec:
  containers:
  - name: client
    image: busybox:1.36
    command: ["sh", "-c", "sleep 3600"]
    volumeMounts:
    - name: api-key
      mountPath: /etc/api
      readOnly: true
  volumes:
  - name: api-key
    secret:
      secretName: api-key
      defaultMode: 0400        # octal in YAML; in JSON write 256
```

**Verify**

```bash
kubectl -n m02-secret get secret api-key -o jsonpath='{.data.token}' | base64 -d
kubectl -n m02-secret exec api-client -- ls -lL /etc/api/token
kubectl -n m02-secret exec api-client -- cat /etc/api/token
kubectl -n m02-secret exec api-client -- env | grep -c ckad-m02
```

```text
ckad-m02-7f3a9c1e5b
-r--------    1 root     root            20 Oct 17 11:02 /etc/api/token
ckad-m02-7f3a9c1e5b
0
```

**Common mistakes**
- `--from-file=$HOME/.../api-key.txt` without `token=` makes the key `api-key.txt`.
- `defaultMode: 400` is *decimal* 400, which is octal 0620, giving `-rw--w----`. Write `0400`, or `256`.
- `ls -l` without `-L` shows the symlink (`lrwxrwxrwx token -> ..data/token`) rather than the file's mode.
- Adding `envFrom`/`secretKeyRef`. The token must not appear in the environment.

**Points (5)**
- 2: Secret `api-key` has key `token` with the file's content.
- 1: the Pod is Running, with the Secret mounted read-only at `/etc/api`.
- 2: `/etc/api/token` has mode `0400` (`-r--------`).

---

## Question 16 — Namespace guardrails (8%)
*Target time: 9 min*

**Approach:** PSA and LimitRanger are both **admission** controls, and both act only when a Pod is created. So: labels first, then the LimitRange, then fix and create the Pod.

```bash
kubectl label namespace m02-guard \
  pod-security.kubernetes.io/enforce=baseline \
  pod-security.kubernetes.io/warn=restricted
kubectl apply -f q16-limitrange.yaml
kubectl apply -f ~/ckad-mocks/exam-02/q16/tools-pod.yaml
# Error from server (Forbidden): ... pods "tools" is forbidden: violates PodSecurity "baseline:latest":
#   host namespaces (hostPID=true), privileged (container "tools" must not set securityContext.privileged=true)
vim ~/ckad-mocks/exam-02/q16/tools-pod.yaml          # remove hostPID and the privileged securityContext
kubectl apply -f ~/ckad-mocks/exam-02/q16/tools-pod.yaml
# Warning: would violate PodSecurity "restricted:latest": allowPrivilegeEscalation != false ..., runAsNonRoot != true ...
# pod/tools created
kubectl -n m02-guard get pod tools -o jsonpath='{.spec.containers[0].resources}' > ~/ckad-mocks/exam-02/q16/resources.txt
```

The LimitRange (`q16-limitrange.yaml`) and the fixed `tools-pod.yaml`:

```yaml
apiVersion: v1
kind: LimitRange
metadata:
  name: defaults
  namespace: m02-guard
spec:
  limits:
  - type: Container
    default:                 # = default limits
      cpu: 200m
      memory: 256Mi
    defaultRequest:          # = default requests
      cpu: 100m
      memory: 128Mi
---
apiVersion: v1
kind: Pod
metadata:
  name: tools
  namespace: m02-guard
spec:
  containers:
  - name: tools
    image: busybox:1.36
    command: ["sh", "-c", "sleep 3600"]
```

**Verify**

```bash
kubectl get ns m02-guard --show-labels
kubectl -n m02-guard get limitrange defaults -o jsonpath='{.spec.limits[0]}{"\n"}'
kubectl -n m02-guard get pod tools
cat ~/ckad-mocks/exam-02/q16/resources.txt; echo
# enforcement test (server-side dry run of a hostPID Pod must be rejected):
kubectl -n m02-guard run psa-test --image=busybox:1.36 --dry-run=server \
  --overrides='{"apiVersion":"v1","spec":{"hostPID":true}}' -- sleep 60
```

```text
NAME        STATUS   AGE   LABELS
m02-guard   Active   45m   ckad-mock=exam-02,kubernetes.io/metadata.name=m02-guard,pod-security.kubernetes.io/enforce=baseline,pod-security.kubernetes.io/warn=restricted
{"default":{"cpu":"200m","memory":"256Mi"},"defaultRequest":{"cpu":"100m","memory":"128Mi"},"type":"Container"}
NAME    READY   STATUS    RESTARTS   AGE
tools   1/1     Running   0          2m
{"limits":{"cpu":"200m","memory":"256Mi"},"requests":{"cpu":"100m","memory":"128Mi"}}
Error from server (Forbidden): pods "psa-test" is forbidden: violates PodSecurity "baseline:latest": host namespaces (hostPID=true)
```

**Common mistakes**
- Creating the Pod before the LimitRange. Defaults are injected only at admission, so delete and re-create the Pod.
- `enforce=restricted`, which rejects the fixed Pod; or a misspelled label key such as `pod-security.kubernetes.io/warning`.
- Setting `privileged: false` but leaving `hostPID: true`, which is still rejected.
- Adding resources to the Pod "to be safe". That is forbidden, and it hides whether the defaults work.
- Expecting PSA to evict running Pods. Labelling only *warns* about existing violators.

**Points (8)**
- 1: label `pod-security.kubernetes.io/enforce=baseline`.
- 1: label `pod-security.kubernetes.io/warn=restricted`.
- 2: LimitRange `defaults` with the four values.
- 2: `tools-pod.yaml` fixed in place (no hostPID/privileged; same name, image and command; no resources), and the Pod is Running.
- 2: `resources.txt` shows the injected defaults.

---

## Question 17 — Repair a Service (6%)
*Target time: 5 min*

**Approach:** Empty EndpointSlices point to the selector. Compare the Service selector with the Pod labels, and the targetPort with the containerPort. There are two faults: selector `app=ledger-api` (the Pods carry `app=ledger, component=api`), and targetPort 80 (the app listens on 8080).

```bash
kubectl -n m02-svc get svc ledger -o wide                                       # SELECTOR app=ledger-api
kubectl -n m02-svc get endpointslices -l kubernetes.io/service-name=ledger       # no endpoints
kubectl -n m02-svc get pods --show-labels
kubectl -n m02-svc get deploy ledger-api -o jsonpath='{.spec.template.spec.containers[0].ports}{"\n"}'   # 8080 "http"
kubectl -n m02-svc patch service ledger --type=merge \
  -p '{"spec":{"selector":{"app":"ledger","component":"api"},"ports":[{"port":80,"targetPort":8080}]}}'
kubectl -n m02-svc exec client -- wget -qO- -T 3 http://ledger > ~/ckad-mocks/exam-02/q17/response.txt
```

```yaml
apiVersion: v1
kind: Service
metadata:
  name: ledger
  namespace: m02-svc
spec:
  type: ClusterIP
  selector:
    app: ledger
    component: api            # without it the ledger-worker Pod is selected too
  ports:
  - port: 80
    targetPort: 8080          # or the port name: http
```

**Verify**

```bash
kubectl -n m02-svc get endpointslices -l kubernetes.io/service-name=ledger \
  -o jsonpath='{range .items[*].endpoints[*]}{.targetRef.name}{"\n"}{end}'
for i in 1 2 3 4; do kubectl -n m02-svc exec client -- wget -qO- -T 3 http://ledger; done
cat ~/ckad-mocks/exam-02/q17/response.txt
```

```text
ledger-api-6d9c7b8f5-7xk2p
ledger-api-6d9c7b8f5-qm4z8
ledger-api OK
ledger-api OK
ledger-api OK
ledger-api OK
ledger-api OK
```

**Common mistakes**
- A selector of just `app: ledger` also selects `ledger-worker`, which has no HTTP server, so some requests are refused.
- Fixing only one of the two faults.
- Relabelling the Deployment to match the Service, which the task forbids.

**Points (6)**
- 2: the selector is `app=ledger,component=api`, so the endpoints are exactly the two `ledger-api` Pods.
- 2: targetPort is `8080` (or `http`), and port 80 is kept.
- 2: `response.txt` contains `ledger-api OK`.

---

## Question 18 — Default deny with DNS (8%)
*Target time: 9 min*

**Approach:** Deny everything, then add the allows back. A connection needs **both** an egress allow on the client and an ingress allow on the server, and name resolution needs DNS egress to kube-system.

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: m02-netpol
spec:
  podSelector: {}               # every Pod in the namespace
  policyTypes:
  - Ingress
  - Egress
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-dns-egress
  namespace: m02-netpol
spec:
  podSelector: {}
  policyTypes:
  - Egress
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: kube-system
    ports:
    - protocol: UDP
      port: 53
    - protocol: TCP
      port: 53
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: web-allow-client
  namespace: m02-netpol
spec:
  podSelector:
    matchLabels:
      app: web
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: client
    ports:
    - protocol: TCP
      port: 80
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: client-allow-web
  namespace: m02-netpol
spec:
  podSelector:
    matchLabels:
      app: client
  policyTypes:
  - Egress
  egress:
  - to:
    - podSelector:
        matchLabels:
          app: web
    ports:
    - protocol: TCP
      port: 80
```

```bash
kubectl apply -f q18-netpol.yaml
```

**Verify**

```bash
kubectl -n m02-netpol get networkpolicy
kubectl -n m02-netpol exec client -- nslookup web.m02-netpol.svc.cluster.local
kubectl -n m02-netpol exec client -- wget -qO- -T 3 http://web | grep '<title>'
kubectl -n m02-netpol run tmp --rm -i --restart=Never --image=busybox:1.36 -- wget -qO- -T 3 http://web   # must fail
```

```text
NAME               POD-SELECTOR   AGE
allow-dns-egress   <none>         1m
client-allow-web   app=client     1m
default-deny-all   <none>         1m
web-allow-client   app=web        1m
Server:    10.96.0.10
Address:   10.96.0.10:53

Name:      web.m02-netpol.svc.cluster.local
Address:   10.96.143.22

<title>Welcome to nginx!</title>
wget: download timed out
pod "tmp" deleted
```

**Common mistakes**
- No DNS policy: `wget http://web` fails with `bad address 'web'` even though the client/web rules are right.
- Only the ingress policy on `web`. `client`'s egress is still denied by `default-deny-all`.
- DNS rule with `- podSelector: {}` as the destination. That means *Pods in this namespace*, not kube-system.
- Only UDP 53. Large responses and some resolvers use TCP 53.
- `ports` placed in a separate list item, which opens the ports to everyone or opens kube-system on every port.

**Points (8)**
- 2: `default-deny-all` has podSelector `{}` and both policyTypes.
- 2: `allow-dns-egress` allows UDP+TCP 53 to `kube-system`.
- 1: `web-allow-client` is correct.
- 1: `client-allow-web` is correct.
- 2: behaviour: `client` resolves and reaches `web`, while any other Pod (`tmp`) is blocked.

---

## Question 19 — Repair an Ingress (6%)
*Target time: 5 min*

**Approach:** `kubectl describe ingress` shows a backend that doesn't exist. `kubectl get ingressclass` shows the real class name. There are three faults:

| Field | Broken value | Fixed value |
|---|---|---|
| `spec.ingressClassName` | `nginx-internal` (no such IngressClass) | `nginx` |
| `backend.service.name` | `docs` | `docs-svc` |
| `backend.service.port` | `number: 80` (the container port) | `number: 8080` or `name: http` |

```bash
kubectl -n m02-ingress describe ingress docs-ingress          # Backends: docs:80 (<error: ... "docs" not found>)
kubectl get ingressclass                                      # NAME: nginx
kubectl -n m02-ingress get svc docs-svc                       # 8080/TCP, port name http
kubectl -n m02-ingress edit ingress docs-ingress
```

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: docs-ingress
  namespace: m02-ingress
spec:
  ingressClassName: nginx
  rules:
  - host: docs.m02.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: docs-svc
            port:
              number: 8080
```

**Verify**

```bash
kubectl -n m02-ingress get ingress docs-ingress                    # CLASS nginx, ADDRESS filled in after ~30 s
kubectl -n m02-ingress describe ingress docs-ingress | grep -A4 'Rules:'
curl -s -H 'Host: docs.m02.local' http://localhost:8080/           # kind lab; minikube: http://$(minikube ip)/
kubectl -n m02-ingress run tmp --rm -i --restart=Never --image=busybox:1.36 -- \
  wget -qO- --header 'Host: docs.m02.local' http://ingress-nginx-controller.ingress-nginx.svc/
```

```text
NAME           CLASS   HOSTS            ADDRESS     PORTS   AGE
docs-ingress   nginx   docs.m02.local   localhost   80      50m
Rules:
  Host            Path  Backends
  ----            ----  --------
  docs.m02.local
                  /   docs-svc:8080 (10.244.1.12:80)
m02 docs portal
m02 docs portal
```

**Common mistakes**
- Fixing only the Service name. With class `nginx-internal`, no controller serves the Ingress, so ADDRESS stays empty.
- Backend port 80. Ingress backends reference the **Service** port (8080), not the container port.
- Changing the Service port to 80 instead, which the task forbids.

**Points (6)**
- 2: `ingressClassName: nginx`.
- 2: the backend Service is `docs-svc`.
- 1: the port is `8080` or `http`.
- 1: the end-to-end request returns `m02 docs portal`.

---

## Scoring table

| Q | Task | Domain | Weight | Your score |
|---|---|---|---|---|
| 1 | Modify Dockerfile + OCI archive | Design & Build | 5 | |
| 2 | Job completions/parallelism/backoff/TTL | Design & Build | 5 | |
| 3 | Init container + emptyDir | Design & Build | 5 | |
| 4 | Bare Pod → Deployment + SA without token | Design & Build | 6 | |
| 5 | Blue/green switch | Deployment | 4 | |
| 6 | maxSurge/maxUnavailable + Recreate | Deployment | 5 | |
| 7 | Kustomize overlay | Deployment | 5 | |
| 8 | Helm uninstall/template/install/get values | Deployment | 6 | |
| 9 | Startup probe | Observability | 5 | |
| 10 | CrashLoopBackOff + previous logs | Observability | 5 | |
| 11 | policy/v1beta1 PDB migration | Observability | 3 | |
| 12 | `top nodes` + Warning events | Observability | 2 | |
| 13 | CRD discovery + custom resources | Env/Config/Security | 5 | |
| 14 | ConfigMap update + restart + immutable | Env/Config/Security | 6 | |
| 15 | Secret file with mode 0400 | Env/Config/Security | 5 | |
| 16 | PSA labels + LimitRange + compliant Pod | Env/Config/Security | 8 | |
| 17 | Repair a Service | Services & Networking | 6 | |
| 18 | Default deny + DNS + allow rules | Services & Networking | 8 | |
| 19 | Repair an Ingress | Services & Networking | 6 | |
| | **Total** (pass mark 66) | | **100** | |

## If you missed it → study

| Missed | Topic to revise | Chapter |
|---|---|---|
| Q1 | Dockerfile instructions, podman save formats | [01 — Application Design and Build](../../01-Application-Design-and-Build/README.md) |
| Q2 | Job spec fields (completions, parallelism, backoffLimit, TTL) | [01 — Application Design and Build](../../01-Application-Design-and-Build/README.md) |
| Q3 | Init containers, shared volumes | [01 — Application Design and Build](../../01-Application-Design-and-Build/README.md) |
| Q4 | Workload choice; ServiceAccount token automounting | [01 — Application Design and Build](../../01-Application-Design-and-Build/README.md) · [04 — Environment, Configuration and Security](../../04-Application-Environment-Configuration-and-Security/README.md) |
| Q5 | Blue/green with Service selectors | [02 — Application Deployment](../../02-Application-Deployment/README.md) |
| Q6 | RollingUpdate parameters vs Recreate | [02 — Application Deployment](../../02-Application-Deployment/README.md) |
| Q7 | Kustomize overlays and transformers | [02 — Application Deployment](../../02-Application-Deployment/README.md) |
| Q8 | Helm list/uninstall/template/get values | [02 — Application Deployment](../../02-Application-Deployment/README.md) |
| Q9 | Startup vs liveness vs readiness probes | [03 — Application Observability and Maintenance](../../03-Application-Observability-and-Maintenance/README.md) |
| Q10 | `logs --previous`, CrashLoopBackOff triage | [03 — Application Observability and Maintenance](../../03-Application-Observability-and-Maintenance/README.md) |
| Q11 | Removed APIs; PodDisruptionBudgets | [03 — Application Observability and Maintenance](../../03-Application-Observability-and-Maintenance/README.md) · [06 — Cross-Cutting Skills](../../06-Cross-Cutting-Skills-and-Bonus-Topics/README.md) |
| Q12 | `kubectl top`, events, field selectors | [03 — Application Observability and Maintenance](../../03-Application-Observability-and-Maintenance/README.md) |
| Q13 | CRDs, `api-resources`, `explain` | [04 — Application Environment, Configuration and Security](../../04-Application-Environment-Configuration-and-Security/README.md) |
| Q14 | ConfigMap updates, immutable ConfigMaps | [04 — Application Environment, Configuration and Security](../../04-Application-Environment-Configuration-and-Security/README.md) |
| Q15 | Secret volumes, file modes | [04 — Application Environment, Configuration and Security](../../04-Application-Environment-Configuration-and-Security/README.md) |
| Q16 | Pod Security Admission, LimitRange | [04 — Application Environment, Configuration and Security](../../04-Application-Environment-Configuration-and-Security/README.md) |
| Q17 | Service selectors, targetPort, EndpointSlices | [05 — Services and Networking](../../05-Services-and-Networking/README.md) |
| Q18 | Default deny, DNS egress, two-sided allows | [05 — Services and Networking](../../05-Services-and-Networking/README.md) |
| Q19 | IngressClass, Ingress backends | [05 — Services and Networking](../../05-Services-and-Networking/README.md) |
| Ran out of time | Imperative commands, patching, jsonpath | [06 — Cross-Cutting Skills](../../06-Cross-Cutting-Skills-and-Bonus-Topics/README.md) · [00 — Exam strategy](../../00-Exam-Overview-and-Setup/README.md) |

## Coverage matrix

| Domain | Competency (official wording) | Questions |
|---|---|---|
| Design & Build | Define, build and modify container images | Q1 |
| Design & Build | Choose and use the right workload resource (Deployment, DaemonSet, CronJob, etc.) | Q2 (Job), Q4 (Pod → Deployment) |
| Design & Build | Understand multi-container Pod design patterns (e.g. sidecar, init and others) | Q3 |
| Design & Build | Utilize persistent and ephemeral volumes | Q3 (emptyDir), Q15 (secret volume), Q5 and Q19 (configMap volumes) |
| Deployment | Use Kubernetes primitives to implement common deployment strategies (e.g. blue/green or canary) | Q5, Q6 |
| Deployment | Understand Deployments and how to perform rolling updates | Q6, Q14 (rollout restart) |
| Deployment | Use the Helm package manager to deploy existing packages | Q8 |
| Deployment | Kustomize | Q7 |
| Observability | Understand API deprecations | Q11 |
| Observability | Implement probes and health checks | Q9 |
| Observability | Use built-in CLI tools to monitor Kubernetes applications | Q12, Q11 (PDB status) |
| Observability | Utilize container logs | Q10 |
| Observability | Debugging in Kubernetes | Q10, Q9, Q17, Q19 |
| Env/Config/Security | Discover and use resources that extend Kubernetes (CRD, Operators) | Q13 |
| Env/Config/Security | Understand authentication, authorization and admission control | Q16 (Pod Security Admission, LimitRanger), Q4 (token automount) |
| Env/Config/Security | Understand requests, limits, quotas | Q16 (LimitRange defaults at admission), Q4 |
| Env/Config/Security | Define resource requirements | Q4 (container requests carried into the Deployment), Q16 (default requests/limits via LimitRange) |
| Env/Config/Security | Understand ConfigMaps | Q14 |
| Env/Config/Security | Create & consume Secrets | Q15 |
| Env/Config/Security | Understand ServiceAccounts | Q4 |
| Env/Config/Security | Understand Application Security (SecurityContexts, Capabilities, etc.) | Q16, Q1 (non-root `USER`) |
| Services & Networking | Demonstrate basic understanding of NetworkPolicies | Q18 |
| Services & Networking | Provide and troubleshoot access to applications via services | Q17, Q5 |
| Services & Networking | Use Ingress rules to expose applications | Q19 |
