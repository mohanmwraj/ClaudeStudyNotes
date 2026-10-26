# 7.8 Kubernetes Platform Blueprints II: Kustomize, Namespace Guardrails, Consumers, Jobs, Canary, and Alerts That Are Tested

> **What was run:**
> * **kustomize 5.8.3** (binary checked against the release SHA-256) rendered five targets: prod (26 documents), staging (20), the prod migration step (3), cluster-scoped platform objects (5) and the namespace guardrails (6).
> * **All 60 documents** were validated against the **official Kubernetes v1.37.1 OpenAPI v3 schemas** and the CRD schemas of KEDA 2.21.0, prometheus-operator, VPA and Gateway API.
> * A **manifest audit** written for this module checked what a schema can't: Pod Security "restricted", NetworkPolicy reachability, quota fit at full scale, the shutdown budget, PDB evictability, selector overlap and KEDA option conflicts. On the first draft it found **three real bugs** (§5).
> * **promtool 3.15.1** linted the alert rules and ran 8 unit tests. The first run failed, and rightly (§6.2).
> * The admission policy's **CEL was evaluated with cel-java 0.10.1** against every rendered pod and five bad ones.
> * The **migration Job's entry point** was run against a real **PostgreSQL 18.6** with Spring Boot 4.1.2 and Flyway 12.4.0, in six scenarios (§4.1).
> * **12 negative tests** showed what each layer catches and what nothing offline catches (§7).
>
> **Not run:** a cluster. There was no `kubectl apply --dry-run=server`, no admission plugins (Pod Security, quota, the VAP), no scheduler, no CNI enforcing NetworkPolicies, and no KEDA or Prometheus operator. The Pod Security check is our own implementation of the documented controls (the Kyverno CLI, which embeds the upstream library, wasn't permitted on this machine), and cel-java is not the API server's cel-go. Run the server-side dry run in §8 on a real cluster before trusting any of this.
>
> **Builds on:** [7.5 single-service blueprints](05-Production-Blueprints-application-yml-Dockerfile-Deployment.md), [7.7 JVM profiles](07-Container-Images-and-JVM-Profiles-Blueprints-II-jlink-AOT-Workloads.md), [10.4 consumer scaling](../10-Kafka-Production/04-Consumer-Scaling-Static-Membership-KIP-848-KEDA-Rolling-Deploys.md), [7.3 shutdown](03-Kubernetes-Probes-and-Graceful-Shutdown.md), [7.4 HPA/KEDA](04-CPU-Throttling-GC-Choice-HPA-KEDA.md).

---

## 0. What this file proves 🔥

| Claim | Evidence |
|---|---|
| The first draft **passed schema validation and had three production bugs**: a CronJob that could reach only DNS, a PDB allowing **0 evictions** at 2–3 replicas, and a quota that a full-scale rollout would exceed | §5 |
| Terminating pods count against quota, but the Deployment controller **doesn't wait for them**. v1.37.1 has `status.terminatingReplicas` and no spec option. Budget one extra wave | §5.3 |
| A `limits.cpu` quota rejects the no-CPU-limit design of 7.4; a default CPU limit in a LimitRange would quietly undo it | §2.2, §7 |
| Spring Boot ignores `ExitCodeExceptionMapper` when context refresh fails, so every Flyway failure exits **1** and a Job can't tell "retry" from "stop". Explicit exit codes + `podFailurePolicy` | §4.1 |
| Two migration pods at once are safe with Flyway on PostgreSQL: the second **waited ~5 s** and found the schema up to date | §4.1 |
| `> on (namespace)` in an alert **dropped the `job` label**. promtool's unit test caught it, and `group_left` fixed it | §6.2 |
| kustomize 5.8.3 relabels the canary's selector, template, **topology spread**, Service and PDB, but a `labels:` transformer in `base/` **doesn't reach** a direct include of `base/api` | §3.3 |
| The image policy (CEL) admits every rendered pod and denies tag-only, Docker Hub, unpinned init containers and a **look-alike registry** (`registry.example.com.evil.io`) | §2.5 |
| KEDA trigger typos pass every schema and are **silently ignored** by default (source) | §7 |

---

## 1. Layout: who owns what ⚡

```text
k8s/
├── platform/
│   ├── cluster/        cluster-admin   PriorityClasses, ValidatingAdmissionPolicy + Binding
│   └── namespace/      platform team   Namespace (Pod Security labels), ResourceQuotas, LimitRange, default-deny + DNS
├── base/               service team
│   ├── kustomization.yaml
│   ├── api/            order-service: Deployment, Service, SA, PDB, HPA, NetworkPolicy, ServiceMonitor, VPA, ConfigMap
│   ├── consumer/       shipping-consumer: Deployment, ScaledObject + TriggerAuthentication, SA, PDB, NetworkPolicy, PodMonitor
│   ├── jobs/
│   │   ├── outbox-purge/   CronJob + NetworkPolicy
│   │   └── migrate/        Job + SA + NetworkPolicy      (deliberately NOT in base/kustomization.yaml)
│   └── monitoring/     PrometheusRule (recording rules, SLO burn, canary gate, workload alerts)
└── overlays/
    ├── staging/        digests, HPA 2–6, KEDA 0–4, staging profile
    └── prod/
        ├── kustomization.yaml   digests, HPA min 6, + canary + HTTPRoute
        ├── canary/              base/api again: nameSuffix -canary, track=canary, 2 replicas
        ├── httproute.yaml       95 / 5 split + "x-canary: always" override
        └── migrate/             this release's migration Job, applied FIRST
```

The five kustomizations that only list resources, for completeness. The rest appear with their resources below.

```yaml
# k8s/platform/cluster/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
# Cluster-scoped, owned by the platform team, applied once per cluster.
resources:
  - priorityclasses.yaml
  - admission-policy.yaml
```

```yaml
# k8s/platform/namespace/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
# The orders namespace and its guardrails. Owned by the platform team, not by the service team.
namespace: orders
resources:
  - namespace.yaml
  - quotas.yaml
  - limitrange.yaml
  - networkpolicies.yaml
```

```yaml
# k8s/base/jobs/migrate/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - job.yaml
  - access.yaml
```

```yaml
# k8s/base/jobs/outbox-purge/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - cronjob.yaml
  - networkpolicy.yaml                        # without it, default-deny leaves the job DNS only (7.8 section 5)
```

```yaml
# k8s/base/monitoring/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - prometheusrule.yaml
```

The split follows **who can change what**. The platform team owns everything that constrains a namespace: Pod Security level, quota, default-deny, admission policy, priority classes. The service team can't loosen any of it from its own repository, because none of it is in that repository.

Apply order, and why each step waits:

```bash
# once per cluster / namespace (platform pipeline)
kustomize build platform/cluster   | kubectl apply --server-side -f -
kustomize build platform/namespace | kubectl apply --server-side -f -

# every release (service pipeline): migration first, then the rollout
kustomize build overlays/prod/migrate | kubectl apply --server-side -f -
job=order-db-migrate-1-4-0
for i in $(seq 1 90); do                       # kubectl wait on Complete would sit out its timeout on a FAILED Job
  s=$(kubectl -n orders get job/$job -o jsonpath='{.status.conditions[?(@.status=="True")].type}')
  case "$s" in *Complete*) break ;; *Failed*) echo "migration failed"; exit 1 ;; esac
  sleep 10
done
kustomize build overlays/prod | kubectl apply --server-side -f -
kubectl -n orders rollout status deploy/order-service --timeout=10m
```

(The pipeline wasn't run: there's no cluster here. Argo CD expresses the same order with sync waves and a `PreSync` hook on the Job.)

---

## 2. Namespace guardrails (platform-owned) 🔥

### 2.1 The namespace and its Pod Security level

```yaml
# k8s/platform/namespace/namespace.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: orders
  labels:
    # enforce pinned to the cluster's version: an upgrade can't tighten the rules under running workloads.
    # warn and audit at "latest": they report what the next version would reject.
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/enforce-version: v1.37
    pod-security.kubernetes.io/warn: restricted
    pod-security.kubernetes.io/warn-version: latest
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/audit-version: latest
    platform.example.com/guardrails: enabled
```

Pod Security admission **enforces on Pods**, and only **warns** when you apply a Deployment whose template would fail. If you skip the warning, the failure shows up as a ReplicaSet `FailedCreate` event and a rollout that never progresses. That's why the audit checks every rendered template in CI (§5): all five templates pass the restricted controls.

### 2.2 Quota and defaults: the CPU-limit trap

```yaml
# k8s/platform/namespace/quotas.yaml
# Sized from the rendered prod manifests at full scale: max replicas + one surge wave + one wave of
# old pods still terminating (quota counts them; the Deployment controller doesn't). 7.8 section 5.3.
# No limits.cpu: the workloads deliberately set no CPU limit (7.4), and a limits.cpu quota would
# reject every such pod.
apiVersion: v1
kind: ResourceQuota
metadata:
  name: orders-compute
spec:
  hard:
    requests.cpu: "84"
    requests.memory: 84Gi
    limits.memory: 84Gi
    pods: "96"
    count/jobs.batch: "30"
    services.loadbalancers: "0"
    services.nodeports: "0"
---
# How much of the namespace may run at the critical priority: a team can't mark everything critical.
apiVersion: v1
kind: ResourceQuota
metadata:
  name: orders-critical-priority
spec:
  hard:
    requests.cpu: "72"
    requests.memory: 72Gi
    pods: "72"
  scopeSelector:
    matchExpressions:
      - scopeName: PriorityClass
        operator: In
        values: ["orders-critical"]
```

```yaml
# k8s/platform/namespace/limitrange.yaml
apiVersion: v1
kind: LimitRange
metadata:
  name: orders-container-defaults
spec:
  limits:
    - type: Container
      defaultRequest:
        cpu: 100m
        memory: 256Mi
      default:
        memory: 256Mi          # a default memory LIMIT only: a default CPU limit would bring CFS throttling back (7.4)
      max:
        memory: 4Gi
```

Two interactions to know (Kubernetes ResourceQuota docs; the audit flags the first one, N09 in §7):

* **A quota on `limits.cpu` requires every container to declare a CPU limit.** The no-CPU-limit design ([7.4 §1.1](04-CPU-Throttling-GC-Choice-HPA-KEDA.md)) then fails at admission. The tempting "fix", a LimitRange `default.cpu`, gives every container a CPU limit **silently**, and the CFS throttling comes back without anyone choosing it. Quota `requests.cpu` instead.
* **The scoped quota** (`scopeName: PriorityClass`) caps how much of the namespace can run at `orders-critical`. Without it, "critical" spreads until preemption protects nothing.

### 2.3 Default-deny, then open what each workload needs

```yaml
# k8s/platform/namespace/networkpolicies.yaml
# Baseline: nothing in or out, except DNS. Each workload then opens exactly what it needs.
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
spec:
  podSelector: {}
  policyTypes: ["Ingress", "Egress"]
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-dns-egress
spec:
  podSelector: {}
  policyTypes: ["Egress"]
  egress:
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: kube-system
          podSelector:
            matchLabels:
              k8s-app: kube-dns
      ports:
        - protocol: UDP
          port: 53
        - protocol: TCP
          port: 53
```

Default-deny is only as good as the per-workload policies that follow it. Forgetting one doesn't fail any validation. The workload just can't reach its database at 3 a.m. (§5.1).

### 2.4 Priority classes

```yaml
# k8s/platform/cluster/priorityclasses.yaml
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: orders-critical
value: 100000
globalDefault: false
preemptionPolicy: PreemptLowerPriority
description: "Customer-facing order APIs. May preempt consumers and batch work."
---
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: orders-standard
value: 50000
globalDefault: false
preemptionPolicy: PreemptLowerPriority
description: "Kafka consumers and deploy-path jobs such as migrations. Lag is tolerable; an outage is not."
---
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: batch-low
value: 10000
globalDefault: false
preemptionPolicy: Never
description: "Housekeeping CronJobs. Waits for free capacity instead of evicting anyone."
```

| Class | Who | Why |
|---|---|---|
| `orders-critical` | API | When the cluster is full, customer requests win |
| `orders-standard` | Consumers, the **migration** Job | Lag is recoverable. The migration is on the deploy path, so it must not queue behind housekeeping |
| `batch-low` (`preemptionPolicy: Never`) | CronJobs | Waits for capacity instead of evicting a consumer at 03:17 |

### 2.5 Admission policy: only our images, only by digest (CEL, evaluated) 🧊

```yaml
# k8s/platform/cluster/admission-policy.yaml
# Pods in namespaces labelled platform.example.com/guardrails=enabled must run images from our registry,
# pinned by digest. Enforced on Pods (catches every controller and operator), not on Deployments.
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicy
metadata:
  name: trusted-pinned-images
spec:
  failurePolicy: Fail
  matchConstraints:
    resourceRules:
      - apiGroups: [""]
        apiVersions: ["v1"]
        operations: ["CREATE", "UPDATE"]
        resources: ["pods"]
  variables:
    - name: containers
      expression: "object.spec.containers + (has(object.spec.initContainers) ? object.spec.initContainers : [])"
  validations:
    - expression: "variables.containers.all(c, c.image.startsWith('registry.example.com/'))"
      message: "images must come from registry.example.com"
      reason: Forbidden
    - expression: "variables.containers.all(c, c.image.matches('@sha256:[0-9a-f]{64}$'))"
      message: "images must be pinned by digest (name@sha256:...)"
      reason: Forbidden
---
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicyBinding
metadata:
  name: trusted-pinned-images
spec:
  policyName: trusted-pinned-images
  validationActions: ["Deny"]          # roll out as ["Warn", "Audit"] first, then switch
  matchResources:
    namespaceSelector:
      matchLabels:
        platform.example.com/guardrails: enabled
```

**Output (verified, cel-java 0.10.1):** the policy's own `variables` and `validations`, read from the rendered YAML, evaluated against a Pod built from every rendered template and five bad Pods:

```text
policy trusted-pinned-images: 1 variable(s), 2 validation(s)
  overlays-prod: Deployment/order-service                    ALLOW
  overlays-prod: Deployment/order-service-canary             ALLOW
  overlays-prod: Deployment/shipping-consumer                ALLOW
  overlays-prod: CronJob/outbox-purge                        ALLOW
  overlays-prod-migrate: Job/order-db-migrate-1-4-0          ALLOW
  overlays-staging: Deployment/order-service                 ALLOW
  overlays-staging: Deployment/shipping-consumer             ALLOW
  overlays-staging: CronJob/outbox-purge                     ALLOW
  BAD tag only                                               DENY: images must be pinned by digest (name@sha256:...)
  BAD Docker Hub, pinned                                     DENY: images must come from registry.example.com
  BAD unpinned initContainer                                 DENY: images must be pinned by digest (name@sha256:...)
  BAD look-alike registry                                    DENY: images must come from registry.example.com
  BAD digest + trailing junk                                 DENY: images must be pinned by digest (name@sha256:...)
```

Design decisions:

* **The trailing slash in `startsWith('registry.example.com/')` matters.** Without it, `registry.example.com.evil.io/...` passes; with it, it's denied (above).
* **Init containers are in the variable.** An unpinned `wait-for` init container is how a mutable tag sneaks into a pinned pod (denied above).
* **Pods, not Deployments.** Matching Pods catches everything: Deployments, Jobs, operators, `kubectl run`. The price is feedback. A denied Pod surfaces as a ReplicaSet `FailedCreate` event, not as a failed `kubectl apply`. CI runs the same check on rendered templates, so the failure appears in the pull request.
* **Roll out with `["Warn", "Audit"]`**, read the audit annotations for a week, then switch to `["Deny"]`.
* **Ephemeral debug containers** are created through the `pods/ephemeralcontainers` subresource, which `resources: ["pods"]` doesn't match. So `kubectl debug` with a JDK image still works ([7.7 §4.5](07-Container-Images-and-JVM-Profiles-Blueprints-II-jlink-AOT-Workloads.md)). Pod Security still applies to it in a restricted namespace, so use `kubectl debug --profile=restricted`.

---

## 3. The service team's base and overlays 🔥

### 3.1 The API workload

What changed from [7.5](05-Production-Blueprints-application-yml-Dockerfile-Deployment.md), and why:

| Change | Why | Evidence |
|---|---|---|
| `JDK_JAVA_OPTIONS`, 65 %, `MaxHeapFreeRatio=100`, `AlwaysPreTouch` | `InitialRAMPercentage` alone was undone at the first Remark; `JAVA_TOOL_OPTIONS` reaches `jcmd` too | [7.7 §4](07-Container-Images-and-JVM-Profiles-Blueprints-II-jlink-AOT-Workloads.md) |
| `track: stable` in selectors | Stable and canary must not select each other's pods (HPA metrics, PDB, Service) | §7 N06 |
| PDB `maxUnavailable: 25%` | `minAvailable: 75%` allowed **0** evictions at 2–3 replicas | §5.2 |
| No `POD_NAME` / `group.instance.id` | Static membership on a Deployment stalled partitions 45 s per pod | [10.4 §4](../10-Kafka-Production/04-Consumer-Scaling-Static-Membership-KIP-848-KEDA-Rolling-Deploys.md) |
| `priorityClassName`, `progressDeadlineSeconds` | §2.4; a stuck rollout is reported after 5 min instead of hanging | — |
| ConfigMap from a generator | Hash suffix: a config change is a normal, gated rollout and rolls back with the image | §3.3 |

```yaml
# k8s/base/api/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: order-service
  labels:
    app.kubernetes.io/name: order-service
    app.kubernetes.io/component: api
spec:
  # no "replicas": the HPA owns the count (7.5)
  revisionHistoryLimit: 5
  minReadySeconds: 10
  progressDeadlineSeconds: 300
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 25%
      maxUnavailable: 0
  selector:
    matchLabels:                              # "track" keeps stable and canary disjoint (HPA, PDB, Service)
      app.kubernetes.io/name: order-service
      track: stable
  template:
    metadata:
      labels:
        app.kubernetes.io/name: order-service
        app.kubernetes.io/component: api
        track: stable
    spec:
      serviceAccountName: order-service
      automountServiceAccountToken: false
      priorityClassName: orders-critical
      terminationGracePeriodSeconds: 45       # preStop 10 + drain 30 + margin 5 (7.3)
      securityContext:
        runAsNonRoot: true
        runAsUser: 65532
        runAsGroup: 65532
        fsGroup: 65532
        seccompProfile:
          type: RuntimeDefault
      topologySpreadConstraints:
        - maxSkew: 1
          topologyKey: topology.kubernetes.io/zone
          whenUnsatisfiable: DoNotSchedule
          labelSelector:
            matchLabels:
              app.kubernetes.io/name: order-service
              track: stable
        - maxSkew: 1
          topologyKey: kubernetes.io/hostname
          whenUnsatisfiable: ScheduleAnyway
          labelSelector:
            matchLabels:
              app.kubernetes.io/name: order-service
              track: stable
      containers:
        - name: app
          image: order-service                # overlays set registry + digest (images: in kustomization)
          ports:
            - name: http
              containerPort: 8080
              protocol: TCP
          env:
            - name: JDK_JAVA_OPTIONS          # launcher only; jcmd/jstack/jfr ignore it (7.7 section 4.5)
              value: >-
                -XX:+UseG1GC -XX:ActiveProcessorCount=2
                -XX:MaxRAMPercentage=65 -XX:InitialRAMPercentage=65
                -XX:MaxHeapFreeRatio=100 -XX:+AlwaysPreTouch
                -XX:MaxDirectMemorySize=128m
                -XX:+ExitOnOutOfMemoryError -XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=/dumps
                -Xlog:gc*:file=/tmp/gc.log:time,uptime,level,tags:filecount=5,filesize=10m
            - name: MALLOC_ARENA_MAX
              value: "2"
          envFrom:
            - configMapRef:
                name: order-service-config
            - secretRef:
                name: order-service-secrets   # DB_URL, DB_USER, DB_PASSWORD, REDIS_URL (External Secrets)
          resources:
            requests:
              cpu: "1"
              memory: 1Gi
            limits:
              memory: 1Gi                     # Guaranteed memory, no CPU limit (7.4)
          startupProbe:
            httpGet:
              path: /livez
              port: http
            periodSeconds: 2
            failureThreshold: 60
          livenessProbe:
            httpGet:
              path: /livez
              port: http
            periodSeconds: 10
            timeoutSeconds: 3
            failureThreshold: 3
          readinessProbe:
            httpGet:
              path: /readyz
              port: http
            periodSeconds: 5
            timeoutSeconds: 2
            failureThreshold: 2
          lifecycle:
            preStop:
              sleep:
                seconds: 10
          securityContext:
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            capabilities:
              drop: ["ALL"]
          volumeMounts:
            - name: tmp
              mountPath: /tmp
            - name: dumps
              mountPath: /dumps
            - name: kafka-user
              mountPath: /etc/kafka-user
              readOnly: true
            - name: kafka-cluster-ca
              mountPath: /etc/kafka-cluster-ca
              readOnly: true
      volumes:
        - name: tmp
          emptyDir:
            sizeLimit: 256Mi
        - name: dumps
          emptyDir:
            sizeLimit: 2Gi
        - name: kafka-user
          secret:
            secretName: kafka-order-service   # Strimzi KafkaUser secret, synced into this namespace
        - name: kafka-cluster-ca
          secret:
            secretName: kafka-cluster-ca
```

```yaml
# k8s/base/api/policy.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: order-service
automountServiceAccountToken: false
---
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: order-service
spec:
  maxUnavailable: 25%          # rounds UP: >= 1 eviction at any size. minAvailable 75% allowed 0 at 2-3 replicas
  selector:
    matchLabels:
      app.kubernetes.io/name: order-service
      track: stable
---
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: order-service
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: order-service
  minReplicas: 3
  maxReplicas: 40
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 60
  behavior:
    scaleUp:
      stabilizationWindowSeconds: 0
      selectPolicy: Max
      policies:
        - type: Percent
          value: 100
          periodSeconds: 60
        - type: Pods
          value: 4
          periodSeconds: 60
    scaleDown:
      stabilizationWindowSeconds: 300
      policies:
        - type: Percent
          value: 20
          periodSeconds: 60
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: order-service
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: order-service    # both tracks
  policyTypes: ["Ingress", "Egress"]
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: ingress      # the Gateway's data plane
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: monitoring   # Prometheus
      ports:
        - protocol: TCP
          port: 8080
  egress:
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: kafka
      ports:
        - protocol: TCP
          port: 9093
    - to:
        - ipBlock:
            cidr: 10.20.0.0/16                         # managed PostgreSQL and Redis subnets
      ports:
        - protocol: TCP
          port: 5432
        - protocol: TCP
          port: 6379
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: monitoring
      ports:
        - protocol: TCP
          port: 4317                                   # OTLP to the collector
```

```yaml
# k8s/base/api/monitoring.yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: order-service
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: order-service    # stable AND canary Services: job label = Service name
  endpoints:
    - port: http
      path: /actuator/prometheus
      interval: 30s
      scrapeTimeout: 10s
---
# Recommendations only. Never "Auto" next to a CPU-based HPA, and read its memory numbers with care:
# a pinned, pre-touched heap (7.7) looks like constant usage to the recommender.
apiVersion: autoscaling.k8s.io/v1
kind: VerticalPodAutoscaler
metadata:
  name: order-service
spec:
  targetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: order-service
  updatePolicy:
    updateMode: "Off"
  resourcePolicy:
    containerPolicies:
      - containerName: app
        controlledResources: ["cpu", "memory"]
```

```yaml
# k8s/base/api/service.yaml
apiVersion: v1
kind: Service
metadata:
  name: order-service
  labels:
    app.kubernetes.io/name: order-service
spec:
  type: ClusterIP
  selector:
    app.kubernetes.io/name: order-service
    track: stable
  ports:
    - name: http
      port: 80
      targetPort: http
      protocol: TCP
```

```yaml
# k8s/base/api/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - deployment.yaml
  - service.yaml
  - policy.yaml
  - monitoring.yaml
configMapGenerator:
  # Generated name gets a content hash, and the Deployment's reference is rewritten to it:
  # a config change is a new ReplicaSet, i.e. a normal, gated rollout (and a rollback restores it).
  - name: order-service-config
    literals:
      - SPRING_PROFILES_ACTIVE=prod
      - KAFKA_BOOTSTRAP_SERVERS=orders-kafka-bootstrap.kafka.svc:9093
```

```yaml
# k8s/base/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: orders
labels:
  - pairs:
      app.kubernetes.io/part-of: order-platform
resources:
  - api
  - consumer
  - jobs/outbox-purge
  - monitoring
# The migration Job is NOT here: it runs as its own step before the rollout (overlays/<env>/migrate).
```

### 3.2 The Kafka consumer (KEDA, KIP-848, no static membership)

The consumer applies [10.4](../10-Kafka-Production/04-Consumer-Scaling-Static-Membership-KIP-848-KEDA-Rolling-Deploys.md):

* One consumer per pod, so KEDA's partition cap of 12 is right.
* Even partition distribution, so the replica count steps through factors of 12.
* No preStop.
* A grace period covering the in-flight record and spring-kafka's 10 s container stop.
* The 7.7 consumer JVM profile.

```yaml
# k8s/base/consumer/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: shipping-consumer
  labels:
    app.kubernetes.io/name: shipping-consumer
    app.kubernetes.io/component: consumer
spec:
  # no "replicas": KEDA owns the count
  revisionHistoryLimit: 5
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 25%
      maxUnavailable: 0
  selector:
    matchLabels:
      app.kubernetes.io/name: shipping-consumer
  template:
    metadata:
      labels:
        app.kubernetes.io/name: shipping-consumer
        app.kubernetes.io/component: consumer
    spec:
      serviceAccountName: shipping-consumer
      automountServiceAccountToken: false
      priorityClassName: orders-standard
      # No preStop: a consumer gets no Service traffic. The grace period covers the in-flight record,
      # spring-kafka's 10 s container stop, commit + LeaveGroup (10.4 section 6.3).
      terminationGracePeriodSeconds: 30
      securityContext:
        runAsNonRoot: true
        runAsUser: 65532
        runAsGroup: 65532
        seccompProfile:
          type: RuntimeDefault
      topologySpreadConstraints:
        - maxSkew: 1
          topologyKey: topology.kubernetes.io/zone
          whenUnsatisfiable: ScheduleAnyway     # consumers may bunch up rather than not scale
          labelSelector:
            matchLabels:
              app.kubernetes.io/name: shipping-consumer
      containers:
        - name: app
          image: shipping-consumer
          ports:
            - name: http
              containerPort: 8080
              protocol: TCP
          env:
            - name: JDK_JAVA_OPTIONS           # the 7.7 consumer profile: 256 MB pinned heap in 512 MiB
              value: >-
                -XX:+UseSerialGC -XX:ActiveProcessorCount=1
                -Xms256m -Xmx256m -XX:+AlwaysPreTouch -Xss256k
                -XX:MaxDirectMemorySize=64m
                -XX:+ExitOnOutOfMemoryError
          envFrom:
            - configMapRef:
                name: shipping-consumer-config
            - secretRef:
                name: shipping-consumer-secrets
          resources:
            requests:
              cpu: 500m
              memory: 512Mi
            limits:
              memory: 512Mi
          startupProbe:
            httpGet:
              path: /livez
              port: http
            periodSeconds: 2
            failureThreshold: 60
          livenessProbe:
            httpGet:
              path: /livez
              port: http
            periodSeconds: 10
            timeoutSeconds: 3
            failureThreshold: 3
          readinessProbe:                       # gates the rollout (maxUnavailable: 0), not traffic
            httpGet:
              path: /readyz
              port: http
            periodSeconds: 5
            failureThreshold: 2
          securityContext:
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            capabilities:
              drop: ["ALL"]
          volumeMounts:
            - name: tmp
              mountPath: /tmp
            - name: kafka-user
              mountPath: /etc/kafka-user
              readOnly: true
            - name: kafka-cluster-ca
              mountPath: /etc/kafka-cluster-ca
              readOnly: true
      volumes:
        - name: tmp
          emptyDir:
            sizeLimit: 128Mi
        - name: kafka-user
          secret:
            secretName: kafka-shipping-consumer
        - name: kafka-cluster-ca
          secret:
            secretName: kafka-cluster-ca
```

```yaml
# k8s/base/consumer/scaling.yaml
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: shipping-consumer
spec:
  scaleTargetRef:
    name: shipping-consumer
  pollingInterval: 30
  minReplicaCount: 1                          # prod keeps one warm consumer; staging scales to zero
  maxReplicaCount: 12                         # = partitions of order-events, one consumer per pod (10.4 section 3.1)
  cooldownPeriod: 300                         # only for N -> 0; 1..N is the HPA behavior below
  advanced:
    horizontalPodAutoscalerConfig:
      behavior:
        scaleUp:
          stabilizationWindowSeconds: 0
          policies:
            - type: Pods
              value: 4
              periodSeconds: 60
        scaleDown:
          stabilizationWindowSeconds: 300
          policies:
            - type: Pods
              value: 2
              periodSeconds: 120              # every removed consumer is a rebalance: go slowly
  triggers:
    - type: kafka
      metadata:
        bootstrapServersFromEnv: KAFKA_BOOTSTRAP_SERVERS   # resolved from the target container's env (one source of truth)
        consumerGroup: shipping
        topic: order-events
        lagThreshold: "1000"
        activationLagThreshold: "50"
        offsetResetPolicy: earliest
        ensureEvenDistributionOfPartitions: "true"         # 12 partitions -> 1, 2, 3, 4, 6, 12 replicas; not with limitToPartitionsWithLag
        tls: enable
      authenticationRef:
        name: kafka-shipping-consumer
---
apiVersion: keda.sh/v1alpha1
kind: TriggerAuthentication
metadata:
  name: kafka-shipping-consumer
spec:
  secretTargetRef:
    - parameter: ca
      name: kafka-cluster-ca
      key: ca.crt
    - parameter: cert
      name: kafka-shipping-consumer
      key: user.crt
    - parameter: key
      name: kafka-shipping-consumer
      key: user.key
```

Four details checked in KEDA v2.21.0's source:

* `bootstrapServersFromEnv` exists because the field's parse order includes `resolvedEnv`.
* KEDA's resolver reads `env` and `envFrom` ConfigMaps of the target's containers, so KEDA and the application use the same bootstrap address from the same generated ConfigMap.
* `tls` can be set in the trigger metadata (`order=triggerMetadata;authParams`), while `ca`, `cert` and `key` come only from auth params (the TriggerAuthentication).
* `ensureEvenDistributionOfPartitions` and `limitToPartitionsWithLag` are mutually exclusive.

```yaml
# k8s/base/consumer/policy.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: shipping-consumer
automountServiceAccountToken: false
---
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: shipping-consumer
spec:
  maxUnavailable: 1                           # a drain moves one consumer at a time (one rebalance at a time)
  selector:
    matchLabels:
      app.kubernetes.io/name: shipping-consumer
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: shipping-consumer
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: shipping-consumer
  policyTypes: ["Ingress", "Egress"]
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: monitoring
      ports:
        - protocol: TCP
          port: 8080
  egress:
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: kafka
      ports:
        - protocol: TCP
          port: 9093
    - to:
        - ipBlock:
            cidr: 10.20.0.0/16
      ports:
        - protocol: TCP
          port: 5432
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: monitoring
      ports:
        - protocol: TCP
          port: 4317
```

```yaml
# k8s/base/consumer/monitoring.yaml
apiVersion: monitoring.coreos.com/v1
kind: PodMonitor                              # no Service in front of a consumer
metadata:
  name: shipping-consumer
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: shipping-consumer
  podMetricsEndpoints:
    - port: http
      path: /actuator/prometheus
      interval: 30s
```

```yaml
# k8s/base/consumer/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - deployment.yaml
  - scaling.yaml
  - policy.yaml
  - monitoring.yaml
configMapGenerator:
  - name: shipping-consumer-config
    literals:
      - SPRING_PROFILES_ACTIVE=prod
      - KAFKA_BOOTSTRAP_SERVERS=orders-kafka-bootstrap.kafka.svc:9093   # KEDA reads it from here too (scaling.yaml)
```

The Kafka namespace's own NetworkPolicies must admit the **`keda` namespace** too: the operator reads consumer-group offsets itself, from its own pods.

### 3.3 Overlays, the canary, and what kustomize actually did (verified)

```yaml
# k8s/overlays/prod/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: orders
resources:
  - ../../base
  - canary
  - httproute.yaml
images:                                       # CI writes the digests; tags are for humans
  - name: order-service
    newName: registry.example.com/orders/order-service
    digest: sha256:666f22ab8e773ae2ddcd0725df60a2232bfe8a3a7793b6b485392d8d39a491e9
  - name: shipping-consumer
    newName: registry.example.com/orders/shipping-consumer
    digest: sha256:51eba7ce952a76332a908354641b1a7cf65a8711382500a13b3c5654c77ac308
  - name: order-jobs
    newName: registry.example.com/orders/order-jobs
    digest: sha256:9daa44e799900a14713a2ce196a47e5dcfe6860fa416fcc1e21c2cb647ad80ba
patches:
  - target:
      kind: HorizontalPodAutoscaler
      name: order-service
    patch: |-
      - op: replace
        path: /spec/minReplicas
        value: 6
```

```yaml
# k8s/overlays/prod/canary/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
# A second copy of the API with the candidate image: order-service-canary, track=canary.
resources:
  - ../../../base/api
nameSuffix: -canary
labels:
  - pairs:
      track: canary
    includeSelectors: true                    # selector, pod template, Service, PDB all say track=canary
  - pairs:                                    # base/kustomization.yaml's labels don't reach a direct include of base/api
      app.kubernetes.io/part-of: order-platform
images:
  - name: order-service
    newName: registry.example.com/orders/order-service
    digest: sha256:a49f39528836812f3a3c036dfd4ca417a4acc99dfd7c67568ccad001dd8f11ef   # 1.5.0-rc1
patches:
  # fixed size, no autoscaling, no duplicate scrape config or VPA
  - target:
      kind: Deployment
      name: order-service
    patch: |-
      - op: add
        path: /spec/replicas
        value: 2
  - patch: |-
      $patch: delete
      apiVersion: autoscaling/v2
      kind: HorizontalPodAutoscaler
      metadata:
        name: order-service
  - patch: |-
      $patch: delete
      apiVersion: monitoring.coreos.com/v1
      kind: ServiceMonitor
      metadata:
        name: order-service
  - patch: |-
      $patch: delete
      apiVersion: autoscaling.k8s.io/v1
      kind: VerticalPodAutoscaler
      metadata:
        name: order-service
  - patch: |-
      $patch: delete
      apiVersion: networking.k8s.io/v1
      kind: NetworkPolicy
      metadata:
        name: order-service
  # The PDB needs no patch: maxUnavailable 25 % of 2 pods rounds up to 1 eviction.
```

```yaml
# k8s/overlays/prod/httproute.yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: order-service
spec:
  parentRefs:
    - name: public                            # the shared Gateway; its listener must allow routes from "orders"
      namespace: ingress
      sectionName: https
  hostnames: ["orders.example.com"]
  rules:
    - matches:                                # testers and synthetic checks force the canary
        - headers:
            - name: x-canary
              value: always
      backendRefs:
        - name: order-service-canary
          port: 80
    - matches:
        - path:
            type: PathPrefix
            value: /
      backendRefs:                            # promotion = 0 -> 5 -> 25 -> 50 -> 100, gated by CanaryErrorRateAboveStable
        - name: order-service
          port: 80
          weight: 95
        - name: order-service-canary
          port: 80
          weight: 5
      timeouts:
        request: 10s
```

```yaml
# k8s/overlays/staging/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: orders
resources:
  - ../../base
images:
  - name: order-service
    newName: registry.example.com/orders/order-service
    digest: sha256:acd8022035cb59768cf333382b8d9137ca38e2aaf9f434d42515cd614ad22bf7
  - name: shipping-consumer
    newName: registry.example.com/orders/shipping-consumer
    digest: sha256:ffe462cf7648fe8cc7efd72393884882879d8a3c26b2abc2e3bdf7983080be77
  - name: order-jobs
    newName: registry.example.com/orders/order-jobs
    digest: sha256:b6612138b02dd742b9d14ba9a685916a88bcf7cab46c5ff90963dba60a01966b
configMapGenerator:
  - name: order-service-config
    behavior: merge
    literals:
      - SPRING_PROFILES_ACTIVE=staging
  - name: shipping-consumer-config
    behavior: merge
    literals:
      - SPRING_PROFILES_ACTIVE=staging
patches:
  - target:
      kind: HorizontalPodAutoscaler
      name: order-service
    patch: |-
      - op: replace
        path: /spec/minReplicas
        value: 2
      - op: replace
        path: /spec/maxReplicas
        value: 6
  - target:
      kind: ScaledObject
      name: shipping-consumer
    patch: |-
      - op: replace
        path: /spec/minReplicaCount
        value: 0
      - op: replace
        path: /spec/maxReplicaCount
        value: 4
```

What the rendered prod output showed (kustomize 5.8.3):

* **The canary copy is consistent.** `order-service-canary` got `replicas: 2`, `track: canary` in its selector, pod template **and both topology-spread label selectors**, the candidate digest, and a reference to its own generated ConfigMap. The Service and PDB selectors also say `track: canary`. The stable Deployment kept the stable digest, because the prod-level `images:` entry matches only the bare name `order-service`, which the canary had already rewritten.
* **Transformers apply to what a kustomization loads.** `base/kustomization.yaml` puts `part-of` on everything below it, but the canary includes `base/api` directly, so its resources rendered **without** the label. That's why the canary declares it again.
* **`digest:` drops the tag.** Images render as `registry.example.com/orders/order-service@sha256:…`. Put the version in a label or annotation if humans need it.
* **Identical ConfigMap data gets an identical suffix:** `order-service-config-kf626bgm86` and `shipping-consumer-config-kf626bgm86`. The hash covers the content, and the name keeps them apart.
* **Selector overlap is a real failure mode.** Without the `track` label, both Deployments select each other's pods (§7, N06). The HPA averages CPU across both, the PDB counts both, and the stable Service sends 50 % of traffic to two canary pods.

How the canary progresses: raise the HTTPRoute weights 5 → 25 → 50 → 100 while `CanaryErrorRateAboveStable` (§6) stays quiet. Then promote by moving the canary digest into the prod `images:` entry, and set the weights back to 100/0. Weighted routing splits **requests**, not users, so a user can see both versions within one session. Anything that needs session consistency must stay compatible across both versions. That is the same discipline as expand/contract schema changes.

---

## 4. Jobs: migrations and housekeeping 🔥

### 4.1 The migration entry point, measured against PostgreSQL

A Job's `podFailurePolicy` can act on exit codes, so first we need exit codes that mean something. Test setup:
* Spring Boot 4.1.2, Flyway 12.4.0, pgjdbc 42.7.14, HikariCP 7.0.2, PostgreSQL 18.6, `spring.main.web-application-type: none`.
* Migrations: `V1__orders.sql`, `V2__order_status_index.sql`, and a broken V3 whose second statement has a typo (`ALTER TABLE ordrs …`).

| Scenario | Plain Boot (`SpringApplication.run`) | Mapped (the code below) | Observed |
|---|---|---|---|
| Fresh database, V1 + V2 | exit 0 | exit 0 | ~2.0 s |
| Run again | exit 0 | exit 0 | "Schema is up to date" |
| Broken V3 (second statement fails) | **exit 1** | **exit 3** | PostgreSQL rolled back the **first** statement too (transactional DDL); no history row |
| Database unreachable | **exit 1** | **exit 2** (SQLState class `08`) | ~3.1 s with `connection-timeout: 3000` |
| An applied migration (V2) edited afterwards | exit 1 | **exit 3** | checksum mismatch on validate |
| **Two runs at once**, V3 takes 5 s | exit 0, exit 0 | exit 0, exit 0 | V3 applied **once**; run 2 waited ~5 s, then "up to date" |

Three things the table shows:

* **Plain Boot exits 1 for everything**, including in the lab app, which had an `ExitCodeExceptionMapper` bean returning 4. The bytecode shows why. `SpringApplication.getExitCodeFromMappedException` returns 0 unless `context.isActive()`, and after a failed refresh the context isn't active, so **mapper beans are never consulted** for startup failures. (An exception that itself implements `ExitCodeGenerator` still is, but Flyway's don't.) Exit 1 can mean "the database is restarting" or "your SQL is wrong", and the Job can't tell which.
* **Concurrent runs are safe.** Flyway serialises on PostgreSQL with a lock. No waiting row appeared in `pg_locks`, which suggests it polls with a try-lock rather than blocking. So a retried pod overlapping a slow one, or two pipelines racing, doesn't double-apply.
* **PostgreSQL's transactional DDL makes "failed" clean.** The broken migration left no half-applied column. On MySQL, DDL auto-commits, so the same failure leaves the first statement applied. Write MySQL migrations as one statement each.

The entry point (the lab code, packaged as `MigrateMain`):

```java
package com.example.orders.migrate;

import java.sql.SQLException;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.context.ConfigurableApplicationContext;

/**
 * Flyway runs during context refresh, then the JVM exits with a code the Job's podFailurePolicy acts on:
 * 0 = migrated, 2 = transient (database unreachable: retry), 3 = permanent (bad SQL, edited migration: stop).
 */
@SpringBootApplication
public class MigrateMain {

    public static void main(String[] args) {
        try {
            ConfigurableApplicationContext ctx = SpringApplication.run(MigrateMain.class, args);
            System.exit(SpringApplication.exit(ctx));
        } catch (Throwable t) {
            System.exit(exitCode(t));        // ExitCodeExceptionMapper beans are NOT consulted when refresh fails
        }
    }

    /** SQLState class 08 = connection exception: worth a retry. Everything else won't fix itself. */
    static int exitCode(Throwable t) {
        for (Throwable c = t; c != null; c = c.getCause())
            if (c instanceof SQLException s && s.getSQLState() != null && s.getSQLState().startsWith("08")) return 2;
        return 3;
    }
}
```

The Job image runs it with `java -cp /app/application.jar com.example.orders.migrate.MigrateMain`. In the extracted layout ([7.7 §3](07-Container-Images-and-JVM-Profiles-Blueprints-II-jlink-AOT-Workloads.md)), `application.jar`'s manifest `Class-Path` lists `lib/`, so the same image runs the service, the migration and the purge job with different main classes. One more measured detail: `spring.datasource.hikari.connection-timeout` binds to a `long` of milliseconds. `3000` works, while `3s` **fails to bind**.

### 4.2 The Job

```yaml
# k8s/base/jobs/migrate/job.yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: order-db-migrate                      # the overlay renames it per release: a Job's pod template is immutable
  labels:
    app.kubernetes.io/name: order-db-migrate
    app.kubernetes.io/component: batch
spec:
  backoffLimit: 4                             # retries for transient failures (exit 2) only, see podFailurePolicy
  activeDeadlineSeconds: 900                  # the whole Job, retries included
  ttlSecondsAfterFinished: 86400
  podReplacementPolicy: Failed                # no replacement pod until the old one has fully terminated
  podFailurePolicy:
    rules:
      - action: FailJob                       # 3 = permanent (bad SQL, edited migration): retrying can't help
        onExitCodes:
          containerName: migrate
          operator: In
          values: [3]
      - action: Ignore                        # node drain / preemption: retry without counting it
        onPodConditions:
          - type: DisruptionTarget
      # anything else (2 = database unreachable, OOM, ...) counts against backoffLimit
  template:
    metadata:
      labels:
        app.kubernetes.io/name: order-db-migrate
        app.kubernetes.io/component: batch
    spec:
      restartPolicy: Never                    # required by podFailurePolicy
      serviceAccountName: order-db-migrate
      automountServiceAccountToken: false
      priorityClassName: orders-standard      # on the deploy path: must not wait behind batch work
      securityContext:
        runAsNonRoot: true
        runAsUser: 65532
        runAsGroup: 65532
        seccompProfile:
          type: RuntimeDefault
      containers:
        - name: migrate
          image: order-jobs
          command: ["/opt/java/bin/java", "-cp", "/app/application.jar", "com.example.orders.migrate.MigrateMain"]
          env:
            - name: JDK_JAVA_OPTIONS
              value: "-XX:+UseSerialGC -Xmx256m -XX:+ExitOnOutOfMemoryError"
          envFrom:
            - secretRef:
                name: order-db-migrate-secrets  # a DDL-capable user; the service's own user can't ALTER
          resources:
            requests:
              cpu: 500m
              memory: 512Mi
            limits:
              memory: 512Mi
          securityContext:
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            capabilities:
              drop: ["ALL"]
          volumeMounts:
            - name: tmp
              mountPath: /tmp
      volumes:
        - name: tmp
          emptyDir:
            sizeLimit: 64Mi
```

```yaml
# k8s/base/jobs/migrate/access.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: order-db-migrate
automountServiceAccountToken: false
---
# Ships with the Job: on the very first deploy the main render hasn't been applied yet, and the
# namespace's default-deny would block the migration from reaching the database.
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: order-db-migrate
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: order-db-migrate
  policyTypes: ["Egress"]
  egress:
    - to:
        - ipBlock:
            cidr: 10.20.0.0/16
      ports:
        - protocol: TCP
          port: 5432
```

```yaml
# k8s/overlays/prod/migrate/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
# Applied and awaited BEFORE the main render (7.8 section 4.3). CI sets the release in the Job name:
# a Job's pod template is immutable, so a new release needs a new Job.
namespace: orders
resources:
  - ../../../base/jobs/migrate
images:
  - name: order-jobs
    newName: registry.example.com/orders/order-jobs
    digest: sha256:9daa44e799900a14713a2ce196a47e5dcfe6860fa416fcc1e21c2cb647ad80ba
patches:
  - target:
      kind: Job
      name: order-db-migrate
    patch: |-
      - op: replace
        path: /metadata/name
        value: order-db-migrate-1-4-0
```

How a failure plays out, per the Kubernetes Job documentation (not run here):

| Pod outcome | Rule | Result |
|---|---|---|
| exit 3: bad SQL, edited migration | `FailJob` | Job fails **immediately**: no retries, no 15-minute wait for a deadline |
| exit 2: database unreachable | (no rule matches → counted) | Retried with exponential back-off (10 s, 20 s, 40 s …), up to `backoffLimit: 4` |
| Evicted by a drain or preemption | `Ignore` on `DisruptionTarget` | Retried, and **not** counted against the limit |
| Anything after 900 s | `activeDeadlineSeconds` | Job fails, whatever the state |

Why it's a Job and not an initContainer, although §4.1 shows concurrent runs are safe:

* **Credentials.** The migration needs DDL rights, and an initContainer would give them to every API pod.
* **Fan-out.** A scale-out from 6 to 40 would run 34 migrations against the database at once, all but one waiting on the lock.
* **Blast radius.** A failing migration would crash-loop every new pod, rather than fail one Job before the rollout starts.
* **Expand/contract** keeps the ordering safe. The Job applies an additive change that the *running* version tolerates, the rollout follows, and the cleanup ships a release later.

### 4.3 The housekeeping CronJob

```yaml
# k8s/base/jobs/outbox-purge/cronjob.yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: outbox-purge
  labels:
    app.kubernetes.io/name: outbox-purge
    app.kubernetes.io/component: batch
spec:
  schedule: "17 3 * * *"                     # off the hour: every team's "0 3 * * *" lands at once
  timeZone: Etc/UTC
  concurrencyPolicy: Forbid                   # a slow run must not overlap the next one
  startingDeadlineSeconds: 600                # missed by >10 min (controller down, no capacity): skip, alert
  successfulJobsHistoryLimit: 3
  failedJobsHistoryLimit: 5
  jobTemplate:
    spec:
      backoffLimit: 2
      activeDeadlineSeconds: 1800
      template:
        metadata:
          labels:
            app.kubernetes.io/name: outbox-purge
            app.kubernetes.io/component: batch
        spec:
          restartPolicy: Never
          priorityClassName: batch-low
          automountServiceAccountToken: false
          securityContext:
            runAsNonRoot: true
            runAsUser: 65532
            runAsGroup: 65532
            seccompProfile:
              type: RuntimeDefault
          containers:
            - name: purge
              image: order-jobs               # the 7.7 "job" target: no AOT cache
              command: ["/opt/java/bin/java", "-cp", "/app/application.jar", "com.example.orders.jobs.OutboxPurgeMain"]
              env:
                - name: JDK_JAVA_OPTIONS
                  value: "-XX:+UseSerialGC -Xmx256m -XX:+ExitOnOutOfMemoryError"
                - name: PURGE_OLDER_THAN
                  value: P7D
                - name: PURGE_BATCH_SIZE
                  value: "5000"               # small DELETE batches: short locks, steady WAL
              envFrom:
                - secretRef:
                    name: order-jobs-secrets
              resources:
                requests:
                  cpu: 500m
                  memory: 512Mi
                limits:
                  memory: 512Mi
              securityContext:
                allowPrivilegeEscalation: false
                readOnlyRootFilesystem: true
                capabilities:
                  drop: ["ALL"]
              volumeMounts:
                - name: tmp
                  mountPath: /tmp
          volumes:
            - name: tmp
              emptyDir:
                sizeLimit: 64Mi
```

```yaml
# k8s/base/jobs/outbox-purge/networkpolicy.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: outbox-purge
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: outbox-purge
  policyTypes: ["Egress"]
  egress:
    - to:
        - ipBlock:
            cidr: 10.20.0.0/16
      ports:
        - protocol: TCP
          port: 5432
```

That second file didn't exist in the first draft (§5.1). `OutboxPurgeNotSucceeding` (§6) is the alert that would have caught it in production, a day later.

---

## 5. Budget math, checked on the render (verified) 🔥

The audit turns each budget into arithmetic over the rendered YAML. On the **first draft** it reported three problems that every schema check had passed.

### 5.1 Reachability: the CronJob that could only resolve names

```text
== NetworkPolicy: what each workload may reach                       (first draft)
  Deployment   order-service       egress: 10.20.0.0/16 -> 5432/TCP,6379/TCP; ns/kafka -> 9093/TCP; …kube-dns -> 53/UDP,53/TCP; ns/monitoring -> 4317/TCP
  Deployment   shipping-consumer   egress: 10.20.0.0/16 -> 5432/TCP; ns/kafka -> 9093/TCP; …kube-dns -> 53/UDP,53/TCP; ns/monitoring -> 4317/TCP
  CronJob      outbox-purge        egress: ns/kube-system pods{"k8s-app":"kube-dns"} -> 53/UDP,53/TCP
  Job          order-db-migrate    egress: 10.20.0.0/16 -> 5432/TCP; …kube-dns -> 53/UDP,53/TCP
findings: 1
  NETPOL CronJob/outbox-purge: egress allows DNS only (default-deny applies)
```

The CronJob would have resolved the database's name every night and timed out connecting to it. Fixed with the NetworkPolicy in §4.3.

### 5.2 PDBs: percentages round **up**, which helps you or hurts you

```text
== PodDisruptionBudgets at minimum scale                              (first draft, staging)
  order-service              -> order-service            at  2 replicas: 0 eviction(s) allowed
findings: 1
  PDB order-service: 0 evictions allowed at 2 replicas -> node drains block
```

The disruption controller rounds percentages **up**. So `minAvailable: 75%` of 2 is 2, and **nothing** may be evicted, and a node drain or cluster upgrade hangs on this pod. Same at 3 replicas: 75 % of 3 rounds up to 3. `maxUnavailable: 25%` rounds up in your favour:

| Replicas | `minAvailable: 75%` → evictions allowed | `maxUnavailable: 25%` → evictions allowed |
|---|---|---|
| 2 | **0** (2 must stay) | 1 |
| 3 | **0** (3 must stay) | 1 |
| 4 | 1 | 1 |
| 6 | 1 | 2 |
| 40 | 10 | 10 |

The final render: prod at 6 replicas allows 2, the canary at 2 allows 1, staging at 2 allows 1. [7.5](05-Production-Blueprints-application-yml-Dockerfile-Deployment.md)'s `minAvailable: 75%` is safe only because its HPA minimum is 4.

### 5.3 Quota: terminating pods are the forgotten term

The audit computes peak demand from the render. For each workload it takes the max replicas (from the HPA or ScaledObject), adds the rollout surge, and adds **one wave of old pods that are still terminating**:

* The Deployment controller doesn't count terminating pods. In v1.37.1, `status.terminatingReplicas` is a beta, on-by-default *status* field, and there is no spec field that makes a rollout wait for them. So the next surge wave starts while the previous one is in its 45 s grace period.
* ResourceQuota counts every pod that hasn't reached a terminal phase, terminating ones included.

```text
== Quota fit at full scale (max replicas + rollout surge)
  workload                       replicas  surge  term   pods  req.cpu   req.mem   lim.mem
  Deployment/order-service             40     10    10     60     60.0     60.0Gi     60.0Gi  orders-critical
  Deployment/order-service-canary        2      1     1      4      4.0      4.0Gi      4.0Gi  orders-critical
  Deployment/shipping-consumer         12      3     3     18      9.0      9.0Gi      9.0Gi  orders-standard
  CronJob/outbox-purge                  1      0     0      1      0.5      0.5Gi      0.5Gi  batch-low
  Job/order-db-migrate-1-4-0            1      0     0      1      0.5      0.5Gi      0.5Gi  orders-standard
  TOTAL at peak                                            84     74.0     74.0Gi     74.0Gi
    of which orders-critical                               64     64.0     64.0Gi
  quota orders-compute             requests.cpu     need    74.0 / hard    84.0  OK (88 % used at peak)
  quota orders-compute             pods             need    84.0 / hard    96.0  OK (88 % used at peak)
  quota orders-critical-priority   requests.cpu     need    64.0 / hard    72.0  OK (89 % used at peak)
```

The first draft's quota (70 CPU, 80 pods, 56 critical) was sized for max replicas plus surge. That's 61.5 CPU, which looked comfortable. With the terminating wave included, peak demand is **74 CPU and 84 pods**, and the audit reported seven `EXCEEDED` lines. In production that's an HPA that wants 40 replicas during a deploy and gets `FailedCreate`. The planned peak now sits at 88–89 % of quota, just under the 90 % `NamespaceQuotaNearlyFull` alert. So the alert fires only when someone raises a maximum without raising the quota.

### 5.4 Shutdown and rollout time

```text
== Shutdown budget
  order-service                  preStop 10 + drain 30 + margin 5 = 45  vs grace 45  OK
  order-service-canary           preStop 10 + drain 30 + margin 5 = 45  vs grace 45  OK
  shipping-consumer              preStop  0 + drain 15 + margin 5 = 20  vs grace 30  OK
```

The consumer's "drain" is spring-kafka's 10 s container stop plus one in-flight record ([10.4 §6.3](../10-Kafka-Production/04-Consumer-Scaling-Static-Membership-KIP-848-KEDA-Rolling-Deploys.md)). Raising the API's preStop to 20 s without raising the grace period is caught (N08: needs 55 s, grace 45 s).

Rollout time at 40 replicas, as arithmetic: `maxSurge: 25%` gives 10 pods per wave, so 4 waves. Each wave costs a JVM start (1.3 s with the AOT cache, [7.7 §2](07-Container-Images-and-JVM-Profiles-Blueprints-II-jlink-AOT-Workloads.md)), the readiness period (5 s) and `minReadySeconds` (10 s), roughly **15–20 s**, so the whole rollout takes **about 1–1.5 minutes**. Terminating pods don't slow it down (§5.3); they only cost quota. If the rollout runs longer than `progressDeadlineSeconds: 300`, the Deployment reports `ProgressDeadlineExceeded`. Your pipeline should fail on that condition rather than wait forever.

---

## 6. Alerts as code, with unit tests (verified) 🔥

### 6.1 The rules

```yaml
# k8s/base/monitoring/prometheusrule.yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: order-platform
spec:
  groups:
    - name: orders.slo.recording
      rules:
        # Error ratio per Service (job = Service name via the ServiceMonitor): order-service and order-service-canary.
        - record: job:http_server_requests:error_ratio_rate5m
          expr: |
            sum by (namespace, job) (rate(http_server_requests_seconds_count{namespace="orders", outcome="SERVER_ERROR"}[5m]))
            /
            sum by (namespace, job) (rate(http_server_requests_seconds_count{namespace="orders"}[5m]))
        - record: job:http_server_requests:error_ratio_rate30m
          expr: |
            sum by (namespace, job) (rate(http_server_requests_seconds_count{namespace="orders", outcome="SERVER_ERROR"}[30m]))
            /
            sum by (namespace, job) (rate(http_server_requests_seconds_count{namespace="orders"}[30m]))
        - record: job:http_server_requests:error_ratio_rate1h
          expr: |
            sum by (namespace, job) (rate(http_server_requests_seconds_count{namespace="orders", outcome="SERVER_ERROR"}[1h]))
            /
            sum by (namespace, job) (rate(http_server_requests_seconds_count{namespace="orders"}[1h]))
        - record: job:http_server_requests:error_ratio_rate6h
          expr: |
            sum by (namespace, job) (rate(http_server_requests_seconds_count{namespace="orders", outcome="SERVER_ERROR"}[6h]))
            /
            sum by (namespace, job) (rate(http_server_requests_seconds_count{namespace="orders"}[6h]))
        - record: job:http_server_requests:rate5m
          expr: sum by (namespace, job) (rate(http_server_requests_seconds_count{namespace="orders"}[5m]))
    - name: orders.slo.alerts
      rules:
        # SLO 99.9 % of requests without a server error. Multiwindow burn rates (9.1).
        - alert: OrderServiceErrorBudgetFastBurn
          expr: |
            job:http_server_requests:error_ratio_rate1h{job="order-service"} > (14.4 * 0.001)
            and
            job:http_server_requests:error_ratio_rate5m{job="order-service"} > (14.4 * 0.001)
          for: 2m
          labels:
            severity: page
          annotations:
            summary: "order-service is burning its 30-day error budget 14x too fast"
        - alert: OrderServiceErrorBudgetSlowBurn
          expr: |
            job:http_server_requests:error_ratio_rate6h{job="order-service"} > (6 * 0.001)
            and
            job:http_server_requests:error_ratio_rate30m{job="order-service"} > (6 * 0.001)
          for: 15m
          labels:
            severity: ticket
        # The canary gate: worse than stable by 2x, with enough traffic to mean something.
        # group_left keeps the canary's labels: plain "on (namespace)" would reduce the result to {namespace}
        - alert: CanaryErrorRateAboveStable
          expr: |
            job:http_server_requests:error_ratio_rate5m{job="order-service-canary"}
              > on (namespace) group_left 2 * job:http_server_requests:error_ratio_rate5m{job="order-service"}
            and on (namespace)
            job:http_server_requests:error_ratio_rate5m{job="order-service-canary"} > 0.01
            and on (namespace)
            job:http_server_requests:rate5m{job="order-service-canary"} > 1
          for: 5m
          labels:
            severity: page
          annotations:
            summary: "canary 5xx ratio is more than twice stable's: set the HTTPRoute canary weight to 0"
    - name: orders.workloads
      rules:
        # Pinned heap (7.7 section 4.4): the working set is flat by design, so alert on NON-heap use of the headroom.
        - alert: JvmNonHeapHeadroomLow
          expr: |
            (
              sum by (namespace, pod) (container_memory_working_set_bytes{namespace="orders", container="app"})
              - sum by (namespace, pod) (jvm_memory_committed_bytes{namespace="orders", area="heap"})
            )
            /
            (
              sum by (namespace, pod) (kube_pod_container_resource_limits{namespace="orders", container="app", resource="memory"})
              - sum by (namespace, pod) (jvm_memory_committed_bytes{namespace="orders", area="heap"})
            )
            > 0.85
          for: 15m
          labels:
            severity: ticket
          annotations:
            summary: "{{ $labels.pod }}: non-heap memory uses over 85 % of the space left above the heap"
        - alert: ShippingConsumerLagAtMaxScale
          expr: |
            sum(kafka_consumer_fetch_manager_records_lag_max{namespace="orders", pod=~"shipping-consumer-.*"}) > 50000
            and on ()
            kube_horizontalpodautoscaler_status_current_replicas{namespace="orders", horizontalpodautoscaler="keda-hpa-shipping-consumer"}
              >= kube_horizontalpodautoscaler_spec_max_replicas{namespace="orders", horizontalpodautoscaler="keda-hpa-shipping-consumer"}
          for: 10m
          labels:
            severity: page
          annotations:
            summary: "shipping lag keeps growing at max replicas: more pods can't help (partition cap)"
        - alert: NamespaceQuotaNearlyFull
          expr: |
            kube_resourcequota{namespace="orders", type="used"}
              / ignoring (type) kube_resourcequota{namespace="orders", type="hard"} > 0.9
          for: 15m
          labels:
            severity: ticket
          annotations:
            summary: "{{ $labels.resourcequota }}/{{ $labels.resource }} above 90 %: the next scale-up may fail with FailedCreate"
        - alert: MigrationJobFailed
          expr: kube_job_failed{namespace="orders", job_name=~"order-db-migrate-.*", condition="true"} == 1
          labels:
            severity: page
        - alert: OutboxPurgeNotSucceeding
          expr: time() - kube_cronjob_status_last_successful_time{namespace="orders", cronjob="outbox-purge"} > 26 * 3600
          labels:
            severity: ticket
        - alert: HikariPoolStarved
          expr: max by (namespace, pod) (hikaricp_connections_pending{namespace="orders"}) > 0
          for: 5m
          labels:
            severity: ticket
```

### 6.2 The tests, and the bug they found

`promtool check rules` lints syntax (`SUCCESS: 14 rules found`). `promtool test rules` evaluates the rules against synthetic series and compares the alerts that fire, with their labels and annotations, against expectations. Eight tests cover:

* the fast burn at 2 % errors;
* the canary gate firing at 5 % vs 1 %, and **not** at 1.5 % vs 1 %;
* stable at 1 % **not** paging;
* the non-heap alert on a 1000 MiB pod and silence on an 850 MiB one;
* quota at 93 %;
* lag paging only once the HPA is at max;
* the purge staleness (silent at 25 h, firing at 28 h);
* a failed migration Job.

The first run:

```text
  FAILED:
    alertname: CanaryErrorRateAboveStable, time: 30m,
        exp:[ Labels:{alertname="CanaryErrorRateAboveStable", job="order-service-canary", namespace="orders", severity="page"} ],
        got:[ Labels:{alertname="CanaryErrorRateAboveStable", namespace="orders", severity="page"} ]
```

The alert fired, but **without its `job` label**. In one-to-one vector matching, `a > on (namespace) b` produces series that carry only the `on` labels, comparison or not. On-call would get a canary page that doesn't say which Service. `group_left` makes it many-to-one and keeps the left-hand side's labels. After the fix: `SUCCESS`. Two other details the tests pinned down:

* `/ ignoring (type)` in the quota alert drops `type` and keeps `resourcequota` and `resource`, so `{{ $labels.resource }}` renders.
* `and on ()` in the lag alert keeps only the left side's labels (none, after `sum`). The page carries just `severity`, which is fine for a single consumer group.

---

## 7. What each layer catches, and what nothing offline catches (verified) 🧊

Twelve mutations of the final render, each run through the schema validator and the audit:

| # | Mistake | Schema (v1.37.1 + CRDs) | Audit | Who catches it otherwise |
|---|---|---|---|---|
| N01 | `readinessProbes:` (typo) | ✅ unknown field | — | API server (strict field validation warns/fails) |
| N02 | `ensureEvenDistributionOfPartition` (KEDA metadata typo) | ❌ passes | ❌ passes | **Nobody by default.** KEDA ignores unknown trigger keys; with `KEDA_CHECK_UNEXPECTED_SCALERS_PARAMS=enabled` on the operator it logs an error and emits a Warning event, and still scales |
| N03 | `limitToPartitionsWithLag` + even distribution | ❌ passes | ✅ | The KEDA scaler at runtime ("cannot be set simultaneously") |
| N04 | VPA `updateMode: "off"` | ✅ not in the CRD enum | — | — |
| N05 | No `allowPrivilegeEscalation: false` | ❌ passes | ✅ PSS | Pod Security admission, at **pod** creation |
| N06 | Canary without `track` | ❌ passes | ✅ overlap | Nobody: wrong HPA math, mixed traffic |
| N07 | HPA `maxReplicas: 60` | ❌ passes | ✅ needs 104 CPU > 84 | Quota admission, during the next big scale-up |
| N08 | preStop 20 s, grace 45 s | ❌ passes | ✅ 55 > 45 | `SIGKILL` mid-drain, under load |
| N09 | Quota on `limits.cpu` | ❌ passes | ✅ | Quota admission rejects every pod without a CPU limit |
| N10 | `podFailurePolicy` with `restartPolicy: OnFailure` | ❌ passes | ❌ passes | **API server only** (cross-field rule) |
| N11 | `timeZone: Mars/Olympus_Mons` | ❌ passes | ❌ passes | **API server only** |
| N12 | HTTPRoute backend `port: 8080` (the Service exposes 80) | ❌ passes | ❌ passes | Gateway controller status (`ResolvedRefs`), or 5 % of requests failing |

So the CI pipeline is: render → schema → audit → policy (CEL) → promtool tests → **`kubectl apply --dry-run=server`** against a real cluster (the only offline-impossible layer, catching N10–N11) → canary (catching N12 and everything semantic). Each layer is cheap. None of them is sufficient alone.

---

## 8. Day-one runbook (not run here)

```bash
# 1. admission on YOUR cluster: Pod Security, VAP, quota, cross-field validation
kustomize build overlays/prod | kubectl apply --dry-run=server -f -
kubectl get validatingadmissionpolicy trusted-pinned-images -o jsonpath='{.status.typeChecking}'   # CEL type warnings

# 2. the guardrails are live
kubectl get ns orders --show-labels | tr ',' '\n' | grep pod-security
kubectl -n orders describe resourcequota                       # used vs hard; "used" includes terminating pods
kubectl -n orders run probe --image=busybox --rm -it --restart=Never -- true   # expect: denied (registry/digest)

# 3. the workloads
kubectl -n orders get deploy,hpa,scaledobject,pdb
kubectl -n orders get pdb -o custom-columns=NAME:.metadata.name,ALLOWED:.status.disruptionsAllowed   # never 0 at steady state
kubectl -n orders get httproute order-service -o jsonpath='{.status.parents[*].conditions}'          # Accepted + ResolvedRefs

# 4. the jobs
kubectl -n orders get cronjob outbox-purge -o jsonpath='{.status.lastSuccessfulTime}'
kubectl -n orders create job --from=cronjob/outbox-purge purge-smoke   # one manual run: proves egress + credentials

# 5. the alerts reach a human: fire one on purpose in staging (set the canary weight to 100 with a failing build)
```

---

## 9. ❌ Naïve vs ✅ production-hardened

| ❌ Naïve | ✅ Hardened |
|---|---|
| One YAML folder per environment, copied | A base + overlays; platform guardrails in a repository the service team can't change (§1) |
| Default-deny added "later" | Default-deny from day one, plus an audit of what each workload can reach (§5.1) |
| `minAvailable: 75%` everywhere | `maxUnavailable: 25%`: never 0 evictions at small scale (§5.2) |
| Quota = max replicas × requests | + surge + one terminating wave, computed from the render (§5.3) |
| Quota on `limits.cpu` "for fairness" | `requests.cpu` only; no default CPU limit (§2.2) |
| Image policy on Deployments only | On Pods, with the same check in CI for fast feedback (§2.5) |
| `startsWith('registry.example.com')` | With the trailing slash: the look-alike registry was denied (§2.5) |
| Migration in an initContainer | A Job with DDL credentials, applied and awaited first (§4.2) |
| Plain `SpringApplication.run` in the migration | Explicit exit codes 2/3; Boot's mappers aren't consulted on a failed refresh (§4.1) |
| `backoffLimit: 6` and hope | `podFailurePolicy`: permanent fails fast, drains don't count (§4.2) |
| A canary that shares the stable selector | `track` labels; the overlap audit (§3.3, N06) |
| Alerts reviewed by eye | promtool unit tests: they caught a label lost in vector matching (§6.2) |
| "It passed `kubeconform`, ship it" | Schema + audit + CEL + promtool + server-side dry run + canary (§7) |

---

## 10. Bar-raiser Q&A 🔥

🎤 *"Our manifests are validated in CI against the Kubernetes schema, so they're correct."*

🔍 **What did your schema validation miss last time?**

<details><summary>🛡️ Defense</summary>

On this blueprint, three things, all of which passed the v1.37.1 schema and every CRD schema. First, a CronJob with no NetworkPolicy in a default-deny namespace: it could resolve the database's name and nothing more. Second, a PDB with `minAvailable: 75%`, which at 2 replicas rounds up to 2 and allows zero evictions, so node drains would hang. Third, a quota sized for max replicas plus surge, while ResourceQuota also counts the previous wave's pods that are still terminating. A full-scale rollout needed 74 CPU against 70. A schema says the YAML is well-formed. Whether the system works is arithmetic over the rendered output, so I run an audit for reachability, PDB math, quota and shutdown budgets, plus a server-side dry run for the cross-field rules no offline tool knows.
</details>

🔍 **Why `maxUnavailable: 25%` instead of `minAvailable: 75%`? They sound the same.**

<details><summary>🛡️ Defense</summary>

They are the same at 40 replicas and very different at 2. The disruption controller rounds percentages up. 75 % of 2 is 2 that must stay, so zero evictions, and a cluster upgrade stalls on this namespace. 25 % of 2 rounds up to 1 that may go. `maxUnavailable` as a percentage never reaches zero for a running workload. The canary at 2 replicas and staging at 2 both allow one eviction with it. I keep `minAvailable` only for absolute floors, like "at least 2 replicas of a quorum".
</details>

🔍 **How did you size the namespace quota?**

<details><summary>🛡️ Defense</summary>

From the rendered manifests. For each workload: max replicas from its HPA or ScaledObject, plus `maxSurge`, plus one wave of terminating pods. The Deployment controller starts the next wave while the previous wave's old pods are still in their 45 s grace period. v1.37 reports them in `status.terminatingReplicas` but has no setting to wait for them, and quota counts them. That came to 84 pods and 74 CPU at peak. I set the quota so peak is 88 %, just under the 90 % alert. And there's no `limits.cpu` quota: it would reject our pods, which deliberately have no CPU limit, and the LimitRange "fix" would silently reintroduce throttling.
</details>

🔍 **The migration fails during a deploy. Walk me through what happens.**

<details><summary>🛡️ Defense</summary>

It depends on why. I measured that plain Spring Boot exits 1 for every startup failure: the `ExitCodeExceptionMapper` beans are skipped because the context never became active. So the migration main maps the failure itself: SQLState class 08 (can't connect) exits 2, anything else exits 3. The Job's `podFailurePolicy` fails the whole Job on 3 immediately (bad SQL won't fix itself), ignores pod disruptions from drains, and lets 2 count against `backoffLimit` with exponential back-off. The pipeline polls the Job's conditions and stops before the rollout on `Failed`. Nothing half-applied remains on PostgreSQL, because the DDL is transactional: the broken migration's first statement was rolled back too. Then `MigrationJobFailed` pages.
</details>

🔍 **Why not just run Flyway in an initContainer? Flyway has locking.**

<details><summary>🛡️ Defense</summary>

It does: two concurrent runs were safe, and the second waited about 5 s, then found the schema up to date. Safety isn't the problem. An initContainer gives DDL credentials to every API pod. A scale-out from 6 to 40 runs 34 migrations at once, 33 of them waiting on a database lock during the moment you most need capacity. A broken migration crash-loops every new pod, when it could fail one Job before the rollout. With expand/contract, the Job runs first and applies only changes the old version tolerates, so the ordering is safe.
</details>

🔍 **How do you know your alerts fire?**

<details><summary>🛡️ Defense</summary>

promtool unit tests, in CI, next to the rules. Synthetic series go in and the expected alerts, with exact labels, come out. They're not ceremony: the first run caught that my canary alert, written as `canary > on (namespace) 2 * stable`, fired without its `job` label, because one-to-one matching keeps only the `on` labels. `group_left` fixed it. The tests also check the negative cases: 1.5 % vs 1 % must not trip a 2× gate, and 1 % on stable must not page. Then, once per quarter in staging, a deliberate failure checks the routing to a human.
</details>

🔍 **What can't any of this catch?**

<details><summary>🛡️ Defense</summary>

Three classes of mistake. First, cross-field API rules: `podFailurePolicy` requires `restartPolicy: Never`, and an invalid `timeZone` is rejected only by the API server. That's why `kubectl apply --dry-run=server` against a real cluster is a CI step. Second, free-form maps: KEDA trigger metadata is `map[string]string`, so a typo passes every schema, and KEDA ignores unknown keys unless the operator runs with `KEDA_CHECK_UNEXPECTED_SCALERS_PARAMS=enabled`, which still only logs. Third, wiring across objects: an HTTPRoute pointing at a port the Service doesn't expose shows up only in the Gateway's status or in failing canary traffic. The canary exists for what's left.
</details>

---

## 11. Source to read

* [Pod Security Standards](https://kubernetes.io/docs/concepts/security/pod-security-standards/) and [Pod Security admission](https://kubernetes.io/docs/concepts/security/pod-security-admission/): the restricted controls, version pinning, enforce vs warn vs audit.
* [Resource quotas](https://kubernetes.io/docs/concepts/policy/resource-quotas/) (scopes, the requests/limits interaction) and [limit ranges](https://kubernetes.io/docs/concepts/policy/limit-range/).
* [Specifying a disruption budget](https://kubernetes.io/docs/tasks/run-application/configure-pdb/): percentages and rounding.
* [Jobs: pod failure policy and pod replacement policy](https://kubernetes.io/docs/concepts/workloads/controllers/job/#pod-failure-policy).
* [Validating admission policy](https://kubernetes.io/docs/reference/access-authn-authz/validating-admission-policy/): variables, bindings, `validationActions`.
* [Gateway API HTTPRoute](https://gateway-api.sigs.k8s.io/reference/api-types/httproute/) and the [traffic-splitting guide](https://gateway-api.sigs.k8s.io/guides/traffic-splitting/): weights, header matches, timeouts.
* [Kustomize `labels`](https://kubectl.docs.kubernetes.io/references/kustomize/kustomization/labels/): `includeSelectors` and which fields it touches.
* [KEDA Apache Kafka scaler](https://keda.sh/docs/2.21/scalers/apache-kafka/) and its [source](https://github.com/kedacore/keda/blob/main/pkg/scalers/kafka_scaler.go).
* [Prometheus unit testing for rules](https://prometheus.io/docs/prometheus/latest/configuration/unit_testing_rules/).

---

## 12. Interview soundbites

* "Schema validation passed and the blueprint still had three bugs: a CronJob that could only reach DNS, a PDB that allowed zero evictions, and a quota a full-scale rollout would blow. I audit the rendered output for those now."
* "PDB percentages round up. `minAvailable: 75%` of 2 pods blocks every drain; `maxUnavailable: 25%` never reaches zero."
* "Quota counts terminating pods; the Deployment controller doesn't wait for them. Budget max, plus surge, plus one terminating wave."
* "Plain Spring Boot exits 1 for every startup failure, because exit-code mappers aren't consulted when refresh fails. My migration main returns 2 for 'retry' and 3 for 'stop', and the Job's `podFailurePolicy` acts on them."
* "My alert tests caught `on (namespace)` stripping the `job` label from a canary page. `group_left` keeps it."
* "Image policy on Pods, with a trailing slash in the registry prefix. Without it, `registry.example.com.evil.io` passes."
* "KEDA ignores unknown trigger keys by default, so a typo in its metadata is invisible to every schema."

---

## Summary

| Topic | Key point | Evidence |
|---|---|---|
| Layout | Platform guardrails apart from the service's base and overlays; migrate → wait → roll out | §1 |
| Guardrails | Pod Security pinned + latest warn; quota on requests only; default-deny + DNS; scoped priority quota | §2.1–2.4 |
| Image policy | CEL on Pods: registry with trailing slash + digest; 8 templates allowed, 5 bad pods denied | §2.5 |
| Canary | `track` labels; kustomize relabels selector, template, topology spread; base labels don't reach a direct include | §3.3 |
| Consumer | KIP-848 dynamic, one consumer per pod, even partitions, KEDA reads the same ConfigMap | §3.2 |
| Migration | Boot exits 1 on any refresh failure; map 2/3; Flyway serialises concurrent runs; PG rolls back DDL | §4.1 |
| Job semantics | `podFailurePolicy`: FailJob on 3, Ignore disruptions, back-off for the rest; Job, not initContainer | §4.2 |
| Audit catches | CronJob DNS-only; PDB 0 evictions; quota without terminating pods | §5.1–5.3 |
| Alerts | Burn rates, canary gate, non-heap headroom, quota, lag at max; 8 promtool tests, one real bug | §6 |
| Limits | Schema/audit miss cross-field rules, free-form maps, cross-object wiring → dry-run=server + canary | §7 |

**Next:** [7.6 Bar-raiser drill-downs (Round 2 covers 7.7–7.8) →](06-Bar-Raiser-Drill-Downs.md)
