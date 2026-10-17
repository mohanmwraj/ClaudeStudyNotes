# Canary lab (replica-ratio canary)

Two Deployments share the label `app=web`, and the Service selects only that label. The traffic split follows the replica split:

```text
canary share ~= canary replicas / (stable replicas + canary replicas)   ->   1 / (4 + 1) = 20 %
```

| File | What it shows |
|---|---|
| [stable-deployment.yaml](stable-deployment.yaml) | `web-stable`: labels `app=web,track=stable`, 4 replicas, nginx:1.27 |
| [canary-deployment.yaml](canary-deployment.yaml) | `web-canary`: labels `app=web,track=canary`, 1 replica, nginx:1.27-alpine |
| [service.yaml](service.yaml) | Service `web`, selector `app=web` only (spans both tracks) |
| [httproute-weighted.yaml](httproute-weighted.yaml) | Architect variant: exact 90/10 split plus a header override with a Gateway API HTTPRoute |

## 1. Deploy stable, Service, canary

```bash
kubectl create namespace canary
kubectl config set-context --current --namespace=canary
kubectl apply -f stable-deployment.yaml -f service.yaml
kubectl apply -f canary-deployment.yaml
kubectl get pods -l app=web -L track                                      # 4 stable + 1 canary
kubectl get endpointslices -l kubernetes.io/service-name=web -o wide      # 5 endpoints
```

## 2. Measure the split (each request is a new connection, so it is roughly 80/20)

```bash
kubectl run tmp --rm -i --image=busybox:1.36 --restart=Never -- \
  sh -c 'for i in $(seq 1 100); do wget -qO- http://web; done' | sort | uniq -c
#   ~80 web STABLE v1
#   ~20 web CANARY v2
```

## 3. Change the ratio (examples)

| Target split | stable | canary | Commands |
|---|---|---|---|
| 80/20 (total 5) | 4 | 1 | (initial state) |
| 90/10 (total 10) | 9 | 1 | `kubectl scale deploy web-stable --replicas=9` |
| 80/20 (total 10) | 8 | 2 | `kubectl scale deploy web-stable --replicas=8; kubectl scale deploy web-canary --replicas=2` |
| 50/50 (total 4) | 2 | 2 | `kubectl scale deploy web-stable --replicas=2; kubectl scale deploy web-canary --replicas=2` |

## 4a. Promote the canary (canary is good)

```bash
kubectl scale deployment web-stable --replicas=5                     # keep full capacity during the change
kubectl set image deployment/web-stable web=nginx:1.27-alpine        # stable now runs the canary's version
kubectl annotate deployment/web-stable kubernetes.io/change-cause="promote canary nginx:1.27-alpine" --overwrite
kubectl rollout status deployment/web-stable
kubectl delete deployment web-canary                                 # 100% on the promoted stable track
```

The `postStart` page text is part of the template, so after promotion stable Pods still say "STABLE v1". Only the image changed. In a real app the version comes from the image itself.

## 4b. Roll back the canary (canary is bad)

```bash
kubectl scale deployment web-canary --replicas=0     # traffic back to 100% stable at once; keeps the object for inspection
kubectl delete deployment web-canary                 # when done investigating
```

## Gotchas

- Each Deployment selector must include `track`. Overlapping selectors make the controllers fight over Pods.
- The Service selector must not include `track`, or the canary gets no traffic.
- The split is per new connection, so it's noisy for small samples and skewed by keep-alive or HTTP/2 clients.
- Granularity is limited by Pod count: with 4 Pods the smallest canary share is 25%. For a 1% canary use weighted routing ([httproute-weighted.yaml](httproute-weighted.yaml)).
- An HPA on either Deployment changes the ratio behind your back.

## Cleanup

```bash
kubectl delete namespace canary
kubectl config set-context --current --namespace=default
```
