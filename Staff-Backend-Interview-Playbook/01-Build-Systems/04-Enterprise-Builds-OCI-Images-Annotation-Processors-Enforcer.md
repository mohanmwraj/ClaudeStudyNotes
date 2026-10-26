# 1.4 Enterprise Builds: OCI Images (Buildpacks, Jib, Layered Jars), AOT Cache, Annotation Processors, Enforcer, and Two Verified Blueprints

> **Verified stack:** Spring Boot **4.1.2**, Maven **3.10.0**, Gradle **9.8.2**, Jib **3.5.2**, Temurin **25.0.4.1**, Lombok **1.18.48**, MapStruct **1.6.3**, maven-enforcer-plugin **3.6.3** + extra-enforcer-rules **1.12.1**.
>
> Both blueprints in §5 were built with `mvn verify` / `gradle build` **including a Spring context test**, and the fixes they contain came from real failures during verification.
>
> **Go deeper:** the production `Dockerfile` and Kubernetes manifests for this service are in [7.5](../07-Docker-JVM-Kubernetes/05-Production-Blueprints-application-yml-Dockerfile-Deployment.md). JVM memory in containers: [7.1](../07-Docker-JVM-Kubernetes/01-JVM-in-Containers-cgroups-v2-Memory-OOMKilled.md).

---

## 0. First principles: an image is a stack of content-addressed layers 🔥

An OCI image is a list of **layers** (tar archives), each identified by the **SHA-256 of its content**. Registries and nodes cache layers by digest, so:

* A layer whose bytes didn't change is **neither rebuilt, nor uploaded, nor pulled again**.
* A layer that changed invalidates **every layer above it** in Dockerfile builds (the build cache is a chain).

So **order layers from least to most frequently changing**:

```text
┌──────────────────────────────┐  changes every commit   (KBs)   ← application classes, resources
├──────────────────────────────┤  changes per release     (KBs)   ← your own SNAPSHOT/sibling modules
├──────────────────────────────┤  changes on dep upgrade  (~20 MB) ← third-party jars
├──────────────────────────────┤  changes monthly         (~60 MB) ← JRE
└──────────────────────────────┘  changes monthly         (~40 MB) ← base OS (Ubuntu/distroless)
```

The naïve `COPY target/app.jar /app.jar` puts ~23 MB of mostly unchanged dependencies **in the top layer**. Every commit re-uploads it and every node re-pulls it. With layering, a typical commit ships a few KB.

---

## 1. Three ways to build a Spring Boot OCI image ⚡

