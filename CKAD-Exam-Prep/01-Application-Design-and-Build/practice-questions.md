# Practice Questions: Application Design and Build

> These are exam-style tasks modelled on the official CNCF curriculum and on task patterns that candidates describe publicly. Real exam questions are confidential under the Linux Foundation candidate agreement; nothing here is a leaked question.

Ordered from most to least frequent. Before each task in the real exam, **switch to the context the task names**. Work in the namespace it names, and write output files exactly where it says. Time yourself with the *Est. time* value.

**One-time lab setup** (your practice cluster, not the exam):

```bash
sudo mkdir -p /opt/course && sudo chown "$USER" /opt/course
for i in $(seq 1 30); do mkdir -p /opt/course/$i; done
for ns in batch logging web storage monitoring data debug; do kubectl create namespace $ns; done
which podman docker            # image tasks: use whichever the task names / is installed
KIT=~/CKAD-Exam-Prep/01-Application-Design-and-Build   # adjust to where this kit lives
```

| # | Task | Frequency | Competency |
|---|---|---|---|
| 1 | Modify Dockerfile, podman build, OCI archive | 🔥 | images |
| 2 | docker build, two tags, push, run, logs | 🔥 | images |
| 3 | CronJob with limits; manual run | 🔥 | workloads |
| 4 | Job completions/parallelism/TTL | 🔥 | workloads |
| 5 | Native sidecar into a Deployment | 🔥 | multi-container |
| 6 | Init container + emptyDir | 🔥 | multi-container / volumes |
| 7 | Static PV + PVC + Pod | 🔥 | volumes |
| 8 | StorageClass + dynamic PVC + default class | 🔥 | volumes |
| 9 | `kubectl run` command vs args | 🔥 | images / pods |
| 10 | DaemonSet incl. control plane | ⚡ | workloads |
| 11 | StatefulSet + headless Service | ⚡ | workloads / volumes |
| 12 | Classic sidecar, keep pod name | ⚡ | multi-container |
| 13 | Adapter | ⚡ | multi-container |
| 14 | Ambassador | ⚡ | multi-container |
| 15 | Memory-backed emptyDir | ⚡ | volumes |
| 16 | hostPath | ⚡ | volumes |
| 17 | Fix Init:CrashLoopBackOff | ⚡ | multi-container |
| 18 | Lifecycle hooks + grace period | ⚡ | pods |
| 19 | Mutable vs immutable pod fields | ⚡ | pods |
| 20 | Deployment → DaemonSet | ⚡ | workloads |
| 21 | Indexed Job | ⚡ | workloads |
| 22 | Job blocked by classic sidecar | ⚡ | multi-container / workloads |
| 23 | Generic ephemeral volume | 🧊 | volumes |
| 24 | podFailurePolicy | 🧊 | workloads |
| 25 | StatefulSet partition (canary) | 🧊 | workloads |
| 26 | Multi-stage build, target, inspect | 🧊 | images |
| 27 | PVC Pending troubleshooting | 🧊 | volumes |
| 28 | ReplicaSet + adoption | 🧊 | workloads |
| 29 | shareProcessNamespace | 🧊 | multi-container |
| 30 | CronJob time zone + suspend | 🧊 | workloads |

---

### Q1. Modify a Dockerfile, build with Podman, save as an OCI archive
**Frequency:** 🔥 High · **Est. time:** 7 min · **Competency:** Define, build and modify container images

The directory `/opt/course/1/image/` contains a `Dockerfile` and `index.html`.

1. Change the Dockerfile so that the image sets `APP_VERSION=2.0` (instead of `1.0`) and runs as user ID `10001`.
2. Build it with **podman** and tag it both `ckad-web:2.0` and `ckad-web:latest`.
3. Save `ckad-web:2.0` in **OCI archive** format to `/opt/course/1/ckad-web-2.0.tar`.
4. Write the image's configured user and environment variables to `/opt/course/1/config.txt`.

<details><summary>Lab setup</summary>

```bash
mkdir -p /opt/course/1/image && cd /opt/course/1/image
cat > Dockerfile <<'EOF'
FROM busybox:1.36
ENV APP_VERSION=1.0
WORKDIR /www
COPY index.html .
EXPOSE 8080
CMD ["httpd", "-f", "-v", "-p", "8080", "-h", "/www"]
EOF
echo 'hello ckad' > index.html
```

</details>

<details><summary>Solution</summary>

```bash
which podman docker
cd /opt/course/1/image
vi Dockerfile
```

```dockerfile
FROM busybox:1.36
ENV APP_VERSION=2.0
WORKDIR /www
COPY index.html .
USER 10001
EXPOSE 8080
CMD ["httpd", "-f", "-v", "-p", "8080", "-h", "/www"]
```

```bash
podman build -t ckad-web:2.0 -t ckad-web:latest .
podman images | grep ckad-web                       # localhost/ckad-web  2.0 / latest
podman save --format oci-archive -o /opt/course/1/ckad-web-2.0.tar ckad-web:2.0
podman image inspect ckad-web:2.0 --format 'User={{.Config.User}} Env={{.Config.Env}}' > /opt/course/1/config.txt
```

Docker variant: `docker build -t ckad-web:2.0 -t ckad-web:latest .` then `docker save -o /opt/course/1/ckad-web-2.0.tar ckad-web:2.0` (Docker Engine 25+ writes an OCI-compliant tarball).

**Verify:**

```bash
tar -tf /opt/course/1/ckad-web-2.0.tar | head -5    # oci-layout, index.json, blobs/sha256/...
cat /opt/course/1/config.txt                         # User=10001 Env=[PATH=... APP_VERSION=2.0]
podman run --rm ckad-web:2.0 id -u                   # 10001 (no ENTRYPOINT, so "id -u" replaces CMD)
```

</details>

---

### Q2. Build with Docker, push two tags, run the container, capture logs
**Frequency:** 🔥 High · **Est. time:** 7 min · **Competency:** Define, build and modify container images

`/opt/course/2/image/` contains a Dockerfile; a registry listens on `localhost:5000`.

1. Build the image with **docker** as `localhost:5000/orders-api` with the tags `v1` and `latest`, and push **both** tags.
2. Run a detached container named `orders-api` from `localhost:5000/orders-api:v1` as user ID `1000`, publishing container port `8080` on host port `18080`.
3. Write the container's logs to `/opt/course/2/logs` and the list of running containers to `/opt/course/2/containers`.

<details><summary>Lab setup</summary>

```bash
docker run -d --name registry -p 5000:5000 registry:2
mkdir -p /opt/course/2/image && cp $KIT/yaml/images/Dockerfile $KIT/yaml/images/index.html /opt/course/2/image/
```

</details>

<details><summary>Solution</summary>

```bash
cd /opt/course/2/image
docker build -t localhost:5000/orders-api:v1 -t localhost:5000/orders-api:latest .
docker push localhost:5000/orders-api:v1
docker push localhost:5000/orders-api:latest        # or: docker push --all-tags localhost:5000/orders-api
docker run -d --name orders-api --user 1000 -p 18080:8080 localhost:5000/orders-api:v1
curl -s localhost:18080 > /dev/null                  # produce a request log line
docker logs orders-api > /opt/course/2/logs 2>&1     # httpd -v logs to stderr, so redirect both streams
docker ps > /opt/course/2/containers
```

Podman variant (same flags; plain-HTTP registry needs `--tls-verify=false`):

```bash
podman build -t localhost:5000/orders-api:v1 -t localhost:5000/orders-api:latest .
podman push --tls-verify=false localhost:5000/orders-api:v1
podman push --tls-verify=false localhost:5000/orders-api:latest
podman run -d --name orders-api --user 1000 -p 18080:8080 localhost:5000/orders-api:v1
podman logs orders-api > /opt/course/2/logs 2>&1
podman ps > /opt/course/2/containers
```

**Verify:**

```bash
curl -s localhost:5000/v2/orders-api/tags/list       # {"name":"orders-api","tags":["latest","v1"]}
docker inspect orders-api --format '{{.Config.User}}'   # 1000
cat /opt/course/2/logs /opt/course/2/containers
```

</details>

---

### Q3. CronJob with history limits, no overlap and a deadline; run it manually
**Frequency:** 🔥 High · **Est. time:** 7 min · **Competency:** Choose and use the right workload resource

