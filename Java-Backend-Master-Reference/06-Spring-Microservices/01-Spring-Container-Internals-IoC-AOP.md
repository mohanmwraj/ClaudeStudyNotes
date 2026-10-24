# 6.1 · Spring Container Internals — IoC Lifecycle, Post-Processors, Circular Dependencies, AOP Proxies

> **Tags:** 🔥 must-know · ⚡ important · 🧊 deep cut · 🎓 Spring Professional
> **Sources:** Spring Framework 7.0 reference ("The IoC Container", "AOP", "Resilience"); Spring Framework source (`AbstractApplicationContext.refresh`, `AbstractAutowireCapableBeanFactory.doCreateBean`, `PostProcessorRegistrationDelegate`, `DefaultSingletonBeanRegistry`); Spring Boot 4.1 configuration metadata.
> **Verified stack:** Spring Framework **7.0.10**, Spring Boot **4.1.2**, AspectJ weaver 1.9.25.1, JDK 25. Every lifecycle order, message and proxy class name below was **captured from a real run**.

---

## 1. The container in one picture 🔥

```
                     ┌───────────────────── AbstractApplicationContext.refresh() ─────────────────────┐
 @Configuration /    │ 1 prepareBeanFactory      register ApplicationContextAwareProcessor, env beans    │
 component scan /    │ 2 invokeBeanFactoryPostProcessors                                                 │
 BeanRegistrar       │     ConfigurationClassPostProcessor (a BeanDefinitionRegistryPostProcessor):     │
   ───► BeanDefinitions   parses @Configuration/@ComponentScan/@Import/@Bean → more BeanDefinitions     │
                     │     then every BeanFactoryPostProcessor (property placeholders, your BFPPs)      │
                     │ 3 registerBeanPostProcessors   PriorityOrdered → Ordered → plain → internal (last)│
                     │ 4 initMessageSource / initApplicationEventMulticaster / onRefresh (web server)   │
                     │ 5 finishBeanFactoryInitialization   instantiate all non-lazy singletons           │
                     │ 6 finishRefresh   SmartLifecycle.start → ContextRefreshedEvent                    │
                     └───────────────────────────────────────────────────────────────────────────────────┘
 per bean (doCreateBean): instantiate → MergedBeanDefinitionPostProcessors → early reference (cycle support)
   → populateBean (@Autowired/@Value via AutowiredAnnotationBeanPostProcessor, then BeanDefinition property values)
   → Aware callbacks → BPP.before → @PostConstruct → afterPropertiesSet → init-method → BPP.after (proxies) → ready
```

| | `BeanFactory` | `ApplicationContext` |
|---|---|---|
| What | The core registry and DI engine (`DefaultListableBeanFactory`) | A `BeanFactory` plus everything an application needs |
| Singletons | Lazy (created on first `getBean`) | **Eager**: all non-lazy singletons at `refresh()`, so config errors fail at startup |
| Post-processors | Must be registered manually | Detected and ordered automatically |
| Also | — | Events (`ApplicationEventPublisher`), `Environment`/profiles, i18n (`MessageSource`), resource loading, `SmartLifecycle`, web server startup (Boot) |

**`BeanFactoryPostProcessor` (BFPP) vs `BeanPostProcessor` (BPP):** a BFPP runs **once, before any regular bean exists**, and edits **BeanDefinitions** (metadata: class, scope, property values, placeholders). A BPP runs **per bean instance** around initialization and can **replace** the instance, which is how every proxy (`@Transactional`, `@Async`, `@Cacheable`, `@Retryable`, aspects) is created. Declare BFPP/BPP `@Bean` methods **`static`** so they don't force early creation of their `@Configuration` class.

### 1.1 Runnable: the complete lifecycle, in the order Spring 7 actually calls it

