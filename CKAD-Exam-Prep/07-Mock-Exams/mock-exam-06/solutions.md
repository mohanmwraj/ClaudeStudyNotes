# CKAD Mock Exam 06 — Solutions (Final boss)

This paper is deliberately harder and longer than the real exam. **66% or more here is a strong signal that you're ready.** Grade honestly: give a question's points only when its **Verify** commands show the expected result. Partial credit follows each question's points table. Any approach that reaches the same end state without breaking a "do not change" rule scores the same.

## Domain weights

| Domain | Questions | Weight |
|---|---|---|
| Application Design and Build | 2, 7, 17 | 20% |
| Application Deployment | 3, 8, 12, 15 | 20% |
| Application Observability and Maintenance | 1, 6, 13 | 15% |
| Application Environment, Configuration and Security | 4, 9, 11, 14, 16 | 25% |
| Services and Networking | 5, 10 | 20% |
| **Total** | **17** | **100%** |

Shortcuts used below (exam hosts provide `k` and completion; set the rest yourself):

```bash
alias k=kubectl
export do="--dry-run=client -o yaml"
```

On the real exam, `ssh` to the host that the task names first and `exit` afterwards. None of the solutions below need `jq`: JSONPath and custom columns do the job.

---

## Question 1 — Find the crash-looping container (4%)

**Approach:** Print restart counts **per container**. The crashing container is the second container of `svc-d`, so shortcuts like `--sort-by=.status.containerStatuses[0].restartCount` miss it. The termination details live in `lastState.terminated`. The worker reads `DB_HOST` from a ConfigMap referenced with `optional: true`, so a missing ConfigMap doesn't block the Pod: the app just crashes.

```bash
kubectl -n m06-fleet get pods
kubectl -n m06-fleet get pods -o jsonpath='{range .items[*]}{.metadata.name}{":"}{range .status.containerStatuses[*]}{" "}{.name}{"="}{.restartCount}{end}{"\n"}{end}'
# ...
# svc-d-7f9c8b6d5-k2x4q: main=0 worker=6        <- the only container with restarts
P=$(kubectl -n m06-fleet get pod -l app=svc-d -o jsonpath='{.items[0].metadata.name}')
kubectl -n m06-fleet get pod "$P" -o jsonpath='{.metadata.name}{" "}{range .status.containerStatuses[?(@.restartCount>0)]}{.name}{" "}{.lastState.terminated.reason}{" "}{.lastState.terminated.exitCode}{" "}{.restartCount}{end}{"\n"}' \
  > ~/ckad-mocks/exam-06/q01/crash.txt

kubectl -n m06-fleet logs "$P" -c worker --previous
# FATAL: DB_HOST is not set (expected from ConfigMap svc-d-env)
kubectl -n m06-fleet get deploy svc-d -o jsonpath='{.spec.template.spec.containers[1].envFrom}{"\n"}'
# [{"configMapRef":{"name":"svc-d-env","optional":true}}]
kubectl -n m06-fleet create configmap svc-d-env --from-literal=DB_HOST=db.m06-fleet.svc.cluster.local
kubectl -n m06-fleet rollout restart deployment svc-d
kubectl -n m06-fleet rollout status deployment svc-d
```

**Verify**

```bash
cat ~/ckad-mocks/exam-06/q01/crash.txt
kubectl -n m06-fleet get pods -l app=svc-d
kubectl -n m06-fleet logs deploy/svc-d -c worker
```

```text
svc-d-7f9c8b6d5-k2x4q worker Error 3 6
NAME                     READY   STATUS    RESTARTS   AGE
svc-d-5d8f7c6b9d-p7w2n   2/2     Running   0          40s
worker connected to db.m06-fleet.svc.cluster.local
```

**Common mistakes**
- Reporting `batch-3` (it failed once with `restartPolicy: Never`, so it never restarts) or `batch-2` (Completed).
- Writing `CrashLoopBackOff`, which is the *waiting* reason. The termination reason for a non-zero exit is `Error`.
- Adding `env:` to the Deployment, which is forbidden. And waiting for the running container to "see" the new ConfigMap: environment variables are read only at container start, so restart.

| Item | Points |
|---|---|
| Correct Pod and container (`worker` of `svc-d`) | 1 |
| reason `Error`, exit code `3`, restart count read via JSONPath | 1 |
| ConfigMap `svc-d-env` with the right `DB_HOST` | 1 |
| New Pod 2/2 Running, worker logs "connected" | 1 |

---

## Question 2 — Init container, native sidecar and the restricted profile (7%)

**Approach:** A native sidecar is an entry in `initContainers` with `restartPolicy: Always` (GA since v1.33). It starts in init order, stays running, and doesn't block the app containers. Pod Security Admission checks **every** container, including init containers. Read the rejection message: it lists every violated control.

```bash
kubectl apply -f ~/ckad-mocks/exam-06/q02/pipeline.yaml
# Error from server (Forbidden): ... pods "pipeline" is forbidden: violates PodSecurity "restricted:latest":
#   allowPrivilegeEscalation != false (...), unrestricted capabilities (...), runAsNonRoot != true (...), seccompProfile (...)
vim ~/ckad-mocks/exam-06/q02/pipeline.yaml
```

```yaml
# ~/ckad-mocks/exam-06/q02/pipeline.yaml (fixed)
apiVersion: v1
kind: Pod
metadata:
  name: pipeline
  namespace: m06-pipeline
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
    runAsGroup: 1000
    seccompProfile:
      type: RuntimeDefault
  initContainers:
  - name: seed
    image: busybox:1.36
    command: ["sh", "-c", "echo 'pipeline starting' > /work/app.log"]
    securityContext:
      allowPrivilegeEscalation: false
      capabilities:
        drop: ["ALL"]
    volumeMounts:
    - name: work
      mountPath: /work
  - name: log-shipper
    image: busybox:1.36
    restartPolicy: Always          # native sidecar: starts after seed, keeps running
    command: ["sh", "-c", "tail -n +1 -f /work/app.log"]
    securityContext:
      allowPrivilegeEscalation: false
      capabilities:
        drop: ["ALL"]
    volumeMounts:
    - name: work
      mountPath: /work
  containers:
  - name: app
    image: busybox:1.36
    command: ["sh", "-c", "i=0; while true; do i=$((i+1)); echo \"record $i processed\" >> /work/app.log; sleep 3; done"]
    securityContext:
      allowPrivilegeEscalation: false
      capabilities:
        drop: ["ALL"]
    volumeMounts:
    - name: work
      mountPath: /work
  volumes:
  - name: work
    emptyDir:
      sizeLimit: 64Mi
```

```bash
kubectl apply -f ~/ckad-mocks/exam-06/q02/pipeline.yaml
kubectl -n m06-pipeline get pod pipeline -w            # Init:0/2 -> PodInitializing -> Running (Ctrl-C)
kubectl -n m06-pipeline logs pipeline -c log-shipper | head -3 > ~/ckad-mocks/exam-06/q02/shipper.log
```

**Verify**

```bash
kubectl -n m06-pipeline get pod pipeline -o jsonpath='{.status.phase} {.spec.initContainers[*].name} {.spec.initContainers[1].restartPolicy}{"\n"}'
kubectl -n m06-pipeline get pod pipeline -o jsonpath='sidecar ready={.status.initContainerStatuses[?(@.name=="log-shipper")].ready} app ready={.status.containerStatuses[?(@.name=="app")].ready}{"\n"}'
cat ~/ckad-mocks/exam-06/q02/shipper.log
kubectl -n m06-pipeline exec pipeline -c app -- id -u
```

```text
Running seed log-shipper Always
sidecar ready=true app ready=true
pipeline starting
record 1 processed
record 2 processed
1000
```

**Common mistakes**
- Putting `restartPolicy: Always` on a container under `containers`. The field is only valid for init containers.
- Listing `log-shipper` before `seed`. The task wants seed first.
- Securing only the app container. PSA also rejects the init containers.
- `runAsNonRoot: true` without `runAsUser`. busybox runs as root, so the kubelet refuses to start it (`CreateContainerConfigError`).
- Relabelling the namespace to `baseline`, which is explicitly forbidden.

| Item | Points |
|---|---|
| `log-shipper` is a native sidecar (`initContainers` + `restartPolicy: Always`) | 2 |
| Order seed → log-shipper → app, names/images/commands unchanged | 1 |
| Restricted-compliant securityContext on Pod + all 3 containers | 2 |
| `emptyDir` `work` with `sizeLimit: 64Mi`, mounted in all 3 | 1 |
| `shipper.log` with the first 3 lines | 1 |

---

## Question 3 — Helm: a bad upgrade, a rollback and a leftover (6%)

**Approach:** Upgrading with only `-f values-v3.yaml` starts from the chart defaults plus that file, so revision 2's `--set` values are gone. That's expected. `helm upgrade` reports success because the Pods are healthy, but the **Service** now targets port 8080, where nginx doesn't listen. The last working revision is 2. `helm list -A` finds the leftover release.