In namespace `batch`, create CronJob `log-cleaner`:

- image `busybox:1.36`, command `sh -c 'echo cleaning; date'`, runs **every 15 minutes**;
- keeps **2** successful and **4** failed Jobs; two Jobs must **never run at the same time**;
- each Job is terminated after **40 seconds** and retried at most **2** times; pods use `restartPolicy: Never`.

Save the manifest to `/opt/course/3/cronjob.yaml`. Then start Job `log-cleaner-manual` from the CronJob right away and write its logs to `/opt/course/3/logs.txt`.

<details><summary>Solution</summary>

```bash
kubectl -n batch create cronjob log-cleaner --image=busybox:1.36 --schedule="*/15 * * * *" --restart=Never \
  --dry-run=client -o yaml -- sh -c 'echo cleaning; date' > /opt/course/3/cronjob.yaml
vi /opt/course/3/cronjob.yaml
```

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: log-cleaner
  namespace: batch
spec:
  schedule: "*/15 * * * *"
  concurrencyPolicy: Forbid
  successfulJobsHistoryLimit: 2
  failedJobsHistoryLimit: 4
  jobTemplate:
    spec:
      activeDeadlineSeconds: 40
      backoffLimit: 2
      template:
        spec:
          restartPolicy: Never
          containers:
          - name: log-cleaner
            image: busybox:1.36
            command: ["sh", "-c", "echo cleaning; date"]
```

```bash
kubectl apply -f /opt/course/3/cronjob.yaml
kubectl -n batch create job log-cleaner-manual --from=cronjob/log-cleaner
kubectl -n batch wait --for=condition=complete job/log-cleaner-manual --timeout=60s
kubectl -n batch logs job/log-cleaner-manual > /opt/course/3/logs.txt
```

**Verify:**

```bash
kubectl -n batch get cronjob log-cleaner -o jsonpath='{.spec.schedule} {.spec.concurrencyPolicy} {.spec.successfulJobsHistoryLimit} {.spec.failedJobsHistoryLimit} {.spec.jobTemplate.spec.activeDeadlineSeconds} {.spec.jobTemplate.spec.backoffLimit}{"\n"}'
# */15 * * * * Forbid 2 4 40 2
cat /opt/course/3/logs.txt                           # cleaning + a date
```

</details>

---

### Q4. Job with completions, parallelism, retries and automatic cleanup
**Frequency:** 🔥 High · **Est. time:** 5 min · **Competency:** Choose and use the right workload resource

In namespace `batch`, create Job `batch-worker` (image `busybox:1.36`, command `sh -c 'echo "work done by $(hostname)"; sleep 3'`). It needs **6** successful completions with **3** pods in parallel, fails after **2** retries, and is deleted automatically **120 s** after it finishes. Its pods carry the label `app=batch-worker`. Save the manifest to `/opt/course/4/job.yaml`. When the Job has completed, write the names of its pods to `/opt/course/4/pods.txt`.

<details><summary>Solution</summary>

```bash
kubectl -n batch create job batch-worker --image=busybox:1.36 --dry-run=client -o yaml \
  -- sh -c 'echo "work done by $(hostname)"; sleep 3' > /opt/course/4/job.yaml
vi /opt/course/4/job.yaml
```

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: batch-worker
  namespace: batch
spec:
  completions: 6
  parallelism: 3
  backoffLimit: 2
  ttlSecondsAfterFinished: 120
  template:
    metadata:
      labels:
        app: batch-worker
    spec:
      restartPolicy: Never
      containers:
      - name: batch-worker
        image: busybox:1.36
        command: ["sh", "-c", "echo \"work done by $(hostname)\"; sleep 3"]
```

```bash
kubectl apply -f /opt/course/4/job.yaml
kubectl -n batch wait --for=condition=complete job/batch-worker --timeout=120s
kubectl -n batch get pods -l job-name=batch-worker --no-headers -o custom-columns=:metadata.name > /opt/course/4/pods.txt
```

Collect the pod names **before** the 120 s TTL deletes the Job and its pods.

**Verify:**

```bash
kubectl -n batch get job batch-worker               # COMPLETIONS 6/6
kubectl -n batch get pods -l app=batch-worker       # 6 Completed pods
wc -l < /opt/course/4/pods.txt                      # 6
```

</details>

---

### Q5. Add a native sidecar to an existing Deployment
**Frequency:** 🔥 High · **Est. time:** 7 min · **Competency:** Understand multi-container Pod design patterns

Deployment `web-logs` (namespace `logging`) runs container `app`, which appends access logs to `/var/log/app/access.log`. Add a **native sidecar** named `log-shipper` (image `busybox:1.36`, command `sh -c 'tail -n +1 -F /var/log/app/access.log'`) that starts **before** `app`. Share the logs through an `emptyDir` volume named `logs`, mounted at `/var/log/app` in both containers. Afterwards `kubectl -n logging logs deploy/web-logs -c log-shipper` must show the access log.

<details><summary>Lab setup</summary>

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web-logs
  namespace: logging
spec:
  replicas: 1
  selector:
    matchLabels:
      app: web-logs
  template:
    metadata:
      labels:
        app: web-logs
    spec:
      containers:
      - name: app
        image: busybox:1.36
        command: ["sh", "-c", "mkdir -p /var/log/app; while true; do echo \"$(date) GET /index.html 200\" >> /var/log/app/access.log; sleep 3; done"]
EOF
```

</details>

<details><summary>Solution</summary>

`kubectl -n logging edit deployment web-logs` and change the pod template to:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web-logs
  namespace: logging
spec:
  replicas: 1
  selector:
    matchLabels:
      app: web-logs
  template:
    metadata:
      labels:
        app: web-logs
    spec:
      initContainers:
      - name: log-shipper
        image: busybox:1.36
        restartPolicy: Always              # native sidecar
        command: ["sh", "-c", "tail -n +1 -F /var/log/app/access.log"]
        volumeMounts:
        - name: logs
          mountPath: /var/log/app
      containers:
      - name: app
        image: busybox:1.36
        command: ["sh", "-c", "mkdir -p /var/log/app; while true; do echo \"$(date) GET /index.html 200\" >> /var/log/app/access.log; sleep 3; done"]
        volumeMounts:
        - name: logs
          mountPath: /var/log/app
      volumes:
      - name: logs
        emptyDir: {}
```

**Verify:**

```bash
kubectl -n logging rollout status deploy/web-logs
kubectl -n logging get pods -l app=web-logs         # READY 2/2
kubectl -n logging get deploy web-logs -o jsonpath='{.spec.template.spec.initContainers[0].restartPolicy}{"\n"}'   # Always
kubectl -n logging logs deploy/web-logs -c log-shipper --tail=3
```

</details>

---

### Q6. Init container prepares the content nginx serves
**Frequency:** 🔥 High · **Est. time:** 5 min · **Competency:** Understand multi-container Pod design patterns

In namespace `web`, create Pod `content-pod` with container `web` (image `nginx:1.27`, port 80). Before nginx starts, an init container `prepare` (image `busybox:1.36`) must write the text `prepared by init` into `/work/index.html`. Use an emptyDir volume `html`, mounted at `/work` in `prepare` and at `/usr/share/nginx/html` in `web`. Write the page the pod serves on port 80 to `/opt/course/6/page.txt`.

<details><summary>Solution</summary>

```bash
kubectl -n web run content-pod --image=nginx:1.27 --port=80 --dry-run=client -o yaml > /opt/course/6/pod.yaml
vi /opt/course/6/pod.yaml          # rename container to "web", add initContainers + volume
```

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: content-pod
  namespace: web
spec:
  initContainers:
  - name: prepare
    image: busybox:1.36
    command: ["sh", "-c", "echo 'prepared by init' > /work/index.html"]
    volumeMounts:
    - name: html
      mountPath: /work
  containers:
  - name: web
    image: nginx:1.27
    ports:
    - containerPort: 80
    volumeMounts:
    - name: html
      mountPath: /usr/share/nginx/html
  volumes:
  - name: html
    emptyDir: {}
