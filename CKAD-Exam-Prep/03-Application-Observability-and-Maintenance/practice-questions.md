# Practice Questions — Application Observability and Maintenance (15%)

> These are exam-style tasks modelled on the official CNCF curriculum and on task patterns that candidates describe publicly. Real exam questions are confidential under the Linux Foundation candidate agreement; nothing here is a leaked question.

**How to use this file**

- Run the **Setup** block in your lab first. Setup commands assume your shell is in this chapter's folder (`cd 03-Application-Observability-and-Maintenance`), because some of them apply files from [yaml/](yaml/).
- Every task uses its own namespace `obs-qN` (plus `obs-top` for the `kubectl top` tasks), so you can do them in any order. Answer files go to `/opt/course/N/`. If `/opt` is not writable in your lab, run `sudo mkdir -p /opt/course && sudo chown "$USER" /opt/course` once.
- Tasks needing metrics-server: Q3, Q19. Lab setup is in [../00-Exam-Overview-and-Setup/README.md](../00-Exam-Overview-and-Setup/README.md).
- Order: most frequent first (🔥 High, then ⚡ Medium, then 🧊 Low). Time yourself against the estimate, then compare with the solution.

---

### Q1. Add readiness and liveness probes to a Deployment
**Frequency:** 🔥 High · **Est. time:** 5 min · **Competency:** Implement probes and health checks

**Setup:**
```bash
kubectl create namespace obs-q1
kubectl -n obs-q1 create deployment api --image=nginx:1.27 --port=80 --replicas=2
```

In namespace `obs-q1`, update Deployment `api` (container `nginx`) so that:
- a **readiness probe** sends an HTTP GET to `/` on port `80`, starting after `5` seconds and repeating every `10` seconds;
- a **liveness probe** opens a TCP connection to port `80`, starting after `15` seconds, every `20` seconds, and fails after `3` consecutive failures.

Both replicas must be Ready afterwards.

<details><summary>Solution</summary>

```bash
kubectl -n obs-q1 edit deployment api
```

Add under `spec.template.spec.containers[0]` (same indentation as `image:`):

```yaml
        readinessProbe:
          httpGet:
            path: /
            port: 80
          initialDelaySeconds: 5
          periodSeconds: 10
        livenessProbe:
          tcpSocket:
            port: 80
          initialDelaySeconds: 15
          periodSeconds: 20
          failureThreshold: 3
```

Non-interactive alternative (strategic merge, containers are merged by name):

```bash
kubectl -n obs-q1 patch deployment api -p '{"spec":{"template":{"spec":{"containers":[{"name":"nginx","readinessProbe":{"httpGet":{"path":"/","port":80},"initialDelaySeconds":5,"periodSeconds":10},"livenessProbe":{"tcpSocket":{"port":80},"initialDelaySeconds":15,"periodSeconds":20,"failureThreshold":3}}]}}}}'
```

**Verify:**
```bash
kubectl -n obs-q1 rollout status deployment api
kubectl -n obs-q1 get deploy api -o jsonpath='{.spec.template.spec.containers[0].readinessProbe}{"\n"}{.spec.template.spec.containers[0].livenessProbe}{"\n"}'
kubectl -n obs-q1 get pods -l app=api          # 2 Pods, READY 1/1, RESTARTS 0
```
</details>

---

### Q2. Fix a manifest that uses a removed Deployment API
**Frequency:** 🔥 High · **Est. time:** 6 min · **Competency:** Understand API deprecations

**Setup:**
```bash
kubectl create namespace obs-q2
mkdir -p /opt/course/2
cat > /opt/course/2/legacy-deploy.yaml <<'EOF'
apiVersion: extensions/v1beta1
kind: Deployment
metadata:
  name: inventory
  labels:
    app: inventory
spec:
  replicas: 2
  template:
    metadata:
      labels:
        app: inventory
        tier: backend
    spec:
      containers:
      - name: inventory
        image: httpd:2.4
        ports:
        - containerPort: 80
EOF
```

`kubectl apply -n obs-q2 -f /opt/course/2/legacy-deploy.yaml` fails. Fix the file **in place** so it works on this cluster, without changing the name, labels, replica count or image. Then apply it to namespace `obs-q2`. Write the apiVersion you used to `/opt/course/2/api.txt`.

<details><summary>Solution</summary>

```bash
kubectl apply -n obs-q2 -f /opt/course/2/legacy-deploy.yaml --dry-run=server
#   no matches for kind "Deployment" in version "extensions/v1beta1"
kubectl explain deployment | head -3            # GROUP: apps  VERSION: v1
vim /opt/course/2/legacy-deploy.yaml            # apiVersion + required selector
```

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: inventory
  labels:
    app: inventory
spec:
  replicas: 2
  selector:                 # required in apps/v1; use the template labels
    matchLabels:
      app: inventory
      tier: backend
  template:
    metadata:
      labels:
        app: inventory
        tier: backend
    spec:
      containers:
      - name: inventory
        image: httpd:2.4
        ports:
        - containerPort: 80
```

```bash
kubectl apply -n obs-q2 -f /opt/course/2/legacy-deploy.yaml
echo apps/v1 > /opt/course/2/api.txt
```

**Verify:**
```bash
kubectl -n obs-q2 rollout status deployment inventory
kubectl -n obs-q2 get deploy inventory -o jsonpath='{.apiVersion} {.spec.selector.matchLabels}{"\n"}'
cat /opt/course/2/api.txt                        # apps/v1
```
</details>

---

### Q3. Find the Pods with the highest CPU and memory usage
**Frequency:** 🔥 High · **Est. time:** 3 min · **Competency:** Use built-in CLI tools to monitor Kubernetes applications

**Setup (needs metrics-server):**
```bash
kubectl apply -f yaml/top-demo-workloads.yaml
kubectl top pod -n obs-top                      # repeat until numbers appear (about 1 minute)
```

In namespace `obs-top`:
1. Write the **name only** of the Pod that currently uses the most CPU to `/opt/course/3/cpu-pod.txt`.
2. Write the name only of the Pod that uses the most memory to `/opt/course/3/mem-pod.txt`.
3. Write a command that shows the per-container usage of all Pods in all namespaces, sorted by memory, to `/opt/course/3/cmd.sh`.

<details><summary>Solution</summary>

```bash
mkdir -p /opt/course/3
kubectl top pod -n obs-top --sort-by=cpu --no-headers | head -1 | awk '{print $1}' > /opt/course/3/cpu-pod.txt
kubectl top pod -n obs-top --sort-by=memory --no-headers | head -1 | awk '{print $1}' > /opt/course/3/mem-pod.txt
echo 'kubectl top pod -A --containers --sort-by=memory' > /opt/course/3/cmd.sh
```

`--sort-by` for `top` sorts highest first. `--no-headers` keeps the header out of the answer.

**Verify:**
```bash
cat /opt/course/3/cpu-pod.txt /opt/course/3/mem-pod.txt   # cpu-burner-..., mem-holder-...
bash /opt/course/3/cmd.sh | head -5
```
</details>

---

### Q4. Save container logs, including those of a crashed instance
**Frequency:** 🔥 High · **Est. time:** 4 min · **Competency:** Utilize container logs

**Setup:**
```bash
kubectl create namespace obs-q4
cat <<'EOF' | kubectl apply -n obs-q4 -f -
apiVersion: v1
kind: Pod
metadata:
  name: multi