```bash
helm -n m06-helm history portal
helm -n m06-helm get values portal                     # rev 2: message: portal v2, replicaCount: 2
helm upgrade portal ~/ckad-mocks/exam-06/q03/portal -n m06-helm -f ~/ckad-mocks/exam-06/q03/values-v3.yaml
kubectl -n m06-helm exec client -- wget -qO- -T 3 http://portal
# wget: can't connect to remote host (10.96.x.x): Connection refused
kubectl -n m06-helm get svc portal -o jsonpath='{.spec.ports[0].targetPort}{"\n"}'          # 8080
kubectl -n m06-helm get pods -l app.kubernetes.io/instance=portal                           # Running and Ready - the Pods are fine
echo service.targetPort > ~/ckad-mocks/exam-06/q03/broken-value.txt

helm rollback portal 2 -n m06-helm
helm history portal -n m06-helm > ~/ckad-mocks/exam-06/q03/history.txt

helm list -A | grep portal-old                         # portal-old   m06-legacy ...
helm uninstall portal-old -n m06-legacy
```

**Verify**

```bash
kubectl -n m06-helm exec client -- wget -qO- -T 3 http://portal
helm -n m06-helm get values portal
cat ~/ckad-mocks/exam-06/q03/history.txt
helm list -A | grep -c portal-old
kubectl get ns m06-legacy
```

```text
portal v2
USER-SUPPLIED VALUES:
message: portal v2
replicaCount: 2
REVISION  UPDATED                   STATUS      CHART         APP VERSION  DESCRIPTION
1         Sat Oct 17 09:02:11 2026  superseded  portal-0.3.0  1.27         Install complete
2         Sat Oct 17 09:02:13 2026  superseded  portal-0.3.0  1.27         Upgrade complete
3         Sat Oct 17 10:21:40 2026  superseded  portal-0.3.0  1.27         Upgrade complete
4         Sat Oct 17 10:23:05 2026  deployed    portal-0.3.0  1.27         Rollback to 2
0
NAME         STATUS   AGE
m06-legacy   Active   80m
```

**Common mistakes**
- `--reuse-values`. The task forbids it, and it would also keep `replicaCount: 2` and hide the lesson.
- Rolling back to revision 1 (`portal v1`). The last *working* revision is 2.
- `helm uninstall portal-old` without `-n m06-legacy`, which gives `release: not found`. Deleting the namespace instead breaks "keep its namespace".
- Fixing the Service with `kubectl edit`. Helm would overwrite the change on the next upgrade, and the task asked for a rollback.

> **Exam tip:** Helm stores each revision as a Secret `sh.helm.release.v1.<release>.v<N>` in the release namespace (`kubectl -n m06-helm get secrets -l owner=helm`). `helm history` reads exactly those Secrets.

| Item | Points |
|---|---|
| Upgrade with only `values-v3.yaml` (revision 3) | 1 |
| `broken-value.txt` = `service.targetPort` | 1 |
| Rolled back to revision 2: answers `portal v2`, values of rev 2 | 2 |
| `history.txt` written | 1 |
| `portal-old` uninstalled, namespace kept | 1 |

---

## Question 4 — CronJob that calls the API with its own token (7%)

**Approach:** The script authenticates with the projected token of the Pod's ServiceAccount, so RBAC applies to that SA. Create the SA, Role and RoleBinding. Then change the CronJob's **job template**: a Job created with `--from=cronjob/...` copies the template as it is at that moment.

```bash
kubectl -n m06-cron get jobs                     # pod-audit-initial and/or scheduled pod-audit-<n> Jobs, all failed
kubectl -n m06-cron logs job/pod-audit-initial   # or any other failed pod-audit Job
# HTTP 403
# {"kind":"Status",...,"message":"pods is forbidden: User \"system:serviceaccount:m06-cron:default\" cannot list resource \"pods\" ...

kubectl -n m06-cron create serviceaccount pod-auditor
kubectl -n m06-cron create role pod-auditor --verb=get,list,watch --resource=pods
kubectl -n m06-cron create rolebinding pod-auditor --role=pod-auditor --serviceaccount=m06-cron:pod-auditor

kubectl -n m06-cron patch cronjob pod-audit --type=merge -p '{"spec":{"concurrencyPolicy":"Forbid","successfulJobsHistoryLimit":2,"failedJobsHistoryLimit":1,"jobTemplate":{"spec":{"template":{"spec":{"serviceAccountName":"pod-auditor"}}}}}}'

kubectl -n m06-cron create job pod-audit-manual --from=cronjob/pod-audit
kubectl -n m06-cron wait --for=condition=complete job/pod-audit-manual --timeout=90s
kubectl -n m06-cron logs job/pod-audit-manual > ~/ckad-mocks/exam-06/q04/audit.log
kubectl auth can-i delete pods --as=system:serviceaccount:m06-cron:pod-auditor -n m06-cron > ~/ckad-mocks/exam-06/q04/can-delete.txt
```

The CronJob after the change (same result with `kubectl edit cronjob pod-audit`):

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: pod-audit
  namespace: m06-cron
spec:
  schedule: "*/15 * * * *"
  concurrencyPolicy: Forbid
  successfulJobsHistoryLimit: 2
  failedJobsHistoryLimit: 1
  jobTemplate:
    spec:
      backoffLimit: 0
      template:
        spec:
          serviceAccountName: pod-auditor
          restartPolicy: Never
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
```

**Verify**

```bash
cat ~/ckad-mocks/exam-06/q04/audit.log ~/ckad-mocks/exam-06/q04/can-delete.txt
kubectl -n m06-cron get cronjob pod-audit -o jsonpath='{.spec.schedule} | {.spec.concurrencyPolicy} {.spec.successfulJobsHistoryLimit} {.spec.failedJobsHistoryLimit} {.spec.jobTemplate.spec.template.spec.serviceAccountName}{"\n"}'
kubectl -n m06-cron get role pod-auditor -o jsonpath='{.rules}{"\n"}'
```

```text
HTTP 200
pod: audit-target-1
pod: audit-target-2
no
*/15 * * * * | Forbid 2 1 pod-auditor
[{"apiGroups":[""],"resources":["pods"],"verbs":["get","list","watch"]}]
```

A Job created with `--from=cronjob/pod-audit` gets an ownerReference to the CronJob, so the CronJob's history limits also apply to it. After two newer successful runs, `pod-audit-manual` may be garbage-collected; `audit.log` is what you grade.

**Common mistakes**
- Creating `pod-audit-manual` **before** patching the CronJob. The Job keeps the old template (default SA, 403), and a Job's Pod template is immutable, so delete it and create it again.
- `--serviceaccount=default:pod-auditor` in the RoleBinding. The subject must be in `m06-cron`.
- Granting a ClusterRole or `*` verbs. It works, but it isn't least privilege, and `can-i delete pods` would say `yes`.
- `serviceAccountName` set at CronJob `spec` level instead of `jobTemplate.spec.template.spec`.

| Item | Points |
|---|---|
| SA, Role (get/list/watch pods only), RoleBinding | 2 |
| CronJob: SA, `Forbid`, history 2/1, schedule & script unchanged | 2 |
| `pod-audit-manual` complete, `audit.log` = HTTP 200 + both Pods | 2 |
| `can-delete.txt` = `no` | 1 |

---

## Question 5 — NetworkPolicy with AND selectors, ipBlock and DNS (8%)

**Approach:** Inside **one** `from` element, `namespaceSelector` + `podSelector` are ANDed. Separate elements are ORed. A bare `podSelector` peer means "Pods in the policy's own namespace". `ipBlock.except` must lie inside `cidr`. Once egress is restricted, DNS must be allowed explicitly.

```bash
kubectl label namespace m06-partners team=partners
kubectl get ns m06-partners m06-others --show-labels
kubectl -n m06-netpol get netpol                 # accounts-db-ingress exists - leave it alone
```

```yaml
# q05-settlement-policy.yaml — kubectl apply -f q05-settlement-policy.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: settlement-policy
  namespace: m06-netpol
spec:
  podSelector:
    matchLabels:
      app: settlement
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - namespaceSelector:           # same element -> partner namespace AND role=api
        matchLabels:
          team: partners
      podSelector:
        matchLabels:
          role: api
    - podSelector:                 # separate element (OR): frontend in m06-netpol
        matchLabels:
          app: frontend
    ports:
    - protocol: TCP
      port: 8080
  egress:
  - to:
    - podSelector:
        matchLabels:
          app: accounts-db
    ports:
    - protocol: TCP
      port: 5432
  - to:
    - ipBlock:
        cidr: 192.0.2.0/24
        except:
        - 192.0.2.128/25
    ports:
    - protocol: TCP
      port: 443
  - to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: kube-system
      podSelector:
        matchLabels:
          k8s-app: kube-dns
    ports:
    - protocol: UDP
      port: 53
    - protocol: TCP
      port: 53
