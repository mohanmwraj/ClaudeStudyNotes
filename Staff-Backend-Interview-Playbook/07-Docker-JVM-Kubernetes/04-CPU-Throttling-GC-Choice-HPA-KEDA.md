# 7.4 CPU in Kubernetes: CFS Throttling, Sizing JVM Threads, Choosing a GC, HPA and KEDA

> **Verified stack:** Temurin **25.0.4.1**; Kubernetes **v1.37.1** (HPA controller defaults read from `pkg/controller/podautoscaler/config/v1alpha1/defaults.go`); KEDA **v2.21.0** (Kafka scaler metadata keys and defaults read from `pkg/scalers/kafka_scaler.go`).
>
> **What was run:** JVM thread ergonomics per CPU count, and a GC comparison (Serial, Parallel, G1, ZGC) **pinned to 2 CPUs** with Windows process affinity. That's like a `cpuset`: it shows CPU *scarcity*. It does **not** reproduce CFS *quota throttling*, which needs a Linux cgroup. The throttling section is a first-principles model; run the commands given to see it on a real node.
>
> **Related:** [7.1](01-JVM-in-Containers-cgroups-v2-Memory-OOMKilled.md) (how the JVM detects CPUs), [10.2 §6](../10-Kafka-Production/02-Kafka-Consumers-Rebalancing-EOS-Retries-DLQ.md) (consumer scaling limits), sibling kit [GC](../../Java-Backend-Master-Reference/01-JVM-Internals/04-Garbage-Collection-G1-ZGC-Shenandoah.md), [JFR & profiling](../../Java-Backend-Master-Reference/08-Observability-Security-Testing/01-JVM-Profiling-JFR-async-profiler-Thread-Dumps.md).

---

## 0. First principles: requests share, limits cap 🔥

| Setting | Becomes (cgroup v2) | Effect |
|---|---|---|
| `requests.cpu` | `cpu.weight` + scheduler bookkeeping | **Placement** (the scheduler reserves it on a node) and **share under contention**. Never a cap |
| `limits.cpu` | `cpu.max` = `quota period`, period **100 ms** | **Hard cap per period**: the cgroup may use `quota` µs of CPU time across *all* its threads every 100 ms, even if the node is idle |

The cap is per **period**, not per second, and it's shared by **all threads**. A JVM is very multi-threaded (request threads, GC workers, JIT compilers), so it can spend a whole period's quota in a fraction of the period. Then **every thread in the container is frozen until the next period starts**. That's **CFS throttling**.

### 0.1 The throttling model, with numbers

```text
limits.cpu: 2  →  quota = 200 ms of CPU per 100 ms period

JVM started without a limit-aware thread count (sees a 16-core node): 13 parallel GC threads
young GC needs ~200 ms of CPU work:
   13 threads × ~15 ms wall = quota gone at t ≈ 15 ms
   → ALL threads (request threads too) frozen for the remaining ~85 ms of the period
   → users see a ~100 ms stall for a GC that "took 15 ms" in the GC log

Same GC work with ParallelGCThreads = 2 (sized to the quota):
   2 threads × 100 ms wall = 200 ms CPU, spread across the period, no freeze beyond the GC itself
```

Two lessons. **Thread counts must match the quota**, otherwise parallelism becomes stalls. And **averages hide it**: a pod at 40 % average CPU can be throttled in 30 % of its periods, because work arrives in bursts (GC, JIT, request spikes).

How to see it on a real node:

```bash
cat /sys/fs/cgroup/cpu.stat                       # nr_periods, nr_throttled, throttled_usec
# Prometheus (cAdvisor):
#   rate(container_cpu_cfs_throttled_periods_total[5m]) / rate(container_cpu_cfs_periods_total[5m])
```

Alert when the throttled-period ratio stays above a few percent for latency-sensitive services, regardless of average CPU.

---

## 1. The JVM's view of CPUs (verified) ⚡

```text
  -XX:ActiveProcessorCount available  commonPool par.  ParallelGCThreads ConcGCThreads     CICompilerCount
  1                      1          1                1                 1                 2
  2                      2          1                2                 1                 2
  4                      4          3                4                 1                 3
  8                      8          7                8                 2                 4
  16                     16         15               13                3                 12
```

* With a CPU **limit**, the JVM derives the count from `cpu.max` (rounded up), and everything above scales with it.
* With **no limit**, it sees the whole node (requests have been ignored since JDK 19). On a 64-core node that's 43 parallel GC threads and a common pool of 63 inside a pod that asked for 1 CPU.
* With one CPU, the JVM also picks **SerialGC** by default ([7.1 §2.2](01-JVM-in-Containers-cgroups-v2-Memory-OOMKilled.md)).

