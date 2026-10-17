# CKAD Mock Exam 02 — Foundations+

| Duration | Questions | Pass mark | Total weight |
|---|---|---|---|
| 120 min | 19 | 66% | 100% |

> **How to take this exam**
> 1. Build a practice cluster: [00 — Exam Overview and Setup](../../00-Exam-Overview-and-Setup/README.md) (lab guide: [02-local-practice-lab-setup.md](../../00-Exam-Overview-and-Setup/02-local-practice-lab-setup.md)). Include metrics-server, an ingress controller and a NetworkPolicy-enforcing CNI, and have `helm` plus `podman` or `docker` installed.
> 2. From this folder run `bash setup.sh`. Read its summary, which warns about any missing optional component.
> 3. Start a **120-minute** timer.
> 4. Keep only kubernetes.io/docs, kubernetes.io/blog and helm.sh/docs open.
> 5. When the timer stops, grade yourself with [solutions.md](solutions.md). Afterwards run `bash cleanup.sh`.
>
> **Real exam vs. this lab:** here everything runs against one local cluster. In the real exam, which currently runs Kubernetes v1.37, every task names a host. You run `ssh <host>`, solve the task there, then `exit` back to the base machine; nested ssh is not supported. The hosts provide `kubectl` (with the `k` alias and completion), `yq`, `curl`, `wget` and `man`. `jq` is not guaranteed, so none of these solutions use it. The Kustomize site (kubectl.docs.kubernetes.io) is **not** on the allowed list; use the kubernetes.io Kustomize task page instead. Details: [00 — Exam Overview and Setup](../../00-Exam-Overview-and-Setup/README.md).

> **Note:** These are exam-style tasks modelled on the official CNCF curriculum and on task patterns that candidates describe publicly. Real exam questions are confidential under the Linux Foundation candidate agreement; nothing here is a leaked question.

**Ground rules**
- Each task names its namespace, so use `-n <namespace>` every time. On the real exam each task also names the host to `ssh` into first, as described in the box above.
- Output files go under `~/ckad-mocks/exam-02/qNN/`; setup.sh creates these directories. Write exactly the content requested.
- Use the images exactly as given. Never use `:latest`.
- "Do not modify X" means the object must be unchanged when you are done. Changes to it cost the points for that task.
- This paper is a step up from Mock 01: several objects are **already broken**, and you have to find out why before you can fix them.

---

## Question 1 — Modify, rebuild and export an image
**Weight:** 5% · **Domain:** Application Design and Build · **Namespace:** — (local machine, no cluster objects)

`~/ckad-mocks/exam-02/q01/` contains a `Dockerfile` and a script `report.sh`. Modify the **Dockerfile** so that:

- the base image is `busybox:1.36`
- the environment variable `APP_ENV` has the value `production`
- the container runs as the non-root user ID `1001`

Build the image as `m02-report:2.0` with podman (docker is also accepted), and save it in **OCI archive** format to `~/ckad-mocks/exam-02/q01/m02-report-2.0.tar`.

---

## Question 2 — Parallel batch Job
**Weight:** 5% · **Domain:** Application Design and Build · **Namespace:** `m02-jobs`

Create a Job named `batch-processor` and save its manifest to `~/ckad-mocks/exam-02/q02/job.yaml`:

- one container named `processor`, image `busybox:1.36`, command `sh -c 'echo "processing chunk on $(hostname)"; sleep 5'`
- the Job must succeed **6** times, with at most **2** Pods running at the same time
- after **3** retries the Job is marked as failed
- Kubernetes deletes the Job automatically **30 minutes** after it finishes
- failed containers are never restarted in place; a failed Pod is replaced by a new Pod

The Job must complete successfully.

---

## Question 3 — Init container prepares web content
**Weight:** 5% · **Domain:** Application Design and Build · **Namespace:** `m02-init`

Create a Pod `welcome` with:

- an init container `prepare` (image `busybox:1.36`) that writes the single line `<h1>Welcome to CKAD mock 02</h1>` to the file `index.html` in an `emptyDir` volume named `html`. The volume is mounted at `/work` in the init container.
- a main container `web` (image `nginx:1.27-alpine`, container port 80) that serves the same volume from `/usr/share/nginx/html`

Running `wget -qO- http://localhost` inside container `web` must return that line.

---

## Question 4 — From a bare Pod to a Deployment
**Weight:** 6% · **Domain:** Application Design and Build · **Namespace:** `m02-convert`

The bare Pod `inventory` must be replaced by a Deployment.

- Create a ServiceAccount `inventory-sa` that does **not** automatically mount API credentials into Pods.
- Create a Deployment `inventory` with **3** replicas. Its Pod template uses the same labels and the same container as Pod `inventory` (name, image, env, ports, resources), and its Pods run as `inventory-sa`. Save the Deployment manifest to `~/ckad-mocks/exam-02/q04/inventory-deploy.yaml`.
- No Pod of the Deployment may have a ServiceAccount token mounted.
- When the Deployment is available, delete the original Pod `inventory`.

