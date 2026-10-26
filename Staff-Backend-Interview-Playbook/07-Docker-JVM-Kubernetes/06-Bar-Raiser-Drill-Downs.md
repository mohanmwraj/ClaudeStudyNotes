# 7.6 Bar-Raiser Drill-Downs: Docker, the JVM, and Kubernetes

> Evidence: [7.1](01-JVM-in-Containers-cgroups-v2-Memory-OOMKilled.md)–[7.5](05-Production-Blueprints-application-yml-Dockerfile-Deployment.md) (Temurin 25.0.4.1 ergonomics and NMT, a GC comparison on 2 pinned CPUs, Boot 4.1.2 probes and graceful shutdown, layer extraction, AOT cache flag mismatch, registry metadata, configs validated against Boot metadata and manifests against Kubernetes v1.37.1 schemas). Container-kernel behavior (cgroup OOM kill, CFS throttling) is explained from first principles; there was no Linux container on the test machine.
>
> 🎤 candidate · 🔍 interviewer probe · 🛡️ staff-level defense

---

## Drill 1: "Our pods keep getting OOMKilled, so we raised `-Xmx`" 🔥

🔍 **Probe 1: Who killed the process?**

<details><summary>🛡️ Defense</summary>

The **kernel**, not the JVM. OOMKilled means the cgroup's total memory hit `memory.max`: SIGKILL, exit code 137, `Reason: OOMKilled`, `oom_kill` incremented in `memory.events`. No stack trace, no heap dump. A heap problem shows up as a Java `OutOfMemoryError` instead. So raising `-Xmx` gives the heap more of the same limit and leaves **less** room for everything else. It makes this worse.
</details>

🔍 **Probe 2: Then what's using the memory?**

<details><summary>🛡️ Defense</summary>

Everything that isn't heap. NMT on a small Boot 4 app with a 256 MB max heap: 232 MB committed, of which **68 MB was heap** and ~165 MB wasn't: G1 structures 55 MB, Metaspace 43 MB, code cache 28 MB, CDS 14 MB, symbols 9.5 MB. Under load, add platform thread stacks, direct buffers (Netty, Kafka; `MaxDirectMemorySize` defaults to the heap max) and glibc malloc arenas. I'd turn on `-XX:NativeMemoryTracking=summary`, take a baseline, load-test, and diff.
</details>

🔍 **Probe 3 (L6): Give me the sizing rule you'd put in the platform standard.**

<details><summary>🛡️ Defense</summary>

Memory request = limit (Guaranteed for memory, since JVM RSS rarely shrinks). Below ~1 GiB, an explicit `-Xmx` with 250–400 MB of non-heap headroom; above ~2 GiB, `MaxRAMPercentage` 70–80. Cap direct memory, `MALLOC_ARENA_MAX=2`, `ExitOnOutOfMemoryError` + heap dump to an `emptyDir`. Verify in staging: working set under ~85 % of the limit at peak. Percentages fail at small sizes: 75 % of 512 MiB is a 384 MiB heap, plus 165 MB of measured non-heap, which is over the limit.
</details>

---

## Drill 2: "We don't set JVM flags. The container limits are 2 GiB and 1 CPU" 🔥

🔍 **Probe 1: What heap and GC does the JVM pick?**

<details><summary>🛡️ Defense</summary>

Verified on Temurin 25 with the same inputs: max heap = **25 %** of the limit (512 MiB of 2 GiB), and with **1 CPU** the default collector is **Serial**, at every memory size I tried. With 2 CPUs it's G1. Per the HotSpot source, G1 also needs about 1792 MB of memory to count as a "server-class machine". So "no flags" means a quarter of the memory used and a single-threaded stop-the-world collector.
</details>

🔍 **Probe 2: And with no CPU limit at all?**

<details><summary>🛡️ Defense</summary>