<!-- run: javac cp=@p6web -->
```java
package demo.container;

import jakarta.annotation.PostConstruct;
import jakarta.annotation.PreDestroy;
import java.util.concurrent.atomic.AtomicInteger;
import org.springframework.beans.factory.*;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.config.*;
import org.springframework.context.*;
import org.springframework.context.annotation.*;
import org.springframework.context.event.ContextClosedEvent;
import org.springframework.context.event.ContextRefreshedEvent;
import org.springframework.context.event.EventListener;

public class BeanLifecycle {
    static final AtomicInteger step = new AtomicInteger();
    static void log(String s) { System.out.printf("%2d. %s%n", step.incrementAndGet(), s); }

    public static class Engine { }

    public static class Car implements BeanNameAware, BeanFactoryAware, ApplicationContextAware,
            InitializingBean, SmartInitializingSingleton, DisposableBean {
        String label = "default";
        public Car() { log("constructor"); }
        @Autowired void setEngine(Engine e) { log("@Autowired setter injection"); }
        public void setLabel(String l) { label = l; log("property from the BeanDefinition applied: label=" + l); }
        public void setBeanName(String name) { log("BeanNameAware.setBeanName(\"" + name + "\")"); }
        public void setBeanFactory(BeanFactory bf) { log("BeanFactoryAware.setBeanFactory"); }
        public void setApplicationContext(ApplicationContext ctx) { log("ApplicationContextAware.setApplicationContext"); }
        @PostConstruct void postConstruct() { log("@PostConstruct"); }
        public void afterPropertiesSet() { log("InitializingBean.afterPropertiesSet"); }
        void customInit() { log("@Bean(initMethod = \"customInit\")"); }
        public void afterSingletonsInstantiated() { log("SmartInitializingSingleton.afterSingletonsInstantiated"); }
        @PreDestroy void preDestroy() { log("@PreDestroy"); }
        public void destroy() { log("DisposableBean.destroy"); }
        void customDestroy() { log("@Bean(destroyMethod = \"customDestroy\")"); }
    }

    static class DefinitionTweaker implements BeanFactoryPostProcessor {
        public void postProcessBeanFactory(ConfigurableListableBeanFactory bf) {
            log("BeanFactoryPostProcessor: no Car exists yet; it edits the 'car' BeanDefinition");
            bf.getBeanDefinition("car").getPropertyValues().add("label", "set-by-BFPP");
        }
    }
    static class Tracer implements BeanPostProcessor {
        public Object postProcessBeforeInitialization(Object bean, String name) {
            if (bean instanceof Car c) log("BeanPostProcessor.before (label=" + c.label + ")");
            return bean;
        }
        public Object postProcessAfterInitialization(Object bean, String name) {
            if (bean instanceof Car) log("BeanPostProcessor.after  ← AOP proxies are created here");
            return bean;
        }
    }
    static class Lifecycle implements SmartLifecycle {
        volatile boolean running;
        public void start() { running = true; log("SmartLifecycle.start"); }
        public void stop() { running = false; log("SmartLifecycle.stop"); }
        public boolean isRunning() { return running; }
    }

    @Configuration
    static class Config {
        @Bean static DefinitionTweaker tweaker() { return new DefinitionTweaker(); }   // static: created before Config itself
        @Bean static Tracer tracer() { return new Tracer(); }
        @Bean Engine engine() { return new Engine(); }
        @Bean(initMethod = "customInit", destroyMethod = "customDestroy") Car car() { return new Car(); }
        @Bean Lifecycle lifecycle() { return new Lifecycle(); }
        @EventListener void on(ContextRefreshedEvent e) { log("ContextRefreshedEvent"); }
        @EventListener void on(ContextClosedEvent e) { log("ContextClosedEvent"); }
    }

    public static void main(String[] args) {
        ((ch.qos.logback.classic.Logger) org.slf4j.LoggerFactory.getLogger("ROOT")).setLevel(ch.qos.logback.classic.Level.WARN);
        var ctx = new AnnotationConfigApplicationContext();
        ctx.register(Config.class);
        System.out.println("-- refresh()");
        ctx.refresh();
        System.out.println("-- close()");
        ctx.close();
    }
}
```

Output (verified):

```
-- refresh()
 1. BeanFactoryPostProcessor: no Car exists yet; it edits the 'car' BeanDefinition
 2. constructor
 3. @Autowired setter injection
 4. property from the BeanDefinition applied: label=set-by-BFPP
 5. BeanNameAware.setBeanName("car")
 6. BeanFactoryAware.setBeanFactory
 7. ApplicationContextAware.setApplicationContext
 8. BeanPostProcessor.before (label=set-by-BFPP)
 9. @PostConstruct
10. InitializingBean.afterPropertiesSet
11. @Bean(initMethod = "customInit")
12. BeanPostProcessor.after  ← AOP proxies are created here
13. SmartInitializingSingleton.afterSingletonsInstantiated
14. SmartLifecycle.start
15. ContextRefreshedEvent
-- close()
16. ContextClosedEvent
17. SmartLifecycle.stop
18. @PreDestroy
19. DisposableBean.destroy
20. @Bean(destroyMethod = "customDestroy")
```

Details that interviews (and bugs) hinge on:

* **Annotation injection happens before XML/BeanDefinition property values** (3 before 4). `AutowiredAnnotationBeanPostProcessor.postProcessProperties` runs inside `populateBean` before `applyPropertyValues`, so explicit definition values win over `@Autowired` setters for the same property.
* **`BeanNameAware` and `BeanFactoryAware` are called by the factory itself. `ApplicationContextAware` is called by a BPP** (`ApplicationContextAwareProcessor`, registered first), which is why it comes after them.
* **Your BPP's `before` ran before `@PostConstruct`** (8 before 9). `@PostConstruct` is executed by `CommonAnnotationBeanPostProcessor`, and Spring **re-registers all internal `MergedBeanDefinitionPostProcessor`s at the end of the BPP chain** (`PostProcessorRegistrationDelegate`). Don't rely on `@PostConstruct` having run inside your own BPP's `before`.
* **Proxies appear in `BPP.after`** (12). Anything that captured `this` earlier (in the constructor, or by registering itself in a listener during `@PostConstruct`) holds the **raw** object, and calls through it skip transactions, async and retries.
* **`SmartInitializingSingleton`** is the hook for "all singletons are ready" (cache warm-up, validation). **`SmartLifecycle.start`** is for things that run (consumers, schedulers), and phases order start/stop. **`ContextRefreshedEvent`** comes after both. In Boot, `ApplicationReadyEvent` comes later still (after runners) and is the right signal for readiness.
* **Shutdown is reversed:** `ContextClosedEvent`, then `SmartLifecycle.stop` (graceful: stop consuming first), then destruction callbacks. **Prototype beans get no destruction callbacks.**

---

## 2. Circular dependencies 🔥

How Spring resolves a cycle **between singletons with field or setter injection**: when bean A is instantiated (before population), the factory registers an **`ObjectFactory` for an early reference** (the third-level `singletonFactories` cache). When B asks for A while A is still in creation, it receives that early reference (moved to `earlySingletonObjects`, the second level). A finishes later and lands in `singletonObjects` (the first level). Constructor injection can't do this, because there is no instance to hand out yet.

### 2.1 Runnable: four cycles, four outcomes

<!-- run: javac cp=@p6web -->
```java
package demo.cycles;

import ch.qos.logback.classic.Level;
import ch.qos.logback.classic.Logger;
import java.util.Map;
import java.util.concurrent.CompletableFuture;
import org.slf4j.LoggerFactory;
import org.springframework.aop.framework.AopProxyUtils;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.SpringBootConfiguration;
import org.springframework.boot.WebApplicationType;
import org.springframework.context.annotation.*;
import org.springframework.scheduling.annotation.Async;
import org.springframework.scheduling.annotation.EnableAsync;

public class CircularDependencies {
    // 1. constructor injection cycle
    public static class CtorA { public CtorA(CtorB b) { } }
    public static class CtorB { public CtorB(CtorA a) { } }
    @Configuration @Import({CtorA.class, CtorB.class}) static class CtorCycle { }

    // 2. field injection cycle
    public static class FieldA { @Autowired FieldB b; }
    public static class FieldB { @Autowired FieldA a; }
    @Configuration @Import({FieldA.class, FieldB.class}) static class FieldCycle { }

    // 3. field cycle where both sides get an @Async proxy (wrapped AFTER an early reference was handed out)
    public static class AsyncA {
        @Autowired AsyncB b;
        @Async public CompletableFuture<String> work() { return CompletableFuture.completedFuture(Thread.currentThread().getName()); }
    }
    public static class AsyncB {
        @Autowired AsyncA a;
        @Async public CompletableFuture<String> work() { return CompletableFuture.completedFuture(Thread.currentThread().getName()); }
    }
    @Configuration @EnableAsync @Import({AsyncA.class, AsyncB.class}) static class AsyncCycle { }

    // 4. the same field cycle under Spring Boot
    @SpringBootConfiguration @Import({FieldA.class, FieldB.class}) static class BootApp { }

    public static void main(String[] args) {
        ((Logger) LoggerFactory.getLogger("ROOT")).setLevel(Level.OFF);

        try (var ctx = new AnnotationConfigApplicationContext(CtorCycle.class)) { }
        catch (Exception e) { System.out.println("1. constructor cycle: " + rootMessage(e)); }

        try (var ctx = new AnnotationConfigApplicationContext(FieldCycle.class)) {
            FieldA a = ctx.getBean(FieldA.class);
            System.out.println("2. field cycle, plain Spring: started; a.b.a == a → " + (a.b.a == a));
        }

        try (var ctx = new AnnotationConfigApplicationContext(AsyncCycle.class)) {
            AsyncA a = (AsyncA) AopProxyUtils.getSingletonTarget(ctx.getBean(AsyncA.class));
            AsyncB b = (AsyncB) AopProxyUtils.getSingletonTarget(ctx.getBean(AsyncB.class));
            System.out.println("3. field cycle + @Async: context started; a.b.work() ran on '" + a.b.work().join()
                + "', b.a.work() ran on '" + b.a.work().join() + "'");
        } catch (Exception e) { System.out.println("3. field cycle + @Async: " + rootMessage(e)); }

        System.out.println("4. same field cycle under Spring Boot (its failure analysis, logged at ERROR):");
        SpringApplication app = new SpringApplication(BootApp.class);
        app.setBannerMode(org.springframework.boot.Banner.Mode.OFF);
        app.setWebApplicationType(WebApplicationType.NONE);
        app.setDefaultProperties(Map.of("logging.level.root", "ERROR", "logging.pattern.console", "%msg%n"));
        try { app.run().close(); }
        catch (Exception e) { System.out.println("   → " + e.getClass().getSimpleName()); }
    }

    static String rootMessage(Throwable e) {
        Throwable t = e; while (t.getCause() != null) t = t.getCause();
        return t.getClass().getSimpleName() + ": " + t.getMessage().replaceAll("\\s+", " ");
    }
}
```

