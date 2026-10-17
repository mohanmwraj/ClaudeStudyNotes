# Practice Questions - Cross-Cutting Skills and Bonus Topics

> These are exam-style tasks modelled on the official CNCF curriculum and on task patterns that candidates describe publicly. Real exam questions are confidential under the Linux Foundation candidate agreement; nothing here is a leaked question.

How to use this page:

- Every real task starts by naming a host (`ssh <host>`) and/or a context - build the habit: start each task below with `k config get-contexts` / your switch command, and on a new host re-export `$do`/`$now`.
- Each task has a **Setup** block for your practice cluster (kind/minikube - see [00](../00-Exam-Overview-and-Setup/README.md)). Some tasks reuse namespaces from earlier ones.
- Output paths follow the exam style `/opt/course/<n>/...`. On a practice machine create the base directory once: `sudo mkdir -p /opt/course && sudo chown -R "$USER" /opt/course`.
- Assumes `alias k=kubectl` and `export do="--dry-run=client -o yaml"`; versions refer to v1.37 (the exam version).

---

### Q1. Pod names and nodes into a file
**Frequency:** 🔥 High · **Est. time:** 3 min · **Competency:** Output formatting - JSONPath

**Setup:**

```bash
k create ns orbit
k create deploy orbit-web -n orbit --image=nginx:1.27 --replicas=3
k run orbit-cli -n orbit --image=busybox:1.36 -- sleep 3600
```

Write every pod of namespace `orbit` as `<pod-name>:<node-name>` - one pod per line, sorted by pod name, no header - into `/opt/course/1/pods-nodes.txt`.

<details><summary>Solution</summary>

```bash
mkdir -p /opt/course/1
k get pods -n orbit -o jsonpath='{range .items[*]}{.metadata.name}{":"}{.spec.nodeName}{"\n"}{end}' | sort > /opt/course/1/pods-nodes.txt
```

Alternative with custom-columns: `k get pods -n orbit --no-headers -o custom-columns=N:.metadata.name,NODE:.spec.nodeName | awk '{print $1":"$2}' | sort`.

**Verify:** `cat /opt/course/1/pods-nodes.txt` shows 4 lines such as `orbit-cli:node01`; `wc -l /opt/course/1/pods-nodes.txt` → 4.
</details>

### Q2. Decode a Secret
**Frequency:** 🔥 High · **Est. time:** 3 min · **Competency:** Output formatting - Secrets

**Setup:**

```bash
k create ns vault
k create secret generic db-credentials -n vault --from-literal=username=admin --from-literal=password='Pa55w0rd!'
```

Write the decoded value of key `password` of Secret `db-credentials` (namespace `vault`) into `/opt/course/2/password.txt`. Write all keys of that Secret as `key=decodedValue` lines into `/opt/course/2/all.txt`.

<details><summary>Solution</summary>

```bash
mkdir -p /opt/course/2
k get secret db-credentials -n vault -o jsonpath='{.data.password}' | base64 -d > /opt/course/2/password.txt
k get secret db-credentials -n vault -o go-template='{{range $k, $v := .data}}{{$k}}={{$v | base64decode}}{{"\n"}}{{end}}' > /opt/course/2/all.txt
```

yq alternative for the second file: `k get secret db-credentials -n vault -o yaml | yq '.data | map_values(@base64d) | to_entries | .[] | .key + "=" + .value'`.

**Verify:** `cat /opt/course/2/password.txt; echo` → `Pa55w0rd!`; `cat /opt/course/2/all.txt` → `password=Pa55w0rd!` and `username=admin`.
</details>

### Q3. Labels and set-based selectors
**Frequency:** 🔥 High · **Est. time:** 6 min · **Competency:** Labels & selectors

**Setup:**

```bash
k create ns shop
k run front-1 -n shop --image=nginx:1.27 --labels=app=frontend,env=prod
k run front-2 -n shop --image=nginx:1.27 --labels=app=frontend,env=dev
k run back-1  -n shop --image=nginx:1.27 --labels=app=backend,env=prod
k run back-2  -n shop --image=nginx:1.27 --labels=app=backend
k run batch-1 -n shop --image=busybox:1.36 --labels=app=batch,env=qa -- sleep 3600
```

In namespace `shop`:
1. Add the label `tier=web` to every pod with `app=frontend`.
2. Change the `env` label of `front-2` to `qa`.
3. Remove the `env` label from `back-1`.
4. Write the names of all pods that **have** an `env` label whose value is **not** `prod` into `/opt/course/3/non-prod.txt` (one per line).
5. Write the names of all pods **without** an `env` label into `/opt/course/3/no-env.txt`.

