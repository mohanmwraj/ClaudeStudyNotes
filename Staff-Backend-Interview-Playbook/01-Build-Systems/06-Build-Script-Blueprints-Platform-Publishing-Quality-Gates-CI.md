# 1.6 Build-Script Blueprints II: A Published Platform (BOM + Version Catalog + Library), Maven and Gradle Consumers, Quality Gates, and CI

> **Verified stack:** Gradle **9.8.2** and Maven **3.10.0** on JDK 25 (Temurin 25.0.4.1), Spring Boot BOM 4.1.2, JUnit 6.0.3, JaCoCo 0.8.14, maven-dependency-plugin 3.11.0, surefire/failsafe 3.5.4, enforcer 3.6.3. Every build in this file was run; outputs are copied from the console. The CI workflow in §5 is a reference and was **not** executed here (no CI runner on this laptop).
>
> **Complements** [1.4 Blueprints A and B](04-Enterprise-Builds-OCI-Images-Annotation-Processors-Enforcer.md) (a hardened multi-module service in Maven and in Gradle). This file adds what large organizations need on top: **one platform that many repositories consume, in either build tool**, and **gates** that fail the build before review does.

---

## 0. First principles: a platform is a contract between repositories 🔥

In a single repository, `dependencyManagement` or a version catalog keeps modules consistent. Across 50 repositories, every team picking its own Spring Boot, PostgreSQL driver and HikariCP versions means 50 combinations to patch when a CVE lands. A **platform** turns "which versions do we run?" into one artifact that every build imports:

| Artifact | What it carries | Consumed by |
|---|---|---|
| **BOM** (`acme-bom`, a POM with `dependencyManagement`) | Version **constraints**, including an imported Spring Boot BOM | Maven (`<scope>import</scope>`) and Gradle (`platform(...)`) |
| **Version catalog** (`acme-catalog`, a TOML) | **Aliases** for coordinates and plugin ids (`acme.postgresql`) | Gradle only |
| **Libraries** (`acme-core`) | Shared code, with an honest public API (`api`) vs internal (`implementation`) split | Both |

The catalog says *what to call things*; the BOM says *which version wins* ([1.3 §5](03-Dependency-Resolution-Jar-Hell-BOMs-Catalogs-Shading.md)). Publish both from one place so they can't disagree.

---

## 1. Blueprint C: the platform build (Gradle) ⚡

```text
platform-gradle/
├── settings.gradle.kts          central repositories, module list
├── gradle.properties            group, version, caches on
├── build.gradle.kts             (empty on purpose: no allprojects/subprojects)
├── bom/build.gradle.kts         java-platform  → acme-bom (POM + Gradle module metadata)
├── catalog/build.gradle.kts     version-catalog → acme-catalog (TOML)
└── acme-core/build.gradle.kts   java-library   → acme-core (jar, sources jar, POM, .module)
```

### 1.1 `settings.gradle.kts`

```kotlin
rootProject.name = "acme-platform"

dependencyResolutionManagement {
    repositoriesMode = RepositoriesMode.FAIL_ON_PROJECT_REPOS     // one place for repositories; a module can't add its own
    repositories { mavenCentral() }
}

include("bom", "catalog", "acme-core")
```

The first run without this block failed with `Cannot resolve external dependency org.slf4j:slf4j-api because no repositories are defined.` In Gradle 9 the right place for repositories is `settings`, not every project.

### 1.2 `gradle.properties`

```properties
group=com.acme
version=1.4.0
org.gradle.configuration-cache=true
org.gradle.caching=true
org.gradle.parallel=true
```

### 1.3 `bom/build.gradle.kts`: the BOM

```kotlin
plugins {
    `java-platform`
    `maven-publish`
}

javaPlatform { allowDependencies() }            // lets the BOM import another BOM (Spring Boot's)

dependencies {
    api(platform("org.springframework.boot:spring-boot-dependencies:4.1.2"))
    constraints {
        api("org.postgresql:postgresql:42.7.14")           // our pins on top of Boot's
        api("com.zaxxer:HikariCP:7.0.2")
        api(project(":acme-core"))                         // the platform also pins our own libraries
    }
}

publishing {
    publications { create<MavenPublication>("bom") { artifactId = "acme-bom"; from(components["javaPlatform"]) } }
    repositories { maven { name = "acme"; url = uri(rootProject.layout.projectDirectory.dir("../repo")) } }
}
```

