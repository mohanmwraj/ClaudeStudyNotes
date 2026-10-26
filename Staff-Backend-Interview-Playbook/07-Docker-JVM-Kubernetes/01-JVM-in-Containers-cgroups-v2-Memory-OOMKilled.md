# 7.1 The JVM in Containers: cgroups v2, Heap Ergonomics, Native Memory, and the Four Kinds of "Out of Memory"

> **Verified stack:** Eclipse Temurin **25.0.4.1** (JDK 25 LTS), Spring Boot **4.1.2**, Kubernetes **1.37** concepts.
>
> **What was run, and what wasn't.** This machine is Windows 11 with no Docker and no WSL, so there was **no Linux container** to run in. Verified here: JVM ergonomics with `-XX:MaxRAM` (the same input a container memory limit feeds into heap sizing) and `-XX:ActiveProcessorCount` (the same input a CPU limit feeds into thread sizing), plus Native Memory Tracking of a running Boot 4 app. The cgroup files and the kernel OOM killer are explained from first principles with the commands to run yourself; **no container output is shown that wasn't produced.**
>
> **Go deeper:** sibling kit [1.2 runtime data areas & off-heap](../../Java-Backend-Master-Reference/01-JVM-Internals/02-Runtime-Data-Areas-Off-Heap-FFM.md), [1.4 GC](../../Java-Backend-Master-Reference/01-JVM-Internals/04-Garbage-Collection-G1-ZGC-Shenandoah.md), [JVM flags cheat sheet](../../Java-Backend-Master-Reference/99-Cheat-Sheets/01-JVM-Flags-and-Diagnostic-Commands.md); CKAD kit [requests, limits, quotas](../../CKAD-Exam-Prep/04-Application-Environment-Configuration-and-Security/03-requests-limits-and-quotas.md).

---

## 0. First principles: the JVM sizes itself from what it thinks it has 🔥

A container is an ordinary Linux process with two kinds of fences:

* **Namespaces** decide what it can **see** (its own PID 1, network interfaces, mounts, hostname).
* **cgroups** decide what it can **use** (memory, CPU time, PIDs, I/O).

At startup the JVM asks "how much memory and how many CPUs do I have?" and derives almost everything from the answer: max and initial heap, which GC to use, the number of GC threads, JIT compiler threads, `ForkJoinPool.commonPool()` parallelism, and the defaults of every library that calls `availableProcessors()` (Netty event loops, Tomcat, Kafka, Reactor).

Before container support (JDK 9, and JDK 8 before 8u191), the JVM read the **host's** `/proc/meminfo` and CPU count. On a 64-core, 256 GB node, a container limited to 2 GB got a 64 GB max heap and 43 parallel GC threads. The heap grew past 2 GB, the kernel killed the process, and nothing in the Java logs explained why. Container awareness (on by default since JDK 10, cgroups v2 support since JDK 15 and backported to 11.0.16 / 8u372) fixed the inputs. **Sizing correctly is still your job.**

---

## 1. Under the hood: cgroups v2 as the JVM sees it ⚡

cgroups v2 is one unified hierarchy under `/sys/fs/cgroup`. Inside a container you see your own cgroup's files:

| File | Meaning | Set by Kubernetes from |
|---|---|---|
| `memory.max` | Hard limit. Exceeding it triggers the **kernel OOM killer** | `resources.limits.memory` |
| `memory.current` | Current usage (anonymous + page cache + kernel memory) | |
| `memory.events` | Counters: `high`, `max`, `oom`, `oom_kill` | |
| `memory.stat` | Breakdown: `anon`, `file`, `kernel`, `sock`, … | |
| `cpu.max` | `"<quota> <period>"`, e.g. `200000 100000` = 2 CPUs per 100 ms period | `resources.limits.cpu` |
| `cpu.weight` | Relative share when CPUs are contended | `resources.requests.cpu` |
| `cpu.stat` | `nr_periods`, `nr_throttled`, `throttled_usec` | |
| `pids.max` | Max processes/threads | kubelet `podPidsLimit` |

What HotSpot does with them (`src/hotspot/os/linux/cgroupV2Subsystem_linux.cpp`):

