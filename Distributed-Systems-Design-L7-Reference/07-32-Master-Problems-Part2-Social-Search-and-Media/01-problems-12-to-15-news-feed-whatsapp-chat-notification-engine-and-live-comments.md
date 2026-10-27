# Problems 12–15: Hybrid-Fanout News Feed, WhatsApp/Slack Chat, Notification Engine, Live Comments

> **Folder 07 · File 01** of the Distributed Systems & System Design L7 Reference: the 32 Master Problems, Part 2
> (Social, Search and Media).
> **Listing:** `feed_chat_lab.py` covers:
> - push vs pull vs hybrid fan-out on a Pareto follower graph;
> - chat idempotency and sequence ordering;
> - notification priority lanes under a burst;
> - live-comment fan-out arithmetic.
>
> The output is deterministic.

---

## Problem 12: A news feed with hybrid fan-out (celebrity pull + normal push)

### 12.1 Scope, scale and SLAs

| Quantity | Target |
|---|---|
| Users | 500M DAU; 1 post per user per day; 20 feed loads per user per day |
| Graph | Follower counts heavy-tailed: lab sample mean **160**, median **37**, max **2.17M** |
| Feed load latency | p99 < 200 ms (first page) |
| Freshness | A post visible to followers within seconds (p99 < 10 s) |
| Ranking | ML-ranked, not chronological |

**Capacity math** (§A of the output, scaled from a 200k-user Pareto sample to 500M users):

| Strategy | Inbox writes/s | Merges per feed read | Timeline reads/s | Worst single-post fan-out |
|---|---|---|---|---|
| Pure push (fan-out on write) | 923,452 | 1.0 | 115,741 | **2,168,469** |
| Hybrid, celebrities ≥ 100k followers pulled | 741,751 | 32.4 | 3.7M | 96,769 |
| **Hybrid, celebrities ≥ 10k pulled** | 588,091 | 59.0 | 6.8M | **9,990** |
| Hybrid, celebrities ≥ 1k pulled | 408,520 | 90.0 | 10.4M | 999 |
| Pure pull (fan-in on read) | 0 | 160.6 | **18.6M** | 0 |

The lesson is not "push is expensive". **With a heavy-tailed graph, the hybrid's main benefit is bounding the
per-post fan-out.**
- Average inbox writes fall by only 36% at the 10k threshold.
- The worst post goes from 2.17M inbox writes (a write storm every time a celebrity posts) to < 10k.
- The cost moves to reads (59 timeline merges per load). Those merges hit a small set of **celebrity timelines that
  are extremely hot, and therefore always cache-resident** (Folder 04 file 02).

**The threshold is a cost optimization:** minimize (write cost × writes) + (read cost × merges), subject to the
fan-out latency SLO. It should be tuned from measured follower and read distributions, not set at a magic 10k.

### 12.2 Schema and partition key

```
posts:        post_id (Snowflake, time-ordered) → {author_id, body_ref, media_refs, created}   partition: hash(post_id)
author_tl:    (author_id, post_id DESC) → ∅                     partition: hash(author_id)  ← celebrity timelines (pulled)
inbox:        (user_id, rank_hint/post_id DESC) → {author_id}   partition: hash(user_id), capped at ~800 entries
social graph: (user_id) → following list ; (author_id) → follower list (sharded for celebrities)   (TAO-like)
seen/engagement: (user_id, post_id) → impressions/likes (for ranking, dedupe)
```

### 12.3 Architecture and paths

```
 WRITE: post → posts store → event (Kafka, partitioned by author) → fan-out workers:
          if author.followers < T: for follower batches → append post_id to each follower's inbox (async, rate-limited)
          else: append to author_tl only (celebrity)
 READ:  feed service: candidates = inbox(user) ∪ ⋃ author_tl(c) for followed celebrities c (cached, top-N each)
          → filter (blocked, seen, deleted) → rank (feature fetch + model) → hydrate (posts, users, media URLs)
          → page 1 (cursor = opaque ranking state)
 CONTROL: threshold T, ranking model versions, fan-out rate limits; backfill tools (new follow → backfill inbox)
 RECOVERY: fan-out workers are idempotent (inbox append keyed by (user, post_id)); lag SLI; on backlog, prefer
           pull for active users (read-time merge of recent author timelines) — degrade freshness not availability
```