Since JDK 19, CPU requests (`cpu.weight`) aren't used for the processor count, so the JVM sees **the whole node**. On 64 cores that's 43 parallel GC threads (8 + 56 × 5/8) and a common pool of 63, in a pod scheduled for 1 CPU. Verified scaling: 16 CPUs → 13 parallel GC threads, 3 concurrent, 12 JIT threads, common pool 15. I pin `-XX:ActiveProcessorCount` to what the pod should use.
</details>

---

## Drill 3: "p99 latency spikes, but CPU usage is only 40 %" 🧊

🔍 **Probe 1: What's your first hypothesis in Kubernetes?**

<details><summary>🛡️ Defense</summary>

CFS throttling. A CPU **limit** becomes a quota per 100 ms period shared by all threads. A JVM with many GC threads can burn a 2-CPU quota (200 ms) in ~15 ms of wall time, then **every thread is frozen** for the rest of the period. The GC log says 15 ms; users see ~100 ms. The average stays at 40 % because the bursts are short. I'd check `nr_throttled`/`throttled_usec` in `cpu.stat`, or the throttled-periods ratio from cAdvisor.
</details>

🔍 **Probe 2: How do you fix it?**

<details><summary>🛡️ Defense</summary>

First make the JVM's thread counts match the quota (`ActiveProcessorCount`, or let it detect the limit), so parallelism doesn't turn into freezes. Then choose a CPU policy deliberately: limit = request (predictable, throttles on bursts); request-only with explicit thread sizing (bursts use idle node CPU); or exclusive cores with the static CPU manager (lowest jitter, wastes capacity). The answer depends on cluster tenancy. The non-negotiable part is measuring throttling.
</details>

---

## Drill 4: "Let's switch to ZGC to fix our latency" ⚡

🔍 **Probe 1: Pod has 2 CPUs and a 512 MB heap. Will it help?**

<details><summary>🛡️ Defense</summary>

Not necessarily. One run on 2 pinned CPUs, 150 MB live set, ~10 GB/s allocation: ZGC's **pauses totaled 20 ms** over 4,221 collections, but the application still saw **stalls up to 69 ms** (p99 17 ms). Concurrent GC needs CPU, and when it can't keep up with allocation, allocating threads wait. G1 on the same run had a flat 23–25 ms tail with the lowest throughput; Parallel had the best p99 but 49 ms worst-case. ZGC shines with CPU and heap headroom. I'd measure request latency, not GC pause logs.
</details>

🔍 **Probe 2 (L6): We use an AOT cache in the image. Anything else changes?**

<details><summary>🛡️ Defense</summary>

Yes, and it fails silently. A cache trained under G1 was rejected under ZGC ("saved state of UseCompressedOops and UseCompressedClassPointers is different from runtime"). With the default `AOTMode` the app still started, just **without** the cache, so startup quietly regressed. Retrain with the production GC flags, and make CI start the image with `-XX:AOTMode=on` so a mismatch fails the build.
</details>

---

## Drill 5: "Every deployment causes a burst of 502s" 🔥

🔍 **Probe 1: What happens when a pod is deleted?**

<details><summary>🛡️ Defense</summary>

Two things **in parallel**: the pod's IP is removed from EndpointSlices (and that change propagates to kube-proxy, ingress and sidecars over seconds), and the kubelet runs preStop and sends SIGTERM. If the app stops listening before every load balancer has stopped routing to it, new requests hit a closed port. I verified the app side: once Boot's graceful shutdown starts, **new connections are refused** while the in-flight request completes with 200.
</details>

🔍 **Probe 2: So what's the fix?**

<details><summary>🛡️ Defense</summary>

A `preStop` sleep (5–15 s; the native `sleep` action needs no shell, so it works on distroless) so the pod keeps serving during propagation. Then Boot's graceful shutdown (the default in 4.1.2, 30 s per phase): readiness → refusing, drain in-flight, stop listeners. And `terminationGracePeriodSeconds` ≥ preStop + drain + consumer shutdown + margin, because the grace period counts from deletion, including preStop.
</details>

🔍 **Probe 3: The fix is in place but Java still gets SIGKILLed after 30 s.**

<details><summary>🛡️ Defense</summary>

