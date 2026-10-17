# Application Deployment: command reference

Grouped by job. Every command has a one-line `#` comment. Replace `web`, `team-a`, chart and release names as needed. Add `-n <namespace>` whenever the task names a namespace.

## 1. Create and generate YAML (Deployments)

```bash
kubectl create deployment web --image=nginx:1.27                                   # 1 replica, container "nginx", Pod label app=web
kubectl create deployment web --image=nginx:1.27 --replicas=3 --port=80            # replicas + containerPort
kubectl create deployment web --image=nginx:1.27 -n team-a                         # in a namespace
kubectl create deployment multi --image=nginx:1.27 --image=redis:7.2               # two containers (nginx, redis)
kubectl create deployment sleeper --image=busybox:1.36 -- sh -c 'sleep 3600'       # with a command
kubectl create deployment web --image=nginx:1.27 --replicas=3 --dry-run=client -o yaml > web.yaml   # generate YAML to edit
kubectl apply -f web.yaml                                                          # create/update declaratively
kubectl create -f web.yaml --save-config                                           # create imperatively, allow later apply
kubectl expose deployment web --port=80 --target-port=80                           # ClusterIP Service "web" with the Deployment's selector
kubectl expose deployment web --port=80 --type=NodePort --name=web-np              # NodePort Service
kubectl explain deployment.spec.strategy --recursive                               # field docs offline
```

## 2. Scale

```bash
kubectl scale deployment web --replicas=5                                          # set replicas (no new revision)
kubectl scale deployment web --current-replicas=5 --replicas=3                     # only if it currently has 5
kubectl scale deployment web-stable web-canary --replicas=2                        # several at once
kubectl scale deployment -l app=web --replicas=0                                   # by label (stop without deleting)
kubectl patch deployment web -p '{"spec":{"replicas":4}}'                          # scale via patch
```

## 3. Change the Pod template (each starts a rollout)

```bash
kubectl set image deployment/web nginx=nginx:1.27-alpine                           # <container>=<image>
kubectl set image deployment/web '*=nginx:1.27-alpine'                             # every container
kubectl set env deployment/web LOG_LEVEL=debug                                     # add/overwrite an env var
kubectl set env deployment/web LOG_LEVEL-                                          # remove an env var
kubectl set env deployment/web --from=configmap/web-config                         # import all keys of a ConfigMap
kubectl set resources deployment/web -c nginx --requests=cpu=100m,memory=64Mi --limits=memory=128Mi   # requests/limits
kubectl set serviceaccount deployment/web app-sa                                   # change spec.template.spec.serviceAccountName
kubectl edit deployment web                                                        # interactive edit, rollout on save
kubectl patch deployment web -p '{"spec":{"template":{"spec":{"containers":[{"name":"nginx","image":"nginx:1.27"}]}}}}'   # strategic merge by container name
kubectl patch deployment web --type=json -p '[{"op":"replace","path":"/spec/template/spec/containers/0/image","value":"nginx:1.27"}]'   # JSON patch by index
kubectl replace -f web.yaml                                                        # replace the whole object
kubectl replace --force -f web.yaml                                                # delete + recreate (needed for selector changes)
kubectl rollout restart deployment/web                                             # new Pods, same spec (restartedAt annotation)
kubectl rollout restart deployment --selector=app=web                              # restart every matching Deployment
```

## 4. Rollout control

```bash
kubectl rollout status deployment/web                                              # wait until done; exit 1 if the deadline is exceeded
kubectl rollout status deployment/web --timeout=90s                                # bounded wait (exit 1 on timeout)
kubectl rollout status deployment/web --watch=false                                # one-shot status, don't wait
kubectl rollout status deployment/web --revision=3                                 # watch a specific revision
kubectl rollout history deployment/web                                             # REVISION + CHANGE-CAUSE list
kubectl rollout history deployment/web --revision=2                                # Pod template of revision 2
kubectl rollout undo deployment/web                                                # back to the previous revision
kubectl rollout undo deployment/web --to-revision=2                                # back to revision 2 (becomes a new revision)
kubectl rollout undo deployment/web --to-revision=2 --dry-run=client               # print the template that would be restored
kubectl rollout pause deployment/web                                               # stop rolling out template changes (Deployments only)
kubectl rollout resume deployment/web                                              # roll out everything changed while paused
kubectl rollout status daemonset/node-agent                                        # same subcommands for DaemonSets ...
kubectl rollout undo statefulset/db --to-revision=1                                # ... and StatefulSets (no pause/resume)
```

