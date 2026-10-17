#!/usr/bin/env bash
# =============================================================================
# CKAD Mock Exam 01 — Foundations — environment setup
#
#   bash setup.sh            create the starting state (safe to re-run)
#   RESET=1 bash setup.sh    same, and also restore the original input files
#
# Creates (and nothing else):
#   - namespaces m01-*            labelled ckad-mock=exam-01
#   - CRD backups.m01.example.com labelled ckad-mock=exam-01
#   - the pre-existing / intentionally broken objects the questions refer to
#   - input files under ~/ckad-mocks/exam-01/qNN/
# Re-running re-applies the starting objects; it may undo changes you made to them.
# Remove everything with: bash cleanup.sh
# =============================================================================
set -euo pipefail

EXAM="exam-01"
LABEL="ckad-mock=${EXAM}"
BASE="${HOME}/ckad-mocks/${EXAM}"
LAB_DOC="00-Exam-Overview-and-Setup/02-local-practice-lab-setup.md"
NAMESPACES=(
  m01-batch m01-sidecar m01-storage m01-rollout m01-canary m01-kustomize
  m01-health m01-legacy m01-monitor m01-config m01-rbac m01-secure
  m01-quota m01-crd m01-svc m01-ingress m01-netpol m01-netpol-ext
)
WARNINGS=()

info() { printf '==> %s\n' "$*"; }
warn() { WARNINGS+=("$*"); printf 'WARNING: %s\n' "$*" >&2; }
have() { command -v "$1" >/dev/null 2>&1; }
apply() { kubectl apply -f - >/dev/null; }

# put_file PATH: write stdin to PATH, but keep an existing file unless RESET=1
put_file() {
  local path="$1"
  if [[ -e "${path}" && "${RESET:-0}" != "1" ]]; then
    cat >/dev/null
    return 0
  fi
  mkdir -p "$(dirname "${path}")"
  cat >"${path}"
}

# ----------------------------------------------------------------- pre-flight
have kubectl || { echo "ERROR: kubectl not found in PATH." >&2; exit 1; }
if ! kubectl get namespace default >/dev/null 2>&1; then
  echo "ERROR: cannot reach a cluster with the current kubeconfig context." >&2
  echo "       Build the practice cluster first: ${LAB_DOC}" >&2
  exit 1
fi
info "Cluster context: $(kubectl config current-context 2>/dev/null || echo unknown)"

# ------------------------------------------- optional components (warn only)
metrics_ok="$(kubectl get apiservice v1beta1.metrics.k8s.io \
  -o jsonpath='{.status.conditions[?(@.type=="Available")].status}' 2>/dev/null || true)"
if [[ "${metrics_ok}" != "True" ]]; then
  warn "metrics-server is not available: Q11 ('kubectl top') cannot be solved yet. See ${LAB_DOC} (section 4b)."
fi

if ! kubectl get ingressclass nginx >/dev/null 2>&1; then
  warn "IngressClass 'nginx' not found: Q18 can be written but not tested end-to-end. See ${LAB_DOC} (section 4a)."
fi

cni_images="$(kubectl get pods -n kube-system -o jsonpath='{.items[*].spec.containers[*].image}' 2>/dev/null || true)"
if grep -Eqi 'calico|cilium|antrea|weave|kube-router' <<<"${cni_images}"; then
  info "NetworkPolicy-capable CNI detected."
elif grep -qi 'kindnet' <<<"${cni_images}"; then
  info "kindnet detected: it enforces NetworkPolicy on kind >= v0.24.0 (older kind versions do not)."
else
  warn "No NetworkPolicy-enforcing CNI detected: Q19 policies are accepted but may not block traffic. See ${LAB_DOC} (section 4c)."
fi

if ! have helm; then
  warn "helm not found: Q7 needs it (its chart is generated with 'helm create'). Install Helm, then re-run setup.sh. See ${LAB_DOC} (section 3)."
fi
if ! have podman && ! have docker; then
  warn "Neither podman nor docker found: Q1 (image build) needs one of them. See ${LAB_DOC} (section 2)."
fi

# ----------------------------------------------------------------- namespaces
info "Creating namespaces (label ${LABEL})"
for ns in "${NAMESPACES[@]}"; do
  kubectl create namespace "${ns}" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
  kubectl label namespace "${ns}" "${LABEL}" --overwrite >/dev/null
done

info "Creating ${BASE}/q01 ... q19"
for q in $(seq -w 1 19); do
  mkdir -p "${BASE}/q${q}"
