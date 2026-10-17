#!/usr/bin/env bash
# =============================================================================
# CKAD Mock Exam 02 — Foundations+ — environment setup
#
#   bash setup.sh            create the starting state (safe to re-run)
#   RESET=1 bash setup.sh    same, and also restore the original input files
#
# Creates (and nothing else):
#   - namespaces m02-*                         labelled ckad-mock=exam-02
#   - CRDs databases/caches.m02.example.com    labelled ckad-mock=exam-02
#   - Helm release m02-legacy in m02-tools     (only if helm is installed)
#   - the pre-existing / intentionally broken objects the questions refer to
#   - input files under ~/ckad-mocks/exam-02/qNN/
# Re-running re-applies the starting objects; it may undo changes you made to them.
# For a completely fresh start run cleanup.sh first. Remove everything with: bash cleanup.sh
# =============================================================================
set -euo pipefail

EXAM="exam-02"
LABEL="ckad-mock=${EXAM}"
BASE="${HOME}/ckad-mocks/${EXAM}"
LAB_DOC="00-Exam-Overview-and-Setup/02-local-practice-lab-setup.md"
NAMESPACES=(
  m02-jobs m02-init m02-convert m02-bluegreen m02-strategy m02-prod
  m02-helm m02-tools m02-probes m02-debug m02-pdb m02-crd
  m02-config m02-secret m02-guard m02-svc m02-netpol m02-ingress
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
  warn "metrics-server is not available: Q12 ('kubectl top nodes') cannot be solved yet. See ${LAB_DOC} (section 4b)."
fi

ingress_classes="$(kubectl get ingressclass -o name 2>/dev/null || true)"
if [[ -z "${ingress_classes}" ]]; then
  warn "No IngressClass found: Q19 can be fixed but not tested end-to-end. Install ingress-nginx - see ${LAB_DOC} (section 4a)."
fi

cni_images="$(kubectl get pods -n kube-system -o jsonpath='{.items[*].spec.containers[*].image}' 2>/dev/null || true)"
if grep -Eqi 'calico|cilium|antrea|weave|kube-router' <<<"${cni_images}"; then
  info "NetworkPolicy-capable CNI detected."
elif grep -qi 'kindnet' <<<"${cni_images}"; then
  info "kindnet detected: it enforces NetworkPolicy on kind >= v0.24.0 (older kind versions do not)."
else
  warn "No NetworkPolicy-enforcing CNI detected: Q18 policies are accepted but may not block traffic. See ${LAB_DOC} (section 4c)."
fi

if ! have helm; then
  warn "helm not found: Q8 needs it (its chart is generated with 'helm create' and a release is pre-installed). Install Helm, then re-run setup.sh. See ${LAB_DOC} (section 3)."
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

# ---------------------------------------------- Q01 Dockerfile to be modified
put_file "${BASE}/q01/Dockerfile" <<'EOF'
FROM busybox:1.35
ENV APP_ENV=dev
WORKDIR /app
COPY report.sh /app/report.sh
CMD ["sh", "/app/report.sh"]
EOF
put_file "${BASE}/q01/report.sh" <<'EOF'
#!/bin/sh
echo "report generator: env=${APP_ENV} uid=$(id -u)"
EOF

# ------------------------------------------------------------ Q04 bare Pod
info "Q04: bare Pod inventory"
apply <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: inventory
  namespace: m02-convert
  labels:
    app: inventory
    tier: backend
spec:
  containers:
  - name: inventory
    image: nginx:1.27-alpine
    env:
    - name: INVENTORY_MODE
      value: "readonly"
    ports:
    - containerPort: 80
    resources:
      requests:
        cpu: 50m
        memory: 64Mi
EOF

# ---------------------------------------------------- Q05 blue/green objects
info "Q05: store-blue (3), store-green (0), Service store -> blue"
apply <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: store-blue-html
  namespace: m02-bluegreen
data:
  index.html: |
    store version: blue
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: store-green-html
  namespace: m02-bluegreen
data:
  index.html: |
    store version: green
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: store-blue
  namespace: m02-bluegreen
  labels:
    app: store
    version: blue
spec:
  replicas: 3
  selector:
    matchLabels:
      app: store
      version: blue
  template:
    metadata:
      labels:
        app: store
        version: blue
    spec:
      containers:
      - name: store
        image: nginx:1.27-alpine
        ports:
        - containerPort: 80
        readinessProbe:
          httpGet:
            path: /
            port: 80
        volumeMounts:
        - name: html
          mountPath: /usr/share/nginx/html
      volumes:
      - name: html
        configMap:
          name: store-blue-html
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: store-green
  namespace: m02-bluegreen
  labels:
    app: store
    version: green
spec:
  replicas: 0
  selector:
    matchLabels:
      app: store
      version: green
  template:
    metadata:
      labels:
        app: store
        version: green
    spec:
      containers:
      - name: store
        image: nginx:1.27-alpine
        ports:
        - containerPort: 80
        readinessProbe:
          httpGet:
            path: /
            port: 80
        volumeMounts:
        - name: html
          mountPath: /usr/share/nginx/html
      volumes:
      - name: html
        configMap:
          name: store-green-html
---
apiVersion: v1
kind: Service
metadata:
  name: store
  namespace: m02-bluegreen
spec:
  selector:
    app: store
    version: blue
  ports:
  - port: 80
    targetPort: 80
EOF

# --------------------------------------------- Q06 Deployments with defaults
info "Q06: Deployments catalog and ledger"
apply <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: catalog
  namespace: m02-strategy
spec:
  replicas: 4
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
        image: nginx:1.27-alpine
        ports:
        - containerPort: 80
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ledger
  namespace: m02-strategy
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ledger
  template:
    metadata:
      labels:
        app: ledger
    spec:
      terminationGracePeriodSeconds: 2
      containers:
      - name: ledger
        image: busybox:1.36
        command:
        - sh
        - -c
        - while true; do echo "ledger running mode=${LEDGER_MODE:-default}"; sleep 10; done
EOF

# ------------------------------------------------------- Q07 Kustomize base
put_file "${BASE}/q07/base/kustomization.yaml" <<'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- deployment.yaml
- service.yaml
EOF
put_file "${BASE}/q07/base/deployment.yaml" <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api
  labels:
    app: api
spec:
  replicas: 1
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
put_file "${BASE}/q07/base/service.yaml" <<'EOF'
apiVersion: v1
kind: Service
metadata:
  name: api
  labels:
    app: api
spec:
  selector:
    app: api
  ports:
  - port: 80
    targetPort: 80
EOF
mkdir -p "${BASE}/q07/overlays/prod"

# --------------------------------------- Q08 local chart + an old release
if have helm; then
  if [[ ! -d "${BASE}/q08/webapp" || "${RESET:-0}" == "1" ]]; then
    rm -rf "${BASE}/q08/webapp"
    helm create "${BASE}/q08/webapp" >/dev/null
  fi
  if helm upgrade --install m02-legacy "${BASE}/q08/webapp" -n m02-tools \
       --set image.tag=1.27-alpine >/dev/null; then
    info "Q08: chart ${BASE}/q08/webapp ready, release m02-legacy installed"
  else
    warn "Could not install Helm release m02-legacy: Q8's first step will have nothing to uninstall."
  fi
fi

# ------------------------------------- Q09 slow app killed by its liveness probe
info "Q09: Deployment slow-app (restart loop)"
apply <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: slow-app
  namespace: m02-probes
spec:
  replicas: 1
  selector:
    matchLabels:
      app: slow-app
  template:
    metadata:
      labels:
        app: slow-app
    spec:
      terminationGracePeriodSeconds: 2
      containers:
      - name: app
        image: busybox:1.36
        command:
        - sh
        - -c
        - |
          echo "warming up caches (about 60s)..."
          sleep 60
          mkdir -p /www && echo "slow-app ready" > /www/index.html
          echo "serving on :8080"
          exec httpd -f -p 8080 -h /www
        ports:
        - name: http
          containerPort: 8080
        livenessProbe:
          httpGet:
            path: /
            port: 8080
          periodSeconds: 10
          failureThreshold: 3
EOF

# -------------------------------------------- Q10 CrashLoopBackOff (bad path)
info "Q10: Deployment ticker (CrashLoopBackOff)"
apply <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: ticker-script
  namespace: m02-debug
data:
  ticker.sh: |
    #!/bin/sh
    echo "ticker started"
    while true; do
      echo "tick $(date +%T)"
      sleep 5
    done
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ticker
  namespace: m02-debug
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
      terminationGracePeriodSeconds: 2
      containers:
      - name: ticker
        image: busybox:1.36
        command: ["sh", "-c", "echo 'booting ticker v2'; exec sh /opt/ticker/tick.sh"]
        volumeMounts:
        - name: script
          mountPath: /opt/ticker
      volumes:
      - name: script
        configMap:
          name: ticker-script
EOF

# --------------------------------------- Q11 Deployment + deprecated PDB file
info "Q11: Deployment web (3 replicas)"
apply <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web
  namespace: m02-pdb
spec:
  replicas: 3
  selector:
    matchLabels:
      app: web
  template:
    metadata:
      labels:
        app: web
    spec:
      containers:
      - name: nginx
        image: nginx:1.27-alpine
        ports:
        - containerPort: 80
EOF
put_file "${BASE}/q11/pdb.yaml" <<'EOF'
# PodDisruptionBudget for Deployment web, written for Kubernetes 1.20
apiVersion: policy/v1beta1
kind: PodDisruptionBudget
metadata:
  name: web-pdb
  namespace: m02-pdb
spec:
  minAvailable: 2
  selector:
    matchLabels:
      app: web
EOF

# ------------------------------------------------------------ Q13 two CRDs
info "Q13: CRDs databases.m02.example.com and caches.m02.example.com"
apply <<'EOF'
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: databases.m02.example.com
  labels:
    ckad-mock: exam-02
spec:
  group: m02.example.com
  scope: Namespaced
  names:
    plural: databases
    singular: database
    kind: Database
    shortNames:
    - mdb
  versions:
  - name: v1alpha1
    served: true
    storage: true
    additionalPrinterColumns:
    - name: Engine
      type: string
      jsonPath: .spec.engine
    - name: Version
      type: string
      jsonPath: .spec.version
    - name: Storage-GB
      type: integer
      jsonPath: .spec.storageGB
    - name: Age
      type: date
      jsonPath: .metadata.creationTimestamp
    schema:
      openAPIV3Schema:
        type: object
        properties:
          spec:
            type: object
            required: ["engine", "version"]
            properties:
              engine:
                type: string
                enum: ["postgres", "mysql"]
              version:
                type: string
                description: Engine version as a string, e.g. "16".
              storageGB:
                type: integer
                minimum: 1
---
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: caches.m02.example.com
  labels:
    ckad-mock: exam-02
spec:
  group: m02.example.com
  scope: Namespaced
  names:
    plural: caches
    singular: cache
    kind: Cache
    shortNames:
    - mch
  versions:
  - name: v1alpha1
    served: true
    storage: true
    schema:
      openAPIV3Schema:
        type: object
        properties:
          spec:
            type: object
            properties:
              engine:
                type: string
                enum: ["redis", "memcached"]
              sizeMB:
                type: integer
                minimum: 16
EOF
kubectl wait --for=condition=Established crd/databases.m02.example.com crd/caches.m02.example.com --timeout=60s >/dev/null

# ----------------------------------------- Q14 ConfigMap consumed via envFrom
info "Q14: ConfigMap api-settings + Deployment api"
apply <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: api-settings
  namespace: m02-config
data:
  LOG_LEVEL: info
  CACHE_TTL: "60"
  DB_POOL_SIZE: "10"
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api
  namespace: m02-config
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
      terminationGracePeriodSeconds: 2
      containers:
      - name: api
        image: busybox:1.36
        command:
        - sh
        - -c
        - while true; do echo "LOG_LEVEL=${LOG_LEVEL} CACHE_TTL=${CACHE_TTL} DB_POOL_SIZE=${DB_POOL_SIZE}"; sleep 10; done
        envFrom:
        - configMapRef:
            name: api-settings
EOF

# ------------------------------------------------------- Q15 Secret source file
put_file "${BASE}/q15/api-key.txt" <<'EOF'
ckad-m02-7f3a9c1e5b
EOF

# ----------------------------------------------- Q16 Pod manifest that violates baseline
put_file "${BASE}/q16/tools-pod.yaml" <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: tools
  namespace: m02-guard
spec:
  hostPID: true
  containers:
  - name: tools
    image: busybox:1.36
    command: ["sh", "-c", "sleep 3600"]
    securityContext:
      privileged: true
EOF

# ---------------------------------------------- Q17 broken Service + decoy Pods
info "Q17: Deployments ledger-api / ledger-worker, broken Service ledger, Pod client"
apply <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ledger-api
  namespace: m02-svc
spec:
  replicas: 2
  selector:
    matchLabels:
      app: ledger
      component: api
  template:
    metadata:
      labels:
        app: ledger
        component: api
    spec:
      terminationGracePeriodSeconds: 2
      containers:
      - name: api
        image: busybox:1.36
        command: ["sh", "-c", "mkdir -p /www && echo 'ledger-api OK' > /www/index.html && exec httpd -f -p 8080 -h /www"]
        ports:
        - name: http
          containerPort: 8080
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ledger-worker
  namespace: m02-svc
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ledger
      component: worker
  template:
    metadata:
      labels:
        app: ledger
        component: worker
    spec:
      terminationGracePeriodSeconds: 2
      containers:
      - name: worker
        image: busybox:1.36
        command: ["sh", "-c", "while true; do echo reconciling ledger; sleep 30; done"]
---
apiVersion: v1
kind: Service
metadata:
  name: ledger
  namespace: m02-svc
spec:
  selector:
    app: ledger-api
  ports:
  - port: 80
    targetPort: 80
---
apiVersion: v1
kind: Pod
metadata:
  name: client
  namespace: m02-svc
  labels:
    app: client
spec:
  terminationGracePeriodSeconds: 2
  containers:
  - name: client
    image: busybox:1.36
    command: ["sh", "-c", "sleep 86400"]
EOF

# ----------------------------------------------- Q18 Pods to lock down
info "Q18: Pods web and client, Service web"
apply <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: web
  namespace: m02-netpol
  labels:
    app: web
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
  name: web
  namespace: m02-netpol
spec:
  selector:
    app: web
  ports:
  - port: 80
    targetPort: 80
---
apiVersion: v1
kind: Pod
metadata:
  name: client
  namespace: m02-netpol
  labels:
    app: client
spec:
  terminationGracePeriodSeconds: 2
  containers:
  - name: client
    image: busybox:1.36
    command: ["sh", "-c", "sleep 86400"]
EOF

# ------------------------------------------------------ Q19 broken Ingress
info "Q19: docs app, Service docs-svc, broken Ingress docs-ingress"
apply <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: docs-html
  namespace: m02-ingress
data:
  index.html: |
    m02 docs portal
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: docs
  namespace: m02-ingress
spec:
  replicas: 1
  selector:
    matchLabels:
      app: docs
  template:
    metadata:
      labels:
        app: docs
    spec:
      containers:
      - name: nginx
        image: nginx:1.27-alpine
        ports:
        - containerPort: 80
        volumeMounts:
        - name: html
          mountPath: /usr/share/nginx/html
      volumes:
      - name: html
        configMap:
          name: docs-html
---
apiVersion: v1
kind: Service
metadata:
  name: docs-svc
  namespace: m02-ingress
spec:
  selector:
    app: docs
  ports:
  - name: http
    port: 8080
    targetPort: 80
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: docs-ingress
  namespace: m02-ingress
spec:
  ingressClassName: nginx-internal
  rules:
  - host: docs.m02.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: docs
            port:
              number: 80
EOF

# -------------------------------------------------------------------- summary
echo
echo "================ CKAD Mock Exam 02 (Foundations+) is ready ================"
echo "Namespaces   : ${NAMESPACES[*]}"
echo "Cluster-wide : crd/databases.m02.example.com, crd/caches.m02.example.com"
if have helm; then
  echo "Helm         : release m02-legacy (namespace hidden on purpose - see Q8)"
fi
echo "Input files  : ${BASE}/q01 ... q19 (outputs go there too)"
if (( ${#WARNINGS[@]} > 0 )); then
  echo "Warnings (${#WARNINGS[@]}) - the affected questions can't be completed fully:"
  for w in "${WARNINGS[@]}"; do
    echo "  - ${w}"
  done
else
  echo "Optional components: all detected"
fi
echo "Some objects are broken on purpose (Q9, Q10, Q17, Q19). Give the Pods a minute to pull images."
echo "Start a 120-minute timer and open questions.md. Clean up afterwards: bash cleanup.sh"
