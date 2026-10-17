# Deployment strategies: Recreate, rolling, blue/green, canary

**Why it matters.** The competency is "Use Kubernetes primitives to implement common deployment strategies (e.g. blue/green or canary)". *Primitives* means Deployments, labels, Service selectors and Ingress. No service mesh or extra controllers are needed. Typical tasks:

- "deploy version 2 next to version 1 and switch the Service to it"
- "send about 20% of traffic to the new version while keeping N Pods in total"

Everything below works on a bare cluster.

## Core concepts

### Strategy comparison

| Strategy | Built from | Downtime | Extra capacity | Rollback | Traffic control | Exam relevance |
|---|---|---|---|---|---|---|
| **Recreate** | 1 Deployment, `strategy.type: Recreate` | **Yes** (all old Pods gone before new start) | None | Undo, with downtime again | None | Medium |
| **Rolling update** | 1 Deployment (default strategy) | No, given readiness probes | `maxSurge` | `kubectl rollout undo` (rolling again) | None (both versions serve during the rollout) | High |
| **Blue/green** | 2 Deployments + switch the Service selector (or Ingress backend) | No | 2x during the switch | **Instant**: switch back | All-or-nothing | High |
| **Canary** | 2 Deployments sharing the Service's label | No | + canary Pods | Scale canary to 0 | ≈ replica ratio | High |
| **A/B testing** | L7 routing on header/cookie (Ingress controller, Gateway API, mesh) | No | + B Pods | Remove the route | Per user attribute | Concept only |
| **Shadow (mirroring)** | L7 mirror filter (Gateway API `RequestMirror`, mesh) | No | + shadow Pods | Stop mirroring | Copy of live traffic, responses discarded | Concept only |

### Labels are the whole trick

A Service sends traffic to **every Ready Pod whose labels match its selector**, no matter which Deployment created the Pod. Every strategy is a deliberate choice of labels:

```text
BLUE/GREEN                                              CANARY
Service shop  selector app=shop,version=blue            Service web  selector app=web  (no track!)
  ├──► shop-blue   Pods app=shop,version=blue   (live)    ├──► web-stable  Pods app=web,track=stable  x4  ≈ 80%
  └──x shop-green  Pods app=shop,version=green  (idle)    └──► web-canary  Pods app=web,track=canary  x1  ≈ 20%
switch = change ONE selector value                      ratio = replica counts
```

**Rule 1:** every Deployment's selector contains its distinguishing label (`version` / `track`), so no two Deployments select each other's Pods. "If you have multiple controllers that have overlapping selectors, the controllers will fight with each other."

**Rule 2:** the Service selector contains the colour for blue/green, and only the shared labels for canary.

## Recreate and rolling update (recap)

- **Recreate**: for apps that must never run two versions at once, e.g. a ReadWriteOnce volume, a singleton consumer, or an incompatible schema. See [yaml/deployment-recreate.yaml](yaml/deployment-recreate.yaml).
- **Rolling update**: the default. Tune `maxSurge`/`maxUnavailable`. The arithmetic and the rollback rules are in [02-rolling-updates-and-rollbacks.md](02-rolling-updates-and-rollbacks.md).

## Blue/green

Files: [yaml/blue-green/](yaml/blue-green/README.md) (`blue-deployment.yaml`, `green-deployment.yaml`, `service.yaml`, `ingress-switch.yaml`).

**Procedure**

```bash
# 1. Blue is live: Service selector app=shop,version=blue
kubectl get svc shop -o jsonpath='{.spec.selector}{"\n"}'

# 2. Deploy green at FULL size with its own colour label (selector AND template)
kubectl apply -f green-deployment.yaml
kubectl rollout status deployment/shop-green        # wait until every green Pod is Ready

# 3. Switch: change only the colour in the Service selector
kubectl patch service shop -p '{"spec":{"selector":{"app":"shop","version":"green"}}}'

# 4. Verify: the endpoints must now be the green Pod IPs
kubectl get endpointslices -l kubernetes.io/service-name=shop -o wide
kubectl get pods -l app=shop,version=green -o wide

# 5a. Rollback = switch back (blue was never touched)
kubectl patch service shop -p '{"spec":{"selector":{"app":"shop","version":"blue"}}}'
# 5b. Or finish: retire blue
kubectl scale deployment shop-blue --replicas=0      # or: kubectl delete deployment shop-blue
```

The Service's selector, the field that changes:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: shop
spec:
  selector:
    app: shop
    version: green        # was: blue
  ports:
  - name: http
    port: 80
    targetPort: 80
