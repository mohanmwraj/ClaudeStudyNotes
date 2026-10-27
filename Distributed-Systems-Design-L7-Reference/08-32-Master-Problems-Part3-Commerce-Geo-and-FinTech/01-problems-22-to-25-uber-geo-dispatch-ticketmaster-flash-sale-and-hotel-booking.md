# Problems 22–25: Uber Geo-Dispatch, Ticketmaster Flash Sale, Airbnb Double-Booking, Food-Delivery ETA

> **Folder 08 · File 01** of the Distributed Systems & System Design L7 Reference: the 32 Master Problems, Part 3
> (Commerce, Geo, FinTech and AI).
> **Listing:** `geo_booking_lab.py` covers:
> - square (geohash-like) vs hexagonal (H3-like) cells for radius queries;
> - greedy vs batched dispatch;
> - flash-sale inventory (naive vs CAS vs escrow);
> - date-range double-booking under snapshot isolation vs room-night rows.
>
> The output is deterministic.

---

## Problem 22: Uber-class real-time geo-indexing and dispatch (S2 vs H3)

### 22.1 Scope, scale and SLAs

| Quantity | Target |
|---|---|
| Active drivers | 5M globally, ~100k–500k in the largest metro at peak |
| Location updates | Every 4 s per driver → **1.25M writes/s** globally |
| Ride requests | ~50k/s peak globally; ~2–5k/s per large city |
| Dispatch latency | Offer to a driver within ~1–2 s of request |
| Index freshness | Driver position ≤ 4–8 s old |

**Capacity math.**
- Location updates are **write-dominated and ephemeral**: no durability needed beyond seconds.
- 1.25M/s × ~100 B = 125 MB/s of updates, held in RAM in a **city-sharded** in-memory geo index (replicated ×2 for
  failover).
- Durable trip state is a separate, much lower-rate path.

### 22.2 Cells: S2 vs H3 (§A of the output)