```

```bash
kubectl apply -f /opt/course/6/pod.yaml
kubectl -n web wait --for=condition=Ready pod/content-pod --timeout=60s
kubectl -n web exec content-pod -c web -- curl -s localhost > /opt/course/6/page.txt
```

**Verify:**

```bash
cat /opt/course/6/page.txt                          # prepared by init
kubectl -n web get pod content-pod -o jsonpath='{.status.initContainerStatuses[0].state.terminated.reason}{"\n"}'   # Completed
```

</details>

---

### Q7. Static PersistentVolume, claim and pod
**Frequency:** 🔥 High · **Est. time:** 7 min · **Competency:** Utilize persistent and ephemeral volumes

1. Create PersistentVolume `pv-logs`: `2Gi`, `ReadWriteOnce`, reclaim policy `Retain`, `storageClassName: manual`, hostPath `/mnt/data/logs` (create the directory if it is missing).
2. In namespace `storage`, create PVC `pvc-logs` requesting `1Gi`, `ReadWriteOnce`, class `manual`.
3. In `storage`, create Pod `logger` (image `busybox:1.36`, command `sh -c 'while true; do date >> /logs/date.log; sleep 5; done'`) that mounts the claim at `/logs`.
4. Write the output of `kubectl get pv pv-logs` to `/opt/course/7/pv.txt`.

<details><summary>Solution</summary>

```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: pv-logs
spec:
  storageClassName: manual
  capacity:
    storage: 2Gi
  accessModes:
  - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  hostPath:
    path: /mnt/data/logs
    type: DirectoryOrCreate
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: pvc-logs
  namespace: storage
spec:
  storageClassName: manual
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
---
apiVersion: v1
kind: Pod
metadata:
  name: logger
  namespace: storage
spec:
  containers:
  - name: logger
    image: busybox:1.36
    command: ["sh", "-c", "while true; do date >> /logs/date.log; sleep 5; done"]
    volumeMounts:
    - name: logs
      mountPath: /logs
  volumes:
  - name: logs
    persistentVolumeClaim:
      claimName: pvc-logs
```

```bash
vi /opt/course/7/storage.yaml && kubectl apply -f /opt/course/7/storage.yaml
kubectl get pv pv-logs > /opt/course/7/pv.txt
```

**Verify:**

```bash
cat /opt/course/7/pv.txt                            # STATUS Bound, CLAIM storage/pvc-logs, RECLAIM Retain
kubectl -n storage get pvc pvc-logs                 # Bound, CAPACITY 2Gi (you get the whole PV)
kubectl -n storage exec logger -- tail -2 /logs/date.log
```

</details>

---

### Q8. StorageClass, dynamic PVC and the default class
**Frequency:** 🔥 High · **Est. time:** 7 min · **Competency:** Utilize persistent and ephemeral volumes

1. Create StorageClass `fast-local`: provisioner `rancher.io/local-path` (use whatever provisioner the task names), reclaim policy `Retain`, binding mode `WaitForFirstConsumer`, volume expansion allowed.
2. In namespace `storage`, create PVC `data-fast` (`500Mi`, `ReadWriteOnce`, class `fast-local`). Write its phase to `/opt/course/8/before.txt`.
3. Create Pod `fast-app` (image `nginx:1.27`) in `storage` that mounts the claim at `/usr/share/nginx/html`. Once it runs, write the PVC phase to `/opt/course/8/after.txt`.
4. Make `fast-local` the **only** default StorageClass.

<details><summary>Solution</summary>

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: fast-local
provisioner: rancher.io/local-path
reclaimPolicy: Retain
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: data-fast
  namespace: storage
spec:
  storageClassName: fast-local
  accessModes: ["ReadWriteOnce"]
  resources:
    requests:
      storage: 500Mi
```

```bash
kubectl apply -f /opt/course/8/sc-pvc.yaml
kubectl -n storage get pvc data-fast -o jsonpath='{.status.phase}{"\n"}' > /opt/course/8/before.txt   # Pending (waiting for first consumer)
```

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: fast-app
  namespace: storage
spec:
  containers:
  - name: fast-app
    image: nginx:1.27
    volumeMounts:
    - name: data
      mountPath: /usr/share/nginx/html
  volumes:
  - name: data
    persistentVolumeClaim:
      claimName: data-fast
```

```bash
kubectl apply -f /opt/course/8/pod.yaml
kubectl -n storage wait --for=condition=Ready pod/fast-app --timeout=90s
kubectl -n storage get pvc data-fast -o jsonpath='{.status.phase}{"\n"}' > /opt/course/8/after.txt    # Bound

kubectl get sc                                      # find the current default, e.g. "standard (default)"
kubectl patch sc standard -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}'
kubectl patch sc fast-local -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
```

**Verify:**

```bash
cat /opt/course/8/before.txt /opt/course/8/after.txt   # Pending / Bound
kubectl get sc                                          # only fast-local shows (default)
kubectl get pv                                          # pvc-<uid> with RECLAIM POLICY Retain, CLAIM storage/data-fast
```

</details>

---

### Q9. Pods with `command` vs `args`
**Frequency:** 🔥 High · **Est. time:** 4 min · **Competency:** Define, build and modify container images

In namespace `default`:

1. Create Pod `busy-cmd` (image `busybox:1.36`) with labels `app=busy` and `tier=tools` and env var `MODE=debug`. Its container **command** (not args) is `sh -c 'echo "mode is $MODE"; sleep 3600'`. Save the manifest to `/opt/course/9/busy-cmd.yaml` before creating the pod.
2. Create Pod `nginx-args` (image `nginx:1.27`) that keeps the image's ENTRYPOINT and replaces its CMD with `nginx-debug -g 'daemon off;'`.
3. Write the first log line of `busy-cmd` to `/opt/course/9/log.txt`.

<details><summary>Solution</summary>

```bash
kubectl run busy-cmd --image=busybox:1.36 --labels=app=busy,tier=tools --env=MODE=debug \
  --dry-run=client -o yaml --command -- sh -c 'echo "mode is $MODE"; sleep 3600' > /opt/course/9/busy-cmd.yaml
kubectl apply -f /opt/course/9/busy-cmd.yaml
kubectl run nginx-args --image=nginx:1.27 -- nginx-debug -g 'daemon off;'     # after "--" without --command = args
kubectl logs busy-cmd | head -1 > /opt/course/9/log.txt
```

**Verify:**

```bash
kubectl get pod busy-cmd -o jsonpath='{.spec.containers[0].command}{"\n"}'    # ["sh","-c","echo \"mode is $MODE\"; sleep 3600"]
kubectl get pod nginx-args -o jsonpath='{.spec.containers[0].command}{" | "}{.spec.containers[0].args}{"\n"}'   #  | ["nginx-debug","-g","daemon off;"]
kubectl get pod nginx-args                          # Running
cat /opt/course/9/log.txt                           # mode is debug
```

</details>

---

### Q10. DaemonSet on every node, including control-plane nodes
**Frequency:** ⚡ Medium · **Est. time:** 6 min · **Competency:** Choose and use the right workload resource

In namespace `monitoring`, create DaemonSet `node-probe` (image `busybox:1.36`) so that exactly one pod runs on **every** node, **control-plane nodes included**. Pods: label `app=node-probe`; env `NODE_NAME` from the node name; command `sh -c 'while true; do echo "$(NODE_NAME) alive"; sleep 60; done'`; requests `cpu: 10m`, `memory: 16Mi`. Use update strategy `RollingUpdate` with `maxUnavailable: 1`. Write the number of scheduled pods to `/opt/course/10/count.txt`.

<details><summary>Solution</summary>

```bash
kubectl -n monitoring create deployment node-probe --image=busybox:1.36 --dry-run=client -o yaml > /opt/course/10/ds.yaml
vi /opt/course/10/ds.yaml          # kind DaemonSet, delete replicas + strategy, add the rest
```

```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: node-probe
  namespace: monitoring
spec:
  selector:
    matchLabels:
      app: node-probe
  updateStrategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 1
  template:
    metadata:
      labels:
        app: node-probe
    spec:
      tolerations:
      - key: node-role.kubernetes.io/control-plane
        operator: Exists
        effect: NoSchedule
      containers:
      - name: probe
        image: busybox:1.36
        command: ["sh", "-c", "while true; do echo \"$(NODE_NAME) alive\"; sleep 60; done"]   # $(NODE_NAME) expanded by Kubernetes
        env:
        - name: NODE_NAME
          valueFrom:
            fieldRef:
              fieldPath: spec.nodeName
        resources:
          requests:
            cpu: 10m
            memory: 16Mi
