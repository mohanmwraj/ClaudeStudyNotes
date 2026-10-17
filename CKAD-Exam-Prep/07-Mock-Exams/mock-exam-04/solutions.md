# CKAD Mock Exam 04 — Solutions

Grade yourself honestly: a part scores only if its end state is exactly what the task asked for (names, namespace, files). Partial credit follows the **Points** line of each solution. Pass mark: **66%**.

## Domain weights

| Domain | Questions | Weight |
|---|---|---|
| Application Design and Build | Q3, Q7, Q12, Q15 | 19% |
| Application Deployment | Q5, Q8, Q14 | 20% |
| Application Observability and Maintenance | Q2, Q11, Q16 | 15% |
| Application Environment, Configuration and Security | Q1, Q4, Q9, Q13, Q17, Q19 | 27% |
| Services and Networking | Q6, Q10, Q18 | 19% |
| **Total** | **19 questions** | **100%** |

Conventions used below: `kubectl` is written out (in the exam use the preconfigured `k` alias). The fastest generator pattern is `kubectl ... --dry-run=client -o yaml > file.yaml`, then edit with vim and `kubectl apply -f file.yaml`. No solution needs `jq`; JSONPath and custom columns are enough.

---

## Question 1 — Work with kubeconfig contexts (3%)

**Approach:** every `kubectl config` subcommand accepts `--kubeconfig <file>`. Read the current context **before** switching it, and use JSONPath filters to pull a single value.

```bash
K=~/ckad-mocks/exam-04/q01/kubeconfig
kubectl config get-contexts --kubeconfig "$K"                         # table view, * marks the current context
kubectl config get-contexts --kubeconfig "$K" -o name > ~/ckad-mocks/exam-04/q01/contexts.txt
kubectl config current-context --kubeconfig "$K" > ~/ckad-mocks/exam-04/q01/current-context.txt
kubectl config view --kubeconfig "$K" -o jsonpath='{.contexts[?(@.name=="prod-ops@gamma")].context.cluster}{"\n"}'   # gamma
kubectl config view --kubeconfig "$K" -o jsonpath='{.clusters[?(@.name=="gamma")].cluster.server}' > ~/ckad-mocks/exam-04/q01/prod-server.txt
kubectl config set-context prod-ops@gamma --namespace=payments --kubeconfig "$K"
kubectl config use-context prod-ops@gamma --kubeconfig "$K"
```

**Verify:**

```bash
cat ~/ckad-mocks/exam-04/q01/contexts.txt           # dev-admin@alpha, prod-ops@gamma, qa-viewer@beta (one per line)
cat ~/ckad-mocks/exam-04/q01/current-context.txt    # qa-viewer@beta
cat ~/ckad-mocks/exam-04/q01/prod-server.txt        # https://10.20.30.40:6443
kubectl config get-contexts --kubeconfig ~/ckad-mocks/exam-04/q01/kubeconfig   # * prod-ops@gamma ... NAMESPACE payments
kubectl config current-context                      # your own kubeconfig is unchanged
```

**Common mistakes:**
- Forgetting `--kubeconfig`: you change your real `~/.kube/config` (in the exam that can break every later task).
- `kubectl config set-context --current --namespace=payments` changes the *current* context (`qa-viewer@beta`), not `prod-ops@gamma`.
- Writing `current-context.txt` after `use-context`, or writing the table instead of `-o name`.

**Points:** 1% `contexts.txt` · 0.5% `current-context.txt` · 0.5% `prod-server.txt` · 1% namespace set on `prod-ops@gamma` and it is the current context of the file.

---

## Question 2 — Broken cache Deployment (5%)

**Approach:** `kubectl get pods` shows `ErrImagePull`/`ImagePullBackOff`; `describe` shows the tag `7.2-alpline` does not exist. Fix the image and add the probe in one change, so only one new rollout happens.

```bash
kubectl -n m04-cache get pods -l app=session-cache
kubectl -n m04-cache get pods -l app=session-cache \
  -o jsonpath='{.items[0].status.containerStatuses[0].state.waiting.reason}{"\n"}' > ~/ckad-mocks/exam-04/q02/reason.txt
kubectl -n m04-cache describe pod -l app=session-cache | grep -iE 'image|failed' | head -n 6
kubectl -n m04-cache patch deployment session-cache --type=json -p='[
  {"op":"replace","path":"/spec/template/spec/containers/0/image","value":"redis:7.2"},
  {"op":"add","path":"/spec/template/spec/containers/0/readinessProbe","value":{"tcpSocket":{"port":6379},"initialDelaySeconds":5,"periodSeconds":10}}]'
kubectl -n m04-cache rollout status deployment session-cache
```

The resulting Deployment (what `kubectl edit` would leave you with):

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: session-cache
  namespace: m04-cache
  labels:
    app: session-cache
spec:
  replicas: 2
  selector:
    matchLabels:
      app: session-cache
  template:
    metadata:
      labels:
        app: session-cache
    spec:
      containers:
      - name: redis
        image: redis:7.2
        ports:
        - containerPort: 6379
        readinessProbe:
          tcpSocket:
            port: 6379
          initialDelaySeconds: 5
          periodSeconds: 10
```

**Verify:**

```bash
cat ~/ckad-mocks/exam-04/q02/reason.txt                       # ImagePullBackOff (or ErrImagePull)
kubectl -n m04-cache get pods -l app=session-cache            # 2 Pods, READY 1/1
kubectl -n m04-cache get endpointslices -l kubernetes.io/service-name=session-cache \
  -o jsonpath='{range .items[*].endpoints[*]}{.addresses[0]} ready={.conditions.ready}{"\n"}{end}'   # 2 lines, ready=true