```

**Verify** (expected result in the comment of each line)

```bash
T='wget -qO- -T 3 http://settlement.m06-netpol:8080'
kubectl -n m06-partners exec partner-api   -- sh -c "$T"     # settlement ok
kubectl -n m06-partners exec partner-batch -- sh -c "$T"     # wget: download timed out
kubectl -n m06-others   exec outsider      -- sh -c "$T"     # wget: download timed out (namespace not team=partners)
kubectl -n m06-netpol   exec frontend      -- sh -c "$T"     # settlement ok
kubectl -n m06-netpol   exec intruder      -- sh -c "$T"     # wget: download timed out
kubectl -n m06-netpol exec settlement -- wget -qO- -T 3 http://accounts-db:5432          # accounts-db ok
kubectl -n m06-netpol exec settlement -- nc -zv -w 3 kubernetes.default.svc 443          # fails after ~3 s
kubectl -n m06-netpol exec settlement -- nslookup accounts-db.m06-netpol.svc.cluster.local | tail -2   # resolves
```

`192.0.2.0/24` is a documentation range (TEST-NET-1) that nothing answers on, so that rule is graded on the spec.

**Common mistakes**
- Two list items `- namespaceSelector: ...` / `- podSelector: role=api`. That is an OR, so `partner-batch` gets in, and the `podSelector` item only matches role=api Pods in m06-netpol.
- Forgetting step 1. Then the namespace selector matches nothing, and `partner-api` is blocked too.
- Leaving out `ports` on the ingress rule, which opens every port to those peers.
- No DNS egress. `wget http://accounts-db:5432` then fails with `bad address`, even though the 5432 rule is right.
- Editing `accounts-db-ingress`. It already allows `settlement` → `accounts-db:5432`.

| Item | Points |
|---|---|
| `m06-partners` labelled `team=partners` | 1 |
| Ingress peer: namespace AND role=api in one element | 2 |
| Ingress peer: `app=frontend` (own namespace) | 1 |
| Ingress restricted to TCP 8080 | 0.5 |
| Egress to accounts-db TCP 5432 | 1 |
| Egress ipBlock 192.0.2.0/24 except 192.0.2.128/25 on TCP 443 | 1.5 |
| DNS egress UDP+TCP 53 to kube-dns | 1 |

---

## Question 6 — A manifest from 2019 (5%)

**Approach:** Let the API tell you what is wrong (`--dry-run=server`). Use `kubectl api-resources` / `kubectl explain --api-version=...` for the new shapes. Changing only the `apiVersion` isn't enough: Deployment needs `selector`, Ingress needs `pathType` + `service.name/port`, and the HPA metric moved under `target`.

| Kind | Removed version | Removed in | Current | What else changes |
|---|---|---|---|---|
| Deployment | apps/v1beta1 | v1.16 | apps/v1 | `spec.selector` is required |
| Ingress | networking.k8s.io/v1beta1 | v1.22 | networking.k8s.io/v1 | `pathType`; `backend.service.name` + `port.number`; `ingressClassName` replaces the annotation |
| CronJob | batch/v1beta1 | v1.25 | batch/v1 | — |
| PodDisruptionBudget | policy/v1beta1 | v1.25 | policy/v1 | (empty selector now means "all Pods") |
| HorizontalPodAutoscaler | autoscaling/v2beta1 | v1.25 | autoscaling/v2 | `targetAverageUtilization` → `target.type: Utilization` + `averageUtilization`; fix `scaleTargetRef.apiVersion` |
| NetworkPolicy | extensions/v1beta1 | v1.16 | networking.k8s.io/v1 | — |

```bash
kubectl apply -f ~/ckad-mocks/exam-06/q06/vintage-stack.yaml --dry-run=server
# error: resource mapping not found for name: "vintage-web" ... no matches for kind "Deployment" in version "apps/v1beta1"
# ... (one line per removed API)
kubectl explain hpa.spec.metrics.resource.target --api-version=autoscaling/v2
vim ~/ckad-mocks/exam-06/q06/vintage-stack.yaml
```

```yaml
# ~/ckad-mocks/exam-06/q06/vintage-stack.yaml (fixed)
apiVersion: apps/v1
kind: Deployment
metadata:
  name: vintage-web
  namespace: m06-apis
  labels:
    app: vintage-web
spec:
  replicas: 2
  selector:
    matchLabels:
      app: vintage-web
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
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: vintage-web
  namespace: m06-apis
spec:
  ingressClassName: nginx
  rules:
  - host: vintage.m06.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: vintage-web
            port:
              number: 80
---
apiVersion: batch/v1
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
apiVersion: policy/v1
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
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: vintage-web
  namespace: m06-apis
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: vintage-web
  minReplicas: 2
  maxReplicas: 4
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
---
apiVersion: networking.k8s.io/v1
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
```

```bash
cat > ~/ckad-mocks/exam-06/q06/migrations.txt <<'EOF'
Deployment: apps/v1beta1 -> apps/v1
Ingress: networking.k8s.io/v1beta1 -> networking.k8s.io/v1
CronJob: batch/v1beta1 -> batch/v1
PodDisruptionBudget: policy/v1beta1 -> policy/v1
HorizontalPodAutoscaler: autoscaling/v2beta1 -> autoscaling/v2
NetworkPolicy: extensions/v1beta1 -> networking.k8s.io/v1
EOF
kubectl apply -f ~/ckad-mocks/exam-06/q06/vintage-stack.yaml
```

**Verify**

```bash
kubectl -n m06-apis get deploy,svc,ingress,cronjob,pdb,hpa,netpol -o name
kubectl -n m06-apis get hpa vintage-web -o jsonpath='{.spec.metrics[0].resource.target}{"\n"}'
```

```text
deployment.apps/vintage-web
service/vintage-web
ingress.networking.k8s.io/vintage-web
cronjob.batch/vintage-report
poddisruptionbudget.policy/vintage-web
horizontalpodautoscaler.autoscaling/vintage-web
networkpolicy.networking.k8s.io/vintage-web-allow-http
{"averageUtilization":70,"type":"Utilization"}
```

**Common mistakes**
- Changing only `apiVersion`. You then get `spec.selector: Required value`, `pathType: Required value` and `unknown field "serviceName"`.
- Leaving the HPA `scaleTargetRef.apiVersion: apps/v1beta1`. The HPA is created but can't find its target (`FailedGetScale`).
- Keeping `kubernetes.io/ingress.class`. It is deprecated, and the task asked for the replacing field.
- Listing the Service in `migrations.txt`. It was never changed.

| Item | Points |
|---|---|
| Deployment apps/v1 with selector | 1 |
| Ingress v1: pathType, service backend, ingressClassName | 1 |
| HPA v2 metric format + scaleTargetRef fixed | 1 |
| CronJob, PDB, NetworkPolicy versions | 1 |
| `migrations.txt` (6 lines) and all 7 objects created | 1 |

---

## Question 7 — StatefulSet: identity, retention and data (8%)

**Approach:** Per-Pod DNS names need the **governing headless Service** named in `spec.serviceName`. That field is immutable, so create a headless Service called `kv-peers` instead of changing the StatefulSet. `persistentVolumeClaimRetentionPolicy` (stable since v1.32) **is** mutable.

```bash
kubectl -n m06-sts get sts kv -o jsonpath='{.spec.serviceName}{"\n"}'      # kv-peers
kubectl -n m06-sts get svc                                                  # only "kv" (ClusterIP)
kubectl -n m06-sts exec dns-client -- nslookup kv-1.kv-peers.m06-sts.svc.cluster.local   # NXDOMAIN
```

```yaml
# q07-kv-peers.yaml — kubectl apply -f q07-kv-peers.yaml
apiVersion: v1
kind: Service
metadata:
  name: kv-peers
  namespace: m06-sts
spec:
  clusterIP: None                  # headless: per-Pod A records
  selector:
    app: kv
  ports:
  - name: redis
    port: 6379
    targetPort: redis
```

```bash
kubectl apply -f q07-kv-peers.yaml
kubectl -n m06-sts exec dns-client -- nslookup kv-1.kv-peers.m06-sts.svc.cluster.local > ~/ckad-mocks/exam-06/q07/dns.txt
#   (CoreDNS may cache the earlier NXDOMAIN for up to ~30 s: repeat if needed)
kubectl -n m06-sts exec kv-2 -- redis-cli SET owner ckad-m06                 # OK

kubectl -n m06-sts patch statefulset kv \
  -p '{"spec":{"persistentVolumeClaimRetentionPolicy":{"whenScaled":"Retain","whenDeleted":"Delete"}}}'
kubectl -n m06-sts scale statefulset kv --replicas=2
kubectl -n m06-sts get pods -w                                               # until kv-2 is gone (Ctrl-C)
kubectl -n m06-sts get pvc > ~/ckad-mocks/exam-06/q07/pvc-after-scale-down.txt
kubectl -n m06-sts scale statefulset kv --replicas=3
kubectl -n m06-sts rollout status statefulset kv
kubectl -n m06-sts exec kv-2 -- redis-cli GET owner > ~/ckad-mocks/exam-06/q07/owner.txt
```

**Verify**

```bash
cat ~/ckad-mocks/exam-06/q07/dns.txt
cat ~/ckad-mocks/exam-06/q07/pvc-after-scale-down.txt
kubectl -n m06-sts get sts kv -o jsonpath='{.spec.persistentVolumeClaimRetentionPolicy} ready={.status.readyReplicas}{"\n"}'
cat ~/ckad-mocks/exam-06/q07/owner.txt
```

```text
Server:		10.96.0.10
Address:	10.96.0.10:53

Name:	kv-1.kv-peers.m06-sts.svc.cluster.local
Address: 10.244.2.31

NAME        STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS   VOLUMEATTRIBUTESCLASS   AGE
data-kv-0   Bound    pvc-0b9c...                                64Mi       RWO            standard       <unset>                 25m
data-kv-1   Bound    pvc-5e21...                                64Mi       RWO            standard       <unset>                 25m
data-kv-2   Bound    pvc-a7f3...                                64Mi       RWO            standard       <unset>                 25m
{"whenDeleted":"Delete","whenScaled":"Retain"} ready=3
ckad-m06
```