### 12.4 The core L7 bottleneck, and the other hard parts

1. **Bounded fan-out per post** (above). Also rate-limit fan-out per author so a celebrity's post never competes with
   everyone else's in the same queue. That is per-tenant fair queueing (Folder 05 file 01 §4).
2. **Ranking is the real latency budget.** Candidate generation is ~1,000 posts; feature fetch is the fan-out
   (Folder 01 file 01 §6.4). Hedge feature-store reads and set per-stage deadlines: retrieval 30 ms, features 40 ms,
   model 50 ms.
3. **Inactive users.** Don't fan out to users who haven't opened the app in 30 days. Build their feed on demand
   (pull) when they return. This alone removes a large fraction of push writes.
4. **Deletes and privacy.** A deleted or privacy-changed post must disappear everywhere. Filter at read time against
   the post store (cheap: hydration already reads it), rather than trying to delete from millions of inboxes.

### 12.5 Failure defense

| Failure | Defense |
|---|---|
| Celebrity post storm | Hybrid threshold; author timeline cached and replicated (hot key) |
| Fan-out backlog | Lag SLI; switch active users to pull temporarily; shed fan-out for inactive users |
| Ranking service slow | Fallback to cached ranked feed / reverse-chronological (graceful degradation) |
| Hot user inbox (bot with 1M follows) | Per-user follow limits; such users are served by pull |
| Cache cold start | Warm celebrity timelines first; admission control at the store |

### 12.6 L5 / L6 / L7 and probing chain

| | L5 | L6 | L7 |
|---|---|---|---|
| Design | Fan-out on write to inboxes | Hybrid push/pull with a celebrity threshold; caches; ranking pipeline | Threshold as a measured cost optimization; bounded per-post fan-out; inactive-user pull; read-time filtering for deletes; staged deadlines |

1. **Probe:** "Fan out every post to every follower." **L5:** "Followers read from their inbox."
2. **Probe:** "A user with 50M followers posts." **L6:** "Don't push celebrities; merge their timelines at read time."
3. **Probe:** "Why 10k, and what does each user's feed load now cost?" **L7:**
   - "The threshold balances inbox writes against read merges. In our sample, 10k cuts the worst post from 2.2M to
     10k writes, but each feed load merges ~59 celebrity timelines."
   - "Those 59 lists come from a small, hot, cache-resident set, so a merge is ~59 cache reads in parallel within the
     30 ms retrieval budget."
   - "I'd tune T from production distributions, per region, and lower it if inbox storage cost dominates."

---

## Problem 13: WhatsApp/Slack-class chat (1:1 and group)

### 13.1 Scope, scale and SLAs

