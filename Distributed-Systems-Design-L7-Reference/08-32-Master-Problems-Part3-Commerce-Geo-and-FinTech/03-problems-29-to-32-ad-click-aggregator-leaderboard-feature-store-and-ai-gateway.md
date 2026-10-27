# Problems 29–32: Ad-Click Aggregator, Gaming Leaderboard, Real-Time Feature Store, Multi-Tenant LLM & Agentic Gateway

> **Folder 08 · File 03** of the Distributed Systems & System Design L7 Reference.
> **Listing:** `streams_ml_gateway_lab.py` covers:
> - click aggregation with duplicates, lateness and fraud;
> - a rank-capable skip list verified against brute force;
> - feature-store point-in-time leakage measured by F1 offline vs in production;
> - LLM gateway token-based limits and prefix-aware routing.
>
> The output is deterministic.

---

## Problem 29: A real-time ad-click aggregator (exactly-once attribution, fraud filtering)

### 29.1 Scope, scale and SLAs

| Quantity | Target |
|---|---|
| Click events | 1M/s peak (impressions 100× more) |
| Aggregates | Per (ad, campaign, minute): clicks, spend, conversions; budget pacing needs ~seconds freshness |
| Correctness | **Billing-grade**: no double counting, no lost clicks; reconcilable with raw logs |
| Fraud | Bots and click farms filtered before billing |
| Latency | Dashboards < 1 min stale; budget pacing < 10 s |

### 29.2 Where counts go wrong (§A of the output: 300k clicks over an hour, 500 ads, 2% duplicates, 1% arriving 3–10 min late, plus a 9,000-click bot)

| Aggregation | Total absolute error vs truth (300,000 legit clicks) |
|---|---|
| Processing-time windows, no dedupe, no fraud filter | **36,021** |
| Event-time windows + dedupe by click_id + 2-min watermark + fraud rule | **2,885**: exactly the late events dropped past the watermark; the bot's 9,000 clicks all filtered |
| **+ late updates** (allowed lateness: re-emit corrected window results / upserts) | **0** |

Three distinct errors, three mechanisms:
1. **Duplicates** from at-least-once delivery (producer retries, consumer replays). The fix is **dedupe by a stable
   click_id** within a bounded window (state TTL ≥ max redelivery delay), or idempotent upserts keyed by click_id.
2. **Processing-time windowing** attributes clicks to the wrong minute whenever delivery is delayed. Billing must use
   **event time**.
3. **Late data** beyond the watermark is either dropped (an error) or handled as a **late update**: the window result
   is re-emitted and the sink upserts. The companion Dataflow/Beam/Flink KB covers watermarks and triggers in depth.

### 29.3 Schema and partition key

```
raw click log (immutable, the source of truth for billing audits):  object storage, partitioned by hour
stream: topic partitioned by hash(ad_id) (or campaign_id) → per-key ordered processing
state:  dedupe store: click_id → seen (RocksDB state, TTL 24 h) ; window state: (ad_id, minute) → counts
sink:   OLAP (ClickHouse/Druid/Pinot) table keyed (ad_id, minute) with UPSERT/replacing-merge semantics
        budget service: campaign_id → spend (pacing; strongly consistent counter with escrow per region)
```

### 29.4 Architecture and paths

```
 click → edge (signature on the click URL: ad_id, ts, nonce; reject unsigned/tampered) → log + stream
   → stream processor (event time, watermarks, dedupe, fraud features: IP/device rates, known-bot lists, ML score)
       ├─ billing aggregates (exactly-once: transactional sink or idempotent upserts keyed by (ad, minute, version))
       ├─ pacing signals (seconds) → budget service (stop serving ads when budget exhausted; tolerate small overshoot)
       └─ fraud side outputs → review / clawback
 batch (hourly/daily): recompute from the raw log (the "kappa/lambda" reconciliation) → compare with streaming
       aggregates → corrections → invoices from the reconciled numbers
```

### 29.5 The core L7 bottleneck: exactly-once *effects* end to end, and reconciliation

- **Exactly-once inside the processor** (checkpointed state + transactional or idempotent sinks) is necessary but not
  sufficient. The edge, the log and the sink must each be idempotent, and the **daily batch recomputation from raw
  logs** is the audit that proves it.
- **Fraud filtering changes counts after the fact.** Invoices use post-fraud reconciled aggregates. Real-time
  dashboards show "preliminary" numbers.
- **Budget pacing** is a distributed counter with a hard-ish limit across regions. Use escrow: allocate budget slices
  to regions and refill. That bounds overshoot, as in the distributed rate limiter of problem 5.

