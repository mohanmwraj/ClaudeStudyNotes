#!/usr/bin/env bash
# CKAD Mock Exam 03 (Intermediate) - environment setup
#
#   bash setup.sh
#
# Creates the namespaces m03-* (label ckad-mock=exam-03), the pre-existing and
# intentionally broken objects used by the questions, and the working files under
# ~/ckad-mocks/exam-03/. Safe to re-run: objects are applied idempotently and the
# provided starter files are rewritten (this resets the broken scenarios).
# It never modifies objects it did not create. Remove everything with: bash cleanup.sh
set -euo pipefail

EXAM="exam-03"
D="${HOME}/ckad-mocks/${EXAM}"
LAB_DOC="CKAD-Exam-Prep/00-Exam-Overview-and-Setup/README.md (local lab setup)"
WARNINGS=()

info() { printf '>> %s\n' "$*"; }
warn() { WARNINGS+=("$*"); printf 'WARNING: %s\n' "$*" >&2; }
have() { command -v "$1" >/dev/null 2>&1; }

# mkns <name> ["key: value" extra label lines...] - idempotent, always labelled ckad-mock=exam-03
mkns() {
  local name="$1" l
  shift
  {
    printf 'apiVersion: v1\nkind: Namespace\nmetadata:\n  name: %s\n  labels:\n    ckad-mock: %s\n' "$name" "$EXAM"
    for l in "$@"; do printf '    %s\n' "$l"; done
  } | kubectl apply -f - >/dev/null
  info "namespace ${name}"
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
  local classes pods defaults
  # Ingress controller / IngressClass nginx (Q11, Q19)
  if kubectl get ingressclass nginx >/dev/null 2>&1; then
    info "IngressClass nginx found"
  else
    classes="$(kubectl get ingressclass -o name 2>/dev/null | tr '\n' ' ' || true)"
    if [ -n "$classes" ]; then
      warn "IngressClass 'nginx' not found (found: ${classes}). Q11/Q19 use class nginx: substitute your class or install ingress-nginx (see ${LAB_DOC})."
    else
      warn "No ingress controller (IngressClass) found. Q11 and Q19 can be solved but not tested end to end (see ${LAB_DOC})."
    fi
  fi
  # NetworkPolicy enforcement (Q6)
  pods="$(kubectl get pods -A --no-headers -o custom-columns=N:.metadata.name 2>/dev/null || true)"
  if grep -Eq 'calico|cilium|antrea|kube-router|weave' <<<"$pods"; then
    info "NetworkPolicy-capable CNI detected"
  elif grep -q 'kindnet' <<<"$pods"; then
    info "kindnet detected: kind v0.24.0+ enforces NetworkPolicies out of the box, older kind releases do not (Q6)"
  else
    warn "Could not detect a NetworkPolicy-enforcing CNI. Q6 can still be graded by labels, but blocked traffic may not be blocked (see ${LAB_DOC})."
  fi
  # default StorageClass (Q15)
  defaults="$(kubectl get storageclass -o jsonpath='{range .items[*]}{.metadata.annotations.storageclass\.kubernetes\.io/is-default-class}{"\n"}{end}' 2>/dev/null || true)"
  if grep -q true <<<"$defaults"; then
    info "default StorageClass found"
  else
    warn "No default StorageClass found: the PVCs of Q15 would stay Pending (see ${LAB_DOC})."
  fi
  if have helm; then info "helm found"; else warn "helm not found: Q3 needs it (see ${LAB_DOC})."; fi
  if have podman || have docker; then info "podman/docker found"; else warn "Neither podman nor docker found: Q10 needs one of them (see ${LAB_DOC})."; fi
  if have openssl; then info "openssl found"; else warn "openssl not found: Q19 needs it (see ${LAB_DOC})."; fi
}
check_optional

# ---------------------------------------------------------------- namespaces and work dirs
for ns in m03-probes m03-ds m03-helm m03-rbac m03-sidecar m03-netpol m03-rollout m03-downward \
          m03-debug m03-legacy m03-kust m03-sched m03-sts m03-canary m03-crd m03-logs m03-tls m03-certs; do
  mkns "$ns"
done
mkns m03-psa "pod-security.kubernetes.io/enforce: restricted" \
             "pod-security.kubernetes.io/enforce-version: latest" \
             "pod-security.kubernetes.io/warn: restricted"

mkdir -p "$D"
for i in $(seq 1 19); do mkdir -p "${D}/$(printf 'q%02d' "$i")"; done
info "work directories ${D}/q01 ... q19"