spec:
  containers:
  - name: web
    image: nginx:1.27
  - name: logger
    image: busybox:1.36
    command: ["sh", "-c", "i=0; while true; do echo \"logger line $i\"; i=$((i+1)); sleep 2; done"]
---
apiVersion: v1
kind: Pod
metadata:
  name: crasher
spec:
  containers:
  - name: app
    image: busybox:1.36
    command: ["sh", "-c", "echo \"run started at $(date)\"; echo 'ERROR: cannot open /data/db.sqlite' >&2; sleep 5; exit 1"]
EOF
```

In namespace `obs-q4`:
1. Write all logs of container `logger` in Pod `multi` to `/opt/course/4/logger.log`.
2. Pod `crasher` restarts constantly. Write the logs of its **previous** container instance to `/opt/course/4/crasher-previous.log`.
3. Write only the lines containing `ERROR` from that previous instance to `/opt/course/4/errors.log`.

<details><summary>Solution</summary>

```bash
mkdir -p /opt/course/4
kubectl -n obs-q4 logs multi -c logger > /opt/course/4/logger.log
kubectl -n obs-q4 get pod crasher                          # wait until RESTARTS >= 1
kubectl -n obs-q4 logs crasher --previous > /opt/course/4/crasher-previous.log
kubectl -n obs-q4 logs crasher --previous | grep ERROR > /opt/course/4/errors.log
```

The app's stderr line is part of the container log stream, so it shows up in `kubectl logs`.

**Verify:**
```bash
head -3 /opt/course/4/logger.log                           # logger line 0, 1, 2 ...
cat /opt/course/4/crasher-previous.log /opt/course/4/errors.log
```
</details>

---

### Q5. Troubleshoot a Deployment stuck in CrashLoopBackOff
**Frequency:** 🔥 High · **Est. time:** 6 min · **Competency:** Debugging in Kubernetes

**Setup:**
```bash
kubectl create namespace obs-q5
cat <<'EOF' | kubectl apply -n obs-q5 -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: orders
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
      - name: orders
        image: busybox:1.36
        command:
        - sh
        - -c
        - |
          echo "orders service starting"
          if [ -z "$DB_HOST" ]; then echo "FATAL: DB_HOST is not set" >&2; exit 1; fi
          echo "using database $DB_HOST"; sleep 3600
EOF
```

Deployment `orders` in namespace `obs-q5` never becomes available. Find the cause and write the exact error line printed by the application to `/opt/course/5/error.txt`. Then fix the Deployment: the application needs the environment variable `DB_HOST=postgres.obs-q5.svc`. All replicas must be Running and Ready.

<details><summary>Solution</summary>

```bash
kubectl -n obs-q5 get pods                                   # Error / CrashLoopBackOff, RESTARTS climbing
kubectl -n obs-q5 logs deploy/orders --previous              # FATAL: DB_HOST is not set
mkdir -p /opt/course/5
kubectl -n obs-q5 logs deploy/orders --previous | grep FATAL > /opt/course/5/error.txt
kubectl -n obs-q5 set env deployment/orders DB_HOST=postgres.obs-q5.svc
```

Fix the **Deployment** (the owner), not the Pods. `set env` changes the template and rolls out new Pods.

**Verify:**
```bash
kubectl -n obs-q5 rollout status deployment orders
kubectl -n obs-q5 logs deploy/orders                          # using database postgres.obs-q5.svc
cat /opt/course/5/error.txt                                   # FATAL: DB_HOST is not set
```
</details>

---

### Q6. Fix an ImagePullBackOff
**Frequency:** 🔥 High · **Est. time:** 4 min · **Competency:** Debugging in Kubernetes

**Setup:**
```bash
kubectl create namespace obs-q6
kubectl -n obs-q6 create deployment frontend --image=nginx:1.27-alpinee --replicas=2
```

The Pods of Deployment `frontend` in namespace `obs-q6` don't start. Write the container's waiting reason, as found in `.status.containerStatuses[].state.waiting.reason` of one of its Pods, to `/opt/course/6/reason.txt`. Then fix the Deployment so it runs image `nginx:1.27-alpine`.

<details><summary>Solution</summary>

```bash
kubectl -n obs-q6 get pods                                   # ErrImagePull / ImagePullBackOff
kubectl -n obs-q6 describe pod -l app=frontend | grep -i -m3 failed   # Failed to pull image "nginx:1.27-alpinee" ... not found
mkdir -p /opt/course/6
kubectl -n obs-q6 get pods -l app=frontend \
  -o jsonpath='{.items[0].status.containerStatuses[0].state.waiting.reason}' > /opt/course/6/reason.txt
kubectl -n obs-q6 set image deployment/frontend nginx=nginx:1.27-alpine   # container name = nginx
```

**Verify:**
```bash
kubectl -n obs-q6 rollout status deployment frontend
kubectl -n obs-q6 get deploy frontend -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
cat /opt/course/6/reason.txt                                  # ErrImagePull or ImagePullBackOff
```
</details>

---

### Q7. Repair a Service that has no working endpoints
**Frequency:** 🔥 High · **Est. time:** 6 min · **Competency:** Debugging in Kubernetes

**Setup:**
```bash
kubectl create namespace obs-q7
kubectl apply -n obs-q7 -f yaml/broken/service-no-endpoints.yaml
```

Clients in namespace `obs-q7` cannot reach Service `web-api` on port 80. Fix the **Service only** (do not change the Deployment) so that `wget -qO- http://web-api.obs-q7` returns the nginx welcome page. Then write the number of **ready** endpoints of the Service to `/opt/course/7/endpoints.txt`.

<details><summary>Solution</summary>

```bash
kubectl -n obs-q7 get endpointslices -l kubernetes.io/service-name=web-api   # ENDPOINTS <unset>
kubectl -n obs-q7 describe svc web-api | grep -E 'Selector|TargetPort'      # app=web-api, 8080/TCP
kubectl -n obs-q7 get pods --show-labels                                     # app=webapi, nginx listens on 80
kubectl -n obs-q7 patch svc web-api -p '{"spec":{"selector":{"app":"webapi"},"ports":[{"port":80,"targetPort":80}]}}'
mkdir -p /opt/course/7
kubectl -n obs-q7 get endpointslices -l kubernetes.io/service-name=web-api \
  -o jsonpath='{range .items[*].endpoints[*]}{.conditions.ready}{"\n"}{end}' | grep -c true > /opt/course/7/endpoints.txt
```

Two bugs: the selector typo (no endpoints at all) and the wrong `targetPort` (connection refused once endpoints exist).

**Verify:**
```bash
kubectl -n obs-q7 run tmp --rm -i -q --image=busybox:1.36 --restart=Never -- wget -qO- -T 2 http://web-api.obs-q7 | head -4
cat /opt/course/7/endpoints.txt                               # 2
```
</details>

---

### Q8. Migrate a legacy Ingress to networking.k8s.io/v1
**Frequency:** 🔥 High · **Est. time:** 7 min · **Competency:** Understand API deprecations

