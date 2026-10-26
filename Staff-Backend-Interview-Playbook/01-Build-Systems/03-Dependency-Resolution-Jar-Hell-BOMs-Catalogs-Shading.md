# 1.3 Dependency Resolution & "Jar Hell": Nearest-Wins vs Highest-Wins, BOMs, Platforms, Version Catalogs, Shading

> **Verified stack:** Maven **3.10.0** (Resolver 2.0.24), Gradle **9.8.2**, Temurin **25.0.4.1**, maven-enforcer-plugin **3.6.3** + extra-enforcer-rules **1.12.1**, maven-shade-plugin **3.6.2**, Shadow (`com.gradleup.shadow`) **9.6.1**, Spring Boot BOM **4.1.2**.
>
> **The lab:** a file-based Maven repository with five tiny artifacts, built so that the conflict is impossible to miss:
>
> ```text
> demo:common:1.0   Version.get()
> demo:common:2.0   Version.get() + Version.newApi()      ← 2.0 ADDS a method
> demo:lib-a:1.0  → common:1.0
> demo:lib-c:1.0  → common:2.0   (LibC.hello() calls Version.newApi())
> demo:lib-b:1.0  → lib-c:1.0
> app             → lib-a, lib-b
> ```
>
> **Go deeper:** class loading and `LinkageError`s in the sibling kit: [Java-Backend-Master-Reference 1.1](../../Java-Backend-Master-Reference/01-JVM-Internals/01-ClassLoading-Linking-JPMS.md)

---

## 0. First principles: why "jar hell" exists at all 🔥

1. **The classpath is flat.** The application class loader searches jars **in order** and returns the *first* `demo/common/Version.class` it finds. One fully-qualified class name maps to exactly **one** class per class loader.
2. **Dependency graphs are diamonds.** Two libraries you use depend on different versions of a third. A build tool **must pick one version per `groupId:artifactId`**, because the JVM can't load both into one class loader.
3. **Compilation and runtime are separated in time.** `lib-c` was compiled against `common:2.0`. If the build picks `common:1.0`, nothing complains *until the JVM links the call* to `Version.newApi()` at runtime. Then you get `NoSuchMethodError`, often in production, often only on one rarely used code path.

So every resolution strategy is an answer to: **"given several requested versions of one module, which one wins, and how do I find out before production?"**

---

## 1. Maven: nearest definition wins 🔥

### 1.1 The algorithm

Maven Resolver builds the full graph, then runs a chain of graph transformers (`org.eclipse.aether.util.graph.transformer`):

| Transformer | Job |
|---|---|
| `ConflictMarker` | Tags all nodes that share a conflict key (`groupId:artifactId:extension:classifier`) |
| `ConflictIdSorter` | Orders conflict groups topologically |
| `ConflictResolver` + **`NearestVersionSelector`** | Picks the winner: **the node closest to the root**. On a depth tie, **the first one encountered in declaration order** |
| `JavaScopeSelector` / `JavaScopeDeriver` | Picks the effective scope (the widest wins: compile > runtime > provided > test) |

The selector does **not** look at version numbers (except to honor hard ranges). A depth-2 `1.0` beats a depth-3 `2.0`.

### 1.2 Verified: nearest wins, then the app crashes

```xml
<dependencies>
  <dependency><groupId>demo</groupId><artifactId>lib-a</artifactId><version>1.0</version></dependency>  <!-- lib-a -> common 1.0 (depth 2) -->
  <dependency><groupId>demo</groupId><artifactId>lib-b</artifactId><version>1.0</version></dependency>  <!-- lib-b -> lib-c -> common 2.0 (depth 3) -->
</dependencies>
```

**Output (verified, `mvn dependency:tree -Dverbose`):**

```text
[INFO] demo:app:jar:1.0
[INFO] +- demo:lib-a:jar:1.0:compile
[INFO] |  \- demo:common:jar:1.0:compile
[INFO] \- demo:lib-b:jar:1.0:compile
[INFO]    \- demo:lib-c:jar:1.0:compile
[INFO]       \- (demo:common:jar:2.0:compile - omitted for conflict with 1.0)
```

The build is **green**. Running the app:

**Output (verified):**

