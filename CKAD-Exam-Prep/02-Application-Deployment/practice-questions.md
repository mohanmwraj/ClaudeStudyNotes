# Application Deployment: practice questions

These are exam-style tasks modelled on the official CNCF curriculum and on task patterns that candidates describe publicly. Real exam questions are confidential under the Linux Foundation candidate agreement; nothing here is a leaked question.

## Lab prerequisites

- A practice cluster with kubectl (see [../00-Exam-Overview-and-Setup/README.md](../00-Exam-Overview-and-Setup/README.md)) and the `helm` CLI (v3 or v4).
- Output directories: `sudo mkdir -p /opt/course && sudo chown "$USER" /opt/course && mkdir -p /opt/course/{1..27}`.
- A local chart for the Helm tasks, so they work offline:
  ```bash
  mkdir -p /opt/course/charts
  cp -r <kit>/02-Application-Deployment/yaml/helm/sample-chart/webapp /opt/course/charts/webapp   # or: helm create /opt/course/charts/webapp
  ```
  The tasks only use values that both charts have: `replicaCount`, `image.tag`, `service.type`.
- Q15 and Q16 need internet (public repo `https://helm.github.io/examples`, chart `hello-world`). Bitnami changed its free image catalog in 2025, so Bitnami chart images may fail to pull. Don't use them for practice.
- In the real exam, first switch to the context the task names. Here every task names its namespace instead.

## Index

| # | Task | Competency | Freq. |
|---|---|---|---|
| 1 | Rolling update + change-cause | Deployments / rolling updates | 🔥 |
| 2 | Roll back to a specific revision | Deployments / rolling updates | 🔥 |
| 3 | Helm install with values | Helm | 🔥 |
| 4 | Helm upgrade keeping existing values | Helm | 🔥 |
| 5 | Helm rollback after a bad upgrade | Helm | 🔥 |
| 6 | Find and remove failed/pending releases | Helm | 🔥 |
| 7 | Canary with an exact ratio | Deployment strategies | 🔥 |
| 8 | Blue/green switch | Deployment strategies | 🔥 |
| 9 | Rolling-update math + strategy tuning | Deployments / rolling updates | ⚡ |
| 10 | Switch to Recreate | Deployments / rolling updates | ⚡ |
| 11 | Pause, batch changes, resume | Deployments / rolling updates | ⚡ |
| 12 | Diagnose a failed rollout and undo it | Deployments / rolling updates | ⚡ |
| 13 | Helm show values + values file | Helm | ⚡ |
| 14 | Helm template to a file | Helm | ⚡ |
| 15 | Helm repo add / search / install a version | Helm | ⚡ |
| 16 | Helm pull --untar and install from a directory | Helm | ⚡ |
| 17 | Fix a stuck pending-upgrade release | Helm | ⚡ |
| 18 | Kustomize overlay (namespace, prefix, labels, replicas, image) | Kustomize | ⚡ |
| 19 | Kustomize configMapGenerator + hash rollout | Kustomize | ⚡ |
| 20 | Kustomize strategic-merge + JSON6902 patches | Kustomize | ⚡ |
| 21 | Kustomize images (newName/newTag/digest) | Kustomize | 🧊 |
| 22 | Promote a canary | Deployment strategies | 🧊 |
| 23 | Blue/green via Ingress backend | Deployment strategies | 🧊 |
| 24 | Restart to pick up a ConfigMap change | Deployments / rolling updates | 🧊 |
| 25 | Change an immutable selector | Deployments / rolling updates | 🧊 |
| 26 | Helm uninstall --keep-history and restore | Helm | 🧊 |
| 27 | StatefulSet partitioned rolling update | Deployments / rolling updates | 🧊 |

---

### Q1. Rolling update with change-cause
**Frequency:** 🔥 High · **Est. time:** 5 min · **Competency:** Understand Deployments and how to perform rolling updates

Namespace `deploy-lab` has Deployment `api` (4 replicas, image `nginx:1.27`). Update it to image `nginx:1.27-alpine`. `kubectl rollout history` must show the change-cause `upgrade to nginx:1.27-alpine` for the new revision. Wait until the rollout has completed, then write the Deployment's current revision number to `/opt/course/1/revision.txt`.

Lab setup:
```bash
kubectl create namespace deploy-lab
kubectl -n deploy-lab create deployment api --image=nginx:1.27 --replicas=4
kubectl -n deploy-lab annotate deployment api kubernetes.io/change-cause="initial release nginx:1.27"
```

<details><summary>Solution</summary>

```bash
kubectl -n deploy-lab get deploy api -o jsonpath='{.spec.template.spec.containers[*].name}{"\n"}'   # container name: nginx
kubectl -n deploy-lab set image deployment/api nginx=nginx:1.27-alpine
kubectl -n deploy-lab annotate deployment/api kubernetes.io/change-cause="upgrade to nginx:1.27-alpine" --overwrite
kubectl -n deploy-lab rollout status deployment/api
kubectl -n deploy-lab get deploy api -o jsonpath='{.metadata.annotations.deployment\.kubernetes\.io/revision}' > /opt/course/1/revision.txt
```

Annotate *after* the change, with `--overwrite`. Annotating first would relabel revision 1.

**Verify:**
```bash
kubectl -n deploy-lab rollout history deployment/api        # 1 initial release..., 2 upgrade to nginx:1.27-alpine
cat /opt/course/1/revision.txt                              # 2
kubectl -n deploy-lab get deploy api -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'   # nginx:1.27-alpine
```
</details>

### Q2. Roll back to a specific revision
**Frequency:** 🔥 High · **Est. time:** 6 min · **Competency:** Understand Deployments and how to perform rolling updates

Deployment `web` in namespace `deploy-lab` has three revisions. Roll it back to the revision that ran image `httpd:2.4`. Write that revision's number (as it was before the rollback) to `/opt/course/2/source-revision.txt`, and the Deployment's current revision number after the rollback to `/opt/course/2/current-revision.txt`.

Lab setup:
```bash
kubectl create namespace deploy-lab 2>/dev/null || true
kubectl -n deploy-lab create deployment web --image=nginx:1.27 --replicas=2
kubectl -n deploy-lab rollout status deployment/web
kubectl -n deploy-lab set image deployment/web nginx=httpd:2.4 && kubectl -n deploy-lab rollout status deployment/web
kubectl -n deploy-lab set image deployment/web nginx=nginx:1.27-alpine && kubectl -n deploy-lab rollout status deployment/web
```

