# 7.2 Container Images for Spring Boot: Multi-Stage Dockerfiles, Layers, Distroless, PID 1, AOT Cache, Buildpacks and Jib

> **Verified stack:** Spring Boot **4.1.2** (`-Djarmode=tools`), Temurin **25.0.4.1**, the Pillar 1 blueprint service (`order-service-1.4.0-SNAPSHOT.jar`, web + actuator + validation + a sibling `order-api` module).
>
> **What was run:** the layer listing and both extract modes, merging the layers exactly as the Dockerfile's `COPY` steps do and starting the result with `java -jar` (healthy, started in 1.6 s), the AOT cache training run (in [1.4 §2](../01-Build-Systems/04-Enterprise-Builds-OCI-Images-Annotation-Processors-Enforcer.md)), and what happens when that cache is used with a different GC (§4.3). Base-image tags, compressed sizes, user, entrypoint and digest were read from the **Docker Hub and gcr.io registry APIs** on 2026-10-25. **Not run:** `docker build` itself. There is no Docker on this machine, so build the Dockerfile once in CI before trusting it.
>
> **Builds on:** [1.4 OCI images, buildpacks, Jib, AOT cache](../01-Build-Systems/04-Enterprise-Builds-OCI-Images-Annotation-Processors-Enforcer.md). **Related:** CKAD kit [container images](../../CKAD-Exam-Prep/01-Application-Design-and-Build/01-container-images.md), [security contexts](../../CKAD-Exam-Prep/04-Application-Environment-Configuration-and-Security/07-security-contexts-and-capabilities.md).

---

## 0. First principles: an image is a stack of cached tarballs 🔥

An OCI image is an ordered list of **layers** (content-addressed tarballs) plus a config (user, entrypoint, env). Four consequences drive every Dockerfile decision:

1. **Cache invalidation is positional.** When a layer's inputs change, that layer **and every layer after it** is rebuilt and re-pushed. Order layers from *rarely changes* to *changes every commit*.
2. **Every layer ships everywhere.** Each byte is stored in the registry, pulled by every node, and scanned. Build tools, compilers and shells in the runtime image are size **and** attack surface.
3. **The config is runtime behavior.** `USER`, `ENTRYPOINT` form, and the working directory decide who the process runs as and whether it receives `SIGTERM`.
4. **Reproducibility** (same inputs → same digest) needs pinned bases and fixed timestamps. That's covered in [1.4](../01-Build-Systems/04-Enterprise-Builds-OCI-Images-Annotation-Processors-Enforcer.md).

---

## 1. ❌ The naïve Dockerfile, line by line

```dockerfile
FROM eclipse-temurin:25                          # ❶ floating tag, full JDK in production
COPY . /src                                      # ❷ whole repo incl. .git, target/, maybe .env
RUN cd /src && ./mvnw package                    # ❸ build tools + sources + ~/.m2 in the final image
ENTRYPOINT java -jar /src/target/app.jar         # ❹ SHELL form: /bin/sh is PID 1
                                                 # ❺ no USER: runs as root
```

| # | Problem | Consequence |
|---|---|---|
| ❶ | Floating tag, JDK instead of JRE | Non-reproducible; bigger image; compiler and tools available to an attacker |
| ❷ | No `.dockerignore`, everything copied in one layer | Any file change invalidates the build; secrets in `.env` end up in a layer **forever** |
| ❸ | Build in the runtime image | Hundreds of MB of Maven repo and sources shipped and scanned |
| ❹ | Shell-form entrypoint | `sh -c` is PID 1 and **doesn't forward `SIGTERM`** to Java. No graceful shutdown; Kubernetes `SIGKILL`s after the grace period |
| ❺ | Root user | A container escape or RCE starts as uid 0 |
| — | One 24 MB fat jar layer | Every commit re-pushes all dependencies |

---

## 2. Layers: what changes per commit (verified) ⚡

Boot's jar carries `BOOT-INF/layers.idx`. `jarmode=tools` splits it.

