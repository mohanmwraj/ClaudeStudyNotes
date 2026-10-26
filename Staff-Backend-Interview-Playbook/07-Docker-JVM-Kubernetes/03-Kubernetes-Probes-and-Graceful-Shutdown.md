# 7.3 Kubernetes Probes and Graceful Shutdown with Spring Boot 4

> **Verified stack:** Spring Boot **4.1.2** (Tomcat 11.0.27, Actuator, `spring-boot-health`), Temurin **25.0.4.1**. The probe endpoints, availability-state events and graceful-shutdown sequence were run (`ProbeApp`, with `KUBERNETES_SERVICE_HOST` set to make Boot detect Kubernetes). Shutdown was triggered through Actuator's `shutdown` endpoint, which closes the context exactly as the JVM shutdown hook does on `SIGTERM`. **Not run here:** a cluster. The kubelet/EndpointSlice side of the timeline follows the Kubernetes pod-lifecycle documentation.
>
> **Related:** CKAD kit [probes and health checks](../../CKAD-Exam-Prep/03-Application-Observability-and-Maintenance/02-probes-and-health-checks.md), [rolling updates](../../CKAD-Exam-Prep/02-Application-Deployment/02-rolling-updates-and-rollbacks.md); [10.2 §2.2](../10-Kafka-Production/02-Kafka-Consumers-Rebalancing-EOS-Retries-DLQ.md) (consumers leaving the group on shutdown).

---

## 0. First principles: three questions and one deadline 🔥

Kubernetes asks your container three different questions, and acts very differently on the answers:

| Question | Probe | If the answer is "no" | So it must check |
|---|---|---|---|
| "Have you finished starting?" | `startupProbe` | Keep waiting (until `failureThreshold × periodSeconds`), then restart | Startup completed |
| "Are you alive, or should I restart you?" | `livenessProbe` | **Restart the container** | Only things a restart can fix: deadlock, corrupted internal state |
| "Should you receive traffic right now?" | `readinessProbe` | **Remove the pod from Service endpoints** (no restart) | Can *this pod* serve requests now? |

And one deadline: when a pod is deleted, it has **`terminationGracePeriodSeconds`** (default 30 s) to stop taking traffic, finish in-flight work and exit before the kubelet sends `SIGKILL`.

The most expensive probe mistake follows from the table: **a liveness probe that checks a dependency.** The database goes down, every pod fails liveness, Kubernetes restarts all of them, and now you have a database outage *plus* a fleet stuck in restart loops and cold starts. A restart can't fix the database.

---

## 1. Spring Boot's probe support (verified) ⚡

### 1.1 What Boot exposes

Boot tracks two availability states and maps them to health groups:

| State | Values | Health group / path |
|---|---|---|
| `LivenessState` | `CORRECT`, `BROKEN` | `/actuator/health/liveness` (and `/livez` on the main port) |
| `ReadinessState` | `ACCEPTING_TRAFFIC`, `REFUSING_TRAFFIC` | `/actuator/health/readiness` (and `/readyz`) |

Probe groups are enabled **automatically when Boot detects Kubernetes** (the `KUBERNETES_SERVICE_HOST`/`_PORT` environment variables), or with `management.endpoint.health.probes.enabled=true`.

**Output (verified, Boot 4.1.2, `KUBERNETES_SERVICE_HOST` set, `management.endpoint.health.probes.add-additional-paths=true`):**

```text
== probes (KUBERNETES_SERVICE_HOST set)
  /actuator/health/liveness    {"status":"UP"} [200]
  /actuator/health/readiness   {"status":"UP"} [200]
  /livez                       {"status":"UP"} [200]
  /readyz                      {"status":"UP"} [200]
  /actuator/health             {"groups":["liveness","readiness"],"status":"UP"} [200]
```

### 1.2 When states change (verified ordering from the app log)

(Abridged: timestamps shortened, PID/thread columns removed, `←` annotations added.)

```text
Tomcat started on port 18080 (http) with context path '/'
12:19:23.637  AVAILABILITY CORRECT                                   ← liveness: context refreshed
defaults: server.shutdown=GRACEFUL, spring.lifecycle.timeout-per-shutdown-phase=PT30S   ← printed by an ApplicationRunner
12:19:23.645  AVAILABILITY ACCEPTING_TRAFFIC                         ← readiness: only AFTER the runners finished
```

