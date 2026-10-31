# 04.2 · Attacks on Failure Modes: Data Loss, Duplication and Split-Brain (Questions 10–17)

> **Folder:** `04-Surviving-the-25-Brutal-Bar-Raiser-Cross-Examination-Questions` · file 2 of 3
> **Question this file answers:** once the interviewers accept that the design was needed, they try to break it. Where can a duplicate still come from? What happens to a write when the leader pauses? Can a user fail to see their own write? These 8 questions separate candidates who designed for failure from those who designed for the happy path.
> **Exhibits:** P-0 Beacon, A·Tidewater, B·Tillpoint, C·Quickset, D·Flightline.
> **Scope labels:** L5 = Senior, L6 = Staff, L7 = Principal / Senior Staff.

| Listing | Language | What it does | Where it runs |
|---|---|---|---|
| L12 `failure_sim.py` | Python 3, standard library | Five seeded simulations, each run without and then with its guard:<br>F1. at-least-once consumer crashes → duplicate effects, plain vs idempotent sink;<br>F2. producer retries after lost acks → duplicates, plain vs idempotent producer;<br>F3. split brain from a lease outliving a pause → lost updates, without vs with fencing tokens;<br>F4. read-your-writes on an async replica → stale reads, vs waiting for the session's commit position;<br>F5. last-writer-wins across regions with clock skew. | [§6](#6-the-failure-simulator) |

**Verification.** The gate extracts the listing, checks it byte for byte against the source, re-runs it, and compares the result with §6. The seeds are fixed, so the output is deterministic. The tool's verdict confirms that every unguarded mode fails and every guard removes the failure. Tellings are checked by the Folder 01 lints. Results are in the [README](../README.md#gate-results).

---

## 0. Orientation

These are the questions that find **unhandled failure modes**. They're usually asked as scenarios: "the consumer crashes here", "the leader pauses there". What is being evaluated is whether you can trace the system's behavior through the failure **step by step**, name the invariant at risk, and point to the mechanism that protects it. "It's handled by the framework" is the answer that fails them all.

The simulator (§6) turns each scenario into numbers you can quote: how many duplicates, how many lost updates, how many stale reads. It also shows how the guard removes them.

---

## 1. First principles: failures are orderings you didn't plan for

### 1.1 Three facts behind every question in this file

1. **Networks and processes fail between steps.** Any two-step action can be interrupted after the first step. "Write, then commit the offset", "charge, then record" and "acquire the lease, then write" all have a gap.
2. **"Delivered exactly once" doesn't exist across a failure boundary; "effective exactly once" does.** It is achieved with at-least-once delivery plus idempotent effects (03.1 §4, 03.2 §4).
3. **Time is not a reliable ordering mechanism across machines.** Leases expire on one clock and are checked on another, and wall clocks skew. Lamport's "Time, clocks, and the ordering of events in a distributed system" (*CACM* 21(7), 1978, DOI 10.1145/359545.359563) is the foundational treatment.

### 1.2 The tracing method interviewers reward

For any failure scenario:
1. **Draw the steps** of the operation as a sequence, with the durable state after each step.
2. **Mark every gap** where a crash, timeout or pause can occur.
3. **For each gap, say what's true afterwards:** what is durable, what isn't, and who will retry.
4. **Name the invariant** at risk (no double effect, no lost effect, no stale read, a single writer).
5. **Name the mechanism** that protects it at that gap, and its cost.

---

## 2. Defense cards: Questions 10–17

### Q10 · "You say exactly-once. Show me every place a duplicate can still come from."

| | |
|---|---|
| **Tests** | Whether "exactly-once" is a product claim or a designed property |
| **Trap** | Naming the framework's guarantee and stopping |
| **Skeleton** | Walk the pipeline end to end: source replays (CDC restarts) → producer retries → consumer redelivery → sink retries → backfill overlap. For each, name the guard (event-id dedup, idempotent producer, idempotent sink or transactional commit, handoff rule) → then the measurement (reconciliation) |
| **Numbers** | Dedup horizon vs the replay window; reconciliation mismatches found |
| **Variants** | Tidewater: 5 sources of duplicates, each guarded. Tillpoint: client retries (idempotency key), gateway retries (key passed downstream), outbox relay crash (consumer dedup). |

### Q11 · "The consumer applies the effect, then crashes before committing its offset."