### 1.1 Three ways to set CPU, with the trade-offs 🧊

| Strategy | Pod spec | JVM flags | Pros | Cons |
|---|---|---|---|---|
| **A. Limit = request** | `requests.cpu: 2`, `limits.cpu: 2` | Detected automatically (2) | Predictable; Guaranteed QoS if memory matches too | Throttled on every burst (GC, JIT, startup); slow starts |
| **B. Request only, no limit** | `requests.cpu: 1` | `-XX:ActiveProcessorCount=2` (or 3–4) | Uses idle node CPU for bursts and startup; no CFS throttling | Noisy neighbors; capacity planning by requests; needs explicit thread sizing |
| **C. Exclusive cores** | Integer CPUs, Guaranteed QoS, kubelet `cpuManagerPolicy: static` | Detected (cpuset) | No throttling and no sharing: lowest jitter | Node-level setting; whole cores only; wastes capacity |

Many platform teams run **B** for JVM services and **A** for batch or multi-tenant clusters. The staff answer is not a slogan ("never set CPU limits"). It's: *measure throttling; whichever you choose, make the JVM's thread counts match the CPU the pod actually gets.*

The JVM computes most pool sizes **at startup**. If the platform resizes CPU in place (in-place pod resize), GC/JIT/common-pool thread counts don't follow. Plan for a restart.

---

## 2. Choosing a garbage collector for a pod 🔥

### 2.1 One measured run on 2 CPUs

Workload: a ~150 MB live set (a cache of 1 KB entries, 1 in 32 requests replaces one), plus 8 × 256-byte request-scoped objects per request; **512 MB heap**; process **pinned to 2 CPUs**; `-XX:ActiveProcessorCount=2`; one worker thread (so the app itself uses at most half the CPUs). A "hiccup" thread asks to sleep 1 ms in a loop and records how much later it woke up. That's the stall any request thread would have seen. 15 s measured after 3 s of warm-up.

```text
baseline-G1  (no worker)   ops/s=         0 alloc≈     0 MB/s  stall µs: p50=  998 p99=  2,061 p99.9=  2,698 max=  4,586   pauses=0, pause time=0 ms
Serial                     ops/s= 4,729,407 alloc≈10,442 MB/s  stall µs: p50=  999 p99=  4,263 p99.9= 76,653 max= 83,018   pauses=1092, pause time=3,290 ms
Parallel                   ops/s= 5,286,443 alloc≈11,672 MB/s  stall µs: p50=  997 p99=  2,858 p99.9= 47,521 max= 49,322   pauses=1014, pause time=2,012 ms
G1                         ops/s= 3,815,052 alloc≈ 8,423 MB/s  stall µs: p50=  999 p99= 22,914 p99.9= 24,221 max= 25,068   pauses=424, pause time=2,095 ms
ZGC                        ops/s= 4,311,638 alloc≈ 9,520 MB/s  stall µs: p50=  988 p99= 16,526 p99.9= 32,344 max= 69,410   pauses=4221, pause time=20 ms
```

(Collector bean names trimmed for width. The baseline shows the OS sleep jitter: about 1 ms at p50 and 2 ms at p99 on Windows. "Pause time" counts only stop-the-world pause beans, not concurrent cycles.)

What to take from it, and what not to:

* **ZGC's pauses totaled 20 ms over 4,221 pauses**, sub-millisecond each, yet the application still saw stalls up to **69 ms**. On 2 CPUs, ZGC's *concurrent* threads compete with the application for CPU, and when allocation outruns concurrent collection, allocating threads stall. **Pause time is not application latency** when CPU is scarce.
* **G1** traded throughput (lowest ops/s) for a tight, flat tail (p99 23 ms, max 25 ms).
* **Serial and Parallel** had the best p99 here, then long tails at p99.9 and max (77–83 ms and 48–49 ms): the occasional big stop-the-world collection.
* It's **one run of a synthetic workload** with affinity rather than a CFS quota. It doesn't crown a winner. It shows **how** to choose: measure *stalls* (or request latency), not GC-reported pause times, with the CPU and heap your pod actually has.

### 2.2 Matrix