## 5. Change-cause (why a revision exists)

```bash
kubectl annotate deployment/web kubernetes.io/change-cause="upgrade to nginx:1.27-alpine" --overwrite   # AFTER the change
kubectl get rs -l app=web -o custom-columns='NAME:.metadata.name,REV:.metadata.annotations.deployment\.kubernetes\.io/revision,CAUSE:.metadata.annotations.kubernetes\.io/change-cause'   # per-RS revision + cause
kubectl get deploy web -o jsonpath='{.metadata.annotations.deployment\.kubernetes\.io/revision}{"\n"}'   # current revision number
```

## 6. Strategy and rollout tuning (no rollout by itself)

```bash
kubectl patch deployment web -p '{"spec":{"strategy":{"type":"RollingUpdate","rollingUpdate":{"maxSurge":1,"maxUnavailable":0}}}}'   # zero-downtime settings
kubectl patch deployment web -p '{"spec":{"strategy":{"rollingUpdate":{"maxSurge":"50%","maxUnavailable":"25%"}}}}'   # percentages as strings
kubectl patch deployment web -p '{"spec":{"strategy":{"type":"Recreate","rollingUpdate":null}}}'   # switch to Recreate (rollingUpdate must go)
kubectl patch deployment web -p '{"spec":{"minReadySeconds":10,"progressDeadlineSeconds":120,"revisionHistoryLimit":5}}'   # timing + history
kubectl get deploy web -o jsonpath='{.spec.strategy}{"\n"}'                        # verify the strategy
```

## 7. Inspect and verify

```bash
kubectl get deploy -o wide                                                         # READY UP-TO-DATE AVAILABLE + images + selector
kubectl get deploy web -o yaml                                                     # full spec + status + conditions
kubectl describe deploy web                                                        # conditions, strategy, events, old/new RS
kubectl get rs -l app=web -o wide                                                  # ReplicaSets (new vs old) with images
kubectl get pods -l app=web --show-labels                                          # pod-template-hash per Pod
kubectl get pods -l app=web -L track,version                                       # extra label columns
kubectl get deploy web -o jsonpath='{.spec.template.spec.containers[*].image}{"\n"}'   # current image(s)
kubectl get deploy web -o jsonpath='{.spec.template.spec.containers[*].name}{"\n"}'    # container names (for set image)
kubectl get deploy web -o jsonpath='{.status.conditions[?(@.type=="Progressing")].reason}{"\n"}'   # NewReplicaSetAvailable / ProgressDeadlineExceeded
kubectl get deploy web -o jsonpath='{.status.readyReplicas}/{.spec.replicas}{"\n"}'   # ready/desired
kubectl get pods -l app=web -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[0].image}{"\n"}{end}'   # image per Pod
kubectl get events --sort-by=.lastTimestamp | tail -20                             # recent events (FailedCreate, BackOff, ...)
kubectl wait --for=condition=Available deployment/web --timeout=120s               # block until Available=True
```

## 8. Blue/green

```bash
kubectl get svc shop -o jsonpath='{.spec.selector}{"\n"}'                          # which colour is live
kubectl rollout status deployment/shop-green                                       # green fully Ready before switching
kubectl patch service shop -p '{"spec":{"selector":{"app":"shop","version":"green"}}}'   # switch to green
kubectl set selector service shop 'app=shop,version=green'                         # alternative (replaces the whole selector)
kubectl get endpointslices -l kubernetes.io/service-name=shop -o wide              # endpoints = green Pod IPs?
kubectl patch service shop -p '{"spec":{"selector":{"app":"shop","version":"blue"}}}'    # roll back to blue
kubectl patch ingress shop --type=json -p '[{"op":"replace","path":"/spec/rules/0/http/paths/0/backend/service/name","value":"shop-green"}]'   # Ingress-level switch
kubectl scale deployment shop-blue --replicas=0                                    # retire blue (keep the object)
```

## 9. Canary

