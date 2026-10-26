# 8.3 Codebases to Study: Sagas, Outbox, CDC, and Kafka Internals

> **Verified 2026-10-25** via the GitHub API, file trees and raw-file checks; excerpts quoted from the default branches on that date.
>
> **Pairs with:** [5.3 sagas](../05-Microservices-Patterns/03-Sagas-Choreography-vs-Orchestration-Compensation-Semantic-Locks.md), [5.4 outbox + idempotent consumer](../05-Microservices-Patterns/04-Transactional-Outbox-and-Idempotent-Consumer-Complete-Implementation.md), [10.1](../10-Kafka-Production/01-Kafka-Producers-Batching-Idempotence-Ordering.md)–[10.2](../10-Kafka-Production/02-Kafka-Consumers-Rebalancing-EOS-Retries-DLQ.md) Kafka.

| Repository | Language | Branch | Stars | Last push | Read it for |
|---|---|---|---|---|---|
| [eventuate-tram/eventuate-tram-sagas](https://github.com/eventuate-tram/eventuate-tram-sagas) | Java | `master` | 1,092 | 2026-10-22 | Orchestrated sagas: DSL, saga instance persistence, **framework-level semantic locks** |
| [eventuate-tram/eventuate-tram-core](https://github.com/eventuate-tram/eventuate-tram-core) | Java | `master` | 1,179 | 2026-10-22 | Transactional messaging: outbox producer, **duplicate-message detection** |
| [microservices-patterns/ftgo-application](https://github.com/microservices-patterns/ftgo-application) | Java | `master` | 3,777 | 2026-03-13 | Chris Richardson's book application: a real `CreateOrderSaga` |
| [debezium/debezium-examples](https://github.com/debezium/debezium-examples) | mixed | `main` | 1,686 | 2026-10-23 | CDC outbox, a CDC-based saga, cache invalidation, failover slots, TOAST |
| [apache/kafka](https://github.com/apache/kafka) | Java/Scala | `trunk` | 34,115 | 2026-10-25 | The producer, consumer, coordinators, idempotence state |
| [spring-projects/spring-kafka](https://github.com/spring-projects/spring-kafka) | Java | `main` | 2,514 | 2026-10-24 | Listener containers, error handling, retry topics |

---

## 1. Eventuate Tram Sagas: an orchestration framework 🧊

### 1.1 The saga, as a definition

FTGO's `ftgo-order-service/src/main/java/net/chrisrichardson/ftgo/orderservice/sagas/createorder/CreateOrderSaga.java` (excerpt):

```java
this.sagaDefinition =
         step()
          .withCompensation(orderService.reject, CreateOrderSagaState::makeRejectOrderCommand)
        .step()
          .invokeParticipant(consumerService.validateOrder, CreateOrderSagaState::makeValidateOrderByConsumerCommand)
        .step()
          .invokeParticipant(kitchenService.create, CreateOrderSagaState::makeCreateTicketCommand)
          .onReply(CreateTicketReply.class, CreateOrderSagaState::handleCreateTicketReply)
          .withCompensation(kitchenService.cancel, CreateOrderSagaState::makeCancelCreateTicketCommand)
        .step()
            .invokeParticipant(accountingService.authorize, CreateOrderSagaState::makeAuthorizeCommand)
        .step()
          .invokeParticipant(kitchenService.confirmCreate, CreateOrderSagaState::makeConfirmCreateTicketCommand)
        .step()
          .invokeParticipant(orderService.approve, CreateOrderSagaState::makeApproveOrderCommand)
        .build();
```

Map it to [5.3](../05-Microservices-Patterns/03-Sagas-Choreography-vs-Orchestration-Compensation-Semantic-Locks.md)'s step types:

| Step | Type | Why |
|---|---|---|
| Order created `PENDING` (compensation: reject) | Compensatable | Can be undone |
| Validate consumer | Read-only check | Nothing to undo |
| Create kitchen ticket (compensation: cancel) | Compensatable | Can be undone |
| **Authorize card** | **Pivot** | No compensation: after it succeeds, the saga must complete |
| Confirm ticket, approve order | Retriable | Must eventually succeed; retried, never compensated |

### 1.2 Files to read

| Path | What to look for |
|---|---|
| `eventuate-tram-sagas-orchestration-simple-dsl/src/main/java/io/eventuate/tram/sagas/simpledsl/SimpleSaga.java` | The DSL entry point |
| `eventuate-tram-sagas-orchestration-simple-dsl/src/main/java/io/eventuate/tram/sagas/simpledsl/StepBuilder.java` and `InvokeParticipantStepBuilder.java` | How `step()`, `invokeParticipant`, `onReply`, `withCompensation` build the definition |
| `eventuate-tram-sagas-orchestration/src/main/java/io/eventuate/tram/sagas/orchestration/SagaManagerImpl.java` | Starting a saga, handling replies, deciding the next step or compensation |
| `eventuate-tram-sagas-orchestration/src/main/java/io/eventuate/tram/sagas/orchestration/SagaInstance.java` and `SagaInstanceRepositoryJdbc.java` | The **durable saga log**: state, current step, compensating flag |
| `eventuate-tram-sagas-common/src/main/java/io/eventuate/tram/sagas/common/SagaLockManagerImpl.java` | **Semantic locks implemented by the framework** (next section) |
| `eventuate-tram-sagas-spring-flyway/src/main/resources/flyway/postgresql/V1000__tram-saga-schema.sql` | `saga_instance`, `saga_instance_participants`, `saga_lock_table`, `saga_stash_table` |

### 1.3 The detail most people miss: `saga_lock_table` and `saga_stash_table`

[5.3](../05-Microservices-Patterns/03-Sagas-Choreography-vs-Orchestration-Compensation-Semantic-Locks.md) implemented a semantic lock as an application state (`PENDING`). Eventuate also offers it **generically** in `SagaLockManagerImpl`:

* `claimLock(sagaType, sagaId, target)` inserts a row for the target resource (for example `Order/42`). If another saga already owns it (`select … for update`), the claim fails.
* A command for a locked target isn't rejected. It's **stashed** (`stashMessage` → `saga_stash_table`).
* `unlock(sagaId, target)` either deletes the lock, or, if messages are stashed, **hands the lock to the next stashed saga** and returns its message for processing.

That's a per-resource queue of sagas in the database: it serializes sagas on the same aggregate without blocking unrelated ones. Ask in an interview: what happens to stashed work if the owning saga never finishes? (Answer: it waits; you need saga timeouts and monitoring of lock age.)

---

## 2. Eventuate Tram Core: outbox and dedup as a library ⚡

| Path | What to look for |
|---|---|
| `eventuate-tram-producer-jdbc/src/main/java/io/eventuate/tram/messaging/producer/jdbc/MessageProducerJdbcImpl.java` | Sending a message = **inserting into the `message` table** in the caller's transaction (the outbox); a CDC service publishes it |
| `eventuate-tram-events/src/main/java/io/eventuate/tram/events/publisher/DomainEventPublisherImpl.java` | Domain events on top of the same mechanism |
| `eventuate-tram-consumer-common/src/main/java/io/eventuate/tram/consumer/common/MessageConsumerImpl.java` | Subscribing, invoking handlers |
| `eventuate-tram-consumer-jdbc/src/main/java/io/eventuate/tram/consumer/jdbc/SqlTableBasedDuplicateMessageDetector.java` | **The idempotent consumer**, below |
| `eventuate-tram-commands/src/main/java/io/eventuate/tram/commands/consumer/CommandDispatcher.java` | Command/reply messaging used by sagas |

The dedup check, from `SqlTableBasedDuplicateMessageDetector.java` (excerpt):

```java
public boolean isDuplicate(String consumerId, String messageId) {
    …
      String table = eventuateSchema.qualifyTable("received_messages");
      eventuateJdbcStatementExecutor.update("insert into %s(consumer_id, message_id, creation_time) values(?, ?, %s)".formatted(…), …);
    …
    } catch (EventuateDuplicateKeyException e) {
      …
```

It's the same design as [5.4](../05-Microservices-Patterns/04-Transactional-Outbox-and-Idempotent-Consumer-Complete-Implementation.md)'s `processed_message` table: insert `(consumer_id, message_id)`, and a **duplicate key means "already processed"**, inside the same transaction as the handler's side effects. Seeing two independent codebases converge on it is good interview evidence.

---

## 3. debezium/debezium-examples: CDC in practice ⚡

| Directory | What it demonstrates | Kit reference |
|---|---|---|
| `outbox/` | `order-service` writes orders + outbox rows; Debezium's outbox event router publishes them; `shipment-service` consumes (with tracing: `jaeger.png`) | [5.4 §6](../05-Microservices-Patterns/04-Transactional-Outbox-and-Idempotent-Consumer-Complete-Implementation.md) |
| `saga/` | An **orchestrated saga over the outbox + CDC**: `order-service` orchestrates `customer-service` (credit) and `payment-service` | [5.3](../05-Microservices-Patterns/03-Sagas-Choreography-vs-Orchestration-Compensation-Semantic-Locks.md) |
| `cache-invalidation/` | Debezium invalidating Hibernate's 2nd-level cache after **out-of-band** DB updates | [6.4 §5.3](../06-Resilience-Caching/04-Cache-Stampede-Penetration-Avalanche-Invalidation.md) |
| `postgres-failover-slots/` | Keeping logical replication slots across a primary failover | [5.4](../05-Microservices-Patterns/04-Transactional-Outbox-and-Idempotent-Consumer-Complete-Implementation.md) (slot risk) |
| `postgres-toast/` | Unchanged TOASTed columns arrive in UPDATE events as a placeholder, not the value (the WAL doesn't carry them unless `REPLICA IDENTITY FULL`), and how a sink copes | [2.1](../02-SQL-RDBMS-Internals/01-Storage-Pages-Tuples-TOAST-WAL.md) |
| `auditlog/` | Enriching change events with application metadata | — |

The saga example's own framework is small enough to read in an hour:

| Path | What to look for |
|---|---|
| `saga/order-service/src/main/java/io/debezium/examples/saga/framework/SagaManager.java` | Starting and advancing sagas |
| `saga/order-service/src/main/java/io/debezium/examples/saga/framework/SagaBase.java` | Step handling, compensation |
| `saga/order-service/src/main/java/io/debezium/examples/saga/framework/internal/SagaState.java` and `SagaStepState.java` | The persisted saga state |
| `saga/order-service/src/main/java/io/debezium/examples/saga/framework/internal/ConsumedMessage.java` | Dedup on the orchestrator side |
| `saga/customer-service/src/main/java/io/debezium/examples/saga/customer/messagelog/MessageLog.java` | Dedup on the participant side |

From its README: *"this implementation avoids unsafe dual writes to a service's database and Apache Kafka by channeling all outgoing messages through the originating service's database and capturing them from there using CDC and Debezium."*

---

## 4. apache/kafka: where to start reading 🧊

Kafka is huge. Read it along the path of one record:

| Stop | Path | What to look for |
|---|---|---|
| 1. Send | `clients/src/main/java/org/apache/kafka/clients/producer/KafkaProducer.java` | `doSend`: metadata wait, serialization, partitioning, `accumulator.append` |
| 2. Batch | `clients/src/main/java/org/apache/kafka/clients/producer/internals/RecordAccumulator.java` | Per-partition deques, `ready`, `drain`, buffer pool |
| 3. Ship | `clients/src/main/java/org/apache/kafka/clients/producer/internals/Sender.java` | In-flight limits, retries, completing batches |
| 4. Partition | `clients/src/main/java/org/apache/kafka/clients/producer/internals/BuiltInPartitioner.java` | murmur2 for keys, uniform sticky for null keys |
| 5. Dedup on the broker | `storage/src/main/java/org/apache/kafka/storage/internals/log/ProducerStateManager.java` | Per-producer sequence state: why 5 in-flight batches keep idempotence |
| 6. Transactions | `clients/src/main/java/org/apache/kafka/clients/producer/internals/TransactionManager.java` and `core/src/main/scala/kafka/coordinator/transaction/TransactionCoordinator.scala` | Producer epochs, fencing, commit markers |
| 7. Groups (KIP-848) | `group-coordinator/src/main/java/org/apache/kafka/coordinator/group/GroupMetadataManager.java` and `group-coordinator/src/main/java/org/apache/kafka/coordinator/group/modern/consumer/ConsumerGroup.java` | Server-side assignment and incremental reconciliation |
| 8. Classic consumer group | `clients/src/main/java/org/apache/kafka/clients/consumer/internals/ConsumerCoordinator.java` and `clients/src/main/java/org/apache/kafka/clients/consumer/CooperativeStickyAssignor.java` | Join/sync, eager vs cooperative revocation |
| 9. New consumer | `clients/src/main/java/org/apache/kafka/clients/consumer/internals/AsyncKafkaConsumer.java` | The background-thread consumer used with `group.protocol=consumer` |
| 10. Fetch | `clients/src/main/java/org/apache/kafka/clients/consumer/internals/Fetcher.java` | Fetch sessions, `isolation.level` handling |

Pair each stop with the experiment in [10.1](../10-Kafka-Production/01-Kafka-Producers-Batching-Idempotence-Ordering.md)/[10.2](../10-Kafka-Production/02-Kafka-Consumers-Rebalancing-EOS-Retries-DLQ.md) that exercised it: batching numbers, sticky null keys, read-committed filtering, eager vs cooperative vs KIP-848 revocations.

---

## 5. spring-projects/spring-kafka ⚡

| Path | What to look for |
|---|---|
| `spring-kafka/src/main/java/org/springframework/kafka/listener/KafkaMessageListenerContainer.java` | The poll loop, ack modes, commits, pause/resume, rebalance listener integration |
| `spring-kafka/src/main/java/org/springframework/kafka/listener/DefaultErrorHandler.java` | Seek-to-current retries; default `FixedBackOff(0, 9)` (verified in [10.2 §4.1](../10-Kafka-Production/02-Kafka-Consumers-Rebalancing-EOS-Retries-DLQ.md)). Each retry is a fresh poll, ~0.5 s apart on a caught-up partition, and the recoverer runs on the consumer thread ([8.6 §7](06-Framework-Internals-by-Stack-Trace-Spring-Hibernate-HikariCP-Caffeine-Kafka.md)) |
| `spring-kafka/src/main/java/org/springframework/kafka/listener/DeadLetterPublishingRecoverer.java` | DLT naming (`-dlt` in 4.x), header population |
| `spring-kafka/src/main/java/org/springframework/kafka/retrytopic/RetryTopicConfigurer.java` | How one `@RetryableTopic` becomes several topics and containers |
| `spring-kafka/src/main/java/org/springframework/kafka/listener/KafkaConsumerBackoffManager.java` | Non-blocking delay = pausing a partition until the record's due time |

---

## 6. Exercises

1. Draw the FTGO `CreateOrderSaga` as a state machine with compensations. Then decide where you'd add a **timeout** and what it compensates.
2. Read `SagaLockManagerImpl` and write the SQL for `claimLock`, `stashMessage` and `unlock` from memory. Compare with `V1000__tram-saga-schema.sql`.
3. Run `debezium-examples/outbox`, stop the Kafka Connect container for a minute, and watch the replication slot retain WAL (same lesson as [5.4](../05-Microservices-Patterns/04-Transactional-Outbox-and-Idempotent-Consumer-Complete-Implementation.md), measured there as retained WAL growing while the slot was inactive).
4. Trace one record through Kafka stops 1–5 above and explain why `max.in.flight.requests.per.connection ≤ 5` is required for idempotence by pointing to code.

---

## 7. Interview soundbites

* "FTGO's create-order saga has the textbook shape: compensatable steps, card authorization as the pivot, then retriable steps."
* "Eventuate implements semantic locks generically: a lock row per target, and commands for a locked target are stashed and handed over on unlock."
* "Eventuate's duplicate detector and my own `processed_message` table are the same idea: a unique `(consumer, message_id)` insert in the handler's transaction."
* "Debezium's examples show the outbox, a CDC-driven saga, and cache invalidation from the WAL. The failover-slots example is the operational detail people forget."

---

## 8. Deep dive: the saga, outbox and Kafka code at its pins (verified 2026-10-26) 🧊

The Eventuate repositories have no release tags, so they're pinned to commits: sagas at [`cd327a0c5f`](https://github.com/eventuate-tram/eventuate-tram-sagas/tree/cd327a0c5f986337b23c0b2e51d68b78f7c3857d), core at [`273bf06509`](https://github.com/eventuate-tram/eventuate-tram-core/tree/273bf065091069cc17367a40aab04ebf681df97d), and FTGO at [`558dfc53b1`](https://github.com/microservices-patterns/ftgo-application/tree/558dfc53b11d30a5f1d995c0c6d58d5106c28189). Debezium is pinned at `v3.7.0.Final`, the version [5.4](../05-Microservices-Patterns/04-Transactional-Outbox-and-Idempotent-Consumer-Complete-Implementation.md) ran; Kafka at `4.2.2` and spring-kafka at `v4.1.2`. All **35 paths cited in this file** resolve at those pins.

### 8.1 Eventuate's semantic lock, line by line

§1.3 described it; here's where each step lives:

| Step | Code at the pin |
|---|---|
| Try to take the lock: insert a row for the target | [`claimLock`](https://github.com/eventuate-tram/eventuate-tram-sagas/blob/cd327a0c5f986337b23c0b2e51d68b78f7c3857d/eventuate-tram-sagas-common/src/main/java/io/eventuate/tram/sagas/common/SagaLockManagerImpl.java#L31) |
| On conflict, find the owner with `select … for update` | [`selectForUpdate(target)`](https://github.com/eventuate-tram/eventuate-tram-sagas/blob/cd327a0c5f986337b23c0b2e51d68b78f7c3857d/eventuate-tram-sagas-common/src/main/java/io/eventuate/tram/sagas/common/SagaLockManagerImpl.java#L38) |
| A command for a locked target is parked | [`stashMessage`](https://github.com/eventuate-tram/eventuate-tram-sagas/blob/cd327a0c5f986337b23c0b2e51d68b78f7c3857d/eventuate-tram-sagas-common/src/main/java/io/eventuate/tram/sagas/common/SagaLockManagerImpl.java#L57) |
| On completion, delete the lock or hand it to the next stashed saga | [`unlock`](https://github.com/eventuate-tram/eventuate-tram-sagas/blob/cd327a0c5f986337b23c0b2e51d68b78f7c3857d/eventuate-tram-sagas-common/src/main/java/io/eventuate/tram/sagas/common/SagaLockManagerImpl.java#L71), [hand-over update](https://github.com/eventuate-tram/eventuate-tram-sagas/blob/cd327a0c5f986337b23c0b2e51d68b78f7c3857d/eventuate-tram-sagas-common/src/main/java/io/eventuate/tram/sagas/common/SagaLockManagerImpl.java#L99) |

### 8.2 Eventuate's deduplication runs in the handler's transaction

§2 claimed the duplicate check and the handler's effects commit together. At the pin, that's explicit:

```java
public void doWithMessage(SubscriberIdAndMessage subscriberIdAndMessage, Runnable callback) {
  eventuateTransactionTemplate.executeInTransaction(() -> {
    if (!isDuplicate(subscriberIdAndMessage.getSubscriberId(), subscriberIdAndMessage.getMessage().getId()))
      callback.run();
    return null;
  });
}
```

[`isDuplicate`](https://github.com/eventuate-tram/eventuate-tram-core/blob/273bf065091069cc17367a40aab04ebf681df97d/eventuate-tram-consumer-jdbc/src/main/java/io/eventuate/tram/consumer/jdbc/SqlTableBasedDuplicateMessageDetector.java#L31) inserts `(consumer_id, message_id)` and treats a [duplicate-key exception](https://github.com/eventuate-tram/eventuate-tram-core/blob/273bf065091069cc17367a40aab04ebf681df97d/eventuate-tram-consumer-jdbc/src/main/java/io/eventuate/tram/consumer/jdbc/SqlTableBasedDuplicateMessageDetector.java#L42) as "already processed". The insert and `callback.run()` share one transaction, which is exactly [5.4](../05-Microservices-Patterns/04-Transactional-Outbox-and-Idempotent-Consumer-Complete-Implementation.md)'s `processed_message` design.

### 8.3 Debezium's outbox router defaults (3.7.0)

[`route.by.field`](https://github.com/debezium/debezium/blob/v3.7.0.Final/debezium-connect-plugins/src/main/java/io/debezium/transforms/outbox/EventRouterConfigDefinition.java#L308) defaults to `aggregatetype`, and the topic is [`outbox.event.${routedByValue}`](https://github.com/debezium/debezium/blob/v3.7.0.Final/debezium-connect-plugins/src/main/java/io/debezium/transforms/outbox/EventRouterConfigDefinition.java#L327). An outbox row with `aggregatetype = 'order'` lands on `outbox.event.order` unless you override it. Name topics deliberately before the first event ships; renaming later is a migration for every consumer.

### 8.4 Kafka and spring-kafka: the lines behind Pillar 10's measurements

The four Kafka-side surprises in this kit each have a one-line cause:
* the 45-second static-member stall;
* KIP-848's `-2` epoch;
* spring-kafka's `-0…-N` instance suffix;
* retries about 500 ms apart.

They're linked and quoted in [8.7 §5](07-Source-Behind-the-Measurements-JDK-PostgreSQL-Redis-Kubernetes-Kafka.md). The listener and recoverer call paths, with frames linked to `v4.1.2`, are in [8.6 §7](06-Framework-Internals-by-Stack-Trace-Spring-Hibernate-HikariCP-Caffeine-Kafka.md). Two facts from there change how you read §5's table:

* `DefaultErrorHandler`'s recoverer runs **on the consumer thread**: a DLT publish happens inside the poll loop.
* The DLT topic is named by `DeadLetterPublishingRecoverer`'s [default resolver](https://github.com/spring-projects/spring-kafka/blob/v4.1.2/spring-kafka/src/main/java/org/springframework/kafka/listener/DeadLetterPublishingRecoverer.java#L76): `<topic>-dlt`, **same partition**, so the DLT needs at least as many partitions as the source topic.

### 8.5 FTGO's pivot, pinned

The pivot step from §1.1 is unchanged at the pin: [`invokeParticipant(accountingService.authorize, …)`](https://github.com/microservices-patterns/ftgo-application/blob/558dfc53b11d30a5f1d995c0c6d58d5106c28189/ftgo-order-service/src/main/java/net/chrisrichardson/ftgo/orderservice/sagas/createorder/CreateOrderSaga.java#L29), with no `withCompensation`.

## Summary

| Topic | Key point | Section |
|---|---|---|
| Orchestrated sagas | FTGO's `CreateOrderSaga`: compensatable steps, card authorization as the pivot, then retriable steps | §1.1 |
| Semantic locks | Eventuate's `saga_lock_table` + `saga_stash_table`: insert, `select … for update`, stash, hand over | §1.3, §8.1 |
| Idempotent consumer | `received_messages` insert and the handler in one transaction | §2, §8.2 |
| CDC | Debezium examples: outbox, CDC saga, cache invalidation, failover slots, TOAST | §3 |
| Outbox routing | Default topic `outbox.event.${aggregatetype}` | §8.3 |
| Kafka internals | Read along one record: `doSend` → accumulator → sender → broker state → groups | §4 |
| spring-kafka | Recoverer on the consumer thread; DLT `<topic>-dlt` on the same partition | §5, §8.4 |

**Next:** [8.4 High-performance internals: HikariCP, Resilience4j, Caffeine →](04-High-Performance-Internals-HikariCP-Resilience4j-Caffeine.md)
