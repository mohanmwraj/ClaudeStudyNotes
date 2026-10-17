# CKAD Mock Exam 05 — Advanced, multi-step

| Duration | Questions | Pass mark | Total weight |
|---|---|---|---|
| 120 min | 19 (+1 unscored bonus) | 66% | 100% |

> **How to take this exam**
> 1. Build a practice cluster: [00 — Exam Overview and Setup](../../00-Exam-Overview-and-Setup/README.md) (lab guide: [02-local-practice-lab-setup.md](../../00-Exam-Overview-and-Setup/02-local-practice-lab-setup.md)). Include an ingress controller with IngressClass `nginx` and a NetworkPolicy-enforcing CNI. Helm, podman/docker and the Gateway API CRDs are needed for single questions.
> 2. From this folder run `bash setup.sh`. Read its summary, which warns about any missing optional component.
> 3. Start a **120-minute** timer.
> 4. Keep only kubernetes.io/docs, kubernetes.io/blog and helm.sh/docs open. The Kustomize site (kubectl.docs.kubernetes.io) is not on the allowed list.
> 5. When the timer stops, grade yourself with [solutions.md](solutions.md). Afterwards run `bash cleanup.sh`.
>
> On the real exam (Kubernetes v1.37) every task names a host. Run `ssh <host>`, solve the task there, then `exit` back to the base machine before the next task, because nested ssh is not supported. This mock runs against one practice cluster, so each task names a namespace instead.

> **Note:** These are exam-style tasks modelled on the official CNCF curriculum and on task patterns that candidates describe publicly. Real exam questions are confidential under the Linux Foundation candidate agreement; nothing here is a leaked question.

**Ground rules**
- Each task names its namespace, so use `-n <namespace>` every time. On the real exam you would first `ssh` to the host the task names.
- Output files go under `~/ckad-mocks/exam-05/qNN/`; setup.sh creates these directories. Write exactly the content requested, with no extra text.
- Use the images exactly as given. Never use `:latest`.
- Unless a task says otherwise, objects you create must end up Running/Ready (Pods, Deployments) or Complete (Jobs).
- This paper is the **advanced** level: most tasks have several steps, several start from objects that are already broken, and many say what you must **not** change. Read every bullet before you type.
- A well-prepared candidate finishes in about 120 minutes. Flag anything that takes more than 10 minutes and come back to it.

| Optional component | Needed by |
|---|---|
| podman or docker | Q19 |
| helm and internet access (public chart repository) | Q7 |
| ingress controller with IngressClass `nginx` (kit lab: `http://localhost:8080`) | Q14 |
| NetworkPolicy-enforcing CNI | Q9 (to verify) |
| Gateway API CRDs | Bonus |

---

## Question 1 — Promote a canary
**Weight:** 5% · **Domain:** Application Deployment · **Namespace:** `m05-canary`

Service `pricing` load-balances across two Deployments: `pricing-stable` (3 replicas, answers `pricing v1`) and `pricing-canary` (1 replica, answers `pricing v2`). The canary has been healthy for a day, so promote it.

Required end state:
- `pricing-canary` runs **4** ready replicas.
- `pricing-stable` is scaled to **0** replicas and still exists, because it is the rollback path.
- Service `pricing` is **not modified in any way**, and no Pod template or Pod label is changed.
- Scale up before you scale down: at no point may fewer than 3 ready Pods back the Service.
- After the promotion, write the IP addresses of the ready endpoints of Service `pricing`, one per line, to `~/ckad-mocks/exam-05/q01/endpoints.txt`. Read them from the Service's **EndpointSlice** objects.

---

## Question 2 — Indexed Job with a work list
**Weight:** 6% · **Domain:** Application Design and Build · **Namespace:** `m05-batch`

The file `~/ckad-mocks/exam-05/q02/shards.txt` lists four shard names, one per line.

