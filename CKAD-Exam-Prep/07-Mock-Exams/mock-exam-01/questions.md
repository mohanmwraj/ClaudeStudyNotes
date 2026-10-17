# CKAD Mock Exam 01 — Foundations

| Duration | Questions | Pass mark | Total weight |
|---|---|---|---|
| 120 min | 19 | 66% | 100% |

> **How to take this exam**
> 1. Build a practice cluster: [00 — Exam Overview and Setup](../../00-Exam-Overview-and-Setup/README.md) (lab guide: [02-local-practice-lab-setup.md](../../00-Exam-Overview-and-Setup/02-local-practice-lab-setup.md)). Include metrics-server, an ingress controller with IngressClass `nginx`, and a NetworkPolicy-enforcing CNI.
> 2. From this folder run `bash setup.sh`. Read its summary, which warns about any missing optional component.
> 3. Start a **120-minute** timer.
> 4. Keep only kubernetes.io/docs, kubernetes.io/blog and helm.sh/docs open.
> 5. When the timer stops, grade yourself with [solutions.md](solutions.md). Afterwards run `bash cleanup.sh`.
>
> **Real exam vs. this lab:** here everything runs against one local cluster. In the real exam, which currently runs Kubernetes v1.37, every task names a host. You run `ssh <host>`, solve the task there, then `exit` back to the base machine; nested ssh is not supported. The hosts provide `kubectl` (with the `k` alias and completion), `yq`, `curl`, `wget` and `man`. `jq` is not guaranteed, so none of these solutions use it. The Kustomize site (kubectl.docs.kubernetes.io) is **not** on the allowed list; use the kubernetes.io Kustomize task page instead. Details: [00 — Exam Overview and Setup](../../00-Exam-Overview-and-Setup/README.md).

> **Note:** These are exam-style tasks modelled on the official CNCF curriculum and on task patterns that candidates describe publicly. Real exam questions are confidential under the Linux Foundation candidate agreement; nothing here is a leaked question.

**Ground rules**
- Each task names its namespace, so use `-n <namespace>` every time. On the real exam each task also names the host to `ssh` into first, as described in the box above.
- Output files go under `~/ckad-mocks/exam-01/qNN/`; setup.sh creates these directories. Write exactly the content requested, with no extra text.
- Use the images exactly as given. Never use `:latest`.
- Unless a task says otherwise, objects you create must end up Running/Ready (Pods, Deployments) or Complete (Jobs).
- This paper is the **foundations** level: most tasks are single-step, and a few combine two or three steps.

---

## Question 1 — Build and archive a container image
**Weight:** 4% · **Domain:** Application Design and Build · **Namespace:** — (local machine, no cluster objects)

The directory `~/ckad-mocks/exam-01/q01/` contains a `Dockerfile` and an `index.html`.

- Build an image from this directory with podman (docker is also accepted), named and tagged `m01-webapp:1.0`.
- Save the image as a **docker-archive** tarball at `~/ckad-mocks/exam-01/q01/m01-webapp-1.0.tar`.
- Do not modify the Dockerfile and do not push the image.

---

## Question 2 — Scheduled clean-up job
**Weight:** 6% · **Domain:** Application Design and Build · **Namespace:** `m01-batch`

Create a CronJob named `log-cleaner`:

- schedule: every 5 minutes (`*/5 * * * *`)
- a single container named `cleaner`, image `busybox:1.36`, command `sh -c 'echo cleaning old logs; date'`
- Pod restart policy `OnFailure`
- keep the **2** most recent successful Jobs and **1** failed Job

Then trigger it right away, without waiting for the schedule, by creating a Job named `log-cleaner-manual` **from the CronJob**. Once that Job has completed, write its logs to `~/ckad-mocks/exam-01/q02/manual.log`.

---

## Question 3 — Sidecar log shipper
**Weight:** 6% · **Domain:** Application Design and Build · **Namespace:** `m01-sidecar`

Create a Pod named `web-logger` with two **regular** containers (no init containers) that share an `emptyDir` volume named `logs`:

| Container | Image | Command | Volume mount |
|---|---|---|---|
| `app` | `busybox:1.36` | `sh -c 'while true; do echo "$(date) app heartbeat" >> /var/log/app/app.log; sleep 5; done'` | `logs` at `/var/log/app` |
| `log-shipper` | `busybox:1.36` | `sh -c 'tail -n +1 -F /var/log/app/app.log'` | `logs` at `/var/log/app`, **read-only** |

Running `kubectl logs web-logger -c log-shipper` must show the heartbeat lines.

---

## Question 4 — Static persistent storage
**Weight:** 5% · **Domain:** Application Design and Build · **Namespace:** `m01-storage` (the PersistentVolume is cluster-scoped)

