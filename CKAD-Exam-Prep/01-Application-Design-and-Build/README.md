# 01: Application Design and Build (20 %)

> **Exam weight: 20 %.** Content targets Kubernetes **v1.37**, the current exam version; everything written for v1.33+ still applies. Exam format, rules and environment: [../00-Exam-Overview-and-Setup/README.md](../00-Exam-Overview-and-Setup/README.md).

## Official competencies (CNCF curriculum)

- Define, build and modify container images
- Choose and use the right workload resource (Deployment, DaemonSet, CronJob, etc.)
- Understand multi-container Pod design patterns (e.g. sidecar, init and others)
- Utilize persistent and ephemeral volumes

## Competency → files → exam frequency

| Competency | Files | Exam frequency |
|---|---|---|
| Define, build and modify container images | [01-container-images.md](01-container-images.md), [yaml/images/](yaml/images/), practice Q1, Q2, Q9, Q19, Q26 | **High** |
| Choose and use the right workload resource | [03-workload-resources.md](03-workload-resources.md) (decision table), [02-pod-fundamentals.md](02-pod-fundamentals.md), [04-jobs-and-cronjobs.md](04-jobs-and-cronjobs.md), [05-daemonsets-and-statefulsets.md](05-daemonsets-and-statefulsets.md), practice Q3, Q4, Q10, Q11, Q18, Q20, Q21, Q24, Q25, Q28, Q30 | **High** (Jobs/CronJobs, Pods) · **Medium** (DaemonSet) · **Low-Medium** (StatefulSet, ReplicaSet) |
| Understand multi-container Pod design patterns | [06-multi-container-pods.md](06-multi-container-pods.md), practice Q5, Q6, Q12, Q13, Q14, Q17, Q22, Q29 | **High** (init, sidecar) · **Medium** (adapter, ambassador) |
| Utilize persistent and ephemeral volumes | [07-ephemeral-volumes.md](07-ephemeral-volumes.md), [08-persistent-volumes.md](08-persistent-volumes.md), practice Q7, Q8, Q15, Q16, Q23, Q27 | **High** (emptyDir, PV/PVC) · **Medium** (StorageClass, hostPath) · **Low** (generic ephemeral, image volumes) |

## Must know: cannot skip

- [ ] Edit a Dockerfile, then `podman build -t name:tag .` / `docker build -t name:tag .` (context `.`, `-f` for other names, several `-t` flags)
- [ ] `podman save -o x.tar img` (docker-archive) vs `podman save --format oci-archive -o x.tar img`; `docker save`; `load -i`; `tag`; `push` (`--tls-verify=false` for HTTP registries); check the tools with `which podman docker`
- [ ] Run and inspect a container: `run -d --name -p --user -e`, `ps`, `logs > file 2>&1`, `image inspect --format`
- [ ] ENTRYPOINT/CMD ↔ `command`/`args`, all four combinations (`command` alone drops the CMD)
- [ ] `kubectl run` flags: `--image --port --labels --env --restart=Never --rm -it --expose --dry-run=client -o yaml`, and `--command --` vs `--`
- [ ] `imagePullPolicy` defaults (`:latest` or no tag → Always, otherwise IfNotPresent)
- [ ] Pod immutability: only image, labels/annotations, tolerations (add) and activeDeadlineSeconds change in place; anything else goes through `kubectl replace --force -f`
- [ ] Lifecycle hooks (postStart, preStop incl. the `sleep` action) and `terminationGracePeriodSeconds`
- [ ] Pick the right workload kind from the task's wording (decision table in [03](03-workload-resources.md))
- [ ] Job fields: `completions`, `parallelism`, `backoffLimit`, `activeDeadlineSeconds`, `ttlSecondsAfterFinished`; pod `restartPolicy` Never|OnFailure
- [ ] CronJob: schedule syntax, `concurrencyPolicy`, history limits, `suspend`; `kubectl create job x --from=cronjob/y`
- [ ] DaemonSet from converted Deployment YAML (delete `replicas` + `strategy`) + control-plane toleration
- [ ] StatefulSet + headless Service + `volumeClaimTemplates` (PVC `<claim>-<sts>-<n>`, pod DNS `<pod>.<svc>.<ns>.svc.cluster.local`)
- [ ] Init containers; **native sidecar** (`initContainers` + `restartPolicy: Always`); classic sidecar; `kubectl logs/exec -c`
- [ ] `emptyDir` (incl. `medium: Memory`, `sizeLimit`) shared between containers; `hostPath` types
- [ ] PV/PVC/StorageClass binding rules; `storageClassName: ""` vs omitted; default class annotation; `WaitForFirstConsumer` → Pending is normal