**Setup:**
```bash
kubectl create namespace obs-q8
mkdir -p /opt/course/8
cat > /opt/course/8/ingress.yaml <<'EOF'
apiVersion: networking.k8s.io/v1beta1
kind: Ingress
metadata:
  name: shop
  annotations:
    kubernetes.io/ingress.class: nginx
spec:
  rules:
  - host: shop.example.com
    http:
      paths:
      - path: /api
        backend:
          serviceName: api-svc
          servicePort: 8080
      - path: /
        backend:
          serviceName: web-svc
          servicePort: http
EOF
```

Convert `/opt/course/8/ingress.yaml` to the current Ingress API and save the result as `/opt/course/8/ingress-v1.yaml`. Keep the host, paths and backends. Use `pathType: Prefix` for both paths, and replace the class annotation with `ingressClassName: nginx`. Create the Ingress in namespace `obs-q8`.

<details><summary>Solution</summary>

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: shop
spec:
  ingressClassName: nginx
  rules:
  - host: shop.example.com
    http:
      paths:
      - path: /api
        pathType: Prefix
        backend:
          service:
            name: api-svc
            port:
              number: 8080        # numeric servicePort
      - path: /
        pathType: Prefix
        backend:
          service:
            name: web-svc
            port:
              name: http          # string servicePort
```

```bash
vim /opt/course/8/ingress-v1.yaml          # paste/write the YAML above
kubectl apply -n obs-q8 -f /opt/course/8/ingress-v1.yaml
```

Generator alternative (`*` = Prefix; named ports are supported):

```bash
kubectl create ingress shop -n obs-q8 --class=nginx \
  --rule="shop.example.com/api*=api-svc:8080" --rule="shop.example.com/*=web-svc:http" \
  --dry-run=client -o yaml > /opt/course/8/ingress-v1.yaml
```

**Verify:**
```bash
kubectl -n obs-q8 get ingress shop -o jsonpath='{.spec.ingressClassName}{"\n"}{range .spec.rules[0].http.paths[*]}{.path} {.pathType} {.backend.service}{"\n"}{end}'
```
</details>

---

### Q9. Migrate a legacy CronJob and run it once
**Frequency:** ⚡ Medium · **Est. time:** 5 min · **Competency:** Understand API deprecations

**Setup:**
```bash
kubectl create namespace obs-q9
mkdir -p /opt/course/9
cat > /opt/course/9/cronjob.yaml <<'EOF'
apiVersion: batch/v1beta1
kind: CronJob
metadata:
  name: report
spec:
  schedule: "0 2 * * *"
  jobTemplate:
    spec:
      template:
        spec:
          restartPolicy: OnFailure
          containers:
          - name: report
            image: busybox:1.36
            command: ["sh", "-c", "echo report generated at $(date)"]
EOF
```

Make `/opt/course/9/cronjob.yaml` valid for this cluster (edit it in place) and create the CronJob in namespace `obs-q9`. Then trigger one run immediately as Job `report-manual`, wait until it has completed, and write its logs to `/opt/course/9/report.log`.

<details><summary>Solution</summary>

```bash
sed -i 's#^apiVersion: batch/v1beta1#apiVersion: batch/v1#' /opt/course/9/cronjob.yaml
kubectl apply -n obs-q9 -f /opt/course/9/cronjob.yaml
kubectl -n obs-q9 create job report-manual --from=cronjob/report
kubectl -n obs-q9 wait --for=condition=Complete job/report-manual --timeout=90s
kubectl -n obs-q9 logs job/report-manual > /opt/course/9/report.log
```

CronJob `batch/v1beta1` → `batch/v1` has no field changes.

**Verify:**
```bash
kubectl -n obs-q9 get cronjob report -o jsonpath='{.apiVersion}{"\n"}'     # batch/v1
cat /opt/course/9/report.log                                               # report generated at ...
```
</details>

---

### Q10. Identify the API versions the cluster serves
**Frequency:** ⚡ Medium · **Est. time:** 4 min · **Competency:** Understand API deprecations

Write to `/opt/course/10/versions.txt` one line per kind, in the form `Kind=group/version`, with the **preferred** version this cluster serves for: CronJob, PodDisruptionBudget, HorizontalPodAutoscaler, Ingress, NetworkPolicy. Then write the resource names (the NAME column) of all resources in API group `apps`, one per line, to `/opt/course/10/apps.txt`.

<details><summary>Solution</summary>

```bash
kubectl api-resources | grep -E '^(cronjobs|poddisruptionbudgets|horizontalpodautoscalers|ingresses|networkpolicies) '
kubectl explain hpa | head -3                       # cross-check: GROUP autoscaling, VERSION v2
mkdir -p /opt/course/10
cat > /opt/course/10/versions.txt <<'EOF'
CronJob=batch/v1
PodDisruptionBudget=policy/v1
HorizontalPodAutoscaler=autoscaling/v2
Ingress=networking.k8s.io/v1
NetworkPolicy=networking.k8s.io/v1
EOF
kubectl api-resources --api-group=apps --no-headers | awk '{print $1}' > /opt/course/10/apps.txt
```

SHORTNAMES can be empty, so for the version use `$(NF-2)` (APIVERSION) and `$NF` (KIND) rather than fixed column numbers, for example `kubectl api-resources --no-headers | awk '{print $NF"="$(NF-2)}'`.

**Verify:**
```bash
cat /opt/course/10/versions.txt
cat /opt/course/10/apps.txt          # controllerrevisions daemonsets deployments replicasets statefulsets
```
</details>

---

### Q11. Liveness probe with an exec handler
**Frequency:** ⚡ Medium · **Est. time:** 4 min · **Competency:** Implement probes and health checks

Create namespace `obs-q11`. In it, create Pod `liveness-exec` with image `busybox:1.36` running the command `sh -c "touch /tmp/healthy; sleep 30; rm -f /tmp/healthy; sleep 600"`. Add a liveness probe that executes `cat /tmp/healthy`, starts after 5 seconds and runs every 5 seconds. After the container has been restarted at least once, write the Pod's restart count to `/opt/course/11/restarts.txt`.

<details><summary>Solution</summary>

```bash
kubectl create namespace obs-q11
kubectl -n obs-q11 run liveness-exec --image=busybox:1.36 --dry-run=client -o yaml \
  --command -- sh -c 'touch /tmp/healthy; sleep 30; rm -f /tmp/healthy; sleep 600' > /tmp/q11.yaml
vim /tmp/q11.yaml                       # add the livenessProbe block
```

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: liveness-exec
  labels:
    run: liveness-exec
spec:
  containers:
  - name: liveness-exec
    image: busybox:1.36
    command: ["sh", "-c", "touch /tmp/healthy; sleep 30; rm -f /tmp/healthy; sleep 600"]
    livenessProbe:
      exec:
        command: ["cat", "/tmp/healthy"]
      initialDelaySeconds: 5
      periodSeconds: 5
```

```bash
kubectl apply -n obs-q11 -f /tmp/q11.yaml
kubectl -n obs-q11 get pod liveness-exec -w       # RESTARTS becomes 1 after ~45-50 s
mkdir -p /opt/course/11
kubectl -n obs-q11 get pod liveness-exec -o jsonpath='{.status.containerStatuses[0].restartCount}' > /opt/course/11/restarts.txt
```

**Verify:**
```bash
kubectl -n obs-q11 get events --field-selector involvedObject.name=liveness-exec,reason=Unhealthy   # cat: can't open '/tmp/healthy'
cat /opt/course/11/restarts.txt                   # >= 1
```
</details>

---