- Create a PersistentVolume `m01-pv-data` with capacity `1Gi`, access mode `ReadWriteOnce`, reclaim policy `Retain`, storageClassName `manual` and hostPath `/tmp/m01-data` (type `DirectoryOrCreate`).
- Create a PersistentVolumeClaim `data-claim` that requests `500Mi` with access mode `ReadWriteOnce` and binds to **this** PersistentVolume. It must not get a dynamically provisioned volume.
- Create a Pod `data-writer` with container `writer` (image `busybox:1.36`) that mounts the claim at `/data` and runs `sh -c 'echo "persisted at $(date)" > /data/out.txt; sleep 3600'`.

---

## Question 5 — Rolling update and rollback
**Weight:** 6% · **Domain:** Application Deployment · **Namespace:** `m01-rollout`

The Deployment `frontend` runs image `nginx:1.27-alpine` in its container `nginx`.

1. Perform a rolling update of container `nginx` to image `nginx:1.27`, and record the change-cause `bump to nginx:1.27` so it shows up in the rollout history.
2. Wait for the rollout to finish, then write the rollout history of `frontend` to `~/ckad-mocks/exam-01/q05/history.txt`.
3. QA rejects the release. Roll `frontend` back to the previous revision and make sure the rollback completes.

---

## Question 6 — Canary release
**Weight:** 6% · **Domain:** Application Deployment · **Namespace:** `m01-canary`

The Service `checkout` currently sends all traffic to the 8 Pods of Deployment `checkout-v1`. Release a canary as follows:

- Create a Deployment `checkout-v2` with image `httpd:2.4`, container name `checkout` and container port `80`.
- The existing Service `checkout` must send about **20%** of requests to `checkout-v2` and 80% to `checkout-v1`.
- `checkout-v2` Pods must carry the label `version: v2`, and the selector of `checkout-v2` must not match any `checkout-v1` Pod.
- Do not modify the Service `checkout` or the Deployment `checkout-v1`.

---

## Question 7 — Install a Helm chart
**Weight:** 5% · **Domain:** Application Deployment · **Namespace:** `m01-helm` (does not exist yet)

A Helm chart is available at `~/ckad-mocks/exam-01/q07/shop-chart`.

- Install it as release `m01-shop` in namespace `m01-helm`. The install itself must create the namespace.
- Override chart values so that the release runs **2 replicas** with image tag **`1.27-alpine`**, and the Deployment it creates is named exactly **`shop-web`**. Inspect the chart's values to find the right keys.
- Write the list of Helm releases in **all** namespaces to `~/ckad-mocks/exam-01/q07/releases.txt`.

---

## Question 8 — Kustomize: add a resource and a common label
**Weight:** 3% · **Domain:** Application Deployment · **Namespace:** `m01-kustomize`

The directory `~/ckad-mocks/exam-01/q08/` contains `kustomization.yaml`, `deployment.yaml` and `service.yaml`.

- Edit **only** `kustomization.yaml` so that:
  - the Service from `service.yaml` is deployed too
  - every resource gets the label `app.kubernetes.io/part-of: notes-app` in its metadata, **without** any selector changing
- Write the rendered output to `~/ckad-mocks/exam-01/q08/rendered.yaml`.
- Apply the kustomization to the cluster.

---

## Question 9 — Readiness and liveness probes
**Weight:** 5% · **Domain:** Application Observability and Maintenance · **Namespace:** `m01-health`

Add the following probes to container `api` of the existing Deployment `api`:

| Probe | Handler | Timing |
|---|---|---|
| readiness | HTTP GET `/` on port `80` | initial delay 5 s, period 10 s |
| liveness | exec `cat /usr/share/nginx/html/index.html` | initial delay 10 s, period 15 s, failure threshold 3 |

Do not change anything else in the Deployment. All replicas must be Ready afterwards.

---

## Question 10 — Migrate a deprecated manifest
**Weight:** 4% · **Domain:** Application Observability and Maintenance · **Namespace:** `m01-legacy`

The manifest `~/ckad-mocks/exam-01/q10/legacy-deploy.yaml` was written for an old cluster and no longer applies.

- Write the API version that **this cluster** serves for Deployments to `~/ckad-mocks/exam-01/q10/api-version.txt`, as one line in `group/version` form.
- Fix the manifest **in place** so that it applies on this cluster, then apply it. Keep its name, namespace, labels, replica count and container spec. Both replicas must run.

---

## Question 11 — Resource usage and container logs
**Weight:** 5% · **Domain:** Application Observability and Maintenance · **Namespace:** `m01-monitor`

- Write the name of the Pod in namespace `m01-monitor` that currently uses the **most CPU** to `~/ckad-mocks/exam-01/q11/top-cpu.txt` (the name only).
- Pod `payment` runs two containers. Write the logs of its container `audit` (that container only) to `~/ckad-mocks/exam-01/q11/audit.log`.
- Write the number of lines in that log that contain `DENIED` to `~/ckad-mocks/exam-01/q11/denied-count.txt` (the number only).

---

## Question 12 — ConfigMap and Secret for an application
**Weight:** 7% · **Domain:** Application Environment, Configuration and Security · **Namespace:** `m01-config`