Check the entrypoint. In shell form (`ENTRYPOINT java -jar …`), `/bin/sh` is PID 1 and doesn't forward SIGTERM, so Java never starts its shutdown and gets killed when the grace period ends. Exec form (`ENTRYPOINT ["java", …]`) or `exec java` in the wrapper script. Second suspect: a grace period shorter than preStop + drain.
</details>

---

## Drill 6: "Our liveness probe checks the database, so we know when we're broken" 🔥

🔍 **Probe 1: The database has a 2-minute outage. Walk me through it.**

<details><summary>🛡️ Defense</summary>

Every pod fails liveness, Kubernetes restarts all of them, they come back cold into a recovering database, fail again, and land in `CrashLoopBackOff` with increasing delays. The DB outage becomes an app outage that outlasts it. Liveness should only check what a restart fixes: Boot's `livenessState`.
</details>

🔍 **Probe 2: Then put the DB in readiness?**

<details><summary>🛡️ Defense</summary>

Not a shared dependency. If the DB is down, every pod goes unready, the Service has zero endpoints, and callers get connection errors instead of a designed degraded response. Readiness is pod-local (warm-up done, local state OK). Shared dependencies get circuit breakers, fallbacks and alerts.
</details>

🔍 **Probe 3 (L6): Probe configuration details for a JVM?**

<details><summary>🛡️ Defense</summary>

A startup probe instead of `initialDelaySeconds`; liveness with a 2–3 s timeout (the default 1 s fails on a GC pause or a throttled period) and 3+ failures; probe `/livez` and `/readyz` on the **main** port (`add-additional-paths`), so a wedged main connector isn't hidden behind a healthy management port. Warm-up goes in `ApplicationRunner`s: I verified Boot only flips readiness to `ACCEPTING_TRAFFIC` after they finish.
</details>

---

## Drill 7: "Write a Dockerfile for this Spring Boot service" ⚡

🔍 **Probe 1: Why not `COPY target/app.jar` and `java -jar`?**

<details><summary>🛡️ Defense</summary>

Layers are cached positionally. A fat jar puts 24 MB of dependencies and 1 MB of code in one layer that changes every commit. `java -Djarmode=tools -jar app.jar extract --layers` split it (verified) into dependencies 23 MB, loader 637 KB, snapshots 0, application ~1 MB (including the sibling module jar). Four `COPY`s in that order, so a commit re-pushes ~1 MB.
</details>

🔍 **Probe 2: Which base image, and which user?**

<details><summary>🛡️ Defense</summary>

Registry data on 2026-10-25: Temurin 25 JRE (noble) 104 MB compressed, alpine 76 MB (musl: test DNS and allocator), distroless Java 25 73 MB with **uid 65532**, no shell, entrypoint `/usr/bin/java -jar`. I use distroless pinned by digest, app files owned by root so the process can't modify them, read-only root filesystem, and ephemeral containers for debugging.
</details>

🔍 **Probe 3 (L6): Where do you run the AOT training?**

<details><summary>🛡️ Defense</summary>

In the **runtime** stage. The cache is valid only for the same JVM build, and the distroless image ships **25.0.5** while my Temurin build stage was **25.0.4.1**. Exec-form `RUN` (no shell), with a training profile that starts without the DB, Kafka or secrets (`hibernate.boot.allow_jdbc_metadata_access=false`, listeners off, Flyway off), and the production GC flag. Then I'd mention the trade: about 47 % faster startup for a ~60 MB layer that changes every commit.
</details>

---

## Drill 8: "The HPA scales up on every deploy and barely scales down" ⚡

🔍 **Probe 1: Why up on deploys?**

<details><summary>🛡️ Defense</summary>

New JVMs burn CPU on class loading and JIT for their first minutes, and HPA utilization is relative to **requests**, so fresh pods look overloaded and the HPA adds more, which also start up. Mitigations: readiness after warm-up, the controller's CPU initialization period (5 min) and readiness delay (30 s), AOT cache for shorter startups, and scale-up `behavior` limits.
</details>

