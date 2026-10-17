# CKAD Mock Exam 03 — Intermediate

| Duration | Questions | Pass mark | Total weight |
|---|---|---|---|
| 120 min | 19 | 66% | 100% |

> **How to take this exam**
>
> 1. Build a practice cluster (kind or minikube) as described in [Exam overview and lab setup](../../00-Exam-Overview-and-Setup/README.md). For full coverage add an ingress controller (IngressClass `nginx`), a CNI that enforces NetworkPolicies, `helm`, `openssl` and `podman` (or `docker`).
> 2. From this folder run `bash setup.sh`. It creates the namespaces `m03-*`, the pre-existing (partly broken) objects and the working files under `~/ckad-mocks/exam-03/`, and prints a WARNING for every optional component it cannot find.
> 3. Start a 120-minute timer.
> 4. Keep only kubernetes.io/docs, kubernetes.io/blog and helm.sh/docs open in your browser (the Kustomize and Podman sites are not allowed in the real exam).
> 5. When the timer ends, stop and grade yourself with [solutions.md](solutions.md). Run `bash cleanup.sh` afterwards.
>
> **How the real exam differs:** it currently runs Kubernetes v1.37 and each task names a host: you `ssh <host>` first, solve the task there, then `exit` back to the base machine (nested ssh is not supported). The guaranteed tools on the exam hosts are `kubectl` (with the `k` alias and completion), `yq`, `curl`, `wget` and `man` — `jq` and `tmux` are not listed, so none of the solutions depend on them.

*These are exam-style tasks modelled on the official CNCF curriculum and on task patterns that candidates describe publicly. Real exam questions are confidential under the Linux Foundation candidate agreement; nothing here is a leaked question.*

**Ground rules for this mock**

- Every task names its namespace. Objects created in the wrong namespace score zero.
- Output files go under `~/ckad-mocks/exam-03/qNN/` (the directories already exist).
- Tasks are independent: you can solve them in any order. Flag long ones and come back.
- Here everything runs against one local cluster. In the real exam, start every task with the `ssh <host>` line it gives you and `exit` when done; practise the habit of checking `kubectl config current-context` and the namespace before you type.
- Allowed images: `nginx:1.27`, `nginx:1.27-alpine`, `busybox:1.36`, `httpd:2.4`, `redis:7.2`, `postgres:16`, `curlimages/curl:8.10.1`, `registry.k8s.io/pause:3.10`.

---

## Question 1 — Liveness probe on the wrong port

**Weight:** 3% · **Domain:** Application Observability and Maintenance · **Namespace:** `m03-probes`

The Pods of Deployment `pricing` keep restarting.

- Write every event with reason `Unhealthy` from namespace `m03-probes` to `~/ckad-mocks/exam-03/q01/unhealthy-events.txt`.
- Fix the **liveness** probe of container `pricing` so that it performs an HTTP GET on `/` against the port the nginx server really listens on.
- Do not change the readiness probe, any other probe setting (delays, period, thresholds) or the image.
- End state: the rollout is complete and the new Pods stay at 0 restarts.

---

## Question 2 — Node agent on every node

**Weight:** 4% · **Domain:** Application Design and Build · **Namespace:** `m03-ds`

Create a DaemonSet named `node-agent`:

- Pod label `app=node-agent`, also used as the selector.
- One container named `agent`, image `busybox:1.36`, running exactly this command:

  ```text
  sh -c 'while true; do echo "agent alive on $NODE_NAME"; sleep 30; done'
  ```

- Environment variable `NODE_NAME` filled with the name of the node the Pod runs on, using the Downward API (not hard-coded).
- Resource requests `cpu: 10m` and `memory: 16Mi`.
- The agent must run on **every** node of the cluster, including control-plane nodes that carry the taint `node-role.kubernetes.io/control-plane:NoSchedule`. Do not use `nodeName` or `nodeSelector`.

---

## Question 3 — Helm: values file, upgrade, rollback

**Weight:** 6% · **Domain:** Application Deployment · **Namespace:** `m03-helm`

A local chart exists at `~/ckad-mocks/exam-03/q03/webapp`. Do not modify any file inside the chart directory.

1. Using `helm`, write the chart's default values to `~/ckad-mocks/exam-03/q03/default-values.yaml`.
2. Create the values file `~/ckad-mocks/exam-03/q03/prod-values.yaml` that sets the replica count to `2` and the image tag to `1.27-alpine` (find the key names in the default values).
3. Install the chart as release `storefront` in namespace `m03-helm` using that values file and no `--set` flags.
4. Upgrade `storefront` so that it runs `4` replicas. All other settings from `prod-values.yaml` must remain in effect.
5. The upgrade was a mistake: roll `storefront` back to revision `1`.
6. Write the release history to `~/ckad-mocks/exam-03/q03/history.txt`.

