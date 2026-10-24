# 6.3 · Distributed Data Patterns — Transactional Outbox, Idempotent Consumers, Sagas, Idempotency Keys

> **Tags:** 🔥 must-know · ⚡ important · 🧊 deep cut
> **Sources:** Garcia-Molina & Salem, *Sagas* (SIGMOD 1987); Chris Richardson, *Microservices Patterns* (transactional outbox, saga, countermeasures for lack of isolation); IETF **draft-ietf-httpapi-idempotency-key-header-08** (22 Oct 2026, active Internet-Draft); Debezium docs (Outbox Event Router); Spring Modulith reference (Event Publication Registry); PostgreSQL docs (`SKIP LOCKED`, `ON CONFLICT`).
> **Verified stack:** Spring Boot 4.1.2 / Spring Framework 7.0.10 (`JdbcClient`, `TransactionTemplate`), PostgreSQL 18.6 (embedded), JDK 25. The broker is an in-memory list in these demos, so the failure injection is deterministic. The Kafka-specific parts are in [6.5](05-Kafka-Consumer-Groups-Rebalancing-EOS-DLQ.md).

---

## 1. The problem: one business action, two systems 🔥

A service that saves an order **and** tells the world about it writes to two systems (its database and a broker or another service) that don't share a transaction. XA/2PC is rarely available (Kafka doesn't support XA). Where it is available, it couples availability: every participant must be up, and in-doubt transactions hold locks. The realistic guarantee is:

> **at-least-once delivery + idempotent processing = effectively-once outcome.**

Every pattern in this file is a piece of that equation: the **outbox** gives atomic "state + intent" and at-least-once publishing, **idempotent consumers** absorb duplicates, **sagas** replace distributed atomicity with compensations, and **idempotency keys** extend the same idea to HTTP clients that retry.

---

## 2. Transactional outbox 🔥

```
 ┌──────────── one local DB transaction ────────────┐        relay (poll + SKIP LOCKED, or CDC on the WAL)
 │ INSERT INTO orders …                             │        ┌──────────────────────────────────────┐
 │ INSERT INTO outbox(aggregate_id, type, payload)  │ ─────► │ claim unpublished rows → send → mark │ ───► Kafka / broker
 └──────────────────────────────────────────────────┘        └──────────────────────────────────────┘
       both rows commit, or neither does                       crash after send, before mark ⇒ resend (at-least-once)
```

### 2.1 Runnable: dual writes vs outbox, a crashing relay, and an idempotent consumer

