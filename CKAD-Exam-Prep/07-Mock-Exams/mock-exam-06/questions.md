# CKAD Mock Exam 06 — Final boss

| Duration | Questions | Pass mark | Total weight |
|---|---|---|---|
| 120 min | 17 | 66% | 100% |

> **Harder than the real exam, on purpose.** This paper is built like a killer.sh session: long scenarios, several faults per task, constraints you can trip over, and more work than fits comfortably into two hours. Most well-prepared candidates do **not** finish it. Scoring **66% or more here is a strong signal that you are ready** for the real exam. Below that, use the study map at the end of the solutions, not panic.

> **How to take this exam**
> 1. Build a practice cluster: [00 — Exam Overview and Setup](../../00-Exam-Overview-and-Setup/README.md) (lab guide: [02-local-practice-lab-setup.md](../../00-Exam-Overview-and-Setup/02-local-practice-lab-setup.md)). Include metrics-server, an ingress controller with IngressClass `nginx`, a NetworkPolicy-enforcing CNI, helm, and podman or docker.
> 2. From this folder run `bash setup.sh`. Read its summary, which warns about any missing optional component. Give the Pods a couple of minutes to pull images.
> 3. Start a **120-minute** timer.
> 4. Keep only kubernetes.io/docs, kubernetes.io/blog and helm.sh/docs open. The Kustomize site (kubectl.docs.kubernetes.io) is not on the allowed list.
> 5. When the timer stops, grade yourself with [solutions.md](solutions.md). Afterwards run `bash cleanup.sh`.
>
> On the real exam (Kubernetes v1.37) every task names a host. Run `ssh <host>`, solve the task there, then `exit` back to the base machine before the next task, because nested ssh is not supported. The exam hosts have kubectl (with the `k` alias and completion), yq, curl, wget and man; don't count on jq. This mock runs against one practice cluster, so each task names namespaces instead.

> **Note:** These are exam-style tasks modelled on the official CNCF curriculum and on task patterns that candidates describe publicly. Real exam questions are confidential under the Linux Foundation candidate agreement; nothing here is a leaked question.

**Ground rules**
- Each task names its namespace(s), so use `-n <namespace>` every time. Several tasks span more than one namespace.
- Output files go under `~/ckad-mocks/exam-06/qNN/`; setup.sh creates these directories. Write exactly the content requested, with no extra text.
- Use the images exactly as given. Never use `:latest`.
- "Do not change X" means exactly that. Graders compare those objects before and after.
- Unless a task says otherwise, objects you create or fix must end up Running/Ready (Pods, Deployments, StatefulSets) or Complete (Jobs).
- Triage first: read all 17 tasks (3 minutes), do the short ones, flag the long ones (Q2, Q5, Q7, Q8, Q10), and come back.

| Optional component | Needed by |
|---|---|
| metrics-server | Q13 (`kubectl top`), Q9 (HPA targets, not graded) |
| ingress controller with IngressClass `nginx` (kit lab: `http://localhost:8080`) | Q10, Q15 |
| NetworkPolicy-enforcing CNI | Q5, Q10 (to verify) |
| helm | Q3 |
| podman or docker | Q17 |

---

## Question 1 — Find the crash-looping container
**Weight:** 4% · **Domain:** Application Observability and Maintenance · **Namespace:** `m06-fleet`

About ten Pods run in `m06-fleet`. Exactly **one container** in that namespace keeps crashing and restarting.

1. Find it with `kubectl get` and JSONPath or custom columns, without describing every Pod. Write one line to `~/ckad-mocks/exam-06/q01/crash.txt` in the format `<pod> <container> <reason> <exitCode> <restartCount>`, where reason and exit code describe the container's **last termination** (example: `web-7d9c-abcde app Error 1 4`). Read every value with JSONPath.
2. The container fails because part of its configuration is missing. Fix the root cause **without editing the Deployment's spec**: create the missing object so that the container gets `DB_HOST=db.m06-fleet.svc.cluster.local`. Then make the Deployment pick it up (`kubectl rollout restart` is allowed).
3. End state: the new Pod has all containers Ready, with 0 restarts, and the formerly crashing container logs `worker connected to db.m06-fleet.svc.cluster.local`.

---

## Question 2 — Init container, native sidecar and the restricted profile
**Weight:** 7% · **Domain:** Application Design and Build · **Namespace:** `m06-pipeline`

Namespace `m06-pipeline` enforces the **restricted** Pod Security Standard. The draft manifest `~/ckad-mocks/exam-06/q02/pipeline.yaml` for Pod `pipeline` is rejected. Fix the file and create the Pod from it:

