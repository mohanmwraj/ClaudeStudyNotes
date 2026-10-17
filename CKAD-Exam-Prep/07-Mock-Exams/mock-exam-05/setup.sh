#!/usr/bin/env bash
# =============================================================================
# CKAD Mock Exam 05 — Advanced, multi-step — environment setup
#
#   bash setup.sh            create the starting state (safe to re-run)
#   RESET=1 bash setup.sh    same, and also restore the original input files
#
# Creates (and nothing else):
#   - namespaces m05-*                    labelled ckad-mock=exam-05
#   - the pre-existing / intentionally broken objects the questions refer to
#   - input files under ~/ckad-mocks/exam-05/qNN/ (+ ~/ckad-mocks/exam-05/.state/ for grading)
# Re-running re-applies the starting objects; it may undo changes you made to them.
# Remove everything with: bash cleanup.sh
#
# SPOILER WARNING: the comments below describe the faults planted for each question.
# Run this script, but read it only after you have taken the exam.
# =============================================================================
set -euo pipefail

EXAM="exam-05"
LABEL="ckad-mock=${EXAM}"
BASE="${HOME}/ckad-mocks/${EXAM}"
STATE="${BASE}/.state"
LAB_DOC="00-Exam-Overview-and-Setup/02-local-practice-lab-setup.md"
NAMESPACES=(
  m05-canary m05-batch m05-secrets m05-svc m05-oom m05-init m05-helm
  m05-rbac m05-netpol m05-probes m05-storage m05-kustomize m05-quota
  m05-ingress m05-logs m05-crd m05-rollout m05-sec
)
WARNINGS=()
GATEWAY_API=0

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

# make_ns NAME [extra labels...]: idempotent namespace + exam label + wait for the default SA
make_ns() {
  local ns="$1"; shift
  kubectl create namespace "${ns}" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
  kubectl label namespace "${ns}" "${LABEL}" "$@" --overwrite >/dev/null
  local i
  for i in $(seq 1 30); do
    kubectl -n "${ns}" get serviceaccount default >/dev/null 2>&1 && return 0
    sleep 1
  done
  warn "ServiceAccount 'default' did not appear in ${ns}; bare Pods there may be rejected. Re-run setup.sh."
}