1. Create a ConfigMap `shard-list` with a single key `shards.txt` that holds the content of that file.
2. Create a Job `shard-processor`:
   - completion mode **Indexed**, `completions: 4`, `parallelism: 2`, `backoffLimit: 2`
   - one container named `worker`, image `busybox:1.36`, Pod restart policy `Never`
   - the ConfigMap mounted **read-only** at `/config`
   - the container runs exactly this command, so each Pod prints the shard that matches its completion index:
     ```text
     sh -c 'echo "index=${JOB_COMPLETION_INDEX} shard=$(sed -n "$((JOB_COMPLETION_INDEX + 1))p" /config/shards.txt)"'
     ```
   - do **not** set `ttlSecondsAfterFinished`, because the Job must remain for grading
3. When the Job is complete, write the log of the Pod with completion index **2** to `~/ckad-mocks/exam-05/q02/index-2.log`.

---

## Question 3 — One Secret, consumed two ways
**Weight:** 5% · **Domain:** Application Environment, Configuration and Security · **Namespace:** `m05-secrets`

1. Create a generic Secret `merchant-creds` from the env file `~/ckad-mocks/exam-05/q03/merchant.env`. It must contain exactly the keys `API_KEY`, `DB_PASSWORD` and `TLS_PIN`.
2. Create a Pod `merchant-api`, image `nginx:1.27-alpine`, container name `api`, that:
   - gets the environment variable `DB_PASS` from Secret key `DB_PASSWORD`
   - has **only** key `TLS_PIN` mounted, as the file `/etc/merchant/pin`. The directory `/etc/merchant` must contain no other file.
   - does not receive `API_KEY` in any way, neither as an environment variable nor as a file

---

## Question 4 — A Service without endpoints
**Weight:** 5% · **Domain:** Services and Networking · **Namespace:** `m05-svc`

Clients report that `http://billing.m05-svc` does not answer, although both Pods of Deployment `billing` are Running.

- Find the cause and fix it. Other teams consume Service `billing` through its **named** target port, so the Service **must not be modified**. Fix the workload instead, and do not delete or recreate the Deployment.
- From the existing Pod `client`, request `http://billing` and write the HTML `<title>` element of the response (one line, for example `<title>Something</title>`) to `~/ckad-mocks/exam-05/q04/title.txt`.

---

## Question 5 — A worker that keeps restarting
**Weight:** 5% · **Domain:** Application Observability and Maintenance · **Namespace:** `m05-oom`

The Pod of Deployment `thumbnailer` restarts again and again.

1. Write the reason and the exit code of the **last termination** of container `resizer` to `~/ckad-mocks/exam-05/q05/reason.txt`, in the format `<reason>:<exitCode>` (for example `Error:1`).
2. Fix the problem: set the memory **limit** of container `resizer` to `128Mi` and its memory **request** to `64Mi`. Do not change the command, the CPU values or the number of replicas.
3. The new Pod must be Running with `0` restarts.

---

## Question 6 — Init container that waits for a Service
**Weight:** 5% · **Domain:** Application Design and Build · **Namespace:** `m05-init`

A Deployment `db` (PostgreSQL, port 5432) already runs in the namespace. Create a Pod `exporter` with:

| Container | Type | Image | Command (exactly) |
|---|---|---|---|
| `wait-for-db` | init container | `busybox:1.36` | `sh -c 'until nslookup db.m05-init.svc.cluster.local; do echo waiting for db; sleep 2; done; nslookup db.m05-init.svc.cluster.local > /work/db-dns.txt'` |
| `export` | app container | `busybox:1.36` | `sh -c 'cat /work/db-dns.txt; sleep 3600'` |

- Both containers share an `emptyDir` volume named `work`, mounted at `/work`.
- Then let the Pod start: expose Deployment `db` through a **ClusterIP** Service named `db`, port `5432`, target port `5432`. Do not change the init command.
- Finally write the logs of container `export` to `~/ckad-mocks/exam-05/q06/export.log`.

---

## Question 7 — Helm: pull, customise, install, upgrade, roll back
**Weight:** 5% · **Domain:** Application Deployment · **Namespace:** `m05-helm`

Needs helm and internet access.

1. Add the chart repository `https://stefanprodan.github.io/podinfo` under the name `m05-podinfo`.
2. Download chart `m05-podinfo/podinfo` and unpack it into `~/ckad-mocks/exam-05/q07/`, so that the chart ends up in `~/ckad-mocks/exam-05/q07/podinfo/`.
3. In the unpacked chart's `values.yaml`, set `replicaCount` to `2`.
4. Install release `web` into `m05-helm` **from that local directory**, setting `ui.message=blue` on the command line.
5. Upgrade `web` from the same directory. Keep every value of the current release and additionally set `ui.color=#00aa00`.
6. Roll `web` back to revision 1.
7. Write the output of `helm history` for release `web` to `~/ckad-mocks/exam-05/q07/history.txt`.

