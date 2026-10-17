# CKAD Mock Exam 03 — Solutions

Grade yourself honestly: a part scores only if its end state is exactly what the task asked for (names, namespace, files). Partial credit follows the **Points** line of each solution. Pass mark: **66%**.

## Domain weights

| Domain | Questions | Weight |
|---|---|---|
| Application Design and Build | Q2, Q5, Q10, Q15 | 20% |
| Application Deployment | Q3, Q7, Q12, Q16 | 21% |
| Application Observability and Maintenance | Q1, Q9, Q14, Q18 | 15% |
| Application Environment, Configuration and Security | Q4, Q8, Q13, Q17 | 23% |
| Services and Networking | Q6, Q11, Q19 | 21% |
| **Total** | **19 questions** | **100%** |

Conventions used below: `kubectl` is written out (in the exam use the preconfigured `k` alias). The fastest generator pattern is `kubectl ... --dry-run=client -o yaml > file.yaml`, then edit with vim and `kubectl apply -f file.yaml`. No solution needs `jq`; JSONPath and custom columns are enough.

---

## Question 1 — Liveness probe on the wrong port (3%)

**Approach:** the `Unhealthy` events say `Liveness probe failed: Get "http://<pod-ip>:8080/": ... connection refused`. nginx listens on 80, so only the liveness port is wrong. Patch it in the Deployment template (never in the Pods).

```bash
kubectl -n m03-probes get events --field-selector reason=Unhealthy > ~/ckad-mocks/exam-03/q01/unhealthy-events.txt
kubectl -n m03-probes get deploy pricing -o jsonpath='{.spec.template.spec.containers[0].livenessProbe}{"\n"}'
kubectl -n m03-probes patch deploy pricing --type=json \
  -p='[{"op":"replace","path":"/spec/template/spec/containers/0/livenessProbe/httpGet/port","value":80}]'
kubectl -n m03-probes rollout status deploy/pricing
```

`kubectl -n m03-probes edit deploy pricing` (change `port: 8080` under `livenessProbe` to `80`) is just as fast.

**Verify:**

```bash
grep -c 'Liveness probe failed' ~/ckad-mocks/exam-03/q01/unhealthy-events.txt          # 1 or more
kubectl -n m03-probes get deploy pricing -o jsonpath='{.spec.template.spec.containers[0].livenessProbe.httpGet.port} {.spec.template.spec.containers[0].readinessProbe.httpGet.port}{"\n"}'
# 80 80
kubectl -n m03-probes get pods -l app=pricing      # wait ~1 min: READY 1/1, RESTARTS 0
```

**Common mistakes:**
- Running `kubectl get events` without `-n m03-probes` (empty file from the default namespace).
- Also "fixing" the readiness probe or the delays, which the task forbids.
- Deleting the Pods: the Deployment recreates them with the same broken probe.

**Points:** 1% events file · 2% liveness port fixed, rollout complete, no new restarts.

---

## Question 2 — Node agent on every node (4%)

**Approach:** generate a Deployment, change `kind` to `DaemonSet`, delete `replicas`, `strategy` and `status`, add the Downward API env var and a toleration for the control-plane taint.

```bash
kubectl -n m03-ds create deployment node-agent --image=busybox:1.36 --dry-run=client -o yaml > q02-ds.yaml
vim q02-ds.yaml          # kind: DaemonSet, remove replicas/strategy/status, add the fields below
kubectl apply -f q02-ds.yaml
```

```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: node-agent
  namespace: m03-ds
  labels:
    app: node-agent
spec:
  selector:
    matchLabels:
      app: node-agent
  template:
    metadata:
      labels:
        app: node-agent
    spec:
      tolerations:
      - key: node-role.kubernetes.io/control-plane   # taint on kubeadm/kind control-plane nodes
        operator: Exists
        effect: NoSchedule
      containers:
      - name: agent
        image: busybox:1.36
        command: ["sh", "-c", "while true; do echo \"agent alive on $NODE_NAME\"; sleep 30; done"]
        env:
        - name: NODE_NAME
          valueFrom:
            fieldRef:
              fieldPath: spec.nodeName      # Downward API
        resources:
          requests:
            cpu: 10m
            memory: 16Mi
```

**Verify:**

```bash
kubectl get nodes --no-headers | wc -l                      # N nodes
kubectl -n m03-ds get ds node-agent                         # DESIRED = CURRENT = READY = N
kubectl -n m03-ds get pods -l app=node-agent -o wide        # one Pod per node, control-plane included
kubectl -n m03-ds logs -l app=node-agent --prefix           # agent alive on <node-name>
```

**Common mistakes:**
- No toleration: the control-plane node gets no Pod (on single-node kind/minikube the node is usually untainted, so check the YAML, not only the Pod count).
- Tolerating the old `node-role.kubernetes.io/master` taint, which current clusters no longer set.
- Leaving `replicas:` or `strategy:` in the manifest (`strategy` is not a DaemonSet field; DaemonSets use `updateStrategy`).

**Points:** 1.5% DaemonSet with correct name, labels, selector, container and command · 1% `NODE_NAME` via `fieldRef` · 0.5% requests · 1% toleration and a Pod on every node.

---

## Question 3 — Helm: values file, upgrade, rollback (6%)

**Approach:** read the key names from `helm show values`, keep the values file on every upgrade (or use `--reuse-values`), roll back to revision 1 (which creates revision 3).

```bash
cd ~/ckad-mocks/exam-03/q03
helm show values ./webapp > default-values.yaml
grep -nE '^replicaCount|^image:|^  tag:' default-values.yaml
cat > prod-values.yaml <<'EOF'
replicaCount: 2
image:
  tag: "1.27-alpine"
EOF
helm install storefront ./webapp -n m03-helm -f prod-values.yaml
helm upgrade storefront ./webapp -n m03-helm -f prod-values.yaml --set replicaCount=4
#   alternative: helm upgrade storefront ./webapp -n m03-helm --reuse-values --set replicaCount=4
helm rollback storefront 1 -n m03-helm
helm history storefront -n m03-helm > history.txt
```

The values file the task asks for:

```yaml
replicaCount: 2
image:
  tag: "1.27-alpine"
```

**Verify:**