| Quantity | Target |
|---|---|
| Users | 2B registered, 500M concurrently connected |
| Messages | 100B/day ≈ **1.2M msgs/s** average, 3–5M/s peak (New Year's Eve) |
| Delivery latency | p99 < 500 ms end-to-end when both are online |
| Ordering | Per conversation, as seen by every participant |
| Delivery semantics | No message lost; no duplicates shown; offline delivery on reconnect |
| Groups | Up to 1,000 members (WhatsApp-like); channels up to 100k+ (Slack-like) |

**Capacity math.**
- 500M persistent connections at ~100–500k connections per gateway host (epoll; ~10–50 KB per connection with TLS
  state) → **1,000–5,000 gateway hosts**.
- Message storage: 100B × 200 B = 20 TB/day. WhatsApp's model deletes messages after delivery, storing only
  undelivered ones. Slack-like retention keeps everything, which means a searchable index.

### 13.2 Schema and partition key

```
conversation: conv_id → {members, type, settings}                     partition: hash(conv_id)
messages:     (conv_id, seq) → {msg_id (client-generated UUID), sender, body (E2E ciphertext), ts}
              seq assigned by the conversation's partition leader: strictly increasing per conversation
inbox/sync:   (user_id, device_id) → per-conversation read cursor + last delivered seq   (sync state)
sessions:     user_id → {gateway host, device list}   (presence/routing; soft state with TTL)
```

**Everything about a conversation goes to one partition.** That gives per-conversation total order cheaply: no global
clocks, no consensus across partitions (Folder 03 file 02 §6).

### 13.3 Architecture and paths

```mermaid
sequenceDiagram
    participant A as Sender device
    participant GA as Gateway (A's connection)
    participant CS as Conversation service (partition leader for conv)
    participant GB as Gateway (B's connection)
    participant B as Recipient device
    A->>GA: send {conv, client_msg_id, ciphertext}
    GA->>CS: append
    CS->>CS: dedupe on client_msg_id, assign seq = last+1, persist (replicated)
    CS-->>GA: ack {seq}
    GA-->>A: sent (single tick)
    CS->>GB: deliver {conv, seq, ...} (lookup session registry)
    GB->>B: push over persistent connection
    B-->>GB: delivered ack (seq)
    GB-->>CS: delivered → update cursor; notify A (double tick)
    Note over B: offline - CS keeps message - push notification (problem 14) - on reconnect, B syncs from cursor
```

### 13.4 The core L7 bottleneck: exactly-once *display* over an at-least-once network

§B of the output (50,000 messages, 5% lost acks with client resends, random delivery delays):

| | Duplicates rendered | Adjacent misorderings when rendering by arrival | …rendering by sequence number |
|---|---|---|---|
| No idempotency | **2,983** | 15,701 | 0 |
| **Client message IDs + server sequence** | **0** | 15,378 | **0** |

- **Retries are mandatory** (mobile networks drop acks), so **dedupe is mandatory**. The client generates `msg_id`
  before the first send, and the server stores (conv_id, msg_id) → seq.
- **Arrival order is not message order.** Messages arrive out of order a third of the time under realistic delays.
  Recipients render by `seq`, detect **gaps** (seq 41, 43 → fetch 42), and request a resync from the cursor.
- **Multi-device:** each device has its own cursor, and sync is "give me everything after seq N for these
  conversations". The same protocol covers reconnects, new devices and missed pushes. It is pull-based catch-up
  plus push for immediacy.

### 13.5 Groups and channels: the fan-out problem again

- **Small groups** (≤ 1,000) fan out at write time to members' delivery queues. Each member's gateway gets a copy.
- **End-to-end encryption complicates group fan-out.**
  - The Signal protocol's sender keys let the sender encrypt once per group message (plus pairwise key distribution
    when membership changes).
  - The server fans out ciphertext without reading it.
  - Membership changes trigger re-keying, a cost that grows with group size.
- **Large channels** (Slack-like, 100k members) are read-heavy:
  - store once per channel;
  - members pull on view;
  - only *notify* online members, batched, with "unread" counters maintained asynchronously;
  - mentions and DMs get priority delivery.

### 13.6 Failure defense

| Failure | Defense |
|---|---|
| Gateway host dies (500k connections) | Clients reconnect with **jittered backoff** to other gateways; session registry updated; sync from cursor fills gaps |
| Reconnect storm after a regional blip | Jitter, connection admission rate limits per gateway, priority for active conversations |
| Conversation partition leader failover | Raft-replicated partitions; seq continues from the committed log |
| Hot group (viral 1,000-member group) | Per-conversation rate limits; batched delivery |
| Message loss on a missed push | Not possible by design: delivery state is cursor-based, and pushes are only hints |

### 13.7 L5 / L6 / L7 and probing chain

| | L5 | L6 | L7 |
|---|---|---|---|
| Design | WebSockets + a message table | Per-conversation partitioning and sequence numbers, client message IDs, cursors, offline push | Exactly-once display over at-least-once delivery; gap detection and resync as the single protocol; reconnect storms; E2E group fan-out costs |

1. **Probe:** "How do you guarantee ordering?" **L5:** "Timestamps."
2. **Probe:** "Phones have skewed clocks." **L6:** "Server-assigned per-conversation sequence numbers from the
   partition leader."
