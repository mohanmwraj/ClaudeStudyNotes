# 6.5 · Kafka for Spring Engineers — Consumer Groups, Rebalancing, Exactly-Once, Dead Letters

> **Tags:** 🔥 must-know · ⚡ important · 🧊 deep cut
> **Sources:** Apache Kafka 4.0 release announcement (KIP-848 GA, KIP-890 phase 2, ZooKeeper removal); KIP-848 (next-generation consumer rebalance protocol); KIP-1030 (`linger.ms` 0 → 5 ms); KIP-98/KIP-447 (transactions, EOS v2); Spring for Apache Kafka 4.1 reference (error handling, DLT, non-blocking retries).
> **Verified stack:** kafka-clients and an embedded **KRaft** broker **4.2.2** (`EmbeddedKafkaKraftBroker` from spring-kafka-test, as managed by Spring Boot 4.1.2; Apache Kafka 4.4 is the latest release), **spring-kafka 4.1.2**, JDK 25. Every assignment change, isolation result, exception type, header and topic name below was **captured from runs against a real broker** (single node, in-process).

---

## 1. The model in five sentences 🔥

1. A **topic** is split into **partitions**. Each partition is an append-only, ordered log, and a record's position in it is its **offset**. Ordering is guaranteed **only within a partition**. The default partitioner maps a record **key** to a partition (murmur2 hash mod partition count), so all events for one key stay ordered.
2. A **consumer group** shares the work: each partition is owned by **exactly one** member at a time. Parallelism ≤ partitions, and extra members sit idle.
3. Consumers **commit offsets** to `__consumer_offsets`. Committing *after* processing gives **at-least-once**; committing *before* gives at-most-once. Everything in [6.3](03-Outbox-Saga-Idempotency.md) assumes at-least-once.
4. **Rebalancing** reassigns partitions when members join, leave, crash (no heartbeat within `session.timeout.ms`) or stall (no `poll()` within `max.poll.interval.ms`).
5. **Kafka 4.x is KRaft-only** (ZooKeeper was removed in 4.0) and offers two group protocols: `classic` (client-side assignment) and `consumer` (KIP-848, server-side, incremental).

### 1.1 Client defaults you should know (printed by the run in §2.1)

```
consumer defaults: group.protocol=classic, partition.assignment.strategy=[RangeAssignor, CooperativeStickyAssignor], enable.auto.commit=true, auto.offset.reset=latest, isolation.level=read_uncommitted, max.poll.records=500, max.poll.interval.ms=300000, session.timeout.ms=45000
producer defaults: acks=all, enable.idempotence=true, retries=2147483647, delivery.timeout.ms=120000, linger.ms=5, batch.size=16384, max.in.flight.requests.per.connection=5
```

* **`enable.auto.commit=true`** commits offsets on a timer, regardless of whether you finished processing. Spring Kafka's listener container disables it and commits after the listener returns (`AckMode.BATCH` by default).
* **`auto.offset.reset=latest`**: a brand-new group **skips** everything already in the topic. Use `earliest` for consumers that must see history.
* **`isolation.level=read_uncommitted`**: consumers see records from **aborted** transactions unless you set `read_committed` (§3).
* **The producer is idempotent and `acks=all` by default** (since 3.0), and **`linger.ms` is 5 ms since 4.0** (KIP-1030; it was 0). Expect up to 5 ms of added latency per batch, in exchange for better batching.

---

## 2. Rebalancing: eager, cooperative, and the new protocol 🔥

| | Classic, eager (`RangeAssignor`, `RoundRobinAssignor`) | Classic, cooperative (`CooperativeStickyAssignor`) | `group.protocol=consumer` (KIP-848) |
|---|---|---|---|
| Who computes the assignment | Group leader (a client) | Group leader (a client) | **Group coordinator (broker)**, `group.remote.assignor` = `uniform`/`range` |
| On membership change | **Every member revokes everything**, then gets a new assignment (stop-the-world) | Only partitions that **move** are revoked (two rounds) | Incremental per member; no global barrier |
| Heartbeats/timeouts | Client configs | Client configs | Broker configs (`group.consumer.heartbeat.interval.ms`, `group.consumer.session.timeout.ms`) |
| Opt-in | — | Listed in the default strategy list (after Range, so not active by default) | **Client must set `group.protocol=consumer`** (default is still `classic` in 4.2, verified); the 4.x broker supports it by default |

### 2.1 Runnable: a second consumer joins a 6-partition topic

