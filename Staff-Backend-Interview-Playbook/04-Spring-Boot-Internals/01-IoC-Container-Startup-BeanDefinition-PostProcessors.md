# 4.1 The IoC Container: `BeanDefinition`s, Post-Processors, the Full Bean Lifecycle, Scopes, and What Boot Auto-Configuration Really Does

> **Verified stack:** Spring Framework **7.0.10**, Spring Boot **4.1.2**, Temurin **25**. The lifecycle trace below was printed by a running application: every number is the real call order.
>
> **Go deeper:** the sibling kit's [6.1 container internals](../../Java-Backend-Master-Reference/06-Spring-Microservices/01-Spring-Container-Internals-IoC-AOP.md).

---

## 0. First principles: two phases, metadata first 🔥

Spring builds your application in two distinct phases:

1. **Metadata phase.** Read configuration (component scanning, `@Bean` methods, auto-configuration imports) into **`BeanDefinition`s**: *recipes* (class, scope, constructor arguments, property values, init/destroy methods, lazy flag, dependencies). **No application objects exist yet.** Post-processors may add, remove or edit recipes.
2. **Instance phase.** For each singleton recipe: instantiate, inject, call `Aware` callbacks, run `BeanPostProcessor`s (which may **replace** the bean with a proxy), run init callbacks.

Almost every "magic" feature is a post-processor operating in one of these phases:

| Feature | Phase | Mechanism |
|---|---|---|
| `@Configuration`/`@Bean`, `@ComponentScan`, `@Import` | Metadata | `ConfigurationClassPostProcessor` (a `BeanDefinitionRegistryPostProcessor`) |
| `${property}` placeholders | Metadata | `PropertySourcesPlaceholderConfigurer` (a `BeanFactoryPostProcessor`) |
| `@Autowired`, `@Value` | Instance | `AutowiredAnnotationBeanPostProcessor` |
| `@PostConstruct`/`@PreDestroy` | Instance | `CommonAnnotationBeanPostProcessor` |
| `@Transactional`, `@Async`, `@Cacheable`, `@Retryable` proxies | Instance (after init) | Auto-proxy creators / advising post-processors |
| Boot auto-configuration | Metadata | `@EnableAutoConfiguration` → `AutoConfigurationImportSelector` + `@Conditional*` evaluation |

---

## 1. The full lifecycle, verified 🔥

The lab registers one `BeanDefinitionRegistryPostProcessor`, one `BeanFactoryPostProcessor`, an `InstantiationAwareBeanPostProcessor`, a `Pricing` bean implementing every callback interface, a `SmartLifecycle`, Boot listeners and an `ApplicationRunner`, then closes the context:

```java
/** Runs BEFORE any bean definition is processed by BFPPs: can add definitions. */
static class RegistryPP implements BeanDefinitionRegistryPostProcessor {
    @Override public void postProcessBeanDefinitionRegistry(BeanDefinitionRegistry registry) {
        log("BeanDefinitionRegistryPostProcessor: registering 'dependency' programmatically (" + registry.getBeanDefinitionCount() + " definitions so far)");
        registry.registerBeanDefinition("dependency", new RootBeanDefinition(Dependency.class));
    }
    @Override public void postProcessBeanFactory(ConfigurableListableBeanFactory bf) { }
}

/** Runs after all definitions are loaded, before ANY bean (except post-processors) is instantiated: can edit definitions. */
static class FactoryPP implements BeanFactoryPostProcessor {
    @Override public void postProcessBeanFactory(ConfigurableListableBeanFactory bf) {
        log("BeanFactoryPostProcessor: setting property currency=USD on the 'pricing' BeanDefinition");
        bf.getBeanDefinition("pricing").getPropertyValues().add("currency", "USD");
    }
}

@Bean static RegistryPP registryPP() { return new RegistryPP(); }      // static: post-processors must exist
@Bean static FactoryPP factoryPP() { return new FactoryPP(); }         // before the config class is instantiated
@Bean static BeanPP beanPP() { return new BeanPP(); }

@Bean(initMethod = "customInit", destroyMethod = "customDestroy")
Pricing pricing() { return new Pricing(); }
```

**Output (verified):**