```bash
helm list -n m03-helm                                  # storefront  REVISION 3  STATUS deployed
cat ~/ckad-mocks/exam-03/q03/history.txt               # 1 superseded Install / 2 superseded Upgrade / 3 deployed "Rollback to 1"
helm get values storefront -n m03-helm                 # image.tag 1.27-alpine, replicaCount 2
kubectl -n m03-helm get deploy storefront-webapp -o jsonpath='{.spec.replicas} {.spec.template.spec.containers[0].image}{"\n"}'
# 2 nginx:1.27-alpine
```

**Common mistakes:**
- `helm upgrade storefront ./webapp --set replicaCount=4` without `-f prod-values.yaml` or `--reuse-values`: Helm re-applies the chart defaults plus the new `--set`, so the image tag silently falls back to the chart's `appVersion`.
- Rolling back to revision 2 (the mistake) instead of 1, or expecting the rollback to reuse revision number 1 (it creates revision 3).
- Forgetting `-n m03-helm` on `history`/`rollback` (Helm looks in the current namespace and reports "release: not found").

**Points:** 1% default values file · 1.5% values file + install at revision 1 · 1.5% upgrade with 4 replicas that kept the image tag · 1% rollback to revision 1 (revision 3 deployed) · 1% history file.

---

## Question 4 — ServiceAccount: fix a 403 and add an image pull secret (7%)

**Approach:** the log line names the identity (`system:serviceaccount:m03-rbac:default`). Bind the existing Role to the existing SA, attach the pull secret to the SA **before** switching the Deployment (pull secrets are injected only when a Pod is created), then switch the Deployment's ServiceAccount.

```bash
kubectl -n m03-rbac logs deploy/inventory-sync --tail=2
# 10:01:10 HTTP 403 forbidden: User \"system:serviceaccount:m03-rbac:default\"
kubectl -n m03-rbac describe role configmap-reader
kubectl -n m03-rbac create rolebinding inventory-configmap-reader \
  --role=configmap-reader --serviceaccount=m03-rbac:inventory
kubectl -n m03-rbac create secret docker-registry regcred \
  --docker-server=registry.m03.example:5000 --docker-username=robot \
  --docker-password='Rob0t-Pass' --docker-email=robot@m03.example
kubectl -n m03-rbac patch serviceaccount inventory -p '{"imagePullSecrets":[{"name":"regcred"}]}'
kubectl -n m03-rbac set serviceaccount deployment inventory-sync inventory
kubectl -n m03-rbac rollout status deploy/inventory-sync
```

Declarative equivalents of the two new objects:

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: inventory-configmap-reader
  namespace: m03-rbac
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: configmap-reader
subjects:
- kind: ServiceAccount
  name: inventory
  namespace: m03-rbac
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: inventory
  namespace: m03-rbac
imagePullSecrets:
- name: regcred
```

**Verify:**

```bash
kubectl auth can-i list configmaps -n m03-rbac --as=system:serviceaccount:m03-rbac:inventory   # yes
kubectl -n m03-rbac logs deploy/inventory-sync --tail=1                                        # ... HTTP 200
kubectl -n m03-rbac get pods -l app=inventory-sync \
  -o custom-columns=POD:.metadata.name,SA:.spec.serviceAccountName,PULL:.spec.imagePullSecrets[*].name
# inventory-sync-...   inventory   regcred
kubectl -n m03-rbac get deploy inventory-sync -o jsonpath='{.spec.template.spec.imagePullSecrets}{"\n"}'   # empty
```

**Common mistakes:**
- `--serviceaccount=inventory` without the `namespace:` prefix (kubectl rejects it), or `--clusterrole=configmap-reader` (there is no such ClusterRole).
- Attaching the secret to the SA after the new Pod already started: that Pod has no `imagePullSecrets`. Fix with `kubectl -n m03-rbac rollout restart deploy/inventory-sync`.
- Trying to change `serviceAccountName` on a running Pod (immutable): change the Deployment template.
- Creating the Secret with `kubectl create secret generic` (wrong type; it must be `kubernetes.io/dockerconfigjson`).

**Points:** 2% RoleBinding · 1% `regcred` of type `kubernetes.io/dockerconfigjson` with the given data · 1% secret attached to SA `inventory` · 2% Deployment runs as `inventory` and logs `HTTP 200` · 1% new Pod carries `regcred` while the Deployment template does not.

---

## Question 5 — Native sidecar log forwarder with a RAM-backed volume (6%)

**Approach:** a native sidecar is an entry under `initContainers` with `restartPolicy: Always`; it starts before the app containers and keeps running. `medium: Memory` makes the `emptyDir` a tmpfs; `sizeLimit` caps it (memory-backed volumes also count against the container memory limits).

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: payments
  namespace: m03-sidecar
spec:
  volumes:
  - name: app-logs
    emptyDir:
      medium: Memory          # tmpfs
      sizeLimit: 32Mi
  initContainers:
  - name: log-forwarder
    image: busybox:1.36
    restartPolicy: Always     # native sidecar (GA since v1.33)
    command: ["tail", "-F", "/var/log/app/payments.log"]
    volumeMounts:
    - name: app-logs
      mountPath: /var/log/app
      readOnly: true
  containers:
  - name: app
    image: busybox:1.36
    command: ["sh", "-c", "i=0; while true; do i=$((i+1)); echo \"$(date +%T) payment $i processed\" >> /var/log/app/payments.log; sleep 2; done"]
    volumeMounts:
    - name: app-logs
      mountPath: /var/log/app
```

```bash
kubectl apply -f q05-payments.yaml
kubectl explain pod.spec.initContainers.restartPolicy      # confirms the field if you forget it
```

**Verify:**

```bash
kubectl -n m03-sidecar get pod payments                     # READY 2/2   STATUS Running
kubectl -n m03-sidecar get pod payments -o jsonpath='{.spec.initContainers[0].name} {.spec.initContainers[0].restartPolicy} {.spec.volumes[0].emptyDir}{"\n"}'
# log-forwarder Always {"medium":"Memory","sizeLimit":"32Mi"}
kubectl -n m03-sidecar logs payments -c log-forwarder --tail=3   # 10:12:01 payment 42 processed ...
kubectl -n m03-sidecar exec payments -c app -- df -h /var/log/app   # Filesystem: tmpfs
```

**Common mistakes:**
- Putting the forwarder under `containers` (a classic sidecar: no start-order guarantee) or setting `restartPolicy: Always` at Pod level (that is the Pod default and does not create a sidecar).
- `medium: memory` (the value is case-sensitive: `Memory`) or `sizeLimit: 32m` (32 milli-bytes).
- Forgetting `readOnly: true` on the forwarder's mount.