```bash
kubectl get deploy web-stable -o jsonpath='{.spec.selector.matchLabels}{"\n"}'     # stable's selector (immutable!)
kubectl get svc web -o jsonpath='{.spec.selector}{"\n"}'                           # must be the shared label only
kubectl create deployment web-canary --image=nginx:1.27-alpine --replicas=1 --dry-run=client -o yaml > canary.yaml   # then fix labels to app=web,track=canary
kubectl apply -f canary.yaml                                                       # create the canary
kubectl scale deployment web-stable --replicas=8 && kubectl scale deployment web-canary --replicas=2   # 80/20 with 10 Pods
kubectl get endpointslices -l kubernetes.io/service-name=web -o wide               # both tracks behind the Service
kubectl run tmp --rm -i --image=busybox:1.36 --restart=Never -- sh -c 'for i in $(seq 1 50); do wget -qO- http://web; done' | sort | uniq -c   # measure the split
kubectl set image deployment/web-stable web=nginx:1.27-alpine && kubectl rollout status deployment/web-stable   # promote
kubectl delete deployment web-canary                                               # finish promotion / remove canary
kubectl scale deployment web-canary --replicas=0                                   # instant canary rollback
```

## 10. Helm

```bash
# Repositories and search
helm repo add examples https://helm.github.io/examples                             # add a repo (local alias "examples")
helm repo update                                                                   # refresh all repo indexes
helm repo list                                                                     # configured repos
helm repo remove examples                                                          # remove a repo
helm search repo hello                                                             # search added repos
helm search repo examples/hello-world --versions                                   # all chart versions
helm search hub nginx                                                              # search Artifact Hub (internet)

# Inspect charts
helm show chart examples/hello-world                                               # Chart.yaml
helm show values examples/hello-world > values.yaml                                # default values to a file
helm show readme examples/hello-world                                              # README
helm show all ./webapp                                                             # everything, local chart

# Install
helm install web ./webapp -n team-a --create-namespace                             # local chart into a new namespace
helm install web examples/hello-world --version 0.1.0 -n team-a                    # pinned chart version
helm install web ./webapp -f values.yaml --set replicaCount=3                      # values file + override
helm install web ./webapp --set-string image.tag=1.20                              # force a string value
helm install ./webapp --generate-name                                              # auto-generated release name
helm install web ./webapp --dry-run=client --debug                                 # simulate + show computed values
helm install web ./webapp --wait --timeout 5m                                      # wait for resources to be ready
helm install web oci://registry.example.com/charts/webapp --version 0.1.0          # from an OCI registry

# Upgrade
helm upgrade web ./webapp --reuse-values --set replicaCount=4                      # keep previous values, change one
helm upgrade web ./webapp -f values.yaml                                           # user values = this file (old --set dropped)
helm upgrade web ./webapp --reset-values                                           # back to chart defaults
helm upgrade web ./webapp --reset-then-reuse-values                                # new chart defaults + previous user values
helm upgrade --install web ./webapp -n team-a --create-namespace                   # install if missing, else upgrade
helm upgrade web examples/hello-world --version 0.1.0 --reuse-values               # avoid an accidental chart upgrade
helm upgrade web ./webapp --history-max 5                                          # keep at most 5 revisions

# Rollback and uninstall
helm history web -n team-a                                                         # revisions with STATUS + DESCRIPTION
helm rollback web 2 -n team-a                                                      # revision 2's config as a NEW revision
helm rollback web -n team-a                                                        # to the previous revision
helm uninstall web -n team-a                                                       # delete objects + history
helm uninstall web -n team-a --keep-history                                        # keep history (status uninstalled)

# List, status, get
helm list                                                                          # releases in the current namespace
helm list -A                                                                       # all namespaces (NAME NAMESPACE REVISION UPDATED STATUS CHART APP VERSION)
helm list -a                                                                       # Helm 3: all statuses (Helm 4 lists them by default, has no -a)
helm list -A --failed                                                              # failed releases
helm list -A --pending                                                             # pending-install/upgrade/rollback
helm list -A --deployed                                                            # deployed releases
helm list -A --superseded                                                          # superseded releases
helm list -A --uninstalled                                                         # uninstalled with --keep-history
helm list -A -o yaml                                                               # machine-readable (chart, app_version, ...)
helm list -A -f 'web'                                                              # filter names by regex
helm status web -n team-a                                                          # status + notes of the current revision
helm get values web -n team-a                                                      # user-supplied values
helm get values web -n team-a --all                                                # all computed values
helm get values web -n team-a --revision 1                                         # values of an old revision
helm get manifest web -n team-a                                                    # rendered manifests applied
helm get notes web -n team-a                                                       # NOTES.txt output
helm get metadata web -n team-a                                                    # chart, version, app version, revision

# Render, download, author
helm template web ./webapp -f values.yaml > out.yaml                               # render locally (no cluster)
helm template web ./webapp --show-only templates/deployment.yaml                   # render one template
helm pull examples/hello-world --version 0.1.0                                     # download the .tgz
helm pull examples/hello-world --version 0.1.0 --untar --untardir /tmp/charts      # download + unpack
helm create webapp                                                                 # scaffold a chart
helm lint ./webapp                                                                 # check a chart
helm package ./webapp                                                              # build webapp-<version>.tgz
helm dependency update ./webapp                                                    # fetch dependencies into charts/
helm version                                                                       # Helm 3 or 4? (check before using rare flags)

# Release storage
kubectl get secrets -n team-a -l owner=helm                                        # one Secret per revision
kubectl get secrets -n team-a -l owner=helm,name=web,status=deployed               # the live revision's record
kubectl delete secret sh.helm.release.v1.web.v4 -n team-a                          # last resort: drop a stuck revision record
```