<!-- run: javac cp=@p6kafka timeout=300 -->
```java
package demo.kafka;

import java.time.Duration;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicBoolean;
import org.apache.kafka.clients.consumer.*;
import org.apache.kafka.clients.producer.ProducerConfig;
import org.apache.kafka.common.TopicPartition;
import org.apache.kafka.common.serialization.StringDeserializer;
import org.springframework.kafka.test.EmbeddedKafkaKraftBroker;

public class ConsumerGroups {
    public static void main(String[] args) throws Exception {
        ((ch.qos.logback.classic.Logger) org.slf4j.LoggerFactory.getLogger("ROOT")).setLevel(ch.qos.logback.classic.Level.OFF);
        Map<String, Object> cd = ConsumerConfig.configDef().defaultValues(), pd = ProducerConfig.configDef().defaultValues();
        System.out.println("consumer defaults: group.protocol=" + cd.get("group.protocol") + ", partition.assignment.strategy="
            + ((List<?>) cd.get("partition.assignment.strategy")).stream().map(c -> ((Class<?>) c).getSimpleName()).toList()
            + ", enable.auto.commit=" + cd.get("enable.auto.commit") + ", auto.offset.reset=" + cd.get("auto.offset.reset")
            + ", isolation.level=" + cd.get("isolation.level") + ", max.poll.records=" + cd.get("max.poll.records")
            + ", max.poll.interval.ms=" + cd.get("max.poll.interval.ms") + ", session.timeout.ms=" + cd.get("session.timeout.ms"));
        System.out.println("producer defaults: acks=" + pd.get("acks") + ", enable.idempotence=" + pd.get("enable.idempotence")
            + ", retries=" + pd.get("retries") + ", delivery.timeout.ms=" + pd.get("delivery.timeout.ms") + ", linger.ms=" + pd.get("linger.ms")
            + ", batch.size=" + pd.get("batch.size") + ", max.in.flight.requests.per.connection=" + pd.get("max.in.flight.requests.per.connection"));

        EmbeddedKafkaKraftBroker broker = new EmbeddedKafkaKraftBroker(1, 6, "orders");
        broker.brokerProperties(Map.of("group.initial.rebalance.delay.ms", "0",
            "group.consumer.heartbeat.interval.ms", "500", "group.consumer.min.heartbeat.interval.ms", "500"));
        var stdout = System.out;
        System.setOut(new java.io.PrintStream(java.io.OutputStream.nullOutputStream()));   // the test kit prints its metadata bootstrap
        broker.afterPropertiesSet();
        System.setOut(stdout);
        try {
            rebalance(broker, "classic, eager (RangeAssignor)", Map.of("group.protocol", "classic",
                "partition.assignment.strategy", RangeAssignor.class.getName()));
            rebalance(broker, "classic, CooperativeStickyAssignor", Map.of("group.protocol", "classic",
                "partition.assignment.strategy", CooperativeStickyAssignor.class.getName()));
            rebalance(broker, "consumer (KIP-848, server-side)", Map.of("group.protocol", "consumer"));
        } finally {
            broker.destroy();
        }
    }

    static void rebalance(EmbeddedKafkaKraftBroker broker, String label, Map<String, Object> protocol) throws Exception {
        String group = "billing-" + label.hashCode();
        Map<String, List<String>> events = new ConcurrentHashMap<>();
        Map<String, Set<Integer>> owned = new ConcurrentHashMap<>();
        AtomicBoolean running = new AtomicBoolean(true);
        try (var threads = Executors.newVirtualThreadPerTaskExecutor()) {
            threads.submit(() -> pollLoop(broker, group, protocol, "c1", events, owned, running));
            await(() -> owned.getOrDefault("c1", Set.of()).size() == 6);
            events.clear();                                                      // only report what the 2nd member causes
            threads.submit(() -> pollLoop(broker, group, protocol, "c2", events, owned, running));
            await(() -> owned.getOrDefault("c1", Set.of()).size() == 3 && owned.getOrDefault("c2", Set.of()).size() == 3);
            Thread.sleep(1500);                                                  // let any trailing callbacks arrive
            String result = "c1 " + summary(events.get("c1")) + " | c2 " + summary(events.get("c2"));   // before close() revokes all
            running.set(false);
            System.out.printf("%-34s when c2 joined: %s%n", label, result);
        }
    }

    static Void pollLoop(EmbeddedKafkaKraftBroker broker, String group, Map<String, Object> protocol, String name,
                         Map<String, List<String>> events, Map<String, Set<Integer>> owned, AtomicBoolean running) {
        Map<String, Object> props = new HashMap<>(protocol);
        props.putAll(Map.of(ConsumerConfig.BOOTSTRAP_SERVERS_CONFIG, broker.getBrokersAsString(), ConsumerConfig.GROUP_ID_CONFIG, group,
            ConsumerConfig.KEY_DESERIALIZER_CLASS_CONFIG, StringDeserializer.class, ConsumerConfig.VALUE_DESERIALIZER_CLASS_CONFIG, StringDeserializer.class));
        try (KafkaConsumer<String, String> consumer = new KafkaConsumer<>(props)) {
            consumer.subscribe(List.of("orders"), new ConsumerRebalanceListener() {
                public void onPartitionsRevoked(Collection<TopicPartition> parts) {
                    if (parts.isEmpty()) return;
                    events.computeIfAbsent(name, k -> new CopyOnWriteArrayList<>()).add("revoked " + parts.size());
                    parts.forEach(p -> owned.computeIfAbsent(name, k -> ConcurrentHashMap.newKeySet()).remove(p.partition()));
                }
                public void onPartitionsAssigned(Collection<TopicPartition> parts) {
                    if (parts.isEmpty()) return;
                    events.computeIfAbsent(name, k -> new CopyOnWriteArrayList<>()).add("assigned " + parts.size());
                    parts.forEach(p -> owned.computeIfAbsent(name, k -> ConcurrentHashMap.newKeySet()).add(p.partition()));
                }
            });
            while (running.get()) consumer.poll(Duration.ofMillis(100));
        }
        return null;
    }

    static String summary(List<String> e) { return e == null ? "[]" : e.toString(); }
    static void await(java.util.function.BooleanSupplier condition) throws InterruptedException {
        long deadline = System.nanoTime() + 60_000_000_000L;
        while (!condition.getAsBoolean()) { if (System.nanoTime() > deadline) throw new IllegalStateException("timeout"); Thread.sleep(50); }
    }
}
```

