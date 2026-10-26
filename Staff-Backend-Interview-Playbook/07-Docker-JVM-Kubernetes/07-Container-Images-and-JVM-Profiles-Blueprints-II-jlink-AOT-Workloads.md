# 7.7 Container Images and JVM Profiles, Blueprints II: jlink Runtimes, the AOT Cache, Per-Workload Flags, and Heap Pinning

> **What was run:** the 7.5 order-service jar (Spring Boot 4.1.2) on **Temurin 25.0.4.1**, which ships **no `jmods/`** (JEP 493), on six runtimes built here with jdeps and jlink. For each runtime: the service was started and `/actuator/health` polled; a locale and charset probe was run; startup was timed 5× per variant; NMT and the process working set were read under container-sized ergonomics (`-XX:MaxRAM`, `-XX:ActiveProcessorCount`); and a G1 log was captured. Other checks: Paketo's `libjvm` jlink code was read, the distroless bases were inspected through the gcr.io registry API, the Dockerfile was linted with **hadolint 2.15.1**, and its jlink stage was replayed command for command.
>
> **Not run:** `docker build`. There is no Docker here, so build it once in CI before trusting it. The runtimes were built on **Windows x64**: Linux files differ in size, but the ratios and the behaviours are the same JDK code. There are no real cgroups either; 7.1 shows the JVM reading them, and here they were simulated with `MaxRAM`/`ActiveProcessorCount`. Timings are one laptop's.
>
> **Builds on:** [7.1 JVM in containers](01-JVM-in-Containers-cgroups-v2-Memory-OOMKilled.md), [7.2 Dockerfiles](02-Dockerfiles-Multistage-Distroless-Layers-Buildpacks-Jib.md), [7.5 blueprints](05-Production-Blueprints-application-yml-Dockerfile-Deployment.md), [1.4 AOT cache](../01-Build-Systems/04-Enterprise-Builds-OCI-Images-Annotation-Processors-Enforcer.md). **Next:** [7.8 platform blueprints](08-Kubernetes-Platform-Blueprints-II-Kustomize-Guardrails-Consumers-Jobs-Canary.md) puts these profiles into full manifests.

---

## 0. What this file proves 🔥

| Claim | Evidence |
|---|---|
| jdeps' module list starts the service but **silently** drops German/Japanese dates to English and loses the `IBM037` charset: service providers are invisible to static analysis | §1.2 |
| Dropping `java.desktop` (it "looks like AWT") breaks Spring: `NoClassDefFoundError: java/beans/PropertyEditorSupport` | §1.1 |
| **Paketo's default jlink** adds only `java.*` modules. The service starts, but `process.cpu.usage`, `system.cpu.usage` and `process.cpu.time` return **404**, and `-XX:StartFlightRecording` **kills the JVM at boot** | §1.3 |
| Without jmods, jlink **refuses** a JDK whose `conf/security/java.security` was edited, and can't cross-link (so a multi-arch image must run jlink on the target arch) | §1.4 |
| The AOT cache works on a jlink runtime, with or without a default CDS archive: **2.31 s → 1.29 s** | §2.1 |
| `--compress zip-6` makes the runtime smaller on disk but **bigger to pull** (45.7 vs 37.5 MB gzipped) and saves no startup time | §2.2 |
| ⚠️ **Correction to 7.1/7.5:** `InitialRAMPercentage=70` does **not** keep the heap committed. G1 gave 674 MB back at the first Remark, **0.85 s** into startup | §4.2 |
| Even a pinned heap (`-Xms`, `MinHeapSize` or `MaxHeapFreeRatio=100`) isn't **resident** until `AlwaysPreTouch`: working set 267 MB vs 880 MB | §4.3 |
| `JAVA_TOOL_OPTIONS` reaches **every** JVM in the container, `jcmd` included; `JDK_JAVA_OPTIONS` reaches only the `java` launcher | §4.5 |
| The Dockerfile blueprint lints clean, and its jlink stage, replayed, gives a 21-module runtime that passes all the checks above | §3 |

---

## 1. jdeps → jlink: what the tools see and what they miss 🔥

### 1.1 Six runtimes, one service

`jdeps --print-module-deps` on the flat extract of the jar (49 jars) printed 13 root modules:

```text
java.base,java.compiler,java.desktop,java.instrument,java.naming,java.net.http,java.prefs,
java.scripting,java.security.jgss,java.sql,jdk.jfr,jdk.management,jdk.unsupported
```

jlink resolves those to 19. Each runtime below was built, then the service was started on it:

| Runtime | How it was built | Modules | Disk | Service? | What's wrong |
|---|---|---|---|---|---|
| Full JDK | Temurin 25.0.4.1 | 70 | 291 MB | UP | Nothing, except 291 MB, `javac`, `jcmd` and friends in production |
| `rt-base` | `java.base` only | 1 | 50 MB | fails | `NoClassDefFoundError: java/beans/PropertyEditorSupport`, the first of many missing modules |
| `rt-nodesktop` | jdeps list **minus** `java.desktop` | 17 | 40 MB | **fails** | `NoClassDefFoundError: java/beans/PropertyEditorSupport`. Spring's type conversion uses `java.beans`, which lives in `java.desktop` |
| `rt-jdeps` | jdeps list as is | 19 | 52 MB | UP | Silent locale and charset gaps (§1.2) |
| `rt-paketo` | all `java.*` modules (Paketo's default, §1.3) | 22 | 64 MB | UP | No `jdk.*` at all: CPU metrics 404, JFR crash (§1.3) |
| **blueprint** | jdeps list **+ `jdk.localedata` + `jdk.charsets`**, `--include-locales=en,de,ja` | **21** | 87 MB | **UP** | Nothing found: locales, charsets, CPU metrics and JFR all work |

### 1.2 Service providers: the gaps jdeps can't see 🧊

Locale data and extended charsets are **service providers**. Nothing references them statically; the JDK looks them up at run time. A 15-line probe (`RuntimeCheck`: format a date in three locales, look up four charsets) on three runtimes:

| Probe | Full JDK | `rt-jdeps` | Blueprint |
|---|---|---|---|
| `EEEE d MMMM yyyy`, `en_US` | Sunday 25 October 2026 | Sunday 25 October 2026 | Sunday 25 October 2026 |
| same, `de_DE` | Sonntag 25 Oktober 2026 | **Sun 25 Oct 2026** | Sonntag 25 Oktober 2026 |
| same, `ja_JP` | 日曜日 25 10月 2026 | **Sun 25 Oct 2026** | 日曜日 25 10月 2026 |
| `Charset.forName("IBM037")` | IBM037 | **`UnsupportedCharsetException`** | IBM037 |
| UTF-8, ISO-8859-1, Shift_JIS | ok | ok | ok |

There is no exception, no warning and no log line. The German invoice just prints English month names. EBCDIC (IBM037) is what mainframe integrations speak. Rules:

* **Always add `jdk.localedata`** if anything formats for humans, and trim it with `--include-locales` (the blueprint keeps en, de, ja).
* **Add `jdk.charsets`** if any integration uses legacy encodings.
* Put this probe (or your own equivalent) **in the image's CI test**, because the failure mode is wrong output, not a crash.

### 1.3 Paketo's default jlink: `java.*` only 🧊

Paketo's Java buildpack can jlink for you (`BP_JVM_JLINK_ENABLED=true`). In [`libjvm/jlink.go`](https://github.com/paketo-buildpacks/libjvm/blob/main/jlink.go), when you don't pass `--add-modules`, `listJVMModules` runs `java --list-modules` and keeps every module whose name starts with `java.`. That's 22 modules and **no `jdk.*` module at all**. Built the same way here and started:

```text
== Paketo-default jlink (java.* only): UP: /actuator/health 200 after 2288 ms
  process.cpu.usage  404        ← micrometer-core needs jdk.management (com.sun.management.OperatingSystemMXBean)
  system.cpu.usage   404
  process.cpu.time   404
  jvm.memory.used    200
== blueprint runtime: all four 200

$ java -XX:StartFlightRecording -version          # on the java.*-only runtime
Error occurred during initialization of boot layer
java.lang.module.FindException: Module jdk.jfr not found       (exit 1)
```

`jdeps -summary` names the jars responsible: `micrometer-core → jdk.management` and `spring-core → jdk.unsupported`.

Think about what that means operationally. The CPU panels and CPU alerts go blank, and nothing errors. And the first time on-call adds `-XX:StartFlightRecording` to the pod's options during an incident, the pod **crash-loops**. With Paketo, pass the modules explicitly (§5).

### 1.4 JEP 493: linking without jmods

Temurin 25 is built with `--enable-linkable-runtime`, so it has no `jmods/` directory and jlink links from the JDK's own run-time image. [JEP 493](https://openjdk.org/jeps/493) lists the restrictions. Two of them change the Dockerfile:

1. **No cross-linking.** jlink can only produce a runtime for the platform it runs on. In a multi-arch build, the jlink stage must run on the **target** arch (§3.2).
2. **An edited `java.security` blocks jlink.** Verified on a copy of the JDK:

```text
$ echo "# hardened: tweak" >> jdk-mod/conf/security/java.security
$ jdk-mod/bin/jlink --add-modules java.base --output img-mod
Error: …\jdk-mod\conf\security\java.security has been modified          (exit 1)
```

Editing the **output** runtime's `conf/security/java.security` afterwards works. Better still, leave the file alone and point the JVM at an override file with `-Djava.security.properties=/app/security/override.properties`.

---

## 2. Startup and size: CDS, the AOT cache, and compression ⚡

### 2.1 Startup to a healthy `/actuator/health` (5 runs each, ms)

| Variant | Runs | Median |
|---|---|---|
| Full JDK (default CDS archive) | 2321 2319 2283 2315 2271 | **2315** |
| jlink, no CDS archive | 2284 2319 2284 2305 2343 | 2305 |
| jlink + `--generate-cds-archive` | 2311 2307 2290 2327 2323 | 2311 |
| Full JDK + AOT cache | 1295 1278 1292 1274 1474 | **1292** |
| jlink + CDS + AOT cache | 1310 1261 1297 1288 1270 | **1288** |
| jlink, **no** CDS + AOT cache, `-XX:AOTMode=on` | 1258 1273 1235 1285 1254 | **1258** |

What this shows:

* **jlink itself doesn't change startup.** A smaller runtime loads the same classes.
* **The default CDS archive matters for small programs, not this service.** jlink drops the JDK's CDS archive unless you pass `--generate-cds-archive` (`java -version` stops saying `sharing`). On the tiny probe program that cost **~220 ms** (969 vs 749 ms, mean of 5). For the Spring service it was within noise, because the app's own classes and bean work dominate.
* **The AOT cache is the lever:** −1.0 s on both the full JDK and jlink.
* **With `-XX:AOTCache`, the JVM opens only the AOT cache** (`-Xlog:aot` shows `Opened AOT cache …`). The default CDS archive isn't used, and training worked on a runtime that has none.

Every training run, on every runtime, logged the same 8 warnings: `class org/springframework/core/type/classreading/ClassFileMetadataReader … cannot be archived because it was not defined from …spring-core-7.0.10.jar as claimed`. These are spring-core's **multi-release** classes (`META-INF/versions/24/…`). The AOT cache skips them and the rest works. Don't let a CI log grep fail the build on them.

### 2.2 Size: on disk vs over the wire

Registries store and ship layers **gzipped**. The size that matters for pulls, cold starts and scale-out is the compressed one:

| Runtime | Disk | `tar.gz` |
|---|---|---|
| jdeps list, `--compress zip-6`, no CDS | 52 MB | 36.4 MB |
| `java.*` only, `--compress=1` (Paketo default) | 64 MB | 27.1 MB |
| final list + CDS, `--compress zip-6` | 82 MB | 45.7 MB |
| final list + CDS, **no** `--compress` | 115 MB | 37.5 MB |
| **Blueprint:** final list, no CDS, no `--compress` | **87 MB** | **29.7 MB** |
| The two CDS archives alone (`classes.jsa`, `classes_nocoops.jsa`) | 29.4 MB | 7.8 MB |
| AOT cache (`app.aot`) | 59 MB | 15.0 MB |
| For scale: `gcr.io/distroless/java25-debian13` (whole image) | — | 73.3 MB |
| `gcr.io/distroless/java-base-debian13` (glibc, CA certs, no JDK) | — | 11.2 MB |

`--compress zip-6` zips the `lib/modules` file (28 MB instead of 61 MB). zip-in-gzip then compresses worse than gzip alone, so the zipped runtime **pulls 8 MB more**. Startup was the same either way (2313 vs 2305 ms medians; 1292 vs 1289 ms with the AOT cache). The trade is pull bytes against node disk (containerd stores layers uncompressed), and the pull usually wins.

### 2.3 Decisions

* **No `--compress`**: smaller pulls, same startup.
* **No `--generate-cds-archive`** in the service image: the AOT cache supersedes it, and the job image gained nothing measurable from it. Add it for small CLIs that run without an AOT cache.
* **AOT cache in long-running services that scale** (APIs, KEDA consumers). **None in batch jobs**: one start per run, and a 15 MB-compressed layer that changes every commit.
* Net effect: about **11 + 30 MB** of base and runtime instead of 73 MB, so the JRE share of the image drops by more than half. The figures are from the Windows build, so check the Linux numbers in your registry.

---

## 3. ✅ The Dockerfile blueprint: one file, two targets, two arches 🔥

### 3.1 The file

```dockerfile
# syntax=docker/dockerfile:1.7
############################################################################################
# order-service on a jlink'd Java 25 runtime. One Dockerfile, two final targets:
#   docker buildx build --target service --platform linux/amd64,linux/arm64 -t order-service:1.4.0 .
#   docker buildx build --target job     --platform linux/amd64,linux/arm64 -t order-jobs:1.4.0 .
# `service` (APIs, Kafka consumers) carries an AOT cache; `job` (batch, migrations) doesn't.
############################################################################################
ARG JDK_IMAGE=eclipse-temurin:25.0.4.1_1-jdk-noble
ARG RUNTIME_BASE=gcr.io/distroless/java-base-debian13:nonroot@sha256:0d16df3717d190692a007d2a0f05a7367f47a35dfdb280016b186b4acf9727f0

############################################################################################
# 1. BUILD on the builder's own arch: bytecode is portable, so never compile under QEMU.
############################################################################################
FROM --platform=$BUILDPLATFORM ${JDK_IMAGE} AS build
WORKDIR /workspace
COPY .mvn/ .mvn/
COPY mvnw pom.xml ./
COPY order-api/ order-api/
COPY order-service/ order-service/
# Two extracts: --layers for the image, a flat one for jdeps (an empty layer such as
# snapshot-dependencies/ has no lib/ directory, and a 'lib/*' class-path glob on it breaks jdeps).
RUN --mount=type=cache,target=/root/.m2 \
    ./mvnw -B -ntp -DskipTests package \
 && cp order-service/target/order-service-*.jar /tmp/application.jar \
 && java -Djarmode=tools -jar /tmp/application.jar extract --layers --destination /extracted \
 && java -Djarmode=tools -jar /tmp/application.jar extract --destination /flat

############################################################################################
# 2. JRE on the TARGET arch. Temurin 25 has no jmods/ (JEP 493): jlink links from its own
#    run-time image, which can't cross-link, and refuses to run if conf/security/java.security
#    was edited. Harden the OUTPUT (/opt/jre/conf) or use -Djava.security.properties instead.
############################################################################################
FROM ${JDK_IMAGE} AS jre
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
COPY --from=build /flat /flat
# jdeps sees static references only. Add what it can't see:
#   jdk.localedata  non-English locale data (without it, de/ja dates silently print in English)
#   jdk.charsets    extended charsets such as IBM037 (EBCDIC)
# Its own list already brings java.desktop (Spring's java.beans), jdk.management (Micrometer CPU
# metrics) and jdk.jfr (Flight Recorder); the assertions below keep a later change from losing them.
# No --compress: the registry gzips the layer anyway, and zip-in-gzip pulls MORE bytes (7.7 section 2).
# No --generate-cds-archive: the service's AOT cache supersedes it, and for this app it saved nothing
# measurable without one (7.7 section 2). Add it back for small CLIs that run without an AOT cache.
RUN MODS="$(jdeps --multi-release 25 --ignore-missing-deps --print-module-deps \
              --class-path '/flat/lib/*' /flat/application.jar)" \
 && echo "jdeps: ${MODS}" \
 && jlink --add-modules "${MODS},jdk.localedata,jdk.charsets" \
          --include-locales=en,de,ja \
          --strip-debug --no-header-files --no-man-pages \
          --output /opt/jre \
 && for m in java.desktop jdk.management jdk.unsupported jdk.jfr jdk.localedata jdk.charsets; do \
      /opt/jre/bin/java --list-modules | grep -q "^${m}@" || { echo "missing module ${m}"; exit 1; }; \
    done \
 && /opt/jre/bin/java -version

############################################################################################
# 3. JOB target: batch and one-shot work. No AOT cache: it starts once per run, and the
#    cache would add a ~60 MB layer that changes on every commit.
############################################################################################
FROM ${RUNTIME_BASE} AS job
COPY --from=jre /opt/jre /opt/java
WORKDIR /app
# least → most frequently changing (each COPY is one layer)
COPY --from=build /extracted/dependencies/          ./
COPY --from=build /extracted/spring-boot-loader/    ./
COPY --from=build /extracted/snapshot-dependencies/ ./
COPY --from=build /extracted/application/           ./
USER 65532:65532
# JVM flags come from JDK_JAVA_OPTIONS in the pod spec (7.7 section 4). Exec form: java is PID 1.
ENTRYPOINT ["/opt/java/bin/java", "-jar", "/app/application.jar"]

############################################################################################
# 4. SERVICE target (the default, being last): adds the AOT cache.
#    Train in THIS stage: the cache is valid only for this JVM build, arch, classpath and GC.
#    The aot-training profile (7.5 section 2.1) starts without a database or broker.
############################################################################################
FROM job AS service
USER 0
RUN ["/opt/java/bin/java", "-XX:+UseG1GC", "-XX:AOTCacheOutput=/app/app.aot", \
     "-Dspring.profiles.active=aot-training", "-Dspring.context.exit=onRefresh", \
     "-jar", "/app/application.jar"]
USER 65532:65532
EXPOSE 8080
ENTRYPOINT ["/opt/java/bin/java", "-XX:AOTCache=/app/app.aot", "-jar", "/app/application.jar"]
```

The `.dockerignore` from [7.2 §4.1](02-Dockerfiles-Multistage-Distroless-Layers-Buildpacks-Jib.md) applies unchanged.

### 3.2 Why each decision 🧊

| Decision | Why |
|---|---|
| Build stage `--platform=$BUILDPLATFORM` | Maven and javac produce portable bytecode. Running them under QEMU emulation for arm64 is many times slower for no benefit |
| jlink stage on the **target** platform | JEP 493: no cross-linking without jmods. On an amd64 runner the arm64 jlink runs under QEMU; it's short, so that's acceptable |
| AOT training in the final stage, on the target platform | The cache is specific to the JVM build, the arch, the classpath and the GC (G1 vs ZGC was rejected in [7.2 §4.3](02-Dockerfiles-Multistage-Distroless-Layers-Buildpacks-Jib.md)). Under QEMU the training run is slow, so use **native arm64 runners** if it hurts |
| Base `distroless/java-base-debian13:nonroot` | glibc, CA certificates, tzdata, `LANG=C.UTF-8`, uid 65532, no shell and no JDK (11.2 MB). The JDK comes from our jlink stage, so there's exactly one Java in the image. Digest pinned |
| Flat extract for jdeps | The `--layers` extract leaves `snapshot-dependencies/` empty in a release build. A `snapshot-dependencies/lib/*` class-path glob then breaks jdeps: here it threw `InvalidPathException: Illegal char <*>` |
| Module assertions in the build | Someone will "tidy" the module list one day. The build fails instead of the CPU dashboards going blank |
| Bash with `pipefail` in the jre stage | `jdeps … \| …` failures must stop the build (hadolint DL4006). A failing jdeps also stops the `&&` chain before jlink runs with an empty list (seen in the replay) |
| Two targets, not two Dockerfiles | The build, jre and job stages are shared and cached. `service` is `job` plus the AOT layer |
| No `ENV JAVA_TOOL_OPTIONS` in the image | Flags belong to the workload and environment, so they go in the pod spec as `JDK_JAVA_OPTIONS` (§4.5) |
| Absolute `/opt/java/bin/java` in exec form | No shell, no `PATH` lookup surprises, and java is PID 1 and gets SIGTERM ([7.2 §5](02-Dockerfiles-Multistage-Distroless-Layers-Buildpacks-Jib.md)) |

### 3.3 What was checked, and what a linter doesn't catch

* **hadolint 2.15.1** (binary checked against the release's published SHA-256): the blueprint passes with **0 findings**. The first draft got DL4006 (a pipe without `pipefail`), which is why the jre stage sets `SHELL`.
* **The jre stage's RUN, replayed** with the same flags against this JDK: jdeps printed the 13 modules above, jlink produced 21 modules and all six assertions passed. The service started on the output with CPU metrics 200, JFR started, and the de/ja/IBM037 probe passed.
* **A naïve Dockerfile linted as a control:** `FROM eclipse-temurin:25`, an `apt-get install`, `COPY target/*.jar app.jar`, and a shell-form `ENTRYPOINT java -jar app.jar`. hadolint flagged the shell-form entrypoint (DL3025, the PID 1 problem) and the apt hygiene. It said **nothing** about the floating major tag, the full JDK in production, or running as root. A linter checks Dockerfile hygiene, not runtime posture. Enforce non-root and digest pinning in admission policy too ([7.8](08-Kubernetes-Platform-Blueprints-II-Kustomize-Guardrails-Consumers-Jobs-Canary.md)).

### 3.4 CI gates for the built image (not run here: no Docker)

```bash
# 1. The AOT cache matches the production flags. AOTMode=on fails instead of silently running without it (7.2 §4.3).
docker run --rm --entrypoint /opt/java/bin/java order-service:ci \
  -XX:+UseG1GC -XX:AOTMode=on -XX:AOTCache=/app/app.aot \
  -Dspring.profiles.active=aot-training -Dspring.context.exit=onRefresh -jar /app/application.jar

# 2. The runtime has what jdeps can't see (belt and braces for the in-build assertion).
docker run --rm --entrypoint /opt/java/bin/java order-service:ci --list-modules \
  | grep -cE '^jdk\.(localedata|charsets|management|jfr)@'          # expect 4

# 3. Both architectures were pushed.
docker buildx imagetools inspect registry.example.com/order-service:1.4.0 | grep -E 'Platform: +linux/(amd64|arm64)'

# 4. Lint, scan, sign: hadolint Dockerfile; your scanner; cosign/notation.
```

---

## 4. JVM flag profiles per workload, measured 🔥

### 4.1 The measurements

The order-service, started and given a little traffic. NMT committed memory and the process **working set** (on Windows, the analogue of RSS and of what a cgroup charges) were read through `jcmd`. One run each:

| # | Profile | Flags (beyond the simulated limits) | Max heap | NMT committed (heap) | Working set | Threads |
|---|---|---|---|---|---|---|
| 1 | Defaults, 1 GiB / 2 CPU | none | 256 MB | 184 MB (39) | 178 MB | 34 |
| 2 | API, `Initial = Max` | G1, `MaxRAMPercentage=70`, `InitialRAMPercentage=70` | 718 MB | 214 MB (**70**) | 182 MB | 34 |
| 3 | API + `MinHeapSize` | #2 + `-XX:MinHeapSize=718m` | 718 MB | 878 MB (718) | **267 MB** | 34 |
| 4 | API, `-Xms = -Xmx` | G1, `-Xms718m -Xmx718m` | 718 MB | 877 MB (718) | **269 MB** | 34 |
| 5 | API + `MaxHeapFreeRatio=100` | #2 + `-XX:MaxHeapFreeRatio=100` | 718 MB | 874 MB (718) | 265 MB | 34 |
| 6 | API pinned + pre-touched, 70 % | #5 + `-XX:+AlwaysPreTouch` | 718 MB | 877 MB (718) | **874 MB** | 34 |
| 7 | API pinned + pre-touched, 65 % | as #6 at 65 % | 666 MB | 822 MB (666) | 818 MB | 34 |
| 8 | Worker, 512 MiB / 1 CPU, C2 on | Serial, `-Xmx256m`, `-Xss256k` | 256 MB | 143 MB (45) | 166 MB | 28 |
| 9 | Worker, C1 only | #8 + `TieredStopAtLevel=1`, `ReservedCodeCacheSize=64m` | 256 MB | 124 MB (46) | 142 MB | 27 |
| 10 | Consumer pinned | #8 + `-Xms256m`, `AlwaysPreTouch`, `MaxDirectMemorySize=64m` | 256 MB | 361 MB (256) | 393 MB | 28 |
| 11 | Batch, 2 GiB / 2 CPU | Parallel, `MaxRAMPercentage=75` | 1536 MB | 234 MB (99) | 197 MB | 30 |

The non-heap breakdown for #6, the budget you size the limit with: GC data structures **51 MB** (about 7 % of a G1 heap), Metaspace 33, compiler arenas 24, code cache 17, CDS/AOT space 14, symbols 8, class space 6, NMT's own bookkeeping 3, thread stacks 2, internal 1. **Total 159 MB at idle.** Under load, add thread stacks (a 200-thread Tomcat pool), direct buffers up to `MaxDirectMemorySize`, glibc arenas and shared libraries outside NMT.

### 4.2 ⚠️ Correction: `InitialRAMPercentage` doesn't keep the heap 🧊

7.1 §5 and the 7.5 Deployment set `-XX:InitialRAMPercentage=70` equal to the max, with the reasoning that this "commits the heap at startup … an undersized pod fails at deploy time". Profile #2 says otherwise: **70 MB** committed, not 718. The G1 log shows when it was given back:

```text
[0.018s][info ][gc,init] Heap Initial Capacity: 718M
[0.829s][info ][gc     ] GC(1) Pause Young (Concurrent Start) (Metadata GC Threshold) 56M->11M(718M) 9.437ms
[0.846s][debug][gc,heap] GC(2) Uncommittable regions after shrink: 674
[0.846s][info ][gc     ] GC(2) Pause Remark 11M->11M(44M) 1.910ms
[0.910s][debug][gc,heap] Concurrent Uncommit Summary: 674M, 674 regions, 8.385ms
```

The mechanism is ordinary. Spring's startup class loading crosses the Metaspace GC threshold, which starts a concurrent mark cycle. At its Remark pause G1 resizes the heap to what `MaxHeapFreeRatio` (default 70 %) allows, and 11 MB live shrinks it to 44 MB. So **every** Spring Boot start erases `InitialRAMPercentage` within about a second. "Initial" means initial. The heap grows back under load, which is exactly the peak-traffic surprise the setting was meant to prevent.

To keep the heap committed, use any of these (profiles #3–#5 above):

| Option | Keeps | Note |
|---|---|---|
| `-XX:MaxHeapFreeRatio=100` | Whatever was committed (with `Initial = Max`: everything) | **Percentages only**: nothing to keep in sync with the pod limit. 4 Remark pauses, no shrink |
| `-Xms = -Xmx` | The whole heap | Absolute sizes: change them with the limit, in two places |
| `-XX:MinHeapSize=` | That floor | Same, also absolute |

### 4.3 Committed isn't resident: `AlwaysPreTouch` 🧊

Profiles #3–#5 committed 718 MB of heap, but the working set stayed at **~267 MB**. The OS hands out pages only when they are first touched. The cgroup charges touched pages, and that charge is what the OOM killer and the kubelet's `working_set` see. So "an undersized pod fails at deploy time" holds only with **`-XX:+AlwaysPreTouch`**, which writes every heap page at startup: working set **874 MB** (#6).

Cost: startup with 718 MB pre-touched was 2316 ms against 2310 ms without (medians of 3), so not measurable at this size. Pre-touch is parallelized over the GC threads, but on tens of GB it costs seconds; measure yours.

### 4.4 Pin or not? A decision, not a default

| Pin + pre-touch the heap when … | Leave it elastic when … |
|---|---|
| The pod is **Guaranteed** (`requests.memory = limits.memory`, as 7.1 recommends): the scheduler has reserved the memory anyway, so giving pages back to the node buys nothing | The pod is **Burstable** and you rely on bin-packing (requests below limits) |
| You want an undersized limit to **fail the rollout**, not the peak | You run many low-traffic replicas where idle footprint is the cost |
| You want a flat, predictable working set | — |

Pinning changes **what the memory alert means**. With a pinned heap the working set starts at heap + non-heap and stays flat (#6: 874 MB = **85 % of 1 GiB at idle**). 7.1's "peak under about 85 %" rule then fires on a healthy idle pod. So alert on **non-heap growth** instead (working set minus committed heap, or NMT), and size the pinned heap from the measured non-heap. At 1 GiB, 70 % leaves 150 MB above the 159 MB idle non-heap, less than the 128 MB direct-memory cap plus thread growth under load. **65 % (#7, 818 MB working set) or a 1.25 GiB limit** is the honest setting for this service.

### 4.5 `JAVA_TOOL_OPTIONS` vs `JDK_JAVA_OPTIONS` (verified)

```text
$ JAVA_TOOL_OPTIONS="-Xmx1m" jcmd -l
Picked up JAVA_TOOL_OPTIONS: -Xmx1m
Error occurred during initialization of VM
Initial heap size set to a larger value than the maximum heap size

$ JDK_JAVA_OPTIONS="-Xmx1m" jcmd -l
<pid> …  (lists the running JVMs: jcmd ignored the variable)

$ JDK_JAVA_OPTIONS="-XX:MaxRAM=1g -XX:MaxRAMPercentage=70" java -XX:+PrintFlagsFinal -version
NOTE: Picked up JDK_JAVA_OPTIONS: -XX:MaxRAM=1g -XX:MaxRAMPercentage=70
   size_t MaxHeapSize = 752877568
```

`JAVA_TOOL_OPTIONS` is read by the JVM itself, so **every** JVM started in the container gets it: `jcmd`, `jstack`, `jfr`, an exec probe that runs `java`. Put `-Xms700m -XX:+AlwaysPreTouch` in it and the next `jcmd` someone runs in the pod tries to commit and touch **another** 700 MB of heap in a memory-capped cgroup. `JDK_JAVA_OPTIONS` is read only by the `java` launcher. The blueprint image has no `jcmd` at all (`jdk.jcmd` isn't linked), but JDK-based images do.

* **Use `JDK_JAVA_OPTIONS`** for the app's flags. 7.5 used `JAVA_TOOL_OPTIONS`, which is mostly harmless there, because none of its flags **touches** memory up front. A second JVM would commit its heap, but the cgroup charges only touched pages (§4.3).
* It is still read by **any** `java` launch in the container (`kubectl exec … java -version` included). Diagnose from outside: Actuator `threaddump`/`heapdump`, JFR (`jdk.jfr` is linked), or an ephemeral debug container (`kubectl debug --target`), which doesn't inherit the pod's env.

### 4.6 The profiles as pod-spec fragments

The full manifests are in [7.8](08-Kubernetes-Platform-Blueprints-II-Kustomize-Guardrails-Consumers-Jobs-Canary.md), validated against Kubernetes v1.37.1.

**API** (latency-sensitive, Guaranteed, AOT image). Profile #7: working set 818 MB in 1 GiB, flat.

```yaml
resources:
  requests: { cpu: "1", memory: 1Gi }
  limits:   {           memory: 1Gi }           # no CPU limit: 7.4 §1.1
env:
  - name: JDK_JAVA_OPTIONS                       # launcher only; jcmd/jstack/jfr ignore it (§4.5)
    value: >-
      -XX:+UseG1GC -XX:ActiveProcessorCount=2
      -XX:MaxRAMPercentage=65 -XX:InitialRAMPercentage=65
      -XX:MaxHeapFreeRatio=100 -XX:+AlwaysPreTouch
      -XX:MaxDirectMemorySize=128m
      -XX:+ExitOnOutOfMemoryError -XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=/dumps
      -Xlog:gc*:file=/tmp/gc.log:time,uptime,level,tags:filecount=5,filesize=10m
  - name: MALLOC_ARENA_MAX
    value: "2"
```

**Kafka consumer** (KEDA-scaled, small, AOT image). Profile #10: working set 393 MB in 512 MiB. Below 1 GiB use explicit sizes, as 7.1 says.

```yaml
resources:
  requests: { cpu: 500m, memory: 512Mi }
  limits:   {            memory: 512Mi }
env:
  - name: JDK_JAVA_OPTIONS
    value: >-
      -XX:+UseSerialGC -XX:ActiveProcessorCount=1
      -Xms256m -Xmx256m -XX:+AlwaysPreTouch -Xss256k
      -XX:MaxDirectMemorySize=64m
      -XX:+ExitOnOutOfMemoryError
```

C1-only (`TieredStopAtLevel=1`, profile #9) saved only **24 MB** of working set against #8, and it gives up C2's peak throughput for good. That's fine for a CLI and wrong for a consumer that does real work, so it's not in the profile.

**Batch Job** (throughput, one run, `job` image without AOT). Profile #11: 197 MB working set at idle; size the limit from a real run's peak.

```yaml
resources:
  requests: { cpu: "2", memory: 2Gi }
  limits:   {           memory: 2Gi }
env:
  - name: JDK_JAVA_OPTIONS
    value: >-
      -XX:+UseParallelGC -XX:ActiveProcessorCount=2
      -XX:MaxRAMPercentage=75
      -XX:+ExitOnOutOfMemoryError -XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=/dumps
```

| Workload | GC | Heap sizing | Pin? | Image target | Why |
|---|---|---|---|---|---|
| API | G1 | 65 % at 1 GiB | Yes (+ pre-touch) | `service` | Pause-time goals, Guaranteed QoS, fail at rollout not at peak |
| Kafka consumer | Serial (1 CPU) | explicit 256 MB | Yes | `service` | Small pod: percentages mislead; AOT helps KEDA scale-from-zero |
| Batch | Parallel | 75 % at 2 GiB | No | `job` | Throughput over pauses; one start per run, no AOT |

---

## 5. Buildpacks and Jib with a custom runtime ⚡

**Paketo** (Boot's `spring-boot:build-image`). Turn jlink on **and pass the modules**. Per the `libjvm` README, custom `BP_JVM_JLINK_ARGS` **replace** the defaults entirely, and without `--add-modules` you get the `java.*`-only runtime from §1.3:

```xml
<plugin>
  <groupId>org.springframework.boot</groupId>
  <artifactId>spring-boot-maven-plugin</artifactId>
  <configuration>
    <image>
      <env>
        <BP_JVM_VERSION>25</BP_JVM_VERSION>
        <BP_JVM_JLINK_ENABLED>true</BP_JVM_JLINK_ENABLED>
        <BP_JVM_JLINK_ARGS>--no-man-pages --no-header-files --strip-debug --add-modules java.base,java.compiler,java.desktop,java.instrument,java.naming,java.net.http,java.prefs,java.scripting,java.security.jgss,java.sql,jdk.jfr,jdk.management,jdk.unsupported,jdk.localedata,jdk.charsets --include-locales=en,de,ja</BP_JVM_JLINK_ARGS>
      </env>
    </image>
  </configuration>
</plugin>
```

This wasn't run here (no Docker). Generate the module list with jdeps in CI, rather than typing it, and run the §1.2 probe against the built image.

**Jib** can't run jlink or an AOT training run. It layers your jar onto a base image. Build the jlink runtime (the Dockerfile's `jre` stage) into a **base image of your own**, point `jib.from.image` at it by digest, and accept that Jib images have no AOT cache. Use Jib where build speed and no-daemon builds matter more than startup.

---

## 6. ❌ Naïve vs ✅ production-hardened

| ❌ Naïve | ✅ Hardened |
|---|---|
| jlink with jdeps' list "because the tests pass" | jdeps list **+ `jdk.localedata` + `jdk.charsets`**, a locale/charset probe in CI (§1.2) |
| Drop `java.desktop`, "we have no GUI" | Keep it: Spring needs `java.beans` (§1.1) |
| `BP_JVM_JLINK_ENABLED=true` and done | Explicit `--add-modules` including `jdk.management`, `jdk.jfr`, `jdk.unsupported` (§1.3) |
| Module list maintained by hand | Generated by jdeps in the build; assertions fail the build if a needed module disappears |
| Harden `java.security` in the JDK, then jlink | jlink first, then the override file (`-Djava.security.properties`) (§1.4) |
| `--compress zip-6` "for the smallest image" | No `--compress`: 8 MB less to pull, same startup (§2.2) |
| `--generate-cds-archive` everywhere | Only where no AOT cache is used and it measurably helps (§2.1) |
| AOT training on the build stage or the laptop | In the final stage, on the target arch, with the production GC |
| Whole build under QEMU for arm64 | Build on `$BUILDPLATFORM`; jlink and training on the target |
| `InitialRAMPercentage = MaxRAMPercentage` "commits the heap" | G1 shrank it at 0.85 s. Use `MaxHeapFreeRatio=100` (or `-Xms`) **+ `AlwaysPreTouch`** (§4.2–4.3) |
| Pinned heap + an "85 % of limit" working-set alert | Alert on non-heap growth; size the heap from the measured non-heap (§4.4) |
| Memory-committing flags in `JAVA_TOOL_OPTIONS` | `JDK_JAVA_OPTIONS` (§4.5) |
| One flag set for every workload | API (G1, pinned), consumer (Serial, explicit 256 MB), batch (Parallel, elastic) (§4.6) |
| "hadolint is green, so the image is safe" | Lint + admission policy for non-root, digests and limits (§3.3) |

---

## 7. Bar-raiser Q&A 🔥

🎤 *"We cut the image from 120 MB to 60 MB with jdeps and jlink. All tests pass."*

🔍 **What does jdeps not see, and how would you know?**

<details><summary>🛡️ Defense</summary>

Anything loaded through `ServiceLoader` or reflection by name, because jdeps reads bytecode references. The two that bite are locale data and extended charsets. On jdeps' own list the service started, then printed German and Japanese dates in English and threw `UnsupportedCharsetException` for IBM037. There was no error at startup and no log line. Tests pass because they run on a full JDK, or only in `en_US`. So I'd add `jdk.localedata` (trimmed with `--include-locales`) and `jdk.charsets`, put a 15-line locale/charset probe in the image's CI, and add in-build assertions for the modules we know we need. Then I'd ask what else is loaded by name in our codebase: JDBC drivers and JNDI providers are the usual suspects.
</details>

🔍 **Why not just turn on Paketo's jlink?**

<details><summary>🛡️ Defense</summary>

You can, but read what the default does. `libjvm`'s `listJVMModules` keeps only modules named `java.*`. I built that runtime: the service came up, and then `process.cpu.usage`, `system.cpu.usage` and `process.cpu.time` were 404 because Micrometer needs `jdk.management`. `-XX:StartFlightRecording` failed at boot with `Module jdk.jfr not found`. The first symptom is a blank CPU dashboard, the second a crash-looping pod during an incident. Paketo is fine with an explicit `--add-modules` in `BP_JVM_JLINK_ARGS`; custom args replace the defaults completely.
</details>

🔍 **Your pods set `InitialRAMPercentage` equal to `MaxRAMPercentage` so an undersized pod fails at deploy time. Does it?**

<details><summary>🛡️ Defense</summary>

No, and I had that wrong in an earlier blueprint. G1 commits 718 MB at startup, but Spring's class loading crosses the Metaspace threshold, a concurrent cycle starts, and at its Remark pause G1 shrinks to what `MaxHeapFreeRatio` allows. In my log it uncommitted 674 MB at 0.85 s, leaving 70 MB. The heap regrows under load, which is exactly the surprise we wanted to avoid. Two fixes are needed together. First, stop the shrink: `-XX:MaxHeapFreeRatio=100` keeps it percentage-only, or use `-Xms = -Xmx`. Second, make it resident with `-XX:+AlwaysPreTouch`, because committed pages aren't charged until touched (267 MB vs 874 MB working set). Pre-touching 718 MB cost no measurable startup.
</details>

🔍 **So should every service pin and pre-touch its heap?**

<details><summary>🛡️ Defense</summary>

No, it depends on the QoS class. For Guaranteed pods (`requests = limits`), the scheduler has already reserved the memory. Giving heap pages back to the node buys nothing, while pinning buys a flat working set and a rollout that fails instead of a 3 a.m. OOMKill. For Burstable pods packed on requests, an elastic heap is the point. Pinning also changes monitoring: the working set sits at about 85 % from the first second, so I alert on non-heap growth instead. And I size the heap from measured non-heap: 159 MB idle here, so 65 % at 1 GiB, not 70 %.
</details>

🔍 **We're adding arm64 nodes. What changes in the image build?**

<details><summary>🛡️ Defense</summary>

Three things. The Maven build stays on `$BUILDPLATFORM`, since bytecode is portable and compiling under QEMU is pointless. jlink must run on the target arch, because Temurin 25 has no jmods and JEP 493 says linking from the run-time image can't cross-link. And the AOT cache must be trained on the target arch, because it's tied to the JVM build. Both of those run under emulation on an amd64 runner. jlink is short; the training run is a full Spring start under QEMU, so I'd move to native arm64 runners if build time hurts. CI then checks that both platforms are in the manifest list and runs the `AOTMode=on` smoke test per arch.
</details>

🔍 **Why is your jlink output uncompressed? Smaller is better.**

<details><summary>🛡️ Defense</summary>

Smaller where? `--compress zip-6` shrank the runtime on disk (115 → 82 MB with CDS), but registries gzip layers and zip-in-gzip compresses worse. The zipped runtime was 45.7 MB to pull against 37.5 MB unzipped. Startup was the same with and without (2.31 s; 1.29 s with the AOT cache). Pull bytes are what scale-out and node cold starts pay for. Node disk is cheaper, and containerd stores layers uncompressed anyway. I measured that before choosing, and I'd re-measure with zstd layers.
</details>

🔍 **Security wants `java.security` hardened in the image. Where does that go?**

<details><summary>🛡️ Defense</summary>

Not in the JDK before jlink: without jmods, jlink refuses to link from a JDK whose `conf/security/java.security` was edited (verified: `java.security has been modified`, exit 1). That restriction exists so an insecure ad-hoc config can't propagate into new runtimes. Either edit the jlink output's `conf/security/java.security` in the jre stage, or, cleaner, ship an override file and start with `-Djava.security.properties=/app/security/override.properties`. The override is visible in the repo, reviewable and per-environment.
</details>

🔍 **On-call wants a thread dump from a production pod. The image has no shell and no `jcmd`.**

<details><summary>🛡️ Defense</summary>

That's by design. The options, in order: Actuator's `threaddump` endpoint on the management port; JFR, since `jdk.jfr` is linked (`jcmd`-free via `-XX:StartFlightRecording` with a dump on exit, or JFR streaming); or an ephemeral container (`kubectl debug -it pod/x --image=<jdk image> --target=app`) running as the same uid. It shares the process namespace and doesn't inherit the pod's env, so it doesn't pick up the app's `JDK_JAVA_OPTIONS`. That's also why the flags live in `JDK_JAVA_OPTIONS` and not `JAVA_TOOL_OPTIONS`: the latter reaches every JVM, and a `jcmd` with the app's `-Xms…/AlwaysPreTouch` would try to commit another heap inside the cgroup.
</details>

---

## 8. Source to read

* [JEP 493: Linking Run-Time Images without JMODs](https://openjdk.org/jeps/493): the Restrictions section.
* [JEP 483](https://openjdk.org/jeps/483), [JEP 514](https://openjdk.org/jeps/514), [JEP 515](https://openjdk.org/jeps/515): AOT class loading and linking, the one-step `AOTCacheOutput`, and AOT method profiling.
* The [`java` command](https://docs.oracle.com/en/java/javase/25/docs/specs/man/java.html) (`JDK_JAVA_OPTIONS`, `MaxHeapFreeRatio`, `AlwaysPreTouch`), [`jlink`](https://docs.oracle.com/en/java/javase/25/docs/specs/man/jlink.html) and [`jdeps`](https://docs.oracle.com/en/java/javase/25/docs/specs/man/jdeps.html).
* Paketo [`libjvm/jlink.go`](https://github.com/paketo-buildpacks/libjvm/blob/main/jlink.go): `listJVMModules`, the `java.*`-only default.
* [GoogleContainerTools/distroless](https://github.com/GoogleContainerTools/distroless): the `java-base` image.
* [hadolint](https://github.com/hadolint/hadolint): the rule list (DL3025, DL4006).

---

## 9. Interview soundbites

* "jdeps sees bytecode, not `ServiceLoader`. On its own list my service printed German dates in English and lost EBCDIC, silently. I add `jdk.localedata` and `jdk.charsets` and assert the modules in the build."
* "Paketo's default jlink is `java.*` only. My CPU metrics went 404, and adding JFR crashed the JVM at boot."
* "`InitialRAMPercentage` is initial. G1 gave 674 MB back 0.85 s into a Spring start. Pinning needs `MaxHeapFreeRatio=100` or `-Xms`, and only `AlwaysPreTouch` makes it resident."
* "Pin the heap in Guaranteed pods, then alert on non-heap. The working set sits at 85 % from the first second by design."
* "jlink's zip compression made my layer 8 MB **bigger** to pull. Measure what the registry ships, not what `du` says."
* "Without jmods, jlink can't cross-link, so in a multi-arch build only jlink and AOT training run on the target arch. Maven doesn't."
* "App flags go in `JDK_JAVA_OPTIONS`: `JAVA_TOOL_OPTIONS` also hits `jcmd`, and `-Xmx1m` there killed it."

---

## Summary

| Topic | Key point | Evidence |
|---|---|---|
| jdeps limits | Service providers are invisible: add `jdk.localedata` + `jdk.charsets`; keep `java.desktop` | §1.1–1.2 |
| Paketo jlink | Default = `java.*` only: CPU metrics 404, JFR boot failure; pass `--add-modules` | §1.3, §5 |
| JEP 493 | No cross-link; an edited `java.security` blocks jlink | §1.4 |
| Startup | jlink ±0; CDS ±0 for this service (−220 ms for a tiny program); AOT cache −1.0 s, also on jlink | §2.1 |
| Size | No `--compress`: 29.7 MB gzipped runtime vs 45.7 MB; drop CDS when using AOT | §2.2–2.3 |
| Dockerfile | One file, `job` and `service` targets; build on `$BUILDPLATFORM`, jlink + train on target; lint-clean | §3 |
| Heap pinning | ⚠️ `InitialRAMPercentage` is undone at the first Remark; `MaxHeapFreeRatio=100`/`-Xms` + `AlwaysPreTouch` | §4.2–4.3 |
| Pin decision | Guaranteed → pin, alert on non-heap; Burstable → elastic | §4.4 |
| Option env vars | `JDK_JAVA_OPTIONS` (launcher only), not `JAVA_TOOL_OPTIONS` (every JVM) | §4.5 |
| Profiles | API G1 65 % pinned; consumer Serial 256 MB pinned; batch Parallel 75 % | §4.6 |

**Next:** [7.8 Kubernetes platform blueprints II: Kustomize, guardrails, consumers, jobs, canary →](08-Kubernetes-Platform-Blueprints-II-Kustomize-Guardrails-Consumers-Jobs-Canary.md)