(Columns differ slightly between kubectl versions.)

**Common mistakes**
- Editing `spec.serviceName`, which is rejected because the field is immutable. Recreating the StatefulSet is forbidden by the task.
- A Service without `clusterIP: None`, which gives no per-Pod records.
- `whenScaled: Delete`. `data-kv-2` is then deleted on scale-down and `owner` is lost.
- Reading `owner` from `kv-0`. Each replica has its own volume.

| Item | Points |
|---|---|
| Headless Service `kv-peers` selecting the Pods | 2 |
| `dns.txt` shows the resolved per-Pod name | 1 |
| Retention policy whenScaled Retain / whenDeleted Delete | 2 |
| `pvc-after-scale-down.txt` still lists `data-kv-2` | 1 |
| 3/3 ready again and `owner.txt` = `ckad-m06` | 2 |

---

## Question 8 — Kustomize base with dev and prod overlays (7%)

**Approach:** Each overlay references `../../base`. The `configMapGenerator` in the overlay produces `reviews-config-<hash>` (with the prefix), and kustomize rewrites the `configMapRef` in the base Deployment automatically. `replicas:` and `patches` targets use the **base** names (`reviews`). `kubectl diff` exits with code 1 when it finds differences, and that isn't an error.

```bash
cd ~/ckad-mocks/exam-06/q08
mkdir -p overlays/dev overlays/prod
```

```yaml
# overlays/dev/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- ../../base
namespace: m06-dev
namePrefix: dev-
labels:
- pairs:
    env: dev
  includeSelectors: true         # new objects, so selectors may change
configMapGenerator:
- name: reviews-config
  literals:
  - LOG_LEVEL=debug
replicas:
- name: reviews
  count: 1
```

```yaml
# overlays/prod/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- ../../base
namespace: m06-prod
namePrefix: prod-
labels:
- pairs:
    env: prod
  includeSelectors: true
configMapGenerator:
- name: reviews-config
  literals:
  - LOG_LEVEL=warn
replicas:
- name: reviews
  count: 3
images:
- name: nginx
  newTag: 1.27-alpine
patches:
- target:
    kind: Deployment
    name: reviews
  patch: |-
    apiVersion: apps/v1
    kind: Deployment
    metadata:
      name: reviews
    spec:
      template:
        spec:
          containers:
          - name: reviews
            resources:
              requests:
                cpu: 100m
                memory: 64Mi
              limits:
                cpu: 250m
                memory: 128Mi
```

```bash
kubectl kustomize overlays/dev                    # review first
kubectl apply -k overlays/dev
kubectl diff -k overlays/prod > prod-diff.txt; echo "diff exit=$?"       # 1 = differences (expected)
kubectl apply -k overlays/prod
sed -i 's/count: 3/count: 4/' overlays/prod/kustomization.yaml
kubectl diff -k overlays/prod > prod-replicas-diff.txt; echo "diff exit=$?"
kubectl apply -k overlays/prod
```

**Verify**

```bash
kubectl -n m06-dev get deploy,svc,cm
kubectl -n m06-dev exec deploy/dev-reviews -- printenv LOG_LEVEL
kubectl -n m06-prod get deploy prod-reviews -o jsonpath='{.spec.replicas} {.spec.template.spec.containers[0].image} {.spec.template.spec.containers[0].resources}{"\n"}'
kubectl -n m06-prod exec deploy/prod-reviews -- printenv LOG_LEVEL
kubectl -n m06-prod get svc prod-reviews -o jsonpath='{.spec.selector}{"\n"}'
grep -E '^[-+] +replicas:' ~/ckad-mocks/exam-06/q08/prod-replicas-diff.txt
```

```text
NAME                          READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/dev-reviews   1/1     1            1           3m
NAME                  TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)   AGE
service/dev-reviews   ClusterIP   10.96.51.200   <none>        80/TCP    3m
NAME                                       DATA   AGE
configmap/dev-reviews-config-6h7k2b9f4m    1      3m
configmap/kube-root-ca.crt                 1      80m
debug
4 nginx:1.27-alpine {"limits":{"cpu":"250m","memory":"128Mi"},"requests":{"cpu":"100m","memory":"64Mi"}}
warn
{"app":"reviews","env":"prod"}
-  replicas: 3
+  replicas: 4
```

> **Exam tip:** The Kustomize reference site (kubectl.docs.kubernetes.io) is **not** an allowed exam resource. Learn the syntax from the kubernetes.io task page *Declarative Management of Kubernetes Objects Using Kustomize*, which covers generators, `namePrefix`, `labels`, `patches` and overlays.

**Common mistakes**
- Adding the ConfigMap to the base (forbidden), or forgetting the generator. The Pods then sit in `CreateContainerConfigError: configmap "reviews-config" not found`.
- `replicas: - name: prod-reviews`. Use the base name `reviews`.
- Scaling the live Deployment with `kubectl scale`. The next `apply -k` resets it, and the task wants the change in the overlay.
- Treating `kubectl diff` exit code 1 as a failure (0 = no differences, 1 = differences, >1 = error).

| Item | Points |
|---|---|
| dev overlay applied: prefix, namespace, label+selectors, ConfigMap `debug`, 1 replica | 2 |
| prod overlay: namespace, prefix, labels, ConfigMap `warn`, image, resources patch | 3 |
| `prod-diff.txt` captured before the first prod apply | 0.5 |
| 4 replicas set in the overlay, `prod-replicas-diff.txt`, applied | 1.5 |

---

## Question 9 — Fit a Deployment and an HPA into the guard rails (6%)

**Approach:** Two constraints decide the CPU limit: LimitRange `max cpu 500m` and `maxLimitRequestRatio cpu 2`. With a 200m request, the ratio wins, so the limit is **400m**. For `maxReplicas`, divide every quota line by the per-Pod amount and take the minimum:

| Quota line | Hard | Per Pod | Pods that fit |
|---|---|---|---|
| pods | 10 | 1 | 10 |
| requests.cpu | 1000m | 200m | **5** |
| requests.memory | 1024Mi | 128Mi | 8 |
| limits.cpu | 2000m | 400m | **5** |
| limits.memory | 2048Mi | 256Mi | 8 |

So `maxReplicas: 5`.

```bash
kubectl -n m06-hpa describe limitrange bounds
kubectl -n m06-hpa describe resourcequota compute
kubectl -n m06-hpa create deployment search --image=nginx:1.27 --replicas=2 --port=80 $do > q09.yaml
vim q09.yaml                      # container name "web", resources; append the HPA below
```

```yaml
# q09.yaml — kubectl apply -f q09.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: search
  namespace: m06-hpa
  labels:
    app: search
spec:
  replicas: 2
  selector:
    matchLabels:
      app: search
  template:
    metadata:
      labels:
        app: search
    spec:
      containers:
      - name: web
        image: nginx:1.27
        ports:
        - containerPort: 80
        resources:
          requests:
            cpu: 200m
            memory: 128Mi
          limits:
            cpu: 400m             # max allowed: request x maxLimitRequestRatio (2)
            memory: 256Mi
---
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: search
  namespace: m06-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: search
  minReplicas: 2
  maxReplicas: 5
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 60
  behavior:
    scaleDown:
      stabilizationWindowSeconds: 120
```

```bash
kubectl apply -f q09.yaml
echo 5 > ~/ckad-mocks/exam-06/q09/max-replicas.txt
```

Imperative HPA alternative: `kubectl -n m06-hpa autoscale deployment search --min=2 --max=5 --cpu=60%` (older kubectl: `--cpu-percent=60`; check `kubectl autoscale --help`), then `kubectl edit hpa search` to add `behavior`.

**Verify**

```bash
kubectl -n m06-hpa get deploy search -o jsonpath='{.status.readyReplicas}/{.spec.replicas} {.spec.template.spec.containers[0].resources}{"\n"}'
kubectl -n m06-hpa get hpa search -o jsonpath='{.spec.minReplicas}-{.spec.maxReplicas} {.spec.metrics[0].resource.target.averageUtilization}% {.spec.behavior.scaleDown.stabilizationWindowSeconds}s{"\n"}'
cat ~/ckad-mocks/exam-06/q09/max-replicas.txt
kubectl -n m06-hpa get hpa search          # TARGETS shows cpu: x%/60% once metrics-server reports
```

```text
2/2 {"limits":{"cpu":"400m","memory":"256Mi"},"requests":{"cpu":"200m","memory":"128Mi"}}
2-5 60% 120s
5
NAME     REFERENCE           TARGETS       MINPODS   MAXPODS   REPLICAS   AGE
search   Deployment/search   cpu: 0%/60%   2         5         2          1m
```

**Common mistakes**
- CPU limit `500m`. The ratio is then 2.5 and LimitRanger rejects every Pod (`cpu max limit to request ratio per Container is 2, but provided ratio is 2.500000`); the events are on the ReplicaSet.
- `maxReplicas: 10` or `8`. Scale-ups beyond 5 Pods would fail with `exceeded quota`.
- `autoscaling/v1`, which has no `behavior` and no `metrics` list.
- Keeping the generated container name `nginx`.