```

```bash
kubectl apply -f /opt/course/10/ds.yaml
kubectl -n monitoring get ds node-probe -o jsonpath='{.status.currentNumberScheduled}{"\n"}' > /opt/course/10/count.txt
```

**Verify:**

```bash
kubectl get nodes --no-headers | wc -l              # equals the content of count.txt
kubectl -n monitoring get pods -l app=node-probe -o wide   # one per node, incl. the control plane
kubectl -n monitoring logs -l app=node-probe --prefix
```

</details>

---

### Q11. StatefulSet with a headless Service and per-pod storage
**Frequency:** ⚡ Medium · **Est. time:** 8 min · **Competency:** Choose and use the right workload resource

In namespace `data`:

1. Create headless Service `redis-hl`: port `6379` named `redis`, selector `app=redis`.
2. Create StatefulSet `redis`: 3 replicas, image `redis:7.2`, container port `6379` named `redis`, governed by `redis-hl`, volume claim template `data` (`ReadWriteOnce`, `100Mi`, default class) mounted at `/data`.
3. Write the PVC names to `/opt/course/11/pvcs.txt` and the DNS answer for `redis-0.redis-hl.data.svc.cluster.local` to `/opt/course/11/dns.txt`.

<details><summary>Solution</summary>

```yaml
apiVersion: v1
kind: Service
metadata:
  name: redis-hl
  namespace: data
spec:
  clusterIP: None
  selector:
    app: redis
  ports:
  - name: redis
    port: 6379
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: redis
  namespace: data
spec:
  serviceName: redis-hl
  replicas: 3
  selector:
    matchLabels:
      app: redis
  template:
    metadata:
      labels:
        app: redis
    spec:
      containers:
      - name: redis
        image: redis:7.2
        ports:
        - name: redis
          containerPort: 6379
        volumeMounts:
        - name: data
          mountPath: /data
  volumeClaimTemplates:
  - metadata:
      name: data
    spec:
      accessModes: ["ReadWriteOnce"]
      resources:
        requests:
          storage: 100Mi
```

```bash
kubectl apply -f /opt/course/11/redis.yaml
kubectl -n data rollout status sts/redis --timeout=180s
kubectl -n data get pvc --no-headers -o custom-columns=:metadata.name > /opt/course/11/pvcs.txt
kubectl -n data run dns --rm -i --image=busybox:1.36 --restart=Never -- nslookup redis-0.redis-hl.data.svc.cluster.local > /opt/course/11/dns.txt
```

**Verify:**

```bash
cat /opt/course/11/pvcs.txt                          # data-redis-0, data-redis-1, data-redis-2
grep Address /opt/course/11/dns.txt                  # matches the next line
kubectl -n data get pod redis-0 -o jsonpath='{.status.podIP}{"\n"}'
```

</details>

---

### Q12. Classic logging sidecar for an existing pod, keeping its name
**Frequency:** ⚡ Medium · **Est. time:** 6 min · **Competency:** Understand multi-container Pod design patterns

Pod `legacy-app` (namespace `logging`) writes its log only to `/var/log/legacy/app.log` inside container `app`, so `kubectl logs` shows nothing. Without changing the `app` command, add a **regular** (classic) sidecar container `sidecar` (image `busybox:1.36`) that streams the file to its stdout. Use an emptyDir volume `legacy-logs` mounted at `/var/log/legacy` in both containers. The pod must keep the name `legacy-app`. Save the final manifest to `/opt/course/12/legacy-app.yaml`.

<details><summary>Lab setup</summary>

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: legacy-app
  namespace: logging
spec:
  containers:
  - name: app
    image: busybox:1.36
    command: ["sh", "-c", "mkdir -p /var/log/legacy; while true; do echo \"$(date) legacy event\" >> /var/log/legacy/app.log; sleep 2; done"]
EOF
```

</details>

<details><summary>Solution</summary>

Containers cannot be added to a running pod, so export it, edit, and replace it:

```bash
kubectl -n logging get pod legacy-app -o yaml > /opt/course/12/legacy-app.yaml
vi /opt/course/12/legacy-app.yaml    # add the volume, the mount in "app", and the "sidecar" container
kubectl replace --force -f /opt/course/12/legacy-app.yaml
```

The relevant end state (you may drop `status`, `uid`, `resourceVersion`, and so on from the exported file):

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: legacy-app
  namespace: logging
spec:
  containers:
  - name: app
    image: busybox:1.36
    command: ["sh", "-c", "mkdir -p /var/log/legacy; while true; do echo \"$(date) legacy event\" >> /var/log/legacy/app.log; sleep 2; done"]
    volumeMounts:
    - name: legacy-logs
      mountPath: /var/log/legacy
  - name: sidecar
    image: busybox:1.36
    command: ["sh", "-c", "tail -n +1 -F /var/log/legacy/app.log"]
    volumeMounts:
    - name: legacy-logs
      mountPath: /var/log/legacy
  volumes:
  - name: legacy-logs
    emptyDir: {}
```

**Verify:**

```bash
kubectl -n logging get pod legacy-app               # READY 2/2, same name
kubectl -n logging logs legacy-app -c sidecar --tail=3
```

</details>

---

### Q13. Adapter container that converts the app's output
**Frequency:** ⚡ Medium · **Est. time:** 6 min · **Competency:** Understand multi-container Pod design patterns

In namespace `logging`, create Pod `metrics-app` with two containers that share an emptyDir `metrics` at `/var/metrics`:

- `app` (busybox:1.36) appends a line `<epoch-seconds> cpu=<n> mem=<n>` to `/var/metrics/raw.txt` every 5 seconds;
- `adapter` (busybox:1.36) converts every line into two Prometheus-style lines on its stdout: `app_cpu_percent <n>` and `app_memory_mb <n>` (it mounts the volume read-only).

<details><summary>Solution</summary>

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: metrics-app
  namespace: logging
spec:
  containers:
  - name: app
    image: busybox:1.36
    command:
    - sh
    - -c
    - |
      i=0
      while true; do
        i=$((i+1))
        echo "$(date +%s) cpu=$((i*7 % 100)) mem=$((i*13 % 512))" >> /var/metrics/raw.txt
        sleep 5
      done
    volumeMounts:
    - name: metrics
      mountPath: /var/metrics
  - name: adapter
    image: busybox:1.36
    command:
    - sh
    - -c
    - |
      tail -n +1 -F /var/metrics/raw.txt | while read -r ts cpu mem; do
        echo "app_cpu_percent ${cpu#cpu=}"
        echo "app_memory_mb ${mem#mem=}"
      done
    volumeMounts:
    - name: metrics
      mountPath: /var/metrics
      readOnly: true
  volumes:
  - name: metrics
    emptyDir: {}
```

**Verify:**

```bash
kubectl -n logging logs metrics-app -c adapter --tail=4    # app_cpu_percent 7 / app_memory_mb 13 / ...
kubectl -n logging exec metrics-app -c app -- tail -2 /var/metrics/raw.txt
```

</details>

---

### Q14. Ambassador container in front of a remote service
**Frequency:** ⚡ Medium · **Est. time:** 7 min · **Competency:** Understand multi-container Pod design patterns

Namespace `web` contains Service `external-api` (port 80). Create:

1. ConfigMap `proxy-conf` with key `default.conf`: an nginx server that listens on port `9000` and proxies everything to `http://external-api:80`.
2. Pod `client` with container `app` (image `curlimages/curl:8.10.1`, command `sh -c 'while true; do curl -s localhost:9000; sleep 5; done'`) and container `proxy` (image `nginx:1.27-alpine`) with the ConfigMap mounted at `/etc/nginx/conf.d`.

`kubectl -n web logs client -c app` must show responses from `external-api`.

<details><summary>Lab setup</summary>

```bash
kubectl -n web create deployment external-api --image=httpd:2.4 --port=80
kubectl -n web expose deployment external-api --port=80
```

</details>

<details><summary>Solution</summary>

```bash
cat > /opt/course/14/default.conf <<'EOF'
server {
  listen 9000;
  location / {
    proxy_pass http://external-api:80;
  }
}
EOF
kubectl -n web create configmap proxy-conf --from-file=default.conf=/opt/course/14/default.conf
```

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: client
  namespace: web
