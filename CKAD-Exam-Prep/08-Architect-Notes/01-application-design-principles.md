# 01 · Application design principles on Kubernetes

> **Exam link:** [01 · Application Design and Build](../01-Application-Design-and-Build/README.md) (images, workload types, multi-container pods, volumes) · [04 · Environment, Configuration and Security](../04-Application-Environment-Configuration-and-Security/README.md) (ConfigMaps, Secrets). The exam tests the fields; this file covers the decisions behind them.

Most production incidents on Kubernetes are design problems that YAML cannot fix later: state hidden in a container filesystem, a "pod" that is really three services, an image tag that silently changed, config baked into images. Decide these before the first manifest exists.

## Principles

1. **Design for disposability.** Any pod can be killed at any time (rollout, node drain, eviction, autoscaler scale-in, spot reclaim). Start fast, stop gracefully on SIGTERM, keep no state you cannot lose.
2. **One scaling unit per Deployment.** Things that scale, fail or release independently get their own workload. A pod is a co-scheduled group of processes, not a VM.
3. **Build once, promote the same artifact.** One image per commit, referenced by digest, promoted unchanged from dev to prod. Environments differ only in injected configuration.
4. **Declare intent, let the platform enforce it.** Requests, probes, security context, disruption budget and spread constraints are how you tell the scheduler and controllers what "healthy" means. Undeclared means unprotected.
5. **State is a first-class design decision.** Keep it in as few, well-run places as possible: a managed service first, a mature operator second, a hand-rolled StatefulSet last (see [08](08-storage-and-stateful-workloads.md)).
6. **Use platform primitives instead of reinventing them** (DNS service discovery, Jobs, CronJobs, probes, PDBs) - but keep business logic in code, not in YAML or shell one-liners.
7. **Least privilege by default.** Non-root, read-only root filesystem, no API token unless needed (see [04](04-security-architecture.md)).

## Recommended defaults

| Area | Default | Why |
|---|---|---|
| Stateless service | `Deployment`, >= 3 replicas, HPA, PDB | survives a node and a zone loss, scales on load |
| Image reference | `registry/app@sha256:<digest>` (tag kept as a label) | immutable, reproducible rollbacks; "only the digest will be used for pulling" |
| Image content | minimal base (distroless/static or slim), non-root `USER`, one process | fewer CVEs, smaller attack surface, clean signals |
| Ports | app listens on a non-privileged port (>= 1024) on `0.0.0.0` | runs as non-root without `NET_BIND_SERVICE` |
| Config | ConfigMap mounted as files (structured) or env (scalars), generated with a content hash | config change = new rollout = rollback-able |
| Secrets | mounted files from an external secret manager, never env when the app can read files | rotation without restart, less leakage |
| Logs | JSON to stdout/stderr | node agents ship them; no files to rotate |
| Admin tasks | `Job` (migrations) and `CronJob` (schedules) | retries, history, deadlines, RBAC-scoped |
| Helpers | native sidecar (`initContainers` + `restartPolicy: Always`, GA v1.33) | ordered start/stop, does not block Jobs |
| Bare Pods | never in production | no rescheduling, no rollout, no self-healing |

## 12-factor on Kubernetes

| Factor | Kubernetes mechanism | Architect note |
|---|---|---|
| I. Codebase | one repo per deployable + a deploy repo (GitOps) | manifests are versioned like code |
| II. Dependencies | the image bundles them; multi-stage builds; base image pinned by digest | rebuild regularly to pick up CVE fixes |
| III. Config | ConfigMap / Secret via env or volume | never one image per environment |
| IV. Backing services | Service DNS names, `ExternalName`, credentials in Secrets | swap a DB by changing config, not code |
| V. Build, release, run | CI builds the image; Helm/Kustomize render the release (digest + config); the cluster runs it | every release is a revision: `kubectl rollout history` |
| VI. Processes | stateless pods; sessions in Redis/DB | no sticky sessions as a correctness requirement |
| VII. Port binding | `containerPort` + Service; named ports | the app owns its HTTP server |
| VIII. Concurrency | replicas + HPA/KEDA; one Deployment per process type (web, worker, scheduler) | scale each type on its own signal |
| IX. Disposability | `startupProbe`, SIGTERM handling, `preStop`, `terminationGracePeriodSeconds` | see [02](02-reliability-and-high-availability.md) |
| X. Dev/prod parity | same base manifests + overlays; same image; kind/minikube locally | parity of versions matters (CRDs, API versions) |
| XI. Logs | stdout/stderr event streams; node-level agent | structured, with trace IDs ([07](07-observability.md)) |
| XII. Admin processes | `Job`/`CronJob`, `kubectl debug` | not `kubectl exec` scripts on live pods |

