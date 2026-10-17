#!/usr/bin/env bash
# CKAD Mock Exam 04 (Intermediate+) - environment setup
#
#   bash setup.sh
#
# Creates the namespaces m04-* (label ckad-mock=exam-04), the pre-existing and
# intentionally broken objects, the Helm releases billing/audit/reports (when helm is
# installed) and the working files under ~/ckad-mocks/exam-04/. Cluster-scoped objects:
# PersistentVolume m04-reports-pv and ClusterRoleBinding m04-auditor-everywhere.
# Safe to re-run (resets most scenarios). It never modifies objects it did not create.
# Remove everything with: bash cleanup.sh
set -euo pipefail

EXAM="exam-04"
D="${HOME}/ckad-mocks/${EXAM}"
LAB_DOC="CKAD-Exam-Prep/00-Exam-Overview-and-Setup/README.md (local lab setup)"
WARNINGS=()

info() { printf '>> %s\n' "$*"; }
warn() { WARNINGS+=("$*"); printf 'WARNING: %s\n' "$*" >&2; }
have() { command -v "$1" >/dev/null 2>&1; }

# mkns <name> ["key: value" extra label lines...] - idempotent, always labelled ckad-mock=exam-04
mkns() {
  local name="$1" l
  shift
  {
    printf 'apiVersion: v1\nkind: Namespace\nmetadata:\n  name: %s\n  labels:\n    ckad-mock: %s\n' "$name" "$EXAM"
    for l in "$@"; do printf '    %s\n' "$l"; done
  } | kubectl apply -f - >/dev/null
  info "namespace ${name}"
}

# wait until a Deployment controller has observed the latest spec (new ReplicaSet exists)
wait_observed() {
  local ns="$1" name="$2" gen obs i
  for i in $(seq 1 60); do
    gen="$(kubectl -n "$ns" get deploy "$name" -o jsonpath='{.metadata.generation}' 2>/dev/null || true)"
    obs="$(kubectl -n "$ns" get deploy "$name" -o jsonpath='{.status.observedGeneration}' 2>/dev/null || true)"
    if [ -n "$gen" ] && [ "$gen" = "$obs" ]; then return 0; fi
    sleep 1
  done
  warn "deployment ${ns}/${name} did not observe its latest spec within 60s"
}

wait_rollout() {
  kubectl -n "$1" rollout status deployment "$2" --timeout="$3" >/dev/null 2>&1 \
    || warn "rollout of $1/$2 did not finish within $3 (slow image pulls?) - the scenario still works"
}

# ---------------------------------------------------------------- preflight
have kubectl || { echo "ERROR: kubectl not found in PATH" >&2; exit 1; }
if ! kubectl get nodes --request-timeout=15s >/dev/null 2>&1; then
  echo "ERROR: cannot reach a cluster with the current kubeconfig context." >&2
  echo "       Start your practice cluster first (see ${LAB_DOC})." >&2
  exit 1
fi
info "using context: $(kubectl config current-context 2>/dev/null || echo unknown)"

check_optional() {
  local avail classes pods
  # metrics-server (Q11)
  if kubectl get apiservice v1beta1.metrics.k8s.io >/dev/null 2>&1; then
    avail="$(kubectl get apiservice v1beta1.metrics.k8s.io -o jsonpath='{.status.conditions[?(@.type=="Available")].status}' 2>/dev/null || true)"
    if [ "$avail" = "True" ]; then
      info "metrics-server available"
    else
      warn "metrics-server is installed but not Available yet: Q11 needs 'kubectl top' (see ${LAB_DOC})."
    fi
  else
    warn "metrics-server not found: Q11 needs 'kubectl top' (see ${LAB_DOC})."
  fi
  # Ingress controller / IngressClass nginx (Q18)
  if kubectl get ingressclass nginx >/dev/null 2>&1; then
    info "IngressClass nginx found"
  else
    classes="$(kubectl get ingressclass -o name 2>/dev/null | tr '\n' ' ' || true)"
    if [ -n "$classes" ]; then
      warn "IngressClass 'nginx' not found (found: ${classes}). Q18 uses class nginx: substitute your class or install ingress-nginx (see ${LAB_DOC})."
    else
      warn "No ingress controller (IngressClass) found. Q18 can be solved but not tested end to end (see ${LAB_DOC})."
    fi
  fi
  # NetworkPolicy enforcement (Q6)
  pods="$(kubectl get pods -A --no-headers -o custom-columns=N:.metadata.name 2>/dev/null || true)"
  if grep -Eq 'calico|cilium|antrea|kube-router|weave' <<<"$pods"; then
    info "NetworkPolicy-capable CNI detected"
  elif grep -q 'kindnet' <<<"$pods"; then
    info "kindnet detected: kind v0.24.0+ enforces NetworkPolicies out of the box, older kind releases do not (Q6)"
  else
    warn "Could not detect a NetworkPolicy-enforcing CNI. Q6 can be graded from the YAML, but blocked traffic may not be blocked (see ${LAB_DOC})."
  fi
  if have helm; then info "helm found"; else warn "helm not found: Q8 needs it (see ${LAB_DOC})."; fi
  if have podman || have docker; then info "podman/docker found"; else warn "Neither podman nor docker found: Q3 needs one of them (see ${LAB_DOC})."; fi
  if have openssl; then info "openssl found"; else warn "openssl not found: the certificate for Q9 cannot be generated (see ${LAB_DOC})."; fi
}
check_optional