**Points:** 1.5% memory-backed `emptyDir` with `sizeLimit: 32Mi` · 1% `app` container · 2% `log-forwarder` as native sidecar · 0.5% read-only mount · 1% Pod 2/2 Running and forwarder logs show payments.

---

## Question 6 — Make existing NetworkPolicies work by labelling Pods (6%)

**Approach:** read every policy's `podSelector` (who is protected) and `from` selectors (who may connect). Two labels inside one `podSelector` are ANDed, so `frontend` needs **both** `tier=web` and `env=prod`.

```bash
kubectl -n m03-netpol get netpol
kubectl -n m03-netpol describe netpol api-allow-web db-allow-api
kubectl -n m03-netpol get pods --show-labels
kubectl -n m03-netpol label pod frontend tier=web env=prod
kubectl -n m03-netpol label pod api tier=api
kubectl -n m03-netpol label pod db tier=db
```

| Policy | Protects | Allows from | Port |
|---|---|---|---|
| `default-deny-ingress` | all Pods | nobody | none |
| `api-allow-web` | `tier=api` | `tier=web` AND `env=prod` | TCP 80 |
| `db-allow-api` | `tier=db` | `tier=api` | TCP 6379 |

**Verify** (needs a CNI that enforces NetworkPolicy):

```bash
kubectl -n m03-netpol exec frontend -- wget -qO- -T 2 http://api | head -n 4     # nginx welcome page
kubectl -n m03-netpol exec frontend -- nc -zv -w 2 db 6379                         # times out (blocked)
kubectl -n m03-netpol exec api -- timeout 2 bash -c 'echo > /dev/tcp/db/6379' && echo "api to db: open"
kubectl -n m03-netpol get pods --show-labels                                       # old app=... labels still present
```

**Common mistakes:**
- Labelling `frontend` with `tier=api`: it would then also be allowed to reach `db`.
- Adding only `tier=web` to `frontend` (the `env=prod` half of the AND is missing).
- Editing a policy or overwriting the existing `app=` labels (the Services select on them).

**Points:** 2% `frontend` labels · 1.5% `api` label · 1.5% `db` label · 1% no policy, Service or existing label changed and `frontend` to `db` still blocked.

---

## Question 7 — Batch several changes into one rollout (5%)

**Approach:** while a Deployment is paused, template changes are recorded but no new ReplicaSet is created. Resume once and all changes roll out as one revision. Annotate the change-cause before resuming.

```bash
kubectl -n m03-rollout rollout pause deployment/api-gateway
kubectl -n m03-rollout set image deployment/api-gateway gateway=nginx:1.27-alpine
kubectl -n m03-rollout set env deployment/api-gateway -c gateway GATEWAY_MODE=strict
kubectl -n m03-rollout set resources deployment/api-gateway -c gateway \
  --requests=cpu=50m,memory=64Mi --limits=cpu=200m,memory=128Mi
kubectl -n m03-rollout annotate deployment/api-gateway \
  kubernetes.io/change-cause="alpine image, strict mode, resources" --overwrite
kubectl -n m03-rollout rollout resume deployment/api-gateway
kubectl -n m03-rollout rollout status deployment/api-gateway
kubectl -n m03-rollout rollout history deployment/api-gateway > ~/ckad-mocks/exam-03/q07/history.txt
```

Expected history file:

```text
deployment.apps/api-gateway
REVISION  CHANGE-CAUSE
1         initial release
2         alpine image, strict mode, resources
```

**Verify:**

```bash
kubectl -n m03-rollout get rs -l app=api-gateway                       # exactly 2 ReplicaSets
kubectl -n m03-rollout get deploy api-gateway -o jsonpath='{.spec.paused}{"\n"}'   # empty = not paused
kubectl -n m03-rollout get deploy api-gateway \
  -o jsonpath='{.spec.template.spec.containers[0].image} {.spec.template.spec.containers[0].env} {.spec.template.spec.containers[0].resources}{"\n"}'
```

**Common mistakes:**
- Not pausing first: every `kubectl set` creates its own revision (4 revisions instead of 2).
- Leaving the Deployment paused (nothing rolls out and `rollout status` keeps waiting).
- Using the deprecated `--record` flag instead of the `kubernetes.io/change-cause` annotation.

**Points:** 2% exactly one new revision · 2% image, env and resources all in the new template · 1% change-cause and history file.

---

## Question 8 — Downward API and a Guaranteed Pod (5%)

**Approach:** env vars use `fieldRef` (Pod fields) and `resourceFieldRef` (container resources, scaled by `divisor`). Whole label or annotation sets are only available as Downward API **volume** files. Guaranteed means requests equal limits for CPU and memory in every container.

```bash
kubectl -n m03-downward run meta-probe --image=busybox:1.36 \
  --labels=app=meta-probe,tier=diagnostics --annotations=owner=team-sre \
  --dry-run=client -o yaml --command -- sh -c 'while true; do sleep 3600; done' > q08.yaml
vim q08.yaml        # rename the container to probe, add env, resources and the volume (below)
kubectl apply -f q08.yaml
kubectl -n m03-downward get pod meta-probe -o jsonpath='{.status.qosClass}' > ~/ckad-mocks/exam-03/q08/qos.txt
kubectl -n m03-downward exec meta-probe -- cat /etc/podinfo/labels > ~/ckad-mocks/exam-03/q08/labels.txt
```

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: meta-probe
  namespace: m03-downward
  labels:
    app: meta-probe
    tier: diagnostics
  annotations:
    owner: team-sre
spec:
  containers:
  - name: probe
    image: busybox:1.36
    command: ["sh", "-c", "while true; do sleep 3600; done"]
    env:
    - name: POD_IP
      valueFrom:
        fieldRef:
          fieldPath: status.podIP
    - name: MEM_LIMIT_MI
      valueFrom:
        resourceFieldRef:
          containerName: probe
          resource: limits.memory
          divisor: 1Mi            # 64Mi / 1Mi = 64
    resources:
      requests:
        cpu: 100m
        memory: 64Mi
      limits:
        cpu: 100m
        memory: 64Mi
    volumeMounts:
    - name: podinfo
      mountPath: /etc/podinfo
  volumes:
  - name: podinfo
    downwardAPI:
      items:
      - path: labels
        fieldRef:
          fieldPath: metadata.labels
      - path: annotations
        fieldRef:
          fieldPath: metadata.annotations