3. **Probe:** "A user sends 3 messages offline, then reconnects; another member sent 2 meanwhile." **L7:**
   - "The offline messages carry client IDs and are sequenced on arrival, *after* the other member's 2. The sender's
     UI shows them as pending until acked, then reorders them into the server's sequence."
   - "Some apps preserve the sender's local order by sequencing their batch atomically. The product chooses, but the
     server sequence is the single truth every device converges to."

---

## Problem 14: A multi-channel notification engine

### 14.1 Scope, scale and SLAs

| Quantity | Target |
|---|---|
| Channels | Push (APNs/FCM), SMS, email, in-app, webhooks |
| Volume | 5B notifications/day; **bursts of 50M+ in minutes** (breaking news, campaigns) |
| Transactional latency | OTP / security alerts: p99 < 5 s end-to-end |
| Marketing latency | Minutes to hours acceptable |
| Correctness | No duplicate sends (users notice); respect preferences, quiet hours, frequency caps |

### 14.2 The core L7 bottleneck: shared egress capacity across priorities

Every channel has a **provider-limited egress rate**: APNs/FCM connection throughput, SMS aggregator TPS, email
reputation and throttling. §C of the output models a 2M-message marketing burst sharing a 50k/s sender with OTP codes
at 200/s:

| Queueing | OTP p50 | OTP p99 |
|---|---|---|
| Single FIFO | **10.4 s** | **39.3 s** (2FA codes expire, logins fail) |
| **Priority lanes** (transactional ≫ marketing) | < 1 ms | < 1 ms |

This is criticality-based shedding (Folder 05 file 02 §3.3) applied to egress:
- **separate queues and separate provider quotas per priority class;**
- marketing is the first to be delayed;
- transactional traffic is never queued behind bulk.

### 14.3 Schema and partition key

```
notification request: {idempotency_key, user_id, template, priority, channel prefs override, dedupe_window, ttl}
preferences:  user_id → channels, quiet hours, frequency caps, locale            partition: hash(user_id)
send log:     (user_id, idempotency_key) → status per channel                    (dedupe; TTL = dedupe window)
device tokens: user_id → [(platform, token, last_valid)]                          (prune on provider 410/Unregistered)
campaign:     campaign_id → audience query, schedule, rate cap, priority
```

### 14.4 Architecture and paths

```
 producers (services, campaign scheduler) ─► ingest API (validate, idempotency check) ─► priority topics
   [P0 security/OTP] [P1 transactional] [P2 social] [P3 marketing]  (Kafka topics / queues per priority)
 per-priority workers: fetch prefs (cached), apply caps/quiet hours, render template (localized), choose channels
   ─► per-channel, per-provider senders with token buckets matching provider limits; P0 has reserved capacity
   ─► providers (APNs/FCM/SMS/email) ─► feedback (bounces, invalid tokens, delivery receipts) ─► token pruning, metrics
 campaigns: audience expansion is itself rate-limited (don't enqueue 50M at once; trickle by rate cap)
```

### 14.5 Failure defense

| Failure | Defense |
|---|---|
| Duplicate sends from retries | Idempotency key per (user, notification); send-log dedupe; provider collapse keys |
| Provider outage/throttle | Per-provider circuit breaker; failover channel for P0 (SMS ↔ voice ↔ email) |
| Campaign floods | Audience expansion rate caps; P3 lane; per-user frequency caps |
| Stale device tokens | Prune on provider feedback; expected-delivery metrics per platform |
| Quiet-hours/timezone bugs | Evaluate in the user's timezone at send time; delayed delivery queue (problem 7's scheduler) |

### 14.6 L5 / L6 / L7 and probing chain

| | L5 | L6 | L7 |
|---|---|---|---|
| Design | A queue and workers per channel | Priorities, preferences, idempotency, provider rate limits | Egress capacity partitioned by criticality (OTP p99 39 s → < 1 ms); campaign expansion as admission control; channel failover for P0 |

