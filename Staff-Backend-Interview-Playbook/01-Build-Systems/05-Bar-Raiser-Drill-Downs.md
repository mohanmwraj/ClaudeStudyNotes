# 1.5 Bar-Raiser Drill-Downs: Build Systems & Dependency Engineering

> **How to use this file:** read the scenario and the first probe, answer out loud (2 minutes), then open the defense. Each chain goes 3–4 levels deep, because that's where bar-raisers separate L5 from L6. The evidence behind every defense is in [1.1](01-Maven-Internals-Lifecycle-Mojos-Reactor.md)–[1.4](04-Enterprise-Builds-OCI-Images-Annotation-Processors-Enforcer.md), and most of it was verified on real builds.
>
> **Format:** 🎤 what the candidate said · 🔍 the interviewer's probe · 🛡️ the staff-level defense.

---

## Drill 1: "A dependency bump broke production with `NoSuchMethodError`" 🔥

**Scenario.** After a routine library bump, one endpoint in production throws `java.lang.NoSuchMethodError: 'String demo.common.Version.newApi()'`. CI was green.

🎤 *"The library has a bug, we should roll back the bump."*

🔍 **Probe 1: Why was CI green if the method doesn't exist?**

<details><summary>🛡️ Defense</summary>

Compilation and linking happen at different times. `lib-c` was compiled against `common:2.0` (which has `newApi()`). Our build *resolved* `common:1.0`, because Maven's nearest-wins picked the depth-2 declaration from `lib-a` over the depth-3 one from `lib-c`. javac only compiled **our** code against our classpath. It never re-verified `lib-c`'s bytecode. The JVM resolves the method reference lazily, the **first time that call site executes**, so only the code path that calls `lib-c` fails, and our tests didn't exercise it.

Proof from the lab ([1.3 §1.2](03-Dependency-Resolution-Jar-Hell-BOMs-Catalogs-Shading.md)): `dependency:tree -Dverbose` shows `(demo:common:jar:2.0:compile - omitted for conflict with 1.0)`, the build passes, and the run fails at `LibC.hello`.
</details>

🔍 **Probe 2: How do you find out, in 5 minutes, which jar the running JVM loaded `Version` from?**

<details><summary>🛡️ Defense</summary>

1. `Version.class.getProtectionDomain().getCodeSource().getLocation()` from a debug endpoint or `jshell` attached to the classpath, or
2. restart one instance with `-Xlog:class+load=info` and grep for the class, or
3. `jcmd <pid> VM.class_hierarchy` / `GC.class_histogram` to confirm it's loaded, then check `VM.system_properties` for `java.class.path`.

Then compare it with `mvn dependency:tree -Dverbose -Dincludes=demo:common`. If the tree says 2.0 but the JVM loaded 1.0 from another jar, it's a **duplicate class**, not a version conflict ([1.3 §2.2](03-Dependency-Resolution-Jar-Hell-BOMs-Catalogs-Shading.md) reproduces exactly that).
</details>

🔍 **Probe 3: Fix it so this class of bug can't ship again, across 200 services.**

<details><summary>🛡️ Defense</summary>

* **Immediate:** pin `common:2.0` in `dependencyManagement`. Managed versions apply to transitive dependencies before conflict resolution, and the tree shows `(version managed from 1.0)`.
* **Systemic:** put the Enforcer in the **corporate parent** and run it in `validate`: `requireUpperBoundDeps` (no silent downgrades) and `banDuplicateClasses` (no order-dependent duplicates). In Gradle: `failOnVersionConflict()` for libraries, dependency locking plus review for applications.
* **Why not `dependencyConvergence` everywhere?** It fails on *any* disagreement, even when the higher version wins. Spring/cloud SDK graphs rarely pass, and teams start excluding the rule. Upper bounds is the rule people can keep.
* **Test strategy:** a "classpath smoke test" that loads every Spring bean and calls a health endpoint for each integration, so lazy linking errors show up in CI.
</details>

🔍 **Probe 4 (L6): The rule breaks 40 services on day one. How do you roll it out?**

<details><summary>🛡️ Defense</summary>

Ship it in **warn mode** first (`<fail>false</fail>`), collect the violations centrally (parse build logs or use a Develocity dashboard), and fix the top offenders **in the platform BOM**. Most violations come from 3–5 libraries. Then flip to fail mode for new services, set a deadline for the rest, and allow narrowly scoped `ignoreClasses`/exclusions **with an owner and an expiry date**. The real L6 move is to stop the problem at the source with a **platform BOM** owned by one team, so services stop resolving conflicts individually.
</details>

**What the interviewer is scoring:** L5 explains nearest-wins and adds `dependencyManagement`. L6 explains *lazy linking*, distinguishes conflicts from duplicate classes, and designs an org-wide rollout with a platform BOM.

---

## Drill 2: "Gradle is better because it picks the highest version" ⚡

