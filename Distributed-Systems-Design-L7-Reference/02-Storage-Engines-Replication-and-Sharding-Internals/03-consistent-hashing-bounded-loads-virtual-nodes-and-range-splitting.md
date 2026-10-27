# Consistent Hashing, Bounded Loads, Virtual Nodes, and Range Splitting

> **Folder 02 · File 03** of the Distributed Systems & System Design L7 Reference.
> **Prerequisites:** [Folder 01 file 01 §6.7](../01-First-Principles-Physics-and-L5-L6-L7-Rubric/01-l5-vs-l6-vs-l7-interview-evaluation-rubric-and-signals.md#67-zipf-and-cache-sizing)
> (Zipf skew).
> **Listing:** `partitioning_lab.py` covers:
> - ring imbalance vs virtual nodes;
> - keys moved on resize: mod-N, ring, rendezvous, jump hash;
> - bounded-load consistent hashing under Zipf skew;
> - range hotspots from monotonic keys.
>
> The output is deterministic.

---

## 0. The problem, and the three properties you want

Partitioning (sharding) maps each key to a node. A good scheme has three properties:

1. **Balance:** each node owns ≈ 1/N of keys, and of *load*. Load is the harder of the two.
2. **Minimal movement:** adding or removing a node moves only ≈ 1/N of keys. Movement costs network bandwidth, cache
   warm-up and rebalancing risk.
3. **Locality where needed:** range scans need ordered placement; hashing destroys order.

No scheme gives all three for all workloads. **Hash partitioning** gives balance plus minimal movement and loses
order. **Range partitioning** keeps order and must handle hotspots and splits. The rest of this file is the
mechanics and math of each.

---

## 1. Why mod-N fails

`node = hash(key) mod N` balances perfectly. When N changes, a key keeps its node only if $h \bmod N = h \bmod
(N+1)$, which happens for ≈ 1/(N+1) of keys. So **≈ N/(N+1) of all keys move**: 90.94% when growing 10 → 11 (§B of
the output).

For a cache tier, that is a near-total cold start at the moment you added capacity because you were overloaded: a
self-inflicted metastable failure (Folder 05 file 02).

---

## 2. The hash ring (Karger et al. 1997)

```
                    0 / 2^64
                 ┌─────●─────┐          each server owns the arc ending at its token
            n3 ●              ● n1      key k → first token clockwise of hash(k)
              │      ring      │
            n2 ●              ● n1'     virtual nodes: each server places V tokens (n1, n1', ...)
                 └─────●─────┘
                       n2'
  add server n4: it takes over arcs from its successors only → ≈ 1/(N+1) of keys move
```

**Imbalance with one token per server is terrible.** Arc lengths between N random points are ~Exponential(1/N), so
the largest arc is ≈ (ln N)/N. With 100 servers (§A of the output):

| Tokens per server | max / mean ownership | min / mean | stdev / mean |
|---|---|---|---|
| 1 | **4.38** | 0.00 | 0.91 |
| 16 | 1.54 | 0.50 | 0.23 |
| 256 | **1.17** | 0.85 | 0.06 |

Standard deviation shrinks as $1/\sqrt{V}$. Virtual nodes have other costs:
- **Metadata:** N × V tokens to gossip and store.
- **Repair and streaming fan-out:** each node shares ranges with many peers.
- **Availability coupling:** with many vnodes, any two node failures likely share *some* range, so RF=3 data loses
  quorum on some ranges more often.

Cassandra 4.0 lowered the default `num_tokens` from 256 to 16 and added a token allocation algorithm that places
tokens to balance load deliberately rather than randomly (⚠ verify for your version). The default changed because of
these costs.

---

## 3. Other consistent-hashing schemes

| Scheme | Lookup cost | Memory | Movement on resize | Arbitrary node removal | Weighted | Notes |
|---|---|---|---|---|---|---|
| **Ring + vnodes** | O(log NV) binary search | O(NV) | ≈ 1/N (measured 9.78%) | Yes | Yes (more vnodes) | Cassandra, Dynamo, Riak |
| **Rendezvous / HRW** (Thaler & Ravishankar 1998) | O(N) per key: score every node | O(N) | ≈ 1/N (8.84%) | Yes | Yes (weighted scores) | Trivially gives an ordered fallback list (top-k scores = replicas). Fine up to hundreds of nodes |
| **Jump consistent hash** (Lamping & Veach 2014) | O(ln N), no table | O(1) | **Optimal 1/N** (9.11%) | **No**: buckets must be 0..N−1; only the last can be removed | No | Ideal for sharding into numbered *partitions* that are then mapped to nodes |
| **Maglev** (Eisenbud et al., NSDI 2016) | O(1) table lookup | O(M), M ≈ 65,537 | Near-minimal | Yes | Yes | L4 load balancers (Folder 04 file 01) |
| **Multi-probe** (Appleton & O'Reilly 2015) | O(k log N) | O(N) | ≈ 1/N | Yes | — | One token per node, k probes per key for balance without vnodes |

**Fixed partitions, then partitions → nodes.** Many production systems (Elasticsearch shards, Kafka partitions,
Riak, Couchbase vBuckets: 1,024) hash keys into a **fixed number of partitions P ≫ N** and keep a small
`partition → node` map. Resizing moves whole partitions, and the map is the control-plane state.

This decouples the hash function (never changes) from placement (changes with capacity). It is the L7 default for
anything with a control plane. The cost is choosing P up front:
- Too few, and you can't grow.
- Too many, and per-partition overhead dominates (file handles, metadata, Kafka controller load).

---

## 4. Load is not keys: bounded-load consistent hashing

Consistent hashing balances *keys*. Real traffic is Zipf-skewed (Folder 01 file 01 §6.7), so one server can receive
many times the mean *load* even with perfect key balance.

**Consistent hashing with bounded loads** (Mirrokni, Thorup & Zadimoghaddam, SODA 2018):
- Give every server a capacity of $\lceil (1+\varepsilon) \cdot \text{mean load} \rceil$.
- A request goes to its first clockwise server **with spare capacity**.
- Vimeo deployed it in HAProxy for video-segment caching (⚠ verify the details), and it is in Envoy's ring-hash and
  Maglev balancers via a `hash_balance_factor` option.

§C of the output (50 servers, 200k requests over 100k keys):

| Request skew | Plain CH max/mean load | Bounded (ε = 0.25) max/mean | Requests displaced from first choice |
|---|---|---|---|
| Uniform | 1.58 | **1.25** | 2.9% |
| Zipf s = 0.8 | 2.31 | 1.25 | 5.2% |
| Zipf s = 1.1 | **7.44** | 1.25 | **30.4%** |

The bound holds by construction. The price is **cache affinity**:
- At heavy skew, 30% of requests land on a non-home server, which then caches the hot object too.
- For caches, that is often *desirable*: hot objects get replicated to more servers automatically.
- For stateful partitions (databases), it is not possible at all. A key's data lives on its owner, so you need
  **hot-key strategies** instead (§5).

The theoretical guarantee: with ε, the expected number of moves when a server is added or removed is $O(1/\varepsilon^2)$
times the optimum, so a small ε costs both locality and stability.

---

## 5. Hot keys: what hashing cannot fix

A single key at 100k QPS lives on one partition no matter how good the hash function is. The toolbox:

| Technique | How | Works for | Cost |
|---|---|---|---|
| **Read replicas of the hot key** | Replicate to k nodes; readers pick randomly | Read-hot keys | Invalidation fan-out ×k |
| **Key salting / splitting** | Store `key#0 … key#(k−1)`; writes go to a random suffix, reads gather all k | Write-hot counters and append-only sets | Reads become k-way scatter-gather |
| **Local (in-process) caching** | L1 cache in every app server for the top-K keys | Read-hot, staleness-tolerant | Staleness window; memory per process |
| **Request coalescing** | Single-flight: one fetch per key per node; others wait | Cache misses on hot keys | A little latency for the waiters |
| **Write batching / aggregation** | Accumulate increments in memory, flush every 100 ms | Counters (likes, views) | Durability window; Folder 08 problem 29 |
| **Isolation** | Move the whale tenant to its own partition/cell | Tenant-level skew | Operational: placement must be dynamic |

Detection comes first: sample requests at the proxy, keep a top-K sketch (count-min + heap), and alert when a key
exceeds ~10% of a partition's capacity. Folder 04 file 02 implements salting and measures it.

---

## 6. Range partitioning and the monotonic-key hotspot

### 6.1 Mechanics

```
 key space:  [ -∞ ............ "f" ............ "m" ............ "t" ............ +∞ )
 ranges:     |   R1 (node A)   |   R2 (node B)   |   R3 (node C)   |   R4 (node A)   |
 metadata:   range → (replicas, leaseholder/leader), versioned; clients cache it and retry on "wrong range"
 split:      R2 > size or QPS threshold → R2a [f, j), R2b [j, m)  (cheap: metadata only + Raft group split)
 merge:      adjacent small/cold ranges → one
```

| System | Unit | Split trigger (⚠ verify the defaults) |
|---|---|---|
| Bigtable / HBase | Tablet / region | Size (HBase ~10 GB regions) |
| Spanner | Split | Size and load; load-based splitting |
| CockroachDB | Range | `range_max_bytes` 512 MiB, plus load-based splitting on QPS/CPU |
| MongoDB | Chunk | Chunk size, plus the balancer |
| TiKV | Region | ~96 MB |

Ranges give **ordered scans** and **cheap splits**, and the metadata (range → node) is the control plane. Bigtable
famously stores it in a 3-level hierarchy (Chubby → root tablet → METADATA tablets).

### 6.2 The hotspot

§D of the output: 16 ranges over a day of timestamp-ordered keys, with 20k writes in the final minute.

| Key design | Hottest range's share of writes (ideal 6.25%) |
|---|---|
| Timestamp / UUIDv7 / auto-increment | **100%** |
| `hash(user) % 16` prefix + timestamp | 6.6% |
| Random UUIDv4 | 6.5% |

**Splitting does not help a monotonic key.** Split the hot range and the right half receives 100% of new writes; split
it again and the same thing happens. Load-based splitting fixes *spread-out* hotspots, not *moving* ones. The fixes:

- **Hash-prefix (salting) the key:** `bucket = hash(entity) % B` as the leading key component. Writes spread over B
  ranges, and per-entity scans stay ordered within a bucket. Global time-ordered scans become a B-way merge.
- **Hash partitioning** for the whole table: CockroachDB hash-sharded indexes, Spanner's advice against monotonically
  increasing primary keys, DynamoDB's partition key design.
- **Keep the monotonic key local:** a time-ordered key is *good* within a single B-tree (file 01 §1.3) and bad as the
  *leading* component of a distributed range key.

### 6.3 Range-partitioned *reads* are skewed too

"Recent data is hot" means the newest ranges get most reads. The fixes:
- follower or replica reads at bounded staleness for the hot tail;
- separate hot and cold tiers (the newest window replicated more widely);
- load-based splitting on *read* QPS, which works because reads of recent-but-spread keys are not monotonic per key.

---

## 7. Rebalancing: moving data without falling over

The cost of moving data is a bandwidth and risk calculation:

$$t_\text{rebalance} = \frac{\text{data to move}}{\text{throttled transfer rate}} \qquad \text{e.g. adding 1 node to 20 × 4 TB} \Rightarrow \frac{80\ \text{TB}}{21} \approx 3.8\ \text{TB} \;\Rightarrow\; \text{at 200 MB/s} \approx 5.3\ \text{h}$$

The throttle protects foreground p99, but a slow rebalance extends the window in which the cluster is under-replicated
or imbalanced. The same equation sets **MTTR after a node failure**, which sets durability. Folder 02 file 04 §4
shows how Aurora's 10 GB segments shrink the double-fault window by ~1,000× compared with 10 TB rebuilds.

The L7 rules:
1. **Many-to-many recovery.** Spread a dead node's ranges across *all* survivors. With vnodes or many partitions, each
   survivor sends a small slice, so recovery speed scales with cluster size. One-to-one rebuilds (a spare node
   receives everything) are bottlenecked on one NIC and one disk.
2. **Automated but rate-limited.** Automatic rebalancing on a node *flap* moves data twice. Wait out short outages
   (hinted handoff covers them), then rebalance.
3. **Placement constraints are part of the control plane:** replicas in distinct AZs/racks, tenant affinity, leaseholder
   preferences.

---

## 8. Request routing: who knows where the key lives?

| Approach | Example | Freshness of routing info | Failure mode |
|---|---|---|---|
| Smart client (token-aware) | Cassandra drivers, Redis Cluster clients | Gossip/topology events; `MOVED`/`ASK` redirects | Client bugs; thundering topology refresh |
| Proxy / router tier | Vitess `vtgate`, mcrouter, Envoy, MongoDB `mongos` | Proxy caches the map from a control plane | The proxy tier is a data-plane dependency, so it must be statically stable |
| Any-node coordinator | Cassandra, CockroachDB (any node forwards) | Each node knows the map | Extra hop |
| Metadata service | ZooKeeper/etcd-backed maps; Bigtable METADATA | Strongly consistent map, cached by clients | Control-plane outage must not stop the data plane: clients use cached maps plus redirects |

**Epochs make stale routing safe.** Every map version has an epoch. A node rejects requests for ranges it no longer
owns, with "wrong range, current epoch E". The client refreshes and retries. A stale cache then costs one extra round
trip and never a wrong answer.

---

## 9. The listing

```python
"""partitioning_lab.py - consistent hashing, virtual nodes, bounded loads and range hotspots (Folder 02, file 03).

  A. ownership imbalance of a hash ring vs virtual nodes per server
  B. keys moved when a node is added: mod-N vs ring vs rendezvous vs jump consistent hash
  C. consistent hashing with bounded loads (Mirrokni-Thorup-Zadimoghaddam) under Zipf-skewed requests
  D. range partitioning: monotonic keys (timestamps, UUIDv7) vs hash-prefixed keys vs random UUIDv4
Standard library only; seeded, deterministic.
"""
import bisect
import hashlib
import random

M64 = (1 << 64) - 1


def h64(*parts) -> int:
    return int.from_bytes(hashlib.blake2b("|".join(map(str, parts)).encode(), digest_size=8).digest(), "big")


class Ring:
    def __init__(self, nodes: list, vnodes: int):
        pts = sorted((h64(n, v), n) for n in nodes for v in range(vnodes))
        self.tokens = [p for p, _ in pts]
        self.owner = [n for _, n in pts]

    def lookup(self, key) -> str:
        i = bisect.bisect_right(self.tokens, h64("k", key)) % len(self.tokens)
        return self.owner[i]

    def successors(self, key):
        i = bisect.bisect_right(self.tokens, h64("k", key))
        for j in range(len(self.tokens)):
            yield self.owner[(i + j) % len(self.tokens)]

    def ownership(self) -> dict:
        own: dict = {}
        prev = self.tokens[-1] - (1 << 64)
        for t, n in zip(self.tokens, self.owner):
            own[n] = own.get(n, 0) + (t - prev)
            prev = t
        return {n: v / (1 << 64) for n, v in own.items()}


def jump_hash(key: int, buckets: int) -> int:
    """Lamping & Veach 2014: O(ln n) time, no memory; buckets must be numbered 0..n-1."""
    b, j = -1, 0
    while j < buckets:
        b = j
        key = (key * 2862933555777941757 + 1) & M64
        j = int((b + 1) * (float(1 << 31) / float((key >> 33) + 1)))
    return b


def rendezvous(key, nodes: list):
    return max(nodes, key=lambda n: h64(n, key))


def zipf_sampler(n: int, s: float, rng: random.Random):
    weights = [1 / (k ** s) for k in range(1, n + 1)]
    cum, total = [], 0.0
    for w in weights:
        total += w
        cum.append(total)
    return lambda: bisect.bisect_left(cum, rng.random() * total)


def bounded_load(nodes: list, requests: list, eps: float | None) -> tuple[float, float]:
    """Assign requests to their ring successor, skipping nodes at capacity ceil((1+eps) * mean)."""
    ring = Ring(nodes, 16)
    cap = None if eps is None else int((1 + eps) * len(requests) / len(nodes)) + 1
    load = {n: 0 for n in nodes}
    displaced = 0
    for key in requests:
        for i, n in enumerate(ring.successors(key)):
            if cap is None or load[n] < cap:
                load[n] += 1
                displaced += i > 0
                break
    mean = len(requests) / len(nodes)
    return max(load.values()) / mean, displaced / len(requests)


def main() -> None:
    rng = random.Random(1)
    print("== A. ownership imbalance: 100 servers on a hash ring")
    print(f"{'vnodes/server':>14} {'max/mean':>9} {'min/mean':>9} {'stdev/mean':>11}")
    imb = {}
    nodes100 = [f"n{i}" for i in range(100)]
    for v in (1, 16, 256):
        own = list(Ring(nodes100, v).ownership().values())
        mean = 1 / 100
        sd = (sum((o - mean) ** 2 for o in own) / len(own)) ** 0.5
        imb[v] = (max(own) / mean, min(own) / mean, sd / mean)
        print(f"{v:>14} {imb[v][0]:>9.2f} {imb[v][1]:>9.2f} {imb[v][2]:>11.3f}")

    print("\n== B. fraction of 100k keys that move when growing 10 -> 11 servers (ideal 1/11 = 9.09%)")
    keys = list(range(100_000))
    n10, n11 = [f"s{i}" for i in range(10)], [f"s{i}" for i in range(11)]
    moved = {}
    moved["mod-N"] = sum(h64("k", k) % 10 != h64("k", k) % 11 for k in keys) / len(keys)
    r10, r11 = Ring(n10, 16), Ring(n11, 16)
    moved["ring, 16 vnodes"] = sum(r10.lookup(k) != r11.lookup(k) for k in keys) / len(keys)
    moved["rendezvous (HRW)"] = sum(rendezvous(k, n10) != rendezvous(k, n11) for k in keys[:20_000]) / 20_000
    moved["jump hash"] = sum(jump_hash(h64("k", k), 10) != jump_hash(h64("k", k), 11) for k in keys) / len(keys)
    for k, v in moved.items():
        print(f"  {k:<20} {v * 100:6.2f}%")

    print("\n== C. bounded-load consistent hashing: 50 servers, 200k requests over 100k keys")
    nodes50 = [f"c{i}" for i in range(50)]
    bl = {}
    for s in (0.0, 0.8, 1.1):
        draw = zipf_sampler(100_000, s, rng) if s else (lambda: rng.randrange(100_000))
        reqs = [draw() for _ in range(200_000)]
        plain = bounded_load(nodes50, reqs, None)
        b25 = bounded_load(nodes50, reqs, 0.25)
        bl[s] = (plain, b25)
        print(f"  Zipf s={s:<4} plain CH max/mean {plain[0]:5.2f}   bounded eps=0.25: max/mean {b25[0]:4.2f}, "
              f"{b25[1] * 100:5.1f}% of requests leave their first-choice server")

    print("\n== D. range partitioning, 16 ranges, writes in the last minute of a day")
    day = 86_400
    last_min = [day - 60 + 60 * rng.random() for _ in range(20_000)]   # 20k writes in the final minute
    bounds_time = [day * i / 16 for i in range(1, 16)]       # ranges split evenly over the day's key space
    hot = {}

    def share(keys_, bounds):
        counts = [0] * 16
        for k in keys_:
            counts[bisect.bisect_right(bounds, k)] += 1
        return max(counts) / len(keys_)
    hot["timestamp / UUIDv7 key"] = share(last_min, bounds_time)
    hot["hash(user)%16 prefix + timestamp"] = share([(h64("u", i) % 16) * day + t for i, t in enumerate(last_min)],
                                                     [day * i for i in range(1, 16)])
    hot["random UUIDv4 key"] = share([rng.random() for _ in last_min], [i / 16 for i in range(1, 16)])
    for k, v in hot.items():
        print(f"  {k:<36} hottest range takes {v * 100:5.1f}% of writes (ideal 6.25%)")

    # self-test
    assert imb[1][0] > 3 and imb[256][0] < 1.35 and imb[16][2] > imb[256][2]
    assert moved["mod-N"] > 0.85
    for k in ("ring, 16 vnodes", "rendezvous (HRW)", "jump hash"):
        assert 0.06 < moved[k] < 0.13, k
    assert bl[1.1][0][0] > 3 and bl[1.1][1][0] <= 1.26 and bl[0.0][1][1] < bl[1.1][1][1]
    assert hot["timestamp / UUIDv7 key"] == 1.0 and hot["hash(user)%16 prefix + timestamp"] < 0.075
    print("\nself-test: all assertions passed")


if __name__ == "__main__":
    main()
```

Output (verified; deterministic):

```text
== A. ownership imbalance: 100 servers on a hash ring
 vnodes/server  max/mean  min/mean  stdev/mean
             1      4.38      0.00       0.912
            16      1.54      0.50       0.233
           256      1.17      0.85       0.061

== B. fraction of 100k keys that move when growing 10 -> 11 servers (ideal 1/11 = 9.09%)
  mod-N                 90.94%
  ring, 16 vnodes        9.78%
  rendezvous (HRW)       8.84%
  jump hash              9.11%

== C. bounded-load consistent hashing: 50 servers, 200k requests over 100k keys
  Zipf s=0.0  plain CH max/mean  1.58   bounded eps=0.25: max/mean 1.25,   2.9% of requests leave their first-choice server
  Zipf s=0.8  plain CH max/mean  2.31   bounded eps=0.25: max/mean 1.25,   5.2% of requests leave their first-choice server
  Zipf s=1.1  plain CH max/mean  7.44   bounded eps=0.25: max/mean 1.25,  30.4% of requests leave their first-choice server

== D. range partitioning, 16 ranges, writes in the last minute of a day
  timestamp / UUIDv7 key               hottest range takes 100.0% of writes (ideal 6.25%)
  hash(user)%16 prefix + timestamp     hottest range takes   6.6% of writes (ideal 6.25%)
  random UUIDv4 key                    hottest range takes   6.5% of writes (ideal 6.25%)

self-test: all assertions passed
```

---

## 10. L5 vs L6 vs L7

| Topic | L5 (Senior) | L6 (Staff) | L7 (Principal) |
|---|---|---|---|
| Scheme | "Consistent hashing" | Vnodes for balance; fixed partitions → nodes; jump vs rendezvous trade-offs | Partition count as a multi-year capacity decision; hash function frozen, placement in the control plane; epoch-fenced routing |
| Skew | — | Hot-key detection and salting; bounded loads for caches | Load models with Zipf exponents; bounded loads' locality cost (30% displaced at s=1.1); whale-tenant isolation into cells |
| Range keys | "Shard by user ID" | Monotonic keys hotspot range stores; hash prefixes | Key design per topology (local B-tree vs distributed range); read-skew on recent data; load-based splitting limits |
| Rebalancing | "Add a node" | Throttled streaming; under-replication window | Many-to-many recovery; MTTR → durability math; don't rebalance on flaps |

---

## 11. Bar-raiser probing chains

### Chain A: "Shard the cache tier with consistent hashing."

1. **L5:** "Ring of cache nodes; clients hash keys to nodes."
2. **Probe:** "One node is at 3× the others' CPU." **L6:** "Imbalance: use more vnodes (1 token gives max/mean 4.4;
   256 gives 1.17). If it's one hot key, salt or replicate it."
3. **Probe:** "Traffic is Zipf, s ≈ 1.1, and it shifts hourly." **L7:**
   - Bounded-load consistent hashing with ε ≈ 0.25 caps every node at 1.25× mean, and replicates hot objects to
     neighbors automatically.
   - Plus an L1 in-process cache for the top ~1,000 keys.
   - "We give up ~30% first-choice affinity at peak skew, which costs some extra memory, but no node can be
     overloaded by popularity."

### Chain B: "Design the partitioning for a 50 TB time-series store with range scans."

1. **L5:** "Range-partition by timestamp."
2. **Probe:** "All writes go to one node." **L6:** "Prefix with a hash bucket of the series ID; scans per series
   stay ordered."
3. **Probe:** "Dashboards need 'all series, last 5 minutes' at 1 s refresh." **L7:**
   - "That query is a B-way scatter-gather over buckets. B = 64 with parallel bucket scans is fine, but its p99 is
     the max of 64 shard p99s (Folder 01 file 01 §6.4)."
   - "So keep a separate rollup/latest-value index updated on write for the dashboard path, and bound fan-out."
   - "Partitioning is chosen per *query*, not per table."

### Chain C: "We have 64 Kafka partitions and need 10× throughput."

1. **L5:** "Add partitions."
2. **Probe:** "Consumers rely on per-key ordering." **L6:** "Adding partitions remaps keys (hash mod P), so ordering
   breaks for keys that move during the transition. Pause producers, or create a new topic and migrate."
3. **Probe:** "Avoid this next time." **L7:**
   - Over-provision partitions up front (e.g. 512), sized to the 3-year target, and accept per-partition overhead.
   - Or put an indirection layer in the producer (key → virtual partition via jump hash; virtual → physical via a
     versioned map) with a dual-write cutover per virtual partition.
   - Ordering is preserved because the move happens at a known offset boundary.

---

## 12. Invariants checklist

- [ ] Movement on resize ≈ 1/N; mod-N is never used where N changes.
- [ ] Balance is measured on *load* (QPS, bytes), not key counts; vnodes or token allocation is sized.
- [ ] Hot-key detection exists; mitigation per key type (replicate, salt, L1, coalesce, batch, isolate).
- [ ] Partition count is chosen for the long-term target; the hash function is frozen; placement is in a versioned
      map.
- [ ] Range stores: no monotonic leading key component; read skew on recent data handled.
- [ ] Routing is epoch-fenced; stale maps cost a retry, never a wrong answer.
- [ ] Rebalancing is throttled, many-to-many, and not triggered by flaps; MTTR feeds the durability math.

---

## 13. References

- D. Karger et al. *Consistent Hashing and Random Trees: Distributed Caching Protocols for Relieving Hot Spots on
  the World Wide Web.* STOC 1997.
- D. Thaler, C. Ravishankar. *Using Name-Based Mappings to Increase Hit Rates.* IEEE/ACM ToN 6(1), 1998 (rendezvous
  hashing).
- J. Lamping, E. Veach. *A Fast, Minimal Memory, Consistent Hash Algorithm.* arXiv:1406.2294, 2014.
- B. Appleton, M. O'Reilly. *Multi-Probe Consistent Hashing.* arXiv:1505.00062, 2015.
- V. Mirrokni, M. Thorup, M. Zadimoghaddam. *Consistent Hashing with Bounded Loads.* SODA 2018. Vimeo
  Engineering's write-up of the HAProxy implementation (⚠ verify the URL).
- D. Eisenbud et al. *Maglev: A Fast and Reliable Software Network Load Balancer.* NSDI 2016.
- F. Chang et al. *Bigtable: A Distributed Storage System for Structured Data.* OSDI 2006.
- Cassandra documentation: tokens, `num_tokens`, and the allocation algorithm. CockroachDB documentation: ranges,
  load-based splitting, hash-sharded indexes. Cloud Spanner documentation: schema design best practices (avoid
  monotonically increasing keys).