# ---------------------------------------------------------------- namespaces and work dirs
for ns in m04-cache m04-config m04-rollback m04-db m04-cron m04-helm-a m04-helm-b m04-secure \
          m04-svc m04-metrics m04-adapter m04-team-a m04-team-b m04-kustomize m04-storage \
          m04-legacy m04-quota m04-ingress m04-crd; do
  mkns "$ns"
done
mkns m04-apps "team: apps"
mkns m04-other "team: other"

mkdir -p "$D"
for i in $(seq 1 19); do mkdir -p "${D}/$(printf 'q%02d' "$i")"; done
info "work directories ${D}/q01 ... q19"

# ---------------------------------------------------------------- Q1 standalone kubeconfig (fake clusters, never contacted)
cat > "${D}/q01/kubeconfig" <<'EOF'
apiVersion: v1
kind: Config
clusters:
- name: alpha
  cluster:
    server: https://alpha.m04.example:6443
    insecure-skip-tls-verify: true
- name: beta
  cluster:
    server: https://beta.m04.example:6443
    insecure-skip-tls-verify: true
- name: gamma
  cluster:
    server: https://10.20.30.40:6443
    insecure-skip-tls-verify: true
users:
- name: dev-admin
  user:
    token: dev-admin-token-not-real
- name: qa-viewer
  user:
    token: qa-viewer-token-not-real
- name: prod-ops
  user:
    token: prod-ops-token-not-real
contexts:
- name: dev-admin@alpha
  context:
    cluster: alpha
    user: dev-admin
    namespace: dev
- name: qa-viewer@beta
  context:
    cluster: beta
    user: qa-viewer
- name: prod-ops@gamma
  context:
    cluster: gamma
    user: prod-ops
current-context: qa-viewer@beta
preferences: {}
EOF
chmod 600 "${D}/q01/kubeconfig"
info "Q1  kubeconfig ${D}/q01/kubeconfig"

# ---------------------------------------------------------------- Q2 image typo (ImagePullBackOff), no readiness probe
kubectl apply -f - >/dev/null <<'EOF'
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
        image: redis:7.2-alpline
        ports:
        - containerPort: 6379
---
apiVersion: v1
kind: Service
metadata:
  name: session-cache
  namespace: m04-cache
spec:
  selector:
    app: session-cache
  ports:
  - port: 6379
    targetPort: 6379
EOF
info "Q2  deployment m04-cache/session-cache (bad image tag)"

# ---------------------------------------------------------------- Q3 multi-stage build context
cat > "${D}/q03/Dockerfile" <<'EOF'
# Stage 1: "build" - stamps the version passed with --build-arg into the script
FROM busybox:1.36 AS build
ARG APP_VERSION=0.0.0-dev
WORKDIR /src
COPY app.sh .
RUN sed "s/__APP_VERSION__/${APP_VERSION}/" app.sh > /src/app && chmod 0755 /src/app

# Stage 2: minimal runtime image, non-root
FROM busybox:1.36
COPY --from=build /src/app /usr/local/bin/app
USER 65534
ENTRYPOINT ["/usr/local/bin/app"]
EOF
cat > "${D}/q03/app.sh" <<'EOF'
#!/bin/sh
echo "inventory-api version __APP_VERSION__"
EOF
info "Q3  build context ${D}/q03"