# ---------------------------------------------------------------- Q1 liveness probe on the wrong port
kubectl apply -f - >/dev/null <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: pricing
  namespace: m03-probes
  labels:
    app: pricing
spec:
  replicas: 2
  selector:
    matchLabels:
      app: pricing
  template:
    metadata:
      labels:
        app: pricing
    spec:
      containers:
      - name: pricing
        image: nginx:1.27
        ports:
        - containerPort: 80
        readinessProbe:
          httpGet:
            path: /
            port: 80
          periodSeconds: 5
        livenessProbe:
          httpGet:
            path: /
            port: 8080
          initialDelaySeconds: 5
          periodSeconds: 5
          failureThreshold: 3
EOF
info "Q1  deployment m03-probes/pricing (broken liveness probe)"

# ---------------------------------------------------------------- Q3 local Helm chart
if have helm; then
  rm -rf "${D}/q03/webapp"
  helm create "${D}/q03/webapp" >/dev/null
  # pin the chart's default image tag (appVersion) to a current nginx release
  sed -i.bak 's/^appVersion:.*/appVersion: "1.27"/' "${D}/q03/webapp/Chart.yaml"
  rm -f "${D}/q03/webapp/Chart.yaml.bak"
  info "Q3  chart ${D}/q03/webapp (helm create, appVersion 1.27)"
fi

# ---------------------------------------------------------------- Q4 RBAC 403 + ServiceAccount
kubectl apply -f - >/dev/null <<'EOF'
apiVersion: v1
kind: ServiceAccount
metadata:
  name: inventory
  namespace: m03-rbac
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: configmap-reader
  namespace: m03-rbac
rules:
- apiGroups: [""]
  resources: ["configmaps"]
  verbs: ["get", "list", "watch"]
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: inventory-settings
  namespace: m03-rbac
data:
  warehouse: "berlin-02"
  syncIntervalSeconds: "10"
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: inventory-sync
  namespace: m03-rbac
  labels:
    app: inventory-sync
spec:
  replicas: 1
  selector:
    matchLabels:
      app: inventory-sync
  template:
    metadata:
      labels:
        app: inventory-sync
    spec:
      containers:
      - name: sync
        image: curlimages/curl:8.10.1
        command:
        - sh
        - -c
        - |
          SA=/var/run/secrets/kubernetes.io/serviceaccount
          while true; do
            code=$(curl -s -o /tmp/resp.json -w '%{http_code}' --cacert "$SA/ca.crt" \
              -H "Authorization: Bearer $(cat "$SA/token")" \
              "https://kubernetes.default.svc/api/v1/namespaces/m03-rbac/configmaps")
            echo "$(date +%T) HTTP $code $(grep -o 'forbidden: User [^ ]*' /tmp/resp.json)"
            sleep 10
          done
EOF
info "Q4  deployment m03-rbac/inventory-sync (HTTP 403), sa inventory, role configmap-reader"

# ---------------------------------------------------------------- Q6 NetworkPolicies + unlabelled Pods
kubectl apply -f - >/dev/null <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: frontend
  namespace: m03-netpol
  labels:
    app: frontend
spec:
  containers:
  - name: frontend
    image: busybox:1.36
    command: ["sh", "-c", "while true; do sleep 3600; done"]
---
apiVersion: v1
kind: Pod
metadata:
  name: api
  namespace: m03-netpol
  labels:
    app: api
spec:
  containers:
  - name: api
    image: nginx:1.27
    ports:
    - containerPort: 80
---
apiVersion: v1
kind: Pod
metadata:
  name: db
  namespace: m03-netpol
  labels:
    app: db
spec:
  containers:
  - name: db
    image: redis:7.2
    ports:
    - containerPort: 6379
---
apiVersion: v1
kind: Service
metadata:
  name: api
  namespace: m03-netpol
spec:
  selector:
    app: api
  ports:
  - port: 80
    targetPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: db
  namespace: m03-netpol
spec:
  selector:
    app: db
  ports:
  - port: 6379
    targetPort: 6379
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-ingress
  namespace: m03-netpol
spec:
  podSelector: {}
  policyTypes:
  - Ingress
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: api-allow-web
  namespace: m03-netpol
spec:
  podSelector:
    matchLabels:
      tier: api
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          tier: web
          env: prod
    ports:
    - protocol: TCP
      port: 80
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: db-allow-api
  namespace: m03-netpol
spec:
  podSelector:
    matchLabels:
      tier: db
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          tier: api
    ports:
    - protocol: TCP
      port: 6379
