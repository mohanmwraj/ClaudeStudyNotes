# CKAD Mock Exam 04 — Intermediate+

| Duration | Questions | Pass mark | Total weight |
|---|---|---|---|
| 120 min | 19 | 66% | 100% |

> **How to take this exam**
>
> 1. Build a practice cluster (kind or minikube) as described in [Exam overview and lab setup](../../00-Exam-Overview-and-Setup/README.md). For full coverage add metrics-server, an ingress controller (IngressClass `nginx`), a CNI that enforces NetworkPolicies, `helm`, `openssl` and `podman` (or `docker`).
> 2. From this folder run `bash setup.sh`. It creates the namespaces `m04-*`, the pre-existing (partly broken) objects, two Helm releases and the working files under `~/ckad-mocks/exam-04/`, and prints a WARNING for every optional component it cannot find. It takes a few minutes because it waits for some rollouts.
> 3. Start a 120-minute timer.
> 4. Keep only kubernetes.io/docs, kubernetes.io/blog and helm.sh/docs open in your browser (the Kustomize and Podman sites are not allowed in the real exam).
> 5. When the timer ends, stop and grade yourself with [solutions.md](solutions.md). Run `bash cleanup.sh` afterwards.
>
> **How the real exam differs:** it currently runs Kubernetes v1.37 and each task names a host: you `ssh <host>` first, solve the task there, then `exit` back to the base machine (nested ssh is not supported). The guaranteed tools on the exam hosts are `kubectl` (with the `k` alias and completion), `yq`, `curl`, `wget` and `man` — `jq` and `tmux` are not listed, so none of the solutions depend on them.

*These are exam-style tasks modelled on the official CNCF curriculum and on task patterns that candidates describe publicly. Real exam questions are confidential under the Linux Foundation candidate agreement; nothing here is a leaked question.*

**Ground rules for this mock**

- Every task names its namespace. Objects created in the wrong namespace score zero.
- Output files go under `~/ckad-mocks/exam-04/qNN/` (the directories already exist).
- Tasks are independent: you can solve them in any order. Flag long ones and come back.
- Here everything runs against one local cluster. In the real exam, start every task with the `ssh <host>` line it gives you and `exit` when done; check the namespace before you type.
- Allowed images: `nginx:1.27`, `nginx:1.27-alpine`, `busybox:1.36`, `httpd:2.4`, `redis:7.2`, `postgres:16`, `curlimages/curl:8.10.1`, `registry.k8s.io/pause:3.10`.

---

## Question 1 — Work with kubeconfig contexts

**Weight:** 3% · **Domain:** Application Environment, Configuration and Security · **Namespace:** none (kubeconfig file `~/ckad-mocks/exam-04/q01/kubeconfig`)

A colleague left the kubeconfig file `~/ckad-mocks/exam-04/q01/kubeconfig`. Work only on that file by passing it explicitly; do not modify `~/.kube/config`.

- Write the names of all contexts in that file, one per line and nothing else, to `~/ckad-mocks/exam-04/q01/contexts.txt`.
- Write the name of the file's current context to `~/ckad-mocks/exam-04/q01/current-context.txt`.
- Write the API server URL used by context `prod-ops@gamma` to `~/ckad-mocks/exam-04/q01/prod-server.txt`.
- Set the default namespace of context `prod-ops@gamma` to `payments` and make it the current context of that file.

---

## Question 2 — Broken cache Deployment

**Weight:** 5% · **Domain:** Application Observability and Maintenance · **Namespace:** `m04-cache`

The Pods of Deployment `session-cache` are not running.

- Before you fix anything, write the waiting reason of the Pods' container, as reported in the container status, to `~/ckad-mocks/exam-04/q02/reason.txt`.
- Fix the Deployment. The intended image is the official Redis image with the tag `7.2`.
- Add a readiness probe to container `redis` that opens a TCP connection to port `6379`, first 5 seconds after the container starts and then every 10 seconds.
- End state: 2/2 Pods Ready and Service `session-cache` has 2 ready endpoints.

---

## Question 3 — Multi-stage build with a build argument

**Weight:** 5% · **Domain:** Application Design and Build · **Namespace:** none (local image build)

The build context `~/ckad-mocks/exam-04/q03/` contains a multi-stage `Dockerfile` and `app.sh`. Do not modify them. Use `podman` (or `docker`).

