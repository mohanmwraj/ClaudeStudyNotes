# 5.8 Bar-Raiser Drill-Downs: Microservices Design Patterns

> Evidence: [5.1](01-Decomposition-Modular-Monolith-Strangler-Branch-by-Abstraction.md)–[5.7](07-Observability-Tracing-Correlation-IDs-Contract-Testing.md) (Spring Modulith 2.1.2, PostgreSQL 18.6, Kafka 4.2.2, Debezium 3.7, Pact 4.7.5, all run). These questions usually come in a system-design round; the drill-down is where the bar-raiser checks whether your boxes and arrows survive failures.
>
> 🎤 candidate · 🔍 interviewer probe · 🛡️ staff-level defense

---

## Drill 1: "We'll split our monolith into 12 microservices this quarter" 🔥

🎤 *"Microservices will let teams move faster."*

🔍 **Probe 1: What specifically is slow today, and does a network boundary fix it?**

<details><summary>🛡️ Defense</summary>

Name the actual constraint: merge conflicts and coordinated releases (team autonomy), one hot module that needs to scale differently, one unstable component taking everything down (fault isolation). A network boundary fixes those **only** if the boundary follows business capabilities and the data ownership follows it too. It adds latency, partial failure, contract versioning and eventual consistency. If the pain is "the code is tangled", microservices distribute the tangle.
</details>

🔍 **Probe 2: So what would you do first?**

<details><summary>🛡️ Defense</summary>

Make the monolith **modular and verified**: modules = business capabilities, public API types and events only, no cycles. With Spring Modulith that's a test: one shortcut into `inventory.internal` produced two violations, an encapsulation breach and a cycle ([5.1 §2.3](01-Decomposition-Modular-Monolith-Strangler-Branch-by-Abstraction.md)). Inter-module events go through the durable publication registry (verified: a failed listener stayed incomplete, then completed on resubmission). Then extract the modules that have a concrete reason to be separate, using the strangler fig with a routing facade.
</details>

🔍 **Probe 3 (L6): How do you know a module is ready to be extracted?**

<details><summary>🛡️ Defense</summary>

No cycles with other modules; communication only through its public API and events (no shared tables: enforce schema ownership with database roles, [5.2 §1](02-Data-Ownership-Database-per-Service.md)); transactions don't span it and its neighbors (or those flows already use events/sagas); a team owns it; its events are versioned contracts. Then extraction is mostly moving code and swapping in-process event delivery for Kafka, which Modulith's externalization supports from the same registry.
</details>

---

## Drill 2: "Place an order: Order, Inventory and Payment services" 🔥

🔍 **Probe 1: How do you keep them consistent without a distributed transaction?**

<details><summary>🛡️ Defense</summary>

A **saga**: local transactions with compensations. Order the steps: compensatable (create order `PENDING`, reserve stock), then the **pivot** (charge the card), then retriable (approve order). Verified ([5.3 §1](03-Sagas-Choreography-vs-Orchestration-Compensation-Semantic-Locks.md)): a declined payment compensated **in reverse order** (release stock, then reject the order), and a crash after step 2 resumed exactly at `next_step = 2` from the durable saga log.
</details>

🔍 **Probe 2: Between reserving stock and charging the card, another request reads the stock. What does it see?**

<details><summary>🛡️ Defense</summary>

The intermediate state: sagas have no isolation. That's acceptable only with countermeasures: a **semantic lock** (the order is `PENDING`; UIs show "processing", other sagas treat it as in flux), **commutative** compensations (`available = available + 1`, never an absolute write that could clobber another saga), and **reread value** checks where a step depends on data another saga may change.
</details>

🔍 **Probe 3: Choreography or orchestration?**

<details><summary>🛡️ Defense</summary>

Three steps with a clear owner (the order process): **orchestration**, so "where is order 42?" is a query, compensation order is explicit, and adding a fraud-check step is one change. Choreography fits short flows between autonomous domains. For long-running processes with timers, retries and human steps, a durable-execution engine (Temporal) instead of a hand-written saga log.
</details>

