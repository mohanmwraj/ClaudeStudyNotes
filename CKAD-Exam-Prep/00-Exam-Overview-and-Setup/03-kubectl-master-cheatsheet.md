# kubectl Master Cheatsheet (all CKAD domains on one page)

Print this or keep it open in a second window while you practise. Every chapter has a deeper `commands.md`; this page is the "muscle memory" set you should be able to type without looking by exam day.

> Assumes `alias k=kubectl` and the two exports below. Image tags are pinned on purpose: never rely on `latest` in the exam unless the task says so.

---

## 0. Shell setup (first 60 seconds of the exam)

```bash
# In the real exam every task runs on its own host (ssh <host> from the task's infobox).
# The k alias and bash completion are preconfigured there; exports are NOT, so re-run them per host
# (or just type the flags).
alias k=kubectl                                   # preconfigured on exam hosts — check with: type k
source <(kubectl completion bash)                 # preconfigured on exam hosts
complete -o default -F __start_kubectl k          # completion for the alias
export do="--dry-run=client -o yaml"              # k create deploy web --image=nginx:1.27 $do > web.yaml
export now="--force --grace-period=0"             # k delete pod web $now
```

```vim
" ~/.vimrc — YAML-friendly editing
set expandtab tabstop=2 shiftwidth=2 autoindent number
```

---

## 1. Host, contexts and namespaces (do this at the start of EVERY task)

```bash
ssh <host-from-task-infobox>                      # every task has a designated host; exit when done (no nested ssh)
k config get-contexts                             # list contexts (* = current)
k config use-context <context-from-task>          # switch cluster/context exactly as the task says
k config current-context
k config set-context --current --namespace=<ns>   # make <ns> the default for this context
k config view --minify -o jsonpath='{..namespace}'; echo   # which namespace am I in?
k get ns
```

---

## 2. Generate YAML instead of typing it

| Kind | Fastest generator |
|---|---|
| Pod | `k run web --image=nginx:1.27 --port=80 --labels=app=web $do > pod.yaml` |
| Pod + command | `k run bb --image=busybox:1.36 $do --command -- sh -c 'sleep 3600' > bb.yaml` |
| Pod + args only | `k run bb --image=busybox:1.36 $do -- sleep 3600` (args, keeps image ENTRYPOINT) |
| Deployment | `k create deploy web --image=nginx:1.27 --replicas=3 --port=80 $do > deploy.yaml` |
| Service from workload | `k expose deploy web --port=80 --target-port=8080 --name=web-svc $do` |
| Service standalone | `k create svc nodeport web --tcp=80:8080 --node-port=30080 $do` (selector = `app=web`) |
| Job | `k create job hello --image=busybox:1.36 $do -- sh -c 'echo hi'` |
| Job from CronJob | `k create job manual-1 --from=cronjob/backup` |
| CronJob | `k create cronjob backup --image=busybox:1.36 --schedule="*/5 * * * *" $do -- sh -c 'date'` |
| ConfigMap | `k create cm app-cfg --from-literal=MODE=prod --from-file=app.properties $do` |
| ConfigMap from env file | `k create cm app-env --from-env-file=app.env $do` (cannot be mixed with --from-literal) |
| Secret (generic) | `k create secret generic db --from-literal=password='S3cr3t!' $do` |
| Secret (TLS) | `k create secret tls web-tls --cert=tls.crt --key=tls.key` |
| Secret (registry) | `k create secret docker-registry regcred --docker-server=reg.example.com --docker-username=u --docker-password=p --docker-email=u@example.com` |
| ServiceAccount | `k create sa app-sa $do` |
| Role / ClusterRole | `k create role pod-reader --verb=get,list,watch --resource=pods $do` |
| RoleBinding | `k create rolebinding pod-reader-rb --role=pod-reader --serviceaccount=<ns>:app-sa $do` |
| ClusterRoleBinding | `k create clusterrolebinding nodes-rb --clusterrole=node-reader --user=jane $do` |
| ResourceQuota | `k create quota q --hard=requests.cpu=1,requests.memory=1Gi,pods=10 $do` |
| Ingress | `k create ingress web --class=nginx --rule="web.example.com/*=web-svc:80" $do` |
| PodDisruptionBudget | `k create pdb web-pdb --selector=app=web --min-available=2 $do` |
| PriorityClass | `k create priorityclass high --value=100000 --description="critical apps" $do` |
| HPA | `k autoscale deploy web --min=2 --max=5 --cpu=70% $do` (v1.37 syntax; `--cpu-percent=70` is the deprecated pre-v1.34 form) |
| Namespace | `k create ns dev $do` |
| **No generator** | DaemonSet, StatefulSet, PV, PVC, NetworkPolicy, LimitRange, StorageClass, CRD → copy from kubernetes.io docs, or convert a Deployment YAML |