```

**Verify:**

```bash
cat ~/ckad-mocks/exam-03/q08/qos.txt                       # Guaranteed
cat ~/ckad-mocks/exam-03/q08/labels.txt                    # app="meta-probe"  tier="diagnostics"
kubectl -n m03-downward exec meta-probe -- sh -c 'echo $POD_IP $MEM_LIMIT_MI'   # 10.244.x.y 64
kubectl -n m03-downward exec meta-probe -- cat /etc/podinfo/annotations         # includes owner="team-sre"
```

**Common mistakes:**
- `divisor: 1M` gives `68` (decimal megabytes, rounded up), not `64`.
- Setting only requests, or only CPU limits: the Pod becomes Burstable.
- Trying to put all labels into one env var (`fieldRef` in env supports single keys such as `metadata.labels['app']`, not the whole map).

**Points:** 1% metadata and container · 1.5% `POD_IP` and `MEM_LIMIT_MI` · 1% Downward API volume · 1% Guaranteed and `qos.txt` · 0.5% `labels.txt`.

---

## Question 9 — Debug a shell-less container (4%)

**Approach:** `kubectl debug` adds an ephemeral container to the running Pod; `--target=api` puts it into the process namespace of container `api`, so `ps` shows that container's processes (PID 1 there is the app).

```bash
kubectl -n m03-debug exec distroless-api -- sh          # fails: executable file not found
kubectl -n m03-debug debug -it distroless-api --image=busybox:1.36 --target=api -c debugger -- sh
# inside the debug container:
ps -o pid,user,args
#   PID  USER     COMMAND
#     1  10001    /pause --config=/etc/api/config.yaml --port=8443
#     7  root     sh
grep '^Uid' /proc/1/status          # Uid: 10001 10001 10001 10001
exit
printf 'cmd=%s\nuid=%s\n' '/pause --config=/etc/api/config.yaml --port=8443' 10001 > ~/ckad-mocks/exam-03/q09/findings.txt
```

Non-interactive variant: `kubectl -n m03-debug debug distroless-api --image=busybox:1.36 --target=api -c debugger -- sleep 3600`, then `kubectl -n m03-debug exec distroless-api -c debugger -- ps -o pid,user,args`.

**Verify:**

```bash
kubectl -n m03-debug get pod distroless-api \
  -o jsonpath='{.spec.ephemeralContainers[*].name} {.spec.ephemeralContainers[*].targetContainerName} {.status.containerStatuses[0].restartCount}{"\n"}'
# debugger api 0
cat ~/ckad-mocks/exam-03/q09/findings.txt
```

**Common mistakes:**
- Using `--copy-to=<new-pod>`: that creates a different Pod, which the task forbids.
- Omitting `--target=api`: the debug container then only sees its own processes.
- Writing only `/pause`: the arguments are part of the command line (they come from the Pod spec, the binary from the image).

**Points:** 2% ephemeral container `debugger` targeting `api`, Pod not restarted · 1% command line · 1% UID.

---

## Question 10 — Fix and harden a container image (4%)

**Approach:** the build fails because `.dockerignore` excludes `*.html`, so `index.html` is not part of the build context. Remove that pattern, then fix the Dockerfile.

```bash
cd ~/ckad-mocks/exam-03/q10
podman build -t m03-motd:1.1 .        # COPY index.html fails: no such file or directory / not found
cat .dockerignore                     # the *.html rule excludes index.html from the context
sed -i '/^\*\.html$/d' .dockerignore  # keep the *.md rule
vim Dockerfile
podman build -t m03-motd:1.1 .
podman image inspect m03-motd:1.1 --format '{{.Config.User}} {{.Config.ExposedPorts}} {{.Config.Cmd}}' > image-config.txt
```

Fixed `Dockerfile`:

```dockerfile
FROM busybox:1.36
ENV APP_MODE=prod
COPY index.html /www/index.html
USER 1001
EXPOSE 8080
CMD ["httpd", "-f", "-p", "8080", "-h", "/www"]
```

Docker users: `docker build -t m03-motd:1.1 .` and `docker image inspect m03-motd:1.1 --format '...'` with the same template.

**Verify:**

```bash
cat ~/ckad-mocks/exam-03/q10/image-config.txt        # 1001 map[8080/tcp:{}] [httpd -f -p 8080 -h /www]
podman run -d --rm --name motd-test -p 8088:8080 m03-motd:1.1 && sleep 1 && curl -s localhost:8088 && podman stop motd-test
```

**Common mistakes:**
- Deleting the whole `.dockerignore` or the `COPY` line, or moving `index.html` (forbidden).
- Exec form with single quotes (`CMD ['httpd', ...]`) is not valid JSON and silently falls back to shell form.
- Forgetting `-f`: busybox `httpd` daemonizes and the container exits immediately.
- `EXPOSE 8080` alone is documentation; the server must also listen on 8080 (`-p 8080`).

**Points:** 1% build fixed via `.dockerignore` · 2% `APP_MODE=prod`, `USER 1001`, port 8080 plus `EXPOSE`, exec-form `CMD` · 1% image `m03-motd:1.1` built and `image-config.txt` correct.

---

## Question 11 — Migrate a legacy Ingress (6%)

**Approach:** `networking.k8s.io/v1beta1` Ingress was removed in v1.22. In `networking.k8s.io/v1` every path needs `pathType`, the backend becomes `service.name` + `service.port.number|name`, and the class annotation is replaced by `spec.ingressClassName`.

```bash
cd ~/ckad-mocks/exam-03/q11
kubectl apply -f legacy-ingress.yaml
# error: resource mapping not found ... no matches for kind "Ingress" in version "networking.k8s.io/v1beta1"
kubectl api-versions | grep networking.k8s.io > api-versions.txt
kubectl explain ingress.spec.rules.http.paths.backend.service --api-version=networking.k8s.io/v1
kubectl create ingress legacy-shop -n m03-legacy --class=nginx \
  --rule="shop.m03.local/api*=shop-api:8080" --rule="shop.m03.local/*=shop-frontend:80" \
  --dry-run=client -o yaml > ingress-v1.yaml      # "*" at the end of a path means pathType Prefix