<details><summary>Solution</summary>

```bash
k label pods -n shop -l app=frontend tier=web
k label pod front-2 -n shop env=qa --overwrite
k label pod back-1 -n shop env-
mkdir -p /opt/course/3
k get pods -n shop -l 'env,env!=prod' -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' > /opt/course/3/non-prod.txt
k get pods -n shop -l '!env' -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' > /opt/course/3/no-env.txt
```

`env!=prod` alone would also return pods without `env` - hence `env,env!=prod`.

**Verify:** `k get pods -n shop -L app,env,tier`; `non-prod.txt` = `batch-1`, `front-2`; `no-env.txt` = `back-1`, `back-2`.
</details>

### Q4. Namespace and default namespace of the context
**Frequency:** 🔥 High · **Est. time:** 3 min · **Competency:** Namespaces & contexts

Create namespace `team-red` with the labels `team=red` and `env=staging`. Make `team-red` the default namespace of your current context. Without using `-n`, create pod `probe` (image `busybox:1.36`, command `sleep 3600`). Write the namespace your current context now uses into `/opt/course/4/ns.txt`.

<details><summary>Solution</summary>

```bash
k create ns team-red
k label ns team-red team=red env=staging
k config set-context --current --namespace=team-red
k run probe --image=busybox:1.36 -- sleep 3600
mkdir -p /opt/course/4
k config view --minify -o jsonpath='{..namespace}' > /opt/course/4/ns.txt
```

Afterwards switch back for the next tasks: `k config set-context --current --namespace=default`.

**Verify:** `k get ns team-red --show-labels`; `k get pod probe -n team-red`; `cat /opt/course/4/ns.txt` → `team-red`.
</details>

### Q5. Change an immutable Pod field
**Frequency:** 🔥 High · **Est. time:** 5 min · **Competency:** kubectl power usage - edit / replace --force

**Setup:**

```bash
k create ns ops
k run legacy-app -n ops --image=busybox:1.36 --labels=app=legacy -- sleep 3600
```

Pod `legacy-app` in namespace `ops` must get the environment variable `MODE=maintenance` and the additional label `fixed=true`. It must keep its name and its existing label. Store the final manifest as `/opt/course/5/legacy-app.yaml`.

<details><summary>Solution</summary>

```bash
mkdir -p /opt/course/5
k get pod legacy-app -n ops -o yaml > /opt/course/5/legacy-app.yaml
vim /opt/course/5/legacy-app.yaml        # add env + label (see below)
k replace --force -f /opt/course/5/legacy-app.yaml
```

Relevant parts of the edited manifest (status/uid fields from the export may stay):

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: legacy-app
  namespace: ops
  labels:
    app: legacy
    fixed: "true"
spec:
  containers:
  - name: legacy-app
    image: busybox:1.36
    args: ["sleep", "3600"]
    env:
    - name: MODE
      value: maintenance
```

Alternative: `k edit pod legacy-app -n ops` → the change is rejected → quit the editor → `k replace --force -f /tmp/kubectl-edit-XXXX.yaml`, then copy that file to `/opt/course/5/legacy-app.yaml`.

**Verify:** `k get pod legacy-app -n ops --show-labels`; `k exec -n ops legacy-app -- env | grep MODE` → `MODE=maintenance`.
</details>

### Q6. Fix a broken manifest
**Frequency:** 🔥 High · **Est. time:** 5 min · **Competency:** YAML

**Setup** (creates the broken file exactly as the task hands it to you):

```bash
k create ns fixit
mkdir -p /opt/course/6
cat > /opt/course/6/broken.yaml <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: broken-app
  namespace: fixit
  labels:
    app: broken-app
    version: 1.10
spec:
  containers:
  - name: app
    image: busybox:1.36
    command: ["sh", "-c", "echo $GREETING; sleep 3600"]
    env:
    - name: GREETING
      value: hello
    - name: RETRIES
      value: 3
     resources:
      requests:
        memory: 64Mi