| Item | Points |
|---|---|
| Deployment 2/2, container `web`, requests 200m/128Mi, memory limit 256Mi | 1.5 |
| CPU limit 400m | 1 |
| HPA autoscaling/v2: min 2, CPU 60%, scale-down window 120 s | 2 |
| `maxReplicas: 5` in the HPA and in the file | 1.5 |

---

## Question 10 — Make the shop reachable (12%)

**Approach:** Walk the request path and fix one layer at a time: controller → Ingress → Service → EndpointSlice → Pod (image, readiness) → NetworkPolicy. The HTTP status from the controller tells you where you are:

| Symptom (ingress-nginx) | Usual layer |
|---|---|
| 404 from the controller | Host/path doesn't match any Ingress rule, or wrong ingressClassName |
| 503 | Ingress backend Service/port not found, or no ready endpoints |
| 504 after a few seconds | Endpoints exist but packets are dropped (NetworkPolicy) or the Pod doesn't listen |

```bash
ING=http://localhost:8080            # kit kind lab; minikube: http://$(minikube ip)
curl -s -o /dev/null -w '%{http_code}\n' -H 'Host: shop.m06.local' $ING/      # 503
kubectl -n m06-shop get deploy,rs,pods,svc,endpointslices,ingress,netpol

# fault 1: image tag typo -> ErrImagePull / ImagePullBackOff
kubectl -n m06-shop describe pod -l app=storefront | grep -m1 'Failed to pull image'
kubectl -n m06-shop set image deployment/storefront web=nginx:1.27-alpine

# fault 2: Pods Running but 0/1 Ready
kubectl -n m06-shop describe pod -l app=storefront | grep -m1 'Readiness probe failed'   # HTTP probe failed with statuscode: 404
kubectl -n m06-shop patch deployment storefront --type=json \
  -p='[{"op":"replace","path":"/spec/template/spec/containers/0/readinessProbe/httpGet/path","value":"/healthz"}]'
kubectl -n m06-shop rollout status deployment storefront

# fault 3: Service selects nothing
kubectl -n m06-shop get endpointslices -l kubernetes.io/service-name=storefront   # ENDPOINTS <unset>
kubectl -n m06-shop get svc storefront -o jsonpath='{.spec.selector}{"\n"}'          # {"app":"store-front"}
kubectl -n m06-shop patch service storefront -p '{"spec":{"selector":{"app":"storefront"}}}'

# fault 4: Ingress points to a Service port that doesn't exist
kubectl -n m06-shop get ingress storefront -o jsonpath='{.spec.rules[0].http.paths[0].backend.service.port}{"\n"}'   # {"number":8080}
kubectl -n m06-shop patch ingress storefront --type=json \
  -p='[{"op":"replace","path":"/spec/rules/0/http/paths/0/backend/service/port/number","value":80}]'

# fault 5: the policy allows a namespace label that does not exist (504 now)
kubectl get namespace ingress-nginx --show-labels          # kubernetes.io/metadata.name=ingress-nginx, no "name" label
kubectl -n m06-shop patch networkpolicy allow-ingress-controller --type=json \
  -p='[{"op":"replace","path":"/spec/ingress/0/from/0/namespaceSelector/matchLabels","value":{"kubernetes.io/metadata.name":"ingress-nginx"}}]'

curl -s -H 'Host: shop.m06.local' $ING/ > ~/ckad-mocks/exam-06/q10/response.txt
cat > ~/ckad-mocks/exam-06/q10/faults.txt <<'EOF'
Deployment storefront: image tag typo nginx:1.27-alpne -> nginx:1.27-alpine
Deployment storefront: readinessProbe path /health (404) -> /healthz
Service storefront: selector app=store-front matched no Pods -> app=storefront
Ingress storefront: backend port 8080 does not exist on the Service -> 80
NetworkPolicy allow-ingress-controller: namespaceSelector name=ingress-nginx matches nothing -> kubernetes.io/metadata.name=ingress-nginx
EOF
```

The two fixed networking objects:

```yaml
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
              number: 80
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
          kubernetes.io/metadata.name: ingress-nginx
    ports:
    - protocol: TCP
      port: 80
```

**Verify**

```bash
cat ~/ckad-mocks/exam-06/q10/response.txt
kubectl -n m06-shop get pods -l app=storefront
kubectl -n m06-shop get endpointslices -l kubernetes.io/service-name=storefront
kubectl -n m06-shop get netpol default-deny-ingress -o jsonpath='{.spec}{"\n"}'
```

```text
storefront: OK
NAME                          READY   STATUS    RESTARTS   AGE
storefront-6c9d7f8b5-4xk2p    1/1     Running   0          4m
storefront-6c9d7f8b5-vb8rt    1/1     Running   0          4m
NAME               ADDRESSTYPE   PORTS   ENDPOINTS                 AGE
storefront-7mwkd   IPv4          80      10.244.1.33,10.244.2.41   60m
{"podSelector":{},"policyTypes":["Ingress"]}
```

**Common mistakes**
- Deleting or loosening `default-deny-ingress`, or allowing `namespaceSelector: {}` (every namespace). Both break the constraints.
- Changing the Service port to 8080 instead of fixing the Ingress. The Service must keep port 80.
- Removing the readiness probe "to make it Ready". The fault was the path; without a probe, broken Pods would receive traffic.
- Testing only from a Pod in `m06-shop`. `default-deny-ingress` blocks that path on purpose; test through the controller.
- If your controller runs with `hostNetwork: true`, its traffic comes from node IPs, not from Pods in its namespace. The kit lab uses hostPort, which keeps the Pod IP, so the namespace selector works.

| Item | Points |
|---|---|
| Image tag fixed | 2 |
| Readiness probe path `/healthz` | 2 |
| Service selector `app=storefront` | 2 |
| Ingress backend port 80 | 2 |
| NetworkPolicy namespace selector fixed, default deny untouched | 2 |
| `response.txt` = `storefront: OK` | 1 |
| `faults.txt` lists the 5 faults | 1 |

---

## Question 11 — Configuration precedence and file projection (5%)

**Approach:** Precedence: an explicit `env` entry beats `envFrom`. Among `envFrom` sources, the **last** source wins for duplicate keys, so without the explicit entry `LOG_LEVEL` would come from the Secret (`debug`). Use `subPath` to drop one file into an existing directory without hiding the image's files. Use `items[].mode` for a per-file mode.

```yaml
# q11.yaml — kubectl apply -f q11.yaml
apiVersion: v1
kind: Pod
metadata:
  name: web-config
  namespace: m06-config
spec:
  containers:
  - name: web
    image: nginx:1.27-alpine
    envFrom:
    - configMapRef:
        name: app-env
    - secretRef:
        name: app-secret           # listed last -> wins over app-env for LOG_LEVEL
    env:
    - name: LOG_LEVEL              # explicit env beats both envFrom sources
      value: warn
    - name: DB_PASS
      valueFrom:
        secretKeyRef:
          name: app-secret
          key: DB_PASSWORD
    volumeMounts:
    - name: extra
      mountPath: /etc/nginx/conf.d/gzip.conf
      subPath: gzip.conf           # only this file; default.conf stays visible
    - name: token
      mountPath: /etc/secrets
      readOnly: true
  volumes:
  - name: extra
    configMap:
      name: nginx-extra
  - name: token
    secret:
      secretName: app-secret
      items:
      - key: API_TOKEN
        path: api/token
        mode: 0440                 # YAML octal; JSON would need decimal 288
```

```bash
kubectl apply -f q11.yaml
kubectl -n m06-config exec web-config -- sh -c "env | sort | grep -E '^(LOG_LEVEL|FEATURE_X|REGION|API_TOKEN|DB_PASS)='" \
  > ~/ckad-mocks/exam-06/q11/env.txt
echo debug > ~/ckad-mocks/exam-06/q11/precedence.txt
```

**Verify**

```bash
cat ~/ckad-mocks/exam-06/q11/env.txt ~/ckad-mocks/exam-06/q11/precedence.txt
kubectl -n m06-config exec web-config -- ls /etc/nginx/conf.d
kubectl -n m06-config exec web-config -- nginx -T 2>/dev/null | grep -m1 'gzip on'
kubectl -n m06-config exec web-config -- stat -L -c '%a %n' /etc/secrets/api/token
kubectl -n m06-config exec web-config -- ls /etc/secrets /etc/secrets/api
```

```text
API_TOKEN=tok-m06-123
DB_PASS=m06-pa55
FEATURE_X=on
LOG_LEVEL=warn
REGION=eu-west-1
debug
default.conf
gzip.conf
gzip on;
440 /etc/secrets/api/token
/etc/secrets:
api

/etc/secrets/api:
token
```