| | Dockerfile + `jarmode=tools extract` | Cloud Native Buildpacks (`spring-boot:build-image` / `bootBuildImage`) | Jib (`jib:build` / `jib:buildTar`) |
|---|---|---|---|
| Needs a Docker daemon? | Yes (or BuildKit/Podman/Kaniko) | **Yes** (talks to Docker's API) | **No.** Talks to registries directly |
| Base image | Yours (full control) | The builder's run image | Configurable (`jib.from.image`) |
| Layering | You write it | Automatic (from `layers.idx`) | Automatic: dependencies / snapshot deps / resources / classes / extra files |
| JVM memory flags | You write them | **Memory calculator** sets `-Xmx`, metaspace, thread stacks from the container limit | You set `jvmFlags` |
| Reproducibility | Depends on you | Good (fixed timestamps) | Excellent (`created` = epoch, see below) |
| Best for | Teams that need a custom base image, extra OS packages, or one Dockerfile standard | Platform teams that want patchable, policy-driven images without Dockerfiles | CI without Docker (Kubernetes runners), fastest rebuilds |

### 1.1 Buildpacks: the default builder in Boot 4.1.2

Read from Boot's own constants (`org.springframework.boot.buildpack.platform.build.BuildRequest` in `spring-boot-buildpack-platform-4.1.2.jar`):

**Output (verified, `javap -constants`):**

```text
  static final java.lang.String DEFAULT_BUILDER_IMAGE_NAME = "paketobuildpacks/builder-noble-java-tiny";
  static final java.lang.String DEFAULT_BUILDER_IMAGE_REF = "paketobuildpacks/builder-noble-java-tiny:latest";
```

So `mvn spring-boot:build-image` builds on **Ubuntu 24.04 "Noble"** with the **tiny** run image: no shell, no package manager, a non-root user, and a small attack surface. The `:latest` tag means builds pick up OS and JRE patches. That's good for security and bad for reproducibility, so pin a digest in regulated environments:

```xml
<plugin>
  <groupId>org.springframework.boot</groupId>
  <artifactId>spring-boot-maven-plugin</artifactId>
  <configuration>
    <image>
      <name>registry.acme.io/order-service:${project.version}</name>
      <builder>paketobuildpacks/builder-noble-java-tiny@sha256:…</builder>   <!-- pin -->
      <env>
        <BP_JVM_VERSION>25</BP_JVM_VERSION>
        <BPE_DELIM_JAVA_TOOL_OPTIONS xml:space="preserve"> </BPE_DELIM_JAVA_TOOL_OPTIONS>
        <BPE_APPEND_JAVA_TOOL_OPTIONS>-XX:+ExitOnOutOfMemoryError</BPE_APPEND_JAVA_TOOL_OPTIONS>
      </env>
    </image>
  </configuration>
</plugin>
```

*(Buildpacks need Docker, which isn't installed on the verification machine. The configuration above follows Boot's documented `image` options but wasn't executed here.)*

### 1.2 Jib: verified without Docker

```bash
mvn com.google.cloud.tools:jib-maven-plugin:3.5.2:buildTar \
    -Djib.from.image=eclipse-temurin:25-jre \
    -Djib.to.image=acme/order-service:1.4.0 \
    -Djib.container.jvmFlags=-XX:MaxRAMPercentage=75
```

**Output (verified, trimmed):**

```text
[WARNING] Base image 'eclipse-temurin:25-jre' does not use a specific image digest - build may not be reproducible
[INFO] Building dependencies layer...
[INFO] Building snapshot dependencies layer...
[INFO] Building classes layer...
[INFO] Building resources layer...
[INFO] Building jvm arg files layer...
[INFO] Using base image with digest: sha256:dbb43d81099eec91e0800226ed2296d03146ee7857165b95112372ad0d67e87f
[INFO] Container entrypoint set to [java, -XX:MaxRAMPercentage=75, -cp, @/app/jib-classpath-file, com.acme.order.service.OrderServiceApplication]
[INFO] Built image tarball at …\order-service\target\jib-image.tar
```

Inspecting the tarball's manifest and config with a short Python script:

**Output (verified):**

```text
RepoTags: ['acme/order-service:1.4.0']
created: 1970-01-01T00:00:00Z
Entrypoint: ['java', '-XX:MaxRAMPercentage=75', '-cp', '@/app/jib-classpath-file', 'com.acme.order.service.OrderServiceApplication']
User: None
layers: 11
 0   42.15 MB  umoci raw add-layer --image /home/buildd/rockcraft-ubuntu-f7 files=6658 e.g. ['bin', 'boot']
 ...
 3   63.08 MB  RUN /bin/sh -c set -eux;     ARCH="$(dpkg --print-architectu files=387 e.g. ['etc', 'etc/adduser.conf']
 ...
 6   21.05 MB  jib-maven-plugin:3.5.2                                       files=58 e.g. ['app', 'app/libs']
 7    0.00 MB  jib-maven-plugin:3.5.2                                       files=3 e.g. ['app', 'app/libs']
 8    0.00 MB  jib-maven-plugin:3.5.2                                       files=6 e.g. ['app', 'app/resources']
 9    0.00 MB  jib-maven-plugin:3.5.2                                       files=7 e.g. ['app', 'app/classes']
10    0.00 MB  jib-maven-plugin:3.5.2                                       files=3 e.g. ['app', 'app/jib-classpath-file']
```

What a reviewer should notice:

1. **Five application layers** on top of six base layers. A code change touches only layer 9 (`app/classes`, a few KB).
2. Jib doesn't ship the Boot fat jar. It runs an **exploded classpath** (`-cp @/app/jib-classpath-file`), so there's no nested-jar launcher at runtime.
3. `created: 1970-01-01T00:00:00Z`: Jib fixes timestamps so **the same inputs produce the same image digest**.
4. ⚠️ `User: None` means **the container runs as root**, because the `eclipse-temurin` base image doesn't set a user. Add `-Djib.container.user=1000:1000` (or `<container><user>`) and pin the base image by digest, as the warning says.

### 1.3 Dockerfile with Boot's layered jar

Boot's executable jar contains `BOOT-INF/layers.idx`, a recipe for splitting it into layers:

**Output (verified, `java -Djarmode=tools -jar order-service-1.4.0-SNAPSHOT.jar list-layers`):**

```text
dependencies
spring-boot-loader
snapshot-dependencies
application
```

**Output (verified, `BOOT-INF/layers.idx`, excerpt):**

```text
- "dependencies":
  - "BOOT-INF/lib/HdrHistogram-2.2.2.jar"
  - "BOOT-INF/lib/classmate-1.7.3.jar"
  - "BOOT-INF/lib/commons-logging-1.3.6.jar"
  ...
- "snapshot-dependencies":
- "application":
  - "BOOT-INF/classes/"
  - "BOOT-INF/classpath.idx"
  - "BOOT-INF/layers.idx"
  - "META-INF/"
  - "BOOT-INF/lib/order-api-1.4.0-SNAPSHOT.jar"
```

Note the last line: **sibling modules from the same reactor go into `application`**, not `snapshot-dependencies`, because they change with every commit just like your classes.

Two extract modes (verified):

| Command | Result | Run with |
|---|---|---|
| `extract --layers --launcher --destination d` | `d/dependencies/BOOT-INF/lib/…`, `d/spring-boot-loader/org/…`, `d/application/BOOT-INF/classes/…` | `java org.springframework.boot.loader.launch.JarLauncher` |
| `extract --layers --destination d` | `d/dependencies/lib/*.jar`, `d/application/order-service-1.4.0-SNAPSHOT.jar` whose `MANIFEST.MF` has `Class-Path: lib/…` | `java -jar order-service-1.4.0-SNAPSHOT.jar`. **This is the layout the AOT cache needs** (§2) |

The complete multi-stage, non-root, AOT-cache Dockerfile is in [7.2](../07-Docker-JVM-Kubernetes/02-Dockerfiles-Multistage-Distroless-Layers-Buildpacks-Jib.md) and [7.5](../07-Docker-JVM-Kubernetes/05-Production-Blueprints-application-yml-Dockerfile-Deployment.md).

---

## 2. Startup: CDS and the JDK 25 AOT cache ⚡

**First principles:** a Spring Boot app spends most of its startup **loading, verifying and linking thousands of classes**, then running cold (interpreted) code. Class Data Sharing (CDS) memory-maps pre-parsed class metadata. JDK 24+'s **AOT cache** (JEP 483, with JDK 25's JEP 514 one-step creation and JEP 515 method profiles) also stores *linked* classes and profiling data from a **training run**.

```bash
java -Djarmode=tools -jar order-service-1.4.0-SNAPSHOT.jar extract --destination extracted
cd extracted
# training run: start the context, then exit
java -XX:AOTCacheOutput=app.aot -Dspring.context.exit=onRefresh -jar order-service-1.4.0-SNAPSHOT.jar
# production runs
java -XX:AOTCache=app.aot -jar order-service-1.4.0-SNAPSHOT.jar
```

The training run produced a 62,914,560-byte `app.aot`, plus warnings such as:

```text
[warning][aot] class org/springframework/core/type/classreading/ClassFileMetadataReaderFactory cannot be archived because it was not defined from …\extracted\lib\spring-core-7.0.10.jar as claimed
```

(Spring Framework 7 ships JDK-24+-specific classes inside a multi-release jar, and the AOT cache can't archive those versioned entries. Harmless: they just load normally.)

**One measured run** (this laptop, 5 runs each, process start → context refreshed → exit):

```text
plain      median=1.92s  runs=[1.95, 1.86, 1.92, 1.88, 2.04]
aot-cache  median=1.01s  runs=[1.0, 0.99, 1.01, 1.01, 1.04]
```

About **47% less startup time** for a small web service, with no code changes. That matters for scale-from-zero, rolling deploys, and how long `startupProbe` has to wait (see [7.3](../07-Docker-JVM-Kubernetes/03-Kubernetes-Probes-and-Graceful-Shutdown.md)).

Rules: the cache is valid only for **the same JDK build and the same classpath** (same jars, same order). Create it in the image build, not on a developer laptop.

---

## 3. Annotation processors: the JDK 23+ trap 🔥

**First principles:** annotation processors (Lombok, MapStruct, Hibernate's metamodel generator, Micronaut/Dagger, `spring-boot-configuration-processor`) run *inside javac* and generate or modify code before compilation finishes. javac used to **discover processors automatically from the classpath**, through `META-INF/services/javax.annotation.processing.Processor`. That was convenient and also a supply-chain hole: any jar on your classpath could run code inside your compiler.

**Since JDK 23, javac no longer runs classpath-discovered processors by default.** Processing runs only if you pass `-processor`, `-processorpath`/`--processor-module-path`, or `-proc:full`.

### 3.1 Verified: the classic Lombok + MapStruct setup breaks on JDK 25

```xml
<!-- ❌ Lombok and mapstruct-processor only as (provided) dependencies -->
<dependency><groupId>org.projectlombok</groupId><artifactId>lombok</artifactId><version>1.18.48</version><scope>provided</scope></dependency>
<dependency><groupId>org.mapstruct</groupId><artifactId>mapstruct-processor</artifactId><version>1.6.3</version><scope>provided</scope></dependency>
```

**Output (verified, `mvn compile`, release 25):**

```text
[ERROR] COMPILATION ERROR :
[ERROR] …/demo/apt/Main.java:[6,10] cannot find symbol
[ERROR]   symbol:   method setName(java.lang.String)
[ERROR]   location: variable c of type demo.apt.Customer
[ERROR] …/demo/apt/Main.java:[7,10] cannot find symbol
[ERROR]   symbol:   method setEmail(java.lang.String)
```

Lombok's `@Getter @Setter` silently didn't run. There's no error about Lombok itself, only missing methods.

### 3.2 ✅ Declare processors explicitly, in the right order

```xml
<plugin>
  <artifactId>maven-compiler-plugin</artifactId>
  <version>3.15.0</version>
  <configuration>
    <annotationProcessorPaths>
      <path><groupId>org.projectlombok</groupId><artifactId>lombok</artifactId><version>1.18.48</version></path>
      <path><groupId>org.projectlombok</groupId><artifactId>lombok-mapstruct-binding</artifactId><version>0.2.0</version></path>
      <path><groupId>org.mapstruct</groupId><artifactId>mapstruct-processor</artifactId><version>1.6.3</version></path>
    </annotationProcessorPaths>
    <compilerArgs>
      <arg>-Amapstruct.defaultComponentModel=default</arg>
      <arg>-Amapstruct.unmappedTargetPolicy=ERROR</arg>
    </compilerArgs>
  </configuration>
</plugin>
```

**Output (verified):** `BUILD SUCCESS`. The generated mapper (`target/generated-sources/annotations/demo/apt/CustomerMapperImpl.java`):

```java
@Generated(
    value = "org.mapstruct.ap.MappingProcessor",
    date = "2026-10-25T09:32:13+0530",
    comments = "version: 1.6.3, compiler: javac, environment: Java 25.0.4.1 (Eclipse Adoptium)"
)
public class CustomerMapperImpl implements CustomerMapper {

    @Override
    public CustomerDto toDto(Customer c) {
        if ( c == null ) {
            return null;
        }

        String name = null;
        String email = null;

        name = c.getName();
        email = c.getEmail();

        CustomerDto customerDto = new CustomerDto( name, email );

        return customerDto;
    }
}
```

and running it prints `CustomerDto[name=Ada, email=ada@example.com]`.

Why each detail matters:

| Detail | Reason |
|---|---|
| `annotationProcessorPaths` | Puts processors on `-processorpath`, which re-enables processing on JDK 23+ and **separates the processor classpath from the compile classpath** (processor dependencies can't leak into your code) |
| Lombok **before** MapStruct + `lombok-mapstruct-binding` | MapStruct reads getters/setters/builders. They exist only after Lombok has modified the AST. The binding tells MapStruct to wait for Lombok's round |
| `unmappedTargetPolicy=ERROR` | A renamed DTO field becomes a compile error instead of a silent `null` in production |
| The `date` in `@Generated` | MapStruct writes the current time into the source. Pass `-Amapstruct.suppressGeneratorTimestamp=true` if you need byte-for-byte reproducible builds |

On JDK 25, Lombok also prints `WARNING: sun.misc.Unsafe::objectFieldOffset has been called by lombok.permit.Permit`. That's the JDK warning about terminally deprecated `Unsafe` memory-access methods. Harmless today, but track Lombok updates.

**Gradle equivalent** (from the blueprint): processors go on the `annotationProcessor` configuration, *not* on `implementation`:

```kotlin
compileOnly(lib("lombok"))
annotationProcessor(lib("lombok"))                       // order: Lombok first...
annotationProcessor(lib("lombok-mapstruct-binding"))
annotationProcessor(lib("mapstruct-processor"))          // ...then MapStruct sees the generated getters
```

Gradle also supports **incremental annotation processing** when processors declare themselves *isolating* or *aggregating*. One non-incremental processor forces full recompilation of the source set. Check with `--info` ("Full recompilation is required because … is not incremental").

---

## 4. The Maven Enforcer as a build firewall 🔥

Run the Enforcer in `validate` so bad builds fail **before** compiling or testing. The rules in the blueprint and what each one protects against:

| Rule | Plugin | Protects against |
|---|---|---|
| `requireMavenVersion` / `requireJavaVersion` | core | "Works with my Maven/JDK" drift |
| `requirePluginVersions` | core | Unpinned plugins (Maven 3.10 no longer pins them) |
| `banDuplicatePomDependencyVersions` | core | The same dependency declared twice with different versions |
| `requireUpperBoundDeps` | core | Silent downgrades ([1.3 §1.4](03-Dependency-Resolution-Jar-Hell-BOMs-Catalogs-Shading.md)) |
| `banDuplicateClasses` | extra | Classpath-order roulette ([1.3 §2](03-Dependency-Resolution-Jar-Hell-BOMs-Catalogs-Shading.md)) |
| `enforceBytecodeVersion` | extra | A dependency compiled for a newer JVM than you run (`UnsupportedClassVersionError` at runtime) |
| `bannedDependencies` | core | Known-bad libraries: EOL log4j 1.x, JUnit 4, `javax.*` in a `jakarta.*` app |
| `requireReleaseDeps` (release profile) | core | SNAPSHOTs in a release |
| `dependencyConvergence` | core | Any version disagreement. Too strict for most Spring apps, but useful for libraries |

### 4.1 What verification caught (real failures while building the blueprint)

**Catch 1: an unpinned plugin you never declared.**

```text
[ERROR] Rule 2: org.apache.maven.enforcer.rules.RequirePluginVersions failed with message:
[ERROR] Some plugins are missing valid versions or depend on Maven 3.10.0 defaults (LATEST, RELEASE, SNAPSHOT, TIMESTAMP SNAPSHOT as plugin version are not allowed)
[ERROR]    org.apache.maven.plugins:maven-site-plugin. 	The version currently in use is 3.22.0 via default lifecycle bindings
```

The **site** lifecycle's default binding counts too. Fix: pin `maven-site-plugin` in `pluginManagement`.

**Catch 2: Spring Framework 7 depends on `commons-logging` again.**

```text
[ERROR] Rule 7: org.apache.maven.enforcer.rules.dependency.BannedDependencies failed with message:
[ERROR] com.acme.order:order-service:jar:1.4.0-SNAPSHOT
[ERROR]    org.springframework.boot:spring-boot-starter-test:jar:4.1.2
[ERROR]       org.springframework:spring-core:jar:7.0.10
[ERROR]          commons-logging:commons-logging:jar:1.3.6 <--- banned via the exclude/include list
```

The old advice "ban `commons-logging`, Spring ships `spring-jcl`" is **wrong for Spring Framework 7**. Spring 7 dropped `spring-jcl` and depends on Apache Commons Logging **1.3.x**, which has the same auto-detection of SLF4J/Log4j 2. The verified rule bans only the old versions: `commons-logging:commons-logging:[,1.3.0)`.

**Catch 3: a compile-only tool shipped in production.** Not an Enforcer rule. Inspecting the Boot jar showed `BOOT-INF/lib/lombok-1.18.48.jar`. Spring Boot's `repackage` **includes `provided`-scoped dependencies**, so Lombok (compile-time only) was in the runtime image. The blueprint excludes it in the plugin configuration (start.spring.io does the same). Gradle's `compileOnly` never reaches `bootJar`.

---

## 5. Blueprint A: hardened multi-module Maven build (verified) 🔥

```text
order-platform/
├── pom.xml                 ← parent + aggregator: BOM import, pinned plugins, Enforcer, CI-friendly version
├── order-api/pom.xml       ← DTOs (records + Jakarta Validation)
└── order-service/pom.xml   ← Spring Boot service (layered jar)
```

### 5.1 `pom.xml` (root)

```xml
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 https://maven.apache.org/xsd/maven-4.0.0.xsd">
  <modelVersion>4.0.0</modelVersion>

  <groupId>com.acme.order</groupId>
  <artifactId>order-platform</artifactId>
  <version>${revision}</version>
  <packaging>pom</packaging>

  <modules>
    <module>order-api</module>
    <module>order-service</module>
  </modules>

  <properties>
    <revision>1.4.0-SNAPSHOT</revision>                <!-- CI-friendly version: mvn -Drevision=1.4.0 deploy -->
    <java.version>25</java.version>
    <maven.compiler.release>${java.version}</maven.compiler.release>
    <project.build.sourceEncoding>UTF-8</project.build.sourceEncoding>
    <project.build.outputTimestamp>2026-01-01T00:00:00Z</project.build.outputTimestamp>  <!-- reproducible jars -->

    <spring-boot.version>4.1.2</spring-boot.version>
    <mapstruct.version>1.6.3</mapstruct.version>
    <lombok.version>1.18.48</lombok.version>
  </properties>

  <!-- 1. Version alignment: IMPORT the Boot BOM instead of inheriting spring-boot-starter-parent,
          so the corporate parent can evolve independently of Spring Boot. -->
  <dependencyManagement>
    <dependencies>
      <dependency>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-dependencies</artifactId>
        <version>${spring-boot.version}</version>
        <type>pom</type>
        <scope>import</scope>
      </dependency>
      <!-- our own modules: every consumer gets one coherent version -->
      <dependency>
        <groupId>com.acme.order</groupId>
        <artifactId>order-api</artifactId>
        <version>${project.version}</version>
      </dependency>
      <dependency>
        <groupId>org.mapstruct</groupId>
        <artifactId>mapstruct</artifactId>
        <version>${mapstruct.version}</version>
      </dependency>
    </dependencies>
  </dependencyManagement>

  <build>
    <!-- 2. Pin EVERY plugin: Maven 3.10 removed the super-POM pluginManagement; Maven 4 warns on unpinned plugins. -->
    <pluginManagement>
      <plugins>
        <plugin><artifactId>maven-clean-plugin</artifactId><version>3.5.0</version></plugin>
        <plugin><artifactId>maven-resources-plugin</artifactId><version>3.5.0</version></plugin>
        <plugin>
          <artifactId>maven-compiler-plugin</artifactId>
          <version>3.15.0</version>
          <configuration>
            <parameters>true</parameters>   <!-- Spring resolves @PathVariable/@RequestParam names from -parameters -->
            <!-- JDK 23+ no longer runs processors discovered on the classpath: declare them. Order matters. -->
            <annotationProcessorPaths>
              <path><groupId>org.projectlombok</groupId><artifactId>lombok</artifactId><version>${lombok.version}</version></path>
              <path><groupId>org.projectlombok</groupId><artifactId>lombok-mapstruct-binding</artifactId><version>0.2.0</version></path>
              <path><groupId>org.mapstruct</groupId><artifactId>mapstruct-processor</artifactId><version>${mapstruct.version}</version></path>
            </annotationProcessorPaths>
            <compilerArgs>
              <arg>-Amapstruct.unmappedTargetPolicy=ERROR</arg>
            </compilerArgs>
          </configuration>
        </plugin>
        <plugin><artifactId>maven-surefire-plugin</artifactId><version>3.6.0</version></plugin>
        <plugin><artifactId>maven-failsafe-plugin</artifactId><version>3.6.0</version></plugin>
        <plugin><artifactId>maven-jar-plugin</artifactId><version>3.5.1</version></plugin>
        <plugin><artifactId>maven-install-plugin</artifactId><version>3.2.0</version></plugin>
        <plugin><artifactId>maven-deploy-plugin</artifactId><version>3.2.0</version></plugin>
        <plugin><artifactId>maven-dependency-plugin</artifactId><version>3.11.0</version></plugin>
        <plugin><artifactId>maven-site-plugin</artifactId><version>3.22.0</version></plugin>  <!-- site lifecycle default; requirePluginVersions flags it -->
        <plugin><artifactId>maven-enforcer-plugin</artifactId><version>3.6.3</version></plugin>
        <plugin><groupId>org.codehaus.mojo</groupId><artifactId>flatten-maven-plugin</artifactId><version>1.8.0</version></plugin>
        <plugin>
          <groupId>org.springframework.boot</groupId>
          <artifactId>spring-boot-maven-plugin</artifactId>
          <version>${spring-boot.version}</version>
        </plugin>
      </plugins>
    </pluginManagement>

    <plugins>
      <!-- 3. Guard rails: fail fast in `validate`, before anything compiles. -->
      <plugin>
        <artifactId>maven-enforcer-plugin</artifactId>
        <version>3.6.3</version>
        <dependencies>
          <dependency>
            <groupId>org.codehaus.mojo</groupId>
            <artifactId>extra-enforcer-rules</artifactId>
            <version>1.12.1</version>
          </dependency>
        </dependencies>
        <executions>
          <execution>
            <id>enforce-build-hygiene</id>
            <goals><goal>enforce</goal></goals>
            <configuration>
              <rules>
                <requireMavenVersion><version>[3.9.9,)</version></requireMavenVersion>
                <requireJavaVersion><version>[25,)</version></requireJavaVersion>
                <requirePluginVersions>
                  <message>Pin every plugin version (reproducibility).</message>
                </requirePluginVersions>
                <banDuplicatePomDependencyVersions/>
                <requireUpperBoundDeps/>          <!-- no transitive dependency silently downgraded -->
                <banDuplicateClasses>              <!-- one FQCN in two jars = classpath-order roulette -->
                  <ignoreWhenIdentical>true</ignoreWhenIdentical>
                  <ignoreClasses>
                    <ignoreClass>module-info</ignoreClass>
                    <ignoreClass>META-INF.versions.*</ignoreClass>
                  </ignoreClasses>
                  <findAllDuplicates>true</findAllDuplicates>
                </banDuplicateClasses>
                <enforceBytecodeVersion>           <!-- no dependency compiled for a newer JVM than we run -->
                  <maxJdkVersion>${java.version}</maxJdkVersion>
                  <ignoreOptionals>true</ignoreOptionals>
                </enforceBytecodeVersion>
                <bannedDependencies>
                  <excludes>
                    <!-- Spring 7 depends on commons-logging 1.3.x itself (spring-jcl is gone): ban only the old ones -->
                    <exclude>commons-logging:commons-logging:[,1.3.0)</exclude>
                    <exclude>log4j:log4j</exclude>                      <!-- EOL log4j 1.x -->
                    <exclude>junit:junit</exclude>                      <!-- JUnit 4 sneaking back in -->
                    <exclude>javax.servlet:*</exclude>                  <!-- javax.* in a jakarta.* world -->
                    <exclude>javax.persistence:*</exclude>
                  </excludes>
                </bannedDependencies>
              </rules>
            </configuration>
          </execution>
        </executions>
      </plugin>

      <!-- 4. Resolve ${revision} in installed/deployed POMs (Maven 3.x needs this; Maven 4 does it natively). -->
      <plugin>
        <groupId>org.codehaus.mojo</groupId>
        <artifactId>flatten-maven-plugin</artifactId>
        <configuration>
          <flattenMode>resolveCiFriendliesOnly</flattenMode>
          <updatePomFile>true</updatePomFile>
        </configuration>
        <executions>
          <execution><id>flatten</id><phase>process-resources</phase><goals><goal>flatten</goal></goals></execution>
          <execution><id>flatten-clean</id><phase>clean</phase><goals><goal>clean</goal></goals></execution>
        </executions>
      </plugin>
    </plugins>
  </build>

  <profiles>
    <profile>
      <id>release</id>
      <build>
        <plugins>
          <plugin>
            <artifactId>maven-enforcer-plugin</artifactId>
            <executions>
              <execution>
                <id>enforce-release</id>
                <goals><goal>enforce</goal></goals>
                <configuration>
                  <rules>
                    <requireReleaseDeps><message>No SNAPSHOT dependencies in a release.</message></requireReleaseDeps>
                  </rules>
                </configuration>
              </execution>
            </executions>
          </plugin>
        </plugins>
      </build>
    </profile>
  </profiles>
</project>
```

### 5.2 `order-api/pom.xml`

```xml
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 https://maven.apache.org/xsd/maven-4.0.0.xsd">
  <modelVersion>4.0.0</modelVersion>
  <parent>
    <groupId>com.acme.order</groupId>
    <artifactId>order-platform</artifactId>
    <version>${revision}</version>
  </parent>
  <artifactId>order-api</artifactId>

  <dependencies>
    <dependency>
      <groupId>jakarta.validation</groupId>
      <artifactId>jakarta.validation-api</artifactId>   <!-- version comes from the Boot BOM -->
    </dependency>
  </dependencies>
</project>
```

### 5.3 `order-service/pom.xml`

```xml
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 https://maven.apache.org/xsd/maven-4.0.0.xsd">
  <modelVersion>4.0.0</modelVersion>
  <parent>
    <groupId>com.acme.order</groupId>
    <artifactId>order-platform</artifactId>
    <version>${revision}</version>
  </parent>
  <artifactId>order-service</artifactId>

  <dependencies>
    <dependency><groupId>com.acme.order</groupId><artifactId>order-api</artifactId></dependency>
    <dependency><groupId>org.springframework.boot</groupId><artifactId>spring-boot-starter-web</artifactId></dependency>
    <dependency><groupId>org.springframework.boot</groupId><artifactId>spring-boot-starter-actuator</artifactId></dependency>
    <dependency><groupId>org.springframework.boot</groupId><artifactId>spring-boot-starter-validation</artifactId></dependency>
    <dependency><groupId>org.mapstruct</groupId><artifactId>mapstruct</artifactId></dependency>
    <dependency>
      <groupId>org.projectlombok</groupId>
      <artifactId>lombok</artifactId>
      <version>${lombok.version}</version>
      <scope>provided</scope>
    </dependency>
    <dependency><groupId>org.springframework.boot</groupId><artifactId>spring-boot-starter-test</artifactId><scope>test</scope></dependency>
  </dependencies>

  <build>
    <plugins>
      <plugin>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-maven-plugin</artifactId>
        <configuration>
          <excludes>   <!-- repackage copies `provided` deps into BOOT-INF/lib; Lombok is compile-time only -->
            <exclude><groupId>org.projectlombok</groupId><artifactId>lombok</artifactId></exclude>
          </excludes>
        </configuration>
        <executions>
          <execution>
            <goals><goal>repackage</goal></goals>   <!-- layered executable jar (BOOT-INF/layers.idx) by default -->
          </execution>
        </executions>
      </plugin>
    </plugins>
  </build>
</project>
```

> Note: in Boot 4, `spring-boot-starter-web` still works (this blueprint was built and run with it), but its own POM describes it as *"deprecated in favor of `spring-boot-starter-webmvc`"*. New services should use `spring-boot-starter-webmvc` (and the version catalog alias in §6 likewise).

### 5.4 Result

**Output (verified, `mvn verify`, trimmed):**

```text
[INFO] Rule 0: org.apache.maven.enforcer.rules.version.RequireMavenVersion passed
[INFO] Rule 1: org.apache.maven.enforcer.rules.version.RequireJavaVersion passed
[INFO] Rule 2: org.apache.maven.enforcer.rules.RequirePluginVersions passed
[INFO] Rule 3: org.apache.maven.enforcer.rules.BanDuplicatePomDependencyVersions passed
[INFO] Rule 4: org.apache.maven.enforcer.rules.dependency.RequireUpperBoundDeps passed
[INFO] Rule 5: org.codehaus.mojo.extraenforcer.dependencies.BanDuplicateClasses passed
[INFO] Rule 6: org.codehaus.mojo.extraenforcer.dependencies.EnforceBytecodeVersion passed
[INFO] Rule 7: org.apache.maven.enforcer.rules.dependency.BannedDependencies passed
...
[INFO] Tests run: 1, Failures: 0, Errors: 0, Skipped: 0
[INFO] order-platform ..................................... SUCCESS [  1.441 s]
[INFO] order-api .......................................... SUCCESS [  1.176 s]
[INFO] order-service ...................................... SUCCESS [ 14.995 s]
[INFO] BUILD SUCCESS
```

---

## 6. Blueprint B: the same platform in Gradle Kotlin DSL (verified) 🔥

```text
order-platform/
├── settings.gradle.kts
├── gradle.properties
├── gradle/libs.versions.toml
├── build-logic/
│   ├── settings.gradle.kts
│   ├── build.gradle.kts
│   └── src/main/kotlin/
│       ├── acme.java-conventions.gradle.kts
│       └── acme.spring-boot-service.gradle.kts
├── order-api/build.gradle.kts
└── order-service/build.gradle.kts
```

### 6.1 `settings.gradle.kts`

```kotlin
pluginManagement {
    includeBuild("build-logic")                 // convention plugins, built before this build configures
    repositories {
        gradlePluginPortal()
        mavenCentral()
    }
}

dependencyResolutionManagement {
    // Repositories are declared ONCE, here. A project that declares its own fails the build.
    repositoriesMode = RepositoriesMode.FAIL_ON_PROJECT_REPOS
    repositories {
        mavenCentral()
    }
}

rootProject.name = "order-platform"

include("order-api", "order-service")
```

### 6.2 `gradle.properties`

```properties
org.gradle.configuration-cache=true
org.gradle.caching=true
org.gradle.parallel=true
org.gradle.jvmargs=-Xmx1g -XX:+UseParallelGC -Dfile.encoding=UTF-8
org.gradle.java.installations.auto-download=false
```

### 6.3 `gradle/libs.versions.toml`

```toml
[versions]
java = "25"
spring-boot = "4.1.2"
mapstruct = "1.6.3"
lombok = "1.18.48"

[libraries]
# BOM, consumed with platform(); every Spring/Jackson/Hibernate version below comes from it
spring-boot-bom = { module = "org.springframework.boot:spring-boot-dependencies", version.ref = "spring-boot" }

spring-boot-starter-web        = { module = "org.springframework.boot:spring-boot-starter-web" }
spring-boot-starter-actuator   = { module = "org.springframework.boot:spring-boot-starter-actuator" }
spring-boot-starter-validation = { module = "org.springframework.boot:spring-boot-starter-validation" }
spring-boot-starter-test       = { module = "org.springframework.boot:spring-boot-starter-test" }
jakarta-validation-api         = { module = "jakarta.validation:jakarta.validation-api" }
junit-platform-launcher        = { module = "org.junit.platform:junit-platform-launcher" }

mapstruct                = { module = "org.mapstruct:mapstruct", version.ref = "mapstruct" }
mapstruct-processor      = { module = "org.mapstruct:mapstruct-processor", version.ref = "mapstruct" }
lombok                   = { module = "org.projectlombok:lombok", version.ref = "lombok" }
lombok-mapstruct-binding = { module = "org.projectlombok:lombok-mapstruct-binding", version = "0.2.0" }

# Plugin artifacts, used as dependencies of build-logic
spring-boot-gradle-plugin = { module = "org.springframework.boot:spring-boot-gradle-plugin", version.ref = "spring-boot" }

[bundles]
web-service = ["spring-boot-starter-web", "spring-boot-starter-actuator", "spring-boot-starter-validation"]

[plugins]
spring-boot = { id = "org.springframework.boot", version.ref = "spring-boot" }
```

### 6.4 `build-logic/settings.gradle.kts` and `build-logic/build.gradle.kts`

```kotlin
// build-logic/settings.gradle.kts
dependencyResolutionManagement {
    repositories {
        gradlePluginPortal()
        mavenCentral()
    }
    versionCatalogs {
        create("libs") { from(files("../gradle/libs.versions.toml")) }   // share the one catalog
    }
}

rootProject.name = "build-logic"
```

```kotlin
// build-logic/build.gradle.kts
plugins {
    `kotlin-dsl`                      // compiles src/main/kotlin/*.gradle.kts into binary plugins
}

dependencies {
    // put the Boot plugin on build-logic's classpath so convention plugins can apply it by id
    implementation(libs.spring.boot.gradle.plugin)
}
```

### 6.5 `build-logic/src/main/kotlin/acme.java-conventions.gradle.kts`

```kotlin
// Applied by EVERY Java module: toolchain, BOM alignment, annotation processors, compiler and test defaults.
plugins {
    java
}

val libs = extensions.getByType<VersionCatalogsExtension>().named("libs")
fun lib(alias: String) = libs.findLibrary(alias).get()

java {
    toolchain { languageVersion = JavaLanguageVersion.of(libs.findVersion("java").get().requiredVersion) }
}

dependencies {
    // platform() = recommendations that take part in conflict resolution (highest still wins).
    // Use enforcedPlatform() only if you accept forced DOWNGRADES of transitive dependencies.
    val bom = platform(lib("spring-boot-bom"))
    implementation(bom)
    annotationProcessor(bom)
    testImplementation(bom)

    compileOnly(lib("lombok"))
    annotationProcessor(lib("lombok"))                       // order: Lombok first...
    annotationProcessor(lib("lombok-mapstruct-binding"))
    annotationProcessor(lib("mapstruct-processor"))          // ...then MapStruct sees the generated getters

    testImplementation(lib("spring-boot-starter-test"))
    testRuntimeOnly(lib("junit-platform-launcher"))
}

configurations.configureEach {
    resolutionStrategy {
        failOnDynamicVersions()        // no 1.+ or latest.release
        failOnChangingVersions()       // no SNAPSHOTs in resolved graphs
    }
}

tasks.withType<JavaCompile>().configureEach {
    options.encoding = "UTF-8"
    options.compilerArgs.addAll(listOf("-parameters", "-Amapstruct.unmappedTargetPolicy=ERROR"))
}

tasks.withType<Test>().configureEach {
    useJUnitPlatform()
    maxParallelForks = (Runtime.getRuntime().availableProcessors() / 2).coerceAtLeast(1)
}
```

### 6.6 `build-logic/src/main/kotlin/acme.spring-boot-service.gradle.kts`

```kotlin
// Applied by deployable services only.
plugins {
    id("acme.java-conventions")
    id("org.springframework.boot")
}

springBoot {
    buildInfo {                        // META-INF/build-info.properties -> /actuator/info
        excludes = setOf("time")       // a timestamp changes every build -> cache miss for every task downstream
    }
}

tasks.named<org.springframework.boot.gradle.tasks.bundling.BootJar>("bootJar") {
    // layered jar is the default; listed here to make the image-layer contract explicit
    layered { enabled = true }
}

tasks.named<Jar>("jar") {
    enabled = false                    // only the executable bootJar is published
}
```

### 6.7 Module builds

```kotlin
// order-api/build.gradle.kts
plugins {
    id("acme.java-conventions")
    `java-library`                     // api vs implementation: what leaks to consumers' compile classpath
}

dependencies {
    api(libs.jakarta.validation.api)   // annotations appear in our public records, so consumers need them
}
```

```kotlin
// order-service/build.gradle.kts
plugins {
    id("acme.spring-boot-service")
}

dependencies {
    implementation(project(":order-api"))
    implementation(libs.bundles.web.service)
    implementation(libs.mapstruct)
}
```

### 6.8 Result

**Output (verified, `gradle clean build` after a warm cache):**

```text
Reusing configuration cache.
> Task :order-api:compileJava FROM-CACHE
> Task :order-service:compileJava FROM-CACHE
> Task :order-service:compileTestJava FROM-CACHE
> Task :order-service:test FROM-CACHE
> Task :order-service:bootJar
20 actionable tasks: 7 executed, 4 from cache, 9 up-to-date
Configuration cache entry reused.
```

The Boot jar contains **no Lombok** (`compileOnly` never reaches `bootJar`), and every archive entry has the fixed timestamp `1980-02-01 00:00` (Gradle 9 reproducible archives).

---

## 7. Supply chain and reproducibility checklist 🧊

| Concern | Maven | Gradle | Image |
|---|---|---|---|
| Same input → same bytes | `project.build.outputTimestamp` (default in 3.10) | Reproducible archives (default in 9) | Jib (`created`=epoch); pinned base digests |
| Know what you ship (SBOM) | `org.cyclonedx:cyclonedx-maven-plugin` | CycloneDX Gradle plugin | Boot puts `META-INF/sbom/application.cdx.json` in the jar when the plugin runs, and Actuator exposes `/actuator/sbom` |
| Artifact integrity | Checksums (Resolver validates), repository manager | `verification-metadata.xml` (checksums + PGP) | Sign images (Sigstore/cosign), verify at admission |
| Credential safety | 3.10: credentials scoped to repository origins | `FAIL_ON_PROJECT_REPOS`, credentials in the user home | Registry pull secrets; no secrets in layers |
| Dependency confusion | Mirror everything through one repository manager | Same, plus `exclusiveContent {}` repository filtering | Allow-listed registries |

---

## 8. ❌ Naïve vs ✅ production-hardened (enterprise build)

| ❌ Naïve | ✅ Hardened |
|---|---|
| `COPY target/app.jar` single-layer image | Layered extract, Buildpacks or Jib; layers ordered by change frequency |
| `FROM eclipse-temurin:25-jre` (moving tag, root user) | Pinned digest, non-root user, `-XX:MaxRAMPercentage`, `ExitOnOutOfMemoryError` ([7.2](../07-Docker-JVM-Kubernetes/02-Dockerfiles-Multistage-Distroless-Layers-Buildpacks-Jib.md)) |
| Annotation processors discovered from the classpath | `annotationProcessorPaths` / `annotationProcessor` configuration, Lombok first |
| Lombok in `BOOT-INF/lib` | Exclude it from `repackage` (Maven) or use `compileOnly` (Gradle) |
| Blanket ban on `commons-logging` copied from a Spring 5 blog | Ban `[,1.3.0)`; Spring 7 needs 1.3.x |
| Startup tuned by trial and error | AOT cache from a training run in the image build: −47% in our measurement |
| Rules documented in a wiki | Rules enforced in `validate` |

---

## 9. GitHub source to read

| Repo | Path | What to look for |
|---|---|---|
| [spring-projects/spring-boot](https://github.com/spring-projects/spring-boot) | `buildpack/spring-boot-buildpack-platform/src/main/java/org/springframework/boot/buildpack/platform/build/BuildRequest.java` | Builder and run image defaults, the Buildpacks lifecycle |
| spring-projects/spring-boot | `loader/spring-boot-jarmode-tools/src/main/java/org/springframework/boot/jarmode/tools/ExtractCommand.java` | How `extract --layers` builds the CDS-friendly layout |
| [GoogleContainerTools/jib](https://github.com/GoogleContainerTools/jib) | `jib-core/src/main/java/com/google/cloud/tools/jib/api/JibContainerBuilder.java` | How layers, entrypoint and the reproducible timestamps are assembled |
| [mapstruct/mapstruct](https://github.com/mapstruct/mapstruct) | `processor/src/main/java/org/mapstruct/ap/MappingProcessor.java` | Deferred processing rounds (why the Lombok binding exists) |
| [mojohaus/extra-enforcer-rules](https://github.com/mojohaus/extra-enforcer-rules) | `src/main/java/org/codehaus/mojo/extraenforcer/dependencies/EnforceBytecodeVersion.java` | Reading class-file major versions inside dependency jars |

*Paths in large repositories move between releases. If a link 404s, search the repository for the class name.*

---

## 10. Interview soundbites

* "Images are content-addressed layers. I order them by change frequency so a commit ships kilobytes, not the 20 MB dependency layer."
* "Buildpacks give a platform team patched, policy-driven images without Dockerfiles. Jib builds without a Docker daemon and is reproducible by default. A Dockerfile with Boot's layered extract gives full control. All three need a non-root user and a pinned base."
* "Since JDK 23, javac doesn't run annotation processors found on the classpath. I declare processors explicitly, Lombok before MapStruct."
* "The Enforcer is a build firewall. On a real Boot 4 build it caught an unpinned site plugin and a stale `commons-logging` ban that no longer applies to Spring 7."
* "A JDK 25 AOT cache from a training run cut our service's startup from about 1.9 s to 1.0 s."

> **Go deeper in this batch:** [1.6 Blueprints II](06-Build-Script-Blueprints-Platform-Publishing-Quality-Gates-CI.md) adds a published platform (BOM + catalog + library) consumed from Maven and Gradle, a Maven quality-gate build (JaCoCo branch coverage, `dependency:analyze`, surefire/failsafe), a reproducibility check (two builds, identical SHA-256) and a reference CI workflow.

---

## Summary

| Topic | Rule | Verified evidence |
|---|---|---|
| OCI images | Content-addressed layers ordered by change frequency | §0–§1 |
| Buildpacks / Jib / Dockerfile | Policy-driven images / daemonless and reproducible / full control; all non-root and pinned | Jib built without Docker (§1.2) |
| Startup | CDS and the JDK 25 AOT cache from a training run | ~1.9 s → 1.0 s (§2) |
| Annotation processors on JDK 23+ | Not discovered from the classpath any more; declare them (Lombok before MapStruct) | The classic setup broke on JDK 25 (§3.1) |
| Enforcer | A build firewall: versions, convergence, duplicates, bans | Caught an unpinned site plugin and a stale ban (§4.1) |
| Blueprint A / B | Hardened multi-module Maven and Gradle builds | Built and run (§5, §6) |
| Supply chain | Pinned plugins, verification metadata, SBOM, reproducible timestamps, one repository manager | §7 |
| Reproducibility as a test | Build twice, compare checksums | Identical jar SHA-256 ([1.6 §3.4](06-Build-Script-Blueprints-Platform-Publishing-Quality-Gates-CI.md#34-reproducibility-check-verified)) |

**Next:** [1.5 Bar-raiser drill-downs →](05-Bar-Raiser-Drill-Downs.md)
