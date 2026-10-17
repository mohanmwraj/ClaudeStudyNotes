# Helm lab (works offline)

| Path | What it shows |
|---|---|
| [sample-chart/webapp/Chart.yaml](sample-chart/webapp/Chart.yaml) | Chart metadata: `apiVersion: v2`, chart `version` vs `appVersion` |
| [sample-chart/webapp/values.yaml](sample-chart/webapp/values.yaml) | Default values (replicaCount, image, message, service, strategy, env, resources) |
| [sample-chart/webapp/templates/_helpers.tpl](sample-chart/webapp/templates/_helpers.tpl) | Named templates: name, fullname, labels, selector labels |
| [sample-chart/webapp/templates/deployment.yaml](sample-chart/webapp/templates/deployment.yaml) | Deployment template, incl. the `checksum/page` annotation (ConfigMap change -> rollout) |
| [sample-chart/webapp/templates/service.yaml](sample-chart/webapp/templates/service.yaml) | Service template with an optional `nodePort` |
| [sample-chart/webapp/templates/configmap.yaml](sample-chart/webapp/templates/configmap.yaml) | ConfigMap holding `index.html`, so `--set message=...` is visible with curl |
| [sample-chart/webapp/templates/NOTES.txt](sample-chart/webapp/templates/NOTES.txt) | Text printed after install/upgrade (`helm get notes`) |
| [values-override.yaml](values-override.yaml) | A user values file for `-f` |

The chart was linted and rendered with Helm v3.22.1 and v4.3.1, and the output validated against the Kubernetes 1.33, 1.35 and 1.37 schemas. The exam runs v1.37.

> **Practice-lab note:** when a question uses a chart, prefer a local chart (this one, or `helm create webapp`) so it works offline. To practise `helm repo add`, the stable public repo `https://helm.github.io/examples` (chart `hello-world`, deploys `nginx:1.16.0`) is a good choice. Bitnami changed its free container image catalog in 2025: most versioned images left `docker.io/bitnami`. Bitnami charts can therefore fail with `ErrImagePull`/`ImagePullBackOff` unless you override the image repository.

## 1. Inspect and render without a cluster

Run from this folder (`yaml/helm`):

```bash
helm lint sample-chart/webapp                                   # chart is well-formed
helm show chart  sample-chart/webapp                            # Chart.yaml
helm show values sample-chart/webapp > /tmp/webapp-values.yaml  # defaults, ready to edit
helm template web sample-chart/webapp -f values-override.yaml --set replicaCount=4   # rendered YAML to stdout
helm template web sample-chart/webapp --show-only templates/deployment.yaml          # one file only
```

## 2. Install, upgrade, roll back, uninstall

```bash
helm install web sample-chart/webapp -n helm-lab --create-namespace
helm list -n helm-lab                                           # STATUS deployed, REVISION 1
kubectl get deploy,svc,cm -n helm-lab -l app.kubernetes.io/instance=web

helm upgrade web sample-chart/webapp -n helm-lab --set message="v2 page"          # REVISION 2
helm upgrade web sample-chart/webapp -n helm-lab --reuse-values --set replicaCount=3   # REVISION 3, keeps message
helm get values web -n helm-lab                                 # message + replicaCount
helm history web -n helm-lab

helm rollback web 1 -n helm-lab                                 # creates REVISION 4 = copy of revision 1
helm history web -n helm-lab                                    # 4 ... deployed ... Rollback to 1

helm uninstall web -n helm-lab                                  # removes the objects AND the release history
```

## 3. Values precedence experiment

```bash
helm template web sample-chart/webapp -f values-override.yaml | grep -m1 replicas:                    # 3 (file wins over chart default 2)
helm template web sample-chart/webapp -f values-override.yaml --set replicaCount=5 | grep -m1 replicas:  # 5 (--set wins)
```

## 4. Public repo practice (needs internet)

```bash
helm repo add examples https://helm.github.io/examples
helm repo update
helm search repo examples --versions                            # examples/hello-world 0.1.0  (app 1.16.0)
helm show values examples/hello-world
helm install hello examples/hello-world -n helm-lab --create-namespace --set replicaCount=2
helm pull examples/hello-world --version 0.1.0 --untar --untardir /tmp/charts   # /tmp/charts/hello-world/
helm uninstall hello -n helm-lab
helm repo remove examples
```

## 5. Simulate and fix a stuck `pending-upgrade` release

```bash
helm install web sample-chart/webapp -n helm-lab --create-namespace
# Start an upgrade that waits on a bad image, then kill the client hard (SIGKILL cannot be handled)
helm upgrade web sample-chart/webapp -n helm-lab --set image.tag=does-not-exist --wait --timeout 5m &
sleep 5; kill -9 $!
helm history web -n helm-lab                                    # revision 2: pending-upgrade
helm upgrade web sample-chart/webapp -n helm-lab                # Error: ... another operation (install/upgrade/rollback) is in progress
helm rollback web 1 -n helm-lab                                 # fix: roll back to the last good revision
helm history web -n helm-lab                                    # revision 3: deployed (Rollback to 1)
kubectl get secrets -n helm-lab -l owner=helm,name=web          # sh.helm.release.v1.web.v1 ... v3
```

## Cleanup

```bash
helm uninstall web -n helm-lab 2>/dev/null; kubectl delete namespace helm-lab
```