**Output (verified, Boot 4.1.2):**

```text
$ java -Djarmode=tools -jar application.jar list-layers
dependencies
spring-boot-loader
snapshot-dependencies
application

$ java -Djarmode=tools -jar application.jar extract --layers --launcher --destination extracted
  extracted/application/        1016K  files=131
  extracted/dependencies/         23M  files=48
  extracted/snapshot-dependencies/      0  files=0
  extracted/spring-boot-loader/   637K  files=99
```

A normal commit changes only **`application`** (about 1 MB, including the sibling `order-api` module jar, which lands here because it changes with your code). The 23 MB of third-party jars are re-pushed only when a dependency version changes.

For the Dockerfile use **`extract --layers` without `--launcher`**. It produces a thin `application.jar` whose manifest lists `lib/…` jars, the layout CDS and the AOT cache require:

```text
$ java -Djarmode=tools -jar application.jar extract --layers --destination plain
plain/application/application.jar   plain/application/lib   plain/dependencies/lib   plain/spring-boot-loader   …

after merging the four directories into one (what the COPY steps do):
  application.jar  lib/ (49 jars)
  Main-Class: com.acme.order.service.OrderServiceApplication
  Class-Path: lib/HdrHistogram-2.2.2.jar lib/classmate-1.7.3.jar lib/commo…
  health: {"groups":["liveness","readiness"],"status":"UP"}
  Started OrderServiceApplication in 1.599 seconds (process running for 1.872)
```

---

## 3. Choosing a base image ⚡

Compressed linux/amd64 sizes from the registries (2026-10-25):

| Base | Compressed | Shell / package manager | Default user | Notes |
|---|---|---|---|---|
| `eclipse-temurin:25.0.4.1_1-jdk-noble` | 140.0 MB | yes / apt | root | Build stage only |
| `eclipse-temurin:25.0.4.1_1-jre-noble` | 104.3 MB | yes / apt | root | Easy to debug; add a user |
| `eclipse-temurin:25.0.4.1_1-jre-alpine` | 75.5 MB | yes / apk | root | **musl** libc: different DNS resolver and allocator behavior; test before adopting |
| `eclipse-temurin:25.0.4.1_1-jre-ubi10-minimal` | 135.7 MB | microdnf | root | Red Hat ecosystem / compliance |
| `gcr.io/distroless/java25-debian13:nonroot` | 73.3 MB (34 layers) | **no / no** | **65532** | Image config: `Entrypoint ["/usr/bin/java","-jar"]`, `JAVA_VERSION=25.0.5`, `WorkingDir /home/nonroot` |
| Paketo `builder-noble-java-tiny` (buildpacks) | — | no | non-root | Boot 4.1.2's default builder ([1.4 §1.1](../01-Build-Systems/04-Enterprise-Builds-OCI-Images-Annotation-Processors-Enforcer.md)) |

Distroless has no shell, so you can't `kubectl exec … sh`. Debug with **ephemeral containers** (`kubectl debug -it pod/x --image=busybox --target=app`), or use the `:debug-nonroot` tag in non-production.

Note the version column. The distroless image ships **25.0.5**, a different JVM build from the Temurin **25.0.4.1** JDK in the build stage. That matters for the AOT cache (§4.2).

---

## 4. ✅ The production Dockerfile 🔥

### 4.1 The file

