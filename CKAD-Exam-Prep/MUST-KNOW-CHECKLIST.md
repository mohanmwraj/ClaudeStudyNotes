# MUST-KNOW Checklist — tick a line only after you have DONE it in your lab

Target times are what you should hit by Tuesday night. If a line takes longer, it is a weak spot: go to the linked chapter and redo its practice questions.

---

## 0. Exam mechanics (every task)
- [ ] Switch context/host exactly as a task says, then confirm with `k config current-context` — 10 s
- [ ] Set the namespace per task (`k config set-context --current --namespace=x`) or use `-n` every time
- [ ] Generate YAML with `$do` (`--dry-run=client -o yaml`) instead of typing it
- [ ] Fix an immutable Pod field with `get -o yaml` → edit → `replace --force`
- [ ] Write command output to an exact file path, then `cat` it — [06](06-Cross-Cutting-Skills-and-Bonus-Topics/README.md)
- [ ] Use vim: indent a block (`V` + `>`), paste docs YAML with `:set paste`, `:%s/old/new/g`

## 1. Application Design and Build — 20% → [chapter](01-Application-Design-and-Build/README.md)
- [ ] Build an image from a Dockerfile with podman **and** docker, tag it, save it as a tar (docker-archive and `--format oci-archive`) — 3 min
- [ ] Edit a Dockerfile (base image, ENV, USER, CMD) and rebuild with a new tag — 3 min
- [ ] Explain ENTRYPOINT/CMD ↔ `command`/`args`; override both in a Pod
- [ ] Pick the right workload: Deployment / StatefulSet / DaemonSet / Job / CronJob / bare Pod
- [ ] CronJob with schedule, `concurrencyPolicy`, `successfulJobsHistoryLimit`/`failedJobsHistoryLimit`, `activeDeadlineSeconds`, `startingDeadlineSeconds`, `suspend` — 4 min
- [ ] Run a CronJob now: `k create job x --from=cronjob/y`
- [ ] Job with `completions`, `parallelism`, `backoffLimit`, `ttlSecondsAfterFinished` (+ Indexed mode) — 3 min
- [ ] DaemonSet from a Deployment YAML (drop replicas/strategy), incl. a control-plane toleration — 4 min
- [ ] StatefulSet + headless Service + `volumeClaimTemplates` — 6 min
- [ ] Init container that prepares a file / waits for DNS — 4 min
- [ ] Sidecar sharing an `emptyDir` (classic, and native: `initContainers` + `restartPolicy: Always`) — 4 min
- [ ] Adapter and ambassador patterns: know what each one is for
- [ ] `emptyDir` (incl. `medium: Memory`, `sizeLimit`), `hostPath` (types)
- [ ] Static PV + PVC + Pod mount; know why a PVC stays `Pending` (class, size, accessModes, WaitForFirstConsumer) — 5 min

## 2. Application Deployment — 20% → [chapter](02-Application-Deployment/README.md)
- [ ] `set image` → `rollout status` → `rollout history` → `rollout undo --to-revision=N` — 2 min
- [ ] Record change-cause with `kubectl annotate ... kubernetes.io/change-cause=...`
- [ ] `maxSurge` / `maxUnavailable` math (surge rounds up, unavailable rounds down) and the `Recreate` strategy
- [ ] `rollout pause` / several changes / `rollout resume`; `rollout restart`
- [ ] Blue/green: two Deployments, switch the Service selector, roll back the switch — 5 min
- [ ] Canary: shared Service label, replica ratio (e.g. 8+2 = 80/20, 4+1 = 20% of 5) — 5 min
- [ ] Helm: `repo add/update`, `search repo --versions`, `show values`, `install -n --create-namespace --set/-f`, `upgrade (--reuse-values)`, `history`, `rollback`, `uninstall`, `list -A --pending/--failed`, `get values`, `template` — 6 min
- [ ] Kustomize: base + overlay with `namespace`, `namePrefix`, `labels`, `images`, `replicas`, `configMapGenerator`/`secretGenerator`, strategic-merge and JSON6902 `patches`; `k kustomize`, `k apply -k` — 6 min