done

# ------------------------------------------------------- Q01 image build files
put_file "${BASE}/q01/Dockerfile" <<'EOF'
FROM nginx:1.27-alpine
COPY index.html /usr/share/nginx/html/index.html
EXPOSE 80
EOF
put_file "${BASE}/q01/index.html" <<'EOF'
<!DOCTYPE html>
<html>
  <head><title>m01-webapp</title></head>
  <body><h1>m01-webapp 1.0</h1></body>
</html>
EOF

# ------------------------------------------- Q05 Deployment for rolling update
info "Q05: Deployment frontend"
apply <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend
  namespace: m01-rollout
  annotations:
    kubernetes.io/change-cause: "initial release nginx:1.27-alpine"
spec:
  replicas: 3
  selector:
    matchLabels:
      app: frontend
  template:
    metadata:
      labels:
        app: frontend
    spec:
      containers:
      - name: nginx
        image: nginx:1.27-alpine
        ports:
        - containerPort: 80
EOF

# --------------------------------------------- Q06 stable version + Service
info "Q06: Deployment checkout-v1 + Service checkout"
apply <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: checkout-v1
  namespace: m01-canary
  labels:
    app: checkout
    version: v1
spec:
  replicas: 8
  selector:
    matchLabels:
      app: checkout
      tier: frontend
      version: v1
  template:
    metadata:
      labels:
        app: checkout
        tier: frontend
        version: v1
    spec:
      containers:
      - name: checkout
        image: nginx:1.27-alpine
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
  namespace: m01-canary
spec:
  selector:
    app: checkout
    tier: frontend
  ports:
  - port: 80
    targetPort: 80
EOF

# ----------------------------------------------------- Q07 local Helm chart
if have helm; then
  if [[ ! -d "${BASE}/q07/shop-chart" || "${RESET:-0}" == "1" ]]; then
    rm -rf "${BASE}/q07/shop-chart"
    helm create "${BASE}/q07/shop-chart" >/dev/null
  fi
  info "Q07: chart ${BASE}/q07/shop-chart ready"
fi

# ------------------------------------------------------- Q08 Kustomize files
put_file "${BASE}/q08/kustomization.yaml" <<'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- deployment.yaml
EOF
put_file "${BASE}/q08/deployment.yaml" <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: notes
  namespace: m01-kustomize
  labels:
    app: notes
spec:
  replicas: 1
  selector:
    matchLabels:
      app: notes
  template:
    metadata:
      labels:
        app: notes
    spec:
      containers:
      - name: notes
        image: nginx:1.27-alpine
        ports:
        - containerPort: 80
EOF
put_file "${BASE}/q08/service.yaml" <<'EOF'
apiVersion: v1
kind: Service
metadata:
  name: notes
  namespace: m01-kustomize
  labels:
    app: notes
spec:
  selector:
    app: notes
  ports:
  - port: 80
    targetPort: 80
EOF

# --------------------------------------------- Q09 Deployment without probes
info "Q09: Deployment api"
apply <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api
  namespace: m01-health
spec:
  replicas: 2
  selector:
    matchLabels:
      app: api
  template:
    metadata:
      labels:
        app: api
    spec:
      containers:
      - name: api
        image: nginx:1.27-alpine
        ports:
        - containerPort: 80
EOF

# ---------------------------------------------- Q10 legacy (broken) manifest
put_file "${BASE}/q10/legacy-deploy.yaml" <<'EOF'
# Written for Kubernetes 1.15. It does not apply on current clusters.
apiVersion: extensions/v1beta1
kind: Deployment
metadata:
  name: legacy-app
  namespace: m01-legacy
  labels:
    app: legacy-app
spec:
  replicas: 2
  template:
    metadata:
      labels:
        app: legacy-app
    spec:
      containers:
      - name: legacy-app
        image: nginx:1.27-alpine
        ports:
        - containerPort: 80
EOF

# ------------------------------------------ Q11 CPU consumers + 2-container Pod
info "Q11: Pods worker-a/b/c and payment"
apply <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: worker-a
  namespace: m01-monitor
  labels:
    app: worker
spec:
  terminationGracePeriodSeconds: 2
  containers:
  - name: worker
    image: busybox:1.36
    command: ["sh", "-c", "while true; do sleep 1; done"]
    resources:
      requests:
        cpu: 10m
      limits:
        cpu: 100m
---
apiVersion: v1
kind: Pod
metadata:
  name: worker-b
  namespace: m01-monitor
  labels:
    app: worker