Output (verified):

```
1. constructor cycle: BeanCurrentlyInCreationException: Error creating bean with name 'demo.cycles.CircularDependencies$CtorA': Requested bean is currently in creation: Is there an unresolvable circular reference or an asynchronous initialization dependency?
2. field cycle, plain Spring: started; a.b.a == a → true
3. field cycle + @Async: context started; a.b.work() ran on 'main', b.a.work() ran on 'SimpleAsyncTaskExecutor-1'
4. same field cycle under Spring Boot (its failure analysis, logged at ERROR):


***************************
APPLICATION FAILED TO START
***************************

Description:

The dependencies of some of the beans in the application context form a cycle:

┌─────┐
|  demo.cycles.CircularDependencies$FieldA (field demo.cycles.CircularDependencies$FieldB demo.cycles.CircularDependencies$FieldA.b)
↑     ↓
|  demo.cycles.CircularDependencies$FieldB (field demo.cycles.CircularDependencies$FieldA demo.cycles.CircularDependencies$FieldB.a)
└─────┘


Action:

Relying upon circular references is discouraged and they are prohibited by default. Update your application to remove the dependency cycle between beans. As a last resort, it may be possible to break the cycle automatically by setting spring.main.allow-circular-references to true.

   → UnsatisfiedDependencyException
```

1. **Constructor cycle:** fails at startup with `BeanCurrentlyInCreationException`. That's the desirable outcome, and one reason to prefer constructor injection.
2. **Field cycle in plain Spring:** works (`allowCircularReferences` defaults to `true` on `DefaultListableBeanFactory`). Both beans get the same instances.
3. **Field cycle + `@Async` on both sides:** the context started, but **one bean holds the raw, unproxied other**. `a.b.work()` ran synchronously on `main`, while `b.a.work()` ran on `SimpleAsyncTaskExecutor-1`. Early references are taken before `BPP.after` wraps the bean. The auto-proxy creator for aspects/`@Transactional` supports early proxies (`getEarlyBeanReference`), but the `@Async` post-processor does not. The classic failure for this setup is `BeanCurrentlyInCreationException … has been injected into other beans … in its raw version`. **On Spring 7.0.10 this run started silently instead**, which is worse: a correctness bug with no error.
4. **Spring Boot forbids cycles by default** (`spring.main.allow-circular-references=false` since Boot 2.6; the default is verified in the 4.1.2 metadata) and prints a failure analysis with the cycle.

**Fixes, in order of preference:** redesign (extract the shared logic into a third bean, or invert a dependency with an event or callback interface); constructor injection everywhere (cycles fail fast); `@Lazy` on one injection point (injects a lazy-resolution proxy); `ObjectProvider<B>`. `allow-circular-references=true` is a last resort.

---

## 3. AOP proxies: JDK vs CGLIB, full vs lite configuration ⚡

| | JDK dynamic proxy | CGLIB subclass proxy |
|---|---|---|
| Created when | Bean implements an interface and `proxyTargetClass=false` | `proxyTargetClass=true` (**Spring Boot default**: `spring.aop.proxy-target-class=true`), or no interfaces |
| Class | `jdk.proxy2.$ProxyN` implementing the interfaces | `Foo$$SpringCGLIB$$0` extends `Foo` |
| Inject by concrete class? | **No** (`NoSuchBeanDefinitionException`) | Yes |
| Limits | Only interface methods are advised | `final` classes and methods can't be advised; constructors run on the **target** only (Spring uses Objenesis to instantiate the proxy without calling the constructor, so the **proxy's fields are never initialized**) |
| Common to both | Self-invocation bypasses the proxy; only `public` (and since 6.0 `protected`/package-visible for CGLIB) methods are advised | |