1. **Probe:** "Marketing sends 50M pushes for a sale." **L5:** "Workers will process them."
2. **Probe:** "Logins fail because OTP SMS take 40 s." **L6:** "Separate high-priority queue for OTPs."
3. **Probe:** "Both use the same SMS aggregator with a 1,000 TPS contract." **L7:**
   - "Partition the *provider quota*: reserve, say, 30% for P0 via separate token buckets, with marketing allowed to
     borrow only unused P0 capacity."
   - "Add a second aggregator for P0 failover."
   - "Campaign audience expansion is paced to the remaining quota, so the queue never holds more than minutes of
     marketing backlog."

---

## Problem 15: Live comments and reactions for millions of concurrent viewers

### 15.1 Scope, scale and SLAs

| Quantity | Target |
|---|---|
| Concurrent viewers per live event | 2M (peaks of 10M+ for major sports) |
| Comment rate | 5,000/s during peaks; reactions 100k+/s |
| Latency | Comments visible within ~1–2 s |
| Display | A human reads ~5–10 comments/s; reactions are aggregated (counts, animations) |

**Capacity math** (§D of the output):
- **Naive broadcast** of every comment to every viewer: 2M × 5,000 = **10¹⁰ messages/s**. Impossible, and pointless,
  since no one can read 5,000 comments a second.
- **Sample ~10 comments/s per viewer and batch into 200 ms frames:** 2×10⁷ comments/s delivered as **10⁷ frames/s**
  fleet-wide.
- **Per edge server with 50k viewers:** 250,000 frames/s and ~0.6 Gbps of comment payload. That is feasible on a
  handful of edge hosts per PoP.

### 15.2 Architecture and paths

```
 WRITE: viewer → API (auth, rate limit per user, moderation pre-filter) → event topic (partitioned by event_id;
        sharded into N sub-partitions for hot events) → aggregator(s):
          • comments: dedupe, moderation (async ML + rules), ranking/sampling (friends, verified, high-quality first)
          • reactions: counted per 200 ms window (CRDT-like counters per shard, summed)
        → per-event "frame" stream (selected comments + reaction counts every 200 ms)
 FANOUT: frame stream → regional pub/sub → edge PoPs (subscribe per event) → each edge broadcasts to its local
         viewers' connections (WebSocket/SSE/QUIC)  ← hierarchical fan-out: 1 → regions → PoPs → viewers
 READ:   viewer joins: gets last N comments snapshot (cache) + subscribes; personalization at the edge (own comments,
         friends) layered onto the shared frame
```

### 15.3 The core L7 bottleneck: fan-out cost scales with viewers × rate, so cut it at the source

1. **Sample and aggregate before fan-out.** The shared frame is identical for millions of viewers, so compute it once
   per event and fan out bytes, not decisions. Reactions become counts, never individual messages.
2. **Hierarchical pub/sub.** Origin → region → PoP → viewer. Each tier multiplies by ~10–1,000, so no tier handles
   the full product.
3. **Personalization at the edge**, cheaply: "your own comment" is echoed locally. Friends' comments are merged by
   the edge from a small per-viewer filter.
4. **Hot-event isolation.** The Super Bowl gets dedicated aggregator and pub/sub capacity (cells), pre-provisioned
   before kickoff. That is static stability, with no autoscaling at minute zero.

### 15.4 Failure defense

| Failure | Defense |
|---|---|
| Join storm at kickoff (5M connects in a minute) | Jittered reconnect, connection admission control, snapshot served from CDN-cached JSON |
| Aggregator failure | Standby per event; frames carry sequence numbers; edges tolerate gaps (comments are lossy by design) |
| Spam/abuse wave | Per-user rate limits, shadow-banning at the aggregator, moderation queue |
| Edge PoP overload | Shed by lowering per-viewer comment rate (degrade to reactions-only) before disconnecting |

### 15.5 L5 / L6 / L7 and probing chain

| | L5 | L6 | L7 |
|---|---|---|---|
| Design | WebSockets broadcasting every comment | Pub/sub to edge servers; rate limiting; reactions aggregated | Fan-out arithmetic (10¹⁰/s naive) → sample + batch + hierarchical fan-out; personalization at the edge; per-event cells pre-provisioned |