- Build the image with the build argument `APP_VERSION=2.4.1` and tag the result as both `m04-api:2.4.1` and `m04-api:stable` with a single build command.
- Save the image `m04-api:2.4.1` in **OCI archive** format to `~/ckad-mocks/exam-04/q03/m04-api-2.4.1.tar`.
- Write the image ID of `m04-api:2.4.1` to `~/ckad-mocks/exam-04/q03/image-id.txt`.
- Running the image must print `inventory-api version 2.4.1`.

---

## Question 4 — Env-file ConfigMap, prefixes and command/args

**Weight:** 5% · **Domain:** Application Environment, Configuration and Security · **Namespace:** `m04-config`

- Create a ConfigMap `batch-config` from the env-file `~/ckad-mocks/exam-04/q04/batch.env` so that every variable in the file becomes its own key.
- Create a Pod `env-printer` with one container `printer`, image `busybox:1.36`, that:
  - receives every key of `batch-config` as an environment variable with the prefix `CFG_` (for example `CFG_MODE`),
  - uses exactly `command: ["sh", "-c"]` and `args: ["env | grep ^CFG_ | sort"]`,
  - is restarted only when it fails (it must not be restarted after a successful run).
- When the Pod has completed, write its logs to `~/ckad-mocks/exam-04/q04/env.txt`.

---

## Question 5 — Roll back to a known-good revision

**Weight:** 5% · **Domain:** Application Deployment · **Namespace:** `m04-rollback`

The latest rollout of Deployment `catalog` is broken.

- Find the revision whose change-cause starts with `v2:` and write its revision number to `~/ckad-mocks/exam-04/q05/revision.txt`.
- Roll `catalog` back to exactly that revision.
- End state: all 3 replicas are Ready and run the image of that revision, and the current revision shows the `v2:` change-cause.

---

## Question 6 — Database access for one team's API only

**Weight:** 6% · **Domain:** Services and Networking · **Namespace:** `m04-db` (clients in `m04-apps` and `m04-other`)

Namespace `m04-db` runs Pod `postgres` (label `app=postgres`, Service `postgres`, port 5432) and already has a default-deny ingress policy. Client Pods run in the namespaces `m04-apps` (namespace label `team=apps`) and `m04-other` (namespace label `team=other`).

Create a NetworkPolicy `postgres-allow-apps-api` in `m04-db` so that:

- Pods labelled `role=api` **in namespaces labelled `team=apps`** can connect to the `app=postgres` Pods on TCP 5432,
- every other Pod cannot connect, including `role=api` Pods in other namespaces and `role=worker` Pods in `m04-apps`.

Do not modify existing NetworkPolicies, Namespaces or Pod labels.

---

## Question 7 — Tune an existing CronJob

**Weight:** 4% · **Domain:** Application Design and Build · **Namespace:** `m04-cron`

Modify the existing CronJob `nightly-report` in place (do not delete and recreate it; keep its schedule and its container unchanged) so that it:

- interprets its schedule in the time zone `Europe/Berlin`,
- never runs two of its Jobs at the same time: a new run is skipped while the previous one is still running,
- skips a run that could not start within 120 seconds of its scheduled time,
- has its finished Jobs deleted automatically 600 seconds after they finish,
- is suspended, so that no new runs start until it is resumed.

---

## Question 8 — Helm housekeeping

**Weight:** 7% · **Domain:** Application Deployment · **Namespace:** `m04-helm-a` (and others)

The chart the team uses is at `~/ckad-mocks/exam-04/q08/webapp`.

1. One Helm release in the cluster is in state `failed`. Find it (search all namespaces), write it as `<namespace>/<release>` to `~/ckad-mocks/exam-04/q08/failed-release.txt`, then uninstall it.
2. Upgrade release `billing` in namespace `m04-helm-a` with that chart so that it runs `3` replicas, using `--set`. Every value that was set for its current revision must stay in effect.
3. Write the user-supplied values of `billing` after the upgrade, in YAML format, to `~/ckad-mocks/exam-04/q08/billing-values.yaml`.

---

## Question 9 — Hardened Pod with a TLS Secret

**Weight:** 6% · **Domain:** Application Environment, Configuration and Security · **Namespace:** `m04-secure`

A certificate and key for `api.m04.local` exist at `~/ckad-mocks/exam-04/q09/tls.crt` and `~/ckad-mocks/exam-04/q09/tls.key`.