EOF
```

`kubectl apply -f /opt/course/6/broken.yaml` fails. Fix every problem without changing names, image or the meaning of any value (the label must read `1.10`), save the result as `/opt/course/6/fixed.yaml` and create the Pod. It must be Running.

<details><summary>Solution</summary>

Three problems: (1) `resources:` is indented by 5 spaces (YAML error `did not find expected key`); (2) `version: 1.10` is a float (would even become `1.1`) - label values must be strings; (3) `value: 3` is a number - env values must be strings.

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: broken-app
  namespace: fixit
  labels:
    app: broken-app
    version: "1.10"
spec:
  containers:
  - name: app
    image: busybox:1.36
    command: ["sh", "-c", "echo $GREETING; sleep 3600"]
    env:
    - name: GREETING
      value: hello
    - name: RETRIES
      value: "3"
    resources:
      requests:
        memory: 64Mi
```

```bash
k apply -f /opt/course/6/fixed.yaml
```

**Verify:** `k get pod broken-app -n fixit` → Running; `k get pod broken-app -n fixit -o jsonpath='{.metadata.labels.version}{"\n"}'` → `1.10`; `k logs broken-app -n fixit` → `hello`.
</details>

### Q7. Sort by restart count with custom-columns
**Frequency:** ⚡ Medium · **Est. time:** 4 min · **Competency:** Output formatting - custom-columns & sort-by

**Setup** (wait ~2 minutes after creating them):

```bash
k create ns crashy
k run crasher -n crashy --image=busybox:1.36 -- sh -c 'sleep 5; exit 1'
k run flaky   -n crashy --image=busybox:1.36 -- sh -c 'sleep 40; exit 1'
k run stable  -n crashy --image=nginx:1.27
```

Write a table with the columns `NAME` and `RESTARTS` (restart count of the first container) of all pods in namespace `crashy`, sorted by restart count ascending and including the header line, into `/opt/course/7/restarts.txt`. Write only the name of the pod with the most restarts into `/opt/course/7/top.txt`.

<details><summary>Solution</summary>

```bash
mkdir -p /opt/course/7
k get pods -n crashy -o custom-columns='NAME:.metadata.name,RESTARTS:.status.containerStatuses[0].restartCount' --sort-by='.status.containerStatuses[0].restartCount' > /opt/course/7/restarts.txt
k get pods -n crashy --sort-by='.status.containerStatuses[0].restartCount' --no-headers -o custom-columns=NAME:.metadata.name | tail -1 > /opt/course/7/top.txt
```

**Verify:** `cat /opt/course/7/restarts.txt` (stable first, crasher last); `cat /opt/course/7/top.txt` → `crasher`.
</details>

### Q8. Write commands (not output) into script files
**Frequency:** ⚡ Medium · **Est. time:** 3 min · **Competency:** Output formatting / shell

Write a kubectl command into `/opt/course/8/pods-by-age.sh` that lists the pods of **all** namespaces sorted by creation time (oldest first). Write a second command into `/opt/course/8/pod-ips.sh` that prints `<pod-name><TAB><pod-IP>` for every pod in namespace `orbit` (from Q1), one per line. Both files must work with `bash <file>`.

<details><summary>Solution</summary>

```bash
mkdir -p /opt/course/8
echo 'kubectl get pods -A --sort-by=.metadata.creationTimestamp' > /opt/course/8/pods-by-age.sh
cat > /opt/course/8/pod-ips.sh <<'EOF'
kubectl get pods -n orbit -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.podIP}{"\n"}{end}'
EOF
```

Use `kubectl`, not the alias `k` - aliases do not exist in `bash file.sh`. The quoted `'EOF'` keeps the JSONPath intact.

**Verify:** `bash /opt/course/8/pods-by-age.sh | head -3`; `bash /opt/course/8/pod-ips.sh` prints 4 tab-separated lines.
</details>

### Q9. Annotations and change-cause
**Frequency:** ⚡ Medium · **Est. time:** 4 min · **Competency:** Annotations / rolling updates

**Setup:**

```bash
k create deploy api -n shop --image=nginx:1.27 --replicas=2
k annotate deploy api -n shop legacy-id=4711
```

For Deployment `api` (namespace `shop`): add the annotation `owner=team-blue`, remove the annotation `legacy-id`, update the image to `nginx:1.27-alpine`, and make `kubectl rollout history` show the change cause `upgrade to alpine` for the new revision. Write the value of the `owner` annotation into `/opt/course/9/owner.txt`.

<details><summary>Solution</summary>

```bash
k annotate deploy api -n shop owner=team-blue
k annotate deploy api -n shop legacy-id-
k set image deploy/api -n shop nginx=nginx:1.27-alpine           # container is named "nginx" (from the image)
k annotate deploy api -n shop kubernetes.io/change-cause="upgrade to alpine" --overwrite
k rollout status deploy/api -n shop
mkdir -p /opt/course/9
k get deploy api -n shop -o jsonpath='{.metadata.annotations.owner}' > /opt/course/9/owner.txt
```