### 3.1 Runnable: proxy classes, `@Configuration` modes, and the warnings the container prints

<!-- run: javac cp=@p6web -->
```java
package demo.proxies;

import ch.qos.logback.classic.Level;
import ch.qos.logback.classic.Logger;
import ch.qos.logback.classic.spi.ILoggingEvent;
import ch.qos.logback.core.read.ListAppender;
import org.aspectj.lang.ProceedingJoinPoint;
import org.aspectj.lang.annotation.Around;
import org.aspectj.lang.annotation.Aspect;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.config.BeanFactoryPostProcessor;
import org.springframework.beans.factory.config.BeanPostProcessor;
import org.springframework.context.annotation.*;

public class ProxiesAndConfig {
    public interface Greeter { String greet(String name); }
    public static class PoliteGreeter implements Greeter { public String greet(String n) { return "Hello " + n; } }
    @Aspect public static class Shout {
        @Around("execution(* demo.proxies.ProxiesAndConfig.Greeter.greet(..))")
        public Object around(ProceedingJoinPoint pjp) throws Throwable { return ((String) pjp.proceed()).toUpperCase(); }
    }
    @Configuration(proxyBeanMethods = false) @EnableAspectJAutoProxy(proxyTargetClass = false)
    static class JdkProxies { @Bean Greeter greeter() { return new PoliteGreeter(); } @Bean Shout shout() { return new Shout(); } }
    @Configuration(proxyBeanMethods = false) @EnableAspectJAutoProxy(proxyTargetClass = true)
    static class ClassProxies { @Bean Greeter greeter() { return new PoliteGreeter(); } @Bean Shout shout() { return new Shout(); } }

    public static class Clock { }
    public static class ServiceA { final Clock clock; ServiceA(Clock c) { clock = c; } }
    public static class ServiceB { final Clock clock; ServiceB(Clock c) { clock = c; } }
    @Configuration                                   // proxyBeanMethods = true: the class itself is CGLIB-enhanced
    static class Full { @Bean Clock clock() { return new Clock(); }
        @Bean ServiceA a() { return new ServiceA(clock()); } @Bean ServiceB b() { return new ServiceB(clock()); } }
    @Configuration(proxyBeanMethods = false)          // "lite" mode: clock() is a plain Java call
    static class Lite { @Bean Clock clock() { return new Clock(); }
        @Bean ServiceA a() { return new ServiceA(clock()); } @Bean ServiceB b() { return new ServiceB(clock()); } }

    public static class Audit { }
    @Configuration
    static class Warnings {
        @Bean BeanFactoryPostProcessor nonStaticBfpp() { return bf -> { }; }                    // should be static
        @Bean BeanPostProcessor tracer(Audit audit) { return new BeanPostProcessor() { }; }      // drags Audit in early
        @Bean Audit audit() { return new Audit(); }
    }

    public static void main(String[] args) {
        Logger root = (Logger) LoggerFactory.getLogger("ROOT");
        root.setLevel(Level.INFO);
        root.detachAndStopAllAppenders();
        ListAppender<ILoggingEvent> log = new ListAppender<>();
        log.start();
        root.addAppender(log);

        try (var ctx = new AnnotationConfigApplicationContext(JdkProxies.class)) {
            Greeter g = ctx.getBean(Greeter.class);
            System.out.println("1. proxyTargetClass=false: " + g.getClass().getName().replaceAll("\\d+$", "N") + " → " + g.greet("ada"));
            try { ctx.getBean(PoliteGreeter.class); } catch (Exception e) { System.out.println("   getBean(PoliteGreeter.class): " + e.getClass().getSimpleName()); }
        }
        try (var ctx = new AnnotationConfigApplicationContext(ClassProxies.class)) {
            Greeter g = ctx.getBean(PoliteGreeter.class);
            System.out.println("2. proxyTargetClass=true:  " + g.getClass().getName() + " → " + g.greet("ada"));
        }
        try (var ctx = new AnnotationConfigApplicationContext(Full.class)) {
            System.out.println("3. full @Configuration: " + ctx.getBean(Full.class).getClass().getSimpleName()
                + ", a.clock == b.clock → " + (ctx.getBean(ServiceA.class).clock == ctx.getBean(ServiceB.class).clock));
        }
        try (var ctx = new AnnotationConfigApplicationContext(Lite.class)) {
            System.out.println("4. lite  @Configuration: " + ctx.getBean(Lite.class).getClass().getSimpleName()
                + ", a.clock == b.clock → " + (ctx.getBean(ServiceA.class).clock == ctx.getBean(ServiceB.class).clock)
                + ", a.clock == the 'clock' bean → " + (ctx.getBean(ServiceA.class).clock == ctx.getBean(Clock.class)));
        }
        log.list.clear();
        try (var ctx = new AnnotationConfigApplicationContext(Warnings.class)) {
            System.out.println("5. container warnings:");
            log.list.stream().filter(e -> e.getLevel().isGreaterOrEqual(Level.INFO))
                .forEach(e -> System.out.println("   " + e.getLevel() + " " + e.getFormattedMessage()
                    .replace("demo.proxies.ProxiesAndConfig$", "")));
        }
    }
}
```