kubectl apply -f ingress-v1.yaml
```

`ingress-v1.yaml` (hand-written equivalent):

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: legacy-shop
  namespace: m03-legacy
spec:
  ingressClassName: nginx            # replaces the kubernetes.io/ingress.class annotation
  rules:
  - host: shop.m03.local
    http:
      paths:
      - path: /api
        pathType: Prefix
        backend:
          service:
            name: shop-api
            port:
              number: 8080
      - path: /
        pathType: Prefix
        backend:
          service:
            name: shop-frontend
            port:
              number: 80
```

**Verify:**

```bash
cat ~/ckad-mocks/exam-03/q11/api-versions.txt      # networking.k8s.io/v1 (plus gateway.networking.k8s.io/... if Gateway API CRDs exist)
kubectl -n m03-legacy get ingress legacy-shop \
  -o jsonpath='{.spec.ingressClassName} {range .spec.rules[0].http.paths[*]}{.path}:{.pathType}:{.backend.service.name}:{.backend.service.port.number} {end}{"\n"}'
# nginx /api:Prefix:shop-api:8080 /:Prefix:shop-frontend:80
grep -c 'serviceName' ~/ckad-mocks/exam-03/q11/legacy-ingress.yaml   # 2 (legacy file untouched)
# with ingress-nginx reachable at $IP (node IP, minikube ip, or 127.0.0.1 with kind port mappings):
curl -s -H 'Host: shop.m03.local' "http://$IP/api/"      # shop-api OK
curl -s -H 'Host: shop.m03.local' "http://$IP/" | grep -m1 title   # Welcome to nginx!
```

**Common mistakes:**
- Changing only `apiVersion` and keeping `serviceName`/`servicePort` (rejected as unknown fields).
- Forgetting `pathType` (required in v1), or writing `path: /api*` in YAML (the trailing `*` is only `kubectl create ingress` syntax for Prefix).
- Keeping the deprecated annotation instead of `spec.ingressClassName`, or editing the legacy file.

**Points:** 1% `api-versions.txt` · 4% correct v1 conversion (apiVersion, `ingressClassName`, `pathType` on both paths, new backend format) · 1% applied in `m03-legacy`.

---

## Question 12 — Kustomize generators (5%)

**Approach:** generators create the ConfigMap/Secret with a content hash suffix and Kustomize rewrites every reference in the Deployment (envFrom, secretKeyRef, volumes) to the hashed name, so `deployment.yaml` stays untouched. `kubectl kustomize` renders, `kubectl apply -k` applies.

```bash
cd ~/ckad-mocks/exam-03/q12
vim kustomization.yaml          # content below
kubectl kustomize . > rendered.yaml
grep -nE 'name: report-(config|secret)' rendered.yaml   # hashed names, also inside the Deployment
kubectl apply -k .
kubectl -n m03-kust rollout status deploy/report-api
```

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: m03-kust
resources:
- deployment.yaml
configMapGenerator:
- name: report-config
  literals:
  - LOG_LEVEL=debug
  files:
  - app.properties
secretGenerator:
- name: report-secret
  literals:
  - API_TOKEN=m03-t0ken
```

**Verify:**

```bash
kubectl -n m03-kust get configmap,secret | grep report-          # report-config-<hash>, report-secret-<hash>
kubectl -n m03-kust get deploy report-api -o jsonpath='{.spec.template.spec.volumes[0].configMap.name}{"\n"}'   # report-config-<hash>
kubectl -n m03-kust logs deploy/report-api | head -n 4
# LOG_LEVEL=debug
# token-length=9
# report.format=pdf
# report.retention.days=14
```

**Common mistakes:**
- `kubectl apply -f kustomization.yaml` (that tries to create a "Kustomization" object); use `apply -k <dir>`.
- Forgetting `namespace: m03-kust`: everything lands in `default`.
- Hand-editing `deployment.yaml` to the hashed names (forbidden and unnecessary).
- Using `envs:` (env-file syntax) for `app.properties`: the task wants the file itself as a key.

**Points:** 3% kustomization (namespace, resource, ConfigMap generator with literal and file, Secret generator) · 1% `rendered.yaml` · 1% applied, Pod Running and logs `LOG_LEVEL=debug`.

---

## Question 13 — Pod Security Admission: fix a rejected Pod (6%)

**Approach:** the rejection lists every violation of the `restricted` profile. Remove `privileged` and the added capability, drop `ALL`, forbid privilege escalation, run as non-root UID 1000 with the `RuntimeDefault` seccomp profile, and swap `hostPath` for `emptyDir`.

```bash
cd ~/ckad-mocks/exam-03/q13
kubectl apply -f secure-web.yaml 2> rejection.txt; cat rejection.txt
# Error from server (Forbidden): error when creating "secure-web.yaml": pods "secure-web" is forbidden:
# violates PodSecurity "restricted:latest": privileged (container "web" must not set securityContext.privileged=true),
# allowPrivilegeEscalation != false (...), unrestricted capabilities (...), restricted volume types (volume "www" uses
# restricted volume type "hostPath"), runAsNonRoot != true (...), runAsUser=0 (...), seccompProfile (...)
vim secure-web.yaml
kubectl apply -f secure-web.yaml
```

Fixed `secure-web.yaml`:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: secure-web
  namespace: m03-psa
  labels:
    app: secure-web
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
    seccompProfile:
      type: RuntimeDefault
  containers:
  - name: web
    image: busybox:1.36
    command: ["sh", "-c", "echo secure > /www/index.html && exec httpd -f -p 8080 -h /www"]
    ports:
    - containerPort: 8080
    securityContext:
      allowPrivilegeEscalation: false
      capabilities:
        drop: ["ALL"]
    volumeMounts:
    - name: www
      mountPath: /www
  volumes:
  - name: www
    emptyDir: {}
```

**Verify:**

```bash
grep -c 'violates PodSecurity' ~/ckad-mocks/exam-03/q13/rejection.txt     # 1
kubectl -n m03-psa get pod secure-web                                      # Running
kubectl -n m03-psa exec secure-web -- wget -qO- http://localhost:8080      # secure
kubectl -n m03-psa exec secure-web -- id                                   # uid=1000 ...
kubectl get ns m03-psa --show-labels                                       # labels unchanged (enforce=restricted)
```

**Common mistakes:**
- Relabelling the namespace to `baseline` or `privileged` (forbidden by the task).
- `drop: ["all"]` in lower case: the restricted check expects `ALL`.
- Putting `allowPrivilegeEscalation` or `capabilities` in the Pod-level `securityContext` (they exist only at container level) or leaving `runAsUser: 0` at container level, which overrides the Pod-level 1000.
- Forgetting the seccomp profile (Pod or container level both satisfy the check).