<details><summary>Solution</summary>

```bash
kubectl -n deploy-lab rollout history deployment/web
for r in 1 2 3; do echo "rev $r: $(kubectl -n deploy-lab rollout history deployment/web --revision=$r | grep -i 'image:')"; done
echo 2 > /opt/course/2/source-revision.txt                 # the revision that showed Image: httpd:2.4
kubectl -n deploy-lab rollout undo deployment/web --to-revision=2
kubectl -n deploy-lab rollout status deployment/web
kubectl -n deploy-lab get deploy web -o jsonpath='{.metadata.annotations.deployment\.kubernetes\.io/revision}' > /opt/course/2/current-revision.txt
```

The rollback copies revision 2's template into a **new** revision (4). Revision 2 disappears from the list.

**Verify:**
```bash
kubectl -n deploy-lab rollout history deployment/web       # 1, 3, 4
cat /opt/course/2/current-revision.txt                     # 4
kubectl -n deploy-lab get deploy web -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'   # httpd:2.4
```
</details>

### Q3. Helm: install a chart with values
**Frequency:** 🔥 High · **Est. time:** 4 min · **Competency:** Use the Helm package manager to deploy existing packages

Install the chart at `/opt/course/charts/webapp` as release `shop` into namespace `helm-a` (create the namespace). The release must run **2** replicas and expose a Service of type **NodePort**. Save the output of `helm list` for that namespace to `/opt/course/3/releases.txt`.

<details><summary>Solution</summary>

```bash
helm show values /opt/course/charts/webapp | grep -E -A2 '^(replicaCount|service):'   # confirm the value names
helm install shop /opt/course/charts/webapp -n helm-a --create-namespace \
  --set replicaCount=2 --set service.type=NodePort
helm list -n helm-a > /opt/course/3/releases.txt
```

**Verify:**
```bash
helm get values shop -n helm-a                   # replicaCount: 2, service.type: NodePort
kubectl -n helm-a get deploy,svc                 # 2/2 Ready, TYPE NodePort
cat /opt/course/3/releases.txt                   # shop  helm-a  1  ...  deployed  webapp-0.1.0 ...
```
</details>

### Q4. Helm: upgrade with one more value, keep the rest
**Frequency:** 🔥 High · **Est. time:** 4 min · **Competency:** Use the Helm package manager to deploy existing packages

Release `shop` in namespace `helm-a` (from Q3) was installed with custom values. Upgrade it so the image tag becomes `1.27-alpine`, keeping all previously set values and the same chart. Write the release's user-supplied values after the upgrade to `/opt/course/4/values.yaml`.

<details><summary>Solution</summary>

```bash
helm get values shop -n helm-a                              # replicaCount 2, service.type NodePort
helm upgrade shop /opt/course/charts/webapp -n helm-a --reuse-values --set image.tag=1.27-alpine
helm get values shop -n helm-a -o yaml > /opt/course/4/values.yaml
```

Without `--reuse-values` the upgrade would keep only `image.tag`, and replicaCount/service.type would fall back to the chart defaults. With a repo chart, also pin `--version <current chart version>` so you don't upgrade the chart by accident.

**Verify:**
```bash
cat /opt/course/4/values.yaml                               # image.tag, replicaCount, service.type
helm history shop -n helm-a                                 # revision 2 deployed, "Upgrade complete"
kubectl -n helm-a get deploy -o jsonpath='{..containers[0].image}{"\n"}'   # nginx:1.27-alpine
```
</details>

### Q5. Helm: roll back a bad upgrade
**Frequency:** 🔥 High · **Est. time:** 4 min · **Competency:** Use the Helm package manager to deploy existing packages

The latest upgrade of release `shop` in `helm-a` broke the Pods. Roll back to the last revision that worked. Write the revision number that is deployed afterwards to `/opt/course/5/revision.txt`.

Lab setup:
```bash
helm upgrade shop /opt/course/charts/webapp -n helm-a --reuse-values --set image.tag=does-not-exist   # revision 3, ImagePullBackOff
```

<details><summary>Solution</summary>

```bash
helm history shop -n helm-a                         # rev 2 = last good (1.27-alpine), rev 3 = broken
kubectl -n helm-a get pods                          # ErrImagePull / ImagePullBackOff
helm rollback shop 2 -n helm-a                      # creates revision 4 = copy of revision 2
helm status shop -n helm-a | awk '/^REVISION:/{print $2}' > /opt/course/5/revision.txt
```

**Verify:**
```bash
helm history shop -n helm-a | tail -2               # 4 deployed ... Rollback to 2
cat /opt/course/5/revision.txt                      # 4
kubectl -n helm-a rollout status deployment -l app.kubernetes.io/instance=shop 2>/dev/null || kubectl -n helm-a get pods
```
</details>

### Q6. Helm: find and remove broken releases
**Frequency:** 🔥 High · **Est. time:** 6 min · **Competency:** Use the Helm package manager to deploy existing packages

Find every Helm release in the cluster whose status is `failed` or `pending-*`. Write them, one per line as `<namespace>/<release>`, to `/opt/course/6/broken.txt`, then uninstall them. Deployed releases must stay.

Lab setup:
```bash
helm install healthy /opt/course/charts/webapp -n helm-b --create-namespace
helm install broken /opt/course/charts/webapp -n helm-c --create-namespace --set image.tag=does-not-exist --wait --timeout 30s   # -> failed
helm install halfway /opt/course/charts/webapp -n helm-d --create-namespace
helm upgrade halfway /opt/course/charts/webapp -n helm-d --set image.tag=nope --wait --timeout 5m &
sleep 5; kill -9 $!                                   # client killed mid-upgrade -> pending-upgrade
```

<details><summary>Solution</summary>

```bash
helm list -A --failed --pending                       # state flags are ORed. Helm 3 hides these by default
helm list -A --failed --pending --no-headers | awk '{print $2"/"$1}' > /opt/course/6/broken.txt
cat /opt/course/6/broken.txt                          # helm-c/broken  helm-d/halfway
helm uninstall broken -n helm-c
helm uninstall halfway -n helm-d
```