```text
 1. ApplicationEnvironmentPreparedEvent (Boot: before the context exists)
 2. ApplicationContextInitializedEvent
 3. ApplicationPreparedEvent (definitions loaded, refresh not started)
 4. BeanDefinitionRegistryPostProcessor: registering 'dependency' programmatically (13 definitions so far)
 5. BeanFactoryPostProcessor: setting property currency=USD on the 'pricing' BeanDefinition
 6. InstantiationAwareBPP.postProcessBeforeInstantiation (could return a proxy and skip creation)
 7. Pricing constructor (currency=EUR)
 8. InstantiationAwareBPP.postProcessAfterInstantiation
 9. @Autowired setter injection
10. property value applied: setCurrency(USD)  <- from the edited BeanDefinition
11. BeanNameAware.setBeanName(pricing)
12. BeanFactoryAware.setBeanFactory
13. ApplicationContextAware.setApplicationContext
14. BeanPostProcessor.postProcessBeforeInitialization
15. @PostConstruct (currency=USD)
16. InitializingBean.afterPropertiesSet
17. @Bean(initMethod) customInit
18. BeanPostProcessor.postProcessAfterInitialization  <- AOP proxies are created here
19. SmartInitializingSingleton.afterSingletonsInstantiated (all singletons exist)
20. SmartLifecycle.start (phase 1000)
21. ContextRefreshedEvent
22. ApplicationStartedEvent (Boot: context refreshed, runners not yet called)
23. ApplicationRunner.run
24. ApplicationReadyEvent (Boot: runners done, ready for traffic)
25. --- context running; closing ---
26. ContextClosedEvent (shutdown begins)
27. SmartLifecycle.stop
28. @PreDestroy
29. DisposableBean.destroy
30. @Bean(destroyMethod) customDestroy
```

What to take from each group:

| Steps | Lesson |
|---|---|
| 4–5 | Recipes can be **changed before anything exists**: step 5 changed `currency` on the *definition*, and step 10 shows the bean received `USD`. This is how property placeholders and many frameworks work |
| 6 | An `InstantiationAwareBeanPostProcessor` can return an object here and **skip normal creation** (used for some proxying and AOP target sources) |
| 7–10 | Construction, then field/setter injection, then definition property values. The constructor sees `EUR`, so **never use injected state in constructors** unless it's constructor-injected |
| 11–13 | `Aware` callbacks (13 is delivered by an internal BPP, which is why it lands with the BPP group) |
| 14–17 | Init callbacks run **in this order**: `@PostConstruct` → `afterPropertiesSet` → `initMethod`. Prefer `@PostConstruct` (or constructor logic); don't mix all three |
| 18 | **The bean you get from the container may not be the object you created.** AOP proxies replace it here. That's why `@PostConstruct` code runs on the *target*, and why a `@Transactional` method called from `@PostConstruct` isn't transactional (no proxy yet) |
| 19 | The safe point to use **other** beans for warm-up: all singletons exist |
| 20–24 | Startup ordering: `SmartLifecycle.start` (Kafka listener containers, schedulers and the web server start here, by phase) → refreshed → runners → **ready**. Readiness probes should follow `ApplicationReadyEvent` ([7.3](../07-Docker-JVM-Kubernetes/03-Kubernetes-Probes-and-Graceful-Shutdown.md)) |
| 26–30 | Shutdown is the mirror: lifecycle stop (graceful web shutdown, listener containers) **before** destroy callbacks. That's how Boot drains requests before closing the `DataSource` |

---

## 2. Scopes: the prototype-in-singleton trap (verified) ⚡

```java
@Bean @Scope("prototype") ShoppingCart cart() { return new ShoppingCart(); }
@Bean CheckoutStale checkoutStale(ShoppingCart cart) { return new CheckoutStale(cart); }                         // ❌
@Bean CheckoutFresh checkoutFresh(ObjectProvider<ShoppingCart> carts) { return new CheckoutFresh(carts); }      // ✅
```

**Output (verified):**

```text
== prototype injected into a singleton
  stale: 1, 1, 1   (same cart forever)
  fresh: 2, 3, 4   (ObjectProvider.getObject() each time)
```

Injection happens **once**, when the singleton is created, so a prototype injected into a singleton is effectively a singleton. Fixes: `ObjectProvider<T>` (or `Provider<T>`), method injection (`@Lookup`), or a scoped proxy (`@Scope(value = "request", proxyMode = TARGET_CLASS)`, the standard way to inject request- or session-scoped beans into singletons).