🔍 **Probe 4 (L6): The payment provider times out. Did we charge the customer?**

<details><summary>🛡️ Defense</summary>

Unknown, so the saga must treat "timeout" as **indeterminate**, not as failure. Send an **idempotency key** (the order id) with every charge request so a retry can't double-charge, and resolve uncertainty by **querying** the provider for that key before compensating. A reconciler sweeps sagas stuck in `CHARGING` for longer than N minutes. Never compensate a pivot whose outcome you don't know.
</details>

---

## Drill 3: "We save the order and then publish `OrderPlaced` to Kafka" 🔥

🔍 **Probe 1: What can go wrong?**

<details><summary>🛡️ Defense</summary>

It's a **dual write**. Crash between commit and send: the order exists and nobody hears about it. Send inside `@Transactional`: the event leaves before commit, so a rollback leaves a phantom event. `@TransactionalEventListener(AFTER_COMMIT)` still loses the event if the process dies after commit.
</details>

🔍 **Probe 2: Fix it, and tell me the delivery guarantee.**

<details><summary>🛡️ Defense</summary>

**Transactional outbox**: the order row and the event row in one local transaction, a relay publishes committed rows, sending first and marking published after the broker ack. That's **at-least-once**, so consumers are **idempotent**: a dedup row and the side effect in one transaction. Verified ([5.4 §5](04-Transactional-Outbox-and-Idempotent-Consumer-Complete-Implementation.md)): a relay crash after the Kafka ack left the row pending, the re-send was a duplicate, and the consumer ignored it (`duplicates_ignored=1`, still 4 shipments). A consumer crash after its side effect rolled back and redelivered, with exactly one shipment.
</details>

🔍 **Probe 3: We run 3 replicas of the service. Do we get 3 relays publishing everything 3 times?**

<details><summary>🛡️ Defense</summary>

