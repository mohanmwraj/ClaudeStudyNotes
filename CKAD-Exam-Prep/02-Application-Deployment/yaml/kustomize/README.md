# Kustomize lab: base and overlays

```text
kustomize/
├── base/
│   ├── kustomization.yaml      resources, labels (no selectors), configMapGenerator web-config
│   ├── deployment.yaml         Deployment "web" (nginx:1.27, envFrom configMapRef web-config)
│   └── service.yaml            Service "web"
└── overlays/
    ├── dev/
    │   ├── kustomization.yaml  namespace dev, namePrefix dev-, labels env=dev (+selectors), SMP patch, generator merge
    │   ├── namespace.yaml
    │   └── patch-replicas.yaml strategic-merge patch: replicas 1
    └── prod/
        ├── kustomization.yaml  namespace prod, prefix, labels, commonAnnotations, images, replicas,
        │                       SMP patch + inline JSON6902 patch, generator merge, secretGenerator
        ├── namespace.yaml
        └── patch-resources.yaml strategic-merge patch: container resources
```

All three renders were verified with kustomize v5.8.3, and the output validated against the Kubernetes 1.33, 1.35 and 1.37 schemas. The exam runs v1.37.

| File | What it shows |
|---|---|
| [base/kustomization.yaml](base/kustomization.yaml) | `resources`, `labels` with `includeSelectors: false` / `includeTemplates: true`, `configMapGenerator` |
| [base/deployment.yaml](base/deployment.yaml) | Base Deployment that references the generated ConfigMap by its short name |
| [base/service.yaml](base/service.yaml) | Base Service |
| [overlays/dev/kustomization.yaml](overlays/dev/kustomization.yaml) | `namespace`, `namePrefix`, `labels` + `includeSelectors: true`, `patches` (file), generator `behavior: merge` |
| [overlays/dev/patch-replicas.yaml](overlays/dev/patch-replicas.yaml) | Strategic-merge patch (replicas). The header shows the minimal exam form |
| [overlays/prod/kustomization.yaml](overlays/prod/kustomization.yaml) | `commonAnnotations`, `images` (newName/newTag), `replicas`, inline JSON6902 ops, `secretGenerator` |
| [overlays/prod/patch-resources.yaml](overlays/prod/patch-resources.yaml) | Strategic-merge patch (resources). Containers merge by `name` |

## Render, diff, apply

Run from this folder (`yaml/kustomize`):

```bash
kubectl kustomize base                       # render only (nothing is sent to the cluster)
kubectl kustomize overlays/dev
kubectl kustomize overlays/prod > /tmp/prod.yaml
kubectl apply -k overlays/dev                # creates namespace dev + dev-web objects
kubectl diff -k overlays/prod                # what would change (exit code 1 = differences found)
kubectl apply -k overlays/prod
kubectl get deploy,svc,cm,secret -n prod
kubectl get -k overlays/prod                 # list exactly the objects this kustomization manages
```

## What to look for in the prod output

```text
Namespace   prod                                  (namePrefix is NOT applied to Namespaces)
ConfigMap   prod-web-config-<hash>                data: GREETING=hello, LOG_LEVEL=warn (merged)
Secret      prod-web-secret-<hash>
Service     prod-web                              selector: app=web, env=prod
Deployment  prod-web   replicas 4, minReadySeconds 10, maxUnavailable 0,
            image docker.io/library/nginx:1.27-alpine,
            envFrom -> prod-web-config-<hash> + prod-web-secret-<hash>,
            env ENVIRONMENT=production appended, resources 250m/256Mi -> 500m/256Mi,
            annotation team=web-platform on the Deployment AND the Pod template
```

## Hash suffix triggers a rollout

```bash
cp -r . /tmp/kustomize-lab && cd /tmp/kustomize-lab      # experiment on a copy
# Change a generator literal: the ConfigMap gets a NEW name, so the Pod template changes and a rollout starts
sed -i 's/LOG_LEVEL=warn/LOG_LEVEL=error/' overlays/prod/kustomization.yaml
kubectl apply -k overlays/prod
kubectl rollout status deployment/prod-web -n prod
kubectl get cm -n prod                       # old prod-web-config-<oldhash> is left behind (garbage)
```

## Cleanup

```bash
kubectl delete -k overlays/dev
kubectl delete -k overlays/prod              # also deletes the Namespace objects listed in the overlays
```