Deployment → DaemonSet: change `kind`, delete `replicas`, `strategy` and `status`. Deployment → StatefulSet: change `kind`, add `serviceName`, delete `strategy` and `status`.

---

## 3. Pods

```bash
k run web --image=nginx:1.27 --port=80 --expose            # Pod + ClusterIP Service named web
k run bb --image=busybox:1.36 --env=MODE=dev --labels=tier=be --command -- sleep 3600
k exec -it web -- sh                                       # shell (use -c <container> for multi-container)
k exec web -c sidecar -- cat /var/log/app.log
k get pod web -o yaml > web.yaml; vim web.yaml; k replace --force -f web.yaml   # change immutable fields
k delete pod web $now
```

---

## 4. Deployments, rollouts, strategies

```bash
k create deploy web --image=nginx:1.27 --replicas=3        # container name will be "nginx"
k scale deploy web --replicas=5
k set image deploy/web nginx=nginx:1.27-alpine             # <container>=<image>
k annotate deploy/web kubernetes.io/change-cause="nginx 1.27-alpine" --overwrite
k rollout status deploy/web
k rollout history deploy/web                               # add --revision=2 for detail
k rollout undo deploy/web                                  # previous revision
k rollout undo deploy/web --to-revision=1
k rollout pause deploy/web; k set image ...; k set resources ...; k rollout resume deploy/web
k rollout restart deploy/web                               # re-read ConfigMaps/Secrets used as env
k set resources deploy/web -c nginx --requests=cpu=100m,memory=128Mi --limits=cpu=200m,memory=256Mi
k set env deploy/web --from=configmap/app-cfg              # or KEY=value, or --from=secret/db --prefix=DB_
k set serviceaccount deploy/web app-sa
k patch deploy web -p '{"spec":{"strategy":{"rollingUpdate":{"maxSurge":1,"maxUnavailable":0}}}}'
```

Blue/green = two Deployments + **switch the Service selector**:
```bash
k patch svc web -p '{"spec":{"selector":{"app":"web","version":"green"}}}'
```
Canary = stable + canary Deployments that **share the Service's selector label**; traffic ≈ replica ratio (8 stable + 2 canary ≈ 80/20).

---

## 5. Jobs and CronJobs

```bash
k create job hello --image=busybox:1.36 -- sh -c 'echo hello'
k create cronjob backup --image=busybox:1.36 --schedule="0 2 * * *" -- sh -c 'date'
k create job backup-manual --from=cronjob/backup           # run a CronJob now
k patch cronjob backup -p '{"spec":{"suspend":true}}'
k get cronjob,job,pod
k logs job/hello
k wait --for=condition=complete job/hello --timeout=120s
```
Edit generated YAML for: `completions`, `parallelism`, `backoffLimit`, `activeDeadlineSeconds`, `ttlSecondsAfterFinished`, `successfulJobsHistoryLimit`, `failedJobsHistoryLimit`, `concurrencyPolicy`, `startingDeadlineSeconds`, `timeZone`.

---

## 6. Services and DNS