End state: release `web` is at revision 3 and deployed, its user-supplied values contain only `ui.message: blue`, and its Deployment has 2 ready Pods.

---

## Question 8 — Narrow RBAC for a debugging ServiceAccount
**Weight:** 7% · **Domain:** Application Environment, Configuration and Security · **Namespace:** `m05-rbac`

Pods `app-1` and `app-2` run in the namespace.

1. Create a ServiceAccount `log-reader` that does **not** automount its token. Set this on the ServiceAccount itself.
2. Create a Role `app-1-debug` and a RoleBinding `app-1-debug` that grant `log-reader` exactly these permissions:
   - `get` on Pod `app-1` and on its `log` subresource
   - `create` on the `exec` subresource of Pod `app-1`
   - nothing on any other Pod (use `resourceNames`)
3. The file `~/ckad-mocks/exam-05/q08/can-i.txt` contains seven checks. After each `=` append `yes` or `no`, as answered by `kubectl auth can-i` for ServiceAccount `log-reader` in namespace `m05-rbac`. Keep the lines in their order and format, for example `get pods app-1 = yes`.
4. Create a Pod `log-agent`, image `curlimages/curl:8.10.1`, container `agent`, command `sleep 3600`. It runs as `log-reader` and **does get a token mounted**. Do not change the ServiceAccount to achieve this.

---

## Question 9 — Egress allow-list for an API Pod
**Weight:** 7% · **Domain:** Services and Networking · **Namespace:** `m05-netpol`

Pods `api` (label `app=api`), `db` (`app=db`, PostgreSQL on 5432) and `cache` (`app=cache`, Redis on 6379) run in the namespace. Services `db` and `cache` point to them.

Create a NetworkPolicy `api-egress` so that Pod `api` can send traffic **only** to:
- Pods labelled `app=db`, on TCP port `5432`
- the cluster DNS: Pods labelled `k8s-app=kube-dns` in namespace `kube-system`, on UDP and TCP port `53`

Also:
- All other egress from `api` must be denied, and incoming traffic to `api` must not be restricted.
- The requirement must actually hold in this namespace. Verify it from inside Pod `api` (`nc -zv -w 3 <host> <port>` is available there).
- Pods other than `api` must keep unrestricted egress.

---

## Question 10 — Probes for a slow-starting store
**Weight:** 5% · **Domain:** Application Observability and Maintenance · **Namespace:** `m05-probes`

Deployment `session-store` (container `redis`) needs about 40 seconds before Redis listens on port 6379, and its current liveness probe kills it before that. Without changing image, command or args, give container `redis` exactly these probes, replacing the existing one:

- **startupProbe**: TCP check on port 6379, `periodSeconds: 5`, and a `failureThreshold` that gives the container **exactly 90 seconds** to start
- **livenessProbe**: exec `redis-cli ping`, `periodSeconds: 10`, `failureThreshold: 3`, no initial delay
- **readinessProbe**: TCP check on port 6379, `periodSeconds: 5`

End state: the rollout completes and the new Pod is Ready with `0` restarts.

---

## Question 11 — Prove that data survives a Pod
**Weight:** 5% · **Domain:** Application Design and Build · **Namespace:** `m05-storage`

1. Create a PersistentVolumeClaim `journal-data`: `100Mi`, `ReadWriteOnce`, using the cluster's default StorageClass. Do not set `storageClassName`.
2. Create a Deployment `journal` (1 replica, update strategy `Recreate`) with container `writer`, image `busybox:1.36`. It mounts the claim at `/data` and runs exactly:
   ```text
   sh -c 'echo "boot $(hostname) $(date)" >> /data/journal.log; sleep 3600'
   ```
3. Once the Pod is Running, delete it and let the Deployment replace it.
4. Read `/data/journal.log` from the **new** Pod and write its content to `~/ckad-mocks/exam-05/q11/journal.txt`. It must contain two `boot` lines written by two different Pods.