| Scope | Lifetime | Thread-safety concern |
|---|---|---|
| `singleton` (default) | One per container | **Shared by all request threads**: must be stateless or thread-safe |
| `prototype` | New per lookup; the container **doesn't call destroy callbacks** | Caller owns cleanup |
| `request` / `session` | Per HTTP request or session (web contexts) | Needs a scoped proxy to inject into singletons |
| `application` | Per `ServletContext` | Shared |

---

## 3. `@Configuration` vs "lite" `@Bean` methods (verified) 🔥

```java
@Configuration                                           // proxyBeanMethods = true (default): CGLIB-enhanced
static class FullConfig {
    @Bean Repo repo() { return new Repo(); }
    @Bean ServiceA serviceA() { return new ServiceA(repo()); }    // inter-bean method call
    @Bean ServiceB serviceB() { return new ServiceB(repo()); }
}

@Configuration(proxyBeanMethods = false)                 // "lite" mode: plain Java calls
static class LiteConfig { /* identical methods */ }
```

**Output (verified):**

```text
== @Configuration proxyBeanMethods
  FullConfig  config class=ContainerLab$FullConfig$$SpringCGLIB$$0  serviceA.repo == serviceB.repo ? true  == context bean ? true
  LiteConfig  config class=LiteConfig  serviceA.repo == serviceB.repo ? false  == context bean ? false
```

In full mode the configuration class is a **CGLIB subclass** that intercepts `repo()` and returns the container's singleton. In lite mode `repo()` is a plain Java call, so each service got its **own** `Repo`, and neither is the container's bean (three instances, two of them unmanaged: no proxies, no lifecycle).

Spring Boot's own auto-configurations use `proxyBeanMethods = false` (faster startup, AOT- and native-friendly). The rule that makes lite mode safe: **declare dependencies as `@Bean` method parameters** (`ServiceA serviceA(Repo repo)`), never call other `@Bean` methods directly.

---

## 4. What Boot auto-configuration actually did (verified) ⚡

A Boot app with `@EnableAutoConfiguration` and `spring-boot-starter-web`, actuator, JDBC and H2 on the classpath (run as a non-web application):

**Output (verified):**

```text
  bean definitions: 291
  auto-config classes/methods evaluated: 314 (matched 162, did not match 152)
  MATCH    TaskExecutionAutoConfiguration : @ConditionalOnClass found required class 'org.springframework.scheduling.concurrent.ThreadPoolTaskExecutor'
  MATCH    DataSourceAutoConfiguration : @ConditionalOnClass found required classes 'javax.sql.DataSource', 'org.springframework.jdbc.datasource.embedded.EmbeddedDatabaseType'
  MATCH    JdbcTemplateAutoConfiguration : @ConditionalOnClass found required classes 'javax.sql.DataSource', 'org.springframework.jdbc.core.JdbcTemplate'
  NO MATCH JndiDataSourceAutoConfiguration : @ConditionalOnProperty (spring.datasource.jndi-name) did not find property 'spring.datasource.jndi-name'
  NO MATCH XADataSourceAutoConfiguration : @ConditionalOnClass did not find required class 'jakarta.transaction.TransactionManager'
  NO MATCH DispatcherServletAutoConfiguration : not a servlet web application
  slowest startup steps:
    spring.context.refresh              2439 ms
    spring.context.beans.post-process   1072 ms
    spring.context.beandef-registry.post-process  702 ms
    spring.context.config-classes.parse  700 ms
```

How auto-configuration works (first principles):