<!-- run: javac cp=@p6web timeout=200 -->
```java
package demo.outbox;

import ch.qos.logback.classic.Level;
import com.zaxxer.hikari.HikariConfig;
import com.zaxxer.hikari.HikariDataSource;
import io.zonky.test.db.postgres.embedded.EmbeddedPostgres;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicBoolean;
import org.slf4j.LoggerFactory;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.jdbc.support.JdbcTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;

public class TransactionalOutbox {
    record Message(long id, String key, String payload) { }

    static final List<Message> broker = Collections.synchronizedList(new ArrayList<>());   // stand-in for Kafka
    static JdbcClient jdbc;
    static TransactionTemplate tx;

    public static void main(String[] args) throws Exception {
        ((ch.qos.logback.classic.Logger) LoggerFactory.getLogger("ROOT")).setLevel(Level.OFF);
        try (EmbeddedPostgres pg = EmbeddedPostgres.builder().start()) {
            HikariConfig hc = new HikariConfig();
            hc.setJdbcUrl(pg.getJdbcUrl("postgres", "postgres"));
            try (HikariDataSource ds = new HikariDataSource(hc)) {
                jdbc = JdbcClient.create(ds);
                tx = new TransactionTemplate(new JdbcTransactionManager(ds));
                jdbc.sql("""
                    create table orders(id bigint primary key, customer text not null, amount numeric not null check (amount > 0));
                    create table outbox(id bigserial primary key, aggregate_id bigint not null, type text not null,
                                        payload jsonb not null, created_at timestamptz not null default now(), published_at timestamptz);
                    create index outbox_unpublished on outbox(id) where published_at is null;
                    create table processed_message(message_id bigint primary key, processed_at timestamptz default now());
                    create table loyalty_points(customer text primary key, points int not null);
                    """).update();

                // 1. the dual-write problem
                try {
                    tx.executeWithoutResult(s -> jdbc.sql("insert into orders values (100, 'ann', 10)").update());
                    throw new IllegalStateException("process killed before publish");             // crash between commit and send
                } catch (IllegalStateException e) { }
                System.out.println("1a. commit, then publish, crash in between: orders=" + count("orders where id = 100") + ", events=" + broker.size() + "  ← event lost");
                try {
                    broker.add(new Message(-1, "101", "{\"orderId\":101}"));                     // publish first…
                    tx.executeWithoutResult(s -> jdbc.sql("insert into orders values (101, 'bob', -5)").update());  // …then the DB rejects it
                } catch (Exception e) { }
                System.out.println("1b. publish, then commit fails:            orders=" + count("orders where id = 101") + ", events=" + broker.size() + "  ← ghost event");
                broker.clear();

                // 2. outbox: the order row and its event commit (or roll back) atomically
                for (long id = 1; id <= 10; id++) {
                    long orderId = id;
                    try {
                        tx.executeWithoutResult(s -> {
                            jdbc.sql("insert into orders values (?, ?, ?)").params(orderId, "c" + (orderId % 3), orderId == 7 ? -1 : orderId * 10).update();
                            jdbc.sql("insert into outbox(aggregate_id, type, payload) values (?, 'OrderPlaced', cast(? as jsonb))")
                                .params(orderId, "{\"orderId\":" + orderId + ",\"customer\":\"c" + (orderId % 3) + "\"}").update();
                        });
                    } catch (Exception e) { }                                                 // order 7 violates the check constraint
                }
                System.out.println("2. outbox: orders=" + count("orders where id <= 10") + ", outbox rows=" + count("outbox") + " (order 7 rolled back with its event)");

                // 3. relay: two workers poll with FOR UPDATE SKIP LOCKED; worker A crashes once after sending, before marking
                AtomicBoolean crashOnce = new AtomicBoolean(true);
                try (var pool = Executors.newVirtualThreadPerTaskExecutor()) {
                    Future<Integer> a = pool.submit(() -> relayLoop("A", crashOnce));
                    Future<Integer> b = pool.submit(() -> relayLoop("B", new AtomicBoolean(false)));
                    System.out.println("3. relay: 2 workers marked " + (a.get() + b.get()) + " rows published, broker received " + broker.size()
                        + " messages for " + count("outbox") + " events, unpublished left=" + count("outbox where published_at is null"));
                }

                // 4. idempotent consumer: dedupe by message id inside the consumer's own transaction
                int applied = 0, skipped = 0;
                for (Message m : List.copyOf(broker)) {
                    boolean done = Boolean.TRUE.equals(tx.execute(s -> {
                        int fresh = jdbc.sql("insert into processed_message(message_id) values (?) on conflict do nothing").param(m.id()).update();
                        if (fresh == 0) return false;                                            // duplicate delivery
                        String customer = m.payload().replaceAll(".*\"customer\": ?\"(\\w+)\".*", "$1");
                        jdbc.sql("insert into loyalty_points values (?, 1) on conflict (customer) do update set points = loyalty_points.points + 1")
                            .param(customer).update();
                        return true;
                    }));
                    if (done) applied++; else skipped++;
                }
                System.out.println("4. consumer: applied=" + applied + ", skipped duplicates=" + skipped + ", total points=" + count("loyalty_points", "sum(points)"));
            }
        }
    }

    static int relayLoop(String worker, AtomicBoolean crashOnce) {
        int sent = 0;
        while (true) {
            List<Message> batch;
            try {
                batch = tx.execute(s -> {
                    List<Message> claimed = jdbc.sql("select id, aggregate_id::text, payload::text from outbox where published_at is null order by id limit 3 for update skip locked")
                        .query((rs, i) -> new Message(rs.getLong(1), rs.getString(2), rs.getString(3))).list();
                    for (Message m : claimed) {
                        broker.add(m);                                                           // send (e.g. kafkaTemplate.send(...).get())
                        if (crashOnce.compareAndSet(true, false)) throw new IllegalStateException("relay crashed after send");
                    }
                    claimed.forEach(m -> jdbc.sql("update outbox set published_at = now() where id = ?").param(m.id()).update());
                    return claimed;
                });
            } catch (IllegalStateException crash) { continue; }                                 // the transaction rolled back: rows unclaimed again
            if (batch.isEmpty()) return sent;
            sent += batch.size();
        }
    }

    static long count(String from) { return count(from, "count(*)"); }
    static long count(String from, String expr) { return jdbc.sql("select coalesce(" + expr + ", 0) from " + from).query(Long.class).single(); }
}
```