End state: release `storefront` is `deployed` at revision 3 and its Deployment runs 2 replicas of `nginx:1.27-alpine`.

---

## Question 4 — ServiceAccount: fix a 403 and add an image pull secret

**Weight:** 7% · **Domain:** Application Environment, Configuration and Security · **Namespace:** `m03-rbac`

Deployment `inventory-sync` calls the Kubernetes API to list the ConfigMaps of its own namespace and logs `HTTP 403` every 10 seconds. The ServiceAccount `inventory` and the Role `configmap-reader` were prepared for this workload.

- Create a RoleBinding named `inventory-configmap-reader` that grants Role `configmap-reader` to ServiceAccount `inventory`.
- Create a docker-registry Secret named `regcred` for server `registry.m03.example:5000`, username `robot`, password `Rob0t-Pass`, email `robot@m03.example`.
- Attach `regcred` to ServiceAccount `inventory` so that every Pod using this ServiceAccount receives it as an image pull secret automatically. Do **not** add `imagePullSecrets` to the Deployment.
- Make `inventory-sync` run as ServiceAccount `inventory`.
- Do not create, modify or delete any Role or ClusterRole, and do not create or delete ServiceAccounts.
- End state: the new Pod logs `HTTP 200` and its `spec.imagePullSecrets` contains `regcred`.

---

## Question 5 — Native sidecar log forwarder with a RAM-backed volume

**Weight:** 6% · **Domain:** Application Design and Build · **Namespace:** `m03-sidecar`

Create a Pod named `payments`:

- A volume named `app-logs`: an `emptyDir` stored in memory (tmpfs) and limited to `32Mi`.
- Container `app`, image `busybox:1.36`, mounts `app-logs` at `/var/log/app` and runs exactly:

  ```text
  sh -c 'i=0; while true; do i=$((i+1)); echo "$(date +%T) payment $i processed" >> /var/log/app/payments.log; sleep 2; done'
  ```

- A log forwarder named `log-forwarder`, image `busybox:1.36`, that mounts `app-logs` **read-only** at `/var/log/app` and runs `tail -F /var/log/app/payments.log`.
- `log-forwarder` must be a **native sidecar**: it is started before `app`, keeps running for the whole life of the Pod and is restarted if it exits.

End state: the Pod is Running with both containers ready, and `kubectl logs payments -c log-forwarder -n m03-sidecar` shows the payment lines.

---

## Question 6 — Make existing NetworkPolicies work by labelling Pods

**Weight:** 6% · **Domain:** Services and Networking · **Namespace:** `m03-netpol`

Namespace `m03-netpol` contains the Pods `frontend`, `api` and `db`, the Services `api` (port 80) and `db` (port 6379), and three NetworkPolicies owned by the security team.

Without creating, editing or deleting any NetworkPolicy or Service, and without removing or changing existing labels, **add** labels to the Pods so that:

- `frontend` can reach `api` on TCP port 80,
- `api` can reach `db` on TCP port 6379,
- `frontend` can **not** reach `db`.

Read the policies to find out which labels they expect.

---

## Question 7 — Batch several changes into one rollout

**Weight:** 5% · **Domain:** Application Deployment · **Namespace:** `m03-rollout`

Deployment `api-gateway` (container `gateway`) is at revision 1. Ship all of the following changes as **one single new revision**:

- image `nginx:1.27-alpine`
- environment variable `GATEWAY_MODE=strict`
- requests `cpu: 50m`, `memory: 64Mi` and limits `cpu: 200m`, `memory: 128Mi`
- change-cause `alpine image, strict mode, resources`

Pause the rollout before the first change and resume it after the last one. When the rollout has finished, write the output of `kubectl rollout history` for this Deployment to `~/ckad-mocks/exam-03/q07/history.txt`. It must list exactly two revisions.

---

## Question 8 — Downward API and a Guaranteed Pod

**Weight:** 5% · **Domain:** Application Environment, Configuration and Security · **Namespace:** `m03-downward`

Create a Pod named `meta-probe`:

- Labels `app=meta-probe` and `tier=diagnostics`, annotation `owner=team-sre`.
- Container `probe`, image `busybox:1.36`, command `sh -c 'while true; do sleep 3600; done'`.
- Environment variable `POD_IP` set to the Pod's IP address, and `MEM_LIMIT_MI` set to the container's memory limit expressed in mebibytes (the value must be `64`). Use the Downward API for both.
- A Downward API volume named `podinfo` mounted at `/etc/podinfo` that exposes the Pod's labels in the file `labels` and its annotations in the file `annotations`.
- CPU `100m` and memory `64Mi` configured so that the Pod gets the QoS class **Guaranteed**.