| | |
|---|---|
| **Tests** | At-least-once mechanics, and where idempotency must live |
| **Trap** | "The framework handles it" |
| **Skeleton** | After restart, the consumer resumes from the last committed offset → every message since that commit is redelivered, including the one whose effect landed → plain effects duplicate (F1: 5,828 duplicate effects at a 0.001 crash rate with commits every 100) → fix: an idempotent effect keyed by message id, *or* committing the offset atomically with the effect (same database transaction) |
| **Numbers** | Commit interval (sets the redelivery size); crash rate; duplicates per crash |
| **Variants** | Tillpoint: the processed-events table in the same transaction as the effect. Beacon SDK: applying a snapshot is idempotent by version. |

### Q12 · "Your producer retries on timeout. How do you know it didn't write twice?"

| | |
|---|---|
| **Tests** | Lost-ack semantics; idempotent producers |
| **Trap** | "Retries are safe because we have acks" |
| **Skeleton** | A timeout means unknown: the write may have landed → a plain retry appends again (F2: 200 duplicates from 100,000 sends at a 0.002 lost-ack rate) → fix: the broker deduplicates by (producer id, sequence number), which is Kafka's idempotent producer ([producer configs](https://kafka.apache.org/documentation/#producerconfigs_enable.idempotence)), or an idempotency key at the application level |
| **Numbers** | Lost-ack rate; duplicates per million sends |
| **Variants** | Tillpoint's gateway call: the same failure at a payment API, solved by passing the idempotency key and resolving timeouts by query (03.2 §4.3). |

### Q13 · "The leader pauses for 30 seconds and its lease expires. Now there are two leaders."