1. **Probe:** "Broadcast each comment over WebSockets." **L5:** "Each server pushes to its connected users."
2. **Probe:** "2M viewers, 5k comments/s." **L6:** "10 billion messages/s; batch and sample per viewer."
3. **Probe:** "Users complain their own comment never appears." **L7:**
   - "Sampling must be *personalized at the edge*: the edge always includes the viewer's own comments and their
     friends' (from a small per-viewer set), merged into the shared frame."
   - "The server-side cost stays per event, not per viewer."
   - "Same principle as the feed: shared work centrally, per-user work at the cheapest tier."

---

## 16. The listing

```python
"""feed_chat_lab.py - feed fan-out economics, chat ordering, notification priorities, live-comment fan-out
(Folder 07, file 01).

  A. News feed: push (fan-out on write) vs pull (fan-in on read) vs hybrid with a celebrity threshold, on a
     power-law follower graph: inbox writes/s, merges per feed read, worst single-post fan-out.
  B. Chat: client retries after lost acks and out-of-order delivery; duplicates and misordering without vs with
     client message IDs and per-conversation server sequence numbers.
  C. Notifications: a 2M-message marketing burst sharing a provider-limited sender with OTP codes; OTP delay with a
     single FIFO vs priority lanes.
  D. Live comments: messages/s for naive broadcast vs per-viewer sampling + batching.
Standard library only; seeded, deterministic.
"""
import collections
import heapq
import random


# ---------------------------------------------------------------- A. feed fan-out
def follower_graph(users: int, rng: random.Random) -> list[int]:
    """Follower counts ~ Pareto (heavy tail): most users have tens of followers, a few have millions."""
    out = []
    for _ in range(users):
        f = int(20 * (1 / (1 - rng.random())) ** (1 / 1.1))      # Pareto(alpha=1.1, x_min=20)
        out.append(min(f, 50_000_000))
    return out


def fanout(followers: list[int], scale: float, posts_per_user_day: float, reads_per_user_day: float,
           threshold: float) -> dict:
    """Push for authors with followers < threshold; pull (merge at read time) for the rest."""
    day = 86400
    pushed = sum(f for f in followers if f < threshold)
    celebs = [f for f in followers if f >= threshold]
    writes_s = pushed * scale * posts_per_user_day / day
    # each user follows celebrities in proportion to their follower counts: expected celebrity follows per user
    total_follow_edges = sum(followers)
    celeb_follows_per_user = sum(celebs) / len(followers)
    merges_per_read = 1 + celeb_follows_per_user                 # own inbox + each celebrity timeline
    reads_s = len(followers) * scale * reads_per_user_day / day
    return {"inbox_writes_s": writes_s, "merges_per_read": merges_per_read,
            "timeline_reads_s": reads_s * merges_per_read,
            "max_fanout": max((f for f in followers if f < threshold), default=0),
            "avg_follows": total_follow_edges / len(followers)}


# ---------------------------------------------------------------- B. chat
def chat(messages: int, dedupe: bool, rng: random.Random) -> dict:
    """Sender sends; 5% of acks are lost so the client resends. The server either dedupes by client message ID
    (idempotency) and assigns a per-conversation sequence number, or stores every attempt. Delivery to the
    recipient reorders messages with random network delays; the recipient renders by arrival or by sequence."""
    stored = []                                                    # (seq, client_msg_id)
    seen = set()
    seq = 0
    for cid in range(messages):
        attempts = 1 + (rng.random() < 0.05) + (rng.random() < 0.01)
        for _ in range(attempts):
            if dedupe and cid in seen:
                continue
            seen.add(cid)
            seq += 1
            stored.append((seq, cid))
    deliveries = sorted((s + rng.expovariate(0.5), s, cid) for s, cid in stored)    # arrival order
    arrival_order = [cid for _, _, cid in deliveries]
    seq_order = [cid for _, cid in sorted((s, cid) for _, s, cid in deliveries)]
    dupes = len(arrival_order) - len(set(arrival_order))
    inversions_arrival = sum(1 for a, b in zip(arrival_order, arrival_order[1:]) if a > b)
    inversions_seq = sum(1 for a, b in zip(seq_order, seq_order[1:]) if a > b)
    return {"rendered_duplicates": dupes, "misordered_by_arrival": inversions_arrival,
            "misordered_by_seq": inversions_seq}


# ---------------------------------------------------------------- C. notifications
def notifications(lanes: bool, rng: random.Random) -> dict:
    """Provider-limited sender: 50,000 msgs/s. At t=0 a 2M marketing campaign is enqueued; OTP codes arrive at
    200/s throughout. Measure OTP delivery delay."""
    rate = 50_000.0
    q_fifo: collections.deque = collections.deque()
    q_hi: collections.deque = collections.deque()
    q_lo: collections.deque = collections.deque()
    for _ in range(2_000_000):
        (q_lo if lanes else q_fifo).append(("mkt", 0.0))
    otp_arrivals = []
    t = 0.0
    while t < 60:
        t += rng.expovariate(200)
        otp_arrivals.append(t)
    i = 0
    now = 0.0
    delays = []
    step = 1 / rate
    while (q_fifo or q_hi or q_lo or i < len(otp_arrivals)) and now < 120:
        while i < len(otp_arrivals) and otp_arrivals[i] <= now:
            (q_hi if lanes else q_fifo).append(("otp", otp_arrivals[i]))
            i += 1
        q = q_hi if (lanes and q_hi) else (q_lo if lanes else q_fifo)
        if q:
            kind, at = q.popleft()
            if kind == "otp":
                delays.append(now - at)
        now += step
    delays.sort()
    return {"otp_p50": delays[len(delays) // 2], "otp_p99": delays[int(len(delays) * 0.99)], "otp_n": len(delays)}


def main() -> None:
    rng = random.Random(12)
    print("== A. feed fan-out: 200k-user sample of a Pareto follower graph, scaled to 500M users;")
    print("       1 post and 20 feed reads per user per day")
    g = follower_graph(200_000, rng)
    scale = 500e6 / len(g)
    print(f"  mean followers {sum(g) / len(g):.0f}, median {sorted(g)[len(g) // 2]}, max {max(g):,}")
    print(f"{'strategy':<26} {'inbox writes/s':>15} {'merges/read':>12} {'timeline reads/s':>17} {'max fan-out/post':>17}")
    fo = {}
    for label, th in (("pure push", float("inf")), ("hybrid, celeb >= 100k", 100_000), ("hybrid, celeb >= 10k", 10_000),
                      ("hybrid, celeb >= 1k", 1_000), ("pure pull", 0)):
        r = fanout(g, scale, 1, 20, th)
        fo[label] = r
        print(f"{label:<26} {r['inbox_writes_s']:>15,.0f} {r['merges_per_read']:>12.1f} "
              f"{r['timeline_reads_s']:>17,.0f} {r['max_fanout']:>17,}")

    print("\n== B. chat: 50,000 messages, 5% lost acks (client resends), random delivery delays")
    ch = {d: chat(50_000, d, rng) for d in (False, True)}
    for d, r in ch.items():
        print(f"  {'client msg IDs + server seq' if d else 'no idempotency          '}: duplicates rendered "
              f"{r['rendered_duplicates']:>5}; adjacent misorderings by arrival {r['misordered_by_arrival']:>6}, "
              f"by sequence number {r['misordered_by_seq']:>3}")

    print("\n== C. notifications: 2M marketing burst + 200/s OTP codes, provider limit 50k/s")
    nt = {ln: notifications(ln, rng) for ln in (False, True)}
    for ln, r in nt.items():
        print(f"  {'priority lanes' if ln else 'single FIFO   '}: OTP p50 {r['otp_p50']:7.3f} s   p99 {r['otp_p99']:7.3f} s")

    print("\n== D. live comments: 2M concurrent viewers, 5,000 comments/s")
    viewers, cps = 2_000_000, 5_000
    naive = viewers * cps
    shown = 10                                                         # comments/s a human can read
    batched = viewers * (1 / 0.2)                                      # one frame per viewer every 200 ms
    print(f"  naive broadcast: {naive:.1e} messages/s; sample {shown}/s per viewer: {viewers * shown:.1e} comments/s "
          f"delivered in {batched:.1e} frames/s (200 ms batches)")
    print(f"  per edge server with 50k viewers: {50_000 * 5:,} frames/s, ~{50_000 * shown * 150 * 8 / 1e9:.1f} Gbps "
          f"of comment payload at 150 B each")

    assert fo["hybrid, celeb >= 10k"]["inbox_writes_s"] < 0.7 * fo["pure push"]["inbox_writes_s"]
    assert fo["pure push"]["max_fanout"] > 100 * fo["hybrid, celeb >= 10k"]["max_fanout"]
    assert fo["hybrid, celeb >= 10k"]["merges_per_read"] < 0.5 * fo["pure pull"]["merges_per_read"]
    assert fo["hybrid, celeb >= 10k"]["max_fanout"] < 10_000 <= fo["pure push"]["max_fanout"]
    assert ch[False]["rendered_duplicates"] > 1000 and ch[True]["rendered_duplicates"] == 0
    assert ch[True]["misordered_by_seq"] == 0 and ch[True]["misordered_by_arrival"] > 1000
    assert nt[False]["otp_p99"] > 30 and nt[True]["otp_p99"] < 0.01
    print("\nself-test: all assertions passed")


if __name__ == "__main__":
    main()
```