### Q12. Protect a slow application with a startup probe
**Frequency:** ⚡ Medium · **Est. time:** 5 min · **Competency:** Implement probes and health checks

**Setup:**
```bash
kubectl create namespace obs-q12
cat <<'EOF' | kubectl apply -n obs-q12 -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: legacy-app
spec:
  replicas: 1
  selector:
    matchLabels:
      app: legacy-app
  template:
    metadata:
      labels:
        app: legacy-app
    spec:
      containers:
      - name: app
        image: nginx:1.27
        command: ["sh", "-c", "echo 'initialising for 45s'; sleep 45; exec nginx -g 'daemon off;'"]
        ports:
        - containerPort: 80
        livenessProbe:
          httpGet:
            path: /
            port: 80
          periodSeconds: 10
          failureThreshold: 3
EOF
```

The Pod of Deployment `legacy-app` (namespace `obs-q12`) is restarted before it finishes initialising. **Without changing the liveness probe or the command**, add a startup probe (HTTP GET `/` on port `80`, every `10` seconds) that gives the application up to **2 minutes** to start. The Pod must become Ready and stop restarting.

<details><summary>Solution</summary>

```bash
kubectl -n obs-q12 describe pod -l app=legacy-app | grep -E 'Liveness probe failed|Killing'
kubectl -n obs-q12 patch deployment legacy-app -p '{"spec":{"template":{"spec":{"containers":[{"name":"app","startupProbe":{"httpGet":{"path":"/","port":80},"periodSeconds":10,"failureThreshold":12}}]}}}}'
```

`failureThreshold × periodSeconds = 12 × 10 s = 120 s`. The liveness probe is disabled until the startup probe succeeds once.

**Verify:**
```bash
kubectl -n obs-q12 rollout status deployment legacy-app --timeout=3m
kubectl -n obs-q12 get pods -l app=legacy-app        # new Pod 1/1 Running, RESTARTS 0
kubectl -n obs-q12 get deploy legacy-app -o jsonpath='{.spec.template.spec.containers[0].startupProbe}{"\n"}'
```
</details>

---

### Q13. Fix broken probes on a Pod
**Frequency:** ⚡ Medium · **Est. time:** 5 min · **Competency:** Implement probes and health checks

**Setup:**
```bash
kubectl create namespace obs-q13
kubectl apply -n obs-q13 -f yaml/broken/wrong-probe-pod.yaml
```

Pod `wrong-probe-demo` in namespace `obs-q13` is restarted repeatedly and never becomes Ready. Write all its probe-failure event messages to `/opt/course/13/events.txt`. Then fix the Pod (keep its name, image and ports) so that it is Running and Ready and is no longer restarted.

<details><summary>Solution</summary>

```bash
mkdir -p /opt/course/13
kubectl -n obs-q13 get events --field-selector involvedObject.name=wrong-probe-demo,reason=Unhealthy \
  -o jsonpath='{range .items[*]}{.message}{"\n"}{end}' > /opt/course/13/events.txt
cat /opt/course/13/events.txt
#   Liveness probe failed: Get "http://10.244.x.y:8080/": dial tcp 10.244.x.y:8080: connect: connection refused
#   Readiness probe failed: HTTP probe failed with statuscode: 404
kubectl -n obs-q13 get pod wrong-probe-demo -o yaml > /tmp/q13.yaml
vim /tmp/q13.yaml          # liveness port 8080 -> 80 (or http); readiness path /healthz -> /
kubectl replace --force -f /tmp/q13.yaml
```

The corrected probes:

```yaml
    livenessProbe:
      httpGet:
        path: /
        port: 80
      initialDelaySeconds: 5
      periodSeconds: 10
    readinessProbe:
      httpGet:
        path: /
        port: http
      periodSeconds: 5
```

Probes are immutable on a running Pod, so `replace --force` (delete and recreate) is required.

**Verify:**
```bash
kubectl -n obs-q13 get pod wrong-probe-demo -w        # 1/1 Running, RESTARTS stays 0
```
</details>

---

### Q14. Get a Pending Pod scheduled
**Frequency:** ⚡ Medium · **Est. time:** 5 min · **Competency:** Debugging in Kubernetes

**Setup:**
```bash
kubectl create namespace obs-q14
kubectl apply -n obs-q14 -f yaml/broken/pending-resources-pod.yaml
```

Pod `pending-demo` in namespace `obs-q14` stays `Pending`. Write the scheduler's message (the `FailedScheduling` event message) to `/opt/course/14/reason.txt`. Then make the Pod run with requests `cpu: 100m` and `memory: 64Mi`, keeping its name and image.

<details><summary>Solution</summary>

```bash
kubectl -n obs-q14 describe pod pending-demo | grep -A4 Events
mkdir -p /opt/course/14
kubectl -n obs-q14 get events --field-selector involvedObject.name=pending-demo,reason=FailedScheduling \
  -o jsonpath='{.items[-1:].message}' > /opt/course/14/reason.txt
kubectl -n obs-q14 get pod pending-demo -o yaml > /tmp/q14.yaml
sed -i -e 's/cpu: "64"/cpu: 100m/' -e 's/memory: 256Gi/memory: 64Mi/' /tmp/q14.yaml
kubectl replace --force -f /tmp/q14.yaml
```

**Verify:**
```bash
kubectl -n obs-q14 get pod pending-demo -o wide                    # Running, NODE set
kubectl -n obs-q14 get pod pending-demo -o jsonpath='{.spec.containers[0].resources.requests}{"\n"}'
cat /opt/course/14/reason.txt        # 0/N nodes are available: ... Insufficient cpu, ... Insufficient memory ...
```
</details>

---

### Q15. Resolve a CreateContainerConfigError without recreating the Pod
**Frequency:** ⚡ Medium · **Est. time:** 4 min · **Competency:** Debugging in Kubernetes

**Setup:**
```bash
kubectl create namespace obs-q15
kubectl apply -n obs-q15 -f yaml/broken/configerror-pod.yaml
```

Pod `configerror-demo` in namespace `obs-q15` does not start. Write the error message from its Warning events to `/opt/course/15/error.txt`. Fix the problem **without deleting or recreating the Pod**: the application expects key `db_url` with value `postgres://db:5432/app` in ConfigMap `app-config`.

<details><summary>Solution</summary>

```bash
kubectl -n obs-q15 get pod configerror-demo                   # CreateContainerConfigError
mkdir -p /opt/course/15
kubectl -n obs-q15 get events --field-selector involvedObject.name=configerror-demo,type=Warning \
  -o jsonpath='{.items[-1:].message}' > /opt/course/15/error.txt
kubectl -n obs-q15 patch configmap app-config -p '{"data":{"db_url":"postgres://db:5432/app"}}'
```

The kubelet keeps retrying container creation, so the Pod starts by itself once the key exists.

**Verify:**
```bash
kubectl -n obs-q15 get pod configerror-demo -w                # Running within about a minute
kubectl -n obs-q15 logs configerror-demo                      # DB_URL=postgres://db:5432/app
cat /opt/course/15/error.txt          # Error: couldn't find key db_url in ConfigMap obs-q15/app-config
```
</details>

---

### Q16. Investigate and fix an OOMKilled container
**Frequency:** ⚡ Medium · **Est. time:** 5 min · **Competency:** Debugging in Kubernetes

**Setup:**
```bash
kubectl create namespace obs-q16
kubectl apply -n obs-q16 -f yaml/broken/oom-pod.yaml
```