EOF
info "Q6  pods frontend/api/db, services, 3 network policies in m03-netpol"

# ---------------------------------------------------------------- Q7 rollout pause/resume
kubectl apply -f - >/dev/null <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api-gateway
  namespace: m03-rollout
  labels:
    app: api-gateway
  annotations:
    kubernetes.io/change-cause: "initial release"
spec:
  replicas: 3
  selector:
    matchLabels:
      app: api-gateway
  template:
    metadata:
      labels:
        app: api-gateway
    spec:
      containers:
      - name: gateway
        image: nginx:1.27
        ports:
        - containerPort: 80
EOF
info "Q7  deployment m03-rollout/api-gateway (revision 1)"

# ---------------------------------------------------------------- Q9 shell-less Pod for kubectl debug
kubectl apply -f - >/dev/null <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: distroless-api
  namespace: m03-debug
  labels:
    app: distroless-api
spec:
  containers:
  - name: api
    image: registry.k8s.io/pause:3.10
    args: ["--config=/etc/api/config.yaml", "--port=8443"]
    securityContext:
      runAsUser: 10001
      runAsGroup: 10001
      allowPrivilegeEscalation: false
EOF
info "Q9  pod m03-debug/distroless-api (no shell in image)"

# ---------------------------------------------------------------- Q10 image build context (build fails on purpose)
cat > "${D}/q10/Dockerfile" <<'EOF'
FROM busybox:1.36
ENV APP_MODE=dev
COPY index.html /www/index.html
EXPOSE 80
CMD httpd -f -p 80 -h /www
EOF
cat > "${D}/q10/index.html" <<'EOF'
<!doctype html>
<html><body><h1>Message of the day: small images, non-root users.</h1></body></html>
EOF
cat > "${D}/q10/.dockerignore" <<'EOF'
# keep the build context small
*.md
*.html
EOF
cat > "${D}/q10/NOTES.md" <<'EOF'
# Build notes
m03-motd serves index.html with the busybox httpd applet.
EOF
info "Q10 build context ${D}/q10"

# ---------------------------------------------------------------- Q11 legacy Ingress + backends
kubectl apply -f - >/dev/null <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: shop-api-content
  namespace: m03-legacy
data:
  index.html: "shop-api OK\n"
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: shop-frontend
  namespace: m03-legacy
  labels:
    app: shop-frontend
spec:
  replicas: 1
  selector:
    matchLabels:
      app: shop-frontend
  template:
    metadata:
      labels:
        app: shop-frontend
    spec:
      containers:
      - name: web
        image: nginx:1.27
        ports:
        - containerPort: 80
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: shop-api
  namespace: m03-legacy
  labels:
    app: shop-api
spec:
  replicas: 1
  selector:
    matchLabels:
      app: shop-api
  template:
    metadata:
      labels:
        app: shop-api
    spec:
      containers:
      - name: api
        image: httpd:2.4
        ports:
        - containerPort: 80
        volumeMounts:
        - name: content
          mountPath: /usr/local/apache2/htdocs/api
      volumes:
      - name: content
        configMap:
          name: shop-api-content
---
apiVersion: v1
kind: Service
metadata:
  name: shop-frontend
  namespace: m03-legacy
spec:
  selector:
    app: shop-frontend
  ports:
  - port: 80
    targetPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: shop-api
  namespace: m03-legacy
spec:
  selector:
    app: shop-api
  ports:
  - port: 8080
    targetPort: 80
EOF
cat > "${D}/q11/legacy-ingress.yaml" <<'EOF'
# Legacy manifest written for Kubernetes 1.18 - do not modify this file.
apiVersion: networking.k8s.io/v1beta1
kind: Ingress
metadata:
  name: legacy-shop
  namespace: m03-legacy
  annotations:
    kubernetes.io/ingress.class: nginx
spec:
  rules:
  - host: shop.m03.local
    http:
      paths:
      - path: /api
        backend:
          serviceName: shop-api
          servicePort: 8080
      - path: /
        backend:
          serviceName: shop-frontend
          servicePort: 80
EOF
info "Q11 services shop-frontend/shop-api + ${D}/q11/legacy-ingress.yaml"

# ---------------------------------------------------------------- Q12 Kustomize generators (files only)
cat > "${D}/q12/deployment.yaml" <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: report-api
  labels:
    app: report-api