## Nice to know (low frequency, still covered)

- Multi-stage builds, `--target`, `--build-arg`, layer caching, `.dockerignore`, podman's OCI build format dropping `HEALTHCHECK` (→ [01](01-container-images.md))
- Pod phases, the STATUS column cheat-sheet, exit codes, static pods, in-place resize (GA v1.35) (→ [02](02-pod-fundamentals.md))
- ReplicaSet adoption, legacy ReplicationController, ownerReferences and cascading deletion (→ [03](03-workload-resources.md))
- Indexed Jobs, `podFailurePolicy`, `backoffLimitPerIndex`/`maxFailedIndexes`, `successPolicy`, `podReplacementPolicy`, CronJob `timeZone`/`startingDeadlineSeconds` (→ [04](04-jobs-and-cronjobs.md))
- DaemonSet `maxSurge`/OnDelete; StatefulSet `partition`, `podManagementPolicy: Parallel`, PVC retention policy, `ordinals.start`, `maxUnavailable` (beta) (→ [05](05-daemonsets-and-statefulsets.md))
- Adapter and ambassador patterns, `shareProcessNamespace`, startup/shutdown ordering details (→ [06](06-multi-container-pods.md))
- projected/downwardAPI volumes, `subPath`/`subPathExpr`, `recursiveReadOnly`, generic ephemeral volumes, image volumes (stable v1.36) (→ [07](07-ephemeral-volumes.md))
- Volume expansion, reclaim policies and reusing `Released` PVs, `local` PVs, RWOP, PVC troubleshooting table (→ [08](08-persistent-volumes.md))

## Recommended study order

| # | File | Time | Focus |
|---|---|---|---|
| 1 | [02-pod-fundamentals.md](02-pod-fundamentals.md) | 45 min | `kubectl run` patterns, immutability, hooks; every later file builds on it |
| 2 | [01-container-images.md](01-container-images.md) | 60 min | hands-on: build, tag, save (OCI), push, run with podman **and** docker |
| 3 | [03-workload-resources.md](03-workload-resources.md) | 20 min | the decision table and "exam phrasing → resource" |
| 4 | [04-jobs-and-cronjobs.md](04-jobs-and-cronjobs.md) | 45 min | fields, defaults, schedule syntax, Never vs OnFailure |
| 5 | [06-multi-container-pods.md](06-multi-container-pods.md) | 45 min | init, native vs classic sidecar, adapter, ambassador |
| 6 | [07-ephemeral-volumes.md](07-ephemeral-volumes.md) | 30 min | emptyDir, hostPath, subPath |
| 7 | [08-persistent-volumes.md](08-persistent-volumes.md) | 45 min | binding rules, StorageClass, Pending troubleshooting |
| 8 | [05-daemonsets-and-statefulsets.md](05-daemonsets-and-statefulsets.md) | 40 min | conversion from a Deployment, headless Service, partition |
| 9 | [practice-questions.md](practice-questions.md) | 2.5–3 h | do Q1–Q9 twice; time yourself |
| 10 | [commands.md](commands.md) | 15 min | final skim before the exam |

## Files in this chapter