🎤 *"Maven's nearest-wins is broken. Gradle always picks the highest version, so it can't downgrade."*

🔍 **Probe 1: Can highest-wins break production too?**

<details><summary>🛡️ Defense</summary>

Yes. It can silently **upgrade across a major**. If `lib-a` was built against `common:1.x` and something else pulls in `common:2.0`, which removed a method `lib-a` calls, `lib-a` gets the `NoSuchMethodError`. Highest-wins bets on backward compatibility. Nearest-wins bets on the author's choice. Neither replaces *visibility*: `dependencyInsight` in Gradle (`Selection reasons: By conflict resolution: between versions 2.0 and 1.0`) and the verbose tree in Maven.
</details>

🔍 **Probe 2: The security team needs everyone *off* `common:2.1.3` (CVE) but *not* on 3.x. Express that in Gradle.**

<details><summary>🛡️ Defense</summary>

Rich versions on a constraint, ideally inside the platform:

```kotlin
dependencies {
    constraints {
        implementation("demo:common") {
            version { require("2.1.4"); reject("2.1.3") }
            because("CVE-2026-XXXX in 2.1.3; 3.x breaks lib-a")
        }
    }
}
```

`require` allows upgrades within what the graph asks for. `reject` bans the bad version. To also forbid 3.x, use a range with `strictly("[2.1.4, 3.0)")`, knowing that `strictly` also **allows downgrades** to 2.1.4 and fails if another strict constraint disagrees.
</details>

🔍 **Probe 3: Why not just use `enforcedPlatform()` for the company BOM?**

<details><summary>🛡️ Defense</summary>

Because `enforcedPlatform` **forces** versions, *including downgrades*. In the lab, `enforcedPlatform(demo-bom:1.0)` rewrote `common:2.0 -> 1.0` and the app crashed with the same `NoSuchMethodError` as Maven ([1.3 §3.2](03-Dependency-Resolution-Jar-Hell-BOMs-Catalogs-Shading.md)). In a **published library** it's worse, because it forces the versions on *your consumers*. Use `platform()` (constraints that join conflict resolution) everywhere, and `enforcedPlatform` only in leaf applications when you accept the downgrade risk on purpose.
</details>

🔍 **Probe 4: Where does the version catalog fit?**

<details><summary>🛡️ Defense</summary>

It doesn't take part in resolution. A catalog is **build-time aliases**: one place to *write* coordinates and versions, plus type-safe accessors (`libs.bundles.web.service`). It doesn't affect transitive dependencies. The catalog holds the BOM's coordinates, and `platform(libs.spring.boot.bom)` does the alignment. Confusing the two is a common mid-level mistake.
</details>

---

## Drill 3: "We moved off `spring-boot-starter-parent` to our corporate parent" 🔥

**Scenario.** You import `spring-boot-dependencies` in a corporate parent. A CVE needs SLF4J pinned, so a team sets `<slf4j.version>…</slf4j.version>` in their POM. The scanner still flags it.

🔍 **Probe 1: Why didn't the property work?**

<details><summary>🛡️ Defense</summary>

An **imported** BOM is a separate model, interpolated with **its own** properties, and only its resolved `dependencyManagement` entries are copied in. Our property never reaches it. With the *parent*, Boot's `dependencyManagement` becomes part of our model and `${slf4j.version}` interpolates against our merged properties.

Verified ([1.3 §3.1](03-Dependency-Resolution-Jar-Hell-BOMs-Catalogs-Shading.md)):

```text
== parent: org.slf4j:slf4j-api:jar:2.0.17:compile
== import: org.slf4j:slf4j-api:jar:2.0.20:compile
== import-fixed: org.slf4j:slf4j-api:jar:2.0.17:compile
```
</details>

🔍 **Probe 2: Give two fixes, and say which one you'd standardize.**

<details><summary>🛡️ Defense</summary>

(a) Import a more specific BOM **before** Boot's, because the first import of a GA wins. (b) Add an explicit `dependencyManagement` entry, because local entries beat imports. I'd standardize (a) inside a **platform BOM** owned by the platform team: `acme-platform-bom` imports the override BOMs first, then `spring-boot-dependencies`, and services import only `acme-platform-bom`. One place to patch a CVE for 300 services, and a version bump is a single PR, repeated across repos by Renovate.
</details>

🔍 **Probe 3 (L6): Why not tell everyone to inherit `spring-boot-starter-parent`?**

<details><summary>🛡️ Defense</summary>

A project has **one** parent. If Boot's parent is the parent, the company can't use inheritance for its own build policy (Enforcer, plugin pins, repositories, release profiles). Splitting *policy* (corporate parent) from *versions* (BOM import) also lets non-Boot modules (libraries, Lambda handlers) share the policy without importing Boot. The cost is losing Boot's property-override convenience, which the platform BOM pattern replaces.
</details>