| | Serial | Parallel | G1 (default ≥ 2 CPUs) | ZGC (generational) | Shenandoah |
|---|---|---|---|---|---|
| Pauses | STW, single-threaded | STW, parallel | Mostly short STW young/mixed pauses; concurrent marking | Sub-ms STW; marking, relocation concurrent | Sub-ms-ish STW; concurrent compaction |
| Throughput | OK for tiny heaps | **Best** | Good | Good; costs CPU for concurrent work | Good; costs CPU |
| CPU need | 1 core | Bursty, all cores during GC | Moderate | **Needs headroom** for concurrent threads | Needs headroom |
| Heap overhead | Lowest | Low | Remembered sets, more native memory ([7.1 §3](01-JVM-in-Containers-cgroups-v2-Memory-OOMKilled.md): 55 MB "GC" at a 256 MB heap) | Needs free heap headroom so allocation doesn't outrun collection | Similar |
| Pod fit | ≤ 1 CPU, small heap, tools and sidecars | Batch, throughput jobs | General-purpose services, 2–8 CPUs | Latency-sensitive, multi-GB heaps, CPU headroom | Same niche as ZGC |

Rules of thumb:

* **Set the collector explicitly.** Don't let the pod's CPU and memory pick it ([7.1](01-JVM-in-Containers-cgroups-v2-Memory-OOMKilled.md)).
* ZGC in a 2-CPU pod with a tight heap is the configuration most likely to disappoint. Give it CPU and 20–30 % heap headroom, or stay on G1.
* Turn on GC logging and continuous JFR in production, both cheap: `-Xlog:gc*:file=/logs/gc.log:time,uptime,level,tags:filecount=5,filesize=20m` and `-XX:StartFlightRecording=maxage=1h,maxsize=200m,dumponexit=true,filename=/logs/`.

---

## 3. Horizontal Pod Autoscaler ⚡

### 3.1 The algorithm and its defaults (verified in Kubernetes source)

```text
desiredReplicas = ceil( currentReplicas × currentMetricValue / targetMetricValue )

  6 pods, CPU utilization 85 % (of REQUESTS), target 60 %  →  ceil(6 × 85 / 60) = ceil(8.5) = 9 pods

controller defaults (pkg/controller/podautoscaler/config/v1alpha1/defaults.go):
  sync period                        15 s
  tolerance                          0.1      (no action within ±10 % of target)
  downscale stabilization window     5 min    (scale-down uses the highest recommendation of the last 5 min)
  CPU initialization period          5 min    (CPU samples of just-started pods are treated specially)
  initial readiness delay            30 s
```

### 3.2 JVM-specific traps 🧊

* **Utilization is relative to requests.** Requests far below real usage → utilization "300 %" → over-scaling. No requests → the HPA can't compute CPU utilization at all.
* **Startup CPU spike**: class loading and JIT make a new JVM burn CPU for its first seconds or minutes. Without care, new pods look overloaded, the HPA adds more, and those start up too. Mitigations: the controller's CPU initialization period and readiness delay (above), readiness that flips only after warm-up ([7.3 §1.2](03-Kubernetes-Probes-and-Graceful-Shutdown.md)), the AOT cache for shorter startups ([7.2 §4](02-Dockerfiles-Multistage-Distroless-Layers-Buildpacks-Jib.md)), and scale-up `behavior` policies.
* **Don't autoscale a JVM on memory.** The heap grows to its max and rarely returns memory to the OS, so a memory target scales up and never down.
* **Better signals**: requests per second per pod, in-flight requests, or queue depth (custom or external metrics). They relate directly to load, while CPU is an indirect proxy.
* **Nodes take time.** If new pods are `Pending` until the cluster autoscaler (or Karpenter) adds a node, reaction time includes node provisioning. Keep some headroom or use overprovisioning placeholder pods.

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata: { name: order-service }
spec:
  scaleTargetRef: { apiVersion: apps/v1, kind: Deployment, name: order-service }
  minReplicas: 4
  maxReplicas: 40
  metrics:
    - type: Resource
      resource: { name: cpu, target: { type: Utilization, averageUtilization: 60 } }
  behavior:
    scaleUp:
      stabilizationWindowSeconds: 0
      policies:
        - { type: Percent, value: 100, periodSeconds: 60 }   # at most double per minute
        - { type: Pods, value: 4, periodSeconds: 60 }
      selectPolicy: Max
    scaleDown:
      stabilizationWindowSeconds: 300
      policies:
        - { type: Percent, value: 20, periodSeconds: 60 }    # shrink gently
