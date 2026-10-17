# Commands - Cross-Cutting Skills and Bonus Topics

Exhaustive, grouped reference for this chapter. Every line has a `#` comment. Version notes refer to v1.37 (the exam version). Assumes:

```bash
alias k=kubectl                          # preconfigured on exam hosts (with completion)
export do="--dry-run=client -o yaml"     # re-export on every task host
export now="--force --grace-period=0"    # re-export on every task host
```

Explanations live in the topic files: [01 kubectl](01-kubectl-power-usage.md) · [02 output](02-output-formatting-jsonpath-and-custom-columns.md) · [03 labels/namespaces](03-labels-selectors-annotations-namespaces.md) · [04 scheduling](04-scheduling-and-placement.md) · [05 HPA](05-autoscaling-hpa.md) · [06 PDB](06-pod-disruption-budgets.md) · [07 YAML](07-yaml-essentials.md) · [08 shell](08-linux-vim-bash-tmux-for-the-exam.md).

---

## 1. Contexts and namespaces

```bash
ssh <task-host>                                          # task names a host: connect first; exit when done (no nested ssh)
k config get-contexts                                    # list contexts; * marks the current one
k config current-context                                 # print the current context
k config use-context k8s-c1                              # task names a context: switch first
k config set-context --current --namespace=dev           # default namespace for the current context
k config view --minify -o jsonpath='{..namespace}'; echo # show the current default namespace
k config view --minify                                   # kubeconfig of the current context only
k get pods -n dev --context=k8s-c2                       # one-off command against another context
k create ns dev                                          # create a namespace
k get ns --show-labels                                   # namespaces and their labels (kubernetes.io/metadata.name)
k label ns dev team=payments                             # label a namespace
k api-resources --namespaced=false -o name               # cluster-scoped kinds
k api-resources --namespaced=true -o name                # namespaced kinds
```

## 2. Discover fields and kinds

```bash
k explain pod.spec.containers.livenessProbe              # one level of a field, with descriptions
k explain deploy.spec.strategy --recursive               # whole subtree (names + types)
k explain pod.spec --recursive --max-depth=2             # limit the depth (kubectl v1.37+)
k explain pod.spec --recursive | grep -n -i -A6 '^ *tolerations'   # locate a field in the tree
k explain hpa.spec.behavior --api-version=autoscaling/v2 # explain a specific API version
k api-resources                                          # names, short names, apiVersion, namespaced, kind
k api-resources -o wide                                  # + verbs and categories
k api-resources --api-group=apps                         # kinds of one API group
k api-resources | grep -i ingress                        # find group/short name of a kind
k api-versions                                           # all served group/versions
k version --client                                       # kubectl version (decides e.g. autoscale flags)
k <command> -h                                           # usage with copy-ready examples
```

## 3. Generate YAML (no object is created)

```bash
k run web --image=nginx:1.27 --port=80 --labels=app=web $do > pod.yaml                  # Pod
k run bb --image=busybox:1.36 --restart=Never $do --command -- sh -c 'sleep 3600' > bb.yaml  # Pod with command
k run sel --image=nginx:1.27 $do --overrides='{"apiVersion":"v1","spec":{"nodeSelector":{"disktype":"ssd"}}}'  # Pod + field without a flag
k create deploy web --image=nginx:1.27 --replicas=3 --port=80 $do > deploy.yaml          # Deployment
k expose deploy web --port=80 --target-port=8080 --name=web-svc $do > svc.yaml          # Service for a workload
k create svc nodeport web --tcp=80:8080 --node-port=30080 $do > np.yaml                 # NodePort Service (selector app=web)
k create job hello --image=busybox:1.36 $do -- sh -c 'echo hi' > job.yaml               # Job
k create cj backup --image=busybox:1.36 --schedule='*/5 * * * *' $do -- sh -c date > cj.yaml   # CronJob
k create cm cfg --from-literal=MODE=prod $do > cm.yaml                                   # ConfigMap
k create secret generic db --from-literal=password='S3cr3t!' $do > secret.yaml           # Secret
k create sa app-sa $do > sa.yaml                                                         # ServiceAccount
k create ns dev $do > ns.yaml                                                            # Namespace
k create role pod-reader --verb=get,list,watch --resource=pods $do > role.yaml           # Role
k create rolebinding rb --role=pod-reader --serviceaccount=dev:app-sa $do > rb.yaml      # RoleBinding
k create quota q --hard=pods=10,requests.cpu=2,requests.memory=2Gi $do > quota.yaml      # ResourceQuota
k create ingress web --class=nginx --rule='web.example.com/*=web-svc:80' $do > ing.yaml  # Ingress
k create pdb web-pdb --selector=app=web --min-available=2 $do > pdb.yaml                 # PodDisruptionBudget
k create priorityclass high --value=1000000 --description='critical' $do > pc.yaml      # PriorityClass
k autoscale deploy web --min=2 --max=5 --cpu=70% $do > hpa.yaml                          # HPA (kubectl v1.34+, i.e. the exam's v1.37)
k autoscale deploy web --min=2 --max=5 --cpu-percent=70 $do > hpa.yaml                   # HPA (old kubectl v1.33 and older)
k get deploy web -o yaml > web-live.yaml                                                 # export a live object to edit
```