Output (verified):

```
1a. commit, then publish, crash in between: orders=1, events=0  ← event lost
1b. publish, then commit fails:            orders=0, events=1  ← ghost event
2. outbox: orders=9, outbox rows=9 (order 7 rolled back with its event)
3. relay: 2 workers marked 9 rows published, broker received 10 messages for 9 events, unpublished left=0
4. consumer: applied=9, skipped duplicates=1, total points=9
```

1. **Dual writes fail both ways.** Commit-then-publish **loses** the event when the process dies in between (1a). Publish-then-commit emits a **ghost** event for an order that never existed (1b). Neither ordering is safe, and `@TransactionalEventListener(AFTER_COMMIT)` is still 1a.
2. **The outbox makes state and intent atomic.** Order 7 violated a constraint, and its outbox row rolled back with it: 9 orders, 9 events.
3. **The relay is at-least-once.** Two workers claimed disjoint batches with `FOR UPDATE SKIP LOCKED` (no double claiming, no waiting). Worker A "crashed" after sending but before marking, so its transaction rolled back, the rows became claimable again, and one message was **sent twice**: 10 messages for 9 events.
4. **The consumer makes it effectively-once.** It records the message ID in `processed_message` **in the same transaction as its side effect** (`ON CONFLICT DO NOTHING` returns 0 for a duplicate): 9 applied, 1 skipped, 9 points.

**Relay design choices:**

| | Polling relay (as above) | CDC (Debezium on the WAL + Outbox Event Router) |
|---|---|---|
| Latency | Poll interval (add `LISTEN/NOTIFY` to wake up) | Sub-second, push |
| Load on DB | Queries plus updates of `published_at` | Reads the WAL; no extra queries |
| Ordering | Per-aggregate order needs care (below) | WAL commit order |
| Operations | Just your app | Kafka Connect + Debezium + replication slots (monitor slot lag, or the WAL fills the disk) |

* **Ordering pitfall:** `bigserial` IDs are assigned at insert time but become visible at **commit** time, so a relay that remembers "last ID seen" can skip a row whose transaction committed late. Use a `published_at`/status flag (as above), not a high-water mark. For per-aggregate ordering, publish with `key = aggregate_id` (same Kafka partition) and avoid processing two events of the same aggregate concurrently: one relay, or partition the relay by `hash(aggregate_id)`.
* **Housekeeping:** delete or partition published rows (a monotonically growing outbox bloats indexes and slows the `where published_at is null` scan); alert on the age of the oldest unpublished row.
* **Spring options:** hand-rolled (as above), **Spring Modulith's Event Publication Registry** (persists `@ApplicationModuleListener` events in the same transaction and republishes incomplete ones), or Debezium for CDC.

---

## 3. Idempotent consumers ⚡

Every consumer of an at-least-once channel (Kafka, SQS, RabbitMQ, outbox relays, webhooks) **will** see duplicates: producer retries, relay crashes, consumer rebalances before an offset commit ([6.5](05-Kafka-Consumer-Groups-Rebalancing-EOS-DLQ.md)). Options, best first:

1. **Naturally idempotent effects:** `UPSERT` to a final state, `set status = 'SHIPPED'`, or conditional updates (`where version = ?`).
2. **A dedup table in the same transaction as the effect** (§2.1 step 4). Keep it bounded with a time-based purge longer than the maximum redelivery window.
3. **Idempotency keys passed downstream** (payment providers dedupe on them).

A Kafka **idempotent producer** (`enable.idempotence=true`) only removes duplicates caused by producer retries **within one producer session**. It does nothing for relay crashes or consumer replays.

---

## 4. Sagas 🔥

A saga is a sequence of local transactions T₁…Tₙ, each with a **compensating transaction** Cᵢ that semantically undoes it. If Tₖ fails, run Cₖ₋₁…C₁. Compensation is a *business* action (refund, release stock, cancel booking), not a rollback, and it must be **idempotent and retryable**, because it can't be allowed to fail permanently.