**Verify:** `k rollout history deploy/api -n shop` → revision 2 `upgrade to alpine`; `k get deploy api -n shop -o jsonpath='{.metadata.annotations}{"\n"}'` has no `legacy-id`; `cat /opt/course/9/owner.txt` → `team-blue`.
</details>

### Q10. Patch: NodePort, merge patch, JSON patch
**Frequency:** ⚡ Medium · **Est. time:** 6 min · **Competency:** kubectl power usage - patch

**Setup:**

```bash
k create deploy web -n ops --image=nginx:1.27
k expose deploy web -n ops --port=80
k patch deploy web -n ops --type=json -p '[{"op":"add","path":"/spec/template/spec/containers/0/readinessProbe","value":{"httpGet":{"path":"/","port":80}}}]'
```

In namespace `ops`, using `kubectl patch` only:
1. Service `web` becomes type `NodePort` with nodePort `30085` for port 80.
2. Deployment `web` gets 3 replicas - use a JSON merge patch.
3. Remove the readinessProbe from the Deployment's first container - use a JSON patch.

<details><summary>Solution</summary>

```bash
k patch svc web -n ops -p '{"spec":{"type":"NodePort","ports":[{"port":80,"nodePort":30085}]}}'   # strategic: ports merge by "port"
k patch deploy web -n ops --type=merge -p '{"spec":{"replicas":3}}'
k patch deploy web -n ops --type=json -p '[{"op":"remove","path":"/spec/template/spec/containers/0/readinessProbe"}]'
```

**Verify:** `k get svc web -n ops -o jsonpath='{.spec.type} {.spec.ports[0].nodePort}{"\n"}'` → `NodePort 30085`; `k get deploy web -n ops -o jsonpath='{.spec.replicas}{" probe="}{.spec.template.spec.containers[0].readinessProbe}{"\n"}'` → `3 probe=`.
</details>

### Q11. Pods that are not Running
**Frequency:** ⚡ Medium · **Est. time:** 4 min · **Competency:** Field selectors / monitoring

Write namespace and name of every pod in the cluster whose **phase** is not `Running` into `/opt/course/11/not-running.txt` (no header). Then write the names of all pods in namespace `crashy` (from Q7) whose first container is waiting in `CrashLoopBackOff` into `/opt/course/11/crashloop.txt`.

<details><summary>Solution</summary>

```bash
mkdir -p /opt/course/11
k get pods -A --field-selector=status.phase!=Running --no-headers -o custom-columns=NS:.metadata.namespace,NAME:.metadata.name > /opt/course/11/not-running.txt
k get pods -n crashy -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.status.containerStatuses[0].state.waiting.reason}{"\n"}{end}' | awk '$2=="CrashLoopBackOff"{print $1}' > /opt/course/11/crashloop.txt
```

A CrashLoopBackOff pod still has `status.phase=Running`, so the field selector does not find it - the waiting reason does. Between restarts the reason can briefly be missing (container running) - re-run if a pod is absent.

**Verify:** `cat /opt/course/11/not-running.txt` (Pending/Succeeded/Failed pods only); `cat /opt/course/11/crashloop.txt` → typically `crasher` (and `flaky`).
</details>

### Q12. Images in use across the cluster
**Frequency:** ⚡ Medium · **Est. time:** 3 min · **Competency:** Output formatting - inventory

Write a sorted list without duplicates of all container images - including init containers - used by pods in **all** namespaces into `/opt/course/12/images.txt`, one image per line.

<details><summary>Solution</summary>

```bash
mkdir -p /opt/course/12
k get pods -A -o jsonpath='{range .items[*]}{range .spec.initContainers[*]}{.image}{"\n"}{end}{range .spec.containers[*]}{.image}{"\n"}{end}{end}' | sort -u > /opt/course/12/images.txt
```

Shorter variant from the docs (containers only): `k get pods -A -o jsonpath='{.items[*].spec.containers[*].image}' | tr -s '[[:space:]]' '\n' | sort -u`.

**Verify:** `cat /opt/course/12/images.txt` contains e.g. `busybox:1.36`, `nginx:1.27` and the `registry.k8s.io/...` system images, each once; `grep -c '^$' /opt/course/12/images.txt` → 0.
</details>