`helm list -A -a` (Helm 3) or plain `helm list -A` (Helm 4) shows every status at once.

**Verify:**
```bash
helm list -A --failed --pending                       # empty
helm list -A                                          # healthy (and shop) still deployed
```
</details>

### Q7. Canary with an exact ratio
**Frequency:** 🔥 High · **Est. time:** 7 min · **Competency:** Use Kubernetes primitives to implement common deployment strategies (e.g. blue/green or canary)

Namespace `canary-lab` runs Deployment `frontend` (10 replicas, `nginx:1.27`) behind Service `frontend`. Create a Deployment `frontend-canary` running `nginx:1.27-alpine` so that about **20%** of the Service's traffic reaches the canary, while the **total** number of Pods behind the Service stays **10**. Don't modify the Service.

Lab setup:
```bash
kubectl create namespace canary-lab
kubectl -n canary-lab create deployment frontend --image=nginx:1.27 --replicas=10
kubectl -n canary-lab expose deployment frontend --port=80
```

<details><summary>Solution</summary>

```bash
kubectl -n canary-lab get svc frontend -o jsonpath='{.spec.selector}{"\n"}'     # {"app":"frontend"}
kubectl -n canary-lab scale deployment frontend --replicas=8                     # 8 + 2 = 10, 2/10 = 20%
```

```yaml
# canary.yaml - kubectl -n canary-lab apply -f canary.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend-canary
spec:
  replicas: 2
  selector:
    matchLabels:
      app: frontend          # shared with the Service selector
      track: canary          # keeps this selector distinct from anything else
  template:
    metadata:
      labels:
        app: frontend
        track: canary
    spec:
      containers:
      - name: nginx
        image: nginx:1.27-alpine
        ports:
        - containerPort: 80
```

`frontend`'s selector (`app=frontend`) is immutable, so leave it alone. Each ReplicaSet owns only Pods with its own `pod-template-hash`, so nothing is stolen.

**Verify:**
```bash
kubectl -n canary-lab get pods -l app=frontend -L track                       # 8 without track + 2 canary
kubectl -n canary-lab get endpointslices -l kubernetes.io/service-name=frontend \
  -o jsonpath='{range .items[*].endpoints[*]}{.addresses[0]}{"\n"}{end}' | wc -l   # 10
```
</details>

### Q8. Blue/green switch
**Frequency:** 🔥 High · **Est. time:** 6 min · **Competency:** Use Kubernetes primitives to implement common deployment strategies (e.g. blue/green or canary)

Namespace `bg-lab` runs Deployment `store-blue` behind Service `store`. Create Deployment `store-green` (3 replicas, image `nginx:1.27-alpine`, labels `app=store`, `version=green`). When all green Pods are Ready, switch Service `store` to the green Pods. `store-blue` must keep running for a possible rollback. Save the Service's selector (JSON) to `/opt/course/8/selector.json`.

Lab setup (`kubectl create namespace bg-lab && kubectl -n bg-lab apply -f blue.yaml`):
```yaml
# blue.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: store-blue
spec:
  replicas: 3
  selector:
    matchLabels:
      app: store
      version: blue
  template:
    metadata:
      labels:
        app: store
        version: blue
    spec:
      containers:
      - name: store
        image: nginx:1.27
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: store
spec:
  selector:
    app: store
    version: blue
  ports:
  - name: http
    port: 80
    targetPort: 80
```

<details><summary>Solution</summary>

```yaml
# green.yaml - kubectl -n bg-lab apply -f green.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: store-green
spec:
  replicas: 3
  selector:
    matchLabels:
      app: store
      version: green
  template:
    metadata:
      labels:
        app: store
        version: green
    spec:
      containers:
      - name: store
        image: nginx:1.27-alpine
        ports:
        - containerPort: 80
```

```bash
kubectl -n bg-lab rollout status deployment/store-green                          # all green Ready first
kubectl -n bg-lab patch service store -p '{"spec":{"selector":{"app":"store","version":"green"}}}'
kubectl -n bg-lab get svc store -o jsonpath='{.spec.selector}' > /opt/course/8/selector.json
```

**Verify:**
```bash
cat /opt/course/8/selector.json                                                  # {"app":"store","version":"green"}
kubectl -n bg-lab get endpointslices -l kubernetes.io/service-name=store -o wide # green Pod IPs
kubectl -n bg-lab get pods -l app=store -L version -o wide                       # compare IPs; blue still Running
```
</details>

### Q9. Rolling-update math and strategy tuning
**Frequency:** ⚡ Medium · **Est. time:** 6 min · **Competency:** Understand Deployments and how to perform rolling updates

a) Write to `/opt/course/9/default-bounds.txt`, as `max=<n> min=<n>`, the maximum total Pods and the minimum available Pods during a rolling update of a **10-replica** Deployment with the **default** strategy.
b) Configure Deployment `batch-api` in `deploy-lab` (10 replicas) so that during an update **at most 12** Pods exist and **at least 9** are available.
c) Update `batch-api` to `nginx:1.27-alpine` and wait until it completes.

Lab setup:
```bash
kubectl -n deploy-lab create deployment batch-api --image=nginx:1.27 --replicas=10
```

<details><summary>Solution</summary>

```bash
# a) maxSurge 25% -> ceil(2.5)=3 -> 13 ; maxUnavailable 25% -> floor(2.5)=2 -> 8
echo "max=13 min=8" > /opt/course/9/default-bounds.txt

# b) 12 = 10 + maxSurge -> 2 ; 9 = 10 - maxUnavailable -> 1
kubectl -n deploy-lab patch deployment batch-api \
  -p '{"spec":{"strategy":{"type":"RollingUpdate","rollingUpdate":{"maxSurge":2,"maxUnavailable":1}}}}'

# c)
kubectl -n deploy-lab set image deployment/batch-api nginx=nginx:1.27-alpine
kubectl -n deploy-lab rollout status deployment/batch-api
```

Percentages work too: `maxSurge: 20%` (ceil 2) and `maxUnavailable: 10%` (floor 1).

**Verify:**
```bash
kubectl -n deploy-lab get deploy batch-api -o jsonpath='{.spec.strategy.rollingUpdate}{"\n"}'   # {"maxSurge":2,"maxUnavailable":1}
kubectl -n deploy-lab get deploy batch-api -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
```
</details>

