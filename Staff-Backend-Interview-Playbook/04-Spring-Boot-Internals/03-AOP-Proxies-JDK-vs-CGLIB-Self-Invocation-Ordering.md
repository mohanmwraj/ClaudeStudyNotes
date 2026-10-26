# 4.3 AOP & Dynamic Proxies: JDK vs CGLIB, the Interceptor Chain, Self-Invocation, Advice Ordering (incl. `@Retryable` vs `@Transactional`)

> **Verified stack:** Spring Framework **7.0.10** (`@EnableAspectJAutoProxy`, `@EnableTransactionManagement`, `@EnableResilientMethods`), AspectJ weaver **1.9.25.1** (for `@Aspect` annotations only; weaving still uses proxies), PostgreSQL **18.6** for real transactions. Transaction begin/commit/rollback lines come from a `TransactionExecutionListener` registered on the transaction manager.

---

## 0. First principles: interception needs an object in between 🔥

Cross-cutting behavior (transactions, security, caching, retries, metrics) must run **around** your method without you calling it. In plain Java, the only ways to do that are:

1. **Put an object in front of yours** that has the same type and forwards calls: a **proxy** (Spring AOP's approach, decided at runtime).
2. **Rewrite your bytecode** so the extra logic is inside your methods: **weaving** (AspectJ, at compile time or class-load time).

Spring uses proxies by default. Every "my annotation doesn't work" bug comes from the proxy's geometry: **only calls that go through the proxy object are intercepted.**

Two ways to build a proxy:

| | JDK dynamic proxy | CGLIB (Spring's repackaged copy) |
|---|---|---|
| Mechanism | `java.lang.reflect.Proxy` generates a class **implementing the interfaces**; calls go to an `InvocationHandler` | Generates a **subclass** of your class that overrides each method |
| Requires | At least one interface | A non-final class, overridable (non-final, non-private) methods |
| Injectable as | The interface type only | The class or its interfaces |
| Spring Boot default | — | `spring.aop.proxy-target-class=true` (CGLIB even when interfaces exist) |

(Hibernate and Mockito use ByteBuddy for the same subclass trick.)

---

## 1. Proxy types, verified 🔥

With plain Spring and `@EnableAspectJAutoProxy(proxyTargetClass = false)`:

```java
public interface Greeter { String greet(); }
public static class GreeterImpl implements Greeter { @Transactional public String greet() { return "hi"; } ... }
public static class OrderService { @Transactional @Retryable(maxRetries = 2, delay = 10) public String process() { ... } ... }
```

**Output (verified):**

```text
== Proxy types (proxyTargetClass = false)
  bean implementing an interface -> $Proxy26  jdkProxy=true
  getBean(GreeterImpl.class) -> NoSuchBeanDefinitionException
  class without interfaces       -> AopLab$OrderService$$SpringCGLIB$$0  cglibProxy=true
```

* The interface-based bean became a **JDK proxy** (`$Proxy26`), which **isn't a `GreeterImpl`**, so looking it up (or injecting it) by the implementation class fails. That's why Boot defaults to class-based proxies: it avoids exactly this surprise.
* The class without interfaces got a **CGLIB subclass** (`…$$SpringCGLIB$$0`).

---

## 2. What happens inside a proxied call ⚡

```text
caller ─► proxy.process()
            └─ CglibAopProxy.DynamicAdvisedInterceptor.intercept()
                 1. get the interceptor chain for this Method (cached): advisors whose pointcut matches, sorted by order
                 2. new CglibMethodInvocation(target, method, args, chain)
                 3. invocation.proceed():
                       interceptor[0].invoke(inv)  → e.g. retry   ─┐ each interceptor decides whether/when
                       interceptor[1].invoke(inv)  → @Order(1)     │ to call inv.proceed() again, and
                       interceptor[2].invoke(inv)  → @Order(2)     │ wraps it in try/catch/finally
                       interceptor[3].invoke(inv)  → transaction  ─┘
                       … finally target.process() via reflection / MethodProxy
```

An **advisor** = a **pointcut** (which methods) + an **advice** (what to do). `@Transactional` contributes the `BeanFactoryTransactionAttributeSourceAdvisor`. Your `@Aspect` classes are turned into advisors by `AnnotationAwareAspectJAutoProxyCreator`, a `BeanPostProcessor` that wraps beans in `postProcessAfterInitialization` ([4.1 §1](01-IoC-Container-Startup-BeanDefinition-PostProcessors.md), step 18).

---

## 3. Self-invocation and its fixes 🔥

`this.inner()` from inside the bean calls the **target**, not the proxy, so no interceptor runs (verified in [3.5 §1](../03-JPA-Hibernate-Spring-Data/05-Transactional-Propagation-Isolation-Pitfalls.md): `self-invoked inner: NO transaction`). Fixes:

```java
@EnableAspectJAutoProxy(proxyTargetClass = false, exposeProxy = true)   // exposes the current proxy in a ThreadLocal

public String outer() { return "self via AopContext: " + ((OrderService) AopContext.currentProxy()).inner(); }
@Transactional public String inner() { ... }
```

**Output (verified):**

```text
== Self-invocation fixed with exposeProxy + AopContext.currentProxy()
     [tx BEGIN]
     [tx COMMIT]
  self via AopContext: tx ACTIVE
```

It works, but it couples your code to Spring AOP. In order of preference: **split into two beans** → `TransactionTemplate`/programmatic API → self-injection with `@Lazy` → `AopContext` → AspectJ weaving.

---

## 4. Advice ordering, verified 🧊

Rules:

* `@Order` / `Ordered` on aspects: **lower value = higher precedence = outermost** on the way in, innermost on the way out.
* `@Transactional`'s advisor has `Ordered.LOWEST_PRECEDENCE` by default, so it ends up **innermost** relative to ordered aspects. Change it with `@EnableTransactionManagement(order = …)`.
* Spring 7's `@Retryable` (`@EnableResilientMethods`) adds its own interceptor. Where does it land relative to transactions?

The lab puts two ordered aspects, `@Retryable(maxRetries = 2)` and `@Transactional` on **one method** that fails twice:

```java
@Aspect @Order(1)
public static class OuterAspect {
    @Around("execution(* p4.AopLab.OrderService.process(..))")
    public Object around(ProceedingJoinPoint pjp) throws Throwable {
        System.out.println("  -> @Order(1) aspect");
        try { return pjp.proceed(); } finally { System.out.println("  <- @Order(1) aspect"); }
    }
}
// InnerAspect identical with @Order(2)

@Transactional
@Retryable(maxRetries = 2, delay = 10)
public String process() {
    int n = calls.incrementAndGet();
    System.out.println("      method body, call #" + n + ", tx active=" + TransactionSynchronizationManager.isActualTransactionActive());
    if (n < 3) throw new IllegalStateException("transient failure #" + n);
    return "done";
}
```

**Output (verified):**

```text
== @Order(1) aspect, @Order(2) aspect, @Retryable and @Transactional on one method
  -> @Order(1) aspect
    -> @Order(2) aspect
     [tx BEGIN]
      method body, call #1, tx active=true
     [tx ROLLBACK]
    <- @Order(2) aspect
  <- @Order(1) aspect
  -> @Order(1) aspect
    -> @Order(2) aspect
     [tx BEGIN]
      method body, call #2, tx active=true
     [tx ROLLBACK]
    <- @Order(2) aspect
  <- @Order(1) aspect
  -> @Order(1) aspect
    -> @Order(2) aspect
     [tx BEGIN]
      method body, call #3, tx active=true
     [tx COMMIT]
    <- @Order(2) aspect
  <- @Order(1) aspect
  result: done
```

Reading it from the outside in:

1. **The retry interceptor is outermost**, even outside `@Order(1)`: every attempt re-enters *both* aspects. (Spring's advising post-processors for `@Async`/`@Retryable` add their advisor at the front of an existing proxy's chain.)
2. `@Order(1)` wraps `@Order(2)`, as documented.
3. **The transaction is innermost**, and each attempt gets a **fresh transaction** (BEGIN/ROLLBACK, BEGIN/ROLLBACK, BEGIN/COMMIT). That's exactly what retries of database work need ([3.5 §6](../03-JPA-Hibernate-Spring-Data/05-Transactional-Propagation-Isolation-Pitfalls.md)).

Practical consequences:

* A logging or metrics aspect at `@Order(1)` here logs **each attempt** separately. If you want one log line per logical call, the aspect must be outside the retry (a different bean, or explicit ordering of the retry interceptor where your retry library allows it).
* An aspect that must run **inside** the transaction (writing an audit row in the same transaction) needs a higher order value than the transaction advisor: e.g. `@EnableTransactionManagement(order = 100)` and `@Order(200)` on the aspect.
* Ordering between proxies from **different mechanisms** (Spring Retry library, Resilience4j aspects, custom BPPs) isn't uniform. Print the chain (`((Advised) bean).getAdvisors()`) or log entry/exit as above instead of guessing.

---

## 5. Limits of proxy-based AOP (verified where noted) ⚡

```text
== final method on a class-based (CGLIB) proxy
WARN org.springframework.aop.framework.CglibAopProxy -- Public final method [public final java.lang.String p4.AopLab$GreeterImpl.finalGreet()] cannot get proxied via CGLIB, consider removing the final marker or using interface-based JDK proxies.
  proxy class: AopLab$GreeterImpl$$SpringCGLIB$$0
  finalGreet(): NO tx   (final methods can't be overridden, so no interception)
```

| Not intercepted | Why | Notes |
|---|---|---|
| `final` methods (verified) | A subclass can't override them | Spring logs a WARN. Worse: the call runs **on the proxy instance**, whose fields are uninitialized, which can throw NPEs |
| `private` methods (verified in [3.5](../03-JPA-Hibernate-Spring-Data/05-Transactional-Propagation-Isolation-Pitfalls.md)) | Not overridable | |
| Self-invocation (`this.x()`) (verified) | Bypasses the proxy | |
| Constructors, static methods, field access | Not method calls on the proxy | AspectJ can intercept these |
| Objects you `new` yourself | Spring never wrapped them | `@Configurable` + AspectJ, or let Spring create them |
| Kotlin classes (final by default) | No subclassing | The `kotlin-spring` (all-open) compiler plugin opens them |

**Identity side effects:** the proxy is a different object from the target. `this` inside the bean is the target, `getClass()` returns the proxy class, and fields read directly on a proxy are empty ([4.2 §3](02-Circular-References-Singleton-Caches-AOT-CDS.md) showed `field b = null`).

---

## 6. When to use AspectJ weaving instead 🧊

| Need | Proxy AOP | AspectJ (compile-time or load-time weaving) |
|---|---|---|
| Self-invocation, private methods, field access | ❌ | ✅ (the code itself is changed) |
| Domain objects not created by Spring | ❌ | ✅ |
| Build simplicity | ✅ | ❌ (ajc/weaver agent, tooling) |
| Startup cost | Proxy generation at startup | Weaving at build or load time |

Spring supports both: `@EnableTransactionManagement(mode = AdviceMode.ASPECTJ)` switches transactions to AspectJ weaving. Most teams stay with proxies and design around their limits.

---

## 7. ❌ Naïve vs ✅ production-hardened AOP

| ❌ Naïve | ✅ Hardened |
|---|---|
| Inject `GreeterImpl` (the class) with JDK proxies | Inject interfaces, or use class-based proxies (Boot default) |
| `final` service classes/methods with `@Transactional` | Non-final (or interface-based proxies). Watch for CglibAopProxy WARNs in logs |
| `AopContext.currentProxy()` everywhere | Split beans; programmatic transactions |
| Assume aspect order | Set explicit `@Order`s; verify with logging or `Advised.getAdvisors()` |
| Audit aspect expected inside the transaction | Order it after the transaction advisor explicitly |
| Logging aspect counting "requests" around a retried method | Know it runs per attempt when the retry is outermost |

---

## 8. Source to read

| Repo | Path | What to look for |
|---|---|---|
| [spring-projects/spring-framework](https://github.com/spring-projects/spring-framework) | `spring-aop/src/main/java/org/springframework/aop/framework/CglibAopProxy.java` | `DynamicAdvisedInterceptor`, the final-method warning |
| spring-projects/spring-framework | `spring-aop/src/main/java/org/springframework/aop/framework/JdkDynamicAopProxy.java` | `invoke()`: equals/hashCode handling, chain retrieval |
| spring-projects/spring-framework | `spring-aop/src/main/java/org/springframework/aop/framework/ReflectiveMethodInvocation.java` | `proceed()`: walking the interceptor chain |
| spring-projects/spring-framework | `spring-aop/src/main/java/org/springframework/aop/framework/DefaultAdvisorChainFactory.java` | How matching advisors become the per-method chain |
| spring-projects/spring-framework | `spring-aop/src/main/java/org/springframework/aop/framework/AbstractAdvisingBeanPostProcessor.java` | `beforeExistingAdvisors`: why `@Async`/`@Retryable` advice lands outermost |
| spring-projects/spring-framework | `spring-aop/src/main/java/org/springframework/aop/aspectj/annotation/AnnotationAwareAspectJAutoProxyCreator.java` | `@Aspect` → advisors |

---

## 9. Interview soundbites

* "Spring AOP is proxies: JDK proxies implement interfaces, CGLIB subclasses your class. Boot defaults to CGLIB because a JDK proxy isn't an instance of your class; I reproduced the `NoSuchBeanDefinitionException`."
* "Only calls through the proxy are intercepted: no self-invocation, no private, no final. Spring even logs a warning for final methods."
* "`@Order(1)` is outermost. `@Transactional` is lowest precedence by default, so it's innermost. And Spring 7's `@Retryable` lands outside everything, so each retry is a new transaction and re-enters my aspects."

---

## 10. Deep dive: proxy boundaries in a production-shaped system (verified) 🔥

The labs in Batch 2 ran the same proxy mechanics as §1–§5 inside real systems. Four results that matter in design reviews:

| Situation | What happened | Evidence |
|---|---|---|
| **`@KafkaListener` + `@Transactional` on the same method** | The listener container invokes the method *through* the transactional proxy. A thrown exception rolls back the inbox row, state change and outbox row together, then the Kafka error handler redelivers | [5.10 scenario 5](../05-Microservices-Patterns/10-Reference-Implementation-Saga-Orchestrator-Kafka-Outbox-Inbox-CQRS.md#scenario-5-crash-between-deciding-and-committing): 1 crash, 1 failed delivery, exactly 1 `AuthorizePayment` and 1 payment |
| **`@Async` picks its executor at call time** | Adding one `ThreadPoolTaskExecutor` bean made Boot drop `applicationTaskExecutor`. Every un-qualified `@Async` moved to it, and the MDC-propagating `TaskDecorator` stopped applying | [4.8 §3](08-Request-Lifecycle-Events-Async-Graceful-Shutdown.md#3-async-which-executor-what-context-where-exceptions-go-verified-): `report-1 requestId=null` vs `task-1 requestId=req-42` with `spring.task.execution.mode=force` |
| **Fields on proxied beans** | A public field read through a CGLIB proxy was `null` | [4.2 §9.2](02-Circular-References-Singleton-Caches-AOT-CDS.md#92-the-proxy-field-trap-met-again-in-a-production-shaped-system-verified): NPE in the saga lab |
| **`@TransactionalEventListener` + `@Transactional`** | Spring 6.1+ rejects the combination at startup unless `REQUIRES_NEW`/`NOT_SUPPORTED` | [4.8 §2.1](08-Request-Lifecycle-Events-Async-Graceful-Shutdown.md#21-the-after_commit-write-trap-proven-both-ways-): the exact `IllegalStateException` message |

**The common thread:** an annotation is a request to a proxy, and its meaning depends on *which* proxy, *which* infrastructure bean and *which* thread end up handling the call.

* **The listener case is the good one:** the container calls through the proxy, so the transaction wraps the listener invocation.
* **The `@Async` case changed behaviour without a code change** at the call site: a bean definition elsewhere decided the executor.

Design rules:

* Qualify `@Async("executorName")`.
* Keep state behind methods.
* Assert the infrastructure you rely on in a startup test, for example "`applicationTaskExecutor` exists and has the decorator".

---

## Summary

| Topic | Key point | Evidence |
|---|---|---|
| Proxy types | JDK proxies implement interfaces; CGLIB subclasses (Boot's default) | §1: `NoSuchBeanDefinitionException` with JDK proxies |
| Interception scope | Only calls through the proxy: no self-invocation, private or final methods | §3, §5 |
| Advice order | `@Order(1)` outermost; `@Transactional` innermost by default; Spring 7 `@Retryable` outside, so each retry is a new transaction | §4 |
| Listener + transaction | The Kafka container calls through the proxy: rollback + redelivery, exactly-once effects | §10 (5.10 scenario 5) |
| `@Async` executor choice | Decided by infrastructure beans at call time; one `Executor` bean changes it | §10 (4.8 §3) |
| Proxy fields | Read through the proxy → `null` | §10 (4.2 §9.2) |

**Next:** [4.4 Web concurrency: Tomcat threads vs virtual threads vs WebFlux →](04-Web-Concurrency-Tomcat-Virtual-Threads-WebFlux.md)