```bash
k expose deploy web --port=80 --target-port=8080 --name=web-svc               # ClusterIP
k expose deploy web --port=80 --type=NodePort --name=web-np
k patch svc web-np -p '{"spec":{"ports":[{"port":80,"nodePort":30080}]}}'      # pin a nodePort
k get svc,endpointslices -o wide
k get endpointslices -l kubernetes.io/service-name=web-svc                     # who is behind it?
k get pods -l app=web --show-labels                                            # do labels match the selector?
k port-forward svc/web-svc 8080:80
```

Service DNS: `<svc>.<ns>.svc.cluster.local` (short `<svc>.<ns>` works across namespaces).

---

## 7. Ingress

```bash
k create ingress shop --class=nginx \
  --rule="shop.example.com/api*=api-svc:8080" \
  --rule="shop.example.com/*=web-svc:80"                  # trailing * = Prefix, none = Exact
k create ingress secure --class=nginx --rule="secure.example.com/*=web-svc:80,tls=web-tls"
k describe ingress shop                                  # check backends resolve to endpoints
curl -s -H "Host: shop.example.com" http://<node-ip>:<ingress-controller-nodeport>/api
```

---

## 8. NetworkPolicy (no generator — memorise this shape)

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: backend-allow-frontend
  namespace: prod
spec:
  podSelector:
    matchLabels:
      app: backend            # the pods being protected
  policyTypes: ["Ingress", "Egress"]
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: frontend       # same element + namespaceSelector would mean AND
    ports:
    - protocol: TCP
      port: 80
  egress:
  - to:
    - namespaceSelector: {}   # DNS anywhere in the cluster
    ports:
    - protocol: UDP
      port: 53
    - protocol: TCP
      port: 53
```

```bash
k get netpol -A; k describe netpol <name> -n <ns>        # read existing policies before changing labels
k label pod client app=frontend --overwrite              # "make traffic work without editing policies"
```

---

## 9. ConfigMaps and Secrets

```bash
k create cm app-cfg --from-literal=MODE=prod --from-file=nginx.conf
k create secret generic db --from-literal=user=admin --from-literal=password='p@ss'
k get secret db -o jsonpath='{.data.password}' | base64 -d; echo
echo -n 'p@ss' | base64                                   # -n avoids a trailing newline
k set env deploy/web --from=secret/db --prefix=DB_
```

```yaml
# consumption patterns inside a container spec
env:
- name: DB_PASSWORD
  valueFrom:
    secretKeyRef: {name: db, key: password}
- name: MODE
  valueFrom:
    configMapKeyRef: {name: app-cfg, key: MODE}
envFrom:
- configMapRef: {name: app-cfg}
- secretRef: {name: db}
volumeMounts:
- {name: cfg, mountPath: /etc/app, readOnly: true}
# pod spec level:
# volumes:
# - name: cfg
#   configMap: {name: app-cfg}            # or  secret: {secretName: db, defaultMode: 0400}
```

---

## 10. ServiceAccounts, RBAC, auth

```bash
k create sa app-sa -n dev
k create role pod-reader -n dev --verb=get,list,watch --resource=pods,pods/log
k create rolebinding pod-reader-rb -n dev --role=pod-reader --serviceaccount=dev:app-sa
k create rolebinding dev-view -n dev --clusterrole=view --user=jane             # ClusterRole scoped to one ns
k auth can-i list pods -n dev --as=system:serviceaccount:dev:app-sa
k auth can-i --list -n dev --as=system:serviceaccount:dev:app-sa
k auth whoami
k create token app-sa -n dev --duration=1h
k get rolebindings,clusterrolebindings -A -o wide | grep app-sa                 # who is bound to what?
```

---

## 11. Requests, limits, quotas, QoS

```bash
k create quota dev-q -n dev --hard=requests.cpu=1,requests.memory=1Gi,limits.cpu=2,limits.memory=2Gi,pods=10
k describe quota -n dev                     # Used vs Hard
k describe limitrange -n dev                # defaults injected into new pods
k get pod web -o jsonpath='{.status.qosClass}'; echo
k describe rs -l app=web | grep -i -A3 events   # "exceeded quota" / "must specify limits" shows here
```

---

## 12. Security context (container level unless noted)

```yaml
securityContext:              # POD level: runAsUser, runAsGroup, fsGroup, runAsNonRoot, seccompProfile, supplementalGroups
  runAsUser: 1000
  runAsGroup: 3000
  fsGroup: 2000
