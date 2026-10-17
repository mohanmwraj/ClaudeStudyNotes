# Commands — Application Observability and Maintenance

Every command here was written for kubectl v1.33+ and is valid on the exam's v1.37. `alias k=kubectl` works the same way. In the exam use `k` and `export do="--dry-run=client -o yaml"` ([00 setup](../00-Exam-Overview-and-Setup/README.md)). Example names: namespace `app`, Deployment/Pod `web`, container `nginx`.

---

## 1. Context and namespace (every task)

```bash
kubectl config use-context <ctx>                                  # switch to the cluster the task names
kubectl config current-context                                    # confirm
kubectl config set-context --current --namespace=app              # default namespace for the session
kubectl config view --minify -o jsonpath='{..namespace}'; echo    # which namespace am I in?
```

## 2. Discover APIs and versions (API deprecations)

```bash
kubectl api-resources                                             # NAME SHORTNAMES APIVERSION NAMESPACED KIND
kubectl api-resources | grep -iE '^(cronjobs|ingresses|poddisruptionbudgets|horizontalpodautoscalers) '   # current versions
kubectl api-resources --api-group=apps                            # resources of one group
kubectl api-resources --namespaced=false                          # cluster-scoped kinds
kubectl api-resources -o wide                                     # + VERBS, CATEGORIES
kubectl api-resources -o name                                     # deployments.apps style names
kubectl api-versions                                              # every served group/version
kubectl api-versions | grep -E 'autoscaling|policy|batch|networking'   # quick version check
kubectl explain cronjob | head -3                                 # GROUP / KIND / VERSION header
kubectl explain hpa --api-version=autoscaling/v1                  # schema of a non-preferred version
kubectl explain ingress.spec.rules.http.paths --recursive         # every field below a path
kubectl explain deployment.spec.selector                          # docs for one field
kubectl get --raw /apis/autoscaling                               # versions + preferredVersion (JSON)
kubectl get deployments.v1.apps -A                                # fully qualified resource.version.group
kubectl get hpa.v1.autoscaling web -o yaml                        # same object served in another version
```

## 3. Migrate manifests

```bash
kubectl apply --dry-run=server -f old.yaml                        # shows "no matches for kind ..." for removed APIs
sed -i 's#^apiVersion: batch/v1beta1#apiVersion: batch/v1#' cj.yaml      # apiVersion-only migrations
sed -i 's#^apiVersion: policy/v1beta1#apiVersion: policy/v1#' pdb.yaml
sed -i 's#^apiVersion: autoscaling/v2beta2#apiVersion: autoscaling/v2#' hpa.yaml
yq --version && yq -i '.apiVersion = "batch/v1"' cj.yaml          # mikefarah yq v4 syntax (check the flavour first)
vim deploy.yaml                                                   # apps/v1: add spec.selector.matchLabels
vim ingress.yaml                                                  # v1: pathType + backend.service.name/port
kubectl apply --dry-run=server -f fixed.yaml                      # validate against the live API (no save)
kubectl apply -f fixed.yaml -n app                                # apply in the namespace the task names
kubectl apply -f fixed.yaml --warnings-as-errors                  # fail on any deprecation warning
kubectl diff -f fixed.yaml                                        # what would change on the live object
kubectl convert -f old.yaml --output-version apps/v1 > new.yaml   # LAB ONLY: needs the kubectl-convert plugin
kubectl get --raw /metrics | grep apiserver_requested_deprecated_apis    # deprecated APIs requested since start
grep -rnE '^apiVersion: *(extensions/|apps/v1beta|batch/v1beta1|policy/v1beta1|autoscaling/v2beta|networking.k8s.io/v1beta1)' .   # scan files
kubectl get endpointslices -l kubernetes.io/service-name=web      # replacement for the deprecated `get endpoints`
```

## 4. Generate YAML skeletons (then add probes in vim)