### 29.6 Failure defense, L5/L6/L7, probing chain

| Failure | Defense |
|---|---|
| Processor crash | Checkpoint restore; replay from committed offsets; idempotent sinks |
| Duplicate floods (client retries) | click_id dedupe; signed click URLs with nonces |
| Late data | Allowed lateness + upserts; side output beyond it; batch reconciliation |
| Bot attack | Rate features per IP/device/ASN, ML scoring, post-hoc clawback |
| Hot ad (viral) | Pre-aggregate per partition and combine; salted keys for counts |

| | L5 | L6 | L7 |
|---|---|---|---|
| Design | Kafka → consumer → counter DB | Event time, watermarks, dedupe, exactly-once sinks | Error decomposition (36k → 2.9k → 0); raw-log batch reconciliation as the billing truth; fraud as post-hoc correction; escrowed budgets |

1. **Probe:** "Count clicks per ad per minute from Kafka." **L5:** "Consumer increments counters."
2. **Probe:** "Advertisers dispute their bills." **L6:** "Dedupe on click_id, event-time windows, exactly-once
   sinks."
3. **Probe:** "How do you *prove* the numbers?" **L7:**
   - "Keep the immutable raw log, and recompute billing aggregates daily in batch from it, including fraud
     decisions. Compare with the streaming results and invoice from the reconciled ones."
   - "The streaming path is for pacing and dashboards; the batch path is the audit trail. Both are idempotent and keyed
     by click_id, so the comparison is exact."

---

## Problem 30: A real-time gaming leaderboard (Redis sorted sets, sharded rank aggregation)

### 30.1 Scope, scale and SLAs

| Quantity | Target |
|---|---|
| Players | 100M per global leaderboard (seasonal), plus millions of small ones (friends, regions, guilds) |
| Score updates | 500k/s peak |
| Queries | "My rank", top-100, "players around me" (±10): 1M QPS |
| Latency | p99 < 20 ms |
| Freshness | Seconds |

### 30.2 The data structure (§B of the output)

A **skip list with span counts** (Redis ZSET: a skip list + hash map) answers rank(player) in O(log n): the sum of
the spans walked. In the lab, with 50k players and 100k updates:
- **0/5,000 wrong ranks** checked against a sorted array;
- **21.5 pointer steps per rank query** (log₂ n = 15.6).

Top-K is O(log n + K), and "around me" is rank, then a range.

### 30.3 The core L7 bottleneck: one sorted set doesn't scale to 100M × 500k updates/s

A single Redis ZSET handles ~100k–1M ops/s on one thread, and its memory is ~100 B per entry: 100M → ~10 GB, which
fits. But **update throughput and single-node failure** are the limits. The options:

| Design | Rank query | Updates | Accuracy |
|---|---|---|---|
| Single ZSET (+ replicas for reads) | O(log n), exact | ≤ one node's write rate | Exact |
| **Score-range sharding** (shard k holds scores in [b_k, b_{k+1})) | rank = Σ counts of higher shards + local rank: needs per-shard counts | Moves players between shards as scores cross boundaries | Exact; boundary maintenance |
| **Hash sharding + score histogram** | rank ≈ Σ over shards of count(score > s), via per-shard histograms (bucketed scores) | Fully parallel | **Approximate** for the long tail; exact top-K via a merged heap of per-shard top-K |
| Batch rank computation | Precomputed hourly | Any | Stale |

The L7 answer is **tiered exactness**, which is what the product actually needs:
- **Top-1,000 is exact and fresh.** Each shard maintains its local top-K, a coordinator merges them, cached for 1 s.
- **"My rank" for the long tail is approximate.** A histogram gives the percentile: "top 3%" or "rank ~2.4M". Players
  can't tell 2,413,557 from 2,413,612, and the data would be stale by the time they read it anyway.
- **Friends/guild leaderboards are small**, so they are exact ZSETs per group, computed on read from friends' scores.

### 30.4 Schema and architecture

```
scores (durable): (season, player_id) → {score, updated_at}   partition hash(player_id) — source of truth (KV)
global leaderboard: N hash shards, each: ZSET + score histogram (e.g. 10,000 buckets) + local top-K
coordinator: merges per-shard top-K every 1 s (cached); answers percentile via Σ histograms
updates: game servers → score service (validate, anti-cheat, idempotent by match_id) → KV + shard ZSET (async, ordered
         per player); season end: snapshot + freeze
```

### 30.5 Failure defense, L5/L6/L7, probing chain