🔍 **Probe 2: And the slow scale-down?**

<details><summary>🛡️ Defense</summary>

The default downscale stabilization window is **5 minutes**: the HPA uses the highest recommendation of the last 5 minutes. Usually that's desirable. If it never scales down at all, check whether it's scaling on **memory**: JVM heaps grow to their max and rarely return memory, so a memory target only goes up. Scale on CPU against honest requests, or better on RPS, in-flight requests or queue depth.
</details>

---

## Drill 9: "Use KEDA to scale our Kafka consumers, down to zero at night" 🧊

🔍 **Probe 1: Lag spikes to 50,000 on a 12-partition topic. How many pods?**

<details><summary>🛡️ Defense</summary>

`ceil(lag / lagThreshold)`, but capped at the partition count: `allowIdleConsumers` defaults to **false** in KEDA v2.21's Kafka scaler (verified in its source). So 12 at most. Pods beyond partitions would sit idle anyway, because one partition has one consumer per group. If 12 isn't enough, the fix is more partitions (planned up front) or more throughput per consumer, not more pods.
</details>

🔍 **Probe 2: What does scale-to-zero cost?**

<details><summary>🛡️ Defense</summary>

A cold start for the first message: JVM + context + group join (the AOT cache helps). And **every scale event is a rebalance**; with the eager assignor each one pauses all consumers. Use cooperative-sticky or KIP-848, an `activationLagThreshold` and a cooldown so it doesn't flap between 0 and 1. If the first message has a latency SLO, keep `minReplicaCount: 1`.
</details>

---

## Drill 10: "How do you know this config is actually right?" 🧊

🔍 **Probe 1: Your `application.yml` has 90 keys. How many are silently ignored?**

<details><summary>🛡️ Defense</summary>

Spring Boot ignores unknown properties, so typos and removed properties fail silently. I check every key against the `spring-configuration-metadata.json` of the jars on the classpath, flagging unknown and deprecated keys. That caught `spring.data.redis.lettuce.cluster.refresh.adaptive`, which Boot 4.1 **removed** ("all adaptive triggers are enabled by default"). Keys under free-form maps (Hibernate, Kafka client properties, Resilience4j instances) I check against the libraries' own constants and setters.
</details>

🔍 **Probe 2: And the manifests?**

<details><summary>🛡️ Defense</summary>

Validate against the cluster version's OpenAPI schemas and the CRDs you use (KEDA, Gateway API) in CI, then `kubectl apply --dry-run=server` for admission policies. I prove the validator works with a negative test: in mine, five injected mistakes (typo'd field, string for int, missing container name, misspelled KEDA field) were all reported.
</details>

---

## L5 vs L6 signal

| Topic | L5 answer | L6 answer |
|---|---|---|
| Container memory | Sets `-Xmx` below the limit | Budgets heap + measured non-heap, knows the four OOM failure modes, sets platform-wide defaults |
| CPU | Sets requests and limits | Explains CFS quota per period, sizes JVM threads to it, chooses a CPU policy with throttling data |
| GC | "G1 default, ZGC for latency" | Knows defaults by CPU count, measures stalls under the pod's CPU budget, knows ZGC's headroom needs and the AOT interaction |
| Images | Multi-stage, small base | Layer economics, PID 1 semantics, non-root by construction, AOT training in the runtime image, CI checks |
| Probes | Liveness and readiness endpoints | What each probe may check, timeouts for JVMs, main vs management port, warm-up ordering |
| Shutdown | `server.shutdown=graceful` | The parallel endpoint/termination race, preStop, grace budget, consumers and executors |
| Autoscaling | HPA on CPU | Requests-relative math, JVM startup effects, controller defaults, KEDA lag scaling capped at partitions |
| Verification | "We tested in staging" | Mechanical validation of config and manifests, with negative tests |

---

## Red flags