- Keep the names, images and commands of all three containers unchanged.
- `seed` stays an init container and runs first.
- Turn `log-shipper` into a **native sidecar**. It must start after `seed`, before `app`, and keep running for the whole lifetime of the Pod.
- All three containers share the volume `work`, an `emptyDir` with a size limit of `64Mi`, mounted at `/work`.
- Make the Pod compliant with `restricted` **without changing the namespace labels**: UID and GID `1000` and `runAsNonRoot` at Pod level, seccomp profile `RuntimeDefault`, and for every container no privilege escalation and all capabilities dropped.
- Once the Pod runs, write the first 3 lines of the `log-shipper` logs to `~/ckad-mocks/exam-06/q02/shipper.log`.

End state: Pod `pipeline` is Running, and `app` and `log-shipper` are both running and ready.

---

## Question 3 — Helm: a bad upgrade, a rollback and a leftover
**Weight:** 6% · **Domain:** Application Deployment · **Namespace:** `m06-helm` (and one more you have to find)

Release `portal` in `m06-helm` was installed from the chart in `~/ckad-mocks/exam-06/q03/portal/`. It has two revisions, and the current one answers `portal v2`.

1. The team asks for an upgrade of `portal` from the same chart directory, using **only** the values file `~/ckad-mocks/exam-06/q03/values-v3.yaml` (no `--set`, no `--reuse-values`). Do it.
2. Afterwards `http://portal.m06-helm` no longer answers (test from Pod `client` in `m06-helm`). Find the key in `values-v3.yaml` that breaks the application and write it in dot notation (for example `image.tag`) to `~/ckad-mocks/exam-06/q03/broken-value.txt`.
3. Roll `portal` back to the **last working** revision. Don't modify the chart or the values file.
4. Write the output of `helm history` for `portal` to `~/ckad-mocks/exam-06/q03/history.txt`.
5. An older release of the same chart, `portal-old`, is still installed somewhere in the cluster. Uninstall it, but keep its namespace.

End state: `portal` answers `portal v2` again, its user-supplied values are those of revision 2, and `portal-old` no longer exists in any namespace.

---

## Question 4 — CronJob that calls the API with its own token
**Weight:** 7% · **Domain:** Application Environment, Configuration and Security · **Namespace:** `m06-cron`

CronJob `pod-audit` runs a script that lists the Pods of its own namespace through the Kubernetes REST API, using the ServiceAccount token mounted into its Pod. Its Jobs fail with `HTTP 403`.

1. Create a ServiceAccount `pod-auditor`, a Role `pod-auditor` that allows only `get`, `list` and `watch` on Pods, and a RoleBinding `pod-auditor` that binds them.
2. Change CronJob `pod-audit` so that:
   - its Pods run as `pod-auditor`
   - its Jobs never run concurrently
   - at most 2 successful and 1 failed Job are kept

   Don't change the schedule or the script.
3. Trigger a Job named `pod-audit-manual` from the CronJob right away. When it has completed, write its logs to `~/ckad-mocks/exam-06/q04/audit.log`. The first line must be `HTTP 200`, followed by `pod: audit-target-1` and `pod: audit-target-2`.
4. Prove least privilege: write the answer (`yes` or `no`) of `kubectl auth can-i delete pods` for ServiceAccount `pod-auditor` in `m06-cron` to `~/ckad-mocks/exam-06/q04/can-delete.txt`.

---

## Question 5 — NetworkPolicy with AND selectors, ipBlock and DNS
**Weight:** 8% · **Domain:** Services and Networking · **Namespaces:** `m06-netpol`, `m06-partners`, `m06-others`

In `m06-netpol`, Pod `settlement` (label `app=settlement`) serves HTTP on port 8080 behind Service `settlement`. Pod `accounts-db` (`app=accounts-db`) listens on port 5432 behind Service `accounts-db`.

1. Label namespace `m06-partners` with `team=partners`.
2. Create a NetworkPolicy `settlement-policy` in `m06-netpol` that selects `app=settlement` and restricts **both** directions:
   - **Ingress**, only on TCP 8080, and only from:
     - Pods labelled `role=api` in namespaces labelled `team=partners`. Both conditions must hold for the same Pod.
     - Pods labelled `app=frontend` in `m06-netpol`.
   - **Egress** only to:
     - Pods labelled `app=accounts-db` in `m06-netpol`, on TCP 5432
     - the external range `192.0.2.0/24` on TCP 443, **except** `192.0.2.128/25`
     - DNS (UDP and TCP 53) to Pods labelled `k8s-app=kube-dns` in `kube-system`