### Q10. Switch a Deployment to Recreate
**Frequency:** ⚡ Medium · **Est. time:** 4 min · **Competency:** Understand Deployments and how to perform rolling updates

Deployment `legacy` in `deploy-lab` must never run old and new Pods at the same time: all old Pods must be terminated before new ones start. Configure that, then update its image to `nginx:1.27-alpine`.

Lab setup:
```bash
kubectl -n deploy-lab create deployment legacy --image=nginx:1.27 --replicas=3
```

<details><summary>Solution</summary>

```bash
kubectl -n deploy-lab patch deployment legacy -p '{"spec":{"strategy":{"type":"Recreate","rollingUpdate":null}}}'
kubectl -n deploy-lab set image deployment/legacy nginx=nginx:1.27-alpine
kubectl -n deploy-lab get pods -l app=legacy -w          # all Terminating first, then new Pods (Ctrl-C)
kubectl -n deploy-lab rollout status deployment/legacy
```

In `kubectl edit`, set `type: Recreate` **and delete** the `rollingUpdate:` block, or the API rejects the change.

**Verify:**
```bash
kubectl -n deploy-lab get deploy legacy -o jsonpath='{.spec.strategy}{"\n"}'     # {"type":"Recreate"}
```
</details>

### Q11. Pause, batch several changes, resume
**Frequency:** ⚡ Medium · **Est. time:** 5 min · **Competency:** Understand Deployments and how to perform rolling updates

Apply all of these changes to Deployment `orders` in `deploy-lab` so that together they create **exactly one** new revision: image `nginx:1.27`, env var `MODE=prod`, memory limit `128Mi` on the container. Write the number of revisions listed by `kubectl rollout history` afterwards to `/opt/course/11/count.txt`.

Lab setup:
```bash
kubectl -n deploy-lab create deployment orders --image=nginx:1.27-alpine --replicas=3
kubectl -n deploy-lab rollout status deployment/orders
```

<details><summary>Solution</summary>

```bash
kubectl -n deploy-lab rollout pause deployment/orders
kubectl -n deploy-lab set image deployment/orders nginx=nginx:1.27
kubectl -n deploy-lab set env deployment/orders MODE=prod
kubectl -n deploy-lab set resources deployment/orders -c nginx --limits=memory=128Mi
kubectl -n deploy-lab rollout resume deployment/orders
kubectl -n deploy-lab rollout status deployment/orders
kubectl -n deploy-lab rollout history deployment/orders | grep -c '^[0-9]' > /opt/course/11/count.txt
```

**Verify:**
```bash
cat /opt/course/11/count.txt                                       # 2
kubectl -n deploy-lab rollout history deployment/orders --revision=2   # image nginx:1.27, MODE=prod, limits memory 128Mi
```
</details>

### Q12. Diagnose a failed rollout and undo it
**Frequency:** ⚡ Medium · **Est. time:** 6 min · **Competency:** Understand Deployments and how to perform rolling updates

The latest rollout of Deployment `checkout` in `deploy-lab` doesn't finish. Write the `reason` of the Deployment's `Progressing` condition to `/opt/course/12/reason.txt`, and the waiting reason of one of the new Pods' containers to `/opt/course/12/pod-reason.txt`. Then restore service: all 3 replicas must run the previous image.

Lab setup:
```bash
kubectl -n deploy-lab create deployment checkout --image=nginx:1.27 --replicas=3
kubectl -n deploy-lab patch deployment checkout -p '{"spec":{"progressDeadlineSeconds":30}}'
kubectl -n deploy-lab rollout status deployment/checkout
kubectl -n deploy-lab set image deployment/checkout nginx=nginx:1.27-broken
sleep 45                                                     # let the progress deadline expire
```

<details><summary>Solution</summary>

```bash
kubectl -n deploy-lab rollout status deployment/checkout --timeout=10s; echo "exit=$?"   # non-zero
kubectl -n deploy-lab get deploy checkout \
  -o jsonpath='{.status.conditions[?(@.type=="Progressing")].reason}' > /opt/course/12/reason.txt
kubectl -n deploy-lab get pods -l app=checkout \
  -o jsonpath='{range .items[*]}{.status.containerStatuses[0].state.waiting.reason}{"\n"}{end}' | grep . | head -1 > /opt/course/12/pod-reason.txt
kubectl -n deploy-lab rollout undo deployment/checkout
kubectl -n deploy-lab rollout status deployment/checkout
```

**Verify:**
```bash
cat /opt/course/12/reason.txt                    # ProgressDeadlineExceeded
cat /opt/course/12/pod-reason.txt                # ImagePullBackOff (or ErrImagePull)
kubectl -n deploy-lab get deploy checkout        # 3/3, image nginx:1.27
```
</details>

### Q13. Helm: export default values and install with a values file
**Frequency:** ⚡ Medium · **Est. time:** 5 min · **Competency:** Use the Helm package manager to deploy existing packages

Write the default values of chart `/opt/course/charts/webapp` to `/opt/course/13/defaults.yaml`. Create `/opt/course/13/custom.yaml` that sets `replicaCount` to 3 and `service.type` to `NodePort`. Install the chart as release `catalog` in namespace `helm-f`, using only that file for overrides.

<details><summary>Solution</summary>

```bash
helm show values /opt/course/charts/webapp > /opt/course/13/defaults.yaml
cat > /opt/course/13/custom.yaml <<'EOF'
replicaCount: 3
service:
  type: NodePort
EOF
helm install catalog /opt/course/charts/webapp -n helm-f --create-namespace -f /opt/course/13/custom.yaml
```

**Verify:**
```bash
helm get values catalog -n helm-f                # exactly the two overrides
kubectl -n helm-f get deploy,svc                 # 3/3, NodePort
```
</details>

### Q14. Helm: render templates to a file
**Frequency:** ⚡ Medium · **Est. time:** 3 min · **Competency:** Use the Helm package manager to deploy existing packages

Without installing anything in the cluster, render chart `/opt/course/charts/webapp` as release `preview` for namespace `helm-g` with 5 replicas. Save the manifests to `/opt/course/14/manifest.yaml`.

<details><summary>Solution</summary>

