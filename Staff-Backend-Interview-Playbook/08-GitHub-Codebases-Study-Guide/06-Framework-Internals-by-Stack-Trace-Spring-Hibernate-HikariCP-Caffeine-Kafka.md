# 8.6 Framework Internals by Stack Trace: Spring, Hibernate, HikariCP, Caffeine, spring-kafka

> **Verified 2026-10-26** with one Spring Boot 4.1.2 application against PostgreSQL 18.6, and a spring-kafka 4.1.2 listener on an embedded Kafka 4.2.2 KRaft broker:
> * The stacks below were captured from the running code: `Thread.getStackTrace()` inside the method, `Thread.getAllStackTraces()` for a blocked thread, and `HotSpotDiagnosticMXBean.dumpThreads` for a virtual thread.
> * Every linked frame points to the **exact source line at the release tag of the jar that ran**: Spring Framework `v7.0.10`, Boot `v4.1.2`, Hibernate `7.4.13`, HikariCP `HikariCP-7.0.2`, Tomcat `11.0.27`, Caffeine `v3.2.4`, spring-kafka `v4.1.2`, Kafka `4.2.2`, JDK `jdk-25.0.4.1+1`.
> * A script mapped **all 653 library frames** in the captured stacks to their source and checked each one: the line exists at that tag and lies inside the method the frame names. That's how you know the jar was built from the tag. The tables below show the frames worth knowing.
> * Both labs ran twice with identical output, apart from timings and thread ids.
>
> **Pairs with:** [4.3 AOP proxies](../04-Spring-Boot-Internals/03-AOP-Proxies-JDK-vs-CGLIB-Self-Invocation-Ordering.md), [4.8 request lifecycle](../04-Spring-Boot-Internals/08-Request-Lifecycle-Events-Async-Graceful-Shutdown.md), [3.2 ActionQueue](../03-JPA-Hibernate-Spring-Data/02-ActionQueue-Flush-Ordering.md), [3.5 `@Transactional`](../03-JPA-Hibernate-Spring-Data/05-Transactional-Propagation-Isolation-Pitfalls.md), [6.3 Caffeine](../06-Resilience-Caching/03-Caching-Caffeine-W-TinyLFU-and-Redis-Lettuce-L1-L2.md), [10.2 consumers](../10-Kafka-Production/02-Kafka-Consumers-Rebalancing-EOS-Retries-DLQ.md), [8.4 HikariCP internals](04-High-Performance-Internals-HikariCP-Resilience4j-Caffeine.md).

---

## 0. Read the stack before you read the source 🔥

Spring Framework has about 11,000 files, Hibernate 19,000. A stack trace tells you which twenty of them ran for one request, in what order, and on which line. Three habits follow from that:

1. **Start from a frame you own, read outward.** The frame just below your method is the framework deciding to call you; the frame just above it (in a thread dump, the top) is where the thread is now.
2. **Read the source at the tag of the jar you run, not `main`.** The Boot 4.1.2 BOM manages **Caffeine 3.2.4**, even though this kit's Caffeine lab used 3.3.1, and **HikariCP 7.0.2**, whose `requite` differs from `dev` ([8.4 §6](04-High-Performance-Internals-HikariCP-Resilience4j-Caffeine.md)). Line numbers in a stack trace only match the source at the right tag.
3. **Capture, don't guess.** One line does it:

```java
// lab/Trace.java (excerpt): write the calling thread's stack to out/stack-<label>.txt
public static void capture(String label) {
    StackTraceElement[] all = Thread.currentThread().getStackTrace();
    // drop Thread.getStackTrace and Trace itself, then write one frame per line
}
```

The lab called `Trace.capture(...)` inside a controller, a `@Transactional` method, a `TransactionSynchronization`, a Hibernate `StatementInspector`, two `@Cacheable` methods, a `@TransactionalEventListener`, a `@KafkaListener` and a Kafka recoverer. Everything below is those captures.

---

## 1. One HTTP request: socket → Tomcat → `DispatcherServlet` → your controller ⚡

`POST /orders` on Tomcat 11.0.27 with Spring MVC 7.0.10. The full stack has 44 frames. The rows below are the ones worth knowing; read them **bottom-up**, the way the request travels.