- Create a ConfigMap `shop-config` that contains the key `APP_COLOR` with value `blue`, plus the file `~/ckad-mocks/exam-01/q12/app.properties` under the key `app.properties`.
- Create a Secret `shop-db` with the key `password` and the value `S3cure-Pa55`.
- Create a Pod `shop` (container `shop`, image `nginx:1.27-alpine`) with:
  - an environment variable `APP_COLOR` taken from ConfigMap key `APP_COLOR`
  - an environment variable `DB_PASSWORD` taken from Secret key `password`
  - the ConfigMap mounted as a volume at `/etc/shop`, so that `/etc/shop/app.properties` exists

---

## Question 13 — RBAC for a ServiceAccount
**Weight:** 6% · **Domain:** Application Environment, Configuration and Security · **Namespace:** `m01-rbac`

- Create a ServiceAccount `pod-reader-sa`.
- Create a Role `pod-reader` that allows only the verbs `get`, `list` and `watch` on `pods`.
- Bind the Role to the ServiceAccount with a RoleBinding `pod-reader-binding`.
- Use `kubectl auth can-i` while impersonating the ServiceAccount and write the answers to these files, each containing only `yes` or `no`:
  - can it **list** pods in `m01-rbac`? → `~/ckad-mocks/exam-01/q13/can-list.txt`
  - can it **delete** pods in `m01-rbac`? → `~/ckad-mocks/exam-01/q13/can-delete.txt`

---

## Question 14 — Security context
**Weight:** 4% · **Domain:** Application Environment, Configuration and Security · **Namespace:** `m01-secure`

Create a Pod `secure-app` with one container `app` (image `busybox:1.36`, command `sh -c 'sleep 3600'`) such that:

- at **Pod level**, all containers run as user ID `1000` and group ID `3000`, and the filesystem group is `2000`
- an `emptyDir` volume named `data` is mounted at `/data`
- container `app` cannot escalate privileges and gets the added Linux capabilities `NET_ADMIN` and `SYS_TIME`

---

## Question 15 — Quota troubleshooting
**Weight:** 5% · **Domain:** Application Environment, Configuration and Security · **Namespace:** `m01-quota`

The Deployment `reporting` (2 replicas) has no running Pods.

- Find the object that prevents the Pods from being created, and write its name to `~/ckad-mocks/exam-01/q15/blocker.txt`.
- **Without modifying that object**, fix `reporting` so that both replicas run. Container `reporter` must request `250m` CPU and `256Mi` memory, with limits of `500m` CPU and `512Mi` memory.

---

## Question 16 — Use a custom resource
**Weight:** 3% · **Domain:** Application Environment, Configuration and Security · **Namespace:** `m01-crd`

The cluster has a CustomResourceDefinition installed for `Backup` objects (API group `m01.example.com`). Create a `Backup` named `nightly-db` with:

- `spec.schedule`: `0 2 * * *`
- `spec.retentionDays`: `7`
- `spec.target`: `postgres-main`

---

## Question 17 — Expose an application with Services
**Weight:** 6% · **Domain:** Services and Networking · **Namespace:** `m01-svc`

The Deployment `catalog` serves HTTP on container port 80.

- Create a ClusterIP Service `catalog-svc` that exposes the Pods of Deployment `catalog`, and only those, on port `8080`.
- Create a NodePort Service `catalog-nodeport` that exposes the same Pods on port `80`. Let Kubernetes choose the node port.
- Write the node port assigned to `catalog-nodeport` to `~/ckad-mocks/exam-01/q17/nodeport.txt` (the number only).

---

## Question 18 — Path-based Ingress
**Weight:** 7% · **Domain:** Services and Networking · **Namespace:** `m01-ingress`

The Services `web-svc` (port 80) and `api-svc` (port 8080) already exist. Create an Ingress `shop-ingress` that uses IngressClass `nginx` for host `shop.m01.local`:

- requests whose path begins with `/api` → Service `api-svc`, port 8080
- every other request (`/`) → Service `web-svc`, port 80
- both rules use `pathType: Prefix`

---

## Question 19 — Restrict access with a NetworkPolicy
**Weight:** 7% · **Domain:** Services and Networking · **Namespace:** `m01-netpol`

The Pods `frontend`, `backend` and `other` run in `m01-netpol`, and the Service `backend` fronts the `backend` Pod. Create a NetworkPolicy named `backend-allow-frontend` that meets all of these:

- Pods labelled `app=backend` accept incoming traffic **only** from Pods labelled `app=frontend` in the **same namespace**, and only on TCP port 80.
- All other incoming traffic to `backend` is denied, including traffic from Pods labelled `app=frontend` in other namespaces (namespace `m01-netpol-ext` has one).
- Outgoing traffic is not restricted.

Do not modify the Pods.

---

*End of exam. Stop the timer, then grade yourself with [solutions.md](solutions.md).*