Pod `oom-demo` in namespace `obs-q16` keeps restarting. Write `reason=<reason> exitCode=<code>` of its **last termination** to `/opt/course/16/termination.txt`. Then give container `app` a memory request of `96Mi` and a memory limit of `128Mi` so that it stays Running. Keep the Pod name.

<details><summary>Solution</summary>

```bash
kubectl -n obs-q16 get pod oom-demo                            # OOMKilled / CrashLoopBackOff
mkdir -p /opt/course/16
kubectl -n obs-q16 get pod oom-demo -o jsonpath='reason={.status.containerStatuses[0].lastState.terminated.reason} exitCode={.status.containerStatuses[0].lastState.terminated.exitCode}{"\n"}' > /opt/course/16/termination.txt
cat /opt/course/16/termination.txt                             # reason=OOMKilled exitCode=137
```

Fix A, in place, without recreating (in-place resize, stable since v1.35; the QoS class stays Burstable):

```bash
kubectl -n obs-q16 patch pod oom-demo --subresource resize \
  -p '{"spec":{"containers":[{"name":"app","resources":{"requests":{"memory":"96Mi"},"limits":{"memory":"128Mi"}}}]}}'
```

Fix B, any version, by recreating:

```bash
kubectl -n obs-q16 get pod oom-demo -o yaml > /tmp/q16.yaml
sed -i -e 's/memory: 32Mi/memory: 96Mi/' -e 's/memory: 50Mi/memory: 128Mi/' /tmp/q16.yaml
kubectl replace --force -f /tmp/q16.yaml
```

**Verify:**
```bash
kubectl -n obs-q16 get pod oom-demo -w                         # Running and stays up
kubectl -n obs-q16 logs oom-demo                               # cache loaded
kubectl -n obs-q16 get pod oom-demo -o jsonpath='{.spec.containers[0].resources}{"\n"}'
```
</details>

---

### Q17. Analyse the events of a namespace
**Frequency:** ⚡ Medium · **Est. time:** 4 min · **Competency:** Use built-in CLI tools to monitor Kubernetes applications

**Setup:**
```bash
kubectl create namespace obs-q17
kubectl -n obs-q17 run good --image=nginx:1.27
kubectl -n obs-q17 run bad-image --image=nginx:9.99.99
kubectl -n obs-q17 run bad-node --image=nginx:1.27 --overrides='{"apiVersion":"v1","spec":{"nodeSelector":{"disktype":"nvme-gold"}}}'
```

In namespace `obs-q17`:
1. Write all **Warning** events, oldest first, to `/opt/course/17/warnings.txt`.
2. Write all events of Pod `bad-image` to `/opt/course/17/bad-image.txt`.
3. Write the distinct **reasons** of the Warning events, one per line and sorted alphabetically, to `/opt/course/17/reasons.txt`.

<details><summary>Solution</summary>

```bash
mkdir -p /opt/course/17
kubectl -n obs-q17 get events --field-selector type=Warning --sort-by=.metadata.creationTimestamp > /opt/course/17/warnings.txt
kubectl -n obs-q17 events --for pod/bad-image > /opt/course/17/bad-image.txt
kubectl -n obs-q17 get events --field-selector type=Warning \
  -o jsonpath='{range .items[*]}{.reason}{"\n"}{end}' | sort -u > /opt/course/17/reasons.txt
```

Alternative for (2): `kubectl -n obs-q17 get events --field-selector involvedObject.name=bad-image`.

**Verify:**
```bash
cat /opt/course/17/reasons.txt         # typically: Failed, FailedScheduling
head -3 /opt/course/17/warnings.txt /opt/course/17/bad-image.txt
```
</details>

---

### Q18. Debug Pods without a shell using ephemeral containers
**Frequency:** ⚡ Medium · **Est. time:** 6 min · **Competency:** Debugging in Kubernetes

**Setup:**
```bash
kubectl create namespace obs-q18
kubectl apply -n obs-q18 -f yaml/debug-target-pod.yaml
```

In namespace `obs-q18`, without restarting or recreating any Pod:
1. Pod `debug-distroless` has no shell. Add an ephemeral container named `psdump` (image `busybox:1.36`) that targets container `app` and runs `ps`. Save its output to `/opt/course/18/ps.txt`.
2. Using an ephemeral container (image `busybox:1.36`) in Pod `debug-web` that targets container `web`, copy the content of the **target container's** file `/etc/nginx/conf.d/default.conf` to `/opt/course/18/default.conf`.

<details><summary>Solution</summary>

```bash
mkdir -p /opt/course/18
kubectl -n obs-q18 exec debug-distroless -- sh || true          # fails: no shell in the image
kubectl -n obs-q18 debug debug-distroless --image=busybox:1.36 --target=app -c psdump -- ps
sleep 3
kubectl -n obs-q18 logs debug-distroless -c psdump > /opt/course/18/ps.txt
kubectl -n obs-q18 debug debug-web --image=busybox:1.36 --target=web -c conf --profile=general \
  -- cat /proc/1/root/etc/nginx/conf.d/default.conf
sleep 3
kubectl -n obs-q18 logs debug-web -c conf > /opt/course/18/default.conf
```

- `--target` puts the debug container into the target's **process namespace**: PID 1 is the target's main process, and `/proc/1/root/` is its filesystem.
- `--profile=general` adds `SYS_PTRACE`. It is the default in kubectl v1.36+, and being explicit makes older kubectl behave the same.
- Interactive alternative: `kubectl -n obs-q18 debug -it debug-web --image=busybox:1.36 --target=web -- sh`, then `cat /proc/1/root/etc/nginx/conf.d/default.conf`.

**Verify:**
```bash
cat /opt/course/18/ps.txt                     # PID 1 ... /pause
head -5 /opt/course/18/default.conf           # server { listen 80; ...
kubectl -n obs-q18 get pods                   # RESTARTS 0 for both
kubectl -n obs-q18 get pod debug-distroless -o jsonpath='{.spec.ephemeralContainers[*].name}{"\n"}'   # psdump
```
</details>

---

### Q19. Report node and container resource usage
**Frequency:** ⚡ Medium · **Est. time:** 3 min · **Competency:** Use built-in CLI tools to monitor Kubernetes applications

**Setup (needs metrics-server):** `kubectl apply -f yaml/top-demo-workloads.yaml` (skip it if you did Q3).

1. Write the name of the node with the highest **memory** usage to `/opt/course/19/node.txt`.
2. Write the per-container usage of all Pods in namespace `obs-top`, sorted by memory and including the header, to `/opt/course/19/containers.txt`.
3. Write the `kubectl top` output, including its totals line, for the Pods labelled `tier=batch` in `obs-top` to `/opt/course/19/batch-sum.txt`.

<details><summary>Solution</summary>

```bash
mkdir -p /opt/course/19
kubectl top node --sort-by=memory --no-headers | head -1 | awk '{print $1}' > /opt/course/19/node.txt
kubectl top pod -n obs-top --containers --sort-by=memory > /opt/course/19/containers.txt
kubectl top pod -n obs-top -l tier=batch --sum > /opt/course/19/batch-sum.txt
```

**Verify:**
```bash
cat /opt/course/19/node.txt
head -3 /opt/course/19/containers.txt          # POD NAME CPU(cores) MEMORY(bytes)
cat /opt/course/19/batch-sum.txt
```
</details>