**Points:** 1% `rejection.txt` · 2% privileged, added capability and privilege escalation removed, `drop: ["ALL"]` · 2% `runAsNonRoot`, UID 1000, `RuntimeDefault` seccomp · 1% `emptyDir`, Pod Running and `wget` prints `secure`.

---

## Question 14 — Pending Pod (5%)

**Approach:** the scheduler's `FailedScheduling` event explains the first failing filter. Here two things are wrong: the node selector value (`linx`) and an impossible memory request (`200Gi`). The second problem shows up in a new event once the first is fixed.

```bash
kubectl -n m03-sched get pods -l app=reporter                       # Pending
kubectl -n m03-sched get events --field-selector reason=FailedScheduling \
  -o custom-columns=MSG:.message --no-headers | tail -n 1 > ~/ckad-mocks/exam-03/q14/reason.txt
cat ~/ckad-mocks/exam-03/q14/reason.txt
# 0/1 nodes are available: 1 node(s) didn't match Pod's node affinity/selector. preemption: ...
kubectl -n m03-sched get deploy reporter \
  -o jsonpath='{.spec.template.spec.nodeSelector} {.spec.template.spec.containers[0].resources}{"\n"}'
# {"kubernetes.io/os":"linx"} {"requests":{"cpu":"100m","memory":"200Gi"}}
kubectl -n m03-sched patch deploy reporter --type=json -p='[
  {"op":"replace","path":"/spec/template/spec/nodeSelector/kubernetes.io~1os","value":"linux"},
  {"op":"replace","path":"/spec/template/spec/containers/0/resources/requests/memory","value":"128Mi"}]'
kubectl -n m03-sched rollout status deploy/reporter
```

(`~1` is the JSON-pointer escape for `/` in the label key. `kubectl edit` works just as well.)

**Verify:**

```bash
kubectl -n m03-sched get pods -l app=reporter -o wide          # Running on a node
kubectl -n m03-sched get deploy reporter \
  -o jsonpath='{.spec.template.spec.nodeSelector} {.spec.template.spec.containers[0].resources.requests}{"\n"}'
# {"kubernetes.io/os":"linux"} {"cpu":"100m","memory":"128Mi"}
```

**Common mistakes:**
- Removing the `nodeSelector` completely (violates the constraint).
- Fixing only the selector and not noticing the follow-up event `Insufficient memory`.
- Deleting the Pod repeatedly: the ReplicaSet recreates it from the same broken template.

**Points:** 1% `reason.txt` · 2% node selector `kubernetes.io/os: linux` · 2% memory request `128Mi`, CPU unchanged, Pod Running.

---

## Question 15 — StatefulSet with stable network identity and storage (6%)

**Approach:** the governing Service must be headless (`clusterIP: None`) for per-Pod DNS records (`<pod>.<svc>.<ns>.svc.cluster.local`). `volumeClaimTemplates` create one PVC per replica (`data-kv-0`, `data-kv-1`) from the default StorageClass.

```bash
kubectl -n m03-sts create service clusterip kv-hl --clusterip=None --tcp=6379:6379 \
  --dry-run=client -o yaml > q15.yaml     # then fix the port name (redis) and the selector (app=kv)
vim q15.yaml                              # add the StatefulSet below, separated by ---
kubectl apply -f q15.yaml
kubectl -n m03-sts rollout status statefulset/kv
kubectl -n m03-sts run dnstest --rm -i --restart=Never --image=busybox:1.36 -- \
  nslookup kv-0.kv-hl.m03-sts.svc.cluster.local > ~/ckad-mocks/exam-03/q15/dns.txt
```

```yaml
apiVersion: v1
kind: Service
metadata:
  name: kv-hl
  namespace: m03-sts
spec:
  clusterIP: None                 # headless
  selector:
    app: kv
  ports:
  - name: redis
    port: 6379
    targetPort: 6379
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: kv
  namespace: m03-sts
spec:
  serviceName: kv-hl              # governing headless Service
  replicas: 2
  selector:
    matchLabels:
      app: kv
  template:
    metadata:
      labels:
        app: kv
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

**Verify:**

```bash
kubectl -n m03-sts get pods -l app=kv -o wide       # kv-0 and kv-1 Running
kubectl -n m03-sts get pvc                           # data-kv-0, data-kv-1 Bound
kubectl -n m03-sts get svc kv-hl -o jsonpath='{.spec.clusterIP}{"\n"}'     # None
kubectl -n m03-sts get pod kv-0 -o jsonpath='{.status.podIP}{"\n"}'        # same IP as in dns.txt
grep -A1 'Name:' ~/ckad-mocks/exam-03/q15/dns.txt
kubectl -n m03-sts get pod dnstest                   # NotFound (the temporary Pod was removed)
```

**Common mistakes:**
- A normal ClusterIP Service: no per-Pod DNS records are created.
- `serviceName` that does not match the Service name, or setting `storageClassName: ""` (disables dynamic provisioning, PVCs stay Pending).
- Running `nslookup` before `kv-0` is Ready (not-ready Pods are not published by default) or forgetting `--rm`.

**Points:** 1% headless Service · 2% StatefulSet (serviceName, labels, image, port) · 2% volume claim template, mount and Bound PVCs · 1% `dns.txt` resolves `kv-0` and no temporary Pod left.

---

## Question 16 — Canary with a fixed Pod budget (5%)

**Approach:** a Service balances across all ready endpoints, so the traffic share follows the Pod count: 4 stable + 1 canary = 20% canary. The canary Pods must carry every label of the Service selector (`app=checkout`, `tier=frontend`), while each Deployment's own selector includes `track` so the two never overlap.

```bash
kubectl -n m03-canary get svc checkout -o jsonpath='{.spec.selector}{"\n"}'                     # {"app":"checkout","tier":"frontend"}
kubectl -n m03-canary get deploy checkout-v1 -o jsonpath='{.spec.selector.matchLabels}{"\n"}'   # {"app":"checkout","track":"stable"}
kubectl -n m03-canary create deployment checkout-v2 --image=nginx:1.27-alpine --replicas=1 \
  --dry-run=client -o yaml > q16.yaml