| # | Frame | Source at the tag |
|---|---|---|
| 44 | `Thread.run` | [L1474](https://github.com/openjdk/jdk25u/blob/jdk-25.0.4.1+1/src/java.base/share/classes/java/lang/Thread.java#L1474) |
| 41 | `ThreadPoolExecutor.runWorker` | [L947](https://github.com/apache/tomcat/blob/11.0.27/java/org/apache/tomcat/util/threads/ThreadPoolExecutor.java#L947) |
| 39 | `NioEndpoint$SocketProcessor.doRun` | [L2202](https://github.com/apache/tomcat/blob/11.0.27/java/org/apache/tomcat/util/net/NioEndpoint.java#L2202) |
| 36 | `Http11Processor.service` | [L411](https://github.com/apache/tomcat/blob/11.0.27/java/org/apache/coyote/http11/Http11Processor.java#L411) |
| 35 | `CoyoteAdapter.service` | [L347](https://github.com/apache/tomcat/blob/11.0.27/java/org/apache/catalina/connector/CoyoteAdapter.java#L347) |
| 34 | `StandardEngineValve.invoke` | [L71](https://github.com/apache/tomcat/blob/11.0.27/java/org/apache/catalina/core/StandardEngineValve.java#L71) |
| 29 | `StandardWrapperValve.invoke` | [L164](https://github.com/apache/tomcat/blob/11.0.27/java/org/apache/catalina/core/StandardWrapperValve.java#L164) |
| 26 | `CharacterEncodingFilter.doFilterInternal` | [L199](https://github.com/spring-projects/spring-framework/blob/v7.0.10/spring-web/src/main/java/org/springframework/web/filter/CharacterEncodingFilter.java#L199) |
| 20 | `RequestContextFilter.doFilterInternal` | [L100](https://github.com/spring-projects/spring-framework/blob/v7.0.10/spring-web/src/main/java/org/springframework/web/filter/RequestContextFilter.java#L100) |
| 16 | `HttpServlet.service` | [L710](https://github.com/apache/tomcat/blob/11.0.27/java/jakarta/servlet/http/HttpServlet.java#L710) |
| 14 | `HttpServlet.service` | [L649](https://github.com/apache/tomcat/blob/11.0.27/java/jakarta/servlet/http/HttpServlet.java#L649) |
| 10 | `DispatcherServlet.doDispatch` | [L963](https://github.com/spring-projects/spring-framework/blob/v7.0.10/spring-webmvc/src/main/java/org/springframework/web/servlet/DispatcherServlet.java#L963) |
| 9 | `AbstractHandlerMethodAdapter.handle` | [L86](https://github.com/spring-projects/spring-framework/blob/v7.0.10/spring-webmvc/src/main/java/org/springframework/web/servlet/mvc/method/AbstractHandlerMethodAdapter.java#L86) |
| 7 | `RequestMappingHandlerAdapter.invokeHandlerMethod` | [L934](https://github.com/spring-projects/spring-framework/blob/v7.0.10/spring-webmvc/src/main/java/org/springframework/web/servlet/mvc/method/annotation/RequestMappingHandlerAdapter.java#L934) |
| 6 | `ServletInvocableHandlerMethod.invokeAndHandle` | [L117](https://github.com/spring-projects/spring-framework/blob/v7.0.10/spring-webmvc/src/main/java/org/springframework/web/servlet/mvc/method/annotation/ServletInvocableHandlerMethod.java#L117) |
| 5 | `InvocableHandlerMethod.invokeForRequest` | [L184](https://github.com/spring-projects/spring-framework/blob/v7.0.10/spring-web/src/main/java/org/springframework/web/method/support/InvocableHandlerMethod.java#L184) |
| 4 | `InvocableHandlerMethod.doInvoke` | [L252](https://github.com/spring-projects/spring-framework/blob/v7.0.10/spring-web/src/main/java/org/springframework/web/method/support/InvocableHandlerMethod.java#L252) |

What the stack shows that diagrams usually don't:

* **One Tomcat worker (`http-nio-18081-exec-1`) carries everything.** The same thread later runs the transaction, the flush, the commit and the after-commit listener (§2–§3). With platform threads, Tomcat's pool size is your concurrency limit ([4.4](../04-Spring-Boot-Internals/04-Web-Concurrency-Tomcat-Virtual-Threads-WebFlux.md)).
* **Filters are just frames.** `CharacterEncodingFilter`, `FormContentFilter`, `RequestContextFilter` and Tomcat's `WsFilter` each appear as a `doFilter` frame between `StandardWrapperValve` and the servlet. Spring Security wasn't on this classpath; with it, `FilterChainProxy` and its chain would sit in the same place ([4.5](../04-Spring-Boot-Internals/05-Security-Filter-Chain-JWT-Method-Security-Rate-Limiting.md)).
* **`DispatcherServlet.doDispatch` line 935** is the method to read first: handler lookup, interceptors, the handler adapter, exception resolution. Frame 10 calls the adapter from inside it, at line 963.

---

## 2. One `@Transactional` call: what the proxy does around your method 🔥

The same request, one level deeper: `OrderController.place` calls `OrderService.place`, which is `@Transactional`.

| # | Frame | Source at the tag |
|---|---|---|
| 11 | `CglibAopProxy$DynamicAdvisedInterceptor.intercept` | [L714](https://github.com/spring-projects/spring-framework/blob/v7.0.10/spring-aop/src/main/java/org/springframework/aop/framework/CglibAopProxy.java#L714) |
| 10 | `ReflectiveMethodInvocation.proceed` | [L179](https://github.com/spring-projects/spring-framework/blob/v7.0.10/spring-aop/src/main/java/org/springframework/aop/framework/ReflectiveMethodInvocation.java#L179) |
| 9 | `TransactionInterceptor.invoke` | [L130](https://github.com/spring-projects/spring-framework/blob/v7.0.10/spring-tx/src/main/java/org/springframework/transaction/interceptor/TransactionInterceptor.java#L130) |
| 8 | `TransactionAspectSupport.invokeWithinTransaction` | [L371](https://github.com/spring-projects/spring-framework/blob/v7.0.10/spring-tx/src/main/java/org/springframework/transaction/interceptor/TransactionAspectSupport.java#L371) |
| 7 | `TransactionInterceptor$1.proceedWithInvocation` | [L133](https://github.com/spring-projects/spring-framework/blob/v7.0.10/spring-tx/src/main/java/org/springframework/transaction/interceptor/TransactionInterceptor.java#L133) |
| 6 | `ReflectiveMethodInvocation.proceed` | [L158](https://github.com/spring-projects/spring-framework/blob/v7.0.10/spring-aop/src/main/java/org/springframework/aop/framework/ReflectiveMethodInvocation.java#L158) |
| 5 | `ReflectiveMethodInvocation.invokeJoinpoint` | [L190](https://github.com/spring-projects/spring-framework/blob/v7.0.10/spring-aop/src/main/java/org/springframework/aop/framework/ReflectiveMethodInvocation.java#L190) |

* Frame 12 is the **CGLIB subclass** (`OrderService$$SpringCGLIB$$1.place`). Frames 11 → 6 are the advice chain; frame 8 is [`TransactionAspectSupport.invokeWithinTransaction`](https://github.com/spring-projects/spring-framework/blob/v7.0.10/spring-tx/src/main/java/org/springframework/transaction/interceptor/TransactionAspectSupport.java#L333), which had already begun the transaction (`createTransactionIfNecessary`, line 628, visible in §4) before it called your method at line 371.
* After your method returns, the same method continues at [line 408](https://github.com/spring-projects/spring-framework/blob/v7.0.10/spring-tx/src/main/java/org/springframework/transaction/interceptor/TransactionAspectSupport.java#L408): `commitTransactionAfterReturning(txInfo)`. Everything in §3 hangs off that call.
* Call `this.place(...)` from inside `OrderService` and frames 6–12 simply aren't there: no proxy, no transaction. The review lab reproduces it ([8.9 R1](09-Staff-Level-System-and-Code-Review-Checklist-20-Questions.md)).

---

## 3. The commit, in order: `beforeCommit` → flush → JDBC commit → `afterCommit` → `@TransactionalEventListener` 🧊

`OrderService.place` registered a `TransactionSynchronization` and published an event. `repository.save()` returned before any `INSERT` was sent, because the id came from a sequence. A `StatementInspector` captured the stack at the moment the `INSERT` was prepared:

| # | Frame | Source at the tag |
|---|---|---|
| 39 | `TransactionAspectSupport.invokeWithinTransaction` | [L408](https://github.com/spring-projects/spring-framework/blob/v7.0.10/spring-tx/src/main/java/org/springframework/transaction/interceptor/TransactionAspectSupport.java#L408) |
| 38 | `TransactionAspectSupport.commitTransactionAfterReturning` | [L687](https://github.com/spring-projects/spring-framework/blob/v7.0.10/spring-tx/src/main/java/org/springframework/transaction/interceptor/TransactionAspectSupport.java#L687) |
| 37 | `AbstractPlatformTransactionManager.commit` | [L757](https://github.com/spring-projects/spring-framework/blob/v7.0.10/spring-tx/src/main/java/org/springframework/transaction/support/AbstractPlatformTransactionManager.java#L757) |
| 36 | `AbstractPlatformTransactionManager.processCommit` | [L794](https://github.com/spring-projects/spring-framework/blob/v7.0.10/spring-tx/src/main/java/org/springframework/transaction/support/AbstractPlatformTransactionManager.java#L794) |
| 35 | `JpaTransactionManager.doCommit` | [L552](https://github.com/spring-projects/spring-framework/blob/v7.0.10/spring-orm/src/main/java/org/springframework/orm/jpa/JpaTransactionManager.java#L552) |
| 34 | `TransactionImpl.commit` | [L89](https://github.com/hibernate/hibernate-orm/blob/7.4.13/hibernate-core/src/main/java/org/hibernate/engine/transaction/internal/TransactionImpl.java#L89) |
| 33 | `JdbcResourceLocalTransactionCoordinatorImpl$TransactionDriverControlImpl.commit` | [L242](https://github.com/hibernate/hibernate-orm/blob/7.4.13/hibernate-core/src/main/java/org/hibernate/resource/transaction/backend/jdbc/internal/JdbcResourceLocalTransactionCoordinatorImpl.java#L242) |
| 31 | `JdbcResourceLocalTransactionCoordinatorImpl.beforeCompletionCallback` | [L167](https://github.com/hibernate/hibernate-orm/blob/7.4.13/hibernate-core/src/main/java/org/hibernate/resource/transaction/backend/jdbc/internal/JdbcResourceLocalTransactionCoordinatorImpl.java#L167) |
| 29 | `SessionImpl.beforeTransactionCompletion` | [L2021](https://github.com/hibernate/hibernate-orm/blob/7.4.13/hibernate-core/src/main/java/org/hibernate/internal/SessionImpl.java#L2021) |
| 28 | `SessionImpl.flushBeforeTransactionCompletion` | [L2104](https://github.com/hibernate/hibernate-orm/blob/7.4.13/hibernate-core/src/main/java/org/hibernate/internal/SessionImpl.java#L2104) |
| 27 | `SessionImpl.managedFlush` | [L498](https://github.com/hibernate/hibernate-orm/blob/7.4.13/hibernate-core/src/main/java/org/hibernate/internal/SessionImpl.java#L498) |
| 26 | `SessionImpl.fireFlush` | [L1472](https://github.com/hibernate/hibernate-orm/blob/7.4.13/hibernate-core/src/main/java/org/hibernate/internal/SessionImpl.java#L1472) |
| 24 | `DefaultFlushEventListener.onFlush` | [L40](https://github.com/hibernate/hibernate-orm/blob/7.4.13/hibernate-core/src/main/java/org/hibernate/event/internal/DefaultFlushEventListener.java#L40) |
| 23 | `AbstractFlushingEventListener.performExecutions` | [L386](https://github.com/hibernate/hibernate-orm/blob/7.4.13/hibernate-core/src/main/java/org/hibernate/event/internal/AbstractFlushingEventListener.java#L386) |
| 22 | `ActionQueue.executeActions` | [L505](https://github.com/hibernate/hibernate-orm/blob/7.4.13/hibernate-core/src/main/java/org/hibernate/engine/spi/ActionQueue.java#L505) |
| 21 | `ActionQueue.executeActions` | [L634](https://github.com/hibernate/hibernate-orm/blob/7.4.13/hibernate-core/src/main/java/org/hibernate/engine/spi/ActionQueue.java#L634) |
| 20 | `EntityInsertAction.execute` | [L108](https://github.com/hibernate/hibernate-orm/blob/7.4.13/hibernate-core/src/main/java/org/hibernate/action/internal/EntityInsertAction.java#L108) |
| 19 | `InsertCoordinatorStandard.insert` | [L96](https://github.com/hibernate/hibernate-orm/blob/7.4.13/hibernate-core/src/main/java/org/hibernate/persister/entity/mutation/InsertCoordinatorStandard.java#L96) |
| 17 | `InsertCoordinatorStandard.doStaticInserts` | [L183](https://github.com/hibernate/hibernate-orm/blob/7.4.13/hibernate-core/src/main/java/org/hibernate/persister/entity/mutation/InsertCoordinatorStandard.java#L183) |
| 5 | `MutationStatementPreparerImpl.prepareStatement` | [L32](https://github.com/hibernate/hibernate-orm/blob/7.4.13/hibernate-core/src/main/java/org/hibernate/engine/jdbc/internal/MutationStatementPreparerImpl.java#L32) |

Line numbers in `AbstractPlatformTransactionManager.processCommit` give the order of everything that happens at commit. Each line comes from a different captured stack:

| Step | `processCommit` line | Captured in | Consequence |
|---|---|---|---|
| `beforeCommit` callbacks | 774 → `triggerBeforeCommit` | `stack-before-commit` | Runs **before** the flush: it can't see constraint violations or generated SQL |
| Flush + JDBC commit | 794 → `JpaTransactionManager.doCommit:552` → Hibernate `beforeTransactionCompletion` → `ActionQueue.executeActions` | `stack-hibernate-insert` (above) | The `INSERT` is sent **here**, so a unique-key violation surfaces at commit, outside any `try` around `save()` |
| `afterCommit` callbacks | 835 → `triggerAfterCommit` | `stack-after-commit` | The row is durable |
| `@TransactionalEventListener` (default phase `AFTER_COMMIT`) | 838 → `triggerAfterCompletion` → `TransactionalApplicationListenerSynchronization$PlatformSynchronization.afterCompletion` | `stack-after-commit-listener` | Runs **after** plain `afterCommit` callbacks, still on the request thread, **before the HTTP response is written** |

The listener's own frames:

| # | Frame | Source at the tag |
|---|---|---|
| 16 | `AbstractPlatformTransactionManager.processCommit` | [L838](https://github.com/spring-projects/spring-framework/blob/v7.0.10/spring-tx/src/main/java/org/springframework/transaction/support/AbstractPlatformTransactionManager.java#L838) |
| 15 | `AbstractPlatformTransactionManager.triggerAfterCompletion` | [L1021](https://github.com/spring-projects/spring-framework/blob/v7.0.10/spring-tx/src/main/java/org/springframework/transaction/support/AbstractPlatformTransactionManager.java#L1021) |
| 14 | `AbstractPlatformTransactionManager.invokeAfterCompletion` | [L1046](https://github.com/spring-projects/spring-framework/blob/v7.0.10/spring-tx/src/main/java/org/springframework/transaction/support/AbstractPlatformTransactionManager.java#L1046) |
| 13 | `TransactionSynchronizationUtils.invokeAfterCompletion` | [L202](https://github.com/spring-projects/spring-framework/blob/v7.0.10/spring-tx/src/main/java/org/springframework/transaction/support/TransactionSynchronizationUtils.java#L202) |
| 12 | `TransactionalApplicationListenerSynchronization$PlatformSynchronization.afterCompletion` | [L118](https://github.com/spring-projects/spring-framework/blob/v7.0.10/spring-tx/src/main/java/org/springframework/transaction/event/TransactionalApplicationListenerSynchronization.java#L118) |
| 11 | `TransactionalApplicationListenerSynchronization.processEventWithCallbacks` | [L65](https://github.com/spring-projects/spring-framework/blob/v7.0.10/spring-tx/src/main/java/org/springframework/transaction/event/TransactionalApplicationListenerSynchronization.java#L65) |
| 10 | `ApplicationListenerMethodAdapter.processEvent` | [L270](https://github.com/spring-projects/spring-framework/blob/v7.0.10/spring-context/src/main/java/org/springframework/context/event/ApplicationListenerMethodAdapter.java#L270) |
| 9 | `ApplicationListenerMethodAdapter.doInvoke` | [L392](https://github.com/spring-projects/spring-framework/blob/v7.0.10/spring-context/src/main/java/org/springframework/context/event/ApplicationListenerMethodAdapter.java#L392) |

Two production consequences:

* **A slow `@TransactionalEventListener` is user-facing latency.** It runs on the Tomcat thread after the commit and before the response. Put real work behind `@Async` or an outbox ([4.8 §2](../04-Spring-Boot-Internals/08-Request-Lifecycle-Events-Async-Graceful-Shutdown.md), [5.4](../05-Microservices-Patterns/04-Transactional-Outbox-and-Idempotent-Consumer-Complete-Implementation.md)).
* **The ActionQueue order bites on delete-then-insert.** The lab deleted a customer and saved a new one with the same unique email in one transaction:

```text
== 3. delete + insert with the same unique key in one transaction
   without flush: DataIntegrityViolationException / root: ERROR: duplicate key value violates unique constraint "uk_customer_email"
     sql: insert into customer (email,name,id) values (?,?,?)
   with flush() after delete: committed
     sql: delete from customer where id=?
     sql: insert into customer (email,name,id) values (?,?,?)
```

Only the `INSERT` was ever sent, because the queue runs inserts before deletes. The enum's own comment in [`ActionQueue`](https://github.com/hibernate/hibernate-orm/blob/7.4.13/hibernate-core/src/main/java/org/hibernate/engine/spi/ActionQueue.java#L109) says *"The order of these operations is very important"*: [`EntityInsertAction`](https://github.com/hibernate/hibernate-orm/blob/7.4.13/hibernate-core/src/main/java/org/hibernate/engine/spi/ActionQueue.java#L135) is declared at line 135, [`EntityDeleteAction`](https://github.com/hibernate/hibernate-orm/blob/7.4.13/hibernate-core/src/main/java/org/hibernate/engine/spi/ActionQueue.java#L210) at line 210. An explicit `flush()` after the delete fixes it; so does updating the existing row instead of replacing it ([3.2](../03-JPA-Hibernate-Spring-Data/02-ActionQueue-Flush-Ordering.md)).

---

## 4. Where the connection is taken, and what pool exhaustion looks like in a thread dump 🔥

Pool size 2. Two threads held a connection inside `@Transactional` methods (`count()`, then `sleep(2500)`). A third thread called a `@Transactional` method, and a monitor took `Thread.getAllStackTraces()` 700 ms later:

```text
== 4. pool exhausted (maximum-pool-size=2): what a thread dump shows
   borrower state after 700 ms: alive=true state=TIMED_WAITING
   platform: Thread.getAllStackTraces() has 29 threads, contains borrower-platform: true, virtual threads in map: 0
   borrower-platform: quick() returned 2506 ms after the borrower started
```

| # | Frame | Source at the tag |
|---|---|---|
| 25 | `TransactionAspectSupport.invokeWithinTransaction` | [L365](https://github.com/spring-projects/spring-framework/blob/v7.0.10/spring-tx/src/main/java/org/springframework/transaction/interceptor/TransactionAspectSupport.java#L365) |
| 24 | `TransactionAspectSupport.createTransactionIfNecessary` | [L628](https://github.com/spring-projects/spring-framework/blob/v7.0.10/spring-tx/src/main/java/org/springframework/transaction/interceptor/TransactionAspectSupport.java#L628) |
| 23 | `AbstractPlatformTransactionManager.getTransaction` | [L405](https://github.com/spring-projects/spring-framework/blob/v7.0.10/spring-tx/src/main/java/org/springframework/transaction/support/AbstractPlatformTransactionManager.java#L405) |
| 22 | `AbstractPlatformTransactionManager.startTransaction` | [L532](https://github.com/spring-projects/spring-framework/blob/v7.0.10/spring-tx/src/main/java/org/springframework/transaction/support/AbstractPlatformTransactionManager.java#L532) |
| 21 | `JpaTransactionManager.doBegin` | [L411](https://github.com/spring-projects/spring-framework/blob/v7.0.10/spring-orm/src/main/java/org/springframework/orm/jpa/JpaTransactionManager.java#L411) |
| 20 | `HibernateJpaDialect.beginTransaction` | [L147](https://github.com/spring-projects/spring-framework/blob/v7.0.10/spring-orm/src/main/java/org/springframework/orm/jpa/vendor/HibernateJpaDialect.java#L147) |
| 19 | `TransactionImpl.begin` | [L75](https://github.com/hibernate/hibernate-orm/blob/7.4.13/hibernate-core/src/main/java/org/hibernate/engine/transaction/internal/TransactionImpl.java#L75) |
| 18 | `JdbcResourceLocalTransactionCoordinatorImpl$TransactionDriverControlImpl.begin` | [L226](https://github.com/hibernate/hibernate-orm/blob/7.4.13/hibernate-core/src/main/java/org/hibernate/resource/transaction/backend/jdbc/internal/JdbcResourceLocalTransactionCoordinatorImpl.java#L226) |
| 17 | `LogicalConnectionManagedImpl.begin` | [L290](https://github.com/hibernate/hibernate-orm/blob/7.4.13/hibernate-core/src/main/java/org/hibernate/resource/jdbc/internal/LogicalConnectionManagedImpl.java#L290) |
| 16 | `LogicalConnectionManagedImpl.getConnectionForTransactionManagement` | [L281](https://github.com/hibernate/hibernate-orm/blob/7.4.13/hibernate-core/src/main/java/org/hibernate/resource/jdbc/internal/LogicalConnectionManagedImpl.java#L281) |
| 15 | `LogicalConnectionManagedImpl.getPhysicalConnection` | [L126](https://github.com/hibernate/hibernate-orm/blob/7.4.13/hibernate-core/src/main/java/org/hibernate/resource/jdbc/internal/LogicalConnectionManagedImpl.java#L126) |
| 13 | `LogicalConnectionManagedImpl.acquire` | [L187](https://github.com/hibernate/hibernate-orm/blob/7.4.13/hibernate-core/src/main/java/org/hibernate/resource/jdbc/internal/LogicalConnectionManagedImpl.java#L187) |
| 12 | `NonContextualJdbcConnectionAccess.obtainConnection` | [L62](https://github.com/hibernate/hibernate-orm/blob/7.4.13/hibernate-core/src/main/java/org/hibernate/internal/NonContextualJdbcConnectionAccess.java#L62) |
| 11 | `DataSourceConnectionProvider.getConnection` | [L149](https://github.com/hibernate/hibernate-orm/blob/7.4.13/hibernate-core/src/main/java/org/hibernate/engine/jdbc/connections/internal/DataSourceConnectionProvider.java#L149) |
| 10 | `HikariDataSource.getConnection` | [L127](https://github.com/brettwooldridge/HikariCP/blob/HikariCP-7.0.2/src/main/java/com/zaxxer/hikari/HikariDataSource.java#L127) |
| 9 | `HikariPool.getConnection` | [L142](https://github.com/brettwooldridge/HikariCP/blob/HikariCP-7.0.2/src/main/java/com/zaxxer/hikari/pool/HikariPool.java#L142) |
| 8 | `HikariPool.getConnection` | [L160](https://github.com/brettwooldridge/HikariCP/blob/HikariCP-7.0.2/src/main/java/com/zaxxer/hikari/pool/HikariPool.java#L160) |
| 7 | `ConcurrentBag.borrow` | [L163](https://github.com/brettwooldridge/HikariCP/blob/HikariCP-7.0.2/src/main/java/com/zaxxer/hikari/util/ConcurrentBag.java#L163) |
| 6 | `SynchronousQueue.poll` | [L338](https://github.com/openjdk/jdk25u/blob/jdk-25.0.4.1+1/src/java.base/share/classes/java/util/concurrent/SynchronousQueue.java#L338) |
| 5 | `SynchronousQueue.xfer` | [L235](https://github.com/openjdk/jdk25u/blob/jdk-25.0.4.1+1/src/java.base/share/classes/java/util/concurrent/SynchronousQueue.java#L235) |

* **The borrower waits at [`ConcurrentBag.borrow` line 163](https://github.com/brettwooldridge/HikariCP/blob/HikariCP-7.0.2/src/main/java/com/zaxxer/hikari/util/ConcurrentBag.java#L163)**, which is `handoffQueue.poll(timeout, NANOSECONDS)` in the 7.0.2 source: the third tier of [8.4 §1.2](04-High-Performance-Internals-HikariCP-Resilience4j-Caffeine.md). On JDK 25 the `SynchronousQueue` frames delegate to `LinkedTransferQueue` (frames 3–6).
* **The connection is taken at transaction begin**, not at the first query: [`JpaTransactionManager.doBegin` line 411](https://github.com/spring-projects/spring-framework/blob/v7.0.10/spring-orm/src/main/java/org/springframework/orm/jpa/JpaTransactionManager.java#L411) → `HibernateJpaDialect.beginTransaction` → `LogicalConnectionManagedImpl.begin`, which needs the physical connection to switch auto-commit off. With Hikari's default `auto-commit=true`, a `@Transactional` method holds a pooled connection **from its first line**, including any HTTP call it makes before touching the database ([8.9 R2](09-Staff-Level-System-and-Code-Review-Checklist-20-Questions.md)).

The same experiment with `spring.datasource.hikari.auto-commit=false` and [`hibernate.connection.provider_disables_autocommit=true`](https://github.com/hibernate/hibernate-orm/blob/7.4.13/hibernate-core/src/main/java/org/hibernate/cfg/JdbcSettings.java#L338) moved the borrow to the **first SQL statement**:

| # | Frame | Source at the tag |
|---|---|---|
| 56 | `JdkDynamicAopProxy.invoke` | [L219](https://github.com/spring-projects/spring-framework/blob/v7.0.10/spring-aop/src/main/java/org/springframework/aop/framework/JdkDynamicAopProxy.java#L219) |
| 49 | `TransactionAspectSupport.invokeWithinTransaction` | [L371](https://github.com/spring-projects/spring-framework/blob/v7.0.10/spring-tx/src/main/java/org/springframework/transaction/interceptor/TransactionAspectSupport.java#L371) |
| 27 | `SimpleJpaRepository.count` | [L649](https://github.com/spring-projects/spring-data-jpa/blob/4.1.2/spring-data-jpa/src/main/java/org/springframework/data/jpa/repository/support/SimpleJpaRepository.java#L649) |
| 26 | `AbstractSelectionQuery.getSingleResult` | [L292](https://github.com/hibernate/hibernate-orm/blob/7.4.13/hibernate-core/src/main/java/org/hibernate/query/spi/AbstractSelectionQuery.java#L292) |
| 16 | `JdbcSelectExecutorStandardImpl.doExecuteQuery` | [L132](https://github.com/hibernate/hibernate-orm/blob/7.4.13/hibernate-core/src/main/java/org/hibernate/sql/exec/internal/JdbcSelectExecutorStandardImpl.java#L132) |
| 15 | `LogicalConnectionManagedImpl.getPhysicalConnection` | [L126](https://github.com/hibernate/hibernate-orm/blob/7.4.13/hibernate-core/src/main/java/org/hibernate/resource/jdbc/internal/LogicalConnectionManagedImpl.java#L126) |
| 7 | `ConcurrentBag.borrow` | [L163](https://github.com/brettwooldridge/HikariCP/blob/HikariCP-7.0.2/src/main/java/com/zaxxer/hikari/util/ConcurrentBag.java#L163) |

`SimpleJpaRepository.count` (frame 27) is where the connection was requested, inside `doExecuteQuery`. The stack also shows a **second `TransactionInterceptor`** (frames 48–50, under the repository's JDK proxy at frame 56): Spring Data repositories are themselves `@Transactional`. The setting is a promise that the pool already disabled auto-commit; turn it on only together with `auto-commit=false`.

**The signature to recognise in a production thread dump:** many threads `TIMED_WAITING` in `ConcurrentBag.borrow` → `SynchronousQueue.poll`, all under `JpaTransactionManager.doBegin` (or under a repository call with lazy acquisition). Then look for the holders: threads in your own code, inside a transaction, doing something that isn't SQL.

---

## 5. Virtual threads aren't in `Thread.getAllStackTraces()` 🧊

The same pool-exhaustion experiment with the borrower as a **virtual thread**:

```text
   borrower state after 700 ms: alive=true state=TIMED_WAITING
   virtual: Thread.getAllStackTraces() has 31 threads, contains borrower-virtual: false, virtual threads in map: 0
   HotSpotDiagnosticMXBean.dumpThreads(JSON): found borrower-virtual in container '<root>' (32 frames; ...)
   thread containers in the JSON dump: 10
   borrower-virtual: quick() returned 2511 ms after the borrower started
```

The blocked request is invisible to the API most "dump threads on timeout" code uses. That's documented behaviour: the [`getAllStackTraces` Javadoc](https://github.com/openjdk/jdk25u/blob/jdk-25.0.4.1+1/src/java.base/share/classes/java/lang/Thread.java#L2220) says it returns *"stack traces for all live platform threads. The map does not include virtual threads."* The JSON dump found it, with the same Hikari frames under `VirtualThread.parkNanos`:

| # | Frame | Source at the tag |
|---|---|---|
| 22 | `JpaTransactionManager.doBegin` | [L411](https://github.com/spring-projects/spring-framework/blob/v7.0.10/spring-orm/src/main/java/org/springframework/orm/jpa/JpaTransactionManager.java#L411) |
| 8 | `ConcurrentBag.borrow` | [L163](https://github.com/brettwooldridge/HikariCP/blob/HikariCP-7.0.2/src/main/java/com/zaxxer/hikari/util/ConcurrentBag.java#L163) |
| 7 | `SynchronousQueue.poll` | [L338](https://github.com/openjdk/jdk25u/blob/jdk-25.0.4.1+1/src/java.base/share/classes/java/util/concurrent/SynchronousQueue.java#L338) |
| 3 | `LockSupport.parkNanos` | [L406](https://github.com/openjdk/jdk25u/blob/jdk-25.0.4.1+1/src/java.base/share/classes/java/util/concurrent/locks/LockSupport.java#L406) |
| 2 | `System$1.parkVirtualThread` | [L2294](https://github.com/openjdk/jdk25u/blob/jdk-25.0.4.1+1/src/java.base/share/classes/java/lang/System.java#L2294) |
| 1 | `VirtualThread.parkNanos` | [L787](https://github.com/openjdk/jdk25u/blob/jdk-25.0.4.1+1/src/java.base/share/classes/java/lang/VirtualThread.java#L787) |

Even the JSON dump makes a weaker promise than you might expect. [`HotSpotDiagnosticMXBean.dumpThreads`](https://github.com/openjdk/jdk25u/blob/jdk-25.0.4.1+1/src/jdk.management/share/classes/com/sun/management/HotSpotDiagnosticMXBean.java#L126) *"will include output for all platform threads. It **may** include output for some or all virtual threads."* In this run it included the parked one. In practice:

* Use the thread-dump format that knows about virtual threads (the MXBean, or `jcmd <pid> Thread.dump_to_file -format=json <file>`) and check that your incident tooling does too.
* With virtual threads, the pool, not the thread count, is the visible bottleneck. Alert on Hikari's pending-threads and acquire-time metrics; don't wait for a dump.

---

## 6. `@Cacheable`: your loader runs inside `ConcurrentHashMap.compute` with `sync = true` 🧊

Two cached methods on a `CaffeineCacheManager`, one plain and one `sync = true`. Plain:

| # | Frame | Source at the tag |
|---|---|---|
| 12 | `CacheInterceptor.invoke` | [L64](https://github.com/spring-projects/spring-framework/blob/v7.0.10/spring-context/src/main/java/org/springframework/cache/interceptor/CacheInterceptor.java#L64) |
| 11 | `CacheAspectSupport.execute` | [L406](https://github.com/spring-projects/spring-framework/blob/v7.0.10/spring-context/src/main/java/org/springframework/cache/interceptor/CacheAspectSupport.java#L406) |
| 10 | `CacheAspectSupport.execute` | [L442](https://github.com/spring-projects/spring-framework/blob/v7.0.10/spring-context/src/main/java/org/springframework/cache/interceptor/CacheAspectSupport.java#L442) |
| 9 | `CacheAspectSupport.evaluate` | [L591](https://github.com/spring-projects/spring-framework/blob/v7.0.10/spring-context/src/main/java/org/springframework/cache/interceptor/CacheAspectSupport.java#L591) |
| 8 | `CacheAspectSupport.invokeOperation` | [L426](https://github.com/spring-projects/spring-framework/blob/v7.0.10/spring-context/src/main/java/org/springframework/cache/interceptor/CacheAspectSupport.java#L426) |
| 7 | `CacheInterceptor.lambda$invoke$0` | [L54](https://github.com/spring-projects/spring-framework/blob/v7.0.10/spring-context/src/main/java/org/springframework/cache/interceptor/CacheInterceptor.java#L54) |

No cache frames are on the stack while the method runs. Ten concurrent misses for the same key run the method ten times: the stampede of [6.4](../06-Resilience-Caching/04-Cache-Stampede-Penetration-Avalanche-Invalidation.md).

With `sync = true` the picture changes:

| # | Frame | Source at the tag |
|---|---|---|
| 21 | `CacheAspectSupport.execute` | [L406](https://github.com/spring-projects/spring-framework/blob/v7.0.10/spring-context/src/main/java/org/springframework/cache/interceptor/CacheAspectSupport.java#L406) |
| 20 | `CacheAspectSupport.execute` | [L432](https://github.com/spring-projects/spring-framework/blob/v7.0.10/spring-context/src/main/java/org/springframework/cache/interceptor/CacheAspectSupport.java#L432) |
| 19 | `CacheAspectSupport.executeSynchronized` | [L489](https://github.com/spring-projects/spring-framework/blob/v7.0.10/spring-context/src/main/java/org/springframework/cache/interceptor/CacheAspectSupport.java#L489) |
| 18 | `AbstractCacheInvoker.doGet` | [L96](https://github.com/spring-projects/spring-framework/blob/v7.0.10/spring-context/src/main/java/org/springframework/cache/interceptor/AbstractCacheInvoker.java#L96) |
| 17 | `CaffeineCache.get` | [L133](https://github.com/spring-projects/spring-framework/blob/v7.0.10/spring-context-support/src/main/java/org/springframework/cache/caffeine/CaffeineCache.java#L133) |
| 16 | `LocalManualCache.get` | [L63](https://github.com/ben-manes/caffeine/blob/v3.2.4/caffeine/src/main/java/com/github/benmanes/caffeine/cache/LocalManualCache.java#L63) |
| 15 | `LocalCache.computeIfAbsent` | [L132](https://github.com/ben-manes/caffeine/blob/v3.2.4/caffeine/src/main/java/com/github/benmanes/caffeine/cache/LocalCache.java#L132) |
| 14 | `BoundedLocalCache.computeIfAbsent` | [L2756](https://github.com/ben-manes/caffeine/blob/v3.2.4/caffeine/src/main/java/com/github/benmanes/caffeine/cache/BoundedLocalCache.java#L2756) |
| 13 | `BoundedLocalCache.doComputeIfAbsent` | [L2765](https://github.com/ben-manes/caffeine/blob/v3.2.4/caffeine/src/main/java/com/github/benmanes/caffeine/cache/BoundedLocalCache.java#L2765) |
| 12 | `ConcurrentHashMap.compute` | [L1932](https://github.com/openjdk/jdk25u/blob/jdk-25.0.4.1+1/src/java.base/share/classes/java/util/concurrent/ConcurrentHashMap.java#L1932) |
| 11 | `BoundedLocalCache.lambda$doComputeIfAbsent$0` | [L2767](https://github.com/ben-manes/caffeine/blob/v3.2.4/caffeine/src/main/java/com/github/benmanes/caffeine/cache/BoundedLocalCache.java#L2767) |
| 10 | `CaffeineCache$LoadFunction.apply` | [L231](https://github.com/spring-projects/spring-framework/blob/v7.0.10/spring-context-support/src/main/java/org/springframework/cache/caffeine/CaffeineCache.java#L231) |
| 9 | `CacheAspectSupport.lambda$executeSynchronized$3` | [L489](https://github.com/spring-projects/spring-framework/blob/v7.0.10/spring-context/src/main/java/org/springframework/cache/interceptor/CacheAspectSupport.java#L489) |
| 8 | `CacheAspectSupport.invokeOperation` | [L426](https://github.com/spring-projects/spring-framework/blob/v7.0.10/spring-context/src/main/java/org/springframework/cache/interceptor/CacheAspectSupport.java#L426) |

[`CacheAspectSupport`](https://github.com/spring-projects/spring-framework/blob/v7.0.10/spring-context/src/main/java/org/springframework/cache/interceptor/CacheAspectSupport.java#L430) branches at line 430 into `executeSynchronized`, which calls [`CaffeineCache.get(key, loader)`](https://github.com/spring-projects/spring-framework/blob/v7.0.10/spring-context-support/src/main/java/org/springframework/cache/caffeine/CaffeineCache.java#L133). Caffeine runs your loader **inside `ConcurrentHashMap.compute`** (frame 12), holding that hash bin's lock while your method talks to the database. That's what makes concurrent callers of the same key wait for one load. Two consequences, both measured:

```text
   sync loader -> same cache, different key: OK
   sync loader -> same cache, SAME key: java.lang.IllegalStateException: Recursive update
```

* A loader that, directly or through another `@Cacheable` method, asks **the same cache for the same key** fails with `IllegalStateException: Recursive update`, thrown at [`ConcurrentHashMap.java` line 1075](https://github.com/openjdk/jdk25u/blob/jdk-25.0.4.1+1/src/java.base/share/classes/java/util/concurrent/ConcurrentHashMap.java#L1075). The contract is in the [`compute` Javadoc](https://github.com/openjdk/jdk25u/blob/jdk-25.0.4.1+1/src/java.base/share/classes/java/util/concurrent/ConcurrentHashMap.java#L1806): *"The remapping function must not modify this map during computation."*
* A nested load for a **different key** worked here, but it ran inside the outer bin lock (the nested stack, `stack-cacheable-sync-nested`, has two `compute` frames). Keep `sync = true` loaders short, non-recursive, and protected by a timeout.

---

## 7. One Kafka record through spring-kafka 4.1.2 ⚡

A `@KafkaListener` on topic `orders` received three records with key `k1`:
* `flaky` fails twice, then succeeds;
* `poison` always fails;
* `ok` succeeds.

The container used `DefaultErrorHandler` with its default back-off. The lab declared one only so the recoverer could be observed. The listener stack on attempt 1:

| # | Frame | Source at the tag |
|---|---|---|
| 20 | `KafkaMessageListenerContainer$ListenerConsumer.run` | [L1388](https://github.com/spring-projects/spring-kafka/blob/v4.1.2/spring-kafka/src/main/java/org/springframework/kafka/listener/KafkaMessageListenerContainer.java#L1388) |
| 19 | `KafkaMessageListenerContainer$ListenerConsumer.pollAndInvoke` | [L1527](https://github.com/spring-projects/spring-kafka/blob/v4.1.2/spring-kafka/src/main/java/org/springframework/kafka/listener/KafkaMessageListenerContainer.java#L1527) |
| 18 | `KafkaMessageListenerContainer$ListenerConsumer.invokeIfHaveRecords` | [L1625](https://github.com/spring-projects/spring-kafka/blob/v4.1.2/spring-kafka/src/main/java/org/springframework/kafka/listener/KafkaMessageListenerContainer.java#L1625) |
| 17 | `KafkaMessageListenerContainer$ListenerConsumer.invokeListener` | [L2329](https://github.com/spring-projects/spring-kafka/blob/v4.1.2/spring-kafka/src/main/java/org/springframework/kafka/listener/KafkaMessageListenerContainer.java#L2329) |
| 16 | `KafkaMessageListenerContainer$ListenerConsumer.invokeRecordListener` | [L2698](https://github.com/spring-projects/spring-kafka/blob/v4.1.2/spring-kafka/src/main/java/org/springframework/kafka/listener/KafkaMessageListenerContainer.java#L2698) |
| 15 | `KafkaMessageListenerContainer$ListenerConsumer.doInvokeWithRecords` | [L2812](https://github.com/spring-projects/spring-kafka/blob/v4.1.2/spring-kafka/src/main/java/org/springframework/kafka/listener/KafkaMessageListenerContainer.java#L2812) |
| 14 | `KafkaMessageListenerContainer$ListenerConsumer.doInvokeRecordListener` | [L2994](https://github.com/spring-projects/spring-kafka/blob/v4.1.2/spring-kafka/src/main/java/org/springframework/kafka/listener/KafkaMessageListenerContainer.java#L2994) |
| 13 | `KafkaMessageListenerContainer$ListenerConsumer.invokeOnMessage` | [L3084](https://github.com/spring-projects/spring-kafka/blob/v4.1.2/spring-kafka/src/main/java/org/springframework/kafka/listener/KafkaMessageListenerContainer.java#L3084) |
| 12 | `KafkaMessageListenerContainer$ListenerConsumer.doInvokeOnMessage` | [L3105](https://github.com/spring-projects/spring-kafka/blob/v4.1.2/spring-kafka/src/main/java/org/springframework/kafka/listener/KafkaMessageListenerContainer.java#L3105) |
| 11 | `RecordMessagingMessageListenerAdapter.onMessage` | [L52](https://github.com/spring-projects/spring-kafka/blob/v4.1.2/spring-kafka/src/main/java/org/springframework/kafka/listener/adapter/RecordMessagingMessageListenerAdapter.java#L52) |
| 10 | `RecordMessagingMessageListenerAdapter.onMessage` | [L92](https://github.com/spring-projects/spring-kafka/blob/v4.1.2/spring-kafka/src/main/java/org/springframework/kafka/listener/adapter/RecordMessagingMessageListenerAdapter.java#L92) |
| 9 | `MessagingMessageListenerAdapter.invoke` | [L427](https://github.com/spring-projects/spring-kafka/blob/v4.1.2/spring-kafka/src/main/java/org/springframework/kafka/listener/adapter/MessagingMessageListenerAdapter.java#L427) |
| 8 | `MessagingMessageListenerAdapter.invokeHandler` | [L490](https://github.com/spring-projects/spring-kafka/blob/v4.1.2/spring-kafka/src/main/java/org/springframework/kafka/listener/adapter/MessagingMessageListenerAdapter.java#L490) |
| 7 | `HandlerAdapter.invoke` | [L80](https://github.com/spring-projects/spring-kafka/blob/v4.1.2/spring-kafka/src/main/java/org/springframework/kafka/listener/adapter/HandlerAdapter.java#L80) |
| 6 | `InvocableHandlerMethod.invoke` | [L119](https://github.com/spring-projects/spring-framework/blob/v7.0.10/spring-messaging/src/main/java/org/springframework/messaging/handler/invocation/InvocableHandlerMethod.java#L119) |
| 4 | `InvocableHandlerMethod.doInvoke` | [L168](https://github.com/spring-projects/spring-framework/blob/v7.0.10/spring-messaging/src/main/java/org/springframework/messaging/handler/invocation/InvocableHandlerMethod.java#L168) |

The stack on **attempt 3** is identical except for the listener's own line. So each retry is not a loop inside the error handler: the handler seeks back to the failed offset, and the record comes back through a fresh `poll()` (frame 19).

When the attempts are exhausted, the recoverer runs **on the consumer thread, inside the poll loop**:

| # | Frame | Source at the tag |
|---|---|---|
| 17 | `KafkaMessageListenerContainer$ListenerConsumer.run` | [L1388](https://github.com/spring-projects/spring-kafka/blob/v4.1.2/spring-kafka/src/main/java/org/springframework/kafka/listener/KafkaMessageListenerContainer.java#L1388) |
| 16 | `KafkaMessageListenerContainer$ListenerConsumer.pollAndInvoke` | [L1527](https://github.com/spring-projects/spring-kafka/blob/v4.1.2/spring-kafka/src/main/java/org/springframework/kafka/listener/KafkaMessageListenerContainer.java#L1527) |
| 11 | `KafkaMessageListenerContainer$ListenerConsumer.doInvokeRecordListener` | [L3008](https://github.com/spring-projects/spring-kafka/blob/v4.1.2/spring-kafka/src/main/java/org/springframework/kafka/listener/KafkaMessageListenerContainer.java#L3008) |
| 10 | `KafkaMessageListenerContainer$ListenerConsumer.invokeErrorHandler` | [L3186](https://github.com/spring-projects/spring-kafka/blob/v4.1.2/spring-kafka/src/main/java/org/springframework/kafka/listener/KafkaMessageListenerContainer.java#L3186) |
| 9 | `DefaultErrorHandler.handleRemaining` | [L168](https://github.com/spring-projects/spring-kafka/blob/v4.1.2/spring-kafka/src/main/java/org/springframework/kafka/listener/DefaultErrorHandler.java#L168) |
| 8 | `SeekUtils.seekOrRecover` | [L226](https://github.com/spring-projects/spring-kafka/blob/v4.1.2/spring-kafka/src/main/java/org/springframework/kafka/listener/SeekUtils.java#L226) |
| 7 | `SeekUtils.doSeeks` | [L105](https://github.com/spring-projects/spring-kafka/blob/v4.1.2/spring-kafka/src/main/java/org/springframework/kafka/listener/SeekUtils.java#L105) |
| 5 | `SeekUtils.lambda$doSeeks$1` | [L108](https://github.com/spring-projects/spring-kafka/blob/v4.1.2/spring-kafka/src/main/java/org/springframework/kafka/listener/SeekUtils.java#L108) |
| 4 | `FailedRecordTracker.recovered` | [L200](https://github.com/spring-projects/spring-kafka/blob/v4.1.2/spring-kafka/src/main/java/org/springframework/kafka/listener/FailedRecordTracker.java#L200) |
| 3 | `FailedRecordTracker.attemptRecovery` | [L250](https://github.com/spring-projects/spring-kafka/blob/v4.1.2/spring-kafka/src/main/java/org/springframework/kafka/listener/FailedRecordTracker.java#L250) |
| 2 | `FailedRecordTracker.lambda$new$1` | [L101](https://github.com/spring-projects/spring-kafka/blob/v4.1.2/spring-kafka/src/main/java/org/springframework/kafka/listener/FailedRecordTracker.java#L101) |

[`DefaultErrorHandler.handleRemaining`](https://github.com/spring-projects/spring-kafka/blob/v4.1.2/spring-kafka/src/main/java/org/springframework/kafka/listener/DefaultErrorHandler.java#L165) → `SeekUtils.seekOrRecover` → `FailedRecordTracker.recovered`. A `DeadLetterPublishingRecoverer` therefore publishes to the DLT synchronously on the poll thread. A slow or blocked DLT send stalls the partition and counts against `max.poll.interval.ms`.

**The timing surprised me.** The default back-off is [`FixedBackOff(0, DEFAULT_MAX_FAILURES - 1)`](https://github.com/spring-projects/spring-kafka/blob/v4.1.2/spring-kafka/src/main/java/org/springframework/kafka/listener/SeekUtils.java#L63), with no configured delay. Measured, though, it was neither instant nor fixed:

| Variant (one measured run each) | Gap between attempts | 10 attempts took |
|---|---|---|
| Defaults, consumer caught up (`fetch.max.wait.ms` = 500) | ~515 ms | 4.6 s |
| `spring.kafka.consumer.fetch-max-wait=50ms` | ~60–70 ms | 0.57 s |
| Defaults, 20,000 records queued behind the poison record | ~15–30 ms | 0.17 s |

The seek invalidates what the consumer had buffered, but a caught-up consumer already has the **next** fetch in flight, a long poll the broker holds for up to [`fetch.max.wait.ms`, default 500 ms](https://github.com/apache/kafka/blob/4.2.2/clients/src/main/java/org/apache/kafka/clients/consumer/ConsumerConfig.java#L210). [`AbstractFetch`](https://github.com/apache/kafka/blob/4.2.2/clients/src/main/java/org/apache/kafka/clients/consumer/internals/AbstractFetch.java#L458) won't send another fetch to that broker *"because previous request to {} has not been processed"*, so every retry waits out the long poll. With a backlog, the in-flight fetch returns at once and retries are fast. Earlier wording in this kit ("10 instant attempts") was corrected in [10.2](../10-Kafka-Production/02-Kafka-Consumers-Rebalancing-EOS-Retries-DLQ.md) and [10.5](../10-Kafka-Production/05-Bar-Raiser-Drill-Downs.md). Configure an explicit `ExponentialBackOff` and a DLT recoverer; don't rely on the default's timing in either direction.

---

## 8. Doing this on your own codebase

| ❌ Naïve | ✅ What worked here |
|---|---|
| Read the framework's `main` branch on GitHub | Read the tag of the jar on your classpath (`mvn dependency:tree`, or the Boot BOM), and link to it |
| Read source top-down from `SpringApplication.run` | Capture one stack at a point you care about; read the five frames around your code |
| Assume line numbers drift | Verify one frame: if the line falls inside the named method at that tag, the rest of the stack maps too |
| Take a thread dump with `Thread.getAllStackTraces()` | Use the JSON thread dump (`dumpThreads` / `jcmd Thread.dump_to_file`) when virtual threads are in play |
| Trust "no back-off" or "instant retry" from a config value | Time the behaviour; the fetch pipeline, not the back-off, set the retry interval |

Tools that pay off: a five-line `Trace.capture` helper like the one in §0; `Thread.dumpStack()` in a debugger condition; IntelliJ's *Analyze Stack Trace* (paste a production stack, click through to the source); JFR's `jdk.ThreadPark` and `jdk.JavaMonitorWait` events for "where do threads wait"; and `javap -c -l` to read a class's line-number table when the source and the jar seem not to match.

---

## 9. Interview soundbites

* "With Hikari's default auto-commit, Spring takes the connection in `JpaTransactionManager.doBegin`, so a `@Transactional` method holds it from the first line, even across an HTTP call. With `provider_disables_autocommit` the borrow moved to the first query. I've seen both in a thread dump."
* "The flush happens inside `JpaTransactionManager.doCommit`, after `beforeCommit` callbacks and before `afterCommit`; `@TransactionalEventListener` runs later still, in `afterCompletion`, on the request thread, before the response."
* "Pool exhaustion has a signature: threads parked in `ConcurrentBag.borrow` → `SynchronousQueue.poll` under `doBegin`. With virtual threads you won't see them in `getAllStackTraces()`; you need the JSON thread dump."
* "`@Cacheable(sync = true)` on Caffeine runs your loader inside `ConcurrentHashMap.compute`. A recursive load of the same key throws `Recursive update`."
* "spring-kafka's default retries are 'no back-off', but on a caught-up partition each one waited about 500 ms for the in-flight fetch. And the recoverer, so the DLT publish, runs on the consumer thread."

---

## Summary

| Topic | Key point | Section |
|---|---|---|
| Method | Capture a stack where you care, read at the jar's tag; 653 frames checked against their tags | §0 |
| HTTP request | One Tomcat thread runs the request, transaction, commit and listeners; filters are frames | §1 |
| `@Transactional` | CGLIB subclass → `TransactionInterceptor` → `invokeWithinTransaction`; self-invocation removes all of it | §2 |
| Commit order | `beforeCommit` (774) → flush + commit (794) → `afterCommit` (835) → `@TransactionalEventListener` (838) | §3 |
| ActionQueue | Inserts before deletes: delete-then-insert of a unique key sent only the `INSERT` (23505) | §3 |
| Connection borrow | At `doBegin` with auto-commit on; at the first SQL with `provider_disables_autocommit` | §4 |
| Pool exhaustion | `ConcurrentBag.borrow:163` → `SynchronousQueue.poll`; find the holders | §4 |
| Virtual threads | Not in `getAllStackTraces()`; the JSON dump "may" include them (it did) | §5 |
| `@Cacheable(sync)` | Loader runs inside `ConcurrentHashMap.compute`; same-key recursion → `Recursive update` | §6 |
| spring-kafka | Retry = seek + fresh poll; recoverer on the consumer thread; ~515 ms per retry when caught up | §7 |

**Next:** [8.7 The source behind the measurements →](07-Source-Behind-the-Measurements-JDK-PostgreSQL-Redis-Kubernetes-Kafka.md)