---

### Q20. Collect logs from all Pods of a Deployment
**Frequency:** ⚡ Medium · **Est. time:** 4 min · **Competency:** Utilize container logs

**Setup:**
```bash
kubectl create namespace obs-q20
kubectl -n obs-q20 create deployment checkout --image=busybox:1.36 --replicas=3 \
  -- sh -c 'i=0; while true; do echo "$(hostname) handled order $i"; i=$((i+1)); sleep 3; done'
```

In namespace `obs-q20`:
1. Write the **last 20 lines** of **every** Pod of Deployment `checkout`, each line prefixed with its source Pod, to `/opt/course/20/checkout.log`.
2. Write the log lines of the last **2 minutes**, with timestamps, of one Pod of the Deployment (let kubectl choose it) to `/opt/course/20/recent.log`.

<details><summary>Solution</summary>

```bash
mkdir -p /opt/course/20
kubectl -n obs-q20 get deploy checkout -o jsonpath='{.spec.selector.matchLabels}{"\n"}'     # {"app":"checkout"}
kubectl -n obs-q20 logs -l app=checkout --tail=20 --prefix > /opt/course/20/checkout.log
#   or: kubectl -n obs-q20 logs deploy/checkout --all-pods --tail=20 > /opt/course/20/checkout.log
kubectl -n obs-q20 logs deploy/checkout --since=2m --timestamps > /opt/course/20/recent.log
```

`kubectl logs deploy/<name>` reads one Pod. Use `-l` or `--all-pods` for all of them.

**Verify:**
```bash
cut -d' ' -f1 /opt/course/20/checkout.log | sort | uniq -c     # 3 sources, <= 20 lines each
head -2 /opt/course/20/recent.log                               # 2026-...Z checkout-... handled order N
```
</details>

---

### Q21. Inspect Pod status with jsonpath
**Frequency:** ⚡ Medium · **Est. time:** 6 min · **Competency:** Use built-in CLI tools to monitor Kubernetes applications

**Setup:**
```bash
kubectl create namespace obs-q21
cat <<'EOF' | kubectl apply -n obs-q21 -f -
apiVersion: v1
kind: Pod
metadata:
  name: qos-guaranteed
spec:
  containers:
  - name: app
    image: busybox:1.36
    command: ["sleep", "3600"]
    resources:
      requests: {cpu: 50m, memory: 32Mi}
      limits: {cpu: 50m, memory: 32Mi}
---
apiVersion: v1
kind: Pod
metadata:
  name: qos-burstable
spec:
  containers:
  - name: app
    image: busybox:1.36
    command: ["sleep", "3600"]
    resources:
      requests: {memory: 16Mi}
---
apiVersion: v1
kind: Pod
metadata:
  name: qos-besteffort
spec:
  containers:
  - name: app
    image: busybox:1.36
    command: ["sleep", "3600"]
---
apiVersion: v1
kind: Pod
metadata:
  name: never-ready
spec:
  containers:
  - name: app
    image: busybox:1.36
    command: ["sleep", "3600"]
    readinessProbe:
      exec:
        command: ["false"]
      periodSeconds: 5
---
apiVersion: v1
kind: Pod
metadata:
  name: restarter
spec:
  containers:
  - name: app
    image: busybox:1.36
    command: ["sh", "-c", "exit 1"]
EOF
```

In namespace `obs-q21`:
1. `/opt/course/21/qos.txt`: one line per Pod, `<pod-name> <qosClass>`.
2. `/opt/course/21/not-ready.txt`: the names of the Pods whose `Ready` condition is not `True`, one per line.
3. `/opt/course/21/restarts.txt`: `<pod-name> <restartCount>` for every Pod, sorted by restart count with the highest last.

<details><summary>Solution</summary>

```bash
mkdir -p /opt/course/21
kubectl -n obs-q21 get pods -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.status.qosClass}{"\n"}{end}' > /opt/course/21/qos.txt
kubectl -n obs-q21 get pods \
  -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.status.conditions[?(@.type=="Ready")].status}{"\n"}{end}' \
  | awk '$2!="True"{print $1}' > /opt/course/21/not-ready.txt
kubectl -n obs-q21 get pods --sort-by='.status.containerStatuses[0].restartCount' --no-headers \
  -o custom-columns='NAME:.metadata.name,RESTARTS:.status.containerStatuses[0].restartCount' \
  | awk '{print $1" "$2}' > /opt/course/21/restarts.txt
```

**Verify:**
```bash
cat /opt/course/21/qos.txt          # qos-guaranteed Guaranteed, qos-burstable Burstable, the rest BestEffort
cat /opt/course/21/not-ready.txt    # never-ready, restarter
cat /opt/course/21/restarts.txt     # restarter last
```
</details>

---

### Q22. Migrate a PodDisruptionBudget and an HPA
**Frequency:** 🧊 Low · **Est. time:** 5 min · **Competency:** Understand API deprecations

**Setup:**
```bash
kubectl create namespace obs-q22
kubectl -n obs-q22 create deployment shop --image=nginx:1.27 --replicas=2
kubectl -n obs-q22 set resources deployment shop --requests=cpu=50m
mkdir -p /opt/course/22
cat > /opt/course/22/legacy.yaml <<'EOF'
apiVersion: policy/v1beta1
kind: PodDisruptionBudget
metadata:
  name: shop-pdb
spec:
  maxUnavailable: 1
  selector:
    matchLabels:
      app: shop
---
apiVersion: autoscaling/v2beta2
kind: HorizontalPodAutoscaler
metadata:
  name: shop-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: shop
  minReplicas: 2
  maxReplicas: 5
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 60
EOF
```

Fix both objects in `/opt/course/22/legacy.yaml` (edit in place) for the current cluster and create them in namespace `obs-q22`. Confirm that the HPA is served as `autoscaling/v2`.

<details><summary>Solution</summary>

```bash
sed -i -e 's#^apiVersion: policy/v1beta1#apiVersion: policy/v1#' \
       -e 's#^apiVersion: autoscaling/v2beta2#apiVersion: autoscaling/v2#' /opt/course/22/legacy.yaml
kubectl apply -n obs-q22 -f /opt/course/22/legacy.yaml --dry-run=server
kubectl apply -n obs-q22 -f /opt/course/22/legacy.yaml
```

Both migrations only change `apiVersion`. Remember the `policy/v1` rule that an empty selector selects every Pod. This one has a real selector.

**Verify:**
```bash
grep '^apiVersion' /opt/course/22/legacy.yaml
kubectl -n obs-q22 get pdb shop-pdb                        # MAX UNAVAILABLE 1
kubectl -n obs-q22 get hpa.v2.autoscaling shop-hpa -o jsonpath='{.apiVersion} {.spec.metrics[0].resource.target}{"\n"}'
```
</details>

---

### Q23. Configure gRPC probes
**Frequency:** 🧊 Low · **Est. time:** 4 min · **Competency:** Implement probes and health checks

In a new namespace `obs-q23`, create Pod `etcd-grpc` with image `registry.k8s.io/etcd:3.5.1-0`, command `/usr/local/bin/etcd --data-dir /var/lib/etcd --listen-client-urls http://0.0.0.0:2379 --advertise-client-urls http://127.0.0.1:2379`, and container port `2379`. Add a **gRPC liveness probe** on port 2379 with an initial delay of 10 seconds, and a **gRPC readiness probe** on port 2379 every 5 seconds. The Pod must become Ready.

