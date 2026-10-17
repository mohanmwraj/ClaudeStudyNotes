# Commands: Application Design and Build

The complete command reference for this chapter, grouped by task. Each command has a one-line comment. Shell setup (aliases such as `k`, `export do="--dry-run=client -o yaml"`, vim settings) is in [../00-Exam-Overview-and-Setup/README.md](../00-Exam-Overview-and-Setup/README.md). The general kubectl and jsonpath tricks are in [../06-Cross-Cutting-Skills-and-Bonus-Topics/README.md](../06-Cross-Cutting-Skills-and-Bonus-Topics/README.md).

---

## 0. Before every task

```bash
kubectl config use-context <context-from-task>             # ALWAYS switch to the context the task names
kubectl config set-context --current --namespace=<ns>      # optional: make the task namespace the default
which podman docker                                        # which container tools exist on this host
```

---

## 1. Container images

### Build and tag

```bash
podman build -t app:v1 .                                   # build ./Containerfile|Dockerfile, context "."
podman build -t app:v1 -f path/Dockerfile .                # other Dockerfile; context stays "."
podman build -t app:v1 -t app:latest .                     # two tags in one build
podman build -t registry.local:5000/team/app:v1 .          # registry-qualified name directly
podman build --build-arg VERSION=1.2 -t app:1.2 .          # pass a build ARG
podman build --target build -f Dockerfile.multistage -t app:builder .   # build up to a named stage
podman build --no-cache --pull=always -t app:v1 .          # full rebuild + refresh base image
podman build --format docker -t app:v1 .                   # Docker format (keeps HEALTHCHECK/SHELL/ONBUILD)
podman tag app:v1 registry.local:5000/team/app:v1          # add another name to an existing image
podman untag app:latest                                    # remove one name (the image stays if others remain)
docker build -t app:v1 .                                   # docker equivalent
docker build -t app:v1 -f Dockerfile.multistage --build-arg VERSION=1.2 --target build .   # docker with options
docker tag app:v1 registry.local:5000/team/app:v1          # docker retag
```

### Inspect

```bash
podman images                                              # local images (podman shows localhost/app for local builds)
podman images --digests                                    # with digests
podman images --format '{{.Repository}}:{{.Tag}} {{.Size}}'   # compact list
podman image inspect app:v1                                # full JSON (Config.Env, Cmd, Entrypoint, User, Labels)
podman image inspect app:v1 --format '{{.Config.Entrypoint}} {{.Config.Cmd}}'   # what runs by default
podman image inspect app:v1 --format '{{.Config.User}} {{.Config.Env}} {{.Config.ExposedPorts}}'   # user, env, ports
podman history app:v1                                      # layers and the instruction behind each
podman history --no-trunc app:v1                           # full instruction text
docker images ; docker image inspect app:v1 --format '{{json .Config}}' ; docker history app:v1   # docker equivalents
```

### Registry: push and pull

```bash
podman login registry.local:5000                           # store credentials
podman push registry.local:5000/team/app:v1                # push (TLS registry)
podman push registry.local:5000/team/app:v1 --tls-verify=false   # push to a plain-HTTP registry
podman pull docker.io/library/nginx:1.27                   # fully-qualified pull (no short-name prompt)
docker push registry.local:5000/team/app:v1                # docker push
docker push --all-tags registry.local:5000/team/app        # push every local tag of the repository
curl -s http://registry.local:5000/v2/_catalog             # list repositories in a registry
curl -s http://registry.local:5000/v2/team/app/tags/list   # list tags of a repository
podman run -d --name registry -p 5000:5000 docker.io/library/registry:2   # practice registry on localhost:5000
```

### Save, load, archive formats

```bash
podman save -o /opt/course/1/app.tar app:v1                # docker-archive (podman default)
podman save --format oci-archive -o /opt/course/1/app-oci.tar app:v1   # OCI archive
podman save --format oci-dir -o /opt/course/1/app-oci-dir app:v1       # OCI layout as a directory
podman save -m -o images.tar app:v1 app:v2                 # several images in one docker-archive
podman load -i /opt/course/1/app.tar                       # import an archive (any supported format)
docker save -o /opt/course/1/app.tar app:v1                # docker save (Engine 25+: OCI-compliant tar)
docker save app:v1 | gzip > app.tar.gz                     # compressed
docker load -i app.tar                                     # import into docker
tar -tf /opt/course/1/app-oci.tar | head                   # verify: oci-layout + index.json = OCI
ls -lh /opt/course/1/                                      # verify the file exists where the task wants it
```