# ---------------------------------------------------------------- Q4 env-file
cat > "${D}/q04/batch.env" <<'EOF'
# batch job settings (env-file format: KEY=value, comments and blank lines are ignored)
MODE=batch
RETRIES=3

REGION=eu-west-1
EOF
info "Q4  env-file ${D}/q04/batch.env"

# ---------------------------------------------------------------- Q5 Deployment with 4 revisions, the last one broken
catalog_rev() {  # catalog_rev <image> <change-cause> [<command as JSON array>]
  local image="$1" cause="$2" cmd="${3:-}"
  {
    cat <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: catalog
  namespace: m04-rollback
  labels:
    app: catalog
  annotations:
    kubernetes.io/change-cause: "${cause}"
spec:
  replicas: 3
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
        image: ${image}
EOF
    if [ -n "$cmd" ]; then printf '        command: %s\n' "$cmd"; fi
  } | kubectl apply -f - >/dev/null
  wait_observed m04-rollback catalog
}
# start from a clean history every time setup runs
kubectl -n m04-rollback delete deployment catalog --ignore-not-found --cascade=foreground --wait=true --timeout=120s >/dev/null 2>&1 || true
catalog_rev nginx:1.27 "v1: initial release on nginx 1.27"
wait_rollout m04-rollback catalog 180s
catalog_rev nginx:1.27-alpine "v2: switch to the alpine base image"
wait_rollout m04-rollback catalog 180s
catalog_rev httpd:2.4 "v3: migrate to httpd"
wait_rollout m04-rollback catalog 180s
catalog_rev nginx:1.27-alpine "v4: experimental cache warm-up" '["sh", "-c", "echo warming cache; exit 1"]'
info "Q5  deployment m04-rollback/catalog (revisions 1-4, revision 4 crash-loops)"

# ---------------------------------------------------------------- Q6 database + clients in three namespaces
kubectl apply -f - >/dev/null <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: postgres
  namespace: m04-db
  labels:
    app: postgres
spec:
  containers:
  - name: postgres
    image: postgres:16
    env:
    - name: POSTGRES_PASSWORD
      value: m04-not-a-secret
    ports:
    - containerPort: 5432
---
apiVersion: v1
kind: Service
metadata:
  name: postgres
  namespace: m04-db
spec:
  selector:
    app: postgres
  ports:
  - port: 5432
    targetPort: 5432
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-ingress
  namespace: m04-db
spec:
  podSelector: {}
  policyTypes:
  - Ingress
---
apiVersion: v1
kind: Pod
metadata:
  name: api
  namespace: m04-apps
  labels:
    role: api
spec:
  containers:
  - name: api
    image: busybox:1.36
    command: ["sh", "-c", "while true; do sleep 3600; done"]
---
apiVersion: v1
kind: Pod
metadata:
  name: worker
  namespace: m04-apps
  labels:
    role: worker
spec:
  containers:
  - name: worker
    image: busybox:1.36
    command: ["sh", "-c", "while true; do sleep 3600; done"]
---
apiVersion: v1
kind: Pod
metadata:
  name: api
  namespace: m04-other
  labels:
    role: api
spec:
  containers:
  - name: api
    image: busybox:1.36
    command: ["sh", "-c", "while true; do sleep 3600; done"]
EOF
info "Q6  postgres in m04-db (default deny), clients in m04-apps and m04-other"

# ---------------------------------------------------------------- Q7 CronJob to tune
kubectl apply -f - >/dev/null <<'EOF'
apiVersion: batch/v1
kind: CronJob
metadata:
  name: nightly-report
  namespace: m04-cron
spec:
  schedule: "30 1 * * *"
  jobTemplate:
    spec:
      template:
        spec:
          restartPolicy: OnFailure
          containers:
          - name: report
            image: busybox:1.36
            command: ["sh", "-c", "date; echo nightly report done"]
EOF
info "Q7  cronjob m04-cron/nightly-report"