```bash
helm template preview /opt/course/charts/webapp -n helm-g --set replicaCount=5 > /opt/course/14/manifest.yaml
```

**Verify:**
```bash
grep -E 'kind:|replicas:' /opt/course/14/manifest.yaml     # Deployment ... replicas: 5
helm list -A | grep preview || echo "not installed (correct)"
```
</details>

### Q15. Helm: add a repo, list versions, install a specific version
**Frequency:** ⚡ Medium · **Est. time:** 5 min · **Competency:** Use the Helm package manager to deploy existing packages

Add the chart repository `https://helm.github.io/examples` under the name `examples` and refresh it. Write every available version of chart `hello-world` to `/opt/course/15/versions.txt`. Install chart version `0.1.0` as release `hello` in namespace `helm-h` with 2 replicas. (Needs internet.)

<details><summary>Solution</summary>

```bash
helm repo add examples https://helm.github.io/examples
helm repo update
helm search repo examples/hello-world --versions > /opt/course/15/versions.txt
helm show values examples/hello-world --version 0.1.0 | grep replicaCount
helm install hello examples/hello-world --version 0.1.0 -n helm-h --create-namespace --set replicaCount=2
```

**Verify:**
```bash
cat /opt/course/15/versions.txt                  # examples/hello-world  0.1.0  1.16.0  ...
helm list -n helm-h                              # CHART hello-world-0.1.0, APP VERSION 1.16.0
kubectl -n helm-h get pods                       # 2 Pods running nginx:1.16.0
```
</details>

### Q16. Helm: pull, unpack, modify, install from a directory
**Frequency:** ⚡ Medium · **Est. time:** 5 min · **Competency:** Use the Helm package manager to deploy existing packages

Download chart `examples/hello-world` version `0.1.0` and unpack it so that `/opt/course/16/hello-world/Chart.yaml` exists. In the unpacked chart, change the default `replicaCount` to 2. Install it from that directory as release `hello-local` in namespace `helm-i`. (Needs the repo from Q15.)

<details><summary>Solution</summary>

```bash
helm pull examples/hello-world --version 0.1.0 --untar --untardir /opt/course/16
sed -i 's/^replicaCount: 1$/replicaCount: 2/' /opt/course/16/hello-world/values.yaml
grep '^replicaCount' /opt/course/16/hello-world/values.yaml        # replicaCount: 2
helm install hello-local /opt/course/16/hello-world -n helm-i --create-namespace
```

**Verify:**
```bash
ls /opt/course/16/hello-world/Chart.yaml
kubectl -n helm-i get deploy                    # 2/2
helm get values hello-local -n helm-i           # USER-SUPPLIED VALUES: null (the change is in the chart itself)
```
</details>

### Q17. Helm: fix a release stuck in pending-upgrade
**Frequency:** ⚡ Medium · **Est. time:** 5 min · **Competency:** Use the Helm package manager to deploy existing packages

Every upgrade of release `billing` in namespace `helm-j` now fails with `another operation (install/upgrade/rollback) is in progress`. Bring the release back to a deployed state with its last good configuration, **without uninstalling** it. Write the final revision number to `/opt/course/17/revision.txt`.

Lab setup:
```bash
helm install billing /opt/course/charts/webapp -n helm-j --create-namespace
helm upgrade billing /opt/course/charts/webapp -n helm-j --set image.tag=does-not-exist --wait --timeout 5m &
sleep 5; kill -9 $!                                         # leaves revision 2 in pending-upgrade
```

<details><summary>Solution</summary>

```bash
helm history billing -n helm-j          # 1 superseded/deployed ... 2 pending-upgrade "Preparing upgrade"
helm rollback billing 1 -n helm-j       # rollback is allowed while pending -> revision 3
helm history billing -n helm-j          # 3 deployed "Rollback to 1"
helm status billing -n helm-j | awk '/^REVISION:/{print $2}' > /opt/course/17/revision.txt
```

If the stuck revision were a `pending-install` (revision 1), there would be nothing to roll back to. Uninstall and reinstall in that case. The last resort is to delete the stuck revision's Secret (`kubectl -n helm-j delete secret sh.helm.release.v1.billing.v2`).

**Verify:**
```bash
cat /opt/course/17/revision.txt                                       # 3
helm upgrade billing /opt/course/charts/webapp -n helm-j --reuse-values --dry-run=client >/dev/null && echo "upgrades work again"
kubectl -n helm-j get pods                                            # Running, good image
```
</details>

### Q18. Kustomize: create an overlay
**Frequency:** ⚡ Medium · **Est. time:** 7 min · **Competency:** Kustomize

A base exists at `/opt/course/18/base` (Deployment `web`, Service `web`). Create the overlay `/opt/course/18/overlays/staging`. It must:

- put every object into namespace `staging`, and the overlay itself must create that namespace
- prefix every name with `stg-`
- add label `env=staging` to every object without changing any selector
- run 3 replicas of `web`
- use image `nginx:1.27-alpine`

Save the rendered output to `/opt/course/18/rendered.yaml`, then apply the overlay.

Lab setup:
```bash
mkdir -p /opt/course/18 && cp -r <kit>/02-Application-Deployment/yaml/kustomize/base /opt/course/18/base
```

<details><summary>Solution</summary>

```bash
mkdir -p /opt/course/18/overlays/staging && cd /opt/course/18/overlays/staging
cat > namespace.yaml <<'EOF'
apiVersion: v1
kind: Namespace
metadata:
  name: staging
EOF
cat > kustomization.yaml <<'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- ../../base
- namespace.yaml
namespace: staging
namePrefix: stg-
labels:
- pairs:
    env: staging
  includeSelectors: false
replicas:
- name: web
  count: 3
images:
- name: nginx
  newTag: "1.27-alpine"
EOF
kubectl kustomize /opt/course/18/overlays/staging > /opt/course/18/rendered.yaml
kubectl apply -k /opt/course/18/overlays/staging
```

**Verify:**
```bash
grep -E '^  name:|namespace:|image:|replicas:' /opt/course/18/rendered.yaml
kubectl -n staging get deploy stg-web -o jsonpath='{.spec.replicas} {.spec.template.spec.containers[0].image} {.spec.selector.matchLabels}{"\n"}'
# 3 nginx:1.27-alpine {"app":"web"}   <- selector unchanged
kubectl -n staging get all,cm --show-labels | grep env=staging
```
</details>

