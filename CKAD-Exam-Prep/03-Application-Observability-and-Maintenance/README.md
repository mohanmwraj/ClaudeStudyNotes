# 03 — Application Observability and Maintenance (15% of the exam)

The smallest domain by weight. Its skills (reading status, events and logs, debugging, probes) are also how you rescue points in **every other domain**, so treat it as a force multiplier. Everything here targets Kubernetes v1.33+ and matches the exam environment's **v1.37** (exam logistics: [../00-Exam-Overview-and-Setup/README.md](../00-Exam-Overview-and-Setup/README.md)).

## Official competencies (CNCF CKAD curriculum)

- Understand API deprecations
- Implement probes and health checks
- Use built-in CLI tools to monitor Kubernetes applications
- Utilize container logs
- Debugging in Kubernetes

## Competency → files → exam frequency

| Competency | File(s) | Exam frequency |
|---|---|---|
| Understand API deprecations | [01-api-deprecations.md](01-api-deprecations.md), [yaml/deprecated/](yaml/deprecated/), [yaml/migrated/](yaml/migrated/) | High |
| Implement probes and health checks | [02-probes-and-health-checks.md](02-probes-and-health-checks.md), `yaml/probe-*.yaml`, [yaml/probes-all-in-one-deployment.yaml](yaml/probes-all-in-one-deployment.yaml) | High |
| Use built-in CLI tools to monitor Kubernetes applications | [03-monitoring-with-built-in-cli.md](03-monitoring-with-built-in-cli.md), [yaml/top-demo-workloads.yaml](yaml/top-demo-workloads.yaml) | High |
| Utilize container logs | [04-container-logs.md](04-container-logs.md), [yaml/logging-sidecar.yaml](yaml/logging-sidecar.yaml) | Medium |
| Debugging in Kubernetes | [05-debugging.md](05-debugging.md), [yaml/broken/](yaml/broken/), [yaml/debug-target-pod.yaml](yaml/debug-target-pod.yaml) | High |
| All of the above | [commands.md](commands.md), [practice-questions.md](practice-questions.md) | — |

## Must know — cannot skip

- [ ] Fix a manifest with a removed apiVersion: Deployment `extensions/v1beta1` → `apps/v1` **+ `spec.selector`**; Ingress → `networking.k8s.io/v1` **+ `pathType` + `backend.service.name/port`**; CronJob → `batch/v1`; PDB → `policy/v1`; HPA → `autoscaling/v2`
- [ ] Find a kind's served group/version: `kubectl api-resources | grep <kind>`, `kubectl explain <kind> | head -3`, `kubectl api-versions`
- [ ] Validate a migration with `kubectl apply --dry-run=server -f file.yaml` (the exam route is manual migration, not `kubectl convert`)
- [ ] Write liveness / readiness / startup probes with `httpGet`, `tcpSocket`, `exec` from memory. Know the defaults (0 / 10 / 1 / 1 / 3) and that `successThreshold` must be 1 for liveness/startup
- [ ] Startup budget = `failureThreshold × periodSeconds`
- [ ] Readiness failure = out of the Service endpoints, no restart. Liveness/startup failure = container killed and restarted
- [ ] Change probes on a bare Pod with `kubectl replace --force -f`; on a Deployment with `kubectl edit`/`patch` + `rollout status`
- [ ] Diagnose wrong probe port/path from `Unhealthy` events (`connection refused`, `statuscode: 404`)
- [ ] `kubectl top pod -n X --sort-by=cpu|memory --no-headers | head -1 | awk '{print $1}' > file` (with `-A` the name is column 2; needs metrics-server)
- [ ] Events: `kubectl get events --sort-by=.metadata.creationTimestamp`, `--field-selector type=Warning,involvedObject.name=x`, `kubectl events --for pod/x`
- [ ] jsonpath for `phase`, the `Ready` condition, `restartCount`, `lastState.terminated.reason/exitCode`, `qosClass`, written to a file exactly as asked
- [ ] `kubectl logs` with `-c`, `-p`, `--all-containers`, `--prefix`, `-l` (default tail 10), `--tail`, `--since`, `--timestamps`, `deploy/x`, `job/x`, and init containers via `-c`
- [ ] Status → cause → fix for Pending, ImagePullBackOff, CrashLoopBackOff, CreateContainerConfigError, OOMKilled, Error/Completed, Init:Error/Init:CrashLoopBackOff
- [ ] Exit codes 1, 126, 127, 137 (SIGKILL/OOM), 139, 143 (SIGTERM)
- [ ] `kubectl debug -it <pod> --image=busybox:1.36 --target=<container>`; `--copy-to=<new> --container=<c> -- sleep 1d`
- [ ] Temp client Pod: `kubectl run tmp --rm -it --image=busybox:1.36 --restart=Never -- wget -qO- -T 2 http://svc.ns`
- [ ] Service without endpoints: selector vs labels, `targetPort`, readiness. Check with `kubectl get endpointslices -l kubernetes.io/service-name=<svc>`
- [ ] Fix the owner (Deployment) with `kubectl set image|env|resources`, not its Pods. Deployment with 0 Pods → `kubectl describe rs`