```bash
kubectl run web --image=nginx:1.27 --port=80 --dry-run=client -o yaml > web-pod.yaml                 # Pod
kubectl create deployment web --image=nginx:1.27 --port=80 --replicas=2 --dry-run=client -o yaml > web-deploy.yaml
kubectl run probe-demo --image=busybox:1.36 --dry-run=client -o yaml --command -- sh -c 'touch /tmp/healthy; sleep 3600' > probe-pod.yaml
kubectl create deployment legacy-web --image=nginx:1.27 --replicas=3 --dry-run=client -o yaml > deploy.yaml   # clean apps/v1
kubectl create cronjob report --image=busybox:1.36 --schedule="*/5 * * * *" --dry-run=client -o yaml -- sh -c 'date' > cj.yaml
kubectl create ingress shop --class=nginx --rule="shop.example.com/api*=api-svc:8080" --dry-run=client -o yaml > ing.yaml
kubectl create pdb web-pdb --selector=app=web --min-available=2 --dry-run=client -o yaml > pdb.yaml
kubectl autoscale deployment web --min=2 --max=6 --cpu=70% --dry-run=client -o yaml > hpa.yaml   # autoscaling/v2 HPA (old form --cpu-percent=70: deprecated since v1.34, still works on v1.37 with a warning)
kubectl autoscale deployment web --min=2 --max=6 --cpu=500m --memory=200Mi --dry-run=client -o yaml   # average-value targets
kubectl explain pod.spec.containers.livenessProbe                 # probe field docs
kubectl explain pod.spec.containers.startupProbe --recursive      # all probe sub-fields
```

## 5. Add / modify probes

```bash
kubectl edit deployment web                                       # add probes under spec.template.spec.containers[]
kubectl patch deployment web -p '{"spec":{"template":{"spec":{"containers":[{"name":"nginx","readinessProbe":{"httpGet":{"path":"/","port":80},"periodSeconds":10}}]}}}}'   # merge by container name
kubectl patch deployment web --type=json -p='[{"op":"add","path":"/spec/template/spec/containers/0/livenessProbe","value":{"tcpSocket":{"port":80},"periodSeconds":20}}]'   # JSON patch by index
kubectl patch deployment web --type=json -p='[{"op":"replace","path":"/spec/template/spec/containers/0/livenessProbe/httpGet/port","value":80}]'   # fix a wrong port
kubectl patch deployment web --type=json -p='[{"op":"remove","path":"/spec/template/spec/containers/0/livenessProbe"}]'   # drop a probe
kubectl rollout status deployment web                             # wait for the new ReplicaSet
kubectl edit pod web                                              # bare Pod: rejected, copy saved to /tmp/kubectl-edit-*.yaml
kubectl replace --force -f /tmp/kubectl-edit-XXXX.yaml            # delete + recreate with the probe
kubectl get pod web -o yaml > web.yaml && vim web.yaml && kubectl replace --force -f web.yaml   # same, explicit
```

## 6. Inspect: get, describe, jsonpath, custom-columns

```bash
kubectl get pods -o wide                                          # IP, NODE, READINESS GATES
kubectl get pods -w                                               # watch
kubectl get pods --show-labels                                    # all labels
kubectl get pods -L app,tier                                      # labels as columns
kubectl get pods -l app=web                                       # label selector
kubectl get pods --field-selector=status.phase!=Running           # field selector
kubectl get pods -A --field-selector=spec.nodeName=worker-1       # Pods on one node
kubectl get deploy,rs,pods,svc,endpointslices -n app              # the whole chain at once
kubectl describe pod web                                          # states, probes, events
kubectl describe deploy web                                       # replicas, conditions, events
kubectl describe rs -l app=web                                    # FailedCreate (quota / PSA / admission)
kubectl get pod web -o jsonpath='{.status.phase}{"\n"}'                                         # phase
kubectl get pod web -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}{"\n"}'         # Ready?
kubectl get pod web -o jsonpath='{.status.containerStatuses[0].restartCount}{"\n"}'             # restarts
kubectl get pod web -o jsonpath='{.status.containerStatuses[?(@.name=="nginx")].ready}{"\n"}'   # one container ready?
kubectl get pod web -o jsonpath='{.status.containerStatuses[0].lastState.terminated.reason}{"\n"}'   # OOMKilled / Error
kubectl get pod web -o jsonpath='{.status.containerStatuses[0].lastState.terminated.exitCode}{"\n"}' # exit code
kubectl get pod web -o jsonpath='{.status.containerStatuses[0].state.waiting.reason}{"\n"}'     # CrashLoopBackOff ...
kubectl get pod web -o jsonpath='{.status.qosClass}{"\n"}'                                      # QoS class
kubectl get pod web -o jsonpath='{.status.initContainerStatuses[*].name}{"\n"}'                 # init containers + native sidecars
kubectl get pods -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.phase}{"\n"}{end}' # one line per Pod
kubectl get pods -o custom-columns='NAME:.metadata.name,RESTARTS:.status.containerStatuses[0].restartCount,QOS:.status.qosClass'
kubectl get pods --no-headers -o custom-columns=:metadata.name    # names only
kubectl get pods --sort-by='.status.containerStatuses[0].restartCount'    # ascending by restarts
kubectl get pods --sort-by=.metadata.creationTimestamp            # oldest first
```