### Q19. Kustomize: generator hash triggers a rollout
**Frequency:** ⚡ Medium · **Est. time:** 6 min · **Competency:** Kustomize

In `/opt/course/19`, create a kustomization for namespace `kz-gen` containing:

- Deployment `reader` (image `busybox:1.36`) that prints `mode=$MODE` every 5 seconds and takes `MODE` from ConfigMap `reader-config` via `envFrom`
- a `configMapGenerator` named `reader-config` with `MODE=blue`

Apply it. Then change `MODE` to `green` and apply again. The Pods must restart automatically. Write both generated ConfigMap names to `/opt/course/19/configmaps.txt`.

<details><summary>Solution</summary>

```yaml
# /opt/course/19/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: reader
spec:
  replicas: 1
  selector:
    matchLabels:
      app: reader
  template:
    metadata:
      labels:
        app: reader
    spec:
      containers:
      - name: reader
        image: busybox:1.36
        command: ["sh", "-c", "while true; do echo mode=$MODE; sleep 5; done"]
        envFrom:
        - configMapRef:
            name: reader-config      # rewritten to reader-config-<hash>
```

```bash
cat > /opt/course/19/kustomization.yaml <<'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: kz-gen
resources:
- deployment.yaml
configMapGenerator:
- name: reader-config
  literals:
  - MODE=blue
EOF
kubectl create namespace kz-gen
kubectl apply -k /opt/course/19
sed -i 's/MODE=blue/MODE=green/' /opt/course/19/kustomization.yaml
kubectl apply -k /opt/course/19                        # new ConfigMap name -> Pod template changed -> rollout
kubectl -n kz-gen rollout status deployment/reader
kubectl -n kz-gen get cm -o name | grep reader-config > /opt/course/19/configmaps.txt
```

**Verify:**
```bash
cat /opt/course/19/configmaps.txt                      # configmap/reader-config-<hash1>, configmap/reader-config-<hash2>
kubectl -n kz-gen logs deploy/reader --tail=1          # mode=green
kubectl -n kz-gen rollout history deployment/reader    # 2 revisions
```
</details>

### Q20. Kustomize: strategic-merge and JSON6902 patches
**Frequency:** ⚡ Medium · **Est. time:** 7 min · **Competency:** Kustomize

Using the base at `/opt/course/20/base` (a copy of the kit base: Deployment `web`, container `web`), create the overlay `/opt/course/20/overlays/prod` with:

- a strategic-merge patch file `patch-memory.yaml` that sets container `web`'s memory limit to `256Mi`
- an inline JSON6902 patch that sets `spec.strategy.rollingUpdate.maxUnavailable` to `0` and appends env var `TIER=prod` to the first container

Render the result to `/opt/course/20/prod.yaml`. Don't apply it.

Lab setup:
```bash
mkdir -p /opt/course/20 && cp -r <kit>/02-Application-Deployment/yaml/kustomize/base /opt/course/20/base
```

<details><summary>Solution</summary>

```bash
mkdir -p /opt/course/20/overlays/prod && cd /opt/course/20/overlays/prod
cat > patch-memory.yaml <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web
spec:
  template:
    spec:
      containers:
      - name: web
        resources:
          limits:
            memory: 256Mi
EOF
cat > kustomization.yaml <<'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- ../../base
patches:
- path: patch-memory.yaml
- target:
    group: apps
    version: v1
    kind: Deployment
    name: web
  patch: |-
    - op: replace
      path: /spec/strategy/rollingUpdate/maxUnavailable
      value: 0
    - op: add
      path: /spec/template/spec/containers/0/env/-
      value:
        name: TIER
        value: prod
EOF
kubectl kustomize /opt/course/20/overlays/prod > /opt/course/20/prod.yaml
```

**Verify:**
```bash
grep -A2 'limits:' /opt/course/20/prod.yaml          # memory: 256Mi
grep 'maxUnavailable' /opt/course/20/prod.yaml       # maxUnavailable: 0
grep -A1 'name: TIER' /opt/course/20/prod.yaml       # value: prod
```
</details>

### Q21. Kustomize: change images without patches
**Frequency:** 🧊 Low · **Est. time:** 4 min · **Competency:** Kustomize

In the overlay `/opt/course/21/overlay` (resources: `../base`, a copy of the kit base), make every container that uses image `nginx` use `docker.io/library/nginx` with tag `1.27-alpine`. Change only `kustomization.yaml`. Render to `/opt/course/21/out.yaml`. Bonus: show how to pin by digest instead.

Lab setup:
```bash
mkdir -p /opt/course/21/overlay && cp -r <kit>/02-Application-Deployment/yaml/kustomize/base /opt/course/21/base
printf 'apiVersion: kustomize.config.k8s.io/v1beta1\nkind: Kustomization\nresources:\n- ../base\n' > /opt/course/21/overlay/kustomization.yaml
```

<details><summary>Solution</summary>

```bash
cat >> /opt/course/21/overlay/kustomization.yaml <<'EOF'
images:
- name: nginx
  newName: docker.io/library/nginx
  newTag: "1.27-alpine"
EOF
kubectl kustomize /opt/course/21/overlay > /opt/course/21/out.yaml
# Same with the standalone binary (if installed):   cd /opt/course/21/overlay && kustomize edit set image nginx=docker.io/library/nginx:1.27-alpine
# Digest variant (replaces the tag):               images: [{name: nginx, digest: "sha256:<64-hex-digest>"}]
```

**Verify:**
```bash
grep 'image:' /opt/course/21/out.yaml                # image: docker.io/library/nginx:1.27-alpine
```
</details>

### Q22. Promote a canary
**Frequency:** 🧊 Low · **Est. time:** 5 min · **Competency:** Use Kubernetes primitives to implement common deployment strategies (e.g. blue/green or canary)

The canary from Q7 (`frontend-canary` in `canary-lab`) is healthy. Promote it: Deployment `frontend` must run `nginx:1.27-alpine` with 10 replicas, and `frontend-canary` must be removed. At least 8 Pods must serve the Service throughout.

<details><summary>Solution</summary>