```

**Common mistakes:**
- `kubectl set image deploy/session-cache session-cache=redis:7.2`: the container is called `redis`, so kubectl reports that the container was not found.
- An `httpGet` probe against Redis (it does not speak HTTP), or `exec: redis-cli ping` when a TCP check was asked for.
- Editing a Pod instead of the Deployment template.

**Points:** 1% `reason.txt` · 2% image fixed · 1.5% readiness probe exactly as specified · 0.5% two ready endpoints.

---

## Question 3 — Multi-stage build with a build argument (5%)

**Approach:** `--build-arg` feeds the `ARG` of the build stage; repeat `-t` to tag twice in one build; `--format oci-archive` selects the OCI layout for `podman save`.

```bash
cd ~/ckad-mocks/exam-04/q03
cat Dockerfile                    # ARG APP_VERSION in stage "build", runtime stage copies /src/app
podman build --build-arg APP_VERSION=2.4.1 -t m04-api:2.4.1 -t m04-api:stable .
podman run --rm m04-api:2.4.1     # inventory-api version 2.4.1
podman save --format oci-archive -o m04-api-2.4.1.tar m04-api:2.4.1
podman image inspect m04-api:2.4.1 --format '{{.Id}}' > image-id.txt
```

Docker equivalent: `docker build --build-arg APP_VERSION=2.4.1 -t m04-api:2.4.1 -t m04-api:stable .`, `docker save -o m04-api-2.4.1.tar m04-api:2.4.1` (there is no `--format` flag; since Docker Engine 25 the `docker image save` tarball is OCI compliant) and `docker image inspect --format '{{.Id}}' m04-api:2.4.1 > image-id.txt`.

**Verify:**

```bash
podman images m04-api                         # tags 2.4.1 and stable with the same IMAGE ID
tar -tf m04-api-2.4.1.tar | head -n 5         # oci-layout, index.json, blobs/sha256/...
cat image-id.txt                              # 64 hex characters (or the 12-character short ID)
```

**Common mistakes:**
- `podman save` without `--format oci-archive`: the default is a docker-archive.
- Two separate builds for the two tags (works, but the task asks for a single command) or tagging after the build with a typo.
- Forgetting the build argument: the image prints `inventory-api version 0.0.0-dev`.

**Points:** 2% build with the argument and both tags · 2% OCI archive of `m04-api:2.4.1` · 1% image ID file.

---

## Question 4 — Env-file ConfigMap, prefixes and command/args (5%)

**Approach:** `--from-env-file` turns each `KEY=value` line into its own key (comments and blank lines are skipped). `envFrom` takes an optional `prefix`. Without `--command`, the words after `--` in `kubectl run` become `args`, so add `command` by hand.

```bash
kubectl -n m04-config create configmap batch-config --from-env-file="$HOME/ckad-mocks/exam-04/q04/batch.env"
kubectl -n m04-config get configmap batch-config -o jsonpath='{.data}{"\n"}'   # {"MODE":"batch","REGION":"eu-west-1","RETRIES":"3"}
kubectl -n m04-config run env-printer --image=busybox:1.36 --restart=OnFailure \
  --dry-run=client -o yaml -- 'env | grep ^CFG_ | sort' > q04.yaml
vim q04.yaml       # container name printer, add command and envFrom (below)
kubectl apply -f q04.yaml
kubectl -n m04-config get pod env-printer      # STATUS Completed, RESTARTS 0
kubectl -n m04-config logs env-printer > ~/ckad-mocks/exam-04/q04/env.txt
```

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: env-printer
  namespace: m04-config
spec:
  restartPolicy: OnFailure          # restart only after a failure
  containers:
  - name: printer
    image: busybox:1.36
    command: ["sh", "-c"]           # overrides the image ENTRYPOINT
    args: ["env | grep ^CFG_ | sort"]   # overrides the image CMD
    envFrom:
    - prefix: CFG_
      configMapRef:
        name: batch-config
```

Expected `env.txt`:

```text
CFG_MODE=batch
CFG_REGION=eu-west-1
CFG_RETRIES=3
```

**Verify:**

```bash
kubectl -n m04-config get pod env-printer \
  -o jsonpath='{.status.phase} {.spec.restartPolicy} {.spec.containers[0].command} {.spec.containers[0].args}{"\n"}'
# Succeeded OnFailure ["sh","-c"] ["env | grep ^CFG_ | sort"]
cat ~/ckad-mocks/exam-04/q04/env.txt
```

**Common mistakes:**
- `--from-file=batch.env`: one key named `batch.env` containing the whole file.
- `--command -- sh -c '...'`: everything ends up in `command` and `args` stays empty.
- `prefix` indented under `configMapRef` (it belongs to the `envFrom` entry), or `restartPolicy: Never`.

**Points:** 1.5% ConfigMap with three keys · 2% Pod with exact `command`/`args` and `restartPolicy: OnFailure` · 1% prefixed `envFrom` · 0.5% logs file.

---

## Question 5 — Roll back to a known-good revision (5%)

**Approach:** read the change-causes with `rollout history`, confirm the template of the chosen revision, then `rollout undo --to-revision`. The old revision is re-used and renumbered as the newest one.

```bash
kubectl -n m04-rollback rollout history deployment catalog
# REVISION  CHANGE-CAUSE
# 1         v1: initial release on nginx 1.27
# 2         v2: switch to the alpine base image
# 3         v3: migrate to httpd
# 4         v4: experimental cache warm-up
kubectl -n m04-rollback rollout history deployment catalog --revision=2     # Image: nginx:1.27-alpine, no command
echo 2 > ~/ckad-mocks/exam-04/q05/revision.txt
kubectl -n m04-rollback rollout undo deployment catalog --to-revision=2
kubectl -n m04-rollback rollout status deployment catalog
kubectl -n m04-rollback rollout history deployment catalog                  # 1, 3, 4, 5 (revision 2 is now 5)
```

**Verify:**

```bash
kubectl -n m04-rollback get deploy catalog \
  -o jsonpath='{.spec.template.spec.containers[0].image} {.spec.template.spec.containers[0].command} | {.metadata.annotations.kubernetes\.io/change-cause}{"\n"}'
# nginx:1.27-alpine  | v2: switch to the alpine base image
kubectl -n m04-rollback get pods -l app=catalog      # 3/3 Running, no CrashLoopBackOff
```

**Common mistakes:**
- `kubectl rollout undo` without `--to-revision`: that goes back one step, to revision 3 (httpd).
- Re-creating revision 2 by hand with `set image`: the image matches but the change-cause and history do not.
- Expecting revision number 2 to remain in the history after the rollback.

**Points:** 1% `revision.txt` · 3% rolled back to the revision 2 template · 1% 3/3 Ready and the `v2:` change-cause is current.

---

## Question 6 — Database access for one team's API only (6%)

**Approach:** put `namespaceSelector` and `podSelector` in the **same** `from` element, so both must match (AND). Two separate list items would be an OR and let in every Pod of `m04-apps` plus every `role=api` Pod of `m04-db`.

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: postgres-allow-apps-api
  namespace: m04-db
spec:
  podSelector:
    matchLabels:
      app: postgres
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:          # same list element as podSelector = AND
        matchLabels:
          team: apps
      podSelector:
        matchLabels:
          role: api
    ports:
    - protocol: TCP
      port: 5432