---

## Question 5 — Blue/green switch
**Weight:** 4% · **Domain:** Application Deployment · **Namespace:** `m02-bluegreen`

Service `store` sends traffic to Deployment `store-blue`. The new version, Deployment `store-green`, exists but is scaled to 0.

1. Scale `store-green` to 3 replicas and wait until all of them are Ready.
2. Switch Service `store` so that **all** traffic goes to the green Pods and none to the blue Pods.
3. Scale `store-blue` down to 0 replicas, keeping the Deployment for a fast rollback.

Do not change the Pod templates of either Deployment.

---

## Question 6 — Tune the update strategy
**Weight:** 5% · **Domain:** Application Deployment · **Namespace:** `m02-strategy`

- Deployment `catalog`: configure rolling updates so that at most **one** extra Pod is created during an update and **no** Pod becomes unavailable. Then update container `catalog` to image `nginx:1.27`, and wait for the rollout to finish.
- Deployment `ledger` holds an exclusive file lock, so an old and a new Pod must **never** run at the same time. Change its update strategy accordingly. Then add the environment variable `LEDGER_MODE=strict` to container `ledger`.

---

## Question 7 — Kustomize production overlay
**Weight:** 5% · **Domain:** Application Deployment · **Namespace:** `m02-prod`

`~/ckad-mocks/exam-02/q07/base/` contains a Kustomize base with a Deployment `api` and a Service `api`. Without modifying anything in the base, create the overlay `~/ckad-mocks/exam-02/q07/overlays/prod/kustomization.yaml` that:

- uses the base
- puts every resource into namespace `m02-prod`
- prefixes every resource name with `prod-`
- sets the tag of the `nginx` image to `1.27`
- runs **3** replicas of the Deployment

Write the rendered overlay to `~/ckad-mocks/exam-02/q07/prod-rendered.yaml`, then apply the overlay to the cluster.

---

## Question 8 — Helm release management
**Weight:** 6% · **Domain:** Application Deployment · **Namespace:** `m02-helm` (and wherever the old release lives)

- A Helm release named `m02-legacy` is installed somewhere in the cluster and is no longer needed. Uninstall it.
- A chart is available at `~/ckad-mocks/exam-02/q08/webapp`. **Without installing anything**, render the manifests for release `m02-web` in namespace `m02-helm` with the values `replicaCount=3`, `image.tag=1.27-alpine` and `service.type=NodePort`, into `~/ckad-mocks/exam-02/q08/m02-web-rendered.yaml`.
- Install the chart as release `m02-web` in namespace `m02-helm` with the same three values.
- Write the **user-supplied** values of release `m02-web` to `~/ckad-mocks/exam-02/q08/values.txt`.

---

## Question 9 — Startup probe for a slow application
**Weight:** 5% · **Domain:** Application Observability and Maintenance · **Namespace:** `m02-probes`

Deployment `slow-app` keeps restarting. Its application needs about 60 seconds to start, but the liveness probe kills it before that.

- Add a startup probe to container `app`: HTTP GET `/` on port `8080`, period 10 s, failure threshold 12.
- Do **not** change the existing liveness probe.

The new Pod must become Ready and stop restarting.

---

## Question 10 — CrashLoopBackOff
**Weight:** 5% · **Domain:** Application Observability and Maintenance · **Namespace:** `m02-debug`

The Pod of Deployment `ticker` is in `CrashLoopBackOff`.

- Write the logs of the **previous**, crashed run of container `ticker` to `~/ckad-mocks/exam-02/q10/previous.log`.
- Fix the Deployment so that the container runs the script provided by ConfigMap `ticker-script` and stays Running. Do not modify the ConfigMap.

---

## Question 11 — Deprecated PodDisruptionBudget
**Weight:** 3% · **Domain:** Application Observability and Maintenance · **Namespace:** `m02-pdb`

The file `~/ckad-mocks/exam-02/q11/pdb.yaml` defines a PodDisruptionBudget for Deployment `web`, but it no longer applies on this cluster.

- Update the file in place to an API version this cluster serves, keeping everything else, and apply it.
- Write the number of disruptions that `web-pdb` currently allows to `~/ckad-mocks/exam-02/q11/allowed.txt` (the number only).

---

## Question 12 — Cluster health snapshot
**Weight:** 2% · **Domain:** Application Observability and Maintenance · **Namespace:** cluster-wide and `m02-debug`

- Write the current resource usage of all nodes (the `kubectl top` table including its header) to `~/ckad-mocks/exam-02/q12/nodes.txt`.
- Write the name of the node with the **highest memory usage** to `~/ckad-mocks/exam-02/q12/top-node.txt` (the name only).
- Write all events of type `Warning` in namespace `m02-debug`, oldest first, to `~/ckad-mocks/exam-02/q12/warnings.txt`.