### Run and test locally

```bash
podman run -d --name web -p 8080:8080 app:v1               # detached, publish host:container port
podman run -d --name web --user 1000 app:v1                # run as a non-root UID
podman run -d --name web -e APP_ENV=prod app:v1            # set env
podman run --rm app:v1 --help                              # trailing words replace CMD
podman run --rm --entrypoint id app:v1 -u                  # replace ENTRYPOINT (prints the UID)
podman run --rm -it --entrypoint sh app:v1                 # explore the image interactively
podman ps                                                  # running containers
podman ps -a                                               # all containers incl. exited
podman ps > /opt/course/2/containers                       # save the list as asked
podman logs web                                            # container output
podman logs web > /opt/course/2/logs 2>&1                  # save stdout AND stderr
podman exec -it web sh                                     # shell inside
podman inspect web --format '{{.State.Status}} {{.Config.User}}'   # container state and user
podman stop web && podman rm web                           # stop and remove
podman rm -f web                                           # force remove a running container
podman rmi app:v1                                          # remove the image
docker run -d --name web -p 8080:8080 app:v1 ; docker logs web ; docker ps   # docker equivalents
```

### Make the image available to a lab cluster

```bash
kind load docker-image app:v1 --name <cluster>             # docker image into kind nodes
kind load image-archive app.tar --name <cluster>           # saved archive into kind (podman workflow)
minikube image load app:v1                                 # minikube
sudo ctr -n k8s.io images import app.tar                   # containerd node
sudo crictl images | grep app                              # what the kubelet runtime sees
```

---

## 2. Pods

### Create / generate

```bash
kubectl run web --image=nginx:1.27                         # pod with label run=web
kubectl run web --image=nginx:1.27 --port=80 --labels=app=web,tier=fe --env=MODE=prod   # port, labels, env
kubectl run web --image=nginx:1.27 --port=80 --expose      # pod + ClusterIP service "web"
kubectl run bb --image=busybox:1.36 -- sleep 3600          # args (CMD replaced)
kubectl run bb --image=busybox:1.36 --command -- sh -c 'echo hi; sleep 3600'   # command (ENTRYPOINT replaced)
kubectl run once --image=busybox:1.36 --restart=Never -- date   # one-shot pod
kubectl run tmp --rm -it --image=busybox:1.36 --restart=Never -- sh   # throwaway interactive shell
kubectl run tmp --rm -i --image=curlimages/curl:8.10.1 --restart=Never -- curl -s -m 5 http://web   # one test request
kubectl run web --image=nginx:1.27 --image-pull-policy=IfNotPresent --annotations=owner=team-a   # pull policy, annotations
kubectl run web --image=nginx:1.27 --overrides='{"apiVersion":"v1","spec":{"serviceAccountName":"sa1"}}'   # fields without flags
kubectl run web --image=nginx:1.27 --port=80 --dry-run=client -o yaml > web.yaml   # YAML only
kubectl apply -f web.yaml                                  # create/update from file
```

### Inspect

```bash
kubectl get pods -o wide --show-labels                     # node, IP, labels
kubectl get pod web -o yaml                                # full spec + status
kubectl describe pod web                                   # events, states, exit codes
kubectl get pod web -o jsonpath='{.status.phase}{"\n"}'    # phase
kubectl get pod web -o jsonpath='{.spec.containers[*].name}{"\n"}'   # container names
kubectl get pod web -o jsonpath='{.status.containerStatuses[0].restartCount}{"\n"}'   # restarts
kubectl get pod web -o jsonpath='{.status.containerStatuses[0].lastState.terminated.reason}{"\n"}'   # e.g. OOMKilled
kubectl get pod web -o jsonpath='{.spec.containers[0].command}{" "}{.spec.containers[0].args}{"\n"}'   # command/args
kubectl explain pod.spec.containers.lifecycle --recursive  # field reference offline
kubectl get events --sort-by=.lastTimestamp                # recent events
```

### Modify

