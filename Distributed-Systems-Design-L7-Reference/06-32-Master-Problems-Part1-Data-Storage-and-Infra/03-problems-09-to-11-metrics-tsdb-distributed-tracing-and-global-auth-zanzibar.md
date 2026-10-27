# Problems 9–11: Metrics TSDB (Gorilla), Distributed Tracing, and Global Authorization (Zanzibar)

> **Folder 06 · File 03** of the Distributed Systems & System Design L7 Reference.
> **Listing:** `tsdb_zanzibar_lab.py` covers:
> - a bit-exact Gorilla encoder/decoder (delta-of-delta timestamps, XOR floats);
> - head vs tail trace sampling;
> - Zanzibar checks with userset rewrites, the new-enemy problem with and without zookies, and a Leopard-style
>   flattened group index.
>
> The output is deterministic.

---

## Problem 9: A time-series metrics database (Gorilla / Monarch class)

### 9.1 Scope, scale and SLAs

| Quantity | Target | Note |
|---|---|---|
| Active series | 1 billion (hosts × metrics × label combinations) | **Cardinality is the scaling axis**, not bytes |
| Ingest | 10 s scrape interval → **100M samples/s** | 1e9 / 10 |
| Query | Dashboards: last 1–24 h, p99 < 1 s; alerting: every 10–60 s over recent data | Recent data is ~all of the query load |
| Retention | 15 days raw; 13 months at 1-min/1-h rollups | |
| Availability | Alerting path 99.99% (it pages people about outages, so it must survive them) | |

**Capacity math.**
- Raw samples are 16 B (8 B timestamp + 8 B double). 100M/s × 16 B = 1.6 GB/s → **138 TB/day uncompressed**.
- With **Gorilla compression**: the Facebook paper reports ~1.37 bytes/point on production data, and the lab measures
  0.29–4.53 B/pt on realistic series. At ~1.4 B/pt, **12 TB/day**, and 26 h of hot data fits in RAM across a modest
  cluster. Facebook kept a 26-hour in-memory window. That **12× compression is what makes in-memory TSDBs possible.**
- Index: 1e9 series × ~200 B of labels ≈ 200 GB, held in an inverted index (label → posting list of series IDs).

### 9.2 Gorilla compression (§A of the output)

| Series shape | Bytes/point | Compression vs 16 B | Why |
|---|---|---|---|
| Constant gauge | **0.29** | 55.6× | Delta-of-delta = 0 → 1 bit; XOR = 0 → 1 bit |
| Integer counter | 1.48 | 10.8× | Small XOR windows (same exponent) |
| 2-decimal sensor | 4.53 | 3.5× | Decimal fractions don't compress well in binary floats |
| Random doubles | 8.07 | 2.0× | Only the timestamps compress |

- **Timestamps:** most scrapes are exactly 10 s apart, so delta-of-delta is 0 and costs 1 bit. Occasional jitter
  costs 9–16 bits.
- **Values:** XOR with the previous value. Identical values cost 1 bit. Similar values share sign, exponent and high
  mantissa bits, so only the "meaningful" middle bits are stored, reusing the previous leading/trailing-zero window
  when it fits.
- **Design implications:**
  - Store integers as integers, or scaled integers (cents, milli-units), where possible.
  - Avoid adding random noise to gauges.
  - **Compression is a function of the data**, so capacity plans must use measured bytes/point, not the paper's 1.37.

### 9.3 Schema and partition key

```
series_id = hash(metric_name, sorted labels)            # identity
index:    label=value → posting list of series_ids (roaring bitmaps), per time block
chunks:   (series_id, block_start) → Gorilla-compressed block (2 h), then immutable + persisted to object storage
partition: hash(series_id) % shards for ingest; time blocks for retention; queries fan out to the shards hosting
           matching series (scatter-gather), with per-shard pre-aggregation
Monarch-style: regional "zones" own their data; global query federation pushes aggregation down to zones
```

### 9.4 Architecture and paths