### Q13. QoS classes
**Frequency:** ⚡ Medium · **Est. time:** 5 min · **Competency:** Requests & limits (QoS)

In namespace `qos`, create three pods with image `nginx:1.27`: `qos-guaranteed` (QoS class Guaranteed), `qos-burstable` (Burstable) and `qos-besteffort` (BestEffort). Then write `name` and `qosClass` of all pods in `qos` into `/opt/course/13/qos.txt` (no header).

<details><summary>Solution</summary>

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: qos
---
apiVersion: v1
kind: Pod
metadata:
  name: qos-guaranteed
  namespace: qos
spec:
  containers:
  - name: nginx
    image: nginx:1.27
    resources:
      requests:            # requests == limits for cpu AND memory
        cpu: 100m
        memory: 64Mi
      limits:
        cpu: 100m
        memory: 64Mi
---
apiVersion: v1
kind: Pod
metadata:
  name: qos-burstable
  namespace: qos
spec:
  containers:
  - name: nginx
    image: nginx:1.27
    resources:
      requests:            # some request/limit, but not Guaranteed
        cpu: 50m
---
apiVersion: v1
kind: Pod
metadata:
  name: qos-besteffort
  namespace: qos
spec:
  containers:
  - name: nginx
    image: nginx:1.27      # no requests, no limits
```

```bash
k apply -f qos.yaml
mkdir -p /opt/course/13
k get pods -n qos --no-headers -o custom-columns=NAME:.metadata.name,QOS:.status.qosClass > /opt/course/13/qos.txt
```

**Verify:** `cat /opt/course/13/qos.txt` → `qos-besteffort BestEffort`, `qos-burstable Burstable`, `qos-guaranteed Guaranteed`.
</details>

### Q14. nodeSelector
**Frequency:** ⚡ Medium · **Est. time:** 4 min · **Competency:** Scheduling - nodeSelector

Label one worker node with `disktype=ssd` (on a single-node lab: the only node). In namespace `sched`, create pod `fast-cache` (image `redis:7.2`) that may only run on nodes with this label. Write the name of the node it runs on into `/opt/course/14/node.txt`.

<details><summary>Solution</summary>

```bash
NODE=$(k get nodes -l '!node-role.kubernetes.io/control-plane' -o jsonpath='{.items[0].metadata.name}')
# single-node lab: NODE=$(k get nodes -o jsonpath='{.items[0].metadata.name}')
k label node "$NODE" disktype=ssd
k create ns sched
k run fast-cache -n sched --image=redis:7.2 $do > fast-cache.yaml    # then add the nodeSelector
```

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: fast-cache
  namespace: sched
  labels:
    run: fast-cache
spec:
  nodeSelector:
    disktype: ssd
  containers:
  - name: fast-cache
    image: redis:7.2
```

```bash
k apply -f fast-cache.yaml
mkdir -p /opt/course/14
k get pod fast-cache -n sched -o jsonpath='{.spec.nodeName}' > /opt/course/14/node.txt
```

**Verify:** `k get pod fast-cache -n sched -o wide` shows `$NODE`; `k get nodes -l disktype=ssd`.
</details>

### Q15. Taint and toleration for a dedicated node
**Frequency:** ⚡ Medium · **Est. time:** 6 min · **Competency:** Scheduling - taints & tolerations

Taint the node from Q14 with `team=ml:NoSchedule`. In namespace `sched`, create pod `trainer` (image `busybox:1.36`, command `sleep 3600`) that tolerates the taint and is scheduled **only** on that node. Create pod `regular` (image `nginx:1.27`) without tolerations and check where it goes. Finally remove the taint.

<details><summary>Solution</summary>

```bash
k taint nodes "$NODE" team=ml:NoSchedule
cat <<EOF | k apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: trainer
  namespace: sched
spec:
  tolerations:
  - key: team
    operator: Equal
    value: ml
    effect: NoSchedule
  nodeSelector:
    kubernetes.io/hostname: $NODE
  containers:
  - name: trainer
    image: busybox:1.36
    command: ["sh", "-c", "sleep 3600"]
EOF
k run regular -n sched --image=nginx:1.27
k get pods -n sched -o wide
k taint nodes "$NODE" team=ml:NoSchedule-
```

The toleration only *permits* the tainted node; the nodeSelector *forces* it. The heredoc delimiter is unquoted on purpose so that `$NODE` expands.

**Verify:** `trainer` runs on `$NODE`; `regular` runs on another node - or, on a single-node lab, stays Pending with `had untolerated taint {team: ml}` until the taint is removed; `k describe node "$NODE" | grep -i taints` after the last command shows no `team` taint.
</details>