```dockerfile
# syntax=docker/dockerfile:1.7
############################################################################################
# 1. BUILD: full JDK, Maven wrapper, dependency cache in a BuildKit cache mount
############################################################################################
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

############################################################################################
# 2. RUNTIME: distroless Java 25, non-root (uid 65532), no shell, no package manager.
#    Pin by digest; the digest below is nonroot as of 2026-10-25, so refresh it via your update bot.
############################################################################################
FROM gcr.io/distroless/java25-debian13:nonroot@sha256:5d3177252775d4b01603470fe21c015393019089904f68724bd37242e4bc6e6d
WORKDIR /app
# least → most frequently changing (each COPY is one layer)
COPY --from=build /extracted/dependencies/          ./
COPY --from=build /extracted/spring-boot-loader/    ./
COPY --from=build /extracted/snapshot-dependencies/ ./
COPY --from=build /extracted/application/           ./

# 3. AOT cache training run, inside THIS image so it's the same JVM build that will read it.
#    Exec form: distroless has no /bin/sh. Root only so it can write into /app; the app runs as 65532.
USER 0
#    Use the SAME GC as production (7.5 sets -XX:+UseG1GC): a cache trained with G1 is rejected under ZGC (§4.3).
RUN ["/usr/bin/java", "-XX:+UseG1GC", "-XX:AOTCacheOutput=/app/app.aot", \
     "-Dspring.profiles.active=aot-training", "-Dspring.context.exit=onRefresh", \
     "-jar", "/app/application.jar"]
USER 65532:65532

EXPOSE 8080
# Exec form: java is PID 1 and receives SIGTERM directly. JVM flags come from JDK_JAVA_OPTIONS (7.7 section 4.5),
# so they can be tuned per environment without rebuilding.
ENTRYPOINT ["/usr/bin/java", "-XX:AOTCache=/app/app.aot", "-jar", "/app/application.jar"]
```

`.dockerignore` (keeps the build context small and secrets out):

```text
**/target/
**/build/
.git
.idea
*.iml
**/*.log
.env
**/*.pem
```

### 4.2 Why each decision 🧊

| Decision | Reason |
|---|---|
| Multi-stage | Maven, the JDK, sources and `~/.m2` never reach the runtime image |
| `--mount=type=cache` for `~/.m2` | Dependencies survive between builds without being baked into a layer (`dependency:go-offline` misses plugin and late-resolved artifacts) |
| Four `COPY` layers in change order | A code change re-pushes ~1 MB of `application`, not 24 MB |
| App files owned by root, process runs as 65532 | The running process **can't modify its own code** |
| AOT training **in the runtime stage** | The cache is valid only for the same JVM build and classpath. Training with the build stage's Temurin 25.0.4.1 and running on distroless 25.0.5 would get the cache rejected at startup (a warning, then no speed-up) |
| `aot-training` profile | The training run needs the context to *start* without a database, Kafka or secrets: disable Flyway, listener auto-startup and JDBC metadata access (below) |
| Exec-form `ENTRYPOINT` | Java is PID 1 and gets `SIGTERM`; graceful shutdown works ([7.3](03-Kubernetes-Probes-and-Graceful-Shutdown.md)) |
| No `HEALTHCHECK` | Kubernetes ignores it; probes live in the Deployment |
| Digest pin | Reproducible builds; tags move |

`application-aot-training.yml`:

```yaml
spring:
  flyway.enabled: false
  kafka.listener.auto-startup: false
  jpa.properties.hibernate.boot.allow_jdbc_metadata_access: false   # don't open a JDBC connection to detect the dialect
  datasource.hikari.initialization-fail-timeout: -1                 # don't fail if the pool can't connect at startup
```

### 4.3 The AOT cache fails *silently* when flags don't match 🧊

The cache records the JVM settings it was created with. **Output (verified, Temurin 25.0.4.1, a cache trained with the default G1, then run with other collectors, `-Xlog:aot=info`):**

```text
== run with -XX:+UseSerialGC / -XX:+UseParallelGC
[info][aot] Opened AOT cache app.aot.
[info][aot] The AOT cache was created with UseCompressedOops = 1, UseCompressedClassPointers = 1, UseCompactObjectHeaders = 0
== run with -XX:+UseZGC
[info][aot] The AOT cache was created with UseCompressedOops = 1, UseCompressedClassPointers = 1, UseCompactObjectHeaders = 0
[warning][aot] Unable to use AOT cache.
            The saved state of UseCompressedOops and UseCompressedClassPointers is different from runtime, CDS will be disabled.

default AOTMode (auto):  the app still started, exit=0, just WITHOUT the cache
-XX:AOTMode=on:          "Error occurred during initialization of VM / Unable to use AOT cache.", exit=1
```