3. Don't change any other Pod, Service or NetworkPolicy.

Test Pods that you can `exec` into (`wget` and `nc` are available): `m06-partners/partner-api` (`role=api`), `m06-partners/partner-batch` (`role=batch`), `m06-others/outsider` (`role=api`), `m06-netpol/frontend` (`app=frontend`) and `m06-netpol/intruder` (`app=intruder`).

---

## Question 6 — A manifest from 2019
**Weight:** 5% · **Domain:** Application Observability and Maintenance · **Namespace:** `m06-apis`

`~/ckad-mocks/exam-06/q06/vintage-stack.yaml` contains seven documents for namespace `m06-apis`. Six of them use API versions that current Kubernetes no longer serves.

1. Fix the file in place so that `kubectl apply -f` creates all seven objects. Use the current GA API versions, and adapt every field that changed with them, including references to other objects. Keep all names and labels, the Ingress host, path and backend, the CronJob schedule, the PodDisruptionBudget's `minAvailable` and the HPA's 70% CPU target. Set the Ingress class through the field that replaced the old annotation.
2. Write one line per **changed** document to `~/ckad-mocks/exam-06/q06/migrations.txt`, in the format `<Kind>: <old apiVersion> -> <new apiVersion>`.
3. Apply the file.

---

## Question 7 — StatefulSet: identity, retention and data
**Weight:** 8% · **Domain:** Application Design and Build · **Namespace:** `m06-sts`

StatefulSet `kv` (3 Redis replicas, one PVC per replica) runs in `m06-sts`, but its Pods have no per-Pod DNS names.

1. Make `kv-0.kv-peers.m06-sts.svc.cluster.local`, `kv-1.kv-peers…` and `kv-2.kv-peers…` resolvable **without deleting or recreating the StatefulSet**. Then run `nslookup kv-1.kv-peers.m06-sts.svc.cluster.local` in Pod `dns-client` and write the output to `~/ckad-mocks/exam-06/q07/dns.txt`.
2. Store the key `owner` with value `ckad-m06` in the Redis instance of Pod `kv-2` (`redis-cli SET owner ckad-m06`, run inside `kv-2`).
3. Configure the StatefulSet so that its PVCs are **kept** when it scales down and **deleted** when the StatefulSet itself is deleted.
4. Scale `kv` to 2 replicas. Once Pod `kv-2` is gone, write the output of `kubectl get pvc -n m06-sts` to `~/ckad-mocks/exam-06/q07/pvc-after-scale-down.txt`.
5. Scale back to 3 replicas. Read `owner` from the Redis of `kv-2` and write the value to `~/ckad-mocks/exam-06/q07/owner.txt`.

End state: 3/3 Pods ready, and `owner.txt` contains `ckad-m06`.

---

## Question 8 — Kustomize base with dev and prod overlays
**Weight:** 7% · **Domain:** Application Deployment · **Namespaces:** `m06-dev`, `m06-prod`

`~/ckad-mocks/exam-06/q08/base/` holds a kustomization for Deployment and Service `reviews`. The Deployment reads its environment from a ConfigMap named `reviews-config`, which the base does **not** contain. Don't modify the base. Create two overlays:

| | `overlays/dev/` | `overlays/prod/` |
|---|---|---|
| namespace | `m06-dev` | `m06-prod` |
| name prefix | `dev-` | `prod-` |
| label on all resources **and** selectors | `env: dev` | `env: prod` |
| generated ConfigMap `reviews-config` | `LOG_LEVEL=debug` | `LOG_LEVEL=warn` |
| replicas | 1 | 3 |
| image | unchanged (`nginx:1.27`) | `nginx:1.27-alpine` |
| container `reviews` resources | — | requests `cpu: 100m`, `memory: 64Mi`; limits `cpu: 250m`, `memory: 128Mi` (via a patch) |

Then:
1. Apply the dev overlay.
2. **Before** applying prod, write the `kubectl diff -k` output for the prod overlay to `~/ckad-mocks/exam-06/q08/prod-diff.txt`. Then apply prod.
3. Change prod to **4** replicas in the overlay. Write the new `kubectl diff -k` output to `~/ckad-mocks/exam-06/q08/prod-replicas-diff.txt` and apply again.

---

## Question 9 — Fit a Deployment and an HPA into the guard rails
**Weight:** 6% · **Domain:** Application Environment, Configuration and Security · **Namespace:** `m06-hpa`

