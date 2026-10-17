#!/usr/bin/env bash
# =============================================================================
# CKAD Mock Exam 06 — Final boss — environment setup
#
#   bash setup.sh            create the starting state (safe to re-run)
#   RESET=1 bash setup.sh    same, and also restore the original input files
#
# Creates (and nothing else):
#   - namespaces m06-*                         labelled ckad-mock=exam-06
#   - CRDs featureflags.flags.m06.ckad.io + flagsets.flags.m06.ckad.io (CRD names must be
#     <plural>.<group>, so they carry "m06" in the group) labelled ckad-mock=exam-06
#   - ClusterRoles/ClusterRoleBindings m06-flag-operator, m06-flag-viewer (same label)
#   - Helm releases portal (m06-helm, 2 revisions) and portal-old (m06-legacy) if helm exists
#   - the pre-existing / intentionally broken objects the questions refer to
#   - input files under ~/ckad-mocks/exam-06/qNN/ (+ ~/ckad-mocks/exam-06/.state/ for grading)
# Re-running re-applies the starting objects; it may undo changes you made to them.
# Helm releases are only installed when missing. For a full reset: bash cleanup.sh && bash setup.sh
#
# SPOILER WARNING: the comments below describe the faults planted for each question.
# Run this script, but read it only after you have taken the exam.
# =============================================================================
set -euo pipefail