| Failure | Defense |
|---|---|
| Shard node loss | Rebuild the ZSET from the durable score store (or replica); leaderboard is derived state |
| Cheaters | Server-authoritative scores, anomaly detection, retroactive removal (recompute) |
| Season-end spike | Pre-scale; freeze writes at the deadline with a sequence cutoff |
| Hot player (streamer) | Read their rank from cache; updates remain O(log n) |

| | L5 | L6 | L7 |
|---|---|---|---|
| Design | Redis ZSET | Skip-list internals; replicas; sharding concerns | Tiered exactness (exact top-K, approximate tail via histograms, exact small groups); leaderboards as derived state |

1. **Probe:** "Use a Redis sorted set." **L5:** "ZADD and ZREVRANK."
2. **Probe:** "100M players, 500k updates/s." **L6:** "Shard by score range or hash; merge top-K."
3. **Probe:** "Exact rank for every player?" **L7:**
   - "Exact top-K (merged per-shard heaps) and approximate tail ranks via summed histograms."
   - "Exact global rank for player #48M costs cross-shard coordination on every query, for a number that changes
     every second and that no one can verify."
   - "We'd show percentiles in the long tail and invest exactness where players compete: the top 1,000 and their
     friends."

---

## Problem 31: A real-time ML feature store (online KV + offline lakehouse, point-in-time correctness)

### 31.1 Scope, scale and SLAs

| Quantity | Target |
|---|---|
| Online reads | 1M feature-vector reads/s (fraud, ranking, ETA models); **p99 < 10 ms** |
| Features | 10k features across 500 entities types; freshness from seconds (streaming) to daily (batch) |
| Offline | Training sets over years of history, billions of rows, **point-in-time correct** |
| Consistency | **Training–serving skew** minimized: the same definitions online and offline |

### 31.2 The core L7 bottleneck: point-in-time correctness (§C of the output)

The scenario is a churn model using "days since last login", 20,000 users, 18.6% churners:

| Training features joined as… | Offline F1 | **Production F1** (served point-in-time) |
|---|---|---|
| **Latest values** (computed at training time: leaks the future) | **0.913** | **0.061** |
| **Point-in-time (as-of) values** | 0.395 | **0.395** |

Joining each training example with the feature value **as of the label's event time** is the whole job of the
offline store. The naive join (the "current" value) leaks the outcome: a churned user has a large "days since last
login" *because* they churned.
- The leaky model looks excellent offline (F1 0.91) and **collapses in production** (0.06) to worse than useless.
- The point-in-time model is honest: offline = online.

**Leakage is the most expensive silent bug in ML systems.** Nothing errors, and the metrics look great.

The mechanism is an **as-of join** (temporal join):

```
for each training row (entity, event_ts, label):
    feature = latest feature row with feature_ts ≤ event_ts − (feature availability lag)
```

Spark/Flink "AS OF" joins and Feast's `get_historical_features` implement this. The **availability lag** matters: a
feature computed by a daily batch at 02:00 wasn't available for a 01:00 prediction, even if its timestamp says
00:00.

### 31.3 Schema and architecture

```
feature definitions (code, versioned): source → transformation → entity key → freshness SLA → owner
offline store (lakehouse: Iceberg/Delta/Hudi tables): (entity_id, feature_ts) → values ; append-only, time-travel
online store (KV: Redis/Cassandra/DynamoDB/Bigtable): (entity_id) → latest values (+ feature_ts) ; TTL per feature
materialization: batch (daily backfills → online) + streaming (Kafka → Flink → online + offline log)
serving: model service → feature server (batched multi-get, p99 < 10 ms, hedged reads, local cache for hot entities)
         → LOG the served feature vector with the prediction (the training set for the next model = no skew)
```

### 31.4 Failure defense, L5/L6/L7, probing chain