<details><summary>Solution</summary>

```bash
kubectl create namespace obs-q23
kubectl -n obs-q23 run etcd-grpc --image=registry.k8s.io/etcd:3.5.1-0 --port=2379 --dry-run=client -o yaml \
  --command -- /usr/local/bin/etcd --data-dir /var/lib/etcd --listen-client-urls http://0.0.0.0:2379 \
  --advertise-client-urls http://127.0.0.1:2379 > /tmp/q23.yaml
vim /tmp/q23.yaml                       # add the two grpc probes
```

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: etcd-grpc
spec:
  containers:
  - name: etcd-grpc
    image: registry.k8s.io/etcd:3.5.1-0
    command: ["/usr/local/bin/etcd", "--data-dir", "/var/lib/etcd", "--listen-client-urls", "http://0.0.0.0:2379", "--advertise-client-urls", "http://127.0.0.1:2379"]
    ports:
    - containerPort: 2379
    livenessProbe:
      grpc:
        port: 2379              # numbers only; gRPC probes cannot use named ports
      initialDelaySeconds: 10
    readinessProbe:
      grpc:
        port: 2379
      periodSeconds: 5
```

```bash
kubectl apply -n obs-q23 -f /tmp/q23.yaml
```

**Verify:**
```bash
kubectl -n obs-q23 wait --for=condition=Ready pod/etcd-grpc --timeout=90s
kubectl -n obs-q23 describe pod etcd-grpc | grep -E 'Liveness|Readiness'
```
</details>

---

### Q24. Diagnose a failing init container
**Frequency:** 🧊 Low · **Est. time:** 4 min · **Competency:** Utilize container logs

**Setup:**
```bash
kubectl create namespace obs-q24
kubectl apply -n obs-q24 -f yaml/broken/init-crash-pod.yaml
```

Pod `init-crash-demo` in namespace `obs-q24` never starts its app container. Write the logs of the failing init container to `/opt/course/24/init.log` and its last exit code to `/opt/course/24/exitcode.txt`. Then fix the Pod (same name; the init container should sleep 5 seconds as intended) so that it reaches Running.

<details><summary>Solution</summary>

```bash
kubectl -n obs-q24 get pod init-crash-demo                     # Init:Error / Init:CrashLoopBackOff
kubectl -n obs-q24 get pod init-crash-demo -o jsonpath='{.spec.initContainers[*].name}{"\n"}'   # wait-for-config
mkdir -p /opt/course/24
kubectl -n obs-q24 logs init-crash-demo -c wait-for-config > /opt/course/24/init.log           # sh: slep: not found
kubectl -n obs-q24 get pod init-crash-demo \
  -o jsonpath='{.status.initContainerStatuses[0].lastState.terminated.exitCode}' > /opt/course/24/exitcode.txt   # 127
kubectl -n obs-q24 get pod init-crash-demo -o yaml > /tmp/q24.yaml
sed -i 's/slep 5/sleep 5/' /tmp/q24.yaml
kubectl replace --force -f /tmp/q24.yaml
```

If `lastState` is still empty (it has failed only once), read `.status.initContainerStatuses[0].state.terminated.exitCode` or `kubectl describe pod`. Exit code **127** = command not found in a shell.

**Verify:**
```bash
kubectl -n obs-q24 get pod init-crash-demo -w                  # Init:0/1 -> PodInitializing -> Running
cat /opt/course/24/init.log /opt/course/24/exitcode.txt
```
</details>

---

### Q25. Inspect a Pod that cannot start, using a debug copy
**Frequency:** 🧊 Low · **Est. time:** 5 min · **Competency:** Debugging in Kubernetes

**Setup:**
```bash
kubectl create namespace obs-q25
kubectl apply -n obs-q25 -f yaml/broken/bad-command-pod.yaml
```

Pod `bad-command-demo` in namespace `obs-q25` never runs.
1. Write `reason=<reason> exitCode=<code>` of its last termination to `/opt/course/25/termination.txt`.
2. Without modifying `bad-command-demo`, create a copy named `bad-command-debug` in which container `app` runs `sleep 1d` instead, so you can inspect the image. From inside the copy, write the output of `ls -la /` to `/opt/course/25/ls.txt`. Leave the copy running.

<details><summary>Solution</summary>

```bash
kubectl -n obs-q25 get pod bad-command-demo                    # RunContainerError / CrashLoopBackOff
mkdir -p /opt/course/25
kubectl -n obs-q25 get pod bad-command-demo -o jsonpath='reason={.status.containerStatuses[0].lastState.terminated.reason} exitCode={.status.containerStatuses[0].lastState.terminated.exitCode}{"\n"}' > /opt/course/25/termination.txt
cat /opt/course/25/termination.txt                             # containerd: reason=StartError exitCode=128
kubectl -n obs-q25 debug bad-command-demo --copy-to=bad-command-debug --container=app -- sleep 1d
kubectl -n obs-q25 wait --for=condition=Ready pod/bad-command-debug --timeout=60s
kubectl -n obs-q25 exec bad-command-debug -- ls -la / > /opt/course/25/ls.txt
kubectl -n obs-q25 exec bad-command-debug -- ls /app            # No such file or directory: the binary is missing
```

`--container=app -- <cmd>` replaces that container's command in the copy. Without `--container`, kubectl would add a new container instead.

**Verify:**
```bash
kubectl -n obs-q25 get pods                                     # demo still failing, debug copy Running
kubectl -n obs-q25 get pod bad-command-debug -o jsonpath='{.spec.containers[0].command}{"\n"}'   # ["sleep","1d"]
head -3 /opt/course/25/ls.txt
```
</details>

---

### Q26. Wait for workloads and record their status
**Frequency:** 🧊 Low · **Est. time:** 4 min · **Competency:** Use built-in CLI tools to monitor Kubernetes applications

In a new namespace `obs-q26`:
1. Create Deployment `waiter` (image `nginx:1.27`, 3 replicas). Use `kubectl wait` to block until it is **Available** (at most 120 s), then write its `.status.readyReplicas` to `/opt/course/26/ready.txt`.
2. Create Job `pi` (image `busybox:1.36`, command `sh -c "sleep 5; echo done"`). Wait until it is **Complete**, then write the Job's `.status.completionTime` to `/opt/course/26/completed.txt`.

<details><summary>Solution</summary>

```bash
kubectl create namespace obs-q26
kubectl -n obs-q26 create deployment waiter --image=nginx:1.27 --replicas=3
kubectl -n obs-q26 wait --for=condition=Available deployment/waiter --timeout=120s
mkdir -p /opt/course/26
kubectl -n obs-q26 get deploy waiter -o jsonpath='{.status.readyReplicas}' > /opt/course/26/ready.txt
kubectl -n obs-q26 create job pi --image=busybox:1.36 -- sh -c "sleep 5; echo done"
kubectl -n obs-q26 wait --for=condition=Complete job/pi --timeout=60s
kubectl -n obs-q26 get job pi -o jsonpath='{.status.completionTime}' > /opt/course/26/completed.txt
```

**Verify:**
```bash
cat /opt/course/26/ready.txt /opt/course/26/completed.txt      # 3, then an RFC3339 timestamp
kubectl -n obs-q26 logs job/pi                                   # done
```
</details>

---

### Q27. Diagnose a "forbidden" error from application logs
**Frequency:** 🧊 Low · **Est. time:** 5 min · **Competency:** Debugging in Kubernetes

**Setup:**
```bash
kubectl create namespace obs-q27
kubectl -n obs-q27 create serviceaccount reader
cat <<'EOF' | kubectl apply -n obs-q27 -f -
apiVersion: v1
kind: Pod
metadata:
  name: lister
