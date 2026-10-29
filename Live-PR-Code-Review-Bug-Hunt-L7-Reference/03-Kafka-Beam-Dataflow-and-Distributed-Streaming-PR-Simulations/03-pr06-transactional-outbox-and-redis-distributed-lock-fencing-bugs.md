# PR06 · Transactional Outbox and Redis Distributed-Lock Fencing Bugs

> **What this module is.** A PR that does the textbook-right thing, "replace the dual write with a transactional outbox," and gets nearly every detail of it wrong. It hides **7 defects (4 Sev-1)** across the outbox write, the relay's cursor, the async producer, the event contract and a Redis lock that the design leans on for correctness it cannot provide. The lesson for L7 reviewers: *naming the right pattern is not the same as implementing it*. The fix moves correctness out of the lock and into the database.

| Artifact | What it is | Verified |
|---|---|---|
| `pr06-diff` | `ShipmentService` changed; `Outbox`, `OutboxRelay`, `RedisLock` new; schema migration; new test class: 225 diff lines | `git diff --no-index` from compiled sources |
| `OutboxTest` (author's) | 3 tests: create writes both rows, relay publishes in order once, only one relay at a time | **3/3 pass** on the PR (§4) |
| `Pr06Probes` | 6 probes: failed create, commits out of id order, broker outage, consumer view, relay stalled past its lease, stale lock release | each shows the defect on the PR and its absence on the fix (§8) |
| Fixed code | One transaction for shipment + outbox row; `FOR UPDATE SKIP LOCKED` batches; broker acks awaited before marking published; event id in every message; compare-and-delete release | fixed suite 5/5; PR's own tests against the fix 2/3 (the failing test asserts messages *without* an event id) |

**Verification.** PostgreSQL 18.6 (embedded), Spring JDBC 7.0.10 (`JdbcTemplate`, `TransactionTemplate`), JDK 25.0.4.1 with `javac --release 21 -Xlint:all,-path,-classfile -Werror`, JUnit Platform 1.13.4. Redis is a single-node double implementing `SET NX PX` with real expiry, `DEL`, the compare-and-delete script, and `INCR`. Out-of-order commits use two real PostgreSQL transactions. P5 and P6 use wall-clock stalls against 200–300 ms leases and are labeled "one measured run."

---

## 0. Orientation

### 0.1 What this PR tests

| Layer | Defects | Why reviewers miss them |
|---|---|---|
| L3 Failure paths | F1 outbox row written outside the business transaction (phantom events), F3 cursor advanced before broker acks | "Outbox" in the PR title earns trust |
| L2 Concurrency | F2 `id > cursor` skips rows committed out of id order, F5 lease shorter than the work, F6 release deletes another holder's lock, F7 cursor written without a fencing token | Each is invisible with one relay and fast commits |
| L5 Contract | F4 messages carry no event id, so at-least-once redeliveries can't be de-duplicated | The relay's guarantee is never stated |

### 0.2 Habits this PR punishes

| Habit | What happens here |
|---|---|
| "Write the event first so it can't be lost." | You now announce shipments that never existed. |
| "Bigserial ids are monotonic, so a cursor works." | Monotonic at *assignment*, not at *commit*. |
| "The producer is async, so the relay is fast." | And the cursor moves before the broker said yes. |
| "Only one relay holds the lock." | Until a GC pause outlives the lease. |
| "Release the lock in finally." | With `DEL`, you can release someone else's lock. |

---

## 1. First principles

1. **The outbox works only if the event row commits atomically with the state it describes.** Same transaction, same connection. Any other ordering re-creates the dual write: event without state (phantom), or state without event (lost).
2. **Sequence order ≠ commit order.** A `BIGSERIAL` value is assigned when the row is inserted. Transactions commit whenever they finish. So a reader that has seen id 42 may later see id 41 appear. PostgreSQL's own docs warn that sequences "cannot be used to obtain 'gapless' sequences," and a cursor of the form `WHERE id > :last` turns that gap into permanent loss. The probe shows it with two real transactions.
3. **A send isn't a delivery until it's acknowledged.** `KafkaProducer.send` returns a future. State that means "published" may only advance after the future completes successfully.
4. **The outbox relay is at-least-once.** A crash between publishing and marking guarantees redelivery, so every message needs a stable id (the outbox row id) for consumers to de-duplicate.
5. **A lease-based lock is not mutual exclusion under pauses.** Kleppmann: if a "GC pause lasts longer than the lease expiry period, and the client doesn't realise that it has expired," two clients act at once. The protected resource must reject stale holders: "a fencing token is simply a number that increases."
6. **Releasing a Redis lock requires proving ownership.** Redis's distributed-lock docs: "Using just DEL is not safe as a client may remove another client's lock." Release with the compare-and-delete script (or `DELEX … IFEQ` on Redis 8.4+).
7. **The best fencing is the database you already write to.** Row locks (`SELECT … FOR UPDATE SKIP LOCKED`) plus per-row state (`published_at`) give each row exactly one owner at a time, and make the Redis lock unnecessary for correctness.

---

## 2. The PR

> **SHIP-640 · Transactional outbox for ShipmentCreated**
>
> The warehouse sometimes never hears about a shipment: `ShipmentService` commits the shipment and then publishes to Kafka, and pods are killed in between. Fix it with a transactional outbox.
>
> **PR description, by the author:**
> - `Outbox.append` records `ShipmentCreated`, *before* the shipment insert, "so the event can never be lost."
> - `OutboxRelay` polls `outbox WHERE id > cursor ORDER BY id LIMIT 500`, publishes, advances `relay_cursor`.
> - Publishing is async (the producer returns a future), which keeps the relay fast.
> - A Redis lock (`SET NX PX`, 10 s lease) ensures only one relay instance runs at a time across the 6 pods; released in `finally`.
> - Migration: `outbox` and `relay_cursor` tables.
> - Tests: both rows written, publish in order once, second instance skips while the lock is held. All green.
>
> **Context the reviewer can discover:** shipment creates fail with unique-constraint violations a few hundred times a day (duplicate tracking numbers from carriers). Peak write rate is 400 shipments/s, so concurrent transactions are the norm. Kafka brokers reject sends during partition-leader elections (`NOT_ENOUGH_REPLICAS`). JVM GC pauses of 1–3 s happen under memory pressure. The warehouse consumer is at-least-once and can de-duplicate by a key, if given one. One order can have several shipments.

---

## 3. The diff

```diff
diff --git a/shipping-service/src/main/java/com/acme/shipping/Outbox.java b/shipping-service/src/main/java/com/acme/shipping/Outbox.java
new file mode 100644
index 0000000..0f24fb4
--- /dev/null
+++ b/shipping-service/src/main/java/com/acme/shipping/Outbox.java
@@ -0,0 +1,16 @@
+package com.acme.shipping;
+
+import org.springframework.jdbc.core.JdbcTemplate;
+
+/** Appends events to the outbox table; OutboxRelay publishes them. */
+public final class Outbox {
+    private final JdbcTemplate jdbc;
+
+    public Outbox(JdbcTemplate jdbc) {
+        this.jdbc = jdbc;
+    }
+
+    public void append(String type, String payload) {
+        jdbc.update("INSERT INTO outbox (type, payload) VALUES (?, ?)", type, payload);
+    }
+}
diff --git a/shipping-service/src/main/java/com/acme/shipping/OutboxRelay.java b/shipping-service/src/main/java/com/acme/shipping/OutboxRelay.java
new file mode 100644
index 0000000..601f4b0
--- /dev/null
+++ b/shipping-service/src/main/java/com/acme/shipping/OutboxRelay.java
@@ -0,0 +1,46 @@
+package com.acme.shipping;
+
+import java.time.Duration;
+import java.util.List;
+import java.util.Map;
+import org.springframework.jdbc.core.JdbcTemplate;
+
+/** Publishes outbox rows to shipments.events in id order. One relay at a time across the fleet (Redis lock). */
+public final class OutboxRelay {
+    private static final String LOCK = "lock:outbox-relay";
+
+    private final JdbcTemplate jdbc;
+    private final EventPublisher publisher;
+    private final RedisLock lock;
+    private final String instanceId;
+    private final Duration lease;
+
+    public OutboxRelay(JdbcTemplate jdbc, EventPublisher publisher, RedisClient redis, String instanceId, Duration lease) {
+        this.jdbc = jdbc;
+        this.publisher = publisher;
+        this.lock = new RedisLock(redis);
+        this.instanceId = instanceId;
+        this.lease = lease;
+    }
+
+    /** One polling round; returns how many events were published. */
+    public int runOnce() {
+        if (!lock.tryAcquire(LOCK, instanceId, lease)) {
+            return 0; // another instance is relaying
+        }
+        try {
+            Long last = jdbc.queryForObject("SELECT last_id FROM relay_cursor WHERE name = 'outbox'", Long.class);
+            List<Map<String, Object>> rows = jdbc.queryForList(
+                    "SELECT id, type, payload FROM outbox WHERE id > ? ORDER BY id LIMIT 500", last);
+            for (Map<String, Object> r : rows) {
+                publisher.publish((String) r.get("type"), (String) r.get("payload")); // async: keeps the relay fast
+            }
+            if (!rows.isEmpty()) {
+                jdbc.update("UPDATE relay_cursor SET last_id = ? WHERE name = 'outbox'", rows.get(rows.size() - 1).get("id"));
+            }
+            return rows.size();
+        } finally {
+            lock.release(LOCK);
+        }
+    }
+}
diff --git a/shipping-service/src/main/java/com/acme/shipping/RedisLock.java b/shipping-service/src/main/java/com/acme/shipping/RedisLock.java
new file mode 100644
index 0000000..32465ab
--- /dev/null
+++ b/shipping-service/src/main/java/com/acme/shipping/RedisLock.java
@@ -0,0 +1,20 @@
+package com.acme.shipping;
+
+import java.time.Duration;
+
+/** Fleet-wide mutual exclusion on Redis: SET NX PX to acquire, DEL to release. */
+public final class RedisLock {
+    private final RedisClient redis;
+
+    public RedisLock(RedisClient redis) {
+        this.redis = redis;
+    }
+
+    public boolean tryAcquire(String key, String owner, Duration lease) {
+        return redis.setIfAbsent(key, owner, lease.toMillis());
+    }
+
+    public void release(String key) {
+        redis.delete(key);
+    }
+}
diff --git a/shipping-service/src/main/java/com/acme/shipping/ShipmentService.java b/shipping-service/src/main/java/com/acme/shipping/ShipmentService.java
index 3d6a753..9ca791d 100644
--- a/shipping-service/src/main/java/com/acme/shipping/ShipmentService.java
+++ b/shipping-service/src/main/java/com/acme/shipping/ShipmentService.java
@@ -3,22 +3,22 @@ package com.acme.shipping;
 import org.springframework.jdbc.core.JdbcTemplate;
 import org.springframework.transaction.support.TransactionTemplate;
 
-/** Creates shipments and announces them to the warehouse (ShipmentCreated on shipments.events). */
+/** Creates shipments. ShipmentCreated now goes through the transactional outbox (published by OutboxRelay). */
 public final class ShipmentService {
     private final JdbcTemplate jdbc;
     private final TransactionTemplate tx;
-    private final EventPublisher publisher;
+    private final Outbox outbox;
 
-    public ShipmentService(JdbcTemplate jdbc, TransactionTemplate tx, EventPublisher publisher) {
+    public ShipmentService(JdbcTemplate jdbc, TransactionTemplate tx, Outbox outbox) {
         this.jdbc = jdbc;
         this.tx = tx;
-        this.publisher = publisher;
+        this.outbox = outbox;
     }
 
     public long create(String orderId, String trackingNo) {
+        outbox.append("ShipmentCreated", orderId + "," + trackingNo); // recorded first, so the event can never be lost
         Long id = tx.execute(s -> jdbc.queryForObject(
                 "INSERT INTO shipments (order_id, tracking_no) VALUES (?, ?) RETURNING id", Long.class, orderId, trackingNo));
-        publisher.publish("ShipmentCreated", orderId + "," + trackingNo).join(); // after commit; lost if we crash here
         return id == null ? 0 : id;
     }
 }
diff --git a/shipping-service/src/main/java/schema.sql b/shipping-service/src/main/java/schema.sql
index eb5b617..36e0ed8 100644
--- a/shipping-service/src/main/java/schema.sql
+++ b/shipping-service/src/main/java/schema.sql
@@ -3,3 +3,14 @@ CREATE TABLE shipments (
     order_id    TEXT NOT NULL,
     tracking_no TEXT NOT NULL UNIQUE
 );
+CREATE TABLE outbox (
+    id         BIGSERIAL PRIMARY KEY,
+    type       TEXT NOT NULL,
+    payload    TEXT NOT NULL,
+    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
+);
+CREATE TABLE relay_cursor (
+    name    TEXT PRIMARY KEY,
+    last_id BIGINT NOT NULL
+);
+INSERT INTO relay_cursor VALUES ('outbox', 0);
diff --git a/shipping-service/src/test/java/com/acme/shipping/OutboxTest.java b/shipping-service/src/test/java/com/acme/shipping/OutboxTest.java
new file mode 100644
index 0000000..43e46e0
--- /dev/null
+++ b/shipping-service/src/test/java/com/acme/shipping/OutboxTest.java
@@ -0,0 +1,46 @@
+package com.acme.shipping;
+
+import static org.junit.jupiter.api.Assertions.assertEquals;
+
+import java.time.Duration;
+import java.util.List;
+import org.junit.jupiter.api.BeforeEach;
+import org.junit.jupiter.api.Test;
+
+class OutboxTest {
+    private final FakeRedis redis = new FakeRedis();
+    private final ShipmentService shipments = new ShipmentService(Db.jdbc(), Db.tx(), new Outbox(Db.jdbc()));
+
+    @BeforeEach
+    void reset() {
+        Db.reset();
+        FakePublisher.BROKER.clear();
+    }
+
+    private OutboxRelay relay(String instance) {
+        return new OutboxRelay(Db.jdbc(), new FakePublisher(), redis, instance, Duration.ofSeconds(10));
+    }
+
+    @Test
+    void createWritesShipmentAndOutboxRow() {
+        shipments.create("o1", "TRK1");
+        assertEquals(1, Db.count("SELECT count(*) FROM shipments"));
+        assertEquals(1, Db.count("SELECT count(*) FROM outbox"));
+    }
+
+    @Test
+    void relayPublishesInOrderOnce() {
+        shipments.create("o1", "TRK1");
+        shipments.create("o2", "TRK2");
+        assertEquals(2, relay("a").runOnce());
+        assertEquals(0, relay("a").runOnce());
+        assertEquals(List.of("ShipmentCreated:o1,TRK1", "ShipmentCreated:o2,TRK2"), FakePublisher.BROKER);
+    }
+
+    @Test
+    void onlyOneRelayAtATime() {
+        shipments.create("o1", "TRK1");
+        redis.setIfAbsent("lock:outbox-relay", "b", 10_000); // instance b is relaying
+        assertEquals(0, relay("a").runOnce());
+    }
+}
diff --git a/shipping-service/src/test/java/com/acme/shipping/ShipmentServiceTest.java b/shipping-service/src/test/java/com/acme/shipping/ShipmentServiceTest.java
deleted file mode 100644
index 76dda92..0000000
--- a/shipping-service/src/test/java/com/acme/shipping/ShipmentServiceTest.java
+++ /dev/null
@@ -1,16 +0,0 @@
-package com.acme.shipping;
-
-import static org.junit.jupiter.api.Assertions.assertEquals;
-
-import java.util.List;
-import org.junit.jupiter.api.Test;
-
-class ShipmentServiceTest {
-    @Test
-    void createsAndAnnounces() {
-        Db.reset();
-        FakePublisher.BROKER.clear();
-        new ShipmentService(Db.jdbc(), Db.tx(), new FakePublisher()).create("o1", "TRK1");
-        assertEquals(List.of("ShipmentCreated:o1,TRK1"), FakePublisher.BROKER);
-    }
-}
```

---

## 4. The author's tests: green

```text
├─ JUnit Jupiter ✔
│  └─ OutboxTest ✔
│     ├─ onlyOneRelayAtATime() ✔
│     ├─ relayPublishesInOrderOnce() ✔
│     └─ createWritesShipmentAndOutboxRow() ✔
[         3 tests found           ]
[         3 tests successful      ]
[         0 tests failed          ]
```

Every create succeeds, so no phantom. Every insert commits before the relay runs, so there are no out-of-order commits. The broker never fails. One relay runs at a time with no pauses. `relayPublishesInOrderOnce` asserts the exact message text, *without* an event id, and is the one test that fails against the fix.

---

## 5. The timed 3-pass diagnostic guide

### Minute 2: map and triage

- **Contracts changed:** the atomicity of "shipment + event," the relay's delivery guarantee (at-least-once? exactly-once? in order?), the event's identity, and a cross-pod mutual-exclusion claim.
- **Hunk scores:** `OutboxRelay.runOnce` 8/8, `ShipmentService.create` 6/8, `RedisLock` 6/8, schema 4/8.
- **Radar hits:** `outbox.append` *before and outside* `tx.execute` (ShipmentService 19–20). `WHERE id > ?` cursor on a `BIGSERIAL` (OutboxRelay 34). `publisher.publish(...)` with the future discarded (36). `UPDATE relay_cursor SET last_id = ?` as a blind write (39). `redis.delete(key)` in release (RedisLock 18). A fixed 10 s lease with no renewal or fencing (28). Payload = `orderId,trackingNo`, with no id.

### Minute 10: one hop each

- What if the shipment insert fails after the outbox insert committed? A phantom `ShipmentCreated`, which happens a few hundred times a day: F1.
- Two concurrent creates: id 41 commits after id 42. The relay saw 42 and moved its cursor to 42, so 41 is skipped forever. F2.
- Broker rejects sends during a leader election, but the cursor already moved: F3.
- After a redelivery, how does the warehouse know it's a duplicate? It can't; there's no id. F4.
- A 3 s GC pause on a 10 s lease with a 500-row batch: the lease expires, another pod relays the same rows. F5.
- The paused pod wakes and `DEL`s the lock now held by the second pod. A third can start. F6.
- The paused pod then writes its stale cursor over the newer one, so rows are re-published. F7.

### Minute 20: prove, unify, fix

- **Unify:** F1 and F3 are the same mistake on both ends of the pipe: *a durable "done" recorded before the thing is done*. F2, F5, F6 and F7 share one: *the relay's correctness depends on single-ownership that neither the cursor nor the lock can guarantee*. F4 is the missing half of at-least-once.
- **Fix shape:** append inside the shipment transaction. Replace the cursor with per-row `published_at` and `FOR UPDATE SKIP LOCKED` batches. Await all broker acks before marking, and roll back on failure. Put the outbox id in every message. Keep the Redis lock only as an optimization, released by compare-and-delete.

---

## 6. The L7 answer key, line by line

### F1 · L3 · Sev-1 · The outbox row commits on its own, before the shipment: failed creates announce phantom shipments (ShipmentService 19–21)

**Mechanism.** `outbox.append` runs outside `tx.execute`, in its own auto-committed statement, *before* the shipment insert. When the insert then fails (duplicate tracking number, a few hundred times a day), the event is already durable, and the warehouse receives `ShipmentCreated` for a shipment that doesn't exist. The author inverted the dual write to avoid lost events and created phantom ones. The outbox only works when both rows commit in one transaction.

**Evidence.** P1: `second create fails on a duplicate tracking number: shipments = 1, ShipmentCreated outbox rows = 2 (phantom events: 1)`. Fix: `phantom events: 0`.

```comment-l7
issue (blocking): the outbox row commits in its own statement before the shipment insert, so failed creates publish phantom events

Line 19 appends outside `tx.execute`, which means when the insert on line 20 fails (duplicate tracking numbers happen a few hundred times a day) the ShipmentCreated row is already committed and the warehouse picks a shipment that doesn't exist. The P1 probe shows 1 phantom per failed create. Suggest appending inside the same transaction, after the insert: same connection, so both rows commit or neither does. That's the property the outbox pattern exists for.
```

**Fix.**
```java
        Long id = tx.execute(s -> {
            Long shipmentId = jdbc.queryForObject(
                    "INSERT INTO shipments (order_id, tracking_no) VALUES (?, ?) RETURNING id", Long.class, orderId, trackingNo);
            outbox.append("ShipmentCreated", orderId + "," + trackingNo); // same connection, same transaction
            return shipmentId;
        });
```

### F2 · L2 · Sev-1 · `WHERE id > cursor` skips rows that commit out of id order (OutboxRelay 32–34, 39)

**Mechanism.** Ids are assigned at insert time; commits happen in whatever order transactions finish. At 400 creates/s, transaction A takes id 41, transaction B takes id 42, and B commits first. The relay sees 42 and stores cursor = 42. When A commits, 41 is behind the cursor forever. No error, no gap metric. The warehouse just never hears about that shipment, which is the outage the ticket was meant to fix.

**Evidence.** P2 (two real PostgreSQL transactions): `two commits out of id order: events ever published = 1 of 2`. Fix: `2 of 2`.

```comment-l7
issue (blocking): the id cursor permanently skips rows that commit after a higher id

Ids are assigned at insert, not at commit, so under concurrent creates a lower id can become visible after the relay has already moved its cursor past it, which means that event is never published (P2 probe, two real transactions: 1 of 2 published). This is exactly the "warehouse never hears about it" bug the ticket targets, now silent. Suggest replacing the cursor with per-row state: `WHERE published_at IS NULL ... FOR UPDATE SKIP LOCKED`, then mark the rows published.
```

**Fix.**
```java
        List<Map<String, Object>> rows = jdbc.queryForList("SELECT id, type, payload FROM outbox WHERE published_at IS NULL "
                + "ORDER BY id LIMIT 500 FOR UPDATE SKIP LOCKED");
```
```java
        jdbc.batchUpdate("UPDATE outbox SET published_at = now() WHERE id = ?", ids);
```

### F3 · L3 · Sev-1 · The cursor advances before the broker acknowledges: a rejected send is lost (36–40)

**Mechanism.** `publisher.publish` returns a future that the relay ignores. The cursor is updated immediately, so if the broker rejects the sends (`NOT_ENOUGH_REPLICAS` during a leader election), those events are past the cursor and gone. The "async for speed" choice in the PR description quietly turned the relay into at-most-once.

**Evidence.** P3: `broker rejects one relay round, then recovers: events published = 0 of 3`. Fix: `3 of 3`.

```comment-l7
issue (blocking): publish futures are discarded, so the cursor moves even when the broker rejected the sends

Line 36 ignores the future the producer returns, and line 39 advances the cursor immediately, which means a leader election (NOT_ENOUGH_REPLICAS) loses that batch permanently; the P3 probe publishes 0 of 3 after the broker recovers. Suggest collecting the futures, joining them before marking rows published, and letting a failure roll the batch back so the next round retries it. Batching keeps it fast: one wait per batch, not per message.
```

**Fix.**
```java
        CompletableFuture.allOf(acks.toArray(CompletableFuture[]::new)).join(); // a failed ack rolls the batch back
```

### F4 · L5 · Sev-2 · Messages carry no event id: consumers cannot de-duplicate the redeliveries the relay will produce (36)

**Mechanism.** Any outbox relay is at-least-once: a crash between publishing and marking redelivers the batch. The payload is `orderId,trackingNo`, and one order can have several shipments, so the warehouse can't tell a redelivery from a second shipment. Either it double-picks, or it "de-duplicates" by order and drops real shipments. The outbox row id is a free, stable, unique event id.

**Evidence.** P4: `messages a consumer receives: [ShipmentCreated:o1,TRK1, ShipmentCreated:o1,TRK1-reship] (unique event id present: false)`. Fix: `[ShipmentCreated:1,o1,TRK1, ShipmentCreated:2,o1,TRK1-reship] (… true)`.

```comment-l7
issue (blocking): published messages have no event id, so the warehouse can't de-duplicate redeliveries

The relay is necessarily at-least-once (a crash between publish and mark redelivers), and the payload is orderId + trackingNo; for example, orders with several shipments produce messages a consumer can't tell apart from a redelivery (P4 probe). This means either double picks or dropped shipments downstream. Suggest including the outbox row id as the event id (in the payload or as the Kafka key/header) and documenting the at-least-once contract for consumers.
```

**Fix.**
```java
            acks.add(publisher.publish((String) r.get("type"), r.get("id") + "," + r.get("payload"))); // id: consumer dedup key
```

### F5 · L2 · Sev-2 · A fixed lease shorter than the work, with nothing to stop the expired holder (28)

**Mechanism.** The lease is 10 s. A batch of 500 sends during a slow broker period, or a 1–3 s GC pause on a loaded pod, can outlast it. When it expires, another pod acquires the lock and relays the same rows while the first is still publishing them. Renewal (a watchdog) narrows the window but cannot close it: a paused process can't renew. Correctness has to come from the resource, not the lease.

**Evidence.** P5: relay A stalls past its 300 ms lease while B takes over: `messages delivered = 30, distinct = 15, duplicates = 15`. Fix: `duplicates = 0`. B's `SKIP LOCKED` sees only rows A hasn't locked. One measured run.

```comment-l7
issue (blocking): when a relay outlives its 10 s lease (GC pause, slow broker), a second relay publishes the same rows

The lock's mutual exclusion lasts only as long as the lease; line 28 neither renews nor fences, which means a paused relay and its successor both publish the batch (the P5 probe: 15 duplicates out of 30 messages). Renewal can't fully fix this, because a paused process can't renew. Suggest making the database the arbiter: FOR UPDATE SKIP LOCKED gives each row one owner regardless of the lease, so the Redis lock becomes an optimization rather than a correctness requirement.
```

**Fix.** Per-row ownership through `FOR UPDATE SKIP LOCKED` (shown under F2), inside one transaction per batch:
```java
            Integer published = tx.execute(s -> publishBatch());
```

### F6 · L2 · Sev-2 · `release` deletes the lock even when another instance now holds it (RedisLock 18; OutboxRelay 43)

**Mechanism.** `finally { lock.release(LOCK) }` calls `DEL`. If this relay's lease expired and another instance acquired the lock, this `DEL` removes *the other instance's* lock, and a third instance can start while the second is mid-batch. Redis's own documentation calls this out: release must delete only if the stored value is still yours.

**Evidence.** P6: `after the stale holder A releases, the lock is held by: nobody (A deleted B's lock; a third instance can start)`. Fix: `b`. One measured run.

```comment-l7
issue (blocking): release() uses DEL, so a relay whose lease expired deletes the lock now held by another instance

Line 18 deletes unconditionally; for example, if A's lease expires and B acquires, A's finally block removes B's lock, which means a third instance can start (P6 probe: lock held by nobody while B is mid-batch). Redis's distributed-lock docs warn that a plain DEL can remove another client's lock. Suggest releasing with the compare-and-delete script (RedisClient.deleteIfValue), keyed by this instance's value.
```

**Fix.**
```java
    public void release(String key, String owner) {
        redis.deleteIfValue(key, owner);
    }
```

### F7 · L2 · Sev-2 · The cursor is written blindly, with no fencing token: a stale relay moves it backward (39)

**Mechanism.** `UPDATE relay_cursor SET last_id = ?` accepts any write from anyone. A relay that resumes after its lease expired writes the cursor it computed before the pause, *behind* where the current holder already moved it, and the next round re-publishes everything in between. This is the textbook case for a fencing token: a number from the lock service that increases on each acquisition, with the storage write conditioned on it (`… WHERE token < :mine`). The fix removes the cursor entirely, so there is nothing left to fence.

**Evidence.** Part of P5, by construction of the scenario: A publishes rows 1–10 (all duplicates of B's), B publishes 1–15 and sets the cursor to 15, then A writes its stale cursor 10, and round C re-publishes 11–15. 10 + 15 + 5 = 30 messages for 15 rows. Five of the 15 duplicates are this cursor regression. Fix: no cursor, no regression.

```comment-l7
issue (blocking): the cursor update accepts writes from a relay that no longer holds the lock, which means a stale relay can move the cursor backward and trigger re-publishing

Line 39 is a blind write; a relay resuming after an expired lease writes the cursor it computed before the pause, behind the current holder's, and the next round republishes the gap (5 of the duplicates in the P5 probe). If we keep a cursor it needs a fencing token (INCR on acquire, `UPDATE ... WHERE token < :mine`); I'd suggest removing the cursor instead (per-row published_at), so there's no shared position to protect.
```

### T1 · The test that pins the contract gap

`relayPublishesInOrderOnce` asserts messages `ShipmentCreated:o1,TRK1` with no id, so adding the event id (F4) breaks it, and it is the one PR test that fails against the fix. The scenarios the author's tests can't see, now covered by the fixed suite: a failed create leaves no event, a row committed out of id order is still published, a broker failure is retried, and release never deletes another instance's lock.

```comment-l7
todo (blocking): the relay test pins the payload format without an event id, and none of the tests exercise concurrency or failure

`relayPublishesInOrderOnce` will need to change once messages carry the outbox id. Suggest adding the four scenarios that would have caught the blocking issues: a failed create produces no outbox row, a lower id committed late is still published, a broker failure leaves rows for the next round, and a stale holder's release keeps the other instance's lock.
```

---

## 7. The refactored code

```java
// ===== shipping-service/src/main/java/com/acme/shipping/Outbox.java =====
package com.acme.shipping;

import org.springframework.jdbc.core.JdbcTemplate;

/** Appends events to the outbox table; OutboxRelay publishes them. */
public final class Outbox {
    private final JdbcTemplate jdbc;

    public Outbox(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    public void append(String type, String payload) {
        jdbc.update("INSERT INTO outbox (type, payload) VALUES (?, ?)", type, payload);
    }
}

// ===== shipping-service/src/main/java/com/acme/shipping/OutboxRelay.java =====
package com.acme.shipping;

import java.time.Duration;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.concurrent.CompletableFuture;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.support.JdbcTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;

/**
 * Publishes unpublished outbox rows to shipments.events. Correctness comes from the database, not the lock: each
 * batch row-locks its rows (FOR UPDATE SKIP LOCKED), waits for broker acks, and marks them published in the same
 * transaction. Concurrent relays get disjoint rows; a stalled relay still holds its rows' locks; a failed publish
 * rolls back and is retried. The Redis lock only avoids pointless polling by idle instances.
 */
public final class OutboxRelay {
    private static final String LOCK = "lock:outbox-relay";

    private final JdbcTemplate jdbc;
    private final TransactionTemplate tx;
    private final EventPublisher publisher;
    private final RedisLock lock;
    private final String instanceId;
    private final Duration lease;

    public OutboxRelay(JdbcTemplate jdbc, EventPublisher publisher, RedisClient redis, String instanceId, Duration lease) {
        this.jdbc = jdbc;
        this.tx = new TransactionTemplate(new JdbcTransactionManager(jdbc.getDataSource()));
        this.publisher = publisher;
        this.lock = new RedisLock(redis);
        this.instanceId = instanceId;
        this.lease = lease;
    }

    /** One polling round; returns how many events were published. Throws if the broker rejected the batch. */
    public int runOnce() {
        if (!lock.tryAcquire(LOCK, instanceId, lease)) {
            return 0;
        }
        try {
            Integer published = tx.execute(s -> publishBatch());
            return published == null ? 0 : published;
        } finally {
            lock.release(LOCK, instanceId); // compare-and-delete: never removes another instance's lock
        }
    }

    private int publishBatch() {
        List<Map<String, Object>> rows = jdbc.queryForList("SELECT id, type, payload FROM outbox WHERE published_at IS NULL "
                + "ORDER BY id LIMIT 500 FOR UPDATE SKIP LOCKED");
        List<CompletableFuture<Void>> acks = new ArrayList<>();
        List<Object[]> ids = new ArrayList<>();
        for (Map<String, Object> r : rows) {
            acks.add(publisher.publish((String) r.get("type"), r.get("id") + "," + r.get("payload"))); // id: consumer dedup key
            ids.add(new Object[] {r.get("id")});
        }
        CompletableFuture.allOf(acks.toArray(CompletableFuture[]::new)).join(); // a failed ack rolls the batch back
        jdbc.batchUpdate("UPDATE outbox SET published_at = now() WHERE id = ?", ids);
        return rows.size();
    }
}

// ===== shipping-service/src/main/java/com/acme/shipping/RedisLock.java =====
package com.acme.shipping;

import java.time.Duration;

/** Fleet-wide advisory lock on Redis. Release only deletes the key if this owner still holds it. */
public final class RedisLock {
    private final RedisClient redis;

    public RedisLock(RedisClient redis) {
        this.redis = redis;
    }

    public boolean tryAcquire(String key, String owner, Duration lease) {
        return redis.setIfAbsent(key, owner, lease.toMillis());
    }

    public void release(String key, String owner) {
        redis.deleteIfValue(key, owner);
    }
}

// ===== shipping-service/src/main/java/com/acme/shipping/ShipmentService.java =====
package com.acme.shipping;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.support.TransactionTemplate;

/** Creates shipments. The shipment row and its ShipmentCreated outbox row commit in one transaction, or neither does. */
public final class ShipmentService {
    private final JdbcTemplate jdbc;
    private final TransactionTemplate tx;
    private final Outbox outbox;

    public ShipmentService(JdbcTemplate jdbc, TransactionTemplate tx, Outbox outbox) {
        this.jdbc = jdbc;
        this.tx = tx;
        this.outbox = outbox;
    }

    public long create(String orderId, String trackingNo) {
        Long id = tx.execute(s -> {
            Long shipmentId = jdbc.queryForObject(
                    "INSERT INTO shipments (order_id, tracking_no) VALUES (?, ?) RETURNING id", Long.class, orderId, trackingNo);
            outbox.append("ShipmentCreated", orderId + "," + trackingNo); // same connection, same transaction
            return shipmentId;
        });
        return id == null ? 0 : id;
    }
}
```

**Fixed suite: 5/5 (output, verified).**

```text
├─ JUnit Jupiter ✔
│  └─ OutboxTest ✔
│     ├─ rowCommittedOutOfIdOrderIsStillPublished() ✔
│     ├─ createWritesShipmentAndOutboxRowTogether() ✔
│     ├─ releaseNeverDeletesAnotherInstancesLock() ✔
│     ├─ brokerFailureLeavesRowsForTheNextRound() ✔
│     └─ relayPublishesOnceWithEventIds() ✔
[         5 tests found           ]
[         5 tests successful      ]
[         0 tests failed          ]
```

**The PR's original tests against the fix (output, verified).** The exact-payload test fails because messages now carry the event id:

```text
├─ JUnit Jupiter ✔
│  └─ OutboxTest ✔
│     ├─ onlyOneRelayAtATime() ✔
│     ├─ relayPublishesInOrderOnce() ✘ expected: <[ShipmentCreated:o1,TRK1, ShipmentCreated:o2,TRK2]> but was: <[ShipmentCreated:1,o1,TRK1, ShipmentCreated:2,o2,TRK2]>
│     └─ createWritesShipmentAndOutboxRow() ✔
[         3 tests found           ]
[         2 tests successful      ]
[         1 tests failed          ]
```

### 7.1 Why this shape

| Concern | PR | Fix |
|---|---|---|
| Atomicity | Outbox row first, own transaction | Shipment + outbox row in one transaction |
| Relay position | Shared `id > cursor` | Per-row `published_at`; no shared position |
| Concurrency safety | Redis lock (lease) | Row locks: `FOR UPDATE SKIP LOCKED`; the lock is an optimization |
| Delivery | Fire-and-forget | Await all acks; failure rolls the batch back |
| Consumer contract | No event id | Outbox id in every message (at-least-once + dedup key) |
| Lock release | `DEL` | Compare-and-delete |

**One trade-off to state in review.** The fixed relay holds its batch's row locks while it waits for broker acks, so batch size × broker latency bounds the hold. That's fine for a few hundred rows; for long stalls, cap the batch or publish in smaller transactional chunks. With several relays, *global* order across relays isn't guaranteed. If per-shipment ordering matters (Created before Updated), key the Kafka message by shipment id and either run one active relay or partition outbox rows by key.

---

## 8. Probe evidence

**Against the PR's code (output, verified; P5 and P6 are one measured run):**

```text
PR06 probes against the PR's outbox relay (PostgreSQL 18, Redis double)
P1 F1 second create fails on a duplicate tracking number: shipments = 1, ShipmentCreated outbox rows = 2 (phantom events: 1)
P2 F2 two commits out of id order: events ever published = 1 of 2
P3 F3 broker rejects one relay round, then recovers: events published = 0 of 3
P4 F4 messages a consumer receives: [ShipmentCreated:o1,TRK1, ShipmentCreated:o1,TRK1-reship] (unique event id present: false)
P5 F5/F7 relay A stalls past its lease while B takes over (15 outbox rows): messages delivered = 30, distinct = 15, duplicates = 15 (one measured run)
P6 F6 after the stale holder A releases, the lock is held by: nobody (A deleted B's lock; a third instance can start) (one measured run)
```

**Against the fixed code (output, verified; P5 and P6 are one measured run):**

```text
PR06 probes against the fixed outbox relay (PostgreSQL 18, Redis double)
P1 F1 second create fails on a duplicate tracking number: shipments = 1, ShipmentCreated outbox rows = 1 (phantom events: 0)
P2 F2 two commits out of id order: events ever published = 2 of 2
P3 F3 broker rejects one relay round, then recovers: events published = 3 of 3
P4 F4 messages a consumer receives: [ShipmentCreated:1,o1,TRK1, ShipmentCreated:2,o1,TRK1-reship] (unique event id present: true)
P5 F5/F7 relay A stalls past its lease while B takes over (15 outbox rows): messages delivered = 15, distinct = 15, duplicates = 0 (one measured run)
P6 F6 after the stale holder A releases, the lock is held by: b (one measured run)
```

<details><summary><b>The probe harness (Pr06Probes.java)</b></summary>

```java
package com.acme.shipping;

import java.sql.Connection;
import java.time.Duration;
import java.util.HashSet;

/**
 * Pr06Probes - failure-shaped probes for PR06 on PostgreSQL 18 (embedded) and a single-node Redis double with real
 * PX expiry. Relays run as separate "instances" with their own producer stalls. Prints outcomes only.
 */
public final class Pr06Probes {
    private static final String LOCK = "lock:outbox-relay";

    private static ShipmentService shipments() {
        return new ShipmentService(Db.jdbc(), Db.tx(), new Outbox(Db.jdbc()));
    }

    private static OutboxRelay relay(FakeRedis redis, String instance, FakePublisher publisher, long leaseMillis) {
        return new OutboxRelay(Db.jdbc(), publisher, redis, instance, Duration.ofMillis(leaseMillis));
    }

    private static void fresh() {
        Db.reset();
        FakePublisher.BROKER.clear();
    }

    private static int tryRun(OutboxRelay r) {
        try {
            return r.runOnce();
        } catch (RuntimeException e) {
            return -1;
        }
    }

    public static void main(String[] args) throws Exception {
        System.out.println("PR06 probes against the " + args[0] + " outbox relay (PostgreSQL 18, Redis double)");

        fresh();
        ShipmentService s = shipments();
        s.create("o1", "TRK1");
        try {
            s.create("o2", "TRK1"); // tracking number already used: the insert fails
        } catch (RuntimeException expected) {
            // 409 to the caller
        }
        System.out.println("P1 F1 second create fails on a duplicate tracking number: shipments = "
                + Db.count("SELECT count(*) FROM shipments") + ", ShipmentCreated outbox rows = "
                + Db.count("SELECT count(*) FROM outbox") + " (phantom events: " + (Db.count("SELECT count(*) FROM outbox")
                - Db.count("SELECT count(*) FROM shipments")) + ")");

        fresh();
        FakeRedis redis = new FakeRedis();
        try (Connection slow = Db.ds().getConnection()) {
            slow.setAutoCommit(false);
            slow.createStatement().execute("INSERT INTO outbox (type, payload) VALUES ('ShipmentCreated', 'o0,TRK0')");
            shipments().create("o1", "TRK1"); // takes the next id, commits first
            tryRun(relay(redis, "a", new FakePublisher(), 10_000));
            slow.commit(); // the lower id becomes visible after the relay moved past it
        }
        tryRun(relay(redis, "a", new FakePublisher(), 10_000));
        tryRun(relay(redis, "a", new FakePublisher(), 10_000));
        System.out.println("P2 F2 two commits out of id order: events ever published = " + FakePublisher.BROKER.size() + " of 2");

        fresh();
        redis = new FakeRedis();
        for (int i = 1; i <= 3; i++) {
            shipments().create("o" + i, "TRK" + i);
        }
        FakePublisher down = new FakePublisher();
        down.brokerDown = true;
        tryRun(relay(redis, "a", down, 10_000)); // broker rejects the sends
        tryRun(relay(redis, "a", new FakePublisher(), 10_000)); // broker healthy again
        System.out.println("P3 F3 broker rejects one relay round, then recovers: events published = "
                + FakePublisher.BROKER.size() + " of 3");

        fresh();
        redis = new FakeRedis();
        shipments().create("o1", "TRK1");
        shipments().create("o1", "TRK1-reship"); // same order, a second shipment
        tryRun(relay(redis, "a", new FakePublisher(), 10_000));
        System.out.println("P4 F4 messages a consumer receives: " + FakePublisher.BROKER
                + " (unique event id present: " + FakePublisher.BROKER.get(0).matches("ShipmentCreated:\\d+,.*") + ")");

        zombieRelay();
        lockRelease();
        System.out.flush();
        System.exit(0);
    }

    /** Relay A stalls past its 300 ms lease mid-batch; relay B takes over; more rows arrive meanwhile. */
    static void zombieRelay() throws Exception {
        fresh();
        FakeRedis redis = new FakeRedis();
        for (int i = 1; i <= 10; i++) {
            shipments().create("o" + i, "TRK" + i);
        }
        FakePublisher slowA = new FakePublisher();
        slowA.stallMillis = 60; // 10 events x 60 ms = 600 ms, twice the lease
        Thread a = new Thread(() -> tryRun(relay(redis, "a", slowA, 300)));
        a.start();
        Thread.sleep(350); // A's lease has expired; A is still publishing
        for (int i = 11; i <= 15; i++) {
            shipments().create("o" + i, "TRK" + i);
        }
        tryRun(relay(redis, "b", new FakePublisher(), 300));
        a.join();
        tryRun(relay(redis, "c", new FakePublisher(), 300)); // the next scheduled round
        int total = FakePublisher.BROKER.size();
        int distinct = new HashSet<>(FakePublisher.BROKER).size();
        System.out.println("P5 F5/F7 relay A stalls past its lease while B takes over (15 outbox rows): messages delivered = "
                + total + ", distinct = " + distinct + ", duplicates = " + (total - distinct) + " (one measured run)");
    }

    /** A's lease expires, B acquires and is still working when A finishes and releases. */
    static void lockRelease() throws Exception {
        fresh();
        FakeRedis redis = new FakeRedis();
        shipments().create("o1", "TRK1");
        FakePublisher slowA = new FakePublisher();
        slowA.stallMillis = 400;
        Thread a = new Thread(() -> tryRun(relay(redis, "a", slowA, 200)));
        a.start();
        Thread.sleep(250); // A's lease expired
        shipments().create("o2", "TRK2");
        FakePublisher slowB = new FakePublisher();
        slowB.stallMillis = 800;
        Thread b = new Thread(() -> tryRun(relay(redis, "b", slowB, 5_000)));
        b.start();
        a.join(); // A finishes and releases while B is still mid-batch
        String holder = redis.get(LOCK);
        System.out.println("P6 F6 after the stale holder A releases, the lock is held by: "
                + (holder == null ? "nobody (A deleted B's lock; a third instance can start)" : holder) + " (one measured run)");
        b.join();
    }
}
```

</details>

<details><summary><b>The refactor as a diff (PR → fixed)</b></summary>

```diff
diff --git a/shipping-service/src/main/java/com/acme/shipping/OutboxRelay.java b/shipping-service/src/main/java/com/acme/shipping/OutboxRelay.java
index 601f4b0..9bd4aae 100644
--- a/shipping-service/src/main/java/com/acme/shipping/OutboxRelay.java
+++ b/shipping-service/src/main/java/com/acme/shipping/OutboxRelay.java
@@ -1,15 +1,25 @@
 package com.acme.shipping;
 
 import java.time.Duration;
+import java.util.ArrayList;
 import java.util.List;
 import java.util.Map;
+import java.util.concurrent.CompletableFuture;
 import org.springframework.jdbc.core.JdbcTemplate;
+import org.springframework.jdbc.support.JdbcTransactionManager;
+import org.springframework.transaction.support.TransactionTemplate;
 
-/** Publishes outbox rows to shipments.events in id order. One relay at a time across the fleet (Redis lock). */
+/**
+ * Publishes unpublished outbox rows to shipments.events. Correctness comes from the database, not the lock: each
+ * batch row-locks its rows (FOR UPDATE SKIP LOCKED), waits for broker acks, and marks them published in the same
+ * transaction. Concurrent relays get disjoint rows; a stalled relay still holds its rows' locks; a failed publish
+ * rolls back and is retried. The Redis lock only avoids pointless polling by idle instances.
+ */
 public final class OutboxRelay {
     private static final String LOCK = "lock:outbox-relay";
 
     private final JdbcTemplate jdbc;
+    private final TransactionTemplate tx;
     private final EventPublisher publisher;
     private final RedisLock lock;
     private final String instanceId;
@@ -17,30 +27,37 @@ public final class OutboxRelay {
 
     public OutboxRelay(JdbcTemplate jdbc, EventPublisher publisher, RedisClient redis, String instanceId, Duration lease) {
         this.jdbc = jdbc;
+        this.tx = new TransactionTemplate(new JdbcTransactionManager(jdbc.getDataSource()));
         this.publisher = publisher;
         this.lock = new RedisLock(redis);
         this.instanceId = instanceId;
         this.lease = lease;
     }
 
-    /** One polling round; returns how many events were published. */
+    /** One polling round; returns how many events were published. Throws if the broker rejected the batch. */
     public int runOnce() {
         if (!lock.tryAcquire(LOCK, instanceId, lease)) {
-            return 0; // another instance is relaying
+            return 0;
         }
         try {
-            Long last = jdbc.queryForObject("SELECT last_id FROM relay_cursor WHERE name = 'outbox'", Long.class);
-            List<Map<String, Object>> rows = jdbc.queryForList(
-                    "SELECT id, type, payload FROM outbox WHERE id > ? ORDER BY id LIMIT 500", last);
-            for (Map<String, Object> r : rows) {
-                publisher.publish((String) r.get("type"), (String) r.get("payload")); // async: keeps the relay fast
-            }
-            if (!rows.isEmpty()) {
-                jdbc.update("UPDATE relay_cursor SET last_id = ? WHERE name = 'outbox'", rows.get(rows.size() - 1).get("id"));
-            }
-            return rows.size();
+            Integer published = tx.execute(s -> publishBatch());
+            return published == null ? 0 : published;
         } finally {
-            lock.release(LOCK);
+            lock.release(LOCK, instanceId); // compare-and-delete: never removes another instance's lock
         }
     }
+
+    private int publishBatch() {
+        List<Map<String, Object>> rows = jdbc.queryForList("SELECT id, type, payload FROM outbox WHERE published_at IS NULL "
+                + "ORDER BY id LIMIT 500 FOR UPDATE SKIP LOCKED");
+        List<CompletableFuture<Void>> acks = new ArrayList<>();
+        List<Object[]> ids = new ArrayList<>();
+        for (Map<String, Object> r : rows) {
+            acks.add(publisher.publish((String) r.get("type"), r.get("id") + "," + r.get("payload"))); // id: consumer dedup key
+            ids.add(new Object[] {r.get("id")});
+        }
+        CompletableFuture.allOf(acks.toArray(CompletableFuture[]::new)).join(); // a failed ack rolls the batch back
+        jdbc.batchUpdate("UPDATE outbox SET published_at = now() WHERE id = ?", ids);
+        return rows.size();
+    }
 }
diff --git a/shipping-service/src/main/java/com/acme/shipping/RedisLock.java b/shipping-service/src/main/java/com/acme/shipping/RedisLock.java
index 32465ab..40a5cf3 100644
--- a/shipping-service/src/main/java/com/acme/shipping/RedisLock.java
+++ b/shipping-service/src/main/java/com/acme/shipping/RedisLock.java
@@ -2,7 +2,7 @@ package com.acme.shipping;
 
 import java.time.Duration;
 
-/** Fleet-wide mutual exclusion on Redis: SET NX PX to acquire, DEL to release. */
+/** Fleet-wide advisory lock on Redis. Release only deletes the key if this owner still holds it. */
 public final class RedisLock {
     private final RedisClient redis;
 
@@ -14,7 +14,7 @@ public final class RedisLock {
         return redis.setIfAbsent(key, owner, lease.toMillis());
     }
 
-    public void release(String key) {
-        redis.delete(key);
+    public void release(String key, String owner) {
+        redis.deleteIfValue(key, owner);
     }
 }
diff --git a/shipping-service/src/main/java/com/acme/shipping/ShipmentService.java b/shipping-service/src/main/java/com/acme/shipping/ShipmentService.java
index 9ca791d..ae257dd 100644
--- a/shipping-service/src/main/java/com/acme/shipping/ShipmentService.java
+++ b/shipping-service/src/main/java/com/acme/shipping/ShipmentService.java
@@ -3,7 +3,7 @@ package com.acme.shipping;
 import org.springframework.jdbc.core.JdbcTemplate;
 import org.springframework.transaction.support.TransactionTemplate;
 
-/** Creates shipments. ShipmentCreated now goes through the transactional outbox (published by OutboxRelay). */
+/** Creates shipments. The shipment row and its ShipmentCreated outbox row commit in one transaction, or neither does. */
 public final class ShipmentService {
     private final JdbcTemplate jdbc;
     private final TransactionTemplate tx;
@@ -16,9 +16,12 @@ public final class ShipmentService {
     }
 
     public long create(String orderId, String trackingNo) {
-        outbox.append("ShipmentCreated", orderId + "," + trackingNo); // recorded first, so the event can never be lost
-        Long id = tx.execute(s -> jdbc.queryForObject(
-                "INSERT INTO shipments (order_id, tracking_no) VALUES (?, ?) RETURNING id", Long.class, orderId, trackingNo));
+        Long id = tx.execute(s -> {
+            Long shipmentId = jdbc.queryForObject(
+                    "INSERT INTO shipments (order_id, tracking_no) VALUES (?, ?) RETURNING id", Long.class, orderId, trackingNo);
+            outbox.append("ShipmentCreated", orderId + "," + trackingNo); // same connection, same transaction
+            return shipmentId;
+        });
         return id == null ? 0 : id;
     }
 }
diff --git a/shipping-service/src/main/java/schema.sql b/shipping-service/src/main/java/schema.sql
index 36e0ed8..92bec6e 100644
--- a/shipping-service/src/main/java/schema.sql
+++ b/shipping-service/src/main/java/schema.sql
@@ -4,13 +4,10 @@ CREATE TABLE shipments (
     tracking_no TEXT NOT NULL UNIQUE
 );
 CREATE TABLE outbox (
-    id         BIGSERIAL PRIMARY KEY,
-    type       TEXT NOT NULL,
-    payload    TEXT NOT NULL,
-    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
+    id           BIGSERIAL PRIMARY KEY,
+    type         TEXT NOT NULL,
+    payload      TEXT NOT NULL,
+    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
+    published_at TIMESTAMPTZ
 );
-CREATE TABLE relay_cursor (
-    name    TEXT PRIMARY KEY,
-    last_id BIGINT NOT NULL
-);
-INSERT INTO relay_cursor VALUES ('outbox', 0);
+CREATE INDEX outbox_unpublished ON outbox (id) WHERE published_at IS NULL;
diff --git a/shipping-service/src/test/java/com/acme/shipping/OutboxTest.java b/shipping-service/src/test/java/com/acme/shipping/OutboxTest.java
index 43e46e0..0b0cf08 100644
--- a/shipping-service/src/test/java/com/acme/shipping/OutboxTest.java
+++ b/shipping-service/src/test/java/com/acme/shipping/OutboxTest.java
@@ -1,11 +1,14 @@
 package com.acme.shipping;
 
 import static org.junit.jupiter.api.Assertions.assertEquals;
+import static org.junit.jupiter.api.Assertions.assertThrows;
 
+import java.sql.Connection;
 import java.time.Duration;
 import java.util.List;
 import org.junit.jupiter.api.BeforeEach;
 import org.junit.jupiter.api.Test;
+import org.springframework.dao.DuplicateKeyException;
 
 class OutboxTest {
     private final FakeRedis redis = new FakeRedis();
@@ -17,30 +20,53 @@ class OutboxTest {
         FakePublisher.BROKER.clear();
     }
 
-    private OutboxRelay relay(String instance) {
-        return new OutboxRelay(Db.jdbc(), new FakePublisher(), redis, instance, Duration.ofSeconds(10));
+    private OutboxRelay relay(String instance, FakePublisher publisher) {
+        return new OutboxRelay(Db.jdbc(), publisher, redis, instance, Duration.ofSeconds(10));
     }
 
     @Test
-    void createWritesShipmentAndOutboxRow() {
+    void createWritesShipmentAndOutboxRowTogether() {
         shipments.create("o1", "TRK1");
+        assertThrows(DuplicateKeyException.class, () -> shipments.create("o2", "TRK1"));
         assertEquals(1, Db.count("SELECT count(*) FROM shipments"));
         assertEquals(1, Db.count("SELECT count(*) FROM outbox"));
     }
 
     @Test
-    void relayPublishesInOrderOnce() {
+    void relayPublishesOnceWithEventIds() {
         shipments.create("o1", "TRK1");
         shipments.create("o2", "TRK2");
-        assertEquals(2, relay("a").runOnce());
-        assertEquals(0, relay("a").runOnce());
-        assertEquals(List.of("ShipmentCreated:o1,TRK1", "ShipmentCreated:o2,TRK2"), FakePublisher.BROKER);
+        assertEquals(2, relay("a", new FakePublisher()).runOnce());
+        assertEquals(0, relay("a", new FakePublisher()).runOnce());
+        assertEquals(List.of("ShipmentCreated:1,o1,TRK1", "ShipmentCreated:2,o2,TRK2"), FakePublisher.BROKER);
     }
 
     @Test
-    void onlyOneRelayAtATime() {
+    void rowCommittedOutOfIdOrderIsStillPublished() throws Exception {
+        try (Connection slow = Db.ds().getConnection()) {
+            slow.setAutoCommit(false);
+            slow.createStatement().execute("INSERT INTO outbox (type, payload) VALUES ('ShipmentCreated', 'o0,TRK0')");
+            shipments.create("o1", "TRK1"); // takes the next id and commits first
+            relay("a", new FakePublisher()).runOnce();
+            slow.commit();
+        }
+        relay("a", new FakePublisher()).runOnce();
+        assertEquals(2, FakePublisher.BROKER.size());
+    }
+
+    @Test
+    void brokerFailureLeavesRowsForTheNextRound() {
         shipments.create("o1", "TRK1");
-        redis.setIfAbsent("lock:outbox-relay", "b", 10_000); // instance b is relaying
-        assertEquals(0, relay("a").runOnce());
+        FakePublisher down = new FakePublisher();
+        down.brokerDown = true;
+        assertThrows(RuntimeException.class, () -> relay("a", down).runOnce());
+        assertEquals(1, relay("a", new FakePublisher()).runOnce());
+    }
+
+    @Test
+    void releaseNeverDeletesAnotherInstancesLock() {
+        redis.setIfAbsent("lock:outbox-relay", "b", 10_000);
+        new RedisLock(redis).release("lock:outbox-relay", "a");
+        assertEquals("b", redis.get("lock:outbox-relay"));
     }
 }
```

</details>

---

## 9. Scoring this PR

| # | Defect | Severity (weight) | Tier | Typically found by |
|---|---|---|---|---|
| F1 | Outbox outside the transaction (phantoms) | Sev-1 (5) | 2 | L5+ |
| F2 | Cursor skips out-of-order commits | Sev-1 (5) | 20 | L7 (requires sequence-vs-commit reasoning) |
| F3 | Cursor before broker ack | Sev-1 (5) | 10 | L6+ |
| F4 | No event id | Sev-2 (3) | 10 | L6+ |
| F5 | Lease shorter than work, no fencing | Sev-2 (3) | 10 | L6+ |
| F6 | Unsafe release | Sev-2 (3) | 2 | L5+ (if they know the Redis pattern) |
| F7 | Blind cursor write | Sev-2 (3) | 20 | L7 |

Total **27**. Most reviewers find F1 and F6. L6s add F3, F4 and F5, and propose renewing the lease. L7s find F2 and say the key sentence: *"stop relying on the lock for correctness; give each row one owner in the database."*

---

## 10. Failure modes (reviewers on this PR)

| Failure mode | What it looks like | Why it fails |
|---|---|---|
| "Use Redlock" | Five Redis nodes for the lock | Still a lease; still no fencing; the gap race and ack bug remain |
| "Add a lock watchdog" | Auto-renew the lease | A paused process can't renew; F5 narrows but persists |
| "Make the cursor transactional" | `SELECT … FOR UPDATE` on `relay_cursor` | Serializes relays, but F2 (commit order) still skips rows |
| Fixing F1 by deleting the outbox row on failure | Compensating delete | Races the relay; it may publish before the delete |
| "Consumers must be idempotent" with no id provided | Pushes the problem downstream | They need a key to be idempotent on |
| Treating Debezium/CDC as automatically safe | "Use CDC instead" | CDC solves F2/F3 (reads the WAL in commit order) but not F1 or F4 |

---

## 11. Bar-raiser chains

<details><summary><b>Q1 · "Why does `WHERE id > cursor` lose events? Ids only go up."</b></summary>

**Initial Prompt.** Sequence vs commit order.

**L5 Answer.** "It doesn't. Ids are monotonic, so the cursor sees everything eventually."

**Why L5 Stalls.** Monotonic *assignment* isn't monotonic *visibility*. That's the whole bug.

**L7 Answer.** "Ids are assigned at insert; rows become visible at commit. Transaction A takes 41, B takes 42, and B commits first. The relay reads 42 and stores cursor 42. A commits, but 41 < 42, so it's never read. At 400 creates/s this happens constantly, and silently. Per-row state with `SKIP LOCKED` fixes it, or a CDC reader that follows the WAL in commit order. A 'safety lag' (only read ids older than N seconds) only makes the bug rarer."

</details>

<details><summary><b>Q2 · "What's a fencing token, and does this design need one?"</b></summary>

**Initial Prompt.** Lease-based locks under pauses.

**L5 Answer.** "It's a lock ID. We could store the owner name in the cursor."

**Why L5 Stalls.** An owner name doesn't order holders. A stale holder's name is still valid-looking.

**L7 Answer.** "A number that increases on each acquisition (Redis `INCR` on acquire). The protected write is conditioned on it: `UPDATE relay_cursor SET last_id = ?, token = ? WHERE token < ?`. A resumed stale holder has a lower token and its write is rejected. The PR's design needs one for the cursor. The fix doesn't, because it has no shared position: each row's lock and `published_at` *are* the fencing. Fencing belongs at the resource, which is why the lock alone can't provide it."

</details>

<details><summary><b>Q3 · "Isn't SKIP LOCKED unfair? One relay could hog everything."</b></summary>

**Initial Prompt.** Operational behavior of the fix.

**L5 Answer.** "Yes, so keep the Redis lock to have only one relay."

**Why L5 Stalls.** Conflates throughput balance with correctness. Unfairness is fine for an outbox; duplicates and losses aren't.

**L7 Answer.** "It's work-stealing, and that's fine: each batch takes the oldest unlocked rows, so idle relays pick up whatever others haven't locked. The Redis lock now just stops five idle pods from polling every 100 ms. If it misbehaves (expires, gets deleted), correctness doesn't change. What I'd watch instead is the age of the oldest unpublished row, the relay's real SLO."

</details>

<details><summary><b>Q4 · "Why not wait for each send's future before the next one?"</b></summary>

**Initial Prompt.** Acks and throughput.

**L5 Answer.** "That's the safest. Do it."

**Why L5 Stalls.** Correct but slow: one broker round trip per message. At 400/s and 5 ms per ack, one relay can't keep up.

**L7 Answer.** "Send the whole batch, then wait for all acks at once (`allOf(...).join()`), then mark the batch published in the same transaction. That gives one round-trip latency per batch, not per message, and a single failure rolls the batch back for a retry. Use an idempotent producer (`enable.idempotence=true`) so a retried batch doesn't duplicate inside the broker. Consumers still de-dup by event id for the crash-after-send case."

</details>

<details><summary><b>Q5 · "Should we just use Debezium (CDC) instead of a polling relay?"</b></summary>

**Initial Prompt.** Alternatives.

**L5 Answer.** "Yes, CDC is the modern approach."

**Why L5 Stalls.** A tool-swap answer that doesn't check which defects it fixes.

**L7 Answer.** "CDC tails the WAL in commit order, so it fixes F2 (and F3/F5/F7, since there's no relay cursor of ours). It doesn't fix F1: a phantom row in the outbox is still a phantom in the WAL. And it doesn't fix F4: messages still need an event id. It also adds infrastructure (Kafka Connect, slot management, WAL retention). For 400/s I'd ship the fixed polling relay now and evaluate CDC when the team runs Connect anyway."

</details>

<details><summary><b>Q6 · "The author proposes Redlock across 5 Redis nodes to make the lock safe. Approve?"</b></summary>

**Initial Prompt.** Distributed-lock algorithms.

**L5 Answer.** "Yes, Redlock is designed for this."

**Why L5 Stalls.** Redlock improves availability of the lock service, not safety under process pauses. Redis's own docs point readers to Kleppmann's analysis and recommend fencing tokens.

**L7 Answer.** "No. The failure here is a *client* pause outliving the lease, and no lock service can prevent that. Redis's documentation itself says to implement fencing tokens for long-running work. The fix stops needing the lock for correctness, so a single Redis node is plenty for the optimization that remains."

</details>

<details><summary><b>Q7 · "How do you monitor an outbox in production?"</b></summary>

**Initial Prompt.** Operability.

**L5 Answer.** "Count published messages."

**Why L5 Stalls.** A counter goes up even while a row is stuck or skipped. F2's skipped rows never show.

**L7 Answer.** "The age of the oldest unpublished row (`now() − min(created_at) WHERE published_at IS NULL`), alerting at your delivery SLO. Plus outbox table growth, publish failure rate, and a daily reconciliation that counts `shipments` vs `ShipmentCreated` delivered per day. That reconciliation is what would have caught both F1 (more events than shipments) and F2 (fewer)."

</details>

<details><summary><b>Q8 · "Rank the findings."</b></summary>

**Initial Prompt.** Prioritization.

**L5 Answer.** "The lock bugs first, since they're the most subtle."

**Why L5 Stalls.** Subtlety isn't severity. F1–F3 lose or invent events on ordinary days. The lock bugs need pauses.

**L7 Answer.** "F2 (silently loses events under normal concurrency, the exact symptom the ticket is fixing), F1 (phantoms on every failed create, hundreds a day), F3 (loses batches on every leader election), then F4 (needed before consumers can tolerate the at-least-once relay), then F5/F6/F7 (duplicates and stomped locks under pauses; all disappear once correctness moves to row locks). It's one refactor, about 40 lines different from the PR."

</details>

---

## 12. Checklist

- [ ] Outbox row and state change in the *same* transaction and connection.
- [ ] Relay position: no `id > cursor` on sequences; per-row state or a commit-ordered log (CDC).
- [ ] Relay marks published only after broker acks; failure means retry, not skip.
- [ ] Every message carries a stable event id; the at-least-once contract is documented for consumers.
- [ ] Any lease-based lock: what if the holder pauses past the lease? Where is the fencing?
- [ ] Lock release: compare-and-delete, never plain `DEL`.
- [ ] Prefer database-native exclusion (`FOR UPDATE SKIP LOCKED`, unique constraints) over external locks.
- [ ] Monitor oldest-unpublished-age, and reconcile state vs events.

---

## 13. References

- Kleppmann, M. *How to do distributed locking* (fencing tokens; GC pauses vs leases). https://martin.kleppmann.com/2016/02/08/how-to-do-distributed-locking.html
- Redis: *Distributed Locks with Redis* (unique value; compare-and-delete release; recommendation to implement fencing tokens). https://redis.io/docs/latest/develop/clients/patterns/distributed-locks/
- PostgreSQL documentation: *Sequence Manipulation Functions* (sequences are not gapless). https://www.postgresql.org/docs/current/functions-sequence.html
- PostgreSQL documentation: *SELECT … FOR UPDATE SKIP LOCKED* (the locking clause). https://www.postgresql.org/docs/current/sql-select.html#SQL-FOR-UPDATE-SHARE
- Richardson, C. *Pattern: Transactional outbox*. https://microservices.io/patterns/data/transactional-outbox.html
- Debezium: *Outbox Event Router* (CDC-based outbox). https://debezium.io/documentation/reference/stable/transformations/outbox-event-router.html
- Within this KB: [PR01 (event after commit)](../02-Java-Spring-Hibernate-and-Microservices-PR-Simulations/01-pr01-fintech-wallet-transfer-transactional-proxy-and-deadlock-traps.md) · [PR04 Kafka consumer](01-pr04-kafka-consumer-offset-commit-race-poison-pill-and-rebalance-storm.md) · [01-00 PR-00 (outbox fix)](../01-The-L7-Code-Review-Mental-Model-and-Rubric/02-the-7-layer-fault-scan-correctness-concurrency-io-compat-security.md#11-pr-00-answer-key-line-by-line)