### Q16. Run a pod on the control-plane node
**Frequency:** ⚡ Medium · **Est. time:** 4 min · **Competency:** Scheduling - tolerations + nodeSelector

Create pod `cp-pod` (image `nginx:1.27`) in namespace `default` that runs on a control-plane node. Do not modify any node (no labels added, no taints removed).

<details><summary>Solution</summary>

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: cp-pod
spec:
  tolerations:
  - key: node-role.kubernetes.io/control-plane
    operator: Exists
    effect: NoSchedule
  nodeSelector:
    node-role.kubernetes.io/control-plane: ""
  containers:
  - name: cp-pod
    image: nginx:1.27
```

```bash
k apply -f cp-pod.yaml
```

**Verify:** `k get pod cp-pod -o wide` → NODE is the node listed by `k get nodes -l node-role.kubernetes.io/control-plane`.
</details>

### Q17. One replica per node (pod anti-affinity)
**Frequency:** ⚡ Medium · **Est. time:** 6 min · **Competency:** Scheduling - pod anti-affinity

In namespace `sched`, create Deployment `ha-web` (image `nginx:1.27`, 4 replicas, pod label `app=ha-web`) so that two `ha-web` pods never run on the same node. Write the number of `ha-web` pods that are Pending into `/opt/course/17/pending.txt`.

<details><summary>Solution</summary>

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ha-web
  namespace: sched
spec:
  replicas: 4
  selector:
    matchLabels:
      app: ha-web
  template:
    metadata:
      labels:
        app: ha-web
    spec:
      affinity:
        podAntiAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
          - labelSelector:
              matchLabels:
                app: ha-web
            topologyKey: kubernetes.io/hostname
      containers:
      - name: nginx
        image: nginx:1.27
```

```bash
k apply -f ha-web.yaml
mkdir -p /opt/course/17
k get pods -n sched -l app=ha-web --field-selector=status.phase=Pending --no-headers | wc -l > /opt/course/17/pending.txt
```

**Verify:** `k get pods -n sched -l app=ha-web -o wide` - at most one pod per schedulable node; `k describe pod <pending-pod> -n sched` shows `didn't match pod anti-affinity rules`.
</details>

### Q18. HPA with kubectl autoscale
**Frequency:** ⚡ Medium · **Est. time:** 4 min · **Competency:** Autoscaling - HPA

**Setup:**

```bash
k create ns scale
k create deploy php -n scale --image=httpd:2.4
```

Deployment `php` (namespace `scale`) must scale automatically between 2 and 6 replicas at 60 % average CPU utilization. The HPA must be named `php`. Make sure utilization can be computed: the container needs a CPU request of `100m`.

<details><summary>Solution</summary>

```bash
k set resources deploy php -n scale --requests=cpu=100m
k autoscale deploy php -n scale --min=2 --max=6 --cpu=60%            # kubectl v1.37 (exam)
# old kubectl (v1.33 and older): k autoscale deploy php -n scale --min=2 --max=6 --cpu-percent=60
```

**Verify:** `k get hpa php -n scale` → MINPODS 2, MAXPODS 6, TARGETS `cpu: <x>%/60%` (`<unknown>` means no metrics-server or missing request); `k get hpa php -n scale -o jsonpath='{.spec.metrics[0].resource.target.averageUtilization}{"\n"}'` → `60`; `k get deploy php -n scale` → 2 replicas.
</details>

### Q19. Node affinity (required + preferred)
**Frequency:** 🧊 Low · **Est. time:** 6 min · **Competency:** Scheduling - node affinity

In namespace `sched`, create Deployment `analytics` (image `httpd:2.4`, 2 replicas) whose pods run **only** on nodes whose label `disktype` is `ssd` or `nvme`, and **prefer** (weight 50) nodes labelled `zone=zone-a`.

<details><summary>Solution</summary>

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: analytics
  namespace: sched
spec:
  replicas: 2
  selector:
    matchLabels:
      app: analytics
  template:
    metadata:
      labels:
        app: analytics
    spec:
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
            - matchExpressions:
              - key: disktype
                operator: In
                values: ["ssd", "nvme"]
          preferredDuringSchedulingIgnoredDuringExecution:
          - weight: 50
            preference:
              matchExpressions:
              - key: zone
                operator: In
                values: ["zone-a"]
      containers:
      - name: httpd
        image: httpd:2.4