## 4. Create, apply, replace, delete

```bash
k create -f web.yaml                                     # create; fails if it already exists
k apply -f web.yaml                                      # create or update (3-way merge)
k apply -f dir/ -R                                       # every manifest in a directory tree
k apply -f web.yaml --dry-run=server                     # full server-side validation, nothing persisted
k apply --server-side -f web.yaml                        # server-side apply (field managers)
k apply --server-side --force-conflicts -f web.yaml      # take over conflicting fields
k diff -f web.yaml                                       # preview changes (exit 1 = differences)
k replace -f web.yaml                                    # full update; fails on immutable fields
k replace --force -f web.yaml                            # delete + re-create (immutable fields)
k replace --force -f /tmp/kubectl-edit-1234.yaml         # recover a rejected kubectl edit
k delete pod web $now                                    # immediate deletion (no graceful wait)
k delete pod web --now                                   # 1-second grace period
k delete pod web --wait=false                            # do not block the terminal
k delete pods -l app=web                                 # delete by label selector
k delete deploy,svc -l app=web                           # several kinds at once
k delete -f web.yaml                                     # delete what a file defines
```

## 5. Modify objects

```bash
k edit deploy web                                        # edit the live object in $KUBE_EDITOR / vi
KUBE_EDITOR=nano k edit svc web                          # one-off editor choice
k patch deploy web -p '{"spec":{"replicas":4}}'          # strategic merge patch (default)
k patch deploy web -p '{"spec":{"template":{"spec":{"containers":[{"name":"nginx","image":"nginx:1.27-alpine"}]}}}}'  # change one container by name
k patch deploy web --type=merge -p '{"metadata":{"annotations":{"owner":null}}}'   # JSON merge patch; null deletes
k patch svc web --type=json -p '[{"op":"replace","path":"/spec/ports/0/nodePort","value":30080}]'   # JSON patch by path
k patch deploy web --type=json -p '[{"op":"remove","path":"/spec/template/spec/containers/0/livenessProbe"}]'  # remove a field
k patch deploy web --patch-file=patch.yaml               # patch from a file
k set image deploy/web nginx=nginx:1.27-alpine           # container=image (triggers a rollout)
k set env deploy/web MODE=prod                           # add/change an env var
k set env deploy/web --from=configmap/cfg                # all keys of a ConfigMap as env vars
k set env deploy/web --list                              # show env vars
k set resources deploy web -c nginx --requests=cpu=100m,memory=128Mi --limits=cpu=200m,memory=256Mi   # requests/limits
k set serviceaccount deploy/web app-sa                   # change the pod template's ServiceAccount
k scale deploy web --replicas=5                          # replicas (an HPA will override this)
k annotate deploy web kubernetes.io/change-cause="image 1.27-alpine"   # shown in rollout history
```

## 6. Inspect and format output

```bash
k get pods -o wide                                       # + IP and node
k get pods -A                                            # all namespaces
k get pods -w                                            # watch for changes
k get pods --show-labels                                 # labels column
k get pods -L app,env                                    # chosen labels as columns
k get pod web -o yaml                                    # full object (find field paths here)
k get pods -o name                                       # pod/<name> lines
k get pods -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}'                  # names, one per line
k get pods -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.podIP}{"\n"}{end}'   # name<TAB>IP
k get nodes -o jsonpath='{.items[*].status.addresses[?(@.type=="InternalIP")].address}{"\n"}'   # node InternalIPs
k get pod web -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}{"\n"}'      # Ready condition
k get deploy web -o jsonpath='{.metadata.annotations.deployment\.kubernetes\.io/revision}{"\n"}'   # escaped dots
k get pods -o jsonpath-file=pods.tmpl                    # JSONPath template from a file
k get pods -o custom-columns='NAME:.metadata.name,NODE:.spec.nodeName,IMAGES:.spec.containers[*].image'   # own table
k get pods --no-headers -o custom-columns=NAME:.metadata.name                          # names only
k get pods -o custom-columns=NAME:.metadata.name,QOS:.status.qosClass                   # QoS class
k get pods --sort-by=.metadata.creationTimestamp         # oldest first
k get pods --sort-by='.status.containerStatuses[0].restartCount'                       # by restarts
k get pv --sort-by=.spec.capacity.storage                # by capacity
k get events -A --sort-by=.metadata.creationTimestamp    # event timeline
k get secret db -o jsonpath='{.data.password}' | base64 -d; echo                       # decode a Secret key
k get secret db -o go-template='{{range $k,$v := .data}}{{$k}}={{$v|base64decode}}{{"\n"}}{{end}}'   # decode all keys
k get pods -A -o jsonpath='{.items[*].spec.containers[*].image}' | tr -s '[[:space:]]' '\n' | sort | uniq -c   # images in use
k get pods -A -o jsonpath='{range .items[*]}{.spec.nodeName}{"\n"}{end}' | sort | uniq -c   # pods per node
k get deploy web -o kyaml                                # KYAML output (beta, default on since v1.35)
k get pods -o yaml | yq '.items[].metadata.name'         # yq (available on exam hosts) - names
k get pods -o yaml | yq '.items[] | select(.status.phase == "Running") | .metadata.name'   # yq filter (jq may be missing)
k get secret db -o yaml | yq '.data | map_values(@base64d)'   # yq: decode every Secret key
k get pods -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' > /opt/course/1/pods.txt   # write exactly to a file
cat -A /opt/course/1/pods.txt                            # check the file (tabs ^I, line ends $)
```