ZGC doesn't use compressed oops, so a G1-trained cache is useless to it. The same applies to `-XX:+UseCompactObjectHeaders` and to heaps over 32 GB (no compressed oops). And by default the JVM **quietly runs without the cache**. Two rules follow: train with the production GC and object-header flags, and in CI start the built image once with **`-XX:AOTMode=on`** so a mismatch fails the pipeline instead of silently costing you the startup gain.

### 4.4 The AOT trade-off nobody mentions 🧊

The AOT cache cut startup from 1.92 s to 1.01 s in [1.4](../01-Build-Systems/04-Enterprise-Builds-OCI-Images-Annotation-Processors-Enforcer.md), but the cache file was **62,914,560 bytes**, and it depends on the classpath, so **it changes on every commit**. Every deploy now pushes and pulls a ~60 MB layer instead of ~1 MB. That's worth it when startup time matters (scale-from-zero, fast rollouts, aggressive HPA). It's not worth it for a service that starts twice a week. Measure both sides.

---

## 5. PID 1 and signals 🔥

```text
ENTRYPOINT java -jar app.jar          → /bin/sh -c "java -jar app.jar"   sh = PID 1, java = child
                                         SIGTERM goes to sh; sh doesn't forward it, java never hears it
                                         → kubelet waits terminationGracePeriodSeconds → SIGKILL (exit 137)

ENTRYPOINT ["java","-jar","app.jar"]  → java = PID 1, receives SIGTERM, runs shutdown hooks → graceful
```

* If you need a wrapper script, end it with **`exec java …`** so Java replaces the shell.
* PID 1 has special signal semantics: the kernel doesn't apply default actions for signals without a handler. The JVM installs handlers for `SIGTERM`/`SIGINT`, so a Java PID 1 is fine. If the container runs a process tree (a script that starts helpers), use a minimal init such as `tini` to forward signals and reap zombie children.
* `SIGKILL` (and the kernel OOM killer) can't be caught: no shutdown hooks, no log flush, no graceful anything.

---

## 6. Runtime security in the pod spec ⚡

The image sets the user; the pod spec enforces the rest:

```yaml
securityContext:                       # pod level
  runAsNonRoot: true
  runAsUser: 65532
  fsGroup: 65532
  seccompProfile: { type: RuntimeDefault }
containers:
  - name: app
    securityContext:
      allowPrivilegeEscalation: false
      readOnlyRootFilesystem: true
      capabilities: { drop: ["ALL"] }
    volumeMounts:
      - { name: tmp, mountPath: /tmp }   # Tomcat work dirs, JVM hsperfdata, multipart uploads need a writable /tmp
volumes:
  - name: tmp
    emptyDir: { sizeLimit: 256Mi }
```

Supply chain: build-time secrets via `RUN --mount=type=secret` (never `COPY`/`ARG`), an SBOM (CycloneDX via the Maven/Gradle plugin; Boot can serve it at `/actuator/sbom`), image scanning in CI, and signing (for example `cosign`), with admission policies that only admit signed images.

---

## 7. Dockerfile vs buildpacks vs Jib

| | Dockerfile + `jarmode=tools` | Buildpacks (`spring-boot:build-image`) | Jib |
|---|---|---|---|
| Needs a Docker daemon | Yes (or BuildKit/Buildah) | Yes | **No** (pushes directly) |
| Control | Total | Opinionated, via env vars | Medium (plugin config) |
| Layering | You write it | Automatic | Automatic (deps / resources / classes) |
| Non-root by default | If you do it | Yes | **No**: verified `User: None` with a Temurin base ([1.4 §1.2](../01-Build-Systems/04-Enterprise-Builds-OCI-Images-Annotation-Processors-Enforcer.md)) |
| Reproducible | With pinned bases + care | Yes | Yes (verified `created: 1970-01-01`) |
| JVM memory tuning | You set flags | Memory calculator sets `-Xmx`, metaspace, stack from the limit | You set flags |
| AOT cache / CDS | You add the training run | Supported through buildpack environment options (see the Boot reference, "Efficient deployments") | Not built in |
| Best for | Platform teams with standards | Teams that want secure defaults with no Dockerfile | Fast CI without Docker |