spec:
  replicas: 1
  selector:
    matchLabels:
      app: report-api
  template:
    metadata:
      labels:
        app: report-api
    spec:
      containers:
      - name: report-api
        image: busybox:1.36
        command: ["sh", "-c", "echo LOG_LEVEL=$LOG_LEVEL; echo token-length=${#API_TOKEN}; cat /etc/report/app.properties; while true; do sleep 3600; done"]
        envFrom:
        - configMapRef:
            name: report-config
        env:
        - name: API_TOKEN
          valueFrom:
            secretKeyRef:
              name: report-secret
              key: API_TOKEN
        volumeMounts:
        - name: config
          mountPath: /etc/report
      volumes:
      - name: config
        configMap:
          name: report-config
EOF
cat > "${D}/q12/app.properties" <<'EOF'
report.format=pdf
report.retention.days=14
EOF
rm -f "${D}/q12/kustomization.yaml" "${D}/q12/rendered.yaml"
info "Q12 kustomize inputs ${D}/q12"

# ---------------------------------------------------------------- Q13 manifest rejected by PSA restricted
cat > "${D}/q13/secure-web.yaml" <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: secure-web
  namespace: m03-psa
  labels:
    app: secure-web
spec:
  containers:
  - name: web
    image: busybox:1.36
    command: ["sh", "-c", "echo secure > /www/index.html && exec httpd -f -p 8080 -h /www"]
    ports:
    - containerPort: 8080
    securityContext:
      privileged: true
      runAsUser: 0
      capabilities:
        add: ["NET_ADMIN"]
    volumeMounts:
    - name: www
      mountPath: /www
  volumes:
  - name: www
    hostPath:
      path: /tmp/m03-www
      type: DirectoryOrCreate
EOF
info "Q13 namespace m03-psa (enforce=restricted) + ${D}/q13/secure-web.yaml"

# ---------------------------------------------------------------- Q14 Pending Pod
kubectl apply -f - >/dev/null <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: reporter
  namespace: m03-sched
  labels:
    app: reporter
spec:
  replicas: 1
  selector:
    matchLabels:
      app: reporter
  template:
    metadata:
      labels:
        app: reporter
    spec:
      nodeSelector:
        kubernetes.io/os: linx
      containers:
      - name: reporter
        image: busybox:1.36
        command: ["sh", "-c", "while true; do echo report generated; sleep 60; done"]
        resources:
          requests:
            cpu: 100m
            memory: 200Gi
EOF
info "Q14 deployment m03-sched/reporter (unschedulable)"

# ---------------------------------------------------------------- Q16 stable version for the canary task
kubectl apply -f - >/dev/null <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: checkout-v1
  namespace: m03-canary
  labels:
    app: checkout
    track: stable
spec:
  replicas: 5
  selector:
    matchLabels:
      app: checkout
      track: stable
  template:
    metadata:
      labels:
        app: checkout
        tier: frontend
        track: stable
    spec:
      containers:
      - name: checkout
        image: nginx:1.27
        ports:
        - containerPort: 80
        resources:
          requests:
            cpu: 10m
            memory: 16Mi
---
apiVersion: v1
kind: Service
metadata:
  name: checkout
  namespace: m03-canary
spec:
  selector:
    app: checkout
    tier: frontend
  ports:
  - port: 80
    targetPort: 80
EOF
info "Q16 deployment m03-canary/checkout-v1 (5 replicas) + service checkout"

# ---------------------------------------------------------------- Q17 operator-style CRD (cluster-scoped, labelled)
kubectl apply -f - >/dev/null <<'EOF'
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: databasebackups.ops.m03.example.com
  labels:
    ckad-mock: exam-03
spec:
  group: ops.m03.example.com
  scope: Namespaced
  names:
    plural: databasebackups
    singular: databasebackup
    kind: DatabaseBackup
    shortNames: ["dbb"]
  versions:
  - name: v1
    served: true
    storage: true
    subresources:
      status: {}
    additionalPrinterColumns:
    - name: Schedule
      type: string
      jsonPath: .spec.schedule
    - name: Database
      type: string
      jsonPath: .spec.target.database
    - name: Tier
      type: string
      jsonPath: .spec.storageTier
    schema:
      openAPIV3Schema:
        type: object
        description: DatabaseBackup tells the backup operator what to back up, when, and how long to keep it.
        properties:
          spec:
            type: object
            required: ["schedule", "target"]
            properties:
              schedule:
                type: string
                description: Cron expression (UTC) that defines when the backup runs, for example "0 2 * * *".
              target:
                type: object
                required: ["database"]
                description: The database to back up.
                properties:
                  database:
                    type: string
                    description: Name of the database to back up.
                  host:
                    type: string
                    description: Database host name. Defaults to the in-cluster postgres Service.
              retention:
                type: object
                description: How many backups the operator keeps.
                properties:
                  keepLast:
                    type: integer
                    minimum: 1
                    maximum: 30
                    description: Number of most recent successful backups to keep (1-30). Older backups are pruned.
                  keepDays:
                    type: integer
                    minimum: 1
                    description: Delete backups older than this many days.
              storageTier:
                type: string
                enum: ["standard", "archive"]
                description: Storage tier of the backup bucket, standard or archive.
          status:
            type: object
            properties:
              phase:
                type: string
              lastBackupTime:
                type: string
