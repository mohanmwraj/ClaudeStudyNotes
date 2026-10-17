# Practice Questions - Application Environment, Configuration and Security (25%)

> These are exam-style tasks modelled on the official CNCF curriculum and on task patterns that candidates describe publicly. Real exam questions are confidential under the Linux Foundation candidate agreement; nothing here is a leaked question.

How to use: work in a lab cluster (see [../00-Exam-Overview-and-Setup/README.md](../00-Exam-Overview-and-Setup/README.md)). In a real task, first run the `kubectl config use-context ...` command given in the task header. Create the output folders once: `sudo mkdir -p /opt/course && sudo chown $USER /opt/course`, then `mkdir -p /opt/course/<N>` per question. "Lab setup" blocks create the starting state the exam would already have - they are not part of the task.

Tasks are ordered from most to least frequent: 🔥 Q1-Q10, ⚡ Q11-Q25, 🧊 Q26-Q30. In solutions, a YAML block followed by `kubectl apply -f qN.yaml` means "save the block as `qN.yaml`, then apply it".

---

### Q1. Secret from literals, consumed as env vars
**Frequency:** 🔥 High · **Est. time:** 5 min · **Competency:** Create & consume Secrets

In namespace `shop` (create it if missing): create a Secret `db-creds` with `DB_USER=admin` and `DB_PASS=S3cr3t!`, and a Secret `api-settings` with `TIMEOUT=30` and `REGION=eu`. Create a Pod `api` (image `nginx:1.27`) that exposes `DB_USER` as env var `DB_USER`, the key `DB_PASS` as env var `DB_PASSWORD`, and **all** keys of `api-settings` as env vars prefixed with `API_`.

<details><summary>Solution</summary>

```bash
kubectl create namespace shop
kubectl create secret generic db-creds -n shop --from-literal=DB_USER=admin --from-literal=DB_PASS='S3cr3t!'
kubectl create secret generic api-settings -n shop --from-literal=TIMEOUT=30 --from-literal=REGION=eu
kubectl run api -n shop --image=nginx:1.27 --dry-run=client -o yaml > q1.yaml   # then edit
```

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: api
  namespace: shop
spec:
  containers:
  - name: api
    image: nginx:1.27
    env:
    - name: DB_USER
      valueFrom:
        secretKeyRef:
          name: db-creds
          key: DB_USER
    - name: DB_PASSWORD
      valueFrom:
        secretKeyRef:
          name: db-creds
          key: DB_PASS
    envFrom:
    - prefix: API_
      secretRef:
        name: api-settings
```

```bash
kubectl apply -f q1.yaml
```

**Verify:**

```bash
kubectl exec -n shop api -- printenv DB_USER DB_PASSWORD API_TIMEOUT API_REGION   # admin, S3cr3t!, 30, eu
```
</details>

---

### Q2. ConfigMaps from literals and a file: envFrom + volume
**Frequency:** 🔥 High · **Est. time:** 6 min · **Competency:** Understand ConfigMaps

Lab setup:

```bash
mkdir -p /opt/course/2 && echo '<h1>Hello from a ConfigMap</h1>' > /opt/course/2/index.html
```

In namespace `web`: create ConfigMap `app-config` with `APP_COLOR=blue` and `APP_MODE=prod`, and ConfigMap `nginx-index` from the file `/opt/course/2/index.html` (key `index.html`). Create Deployment `frontend` (image `nginx:1.27`, 2 replicas) that imports all keys of `app-config` as env vars and serves `nginx-index` from `/usr/share/nginx/html`.

<details><summary>Solution</summary>

```bash
kubectl create namespace web
kubectl create configmap app-config -n web --from-literal=APP_COLOR=blue --from-literal=APP_MODE=prod
kubectl create configmap nginx-index -n web --from-file=/opt/course/2/index.html     # key = index.html
kubectl create deployment frontend -n web --image=nginx:1.27 --replicas=2 --dry-run=client -o yaml > q2.yaml
```

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend
  namespace: web
spec:
  replicas: 2
  selector:
    matchLabels:
      app: frontend
  template:
    metadata:
      labels:
        app: frontend
    spec:
      containers:
      - name: nginx
        image: nginx:1.27
        envFrom:
        - configMapRef:
            name: app-config
        volumeMounts:
        - name: html
          mountPath: /usr/share/nginx/html
      volumes:
      - name: html
        configMap:
          name: nginx-index
```

```bash
kubectl apply -f q2.yaml
```

**Verify:**

```bash
kubectl rollout status deploy/frontend -n web
kubectl exec -n web deploy/frontend -- printenv APP_COLOR APP_MODE     # blue, prod
kubectl exec -n web deploy/frontend -- curl -s localhost               # <h1>Hello from a ConfigMap</h1>
```
</details>

---

### Q3. The application logs "forbidden" - use the right ServiceAccount
**Frequency:** 🔥 High · **Est. time:** 6 min · **Competency:** Understand ServiceAccounts

Lab setup:

```bash
kubectl create namespace monitoring
kubectl create serviceaccount metrics-reader -n monitoring
kubectl create serviceaccount log-shipper -n monitoring
kubectl create role pod-lister -n monitoring --verb=get,list --resource=pods
kubectl create rolebinding pod-lister-binding -n monitoring --role=pod-lister --serviceaccount=monitoring:metrics-reader
kubectl create deployment scraper -n monitoring --image=curlimages/curl:8.10.1 -- sh -c 'while true; do curl -s --cacert /var/run/secrets/kubernetes.io/serviceaccount/ca.crt -H "Authorization: Bearer $(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" https://kubernetes.default.svc/api/v1/namespaces/monitoring/pods | head -c 300; echo; sleep 5; done'
```

The Deployment `scraper` in namespace `monitoring` must list Pods in its namespace, but its logs show `forbidden`. Do **not** modify any Role or RoleBinding. Make the Deployment use the ServiceAccount that already has the required permissions.

<details><summary>Solution</summary>

```bash
kubectl logs -n monitoring deploy/scraper --tail=20 | grep -m1 message
#   "message": "pods is forbidden: User \"system:serviceaccount:monitoring:default\" cannot list resource \"pods\" ...
kubectl get role,rolebinding -n monitoring -o wide
# rolebinding pod-lister-binding  ROLE: Role/pod-lister  SERVICEACCOUNTS: monitoring/metrics-reader
kubectl describe role pod-lister -n monitoring          # pods: get, list -> what we need
kubectl set serviceaccount deploy/scraper metrics-reader -n monitoring
kubectl rollout status deploy/scraper -n monitoring
```

**Verify:**

```bash
kubectl get deploy scraper -n monitoring -o jsonpath='{.spec.template.spec.serviceAccountName}{"\n"}'   # metrics-reader
kubectl auth can-i list pods -n monitoring --as=system:serviceaccount:monitoring:metrics-reader       # yes
kubectl logs -n monitoring deploy/scraper --since=15s | grep -m1 '"kind"'     # "kind": "PodList"
kubectl logs -n monitoring deploy/scraper --since=15s | grep -c forbidden     # 0
```
</details>

---

### Q4. ServiceAccount + Role + RoleBinding, proven with can-i
**Frequency:** 🔥 High · **Est. time:** 6 min · **Competency:** Understand authentication, authorization and admission control

In namespace `team-a` create ServiceAccount `deployer`. Create Role `deploy-manager` allowing `get, list, watch, create, update, patch, delete` on Deployments and `get, list, watch` on Pods, and bind it to `deployer` with RoleBinding `deployer-binding`. Write the output of "can `deployer` delete deployments in `team-a`?" to `/opt/course/4/team-a.txt` and the same check for namespace `default` to `/opt/course/4/default.txt`.