---

## Drill 4: "Our CI takes 40 minutes" ⚡

🎤 *"We'll add more CI runners and run `mvn -T 4`."*

🔍 **Probe 1: What's the theoretical maximum speed-up of `-T` for a reactor?**

<details><summary>🛡️ Defense</summary>

Maven parallelizes **modules**, and a dependent module waits for its dependency's *whole* lifecycle up to the requested phase. The floor is the **critical path**: the longest chain of dependent modules, each including its tests. With 40 modules where the core chain is 12 deep, `-T 16` barely helps. First measure the per-module time (build scan, or timestamps), then shorten the critical path: split a fat `core` module, move slow integration tests into Failsafe or a separate job, or try Maven 4's concurrent builder, which lets dependents start at `ready`.
</details>

🔍 **Probe 2: After switching to Gradle with a remote build cache, the hit rate is 15%. Why?**

<details><summary>🛡️ Defense</summary>

Usually **non-hermetic inputs** or **non-relocatable keys**:

* A timestamp or git SHA in a generated resource on the classpath. In our blueprint, `springBoot { buildInfo() }` wrote `build.time`, so `:test` missed the cache every build. After `excludes = setOf("time")` it became `:order-service:test FROM-CACHE` (verified, [1.2 §4.2](02-Gradle-Internals-Phases-Task-Graph-Caches-Daemon.md)).
* Absolute paths in inputs. Use `@PathSensitive(RELATIVE)`.
* Different JDK vendors or versions between CI and laptops (part of the key).
* Tasks that aren't cacheable (custom tasks without `@CacheableTask`).

Diagnose with `--scan` (compare two builds' cache keys) or `-Dorg.gradle.caching.debug=true`.
</details>

🔍 **Probe 3: Developers complain every Gradle command takes 8 seconds before anything runs.**

<details><summary>🛡️ Defense</summary>

That's **configuration time**. Fixes: the configuration cache (on a hit, the configuration phase is skipped entirely; verified: the scripts' `println`s vanish and `Reusing configuration cache.` appears), lazy `tasks.register`, no expensive work at script top level, and convention plugins in `build-logic` instead of `subprojects {}`. Measure with `--profile` or a build scan's configuration breakdown.
</details>

🔍 **Probe 4 (L6): Maven or Gradle for a new 300-module monorepo?**

<details><summary>🛡️ Defense</summary>

It's an organizational decision as much as a technical one:

| Factor | Maven | Gradle |
|---|---|---|
| Incremental and cache granularity | Module-level (build cache extension, mvnd) | **Task-level**, ABI compile avoidance, configuration cache |
| Uniformity and onboarding | **Very high.** The lifecycle is fixed | Depends on discipline (convention plugins) |
| Arbitrary logic | Write a plugin | Kotlin in `build-logic` (powerful, and easy to abuse) |
| Tooling ecosystem in the company | Usually larger | Growing |

At 300 modules, Gradle's task-level caching and compile avoidance usually win **if** a platform team owns `build-logic` and enforces conventions. If there's no build-platform team, Maven 4 plus the build cache extension and mvnd can be the lower-risk choice. Either way: remote cache, build scans, and a written build SLO ("p50 PR build < 10 min").
</details>

---

## Drill 5: "Our image push takes 3 minutes per commit" ⚡

🔍 **Probe 1: Explain why from first principles.**

<details><summary>🛡️ Defense</summary>

OCI layers are content-addressed, and a changed layer invalidates every layer above it. With `COPY app.jar`, ~23 MB of third-party jars sit in the same layer as our classes, so every commit produces a new 23 MB layer to push and every node pulls it again. Layering by change frequency (OS → JRE → dependencies → snapshot deps → application) makes a typical commit a few-KB layer.
</details>

🔍 **Probe 2: Jib, Buildpacks or a Dockerfile?**

<details><summary>🛡️ Defense</summary>