```

**Verify:** `k get pods -n sched -l app=analytics -o wide` → only nodes from `k get nodes -l 'disktype in (ssd,nvme)'`.
</details>

### Q20. Topology spread across nodes
**Frequency:** 🧊 Low · **Est. time:** 6 min · **Competency:** Scheduling - topology spread constraints

In namespace `sched`, create Deployment `spread` (image `nginx:1.27`, 4 replicas, pod label `app=spread`). The number of `spread` pods per node may differ by at most 1 (hard rule); nodes whose taints the pods do not tolerate must not count. Write the pod count per node (`<count> <node>`) into `/opt/course/20/spread.txt`.

<details><summary>Solution</summary>

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: spread
  namespace: sched
spec:
  replicas: 4
  selector:
    matchLabels:
      app: spread
  template:
    metadata:
      labels:
        app: spread
    spec:
      topologySpreadConstraints:
      - maxSkew: 1
        topologyKey: kubernetes.io/hostname
        whenUnsatisfiable: DoNotSchedule
        nodeTaintsPolicy: Honor
        labelSelector:
          matchLabels:
            app: spread
      containers:
      - name: nginx
        image: nginx:1.27
```

```bash
k apply -f spread.yaml
mkdir -p /opt/course/20
k get pods -n sched -l app=spread -o jsonpath='{range .items[*]}{.spec.nodeName}{"\n"}{end}' | sort | uniq -c > /opt/course/20/spread.txt
```

**Verify:** `cat /opt/course/20/spread.txt` - e.g. `2 node01` / `2 node02` on two workers; all 4 Running.
</details>

### Q21. PriorityClass
**Frequency:** 🧊 Low · **Est. time:** 5 min · **Competency:** Scheduling - priority & preemption

Create PriorityClass `mission-critical` (value `1000000`, not the global default, description `Mission critical apps`) and PriorityClass `batch-low` (value `100`, never preempts other pods). Create pod `important` (image `nginx:1.27`, namespace `default`) that uses `mission-critical`. Write the pod's `spec.priority` into `/opt/course/21/priority.txt`.

<details><summary>Solution</summary>

```bash
k create priorityclass mission-critical --value=1000000 --description="Mission critical apps"
k create priorityclass batch-low --value=100 --preemption-policy=Never
k run important --image=nginx:1.27 $do > important.yaml     # add priorityClassName
```

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: important
  labels:
    run: important
spec:
  priorityClassName: mission-critical
  containers:
  - name: important
    image: nginx:1.27
```

```bash
k apply -f important.yaml
mkdir -p /opt/course/21
k get pod important -o jsonpath='{.spec.priority}' > /opt/course/21/priority.txt
```

**Verify:** `k get pc` shows both classes (`batch-low` with PREEMPTIONPOLICY Never); `cat /opt/course/21/priority.txt` → `1000000`.
</details>

### Q22. HPA v2 with two metrics and behavior
**Frequency:** 🧊 Low · **Est. time:** 7 min · **Competency:** Autoscaling - HPA v2 behavior

**Setup:**

```bash
k create deploy api -n scale --image=httpd:2.4
k set resources deploy api -n scale --requests=cpu=100m,memory=64Mi
```

Create HPA `api-hpa` for Deployment `api` (namespace `scale`): 1-10 replicas, target 75 % average CPU utilization **and** an average memory value of `250Mi` per pod; scale-down may remove at most 1 pod per 60 seconds and uses a 120-second stabilization window. Leave scale-up at its defaults.

<details><summary>Solution</summary>

Start from `k autoscale deploy api -n scale --name=api-hpa --min=1 --max=10 --cpu=75% --memory=250Mi $do > hpa.yaml` and add `behavior`, or write it directly:

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: api-hpa
  namespace: scale
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: api
  minReplicas: 1
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 75
  - type: Resource
    resource:
      name: memory
      target:
        type: AverageValue
        averageValue: 250Mi
  behavior:
    scaleDown:
      stabilizationWindowSeconds: 120
      policies:
      - type: Pods
        value: 1
        periodSeconds: 60
```

```bash
k apply -f hpa.yaml
```

**Verify:** `k describe hpa api-hpa -n scale` (two metrics, behavior); `k get hpa api-hpa -n scale -o jsonpath='{.spec.behavior.scaleDown}{"\n"}'`.
</details>

### Q23. PodDisruptionBudget
**Frequency:** 🧊 Low · **Est. time:** 4 min · **Competency:** Disruptions - PDB

**Setup:**