## 3. Application Observability and Maintenance — 15% → [chapter](03-Application-Observability-and-Maintenance/README.md)
- [ ] Fix manifests that use removed APIs (Deployment `extensions/v1beta1` → `apps/v1` + selector; Ingress → `networking.k8s.io/v1` + `pathType`; CronJob → `batch/v1`; PDB → `policy/v1`; HPA → `autoscaling/v2`) — 4 min
- [ ] Find a kind's current group/version with `k api-resources` / `k explain`
- [ ] Liveness / readiness / startup probes with httpGet, tcpSocket, exec (and grpc); know the defaults; fix a probe on the wrong port — 3 min
- [ ] `k top pod --sort-by=cpu|memory [--containers]`, `k top node`; write the top pod name to a file — 2 min
- [ ] `k logs` with `-c`, `-p`, `--since`, `--tail`, `-l`, `--all-containers`, `--prefix` → file — 1 min
- [ ] Diagnose: Pending, ImagePullBackOff, CrashLoopBackOff, CreateContainerConfigError, OOMKilled (137), failing readiness (no endpoints) — 5 min each
- [ ] `k debug -it pod --image=busybox:1.36 --target=c`; `--copy-to`; temporary client pods with `--rm -it --restart=Never`
- [ ] Events sorted by time; `describe` bottom section

## 4. Application Environment, Configuration and Security — 25% → [chapter](04-Application-Environment-Configuration-and-Security/README.md)
- [ ] CRD: list them, `explain` a custom resource, create a CR instance; recognise the operator pattern — 4 min
- [ ] Request flow: authentication → authorization → admission (mutating → validating); kubeconfig contexts/users/clusters
- [ ] Find/enable admission plugins (`--enable-admission-plugins` in the kube-apiserver static Pod manifest)
- [ ] Pod Security Admission labels on a namespace (`enforce/audit/warn` = `privileged/baseline/restricted`); make a rejected Pod compliant — 5 min
- [ ] Role/ClusterRole + RoleBinding/ClusterRoleBinding for a ServiceAccount; verify with `k auth can-i ... --as=system:serviceaccount:ns:sa` — 3 min
- [ ] Fix "forbidden" in app logs by binding the right Role or switching the Deployment's SA (`k set serviceaccount`) — 4 min
- [ ] ServiceAccount: create, assign, `automountServiceAccountToken: false`, `k create token`
- [ ] Requests vs limits, units (`500m`, `256Mi`), QoS classes (Guaranteed/Burstable/BestEffort)
- [ ] ResourceQuota (compute + object counts) and LimitRange (default/defaultRequest/min/max); fix a Deployment blocked by quota (read the ReplicaSet events) — 5 min
- [ ] ConfigMap from literal / file / env-file; consume as `env`, `envFrom`, volume (`items`, `subPath` caveat); `rollout restart` after changes — 4 min
- [ ] Secret generic / tls / docker-registry; `stringData` vs `data`; decode with `base64 -d`; consume as env/volume (`defaultMode`); `imagePullSecrets` — 4 min
- [ ] SecurityContext: `runAsUser/Group`, `fsGroup`, `runAsNonRoot`, `allowPrivilegeEscalation: false`, `readOnlyRootFilesystem` (+ emptyDir), `capabilities.add/drop` (no `CAP_` prefix), `seccompProfile: RuntimeDefault`; container-level overrides pod-level — 4 min
- [ ] Downward API env (`fieldRef`, `resourceFieldRef`) and volume (labels/annotations)