```text
lib-a uses common-1.0
Exception in thread "main" java.lang.NoSuchMethodError: 'java.lang.String demo.common.Version.newApi()'
	at demo.c.LibC.hello(LibC.java:2)
	at demo.b.LibB.hello(LibB.java:2)
	at demo.app.App.main(App.java:6)
```

### 1.3 Verified: on a depth tie, declaration order decides

Swap in `lib-d → common:2.0`, also at depth 2, and declare it **first**:

```text
[INFO] demo:tie:jar:1.0
[INFO] +- demo:lib-d:jar:1.0:compile
[INFO] |  \- demo:common:jar:2.0:compile
[INFO] \- demo:lib-a:jar:1.0:compile
[INFO]    \- (demo:common:jar:1.0:compile - omitted for conflict with 2.0)
```

Reordering two lines in a POM silently changes which version ships. That's why "it worked until someone sorted the dependencies alphabetically" is a real incident.

### 1.4 Verified: let the build fail instead of production

The Enforcer catches both problems in `validate`, before compiling:

```xml
<requireUpperBoundDeps/>
<dependencyConvergence/>
```

**Output (verified):**

```text
[ERROR] Rule 2: org.apache.maven.enforcer.rules.dependency.RequireUpperBoundDeps failed with message:
[ERROR] Failed while enforcing RequireUpperBoundDeps. The error(s) are [
[ERROR] Require upper bound dependencies error for demo:common:1.0. Paths to dependency are:
[ERROR] +-demo:app:1.0
[ERROR]   +-demo:lib-a:1.0
[ERROR]     +-demo:common:1.0
[ERROR] and
[ERROR] +-demo:app:1.0
[ERROR]   +-demo:lib-b:1.0
[ERROR]     +-demo:lib-c:1.0
[ERROR]       +-demo:common:2.0
[ERROR] ]
[ERROR] Rule 3: org.apache.maven.enforcer.rules.dependency.DependencyConvergence failed with message:
[ERROR] Failed while enforcing releasability.
[ERROR]
[ERROR] Dependency convergence error for demo:common:jar:1.0. Paths to dependency are:
...
```

| Rule | Fails when… | Strictness |
|---|---|---|
| `requireUpperBoundDeps` | The resolved version is **lower** than some requested version (a silent downgrade) | ✅ Sensible default for applications |
| `dependencyConvergence` | **Any** two paths request different versions, even if the higher one won | Very strict. Big Spring/cloud SDK graphs rarely pass. Best for libraries or release profiles |

### 1.5 The fix: pin with `dependencyManagement`

```xml
<dependencyManagement>
  <dependencies>
    <!-- the fix: pin the converged version for the whole graph -->
    <dependency><groupId>demo</groupId><artifactId>common</artifactId><version>2.0</version></dependency>
  </dependencies>
</dependencyManagement>
```

**Output (verified):** `dependencyManagement` rewrites *transitive* versions too:

```text
[INFO] demo:app:jar:1.0
[INFO] +- demo:lib-a:jar:1.0:compile
[INFO] |  \- demo:common:jar:2.0:compile (version managed from 1.0)
[INFO] +- demo:lib-b:jar:1.0:compile
[INFO] |  \- demo:lib-c:jar:1.0:compile
[INFO] |     \- (demo:common:jar:2.0:compile - version managed from 2.0; omitted for duplicate)
```

The rule to say in the interview: **`dependencyManagement` beats nearest-wins.** Managed versions are applied while the graph is collected, before conflict resolution runs.

### 1.6 Scopes and transitivity (the table everyone gets wrong)

Rows: how *you* depend on X. Columns: how X depends on Y. Cell: the scope Y gets on *your* classpath.

| You → X ↓ \ X → Y → | `compile` | `provided` | `runtime` | `test` |
|---|---|---|---|---|
| `compile` | compile | — | runtime | — |
| `provided` | provided | — | provided | — |
| `runtime` | runtime | — | runtime | — |
| `test` | test | — | test | — |

Corollaries: `provided` and `test` dependencies of your dependencies **never** reach you. `<optional>true</optional>` stops transitivity as well. That's how libraries offer optional integrations (Jackson modules, Micrometer registries) without forcing them on you.

---

## 2. Duplicate classes: when the tree lies 🔥

