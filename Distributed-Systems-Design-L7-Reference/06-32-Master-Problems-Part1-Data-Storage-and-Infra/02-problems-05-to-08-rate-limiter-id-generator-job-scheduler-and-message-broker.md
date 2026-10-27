# Problems 5–8: Distributed Rate Limiter, Unique ID Generator, Delayed Job Scheduler, Message Broker

> **Folder 06 · File 02** of the Distributed Systems & System Design L7 Reference.
> **Listing:** `limiter_idgen_lab.py` covers:
> - limiter accuracy against boundary bursts (fixed window, sliding log, sliding counter, GCRA);
> - distributed limiting under skew;
> - Snowflake IDs under clock regression;
> - a hierarchical timing wheel verified against a heap.
>
> The output is deterministic.
> **Blueprint per problem:** scale/SLA → schema and partition key → architecture and paths → core L7 bottleneck →
> failure defense → L5/L6/L7 → probing chain.

---

## Problem 5: A distributed rate limiter

### 5.1 Scope, scale and SLAs

**Interpretation.** A platform service enforcing per-API-key, per-tenant and per-IP limits at the edge and at internal
gateways. For example: 1,000 req/s per key with bursts of 2,000, 10,000 req/s per tenant across all regions, and
abuse limits per IP.

| Quantity | Target |
|---|---|
| Decisions | 5M/s globally across 500 gateways |
| Keys | 100M active limit keys (API keys × routes, IPs) |
| Added latency | < 1 ms p99 (local decision); < 0.1 ms ideally |
| Accuracy | Within ±5% of the configured limit globally; never 2× over |
| Availability | **Fail open** for most limits (the limiter must not be the outage); fail closed for abuse/security limits |

**Capacity math.**
- A central counter at 5M decisions/s is a hot-key nightmare: 5M Redis ops/s on a few keys, plus 1 RTT per request.
- Local decisions with asynchronous aggregation: 500 gateways each sync deltas every 100 ms is 5,000 sync messages/s,
  each carrying many keys. That is cheap.
- State: 100M keys × ~32 B (GCRA needs one timestamp) = **3.2 GB**, partitionable by key.

### 5.2 Algorithms (measured, §A of the output: 100 req/s limit, bursts straddling each second boundary)