# ---------------------------------------------------------------- Q8 Helm chart + releases (one deliberately failed)
if have helm; then
  CHART="${D}/q08/webapp"
  rm -rf "$CHART"
  helm create "$CHART" >/dev/null
  sed -i.bak 's/^appVersion:.*/appVersion: "1.27"/' "${CHART}/Chart.yaml"
  rm -f "${CHART}/Chart.yaml.bak"
  helm upgrade --install billing "$CHART" -n m04-helm-a \
    --set replicaCount=1 --set podAnnotations.team=billing >/dev/null
  helm upgrade --install audit "$CHART" -n m04-helm-b --set replicaCount=1 >/dev/null
  if ! helm status reports -n m04-helm-b >/dev/null 2>&1; then
    # service.port=99999 is rejected by the API server, so Helm records the release as "failed"
    helm install reports "$CHART" -n m04-helm-b --set service.port=99999 >/dev/null 2>&1 || true
  fi
  failed="$(helm list -n m04-helm-b --failed -q 2>/dev/null || true)"
  if grep -qx reports <<<"$failed"; then
    info "Q8  chart ${CHART}; releases m04-helm-a/billing, m04-helm-b/audit, m04-helm-b/reports (failed)"
  else
    warn "Could not create the failed Helm release m04-helm-b/reports (Helm version difference?). Q8 part 1 has nothing to find."
  fi
fi

# ---------------------------------------------------------------- Q9 certificate and key for the TLS Secret
if have openssl; then
  # MSYS2_ARG_CONV_EXCL stops Git Bash on Windows from rewriting "/CN=..." into a file path (harmless elsewhere)
  if MSYS2_ARG_CONV_EXCL='/CN=' openssl req -x509 -nodes -newkey rsa:2048 -days 365 \
       -keyout "${D}/q09/tls.key" -out "${D}/q09/tls.crt" -subj "/CN=api.m04.local" >/dev/null 2>&1; then
    info "Q9  certificate ${D}/q09/tls.crt and key ${D}/q09/tls.key (CN=api.m04.local)"
  else
    warn "openssl could not create ${D}/q09/tls.crt and tls.key: create them yourself for Q9 (CN=api.m04.local)."
  fi
fi

# ---------------------------------------------------------------- Q10 stable + canary Deployments with named ports
for track in stable canary; do
  if [ "$track" = stable ]; then replicas=3; else replicas=1; fi
  kubectl apply -f - >/dev/null <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: shop-${track}
  namespace: m04-svc
  labels:
    app: shop
    track: ${track}
spec:
  replicas: ${replicas}
  selector:
    matchLabels:
      app: shop
      track: ${track}
  template:
    metadata:
      labels:
        app: shop
        track: ${track}
    spec:
      containers:
      - name: web
        image: nginx:1.27
        ports:
        - name: http
          containerPort: 80
      - name: status
        image: busybox:1.36
        command: ["sh", "-c", "mkdir -p /tmp/www && echo ${track}-ok > /tmp/www/healthz && exec httpd -f -p 8081 -h /tmp/www"]
        ports:
        - name: status
          containerPort: 8081
EOF
done
info "Q10 deployments m04-svc/shop-stable (3) and shop-canary (1)"

# ---------------------------------------------------------------- Q11 Pods with different memory usage + a chatty container
kubectl apply -f - >/dev/null <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: analytics
  namespace: m04-metrics
  labels:
    app: analytics
spec:
  containers:
  - name: ingest
    image: busybox:1.36
    command: ["sh", "-c", "i=0; while true; do i=$((i+1)); echo \"ingested batch $i\"; sleep 2; done"]
  - name: crunch
    image: busybox:1.36
    # writes 48 MiB to tmpfs /dev/shm, which is charged to this container's memory
    command: ["sh", "-c", "dd if=/dev/zero of=/dev/shm/blob bs=1M count=48 2>/dev/null; while true; do sleep 3600; done"]
---
apiVersion: v1
kind: Pod
metadata:
  name: cache-warmer
  namespace: m04-metrics
  labels:
    app: cache-warmer
spec:
  containers:
  - name: warmer
    image: busybox:1.36
    command: ["sh", "-c", "dd if=/dev/zero of=/dev/shm/blob bs=1M count=20 2>/dev/null; while true; do sleep 3600; done"]
---
apiVersion: v1
kind: Pod
metadata:
  name: idle
  namespace: m04-metrics
  labels:
    app: idle
spec:
  containers:
  - name: idle
    image: registry.k8s.io/pause:3.10
EOF
info "Q11 pods analytics (ingest + crunch), cache-warmer, idle in m04-metrics"

# ---------------------------------------------------------------- Q12 legacy log format + converter script
kubectl apply -f - >/dev/null <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: adapter-script
  namespace: m04-adapter
data:
  adapt.sh: |
    #!/bin/sh
    # Converts "<epoch>|<LEVEL>|<message>" lines into JSON lines for the log pipeline.
    tail -F /var/log/legacy/app.log | while IFS='|' read -r ts level msg; do
      printf '{"ts":%s,"level":"%s","msg":"%s"}\n' "$ts" "$level" "$msg"
    done