| | Square cells (geohash/S2-like) | Hexagonal cells (H3) |
|---|---|---|
| Neighbor distances | 4 edge neighbors at s, 4 corner neighbors at s√2 | **All 6 neighbors equidistant** |
| Radius query (1 km, 0.5 km² cells, 100k drivers in 40×40 km) | Examines **782** drivers per query, 25.0% within radius | Examines **594**, 33.0% within radius |
| Recall | 100% | 100% |
| Hierarchy | S2: exact containment (each cell has 4 children) | H3: aperture-7, approximate containment (children don't exactly tile parents) |
| Typical use | S2: geometry and coverage (Google, many DBs); geohash: prefix-searchable strings | H3: uniform analytics and pricing grids, k-ring neighborhoods (Uber) |

- **Hexagons approximate circles better.** For the same cell area and full recall, a k-ring examines ~24% fewer
  candidates.
- Hexagons also give **uniform adjacency**, which matters for *analytics*: surge pricing and demand forecasting
  smooth over neighbors, and square grids bias diagonal neighbors.
- S2's exact hierarchy is better for **geometric containment** (polygons, geofences, region coverings).
- **Many systems use both:** H3 for marketplace aggregation, S2 or R-trees for geometry.

### 22.3 Schema and partition key

```
driver_location (in-memory, per city shard):  driver_id → {lat, lng, cell_res9, heading, status, ts}
cell index:  (city, cell_res9) → set(driver_ids available)       updated on cell change (most updates stay in cell)
supply/demand aggregates: (city, cell_res7, minute) → counts      (stream-computed, for surge/ETA models)
trips (durable, OLTP):  trip_id → state machine; partition hash(trip_id); rider/driver secondary indexes
partition: by CITY (geofence) → each city is a cell (Folder 05) with its own dispatch + index; cross-city trips rare
```

### 22.4 Architecture and paths

```
 driver app ──(4 s, UDP/QUIC/WebSocket)──► location gateway ─► city shard: update driver record + cell index
 rider request ─► dispatch service (city shard):
      candidates = k-ring(rider cell) available drivers → ETA per candidate (road-network ETA service, cached
      tiles) → BATCH over a short window (1–2 s) → assignment (min total ETA / weighted) → offer to driver
      → accept/decline/timeout → re-offer
 stream: location + trip events → Kafka → supply/demand per cell → surge pricing, forecasting, ETA model features
 control: city configs (geofences, dispatch params, surge rules) versioned & staged per city
 failure: city shard leader dies → standby with replicated in-memory index (or rebuild from the last 8 s of updates)
```

### 22.5 The core L7 bottleneck: matching quality vs latency, and the write firehose

1. **Greedy vs batched matching** (§B: 40 riders × 60 drivers per 2-second window):
   - Greedy (first come, nearest driver): mean pickup **0.99 km**, p95 2.34 km.
   - Batched (globally shortest pairs first): mean **0.94 km** (−5%), but **p95 2.53 km (worse)**.
   - **Batching improves the total but can hurt the unlucky.** The objective must encode what the marketplace
     values: min total ETA, plus a penalty on max wait and fairness for long-waiting riders. That is why production
     matching solves a weighted bipartite assignment (Hungarian / auction algorithms, min-cost flow) with business
     terms, not "nearest driver".
   - The batch window trades latency (seconds of waiting) against efficiency.
2. **Write firehose:** 1.25M updates/s.
   - Keep positions in memory, sharded by city.
   - Update the cell index only on a cell change (most 4-s updates stay in the same res-9 cell).
   - Never write positions to the durable store synchronously. Trip-relevant positions (for billing and safety) go
     to a log asynchronously.
3. **ETA is a service, not a formula.** Road-network routing with live traffic; contraction hierarchies precomputed;
   ML correction. Cache ETA by (cell, cell, time bucket) for candidate ranking.

### 22.6 Failure defense

| Failure | Defense |
|---|---|
| City shard failure | Hot standby; driver apps resend location every 4 s, so the index rebuilds itself within one interval |
| Region outage | Cities pinned to a home region with a warm standby region; trips in progress survive via the durable trip store |
| Location update storm (app bug) | Per-driver rate limits; drop stale/out-of-order updates (timestamp check) |
| ETA service slow | Fallback to cached cell-to-cell ETAs; degrade matching quality, not availability |
| Surge feedback loop | Damping and caps on surge changes per interval |

### 22.7 L5 / L6 / L7 and probing chain

| | L5 | L6 | L7 |
|---|---|---|---|
| Design | Geohash + nearest driver | City sharding, in-memory index, k-ring candidates, ETA service, batching | Hex vs square trade-offs (−24% candidates, uniform adjacency); matching objective design (mean vs tail); write path never durable; cities as cells |

1. **Probe:** "Assign the nearest driver." **L5:** "Query drivers within a radius, pick the closest."
2. **Probe:** "Two riders 100 m apart, one driver between them." **L6:** "Batch requests over a short window and
   solve a global assignment."
3. **Probe:** "Batching made the worst pickups worse." **L7:**
   - "Right, min-sum objectives do that; the lab's p95 rose while the mean fell."
   - "Add a convex penalty on individual ETA, or a max-wait constraint, and age-based priority for riders who've
     waited."
   - "Tune the window per city by density: in dense cities a 1 s window captures enough options, and in sparse ones
     batching buys little."
   - "Validate with marketplace A/B tests on completed-trip rate, not just ETA."

---

## Problem 23: Ticketmaster-class flash sale with seat locking

### 23.1 Scope, scale and SLAs

| Quantity | Target |
|---|---|
| Inventory | 50,000 seats per event (assigned seating) or N general-admission units |
| Demand | **400k–10M users** arriving in the first minute (8–200× supply) |
| Correctness | **Zero oversell**; no seat sold twice |
| Fairness | Users served in a defensible order; bots constrained |
| Latency | Seat selection responsive; checkout within a hold window (e.g. 10 min) |

### 23.2 Inventory correctness (§C of the output: 50,000 seats, 400,000 buyers, 200 requests in flight)

| Strategy | Seats sold | **Oversold** | Success rate |
|---|---|---|---|
| Naive read-then-write (check availability, then write) | 49,984 | **210** | 12.5% |
| **Per-seat compare-and-set** (conditional write: free → held) | 49,982 | **0** | 12.5% |
| **Escrow shards** (general admission: 64 counters, atomic decrement) | **50,000** | **0** | 12.5% |

- **Read-then-write oversells under concurrency** (Folder 01 file 03 §3: lost update / write skew). Any design whose
  correctness relies on "check, then write" without an atomic conditional write is wrong.
- **Per-seat CAS** (`UPDATE seats SET state='HELD', holder=? WHERE seat_id=? AND state='FREE'`, or a DynamoDB
  condition expression) makes each seat a single-row, linearizable decision.
- **General admission doesn't need per-seat rows.** Pre-split the count into escrow shards and decrement atomically.
  Contention spreads across 64 keys instead of one hot counter, and all 50,000 units sell.

### 23.3 Schema and partition key

```
seats:  (event_id, seat_id) → {state: FREE|HELD|SOLD, holder, hold_expires, version}   partition: hash(event_id, section)
holds:  hold_id → {user, seats[], expires}   (TTL index → expired holds return seats via CAS HELD→FREE)
GA inventory: (event_id, shard k) → remaining                                          (escrow)
queue:  (event_id) → waiting-room tokens: position, admitted_at, signed token (JWT) with expiry
orders: order_id → payment state machine (problem 26)
```

### 23.4 Architecture and paths

```
 users ─► CDN-hosted WAITING ROOM (static page + queue service): assigns random/arrival-order positions at the
          on-sale moment; ADMITS at a controlled rate R (sized to backend capacity) with signed admission tokens
        ─► seat map (cached availability, eventually consistent; ~1 s stale OK for display)
        ─► HOLD: CAS on chosen seats (all-or-nothing for a multi-seat hold via a transaction within one partition)
        ─► checkout: payment (idempotent) → CAS HELD→SOLD (holder must match, hold unexpired)
 expiry: hold TTL scanner → CAS HELD→FREE (only if still HELD by that hold) → seats reappear
 bots: proof-of-work/CAPTCHA at queue entry, per-account/payment-instrument limits, device fingerprinting
```

### 23.5 The core L7 bottleneck: admission, not the database

The inventory decision is easy once it is a CAS. The hard part is that **10M users arrive at once**, and every
backend (seat map, holds, payments) would melt. The answer is the **virtual waiting room**, which is admission
control (Folder 05 file 02) made into a product:
- static, CDN-served, effectively infinitely scalable;
- an explicit, fair queue;
- a controlled admission rate to the transactional tier.

Admission rate ≈ (backend throughput) ÷ (requests per admitted user).

**Holds are inventory too.** If 30% of holders abandon, a hold without a TTL removes 30% of inventory from sale.
Holds must have short TTLs, CAS-based release, and visible countdowns.

### 23.6 Failure defense

| Failure | Defense |
|---|---|
| Thundering herd at on-sale | Waiting room with controlled admission; pre-warmed caches; pre-provisioned capacity (scheduled event) |
| Hot partition (one event's seat rows) | Partition seats by (event, section); GA escrow shards; holds batched per user |
| Payment provider slow | Hold TTL extended once on payment-in-progress; idempotent retries |
| Bot swarms | Queue-entry challenges, per-identity limits, post-sale cancellation of bot orders |
| Double sale through retries | CAS + idempotency keys; seat state machine allows only FREE→HELD→SOLD and HELD→FREE |

### 23.7 L5 / L6 / L7 and probing chain

| | L5 | L6 | L7 |
|---|---|---|---|
| Design | Lock seat rows in a transaction | CAS holds with TTL; idempotent checkout; caching the seat map | Waiting room as admission control; escrow for GA; holds as inventory; bot economics; scheduled-event capacity |

1. **Probe:** "SELECT the seat; if free, UPDATE it." **L5:** "Inside a transaction."
2. **Probe:** "Under READ COMMITTED, two buyers both see it free." **L6:** "Use a conditional update or SELECT … FOR
   UPDATE; the lab shows 210 oversold seats with read-then-write."
3. **Probe:** "Correctness is fixed; now 10M users arrive in 60 s." **L7:**
   - "The database is not the bottleneck to solve. Admission is."
   - "A CDN-served waiting room gives positions at on-sale and admits at the rate the hold/checkout tier sustains."
   - "Holds expire in minutes; seat-map reads come from a cache."
   - "The transactional tier sees a smooth, bounded load, and fairness becomes a product property we can explain."

---

## Problem 24: Airbnb/Booking.com double-booking prevention

### 24.1 Scope, scale and SLAs

| Quantity | Target |
|---|---|
| Listings | 10M properties; availability calendars per night |
| Searches | 100k QPS (availability is read-mostly) |
| Bookings | ~1k–10k/s peak |
| Correctness | **Never** two confirmed bookings for overlapping nights of the same unit |
| Sync | Calendars synchronized with external channels (iCal, channel managers) |

### 24.2 The invariant and why snapshot isolation breaks it (§D of the output)

"Check for an overlapping booking, then insert" is a **predicate write skew**. Under snapshot isolation (PostgreSQL
REPEATABLE READ, Oracle "SERIALIZABLE"), two concurrent transactions can't see each other's inserts (Folder 01 file
03 §3.3).

| Design (1 room, 365 nights, 20,000 requests, 8 concurrent transactions) | Accepted | **Double bookings** |
|---|---|---|
| Check-then-insert under SI | 176 | **48** |
| **One row per (room, night) + UNIQUE constraint** | 173 | **0** |

### 24.3 Schema and partition key

```
availability: (listing_id, night_date) → {state: OPEN|HELD|BOOKED, booking_id, version}   ← one row per night
              PRIMARY KEY (listing_id, night_date)  → a booking = insert/CAS of N rows in ONE transaction
              partition: hash(listing_id) → all nights of a listing on one shard (single-shard transaction)
bookings:     booking_id → {listing, check_in, check_out, guest, state machine, payment ref}
search index: listing → bitmap of open nights (denormalized, eventually consistent, refreshed via CDC)
alternatives: PostgreSQL EXCLUDE USING gist (listing_id WITH =, stay WITH &&) on a daterange column
```

**Materializing the conflict** turns a predicate check into **unique-key conflicts on concrete rows**. Every database
enforces those correctly under any isolation level. Keeping all of a listing's nights on one partition makes the
multi-row booking a **single-shard transaction**, with no 2PC.

### 24.4 Architecture and paths

```
 search ─► search index (open-night bitmaps, ~seconds stale) ─► listing page (cached)
 book   ─► booking service: BEGIN; CAS/INSERT nights (listing, d) for d in [in, out) → all succeed or abort;
           create booking (HELD) ; COMMIT → payment (idempotent) → booking CONFIRMED; nights BOOKED
           failure/timeout → release nights (CAS HELD→OPEN) via saga compensation
 channels ─► external calendar sync (iCal polling, channel-manager APIs): imported blocks are writes to the same
           night rows; conflicts (an external booking lands on a held night) → resolution policy + host notification
```

### 24.5 The core L7 bottleneck: external systems and the saga

The database invariant is solved by night rows. The remaining risk is **outside the database**:
- **Payment** is a saga step (hold nights → charge → confirm). It needs compensations, idempotency, and a pivot: once
  charged, confirm or refund.
- **Channel managers and iCal sync** are asynchronous and lossy. A host listed on three platforms can be booked on two
  before sync. That is a multi-leader conflict (Folder 02 file 02 §3) with *physical* consequences. The mitigations:
  - shorter sync intervals;
  - "instant book" only for listings with API-based (push) sync;
  - conflict resolution with compensation (rebooking support, penalties) as the business backstop.
- **Search staleness** shows rooms that were just booked. That's acceptable (the booking CAS is authoritative), but
  measure "search-to-book conflict rate" as an SLI.

### 24.6 Failure defense

| Failure | Defense |
|---|---|
| Concurrent bookings | Night rows + UNIQUE/CAS; single-shard transactions |
| Payment timeout after nights held | Hold TTL; saga compensation releases nights; idempotent payment retry |
| External double booking | Push-sync partners; conflict detection on import; compensation workflow |
| Hot listing (viral property) | All its nights on one shard. Fine: bookings per listing are low; reads are served from cache/search |
| Search index lag | CDC lag SLI; booking path always re-checks authoritatively |

### 24.7 L5 / L6 / L7 and probing chain

| | L5 | L6 | L7 |
|---|---|---|---|
| Design | Check availability then insert in a transaction | Recognizes write skew; SERIALIZABLE or locks; exclusion constraints | Materialized night rows (48 → 0), single-shard transactions by listing, payment saga, channel-sync conflicts as multi-leader replication |

1. **Probe:** "We use REPEATABLE READ and check for overlaps." **L5:** "The snapshot is consistent."
2. **Probe:** "Two guests book overlapping dates concurrently." **L6:** "Write skew: neither sees the other's insert.
   Use SERIALIZABLE, or lock the listing row."
3. **Probe:** "SERIALIZABLE aborts too much at peak, and a listing lock serializes unrelated dates." **L7:**
   - "One row per night: concurrent bookings of *different* dates don't conflict at all, and overlapping ones
     conflict deterministically on a unique key. There are no false-positive aborts like SSI's."
   - "Partition by listing so it's a single-shard transaction."
   - "Then the real risk moves to channel sync, which we treat as a replication-conflict problem with a business
     compensation path."

---

## Problem 25: Food-delivery ETA and multi-hop dispatch (DoorDash/Uber Eats)

### 25.1 Scope, scale and SLAs

| Quantity | Target |
|---|---|
| Orders | 1M/hour at peak dinner in a large market set |
| Parties | Customer, restaurant (prep time), courier (travel) |
| ETA accuracy | p50 error < 3–5 min; the promise shown at checkout drives conversion |
| Dispatch | Assign couriers considering prep time; **batch** multiple orders per courier |

### 25.2 What makes it harder than ride-hailing

- **Three-sided timing.** Delivery time = max(courier arrival at the restaurant, food ready) + travel to the customer.
  Assigning a courier too early wastes courier time waiting at the restaurant; too late makes the food wait (cold
  food). The **prep-time model** (restaurant, items, current load) is as important as routing.
- **Multi-hop batching.** One courier picks up two orders from the same or nearby restaurants: fewer couriers, and
  each order's delivery time grows. This is a vehicle-routing problem with time windows, solved heuristically every
  few seconds (insertion heuristics, local search).
- **ETA is a distribution, not a number.** Quote a quantile (e.g. the p80 promise) and track calibration: the share of
  orders delivered before their quote should match the quoted quantile.

### 25.3 Schema and data flow

```
orders:      order_id → {restaurant, items, placed_at, promised_eta (quantile), state machine}   partition: hash(order_id)
couriers:    in-memory per city shard (as problem 22): location, state, current route (stops)
predictions: prep_time(restaurant, items, load) ; travel(cell, cell, time) ; dropoff_time(address type)
dispatch loop (every ~5–30 s per zone): unassigned orders × available couriers → batch/route optimization
             objective: Σ (lateness penalty + courier idle + food-wait) → assignments → push to courier app
features:    real-time (restaurant queue length, courier density) + historical, served from a feature store (problem 31)
```

### 25.4 The core L7 bottleneck: the optimization loop's latency and its feedback effects

- The dispatch optimizer runs per zone on a fixed cadence (**constant work**, Folder 05 file 03). Its runtime must fit
  the cadence. When demand spikes, degrade to a faster heuristic rather than running late.
- **Feedback loops:** quoted ETAs change demand (long quotes reduce orders), and dispatch changes courier supply
  positions. Model changes must be A/B tested at the market level (switchback experiments), not the user level,
  because of interference.
- **Prep-time prediction drift** (a new menu, a kitchen staffing change) silently degrades ETAs. Use per-restaurant
  error monitoring with online recalibration.

### 25.5 Failure defense

| Failure | Defense |
|---|---|
| Optimizer overrun | Time-boxed optimization with anytime heuristics; fall back to greedy insertion |
| ETA model outage | Cached per-restaurant/per-zone priors; wider quantile quotes |
| Courier app connectivity | Offline-tolerant state machine; idempotent status updates with sequence numbers |
| Restaurant tablet offline | Order acceptance timeouts → auto-call or cancel-and-refund saga |

### 25.6 L5 / L6 / L7 and probing chain

| | L5 | L6 | L7 |
|---|---|---|---|
| Design | Nearest courier at order time | Prep-time-aware assignment, batching, ETA service | ETA quantiles and calibration; time-boxed optimization loops; switchback experiments for marketplace interference |

1. **Probe:** "Assign the nearest courier when the order is placed." **L5:** "Fastest pickup."
2. **Probe:** "The courier waits 20 minutes at the restaurant." **L6:** "Delay assignment until predicted ready time
   minus travel time."
3. **Probe:** "How do you know a change to the dispatch algorithm is better?" **L7:**
   - "User-level A/B is contaminated: treatment and control share couriers."
   - "Run switchback experiments that alternate the algorithm by zone and time window, and measure delivery time,
     lateness vs quote (calibration), courier utilization and cancellation."
   - "Ship only if the market-level metrics improve, because the system is a coupled marketplace, not independent
     requests."

---

## 26. The listing

```python
"""geo_booking_lab.py - geo indexing and dispatch, flash-sale inventory, and double-booking prevention (Folder 08, file 01).

  A. Geo index: square (geohash-like) vs hexagonal (H3-like) cells of equal area for "drivers within r" queries:
     drivers examined per query and the share that are actually within r.
  B. Dispatch: greedy nearest-driver per rider (arrival order) vs batched matching over a 2 s window.
  C. Flash sale: 50,000 seats, 400,000 buyers in a burst: naive read-then-write vs per-seat compare-and-set vs
     escrowed inventory shards (general admission).
  D. Hotel booking: overlapping date ranges under snapshot isolation (check-then-insert) vs one row per room-night
     with a uniqueness constraint.
Standard library only; seeded, deterministic.
"""
import collections
import math
import random


# ---------------------------------------------------------------- A. cells
def square_cell(x: float, y: float, s: float) -> tuple:
    return int(x // s), int(y // s)


def hex_cell(x: float, y: float, size: float) -> tuple:
    """Pointy-top axial coordinates (cube rounding)."""
    q = (math.sqrt(3) / 3 * x - y / 3) / size
    r = (2 / 3 * y) / size
    cx, cz = q, r
    cy = -cx - cz
    rx, ry, rz = round(cx), round(cy), round(cz)
    dx, dy, dz = abs(rx - cx), abs(ry - cy), abs(rz - cz)
    if dx > dy and dx > dz:
        rx = -ry - rz
    elif dy > dz:
        ry = -rx - rz
    else:
        rz = -rx - ry
    return rx, rz


def hex_ring(c: tuple, k: int) -> list:
    q0, r0 = c
    return [(q0 + dq, r0 + dr) for dq in range(-k, k + 1) for dr in range(max(-k, -dq - k), min(k, -dq + k) + 1)]


def geo_index(rng: random.Random, drivers: int = 100_000, city_km: float = 40.0, radius: float = 1.0) -> dict:
    pts = [(rng.uniform(0, city_km), rng.uniform(0, city_km)) for _ in range(drivers)]
    area = 0.5                                                   # km^2 per cell, both schemes
    s = math.sqrt(area)
    hsize = math.sqrt(2 * area / (3 * math.sqrt(3)))             # hexagon circumradius for that area
    sq, hx = collections.defaultdict(list), collections.defaultdict(list)
    for p in pts:
        sq[square_cell(*p, s)].append(p)
        hx[hex_cell(*p, hsize)].append(p)
    res = {"square": [0, 0], "hex": [0, 0]}
    queries = [(rng.uniform(5, 35), rng.uniform(5, 35)) for _ in range(500)]
    ks = math.ceil(radius / s)                                   # (2k+1)^2 block around the query's cell
    kh = 0                                                       # smallest hex k-ring whose inner radius covers r + R
    while (2 * kh + 1) * math.sqrt(3) * hsize / 2 < radius + hsize:
        kh += 1
    for qx, qy in queries:
        cx, cy = square_cell(qx, qy, s)
        cands = [p for i in range(-ks, ks + 1) for j in range(-ks, ks + 1) for p in sq[(cx + i, cy + j)]]
        res["square"][0] += len(cands)
        res["square"][1] += sum(1 for p in cands if math.dist(p, (qx, qy)) <= radius)
        cands = [p for c in hex_ring(hex_cell(qx, qy, hsize), kh) for p in hx[c]]
        res["hex"][0] += len(cands)
        res["hex"][1] += sum(1 for p in cands if math.dist(p, (qx, qy)) <= radius)
    truth = sum(1 for qx, qy in queries for p in pts if math.dist(p, (qx, qy)) <= radius) if drivers <= 100_000 else 0
    return {k: {"examined": v[0] / 500, "precision": v[1] / v[0], "recall": v[1] / truth} for k, v in res.items()}


# ---------------------------------------------------------------- B. dispatch
def dispatch(rng: random.Random, rounds: int = 200) -> dict:
    greedy_d, batch_d, greedy_max, batch_max = [], [], 0.0, 0.0
    for _ in range(rounds):
        drivers = [(rng.uniform(0, 10), rng.uniform(0, 10)) for _ in range(60)]
        riders = [(rng.uniform(0, 10), rng.uniform(0, 10)) for _ in range(40)]
        free = set(range(len(drivers)))
        for r in riders:                                          # greedy: first come, nearest free driver
            d = min(free, key=lambda i: math.dist(drivers[i], r))
            free.remove(d)
            greedy_d.append(math.dist(drivers[d], r))
        pairs = sorted((math.dist(drivers[i], r), i, j) for j, r in enumerate(riders) for i in range(len(drivers)))
        used_d, used_r = set(), set()
        for dist, i, j in pairs:                                  # batched: globally shortest pairs first
            if i not in used_d and j not in used_r:
                used_d.add(i)
                used_r.add(j)
                batch_d.append(dist)
        greedy_max = max(greedy_max, max(greedy_d[-40:]))
        batch_max = max(batch_max, max(batch_d[-40:]))
    return {"greedy_mean": sum(greedy_d) / len(greedy_d), "batch_mean": sum(batch_d) / len(batch_d),
            "greedy_p95": sorted(greedy_d)[int(len(greedy_d) * 0.95)],
            "batch_p95": sorted(batch_d)[int(len(batch_d) * 0.95)]}


# ---------------------------------------------------------------- C. flash sale
def flash_sale(mode: str, rng: random.Random, seats: int = 50_000, buyers: int = 400_000) -> dict:
    sold = [0] * seats                                            # times each seat was sold
    window = 200                                                  # concurrent in-flight requests
    inflight: collections.deque = collections.deque()
    shards = [seats // 64 + (i < seats % 64) for i in range(64)] if mode == "escrow shards" else None
    next_seat = 0
    attempts = successes = 0
    state = [0] * seats                                           # 0 free, 1 sold
    for b in range(buyers):
        attempts += 1
        if mode == "naive read-then-write":
            seat = rng.randrange(seats)
            inflight.append((seat, state[seat]))                  # read now, write later
            if len(inflight) > window:
                s, seen = inflight.popleft()
                if seen == 0:                                     # it LOOKED free when this request read it
                    state[s] = 1
                    sold[s] += 1
                    successes += 1
        elif mode == "per-seat compare-and-set":
            seat = rng.randrange(seats)
            if state[seat] == 0:                                  # CAS(state 0 -> 1) is atomic at the store
                state[seat] = 1
                sold[seat] += 1
                successes += 1
        else:                                                     # escrow: decrement a random shard's counter
            k = rng.randrange(64)
            if shards[k] > 0:
                shards[k] -= 1
                sold[next_seat] += 1
                next_seat += 1
                successes += 1
    oversold = sum(c - 1 for c in sold if c > 1)
    return {"sold": sum(1 for c in sold if c), "oversold": oversold, "success_rate": successes / attempts}


# ---------------------------------------------------------------- D. hotel booking
def booking(mode: str, rng: random.Random, requests: int = 20_000) -> dict:
    """One room, 365 nights; requests for random 1-7 night stays. Transactions overlap in time: each one's snapshot
    misses the commits of the previous `concurrency` transactions (that is what snapshot isolation allows)."""
    concurrency = 8
    committed: list = []                                          # (start, end)
    nights: set = set()
    double = accepted = 0
    for i in range(requests):
        start = rng.randrange(0, 360)
        stay = (start, start + rng.randint(1, 7))
        if mode == "check-then-insert under SI":
            snapshot = committed[:max(0, len(committed) - concurrency)]
            if not any(s < stay[1] and stay[0] < e for s, e in snapshot):
                if any(s < stay[1] and stay[0] < e for s, e in committed):
                    double += 1                                    # overlaps a booking its snapshot could not see
                committed.append(stay)
                accepted += 1
        else:                                                     # rows (room, night) with a UNIQUE constraint
            want = set(range(*stay))
            if not (want & nights):                               # the insert of all rows commits atomically or fails
                nights |= want
                committed.append(stay)
                accepted += 1
    return {"accepted": accepted, "double_bookings": double}


def main() -> None:
    rng = random.Random(22)
    print("== A. 100k drivers in a 40x40 km city; 'drivers within 1 km' with 0.5 km^2 cells")
    gi = geo_index(rng)
    for k, r in gi.items():
        print(f"  {k:<7} cells: examined {r['examined']:7.0f} drivers per query, {r['precision'] * 100:5.1f}% inside "
              f"the radius, recall {r['recall'] * 100:5.1f}%")

    print("\n== B. dispatch: 40 riders x 60 drivers per 2 s window, 10x10 km, 200 windows")
    dp = dispatch(rng)
    print(f"  greedy (first come, nearest driver): mean pickup {dp['greedy_mean']:.2f} km, p95 {dp['greedy_p95']:.2f} km")
    print(f"  batched (globally shortest pairs):   mean pickup {dp['batch_mean']:.2f} km, p95 {dp['batch_p95']:.2f} km")

    print("\n== C. flash sale: 50,000 seats, 400,000 buyers, 200 requests in flight")
    fs = {}
    for mode in ("naive read-then-write", "per-seat compare-and-set", "escrow shards"):
        fs[mode] = flash_sale(mode, rng)
        r = fs[mode]
        print(f"  {mode:<26} seats sold {r['sold']:>6}   oversold {r['oversold']:>6}   "
              f"request success rate {r['success_rate'] * 100:5.1f}%")

    print("\n== D. hotel: 1 room, 365 nights, 20,000 requests, 8 concurrent transactions")
    bk = {m: booking(m, rng) for m in ("check-then-insert under SI", "room-night rows + UNIQUE")}
    for m, r in bk.items():
        print(f"  {m:<30} accepted {r['accepted']:>5}   double bookings {r['double_bookings']:>4}")

    assert gi["hex"]["recall"] > 0.999 and gi["square"]["recall"] > 0.999
    assert gi["hex"]["examined"] < gi["square"]["examined"]
    assert dp["batch_mean"] < dp["greedy_mean"]                    # the tail is NOT guaranteed (see the p95)
    assert fs["naive read-then-write"]["oversold"] > 0
    assert fs["per-seat compare-and-set"]["oversold"] == 0 and fs["escrow shards"]["oversold"] == 0
    assert fs["escrow shards"]["sold"] == 50_000
    assert bk["check-then-insert under SI"]["double_bookings"] > 0 and bk["room-night rows + UNIQUE"]["double_bookings"] == 0
    print("\nself-test: all assertions passed")


if __name__ == "__main__":
    main()
```

Output (verified; deterministic):

```text
== A. 100k drivers in a 40x40 km city; 'drivers within 1 km' with 0.5 km^2 cells
  square  cells: examined     782 drivers per query,  25.0% inside the radius, recall 100.0%
  hex     cells: examined     594 drivers per query,  33.0% inside the radius, recall 100.0%

== B. dispatch: 40 riders x 60 drivers per 2 s window, 10x10 km, 200 windows
  greedy (first come, nearest driver): mean pickup 0.99 km, p95 2.34 km
  batched (globally shortest pairs):   mean pickup 0.94 km, p95 2.53 km

== C. flash sale: 50,000 seats, 400,000 buyers, 200 requests in flight
  naive read-then-write      seats sold  49984   oversold    210   request success rate  12.5%
  per-seat compare-and-set   seats sold  49982   oversold      0   request success rate  12.5%
  escrow shards              seats sold  50000   oversold      0   request success rate  12.5%

== D. hotel: 1 room, 365 nights, 20,000 requests, 8 concurrent transactions
  check-then-insert under SI     accepted   176   double bookings   48
  room-night rows + UNIQUE       accepted   173   double bookings    0

self-test: all assertions passed
```

---

## 27. References for problems 22–25

- Uber Engineering. *H3: Uber's Hexagonal Hierarchical Spatial Index*, 2018; h3geo.org. Google S2 geometry library
  (s2geometry.io).
- Uber Engineering posts on dispatch/matching and DISCO, and on ETA prediction (DeepETA, 2022) (⚠ verify the titles in
  Folder 10).
- Ticketmaster / SeatGeek / Queue-it engineering write-ups on virtual waiting rooms (⚠ verify the URLs).
- PostgreSQL documentation: exclusion constraints (`EXCLUDE USING gist`), range types.
- DoorDash Engineering. *Switchback experiments*, and posts on dispatch optimization and ETA prediction (⚠ verify
  the titles).
