# PR04 · Kafka Consumer: Offset-Commit Race, Poison Pill and Rebalance Storm

> **What this module is.** A one-file PR that "parallelizes" a Kafka consumer to fix 40 minutes of lag. The diff is small (167 lines) and reads like an obvious improvement: a thread pool, async commits, bigger batches, retries with backoff. It turns an at-least-once, in-order consumer into an **at-most-once, out-of-order consumer that loses data on every deploy, hides its own lag, and cannot be shut down**. It has **8 defects (4 Sev-1)**, and none needs a broker to demonstrate: everything below runs on kafka-clients' `MockConsumer` with the real `Consumer` API.

| Artifact | What it is | Verified |
|---|---|---|
| `pr04-diff` | `PaymentEventsConsumer` rewritten + its test: 167 diff lines (+75 −29) | `git diff --no-index` from compiled sources |
| `PaymentEventsConsumerTest` (author's) | 3 tests: applies and commits 100 events, "parallel is faster," retries transient failures | **3/3 pass** on the PR (§4) |
| `Pr04Probes` | 7 probes: auto-commit config, per-payment ordering, revocation mid-batch, backpressure, deploy mid-batch, shutdown, poison pill | each shows the defect on the PR and its absence on the fix (§8) |
| Fixed code | Per-partition ordered lanes, commit-what's-done, pause/resume backpressure, DLQ for permanent failures, bounded retries, rebalance listener that drains, `wakeup()`-based shutdown | fixed suite 5/5; PR's own tests against the fix 2/3 (the failing test asserts within-partition parallelism, the defect) |

**Verification.** kafka-clients 4.2.2 (`MockConsumer`: `rebalance`, `pause`/`resume`, `wakeup`, `commitSync`/`commitAsync`, `committed`), JDK 25.0.4.1 with `javac --release 21 -Xlint:all -Werror`, and JUnit Platform 1.13.4. Config defaults were read from `ConsumerConfig` in the same jar. P4, P6 and P7 depend on timing and are labeled "one measured run"; every other line is deterministic in structure, and the counts move only with scheduling.

---

## 0. Orientation

### 0.1 What this PR tests

| Layer | Defects | Why reviewers miss them |
|---|---|---|
| L3 Failure paths | F1 commit before processing, F7 shutdown loses in-flight work, F8 retry loop swallows interrupts | Each line is idiomatic; the failure is in what happens *between* them |
| L2 Concurrency | F2 per-payment ordering lost, F6 no rebalance handling | "Kafka guarantees order" is true per partition, and only if you keep it |
| L5 Compatibility | F3 a v2 event type becomes an infinite retry (and the before-code's DLQ path was deleted) | The poison pill arrives from *another team's* deploy |
| L7 Operability | F3 lag reads 0 while nothing is applied, F4 no backpressure, F5 auto-commit back on by default | Dashboards look healthy |

### 0.2 Habits this PR punishes

| Habit | What happens here |
|---|---|
| "commitAsync is just the non-blocking commitSync." | It commits the *poll position*, not what was processed. |
| "A thread pool parallelizes the consumer." | It also parallelizes events that must be ordered. |
| "Retry transient errors forever with backoff." | A v2 event type isn't transient. Forever means forever. |
| "Removing a config line is a cleanup." | The removed line was `enable.auto.commit=false`. |
| "shutdownNow() stops the workers." | Not if they swallow the interrupt. |

---

## 1. First principles

1. **The commit is the delivery guarantee.** Kafka stores a committed *offset*, which means "everything before this is done." Commit after processing and you get at-least-once. Commit before and you get at-most-once. The KafkaConsumer javadoc, on processing in other threads: you "must disable automatic commits and manually commit processed offsets for records only after the thread has finished handling them."
2. **Order exists only within a partition, and only if you process it that way.** Kafka orders records per partition (records with the same key go to the same partition). A shared thread pool reorders them. Safe parallelism is across partitions (or across keys within a partition, with careful offset tracking).
3. **The consumer object is single-threaded.** "The Kafka consumer is NOT thread-safe." The only exception is `wakeup()`, "which can safely be used from an external thread to interrupt an active operation," and "Un-synchronized access will result in ConcurrentModificationException."
4. **Flow control is pause/resume, not buffering.** The javadoc describes pausing partitions "so that no new records are received from poll" while background threads catch up.
5. **Rebalances revoke partitions mid-flight.** Without a `ConsumerRebalanceListener` that finishes (or abandons) in-flight work and commits before returning, the old owner keeps writing while the new owner starts from the last commit.
6. **Poison pills are permanent failures.** Retrying a record the code can never parse blocks its partition (or its worker) forever. Classify failures: permanent → dead-letter queue; transient → bounded retry, then the DLQ.
7. **Defaults are part of the contract.** With a `group.id`, `enable.auto.commit` is effectively `true` (P5 reads it from `ConsumerConfig`), so a manual-commit consumer that doesn't set it to `false` also auto-commits every `auto.commit.interval.ms` (5 s).

---

## 2. The PR

> **PAY-5120 · Parallelize the ledger consumer**
>
> On Black Friday, `payments.events` lag reached 40 minutes and the ledger showed stale payment statuses. The consumer applies events one at a time (≈ 4 ms each). Make it parallel.
>
> **PR description, by the author:**
> - Records are handed to a fixed thread pool (`threads` configurable, default 16).
> - `commitAsync()` replaces `commitSync()`, so the poll loop never blocks.
> - `max.poll.records` raised to 1,000 now that processing is parallel.
> - Failures are retried with exponential backoff (cap 1 s), since ledger blips are transient.
> - Simplified `config()` to the platform defaults.
> - Tests: all events applied and committed, parallel faster than sequential, transient failures retried.
>
> **Context the reviewer can discover:** `payments.events` has 24 partitions keyed by `paymentId`; the ledger update is last-write-wins (`UPDATE payments SET status = ?`). The producer team is rolling out v2 events (adds `REFUND_REVERSED`) next sprint, and this consumer's `PaymentEvent.parse` is v1 and strict. Deploys are rolling restarts with SIGTERM and a 30 s grace period. Lag alerts are based on committed offsets.

---

## 3. The diff

```diff
diff --git a/ledger-consumer/src/main/java/com/acme/payments/PaymentEventsConsumer.java b/ledger-consumer/src/main/java/com/acme/payments/PaymentEventsConsumer.java
index 058d212..8c410f4 100644
--- a/ledger-consumer/src/main/java/com/acme/payments/PaymentEventsConsumer.java
+++ b/ledger-consumer/src/main/java/com/acme/payments/PaymentEventsConsumer.java
@@ -3,25 +3,30 @@ package com.acme.payments;
 import java.time.Duration;
 import java.util.List;
 import java.util.Properties;
+import java.util.concurrent.ExecutorService;
+import java.util.concurrent.Executors;
 import org.apache.kafka.clients.consumer.Consumer;
 import org.apache.kafka.clients.consumer.ConsumerConfig;
 import org.apache.kafka.clients.consumer.ConsumerRecord;
-import org.apache.kafka.common.errors.WakeupException;
+import org.apache.kafka.clients.consumer.ConsumerRecords;
 import org.apache.kafka.common.serialization.StringDeserializer;
 
-/** Applies payments.events to the ledger, one record at a time, in partition order. */
+/** Applies payments.events to the ledger. Parallel: lag reached 40 minutes on Black Friday. */
 public final class PaymentEventsConsumer implements Runnable {
     public static final String TOPIC = "payments.events";
 
     private final Consumer<String, String> consumer;
     private final LedgerClient ledger;
     private final DeadLetters deadLetters;
+    private final ExecutorService workers;
     private volatile boolean running = true;
 
-    public PaymentEventsConsumer(Consumer<String, String> consumer, LedgerClient ledger, DeadLetters deadLetters) {
+    public PaymentEventsConsumer(Consumer<String, String> consumer, LedgerClient ledger, DeadLetters deadLetters,
+                                 int threads) {
         this.consumer = consumer;
         this.ledger = ledger;
         this.deadLetters = deadLetters;
+        this.workers = Executors.newFixedThreadPool(threads);
     }
 
     public static Properties config(String bootstrapServers, String groupId) {
@@ -30,36 +35,44 @@ public final class PaymentEventsConsumer implements Runnable {
         p.put(ConsumerConfig.GROUP_ID_CONFIG, groupId);
         p.put(ConsumerConfig.KEY_DESERIALIZER_CLASS_CONFIG, StringDeserializer.class.getName());
         p.put(ConsumerConfig.VALUE_DESERIALIZER_CLASS_CONFIG, StringDeserializer.class.getName());
-        p.put(ConsumerConfig.ENABLE_AUTO_COMMIT_CONFIG, "false"); // we commit after the ledger write
+        p.put(ConsumerConfig.MAX_POLL_RECORDS_CONFIG, "1000"); // bigger batches now that processing is parallel
         return p;
     }
 
     @Override
     public void run() {
-        try {
-            consumer.subscribe(List.of(TOPIC));
-            while (running) {
-                for (ConsumerRecord<String, String> r : consumer.poll(Duration.ofMillis(100))) {
-                    PaymentEvent event;
-                    try {
-                        event = PaymentEvent.parse(r.value());
-                    } catch (IllegalArgumentException e) {
-                        deadLetters.send(r, e);
-                        continue;
-                    }
-                    ledger.apply(event);
-                }
-                consumer.commitSync();
+        consumer.subscribe(List.of(TOPIC));
+        while (running) {
+            ConsumerRecords<String, String> records = consumer.poll(Duration.ofMillis(100));
+            for (ConsumerRecord<String, String> r : records) {
+                workers.submit(() -> process(r));
             }
-        } catch (WakeupException e) {
-            // stop() was called
-        } finally {
-            consumer.close();
+            consumer.commitAsync(); // non-blocking, keeps the poll loop fast
         }
     }
 
     public void stop() {
         running = false;
-        consumer.wakeup();
+        workers.shutdownNow();
+        consumer.close();
+    }
+
+    private void process(ConsumerRecord<String, String> r) {
+        for (int attempt = 1; ; attempt++) {
+            try {
+                ledger.apply(PaymentEvent.parse(r.value()));
+                return;
+            } catch (RuntimeException e) {
+                sleep(Math.min(1_000, 50L * attempt)); // ledger blips are transient: back off and retry
+            }
+        }
+    }
+
+    private static void sleep(long millis) {
+        try {
+            Thread.sleep(millis);
+        } catch (InterruptedException e) {
+            Thread.currentThread().interrupt();
+        }
     }
 }
diff --git a/ledger-consumer/src/test/java/com/acme/payments/PaymentEventsConsumerTest.java b/ledger-consumer/src/test/java/com/acme/payments/PaymentEventsConsumerTest.java
index 322227e..9341667 100644
--- a/ledger-consumer/src/test/java/com/acme/payments/PaymentEventsConsumerTest.java
+++ b/ledger-consumer/src/test/java/com/acme/payments/PaymentEventsConsumerTest.java
@@ -2,20 +2,53 @@ package com.acme.payments;
 
 import static org.junit.jupiter.api.Assertions.assertEquals;
 
+import java.util.ArrayList;
 import java.util.List;
 import org.junit.jupiter.api.Test;
 
 class PaymentEventsConsumerTest {
+    private static List<String> authorizations(int n) {
+        List<String> values = new ArrayList<>();
+        for (int i = 0; i < n; i++) {
+            values.add("e" + i + ",p" + i + ",AUTHORIZED,500");
+        }
+        return values;
+    }
+
     @Test
-    void appliesEventsInOrderAndCommits() throws Exception {
-        Topic topic = new Topic(List.of("e1,p1,AUTHORIZED,500", "e2,p1,CAPTURED,500"));
+    void appliesAllEventsAndCommits() throws Exception {
+        Topic topic = new Topic(authorizations(100));
         FakeLedger ledger = new FakeLedger(0, 0);
-        PaymentEventsConsumer c = new PaymentEventsConsumer(topic.consumer, ledger, topic.dlq);
+        PaymentEventsConsumer c = new PaymentEventsConsumer(topic.consumer, ledger, topic.dlq, 8);
+        Thread t = Topic.start(c);
+        Topic.sleep(500);
+        c.stop();
+        t.join();
+        assertEquals(100, ledger.applied());
+        assertEquals(100, topic.committed());
+    }
+
+    @Test
+    void parallelIsFasterThanSequential() throws Exception {
+        Topic topic = new Topic(authorizations(80));
+        FakeLedger ledger = new FakeLedger(10, 10);
+        PaymentEventsConsumer c = new PaymentEventsConsumer(topic.consumer, ledger, topic.dlq, 8);
+        Thread t = Topic.start(c);
+        Topic.sleep(400); // 80 x 10 ms is 800 ms sequentially; 8 threads need ~100 ms
+        assertEquals(80, ledger.applied());
+        c.stop();
+        t.join();
+    }
+
+    @Test
+    void retriesTransientLedgerFailures() throws Exception {
+        Topic topic = new Topic(List.of("e1,p1,AUTHORIZED,500"));
+        FlakyLedger ledger = new FlakyLedger(2);
+        PaymentEventsConsumer c = new PaymentEventsConsumer(topic.consumer, ledger, topic.dlq, 2);
         Thread t = Topic.start(c);
-        Topic.sleep(300);
+        Topic.sleep(500);
         c.stop();
         t.join();
-        assertEquals(PaymentEvent.Type.CAPTURED, ledger.status.get("p1"));
-        assertEquals(2, topic.committed());
+        assertEquals(1, ledger.successes);
     }
 }
```

---

## 4. The author's tests: green

```text
├─ JUnit Jupiter ✔
│  └─ PaymentEventsConsumerTest ✔
│     ├─ appliesAllEventsAndCommits() ✔
│     ├─ parallelIsFasterThanSequential() ✔
│     └─ retriesTransientLedgerFailures() ✔
[         3 tests found           ]
[         3 tests successful      ]
[         0 tests failed          ]
```

Every test uses one event type per payment, so there's no ordering to violate, and only valid v1 events. Each test waits long enough for all work to finish before `stop()`, so nothing is in flight at shutdown. No test rebalances. `parallelIsFasterThanSequential` asserts that one partition's records are processed concurrently, which *is* the ordering defect. It is the one test that fails against the fix.

---

## 5. The timed 3-pass diagnostic guide

### Minute 2: map and triage

- **Contracts changed:** the delivery guarantee (where the commit sits), the ordering guarantee (threads), the failure policy (retry vs DLQ) and the shutdown path. Plus a config line removed.
- **Hunk scores:** `run()` 8/8, `process()` 6/8, `stop()` 6/8, `config()` 4/8 (a contract change by deletion).
- **Radar hits:** `workers.submit` followed by `consumer.commitAsync()` (48–50). `for (int attempt = 1; ; attempt++)` with a catch-all (61–66). `deadLetters` still injected but now unused (20, 28). `- ENABLE_AUTO_COMMIT_CONFIG, "false"` in the removed lines. `shutdownNow()` then `consumer.close()` from another thread (56–57). `subscribe(List.of(TOPIC))` with no listener (44).

### Minute 10: one hop each

- What does `commitAsync()` commit? The position after the last *poll*, not processing: F1.
- Two events for one payment in the same batch on two threads? Last-write-wins in the ledger, so reversed order sticks: F2.
- What does `PaymentEvent.parse` do with `REFUND_REVERSED`? It throws `IllegalArgumentException`, which the loop retries forever, and the workers fill up. Meanwhile commits keep advancing, so lag reads 0: F3.
- What stops `poll` from fetching more than the workers can apply? Nothing. The executor queue is unbounded: F4.
- The removed line: `enable.auto.commit` reverts to its default: F5.
- Partition revoked while 500 tasks are queued? They keep writing: F6.
- SIGTERM: `shutdownNow()` interrupts tasks whose offsets were already committed: F7. `close()` is called from a non-poll thread, a documented `ConcurrentModificationException` on the real client.
- What does the retry loop do with an interrupt? Restores the flag, sleeps, gets interrupted again, loops forever: F8.

### Minute 20: prove, unify, fix

- **Unify:** F1, F3, F6 and F7 share one cause. *The commit is decoupled from completion.* F2 and F4 share another: *a shared unbounded pool replaced the partition as the unit of work.* F5 and F8 are a config and a coding rule.
- **Fix shape:** one single-threaded lane per partition (hash partitions onto `threads` lanes), commit the per-partition "done" offset, pause partitions over 500 in flight, DLQ permanent failures, retry transient ones at most 5 times, drain-and-commit in `onPartitionsRevoked`, `stop()` = `wakeup()`, and shut down by draining, committing, then closing on the poll thread.

---

## 6. The L7 answer key, line by line

### F1 · L3 · Sev-1 · Offsets are committed before the records are processed (48–50)

**Mechanism.** The loop submits the batch to the pool and immediately calls `commitAsync()`, which commits the consumer's *position*: the offset after the last polled record. From that moment, a crash, OOM kill or deploy loses every record still queued or running. After restart the group resumes at the committed offset, past them. The consumer has silently become at-most-once.

**Evidence.** P1: `deploy mid-batch: committed offset 200, events applied N -> skipped forever after restart: 200 − N`. Fix: committed equals applied.

```comment-l7
issue (blocking): commitAsync() on line 50 commits the poll position, not what the workers have finished

Records are submitted on line 48 and their offsets committed on line 50 before any worker runs, which means anything in the queue when the pod dies is skipped forever (the next owner starts at the committed offset). The P1 probe stops the consumer mid-batch: offset 200 committed, far fewer applied. Suggest tracking a per-partition "done" offset in the workers and committing only that (commitSync with an explicit map), as the KafkaConsumer javadoc prescribes for multi-threaded processing.
```

**Fix.**
```java
        done.put(tp, r.offset() + 1);
```
```java
    private void commitDone() {
        Map<TopicPartition, OffsetAndMetadata> offsets = new HashMap<>();
        done.forEach((tp, next) -> offsets.put(tp, new OffsetAndMetadata(next)));
        if (!offsets.isEmpty()) {
            consumer.commitSync(offsets);
        }
    }
```

### F2 · L2 · Sev-1 · A shared pool reorders each payment's events, and the ledger is last-write-wins (29, 48)

**Mechanism.** `AUTHORIZED` and `CAPTURED` for the same payment are adjacent on the same partition and now run on different threads. Whichever *finishes* last wins the ledger's `UPDATE … SET status`. The authorization write is slower, so captured payments end as `AUTHORIZED`: customers charged, merchants shown "not captured," settlement mismatches.

**Evidence.** P2: `50 payments AUTHORIZED then CAPTURED: 50 end in status AUTHORIZED`. Fix: 0.

```comment-l7
issue (blocking): the shared pool processes one payment's events concurrently, so the ledger ends with whichever write finishes last

payments.events is keyed by paymentId precisely so each payment's events arrive in order, and the ledger update is last-write-wins. With line 48 submitting every record to a shared pool, AUTHORIZED and CAPTURED for the same payment race, which means the final status depends on thread timing; for example, in the P2 probe all 50 captured payments end as AUTHORIZED. Suggest parallelism across partitions only: one single-threaded lane per partition (24 partitions is plenty), or key-hash lanes within a partition if we ever need more.
```

**Fix.**
```java
    private ExecutorService lane(TopicPartition tp) {
        return lanes[Math.floorMod(tp.hashCode(), lanes.length)];
    }
```

### F3 · L5/L7 · Sev-1 · A v2 event type becomes an infinite retry, and lag reads zero while nothing is applied (61–66; DLQ path removed)

**Mechanism.** `PaymentEvent.parse` is strict v1. The producer team's `REFUND_REVERSED` makes it throw `IllegalArgumentException`, a *permanent* failure that the catch-all treats as transient and retries forever. Each poison record pins a worker. With as many poison records as threads, the pool is fully occupied and every later record waits behind them indefinitely. Because of F1, commits keep advancing, so **committed-offset lag reads 0** and no alert fires. The before-code dead-lettered unparseable records. The PR still injects `deadLetters` but no longer uses it.

**Evidence.** P3: `4 REFUND_REVERSED events + 100 valid, 4 threads: applied 0, dead-lettered 0, committed 104 (consumer lag 0)`. Fix: `applied 100, dead-lettered 4`.

```comment-l7
issue (blocking): unparseable records are retried forever, and with commit-before-process the lag metric stays at zero

`PaymentEvent.parse` throws for event types this version doesn't know, and the producer team ships REFUND_REVERSED next sprint; lines 61-66 retry that forever, which means each one permanently occupies a worker. In the P3 probe four of them stop all processing while committed offsets (and therefore our lag alert) say everything is done. The before-code sent these to deadLetters, which is still injected but unused. Suggest restoring the DLQ for permanent failures (IllegalArgumentException from parse) and capping transient retries (5 attempts, then DLQ) so a partition always moves.
```

**Fix.**
```java
        } catch (IllegalArgumentException e) {
            deadLetters.send(r, e); // unknown type or malformed: retrying cannot help
```
```java
                    if (attempt == MAX_ATTEMPTS) {
                        deadLetters.send(r, e); // bounded: park it and keep the partition moving
                        break;
                    }
```

### F4 · L7 · Sev-2 · No backpressure: the consumer reads the whole backlog into memory (46–49)

**Mechanism.** The poll loop never waits for workers, and `newFixedThreadPool` has an unbounded queue. Under the exact scenario this PR targets (40 minutes of lag), the consumer fetches millions of records into the executor queue as fast as the broker sends them. The heap fills, the pod is OOM-killed, the group rebalances, another member inherits the backlog, and the cycle repeats: a rebalance storm. Every kill also loses the queued records (F1).

**Evidence.** P4: `20,000 events available, after 300 ms: records held in memory (polled − applied) = ~19,900` (fix: ≤ ~1,000). One measured run.

```comment-l7
issue (blocking): nothing stops the poll loop from buffering the entire backlog in the executor's unbounded queue

With a slow ledger, every poll adds more tasks than the workers finish, which means memory grows with lag, exactly the Black Friday condition this PR is for; the P4 probe holds ~19,900 records in memory after 300 ms. An OOM kill then triggers a rebalance and the next member repeats it. Suggest pausing a partition when its in-flight count passes a bound (500) and resuming below half: consumer.pause/resume is the documented flow-control mechanism.
```

**Fix.**
```java
    private void applyBackpressure() {
        inFlight.forEach((tp, n) -> {
            if (n.get() > MAX_IN_FLIGHT_PER_PARTITION) {
                consumer.pause(Set.of(tp));
            } else if (n.get() < MAX_IN_FLIGHT_PER_PARTITION / 2 && consumer.paused().contains(tp)) {
                consumer.resume(Set.of(tp));
            }
        });
    }
```

### F5 · L3 · Sev-2 · `enable.auto.commit=false` deleted from `config()` (removed line)

**Mechanism.** The diff deletes the line that disabled auto-commit as a "simplification to platform defaults." With a `group.id`, the client's default is auto-commit every 5 s. The real consumer therefore commits positions in the background *in addition to* the manual commits, which is at-most-once even if F1 were fixed. Easy to miss: it's a `-` line, and `config()` isn't exercised by the tests.

**Evidence.** P5: `effective enable.auto.commit = true` (fix: `false`).

```comment-l7
issue (blocking): removing ENABLE_AUTO_COMMIT_CONFIG=false turns background auto-commit back on

The deleted line was the one that made this a manual-commit consumer; with a group.id, the client default is to auto-commit polled positions every 5 seconds (the P5 probe reads `true` from ConsumerConfig). This means that even with processing-based commits we'd still commit unprocessed records in the background. Suggest restoring it, plus a unit test on config() so it can't silently drift again.
```

**Fix.**
```java
        p.put(ConsumerConfig.ENABLE_AUTO_COMMIT_CONFIG, "false"); // we commit only what the ledger has applied
```

### F6 · L2 · Sev-2 · No rebalance listener: revoked partitions keep being written by the old owner (44)

**Mechanism.** `subscribe(List.of(TOPIC))` registers no `ConsumerRebalanceListener`. When the group rebalances (deploy, scale-out, a member's GC pause), revoked partitions' records are still queued here and keep being applied, while the new owner starts from the last committed offset and applies the same events. Two consumers write the same payments concurrently, out of order. Under F4's OOM loop, rebalances are frequent, so this is routine.

**Evidence.** P6: `partition revoked mid-batch: ledger writes by this consumer AFTER it lost the partition = N` (fix: 0). One measured run.

```comment-l7
issue (blocking): without a rebalance listener, this consumer keeps applying events for partitions it no longer owns

On revocation the queued records for those partitions still run here while the new owner starts from the last commit, which means two consumers write the same payments concurrently; the P6 probe counts ledger writes after the partition was revoked. Suggest implementing onPartitionsRevoked to drain (or drop) that partition's queued work and commit its done offset before returning, and the cooperative-sticky assignor so deploys don't revoke everything at once.
```

**Fix.**
```java
    @Override
    public void onPartitionsRevoked(Collection<TopicPartition> partitions) { // on the poll thread, inside poll()
        drain(partitions);
        commitDone();
```

### F7 · L3 · Sev-1 · Shutdown interrupts committed work and closes the consumer from the wrong thread (54–58)

**Mechanism.** On SIGTERM, `stop()` sets the flag, then `shutdownNow()` interrupts every running task and discards every queued one. Their offsets were already committed (F1), so a rolling deploy loses a slice of events from **every partition this pod owned, on every deploy**. `consumer.close()` is then called from the signal-handling thread while the poll thread may be inside `poll()`. On the real `KafkaConsumer` that's a documented `ConcurrentModificationException` (MockConsumer is synchronized, so the probe can't show this half).

**Evidence.** P1 (above) is this scenario: a deploy mid-batch. The thread-safety half is from the KafkaConsumer javadoc (§1).

```comment-l7
issue (blocking): stop() discards in-flight records whose offsets are already committed, on every deploy

`shutdownNow()` (line 56) interrupts running tasks and drops queued ones, which means a rolling deploy skips events on every partition this pod owned (P1 probe), and `consumer.close()` (line 57) runs on the caller's thread, which the real KafkaConsumer rejects with ConcurrentModificationException. Suggest `stop()` = `running = false; consumer.wakeup();` and, on the poll thread: drain the lanes, commit done offsets, then close.
```

**Fix.**
```java
    public void stop() {
        running = false;
        consumer.wakeup();
    }
```

### F8 · L3 · Sev-2 · The retry loop swallows interrupts: workers never stop, and the pod hangs on SIGTERM (61–75)

**Mechanism.** `sleep()` catches `InterruptedException`, restores the flag, and returns. The `for (;;)` loop then retries: `ledger.apply` or the next `sleep` sees the interrupt and fails at once, and the loop spins. `shutdownNow()` can never terminate these workers, so the JVM's non-daemon pool threads keep it alive at 100% CPU per thread until Kubernetes SIGKILLs the pod after the grace period. (This module's own probe run hit it: the first probe JVM never exited.)

**Evidence.** P7: `worker threads still running 500 ms after stop(): N` (fix: 0). One measured run.

```comment-l7
issue (blocking): the retry loop turns an interrupt into a busy loop, so stop() can never end the workers

`sleep` restores the interrupt flag and returns, then the `for (;;)` on line 61 retries immediately and fails again, forever. That means shutdownNow() leaves the workers spinning (P7 probe: threads still running after stop) and the pod hangs on SIGTERM until it is killed. Suggest treating InterruptedException as "stop now": return without advancing the done offset, so the next owner reprocesses the record.
```

**Fix.**
```java
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            return; // not done: the offset is not advanced, so the next owner reprocesses it
```

### T1 · The test that asserts the defect

`parallelIsFasterThanSequential` puts 80 records on **one** partition and requires them to finish in 400 ms with 10 ms each, which is only possible if one partition's records run concurrently. That is F2's precondition written as a requirement. Against the fix it fails (`expected: <80>`, with fewer done in 400 ms): the fix processes a partition sequentially and gets its parallelism across partitions. The right test asserts per-key order *and* cross-partition throughput.

```comment-l7
todo (blocking): `parallelIsFasterThanSequential` requires concurrency within a single partition, which is the ordering bug

The test only passes if one partition's records run in parallel, which means it will fail any fix that restores per-payment ordering. Suggest replacing it with two tests: same-payment events stay in order (AUTHORIZED then CAPTURED ends CAPTURED), and N partitions finish about N times faster than one.
```

---

## 7. The refactored code

```java
// ===== ledger-consumer/src/main/java/com/acme/payments/PaymentEventsConsumer.java =====
package com.acme.payments;

import java.time.Duration;
import java.util.Collection;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Properties;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ExecutionException;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;
import org.apache.kafka.clients.consumer.Consumer;
import org.apache.kafka.clients.consumer.ConsumerConfig;
import org.apache.kafka.clients.consumer.ConsumerRebalanceListener;
import org.apache.kafka.clients.consumer.ConsumerRecord;
import org.apache.kafka.clients.consumer.OffsetAndMetadata;
import org.apache.kafka.common.TopicPartition;
import org.apache.kafka.common.errors.WakeupException;
import org.apache.kafka.common.serialization.StringDeserializer;

/**
 * Applies payments.events to the ledger in parallel across partitions and in order within each partition (a
 * partition always maps to the same single-threaded lane). Commits only offsets whose records are done, pauses
 * partitions that run too far ahead, dead-letters what can never succeed, and drains before giving partitions up.
 * Only the poll thread touches the consumer; stop() uses wakeup(), the consumer's one thread-safe method.
 */
public final class PaymentEventsConsumer implements Runnable, ConsumerRebalanceListener {
    public static final String TOPIC = "payments.events";
    private static final int MAX_IN_FLIGHT_PER_PARTITION = 500;
    private static final int MAX_ATTEMPTS = 5;

    private final Consumer<String, String> consumer;
    private final LedgerClient ledger;
    private final DeadLetters deadLetters;
    private final ExecutorService[] lanes;
    private final Map<TopicPartition, Long> done = new ConcurrentHashMap<>(); // next offset to commit
    private final Map<TopicPartition, AtomicInteger> inFlight = new ConcurrentHashMap<>();
    private volatile boolean running = true;

    public PaymentEventsConsumer(Consumer<String, String> consumer, LedgerClient ledger, DeadLetters deadLetters,
                                 int threads) {
        this.consumer = consumer;
        this.ledger = ledger;
        this.deadLetters = deadLetters;
        this.lanes = new ExecutorService[threads];
        for (int i = 0; i < threads; i++) {
            lanes[i] = Executors.newSingleThreadExecutor();
        }
    }

    public static Properties config(String bootstrapServers, String groupId) {
        Properties p = new Properties();
        p.put(ConsumerConfig.BOOTSTRAP_SERVERS_CONFIG, bootstrapServers);
        p.put(ConsumerConfig.GROUP_ID_CONFIG, groupId);
        p.put(ConsumerConfig.KEY_DESERIALIZER_CLASS_CONFIG, StringDeserializer.class.getName());
        p.put(ConsumerConfig.VALUE_DESERIALIZER_CLASS_CONFIG, StringDeserializer.class.getName());
        p.put(ConsumerConfig.ENABLE_AUTO_COMMIT_CONFIG, "false"); // we commit only what the ledger has applied
        p.put(ConsumerConfig.PARTITION_ASSIGNMENT_STRATEGY_CONFIG,
                "org.apache.kafka.clients.consumer.CooperativeStickyAssignor"); // no stop-the-world on deploys
        return p;
    }

    @Override
    public void run() {
        try {
            consumer.subscribe(List.of(TOPIC), this);
            while (running) {
                for (ConsumerRecord<String, String> r : consumer.poll(Duration.ofMillis(100))) {
                    TopicPartition tp = new TopicPartition(r.topic(), r.partition());
                    inFlight.computeIfAbsent(tp, k -> new AtomicInteger()).incrementAndGet();
                    lane(tp).submit(() -> process(tp, r));
                }
                applyBackpressure();
                commitDone();
            }
        } catch (WakeupException e) {
            // stop() was called
        } finally {
            drain(Set.copyOf(inFlight.keySet()));
            commitDone();
            consumer.close();
            for (ExecutorService lane : lanes) {
                lane.shutdown();
            }
        }
    }

    public void stop() {
        running = false;
        consumer.wakeup();
    }

    @Override
    public void onPartitionsRevoked(Collection<TopicPartition> partitions) { // on the poll thread, inside poll()
        drain(partitions);
        commitDone();
        partitions.forEach(tp -> {
            done.remove(tp);
            inFlight.remove(tp);
        });
    }

    @Override
    public void onPartitionsAssigned(Collection<TopicPartition> partitions) {
    }

    private void process(TopicPartition tp, ConsumerRecord<String, String> r) {
        try {
            PaymentEvent event = PaymentEvent.parse(r.value());
            for (int attempt = 1; ; attempt++) {
                try {
                    ledger.apply(event);
                    break;
                } catch (RuntimeException e) {
                    if (attempt == MAX_ATTEMPTS) {
                        deadLetters.send(r, e); // bounded: park it and keep the partition moving
                        break;
                    }
                    Thread.sleep(Math.min(1_000, 50L * attempt));
                }
            }
        } catch (IllegalArgumentException e) {
            deadLetters.send(r, e); // unknown type or malformed: retrying cannot help
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            return; // not done: the offset is not advanced, so the next owner reprocesses it
        } finally {
            inFlight.get(tp).decrementAndGet();
        }
        done.put(tp, r.offset() + 1);
    }

    private ExecutorService lane(TopicPartition tp) {
        return lanes[Math.floorMod(tp.hashCode(), lanes.length)];
    }

    private void applyBackpressure() {
        inFlight.forEach((tp, n) -> {
            if (n.get() > MAX_IN_FLIGHT_PER_PARTITION) {
                consumer.pause(Set.of(tp));
            } else if (n.get() < MAX_IN_FLIGHT_PER_PARTITION / 2 && consumer.paused().contains(tp)) {
                consumer.resume(Set.of(tp));
            }
        });
    }

    private void commitDone() {
        Map<TopicPartition, OffsetAndMetadata> offsets = new HashMap<>();
        done.forEach((tp, next) -> offsets.put(tp, new OffsetAndMetadata(next)));
        if (!offsets.isEmpty()) {
            consumer.commitSync(offsets);
        }
    }

    private void drain(Collection<TopicPartition> partitions) { // FIFO lanes: a marker runs after earlier work
        for (TopicPartition tp : partitions) {
            try {
                lane(tp).submit(() -> { }).get(30, TimeUnit.SECONDS);
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                return;
            } catch (ExecutionException | java.util.concurrent.TimeoutException e) {
                throw new IllegalStateException("could not drain " + tp, e);
            }
        }
    }
}
```

**Fixed suite: 5/5 (output, verified).**

```text
├─ JUnit Jupiter ✔
│  └─ PaymentEventsConsumerTest ✔
│     ├─ appliesAllEventsAndCommits() ✔
│     ├─ keepsEachPaymentsEventsInOrder() ✔
│     ├─ shutdownCommitsExactlyWhatWasApplied() ✔
│     ├─ unknownEventTypesAreDeadLetteredAndThePartitionMoves() ✔
│     └─ autoCommitIsDisabled() ✔
[         5 tests found           ]
[         5 tests successful      ]
[         0 tests failed          ]
```

**The PR's original tests against the fix (output, verified).** The within-partition parallelism test fails, as it should:

```text
├─ JUnit Jupiter ✔
│  └─ PaymentEventsConsumerTest ✔
│     ├─ appliesAllEventsAndCommits() ✔
│     ├─ parallelIsFasterThanSequential() ✘ expected: <80> but was: <36>
│     └─ retriesTransientLedgerFailures() ✔
[         3 tests found           ]
[         2 tests successful      ]
[         1 tests failed          ]
```

### 7.1 Why this shape

| Concern | PR | Fix |
|---|---|---|
| Unit of parallelism | Record (shared pool) | Partition (a partition always maps to the same single-threaded lane) |
| Commit | Poll position, async, immediately | Per-partition done offset, sync, every loop and on revoke/shutdown |
| Auto-commit | Default (on) | Off |
| Backpressure | None (unbounded queue) | `pause` above 500 in flight per partition, `resume` below 250 |
| Permanent failures | Retried forever | Dead-lettered immediately |
| Transient failures | Retried forever | 5 attempts with backoff, then DLQ |
| Rebalance | Ignored | Drain and commit revoked partitions inside `onPartitionsRevoked`; cooperative-sticky assignor |
| Shutdown | `shutdownNow()` + `close()` from another thread | `wakeup()`; the poll thread drains, commits, closes |
| Interrupts | Swallowed; busy loop | Stop without advancing the offset |

If 24 partitions × one lane each is not enough throughput, the next step is key-hash lanes *within* a partition, with a contiguous-completed-offset tracker (the design behind Confluent's Parallel Consumer), not a shared pool.

---

## 8. Probe evidence

**Against the PR's code (output, verified; P4, P6, P7 are one measured run):**

```text
PR04 probes against the PR's PaymentEventsConsumer (kafka-clients 4.2 MockConsumer)
P5 F5 effective enable.auto.commit = true
P2 F2 50 payments AUTHORIZED then CAPTURED: 50 end in status AUTHORIZED (captured money shown as uncaptured)
P6 F6 partition revoked mid-batch: ledger writes by this consumer AFTER it lost the partition = 36 (one measured run)
P4 F4 slow ledger, 20,000 events available, after 300 ms: records held in memory (polled - applied) = 19,856 (one measured run)
P1 F1/F7 deploy mid-batch: committed offset 200, events applied 54 -> skipped forever after restart: 146
P7 F8 worker threads still running 500 ms after stop(): 7
P3 F3 4 REFUND_REVERSED events + 100 valid, 4 threads: applied 0, dead-lettered 0, committed 104 (consumer lag 0)
```

**Against the fixed code (output, verified; P4, P6, P7 are one measured run):**

```text
PR04 probes against the fixed PaymentEventsConsumer (kafka-clients 4.2 MockConsumer)
P5 F5 effective enable.auto.commit = false
P2 F2 50 payments AUTHORIZED then CAPTURED: 0 end in status AUTHORIZED (captured money shown as uncaptured)
P6 F6 partition revoked mid-batch: ledger writes by this consumer AFTER it lost the partition = 0 (one measured run)
P4 F4 slow ledger, 20,000 events available, after 300 ms: records held in memory (polled - applied) = 981 (one measured run)
P1 F1/F7 deploy mid-batch: committed offset 200, events applied 200 -> skipped forever after restart: 0
P7 F8 worker threads still running 500 ms after stop(): 0
P3 F3 4 REFUND_REVERSED events + 100 valid, 4 threads: applied 100, dead-lettered 4, committed 104 (consumer lag 0)
```

<details><summary><b>The probe harness (Pr04Probes.java)</b></summary>

```java
package com.acme.payments;

import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.concurrent.atomic.AtomicLong;
import org.apache.kafka.clients.consumer.ConsumerConfig;

/**
 * Pr04Probes - deploy, ordering, poison-pill, backpressure, config and rebalance probes for PR04, on kafka-clients'
 * MockConsumer (real Consumer API: offsets, pause/resume, rebalance callbacks, wakeup). Prints outcomes only.
 */
public final class Pr04Probes {
    private static String n(long v) {
        return String.format(Locale.ROOT, "%,d", v);
    }

    private static List<String> authorizations(int n, int from) {
        List<String> values = new ArrayList<>();
        for (int i = from; i < from + n; i++) {
            values.add("e" + i + ",p" + i + ",AUTHORIZED,500");
        }
        return values;
    }

    public static void main(String[] args) throws Exception {
        System.out.println("PR04 probes against the " + args[0] + " PaymentEventsConsumer (kafka-clients 4.2 MockConsumer)");
        // Order matters: on the PR's code, stop() leaves interrupted workers spinning forever (F8), so the probes
        // that stop mid-work run last, and the JVM exits explicitly.
        System.out.println("P5 F5 effective enable.auto.commit = " + new ConsumerConfig(
                PaymentEventsConsumer.config("localhost:9092", "ledger")).getBoolean(ConsumerConfig.ENABLE_AUTO_COMMIT_CONFIG));
        ordering();
        rebalance();
        backpressure();
        deploy();
        poisonPill();
        System.out.flush();
        System.exit(0);
    }

    static void deploy() throws Exception {
        Topic topic = new Topic(authorizations(200, 0));
        FakeLedger ledger = new FakeLedger(5, 5);
        java.util.Set<Long> before = Thread.getAllStackTraces().keySet().stream().map(Thread::threadId)
                .collect(java.util.stream.Collectors.toSet());
        PaymentEventsConsumer c = new PaymentEventsConsumer(topic.consumer, ledger, topic.dlq, 8);
        Thread t = Topic.start(c);
        Topic.sleep(100);
        c.stop(); // rolling deploy: SIGTERM -> stop()
        t.join();
        Topic.sleep(500);
        long committed = topic.committed();
        System.out.println("P1 F1/F7 deploy mid-batch: committed offset " + n(committed) + ", events applied " + n(ledger.applied())
                + " -> skipped forever after restart: " + n(Math.max(0, committed - ledger.applied())));
        long busy = Thread.getAllStackTraces().keySet().stream()
                .filter(th -> !before.contains(th.threadId()) && th.isAlive() && th.getState() != Thread.State.WAITING)
                .count();
        System.out.println("P7 F8 worker threads still running 500 ms after stop(): " + busy);
    }

    static void ordering() throws Exception {
        List<String> values = new ArrayList<>();
        for (int i = 0; i < 50; i++) {
            values.add("a" + i + ",p" + i + ",AUTHORIZED,500");
            values.add("c" + i + ",p" + i + ",CAPTURED,500");
        }
        Topic topic = new Topic(values);
        FakeLedger ledger = new FakeLedger(10, 0); // the authorization write is slower than the capture write
        PaymentEventsConsumer c = new PaymentEventsConsumer(topic.consumer, ledger, topic.dlq, 8);
        Thread t = Topic.start(c);
        Topic.sleep(1_500);
        c.stop();
        t.join();
        long wrong = ledger.status.values().stream().filter(s -> s == PaymentEvent.Type.AUTHORIZED).count();
        System.out.println("P2 F2 50 payments AUTHORIZED then CAPTURED: " + wrong
                + " end in status AUTHORIZED (captured money shown as uncaptured)");
    }

    static void poisonPill() throws Exception {
        List<String> values = new ArrayList<>();
        for (int i = 0; i < 4; i++) {
            values.add("x" + i + ",px" + i + ",REFUND_REVERSED,500"); // v2 producer, v1 parser
        }
        values.addAll(authorizations(100, 0));
        Topic topic = new Topic(values);
        FakeLedger ledger = new FakeLedger(0, 0);
        PaymentEventsConsumer c = new PaymentEventsConsumer(topic.consumer, ledger, topic.dlq, 4);
        Thread t = Topic.start(c);
        Topic.sleep(800);
        long committed = topic.committed();
        System.out.println("P3 F3 4 REFUND_REVERSED events + 100 valid, 4 threads: applied " + ledger.applied()
                + ", dead-lettered " + topic.deadLettered.size() + ", committed " + committed + " (consumer lag "
                + (104 - committed) + ")");
        c.stop();
        t.join(2_000);
    }

    static void backpressure() throws Exception {
        Topic topic = new Topic(authorizations(20_000, 0));
        FakeLedger ledger = new FakeLedger(5, 5);
        PaymentEventsConsumer c = new PaymentEventsConsumer(topic.consumer, ledger, topic.dlq, 8);
        Thread t = Topic.start(c);
        Topic.sleep(300);
        long polled = topic.consumer.position(Topic.P0);
        System.out.println("P4 F4 slow ledger, 20,000 events available, after 300 ms: records held in memory (polled - applied) = "
                + n(polled - ledger.applied()) + " (one measured run)");
        c.stop();
        t.join(5_000);
    }

    static void rebalance() throws Exception {
        Topic topic = new Topic(authorizations(100, 0));
        FakeLedger ledger = new FakeLedger(5, 5);
        PaymentEventsConsumer c = new PaymentEventsConsumer(topic.consumer, ledger, topic.dlq, 8);
        Thread t = Topic.start(c);
        Topic.sleep(50);
        AtomicLong revokedAt = new AtomicLong(Long.MAX_VALUE);
        topic.consumer.schedulePollTask(() -> { // the group coordinator moves partition 0 to another consumer
            topic.consumer.rebalance(List.of());
            revokedAt.set(System.nanoTime());
        });
        Topic.sleep(1_500);
        long after = ledger.appliedAtNanos.stream().filter(ts -> ts > revokedAt.get()).count();
        System.out.println("P6 F6 partition revoked mid-batch: ledger writes by this consumer AFTER it lost the partition = "
                + after + " (one measured run)");
        c.stop();
        t.join(2_000);
    }
}
```

</details>

<details><summary><b>The refactor as a diff (PR → fixed)</b></summary>

```diff
diff --git a/ledger-consumer/src/main/java/com/acme/payments/PaymentEventsConsumer.java b/ledger-consumer/src/main/java/com/acme/payments/PaymentEventsConsumer.java
index 8c410f4..9f09fb6 100644
--- a/ledger-consumer/src/main/java/com/acme/payments/PaymentEventsConsumer.java
+++ b/ledger-consumer/src/main/java/com/acme/payments/PaymentEventsConsumer.java
@@ -1,24 +1,44 @@
 package com.acme.payments;
 
 import java.time.Duration;
+import java.util.Collection;
+import java.util.HashMap;
 import java.util.List;
+import java.util.Map;
 import java.util.Properties;
+import java.util.Set;
+import java.util.concurrent.ConcurrentHashMap;
+import java.util.concurrent.ExecutionException;
 import java.util.concurrent.ExecutorService;
 import java.util.concurrent.Executors;
+import java.util.concurrent.TimeUnit;
+import java.util.concurrent.atomic.AtomicInteger;
 import org.apache.kafka.clients.consumer.Consumer;
 import org.apache.kafka.clients.consumer.ConsumerConfig;
+import org.apache.kafka.clients.consumer.ConsumerRebalanceListener;
 import org.apache.kafka.clients.consumer.ConsumerRecord;
-import org.apache.kafka.clients.consumer.ConsumerRecords;
+import org.apache.kafka.clients.consumer.OffsetAndMetadata;
+import org.apache.kafka.common.TopicPartition;
+import org.apache.kafka.common.errors.WakeupException;
 import org.apache.kafka.common.serialization.StringDeserializer;
 
-/** Applies payments.events to the ledger. Parallel: lag reached 40 minutes on Black Friday. */
-public final class PaymentEventsConsumer implements Runnable {
+/**
+ * Applies payments.events to the ledger in parallel across partitions and in order within each partition (a
+ * partition always maps to the same single-threaded lane). Commits only offsets whose records are done, pauses
+ * partitions that run too far ahead, dead-letters what can never succeed, and drains before giving partitions up.
+ * Only the poll thread touches the consumer; stop() uses wakeup(), the consumer's one thread-safe method.
+ */
+public final class PaymentEventsConsumer implements Runnable, ConsumerRebalanceListener {
     public static final String TOPIC = "payments.events";
+    private static final int MAX_IN_FLIGHT_PER_PARTITION = 500;
+    private static final int MAX_ATTEMPTS = 5;
 
     private final Consumer<String, String> consumer;
     private final LedgerClient ledger;
     private final DeadLetters deadLetters;
-    private final ExecutorService workers;
+    private final ExecutorService[] lanes;
+    private final Map<TopicPartition, Long> done = new ConcurrentHashMap<>(); // next offset to commit
+    private final Map<TopicPartition, AtomicInteger> inFlight = new ConcurrentHashMap<>();
     private volatile boolean running = true;
 
     public PaymentEventsConsumer(Consumer<String, String> consumer, LedgerClient ledger, DeadLetters deadLetters,
@@ -26,7 +46,10 @@ public final class PaymentEventsConsumer implements Runnable {
         this.consumer = consumer;
         this.ledger = ledger;
         this.deadLetters = deadLetters;
-        this.workers = Executors.newFixedThreadPool(threads);
+        this.lanes = new ExecutorService[threads];
+        for (int i = 0; i < threads; i++) {
+            lanes[i] = Executors.newSingleThreadExecutor();
+        }
     }
 
     public static Properties config(String bootstrapServers, String groupId) {
@@ -35,44 +58,114 @@ public final class PaymentEventsConsumer implements Runnable {
         p.put(ConsumerConfig.GROUP_ID_CONFIG, groupId);
         p.put(ConsumerConfig.KEY_DESERIALIZER_CLASS_CONFIG, StringDeserializer.class.getName());
         p.put(ConsumerConfig.VALUE_DESERIALIZER_CLASS_CONFIG, StringDeserializer.class.getName());
-        p.put(ConsumerConfig.MAX_POLL_RECORDS_CONFIG, "1000"); // bigger batches now that processing is parallel
+        p.put(ConsumerConfig.ENABLE_AUTO_COMMIT_CONFIG, "false"); // we commit only what the ledger has applied
+        p.put(ConsumerConfig.PARTITION_ASSIGNMENT_STRATEGY_CONFIG,
+                "org.apache.kafka.clients.consumer.CooperativeStickyAssignor"); // no stop-the-world on deploys
         return p;
     }
 
     @Override
     public void run() {
-        consumer.subscribe(List.of(TOPIC));
-        while (running) {
-            ConsumerRecords<String, String> records = consumer.poll(Duration.ofMillis(100));
-            for (ConsumerRecord<String, String> r : records) {
-                workers.submit(() -> process(r));
+        try {
+            consumer.subscribe(List.of(TOPIC), this);
+            while (running) {
+                for (ConsumerRecord<String, String> r : consumer.poll(Duration.ofMillis(100))) {
+                    TopicPartition tp = new TopicPartition(r.topic(), r.partition());
+                    inFlight.computeIfAbsent(tp, k -> new AtomicInteger()).incrementAndGet();
+                    lane(tp).submit(() -> process(tp, r));
+                }
+                applyBackpressure();
+                commitDone();
+            }
+        } catch (WakeupException e) {
+            // stop() was called
+        } finally {
+            drain(Set.copyOf(inFlight.keySet()));
+            commitDone();
+            consumer.close();
+            for (ExecutorService lane : lanes) {
+                lane.shutdown();
             }
-            consumer.commitAsync(); // non-blocking, keeps the poll loop fast
         }
     }
 
     public void stop() {
         running = false;
-        workers.shutdownNow();
-        consumer.close();
+        consumer.wakeup();
     }
 
-    private void process(ConsumerRecord<String, String> r) {
-        for (int attempt = 1; ; attempt++) {
-            try {
-                ledger.apply(PaymentEvent.parse(r.value()));
-                return;
-            } catch (RuntimeException e) {
-                sleep(Math.min(1_000, 50L * attempt)); // ledger blips are transient: back off and retry
-            }
-        }
+    @Override
+    public void onPartitionsRevoked(Collection<TopicPartition> partitions) { // on the poll thread, inside poll()
+        drain(partitions);
+        commitDone();
+        partitions.forEach(tp -> {
+            done.remove(tp);
+            inFlight.remove(tp);
+        });
+    }
+
+    @Override
+    public void onPartitionsAssigned(Collection<TopicPartition> partitions) {
     }
 
-    private static void sleep(long millis) {
+    private void process(TopicPartition tp, ConsumerRecord<String, String> r) {
         try {
-            Thread.sleep(millis);
+            PaymentEvent event = PaymentEvent.parse(r.value());
+            for (int attempt = 1; ; attempt++) {
+                try {
+                    ledger.apply(event);
+                    break;
+                } catch (RuntimeException e) {
+                    if (attempt == MAX_ATTEMPTS) {
+                        deadLetters.send(r, e); // bounded: park it and keep the partition moving
+                        break;
+                    }
+                    Thread.sleep(Math.min(1_000, 50L * attempt));
+                }
+            }
+        } catch (IllegalArgumentException e) {
+            deadLetters.send(r, e); // unknown type or malformed: retrying cannot help
         } catch (InterruptedException e) {
             Thread.currentThread().interrupt();
+            return; // not done: the offset is not advanced, so the next owner reprocesses it
+        } finally {
+            inFlight.get(tp).decrementAndGet();
+        }
+        done.put(tp, r.offset() + 1);
+    }
+
+    private ExecutorService lane(TopicPartition tp) {
+        return lanes[Math.floorMod(tp.hashCode(), lanes.length)];
+    }
+
+    private void applyBackpressure() {
+        inFlight.forEach((tp, n) -> {
+            if (n.get() > MAX_IN_FLIGHT_PER_PARTITION) {
+                consumer.pause(Set.of(tp));
+            } else if (n.get() < MAX_IN_FLIGHT_PER_PARTITION / 2 && consumer.paused().contains(tp)) {
+                consumer.resume(Set.of(tp));
+            }
+        });
+    }
+
+    private void commitDone() {
+        Map<TopicPartition, OffsetAndMetadata> offsets = new HashMap<>();
+        done.forEach((tp, next) -> offsets.put(tp, new OffsetAndMetadata(next)));
+        if (!offsets.isEmpty()) {
+            consumer.commitSync(offsets);
+        }
+    }
+
+    private void drain(Collection<TopicPartition> partitions) { // FIFO lanes: a marker runs after earlier work
+        for (TopicPartition tp : partitions) {
+            try {
+                lane(tp).submit(() -> { }).get(30, TimeUnit.SECONDS);
+            } catch (InterruptedException e) {
+                Thread.currentThread().interrupt();
+                return;
+            } catch (ExecutionException | java.util.concurrent.TimeoutException e) {
+                throw new IllegalStateException("could not drain " + tp, e);
+            }
         }
     }
 }
diff --git a/ledger-consumer/src/test/java/com/acme/payments/PaymentEventsConsumerTest.java b/ledger-consumer/src/test/java/com/acme/payments/PaymentEventsConsumerTest.java
index 9341667..6c47af8 100644
--- a/ledger-consumer/src/test/java/com/acme/payments/PaymentEventsConsumerTest.java
+++ b/ledger-consumer/src/test/java/com/acme/payments/PaymentEventsConsumerTest.java
@@ -1,9 +1,11 @@
 package com.acme.payments;
 
 import static org.junit.jupiter.api.Assertions.assertEquals;
+import static org.junit.jupiter.api.Assertions.assertFalse;
 
 import java.util.ArrayList;
 import java.util.List;
+import org.apache.kafka.clients.consumer.ConsumerConfig;
 import org.junit.jupiter.api.Test;
 
 class PaymentEventsConsumerTest {
@@ -15,40 +17,58 @@ class PaymentEventsConsumerTest {
         return values;
     }
 
+    private static void runFor(PaymentEventsConsumer c, long millis) throws InterruptedException {
+        Thread t = Topic.start(c);
+        Topic.sleep(millis);
+        c.stop();
+        t.join();
+    }
+
     @Test
     void appliesAllEventsAndCommits() throws Exception {
         Topic topic = new Topic(authorizations(100));
         FakeLedger ledger = new FakeLedger(0, 0);
-        PaymentEventsConsumer c = new PaymentEventsConsumer(topic.consumer, ledger, topic.dlq, 8);
-        Thread t = Topic.start(c);
-        Topic.sleep(500);
-        c.stop();
-        t.join();
+        runFor(new PaymentEventsConsumer(topic.consumer, ledger, topic.dlq, 8), 500);
         assertEquals(100, ledger.applied());
         assertEquals(100, topic.committed());
     }
 
     @Test
-    void parallelIsFasterThanSequential() throws Exception {
-        Topic topic = new Topic(authorizations(80));
-        FakeLedger ledger = new FakeLedger(10, 10);
-        PaymentEventsConsumer c = new PaymentEventsConsumer(topic.consumer, ledger, topic.dlq, 8);
-        Thread t = Topic.start(c);
-        Topic.sleep(400); // 80 x 10 ms is 800 ms sequentially; 8 threads need ~100 ms
-        assertEquals(80, ledger.applied());
-        c.stop();
-        t.join();
+    void shutdownCommitsExactlyWhatWasApplied() throws Exception {
+        Topic topic = new Topic(authorizations(200));
+        FakeLedger ledger = new FakeLedger(5, 5);
+        runFor(new PaymentEventsConsumer(topic.consumer, ledger, topic.dlq, 8), 100);
+        assertEquals(ledger.applied(), topic.committed());
     }
 
     @Test
-    void retriesTransientLedgerFailures() throws Exception {
-        Topic topic = new Topic(List.of("e1,p1,AUTHORIZED,500"));
-        FlakyLedger ledger = new FlakyLedger(2);
-        PaymentEventsConsumer c = new PaymentEventsConsumer(topic.consumer, ledger, topic.dlq, 2);
-        Thread t = Topic.start(c);
-        Topic.sleep(500);
-        c.stop();
-        t.join();
-        assertEquals(1, ledger.successes);
+    void keepsEachPaymentsEventsInOrder() throws Exception {
+        List<String> values = new ArrayList<>();
+        for (int i = 0; i < 20; i++) {
+            values.add("a" + i + ",p" + i + ",AUTHORIZED,500");
+            values.add("c" + i + ",p" + i + ",CAPTURED,500");
+        }
+        Topic topic = new Topic(values);
+        FakeLedger ledger = new FakeLedger(10, 0);
+        runFor(new PaymentEventsConsumer(topic.consumer, ledger, topic.dlq, 8), 600);
+        assertFalse(ledger.status.containsValue(PaymentEvent.Type.AUTHORIZED));
+    }
+
+    @Test
+    void unknownEventTypesAreDeadLetteredAndThePartitionMoves() throws Exception {
+        List<String> values = new ArrayList<>(List.of("x1,p9,REFUND_REVERSED,500"));
+        values.addAll(authorizations(10));
+        Topic topic = new Topic(values);
+        FakeLedger ledger = new FakeLedger(0, 0);
+        runFor(new PaymentEventsConsumer(topic.consumer, ledger, topic.dlq, 2), 400);
+        assertEquals(List.of("x1,p9,REFUND_REVERSED,500"), topic.deadLettered);
+        assertEquals(10, ledger.applied());
+        assertEquals(11, topic.committed());
+    }
+
+    @Test
+    void autoCommitIsDisabled() {
+        assertEquals("false", PaymentEventsConsumer.config("localhost:9092", "ledger")
+                .get(ConsumerConfig.ENABLE_AUTO_COMMIT_CONFIG));
     }
 }
```

</details>

---

## 9. Scoring this PR

| # | Defect | Severity (weight) | Tier | Typically found by |
|---|---|---|---|---|
| F1 | Commit before processing | Sev-1 (5) | 2 | L5+ with Kafka experience |
| F2 | Ordering lost | Sev-1 (5) | 10 | L6+ (requires the key/partition model and the ledger's last-write-wins) |
| F3 | Poison pill + hidden lag | Sev-1 (5) | 10 | L6+ (requires the producer roadmap and the deleted DLQ path) |
| F7 | Shutdown loses committed work | Sev-1 (5) | 10 | L6+ |
| F4 | No backpressure | Sev-2 (3) | 10 | L6+ |
| F5 | Auto-commit re-enabled by deletion | Sev-2 (3) | 2 | L7 (it's a `-` line) |
| F6 | No rebalance listener | Sev-2 (3) | 10 | L6+ |
| F8 | Interrupt swallowed | Sev-2 (3) | 20 | L7 |

Total **32**. Most L5s find F1. Strong L6s add F2, F3 and F6. L7s read the removed lines (F5), follow the shutdown path to the interrupt handling (F7, F8), and connect F1 to F3 into the scariest sentence in this module: *"during the incident the lag dashboard will show zero."*

---

## 10. Failure modes (reviewers on this PR)

| Failure mode | What it looks like | Why it fails |
|---|---|---|
| Swapping `commitAsync` for `commitSync` | "Use commitSync for safety" | Still commits the poll position: same at-most-once |
| "Use a bigger pool" for lag | Raise threads to 64 | Amplifies F2 and F4 |
| Fixing F3 with a retry cap only | "Retry 5 times then skip" | Without a DLQ the skipped events vanish; without commit-after-process the cap doesn't matter |
| Missing deleted lines | Reviewing only `+` lines | F5 is a deletion |
| Ignoring the producer roadmap | "Parse errors are bugs, they won't happen" | The v2 event ships next sprint |
| Treating MockConsumer success as thread-safety | "Tests call stop() fine" | MockConsumer is synchronized; KafkaConsumer throws |

---

## 11. Bar-raiser chains

<details><summary><b>Q1 · "Why not keep the pool and just call `commitSync()` after `submit`?"</b></summary>

**Initial Prompt.** The most common half-fix.

**L5 Answer.** "commitSync waits for the commit, so it's safe."

**Why L5 Stalls.** `commitSync()` without arguments commits the *position*, the same offsets as `commitAsync()`. It waits for the broker, not for the workers.

**L7 Answer.** "Commit what's *done*, not what's polled: track the highest contiguous completed offset per partition and commit that map explicitly. With one ordered lane per partition, 'contiguous' is trivially the last finished record. With a shared pool you'd need a gap-tracking structure, and you'd still have the ordering bug."

</details>

<details><summary><b>Q2 · "At-least-once means duplicates. Is that acceptable for a ledger?"</b></summary>

**Initial Prompt.** Delivery semantics vs idempotency.

**L5 Answer.** "Duplicates are rare, so it's fine."

**Why L5 Stalls.** After the fix, duplicates are *guaranteed* on every crash and rebalance between apply and commit. "Rare" isn't a design.

**L7 Answer.** "At-least-once is the right default, and it makes idempotency the handler's job. Here the ledger's status update is naturally idempotent (setting CAPTURED twice is harmless), but the journal row isn't, so it needs a unique constraint on `event_id` with insert-if-absent. Exactly-once *effects* = at-least-once delivery + idempotent apply. Kafka transactions give exactly-once only for Kafka-to-Kafka pipelines, not for an external ledger."

</details>

<details><summary><b>Q3 · "How would you know in production that F3 is happening?"</b></summary>

**Initial Prompt.** Detection when the usual metric lies.

**L5 Answer.** "The lag alert would fire."

**Why L5 Stalls.** Not with commit-before-process: committed offsets advance, so lag is zero.

**L7 Answer.** "Measure progress at the *effect*, not the commit: the ledger's applied-event rate per partition versus the topic's produce rate, and the age of the oldest unapplied event (end-to-end latency from the event timestamp). Add a DLQ rate alert, plus a per-worker 'stuck on the same record for more than N minutes' gauge. After the fix, committed-offset lag becomes trustworthy again, because commits mean completion."

</details>

<details><summary><b>Q4 · "What causes a rebalance storm here, concretely?"</b></summary>

**Initial Prompt.** Systems-level causality.

**L5 Answer.** "Too many consumers joining and leaving."

**Why L5 Stalls.** It describes the symptom, not this PR's mechanism.

**L7 Answer.** "F4 buffers the whole backlog, the heap fills, and the pod is OOM-killed. The group rebalances and the next member inherits the backlog and repeats it. Each kill also loses queued records (F1) and leaves revoked work writing (F6). On the classic protocol with eager assignment, every rebalance stops the whole group. Fixes: backpressure (pause/resume) removes the trigger, cooperative-sticky or the KIP-848 consumer protocol limits each rebalance's blast radius, and static membership (`group.instance.id`) stops restarts from causing rebalances at all."

</details>

<details><summary><b>Q5 · "Should a parse failure ever be retried?"</b></summary>

**Initial Prompt.** Failure classification.

**L5 Answer.** "No, never retry parse errors."

**Why L5 Stalls.** Mostly right, but it misses the operational follow-up: DLQ'd v2 events must be *replayed* once the consumer understands v2, or the ledger permanently misses refund reversals.

**L7 Answer.** "Not in-line: a parse failure is permanent for this version of the code. Dead-letter it with the reason and the original offset, alert on the DLQ rate, and once the consumer supports v2 (a tolerant reader), replay the DLQ. Better still, coordinate with the producer team to ship consumer support *before* emitting new types (expand, then contract), and make the parser tolerant: unknown types counted and parked, not thrown."

</details>

<details><summary><b>Q6 · "The PR's tests use MockConsumer and pass. Why didn't they catch `close()` from another thread?"</b></summary>

**Initial Prompt.** Limits of test doubles.

**L5 Answer.** "The tests should use a real Kafka."

**Why L5 Stalls.** Reasonable, but it doesn't explain the gap. The gap is that MockConsumer is more permissive than the real client.

**L7 Answer.** "MockConsumer's methods are synchronized, so cross-thread calls just queue, while KafkaConsumer detects them and throws ConcurrentModificationException. Every test double encodes assumptions. Here it hides a documented contract. Keep MockConsumer for fast logic tests and add one integration test against a real broker (Testcontainers or an embedded KRaft broker) covering shutdown and rebalance. And in review, check thread-confinement rules against the javadoc, not against the double."

</details>

<details><summary><b>Q7 · "24 partitions, one lane each: is that enough throughput to clear 40 minutes of lag?"</b></summary>

**Initial Prompt.** Capacity math.

**L5 Answer.** "Add more threads if not."

**Why L5 Stalls.** More threads than partitions doesn't help with partition-ordered lanes. The math needs to come first.

**L7 Answer.** "At 4 ms per event, one lane does 250 events/s, and 24 lanes across the group do about 6,000/s. If Black Friday peaks above that, options in order: add partitions (a keyed-topic change: plan it with the producers, since the key-to-partition mapping changes), batch ledger writes per partition (often 10× fewer round trips), or key-hash lanes within a partition with contiguous-offset commits. Measure the produce rate first. The PR never stated a target."

</details>

<details><summary><b>Q8 · "Rank the findings."</b></summary>

**Initial Prompt.** Prioritization.

**L5 Answer.** "F1 first, then everything else equally."

**Why L5 Stalls.** Misses that F3 and F7 turn F1 from a crash-only issue into a *guaranteed* recurring loss.

**L7 Answer.** "F7 + F1 together: data loss on every deploy, starting with the first one. F3: the v2 rollout next sprint stops processing with healthy-looking lag. F2: wrong payment statuses at volume. Then F5 (it reintroduces loss even after F1 is fixed), F4 + F6 (the storm), F8 (pods that won't stop). This shouldn't merge in parts. The fix is one coherent rewrite, about 150 lines, and the probes in this module are its regression suite."

</details>

---

## 12. Checklist

- [ ] Where is the commit relative to completion? Commit only what's done.
- [ ] `enable.auto.commit` explicitly `false` for manual-commit consumers.
- [ ] Parallelism unit: partition (or key with offset tracking). Never a shared pool over a keyed topic.
- [ ] Backpressure: `pause`/`resume` on in-flight bounds.
- [ ] Permanent vs transient failures: DLQ vs bounded retry. Who replays the DLQ?
- [ ] `ConsumerRebalanceListener`: drain or abandon, then commit, before returning.
- [ ] Shutdown: `wakeup()` from outside; drain, commit and close on the poll thread.
- [ ] `InterruptedException` handled as "stop", never swallowed in a loop.
- [ ] Lag measured at the effect (applied events, event age), not only at the commit.
- [ ] Removed lines reviewed as carefully as added ones.

---

## 13. References

- Apache Kafka 4.2 javadoc: `KafkaConsumer` (multi-threaded processing, manual offset control, flow control). https://kafka.apache.org/42/javadoc/org/apache/kafka/clients/consumer/KafkaConsumer.html
- Apache Kafka 4.2 javadoc: `ConsumerRebalanceListener`. https://kafka.apache.org/42/javadoc/org/apache/kafka/clients/consumer/ConsumerRebalanceListener.html
- Apache Kafka 4.2 javadoc: `MockConsumer`. https://kafka.apache.org/42/javadoc/org/apache/kafka/clients/consumer/MockConsumer.html
- Apache Kafka: *KIP-848: The Next Generation of the Consumer Rebalance Protocol*. https://cwiki.apache.org/confluence/display/KAFKA/KIP-848%3A+The+Next+Generation+of+the+Consumer+Rebalance+Protocol
- Apache Kafka: *KIP-429: Kafka Consumer Incremental Rebalance Protocol*. https://cwiki.apache.org/confluence/display/KAFKA/KIP-429%3A+Kafka+Consumer+Incremental+Rebalance+Protocol
- Confluent Parallel Consumer (key-level parallelism with offset tracking). https://github.com/confluentinc/parallel-consumer
- Within this KB: [01-02 Layer 5 (tolerant readers)](../01-The-L7-Code-Review-Mental-Model-and-Rubric/02-the-7-layer-fault-scan-correctness-concurrency-io-compat-security.md#7-layer-5-data-and-wire-compatibility) · [PR06 Outbox](03-pr06-transactional-outbox-and-redis-distributed-lock-fencing-bugs.md) · [PR05 Beam](02-pr05-apache-beam-stateful-dofn-watermark-stall-and-coder-non-determinism.md)