spec:
  containers:
  - name: app
    image: curlimages/curl:8.10.1
    command: ["sh", "-c", "while true; do curl -s localhost:9000; sleep 5; done"]
  - name: proxy
    image: nginx:1.27-alpine
    ports:
    - containerPort: 9000
    volumeMounts:
    - name: conf
      mountPath: /etc/nginx/conf.d
  volumes:
  - name: conf
    configMap:
      name: proxy-conf
```

**Verify:**

```bash
kubectl -n web get pod client                       # READY 2/2
kubectl -n web logs client -c app --tail=2          # <html><body><h1>It works!</h1></body></html>
```

</details>

---

### Q15. Memory-backed emptyDir shared by two containers
**Frequency:** ⚡ Medium · **Est. time:** 4 min · **Competency:** Utilize persistent and ephemeral volumes

In namespace `web`, create Pod `cache-pod` with container `producer` (busybox:1.36, `sh -c 'while true; do date > /cache/now; sleep 2; done'`) and container `consumer` (busybox:1.36, `sh -c 'while true; do cat /cache/now; sleep 5; done'`). They share an emptyDir `cache` held **in memory** with a size limit of `32Mi`, mounted at `/cache` (read-only in `consumer`). Each container has a memory limit of `64Mi`. Write `df -h /cache` as seen by `consumer` to `/opt/course/15/fs.txt`.

<details><summary>Solution</summary>

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: cache-pod
  namespace: web
spec:
  containers:
  - name: producer
    image: busybox:1.36
    command: ["sh", "-c", "while true; do date > /cache/now; sleep 2; done"]
    resources:
      limits:
        memory: 64Mi
    volumeMounts:
    - name: cache
      mountPath: /cache
  - name: consumer
    image: busybox:1.36
    command: ["sh", "-c", "while true; do cat /cache/now; sleep 5; done"]
    resources:
      limits:
        memory: 64Mi
    volumeMounts:
    - name: cache
      mountPath: /cache
      readOnly: true
  volumes:
  - name: cache
    emptyDir:
      medium: Memory
      sizeLimit: 32Mi
```

```bash
kubectl -n web exec cache-pod -c consumer -- df -h /cache > /opt/course/15/fs.txt
```

**Verify:**

```bash
cat /opt/course/15/fs.txt                           # Filesystem "tmpfs"
kubectl -n web logs cache-pod -c consumer --tail=2  # dates written by producer
kubectl -n web exec cache-pod -c consumer -- touch /cache/x   # fails: Read-only file system
```

</details>

---

### Q16. hostPath volumes with the right type
**Frequency:** ⚡ Medium · **Est. time:** 4 min · **Competency:** Utilize persistent and ephemeral volumes

In namespace `default`, create Pod `node-reader` (image `busybox:1.36`). It mounts the node's `/var/log` **read-only** at `/node-logs` (hostPath type `Directory`) and the node directory `/tmp/node-reader` at `/out` (created if missing). The container writes the listing of `/node-logs` to `/out/listing.txt` and then sleeps for 3600 s. Write the name of the node the pod runs on to `/opt/course/16/node.txt`.

<details><summary>Solution</summary>

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: node-reader
spec:
  containers:
  - name: reader
    image: busybox:1.36
    command: ["sh", "-c", "ls -la /node-logs > /out/listing.txt; sleep 3600"]
    volumeMounts:
    - name: node-logs
      mountPath: /node-logs
      readOnly: true
    - name: out
      mountPath: /out
  volumes:
  - name: node-logs
    hostPath:
      path: /var/log
      type: Directory
  - name: out
    hostPath:
      path: /tmp/node-reader
      type: DirectoryOrCreate
```

```bash
kubectl apply -f /opt/course/16/pod.yaml
kubectl get pod node-reader -o jsonpath='{.spec.nodeName}{"\n"}' > /opt/course/16/node.txt
```

**Verify:**

```bash
kubectl exec node-reader -- head -5 /out/listing.txt
cat /opt/course/16/node.txt                         # the file also exists on that node: /tmp/node-reader/listing.txt
```

</details>

---

### Q17. Fix a pod stuck in `Init:CrashLoopBackOff`
**Frequency:** ⚡ Medium · **Est. time:** 5 min · **Competency:** Understand multi-container Pod design patterns

Pod `broken-init` (namespace `debug`) never becomes Ready. Find the cause. Write the name of the failing container and its error message to `/opt/course/17/reason.txt`. Then fix the pod, keeping its name, so that it reaches `Running`.

<details><summary>Lab setup</summary>

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: broken-init
  namespace: debug
spec:
  initContainers:
  - name: init-setup
    image: busybox:1.36
    command: ["sh", "-c", "ech 'initialising' && touch /work/ready"]
    volumeMounts:
    - name: work
      mountPath: /work
  containers:
  - name: app
    image: nginx:1.27
    volumeMounts:
    - name: work
      mountPath: /work
  volumes:
  - name: work
    emptyDir: {}
EOF
```

</details>

<details><summary>Solution</summary>

```bash
kubectl -n debug get pod broken-init                # Init:Error -> Init:CrashLoopBackOff
kubectl -n debug describe pod broken-init           # init-setup: Terminated, Exit Code 127
kubectl -n debug logs broken-init -c init-setup     # sh: ech: not found
echo "init-setup: sh: ech: not found (exit code 127)" > /opt/course/17/reason.txt

kubectl -n debug get pod broken-init -o yaml > /opt/course/17/pod.yaml
vi /opt/course/17/pod.yaml                          # fix "ech" -> "echo" in the init container command
kubectl replace --force -f /opt/course/17/pod.yaml  # init container commands are immutable
```

**Verify:**

```bash
kubectl -n debug get pod broken-init                # Running 1/1
kubectl -n debug exec broken-init -c app -- ls /work   # ready
```

</details>

---

### Q18. Lifecycle hooks and a longer termination grace period
**Frequency:** ⚡ Medium · **Est. time:** 5 min · **Competency:** Choose and use the right workload resource (Pod spec: lifecycle)

In namespace `default`, create Pod `graceful` (image `nginx:1.27`) with:

- a **postStart** hook that writes `started` to `/usr/share/nginx/html/started.txt`;
- a **preStop** hook that waits 10 seconds using the **sleep action** (no shell command);
- a termination grace period of **45** seconds.

Write the content served at `/started.txt` to `/opt/course/18/started.txt`.

<details><summary>Solution</summary>

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: graceful
spec:
  terminationGracePeriodSeconds: 45
  containers:
  - name: nginx
    image: nginx:1.27
    ports:
    - containerPort: 80
    lifecycle:
      postStart:
        exec:
          command: ["sh", "-c", "echo started > /usr/share/nginx/html/started.txt"]
      preStop:
        sleep:
          seconds: 10
```

```bash
kubectl apply -f /opt/course/18/pod.yaml
kubectl wait --for=condition=Ready pod/graceful --timeout=60s
kubectl exec graceful -- curl -s localhost/started.txt > /opt/course/18/started.txt
```

**Verify:**

```bash
cat /opt/course/18/started.txt                      # started
kubectl get pod graceful -o jsonpath='{.spec.terminationGracePeriodSeconds} {.spec.containers[0].lifecycle.preStop.sleep.seconds}{"\n"}'   # 45 10
time kubectl delete pod graceful                    # roughly 10-11 s (preStop sleep, then a quick nginx stop)
```

</details>

---

### Q19. Change a running pod: image in place, env through replace
**Frequency:** ⚡ Medium · **Est. time:** 5 min · **Competency:** Define, build and modify container images

Pod `api` exists in namespace `default` (container `api`, image `nginx:1.27`).

1. Change its image to `nginx:1.27-alpine` **without** recreating the pod, then write the container's restart count to `/opt/course/19/restarts.txt`.
2. Add the env var `LOG_LEVEL=debug` to the container. The pod must keep the name `api`.

<details><summary>Lab setup</summary>

```bash
kubectl run api --image=nginx:1.27 --labels=app=api
```

</details>

<details><summary>Solution</summary>

```bash
kubectl set image pod/api api=nginx:1.27-alpine      # image is one of the few mutable pod fields
kubectl get pod api -w                               # wait until Running again (Ctrl-C)
kubectl get pod api -o jsonpath='{.status.containerStatuses[0].restartCount}{"\n"}' > /opt/course/19/restarts.txt   # 1