Output (verified):

```
consumer defaults: group.protocol=classic, partition.assignment.strategy=[RangeAssignor, CooperativeStickyAssignor], enable.auto.commit=true, auto.offset.reset=latest, isolation.level=read_uncommitted, max.poll.records=500, max.poll.interval.ms=300000, session.timeout.ms=45000
producer defaults: acks=all, enable.idempotence=true, retries=2147483647, delivery.timeout.ms=120000, linger.ms=5, batch.size=16384, max.in.flight.requests.per.connection=5
classic, eager (RangeAssignor)     when c2 joined: c1 [revoked 6, assigned 3] | c2 [assigned 3]
classic, CooperativeStickyAssignor when c2 joined: c1 [revoked 3] | c2 [assigned 3]
consumer (KIP-848, server-side)    when c2 joined: c1 [revoked 3] | c2 [assigned 3]
```

* **Eager:** c1 revoked **all 6** partitions and got 3 back. During that window nothing in the group was processed, and every in-memory state (caches, open batches) had to be dropped.
* **Cooperative and KIP-848:** c1 revoked only the **3 partitions that moved** and kept processing the others throughout.
* **Note the default strategy list `[RangeAssignor, CooperativeStickyAssignor]`:** the first (eager) one wins. To upgrade a live classic group to cooperative, roll out the list `[CooperativeStickyAssignor, RangeAssignor]` first, then remove Range in a second rollout.

**Rebalance hygiene:**

* **Static membership** (`group.instance.id` per pod, e.g. the StatefulSet ordinal): a restart within the session timeout doesn't trigger a rebalance, which keeps rolling deploys quiet.
* **`max.poll.interval.ms` (5 min)** is the processing deadline per `poll()` batch. A slow batch gets the member kicked out, its partitions reassigned, and **records reprocessed**. Lower `max.poll.records`, speed up processing, or offload with `pause()`/`resume()`.
* **Commit before you lose partitions:** in `onPartitionsRevoked`, commit processed offsets synchronously. Spring Kafka's container does this for you.
* With KIP-848, `partition.assignment.strategy` must not be set on the client, and session and heartbeat timing are **broker** settings.

---

## 3. Delivery guarantees and exactly-once 🔥

```
producer (transactional.id = T, epoch e) ──► partitions: data records … [COMMIT|ABORT marker]
                                               ▲ read_committed consumers read only up to the LSO (last stable offset)
consume → transform → produce:  beginTransaction → send outputs → sendOffsetsToTransaction(input offsets, groupMetadata) → commit
```

* **Idempotent producer** (default): each producer gets a producer ID, and each partition tracks sequence numbers, so retries of the same batch are written **once**, in order, with up to 5 in flight.
* **Transactions:** a `transactional.id` survives restarts. `initTransactions()` bumps its **epoch**, **fences** any older instance ("zombie"), and aborts its open transaction. Commit and abort write **control markers** into each partition.
* **Exactly-once processing (EOS v2, KIP-447)** for Kafka→Kafka pipelines: the output records **and** the consumer offsets commit atomically in one transaction.

### 3.1 Runnable: committed vs aborted transactions, zombie fencing, and a crash mid-transaction