```
 targets ─scrape/push─► ingesters (sharded by series hash; WAL + in-memory head block; replicated ×2–3)
                           │ every 2 h: cut block → compress → upload to object storage (+ index)
 queries ─► query frontend (split by time, cache results, limit cardinality) ─► ingesters (recent) + store gateways
            (historical blocks) ─► merge/aggregate ─► dashboards
 rules/alerts ─► rule evaluators (independent of the query frontend; read recent data from ingesters directly)
 compactor: merges blocks, downsamples (1 min, 1 h), applies retention
 control plane: tenant limits (series, samples/s, label cardinality), shard assignment ring
```

### 9.5 The core L7 bottleneck: cardinality explosions, and the monitoring system's own availability

1. **Cardinality is the denial-of-service vector.**
   - One engineer adds `user_id` as a label, and 10M new series appear in minutes. Memory explodes, ingesters OOM,
     and the monitoring system dies **during the incident it was supposed to observe.**
   - Defenses:
     - per-tenant and per-metric series limits enforced at ingest: reject new series beyond the limit, keep existing
       ones;
     - cardinality dashboards;
     - label allow-lists for high-cardinality dimensions;
     - **exemplars** (a trace ID attached to a sample) instead of per-request labels.
2. **The alerting path must be more available than what it monitors.**
   - Rule evaluation reads only recent, in-memory data.
   - It runs in each failure domain: regional, with **meta-monitoring** from outside the region.
   - It degrades by dropping dashboards before alerts: criticality shedding (Folder 05 file 02 §3.3).
   - Monarch's design keeps data in the zone where it is produced, so a regional outage doesn't blind other regions.
3. **Query fan-out tails.** "Sum over all hosts" touches every shard. Reduce it with:
   - per-shard pre-aggregation;
   - recording rules (pre-computed aggregates);
   - query result caching;
   - per-query cardinality limits.

### 9.6 Failure defense

| Failure | Defense |
|---|---|
| Cardinality bomb | Ingest-time series limits per tenant/metric; reject new series, not samples of existing ones |
| Ingester crash | WAL replay; replication factor 2–3 for the head block; queries dedupe replicas |
| Object store outage | Recent data stays in ingesters; alerting unaffected; block uploads retry |
| Query of death (huge range × cardinality) | Query splitting, limits, timeouts, per-tenant query concurrency |
| Region outage | Regional independence; global views degrade, local alerting continues; external meta-monitoring |

### 9.7 L5 / L6 / L7 and probing chain

| | L5 | L6 | L7 |
|---|---|---|---|
| Design | "Store metrics in Cassandra" | Chunks, Gorilla compression, inverted label index, downsampling | Cardinality as the scaling and DoS axis; alerting more available than its targets; compression measured on our data |
| Numbers | Samples/s | Bytes/point, RAM for the hot window | 138 → 12 TB/day; index size from cardinality |

1. **Probe:** "Ingesters keep OOMing." **L5:** "Add memory."
2. **Probe:** "Series count doubled overnight." **L6:** "A cardinality explosion; find the new label, drop it via
   relabeling."
3. **Probe:** "Prevent it platform-wide." **L7:**
   - Per-tenant and per-metric series limits at ingest, with clear rejection metrics fed back to the owning team.
   - Cardinality budgets per service in review.
   - Exemplars for per-request identifiers.
   - "Critically, enforcement keeps existing series flowing, so a bad deploy can't blind the alerting the company
     needs to detect that very deploy."

---

## Problem 10: A distributed tracing system (Dapper class)

### 10.1 Scope, scale and SLAs

| Quantity | Target |
|---|---|
| Requests traced | 10M req/s across 2,000 services; ~20 spans per request |
| Raw span volume | 200M spans/s × ~500 B = **100 GB/s** if everything were kept |
| Storage budget | ≤ 2–3% of raw (≈ 2–3 GB/s → ~200 TB/day) |
| Query | Find a trace by ID in < 2 s; search by service/error/latency over the last 7 days |
| Overhead | < 1% CPU and < 1 ms added latency per service hop |

### 10.2 Sampling (§B of the output: 200,000 traces, 1% errors, 0.5% pathological slow tail)