# env is immutable on a pod ("kubectl set env pod/api ..." is rejected): recreate it with the same name
kubectl get pod api -o yaml > /opt/course/19/api.yaml
vi /opt/course/19/api.yaml                           # under the container add:  env: [{name: LOG_LEVEL, value: debug}]
kubectl replace --force -f /opt/course/19/api.yaml
```

**Verify:**

```bash
cat /opt/course/19/restarts.txt                      # 1
kubectl get pod api -o jsonpath='{.spec.containers[0].image}{"\n"}'   # nginx:1.27-alpine
kubectl exec api -- printenv LOG_LEVEL               # debug
```

</details>

---

### Q20. Requirement change: replace a Deployment with a DaemonSet
**Frequency:** ⚡ Medium · **Est. time:** 5 min · **Competency:** Choose and use the right workload resource

`/opt/course/20/collector.yaml` defines Deployment `log-collector` (namespace `monitoring`, 3 replicas), which is running. The requirement has changed: run **exactly one** collector pod per **worker** node (none on control-plane nodes). Replace the Deployment with a DaemonSet `log-collector` with the same labels and container. Save the new manifest to `/opt/course/20/collector-ds.yaml`.

<details><summary>Lab setup</summary>

```bash
kubectl -n monitoring create deployment log-collector --image=busybox:1.36 --replicas=3 --dry-run=client -o yaml \
  -- sh -c 'while true; do echo collecting; sleep 30; done' > /opt/course/20/collector.yaml
kubectl apply -f /opt/course/20/collector.yaml
```

</details>

<details><summary>Solution</summary>

```bash
cp /opt/course/20/collector.yaml /opt/course/20/collector-ds.yaml
vi /opt/course/20/collector-ds.yaml   # kind: DaemonSet; delete "replicas: 3" and "strategy: {}"
kubectl -n monitoring delete deployment log-collector
kubectl apply -f /opt/course/20/collector-ds.yaml
```

```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  labels:
    app: log-collector
  name: log-collector
  namespace: monitoring
spec:
  selector:
    matchLabels:
      app: log-collector
  template:
    metadata:
      labels:
        app: log-collector
    spec:
      containers:
      - command:
        - sh
        - -c
        - while true; do echo collecting; sleep 30; done
        image: busybox:1.36
        name: busybox
        resources: {}
```

No toleration is added, so the control-plane taint keeps the pods off control-plane nodes. On a single-node lab without that taint, the one node gets a pod.

**Verify:**

```bash
kubectl -n monitoring get deploy                    # No resources found
kubectl -n monitoring get ds log-collector          # DESIRED = number of worker nodes
kubectl -n monitoring get pods -l app=log-collector -o wide
```

</details>

---

### Q21. Indexed Job
**Frequency:** ⚡ Medium · **Est. time:** 5 min · **Competency:** Choose and use the right workload resource

In namespace `batch`, create Job `shard-processor` (image `busybox:1.36`) with **4** completions, **2** pods in parallel and completion mode **Indexed**. Each pod prints `processing shard <index>`, where `<index>` is its completion index. Once the Job completes, write the logs of all its pods to `/opt/course/21/shards.log`.

<details><summary>Solution</summary>

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: shard-processor
  namespace: batch
spec:
  completionMode: Indexed
  completions: 4
  parallelism: 2
  template:
    spec:
      restartPolicy: Never
      containers:
      - name: worker
        image: busybox:1.36
        command: ["sh", "-c", "echo \"processing shard $JOB_COMPLETION_INDEX\""]
```

```bash
kubectl apply -f /opt/course/21/job.yaml
kubectl -n batch wait --for=condition=complete job/shard-processor --timeout=120s
kubectl -n batch logs -l job-name=shard-processor --tail=-1 > /opt/course/21/shards.log
```

**Verify:**

```bash
sort /opt/course/21/shards.log                       # processing shard 0 .. 3
kubectl -n batch get pods -l job-name=shard-processor -L batch.kubernetes.io/job-completion-index
```

</details>

---

### Q22. A Job that never completes: make its sidecar native
**Frequency:** ⚡ Medium · **Est. time:** 6 min · **Competency:** Understand multi-container Pod design patterns

Job `report-gen` (namespace `batch`, manifest `/opt/course/22/report-job.yaml`) has stayed active for minutes although its `main` container finished: container `forwarder` never exits. Change the manifest so that `forwarder` becomes a **native sidecar**, recreate the Job, and make sure it completes. Write the `forwarder` logs to `/opt/course/22/forwarder.log`.

<details><summary>Lab setup</summary>

```bash
cat > /opt/course/22/report-job.yaml <<'EOF'
apiVersion: batch/v1
kind: Job
metadata:
  name: report-gen
  namespace: batch
spec:
  backoffLimit: 1
  template:
    spec:
      restartPolicy: Never
      containers:
      - name: main
        image: busybox:1.36
        command: ["sh", "-c", "for i in 1 2 3; do echo \"report line $i\" >> /out/report.log; sleep 2; done"]
        volumeMounts:
        - name: out
          mountPath: /out
      - name: forwarder
        image: busybox:1.36
        command: ["sh", "-c", "tail -n +1 -F /out/report.log"]
        volumeMounts:
        - name: out
          mountPath: /out
      volumes:
      - name: out
        emptyDir: {}
EOF
kubectl apply -f /opt/course/22/report-job.yaml
```

</details>

<details><summary>Solution</summary>

Move `forwarder` from `containers` to `initContainers` and add `restartPolicy: Always`:

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: report-gen
  namespace: batch
spec:
  backoffLimit: 1
  template:
    spec:
      restartPolicy: Never
      initContainers:
      - name: forwarder
        image: busybox:1.36
        restartPolicy: Always            # native sidecar: does not block Job completion
        command: ["sh", "-c", "tail -n +1 -F /out/report.log"]
        volumeMounts:
        - name: out
          mountPath: /out
      containers:
      - name: main
        image: busybox:1.36
        command: ["sh", "-c", "for i in 1 2 3; do echo \"report line $i\" >> /out/report.log; sleep 2; done"]
        volumeMounts:
        - name: out
          mountPath: /out
      volumes:
      - name: out
        emptyDir: {}
```

```bash
vi /opt/course/22/report-job.yaml
kubectl replace --force -f /opt/course/22/report-job.yaml   # the Job pod template is immutable
kubectl -n batch wait --for=condition=complete job/report-gen --timeout=90s
kubectl -n batch logs job/report-gen -c forwarder > /opt/course/22/forwarder.log
```

Edit the **original manifest**. Recreating from `kubectl get job -o yaml` fails unless you strip `spec.selector` and the `controller-uid` labels.

**Verify:**

```bash
kubectl -n batch get job report-gen                 # COMPLETIONS 1/1
cat /opt/course/22/forwarder.log                    # report line 1..3
```

</details>

---

### Q23. Generic ephemeral volume
**Frequency:** 🧊 Low · **Est. time:** 4 min · **Competency:** Utilize persistent and ephemeral volumes

In namespace `storage`, create Pod `scratch-pod` (image `busybox:1.36`, command `sleep 3600`) with a **generic ephemeral volume** `scratch` (`ReadWriteOnce`, `50Mi`, default StorageClass) mounted at `/scratch`. Write the name of the PVC that Kubernetes created to `/opt/course/23/pvc.txt`. Then delete the pod and confirm the PVC is gone.

<details><summary>Solution</summary>

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: scratch-pod
  namespace: storage
spec:
  containers:
  - name: app
    image: busybox:1.36
    command: ["sleep", "3600"]
    volumeMounts:
    - name: scratch
      mountPath: /scratch
  volumes:
  - name: scratch
    ephemeral:
      volumeClaimTemplate:
        spec:
          accessModes: ["ReadWriteOnce"]
          resources:
            requests:
              storage: 50Mi
```

```bash
kubectl apply -f /opt/course/23/pod.yaml
kubectl -n storage wait --for=condition=Ready pod/scratch-pod --timeout=90s
kubectl -n storage get pvc scratch-pod-scratch -o jsonpath='{.metadata.name}{"\n"}' > /opt/course/23/pvc.txt
kubectl -n storage delete pod scratch-pod
```

**Verify:**