### 1.4 `catalog/build.gradle.kts`: the version catalog

```kotlin
plugins {
    `version-catalog`
    `maven-publish`
}

catalog {
    versionCatalog {
        version("spring-boot", "4.1.2")
        library("postgresql", "org.postgresql", "postgresql").version("42.7.14")
        library("hikari", "com.zaxxer", "HikariCP").version("7.0.2")
        library("acme-core", "com.acme", "acme-core").version("1.4.0")
        library("acme-bom", "com.acme", "acme-bom").version("1.4.0")
        plugin("spring-boot", "org.springframework.boot").versionRef("spring-boot")
    }
}

publishing {
    publications { create<MavenPublication>("catalog") { artifactId = "acme-catalog"; from(components["versionCatalog"]) } }
    repositories { maven { name = "acme"; url = uri(rootProject.layout.projectDirectory.dir("../repo")) } }
}
```

### 1.5 `acme-core/build.gradle.kts`: a library with an honest API

```kotlin
plugins {
    `java-library`
    `maven-publish`
}

java { withSourcesJar() }

tasks.withType<JavaCompile>().configureEach { options.release = 25 }
tasks.withType<AbstractArchiveTask>().configureEach {       // byte-for-byte reproducible jars
    isPreserveFileTimestamps = false
    isReproducibleFileOrder = true
}

dependencies {
    implementation(platform(project(":bom")))
    api("org.slf4j:slf4j-api")                 // part of our public API (we expose org.slf4j.Logger): consumers compile against it
    implementation("com.zaxxer:HikariCP")      // internal detail: consumers get it at runtime only
}

publishing {
    publications { create<MavenPublication>("lib") { from(components["java"]) } }
    repositories { maven { name = "acme"; url = uri(rootProject.layout.projectDirectory.dir("../repo")) } }
}
```

```java
public final class Pools {
    private static final Logger LOG = LoggerFactory.getLogger(Pools.class);
    public static Logger log() { return LOG; }                          // slf4j type in the public API → `api`
    public static int recommendedPoolSize(int cores, int spindles) {    // HikariCP used only inside → `implementation`
        HikariConfig cfg = new HikariConfig();
        cfg.setMaximumPoolSize(cores * 2 + spindles);
        return cfg.getMaximumPoolSize();
    }
}
```