Namespace `m06-hpa` has LimitRange `bounds` and ResourceQuota `compute`. Read both before you start.

1. Create a Deployment `search`: 2 replicas, image `nginx:1.27`, container `web`, port 80. The container requests `cpu: 200m` and `memory: 128Mi` and has a memory limit of `256Mi`. Its CPU limit is the **highest value the LimitRange allows** for that request.
2. Create an HPA `search` (API `autoscaling/v2`) for the Deployment:
   - `minReplicas: 2`
   - target average CPU utilization of 60%
   - a scale-down stabilization window of 120 seconds
   - `maxReplicas` set to the **highest replica count the ResourceQuota can hold** for these Pods
3. Write that `maxReplicas` value to `~/ckad-mocks/exam-06/q09/max-replicas.txt`.

End state: Deployment 2/2 ready, HPA created.

---

## Question 10 — Make the shop reachable
**Weight:** 12% · **Domain:** Services and Networking · **Namespace:** `m06-shop`

Users must reach the storefront at `http://shop.m06.local/` through the ingress controller, but every request fails. The stack in `m06-shop` consists of Deployment `storefront`, Service `storefront`, Ingress `storefront`, ConfigMap `storefront-conf`, and NetworkPolicies `default-deny-ingress` and `allow-ingress-controller`.

Find and fix **every** fault, so that `curl -H 'Host: shop.m06.local' <ingress-address>/` returns `storefront: OK`. Constraints:
- Don't delete, recreate or rename any object, and don't change `default-deny-ingress` or ConfigMap `storefront-conf`. The nginx configuration serves `/` and the health endpoint `/healthz`.
- Service `storefront` keeps port 80. Ingress `storefront` keeps its host and path.
- Only Pods in the ingress controller's namespace (kit lab: `ingress-nginx`) may reach the storefront Pods, and only on port 80.

Write the response body to `~/ckad-mocks/exam-06/q10/response.txt`. Write one line per fault you fixed (the object and what was wrong) to `~/ckad-mocks/exam-06/q10/faults.txt`.

---

## Question 11 — Configuration precedence and file projection
**Weight:** 5% · **Domain:** Application Environment, Configuration and Security · **Namespace:** `m06-config`

ConfigMaps `app-env` and `nginx-extra` and Secret `app-secret` exist in `m06-config`. Create a Pod `web-config` (image `nginx:1.27-alpine`, container `web`) with:

- all keys of `app-env` and all keys of `app-secret` as environment variables, through `envFrom`, with the ConfigMap listed first and the Secret second
- an explicit environment variable `LOG_LEVEL=warn` that must win over both sources, and `DB_PASS` from Secret key `DB_PASSWORD`
- key `gzip.conf` of `nginx-extra` mounted as the **single file** `/etc/nginx/conf.d/gzip.conf`, so that the image's `/etc/nginx/conf.d/default.conf` still exists
- only Secret key `API_TOKEN` mounted, as the file `/etc/secrets/api/token` with file mode `0440`

Then:
1. Inside the container run `env | sort | grep -E '^(LOG_LEVEL|FEATURE_X|REGION|API_TOKEN|DB_PASS)='` and write the output to `~/ckad-mocks/exam-06/q11/env.txt`.
2. Both `app-env` and `app-secret` define `LOG_LEVEL`. Write the value the container **would** get without your explicit `LOG_LEVEL` entry to `~/ckad-mocks/exam-06/q11/precedence.txt`.

---

## Question 12 — A rollout that the quota blocks
**Weight:** 3% · **Domain:** Application Deployment · **Namespace:** `m06-rollout`

Deployment `edge-api` (4 replicas) must be updated to image `nginx:1.27-alpine`. Namespace `m06-rollout` has a ResourceQuota that allows at most 4 Pods, and you must not change it.

- Complete the update with 4 replicas. At no time may fewer than 3 Pods be available.
- Set the change-cause of the new revision to `nginx 1.27-alpine within pod quota`.
- Write the output of `kubectl rollout history` for `edge-api` to `~/ckad-mocks/exam-06/q12/history.txt`.

---

## Question 13 — Resource report and merged logs
**Weight:** 6% · **Domain:** Application Observability and Maintenance · **Namespace:** `m06-fleet`

1. Using `kubectl top`, find the Pod in `m06-fleet` that uses the most CPU. Write its name to `~/ckad-mocks/exam-06/q13/top-cpu.txt`.
2. Write a report of all Pods in `m06-fleet` to `~/ckad-mocks/exam-06/q13/report.txt`, sorted by Pod name, with exactly these columns:

   | Column | Content |
   |---|---|
   | `NAME` | Pod name |
   | `NODE` | node name |
   | `QOS` | QoS class |
   | `RESTARTS` | restart counts of all containers |
   | `IMAGES` | images of all containers |