<!-- run: javac cp=@p6kafka timeout=300 -->
```java
package demo.kafka;

import java.time.Duration;
import java.util.*;
import org.apache.kafka.clients.consumer.*;
import org.apache.kafka.clients.producer.*;
import org.apache.kafka.common.TopicPartition;
import org.apache.kafka.common.serialization.*;
import org.springframework.kafka.test.EmbeddedKafkaKraftBroker;

public class ExactlyOnce {
    static String bootstrap;

    public static void main(String[] args) throws Exception {
        ((ch.qos.logback.classic.Logger) org.slf4j.LoggerFactory.getLogger("ROOT")).setLevel(ch.qos.logback.classic.Level.OFF);
        EmbeddedKafkaKraftBroker broker = new EmbeddedKafkaKraftBroker(1, 1, "orders", "payments", "ledger");
        broker.brokerProperties(Map.of("transaction.state.log.replication.factor", "1", "transaction.state.log.min.isr", "1",
            "group.initial.rebalance.delay.ms", "0"));
        var stdout = System.out;
        System.setOut(new java.io.PrintStream(java.io.OutputStream.nullOutputStream()));
        broker.afterPropertiesSet();
        System.setOut(stdout);
        bootstrap = broker.getBrokersAsString();
        try {
            // 1. a committed and an aborted transaction, seen by both isolation levels
            try (KafkaProducer<String, String> p = producer("orders-tx")) {
                p.initTransactions();
                p.beginTransaction();
                for (String v : List.of("A1", "A2", "A3")) p.send(new ProducerRecord<>("orders", v));
                p.commitTransaction();
                p.beginTransaction();
                for (String v : List.of("B1", "B2")) p.send(new ProducerRecord<>("orders", v));
                p.flush();
                p.abortTransaction();
            }
            System.out.println("1. read_uncommitted sees " + readAll("orders", "read_uncommitted"));
            System.out.println("   read_committed   sees " + readAll("orders", "read_committed") + ", log end offset = " + endOffset("orders")
                + " (5 records + 2 transaction markers)");

            // 2. zombie fencing: a second producer with the same transactional.id fences the first
            try (KafkaProducer<String, String> zombie = producer("payments-processor-0");
                 KafkaProducer<String, String> successor = producer("payments-processor-0")) {
                zombie.initTransactions();
                successor.initTransactions();                                  // bumps the epoch for this transactional.id
                try {
                    zombie.beginTransaction();
                    zombie.send(new ProducerRecord<>("ledger", "zombie write")).get();
                    zombie.commitTransaction();
                } catch (Exception e) {
                    Throwable t = e instanceof java.util.concurrent.ExecutionException ? e.getCause() : e;
                    System.out.println("2. old producer after a successor called initTransactions: " + t.getClass().getSimpleName());
                }
            }

            // 3. consume-transform-produce with offsets committed in the same transaction
            try (KafkaProducer<String, String> p = new KafkaProducer<>(Map.of(ProducerConfig.BOOTSTRAP_SERVERS_CONFIG, bootstrap,
                    ProducerConfig.KEY_SERIALIZER_CLASS_CONFIG, StringSerializer.class, ProducerConfig.VALUE_SERIALIZER_CLASS_CONFIG, StringSerializer.class))) {
                for (String v : List.of("pay-1", "pay-2", "pay-3", "pay-4")) p.send(new ProducerRecord<>("payments", v));
            }
            int firstRun = process(2);                                         // crashes after producing 2 outputs, before commit
            int secondRun = process(Integer.MAX_VALUE);                        // restart: resumes from the last committed offset
            System.out.println("3. run 1 produced " + firstRun + " then crashed before commit; run 2 produced " + secondRun);
            System.out.println("   ledger read_committed   = " + readAll("ledger", "read_committed"));
            System.out.println("   ledger read_uncommitted = " + readAll("ledger", "read_uncommitted"));
        } finally {
            broker.destroy();
        }
    }

    /** Reads committed input, writes output + consumer offsets atomically. crashAfter simulates a process kill. */
    static int process(int crashAfter) {
        int produced = 0;
        try (KafkaConsumer<String, String> in = consumer("ledger-writer", "read_committed");
             KafkaProducer<String, String> out = producer("ledger-writer-0")) {
            out.initTransactions();                                            // also aborts the previous incarnation's open transaction
            in.subscribe(List.of("payments"));
            for (int idle = 0; idle < 30; idle++) {
                ConsumerRecords<String, String> batch = in.poll(Duration.ofMillis(200));
                if (batch.isEmpty()) { if (produced > 0) break; continue; }
                out.beginTransaction();
                Map<TopicPartition, OffsetAndMetadata> offsets = new HashMap<>();
                for (ConsumerRecord<String, String> r : batch) {
                    out.send(new ProducerRecord<>("ledger", r.value().toUpperCase()));
                    offsets.put(new TopicPartition(r.topic(), r.partition()), new OffsetAndMetadata(r.offset() + 1));
                    if (++produced == crashAfter) { out.flush(); return produced; }   // "kill -9": no commit, no abort
                }
                out.sendOffsetsToTransaction(offsets, in.groupMetadata());
                out.commitTransaction();
            }
        }
        return produced;
    }

    static KafkaProducer<String, String> producer(String transactionalId) {
        return new KafkaProducer<>(Map.of(ProducerConfig.BOOTSTRAP_SERVERS_CONFIG, bootstrap, ProducerConfig.TRANSACTIONAL_ID_CONFIG, transactionalId,
            ProducerConfig.KEY_SERIALIZER_CLASS_CONFIG, StringSerializer.class, ProducerConfig.VALUE_SERIALIZER_CLASS_CONFIG, StringSerializer.class));
    }
    static KafkaConsumer<String, String> consumer(String group, String isolation) {
        return new KafkaConsumer<>(Map.of(ConsumerConfig.BOOTSTRAP_SERVERS_CONFIG, bootstrap, ConsumerConfig.GROUP_ID_CONFIG, group,
            ConsumerConfig.ISOLATION_LEVEL_CONFIG, isolation, ConsumerConfig.AUTO_OFFSET_RESET_CONFIG, "earliest",
            ConsumerConfig.ENABLE_AUTO_COMMIT_CONFIG, false,
            ConsumerConfig.KEY_DESERIALIZER_CLASS_CONFIG, StringDeserializer.class, ConsumerConfig.VALUE_DESERIALIZER_CLASS_CONFIG, StringDeserializer.class));
    }
    static List<String> readAll(String topic, String isolation) {
        try (KafkaConsumer<String, String> c = consumer("reader-" + UUID.randomUUID(), isolation)) {
            TopicPartition tp = new TopicPartition(topic, 0);
            c.assign(List.of(tp));
            c.seekToBeginning(List.of(tp));
            List<String> values = new ArrayList<>();
            for (int i = 0; i < 10; i++) c.poll(Duration.ofMillis(300)).forEach(r -> values.add(r.value()));
            return values;
        }
    }
    static long endOffset(String topic) {
        try (KafkaConsumer<String, String> c = consumer("offsets", "read_uncommitted")) {
            return c.endOffsets(List.of(new TopicPartition(topic, 0))).values().iterator().next();
        }
    }
}
```