## 7. Labels, selectors, annotations, field selectors

```bash
k label pod web env=prod                                 # add a label
k label pod web env=dev --overwrite                      # change a label
k label pod web env-                                     # remove a label
k label pods -l app=web tier=frontend                    # bulk by selector
k label pods --all audit=true                            # every pod in the namespace
k label pod web --list                                   # list labels of one object
k get pods -l 'env in (dev,qa)'                          # set-based selector
k get pods -l 'env notin (prod)'                         # notin (also matches pods without env)
k get pods -l '!env'                                     # key absent
k get pods -l 'env,env!=prod'                            # has env, but not prod
k get pods -l 'app=web,tier=frontend'                    # AND
k get pods --field-selector status.phase=Running         # field selector
k get pods -A --field-selector spec.nodeName=node01      # pods on a node
k get pods -A --field-selector 'status.phase!=Running'   # not Running (CrashLoopBackOff is still Running!)
k get events --field-selector involvedObject.name=web,type=Warning   # events of one object
k get svc -A --field-selector spec.type=NodePort         # Service field selector (v1.37; not in v1.35 and older)
k annotate pod web owner=team-a                          # add an annotation
k annotate pod web owner=team-b --overwrite              # change it
k annotate pod web owner-                                # remove it
k get pod web -o jsonpath='{.metadata.annotations}{"\n"}'            # all annotations
k get endpointslices -l kubernetes.io/service-name=web   # does the Service selector match pods?
```

## 8. Scheduling and placement

```bash
k get nodes --show-labels                                # node labels
k get nodes -L kubernetes.io/hostname,topology.kubernetes.io/zone    # selected node labels as columns
k label node node01 disktype=ssd                         # label a node
k label node node01 disktype-                            # remove a node label
k taint nodes node01 dedicated=gpu:NoSchedule            # add a taint
k taint nodes node01 dedicated=gpu:NoSchedule-           # remove exactly that taint
k taint nodes node01 dedicated-                          # remove all taints with that key
k taint nodes node01 dedicated=ml:NoSchedule --overwrite # change a taint value
k get nodes -o custom-columns='NAME:.metadata.name,TAINTS:.spec.taints[*].key,EFFECTS:.spec.taints[*].effect'   # all taints
k describe node node01 | grep -i -A3 taints              # taints of one node
k describe node node01 | grep -A8 -i 'allocated resources'   # requested vs allocatable
k cordon node01                                          # mark unschedulable
k uncordon node01                                        # schedulable again
k patch deploy web -p '{"spec":{"template":{"spec":{"nodeSelector":{"disktype":"ssd"}}}}}'   # add nodeSelector
k patch deploy web --type=json -p '[{"op":"add","path":"/spec/template/spec/tolerations","value":[{"key":"dedicated","operator":"Equal","value":"gpu","effect":"NoSchedule"}]}]'   # add a toleration
k create priorityclass high --value=1000000 --description="critical"   # PriorityClass
k create priorityclass batch --value=1000 --preemption-policy=Never    # non-preempting class
k get pc                                                 # list PriorityClasses (incl. system-*)
k get pods -o custom-columns=NAME:.metadata.name,CLASS:.spec.priorityClassName,PRIO:.spec.priority   # pod priorities
k get pods -o wide                                       # NODE column = where pods landed
k get events --field-selector reason=FailedScheduling    # why pods are Pending
```

## 9. Autoscaling (HPA)

