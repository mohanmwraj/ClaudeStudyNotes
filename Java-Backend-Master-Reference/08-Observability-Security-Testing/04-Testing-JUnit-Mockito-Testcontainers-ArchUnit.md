# 8.4 · Testing — JUnit 6, Mockito 5, Spring Test Context Caching, Testcontainers 2, ArchUnit

> **Tags:** 🔥 must-know · ⚡ important · 🧊 deep cut
> **Sources:** JUnit 6.0 release notes and User Guide; Mockito 5 release notes and `Mockito` Javadoc §0.3 (mockito as an agent); JEP 451 (dynamic agent loading); Spring Framework 7.0 reference ("Context Caching", "Bean Overriding in Tests"); Spring Boot 4.1 reference ("Testing", "Testcontainers"); Testcontainers for Java 2.0 release notes; ArchUnit 1.5 User Guide.
> **Verified stack:** JUnit **6.0.3** (Platform + Jupiter), Mockito **5.23.0** (Byte Buddy 1.18.15), Spring Framework 7.0.10 `spring-test`, Spring Boot 4.1.2, Testcontainers **2.0.5**, ArchUnit **1.5.1**, JDK 25. Each sample below runs the JUnit Platform **in-process via the `Launcher` API** and prints what an IDE or Surefire would report, so the results are captured output and not described behavior.

---

## 1. What to test where 🔥

| Level | Tools | What it proves | Typical cost |
|---|---|---|---|
| Unit | JUnit 6 + AssertJ, Mockito for collaborators you own | Domain logic, edge cases, error paths | ms; thousands per minute |
| Architecture | ArchUnit (§6) | Layering, dependency direction, no cycles, banned APIs | One bytecode import per suite |
| Slice | `@WebMvcTest`, `@DataJpaTest`, `@JsonTest`, `@RestClientTest` | One layer with real Spring wiring (MVC mapping and validation, JPA mappings and queries, JSON shape) | 1–3 s per **cached** context |
| Integration | `@SpringBootTest` + Testcontainers (§5) | Real Postgres, Kafka or Redis behavior: SQL dialect, locks, transactions, serialization | Seconds per container start; share containers |
| Contract / E2E | Spring Cloud Contract, Pact; a small smoke suite against a deployed environment | Compatibility between services | Minutes; keep few |

* **Boot 4 split the test auto-configuration by technology.** The slice annotations are no longer in one `spring-boot-test-autoconfigure` jar. Add the matching test starter: `spring-boot-starter-webmvc-test`, `spring-boot-starter-data-jpa-test`, `spring-boot-starter-jdbc-test`, `spring-boot-starter-kafka-test`, `spring-boot-starter-security-test`, and so on (all in the 4.1.2 BOM). `spring-boot-starter-test-classic` exists for an all-in-one migration step.
* **`@MockBean`/`@SpyBean` are gone in Boot 4** (deprecated in 3.4; absent from `spring-boot-test` 4.1.2). Use Spring Framework's **`@MockitoBean` / `@MockitoSpyBean`** (`org.springframework.test.context.bean.override.mockito`), shown in §4.
* The trap with Testcontainers is mocking the database. H2 in Postgres mode isn't Postgres: `for no key update`, `skip locked`, JSONB, partial indexes, `ON CONFLICT` and isolation behavior differ. Pillar 5's locking and outbox results were measured on a real PostgreSQL 18 for that reason.

---

## 2. JUnit 6 — the platform, the lifecycle, extensions 🔥

| JUnit 6 change | What it means for you |
|---|---|
| **Java 17 baseline** (Kotlin 2.2 for Kotlin users) | Java 8/11 builds stay on JUnit 5.x |
| **One version number** for Platform, Jupiter and Vintage (6.0.x) | No more Platform 1.x vs Jupiter 5.x mismatch; import `junit-bom` |
| **JSpecify** nullness annotations across the API | Better null analysis in IDEs and NullAway |
| `@CsvSource` / `@CsvFileSource` parse with **FastCSV** (shaded) | Stricter, faster CSV; a few edge cases (quotes, blank lines) can change |
| **`CancellationToken`** in the Platform; console launcher `--fail-fast` | Stop a run after the first failure |
| Parameterized display names **quote string arguments** | `"10" items → "10"%` below; reports and filters that matched the old names need updating |
| **Vintage engine deprecated**; JUnit 4 rules and runners are on the way out | Migrate `@RunWith`/`@Rule` tests; Testcontainers 2 already dropped JUnit 4 (§5) |
| `junit-platform-runner` (`@RunWith(JUnitPlatform.class)`) **removed**; Surefire/Failsafe **< 3.0.0 unsupported** | Upgrade build plugins along with JUnit |
| Kotlin `suspend` test and lifecycle methods supported | Coroutine tests without `runBlocking` |

### 2.1 Runnable: parameterized tests, nested classes, assumptions, `@Timeout`, `@TempDir`, and a custom extension