Not with `FOR UPDATE SKIP LOCKED`: each relay claims rows the others haven't locked. Verified: two relays over 200 events published 100 each, **0** events sent twice. But `SKIP LOCKED` doesn't preserve per-aggregate ordering across relays (relay B can publish order 42's `Cancelled` before relay A publishes its `Placed`). If order matters: a single active relay (advisory lock), partitioned relays by `hash(aggregate_id)`, or version-aware consumers.
</details>

🔍 **Probe 4 (L6): Polling or Debezium?**

<details><summary>🛡️ Defense</summary>

Polling: simplest to own, ~poll-interval latency, writes `published_at` (bloat, vacuum). Debezium: reads the WAL, so it's push-based and adds no writes. Verified: it emitted an event for a row inserted and deleted in the same transaction (an always-empty outbox). The operational catch, also verified: a stopped connector's replication slot kept **3,056 kB** of WAL after 20,000 inserts and keeps growing, which can fill the disk. I'd choose polling for a few services and Debezium where a platform team runs CDC with slot-lag alerts and `max_slot_wal_keep_size`.
</details>

---

## Drill 4: "Build a searchable order history across Order, Payment and Shipping" ⚡

🔍 **Probe 1: Query all three services on every search?**

<details><summary>🛡️ Defense</summary>

For a detail page, API composition can work. For search with filters and sorting across services, no: latency compounds and one slow service breaks search. Build a **CQRS read model** (a search index or a denormalized table) fed by the three services' events. Queries become local; freshness is eventual (seconds).
</details>

🔍 **Probe 2: Your projector checkpoints the last event position it processed. Any risk?**

<details><summary>🛡️ Defense</summary>

Yes, if the position comes from a sequence. Positions are assigned at insert and become visible at commit, so a slow transaction can commit position 1 **after** the projector moved past 2. Verified ([5.5 §4](05-CQRS-and-Event-Sourcing.md)): event 1 was **never** projected, silently. Fixes: read in commit order (CDC/WAL or Kafka offsets), a single writer, or only consume events from transactions older than `pg_snapshot_xmin(pg_current_snapshot())` (verified: B's event was held back until A committed, then both arrived in order).
</details>

🔍 **Probe 3: A bug corrupted the read model for a week. Recovery?**

<details><summary>🛡️ Defense</summary>

Read models are **disposable**: fix the projector, rebuild into a new table/index by replaying from the beginning (Kafka retention or the event store), then switch reads over. Verified: dropping the read model and replaying gave identical balances. This only works if events are retained (compacted topics, an event store, or the outbox archive) and projectors are idempotent.
</details>

---

## Drill 5: "Should we use event sourcing for our order system?" 🧊

🔍 **Probe: Convince me either way.**

<details><summary>🛡️ Defense</summary>

Event sourcing earns its cost when **history is the product**: audit requirements, temporal queries, or new read models built from past events. It costs: event versioning forever (upcasters, crypto-shredding for GDPR), projections for every query, snapshot management, and team learning. Its concurrency story is simple: the `(stream_id, version)` key is the optimistic lock (verified: the second writer got 23505, reloaded, and its retried command was correctly rejected). For a typical order system I'd choose **CQRS + outbox events** over a normal relational write model, and keep event sourcing for genuinely ledger-like domains.
</details>

---

## Drill 6: "The order-details page takes 2+ seconds and sometimes errors" ⚡

🔍 **Probe: It calls Order, Shipping and Reviews. Redesign the aggregation.**

<details><summary>🛡️ Defense</summary>

Classify dependencies: order is **critical**, shipping and reviews are **optional**. Call them **in parallel** (virtual threads) with **per-call timeouts** inside an overall deadline, and **fallbacks** for optional parts. Verified ([5.6 §3](06-Edge-Patterns-Gateway-BFF-Aggregator-Service-Mesh.md)): sequential with no timeouts took **2,230 ms and failed** on a 503 from reviews; the hardened version answered in **308 ms** with `shipping: degraded` and empty reviews. Add circuit breakers per dependency, propagate the remaining deadline downstream, and if this page is hot, replace composition with a read model.
</details>

---

## Drill 7: "Should we adopt a service mesh?" 🧊

🔍 **Probe 1: What do we get?**

<details><summary>🛡️ Defense</summary>

Service identity and **mTLS** everywhere, uniform L4/L7 telemetry, declarative traffic management (canaries, mirroring), and policy-based retries/timeouts across languages. Cost: proxies (per pod with sidecars, per node with Istio ambient/Cilium eBPF), upgrade and debugging expertise, and another control plane.
</details>

🔍 **Probe 2: Our Java services already retry with Resilience4j. Any interaction?**

<details><summary>🛡️ Defense</summary>

Multiplicative retries: 3 app attempts × 3 mesh attempts = 9 calls per request during an outage, exactly when the dependency is least able to cope. Pick **one owner** for retries per hop (usually the mesh for idempotent calls, or the app when it needs business-aware retry logic), align timeouts so the inner timeout is shorter than the outer one, and use retry budgets.
</details>

---

## Drill 8: "Traces stop at the Kafka hop" ⚡

🔍 **Probe: Find and fix it.**

<details><summary>🛡️ Defense</summary>

Context propagation must be explicit at every transport change. Check: is observation enabled on the `KafkaTemplate` and listener containers (so `traceparent` goes into record headers)? With an outbox, was the `traceparent` saved in the outbox row and copied into the message by the relay? Also check hand-built HTTP clients. Verified in Boot 4: a `RestClient` without the `ObservationRegistry` creates no client span and sends no `traceparent` ([5.7 §1](07-Observability-Tracing-Correlation-IDs-Contract-Testing.md)), while the instrumented one carried trace `4bf92f35…` from the gateway through both services.
</details>

---

## Drill 9: "Our E2E test environment is always broken, but we can't stop breaking each other's APIs" ⚡

🔍 **Probe: What replaces it?**

<details><summary>🛡️ Defense</summary>

**Consumer-driven contracts.** Each consumer's tests generate a contract of what it actually uses (with matchers); each provider's CI replays every consumer's contract against its real code; a `can-i-deploy` check gates deployments using a Pact Broker. Verified ([5.7 §4](07-Observability-Tracing-Correlation-IDs-Contract-Testing.md)): renaming `available` → `availableQty` failed the **provider's** build with `Actual map is missing the following keys: available`, before deployment, without running the consumer. Keep a thin layer of E2E smoke tests for wiring, not for API compatibility.
</details>

---

## Drill 10: "Reporting needs data from five services. Can it just read their databases?" 🔥

🔍 **Probe: Why not?**

<details><summary>🛡️ Defense</summary>

Every table it reads becomes an API the owning team can no longer change, and analytical queries on OLTP primaries hurt production latency (and hold back VACUUM). Enforce ownership: separate roles and schemas (verified: `permission denied for schema orders`). Feed reporting through CDC/events into a warehouse, where joins across services are cheap and owned by the data team.
</details>

---

# Round 2: the patterns under failure (Batch 2 deep dive)

> Evidence for Round 2 is in [5.9](09-Microservices-Patterns-Catalog-Flows-Failure-Modes-Spring-Code.md) (catalog + run snippets), [5.10](10-Reference-Implementation-Saga-Orchestrator-Kafka-Outbox-Inbox-CQRS.md) (saga reference implementation, 11 failure modes, two identical runs), [5.11](11-Modular-Monolith-Blueprint-Spring-Modulith-Externalized-Events-Extraction.md) (Modulith outage drill) and the new verified sections of 5.1–5.7 (Spring Boot 4.1.2, Kafka 4.2.2, Spring Modulith 2.1.2, PostgreSQL 18.6). 🎤 candidate · 🔍 probe · 🛡️ staff-level defense.

---

## Drill 11: "The payment provider timed out, we compensated, and the customer was charged anyway" 🔥

🎤 *"Our saga treats a payment timeout as a decline and releases the stock."*

🔍 **Probe 1: What actually happened?**

<details><summary>🛡️ Defense</summary>

The timeout was **indeterminate**: the PSP authorized after we stopped waiting. Reproduced in [5.10 scenario 7](10-Reference-Implementation-Saga-Orchestrator-Kafka-Outbox-Inbox-CQRS.md#scenario-7-a-timeout-during-the-pivot-): `PAYING → COMPENSATING (timeout) → REJECTED`, then `PaymentAuthorized` arrived. The pivot had happened, so the saga can only move **forward**: `RefundPayment`, and the final payment was `REFUNDED 40.00`. A state machine without that branch would have ignored or crashed on the reply and kept the money.
</details>

🔍 **Probe 2: How do you avoid the refund path in the first place?**

<details><summary>🛡️ Defense</summary>

* Send an **idempotency key** (the order id) with every PSP call.
* On timeout, **query the PSP by that key** before deciding.
* Give the pivot step a timeout longer than the PSP's own.
* Keep the late-reply refund branch as the safety net, and alert on its rate: it should be rare.

Note the call to the PSP must happen *outside* the DB transaction. Record the intent, call, then record the result.
</details>

---

## Drill 12: "We replayed yesterday's messages after an incident and some customers got two shipments" 🔥

🎤 *"Our consumer checks whether the message id was seen before processing it."*

🔍 **Probe 1: Where is the "seen" record written, relative to the side effect?**

<details><summary>🛡️ Defense</summary>

It has to be the **same local transaction** as the side effect. Then a crash either keeps both or neither. Verified: [5.10 scenario 5](10-Reference-Implementation-Saga-Orchestrator-Kafka-Outbox-Inbox-CQRS.md#scenario-5-crash-between-deciding-and-committing) threw after writing the state change, the inbox row and the outgoing command. All rolled back, the redelivery was processed once, and there was exactly one `AuthorizePayment`. A check-then-act ("select, then process, then insert") races under concurrency, and an inbox committed separately loses the effect forever on a crash.
</details>

🔍 **Probe 2: Prove the system is exactly-once in *effect*.**

<details><summary>🛡️ Defense</summary>

Re-deliver everything and **reconcile**. 5.10 scenario 2 reset `published_at` on all six messages of a finished saga: 2 + 1 + 1 duplicates dropped by inboxes, 2 by the projector's version guard, 0 new transitions, stock unchanged. Then §7 accounted for every send (702/217/61) against inbox rows (276/216/60). For synchronous POSTs the same idea is an **idempotency key**: 5 concurrent retries → 1 effect, 5 identical responses ([5.9 §8.3](09-Microservices-Patterns-Catalog-Flows-Failure-Modes-Spring-Code.md)).
</details>

---

## Drill 13: "One bad message stopped order processing for 40 minutes" ⚡

🎤 *"The listener throws, the error handler retries, and the partition is stuck behind it."*

🔍 **Probe: Design the error policy.**

<details><summary>🛡️ Defense</summary>

**Classify** exceptions. Transient ones get short in-place retries; everything else is dead-lettered and the partition moves on. Verified ([5.10 scenario 9](10-Reference-Implementation-Saga-Orchestrator-Kafka-Outbox-Inbox-CQRS.md#scenario-9-poison-messages)):

* a reply for a non-existent saga (`EmptyResultDataAccessException`, marked not retryable) took **1** attempt;
* a header-less record (`NullPointerException`, retryable by default) took **4**;
* both landed in `order.replies.DLT` with the original topic, group and cause in headers;
* the next order was `APPROVED`.

Long back-offs belong in non-blocking retry topics, but those break per-key order, which saga replies need. Add a DLT runbook (alert on depth, fix, re-drive with original headers) and a total state machine, so late or duplicate replies are recorded, not thrown.
</details>

---

## Drill 14: "We oversold the last 10 units during a flash sale" ⚡

🎤 *"Inventory reads the stock, checks it, then updates it, inside a transaction."*

🔍 **Probe 1: Why doesn't the transaction protect you?**

<details><summary>🛡️ Defense</summary>

Read-check-write under `READ COMMITTED` is a lost update: two transactions read 1, both write 0. Make the check **part of the write**: `update stock set available = available - ? where sku = ? and available >= ?`, with a `check (available >= 0)` constraint. The row lock serializes it in the database. Verified ([5.10 scenario 10](10-Reference-Implementation-Saga-Orchestrator-Kafka-Outbox-Inbox-CQRS.md#scenario-10-contention-without-distributed-locks)): 200 concurrent orders for 50 units with 3 consumers gave 50 approved, 150 rejected, stock 0 and no negative rows.
</details>

🔍 **Probe 2 (L6): The saga releases stock on compensation. What can go wrong?**

<details><summary>🛡️ Defense</summary>

* **Absolute writes clobber concurrent sagas:** compensations must be **commutative** (`available + qty`), never `set available = 50`.
* **A release that runs before its reservation must not be undone later:** a **tombstone** makes release-then-reserve end as "not reserved".
* **Retried compensations must be idempotent:** 5.10 scenario 8 re-sent `ReleaseStock`, and stock was released once.
</details>

---

## Drill 15: "Kafka is down for an hour of maintenance. Can we still take orders?" 🔥

🔍 **Probe: Walk through what happens to an order placed during the outage.**

<details><summary>🛡️ Defense</summary>

With an outbox, yes: Kafka is not on the write path. Verified twice:

* **5.10:** relays retry and catch up.
* **[5.11 §4](11-Modular-Monolith-Blueprint-Spring-Modulith-Externalized-Events-Extraction.md#4-outage-and-restart-drill-verified-), Modulith's registry-backed `@Externalized`:**
  * a new process started with the broker unreachable;
  * `place()` committed and returned in **14 ms**;
  * the externalization failed after `max.block.ms` on an executor thread (`FAILED, attempts=1`);
  * after a restart with `republish-outstanding-events-on-restart`, it reached Kafka (`COMPLETED, attempts=2`).

The costs are latency to downstream consumers, an alert on the age of the oldest unpublished row, and care with re-drive in a cluster. Restart republication runs on *every* instance, so prefer one scheduled `resubmitIncompletePublicationsOlderThan` behind a lock.
</details>

---

## Drill 16: "Extract the inventory module into its own service" 🔥

🔍 **Probe 1: How do you know it's extractable?**

<details><summary>🛡️ Defense</summary>

* **Its boundaries are enforced**, not hoped for: `ApplicationModules.verify()` in CI. One illegal use of a non-exposed type produced three violations with line numbers.
* **It boots alone:** `@ApplicationModuleTest` STANDALONE started inventory with **0** beans from other modules, and its only input was the `OrderPlaced` event. A module that only boots with all its dependencies isn't extractable yet ([5.11 §2, §5](11-Modular-Monolith-Blueprint-Spring-Modulith-Externalized-Events-Extraction.md#5-module-integration-tests-with-scenario-verified-)).
</details>

🔍 **Probe 2: The new service can't deserialize the events. Why?**

<details><summary>🛡️ Defense</summary>

Verified on the wire: every externalized record carried **`__TypeId__=com.acme.shop.order.OrderPlaced`**, the monolith's class name. A consumer using type headers tries to load a class that doesn't exist in its codebase. Either ignore type headers and bind to the consumer's own type (`spring.json.use.type.headers=false` + a default type), or map logical type ids on both sides. Then version the payload, add message contract tests, and give the new service an **inbox**: Kafka delivery is at-least-once, unlike the in-process listener it replaces.
</details>

🔍 **Probe 3 (L6): Sequence the cutover.**

<details><summary>🛡️ Defense</summary>

1. Externalize the event: the topic is now the contract.
2. Run the service in **shadow mode** (own DB, no side effects) and reconcile its state with the module's.
3. Flip a flag that disables the in-process listener and enables the service's effects.
4. Move the module's tables, then delete the module.

Every step until the last is reversible. That's branch by abstraction with a topic as the abstraction.
</details>

---

## Drill 17: "The order-history page sometimes shows an order as pending after it was approved, and once showed nothing" ⚡

🔍 **Probe 1: Explain both symptoms.**

<details><summary>🛡️ Defense</summary>

* **"Nothing" is read-your-writes on an eventually consistent read model.** Verified in [5.10 scenario 11](10-Reference-Implementation-Saga-Orchestrator-Kafka-Outbox-Inbox-CQRS.md#scenario-11-cqrs-guarantees): right after `place()` returned, the view row didn't exist. The fix: the command returns a version, and the client waits for it (43 ms in one run) or reads the write model briefly.
* **"Pending after approved"** is either projection lag (p99 224 ms under a 200-order burst) or a projector that applied an older event *after* a newer one: a replay, a rebuild overlap, or a second consumer.
</details>

🔍 **Probe 2: Make the projector immune to the second cause.**

<details><summary>🛡️ Defense</summary>

Carry a per-aggregate **version** in every event and upsert with `on conflict … do update … where v.version < excluded.version`. Duplicates and older events become no-ops (verified: 420 applied, 2 skipped), and a full replay from offset 0 produced a table identical to the live one (0 differing rows). That also makes the read model **disposable**: rebuild into a new table, compare, swap.
</details>

---

## Drill 18: "We need to rename `amount` to `total` in `OrderPlaced`. Six teams consume it." 🧊

🔍 **Probe: Plan it, and tell me what could still go wrong.**

<details><summary>🛡️ Defense</summary>

1. **Never rename in place.** Ship v2 additively (both fields, or `schemaVersion` + tolerant readers), and upcast v1 on read, including replays.
2. **Use Pact message contracts** to see which consumers still read `amount`.
3. **Stop writing it only after `can-i-deploy` agrees.**

What still went wrong in my verification ([5.9 §8.4](09-Microservices-Patterns-Catalog-Flows-Failure-Modes-Spring-Code.md)): the upcaster's logic was correct, but the default Jackson parser turned `25.00` into `25.0` (a `double`) before it ran. Every parser on the path needs `USE_BIG_DECIMAL_FOR_FLOATS`, or money as minor units. Contract tests should assert scale.
</details>

---

## L5 vs L6 signal

| Topic | L5 | L6 |
|---|---|---|
| Decomposition | Splits by entity/service names | Splits by capability and consistency boundary; modular monolith with verified boundaries first |
| Sagas | Knows compensations | Pivot ordering, isolation countermeasures, indeterminate outcomes, durable execution |
| Outbox | Knows the pattern | Proves the guarantees under crashes, handles relay concurrency and ordering, knows CDC's slot risk |
| CQRS/ES | Builds a read model | Knows projection gaps, replay, event versioning, when not to use ES |
| Edge | Puts a gateway in front | Deadlines, critical vs optional dependencies, one retry owner per hop |
| Testing | E2E tests | Consumer-driven contracts with `can-i-deploy` |
| Saga failure modes (Round 2) | Compensates on failure | Treats timeouts as indeterminate, refunds late pivots, keeps the state machine total, retries idempotent compensations |
| Effects (Round 2) | Dedups by message id | Inbox in the effect's transaction; idempotency keys for synchronous APIs; proves it by re-delivery and reconciliation |
| Poison messages (Round 2) | Adds a DLT | Classifies exceptions, keeps per-key order, owns the re-drive runbook |
| Outages (Round 2) | "Kafka is highly available" | Keeps the broker off the write path; monitors outbox age; re-drives safely in a cluster |
| Extraction (Round 2) | Moves code into a new repo | Proves isolation with module tests, makes the topic the contract, shadows, cuts over with an inbox |
| Read models (Round 2) | Builds a projection | Version guard, rebuild-and-swap, read-your-writes by version |

## Red flags

* "We use 2PC between services."
* "We publish to Kafka inside the transaction."
* "Kafka gives us exactly-once, so consumers don't need deduplication."
* "Services can read each other's tables for reporting."
* "Compensation is just deleting the row."
* "A payment timeout means the payment failed."
* "We check the inbox, then process, then record it."
* "Retry the message until it succeeds."
* "Read the stock, check it, then update it."
* "We'll just rename the field; consumers will update."
* "The new service can reuse the monolith's event classes."

---

## Rapid-fire flashcards

<details><summary>1. What does a service boundary also define?</summary>A consistency (transaction) boundary.</details>

<details><summary>2. Spring Modulith module = ?</summary>A direct sub-package of the application's main package; its top-level package is its API.</details>

<details><summary>3. What does `@ApplicationModuleListener` combine?</summary>`@Async` + `@TransactionalEventListener` (after commit) + `@Transactional(REQUIRES_NEW)`.</details>

<details><summary>4. Strangler fig steps?</summary>Facade, pick a seam, build new, sync data, shift traffic gradually, delete old.</details>

<details><summary>5. Why avoid 2PC across services?</summary>Locks across the network, in-doubt transactions, availability = product of participants, many systems don't support XA.</details>

<details><summary>6. Saga step types?</summary>Compensatable, pivot, retriable.</details>

<details><summary>7. Compensation order?</summary>Reverse order of completed steps.</details>

<details><summary>8. Semantic lock?</summary>An application-level "in progress" state (e.g. `PENDING`) visible to other transactions.</details>

<details><summary>9. Outbox delivery guarantee?</summary>At-least-once; exactly-once effects need idempotent consumers.</details>

<details><summary>10. Relay order of operations?</summary>Send, wait for the ack, then mark published.</details>

<details><summary>11. How do multiple relays avoid double sends?</summary>`FOR UPDATE SKIP LOCKED`.</details>

<details><summary>12. What doesn't `SKIP LOCKED` preserve?</summary>Per-aggregate ordering across relays.</details>

<details><summary>13. CDC operational risk?</summary>Replication slots retain WAL (and hold back catalog_xmin) while the consumer is down.</details>

<details><summary>14. Insert-then-delete outbox trick?</summary>CDC still sees the INSERT in the WAL; the table stays empty.</details>

<details><summary>15. Event store optimistic lock?</summary>Unique `(stream_id, version)`.</details>

<details><summary>16. Why can sequence-based projectors miss events?</summary>Positions are assigned at insert, visible at commit; out-of-order commits get skipped.</details>

<details><summary>17. Read models are…?</summary>Disposable: rebuild by replay.</details>

<details><summary>18. Aggregator rules?</summary>Parallel calls, per-call timeouts within a deadline, fallbacks for optional data.</details>

<details><summary>19. BFF owner?</summary>The team owning that client experience.</details>

<details><summary>20. Sidecar vs ambient?</summary>Proxy per pod vs per-node L4 agent + optional L7 waypoints.</details>

<details><summary>21. W3C traceparent fields?</summary>version-traceid-parentid-flags.</details>

<details><summary>22. Head vs tail sampling?</summary>Decision at trace start vs after completion (keeps errors/slow traces).</details>

<details><summary>23. What does a consumer-driven contract capture?</summary>Only what the consumer uses, with matchers.</details>

<details><summary>24. Pact gate before deploy?</summary>`can-i-deploy` against the Pact Broker.</details>

<details><summary>25. What is a late pivot reply, and the only correct response?</summary>A success for the irreversible step after the saga gave up on it; a forward action (refund).</details>

<details><summary>26. Why must an orchestrator's state machine be total?</summary>Duplicates and late replies are guaranteed; unhandled pairs become poison messages.</details>

<details><summary>27. What does a tombstone in a compensation protect against?</summary>A release that runs before its reservation being undone by the late reservation.</details>

<details><summary>28. Reply handler vs timeout sweeper: how do they avoid double transitions?</summary>The handler takes `FOR UPDATE`, the sweeper `FOR UPDATE SKIP LOCKED`; the first to lock wins.</details>

<details><summary>29. Why must the inbox row share the effect's transaction?</summary>A crash otherwise records "seen" without the effect (lost forever) or vice versa.</details>

<details><summary>30. How do you prevent overselling without distributed locks?</summary>An atomic conditional update (`where available >= qty`) plus a check constraint.</details>

<details><summary>31. Which exceptions should skip retries and go to the DLT?</summary>Non-transient ones (unknown saga, malformed message); classify them explicitly.</details>

<details><summary>32. Why avoid non-blocking retry topics for saga replies?</summary>They break per-key ordering.</details>

<details><summary>33. What makes a Kafka-fed projection idempotent and order-safe?</summary>A per-aggregate version and `where v.version < excluded.version`.</details>

<details><summary>34. How does a client read its own write from a CQRS view?</summary>The command returns the version; the client waits for it (or reads the write model briefly).</details>

<details><summary>35. What header did Modulith's Kafka externalization add, and why does it matter?</summary>`__TypeId__` with the producer's class name; other codebases can't load it.</details>

<details><summary>36. What does `republish-outstanding-events-on-restart` risk in a cluster?</summary>Every starting instance re-drives the same publications concurrently.</details>

<details><summary>37. Idempotency key arbitration?</summary>`insert … on conflict do nothing` in the effect's transaction; concurrent twins block, then replay the stored response.</details>

<details><summary>38. Jackson trap for money in JSON?</summary>Decimals parse as `double` (`25.00` → `25.0`) without `USE_BIG_DECIMAL_FOR_FLOATS`.</details>

---

## Summary

| Round | Drills | What it tests |
|---|---|---|
| Round 1 (1–10) | Splitting a monolith, the order saga, dual write, cross-service history, event sourcing, slow details page, service mesh, broken traces, broken E2E env, cross-service reporting | Choosing patterns and defending the boxes and arrows |
| Round 2 (11–18) | Late pivot, replays doubling effects, poison messages, overselling, broker outage, module extraction, stale read models, renaming an event field | The same patterns under failure: timeouts, duplicates, ordering, outages, contracts, all reproduced in 5.9–5.11 |

**Next pillar:** [6.1 Resilience4j circuit breaker internals →](../06-Resilience-Caching/01-Resilience4j-Circuit-Breaker-Internals-Sliding-Windows.md)