## 7. Events

```bash
kubectl get events -n app                                         # LAST SEEN TYPE REASON OBJECT MESSAGE
kubectl get events -n app --sort-by=.metadata.creationTimestamp   # time order (reliable)
kubectl get events -n app --sort-by=.lastTimestamp                # classic idiom
kubectl get events -n app --field-selector type=Warning           # warnings only
kubectl get events -n app --field-selector involvedObject.name=web,involvedObject.kind=Pod   # one object
kubectl get events -n app --field-selector reason=Unhealthy       # probe failures
kubectl get events -n app --field-selector reason=FailedScheduling   # scheduling problems
kubectl get events -A --field-selector type=Warning -w            # stream warnings cluster-wide
kubectl get events -n app -o jsonpath='{range .items[*]}{.reason}{"\n"}{end}' | sort | uniq -c   # reason histogram
kubectl events -n app                                             # newer command, sorted by time
kubectl events -n app --for pod/web                               # events of one object
kubectl events -n app --types=Warning                             # filter by type
kubectl events -A --types=Warning -w                              # watch warnings everywhere
```

## 8. Resource usage (metrics-server)

```bash
kubectl get apiservices | grep metrics                            # v1beta1.metrics.k8s.io must be Available=True
kubectl -n kube-system get deploy metrics-server                  # add-on running?
kubectl top node                                                  # CPU/memory per node (+ % of allocatable)
kubectl top node --sort-by=memory --no-headers                    # highest memory first
kubectl top node --show-capacity                                  # % of capacity instead of allocatable
kubectl top pod -n app                                            # per Pod
kubectl top pod -n app --sort-by=cpu                              # highest CPU first
kubectl top pod -n app --sort-by=memory --containers              # per container
kubectl top pod -A --sort-by=memory                               # all namespaces (NAMESPACE = 1st column)
kubectl top pod -n app -l app=web --sum                           # selector + totals line
kubectl get --raw /apis/metrics.k8s.io/v1beta1/namespaces/app/pods   # raw Metrics API (version: check api-versions)
kubectl describe node worker-1 | grep -A8 "Allocated resources"   # requests/limits vs allocatable (not usage)
```

## 9. Wait and rollout

```bash
kubectl wait --for=condition=Ready pod/web --timeout=60s          # Pod Ready (default timeout 30s)
kubectl wait --for=condition=Ready pod -l app=web --timeout=120s  # all matching Pods
kubectl wait --for=condition=Available deployment/web --timeout=120s   # Deployment available
kubectl wait --for=condition=Complete job/report --timeout=120s   # Job finished
kubectl wait --for=condition=Failed job/report --timeout=60s      # Job failed
kubectl wait --for=jsonpath='{.status.phase}'=Running pod/web     # any field value
kubectl wait --for=jsonpath='{.status.readyReplicas}'=3 deploy/web   # numeric field
kubectl wait --for=delete pod/web --timeout=60s                   # until deleted
kubectl wait --for=create secret/web-tls --timeout=30s            # until created
kubectl rollout status deployment/web --timeout=2m                # rollout progress
kubectl rollout history deployment/web                            # revisions
kubectl rollout undo deployment/web                               # back to the previous revision
```

## 10. Logs