```

**Other ways to switch**

| Switch point | How | Note |
|---|---|---|
| Service selector | `kubectl patch svc`, `kubectl edit svc`, `kubectl set selector svc shop 'app=shop,version=green'` | `set selector` replaces the whole selector |
| Ingress backend | One Service per colour. Change `backend.service.name` in the Ingress ([ingress-switch.yaml](yaml/blue-green/ingress-switch.yaml)) | `kubectl patch ingress shop --type=json -p '[{"op":"replace","path":"/spec/rules/0/http/paths/0/backend/service/name","value":"shop-green"}]'` |
| Gateway API | HTTPRoute `backendRefs`: move the weight from 100/0 to 0/100 | Same mechanism as weighted canary, below |
| DNS / external LB | Point the record at the other environment | Slow (TTL), outside Kubernetes |

**Blue/green gotchas**

- If the Service selects only `app=shop` while both colours run, you get an accidental 50/50 split.
- Switch only after green is fully Ready. A selector pointing at unready Pods gives an empty endpoint list, which is an outage.
- Open keep-alive connections keep hitting blue until they close. Keep blue running for a while after the switch.
- 2x capacity. Under a ResourceQuota the green Deployment may show `ReplicaFailure/FailedCreate`.
- Both colours share databases and queues. Schema changes must be backward compatible, or rollback is not really instant.

## Canary

Files: [yaml/canary/](yaml/canary/README.md) (`stable-deployment.yaml`, `canary-deployment.yaml`, `service.yaml`).

### Ratio arithmetic

```text
canary share  =  canary replicas / (stable replicas + canary replicas)