```bash
cat /opt/course/23/pvc.txt                          # scratch-pod-scratch  (<pod>-<volume>)
kubectl -n storage get pvc scratch-pod-scratch      # NotFound after the pod is gone (owned by the pod)
```

</details>

---

### Q24. Fail a Job immediately on a non-retryable exit code
**Frequency:** 🧊 Low · **Est. time:** 5 min · **Competency:** Choose and use the right workload resource

In namespace `batch`, create Job `trainer` (image `busybox:1.36`, command `sh -c 'echo "config invalid"; exit 3'`, `backoffLimit: 4`). Exit code `3` means a configuration error, so the Job must fail **immediately** without retries. Pod disruptions (pod condition `DisruptionTarget`) must not count towards the backoff limit. Write the Job's failure reason to `/opt/course/24/reason.txt`.

<details><summary>Solution</summary>

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: trainer
  namespace: batch
spec:
  backoffLimit: 4
  podFailurePolicy:
    rules:
    - action: FailJob
      onExitCodes:
        containerName: trainer
        operator: In
        values: [3]
    - action: Ignore
      onPodConditions:
      - type: DisruptionTarget
  template:
    spec:
      restartPolicy: Never                 # required for podFailurePolicy
      containers:
      - name: trainer
        image: busybox:1.36
        command: ["sh", "-c", "echo \"config invalid\"; exit 3"]
```

```bash
kubectl apply -f /opt/course/24/job.yaml
kubectl -n batch wait --for=condition=failed job/trainer --timeout=60s
kubectl -n batch get job trainer -o jsonpath='{.status.conditions[?(@.type=="Failed")].reason}{"\n"}' > /opt/course/24/reason.txt
```

**Verify:**

```bash
cat /opt/course/24/reason.txt                        # PodFailurePolicy
kubectl -n batch get pods -l job-name=trainer        # exactly ONE pod (no retries)
```

</details>

---

### Q25. StatefulSet canary update with a partition
**Frequency:** 🧊 Low · **Est. time:** 5 min · **Competency:** Choose and use the right workload resource

StatefulSet `web` in namespace `data` runs 3 replicas of container `nginx` (image `nginx:1.27`, pod label `app=nginx-sts`). Roll out `nginx:1.27-alpine` **only to `web-2`** first. Write each pod's name and image (one per line) to `/opt/course/25/canary.txt`. Then complete the rollout to all pods.

<details><summary>Lab setup</summary>

```bash
kubectl -n data apply -f $KIT/yaml/statefulset-with-headless-svc.yaml
kubectl -n data rollout status sts/web
```

</details>

<details><summary>Solution</summary>

```bash
kubectl -n data patch sts web -p '{"spec":{"updateStrategy":{"type":"RollingUpdate","rollingUpdate":{"partition":2}}}}'
kubectl -n data set image sts/web nginx=nginx:1.27-alpine
kubectl -n data rollout status sts/web --timeout=120s    # "partitioned roll out complete"
kubectl -n data get pods -l app=nginx-sts --no-headers \
  -o custom-columns=NAME:.metadata.name,IMAGE:.spec.containers[0].image > /opt/course/25/canary.txt

kubectl -n data patch sts web -p '{"spec":{"updateStrategy":{"rollingUpdate":{"partition":0}}}}'
kubectl -n data rollout status sts/web --timeout=180s
```

**Verify:**

```bash
cat /opt/course/25/canary.txt                        # web-0/web-1 nginx:1.27, web-2 nginx:1.27-alpine
kubectl -n data get pods -l app=nginx-sts -o custom-columns=NAME:.metadata.name,IMAGE:.spec.containers[0].image   # all alpine now
```

</details>

---

### Q26. Multi-stage build with a build argument and a target stage
**Frequency:** 🧊 Low · **Est. time:** 7 min · **Competency:** Define, build and modify container images

`/opt/course/26/` contains `Dockerfile.multistage` and Go sources in `app/`.

1. Build the final image with **podman** as `hello:1.2.0`, passing build argument `VERSION=1.2.0`.
2. Build only the stage named `build` as `hello:builder`.
3. Write the final image's ENTRYPOINT and CMD to `/opt/course/26/entry.txt`, and the sizes of both images to `/opt/course/26/sizes.txt`.
4. Run `hello:1.2.0` detached as container `hello` on host port `18082` (container port 8080). Save the HTTP response to `/opt/course/26/response.txt`.

<details><summary>Lab setup</summary>

```bash
cp -r $KIT/yaml/images/Dockerfile.multistage $KIT/yaml/images/app /opt/course/26/
```

</details>

<details><summary>Solution</summary>

```bash
cd /opt/course/26
podman build -f Dockerfile.multistage --build-arg VERSION=1.2.0 -t hello:1.2.0 .
podman build -f Dockerfile.multistage --target build -t hello:builder .
podman image inspect hello:1.2.0 --format '{{.Config.Entrypoint}} {{.Config.Cmd}}' > /opt/course/26/entry.txt
podman images --format '{{.Repository}}:{{.Tag}} {{.Size}}' | grep hello > /opt/course/26/sizes.txt
podman run -d --name hello -p 18082:8080 hello:1.2.0
curl -s localhost:18082 > /opt/course/26/response.txt
```

Docker variant: the same `build` flags; `docker image inspect hello:1.2.0 --format '{{.Config.Entrypoint}} {{.Config.Cmd}}'`; `docker images --format '{{.Repository}}:{{.Tag}} {{.Size}}'`.

**Verify:**

```bash
cat /opt/course/26/entry.txt                         # [/hello] [-port=8080]
cat /opt/course/26/sizes.txt                         # builder is hundreds of MB, final only a few MB
cat /opt/course/26/response.txt                      # hello from the CKAD study kit (version=1.2.0, host=...)
```

</details>

---

### Q27. Troubleshoot a Pending PVC
**Frequency:** 🧊 Low · **Est. time:** 6 min · **Competency:** Utilize persistent and ephemeral volumes

In namespace `storage`, Pod `reports` is Pending because PVC `reports-pvc` is Pending. PersistentVolume `reports-pv` is `Available` and must be used **unchanged**. Fix the claim so that it binds to `reports-pv` and the pod starts. Write the mismatches you found to `/opt/course/27/mismatches.txt`.

<details><summary>Lab setup</summary>

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: PersistentVolume
metadata:
  name: reports-pv
spec:
  storageClassName: slow
  capacity:
    storage: 1Gi
  accessModes: ["ReadWriteOnce"]
  hostPath:
    path: /tmp/reports
    type: DirectoryOrCreate
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: reports-pvc
  namespace: storage
spec:
  storageClassName: fast
  accessModes: ["ReadWriteMany"]
  resources:
    requests:
      storage: 2Gi
---
apiVersion: v1
kind: Pod
metadata:
  name: reports
  namespace: storage
spec:
  containers:
  - name: app
    image: busybox:1.36
    command: ["sh", "-c", "sleep 3600"]
    volumeMounts:
    - name: data
      mountPath: /reports
  volumes:
  - name: data
    persistentVolumeClaim:
      claimName: reports-pvc
EOF
```

</details>

<details><summary>Solution</summary>

```bash
kubectl -n storage describe pvc reports-pvc          # e.g. storageclass.storage.k8s.io "fast" not found
kubectl get pv reports-pv -o jsonpath='{.spec.storageClassName} {.spec.accessModes} {.spec.capacity.storage}{"\n"}'   # slow ["ReadWriteOnce"] 1Gi
kubectl -n storage get pvc reports-pvc -o jsonpath='{.spec.storageClassName} {.spec.accessModes} {.spec.resources.requests.storage}{"\n"}'   # fast ["ReadWriteMany"] 2Gi
cat > /opt/course/27/mismatches.txt <<'EOF'
storageClassName: PVC fast  vs PV slow
accessModes:      PVC ReadWriteMany vs PV ReadWriteOnce
size:             PVC requests 2Gi vs PV capacity 1Gi
EOF
kubectl -n storage delete pvc reports-pvc            # PVC spec is immutable -> recreate (the unscheduled pod does not block deletion)
```

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: reports-pvc
  namespace: storage
spec:
  storageClassName: slow
  accessModes: ["ReadWriteOnce"]
  resources:
    requests:
      storage: 1Gi