* **Memory limit** = `memory.max`. That becomes the "physical memory" every ergonomic calculation uses.
* **CPU count** = `ceil(quota / period)` from `cpu.max`, capped by the cpuset. Since **JDK 19** (JDK-8281181), `cpu.weight` (requests) is **not** used. A pod with **no CPU limit sees every core of the node**.
* Overrides: `-XX:ActiveProcessorCount=N` for CPUs and `-XX:MaxRAM=<size>` for memory; `-XX:-UseContainerSupport` turns detection off (don't).

Commands to run inside a pod:

```bash
cat /sys/fs/cgroup/memory.max /sys/fs/cgroup/cpu.max      # what the kernel enforces
java -XshowSettings:system -version                        # what the JVM detected (provider cgroupv2, CPU quota, memory limit)
java -Xlog:os+container=trace -version                     # every cgroup file the JVM read, and the values
cat /sys/fs/cgroup/memory.events                           # oom / oom_kill counters for this cgroup
```

---

## 2. Heap ergonomics, verified 🔥

### 2.1 The defaults

```text
$ java -XX:+PrintFlagsFinal -version | grep RAMPercentage …     (Temurin 25.0.4.1)
  ActiveProcessorCount     -1
  InitialRAMPercentage     1.562500
  MaxRAMPercentage         25.000000
  MinRAMPercentage         50.000000
```

(`UseContainerSupport` doesn't appear in that list on Windows: it's a Linux-only flag, `true` by default there.)

**Max heap = 25 % of the memory limit.** In a 2 GiB pod that's a 512 MiB heap, and 1.5 GiB of mostly unused headroom. That's why everyone sets `MaxRAMPercentage`.

### 2.2 Max heap and GC choice by memory limit and CPU count

**Output (verified, Temurin 25.0.4.1; limits simulated with `-XX:MaxRAM` and `-XX:ActiveProcessorCount`):**

```text
== Heap ergonomics vs memory limit (simulated with -XX:MaxRAM), default percentages
  MaxRAM   CPUs      MaxHeapSize    InitialHeap  GC
  256m     1           132120576        8388608  UseSerialGC
  256m     2           132120576        8388608  UseG1GC
  512m     1           134217728        8388608  UseSerialGC
  512m     2           134217728        8388608  UseG1GC
  1g       1           268435456       16777216  UseSerialGC
  1g       2           268435456       16777216  UseG1GC
  2g       1           536870912       33554432  UseSerialGC
  2g       2           536870912       33554432  UseG1GC
  4g       1          1073741824       67108864  UseSerialGC
  4g       2          1073741824       67108864  UseG1GC
== Same limits with -XX:MaxRAMPercentage=75
  256m     MaxHeapSize=201326592
  512m     MaxHeapSize=402653184
  1g       MaxHeapSize=805306368
  2g       MaxHeapSize=1610612736
  4g       MaxHeapSize=3221225472
```

Reading it:

* At **256 MiB** the heap is about **126 MiB**, roughly 50 %. Very small memory takes the `MinRAMPercentage` branch. From 512 MiB up, it's the 25 % rule (128 MiB, 256 MiB, 512 MiB, 1 GiB).
* With `MaxRAMPercentage=75`: 192 MiB, 384 MiB, 768 MiB, 1.5 GiB, 3 GiB.
* **One CPU → `SerialGC`, at every memory size.** A pod with `limits.cpu: 1` (or `500m`, which rounds up to 1) silently runs the single-threaded stop-the-world collector. Per the HotSpot source (`os::is_server_class_machine`), G1 is chosen only on a "server-class machine": **≥ 2 CPUs and ≥ ~1792 MB of memory**. `-XX:MaxRAM` didn't trigger the memory half in this run because that check reads physical memory, which `MaxRAM` doesn't override; inside a container the limit *is* the physical memory. **Always set the collector explicitly** (`-XX:+UseG1GC` or `-XX:+UseZGC`) instead of inheriting a size-dependent default.

### 2.3 Thread pools follow the CPU count

**Output (verified):**

```text
  -XX:ActiveProcessorCount available  commonPool par.  ParallelGCThreads ConcGCThreads     CICompilerCount
  1                      1          1                1                 1                 2
  2                      2          1                2                 1                 2
  4                      4          3                4                 1                 3
  8                      8          7                8                 2                 4
  16                     16         15               13                3                 12
host: 12 11
```

`ParallelGCThreads` is `n` up to 8, then `8 + (n − 8) × 5/8` (13 at 16 CPUs). `ConcGCThreads` is about a quarter of that. On a 64-core node with **no CPU limit**, the same formula gives 43 parallel GC threads and a common pool of 63, all running inside a pod that the scheduler packed assuming it needs 1 CPU. That's the setup for the CPU-throttling problem in [7.4](04-CPU-Throttling-GC-Choice-HPA-KEDA.md).

---

## 3. Where a Java process's memory goes 🔥

The heap is one line in a longer bill. Native Memory Tracking of the Boot 4 probe app (Tomcat + Actuator, `-Xmx256m`, after about 300 requests):

```text
$ jcmd <pid> VM.native_memory summary          (-XX:NativeMemoryTracking=summary, Temurin 25.0.4.1, Boot 4.1.2)
  Total: reserved=1772545KB, committed=237409KB
  -                 Java Heap (reserved=262144KB, committed=69632KB)
  -                     Class (reserved=1049470KB, committed=7678KB)
  -                    Thread (reserved=46214KB, committed=2602KB)
  -                      Code (reserved=256708KB, committed=28192KB)
  -                        GC (reserved=59333KB, committed=55589KB)
  -                  Compiler (reserved=326KB, committed=326KB)
  -                  Internal (reserved=1479KB, committed=1479KB)
  -                    Symbol (reserved=9568KB, committed=9568KB)
  -    Native Memory Tracking (reserved=4011KB, committed=4011KB)
  -        Shared class space (reserved=16384KB, committed=14016KB, readonly=0KB)
  -                 Metaspace (reserved=65743KB, committed=43151KB)
  … (small categories omitted)
```

* **Committed** is what counts against the container limit (eventually, once touched). **Reserved** is address space and costs nothing: the 1 GB under `Class` is the compressed-class-space reservation, not memory used.
* **232 MB committed, of which the heap was 68 MB.** About **165 MB was outside the heap**: GC data structures (55 MB: G1's remembered sets, card table, mark bitmaps), Metaspace (43 MB), JIT code cache (28 MB), CDS archive (14 MB), symbols (9.5 MB).
* Under load, the non-heap side grows: more code cache, more threads, **direct buffers** (Netty, NIO, Kafka clients), and the **glibc malloc arenas** that NMT doesn't fully attribute.

The budget a container must cover:

```text
container limit  ≥  max heap
                  + metaspace + code cache + CDS/AOT cache
                  + GC structures              (scales with heap size; G1 more than Parallel/Serial)
                  + platform threads × stack   (-Xss, 1 MB reserved each; virtual-thread stacks live in the heap)
                  + direct memory              (-XX:MaxDirectMemorySize, defaults to the max heap size!)
                  + malloc arenas / native libs
                  + safety margin
```

How to find a native leak: start with `-XX:NativeMemoryTracking=summary` (a few percent overhead), take `jcmd <pid> VM.native_memory baseline`, run load, then `jcmd <pid> VM.native_memory summary.diff`. The category that keeps growing is the lead.

---

## 4. Four different "out of memory" failures 🔥

| Symptom | Who acts | What you see | Typical cause | Fix |
|---|---|---|---|---|
| `java.lang.OutOfMemoryError: Java heap space` | The **JVM** | Stack trace in logs; the process may **keep running in a broken state** | Live set > heap, or a leak | `-XX:+ExitOnOutOfMemoryError` (exits with code 3, so Kubernetes restarts it) + `-XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=/dumps`; fix the leak or size the heap |
| `OutOfMemoryError: Metaspace` / `Direct buffer memory` / `unable to create native thread` | The **JVM** | Specific message | Class-loader leak; Netty/NIO buffers; thread explosion or `pids.max` | `MaxMetaspaceSize`, `MaxDirectMemorySize`, bounded pools, virtual threads |
| **OOMKilled** | The **kernel** (cgroup OOM killer) | **SIGKILL, exit code 137**, `Reason: OOMKilled` in `kubectl describe pod`, `oom_kill` in `memory.events`. **No Java stack trace, no heap dump** | Heap + non-heap > `memory.max`. **The heap can be perfectly fine** | Leave non-heap headroom (§5); NMT to find what grew |
| **Evicted** | The **kubelet** (node memory pressure) | `Status: Failed, Reason: Evicted` | The *node* ran low; pods using more than their **requests** go first (BestEffort → Burstable → Guaranteed) | Memory `requests = limits` (Guaranteed for memory), realistic requests |

The interview trap: *"Our pod was OOMKilled, so we raised -Xmx."* That makes it **worse**. OOMKilled means the **whole process** exceeded the limit; a bigger heap leaves even less room for everything else. A heap problem shows up as a Java `OutOfMemoryError`, not as exit code 137.

---

## 5. Sizing recipe ⚡

```yaml
resources:
  requests: { cpu: "1",  memory: 1Gi }
  limits:   {            memory: 1Gi }      # memory: requests = limits; CPU limit: see 7.4
env:
  - name: JDK_JAVA_OPTIONS                    # launcher only: jcmd/jstack don't inherit it (7.7 section 4.5)
    value: >-
      -XX:MaxRAMPercentage=65 -XX:InitialRAMPercentage=65
      -XX:MaxHeapFreeRatio=100 -XX:+AlwaysPreTouch
      -XX:+UseG1GC -XX:ActiveProcessorCount=2
      -XX:+ExitOnOutOfMemoryError -XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=/dumps
      -XX:MaxDirectMemorySize=128m
  - name: MALLOC_ARENA_MAX
    value: "2"                                # cap glibc arenas (fewer, more contended arenas, much less RSS growth)
```

* **Percentages break for small pods.** At 512 MiB, 75 % is a 384 MiB heap, and the idle non-heap measured above was about 165 MB, so the pod is OOMKilled under load. Below about 1 GiB use explicit `-Xmx` with 250–400 MB of non-heap headroom for a Spring Boot service. From 2 GiB up, 70–80 % usually works.
* ⚠️ **Initial = max alone doesn't keep the heap** (corrected after measuring, [7.7 §4.2](07-Container-Images-and-JVM-Profiles-Blueprints-II-jlink-AOT-Workloads.md)). G1 uncommitted 674 MB of a 718 MB initial heap at the first Remark, 0.85 s into a Spring start. To keep it committed add `-XX:MaxHeapFreeRatio=100` (or `-Xms = -Xmx`). To make it **resident**, so an undersized pod fails at deploy time instead of at peak traffic, add `-XX:+AlwaysPreTouch`: working set 874 MB vs 267 MB without it, at no measurable startup cost at that size. 65 % leaves room for the measured 159 MB idle non-heap.
* **Measure, then set.** Run a load test with NMT on, watch `container_memory_working_set_bytes` (what the kubelet uses for eviction) and the kernel's `memory.current`, and keep peak usage under about 85 % of the limit.
* **Guaranteed memory**: `requests.memory = limits.memory`. A JVM's RSS rarely shrinks, so a request below the actual usage just marks the pod for eviction.

---

## 6. ❌ Naïve vs ✅ production-hardened

| ❌ Naïve | ✅ Production-hardened |
|---|---|
| No flags: heap = 25 % of the limit | `MaxRAMPercentage` 70–80 (big pods) or explicit `-Xmx` (small pods) |
| `-Xmx` = the container limit | Heap + measured non-heap + margin ≤ limit |
| OOMKilled → raise `-Xmx` | OOMKilled = native/total memory; NMT, then raise the **limit** or cut non-heap |
| `limits.cpu: 1` and whatever GC the JVM picks | GC set explicitly; aware that 1 CPU means SerialGC by default |
| No CPU limit and default thread counts (node core count) | `-XX:ActiveProcessorCount` = what the pod is entitled to |
| `OutOfMemoryError` leaves a zombie process | `ExitOnOutOfMemoryError` + heap dump to a volume |
| Memory request far below usage | `requests.memory = limits.memory` |
| Unbounded direct memory (Netty, Kafka) | `MaxDirectMemorySize`, monitored |
| Default glibc arenas on many-core nodes | `MALLOC_ARENA_MAX=2` (or a different allocator), after measuring |

---

## 7. Source to read

| Repo | Path | What to look for |
|---|---|---|
| [openjdk/jdk](https://github.com/openjdk/jdk) | `src/hotspot/os/linux/cgroupV2Subsystem_linux.cpp` | Reading `memory.max`, `cpu.max`, `cpu.weight` |
| same | `src/hotspot/os/linux/cgroupSubsystem_linux.cpp` | v1 vs v2 detection, `active_processor_count` |
| same | `src/hotspot/os/linux/osContainer_linux.cpp` | What `-XshowSettings:system` and `os+container` logging report |
| same | `src/hotspot/share/gc/shared/gcArguments.cpp` | Heap sizing from `MaxRAMPercentage` / `MinRAMPercentage` |
| same | `src/hotspot/share/gc/shared/gcConfig.cpp` | How the default GC is selected |

---

## 8. Interview soundbites

* "The JVM sizes its heap, GC and thread pools from the memory and CPU it detects, and in a container that's the cgroup's `memory.max` and `cpu.max`. CPU requests aren't used since JDK 19, so no CPU limit means it sees the whole node."
* "Default max heap is 25 % of the limit, and with one CPU the default collector is Serial. I verified both on JDK 25, so I set the percentage and the GC explicitly."
* "A small Boot app had 68 MB of heap committed and about 165 MB outside it: GC structures, metaspace, code cache, CDS. Container sizing is heap plus non-heap plus margin."
* "OOMKilled with exit code 137 is the kernel, not the JVM. No stack trace, often a healthy heap. Raising `-Xmx` makes it worse."
* "Memory requests equal limits, exit on `OutOfMemoryError` with a heap dump, and NMT baselines in staging to catch native growth."

---

## 9. Deep dive: what the JVM actually keeps, per workload (verified) 🔥

[7.7 §4](07-Container-Images-and-JVM-Profiles-Blueprints-II-jlink-AOT-Workloads.md) measured this module's sizing recipe on the real order-service. Container limits were simulated with `-XX:MaxRAM`/`ActiveProcessorCount`; NMT and the process working set were read through `jcmd`. The rows that matter:

| Profile | Committed heap | Working set | Lesson |
|---|---|---|---|
| 70 % max, **70 % initial** (§5 as first written) | **70 MB** of 718 | 182 MB | G1 uncommitted 674 MB at the first Remark, **0.85 s** into startup |
| + `-XX:MaxHeapFreeRatio=100` (or `-Xms = -Xmx`) | 718 MB | **265–269 MB** | Committed isn't resident: pages count only once touched |
| + `-XX:+AlwaysPreTouch` | 718 MB | **874 MB** | Now an undersized pod fails at deploy time; startup unchanged at this size |
| 65 %, pinned + pre-touched | 666 MB | 818 MB | The honest setting for 1 GiB with 159 MB idle non-heap |
| Consumer: Serial, `-Xms256m`, pre-touched, 512 MiB | 256 MB | 393 MB | Small pods: explicit sizes, as §5 says |

Three corrections and additions to this module:

* **§5's "Initial = max commits the heap" was wrong, and is corrected in place.** Spring's class loading crosses the Metaspace threshold, which starts a concurrent cycle. At its Remark pause, G1 shrinks the heap to what `MaxHeapFreeRatio` (default 70 %) allows. Keeping the heap takes `MaxHeapFreeRatio=100` or `-Xms`; making it resident takes `AlwaysPreTouch`.
* **The non-heap budget, itemized:** GC structures 51 MB, Metaspace 33, compiler arenas 24, code cache 17, CDS/AOT 14, symbols 8, class space 6, NMT 3, threads 2, for **159 MB at idle**. §3's ~165 MB came from a smaller app and a different profile, and it's the same order of magnitude.
* **`JAVA_TOOL_OPTIONS` reaches every JVM in the container, `jcmd` included** (`-Xmx1m` there killed it). App flags go in `JDK_JAVA_OPTIONS`, which only the `java` launcher reads. §5's snippet now uses it.

**Pinning changes monitoring.** A pinned, pre-touched heap sits at about 85 % of the limit from the first second, so "working set under 85 %" would fire on a healthy idle pod. The [7.8](08-Kubernetes-Platform-Blueprints-II-Kustomize-Guardrails-Consumers-Jobs-Canary.md) alert `JvmNonHeapHeadroomLow` measures non-heap against the space left above the heap instead, and its promtool test fires on a pod at 93 % of that headroom and stays silent at 51 %.

---

## Summary

| Topic | Key point | Evidence |
|---|---|---|
| Ergonomics | The JVM sizes heap, GC and threads from cgroup `memory.max`/`cpu.max`; CPU requests aren't read since JDK 19 | §0–§1 |
| Defaults (JDK 25) | Max heap 25 % of the limit; Serial GC at 1 CPU | §2.1–§2.2 |
| Thread pools | Follow the detected CPU count; pin it with `ActiveProcessorCount` | §2.3 |
| Memory map | Heap + non-heap (GC, Metaspace, code cache, CDS, threads, direct buffers) + margin | §3 |
| Four failures | Heap `OutOfMemoryError`; Metaspace/direct/native-thread `OutOfMemoryError`; the kernel's OOMKilled (exit 137, no stack trace); kubelet eviction | §4 |
| Sizing recipe | Guaranteed memory; 65–75 % for big pods, explicit `-Xmx` below 1 GiB; pinned + pre-touched (corrected) | §5, §9 |
| Measured profiles | `InitialRAMPercentage` undone at 0.85 s; committed ≠ resident; 159 MB idle non-heap | §9 (7.7 §4) |
| Flag delivery | `JDK_JAVA_OPTIONS`, not `JAVA_TOOL_OPTIONS` | §9 (7.7 §4.5) |
| Monitoring | With a pinned heap, alert on non-heap headroom (promtool-tested) | §9 (7.8 §6) |

**Next:** [7.2 Dockerfiles: multi-stage, distroless, layers, buildpacks, Jib →](02-Dockerfiles-Multistage-Distroless-Layers-Buildpacks-Jib.md)