- Create a TLS Secret `api-tls` in `m04-secure` from these files.
- Create a Pod `secure-api` with:
  - a Pod-level security context: UID `1000`, GID `3000`, filesystem group `2000`, non-root enforced, seccomp profile `RuntimeDefault`;
  - container `api` (image `busybox:1.36`, command `sh -c 'while true; do sleep 3600; done'`) that runs as UID `2000` (overriding the Pod level), has a read-only root filesystem, no privilege escalation and all capabilities dropped, a writable `emptyDir` mounted at `/tmp`, and Secret `api-tls` mounted read-only at `/etc/tls`;
  - container `audit` (image `busybox:1.36`, same command) with no UID setting of its own, no privilege escalation and all capabilities dropped.
- Write the output of `id` run in container `api` to `~/ckad-mocks/exam-04/q09/id-api.txt`, and in container `audit` to `~/ckad-mocks/exam-04/q09/id-audit.txt`.

---

## Question 10 — Three kinds of Services

**Weight:** 7% · **Domain:** Services and Networking · **Namespace:** `m04-svc`

Deployments `shop-stable` (3 Pods, labels `app=shop,track=stable`) and `shop-canary` (1 Pod, labels `app=shop,track=canary`) run in `m04-svc`. Their containers expose the named ports `http` (80) and `status` (8081). The canary is being withdrawn: it must not receive traffic through the new Services. Do not modify the Deployments.

- Create a ClusterIP Service `shop` with two ports: `http` (port 80 to the container port named `http`) and `status` (port 8081 to the container port named `status`), selecting only the stable Pods.
- Create a NodePort Service `shop-public`: port 80 to the container port named `http`, node port `30784`, stable Pods only.
- Create a Service `payments-gw` that makes the in-cluster name `payments-gw.m04-svc.svc.cluster.local` resolve to the external host `payments.m04.example.com` (a DNS alias: no selector, no proxying).

---

## Question 11 — Resource usage and log slices

**Weight:** 5% · **Domain:** Application Observability and Maintenance · **Namespace:** `m04-metrics`

Namespace `m04-metrics` runs several Pods; Pod `analytics` has the containers `ingest` and `crunch`. This task needs metrics-server.

- Write kubectl's resource-usage view of all Pods in `m04-metrics`, broken down per container and sorted by memory, to `~/ckad-mocks/exam-04/q11/top.txt`.
- Write the container that uses the most memory in the namespace, as `<pod>/<container>`, to `~/ckad-mocks/exam-04/q11/top-container.txt`.
- From container `ingest` of Pod `analytics`, write only log lines from the last 2 minutes, at most the 15 most recent of them, each prefixed with its timestamp, to `~/ckad-mocks/exam-04/q11/ingest.log`.

---

## Question 12 — Adapter container

**Weight:** 6% · **Domain:** Application Design and Build · **Namespace:** `m04-adapter`

Deployment `legacy-reporter` writes log lines in the format `<epoch>|<LEVEL>|<message>` to `/var/log/legacy/app.log` on its volume `logs`. The log pipeline only accepts JSON lines. ConfigMap `adapter-script` contains a converter script `adapt.sh`.

Add a second container to the Deployment:

- name `adapter`, image `busybox:1.36`, command `sh /opt/adapter/adapt.sh`,
- mounts the existing volume `logs` **read-only** at `/var/log/legacy` and ConfigMap `adapter-script` at `/opt/adapter`,
- requests `cpu: 20m`, `memory: 32Mi` and limits `cpu: 100m`, `memory: 64Mi`.

Do not change container `app`. When the new Pod runs, write the last 3 lines of the adapter's output to `~/ckad-mocks/exam-04/q12/adapter.log`.

---

## Question 13 — Least-privilege access for an auditor

**Weight:** 5% · **Domain:** Application Environment, Configuration and Security · **Namespace:** `m04-team-a`

ServiceAccount `auditor` in namespace `m04-team-a` can currently read resources in every namespace. Restrict it:

- Create a ClusterRole `m04-deploy-viewer` that allows only `get`, `list` and `watch` on Deployments and ReplicaSets (API group `apps`).
- Grant it to `auditor` **only in namespace `m04-team-a`**, with a RoleBinding named `auditor-deploy-viewer`.
- Remove whatever currently gives `auditor` cluster-wide access. Do not modify or delete the built-in ClusterRole `view`.
- Create a token for `auditor` that is valid for 2 hours and write only the token to `~/ckad-mocks/exam-04/q13/token.txt`.

---

## Question 14 — Kustomize production overlay

**Weight:** 8% · **Domain:** Application Deployment · **Namespace:** `m04-kustomize`

`~/ckad-mocks/exam-04/q14/base/` contains a Kustomize base (Deployment `inventory` and Service `inventory`). Do not modify files in `base/`.