Output (verified):

```
1. proxyTargetClass=false: jdk.proxy2.$ProxyN → HELLO ADA
   getBean(PoliteGreeter.class): NoSuchBeanDefinitionException
2. proxyTargetClass=true:  demo.proxies.ProxiesAndConfig$PoliteGreeter$$SpringCGLIB$$0 → HELLO ADA
3. full @Configuration: ProxiesAndConfig$Full$$SpringCGLIB$$0, a.clock == b.clock → true
4. lite  @Configuration: Lite, a.clock == b.clock → false, a.clock == the 'clock' bean → false
5. container warnings:
   INFO @Bean method Warnings.nonStaticBfpp is non-static and returns an object assignable to Spring's BeanFactoryPostProcessor interface. This will result in a failure to process annotations such as @Autowired, @Resource, and @PostConstruct within the method's declaring @Configuration class. Add the 'static' modifier to this method to avoid these container lifecycle issues; see @Bean javadoc for complete details.
   WARN Bean 'audit' of type [Audit] is not eligible for getting processed by all BeanPostProcessors (for example: not eligible for auto-proxying). Is this bean getting eagerly injected/applied to a currently created BeanPostProcessor [tracer]? Check the corresponding BeanPostProcessor declaration and its dependencies/advisors. If this bean does not have to be post-processed, declare it with ROLE_INFRASTRUCTURE.
```

* **Full mode** (`@Configuration`, `proxyBeanMethods = true`): the configuration class itself is CGLIB-enhanced, so the inter-bean call `clock()` is intercepted and returns **the singleton**.
* **Lite mode** (`proxyBeanMethods = false`, or `@Bean` methods on a `@Component`): `clock()` is a plain Java call, so **each call creates a new `Clock`** that isn't even the container's bean (line 4). Spring Boot's own auto-configurations use lite mode for startup speed and AOT. In lite mode, wire dependencies through `@Bean` method **parameters**, never by calling other `@Bean` methods.
* **Warning 5b is a real production bug signal:** a BPP that depends on a regular bean forces that bean (and its dependency graph) to be created **before** the other post-processors are registered. Those beans silently get **no** `@Transactional`, `@Async` or metrics proxies. Keep BPPs `static` with minimal, lazily resolved dependencies (`ObjectProvider`).
* Spring 7 logs the non-static BFPP message at **INFO**, so it is easy to miss if only WARN and above are collected.

---

## 4. Spring 7 additions you'll meet in Boot 4 code ⚡