| Strategy | Stored | Error traces retained | Slow (> 500 ms) traces retained |
|---|---|---|---|
| Head-based, 1% (decided at the root, before the outcome is known) | 0.98% | **1.0%** | **0.5%** |
| **Tail-based** (decide after completion: keep errors + slow + 1% baseline) | **2.26%** | **100%** | **100%** |

**Head-based sampling throws away 99% of exactly the traces you need during an incident.** Tail-based sampling keeps
all of them for 2.3% of the volume. The cost is architectural:
- spans of a trace must be buffered until the trace completes;
- they must be routed to the same collector.

### 10.3 Schema and partition key

```
span = {trace_id (128-bit), span_id, parent_id, service, operation, start_ns, duration_ns, status, attributes,
        links}   — W3C Trace Context headers propagate trace_id/parent_id (traceparent, tracestate)
collector routing: hash(trace_id) → collector (all spans of a trace meet in one place for the tail decision)
storage: (trace_id) → spans (columnar, compressed) ; secondary indexes: (service, operation, time bucket, status,
         duration bucket) → trace_ids   (time-bucketed to avoid hotspots)
```

### 10.4 Architecture and paths

```
 service (OpenTelemetry SDK: create spans, propagate context, export async in batches; never block requests)
   └► local agent/sidecar (buffer, batch, drop under pressure) ─► gateway LB (consistent hash on trace_id)
        ─► tail-sampling collectors (buffer each trace ~10–30 s after its last span; policies: error, latency,
           rare service, baseline %) ─► kept traces ─► storage (columnar/object store + index)
                                                    ─► span metrics (RED: rate/errors/duration) computed from ALL spans
                                                       BEFORE sampling (so dashboards are unbiased)
 query: by trace_id (direct), by search (index) → UI
```

### 10.5 The core L7 bottleneck: never hurt production, and keep the right 2%

1. **Telemetry must be the first thing shed.** Span export is asynchronous, with bounded buffers that *drop*, never
   block. Under overload, agents drop spans before applications slow down. A tracing system that causes a
   latency incident is the canonical "fallback that becomes the failure".
2. **Tail sampling at scale is a stateful streaming problem.**
   - Buffer memory = span rate × decision delay: 200M spans/s × 20 s × 500 B = **2 TB of RAM** across collectors.
   - So the decision delay and the buffer per trace are bounded, and "trace never completes" timeouts are enforced.
   - Consistent hashing on trace_id must survive collector scaling: use bounded-load or consistent hashing with
     handoff (Folder 02 file 03).
3. **Unbiased metrics.** Compute service-level RED metrics from 100% of spans before sampling. Store the sampled
   traces with their sampling weights, so counts derived from traces can be re-weighted.

### 10.6 Failure defense

| Failure | Defense |
|---|---|
| Tracing backend down | SDK buffers drop silently; apps unaffected; metrics from local aggregation continue |
| Collector loss | Traces in its buffer are lost (acceptable); consistent hashing reroutes new spans |
| Huge traces (fan-out of 100k spans) | Per-trace span limits; truncation with markers |
| Hot trace ID / one service flooding spans | Per-service rate limits at the agent; adaptive sampling per service |
| PII in attributes | Attribute scrubbing at the collector; allow-lists |

### 10.7 L5 / L6 / L7 and probing chain

| | L5 | L6 | L7 |
|---|---|---|---|
| Design | Log spans to Elasticsearch | Context propagation, head sampling, collectors, trace-ID lookup | Tail sampling (100% of errors at 2.3% storage), its memory cost, routing by trace ID; telemetry shed first; RED metrics pre-sampling |

1. **Probe:** "Sample 1% of requests." **L5:** "Saves 99%."
2. **Probe:** "During an incident, you can't find any failing traces." **L6:** "Switch to tail-based sampling: keep
   all errors and slow traces."
3. **Probe:** "What does tail sampling cost, and what can go wrong?" **L7:**
   - "~2 TB of buffer RAM at our span rate, routing by trace ID, and a decision delay of tens of seconds."
   - "Failure modes: collector hot spots and 'never-completing' traces filling buffers."
   - "So enforce per-trace limits, bounded-load hashing, and agent-side drop policies."
   - "The SLO is that tracing never adds latency: drops, not blocking."