spec:
  terminationGracePeriodSeconds: 2
  containers:
  - name: worker
    image: busybox:1.36
    command: ["sh", "-c", "while true; do :; done"]   # busy loop, capped by the CPU limit
    resources:
      requests:
        cpu: 10m
      limits:
        cpu: 250m
---
apiVersion: v1
kind: Pod
metadata:
  name: worker-c
  namespace: m01-monitor
  labels:
    app: worker
spec:
  terminationGracePeriodSeconds: 2
  containers:
  - name: worker
    image: busybox:1.36
    command: ["sh", "-c", "while true; do :; done"]
    resources:
      requests:
        cpu: 10m
      limits:
        cpu: 80m
---
apiVersion: v1
kind: Pod
metadata:
  name: payment
  namespace: m01-monitor
  labels:
    app: payment
spec:
  terminationGracePeriodSeconds: 2
  containers:
  - name: app
    image: busybox:1.36
    command:
    - sh
    - -c
    - |
      echo "payment-gateway started"
      echo "note: DENIED transactions are recorded by the audit container"
      while true; do echo "processed batch at $(date +%T)"; sleep 20; done
  - name: audit
    image: busybox:1.36
    command:
    - sh
    - -c
    - |
      echo "AUDIT txn=1001 user=alice result=APPROVED"
      echo "AUDIT txn=1002 user=bob   result=DENIED reason=limit"
      echo "AUDIT txn=1003 user=carol result=APPROVED"
      echo "AUDIT txn=1004 user=dave  result=DENIED reason=fraud-check"
      echo "AUDIT txn=1005 user=erin  result=APPROVED"
      echo "AUDIT txn=1006 user=frank result=DENIED reason=expired-card"
      echo "AUDIT txn=1007 user=grace result=APPROVED"
      sleep 86400
EOF

# -------------------------------------------------- Q12 properties file
put_file "${BASE}/q12/app.properties" <<'EOF'
shop.currency=EUR
shop.max-cart-items=25
shop.payment.provider=sandbox
EOF

# ---------------------------------- Q15 ResourceQuota + Deployment it blocks
info "Q15: ResourceQuota team-quota + Deployment reporting (blocked)"
apply <<'EOF'
apiVersion: v1
kind: ResourceQuota
metadata:
  name: team-quota
  namespace: m01-quota
spec:
  hard:
    requests.cpu: "1"
    requests.memory: 1Gi
    limits.cpu: "2"
    limits.memory: 2Gi
EOF
apply <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: reporting
  namespace: m01-quota
spec:
  replicas: 2
  selector:
    matchLabels:
      app: reporting
  template:
    metadata:
      labels:
        app: reporting
    spec:
      terminationGracePeriodSeconds: 2
      containers:
      - name: reporter
        image: busybox:1.36
        command: ["sh", "-c", "while true; do echo generating report; sleep 30; done"]
EOF

# ------------------------------------------------------------- Q16 the CRD
info "Q16: CRD backups.m01.example.com"
apply <<'EOF'
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: backups.m01.example.com
  labels:
    ckad-mock: exam-01
spec:
  group: m01.example.com
  scope: Namespaced
  names:
    plural: backups
    singular: backup
    kind: Backup
    shortNames:
    - bkp
  versions:
  - name: v1
    served: true
    storage: true
    additionalPrinterColumns:
    - name: Schedule
      type: string
      jsonPath: .spec.schedule
    - name: Retention
      type: integer
      jsonPath: .spec.retentionDays
    - name: Target
      type: string
      jsonPath: .spec.target
    - name: Age
      type: date
      jsonPath: .metadata.creationTimestamp
    schema:
      openAPIV3Schema:
        type: object
        properties:
          spec:
            type: object
            required: ["schedule", "target"]
            properties:
              schedule:
                type: string
                description: Cron expression for the backup run.
              retentionDays:
                type: integer
                minimum: 1
                maximum: 30
                description: How many days backups are kept.
              target:
                type: string
                description: Name of the database to back up.
EOF
kubectl wait --for=condition=Established crd/backups.m01.example.com --timeout=60s >/dev/null

# ------------------------------------------- Q17 Deployment + decoy Deployment
info "Q17: Deployments catalog and catalog-admin"
apply <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: catalog
  namespace: m01-svc
  labels:
    app: catalog