```

---

## 4. KEDA: scaling on events, and to zero ⚡

KEDA is an operator: a `ScaledObject` describes **triggers** (Kafka lag, Prometheus queries, queues, cron, …). KEDA creates and manages an HPA fed with those external metrics, and handles **0 ↔ 1** itself (activation), which a plain HPA can't.

### 4.1 Kafka lag scaler (keys and defaults verified in v2.21.0)

```yaml
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata: { name: shipping-consumer }
spec:
  scaleTargetRef: { name: shipping-consumer }          # a Deployment
  minReplicaCount: 0                                    # scale to zero when there's nothing to do
  maxReplicaCount: 12
  cooldownPeriod: 300
  triggers:
    - type: kafka
      metadata:
        bootstrapServers: kafka-0.kafka:9092,kafka-1.kafka:9092
        consumerGroup: shipping
        topic: order-events
        lagThreshold: "1000"                            # target lag PER REPLICA (default 10)
        activationLagThreshold: "50"                    # 0 → 1 only when lag > 50 (default 0)
        offsetResetPolicy: earliest                     # default latest; match the consumer's auto.offset.reset
        allowIdleConsumers: "false"                     # default false: never more replicas than partitions
        limitToPartitionsWithLag: "true"                # default false: cap at partitions that actually have lag
      authenticationRef: { name: kafka-sasl }           # TriggerAuthentication: sasl, username, password, tls…
```

```text
replicas ≈ ceil(total lag / lagThreshold), capped by partitions (allowIdleConsumers=false)

  lag 12,000 on a 6-partition topic, lagThreshold 1,000 → 12 → capped at 6