## Nice to know (low frequency, still covered)

- gRPC probes (numeric port only), probe-level `terminationGracePeriodSeconds`, Pod readiness gates, probes on native sidecars
- The v1.37 alpha probe fields `httpGet.protocol: HTTP2` and `grpc.mode: TLS` (off by default; don't use them)
- The deprecation policy rules and beta lifetimes; deprecated vs removed; the `Warning:` header and `--warnings-as-errors`
- The `kubectl-convert` plugin (lab/real-world convenience, not a guaranteed exam tool)
- `apiserver_requested_deprecated_apis` metric, audit annotation `k8s.io/deprecated`, pluto/kubent
- Endpoints API deprecated since v1.33 → EndpointSlices; the `get endpointslices` ENDPOINTS column includes not-ready addresses
- Node logging layout (`/var/log/pods`, `/var/log/containers`), rotation (`containerLogMaxSize` 10Mi, `containerLogMaxFiles` 5), `terminationMessagePolicy: FallbackToLogsOnError`
- `kubectl debug` profiles (`general` is the default on v1.36+), node debugging, custom profiles; `kubectl port-forward`, `kubectl cp`
- Restart back-off 10 s → 300 s; container-level `restartPolicyRules` (beta v1.35); in-place Pod resize (`--subresource resize`, stable v1.35)
- RBAC `Forbidden` errors → `kubectl auth can-i ... --as=system:serviceaccount:ns:sa`

## Recommended study order (≈ 6 h)

| # | File | Time | Why in this order |
|---|---|---|---|
| 1 | [02-probes-and-health-checks.md](02-probes-and-health-checks.md) | 60 min | Highest points per minute; type every handler once |
| 2 | [01-api-deprecations.md](01-api-deprecations.md) | 45 min | Mechanical, quick wins; do the five migrations in [yaml/deprecated/](yaml/deprecated/) by hand |
| 3 | [03-monitoring-with-built-in-cli.md](03-monitoring-with-built-in-cli.md) | 40 min | `top`, events and jsonpath-to-file patterns |
| 4 | [04-container-logs.md](04-container-logs.md) | 30 min | Every `kubectl logs` flag; sidecar streaming |
| 5 | [05-debugging.md](05-debugging.md) | 75 min | Status table, exit codes, `debug`; break and fix every file in [yaml/broken/](yaml/broken/) |
| 6 | [commands.md](commands.md) | 15 min | Skim; mark what you didn't know |
| 7 | [practice-questions.md](practice-questions.md) | 2–3 h | All 🔥 first, then ⚡, then 🧊; timed |

## Files in this chapter

| File | Content |
|---|---|
| [01-api-deprecations.md](01-api-deprecations.md) | API groups/versions, maturity levels, deprecation policy, removed-API table with manifest changes, discovery commands, warnings, kubectl-convert, five migration walk-throughs, finding deprecated usage, Endpoints → EndpointSlice |
| [02-probes-and-health-checks.md](02-probes-and-health-checks.md) | Liveness/readiness/startup semantics, handlers, timing fields + formulas, readiness vs endpoints, readiness gates, sidecar probes, design rules, fixing broken probes |
| [03-monitoring-with-built-in-cli.md](03-monitoring-with-built-in-cli.md) | get/describe/events/top/wait, status fields, usage vs requests/limits, metrics-server, jsonpath/custom-columns, writing answers to files |
| [04-container-logs.md](04-container-logs.md) | Node logging architecture and rotation, every `kubectl logs` flag, init/sidecar/previous logs, sidecar streaming, termination messages, cluster-level logging |
| [05-debugging.md](05-debugging.md) | Triage flow, status/reason table, exit codes, exec/debug/profiles/port-forward/temp Pods/cp, Service & DNS steps, RBAC errors, scheduling failures, node checks |
| [commands.md](commands.md) | Grouped command reference for the whole chapter |
| [practice-questions.md](practice-questions.md) | 28 exam-style tasks with setup, solution and verification, plus the must-know summary |

## yaml/ index

| File | What it shows |
|---|---|
| [yaml/probe-liveness-http.yaml](yaml/probe-liveness-http.yaml) | httpGet liveness probe: named port, custom header, every timing field |
| [yaml/probe-readiness-exec.yaml](yaml/probe-readiness-exec.yaml) | exec readiness probe + Service; toggle readiness and watch EndpointSlice conditions |
| [yaml/probe-tcp.yaml](yaml/probe-tcp.yaml) | tcpSocket readiness/liveness for Redis |
| [yaml/probe-startup.yaml](yaml/probe-startup.yaml) | startupProbe budget (12 × 5 s) for an app that needs 30 s to start |
| [yaml/probe-grpc.yaml](yaml/probe-grpc.yaml) | gRPC liveness/readiness probes (etcd, official docs example) |
| [yaml/probes-all-in-one-deployment.yaml](yaml/probes-all-in-one-deployment.yaml) | Deployment with startup + liveness + readiness, probe-level grace period, native sidecar with probes, Service |
| [yaml/logging-sidecar.yaml](yaml/logging-sidecar.yaml) | Log streaming sidecar: classic (2nd container) and native (`initContainers` + `restartPolicy: Always`) |
| [yaml/debug-target-pod.yaml](yaml/debug-target-pod.yaml) | Shell-less `pause` Pod and an nginx Pod for `kubectl debug` practice |
| [yaml/top-demo-workloads.yaml](yaml/top-demo-workloads.yaml) | Namespace `obs-top` with CPU-heavy, memory-heavy and idle Deployments for `kubectl top` |
| [yaml/deprecated/deployment-extensions-v1beta1.yaml](yaml/deprecated/deployment-extensions-v1beta1.yaml) | LEGACY Deployment (`extensions/v1beta1`, no selector) |
| [yaml/deprecated/ingress-v1beta1.yaml](yaml/deprecated/ingress-v1beta1.yaml) | LEGACY Ingress (`networking.k8s.io/v1beta1`, flat backends, no pathType) |
| [yaml/deprecated/cronjob-v1beta1.yaml](yaml/deprecated/cronjob-v1beta1.yaml) | LEGACY CronJob (`batch/v1beta1`) |
| [yaml/deprecated/pdb-v1beta1.yaml](yaml/deprecated/pdb-v1beta1.yaml) | LEGACY PodDisruptionBudget (`policy/v1beta1`) |
| [yaml/deprecated/hpa-v2beta2.yaml](yaml/deprecated/hpa-v2beta2.yaml) | LEGACY HPA (`autoscaling/v2beta2`, plus the older v2beta1 style) |
| [yaml/migrated/deployment-apps-v1.yaml](yaml/migrated/deployment-apps-v1.yaml) | FIXED `apps/v1` Deployment with the required selector |
| [yaml/migrated/ingress-v1.yaml](yaml/migrated/ingress-v1.yaml) | FIXED `networking.k8s.io/v1` Ingress (pathType, `service.port.number/name`, defaultBackend, ingressClassName) |
| [yaml/migrated/cronjob-batch-v1.yaml](yaml/migrated/cronjob-batch-v1.yaml) | FIXED `batch/v1` CronJob (+ optional `timeZone`) |
| [yaml/migrated/pdb-policy-v1.yaml](yaml/migrated/pdb-policy-v1.yaml) | FIXED `policy/v1` PodDisruptionBudget |
| [yaml/migrated/hpa-autoscaling-v2.yaml](yaml/migrated/hpa-autoscaling-v2.yaml) | FIXED `autoscaling/v2` HPA |
| [yaml/broken/crashloop-pod.yaml](yaml/broken/crashloop-pod.yaml) | CrashLoopBackOff: missing env var (exit 1) |
| [yaml/broken/imagepull-pod.yaml](yaml/broken/imagepull-pod.yaml) | ErrImagePull → ImagePullBackOff: wrong tag |
| [yaml/broken/pending-resources-pod.yaml](yaml/broken/pending-resources-pod.yaml) | Pending: requests larger than any node |
| [yaml/broken/pending-other-causes.yaml](yaml/broken/pending-other-causes.yaml) | Pending: nodeSelector mismatch, missing PVC |
| [yaml/broken/configerror-pod.yaml](yaml/broken/configerror-pod.yaml) | CreateContainerConfigError: missing ConfigMap key |
| [yaml/broken/oom-pod.yaml](yaml/broken/oom-pod.yaml) | OOMKilled (exit 137): limit below real usage |
| [yaml/broken/wrong-probe-pod.yaml](yaml/broken/wrong-probe-pod.yaml) | Liveness on the wrong port + readiness on the wrong path |
| [yaml/broken/bad-command-pod.yaml](yaml/broken/bad-command-pod.yaml) | RunContainerError / StartError (exit 128): binary not found |
| [yaml/broken/init-crash-pod.yaml](yaml/broken/init-crash-pod.yaml) | Init:Error → Init:CrashLoopBackOff: typo in the init command (exit 127) |
| [yaml/broken/service-no-endpoints.yaml](yaml/broken/service-no-endpoints.yaml) | Service selector typo + wrong targetPort |

Each `yaml/broken/` file starts with a comment that names the bug and the fix. The `yaml/deprecated/` files are legacy on purpose: read them, never apply them.

## Related chapters

- [../00-Exam-Overview-and-Setup/README.md](../00-Exam-Overview-and-Setup/README.md): exam environment, aliases, lab setup (metrics-server, ingress controller)
- [../01-Application-Design-and-Build/README.md](../01-Application-Design-and-Build/README.md): sidecar/init patterns, volumes, Jobs/CronJobs
- [../02-Application-Deployment/README.md](../02-Application-Deployment/README.md): rollouts, `rollout status/undo`
- [../04-Application-Environment-Configuration-and-Security/README.md](../04-Application-Environment-Configuration-and-Security/README.md): requests/limits/QoS, ConfigMaps/Secrets, RBAC, SecurityContext
- [../05-Services-and-Networking/README.md](../05-Services-and-Networking/README.md): Services, EndpointSlices, Ingress, NetworkPolicies
- [../06-Cross-Cutting-Skills-and-Bonus-Topics/README.md](../06-Cross-Cutting-Skills-and-Bonus-Topics/README.md): jsonpath/custom-columns, HPA, PDB
- [../08-Architect-Notes/README.md](../08-Architect-Notes/README.md): production observability and reliability design