| File | Content |
|---|---|
| [01-container-images.md](01-container-images.md) | Dockerfile reference, shell vs exec form, caching, multi-stage, podman vs docker, archive formats, ENTRYPOINT/CMD ↔ command/args, imagePullPolicy, private registries, best practices |
| [02-pod-fundamentals.md](02-pod-fundamentals.md) | Pod anatomy, container fields, restartPolicy, phases/states/STATUS, hooks, graceful shutdown, labels, namespaces, static pods, mutable fields + `replace --force` |
| [03-workload-resources.md](03-workload-resources.md) | decision table for Pod / ReplicaSet / Deployment / StatefulSet / DaemonSet / Job / CronJob / ReplicationController, phrasing hints, update strategies |
| [04-jobs-and-cronjobs.md](04-jobs-and-cronjobs.md) | every Job field, Never vs OnFailure, Indexed Jobs, failure policies, CronJob fields, schedule syntax and common schedules |
| [05-daemonsets-and-statefulsets.md](05-daemonsets-and-statefulsets.md) | DaemonSet scheduling, tolerations, update strategies; StatefulSet identity, storage, policies, partition; Deployment → DS/STS conversion |
| [06-multi-container-pods.md](06-multi-container-pods.md) | init containers, native vs classic sidecars, ambassador, adapter, shared namespaces, ordering, common tasks |
| [07-ephemeral-volumes.md](07-ephemeral-volumes.md) | emptyDir, hostPath types, configMap/secret/downwardAPI/projected overview, generic ephemeral, CSI ephemeral, image volumes, volumeMounts options |
| [08-persistent-volumes.md](08-persistent-volumes.md) | PV/PVC/StorageClass, access modes, reclaim policies, binding rules, binding modes, expansion, Pending troubleshooting, data persistence checks |
| [commands.md](commands.md) | grouped command reference for the whole chapter |
| [practice-questions.md](practice-questions.md) | 30 exam-style tasks with solutions and verification + must-know summary |

## yaml/ index