Output (verified):

```
1. read_uncommitted sees [A1, A2, A3, B1, B2]
   read_committed   sees [A1, A2, A3], log end offset = 7 (5 records + 2 transaction markers)
2. old producer after a successor called initTransactions: InvalidProducerEpochException
3. run 1 produced 2 then crashed before commit; run 2 produced 4
   ledger read_committed   = [PAY-1, PAY-2, PAY-3, PAY-4]
   ledger read_uncommitted = [PAY-1, PAY-2, PAY-1, PAY-2, PAY-3, PAY-4]
```

1. **Isolation level is a consumer decision.** `read_uncommitted` (the default!) delivered the aborted `B1`, `B2`. `read_committed` delivered only the committed records. The log end offset is 7: **transaction markers occupy offsets**, so offsets are not record counts. Never compute "lag = messages" from offsets on transactional topics.
2. **Zombie fencing:** after the successor's `initTransactions()`, the old producer's next send failed. On Kafka 4.2 (transaction protocol v2 from KIP-890 is active: the broker bootstrapped `transaction.version` level 2) the error surfaced as **`InvalidProducerEpochException`**. Older clients and brokers report `ProducerFencedException`. Treat both as fatal: close the producer and stop processing.
3. **EOS survives a crash mid-batch.** Run 1 produced `PAY-1`, `PAY-2` and died before committing. Run 2's `initTransactions()` aborted that transaction, re-read from the last **committed** offset, and produced all 4. `read_committed` readers see exactly 4 outputs; `read_uncommitted` readers see the 2 aborted duplicates too.