**`ApplicationRunner`s run before readiness flips to `ACCEPTING_TRAFFIC`.** That's the right hook for warm-up (prime caches, open connection pools, run a few requests through the JIT): Kubernetes won't route traffic to the pod until it's done.

Your code can change the states too:

```java
@Component
class FatalStateGuard {
    private final ApplicationEventPublisher events;
    FatalStateGuard(ApplicationEventPublisher events) { this.events = events; }

    void onUnrecoverable(Exception e) {                    // e.g. a corrupted local index, an irrecoverable consumer
        AvailabilityChangeEvent.publish(events, e, LivenessState.BROKEN);       // liveness fails → kubelet restarts us
    }

    void drainForMaintenance() {
        AvailabilityChangeEvent.publish(events, this, ReadinessState.REFUSING_TRAFFIC);  // out of the Service, still alive
    }
}
```

### 1.3 Which port to probe 🧊

* With `management.server.port` on a **separate port**, Actuator runs on its own connector. The probes can stay green while the **main** connector is saturated or wedged, so Kubernetes keeps sending traffic to a pod that can't serve it.
* `management.endpoint.health.probes.add-additional-paths=true` exposes `/livez` and `/readyz` on the **main** server port (verified above). Point the kubelet there, so the probe goes through the same connector and thread pool as real traffic.
* The flip side: under heavy load with platform threads, probe requests queue behind real work, liveness times out, and Kubernetes restarts pods **because** they're busy. Give liveness generous `timeoutSeconds` and `failureThreshold`. With virtual threads ([4.4](../04-Spring-Boot-Internals/04-Web-Concurrency-Tomcat-Virtual-Threads-WebFlux.md)) the queueing mostly disappears.

### 1.4 What goes into readiness 🧊

Readiness should answer "can this pod serve?", so include **pod-local** conditions (warm-up done, local resources OK) and leave out **shared** dependencies. If the shared database is down, every pod goes unready at once, the Service has zero endpoints, and clients get connection errors instead of your well-designed degraded response. Shared dependency health belongs in circuit breakers and dashboards ([6.1 §6.4](../06-Resilience-Caching/01-Resilience4j-Circuit-Breaker-Internals-Sliding-Windows.md)).

```yaml
management:
  endpoint:
    health:
      probes:
        enabled: true                    # also auto-enabled on Kubernetes
        add-additional-paths: true       # /livez, /readyz on the main port
      group:
        readiness:
          include: readinessState        # NOT db, redis, kafka: those are shared dependencies
        liveness:
          include: livenessState
```

---

## 2. Probe settings for a JVM service ⚡

```yaml
startupProbe:                      # covers JVM start + context refresh + warm-up runners
  httpGet: { path: /livez, port: http }
  periodSeconds: 2
  failureThreshold: 60             # up to 120 s to start; liveness and readiness don't run until this passes
livenessProbe:
  httpGet: { path: /livez, port: http }
  periodSeconds: 10
  timeoutSeconds: 3                # default is 1 s: one GC pause or CPU-throttled period → false failure
  failureThreshold: 3              # restart only after ~30 s of consistent failure
readinessProbe:
  httpGet: { path: /readyz, port: http }
  periodSeconds: 5
  timeoutSeconds: 2
  failureThreshold: 2              # out of rotation quickly
```

* **Startup probe instead of `initialDelaySeconds`**: no guessing; slow starts (cold node, image pull, CPU limit) don't get killed.
* **The 1-second default timeout** is the classic restart-storm cause on JVMs: a full GC, a throttled CPU period ([7.4](04-CPU-Throttling-GC-Choice-HPA-KEDA.md)) or a busy thread pool makes the probe late, never the app dead.

---

## 3. Graceful shutdown: the whole sequence 🔥

### 3.1 The timeline