spec:
  serviceAccountName: reader
  containers:
  - name: client
    image: curlimages/curl:8.10.1
    command:
    - sh
    - -c
    - |
      SA=/var/run/secrets/kubernetes.io/serviceaccount
      while true; do
        curl -s --cacert $SA/ca.crt -H "Authorization: Bearer $(cat $SA/token)" \
          "https://kubernetes.default.svc/api/v1/namespaces/obs-q27/pods?pretty=true" | grep -E '"(kind|message)"' | head -2
        sleep 10
      done
EOF
```

Pod `lister` in namespace `obs-q27` (ServiceAccount `reader`) should list the Pods of its namespace, but its logs show an error. Find the reason. Write the `kubectl auth can-i` command that proves the missing permission, and its answer, to `/opt/course/27/check.txt` (two lines). Then grant exactly what is needed: Role `pod-reader` (verbs `get`, `list`, `watch` on `pods`) and RoleBinding `reader-binding` for the ServiceAccount. Confirm that the Pod's output changes.

<details><summary>Solution</summary>

```bash
kubectl -n obs-q27 logs lister --tail=2
#   "kind": "Status",
#   "message": "pods is forbidden: User \"system:serviceaccount:obs-q27:reader\" cannot list resource \"pods\" in API group \"\" in the namespace \"obs-q27\"",
mkdir -p /opt/course/27
CMD='kubectl auth can-i list pods -n obs-q27 --as=system:serviceaccount:obs-q27:reader'
{ echo "$CMD"; $CMD; } > /opt/course/27/check.txt              # 2nd line: no
kubectl -n obs-q27 create role pod-reader --verb=get,list,watch --resource=pods
kubectl -n obs-q27 create rolebinding reader-binding --role=pod-reader --serviceaccount=obs-q27:reader
```

The error message names the subject, verb, resource, API group and namespace: everything the Role needs. More RBAC in [chapter 04](../04-Application-Environment-Configuration-and-Security/README.md).

**Verify:**
```bash
kubectl auth can-i list pods -n obs-q27 --as=system:serviceaccount:obs-q27:reader   # yes
kubectl -n obs-q27 logs lister --tail=1                          # "kind": "PodList", (within ~10 s)
cat /opt/course/27/check.txt
```
</details>

---

### Q28. Find deprecated API usage in the cluster
**Frequency:** 🧊 Low · **Est. time:** 3 min · **Competency:** Understand API deprecations

1. Write every sample line of the kube-apiserver metric `apiserver_requested_deprecated_apis` to `/opt/course/28/deprecated.txt` (an empty file if there are none).
2. Run `kubectl get endpoints -A` once and write the **warning** it prints to `/opt/course/28/warning.txt`.

<details><summary>Solution</summary>

```bash
mkdir -p /opt/course/28
kubectl get --raw /metrics | grep '^apiserver_requested_deprecated_apis' > /opt/course/28/deprecated.txt || true
kubectl get endpoints -A 2>&1 >/dev/null | grep -i warning > /opt/course/28/warning.txt
```

- The metric is a gauge, set to 1 for each deprecated group/version/resource requested since the API server started. Labels: `group`, `version`, `resource`, `subresource`, `removed_release`. On v1.33+ you will usually see `resource="endpoints"`, because controllers still read and write v1 Endpoints.
- `2>&1 >/dev/null` sends stderr (where kubectl prints warnings) into the pipe and discards the normal output.

**Verify:**
```bash
cat /opt/course/28/deprecated.txt
cat /opt/course/28/warning.txt     # Warning: v1 Endpoints is deprecated in v1.33+; use discovery.k8s.io/v1 EndpointSlice
```
</details>

---

## Lab cleanup

```bash
kubectl get namespaces -o name | grep -E '^namespace/obs-(q[0-9]+|top)$' | xargs -r kubectl delete
rm -rf /opt/course/{1..28} /tmp/q1[0-9].yaml /tmp/q2[0-9].yaml
```

---

## Must-know summary

- Removed APIs fail with `no matches for kind ... in version ...`. Find the served version with `kubectl api-resources | grep <kind>` or `kubectl explain <kind> | head -3`, then validate the fix with `kubectl apply --dry-run=server -f`.
- `apps/v1` needs `spec.selector.matchLabels` matching the template labels. Ingress v1 needs `pathType` and `backend.service.name` + `port.number|name`. CronJob/PDB/HPA (v2beta2) migrations change only `apiVersion`.
- The exam route is manual migration. `kubectl convert` is a separate plugin and not a guaranteed exam tool.
- Readiness failure ⇒ no restart, the endpoint becomes `ready: false`. Liveness/startup failure ⇒ container killed and restarted. The startup probe disables the other two until it succeeds.
- Probe defaults: `initialDelaySeconds 0`, `periodSeconds 10`, `timeoutSeconds 1`, `successThreshold 1` (must be 1 for liveness/startup), `failureThreshold 3`. Startup budget = `failureThreshold × periodSeconds`.
- exec probes don't run in a shell (`["sh","-c","..."]`). gRPC probes take numeric ports only. httpGet success = 200–399.
- Probes and most Pod fields are immutable: Pods need `kubectl replace --force -f`, Deployments roll out on `kubectl edit`/`patch`.
- `kubectl top pod -n X --sort-by=cpu --no-headers | head -1 | awk '{print $1}' > file`. With `-A` the name is column 2. Requires metrics-server.
- Events: `kubectl get events --sort-by=.metadata.creationTimestamp`, `--field-selector type=Warning,involvedObject.name=x`, or `kubectl events --for pod/x`. Events expire after 1 h.
- Logs: `-c`, `-p`, `--all-containers`, `--prefix`, `--tail`, `--since`, `--timestamps`, `-l` (default tail 10!), `deploy/x`, `--all-pods`, init containers via `-c`.
- Status → cause: Pending = scheduling, ImagePullBackOff = image/registry, CreateContainerConfigError = missing ConfigMap/Secret/key, CrashLoopBackOff = read `logs -p` + exit code, OOMKilled = 137, Init:* = `logs -c <init>`.
- Exit codes: 1 app error, 126 not executable, 127 not found, 128 StartError, 137 SIGKILL/OOM, 139 segfault, 143 SIGTERM.
- `kubectl debug -it <pod> --image=busybox:1.36 --target=<c>` for shell-less images. `--copy-to=<new> --container=<c> -- sleep 1d` for crashing ones. The default profile is `general` on v1.36+.
- Temp client: `kubectl run tmp --rm -it --image=busybox:1.36 --restart=Never -- wget -qO- -T 2 http://svc.ns`. Add `-q` and drop `-t` when redirecting to a file.
- A Service without endpoints is a selector/label mismatch. Endpoints that refuse connections mean a wrong `targetPort` or unready Pods. Check with `kubectl get endpointslices -l kubernetes.io/service-name=<svc>`.