| Failure | Defense |
|---|---|
| Training–serving skew | Single feature definition for both paths; **log served features** and train on them |
| Leakage | As-of joins with availability lag; leakage tests (features shouldn't predict labels "too well"; temporal holdouts) |
| Online store slow | Hedged reads; defaults for missing features with model awareness; per-feature freshness SLIs |
| Stale streaming features | Freshness monitors; fall back to batch values with a staleness flag |
| Backfill overload | Throttled bulk loads into the online store; separate write capacity |

| | L5 | L6 | L7 |
|---|---|---|---|
| Design | Compute features in the model service | Online KV + offline warehouse, batch + streaming materialization | Point-in-time as-of joins with availability lag (F1 0.91 → 0.06 leak demo); logging served features; skew/leakage as tested invariants |

1. **Probe:** "Join the current feature table to the labels to build training data." **L5:** "Simple SQL join."
2. **Probe:** "The model is great offline and terrible online." **L6:** "Training–serving skew or leakage: use
   point-in-time joins."
3. **Probe:** "We use as-of joins and still see skew." **L7:**
   - "Check availability lag. A feature stamped 00:00 but materialized at 02:00 wasn't servable for 01:00
     predictions, so join on materialization time."
   - "Better: log the exact feature vectors served at prediction time and train on those logs. That is skew-free by
     construction."
   - "Then add a monitor comparing online and offline feature distributions per feature."

---

## Problem 32: A multi-tenant enterprise LLM and agentic gateway

### 32.1 Scope, scale and SLAs

| Quantity | Target |
|---|---|
| Tenants | 5,000 enterprise tenants; internal apps and agents |
| Traffic | 50k requests/s; **tokens, not requests, are the capacity unit** (prompts 100–100k tokens) |
| Backends | Self-hosted GPU pools (vLLM/TRT-LLM) + external model APIs |
| SLOs | TTFT p95 < 1 s for interactive; throughput tiers for batch/agents |
| Governance | Per-tenant budgets, PII redaction, audit logs, model allow-lists, tool permissions for agents |

### 32.2 The core L7 bottlenecks

**1. Requests are the wrong unit of fairness.** From §D:
- Two tenants each limited to 100 req/s.
- A sends 200-token requests and B sends 20,000-token requests.
- **B consumes 99.0% of GPU tokens.**

The gateway must limit **tokens per minute** (input + output; estimated before the call, reconciled after) and
**concurrent sequences** per tenant. The pattern is reserve-then-refund:
1. reserve max_tokens at admission;
2. refund the unused part on completion.

Without it, admission control can't promise capacity. The companion AI KB measured this pattern.

**2. Prefix-aware routing turns KV-cache reuse into capacity.**
- Enterprise traffic shares long system prompts, RAG templates and tool schemas.
- Routing requests with the same prefix to the same replica lets the inference engine reuse the prefix's KV cache:
  prefix caching / RadixAttention.
- The result: lower TTFT and less prefill compute.

From §D (8 replicas, 400 tenants with Zipf traffic, LRU prefix caches of 40 prefixes per replica):

| Routing | Prefix-cache hit rate | Busiest replica |
|---|---|---|
| Round-robin | 51.8% | 1.00× mean |
| **Prefix-aware (hash of prefix, bounded load)** | **88.5%** | 1.25× mean |

That is consistent hashing with bounded loads (Folder 02 file 03 §4) applied to KV caches. The bound (1.25×) keeps one
tenant's hot prefix from overloading a replica.

**3. Semantic caching is a correctness trade, not a free win.**
- Exact-match caching of (model, prompt, parameters) is safe for deterministic settings (temperature 0, fixed
  version).
- *Semantic* caching (embedding similarity above a threshold) returns another user's answer to a "similar" question.
  It needs:
  - per-tenant isolation (never cross tenants);
  - thresholds tuned on false-hit rates;
  - an exclusion list for personalized or tool-using prompts.

**4. Agents multiply calls.**
- One user request becomes 10–50 model and tool calls. Budget per *task* (tokens, tool calls, wall time), not per
  call.
- Enforce tool permissions (Zanzibar-style checks, problem 11) and require idempotency for side-effecting tools.
- Agent loops are retry storms with extra steps (Folder 05 file 02): bound them.

### 32.3 Architecture and paths

```
 client/agent ─► gateway edge: authN (tenant, user), policy (model allow-list, data residency), PII redaction,
                 token estimation → per-tenant TPM/concurrency admission (reserve), priority (interactive > batch)
   ─► cache layer: exact cache (tenant-scoped) → optional semantic cache (tenant-scoped, thresholded)
   ─► router: model selection (cost/latency/quality policy), PREFIX-AWARE replica choice (bounded-load hashing on the
       prefix hash), spillover to external APIs when GPU pools saturate, circuit breakers per backend
   ─► inference pools (continuous batching; prefix caching) / external providers (rate-limited per key)
   ─► stream tokens back (SSE) ; on completion: refund unused reservation, log usage (billing), audit (prompt hashes)
 agents: task budget object (tokens, calls, deadline) propagated through every step; tool calls via a tool proxy with
         per-tool authz, idempotency keys and timeouts
 control: model registry, routing policies, tenant quotas (staged config, LKG on gateways)
```

### 32.4 Schema and partition key

```
tenant_quota: tenant_id → {tpm, max_concurrency, priority, models[], residency}           (config, LKG)
usage:        (tenant_id, minute) → tokens_in/out, cost                                    (stream-aggregated; billing)
exact_cache:  (tenant_id, model_version, hash(prompt, params)) → response, ttl             partition: hash(tenant_id, …)
prefix map:   hash(prefix) → replica (bounded-load ring per model pool)                    (soft state)
audit:        (tenant_id, request_id) → metadata, prompt/response hashes, policy decisions  (immutable, retained)
```

### 32.5 Failure defense, L5/L6/L7, probing chain

| Failure | Defense |
|---|---|
| GPU pool saturation | Token-based admission with priorities; spill batch to queues; spill interactive to external APIs within budget |
| External provider outage / 429s | Per-provider circuit breakers; fallback models with quality tiers; retry budgets |
| Runaway agent | Per-task budgets; loop detection; tool-call caps |
| Cache leak across tenants | Tenant-scoped keys; no global semantic cache; tests for cross-tenant hits |
| Prompt injection via tools/RAG | Tool permissions independent of model output; allow-lists; human confirmation for high-risk actions |
| Cost explosion | Real-time usage aggregation per tenant with alerts and hard caps |

| | L5 | L6 | L7 |
|---|---|---|---|
| Design | A proxy with API keys and request rate limits | Token-based limits, model routing, caching, streaming, usage metering | Reserve-then-refund token admission; prefix-aware bounded-load routing (52% → 89% cache hits); tenant-scoped semantic caching; agent task budgets and tool authz |

1. **Probe:** "Rate-limit each tenant to 100 requests/s." **L5:** "Token bucket per API key."
2. **Probe:** "One tenant's requests are 100× longer." **L6:** "Limit tokens per minute, not requests."
3. **Probe:** "Your GPUs are at 100% and TTFT is 8 s. What's the highest-leverage change?" **L7:**
   - "Before buying GPUs, raise the prefix-cache hit rate with prefix-aware routing. In our model it goes 52% → 89%,
     and each hit skips the prefill for a long shared prompt."
   - "Add priority admission so interactive traffic preempts batch."
   - "Then measure tokens of prefill saved per GPU-hour. That's capacity recovered from scheduling, not hardware."

---

## 33. The listing

```python
"""streams_ml_gateway_lab.py - click aggregation, leaderboards, feature-store leakage, LLM gateway routing
(Folder 08, file 03).

  A. Ad clicks: 1-minute windows with duplicates (at-least-once delivery) and late events: processing-time counting vs
     event-time + dedupe + watermark vs event-time + dedupe + late updates; plus a click-fraud rule.
  B. Leaderboard: a skip list with span counts answers rank(player) in O(log n); verified against a sorted array.
  C. Feature store: training on "latest" feature values (leakage) vs point-in-time (as-of) joins, for a churn model.
  D. LLM gateway: request-count vs token-based tenant limits; prefix-aware routing vs round-robin for KV prefix-cache
     hits.
Standard library only; seeded, deterministic.
"""
import bisect
import collections
import math
import random


# ---------------------------------------------------------------- A. clicks
def clicks(rng: random.Random, n: int = 300_000, ads: int = 500) -> dict:
    events = []
    for cid in range(n):
        t = rng.uniform(0, 3600)
        delay = rng.lognormvariate(math.log(2), 1.0) + (rng.uniform(180, 600) if rng.random() < 0.01 else 0)
        ev = (t + delay, t, cid, rng.randrange(ads), f"ip{rng.randrange(50_000)}")
        events.append(ev)
        if rng.random() < 0.02:
            events.append((t + delay + rng.uniform(1, 30), t, cid, ev[3], ev[4]))      # redelivered duplicate
    for k in range(300 * 30):                                                         # a bot: one IP, one ad
        t = 1800 + k * 0.2
        events.append((t + 1, t, n + k, 7, "ip-bot"))
    events.sort()
    unique = {e[2]: (e[3], int(e[1] // 60)) for e in events if e[4] != "ip-bot"}       # one per click_id
    truth = collections.Counter(unique.values())
    seen_ids = set()
    proc = collections.Counter()
    for arr, t, cid, ad, ip in events:
        proc[(ad, int(arr // 60))] += 1                                               # processing time, no dedupe
    # event time + dedupe + watermark (allowed lateness 120 s); per-IP fraud rule (> 20 clicks/ad/minute)
    wm_counts = collections.Counter()
    late = 0
    watermark = -1.0
    per_ip = collections.Counter()
    for arr, t, cid, ad, ip in events:
        watermark = max(watermark, arr - 120)
        if cid in seen_ids:
            continue
        seen_ids.add(cid)
        if t < watermark - 60:                                                        # its window already closed
            late += 1
            continue
        per_ip[(ip, ad, int(t // 60))] += 1
        wm_counts[(ad, int(t // 60), ip)] += 1
    billed = collections.Counter()
    fraud = 0
    for (ad, w, ip), c in wm_counts.items():
        if per_ip[(ip, ad, w)] > 20:
            fraud += c
        else:
            billed[(ad, w)] += c
    exact = collections.Counter()                                                     # + late updates
    seen2 = set()
    per_ip2 = collections.Counter()
    for arr, t, cid, ad, ip in events:
        if cid not in seen2:
            seen2.add(cid)
            per_ip2[(ip, ad, int(t // 60))] += 1
    for (ip, ad, w), c in per_ip2.items():
        if c <= 20:
            exact[(ad, w)] += c
    err = lambda counts: sum(abs(counts[k] - truth[k]) for k in set(truth) | set(counts))
    return {"truth_total": sum(truth.values()), "proc_error": err(proc), "wm_error": err(billed),
            "late_dropped": late, "exact_error": err(exact), "fraud_filtered": fraud,
            "bot_clicks": 300 * 30}


# ---------------------------------------------------------------- B. skip list leaderboard
class SkipList:
    """Descending scores; each forward pointer stores its span so rank = sum of spans walked (Redis ZSET-style)."""
    MAX = 20

    def __init__(self, rng: random.Random):
        self.rng = rng
        self.head = [None, [None] * self.MAX, [0] * self.MAX]       # [key, forwards, spans]
        self.level = 1
        self.n = 0
        self.steps = 0

    @staticmethod
    def _before(a: tuple, b: tuple) -> bool:                         # (score, player): higher score first
        return (-a[0], a[1]) < (-b[0], b[1])

    def insert(self, key: tuple) -> None:
        update, rank = [None] * self.MAX, [0] * self.MAX
        x = self.head
        for i in range(self.level - 1, -1, -1):
            rank[i] = rank[i + 1] if i < self.level - 1 else 0
            while x[1][i] and self._before(x[1][i][0], key):
                rank[i] += x[2][i]
                x = x[1][i]
                self.steps += 1
            update[i] = x
        lvl = 1
        while lvl < self.MAX and self.rng.random() < 0.25:
            lvl += 1
        if lvl > self.level:
            for i in range(self.level, lvl):
                rank[i], update[i] = 0, self.head
                self.head[2][i] = self.n
            self.level = lvl
        node = [key, [None] * lvl, [0] * lvl]
        for i in range(lvl):
            node[1][i] = update[i][1][i]
            update[i][1][i] = node
            node[2][i] = update[i][2][i] - (rank[0] - rank[i])
            update[i][2][i] = rank[0] - rank[i] + 1
        for i in range(lvl, self.level):
            update[i][2][i] += 1
        self.n += 1

    def delete(self, key: tuple) -> None:
        update = [None] * self.MAX
        x = self.head
        for i in range(self.level - 1, -1, -1):
            while x[1][i] and self._before(x[1][i][0], key):
                x = x[1][i]
                self.steps += 1
            update[i] = x
        target = x[1][0]
        for i in range(self.level):
            if update[i][1][i] is target:
                update[i][2][i] += target[2][i] - 1
                update[i][1][i] = target[1][i]
            else:
                update[i][2][i] -= 1
        self.n -= 1

    def rank(self, key: tuple) -> int:
        r, x = 0, self.head
        for i in range(self.level - 1, -1, -1):
            while x[1][i] and not self._before(key, x[1][i][0]):
                r += x[2][i]
                x = x[1][i]
                self.steps += 1
        return r                                                     # 1-based rank


def leaderboard(rng: random.Random, players: int = 50_000, updates: int = 100_000) -> dict:
    sl = SkipList(rng)
    score = {}
    for p in range(players):
        score[p] = rng.randint(0, 1_000_000)
        sl.insert((score[p], p))
    for _ in range(updates):
        p = rng.randrange(players)
        sl.delete((score[p], p))
        score[p] += rng.randint(1, 5_000)
        sl.insert((score[p], p))
    ordered = sorted(((-s, p) for p, s in score.items()))
    wrong = 0
    sl.steps = 0
    checks = 5_000
    for _ in range(checks):
        p = rng.randrange(players)
        expect = bisect.bisect_left(ordered, (-score[p], p)) + 1
        wrong += sl.rank((score[p], p)) != expect
    return {"wrong": wrong, "checks": checks, "steps_per_rank": sl.steps / checks, "log2n": math.log2(players)}


# ---------------------------------------------------------------- C. feature store leakage
def feature_leakage(rng: random.Random, users: int = 20_000) -> dict:
    day = 86400
    rows = []
    for _ in range(users):
        t0 = rng.uniform(30, 60) * day                                         # prediction time
        churn = rng.random() < 0.3
        rate = rng.uniform(0.2, 1.0) * (0.4 if churn else 1.0)                 # churners were already less active
        logins, t = [], 0.0
        stop = t0 + rng.uniform(0, 7) * day if churn else math.inf
        while True:
            t += rng.expovariate(rate / day)
            if t > t0 + 21 * day or t > stop:
                break
            logins.append(t)
        label = not any(t0 < x <= t0 + 7 * day for x in logins)
        asof = t0 - max([x for x in logins if x <= t0], default=0)            # days since last login AS OF t0
        latest = (t0 + 21 * day) - max(logins, default=0)                     # computed at training time (leaks)
        rows.append((asof / day, latest / day, label))

    def f1(idx: int, th: float) -> float:
        tp = sum(1 for r in rows if r[idx] > th and r[2])
        fp = sum(1 for r in rows if r[idx] > th and not r[2])
        fn = sum(1 for r in rows if r[idx] <= th and r[2])
        return 2 * tp / (2 * tp + fp + fn) if tp else 0.0

    def fit_and_score(train_idx: int, test_idx: int) -> tuple[float, float]:
        """Fit a threshold on the training feature (max F1), then score it on the feature production serves."""
        best_th = max((x / 4 for x in range(0, 200)), key=lambda th: f1(train_idx, th))
        return f1(train_idx, best_th), f1(test_idx, best_th)
    leaky_off, leaky_on = fit_and_score(1, 0)            # trained on leaked features, served point-in-time features
    pit_off, pit_on = fit_and_score(0, 0)
    return {"leaky_offline": leaky_off, "leaky_online": leaky_on, "pit_offline": pit_off, "pit_online": pit_on,
            "base_rate": sum(r[2] for r in rows) / len(rows)}


# ---------------------------------------------------------------- D. LLM gateway
def prefix_routing(rng: random.Random, replicas: int = 8, cache_prefixes: int = 40, reqs: int = 100_000) -> dict:
    tenants = 400
    w = [1 / (i + 1) ** 1.0 for i in range(tenants)]
    traffic = rng.choices(range(tenants), weights=w, k=reqs)
    out = {}
    for mode in ("round-robin", "prefix-aware (hash of prefix, bounded load)"):
        caches = [collections.OrderedDict() for _ in range(replicas)]
        load = [0] * replicas
        hits = 0
        for i, t in enumerate(traffic):
            if mode == "round-robin":
                r = i % replicas
            else:
                r = (t * 2654435761 % 2 ** 32) % replicas
                if load[r] > 1.25 * (i + 1) / replicas:                        # bounded load: spill to the next one
                    r = (r + 1) % replicas
            load[r] += 1
            c = caches[r]
            if t in c:
                hits += 1
                c.move_to_end(t)
            else:
                c[t] = True
                if len(c) > cache_prefixes:
                    c.popitem(last=False)
        out[mode] = {"hit": hits / reqs, "max_load_share": max(load) / reqs * replicas}
    return out


def main() -> None:
    rng = random.Random(29)
    print("== A. ad clicks: 300k clicks over 1 h, 500 ads, 2% duplicates, 1% arrive 3-10 min late, plus a 9,000-click bot")
    ck = clicks(rng)
    print(f"  ground truth (legit, deduped, by event-time minute): {ck['truth_total']:,} clicks")
    print(f"  processing-time count, no dedupe, no fraud filter:  total abs error {ck['proc_error']:>7,}")
    print(f"  event time + dedupe + 2-min watermark + fraud rule:  total abs error {ck['wm_error']:>7,} "
          f"(late events dropped {ck['late_dropped']:,}; bot clicks filtered {ck['fraud_filtered']:,} of {ck['bot_clicks']:,})")
    print(f"  ... + late updates (retractions/upserts, no drop):   total abs error {ck['exact_error']:>7,}")

    print("\n== B. leaderboard skip list: 50k players, 100k score updates, 5,000 rank queries checked")
    lb = leaderboard(rng)
    print(f"  wrong ranks {lb['wrong']}/{lb['checks']}; {lb['steps_per_rank']:.1f} pointer steps per rank query "
          f"(log2 n = {lb['log2n']:.1f})")

    print("\n== C. churn model on 'days since last login': training features joined how?")
    fl = feature_leakage(rng)
    print(f"  base rate (churners) {fl['base_rate'] * 100:.1f}%")
    print(f"  trained on LATEST values (leak): offline F1 {fl['leaky_offline']:.3f} -> in production "
          f"{fl['leaky_online']:.3f}")
    print(f"  trained on POINT-IN-TIME values:  offline F1 {fl['pit_offline']:.3f} -> in production "
          f"{fl['pit_online']:.3f}")

    print("\n== D. LLM gateway")
    a_tok, b_tok = 100 * 200, 100 * 20_000
    print(f"  request limits (100 req/s each): tenant A uses {a_tok:,} tokens/s, tenant B {b_tok:,} -> B takes "
          f"{b_tok / (a_tok + b_tok) * 100:.1f}% of GPU tokens; token-per-minute budgets make capacity shares explicit")
    pr = prefix_routing(rng)
    for mode, r in pr.items():
        print(f"  {mode:<44} prefix-cache hit {r['hit'] * 100:5.1f}%   busiest replica {r['max_load_share']:.2f}x mean")

    assert ck["exact_error"] == 0 and ck["wm_error"] < ck["proc_error"] / 10 and ck["fraud_filtered"] >= 9000
    assert lb["wrong"] == 0 and lb["steps_per_rank"] < 4 * lb["log2n"]
    assert fl["leaky_offline"] > fl["pit_offline"] + 0.1 and fl["leaky_online"] < fl["pit_online"]
    assert abs(fl["pit_offline"] - fl["pit_online"]) < 1e-9
    rr, pa = pr["round-robin"], pr["prefix-aware (hash of prefix, bounded load)"]
    assert pa["hit"] > rr["hit"] + 0.15 and pa["max_load_share"] < 1.3
    print("\nself-test: all assertions passed")


if __name__ == "__main__":
    main()
```

Output (verified; deterministic):

```text
== A. ad clicks: 300k clicks over 1 h, 500 ads, 2% duplicates, 1% arrive 3-10 min late, plus a 9,000-click bot
  ground truth (legit, deduped, by event-time minute): 300,000 clicks
  processing-time count, no dedupe, no fraud filter:  total abs error  36,021
  event time + dedupe + 2-min watermark + fraud rule:  total abs error   2,885 (late events dropped 2,885; bot clicks filtered 9,000 of 9,000)
  ... + late updates (retractions/upserts, no drop):   total abs error       0

== B. leaderboard skip list: 50k players, 100k score updates, 5,000 rank queries checked
  wrong ranks 0/5000; 21.5 pointer steps per rank query (log2 n = 15.6)

== C. churn model on 'days since last login': training features joined how?
  base rate (churners) 18.6%
  trained on LATEST values (leak): offline F1 0.913 -> in production 0.061
  trained on POINT-IN-TIME values:  offline F1 0.395 -> in production 0.395

== D. LLM gateway
  request limits (100 req/s each): tenant A uses 20,000 tokens/s, tenant B 2,000,000 -> B takes 99.0% of GPU tokens; token-per-minute budgets make capacity shares explicit
  round-robin                                  prefix-cache hit  51.8%   busiest replica 1.00x mean
  prefix-aware (hash of prefix, bounded load)  prefix-cache hit  88.5%   busiest replica 1.25x mean

self-test: all assertions passed
```

---

## 34. References for problems 29–32

- Google. *Ad click prediction: a view from the trenches*, KDD 2013 (context). T. Akidau et al., *The Dataflow
  Model*, VLDB 2015 (event time, watermarks, late data).
- Redis documentation: sorted sets (skip list + hash table). W. Pugh, *Skip Lists: A Probabilistic Alternative to
  Balanced Trees*, CACM 1990.
- Uber Engineering. *Michelangelo*, 2017. Feast documentation (point-in-time joins). Tecton/Hopsworks writings on
  training–serving skew (⚠ verify).
- D. Sculley et al. *Hidden Technical Debt in Machine Learning Systems.* NeurIPS 2015.
- W. Kwon et al. *Efficient Memory Management for Large Language Model Serving with PagedAttention (vLLM).* SOSP
  2023. L. Zheng et al., *SGLang / RadixAttention*, 2024.
- The companion *Production AI Engineering L7 Reference* (this workspace) for KV-cache math, prefix routing and gateway
  economics.