```bash
kubectl set image pod/web web=nginx:1.27-alpine            # image is mutable (container restarts)
kubectl label pod web env=prod                             # add label
kubectl label pod web env=stage --overwrite                # change label
kubectl label pod web env-                                 # remove label
kubectl annotate pod web description="frontend"            # add annotation
kubectl edit pod web                                       # immutable change -> copy saved in /tmp/kubectl-edit-*.yaml
kubectl replace --force -f /tmp/kubectl-edit-1234.yaml     # delete + recreate with the saved change
kubectl get pod web -o yaml > web.yaml && vi web.yaml && kubectl replace --force -f web.yaml   # same, explicit
kubectl patch pod web --subresource resize -p '{"spec":{"containers":[{"name":"web","resources":{"limits":{"cpu":"500m"}}}]}}'   # in-place resize (v1.33+)
```

### Logs / exec / delete

```bash
kubectl logs web                                           # logs (single container)
kubectl logs web -c sidecar                                # one container of a multi-container pod
kubectl logs web --previous                                # crashed previous instance
kubectl logs web --all-containers --prefix                 # every container, prefixed lines
kubectl exec -it web -- sh                                 # shell
kubectl exec web -c app -- cat /data/out.txt               # one command in one container
kubectl delete pod web                                     # graceful delete
kubectl delete pod web --grace-period=0 --force            # immediate API removal
kubectl delete pods -l app=web                             # delete by label
```

### Static pods (on the node)

```bash
grep staticPodPath /var/lib/kubelet/config.yaml            # where the kubelet reads manifests
sudo cp static-pod.yaml /etc/kubernetes/manifests/          # create (kubeadm default path)
sudo mv /etc/kubernetes/manifests/static-web.yaml /tmp/     # stop/delete it
kubectl get pods -A | grep <node-name>                     # mirror pods are suffixed with the node name
```

---

## 3. Deployments, ReplicaSets, ReplicationControllers

```bash
kubectl create deployment web --image=nginx:1.27 --replicas=3 --port=80 --dry-run=client -o yaml > deploy.yaml   # generate
kubectl create deployment web --image=busybox:1.36 --image=nginx:1.27 --dry-run=client -o yaml   # two containers
kubectl scale deployment web --replicas=5                  # scale (also rs, rc, sts)
kubectl set image deployment/web nginx=nginx:1.27-alpine   # update image (rollout)
kubectl rollout status deployment/web                      # wait for the rollout
kubectl rollout history deployment/web                     # revisions
kubectl rollout undo deployment/web --to-revision=1        # roll back
kubectl rollout restart deployment/web                     # restart all pods
kubectl get deploy,rs,pods -l app=web                      # the ownership chain
kubectl get rs                                             # ReplicaSets (one per template revision)
kubectl scale rs frontend-rs --replicas=2                  # scale a bare ReplicaSet
kubectl get rc                                             # legacy ReplicationControllers
kubectl get pod <pod> -o jsonpath='{.metadata.ownerReferences[0].kind}{"/"}{.metadata.ownerReferences[0].name}{"\n"}'   # owner
kubectl delete deployment web --cascade=orphan             # delete controller, keep pods
```

---

## 4. Jobs

```bash
kubectl create job pi --image=busybox:1.36 -- sh -c 'echo hi'   # create directly (restartPolicy Never)
kubectl create job pi --image=busybox:1.36 --dry-run=client -o yaml -- sh -c 'echo hi' > job.yaml   # generate, then add fields
kubectl apply -f job.yaml                                  # create with completions/parallelism/... added
kubectl get jobs -w                                        # COMPLETIONS / DURATION live
kubectl get pods -l job-name=pi                            # the Job's pods
kubectl get pods -l job-name=pi -L batch.kubernetes.io/job-completion-index   # indexes of an Indexed Job
kubectl wait --for=condition=complete job/pi --timeout=120s   # block until complete
kubectl wait --for=condition=failed job/pi --timeout=120s  # block until failed
kubectl logs job/pi                                        # logs of one pod of the Job
kubectl logs -l job-name=pi --prefix --tail=-1             # all pods, all lines
kubectl describe job pi                                    # pod statuses + events (BackoffLimitExceeded, DeadlineExceeded)
kubectl get job pi -o jsonpath='{.status.succeeded}{"/"}{.spec.completions}{"\n"}'   # progress
kubectl get job pi -o jsonpath='{.status.conditions[*].type}{" "}{.status.conditions[*].reason}{"\n"}'   # outcome + reason
kubectl patch job pi -p '{"spec":{"suspend":true}}'        # suspend (deletes active pods)
kubectl patch job pi -p '{"spec":{"suspend":false}}'       # resume
kubectl replace --force -f job.yaml                        # change the (immutable) pod template
kubectl delete job pi                                      # delete Job + pods
kubectl delete jobs --field-selector status.successful=1   # delete finished-successful Jobs
```