Then write the QoS class reported by the API server to `~/ckad-mocks/exam-03/q08/qos.txt`, and the content of `/etc/podinfo/labels`, read from inside the container, to `~/ckad-mocks/exam-03/q08/labels.txt`.

---

## Question 9 — Debug a shell-less container

**Weight:** 4% · **Domain:** Application Observability and Maintenance · **Namespace:** `m03-debug`

Pod `distroless-api` (container `api`) uses a minimal image without a shell, so `kubectl exec` is of no use.

- Add an ephemeral debug container named `debugger` with image `busybox:1.36` that can see the processes of container `api`.
- From it, find the full command line of the main process of `api` and the numeric UID that process runs as.
- Write exactly two lines to `~/ckad-mocks/exam-03/q09/findings.txt`: `cmd=<full command line>` and `uid=<uid>`.
- Do not delete, recreate or restart the Pod (its UID must stay the same and its restart count must stay 0).

---

## Question 10 — Fix and harden a container image

**Weight:** 4% · **Domain:** Application Design and Build · **Namespace:** none (local image build)

The build context is `~/ckad-mocks/exam-03/q10/` (`Dockerfile`, `index.html`, `.dockerignore`, `NOTES.md`). Use `podman` (or `docker`).

- The build currently fails. Fix the cause without renaming or moving `index.html` and without removing the `COPY` instruction.
- Change the `Dockerfile` so that the image sets `APP_MODE=prod`, runs as UID `1001`, serves HTTP on port `8080` and declares that port, and uses the exec (JSON array) form for `CMD`.
- Build the image as `m03-motd:1.1`.
- Write the output of the following command (or its `docker image inspect` equivalent) to `~/ckad-mocks/exam-03/q10/image-config.txt`:

  ```text
  podman image inspect m03-motd:1.1 --format '{{.Config.User}} {{.Config.ExposedPorts}} {{.Config.Cmd}}'
  ```

---

## Question 11 — Migrate a legacy Ingress

**Weight:** 6% · **Domain:** Services and Networking · **Namespace:** `m03-legacy`

`~/ckad-mocks/exam-03/q11/legacy-ingress.yaml` was written for an old cluster and can no longer be applied. The Services `shop-frontend` and `shop-api` already exist.

- Write the API versions of the group `networking.k8s.io` that your cluster serves to `~/ckad-mocks/exam-03/q11/api-versions.txt`.
- Create `~/ckad-mocks/exam-03/q11/ingress-v1.yaml` containing the same Ingress (name, namespace, host, paths and backends) converted to the current stable API. Use `pathType: Prefix` for every path and replace the deprecated class annotation with its `spec` field equivalent (class `nginx`). Do not modify the legacy file.
- Apply the new file.

---

## Question 12 — Kustomize generators

**Weight:** 5% · **Domain:** Application Deployment · **Namespace:** `m03-kust`

`~/ckad-mocks/exam-03/q12/` contains `deployment.yaml` (Deployment `report-api`) and `app.properties`. The Deployment expects a ConfigMap `report-config` and a Secret `report-secret`, which do not exist yet. Do not edit `deployment.yaml`.

Create `~/ckad-mocks/exam-03/q12/kustomization.yaml` that:

- uses `deployment.yaml` as a resource and places every object in namespace `m03-kust`,
- generates ConfigMap `report-config` from the literal `LOG_LEVEL=debug` **and** from the file `app.properties`,
- generates Secret `report-secret` from the literal `API_TOKEN=m03-t0ken`.

Render the result with `kubectl` to `~/ckad-mocks/exam-03/q12/rendered.yaml`, then apply the directory with kubectl's built-in Kustomize support.

End state: the generated ConfigMap and Secret (names with a hash suffix) exist in `m03-kust`, and the `report-api` Pod is Running and logs `LOG_LEVEL=debug`.

---

## Question 13 — Pod Security Admission: fix a rejected Pod

**Weight:** 6% · **Domain:** Application Environment, Configuration and Security · **Namespace:** `m03-psa`

Namespace `m03-psa` enforces the `restricted` Pod Security Standard. The manifest `~/ckad-mocks/exam-03/q13/secure-web.yaml` is rejected.

- Apply the manifest once, unchanged, and save the rejection message (stderr) to `~/ckad-mocks/exam-03/q13/rejection.txt`.
- Edit `secure-web.yaml` in place so that the Pod is admitted and Running. Do not change the namespace labels, the image, the command or the container port. Run the container as UID `1000`. The volume `www` must stay mounted at `/www` but may no longer be a `hostPath`; use an `emptyDir`.
- End state: `kubectl -n m03-psa exec secure-web -- wget -qO- http://localhost:8080` prints `secure`.