Beyond the original twelve: expose health endpoints, emit telemetry (OpenTelemetry), run as non-root, degrade gracefully when a dependency is down, and make every operation idempotent (pods get retried).

## Decision tables / trade-offs

### Stateless or stateful?

| Question | Yes means |
|---|---|
| Must data survive a pod restart or reschedule? | It is state: managed service > operator > StatefulSet + PVC |
| Can any replica serve any request? | `Deployment` |
| Do replicas need stable names or peer discovery (quorum, leader election, sharding)? | `StatefulSet` + headless Service (usually via an operator) |
| Is it only a cache you can rebuild? | `Deployment` + Redis or `emptyDir` with `sizeLimit`; accept cold starts |
| Is it a file someone uploads? | object storage (S3/GCS/Blob), not a PVC |

### Choosing the workload type at design time

| Workload shape | Kind | Design these fields | Pitfall |
|---|---|---|---|
| HTTP/gRPC service | `Deployment` | probes, `maxSurge`/`maxUnavailable`, PDB, HPA | declaring `replicas` in Git while an HPA owns it |
| Queue consumer | `Deployment` (+ KEDA) | grace period >= longest message, idempotency | very long tasks: use a Job/ScaledJob instead |
| Clustered stateful (DB, Kafka) | `StatefulSet` via an operator | `serviceName`, `volumeClaimTemplates`, PVC retention | hand-rolled failover and backups |
| Per-node agent (logs, metrics, CNI) | `DaemonSet` | tolerations, small requests, `updateStrategy` | requests are paid on every node |
| Batch, run to completion | `Job` | `backoffLimit`, `activeDeadlineSeconds`, `ttlSecondsAfterFinished`, `podFailurePolicy`, Indexed mode | non-idempotent work retried up to 6 times (`backoffLimit` default) |
| Scheduled task | `CronJob` | `timeZone`, `concurrencyPolicy: Forbid`, `startingDeadlineSeconds` | default `concurrencyPolicy: Allow` overlaps slow runs |
| One-off admin (migration) | `Job` as a deploy hook | low `backoffLimit`, backward-compatible change | migrating inside an init container of N replicas |

### Configuration channel

| Mechanism | Updates without restart | Exposure | Use for |
|---|---|---|---|
| env (`valueFrom`) | no (pod restart needed) | process environment, child processes, crash dumps, `/proc/<pid>/environ` | non-secret scalars, feature flags |
| ConfigMap/Secret volume | yes, eventually consistent (not with `subPath`) | files; Secret volumes are tmpfs on the node | structured config, certificates, credentials |
| Secrets Store CSI volume | yes (rotation feature) | file only, no Secret object unless sync is enabled | secrets that should not live in etcd |
| Runtime fetch via SDK (Vault, cloud secret manager) | yes | process memory | dynamic, short-lived credentials |
| Baked into the image | never | everyone with pull access | nothing environment-specific, ever |

Prefer **immutable, hash-named ConfigMaps** (Kustomize `configMapGenerator`, or Helm `checksum/config` annotation) over editing a ConfigMap in place: an in-place edit reaches running pods at different times and leaves no rollback point.

### Tags versus digests

| | Tag (`app:1.4.2`) | Digest (`app@sha256:...`) |
|---|---|---|
| Mutability | can be re-pushed to point elsewhere | content address, immutable |
| Rollback | may not restore the same bits | exact |
| Readability | human-friendly | opaque, so keep the tag in `app.kubernetes.io/version` |
| Policy enforcement | weak | admission policies can require digests and verify signatures |

Use both: CI tags `1.4.2` and `git-<sha>`, the deploy repo pins the digest (Kustomize `images[].digest`, Argo CD Image Updater or Flux image automation can write it). With `name:tag@sha256:...` Kubernetes pulls by digest only. Enable tag immutability in your registry if it supports it (verify current status per registry).

> Pre-pulled image caveat: with `imagePullPolicy: IfNotPresent`, a private image already on a node could historically be started by a pod that has no pull credentials. Kubelet image-pull credential verification (`KubeletEnsureSecretPulledImages`, beta and on by default in v1.35) closes this; on older clusters use the `AlwaysPullImages` admission plugin in multi-tenant clusters.