EXAM="exam-06"
LABEL="ckad-mock=${EXAM}"
BASE="${HOME}/ckad-mocks/${EXAM}"
STATE="${BASE}/.state"
LAB_DOC="00-Exam-Overview-and-Setup/02-local-practice-lab-setup.md"
NAMESPACES=(
  m06-fleet m06-pipeline m06-helm m06-legacy m06-cron m06-netpol m06-partners m06-others
  m06-apis m06-sts m06-dev m06-prod m06-hpa m06-shop m06-config m06-rollout m06-psa
  m06-bluegreen m06-flags-system m06-team-a m06-team-b m06-build
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

# web_app NS NAME REPLICAS BODY: nginx Deployment that answers every request with BODY
web_app() {
  local ns="$1" name="$2" replicas="$3" body="$4"
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
        return 200 '${body}\n';
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

# sleeper NS NAME LABELKEY LABELVALUE: a busybox Pod that just waits (test client)
sleeper() {
  apply <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: $2
  namespace: $1
  labels:
    $3: $4
spec:
  containers:
  - name: shell
    image: busybox:1.36
    command: ["sh", "-c", "sleep 86400"]
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
metrics_ok="$(kubectl get apiservice v1beta1.metrics.k8s.io \
  -o jsonpath='{.status.conditions[?(@.type=="Available")].status}' 2>/dev/null || true)"
if [[ "${metrics_ok}" != "True" ]]; then
  warn "metrics-server is not available: Q13 ('kubectl top') cannot be solved yet. See ${LAB_DOC} (section 4b)."
fi

if ! kubectl get ingressclass nginx >/dev/null 2>&1; then
  warn "IngressClass 'nginx' not found: Q10 and Q15 can be written but not tested end-to-end. See ${LAB_DOC} (section 4a)."
fi
if ! kubectl get namespace ingress-nginx >/dev/null 2>&1; then
  warn "Namespace 'ingress-nginx' not found: in Q10, allow the namespace your ingress controller actually runs in."
fi

cni_images="$(kubectl get pods -n kube-system -o jsonpath='{.items[*].spec.containers[*].image}' 2>/dev/null || true)"
other_cni="$(kubectl get pods -A -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || true)"
if grep -Eqi 'calico|cilium|antrea|weave|kube-router' <<<"${cni_images} ${other_cni}"; then
  info "NetworkPolicy-capable CNI detected."
elif grep -qi 'kindnet' <<<"${cni_images}"; then
  info "kindnet detected: it enforces NetworkPolicy on kind >= v0.24.0 (older kind versions do not)."
else
  warn "No NetworkPolicy-enforcing CNI detected: Q5/Q10 policies are accepted but may not block traffic. See ${LAB_DOC} (section 4c)."
fi

if ! have helm; then
  warn "helm not found: Q3 needs it (setup installs two releases from a local chart). Install Helm, then re-run setup.sh. See ${LAB_DOC} (section 3)."
fi
if ! have podman && ! have docker; then
  warn "Neither podman nor docker found: Q17 (image build) needs one of them. See ${LAB_DOC} (section 2)."
fi

# ---------------------------------------------------------------- namespaces
info "Creating namespaces (label ${LABEL})"
for ns in "${NAMESPACES[@]}"; do make_ns "${ns}"; done
# Q2 starts inside a namespace that enforces the restricted profile
kubectl label namespace m06-pipeline --overwrite >/dev/null \
  pod-security.kubernetes.io/enforce=restricted pod-security.kubernetes.io/enforce-version=latest
# reset the labels that Q5 / Q14 ask you to add
kubectl label namespace m06-partners team- >/dev/null 2>&1 || true
kubectl label namespace m06-psa pod-security.kubernetes.io/enforce- pod-security.kubernetes.io/enforce-version- \
  pod-security.kubernetes.io/warn- pod-security.kubernetes.io/warn-version- >/dev/null 2>&1 || true

mkdir -p "${STATE}"
for q in $(seq -w 1 17); do mkdir -p "${BASE}/q${q}"; done

# ------------------------------------------- Q1 + Q13 a fleet of Pods (m06-fleet)
info "Q1/Q13 fleet: svc-a..svc-d, cpu-burner, batch-1..3"
kubectl -n m06-fleet delete configmap svc-d-env --ignore-not-found >/dev/null
apply <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: svc-a
  namespace: m06-fleet
  labels:
    app: svc-a
spec:
  replicas: 2
  selector:
    matchLabels:
      app: svc-a
  template:
    metadata:
      labels:
        app: svc-a
    spec:
      containers:
      - name: web
        image: nginx:1.27-alpine
        resources:                 # requests == limits -> QoS Guaranteed
          requests:
            cpu: 50m
            memory: 64Mi
          limits:
            cpu: 50m
            memory: 64Mi
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: svc-b
  namespace: m06-fleet
  labels:
    app: svc-b
spec:
  replicas: 3
  selector:
    matchLabels:
      app: svc-b
  template:
    metadata:
      labels:
        app: svc-b
    spec:
      containers:
      - name: app
        image: busybox:1.36
        command: ["sh", "-c", "i=0; while true; do i=$((i+1)); echo \"svc-b $(hostname) event $i\"; sleep 4; done"]
        resources:                 # requests only -> QoS Burstable
          requests:
            cpu: 10m
            memory: 16Mi
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: svc-c
  namespace: m06-fleet
  labels:
    app: svc-c
spec:
  replicas: 1
  selector:
    matchLabels:
      app: svc-c
  template:
    metadata:
      labels:
        app: svc-c
    spec:
      containers:
      - name: redis                # no resources -> QoS BestEffort
        image: redis:7.2
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: svc-d
  namespace: m06-fleet
  labels:
    app: svc-d
spec:
  replicas: 1
  selector:
    matchLabels:
      app: svc-d
  template:
    metadata:
      labels:
        app: svc-d
    spec:
      containers:
      - name: main                 # healthy - index 0, so "[0]" shortcuts miss the crash
        image: busybox:1.36
        command: ["sh", "-c", "while true; do echo main alive; sleep 20; done"]
      - name: worker               # BROKEN on purpose: needs DB_HOST from a ConfigMap that is missing
        image: busybox:1.36
        command:
        - sh
        - -c
        - |
          if [ -z "$DB_HOST" ]; then echo "FATAL: DB_HOST is not set (expected from ConfigMap svc-d-env)" >&2; exit 3; fi
          echo "worker connected to $DB_HOST"
          while true; do sleep 30; done
        envFrom:
        - configMapRef:
            name: svc-d-env
            optional: true
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: cpu-burner
  namespace: m06-fleet
  labels:
    app: cpu-burner
spec:
  replicas: 1
  selector:
    matchLabels:
      app: cpu-burner
  template:
    metadata:
      labels:
        app: cpu-burner
    spec:
      containers:
      - name: burn
        image: busybox:1.36
        command: ["sh", "-c", "while true; do :; done"]
        resources:
          requests:
            cpu: 50m
            memory: 16Mi
          limits:
            cpu: 200m              # keeps the lab laptop usable
            memory: 32Mi
---
apiVersion: v1
kind: Pod
metadata:
  name: batch-1
  namespace: m06-fleet
  labels:
    app: batch
spec:
  containers:
  - name: job
    image: busybox:1.36
    command: ["sh", "-c", "sleep 86400"]
---
apiVersion: v1
kind: Pod
metadata:
  name: batch-2                    # Completed - not crashing
  namespace: m06-fleet
  labels:
    app: batch
spec:
  restartPolicy: Never
  containers:
  - name: job
    image: busybox:1.36
    command: ["sh", "-c", "echo batch done"]
---
apiVersion: v1
kind: Pod
metadata:
  name: batch-3                    # failed once (Error), never restarts - not "keeps crashing"
  namespace: m06-fleet
  labels:
    app: batch
spec:
  restartPolicy: Never
  containers:
  - name: job
    image: busybox:1.36
    command: ["sh", "-c", "echo 'input missing' >&2; exit 1"]
EOF

# ------------------------------------------------- Q2 restricted sidecar Pod (m06-pipeline)
info "Q2  draft pipeline.yaml (rejected by PSA restricted)"
put_file "${BASE}/q02/pipeline.yaml" <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: pipeline
  namespace: m06-pipeline
spec:
  initContainers:
  - name: seed
    image: busybox:1.36
    command: ["sh", "-c", "echo 'pipeline starting' > /work/app.log"]
    volumeMounts:
    - name: work
      mountPath: /work
  containers:
  - name: app
    image: busybox:1.36
    command: ["sh", "-c", "i=0; while true; do i=$((i+1)); echo \"record $i processed\" >> /work/app.log; sleep 3; done"]
    volumeMounts:
    - name: work
      mountPath: /work
  - name: log-shipper
    image: busybox:1.36
    command: ["sh", "-c", "tail -n +1 -f /work/app.log"]
    volumeMounts:
    - name: work
      mountPath: /work
  volumes:
  - name: work
    emptyDir: {}
EOF

# ------------------------------------------------- Q3 Helm chart + releases (m06-helm, m06-legacy)
info "Q3  local chart 'portal', values-v3.yaml, client Pod"
put_file "${BASE}/q03/portal/Chart.yaml" <<'EOF'
apiVersion: v2
name: portal
description: CKAD mock exam 06 demo chart (nginx answering a configurable message)
type: application
version: 0.3.0
appVersion: "1.27"
EOF
put_file "${BASE}/q03/portal/values.yaml" <<'EOF'
replicaCount: 1
image:
  repository: nginx
  tag: "1.27-alpine"
message: "portal v1"
service:
  port: 80
  targetPort: 80
EOF
put_file "${BASE}/q03/portal/templates/configmap.yaml" <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ .Release.Name }}-conf
  labels:
    app.kubernetes.io/name: portal
    app.kubernetes.io/instance: {{ .Release.Name }}
data:
  default.conf: |
    server {
      listen 80;
      location / {
        default_type text/plain;
        return 200 '{{ .Values.message }}\n';
      }
    }
EOF
put_file "${BASE}/q03/portal/templates/deployment.yaml" <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ .Release.Name }}
  labels:
    app.kubernetes.io/name: portal
    app.kubernetes.io/instance: {{ .Release.Name }}