```text
t = 0 s    Pod gets a deletionTimestamp (rolling update, scale-down, node drain, eviction)
           ├─ async: EndpointSlice controller removes the pod IP
           │         → kube-proxy, ingress controllers, service-mesh sidecars update over the next ~1–N s
           │         (until then, SOME clients still send NEW requests to this pod)
           └─ kubelet runs the preStop hook:  sleep 10 s        ← the pod keeps serving normally meanwhile
t = 10 s   kubelet sends SIGTERM to PID 1 (java, exec-form ENTRYPOINT: 7.2 §5)
           JVM shutdown hook → Spring closes the context:
             1. ReadinessState → REFUSING_TRAFFIC
             2. web server graceful shutdown: stop accepting connections, wait for in-flight requests
                (bounded by spring.lifecycle.timeout-per-shutdown-phase, default 30 s)
             3. other SmartLifecycle beans stop: Kafka listener containers (consumers leave the group),
                schedulers, message listeners
             4. beans destroyed: HikariCP pool closed, Kafka producers flushed and closed, executors drained
           process exits (code 0)
t = 45 s   terminationGracePeriodSeconds (counted from t = 0, INCLUDING preStop) → SIGKILL if still running
```

### 3.2 Verified: the Spring half

A `/slow` request (3 s) was in flight when shutdown started; then a new request was attempted. **Output (verified, Boot 4.1.2; client view first, then the app log, abridged as above).** (On Windows a refused connection takes ~2 s to fail, which is why the third line is late.)

```text
== graceful shutdown
  +807 ms POST /actuator/shutdown -> {"message":"Shutting down, bye..."}
  +1463 ms new GET /fast during shutdown ->  [000] exit=7
  +3820 ms GET /readyz during shutdown ->  [000] exit=7
  slow: HTTP 200 after 3.005769s
```

```text
12:19:39.912  /slow started
12:19:41.222  AVAILABILITY REFUSING_TRAFFIC
12:19:41.226  CONTEXT CLOSING
12:19:41.229  INFO o.s.boot.tomcat.GracefulShutdown : Commencing graceful shutdown. Waiting for active requests to complete
12:19:42.913  /slow finished
12:19:42.952  INFO [tomcat-shutdown] o.s.boot.tomcat.GracefulShutdown : Graceful shutdown complete
```

What it proves:

* **Graceful is the default in Boot 4.1.2** (`server.shutdown=GRACEFUL`, verified by printing the defaults), with a **30 s** per-phase timeout.
* Readiness flipped to `REFUSING_TRAFFIC` **first**, then Tomcat waited for the in-flight request: `/slow` completed with **200** after its full 3 s.
* **New connections were refused** (`curl` exit code 7, "couldn't connect") as soon as graceful shutdown began. That's exactly why the preStop sleep exists: any load balancer that hasn't yet removed this pod's IP would send requests into a closed port, and users would see connection errors or 502s.

### 3.3 Why `preStop: sleep` and not "just handle SIGTERM" 🧊

Kubernetes does two things **in parallel** when a pod is deleted: it removes the pod from endpoints (asynchronous, propagates through every kube-proxy, ingress and sidecar), and it starts terminating the container. Without a delay, the app can close its listener before the last load balancer has stopped sending traffic. The sleep simply waits out that propagation while the app still serves normally.

```yaml
lifecycle:
  preStop:
    sleep:
      seconds: 10              # native sleep action: no shell needed, so it works with distroless
terminationGracePeriodSeconds: 45   # ≥ preStop (10) + shutdown phase timeout (30) + margin (5)
```

(The `sleep` action has been on by default since Kubernetes 1.30. On older clusters, or with a shell in the image, `exec: { command: ["sh", "-c", "sleep 10"] }` does the same.)

### 3.4 The budget

```text
terminationGracePeriodSeconds  ≥  preStop sleep
                                 + spring.lifecycle.timeout-per-shutdown-phase   (web server drain)
                                 + time for the remaining phases (Kafka consumers committing and leaving, pools closing)
                                 + margin
```

If the sum exceeds the grace period, the `SIGKILL` arrives mid-shutdown: in-flight requests are cut, Kafka consumers don't leave the group (it waits `session.timeout.ms`, 45 s, to notice, then rebalances), and producer buffers are lost.

### 3.5 Things graceful shutdown doesn't handle for you ⚡