Output (verified; deterministic):

```text
== A. feed fan-out: 200k-user sample of a Pareto follower graph, scaled to 500M users;
       1 post and 20 feed reads per user per day
  mean followers 160, median 37, max 2,168,469
strategy                    inbox writes/s  merges/read  timeline reads/s  max fan-out/post
pure push                          923,452          1.0           115,741         2,168,469
hybrid, celeb >= 100k              741,751         32.4         3,749,748            96,769
hybrid, celeb >= 10k               588,091         59.0         6,822,960             9,990
hybrid, celeb >= 1k                408,520         90.0        10,414,366               999
pure pull                                0        160.6        18,584,776                 0

== B. chat: 50,000 messages, 5% lost acks (client resends), random delivery delays
  no idempotency          : duplicates rendered  2983; adjacent misorderings by arrival  15701, by sequence number   0
  client msg IDs + server seq: duplicates rendered     0; adjacent misorderings by arrival  15378, by sequence number   0

== C. notifications: 2M marketing burst + 200/s OTP codes, provider limit 50k/s
  single FIFO   : OTP p50  10.415 s   p99  39.332 s
  priority lanes: OTP p50   0.000 s   p99   0.000 s

== D. live comments: 2M concurrent viewers, 5,000 comments/s
  naive broadcast: 1.0e+10 messages/s; sample 10/s per viewer: 2.0e+07 comments/s delivered in 1.0e+07 frames/s (200 ms batches)
  per edge server with 50k viewers: 250,000 frames/s, ~0.6 Gbps of comment payload at 150 B each

self-test: all assertions passed
```

---

## 17. References for problems 12–15

- Facebook Engineering. *Serving Facebook Multifeed: Efficiency, performance gains through redesign*, 2015.
  Twitter/X Engineering, timeline fan-out posts (⚠ verify the URLs in Folder 10).
- N. Bronson et al. *TAO.* USENIX ATC 2013.
- WhatsApp Engineering / Erlang Factory talks on scaling to millions of connections (⚠ verify).
- Signal. *The Signal Protocol* (Double Ratchet, X3DH); sender keys for groups.
- Slack Engineering. *Real-time Messaging*, 2023, and *Flannel: An Application-Level Edge Cache to Make Slack Scale*,
  2017.
- Meta Engineering. *Live video comments and reactions at scale* (⚠ verify the title). LinkedIn Engineering. *Instant
  Messaging at LinkedIn: Scaling to Hundreds of Thousands of Persistent Connections on One Machine*, 2016.