spec:
  replicas: {{ .Values.replicaCount }}
  selector:
    matchLabels:
      app.kubernetes.io/name: portal
      app.kubernetes.io/instance: {{ .Release.Name }}
  template:
    metadata:
      labels:
        app.kubernetes.io/name: portal
        app.kubernetes.io/instance: {{ .Release.Name }}
      annotations:
        checksum/config: {{ include (print $.Template.BasePath "/configmap.yaml") . | sha256sum }}
    spec:
      containers:
      - name: web
        image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
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
          name: {{ .Release.Name }}-conf
EOF
put_file "${BASE}/q03/portal/templates/service.yaml" <<'EOF'
apiVersion: v1
kind: Service
metadata:
  name: {{ .Release.Name }}
  labels:
    app.kubernetes.io/name: portal
    app.kubernetes.io/instance: {{ .Release.Name }}
spec:
  selector:
    app.kubernetes.io/name: portal
    app.kubernetes.io/instance: {{ .Release.Name }}
  ports:
  - name: http
    port: {{ .Values.service.port }}
    targetPort: {{ .Values.service.targetPort }}
EOF
put_file "${BASE}/q03/values-v3.yaml" <<'EOF'
# requested by the portal team for release v3
replicaCount: 3
message: "portal v3"
service:
  targetPort: 8080