# web_app NS NAME REPLICAS BODY [STATUS]: nginx Deployment that answers every request with BODY
web_app() {
  local ns="$1" name="$2" replicas="$3" body="$4" status="${5:-200}"
  apply <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: ${name}-conf
  namespace: ${ns}
data:
  default.conf: |
    server {
      listen 80;
      location / {
        default_type text/plain;
        return ${status} '${body}\n';
      }
    }
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${name}
  namespace: ${ns}
  labels:
    app: ${name}
spec:
  replicas: ${replicas}
  selector:
    matchLabels:
      app: ${name}
  template:
    metadata:
      labels:
        app: ${name}
    spec:
      containers:
      - name: web
        image: nginx:1.27-alpine
        ports:
        - name: http
          containerPort: 80
        volumeMounts:
        - name: conf
          mountPath: /etc/nginx/conf.d
      volumes:
      - name: conf
        configMap:
          name: ${name}-conf
EOF
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
if ! kubectl get ingressclass nginx >/dev/null 2>&1; then
  warn "IngressClass 'nginx' not found: Q14 can be written but not tested end-to-end. See ${LAB_DOC} (section 4a)."
fi

cni_images="$(kubectl get pods -n kube-system -o jsonpath='{.items[*].spec.containers[*].image}' 2>/dev/null || true)"
other_cni="$(kubectl get pods -A -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || true)"
if grep -Eqi 'calico|cilium|antrea|weave|kube-router' <<<"${cni_images} ${other_cni}"; then
  info "NetworkPolicy-capable CNI detected."
elif grep -qi 'kindnet' <<<"${cni_images}"; then
  info "kindnet detected: it enforces NetworkPolicy on kind >= v0.24.0 (older kind versions do not)."
else
  warn "No NetworkPolicy-enforcing CNI detected: the Q9 policy is accepted but may not block traffic. See ${LAB_DOC} (section 4c)."
fi

if kubectl get crd httproutes.gateway.networking.k8s.io gateways.gateway.networking.k8s.io >/dev/null 2>&1; then
  GATEWAY_API=1
else
  warn "Gateway API CRDs not installed: skip the unscored Bonus question (Gateway API is not on the CKAD curriculum; to try it anyway see ${LAB_DOC} section 4d and re-run setup.sh)."
fi

if ! have helm; then
  warn "helm not found: Q7 needs helm and internet access to https://stefanprodan.github.io/podinfo. See ${LAB_DOC} (section 3)."
fi
if ! have podman && ! have docker; then
  warn "Neither podman nor docker found: Q19 (image build) needs one of them. See ${LAB_DOC} (section 2)."
fi

# ---------------------------------------------------------------- namespaces
info "Creating namespaces (label ${LABEL})"
for ns in "${NAMESPACES[@]}"; do make_ns "${ns}"; done
if [[ "${GATEWAY_API}" == "1" ]]; then make_ns m05-gateway; fi

mkdir -p "${STATE}"
for q in $(seq -w 1 19); do mkdir -p "${BASE}/q${q}"; done

# ------------------------------------------------- Q1 canary promotion (m05-canary)
info "Q1  pricing-stable / pricing-canary behind Service pricing"
apply <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: pricing-v1-conf
  namespace: m05-canary
data:
  default.conf: |
    server {
      listen 80;
      location / {
        default_type text/plain;
        return 200 'pricing v1\n';
      }
    }
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: pricing-v2-conf
  namespace: m05-canary
data:
  default.conf: |
    server {
      listen 80;
      location / {
        default_type text/plain;
        return 200 'pricing v2\n';
      }
    }
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: pricing-stable
  namespace: m05-canary
  labels:
    app: pricing
    track: stable
spec:
  replicas: 3
  selector:
    matchLabels:
      app: pricing
      track: stable
  template:
    metadata:
      labels:
        app: pricing
        track: stable
        version: v1
    spec:
      containers:
      - name: web
        image: nginx:1.27-alpine
        ports:
        - name: http
          containerPort: 80
        readinessProbe:
          httpGet:
            path: /
            port: http
          periodSeconds: 5
        volumeMounts:
        - name: conf
          mountPath: /etc/nginx/conf.d
      volumes:
      - name: conf
        configMap:
          name: pricing-v1-conf
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: pricing-canary
  namespace: m05-canary
  labels:
    app: pricing
    track: canary
spec:
  replicas: 1
  selector:
    matchLabels:
      app: pricing
      track: canary
  template:
    metadata:
      labels:
        app: pricing
        track: canary
        version: v2
    spec:
      containers:
      - name: web
        image: nginx:1.27-alpine
        ports:
        - name: http
          containerPort: 80
        readinessProbe:
          httpGet:
            path: /
            port: http
          periodSeconds: 5
        volumeMounts:
        - name: conf
          mountPath: /etc/nginx/conf.d
      volumes:
      - name: conf
        configMap:
          name: pricing-v2-conf
---
apiVersion: v1
kind: Service
metadata:
  name: pricing
  namespace: m05-canary
spec:
  selector:
    app: pricing          # matches stable AND canary Pods
  ports:
  - name: http
    port: 80
    targetPort: http
EOF
# remember the Service's resourceVersion so the solution can prove "not modified"
kubectl -n m05-canary get service pricing -o jsonpath='{.metadata.resourceVersion}' >"${STATE}/q01-svc-rv"

# ------------------------------------------------- Q2 Indexed Job input (m05-batch)
info "Q2  shard list file"
put_file "${BASE}/q02/shards.txt" <<'EOF'
eu-west
us-east
ap-south
sa-east
EOF

# ------------------------------------------------- Q3 Secret env file (m05-secrets)
info "Q3  merchant.env"
put_file "${BASE}/q03/merchant.env" <<'EOF'
API_KEY=pk_m05_7f3a9c
DB_PASSWORD=Sup3r-S3cret-m05
TLS_PIN=sha256-m05-9d8c7b
EOF

# ------------------------------------------------- Q4 named targetPort mismatch (m05-svc)
info "Q4  billing (named port mismatch) + client Pod"
apply <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: billing
  namespace: m05-svc
  labels:
    app: billing
spec:
  replicas: 2
  selector:
    matchLabels:
      app: billing
  template:
    metadata:
      labels:
        app: billing
    spec:
      containers:
      - name: web
        image: nginx:1.27-alpine
        ports:
        - name: web-http        # BROKEN on purpose: the Service targets the port name "http"
          containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: billing
  namespace: m05-svc
spec:
  selector:
    app: billing
  ports:
  - name: http
    port: 80
    targetPort: http            # named target port - the contract other teams rely on
---
apiVersion: v1
kind: Pod
metadata:
  name: client
  namespace: m05-svc
  labels:
    app: client
spec:
  containers:
  - name: client
    image: busybox:1.36
    command: ["sh", "-c", "sleep 86400"]
EOF
kubectl -n m05-svc get service billing -o jsonpath='{.metadata.resourceVersion}' >"${STATE}/q04-svc-rv"

# ------------------------------------------------- Q5 OOMKilled worker (m05-oom)
info "Q5  thumbnailer (memory limit too low)"
apply <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: thumbnailer
  namespace: m05-oom
  labels:
    app: thumbnailer
spec:
  replicas: 1
  selector:
    matchLabels:
      app: thumbnailer
  template:
    metadata:
      labels:
        app: thumbnailer
    spec:
      containers:
      - name: resizer
        image: busybox:1.36
        command: ["sh", "-c"]
        args:
        - |
          echo "thumbnailer: loading image cache"
          cache=$(yes 0123456789abcdef | head -c 40000000)
          echo "thumbnailer: cache ready"
          while true; do sleep 30; done
        resources:
          requests:
            cpu: 50m
            memory: 16Mi
          limits:
            cpu: 500m
            memory: 32Mi        # BROKEN on purpose: the cache needs ~40-80 MiB
EOF

# ------------------------------------------------- Q6 database without a Service (m05-init)
info "Q6  db Deployment (no Service yet)"
apply <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: db
  namespace: m05-init
  labels:
    app: db
spec:
  replicas: 1
  selector:
    matchLabels:
      app: db
  template:
    metadata:
      labels:
        app: db
    spec:
      containers:
      - name: postgres
        image: postgres:16
        env:
        - name: POSTGRES_PASSWORD
          value: m05-lab-only     # lab only - real workloads take this from a Secret
        ports:
        - name: postgres
          containerPort: 5432
EOF

# ------------------------------------------------- Q8 RBAC targets (m05-rbac)
info "Q8  app-1 / app-2 Pods + can-i.txt"
apply <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: app-1
  namespace: m05-rbac
  labels:
    app: demo
spec:
  containers:
  - name: app
    image: busybox:1.36
    command: ["sh", "-c", "while true; do echo \"$(date) app-1 heartbeat\"; sleep 5; done"]
---
apiVersion: v1
kind: Pod
metadata:
  name: app-2
  namespace: m05-rbac
  labels:
    app: demo
spec:
  containers:
  - name: app
    image: busybox:1.36
    command: ["sh", "-c", "while true; do echo \"$(date) app-2 heartbeat\"; sleep 5; done"]
EOF
put_file "${BASE}/q08/can-i.txt" <<'EOF'
get pods app-1 =
get pods app-2 =
get pods/log app-1 =
get pods/log app-2 =
create pods/exec app-1 =
list pods =
delete pods app-1 =
EOF

# ------------------------------------------------- Q9 egress policy (m05-netpol)
info "Q9  api / db / cache Pods + a permissive legacy NetworkPolicy"
apply <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: api
  namespace: m05-netpol
  labels:
    app: api
spec:
  containers:
  - name: api
    image: busybox:1.36
    command: ["sh", "-c", "sleep 86400"]
---
apiVersion: v1
kind: Pod
metadata:
  name: db
  namespace: m05-netpol
  labels:
    app: db
spec:
  containers:
  - name: postgres
    image: postgres:16
    env:
    - name: POSTGRES_PASSWORD
      value: m05-lab-only
    ports:
    - containerPort: 5432
---
apiVersion: v1
kind: Pod
metadata:
  name: cache
  namespace: m05-netpol
  labels:
    app: cache
spec:
  containers:
  - name: redis
    image: redis:7.2
    ports:
    - containerPort: 6379
---
apiVersion: v1
kind: Service
metadata:
  name: db
  namespace: m05-netpol
spec:
  selector:
    app: db
  ports:
  - port: 5432
    targetPort: 5432
---
apiVersion: v1
kind: Service
metadata:
  name: cache
  namespace: m05-netpol
spec:
  selector:
    app: cache
  ports:
  - port: 6379
    targetPort: 6379
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-all-egress          # TRAP: selects every Pod and allows all egress
  namespace: m05-netpol
spec:
  podSelector: {}
  policyTypes:
  - Egress
  egress:
  - {}
EOF

# ------------------------------------------------- Q10 slow start vs. liveness (m05-probes)
info "Q10 session-store (liveness kills it during start-up)"
apply <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: session-store
  namespace: m05-probes
  labels:
    app: session-store
spec:
  replicas: 1
  selector:
    matchLabels:
      app: session-store
  template:
    metadata:
      labels:
        app: session-store
    spec:
      containers:
      - name: redis
        image: redis:7.2
        command: ["sh", "-c"]
        args: ["echo 'session-store warming up (40s)'; sleep 40; exec redis-server"]
        ports:
        - containerPort: 6379
        livenessProbe:            # BROKEN on purpose: fails before Redis is up
          exec:
            command: ["redis-cli", "ping"]
          initialDelaySeconds: 5
          periodSeconds: 5
          failureThreshold: 3
EOF

# ------------------------------------------------- Q12 kustomization (m05-kustomize)
info "Q12 warehouse kustomization (files + applied objects)"
put_file "${BASE}/q12/kustomization.yaml" <<'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: m05-kustomize
resources:
- deployment.yaml
- service.yaml
EOF
put_file "${BASE}/q12/deployment.yaml" <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: warehouse
  labels:
    app: warehouse
spec:
  replicas: 1
  selector:
    matchLabels:
      app: warehouse
  template:
    metadata:
      labels:
        app: warehouse
    spec:
      containers:
      - name: api
        image: nginx:1.27-alpine
        ports:
        - containerPort: 80
EOF
put_file "${BASE}/q12/service.yaml" <<'EOF'
apiVersion: v1
kind: Service
metadata:
  name: warehouse
  labels:
    app: warehouse
spec:
  selector:
    app: warehouse
  ports:
  - port: 80
    targetPort: 80
EOF
# the starting state "was applied earlier" (selectors are now immutable in the cluster)
apply <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: warehouse
  namespace: m05-kustomize
  labels:
    app: warehouse
spec:
  replicas: 1
  selector:
    matchLabels:
      app: warehouse
  template:
    metadata:
      labels:
        app: warehouse
    spec:
      containers:
      - name: api
        image: nginx:1.27-alpine
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: warehouse
  namespace: m05-kustomize
  labels:
    app: warehouse
spec:
  selector:
    app: warehouse
  ports:
  - port: 80
    targetPort: 80
EOF

# ------------------------------------------------- Q13 LimitRange + quota (m05-quota)
info "Q13 analytics vs. LimitRange + ResourceQuota"
apply <<'EOF'
apiVersion: v1
kind: LimitRange
metadata:
  name: container-limits
  namespace: m05-quota
spec:
  limits:
  - type: Container
    max:
      cpu: 500m
      memory: 256Mi
    default:
      cpu: 200m
      memory: 128Mi
    defaultRequest:
      cpu: 100m
      memory: 64Mi
---
apiVersion: v1
kind: ResourceQuota
metadata:
  name: team-quota
  namespace: m05-quota
spec:
  hard:
    requests.cpu: "1"
    requests.memory: 512Mi
    limits.cpu: "2"
    limits.memory: 1Gi
    pods: "6"
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: analytics
  namespace: m05-quota
  labels:
    app: analytics
spec:
  replicas: 3
  selector:
    matchLabels:
      app: analytics
  template:
    metadata:
      labels:
        app: analytics
    spec:
      containers:
      - name: etl
        image: nginx:1.27-alpine
        resources:
          limits:               # no requests: the API server copies limits into requests
            cpu: 300m
            memory: 512Mi       # BROKEN on purpose: above the LimitRange max of 256Mi
EOF

# ------------------------------------------------- Q14 Ingress backends (m05-ingress)
info "Q14 docs / status-api / fallback backends"
web_app m05-ingress docs 1 'docs: ok'
web_app m05-ingress status-api 1 'status-api: ok'
web_app m05-ingress fallback 1 'fallback: no route' 404
apply <<'EOF'
apiVersion: v1
kind: Service
metadata:
  name: docs
  namespace: m05-ingress
spec:
  selector:
    app: docs
  ports:
  - port: 80
    targetPort: http
---
apiVersion: v1
kind: Service
metadata:
  name: status-api
  namespace: m05-ingress
spec:
  selector:
    app: status-api
  ports:
  - name: http
    port: 8080
    targetPort: http
---
apiVersion: v1
kind: Service
metadata:
  name: fallback
  namespace: m05-ingress
spec:
  selector:
    app: fallback
  ports:
  - port: 80
    targetPort: http
EOF

# ------------------------------------------------- Q15 logs, events, legacy API (m05-logs)
info "Q15 dispatch (2 containers), an event generator, legacy PriorityClass file"
apply <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: dispatch
  namespace: m05-logs
  labels:
    app: dispatch
spec:
  replicas: 2
  selector:
    matchLabels:
      app: dispatch
  template:
    metadata:
      labels:
        app: dispatch
    spec:
      containers:
      - name: router
        image: busybox:1.36
        command: ["sh", "-c", "while true; do echo \"$(date +%T) router: dispatched order $RANDOM\"; sleep 2; done"]
      - name: auditor
        image: busybox:1.36
        command: ["sh", "-c", "while true; do echo \"$(date +%T) auditor: queue depth $((RANDOM % 50))\"; sleep 3; done"]
---
apiVersion: v1
kind: Pod
metadata:
  name: probe-flapper
  namespace: m05-logs
  labels:
    app: probe-flapper
spec:
  containers:
  - name: web
    image: busybox:1.36
    command: ["sh", "-c", "mkdir -p /tmp/www && echo ok > /tmp/www/index.html && exec httpd -f -p 8080 -h /tmp/www"]
    readinessProbe:               # fails forever -> produces Warning events
      tcpSocket:
        port: 9999
      periodSeconds: 10
EOF
put_file "${BASE}/q15/priorityclass.yaml" <<'EOF'
apiVersion: scheduling.k8s.io/v1beta1
kind: PriorityClass
metadata:
  name: m05-batch-critical
  labels:
    ckad-mock: exam-05
value: 100000
globalDefault: false
description: "Batch jobs that must not be preempted by best-effort work"
EOF

# ------------------------------------------------- Q16 CR that must be rejected (m05-crd)
info "Q16 too-long.yaml"
put_file "${BASE}/q16/too-long.yaml" <<'EOF'
apiVersion: ops.m05.ckad.io/v1
kind: MaintenanceWindow
metadata:
  name: marathon
  namespace: m05-crd
spec:
  start: "0 1 * * 0"
  durationMinutes: 480
  mode: drain
EOF

# ------------------------------------------------- Q17 stalled rollout (m05-rollout)
if kubectl -n m05-rollout get deployment quotes >/dev/null 2>&1; then
  info "Q17 quotes already exists - keeping its rollout history"
else
  info "Q17 quotes: revision 1 (good), then revision 2 (never becomes ready)"
  apply <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: quotes
  namespace: m05-rollout
  labels:
    app: quotes
  annotations:
    kubernetes.io/change-cause: "v1: initial release"
spec:
  replicas: 3
  selector:
    matchLabels:
      app: quotes
  template:
    metadata:
      labels:
        app: quotes
    spec:
      containers:
      - name: web
        image: nginx:1.27-alpine
        ports:
        - name: http
          containerPort: 80
        readinessProbe:
          httpGet:
            path: /
            port: http
          periodSeconds: 5
EOF
  kubectl -n m05-rollout rollout status deployment/quotes --timeout=180s >/dev/null 2>&1 \
    || warn "quotes revision 1 is not fully ready yet (slow image pull?); Q17 still works."
  apply <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: quotes
  namespace: m05-rollout
  labels:
    app: quotes
  annotations:
    kubernetes.io/change-cause: "v2: release 2.0"
spec:
  replicas: 3
  selector:
    matchLabels:
      app: quotes
  template:
    metadata:
      labels:
        app: quotes
    spec:
      containers:
      - name: web
        image: nginx:1.27-alpine
        env:
        - name: RELEASE
          value: "2.0"
        ports:
        - name: http
          containerPort: 80
        readinessProbe:
          httpGet:
            path: /healthz        # BROKEN on purpose: nginx answers 404 here
            port: http
          periodSeconds: 5
EOF
fi

# ------------------------------------------------- Q19 image build input (local)
info "Q19 Dockerfile + greet.sh"
put_file "${BASE}/q19/Dockerfile" <<'EOF'
FROM busybox:1.35
COPY greet.sh /usr/local/bin/greet.sh
ENTRYPOINT ["/bin/sh", "/usr/local/bin/greet.sh"]
CMD ["world"]
EOF
put_file "${BASE}/q19/greet.sh" <<'EOF'
#!/bin/sh
echo "${GREETING:-Hello}, ${1:-nobody}! (build ${BUILD_ID:-dev}, uid $(id -u))"
EOF

# ------------------------------------------------- Bonus Gateway API (m05-gateway)
if [[ "${GATEWAY_API}" == "1" ]]; then
  info "Bonus rates-v1 / rates-v2 + Gateway m05-gateway"
  web_app m05-gateway rates-v1 1 'rates v1'
  web_app m05-gateway rates-v2 1 'rates v2'
  apply <<'EOF'
apiVersion: v1
kind: Service
metadata:
  name: rates-v1
  namespace: m05-gateway
spec:
  selector:
    app: rates-v1
  ports:
  - port: 80
    targetPort: http
---
apiVersion: v1
kind: Service
metadata:
  name: rates-v2
  namespace: m05-gateway
spec:
  selector:
    app: rates-v2
  ports:
  - port: 80
    targetPort: http
EOF
  gw_class="$(kubectl get gatewayclass -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
  if [[ -z "${gw_class}" ]]; then
    gw_class="m05-no-implementation"
    warn "No GatewayClass found: Gateway m05-gateway is created but nothing will program it (the bonus is graded on the HTTPRoute spec)."
  fi
  apply <<EOF
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: m05-gateway
  namespace: m05-gateway
spec:
  gatewayClassName: ${gw_class}
  listeners:
  - name: http
    protocol: HTTP
    port: 80
    allowedRoutes:
      namespaces:
        from: Same
EOF
fi

# ------------------------------------------------------------------- summary
echo
echo "======================================================================"
echo " CKAD Mock Exam 05 is ready."
echo "   Namespaces : ${NAMESPACES[*]}$([[ "${GATEWAY_API}" == "1" ]] && echo " m05-gateway")"
echo "   Files      : ${BASE}/q01 ... q19 (existing files kept; RESET=1 restores them)"
echo "   Ingress    : kit lab (kind) -> http://localhost:8080 ; minikube -> http://\$(minikube ip)"
echo "                any cluster   -> kubectl -n ingress-nginx port-forward svc/ingress-nginx-controller 8080:80"
echo "   Images are still being pulled for a minute or two - that is normal."
if (( ${#WARNINGS[@]} > 0 )); then
  echo "   ${#WARNINGS[@]} warning(s):"
  for w in "${WARNINGS[@]}"; do echo "     - ${w}"; done
else
  echo "   No warnings."
fi
echo " Start your 120-minute timer now. Questions: questions.md"
echo "======================================================================"