| | Choreography | Orchestration |
|---|---|---|
| Control | Each service reacts to events and emits the next event | A central orchestrator (state machine) sends commands and awaits replies |
| Coupling | Services know each other's events; the flow is implicit | Services know only commands; the flow is explicit in one place |
| Visibility, debugging | Hard: reconstruct the flow from logs and traces | Easy: the saga state is a row you can query |
| Best for | 2–3 steps, stable flows | Many steps, branching, timeouts, human tasks |
| Tools | Kafka + outbox | Hand-rolled (below), Temporal, Camunda/Zeebe, AWS Step Functions |

### 4.1 Runnable: an orchestrated order saga with persisted state, compensations and crash recovery

<!-- run: javac cp=@p6web timeout=200 -->
```java
package demo.saga;

import ch.qos.logback.classic.Level;
import com.zaxxer.hikari.HikariConfig;
import com.zaxxer.hikari.HikariDataSource;
import io.zonky.test.db.postgres.embedded.EmbeddedPostgres;
import java.util.*;
import java.util.concurrent.ConcurrentHashMap;
import org.slf4j.LoggerFactory;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.jdbc.support.JdbcTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;

public class OrchestratedSaga {
    enum State { STARTED, INVENTORY_RESERVED, PAYMENT_CHARGED, COMPLETED, COMPENSATING, COMPENSATED }

    // Participants: every operation is idempotent per saga id, because the orchestrator may repeat it after a crash
    static class Inventory {
        final Map<String, Integer> reserved = new ConcurrentHashMap<>();
        void reserve(String saga, int qty) { reserved.putIfAbsent(saga, qty); }
        void release(String saga) { reserved.remove(saga); }
    }
    static class Payments {
        final Map<String, Integer> charges = new ConcurrentHashMap<>();
        int calls;
        void charge(String saga, int amount) {
            calls++;
            if (amount > 500) throw new IllegalStateException("card declined");
            charges.putIfAbsent(saga, amount);                         // second call for the same saga = no-op
        }
        void refund(String saga) { charges.remove(saga); }
    }
    static class Shipping {
        void schedule(String saga, String address) { if (address.contains("Atlantis")) throw new IllegalStateException("no carrier"); }
    }

    static JdbcClient jdbc; static TransactionTemplate tx;
    static final Inventory inventory = new Inventory(); static final Payments payments = new Payments(); static final Shipping shipping = new Shipping();
    static final Set<String> crashAfterChargeOnce = new HashSet<>(Set.of("saga-4"));

    static void run(String saga) {
        while (true) {
            var row = jdbc.sql("select state, amount, address from saga where id = ?").param(saga)
                .query((rs, i) -> new Object[] {State.valueOf(rs.getString(1)), rs.getInt(2), rs.getString(3)}).single();
            State state = (State) row[0]; int amount = (int) row[1]; String address = (String) row[2];
            switch (state) {
                case STARTED -> { inventory.reserve(saga, 1); advance(saga, state, State.INVENTORY_RESERVED, "reserve inventory"); }
                case INVENTORY_RESERVED -> {
                    try { payments.charge(saga, amount); }
                    catch (IllegalStateException e) { advance(saga, state, State.COMPENSATING, "payment failed: " + e.getMessage()); continue; }
                    if (crashAfterChargeOnce.remove(saga)) throw new IllegalStateException("orchestrator crashed");   // before the state was saved
                    advance(saga, state, State.PAYMENT_CHARGED, "charge " + amount);
                }
                case PAYMENT_CHARGED -> {
                    try { shipping.schedule(saga, address); advance(saga, state, State.COMPLETED, "schedule shipping"); }
                    catch (IllegalStateException e) { advance(saga, state, State.COMPENSATING, "shipping failed: " + e.getMessage()); }
                }
                case COMPENSATING -> {                                     // undo completed steps in reverse order
                    List<String> done = jdbc.sql("select step from saga_log where saga_id = ? order by seq").param(saga).query(String.class).list();
                    if (done.stream().anyMatch(s -> s.startsWith("charge ")))  { payments.refund(saga);  log(saga, "compensate: refund"); }
                    if (done.contains("reserve inventory"))                     { inventory.release(saga); log(saga, "compensate: release inventory"); }
                    advance(saga, state, State.COMPENSATED, "compensated");
                }
                case COMPLETED, COMPENSATED -> { return; }
            }
        }
    }

    static void advance(String saga, State from, State to, String step) {
        tx.executeWithoutResult(s -> {
            int updated = jdbc.sql("update saga set state = ? where id = ? and state = ?").params(to.name(), saga, from.name()).update();
            if (updated != 1) throw new IllegalStateException("concurrent modification of " + saga);   // optimistic guard
            log(saga, step);
        });
    }
    static void log(String saga, String step) { jdbc.sql("insert into saga_log(saga_id, step) values (?, ?)").params(saga, step).update(); }

    public static void main(String[] args) throws Exception {
        ((ch.qos.logback.classic.Logger) LoggerFactory.getLogger("ROOT")).setLevel(Level.OFF);
        try (EmbeddedPostgres pg = EmbeddedPostgres.builder().start()) {
            HikariConfig hc = new HikariConfig();
            hc.setJdbcUrl(pg.getJdbcUrl("postgres", "postgres"));
            try (HikariDataSource ds = new HikariDataSource(hc)) {
                jdbc = JdbcClient.create(ds);
                tx = new TransactionTemplate(new JdbcTransactionManager(ds));
                jdbc.sql("""
                    create table saga(id text primary key, state text not null, amount int not null, address text not null);
                    create table saga_log(seq bigserial primary key, saga_id text not null, step text not null);
                    """).update();
                Object[][] orders = {{"saga-1", 120, "Main St 1"}, {"saga-2", 900, "Main St 2"}, {"saga-3", 80, "Atlantis 7"}, {"saga-4", 60, "Main St 4"}};
                for (Object[] o : orders) jdbc.sql("insert into saga values (?, 'STARTED', ?, ?)").params(o[0], o[1], o[2]).update();

                for (Object[] o : orders) {
                    try { run((String) o[0]); } catch (IllegalStateException crash) { System.out.println(o[0] + ": " + crash.getMessage() + " — will be recovered"); }
                }
                // recovery job: resume every non-terminal saga from its persisted state
                jdbc.sql("select id from saga where state not in ('COMPLETED', 'COMPENSATED') order by id").query(String.class).list()
                    .forEach(saga -> { System.out.println("recovering " + saga); run(saga); });

                for (Object[] o : orders) {
                    String saga = (String) o[0];
                    System.out.printf("%s %-11s %s%n", saga, jdbc.sql("select state from saga where id = ?").param(saga).query(String.class).single(),
                        jdbc.sql("select step from saga_log where saga_id = ? order by seq").param(saga).query(String.class).list());
                }
                System.out.println("inventory reserved=" + new TreeMap<>(inventory.reserved) + " | charges=" + new TreeMap<>(payments.charges)
                    + " | payment calls=" + payments.calls);
            }
        }
    }
}
```

