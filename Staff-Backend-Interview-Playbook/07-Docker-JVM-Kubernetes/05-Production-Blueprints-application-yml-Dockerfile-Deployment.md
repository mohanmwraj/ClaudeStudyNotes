# 7.5 Production Blueprints: `application.yml`, Dockerfile, Kubernetes Manifests

> **Verified stack:** Spring Boot **4.1.2**, Resilience4j **2.4.0**, Hibernate **7.4.13**, Kafka clients **4.2.2**, Temurin **25.0.4.1** / distroless Java **25.0.5**, Kubernetes **v1.37.1**, KEDA **v2.21.0**.
>
> These are the copy-paste-ready versions of everything Pillars 6 and 7 argued for, for one service (`order-service`: Spring MVC on virtual threads, PostgreSQL via JPA, Kafka, Redis, Resilience4j).

---

## 0. How these files were verified

| Artifact | Check | Result |
|---|---|---|
| `application.yml` | Every key checked against the `spring-configuration-metadata.json` of all Boot 4.1.2 modules used + `resilience4j-spring-boot4` (76 metadata files, 1,798 known properties), flagging unknown **and deprecated** keys | **88 keys, 0 problems** (it caught one: `spring.data.redis.lettuce.cluster.refresh.adaptive` was **removed in Boot 4.1**, "all adaptive triggers are enabled by default") |
| Map-typed keys inside it | Hibernate keys vs `AvailableSettings` constants; Kafka keys vs `ProducerConfig`/`ConsumerConfig.configNames()`; Resilience4j instance keys vs the `InstanceProperties` setters | **36 keys, 0 problems** |
| Kubernetes manifests | Structural validation (unknown fields, required fields, types) against the **official OpenAPI v3 schemas of Kubernetes v1.37.1** and the **KEDA v2.21.0 CRD** | **7 documents, 0 problems**. A negative test with 5 injected mistakes (typo'd field, string for an int, missing `name`, a misspelled KEDA field) reported all 5 |
| Dockerfile | Not built (no Docker here). Each step was run separately: `jarmode=tools extract --layers`, the merged layout started with `java -jar` and served `/actuator/health`, AOT cache training and use ([1.4](../01-Build-Systems/04-Enterprise-Builds-OCI-Images-Annotation-Processors-Enforcer.md), [7.2 §4.3](02-Dockerfiles-Multistage-Distroless-Layers-Buildpacks-Jib.md)); base tags, digest, user and entrypoint read from the registries | Build it once in CI before relying on it |

**Not verified here:** that the app works against *your* database, Kafka and Redis, or that the manifests are accepted by your cluster's admission policies. Run `kubectl apply --dry-run=server` and a staging deploy.

---

## 1. Dependencies (Maven, Boot 4.1.2 starters)

```xml
<dependencies>
  <dependency><groupId>org.springframework.boot</groupId><artifactId>spring-boot-starter-webmvc</artifactId></dependency>        <!-- Boot 4 name; -starter-web is deprecated -->
  <dependency><groupId>org.springframework.boot</groupId><artifactId>spring-boot-starter-validation</artifactId></dependency>
  <dependency><groupId>org.springframework.boot</groupId><artifactId>spring-boot-starter-actuator</artifactId></dependency>
  <dependency><groupId>io.micrometer</groupId><artifactId>micrometer-registry-prometheus</artifactId></dependency>           <!-- version from the Boot BOM -->
  <dependency><groupId>org.springframework.boot</groupId><artifactId>spring-boot-starter-opentelemetry</artifactId></dependency>
  <dependency><groupId>org.springframework.boot</groupId><artifactId>spring-boot-starter-data-jpa</artifactId></dependency>
  <dependency><groupId>org.springframework.boot</groupId><artifactId>spring-boot-starter-flyway</artifactId></dependency>
  <dependency><groupId>org.postgresql</groupId><artifactId>postgresql</artifactId><scope>runtime</scope></dependency>
  <dependency><groupId>org.springframework.boot</groupId><artifactId>spring-boot-starter-kafka</artifactId></dependency>
  <dependency><groupId>org.springframework.boot</groupId><artifactId>spring-boot-starter-data-redis</artifactId></dependency>
  <dependency><groupId>org.springframework.boot</groupId><artifactId>spring-boot-starter-cache</artifactId></dependency>
  <dependency><groupId>com.github.ben-manes.caffeine</groupId><artifactId>caffeine</artifactId></dependency>
  <dependency><groupId>org.springframework.boot</groupId><artifactId>spring-boot-starter-aspectj</artifactId></dependency>        <!-- Boot 4 name of the AOP starter -->
  <dependency><groupId>io.github.resilience4j</groupId><artifactId>resilience4j-spring-boot4</artifactId><version>2.4.0</version></dependency>
</dependencies>
```

The build itself (BOM import, Enforcer, annotation processors, reproducible builds) is the [1.4 blueprint](../01-Build-Systems/04-Enterprise-Builds-OCI-Images-Annotation-Processors-Enforcer.md).

---

## 2. `src/main/resources/application.yml` (validated)

```yaml
spring:
  application:
    name: order-service
  threads:
    virtual:
      enabled: true                               # Tomcat request handling, @Async, schedulers on virtual threads (4.4)
  lifecycle:
    timeout-per-shutdown-phase: 30s               # web-server drain budget (7.3)
  datasource:
    url: ${DB_URL}
    username: ${DB_USER}
    password: ${DB_PASSWORD}
    hikari:
      pool-name: order-db
      maximum-pool-size: 20                       # sized from DB capacity ÷ pods, not from threads (2.7)
      minimum-idle: 20                            # fixed-size pool: no churn under load
      connection-timeout: 2000                    # ms: fail fast instead of queueing forever
      max-lifetime: 1800000                       # ms: below any LB / DB idle cut-off
      keepalive-time: 300000
      leak-detection-threshold: 20000
  jpa:
    open-in-view: false                           # no lazy loading during view rendering (3.3)
    properties:
      hibernate:
        jdbc:
          batch_size: 50
          time_zone: UTC
        order_inserts: true
        order_updates: true
        default_batch_fetch_size: 32
        query:
          fail_on_pagination_over_collection_fetch: true
        id:
          optimizer:
            pooled:
              preferred: pooled-lo                # Hibernate 7 name (3.4)
  flyway:
    enabled: true
  kafka:
    bootstrap-servers: ${KAFKA_BOOTSTRAP_SERVERS}
    producer:
      acks: all
      compression-type: lz4
      batch-size: 64KB
      properties:
        linger.ms: 10
        enable.idempotence: true
        max.in.flight.requests.per.connection: 5
        delivery.timeout.ms: 120000
        max.block.ms: 5000
    consumer:
      group-id: order-service
      auto-offset-reset: earliest
      enable-auto-commit: false
      max-poll-records: 100
      isolation-level: read-committed
      properties:
        max.poll.interval.ms: 120000
        partition.assignment.strategy: org.apache.kafka.clients.consumer.CooperativeStickyAssignor
        group.instance.id: ${POD_NAME}
    listener:
      ack-mode: record
      concurrency: 3
      observation-enabled: true
    template:
      observation-enabled: true
  data:
    redis:
      url: ${REDIS_URL}
      timeout: 200ms                              # command timeout: a sick Redis must fail fast (6.3)
      connect-timeout: 1s
      lettuce:
        cluster:
          refresh:
            period: 30s                           # adaptive triggers are on by default since Boot 4.1
  cache:
    type: caffeine
    cache-names: products, prices
    caffeine:
      spec: maximumSize=50000,expireAfterWrite=10m,recordStats

server:
  port: 8080
  shutdown: graceful                              # the default in Boot 4.1.2; stated for readers
  forward-headers-strategy: framework             # behind an ingress / gateway
  max-http-request-header-size: 16KB

management:
  endpoints:
    web:
      exposure:
        include: health, info, prometheus
  endpoint:
    health:
      show-details: never
      probes:
        enabled: true
        add-additional-paths: true                # /livez and /readyz on the main port (7.3)
      group:
        readiness:
          include: readinessState
        liveness:
          include: livenessState
  metrics:
    tags:
      application: ${spring.application.name}
    distribution:
      percentiles-histogram:
        http.server.requests: true
  tracing:
    sampling:
      probability: 0.1
  opentelemetry:
    tracing:
      export:
        otlp:
          endpoint: ${OTEL_EXPORTER_OTLP_TRACES_ENDPOINT:http://otel-collector:4318/v1/traces}

logging:
  structured:
    format:
      console: ecs                                # one JSON object per line
  level:
    root: INFO
    org.apache.kafka: WARN

resilience4j:
  circuitbreaker:
    configs:
      default:
        sliding-window-type: TIME_BASED
        sliding-window-size: 20
        minimum-number-of-calls: 20
        failure-rate-threshold: 50
        slow-call-duration-threshold: 1s
        slow-call-rate-threshold: 60
        wait-duration-in-open-state: 10s
        permitted-number-of-calls-in-half-open-state: 5
        max-wait-duration-in-half-open-state: 15s
        writable-stack-trace-enabled: false
        ignore-exceptions:
          - org.springframework.web.client.HttpClientErrorException
          - io.github.resilience4j.bulkhead.BulkheadFullException
    instances:
      inventory:
        base-config: default
  retry:
    instances:
      inventory:
        max-attempts: 3
        wait-duration: 100ms
        enable-exponential-backoff: true
        exponential-backoff-multiplier: 2
        enable-randomized-wait: true
        randomized-wait-factor: 0.5
        ignore-exceptions:
          - io.github.resilience4j.circuitbreaker.CallNotPermittedException
  bulkhead:
    instances:
      inventory:
        max-concurrent-calls: 40
        max-wait-duration: 0
```

### 2.1 `application-aot-training.yml` (used only by the image build's training run)

```yaml
spring:
  flyway.enabled: false
  kafka.listener.auto-startup: false
  jpa.properties.hibernate.boot.allow_jdbc_metadata_access: false   # Hibernate 7.4 constant JdbcSettings.ALLOW_METADATA_ON_BOOT
  datasource.hikari.initialization-fail-timeout: -1
```

### 2.2 Why each block (cross-reference)

| Block | Failure it prevents | Where it's explained |
|---|---|---|
| Virtual threads + Hikari 20 | Thread exhaustion; and the pool, not threads, as the bulkhead | [4.4](../04-Spring-Boot-Internals/04-Web-Concurrency-Tomcat-Virtual-Threads-WebFlux.md), [6.2 §1.2](../06-Resilience-Caching-Kafka/02-Bulkheads-Rate-Limiters-Retries-Jitter-Decorator-Order.md) |
| `open-in-view: false`, batch fetch, `fail_on_pagination_over_collection_fetch` | N+1 in views, in-memory pagination | [3.3](../03-JPA-Hibernate-Spring-Data/03-NPlus1-Lazy-Loading-Fetch-Plans-Pagination-Projections.md) |
| Batch inserts + `pooled-lo` | One round trip per row | [3.4](../03-JPA-Hibernate-Spring-Data/04-Write-Throughput-Batching-Sequences-Hybrid-JDBC-jOOQ.md) |
| Kafka producer block | Loss, duplicates, small batches, blocked request threads | [6.5](../06-Resilience-Caching-Kafka/05-Kafka-Producers-Batching-Idempotence-Ordering.md) |
| Kafka consumer block | Skipped history, rebalance storms, stop-the-world rebalances | [6.6](../06-Resilience-Caching-Kafka/06-Kafka-Consumers-Rebalancing-EOS-Retries-DLQ.md) |
| Redis timeouts | A slow Redis stalling every request | [6.3](../06-Resilience-Caching-Kafka/03-Caching-Caffeine-W-TinyLFU-and-Redis-Lettuce-L1-L2.md), [6.4 §3.2](../06-Resilience-Caching-Kafka/04-Cache-Stampede-Penetration-Avalanche-Invalidation.md) |
| Probes, graceful shutdown | Restart storms, dropped requests on deploy | [7.3](03-Kubernetes-Probes-and-Graceful-Shutdown.md) |
| Tracing, histograms, ECS logs | Blind incident response | [5.7](../05-Microservices-Patterns/07-Observability-Tracing-Correlation-IDs-Contract-Testing.md) |
| Resilience4j | Cascading failure, retry storms | [6.1](../06-Resilience-Caching-Kafka/01-Resilience4j-Circuit-Breaker-Internals-Sliding-Windows.md), [6.2](../06-Resilience-Caching-Kafka/02-Bulkheads-Rate-Limiters-Retries-Jitter-Decorator-Order.md) |

---

## 3. `Dockerfile` and `.dockerignore`

```dockerfile
# syntax=docker/dockerfile:1.7
FROM eclipse-temurin:25.0.4.1_1-jdk-noble AS build
WORKDIR /workspace
COPY .mvn/ .mvn/
COPY mvnw pom.xml ./
COPY order-api/ order-api/
COPY order-service/ order-service/
RUN --mount=type=cache,target=/root/.m2 \
    ./mvnw -B -ntp -DskipTests package \
 && cp order-service/target/order-service-*.jar /tmp/application.jar \
 && java -Djarmode=tools -jar /tmp/application.jar extract --layers --destination /extracted

FROM gcr.io/distroless/java25-debian13:nonroot@sha256:5d3177252775d4b01603470fe21c015393019089904f68724bd37242e4bc6e6d
WORKDIR /app
COPY --from=build /extracted/dependencies/          ./
COPY --from=build /extracted/spring-boot-loader/    ./
COPY --from=build /extracted/snapshot-dependencies/ ./
COPY --from=build /extracted/application/           ./
USER 0
RUN ["/usr/bin/java", "-XX:+UseG1GC", "-XX:AOTCacheOutput=/app/app.aot", \
     "-Dspring.profiles.active=aot-training", "-Dspring.context.exit=onRefresh", \
     "-jar", "/app/application.jar"]
USER 65532:65532
EXPOSE 8080
ENTRYPOINT ["/usr/bin/java", "-XX:AOTCache=/app/app.aot", "-jar", "/app/application.jar"]
```

```text
# .dockerignore
**/target/
**/build/
.git
.idea
*.iml
**/*.log
.env
**/*.pem
```

The line-by-line reasoning is in [7.2 §4](02-Dockerfiles-Multistage-Distroless-Layers-Buildpacks-Jib.md). CI smoke test after the build (fails if the AOT cache doesn't match the runtime flags):

```bash
docker run --rm -e JAVA_TOOL_OPTIONS="-XX:+UseG1GC -XX:AOTMode=on" \
  --entrypoint /usr/bin/java order-service:ci \
  -XX:AOTCache=/app/app.aot -Dspring.profiles.active=aot-training -Dspring.context.exit=onRefresh -jar /app/application.jar
```

---

## 4. Kubernetes manifests (validated against v1.37.1 + KEDA v2.21.0)

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: order-service
  namespace: orders
automountServiceAccountToken: false            # the app doesn't call the Kubernetes API
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: order-service
  namespace: orders
  labels:
    app.kubernetes.io/name: order-service
    app.kubernetes.io/part-of: order-platform
spec:
  # no "replicas": the HPA owns it. A hard-coded value would reset the HPA's choice on every apply.
  revisionHistoryLimit: 5
  minReadySeconds: 10
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 25%
      maxUnavailable: 0
  selector:
    matchLabels:
      app.kubernetes.io/name: order-service
  template:
    metadata:
      labels:
        app.kubernetes.io/name: order-service
        app.kubernetes.io/part-of: order-platform
    spec:
      serviceAccountName: order-service
      automountServiceAccountToken: false
      terminationGracePeriodSeconds: 45        # ≥ preStop 10 s + drain 30 s + margin (7.3)
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
          whenUnsatisfiable: DoNotSchedule      # survive a zone loss
          labelSelector:
            matchLabels:
              app.kubernetes.io/name: order-service
        - maxSkew: 1
          topologyKey: kubernetes.io/hostname
          whenUnsatisfiable: ScheduleAnyway     # prefer different nodes, don't block scheduling
          labelSelector:
            matchLabels:
              app.kubernetes.io/name: order-service
      containers:
        - name: app
          image: registry.example.com/orders/order-service:1.4.0@sha256:0000000000000000000000000000000000000000000000000000000000000000   # CI writes the real digest
          imagePullPolicy: IfNotPresent
          ports:
            - name: http
              containerPort: 8080
              protocol: TCP
          env:
            - name: JAVA_TOOL_OPTIONS
              value: >-
                -XX:MaxRAMPercentage=70 -XX:InitialRAMPercentage=70
                -XX:+UseG1GC -XX:ActiveProcessorCount=2
                -XX:+ExitOnOutOfMemoryError -XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=/dumps
                -XX:MaxDirectMemorySize=128m
                -Xlog:gc*:file=/tmp/gc.log:time,uptime,level,tags:filecount=5,filesize=10m
            - name: MALLOC_ARENA_MAX
              value: "2"
            - name: SPRING_PROFILES_ACTIVE
              value: prod
            - name: POD_NAME                    # Kafka static membership: group.instance.id (6.6)
              valueFrom:
                fieldRef:
                  fieldPath: metadata.name
          envFrom:
            - secretRef:
                name: order-service-secrets     # DB_URL, DB_USER, DB_PASSWORD, REDIS_URL, KAFKA_BOOTSTRAP_SERVERS
          resources:
            requests:
              cpu: "1"
              memory: 1Gi
            limits:
              memory: 1Gi                       # memory requests = limits; no CPU limit (7.4 §1.1, strategy B)
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
      volumes:
        - name: tmp
          emptyDir:
            sizeLimit: 256Mi
        - name: dumps
          emptyDir:
            sizeLimit: 2Gi                      # survives container restarts (not pod deletion): copy the dump out
---
apiVersion: v1
kind: Service
metadata:
  name: order-service
  namespace: orders
  labels:
    app.kubernetes.io/name: order-service
spec:
  type: ClusterIP
  selector:
    app.kubernetes.io/name: order-service
  ports:
    - name: http
      port: 80
      targetPort: http
      protocol: TCP
---
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: order-service
  namespace: orders
spec:
  minAvailable: 75%
  selector:
    matchLabels:
      app.kubernetes.io/name: order-service
---
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: order-service
  namespace: orders
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: order-service
  minReplicas: 4
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
  namespace: orders
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: order-service
  policyTypes: ["Ingress"]
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: ingress    # the ingress controller / gateway namespace
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: monitoring # Prometheus scraping /actuator/prometheus
      ports:
        - port: 8080
          protocol: TCP
---
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: shipping-consumer
  namespace: orders
spec:
  scaleTargetRef:
    name: shipping-consumer
  minReplicaCount: 0
  maxReplicaCount: 12
  cooldownPeriod: 300
  triggers:
    - type: kafka
      metadata:
        bootstrapServers: kafka-0.kafka:9092,kafka-1.kafka:9092
        consumerGroup: shipping
        topic: order-events
        lagThreshold: "1000"
        activationLagThreshold: "50"
        offsetResetPolicy: earliest
        allowIdleConsumers: "false"
        limitToPartitionsWithLag: "true"
      authenticationRef:
        name: kafka-sasl
```

### 4.1 Decisions worth defending

| Decision | Why | Explained in |
|---|---|---|
| No `replicas` in the Deployment | The HPA owns the count; `kubectl apply` with `replicas` fights it | [7.4 §3](04-CPU-Throttling-GC-Choice-HPA-KEDA.md) |
| Memory request = limit, no CPU limit, `ActiveProcessorCount=2` | Guaranteed memory; burst CPU without CFS throttling; JVM threads sized deliberately | [7.1 §5](01-JVM-in-Containers-cgroups-v2-Memory-OOMKilled.md), [7.4 §1.1](04-CPU-Throttling-GC-Choice-HPA-KEDA.md) |
| 70 % heap of 1 GiB | ~700 MB heap leaves ~300 MB for the ~165 MB+ measured non-heap and growth | [7.1 §3](01-JVM-in-Containers-cgroups-v2-Memory-OOMKilled.md) |
| `ExitOnOutOfMemoryError` + dump to `emptyDir` | A broken JVM restarts; the dump survives the container restart for collection | [7.1 §4](01-JVM-in-Containers-cgroups-v2-Memory-OOMKilled.md) |
| Startup probe, generous liveness, quick readiness on `/livez` `/readyz` | No restart storms, no traffic before warm-up | [7.3 §2](03-Kubernetes-Probes-and-Graceful-Shutdown.md) |
| `preStop.sleep` 10 + grace 45 | Endpoint propagation before drain; drain before SIGKILL | [7.3 §3](03-Kubernetes-Probes-and-Graceful-Shutdown.md) |
| `maxUnavailable: 0`, `minReadySeconds`, PDB 75 % | Capacity never drops during rollouts and drains | [7.3 §4](03-Kubernetes-Probes-and-Graceful-Shutdown.md) |
| Zone spread `DoNotSchedule`, host spread `ScheduleAnyway` | Survive a zone loss without blocking scheduling on small clusters | — |
| Non-root, read-only FS, drop ALL, seccomp, no SA token | Smallest blast radius on compromise | [7.2 §6](02-Dockerfiles-Multistage-Distroless-Layers-Buildpacks-Jib.md) |
| `POD_NAME` → `group.instance.id` | Kafka static membership: no rebalance on a quick restart | [6.6 §2.2](../06-Resilience-Caching-Kafka/06-Kafka-Consumers-Rebalancing-EOS-Retries-DLQ.md) |
| KEDA consumer: lag per replica, capped at partitions, activation 50 | Scale on work, never past partitions, avoid 0↔1 flapping | [7.4 §4](04-CPU-Throttling-GC-Choice-HPA-KEDA.md) |

---

## 5. Day-one verification runbook

```bash
kubectl apply --dry-run=server -f k8s/                      # admission + schema on YOUR cluster
kubectl apply -f k8s/ && kubectl -n orders rollout status deploy/order-service

kubectl -n orders get pods -o wide                          # spread across zones/nodes?

kubectl -n orders port-forward deploy/order-service 8080
curl -s localhost:8080/readyz; curl -s localhost:8080/livez
# Did the JVM size itself as intended? Ask the app, don't start a second JVM inside a memory-capped pod:
curl -s localhost:8080/actuator/prometheus | grep -E '^jvm_memory_max_bytes\{area="heap"|^system_cpu_count|^jvm_gc_pause_seconds_count'
#   heap max ≈ 70 % of 1 GiB, system_cpu_count = 2 (ActiveProcessorCount), gc="G1 Young Generation" / "G1 Concurrent GC"
curl -s localhost:8080/actuator/prometheus | grep -E '^hikaricp_connections|^resilience4j_circuitbreaker_state'

# under load in staging:
#   container_memory_working_set_bytes  < ~85 % of the limit at peak
#   rate(container_cpu_cfs_throttled_periods_total[5m]) / rate(container_cpu_cfs_periods_total[5m])  near 0
#   a rolling restart with traffic: zero 5xx, zero connection errors
#   kill -9 a pod (kubectl delete pod --grace-period=0 --force): consumers rebalance, no data loss
```

---

## 6. Interview soundbites

* "Everything in this blueprint is checked mechanically: config keys against Boot's own metadata, manifests against the cluster version's OpenAPI schema. That's how I caught a Redis property Boot 4.1 removed."
* "Memory request equals limit, heap at 70 % to leave room for the measured non-heap, no CPU limit but the JVM's processor count pinned, so thread pools match what the pod gets."
* "The Deployment has no replica count because the HPA owns it."
* "Startup, liveness and readiness each answer a different question, and the grace period covers preStop, drain and consumer shutdown."

**Next:** [7.6 Bar-raiser drill-downs →](06-Bar-Raiser-Drill-Downs.md)