Apply any file with `kubectl apply -f yaml/<file>` (each file's header comment explains how to test it).

| File | What it shows |
|---|---|
| [yaml/images/Dockerfile](yaml/images/Dockerfile) | every common Dockerfile instruction; non-root busybox httpd on 8080 |
| [yaml/images/Dockerfile.nginx](yaml/images/Dockerfile.nginx) | minimal exam-style Dockerfile (nginx + content) |
| [yaml/images/Dockerfile.multistage](yaml/images/Dockerfile.multistage) | multi-stage Go build into `scratch`, `ARG` per stage, `--target` |
| [yaml/images/index.html](yaml/images/index.html) | page served by the image examples |
| [yaml/images/app/main.go](yaml/images/app/main.go), [yaml/images/app/go.mod](yaml/images/app/go.mod) | tiny Go HTTP app for the multi-stage build |
| [yaml/images/.dockerignore](yaml/images/.dockerignore) | build-context exclusions |
| [yaml/images/pod-local-image.yaml](yaml/images/pod-local-image.yaml) | running a locally built image (`localhost/` name, pull policy, non-root) |
| [yaml/pod-basic.yaml](yaml/pod-basic.yaml) | pod anatomy: labels, annotations, named port, env + downward API, resources |
| [yaml/pod-command-args.yaml](yaml/pod-command-args.yaml) | args-only, command-only, command+args, `$(VAR)` expansion, nginx args |
| [yaml/pod-lifecycle-hooks.yaml](yaml/pod-lifecycle-hooks.yaml) | postStart exec, preStop sleep action, grace period |
| [yaml/static-pod.yaml](yaml/static-pod.yaml) | static pod manifest for `/etc/kubernetes/manifests` |
| [yaml/deployment.yaml](yaml/deployment.yaml) | Deployment with strategy, change-cause, readiness probe |
| [yaml/replicaset.yaml](yaml/replicaset.yaml) | ReplicaSet with `matchLabels` + `matchExpressions` |
| [yaml/replicationcontroller-legacy.yaml](yaml/replicationcontroller-legacy.yaml) | legacy ReplicationController (map selector) |
| [yaml/daemonset.yaml](yaml/daemonset.yaml) | DaemonSet with control-plane toleration, RollingUpdate, read-only hostPath |
| [yaml/statefulset-with-headless-svc.yaml](yaml/statefulset-with-headless-svc.yaml) | headless Service + StatefulSet + volumeClaimTemplates + partition + retention policy |
| [yaml/job.yaml](yaml/job.yaml) | Job: completions, parallelism, backoffLimit, activeDeadlineSeconds, TTL |
| [yaml/job-parallel-indexed.yaml](yaml/job-parallel-indexed.yaml) | Indexed Job using `JOB_COMPLETION_INDEX` |
| [yaml/job-pod-failure-policy.yaml](yaml/job-pod-failure-policy.yaml) | podFailurePolicy (FailJob/Ignore) and backoffLimitPerIndex/maxFailedIndexes |
| [yaml/job-with-native-sidecar.yaml](yaml/job-with-native-sidecar.yaml) | Job that completes despite a running native sidecar |
| [yaml/cronjob.yaml](yaml/cronjob.yaml) | CronJob with schedule, timeZone, concurrencyPolicy, deadlines, history limits |
| [yaml/init-container.yaml](yaml/init-container.yaml) | init containers: wait for a Service, then prepare content |
| [yaml/sidecar-native.yaml](yaml/sidecar-native.yaml) | native sidecar with startupProbe and readinessProbe |
| [yaml/sidecar-classic-logging.yaml](yaml/sidecar-classic-logging.yaml) | classic log-tailing sidecar |
| [yaml/ambassador.yaml](yaml/ambassador.yaml) | ambassador: app → localhost → nginx proxy → remote Service |
| [yaml/adapter.yaml](yaml/adapter.yaml) | adapter: `key=value` log lines → JSON lines |
| [yaml/pod-shared-process-namespace.yaml](yaml/pod-shared-process-namespace.yaml) | `shareProcessNamespace` for cross-container signalling and inspection |
| [yaml/emptydir.yaml](yaml/emptydir.yaml) | disk-backed emptyDir shared by two containers, `sizeLimit` |
| [yaml/emptydir-memory.yaml](yaml/emptydir-memory.yaml) | memory-backed emptyDir (tmpfs) + limits |
| [yaml/hostpath.yaml](yaml/hostpath.yaml) | hostPath `DirectoryOrCreate`, `FileOrCreate`, `File` |
| [yaml/projected-volume.yaml](yaml/projected-volume.yaml) | projected configMap + secret + downwardAPI + serviceAccountToken |
| [yaml/pod-subpath.yaml](yaml/pod-subpath.yaml) | `subPath` (one ConfigMap key as a file) and `subPathExpr` |
| [yaml/pv-pvc-pod-static.yaml](yaml/pv-pvc-pod-static.yaml) | static PV + PVC (+ selector) + Pod |
| [yaml/storageclass.yaml](yaml/storageclass.yaml) | StorageClass (Retain, WaitForFirstConsumer, expansion) + no-provisioner class |
| [yaml/pvc-dynamic.yaml](yaml/pvc-dynamic.yaml) | PVC using the default StorageClass + Pod |
| [yaml/generic-ephemeral-volume.yaml](yaml/generic-ephemeral-volume.yaml) | generic ephemeral volume (PVC owned by the pod) |

Related chapters: deployments and rollouts → [../02-Application-Deployment/README.md](../02-Application-Deployment/README.md) · probes, logs, debugging → [../03-Application-Observability-and-Maintenance/README.md](../03-Application-Observability-and-Maintenance/README.md) · ConfigMaps, Secrets, ServiceAccounts, security contexts, resources → [../04-Application-Environment-Configuration-and-Security/README.md](../04-Application-Environment-Configuration-and-Security/README.md) · Services → [../05-Services-and-Networking/README.md](../05-Services-and-Networking/README.md) · scheduling, labels, kubectl skills → [../06-Cross-Cutting-Skills-and-Bonus-Topics/README.md](../06-Cross-Cutting-Skills-and-Bonus-Topics/README.md) · production design → [../08-Architect-Notes/README.md](../08-Architect-Notes/README.md)