* **Jib:** no Docker daemon (great for Kubernetes CI runners), exploded classpath, reproducible (`created: 1970-01-01T00:00:00Z`, verified). But it's not a general-purpose Dockerfile, so adding OS packages is awkward.
* **Buildpacks:** `spring-boot:build-image` defaults to `paketobuildpacks/builder-noble-java-tiny` (verified from Boot 4.1.2's `BuildRequest`). You get patched bases, a memory calculator and policy from a platform team, but it needs Docker.
* **Dockerfile + `jarmode=tools extract --layers`:** full control, works with any builder, needs discipline.

I'd let the platform team pick one standard per company and lint for it.
</details>

🔍 **Probe 3: You inspect the Jib image config and see `User: None`. So what?**

<details><summary>🛡️ Defense</summary>

The container runs as **root**, because `eclipse-temurin` doesn't set a user and Jib inherits it. A container escape or a file-write bug becomes root on the container filesystem, and Pod Security "restricted" admission rejects it unless `runAsNonRoot` and a numeric user are set. Fix: `jib.container.user=1000:1000` (or `USER 1000` in a Dockerfile), plus `securityContext.runAsNonRoot: true` in Kubernetes. Also pin the base image **by digest**. Jib itself warned: `Base image 'eclipse-temurin:25-jre' does not use a specific image digest - build may not be reproducible`.
</details>

---

## Drill 6: "Lombok stopped working after we upgraded to JDK 25" 🔥

🔍 **Probe 1: Nothing in the Lombok error mentions Lombok. What happened?**

<details><summary>🛡️ Defense</summary>

Since **JDK 23**, javac doesn't run annotation processors **discovered on the classpath** unless processing is requested explicitly (`-processor`, `-processorpath` or `-proc:full`). Lombok was only a `provided` dependency, so it silently didn't run and the build failed with `cannot find symbol … setName(java.lang.String)` (verified, [1.4 §3.1](04-Enterprise-Builds-OCI-Images-Annotation-Processors-Enforcer.md)).
</details>

🔍 **Probe 2: Why would the JDK team make that change?**

<details><summary>🛡️ Defense</summary>

Supply-chain safety. Any jar on the compile classpath could ship a `META-INF/services/javax.annotation.processing.Processor` entry and run arbitrary code **inside your compiler**, with access to your sources and the build machine. Explicit processor paths make that an opt-in decision and keep processor dependencies off the compile classpath.
</details>

🔍 **Probe 3: You add `annotationProcessorPaths`; now MapStruct generates mappers with all fields `null`.**

<details><summary>🛡️ Defense</summary>

Processor **ordering**. MapStruct ran before Lombok generated the getters, so it saw no properties. Order Lombok first, add `lombok-mapstruct-binding` so MapStruct defers until Lombok's round, and set `-Amapstruct.unmappedTargetPolicy=ERROR` so a missing mapping becomes a compile error instead of a `null` in production.
</details>

---

## Drill 7: "Should we shade our dependencies?" 🧊

🔍 **Probe 1: When is shading the right answer?**

<details><summary>🛡️ Defense</summary>

When you **publish a library** that must not impose its dependency versions on users (Kafka clients, Hadoop and Elasticsearch shade Guava/Netty/Jackson for this reason), or, rarely, when an application *must* run two incompatible majors and can't upgrade the old caller. Relocation rewrites bytecode references (verified: `invokestatic … demo/c/shaded/common/Version.newApi`), so both copies coexist ([1.3 §6](03-Dependency-Resolution-Jar-Hell-BOMs-Catalogs-Shading.md)).
</details>

🔍 **Probe 2: What breaks?**

<details><summary>🛡️ Defense</summary>

String-based references (`Class.forName`, XML/YAML config, `META-INF/services` unless transformed), reflection-heavy frameworks, and **CVE scanners**: the vulnerable library now hides under `shaded.*` and the SBOM no longer lists it. Mitigations: `ServicesResourceTransformer`/`mergeServiceFiles()`, relocating only the conflicting packages, and generating the SBOM before shading, or with tooling that records shaded components.
</details>

🔍 **Probe 3 (L6): What would you do instead in an application?**

<details><summary>🛡️ Defense</summary>

In order of preference: upgrade the old caller; exclude and replace; isolate the legacy component **in its own process** (a sidecar or separate service) or a separate class loader; shade as a last resort, with an owner and an exit plan. Shading in an app usually means a dependency-governance problem upstream.
</details>

---

## Drill 8: "Prove our build is reproducible" 🧊

🔍 **Probe 1: Why does anyone care?**

<details><summary>🛡️ Defense</summary>

(1) **Supply-chain verification**: an independent rebuild should match the published artifact bit for bit, which proves the binary came from the source. (2) **Caching**: identical inputs giving identical outputs is what makes build caches and layer caches effective. (3) Debugging: you can rebuild an old release exactly.
</details>

🔍 **Probe 2: What makes jars differ between two builds of the same commit?**

<details><summary>🛡️ Defense</summary>

Timestamps in zip entries, file ordering, generated sources with dates (MapStruct writes `date = "2026-10-25T09:32:13+0530"` into `@Generated`), build-info files with `build.time`, absolute paths, and non-pinned plugin or dependency versions. Defaults have improved: Maven 3.10 sets `project.build.outputTimestamp` by default, Gradle 9 makes archives reproducible by default (verified: entries dated `1980-02-01 00:00`), and Jib fixes the image `created` field to the epoch.
</details>

🔍 **Probe 3: How do you *test* it in CI?**

<details><summary>🛡️ Defense</summary>

Build twice in clean environments (different directories, different users/time zones) and compare SHA-256s of the artifacts. Maven offers `mvn artifact:compare` (from the `maven-artifact-plugin`) against a reference build, and the Reproducible Builds project documents the common offenders. Failures are triaged like flaky tests: find the non-hermetic input and remove or pin it.
</details>

---

## Drill 9: "How do you version and release a multi-module repo?" ⚡

🔍 **Probe 1: Why do `1.4.0-SNAPSHOT` bumps cause merge conflicts, and what's the fix?**

<details><summary>🛡️ Defense</summary>

Every module repeats the version in its `<parent>`, so a release touches every POM. CI-friendly versions (`${revision}`) keep one property in the root and let CI pass `-Drevision=1.4.0`. In Maven 3 you **must** also run `flatten-maven-plugin` (`resolveCiFriendliesOnly`) so the *deployed* POMs contain real versions, not `${revision}`. Maven 4 resolves them natively in the consumer POM.
</details>

🔍 **Probe 2: What is Maven 4's consumer POM and why should a release engineer care?**

<details><summary>🛡️ Defense</summary>

Maven 4 deploys a **separate consumer POM** (model 4.0.0, readable by Maven 3) instead of your build POM (model 4.1.0). With flattening enabled it has no parent, resolved versions and only compile/runtime dependencies. Verified: `service-1.0.0.pom` contained only `api:1.0.0` and `slf4j-api:2.0.17`, while `service-1.0.0-build.pom` kept the original. Consumers no longer download your parent chain or evaluate your profiles, and your build syntax can evolve.
</details>

---

## Drill 10: "Write a custom Maven plugin" (live-coding variant) ⚡

🔍 **Probe: Write a mojo that fails if the runtime classpath exceeds N jars. What annotation elements matter?**

<details><summary>🛡️ Defense</summary>

`@Mojo(name="check", defaultPhase=VERIFY, requiresDependencyResolution=RUNTIME, threadSafe=true)`, inject `MavenProject` via `@Parameter(defaultValue="${project}", readonly=true)`, read `project.getArtifacts()` (the **post-conflict** set), and throw `MojoFailureException` (build failure) rather than `MojoExecutionException` (unexpected error). Without `requiresDependencyResolution`, `getArtifacts()` is empty. Without `threadSafe`, `-T` warns. The verified plugin and its output are in [1.1 §3.1](01-Maven-Internals-Lifecycle-Mojos-Reactor.md): `Dependency budget exceeded: 57 > 40`.
</details>

---

# Round 2: platforms, publishing and gates (Batch 1 deep dive)

> Evidence: [1.6 Blueprints II](06-Build-Script-Blueprints-Platform-Publishing-Quality-Gates-CI.md), [1.2 §5.1](02-Gradle-Internals-Phases-Task-Graph-Caches-Daemon.md#51-verified-what-invalidates-the-configuration-cache-eager-vs-lazy-environment-reads-), [1.1 §7.1.1](01-Maven-Internals-Lifecycle-Mojos-Reactor.md#711-verified-resolver-2-asks-each-remote-repository-only-for-groupids-it-can-have-), [1.3 §6.5](03-Dependency-Resolution-Jar-Hell-BOMs-Catalogs-Shading.md#65-what-your-librarys-consumers-actually-get-api-vs-implementation-and-used-undeclared-verified-) (Gradle 9.8.2, Maven 3.10.0, JDK 25).

---

## Drill 11: "40 repositories, half Maven, half Gradle. Give them one set of versions." 🔥

🎤 *"A shared `libs.versions.toml` in a Git submodule."*

🔍 **Probe 1: What does a version catalog not do, and what does that mean for the Maven half?**

<details><summary>🛡️ Defense</summary>

A catalog is aliases for coordinates: it doesn't constrain **transitive** versions, and Maven can't read it at all. The thing that aligns versions in both tools is a **BOM**. Publish both from one platform build: `java-platform` → `acme-bom` (constraints, plus Spring Boot's BOM imported) and `version-catalog` → `acme-catalog`. Verified: a Maven service imported the Gradle-built BOM and resolved PostgreSQL 42.7.14 from it and slf4j 2.0.20 through the imported Boot BOM; a Gradle service used `from("com.acme:acme-catalog:1.4.0")` for aliases and `platform(acme.acme.bom)` for alignment.
</details>

🔍 **Probe 2: Does the platform affect versions a consumer never declared?**

<details><summary>🛡️ Defense</summary>

Yes, and that's its main value. HikariCP asks for slf4j **2.0.17**; on the Gradle consumer's runtime classpath the platform aligned it to **2.0.20** (`org.slf4j:slf4j-api:2.0.17 -> 2.0.20`, verified). In Maven, an imported BOM's `dependencyManagement` applies to transitive dependencies as well.
</details>

🔍 **Probe 3 (L6): How do you roll a platform upgrade out to 40 repositories?**

<details><summary>🛡️ Defense</summary>

Version the platform like a product (BOM, catalog and shared libraries released **together**), automate PRs into every consumer (Renovate/Dependabot pointed at the BOM and catalog), and run each consumer's own gates on that PR. Track adoption (which repos are on which platform version) and set a support window. Use `constraints` (strict only where you must) rather than `enforcedPlatform`, so a team can still pin a security fix ahead of the platform.
</details>

---

## Drill 12: "We removed HikariCP from our shared library and three services stopped compiling" 🔥

🎤 *"They should have declared HikariCP themselves."*

🔍 **Probe 1: True, but whose bug is it?**

<details><summary>🛡️ Defense</summary>

The library's. If HikariCP was declared with `api` (or `compile` scope in Maven), the library **promised** it to consumers' compile classpaths, so removing it is a breaking change. Declared as `implementation`, Gradle publishes it with `<scope>runtime</scope>`: verified, a Maven consumer that imported `com.zaxxer.hikari.HikariConfig` failed with `package com.zaxxer.hikari does not exist`, and the Gradle consumer's `compileClasspath` didn't contain it. With that split, consumers can't come to depend on it, and the removal is a minor release.
</details>

🔍 **Probe 2: And on the consumer side?**

<details><summary>🛡️ Defense</summary>

"Used undeclared" dependencies are a liability even when they compile. Verified with `mvn dependency:analyze`: code that used slf4j compiled against **2.0.17**, a version that only arrived because HikariCP was on the classpath. Gate it: `analyze-only` with `failOnWarning` in `verify` (with explicit ignores for aggregators like `junit-jupiter` or Boot starters), or Gradle's dependency-analysis plugin.
</details>

---

## Drill 13: "We enabled the configuration cache but CI never reuses it" ⚡

🎤 *"CI agents are ephemeral, so caches don't help."*

🔍 **Probe 1: Even on a persistent agent it says "Calculating task graph" every time. Why?**

<details><summary>🛡️ Defense</summary>

Something read at configuration time changes on every run. Gradle tells you: verified, `Calculating task graph as configuration cache cannot be reused because environment variable 'DEPLOY_REGION' has changed.` The script read `System.getenv("DEPLOY_REGION")` while being evaluated. In CI, build numbers, commit SHAs and timestamps are typical culprits.
</details>

🔍 **Probe 2: Fix it without losing the value.**

<details><summary>🛡️ Defense</summary>

Read it as a provider: `providers.environmentVariable("DEPLOY_TIER")`, resolved inside the task action. Verified: changing `DEPLOY_TIER` reused the cache (`Configuration cache entry reused.`) and the task still printed the new value. For values that genuinely change the task graph, accept the miss but keep them out of the common path (e.g. only on release builds).
</details>

🔍 **Probe 3 (L6): How do you keep 200 build scripts configuration-cache clean?**

<details><summary>🛡️ Defense</summary>

Convention plugins in `build-logic` that only use providers and `Property<T>`; keep `org.gradle.configuration-cache.problems=fail` (the default; teams often relax it to `warn` during migration and forget) so new problems break the build; a CI job that runs the build twice and fails if the second run doesn't say `Configuration cache entry reused`; and code review for `System.getenv`/`System.getProperty`/file reads at configuration time.
</details>

---

## Drill 14: "Coverage is 85 % and bugs still ship in error paths" ⚡

🎤 *"Raise the line-coverage threshold to 90 %."*

🔍 **Probe 1: What metric would have caught it?**

<details><summary>🛡️ Defense</summary>

**Branch** coverage. Verified: a module passed its 80 % line rule while JaCoCo reported `branches covered ratio is 0.50, but expected minimum is 0.70`: the VIP path and the invalid-input guard were never exercised as both outcomes. A parameterized test over the decision table plus tests for the guard got it to `All coverage checks have been met.`
</details>

🔍 **Probe 2: Our ITs exercise those branches; why don't they count?**

<details><summary>🛡️ Defense</summary>

They do if the agent is wired into both: `jacoco:prepare-agent` sets the `argLine` property that **both** surefire and failsafe use, so unit tests and ITs write to the same `jacoco.exec` and `jacoco:check` runs in `verify` after failsafe (verified plan order: surefire → jar → failsafe integration-test/verify → jacoco report/check). A custom `argLine` that doesn't include `@{argLine}` silently drops the agent.
</details>

🔍 **Probe 3 (L6): Is a coverage gate a quality strategy?**

<details><summary>🛡️ Defense</summary>

It's a floor, not a strategy. Use it to stop regressions (ratchet: never lower than main), prefer branch over line, exclude generated code, and pair it with mutation testing (PIT) on critical modules, which measures whether tests would notice a wrong branch at all.
</details>

---

## Drill 15: "Someone published `com.acme:acme-core:99.0` to Maven Central" 🧊

🎤 *"Our repository manager proxies Central, so we're safe."*

🔍 **Probe 1: How would that version reach a build?**

<details><summary>🛡️ Defense</summary>

Dependency confusion: if a build asks several repositories for `com.acme:acme-core` with a dynamic or range version, or the manager's group repository merges internal and public artifacts, the highest version can come from the public side. A proxy alone doesn't stop that; **routing rules** do.
</details>

🔍 **Probe 2: What do Maven and Gradle give you to prevent it?**

<details><summary>🛡️ Defense</summary>

Gradle: per-repository content filters. Verified in our consumer: `maven(internal) { content { includeGroup("com.acme") } }` and `mavenCentral { content { excludeGroup("com.acme") } }`, under `FAIL_ON_PROJECT_REPOS` so no module can add its own repository. Maven 3.10 / Resolver 2: remote repository filters; the build log showed `Loaded 24231 auto-discovered prefixes for remote repository central`, so Central is only asked for groupIds it serves, and a `groupId` filter can pin `com.acme` to the internal repository explicitly. Plus: no dynamic versions for internal artifacts, dependency locking/verification metadata, and the repository manager's routing rules (block `com.acme` from proxied remotes).
</details>

---

## L5 vs L6 signal

| Topic | L5 (senior) answer | L6 (staff) answer |
|---|---|---|
| Conflicts | Explains nearest-wins / highest-wins, uses `dependencyManagement` | Explains lazy linking and duplicate classes; designs Enforcer + platform BOM rollout across the org |
| Platforms (Round 2) | Shares a catalog file | Publishes BOM + catalog + libraries together, consumable from Maven and Gradle; automates rollout |
| Library APIs (Round 2) | Uses `implementation` because the IDE suggests it | Explains the published scopes and treats `api` as a compatibility promise |
| Gates (Round 2) | Has coverage reports | Enforces branch coverage, declared-equals-used and reproducibility in `verify` |
| Supply chain (Round 2) | "We use a proxy" | Repository content filters, resolver prefix filtering, no dynamic internal versions |
| Build speed | `-T`, more runners | Critical path, task-level caching, hermeticity, configuration cache, a build SLO |
| BOMs | Imports Boot's BOM | Knows the property-override trap and the import-order rule; owns a platform BOM |
| Images | Multi-stage Dockerfile | Layer economics, reproducibility, non-root, digest pinning, AOT cache; picks one standard |
| Tooling choice | Personal preference | Org capability (who owns `build-logic`?), migration cost, measurable SLOs |

## Red flags interviewers listen for

* "Maven/Gradle resolves conflicts, so we don't need to check."
* "We run `mvn clean install` in CI."
* "We use `enforcedPlatform` so versions are always right."
* "Version catalogs manage our transitive dependencies."
* "We shade everything to avoid conflicts."
* "A shared `libs.versions.toml` aligns our versions."
* "We declare everything as `api`, it's simpler."
* "Line coverage is above 80 %, so the error paths are tested."
* "The proxy repository protects us from dependency confusion."

---

## Rapid-fire flashcards

<details><summary>1. Name the 3 Maven lifecycles and the phase that runs integration tests' cleanup.</summary>

`clean`, `default`, `site`. `post-integration-test` (Failsafe's `verify` goal runs after it, so containers are stopped even when tests fail).
</details>

<details><summary>2. What's the execution id of a goal run from the command line?</summary>

`default-cli`.
</details>

<details><summary>3. How do you disable an inherited plugin execution?</summary>

Redeclare the execution with the same `<id>` and `<phase>none</phase>`.
</details>

<details><summary>4. Inheritance vs aggregation in one sentence each.</summary>

Inheritance (`<parent>`) merges configuration from parent to child. Aggregation (`<modules>`/`<subprojects>`) only says which projects build together in the reactor.
</details>

<details><summary>5. Which wins: a `dependencyManagement` entry or nearest-wins?</summary>

`dependencyManagement`. It rewrites transitive versions before conflict resolution (`version managed from 1.0`).
</details>

<details><summary>6. Maven tie-break at equal depth?</summary>

First declaration in POM order.
</details>

<details><summary>7. Which BOM wins when two imports manage the same GA?</summary>

The first import declared.
</details>

<details><summary>8. `requireUpperBoundDeps` vs `dependencyConvergence`?</summary>

Upper-bound fails only on downgrades. Convergence fails on any disagreement.
</details>

<details><summary>9. What can `banDuplicateClasses` find that the dependency tree can't?</summary>

The same FQCN in two *different* artifacts (relocated or uber jars), where correctness depends on classpath order.
</details>

<details><summary>10. Gradle's three phases?</summary>

Initialization (settings, included builds, project objects), configuration (scripts, task registration, task graph), execution.
</details>

<details><summary>11. `tasks.register` vs `tasks.create`?</summary>

`register` is lazy (configured only if the task is in the graph). `create` configures eagerly on every build.
</details>

<details><summary>12. UP-TO-DATE vs FROM-CACHE?</summary>

UP-TO-DATE: inputs and outputs unchanged since the last run in this workspace. FROM-CACHE: outputs restored from the local or remote build cache using the cache key.
</details>

<details><summary>13. Why is `Jar` not cacheable in Gradle?</summary>

Re-zipping is about as cheap as downloading the zip from the cache.
</details>

<details><summary>14. What does the configuration cache skip?</summary>

Initialization and configuration (scripts, plugins, task-graph calculation) when the inputs to configuration are unchanged.
</details>

<details><summary>15. Why is `Task.project` forbidden at execution time with the configuration cache?</summary>

Execution runs from a serialized task graph with no `Project` model.
</details>

<details><summary>16. `platform()` vs `enforcedPlatform()`?</summary>

Constraints that join conflict resolution vs forced versions (downgrades included).
</details>

<details><summary>17. Version catalog vs platform?</summary>

Aliases for writing coordinates vs resolution constraints that affect transitive dependencies.
</details>

<details><summary>18. `api` vs `implementation` in `java-library`?</summary>

`api` dependencies leak to consumers' compile classpath (use them for types in your public signatures). `implementation` dependencies don't, which enables compile avoidance.
</details>

<details><summary>19. What did JDK 23 change for annotation processors?</summary>

No implicit discovery from the classpath. Processors must be requested explicitly.
</details>

<details><summary>20. Boot 4.1.2's default Buildpacks builder?</summary>

`paketobuildpacks/builder-noble-java-tiny` (Ubuntu 24.04, tiny run image).
</details>

<details><summary>21. Which layer does a sibling reactor module go to in Boot's `layers.idx`?</summary>

`application`.
</details>

<details><summary>22. Why does the AOT cache need `extract` rather than the fat jar?</summary>

It needs a plain classpath of jars (same jars, same order) at training and production time. Nested jars inside a Boot fat jar aren't supported.
</details>

<details><summary>23. Two Maven 3.10 changes that can break an upgrade?</summary>

Stricter POM validation (duplicates now fail) and no super-POM plugin versions (unpinned plugins change).
</details>

<details><summary>24. Maven 4's build POM vs consumer POM?</summary>

Model 4.1.0 build POM for building. A model 4.0.0 consumer POM is deployed for consumers (optionally flattened).
</details>

<details><summary>25. Spring Framework 7 and `commons-logging`?</summary>

Spring 7 dropped `spring-jcl` and depends on Apache Commons Logging 1.3.x. Ban only versions below 1.3.
</details>

<details><summary>26. What does a Gradle `java-platform` publish?</summary>

A POM whose `<dependencyManagement>` holds the constraints (imported BOMs become `<scope>import</scope>`), plus Gradle Module Metadata.
</details>

<details><summary>27. `api` and `implementation` in the published POM?</summary>

`compile` and `runtime` scope.
</details>

<details><summary>28. Can Maven read a Gradle version catalog?</summary>

No. Publish a BOM next to the catalog for Maven consumers.
</details>

<details><summary>29. Why can "used undeclared" be dangerous if the code compiles?</summary>

The version comes from someone else's dependency (slf4j 2.0.17 via HikariCP in our run) and changes when they change.
</details>

<details><summary>30. Classic `dependency:analyze` false positive?</summary>

Aggregator artifacts (`junit-jupiter`, Boot starters): "unused declared" while their parts are "used undeclared".
</details>

<details><summary>31. How do surefire and failsafe both feed JaCoCo?</summary>

`jacoco:prepare-agent` sets `argLine`, used by both; keep `@{argLine}` if you customize it.
</details>

<details><summary>32. What does "configuration cache cannot be reused because environment variable X has changed" mean?</summary>

X was read at configuration time (eagerly); read it through `providers.environmentVariable` inside the task.
</details>

<details><summary>33. What does "Loaded 24231 auto-discovered prefixes for remote repository central" mean?</summary>

Maven Resolver 2's prefix filter: the repository is only asked for paths it serves.
</details>

<details><summary>34. Gradle's dependency-confusion control?</summary>

`dependencyResolutionManagement` with `FAIL_ON_PROJECT_REPOS` and per-repository `content { includeGroup / excludeGroup }`.
</details>

---

## Summary

| Round | Drills | What it tests |
|---|---|---|
| Round 1 (1–10) | `NoSuchMethodError` after a bump, highest-wins myths, corporate parent vs Boot parent, 40-minute CI, slow image pushes, Lombok on JDK 25, shading, reproducibility, versioning, writing a plugin | Resolution mechanics, build performance, images and toolchains |
| Round 2 (11–15) | One platform for Maven + Gradle, library API scopes, configuration-cache reuse in CI, branch coverage gates, dependency confusion | Building for an organization: platforms, publishing contracts, gates and supply chain |

**Next pillar:** [2.1 Storage, pages, tuples & WAL →](../02-SQL-RDBMS-Internals/01-Storage-Pages-Tuples-TOAST-WAL.md)