<details><summary>Solution</summary>

One `kubectl create role` call gives all resources the same verbs, so generate YAML and add the second rule:

```bash
kubectl create namespace team-a
kubectl create serviceaccount deployer -n team-a
kubectl create role deploy-manager -n team-a --verb=get,list,watch,create,update,patch,delete \
  --resource=deployments --dry-run=client -o yaml > q4-role.yaml
```

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: deploy-manager
  namespace: team-a
rules:
- apiGroups: ["apps"]
  resources: ["deployments"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["get", "list", "watch"]
```

```bash
kubectl apply -f q4-role.yaml
kubectl create rolebinding deployer-binding -n team-a --role=deploy-manager --serviceaccount=team-a:deployer
mkdir -p /opt/course/4
kubectl auth can-i delete deployments -n team-a --as=system:serviceaccount:team-a:deployer > /opt/course/4/team-a.txt
kubectl auth can-i delete deployments -n default --as=system:serviceaccount:team-a:deployer > /opt/course/4/default.txt
```

**Verify:**

```bash
cat /opt/course/4/team-a.txt /opt/course/4/default.txt          # yes / no
kubectl auth can-i delete pods -n team-a --as=system:serviceaccount:team-a:deployer   # no (read-only on pods)
kubectl get rolebinding deployer-binding -n team-a -o wide
```
</details>

---

### Q5. Run as a specific user and group, with fsGroup on a volume
**Frequency:** 🔥 High · **Est. time:** 5 min · **Competency:** Understand Application Security (SecurityContexts, Capabilities, etc.)

In namespace `sec` create Pod `secure-pod` (image `busybox:1.36`, command `sleep 3600`). All processes run as UID `1000` and GID `3000`; files on an `emptyDir` volume mounted at `/data` must be group-owned by `2000`; privilege escalation must be disabled. Write the output of `id` from the container to `/opt/course/5/id.txt`.

<details><summary>Solution</summary>

```bash
kubectl create namespace sec
kubectl run secure-pod -n sec --image=busybox:1.36 --dry-run=client -o yaml -- sh -c 'sleep 3600' > q5.yaml
```

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: secure-pod
  namespace: sec
spec:
  securityContext:              # pod level: users, groups, fsGroup
    runAsUser: 1000
    runAsGroup: 3000
    fsGroup: 2000
  volumes:
  - name: data
    emptyDir: {}
  containers:
  - name: secure-pod
    image: busybox:1.36
    command: ["sh", "-c", "sleep 3600"]
    securityContext:            # container level only
      allowPrivilegeEscalation: false
    volumeMounts:
    - name: data
      mountPath: /data
```

```bash
kubectl apply -f q5.yaml
mkdir -p /opt/course/5
kubectl exec -n sec secure-pod -- id > /opt/course/5/id.txt
```

**Verify:**

```bash
cat /opt/course/5/id.txt                                         # uid=1000 gid=3000 groups include 2000
kubectl exec -n sec secure-pod -- sh -c 'touch /data/f && ls -ln /data/f'   # owner 1000, group 2000
kubectl exec -n sec secure-pod -- grep NoNewPrivs /proc/1/status            # NoNewPrivs: 1
```
</details>

---

### Q6. Add and drop Linux capabilities
**Frequency:** 🔥 High · **Est. time:** 4 min · **Competency:** Understand Application Security (SecurityContexts, Capabilities, etc.)

In namespace `sec` create Pod `net-tools` (image `busybox:1.36`, command `sleep 3600`) that drops **all** capabilities and adds only `NET_ADMIN` and `SYS_TIME`. Write the `CapEff` line of the container's PID 1 to `/opt/course/6/caps.txt`.

<details><summary>Solution</summary>

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: net-tools
  namespace: sec
spec:
  containers:
  - name: net-tools
    image: busybox:1.36
    command: ["sh", "-c", "sleep 3600"]
    securityContext:
      capabilities:
        drop: ["ALL"]
        add: ["NET_ADMIN", "SYS_TIME"]     # no CAP_ prefix
```

```bash
kubectl apply -f q6.yaml
mkdir -p /opt/course/6
kubectl exec -n sec net-tools -- grep CapEff /proc/1/status > /opt/course/6/caps.txt
```

**Verify:**

```bash
cat /opt/course/6/caps.txt                     # CapEff: 0000000002001000  (NET_ADMIN 0x1000 + SYS_TIME 0x2000000)
kubectl exec -n sec net-tools -- ip addr add 10.200.0.1/32 dev lo && echo NET_ADMIN works
# do NOT test SYS_TIME with `date -s`: the clock is not namespaced and the node's time would change
```
</details>

---

### Q7. Requests and limits that fit a namespace quota
**Frequency:** 🔥 High · **Est. time:** 7 min · **Competency:** Define resource requirements

Lab setup:

```bash
kubectl create namespace quota-ns
kubectl create quota compute -n quota-ns --hard=requests.cpu=1,requests.memory=1Gi,limits.cpu=2,limits.memory=2Gi
```

In namespace `quota-ns` create Deployment `worker` (image `busybox:1.36`, command `sleep 3600`, 3 replicas). Each container requests `250m` CPU / `256Mi` memory and is limited to `500m` CPU / `512Mi` memory. All 3 replicas must be running. Save `kubectl describe quota compute -n quota-ns` to `/opt/course/7/quota.txt`.

<details><summary>Solution</summary>

```bash
kubectl create deployment worker -n quota-ns --image=busybox:1.36 --replicas=3 \
  --dry-run=client -o yaml -- sleep 3600 > q7.yaml
kubectl set resources --local -f q7.yaml --requests=cpu=250m,memory=256Mi \
  --limits=cpu=500m,memory=512Mi -o yaml > q7-res.yaml
kubectl apply -f q7-res.yaml
kubectl rollout status deploy/worker -n quota-ns
mkdir -p /opt/course/7 && kubectl describe quota compute -n quota-ns > /opt/course/7/quota.txt
```

Without resources the ReplicaSet could not create any Pod (`failed quota: compute: must specify ...`). Totals: 3 x 250m = 750m of 1 CPU requested, 3 x 512Mi = 1.5Gi of 2Gi memory limit.

**Verify:**

```bash
kubectl get deploy worker -n quota-ns                      # READY 3/3
cat /opt/course/7/quota.txt                                # requests.cpu 750m/1, limits.memory 1536Mi/2Gi
kubectl scale deploy worker -n quota-ns --replicas=5       # experiment: only 4 Pods fit
kubectl describe rs -n quota-ns -l app=worker | grep -m1 'exceeded quota'
kubectl scale deploy worker -n quota-ns --replicas=3
```
</details>

---

### Q8. ResourceQuota with compute and object counts
**Frequency:** 🔥 High · **Est. time:** 4 min · **Competency:** Understand requests, limits, quotas

In namespace `dev-team` create ResourceQuota `team-quota`: max 5 Pods, total requests `2` CPU / `4Gi` memory, total limits `4` CPU / `8Gi` memory, max 10 ConfigMaps, 10 Secrets, 3 Services and 3 Deployments.

<details><summary>Solution</summary>

```bash
kubectl create namespace dev-team
kubectl create quota team-quota -n dev-team \
  --hard=pods=5,requests.cpu=2,requests.memory=4Gi,limits.cpu=4,limits.memory=8Gi,configmaps=10,secrets=10,services=3,count/deployments.apps=3
```

**Verify:**

```bash
kubectl describe quota team-quota -n dev-team            # every key with Used/Hard
for i in 1 2 3 4; do kubectl create deployment d$i -n dev-team --image=nginx:1.27; done
# the 4th fails: exceeded quota: team-quota, requested: count/deployments.apps=1, used: ...=3, limited: ...=3
# (and d1-d3 get no Pods: they declare no requests/limits -> "must specify" in their ReplicaSet events)
kubectl delete deployment d1 d2 d3 -n dev-team
```
</details>

---

### Q9. Secret from a file, mounted as one file with mode 0400; decode another Secret
**Frequency:** 🔥 High · **Est. time:** 6 min · **Competency:** Create & consume Secrets

Lab setup:

```bash
mkdir -p /opt/course/9 && echo -n 'tok-12345' > /opt/course/9/token.txt
kubectl create namespace vault-demo
kubectl create secret generic legacy-creds -n vault-demo --from-literal=password='Pa55-legacy'
```

In namespace `vault-demo`: create Secret `api-token` with key `token` from the file `/opt/course/9/token.txt`. Create Pod `consumer` (image `busybox:1.36`, `sleep 3600`) that mounts **only** key `token` as the file `/etc/api/token-file` with permissions `0400`. Write the decoded `password` of the existing Secret `legacy-creds` to `/opt/course/9/legacy-password.txt`.

<details><summary>Solution</summary>

```bash
kubectl create secret generic api-token -n vault-demo --from-file=token=/opt/course/9/token.txt
```

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: consumer
  namespace: vault-demo
spec:
  containers:
  - name: consumer
    image: busybox:1.36
    command: ["sh", "-c", "sleep 3600"]
    volumeMounts:
    - name: token
      mountPath: /etc/api
      readOnly: true
  volumes:
  - name: token
    secret:
      secretName: api-token
      defaultMode: 0400
      items:
      - key: token
        path: token-file
```

```bash
kubectl apply -f q9.yaml
kubectl get secret legacy-creds -n vault-demo -o jsonpath='{.data.password}' | base64 -d > /opt/course/9/legacy-password.txt
```

**Verify:**

```bash
kubectl exec -n vault-demo consumer -- cat /etc/api/token-file          # tok-12345
kubectl exec -n vault-demo consumer -- ls -lL /etc/api/token-file       # -r-------- (-L follows the symlink)
cat /opt/course/9/legacy-password.txt                                    # Pa55-legacy
```
</details>

---

### Q10. Discover a CRD and use its custom resources
**Frequency:** 🔥 High · **Est. time:** 6 min · **Competency:** Discover and use resources that extend Kubernetes (CRD, Operators)

Lab setup (files from this chapter):

```bash
kubectl apply -f yaml/crd-crontab.yaml
kubectl wait --for=condition=Established crd/crontabs.stable.example.com
kubectl apply -f yaml/cr-crontab-instance.yaml
kubectl create namespace batch-jobs
kubectl apply -n batch-jobs -f yaml/cr-crontab-instance.yaml
```

1. Write the names of all CRDs of API group `stable.example.com` to `/opt/course/10/crds.txt`.
2. Write the API resource information (name, short names, API version, namespaced, kind) of that group to `/opt/course/10/resources.txt`.
3. Write `<namespace>/<name>` of every CronTab in the cluster to `/opt/course/10/crontabs.txt`.
4. Create a CronTab `weekly-backup` in namespace `default` with `cronSpec: "0 3 * * 0"`, `image: busybox:1.36` and `replicas: 1`.

<details><summary>Solution</summary>

```bash
mkdir -p /opt/course/10
kubectl get crd -o custom-columns=NAME:.metadata.name,GROUP:.spec.group --no-headers \
  | awk '$2=="stable.example.com" {print $1}' > /opt/course/10/crds.txt
kubectl api-resources --api-group=stable.example.com > /opt/course/10/resources.txt
kubectl get crontabs -A -o custom-columns=NS:.metadata.namespace,NAME:.metadata.name --no-headers \
  | awk '{print $1"/"$2}' > /opt/course/10/crontabs.txt
kubectl explain crontab.spec                       # discover the fields
```

```yaml
apiVersion: stable.example.com/v1
kind: CronTab
metadata:
  name: weekly-backup
  namespace: default
spec:
  cronSpec: "0 3 * * 0"
  image: busybox:1.36
  replicas: 1
```

```bash
kubectl apply -f q10.yaml
```

**Verify:**

```bash
cat /opt/course/10/crds.txt /opt/course/10/resources.txt /opt/course/10/crontabs.txt
kubectl get ct weekly-backup -n default          # SPEC "0 3 * * 0", IMAGE busybox:1.36, REPLICAS 1
```
</details>

---

### Q11. kubeconfig: contexts, current context, client certificate
**Frequency:** ⚡ Medium · **Est. time:** 6 min · **Competency:** Understand authentication, authorization and admission control

Lab setup:

```bash
mkdir -p /opt/course/11 && cp ~/.kube/config /opt/course/11/kubeconfig
```

Using only the kubeconfig `/opt/course/11/kubeconfig`:

1. Write all context names (one per line) to `/opt/course/11/contexts`.
2. Write the current context name to `/opt/course/11/current-context`.
3. Write a shell command that prints the current context **without using kubectl** to `/opt/course/11/current-context.sh`.
4. Write the decoded client certificate of the user of the current context to `/opt/course/11/client.crt`.
5. Add a context `dev-admin` that uses the current context's cluster and user with default namespace `dev`. Do not switch to it.

<details><summary>Solution</summary>

```bash
KC=/opt/course/11/kubeconfig
kubectl --kubeconfig $KC config get-contexts -o name > /opt/course/11/contexts
kubectl --kubeconfig $KC config current-context > /opt/course/11/current-context
echo "grep 'current-context:' $KC | awk '{print \$2}'" > /opt/course/11/current-context.sh
kubectl --kubeconfig $KC config view --raw --minify \
  -o jsonpath='{.users[0].user.client-certificate-data}' | base64 -d > /opt/course/11/client.crt
CLUSTER=$(kubectl --kubeconfig $KC config view --minify -o jsonpath='{.contexts[0].context.cluster}')
KUSER=$(kubectl --kubeconfig $KC config view --minify -o jsonpath='{.contexts[0].context.user}')
kubectl --kubeconfig $KC config set-context dev-admin --cluster=$CLUSTER --user=$KUSER --namespace=dev
```

`--minify` keeps only the current context's cluster and user, so `users[0]` is the right one. If the kubeconfig references a certificate **file** (`client-certificate:`) instead of embedded data, copy that file instead. Without `--raw`, kubectl prints `DATA+OMITTED`.

**Verify:**

```bash
cat /opt/course/11/contexts /opt/course/11/current-context
bash /opt/course/11/current-context.sh                       # same name as current-context
head -1 /opt/course/11/client.crt                            # -----BEGIN CERTIFICATE-----
kubectl --kubeconfig $KC config get-contexts                 # dev-admin listed, * still on the old one
```
</details>

---

### Q12. Pods rejected by Pod Security Admission - fix the Deployment
**Frequency:** ⚡ Medium · **Est. time:** 7 min · **Competency:** Understand authentication, authorization and admission control

Lab setup:

```bash
kubectl create namespace restricted-apps
kubectl label namespace restricted-apps pod-security.kubernetes.io/enforce=restricted
kubectl create deployment legacy-app -n restricted-apps --image=busybox:1.36 --replicas=2 -- sh -c 'while true; do date; sleep 10; done'
```

Deployment `legacy-app` in namespace `restricted-apps` has no running Pods. Find out why and fix the **Deployment** so both replicas run. Do not change the namespace labels. The app may run as UID `1000`.

<details><summary>Solution</summary>

```bash
kubectl get deploy,rs -n restricted-apps                       # READY 0/2, CURRENT 0
kubectl describe rs -n restricted-apps -l app=legacy-app | grep -m1 -A2 FailedCreate
# ... violates PodSecurity "restricted:latest": allowPrivilegeEscalation != false, unrestricted capabilities,
#     runAsNonRoot != true, seccompProfile ...
kubectl edit deploy legacy-app -n restricted-apps
```

Merge into `spec.template.spec` (add the `securityContext` keys to the existing `busybox` container):

```yaml
securityContext:
  runAsNonRoot: true
  runAsUser: 1000
  seccompProfile:
    type: RuntimeDefault
containers:
- name: busybox
  image: busybox:1.36
  command: ["sh", "-c", "while true; do date; sleep 10; done"]
  securityContext:
    allowPrivilegeEscalation: false
    capabilities:
      drop: ["ALL"]
```

Same change as a one-liner (strategic merge patch merges containers by name):

```bash
kubectl patch deploy legacy-app -n restricted-apps -p '{"spec":{"template":{"spec":{"securityContext":{"runAsNonRoot":true,"runAsUser":1000,"seccompProfile":{"type":"RuntimeDefault"}},"containers":[{"name":"busybox","securityContext":{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]}}}]}}}}'
```

**Verify:**

```bash
kubectl rollout status deploy/legacy-app -n restricted-apps    # 2/2
kubectl get ns restricted-apps --show-labels                   # label unchanged
kubectl logs -n restricted-apps deploy/legacy-app --tail=2
```
</details>

---

### Q13. LimitRange defaults and maximums
**Frequency:** ⚡ Medium · **Est. time:** 6 min · **Competency:** Understand requests, limits, quotas

In namespace `limits-demo` create LimitRange `container-defaults` so that containers without resources get requests `100m` CPU / `128Mi` memory and limits `500m` CPU / `256Mi` memory, and no container may have more than `1` CPU / `512Mi` memory. Then create Pod `no-resources` (image `nginx:1.27`, no resources) and write its effective `resources` to `/opt/course/13/resources.txt`. Finally try Pod `too-big` with a memory limit of `1Gi` and write the error to `/opt/course/13/error.txt`.

<details><summary>Solution</summary>

```yaml
apiVersion: v1
kind: LimitRange
metadata:
  name: container-defaults
  namespace: limits-demo
spec:
  limits:
  - type: Container
    default:
      cpu: 500m
      memory: 256Mi
    defaultRequest:
      cpu: 100m
      memory: 128Mi
    max:
      cpu: "1"
      memory: 512Mi
```

```bash
kubectl create namespace limits-demo
kubectl apply -f q13-lr.yaml
kubectl run no-resources -n limits-demo --image=nginx:1.27
mkdir -p /opt/course/13
kubectl get pod no-resources -n limits-demo -o jsonpath='{.spec.containers[0].resources}' > /opt/course/13/resources.txt
kubectl run too-big -n limits-demo --image=nginx:1.27 --dry-run=client -o yaml \
  | kubectl set resources --local -f - --limits=memory=1Gi -o yaml \
  | kubectl apply -f - 2> /opt/course/13/error.txt
```

**Verify:**

```bash
cat /opt/course/13/resources.txt   # {"limits":{"cpu":"500m","memory":"256Mi"},"requests":{"cpu":"100m","memory":"128Mi"}}
cat /opt/course/13/error.txt       # ... forbidden: maximum memory usage per Container is 512Mi, but limit is 1Gi
kubectl describe limitrange container-defaults -n limits-demo
```
</details>

---

### Q14. Create Pods of each QoS class and report them
**Frequency:** ⚡ Medium · **Est. time:** 5 min · **Competency:** Understand requests, limits, quotas

In namespace `qos` create three Pods with image `nginx:1.27`: `qos-g` (Guaranteed: `100m` CPU / `64Mi` memory), `qos-b` (Burstable: requests `50m` / `32Mi` only) and `qos-be` (BestEffort). Write each Pod's name and QoS class to `/opt/course/14/qos.txt`.

<details><summary>Solution</summary>

```bash
kubectl create namespace qos
kubectl run qos-g -n qos --image=nginx:1.27 --dry-run=client -o yaml \
  | kubectl set resources --local -f - --requests=cpu=100m,memory=64Mi --limits=cpu=100m,memory=64Mi -o yaml \
  | kubectl apply -f -
kubectl run qos-b -n qos --image=nginx:1.27 --dry-run=client -o yaml \
  | kubectl set resources --local -f - --requests=cpu=50m,memory=32Mi -o yaml \
  | kubectl apply -f -
kubectl run qos-be -n qos --image=nginx:1.27
mkdir -p /opt/course/14
kubectl get pods -n qos -o custom-columns=NAME:.metadata.name,QOS:.status.qosClass > /opt/course/14/qos.txt
```

**Verify:**

```bash
cat /opt/course/14/qos.txt          # qos-b Burstable, qos-be BestEffort, qos-g Guaranteed
```
</details>

---

### Q15. ClusterRole used in one namespace only
**Frequency:** ⚡ Medium · **Est. time:** 4 min · **Competency:** Understand authentication, authorization and admission control

Create ClusterRole `secret-reader` (`get`, `list`, `watch` on Secrets). User `alice` must be able to read Secrets **only** in namespace `finance`. Write the `can-i list secrets` answer for `alice` in `finance` to `/opt/course/15/finance.txt` and in `default` to `/opt/course/15/default.txt`.

<details><summary>Solution</summary>

```bash
kubectl create namespace finance
kubectl create clusterrole secret-reader --verb=get,list,watch --resource=secrets
kubectl create rolebinding alice-secret-reader -n finance --clusterrole=secret-reader --user=alice
mkdir -p /opt/course/15
kubectl auth can-i list secrets -n finance --as=alice > /opt/course/15/finance.txt
kubectl auth can-i list secrets -n default --as=alice > /opt/course/15/default.txt
```

A **RoleBinding** to a ClusterRole limits it to the binding's namespace; a ClusterRoleBinding would grant it everywhere.

**Verify:**

```bash
cat /opt/course/15/finance.txt /opt/course/15/default.txt    # yes / no
kubectl describe rolebinding alice-secret-reader -n finance
```
</details>

---

### Q16. ClusterRoleBinding for a ServiceAccount (cluster-scoped resources)
**Frequency:** ⚡ Medium · **Est. time:** 4 min · **Competency:** Understand authentication, authorization and admission control

In namespace `ops` create ServiceAccount `node-viewer`. It must be able to `get`, `list` and `watch` Nodes. Use ClusterRole `node-reader` and ClusterRoleBinding `node-viewer-binding`.

<details><summary>Solution</summary>

```bash
kubectl create namespace ops
kubectl create serviceaccount node-viewer -n ops
kubectl create clusterrole node-reader --verb=get,list,watch --resource=nodes
kubectl create clusterrolebinding node-viewer-binding --clusterrole=node-reader --serviceaccount=ops:node-viewer
```

Nodes are cluster-scoped, so a RoleBinding cannot grant them - a ClusterRoleBinding is required.

**Verify:**

```bash
kubectl auth can-i list nodes --as=system:serviceaccount:ops:node-viewer      # yes
kubectl get nodes --as=system:serviceaccount:ops:node-viewer                  # works
kubectl auth can-i delete nodes --as=system:serviceaccount:ops:node-viewer    # no
```
</details>

---

### Q17. Private registry credentials for a whole namespace
**Frequency:** ⚡ Medium · **Est. time:** 5 min · **Competency:** Create & consume Secrets

In namespace `private` create a docker-registry Secret `regcred` for server `registry.example.com`, user `ci`, password `pa55word`, email `ci@example.com`. Make every new Pod that uses the namespace's `default` ServiceAccount get this pull secret automatically. Create Pod `private-app` (image `nginx:1.27`) to prove it.

<details><summary>Solution</summary>

```bash
kubectl create namespace private
kubectl create secret docker-registry regcred -n private --docker-server=registry.example.com \
  --docker-username=ci --docker-password=pa55word --docker-email=ci@example.com
kubectl patch serviceaccount default -n private -p '{"imagePullSecrets":[{"name":"regcred"}]}'
kubectl run private-app -n private --image=nginx:1.27
```

**Verify:**

```bash
kubectl get secret regcred -n private -o jsonpath='{.type}{"\n"}'                 # kubernetes.io/dockerconfigjson
kubectl get secret regcred -n private -o jsonpath='{.data.\.dockerconfigjson}' | base64 -d; echo
kubectl get pod private-app -n private -o jsonpath='{.spec.imagePullSecrets}{"\n"}'   # [{"name":"regcred"}]
```

Per-Pod alternative: `spec.imagePullSecrets: [{name: regcred}]` in the Pod spec.
</details>

---

### Q18. One ConfigMap key as a file in an existing directory (subPath) and renamed keys (items)
**Frequency:** ⚡ Medium · **Est. time:** 6 min · **Competency:** Understand ConfigMaps

Lab setup:

```bash
mkdir -p /opt/course/18
cat > /opt/course/18/proxy.conf <<'EOF'
server {
  listen 80;
  default_type text/plain;
  location / { return 200 'served by proxy.conf\n'; }
}
EOF
```

In namespace `web` create ConfigMap `proxy-conf` with key `default.conf` holding the content of `/opt/course/18/proxy.conf`. Create Pod `custom-nginx` (image `nginx:1.27`) that mounts that key as `/etc/nginx/conf.d/default.conf` without replacing the directory, and additionally mounts the same key as `/config/site.conf`.

<details><summary>Solution</summary>

```bash
kubectl create namespace web 2>/dev/null || true
kubectl create configmap proxy-conf -n web --from-file=default.conf=/opt/course/18/proxy.conf   # custom key
```

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: custom-nginx
  namespace: web
spec:
  containers:
  - name: nginx
    image: nginx:1.27
    volumeMounts:
    - name: proxy
      mountPath: /etc/nginx/conf.d/default.conf
      subPath: default.conf             # single file; no live updates
    - name: proxy-renamed
      mountPath: /config
  volumes:
  - name: proxy
    configMap:
      name: proxy-conf
  - name: proxy-renamed
    configMap:
      name: proxy-conf
      items:
      - key: default.conf
        path: site.conf
```

```bash
kubectl apply -f q18.yaml
```

**Verify:**

```bash
kubectl exec -n web custom-nginx -- curl -s localhost          # served by proxy.conf
kubectl exec -n web custom-nginx -- ls /etc/nginx              # nginx.conf, mime.types ... still there
kubectl exec -n web custom-nginx -- ls /config                 # site.conf
```
</details>

---

### Q19. ConfigMap from an env-file, single key as env, then roll out a change
**Frequency:** ⚡ Medium · **Est. time:** 6 min · **Competency:** Understand ConfigMaps

Lab setup:

```bash
mkdir -p /opt/course/19 && printf 'COLOR=blue\nFONT=sans\n' > /opt/course/19/ui.env
```

In namespace `ui` create ConfigMap `ui-config` from the env-file `/opt/course/19/ui.env`. Create Deployment `colors` (image `nginx:1.27`, 2 replicas) whose containers get env var `UI_COLOR` from key `COLOR`. Then change `COLOR` to `green` and make sure the running Pods see the new value.

<details><summary>Solution</summary>

```bash
kubectl create namespace ui
kubectl create configmap ui-config -n ui --from-env-file=/opt/course/19/ui.env
kubectl create deployment colors -n ui --image=nginx:1.27 --replicas=2 --dry-run=client -o yaml > q19.yaml
```

Add to the container in `q19.yaml`:

```yaml
env:
- name: UI_COLOR
  valueFrom:
    configMapKeyRef:
      name: ui-config
      key: COLOR
```

```bash
kubectl apply -f q19.yaml
kubectl patch configmap ui-config -n ui --type=merge -p '{"data":{"COLOR":"green"}}'   # keeps FONT
kubectl rollout restart deploy/colors -n ui            # env vars are only read at container start
kubectl rollout status deploy/colors -n ui
```

Do not recreate the ConfigMap with only `--from-literal=COLOR=green` - that would drop `FONT`.

**Verify:**

```bash
kubectl get cm ui-config -n ui -o jsonpath='{.data}{"\n"}'          # COLOR green, FONT sans
kubectl exec -n ui deploy/colors -- printenv UI_COLOR                # green
```
</details>

---

### Q20. Downward API as environment variables
**Frequency:** ⚡ Medium · **Est. time:** 5 min · **Competency:** Understand ConfigMaps (application environment / Downward API)

In namespace `meta` create Pod `info` (image `busybox:1.36`, `sleep 3600`, CPU limit `300m`, memory limit `64Mi`) with env vars `MY_POD_NAME`, `MY_NAMESPACE`, `MY_POD_IP`, `MY_NODE` and `MY_CPU_LIMIT` (CPU limit in millicores). Write all `MY_*` variables (sorted) to `/opt/course/20/env.txt`.

<details><summary>Solution</summary>

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: info
  namespace: meta
spec:
  containers:
  - name: info
    image: busybox:1.36
    command: ["sh", "-c", "sleep 3600"]
    resources:
      limits:
        cpu: 300m
        memory: 64Mi
    env:
    - name: MY_POD_NAME
      valueFrom:
        fieldRef:
          fieldPath: metadata.name
    - name: MY_NAMESPACE
      valueFrom:
        fieldRef:
          fieldPath: metadata.namespace
    - name: MY_POD_IP
      valueFrom:
        fieldRef:
          fieldPath: status.podIP
    - name: MY_NODE
      valueFrom:
        fieldRef:
          fieldPath: spec.nodeName
    - name: MY_CPU_LIMIT
      valueFrom:
        resourceFieldRef:
          resource: limits.cpu
          divisor: 1m
```

```bash
kubectl create namespace meta
kubectl apply -f q20.yaml
mkdir -p /opt/course/20
kubectl exec -n meta info -- env | grep '^MY_' | sort > /opt/course/20/env.txt
```

**Verify:**

```bash
cat /opt/course/20/env.txt        # MY_CPU_LIMIT=300, MY_NAMESPACE=meta, MY_NODE=<node>, MY_POD_IP=<ip>, MY_POD_NAME=info
kubectl get pod info -n meta -o wide                 # IP and NODE match
```
</details>

---

### Q21. Read-only root filesystem with writable scratch paths
**Frequency:** ⚡ Medium · **Est. time:** 6 min · **Competency:** Understand Application Security (SecurityContexts, Capabilities, etc.)

In namespace `secure` create Deployment `hardened-web` (image `nginx:1.27`, 1 replica) whose container has a read-only root filesystem and cannot escalate privileges. nginx must still run: give it writable `emptyDir` volumes at `/var/cache/nginx`, `/var/run` and `/tmp`.

<details><summary>Solution</summary>

```bash
kubectl create namespace secure
kubectl create deployment hardened-web -n secure --image=nginx:1.27 --dry-run=client -o yaml > q21.yaml
```

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: hardened-web
  namespace: secure
spec:
  replicas: 1
  selector:
    matchLabels:
      app: hardened-web
  template:
    metadata:
      labels:
        app: hardened-web
    spec:
      containers:
      - name: nginx
        image: nginx:1.27
        securityContext:
          readOnlyRootFilesystem: true
          allowPrivilegeEscalation: false
        volumeMounts:
        - name: cache
          mountPath: /var/cache/nginx
        - name: run
          mountPath: /var/run
        - name: tmp
          mountPath: /tmp
      volumes:
      - name: cache
        emptyDir: {}
      - name: run
        emptyDir: {}
      - name: tmp
        emptyDir: {}
```

```bash
kubectl apply -f q21.yaml
```

**Verify:**

```bash
kubectl rollout status deploy/hardened-web -n secure                 # 1/1, no CrashLoopBackOff
kubectl exec -n secure deploy/hardened-web -- touch /test.txt        # Read-only file system
kubectl exec -n secure deploy/hardened-web -- touch /tmp/ok.txt      # works
kubectl exec -n secure deploy/hardened-web -- curl -s -o /dev/null -w '%{http_code}\n' localhost   # 200
```
</details>

---

### Q22. ServiceAccount tokens and automount
**Frequency:** ⚡ Medium · **Est. time:** 7 min · **Competency:** Understand ServiceAccounts

In namespace `cicd`:

1. Create ServiceAccount `ci-bot` and write a token for it, valid for 2 hours, to `/opt/course/22/token`.
2. Create a long-lived token Secret `ci-bot-token` for `ci-bot`.
3. Disable token automount on the ServiceAccount.
4. Create Pod `ci-runner` (image `busybox:1.36`, `sleep 3600`) running as `ci-bot` that **does** get the token mounted.

<details><summary>Solution</summary>

```bash
kubectl create namespace cicd
kubectl create serviceaccount ci-bot -n cicd
mkdir -p /opt/course/22
kubectl create token ci-bot -n cicd --duration=2h > /opt/course/22/token
kubectl patch serviceaccount ci-bot -n cicd -p '{"automountServiceAccountToken": false}'
```

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: ci-bot-token
  namespace: cicd
  annotations:
    kubernetes.io/service-account.name: ci-bot
type: kubernetes.io/service-account-token
---
apiVersion: v1
kind: Pod
metadata:
  name: ci-runner
  namespace: cicd
spec:
  serviceAccountName: ci-bot
  automountServiceAccountToken: true      # Pod level overrides the SA's false
  containers:
  - name: runner
    image: busybox:1.36
    command: ["sh", "-c", "sleep 3600"]
```

```bash
kubectl apply -f q22.yaml
```

**Verify:**

```bash
cut -c1-10 /opt/course/22/token                                          # eyJhbGciOi (a JWT)
kubectl get secret ci-bot-token -n cicd -o jsonpath='{.data.token}' | base64 -d | cut -c1-10; echo   # populated
kubectl get sa ci-bot -n cicd -o jsonpath='{.automountServiceAccountToken}{"\n"}'                    # false
kubectl exec -n cicd ci-runner -- ls /var/run/secrets/kubernetes.io/serviceaccount                   # ca.crt namespace token
kubectl run no-override -n cicd --image=busybox:1.36 --overrides='{"apiVersion":"v1","spec":{"serviceAccountName":"ci-bot"}}' -- sleep 3600
kubectl exec -n cicd no-override -- ls /var/run/secrets/kubernetes.io/serviceaccount   # No such file or directory
```
</details>

---

### Q23. Create a CRD from a specification
**Frequency:** ⚡ Medium · **Est. time:** 7 min · **Competency:** Discover and use resources that extend Kubernetes (CRD, Operators)

Create a namespaced CRD for kind `Backup` in group `ops.example.com`, version `v1`, plural `backups`, short name `bk`. `spec.schedule` (string) is required; `spec.retentionDays` is an integer of at least `1`. Then create Backup `db-nightly` in namespace `default` with schedule `0 1 * * *` and retention 7 days.

<details><summary>Solution</summary>

Copy the CronTab example from the CRD docs page and adapt it:

```yaml
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: backups.ops.example.com
spec:
  group: ops.example.com
  scope: Namespaced
  names:
    plural: backups
    singular: backup
    kind: Backup
    shortNames: ["bk"]
  versions:
  - name: v1
    served: true
    storage: true
    schema:
      openAPIV3Schema:
        type: object
        properties:
          spec:
            type: object
            required: ["schedule"]
            properties:
              schedule:
                type: string
              retentionDays:
                type: integer
                minimum: 1
---
apiVersion: ops.example.com/v1
kind: Backup
metadata:
  name: db-nightly
  namespace: default
spec:
  schedule: "0 1 * * *"
  retentionDays: 7
```

Apply the CRD first and wait, then the CR (in one file the CR can fail with "no matches for kind" on a fast apply):

```bash
kubectl apply -f q23.yaml
kubectl wait --for=condition=Established crd/backups.ops.example.com
kubectl apply -f q23.yaml                      # re-run creates the CR if it failed the first time
```

**Verify:**

```bash
kubectl api-resources --api-group=ops.example.com        # backups  bk  ops.example.com/v1  true  Backup
kubectl get bk db-nightly -o yaml | grep -A2 '^spec:'
kubectl patch bk db-nightly --type=merge -p '{"spec":{"retentionDays":0}}'   # rejected: should be >= 1
```
</details>

---

### Q24. TLS Secret from certificate files, mounted read-only
**Frequency:** ⚡ Medium · **Est. time:** 5 min · **Competency:** Create & consume Secrets

Lab setup (the exam would give you the files; `openssl` is not guaranteed on exam hosts):

```bash
mkdir -p /opt/course/24 && cd /opt/course/24
openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout tls.key -out tls.crt -subj "/CN=shop.example.com"
cd -
```

In namespace `ingress-demo` create TLS Secret `web-tls` from `/opt/course/24/tls.crt` and `/opt/course/24/tls.key`. Write its `type` to `/opt/course/24/type.txt`. Mount it into Pod `tls-pod` (image `nginx:1.27`) at `/etc/tls` with file mode `0400`.

<details><summary>Solution</summary>

```bash
kubectl create namespace ingress-demo
kubectl create secret tls web-tls -n ingress-demo --cert=/opt/course/24/tls.crt --key=/opt/course/24/tls.key
kubectl get secret web-tls -n ingress-demo -o jsonpath='{.type}' > /opt/course/24/type.txt
```

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: tls-pod
  namespace: ingress-demo
spec:
  containers:
  - name: nginx
    image: nginx:1.27
    volumeMounts:
    - name: tls
      mountPath: /etc/tls
      readOnly: true
  volumes:
  - name: tls
    secret:
      secretName: web-tls
      defaultMode: 0400
```

```bash
kubectl apply -f q24.yaml
```

**Verify:**

```bash
cat /opt/course/24/type.txt                                                     # kubernetes.io/tls
kubectl get secret web-tls -n ingress-demo -o jsonpath='{.data.tls\.crt}' | base64 -d | head -1   # -----BEGIN CERTIFICATE-----
kubectl exec -n ingress-demo tls-pod -- ls -lL /etc/tls                          # tls.crt, tls.key: -r--------
```
</details>

---

### Q25. Pod Security levels per namespace: enforce baseline, warn restricted
**Frequency:** ⚡ Medium · **Est. time:** 5 min · **Competency:** Understand authentication, authorization and admission control

Configure namespace `payments` so that Pods violating the **baseline** standard are rejected, and users get warnings (and audit entries) for anything violating **restricted**. Prove it: a privileged Pod must be rejected (save the error to `/opt/course/25/error.txt`); a plain `nginx:1.27` Pod must be admitted with a warning (save the warning to `/opt/course/25/warning.txt`).

<details><summary>Solution</summary>

```bash
kubectl create namespace payments
kubectl label namespace payments pod-security.kubernetes.io/enforce=baseline \
  pod-security.kubernetes.io/warn=restricted pod-security.kubernetes.io/audit=restricted
mkdir -p /opt/course/25
```

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: priv-pod
  namespace: payments
spec:
  containers:
  - name: app
    image: busybox:1.36
    command: ["sh", "-c", "sleep 3600"]
    securityContext:
      privileged: true
```

```bash
kubectl apply -f q25-priv.yaml 2> /opt/course/25/error.txt
kubectl run plain -n payments --image=nginx:1.27 2> /opt/course/25/warning.txt
```

**Verify:**

```bash
cat /opt/course/25/error.txt     # forbidden: violates PodSecurity "baseline:latest": privileged (container "app" ...)
cat /opt/course/25/warning.txt   # Warning: would violate PodSecurity "restricted:latest": allowPrivilegeEscalation != false ...
kubectl get pod plain -n payments            # Running (baseline allows it)
kubectl get ns payments --show-labels
```
</details>

---

### Q26. Downward API volume with labels and annotations
**Frequency:** 🧊 Low · **Est. time:** 5 min · **Competency:** Understand ConfigMaps (application environment / Downward API)

In namespace `meta` create Pod `labeller` (image `busybox:1.36`, `sleep 3600`, labels `app=labeller`, `tier=backend`, annotation `owner=team-x`) that exposes **all** its labels as `/etc/podinfo/labels` and all annotations as `/etc/podinfo/annotations`. Add the label `release=stable` afterwards and write the updated labels file to `/opt/course/26/labels.txt`.

<details><summary>Solution</summary>

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: labeller
  namespace: meta
  labels:
    app: labeller
    tier: backend
  annotations:
    owner: team-x
spec:
  containers:
  - name: labeller
    image: busybox:1.36
    command: ["sh", "-c", "sleep 3600"]
    volumeMounts:
    - name: podinfo
      mountPath: /etc/podinfo
  volumes:
  - name: podinfo
    downwardAPI:
      items:
      - path: labels
        fieldRef:
          fieldPath: metadata.labels
      - path: annotations
        fieldRef:
          fieldPath: metadata.annotations
```

```bash
kubectl create namespace meta 2>/dev/null || true
kubectl apply -f q26.yaml
kubectl label pod labeller -n meta release=stable
sleep 70        # the kubelet refreshes downwardAPI files periodically (about a minute)
mkdir -p /opt/course/26
kubectl exec -n meta labeller -- cat /etc/podinfo/labels > /opt/course/26/labels.txt
```

**Verify:**

```bash
cat /opt/course/26/labels.txt      # app="labeller"  release="stable"  tier="backend"
kubectl exec -n meta labeller -- cat /etc/podinfo/annotations   # owner="team-x" plus kubectl's last-applied-configuration (created with apply)
```
</details>

---

### Q27. Call the Kubernetes API from a Pod with its ServiceAccount token
**Frequency:** 🧊 Low · **Est. time:** 7 min · **Competency:** Understand ServiceAccounts

In namespace `api-demo` create ServiceAccount `cm-reader` with permission to `get` and `list` ConfigMaps (Role `cm-read`, RoleBinding `cm-read-binding`). Run Pod `api-check` (image `curlimages/curl:8.10.1`, command `sleep 3600`) as `cm-reader`. From inside the Pod, list the namespace's ConfigMaps through `https://kubernetes.default.svc` using the mounted token and CA, saving the response to `/opt/course/27/configmaps.json`; do the same for Secrets into `/opt/course/27/secrets.json`.

<details><summary>Solution</summary>

```bash
kubectl create namespace api-demo
kubectl create serviceaccount cm-reader -n api-demo
kubectl create role cm-read -n api-demo --verb=get,list --resource=configmaps
kubectl create rolebinding cm-read-binding -n api-demo --role=cm-read --serviceaccount=api-demo:cm-reader
```

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: api-check
  namespace: api-demo
spec:
  serviceAccountName: cm-reader
  containers:
  - name: curl
    image: curlimages/curl:8.10.1
    command: ["sleep", "3600"]
```

```bash
kubectl apply -f q27.yaml
mkdir -p /opt/course/27
kubectl exec -n api-demo api-check -- sh -c 'SA=/var/run/secrets/kubernetes.io/serviceaccount; curl -s --cacert $SA/ca.crt -H "Authorization: Bearer $(cat $SA/token)" https://kubernetes.default.svc/api/v1/namespaces/api-demo/configmaps' > /opt/course/27/configmaps.json
kubectl exec -n api-demo api-check -- sh -c 'SA=/var/run/secrets/kubernetes.io/serviceaccount; curl -s --cacert $SA/ca.crt -H "Authorization: Bearer $(cat $SA/token)" https://kubernetes.default.svc/api/v1/namespaces/api-demo/secrets' > /opt/course/27/secrets.json
```

The single quotes make `$SA` and `$(cat ...)` expand **inside** the container.

**Verify:**

```bash
grep -m1 '"kind"' /opt/course/27/configmaps.json     # "kind": "ConfigMapList"  (kube-root-ca.crt is always there)
grep -E '"(reason|code)"' /opt/course/27/secrets.json # "reason": "Forbidden", "code": 403
```
</details>

---

### Q28. Inspect and enable an admission plugin (kubeadm control plane)
**Frequency:** 🧊 Low · **Est. time:** 8 min · **Competency:** Understand authentication, authorization and admission control

Practise on a kubeadm-based lab (in kind: `docker exec -it <cluster>-control-plane bash`, where you are already root - drop `sudo`). On the control-plane node, write the current value of `--enable-admission-plugins` to `/opt/course/28/plugins.txt`. Then also enable `AlwaysPullImages` and prove that a new Pod created with `imagePullPolicy: IfNotPresent` ends up with `Always`. Restore the original configuration afterwards.

<details><summary>Solution</summary>

On the control-plane node:

```bash
mkdir -p /opt/course/28
sudo grep -- '--enable-admission-plugins' /etc/kubernetes/manifests/kube-apiserver.yaml \
  | sed 's/.*--enable-admission-plugins=//' > /opt/course/28/plugins.txt          # e.g. NodeRestriction
sudo cp /etc/kubernetes/manifests/kube-apiserver.yaml /root/kube-apiserver.yaml.bak   # backup OUTSIDE manifests/
sudo sed -i 's/--enable-admission-plugins=NodeRestriction$/--enable-admission-plugins=NodeRestriction,AlwaysPullImages/' \
  /etc/kubernetes/manifests/kube-apiserver.yaml      # or edit with vi; comma list, no spaces
sudo grep -- '--enable-admission-plugins' /etc/kubernetes/manifests/kube-apiserver.yaml   # check the edit
sudo crictl ps --name kube-apiserver               # wait until a new container is Running (30-90 s)
```

From your normal kubectl shell:

```bash
kubectl get --raw /readyz; echo                    # ok once the API server is back
kubectl run pull-test --image=nginx:1.27 --image-pull-policy=IfNotPresent
kubectl get pod pull-test -o jsonpath='{.spec.containers[0].imagePullPolicy}{"\n"}'   # Always
```

Restore on the node: `sudo cp /root/kube-apiserver.yaml.bak /etc/kubernetes/manifests/kube-apiserver.yaml`.

**Verify:**

```bash
cat /opt/course/28/plugins.txt
kubectl -n kube-system get pod -l component=kube-apiserver -o yaml | grep -- '--enable-admission-plugins'
```
</details>

---

### Q29. ValidatingAdmissionPolicy: cap replicas in test namespaces
**Frequency:** 🧊 Low · **Est. time:** 7 min · **Competency:** Understand authentication, authorization and admission control

Create a ValidatingAdmissionPolicy `max-3-replicas` that rejects Deployments (create and update) with more than 3 replicas, with the message `max 3 replicas in test namespaces`. Bind it (binding `max-3-replicas-binding`, action Deny) to namespaces labelled `env=test`. Label namespace `qa` with `env=test` and prove it works.

<details><summary>Solution</summary>

```yaml
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicy
metadata:
  name: max-3-replicas
spec:
  failurePolicy: Fail
  matchConstraints:
    resourceRules:
    - apiGroups: ["apps"]
      apiVersions: ["v1"]
      operations: ["CREATE", "UPDATE"]
      resources: ["deployments"]
  validations:
  - expression: "object.spec.replicas <= 3"
    message: "max 3 replicas in test namespaces"
---
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicyBinding
metadata:
  name: max-3-replicas-binding
spec:
  policyName: max-3-replicas
  validationActions: [Deny]
  matchResources:
    namespaceSelector:
      matchLabels:
        env: test
```

```bash
kubectl apply -f q29.yaml
kubectl create namespace qa
kubectl label namespace qa env=test
```

**Verify:**

```bash
kubectl create deployment big -n qa --image=nginx:1.27 --replicas=4      # denied: max 3 replicas in test namespaces
kubectl create deployment ok -n qa --image=nginx:1.27 --replicas=3       # created
kubectl patch deployment ok -n qa -p '{"spec":{"replicas":5}}'           # denied (UPDATE of the Deployment)
kubectl create deployment big -n default --image=nginx:1.27 --replicas=4 # allowed (namespace not labelled)
```

Caveat: `kubectl scale` (and the HPA) write the `deployments/scale` **subresource**, which `resources: ["deployments"]` does not match - `kubectl scale deployment ok -n qa --replicas=5` would succeed. Add `"deployments/scale"` to `resources` to cover it (the object is then an `autoscaling/v1` Scale, which also has `spec.replicas`).
</details>

---

### Q30. Immutable ConfigMap from a directory and immutable Secret from YAML
**Frequency:** 🧊 Low · **Est. time:** 6 min · **Competency:** Understand ConfigMaps

Lab setup:

```bash
mkdir -p /opt/course/30/release
echo -n '1.0' > /opt/course/30/release/VERSION
echo -n '2026-10-21' > /opt/course/30/release/DATE
```

In namespace `releases`: create an **immutable** ConfigMap `release-info-v1` from the directory `/opt/course/30/release` and an **immutable** Secret `release-signing` written in YAML with `stringData` key `key: sign-me-123`. Try to change `VERSION` in the ConfigMap to `1.1` and save the error to `/opt/course/30/error.txt`; then publish version `1.1` as a new immutable ConfigMap `release-info-v2` (same keys).

<details><summary>Solution</summary>

```bash
kubectl create namespace releases
kubectl create configmap release-info-v1 -n releases --from-file=/opt/course/30/release/ \
  --dry-run=client -o yaml > q30-cm.yaml
echo 'immutable: true' >> q30-cm.yaml          # top-level field; there is no --immutable flag
kubectl apply -f q30-cm.yaml
```

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: release-signing
  namespace: releases
type: Opaque
immutable: true
stringData:
  key: sign-me-123
```

```bash
kubectl apply -f q30-secret.yaml
mkdir -p /opt/course/30
kubectl patch configmap release-info-v1 -n releases --type=merge -p '{"data":{"VERSION":"1.1"}}' 2> /opt/course/30/error.txt
echo -n '1.1' > /opt/course/30/release/VERSION
kubectl create configmap release-info-v2 -n releases --from-file=/opt/course/30/release/ \
  --dry-run=client -o yaml > q30-cm2.yaml
echo 'immutable: true' >> q30-cm2.yaml
kubectl apply -f q30-cm2.yaml
```

**Verify:**

```bash
cat /opt/course/30/error.txt                     # ... data: Forbidden: field is immutable when `immutable` is set
kubectl get cm release-info-v2 -n releases -o jsonpath='{.data.VERSION} {.immutable}{"\n"}'   # 1.1 true
kubectl get secret release-signing -n releases -o jsonpath='{.data.key}' | base64 -d; echo     # sign-me-123
```
</details>

---

## Must-know summary

- Switch context first (`kubectl config use-context <ctx>`), and put `-n <ns>` on every command; most lost points are "right answer, wrong cluster/namespace".
- Secrets: `kubectl create secret generic|tls|docker-registry`; decode with `-o jsonpath='{.data.<key>}' | base64 -d` (escape dots: `tls\.crt`); encode with `echo -n`. `describe` never shows values.
- ConfigMaps/Secrets: `env.valueFrom.*KeyRef` (one key), `envFrom` (+ `prefix`), volumes (`configMap.name` vs `secret.secretName`), `items` to pick/rename keys, `subPath` for one file. Env vars and `subPath` files never update - `kubectl rollout restart`.
- Update existing ConfigMaps/Secrets with `kubectl create ... --dry-run=client -o yaml | kubectl apply -f -` or `kubectl patch`; immutable ones must be recreated.
- RBAC: Role + RoleBinding = one namespace; ClusterRole + RoleBinding = that ClusterRole in one namespace; ClusterRoleBinding = everywhere. `--serviceaccount=<ns>:<sa>` in bindings, `--as=system:serviceaccount:<ns>:<sa>` in `can-i`. `roleRef` is immutable.
- `kubectl auth can-i <verb> <resource> [--subresource=x] -n <ns> --as=...` and `--list` prove permissions; write their output to files when asked.
- "forbidden" in app logs: read the username in the error, `kubectl get rolebinding -o wide`, then `kubectl set serviceaccount deploy/<d> <sa>`.
- ServiceAccounts: `spec.serviceAccountName`; immutable on running Pods; Pod-level `automountServiceAccountToken` wins; `kubectl create token <sa> --duration=...`; long-lived token = annotated `kubernetes.io/service-account-token` Secret.
- securityContext placement: `fsGroup`/`supplementalGroups`/`sysctls` pod-only; `capabilities`/`privileged`/`allowPrivilegeEscalation`/`readOnlyRootFilesystem` container-only; container wins for shared fields. Capabilities without `CAP_`.
- Pod Security Admission: labels `pod-security.kubernetes.io/<enforce|warn|audit>=<privileged|baseline|restricted>`; enforce rejects Pods, not Deployments - read ReplicaSet `FailedCreate` events. Restricted needs runAsNonRoot, no privilege escalation, drop ALL, seccomp RuntimeDefault.
- Requests drive scheduling, limits drive throttling (CPU) and OOMKill (memory, exit 137). QoS: Guaranteed (requests == limits everywhere), Burstable, BestEffort. Memory in `Mi`/`Gi`.
- A compute ResourceQuota forces every new Pod to declare those resources (or get LimitRange defaults); quota/LimitRange apply only at admission of new Pods. Check `kubectl describe quota`.
- CRDs: `kubectl get crd`, `kubectl api-resources --api-group=<g>`, `kubectl explain <kind>.spec`, `kubectl get <plural>.<group>`; CR `apiVersion` = `<group>/<version>`; deleting a CRD deletes all its CRs.
- Downward API: `status.podIP`, `spec.nodeName`, `spec.serviceAccountName` only as env; whole `metadata.labels`/`annotations` only as volume files; `resourceFieldRef` + `divisor: 1m`/`1Mi`.
- Admission plugins live in `/etc/kubernetes/manifests/kube-apiserver.yaml` (`--enable-admission-plugins`); back up outside the manifests directory and wait for the static Pod to return.