---

## Question 14 — Pending Pod

**Weight:** 5% · **Domain:** Application Observability and Maintenance · **Namespace:** `m03-sched`

The Pod of Deployment `reporter` never starts.

- Before changing anything, write the message of the Pod's `FailedScheduling` event to `~/ckad-mocks/exam-03/q14/reason.txt`.
- Fix the Deployment so that its Pod is scheduled and Running. Constraints: the Pod must stay restricted to Linux nodes through a `nodeSelector` on the well-known label `kubernetes.io/os`; the container needs only `128Mi` of memory; keep the CPU request unchanged.

---

## Question 15 — StatefulSet with stable network identity and storage

**Weight:** 6% · **Domain:** Application Design and Build · **Namespace:** `m03-sts`

- Create a headless Service `kv-hl` with one port `6379` named `redis`, selecting Pods labelled `app=kv`.
- Create a StatefulSet `kv` with 2 replicas, governed by Service `kv-hl`, Pod label `app=kv`, one container `redis` (image `redis:7.2`, container port `6379`), and a volume claim template `data` (`ReadWriteOnce`, `100Mi`, the cluster's default StorageClass — do not set `storageClassName`) mounted at `/data`.
- When both Pods are Ready, resolve `kv-0.kv-hl.m03-sts.svc.cluster.local` with `nslookup` from a temporary `busybox:1.36` Pod in namespace `m03-sts` and save the output to `~/ckad-mocks/exam-03/q15/dns.txt`. The temporary Pod must not exist afterwards.

---

## Question 16 — Canary with a fixed Pod budget

**Weight:** 5% · **Domain:** Application Deployment · **Namespace:** `m03-canary`

Deployment `checkout-v1` (5 replicas) serves the Service `checkout`. Release a canary:

- Create Deployment `checkout-v2` with container `checkout` and image `nginx:1.27-alpine`, whose Pods receive roughly 20% of the requests sent to Service `checkout`.
- The total number of Pods behind Service `checkout` must stay at 5.
- Canary Pods carry the label `track=canary`. The selectors of `checkout-v1` and `checkout-v2` must not overlap.
- Do not modify Service `checkout`.

---

## Question 17 — Explore an operator's CRD

**Weight:** 5% · **Domain:** Application Environment, Configuration and Security · **Namespace:** `m03-crd`

A backup operator runs in namespace `m03-crd` and has registered a CustomResourceDefinition in the API group `ops.m03.example.com`.

- Write the list of resource types of that API group, as shown by `kubectl`, to `~/ckad-mocks/exam-03/q17/resources.txt`.
- Write the `kubectl` documentation of the field `spec.retention.keepLast` of that resource to `~/ckad-mocks/exam-03/q17/keeplast.txt`.
- Create a custom resource named `orders-nightly` in namespace `m03-crd` that backs up the database `orders` every day at 02:00 (cron `0 2 * * *`), keeps the last 7 backups and uses the storage tier `archive`. Discover the exact field names from the API.

---

## Question 18 — Collect logs from every container by label

**Weight:** 3% · **Domain:** Application Observability and Maintenance · **Namespace:** `m03-logs`

Deployment `orders` runs 2 Pods with the containers `app` and `audit`. With a single `kubectl` command, write **all** log lines (from container start, not only the most recent ones) of **all** containers of all Pods labelled `app=orders` to `~/ckad-mocks/exam-03/q18/orders.log`. Every line must be prefixed with its Pod and container name.

---

## Question 19 — Expose an application over HTTPS

**Weight:** 9% · **Domain:** Services and Networking · **Namespace:** `m03-tls`

Deployment `portal` (container port 80, Pod label `app=portal`) has no Service yet.

- Create a ClusterIP Service `portal` with one port `8080` named `http` that forwards to container port 80.
- With `openssl`, create a self-signed certificate valid for 365 days with subject `CN=portal.m03.local` (RSA 2048, private key without passphrase): key `~/ckad-mocks/exam-03/q19/portal.key`, certificate `~/ckad-mocks/exam-03/q19/portal.crt`.
- Store both in a TLS Secret `portal-tls` in namespace `m03-tls`. (A Secret with the same name exists in namespace `m03-certs`; it belongs to another host and cannot be used.)
- Create an Ingress `portal` with IngressClass `nginx` that routes `https://portal.m03.local/` (path `/`, type `Prefix`) to Service `portal` and terminates TLS for host `portal.m03.local` with Secret `portal-tls`.

---

**End of exam.** Stop the timer and grade yourself with [solutions.md](solutions.md).