```

```bash
kubectl apply -f q06-netpol.yaml
kubectl -n m04-db describe netpol postgres-allow-apps-api
```

**Verify** (needs a CNI that enforces NetworkPolicy):

```bash
kubectl -n m04-apps  exec api    -- nc -zv -w 2 postgres.m04-db.svc.cluster.local 5432   # open
kubectl -n m04-apps  exec worker -- nc -zv -w 2 postgres.m04-db.svc.cluster.local 5432   # timed out
kubectl -n m04-other exec api    -- nc -zv -w 2 postgres.m04-db.svc.cluster.local 5432   # timed out
```

**Common mistakes:**
- A `-` in front of `podSelector` (two elements, OR semantics).
- Selecting the namespace by `kubernetes.io/metadata.name: m04-apps`: it works today but ignores the requirement "namespaces labelled `team=apps`".
- Omitting `ports` (allows every port) or using the Service port name instead of the Pod port.

**Points:** 1% policy selects the postgres Pods · 3% AND-combined namespace and Pod selectors · 1% port TCP 5432 · 1% traffic behaves as required.

---

## Question 7 — Tune an existing CronJob (4%)

**Approach:** a merge patch changes the fields in place (same object, same UID). `ttlSecondsAfterFinished` belongs to the **Job** spec, i.e. under `jobTemplate.spec`.

```bash
kubectl -n m04-cron patch cronjob nightly-report --type=merge -p '{"spec":{
  "timeZone":"Europe/Berlin","concurrencyPolicy":"Forbid","startingDeadlineSeconds":120,"suspend":true,
  "jobTemplate":{"spec":{"ttlSecondsAfterFinished":600}}}}'
```

The resulting object (`kubectl edit` gives the same result):

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: nightly-report
  namespace: m04-cron
spec:
  schedule: "30 1 * * *"
  timeZone: Europe/Berlin           # GA since v1.27
  concurrencyPolicy: Forbid         # skip a run while the previous one is active
  startingDeadlineSeconds: 120
  suspend: true
  jobTemplate:
    spec:
      ttlSecondsAfterFinished: 600  # Job field, not CronJob field
      template:
        spec:
          restartPolicy: OnFailure
          containers:
          - name: report
            image: busybox:1.36
            command: ["sh", "-c", "date; echo nightly report done"]
```

**Verify:**

```bash
kubectl -n m04-cron get cronjob nightly-report -o jsonpath='{.spec.schedule} | {.spec.timeZone} | {.spec.concurrencyPolicy} | {.spec.startingDeadlineSeconds} | {.spec.suspend} | {.spec.jobTemplate.spec.ttlSecondsAfterFinished}{"\n"}'
# 30 1 * * * | Europe/Berlin | Forbid | 120 | true | 600
kubectl -n m04-cron get cronjob nightly-report -o jsonpath='{.metadata.creationTimestamp}{"\n"}'   # from setup time: not recreated
```

**Common mistakes:**
- `concurrencyPolicy: Replace` (kills the running Job instead of skipping the new one).
- `ttlSecondsAfterFinished` at CronJob level (rejected as unknown field) or `TZ=Europe/Berlin` inside `schedule` (rejected; use `timeZone`).
- Deleting and recreating the CronJob.

**Points:** 1% time zone · 1% `Forbid` · 0.5% starting deadline · 1% TTL on the Job template · 0.5% suspended.

---

## Question 8 — Helm housekeeping (7%)

**Approach:** `helm list -A --failed` finds failed releases in every namespace. For the upgrade use `--reuse-values` so the values of the current revision (`podAnnotations.team=billing`) survive the new `--set`. `helm get values` shows only user-supplied values.

```bash
helm list -A --failed                       # m04-helm-b  reports  ...  failed
echo "m04-helm-b/reports" > ~/ckad-mocks/exam-04/q08/failed-release.txt
helm uninstall reports -n m04-helm-b
helm get values billing -n m04-helm-a       # podAnnotations: team: billing / replicaCount: 1
helm upgrade billing ~/ckad-mocks/exam-04/q08/webapp -n m04-helm-a --reuse-values --set replicaCount=3
helm get values billing -n m04-helm-a -o yaml > ~/ckad-mocks/exam-04/q08/billing-values.yaml
```

Expected `billing-values.yaml`:

```yaml
podAnnotations:
  team: billing
replicaCount: 3
```

**Verify:**

```bash
helm list -A                                 # no failed release; billing at REVISION 2, deployed
kubectl -n m04-helm-a get deploy billing-webapp          # READY 3/3
kubectl -n m04-helm-a get pods -l app.kubernetes.io/instance=billing \
  -o jsonpath='{range .items[*]}{.metadata.annotations.team}{"\n"}{end}'   # billing (3 lines)
```

**Common mistakes:**
- `helm upgrade billing <chart> --set replicaCount=3` without `--reuse-values`: the `team` annotation disappears.
- `helm get values --all` (prints every computed value, not the user-supplied ones).
- `helm uninstall reports` without `-n m04-helm-b` ("release: not found").

**Points:** 1% failed-release file · 1.5% `reports` uninstalled · 3% `billing` at 3 replicas with the annotation kept · 1.5% values file.

---

## Question 9 — Hardened Pod with a TLS Secret (6%)

**Approach:** Pod-level `securityContext` holds UID/GID defaults, `fsGroup` and seccomp; container-level fields override UID and add `readOnlyRootFilesystem`, `allowPrivilegeEscalation` and capabilities (container-only fields). A read-only root needs a writable `emptyDir` for `/tmp`.

```bash
kubectl -n m04-secure create secret tls api-tls \
  --cert="$HOME/ckad-mocks/exam-04/q09/tls.crt" --key="$HOME/ckad-mocks/exam-04/q09/tls.key"
kubectl -n m04-secure run secure-api --image=busybox:1.36 --dry-run=client -o yaml \
  --command -- sh -c 'while true; do sleep 3600; done' > q09.yaml
vim q09.yaml        # complete it as below
kubectl apply -f q09.yaml
kubectl -n m04-secure exec secure-api -c api -- id > ~/ckad-mocks/exam-04/q09/id-api.txt
kubectl -n m04-secure exec secure-api -c audit -- id > ~/ckad-mocks/exam-04/q09/id-audit.txt
```

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: secure-api
  namespace: m04-secure