```

```bash
kubectl apply -f /opt/course/27/pvc-fixed.yaml
kubectl -n storage get pod reports -w                # the Pending pod is scheduled once the claim binds
```

If the pod does not recover on its own, recreate it: `kubectl -n storage get pod reports -o yaml > p.yaml && kubectl replace --force -f p.yaml`.

**Verify:**

```bash
kubectl -n storage get pvc reports-pvc               # Bound  reports-pv
kubectl get pv reports-pv                            # Bound  storage/reports-pvc
kubectl -n storage get pod reports                   # Running
```

</details>

---

### Q28. ReplicaSet and pod adoption
**Frequency:** 🧊 Low · **Est. time:** 4 min · **Competency:** Choose and use the right workload resource

In namespace `web`:

1. Create ReplicaSet `frontend`: 3 replicas of `httpd:2.4`, pod labels `app=frontend,tier=web`, selector `app=frontend`.
2. Create a bare pod `stray` (image `nginx:1.27`) with labels `app=frontend,tier=web`. Observe what happens, and write the final number of pods with label `app=frontend` to `/opt/course/28/count.txt`.
3. Scale the ReplicaSet to 5 replicas.

<details><summary>Solution</summary>

```yaml
apiVersion: apps/v1
kind: ReplicaSet
metadata:
  name: frontend
  namespace: web
spec:
  replicas: 3
  selector:
    matchLabels:
      app: frontend
  template:
    metadata:
      labels:
        app: frontend
        tier: web
    spec:
      containers:
      - name: httpd
        image: httpd:2.4
```

```bash
kubectl apply -f /opt/course/28/rs.yaml
kubectl -n web run stray --image=nginx:1.27 --labels=app=frontend,tier=web
kubectl -n web get pods -l app=frontend -w           # stray is adopted, then one surplus pod is deleted (usually stray)
kubectl -n web get pods -l app=frontend --no-headers | wc -l > /opt/course/28/count.txt   # 3
kubectl -n web scale rs frontend --replicas=5
```

**Verify:**

```bash
cat /opt/course/28/count.txt                         # 3
kubectl -n web get rs frontend                       # DESIRED 5, READY 5
```

</details>

---

### Q29. Shared process namespace for cross-container debugging
**Frequency:** 🧊 Low · **Est. time:** 4 min · **Competency:** Understand multi-container Pod design patterns

In namespace `default`, create Pod `pid-share` with containers `nginx` (image `nginx:1.27`) and `debug` (image `busybox:1.36`, command `sleep 3600`) that **share one process namespace**. From the `debug` container, write the process list to `/opt/course/29/ps.txt`. Then read nginx's `/etc/nginx/nginx.conf` through `/proc/<pid>/root` and save it to `/opt/course/29/nginx.conf`.

<details><summary>Solution</summary>

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: pid-share
spec:
  shareProcessNamespace: true
  containers:
  - name: nginx
    image: nginx:1.27
  - name: debug
    image: busybox:1.36
    command: ["sleep", "3600"]
    securityContext:
      capabilities:
        add: ["SYS_PTRACE"]
```

```bash
kubectl apply -f /opt/course/29/pod.yaml
kubectl wait --for=condition=Ready pod/pid-share --timeout=60s
kubectl exec pid-share -c debug -- ps > /opt/course/29/ps.txt
PID=$(kubectl exec pid-share -c debug -- sh -c "ps | grep '[n]ginx: master' | awk '{print \$1}'")
kubectl exec pid-share -c debug -- cat /proc/$PID/root/etc/nginx/nginx.conf > /opt/course/29/nginx.conf
```

**Verify:**

```bash
grep -E 'pause|nginx' /opt/course/29/ps.txt          # /pause (PID 1) plus nginx master/workers
head -3 /opt/course/29/nginx.conf                    # user nginx; worker_processes auto; ...
```

</details>

---

### Q30. CronJob in a specific time zone, created suspended
**Frequency:** 🧊 Low · **Est. time:** 4 min · **Competency:** Choose and use the right workload resource

In namespace `batch`, create CronJob `nightly-backup` (image `busybox:1.36`, command `sh -c 'echo backup done'`). It runs at **02:30 every day, Europe/Berlin time**, keeps **no** failed Jobs, and is created **suspended**. Write its schedule, time zone and suspend flag to `/opt/course/30/cj.txt`, then resume it.

<details><summary>Solution</summary>

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: nightly-backup
  namespace: batch
spec:
  schedule: "30 2 * * *"
  timeZone: "Europe/Berlin"
  failedJobsHistoryLimit: 0
  suspend: true
  jobTemplate:
    spec:
      template:
        spec:
          restartPolicy: OnFailure
          containers:
          - name: nightly-backup
            image: busybox:1.36
            command: ["sh", "-c", "echo backup done"]
```

```bash
kubectl apply -f /opt/course/30/cj.yaml
kubectl -n batch get cronjob nightly-backup -o jsonpath='{.spec.schedule} {.spec.timeZone} {.spec.suspend}{"\n"}' > /opt/course/30/cj.txt
kubectl -n batch patch cronjob nightly-backup -p '{"spec":{"suspend":false}}'
```

**Verify:**

```bash
cat /opt/course/30/cj.txt                            # 30 2 * * * Europe/Berlin true
kubectl -n batch get cronjob nightly-backup          # TIMEZONE Europe/Berlin, SUSPEND False
```

</details>

---

## Must-know summary

- **Images:** `podman|docker build -t name:tag [-f file] .`, add more `-t` flags for more tags, then `push`. `podman save` writes **docker-archive**; add `--format oci-archive` for OCI. `docker save` (Engine 25+) is OCI-compliant. Verify with `tar -tf`. Check the available tools first with `which podman docker`.
- `podman logs x > file 2>&1` captures both streams. Run as non-root with `--user <uid>`. podman calls local builds `localhost/<name>`.
- **command/args:** `command` replaces ENTRYPOINT (and drops CMD); `args` replaces CMD. `kubectl run ... -- a b` gives args, `kubectl run ... --command -- a b` gives command, and `kubectl create deploy|job|cronjob ... -- a b` gives command.
- **Pods** are mostly immutable. Image, labels and annotations change in place; everything else goes through `kubectl replace --force -f` (use the `/tmp/kubectl-edit-*.yaml` copy).
- **Jobs:** `completions`, `parallelism`, `backoffLimit` (default 6), `activeDeadlineSeconds` (wins over backoffLimit), `ttlSecondsAfterFinished`; `restartPolicy` Never|OnFailure is mandatory. Indexed Jobs use `JOB_COMPLETION_INDEX`.
- **CronJobs:** 5-field schedule (quote it), `concurrencyPolicy` Allow|Forbid|Replace, history limits 3/1, `startingDeadlineSeconds`, `timeZone`, `suspend`. Test with `kubectl create job x --from=cronjob/y`.
- **DaemonSet** = Deployment YAML with `kind` changed and `replicas` + `strategy` deleted; add the control-plane toleration when asked.
- **StatefulSet** needs a headless Service (`clusterIP: None`) plus `serviceName`. `volumeClaimTemplates` produce PVC `<claim>-<sts>-<ordinal>`. PVCs survive deletion. Use `partition` for canaries.
- **Init containers** run sequentially to completion. A **native sidecar** is `initContainers[]` + `restartPolicy: Always`: it starts first, stops last, and does not block Jobs. A classic sidecar is just another container.
- Always use **`-c <container>`** with logs and exec. An init failure shows as `Init:CrashLoopBackOff`: run `kubectl logs <pod> -c <init>`.
- **emptyDir** is per pod and survives container restarts. `medium: Memory` counts against memory limits; set `sizeLimit`. **hostPath** `type`: DirectoryOrCreate, Directory, FileOrCreate (no parent dirs), File, Socket, ...
- **PV/PVC binding** needs matching `storageClassName`, all requested access modes, capacity ≥ request, and the same volumeMode. PVs and StorageClasses are cluster-scoped; PVCs are namespaced (the pod's namespace).
- **`storageClassName: ""` ≠ omitted.** Empty means no class and no dynamic provisioning; omitted means the default class. `WaitForFirstConsumer` → Pending until a pod uses the PVC, which is normal.
- Default StorageClass = annotation `storageclass.kubernetes.io/is-default-class: "true"`. Dynamic PVs inherit the class `reclaimPolicy` (default `Delete`). A `Released` PV needs its `claimRef` removed before it can be reused.