---

## Problem 11: Global authorization (Google Zanzibar)

### 11.1 Scope, scale and SLAs

**Interpretation.** One authorization service for all products, using relationship-based access control (ReBAC):
- "user U can view document D because U is in group G, which is an editor of folder F, which is D's parent."

| Quantity (Zanzibar paper, ATC 2019) | Value |
|---|---|
| Relation tuples | **> 2 trillion** |
| Check QPS | **~10M/s** peak, from many products |
| Latency | **p95 < 10 ms**; p99 < 20 ms (paper) |
| Availability | **> 99.999%** over 3 years (paper) |
| Consistency | No "new enemy" problem: checks must respect the order of ACL changes and content changes |

### 11.2 Data model, schema and partitioning

```
tuple:   ⟨object⟩#⟨relation⟩@⟨user | userset⟩       e.g.  doc:readme#owner@user:alice
                                                        group:eng#member@group:infra#member   (nested groups)
                                                        doc:readme#parent@folder:docs
namespace config (per object type), with userset REWRITES:
  doc#viewer = this ∪ doc#editor ∪ (doc#parent → folder#viewer)       # computed_userset + tuple_to_userset
storage: Spanner, per namespace; primary key (object_id, relation, user) → tuple, MVCC timestamped
partition: shard by object_id (and namespace); hot objects → cache + request hedging
zookie:   an opaque token encoding a Spanner commit timestamp ("content version" for ACL purposes)
```

### 11.3 Architecture and paths

```
 client (product) ─► aclserver (any region) ─► Check(object, relation, user, zookie?)
     evaluation = graph traversal over tuples + rewrites, at a SNAPSHOT TIMESTAMP chosen ≥ zookie
     ├─ distributed cache of (object#relation, snapshot) results across aclservers (consistent hashing)
     ├─ request hedging to replicas; duplicate in-flight requests coalesced
     └─ Leopard index for deeply nested groups: flattened (group → all member users) set, updated incrementally
 writes: Write(tuples) → Spanner transaction → returns zookie (commit timestamp)
 Watch: change stream of tuples (for downstream indexes, search ACL trimming, Leopard updates)
 storage: Spanner (TrueTime external consistency) → snapshot reads at any timestamp, globally
```

### 11.4 The core L7 bottleneck: the new-enemy problem (consistency vs latency)

The scenario, from the paper:
1. Alice removes Bob from a folder's viewers.
2. Alice then puts secret content in a document in that folder.
3. If Bob's check is evaluated at a snapshot *before* the removal, Bob sees the secret. Replicas lag, and caches
   serve stale results.

§C of the output, with replica lag of 0–5 time units:

| | Bob sees content written after his removal |
|---|---|
| Checks at the replica's latest snapshot (no zookies) | **2,490 of 5,000** |
| **Checks at a snapshot ≥ the content's zookie** | **0** |

**The mechanism:**
- When content is modified, the product asks Zanzibar for a **content-change check** and stores the returned zookie
  with the content version.
- Later checks for that content pass the zookie.
- Zanzibar evaluates at any snapshot **at least as fresh as the zookie**.

That gives causal consistency between ACL changes and content changes (Folder 01 file 03 §8.2) *without* forcing
every check to read the latest data. Zanzibar picks the snapshot freely (≥ the zookie), which lets it serve from
cache and nearby replicas most of the time. That flexibility is what makes 10M checks/s at p95 < 10 ms possible.

### 11.5 The second bottleneck: deep group nesting, and Leopard

Recursive evaluation reads one tuple set per nesting level (§C):

| Nesting depth | Recursive reads |
|---|---|
| 2 | 3 |
| 5 | 6 |
| 8 | 9 |

Each read is a storage round trip, and real graphs fan out at every level. **Leopard** maintains a **flattened
transitive closure** (group → all member users, and group → all descendant groups) in a specialized in-memory index,
updated incrementally from the Watch stream. A check becomes a set-intersection lookup.