Output (verified):

```
saga-4: orchestrator crashed — will be recovered
recovering saga-4
saga-1 COMPLETED   [reserve inventory, charge 120, schedule shipping]
saga-2 COMPENSATED [reserve inventory, payment failed: card declined, compensate: release inventory, compensated]
saga-3 COMPENSATED [reserve inventory, charge 80, shipping failed: no carrier, compensate: refund, compensate: release inventory, compensated]
saga-4 COMPLETED   [reserve inventory, charge 60, schedule shipping]
inventory reserved={saga-1=1, saga-4=1} | charges={saga-1=120, saga-4=60} | payment calls=5
```

* **saga-1** is the happy path. **saga-2**: payment declined, so only the inventory reservation is compensated (the log decides which steps completed). **saga-3**: shipping failed **after** the charge, so it refunds, then releases, in reverse order.
* **saga-4** shows why the state must be persisted and participants must be idempotent. The orchestrator crashed after the payment provider accepted the charge but **before** saving `PAYMENT_CHARGED`. Recovery resumed from `INVENTORY_RESERVED` and charged **again** (5 payment calls in total). Because `charge` is idempotent per saga ID, there is exactly one charge of 60. With a non-idempotent payment API this is a double charge, so pass the saga ID as the provider's idempotency key.
* **The state update is guarded** (`update … where state = ?` must affect 1 row), so two orchestrator instances can't advance the same saga concurrently.
* **Sagas aren't isolated** (ACD without the I). Other transactions see intermediate states (stock reserved, payment pending). Countermeasures: *semantic locks* (`PENDING` status that other operations respect), *commutative updates* (increments instead of overwrites), *re-reading values* before the pivot step, and ordering steps so that the **pivot transaction** (the point of no return, here the charge) comes after the steps that are likely to fail.