```bash
kubectl logs web                                                  # single-container Pod
kubectl logs web -c sidecar                                       # one container
kubectl logs web --all-containers --prefix                        # all containers, prefixed
kubectl logs web -p                                               # previous (crashed) instance
kubectl logs web -c app --previous --tail=50                      # previous instance, last 50 lines
kubectl logs web -f                                               # follow
kubectl logs web --tail=20                                        # last 20 lines
kubectl logs web --since=1h                                       # last hour
kubectl logs web --since-time=2026-10-17T08:00:00Z                # since an RFC3339 time
kubectl logs web --timestamps                                     # prefix RFC3339Nano timestamps
kubectl logs web --limit-bytes=2000                               # cap the output size
kubectl logs web -c init-db                                       # init container logs
kubectl logs web -c debugger-x7k2p                                # ephemeral container logs
kubectl logs deploy/web                                           # one Pod of a Deployment
kubectl logs deploy/web --all-pods                                # every Pod of it (v1.31+)
kubectl logs job/report                                           # Pod of a Job
kubectl logs -l app=web --prefix                                  # by label (default tail 10 per Pod!)
kubectl logs -l app=web --tail=-1 --prefix                        # by label, every line
kubectl logs -l app=web -f --max-log-requests=10                  # follow more than 5 Pods
kubectl logs -l batch.kubernetes.io/job-name=report               # all Pods of a Job
kubectl get --raw "/api/v1/namespaces/app/pods/web/log?container=nginx&tailLines=5"   # raw API
```

## 11. Exec, debug, port-forward, cp, temporary Pods

```bash
kubectl exec web -- ls /usr/share/nginx/html                      # one-off command
kubectl exec -it web -c nginx -- sh                               # interactive shell
kubectl exec deploy/web -- env                                    # a Pod of the Deployment
kubectl exec web -- sh -c 'cat /etc/resolv.conf; env | sort'      # shell features need sh -c
kubectl exec web -- wget -qO- -T 2 http://localhost:80/           # test the app from inside
kubectl debug -it web --image=busybox:1.36 --target=nginx         # ephemeral container in nginx's PID namespace
kubectl debug -it web --image=busybox:1.36 --target=nginx --profile=general -- sh   # + SYS_PTRACE (/proc/<pid>/root)
kubectl debug web --image=busybox:1.36 --target=nginx -c psdump -- ps   # non-interactive ...
kubectl logs web -c psdump                                        # ... then read its output
kubectl debug -it web --copy-to=web-debug --image=busybox:1.36 --share-processes   # copy + debug container
kubectl debug crashy -it --copy-to=crashy-debug --container=crashy -- sh    # copy with a changed command
kubectl debug web --copy-to=web-debug --set-image='*=busybox:1.36'          # copy with changed images
kubectl debug node/worker-1 -it --image=busybox:1.36             # node shell, host fs at /host
kubectl debug node/worker-1 -it --image=busybox:1.36 --profile=sysadmin    # privileged node shell
kubectl port-forward pod/web 8080:80                              # local 8080 -> Pod 80
kubectl port-forward svc/web 8080:80                              # via the Service's targetPort (one Pod)
kubectl port-forward --address 0.0.0.0 deploy/web 8080:80         # listen on all interfaces
kubectl cp app/web:/etc/nginx/nginx.conf ./nginx.conf             # Pod -> local (needs tar)
kubectl cp ./index.html app/web:/usr/share/nginx/html/index.html -c nginx   # local -> Pod
kubectl run tmp --rm -it --image=busybox:1.36 --restart=Never -- wget -qO- -T 2 http://web.app.svc.cluster.local   # HTTP test
kubectl run tmp --rm -it --image=busybox:1.36 --restart=Never -- nslookup web.app.svc.cluster.local              # DNS test
kubectl run tmp --rm -it --image=curlimages/curl:8.10.1 --restart=Never -- curl -sS -m 3 http://web.app/healthz   # curl test
kubectl run tmp -n app --rm -i -q --image=busybox:1.36 --restart=Never -- wget -qO- -T 2 http://web > out.txt     # capture cleanly
```

## 12. Fix common breakages

```bash
kubectl set image deploy/web nginx=nginx:1.27                     # wrong image / tag
kubectl set image pod/web nginx=nginx:1.27                        # image is mutable even on a bare Pod
kubectl set env deploy/web DB_HOST=db.app.svc                     # missing env var
kubectl set env deploy/web --from=configmap/app-config            # env from a ConfigMap
kubectl set resources deploy/web -c=nginx --requests=cpu=100m,memory=64Mi --limits=memory=128Mi   # requests/limits
kubectl patch pod web --subresource resize -p '{"spec":{"containers":[{"name":"nginx","resources":{"limits":{"memory":"256Mi"}}}]}}'   # in-place resize (v1.35+)
kubectl create configmap app-config --from-literal=db_url=postgres://db:5432/app   # missing ConfigMap
kubectl patch configmap app-config -p '{"data":{"db_url":"postgres://db:5432/app"}}'   # missing key
kubectl patch svc web -p '{"spec":{"selector":{"app":"web"}}}'    # Service selector typo
kubectl patch svc web -p '{"spec":{"ports":[{"port":80,"targetPort":8080}]}}'   # wrong targetPort
kubectl label node worker-1 disktype=ssd                          # satisfy a nodeSelector
kubectl replace --force -f pod.yaml                               # recreate a bare Pod with new spec
kubectl rollout restart deploy/web                                # new Pods, same spec
kubectl delete pod web --force --grace-period=0                   # stuck Terminating (last resort)
kubectl patch pod web --type=merge -p '{"metadata":{"finalizers":null}}'   # remove finalizers (only if you own them)
```