spec:
  securityContext:                  # Pod level: defaults for all containers
    runAsUser: 1000
    runAsGroup: 3000
    fsGroup: 2000                   # Pod-level only
    runAsNonRoot: true
    seccompProfile:
      type: RuntimeDefault
  containers:
  - name: api
    image: busybox:1.36
    command: ["sh", "-c", "while true; do sleep 3600; done"]
    securityContext:
      runAsUser: 2000               # overrides the Pod-level 1000
      readOnlyRootFilesystem: true  # container-level only
      allowPrivilegeEscalation: false
      capabilities:
        drop: ["ALL"]
    volumeMounts:
    - name: tmp
      mountPath: /tmp
    - name: tls
      mountPath: /etc/tls
      readOnly: true
  - name: audit
    image: busybox:1.36
    command: ["sh", "-c", "while true; do sleep 3600; done"]
    securityContext:
      allowPrivilegeEscalation: false
      capabilities:
        drop: ["ALL"]
  volumes:
  - name: tmp
    emptyDir: {}
  - name: tls
    secret:
      secretName: api-tls
```

**Verify:**

```bash
cat ~/ckad-mocks/exam-04/q09/id-api.txt          # uid=2000 gid=3000 groups=... (includes 2000)
cat ~/ckad-mocks/exam-04/q09/id-audit.txt        # uid=1000 gid=3000 groups=... (includes 2000)
kubectl -n m04-secure exec secure-api -c api -- touch /probe        # touch: /probe: Read-only file system
kubectl -n m04-secure exec secure-api -c api -- touch /tmp/probe    # works
kubectl -n m04-secure exec secure-api -c api -- ls /etc/tls         # tls.crt tls.key
kubectl -n m04-secure exec secure-api -c api -- grep CapEff /proc/1/status   # 0000000000000000
kubectl -n m04-secure get secret api-tls -o jsonpath='{.type}{"\n"}'          # kubernetes.io/tls
```

**Common mistakes:**
- `readOnlyRootFilesystem`, `allowPrivilegeEscalation` or `capabilities` in the Pod-level context, or `fsGroup` at container level: the API server rejects unknown fields.
- `drop: ["all"]` instead of `ALL`, or capability names with a `CAP_` prefix (YAML uses `NET_ADMIN`, not `CAP_NET_ADMIN`).
- `kubectl create secret generic` for the certificate (type `Opaque` instead of `kubernetes.io/tls`).

**Points:** 1% TLS Secret · 1.5% Pod-level security context · 2% `api` container (UID override, read-only root, no escalation, drop ALL, both mounts) · 0.5% `audit` container · 1% both `id` files.

---

## Question 10 — Three kinds of Services (7%)

**Approach:** generate the Services, then fix selectors (`app=shop,track=stable` keeps the canary out), port names and named target ports. `kubectl create service nodeport --node-port` sets the fixed node port; `kubectl create service externalname` creates the DNS alias.

```bash
kubectl -n m04-svc get pods --show-labels
kubectl -n m04-svc create service clusterip shop --tcp=80:80 --tcp=8081:8081 --dry-run=client -o yaml > shop.yaml
kubectl -n m04-svc create service nodeport shop-public --tcp=80:80 --node-port=30784 --dry-run=client -o yaml > shop-public.yaml
vim shop.yaml shop-public.yaml      # selector app=shop + track=stable, port names, targetPort http/status
kubectl apply -f shop.yaml -f shop-public.yaml
kubectl -n m04-svc create service externalname payments-gw --external-name=payments.m04.example.com
```

```yaml
apiVersion: v1
kind: Service
metadata:
  name: shop
  namespace: m04-svc
spec:
  type: ClusterIP
  selector:
    app: shop
    track: stable                   # the canary has track=canary
  ports:
  - name: http
    port: 80
    targetPort: http                # container port name
  - name: status
    port: 8081
    targetPort: status
---
apiVersion: v1
kind: Service
metadata:
  name: shop-public
  namespace: m04-svc
spec:
  type: NodePort
  selector:
    app: shop
    track: stable
  ports:
  - name: http
    port: 80
    targetPort: http
    nodePort: 30784                 # must be inside the node port range (default 30000-32767)
---
apiVersion: v1
kind: Service
metadata:
  name: payments-gw
  namespace: m04-svc
spec:
  type: ExternalName
  externalName: payments.m04.example.com
```

**Verify:**

```bash
kubectl -n m04-svc get svc                       # shop ClusterIP 80/TCP,8081/TCP; shop-public 80:30784/TCP; payments-gw ExternalName
kubectl -n m04-svc get endpointslices -l kubernetes.io/service-name=shop \
  -o jsonpath='{range .items[*].endpoints[*]}{.targetRef.name}{"\n"}{end}'     # 3 shop-stable-... Pods, no canary
kubectl -n m04-svc run svc-test --rm -i --restart=Never --image=busybox:1.36 -- \
  sh -c 'for i in 1 2 3 4 5 6; do wget -qO- http://shop:8081/healthz; done; nslookup payments-gw | grep -i canonical'