* **Long-lived connections** (WebSockets, SSE, gRPC streams) never "complete". Shutdown waits the full phase timeout and then cuts them. Send a close/GOAWAY with a reconnect hint when readiness flips.
* **Your own executors**: Spring-managed `ThreadPoolTaskExecutor` needs `setWaitForTasksToCompleteOnShutdown(true)` + `setAwaitTerminationSeconds(…)`; unmanaged `ExecutorService`s are just abandoned.
* **Work that must not be interrupted** (a batch step, a saga step) should be resumable and idempotent anyway, because `SIGKILL`, OOMKilled and node failures skip every hook.

---

## 4. Rollouts and disruptions ⚡

```yaml
spec:
  strategy:
    type: RollingUpdate
    rollingUpdate: { maxSurge: 25%, maxUnavailable: 0 }   # never drop below desired capacity
  minReadySeconds: 10                                      # a pod must stay ready 10 s before it counts as available
---
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata: { name: order-service }
spec:
  maxUnavailable: 25%                                      # rounds UP: never 0 evictions (minAvailable 75% of 2 pods = 0: 7.8 section 5.2)
  selector: { matchLabels: { app: order-service } }
```

* `maxUnavailable: 0` + readiness gating means a rollout only removes old pods after new ones are **ready**, which is after your warm-up runners.
* A PDB protects against **voluntary** disruptions (drains, cluster upgrades). It does nothing for crashes or OOM kills, so you still need enough replicas and topology spread ([7.5](05-Production-Blueprints-application-yml-Dockerfile-Deployment.md)).

---

## 5. ❌ Naïve vs ✅ production-hardened

| ❌ Naïve | ✅ Production-hardened |
|---|---|
| Liveness checks the DB / downstreams | Liveness = `livenessState` only |
| Readiness includes shared dependencies | Readiness = pod-local state; shared deps → breakers and alerts |
| `initialDelaySeconds: 60` | `startupProbe` with a generous failure threshold |
| Default `timeoutSeconds: 1` on a JVM | 2–3 s timeouts, failure thresholds that tolerate a GC pause |
| Probes on a separate management port only | `/livez`, `/readyz` on the main port (`add-additional-paths`) |
| No preStop: shutdown races endpoint removal | `preStop.sleep` 5–15 s |
| Grace period 30 s with a 30 s drain timeout + preStop | Grace ≥ preStop + drain + other phases + margin |
| Shell-form entrypoint (no `SIGTERM` for Java) | Exec form ([7.2](02-Dockerfiles-Multistage-Distroless-Layers-Buildpacks-Jib.md)) |
| Warm-up after readiness | Warm-up in `ApplicationRunner`s, which run before `ACCEPTING_TRAFFIC` |
| `maxUnavailable: 25%`, no PDB | `maxUnavailable: 0`, `minReadySeconds`, PDB |

---

## 6. Source to read