containers:
- name: app
  image: busybox:1.36
  command: ["sh", "-c", "sleep 3600"]
  securityContext:            # CONTAINER level wins over pod level for the same field
    runAsNonRoot: true
    allowPrivilegeEscalation: false
    readOnlyRootFilesystem: true
    capabilities:
      add: ["NET_ADMIN", "SYS_TIME"]   # no CAP_ prefix
      drop: ["ALL"]
    seccompProfile:
      type: RuntimeDefault
```

```bash
k exec app -- id; k exec app -- sh -c 'grep Cap /proc/1/status'
k label ns dev pod-security.kubernetes.io/enforce=restricted --overwrite      # Pod Security Admission
```

---

## 13. Probes

```yaml
readinessProbe:
  httpGet: {path: /healthz, port: 8080}
  initialDelaySeconds: 5
  periodSeconds: 10
livenessProbe:
  exec:
    command: ["sh", "-c", "test -f /tmp/healthy"]
  failureThreshold: 3
startupProbe:
  tcpSocket: {port: 8080}
  failureThreshold: 30        # 30 x 10s = up to 300s to start
  periodSeconds: 10
```

---

## 14. Volumes

```yaml
volumes:
- name: scratch
  emptyDir: {}                # or {medium: Memory, sizeLimit: 64Mi}
- name: host
  hostPath: {path: /data, type: DirectoryOrCreate}
- name: data
  persistentVolumeClaim: {claimName: data-pvc}