* "OOMKilled → raise `-Xmx`."
* No JVM flags in containers, or `-Xmx` equal to the limit.
* No CPU limit and no `ActiveProcessorCount` on big nodes; or CPU limits with no throttling dashboard.
* Choosing ZGC from GC pause logs alone.
* Liveness checking a database; 1-second probe timeouts on JVMs.
* Shell-form entrypoints; root containers; floating base tags.
* No preStop, or a grace period shorter than preStop + drain.
* HPA on memory for a JVM; KEDA scaling past the partition count.
* "Boot ignores unknown properties" treated as harmless.

---

## Rapid-fire flashcards

<details><summary>1. Exit code 137 with OOMKilled means?</summary>The kernel's cgroup OOM killer sent SIGKILL: total process memory exceeded `memory.max`.</details>

<details><summary>2. Default MaxRAMPercentage?</summary>25 %.</details>

<details><summary>3. Default GC with 1 CPU?</summary>SerialGC.</details>

<details><summary>4. Does the JVM use CPU requests for availableProcessors?</summary>Not since JDK 19; only the limit (quota) and cpuset.</details>

<details><summary>5. ParallelGCThreads formula above 8 CPUs?</summary>8 + (n − 8) × 5/8.</details>

<details><summary>6. Biggest non-heap items in a small Boot app?</summary>GC structures, Metaspace, code cache, CDS archive.</details>

<details><summary>7. MaxDirectMemorySize default?</summary>The max heap size.</details>

<details><summary>8. What does `ExitOnOutOfMemoryError` give you?</summary>The JVM exits (code 3) on OOME instead of limping on, so Kubernetes restarts it.</details>

<details><summary>9. CFS period and what a limit of 2 means?</summary>100 ms; 200 ms of CPU time per period across all threads.</details>

<details><summary>10. Throttling metric?</summary>`container_cpu_cfs_throttled_periods_total / container_cpu_cfs_periods_total` (or `nr_throttled` in cpu.stat).</details>

<details><summary>11. Why shell-form ENTRYPOINT breaks shutdown?</summary>`sh` is PID 1 and doesn't forward SIGTERM to Java.</details>

<details><summary>12. Distroless Java 25 user and entrypoint?</summary>uid 65532; `/usr/bin/java -jar`.</details>

<details><summary>13. Where to train the AOT cache?</summary>In the runtime image, with production GC flags.</details>

<details><summary>14. What happens if the AOT cache doesn't match?</summary>Default: a warning and the app runs without it. `-XX:AOTMode=on`: the JVM fails to start.</details>

<details><summary>15. Boot 4.1.2 shutdown defaults?</summary>`server.shutdown=GRACEFUL`, 30 s per shutdown phase.</details>

<details><summary>16. When does Boot set readiness to ACCEPTING_TRAFFIC?</summary>After `ApplicationRunner`s/`CommandLineRunner`s complete.</details>

<details><summary>17. `/livez` and `/readyz` on the main port?</summary>`management.endpoint.health.probes.add-additional-paths=true`.</details>

<details><summary>18. Why preStop sleep?</summary>Endpoint removal and SIGTERM happen in parallel; the sleep covers LB propagation.</details>

<details><summary>19. Grace period counts from?</summary>Pod deletion, including preStop time.</details>

<details><summary>20. HPA defaults: tolerance, downscale window, CPU init period?</summary>0.1, 5 min, 5 min.</details>

<details><summary>21. HPA CPU utilization is relative to?</summary>Requests.</details>

<details><summary>22. KEDA Kafka `lagThreshold` default and `allowIdleConsumers` default?</summary>10 and false.</details>

<details><summary>23. Boot 4 AOP starter and web starter names?</summary>`spring-boot-starter-aspectj`; `spring-boot-starter-webmvc` (`-web` is deprecated).</details>

<details><summary>24. Removed Redis property in Boot 4.1?</summary>`spring.data.redis.lettuce.cluster.refresh.adaptive`: adaptive triggers are always on.</details>

**Next pillar:** [8.1 Modular monolith and DDD repositories →](../08-GitHub-Codebases-Study-Guide/01-Modular-Monolith-and-DDD-Repos.md)