```bash
kubectl -n canary-lab scale deployment frontend --replicas=10        # capacity first (10 + 2 canary)
kubectl -n canary-lab set image deployment/frontend nginx=nginx:1.27-alpine
kubectl -n canary-lab annotate deployment/frontend kubernetes.io/change-cause="promote canary nginx:1.27-alpine" --overwrite
kubectl -n canary-lab rollout status deployment/frontend              # default 25%: >= 8 frontend Pods available at any time
kubectl -n canary-lab delete deployment frontend-canary
```

**Verify:**
```bash
kubectl -n canary-lab get deploy                                      # only frontend 10/10
kubectl -n canary-lab get deploy frontend -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'   # nginx:1.27-alpine
kubectl -n canary-lab get endpointslices -l kubernetes.io/service-name=frontend -o wide
```
</details>

### Q23. Blue/green via the Ingress backend
**Frequency:** 🧊 Low · **Est. time:** 5 min · **Competency:** Use Kubernetes primitives to implement common deployment strategies (e.g. blue/green or canary)

In namespace `bg-ingress`, Ingress `shop` sends traffic to Service `shop-blue`. Switch it to Service `shop-green`, verify, then roll back to blue. Write the Ingress's backend Service name after the rollback to `/opt/course/23/backend.txt`.

Lab setup (uses the kit files; the Ingress object works without a controller, but traffic tests need one):
```bash
kubectl create namespace bg-ingress
cd <kit>/02-Application-Deployment/yaml/blue-green
kubectl -n bg-ingress apply -f blue-deployment.yaml -f green-deployment.yaml -f ingress-switch.yaml
```

<details><summary>Solution</summary>

```bash
kubectl -n bg-ingress get ingress shop -o jsonpath='{.spec.rules[0].http.paths[0].backend.service.name}{"\n"}'   # shop-blue
kubectl -n bg-ingress rollout status deployment/shop-green
kubectl -n bg-ingress patch ingress shop --type=json \
  -p '[{"op":"replace","path":"/spec/rules/0/http/paths/0/backend/service/name","value":"shop-green"}]'
kubectl -n bg-ingress describe ingress shop | grep -A3 Rules          # backend shop-green:80 + endpoints
kubectl -n bg-ingress patch ingress shop --type=json \
  -p '[{"op":"replace","path":"/spec/rules/0/http/paths/0/backend/service/name","value":"shop-blue"}]'
kubectl -n bg-ingress get ingress shop -o jsonpath='{.spec.rules[0].http.paths[0].backend.service.name}' > /opt/course/23/backend.txt
```

**Verify:**
```bash
cat /opt/course/23/backend.txt                                        # shop-blue
kubectl -n bg-ingress get endpointslices -l kubernetes.io/service-name=shop-green   # green stays ready for the next switch
```
</details>

### Q24. Make running Pods pick up a changed ConfigMap
**Frequency:** 🧊 Low · **Est. time:** 4 min · **Competency:** Understand Deployments and how to perform rolling updates

Deployment `greeter` in `deploy-lab` reads `GREETING` from ConfigMap `greeter-config`. The ConfigMap was just changed to `bonjour`, but the Pods still print `hello`. Make the Pods use the new value without editing the Deployment manifest. Write the Deployment's revision number afterwards to `/opt/course/24/revision.txt`.

Lab setup:
```bash
kubectl -n deploy-lab create configmap greeter-config --from-literal=GREETING=hello
kubectl -n deploy-lab create deployment greeter --image=busybox:1.36 -- sh -c 'while true; do echo "$GREETING"; sleep 5; done'
kubectl -n deploy-lab set env deployment/greeter --from=configmap/greeter-config
kubectl -n deploy-lab rollout status deployment/greeter
kubectl -n deploy-lab create configmap greeter-config --from-literal=GREETING=bonjour --dry-run=client -o yaml | kubectl apply -f -
```

<details><summary>Solution</summary>

```bash
kubectl -n deploy-lab logs deploy/greeter --tail=1                    # hello (env is read only at container start)
kubectl -n deploy-lab rollout restart deployment/greeter
kubectl -n deploy-lab rollout status deployment/greeter
kubectl -n deploy-lab get deploy greeter -o jsonpath='{.metadata.annotations.deployment\.kubernetes\.io/revision}' > /opt/course/24/revision.txt
```

**Verify:**
```bash
kubectl -n deploy-lab logs deploy/greeter --tail=1                    # bonjour
cat /opt/course/24/revision.txt                                       # 3 (create=1, set env=2, restart=3)
kubectl -n deploy-lab get deploy greeter -o jsonpath='{.spec.template.metadata.annotations}{"\n"}'   # kubectl.kubernetes.io/restartedAt
```
</details>

### Q25. Change the selector of an existing Deployment
**Frequency:** 🧊 Low · **Est. time:** 6 min · **Competency:** Understand Deployments and how to perform rolling updates

Deployment `legacy-web` in `deploy-lab` (2 replicas, `nginx:1.27`) currently selects `app=legacy-web`. It must select its Pods by **both** `app=legacy-web` and `tier=web`, and its Pods must carry both labels. Service `legacy-web` must still route to the Pods afterwards. Keep image and replicas.

Lab setup:
```bash
kubectl -n deploy-lab create deployment legacy-web --image=nginx:1.27 --replicas=2
kubectl -n deploy-lab expose deployment legacy-web --port=80
```

<details><summary>Solution</summary>

The selector is immutable, so `kubectl edit`/`patch` fail with `field is immutable`. Recreate the Deployment from a clean manifest:

```yaml
# legacy-web.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: legacy-web
  labels:
    app: legacy-web
spec:
  replicas: 2
  selector:
    matchLabels:
      app: legacy-web
      tier: web
  template:
    metadata:
      labels:
        app: legacy-web
        tier: web
    spec:
      containers:
      - name: nginx
        image: nginx:1.27
        ports:
        - containerPort: 80
```

```bash
kubectl -n deploy-lab replace --force -f legacy-web.yaml     # delete + create
kubectl -n deploy-lab rollout status deployment/legacy-web
```

The Service selector `app=legacy-web` is a subset of the new Pod labels, so it keeps working unchanged.

**Verify:**
```bash
kubectl -n deploy-lab get deploy legacy-web -o jsonpath='{.spec.selector.matchLabels}{"\n"}'   # {"app":"legacy-web","tier":"web"}
kubectl -n deploy-lab get pods -l app=legacy-web,tier=web
kubectl -n deploy-lab get endpointslices -l kubernetes.io/service-name=legacy-web -o wide     # 2 endpoints
```
</details>