* **`BeanRegistrar`**: programmatic, conditional bean registration that stays AOT- and native-image-friendly. It is imported with `@Import`, and you code against `BeanRegistry` + `Environment` (§4.1).
* **Core resilience**: `@Retryable` and `@ConcurrencyLimit` (+ `@EnableResilientMethods`) in `spring-context`, used for optimistic-lock retries in [5.4 §4.1](../05-Persistence-JPA-Hibernate/04-Transactions-Isolation-Locking-Spring-Transactional.md#41-runnable-the-ten-behaviours-every-spring-developer-gets-bitten-by), with circuit breakers in [6.4](04-Resilience4j-CircuitBreaker-RateLimiter-Bulkhead.md).
* **HTTP service clients**: `@ImportHttpServices` registers `@HttpExchange` interfaces as beans in groups backed by `RestClient`/`WebClient`.
* **API versioning** in MVC/WebFlux: `ApiVersionConfigurer` (`useRequestHeader`, `usePathSegment`, `useQueryParam`, `useMediaTypeParameter`) plus `@GetMapping(version = "1.1")`.
* **JSpecify null-safety annotations** across the framework (`@Nullable`/`@NonNull` from `org.jspecify`), which Kotlin and static analysers understand.
* **Jackson 3** (`tools.jackson.*`) is the default JSON library in Boot 4 ([4.3](../04-IO-NIO-Serialization/03-Serialization-Security-Protobuf-Avro-Jackson.md)).

### 4.1 Runnable: `BeanRegistrar` choosing beans from the `Environment`

<!-- run: javac cp=@p6web -->
```java
package demo.registrar;

import java.util.Map;
import org.springframework.beans.factory.BeanRegistrar;
import org.springframework.beans.factory.BeanRegistry;
import org.springframework.context.annotation.*;
import org.springframework.core.env.Environment;
import org.springframework.core.env.MapPropertySource;

public class ProgrammaticBeans {
    public interface PaymentGateway { String name(); }
    public record StripeGateway(String apiBase) implements PaymentGateway { public String name() { return "stripe@" + apiBase; } }
    public record FakeGateway() implements PaymentGateway { public String name() { return "fake"; } }
    public record Checkout(PaymentGateway gateway) { }

    // Spring 7: imperative, AOT-friendly registration with access to the Environment
    static class PaymentBeans implements BeanRegistrar {
        public void register(BeanRegistry registry, Environment env) {
            if (env.getProperty("payments.mode", "fake").equals("live")) {
                registry.registerBean("gateway", StripeGateway.class,
                    spec -> spec.supplier(ctx -> new StripeGateway(env.getProperty("payments.api-base"))));
            } else {
                registry.registerBean("gateway", FakeGateway.class);
            }
            registry.registerBean(Checkout.class, spec -> spec.supplier(ctx -> new Checkout(ctx.bean(PaymentGateway.class))));
        }
    }
    @Configuration @Import(PaymentBeans.class) static class AppConfig { }

    public static void main(String[] args) {
        for (String mode : new String[] {"fake", "live"}) {
            var ctx = new AnnotationConfigApplicationContext();
            ctx.getEnvironment().getPropertySources().addFirst(new MapPropertySource("demo",
                Map.of("payments.mode", mode, "payments.api-base", "https://api.example.test")));
            ctx.register(AppConfig.class);
            ctx.refresh();
            System.out.println("payments.mode=" + mode + " → Checkout uses " + ctx.getBean(Checkout.class).gateway().name());
            ctx.close();
        }
    }
}
```

Output (verified):

```
payments.mode=fake → Checkout uses fake
payments.mode=live → Checkout uses stripe@https://api.example.test
```

Compared with `@Conditional`/`@Profile` on many `@Bean` methods, a registrar keeps the decision logic in one readable method with typed suppliers.

---

## 5. Production failure modes & diagnostics (container)

| Symptom | Cause | Confirm with | Fix |
|---|---|---|---|
| `@Transactional`/`@Async`/`@Cacheable` silently ignored on some beans | Self-invocation; bean created before the BPPs (warning 5b); raw early reference in a cycle; `final` method | `AopUtils.isAopProxy(bean)`; startup log "not eligible for getting processed by all BeanPostProcessors" | Call through the proxy; `static` BPP `@Bean`s; break the cycle |
| `NullPointerException` on a field of a bean that "is definitely injected" | Field read **through a CGLIB proxy** (the proxy's fields are never initialized) | Debugger: the object is `…$$SpringCGLIB$$0` | Access state via methods; never make injected fields `public` |
| `NoSuchBeanDefinitionException` for a concrete class | JDK proxy (`proxyTargetClass=false`) | Bean class `jdk.proxy…` | Inject the interface, or use CGLIB proxies |
| Startup fails with "form a cycle" after a Boot upgrade | Boot ≥ 2.6 prohibits cycles | Failure analysis output | Redesign; constructor injection; `@Lazy` |
| Two instances of a "singleton" | Lite-mode `@Bean` method called directly | Identity checks; Boot `/actuator/beans` | Inject via `@Bean` parameters |
| Slow startup | Eager initialization of heavy beans; classpath scanning; many auto-configurations | Boot `ApplicationStartup` (`BufferingApplicationStartup` + `/actuator/startup`), JFR | Lazy init for specific beans, narrow scanning, AOT/CDS ([1.5](../01-JVM-Internals/05-JIT-Compilation-AOT-Native-Image.md)) |
| Beans used before they're ready (`@PostConstruct` calling another bean's proxied method in a cycle) | Lifecycle ordering | Lifecycle logs | Move work to `SmartInitializingSingleton` or `ApplicationReadyEvent` |
| Consumers keep running during shutdown, and messages get lost | Work started outside `SmartLifecycle` | Shutdown logs order | Implement `SmartLifecycle` with phases; graceful shutdown |

**Tools:** `/actuator/beans` (dependencies and scopes), `/actuator/conditions` (why an auto-configuration did or didn't apply), `/actuator/startup` (startup steps with timings), `--debug` (condition evaluation report), `AopUtils.isAopProxy/isCglibProxy/isJdkDynamicProxy`, and `AopProxyUtils.getSingletonTarget`.

---

## 6. Interview Q&A

<details><summary><b>Q1. 🔥 Walk through the lifecycle of a singleton bean in Spring.</b></summary>

BeanDefinition created (scan, `@Bean` or registrar) → BFPPs may modify it → instantiation (constructor/factory method) → `MergedBeanDefinitionPostProcessor`s collect injection metadata → an early reference is registered (for cycles) → population (`@Autowired`/`@Value`, then definition property values) → `BeanNameAware`, `BeanClassLoaderAware`, `BeanFactoryAware` → BPP `before` (including `ApplicationContextAware` via `ApplicationContextAwareProcessor`, and `@PostConstruct` via `CommonAnnotationBeanPostProcessor`) → `afterPropertiesSet` → custom init method → BPP `after` (proxies) → in use. After all singletons: `SmartInitializingSingleton`; then `SmartLifecycle.start`; then `ContextRefreshedEvent`. On close: `ContextClosedEvent` → `SmartLifecycle.stop` → `@PreDestroy` → `destroy()` → custom destroy method.
</details>

<details><summary><b>Q2. 🔥 BeanFactoryPostProcessor vs BeanPostProcessor: give a real example of each.</b></summary>

A BFPP operates on bean *definitions* before instantiation. Examples: `PropertySourcesPlaceholderConfigurer` (resolves `${…}`) and `ConfigurationClassPostProcessor` (parses `@Configuration` and registers more definitions). A BPP operates on bean *instances* around initialization and may return a different object. Examples: `AutowiredAnnotationBeanPostProcessor` (injection), `CommonAnnotationBeanPostProcessor` (`@PostConstruct`/`@PreDestroy`/`@Resource`), and `AnnotationAwareAspectJAutoProxyCreator` (wraps beans in AOP proxies). Declare both as `static` `@Bean` methods.
</details>

<details><summary><b>Q3. 🔥 How does Spring resolve circular dependencies, and when can't it?</b></summary>

For singleton field/setter injection it exposes an early reference through the three-level cache (`singletonFactories` → `earlySingletonObjects` → `singletonObjects`), so B can receive A before A is fully initialized. It can't for constructor injection (no instance yet), for prototype-scoped beans, or correctly when a post-processor that doesn't support early proxies (such as `@Async`) wraps the bean afterwards: then one side keeps the raw object (verified on Spring 7: an `@Async` call ran synchronously). Spring Boot disables circular references by default.
</details>

<details><summary><b>Q4. ⚡ JDK dynamic proxy vs CGLIB: what does Spring Boot use, and what breaks with each?</b></summary>

Boot defaults to CGLIB (`spring.aop.proxy-target-class=true`), which subclasses the bean class. It can't advise `final` classes or methods, and the proxy's own fields are uninitialized (Objenesis). JDK proxies implement the bean's interfaces only, so you can't inject or `getBean` by the concrete class, and only interface methods are advised. Both share the self-invocation limitation.
</details>

<details><summary><b>Q5. ⚡ `@Configuration` vs `@Configuration(proxyBeanMethods = false)`?</b></summary>

Full mode CGLIB-enhances the configuration class so that calling another `@Bean` method returns the container-managed singleton. Lite mode skips the enhancement (faster startup, AOT-friendly), so a direct call to another `@Bean` method is just a Java call that creates a new, unmanaged object (verified: `a.clock != b.clock`, and neither is the container's bean). In lite mode, express dependencies as `@Bean` method parameters.
</details>

<details><summary><b>Q6. ⚡ What does "Bean 'x' is not eligible for getting processed by all BeanPostProcessors" mean, and why care?</b></summary>

Bean `x` was created while the BPP chain was still being registered, typically because a BPP (or a non-static `@Bean` method in its configuration class) depends on it. Post-processors registered later never see `x`, so it may silently lack `@Transactional`/`@Async`/metrics proxies. Make BPP `@Bean` methods `static` and resolve their dependencies lazily (`ObjectProvider`, `@Lazy`).
</details>

<details><summary><b>Q7. 🧊 Where should "run once at startup" logic go: constructor, `@PostConstruct`, `SmartInitializingSingleton`, `ContextRefreshedEvent`, or `ApplicationReadyEvent`?</b></summary>

Not the constructor (no injection, no proxy). `@PostConstruct` runs before the bean's own proxy exists and before other singletons are guaranteed ready. `SmartInitializingSingleton` runs once all singletons are created (good for validation and warm-up). `ContextRefreshedEvent` can fire more than once (refreshable or child contexts). In Boot, `ApplicationReadyEvent` (after `ApplicationRunner`s, when the app is ready to serve) is the safest for work that touches other beans or external systems. For things that run continuously, implement `SmartLifecycle`.
</details>