1. `@EnableAutoConfiguration` imports `AutoConfigurationImportSelector`, a **deferred** import selector: it runs **after** your configuration is processed, so your beans are known first.
2. It reads candidate class names from `META-INF/spring/org.springframework.boot.autoconfigure.AutoConfiguration.imports` in every jar (the old `spring.factories` key was removed in Boot 3).
3. Each candidate is guarded by **conditions** evaluated against the classpath, properties and existing beans: `@ConditionalOnClass` (cheap, evaluated even before loading the class via ASM metadata), `@ConditionalOnProperty`, `@ConditionalOnMissingBean` (the **back-off** rule: define your own `DataSource` and Boot's steps aside), `@ConditionalOnWebApplication`, …
4. Ordering between auto-configurations uses `@AutoConfiguration(before = …, after = …)`.

The tools to see this in your own app: `--debug` (prints the condition evaluation report), `/actuator/conditions`, and `BufferingApplicationStartup` (used above; Actuator's `/actuator/startup` exposes it) to find slow startup steps.

> Boot 4 note: Boot 4 split the monolithic `spring-boot-autoconfigure` into **per-technology modules** (e.g. `spring-boot-jdbc`, `spring-boot-hibernate` appear on the classpaths used in this playbook), and `@SpringBootConfiguration` now lives in `org.springframework.boot` (a compile error in the lab revealed the move).

---

## 5. ❌ Naïve vs ✅ production-hardened container usage

| ❌ Naïve | ✅ Hardened |
|---|---|
| `@Bean` post-processor declared as a non-static method | `static @Bean` for `BeanFactoryPostProcessor`/`BeanPostProcessor` (otherwise the config class is instantiated too early, and its own beans miss processing) |
| Business logic calling `@Transactional` methods from `@PostConstruct` | Do warm-up in `SmartInitializingSingleton` or an `ApplicationReadyEvent` listener (proxies exist then) |
| Stateful singletons (`private List<Order> current`) | Stateless singletons; request state in method parameters or request scope |
| Prototype injected into a singleton | `ObjectProvider`, `@Lookup` or a scoped proxy |
| Calling other `@Bean` methods with `proxyBeanMethods = false` | Method parameters for dependencies |
| Guessing why a bean exists or not | `--debug`, `/actuator/conditions`, `/actuator/beans` |
| Slow startup, no data | `BufferingApplicationStartup` + `/actuator/startup`; AOT and the JDK AOT cache ([4.2](02-Circular-References-Singleton-Caches-AOT-CDS.md)) |

---

## 6. Source to read

| Repo | Path | What to look for |
|---|---|---|
| [spring-projects/spring-framework](https://github.com/spring-projects/spring-framework) | `spring-context/src/main/java/org/springframework/context/support/AbstractApplicationContext.java` | `refresh()`: the whole startup sequence in one method |
| spring-projects/spring-framework | `spring-context/src/main/java/org/springframework/context/support/PostProcessorRegistrationDelegate.java` | The ordering rules for BDRPP → BFPP → BPP (`PriorityOrdered`, `Ordered`, the rest) |
| spring-projects/spring-framework | `spring-beans/src/main/java/org/springframework/beans/factory/support/AbstractAutowireCapableBeanFactory.java` | `doCreateBean` → `populateBean` → `initializeBean`: steps 6–18 |
| spring-projects/spring-framework | `spring-context/src/main/java/org/springframework/context/annotation/ConfigurationClassEnhancer.java` | The CGLIB trick behind `proxyBeanMethods = true` |
| [spring-projects/spring-boot](https://github.com/spring-projects/spring-boot) | `core/spring-boot-autoconfigure/src/main/java/org/springframework/boot/autoconfigure/AutoConfigurationImportSelector.java` | Candidate loading, exclusions, filtering |
| spring-projects/spring-boot | `core/spring-boot/src/main/java/org/springframework/boot/SpringApplication.java` | `run()`: environment, context creation, refresh, runners, events |

*(Spring Boot 4 reorganized its source tree; if a path moved, search the repository for the class name.)*

---

## 7. Interview soundbites

* "Spring works in two phases: bean definitions first, which post-processors can add or edit, then instances, which bean post-processors can wrap. I printed all 30 lifecycle callbacks in order."
* "AOP proxies are created in `postProcessAfterInitialization`, so `@PostConstruct` runs on the raw target, and transactional calls from it aren't transactional."
* "A prototype injected into a singleton is created once. I use `ObjectProvider` or a scoped proxy."
* "With `proxyBeanMethods = false`, calling another `@Bean` method creates a new unmanaged object. I pass dependencies as parameters."
* "Auto-configuration is a deferred import of conditional configurations that back off when you define your own bean. `--debug` showed 162 matched and 152 skipped, each with the reason."

---

## 8. Deep dive: property-source precedence, condition timing, and the frozen bean graph (verified) 🔥

### 8.1 Where a property value actually comes from (verified)

One key, `lab.key`, set in five places: `SpringApplicationBuilder.properties(...)`, `application.properties`, the OS environment (`LAB_KEY`), `-Dlab.key`, and `--lab.key`. The app prints the resolved value and walks `environment.getPropertySources()` in order:

**Output (verified):**

```text
RESOLVED lab.key = from-command-line
   1. configurationProperties                lab.key=from-command-line
   2. commandLineArgs                        lab.key=from-command-line
   3. systemProperties                       lab.key=from-system-property
   4. systemEnvironment                      lab.key=from-OS-environment
   5. random
   6. Config resource 'class path resource [application.properties]' via location 'optional:classpath:/' lab.key=from-application.properties
   7. applicationInfo
   8. defaultProperties                      lab.key=from-builder-properties (default properties)
```

Without `--lab.key` and `-D`, the result was `from-OS-environment`; with only the file and the defaults, `from-application.properties`.

**Reading it:**

* **`configurationProperties`** isn't a real source. It's Boot's relaxed-binding view over all the others, attached first, so it always shows the winner.
* **`LAB_KEY` matched `lab.key`** through relaxed binding (`SystemEnvironmentPropertySource`): the uppercase-and-underscore form is how containers and Kubernetes inject configuration.
* **`SpringApplicationBuilder.properties(…)` / `setDefaultProperties(…)` are the *lowest* precedence.** This bit the [5.11](../05-Microservices-Patterns/11-Modular-Monolith-Blueprint-Spring-Modulith-Externalized-Events-Extraction.md) lab: overrides passed that way silently lost to `application.properties`, so `schema.sql` re-ran in every simulated restart. Tests should use `--k=v`, `@TestPropertySource` or `@DynamicPropertySource`, which all outrank packaged files.
* **Profile-specific files, `spring.config.import` (including `configtree:` for Kubernetes-mounted secrets) and `SPRING_APPLICATION_JSON`** slot into the same ordered list. The operational rule: the jar carries defaults, the deployment carries environment-specific values, and secrets come from env vars or a config tree, never from a packaged file.

### 8.2 When conditions run relative to *your* configuration (verified in 4.7)

| Where the `@ConditionalOnBean` lives | Sees auto-configured beans? | Evidence |
|---|---|---|
| Auto-configuration with `after = …` the bean's auto-configuration | ✅ yes | [4.7 §5.2](07-Auto-Configuration-Internals-Production-Starter-Blueprint.md#52-ordering-trap-1-an-auto-configuration-without-after-verified-) 6b: `MATCH … found bean 'jdbcClient'` |
| Auto-configuration **without** `after` | ❌ no, if it sorts earlier by name | 4.7 §5.2 6: `com.acme…` evaluated first → `NO MATCH`, although the context ended with `JdbcClient beans=1` |
| Application `@Configuration` | ❌ never | [4.7 §5.3](07-Auto-Configuration-Internals-Production-Starter-Blueprint.md#53-ordering-trap-2-conditionalonbean-in-application-configuration-verified-): `NO MATCH`, `JdbcClient beans=1` |

This is the flip side of §4's "back-off" rule. Your configuration is registered *before* the deferred auto-configurations, so `@ConditionalOnMissingBean` in an auto-configuration sees your bean. By the same ordering, `@ConditionalOnBean` in your code never sees theirs.

### 8.3 Spring AOT turns the bean graph into a build artifact (verified in 4.2)

With `process-aot`, a bean guarded by `@ConditionalOnBooleanProperty` and another by `@Profile("eu")` were **absent at runtime** even with `--feature.audit.enabled=true --spring.profiles.active=eu`, and the environment *reported* both settings. The 46 bean registrations had been generated at build time ([4.2 §9](02-Circular-References-Singleton-Caches-AOT-CDS.md#9-deep-dive-spring-aot-freezes-conditions-and-the-proxy-field-trap-in-production-verified-)). §1's two-phase model still holds; AOT just runs phase one in the build.

---

## Summary

| Topic | Key point | Evidence |
|---|---|---|
| Two phases | Bean definitions first (registry/factory post-processors can change them), then instances (bean post-processors can wrap them) | §1: all 30 lifecycle callbacks in order |
| Proxies vs `@PostConstruct` | Proxies are created in `postProcessAfterInitialization`; `@PostConstruct` runs on the raw target | §1 |
| Scopes | A prototype injected into a singleton is created once: `ObjectProvider` or a scoped proxy | §2 |
| `proxyBeanMethods = false` | Inter-`@Bean` calls create unmanaged objects: pass dependencies as parameters | §3 |
| Auto-configuration | Deferred, conditional imports that back off for your beans | §4: 314 evaluated, 162 matched |
| Property precedence | Command line > system properties > OS env (relaxed) > config files > default properties | §8.1 |
| Condition timing | User config before auto-config: `@ConditionalOnBean` only belongs in ordered auto-configurations | §8.2 |
| AOT | Conditions and profiles are decided at build time | §8.3 |

**Next:** [4.2 Circular references, singleton caches, AOT & CDS →](02-Circular-References-Singleton-Caches-AOT-CDS.md)