---

## 5. CronJobs

```bash
kubectl create cronjob tick --image=busybox:1.36 --schedule="*/5 * * * *" -- date   # create directly
kubectl create cronjob tick --image=busybox:1.36 --schedule="*/5 * * * *" --restart=Never --dry-run=client -o yaml -- sh -c 'date' > cj.yaml   # generate
kubectl get cronjob tick                                   # SCHEDULE, TIMEZONE, SUSPEND, ACTIVE, LAST SCHEDULE
kubectl create job tick-manual-1 --from=cronjob/tick       # run now from the jobTemplate
kubectl get jobs --watch                                   # watch scheduled and manual Jobs appear
kubectl logs job/tick-manual-1                             # output of the manual run
kubectl get cronjob tick -o jsonpath='{.status.lastScheduleTime}{" "}{.status.lastSuccessfulTime}{"\n"}'   # last runs
kubectl patch cronjob tick -p '{"spec":{"suspend":true}}'  # suspend
kubectl patch cronjob tick -p '{"spec":{"suspend":false}}' # resume
kubectl patch cronjob tick -p '{"spec":{"schedule":"0 * * * *"}}'   # change schedule (applies to future Jobs)
kubectl delete cronjob tick                                # delete CronJob + its Jobs + pods
```

---

## 6. DaemonSets

```bash
kubectl create deployment agent --image=busybox:1.36 --dry-run=client -o yaml -- sleep 3600 > ds.yaml   # start from a Deployment
sed -i -e 's/^kind: Deployment/kind: DaemonSet/' -e '/^  replicas:/d' -e '/^  strategy: {}/d' ds.yaml     # convert (check the result!)
kubectl apply -f ds.yaml                                   # create
kubectl get ds                                             # DESIRED/CURRENT/READY/UP-TO-DATE/AVAILABLE
kubectl get pods -l app=agent -o wide                      # one pod per node?
kubectl describe node <node> | grep -i taints              # taints the toleration must match
kubectl set image ds/agent busybox=busybox:1.37            # rolling update
kubectl rollout status ds/agent                            # wait
kubectl rollout history ds/agent                           # revisions
kubectl rollout undo ds/agent                              # roll back
kubectl get ds agent -o jsonpath='{.status.desiredNumberScheduled} {.status.numberReady}{"\n"}'   # counts
```

---

## 7. StatefulSets

```bash
kubectl create service clusterip web --clusterip="None" --tcp=80:80 --dry-run=client -o yaml > svc.yaml   # headless Service
kubectl create deployment web --image=nginx:1.27 --replicas=3 --dry-run=client -o yaml > sts.yaml   # then: kind, -strategy, +serviceName, +volumeClaimTemplates
kubectl apply -f svc.yaml -f sts.yaml                      # create both
kubectl get sts web                                        # READY x/N
kubectl get pods -l app=web -w                             # ordered creation web-0, web-1, ...
kubectl get pvc                                            # <claim>-web-0, <claim>-web-1, ...
kubectl scale sts web --replicas=5                         # ordered scale-up
kubectl run dns --rm -i --image=busybox:1.36 --restart=Never -- nslookup web-0.web.default.svc.cluster.local   # per-pod DNS
kubectl patch sts web -p '{"spec":{"updateStrategy":{"type":"RollingUpdate","rollingUpdate":{"partition":2}}}}'   # canary: only ordinals >= 2
kubectl set image sts/web nginx=nginx:1.27-alpine          # rolling update (respects partition)
kubectl rollout status sts/web                             # wait
kubectl get pods -l app=web -o custom-columns=NAME:.metadata.name,IMAGE:.spec.containers[0].image   # who runs what
kubectl delete sts web --cascade=orphan                    # delete controller, keep pods (to change immutable fields)
kubectl delete pvc -l app=web                              # PVCs are NOT deleted with the StatefulSet
```

---

## 8. Multi-container pods