| Repo | Path | What to look for |
|---|---|---|
| [spring-projects/spring-boot](https://github.com/spring-projects/spring-boot) | `module/spring-boot-tomcat/src/main/java/org/springframework/boot/tomcat/GracefulShutdown.java` | How Tomcat's connectors are paused and active requests awaited |
| same | `core/spring-boot/src/main/java/org/springframework/boot/availability/` | `ApplicationAvailabilityBean`, the states and events |
| same | `module/spring-boot-health/src/main/java/org/springframework/boot/health/autoconfigure/actuate/endpoint/AvailabilityProbesAutoConfiguration.java` | Kubernetes detection and probe groups |
| [kubernetes/website](https://github.com/kubernetes/website) | `content/en/docs/concepts/workloads/pods/pod-lifecycle.md` | "Termination of Pods": the parallel endpoint removal and preStop/SIGTERM/SIGKILL sequence |

---

## 7. Interview soundbites

* "Startup gates the others, liveness restarts, readiness routes. Liveness never checks dependencies; a restart can't fix the database."
* "Boot runs `ApplicationRunner`s before readiness flips to accepting traffic, so warm-up goes there. I verified that ordering in the logs."
* "In Boot 4 graceful shutdown is the default with a 30-second phase timeout. In my run, readiness flipped to refusing first, the in-flight request completed with 200, and new connections were refused."
* "That refusal is why I add a preStop sleep: endpoint removal and SIGTERM happen in parallel, and the sleep covers propagation to every load balancer."
* "The grace period counts from deletion, including preStop, so it has to cover preStop plus the drain plus consumers leaving the group, or SIGKILL cuts everything."

---

## 8. Deep dive: shutdown and disruption budgets across a namespace (verified) 🔥

This module derived the budgets for one HTTP service. [7.8 §5](08-Kubernetes-Platform-Blueprints-II-Kustomize-Guardrails-Consumers-Jobs-Canary.md) checked them mechanically over a rendered namespace, and [10.4](../10-Kafka-Production/04-Consumer-Scaling-Static-Membership-KIP-848-KEDA-Rolling-Deploys.md) measured the consumer side:

| Budget | Result | Evidence |
|---|---|---|
| API: preStop 10 + drain 30 + margin 5 vs grace 45 | OK. Raising preStop to 20 without the grace period was caught (55 > 45) | 7.8 §5.4, N08 |
| Consumer: no preStop; 10 s container stop + in-flight record + margin vs grace 30 | OK. A consumer gets no Service traffic, so a preStop sleep only delays its LeaveGroup | 10.4 §6.3 |
| Consumer leaving the group (§3.4's "consumers leaving") | **0.5 s** for a KIP-848 dynamic member; **45 s** for a static member, whose `close()` doesn't leave at all | 10.4 §1.1 |
| PDB `minAvailable: 75%` (this module's §4 as first written) | At 2 or 3 replicas: **0 evictions allowed**, so node drains hang. Corrected in place to `maxUnavailable: 25%` | 7.8 §5.2 |
| Rollout at max scale | The Deployment controller **doesn't wait for terminating pods**; quota counts them. Budget one extra wave | 7.8 §5.3 |
| Batch pods during a drain | A Job's `podFailurePolicy` with `Ignore` on `DisruptionTarget` retries an evicted pod without spending its `backoffLimit` | 7.8 §4.2 |

What this adds to §3–§4:

* **§3.4's budget formula holds, with the drain term depending on the workload type.** HTTP: preStop + web drain. Consumer: in-flight work + spring-kafka's 10 s container stop, and no preStop. Batch: whatever the current step needs, and the step must be idempotent anyway, because a `SIGKILL` skips every hook.
* **PDB percentages round up.** That's harmless for large Deployments and fatal for small ones. `maxUnavailable` as a percentage never reaches zero; `minAvailable` as a percentage reaches it at small scale.
* **Terminating pods overlap the next wave.** In v1.37 `status.terminatingReplicas` (beta, on by default) reports them, but no spec field makes a rollout wait. A rollout at 40 replicas with a 45 s grace period briefly holds 40 + 10 new + up to 10 terminating pods. That's a quota and capacity question, not a correctness one.

---

## Summary

| Topic | Key point | Evidence |
|---|---|---|
| Three questions | Startup gates, liveness restarts, readiness routes; liveness never checks dependencies | §0, §2 |
| Boot's probes | `/livez` and `/readyz` groups; readiness flips after `ApplicationRunner`s | §1.1–§1.2 |
| Probe port and content | Main port; readiness = "can I serve", not "is everything I call healthy" | §1.3–§1.4 |
| Graceful shutdown | Boot 4 default, 30 s phase; readiness refuses first, in-flight completes, new connections refused | §3.1–§3.2 |
| preStop sleep | Endpoint removal and SIGTERM run in parallel; the sleep covers propagation | §3.3 |
| The budget | Grace ≥ preStop + drain + remaining phases + margin, counted from deletion | §3.4 |
| What it doesn't handle | Long-lived connections, unmanaged executors, non-idempotent work | §3.5 |
| Rollouts and PDBs | `maxUnavailable: 0`, `minReadySeconds`; PDB `maxUnavailable: 25%` (corrected) | §4, §8 |
| Namespace-wide budgets | Audited per workload; consumers without preStop; terminating pods cost quota | §8 (7.8 §5) |

**Next:** [7.4 CPU throttling, GC choice, HPA and KEDA →](04-CPU-Throttling-GC-Choice-HPA-KEDA.md)