# stable-ok (6 times) and "canonical name = payments.m04.example.com"
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
kubectl -n m04-svc run np-test --rm -i --restart=Never --image=busybox:1.36 -- wget -qO- "http://$NODE_IP:30784" | grep -m1 title
```

**Common mistakes:**
- Selector `app=shop` only: the canary Pod is included (4 endpoints, `canary-ok` appears).
- A multi-port Service without port names (the API server rejects it).
- Trying to set the node port with `kubectl expose` (no such flag: generate YAML or use `kubectl create service nodeport --node-port`).
- An ExternalName pointing to an IP address, or adding a selector to it (ExternalName is pure DNS).

**Points:** 3% `shop` (two named ports, named target ports, stable-only selector) · 2% `shop-public` with node port 30784 · 2% `payments-gw` ExternalName.

---

## Question 11 — Resource usage and log slices (5%)

**Approach:** `kubectl top pods --containers --sort-by=memory` lists every container; the sorting is done per Pod (by the Pod total), so read the highest single container from the rows. `--since`, `--tail` and `--timestamps` combine: lines newer than 2 minutes, of those the last 15.

```bash
kubectl top pods -n m04-metrics --containers --sort-by=memory > ~/ckad-mocks/exam-04/q11/top.txt
cat ~/ckad-mocks/exam-04/q11/top.txt
# POD            NAME     CPU(cores)   MEMORY(bytes)
# analytics      crunch   0m           49Mi
# analytics      ingest   1m           1Mi
# cache-warmer   warmer   0m           21Mi
# idle           idle     0m           0Mi
echo "analytics/crunch" > ~/ckad-mocks/exam-04/q11/top-container.txt
kubectl -n m04-metrics logs analytics -c ingest --since=2m --tail=15 --timestamps > ~/ckad-mocks/exam-04/q11/ingest.log
```

**Verify:**

```bash
wc -l < ~/ckad-mocks/exam-04/q11/ingest.log         # 15 (the container logs every 2 s)
head -n 2 ~/ckad-mocks/exam-04/q11/ingest.log       # 2026-10-21T09:14:03.123456789Z ingested batch 412
cat ~/ckad-mocks/exam-04/q11/top-container.txt      # analytics/crunch
```

**Common mistakes:**
- Forgetting `--containers` (one line per Pod only) or `--sort-by=mem` (valid values are `cpu` and `memory`).
- Only `--tail=15` (may include lines older than 2 minutes) or only `--since=2m` (about 60 lines).
- Running `top` in the first minute after setup: metrics-server needs a scrape cycle before it reports new Pods.

**Points:** 2% `top.txt` per container and sorted by memory · 1% `top-container.txt` · 2% `ingest.log` (since, tail, timestamps).

---

## Question 12 — Adapter container (6%)

**Approach:** the adapter shares the `logs` volume (read-only) and runs the converter from the mounted ConfigMap; its stdout is what the log pipeline collects. Add a ConfigMap volume to the Pod template, then the container.

```bash
kubectl -n m04-adapter get configmap adapter-script -o yaml
kubectl -n m04-adapter get deployment legacy-reporter -o yaml > q12.yaml
vim q12.yaml           # add the adapter container and the adapter-script volume (below)
kubectl apply -f q12.yaml
kubectl -n m04-adapter rollout status deployment legacy-reporter
kubectl -n m04-adapter logs deployment/legacy-reporter -c adapter --tail=3 > ~/ckad-mocks/exam-04/q12/adapter.log
```

The Deployment after the change:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: legacy-reporter
  namespace: m04-adapter
  labels:
    app: legacy-reporter
spec:
  replicas: 1
  selector:
    matchLabels:
      app: legacy-reporter
  template:
    metadata:
      labels:
        app: legacy-reporter
    spec:
      containers:
      - name: app
        image: busybox:1.36
        command: ["sh", "-c", "i=0; while true; do i=$((i+1)); echo \"$(date +%s)|INFO|report $i generated\" >> /var/log/legacy/app.log; sleep 3; done"]
        volumeMounts:
        - name: logs
          mountPath: /var/log/legacy
      - name: adapter
        image: busybox:1.36
        command: ["sh", "/opt/adapter/adapt.sh"]
        resources:
          requests:
            cpu: 20m
            memory: 32Mi
          limits:
            cpu: 100m
            memory: 64Mi
        volumeMounts:
        - name: logs
          mountPath: /var/log/legacy
          readOnly: true
        - name: adapter-script
          mountPath: /opt/adapter
      volumes:
      - name: logs
        emptyDir: {}
      - name: adapter-script
        configMap:
          name: adapter-script
```

**Verify:**

```bash
cat ~/ckad-mocks/exam-04/q12/adapter.log
# {"ts":1792571234,"level":"INFO","msg":"report 17 generated"}  (3 lines)
kubectl -n m04-adapter get pods -l app=legacy-reporter          # READY 2/2
kubectl -n m04-adapter get deploy legacy-reporter \
  -o jsonpath='{range .spec.template.spec.containers[*]}{.name}: {.resources} {.volumeMounts}{"\n"}{end}'
```

**Common mistakes:**
- Mounting the ConfigMap without declaring the `adapter-script` volume (the API server rejects the unknown volume name).
- Making the adapter an init container: a classic init container must finish before `app` starts, and this one never finishes.
- `kubectl logs deployment/legacy-reporter` without `-c adapter` (shows the first container, `app`, which writes nothing to stdout).

**Points:** 1.5% `adapter` container with the right image and command · 2% read-only `logs` mount and ConfigMap volume · 1% requests and limits · 1.5% `adapter.log` with JSON lines, `app` unchanged.

---

## Question 13 — Least-privilege access for an auditor (5%)

**Approach:** find the binding that grants too much (`-o wide` shows the subjects), delete it, then create a ClusterRole (a reusable rule set) and bind it with a **RoleBinding**, which limits it to one namespace.

```bash
SA=system:serviceaccount:m04-team-a:auditor
kubectl auth can-i list deployments.apps -n m04-team-b --as="$SA"          # yes (too much)
kubectl get clusterrolebindings -o wide | grep -E '^NAME|auditor'
# m04-auditor-everywhere   ClusterRole/view   ...   m04-team-a/auditor
kubectl delete clusterrolebinding m04-auditor-everywhere
kubectl create clusterrole m04-deploy-viewer --verb=get,list,watch --resource=deployments.apps,replicasets.apps
kubectl -n m04-team-a create rolebinding auditor-deploy-viewer \
  --clusterrole=m04-deploy-viewer --serviceaccount=m04-team-a:auditor
kubectl -n m04-team-a create token auditor --duration=2h > ~/ckad-mocks/exam-04/q13/token.txt
```

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: m04-deploy-viewer
rules:
- apiGroups: ["apps"]
  resources: ["deployments", "replicasets"]
  verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: auditor-deploy-viewer
  namespace: m04-team-a          # the binding's namespace limits the ClusterRole's scope
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: m04-deploy-viewer
subjects:
- kind: ServiceAccount
  name: auditor
  namespace: m04-team-a
```

**Verify:**

```bash
SA=system:serviceaccount:m04-team-a:auditor
kubectl auth can-i list deployments.apps -n m04-team-a --as="$SA"     # yes
kubectl auth can-i watch replicasets.apps -n m04-team-a --as="$SA"    # yes
kubectl auth can-i list deployments.apps -n m04-team-b --as="$SA"     # no
kubectl auth can-i list pods -n m04-team-a --as="$SA"                 # no
APISERVER=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')
curl -sk -H "Authorization: Bearer $(cat ~/ckad-mocks/exam-04/q13/token.txt)" \
  "$APISERVER/apis/apps/v1/namespaces/m04-team-a/deployments" | grep -m1 '"kind"'   # "kind": "DeploymentList"
```

`curl` is the honest token test: `kubectl --token=...` combined with a client-certificate kubeconfig may still authenticate with the certificate.

**Common mistakes:**
- A ClusterRoleBinding for the new role: access is cluster-wide again.
- Leaving `m04-auditor-everywhere` in place (permissions are additive, so the old binding still grants `view` everywhere).
- Editing or deleting the built-in `view` ClusterRole, or writing kubectl output besides the token into `token.txt`.

**Points:** 1.5% ClusterRole with exactly the requested rules · 1.5% RoleBinding in `m04-team-a` · 1% cluster-wide binding removed · 1% token file.

---

## Question 14 — Kustomize production overlay (8%)

**Approach:** an overlay references the base as a resource. `labels` with `includeSelectors: false` and `includeTemplates: true` labels objects and Pod templates but leaves selectors alone (the deprecated `commonLabels` would change selectors too). Both patch types go under `patches`; the JSON6902 one needs a `target`.

```bash
mkdir -p ~/ckad-mocks/exam-04/q14/overlays/prod && cd ~/ckad-mocks/exam-04/q14/overlays/prod
cat > resources-patch.yaml <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: inventory
spec:
  template:
    spec:
      containers:
      - name: app
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 500m
            memory: 256Mi