## 11. Kustomize

```bash
kubectl kustomize overlays/prod                                                    # render to stdout
kubectl kustomize overlays/prod > /tmp/prod.yaml                                   # render to a file
kubectl apply -k overlays/prod                                                     # build + apply
kubectl apply -k overlays/prod --dry-run=server                                    # server-side validation only
kubectl diff -k overlays/prod                                                      # diff against the cluster
kubectl get -k overlays/prod                                                       # objects managed by this kustomization
kubectl delete -k overlays/prod                                                    # delete them
kubectl version --client                                                           # shows the embedded Kustomize version
kustomize build overlays/prod                                                      # standalone equivalent of kubectl kustomize
kustomize create --resources ../../base --namespace prod --nameprefix prod-        # new overlay kustomization
kustomize edit set image nginx=nginx:1.27-alpine                                   # images: entry
kustomize edit set namespace prod                                                  # namespace field
kustomize edit set nameprefix prod-                                                # namePrefix field
kustomize edit set namesuffix -- -v2                                               # nameSuffix field
kustomize edit set replicas web=4                                                  # replicas: entry
kustomize edit add resource deployment.yaml                                        # resources: entry
kustomize edit add configmap web-config --from-literal=LOG_LEVEL=warn              # configMapGenerator entry
kustomize edit add patch --path patch.yaml --kind Deployment --name web            # patches: entry with target
kustomize edit add label env:prod --without-selector                               # labels: entry (no selectors)
kustomize edit fix                                                                 # migrate deprecated fields
```

## 12. Debug a failed rollout

```bash
kubectl rollout status deployment/web --timeout=60s; echo "exit=$?"                # non-zero = failed / not finished
kubectl describe deployment web | sed -n '/Conditions/,/Events/p'                  # Progressing / Available / ReplicaFailure
kubectl get rs -l app=web                                                          # new RS stuck with DESIRED > READY?
kubectl get pods -l app=web                                                        # ImagePullBackOff / CrashLoopBackOff / Pending
kubectl describe pod <pod>                                                         # image pull errors, probe failures, scheduling
kubectl logs deploy/web --all-containers --tail=50                                 # app errors (picks one Pod)
kubectl get events --field-selector reason=FailedCreate                            # quota/admission failures
kubectl rollout undo deployment/web                                                # restore the last good template
```

## 13. Cleanup

```bash
kubectl delete deployment web                                                      # deletes RS + Pods too
kubectl delete deployment web --cascade=orphan                                     # keep the Pods/RS running
kubectl delete deployment,service -l app=shop                                      # by label
helm uninstall web -n team-a                                                       # remove a Helm release
kubectl delete -k overlays/dev                                                     # remove a kustomization's objects
kubectl delete namespace team-a                                                    # everything in the namespace (incl. Helm records)
```