```bash
k create ns money
k create deploy pay -n money --image=nginx:1.27 --replicas=4
```

Ensure that voluntary disruptions (node drains) can take down at most one `pay` pod (label `app=pay`) at a time. Name the budget `pay-pdb`. Write the number of currently allowed disruptions into `/opt/course/23/allowed.txt`.

<details><summary>Solution</summary>

```bash
k create pdb pay-pdb -n money --selector=app=pay --max-unavailable=1
mkdir -p /opt/course/23
k get pdb pay-pdb -n money -o jsonpath='{.status.disruptionsAllowed}' > /opt/course/23/allowed.txt
```

**Verify:** `k get pdb -n money` → MAX UNAVAILABLE 1, ALLOWED DISRUPTIONS 1 (once all 4 pods are Ready); `cat /opt/course/23/allowed.txt` → `1`. Optional test: `k drain <node> --ignore-daemonsets --pod-selector=app=pay --timeout=60s`, then `k uncordon <node>`.
</details>

### Q24. Discover with api-resources and explain
**Frequency:** 🧊 Low · **Est. time:** 4 min · **Competency:** kubectl power usage - discovery

1. Write the plural resource names of all **cluster-scoped** resources (NAME column only) into `/opt/course/24/cluster-scoped.txt`.
2. Write the short names of `poddisruptionbudgets` and `priorityclasses`, one per line, into `/opt/course/24/short.txt`.
3. Using only kubectl (no browser), find the container field that makes the root filesystem read-only and write its full path in `kubectl explain` notation into `/opt/course/24/field.txt`.

<details><summary>Solution</summary>

```bash
mkdir -p /opt/course/24
k api-resources --namespaced=false --no-headers | awk '{print $1}' > /opt/course/24/cluster-scoped.txt
k api-resources --no-headers | awk '$1=="poddisruptionbudgets" || $1=="priorityclasses" {print $2}' > /opt/course/24/short.txt
k explain pod.spec.containers.securityContext | grep -i readonly
echo 'pod.spec.containers.securityContext.readOnlyRootFilesystem' > /opt/course/24/field.txt
```

**Verify:** `grep -x -e nodes -e namespaces -e persistentvolumes /opt/course/24/cluster-scoped.txt` → 3 lines; `cat /opt/course/24/short.txt` → `pdb`, `pc`; `k explain pod.spec.containers.securityContext.readOnlyRootFilesystem` prints the field's description.
</details>

---

## Must-know summary

- Start every task on the right host/context; on a new host re-export `$do` and `$now`, and `exit` back when done.
- Generate YAML with `$do` for every kind that has a generator; know the ones that do not (DaemonSet, StatefulSet, PV, PVC, NetworkPolicy) and where to copy them from.
- `k explain <kind>.<path>` (and `--recursive`) answers "what is the field called / where does it go" faster than the docs.
- Immutable Pod fields: export or use the `/tmp/kubectl-edit-*.yaml` copy, then `k replace --force -f`.
- One of each patch type: strategic (default, lists merge by name/port), `--type=merge` (lists replaced, `null` deletes), `--type=json` (paths, `remove`).
- JSONPath: `{range .items[*]}...{"\n"}{end}` for one item per line, `?(@.type=="InternalIP")` filters, `\.` for dotted keys; custom-columns + `--sort-by` + `--no-headers` for tables.
- Always `cat` the file you wrote; produce exactly the requested format (no headers, no `pod/` prefix).
- Selectors: `!=` and `notin` also match objects without the key - use `-l 'key,key!=value'`; single-quote selectors with `!` or parentheses.
- `k label/annotate ... --overwrite` changes, `key-` removes; labelling a Deployment does not label its pods.
- Quote YAML strings that look like numbers or booleans (`"1.10"`, `"true"`, `"3"`); never quote integer fields (`replicas`, `containerPort`).
- Toleration permits, nodeSelector/affinity attracts: dedicated or control-plane placement needs both.
- Required pod anti-affinity on `kubernetes.io/hostname` = at most one replica per node; extra replicas stay Pending.
- HPA: metrics-server + CPU requests; on v1.37 `k autoscale ... --cpu=70%` (`--cpu-percent` only on old kubectl); `<unknown>` targets mean missing metrics or requests.
- PDB: `k create pdb x --selector=app=y --max-unavailable=1`; only evictions (drain) respect it - deletes and rollouts do not.
- `yq` is available on exam hosts; `jq` and `tmux` may not be - JSONPath always works.