vim q16.yaml          # labels, selector and container name as below
kubectl apply -f q16.yaml
kubectl -n m03-canary scale deployment checkout-v1 --replicas=4
```

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: checkout-v2
  namespace: m03-canary
  labels:
    app: checkout
    track: canary
spec:
  replicas: 1
  selector:
    matchLabels:
      app: checkout
      track: canary            # disjoint from checkout-v1 (track=stable)
  template:
    metadata:
      labels:
        app: checkout
        tier: frontend         # needed by the Service selector
        track: canary
    spec:
      containers:
      - name: checkout
        image: nginx:1.27-alpine
        ports:
        - containerPort: 80
```

**Verify:**

```bash
kubectl -n m03-canary get pods -l app=checkout -L track          # 4 x stable, 1 x canary, all Running
kubectl -n m03-canary get endpointslices -l kubernetes.io/service-name=checkout \
  -o jsonpath='{range .items[*].endpoints[*]}{.targetRef.name}{"\n"}{end}'
# 5 lines, exactly one checkout-v2-...
```

**Common mistakes:**
- Forgetting `tier=frontend` on the canary template: the canary runs but receives no traffic.
- Keeping `checkout-v1` at 5 replicas (6 Pods, about 17% canary) or scaling the canary to 2.
- Selecting the canary with `app=checkout,tier=frontend` only: that selector overlaps with the stable Pods.

**Points:** 2% `checkout-v2` correct and in the Service endpoints · 1.5% `checkout-v1` at 4 replicas (total 5) · 1% non-overlapping selectors · 0.5% Service unchanged.

---

## Question 17 — Explore an operator's CRD (5%)

**Approach:** `kubectl api-resources --api-group=...` discovers the kind and its short name; `kubectl explain` reads the CRD's OpenAPI schema (descriptions, types, required fields, enums).

```bash
kubectl api-resources --api-group=ops.m03.example.com > ~/ckad-mocks/exam-03/q17/resources.txt
cat ~/ckad-mocks/exam-03/q17/resources.txt
# NAME              SHORTNAMES   APIVERSION                 NAMESPACED   KIND
# databasebackups   dbb          ops.m03.example.com/v1     true         DatabaseBackup
kubectl explain databasebackups.spec.retention.keepLast > ~/ckad-mocks/exam-03/q17/keeplast.txt
kubectl explain databasebackups.spec --recursive        # schedule, target.database, retention.keepLast, storageTier
kubectl apply -f q17-cr.yaml
```

```yaml
apiVersion: ops.m03.example.com/v1
kind: DatabaseBackup
metadata:
  name: orders-nightly
  namespace: m03-crd
spec:
  schedule: "0 2 * * *"
  target:
    database: orders
  retention:
    keepLast: 7
  storageTier: archive
```

**Verify:**

```bash
kubectl -n m03-crd get dbb                                   # orders-nightly  0 2 * * *  orders  archive
kubectl -n m03-crd get dbb orders-nightly -o jsonpath='{.spec}{"\n"}'
grep -i 'keepLast' ~/ckad-mocks/exam-03/q17/keeplast.txt     # FIELD: keepLast <integer> + description
```

**Common mistakes:**
- Putting `database` directly under `spec`: with kubectl's default strict field validation the API server rejects the unknown field (with `--validate=false` it would be silently pruned).
- `storageTier: Archive` (the enum is case-sensitive) or `keepLast: "7"` (string instead of integer).
- Creating the object in `default` instead of `m03-crd`.

**Points:** 1% `resources.txt` · 1% `keeplast.txt` · 3% custom resource with all four settings in the right fields.

---

## Question 18 — Collect logs from every container by label (3%)

**Approach:** with a label selector `kubectl logs` shows only the **last 10 lines per container** unless you pass `--tail=-1`. `--all-containers` covers both containers, `--prefix` adds `[pod/<name>/<container>]`.

```bash
kubectl -n m03-logs logs -l app=orders --all-containers --prefix --tail=-1 > ~/ckad-mocks/exam-03/q18/orders.log
```

**Verify:**

```bash
grep -c 'started' ~/ckad-mocks/exam-03/q18/orders.log                 # 4 (2 Pods x 2 containers)
cut -d' ' -f1 ~/ckad-mocks/exam-03/q18/orders.log | sort | uniq -c    # 4 distinct [pod/orders-.../app|audit] prefixes
```

**Common mistakes:**
- No `--tail=-1`: the startup lines (`orders-app started`, `audit-trail started`) are missing.
- No `--all-containers`: only the default container (`app`) is shown.
- Looping over Pods with several commands (the task asks for a single command).

**Points:** 1% all containers · 1% prefixes · 1% complete history.

---

## Question 19 — Expose an application over HTTPS (9%)

**Approach:** Service first (Ingress backends reference **Service** ports), then the certificate, the TLS Secret in the Ingress's own namespace, and finally the Ingress with a `tls` block whose host matches the rule host.

```bash
cd ~/ckad-mocks/exam-03/q19
kubectl -n m03-tls create service clusterip portal --tcp=8080:80 --dry-run=client -o yaml > svc.yaml
vim svc.yaml          # rename the port "8080-80" to http (the generated selector app=portal is correct)
kubectl apply -f svc.yaml
openssl req -x509 -nodes -newkey rsa:2048 -days 365 \
  -keyout portal.key -out portal.crt -subj "/CN=portal.m03.local"
kubectl -n m03-tls create secret tls portal-tls --cert=portal.crt --key=portal.key
kubectl -n m03-tls create ingress portal --class=nginx \
  --rule="portal.m03.local/*=portal:8080,tls=portal-tls"
```

Equivalent manifests:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: portal
  namespace: m03-tls
spec:
  type: ClusterIP
  selector:
    app: portal
  ports:
  - name: http
    port: 8080
    targetPort: 80
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: portal
  namespace: m03-tls
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - portal.m03.local
    secretName: portal-tls
  rules:
  - host: portal.m03.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: portal
            port:
              number: 8080