---

## Question 13 — Discover and use custom resources
**Weight:** 5% · **Domain:** Application Environment, Configuration and Security · **Namespace:** `m02-crd`

- Write the names of all CustomResourceDefinitions in the API group `m02.example.com` to `~/ckad-mocks/exam-02/q13/crds.txt`, one per line.
- Create two `Database` objects in `m02-crd`:

| Name | `spec.engine` | `spec.version` | `spec.storageGB` |
|---|---|---|---|
| `orders-db` | `postgres` | `16` | `10` |
| `users-db` | `mysql` | `8.4` | `5` |

- Using the resource's **short name**, write the `kubectl get` output that lists all Database objects in `m02-crd` to `~/ckad-mocks/exam-02/q13/databases.txt`.

---

## Question 14 — Update configuration safely
**Weight:** 6% · **Domain:** Application Environment, Configuration and Security · **Namespace:** `m02-config`

Deployment `api` reads its settings from ConfigMap `api-settings` as environment variables.

- Change `LOG_LEVEL` in `api-settings` to `debug` and keep all the other keys.
- Make the running `api` Pods use the new value by performing a **rolling restart**. Do not delete Pods yourself, and do not edit the Deployment's Pod template.
- Create a ConfigMap `feature-flags` with `FEATURE_X=on` and `FEATURE_Y=off` whose data **cannot be changed** after creation.

---

## Question 15 — Secret as a read-only file
**Weight:** 5% · **Domain:** Application Environment, Configuration and Security · **Namespace:** `m02-secret`

- Create a Secret `api-key` from the file `~/ckad-mocks/exam-02/q15/api-key.txt`. The key inside the Secret must be `token`.
- Create a Pod `api-client` (container `client`, image `busybox:1.36`, command `sh -c 'sleep 3600'`) that mounts the Secret read-only at `/etc/api`, so that `/etc/api/token` exists with file permissions `0400`.
- The token must not be exposed as an environment variable.

---

## Question 16 — Namespace guardrails
**Weight:** 8% · **Domain:** Application Environment, Configuration and Security · **Namespace:** `m02-guard`

- Configure namespace `m02-guard` so that Pod Security Admission **enforces** the `baseline` profile and **warns** about violations of the `restricted` profile.
- Create a LimitRange `defaults` that gives every container without resource settings these values: requests `100m` CPU and `128Mi` memory, limits `200m` CPU and `256Mi` memory.
- The new policy rejects the manifest `~/ckad-mocks/exam-02/q16/tools-pod.yaml`. Fix the file in place so the Pod is admitted: keep the name, image and command, and do not add resource settings. Then create the Pod. A warning about the `restricted` profile is expected and fine.
- Write the `resources` of container `tools`, as stored in the cluster, to `~/ckad-mocks/exam-02/q16/resources.txt` (the JSON printed by jsonpath is fine).

---

## Question 17 — Repair a Service
**Weight:** 6% · **Domain:** Services and Networking · **Namespace:** `m02-svc`

Service `ledger` should load-balance HTTP traffic on port 80 to the Pods of Deployment `ledger-api`, but requests to it fail.

- Fix the Service, keeping its name, type and port 80. Do not modify any Deployment.
- From inside the Pod `client`, fetch `http://ledger` and save the response body to `~/ckad-mocks/exam-02/q17/response.txt`.

---

## Question 18 — Default deny with DNS
**Weight:** 8% · **Domain:** Services and Networking · **Namespace:** `m02-netpol`

Lock down namespace `m02-netpol`, which runs the Pods `web` (label `app=web`) and `client` (label `app=client`), with exactly these NetworkPolicies:

| Name | Purpose |
|---|---|
| `default-deny-all` | deny **all** ingress and **all** egress traffic for every Pod in the namespace |
| `allow-dns-egress` | allow every Pod in the namespace to send DNS traffic (UDP and TCP port 53) to namespace `kube-system` |
| `web-allow-client` | allow `web` to receive traffic from `client` on TCP port 80 |
| `client-allow-web` | allow `client` to send traffic to `web` on TCP port 80 |

When you are done, `client` must be able to resolve and reach `web` (`wget http://web`), and everything else must be blocked.

---

## Question 19 — Repair an Ingress
**Weight:** 6% · **Domain:** Services and Networking · **Namespace:** `m02-ingress`

The Ingress `docs-ingress` should route `http://docs.m02.local/` through the cluster's ingress controller to the docs application behind Service `docs-svc`, but it doesn't work.

- Fix the Ingress, keeping its name, host and path.
- Do not modify the Service or the Deployment.

---

*End of exam. Stop the timer, then grade yourself with [solutions.md](solutions.md).*