---
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
      volumes:
      - name: logs
        emptyDir: {}
EOF
info "Q12 deployment m04-adapter/legacy-reporter + configmap adapter-script"

# ---------------------------------------------------------------- Q13 over-privileged ServiceAccount
kubectl apply -f - >/dev/null <<'EOF'
apiVersion: v1
kind: ServiceAccount
metadata:
  name: auditor
  namespace: m04-team-a
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: m04-auditor-everywhere
  labels:
    ckad-mock: exam-04
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: view
subjects:
- kind: ServiceAccount
  name: auditor
  namespace: m04-team-a
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web
  namespace: m04-team-a
  labels:
    app: web
spec:
  replicas: 1
  selector:
    matchLabels:
      app: web
  template:
    metadata:
      labels:
        app: web
    spec:
      containers:
      - name: web
        image: registry.k8s.io/pause:3.10
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web
  namespace: m04-team-b
  labels:
    app: web
spec:
  replicas: 1
  selector:
    matchLabels:
      app: web
  template:
    metadata:
      labels:
        app: web
    spec:
      containers:
      - name: web
        image: registry.k8s.io/pause:3.10
EOF
info "Q13 sa m04-team-a/auditor bound cluster-wide by clusterrolebinding m04-auditor-everywhere"

# ---------------------------------------------------------------- Q14 Kustomize base
mkdir -p "${D}/q14/base"
cat > "${D}/q14/base/deployment.yaml" <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: inventory
  labels:
    app: inventory
spec:
  replicas: 1
  selector:
    matchLabels:
      app: inventory
  template:
    metadata:
      labels:
        app: inventory
    spec:
      containers:
      - name: app
        image: nginx:1.27
        ports:
        - containerPort: 80
EOF
cat > "${D}/q14/base/service.yaml" <<'EOF'
apiVersion: v1
kind: Service
metadata:
  name: inventory
  labels:
    app: inventory
spec:
  selector:
    app: inventory
  ports:
  - port: 80
    targetPort: 80
EOF
cat > "${D}/q14/base/kustomization.yaml" <<'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- deployment.yaml
- service.yaml
EOF
info "Q14 kustomize base ${D}/q14/base"

# ---------------------------------------------------------------- Q15 static PV + mismatching PVC + Pod
kubectl apply -f - >/dev/null <<'EOF'
apiVersion: v1
kind: PersistentVolume
metadata:
  name: m04-reports-pv
  labels:
    ckad-mock: exam-04
spec:
  capacity:
    storage: 1Gi
  accessModes:
  - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: manual
  hostPath:
    path: /tmp/m04-reports
    type: DirectoryOrCreate
EOF
if ! kubectl -n m04-storage get pvc reports-data >/dev/null 2>&1; then
  kubectl apply -f - >/dev/null <<'EOF'
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: reports-data
  namespace: m04-storage
spec:
  storageClassName: fast-ssd
  accessModes:
  - ReadWriteMany
  resources:
    requests:
      storage: 1Gi
EOF
fi
cat > "${D}/q15/reports-pod.yaml" <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: reports
  namespace: m04-storage
  labels:
    app: reports
spec:
  containers:
  - name: reports
    image: busybox:1.36
    command: ["sh", "-c", "date >> /data/report.txt; while true; do sleep 3600; done"]
    volumeMounts:
    - name: data
      mountPath: /data
  volumes:
  - name: data
    persistentVolumeClaim:
      claimName: reports-data
EOF
kubectl apply -f "${D}/q15/reports-pod.yaml" >/dev/null 2>&1 || warn "Pod m04-storage/reports already exists with a different spec - left unchanged"
info "Q15 pv m04-reports-pv, pvc m04-storage/reports-data (Pending), pod reports"

# ---------------------------------------------------------------- Q16 HPA target + legacy manifests
kubectl apply -f - >/dev/null <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ticker
  namespace: m04-legacy
  labels:
    app: ticker
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
      containers:
      - name: ticker
        image: nginx:1.27-alpine
        resources:
          requests:
            cpu: 50m
            memory: 32Mi
          limits:
            cpu: 200m
            memory: 64Mi