The cost is index maintenance: a change to a large group fans out. That is acceptable because group membership
changes are rare compared with checks.

### 11.6 Failure defense

| Failure | Defense |
|---|---|
| Hot object (a popular document checked by millions) | Distributed result cache keyed by (object#relation, snapshot); coalescing; hedging |
| Replica lag | Snapshot choice ≥ zookie; otherwise evaluate at a slightly stale "safe" snapshot (default staleness ~seconds in the paper, ⚠ verify) |
| Region outage | Spanner replicas in many regions; aclservers everywhere; checks keep working at bounded staleness |
| Abusive client | Per-client quotas; isolation by client in aclserver pools (shuffle sharding) |
| Config error in namespace rewrites | Validated, staged namespace config changes; per-namespace rollout |
| Fail-open vs fail-closed | **Fail closed.** Authorization must never grant on error; products degrade UX (e.g. "request access") instead |

### 11.7 L5 / L6 / L7 and probing chain

| | L5 | L6 | L7 |
|---|---|---|---|
| Model | Roles in each service's DB | Central ReBAC tuples with rewrites; caching | Zookies for the new-enemy problem; snapshot freedom as the latency lever; Leopard for nesting; Watch for downstream indexes |
| Consistency | Read the latest | Strong reads everywhere (slow) | Causal between ACL and content changes via tokens; bounded staleness otherwise |
| Failure | — | Cache invalidation | Fail closed; per-client isolation; staged namespace config |

1. **Probe:** "Cache authorization results for 5 minutes." **L5:** "Big latency win."
2. **Probe:** "A user is removed from a team and still sees new confidential docs for 5 minutes." **L6:** "Invalidate
   caches on ACL changes."
3. **Probe:** "Invalidation is async and lossy at our scale." **L7:**
   - "Use zookies: content carries the timestamp of its ACL-relevant change, and checks must evaluate at a snapshot
     ≥ that."
   - "Cached results keyed by snapshot are reused only if their snapshot ≥ the requested zookie."
   - "Staleness becomes harmless exactly where it would be dangerous, and caching stays effective everywhere else."
   - The simulation: 2,490 leaks → 0.

---

## 12. The listing

```python
"""tsdb_zanzibar_lab.py - Gorilla compression, trace sampling, and Zanzibar checks (Folder 06, file 03).

  A. Gorilla (Pelkonen et al., VLDB 2015): delta-of-delta timestamps + XOR'd float values, bit-exact encoder and
     decoder; bytes per point for several series shapes.
  B. Distributed tracing: head-based 1% sampling vs tail-based sampling (keep errors + slow + 1% baseline):
     fraction of error/slow traces retained vs storage.
  C. Zanzibar (Pang et al., ATC 2019): relation tuples with userset rewrites; the "new enemy" problem under replica
     lag, without and with zookies (snapshot tokens); a Leopard-style flattened group index vs recursive expansion.
Standard library only; seeded, deterministic.
"""
import math
import random
import struct


# ---------------------------------------------------------------- A. Gorilla
class BitWriter:
    def __init__(self):
        self.bits: list[int] = []

    def write(self, value: int, n: int) -> None:
        for i in range(n - 1, -1, -1):
            self.bits.append((value >> i) & 1)


class BitReader:
    def __init__(self, bits: list[int]):
        self.bits, self.pos = bits, 0

    def read(self, n: int) -> int:
        v = 0
        for _ in range(n):
            v = (v << 1) | self.bits[self.pos]
            self.pos += 1
        return v


def f2u(x: float) -> int:
    return struct.unpack(">Q", struct.pack(">d", x))[0]


def u2f(u: int) -> float:
    return struct.unpack(">d", struct.pack(">Q", u))[0]


DOD_BUCKETS = ((0b10, 2, 7), (0b110, 3, 9), (0b1110, 4, 12))


def gorilla_encode(points: list) -> BitWriter:
    w = BitWriter()
    t0, v0 = points[0]
    w.write(t0, 64)
    w.write(f2u(v0), 64)
    prev_t, prev_delta, prev_v = t0, 0, f2u(v0)
    lead, trail = 64, 0
    for t, v in points[1:]:
        delta = t - prev_t
        dod = delta - prev_delta
        if dod == 0:
            w.write(0, 1)
        else:
            for prefix, plen, bits in DOD_BUCKETS:
                if -(1 << (bits - 1)) < dod <= (1 << (bits - 1)):
                    w.write(prefix, plen)
                    w.write(dod & ((1 << bits) - 1), bits)
                    break
            else:
                w.write(0b1111, 4)
                w.write(dod & 0xFFFFFFFF, 32)
        prev_t, prev_delta = t, delta
        u = f2u(v)
        x = u ^ prev_v
        if x == 0:
            w.write(0, 1)
        else:
            w.write(1, 1)
            lz = min(64 - x.bit_length(), 31)
            tz = (x & -x).bit_length() - 1
            if lz >= lead and tz >= trail:                       # fits in the previous meaningful window
                w.write(0, 1)
                w.write(x >> trail, 64 - lead - trail)
            else:
                lead, trail = lz, tz
                w.write(1, 1)
                w.write(lead, 5)
                w.write(64 - lead - trail - 1, 6)                # meaningful length - 1 (1..64)
                w.write(x >> trail, 64 - lead - trail)
        prev_v = u
    return w


def gorilla_decode(bits: list, n: int) -> list:
    r = BitReader(bits)
    t, v = r.read(64), r.read(64)
    out = [(t, u2f(v))]
    delta, lead, trail = 0, 64, 0
    for _ in range(n - 1):
        if r.read(1) == 0:
            dod = 0
        else:
            nbits = 32
            for i, (_, _, bits_) in enumerate(DOD_BUCKETS):
                if r.read(1) == 0:
                    nbits = bits_
                    break
            raw = r.read(nbits)
            dod = raw - (1 << nbits) if raw > (1 << (nbits - 1)) else raw
        delta += dod
        t += delta
        if r.read(1) == 1:
            if r.read(1) == 1:
                lead = r.read(5)
                mlen = r.read(6) + 1
                trail = 64 - lead - mlen
            v ^= r.read(64 - lead - trail) << trail
        out.append((t, u2f(v)))
    return out


def series(kind: str, n: int, rng: random.Random) -> list:
    t, pts = 1_761_500_000, []
    val = 20.0
    for i in range(n):
        t += 10 if rng.random() > 0.01 else rng.choice((9, 11))    # mostly regular 10 s scrapes, rare jitter
        if kind == "constant gauge":
            v = 1.0
        elif kind == "integer counter":
            val += rng.randrange(0, 5)
            v = float(int(val))
        elif kind == "2-decimal sensor":
            val += rng.choice((-0.01, 0.0, 0.01))
            v = round(val, 2)
        else:
            v = rng.random() * 1000
        pts.append((t, v))
    return pts


# ---------------------------------------------------------------- B. trace sampling
def sampling(traces: int, rng: random.Random) -> dict:
    kept_head = kept_tail = err_total = slow_total = err_head = err_tail = slow_head = slow_tail = 0
    for _ in range(traces):
        err = rng.random() < 0.01
        lat = rng.lognormvariate(math.log(80), 0.6) * (5 if rng.random() < 0.005 else 1)
        slow = lat > 500
        err_total += err
        slow_total += slow
        if rng.random() < 0.01:                                  # head-based: decide at the root, before outcome
            kept_head += 1
            err_head += err
            slow_head += slow
        if err or slow or rng.random() < 0.01:                   # tail-based: decide after the trace completes
            kept_tail += 1
            err_tail += err
            slow_tail += slow
    return {"head": (kept_head / traces, err_head / err_total, slow_head / slow_total),
            "tail": (kept_tail / traces, err_tail / err_total, slow_tail / slow_total)}


# ---------------------------------------------------------------- C. Zanzibar
class Zanzibar:
    """Tuples: (object, relation, subject, ts) where subject is 'user:x' or a userset 'object#relation'.
    Rewrites: doc#viewer = this | doc#editor | parent->folder#viewer ; folder#viewer = this."""
    def __init__(self):
        self.tuples: list = []                                  # (obj, rel, subject, ts, deleted_ts)

    def write(self, obj: str, rel: str, sub: str, ts: int) -> None:
        self.tuples.append([obj, rel, sub, ts, None])

    def delete(self, obj: str, rel: str, sub: str, ts: int) -> None:
        for tp in self.tuples:
            if tp[:3] == [obj, rel, sub] and tp[4] is None:
                tp[4] = ts

    def _direct(self, obj: str, rel: str, snap: int) -> list:
        return [tp[2] for tp in self.tuples if tp[0] == obj and tp[1] == rel and tp[3] <= snap
                and (tp[4] is None or tp[4] > snap)]

    def check(self, obj: str, rel: str, user: str, snap: int, depth: int = 0) -> bool:
        if depth > 10:
            return False
        for sub in self._direct(obj, rel, snap):
            if sub == user:
                return True
            if "#" in sub:
                o, r = sub.split("#")
                if self.check(o, r, user, snap, depth + 1):
                    return True
        if obj.startswith("doc:") and rel == "viewer":
            if self.check(obj, "editor", user, snap, depth + 1):              # computed userset
                return True
            for parent in self._direct(obj, "parent", snap):                  # tuple-to-userset
                if self.check(parent, "viewer", user, snap, depth + 1):
                    return True
        return False


def new_enemy(trials: int, use_zookie: bool, rng: random.Random) -> int:
    """t=10 Alice removes Bob from folder viewers; t=11 Alice puts secret content in a doc under the folder and the
    content stores the zookie (t=11). Bob's check is served by a replica lagging 0-5 time units."""
    leaks = 0
    for _ in range(trials):
        z = Zanzibar()
        z.write("folder:f", "viewer", "user:bob", 1)
        z.write("doc:d", "parent", "folder:f", 1)
        z.delete("folder:f", "viewer", "user:bob", 10)
        content_zookie = 11
        replica_snapshot = 12 - rng.randint(0, 5)                            # possibly before t=10
        snap = max(replica_snapshot, content_zookie) if use_zookie else replica_snapshot
        leaks += z.check("doc:d", "viewer", "user:bob", snap)                 # Bob sees content written after removal
    return leaks


def leopard(depth: int, fanout: int) -> dict:
    """Nested groups: group:g0 contains g1 ... contains g_depth, each also with `fanout` direct users.
    Recursive expansion touches every level; a Leopard-style index stores the flattened user set per group."""
    z = Zanzibar()
    for d in range(depth):
        z.write(f"group:g{d}", "member", f"group:g{d + 1}#member", 1)
        for u in range(fanout):
            z.write(f"group:g{d}", "member", f"user:u{d}_{u}", 1)
    for u in range(fanout):
        z.write(f"group:g{depth}", "member", f"user:u{depth}_{u}", 1)
    reads = [0]
    orig = z._direct

    def counted(obj, rel, snap):
        reads[0] += 1
        return orig(obj, rel, snap)
    z._direct = counted
    ok = z.check("group:g0", "member", f"user:u{depth}_0", 5)
    flattened = {f"user:u{d}_{u}" for d in range(depth + 1) for u in range(fanout)}
    return {"recursive_reads": reads[0], "allowed": ok, "leopard_lookups": 1,
            "leopard_hit": f"user:u{depth}_0" in flattened, "index_size": len(flattened)}


def main() -> None:
    rng = random.Random(15)
    print("== A. Gorilla compression, 1,440 points per series (4 h at ~10 s), raw = 16 bytes/point")
    gz = {}
    for kind in ("constant gauge", "integer counter", "2-decimal sensor", "random doubles"):
        pts = series(kind, 1440, rng)
        enc = gorilla_encode(pts)
        dec = gorilla_decode(enc.bits, len(pts))
        bpp = len(enc.bits) / 8 / len(pts)
        gz[kind] = (bpp, dec == pts)
        print(f"  {kind:<18} {bpp:6.2f} bytes/point ({16 / bpp:5.1f}x)   round-trip exact: {dec == pts}")

    print("\n== B. trace sampling over 200,000 traces (1% errors, 0.5% pathological slow tail)")
    sm = sampling(200_000, rng)
    for name, (kept, err, slow) in sm.items():
        print(f"  {name + '-based':<11} stored {kept * 100:5.2f}% of traces; retained {err * 100:5.1f}% of error "
              f"traces and {slow * 100:5.1f}% of slow (>500 ms) traces")

    print("\n== C. Zanzibar")
    ne = {z: new_enemy(5000, z, rng) for z in (False, True)}
    for z, leaks in ne.items():
        print(f"  new-enemy problem, replica lag 0-5 units, {'with zookies' if z else 'no zookies  '}: "
              f"Bob sees post-removal content in {leaks} of 5000 checks")
    for depth in (2, 5, 8):
        lp = leopard(depth, 20)
        print(f"  nested groups depth {depth}: recursive check reads {lp['recursive_reads']:>3} tuple sets; "
              f"Leopard flattened index: 1 lookup in a set of {lp['index_size']} (both allow: "
              f"{lp['allowed'] and lp['leopard_hit']})")

    for kind, (bpp, ok) in gz.items():
        assert ok, kind
    assert gz["constant gauge"][0] < 0.3 and gz["2-decimal sensor"][0] < 8 and gz["random doubles"][0] > 8
    h, t = sm["head"], sm["tail"]
    assert abs(h[1] - 0.01) < 0.01 and t[1] == 1.0 and t[2] == 1.0 and t[0] < 0.05
    assert ne[False] > 0 and ne[True] == 0
    assert leopard(8, 20)["recursive_reads"] > leopard(2, 20)["recursive_reads"]
    print("\nself-test: all assertions passed")


if __name__ == "__main__":
    main()
```

Output (verified; deterministic):

```text
== A. Gorilla compression, 1,440 points per series (4 h at ~10 s), raw = 16 bytes/point
  constant gauge       0.29 bytes/point ( 55.6x)   round-trip exact: True
  integer counter      1.48 bytes/point ( 10.8x)   round-trip exact: True
  2-decimal sensor     4.53 bytes/point (  3.5x)   round-trip exact: True
  random doubles       8.07 bytes/point (  2.0x)   round-trip exact: True

== B. trace sampling over 200,000 traces (1% errors, 0.5% pathological slow tail)
  head-based  stored  0.98% of traces; retained   1.0% of error traces and   0.5% of slow (>500 ms) traces
  tail-based  stored  2.26% of traces; retained 100.0% of error traces and 100.0% of slow (>500 ms) traces

== C. Zanzibar
  new-enemy problem, replica lag 0-5 units, no zookies  : Bob sees post-removal content in 2490 of 5000 checks
  new-enemy problem, replica lag 0-5 units, with zookies: Bob sees post-removal content in 0 of 5000 checks
  nested groups depth 2: recursive check reads   3 tuple sets; Leopard flattened index: 1 lookup in a set of 60 (both allow: True)
  nested groups depth 5: recursive check reads   6 tuple sets; Leopard flattened index: 1 lookup in a set of 120 (both allow: True)
  nested groups depth 8: recursive check reads   9 tuple sets; Leopard flattened index: 1 lookup in a set of 180 (both allow: True)

self-test: all assertions passed
```

---

## 13. References for problems 9–11

- T. Pelkonen et al. *Gorilla: A Fast, Scalable, In-Memory Time Series Database.* VLDB 2015.
- C. Adams et al. *Monarch: Google's Planet-Scale In-Memory Time Series Database.* VLDB 2020.
- B. Sigelman et al. *Dapper, a Large-Scale Distributed Systems Tracing Infrastructure.* Google TR 2010.
  OpenTelemetry specification; W3C Trace Context.
- R. Pang et al. *Zanzibar: Google's Consistent, Global Authorization System.* USENIX ATC 2019.
- Prometheus TSDB design (head block, WAL, 2-hour blocks); Thanos/Cortex/Mimir architecture documentation.
- Open-source Zanzibar implementations (SpiceDB, OpenFGA): see Folder 10 file 03.
