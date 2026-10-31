# 03.2 · Archetype B: Financial/Commerce Microservices Modernization (Java, Spring Boot, SQL, Idempotency, Saga)

> **Folder:** `03-Complete-L7-Whiteboard-Blueprints-for-4-Career-Archetypes` · file 2 of 4
> **Question this file answers:** I led the modernization of a money-moving monolith into services: payments, ledger, checkout, inventory. What does the whiteboard look like, and how do I defend idempotency, sagas, SQL performance and resiliency against Principal Engineers who have debugged double charges at 3 a.m.?
> **Composite exhibit:** "Tillpoint", a commerce company's checkout and payments platform. It was previewed in [02.1](../02-The-3-Viable-Options-Tradeoff-Defense-Framework/01-proving-first-principles-why-you-rejected-option-a-and-option-b.md) and [02.2](../02-The-3-Viable-Options-Tradeoff-Defense-Framework/02-quantifying-bottlenecks-before-and-after-latency-throughput-and-finops-math.md). The numbers are placeholders.
> **Scope labels:** L5 = Senior, L6 = Staff, L7 = Principal / Senior Staff.

| Listing | Language | What it does | Where it runs |
|---|---|---|---|
| L8 `TillpointLedger.java` | Java 21 source level, plain JDBC, PostgreSQL 18 (embedded) | It runs against a real PostgreSQL 18 and checks five things: <br>1. idempotency keys under 8 concurrent identical requests (exactly 1 charge); <br>2. double-entry ledger invariants; <br>3. a transactional outbox drained by 2 relays with `FOR UPDATE SKIP LOCKED`; <br>4. an orchestrated saga whose compensation is delivered twice and applied once; <br>5. `EXPLAIN ANALYZE` before and after a partial composite index. | [§12](#12-listing-and-output), compiled with `-Xlint:all -Werror` and run on JDK 25 |

**Verification.** The gate extracts the listing, checks it byte for byte against the source, compiles and runs it against an embedded PostgreSQL 18.6 (the binaries come from Maven Central, SHA-1 verified), and compares the output with §12. The program prints `verdict: OK` only if all of its checks pass. The plan output is shown with `COSTS OFF, TIMING OFF, BUFFERS OFF`, so it is deterministic. The ledger in §9 and the tellings are checked by the Folder 01 tools. Results are in the [README](../README.md#gate-results).

---

## 0. Orientation

**Who this archetype fits.** Engineers who broke a payments, banking, ordering or checkout monolith into services, typically in Java and Spring Boot with a relational database per service. Typical résumé lines: "decomposed a monolith into N microservices", "implemented the saga pattern", "reduced latency by X% through SQL tuning", "built idempotent payment APIs".

**Why it's dangerous in a deep dive.** Money makes every bug a story the interviewers have lived through: the double charge, the lost refund, the oversold stock, the ledger that doesn't balance. They'll test whether your idempotency survives concurrency, whether your saga's compensations are themselves idempotent, whether your "microservices" are justified (02.1 §4.3–§4.5), and whether your SQL claims come with plans.

---

## 1. First principles: what interviewers assume about this archetype

### 1.1 The attack surface

| Claim | What they suspect | The probe | What survives |
|---|---|---|---|
| "Idempotent payment API" | A uniqueness check that races | "Two identical requests at the same millisecond. Show me the SQL." | A unique constraint as the arbiter, with payload-hash and in-progress semantics (§4) |
| "Saga pattern" | Compensations that aren't idempotent | "Your compensation event is delivered twice." | State-guarded transitions; compensation as a forward step (§5) |
| "Microservices for scale" | Throughput that a single database could handle | "Why not one Postgres?" | The concession (36% at peak) and the real reasons: PCI scope and deploy coupling (02.1 §4.6) |
| "Reduced latency 40%" | An unattributed delta | "Prove it." | Canary vs control; the p50/p99 shape (02.2 §9) |
| "Resilient: retries and circuit breakers" | Retry amplification | "Three layers retry three times each. What does the gateway see?" | Retry budgets, jitter, retries at one layer only (§7) |

### 1.2 The invariants that money systems must hold

1. **No double effect:** one customer intent produces at most one charge.
2. **No lost effect:** a captured payment is never forgotten; refunds and settlements reconcile.
3. **The ledger balances:** every transaction's entries sum to zero; balances are derived from entries, never stored independently.
4. **Stock is conserved:** reservations plus available stock equal physical stock.

Every mechanism in this file exists to keep one of those true, under concurrency, retries and partial failure.

---

## 2. The composite project: "Tillpoint" fact sheet

### 2.1 Before-state

- **Monolith:** `store-core`, a Spring Boot 2 application on one PostgreSQL primary with 2 replicas.
- **PCI scope:** card data passed through the order code path, so all **140 hosts** of the order cluster were in PCI scope.
- **Deploys:** 14 teams shared a 45-minute serialized release train, so ρ = 3.15 and deploys were batched about 3 changes each (02.2 §7).
- **Checkout:**
  - 40 synchronous internal and external calls; p99 **238 ms**.
  - Peak 2,400 orders/s against a mean of 300 (8×).
  - The connection pool was undersized against **432** concurrent checkouts (02.2 Q10).
- **Incident INC-P3 (Black Friday, the year before):**
  - Payment-gateway timeouts triggered client and server retries.
  - **1,214 customers were charged twice** in 40 minutes.
  - Refunds took 9 days; the customer-support cost was about $180k.

### 2.2 Goals and kill criteria

| ID | Goal | Threshold | Kind |
|---|---|---|---|
| K1 | No double charge under retries, timeouts or concurrency | 0 duplicate captures per idempotency key | Kill |
| K2 | Ledger balances | Every payment's entries sum to 0; daily settlement reconciles to the gateway file | Kill |
| K3 | PCI scope | Card data reaches only the tokenization service | Kill |
| K4 | Checkout availability | ≥ 99.9% (critical path ≤ 2 synchronous dependencies) | Kill |
| G5 | Checkout p99 | ≤ 160 ms at peak | Scored |
| G6 | Independent deploys | Each team deploys without the train | Scored |

### 2.3 Architecture after (ownership marked)

| # | Component | Mark | What it does |
|---|---|---|---|
| B1 | Edge tokenization service | ◆ (designed by the security architect; I reviewed it and integrated checkout) | Card data in, token out; the only PCI-scoped component (12 hosts) |
| B2 | Checkout orchestrator | ★ designed the saga and the state machine | Reserve inventory → authorize payment → confirm order; compensations on failure |
| B3 | Payments service | ★ idempotency design; ○ gateway adapter (payments team) | Idempotency keys on every POST; passes its key to the gateway; reconciles timeouts by query |
| B4 | Ledger service | ★ invariants and schema | Double-entry, append-only, balances derived; daily settlement reconciliation |
| B5 | Inventory service | ★ the hot-SKU bucket design; ○ the service itself | Reservations with a TTL; per-SKU stock split into buckets for hot items |
| B6 | Transactional outbox + relays | ★ | Events committed in the same transaction as the state change; relays publish to Kafka with `SKIP LOCKED` |
| B7 | Asynchronous consumers (notifications, loyalty, analytics) | ○ | Off the critical path; idempotent by event id |
| B8 | Resilience layer (timeouts, retries, circuit breakers) | ◆ policy and budgets; ○ libraries | One retry layer; deadlines propagated; jittered backoff |

### 2.4 Scale, team, timeline, outcomes

| Fact | Value | Provenance |
|---|---|---|
| Peak orders | ~2,400/s (8× mean) | [M] |
| Order-write fit on one primary | 14,400 rows/s vs 40,000 measured, so **36%** at peak | [M]/[E] (02.1 §4.6) |
| PCI in-scope hosts | 140 → 12 (~$230k/yr audit and evidence work) | [M]/[E] |
| Checkout synchronous dependencies | 5 → 2 (99.75% → 99.90% composed) | [E] |
| Fan-out | 40 → 12 calls; tail exposure 33.1% → 11.4% | [E] |
| Checkout p99 | 238 → 141 ms (2-week canary vs control) | [M] |
| Primary CPU at peak | 85% → 61%; commit p99 31 → 9 ms | [M] |
| Duplicate captures | 1,214 (INC-P3) → 0 in 2 peak seasons since | [M] |
| Team | Me (staff engineer, architecture across 4 teams), ~22 engineers across payments, checkout, ledger and inventory | — |
| Timeline | 18-month strangler migration; payments and ledger first (K1–K3), checkout orchestration in month 9, inventory buckets before the second peak season | — |

---

## 3. The whiteboard blueprint

```text
 ENTERPRISE BAND (thin): card networks/gateway (o) | Kafka (o) | identity (o) | 14 product teams (o) | settlement files (o)

 client --> API edge --> [[ TOKENIZATION <> ]] (PCI zone: 12 hosts) -- token -->
                                                                  |
             [[ CHECKOUT ORCHESTRATOR * ]]  saga: RESERVED -> AUTHORIZED -> CONFIRMED | PAYMENT_FAILED -> COMPENSATED
                |  sync (deadline 120 ms)          |  sync (deadline 300 ms)
                v                                  v
        [[ INVENTORY * buckets ]]           [[ PAYMENTS * idempotency ]] --(Idempotency-Key)--> gateway (o)
         PG: reservations, TTL                PG: idempotency_keys, payments
                                                   |  same tx
                                                   v
                                            [[ LEDGER * double-entry ]]  PG: entries (append-only), sum = 0
         every service: [[ OUTBOX * ]] -- relays, SKIP LOCKED --> Kafka --> notifications / loyalty / analytics (o, async)
 numbers: 2,400 orders/s peak | 36% of 1 primary | PCI 140->12 hosts | p99 238->141 ms | 0 double charges
```

| Phase | What to draw and say for Archetype B |
|---|---|
| Context | INC-P3 (1,214 double charges), PCI scope (140 hosts), the deploy train (ρ 3.15), checkout p99 238 ms |
| Architecture | The tokenization boundary first (it explains the split), then the saga path, then the outbox |
| Depth menu | (1) idempotency under concurrency, (2) the saga and its compensations, (3) SQL: ledger invariants, the index, transaction boundaries, hot rows |
| Failure | INC-P9: the compensation replay that over-released stock (§6) |
| Trade-offs | Monolith with fixed pipeline vs modular monolith vs services (02.1 §4.5); 2PC vs saga (Q6) |
| Hindsight | Integer minor units + currency code (02.3 §3.1) |

#### How an L5 tells it

> I worked on breaking up our monolith into microservices for payments and checkout. We used Spring Boot and Kafka, and implemented the saga pattern and idempotency so it was robust. It made the system a lot more scalable and we stopped having double-charge issues.

#### How an L7 tells it

> Tillpoint split a commerce monolith's checkout and payments into services over 18 months. Two facts forced it, and throughput wasn't one of them: one primary ran our peak at about 36% of its measured capacity. Card data crossed the order code, which put 140 hosts in PCI scope, and the year before, gateway timeouts plus layered retries charged 1,214 customers twice in 40 minutes. I was the staff engineer across the payments, checkout, ledger and inventory teams. I designed the idempotency scheme, the checkout saga and its compensations, the ledger's double-entry invariants and the outbox. PCI scope went from 140 hosts to 12, checkout p99 from 238 to 141 milliseconds in a controlled canary, and 2 peak seasons have passed with 0 duplicate captures.

---

## 4. Deep well 1: idempotency under concurrency

### 4.1 Semantics, precisely

| Decision | Tillpoint's choice | Why |
|---|---|---|
| **Who generates the key** | The client, once per customer intent (per checkout attempt), reused on every retry | Only the client knows that two requests are the same intent |
| **Scope** | Per API operation and per merchant account | The same key on a different operation is a different intent |
| **Arbiter** | A `PRIMARY KEY` on `idempotency_keys(key)` with `INSERT … ON CONFLICT DO NOTHING` | The database's uniqueness check is atomic. A `SELECT`-then-`INSERT` races (Q1) |
| **Payload binding** | A SHA-256 of the canonical request is stored with the key; a mismatch → **422** | A reused key with a different amount is a client bug, never a replay |
| **In-flight** | A key claimed but not completed → **409**, retry later | Prevents two executions; the client backs off |
| **Replay** | The stored response is returned (**200**) | A retry looks exactly like the original success |
| **Atomicity** | The key row, payment, ledger entries and outbox event commit in **one transaction** | No state where the key says "done" but the payment is missing, or the reverse |
| **TTL** | 24 h; then keys expire | Bounded table; client retries end well before then |

Stripe's public API documentation describes a similar client-supplied idempotency-key contract ([Stripe: idempotent requests](https://docs.stripe.com/api/idempotent_requests)), and the Amazon Builders' Library covers the general design ([Making retries safe with idempotent APIs](https://aws.amazon.com/builders-library/making-retries-safe-with-idempotent-APIs/)).

### 4.2 Why the unique constraint is the whole trick

In PostgreSQL, when two transactions insert the same key concurrently, the second one **blocks on the unique index** until the first commits or aborts. It then sees the conflict and does nothing (see `INSERT … ON CONFLICT` in the [PostgreSQL docs](https://www.postgresql.org/docs/current/sql-insert.html)). The listing runs 8 concurrent identical requests: **1 creates the payment, 7 replay it**, and the ledger holds exactly 2 entries summing to 0 (§12).

### 4.3 The external call: idempotency doesn't stop at your database

The gateway call is outside your transaction. Tillpoint's design:
1. **Claim the key** and commit a `PENDING` payment, so the attempt is durable before any external call.
2. **Call the gateway** *with the same idempotency key*. Most payment gateways support one. A retried call with the same key returns the original result rather than charging again.
3. **On timeout,** the outcome is unknown. Never retry blindly with a new key. Query the gateway by key, or wait for the settlement file, and only then move the payment to `CAPTURED` or `FAILED`.

(The listing keeps the charge in a single local transaction to isolate the database mechanics. §4.3 is the production extension.)

#### How an L5 tells it

> We added idempotency keys to the payment API, so if the client retries, we basically check if we've seen the key before and skip it. That fixed the double-charge problem.

#### How an L7 tells it

> The arbiter is the database, not application code. I insert the key into a table whose primary key is the idempotency key, with ON CONFLICT DO NOTHING, so if 8 identical requests arrive together, 7 of them block on the unique index until the first commits, and then see it as completed and replay the stored response. A check-then-insert would have let 2 through in the same millisecond. The key row, the payment, both ledger entries and the outbox event commit in 1 transaction, and I store a hash of the request with the key, so a client that reuses a key with a different amount gets a 422 instead of a silent replay. For the gateway I pass the same key downstream, and a timeout is resolved by querying the gateway by key, never by retrying with a new one, which was the exact mechanism behind INC-P3's 1,214 double charges.

---

## 5. Deep well 2: the saga, the outbox and their idempotency

### 5.1 Orchestration over choreography, for this flow

Garcia-Molina and Salem's original "Sagas" paper (SIGMOD 1987, DOI 10.1145/38713.38742) defines a saga as a sequence of local transactions, each with a compensating transaction. Tillpoint uses an **orchestrator** (the checkout service owns the state machine) rather than choreography (services reacting to each other's events), for three reasons:
1. The flow has a **pivot**: payment authorization. Before it, everything is compensable. After it, the saga must go forward. An explicit state machine makes the pivot visible and testable.
2. **Operators need one place** to see where every checkout is: `SELECT state, count(*) FROM saga GROUP BY state`.
3. Choreography spreads the flow's logic across 4 teams' services, which is exactly the coupling the split was meant to reduce.

Chris Richardson's pattern catalog compares the two styles ([Saga](https://microservices.io/patterns/data/saga.html)).

### 5.2 State machine

```text
 START --reserve ok--> RESERVED --authorize ok (pivot)--> AUTHORIZED --confirm--> CONFIRMED
                          |
                          +--authorize declined/failed--> PAYMENT_FAILED --compensate--> COMPENSATED
 Every transition is: UPDATE saga SET state = :to WHERE order_id = :id AND state = :from
 -> 1 row updated = this delivery owns the transition; 0 rows = already done (no-op)
```

**Compensations are forward steps, and they must be idempotent.** Messages are delivered at least once, so a compensation *will* arrive twice. The guard is the conditional `UPDATE`. Only the delivery that moves the state performs the side effect (releasing inventory). The listing delivers the compensation twice: the first releases 2 units, the second is a no-op, and inventory returns to exactly 5.

### 5.3 The transactional outbox

- **The problem:** writing to the database and publishing to Kafka can't be atomic across two systems ("dual write"). Publish first and the commit may fail; commit first and the publish may fail.
- **The outbox pattern** ([Transactional outbox](https://microservices.io/patterns/data/transactional-outbox.html)) inserts the event into an `outbox` table *in the same transaction* as the state change. Relays then publish committed outbox rows.
- **Relays and locking:** Tillpoint's relays claim batches with `SELECT … FOR UPDATE SKIP LOCKED` ([PostgreSQL SELECT, locking clause](https://www.postgresql.org/docs/current/sql-select.html)), so two relays never claim the same row and neither waits on the other.
- **Delivery is still at least once:** a relay can crash after publishing and before marking the row. **Consumers dedup by event id.**

The listing runs 2 relays over 11 events: each event is published exactly once across both relays, and none is left behind.

---

## 6. Failure archaeology: INC-P9, the compensation replay

1. **Detection.** The inventory invariant check (available + reserved = physical, hourly) failed for 37 SKUs at 02:00: available stock was *above* physical stock.
2. **Bounding.** All 37 SKUs had had `PaymentFailed` sagas in the previous 6 hours. 112 orders were accepted against stock that didn't exist.
3. **Mitigation.**
   - The inventory team froze those 37 SKUs.
   - Customer support contacted the 112 customers: 71 were fulfilled from another warehouse, and 41 received cancellations with a credit.
4. **Root cause, mine.**
   - The first version of my compensation handler released inventory unconditionally when it received a `PaymentFailed` event.
   - A consumer-group offset reset during a Kafka maintenance window replayed 6 hours of those events, so each compensation ran a second time.
   - My design said "consumers are idempotent". This handler wasn't.
5. **Fix.** State-guarded transitions (§5.2) for every compensation, plus a consumer-side processed-event table keyed by event id for handlers that have no natural state.
6. **Systemic.**
   - A replay test in CI: every consumer must survive its whole topic being redelivered with no change to state.
   - The hourly inventory invariant check became a 5-minute check with a page.

#### How an L5 tells it

> At one point some inventory got messed up because events were replayed, which was kind of an edge case with Kafka. We fixed the consumer and added checks, and it hasn't happened since.

#### How an L7 tells it

> The incident I learned most from was INC-P9, and the root cause was my code. My first compensation handler released inventory every time it saw a PaymentFailed event, with no check of the saga's state. A consumer-group offset reset during Kafka maintenance replayed 6 hours of those events, so 37 SKUs were released twice and 112 orders were accepted against stock that didn't exist. The hourly invariant check caught it at 02:00, available above physical for exactly those SKUs. Support fulfilled 71 of the orders from another warehouse and cancelled 41 with a credit. The fix was a conditional state transition on every compensation, so only the delivery that moves the saga from PAYMENT_FAILED to COMPENSATED releases stock, and a CI test that redelivers every consumer's whole topic and asserts that state doesn't change.

---

## 7. Deep well 3: SQL, transactions and resiliency

### 7.1 Ledger invariants in the schema

- **Append-only entries:** no `UPDATE` or `DELETE` on `ledger_entries`; corrections are new reversing entries.
- **Double entry:** every payment writes a debit and a credit in the same transaction. The daily check `SELECT payment_id FROM ledger_entries GROUP BY payment_id HAVING sum(amount_cents) <> 0` must return 0 rows. The listing runs it over 11 payments.
- **Balances derived,** from entries, or from snapshots of entries, never as an independently updated column.
- **Money as integer minor units** plus a currency code (the 02.3 §3.1 regret: Tillpoint started with 2-place decimals).

### 7.2 The index that interviewers will ask you to prove

- **Query:** a customer's 20 most recent open orders, newest first.
- **Before:** a sequential scan of **200,000** rows, removing 194,256, then a top-N heapsort.
- **After:** `CREATE INDEX … (customer_id, created_at DESC) WHERE status = 'OPEN'` gives an index scan that reads **20** rows, with **no sort**, because the index order matches the query order.
- **The partial predicate** keeps the index to open orders only, about 20% of rows ([PostgreSQL partial indexes](https://www.postgresql.org/docs/current/indexes-partial.html)).

The listing shows both plans with `EXPLAIN ANALYZE` ([Using EXPLAIN](https://www.postgresql.org/docs/current/using-explain.html)). It also shows the planner choosing a *bitmap scan plus a tiny sort* for a customer with only 14 open orders. That's correct, and worth saying: the "no sort" plan matters for the large accounts.

#### How an L5 tells it

> The orders query was slow, so we added an index and it got way faster. We also did some general query optimization across the services.

#### How an L7 tells it

> The slow query was 'a customer's 20 newest open orders', and EXPLAIN ANALYZE showed why: a sequential scan of all 200,000 rows, discarding 194,256 of them, then a top-N sort, which hurt most for our largest broker accounts with thousands of open orders. I added a partial composite index on customer id and created-at descending, restricted to open orders. The plan became an index scan reading exactly 20 rows with no sort step, because the index order is the query order. For a customer with 14 open orders the planner picks a bitmap scan and a 14-row sort instead, which is the right call, so I quote the large-account plan as the reason for the index, not as a universal speedup.

### 7.3 Transaction boundaries: never hold a connection across a remote call

The largest latency win wasn't an index. Checkout had opened a transaction, then called the payment gateway, *then* committed, holding a connection for the whole ~180 ms. By Little's law (02.2 §3.1), that needed **432** connections at peak. Moving the gateway call outside the transaction (claim → commit → call → record result in a second short transaction, §4.3) dropped the database-holding time to ~12 ms, about **29** connections on average. The same change took primary CPU from 85% to 61% and commit p99 from 31 to 9 ms.

### 7.4 Hot rows: the Black Friday television

- **The problem:** one SKU's stock is one row, so every reservation for it serializes on that row's lock. `pg_stat_activity` showed lock waits on 0.3% of SKUs, and those were exactly the doorbusters.
- **The fix:** split hot SKUs' stock into **N buckets** (rows), and reserve from a random bucket, falling back to the others when one is empty. Contention drops by roughly N. The invariant becomes Σ buckets = available stock, checked every 5 minutes.
- **The cost:** a reservation may need to probe more than one bucket near sellout. That's acceptable, because the alternative was a 4-second lock queue.

### 7.5 Resiliency: retries are a load multiplier

- **Amplification:** if 3 layers each retry 3 times, one user request can become 3 × 3 × 3 = **27** gateway calls during an outage. That is a retry storm that keeps the outage going.
- **Tillpoint's policy:**
  1. **Retry at one layer only:** the payments service, next to the gateway.
  2. **Budgets:** retries may not exceed 10% of requests, enforced by a token bucket.
  3. **Exponential backoff with full jitter** ([Timeouts, retries and backoff with jitter](https://aws.amazon.com/builders-library/timeouts-retries-and-backoff-with-jitter/)).
  4. **Deadlines propagated:** checkout's 300 ms budget flows down, so nothing retries past the caller's deadline.
  5. **Circuit breakers on the gateway adapter** ([Resilience4j](https://resilience4j.readme.io/docs)), opening at a 50% failure rate over 20 calls.
- **The Google Cloud June 2025 postmortem** (01.1 §3.6) is a public example of missing randomized backoff causing a herd effect on restart.

#### How an L5 tells it

> We made the services resilient with retries and circuit breakers using Resilience4j, which is basically best practice. That way if the gateway has issues, the system handles it gracefully.

#### How an L7 tells it

> INC-P3 was a retry storm, so the resiliency design starts from amplification. The client, checkout and payments each retried 3 times, so a gateway brownout turned 1 purchase into up to 27 gateway calls. I moved retries to 1 layer, the payments adapter next to the gateway, with full-jitter exponential backoff and a retry budget of 10% of requests, and checkout's 300-millisecond deadline propagates down so nothing retries past it. The circuit breaker opens at a 50% failure rate over 20 calls. In the next peak season the gateway had a 9-minute brownout, and our gateway call rate rose by 8% instead of multiplying.

---

## 8. Why not simpler? (three options + Option Zero)

| Option | Fails | Kept from it |
|---|---|---|
| Option Zero: fix the monolith (faster pipeline, idempotency inside it) | K3: card data still crosses the order code, so 140 hosts stay in PCI scope. The deploy queue stays at ρ 0.84 (02.1 §4.5). | The idempotency design, which was in fact built first, inside the monolith |
| Modular monolith with independent deploy units | K3, unless tokenization is split out anyway | Module boundaries became the service boundaries |
| Services (chosen) | — | — |
| Distributed transactions (2PC/XA) instead of a saga | The gateway doesn't take part in XA; locks held across services hurt availability (K4) | — (Q6) |

**The concession, stated first:** a single primary handled the write load at 36% of peak capacity (02.1 §4.6). The split rests on PCI scope (K3), deploy coupling (G6), and shortening the critical path (K4), not on throughput.

---

## 9. Constraints and hindsight

<!-- ledger:start name=b-tillpoint -->
| ID | Constraint | Category | Source | Hardness | Evidence it was real | Design consequence | Cost paid | Revisit trigger |
|---|---|---|---|---|---|---|---|---|
| TB1 | Card data may reach only PCI-scoped systems | Regulatory | Security architect; PCI assessor | Hard | Assessor's scoping report listing 140 in-scope hosts | Tokenization at the edge; services see only tokens | ~3 months for the tokenization rollout; 12 hosts stay in scope | Scope rules change, or a hosted payment page removes card data entirely |
| TB2 | The payment gateway doesn't take part in distributed transactions | Legacy | Gateway's API contract | Hard | Gateway docs: REST with idempotency keys only | Saga with a pivot at authorization; timeout resolution by query | ~2 engineer-months for the saga and the timeout reconciler | Gateway offers a two-phase authorize/capture with holds (we used it) |
| TB3 | Peak season code freeze, 6 weeks | Deadline | Retail operations calendar | Hard | Published freeze calendar; previous year's incident review | Inventory buckets shipped 2 weeks before the freeze | 1 planned feature moved to the next quarter | Freeze policy changes |
| TB4 | 4 teams own the 4 services; each has its own on-call | Stakeholder | Engineering directors | Negotiable | Team charters | Contracts per service; the saga state machine owned by checkout | ~1 day per contract change for cross-team review | A team merge, or a service changing owners |
<!-- ledger:end -->

**Hindsight:**
- **Money type:** integer minor units plus an ISO 4217 code from day 1 (02.3 §3.1). A bad decision with a bad outcome: 11 services were retrofitted.
- **Compensation handlers:** guarded from day 1. The INC-P9 lesson.
- **A good decision to defend:** single-region primary plus cross-region standby over active-active (02.3 §7).

---

## 10. Numbers card (Archetype B)

| Number | Value | Re-derive |
|---|---|---|
| Peak orders | 2,400/s | 8 × 300 mean |
| Peak rows | 14,400/s; 36% of 40,000 | 2,400 × 6 |
| Concurrent checkouts | 432 | 2,400/s × 0.18 s |
| Connections needed | ~29 avg, ~41 at 70% | 2,400 × 0.012 s; ÷ 0.7 |
| Critical-path availability | 99.90% | 0.9995² |
| Tail exposure | 33.1% → 11.4% | 1 − 0.99⁴⁰; 1 − 0.99¹² |
| Retry amplification | 27× → 1.1× | 3³; 1 layer with a 10% budget |
| PCI hosts | 140 → 12; ~$230k/yr | × ~$1,800 per host |
| Index | 200,000 rows read → 20 | EXPLAIN ANALYZE |

---

## 11. Hiring-committee scoring rubric: Archetype B

| Dimension | Poor | Borderline | Solid (L6) | Outstanding (L7) |
|---|---|---|---|---|
| **Idempotency** | "We check if we've seen it" | A unique key | Unique constraint + payload hash + in-progress + replay, all atomic | Plus the external call (key passed downstream, timeout resolved by query) |
| **Saga** | "We used sagas" | Names the compensations | Orchestrated state machine with a pivot | Idempotent compensations by state guard; replay tests; owns INC-P9 |
| **Outbox** | Dual write | Outbox | Outbox + `SKIP LOCKED` relays + idempotent consumers | Plus at-least-once from relay crashes acknowledged |
| **SQL** | "Added an index" | Shows the index | `EXPLAIN ANALYZE` before and after | Plus the planner's choice explained; transaction boundaries; hot-row buckets |
| **Resiliency** | "Retries and circuit breakers" | Configured values | One retry layer, jitter, deadlines | Amplification math; retry budgets; measured behavior in a real brownout |
| **Justification** | "Microservices scale" | Velocity | PCI and availability arguments | Concedes the throughput fit; defends on K3/K4/G6 with numbers |

---

## 12. Listing and output

### 12.1 Listing L8: `TillpointLedger.java`

<!-- listing:TillpointLedger.java -->
```java
// profile: db
// TillpointLedger.java - the Archetype B mechanisms, against a real PostgreSQL 18
// (embedded via zonky), with plain JDBC so every statement is visible:
//   1. idempotency keys: 8 concurrent identical requests -> exactly 1 charge
//   2. double-entry ledger: every payment's entries sum to zero
//   3. transactional outbox + 2 relays using FOR UPDATE SKIP LOCKED -> each event once
//   4. orchestrated saga with an idempotent compensation (run twice, applied once)
//   5. SQL tuning: EXPLAIN ANALYZE before/after a partial composite index
// In the service this sits behind Spring's @Transactional; here the transaction
// boundaries are explicit so the interviewer can see exactly what commits together.
import io.zonky.test.db.postgres.embedded.EmbeddedPostgres;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Statement;
import java.util.ArrayList;
import java.util.HexFormat;
import java.util.List;
import java.util.Map;
import java.util.TreeMap;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import javax.sql.DataSource;

public class TillpointLedger {
    static int checks = 0;
    static int failed = 0;

    static void check(boolean ok, String what) {
        checks++;
        if (!ok) {
            failed++;
        }
        System.out.println("  [" + (ok ? "ok" : "FAIL") + "] " + what);
    }

    static void exec(Connection c, String sql) throws SQLException {
        try (Statement s = c.createStatement()) {
            s.execute(sql);
        }
    }

    static long one(Connection c, String sql) throws SQLException {
        try (Statement s = c.createStatement(); ResultSet r = s.executeQuery(sql)) {
            r.next();
            return r.getLong(1);
        }
    }

    static String sha256(String s) throws Exception {
        return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(s.getBytes(StandardCharsets.UTF_8)));
    }

    /** POST /payments with an Idempotency-Key. Returns an HTTP-like status line. */
    static String charge(DataSource ds, String key, String orderId, long cents) throws Exception {
        String hash = sha256(orderId + "|" + cents);
        try (Connection c = ds.getConnection()) {
            c.setAutoCommit(false);
            int claimed;
            try (PreparedStatement ins = c.prepareStatement(
                    "INSERT INTO idempotency_keys(key, request_hash, status) VALUES (?, ?, 'IN_PROGRESS') "
                            + "ON CONFLICT (key) DO NOTHING")) {
                ins.setString(1, key);
                ins.setString(2, hash);
                claimed = ins.executeUpdate();     // a concurrent claimant blocks here until we commit
            }
            if (claimed == 1) {
                long paymentId;
                try (PreparedStatement p = c.prepareStatement(
                        "INSERT INTO payments(order_id, amount_cents) VALUES (?, ?) RETURNING payment_id")) {
                    p.setString(1, orderId);
                    p.setLong(2, cents);
                    try (ResultSet r = p.executeQuery()) {
                        r.next();
                        paymentId = r.getLong(1);
                    }
                }
                try (PreparedStatement e = c.prepareStatement(
                        "INSERT INTO ledger_entries(payment_id, account, amount_cents) VALUES (?, ?, ?), (?, ?, ?)")) {
                    e.setLong(1, paymentId);
                    e.setString(2, "customer:" + orderId);
                    e.setLong(3, -cents);
                    e.setLong(4, paymentId);
                    e.setString(5, "merchant:settlement");
                    e.setLong(6, cents);
                    e.executeUpdate();
                }
                try (PreparedStatement o = c.prepareStatement(
                        "INSERT INTO outbox(aggregate_id, type, payload) VALUES (?, 'PaymentCaptured', ?)")) {
                    o.setString(1, orderId);
                    o.setString(2, "{\"payment\":" + paymentId + ",\"cents\":" + cents + "}");
                    o.executeUpdate();
                }
                String response = "payment " + paymentId;
                try (PreparedStatement u = c.prepareStatement(
                        "UPDATE idempotency_keys SET status = 'COMPLETED', response = ? WHERE key = ?")) {
                    u.setString(1, response);
                    u.setString(2, key);
                    u.executeUpdate();
                }
                c.commit();                         // payment, ledger, outbox and key commit together
                return "201 created " + response;
            }
            String storedHash;
            String status;
            String response;
            try (PreparedStatement q = c.prepareStatement(
                    "SELECT request_hash, status, response FROM idempotency_keys WHERE key = ?")) {
                q.setString(1, key);
                try (ResultSet r = q.executeQuery()) {
                    r.next();
                    storedHash = r.getString(1);
                    status = r.getString(2);
                    response = r.getString(3);
                }
            }
            c.commit();
            if (!storedHash.equals(hash)) {
                return "422 key reused with a different payload";
            }
            if (status.equals("IN_PROGRESS")) {
                return "409 in progress, retry later";
            }
            return "200 replayed " + response;
        }
    }

    public static void main(String[] args) throws Exception {
        try (EmbeddedPostgres pg = EmbeddedPostgres.builder().start()) {
            DataSource ds = pg.getPostgresDatabase();
            try (Connection c = ds.getConnection()) {
                System.out.println("PostgreSQL " + one(c, "SHOW server_version_num") / 10000);
                exec(c, "CREATE TABLE idempotency_keys (key text PRIMARY KEY, request_hash text NOT NULL, "
                        + "status text NOT NULL, response text, created_at timestamptz NOT NULL DEFAULT now())");
                exec(c, "CREATE TABLE payments (payment_id bigserial PRIMARY KEY, order_id text NOT NULL UNIQUE, "
                        + "amount_cents bigint NOT NULL CHECK (amount_cents > 0))");
                exec(c, "CREATE TABLE ledger_entries (entry_id bigserial PRIMARY KEY, "
                        + "payment_id bigint NOT NULL REFERENCES payments, account text NOT NULL, amount_cents bigint NOT NULL)");
                exec(c, "CREATE TABLE outbox (event_id bigserial PRIMARY KEY, aggregate_id text NOT NULL, "
                        + "type text NOT NULL, payload text NOT NULL, published_by text)");
                exec(c, "CREATE TABLE inventory (sku text PRIMARY KEY, available int NOT NULL CHECK (available >= 0))");
                exec(c, "CREATE TABLE saga (order_id text PRIMARY KEY, state text NOT NULL)");
                exec(c, "INSERT INTO inventory VALUES ('SKU-A', 5)");
            }

            System.out.println("1. Idempotency: 8 concurrent POSTs with the same key");
            ExecutorService pool = Executors.newFixedThreadPool(8);
            CountDownLatch go = new CountDownLatch(1);
            List<Future<String>> fs = new ArrayList<>();
            for (int i = 0; i < 8; i++) {
                fs.add(pool.submit(() -> {
                    go.await();
                    return charge(ds, "idem-7f3a", "o-1001", 12999);
                }));
            }
            go.countDown();
            Map<String, Integer> tally = new TreeMap<>();
            for (Future<String> f : fs) {
                tally.merge(f.get().replaceAll(" payment \\d+", " payment N"), 1, Integer::sum);
            }
            tally.forEach((k, v) -> System.out.println("    " + v + " x " + k));
            check(tally.getOrDefault("201 created payment N", 0) == 1, "exactly one request created the payment");
            check(tally.getOrDefault("200 replayed payment N", 0) == 7, "the other 7 replayed the stored response");
            check(charge(ds, "idem-7f3a", "o-1001", 13999).startsWith("422"), "same key, different amount -> 422");
            try (Connection c = ds.getConnection()) {
                check(one(c, "SELECT count(*) FROM payments") == 1, "1 payment row");
                check(one(c, "SELECT count(*) FROM ledger_entries") == 2, "2 ledger entries (double entry)");
                check(one(c, "SELECT coalesce(sum(amount_cents), 0) FROM ledger_entries") == 0, "ledger sums to zero");
            }

            System.out.println("2. Outbox: 10 more payments, then 2 relays drain with SKIP LOCKED");
            for (int i = 1; i <= 10; i++) {
                charge(ds, "idem-b" + i, "o-20" + i, 1000L * i);
            }
            Map<Long, String> publishedBy = new ConcurrentHashMap<>();
            CountDownLatch go2 = new CountDownLatch(1);
            List<Future<Integer>> relays = new ArrayList<>();
            for (String relay : List.of("relay-1", "relay-2")) {
                relays.add(pool.submit(() -> {
                    go2.await();
                    int n = 0;
                    try (Connection c = ds.getConnection()) {
                        c.setAutoCommit(false);
                        while (true) {
                            List<Long> batch = new ArrayList<>();
                            try (Statement s = c.createStatement(); ResultSet r = s.executeQuery(
                                    "SELECT event_id FROM outbox WHERE published_by IS NULL ORDER BY event_id "
                                            + "LIMIT 3 FOR UPDATE SKIP LOCKED")) {
                                while (r.next()) {
                                    batch.add(r.getLong(1));
                                }
                            }
                            if (batch.isEmpty()) {
                                c.commit();
                                return n;
                            }
                            for (long id : batch) {
                                if (publishedBy.putIfAbsent(id, relay) != null) {
                                    throw new IllegalStateException("event " + id + " published twice");
                                }
                            }
                            try (PreparedStatement u = c.prepareStatement(
                                    "UPDATE outbox SET published_by = ? WHERE event_id = ANY (?)")) {
                                u.setString(1, relay);
                                u.setArray(2, c.createArrayOf("bigint", batch.toArray()));
                                u.executeUpdate();
                            }
                            c.commit();
                            n += batch.size();
                        }
                    }
                }));
            }
            go2.countDown();
            int total = 0;
            for (Future<Integer> f : relays) {
                total += f.get();
            }
            try (Connection c = ds.getConnection()) {
                long outbox = one(c, "SELECT count(*) FROM outbox");
                System.out.println("    outbox rows " + outbox + ", published " + total + " (split between relays varies run to run)");
                check(total == outbox && outbox == 11, "every event published exactly once across 2 relays");
                check(one(c, "SELECT count(*) FROM outbox WHERE published_by IS NULL") == 0, "no event left unpublished");
                check(one(c, "SELECT count(*) FROM (SELECT payment_id FROM ledger_entries GROUP BY payment_id "
                        + "HAVING sum(amount_cents) <> 0) x") == 0, "all 11 payments balance to zero");
            }

            System.out.println("3. Saga: reserve -> authorize (declined) -> compensate (delivered twice)");
            try (Connection c = ds.getConnection()) {
                c.setAutoCommit(false);
                int reserved = c.createStatement().executeUpdate(
                        "UPDATE inventory SET available = available - 2 WHERE sku = 'SKU-A' AND available >= 2");
                exec(c, "INSERT INTO saga VALUES ('o-77', 'RESERVED')");
                c.commit();
                System.out.println("    reserve 2 x SKU-A: " + (reserved == 1 ? "ok" : "insufficient") + ", saga RESERVED");
                exec(c, "UPDATE saga SET state = 'PAYMENT_FAILED' WHERE order_id = 'o-77' AND state = 'RESERVED'");
                c.commit();
                System.out.println("    authorize: declined by issuer, saga PAYMENT_FAILED");
                for (int attempt = 1; attempt <= 2; attempt++) {
                    int moved = c.createStatement().executeUpdate(
                            "UPDATE saga SET state = 'COMPENSATED' WHERE order_id = 'o-77' AND state = 'PAYMENT_FAILED'");
                    if (moved == 1) {
                        exec(c, "UPDATE inventory SET available = available + 2 WHERE sku = 'SKU-A'");
                    }
                    c.commit();
                    System.out.println("    compensation attempt " + attempt + ": " + (moved == 1 ? "released 2" : "no-op (already compensated)"));
                }
                check(one(c, "SELECT available FROM inventory WHERE sku = 'SKU-A'") == 5, "inventory back to 5, released once");
                check(one(c, "SELECT count(*) FROM saga WHERE state = 'COMPENSATED'") == 1, "saga ends COMPENSATED");
                c.commit();
            }

            System.out.println("4. SQL tuning: open orders for one customer, newest first (customer 1 = a large broker account)");
            try (Connection c = ds.getConnection()) {
                exec(c, "CREATE TABLE orders (order_id bigint PRIMARY KEY, customer_id int NOT NULL, status text NOT NULL, "
                        + "created_at timestamptz NOT NULL, total_cents bigint NOT NULL)");
                exec(c, "INSERT INTO orders SELECT g, CASE WHEN g % 10 = 0 THEN 1 ELSE g % 2000 END, "
                        + "CASE WHEN (g / 7) % 5 = 0 THEN 'OPEN' ELSE 'CLOSED' END, "
                        + "timestamptz '2026-01-01 00:00+00' + g * interval '1 minute', (g % 977) * 100 "
                        + "FROM generate_series(1, 200000) g");
                exec(c, "ANALYZE orders");
                exec(c, "SET max_parallel_workers_per_gather = 0");
                String big = "SELECT order_id, created_at, total_cents FROM orders "
                        + "WHERE customer_id = 1 AND status = 'OPEN' ORDER BY created_at DESC LIMIT 20";
                String small = big.replace("customer_id = 1 ", "customer_id = 42 ");
                System.out.println("    open orders: customer 1 = " + one(c, "SELECT count(*) FROM orders WHERE customer_id = 1 AND status = 'OPEN'")
                        + ", customer 42 = " + one(c, "SELECT count(*) FROM orders WHERE customer_id = 42 AND status = 'OPEN'"));
                List<String> before = plan(c, big);
                exec(c, "CREATE INDEX orders_open_by_customer ON orders (customer_id, created_at DESC) WHERE status = 'OPEN'");
                exec(c, "ANALYZE orders");
                List<String> after = plan(c, big);
                List<String> afterSmall = plan(c, small);
                System.out.println("    customer 1, before:");
                before.forEach(l -> System.out.println("      " + l));
                System.out.println("    customer 1, after CREATE INDEX ... (customer_id, created_at DESC) WHERE status = 'OPEN':");
                after.forEach(l -> System.out.println("      " + l));
                System.out.println("    customer 42 (14 open orders), after:");
                afterSmall.forEach(l -> System.out.println("      " + l));
                check(before.stream().anyMatch(l -> l.contains("Seq Scan")) && before.stream().anyMatch(l -> l.contains("Sort")),
                        "before: sequential scan of 200,000 rows plus a sort");
                check(after.stream().anyMatch(l -> l.contains("Index Scan using orders_open_by_customer"))
                        && after.stream().noneMatch(l -> l.contains("Sort")), "after: index scan, no sort (index order = query order)");
                check(afterSmall.stream().anyMatch(l -> l.contains("orders_open_by_customer")),
                        "small customer: same index, planner may pick bitmap + tiny sort");
            }
            pool.shutdown();
        }
        System.out.println();
        System.out.println(failed == 0 ? "verdict: OK (" + checks + " checks)" : "verdict: CHECK (" + failed + " of " + checks + " failed)");
    }

    static List<String> plan(Connection c, String q) throws SQLException {
        List<String> out = new ArrayList<>();
        try (Statement s = c.createStatement(); ResultSet r = s.executeQuery(
                "EXPLAIN (ANALYZE, BUFFERS OFF, COSTS OFF, TIMING OFF, SUMMARY OFF) " + q)) {
            while (r.next()) {
                out.add(r.getString(1).replaceAll("\\s+Memory: \\d+kB", ""));
            }
        }
        return out;
    }
}
```

### 12.2 Output (PostgreSQL 18, embedded)

<!-- output:TillpointLedger.java -->
```text
PostgreSQL 18
1. Idempotency: 8 concurrent POSTs with the same key
    7 x 200 replayed payment N
    1 x 201 created payment N
  [ok] exactly one request created the payment
  [ok] the other 7 replayed the stored response
  [ok] same key, different amount -> 422
  [ok] 1 payment row
  [ok] 2 ledger entries (double entry)
  [ok] ledger sums to zero
2. Outbox: 10 more payments, then 2 relays drain with SKIP LOCKED
    outbox rows 11, published 11 (split between relays varies run to run)
  [ok] every event published exactly once across 2 relays
  [ok] no event left unpublished
  [ok] all 11 payments balance to zero
3. Saga: reserve -> authorize (declined) -> compensate (delivered twice)
    reserve 2 x SKU-A: ok, saga RESERVED
    authorize: declined by issuer, saga PAYMENT_FAILED
    compensation attempt 1: released 2
    compensation attempt 2: no-op (already compensated)
  [ok] inventory back to 5, released once
  [ok] saga ends COMPENSATED
4. SQL tuning: open orders for one customer, newest first (customer 1 = a large broker account)
    open orders: customer 1 = 5744, customer 42 = 14
    customer 1, before:
      Limit (actual rows=20.00 loops=1)
        ->  Sort (actual rows=20.00 loops=1)
              Sort Key: created_at DESC
              Sort Method: top-N heapsort
              ->  Seq Scan on orders (actual rows=5744.00 loops=1)
                    Filter: ((customer_id = 1) AND (status = 'OPEN'::text))
                    Rows Removed by Filter: 194256
    customer 1, after CREATE INDEX ... (customer_id, created_at DESC) WHERE status = 'OPEN':
      Limit (actual rows=20.00 loops=1)
        ->  Index Scan using orders_open_by_customer on orders (actual rows=20.00 loops=1)
              Index Cond: (customer_id = 1)
              Index Searches: 1
    customer 42 (14 open orders), after:
      Limit (actual rows=14.00 loops=1)
        ->  Sort (actual rows=14.00 loops=1)
              Sort Key: created_at DESC
              Sort Method: quicksort
              ->  Bitmap Heap Scan on orders (actual rows=14.00 loops=1)
                    Recheck Cond: ((customer_id = 42) AND (status = 'OPEN'::text))
                    Heap Blocks: exact=14
                    ->  Bitmap Index Scan on orders_open_by_customer (actual rows=14.00 loops=1)
                          Index Cond: (customer_id = 42)
                          Index Searches: 1
  [ok] before: sequential scan of 200,000 rows plus a sort
  [ok] after: index scan, no sort (index order = query order)
  [ok] small customer: same index, planner may pick bitmap + tiny sort

verdict: OK (14 checks)
```

**Reading the output.**
- **Section 1:** one request created the payment and 7 replayed it, although all 8 started together. The unique index serialized them.
- **Section 2:** the outbox relays split the work differently on each run (deliberately not printed), but the total is always 11 events, each published once.
- **Section 3:** the compensation is delivered twice and applied once.
- **Section 4:** the plan changes from Seq Scan + Sort over 200,000 rows to an Index Scan reading 20 rows, while the small customer's plan correctly stays a bitmap scan with a 14-row sort.

---

## 13. Failure modes

| # | Failure mode | Symptom | Fix |
|---|---|---|---|
| F1 | Check-then-insert idempotency | Double charge under concurrency | Unique constraint as the arbiter (§4.2) |
| F2 | Key without a payload hash | A reused key with a new amount silently replays | Store and compare the request hash → 422 |
| F3 | Retry with a new key after a timeout | Double charge at the gateway | Pass the key downstream; resolve by query (§4.3) |
| F4 | Unguarded compensation | Over-released stock on replay (INC-P9) | State-guarded transitions (§5.2) |
| F5 | Dual write | Lost or phantom events | Transactional outbox (§5.3) |
| F6 | Connection held across a remote call | Pool exhaustion at peak | Commit before the call (§7.3) |
| F7 | Hot row | Lock queues on doorbusters | Bucketed stock (§7.4) |
| F8 | Retries at every layer | 27× amplification | One layer, a budget, jitter, deadlines (§7.5) |
| F9 | Stored balances | Balances drift from entries | Derive balances; append-only entries (§7.1) |
| F10 | "Microservices for scale" | Fails the 36% concession | Defend on PCI, availability and deploy coupling (§8) |

---

## 14. Bar-raiser chains

<details><summary><b>Q1 · "Two identical requests arrive in the same millisecond. Show me the SQL."</b></summary>

**Initial Prompt.** "Your idempotency check: write the statements on the board, and tell me what happens when two requests with the same key arrive together."

**L5 Answer.** "First we SELECT from the idempotency table to see if the key exists, and if not we INSERT it and process the payment."

**Why L5 Stalls.** SELECT-then-INSERT is the textbook race: both requests see no row, both insert, and without a unique constraint both charge. With one, the second fails with an error the code may not handle. The candidate has described the bug INC-P3-class systems contain.

**L7 Answer.** "`INSERT INTO idempotency_keys(key, request_hash, status) VALUES ($1, $2, 'IN_PROGRESS') ON CONFLICT (key) DO NOTHING`. Then I check the row count. If it's 1, this request owns the key: it inserts the payment, the 2 ledger entries and the outbox event, updates the key to COMPLETED with the response, and commits, all in 1 transaction. If it's 0, I read the stored row. A different hash means 422, IN_PROGRESS means 409, COMPLETED means replay the response. In the same millisecond, the second INSERT blocks on the primary key's unique index until the first transaction commits, then sees the conflict. That's why my test with 8 concurrent requests always shows 1 created and 7 replayed: the index is the arbiter, not my code."

</details>

<details><summary><b>Q2 · "The gateway call timed out. Did you charge the customer?"</b></summary>

**Initial Prompt.** "Your payments service calls the gateway, and the call times out after 2 seconds. What's the state of the world, and what do you do?"

**L5 Answer.** "We retry the call a few times, and if it still fails we return an error to the customer so they can try again."

**Why L5 Stalls.** A timeout means *unknown*, not *failed*: the gateway may have charged. Retrying (with a new request) or letting the customer "try again" is exactly how INC-P3 charged 1,214 people twice.

**L7 Answer.** "Unknown, so I treat it as unknown. Before the call, the payment is already durable as PENDING with our idempotency key, and the gateway call carries that same key. On timeout I don't retry with a new identity and I don't tell the customer to try again. A reconciler queries the gateway by our key: if the charge exists it moves to CAPTURED, if the gateway has no record it moves to FAILED, and if the gateway is unreachable it waits and asks again. The customer sees 'payment processing' and the order can't be resubmitted under a new key while one is pending. The settlement file is the final backstop, matched against the ledger daily."

</details>

<details><summary><b>Q3 · "Orchestration or choreography? Defend your choice."</b></summary>

**Initial Prompt.** "You built an orchestrator. Choreography is looser coupling. Why centralize?"

**L5 Answer.** "Orchestration is easier to understand, and choreography can get messy with a lot of events."

**Why L5 Stalls.** "Easier" and "messy" are preferences. The interviewer wants the property of *this* flow that made orchestration right.

**L7 Answer.** "This flow has a pivot: payment authorization. Before it everything can be compensated; after it the saga must go forward. I wanted the pivot explicit in 1 state machine, testable as code, not implied by which services listen to which events. Operations wanted 1 place to answer 'where are all the in-flight checkouts': a GROUP BY on the saga table. And choreography would have spread the checkout flow's logic across 4 teams' services, which recreates the coupling we were removing. The cost is that checkout owns a central component the others depend on. Where there is no pivot and no single owner, like the post-confirmation events going to loyalty, notifications and analytics, I used choreography: those are independent reactions to a fact."

</details>

<details><summary><b>Q4 · "Your compensation event was delivered twice. What happened?"</b></summary>

**Initial Prompt.** "Messages are at-least-once. Your 'release inventory' compensation arrives twice. Walk me through it."

**L5 Answer.** "Our consumers are idempotent, so processing it twice wouldn't cause a problem."

**Why L5 Stalls.** "Our consumers are idempotent" is the assumption that caused INC-P9. Asserting idempotency without the mechanism is exactly what the probe tests.

**L7 Answer.** "Today it's a no-op the second time, and I learned that the hard way. Every compensation is a conditional transition: UPDATE saga SET state = 'COMPENSATED' WHERE order_id = $1 AND state = 'PAYMENT_FAILED', and only if that updates 1 row does the handler release stock, in the same transaction. The second delivery updates 0 rows and does nothing. My first version didn't have the guard. A consumer-group offset reset replayed 6 hours of events, 37 SKUs were released twice, and 112 orders were accepted against stock that didn't exist. Since then, every consumer has a CI test that redelivers its whole topic and asserts that state doesn't change."

</details>

<details><summary><b>Q5 · "Your relay published the event, then crashed before marking the row."</b></summary>

**Initial Prompt.** "The outbox relay sends to Kafka and dies before its UPDATE commits. What happens?"

**L5 Answer.** "The outbox pattern guarantees exactly-once delivery, so the event goes out once."

**Why L5 Stalls.** The outbox guarantees the event is *not lost*. It doesn't guarantee *once*. The relay crash described is exactly the duplicate case.

**L7 Answer.** "The row is still unmarked, and its lock is released when the connection dies, so the next relay pass publishes it again. Consumers see the event twice. The outbox makes publishing *at least once*, never lossy, and duplicates are handled by consumers deduplicating on the event id, which every consumer does, either through a natural state guard or a processed-events table. The relays use FOR UPDATE SKIP LOCKED so 2 relays don't claim the same batch at the same time, which avoids systematic duplicates. The crash-window duplicate is handled downstream, by design."

</details>

<details><summary><b>Q6 · "Why not a distributed transaction? XA exists."</b></summary>

**Initial Prompt.** "Two-phase commit across inventory, payments and ledger would give you atomicity. Why a saga?"

**L5 Answer.** "Two-phase commit doesn't scale and it's an anti-pattern in microservices."

**Why L5 Stalls.** "Anti-pattern" is a slogan. The interviewer wants the specific reasons 2PC fails *this* system.

**L7 Answer.** "Three specific reasons. First, the participant that matters most, the payment gateway, doesn't support XA: its API is REST with idempotency keys, so 2PC could never cover the actual charge. Second, 2PC holds locks in every participant until the coordinator decides. A slow or partitioned coordinator holds inventory rows locked across the checkout path, which directly attacks our 99.9% availability goal, and a coordinator failure between prepare and commit leaves participants in doubt. Third, the business already has compensating semantics: reservations expire, authorizations can be voided before capture. Where I could get local atomicity, I used it: payment, ledger entries and outbox commit in 1 database transaction, because those 3 tables live in the payments database."

</details>

<details><summary><b>Q7 · "Show me how you found the slow query and proved the fix."</b></summary>

**Initial Prompt.** "You said an index fixed the open-orders query. How did you find it, and how do you know?"

**L5 Answer.** "It was showing up as slow in our monitoring, so we added an index on customer id and it got faster."

**Why L5 Stalls.** An index on customer id alone doesn't remove the sort or the status filter, and "it got faster" isn't proof. The candidate shows no plan.

**L7 Answer.** "pg_stat_statements ranked it third by total time. The plan with EXPLAIN ANALYZE showed a sequential scan reading all 200,000 rows, discarding 194,256, then a top-N heapsort, and the cost was concentrated on large accounts with thousands of open orders. I created a partial index on customer id and created-at descending, where status is OPEN. The new plan is an index scan that reads exactly 20 rows with no sort, because the index order matches the ORDER BY and the partial predicate matches the WHERE. I also checked a small customer: with 14 open orders the planner prefers a bitmap scan and a tiny sort, which is fine. The partial predicate keeps the index at about 20% of the table, which matters for write cost on a hot table."

</details>

<details><summary><b>Q8 · "Three layers retry three times each. What does the gateway see in an outage?"</b></summary>

**Initial Prompt.** "Client, checkout, payments: each retries 3 times. The gateway browns out. Do the math."

**L5 Answer.** "It would get more traffic, but the circuit breaker would open and protect it."

**Why L5 Stalls.** A breaker at one layer doesn't stop the other two layers multiplying, and "more traffic" isn't the math. INC-P3 is what this answer produces.

**L7 Answer.** "Up to 3 × 3 × 3 = 27 gateway calls per purchase, at the moment the gateway can handle the fewest. That's a retry storm that extends the outage, and with keys regenerated per attempt, it also double-charges. My policy: retries happen at 1 layer only, the payments adapter. Retries are capped by a budget of 10% of requests through a token bucket. Backoff is exponential with full jitter, so retries don't synchronize. And checkout's 300-millisecond deadline propagates, so nothing retries after the caller has given up. In the following peak season, a 9-minute gateway brownout raised our gateway call rate by 8%, not 27×, and the breaker opened for 3 of those minutes."

</details>

<details><summary><b>Q9 · "Black Friday: everyone buys the same TV."</b></summary>

**Initial Prompt.** "One SKU gets 40% of reservations in the first minute. Your inventory row is the bottleneck. What did you do?"

**L5 Answer.** "We used optimistic locking with retries, so concurrent updates wouldn't block each other."

**Why L5 Stalls.** Optimistic locking on one hot row turns lock waits into retry storms: most attempts fail and retry, and throughput still serializes on one row. The interviewer is testing whether the candidate knows to split the contended resource.

**L7 Answer.** "I split the contended row. Hot SKUs, about 0.3% of the catalog, which we know in advance from merchandising, get their stock divided into 8 bucket rows. A reservation picks a random bucket and decrements it with a conditional UPDATE (available >= qty), trying the others when one is empty. Contention drops roughly 8×, because reservations spread over 8 row locks. The invariant becomes 'the sum of buckets equals available stock', checked every 5 minutes. The cost shows near sellout: a reservation may probe several empty buckets, so I return 'sold out' once 2 full passes find nothing, rather than spinning. Lock waits in pg_stat_activity during the doorbuster minute dropped from a 4-second queue to under 50 milliseconds."

</details>

<details><summary><b>Q10 · "Why not keep the monolith and just fix the pipeline?"</b></summary>

**Initial Prompt.** "Your velocity problem was a slow release train. Fix the train. Why 4 services?"

**L5 Answer.** "Because with microservices each team can deploy independently, and the monolith couldn't scale anymore."

**Why L5 Stalls.** "Couldn't scale" contradicts the 36% concession, and independent deploys can be achieved with a modular monolith. The candidate hasn't separated the reasons.

**L7 Answer.** "I did fix the train first: 45 minutes to 12. The queue math still left 63 minutes of mean wait at 0.84 utilization, which pointed to independent deploy units, and on velocity alone that's a modular monolith, not services. The services came from 2 other requirements. PCI scope: as long as card data crossed the order code, 140 hosts were in scope, and tokenization at the edge took that to 12. And the critical path: checkout needed to depend synchronously on only 2 things for 99.9%, which meant moving 3 dependencies behind an outbox. I'd defend the payments and ledger split on PCI and money invariants. Inventory as a separate service I'd defend less strongly: a module with its own schema would have been close."

</details>

---

## 15. Checklist

- [ ] Idempotency semantics table for your API: key owner, scope, arbiter, payload binding, in-flight, replay, atomicity, TTL (§4.1).
- [ ] The SQL of your idempotency path, and what happens to two concurrent requests (Q1).
- [ ] Timeout handling for every external call: unknown is not failed (§4.3).
- [ ] Your saga's state machine, its pivot, and the guard on every compensation (§5.2).
- [ ] Outbox: same-transaction insert, relay locking, consumer dedup (§5.3).
- [ ] Ledger invariants as queries you can write on the board (§7.1).
- [ ] One `EXPLAIN ANALYZE` before/after you can reproduce (§7.2).
- [ ] Transaction boundaries: no remote call inside a transaction (§7.3).
- [ ] Retry amplification math for your call graph, and your retry policy (§7.5).
- [ ] The concession on throughput, and the real reasons for each service boundary (§8).

---

## 16. References

- Hector Garcia-Molina and Kenneth Salem, "Sagas", *SIGMOD '87*, pp. 249–259, 1987. DOI 10.1145/38713.38742 (verified via Crossref).
- Chris Richardson, "Pattern: Saga". <https://microservices.io/patterns/data/saga.html>
- Chris Richardson, "Pattern: Transactional outbox". <https://microservices.io/patterns/data/transactional-outbox.html>
- Stripe API reference, "Idempotent requests". <https://docs.stripe.com/api/idempotent_requests>
- Amazon Builders' Library, "Making retries safe with idempotent APIs". <https://aws.amazon.com/builders-library/making-retries-safe-with-idempotent-APIs/>
- Amazon Builders' Library, "Timeouts, retries, and backoff with jitter". <https://aws.amazon.com/builders-library/timeouts-retries-and-backoff-with-jitter/>
- PostgreSQL documentation: `INSERT … ON CONFLICT`. <https://www.postgresql.org/docs/current/sql-insert.html>
- PostgreSQL documentation: `SELECT`, the locking clause (`FOR UPDATE SKIP LOCKED`). <https://www.postgresql.org/docs/current/sql-select.html>
- PostgreSQL documentation: Partial indexes. <https://www.postgresql.org/docs/current/indexes-partial.html>
- PostgreSQL documentation: Using EXPLAIN. <https://www.postgresql.org/docs/current/using-explain.html>
- Resilience4j documentation. <https://resilience4j.readme.io/docs>