A version conflict is *one GA, two versions*. A **duplicate class** is *two different GAs containing the same FQCN*. Common sources:

* relocated artifacts: `javax.*` vs `jakarta.*` copies, `bcprov-jdk15on` vs `bcprov-jdk18on`, `log4j` vs `reload4j`;
* uber-jars that bundle third-party classes without relocating them;
* split packages left over after a library was split into modules.

**No resolver can see this**, because the GAVs differ. Our lab adds `demo:fat-util:1.0`, which bundles a copy of `demo/common/Version.class` (the 1.0 one).

### 2.1 Verified: `banDuplicateClasses` catches it

```xml
<banDuplicateClasses><findAllDuplicates>true</findAllDuplicates></banDuplicateClasses>
```

**Output (verified):**

```text
[ERROR] Rule 4: org.codehaus.mojo.extraenforcer.dependencies.BanDuplicateClasses failed with message:
[ERROR] Duplicate classes found:
[ERROR]
[ERROR]   Found in:
[ERROR]     demo:common:jar:2.0:compile
[ERROR]     demo:fat-util:jar:1.0:compile
[ERROR]   Duplicate classes:
[ERROR]     demo/common/Version.class
```

### 2.2 Verified: classpath order decides what runs, and the tree can't tell you

With `common` **managed to 2.0** (so the tree looks perfect) and `fat-util` declared **first**:

**Output (verified, the classpath Maven produced, then the run):**

```text
classpath: fat-util-1.0.jar lib-a-1.0.jar common-2.0.jar lib-b-1.0.jar lib-c-1.0.jar
lib-a uses common-1.0
Exception in thread "main" java.lang.NoSuchMethodError: 'java.lang.String demo.common.Version.newApi()'
	at demo.c.LibC.hello(LibC.java:2)
```

`dependency:tree` says `common:2.0`, yet the JVM loaded the 1.0 `Version` from `fat-util`, because that jar comes first. Declare `fat-util` last and the same code works. **This is why duplicate classes must fail the build:** correctness would otherwise depend on an ordering the build tool doesn't promise to keep (see the Maven 3.10 note in [1.1 §7](01-Maven-Internals-Lifecycle-Mojos-Reactor.md)).

### 2.3 Diagnosing jar hell in a running system

| Symptom | Usual cause | First command |
|---|---|---|
| `NoSuchMethodError` / `NoSuchFieldError` | Compiled against version N+1, running N (downgrade or duplicate class) | `mvn dependency:tree -Dverbose -Dincludes=g:a` · `gradle dependencyInsight --dependency a` |
| `NoClassDefFoundError` (with a `ClassNotFoundException` cause) | Transitive dependency excluded or `optional`, or class removed in the chosen version | Check exclusions and optional flags |
| `AbstractMethodError` / `IncompatibleClassChangeError` | An interface or class shape changed between versions (e.g. a new method in an SPI) | Compare the API between versions |
| `ClassCastException: X cannot be cast to X` | **The same class loaded by two class loaders** (app server, plugin systems, devtools restart loader) | Print `X.class.getClassLoader()` on both sides |
| `LinkageError: loader constraint violation` | Two loaders disagree on a class used in a method signature | Same as above |

The one-liner that answers "**which jar did this class come from?**" in production:

```java
System.out.println(demo.common.Version.class.getProtectionDomain().getCodeSource().getLocation());
```

or, without code changes: `java -Xlog:class+load=info -jar app.jar | grep demo.common.Version`.

---

## 3. BOMs and the import order rule 🔥

A **BOM** (bill of materials) is a POM whose `dependencyManagement` lists mutually tested versions. Importing it (`<type>pom</type><scope>import</scope>`) copies those entries into your `dependencyManagement`.

Rules:

1. **Your own `dependencyManagement` entries beat imported ones.**
2. **Among imports, the first declaration of a GA wins.** Order your BOM imports from most specific to most general.
3. An imported BOM is interpolated with **its own** properties, never yours.

Rule 3 surprises almost everyone who leaves `spring-boot-starter-parent` for a corporate parent.

### 3.1 Verified: Spring Boot property overrides only work with the parent

Three POMs try to downgrade SLF4J from Boot 4.1.2's managed **2.0.20** to **2.0.17**:

```xml
<!-- A: inherit spring-boot-starter-parent, override with a property -->
<parent><groupId>org.springframework.boot</groupId><artifactId>spring-boot-starter-parent</artifactId><version>4.1.2</version></parent>
<properties><slf4j.version>2.0.17</slf4j.version></properties>

<!-- B: import spring-boot-dependencies, same property -->
<properties><slf4j.version>2.0.17</slf4j.version></properties>   <!-- silently IGNORED: imported BOMs are interpolated with their own properties -->
<dependencyManagement><dependencies>
  <dependency><groupId>org.springframework.boot</groupId><artifactId>spring-boot-dependencies</artifactId><version>4.1.2</version><type>pom</type><scope>import</scope></dependency>
</dependencies></dependencyManagement>

<!-- C: import, with the override BOM declared FIRST -->
<dependencyManagement><dependencies>
  <dependency><groupId>org.slf4j</groupId><artifactId>slf4j-bom</artifactId><version>2.0.17</version><type>pom</type><scope>import</scope></dependency>
  <dependency><groupId>org.springframework.boot</groupId><artifactId>spring-boot-dependencies</artifactId><version>4.1.2</version><type>pom</type><scope>import</scope></dependency>
</dependencies></dependencyManagement>
```

**Output (verified, resolved `slf4j-api` per POM):**

```text
== parent: org.slf4j:slf4j-api:jar:2.0.17:compile
== import: org.slf4j:slf4j-api:jar:2.0.20:compile
== import-fixed: org.slf4j:slf4j-api:jar:2.0.17:compile
```