---

## 5. Idempotency keys for HTTP APIs 🔥

Clients retry: timeouts, mobile networks, load balancers that retry on connection reset. For non-idempotent operations (`POST /payments`) the server needs a client-supplied key. The IETF draft (`Idempotency-Key` header, draft-08) specifies:

* **`400`** when a required key is missing;
* **`409 Conflict`** while the original request with that key is still in progress;
* **`422 Unprocessable Content`** when the key is reused with a different payload (detected via a request fingerprint);
* an **expiry policy** the server should document.

### 5.1 Runnable: a Boot endpoint hammered by a retrying client

<!-- run: javac cp=@p6web timeout=200 -->
```java
package demo.idempotency;

import io.zonky.test.db.postgres.embedded.EmbeddedPostgres;
import java.net.URI;
import java.net.http.*;
import java.security.MessageDigest;
import java.util.*;
import java.util.concurrent.*;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.SpringBootConfiguration;
import org.springframework.boot.autoconfigure.EnableAutoConfiguration;
import org.springframework.boot.web.server.context.WebServerApplicationContext;
import org.springframework.context.annotation.Import;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.transaction.support.TransactionTemplate;
import org.springframework.web.bind.annotation.*;

public class IdempotencyKeys {
    @RestController
    public static class PaymentController {
        final JdbcClient jdbc; final TransactionTemplate tx;
        public PaymentController(JdbcClient jdbc, TransactionTemplate tx) { this.jdbc = jdbc; this.tx = tx; }

        @PostMapping("/payments")
        public ResponseEntity<String> pay(@RequestHeader(value = "Idempotency-Key", required = false) String key,
                                          @RequestBody String body) throws Exception {
            if (key == null) return ResponseEntity.badRequest().body("{\"error\":\"Idempotency-Key header required\"}");
            String fingerprint = HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(body.getBytes()));
            int claimed = jdbc.sql("insert into idempotency_key(key, fingerprint, status) values (?, ?, 'IN_PROGRESS') on conflict do nothing")
                .params(key, fingerprint).update();                                    // auto-commit: visible to concurrent requests at once
            if (claimed == 0) {
                var row = jdbc.sql("select fingerprint, status, response_code, response_body from idempotency_key where key = ?").param(key)
                    .query((rs, i) -> new String[] {rs.getString(1), rs.getString(2), rs.getString(3), rs.getString(4)}).single();
                if (!row[0].equals(fingerprint)) return ResponseEntity.unprocessableContent().body("{\"error\":\"key reused with a different payload\"}");
                if (row[1].equals("IN_PROGRESS")) return ResponseEntity.status(409).header("Retry-After", "1").body("{\"error\":\"request in progress\"}");
                return ResponseEntity.status(Integer.parseInt(row[2])).header("Idempotent-Replayed", "true").body(row[3]);
            }
            try {
                Thread.sleep(200);                                                     // the call to the payment provider
                String response = tx.execute(s -> {                                 // effect + stored response commit together
                    long paymentId = jdbc.sql("insert into payment(idempotency_key, body) values (?, ?) returning id").params(key, body).query(Long.class).single();
                    String r = "{\"paymentId\":" + paymentId + "}";
                    jdbc.sql("update idempotency_key set status = 'COMPLETED', response_code = 201, response_body = ? where key = ?").params(r, key).update();
                    return r;
                });
                return ResponseEntity.status(201).body(response);
            } catch (Exception e) {
                jdbc.sql("delete from idempotency_key where key = ?").param(key).update();   // let the client retry
                throw e;
            }
        }
    }
    @SpringBootConfiguration @EnableAutoConfiguration @Import(PaymentController.class) static class App { }

    public static void main(String[] args) throws Exception {
        ((ch.qos.logback.classic.Logger) org.slf4j.LoggerFactory.getLogger("ROOT")).setLevel(ch.qos.logback.classic.Level.OFF);
        try (EmbeddedPostgres pg = EmbeddedPostgres.builder().start()) {
            SpringApplication sa = new SpringApplication(App.class);
            sa.setBannerMode(org.springframework.boot.Banner.Mode.OFF);
            sa.setDefaultProperties(Map.of("server.port", "0", "logging.level.root", "OFF", "spring.threads.virtual.enabled", "true",
                "spring.datasource.url", pg.getJdbcUrl("postgres", "postgres")));
            try (var ctx = sa.run(); HttpClient http = HttpClient.newHttpClient()) {
                JdbcClient jdbc = ctx.getBean(JdbcClient.class);
                jdbc.sql("""
                    create table idempotency_key(key text primary key, fingerprint text not null, status text not null,
                                                 response_code int, response_body text, created_at timestamptz default now());
                    create table payment(id bigserial primary key, idempotency_key text not null unique, body text not null);
                    """).update();
                URI uri = URI.create("http://localhost:" + ((WebServerApplicationContext) ctx).getWebServer().getPort() + "/payments");

                List<Integer> statuses = new CopyOnWriteArrayList<>();
                try (var clients = Executors.newVirtualThreadPerTaskExecutor()) {               // a client retrying aggressively
                    for (int i = 0; i < 10; i++) clients.submit(() -> statuses.add(post(http, uri, "key-A", "{\"amount\":42}").statusCode()));
                }
                Map<Integer, Long> byStatus = new TreeMap<>();
                statuses.forEach(s -> byStatus.merge(s, 1L, Long::sum));
                System.out.println("1. 10 concurrent POSTs, same key: status counts " + byStatus);

                HttpResponse<String> retry = post(http, uri, "key-A", "{\"amount\":42}");
                System.out.println("2. retry after completion: " + retry.statusCode() + " " + retry.body()
                    + " Idempotent-Replayed=" + retry.headers().firstValue("Idempotent-Replayed").orElse("-"));
                System.out.println("3. same key, different amount: " + post(http, uri, "key-A", "{\"amount\":99}").statusCode());
                System.out.println("4. no key: " + post(http, uri, null, "{\"amount\":42}").statusCode());
                System.out.println("5. payments actually executed for key-A: "
                    + jdbc.sql("select count(*) from payment where idempotency_key = 'key-A'").query(Long.class).single());
            }
        }
    }

    static HttpResponse<String> post(HttpClient http, URI uri, String key, String body) throws Exception {
        var b = HttpRequest.newBuilder(uri).header("Content-Type", "application/json").POST(HttpRequest.BodyPublishers.ofString(body));
        if (key != null) b.header("Idempotency-Key", key);
        return http.send(b.build(), HttpResponse.BodyHandlers.ofString());
    }
}
```