```

That cap is the consumer-group rule from [10.2](../10-Kafka-Production/02-Kafka-Consumers-Rebalancing-EOS-Retries-DLQ.md): more consumers than partitions sit idle.

### 4.2 Trade-offs to state in an interview 🧊

* **Scale to zero means a cold start for the first event**: JVM start + context refresh + group join. The AOT cache and a cooperative or KIP-848 group protocol shorten it; a latency SLO on the first message may rule it out.
* **Every scale event is a rebalance.** With the eager assignor, each one pauses all consumers ([10.2 §2](../10-Kafka-Production/02-Kafka-Consumers-Rebalancing-EOS-Retries-DLQ.md)). Use cooperative-sticky or KIP-848, and a `cooldownPeriod` and HPA `behavior` that don't flap.
* **Lag isn't time.** 10,000 tiny records may be 2 s of work; 10,000 image-processing records may be an hour. If processing cost varies, scale on a Prometheus query of *time lag* or processing backlog seconds instead.
* A **Prometheus trigger** works for HTTP services too: for example `sum(rate(http_server_requests_seconds_count{app="order-service"}[2m]))` with a threshold in requests per second per replica.

---

## 5. ❌ Naïve vs ✅ production-hardened

| ❌ Naïve | ✅ Production-hardened |
|---|---|
| No CPU limit and default JVM thread counts (= node cores) | `-XX:ActiveProcessorCount` set to what the pod should use |
| CPU limit chosen without looking at throttling | Throttled-period ratio on dashboards and alerts; limits chosen by measurement |
| GC chosen by the JVM from pod size (Serial at 1 CPU) | Collector set explicitly; ZGC only with CPU and heap headroom |
| GC pause times as the latency metric | Request latency / stall measurements under the pod's real CPU budget |
| HPA on memory for a JVM | CPU against honest requests, or better: RPS, in-flight, queue depth |
| HPA reacting to startup CPU spikes | Readiness after warm-up, initialization period, AOT cache, scale-up policies |
| Scale consumers on lag past the partition count | KEDA Kafka scaler capped at partitions; partitions sized for max parallelism |
| Scale to zero for a latency-critical consumer | `minReplicaCount ≥ 1` where first-event latency matters |

---

## 6. Source to read

| Repo | Path | What to look for |
|---|---|---|
| [kubernetes/kubernetes](https://github.com/kubernetes/kubernetes) | `pkg/controller/podautoscaler/replica_calculator.go` | The ratio formula, tolerance, how unready and missing pods are treated |
| same | `pkg/controller/podautoscaler/config/v1alpha1/defaults.go` | The defaults quoted above |
| [kedacore/keda](https://github.com/kedacore/keda) | `pkg/scalers/kafka_scaler.go` | Lag computation, partition cap, activation |
| [openjdk/jdk](https://github.com/openjdk/jdk) | `src/hotspot/share/gc/shared/gcConfig.cpp` | Default collector selection |
| same | `src/hotspot/share/gc/shared/workerPolicy.cpp` | How `ParallelGCThreads` / `ConcGCThreads` are derived from the CPU count |

---

## 7. Interview soundbites

* "Requests are for placement and sharing; limits are a hard cap per 100 ms period across all threads. A many-threaded JVM can burn its quota in 15 ms and freeze for 85."
* "Whatever CPU policy we pick, I make the JVM's thread counts match it with `ActiveProcessorCount`. Without a limit it sees the whole node."
* "On 2 pinned CPUs, ZGC reported 20 ms of total pauses, but the app still saw stalls up to 69 ms, because concurrent GC needs CPU too. I choose collectors by measured latency, not reported pauses."
* "HPA utilization is relative to requests, the scale-down window is five minutes by default, and JVM startup spikes need readiness gating and initialization periods. I'd rather scale on RPS or queue depth."
* "KEDA's Kafka scaler targets lag per replica and caps at partitions by default. Scale-to-zero costs a cold start and every scale event is a rebalance."

---

## 8. Deep dive: autoscaling inside quotas and partitions (verified) 🔥

An autoscaler decides how many pods it *wants*. Quotas, partitions and the controller around it decide how many it *gets*, and whether they help. Batch 3 measured each limit:

| Limit | Result | Evidence |
|---|---|---|
| KEDA's partition cap | Counts **pods**, not consumers: `concurrency: 3` × 12 replicas = 36 consumers for 12 partitions, 24 idle | [10.4 §3.1](../10-Kafka-Production/04-Consumer-Scaling-Static-Membership-KIP-848-KEDA-Rolling-Deploys.md) |
| Uneven partitions | 12 partitions over 5 consumers = the throughput of 4. `ensureEvenDistributionOfPartitions` steps through factors of 12; it **can't be combined** with `limitToPartitionsWithLag` (KEDA source) | 10.4 §3.2 |
| `cooldownPeriod` | Governs only N → 0; between 1 and N it's the HPA `behavior` under `advanced.horizontalPodAutoscalerConfig` | 10.4 §3.4 |
| Every scale-down is a rebalance | KIP-848 dynamic: 0.5 s; a static member: 45 s, which builds lag and invites a scale-up | 10.4 §1, §3.3 |
| Quota at the HPA maximum | Peak = max + surge + **one terminating wave**: 74 CPU for this namespace. An HPA max of 60 would need 104 CPU against a quota of 84 (caught) | [7.8 §5.3](08-Kubernetes-Platform-Blueprints-II-Kustomize-Guardrails-Consumers-Jobs-Canary.md), N07 |
| CPU limits via policy | A `limits.cpu` quota rejects the no-limit pods of §1.1. A LimitRange default CPU limit "fixes" that by **silently reintroducing throttling** | 7.8 §2.2, N09 |
| KEDA configuration typos | Trigger metadata is `map[string]string`: a typo passes every schema and KEDA **ignores unknown keys** by default | 7.8 §7, N02 |

Design rules:

* **Divide KEDA's maximum by the consumers per pod**, or run one consumer per pod (7.8 does).
* **Choose partition counts with many divisors** (12, 24, 60), because replica steps between divisors buy nothing.
* **Size the namespace quota from the rendered maxima, surge and terminating pods included.** An HPA that can't create pods fails quietly: the ReplicaSet shows `FailedCreate`, and the `NamespaceQuotaNearlyFull` alert is the early warning.
* **Keep CPU policy explicit end to end**: no CPU limit, no `limits.cpu` quota, no LimitRange CPU default, and `ActiveProcessorCount` pinned in the JVM profile ([7.7 §4.6](07-Container-Images-and-JVM-Profiles-Blueprints-II-jlink-AOT-Workloads.md)).

The GC choice in §2 became per-workload profiles in 7.7: G1 pinned for the API, Serial with 256 MB for 1-CPU consumers, Parallel for batch.

---

## Summary

| Topic | Key point | Evidence |
|---|---|---|
| Requests vs limits | Requests place and share; limits cap per 100 ms period across all threads (15 ms burn, 85 ms freeze) | §0, §0.1 |
| The JVM's CPU view | Without a limit it sees the node; pin `ActiveProcessorCount` | §1 |
| CPU strategies | A: limit = request; B: request only + `ActiveProcessorCount`; C: exclusive cores (static CPU manager) | §1.1 |
| GC in a pod | ZGC reported 20 ms of pauses while the app saw 69 ms stalls on 2 CPUs; choose by measured latency | §2.1–§2.2 |
| HPA | Utilization relative to requests; 5-minute scale-down window; JVM startup spikes need readiness gating | §3.1–§3.2 |
| KEDA | Lag per replica, activation threshold, capped at partitions; scale-to-zero costs a cold start | §4 |
| Limits on scaling | Pods vs consumers, factors of the partition count, cooldown only to zero | §8 (10.4) |
| Quotas | Max + surge + terminating wave; no `limits.cpu` quota; no LimitRange CPU default | §8 (7.8) |

**Next:** [7.5 Production blueprints: application.yml, Dockerfile, Deployment →](05-Production-Blueprints-application-yml-Dockerfile-Deployment.md)