---

## 8. ❌ Naïve vs ✅ production-hardened

| ❌ Naïve | ✅ Production-hardened |
|---|---|
| `FROM eclipse-temurin:25` | Version **and digest** pinned, updated by a bot |
| Build in the final image | Multi-stage; JRE or distroless runtime |
| Fat jar in one layer | Four layers via `jarmode=tools extract --layers` |
| Shell-form `ENTRYPOINT` / wrapper without `exec` | Exec form; Java is PID 1 |
| Root user | uid 65532, `runAsNonRoot`, read-only root FS, capabilities dropped |
| JVM flags baked into the image | `JDK_JAVA_OPTIONS` from the Deployment (`JAVA_TOOL_OPTIONS` also reaches `jcmd`: [7.7 §4.5](07-Container-Images-and-JVM-Profiles-Blueprints-II-jlink-AOT-Workloads.md)) |
| `COPY . .` without `.dockerignore` | Explicit copies + `.dockerignore`; secrets via `--mount=type=secret` |
| AOT cache built on a laptop or in the build stage | Trained in the runtime image, with a training profile |
| `HEALTHCHECK curl …` | Kubernetes probes (distroless has no curl anyway) |
| No SBOM, no scan, no signature | SBOM + scan gate + signed images + admission policy |

---

## 9. Source to read