### Sidecar, node agent or library?

| Need | Sidecar | Node-level (DaemonSet / ambient) | In-process library |
|---|---|---|---|
| Log shipping | only if the app cannot write to stdout | default (Fluent Bit, Vector, OTel agent) | - |
| mTLS, retries, traffic policy | mesh sidecar (Istio sidecar mode, Linkerd) | Istio ambient (ztunnel per node), Cilium | gRPC/xDS clients, language-specific |
| Secrets delivery | Vault Agent | Secrets Store CSI driver | cloud/Vault SDK |
| Metrics | exporter for third-party software | node exporter, kubelet/cAdvisor | Prometheus/OTel client library (default) |
| Cloud DB with IAM auth | auth proxy sidecar | - | connector library |

Every sidecar multiplies cost (its requests times every replica), adds a network hop or a start-up dependency, and couples upgrades (a sidecar-mode mesh upgrade restarts every pod). Prefer node-level or in-process options when they exist.

### Init work versus start-up work

| Work | Put it in | Why |
|---|---|---|
| Wait for a dependency | application retry with backoff and timeout | a dependency can also fail after start; init loops hide outages |
| Schema migration | a `Job` run before the rollout (Helm hook, Argo CD `PreSync`) | N replicas would race N init containers; migrations must be backward compatible (expand/contract) |
| Fetch config, certificates, model files | init container, Secrets Store CSI, or an `image` volume (GA v1.36) | runs before the app, once per pod |
| Warm caches, JIT, load data | the app itself, gated by `startupProbe` + readiness | no traffic until warm, no liveness kills while booting |
| Fix file permissions | `fsGroup` + `fsGroupChangePolicy: OnRootMismatch` | a privileged `chown` init container breaks PSA `restricted` |
| Long-running helper | native sidecar | starts before, stops after the app containers |

## Anti-patterns

| Anti-pattern | Why it hurts | Do instead |
|---|---|---|
| App + its database in one pod | data dies with the pod; cannot scale one without the other | separate workloads; managed DB or operator |
| "Pod as VM": several services in one pod | coupled scaling, releases and failure | one Deployment per service |
| Shell script as PID 1 starting two processes | signals not forwarded, no supervision, zombie processes | one process per container; exec-form `ENTRYPOINT`, or a tiny init such as tini |
| Classic sidecar (regular container) in a Job | Job never completes | native sidecar (`restartPolicy: Always` in `initContainers`) |
| App assumes its proxy is up (no ordering) | first requests fail at start-up | native sidecar with a `startupProbe` |
| Sidecars without requests/limits | scheduler under-counts; one unsized container turns a Guaranteed pod into Burstable | size every container |
| `until nslookup db; do sleep 2; done` init container | blocks forever, no timeout, hides outages | app-level retry with backoff; alert on readiness |
| `:latest` or re-pushed tags | non-reproducible rollouts, `imagePullPolicy` defaults to `Always` | immutable tags + digests |
| Environment-specific images | what you tested is not what you ship | one image, injected config |
| Secrets in ConfigMaps, images, Git, or command-line args | leaked through RBAC `view`, registries, history, `ps` | Secret objects fed by a secret manager ([04](04-security-architecture.md)) |
| Writing to the container filesystem | lost on restart; breaks `readOnlyRootFilesystem` | `emptyDir` with `sizeLimit` for scratch, PVC or object storage for data |

## Reference YAML

Full, hardened service: [`yaml/production-deployment-template.yaml`](yaml/production-deployment-template.yaml).

Native sidecar with start-up ordering (fragment of `spec.template.spec`):

```yaml
initContainers:
- name: config-agent                 # native sidecar: init container + restartPolicy Always
  image: registry.example.com/platform/config-agent:2.1.0
  restartPolicy: Always
  startupProbe:                      # app containers start only after this succeeds
    httpGet:
      path: /healthz
      port: 9090
    periodSeconds: 2
    failureThreshold: 15
  resources:
    requests:
      cpu: 10m
      memory: 32Mi
    limits:
      memory: 32Mi
  volumeMounts:
  - name: rendered-config
    mountPath: /config
containers:
- name: app
  image: registry.example.com/shop/api:1.4.2@sha256:4bf9d34f1c1d5b8e3fa2c9a0e1b7d6c5f4e3d2c1b0a9f8e7d6c5b4a3f2e1d0c9   # example digest
  volumeMounts:
  - name: rendered-config
    mountPath: /etc/api
    readOnly: true
volumes:
- name: rendered-config
  emptyDir:
    sizeLimit: 16Mi
```