Total N fixed, share p:          canary = round(N x p)          stable = N - canary
Stable S fixed (don't touch it): canary = S x p / (1 - p)       (must come out a whole number)
```

| Requirement | stable | canary | Canary share | Commands |
|---|---|---|---|---|
| 80/20, 10 Pods total | 8 | 2 | 20% | `scale web-stable --replicas=8`, canary `--replicas=2` |
| 90/10, 10 Pods total | 9 | 1 | 10% | `scale web-stable --replicas=9`, canary `--replicas=1` |
| 75/25 (the official tutorial) | 3 | 1 | 25% | |
| "Keep **5** Pods total, 20% canary" (stable now 5) | 4 | 1 | 20% | Scale stable 5 → 4, create canary with 1 |
| "Keep **10** Pods total, 30% canary" | 7 | 3 | 30% | |
| "Stable must keep its 4 replicas, canary gets 20%" | 4 | 1 | 20% | 4 × 0.2 / 0.8 = 1 |
| "Stable has 9 replicas unchanged, canary ≈ 10%" | 9 | 1 | 10% | 9 × 0.1 / 0.9 = 1 |
| "10% canary with only 4 Pods allowed" | n/a | n/a | not possible | Smallest step is 1/4 = 25%. Needs weighted routing |

### Procedure

```bash
# 1. Inspect what exists: labels, selector, Service selector
kubectl get deploy web-stable -o jsonpath='{.spec.selector.matchLabels}{"\n"}'
kubectl get svc web -o jsonpath='{.spec.selector}{"\n"}'          # must be the SHARED label only (app=web)

# 2. Create the canary. Copy the stable manifest, then change name, track label (selector AND
#    template), image and replicas
kubectl get deploy web-stable -o yaml > canary.yaml               # strip status/uid/resourceVersion, or use:
kubectl create deployment web-canary --image=nginx:1.27-alpine --replicas=1 --dry-run=client -o yaml > canary.yaml
#    !! create deployment labels Pods app=web-canary -> change selector + template labels to app=web, track=canary
vim canary.yaml && kubectl apply -f canary.yaml

# 3. Keep the total constant if required
kubectl scale deployment web-stable --replicas=4

# 4. Verify: both tracks are behind the Service
kubectl get pods -l app=web -L track
kubectl get endpointslices -l kubernetes.io/service-name=web -o wide      # 4 + 1 endpoints

# 5. Measure (each request is a new connection)
kubectl run tmp --rm -i --image=busybox:1.36 --restart=Never -- \
  sh -c 'for i in $(seq 1 100); do wget -qO- http://web; done' | sort | uniq -c
```

The canary's labels:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web-canary
spec:
  replicas: 1
  selector:
    matchLabels:
      app: web            # shared with stable -> the Service picks these Pods
      track: canary       # distinguishing -> no overlap with the stable Deployment
  template:
    metadata:
      labels:
        app: web
        track: canary
    spec:
      containers:
      - name: web
        image: nginx:1.27-alpine
```

> If the existing stable Deployment selects **only** `app=web`, you can't add `track` to it: selectors are immutable. Leave it alone and give the canary the extra label. Its ReplicaSet Pods carry their own `pod-template-hash`, so the two Deployments don't take each other's Pods. Avoid this overlap in designs you control.

### Promotion and rollback

| Goal | Steps |
|---|---|
| **Promote** (canary is healthy) | 1. `kubectl scale deploy web-stable --replicas=<full>` (keep capacity) · 2. `kubectl set image deploy/web-stable web=<canary image>` · 3. `kubectl rollout status deploy/web-stable` · 4. `kubectl delete deploy web-canary` |
| **Promote gradually** | Shift replicas step by step: canary 1→2→5, stable 4→3→0. Then decide which Deployment stays the long-term "stable" |
| **Roll back** (canary is bad) | `kubectl scale deploy web-canary --replicas=0` (instant, keeps the object for inspection), then `kubectl delete deploy web-canary`. Scale stable back up if you reduced it |

### Limitations of replica-based canary

- **Granularity**: the share moves in steps of 1/total Pods. 1% needs 100 Pods.
- **Approximate**: kube-proxy picks an endpoint per *new connection* (random or round-robin, depending on mode). HTTP keep-alive, HTTP/2, gRPC and connection pools skew it.
- **No targeting**: you can't send "only internal users" or "only header X" to the canary.
- **Coupled to scaling**: an HPA on either Deployment changes the ratio. Capacity and traffic share can't be tuned separately.
- **Session affinity** (`sessionAffinity: ClientIP`) pins clients, which distorts the split.
- **Metrics**: telling canary errors from stable errors needs per-track labels in your monitoring.

## A/B testing and shadow traffic (concepts)

- **A/B testing** routes by a request attribute (header, cookie, user segment) to compare two variants for a business metric. It needs L7 routing: Gateway API `HTTPRoute` `matches` on headers, ingress-controller canary-by-header annotations, or a service mesh. Plain Services can't do it.
- **Shadow (mirroring)** copies live requests to the new version and discards its responses. It tests behaviour and performance with zero user impact. Gateway API has a `RequestMirror` filter, and meshes have mirror settings. Watch out for side effects: a mirrored "POST /pay" is still a payment.

## Key fields / syntax

| Strategy | Field(s) that matter |
|---|---|
| Recreate | `spec.strategy.type: Recreate` (no `rollingUpdate`) |
| Rolling | `spec.strategy.rollingUpdate.maxSurge` / `maxUnavailable`, `minReadySeconds` |
| Blue/green | Deployment `spec.selector.matchLabels.version` and template labels; Service `spec.selector.version` |
| Canary | Shared `app` label in both templates; distinct `track` in both selectors; Service selects `app` only; `spec.replicas` sets the ratio |

## Imperative commands

```bash
# Blue/green switch and check
kubectl patch service shop -p '{"spec":{"selector":{"app":"shop","version":"green"}}}'
kubectl set selector service shop 'app=shop,version=green'
kubectl get svc shop -o wide                                         # SELECTOR column
kubectl describe svc shop | grep -i -A2 endpoints

# Canary
kubectl create deployment web-canary --image=nginx:1.27-alpine --replicas=1 --dry-run=client -o yaml > canary.yaml
kubectl scale deployment web-stable --replicas=8 && kubectl scale deployment web-canary --replicas=2
kubectl get pods -l app=web -L track,version
kubectl get endpointslices -l kubernetes.io/service-name=web -o wide

# Promote / roll back the canary
kubectl set image deployment/web-stable web=nginx:1.27-alpine && kubectl rollout status deployment/web-stable
kubectl delete deployment web-canary
kubectl scale deployment web-canary --replicas=0
```

## Exam traps & tips

> **Exam tip:** `kubectl create deployment web-canary ...` labels the Pods `app=web-canary`. Edit both the selector and the template labels to the Service's label, or the canary gets no traffic.

> **Exam tip:** Check the Service selector before and after your change with `kubectl get svc <n> -o jsonpath='{.spec.selector}'`. Then check the endpoints. That is how the task will be graded.

> **Exam tip:** "20% of traffic to the new version, 5 Pods in total" means 4 + 1, not 5 + 1. Read whether the total must stay fixed.

> **Exam tip:** Don't edit the stable Deployment's selector to add `track`. It's immutable. Add the distinguishing label to the new Deployment.

> **Exam tip:** For blue/green, deploy green at full size, wait for `rollout status`, then switch. If you switch before green is Ready, the endpoints are empty.

> **Exam tip:** The template label `version: green` must also be in green's selector, so the blue and green Deployments don't overlap.

## Architect notes

- **Weighted routing beats replica ratios.** Gateway API `HTTPRoute` splits by `backendRefs[].weight`. Weights are relative, default 1, and weight 0 sends nothing. It's exact, independent of Pod counts, and supports header matches for A/B. See [yaml/canary/httproute-weighted.yaml](yaml/canary/httproute-weighted.yaml):

  ```yaml
  apiVersion: gateway.networking.k8s.io/v1
  kind: HTTPRoute
  metadata:
    name: web
  spec:
    parentRefs:
    - name: example-gateway
    rules:
    - backendRefs:
      - name: web-stable
        port: 80
        weight: 90
      - name: web-canary
        port: 80
        weight: 10
  ```

- **Ingress-controller canaries**: ingress-nginx implemented canaries with annotations on a second Ingress (`nginx.ingress.kubernetes.io/canary: "true"`, `canary-weight`, `canary-by-header`, `canary-by-cookie`; precedence header → cookie → weight; one canary Ingress per rule). The ingress-nginx project was **retired** (announced by SIG Network in Nov 2025, best-effort maintenance ended March 2026). The Ingress API itself stays GA. Use Gateway API for new designs. ingress-nginx is still fine for practice labs.

  ```yaml
  apiVersion: networking.k8s.io/v1
  kind: Ingress
  metadata:
    name: web-canary
    annotations:
      nginx.ingress.kubernetes.io/canary: "true"
      nginx.ingress.kubernetes.io/canary-weight: "10"   # 10% of the main Ingress's traffic
  spec:
    ingressClassName: nginx
    rules:
    - host: web.example.com                             # same host/path as the main Ingress
      http:
        paths:
        - path: /
          pathType: Prefix
          backend:
            service:
              name: web-canary
              port:
                number: 80
  ```

- **Service mesh** (Istio, Linkerd, ...) gives per-request weights, header routing, mirroring, retries and per-version telemetry. It costs operational complexity. Many meshes now also implement Gateway API routes.
- **Progressive delivery controllers** automate the loop of shift weight → measure → promote or abort. Argo Rollouts uses a `Rollout` resource with steps (`setWeight: 20`, `pause`, analysis against Prometheus). Flagger uses a `Canary` resource driving a mesh or Gateway API. Both roll back automatically when metrics breach the thresholds.
- **Blue/green at platform level**: two Helm releases or two Kustomize overlays plus a switchable route, or whole-cluster blue/green for upgrades.
- **Data compatibility** decides whether rollback is instant. Use expand/contract migrations, idempotent consumers, and feature flags to decouple *deploy* from *release*.
- **Observe per version**: add `version`/`track` labels to Pods, and make them part of metric labels and log fields, so the canary's error rate can be compared with stable's.

## Docs to bookmark

- Canary deployments (labels pattern): https://kubernetes.io/docs/concepts/workloads/management/
- Tutorial, canary deployment: https://kubernetes.io/docs/tutorials/stateless-application/canary-deployment/
- Deployment strategies (Recreate / RollingUpdate): https://kubernetes.io/docs/concepts/workloads/controllers/deployment/#strategy
- Services and selectors: https://kubernetes.io/docs/concepts/services-networking/service/
- `kubectl set selector`: https://kubernetes.io/docs/reference/kubectl/generated/kubectl_set/kubectl_set_selector/
- `kubectl patch` how-to: https://kubernetes.io/docs/tasks/manage-kubernetes-objects/update-api-object-kubectl-patch/
- Gateway API concept page: https://kubernetes.io/docs/concepts/services-networking/gateway/
- Ingress-nginx retirement: https://kubernetes.io/blog/2025/11/11/ingress-nginx-retirement/
- Beyond the exam: Gateway API traffic splitting https://gateway-api.sigs.k8s.io/guides/user-guides/traffic-splitting/ · Argo Rollouts https://argo-rollouts.readthedocs.io/en/stable/ · Flagger https://docs.flagger.app/

Related chapters: Services and Ingress in [../05-Services-and-Networking/README.md](../05-Services-and-Networking/README.md). Production rollout design in [../08-Architect-Notes/README.md](../08-Architect-Notes/README.md).

## Quick self-check

1. Blue/green: which single object do you change to switch traffic, and what do you change in it?
2. Stable runs 6 replicas and must not be modified. How many canary replicas give 25% canary traffic?
3. Why must the canary Deployment's selector include `track: canary`, while the Service selector must not?
4. 10 Pods total, 30% canary. Give the replica counts and the commands.
5. Name two reasons why a replica-based canary split is only approximate.
6. How do you roll back a canary instantly while keeping it for investigation?

<details><summary>Answers</summary>

1. The Service: its `spec.selector` colour label (`version: blue` → `green`). Or the Ingress backend, in the Ingress variant.
2. 6 × 0.25 / 0.75 = **2** canary replicas (2 / 8 = 25%).
3. The Deployment selector must not overlap the stable Deployment's Pods. The Service must select the shared label so it spans both tracks.
4. Stable 7, canary 3: `kubectl scale deploy web-stable --replicas=7` and `kubectl scale deploy web-canary --replicas=3`.
5. Any two of: per-connection load balancing (keep-alive/HTTP/2), small sample sizes, HPA changing replica counts, session affinity, Pods not Ready yet.
6. `kubectl scale deployment web-canary --replicas=0`.

</details>