**Why A works and B doesn't (first principles):** with inheritance, the parent's `dependencyManagement` becomes part of *your* model, and Maven interpolates `${slf4j.version}` against *your* merged properties. With `import`, Maven builds the BOM as a separate model (using the BOM's own properties) and copies in the already-resolved entries. Your property has no way in.

**Fix options when importing:** (C) put a more specific BOM *before* Boot's, or (D) add an explicit `dependencyManagement` entry for the artifact. Your own entries always beat imported ones.

### 3.2 Gradle: `platform()` vs `enforcedPlatform()` (verified)

Gradle consumes the same BOM through `platform()`. The difference from Maven: **a platform's versions are *constraints* that join conflict resolution. They are not overrides.**

Our lab BOM `demo:demo-bom:1.0` says `common = 1.0`, while `lib-c` needs 2.0.

**Output (verified, `gradle dependencies --configuration runtimeClasspath`):**

```text
=== mode=platform
+--- demo:lib-a:1.0
|    \--- demo:common:1.0 -> 2.0
+--- demo:lib-b:1.0
|    \--- demo:lib-c:1.0
|         \--- demo:common:2.0
\--- demo:demo-bom:1.0
     \--- demo:common:1.0 -> 2.0 (c)
=== mode=enforcedPlatform
+--- demo:lib-a:1.0
|    \--- demo:common:1.0
+--- demo:lib-b:1.0
|    \--- demo:lib-c:1.0
|         \--- demo:common:2.0 -> 1.0
\--- demo:demo-bom:{strictly 1.0} -> 1.0
     \--- demo:common:1.0 (c)
```

…and the forced downgrade fails exactly like Maven's nearest-wins:

**Output (verified, `gradle -Pmode=enforcedPlatform run`):**

```text
lib-a uses common-1.0
Exception in thread "main" java.lang.NoSuchMethodError: 'java.lang.String demo.common.Version.newApi()'
	at demo.c.LibC.hello(LibC.java:2)
```

| | Maven BOM import | Gradle `platform()` | Gradle `enforcedPlatform()` |
|---|---|---|---|
| Semantics | Overrides (managed versions win over nearest) | Recommendations; **highest still wins** | Strict: forces the BOM's version, **including downgrades** |
| Risk | Silent downgrades | Silent *upgrades* past the BOM | Silent downgrades |
| Publishing a library with it | Consumers see the BOM in the POM | Fine | ❌ Avoid: it forces versions on *your consumers* |

---

## 4. Gradle: highest version wins, plus rich versions 🔥

### 4.1 Verified: same graph, opposite answer

**Output (verified, the lab with no BOM):**

```text
runtimeClasspath - Runtime classpath of source set 'main'.
+--- demo:lib-a:1.0
|    \--- demo:common:1.0 -> 2.0
\--- demo:lib-b:1.0
     \--- demo:lib-c:1.0
          \--- demo:common:2.0
```

The app runs:

```text
lib-a uses common-2.0
lib-b -> lib-c calls newApi() from common-2.0
```

`dependencyInsight` explains *why*:

**Output (verified, trimmed):**

```text
demo:common:2.0
   Selection reasons:
      - By conflict resolution: between versions 2.0 and 1.0

demo:common:2.0
\--- demo:lib-c:1.0
     \--- demo:lib-b:1.0
          \--- runtimeClasspath

demo:common:1.0 -> 2.0
\--- demo:lib-a:1.0
     \--- runtimeClasspath
```

**Is "highest wins" safer?** Usually, because libraries tend to stay backward compatible across minors. But it can silently **upgrade across a major** (2.x → 3.x with removed methods), and then `lib-a` gets the `NoSuchMethodError` instead. Neither strategy removes the need for conflict *visibility*.

### 4.2 Rich versions and conflict policies (verified)

```kotlin
val mode = providers.gradleProperty("mode").getOrElse("default")

dependencies {
    implementation("demo:lib-a:1.0")   // -> common 1.0
    implementation("demo:lib-b:1.0")   // -> lib-c -> common 2.0
    when (mode) {
        "platform"         -> implementation(platform("demo:demo-bom:1.0"))          // BOM says common 1.0 (a recommendation)
        "enforcedPlatform" -> implementation(enforcedPlatform("demo:demo-bom:1.0"))  // BOM says common 1.0 (forced)
        "strictly"         -> implementation("demo:common") { version { strictly("1.0") } }
        "require"          -> implementation("demo:common") { version { require("1.0") } }
    }
}

if (mode == "fail") {
    configurations.configureEach { resolutionStrategy.failOnVersionConflict() }
}
```

**Output (verified):**

```text
=== mode=strictly
|         \--- demo:common:2.0 -> 1.0
\--- demo:common:{strictly 1.0} -> 1.0
=== mode=require
\--- demo:common:1.0 -> 2.0
=== mode=fail
+--- demo:lib-a:1.0
|    \--- demo:common:1.0 FAILED
\--- demo:lib-b:1.0
     \--- demo:lib-c:1.0
          \--- demo:common:2.0 FAILED
```

and the build error for `fail`:

```text
> Could not resolve all files for configuration ':compileClasspath'.
   > Could not resolve demo:common:1.0.
     Required by:
         root project 'gradle-app' > demo:lib-a:1.0
      > Conflict found for module 'demo:common': between versions 2.0 and 1.0
```

| Rich version | Meaning | Use |
|---|---|---|
| `require("1.0")` (the default for `"g:a:1.0"`) | "At least this, upgrades allowed" | Normal declarations |
| `strictly("1.0")` | "Exactly this", downgrades allowed, fails if something else is also strict | Pinning a known-good version, CVE rollbacks |
| `prefer("1.0")` | Used only if nothing else expresses an opinion | Soft defaults in platforms |
| `reject("1.3.2")` | Never select this version | Known-bad releases |
| `failOnVersionConflict()` | Every conflict is an error | Libraries, strict platforms |

### 4.3 Other Gradle tools you should be able to name 🧊

* **Constraints** (`constraints { implementation("g:a:2.0") }`): version opinions that only apply *if* the module shows up in the graph. This is how a platform works internally.
* **Capabilities**: two different GAs that provide the *same thing* (e.g. `log4j:log4j` vs `ch.qos.reload4j:reload4j`). Declare the capability and Gradle detects the conflict that Maven can't see at all, then `capabilitiesResolution { … selectHighestVersion() }` picks one.
* **Component metadata rules**: fix broken third-party POMs, for example by adding a missing capability or dropping an unwanted transitive dependency.
* **Dependency locking** (`dependencyLocking { lockAllConfigurations() }` + `--write-locks`): writes `gradle.lockfile` so applications resolve the same graph until someone deliberately updates it.
* **Dependency verification** (`gradle/verification-metadata.xml`): checksums and signatures for every artifact. It's supply-chain protection Maven doesn't have built in.

---

## 5. Version catalogs: aliases, not resolution 🔥

`gradle/libs.versions.toml` (excerpt from the verified blueprint in [1.4](04-Enterprise-Builds-OCI-Images-Annotation-Processors-Enforcer.md)):

```toml
[versions]
spring-boot = "4.1.2"
mapstruct = "1.6.3"

[libraries]
spring-boot-bom = { module = "org.springframework.boot:spring-boot-dependencies", version.ref = "spring-boot" }
spring-boot-starter-web = { module = "org.springframework.boot:spring-boot-starter-web" }   # version from the BOM
mapstruct = { module = "org.mapstruct:mapstruct", version.ref = "mapstruct" }

[bundles]
web-service = ["spring-boot-starter-web", "spring-boot-starter-actuator", "spring-boot-starter-validation"]

[plugins]
spring-boot = { id = "org.springframework.boot", version.ref = "spring-boot" }
```

```kotlin
dependencies {
    implementation(platform(libs.spring.boot.bom))
    implementation(libs.bundles.web.service)
    implementation(libs.mapstruct)
}
```

**A catalog is not a platform.** Interviewers like this distinction:

| | Version catalog | Platform / BOM |
|---|---|---|
| What it is | Build-time **aliases** (type-safe accessors), a single place to *write* versions | **Resolution constraints** that take part in conflict resolution |
| Affects transitive dependencies? | **No.** It only fills in versions where you use the alias | **Yes** |
| Published to consumers? | No (unless you publish the catalog separately) | Yes, as a POM/BOM |
| Use together? | ✅ Catalog entry for the BOM, then `platform(libs.x.bom)` | |

---

## 6. Shading and relocation: the last resort ⚡

When two parts of one application **need incompatible majors** of the same library (and upgrading the old caller isn't possible), you can **relocate** one copy into a private package. Bytecode references are rewritten, so the two copies stop colliding.

### 6.1 Verified with `maven-shade-plugin`

```xml
<plugin>
  <artifactId>maven-shade-plugin</artifactId>
  <version>3.6.2</version>
  <executions>
    <execution>
      <phase>package</phase>
      <goals><goal>shade</goal></goals>
      <configuration>
        <artifactSet><includes><include>demo:lib-c</include><include>demo:common</include></includes></artifactSet>
        <relocations>
          <relocation>
            <pattern>demo.common</pattern>
            <shadedPattern>demo.c.shaded.common</shadedPattern>
          </relocation>
        </relocations>
        <createDependencyReducedPom>true</createDependencyReducedPom>
      </configuration>
    </execution>
  </executions>
</plugin>
```

**Output (verified):** the shaded jar's contents, the rewritten call site, and the reduced POM:

```text
      779  2026-01-01 00:00   demo/c/LibC.class
      375  2026-01-01 00:00   demo/c/shaded/common/Version.class
--- dependency-reduced-pom deps:
0
         0: invokestatic  #21                 // Method demo/c/shaded/common/Version.newApi:()Ljava/lang/String;
```

An app that depends on `lib-a` (→ `common:1.0`) **and** the shaded `lib-c` now runs both:

**Output (verified):**

```text
[INFO] demo:shade-app:jar:1.0
[INFO] +- demo:lib-a:jar:1.0:compile
[INFO] |  \- demo:common:jar:1.0:compile
[INFO] \- demo:lib-c-shaded:jar:1.0:compile
lib-a uses common-1.0
lib-c calls newApi() from common-2.0
```

### 6.2 Verified with Gradle Shadow

```kotlin
plugins {
    `java-library`
    id("com.gradleup.shadow") version "9.6.1"
}

dependencies {
    implementation("demo:lib-c:1.0")          // brings demo:common:2.0
}

tasks.shadowJar {
    archiveClassifier = ""                    // publish the shaded jar as THE jar
    relocate("demo.common", "demo.c.shaded.common")
    mergeServiceFiles()                       // rewrite META-INF/services entries for relocated providers
}
```

**Output (verified, jar contents and the rewritten call):**

```text
      779  1980-02-01 00:00   demo/c/LibC.class
      375  1980-02-01 00:00   demo/c/shaded/common/Version.class
         0: invokestatic  #21                 // Method demo/c/shaded/common/Version.newApi:()Ljava/lang/String;
```

### 6.3 Shading's hidden costs (what a staff engineer adds)

| Cost | Why | Mitigation |
|---|---|---|
| **Reflection and string-based lookups break** | Relocation rewrites constant-pool references, not strings in config files, `Class.forName("demo.common.X")` or XML | `ServicesResourceTransformer` / `mergeServiceFiles()`; audit for `forName` |
| **Vulnerability scanners go blind** | The CVE-laden library now hides in your jar under another package name | Generate an SBOM (CycloneDX) *before* shading, or use scanners that fingerprint classes |
| Bigger artifacts, duplicated memory | Two copies of the library are loaded | Shade only the conflicting packages (`artifactSet` includes) |
| Licensing | You are now *redistributing* the library | Keep NOTICE/LICENSE files (Apache transformers) |
| Debugging | Stack traces show `shaded.*` packages | Keep relocation prefixes recognizable |

**Rule of thumb:** *libraries* shade (Kafka clients, Elasticsearch, Hadoop do it) so they don't impose versions on users. *Applications* should almost never need to. If you're shading in an app, first try upgrading the old caller, excluding the dependency, or isolating it in a separate class loader or process.

---

## 6.5 What your library's consumers actually get: `api` vs `implementation`, and "used undeclared" (verified) 🔥

Two verified facts from [1.6](06-Build-Script-Blueprints-Platform-Publishing-Quality-Gates-CI.md), where a Gradle-built library (`acme-core`, `api("org.slf4j:slf4j-api")`, `implementation("com.zaxxer:HikariCP")`) was consumed by a Maven service and a Gradle service:

**1. Gradle's dependency configurations become Maven scopes in the published POM.**

```xml
<dependency><groupId>org.slf4j</groupId><artifactId>slf4j-api</artifactId><scope>compile</scope></dependency>
<dependency><groupId>com.zaxxer</groupId><artifactId>HikariCP</artifactId><scope>runtime</scope></dependency>
```

A Maven consumer then **can't compile** against HikariCP (`package com.zaxxer.hikari does not exist`), and a Gradle consumer's `compileClasspath` doesn't contain it. That is the encapsulation you want: the library can replace an `implementation` dependency in a minor release. Put a dependency in `api` only if its types appear in your public signatures (`public Logger log()` here). Everything in `api` is a promise.

**2. "It compiles" can mean "it compiles against a version nobody chose".** `mvn dependency:analyze` on a module that used slf4j without declaring it:

```text
[ERROR] Used undeclared dependencies found:
[ERROR]    org.slf4j:slf4j-api:jar:2.0.17:compile
[ERROR] Unused declared dependencies found:
[ERROR]    com.zaxxer:HikariCP:jar:7.0.2:compile
```

The code compiled against slf4j **2.0.17** only because HikariCP happened to bring it. Upgrade or remove HikariCP and the code's slf4j version changes silently, or it stops compiling. Rule: **declare what you import**; enforce it with `dependency:analyze` (`failOnWarning`) in Maven and the dependency-analysis plugin in Gradle, minus the known aggregator false positives (`junit-jupiter`, Boot starters).

## 7. ❌ Naïve vs ✅ production-hardened dependency hygiene

| ❌ Naïve | ✅ Hardened |
|---|---|
| Trust `mvn dependency:tree` and ship | `requireUpperBoundDeps` + `banDuplicateClasses` in `validate`; `failOnVersionConflict` or locking in Gradle |
| Add `<exclusions>` until it compiles | Exclude deliberately, with a comment and a test that hits the code path |
| Override a BOM-managed version with a property after switching to BOM import | Override BOM first, or an explicit `dependencyManagement` entry (§3.1) |
| `enforcedPlatform()` in a published library | `platform()` in libraries; `enforcedPlatform()` only in leaf applications, knowingly |
| Version catalog treated as "the place that controls transitive versions" | Catalog for aliases, platform/BOM for resolution |
| Shading inside an application | Upgrade, exclude, or isolate. Shade in libraries only, with an SBOM |
| CVE fixed by bumping a transitive version once | Pin through `dependencyManagement`/constraints, add a `reject` for the bad version, let Renovate/Dependabot keep it current |

---

## 8. GitHub source to read

| Repo | Path / class | What to look for |
|---|---|---|
| [apache/maven-resolver](https://github.com/apache/maven-resolver) | `maven-resolver-util/src/main/java/org/eclipse/aether/util/graph/transformer/NearestVersionSelector.java` | The "nearest wins, first declared on ties" logic |
| apache/maven-resolver | `maven-resolver-util/src/main/java/org/eclipse/aether/util/graph/transformer/ConflictResolver.java` | How the selectors plug in |
| apache/maven-resolver | `maven-resolver-impl/src/main/java/org/eclipse/aether/internal/impl/collect/bf/BfDependencyCollector.java` | The breadth-first graph collector (selectable with `-Daether.dependencyCollector.impl=bf\|df`) and its parallel POM downloads |
| [apache/maven-enforcer](https://github.com/apache/maven-enforcer) | `enforcer-rules/src/main/java/org/apache/maven/enforcer/rules/dependency/RequireUpperBoundDeps.java` | Upper-bound detection on the verbose graph |
| [mojohaus/extra-enforcer-rules](https://github.com/mojohaus/extra-enforcer-rules) | `src/main/java/org/codehaus/mojo/extraenforcer/dependencies/BanDuplicateClasses.java` | Scanning jars for identical class entries |
| [gradle/gradle](https://github.com/gradle/gradle) | `org.gradle.api.internal.artifacts.ivyservice.resolveengine.graph.conflicts.DefaultModuleConflictHandler` | Gradle's module conflict handling |
| gradle/gradle | `org.gradle.api.internal.artifacts.ivyservice.resolveengine.LatestModuleConflictResolver` | "Highest wins" |
| [apache/maven-shade-plugin](https://github.com/apache/maven-shade-plugin) | `src/main/java/org/apache/maven/plugins/shade/relocation/SimpleRelocator.java` | What relocation rewrites, and what it can't |

---

## 9. Interview soundbites

* "The classpath is flat: one FQCN, first jar wins. So a build tool must pick one version per module, and the failure only shows up when the JVM links the call."
* "Maven picks the nearest declaration and breaks ties by declaration order. Gradle picks the highest version. Both can be wrong, so I make conflicts fail the build: `requireUpperBoundDeps` and `banDuplicateClasses` in Maven, `failOnVersionConflict` or locking in Gradle."
* "`dependencyManagement` beats nearest-wins, including for transitive dependencies."
* "If you import Spring Boot's BOM instead of inheriting its parent, version properties are ignored. You override by importing a more specific BOM first."
* "A Gradle `platform()` is a set of constraints; `enforcedPlatform()` forces versions, including downgrades. A version catalog is just aliases and doesn't touch transitive resolution."
* "Shading is for libraries. It hides the dependency from scanners, so I pair it with an SBOM."
* "`implementation` becomes runtime scope in the published POM: our Maven consumer couldn't compile against HikariCP, which is the point. And `dependency:analyze` found code compiling against an slf4j version that only arrived transitively."

---

## Summary

| Mechanism | Rule | Verified evidence |
|---|---|---|
| Flat classpath | One class name, first jar wins; failures appear at link time (`NoSuchMethodError`) | §1.2 |
| Maven mediation | Nearest wins; ties broken by declaration order | §1.2–1.3 |
| Making conflicts fail | `requireUpperBoundDeps`, `dependencyConvergence`, `banDuplicateClasses` | §1.4, §2.1 |
| `dependencyManagement` | Beats nearest-wins, transitively too | §1.5 |
| Scopes | compile / provided / runtime / test transitivity table | §1.6 |
| BOM import order | First import wins; Boot properties only work with the parent | §3.1 |
| Gradle resolution | Highest version wins; rich versions; `platform` vs `enforcedPlatform` | §3.2, §4 |
| Version catalogs | Aliases only, no effect on transitive resolution | §5 |
| Shading | Relocation for libraries; hides dependencies from scanners | §6 |
| `api` vs `implementation` | compile vs runtime scope in the published POM | Maven consumer compile error (§6.5) |
| Used-undeclared dependencies | Versions nobody chose | slf4j 2.0.17 via HikariCP (§6.5) |

**Next:** [1.4 Enterprise builds, OCI images and blueprints →](04-Enterprise-Builds-OCI-Images-Annotation-Processors-Enforcer.md)