| Algorithm | Max admitted in any 1 s | Average admitted | State per key | Verdict |
|---|---|---|---|---|
| Fixed window | **198** (2× the limit at the boundary) | 103/s | counter + window | Cheap; wrong at boundaries |
| Sliding log | **100** (exact) | 100/s | one timestamp per admitted request | Exact, but memory ∝ rate |
| Sliding-window counter | 116 | 100/s | 2 counters | Good approximation, cheap (Cloudflare's approach) |
| **Token bucket / GCRA** (burst 100) | 161 (burst + refill, by design) | 102/s | **1 timestamp** | The industry default: explicit burst semantics, O(1) |

GCRA (the generic cell rate algorithm) stores a single *theoretical arrival time* (TAT). It allows a request iff
$\text{TAT} - t \le \tau - T$ and then sets $\text{TAT} = \max(\text{TAT}, t) + T$, where $T = 1/\text{rate}$ and τ is
the burst tolerance. It fits in one atomic Redis/KV operation.

### 5.3 Distributed enforcement (§B of the output: a global 10,000/s limit, 20 gateways, 4 of them get 3× traffic)

| Scheme | Offered 8,000/s (under the limit) | Offered 15,000/s (over) | Cost |
|---|---|---|---|
| Static split (limit/N per node) | **6,550/s admitted**: rejects 18% of legitimate traffic on busy gateways | 9,996 | None |
| Central counter (1 RTT per request) | 7,972 | **10,000 exactly** | RTT per request; a hot key; the counter is a hard dependency |
| **Async counts, sync every 100 ms** | 7,995 | 10,540 mean / 10,719 max (+5–7%) | Bounded overshoot ≈ rate × sync interval |

The L7 design is local decisions against globally synchronized budgets:
1. Each gateway enforces locally, using GCRA per key (in-process, ~100 ns).
2. Gateways ship per-key **deltas** to an aggregator every 100 ms. The aggregator is partitioned by key hash, and
   regional with cross-region gossip.
3. The aggregator returns the global consumption per key, and each gateway adjusts its local allowance.
4. **Overshoot is bounded by (number of gateways seeing the key) × (per-gateway rate) × (sync interval).** Shorten
   the interval or partition keys to gateways (consistent hashing at L4) for keys needing tighter accuracy.
5. **Precision tiers:**
   - "Abuse" and "security" limits fail closed, with stricter sync.
   - "Fairness" limits fail open: if the aggregator is unreachable, enforce the last-known allowance and log it.

### 5.4 Schema and partition key

```
limit config (control plane, versioned, LKG on gateways):
  rule_id → {match: (tenant|api_key|ip|route), rate, burst, scope: local|regional|global, fail_mode}
counter state (aggregator, partitioned by hash(limit_key)):
  limit_key = (rule_id, subject) → {tat_ns | window_counts, last_sync, region_counts{}}
```

### 5.5 Architecture and paths

```
 request ─► gateway: match rules (config LKG) → GCRA(key) in local memory → allow | 429 (+Retry-After)
                │ every 100 ms: batch deltas {key: count}
                ▼
        aggregator shard (by key hash) ─► merge, compute global usage → reply with allowances
                │ cross-region: gossip region totals every 1 s (global limits are approximate across regions)
 failure: aggregator down → gateways keep last allowance (fail-open rules) or local-only strict mode (fail-closed)
```

### 5.6 Core L7 bottleneck

The limiter sits on **every request**, so its availability and latency are the platform's. **It must never be the
cause of an outage.**
- Local decisions, so there is no dependency on the request path.
- Fail-open by default.
- Bounded inaccuracy instead of exactness.
- Rules distributed like config: staged, validated, LKG.

A rule that accidentally limits every tenant to 0 is a global outage, so rule changes need canaries and
"blast-radius previews" (how many requests would this rule have rejected yesterday?).

### 5.7 Failure defense

| Failure | Defense |
|---|---|
| Aggregator partition / outage | Local enforcement with last allowance; fail-open rules; alert |
| Hot key (one API key at 1M req/s) | Pin it to specific gateways via L4 hashing; local-only enforcement is then exact |
| Bad rule push | Staged rollout, dry-run "shadow mode" counting would-be rejections, kill switch |
| Retry storm from 429s | `Retry-After` headers, client SDK budgets; 429 is cheap to serve (no backend work) |
| Clock skew between gateways | GCRA uses local monotonic time; aggregation is count-based, not time-based |

### 5.8 L5 / L6 / L7 and probing chain

| | L5 | L6 | L7 |
|---|---|---|---|
| Algorithm | Token bucket in Redis | GCRA, sliding-window counter; boundary-burst analysis | Precision tiers, fail-open vs fail-closed per rule class |
| Distribution | Central Redis | Local + periodic sync; overshoot bound | Limiter must not be an outage source: local decisions, LKG rules, shadow mode, blast-radius previews |

1. **Probe:** "Use Redis INCR with expiry per key." **L5:** "Yes, simple and exact."
2. **Probe:** "Redis is in one region; you have 500 gateways in 30 regions." **L6:** "Regional Redis with local
   caching of decisions; sync periodically; accept a few % overshoot."
3. **Probe:** "Redis is down." **L7:**
   - "Gateways enforce from local state with the last allowance. Fairness limits fail open and abuse limits fail
     closed."
   - "The limiter's SLO is 'adds < 0.1 ms and never causes a 5xx'. Redis is an *optimization* for accuracy, not a
     dependency."

---

## Problem 6: A unique ID generator (Snowflake vs HLC vs ticket server)

### 6.1 Scope, scale and SLAs

| Quantity | Target |
|---|---|
| Throughput | 10M IDs/s globally, bursts of 100k/s per generator |
| Properties | Unique (always), roughly time-ordered (k-sortable), 64-bit if possible, no coordination per ID |
| Latency | < 1 µs per ID (in-process) |
| Availability | Must work during network partitions and control-plane outages |

### 6.2 The options

| Scheme | Bits | Ordering | Coordination | Failure mode |
|---|---|---|---|---|
| **Snowflake** (Twitter 2010): 41-bit ms timestamp \| 10-bit worker \| 12-bit sequence | 64 | k-sortable by time | Worker ID assignment only | **Clock regression → duplicates**; worker-ID collisions |
| Ticket server (Flickr): `REPLACE INTO tickets` auto-increment, two servers with odd/even offsets | 64 | Strictly increasing per server | 1 RTT per ID, or **block allocation** (grab 1,000 at a time) | Server outage; ordering gaps |
| **Block allocation** from a consensus store (etcd/DB): each node leases ranges of 10⁶ IDs | 64 | Increasing per block | 1 RTT per block | Unused IDs lost on crash (gaps, fine) |
| UUIDv4 | 128 | None | None | B-tree locality (Folder 02 file 01 §1.3) |
| **UUIDv7 / ULID**: 48-bit ms timestamp + 74/80 random bits | 128 | k-sortable | None | Clock regression only reorders, since the random bits keep uniqueness |
| HLC-based | 64 | Causally consistent | Piggybacks on messages | Needs a node ID for uniqueness |

**Snowflake capacity (§C of the output):**
- a lifetime of **69.7 years** from the custom epoch;
- **1,024 workers**;
- **4,096,000 IDs/s per worker**;
- 4.2 billion IDs/s fleet-wide.

The 12-bit sequence per ms is the per-worker ceiling. A generator that exhausts it must wait for the next millisecond.

### 6.3 The core L7 bottleneck: the two coordination points Snowflake hides

1. **Clock regression.** NTP steps the clock back 5 ms in the lab.
   - The naive generator produced **5,000 duplicate IDs**.
   - The regression-safe one (never go below the last timestamp; wait or reuse it with the sequence) produced
     **0 duplicates and strictly increasing IDs.**
   - Production generators also **refuse to start** if the clock is behind the last persisted timestamp, and alarm
     on regressions larger than a threshold.
2. **Worker-ID uniqueness.** Two processes with the same worker ID generate identical IDs. Worker IDs must be
   **leased from a consensus store** (ZooKeeper sequential node, etcd lease) with fencing semantics. A process whose
   lease expired must stop generating, or lease-plus-epoch bits go into the ID. In Kubernetes, the pod ordinal of a
   StatefulSet is a common but brittle choice.

### 6.4 Architecture

```
 app process ─► in-process generator (lock-free: atomic (ms, seq) packed in one 64-bit word; CAS loop)
                 worker_id ← leased from etcd/ZK at startup (TTL 30 s, renewed; fencing epoch)
                 last_ms persisted periodically → startup refuses if wall clock < last_ms
 no network call per ID; the control plane (lease store) down → existing leases continue until TTL, then
 generators must stop (or fall back to UUIDv7, which needs no coordination)
```

### 6.5 Failure defense and choice

| Need | Choose |
|---|---|
| 64-bit, k-sortable, high rate, DB primary keys | Snowflake with leased worker IDs and regression protection |
| No coordination at all, 128 bits acceptable | UUIDv7 (k-sortable) |
| Strictly increasing per entity (ledger sequence) | **Per-entity sequence from the entity's partition leader**, not a global generator (Folder 03 file 02 §6) |
| Short user-facing codes (URL shortener) | Block allocation + a bijective permutation (Feistel) for non-guessability (Folder 01 file 01 §7) |

Note: none of these IDs provides *causal* or *real-time* order across generators. Never use IDs as a causality
mechanism.

### 6.6 L5 / L6 / L7 and probing chain

| | L5 | L6 | L7 |
|---|---|---|---|
| Design | UUIDs or Snowflake | Snowflake bit layout, capacity, worker assignment | Clock-regression and worker-lease fencing; chooses per need (sortable, per-entity sequence, short codes); IDs never used as causality |

1. **Probe:** "Use Snowflake." **L5:** "Timestamp, worker, sequence."
2. **Probe:** "A VM is live-migrated and its clock jumps back 50 ms." **L6:** "Wait until the clock passes the last
   timestamp; alarm."
3. **Probe:** "And if the jump is 2 hours?" **L7:**
   - "Waiting 2 hours is an outage, so the generator refuses to serve and is drained."
   - "Callers fail over to other generators, or to UUIDv7 if the schema allows 128 bits."
   - "We'd also check the worker-ID lease: a migrated VM may be a *duplicate* if it was cloned. So epoch-fenced
     leases make the clone's IDs impossible."

---

## Problem 7: A distributed delayed-job scheduler

### 7.1 Scope, scale and SLAs

**Interpretation.** Schedule jobs to run at a future time (seconds to months): reminders, retries with delay, TTL
expiry, cron-like recurring tasks. At-least-once execution, with idempotent handlers.

| Quantity | Target |
|---|---|
| Scheduled jobs | 10B pending |
| Due rate | 1M jobs/s at peak, with spikes at round times (top of the hour) |
| Timing accuracy | Fire within 1 s of due time at p99 (1 min for long-horizon jobs) |
| Delivery | At-least-once; exactly-once *effects* via idempotency keys |

**Capacity math.**
- 10B jobs × 200 B = **2 TB** of pending state: a partitioned KV, not RAM.
- **"Top of the hour" spikes** (`0 * * * *` crons) can put 10% of a day's recurring jobs in one second. That needs
  jittering at schedule time, or smoothing: spread over 60 s unless strict.

### 7.2 Schema and partition key

```
jobs table (partitioned by hash(job_id) % P for storage):
  job_id → {due_ts, payload_ref, handler, attempt, state: SCHEDULED|LEASED|DONE|DEAD, lease_owner, lease_expiry}
due index (time-bucketed, so "what is due now" is a narrow range scan):
  (bucket = due_ts // 1 s, shard = hash(job_id) % S) → job_ids   ← S shards per second avoid a hot time bucket
```

**The partition key for the due index is (time bucket, shard).** A time-only key puts every due job of a given second
on one partition: the monotonic-key hotspot of Folder 02 file 03 §6.

### 7.3 Architecture and paths

```
 SCHEDULE: API → write job row + due-index entry (one txn or outbox) → ack
 NEAR-TERM TIER (due within ~1 h): pullers load upcoming buckets into an in-memory HIERARCHICAL TIMING WHEEL
   (per shard owner, lease-protected) → on tick, push due jobs to a work queue
 EXECUTION: workers lease jobs (visibility timeout = expected runtime × 3), run idempotent handler,
            mark DONE (CAS on attempt/lease); on timeout the lease expires → re-delivered (at-least-once)
 FAILURES: handler error → reschedule with backoff (attempt+1); after N → DEAD queue + alert
 FAR-FUTURE TIER: stays in the KV store; pullers scan buckets as they come within the horizon
```

### 7.4 The timing wheel (§D of the output)

Hierarchical timing wheels (Varghese & Lauck, SOSP 1987; Kafka's purgatory uses them) give **O(1) insert and O(1)
per-tick expiry**. Each level has 256 slots and covers 256× the span of the level below, and jobs cascade down as
time approaches.

In the lab, 50,000 jobs over 100,000 ticks all fired **on exactly the same tick as a reference heap (0
mismatches)**. A heap costs O(log n) per insert and pop; at 1M timers per node, the wheel's O(1) and cache
friendliness matter.

### 7.5 The core L7 bottleneck: correctness of "exactly once", and herds at round times

1. **"Exactly once" is impossible; exactly-once *effects* are not.**
   - A worker may finish the job and die before marking it DONE, so the job runs again.
   - Every handler gets an idempotency key = (job_id, scheduled_ts). Side-effect services dedupe on it (Folder 03
     file 03 §4).
   - The lease plus a CAS on completion prevents two workers from marking it done. A **fencing token** (lease epoch)
     prevents a paused worker's late completion from overwriting a newer attempt.
2. **Thundering herds at round times.**
   - Jitter recurring schedules by default, e.g. `0 * * * *` runs at a hash(job_id)-derived second within the
     minute.
   - Offer "strict" timing only as an explicit, quota-limited option.
   - Rate-limit dispatch per handler, so a million reminders don't DDoS the notification service. That is Problem
     14's admission problem.
3. **Shard ownership.** Each due-index shard is owned by one puller via a lease. A puller failure transfers ownership
   in seconds, and a fresh owner rescans the last few buckets, covered by idempotency.

### 7.6 Failure defense

| Failure | Defense |
|---|---|
| Puller dies | Lease expiry → new owner rescans the last N buckets (idempotent duplicates OK) |
| Worker dies mid-job | Visibility timeout → re-delivery; idempotent handlers |
| Backlog after an outage | Catch-up with rate limits and priorities (old reminders may be skipped by policy); avoid releasing an hour of jobs in one second |
| Clock skew | Due time compared on the puller's clock; tolerance windows; jobs carry absolute UTC due times |
| Poison job | Attempt counter → DEAD queue after N; per-handler circuit breaker |

### 7.7 L5 / L6 / L7 and probing chain

| | L5 | L6 | L7 |
|---|---|---|---|
| Design | Cron + DB polling | Time-bucketed index, leases, visibility timeouts, at-least-once | Sharded time buckets (no hotspot), timing wheels, fencing on completion, jittered schedules, dispatch rate limits, catch-up policy |

1. **Probe:** "Poll `SELECT * FROM jobs WHERE due < now()` every second." **L5:** "With an index on due."
2. **Probe:** "10B rows, 1M due/s." **L6:** "Time-bucketed partitions, sharded per second, pullers per shard with
   leases."
3. **Probe:** "The scheduler was down for an hour; what happens at recovery?" **L7:**
   - "3.6B jobs are now due. Releasing them at once would DDoS every downstream."
   - "Catch-up runs at a configured multiple of normal dispatch rate, prioritized by job class."
   - "Each job carries a staleness policy (skip reminders older than X, always run billing)."
   - "Downstream admission control protects the rest: the metastability lesson of Folder 05 applied to schedulers."

---

## Problem 8: A distributed log / message broker (Kafka-class)

### 8.1 Scope, scale and SLAs

| Quantity | Target |
|---|---|
| Ingest | 10 GB/s (≈ 10M msgs/s at 1 KB) per cluster; multiple clusters |
| Retention | 7 days hot; 90 days in tiered storage |
| Latency | p99 produce-ack < 20 ms (acks=all, in-region); end-to-end < 100 ms |
| Ordering | Per partition |
| Durability | No acknowledged message lost on any single-AZ failure |
| Consumers | Fan-out to 10+ consumer groups |

**Capacity math.**
- 10 GB/s × RF 3 = 30 GB/s of disk writes, plus 20 GB/s of replication network traffic.
- 7 days hot = 10 GB/s × 604,800 s ≈ **6 PB × RF 3 = 18 PB**. That is why **tiered storage** moves closed segments
  to object storage: brokers keep hours locally, and the rest is S3-class at ~1/10 the $/GB.
- **The cross-AZ bill** at 10 GB/s with RF 3 is ~$1.75M/month on AWS list prices (Folder 01 file 02 §7.4: $175k per
  GiB/s). This is the dominant TCO line, and it motivates fetch-from-follower and diskless designs.

### 8.2 Schema and partitioning

```
topic → P partitions; partition = ordered, append-only log of segments (e.g. 1 GB files + sparse offset index +
        time index); message = (offset, key, value, headers, timestamp, producer_id, epoch, sequence)
partition key = hash(message key) % P   (per-key ordering) ; P sized for the 3-year peak (Folder 02 file 03 Chain C)
replication: leader + followers in ISR; high watermark = min offset replicated to all ISR members
consumer groups: partition → one consumer; committed offsets in an internal compacted topic
metadata: KRaft quorum (Raft) for topics, partitions, leaders, ISRs, configs   (control plane)
```

### 8.3 Architecture and paths

```
 PRODUCE: client batches (linger, batch.size, compression zstd/lz4) → partition leader → append to page cache
          → followers fetch → when all ISR have it, HW advances → ack (acks=all, min.insync.replicas=2)
          idempotent producer: (producer_id, epoch, sequence) dedupes retries; transactions: atomic multi-partition
 CONSUME: consumer fetches from leader (or nearest follower: KIP-392) from committed offset; zero-copy sendfile
 TIERED:  closed segments → object storage; local retention hours; old fetches served from the remote tier
 CONTROL: KRaft controller quorum elects partition leaders; brokers fence by leader epoch
 RECOVERY: broker dies → controller elects new leaders from ISR (seconds); replacement re-replicates (throttled)
```

### 8.4 The core L7 bottleneck: the cost and the tail, not the throughput

Throughput is solved by partitioning, batching and zero-copy. The L7 problems:

1. **Cross-AZ replication cost** (§8.1). The levers:
   - rack-aware fetch-from-follower for consumers;
   - producer AZ affinity, where possible;
   - **diskless/S3-direct topics** for high-volume, latency-tolerant streams (Folder 01 file 02 §7.4: a 31× bill
     reduction, at p99 latency in the hundreds of ms).

   Per-topic tiering by latency SLO is the L7 answer.
2. **Tail latency of acks=all** is the max of the follower fetch latencies. A slow follower stalls the high watermark
   until it is dropped from the ISR (`replica.lag.time.max.ms`), and dropping and re-adding flaps. Defenses:
   - PLP NVMe;
   - avoiding GC pauses: brokers are page-cache heavy, not heap heavy;
   - leader balancing;
   - quotas so one client can't saturate a broker's NIC.
3. **Rebalancing pain.** Moving partitions copies data, so throttle it. KIP-848's new consumer rebalance protocol
   reduces stop-the-world consumer rebalances (⚠ verify the version availability). For consumers, cooperative
   rebalancing and static membership avoid churn during deploys.
4. **Exactly-once semantics, precisely.**
   - Idempotent producers dedupe broker-side retries.
   - Transactions make consume-transform-produce atomic *within Kafka*.
   - **End-to-end effects in external systems still need idempotent sinks** (Folder 08 problem 29).

### 8.5 Failure defense

| Failure | Defense |
|---|---|
| Broker loss | Leaders re-elected from ISR in seconds; RF=3 across AZs; `min.insync.replicas=2` |
| AZ loss | One replica per AZ; acks=all still satisfiable with 2 AZs; pre-provisioned capacity |
| Unclean election temptation | `unclean.leader.election.enable=false`: trade availability for not losing acked data |
| Controller quorum issues | KRaft with 3–5 controllers across AZs; brokers keep serving existing leaders while the controller is unavailable (static stability for the data path) |
| Consumer lag explosion | Lag SLI; autoscale consumers up to partition count; backpressure to producers via quotas |
| Hot partition (skewed key) | Key salting for non-order-sensitive keys; partition count planning; per-client quotas |
| Poison message | Consumer-side DLQ after N attempts; schema validation at produce time (schema registry) |

### 8.6 L5 / L6 / L7 and probing chain

| | L5 | L6 | L7 |
|---|---|---|---|
| Design | Topics, partitions, consumer groups | ISR, acks/min.insync, idempotent producers, transactions, tiered storage | Cross-AZ TCO as the dominant line; diskless tiers per SLO; tail of acks=all; partition-count planning; EOS boundaries |
| Ops | — | Rebalancing, quotas | KRaft static stability, leader balancing, flapping ISRs, lag as an SLI, KIP-848 |

1. **Probe:** "Why is our Kafka bill $2M/month?" **L5:** "Too many brokers."
2. **Probe:** "Brokers are 20% of it." **L6:** "Cross-AZ replication and consumer traffic; enable rack-aware
   consumers."
3. **Probe:** "Still $1.4M. Next?" **L7:**
   - "Replication is now the line: 2 cross-AZ copies per byte."
   - Classify topics by latency need. The 80% of bytes that are analytics/log streams with second-level SLOs move to
     diskless (S3-backed) topics: replication traffic goes to zero, S3 provides multi-AZ durability, and PUT costs
     are amortized with large batches.
   - "Order-of-magnitude saving on those topics; latency-critical topics stay on replicated disks."

---

## 9. The listing

```python
"""limiter_idgen_lab.py - rate limiters, distributed limiting, Snowflake IDs, and timing wheels (Folder 06, file 02).

  A. Single-key limiters at 100 req/s against boundary bursts: fixed window, sliding log, sliding-window counter,
     token bucket / GCRA. Max admitted in ANY 1-second interval, and memory per key.
  B. A 10,000 req/s global limit enforced by 20 gateways under skewed traffic: static split vs central counter vs
     local buckets with periodic global sync.
  C. Snowflake IDs: capacity math, and a clock that steps back 5 ms: naive generator vs regression-safe generator.
  D. A hierarchical timing wheel (the delayed-job / Kafka purgatory structure) checked against a heap.
Standard library only; seeded, deterministic.
"""
import bisect
import collections
import heapq
import random


# ---------------------------------------------------------------- A. single-key limiters
class FixedWindow:
    def __init__(self, limit: int, window: float = 1.0):
        self.limit, self.window, self.cur, self.count = limit, window, -1, 0

    def allow(self, t: float) -> bool:
        w = int(t // self.window)
        if w != self.cur:
            self.cur, self.count = w, 0
        if self.count < self.limit:
            self.count += 1
            return True
        return False


class SlidingLog:
    def __init__(self, limit: int, window: float = 1.0):
        self.limit, self.window, self.log = limit, window, collections.deque()

    def allow(self, t: float) -> bool:
        while self.log and self.log[0] <= t - self.window:
            self.log.popleft()
        if len(self.log) < self.limit:
            self.log.append(t)
            return True
        return False


class SlidingCounter:
    """Two counters; estimate = prev * (overlap fraction) + current (Cloudflare-style approximation)."""
    def __init__(self, limit: int, window: float = 1.0):
        self.limit, self.window, self.cur, self.cnt, self.prev = limit, window, 0, 0, 0

    def allow(self, t: float) -> bool:
        w = int(t // self.window)
        if w != self.cur:
            self.prev = self.cnt if w == self.cur + 1 else 0
            self.cur, self.cnt = w, 0
        frac = 1 - (t / self.window - w)
        if self.prev * frac + self.cnt < self.limit:
            self.cnt += 1
            return True
        return False


class GCRA:
    """Generic cell rate algorithm = token bucket with one timestamp: theoretical arrival time (TAT)."""
    def __init__(self, rate: float, burst: int):
        self.T, self.tau, self.tat = 1 / rate, burst / rate, 0.0

    def allow(self, t: float) -> bool:
        tat = max(self.tat, t)
        if tat - t <= self.tau - self.T:
            self.tat = tat + self.T
            return True
        return False


def max_in_any_window(times: list, window: float = 1.0) -> int:
    best, j = 0, 0
    for i, t in enumerate(times):
        while times[j] <= t - window:
            j += 1
        best = max(best, i - j + 1)
    return best


def limiter_accuracy(rng: random.Random) -> dict:
    reqs = []
    for s in range(30):                                     # bursts straddling every second boundary + noise
        reqs += [s + 0.99 + rng.uniform(0, 0.009) for _ in range(150)]
        reqs += [s + 1.0 + rng.uniform(0, 0.009) for _ in range(150)]
        reqs += [s + rng.uniform(0, 1) for _ in range(50)]
    reqs.sort()
    out = {}
    for name, lim, mem in (("fixed window", FixedWindow(100), "1 counter + window id"),
                           ("sliding log", SlidingLog(100), "1 timestamp per admitted request"),
                           ("sliding-window counter", SlidingCounter(100), "2 counters"),
                           ("token bucket / GCRA (burst 100)", GCRA(100, 100), "1 timestamp")):
        admitted = [t for t in reqs if lim.allow(t)]
        out[name] = (max_in_any_window(admitted), len(admitted) / 30, mem)
    return out


# ---------------------------------------------------------------- B. distributed limiting
def distributed(mode: str, offered: float, rng: random.Random, nodes: int = 20, limit: int = 10_000,
                seconds: int = 10, sync_ms: int = 100) -> dict:
    """Per-request simulation. 4 of 20 gateways receive 3x the traffic of the others.
      static split: each node enforces limit/N locally (no coordination).
      central:      every request increments one global counter (exact; costs an RTT and a hot key).
      async sync:   each node admits if (global count as of the last sync + its own unsynced count) < limit;
                    counts are exchanged every sync_ms -> over-admission bounded by what others admit unseen."""
    weights = [3.0 if i < 4 else 1.0 for i in range(nodes)]
    events = []
    for i, w in enumerate(weights):
        t, r = 0.0, offered * w / sum(weights)
        while True:
            t += rng.expovariate(r)
            if t >= seconds:
                break
            events.append((t, i))
    events.sort()
    per_sec = [0] * seconds
    local = [0] * nodes                                   # admitted this window by each node
    unsynced = [0] * nodes
    global_known, window, next_sync = 0, 0, sync_ms / 1000
    for t, i in events:
        w = int(t)
        if w != window:
            window, local, unsynced, global_known = w, [0] * nodes, [0] * nodes, 0
            next_sync = w + sync_ms / 1000
        while t >= next_sync:                              # periodic exchange of counts
            global_known += sum(unsynced)
            unsynced = [0] * nodes
            next_sync += sync_ms / 1000
        if mode.startswith("static"):
            ok = local[i] < limit / nodes
        elif mode.startswith("central"):
            ok = sum(local) < limit
        else:
            ok = global_known + unsynced[i] < limit
        if ok:
            local[i] += 1
            unsynced[i] += 1
            per_sec[w] += 1
    return {"mean_admitted": sum(per_sec) / seconds, "max_admitted": max(per_sec)}


# ---------------------------------------------------------------- C. Snowflake
class Snowflake:
    EPOCH = 1_288_834_974_657                                 # Twitter's epoch (ms)

    def __init__(self, worker: int, safe: bool):
        self.worker, self.safe, self.last_ms, self.seq = worker, safe, -1, 0
        self.waits = 0

    def next_id(self, now_ms: int) -> int:
        if self.safe and now_ms < self.last_ms:
            self.waits += self.last_ms - now_ms                     # wait out (or reuse last_ms) instead of going back
            now_ms = self.last_ms
        if now_ms == self.last_ms:
            self.seq = (self.seq + 1) & 0xFFF
            if self.seq == 0:
                now_ms += 1                                         # sequence exhausted: next millisecond
        else:
            self.seq = 0
        self.last_ms = now_ms
        return ((now_ms - self.EPOCH) << 22) | (self.worker << 12) | self.seq


def snowflake_demo() -> dict:
    res = {}
    for safe in (False, True):
        g = Snowflake(7, safe)
        ids = []
        clock = 1_761_500_000_000
        for i in range(20_000):
            if i == 10_000:
                clock -= 5                                          # NTP steps the clock back 5 ms
            if i % 1000 == 999:
                clock += 1
            ids.append(g.next_id(clock))
        res[safe] = {"duplicates": len(ids) - len(set(ids)), "monotonic": all(a < b for a, b in zip(ids, ids[1:]))}
    return res


# ---------------------------------------------------------------- D. timing wheel
class TimingWheel:
    """Hierarchical wheel: level 0 has 256 slots of 1 tick, level 1 256 slots of 256 ticks, level 2 ... Insert O(1);
    on each tick, expire level-0 slot; when level 0 wraps, cascade the next level-1 slot down."""
    def __init__(self, levels: int = 3, slots: int = 256):
        self.levels, self.slots, self.now = levels, slots, 0
        self.wheels = [[[] for _ in range(slots)] for _ in range(levels)]

    def add(self, fire_at: int, job) -> None:
        delta = fire_at - self.now
        for lvl in range(self.levels):
            span = self.slots ** (lvl + 1)
            if delta < span or lvl == self.levels - 1:
                slot = (fire_at // self.slots ** lvl) % self.slots
                self.wheels[lvl][slot].append((fire_at, job))
                return

    def tick(self) -> list:
        self.now += 1
        for lvl in range(1, self.levels):                       # cascade when lower levels wrap
            if self.now % self.slots ** lvl == 0:
                slot = (self.now // self.slots ** lvl) % self.slots
                items, self.wheels[lvl][slot] = self.wheels[lvl][slot], []
                for fire_at, job in items:
                    self.add(fire_at, job)
        slot = self.now % self.slots
        due = [j for j in self.wheels[0][slot] if j[0] == self.now]
        self.wheels[0][slot] = [j for j in self.wheels[0][slot] if j[0] != self.now]
        return due


def wheel_vs_heap(jobs: int, horizon: int, rng: random.Random) -> dict:
    tw, heap = TimingWheel(), []
    for i in range(jobs):
        at = rng.randint(1, horizon)
        tw.add(at, i)
        heapq.heappush(heap, (at, i))
    mismatches = fired = 0
    for _ in range(horizon):
        due = sorted(j for _, j in tw.tick())
        expect = []
        while heap and heap[0][0] <= tw.now:
            expect.append(heapq.heappop(heap)[1])
        mismatches += due != sorted(expect)
        fired += len(due)
    return {"fired": fired, "mismatched_ticks": mismatches}


def main() -> None:
    rng = random.Random(6)
    print("== A. 100 req/s limit; 30 s of bursts straddling each second boundary (350 req per second offered)")
    print(f"{'algorithm':<34} {'max in any 1 s':>15} {'admitted/s':>11}   state per key")
    acc = limiter_accuracy(rng)
    for name, (mx, per_s, mem) in acc.items():
        print(f"{name:<34} {mx:>15} {per_s:>11.1f}   {mem}")

    print("\n== B. global limit 10,000/s over 20 gateways (4 get 3x traffic); admitted requests per second")
    di = {}
    for offered in (8_000, 15_000):
        for mode in ("static split (limit/N per node)", "central counter (1 RTT per request)",
                     "async counts, global sync every 100 ms"):
            di[(offered, mode)] = r = distributed(mode, offered, rng)
            print(f"  offered {offered:>6}/s  {mode:<40} mean {r['mean_admitted']:>7.0f}/s   "
                  f"max {r['max_admitted']:>7.0f}/s")

    print("\n== C. Snowflake: 41-bit ms timestamp | 10-bit worker | 12-bit sequence")
    print(f"  lifetime {2 ** 41 / 1000 / 86400 / 365.25:.1f} years; {2 ** 10} workers; {2 ** 12 * 1000:,} IDs/s per "
          f"worker; {2 ** 22 * 1000 / 1e9:.1f} B IDs/s fleet-wide")
    sf = snowflake_demo()
    for safe, r in sf.items():
        print(f"  {'regression-safe' if safe else 'naive':<16} clock steps back 5 ms: duplicates {r['duplicates']}, "
              f"strictly increasing {r['monotonic']}")

    print("\n== D. hierarchical timing wheel (3 x 256 slots) vs heap: 50,000 jobs over 100,000 ticks")
    wh = wheel_vs_heap(50_000, 100_000, rng)
    print(f"  jobs fired {wh['fired']}, ticks where wheel and heap disagreed: {wh['mismatched_ticks']}")

    assert acc["fixed window"][0] >= 190 and acc["sliding log"][0] == 100
    assert acc["token bucket / GCRA (burst 100)"][0] <= 200 and acc["sliding-window counter"][0] <= 150
    assert di[(8_000, "static split (limit/N per node)")]["mean_admitted"] < 7_000     # rejects under the limit
    assert abs(di[(8_000, "central counter (1 RTT per request)")]["mean_admitted"] - 8_000) < 300
    assert di[(15_000, "central counter (1 RTT per request)")]["max_admitted"] == 10_000
    assert 10_000 <= di[(15_000, "async counts, global sync every 100 ms")]["max_admitted"] < 11_600
    assert sf[False]["duplicates"] > 0 and sf[True]["duplicates"] == 0 and sf[True]["monotonic"]
    assert wh["fired"] == 50_000 and wh["mismatched_ticks"] == 0
    print("\nself-test: all assertions passed")


if __name__ == "__main__":
    main()
```

Output (verified; deterministic):

```text
== A. 100 req/s limit; 30 s of bursts straddling each second boundary (350 req per second offered)
algorithm                           max in any 1 s  admitted/s   state per key
fixed window                                   198       103.3   1 counter + window id
sliding log                                    100       100.1   1 timestamp per admitted request
sliding-window counter                         116       100.0   2 counters
token bucket / GCRA (burst 100)                161       101.7   1 timestamp

== B. global limit 10,000/s over 20 gateways (4 get 3x traffic); admitted requests per second
  offered   8000/s  static split (limit/N per node)          mean    6550/s   max    6709/s
  offered   8000/s  central counter (1 RTT per request)      mean    7972/s   max    8075/s
  offered   8000/s  async counts, global sync every 100 ms   mean    7995/s   max    8091/s
  offered  15000/s  static split (limit/N per node)          mean    9996/s   max   10000/s
  offered  15000/s  central counter (1 RTT per request)      mean   10000/s   max   10000/s
  offered  15000/s  async counts, global sync every 100 ms   mean   10540/s   max   10719/s

== C. Snowflake: 41-bit ms timestamp | 10-bit worker | 12-bit sequence
  lifetime 69.7 years; 1024 workers; 4,096,000 IDs/s per worker; 4.2 B IDs/s fleet-wide
  naive            clock steps back 5 ms: duplicates 5000, strictly increasing False
  regression-safe  clock steps back 5 ms: duplicates 0, strictly increasing True

== D. hierarchical timing wheel (3 x 256 slots) vs heap: 50,000 jobs over 100,000 ticks
  jobs fired 50000, ticks where wheel and heap disagreed: 0

self-test: all assertions passed
```

---

## 10. References for problems 5–8

- Cloudflare Blog. *How we built rate limiting capable of scaling to millions of domains*, 2017 (sliding-window
  counter). Stripe Engineering, *Scaling your API with rate limiters*, 2017.
- J. Turner. *New directions in communications (or which way to the information age?)*, 1986 (leaky bucket). The
  GCRA (ITU-T I.371).
- Twitter Engineering. *Announcing Snowflake*, 2010. Flickr Engineering, *Ticket Servers: Distributed Unique Primary
  Keys on the Cheap*, 2010. RFC 9562 (UUIDv7).
- G. Varghese, A. Lauck. *Hashed and Hierarchical Timing Wheels.* SOSP 1987. Confluent Blog, *Apache Kafka, Purgatory,
  and Hierarchical Timing Wheels*, 2015.
- J. Kreps, N. Narkhede, J. Rao. *Kafka: a Distributed Messaging System for Log Processing.* NetDB 2011. Kafka KIPs
  98 (exactly-once), 392 (fetch from follower), 405 (tiered storage), 500 (KRaft), 848 (consumer rebalance), 1150
  (diskless topics).