One verified run (how the 10 concurrent requests split between `409` and a replayed `201` depends on timing; everything else is deterministic):

```
1. 10 concurrent POSTs, same key: status counts {201=1, 409=9}
2. retry after completion: 201 {"paymentId":1} Idempotent-Replayed=true
3. same key, different amount: 422
4. no key: 400
5. payments actually executed for key-A: 1
```

Design rules the code follows:

1. **Claim first, atomically:** `INSERT … ON CONFLICT DO NOTHING` in its own auto-commit statement, so concurrent duplicates see the claim immediately. A "select, then insert" check races.
2. **Fingerprint the payload** (SHA-256 of the body) to detect key reuse with different content: `422`.
3. **Commit the effect and the stored response in one transaction**, so a crash can't leave "payment done, key still `IN_PROGRESS`". If the effect is remote (a payment provider), forward the key to it, and add a **lease** (`locked_until`) so stuck `IN_PROGRESS` rows can be retried after a crash.
4. **Replay the original response** (status and body), marked with a header, for completed keys.
5. **Scope and expire keys**: per client or tenant (`unique (client_id, key)`), purged after the documented window.

---

## 6. Production failure modes & diagnostics

| Symptom | Cause | Confirm with | Fix |
|---|---|---|---|
| Downstream missing events after deploys or crashes | Dual write (publish after commit) | Compare entity counts with event counts | Outbox / CDC |
| Events for data that doesn't exist | Publish before commit; publishing inside a transaction that later rolls back | Consumer errors "not found" | Outbox |
| Duplicated side effects (double emails, double charges) | At-least-once delivery without idempotent consumers | Duplicate message IDs in consumer logs | Dedup table in the same transaction; idempotent operations; idempotency keys downstream |
| Outbox lag grows | Relay down or slow, poison event, lock contention | Age of the oldest unpublished row; relay error logs | Alert on age; DLQ for poison events; scale with `SKIP LOCKED` |
| Events out of order for one entity | Parallel relays or consumers for the same aggregate; high-water-mark relay skipping late commits | Event sequence numbers per aggregate | Key by aggregate; status flag instead of max-ID; versions in events |
| Saga stuck in an intermediate state | Orchestrator crashed; participant down; no timeout | Query saga rows by state and age | Recovery job; timeouts per step; alerting on stuck sagas |
| Compensation failed, data inconsistent | Non-idempotent or failing compensation | Saga log | Retry compensations until they succeed; manual-intervention queue |
| Clients get `409` storms | Aggressive client retries without back-off | Access logs: same key, many `409`s | `Retry-After`, client back-off with jitter |
| WAL disk full on the DB | CDC replication slot not consumed | `pg_replication_slots` (`restart_lsn` lag) | Monitor slot lag; drop abandoned slots |