## 5. Services and Networking — 20% → [chapter](05-Services-and-Networking/README.md)
- [ ] `k expose` (ClusterIP/NodePort), pin a nodePort, `k create svc`; headless and ExternalName — 2 min
- [ ] Troubleshoot a Service with no endpoints: selector vs labels, `targetPort`, readiness, named ports — 4 min
- [ ] DNS names `<svc>.<ns>.svc.cluster.local`; test with busybox `nslookup`/`wget`
- [ ] Ingress: host + path rules (`Prefix`/`Exact`), `ingressClassName`, TLS secret, default backend; `k create ingress --rule="host/path*=svc:port"`; test with `curl -H "Host: ..."` — 4 min
- [ ] Fix a broken Ingress (wrong service name/port, missing pathType/class) — 3 min
- [ ] NetworkPolicy: default-deny (ingress/egress/all), allow from pod labels, from a namespace (`kubernetes.io/metadata.name`), AND vs OR, ports, ipBlock, egress with DNS (53 UDP+TCP) — 5 min
- [ ] "Don't touch the policies": relabel Pods so the existing policies allow the traffic — 3 min
- [ ] Bonus: Gateway API Gateway + HTTPRoute with weighted backends (know the shape)

## 6. Numbers and defaults to memorise

| Item | Value |
|---|---|
| Probe defaults | initialDelaySeconds 0 · periodSeconds 10 · timeoutSeconds 1 · successThreshold 1 · failureThreshold 3 |
| Deployment | maxSurge 25% · maxUnavailable 25% · revisionHistoryLimit 10 · progressDeadlineSeconds 600 |
| Job | backoffLimit 6 · completions 1 · parallelism 1 · restartPolicy Never/OnFailure only |
| CronJob | successfulJobsHistoryLimit 3 · failedJobsHistoryLimit 1 · concurrencyPolicy Allow |
| Pod | restartPolicy Always · terminationGracePeriodSeconds 30 · dnsPolicy ClusterFirst |
| imagePullPolicy | `Always` for `:latest`/no tag, otherwise `IfNotPresent` |
| NodePort range | 30000–32767 |
| ConfigMap/Secret size | ≤ 1 MiB |
| Secret/ConfigMap volume defaultMode | 0644 |
| SA token mount | `/var/run/secrets/kubernetes.io/serviceaccount/{token,ca.crt,namespace}` |
| Service DNS | `<svc>.<ns>.svc.cluster.local` · pod in StatefulSet: `<pod>.<svc>.<ns>.svc.cluster.local` |
| QoS | Guaranteed = requests == limits (cpu+mem, every container) · Burstable = some · BestEffort = none |
| Exit codes | 137 = SIGKILL (often OOMKilled) · 143 = SIGTERM · 127 = command not found · 126 = not executable |
| PV reclaim | static PV default `Retain` · dynamic = StorageClass `reclaimPolicy` (default `Delete`) |

## 7. Architect must-knows (beyond the exam) → [08-Architect-Notes](08-Architect-Notes/README.md)
- [ ] Readiness ≠ liveness: never check dependencies in liveness; use startupProbe for slow boots
- [ ] Graceful shutdown: preStop sleep + terminationGracePeriodSeconds > drain time
- [ ] Always set requests; memory limit = request for predictability; be careful with CPU limits (throttling)
- [ ] Replicas ≥ 2 + PDB + topology spread across zones for anything user-facing
- [ ] Namespace baseline: PSA `restricted`, ResourceQuota, LimitRange, default-deny NetworkPolicy + DNS allow
- [ ] One ServiceAccount per workload, automount off unless the app calls the API, least-privilege Roles
- [ ] Secrets: encryption at rest (KMS), external secret managers, no secrets in images or Git
- [ ] New north-south traffic designs → Gateway API (ingress-nginx was retired in March 2026)
- [ ] GitOps (Argo CD/Flux) with Helm/Kustomize; promote immutable image digests; progressive delivery for risky changes
- [ ] Keep manifests on current APIs: lint in CI (kubeconform/pluto) before every cluster upgrade