---

## Question 12 — Kustomize: labels that leave selectors alone, plus a JSON 6902 patch
**Weight:** 5% · **Domain:** Application Deployment · **Namespace:** `m05-kustomize`

`~/ckad-mocks/exam-05/q12/` contains a kustomization (`kustomization.yaml`, `deployment.yaml`, `service.yaml`). It has already been applied, so Deployment `warehouse` is running. Edit **only** `kustomization.yaml`:

- Add the labels `team: logistics` and `env: staging` to the metadata of all resources **and** to the Pod template. Do not change any selector: the Deployment's `spec.selector` and the Service's `spec.selector` must stay `app: warehouse`.
- Add an inline **JSON 6902** patch (a list of operations) that targets Deployment `warehouse`. It sets `spec.replicas` to `3` and adds the environment variable `MODE=readonly` to the first container.

Then write the rendered output of `kubectl kustomize` to `~/ckad-mocks/exam-05/q12/rendered.yaml`, and apply the kustomization with `kubectl apply -k`.

---

## Question 13 — Admission says no
**Weight:** 6% · **Domain:** Application Environment, Configuration and Security · **Namespace:** `m05-quota`

Deployment `analytics` (3 replicas, container `etl`) has no running Pods.

1. Find out why. Write the name of the **admission plugin** that rejects the Pods to `~/ckad-mocks/exam-05/q13/rejected-by.txt`.
2. Fix the Deployment so that all 3 replicas run. Rules:
   - Do not modify the LimitRange or the ResourceQuota.
   - Keep 3 replicas and keep the CPU values.
   - The memory limit must be the **maximum** that the LimitRange allows.
   - Choose a memory request that lets all 3 Pods fit into the quota.
3. Write the value of the kube-apiserver flag `--enable-admission-plugins`, exactly as it appears in the kube-apiserver static Pod manifest (comma-separated), to `~/ckad-mocks/exam-05/q13/admission-plugins.txt`.

---

## Question 14 — Multi-host Ingress with a default backend
**Weight:** 7% · **Domain:** Services and Networking · **Namespace:** `m05-ingress`

Services `docs` (port 80), `status-api` (port 8080, named `http`) and `fallback` (port 80) exist. Create an Ingress `edge` with `ingressClassName: nginx`:

| Host | Path (pathType) | Backend |
|---|---|---|
| `docs.m05.local` | `/` (Prefix) | Service `docs`, port `80` |
| `status.m05.local` | `/api` (Prefix) | Service `status-api`, port referenced **by name** |
| default backend (no host, no path) | — | Service `fallback`, port `80` |

Test through your ingress controller with `curl` and a `Host` header, and save the response bodies:
- `GET /guide` with host `docs.m05.local` → `~/ckad-mocks/exam-05/q14/docs.txt`
- `GET /api/health` with host `status.m05.local` → `~/ckad-mocks/exam-05/q14/status.txt`
- `GET /about` with host `status.m05.local` → `~/ckad-mocks/exam-05/q14/default.txt`

---

## Question 15 — Logs, events and API discovery
**Weight:** 5% · **Domain:** Application Observability and Maintenance · **Namespace:** `m05-logs`

1. Write the logs of **all containers** of **all Pods** labelled `app=dispatch` from the **last 5 minutes** to `~/ckad-mocks/exam-05/q15/dispatch.log`. Include every line in that window, and prefix each line with its Pod and container name.
2. Write all events of the namespace, sorted by creation time (oldest first), to `~/ckad-mocks/exam-05/q15/events.txt`.
3. `~/ckad-mocks/exam-05/q15/priorityclass.yaml` no longer applies. Use `kubectl api-resources` to find the group/version that the cluster serves for PriorityClass, and write that line of the `kubectl api-resources` output to `~/ckad-mocks/exam-05/q15/api.txt`. Fix the file in place, changing nothing but the `apiVersion`, and create the PriorityClass from it.

---

## Question 16 — A CustomResourceDefinition with validation
**Weight:** 4% · **Domain:** Application Environment, Configuration and Security · **Namespace:** `m05-crd`