```bash
kubectl get pod app -o jsonpath='{.spec.initContainers[*].name}{" | "}{.spec.containers[*].name}{"\n"}'   # all container names
kubectl logs app -c init-db                                # init container logs
kubectl logs app -c init-db --previous                     # previous failed init attempt
kubectl logs app -c log-shipper -f                         # follow a sidecar
kubectl logs deploy/web -c sidecar                         # sidecar of a Deployment's pod
kubectl exec -it app -c app -- sh                          # shell in a chosen container
kubectl describe pod app | grep -A20 "Init Containers"     # init/sidecar states
kubectl get pod app -o jsonpath='{range .status.initContainerStatuses[*]}{.name}{" ready="}{.ready}{" restarts="}{.restartCount}{"\n"}{end}'   # init statuses
kubectl debug -it app --image=busybox:1.36 --target=app    # ephemeral debug container in app's PID namespace
```

---

## 9. Volumes (ephemeral)

```bash
kubectl explain pod.spec.volumes.emptyDir                  # medium, sizeLimit
kubectl explain pod.spec.volumes.hostPath                  # path, type
kubectl explain pod.spec.volumes.projected.sources         # configMap/secret/downwardAPI/serviceAccountToken
kubectl explain pod.spec.volumes.ephemeral.volumeClaimTemplate.spec   # generic ephemeral PVC spec
kubectl explain pod.spec.containers.volumeMounts           # subPath, subPathExpr, readOnly, recursiveReadOnly
kubectl exec app -- df -h /cache                           # tmpfs = memory-backed
kubectl exec app -- sh -c 'mount | grep /data'             # mount type, ro/rw
kubectl exec app -c reader -- ls -la /input                # what the other container wrote
kubectl get pod app -o jsonpath='{.spec.nodeName}{"\n"}'   # node that holds hostPath data
kubectl get pvc                                            # generic ephemeral PVCs: <pod>-<volume>
```

---

## 10. PersistentVolumes, PVCs, StorageClasses

```bash
kubectl get pv                                             # capacity, modes, reclaim, status, claim, class
kubectl get pvc -A                                         # claims everywhere
kubectl get sc                                             # classes; "(default)" marks the default
kubectl describe pvc data                                  # events: why Pending
kubectl describe pv pv-data                                # source, claimRef, node affinity
kubectl get pv pv-data -o jsonpath='{.status.phase} {.spec.claimRef.namespace}/{.spec.claimRef.name}{"\n"}'   # binding
kubectl get pvc data -o jsonpath='{.status.phase} {.spec.volumeName} {.status.capacity.storage}{"\n"}'   # bound PV + size
kubectl patch sc standard -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}'   # un-default
kubectl patch sc fast -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'       # make default
kubectl patch pv pv-data -p '{"spec":{"persistentVolumeReclaimPolicy":"Retain"}}'   # change reclaim policy
kubectl patch pvc data -p '{"spec":{"resources":{"requests":{"storage":"2Gi"}}}}'  # expand (class must allow)
kubectl patch pv pv-data -p '{"spec":{"claimRef":null}}'   # Released -> Available (after cleanup)
kubectl exec pvc-pod -- sh -c 'echo test > /data/t.txt' && kubectl delete pod pvc-pod   # persistence test, step 1
kubectl apply -f pvc-pod.yaml && kubectl exec pvc-pod -- cat /data/t.txt              # persistence test, step 2
kubectl delete pvc data                                    # Terminating until no pod uses it
kubectl delete pv pv-data                                  # remove the PV object
```

---

## 11. Verify and debug (any object)

```bash
kubectl get <kind> <name> -o yaml | grep -A5 <field>       # quick field check
kubectl get events --field-selector involvedObject.name=<name> --sort-by=.lastTimestamp   # events for one object
kubectl get all -n <ns>                                    # overview (no PVC/CM/Secret/Ingress)
kubectl api-resources --namespaced=false                   # cluster-scoped kinds (PV, SC, Node, ...)
kubectl auth can-i create persistentvolumes                # cluster-scoped objects may need extra rights
```

---

## 12. Cleanup

```bash
kubectl delete -f yaml/                                    # everything created from the folder
kubectl delete pod,deploy,rs,ds,sts,job,cronjob -l app=<x> # by label across kinds
kubectl delete pvc --all -n <ns>                           # PVCs left behind by StatefulSets
kubectl delete pv <pv>                                     # PVs are cluster-scoped
kubectl delete ns <ns>                                     # everything in the namespace
podman rm -f $(podman ps -aq) ; podman rmi -f app:v1       # local container cleanup
```