Create the overlay `~/ckad-mocks/exam-04/q14/overlays/prod/` so that it:

- uses the base and places all objects in namespace `m04-kustomize`,
- adds the label `env: prod` to all objects and to the Pod template, **without** changing any selector,
- applies a strategic-merge patch from the file `resources-patch.yaml` that sets, for container `app`, requests `cpu: 100m`, `memory: 128Mi` and limits `cpu: 500m`, `memory: 256Mi`,
- applies a JSON6902 patch from the file `replicas-patch.yaml`, targeted at Deployment `inventory`, that sets `replicas` to `3` and the image of the first container to `nginx:1.27-alpine`.

Render the overlay to `~/ckad-mocks/exam-04/q14/prod-rendered.yaml` and apply it to the cluster.

---

## Question 15 — Pending PersistentVolumeClaim

**Weight:** 4% · **Domain:** Application Design and Build · **Namespace:** `m04-storage`

PVC `reports-data` and Pod `reports` in `m04-storage` are Pending. An administrator prepared the PersistentVolume `m04-reports-pv` for this claim.

- Make `reports-data` bind to `m04-reports-pv` without modifying the PV. The claim keeps its name and requests `1Gi`.
- Pod `reports` (its manifest is saved at `~/ckad-mocks/exam-04/q15/reports-pod.yaml`) must end up Running with the claim mounted at `/data`.

---

## Question 16 — Migrate deprecated manifests

**Weight:** 5% · **Domain:** Application Observability and Maintenance · **Namespace:** `m04-legacy`

`~/ckad-mocks/exam-04/q16/legacy/` contains `cronjob.yaml` and `hpa.yaml`, written for an old cluster. Neither can be applied any more. Do not modify the legacy files.

- Write the API versions your cluster serves for the groups `batch` and `autoscaling` to `~/ckad-mocks/exam-04/q16/versions.txt`.
- Write two lines to `~/ckad-mocks/exam-04/q16/removed.txt`: `cronjob=<minor>` and `hpa=<minor>`, the Kubernetes minor versions (format `1.NN`) in which the API versions used by the legacy files stopped being served.
- Create migrated copies `~/ckad-mocks/exam-04/q16/fixed/cronjob.yaml` and `~/ckad-mocks/exam-04/q16/fixed/hpa.yaml` that use the current stable API versions and keep every setting, and apply both to namespace `m04-legacy`.

---

## Question 17 — Quota blocks a scale-up

**Weight:** 4% · **Domain:** Application Environment, Configuration and Security · **Namespace:** `m04-quota`

- Scale Deployment `worker` in `m04-quota` to `4` replicas. Not all replicas will appear.
- While the scale-up is blocked, write the `kubectl describe` output of the namespace's ResourceQuota to `~/ckad-mocks/exam-04/q17/quota.txt`.
- Without modifying the ResourceQuota, get all 4 `worker` replicas running. The Pods labelled `purpose=debug` are leftovers and may be deleted; nothing else may be deleted.

---

## Question 18 — Two hosts, one Ingress

**Weight:** 6% · **Domain:** Services and Networking · **Namespace:** `m04-ingress`

The Services `blog` (port 80) and `wiki` (port 8080, named `web`) exist in `m04-ingress`. Create one Ingress named `sites` with IngressClass `nginx`:

- requests for host `blog.m04.local` (path `/`, type `Prefix`) go to Service `blog` on port 80,
- requests for host `wiki.m04.local` (path `/`, type `Prefix`) go to Service `wiki`, referencing its port **by name**,
- requests for any other host are not routed to either application (no default backend).

---

## Question 19 — Extend the API with a CRD

**Weight:** 4% · **Domain:** Application Environment, Configuration and Security · **Namespace:** `m04-crd`

- Create a CustomResourceDefinition for the kind `FeatureFlag` in API group `flags.m04.example.com`, version `v1` (served and storage), namespaced, plural `featureflags`, singular `featureflag`, short name `ff`. Schema: `spec` is an object with the required fields `enabled` (boolean) and `owner` (string) and the optional field `rolloutPercent` (integer, minimum 0, maximum 100).
- Create the FeatureFlag `dark-mode` in namespace `m04-crd` with `enabled: true`, `owner: team-ui` and `rolloutPercent: 25`.
- End state: `kubectl -n m04-crd get ff` lists `dark-mode`, and setting `rolloutPercent` to 150 is rejected by the API server.

---

**End of exam.** Stop the timer and grade yourself with [solutions.md](solutions.md).