**What EOS does *not* cover:** any side effect outside Kafka (database writes, HTTP calls, emails). A listener that writes to PostgreSQL inside a Kafka transaction can still double-write after a crash. For those, use the idempotent-consumer techniques of [6.3 §3](03-Outbox-Saga-Idempotency.md#3-idempotent-consumers-), or the outbox in the other direction.

**Operational gotcha:** `read_committed` consumers stop at the **LSO**. One producer with a long-open or hung transaction (up to `transaction.timeout.ms`, default 60 s) stalls every `read_committed` consumer of those partitions, which shows up as lag with no visible cause.

**In Spring:** `KafkaTemplate.executeInTransaction(…)`, `KafkaTransactionManager` + `@Transactional`, or a listener container with a transaction manager (it sends the offsets to the transaction for you, EOS v2). Set `transactional.id` prefixes per application instance.

---

## 4. Errors, retries and dead-letter topics 🔥

| | Blocking retries: `DefaultErrorHandler` + `DeadLetterPublishingRecoverer` | Non-blocking retries: `@RetryableTopic` |
|---|---|---|
| How | Re-seeks and redelivers the failed record in place, with a `BackOff` | Forwards the record to retry topic(s) with a delay header, consumed by the same listener after the delay |
| Partition while retrying | **Blocked** (ordering preserved) | **Keeps flowing** (ordering lost for retried records) |
| Long back-offs | Risky (`max.poll.interval.ms`; the container pauses the consumer to cope) | Fine (minutes or hours) |
| Extra topics | `<topic>-dlt` | `<topic>-retry[-N]` + `<topic>-dlt` (auto-created) |
| Requirements | — | `@EnableKafkaRetryTopic` (Boot: automatic) **and a `TaskScheduler` bean** (verified: startup fails without one in plain Spring) |

### 4.1 Runnable: poison pills, non-retryable errors, retry topics, and what lands in the DLT

<!-- run: javac cp=@p6kafka timeout=300 -->
```java
package demo.kafka.dlt;

import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.util.*;
import java.util.concurrent.*;
import org.apache.kafka.clients.consumer.*;
import org.apache.kafka.clients.producer.ProducerConfig;
import org.apache.kafka.common.TopicPartition;
import org.apache.kafka.common.serialization.*;
import org.springframework.context.annotation.*;
import org.springframework.kafka.annotation.*;
import org.springframework.kafka.config.ConcurrentKafkaListenerContainerFactory;
import org.springframework.kafka.core.*;
import org.springframework.kafka.listener.*;
import org.springframework.kafka.test.EmbeddedKafkaKraftBroker;
import org.springframework.util.backoff.FixedBackOff;

public class DeadLetters {
    static String bootstrap;
    static final Map<String, Integer> deliveries = new ConcurrentSkipListMap<>();

    public static class Listeners {
        @KafkaListener(id = "orders-listener", topics = "orders", containerFactory = "blockingRetries")
        public void onOrder(String value) {
            deliveries.merge("orders:" + value, 1, Integer::sum);
            if (value.equals("poison")) throw new IllegalStateException("cannot price order " + value);
            if (value.equals("malformed")) throw new IllegalArgumentException("not a valid order: " + value);
        }

        @RetryableTopic(attempts = "3", backOff = @BackOff(delay = 200), numPartitions = "1", replicationFactor = "1")
        @KafkaListener(id = "payments-listener", topics = "payments")
        public void onPayment(String value) {
            deliveries.merge("payments:" + value, 1, Integer::sum);
            if (value.startsWith("declined")) throw new IllegalStateException("gateway timeout for " + value);
        }
    }

    @Configuration @EnableKafka @EnableKafkaRetryTopic
    static class Config {
        @Bean ConsumerFactory<String, String> consumerFactory() {
            return new DefaultKafkaConsumerFactory<>(Map.of(ConsumerConfig.BOOTSTRAP_SERVERS_CONFIG, bootstrap,
                ConsumerConfig.AUTO_OFFSET_RESET_CONFIG, "earliest", ConsumerConfig.GROUP_ID_CONFIG, "demo",
                ConsumerConfig.KEY_DESERIALIZER_CLASS_CONFIG, StringDeserializer.class, ConsumerConfig.VALUE_DESERIALIZER_CLASS_CONFIG, StringDeserializer.class));
        }
        @Bean ProducerFactory<String, String> producerFactory() {
            return new DefaultKafkaProducerFactory<>(Map.of(ProducerConfig.BOOTSTRAP_SERVERS_CONFIG, bootstrap,
                ProducerConfig.KEY_SERIALIZER_CLASS_CONFIG, StringSerializer.class, ProducerConfig.VALUE_SERIALIZER_CLASS_CONFIG, StringSerializer.class));
        }
        @Bean KafkaTemplate<String, String> kafkaTemplate(ProducerFactory<String, String> pf) { return new KafkaTemplate<>(pf); }
        @Bean ConcurrentKafkaListenerContainerFactory<String, String> kafkaListenerContainerFactory(ConsumerFactory<String, String> cf) {
            var f = new ConcurrentKafkaListenerContainerFactory<String, String>();
            f.setConsumerFactory(cf);
            return f;
        }
        @Bean ConcurrentKafkaListenerContainerFactory<String, String> blockingRetries(ConsumerFactory<String, String> cf, KafkaTemplate<String, String> t) {
            var handler = new DefaultErrorHandler(new DeadLetterPublishingRecoverer(t), new FixedBackOff(100, 2));   // 1 try + 2 retries
            handler.addNotRetryableExceptions(IllegalArgumentException.class);                                    // bad data: straight to DLT
            var f = new ConcurrentKafkaListenerContainerFactory<String, String>();
            f.setConsumerFactory(cf);
            f.setCommonErrorHandler(handler);
            return f;
        }
        @Bean Listeners listeners() { return new Listeners(); }
        @Bean org.springframework.scheduling.concurrent.ThreadPoolTaskScheduler taskScheduler() {   // retry topics need one (Boot provides it)
            return new org.springframework.scheduling.concurrent.ThreadPoolTaskScheduler();
        }
    }

    public static void main(String[] args) throws Exception {
        ((ch.qos.logback.classic.Logger) org.slf4j.LoggerFactory.getLogger("ROOT")).setLevel(ch.qos.logback.classic.Level.OFF);
        EmbeddedKafkaKraftBroker broker = new EmbeddedKafkaKraftBroker(1, 1, "orders", "payments", "orders-dlt");
        broker.brokerProperties(Map.of("group.initial.rebalance.delay.ms", "0"));
        var stdout = System.out;
        System.setOut(new java.io.PrintStream(java.io.OutputStream.nullOutputStream()));
        broker.afterPropertiesSet();
        System.setOut(stdout);
        bootstrap = broker.getBrokersAsString();
        try (var ctx = new AnnotationConfigApplicationContext(Config.class)) {
            @SuppressWarnings("unchecked") KafkaTemplate<String, String> template = ctx.getBean(KafkaTemplate.class);
            for (String v : List.of("ok-1", "poison", "malformed", "ok-2")) template.send("orders", v);
            for (String v : List.of("paid-1", "declined-7")) template.send("payments", v);
            template.flush();

            List<ConsumerRecord<String, String>> ordersDlt = drain("orders-dlt", 2);
            String paymentsDltTopic = topics(broker).stream().filter(n -> n.startsWith("payments-dlt")).findFirst().orElseThrow();
            List<ConsumerRecord<String, String>> paymentsDlt = drain(paymentsDltTopic, 1);

            System.out.println("deliveries per message: " + deliveries);
            for (var r : ordersDlt) System.out.println("orders-dlt ← " + r.value() + " | " + headers(r));
            for (var r : paymentsDlt) System.out.println(paymentsDltTopic + " ← " + r.value() + " | " + headers(r));
            System.out.println("topics: " + topics(broker));
        } finally {
            broker.destroy();
        }
    }

    static SortedSet<String> topics(EmbeddedKafkaKraftBroker broker) {
        return broker.<SortedSet<String>>doWithAdminFunction(admin -> {
            try { return new TreeSet<>(admin.listTopics().names().get()); } catch (Exception e) { throw new RuntimeException(e); }
        });
    }

    static String headers(ConsumerRecord<String, String> r) {           // the two DLT mechanisms use different header names
        String prefix = r.headers().lastHeader("kafka_dlt-original-topic") != null ? "kafka_dlt-" : "kafka_";
        return "headers " + prefix + "*: exception-cause-fqcn=" + text(r, prefix + "exception-cause-fqcn")
            + ", original-topic=" + text(r, prefix + "original-topic")
            + ", original-offset=" + java.nio.ByteBuffer.wrap(r.headers().lastHeader(prefix + "original-offset").value()).getLong();
    }
    static String text(ConsumerRecord<String, String> r, String header) { return new String(r.headers().lastHeader(header).value(), StandardCharsets.UTF_8); }

    static List<ConsumerRecord<String, String>> drain(String topic, int expected) {
        try (KafkaConsumer<String, String> c = new KafkaConsumer<>(Map.of(ConsumerConfig.BOOTSTRAP_SERVERS_CONFIG, bootstrap,
                ConsumerConfig.GROUP_ID_CONFIG, "inspector-" + topic, ConsumerConfig.AUTO_OFFSET_RESET_CONFIG, "earliest",
                ConsumerConfig.KEY_DESERIALIZER_CLASS_CONFIG, StringDeserializer.class, ConsumerConfig.VALUE_DESERIALIZER_CLASS_CONFIG, StringDeserializer.class))) {
            c.subscribe(List.of(topic));
            List<ConsumerRecord<String, String>> got = new ArrayList<>();
            long deadline = System.nanoTime() + 60_000_000_000L;
            while (got.size() < expected && System.nanoTime() < deadline) c.poll(Duration.ofMillis(200)).forEach(got::add);
            got.sort(Comparator.comparing(ConsumerRecord::value));
            return got;
        }
    }
}
```

Output (verified):

```
deliveries per message: {orders:malformed=1, orders:ok-1=1, orders:ok-2=1, orders:poison=3, payments:declined-7=3, payments:paid-1=1}
orders-dlt ← malformed | headers kafka_dlt-*: exception-cause-fqcn=java.lang.IllegalArgumentException, original-topic=orders, original-offset=2
orders-dlt ← poison | headers kafka_dlt-*: exception-cause-fqcn=java.lang.IllegalStateException, original-topic=orders, original-offset=1
payments-dlt ← declined-7 | headers kafka_*: exception-cause-fqcn=java.lang.IllegalStateException, original-topic=payments, original-offset=1
topics: [orders, orders-dlt, payments, payments-dlt, payments-retry]
```

* **`poison`** was delivered **3 times** (1 + 2 retries from `FixedBackOff(100, 2)`), then published to **`orders-dlt`**. The partition was blocked while it retried, so `ok-2` waited behind it.
* **`malformed`** (an `IllegalArgumentException`, registered as **not retryable**) went to the DLT after **1** delivery. Retrying bad data only wastes time. By default the handler already treats deserialization, conversion and `ClassCastException`-type errors as not retryable. Add your validation exceptions.
* **`declined-7`** went through `payments` → `payments-retry` (one topic reused for a fixed back-off) → `payments-dlt`: 3 deliveries without ever blocking `payments`.
* **The two mechanisms use different header names** (verified): `DeadLetterPublishingRecoverer` writes `kafka_dlt-original-topic`, `kafka_dlt-exception-cause-fqcn`, …, while the retry-topic DLT carries `kafka_original-topic`, `kafka_exception-cause-fqcn`, …. A generic "DLT replay" tool must handle both.
* The top-level exception in either case is Spring's `ListenerExecutionFailedException`. **Classify on the cause** (`exception-cause-fqcn`).
* **spring-kafka 4** uses its own `@BackOff` annotation (with `jitter`) and no longer depends on Spring Retry (no `spring-retry` jar on this classpath).

**DLT operations:** alert on any DLT traffic; keep the DLT's retention longer than your fix-and-replay cycle; build a replay path (DLT → original topic, after the fix, preserving the key); use `ErrorHandlingDeserializer` so undeserializable bytes reach the DLT instead of looping forever.

---

## 5. Partitioning and ordering ⚡

* **Pick keys for ordering and spread:** order ID or account ID, not country or status (hot partitions). Throughput per partition is bounded, and consumer parallelism ≤ partitions.
* **Adding partitions remaps keys** (hash mod N changes), so for a while events of one key can be processed out of order across old and new partitions. Over-provision partitions up front.
* **Per-key parallelism inside one partition:** Spring Kafka `concurrency` creates multiple consumers (≤ partitions). Beyond that, use a key-ordered worker pool (Confluent Parallel Consumer, or a hash-to-virtual-thread queue), committing offsets only up to the lowest fully processed offset.

---

## 6. Production failure modes & diagnostics

| Symptom | Cause | Confirm with | Fix |
|---|---|---|---|
| Duplicate processing after deploys | Rebalance before an offset commit; `max.poll.interval.ms` exceeded | Logs: "consumer poll timeout has expired"; `rebalance-rate-per-hour` | Idempotent consumers; static membership; smaller batches |
| Lag spikes on every rolling deploy | Eager rebalances | Rebalance count per deploy; all partitions revoked | Cooperative-sticky or KIP-848; static membership |
| One partition's lag grows, others fine | Poison record with blocking retries; hot key | Container logs with the same offset repeating; per-partition lag | DLT with bounded retries; non-retryable classification; better keys |
| `read_committed` consumers stuck | Open or hung transaction (LSO not advancing) | `kafka-transactions.sh --describe` / admin `listTransactions`; consumer lag at the LSO | Fix or abort the producer; shorter `transaction.timeout.ms` |
| Consumers see "phantom" events that were rolled back | `read_uncommitted` (default) on transactional topics | Data shows aborted records | `isolation.level=read_committed` |
| New consumer group misses historical data | `auto.offset.reset=latest` default | Committed offsets start at the log end | `earliest` for that group, or reset offsets with the CLI |
| Producer `TimeoutException`s under load | `delivery.timeout.ms` exceeded (broker slow, ISR shrink) | Producer metrics `record-error-rate`, `request-latency-avg` | Broker health; batching; backpressure upstream |
| `InvalidProducerEpochException` / `ProducerFencedException` | Two instances share a `transactional.id`, or a zombie after failover | Logs of both instances | Unique `transactional.id` per instance; close the fenced producer |
| JDK 24+ prints "terminally deprecated method in sun.misc.Unsafe" | kafka-clients 4.2.2 calls `Unsafe::invokeCleaner` (seen on JDK 25) | stderr at startup | Harmless today; track client upgrades ([1.2](../01-JVM-Internals/02-Runtime-Data-Areas-Off-Heap-FFM.md) covers the JDK's `Unsafe` deprecation timeline) |

**Metrics:** consumer `records-lag-max` (and exported group lag, e.g. Kafka exporter or Burrow), `rebalance-rate-per-hour`, `last-rebalance-seconds-ago`, `commit-latency-avg`; producer `record-error-rate`, `record-retry-rate`, `request-latency-avg`, `batch-size-avg`; Spring Kafka `spring.kafka.listener` timers (Micrometer); DLT message rate.

---

## 7. Interview Q&A

<details><summary><b>Q1. 🔥 How does Kafka guarantee ordering, and how can you break it?</b></summary>

Only within a partition. Records with the same key go to the same partition (murmur2 hash mod partition count), so per-key order holds as long as the partition count doesn't change, retries don't reorder (the idempotent producer prevents reordering with up to 5 in-flight requests), and consumers process a partition sequentially. It breaks when you add partitions (keys remap), use non-blocking retry topics (retried records come back later), or process one partition's records in parallel without per-key sequencing.
</details>

<details><summary><b>Q2. 🔥 Eager vs cooperative rebalancing vs KIP-848?</b></summary>

Eager: every member revokes all partitions and waits for the new assignment (stop-the-world; verified: c1 revoked 6). Cooperative-sticky: only the partitions that move are revoked, over two rebalance rounds (verified: c1 revoked 3). KIP-848 (`group.protocol=consumer`, GA in Kafka 4.0): the broker computes assignments and reconciles each member incrementally, with no group-wide barrier; heartbeat and session settings are broker-side. Clients still default to `classic` in 4.2 (verified).
</details>

<details><summary><b>Q3. 🔥 What does "exactly-once" mean in Kafka, precisely?</b></summary>

For read-process-write pipelines **within Kafka**: output records and input offsets commit atomically in one producer transaction, and downstream `read_committed` consumers only see committed results. After a crash, the new instance's `initTransactions()` aborts the open transaction and fences zombies (verified: 4 outputs visible to `read_committed` despite a crash mid-batch). It doesn't extend to external side effects (DB writes, HTTP calls), which need idempotent consumers or the outbox pattern.
</details>

<details><summary><b>Q4. ⚡ Why might `read_committed` consumers show lag even though producers are healthy?</b></summary>

They can't read past the last stable offset: the first offset of the oldest still-open transaction. A producer that began a transaction and hung or crashed holds the LSO until the transaction is aborted (`transaction.timeout.ms`, default 60 s). Also, transaction markers occupy offsets, so offset-based lag overstates the number of records (verified: 5 records + 2 markers = end offset 7).
</details>

<details><summary><b>Q5. ⚡ Blocking retries vs `@RetryableTopic`: when do you use each?</b></summary>

Blocking (`DefaultErrorHandler` with a back-off, then a DLT) when per-key ordering matters and retries are short. The partition waits, which is visible as lag. Non-blocking retry topics when throughput matters more than ordering, or retries need long delays. The main partition keeps flowing, and failed records are re-consumed from retry topics later. Either way, classify non-retryable exceptions (bad data goes straight to the DLT), alert on DLT traffic, and build a replay path. Note the different DLT header names (`kafka_dlt-*` vs `kafka_*`, verified).
</details>

<details><summary><b>Q6. 🧊 What is `max.poll.interval.ms`, and what happens when you exceed it?</b></summary>

The maximum time between `poll()` calls (default 5 min) before the consumer is considered stuck. The client leaves the group proactively, its partitions are reassigned, and uncommitted records are redelivered to another member, so they get processed twice. Causes are slow batches (`max.poll.records` × per-record time) or blocking calls. Fixes: smaller batches, faster processing, `pause()`/`resume()` with async work, and idempotent processing.
</details>