Config as files and scalars, credentials as a read-only Secret volume (fragment of a container + pod spec):

```yaml
containers:
- name: app
  image: registry.example.com/shop/api:1.4.2
  env:
  - name: LOG_LEVEL                  # small scalar: env is fine
    valueFrom:
      configMapKeyRef:
        name: api-config
        key: logLevel
  - name: DB_PASSWORD_FILE           # point the app at a file, not at a value
    value: /var/run/secrets/db/password
  volumeMounts:
  - name: config
    mountPath: /etc/api
    readOnly: true
  - name: db-credentials
    mountPath: /var/run/secrets/db
    readOnly: true
volumes:
- name: config
  configMap:
    name: api-config
- name: db-credentials
  secret:
    secretName: api-db
    defaultMode: 0400
```

Hash-suffixed, immutable ConfigMap and digest pinning with Kustomize:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: shop
resources:
- deployment.yaml
configMapGenerator:
- name: api-config                   # rendered as api-config-<hash>; references are rewritten
  files:
  - config/app.yaml
  literals:
  - logLevel=info
  options:
    immutable: true
images:
- name: registry.example.com/shop/api
  digest: sha256:4bf9d34f1c1d5b8e3fa2c9a0e1b7d6c5f4e3d2c1b0a9f8e7d6c5b4a3f2e1d0c9   # example digest
```

Schema migration as a pre-deploy Job (not an init container):

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: api-migrate-1-4-2
  namespace: shop
  annotations:
    argocd.argoproj.io/hook: PreSync                          # Argo CD; Helm: helm.sh/hook: pre-upgrade
    argocd.argoproj.io/hook-delete-policy: BeforeHookCreation
spec:
  backoffLimit: 1                    # a failing migration should stop the release, not retry 6 times
  activeDeadlineSeconds: 600
  ttlSecondsAfterFinished: 86400
  template:
    spec:
      restartPolicy: Never
      automountServiceAccountToken: false
      securityContext:
        runAsNonRoot: true
        seccompProfile:
          type: RuntimeDefault
      containers:
      - name: migrate
        image: registry.example.com/shop/api:1.4.2
        args: ["migrate", "--to=latest"]
        securityContext:
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: true
          capabilities:
            drop: ["ALL"]
```

## Checklist

- [ ] Each independently scaled/released component has its own workload; no bare Pods.
- [ ] Workload kind chosen deliberately (table above); stateful parts have an owner and a backup plan.
- [ ] Images: minimal base, non-root `USER`, exec-form `ENTRYPOINT`, deployed by digest; no `:latest`.
- [ ] One image promoted across environments; only config differs.
- [ ] Config split: ConfigMap (non-secret) vs Secret from a secret manager; nothing secret in Git or images.
- [ ] Config changes roll out as new revisions (hash-suffixed or checksum-annotated).
- [ ] App starts fast, handles SIGTERM, and drains in-flight work.
- [ ] Logs are structured JSON on stdout/stderr.
- [ ] Migrations run as a Job before rollout and are backward compatible.
- [ ] Helpers are native sidecars with requests/limits and a `startupProbe` when start order matters.
- [ ] No init container waits indefinitely on a dependency.

## References

- Workloads overview: https://kubernetes.io/docs/concepts/workloads/
- Sidecar containers: https://kubernetes.io/docs/concepts/workloads/pods/sidecar-containers/
- Init containers: https://kubernetes.io/docs/concepts/workloads/pods/init-containers/
- Images (tags, digests, pull policy, credential verification): https://kubernetes.io/docs/concepts/containers/images/
- Configuration good practices (blog): https://kubernetes.io/blog/2025/11/25/configuration-good-practices/
- Secrets: https://kubernetes.io/docs/concepts/configuration/secret/
- Kustomize (configMapGenerator, images): https://kubernetes.io/docs/tasks/manage-kubernetes-objects/kustomization/
- Recommended labels: https://kubernetes.io/docs/concepts/overview/working-with-objects/common-labels/
- Image volumes: https://kubernetes.io/docs/tasks/configure-pod-container/image-volumes/
- The Twelve-Factor App: https://12factor.net/
