# 8.7 The Source Behind the Measurements: JDK, PostgreSQL, Redis, Kubernetes, KEDA, Kafka, Spring

> **Verified 2026-10-26.** This module takes the measured surprises from Pillars 1–7 and 10 and links each to the line of source that causes it, at the release tag of the version the kit ran. The excerpts are copied from the fetched files, never retyped. A script checked all 83 references: the file exists at the tag and contains the quoted code on the linked line.
>
> | Area | Pinned at |
> |---|---|
> | JDK | `jdk-25.0.4.1+1` (Temurin 25.0.4.1) |
> | Databases | PostgreSQL `REL_18_6` · Redis `8.10.2` · Lettuce `7.5.2.RELEASE` |
> | Kubernetes stack | Kubernetes `v1.37.1` · KEDA `v2.21.0` · Prometheus `v3.15.1` · kustomize `v5.8.3` |
> | Kafka | Kafka `4.2.2` · spring-kafka `v4.1.2` |
> | Spring | Spring Boot `v4.1.2` · Spring Framework `v7.0.10` · Spring Data Redis `4.1.2` |
> | Persistence and migration | Hibernate `7.4.13` · Flyway `flyway-12.4.0` |
> | Resilience, caching, pooling | Resilience4j `v2.4.0` · Spring Cloud CircuitBreaker `v5.0.1` · Caffeine `v3.3.1` · HikariCP `7.0.2` and `7.1.0` |
> | Build | maven-resolver `2.0.24` |
>
> **Pairs with:** the README's *Verified surprises* table (the measurements), [8.6](06-Framework-Internals-by-Stack-Trace-Spring-Hibernate-HikariCP-Caffeine-Kafka.md) (call paths), [8.8](08-GitHub-Codebase-Study-Matrix-and-Master-Interview-Synthesis.md) (what to read next).

---

## 0. A surprise is an anecdote until you can point at the line 🔥

"Our pods hung on drain" is a story. "The disruption controller computes `minAvailable` with `GetScaledValueFromIntOrPercent(..., roundUp=true)`, so 75 % of 2 is 2" is a mechanism. You can predict the next case from it, test it in CI and explain it in four sentences. The method used for every row below:

1. **Measure first**, with numbers: what happened, on which version.
2. **Find the default or knob**: usually a constant or a `*Config`/`*Properties` class.
3. **Find the decision**: the `if` that turns the knob into the behaviour you saw.
4. **Pin it**: link to the line at the release tag, not to `main`, and quote it.
5. **Put it on the upgrade watchlist** (§8): these are the lines that silently change between versions.

---

## 1. The JVM in containers (JDK 25)