---

## 7. Interview Q&A

<details><summary><b>Q1. 🔥 What is the dual-write problem, and how does the transactional outbox solve it?</b></summary>

Writing to a database and a broker in two steps can't be atomic: commit-then-publish loses events on a crash, and publish-then-commit emits events for rolled-back data (both reproduced). The outbox writes the event into an `outbox` table in the **same local transaction** as the state change, and a relay (polling with `SKIP LOCKED`, or CDC) publishes it afterwards. That is atomic state + intent, and at-least-once publication, so consumers must be idempotent.
</details>

<details><summary><b>Q2. ⚡ Why must outbox consumers be idempotent even if the producer uses Kafka's idempotent producer?</b></summary>

The idempotent producer only dedupes retries of the same send within one producer session. Duplicates also come from a relay crashing after sending but before marking the row (reproduced: 10 messages for 9 events), from consumer rebalances before an offset commit, and from replays. Consumers dedupe by message or business ID in the same transaction as their effect, or make the effect naturally idempotent.
</details>

<details><summary><b>Q3. 🔥 Choreography vs orchestration for sagas: how do you choose?</b></summary>

Choreography (services react to each other's events) is simple for a few steps but makes the flow implicit and hard to observe or change. Orchestration puts the flow in one state machine that sends commands and records state, which helps with many steps, branching, timeouts and visibility. Either way: persist saga state, make every step and compensation idempotent, use timeouts, and handle the lack of isolation (semantic locks, commutative updates, pivot ordering).
</details>

<details><summary><b>Q4. ⚡ An orchestrator crashes right after calling the payment service but before saving its state. What happens on recovery, and how do you make it safe?</b></summary>

Recovery resumes from the last persisted state and calls the payment step again (reproduced: 5 payment calls for 4 sagas). It is safe only if the call is idempotent, by passing the saga ID as the idempotency key so the provider returns the original result instead of charging twice. Guard state transitions with a compare-and-set (`where state = ?`) so concurrent orchestrators can't both advance a saga.
</details>

<details><summary><b>Q5. 🔥 Design idempotency keys for `POST /payments`.</b></summary>

The client sends `Idempotency-Key`. The server atomically claims the key (`INSERT … ON CONFLICT DO NOTHING`) with a payload fingerprint and an `IN_PROGRESS` status. Duplicates get `409` while in progress, `422` if the fingerprint differs, and the stored response (replayed) once completed. A missing key gets `400` (IETF draft-08 semantics, all reproduced). Commit the effect and the stored response atomically; forward the key to external providers; use leases for crash recovery; scope keys per client and expire them on a documented schedule.
</details>

<details><summary><b>Q6. 🧊 Why can an outbox relay that tracks "the highest ID published so far" lose events?</b></summary>

Sequence values are assigned when rows are inserted, but rows become visible when their transactions commit. A transaction that took ID 41 may commit after one that took ID 42. A relay that has already moved its high-water mark past 42 never sees 41. Track publication per row (a status or `published_at` column, claimed with `SKIP LOCKED`), or use CDC, which follows commit order in the WAL.
</details>