1. Create a CustomResourceDefinition `maintenancewindows.ops.m05.ckad.io`:
   - group `ops.m05.ckad.io`, a single version `v1` (served, storage), scope `Namespaced`
   - kind `MaintenanceWindow`, plural `maintenancewindows`, singular `maintenancewindow`, short name `mw`
   - label the CRD `ckad-mock=exam-05`
   - schema: `spec` is an object with the **required** fields `start` (string) and `durationMinutes` (integer, minimum 15, maximum 240), plus the optional field `mode` (string, one of `drain`, `cordon`)
2. Create a `MaintenanceWindow` named `saturday-night` in `m05-crd` with `start: "0 2 * * 6"`, `durationMinutes: 120` and `mode: drain`.
3. Try to apply `~/ckad-mocks/exam-05/q16/too-long.yaml`. Your schema must reject it. Write the error message to `~/ckad-mocks/exam-05/q16/rejected.txt`.

---

## Question 17 — Detect and recover a stalled rollout
**Weight:** 5% · **Domain:** Application Deployment · **Namespace:** `m05-rollout`

The latest rollout of Deployment `quotes` never finishes.

1. Configure the Deployment so that the controller reports a rollout as failed after **30 seconds** without progress. Do not touch the Pod template.
2. Once the controller has marked the rollout as failed, write the `reason` of the Deployment's `Progressing` condition to `~/ckad-mocks/exam-05/q17/condition.txt`.
3. Roll back to the previous revision.
4. Set the change-cause of the resulting revision to `rollback: readiness /healthz 404`.
5. Write the output of `kubectl rollout history` for `quotes` to `~/ckad-mocks/exam-05/q17/history.txt`.

End state: 3/3 Pods ready, `progressDeadlineSeconds: 30`.

---

## Question 18 — Least-privilege securityContext, proven from /proc
**Weight:** 4% · **Domain:** Application Environment, Configuration and Security · **Namespace:** `m05-sec`

Create a Pod `hardened` with container `app`, image `busybox:1.36`, command `sleep 3600`:
- Pod level: `runAsNonRoot: true`, `runAsUser: 1000`, `runAsGroup: 3000`, seccomp profile `RuntimeDefault`
- container level: `allowPrivilegeEscalation: false`, `readOnlyRootFilesystem: true`, drop **all** capabilities and add back only `NET_BIND_SERVICE`

Then write the lines of `/proc/1/status` inside the container that start with `Uid:`, `CapEff:`, `CapBnd:`, `NoNewPrivs:` and `Seccomp:` to `~/ckad-mocks/exam-05/q18/status.txt`, in the order in which they appear in the file.

---

## Question 19 — Modify, build and run an image
**Weight:** 4% · **Domain:** Application Design and Build · **Namespace:** — (podman or docker on your machine, no cluster objects)

The directory `~/ckad-mocks/exam-05/q19/` contains a `Dockerfile` and `greet.sh`.

1. Modify the Dockerfile:
   - base image `busybox:1.36`
   - environment variable `BUILD_ID=m05-q19`
   - default argument (`CMD`) `CKAD`
   - the image runs as UID `65534`
   - keep the `ENTRYPOINT` unchanged
2. Build the image as `localhost/m05-greeter:1.1` (podman; docker is also accepted).
3. Run a container named `m05-greeter` from that image, with environment variable `GREETING=Howdy` and the argument `Kubernetes`. Do not override the entrypoint. Write the container's logs to `~/ckad-mocks/exam-05/q19/run.log`.
4. Write the user configured in the image metadata, as shown by `inspect`, to `~/ckad-mocks/exam-05/q19/user.txt`.

---

## Bonus — Gateway API traffic split (unscored)
**Weight:** bonus, not part of the 100% · **Domain:** Services and Networking · **Namespace:** `m05-gateway`

Gateway API is **not** part of the CKAD curriculum. This task is practice for after the exam: it counts 0% and is not in the coverage matrix. Skip it if setup.sh warned that the Gateway API CRDs are missing.

Create an HTTPRoute `rates-split` that attaches to Gateway `m05-gateway`, matches hostname `rates.m05.local`, and sends **90%** of requests to Service `rates-v1` (port 80) and **10%** to Service `rates-v2` (port 80).