EOF
sleeper m06-helm client app client
if have helm; then
  if ! helm status portal -n m06-helm >/dev/null 2>&1; then
    info "Q3  helm install portal (rev 1) + upgrade (rev 2)"
    helm install portal "${BASE}/q03/portal" -n m06-helm >/dev/null \
      && helm upgrade portal "${BASE}/q03/portal" -n m06-helm --set replicaCount=2 --set message="portal v2" >/dev/null \
      || warn "helm install/upgrade of 'portal' failed - check 'helm list -n m06-helm'."
  else
    info "Q3  release portal already exists - keeping its history"
  fi
  if ! helm status portal-old -n m06-legacy >/dev/null 2>&1; then
    helm install portal-old "${BASE}/q03/portal" -n m06-legacy --set message="portal old" >/dev/null \
      || warn "helm install of 'portal-old' failed."
  fi
fi

# ------------------------------------------------- Q4 CronJob without permissions (m06-cron)
info "Q4  CronJob pod-audit (403), audit-target Pods"
sleeper m06-cron audit-target-1 app audit-target
sleeper m06-cron audit-target-2 app audit-target
apply <<'EOF'
apiVersion: batch/v1
kind: CronJob
metadata:
  name: pod-audit
  namespace: m06-cron
spec:
  schedule: "*/15 * * * *"
  jobTemplate:
    spec:
      backoffLimit: 0
      template:
        spec:
          restartPolicy: Never     # runs as the "default" ServiceAccount -> HTTP 403
          containers:
          - name: audit
            image: curlimages/curl:8.10.1
            command:
            - sh
            - -c
            - |
              SA=/var/run/secrets/kubernetes.io/serviceaccount
              NS=$(cat $SA/namespace)
              code=$(curl -s -o /tmp/pods.json -w '%{http_code}' --cacert $SA/ca.crt \
                -H "Authorization: Bearer $(cat $SA/token)" \
                https://kubernetes.default.svc/api/v1/namespaces/$NS/pods)
              echo "HTTP $code"
              if [ "$code" != "200" ]; then head -c 300 /tmp/pods.json; echo; exit 1; fi
              grep -o '"name": *"audit-target-[0-9]*"' /tmp/pods.json | sed 's/.*"\(audit-target-[0-9]*\)"/pod: \1/' | sort -u
EOF
if ! kubectl -n m06-cron get job pod-audit-initial >/dev/null 2>&1; then
  kubectl -n m06-cron create job pod-audit-initial --from=cronjob/pod-audit >/dev/null
fi

# ------------------------------------------------- Q5 NetworkPolicy playground
info "Q5  settlement / accounts-db / test Pods in m06-netpol, m06-partners, m06-others"
apply <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: settlement
  namespace: m06-netpol
  labels:
    app: settlement
spec:
  containers:
  - name: web
    image: busybox:1.36
    command: ["sh", "-c", "mkdir -p /tmp/www && echo 'settlement ok' > /tmp/www/index.html && exec httpd -f -p 8080 -h /tmp/www"]
    ports:
    - containerPort: 8080
---
apiVersion: v1
kind: Pod
metadata:
  name: accounts-db
  namespace: m06-netpol
  labels:
    app: accounts-db
spec:
  containers:
  - name: db                       # a stub that speaks HTTP on 5432, so wget can test it
    image: busybox:1.36
    command: ["sh", "-c", "mkdir -p /tmp/www && echo 'accounts-db ok' > /tmp/www/index.html && exec httpd -f -p 5432 -h /tmp/www"]
    ports:
    - containerPort: 5432
---
apiVersion: v1
kind: Service
metadata:
  name: settlement
  namespace: m06-netpol
spec:
  selector:
    app: settlement
  ports:
  - port: 8080
    targetPort: 8080
---
apiVersion: v1
kind: Service
metadata:
  name: accounts-db
  namespace: m06-netpol
spec:
  selector:
    app: accounts-db
  ports:
  - port: 5432
    targetPort: 5432
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: accounts-db-ingress        # existing policy - must stay unchanged
  namespace: m06-netpol
spec:
  podSelector:
    matchLabels:
      app: accounts-db
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: settlement
    ports:
    - protocol: TCP
      port: 5432
EOF
sleeper m06-netpol frontend app frontend
sleeper m06-netpol intruder app intruder
sleeper m06-partners partner-api role api
sleeper m06-partners partner-batch role batch
sleeper m06-others outsider role api

# ------------------------------------------------- Q6 removed APIs (m06-apis)
info "Q6  vintage-stack.yaml (removed API versions)"
put_file "${BASE}/q06/vintage-stack.yaml" <<'EOF'
# vintage-stack.yaml - written for Kubernetes 1.15 (2019). Namespace m06-apis.
apiVersion: apps/v1beta1
kind: Deployment
metadata:
  name: vintage-web
  namespace: m06-apis
  labels:
    app: vintage-web
spec:
  replicas: 2
  template:
    metadata:
      labels:
        app: vintage-web
    spec:
      containers:
      - name: web
        image: nginx:1.27-alpine
        ports:
        - containerPort: 80
        resources:
          requests:
            cpu: 50m
---
apiVersion: v1
kind: Service
metadata:
  name: vintage-web
  namespace: m06-apis
spec:
  selector:
    app: vintage-web
  ports:
  - port: 80
    targetPort: 80
---
apiVersion: networking.k8s.io/v1beta1
kind: Ingress
metadata:
  name: vintage-web
  namespace: m06-apis
  annotations:
    kubernetes.io/ingress.class: nginx
spec:
  rules:
  - host: vintage.m06.local
    http:
      paths:
      - path: /
        backend:
          serviceName: vintage-web
          servicePort: 80
---
apiVersion: batch/v1beta1
kind: CronJob
metadata:
  name: vintage-report
  namespace: m06-apis
spec:
  schedule: "30 2 * * *"
  jobTemplate:
    spec:
      template:
        spec:
          restartPolicy: OnFailure
          containers:
          - name: report
            image: busybox:1.36
            command: ["sh", "-c", "echo nightly report"]
---
apiVersion: policy/v1beta1
kind: PodDisruptionBudget
metadata:
  name: vintage-web
  namespace: m06-apis
spec:
  minAvailable: 1
  selector:
    matchLabels:
      app: vintage-web
---
apiVersion: autoscaling/v2beta1
kind: HorizontalPodAutoscaler
metadata:
  name: vintage-web
  namespace: m06-apis
spec:
  scaleTargetRef:
    apiVersion: apps/v1beta1
    kind: Deployment
    name: vintage-web
  minReplicas: 2
  maxReplicas: 4
  metrics:
  - type: Resource
    resource:
      name: cpu
      targetAverageUtilization: 70
---
apiVersion: extensions/v1beta1
kind: NetworkPolicy
metadata:
  name: vintage-web-allow-http
  namespace: m06-apis
spec:
  podSelector:
    matchLabels:
      app: vintage-web
  policyTypes:
  - Ingress
  ingress:
  - ports:
    - protocol: TCP
      port: 80
EOF

# ------------------------------------------------- Q7 StatefulSet without its headless Service (m06-sts)
info "Q7  StatefulSet kv (serviceName kv-peers does not exist), Service kv, dns-client"
apply <<'EOF'
apiVersion: v1
kind: Service
metadata:
  name: kv                         # client Service (ClusterIP) - NOT the governing Service
  namespace: m06-sts
spec:
  selector:
    app: kv
  ports:
  - name: redis
    port: 6379
    targetPort: redis
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: kv
  namespace: m06-sts
  labels:
    app: kv
spec:
  serviceName: kv-peers            # BROKEN on purpose: no such headless Service (and the field is immutable)
  replicas: 3
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
        args: ["--appendonly", "yes"]
        ports:
        - name: redis
          containerPort: 6379
        readinessProbe:
          exec:
            command: ["redis-cli", "ping"]
          periodSeconds: 5
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
          storage: 64Mi
EOF
sleeper m06-sts dns-client app dns-client

# ------------------------------------------------- Q8 kustomize base (files only)
info "Q8  kustomize base 'reviews'"
put_file "${BASE}/q08/base/kustomization.yaml" <<'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- deployment.yaml
- service.yaml
EOF
put_file "${BASE}/q08/base/deployment.yaml" <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: reviews
  labels:
    app: reviews
spec:
  replicas: 1
  selector:
    matchLabels:
      app: reviews
  template:
    metadata:
      labels:
        app: reviews
    spec:
      containers:
      - name: reviews
        image: nginx:1.27
        ports:
        - containerPort: 80
        envFrom:
        - configMapRef:
            name: reviews-config   # provided by the overlays (configMapGenerator)
EOF
put_file "${BASE}/q08/base/service.yaml" <<'EOF'
apiVersion: v1
kind: Service
metadata:
  name: reviews
  labels:
    app: reviews
spec:
  selector:
    app: reviews
  ports:
  - port: 80
    targetPort: 80
EOF

# ------------------------------------------------- Q9 guard rails (m06-hpa)
info "Q9  LimitRange bounds + ResourceQuota compute"
apply <<'EOF'
apiVersion: v1
kind: LimitRange
metadata:
  name: bounds
  namespace: m06-hpa
spec:
  limits:
  - type: Container
    min:
      cpu: 50m
      memory: 32Mi
    max:
      cpu: 500m
      memory: 256Mi
    maxLimitRequestRatio:
      cpu: "2"
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
  name: compute
  namespace: m06-hpa
spec:
  hard:
    requests.cpu: "1"
    requests.memory: 1Gi
    limits.cpu: "2"
    limits.memory: 2Gi
    pods: "10"
EOF

# ------------------------------------------------- Q10 broken end-to-end stack (m06-shop)
info "Q10 storefront stack with five faults"
apply <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: storefront-conf
  namespace: m06-shop
data:
  default.conf: |
    server {
      listen 80;
      location = /healthz {
        default_type text/plain;
        return 200 'ok\n';
      }
      location = / {
        default_type text/plain;
        return 200 'storefront: OK\n';
      }
      location / {
        default_type text/plain;
        return 404 'not found\n';
      }
    }
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: storefront
  namespace: m06-shop
  labels:
    app: storefront
spec:
  replicas: 2
  selector:
    matchLabels:
      app: storefront
  template:
    metadata:
      labels:
        app: storefront
        tier: web
    spec:
      containers:
      - name: web
        image: nginx:1.27-alpne           # fault 1: tag typo
        ports:
        - name: http
          containerPort: 80
        readinessProbe:
          httpGet:
            path: /health                 # fault 2: the app serves /healthz
            port: http
          periodSeconds: 5
        livenessProbe:
          httpGet:
            path: /healthz
            port: http
          initialDelaySeconds: 5
          periodSeconds: 10
        volumeMounts:
        - name: conf
          mountPath: /etc/nginx/conf.d
      volumes:
      - name: conf
        configMap:
          name: storefront-conf
---
apiVersion: v1
kind: Service
metadata:
  name: storefront
  namespace: m06-shop
spec:
  selector:
    app: store-front                      # fault 3: Pods are labelled app=storefront
  ports:
  - name: http
    port: 80
    targetPort: http
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: storefront
  namespace: m06-shop
spec:
  ingressClassName: nginx
  rules:
  - host: shop.m06.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: storefront
            port:
              number: 8080                # fault 4: the Service port is 80
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-ingress
  namespace: m06-shop
spec:
  podSelector: {}
  policyTypes:
  - Ingress
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-ingress-controller
  namespace: m06-shop
spec:
  podSelector:
    matchLabels:
      app: storefront
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: ingress-nginx             # fault 5: namespaces carry kubernetes.io/metadata.name
    ports:
    - protocol: TCP
      port: 80
EOF

# ------------------------------------------------- Q11 configuration sources (m06-config)
info "Q11 app-env, nginx-extra, app-secret"
apply <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-env
  namespace: m06-config
data:
  LOG_LEVEL: info
  FEATURE_X: "on"                  # quoted: unquoted on/off/yes/no become booleans in YAML 1.1
  REGION: eu-west-1
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: nginx-extra
  namespace: m06-config
data:
  gzip.conf: |
    gzip on;
    gzip_types text/plain application/json;
---
apiVersion: v1
kind: Secret
metadata:
  name: app-secret
  namespace: m06-config
type: Opaque
stringData:
  LOG_LEVEL: debug
  DB_PASSWORD: m06-pa55
  API_TOKEN: tok-m06-123
EOF

# ------------------------------------------------- Q12 rollout vs. pod quota (m06-rollout)
info "Q12 edge-api (4 replicas, maxSurge 1 / maxUnavailable 0) + quota pods=4"
apply <<'EOF'
apiVersion: v1
kind: ResourceQuota
metadata:
  name: pod-cap
  namespace: m06-rollout
spec:
  hard:
    pods: "4"
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: edge-api
  namespace: m06-rollout
  labels:
    app: edge-api
spec:
  replicas: 4
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1                  # TRAP: the surge Pod would be Pod number 5
      maxUnavailable: 0
  selector:
    matchLabels:
      app: edge-api
  template:
    metadata:
      labels:
        app: edge-api
    spec:
      containers:
      - name: api
        image: nginx:1.27
        ports:
        - containerPort: 80
EOF

# ------------------------------------------------- Q14 workload that violates restricted (m06-psa)
info "Q14 metrics-api (root, NET_ADMIN, hostPath)"
apply <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: metrics-api
  namespace: m06-psa
  labels:
    app: metrics-api
spec:
  replicas: 2
  selector:
    matchLabels:
      app: metrics-api
  template:
    metadata:
      labels:
        app: metrics-api
    spec:
      containers:
      - name: api
        image: busybox:1.36
        command: ["sh", "-c", "mkdir -p /tmp/www && echo 'metrics-api ok' > /tmp/www/index.html && exec httpd -f -p 8080 -h /tmp/www"]
        ports:
        - name: http
          containerPort: 8080
        securityContext:
          capabilities:
            add: ["NET_ADMIN"]
        volumeMounts:
        - name: node-logs
          mountPath: /logs
          readOnly: true
      volumes:
      - name: node-logs
        hostPath:
          path: /var/log
          type: Directory
EOF

# ------------------------------------------------- Q15 blue/green behind an Ingress (m06-bluegreen)
info "Q15 tracker-blue / tracker-green + Ingress tracker"
web_app m06-bluegreen tracker-blue 2 'tracker: blue'
web_app m06-bluegreen tracker-green 2 'tracker: green'
apply <<'EOF'
apiVersion: v1
kind: Service
metadata:
  name: tracker-blue
  namespace: m06-bluegreen
spec:
  selector:
    app: tracker-blue
  ports:
  - port: 80
    targetPort: http
---
apiVersion: v1
kind: Service
metadata:
  name: tracker-green
  namespace: m06-bluegreen
spec:
  selector:
    app: tracker-green
  ports:
  - name: http
    port: 8080                     # note: not 80
    targetPort: http
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: tracker
  namespace: m06-bluegreen
spec:
  ingressClassName: nginx
  rules:
  - host: tracker.m06.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: tracker-blue
            port:
              number: 80
EOF
for d in tracker-blue tracker-green; do
  kubectl -n m06-bluegreen get deployment "${d}" -o jsonpath='{.metadata.generation}' >"${STATE}/q15-${d}-deploy-gen"
  kubectl -n m06-bluegreen get service "${d}" -o jsonpath='{.metadata.resourceVersion}' >"${STATE}/q15-${d}-svc-rv"
done

# ------------------------------------------------- Q16 a feature-flag "operator"
info "Q16 CRDs, operator Deployments, RBAC, FeatureFlags"
apply <<'EOF'
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: featureflags.flags.m06.ckad.io
  labels:
    ckad-mock: exam-06
spec:
  group: flags.m06.ckad.io
  scope: Namespaced
  names:
    kind: FeatureFlag
    plural: featureflags
    singular: featureflag
    shortNames: ["ff"]
  versions:
  - name: v1alpha1
    served: true
    storage: false
    deprecated: true
    deprecationWarning: "flags.m06.ckad.io/v1alpha1 FeatureFlag is deprecated; use flags.m06.ckad.io/v1"
    schema:
      openAPIV3Schema:
        type: object
        properties:
          spec:
            type: object
            required: ["enabled", "rolloutPercent"]
            properties:
              enabled:
                type: boolean
              rolloutPercent:
                type: integer
                minimum: 0
                maximum: 100
              owner:
                type: string
  - name: v1
    served: true
    storage: true
    schema:
      openAPIV3Schema:
        type: object
        properties:
          spec:
            type: object
            required: ["enabled", "rolloutPercent"]
            properties:
              enabled:
                type: boolean
              rolloutPercent:
                type: integer
                minimum: 0
                maximum: 100
              owner:
                type: string
    additionalPrinterColumns:
    - name: Enabled
      type: boolean
      jsonPath: .spec.enabled
    - name: Rollout
      type: integer
      jsonPath: .spec.rolloutPercent
    - name: Owner
      type: string
      jsonPath: .spec.owner
---
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: flagsets.flags.m06.ckad.io
  labels:
    ckad-mock: exam-06
spec:
  group: flags.m06.ckad.io
  scope: Namespaced
  names:
    kind: FlagSet
    plural: flagsets
    singular: flagset
    shortNames: ["fset"]
  versions:
  - name: v1
    served: true
    storage: true
    schema:
      openAPIV3Schema:
        type: object
        x-kubernetes-preserve-unknown-fields: true
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: flag-operator
  namespace: m06-flags-system
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: flag-ui
  namespace: m06-flags-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: m06-flag-operator
  labels:
    ckad-mock: exam-06
rules:
- apiGroups: ["flags.m06.ckad.io"]
  resources: ["featureflags", "flagsets"]
  verbs: ["get", "list", "watch", "update", "patch"]
- apiGroups: ["flags.m06.ckad.io"]
  resources: ["featureflags/status"]
  verbs: ["update", "patch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: m06-flag-operator
  labels:
    ckad-mock: exam-06
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: m06-flag-operator
subjects:
- kind: ServiceAccount
  name: flag-operator
  namespace: m06-flags-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: m06-flag-viewer
  labels:
    ckad-mock: exam-06
rules:
- apiGroups: ["flags.m06.ckad.io"]
  resources: ["featureflags", "flagsets"]
  verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: m06-flag-viewer
  labels:
    ckad-mock: exam-06
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: m06-flag-viewer
subjects:
- kind: ServiceAccount
  name: flag-ui
  namespace: m06-flags-system
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: flag-controller            # the operator (runs as flag-operator)
  namespace: m06-flags-system
  labels:
    app: flag-controller
spec:
  replicas: 1
  selector:
    matchLabels:
      app: flag-controller
  template:
    metadata:
      labels:
        app: flag-controller
    spec:
      serviceAccountName: flag-operator
      containers:
      - name: manager
        image: busybox:1.36
        command: ["sh", "-c", "while true; do echo 'reconciling featureflags'; sleep 30; done"]
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: flag-dashboard             # read-only UI (runs as flag-ui) - a decoy
  namespace: m06-flags-system
  labels:
    app: flag-dashboard
spec:
  replicas: 1
  selector:
    matchLabels:
      app: flag-dashboard
  template:
    metadata:
      labels:
        app: flag-dashboard
    spec:
      serviceAccountName: flag-ui
      containers:
      - name: ui
        image: busybox:1.36
        command: ["sh", "-c", "while true; do echo 'serving dashboard'; sleep 30; done"]
EOF
if ! kubectl wait --for condition=established --timeout=60s \
    crd/featureflags.flags.m06.ckad.io crd/flagsets.flags.m06.ckad.io >/dev/null; then
  warn "FeatureFlag CRDs not established after 60s; re-run setup.sh to create the Q16 FeatureFlags."
else
apply <<'EOF'
apiVersion: flags.m06.ckad.io/v1
kind: FeatureFlag
metadata:
  name: dark-mode
  namespace: m06-team-a
spec:
  enabled: true
  rolloutPercent: 100
  owner: team-a
---
apiVersion: flags.m06.ckad.io/v1
kind: FeatureFlag
metadata:
  name: new-checkout
  namespace: m06-team-b
spec:
  enabled: false
  rolloutPercent: 0
  owner: team-b
---
apiVersion: flags.m06.ckad.io/v1
kind: FeatureFlag
metadata:
  name: beta-search
  namespace: m06-team-b
spec:
  enabled: true
  rolloutPercent: 10
  owner: team-b
EOF
fi

# ------------------------------------------------- Q17 image build input (local + m06-build)
info "Q17 Dockerfile, server.sh, www/index.html"
put_file "${BASE}/q17/Dockerfile" <<'EOF'
FROM busybox:1.36
RUN adduser -D -H -u 10001 tally
WORKDIR /app
COPY server.sh /app/server.sh
COPY www/ /app/www/
USER tally
EXPOSE 8080
ENTRYPOINT ["sh", "/app/server.sh"]
EOF
put_file "${BASE}/q17/server.sh" <<'EOF'
#!/bin/sh
echo "tally ${APP_VERSION:-dev} listening on :8080 as uid $(id -u)"
exec httpd -f -p 8080 -h /app/www
EOF
put_file "${BASE}/q17/www/index.html" <<'EOF'
<h1>tally 2.1.0</h1>
EOF

# ------------------------------------------------------------------- summary
echo
echo "======================================================================"
echo " CKAD Mock Exam 06 (final boss) is ready."
echo "   Namespaces : ${NAMESPACES[*]}"
echo "   Files      : ${BASE}/q01 ... q17 (existing files kept; RESET=1 restores them)"
echo "   Ingress    : kit lab (kind) -> http://localhost:8080 ; minikube -> http://\$(minikube ip)"
echo "                any cluster   -> kubectl -n ingress-nginx port-forward svc/ingress-nginx-controller 8080:80"
echo "   Give the Pods 2-3 minutes to pull images (redis, nginx, busybox, curl)."
if (( ${#WARNINGS[@]} > 0 )); then
  echo "   ${#WARNINGS[@]} warning(s):"
  for w in "${WARNINGS[@]}"; do echo "     - ${w}"; done
else
  echo "   No warnings."
fi
echo " This paper is deliberately harder than the real exam. 66% here is a strong result."
echo " Start your 120-minute timer now. Questions: questions.md"
echo "======================================================================"