| Repo | Path | What to look for |
|---|---|---|
| [spring-projects/spring-boot](https://github.com/spring-projects/spring-boot) | `loader/spring-boot-jarmode-tools/src/main/java/org/springframework/boot/jarmode/tools/ExtractCommand.java` | How `--layers` and the thin-jar layout are produced |
| [GoogleContainerTools/distroless](https://github.com/GoogleContainerTools/distroless) | `java/README.md` | What's in the Java images, users, tags |
| [GoogleContainerTools/jib](https://github.com/GoogleContainerTools/jib) | `jib-core/src/main/java/com/google/cloud/tools/jib/api/JibContainerBuilder.java` | Layering and reproducibility without a daemon |
| [paketo-buildpacks/libjvm](https://github.com/paketo-buildpacks/libjvm) | `calc/` | The memory calculator that turns a container limit into JVM flags |

---

## 10. Interview soundbites

* "Layers are cached positionally, so I order them by change frequency. With Boot's `jarmode=tools`, a commit changes about 1 MB of application layer instead of a 24 MB fat jar."
* "Exec-form entrypoint, so Java is PID 1 and gets `SIGTERM`. A shell-form entrypoint is the most common reason graceful shutdown silently doesn't happen."
* "Distroless Java 25 is 73 MB compressed, runs as 65532 and has no shell. I debug with ephemeral containers."
* "The AOT cache must be trained by the same JVM build that reads it. The distroless image ships 25.0.5 while my build stage had 25.0.4.1, so I train inside the runtime stage, with a profile that starts without external systems."
* "A mismatched AOT cache doesn't fail; the JVM just runs without it. A G1-trained cache was rejected under ZGC in my test. CI starts the image with `AOTMode=on` to catch that."
* "The AOT cache halves startup but adds a ~60 MB layer that changes every commit. That's a deliberate trade."

---

## 11. Deep dive: the image beyond the Dockerfile (verified) 🔥

[7.7](07-Container-Images-and-JVM-Profiles-Blueprints-II-jlink-AOT-Workloads.md) replaced this module's distroless Java image with a jlink'd runtime on `distroless/java-base`. [7.8](08-Kubernetes-Platform-Blueprints-II-Kustomize-Guardrails-Consumers-Jobs-Canary.md) moved digest pinning from convention into admission. What changed and why:

| Decision here (§3–§6) | Batch 3 result | Evidence |
|---|---|---|
| `distroless/java25` base (73.3 MB compressed) | jlink runtime (21 modules) + `java-base` (11.2 MB): **29.7 MB** of runtime to pull, with every check passing | 7.7 §1.1, §2.2 |
| "jdeps gives you the module list" | jdeps **can't see** service providers: German/Japanese dates silently printed in English and `IBM037` vanished. Dropping `java.desktop` broke Spring (`java.beans`) | 7.7 §1.1–§1.2 |
| Buildpacks as the easy path (§7) | Paketo's default jlink is `java.*` only: CPU metrics **404**, `-XX:StartFlightRecording` **fails at boot** | 7.7 §1.3 |
| Smaller is better | `--compress zip-6` made the runtime **8 MB bigger to pull** (zip-in-gzip) with the same startup | 7.7 §2.2 |
| AOT cache (§4.3–§4.4) | Works on a jlink runtime with or without a CDS archive: 2.31 s → **1.29 s** | 7.7 §2.1 |
| Multi-arch | Temurin 25 has no jmods, so jlink **can't cross-link** (JEP 493). Build on `$BUILDPLATFORM`, jlink and AOT training on the target arch | 7.7 §1.4, §3.2 |
| Pinned by digest in the Deployment | A `ValidatingAdmissionPolicy` denies tag-only images, foreign registries, unpinned init containers and a look-alike `registry.example.com.evil.io` (CEL evaluated) | 7.8 §2.5 |
| Flags from `JAVA_TOOL_OPTIONS` | `JDK_JAVA_OPTIONS`: the former also reaches `jcmd` (corrected in §4.1's comment and §8's table) | 7.7 §4.5 |

Two lessons that generalize:

* **A linter checks hygiene, not posture.** hadolint passed the 7.7 Dockerfile and flagged the naïve one's shell-form entrypoint. It said nothing about the floating tag, the full JDK, or running as root. Non-root, digests and limits are enforced at admission ([7.8 §2](08-Kubernetes-Platform-Blueprints-II-Kustomize-Guardrails-Consumers-Jobs-Canary.md)) and Pod Security, not in review.
* **Measure what the registry ships, not what `du` says.** Layers travel gzipped, and scale-out speed depends on pull bytes.

---

## Summary

| Topic | Key point | Evidence |
|---|---|---|
| Layers | Cached positionally; order by change frequency; a commit changes ~1 MB instead of a 24 MB fat jar | §0, §2 |
| Base image | Distroless: no shell, uid 65532; debug with ephemeral containers | §3 |
| The Dockerfile | Multi-stage, `jarmode=tools` extract, exec-form entrypoint | §4.1–§4.2 |
| AOT cache | Train in the runtime stage with the same JVM build; a mismatch fails **silently** (G1-trained cache rejected under ZGC); CI runs `AOTMode=on` | §4.3 |
| AOT trade-off | Halves startup, adds a ~60 MB layer per commit | §4.4 |
| PID 1 | Exec form, so Java gets `SIGTERM`; shell form silently breaks graceful shutdown | §5 |
| Pod security | Non-root, read-only root, drop ALL, seccomp `RuntimeDefault` | §6 |
| Buildpacks vs Jib | Convenience vs control; Paketo's jlink needs explicit modules | §7, §11 |
| jlink runtime | jdeps + `jdk.localedata` + `jdk.charsets`; no `--compress`; 29.7 MB gzipped | §11 (7.7) |
| Admission | Registry + digest enforced by CEL on Pods | §11 (7.8 §2.5) |

**Next:** [7.3 Kubernetes probes and graceful shutdown →](03-Kubernetes-Probes-and-Graceful-Shutdown.md)