## 13. Service / DNS debugging

```bash
kubectl get svc web -o wide                                       # selector, ports
kubectl describe svc web | grep -E 'Selector|Port|Endpoints'      # quick view (ready endpoints only)
kubectl get endpointslices -l kubernetes.io/service-name=web      # endpoints (all addresses)
kubectl get endpointslices -l kubernetes.io/service-name=web -o jsonpath='{range .items[*].endpoints[*]}{.addresses[0]} ready={.conditions.ready}{"\n"}{end}'
kubectl get pods -l app=web --show-labels                         # Pods the selector should match
kubectl get pod <pod> -o jsonpath='{.spec.containers[*].ports}{"\n"}'   # container ports (targetPort check)
kubectl get pods -n kube-system -l k8s-app=kube-dns               # CoreDNS up?
kubectl get networkpolicy -n app                                  # policies that may block traffic
```

## 14. RBAC checks

```bash
kubectl auth can-i list pods -n app --as=system:serviceaccount:app:reader   # yes / no
kubectl auth can-i --list -n app --as=system:serviceaccount:app:reader      # everything allowed
kubectl auth whoami                                               # current identity
kubectl get pod web -o jsonpath='{.spec.serviceAccountName}{"\n"}'          # SA used by the app
kubectl create role pod-reader -n app --verb=get,list,watch --resource=pods
kubectl create rolebinding reader-binding -n app --role=pod-reader --serviceaccount=app:reader
```

## 15. Node checks (brief)

```bash
kubectl get nodes -o wide                                         # Ready / NotReady / SchedulingDisabled
kubectl describe node worker-1 | grep -A6 Conditions              # MemoryPressure, DiskPressure, PIDPressure, Ready
kubectl get nodes -o custom-columns=NAME:.metadata.name,TAINTS:.spec.taints   # taints
kubectl get nodes --show-labels                                   # labels for nodeSelector/affinity
```

## 16. Write results to files

```bash
mkdir -p /opt/course/1                                            # create the target directory first
kubectl top pod -n app --sort-by=cpu --no-headers | head -1 | awk '{print $1}' > /opt/course/1/pod.txt   # top Pod name
kubectl top pod -A --sort-by=memory --no-headers | head -1 | awk '{print $2}' > /opt/course/1/pod.txt    # with -A: column 2
kubectl top node --sort-by=cpu --no-headers | head -1 | awk '{print $1}' > /opt/course/1/node.txt       # top node
kubectl logs web -c sidecar > /opt/course/1/sidecar.log           # logs of one container
kubectl logs web -p > /opt/course/1/previous.log                  # previous instance
kubectl get events -n app --field-selector type=Warning --sort-by=.metadata.creationTimestamp > /opt/course/1/events.txt
kubectl get pod web -o jsonpath='{.status.containerStatuses[0].restartCount}' > /opt/course/1/restarts.txt
echo 'kubectl top pod -A --sort-by=memory' > /opt/course/1/cmd.sh # when the task wants the COMMAND itself
cat /opt/course/1/pod.txt                                         # always verify the file content
```

## 17. Cleanup

```bash
kubectl delete pod web-debug crashy-debug --ignore-not-found      # debug copies
kubectl delete pod -l run=tmp --ignore-not-found                  # leftover temp Pods (kubectl run labels run=<name>)
kubectl delete pods -n app --field-selector=status.phase=Failed   # evicted / failed Pods
kubectl delete pods -n app --field-selector=status.phase=Succeeded   # completed Pods
kubectl get pods -A | grep node-debugger                          # find node debug Pods ...
kubectl delete pod node-debugger-worker-1-xxxxx                   # ... and delete them
kubectl delete namespace obs-top                                  # lab namespaces from this chapter
```