```

```bash
k get pv,pvc,sc
k describe pvc data-pvc       # Pending? check storageClassName, accessModes, size, volumeBindingMode
```

---

## 15. Observability: logs, top, events

```bash
k logs web                         # -c <ctr>, -p (previous crash), -f, --since=1h, --tail=50, --timestamps
k logs -l app=web --all-containers --prefix --max-log-requests=10
k logs deploy/web; k logs job/hello
k logs web -c app > /opt/course/1/web.log      # tasks often ask for output in a file
k top pod -n dev --sort-by=cpu --containers    # needs metrics-server
k top node
k get events -n dev --sort-by=.lastTimestamp
k events -n dev --for pod/web
k get pod web -o jsonpath='{.status.containerStatuses[0].restartCount}'
k get pod web -o jsonpath='{.status.containerStatuses[0].lastState.terminated.reason}'   # OOMKilled? Error?
```

---

## 16. Debugging

```bash
k describe pod web | sed -n '/Events:/,$p'                       # bottom of describe = the why
k debug -it web --image=busybox:1.36 --target=nginx               # ephemeral container sharing the process namespace
k debug web -it --copy-to=web-dbg --container=nginx -- sh         # debug a copy, override the command
k debug node/<node> -it --image=busybox:1.36                      # node filesystem at /host
k run tmp --rm -it --image=busybox:1.36 --restart=Never -- wget -qO- -T 2 http://web-svc.dev
k run tmp --rm -it --image=busybox:1.36 --restart=Never -- nslookup web-svc.dev.svc.cluster.local
k run tmp --rm -it --image=curlimages/curl:8.10.1 --restart=Never -- curl -s -m 3 http://web-svc.dev
```

| Symptom | First look |
|---|---|
| `Pending` | `describe` events: insufficient cpu/memory, taints, nodeSelector, unbound PVC |
| `ImagePullBackOff` / `ErrImagePull` | image name/tag typo, registry auth (`imagePullSecrets`) |
| `CrashLoopBackOff` | `logs -p`, wrong command/args, failing liveness probe |
| `CreateContainerConfigError` | missing ConfigMap/Secret/key; `runAsNonRoot` with a root image |
| `OOMKilled` / exit 137 | memory limit too low |
| Service gives no answer | `get endpointslices` empty → selector/labels/readiness/targetPort |

---

## 17. API discovery and deprecations

```bash
k api-resources | grep -i cronjob             # NAME, SHORTNAMES, APIVERSION, NAMESPACED, KIND
k api-resources --api-group=apps
k api-versions | grep -E 'batch|networking'
k explain cronjob.spec.jobTemplate.spec --recursive | less
k explain ingress --api-version=networking.k8s.io/v1
kubectl convert -f old.yaml --output-version apps/v1   # only if the kubectl-convert plugin is installed
```

---

## 18. Helm

```bash
helm repo add examples https://helm.github.io/examples && helm repo update
helm search repo examples --versions
helm show values examples/hello-world > values.yaml
helm install web examples/hello-world -n web --create-namespace --set replicaCount=2 -f values.yaml
helm list -A                                   # filters: --pending, --failed, --uninstalled (Helm 3 only: -a = all statuses; Helm 4 lists all by default)
helm upgrade web examples/hello-world -n web --set replicaCount=3 --reuse-values
helm history web -n web
helm rollback web 1 -n web
helm get values web -n web --all; helm get manifest web -n web
helm template web examples/hello-world --set replicaCount=2 > rendered.yaml
helm pull examples/hello-world --untar
helm uninstall web -n web
```

---

## 19. Kustomize

```bash
k kustomize overlays/prod                 # render only
k apply -k overlays/prod                  # render + apply
k diff -k overlays/prod
k delete -k overlays/prod
```

---

## 20. Container images (podman or docker — same verbs)

```bash
podman build -t myapp:1.0 .                                     # Dockerfile in current dir
podman build -t myapp:2.0 -f Dockerfile.prod --build-arg VERSION=2 .
podman tag myapp:1.0 registry.example.com/team/myapp:1.0
podman images; podman image inspect myapp:1.0
podman save -o /opt/course/1/myapp.tar myapp:1.0                # docker-archive (default)
podman save --format oci-archive -o /opt/course/1/myapp-oci.tar myapp:1.0
podman load -i myapp.tar
podman run --rm -p 8080:80 myapp:1.0                            # quick local test
docker build -t myapp:1.0 . && docker save -o myapp.tar myapp:1.0
```

---

## 21. Output formatting (answers written to files)

```bash
k get pods -o name                                        # pod/web-123...
k get pods -o wide --show-labels
k get pods -o jsonpath='{.items[*].metadata.name}'
k get pods -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[*].image}{"\n"}{end}'
k get pods -o custom-columns=NAME:.metadata.name,IMAGE:.spec.containers[*].image,NODE:.spec.nodeName
k get pods --sort-by=.metadata.creationTimestamp
k get pods --sort-by='.status.containerStatuses[0].restartCount'
k get nodes -o jsonpath='{.items[*].status.addresses[?(@.type=="InternalIP")].address}'
k get pods --field-selector=status.phase=Running -l app=web --no-headers | wc -l
k top pod --no-headers --sort-by=cpu | head -1 | awk '{print $1}' > /opt/course/5/top-pod.txt
```

---

## 22. Edit, patch, label, wait

```bash
k edit deploy web                  # if a change is rejected, kubectl saves it to /tmp/kubectl-edit-*.yaml
k replace --force -f /tmp/kubectl-edit-123.yaml
k patch deploy web -p '{"spec":{"replicas":3}}'                                   # strategic merge
k patch deploy web --type=json -p='[{"op":"replace","path":"/spec/template/spec/containers/0/image","value":"nginx:1.27"}]'
k label pod web tier=frontend --overwrite; k label pod web tier-                  # add/replace, remove
k annotate pod web owner=team-a
k apply -f app.yaml; k diff -f app.yaml
k wait --for=condition=Ready pod/web --timeout=60s
k get deploy web -w
```

---

## 23. Cleanup and speed

```bash
k delete pod web $now
k delete deploy,svc -l app=web
k delete -f app.yaml
k delete ns scratch                              # deletes everything inside it
```

> **Exam tip:** After every task, run one verification command (`get`, `describe`, `logs`, `auth can-i`, `curl`) before moving on. A task you think you finished but didn't verify is the most common way to lose points.
