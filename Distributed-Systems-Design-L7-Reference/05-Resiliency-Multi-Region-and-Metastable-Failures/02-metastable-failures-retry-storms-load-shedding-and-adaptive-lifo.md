# Metastable Failures, Retry Storms, Load Shedding, and Adaptive LIFO

> **Folder 05 · File 02** of the Distributed Systems & System Design L7 Reference.
> **Prerequisites:**
> - [Folder 01 file 01 §6.5–6.6](../01-First-Principles-Physics-and-L5-L6-L7-Rubric/01-l5-vs-l6-vs-l7-interview-evaluation-rubric-and-signals.md#66-littles-law-and-the-metastability-preview)
>   (queueing knees, Little's law);
> - [Folder 04 file 02](../04-Networking-Edge-Caching-and-Global-Traffic-Routing/02-distributed-caching-tao-lease-tokens-thundering-herds-and-hotkey-salting.md)
>   (cache cold start).
>
> **Listing:** `metastability_sim.py` applies a 10-second capacity drop to a 1,000 req/s server under 700 req/s of
> load, with timeouts and retries. It then tests six designs for recovery: naive, backoff, retry budget,
> deadline-aware dropping, adaptive LIFO + CoDel, and all combined. The output is deterministic.

---

## 0. The definition

Bronson, Aghayev, Charapko & Zhu (HotOS 2021) gave the name to the outage class that every large operator knows.

A **metastable failure** is a state in which:
1. a **trigger** (a load spike, a slow dependency, a cache flush, a GC storm) pushes a system out of its stable
   region;
2. a **sustaining effect**, a feedback loop *inside the system*, keeps it degraded **after the trigger is gone**.

| State | Meaning |
|---|---|
| **Stable** | Absorbs perturbations and returns |
| **Vulnerable** | Stable now, but a big enough trigger would tip it. Most efficiently run systems live here: high utilization, aggressive retries, caches load-bearing |
| **Metastable** | Degraded and self-sustaining; only an external intervention (shedding load, a restart, blocking traffic) restores it |

Huang et al. (OSDI 2022) analyzed real incidents from public post-mortems. They found the sustaining effects
dominated by **retry policies**, followed by look-aside cache failures, slowdowns that cause work amplification, and
link imbalance (⚠ verify the proportions).

**The L7 point:** you cannot test your way out of a metastable failure at normal load. Only designs that *bound the
sustaining loop* make the system recover by itself.

---

## 1. The mechanism, from first principles

1. A server with capacity μ receives load λ < μ. It is stable.
2. A trigger cuts capacity to μ' < λ for a while. The queue grows at λ − μ'.
3. Once queueing delay exceeds the client timeout T, **every request the server completes has already been abandoned
   by its client**. Goodput is 0, even though the server is at 100% CPU.
4. Abandoned clients **retry**. With R retries, offered load climbs toward λ(1 + R).
5. When the trigger ends and capacity returns to μ: if λ(1 + R) > μ, or the backlog of dead work is large, the queue
   *never drains*. The system is metastable.

```
 goodput
   ▲          trigger
 λ ┤────────┐       ┌ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─  stable design: returns to λ
   │        │       │
   │        └───────┘
 0 ┤                └─────────────────────────────  metastable: retries + dead work keep goodput ≈ 0
   └──────────────────────────────────────────────► time
            t=10s   t=20s (trigger ends)
```

---

## 2. The simulation (§ output)

Setup:
- capacity 1,000 req/s, 700 req/s of first attempts;
- from t = 10–20 s, capacity drops to 400 req/s;
- clients time out after 1 s and retry up to 3 times.

| Design | Goodput before | During trigger | At t = 40–60 s | Wasted work after | Queue at 60 s | Recovered after trigger ends |
|---|---|---|---|---|---|---|
| Naive FIFO, 3 immediate retries | 719 | 103 | **0** | 1,000/s | 87,385 | **never** |
| + exponential backoff, full jitter | 719 | 103 | **0** | 1,000/s | 87,737 | **never** |
| + retry budget (10% of first attempts) | 719 | 103 | 693 | 0 | 0 | 11 s |
| + deadline-aware dropping | 719 | **400** | 693 | 0 | 0 | **0 s** |
| + adaptive LIFO + CoDel (5 ms) | 719 | 398 | 693 | 0 | 0 | **0 s** |
| Budget + deadline + LIFO/CoDel | 719 | 394 | 693 | 0 | 0 | **0 s** |

What each row teaches:

1. **Naive: textbook metastability.**
   - During the trigger, goodput is 103 req/s, while the server is busy serving requests whose clients have already
     left.
   - After the trigger, goodput stays at **zero for 40 seconds and counting**, with the server at full capacity
     (1,000 req/s of wasted work).
   - The queue holds 87k dead requests.
2. **Backoff with jitter does not fix it.**
   - Backoff *spreads* retries in time but does not reduce their *number*, so the offered load still exceeds
     capacity.
   - Jitter prevents synchronized waves; it is necessary, not sufficient.
   - This is the most common misconception in retry design.
3. **A retry budget bounds the sustaining loop.** Retries are capped at 10% of first attempts (λ × 1.1 = 770 < 1,000),
   so the system *must* drain once capacity returns. It takes 11 s here to clear the backlog.
4. **Deadline-aware dropping eliminates wasted work.**
   - The server skips requests whose client has already given up. Clients send the deadline, as gRPC does with
     `grpc-timeout`.
   - Goodput during the trigger rises to the full degraded capacity (400), and recovery is immediate.
5. **Adaptive LIFO + CoDel.**
   - Under overload, serve the *newest* request first, since it is the one whose client is still waiting.
   - Shed requests that have queued longer than a small target.
   - Same effect as deadline-awareness, without needing client deadlines. Facebook described this in *Fail at Scale*
     (Maurer, ACM Queue 2015): adaptive LIFO combined with a CoDel-style controlled queue timeout.

---

## 3. The toolbox, in the order to apply it

### 3.1 Retries: bound them

| Rule | Why | Concrete |
|---|---|---|
| Retry only idempotent operations and retryable errors | Non-idempotent retries cause duplicate effects; non-retryable errors (4xx, validation) never succeed | Classify errors; idempotency keys (Folder 03 file 03) |
| **Retry budget** | Bounds amplification regardless of failure pattern | Token bucket: each request earns 0.1 tokens, each retry costs 1, giving ≤ 10% extra load. gRPC retry throttling (`maxTokens`, `tokenRatio`) and Envoy retry budgets implement this |
| **Retry at one layer only** | Retries multiply across layers: 3 retries at each of 5 layers = 4⁵ = **1,024×** load on the bottom service | Retry at the edge (or the layer that owns the user's intent); inner layers fail fast |
| Exponential backoff + **full jitter** | Avoids synchronized retry waves (AWS Architecture Blog, 2015) | `sleep = random(0, min(cap, base · 2^attempt))` |
| **Deadline propagation** | Lets every layer skip work the client no longer wants | Absolute deadline in headers; each hop subtracts elapsed time; servers check before starting work |
| **Hedging only with a budget** | Hedges are retries on a timer | ≤ 5% extra (Folder 01 file 01 §6.4) |

### 3.2 Queues: keep them short, and favor live work

| Mechanism | What it does | Note |
|---|---|---|
| **Bounded queues** | Reject quickly instead of queueing beyond the timeout | Queue capacity ≤ (timeout × service rate), by Little's law |
| **CoDel** (Nichols & Jacobson 2012) | If the *minimum* sojourn time over an interval (100 ms) exceeds a target (5 ms), drop or shed | Distinguishes a standing queue (bad) from a burst (fine) |
| **Adaptive LIFO** | FIFO normally; LIFO when the queue is standing | Newest requests are the ones still wanted; old ones are likely abandoned |
| **Deadline checks at dequeue** | Drop expired work for free | Requires deadlines from clients |
| **Fair queueing per tenant** | One tenant's backlog doesn't delay others | Combine with blast-radius isolation (file 01) |

### 3.3 Admission control and load shedding

- **Server-side concurrency limits.** Cap in-flight requests at the level where latency starts to rise. Adaptive
  algorithms find that level automatically:
  - **Netflix concurrency-limits:** Vegas, Gradient2, AIMD;
  - **Envoy adaptive concurrency filter** (gradient-based).

  The Vegas-style idea, from TCP Vegas:

  $$\text{limit}_{new} = \text{limit} \cdot \frac{\text{RTT}_{min}}{\text{RTT}_{sample}} + \text{queue allowance}$$

  The limit shrinks when latency rises above the no-load baseline.
- **Client-side adaptive throttling** (Google SRE book, *Handling Overload*). Each client tracks `requests` and
  `accepts` over a window and rejects locally with probability

  $$p_{reject} = \max\left(0,\ \frac{\text{requests} - K \cdot \text{accepts}}{\text{requests} + 1}\right), \quad K \approx 2$$

  Overloaded backends are thus protected *before* requests reach them.
- **Priority / criticality shedding.** Requests carry a criticality, and servers shed from the bottom up as they
  approach their limits. Google's SRE book describes CRITICAL_PLUS, CRITICAL, SHEDDABLE_PLUS and SHEDDABLE. In
  product terms:
  - checkout > browse > recommendations > prefetch;
  - interactive > batch;
  - retries < first attempts.
- **Brownouts / graceful degradation.** Turn off expensive features (personalization, high-resolution images, search
  suggestions) before shedding core requests (file 03).

### 3.4 Breakers and their pitfalls

- A **circuit breaker** (closed → open on an error rate → half-open probe → closed) stops calls to a failing
  dependency, giving it room to recover and giving callers fast failures.
- **Pitfall 1:** breakers per *dependency* in a fleet of thousands of callers cause synchronized open and close, and
  thundering re-probes. Use jittered half-open probes.
- **Pitfall 2:** a breaker on a *degraded* dependency can shift load to a fallback that isn't sized for it, moving
  the failure. The AWS Builders' Library argues for avoiding fallback paths that aren't exercised in normal
  operation.

---

## 4. Other sustaining effects (and their specific cures)

| Sustaining effect | Loop | Cure |
|---|---|---|
| **Retry storm** | Timeouts → retries → more load → more timeouts | Retry budgets, deadlines, single-layer retries |
| **Cold cache** (look-aside) | Cache lost → DB overloaded → slow fills → cache stays cold | DB admission control; warm from a peer; SWR; gradual traffic ramp (Folder 04 file 02) |
| **Connection storms** | Timeouts → reconnects → TLS handshakes (CPU) → more timeouts | Connection pooling with limits; jittered reconnect; session resumption |
| **GC death spiral** | High load → more allocation → longer GC → longer queues → more live objects | Bounded queues, shedding, heap headroom |
| **Autoscaling lag + cold starts** | New instances arrive cold (JIT, caches) and fail health checks under load | Pre-warming; slow-start weights at the LB; scale on leading indicators |
| **Failover storms** | Health checks fail under load → instances removed → survivors overloaded | Fail-open health checking; capped ejection (Folder 04 file 01 §3.3) |
| **Work amplification on slow paths** | Slower DB → longer transactions → more lock contention → slower DB | Statement timeouts; shedding before the DB; short transactions |

---

## 5. The listing

```python
"""metastability_sim.py - a trigger, a sustaining loop, and the mechanisms that break it (Folder 05, file 02).

A server with capacity 1,000 req/s receives 700 req/s of first attempts. From t=10 s to t=20 s a trigger (a slow
dependency, a GC storm) cuts capacity to 400 req/s. Clients time out after 1 s and retry up to 3 times. After the
trigger ends, does goodput return to 700 req/s?
Variants: naive FIFO; exponential backoff with jitter; a 10% retry budget; deadline-aware dropping (don't serve
requests whose client already gave up); adaptive LIFO + CoDel-style shedding (Facebook); and the combination.
Standard library only; seeded, deterministic. Time step 1 ms.
"""
import collections
import heapq
import random

CAP_NORMAL, CAP_TRIGGER = 1.0, 0.4        # requests per ms
RATE = 0.7                                # first attempts per ms
TIMEOUT = 1000                            # ms
MAX_RETRIES = 3
T_END = 60_000


def run(variant: dict, seed: int = 21) -> dict:
    rng = random.Random(seed)
    queue: collections.deque = collections.deque()     # (enqueue_ms, deadline_ms, req_id)
    timers: list = []                                   # (deadline, req_id, attempt): client-side timeouts
    pending: list = []                                  # (enter_ms, req_id, attempt): retries waiting to be sent
    attempts: dict = {}
    done: set = set()
    budget = 0.0                                        # retry tokens (retry-budget variant)
    next_arrival = rng.expovariate(RATE)
    next_id = 0
    credit = 0.0
    secs = T_END // 1000
    goodput, wasted, first, qlen = [0] * secs, [0] * secs, [0] * secs, [0] * secs
    last_empty = 0
    for now in range(T_END):
        sec = now // 1000
        while next_arrival <= now:                      # new logical requests
            rid, next_id = next_id, next_id + 1
            attempts[rid] = 1
            queue.append((now, now + TIMEOUT, rid))
            heapq.heappush(timers, (now + TIMEOUT, rid, 1))
            first[sec] += 1
            if variant.get("budget"):
                budget = min(budget + variant["budget"], 50.0)    # each first attempt earns 0.1 retry tokens
            next_arrival += rng.expovariate(RATE)
        while timers and timers[0][0] <= now:           # client-side timeout -> maybe retry
            _, rid, att = heapq.heappop(timers)
            if rid in done or att != attempts[rid] or att > MAX_RETRIES:
                continue
            if variant.get("budget"):
                if budget < 1:
                    continue                            # budget exhausted: fail fast instead of retrying
                budget -= 1
            delay = int(rng.uniform(0, min(8000, 100 * 2 ** att))) if variant.get("backoff") else 0  # full jitter
            attempts[rid] = att + 1
            heapq.heappush(pending, (now + delay, rid, att + 1))
        while pending and pending[0][0] <= now:          # retries enter the queue
            _, rid, att = heapq.heappop(pending)
            if rid in done:
                continue
            queue.append((now, now + TIMEOUT, rid))
            heapq.heappush(timers, (now + TIMEOUT, rid, att))
        credit += CAP_TRIGGER if 10_000 <= now < 20_000 else CAP_NORMAL
        if not queue:
            last_empty = now
        lifo = variant.get("lifo") and now - last_empty > 100     # queue non-empty for >100 ms: overloaded
        while credit >= 1 and queue:
            enq, deadline, rid = queue.pop() if lifo else queue.popleft()
            if rid in done:
                continue                                          # duplicate of an already-answered request
            if variant.get("deadline") and now >= deadline:
                continue                                          # client gave up: skip the work
            if lifo and variant.get("codel") and now - enq > 5:
                continue                                          # CoDel-style: shed work queued > 5 ms
            credit -= 1
            if now <= deadline:
                done.add(rid)
                goodput[sec] += 1
            else:
                wasted[sec] += 1                                  # served, but nobody was waiting
        credit = min(credit, 1.0)
        if now % 1000 == 999:
            qlen[sec] = len(queue)
    recovered = next((s for s in range(20, secs) if goodput[s] >= 0.95 * first[s]), None)
    return {"before": sum(goodput[2:10]) / 8, "during": sum(goodput[10:20]) / 10,
            "after": sum(goodput[40:60]) / 20, "wasted_after": sum(wasted[40:60]) / 20, "queue_end": qlen[-1],
            "recovered_s": None if recovered is None else recovered - 20}


VARIANTS = {
    "naive FIFO, 3 immediate retries": {},
    "+ exponential backoff, full jitter": {"backoff": True},
    "+ retry budget (10% of first attempts)": {"budget": 0.1},
    "+ deadline-aware dropping": {"deadline": True},
    "+ adaptive LIFO + CoDel (5 ms)": {"lifo": True, "codel": True},
    "budget + deadline + LIFO/CoDel": {"budget": 0.1, "deadline": True, "lifo": True, "codel": True},
}


def main() -> None:
    print("capacity 1,000 req/s; first attempts 700 req/s; trigger t=10-20 s cuts capacity to 400 req/s;")
    print("client timeout 1 s, up to 3 retries. goodput = answers delivered before the client's deadline (req/s)")
    print(f"{'variant':<40} {'before':>7} {'during':>7} {'t=40-60s':>9} {'wasted':>7} {'queue@60s':>10} "
          f"{'recovered after':>16}")
    res = {}
    for name, v in VARIANTS.items():
        r = run(v)
        res[name] = r
        rec = "never" if r["recovered_s"] is None else f"{r['recovered_s']} s"
        print(f"{name:<40} {r['before']:>7.0f} {r['during']:>7.0f} {r['after']:>9.0f} "
              f"{r['wasted_after']:>7.0f} {r['queue_end']:>10} {rec:>16}")

    naive = res["naive FIFO, 3 immediate retries"]
    assert naive["before"] > 650 and naive["after"] < 100 and naive["recovered_s"] is None
    for name in ("+ retry budget (10% of first attempts)", "budget + deadline + LIFO/CoDel"):
        assert res[name]["after"] > 650 and res[name]["recovered_s"] is not None, name
    print("\nself-test: all assertions passed")


if __name__ == "__main__":
    main()
```

Output (verified; deterministic):

```text
capacity 1,000 req/s; first attempts 700 req/s; trigger t=10-20 s cuts capacity to 400 req/s;
client timeout 1 s, up to 3 retries. goodput = answers delivered before the client's deadline (req/s)
variant                                   before  during  t=40-60s  wasted  queue@60s  recovered after
naive FIFO, 3 immediate retries              719     103         0    1000      87385            never
+ exponential backoff, full jitter           719     103         0    1000      87737            never
+ retry budget (10% of first attempts)       719     103       693       0          0             11 s
+ deadline-aware dropping                    719     400       693       0          0              0 s
+ adaptive LIFO + CoDel (5 ms)               719     398       693       0          0              0 s
budget + deadline + LIFO/CoDel               719     394       693       0          0              0 s

self-test: all assertions passed
```

---

## 6. Testing for metastability

- **Load test beyond capacity, then remove the overload.** The pass criterion is *recovery without intervention*
  within a bound, not just surviving the peak.
- **Inject the triggers in production-like environments:**
  - dependency latency (not just errors);
  - a 50% capacity loss;
  - a cache flush;
  - a GC pause.
- **Measure the sustaining loop's gain:** the retry amplification factor (attempts ÷ first attempts) and wasted work
  (served-after-deadline ÷ served). Alert when these leave their normal band. They are **leading indicators** of
  metastability.
- **Write runbooks for breaking the loop**, for when it happens anyway:
  1. shed load at the edge (block a fraction or a tier);
  2. disable retries via a dynamic flag;
  3. drain queues;
  4. ramp traffic back in steps.

  Practice them in game days.

---

## 7. L5 vs L6 vs L7

| Topic | L5 (Senior) | L6 (Staff) | L7 (Principal) |
|---|---|---|---|
| Retries | "Retry 3 times with backoff" | Exponential backoff + jitter; idempotency; retry only on retryable errors | Retry budgets and single-layer retries; proves backoff alone doesn't prevent metastability (goodput 0 vs 693 with a budget) |
| Overload | "Autoscale" | Rate limits, circuit breakers, timeouts | Deadline propagation, adaptive LIFO + CoDel, adaptive concurrency limits, criticality-based shedding, client-side throttling |
| Recovery | "Restart the service" | Runbooks | Designs that recover *without* intervention; amplification and wasted-work SLIs as leading indicators; overload-recovery tests |
| Theory | — | Queueing intuition | Trigger vs sustaining effect; stable, vulnerable and metastable states; the gain of the feedback loop as the design target |

---

## 8. Bar-raiser probing chains

### Chain A: "A 30-second database slowdown caused a 2-hour outage."

1. **L5:** "The database was overloaded; add capacity."
2. **Probe:** "The DB recovered in 30 seconds." **L6:** "The app tier kept retrying and the queues filled with
   timed-out requests: a retry storm."
3. **Probe:** "Design it so the system recovers on its own." **L7:**
   - "Bound the sustaining loop at three points:
     1. a retry budget of 10% at the single retrying layer (the edge);
     2. deadlines propagated to the DB layer, so expired work is dropped before it hits the DB;
     3. adaptive LIFO + CoDel in the app's request queues."
   - "In the simulation, that's goodput of 0 forever → full goodput 0 s after the trigger ends."
   - Add SLIs: retry amplification and served-after-deadline.

### Chain B: "We added exponential backoff with jitter. Are we safe from retry storms?"

1. **L5:** "Yes."
2. **Probe:** "What's the total number of retries during an outage?" **L6:** "Still up to 3 per request; backoff
   spreads them out."
3. **Probe:** "So?" **L7:**
   - "So the offered load is still up to 4× under sustained failure, and the system can stay overloaded after
     recovery. Backoff changed the shape, not the volume."
   - The simulation shows backoff alone never recovers.
   - "Add a budget (token bucket, ≤ 10%) and fail fast once it's empty."
   - "And make sure inner layers don't also retry. Retries multiply: 4⁵ = 1,024× across 5 layers."

### Chain C: "Our service handles 10k req/s. How should it behave at 30k?"

1. **L5:** "Autoscale to 30k."
2. **Probe:** "Autoscaling takes 5 minutes; the spike lasts 3." **L6:** "Rate-limit at the edge; shed excess with
   429s; keep latency for accepted requests."
3. **Probe:** "Which requests do you shed, and how does the server know it's overloaded?" **L7:**
   - An adaptive concurrency limit detects overload from latency gradients, not CPU.
   - Shed by criticality: checkout and login last, recommendations and prefetch first, retries before first attempts.
   - Client-side adaptive throttling, so clients stop sending what will be rejected.
   - Goal: goodput stays at capacity (~10k) throughout, with p99 for accepted requests intact.
   - "Then validate with an overload-and-recover test: 3× for 3 minutes, then back to 1×; pass = no intervention
     needed."

---

## 9. Invariants checklist

- [ ] Retries are budgeted (≤ ~10%), happen at a single layer, use backoff with full jitter, and only target
      idempotent operations.
- [ ] Deadlines propagate end to end; servers drop expired work before doing it.
- [ ] Queues are bounded (≤ timeout × service rate); standing queues trigger LIFO/CoDel shedding.
- [ ] Adaptive concurrency limits and criticality-based shedding protect every service; clients throttle adaptively.
- [ ] Look-aside caches have a cold-start plan (warmup, SWR, DB admission control).
- [ ] Health checks fail open; ejection is capped.
- [ ] Overload-and-recover tests pass without intervention; amplification and wasted-work SLIs are alerted.

---

## 10. References

- N. Bronson, A. Aghayev, A. Charapko, T. Zhu. *Metastable Failures in Distributed Systems.* HotOS 2021.
- L. Huang et al. *Metastable Failures in the Wild.* OSDI 2022.
- B. Maurer. *Fail at Scale: Reliability in the Face of Rapid Change.* ACM Queue 13(8), 2015 (adaptive LIFO,
  controlled delay).
- K. Nichols, V. Jacobson. *Controlling Queue Delay.* ACM Queue 10(5), 2012 (CoDel).
- Google SRE Book (2016), ch. 21 *Handling Overload*, ch. 22 *Addressing Cascading Failures*.
- M. Brooker. *Exponential Backoff And Jitter*, AWS Architecture Blog, 2015. AWS Builders' Library: *Timeouts,
  retries, and backoff with jitter*; *Using load shedding to avoid overload*; *Avoiding fallback in distributed
  systems*; *Avoiding insurmountable queue backlogs*.
- Netflix TechBlog. *Performance Under Load* (adaptive concurrency limits, 2018); github.com/Netflix/concurrency-limits.
- gRPC documentation: retry throttling, deadlines. Envoy documentation: adaptive concurrency, retry budgets.