spec:
  replicas: 2
  selector:
    matchLabels:
      app: catalog
      tier: api
  template:
    metadata:
      labels:
        app: catalog
        tier: api
    spec:
      containers:
      - name: catalog
        image: nginx:1.27-alpine
        ports:
        - containerPort: 80
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: catalog-admin
  namespace: m01-svc
  labels:
    app: catalog
spec:
  replicas: 1
  selector:
    matchLabels:
      app: catalog
      tier: admin
  template:
    metadata:
      labels:
        app: catalog
        tier: admin
    spec:
      containers:
      - name: admin
        image: httpd:2.4
        ports:
        - containerPort: 80
EOF

# ------------------------------------------------ Q18 Ingress backends
info "Q18: backends storefront/orders + Services web-svc/api-svc"
apply <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: storefront-conf
  namespace: m01-ingress
data:
  default.conf: |
    server {
      listen 80;
      location / {
        default_type text/plain;
        return 200 "storefront: $request_uri\n";
      }
    }
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: orders-conf
  namespace: m01-ingress
data:
  default.conf: |
    server {
      listen 80;
      location / {
        default_type text/plain;
        return 200 "orders-api: $request_uri\n";
      }
    }
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: storefront
  namespace: m01-ingress
spec:
  replicas: 1
  selector:
    matchLabels:
      app: storefront
  template:
    metadata:
      labels:
        app: storefront
    spec:
      containers:
      - name: nginx
        image: nginx:1.27-alpine
        ports:
        - containerPort: 80
        volumeMounts:
        - name: conf
          mountPath: /etc/nginx/conf.d
      volumes:
      - name: conf
        configMap:
          name: storefront-conf
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: orders
  namespace: m01-ingress
spec:
  replicas: 1
  selector:
    matchLabels:
      app: orders
  template:
    metadata:
      labels:
        app: orders
    spec:
      containers:
      - name: nginx
        image: nginx:1.27-alpine
        ports:
        - containerPort: 80
        volumeMounts:
        - name: conf
          mountPath: /etc/nginx/conf.d
      volumes:
      - name: conf
        configMap:
          name: orders-conf
---
apiVersion: v1
kind: Service
metadata:
  name: web-svc
  namespace: m01-ingress
spec:
  selector:
    app: storefront
  ports:
  - port: 80
    targetPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: api-svc
  namespace: m01-ingress
spec:
  selector:
    app: orders
  ports:
  - port: 8080
    targetPort: 80
EOF

# ------------------------------------------------ Q19 NetworkPolicy targets
info "Q19: Pods frontend/backend/other (+ frontend in m01-netpol-ext)"
apply <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: frontend
  namespace: m01-netpol
  labels:
    app: frontend
spec:
  terminationGracePeriodSeconds: 2
  containers:
  - name: client
    image: busybox:1.36
    command: ["sh", "-c", "sleep 86400"]
---
apiVersion: v1
kind: Pod
metadata:
  name: other
  namespace: m01-netpol
  labels:
    app: other
spec:
  terminationGracePeriodSeconds: 2
  containers:
  - name: client
    image: busybox:1.36
    command: ["sh", "-c", "sleep 86400"]
---
apiVersion: v1
kind: Pod
metadata:
  name: backend
  namespace: m01-netpol
  labels:
    app: backend
spec:
  containers:
  - name: nginx
    image: nginx:1.27-alpine
    ports:
    - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: backend
  namespace: m01-netpol
spec:
  selector:
    app: backend
  ports:
  - port: 80
    targetPort: 80
---
apiVersion: v1
kind: Pod
metadata:
  name: frontend
  namespace: m01-netpol-ext
  labels:
    app: frontend
spec:
  terminationGracePeriodSeconds: 2
  containers:
  - name: client
    image: busybox:1.36
    command: ["sh", "-c", "sleep 86400"]
EOF

# -------------------------------------------------------------------- summary
echo
echo "================= CKAD Mock Exam 01 (Foundations) is ready ================="
echo "Namespaces   : ${NAMESPACES[*]}"
echo "Cluster-wide : crd/backups.m01.example.com"
echo "Input files  : ${BASE}/q01 ... q19 (outputs go there too)"
if (( ${#WARNINGS[@]} > 0 )); then
  echo "Warnings (${#WARNINGS[@]}) - the affected questions can't be completed fully:"
  for w in "${WARNINGS[@]}"; do
    echo "  - ${w}"
  done
else
  echo "Optional components: all detected"
fi
echo "Images are pulling; give the Pods a minute:  kubectl get pods -A | grep '^m01-'"
echo "Start a 120-minute timer and open questions.md. Clean up afterwards: bash cleanup.sh"
