# Blue/green lab

Two full-size Deployments run side by side. A Service (or an Ingress) points at exactly one of them. The release is a one-line selector change, and so is the rollback.

| File | What it shows |
|---|---|
| [blue-deployment.yaml](blue-deployment.yaml) | `shop-blue`: current version, labels `app=shop,version=blue`, 3 replicas |
| [green-deployment.yaml](green-deployment.yaml) | `shop-green`: new version, labels `app=shop,version=green`, 3 replicas |
| [service.yaml](service.yaml) | Service `shop`, selector `app=shop,version=blue` (the switch point) |
| [ingress-switch.yaml](ingress-switch.yaml) | Variant: one Service per colour plus an Ingress whose backend is flipped |

## 1. Deploy blue and the Service

```bash
kubectl create namespace bluegreen
kubectl config set-context --current --namespace=bluegreen
kubectl apply -f blue-deployment.yaml -f service.yaml
kubectl rollout status deployment/shop-blue
kubectl run tmp --rm -it --image=curlimages/curl:8.10.1 --restart=Never -- curl -s http://shop   # shop BLUE v1
```

## 2. Deploy green (no traffic yet) and wait until it is fully Ready

```bash
kubectl apply -f green-deployment.yaml
kubectl rollout status deployment/shop-green              # never switch before this succeeds
kubectl get pods -l app=shop,version=green                # 3/3 Running and READY 1/1
```

## 3. Switch the Service selector to green

```bash
# Strategic-merge patch: only the "version" key changes, "app" stays
kubectl patch service shop -p '{"spec":{"selector":{"app":"shop","version":"green"}}}'

# Alternatives:
kubectl set selector service shop 'app=shop,version=green'   # replaces the WHOLE selector, so list every key
kubectl edit service shop                                    # change spec.selector.version by hand
```

## 4. Verify

```bash
kubectl get service shop -o jsonpath='{.spec.selector}{"\n"}'          # {"app":"shop","version":"green"}
kubectl get endpointslices -l kubernetes.io/service-name=shop -o wide  # IPs must be the green Pod IPs
kubectl get pods -l app=shop,version=green -o wide                     # compare the IPs
kubectl run tmp --rm -it --image=curlimages/curl:8.10.1 --restart=Never -- curl -s http://shop   # shop GREEN v2
```

## 5. Roll back (instant), or finish

```bash
# Rollback: point the selector back at blue (blue Pods were never touched)
kubectl patch service shop -p '{"spec":{"selector":{"app":"shop","version":"blue"}}}'

# Finish: once green is proven, remove (or scale down) blue
kubectl scale deployment shop-blue --replicas=0    # keep it around for a fast rollback
kubectl delete deployment shop-blue                # or remove it completely
```

## Variant: switch at the Ingress

Needs an Ingress controller with class `nginx`.

```bash
kubectl apply -f blue-deployment.yaml -f green-deployment.yaml -f ingress-switch.yaml
kubectl patch ingress shop --type=json \
  -p '[{"op":"replace","path":"/spec/rules/0/http/paths/0/backend/service/name","value":"shop-green"}]'
kubectl get ingress shop -o jsonpath='{.spec.rules[0].http.paths[0].backend.service.name}{"\n"}'
```

## Gotchas

- The Service selector must include the colour label. If it selects only `app=shop`, you get an accidental 50/50 canary instead of a switch.
- `kubectl set selector` replaces the whole selector. `kubectl patch` (strategic merge) changes only the keys you send.
- Existing keep-alive connections stay on the old Pods until they close. New connections go to the new colour.
- During the switch you run 2x capacity. Make sure quotas allow it, or the green Deployment shows `ReplicaFailure`.

## Cleanup

```bash
kubectl delete namespace bluegreen
kubectl config set-context --current --namespace=default
```