### Q26. Helm: uninstall with history, then restore
**Frequency:** 🧊 Low · **Est. time:** 4 min · **Competency:** Use the Helm package manager to deploy existing packages

Uninstall release `audit` in namespace `helm-k`, but keep its history. Write the status that `helm history` shows for its last revision to `/opt/course/26/status.txt`. Then restore the release from revision 1 and confirm its Pods run again.

Lab setup:
```bash
helm install audit /opt/course/charts/webapp -n helm-k --create-namespace
```

<details><summary>Solution</summary>

```bash
helm uninstall audit -n helm-k --keep-history
helm history audit -n helm-k                                  # 1 ... uninstalled ... Uninstallation complete
helm history audit -n helm-k -o yaml | grep 'status:' | tail -1 | awk '{print $2}' > /opt/course/26/status.txt
helm list -n helm-k --uninstalled                             # visible only with this flag (Helm 3)
helm rollback audit 1 -n helm-k                               # revision 2 re-creates the objects
```

**Verify:**
```bash
cat /opt/course/26/status.txt                                 # uninstalled
helm list -n helm-k                                           # audit  2  deployed
kubectl -n helm-k get pods                                    # Running again
```
</details>

### Q27. StatefulSet partitioned rolling update
**Frequency:** 🧊 Low · **Est. time:** 6 min · **Competency:** Understand Deployments and how to perform rolling updates

StatefulSet `db` in `deploy-lab` runs 3 replicas of `nginx:1.27`. Update it to `nginx:1.27-alpine` so that, for now, **only** `db-2` runs the new image. Verify. Then complete the update for all Pods.

Lab setup (`kubectl -n deploy-lab apply -f db.yaml`):
```yaml
# db.yaml
apiVersion: v1
kind: Service
metadata:
  name: db
spec:
  clusterIP: None
  selector:
    app: db
  ports:
  - name: http
    port: 80
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: db
spec:
  serviceName: db
  replicas: 3
  selector:
    matchLabels:
      app: db
  template:
    metadata:
      labels:
        app: db
    spec:
      containers:
      - name: db
        image: nginx:1.27
        ports:
        - containerPort: 80
```

<details><summary>Solution</summary>

```bash
kubectl -n deploy-lab patch statefulset db -p '{"spec":{"updateStrategy":{"type":"RollingUpdate","rollingUpdate":{"partition":2}}}}'
kubectl -n deploy-lab set image statefulset/db db=nginx:1.27-alpine
kubectl -n deploy-lab rollout status statefulset/db            # partitioned roll out complete: 1 new pods ...
kubectl -n deploy-lab get pods -l app=db -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[0].image}{"\n"}{end}'
# db-0 nginx:1.27 / db-1 nginx:1.27 / db-2 nginx:1.27-alpine
kubectl -n deploy-lab patch statefulset db -p '{"spec":{"updateStrategy":{"rollingUpdate":{"partition":0}}}}'
kubectl -n deploy-lab rollout status statefulset/db            # db-1, then db-0 updated
```

**Verify:**
```bash
kubectl -n deploy-lab get pods -l app=db -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[0].image}{"\n"}{end}'   # all 1.27-alpine
kubectl -n deploy-lab rollout history statefulset/db
```
</details>

---

## Cleanup

```bash
kubectl delete namespace deploy-lab canary-lab bg-lab bg-ingress kz-gen staging --ignore-not-found
for ns in helm-a helm-b helm-c helm-d helm-f helm-h helm-i helm-j helm-k; do kubectl delete namespace "$ns" --ignore-not-found; done
helm repo remove examples 2>/dev/null || true
```

## Must-know summary

- `kubectl set image deploy/<n> <container>=<image>`, then `kubectl annotate deploy/<n> kubernetes.io/change-cause="..." --overwrite`, then `kubectl rollout status`. Get the container name first. `--record` is deprecated.
- Only `spec.template` changes create revisions. Scaling, strategy changes and annotations don't. A ConfigMap change needs `kubectl rollout restart`.
- `rollout undo --to-revision=N` copies N's template into a **new** revision. N disappears from the history. Paused Deployments can't be undone.
- Rolling-update math: maxSurge rounds **up**, maxUnavailable rounds **down**. Defaults 25%/25%. 10 replicas gives max 13 and min 8. Both explicitly 0 is invalid.
- Recreate = `type: Recreate` with **no** `rollingUpdate` block (`"rollingUpdate": null` in a patch).
- `rollout pause` → several `set` commands → `rollout resume` = one revision. `rollout status --timeout` exits non-zero on failure. Look for `ProgressDeadlineExceeded`.
- `spec.selector` is immutable. Recreate the Deployment (`kubectl replace --force -f`) to change it.
- Blue/green: two full Deployments with a colour label (selector and template). Switch the Service selector (`kubectl patch svc`). Roll back by switching back.
- Canary: a shared label in the Service selector and a distinct `track` label in each Deployment selector. Share = canary / (stable + canary). Keep the total if the task says so.
- Helm: `helm install <release> <chart> -n <ns> --create-namespace -f values.yaml --set k=v`. `--set` beats `-f`, and the right-most file wins.
- `helm upgrade` with new values but no `--reuse-values` drops the old values. Pin `--version` for repo charts. Verify with `helm get values` (and `--all`).
- `helm history` → `helm rollback <release> <revision>` (new revision "Rollback to N"). `helm uninstall [--keep-history]`. `helm list -A` and status flags find releases. Helm 3 hides pending/uninstalled releases without `-a`.
- Stuck `pending-*` release: `helm rollback` to the last good revision. Release records are Secrets `sh.helm.release.v1.<rel>.v<rev>`.
- `helm show values`, `helm template`, `helm pull --untar --untardir`, `helm repo add` + `helm repo update`. Run `helm version` first: Helm 4 is current.
- Kustomize: `kubectl kustomize <dir>` to render, `kubectl apply -k <dir>` to apply. Use `resources`, `namespace`, `namePrefix`, `labels`, `images`, `replicas`, `configMapGenerator`, `patches`. Patches name the base object, and hash-suffixed generators trigger rollouts.