<!-- run: javac cp=@p8 timeout=120 -->
```java
package demo.testing;

import static org.junit.jupiter.api.Assertions.*;
import static org.junit.jupiter.api.Assumptions.assumeTrue;
import static org.junit.platform.engine.discovery.DiscoverySelectors.selectClass;

import java.nio.file.*;
import java.util.*;
import java.util.concurrent.TimeUnit;
import org.junit.jupiter.api.*;
import org.junit.jupiter.api.extension.*;
import org.junit.jupiter.api.io.TempDir;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.CsvSource;
import org.junit.platform.engine.TestExecutionResult;
import org.junit.platform.launcher.*;
import org.junit.platform.launcher.core.*;
import org.junit.platform.launcher.listeners.SummaryGeneratingListener;

public class JUnit6Tour {
    static int discountPercent(int items, boolean vip) { return Math.min(items >= 10 ? 10 : items >= 5 ? 5 : 0, 10) + (vip ? 5 : 0); }

    /** A tiny extension: times each test method (BeforeTestExecution/AfterTestExecution callbacks). */
    static class Timing implements BeforeTestExecutionCallback, AfterTestExecutionCallback {
        static final List<String> slow = new ArrayList<>();
        public void beforeTestExecution(ExtensionContext c) { c.getStore(ExtensionContext.Namespace.GLOBAL).put("t", System.nanoTime()); }
        public void afterTestExecution(ExtensionContext c) {
            long ms = (System.nanoTime() - c.getStore(ExtensionContext.Namespace.GLOBAL).get("t", Long.class)) / 1_000_000;
            if (ms >= 40) slow.add(c.getDisplayName());
        }
    }

    @ExtendWith(Timing.class)
    static class PricingTest {
        @ParameterizedTest(name = "{0} items → {1}%")
        @CsvSource({"1, 0", "5, 5", "10, 10", "50, 15"})                      // the last row is a wrong expectation
        void discount(int items, int expected) { assertEquals(expected, discountPercent(items, false)); }

        @Nested class ForVipCustomers {
            @Test void vipGetsFivePointsMore() { assertEquals(15, discountPercent(10, true)); }
        }

        @RepeatedTest(3) void pureFunction(RepetitionInfo info) { assertEquals(5, discountPercent(5, false)); }

        @Test @Timeout(value = 50, unit = TimeUnit.MILLISECONDS)
        void quoteServiceCall() throws InterruptedException { Thread.sleep(200); }

        @Test void onlyOnLinuxCi() { assumeTrue(System.getProperty("os.name").startsWith("Linux"), "runs on Linux CI only"); }

        @Test void writesInvoice(@TempDir Path dir) throws Exception {
            Path invoice = Files.writeString(dir.resolve("invoice.txt"), "total=95.00");
            assertAll(() -> assertTrue(Files.exists(invoice)), () -> assertEquals("total=95.00", Files.readString(invoice)));
        }
    }

    public static void main(String[] args) {
        Map<String, String> results = new TreeMap<>();
        TestExecutionListener collector = new TestExecutionListener() {
            public void executionFinished(TestIdentifier id, TestExecutionResult r) {
                if (id.isTest()) results.put(id.getDisplayName(), r.getStatus() + r.getThrowable().map(t -> " " + t.getClass().getSimpleName()
                    + ": " + t.getMessage().lines().findFirst().orElse("")).orElse(""));
            }
            public void executionSkipped(TestIdentifier id, String reason) { results.put(id.getDisplayName(), "SKIPPED " + reason); }
        };
        SummaryGeneratingListener summary = new SummaryGeneratingListener();
        Launcher launcher = LauncherFactory.create();
        launcher.execute(LauncherDiscoveryRequestBuilder.request().selectors(selectClass(PricingTest.class)).build(), summary, collector);

        results.forEach((name, status) -> System.out.printf("%-26s %s%n", name, status));
        var s = summary.getSummary();
        System.out.printf("found %d, succeeded %d, failed %d, aborted %d; tests >= 40 ms (extension): %s%n",
            s.getTestsFoundCount(), s.getTestsSucceededCount(), s.getTestsFailedCount(), s.getTestsAbortedCount(), Timing.slow);
    }
}
```

Output (verified):

```
"1" items → "0"%           SUCCESSFUL
"10" items → "10"%         SUCCESSFUL
"5" items → "5"%           SUCCESSFUL
"50" items → "15"%         FAILED AssertionFailedError: expected: <15> but was: <10>
onlyOnLinuxCi()            ABORTED TestAbortedException: Assumption failed: runs on Linux CI only
quoteServiceCall()         FAILED TimeoutException: quoteServiceCall() timed out after 50 milliseconds
repetition 1 of 3          SUCCESSFUL
repetition 2 of 3          SUCCESSFUL
repetition 3 of 3          SUCCESSFUL
vipGetsFivePointsMore()    SUCCESSFUL
writesInvoice(Path)        SUCCESSFUL
found 11, succeeded 8, failed 2, aborted 1; tests >= 40 ms (extension): [quoteServiceCall()]
```

Reading the results:

* **Three outcomes, not two.** `FAILED` (an assertion), `ABORTED` (an assumption: `assumeTrue` on a non-Linux machine) and `SUCCESSFUL`. Aborted tests aren't failures. CI dashboards that count them as passed hide tests that never run on the CI OS.
* **The `50 items → 15%` row failed.** The expectation was wrong, which is what a parameterized table should catch. The display names show JUnit 6's **quoted arguments**.
* **`@Timeout(50 ms)` failed the 200 ms test after ~50 ms.** In the default `SAME_THREAD` mode JUnit interrupts the test thread. A test that ignores interrupts (busy loop, non-interruptible I/O) only fails after it finishes. Use `threadMode = SEPARATE_THREAD` for those, and set a global `junit.jupiter.execution.timeout.default` as a safety net for hung tests.
* **Extensions are the plugin model.** The `Timing` extension used `BeforeTestExecutionCallback`/`AfterTestExecutionCallback` and the `ExtensionContext.Store` (per-test state, closed automatically). Spring (`SpringExtension`), Mockito (`MockitoExtension`) and Testcontainers (`TestcontainersExtension`) are all built this way.
* **`@TempDir`** gives each test a fresh directory, deleted afterwards (configurable with `cleanup = ON_SUCCESS` to keep failing tests' files).

Execution-model facts worth knowing ⚡:

* A **new test-class instance per test method** (`PER_METHOD`) by default. `@TestInstance(PER_CLASS)` allows non-static `@BeforeAll` and shared state, and also lets tests couple through that state.
* Method and class order is **deterministic but intentionally non-obvious**. Use `@TestMethodOrder`/`@TestClassOrder` (or `junit.jupiter.testclass.order.default`, used in §4) when order matters, and fix the tests that rely on it.
* **Parallel execution** (`junit.jupiter.execution.parallel.enabled=true`, mode `concurrent`) needs isolation: `@ResourceLock`, `@Isolated`, no shared static state, no shared database rows. Spring contexts are shared between parallel classes (§4).

---

## 3. Mockito 5 — how mocks are made, and when not to mock 🔥

### 3.1 Runnable: final classes, static methods, captors, strict stubs, and the Java agent

<!-- run: javac cp=@p8 timeout=200 -->
```java
package demo.mocking;

import static org.mockito.Mockito.*;

import java.io.File;
import java.math.BigDecimal;
import java.nio.file.*;
import java.util.*;
import org.mockito.*;
import org.mockito.exceptions.misusing.UnnecessaryStubbingException;
import org.mockito.quality.Strictness;

public class MockitoInternals {
    public static final class PriceService {                                         // final class, final method, static method
        public BigDecimal price(String sku) { return new BigDecimal("19.99"); }
        public static String region() { return "EU"; }
    }
    public interface AuditLog { void record(String event); }

    public static void main(String[] args) throws Exception {
        if (args.length > 0) { mock(PriceService.class); System.err.println("child: mock created"); return; }

        PriceService prices = mock(PriceService.class);
        when(prices.price("SKU-1")).thenReturn(BigDecimal.TEN);
        System.out.println("1. mock of a final class: getClass()==PriceService.class → " + (prices.getClass() == PriceService.class)
            + ", price(SKU-1)=" + prices.price("SKU-1") + ", unstubbed price(SKU-2)=" + prices.price("SKU-2"));

        try (MockedStatic<PriceService> statics = mockStatic(PriceService.class)) {
            statics.when(PriceService::region).thenReturn("US");
            System.out.print("2. static mock: inside scope region()=" + PriceService.region());
        }
        System.out.println(", after close region()=" + PriceService.region());

        AuditLog audit = mock(AuditLog.class);
        audit.record("refund A-1 100.00");
        ArgumentCaptor<String> captor = ArgumentCaptor.forClass(String.class);
        verify(audit).record(captor.capture());
        System.out.println("3. captured argument: " + captor.getValue() + "; interface mock class: " + audit.getClass().getSimpleName().replaceAll("MockitoMock\\$\\w+", "MockitoMock\\$<random>"));

        MockitoSession session = Mockito.mockitoSession().initMocks(new Object()).strictness(Strictness.STRICT_STUBS).startMocking();
        PriceService unused = mock(PriceService.class);
        when(unused.price("never-called")).thenReturn(BigDecimal.ONE);
        try { session.finishMocking(); }
        catch (UnnecessaryStubbingException e) { System.out.println("4. strict stubs: " + e.getClass().getSimpleName() + " for an unused stubbing"); }

        // 5. how the inline mock maker gets its instrumentation: self-attach vs -javaagent
        String cp = System.getProperty("java.class.path");
        String mockitoJar = Arrays.stream(cp.split(File.pathSeparator)).filter(p -> p.contains("mockito-core")).findFirst().orElseThrow();
        Path argfile = Files.createTempFile("cp", ".args");
        Files.writeString(argfile, "-cp \"" + cp.replace('\\', '/') + "\"");
        String java = ProcessHandle.current().info().command().orElseThrow();
        for (boolean agent : new boolean[] {false, true}) {
            List<String> cmd = new ArrayList<>(List.of(java));
            if (agent) cmd.add("-javaagent:" + mockitoJar);
            cmd.addAll(List.of("@" + argfile, MockitoInternals.class.getName(), "child"));
            Process p = new ProcessBuilder(cmd).redirectErrorStream(true).start();
            List<String> lines = new String(p.getInputStream().readAllBytes()).lines().filter(l -> !l.isBlank()).toList();
            p.waitFor();
            System.out.println("5. child JVM " + (agent ? "with -javaagent:mockito-core.jar" : "without agent") + ":");
            lines.stream().map(l -> l.replaceAll("\\(\\S*[\\\\/]([^\\\\/]+\\.jar)\\)", "(…/$1)"))
                .forEach(l -> System.out.println("   " + (l.length() > 150 ? l.substring(0, 150) + "…" : l)));
        }
        Files.delete(argfile);
    }
}
```

Output (verified):

```
1. mock of a final class: getClass()==PriceService.class → true, price(SKU-1)=10, unstubbed price(SKU-2)=null
2. static mock: inside scope region()=US, after close region()=EU
3. captured argument: refund A-1 100.00; interface mock class: MockitoInternals$AuditLog$MockitoMock$<random>
4. strict stubs: UnnecessaryStubbingException for an unused stubbing
5. child JVM without agent:
   Mockito is currently self-attaching to enable the inline-mock-maker. This will no longer work in future releases of the JDK. Please add Mockito as an …
   WARNING: A Java agent has been loaded dynamically (…/byte-buddy-agent-1.18.15.jar)
   WARNING: If a serviceability tool is in use, please run with -XX:+EnableDynamicAgentLoading to hide this warning
   WARNING: If a serviceability tool is not in use, please run with -Djdk.instrument.traceUsage for more information
   WARNING: Dynamic loading of agents will be disallowed by default in a future release
   OpenJDK 64-Bit Server VM warning: Sharing is only supported for boot loader classes because bootstrap classpath has been appended
   child: mock created
5. child JVM with -javaagent:mockito-core.jar:
   OpenJDK 64-Bit Server VM warning: Sharing is only supported for boot loader classes because bootstrap classpath has been appended
   child: mock created
```

Reading the results:

* **The inline mock maker is the default since Mockito 5.** It does not subclass. It **retransforms the real class** through `java.lang.instrument`, so a mock of a `final` class still has `getClass() == PriceService.class`, and `final` and `static` methods can be stubbed. Interfaces still get a generated class (`AuditLog$MockitoMock$…`).
* **Unstubbed calls return defaults:** `null` for objects, `0`/`false` for primitives, empty collections, `Optional.empty()`. The unstubbed `price("SKU-2")` printed `null`, which is how a missing stub becomes an NPE three calls away.
* **`mockStatic` is thread-local and scoped.** Inside the try-with-resources `region()` returned `US`. After `close()` the real `EU` came back. A leaked (unclosed) static mock breaks later tests on the same thread.
* **Strict stubs** (the default for `MockitoExtension`, and the `MockitoSession` above) fail the test on an **unused stubbing** (`UnnecessaryStubbingException`). That catches copy-pasted setup and tests that no longer exercise what they claim.
* **The agent warning is a build-configuration bug, not noise.** Without an agent, Mockito **self-attaches** Byte Buddy's agent at runtime, and JDK 21+ prints the JEP 451 warnings that a future JDK will make fatal. With `-javaagent:mockito-core.jar` the warnings disappear (the remaining CDS line is a JVM note about the appended boot class path). Configure it once in the build:

```xml
<!-- Maven: resolve the jar path, then pass it to Surefire/Failsafe -->
<plugin>
  <artifactId>maven-dependency-plugin</artifactId>
  <executions><execution><goals><goal>properties</goal></goals></execution></executions>
</plugin>
<plugin>
  <artifactId>maven-surefire-plugin</artifactId>
  <configuration><argLine>@{argLine} -javaagent:${org.mockito:mockito-core:jar}</argLine></configuration>
</plugin>
```

(`@{argLine}` keeps JaCoCo's agent. In Gradle, declare a `mockitoAgent` configuration holding `mockito-core` (non-transitive) and add `-javaagent:${mockitoAgent.asPath}` to the `test` task's `jvmArgs`.)

**When not to mock** ⚡:

* **Don't mock types you don't own** (JDBC, `HttpClient`, Kafka producers, the Claude SDK). The mock encodes your *assumption* of their behavior. Test those boundaries with Testcontainers or a local fake (Pillar 7 used a JDK `HttpServer` speaking the Messages API).
* **Don't mock value objects or the class under test.** If a test needs `spy()` on the class under test, the class probably has two responsibilities.
* **Verify outcomes, not interactions,** unless the interaction *is* the behavior (an audit event, a published message). Over-verified tests break on every refactor and catch few bugs.

---

## 4. Spring test context caching — the biggest lever on suite time 🔥

Spring builds one `ApplicationContext` per unique **`MergedContextConfiguration`**: configuration classes, active profiles, property sources, context customizers and **bean overrides** such as `@MockitoBean`. It caches the context for the rest of the JVM (LRU, default `spring.test.context.cache.maxSize=32`). Every distinct key costs a full context start.

### 4.1 Runnable: six test classes, one configuration — how many contexts?

<!-- run: javac cp=@p8 timeout=120 -->
```java
package demo.ctx;

import static org.junit.platform.engine.discovery.DiscoverySelectors.selectClass;
import static org.mockito.Mockito.when;

import java.util.*;
import java.util.concurrent.atomic.AtomicInteger;
import org.junit.jupiter.api.*;
import org.junit.platform.launcher.core.*;
import org.junit.platform.launcher.listeners.SummaryGeneratingListener;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.context.SmartLifecycle;
import org.springframework.context.annotation.*;
import org.springframework.test.annotation.DirtiesContext;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.context.junit.jupiter.SpringJUnitConfig;

public class ContextCaching {
    static final List<String> log = Collections.synchronizedList(new ArrayList<>());
    static final AtomicInteger built = new AtomicInteger();

    public interface PaymentGateway { String charge(String order); }

    @Configuration
    public static class AppConfig {
        final int id = built.incrementAndGet();
        AppConfig() { log.add("build context #" + id); }
        @Bean PaymentGateway gateway() { return order -> "charged " + order; }
        @Bean SmartLifecycle kafkaListenerStandIn() {                    // anything with threads: listeners, schedulers, pools
            return new SmartLifecycle() {
                volatile boolean running;
                public void start() { running = true; log.add("    context #" + id + " lifecycle start"); }
                public void stop() { running = false; log.add("    context #" + id + " lifecycle stop"); }
                public boolean isRunning() { return running; }
            };
        }
    }

    static abstract class Base {
        @Autowired AppConfig config;
        @Autowired PaymentGateway gateway;
        @Test void run() { log.add("  " + getClass().getSimpleName() + " ran on context #" + config.id + " → " + gateway.charge("A-1")); }
    }
    @SpringJUnitConfig(AppConfig.class) @Order(1) static class OrdersTest extends Base { }
    @SpringJUnitConfig(AppConfig.class) @Order(2) static class InvoicesTest extends Base { }
    @SpringJUnitConfig(AppConfig.class) @Order(3) static class RefundsTest extends Base {
        @MockitoBean PaymentGateway gateway;                               // a bean override is part of the cache key
        @BeforeEach void stub() { when(gateway.charge("A-1")).thenReturn("mocked"); }
    }
    @SpringJUnitConfig(AppConfig.class) @Order(4) static class ReportsTest extends Base { }
    @SpringJUnitConfig(AppConfig.class) @Order(5) @DirtiesContext static class MigrationTest extends Base { }
    @SpringJUnitConfig(AppConfig.class) @Order(6) static class AuditTest extends Base { }

    public static void main(String[] args) {
        ((ch.qos.logback.classic.Logger) org.slf4j.LoggerFactory.getLogger(org.slf4j.Logger.ROOT_LOGGER_NAME)).setLevel(ch.qos.logback.classic.Level.WARN);
        var request = LauncherDiscoveryRequestBuilder.request()
            .selectors(List.of(OrdersTest.class, InvoicesTest.class, RefundsTest.class, ReportsTest.class, MigrationTest.class, AuditTest.class)
                .stream().map(c -> selectClass(c)).toList())
            .configurationParameter("junit.jupiter.testclass.order.default", "org.junit.jupiter.api.ClassOrderer$OrderAnnotation")
            .build();
        var summary = new SummaryGeneratingListener();
        LauncherFactory.create().execute(request, summary);
        log.forEach(System.out::println);
        System.out.printf("%d test classes, %d tests passed, %d contexts built%n",
            6, summary.getSummary().getTestsSucceededCount(), built.get());
    }
}
```

Output (verified):

```
build context #1
    context #1 lifecycle start
  OrdersTest ran on context #1 → charged A-1
  InvoicesTest ran on context #1 → charged A-1
    context #1 lifecycle stop
build context #2
    context #2 lifecycle start
  RefundsTest ran on context #2 → mocked
    context #2 lifecycle stop
    context #1 lifecycle start
  ReportsTest ran on context #1 → charged A-1
  MigrationTest ran on context #1 → charged A-1
    context #1 lifecycle stop
build context #3
    context #3 lifecycle start
  AuditTest ran on context #3 → charged A-1
6 test classes, 6 tests passed, 3 contexts built
```

Reading the results:

* **Same configuration → same context.** `OrdersTest` and `InvoicesTest` shared context #1, built once.
* **`@MockitoBean` changed the cache key.** `RefundsTest` needed context #2, a full second start. Ten test classes with ten different `@MockitoBean` combinations means ten contexts. Standardize the mocked set in a shared base class or a meta-annotation so classes share a key.
* **Spring Framework 7 pauses inactive contexts.** When the run switched to context #2, context #1's `SmartLifecycle` beans were **stopped**, and restarted when `ReportsTest` reused it. Before 7.0, cached contexts kept their listeners, schedulers and consumers running in the background, so a Kafka listener in an idle cached context could steal messages from the test that was running. The default is `ON_CONTEXT_SWITCH`. With `-Dspring.test.context.cache.pause=never` the same run showed no stop/start between contexts #1 and #2. With `always`, every class ended with a stop and the next class using that context restarted it, even between `OrdersTest` and `InvoicesTest` (both modes verified with the same sample).
* **`@DirtiesContext` closed context #1** after `MigrationTest`, so `AuditTest` paid for context #3. Use it only for tests that truly corrupt the context, and prefer resetting state (truncate tables, reset mocks) instead.

Suite-speed checklist: log the cache statistics (`logging.level.org.springframework.test.context.cache=debug`), count distinct contexts, and remove accidental key differences (`@TestPropertySource` variants, profile mixes, per-class `@MockitoBean`s, `@Import`s).

---

## 5. Testcontainers 2 and Boot `@ServiceConnection` 🔥

### 5.1 Runnable: a Postgres integration test, wired by `@ServiceConnection` (and what happens without Docker)

<!-- run: javac cp=@p8 timeout=120 -->
```java
package demo.containers;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.platform.engine.discovery.DiscoverySelectors.selectClass;

import javax.sql.DataSource;
import org.junit.jupiter.api.Test;
import org.junit.platform.engine.TestExecutionResult;
import org.junit.platform.launcher.*;
import org.junit.platform.launcher.core.*;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.testcontainers.service.connection.ServiceConnection;
import org.testcontainers.DockerClientFactory;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;
import org.testcontainers.postgresql.PostgreSQLContainer;                 // 2.0: new package, no self-type generic

public class ContainersTour {
    @SpringBootApplication static class App { }

    @SpringBootTest(classes = App.class)
    @Testcontainers(disabledWithoutDocker = true)                           // no Docker → skipped, not a red build
    static class OrderRepositoryIT {
        @Container @ServiceConnection                                       // Boot derives spring.datasource.* from the container
        static PostgreSQLContainer postgres = new PostgreSQLContainer("postgres:18-alpine");   // pin the tag you run in prod

        @Autowired DataSource dataSource;                                   // Hikari, pointed at the container's mapped port

        @Test void talksToRealPostgres() throws Exception {
            try (var c = dataSource.getConnection(); var rs = c.createStatement().executeQuery("show server_version")) {
                rs.next();
                assertEquals("18", rs.getString(1).substring(0, 2));
            }
        }
    }

    public static void main(String[] args) {
        ((ch.qos.logback.classic.Logger) org.slf4j.LoggerFactory.getLogger(org.slf4j.Logger.ROOT_LOGGER_NAME)).setLevel(ch.qos.logback.classic.Level.OFF);
        System.out.println("Docker available: " + DockerClientFactory.instance().isDockerAvailable());
        LauncherFactory.create().execute(LauncherDiscoveryRequestBuilder.request().selectors(selectClass(OrderRepositoryIT.class)).build(),
            new TestExecutionListener() {
                public void executionSkipped(TestIdentifier id, String reason) { System.out.println("SKIPPED " + id.getDisplayName() + ": " + reason); }
                public void executionFinished(TestIdentifier id, TestExecutionResult r) {
                    if (id.isTest()) System.out.println(r.getStatus() + " " + id.getDisplayName());   // never reached without Docker
                }
            });
    }
}
```

One measured run (this machine has **no Docker engine**; with Docker the test starts `postgres:18-alpine` and passes):

```
Docker available: false
SKIPPED ContainersTour$OrderRepositoryIT: disabledWithoutDocker is true and Docker is not available
```

Reading the results:

* **Testcontainers 2.0 changes:** modules are published as `testcontainers-<module>` (`testcontainers-postgresql`, `testcontainers-kafka`); container classes moved to module packages (`org.testcontainers.postgresql.PostgreSQLContainer`) and **dropped the self-type generic** (no more `PostgreSQLContainer<?>`). The old `org.testcontainers.containers.PostgreSQLContainer` is still shipped but `@Deprecated`, and the constructor needs an explicit image. **JUnit 4 support was removed**: the core jar no longer depends on `junit:junit`.
* **`@ServiceConnection`** makes Boot create `JdbcConnectionDetails` from the running container (URL with the mapped random port, user, password), which takes precedence over `spring.datasource.*`. It replaces the `@DynamicPropertySource` boilerplate. The same works for Kafka, Redis, Mongo, RabbitMQ, Elasticsearch and others, chosen by container type or image name.
* **`disabledWithoutDocker = true` skipped the class** instead of failing. That is right for a laptop without Docker and **wrong for CI**: a CI agent that silently lost Docker shows a green build with no integration tests. In CI, leave it `false` (fail fast) or assert on the expected test count.
* **Container lifecycle:** a `static @Container` field starts once per test class; an instance field starts once per **test method** (slow). The *singleton container* pattern, a container started in a static initializer of a shared base class or declared as a `@Bean @ServiceConnection` in a shared `@TestConfiguration`, lets every test class reuse one container. Ryuk removes it when the JVM exits.

<!-- run: compile cp=@p8 -->
```java
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.boot.testcontainers.service.connection.ServiceConnection;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Import;
import org.testcontainers.postgresql.PostgreSQLContainer;

@SpringBootApplication
class Application { public static void main(String[] args) { SpringApplication.run(Application.class, args); } }

// Shared across the suite: one Postgres, and one cached Spring context (same configuration = same cache key, §4)
@TestConfiguration(proxyBeanMethods = false)
class Containers {
    @Bean @ServiceConnection
    PostgreSQLContainer postgres() { return new PostgreSQLContainer("postgres:18-alpine"); }
}

@SpringBootTest @Import(Containers.class)
class OrderFlowIT { /* ... */ }

// Local development: run the real app against the same containers (src/test/java)
class TestApplication {
    public static void main(String[] args) { SpringApplication.from(Application::main).with(Containers.class).run(args); }
}
```

* **Determinism:** pin image tags (no `latest`). Wait on readiness (`Wait.forLogMessage`, health checks) and not on `sleep`. Use **Awaitility** (`await().atMost(…).untilAsserted(…)`) for asynchronous outcomes such as outbox relays and Kafka consumers. Reset data between tests instead of restarting containers.

---

## 6. ArchUnit — architecture as executable rules ⚡

### 6.1 Runnable: a layered rule and a standard-streams rule against a codebase with two planted violations

<!-- run: javac cp=@p8 timeout=120 -->
```java
package demo.arch;

import static com.tngtech.archunit.base.DescribedPredicate.describe;
import static com.tngtech.archunit.lang.syntax.ArchRuleDefinition.*;
import static com.tngtech.archunit.library.Architectures.layeredArchitecture;
import static com.tngtech.archunit.library.GeneralCodingRules.NO_CLASSES_SHOULD_ACCESS_STANDARD_STREAMS;

import com.tngtech.archunit.core.domain.JavaClass;
import com.tngtech.archunit.core.domain.JavaClasses;
import com.tngtech.archunit.core.importer.ClassFileImporter;
import com.tngtech.archunit.lang.ArchRule;
import com.tngtech.archunit.lang.EvaluationResult;
import java.util.List;

public class ArchitectureRules {
    // a miniature codebase with two planted violations
    static class Order { }
    static class OrderRepository { Order find(String id) { return new Order(); } }
    static class OrderService {
        final OrderRepository repo = new OrderRepository();
        Order load(String id) { System.out.println("loading " + id); return repo.find(id); }   // violation: standard streams
    }
    static class OrderController {
        final OrderService service = new OrderService();
        final OrderRepository repo = new OrderRepository();                                     // violation: skips the service layer
        Order get(String id) { return repo.find(id); }
    }

    public static void main(String[] args) {
        ((ch.qos.logback.classic.Logger) org.slf4j.LoggerFactory.getLogger("com.tngtech")).setLevel(ch.qos.logback.classic.Level.WARN);
        // a real test uses @AnalyzeClasses(packages = "com.acme") or importPackages(...); here: just the four demo classes, not main()
        JavaClasses classes = new ClassFileImporter().importClasses(Order.class, OrderRepository.class, OrderService.class, OrderController.class);
        var isController = describe("controllers", (JavaClass c) -> c.getSimpleName().endsWith("Controller"));
        var isService = describe("services", (JavaClass c) -> c.getSimpleName().endsWith("Service"));
        var isRepository = describe("repositories", (JavaClass c) -> c.getSimpleName().endsWith("Repository"));

        List<ArchRule> rules = List.of(
            layeredArchitecture().consideringOnlyDependenciesInLayers()
                .layer("Web").definedBy(isController)
                .layer("Service").definedBy(isService)
                .layer("Persistence").definedBy(isRepository)
                .whereLayer("Web").mayNotBeAccessedByAnyLayer()
                .whereLayer("Service").mayOnlyBeAccessedByLayers("Web")
                .whereLayer("Persistence").mayOnlyBeAccessedByLayers("Service"),
            NO_CLASSES_SHOULD_ACCESS_STANDARD_STREAMS,
            classes().that(isRepository).should().haveSimpleNameEndingWith("Repository"));      // trivially true: shows a passing rule

        for (ArchRule rule : rules) {
            EvaluationResult result = rule.evaluate(classes);
            System.out.println((result.hasViolation() ? "FAIL " : "PASS ") + rule.getDescription().lines().findFirst().orElse(""));
            result.getFailureReport().getDetails().stream().limit(3)
                .forEach(d -> System.out.println("     " + d.replaceAll("\\(ArchitectureRules\\.java:\\d+\\)", "(ArchitectureRules.java)")));
        }
    }
}
```

Output (verified):

```
FAIL Layered architecture considering only dependencies in layers, consisting of
     Constructor <demo.arch.ArchitectureRules$OrderController.<init>()> calls constructor <demo.arch.ArchitectureRules$OrderRepository.<init>()> in (ArchitectureRules.java)
     Field <demo.arch.ArchitectureRules$OrderController.repo> has type <demo.arch.ArchitectureRules$OrderRepository> in (ArchitectureRules.java)
     Method <demo.arch.ArchitectureRules$OrderController.get(java.lang.String)> calls method <demo.arch.ArchitectureRules$OrderRepository.find(java.lang.String)> in (ArchitectureRules.java)
FAIL no classes should access standard streams
     Method <demo.arch.ArchitectureRules$OrderService.load(java.lang.String)> gets field <java.lang.System.out> in (ArchitectureRules.java)
PASS classes that repositories should have simple name ending with 'Repository'
```

Reading the results:

* ArchUnit **imports bytecode** (`ClassFileImporter`) and checks rules against the dependency graph: constructor calls, field types and method calls are each reported. The controller that reached into the repository produced **three** violations for one design mistake: the field, its initialization and the call.
* `NO_CLASSES_SHOULD_ACCESS_STANDARD_STREAMS` (one of the `GeneralCodingRules`) caught `System.out` in a service. Its siblings ban `java.util.logging`, field injection (`NO_CLASSES_SHOULD_USE_FIELD_INJECTION`) and Joda-Time, and `ASSERTIONS_SHOULD_HAVE_DETAIL_MESSAGE` requires assertion messages.
* In a real build: `@AnalyzeClasses(packages = "com.acme", importOptions = ImportOption.DoNotIncludeTests.class)` with `@ArchTest static final ArchRule …` fields (the `archunit-junit5` engine runs them). Import is cached per class set.
* **Cycles:** `slices().matching("com.acme.(*)..").should().beFreeOfCycles()`. **Legacy code:** wrap a rule in `FreezingArchRule.freeze(rule)`. Existing violations are recorded in a violation store, new ones fail, and fixed ones drop out, so a rule can be introduced into a large codebase on day one. Also useful: `onionArchitecture()` for hexagonal layouts and Spring Modulith's verification for module boundaries.

---

## 7. Production failure modes & diagnostics

| Symptom | Cause | Fix |
|---|---|---|
| Suite got 3× slower after adding a few tests | New `@MockitoBean`/`@TestPropertySource` combinations → new contexts; `@DirtiesContext` | Count contexts (§4); unify configurations; remove `@DirtiesContext` |
| Kafka test randomly receives another test's messages | Listener containers in another cached context still running (pre-7.0), or shared topics and groups | Spring 7 pause (default); unique topics or group ids per test |
| Flaky asynchronous tests | `Thread.sleep` timing assumptions | Awaitility with a timeout; deterministic clocks (`Clock` injection) |
| Tests pass alone, fail together | Shared static state, leaked `mockStatic`, data left in the database, order dependence | Scoped static mocks; data reset per test; run with random order in CI |
| "Mockito is currently self-attaching" warning | No `-javaagent` configured | Surefire/Gradle agent configuration (§3) |
| Green build with no integration tests | `disabledWithoutDocker` on a CI agent without Docker; aborted tests counted as success | Fail fast in CI; assert test counts |
| Passes on H2, fails in production | Dialect, locking and constraint differences | Testcontainers with the production database version |
| Architecture erodes despite reviews | Rules only in a wiki | ArchUnit + `FreezingArchRule` in the build |
| `@Timeout` not firing on a hung test | Non-interruptible code in `SAME_THREAD` mode | `threadMode = SEPARATE_THREAD`; global default timeout |
| Upgrading to JUnit 6 changed test names in reports | Quoted parameterized display names | Update report filters; custom `name` patterns |

---

## 8. Interview Q&A

<details><summary><b>Q1. 🔥 What are the three outcomes of a JUnit test, and why does the distinction matter in CI?</b></summary>

Successful, failed (an assertion or exception) and aborted (a failed assumption, e.g. `assumeTrue`). Aborted tests didn't run. Counting them as passed hides tests that never execute in the CI environment. The verified run showed one aborted test (Linux-only on Windows) alongside two failures and eight successes.
</details>

<details><summary><b>Q2. 🔥 How can Mockito 5 mock a final class, and what does the "self-attaching" warning mean?</b></summary>

The default inline mock maker retransforms the real class through `java.lang.instrument`, instead of generating a subclass, so `final` classes and methods and (with `mockStatic`) static methods can be stubbed. The mock's class is the real class (verified). Instrumentation needs an agent. Without `-javaagent`, Mockito attaches Byte Buddy's agent dynamically, which JDK 21+ warns about (JEP 451) and a future JDK will disallow. Configure `-javaagent:mockito-core.jar` in Surefire or Gradle.
</details>

<details><summary><b>Q3. 🔥 Your Spring Boot test suite takes 20 minutes. Where do you look first?</b></summary>

Context caching. Each unique `MergedContextConfiguration` (config classes, profiles, properties, `@MockitoBean` overrides) means a new context start, and `@DirtiesContext` throws contexts away. Turn on cache debug logging, count distinct contexts, and unify configurations. Then share containers (singleton pattern), replace `@SpringBootTest` with slices where a full context isn't needed, and enable parallel execution where tests are isolated. The verified run built three contexts for six classes because of one `@MockitoBean` and one `@DirtiesContext`.
</details>

<details><summary><b>Q4. ⚡ What does Spring Framework 7's context pausing solve?</b></summary>

Cached contexts used to keep running: Kafka listeners, `@Scheduled` tasks and pollers in an idle cached context could consume messages or touch data meant for the active test. Spring 7 stops `SmartLifecycle` beans of a context when the run switches to a different context, and restarts them on reuse (default `ON_CONTEXT_SWITCH`; property `spring.test.context.cache.pause`). Verified: context #1 stopped when context #2 started and restarted for `ReportsTest`.
</details>

<details><summary><b>Q5. 🔥 Why use Testcontainers instead of H2 for repository tests, and what does `@ServiceConnection` do?</b></summary>

H2 doesn't reproduce Postgres SQL, locking (`for no key update`, `skip locked`), JSONB or constraint behavior, so tests pass on H2 and fail in production. Testcontainers runs the real database version. `@ServiceConnection` turns the started container into Boot connection details (`JdbcConnectionDetails` with the mapped port and credentials), replacing `@DynamicPropertySource` property wiring.
</details>

<details><summary><b>Q6. ⚡ What changed in Testcontainers 2.0?</b></summary>

Artifacts are prefixed (`testcontainers-postgresql`), container classes moved to module packages (`org.testcontainers.postgresql.PostgreSQLContainer`) and lost the self-type generic, the old classes are deprecated, and JUnit 4 support was removed. The JUnit Jupiter integration (`@Testcontainers`, `@Container`) remains; `disabledWithoutDocker` skips classes when Docker is absent (verified), so use it carefully in CI.
</details>

<details><summary><b>Q7. ⚡ How would you introduce architecture rules into a 10-year-old codebase with hundreds of violations?</b></summary>

ArchUnit rules (layering, `beFreeOfCycles`, banned APIs) wrapped in `FreezingArchRule.freeze(...)`. The current violations are stored as a baseline, so the build fails only on **new** violations, and the baseline shrinks as code is fixed. The rules live in the build, not in a wiki.
</details>

<details><summary><b>Q8. 🧊 When should you not mock?</b></summary>

For types you don't own (JDBC, HTTP clients, Kafka, SDKs: use containers or local fakes), for value objects, and for the class under test. Prefer verifying outcomes over interactions, except when the interaction is the behavior (an audit record, a published event). Strict stubs flag unused stubbings, which often point to tests that no longer test what they claim.
</details>
