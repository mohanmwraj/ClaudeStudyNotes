# Problems 26–28: Stripe-Class Idempotent Payment Gateway, Double-Entry Ledger, Stock-Exchange Matching Engine

> **Folder 08 · File 02** of the Distributed Systems & System Design L7 Reference.
> **Listing:** `payments_ledger_exchange_lab.py` covers:
> - idempotency keys with in-progress locks and crash recovery;
> - double-entry invariants and the bugs that only reconciliation catches;
> - a price-time-priority matching engine whose journal replay is bit-identical, while reordered inputs are not.
>
> The output is deterministic.

---

## Problem 26: An idempotent payment gateway (Stripe class)

### 26.1 Scope, scale and SLAs

| Quantity | Target |
|---|---|
| API requests | 50k req/s peak (charges, refunds, payment intents), plus webhooks |
| Money correctness | **Zero double charges; zero lost charges**, under retries, timeouts and crashes |
| Latency | p99 < 1–2 s for authorization (dominated by card networks/issuers) |
| Availability | 99.999% for the API front door; degraded modes per downstream processor |
| Audit | Every state change attributable and immutable |

### 26.2 The core L7 problem: a side effect you cannot undo, behind an unreliable network

The card network charge is an **external, irreversible side effect**. Everything between the client and that charge
can fail:
- the client's request can time out after the charge succeeded;
- the server can crash between charging and recording;
- the client retries.

§A of the output (100,000 orders, 8% + 2% retries, 1% crashes between "charge" and "record"):

| Design | Charges made | **Double-charged orders** |
|---|---|---|
| No idempotency | 110,008 | **9,848** |
| **Idempotency keys + in-progress lock + recovery** | **100,000** | **0** |