EOF
mkdir -p "${D}/q16/legacy"
cat > "${D}/q16/legacy/cronjob.yaml" <<'EOF'
# Legacy manifest (Kubernetes 1.20 era) - do not modify this file.
apiVersion: batch/v1beta1
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
EOF
cat > "${D}/q16/legacy/hpa.yaml" <<'EOF'
# Legacy manifest (Kubernetes 1.22 era) - do not modify this file.
apiVersion: autoscaling/v2beta2
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
EOF
rm -rf "${D}/q16/fixed"
info "Q16 deployment m04-legacy/ticker + ${D}/q16/legacy/{cronjob,hpa}.yaml"

# ---------------------------------------------------------------- Q17 ResourceQuota (object counts) already full
# Workload first, quota last: a brand-new quota has no status yet and would make admission
# reject Pods ("status unknown for quota"). On a re-run the quota may already be full.
kubectl apply -f - >/dev/null <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: worker
  namespace: m04-quota
  labels:
    app: worker
spec:
  replicas: 2
  selector:
    matchLabels:
      app: worker
  template:
    metadata:
      labels:
        app: worker
    spec:
      containers:
      - name: worker
        image: busybox:1.36
        command: ["sh", "-c", "while true; do echo working; sleep 30; done"]
EOF
kubectl apply -f - >/dev/null 2>&1 <<'EOF' || warn "debug Pods in m04-quota not (re)created - quota already full from an earlier run"
apiVersion: v1
kind: Pod
metadata:
  name: debug-shell-1
  namespace: m04-quota
  labels:
    purpose: debug
spec:
  containers:
  - name: shell
    image: busybox:1.36
    command: ["sh", "-c", "while true; do sleep 3600; done"]
---
apiVersion: v1
kind: Pod
metadata:
  name: debug-shell-2
  namespace: m04-quota
  labels:
    purpose: debug
spec:
  containers:
  - name: shell
    image: busybox:1.36
    command: ["sh", "-c", "while true; do sleep 3600; done"]
EOF
kubectl apply -f - >/dev/null <<'EOF'
apiVersion: v1
kind: ResourceQuota
metadata:
  name: m04-objects
  namespace: m04-quota
spec:
  hard:
    pods: "4"
    services: "2"
    count/deployments.apps: "2"
    count/configmaps: "5"
EOF
info "Q17 deployment m04-quota/worker (2) + 2 debug pods + resourcequota m04-objects (pods=4)"

# ---------------------------------------------------------------- Q18 two apps for host-based routing
kubectl apply -f - >/dev/null <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: blog
  namespace: m04-ingress
  labels:
    app: blog
spec:
  replicas: 1
  selector:
    matchLabels:
      app: blog
  template:
    metadata:
      labels:
        app: blog
    spec:
      containers:
      - name: blog
        image: nginx:1.27
        ports:
        - containerPort: 80
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: wiki
  namespace: m04-ingress
  labels:
    app: wiki
spec:
  replicas: 1
  selector:
    matchLabels:
      app: wiki
  template:
    metadata:
      labels:
        app: wiki
    spec:
      containers:
      - name: wiki
        image: httpd:2.4
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: blog
  namespace: m04-ingress
spec:
  selector:
    app: blog
  ports:
  - port: 80
    targetPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: wiki
  namespace: m04-ingress
spec:
  selector:
    app: wiki
  ports:
  - name: web
    port: 8080
    targetPort: 80
EOF
info "Q18 services m04-ingress/blog (80) and wiki (8080, named web)"

# ---------------------------------------------------------------- summary
echo
echo "================ CKAD Mock Exam 04 is ready ================"
echo "Namespaces : $(kubectl get ns -l "ckad-mock=${EXAM}" -o name | sed 's#namespace/##' | tr '\n' ' ')"
echo "Cluster    : persistentvolume m04-reports-pv, clusterrolebinding m04-auditor-everywhere"
echo "Work files : ${D}/q01 ... ${D}/q19"
echo "Broken on purpose: m04-cache/session-cache, m04-rollback/catalog (rev 4), helm release reports,"
echo "                   m04-storage/reports-data, q16 legacy manifests, m04-quota (quota full)"
if [ "${#WARNINGS[@]}" -gt 0 ]; then
  echo
  echo "Warnings (${#WARNINGS[@]}) - the affected questions cannot be fully tested:"
  for w in "${WARNINGS[@]}"; do echo "  - $w"; done
fi
echo
echo "Pods may need a minute or two to pull images (postgres:16 is the largest)."
echo "Start your 120-minute timer and open questions.md."