`bom` constrains `acme-core`, and `acme-core` depends on `platform(:bom)`: that cycle is the intended pattern (constraints aren't dependencies), and Gradle resolved it.

### 1.6 What `gradle publish` produced (verified)

```text
com/acme/acme-bom/1.4.0/acme-bom-1.4.0.module
com/acme/acme-bom/1.4.0/acme-bom-1.4.0.pom
com/acme/acme-catalog/1.4.0/acme-catalog-1.4.0.module
com/acme/acme-catalog/1.4.0/acme-catalog-1.4.0.pom
com/acme/acme-catalog/1.4.0/acme-catalog-1.4.0.toml
com/acme/acme-core/1.4.0/acme-core-1.4.0.module
com/acme/acme-core/1.4.0/acme-core-1.4.0.pom
(+ acme-core-1.4.0.jar, -sources.jar, and .md5/.sha1/.sha256/.sha512 for every file)
```

**The generated `acme-bom-1.4.0.pom` (verified excerpt):**

```xml
<dependencyManagement>
  <dependencies>
    <dependency><groupId>org.postgresql</groupId><artifactId>postgresql</artifactId><version>42.7.14</version></dependency>
    <dependency><groupId>com.zaxxer</groupId><artifactId>HikariCP</artifactId><version>7.0.2</version></dependency>
    <dependency><groupId>com.acme</groupId><artifactId>acme-core</artifactId><version>1.4.0</version></dependency>
    <dependency>
      <groupId>org.springframework.boot</groupId><artifactId>spring-boot-dependencies</artifactId><version>4.1.2</version>
      <type>pom</type><scope>import</scope>
    </dependency>
  </dependencies>
</dependencyManagement>
```

**The generated `acme-core-1.4.0.pom` (verified excerpt):**

```xml
<dependencyManagement>
  <dependencies>
    <dependency><groupId>com.acme</groupId><artifactId>acme-bom</artifactId><version>1.4.0</version><type>pom</type><scope>import</scope></dependency>
  </dependencies>
</dependencyManagement>
<dependencies>
  <dependency><groupId>org.slf4j</groupId><artifactId>slf4j-api</artifactId><scope>compile</scope></dependency>
  <dependency><groupId>com.zaxxer</groupId><artifactId>HikariCP</artifactId><scope>runtime</scope></dependency>
</dependencies>
```

**The generated `acme-catalog-1.4.0.toml` (verified):**

```toml
[versions]
spring-boot = "4.1.2"

[libraries]
acme-bom = {group = "com.acme", name = "acme-bom", version = "1.4.0" }
acme-core = {group = "com.acme", name = "acme-core", version = "1.4.0" }
hikari = {group = "com.zaxxer", name = "HikariCP", version = "7.0.2" }
postgresql = {group = "org.postgresql", name = "postgresql", version = "42.7.14" }

[plugins]
spring-boot = {id = "org.springframework.boot", version.ref = "spring-boot" }
```

The translation rules worth memorizing:

| In the Gradle build | In the published POM |
|---|---|
| `constraints { api(...) }` in a `java-platform` | `<dependencyManagement>` entries |
| `api(platform(otherBom))` in a platform | `<scope>import</scope>` of that BOM |
| `api(...)` in a `java-library` | `<scope>compile</scope>` |
| `implementation(...)` | `<scope>runtime</scope>` |
| `implementation(platform(...))` | An imported BOM in the library's `<dependencyManagement>` (versionless dependencies resolve for Maven consumers) |

Gradle consumers read the richer `.module` file (Gradle Module Metadata) instead of the POM, so they also get variants and capabilities the POM can't express.

---

## 2. Blueprint D: consuming the platform from Maven and from Gradle (verified) 🔥

### 2.1 A Maven service importing the Gradle-built BOM

```xml
<repositories>
  <repository><id>acme</id><url>file:///…/repo</url></repository>       <!-- a repository manager in real life -->
</repositories>
<dependencyManagement>
  <dependencies>
    <dependency>                                    <!-- the BOM a Gradle build published -->
      <groupId>com.acme</groupId><artifactId>acme-bom</artifactId><version>1.4.0</version>
      <type>pom</type><scope>import</scope>
    </dependency>
  </dependencies>
</dependencyManagement>
<dependencies>
  <dependency><groupId>com.acme</groupId><artifactId>acme-core</artifactId></dependency>        <!-- no version: from the BOM -->
  <dependency><groupId>org.postgresql</groupId><artifactId>postgresql</artifactId></dependency> <!-- no version: from the BOM -->
</dependencies>
```

**Output (verified, `mvn dependency:tree`, Maven 3.10.0):**

```text
[INFO] com.acme:billing-service:jar:1.0.0-SNAPSHOT
[INFO] +- com.acme:acme-core:jar:1.4.0:compile
[INFO] |  +- org.slf4j:slf4j-api:jar:2.0.20:compile
[INFO] |  \- com.zaxxer:HikariCP:jar:7.0.2:runtime
[INFO] \- org.postgresql:postgresql:jar:42.7.14:compile
[INFO]    \- org.checkerframework:checker-qual:jar:3.55.1:runtime
```

* Versions came from the chain `acme-bom` → its imported `spring-boot-dependencies` (slf4j 2.0.20).
* HikariCP is **runtime** for the Maven consumer, exactly as declared with `implementation`. Code that tries to use it anyway doesn't compile:

```text
[ERROR] /…/consumer-maven/src/main/java/com/acme/billing/DirectPool.java:[3,25] package com.zaxxer.hikari does not exist
[ERROR] BUILD FAILURE
```

That's the point of `api` vs `implementation`: acme-core can swap HikariCP for something else in a minor release without breaking a single consumer's compilation.

### 2.2 A Gradle service using the published catalog

```kotlin
// settings.gradle.kts
dependencyResolutionManagement {
    repositoriesMode = RepositoriesMode.FAIL_ON_PROJECT_REPOS
    repositories {
        maven { url = uri("file:///…/repo"); content { includeGroup("com.acme") } }   // internal repo serves ONLY com.acme
        mavenCentral { content { excludeGroup("com.acme") } }                   // and Central never does (dependency confusion)
    }
    versionCatalogs { create("acme") { from("com.acme:acme-catalog:1.4.0") } }  // the catalog a Gradle build published
}

// build.gradle.kts
plugins { java }
dependencies {
    implementation(platform(acme.acme.bom))
    implementation(acme.acme.core)
    runtimeOnly(acme.postgresql)
}
```

**Output (verified, `gradle dependencies --configuration compileClasspath`):**

```text
compileClasspath - Compile classpath for source set 'main'.
+--- com.acme:acme-bom:1.4.0
|    +--- org.springframework.boot:spring-boot-dependencies:4.1.2
|    |    \--- org.slf4j:slf4j-api:2.0.20 (c)
|    \--- com.acme:acme-core:1.4.0 (c)
\--- com.acme:acme-core:1.4.0
     \--- org.slf4j:slf4j-api -> 2.0.20
```

**Output (verified, `--configuration runtimeClasspath`, excerpt):**

```text
+--- com.acme:acme-core:1.4.0
|    +--- com.acme:acme-bom:1.4.0 (*)
|    +--- com.zaxxer:HikariCP -> 7.0.2
|    |    \--- org.slf4j:slf4j-api:2.0.17 -> 2.0.20
|    \--- org.slf4j:slf4j-api -> 2.0.20
\--- org.postgresql:postgresql:42.7.14
```

* HikariCP is **absent from the compile classpath** and present at runtime. `(c)` marks a constraint contributed by the platform.
* HikariCP itself asks for slf4j **2.0.17**; the platform raised it to **2.0.20** (`2.0.17 -> 2.0.20`). That's the BOM doing its job for transitive dependencies too.
* `content { includeGroup("com.acme") }` / `excludeGroup` makes the internal repository the **only** source of `com.acme` artifacts: an attacker publishing `com.acme:acme-core:99.0` to Central can't win resolution (dependency confusion).

---

## 3. Blueprint E: a Maven build that refuses bad code (verified) 🔥

One module, five gates, all bound to `mvn verify`:

```xml
<properties>
  <maven.compiler.release>25</maven.compiler.release>
  <project.build.sourceEncoding>UTF-8</project.build.sourceEncoding>
  <project.build.outputTimestamp>2026-01-01T00:00:00Z</project.build.outputTimestamp>   <!-- reproducible jars -->
  <coverage.minimum>0.80</coverage.minimum>
</properties>

<dependencies>
  <dependency><groupId>org.slf4j</groupId><artifactId>slf4j-api</artifactId><version>2.0.20</version></dependency>
  <dependency><groupId>org.junit.jupiter</groupId><artifactId>junit-jupiter-api</artifactId><version>6.0.3</version><scope>test</scope></dependency>
  <dependency><groupId>org.junit.jupiter</groupId><artifactId>junit-jupiter-params</artifactId><version>6.0.3</version><scope>test</scope></dependency>
  <dependency><groupId>org.junit.jupiter</groupId><artifactId>junit-jupiter-engine</artifactId><version>6.0.3</version><scope>test</scope></dependency>
</dependencies>

<build>
  <plugins>
    <plugin>                                                     <!-- gate 1: toolchain and dependency sanity -->
      <groupId>org.apache.maven.plugins</groupId><artifactId>maven-enforcer-plugin</artifactId><version>3.6.3</version>
      <executions><execution><id>enforce</id><goals><goal>enforce</goal></goals>
        <configuration><rules>
          <requireMavenVersion><version>[3.9.0,)</version></requireMavenVersion>
          <requireJavaVersion><version>[25,)</version></requireJavaVersion>
          <dependencyConvergence/>
          <banDuplicatePomDependencyVersions/>
        </rules></configuration>
      </execution></executions>
    </plugin>
    <plugin>                                                     <!-- gate 2: unit tests (*Test) in phase test -->
      <groupId>org.apache.maven.plugins</groupId><artifactId>maven-surefire-plugin</artifactId><version>3.5.4</version>
    </plugin>
    <plugin>                                                     <!-- gate 3: integration tests (*IT), fail in verify -->
      <groupId>org.apache.maven.plugins</groupId><artifactId>maven-failsafe-plugin</artifactId><version>3.5.4</version>
      <executions><execution><goals><goal>integration-test</goal><goal>verify</goal></goals></execution></executions>
    </plugin>
    <plugin>                                                     <!-- gate 4: coverage -->
      <groupId>org.jacoco</groupId><artifactId>jacoco-maven-plugin</artifactId><version>0.8.14</version>
      <executions>
        <execution><id>agent</id><goals><goal>prepare-agent</goal></goals></execution>
        <execution><id>report</id><phase>verify</phase><goals><goal>report</goal></goals></execution>
        <execution><id>gate</id><phase>verify</phase><goals><goal>check</goal></goals>
          <configuration><rules><rule><element>BUNDLE</element><limits>
            <limit><counter>LINE</counter><value>COVEREDRATIO</value><minimum>${coverage.minimum}</minimum></limit>
            <limit><counter>BRANCH</counter><value>COVEREDRATIO</value><minimum>0.70</minimum></limit>
          </limits></rule></rules></configuration>
        </execution>
      </executions>
    </plugin>
    <plugin>                                                     <!-- gate 5: declared == used -->
      <groupId>org.apache.maven.plugins</groupId><artifactId>maven-dependency-plugin</artifactId><version>3.11.0</version>
      <executions><execution><id>analyze</id><phase>verify</phase><goals><goal>analyze-only</goal></goals>
        <configuration>
          <failOnWarning>true</failOnWarning>
          <ignoredUnusedDeclaredDependencies>
            <ignoredUnusedDeclaredDependency>org.junit.jupiter:junit-jupiter-engine</ignoredUnusedDeclaredDependency>  <!-- runtime-only by design -->
          </ignoredUnusedDeclaredDependencies>
        </configuration>
      </execution></executions>
    </plugin>
  </plugins>
</build>
```

### 3.1 The order Maven actually ran (verified, `mvn clean verify`)

```text
--- clean:3.5.0:clean (default-clean) @ pricing ---
--- enforcer:3.6.3:enforce (enforce) @ pricing ---
--- jacoco:0.8.14:prepare-agent (agent) @ pricing ---
--- resources:3.5.0:resources (default-resources) @ pricing ---
--- compiler:3.16.0:compile (default-compile) @ pricing ---
--- resources:3.5.0:testResources (default-testResources) @ pricing ---
--- compiler:3.16.0:testCompile (default-testCompile) @ pricing ---
--- surefire:3.5.4:test (default-test) @ pricing ---
--- jar:3.5.1:jar (default-jar) @ pricing ---
--- failsafe:3.5.4:integration-test (default) @ pricing ---
--- failsafe:3.5.4:verify (default) @ pricing ---
--- jacoco:0.8.14:report (report) @ pricing ---
--- jacoco:0.8.14:check (gate) @ pricing ---
--- dependency:3.11.0:analyze-only (analyze) @ pricing ---
```

* `prepare-agent` runs in `initialize` and sets the `argLine` property that **both** surefire and failsafe use, so unit tests and ITs write to the same `jacoco.exec` and coverage counts both.
* Failsafe's `integration-test` never fails the build itself (so post-integration cleanup can run); its `verify` goal does.
* Gates in `verify` run in declaration order **within the phase**: JaCoCo report → check → analyze ([1.1 §2.3](01-Maven-Internals-Lifecycle-Mojos-Reactor.md)).

### 3.2 Gate 4 failing: one test, half the branches (verified)

```text
[INFO] Tests run: 1, Failures: 0, Errors: 0, Skipped: 0, Time elapsed: 0.083 s -- in com.acme.pricing.DiscountTest
[INFO] Tests run: 1, Failures: 0, Errors: 0, Skipped: 0, Time elapsed: 0.077 s -- in com.acme.pricing.PricingIT
[WARNING] Rule violated for bundle pricing: branches covered ratio is 0.50, but expected minimum is 0.70
[ERROR] Failed to execute goal org.jacoco:jacoco-maven-plugin:0.8.14:check (gate) on project pricing: Coverage checks have not been met.
```

Line coverage passed (the IT covered the VIP path); **branch** coverage didn't. A parameterized test over the discount table and a test for the invalid-percent guard fixed it: `Tests run: 6` and `All coverage checks have been met.`

### 3.3 Gate 5 failing: what `dependency:analyze` catches (verified)

Planted: `slf4j-api` removed from the POM (still used in code), `HikariCP` added (never used, but it brings slf4j in transitively), and the JUnit **aggregator** `junit-jupiter` instead of the individual artifacts.

```text
[ERROR] Used undeclared dependencies found:
[ERROR]    org.junit.jupiter:junit-jupiter-api:jar:6.0.3:test
[ERROR]    org.slf4j:slf4j-api:jar:2.0.17:compile
[ERROR] Unused declared dependencies found:
[ERROR]    com.zaxxer:HikariCP:jar:7.0.2:compile
[ERROR]    org.junit.jupiter:junit-jupiter:jar:6.0.3:test
[ERROR] Failed to execute goal org.apache.maven.plugins:maven-dependency-plugin:3.11.0:analyze-only (analyze) on project pricing: Dependency problems found
```

* **The real bug it caught:** the code compiled against **slf4j 2.0.17**, a version nobody chose; it arrived through HikariCP. Remove HikariCP (or upgrade it) and the code stops compiling or silently changes version. "Used undeclared" is a version you don't control.
* **The false positive to know:** aggregator artifacts (`junit-jupiter`, many `*-starter`s) are "unused" by bytecode analysis because your code references the artifacts they pull in. Declare what you use (`junit-jupiter-api`, `-params`) and ignore runtime-only pieces explicitly (`junit-jupiter-engine`). For Spring Boot starters, most teams configure `ignoredUnusedDeclaredDependencies` for `org.springframework.boot:spring-boot-starter*` and keep the gate for everything else.
* After the fix: `No dependency problems found`, `BUILD SUCCESS`.

### 3.4 Reproducibility check (verified)

Two `mvn clean package` runs in a row:

```text
build1 5695be76e81c274a  build2 5695be76e81c274a          (first 16 hex chars of each jar's SHA-256)

  Length      Date    Time    Name
---------  ---------- -----   ----
        0  2026-01-01 00:00   META-INF/
       99  2026-01-01 00:00   META-INF/MANIFEST.MF
```

Identical bytes, every entry stamped with `project.build.outputTimestamp`. In CI, build twice (or rebuild a release tag) and compare checksums; Maven's `artifact:compare` (maven-artifact-plugin) automates the comparison against a published reference build.

---

## 4. Gradle equivalents of the gates ⚡

(A mapping for teams running both tools; the Gradle column wasn't built as a separate project here, except where a link points to a verified example.)

| Gate | Maven (§3) | Gradle |
|---|---|---|
| Toolchain / version sanity | Enforcer `requireJavaVersion`, `requireMavenVersion` | `java { toolchain { languageVersion = JavaLanguageVersion.of(25) } }`; Gradle wrapper pins the Gradle version |
| Dependency convergence | Enforcer `dependencyConvergence` | `configurations.all { resolutionStrategy.failOnVersionConflict() }` (strict) or the platform + `dependencyInsight` |
| Unit vs integration tests | surefire / failsafe naming | `testing { suites { register<JvmTestSuite>("integrationTest") { … } } }` + `tasks.check { dependsOn(...) }` |
| Coverage | `jacoco:check` | `jacoco` plugin + `jacocoTestCoverageVerification { violationRules { … } }` wired into `check` |
| Declared == used | `dependency:analyze` | The `dependency-analysis` plugin (`com.autonomousapps.dependency-analysis`), `buildHealth` task; `api` vs `implementation` already enforces the compile-classpath half (§2.2) |
| Reproducible archives | `project.build.outputTimestamp` | `isPreserveFileTimestamps = false`, `isReproducibleFileOrder = true` (§1.5) |
| Supply chain | Enforcer + repository manager | `dependencyLocking`, `gradle/verification-metadata.xml`, repository `content {}` filters ([1.3](03-Dependency-Resolution-Jar-Hell-BOMs-Catalogs-Shading.md), [1.4](04-Enterprise-Builds-OCI-Images-Annotation-Processors-Enforcer.md)) |

Configuration-cache hygiene is a gate of its own in Gradle 9: a build script that reads an environment variable eagerly invalidates the cache whenever it changes ([1.2 §5.1](02-Gradle-Internals-Phases-Task-Graph-Caches-Daemon.md#51-verified-what-invalidates-the-configuration-cache-eager-vs-lazy-environment-reads-)).

---

## 5. Reference CI workflow (GitHub Actions; not executed here)

```yaml
name: build
on: [push, pull_request]
jobs:
  maven:
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with: { distribution: temurin, java-version: '25', cache: maven }   # caches ~/.m2/repository keyed by pom.xml hashes
      - run: ./mvnw -B -ntp verify                                           # all five gates of §3
      - run: ./mvnw -B -ntp -q clean package -DskipTests && sha256sum target/*.jar > build2.sha
        # optional reproducibility check: compare with the first build's checksums
  gradle:
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with: { distribution: temurin, java-version: '25' }
      - uses: gradle/actions/setup-gradle@v4                                 # wrapper validation + Gradle user home cache
      - run: ./gradlew build --configuration-cache --build-cache
      - run: ./gradlew publish
        if: github.ref == 'refs/heads/main'
        env: { ORG_GRADLE_PROJECT_acmeUsername: '${{ secrets.REPO_USER }}', ORG_GRADLE_PROJECT_acmePassword: '${{ secrets.REPO_TOKEN }}' }
```

What makes it production-grade: wrappers (`mvnw`, `gradlew`) pin the build-tool version; the cache is keyed on build files (not on time); every PR runs the same gates as `main`; publishing happens only from `main` with credentials from secrets; and for the platform repository, a release bumps `version` and publishes BOM, catalog and libraries **together**.

---

## 6. ❌ Naïve vs ✅ production-hardened

| ❌ Naïve | ✅ Hardened |
|---|---|
| Each repository pins its own framework versions | One published platform (BOM + catalog) imported everywhere |
| A catalog without a BOM (or a BOM without a catalog) | Both, published from one build so they can't disagree |
| Libraries declare everything with `api` (or `compile`) | `api` only for types in the public signature; `implementation` for the rest (runtime scope in the POM) |
| Repositories declared in every module | `dependencyResolutionManagement` with `FAIL_ON_PROJECT_REPOS` and per-repository `content {}` filters |
| Coverage measured, never enforced | `jacoco:check` / `jacocoTestCoverageVerification` in `verify`/`check`, with line **and** branch rules |
| Rely on transitive dependencies you happen to use | `dependency:analyze` with `failOnWarning` (it found an unchosen slf4j 2.0.17) |
| "Our builds are reproducible" | Build twice and compare checksums in CI |

---

## 7. Interview soundbites

* "I publish the platform as two artifacts from one build: a BOM for Maven and Gradle, and a version catalog for Gradle aliases. A Maven service imported our Gradle-built BOM and got Boot's slf4j 2.0.20 through the import chain."
* "`api` becomes compile scope and `implementation` becomes runtime scope in the published POM. A Maven consumer that touched HikariCP from our library failed to compile, which is exactly what lets us swap it in a minor release."
* "The platform raised HikariCP's own slf4j 2.0.17 to 2.0.20 on the consumer's runtime classpath."
* "`dependency:analyze` caught code compiling against slf4j 2.0.17 that only arrived through HikariCP: a version nobody chose. Aggregators like `junit-jupiter` are its classic false positive."
* "Reproducibility is a test, not a claim: two builds, same SHA-256."

---

## Summary

| Blueprint | What it gives you | Verified evidence |
|---|---|---|
| C: platform build (Gradle) | BOM (`java-platform`), catalog (`version-catalog`), library with `api`/`implementation`, reproducible archives | Published POMs/TOML/`.module`; `constraints` → `dependencyManagement`; Boot BOM → `import` |
| D: consumers | Maven imports the BOM; Gradle imports BOM + catalog; content-filtered repositories | `implementation` → runtime scope; compile error when used directly; 2.0.17 → 2.0.20 alignment |
| E: Maven quality gates | Enforcer, surefire/failsafe split, JaCoCo line + branch, `dependency:analyze` | Branch 0.50 < 0.70 failed; used-undeclared slf4j 2.0.17 caught; aggregator false positive; all green after fixes |
| Reproducibility | Fixed timestamps and order | Identical jar SHA-256 across two builds |
| Gradle gate equivalents | Toolchains, test suites, JaCoCo verification, dependency-analysis plugin, locking/verification | Configuration-cache invalidation verified in 1.2 |
| CI | Wrappers, cache by build files, same gates on every PR, publish from `main` | Reference only (not executed) |

**Next:** [1.5 Bar-raiser drill-downs (Round 2 covers this file) →](05-Bar-Raiser-Drill-Downs.md)