```

**Verify:**

```bash
kubectl -n m03-tls get endpointslices -l kubernetes.io/service-name=portal     # 2 endpoints, port 80
openssl x509 -in ~/ckad-mocks/exam-03/q19/portal.crt -noout -subject -dates    # subject=CN = portal.m03.local, 365 days
kubectl -n m03-tls get secret portal-tls -o jsonpath='{.type}{"\n"}'           # kubernetes.io/tls
kubectl -n m03-tls get ingress portal -o jsonpath='{.spec.tls[0].secretName} {.spec.tls[0].hosts[0]} {.spec.rules[0].http.paths[0].backend.service.port.number}{"\n"}'
# portal-tls portal.m03.local 8080
# with ingress-nginx reachable at $IP on port 443:
curl -sk --resolve "portal.m03.local:443:$IP" https://portal.m03.local/ | grep -m1 title
curl -skv --resolve "portal.m03.local:443:$IP" https://portal.m03.local/ 2>&1 | grep -i 'subject:'   # CN=portal.m03.local
```

**Common mistakes:**
- Referencing the Secret from `m03-certs`: an Ingress can only use TLS Secrets from its own namespace.
- `kubectl create secret generic` (type `Opaque`) instead of `secret tls` (type `kubernetes.io/tls`).
- Backend port `80` in the Ingress: it must be the **Service** port (`8080` or the name `http`).
- Omitting `-nodes`: the key is encrypted and `kubectl create secret tls` cannot use it. In Git Bash on Windows prefix the command with `MSYS2_ARG_CONV_EXCL='/CN='`, otherwise `-subj "/CN=..."` is rewritten into a file path.

**Points:** 2% Service · 2% key and certificate with the right subject and validity · 2% TLS Secret in `m03-tls` · 2% Ingress rule (class, host, path, backend) · 1% `tls` section.

---

## Scoring table

| Question | Topic | Weight | Your score |
|---|---|---|---|
| 1 | Liveness probe port | 3% | |
| 2 | DaemonSet on every node | 4% | |
| 3 | Helm values / upgrade / rollback | 6% | |
| 4 | RBAC 403 + image pull secret | 7% | |
| 5 | Native sidecar + memory emptyDir | 6% | |
| 6 | Labels for existing NetworkPolicies | 6% | |
| 7 | Pause / resume rollout | 5% | |
| 8 | Downward API + Guaranteed QoS | 5% | |
| 9 | Ephemeral debug container | 4% | |
| 10 | Fix and harden an image | 4% | |
| 11 | Ingress v1beta1 to v1 | 6% | |
| 12 | Kustomize generators | 5% | |
| 13 | PSA restricted Pod | 6% | |
| 14 | Pending Pod | 5% | |
| 15 | StatefulSet + headless DNS | 6% | |
| 16 | Canary 20% with 5 Pods | 5% | |
| 17 | CRD discovery + custom resource | 5% | |
| 18 | Logs by label | 3% | |
| 19 | TLS Ingress | 9% | |
| **Total** | | **100%** | **/100** |

66% or more is a pass. Below 66%: redo the questions you missed tomorrow without looking at the solutions.

## If you missed it, study

| Question | Study |
|---|---|
| Q2, Q5, Q10, Q15 | [01 Application Design and Build](../../01-Application-Design-and-Build/README.md) |
| Q3, Q7, Q12, Q16 | [02 Application Deployment](../../02-Application-Deployment/README.md) |
| Q1, Q9, Q11 (deprecations), Q14, Q18 | [03 Application Observability and Maintenance](../../03-Application-Observability-and-Maintenance/README.md) |
| Q4, Q8, Q13, Q17, Q19 (TLS Secret) | [04 Application Environment, Configuration and Security](../../04-Application-Environment-Configuration-and-Security/README.md) |
| Q6, Q11, Q15 (headless DNS), Q16 (Service endpoints), Q19 | [05 Services and Networking](../../05-Services-and-Networking/README.md) |
| Q2 (taints/tolerations), Q14 (scheduling), JSONPath and custom columns | [06 Cross-Cutting Skills and Bonus Topics](../../06-Cross-Cutting-Skills-and-Bonus-Topics/README.md) |
| Exam setup, ssh-per-task workflow, aliases | [00 Exam Overview and Setup](../../00-Exam-Overview-and-Setup/README.md) |

## Coverage matrix

| Domain | Competency | Questions |
|---|---|---|
| Application Design and Build | Define, build and modify container images | Q10 |
| Application Design and Build | Choose and use the right workload resource (Deployment, DaemonSet, CronJob, etc.) | Q2 (DaemonSet), Q15 (StatefulSet), Q16 (Deployment), Q5 (Pod) |
| Application Design and Build | Understand multi-container Pod design patterns (e.g. sidecar, init and others) | Q5 (native sidecar), Q18 (two containers), Q9 (ephemeral container) |
| Application Design and Build | Utilize persistent and ephemeral volumes | Q15 (volumeClaimTemplates), Q5 (memory emptyDir), Q8 (downwardAPI volume), Q13 (emptyDir) |
| Application Deployment | Use Kubernetes primitives to implement common deployment strategies (e.g. blue/green or canary) | Q16 |
| Application Deployment | Understand Deployments and how to perform rolling updates | Q7, Q1 |
| Application Deployment | Use the Helm package manager to deploy existing packages | Q3 |
| Application Deployment | Kustomize | Q12 |
| Application Observability and Maintenance | Understand API deprecations | Q11 |
| Application Observability and Maintenance | Implement probes and health checks | Q1 |
| Application Observability and Maintenance | Use built-in CLI tools to monitor Kubernetes applications | Q1 (events), Q14 (events), Q7 (rollout status and history) |
| Application Observability and Maintenance | Utilize container logs | Q18, Q4, Q5 |
| Application Observability and Maintenance | Debugging in Kubernetes | Q9, Q14, Q1 |
| Application Environment, Configuration and Security | Discover and use resources that extend Kubernetes (CRD, Operators) | Q17 |
| Application Environment, Configuration and Security | Understand authentication, authorization and admission control | Q4 (RBAC), Q13 (Pod Security Admission) |
| Application Environment, Configuration and Security | Understand requests, limits, quotas | Q8 (QoS classes), Q14 (requests and scheduling) |
| Application Environment, Configuration and Security | Define resource requirements | Q2, Q7, Q8, Q14 |
| Application Environment, Configuration and Security | Understand ConfigMaps | Q12 |
| Application Environment, Configuration and Security | Create & consume Secrets | Q4 (docker-registry), Q12 (secretGenerator), Q19 (TLS) |
| Application Environment, Configuration and Security | Understand ServiceAccounts | Q4 |
| Application Environment, Configuration and Security | Understand Application Security (SecurityContexts, Capabilities, etc.) | Q13, Q9 |
| Services and Networking | Demonstrate basic understanding of NetworkPolicies | Q6 |
| Services and Networking | Provide and troubleshoot access to applications via services | Q15, Q16, Q19, Q11 |
| Services and Networking | Use Ingress rules to expose applications | Q11, Q19 |