The protocol (Stripe's public design; Brandur Leach's write-up):
1. The client sends `Idempotency-Key: <uuid>` (one per logical operation, reused on retries).
2. The server **atomically inserts** `(key, request_hash, state=IN_PROGRESS)`:
   - an existing key with `DONE` → **return the stored response**, byte-identical;
   - an existing key with `IN_PROGRESS` → a concurrent duplicate (409), or crash recovery (step 5);
   - a key reused with a different request body → error (it's a client bug).
3. Call the processor **with the idempotency key as the processor-side reference** (or the processor's own idempotency
   key), so the external call is itself deduplicable.
4. Record the result and set the key to `DONE` with the response, in one transaction with the payment's state change.
5. **Recovery:** a key stuck `IN_PROGRESS` past a lease is resolved by **asking the processor** whether a charge with
   that reference exists, then completing or retrying. This is "atomic phases": each phase is a local transaction,
   with the external call between recorded recovery points.

### 26.3 Schema and partition key

```
idempotency_keys: (merchant_id, key) → {request_hash, state, response, locked_until, recovery_point}
                  partition: hash(merchant_id) ; TTL 24 h–7 d
payment_intents:  pi_id → state machine (requires_payment_method → processing → succeeded | failed | canceled)
                  every transition = row update + an append to the ledger (problem 27) in ONE local transaction
outbox:           event rows (webhooks, ledger postings) written in the same transaction → relay publishes
processor_calls:  (pi_id, attempt) → request/response, network-level IDs (for reconciliation with settlement files)
```

### 26.4 Architecture and paths

```
 client ─► API edge (authN, rate limits per merchant, idempotency check) ─► payments service (state machines)
   ─► processor router (per card network / acquirer / region: health, cost, success-rate routing)
   ─► external processors (auth/capture) ─► responses + async webhooks from processors (deduped by event ID)
 outbox relay ─► merchant webhooks (at-least-once, signed, retried with backoff; merchants dedupe by event ID)
 reconciliation (daily + intraday): processor settlement files vs internal ledger → discrepancies → investigation queue
 control: routing rules, risk/fraud models, merchant configs (staged)
```

### 26.5 L7 failure-mode defense

| Failure | Defense |
|---|---|
| Client retry after a timeout | Idempotency key returns the original result |
| Server crash after charge | Recovery via processor lookup by reference; atomic phases |
| Processor timeout (unknown outcome) | Treat as **unknown**, not failure (Folder 01 file 03 §2.3 H6); query status; never re-charge blindly |
| Processor outage | Route to an alternate acquirer where contracts allow; degrade gracefully (queue captures, which are separate from auths) |
| Duplicate webhooks | Dedupe by provider event ID; handlers idempotent |
| Partial regional outage | Merchants pinned to home regions; idempotency store regional with the merchant; no cross-region synchronous dependency on the hot path |
| Silent drift between systems | Reconciliation as a first-class pipeline with SLAs on discrepancy resolution |

### 26.6 L5 / L6 / L7 and probing chain

| | L5 | L6 | L7 |
|---|---|---|---|
| Design | A payments table and a processor call | Idempotency keys, payment state machines, webhooks via outbox | Atomic phases with recovery points; unknown outcomes resolved by processor lookup; processor-side references; reconciliation as a correctness system |

1. **Probe:** "The client times out and retries." **L5:** "Check if a payment for this order exists."
2. **Probe:** "Two retries arrive concurrently." **L6:** "Insert the idempotency key with a unique constraint before
   charging; the loser gets 409 or waits."
3. **Probe:** "The server crashed after the processor charged but before writing the result." **L7:**
   - "The key is IN_PROGRESS with a lease. Recovery queries the processor by our reference, which is the idempotency
     key passed downstream."
   - "If the charge exists, record it and complete. If not, the charge never happened, so retry the phase."
   - "Correctness never depends on our process surviving; it depends on the external system being queryable by a key
     we control. That's the design requirement we put on processors."

---

## Problem 27: An immutable double-entry financial ledger with auditable reconciliation

### 27.1 Scope, scale and SLAs

| Quantity | Target |
|---|---|
| Postings | 100k journal entries/s peak (payments, fees, refunds, payouts, FX) |
| Accounts | 100M+ (merchant balances, customer wallets, internal clearing accounts) |
| Correctness | Debits = credits for every transaction; balances derivable from entries; nothing ever updated in place |
| Audit | Full history, reproducible balances at any timestamp, regulator-grade |
| Latency | Balance reads p99 < 50 ms; postings p99 < 100 ms |

### 27.2 Data model

```
journal_entry (immutable, append-only):
  entry_id, txn_id, account_id, amount (integer minor units + currency), direction, effective_ts, recorded_ts,
  idempotency/source ref, metadata
invariant per txn_id: Σ amounts = 0 (per currency); enforced in the posting transaction
accounts: account_id → {type: asset|liability|revenue|expense, currency, owner}
balances (derived, materialized): (account_id) → {balance, last_entry_id, version}   updated in the SAME txn as postings
                                  or computed by a streaming aggregator with exactly-once offsets
corrections: NEVER update/delete entries — post reversing entries (txn_id' referencing txn_id)
partition: by account_id for balances; journal partitioned by txn_id or time; multi-account postings that span
           partitions use a per-txn coordinator (or keep both accounts in one partition: e.g. per-merchant ledgers)
```

### 27.3 What catches what (§B of the output: 200,000 transfers, 0.1% one-sided and 0.1% duplicate postings injected)

| Check | One-sided postings (credit leg lost) | Duplicate postings (whole txn posted twice) |
|---|---|---|
| **Per-transaction balance check** (Σ = 0) | **189/189** | **0/197**: duplicates are balanced! |
| **Reconciliation against the processor's statement** (one movement per transfer) | — | **197/197** |
| System-wide sum of balances | −4,739,327 cents (≠ 0): reveals that *something* is wrong, not what | |

This is the reason ledgers have **two independent correctness mechanisms**:
1. **Structural invariants** inside the ledger. Every transaction balances, and that is enforced at write time, so a
   one-sided posting cannot commit.
2. **External reconciliation.** Compare against an *independent* source of truth: bank statements, card-network
   settlement files, the payment processor's records. That catches errors that are internally consistent:
   duplicates, wrong amounts on both legs, missing transactions.

A ledger that is "always balanced" can still be **wrong**. Reconciliation is how you know it is right.

### 27.4 Architecture and paths

```
 producers (payments, payouts, billing) ─► posting API (idempotent by source ref) ─► validate (Σ=0, accounts exist,
   currency rules, overdraft policy) ─► append entries + update balances in ONE transaction (single-partition when
   possible) ─► outbox → downstream (analytics, statements, risk)
 reads: balance (materialized row) ; history (entries by account, time-ordered) ; as-of balance (sum entries ≤ ts,
        or snapshots + replay)
 reconciliation: ingest external files → match by reference/amount/date → breaks → workflow (auto-resolve rules,
        human queue, aging SLAs) ; daily trial balance (Σ all = 0 per currency) ; immutable audit log export
```

### 27.5 The core L7 bottleneck: hot accounts and multi-partition postings

1. **Hot accounts.** Every card payment credits the same *internal clearing account* and the same fee account, so a
   single row takes 100k updates/s. Mitigations:
   - **sub-accounts** (shard the clearing account into N sub-accounts, sum for reporting: write salting for money);
   - **batch postings** per time window from a durable queue (net settlement);
   - **don't materialize** hot internal balances synchronously; compute them from entries asynchronously.
2. **Postings spanning partitions** (customer wallet A → merchant B on different shards) need atomicity. Options:
   - put both legs in one partition by design: per-merchant ledgers with a clearing account per partition;
   - a distributed transaction (Spanner/CRDB);
   - a saga with a **clearing/suspense account**: debit A → credit suspense, then debit suspense → credit B. Each
     step balances locally, and in-flight money is visible in suspense, which reconciliation watches (Folder 03 file
     03 Chain B).
3. **Overdraft and limits** need a read-check-write on the balance. Use a CAS on the balance version, or escrow-style
   reservations, never read-then-write (problem 23's lesson).

### 27.6 Failure defense

| Failure | Defense |
|---|---|
| Duplicate posting from retries | Idempotent posting API keyed by source reference |
| Partial posting | Σ=0 enforced in a single transaction; saga legs each balanced via suspense accounts |
| Reconciliation breaks | Aging SLAs; auto-resolution rules; never "plug" differences without a reversing-entry trail |
| Bug writes bad entries | Immutable log + reversing entries; replay from entries to rebuild balances; shadow ledgers for new logic |
| Currency/rounding | Integer minor units; explicit FX entries with rates; banker's rounding rules documented |

### 27.7 L5 / L6 / L7 and probing chain

| | L5 | L6 | L7 |
|---|---|---|---|
| Design | A balance column updated per transaction | Immutable entries, Σ=0 per transaction, materialized balances, reversals | Two independent correctness systems (structural + reconciliation; duplicates are balanced!); hot internal accounts sharded; suspense accounts for cross-partition sagas |

1. **Probe:** "Store a balance per account and update it." **L5:** "In a transaction."
2. **Probe:** "Auditors ask why a balance changed last March." **L6:** "Immutable journal entries; the balance is
   derived; corrections are reversing entries."
3. **Probe:** "Every transaction balances, yet the bank says we're $47k off." **L7:**
   - "Balanced isn't correct: a duplicated or mis-amounted transaction balances perfectly. The lab's duplicates
     passed 0/197 balance checks."
   - "Reconcile against independent external records by reference, amount and date. Breaks go to a workflow with
     aging SLAs, and every fix is a reversing entry."
   - "Then add a daily trial balance and a reconciliation-coverage SLI (the % of entries matched externally)."

---

## Problem 28: A sub-millisecond stock-exchange matching engine

### 28.1 Scope, scale and SLAs

| Quantity | Target |
|---|---|
| Order rate | 1–10M messages/s per venue at peak (orders, cancels, modifies) |
| Latency | Order-to-ack **< 10–100 µs** inside the matching core; tens of µs on the wire in colocation |
| Fairness | Strict **price-time priority**; deterministic, auditable |
| Availability | Failover in milliseconds to seconds without losing or reordering any order |
| Determinism | Replaying the input journal reproduces every trade exactly |

### 28.2 The core design: a single-threaded deterministic state machine in RAM

The LMAX architecture (Martin Fowler, *The LMAX Architecture*, 2011; LMAX Disruptor):
1. **A sequencer** assigns every inbound message a global sequence number and **journals it**: durable, replicated to
   a standby.
2. **One thread per order book** (symbol, or a symbol range) applies messages in sequence. No locks, no
   cross-thread state, no I/O on the critical path. Everything is in L1/L2-resident data structures (Folder 01 file
   02 §2: 1–4 ns per access vs ~115 ns DRAM).
3. **Outputs** (acks, trades, market data) are produced in sequence and published to downstream ring buffers.
4. **Replication = replaying the same journal** on a standby engine. Determinism makes the standby's state identical.

§C of the output (50,000 events: 80% limit, 10% market, 10% cancel):

| Run | Trades | State hash |
|---|---|---|
| Original | 31,120 | `0a08bb9c408067e6` |
| **Replay of the same journal** | 31,120 | `0a08bb9c408067e6`: **identical** |
| Same orders, 5% of adjacent pairs reordered | — | `509adb7025b3f07b`: **different, 8,294 trades differ** |

- **Order of arrival *is* the market.** Reordering just 5% of adjacent pairs changes thousands of trades: 8,294 in the
  symmetric difference of the two trade sets, against 31,120 trades.
- That's why the sequencer (a single total order) is the heart of an exchange, and why multi-threaded matching
  without a sequencer is unfair and unauditable.

### 28.3 Data structures

```
order book per symbol:
  bids: price levels sorted descending ; asks: ascending — each level a FIFO queue of orders (intrusive linked list)
  price → level map (array indexed by tick for dense books, or a tree/skip list); order_id → node (O(1) cancel)
  match: while incoming crosses best opposite level: fill against the level's FIFO head (price-time priority)
journal entry: (seq, timestamp, gateway_id, msg) → append-only, replicated before ack (or async with standby replay)
market data: incremental updates (add/modify/delete level), snapshot + sequence numbers for gap recovery
```

(The listing uses heaps with lazy deletion for clarity; production engines use per-tick arrays and intrusive lists
for O(1) operations and cache locality.)

### 28.4 Architecture

```
 member gateways (FIX/binary protocols; risk checks: credit, fat-finger, self-trade prevention, per-member rate limits)
   ─► sequencer (assigns seq, journals to replicated log: shared memory ring + network replication to standby)
   ─► matching engine (one thread per book; deterministic) ─► outputs ring ─► execution reports + market data
   ─► standby engine replays the same journal (hot) ─► failover: promote standby at seq N (no gap, no reorder)
 clearing/settlement downstream (T+1): trades → clearing house → ledger (problem 27)
 control: symbol configs, trading phases (auctions), circuit breakers (volatility halts) as SEQUENCED messages
```

**Even control actions** (halts, auctions, config) **go through the sequencer.** Every state change is in the
journal, so replay and audit are complete.

### 28.5 The core L7 bottleneck: tail latency and fairness, not throughput

1. **Tail latency.** One GC pause or page fault on the matching thread delays every order. The fixes:
   - no allocation on the hot path (object pools, off-heap);
   - pinned cores, isolated CPUs (`isolcpus`), busy-polling, huge pages;
   - kernel bypass for the network (Folder 01 file 02 §4.7);
   - pre-faulted memory.
2. **Fairness is a protocol property:** sequence by arrival at the sequencer. Some venues deliberately add
   **speed bumps** (IEX's 350 µs delay coil) or batch auctions to change fairness.
3. **Durability vs latency.** Synchronous replication of the journal to a standby adds µs to ms. Exchanges choose
   between in-memory replication to a nearby standby (µs) and async disk persistence.

### 28.6 Failure defense

| Failure | Defense |
|---|---|
| Matching engine crash | Hot standby replaying the journal; promote at the last seq; clients reconcile by seq |
| Sequencer failure | Replicated sequencer (primary/backup with seq handoff; consensus for the leader) |
| Runaway algo (fat finger, loop) | Pre-trade risk checks; per-member kill switches; volatility circuit breakers |
| Market-data gaps | Sequence numbers + snapshot/retransmission service |
| Clock disputes | Hardware timestamps (PTP, Folder 03 file 02) on ingress for audit (e.g. regulatory clock-sync rules) |

### 28.7 L5 / L6 / L7 and probing chain

| | L5 | L6 | L7 |
|---|---|---|---|
| Design | A database of orders with matching queries | In-memory order book, price-time priority, journaling | Sequencer + single-threaded deterministic engine; replay-based replication (bit-identical hashes); control actions as sequenced messages; tail-latency engineering |

1. **Probe:** "Use multiple threads to match faster." **L5:** "Lock per order book."
2. **Probe:** "Two orders arrive 1 µs apart on different threads." **L6:** "Arrival order becomes nondeterministic;
   use a sequencer and one thread per book."
3. **Probe:** "How do you fail over without losing fairness?" **L7:**
   - "The journal *is* the system. A standby replays the identical sequence, so its book is bit-identical (same
     state hash)."
   - "Failover promotes it at sequence N, and clients resend anything unacknowledged with idempotent client order
     IDs."
   - "Throughput scales by sharding books across engines, never by multi-threading one book."

---

## 29. The listing

```python
"""payments_ledger_exchange_lab.py - idempotent payments, double-entry ledgers, deterministic matching (Folder 08, file 02).

  A. Payment API under client retries, lost responses and server crashes between "charge the card" and "record the
     result": no idempotency vs an idempotency-key store with an in-progress lock and recovery.
  B. Double-entry ledger: random transfers as balanced journal entries; injected bugs (one-sided postings, duplicate
     postings) caught by per-transaction balance checks and by reconciliation against the processor's statement.
  C. Price-time-priority matching engine (limit, market, cancel): replaying the same input journal reproduces the same
     trades and state hash; the same orders processed in a different order do not.
Standard library only; seeded, deterministic.
"""
import collections
import hashlib
import heapq
import random


# ---------------------------------------------------------------- A. idempotent payments
class Processor:
    """The card network: charges are real side effects."""
    def __init__(self):
        self.charges: list = []

    def charge(self, ref: str, cents: int) -> str:
        self.charges.append((ref, cents))
        return f"ch_{len(self.charges)}"


def payments(requests: int, idempotent: bool, rng: random.Random) -> dict:
    proc = Processor()
    store: dict = {}                                          # idempotency_key -> ("in_progress", None) | ("done", resp)
    for i in range(requests):
        key = f"order-{i}"
        attempts = 1 + (rng.random() < 0.08) + (rng.random() < 0.02)       # client retries on timeout
        for _ in range(attempts):
            if idempotent:
                rec = store.get(key)
                if rec and rec[0] == "done":
                    continue                                  # replay the stored response; no new charge
                if rec and rec[0] == "in_progress":
                    # the earlier attempt crashed after charging but before recording: recover by asking the
                    # processor (charges carry our idempotency key as their reference), then finish
                    found = [c for c in proc.charges if c[0] == key]
                    store[key] = ("done", found[0] if found else proc.charge(key, 1000))
                    continue
                store[key] = ("in_progress", None)            # lock the key BEFORE the side effect
            ch = proc.charge(key, 1000)
            if rng.random() < 0.01:
                continue                                      # server crashes before recording the result
            if idempotent:
                store[key] = ("done", ch)
    per = collections.Counter(ref for ref, _ in proc.charges)
    return {"orders": requests, "charges": len(proc.charges), "double_charged_orders": sum(1 for c in per.values() if c > 1)}


# ---------------------------------------------------------------- B. ledger
def ledger(transfers: int, rng: random.Random) -> dict:
    accounts = [f"acct{i}" for i in range(50)]
    journal = []                                              # (txn_id, account, amount_cents); debits negative
    injected = {"one_sided": set(), "duplicate": set()}
    for t in range(transfers):
        a, b = rng.sample(accounts, 2)
        amt = rng.randint(1, 50_000)
        legs = [(t, a, -amt), (t, b, amt)]
        r = rng.random()
        if r < 0.001:
            legs = legs[:1]                                   # bug: credit leg lost
            injected["one_sided"].add(t)
        elif r < 0.002:
            legs = legs + legs                                # bug: transaction posted twice
            injected["duplicate"].add(t)
        journal.extend(legs)
    by_txn = collections.defaultdict(list)
    for t, acct, amt in journal:
        by_txn[t].append(amt)
    unbalanced = {t for t, amts in by_txn.items() if sum(amts) != 0}
    # reconciliation vs the external statement: the processor reports exactly one movement per transfer
    duplicated = {t for t, amts in by_txn.items() if len(amts) > 2}
    balances = collections.Counter()
    for _, acct, amt in journal:
        balances[acct] += amt
    return {"entries": len(journal), "unbalanced_detected": unbalanced, "duplicates_detected": duplicated,
            "injected": injected, "system_total": sum(balances.values())}


# ---------------------------------------------------------------- C. matching engine
class Book:
    """Price-time priority: best price first; FIFO within a price level (sequence number breaks ties)."""
    def __init__(self):
        self.bids: list = []                                  # (-price, seq, order_id, qty)
        self.asks: list = []                                  # (price, seq, order_id, qty)
        self.live: dict = {}                                  # order_id -> remaining qty (0 = cancelled/filled)
        self.trades: list = []
        self.seq = 0

    def _match(self, side: str, oid: int, price, qty: int) -> int:
        book = self.asks if side == "B" else self.bids
        while qty and book:
            key, s, rid, rq = book[0]
            best = key if side == "B" else -key
            if self.live.get(rid, 0) == 0:
                heapq.heappop(book)                           # lazily drop cancelled/filled orders
                continue
            if price is not None and ((side == "B" and best > price) or (side == "S" and best < price)):
                break
            fill = min(qty, self.live[rid])
            self.trades.append((oid, rid, best, fill))
            qty -= fill
            self.live[rid] -= fill
            if self.live[rid] == 0:
                heapq.heappop(book)
        return qty

    def submit(self, oid: int, side: str, price, qty: int) -> None:
        self.seq += 1
        rest = self._match(side, oid, price, qty)
        if rest and price is not None:                       # market orders never rest
            self.live[oid] = rest
            heapq.heappush(self.bids if side == "B" else self.asks,
                           (-price if side == "B" else price, self.seq, oid, rest))

    def cancel(self, oid: int) -> None:
        if oid in self.live:
            self.live[oid] = 0

    def state_hash(self) -> str:
        h = hashlib.sha256()
        h.update(repr(self.trades).encode())
        h.update(repr(sorted((k, v) for k, v in self.live.items() if v)).encode())
        return h.hexdigest()[:16]


def order_flow(n: int, rng: random.Random) -> list:
    flow = []
    for oid in range(n):
        r = rng.random()
        if r < 0.1 and oid > 10:
            flow.append(("cancel", rng.randrange(oid)))
        elif r < 0.2:
            flow.append(("new", oid, rng.choice("BS"), None, rng.randint(1, 50)))          # market
        else:
            side = rng.choice("BS")
            px = 10_000 + rng.randint(-50, 50) + (-10 if side == "B" else 10)
            flow.append(("new", oid, side, px, rng.randint(1, 100)))
    return flow


def run_book(flow: list) -> Book:
    b = Book()
    for ev in flow:
        if ev[0] == "new":
            b.submit(*ev[1:])
        else:
            b.cancel(ev[1])
    return b


def main() -> None:
    rng = random.Random(26)
    print("== A. payments: 100,000 orders, 8% + 2% client retries, 1% crashes between charge and record")
    pay = {i: payments(100_000, i, rng) for i in (False, True)}
    for i, r in pay.items():
        print(f"  {'idempotency keys + recovery' if i else 'no idempotency           '}: charges {r['charges']:>7} "
              f"for {r['orders']} orders; double-charged orders {r['double_charged_orders']:>6}")

    print("\n== B. double-entry ledger: 200,000 transfers, 0.1% one-sided and 0.1% duplicate postings injected")
    lg = ledger(200_000, rng)
    inj = lg["injected"]
    print(f"  journal entries {lg['entries']:,}; system-wide sum of balances {lg['system_total']:,} cents "
          f"(must be 0 in a closed system)")
    print(f"  per-transaction balance check caught {len(lg['unbalanced_detected'] & inj['one_sided'])}/"
          f"{len(inj['one_sided'])} one-sided postings; duplicates are balanced, so it caught "
          f"{len(lg['unbalanced_detected'] & inj['duplicate'])}/{len(inj['duplicate'])} of them")
    print(f"  reconciliation against the processor statement caught {len(lg['duplicates_detected'] & inj['duplicate'])}"
          f"/{len(inj['duplicate'])} duplicate postings")

    print("\n== C. matching engine: 50,000 events (limit 80%, market 10%, cancel 10%)")
    flow = order_flow(50_000, rng)
    a, b = run_book(flow), run_book(list(flow))
    shuffled = flow[:]
    for i in range(0, len(shuffled) - 1, 2):                    # swap adjacent events, as unsequenced threads might
        if rng.random() < 0.05:
            shuffled[i], shuffled[i + 1] = shuffled[i + 1], shuffled[i]
    c = run_book(shuffled)
    print(f"  trades {len(a.trades):,}; replay of the same journal: state hash {a.state_hash()} == {b.state_hash()} "
          f"-> {a.state_hash() == b.state_hash()}")
    print(f"  same orders, 5% of adjacent pairs reordered: {c.state_hash()} -> identical: {a.state_hash() == c.state_hash()}"
          f"; trades differing: {len(set(a.trades) ^ set(c.trades))}")

    assert pay[False]["double_charged_orders"] > 1000 and pay[True]["double_charged_orders"] == 0
    assert pay[True]["charges"] == 100_000
    assert inj["one_sided"] <= lg["unbalanced_detected"] and not (lg["unbalanced_detected"] & inj["duplicate"])
    assert inj["duplicate"] <= lg["duplicates_detected"] and lg["system_total"] != 0
    assert a.state_hash() == b.state_hash() and a.state_hash() != c.state_hash()
    print("\nself-test: all assertions passed")


if __name__ == "__main__":
    main()
```

Output (verified; deterministic):

```text
== A. payments: 100,000 orders, 8% + 2% client retries, 1% crashes between charge and record
  no idempotency           : charges  110008 for 100000 orders; double-charged orders   9848
  idempotency keys + recovery: charges  100000 for 100000 orders; double-charged orders      0

== B. double-entry ledger: 200,000 transfers, 0.1% one-sided and 0.1% duplicate postings injected
  journal entries 400,205; system-wide sum of balances -4,739,327 cents (must be 0 in a closed system)
  per-transaction balance check caught 189/189 one-sided postings; duplicates are balanced, so it caught 0/197 of them
  reconciliation against the processor statement caught 197/197 duplicate postings

== C. matching engine: 50,000 events (limit 80%, market 10%, cancel 10%)
  trades 31,120; replay of the same journal: state hash 0a08bb9c408067e6 == 0a08bb9c408067e6 -> True
  same orders, 5% of adjacent pairs reordered: 509adb7025b3f07b -> identical: False; trades differing: 8294

self-test: all assertions passed
```

---

## 30. References for problems 26–28

- Stripe Engineering. *Designing robust and predictable APIs with idempotency*, 2017. B. Leach, *Implementing
  Stripe-like Idempotency Keys in Postgres*, 2017.
- M. Kleppmann. *Designing Data-Intensive Applications*, ch. 11–12 (end-to-end idempotence).
- Modern Treasury / Square / Uber engineering posts on double-entry ledgers (⚠ verify the URLs in Folder 10).
- M. Fowler. *The LMAX Architecture*, 2011. LMAX Disruptor (lmax-exchange.github.io/disruptor).
- M. Thompson et al. *Disruptor: High performance alternative to bounded queues for exchanging data between
  concurrent threads*, 2011.
- IEX. *The Speed Bump* (350 µs delay). Nasdaq, CME public architecture talks (⚠ verify).