EOF
kubectl apply -f - >/dev/null <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: backup-operator
  namespace: m03-crd
  labels:
    app: backup-operator
spec:
  replicas: 1
  selector:
    matchLabels:
      app: backup-operator
  template:
    metadata:
      labels:
        app: backup-operator
    spec:
      containers:
      - name: operator
        image: registry.k8s.io/pause:3.10
EOF
info "Q17 crd databasebackups.ops.m03.example.com + deployment m03-crd/backup-operator"

# ---------------------------------------------------------------- Q18 two-container Deployment that logs
kubectl apply -f - >/dev/null <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: orders
  namespace: m03-logs
  labels:
    app: orders
spec:
  replicas: 2
  selector:
    matchLabels:
      app: orders
  template:
    metadata:
      labels:
        app: orders
    spec:
      containers:
      - name: app
        image: busybox:1.36
        command: ["sh", "-c", "echo 'orders-app started'; i=0; while true; do i=$((i+1)); echo \"order $i received\"; sleep 3; done"]
      - name: audit
        image: busybox:1.36
        command: ["sh", "-c", "echo 'audit-trail started'; i=0; while true; do i=$((i+1)); echo \"audit event $i written\"; sleep 3; done"]
EOF
info "Q18 deployment m03-logs/orders (containers app + audit)"

# ---------------------------------------------------------------- Q19 app without Service + decoy TLS secret
kubectl apply -f - >/dev/null <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: portal
  namespace: m03-tls
  labels:
    app: portal
spec:
  replicas: 2
  selector:
    matchLabels:
      app: portal
  template:
    metadata:
      labels:
        app: portal
    spec:
      containers:
      - name: portal
        image: nginx:1.27
        ports:
        - containerPort: 80
EOF
if have openssl; then
  tmp="$(mktemp -d)"
  # MSYS2_ARG_CONV_EXCL stops Git Bash on Windows from rewriting "/CN=..." into a file path (harmless elsewhere)
  if MSYS2_ARG_CONV_EXCL='/CN=' openssl req -x509 -nodes -newkey rsa:2048 -days 30 \
       -keyout "${tmp}/tls.key" -out "${tmp}/tls.crt" -subj "/CN=legacy-portal.m03.local" >/dev/null 2>&1; then
    kubectl -n m03-certs create secret tls portal-tls --cert="${tmp}/tls.crt" --key="${tmp}/tls.key" \
      --dry-run=client -o yaml | kubectl apply -f - >/dev/null
    info "Q19 decoy secret m03-certs/portal-tls (CN=legacy-portal.m03.local)"
  else
    warn "openssl could not create the decoy certificate for Q19 (the task itself is unaffected)."
  fi
  rm -rf "$tmp"
fi
info "Q19 deployment m03-tls/portal (no Service yet)"

# ---------------------------------------------------------------- summary
echo
echo "================ CKAD Mock Exam 03 is ready ================"
echo "Namespaces : $(kubectl get ns -l "ckad-mock=${EXAM}" -o name | sed 's#namespace/##' | tr '\n' ' ')"
echo "Cluster    : customresourcedefinition databasebackups.ops.m03.example.com"
echo "Work files : ${D}/q01 ... ${D}/q19"
echo "Broken on purpose: m03-probes/pricing, m03-rbac/inventory-sync, m03-sched/reporter,"
echo "                   q10/Dockerfile build, q11/legacy-ingress.yaml, q13/secure-web.yaml"
if [ "${#WARNINGS[@]}" -gt 0 ]; then
  echo
  echo "Warnings (${#WARNINGS[@]}) - the affected questions cannot be fully tested:"
  for w in "${WARNINGS[@]}"; do echo "  - $w"; done
fi
echo
echo "Pods may need a minute or two to pull images. Start your 120-minute timer and open questions.md."