| Measured in the kit | The code that explains it | What to notice |
|---|---|---|
| One CPU → **SerialGC** at any memory size ([7.1](../07-Docker-JVM-Kubernetes/01-JVM-in-Containers-cgroups-v2-Memory-OOMKilled.md)) | [`GCConfig::select_gc_ergonomically`](https://github.com/openjdk/jdk25u/blob/jdk-25.0.4.1+1/src/hotspot/share/gc/shared/gcConfig.cpp#L98) → [`os::is_server_class_machine`](https://github.com/openjdk/jdk25u/blob/jdk-25.0.4.1+1/src/hotspot/share/runtime/os.cpp#L1928) | "Server class" needs **2 processors** *and* about 2 GB; fail either and ergonomics picks Serial |
| Container memory limit → heap size ([7.1](../07-Docker-JVM-Kubernetes/01-JVM-in-Containers-cgroups-v2-Memory-OOMKilled.md)) | [`CgroupV2MemoryController::read_memory_limit_in_bytes`](https://github.com/openjdk/jdk25u/blob/jdk-25.0.4.1+1/src/hotspot/os/linux/cgroupV2Subsystem_linux.cpp#L298) (reads `memory.max`) → [`Arguments::set_heap_size`](https://github.com/openjdk/jdk25u/blob/jdk-25.0.4.1+1/src/hotspot/share/runtime/arguments.cpp#L1492) | `MaxRAMPercentage` applies to the cgroup limit, not the host's RAM |
| CPU limit → `availableProcessors()` ([7.4](../07-Docker-JVM-Kubernetes/04-CPU-Throttling-GC-Choice-HPA-KEDA.md)) | [`CgroupV2CpuController::cpu_quota`](https://github.com/openjdk/jdk25u/blob/jdk-25.0.4.1+1/src/hotspot/os/linux/cgroupV2Subsystem_linux.cpp#L123) (reads `cpu.max`) | A fractional quota [rounds **up**](https://github.com/openjdk/jdk25u/blob/jdk-25.0.4.1+1/src/hotspot/os/linux/cgroupUtil_linux.cpp#L37) (1.5 CPUs → 2); no limit means all host CPUs, hence `ActiveProcessorCount` |
| G1 uncommitted 674 MB of a 718 MB initial heap **0.85 s** into startup ([7.7 §4](../07-Docker-JVM-Kubernetes/07-Container-Images-and-JVM-Profiles-Blueprints-II-jlink-AOT-Workloads.md)) | [`G1ConcurrentMark::remark`](https://github.com/openjdk/jdk25u/blob/jdk-25.0.4.1+1/src/hotspot/share/gc/g1/g1ConcurrentMark.cpp#L1464) calls `resize_heap_if_necessary` and `uncommit_regions_if_necessary`; [the target](https://github.com/openjdk/jdk25u/blob/jdk-25.0.4.1+1/src/hotspot/share/gc/g1/g1HeapSizingPolicy.cpp#L248) uses `MaxHeapFreeRatio` | Every concurrent cycle's Remark pause may shrink the heap to `MaxHeapFreeRatio` (70 % free by default). That's why `InitialRAMPercentage` didn't "pin" anything |
| `JAVA_TOOL_OPTIONS=-Xmx1m` broke `jcmd`; `JDK_JAVA_OPTIONS` didn't ([7.7](../07-Docker-JVM-Kubernetes/07-Container-Images-and-JVM-Profiles-Blueprints-II-jlink-AOT-Workloads.md)) | [`Arguments::parse_java_tool_options_environment_variable`](https://github.com/openjdk/jdk25u/blob/jdk-25.0.4.1+1/src/hotspot/share/runtime/arguments.cpp#L3081) (the VM itself) vs [`JDK_JAVA_OPTIONS` in libjli](https://github.com/openjdk/jdk25u/blob/jdk-25.0.4.1+1/src/java.base/share/native/libjli/args.c#L37) (the `java` launcher only) | `JAVA_TOOL_OPTIONS` reaches every JVM in the container, including `jcmd`'s and `jstat`'s |
| A blocked virtual thread was missing from `Thread.getAllStackTraces()` ([8.6 §5](06-Framework-Internals-by-Stack-Trace-Spring-Hibernate-HikariCP-Caffeine-Kafka.md)) | [`Thread.getAllStackTraces` Javadoc](https://github.com/openjdk/jdk25u/blob/jdk-25.0.4.1+1/src/java.base/share/classes/java/lang/Thread.java#L2220); [`HotSpotDiagnosticMXBean.dumpThreads`](https://github.com/openjdk/jdk25u/blob/jdk-25.0.4.1+1/src/jdk.management/share/classes/com/sun/management/HotSpotDiagnosticMXBean.java#L126) | Documented: "does not include virtual threads"; the JSON dump "may include" them |
| `@Cacheable(sync = true)` recursion → `Recursive update` ([8.6 §6](06-Framework-Internals-by-Stack-Trace-Spring-Hibernate-HikariCP-Caffeine-Kafka.md)) | [`ConcurrentHashMap.compute` throws](https://github.com/openjdk/jdk25u/blob/jdk-25.0.4.1+1/src/java.base/share/classes/java/util/concurrent/ConcurrentHashMap.java#L1075); [its contract](https://github.com/openjdk/jdk25u/blob/jdk-25.0.4.1+1/src/java.base/share/classes/java/util/concurrent/ConcurrentHashMap.java#L1806) | The loader runs inside `compute`, under the bin lock |

The server-class test, from `os.cpp`:

```cpp
bool os::is_server_class_machine() {
  // First check for the early returns
  if (NeverActAsServerClassMachine) {
    return false;
  }
  if (AlwaysActAsServerClassMachine) {
    return true;
  }
  // Then actually look at the machine
  bool  result                                    = false;
  const unsigned int server_processors            = 2;
  const physical_memory_size_type server_memory   = 2UL * G;
  // We seem not to get our full complement of memory.
  //     We allow some part (1/8?) of the memory to be "missing",
  //     based on the sizes of DIMMs, and maybe graphics cards.
  const physical_memory_size_type missing_memory  = 256UL * M;
  physical_memory_size_type phys_mem              = os::physical_memory();
  /* Is this a server class machine? */
  if ((os::active_processor_count() >= (int)server_processors) &&
      (phys_mem >= server_memory - missing_memory)) {
    const unsigned int logical_processors =
      VM_Version::logical_processors_per_package();
    if (logical_processors > 1) {
      const unsigned int physical_packages =
        os::active_processor_count() / logical_processors;
      if (physical_packages >= server_processors) {
        result = true;
      }
    } else {
      result = true;
    }
  }
  return result;
}
```

And the Remark pause that undid the "pinned" initial heap, from `g1ConcurrentMark.cpp`:

```cpp
_g1h->increment_total_collections();

_g1h->resize_heap_if_necessary(size_t(0) /* allocation_word_size */);
_g1h->uncommit_regions_if_necessary();

compute_new_sizes();
```

---

## 2. PostgreSQL 18.6 and Flyway

| Measured in the kit | The code that explains it | What to notice |
|---|---|---|
| VACUUM skipped index cleanup when fewer than ~2 % of pages had dead items, so index-only scans kept fetching the heap ([2.9 §5](../02-SQL-RDBMS-Internals/09-EXPLAIN-Atlas-Part-1-Scans-Sorts-Aggregates-Parallelism.md#5-index-only-scan-the-visibility-map-and-the-vacuum-that-didnt-help-)) | [`BYPASS_THRESHOLD_PAGES`](https://github.com/postgres/postgres/blob/REL_18_6/src/backend/access/heap/vacuumlazy.c#L187) in `vacuumlazy.c` | An optimization with a visible cost: the visibility map stays stale |
| `pg_stat_statements` 1.12 folded IN lists of any length into one entry ([3.7 §3.3](../03-JPA-Hibernate-Spring-Data/07-High-Scale-Persistence-Streaming-L2-Cache-Batch-Fetch-Multitenancy-EXPLAIN.md#33-how-postgresql-18s-pg_stat_statements-sees-in-lists)) | [Query jumbling's "squash" rule](https://github.com/postgres/postgres/blob/REL_18_6/src/backend/nodes/queryjumblefuncs.c#L24) | New in 18: lists of two or more constants contribute once to the query id |
| Data checksums on by default; built-in `uuidv7()` ([2.2](../02-SQL-RDBMS-Internals/02-Indexes-BTree-Hash-GIN-GiST-BRIN-Covering-Composite.md)) | [`initdb.c`](https://github.com/postgres/postgres/blob/REL_18_6/src/bin/initdb/initdb.c#L167), [`uuid.c`](https://github.com/postgres/postgres/blob/REL_18_6/src/backend/utils/adt/uuid.c#L63) | Version facts are cheapest to verify in source |
| A stale logical slot retained WAL and held back catalog vacuum ([2.5 §2.3](../02-SQL-RDBMS-Internals/05-MVCC-Visibility-Vacuum-Wraparound-vs-InnoDB-Undo.md#23-verified-what-a-stale-logical-replication-slot-actually-blocks-)) | [`catalog_xmin` in `slot.c`](https://github.com/postgres/postgres/blob/REL_18_6/src/backend/replication/slot.c#L450) | A logical slot pins the catalog horizon, not the data-table horizon |
| Visibility of a row version ([2.5](../02-SQL-RDBMS-Internals/05-MVCC-Visibility-Vacuum-Wraparound-vs-InnoDB-Undo.md)) | [`HeapTupleSatisfiesMVCC`](https://github.com/postgres/postgres/blob/REL_18_6/src/backend/access/heap/heapam_visibility.c#L40) | xmin/xmax against the snapshot, plus hint bits |
| A second Flyway run waited ~5 s and **no waiting row appeared in `pg_locks`** ([7.8 §4](../07-Docker-JVM-Kubernetes/08-Kubernetes-Platform-Blueprints-II-Kustomize-Guardrails-Consumers-Jobs-Canary.md)) | [`PostgreSQLAdvisoryLockTemplate`](https://github.com/flyway/flyway/blob/flyway-12.4.0/flyway-database/flyway-database-postgresql/src/main/java/org/flywaydb/database/postgresql/PostgreSQLAdvisoryLockTemplate.java#L90): `doWithRetries` around [`pg_try_advisory_lock`](https://github.com/flyway/flyway/blob/flyway-12.4.0/flyway-database/flyway-database-postgresql/src/main/java/org/flywaydb/database/postgresql/PostgreSQLAdvisoryLockTemplate.java#L101) | A polling *try*-lock, not a blocking lock: nothing waits inside PostgreSQL, so lock-wait monitoring can't see it |

```c
/*
 * Threshold that controls whether we bypass index vacuuming and heap
 * vacuuming as an optimization
 */
#define BYPASS_THRESHOLD_PAGES    0.02    /* i.e. 2% of rel_pages */
```

---

## 3. Redis 8.10.2, Lettuce 7.5.2, Spring Data Redis 4.1.2

| Measured in the kit | The code that explains it | What to notice |
|---|---|---|
| `volatile-lru` with keys that had no TTL: **14,760 failed `SET`s** ([6.7](../06-Resilience-Caching/07-Redis-in-Production-Memory-Eviction-Client-Caching-Failover-Spring-Cache.md)) | [`performEvictions`](https://github.com/redis/redis/blob/8.10.2/src/evict.c#L532) returns [`EVICT_FAIL`](https://github.com/redis/redis/blob/8.10.2/src/evict.c#L451) when nothing is evictable → [`OOM command not allowed`](https://github.com/redis/redis/blob/8.10.2/src/server.c#L2250) | `volatile-*` only considers keys with a TTL |
| `allkeys-lfu` beat `allkeys-lru` on a Zipf workload ([6.7](../06-Resilience-Caching/07-Redis-in-Production-Memory-Eviction-Client-Caching-Failover-Spring-Cache.md)) | [`LFUDecrAndReturn`](https://github.com/redis/redis/blob/8.10.2/src/evict.c#L162) | A decaying logarithmic counter per key |
| `WAIT 1`: 0 confirmed writes lost in a failover (38 without) ([6.7](../06-Resilience-Caching/07-Redis-in-Production-Memory-Eviction-Client-Caching-Failover-Spring-Cache.md)) | [`waitCommand`](https://github.com/redis/redis/blob/8.10.2/src/replication.c#L4895) | Counts replica acknowledgements; it doesn't make a write consensus-safe |
| A 40-byte value: 110 bytes as a key, 44 bytes in a small hash ([6.7](../06-Resilience-Caching/07-Redis-in-Production-Memory-Eviction-Client-Caching-Failover-Spring-Cache.md)) | [`hash_max_listpack_entries`](https://github.com/redis/redis/blob/8.10.2/src/t_hash.c#L371) in `t_hash.c` | Small hashes stay listpack-encoded |
| Lettuce waits **60 s** by default ([6.7](../06-Resilience-Caching/07-Redis-in-Production-Memory-Eviction-Client-Caching-Failover-Spring-Cache.md)) | [`RedisURI.DEFAULT_TIMEOUT`](https://github.com/redis/lettuce/blob/7.5.2.RELEASE/src/main/java/io/lettuce/core/RedisURI.java#L224) | Every Redis call can hold a request thread for a minute |
| Spring's Redis cache: 21–59 of 200 immediate re-reads missed ([6.7 §8](../06-Resilience-Caching/07-Redis-in-Production-Memory-Eviction-Client-Caching-Failover-Spring-Cache.md)) | [`immediateWrites = false`](https://github.com/spring-projects/spring-data-redis/blob/4.1.2/src/main/java/org/springframework/data/redis/cache/DefaultRedisCacheWriter.java#L162) → [`asynchronousWrites = !immediateWrites`](https://github.com/spring-projects/spring-data-redis/blob/4.1.2/src/main/java/org/springframework/data/redis/cache/DefaultRedisCacheWriter.java#L152) | Writes are asynchronous unless you opt in |
| Caching `null` threw `IllegalArgumentException` ([6.5 drill 12](../06-Resilience-Caching/05-Bar-Raiser-Drill-Downs.md)) | [`RedisCache`](https://github.com/spring-projects/spring-data-redis/blob/4.1.2/src/main/java/org/springframework/data/redis/cache/RedisCache.java#L315) | Decide how absence is cached; don't find out on the read path |

---

## 4. Kubernetes v1.37.1, KEDA v2.21.0, Prometheus, kustomize

| Measured in the kit | The code that explains it | What to notice |
|---|---|---|
| `minAvailable: 75%` allowed **0 evictions** at 2–3 replicas ([7.8 §5.2](../07-Docker-JVM-Kubernetes/08-Kubernetes-Platform-Blueprints-II-Kustomize-Guardrails-Consumers-Jobs-Canary.md)) | [`minAvailable` → `GetScaledValueFromIntOrPercent(..., true)`](https://github.com/kubernetes/kubernetes/blob/v1.37.1/pkg/controller/disruption/disruption.go#L847) and [the `maxUnavailable` branch](https://github.com/kubernetes/kubernetes/blob/v1.37.1/pkg/controller/disruption/disruption.go#L828) | Both round **up**: good for `maxUnavailable`, bad for `minAvailable` |
| The namespace quota was exceeded during a rollout at max scale ([7.8 §5.3](../07-Docker-JVM-Kubernetes/08-Kubernetes-Platform-Blueprints-II-Kustomize-Guardrails-Consumers-Jobs-Canary.md)) | [`QuotaV1Pod`](https://github.com/kubernetes/kubernetes/blob/v1.37.1/pkg/quota/v1/evaluator/core/pods.go#L491): a terminating pod is charged [until `deletionTimestamp + grace`](https://github.com/kubernetes/kubernetes/blob/v1.37.1/pkg/quota/v1/evaluator/core/pods.go#L503) | Terminating pods use quota for their whole grace period |
| …and the Deployment doesn't wait for them ([7.8 §5.3](../07-Docker-JVM-Kubernetes/08-Kubernetes-Platform-Blueprints-II-Kustomize-Guardrails-Consumers-Jobs-Canary.md)) | [`status.terminatingReplicas`](https://github.com/kubernetes/kubernetes/blob/v1.37.1/pkg/controller/deployment/sync.go#L513) behind a feature gate | Reported in status; no spec field acts on it |
| preStop time comes **out of** the grace period (shutdown budgets in [7.3](../07-Docker-JVM-Kubernetes/03-Kubernetes-Probes-and-Graceful-Shutdown.md)) | [`gracePeriod = gracePeriod - executePreStopHook(...)`](https://github.com/kubernetes/kubernetes/blob/v1.37.1/pkg/kubelet/kuberuntime/kuberuntime_container.go#L897), then a [2-second floor](https://github.com/kubernetes/kubernetes/blob/v1.37.1/pkg/kubelet/kuberuntime/kuberuntime_container.go#L908) | `preStop sleep 10` + 30 s drain needs a grace period above 40 s |
| HPA ignores changes within 10 %; scale-down waits 5 minutes ([7.4](../07-Docker-JVM-Kubernetes/04-CPU-Throttling-GC-Choice-HPA-KEDA.md)) | [`HorizontalPodAutoscalerTolerance = 0.1`](https://github.com/kubernetes/kubernetes/blob/v1.37.1/pkg/controller/podautoscaler/config/v1alpha1/defaults.go#L53), [`5 * time.Minute`](https://github.com/kubernetes/kubernetes/blob/v1.37.1/pkg/controller/podautoscaler/config/v1alpha1/defaults.go#L44) | Controller-wide defaults. Per-HPA `behavior` overrides the window, and v1.37 has a per-HPA [`tolerance`](https://github.com/kubernetes/kubernetes/blob/v1.37.1/staging/src/k8s.io/api/autoscaling/v2/types.go#L231) behind the [`HPAConfigurableTolerance`](https://github.com/kubernetes/kubernetes/blob/v1.37.1/staging/src/k8s.io/api/autoscaling/v2/types.go#L229) feature gate |
| `podFailurePolicy` + `restartPolicy: OnFailure` passed every offline check ([7.8 N10](../07-Docker-JVM-Kubernetes/08-Kubernetes-Platform-Blueprints-II-Kustomize-Guardrails-Consumers-Jobs-Canary.md)) | [API-server validation](https://github.com/kubernetes/kubernetes/blob/v1.37.1/pkg/apis/batch/validation/validation.go#L310) | Cross-field rules live in the API server; only `--dry-run=server` sees them |
| An invalid CronJob `timeZone` passed offline ([7.8 N11](../07-Docker-JVM-Kubernetes/08-Kubernetes-Platform-Blueprints-II-Kustomize-Guardrails-Consumers-Jobs-Canary.md)) | [`TimeZone` validation](https://github.com/kubernetes/kubernetes/blob/v1.37.1/pkg/apis/batch/validation/validation.go#L897) | Same: API server only |
| KEDA caps replicas at the **partition count**, not consumers ([10.4 §3](../10-Kafka-Production/04-Consumer-Scaling-Static-Membership-KIP-848-KEDA-Rolling-Deploys.md)) | [`upperBound := totalTopicPartitions`](https://github.com/kedacore/keda/blob/v2.21.0/pkg/scalers/kafka_scaler.go#L942) | It doesn't know your listener concurrency |
| `ensureEvenDistributionOfPartitions` steps through factors and conflicts with `limitToPartitionsWithLag` ([10.4](../10-Kafka-Production/04-Consumer-Scaling-Static-Membership-KIP-848-KEDA-Rolling-Deploys.md)) | [`getNextFactorThatBalancesConsumersToTopicPartitions`](https://github.com/kedacore/keda/blob/v2.21.0/pkg/scalers/kafka_scaler.go#L960), [the validation](https://github.com/kedacore/keda/blob/v2.21.0/pkg/scalers/kafka_scaler.go#L147) | 12 partitions: 1, 2, 3, 4, 6, 12 |
| A typo in KEDA trigger metadata was silently ignored ([7.8 N02](../07-Docker-JVM-Kubernetes/08-Kubernetes-Platform-Blueprints-II-Kustomize-Guardrails-Consumers-Jobs-Canary.md)) | [`KEDA_CHECK_UNEXPECTED_SCALERS_PARAMS`](https://github.com/kedacore/keda/blob/v2.21.0/pkg/scalers/scalersconfig/typed_config.go#L40) | Opt-in; it logs and emits an event, never rejects |
| `cooldownPeriod` didn't stop 6 ↔ 4 flapping ([10.5 drill 7](../10-Kafka-Production/05-Bar-Raiser-Drill-Downs.md)) | [`scaleToZeroOrIdle`](https://github.com/kedacore/keda/blob/v2.21.0/pkg/scaling/executor/scale_scaledobjects.go#L199) is the only user of [`cooldownPeriod`](https://github.com/kedacore/keda/blob/v2.21.0/pkg/scaling/executor/scale_scaledobjects.go#L223) | Between 1 and N, the HPA's `behavior` decides |
| `canary > on (namespace) 2 * stable` dropped the `job` label ([7.8 §6.2](../07-Docker-JVM-Kubernetes/08-Kubernetes-Platform-Blueprints-II-Kustomize-Guardrails-Consumers-Jobs-Canary.md)) | [`resultMetric`: one-to-one with `on` → `Keep(matching.MatchingLabels...)`](https://github.com/prometheus/prometheus/blob/v3.15.1/promql/engine.go#L3446) | `group_left` keeps the left side's labels |
| kustomize `labels` with `includeSelectors` rewrote `topologySpreadConstraints` ([7.8](../07-Docker-JVM-Kubernetes/08-Kubernetes-Platform-Blueprints-II-Kustomize-Guardrails-Consumers-Jobs-Canary.md)) | [The field-spec list](https://github.com/kubernetes-sigs/kustomize/blob/kustomize/v5.8.3/api/internal/konfig/builtinpluginconsts/commonlabels.go#L41) | Which paths a label transformer touches is data you can read |

The PDB rounding, both branches:

```go
    maxUnavailable, err = intstr.GetScaledValueFromIntOrPercent(pdb.Spec.MaxUnavailable, int(expectedCount), true)
    if err != nil {
        return
    }
    desiredHealthy = expectedCount - int32(maxUnavailable)
    if desiredHealthy < 0 {
        desiredHealthy = 0
    }
} else if pdb.Spec.MinAvailable != nil {
    if pdb.Spec.MinAvailable.Type == intstr.Int {
        desiredHealthy = pdb.Spec.MinAvailable.IntVal
        expectedCount = int32(len(pods))
    } else if pdb.Spec.MinAvailable.Type == intstr.String {
        expectedCount, unmanagedPods, err = dc.getExpectedScale(ctx, pods)
        if err != nil {
            return
        }

        var minAvailable int
        minAvailable, err = intstr.GetScaledValueFromIntOrPercent(pdb.Spec.MinAvailable, int(expectedCount), true)
```

The quota rule for terminating pods:

```go
// QuotaV1Pod returns true if the pod is eligible to track against a quota
// if it's not in a terminal state according to its phase.
func QuotaV1Pod(pod *corev1.Pod, clock clock.Clock) bool {
    // if pod is terminal, ignore it for quota
    if corev1.PodFailed == pod.Status.Phase || corev1.PodSucceeded == pod.Status.Phase {
        return false
    }
    // if pods are stuck terminating (for example, a node is lost), we do not want
    // to charge the user for that pod in quota because it could prevent them from
    // scaling up new pods to service their application.
    if pod.DeletionTimestamp != nil && pod.DeletionGracePeriodSeconds != nil {
        now := clock.Now()
        deletionTime := pod.DeletionTimestamp.Time
        gracePeriod := time.Duration(*pod.DeletionGracePeriodSeconds) * time.Second
        if now.After(deletionTime.Add(gracePeriod)) {
            return false
        }
    }
    return true
}
```

KEDA's cap:

```go
if !s.metadata.AllowIdleConsumers || s.metadata.LimitToPartitionsWithLag || s.metadata.EnsureEvenDistributionOfPartitions {
    // don't scale out beyond the number of topicPartitions or partitionsWithLag depending on settings
    upperBound := totalTopicPartitions
    // Ensure that the number of partitions is evenly distributed across the number of consumers
    if s.metadata.EnsureEvenDistributionOfPartitions {
        nextFactor := getNextFactorThatBalancesConsumersToTopicPartitions(totalLag, totalTopicPartitions, s.metadata.LagThreshold)
        s.logger.V(1).Info(fmt.Sprintf("Kafka scaler: Providing metrics to ensure even distribution of partitions on totalLag %v, topicPartitions %v, evenPartitions %v", totalLag, totalTopicPartitions, nextFactor))
        totalLag = nextFactor * s.metadata.LagThreshold
```

---

## 5. Kafka 4.2.2 and spring-kafka 4.1.2

| Measured in the kit | The code that explains it | What to notice |
|---|---|---|
| A static member's `close()` stalled its partitions **45 s** ([10.4 §1](../10-Kafka-Production/04-Consumer-Scaling-Static-Membership-KIP-848-KEDA-Rolling-Deploys.md)) | [`shouldSendLeaveGroupRequest`](https://github.com/apache/kafka/blob/4.2.2/clients/src/main/java/org/apache/kafka/clients/consumer/internals/AbstractCoordinator.java#L1192) | `DEFAULT` close leaves only for dynamic members |
| Same under KIP-848 (45.3 s) | [`leaveGroupEpoch`](https://github.com/apache/kafka/blob/4.2.2/clients/src/main/java/org/apache/kafka/clients/consumer/internals/ConsumerMembershipManager.java#L512) sends [`-2` for static members](https://github.com/apache/kafka/blob/4.2.2/clients/src/main/java/org/apache/kafka/common/requests/ConsumerGroupHeartbeatRequest.java#L32) unless `LEAVE_GROUP` | "Temporarily leaving": the broker keeps the assignment until the session times out |
| KIP-848 rejected `session.timeout.ms` at startup ([10.4](../10-Kafka-Production/04-Consumer-Scaling-Static-Membership-KIP-848-KEDA-Rolling-Deploys.md)) | [`... cannot be set when group.protocol=CONSUMER`](https://github.com/apache/kafka/blob/4.2.2/clients/src/main/java/org/apache/kafka/clients/consumer/ConsumerConfig.java#L786) | A good failure: it shows up in the canary |
| Broker minimum session 45 s, heartbeat 5 s ([10.4](../10-Kafka-Production/04-Consumer-Scaling-Static-Membership-KIP-848-KEDA-Rolling-Deploys.md)) | [`GroupCoordinatorConfig`](https://github.com/apache/kafka/blob/4.2.2/group-coordinator/src/main/java/org/apache/kafka/coordinator/group/GroupCoordinatorConfig.java#L163) | Moved from client to broker in KIP-848 |
| `linger.ms` defaults to 5 in 4.x ([10.1](../10-Kafka-Production/01-Kafka-Producers-Batching-Idempotence-Ordering.md)) | [`define(LINGER_MS_CONFIG, Type.LONG, 5, ...)`](https://github.com/apache/kafka/blob/4.2.2/clients/src/main/java/org/apache/kafka/clients/producer/ProducerConfig.java#L405) | Producers batch for 5 ms even when nobody configured it |
| Two brokers down: `acks=all` surfaced after **120 s** as `TimeoutException` ([10.3 §3](../10-Kafka-Production/03-Production-Kafka-Multi-Broker-Durability-Compaction-Strimzi-Blueprint.md)) | [`delivery.timeout.ms` = `120 * 1000`](https://github.com/apache/kafka/blob/4.2.2/clients/src/main/java/org/apache/kafka/clients/producer/ProducerConfig.java#L406) | Retriable errors are retried until this expires |
| Idempotence survives `max.in.flight ≤ 5` ([10.1](../10-Kafka-Production/01-Kafka-Producers-Batching-Idempotence-Ordering.md)) | [`NUM_BATCHES_TO_RETAIN`](https://github.com/apache/kafka/blob/4.2.2/storage/src/main/java/org/apache/kafka/storage/internals/log/ProducerStateEntry.java#L32) | The broker remembers 5 batches per producer |
| Default assignors behaved eagerly (the group stalled 41.4 s) ([10.4](../10-Kafka-Production/04-Consumer-Scaling-Static-Membership-KIP-848-KEDA-Rolling-Deploys.md)) | [`RangeAssignor.class, CooperativeStickyAssignor.class`](https://github.com/apache/kafka/blob/4.2.2/clients/src/main/java/org/apache/kafka/clients/consumer/ConsumerConfig.java#L448) | The first common assignor (Range, eager) wins |
| `DefaultErrorHandler` retries ~515 ms apart on a caught-up partition ([8.6 §7](06-Framework-Internals-by-Stack-Trace-Spring-Hibernate-HikariCP-Caffeine-Kafka.md)) | [`AbstractFetch` skips while a fetch is in flight](https://github.com/apache/kafka/blob/4.2.2/clients/src/main/java/org/apache/kafka/clients/consumer/internals/AbstractFetch.java#L458); [`fetch.max.wait.ms` = 500](https://github.com/apache/kafka/blob/4.2.2/clients/src/main/java/org/apache/kafka/clients/consumer/ConsumerConfig.java#L210) | The long poll, not the back-off, set the interval |
| spring-kafka appended `-0`…`-N` to `group.instance.id` and closed with plain `close()` ([10.4](../10-Kafka-Production/04-Consumer-Scaling-Static-Membership-KIP-848-KEDA-Rolling-Deploys.md)) | [`checkGroupInstance`](https://github.com/spring-projects/spring-kafka/blob/v4.1.2/spring-kafka/src/main/java/org/springframework/kafka/listener/KafkaMessageListenerContainer.java#L1120) [appends the suffix](https://github.com/spring-projects/spring-kafka/blob/v4.1.2/spring-kafka/src/main/java/org/springframework/kafka/listener/KafkaMessageListenerContainer.java#L1133); [`this.consumer.close()`](https://github.com/spring-projects/spring-kafka/blob/v4.1.2/spring-kafka/src/main/java/org/springframework/kafka/listener/KafkaMessageListenerContainer.java#L2118) | No `CloseOptions`: static members never leave on shutdown |
| Container stop waits 10 s ([10.5 drill 11](../10-Kafka-Production/05-Bar-Raiser-Drill-Downs.md)) | [`DEFAULT_SHUTDOWN_TIMEOUT`](https://github.com/spring-projects/spring-kafka/blob/v4.1.2/spring-kafka/src/main/java/org/springframework/kafka/listener/ContainerProperties.java#L202) | Budget it inside the pod's grace period |
| `DefaultErrorHandler` = 10 attempts, then log and skip ([10.2 §4](../10-Kafka-Production/02-Kafka-Consumers-Rebalancing-EOS-Retries-DLQ.md)) | [`new FixedBackOff(0, DEFAULT_MAX_FAILURES - 1)`](https://github.com/spring-projects/spring-kafka/blob/v4.1.2/spring-kafka/src/main/java/org/springframework/kafka/listener/SeekUtils.java#L63), [`DEFAULT_MAX_FAILURES = 10`](https://github.com/spring-projects/spring-kafka/blob/v4.1.2/spring-kafka/src/main/java/org/springframework/kafka/listener/SeekUtils.java#L57) | Skip means the record is gone unless a recoverer publishes it |
| DLT topic `<topic>-dlt` ([10.2](../10-Kafka-Production/02-Kafka-Consumers-Rebalancing-EOS-Retries-DLQ.md)) | [`DEFAULT_DESTINATION_RESOLVER`](https://github.com/spring-projects/spring-kafka/blob/v4.1.2/spring-kafka/src/main/java/org/springframework/kafka/listener/DeadLetterPublishingRecoverer.java#L76) in `DeadLetterPublishingRecoverer`; retry topics use [`DEFAULT_DLT_SUFFIX`](https://github.com/spring-projects/spring-kafka/blob/v4.1.2/spring-kafka/src/main/java/org/springframework/kafka/retrytopic/RetryTopicConstants.java#L37) | Same partition number: the DLT needs at least as many partitions |

The two lines behind the 45-second stall:

```java
private boolean shouldSendLeaveGroupRequest(CloseOptions.GroupMembershipOperation membershipOperation) {
    if (!coordinatorUnknown() && state != MemberState.UNJOINED && generation.hasMemberId()) {
        return membershipOperation == LEAVE_GROUP || (isDynamicMember() && membershipOperation == DEFAULT);
    } else {
        return false;
    }
}

protected boolean isDynamicMember() {
    return rebalanceConfig.groupInstanceId.isEmpty();
}
```

```java
public int leaveGroupEpoch() {
    boolean isStaticMember = groupInstanceId.isPresent();
    // Currently, the server doesn't have a mechanism for static members to permanently leave the group.
    // Therefore, we use LEAVE_GROUP_MEMBER_EPOCH to force the GroupMetadataManager to fence
    // this member, effectively removing it from the group.
    if (LEAVE_GROUP == leaveGroupOperation) {
        return ConsumerGroupHeartbeatRequest.LEAVE_GROUP_MEMBER_EPOCH;
    }

    return isStaticMember ?
        ConsumerGroupHeartbeatRequest.LEAVE_GROUP_STATIC_MEMBER_EPOCH :
        ConsumerGroupHeartbeatRequest.LEAVE_GROUP_MEMBER_EPOCH;
}
```

---

## 6. Spring Boot 4.1.2, Spring Framework 7.0.10, Hibernate 7.4.13

| Measured in the kit | The code that explains it | What to notice |
|---|---|---|
| Boot exited **1** for every startup failure, ignoring `ExitCodeExceptionMapper`s ([7.8 §4.1](../07-Docker-JVM-Kubernetes/08-Kubernetes-Platform-Blueprints-II-Kustomize-Guardrails-Consumers-Jobs-Canary.md)) | [`getExitCodeFromMappedException`](https://github.com/spring-projects/spring-boot/blob/v4.1.2/core/spring-boot/src/main/java/org/springframework/boot/SpringApplication.java#L890) | A failed refresh leaves the context inactive, so mappers are skipped |
| Graceful shutdown is the default ([7.3](../07-Docker-JVM-Kubernetes/03-Kubernetes-Probes-and-Graceful-Shutdown.md)) | [`Shutdown.GRACEFUL`](https://github.com/spring-projects/spring-boot/blob/v4.1.2/module/spring-boot-web-server/src/main/java/org/springframework/boot/web/server/autoconfigure/ServerProperties.java#L95) | Opt out explicitly, never by accident |
| `applicationTaskExecutor` never grew past 8 threads; 392 tasks queued ([8.9 R10](09-Staff-Level-System-and-Code-Review-Checklist-20-Questions.md)) | [`queueCapacity = Integer.MAX_VALUE`](https://github.com/spring-projects/spring-boot/blob/v4.1.2/core/spring-boot-autoconfigure/src/main/java/org/springframework/boot/autoconfigure/task/TaskExecutionProperties.java#L133) | With an unbounded queue, `max-size` is never reached |
| `SpringApplicationBuilder.properties()` had the lowest precedence ([4.1 §8.1](../04-Spring-Boot-Internals/01-IoC-Container-Startup-BeanDefinition-PostProcessors.md#81-where-a-property-value-actually-comes-from-verified)) | [`defaultProperties`](https://github.com/spring-projects/spring-boot/blob/v4.1.2/core/spring-boot/src/main/java/org/springframework/boot/builder/SpringApplicationBuilder.java#L78) | They're defaults, not overrides |
| The open-in-view warning at startup | [`JpaBaseConfiguration`](https://github.com/spring-projects/spring-boot/blob/v4.1.2/module/spring-boot-jpa/src/main/java/org/springframework/boot/jpa/autoconfigure/JpaBaseConfiguration.java#L250) | Still on by default; set it explicitly |
| An `AFTER_COMMIT` write survived with Hikari auto-commit on ([4.8 §2.1](../04-Spring-Boot-Internals/08-Request-Lifecycle-Events-Async-Graceful-Shutdown.md#21-the-after_commit-write-trap-proven-both-ways-)) | [`setMustRestoreAutoCommit(true)`](https://github.com/spring-projects/spring-framework/blob/v7.0.10/spring-jdbc/src/main/java/org/springframework/jdbc/datasource/DataSourceTransactionManager.java#L293) … [restored after completion](https://github.com/spring-projects/spring-framework/blob/v7.0.10/spring-jdbc/src/main/java/org/springframework/jdbc/datasource/DataSourceTransactionManager.java#L387) | Auto-commit returns after the callbacks ran |
| The connection was borrowed in `doBegin` ([8.6 §4](06-Framework-Internals-by-Stack-Trace-Spring-Hibernate-HikariCP-Caffeine-Kafka.md)) | [`getJpaDialect().beginTransaction(...)`](https://github.com/spring-projects/spring-framework/blob/v7.0.10/spring-orm/src/main/java/org/springframework/orm/jpa/JpaTransactionManager.java#L411); opt out with [`provider_disables_autocommit`](https://github.com/hibernate/hibernate-orm/blob/7.4.13/hibernate-core/src/main/java/org/hibernate/cfg/JdbcSettings.java#L338) | Held from the method's first line |
| `@TransactionalEventListener` ran after `afterCommit` ([8.6 §3](06-Framework-Internals-by-Stack-Trace-Spring-Hibernate-HikariCP-Caffeine-Kafka.md)) | [`afterCompletion`](https://github.com/spring-projects/spring-framework/blob/v7.0.10/spring-tx/src/main/java/org/springframework/transaction/event/TransactionalApplicationListenerSynchronization.java#L115) | Before the HTTP response |
| `@Cacheable(sync = true)` runs the loader under a lock ([8.6 §6](06-Framework-Internals-by-Stack-Trace-Spring-Hibernate-HikariCP-Caffeine-Kafka.md)) | [`executeSynchronized`](https://github.com/spring-projects/spring-framework/blob/v7.0.10/spring-context/src/main/java/org/springframework/cache/interceptor/CacheAspectSupport.java#L448) → [`CaffeineCache.get(key, loader)`](https://github.com/spring-projects/spring-framework/blob/v7.0.10/spring-context-support/src/main/java/org/springframework/cache/caffeine/CaffeineCache.java#L133) | |
| Delete-then-insert of a unique key failed ([8.6 §3](06-Framework-Internals-by-Stack-Trace-Spring-Hibernate-HikariCP-Caffeine-Kafka.md), [3.2](../03-JPA-Hibernate-Spring-Data/02-ActionQueue-Flush-Ordering.md)) | [`OrderedActions`](https://github.com/hibernate/hibernate-orm/blob/7.4.13/hibernate-core/src/main/java/org/hibernate/engine/spi/ActionQueue.java#L109) | Inserts at line 135, deletes at 210 |
| `JOIN FETCH` + `setMaxResults` paginated in memory (HHH90003004) ([3.3](../03-JPA-Hibernate-Spring-Data/03-NPlus1-Lazy-Loading-Fetch-Plans-Pagination-Projections.md)) | [`firstOrMaxResultsSpecifiedWithCollectionFetch`](https://github.com/hibernate/hibernate-orm/blob/7.4.13/hibernate-core/src/main/java/org/hibernate/query/QueryLogging.java#L59) | The warning to fail the build on |
| `…pooled.preferred_lo` was ignored ([3.4](../03-JPA-Hibernate-Spring-Data/04-Write-Throughput-Batching-Sequences-Hybrid-JDBC-jOOQ.md)) | [`PREFERRED_POOLED_OPTIMIZER`](https://github.com/hibernate/hibernate-orm/blob/7.4.13/hibernate-core/src/main/java/org/hibernate/cfg/MappingSettings.java#L138) read by [`OptimizerFactory`](https://github.com/hibernate/hibernate-orm/blob/7.4.13/hibernate-core/src/main/java/org/hibernate/id/enhanced/OptimizerFactory.java#L81) | The only key is `hibernate.id.optimizer.pooled.preferred` |
| A native `UPDATE` without synchronization evicted the whole second-level cache ([3.7 §2](../03-JPA-Hibernate-Spring-Data/07-High-Scale-Persistence-Streaming-L2-Cache-Batch-Fetch-Multitenancy-EXPLAIN.md#2-the-second-level-cache-hits-invalidation-and-staleness-verified-)) | [`affectedEntity`](https://github.com/hibernate/hibernate-orm/blob/7.4.13/hibernate-core/src/main/java/org/hibernate/action/internal/BulkOperationCleanupAction.java#L191): [unknown table spaces → every entity](https://github.com/hibernate/hibernate-orm/blob/7.4.13/hibernate-core/src/main/java/org/hibernate/action/internal/BulkOperationCleanupAction.java#L192) | Declare `addSynchronizedEntityClass` |

```java
private int getExitCodeFromMappedException(@Nullable ConfigurableApplicationContext context, Throwable exception) {
    if (context == null || !context.isActive()) {
        return 0;
    }
```

```java
private boolean affectedEntity(Set<?> affectedTableSpaces, Serializable[] checkTableSpaces) {
    if ( affectedTableSpaces == null || affectedTableSpaces.isEmpty() ) {
        return true;
    }
    else {
        for ( Serializable checkTableSpace : checkTableSpaces ) {
            if ( affectedTableSpaces.contains( checkTableSpace ) ) {
                return true;
            }
        }
        return false;
    }
}
```

---

## 7. Resilience4j 2.4.0, Spring Cloud CircuitBreaker 5.0.1, Caffeine, HikariCP, Maven

| Measured or claimed in the kit | The code that explains it | What to notice |
|---|---|---|
| `slowCallDurationThreshold` defaults to 60 s ([6.5 drill 9](../06-Resilience-Caching/05-Bar-Raiser-Drill-Downs.md)) | [`DEFAULT_SLOW_CALL_DURATION_THRESHOLD`](https://github.com/resilience4j/resilience4j/blob/v2.4.0/resilience4j-circuitbreaker/src/main/java/io/github/resilience4j/circuitbreaker/CircuitBreakerConfig.java#L49) | "Never" for an HTTP client with a sane timeout |
| 10 permits in 54 ms with a limit of 5/s ([6.2](../06-Resilience-Caching/02-Bulkheads-Rate-Limiters-Retries-Jitter-Decorator-Order.md)) | [`calculateNextState`](https://github.com/resilience4j/resilience4j/blob/v2.4.0/resilience4j-ratelimiter/src/main/java/io/github/resilience4j/ratelimiter/internal/AtomicRateLimiter.java#L227): [whole cycles](https://github.com/resilience4j/resilience4j/blob/v2.4.0/resilience4j-ratelimiter/src/main/java/io/github/resilience4j/ratelimiter/internal/AtomicRateLimiter.java#L233) | A fixed window, not a token bucket |
| Discarded `OpenState`s left timers that flipped a breaker to HALF_OPEN ([8.4 §6](04-High-Performance-Internals-HikariCP-Resilience4j-Caffeine.md)) | [`stateReference.getAndUpdate`](https://github.com/resilience4j/resilience4j/blob/v2.4.0/resilience4j-circuitbreaker/src/main/java/io/github/resilience4j/circuitbreaker/internal/CircuitBreakerStateMachine.java#L313) with [a side-effecting updater](https://github.com/resilience4j/resilience4j/blob/v2.4.0/resilience4j-circuitbreaker/src/main/java/io/github/resilience4j/circuitbreaker/internal/CircuitBreakerStateMachine.java#L315) | Re-applied under contention |
| Spring Cloud CircuitBreaker adds a 1 s time limit by default ([8.2 §5](02-Microservices-and-Cloud-Native-Repos.md)) | [`TimeLimiterConfig.ofDefaults()`](https://github.com/spring-cloud/spring-cloud-circuitbreaker/blob/v5.0.1/spring-cloud-circuitbreaker-resilience4j/src/main/java/org/springframework/cloud/circuitbreaker/resilience4j/Resilience4JConfigBuilder.java#L33) = [`Duration.ofSeconds(1)`](https://github.com/resilience4j/resilience4j/blob/v2.4.0/resilience4j-timelimiter/src/main/java/io/github/resilience4j/timelimiter/TimeLimiterConfig.java#L14) | Petclinic's `cb.run(...)` has a timeout nobody configured |
| Caffeine admits a warm candidate 1 time in 128 ([6.3 §1.2](../06-Resilience-Caching/03-Caching-Caffeine-W-TinyLFU-and-Redis-Lettuce-L1-L2.md)) | [`ADMIT_HASHDOS_THRESHOLD = 6`](https://github.com/ben-manes/caffeine/blob/v3.3.1/caffeine/src/main/java/com/github/benmanes/caffeine/cache/BoundedLocalCache.java#L229) | Defends against hash flooding |
| HikariCP's virtual-thread back-off isn't in the version Boot 4.1.2 ships ([8.4 §6](04-High-Performance-Internals-HikariCP-Resilience4j-Caffeine.md)) | [7.0.2 `requite`](https://github.com/brettwooldridge/HikariCP/blob/HikariCP-7.0.2/src/main/java/com/zaxxer/hikari/util/ConcurrentBag.java#L195) vs [7.1.0](https://github.com/brettwooldridge/HikariCP/blob/HikariCP-7.1.0/src/main/java/com/zaxxer/hikari/util/ConcurrentBag.java#L225) | Read the tag you run |
| Maven picks the nearest version ([1.3](../01-Build-Systems/03-Dependency-Resolution-Jar-Hell-BOMs-Catalogs-Shading.md)) | [`NearestVersionSelector`](https://github.com/apache/maven-resolver/blob/maven-resolver-2.0.24/maven-resolver-util/src/main/java/org/eclipse/aether/util/graph/transformer/NearestVersionSelector.java#L47) | Depth first, then declaration order |

---

## 8. The upgrade watchlist: lines to re-read when you bump a version 🧊

| When you upgrade | Re-read | Because the kit's behaviour depends on it |
|---|---|---|
| The JDK | [`os::is_server_class_machine`](https://github.com/openjdk/jdk25u/blob/jdk-25.0.4.1+1/src/hotspot/share/runtime/os.cpp#L1928), [`G1ConcurrentMark::remark`](https://github.com/openjdk/jdk25u/blob/jdk-25.0.4.1+1/src/hotspot/share/gc/g1/g1ConcurrentMark.cpp#L1384), [cgroup v2 readers](https://github.com/openjdk/jdk25u/blob/jdk-25.0.4.1+1/src/hotspot/os/linux/cgroupV2Subsystem_linux.cpp#L298) | GC selection, heap shrink, container limits |
| The Spring Boot BOM | [`SpringApplication` exit codes](https://github.com/spring-projects/spring-boot/blob/v4.1.2/core/spring-boot/src/main/java/org/springframework/boot/SpringApplication.java#L890), [`ServerProperties.shutdown`](https://github.com/spring-projects/spring-boot/blob/v4.1.2/module/spring-boot-web-server/src/main/java/org/springframework/boot/web/server/autoconfigure/ServerProperties.java#L95), [`TaskExecutionProperties`](https://github.com/spring-projects/spring-boot/blob/v4.1.2/core/spring-boot-autoconfigure/src/main/java/org/springframework/boot/autoconfigure/task/TaskExecutionProperties.java#L133), and the managed HikariCP/Caffeine versions | Exit codes in Jobs, drain, executor back-pressure, which library code you actually run |
| kafka-clients | [`ProducerConfig` defaults](https://github.com/apache/kafka/blob/4.2.2/clients/src/main/java/org/apache/kafka/clients/producer/ProducerConfig.java#L405), [`ConsumerConfig` rejections](https://github.com/apache/kafka/blob/4.2.2/clients/src/main/java/org/apache/kafka/clients/consumer/ConsumerConfig.java#L786), [leave-group rules](https://github.com/apache/kafka/blob/4.2.2/clients/src/main/java/org/apache/kafka/clients/consumer/internals/AbstractCoordinator.java#L1192), [fetch pipelining](https://github.com/apache/kafka/blob/4.2.2/clients/src/main/java/org/apache/kafka/clients/consumer/internals/AbstractFetch.java#L458) | Batching, startup failures, scale-down stalls, retry timing |
| spring-kafka | [`SeekUtils` default back-off](https://github.com/spring-projects/spring-kafka/blob/v4.1.2/spring-kafka/src/main/java/org/springframework/kafka/listener/SeekUtils.java#L63), [`checkGroupInstance`](https://github.com/spring-projects/spring-kafka/blob/v4.1.2/spring-kafka/src/main/java/org/springframework/kafka/listener/KafkaMessageListenerContainer.java#L1120), [`ContainerProperties` shutdown](https://github.com/spring-projects/spring-kafka/blob/v4.1.2/spring-kafka/src/main/java/org/springframework/kafka/listener/ContainerProperties.java#L202) | Data loss on skip, static ids, shutdown budget |
| Kubernetes | [PDB rounding](https://github.com/kubernetes/kubernetes/blob/v1.37.1/pkg/controller/disruption/disruption.go#L847), [quota evaluator](https://github.com/kubernetes/kubernetes/blob/v1.37.1/pkg/quota/v1/evaluator/core/pods.go#L491), [kubelet `killContainer`](https://github.com/kubernetes/kubernetes/blob/v1.37.1/pkg/kubelet/kuberuntime/kuberuntime_container.go#L897), [HPA defaults](https://github.com/kubernetes/kubernetes/blob/v1.37.1/pkg/controller/podautoscaler/config/v1alpha1/defaults.go#L53) | Drains, quota headroom, shutdown budgets, scaling |
| KEDA | [`kafka_scaler.go` bounds](https://github.com/kedacore/keda/blob/v2.21.0/pkg/scalers/kafka_scaler.go#L942), [typed-config checks](https://github.com/kedacore/keda/blob/v2.21.0/pkg/scalers/scalersconfig/typed_config.go#L40) | Replica caps, silently ignored metadata |
| Hibernate | [`ActionQueue` order](https://github.com/hibernate/hibernate-orm/blob/7.4.13/hibernate-core/src/main/java/org/hibernate/engine/spi/ActionQueue.java#L109), [`BulkOperationCleanupAction`](https://github.com/hibernate/hibernate-orm/blob/7.4.13/hibernate-core/src/main/java/org/hibernate/action/internal/BulkOperationCleanupAction.java#L191), [optimizer settings](https://github.com/hibernate/hibernate-orm/blob/7.4.13/hibernate-core/src/main/java/org/hibernate/cfg/MappingSettings.java#L138) | Flush order, cache eviction, id allocation |
| Lettuce / Spring Data Redis | [`RedisURI.DEFAULT_TIMEOUT`](https://github.com/redis/lettuce/blob/7.5.2.RELEASE/src/main/java/io/lettuce/core/RedisURI.java#L224), [cache writer defaults](https://github.com/spring-projects/spring-data-redis/blob/4.1.2/src/main/java/org/springframework/data/redis/cache/DefaultRedisCacheWriter.java#L162) | Thread hold time, read-your-writes |
| Resilience4j | [`CircuitBreakerConfig` defaults](https://github.com/resilience4j/resilience4j/blob/v2.4.0/resilience4j-circuitbreaker/src/main/java/io/github/resilience4j/circuitbreaker/CircuitBreakerConfig.java#L49), [`AtomicRateLimiter`](https://github.com/resilience4j/resilience4j/blob/v2.4.0/resilience4j-ratelimiter/src/main/java/io/github/resilience4j/ratelimiter/internal/AtomicRateLimiter.java#L227) | Slow-call detection, burst behaviour |

A practical form: keep this table in the service's upgrade checklist, and keep a test per row where you can. The kit's own tests of this kind are the `promtool` rule tests (7.8), the manifest audit (7.8), `KafkaConsumer` config validation (10.4) and `javap -constants` reads of defaults (6.1, 10.2).

---

## 9. Interview soundbites

* "I don't trust a default until I've seen the constant. Lettuce's is `DEFAULT_TIMEOUT = 60` seconds; Resilience4j's slow-call threshold is 60 seconds; spring-kafka's error handler is `FixedBackOff(0, 9)` and then skips."
* "The PDB problem is one boolean: `GetScaledValueFromIntOrPercent(..., true)` rounds up, so `minAvailable: 75%` of 2 pods is 2. I use `maxUnavailable: 25%`, which rounds up in my favour."
* "The 45-second stall is `shouldSendLeaveGroupRequest`: a default `close()` leaves only for dynamic members, and under KIP-848 a static member sends epoch −2, 'temporarily leaving'."
* "Flyway's migration lock is a polling `pg_try_advisory_lock`, which is why nothing shows up as waiting in `pg_locks`."
* "When I upgrade, I re-read a short list of lines: the ones my production behaviour depends on. That list is the real value of reading source."

---

## Summary

| Area | The line that matters most | Section |
|---|---|---|
| JVM in containers | `is_server_class_machine` (2 CPUs) and G1's resize at Remark | §1 |
| PostgreSQL / Flyway | `BYPASS_THRESHOLD_PAGES 0.02`; Flyway's polling `pg_try_advisory_lock` | §2 |
| Redis | `EVICT_FAIL` with `volatile-*`; Lettuce `DEFAULT_TIMEOUT = 60`; SDR async writes | §3 |
| Kubernetes | PDB round-up; quota charges terminating pods; preStop inside the grace period | §4 |
| KEDA / Prometheus | `upperBound := totalTopicPartitions`; one-to-one `on` keeps only matching labels | §4 |
| Kafka | Static `close()` doesn't leave; KIP-848 epoch −2; fetch in flight sets the retry interval | §5 |
| Spring / Boot / Hibernate | Exit code 1 on refresh failure; connection at `doBegin`; inserts before deletes | §6 |
| Resilience4j / HikariCP | Side-effecting `getAndUpdate`; 7.0.2 vs 7.1.0 `requite` | §7 |
| Upgrades | A watchlist of lines per dependency | §8 |

**Next:** [8.8 GitHub codebase study matrix and master interview synthesis →](08-GitHub-Codebase-Study-Matrix-and-Master-Interview-Synthesis.md)