```bash
k autoscale deploy web --min=2 --max=5 --cpu=70%         # HPA on 70 % CPU utilization (kubectl v1.34+, exam v1.37)
k autoscale deploy web --min=2 --max=5 --cpu=500m --memory=200Mi   # AverageValue targets (v1.34+)
k autoscale deploy web --min=2 --max=5 --cpu-percent=70  # same on kubectl v1.33 and older (deprecated since v1.34)
k autoscale deploy web --max=5 --name=web-hpa            # custom HPA name
k get hpa                                                # TARGETS, MINPODS, MAXPODS, REPLICAS
k get hpa web -w                                         # watch scaling
k describe hpa web                                       # metrics, conditions, events
k top pods                                               # CPU/memory usage (needs metrics-server)
k top nodes                                              # node usage
k get apiservices v1beta1.metrics.k8s.io                 # is the metrics API available?
k set resources deploy web --requests=cpu=100m           # add the CPU request a Utilization HPA needs
k run load --rm -it --image=busybox:1.36 --restart=Never -- sh -c 'while true; do wget -q -O- http://web >/dev/null; done'   # generate load
k delete hpa web                                         # remove the autoscaler
```

## 10. Disruptions (PDB, drain, eviction)

```bash
k create pdb web-pdb --selector=app=web --min-available=2   # keep at least 2 pods
k create pdb web-pdb --selector=app=web --max-unavailable=1 # at most 1 pod down
k create pdb web-pdb --selector=app=web --min-available=50% # percentage (rounded up)
k patch pdb web-pdb --type=merge -p '{"spec":{"unhealthyPodEvictionPolicy":"AlwaysAllow"}}'   # let unhealthy pods be evicted
k get pdb                                                # MIN AVAILABLE, MAX UNAVAILABLE, ALLOWED DISRUPTIONS
k describe pdb web-pdb                                   # status and events
k drain node01 --ignore-daemonsets --delete-emptydir-data    # cordon + evict everything (respects PDBs)
k drain node01 --ignore-daemonsets --pod-selector=app=web --timeout=60s   # evict only matching pods
k drain node01 --ignore-daemonsets --dry-run=client     # show what would be evicted
k uncordon node01                                        # end maintenance
```

## 11. Verify and wait

```bash
k rollout status deploy/web --timeout=120s               # wait for a rollout
k wait --for=condition=Ready pod/web --timeout=60s       # wait for a condition
k wait --for=condition=Ready pods -l app=web --timeout=90s   # wait for all matching pods
k wait --for=jsonpath='{.status.phase}'=Running pod/web  # wait for a field value
k wait --for=delete pod/web --timeout=60s                # wait until gone
k wait --for=condition=complete job/hello --timeout=120s # wait for a Job
k get pod web -o jsonpath='{.spec.nodeName}{"\n"}'       # verify placement
k get pdb web-pdb -o jsonpath='{.status.disruptionsAllowed}{"\n"}'   # verify a budget
k auth can-i create deployments -n dev                   # am I allowed to?
```

## 12. Debug

```bash
k describe pod web                                       # events at the bottom: scheduling, pulling, probes
k get events -n dev --sort-by=.metadata.creationTimestamp   # recent events
k logs web -c app --tail=50                              # container logs
k exec -it web -- sh                                     # shell in a container
k run tmp --rm -it --image=busybox:1.36 --restart=Never -- wget -qO- --timeout=2 http://web-svc   # HTTP test
k run tmp --rm -it --image=busybox:1.36 --restart=Never -- nslookup web-svc.dev.svc.cluster.local   # DNS test
k run tmp --rm -it --image=curlimages/curl:8.10.1 --restart=Never -- curl -s -m 3 http://web-svc   # curl test
k cp dev/web:/etc/nginx/nginx.conf ./nginx.conf          # copy out of a pod (needs tar in the image)
k apply -f broken.yaml --dry-run=server                  # see validation errors without changing anything
k api-resources --verbs=list --namespaced -o name | xargs -n 1 kubectl get --show-kind --ignore-not-found -n dev   # really everything in a namespace
```

## 13. Cleanup

```bash
k delete ns selectors-lab                                # lab namespace from yaml/labels-selectors-demo.yaml
k delete -f yaml/hpa-cpu.yaml -f yaml/hpa-behavior.yaml  # HPA labs
k delete -f yaml/pdb-min-available.yaml -f yaml/pdb-max-unavailable.yaml   # PDB labs
k delete -f yaml/priorityclass.yaml                      # PriorityClasses + pod
k delete -f yaml/topology-spread-deployment.yaml -f yaml/pod-affinity-anti-affinity.yaml   # placement labs
k delete pod -l demo=tolerations ; k delete pod -l demo=node-affinity ; k delete pod ssd-pod linux-only   # pods
k taint nodes node01 dedicated- ; k label node node01 disktype- dedicated-   # undo node changes
k config set-context --current --namespace=default       # back to the default namespace
```