3. Deployment `svc-b` runs 3 Pods. Write the complete logs of **all** of its Pods to `~/ckad-mocks/exam-06/q13/svc-b.log`. Prefix every line with its Pod and container, add timestamps, and merge the lines into one chronological stream (oldest first).

---

## Question 14 — Enforce the restricted profile
**Weight:** 4% · **Domain:** Application Environment, Configuration and Security · **Namespace:** `m06-psa`

Namespace `m06-psa` runs Deployment `metrics-api` (2 replicas) and has no Pod Security labels yet.

1. Label the namespace so that it **enforces** and **warns** on the `restricted` profile, both pinned to version `latest`. Write the warning output of the label command to `~/ckad-mocks/exam-06/q14/warnings.txt`.
2. Fix Deployment `metrics-api` so that its Pods are admitted under `restricted` and run:
   - Keep the image, the command and port 8080.
   - Replace the `hostPath` volume with an `emptyDir` at the same mount path.
   - Run as UID `1000`.

End state: 2 Pods of the new revision Running in the restricted namespace. Inside a Pod, `wget -qO- http://localhost:8080` returns `metrics-api ok`.

---

## Question 15 — Blue/green at the Ingress
**Weight:** 4% · **Domain:** Application Deployment · **Namespace:** `m06-bluegreen`

Ingress `tracker` (host `tracker.m06.local`) sends all traffic to Service `tracker-blue`. The new version, green, runs as Deployment `tracker-green` behind Service `tracker-green`.

1. Switch all traffic to green by changing **only** the Ingress. Don't modify either Service or Deployment, and keep blue running.
2. Verify through the ingress controller and write the response body to `~/ckad-mocks/exam-06/q15/after-switch.txt`.
3. Write the single `kubectl` command that would switch traffic back to blue to `~/ckad-mocks/exam-06/q15/rollback-cmd.txt`. Don't run it.

---

## Question 16 — Find your way around an operator
**Weight:** 3% · **Domain:** Application Environment, Configuration and Security · **Namespaces:** cluster-wide

A feature-flag operator is installed in the cluster.

1. CRD `featureflags.flags.m06.ckad.io` serves two versions. Write `deprecated=<version> storage=<version>` to `~/ckad-mocks/exam-06/q16/versions.txt`.
2. Before you create anything in step 4, write every FeatureFlag in the cluster as `<namespace>/<name>`, one per line and sorted, to `~/ckad-mocks/exam-06/q16/flags.txt`.
3. Find the Deployment that runs the operator: its ServiceAccount is granted `update` on featureflags through a ClusterRoleBinding. Write `<namespace>/<deployment>` to `~/ckad-mocks/exam-06/q16/operator.txt`.
4. Using the **non-deprecated** version, create a FeatureFlag `fast-search` in `m06-team-a` with `enabled: true`, `rolloutPercent: 25` and `owner: team-a`.

---

## Question 17 — Build, tag, save, and write a manifest
**Weight:** 5% · **Domain:** Application Design and Build · **Namespace:** `m06-build` (plus podman or docker on your machine)

`~/ckad-mocks/exam-06/q17/` contains a `Dockerfile`, `server.sh` and `www/index.html`.

1. The image must be able to start in a Pod that sets `runAsNonRoot: true` **without** `runAsUser`. Modify the Dockerfile so that it can, changing only its `USER` line.
2. Build the image as `tally:2.1.0`, and also tag it as `registry.m06.local:5000/tally:2.1.0`.
3. Save `registry.m06.local:5000/tally:2.1.0` as a **docker-archive** to `~/ckad-mocks/exam-06/q17/tally-2.1.0.tar`.
4. Write, but **do not apply**, `~/ckad-mocks/exam-06/q17/tally-pod.yaml`. It defines a Pod `tally` in namespace `m06-build` with:
   - container `tally`, image `registry.m06.local:5000/tally:2.1.0`, `imagePullPolicy: IfNotPresent`
   - container port 8080 named `http`, and env `APP_VERSION=2.1.0`
   - an HTTP readiness probe on path `/`, port `http`
   - Pod-level `runAsNonRoot: true`, and container-level `allowPrivilegeEscalation: false`

   The file must pass `kubectl apply --dry-run=server -f`.
5. Afterwards no Pod `tally` may exist in `m06-build`.