EOF
vim replicas-patch.yaml kustomization.yaml      # contents below
kubectl kustomize . > ~/ckad-mocks/exam-04/q14/prod-rendered.yaml
kubectl apply -k .
```

`replicas-patch.yaml` (JSON6902 operations written as YAML):

```yaml
- op: replace
  path: /spec/replicas
  value: 3
- op: replace
  path: /spec/template/spec/containers/0/image
  value: nginx:1.27-alpine
```

`kustomization.yaml`:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: m04-kustomize
resources:
- ../../base
labels:
- pairs:
    env: prod
  includeSelectors: false        # do not touch spec.selector / Service selectors
  includeTemplates: true         # but do label the Pod template
patches:
- path: resources-patch.yaml     # strategic merge: target taken from kind/name inside the file
- path: replicas-patch.yaml      # JSON6902: needs an explicit target
  target:
    group: apps
    version: v1
    kind: Deployment
    name: inventory
```

**Verify:**

```bash
grep -c 'env: prod' ~/ckad-mocks/exam-04/q14/prod-rendered.yaml       # 3 (Service, Deployment, Pod template)
kubectl -n m04-kustomize get deploy inventory \
  -o jsonpath='{.spec.replicas} {.spec.template.spec.containers[0].image} {.spec.selector.matchLabels} {.spec.template.metadata.labels}{"\n"}'
# 3 nginx:1.27-alpine {"app":"inventory"} {"app":"inventory","env":"prod"}
kubectl -n m04-kustomize get deploy inventory -o jsonpath='{.spec.template.spec.containers[0].resources}{"\n"}'
kubectl -n m04-kustomize get svc inventory -o jsonpath='{.metadata.labels} {.spec.selector}{"\n"}'
# {"app":"inventory","env":"prod"} {"app":"inventory"}
```