| | |
|---|---|
| **Tests** | Whether leases alone are trusted; fencing tokens |
| **Trap** | "The lease prevents two leaders", which is false across a process pause |
| **Skeleton** | Leases are time-based, and a paused process doesn't know time passed → after the pause it acts on a stale belief (F3: 6 lost updates) → fix: every lease grant carries a monotonically increasing **fencing token**, and the *storage* rejects writes carrying a token lower than the highest it has seen (F3: the stale write rejected, 0 lost). This is the argument in Kleppmann's "How to do distributed locking" ([kleppmann.com](https://martin.kleppmann.com/2016/02/08/how-to-do-distributed-locking.html)) |
| **Numbers** | Lease duration vs the longest observed pause (GC, VM migration); token checks per write |
| **Variants** | Beacon's publisher leader lease: publish requests carry the lease epoch, and object writes are content-addressed and version-gated, so a stale leader's publish can't regress the version. Tillpoint's saga: state-guarded transitions act as a fencing check. |

### Q14 · "A user writes, then reads from a replica and doesn't see the write. Bug?"

| | |
|---|---|
| **Tests** | Consistency models, and whether you chose one deliberately |
| **Trap** | "Replication is fast, so it doesn't happen" (F4: 37.4% stale under an 80 ms mean lag with reads 0–200 ms later) |
| **Skeleton** | It's a bug only if read-your-writes was promised → ways to provide it: read from the primary for the session's recent writes; carry the commit position (LSN) in the session and have the replica wait until it has replayed past it (F4: 0 stale, p99 extra wait 369 ms in the model); synchronous replication with `remote_apply` ([PostgreSQL WAL settings](https://www.postgresql.org/docs/current/runtime-config-wal.html)) → choose by which reads need it |
| **Numbers** | Replica lag distribution; the fraction of reads that need read-your-writes; the wait cost |
| **Variants** | Tillpoint: order status after checkout reads the primary for 5 s, everything else reads replicas. Beacon: the SDK's applied-version report gives "read your config change" semantics per instance. |

### Q15 · "Backfill and live traffic overlap for a day. Are your counts right?"

| | |
|---|---|
| **Tests** | Whether two writers to one dataset were designed for |
| **Trap** | "Dedup handles it", when dedup state isn't shared between the batch and streaming jobs |
| **Skeleton** | Name the two writers → name what each one dedups against → a handoff rule (timestamp) and partition ownership → idempotent partition replacement → reconciliation in both directions |
| **Numbers** | Overlap window; mismatch detected (INC-T4: +0.7% on one partition-day) |
| **Variants** | Tidewater INC-T4 (03.1 §7). Beacon: the ZooKeeper bridge's shadow mode had two readers, never two writers, by design. |

### Q16 · "A poison message is blocking a partition. What happens to everything behind it?"

| | |
|---|---|
| **Tests** | Ordering vs availability trade-offs in consumers |
| **Trap** | "We retry until it works", which blocks forever |
| **Skeleton** | Bounded retries with backoff → park the message (DLQ) with its reason → **decide what happens to later messages for the same key**: skip ahead (breaks per-key order) or park the key too (preserves order, delays the key) → a replay tool after the fix → an alert on DLQ growth |
| **Numbers** | Retry count and backoff; DLQ size alert threshold; parked-key count |
| **Variants** | Tidewater: malformed records go to the DLQ with the reason; schema-incompatible records are parked; replay after a fix. Tillpoint: a payment event for an order whose earlier event is parked must park too, because order matters per order. |

### Q17 · "Two events for the same key arrive out of order across regions. Which one wins?"

| | |
|---|---|
| **Tests** | Conflict resolution, and whether wall clocks are trusted |
| **Trap** | "The one with the later timestamp", which is last-writer-wins with skewed clocks (F5: the later write loses ~20% of the time with ±30 ms skew and writes 0–50 ms apart) |
| **Skeleton** | Avoid the conflict: a single writer per key (a home region) → or order by a per-key version from one sequencer → or merge, if the data type allows (counters, sets) → use timestamps only as a tie-breaker hint, never as truth → surface true conflicts instead of silently dropping one |
| **Numbers** | Clock skew bound; write gap distribution; conflict rate |
| **Variants** | Beacon: one publisher per namespace and monotonic versions, so no cross-region writes. Tillpoint: orders have a home region; the standby region doesn't accept writes. |

---

## 3. Tellings

### 3.1 Split brain

#### How an L5 tells it

> We used a distributed lock with a lease, so only one leader could write at a time. If the leader died, the lease would expire and another node would take over, which basically handles split-brain.

#### How an L7 tells it

> The lease alone doesn't prevent 2 writers; it only bounds how long the system waits before electing a new one. A leader that pauses for longer than the lease (a 15-second GC pause in our case, against a 10-second lease) wakes up still believing it leads and writes with a stale view. In my simulation of exactly that, 6 of 19 increments were lost. So every lease grant carries a fencing token that only goes up, and the storage layer rejects any write whose token is below the highest it has accepted. The old leader's write is refused, and 0 updates are lost. In Beacon, the publisher's lease epoch plays that role, and versions that only go up make a stale publish harmless even if it got through.

### 3.2 Exactly-once

#### How an L5 tells it

> The whole pipeline is basically exactly-once end to end, because we used Kafka transactions and Dataflow, so there are no duplicates anywhere.

#### How an L7 tells it

> I'd say the pipeline has exactly-once effects in the warehouse, and that's a property I built rather than one I bought. There are 5 places duplicates can come from: CDC connector replays, producer retries, consumer redelivery, sink retries, and backfill overlapping the stream. Each has a named guard: event-id dedup with a 7-day horizon, the broker's producer sequence numbers, the runner's checkpointed reads, the sink's exactly-once write mode, and the handoff rule. Then I measure it, because guards fail: reconciliation compares source and warehouse totals per table and partition-day, and in the dual run it found 11 mismatches, 1 of them from my own backfill design.

### 3.3 Poison messages

#### How an L5 tells it

> If a message fails, we send it to a dead-letter queue so it doesn't block the pipeline, which is the best practice, and someone can look at it later.

#### How an L7 tells it

> A dead-letter queue is half the answer; the other half is what happens to the next messages for the same key. In Tillpoint, events for 1 order must apply in order, so I designed the consumer to park an order's later events behind its failed one, after 5 retries with backoff, rather than skip them, while other orders keep flowing. The DLQ entry records the reason and the consumer version. After a fix, a replay tool re-processes the parked key's events in order. The alert fires on DLQ growth above 50 messages in 10 minutes, because 1 bad deploy produces a wave, not a trickle.

---

## 4. Hiring-committee scoring rubric: failure-mode attacks

| Dimension | Poor | Borderline | Solid (L6) | Outstanding (L7) |
|---|---|---|---|---|
| **Tracing** | "It's handled" | Names the failure | Step-by-step with durable state after each step | Every gap named, with the invariant and the guard |
| **Duplicates** | "Exactly-once" | One guard | All sources and guards | Plus measurement (reconciliation) and a mismatch they found |
| **Split brain** | "We use a lock" | Lease mentioned | Fencing tokens | Storage-enforced fencing; the pause-length vs lease analysis |
| **Consistency** | "Replication is fast" | Names eventual consistency | Read-your-writes where needed | Chooses per read path, with the wait cost |
| **Ordering** | Timestamps decide | Knows skew exists | Single writer per key or versions | Plus conflict surfacing; timestamps only as hints |

---

## 5. Archetype mapping

| Question | A·Tidewater | B·Tillpoint | C·Quickset | D·Flightline | Beacon |
|---|---|---|---|---|---|
| Q10 duplicates | 5 sources, 5 guards | Idempotency key end to end | Versioned updates | Latest-value table per label: a repeated word is harmless | Version gate |
| Q11 consumer crash | Runner checkpoints | Processed-events table | Updates idempotent by version | Ring never re-delivers | Idempotent apply |
| Q13 split brain | Single job (managed) | Saga state guard | Single writer per shard | Single executive | Lease epoch + monotonic versions |
| Q14 read-your-writes | Freshness SLO, not RYW | Primary reads for 5 s | Miss-fill version check | n/a | Applied-version reports |
| Q16 poison | DLQ + parking | Per-order parking | Bad updates rejected by validation | Parity/SSM rejection, counted | Validator rejects before publish |
| Q17 ordering | Per-key partitions | Home region | Per-key versions | Per-label latest value | One publisher per namespace |

---

## 6. The failure simulator

### 6.1 Listing L12: `failure_sim.py`

<!-- listing:failure_sim.py -->
```python
#!/usr/bin/env python3
"""failure_sim.py - seeded simulations of the failure modes cross-examiners ask about.

  F1 at-least-once consumer: effect applied, crash before the offset commit
     -> redelivery; duplicates with a plain sink vs an idempotent sink
  F2 producer retry after a lost ack -> duplicate writes; vs an idempotent
     producer (per-producer sequence numbers deduplicated by the broker)
  F3 split brain: a leader pauses past its lease, a new leader is elected, the
     old one wakes and writes; lost updates without fencing vs with fencing tokens
  F4 read-your-writes on an async replica: stale reads vs waiting for the
     session's commit position (LSN) on the replica
  F5 last-writer-wins across regions with clock skew: how often the write that
     happened last loses

Usage: python -I failure_sim.py [<file.md>]   (argument ignored; deterministic seeds)
"""
import random
import sys


def f1(n=100_000, p_crash=0.001, batch=100, seed=1):
    rng = random.Random(seed)
    plain = set_effects = 0
    applied_ids = set()
    committed = 0
    i = 0
    redelivered = 0
    while i < n:
        msg = i
        plain += 1
        applied_ids.add(msg)
        set_effects = len(applied_ids)
        if rng.random() < p_crash:          # crash after the effect, before the commit
            redelivered += i - committed + 1
            i = committed                   # resume from the last committed offset
            continue
        i += 1
        if i % batch == 0:
            committed = i
    return plain - n, set_effects - n, redelivered


def f2(n=100_000, p_lost_ack=0.002, seed=2):
    rng = random.Random(seed)
    log_plain, seen = 0, set()
    for seq in range(n):
        log_plain += 1
        seen.add(seq)
        if rng.random() < p_lost_ack:       # write landed, ack lost, producer retries
            log_plain += 1                  # plain producer: broker appends again
            seen.add(seq)                   # idempotent producer: (producer, seq) already seen
    return log_plain - n, len(seen) - n


def f3(fencing):
    store = {"value": 0, "max_token": 0, "writes_applied": 0}

    def write(token, new_value):
        if fencing and token < store["max_token"]:
            return False                    # storage rejects the stale leader
        store["max_token"] = max(store["max_token"], token)
        store["value"] = new_value
        store["writes_applied"] += 1
        return True

    increments, rejected = 0, 0
    a_token, a_seen = 1, None
    for t in range(0, 12):                  # A is leader, increments once per second
        write(a_token, store["value"] + 1)
        increments += 1
    a_seen = store["value"]                 # A reads, then pauses 15 s (GC / VM migration)
    b_token = 2                             # lease (10 s) expires; B elected at t=21
    for t in range(21, 27):
        write(b_token, store["value"] + 1)
        increments += 1
    # t=27: A resumes, still believes it leads, writes based on its stale read
    if not write(a_token, a_seen + 1):
        rejected += 1
    else:
        increments += 1
    lost = increments - store["value"]
    return store["value"], increments, lost, rejected


def f4(n=10_000, mean_lag_ms=80.0, seed=4):
    rng = random.Random(seed)
    stale = 0
    waited_ms = []
    for _ in range(n):
        lag = rng.expovariate(1.0 / mean_lag_ms)
        read_after = rng.uniform(0, 200)
        if lag > read_after:
            stale += 1
            waited_ms.append(lag - read_after)   # LSN-wait: block until the replica catches up
    waited_ms.sort()
    p99 = waited_ms[int(0.99 * len(waited_ms))] if waited_ms else 0.0
    return stale, p99


def f5(n=100_000, skew_ms=30.0, gap_ms=50.0, seed=5):
    rng = random.Random(seed)
    wrong = 0
    for _ in range(n):
        t1 = 0.0
        t2 = rng.uniform(0, gap_ms)               # second write really happens later
        s1 = rng.uniform(-skew_ms, skew_ms)
        s2 = rng.uniform(-skew_ms, skew_ms)
        if t2 + s2 < t1 + s1:                     # its timestamp says earlier -> it loses
            wrong += 1
    return wrong


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    ok = True
    d_plain, d_idem, redeliv = f1()
    print("F1 at-least-once consumer: 100,000 messages, crash p=0.001 after the effect, commit every 100")
    print(f"   redelivered {redeliv:,} messages; duplicate effects: plain sink {d_plain:,}, idempotent sink {d_idem}")
    ok &= d_plain > 0 and d_idem == 0

    p_plain, p_idem = f2()
    print("F2 producer retry after a lost ack: 100,000 sends, ack lost p=0.002")
    print(f"   duplicate records: plain producer {p_plain:,}, idempotent producer {p_idem}")
    ok &= p_plain > 0 and p_idem == 0

    v0, inc0, lost0, rej0 = f3(fencing=False)
    v1, inc1, lost1, rej1 = f3(fencing=True)
    print("F3 split brain: A pauses 15 s past a 10 s lease, B elected, A wakes and writes")
    print(f"   no fencing  : final value {v0}, increments performed {inc0}, lost updates {lost0}, rejected {rej0}")
    print(f"   fencing     : final value {v1}, increments performed {inc1}, lost updates {lost1}, rejected {rej1}")
    ok &= lost0 > 0 and lost1 == 0 and rej1 == 1

    stale, p99_wait = f4()
    print("F4 read-your-writes on an async replica: 10,000 sessions, lag ~ exp(mean 80 ms), read 0-200 ms later")
    print(f"   stale reads without a guard: {stale:,} ({stale / 100:.1f}%); with LSN-wait: 0 stale, p99 extra wait {p99_wait:.0f} ms")
    ok &= stale > 0

    wrong = f5()
    print("F5 last-writer-wins across 2 regions: clocks skewed +/-30 ms, writes 0-50 ms apart, 100,000 pairs")
    print(f"   the later write loses in {wrong:,} pairs ({wrong / 1000:.1f}%) -> use versions or per-key leaders, not wall clocks")
    ok &= wrong > 0

    print()
    print("verdict:", "OK (each unguarded mode fails, each guard removes the failure)" if ok else "CHECK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
```

### 6.2 Output

<!-- output:failure_sim.py -->
```text
F1 at-least-once consumer: 100,000 messages, crash p=0.001 after the effect, commit every 100
   redelivered 5,828 messages; duplicate effects: plain sink 5,828, idempotent sink 0
F2 producer retry after a lost ack: 100,000 sends, ack lost p=0.002
   duplicate records: plain producer 200, idempotent producer 0
F3 split brain: A pauses 15 s past a 10 s lease, B elected, A wakes and writes
   no fencing  : final value 13, increments performed 19, lost updates 6, rejected 0
   fencing     : final value 18, increments performed 18, lost updates 0, rejected 1
F4 read-your-writes on an async replica: 10,000 sessions, lag ~ exp(mean 80 ms), read 0-200 ms later
   stale reads without a guard: 3,738 (37.4%); with LSN-wait: 0 stale, p99 extra wait 369 ms
F5 last-writer-wins across 2 regions: clocks skewed +/-30 ms, writes 0-50 ms apart, 100,000 pairs
   the later write loses in 19,911 pairs (19.9%) -> use versions or per-key leaders, not wall clocks

verdict: OK (each unguarded mode fails, each guard removes the failure)
```

**Reading the output.** Every unguarded run produces the failure the question describes, and every guard removes it:
- **F1:** 5,828 duplicate effects with a plain sink, 0 with an idempotent one.
- **F2:** 200 duplicate records from a plain producer, 0 from an idempotent one.
- **F3:** 6 lost updates without fencing; the stale write rejected with fencing.
- **F4:** 37.4% stale reads unguarded. Waiting for the session's commit position removes them at a p99 cost of 369 ms in this model.
- **F5:** last-writer-wins loses the later write about 20% of the time at ±30 ms skew.

Quote the *shape*. The exact numbers depend on the parameters, which you should replace with your own crash rates, lag distributions and skew bounds.

---

## 7. Failure modes (in your answers)

| # | Failure mode | Symptom | Fix |
|---|---|---|---|
| F1 | Framework as answer | "Kafka/Dataflow handles it" | Trace the steps (§1.2) |
| F2 | Missing a duplicate source | Backfill or source replays forgotten | Walk every hop (Q10) |
| F3 | Timeout treated as failure | Retry with a new identity | Unknown → query or idempotent retry (Q12) |
| F4 | Lease trusted alone | Split brain under pauses | Fencing tokens enforced by storage (Q13) |
| F5 | Consistency by hope | "Replication is fast" | Choose read-your-writes per path (Q14) |
| F6 | Two writers, one dataset | Double counts | Handoff + ownership (Q15) |
| F7 | Infinite retry | A blocked partition | Bounded retry, park, per-key policy (Q16) |
| F8 | Wall-clock LWW | Silent lost writes | Single writer per key or versions (Q17) |

---

## 8. Bar-raiser chains

<details><summary><b>Q10 · "You say exactly-once. Show me every place a duplicate can still come from."</b></summary>

**Initial Prompt.** On Tidewater: "Walk the whole path. Every place a duplicate can be born, and what kills it."

**L5 Answer.** "Duplicates can't really happen because Dataflow is exactly-once and BigQuery deduplicates."

**Why L5 Stalls.** Dataflow's guarantee covers its own committed outputs, not upstream replays. And BigQuery's deduplication behavior depends on the write method. The candidate has named two products, not five mechanisms.

**L7 Answer.** "Five places, left to right. One: the CDC connector replays from its last checkpoint on restart, so the same change appears twice in Kafka. Dedup by event id with a 7-day horizon kills it. Two: producer retries after a lost ack. The broker's per-producer sequence numbers kill those. Three: pipeline worker retries and restarts. The runner's checkpointed reads and committed outputs cover them. Four: sink write retries. The exactly-once Storage Write API mode, with offsets, covers those. Five: backfill overlapping the stream, which dedup can't see, because it's a different job. The handoff timestamp and partition ownership kill that one. And because 5 guards can still fail, reconciliation compares totals per table and partition-day in both directions. It found the fifth class the hard way in INC-T4."

</details>

<details><summary><b>Q11 · "The consumer applies the effect, then crashes before committing its offset. What happens?"</b></summary>

**Initial Prompt.** On Tillpoint's loyalty consumer: "It credits points, then dies before committing. Walk me through the restart."

**L5 Answer.** "It would reprocess the message, but our consumers are idempotent, so it's fine."

**Why L5 Stalls.** "Our consumers are idempotent" is an assertion, and INC-P9 showed it was false for at least one consumer. The interviewer wants the mechanism and its location.

**L7 Answer.** "On restart, the consumer resumes from the last committed offset, so every message since that commit is redelivered, including the one whose points were already credited. With commits every 100 messages, a crash redelivers up to 100. In my simulation at a 0.1% crash rate that's about 5,800 duplicate effects per 100,000 messages with a plain sink. The loyalty consumer avoids it by writing the credit and the message id into its own database in 1 transaction, with a unique constraint on the message id, so a redelivered message inserts nothing and credits nothing. The alternative is committing the offset in the same transaction as the effect, which works when the consumer owns the offset store. Every consumer has the redelivery test from INC-P9 in CI."

</details>

<details><summary><b>Q12 · "Your producer retries on timeout. How do you know it didn't write twice?"</b></summary>

**Initial Prompt.** "The send times out. You retry. Did the first one land?"

**L5 Answer.** "We set acks to all, so if it times out the write didn't succeed, and retrying is safe."

**Why L5 Stalls.** A timeout doesn't mean the write failed. The broker may have written it and the ack been lost. "Acks all" makes a landed write durable; it says nothing about whether a retry duplicates it.

**L7 Answer.** "A timeout means I don't know, and a plain retry appends a second copy if the first landed. In my simulation, 0.2% lost acks on 100,000 sends gives 200 duplicates. The fix is to make the retry recognizable. Kafka's idempotent producer attaches a producer id and a per-partition sequence number, and the broker discards a retried batch it has already written, so in-session retries don't duplicate. That doesn't cover a producer that restarts and resends from its own source, which is why the event also carries an application-level event id that consumers dedup on. The same shape applies to payment gateways: pass an idempotency key, and resolve the timeout by asking, never by retrying with a new identity."

</details>

<details><summary><b>Q13 · "The leader pauses for 30 seconds, its lease expires, and there are two leaders. What stops them corrupting data?"</b></summary>

**Initial Prompt.** On Beacon's publisher: "GC pause, VM migration, whatever. Your leader goes silent past its lease, another is elected, then the old one wakes up mid-publish."

**L5 Answer.** "The lease makes sure only one leader exists at a time, so the old one would know it lost the lease."

**Why L5 Stalls.** A paused process can't know time passed until it checks, and it may act between waking and checking. The lease bounds the *failover delay*, not the number of writers.

**L7 Answer.** "The lease doesn't stop it; fencing does. A paused leader wakes believing it still leads and can issue a write before it re-checks. In a simulation with a 15-second pause and a 10-second lease, the stale leader's write lost 6 updates. Every lease grant comes with an epoch that only goes up, and every publish carries it. The object store writes are content-addressed, and the version pointer is a conditional update that is rejected if the epoch is lower than the last one applied, so the woken leader's publish is refused. Separately, versions that only go up mean that even a stale publish that got through couldn't move clients backwards. I also measured our worst GC pause, 1.4 seconds, against the 10-second lease, so this is the rare path, but it's closed."

</details>

<details><summary><b>Q14 · "A user writes, then reads from a replica and doesn't see their write. Is that a bug?"</b></summary>

**Initial Prompt.** On Tillpoint: "Customer places an order, refreshes the order page, and it's not there. Bug?"

**L5 Answer.** "It could happen briefly because of replication lag, but the lag is usually very small, so it's not really an issue."

**Why L5 Stalls.** "Usually very small" isn't a consistency model. With a mean lag of 80 ms and reads within 200 ms of the write, the simulation shows about 37% of such reads are stale, which is very much an issue for this read.

**L7 Answer.** "For that read, yes. We promise read-your-writes on order status, because a customer who doesn't see their order places it again. Lag makes it common, not rare: with an 80-millisecond mean lag and the page reload within 200 milliseconds, about 37% of those reads would be stale. For the order-status endpoint only, reads go to the primary for 5 seconds after the session's last write, tracked in the session. Catalog and history reads stay on replicas, where staleness is harmless. Where I need read-your-writes on a replica, the session carries its commit LSN and the replica waits until it has replayed past it. That removes stale reads at a tail cost, about 370 milliseconds at p99 in the model, so I use it only where waiting is acceptable."

</details>

<details><summary><b>Q15 · "Backfill and live traffic overlap for a day. Are your counts right?"</b></summary>

**Initial Prompt.** On Tidewater: "You re-run the backfill for last Tuesday while the stream is live. Double counts?"

**L5 Answer.** "No, because dedup removes any duplicates between the backfill and the stream."

**Why L5 Stalls.** Dedup state lives inside the streaming job; the batch backfill can't see it. That's precisely the mechanism behind INC-T4.

**L7 Answer.** "They were wrong once, which is why they're right now. The streaming job's dedup state is invisible to the batch backfill, so in INC-T4 my re-run of 1 day overlapped the stream's writes and the partition came out 0.7% high. Reconciliation caught it 4 hours before the regulatory extract. The design now has 3 rules. A handoff timestamp: the backfill writes only events committed before it, the stream only after. A partition-ownership table: each partition-day has exactly 1 writer type, and the backfill tool refuses stream-owned days. And idempotent partition replacement: a backfill writes a staging table and swaps the whole partition, so re-running it twice changes nothing. Reconciliation runs within an hour of each day closing, in both directions."

</details>

<details><summary><b>Q16 · "A poison message is blocking a partition. What happens to everything behind it?"</b></summary>

**Initial Prompt.** "One malformed event. Your consumer throws on it, forever. What happens to the other 40,000 events queued behind it?"

**L5 Answer.** "We'd move the bad message to a dead-letter queue and continue processing the rest."

**Why L5 Stalls.** It skips the hard question: if later events for the *same key* depend on the parked one, continuing breaks per-key ordering. It also says nothing about bounded retries or detection.

**L7 Answer.** "First, bounded retries: 5 attempts with exponential backoff, because many failures are transient, like a dependency timeout. Then the event is parked in the DLQ with its error, consumer version and key. The design choice is what happens to later events for that key. For Tillpoint's order events, order matters per order, so the key is parked too: its later events go to the parking topic behind it, and the other orders keep flowing. That costs 1 order's delay, not the partition's. For Tidewater's raw records, which are independent rows, the bad record is parked alone. After a fix, the replay tool re-processes a parked key's events in order. The alert is DLQ growth above 50 in 10 minutes, because a bad deploy produces a wave."

</details>

<details><summary><b>Q17 · "Two events for the same key arrive out of order across regions. Which one wins, and why?"</b></summary>

**Initial Prompt.** "Two regions both accept writes for the same customer record. They conflict. Who wins?"

**L5 Answer.** "The one with the latest timestamp wins. We use last-writer-wins."

**Why L5 Stalls.** Last-writer-wins on wall clocks loses real writes whenever skew exceeds the gap between them: about 20% of the time with ±30 ms skew and writes 0–50 ms apart, in the simulation. Silently.

**L7 Answer.** "In my designs, mostly nobody, because I avoid the conflict. Wall-clock last-writer-wins drops the later write whenever clock skew exceeds the gap between writes, about 20% of the time in a simulation with 30-millisecond skew. In Tillpoint, each customer has a home region that accepts their writes, and the other region forwards to it, so there's 1 writer per key. In Beacon, 1 publisher per namespace issues versions that only go up, so ordering comes from the sequencer, not clocks. Where multi-region writes are truly needed, I use a per-key version and surface conflicts to the application, or a mergeable data type when the semantics allow it, such as counters or sets. Timestamps are a tie-breaker hint at most."

</details>

---

## 9. Checklist

- [ ] The step-by-step trace, with durable state after each step, for your system's core write path (§1.2).
- [ ] Every duplicate source and its guard, plus the measurement that proves the guards work (Q10).
- [ ] Your consumers' idempotency mechanism, named per consumer, and a redelivery test (Q11).
- [ ] Timeout semantics for every external call and producer (Q12).
- [ ] Lease duration vs the longest observed pause, and fencing at the storage layer (Q13).
- [ ] Which reads need read-your-writes, and how each gets it (Q14).
- [ ] Two-writer scenarios (backfill, migration, dual-write) and their handoff rules (Q15).
- [ ] Poison-message policy, including the per-key ordering decision (Q16).
- [ ] Conflict policy for any key that can be written in more than one place (Q17).
- [ ] `failure_sim.py` re-run with your own parameters (§6).

---

## 10. References

- Leslie Lamport, "Time, clocks, and the ordering of events in a distributed system", *Communications of the ACM* 21(7):558–565, 1978. DOI 10.1145/359545.359563 (verified via Crossref).
- Martin Kleppmann, "How to do distributed locking" (fencing tokens). <https://martin.kleppmann.com/2016/02/08/how-to-do-distributed-locking.html>
- Google SRE Book, "Managing Critical State: Distributed Consensus for Reliability". <https://sre.google/sre-book/managing-critical-state/>
- Apache Kafka documentation, producer configuration (`enable.idempotence`). <https://kafka.apache.org/documentation/#producerconfigs_enable.idempotence>
- PostgreSQL documentation, Write Ahead Log settings (`synchronous_commit`, including `remote_apply`). <https://www.postgresql.org/docs/current/runtime-config-wal.html>
- PostgreSQL documentation, system administration functions (WAL positions on primary and standby). <https://www.postgresql.org/docs/current/functions-admin.html>
- Jepsen, analyses of distributed systems' consistency claims. <https://jepsen.io/analyses>
- Google Cloud, "Exactly-once in Dataflow". <https://cloud.google.com/dataflow/docs/concepts/exactly-once>