(`ls -a` would also show the Secret volume's internal `..data` symlinks. Those are how the kubelet swaps updated files atomically.)

**Common mistakes**
- Mounting the ConfigMap at `/etc/nginx/conf.d` without `subPath`. That hides `default.conf`, and nginx stops serving port 80.
- Reversing the `envFrom` order, which makes `precedence.txt` = `info`.
- `defaultMode` instead of the per-item `mode`. Both work here because there is only one item, but know the difference.
- Forgetting that `subPath` mounts never receive ConfigMap updates. Restart the Pod after changing `nginx-extra`.

| Item | Points |
|---|---|
| `envFrom` ConfigMap then Secret; explicit `LOG_LEVEL=warn`; `DB_PASS` | 1.5 |
| `gzip.conf` via subPath, `default.conf` still present | 1 |
| Only `API_TOKEN` at `/etc/secrets/api/token`, mode 0440 | 1 |
| `env.txt` correct | 1 |
| `precedence.txt` = `debug` | 0.5 |

---

## Question 12 — A rollout that the quota blocks (3%)

**Approach:** With `maxSurge: 1` / `maxUnavailable: 0`, the controller must create Pod number 5 before it may remove an old one. The quota refuses it, and the rollout hangs forever (`FailedCreate ... exceeded quota` on the new ReplicaSet). `maxSurge: 0` / `maxUnavailable: 1` replaces one Pod at a time inside the 4-Pod budget and keeps at least 3 available.

```bash
kubectl -n m06-rollout describe resourcequota pod-cap              # pods 4/4
kubectl -n m06-rollout patch deployment edge-api \
  -p '{"spec":{"strategy":{"rollingUpdate":{"maxSurge":0,"maxUnavailable":1}}}}'
kubectl -n m06-rollout set image deployment/edge-api api=nginx:1.27-alpine
kubectl -n m06-rollout rollout status deployment edge-api
kubectl -n m06-rollout annotate deployment edge-api kubernetes.io/change-cause='nginx 1.27-alpine within pod quota' --overwrite
kubectl -n m06-rollout rollout history deployment edge-api > ~/ckad-mocks/exam-06/q12/history.txt
```

If you set the image first, you'll see the hang. `kubectl -n m06-rollout describe rs -l app=edge-api | grep -m1 'exceeded quota'` shows `... forbidden: exceeded quota: pod-cap, requested: pods=1, used: pods=4, limited: pods=4`. Patching the strategy afterwards un-sticks it.

**Verify**

```bash
kubectl -n m06-rollout get deploy edge-api -o jsonpath='{.spec.template.spec.containers[0].image} {.status.updatedReplicas}/{.spec.replicas} {.spec.strategy.rollingUpdate}{"\n"}'
cat ~/ckad-mocks/exam-06/q12/history.txt
```

```text
nginx:1.27-alpine 4/4 {"maxSurge":0,"maxUnavailable":1}
deployment.apps/edge-api
REVISION  CHANGE-CAUSE
1         <none>
2         nginx 1.27-alpine within pod quota
```

**Common mistakes**
- Raising the quota (forbidden).
- `strategy: Recreate`. All 4 Pods go down at once, which breaks "at least 3 available".
- `maxUnavailable: 2`, which allows dropping to 2 available.

| Item | Points |
|---|---|
| Rollout complete: 4/4 on `nginx:1.27-alpine`, quota unchanged | 1.5 |
| Strategy that fits the quota and keeps ≥ 3 available | 1 |
| Change-cause + `history.txt` | 0.5 |

---

## Question 13 — Resource report and merged logs (6%)

**Approach:** `kubectl top` needs metrics-server. Custom columns accept `[*]` to list all containers. `kubectl logs deploy/x` reads **one** Pod only, so use the label selector with `--prefix --timestamps --tail=-1`, then sort by the timestamp column (RFC 3339 timestamps sort lexically).

```bash
kubectl -n m06-fleet top pod --sort-by=cpu
kubectl -n m06-fleet top pod --sort-by=cpu --no-headers | head -1 | awk '{print $1}' > ~/ckad-mocks/exam-06/q13/top-cpu.txt

kubectl -n m06-fleet get pods --sort-by=.metadata.name \
  -o custom-columns='NAME:.metadata.name,NODE:.spec.nodeName,QOS:.status.qosClass,RESTARTS:.status.containerStatuses[*].restartCount,IMAGES:.spec.containers[*].image' \
  > ~/ckad-mocks/exam-06/q13/report.txt

kubectl -n m06-fleet logs -l app=svc-b --prefix --timestamps --tail=-1 | sort -k2,2 > ~/ckad-mocks/exam-06/q13/svc-b.log
```

**Verify**

```bash
cat ~/ckad-mocks/exam-06/q13/top-cpu.txt
head -4 ~/ckad-mocks/exam-06/q13/report.txt
cut -d' ' -f1 ~/ckad-mocks/exam-06/q13/svc-b.log | sort | uniq -c
awk '{print $2}' ~/ckad-mocks/exam-06/q13/svc-b.log | sort -c && echo chronological
```

```text
cpu-burner-5b7c9d8f6-tq2lm
NAME                          NODE           QOS          RESTARTS   IMAGES
batch-1                       ckad-worker    BestEffort   0          busybox:1.36
batch-2                       ckad-worker2   BestEffort   0          busybox:1.36
batch-3                       ckad-worker    BestEffort   0          busybox:1.36
    310 [pod/svc-b-7d4f8c9b6-2mzkq/app]
    310 [pod/svc-b-7d4f8c9b6-h8w5d/app]
    310 [pod/svc-b-7d4f8c9b6-xq7rn/app]
chronological
```

**Common mistakes**
- `kubectl logs deployment/svc-b`, which gives one Pod's log only.
- Leaving out `--tail=-1`. With a selector, kubectl shows only the last 10 lines per container.
- `sort` on the whole line, which sorts by Pod name, not by time.
- `.status.containerStatuses.restartCount` without `[*]`, which prints `<none>`.

| Item | Points |
|---|---|
| `top-cpu.txt` = the cpu-burner Pod | 2 |
| `report.txt`: 5 columns, sorted by name | 2 |
| `svc-b.log`: all 3 Pods, prefixed, timestamped, chronological, complete | 2 |

---

## Question 14 — Enforce the restricted profile (4%)

**Approach:** Labelling a namespace with an `enforce` level makes the API server check the **existing** Pods and print warnings. It doesn't evict them, but every **new** Pod must comply. Preview without changing anything with `kubectl label --dry-run=server --overwrite ns m06-psa pod-security.kubernetes.io/enforce=restricted`.

```bash
kubectl label namespace m06-psa --overwrite \
  pod-security.kubernetes.io/enforce=restricted pod-security.kubernetes.io/enforce-version=latest \
  pod-security.kubernetes.io/warn=restricted pod-security.kubernetes.io/warn-version=latest \
  2> ~/ckad-mocks/exam-06/q14/warnings.txt
cat ~/ckad-mocks/exam-06/q14/warnings.txt          # exact wording varies slightly between versions:
# Warning: existing pods in namespace "m06-psa" violate the new PodSecurity enforce level "restricted:latest"
# Warning: metrics-api-6f9b8c7d5-abcde (and 1 other pod): hostPath volumes, allowPrivilegeEscalation != false, unrestricted capabilities, restricted volume types, runAsNonRoot != true, seccompProfile
kubectl -n m06-psa edit deployment metrics-api
```

```yaml
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
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
        seccompProfile:
          type: RuntimeDefault
      containers:
      - name: api
        image: busybox:1.36
        command: ["sh", "-c", "mkdir -p /tmp/www && echo 'metrics-api ok' > /tmp/www/index.html && exec httpd -f -p 8080 -h /tmp/www"]
        ports:
        - name: http
          containerPort: 8080
        securityContext:
          allowPrivilegeEscalation: false
          capabilities:
            drop: ["ALL"]          # NET_ADMIN removed - only NET_BIND_SERVICE may be added
        volumeMounts:
        - name: node-logs
          mountPath: /logs
      volumes:
      - name: node-logs
        emptyDir: {}               # hostPath is not allowed under restricted (or baseline)
```

```bash
kubectl -n m06-psa rollout status deployment metrics-api
kubectl -n m06-psa exec deploy/metrics-api -- wget -qO- http://localhost:8080
```

**Verify**

```bash
kubectl get namespace m06-psa -o jsonpath='{.metadata.labels}{"\n"}'
kubectl -n m06-psa get rs -l app=metrics-api
kubectl -n m06-psa exec deploy/metrics-api -- sh -c 'id -u; wget -qO- http://localhost:8080'
```

```text
{"ckad-mock":"exam-06","kubernetes.io/metadata.name":"m06-psa","pod-security.kubernetes.io/enforce":"restricted","pod-security.kubernetes.io/enforce-version":"latest","pod-security.kubernetes.io/warn":"restricted","pod-security.kubernetes.io/warn-version":"latest"}
NAME                     DESIRED   CURRENT   READY   AGE
metrics-api-6f9b8c7d5    0         0         0       50m
metrics-api-7c8d9e6f4    2         2         2       2m
1000
metrics-api ok
```

**Common mistakes**
- Expecting the old Pods to die after labelling. They keep running; only replacements are checked. The fix must therefore be rolled out, and the ReplicaSet events show any remaining violation (`FailedCreate ... violates PodSecurity`).
- Keeping `add: ["NET_ADMIN"]` next to `drop: ["ALL"]`. It is still a violation.
- Leaving out `runAsUser`. busybox defaults to root, and httpd needs a writable dir and a port above 1024 as non-root, both of which you already have.
- Labelling only `enforce` and forgetting `warn` or the `-version` labels.

| Item | Points |
|---|---|
| enforce + warn = restricted, both versions `latest` | 1 |
| `warnings.txt` contains the label warnings | 0.5 |
| Deployment template restricted-compliant, hostPath → emptyDir | 2 |
| 2 new Pods Running and serving | 0.5 |

---

## Question 15 — Blue/green at the Ingress (4%)

**Approach:** Blue/green at the edge means you switch the Ingress backend while both versions keep running. The trap: `tracker-green` listens on Service port **8080**, so changing only the name gives a 503.

```bash
kubectl -n m06-bluegreen get svc                     # tracker-blue 80/TCP, tracker-green 8080/TCP
kubectl -n m06-bluegreen patch ingress tracker --type=json \
  -p='[{"op":"replace","path":"/spec/rules/0/http/paths/0/backend/service","value":{"name":"tracker-green","port":{"number":8080}}}]'
curl -s -H 'Host: tracker.m06.local' http://localhost:8080/ > ~/ckad-mocks/exam-06/q15/after-switch.txt
cat > ~/ckad-mocks/exam-06/q15/rollback-cmd.txt <<'EOF'
kubectl -n m06-bluegreen patch ingress tracker --type=json -p='[{"op":"replace","path":"/spec/rules/0/http/paths/0/backend/service","value":{"name":"tracker-blue","port":{"number":80}}}]'
EOF
```

**Verify**

```bash
cat ~/ckad-mocks/exam-06/q15/after-switch.txt
for d in tracker-blue tracker-green; do
  [ "$(kubectl -n m06-bluegreen get deploy $d -o jsonpath='{.metadata.generation}')" = "$(cat ~/ckad-mocks/exam-06/.state/q15-$d-deploy-gen)" ] &&
  [ "$(kubectl -n m06-bluegreen get svc $d -o jsonpath='{.metadata.resourceVersion}')" = "$(cat ~/ckad-mocks/exam-06/.state/q15-$d-svc-rv)" ] &&
  echo "$d untouched"
done
kubectl -n m06-bluegreen get deploy tracker-blue
```

```text
tracker: green
tracker-blue untouched
tracker-green untouched
NAME           READY   UP-TO-DATE   AVAILABLE   AGE
tracker-blue   2/2     2            2           70m
```

**Common mistakes**
- Changing only the Service name and keeping port 80, which gives a 503.
- Editing the Services' selectors. That is blue/green at the Service layer, and the task forbids it.
- Scaling blue to 0. The task says keep it running, because it is the instant rollback.
- A rollback command that changes only the name (port 8080 doesn't exist on `tracker-blue`).

| Item | Points |
|---|---|
| Ingress backend `tracker-green:8080` | 2 |
| Services/Deployments untouched, blue still running | 1 |
| `after-switch.txt` + correct `rollback-cmd.txt` | 1 |

---

## Question 16 — Find your way around an operator (3%)

**Approach:** An operator is a CRD plus a controller with RBAC. Follow the chain CRD → ClusterRole that grants `update` → ClusterRoleBinding → ServiceAccount → the Deployment that runs as that SA. The decoy `flag-dashboard` can only read.

```bash
kubectl get crd featureflags.flags.m06.ckad.io \
  -o jsonpath='{range .spec.versions[*]}{.name} served={.served} storage={.storage} deprecated={.deprecated}{"\n"}{end}'
# v1alpha1 served=true storage=false deprecated=true
# v1 served=true storage=true deprecated=
echo "deprecated=v1alpha1 storage=v1" > ~/ckad-mocks/exam-06/q16/versions.txt

kubectl get featureflags -A -o custom-columns=NS:.metadata.namespace,NAME:.metadata.name --no-headers \
  | awk '{print $1"/"$2}' | sort > ~/ckad-mocks/exam-06/q16/flags.txt

kubectl get clusterrolebindings -o custom-columns='NAME:.metadata.name,ROLE:.roleRef.name,SA:.subjects[*].name,NS:.subjects[*].namespace' | grep -i flag
kubectl describe clusterrole m06-flag-operator | grep featureflags        # ... [get list watch update patch]
kubectl auth can-i update featureflags.flags.m06.ckad.io -A --as=system:serviceaccount:m06-flags-system:flag-operator   # yes
kubectl auth can-i update featureflags.flags.m06.ckad.io -A --as=system:serviceaccount:m06-flags-system:flag-ui         # no
kubectl get deploy -A -o custom-columns='NS:.metadata.namespace,NAME:.metadata.name,SA:.spec.template.spec.serviceAccountName' | grep flag-
# m06-flags-system   flag-controller   flag-operator
# m06-flags-system   flag-dashboard    flag-ui
echo m06-flags-system/flag-controller > ~/ckad-mocks/exam-06/q16/operator.txt
```

```yaml
# q16-fast-search.yaml — kubectl apply -f q16-fast-search.yaml
apiVersion: flags.m06.ckad.io/v1
kind: FeatureFlag
metadata:
  name: fast-search
  namespace: m06-team-a
spec:
  enabled: true
  rolloutPercent: 25
  owner: team-a
```

**Verify**

```bash
cat ~/ckad-mocks/exam-06/q16/versions.txt ~/ckad-mocks/exam-06/q16/flags.txt ~/ckad-mocks/exam-06/q16/operator.txt
kubectl get ff -A
kubectl -n m06-team-a get featureflags.v1alpha1.flags.m06.ckad.io fast-search     # served, but warns
```

```text
deprecated=v1alpha1 storage=v1
m06-team-a/dark-mode
m06-team-b/beta-search
m06-team-b/new-checkout
m06-flags-system/flag-controller
NAMESPACE    NAME           ENABLED   ROLLOUT   OWNER
m06-team-a   dark-mode      true      100       team-a
m06-team-a   fast-search    true      25        team-a
m06-team-b   beta-search    true      10        team-b
m06-team-b   new-checkout   false     0         team-b
Warning: flags.m06.ckad.io/v1alpha1 FeatureFlag is deprecated; use flags.m06.ckad.io/v1
NAME          AGE
fast-search   1m
```

**Common mistakes**
- Answering with the ServiceAccount name (`flag-operator`). The task asked for the Deployment (`flag-controller`).
- Picking `flag-dashboard`. Its ClusterRole has no `update`.
- Writing `flags.txt` after creating `fast-search`. The task asked for the list before step 4.
- Creating the CR as `v1alpha1`. It is accepted, but with a deprecation warning, and the task required the non-deprecated version.

| Item | Points |
|---|---|
| `versions.txt` | 0.5 |
| `flags.txt` (3 lines, sorted) | 0.5 |
| `operator.txt` = `m06-flags-system/flag-controller` | 1 |
| `fast-search` created via `flags.m06.ckad.io/v1` | 1 |

---

## Question 17 — Build, tag, save, and write a manifest (5%)

**Approach:** The kubelet can only verify `runAsNonRoot` for a **numeric** image user. With `USER tally`, the Pod fails with `container has runAsNonRoot and image has non-numeric user (tally), cannot verify user is non-root`. Use the UID that the Dockerfile creates (10001). Generate the Pod manifest with `kubectl run --dry-run=client`, then add what `run` can't set.

```bash
cd ~/ckad-mocks/exam-06/q17
sed -i 's/^USER tally$/USER 10001/' Dockerfile
podman build -t tally:2.1.0 .
podman tag tally:2.1.0 registry.m06.local:5000/tally:2.1.0
podman save --format docker-archive -o ~/ckad-mocks/exam-06/q17/tally-2.1.0.tar registry.m06.local:5000/tally:2.1.0
# docker: docker build -t tally:2.1.0 . && docker tag tally:2.1.0 registry.m06.local:5000/tally:2.1.0
#         docker save -o ~/ckad-mocks/exam-06/q17/tally-2.1.0.tar registry.m06.local:5000/tally:2.1.0

kubectl -n m06-build run tally --image=registry.m06.local:5000/tally:2.1.0 --image-pull-policy=IfNotPresent \
  --port=8080 --env=APP_VERSION=2.1.0 --dry-run=client -o yaml > ~/ckad-mocks/exam-06/q17/tally-pod.yaml
vim ~/ckad-mocks/exam-06/q17/tally-pod.yaml
kubectl apply --dry-run=server -f ~/ckad-mocks/exam-06/q17/tally-pod.yaml      # pod/tally created (server dry run)
```

```yaml
# ~/ckad-mocks/exam-06/q17/tally-pod.yaml
apiVersion: v1
kind: Pod
metadata:
  name: tally
  namespace: m06-build
  labels:
    run: tally
spec:
  securityContext:
    runAsNonRoot: true             # works because the image USER is numeric (10001)
  containers:
  - name: tally
    image: registry.m06.local:5000/tally:2.1.0
    imagePullPolicy: IfNotPresent
    env:
    - name: APP_VERSION
      value: "2.1.0"
    ports:
    - name: http
      containerPort: 8080
    readinessProbe:
      httpGet:
        path: /
        port: http
    securityContext:
      allowPrivilegeEscalation: false
```

**Verify**

```bash
grep '^USER' ~/ckad-mocks/exam-06/q17/Dockerfile
podman images --format '{{.Repository}}:{{.Tag}}' | grep tally
podman image inspect --format '{{.Config.User}}' registry.m06.local:5000/tally:2.1.0
tar -tf ~/ckad-mocks/exam-06/q17/tally-2.1.0.tar | grep -E '^(manifest.json|repositories)$'
kubectl apply --dry-run=server -f ~/ckad-mocks/exam-06/q17/tally-pod.yaml
kubectl -n m06-build get pods
```

```text
USER 10001
localhost/tally:2.1.0
registry.m06.local:5000/tally:2.1.0
10001
manifest.json
repositories
pod/tally created (server dry run)
No resources found in m06-build namespace.
```

Optional end-to-end test in the kit's kind lab (then delete the Pod again, because task 5 wants none):

```bash
kind load image-archive ~/ckad-mocks/exam-06/q17/tally-2.1.0.tar --name ckad
kubectl apply -f ~/ckad-mocks/exam-06/q17/tally-pod.yaml
kubectl -n m06-build wait --for=condition=Ready pod/tally --timeout=60s && kubectl -n m06-build logs tally
# tally 2.1.0 listening on :8080 as uid 10001
kubectl -n m06-build delete pod tally
```

**Common mistakes**
- Keeping `USER tally`. The Pod can never start with `runAsNonRoot: true` alone.
- Saving `tally:2.1.0` instead of the registry tag, or saving in OCI format (`--format oci-archive`) when docker-archive was asked.
- `imagePullPolicy: Always`. In a real cluster the kubelet would try to pull from `registry.m06.local`, which doesn't exist (`ErrImagePull`).
- Applying the manifest for real. `--dry-run=server` validates everything (schema, admission) but persists nothing.

| Item | Points |
|---|---|
| Dockerfile `USER 10001` (only that line changed) | 1 |
| Image built and tagged twice | 1 |
| docker-archive `tally-2.1.0.tar` of the registry tag | 1 |
| Manifest complete and passes `--dry-run=server` | 1.5 |
| No Pod `tally` in `m06-build` | 0.5 |

---

## Scoring table

| Question | Topic | Weight | Your score |
|---|---|---|---|
| 1 | Crash-looping container via JSONPath | 4 | |
| 2 | Init + native sidecar under restricted PSA | 7 | |
| 3 | Helm bad upgrade, rollback, leftover release | 6 | |
| 4 | CronJob + ServiceAccount token + RBAC | 7 | |
| 5 | NetworkPolicy AND/OR, ipBlock, DNS | 8 | |
| 6 | Removed APIs in a multi-document manifest | 5 | |
| 7 | StatefulSet headless DNS + PVC retention | 8 | |
| 8 | Kustomize base + dev/prod overlays + diff | 7 | |
| 9 | LimitRange + ResourceQuota + HPA v2 | 6 | |
| 10 | Broken end-to-end stack (5 faults) | 12 | |
| 11 | envFrom precedence, subPath, Secret items | 5 | |
| 12 | Rolling update inside a Pod quota | 3 | |
| 13 | `kubectl top`, custom columns, merged logs | 6 | |
| 14 | Pod Security Admission restricted | 4 | |
| 15 | Blue/green via the Ingress backend | 4 | |
| 16 | CRD/operator discovery | 3 | |
| 17 | Image build/tag/save + manifest | 5 | |
| **Total** | | **100** | |

**66+ on this paper is a strong readiness signal.** 50–65 is normal for a first attempt at a killer.sh-style paper: review every miss and retake it in two days. Below 50, the real exam is still within reach: work through the study map below, then mock 05.

## If you missed it → study

| Missed question(s) | Revise | Where |
|---|---|---|
| 17 | Dockerfile USER, podman build/tag/save, docker-archive | [01 — Application Design and Build](../../01-Application-Design-and-Build/README.md) |
| 2 | Native sidecars, init order, emptyDir sizeLimit | [01 — Application Design and Build](../../01-Application-Design-and-Build/README.md) |
| 7 | StatefulSets, headless Services, volumeClaimTemplates, PVC retention | [01 — Application Design and Build](../../01-Application-Design-and-Build/README.md) · [05 — Services and Networking](../../05-Services-and-Networking/README.md) |
| 15 | Blue/green switch points (Service vs Ingress) | [02 — Application Deployment](../../02-Application-Deployment/README.md) |
| 12 | maxSurge/maxUnavailable, rollout history, change-cause | [02 — Application Deployment](../../02-Application-Deployment/README.md) |
| 3 | helm upgrade -f, rollback to a revision, list -A, uninstall | [02 — Application Deployment](../../02-Application-Deployment/README.md) |
| 8 | Overlays, generators, namePrefix, images, replicas, patches, kubectl diff -k | [02 — Application Deployment](../../02-Application-Deployment/README.md) |
| 6 | Deprecated API migration, `kubectl explain --api-version` | [03 — Application Observability and Maintenance](../../03-Application-Observability-and-Maintenance/README.md) |
| 1, 10 | Termination reasons, `logs --previous`, layer-by-layer debugging | [03 — Application Observability and Maintenance](../../03-Application-Observability-and-Maintenance/README.md) |
| 13 | `kubectl top`, custom columns, `logs -l --prefix --timestamps` | [03 — Application Observability and Maintenance](../../03-Application-Observability-and-Maintenance/README.md) · [06 — Cross-Cutting Skills and Bonus Topics](../../06-Cross-Cutting-Skills-and-Bonus-Topics/README.md) |
| 4 | ServiceAccount tokens, Roles, RoleBindings, CronJob templates | [04 — Application Environment, Configuration and Security](../../04-Application-Environment-Configuration-and-Security/README.md) |
| 9 | LimitRange (max, ratio), ResourceQuota maths, HPA v2 | [04 — Application Environment, Configuration and Security](../../04-Application-Environment-Configuration-and-Security/README.md) · [06 — Cross-Cutting Skills and Bonus Topics](../../06-Cross-Cutting-Skills-and-Bonus-Topics/README.md) |
| 11 | envFrom precedence, subPath, Secret items/mode | [04 — Application Environment, Configuration and Security](../../04-Application-Environment-Configuration-and-Security/README.md) |
| 2, 14 | Pod Security Admission levels and labels, securityContext | [04 — Application Environment, Configuration and Security](../../04-Application-Environment-Configuration-and-Security/README.md) |
| 16 | CRD versions, operators, RBAC discovery | [04 — Application Environment, Configuration and Security](../../04-Application-Environment-Configuration-and-Security/README.md) |
| 5 | NetworkPolicy peers (AND/OR), ipBlock/except, DNS egress | [05 — Services and Networking](../../05-Services-and-Networking/README.md) |
| 10, 15 | Ingress backends, Service selectors/ports, EndpointSlices | [05 — Services and Networking](../../05-Services-and-Networking/README.md) |
| "why would I do it this way?" | Operators, guard rails, progressive delivery in production | [08 — Architect Notes](../../08-Architect-Notes/README.md) |

## Coverage matrix

All 24 competencies of the official curriculum are exercised.

| Domain | Competency | Questions |
|---|---|---|
| Application Design and Build | Define, build and modify container images | 17 |
| | Choose and use the right workload resource (Deployment, DaemonSet, CronJob, etc.) | 7 (StatefulSet), 4 (CronJob), 9 (Deployment + HPA) |
| | Understand multi-container Pod design patterns (e.g. sidecar, init and others) | 2 (init + native sidecar), 1 (two-container Pod) |
| | Utilize persistent and ephemeral volumes | 7 (volumeClaimTemplates), 2 (emptyDir sizeLimit), 11 (ConfigMap/Secret volumes, subPath) |
| Application Deployment | Use Kubernetes primitives to implement common deployment strategies (e.g. blue/green or canary) | 15 |
| | Understand Deployments and how to perform rolling updates | 12, 14, 1 (`rollout restart`) |
| | Use the Helm package manager to deploy existing packages | 3 |
| | Kustomize | 8 |
| Application Observability and Maintenance | Understand API deprecations | 6, 16 (deprecated CRD version) |
| | Implement probes and health checks | 10 (readiness fix), 17 (readiness probe in the manifest), 7 (exec readiness) |
| | Use built-in CLI tools to monitor Kubernetes applications | 13 (`top`, custom columns), 1 (JSONPath) |
| | Utilize container logs | 13, 1 (`--previous`), 4 |
| | Debugging in Kubernetes | 10, 1, 3 |
| Application Environment, Configuration and Security | Discover and use resources that extend Kubernetes (CRD, Operators) | 16 |
| | Understand authentication, authorization and admission control | 4 (RBAC + SA token), 14 (Pod Security Admission), 2 (PSA rejection) |
| | Define resource requirements | 9 (requests/limits within a LimitRange), 8 (prod resources patch) |
| | Understand requests, limits, quotas | 9, 12 |
| | Understand ConfigMaps | 11, 1, 8 (generator) |
| | Create & consume Secrets | 11 |
| | Understand ServiceAccounts | 4, 16 |
| | Understand Application Security (SecurityContexts, Capabilities, etc.) | 2, 14, 17 |
| Services and Networking | Demonstrate basic understanding of NetworkPolicies | 5, 10 |
| | Provide and troubleshoot access to applications via services | 10, 7 (headless), 15, 3 |
| | Use Ingress rules to expose applications | 10, 15, 6 |