**Common mistakes:**
- `commonLabels: {env: prod}`: it also rewrites the selectors (and a Deployment's selector is immutable once created).
- A JSON6902 patch without `target`, or a path like `/spec/template/spec/containers/app/image` (JSON pointers need the list index).
- Editing files in `base/`, or rendering with `kustomize build` when only `kubectl kustomize` is available.

**Points:** 1.5% overlay with base resource and namespace · 2% `env: prod` on objects and template, selectors untouched · 2% strategic-merge resources patch · 2% JSON6902 patch with target · 0.5% rendered file and applied.

---

## Question 15 — Pending PersistentVolumeClaim (4%)

**Approach:** the claim asks for StorageClass `fast-ssd` (does not exist) and `ReadWriteMany` (the PV offers `ReadWriteOnce` with class `manual`). Those PVC fields are immutable, so save the Pod manifest, delete Pod and PVC, recreate the PVC to match the PV, then recreate the Pod.

```bash
kubectl -n m04-storage describe pvc reports-data | tail -n 3      # storageclass.storage.k8s.io "fast-ssd" not found
kubectl get pv m04-reports-pv \
  -o custom-columns=NAME:.metadata.name,CLASS:.spec.storageClassName,MODES:.spec.accessModes,SIZE:.spec.capacity.storage,STATUS:.status.phase
# m04-reports-pv   manual   [ReadWriteOnce]   1Gi   Available
kubectl -n m04-storage delete pod reports
kubectl -n m04-storage delete pvc reports-data
kubectl apply -f q15-pvc.yaml
kubectl apply -f ~/ckad-mocks/exam-04/q15/reports-pod.yaml
```

`q15-pvc.yaml`:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: reports-data
  namespace: m04-storage
spec:
  storageClassName: manual        # must equal the PV's class
  accessModes:
  - ReadWriteOnce                 # must be offered by the PV
  resources:
    requests:
      storage: 1Gi
  volumeName: m04-reports-pv      # optional: pre-binds to exactly this PV
```

**Verify:**

```bash
kubectl -n m04-storage get pvc reports-data      # Bound   m04-reports-pv   1Gi   RWO   manual
kubectl get pv m04-reports-pv                     # Bound   m04-storage/reports-data
kubectl -n m04-storage get pod reports            # Running
kubectl -n m04-storage exec reports -- cat /data/report.txt
```

**Common mistakes:**
- `kubectl edit pvc` to change class or access mode: rejected, the spec is immutable apart from the storage request.
- Removing `storageClassName` instead of setting `manual`: the default StorageClass is filled in and a new volume is provisioned instead of using `m04-reports-pv`.
- Changing the PV (forbidden by the task).

**Points:** 2% claim recreated with matching class, access mode and size · 1% bound to `m04-reports-pv` · 1% Pod Running with the claim at `/data`.

---

## Question 16 — Migrate deprecated manifests (5%)

**Approach:** `batch/v1beta1` CronJob stopped being served in v1.25 and `autoscaling/v2beta2` HPA in v1.26 (Deprecated API Migration Guide). Both successors are field-compatible, so only `apiVersion` changes.

```bash
cd ~/ckad-mocks/exam-04/q16
kubectl apply -f legacy/
# no matches for kind "CronJob" in version "batch/v1beta1" / kind "HorizontalPodAutoscaler" in version "autoscaling/v2beta2"
kubectl api-versions | grep -E '^(batch|autoscaling)/' > versions.txt
printf 'cronjob=1.25\nhpa=1.26\n' > removed.txt
mkdir -p fixed
sed 's#^apiVersion: batch/v1beta1#apiVersion: batch/v1#' legacy/cronjob.yaml > fixed/cronjob.yaml
sed 's#^apiVersion: autoscaling/v2beta2#apiVersion: autoscaling/v2#' legacy/hpa.yaml > fixed/hpa.yaml
kubectl apply -f fixed/
```

The migrated files:

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: cleanup
  namespace: m04-legacy
spec:
  schedule: "*/15 * * * *"
  concurrencyPolicy: Replace
  successfulJobsHistoryLimit: 2
  failedJobsHistoryLimit: 1
  jobTemplate:
    spec:
      backoffLimit: 2
      template:
        spec:
          restartPolicy: OnFailure
          containers:
          - name: cleanup
            image: busybox:1.36
            command: ["sh", "-c", "echo cleaning temp files; date"]
---
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: ticker
  namespace: m04-legacy
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: ticker
  minReplicas: 1
  maxReplicas: 4
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
  behavior:
    scaleDown:
      stabilizationWindowSeconds: 120
```

**Verify:**

```bash
cat ~/ckad-mocks/exam-04/q16/versions.txt        # autoscaling/v1, autoscaling/v2, batch/v1
cat ~/ckad-mocks/exam-04/q16/removed.txt         # cronjob=1.25 / hpa=1.26
kubectl -n m04-legacy get cronjob cleanup -o jsonpath='{.spec.schedule} {.spec.concurrencyPolicy} {.spec.successfulJobsHistoryLimit}{"\n"}'   # */15 * * * * Replace 2
kubectl -n m04-legacy get hpa ticker -o jsonpath='{.spec.maxReplicas} {.spec.metrics[0].resource.target.averageUtilization} {.spec.behavior.scaleDown.stabilizationWindowSeconds}{"\n"}'   # 4 70 120
```

**Common mistakes:**
- Converting the HPA to `autoscaling/v1`: it has no `metrics` list or `behavior`, so settings are lost.
- Expecting `kubectl convert` to exist: it is a separate plugin that is not installed by default.
- Answering 1.22 for the CronJob (1.22 removed the beta Ingress, CRD and RBAC APIs).

**Points:** 1% `versions.txt` · 1% `removed.txt` · 1.5% CronJob migrated and applied · 1.5% HPA migrated and applied.

---

## Question 17 — Quota blocks a scale-up (4%)

**Approach:** the ReplicaSet records `FailedCreate` events (`exceeded quota`). Usage counts every non-terminated Pod in the namespace, including the two leftover debug Pods. Free the quota by deleting them; the ReplicaSet retries on its own.

```bash
kubectl -n m04-quota scale deployment worker --replicas=4
kubectl -n m04-quota get deploy worker                       # READY 2/4
kubectl -n m04-quota get events --field-selector reason=FailedCreate -o custom-columns=MSG:.message --no-headers | tail -n 1
# Error creating: pods "worker-..." is forbidden: exceeded quota: m04-objects, requested: pods=1, used: pods=4, limited: pods=4
kubectl -n m04-quota describe resourcequota m04-objects > ~/ckad-mocks/exam-04/q17/quota.txt
kubectl -n m04-quota delete pod -l purpose=debug
kubectl -n m04-quota get deploy worker -w                    # reaches 4/4 within about a minute
```

Expected `quota.txt` (while blocked):

```text
Name:                   m04-objects
Namespace:              m04-quota
Resource                Used  Hard
--------                ----  ----
count/configmaps        1     5
count/deployments.apps  1     2
pods                    4     4
services                0     2
```

**Verify:**

```bash
grep -E '^pods' ~/ckad-mocks/exam-04/q17/quota.txt                         # pods  4  4
kubectl -n m04-quota get deploy worker                                      # READY 4/4
kubectl -n m04-quota get resourcequota m04-objects -o jsonpath='{.spec.hard}{"\n"}'   # unchanged
```

**Common mistakes:**
- Raising `pods` in the quota (forbidden by the task) or deleting Pods of `worker`.
- Waiting forever: the ReplicaSet controller retries with back-off. If nothing happens after a minute, scale to 3 and back to 4 to trigger an immediate sync.
- Looking for the error on the Deployment or its Pods; it is an event of the ReplicaSet (`kubectl describe rs -l app=worker`).

**Points:** 1.5% scaled and `quota.txt` shows the full quota · 1% only the debug Pods deleted · 1.5% 4/4 replicas with the quota unchanged.

---

## Question 18 — Two hosts, one Ingress (6%)

**Approach:** one rule per host. A backend port can be referenced by Service port `name` instead of `number`. Without `defaultBackend`, unknown hosts get the controller's own 404.

```bash
kubectl -n m04-ingress get svc                      # blog 80/TCP, wiki 8080/TCP (port name web)
kubectl -n m04-ingress create ingress sites --class=nginx \
  --rule="blog.m04.local/*=blog:80" --rule="wiki.m04.local/*=wiki:web" \
  --dry-run=client -o yaml > q18.yaml                # a non-numeric port becomes port.name
kubectl apply -f q18.yaml
```

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: sites
  namespace: m04-ingress
spec:
  ingressClassName: nginx
  rules:
  - host: blog.m04.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: blog
            port:
              number: 80
  - host: wiki.m04.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: wiki
            port:
              name: web             # Service port name, not the container port
```

**Verify:**

```bash
kubectl -n m04-ingress get ingress sites \
  -o jsonpath='{range .spec.rules[*]}{.host} {.http.paths[0].backend.service.name} {.http.paths[0].backend.service.port}{"\n"}{end}'
# blog.m04.local blog {"number":80}
# wiki.m04.local wiki {"name":"web"}
kubectl -n m04-ingress get ingress sites -o jsonpath='{.spec.defaultBackend}{"\n"}'          # empty
# with ingress-nginx reachable at $IP:
curl -s -H 'Host: blog.m04.local' "http://$IP/" | grep -m1 title                          # Welcome to nginx!
curl -s -H 'Host: wiki.m04.local' "http://$IP/"                                           # It works!
curl -s -o /dev/null -w '%{http_code}\n' -H 'Host: other.m04.local' "http://$IP/"         # 404
```

**Common mistakes:**
- One host with two paths instead of two host rules.
- `port: number: 80` for `wiki` (80 is the container port; the Service exposes 8080) or `number: web`.
- Adding a `defaultBackend` (then every unknown host reaches an application).

**Points:** 2% `blog` rule · 2% `wiki` rule referencing the port by name · 1% class `nginx` and no default backend · 1% applied in `m04-ingress`.

---

## Question 19 — Extend the API with a CRD (4%)

**Approach:** a v1 CRD needs `group`, `names`, `scope` and at least one version with `served`, `storage` and a structural `openAPIV3Schema`. Validation keywords (`required`, `minimum`, `maximum`) are enforced by the API server.

```yaml
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: featureflags.flags.m04.example.com     # must be plural + "." + group
spec:
  group: flags.m04.example.com
  scope: Namespaced
  names:
    plural: featureflags
    singular: featureflag
    kind: FeatureFlag
    shortNames:
    - ff
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
            required: ["enabled", "owner"]
            properties:
              enabled:
                type: boolean
              owner:
                type: string
              rolloutPercent:
                type: integer
                minimum: 0
                maximum: 100
---
apiVersion: flags.m04.example.com/v1
kind: FeatureFlag
metadata:
  name: dark-mode
  namespace: m04-crd
spec:
  enabled: true
  owner: team-ui
  rolloutPercent: 25
```

```bash
kubectl apply -f q19-crd.yaml          # if the CR is rejected with "no matches for kind", apply again after a second
kubectl wait --for=condition=Established crd/featureflags.flags.m04.example.com
```

**Verify:**

```bash
kubectl api-resources --api-group=flags.m04.example.com          # featureflags  ff  flags.m04.example.com/v1  true  FeatureFlag
kubectl -n m04-crd get ff                                         # dark-mode
kubectl -n m04-crd patch ff dark-mode --type=merge -p '{"spec":{"rolloutPercent":150}}'
# The FeatureFlag "dark-mode" is invalid: spec.rolloutPercent: Invalid value: 150: spec.rolloutPercent in body should be less than or equal to 100
```

**Common mistakes:**
- `apiextensions.k8s.io/v1beta1` (removed in v1.22) or a CRD name that is not `<plural>.<group>`.
- Missing `type: object` on `spec`, or `required` placed inside a property instead of next to `properties`.
- Creating the custom resource before the CRD is established (retry, or use `kubectl wait`).

**Points:** 1.5% CRD names, scope and version · 1.5% schema with required fields and the 0-100 range · 1% FeatureFlag `dark-mode` in `m04-crd`.

---

## Scoring table

| Question | Topic | Weight | Your score |
|---|---|---|---|
| 1 | kubeconfig contexts | 3% | |
| 2 | ImagePullBackOff + TCP readiness | 5% | |
| 3 | Multi-stage build, OCI archive | 5% | |
| 4 | Env-file ConfigMap, command/args | 5% | |
| 5 | Roll back to a chosen revision | 5% | |
| 6 | NetworkPolicy namespace AND Pod selector | 6% | |
| 7 | Tune an existing CronJob | 4% | |
| 8 | Helm failed release, upgrade, values | 7% | |
| 9 | Hardened Pod + TLS Secret | 6% | |
| 10 | Multi-port, NodePort, ExternalName | 7% | |
| 11 | kubectl top + log slices | 5% | |
| 12 | Adapter container | 6% | |
| 13 | ClusterRole + RoleBinding + token | 5% | |
| 14 | Kustomize overlay with two patch types | 8% | |
| 15 | Pending PVC | 4% | |
| 16 | Migrate CronJob and HPA manifests | 5% | |
| 17 | ResourceQuota blocks scale-up | 4% | |
| 18 | Host-based Ingress | 6% | |
| 19 | CRD + custom resource | 4% | |
| **Total** | | **100%** | **/100** |

66% or more is a pass. Below 66%: redo the questions you missed tomorrow without looking at the solutions.

## If you missed it, study

| Question | Study |
|---|---|
| Q3, Q7, Q12, Q15 | [01 Application Design and Build](../../01-Application-Design-and-Build/README.md) |
| Q5, Q8, Q14, Q10 (canary withdrawn by selector) | [02 Application Deployment](../../02-Application-Deployment/README.md) |
| Q2, Q11, Q16 | [03 Application Observability and Maintenance](../../03-Application-Observability-and-Maintenance/README.md) |
| Q1, Q4, Q9, Q13, Q17, Q19 | [04 Application Environment, Configuration and Security](../../04-Application-Environment-Configuration-and-Security/README.md) |
| Q6, Q10, Q18 | [05 Services and Networking](../../05-Services-and-Networking/README.md) |
| Q1 (kubeconfig), Q16 (HPA), JSONPath and custom columns | [06 Cross-Cutting Skills and Bonus Topics](../../06-Cross-Cutting-Skills-and-Bonus-Topics/README.md) |
| Exam setup, ssh-per-task workflow, aliases | [00 Exam Overview and Setup](../../00-Exam-Overview-and-Setup/README.md) |

## Coverage matrix

| Domain | Competency | Questions |
|---|---|---|
| Application Design and Build | Define, build and modify container images | Q3 |
| Application Design and Build | Choose and use the right workload resource (Deployment, DaemonSet, CronJob, etc.) | Q7 (CronJob), Q4 (Pod with `OnFailure`), Q12 (Deployment), Q16 (CronJob, HPA) |
| Application Design and Build | Understand multi-container Pod design patterns (e.g. sidecar, init and others) | Q12 (adapter), Q9 (two containers), Q11 (two-container Pod) |
| Application Design and Build | Utilize persistent and ephemeral volumes | Q15 (PV/PVC), Q9 (emptyDir, Secret volume), Q12 (shared emptyDir, ConfigMap volume) |
| Application Deployment | Use Kubernetes primitives to implement common deployment strategies (e.g. blue/green or canary) | Q10 (canary withdrawn through Service selectors), Q5 (back out a bad release) |
| Application Deployment | Understand Deployments and how to perform rolling updates | Q5, Q2 |
| Application Deployment | Use the Helm package manager to deploy existing packages | Q8 |
| Application Deployment | Kustomize | Q14 |
| Application Observability and Maintenance | Understand API deprecations | Q16 |
| Application Observability and Maintenance | Implement probes and health checks | Q2 |
| Application Observability and Maintenance | Use built-in CLI tools to monitor Kubernetes applications | Q11 (`kubectl top`), Q17 (events, `describe quota`) |
| Application Observability and Maintenance | Utilize container logs | Q11, Q4, Q12 |
| Application Observability and Maintenance | Debugging in Kubernetes | Q2, Q15, Q17 |
| Application Environment, Configuration and Security | Discover and use resources that extend Kubernetes (CRD, Operators) | Q19 |
| Application Environment, Configuration and Security | Understand authentication, authorization and admission control | Q1 (kubeconfig credentials and contexts), Q13 (RBAC), Q17 (ResourceQuota admission) |
| Application Environment, Configuration and Security | Understand requests, limits, quotas | Q17, Q14, Q12 |
| Application Environment, Configuration and Security | Define resource requirements | Q12, Q14 |
| Application Environment, Configuration and Security | Understand ConfigMaps | Q4, Q12 |
| Application Environment, Configuration and Security | Create & consume Secrets | Q9 |
| Application Environment, Configuration and Security | Understand ServiceAccounts | Q13 |
| Application Environment, Configuration and Security | Understand Application Security (SecurityContexts, Capabilities, etc.) | Q9 |
| Services and Networking | Demonstrate basic understanding of NetworkPolicies | Q6 |
| Services and Networking | Provide and troubleshoot access to applications via services | Q10, Q2 (endpoints), Q18 |
| Services and Networking | Use Ingress rules to expose applications | Q18 |
