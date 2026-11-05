# 02 · Grafana Mimir and Thanos: Distributor–Ingester Hash Rings and S3 Compaction

> **Folder 06 — OpenTelemetry, Grafana Alloy and the LGTM Scale Stack · File 2 of 3.**
> Pinned to **Grafana Mimir 3.2.4** (dskit `aa16062bba48`), **Thanos v0.42.5**, **Prometheus v3.15.1**.
> Labels: **[D]** documented / read in pinned source · **[M]** measured by the listing (deterministic, re-run by the gate) · **[E]** model · **⚠** version-sensitive.

| Listing | What it proves | Runtime |
|---|---|---|
| L2 `ring_lab.py` | **Series token.** Ports Mimir's series token (FNV-1 32 over tenant + label names/values, no separators). FNV vectors match, and the upstream "unsorted labels hash differently" behaviour reproduces. **Ring lookup.** Ports dskit's lookup (first token > key, distinct instances, one per zone). **Ownership.** On 30 ingesters × 128 tokens: random tokens give a 1.12× hottest-ingester load; tokens that are even but zone-blind give **7.01×**; per-zone spread gives 1.02×. **Failures.** A whole-zone loss costs 0% of writes with zone awareness and 23.7% without. **Shuffle sharding.** 91,125 possible shards; no tenant shares all 6 ingesters with a noisy neighbour. **Thanos dedup.** Ports Thanos's penalty dedup iterator: 5/5 upstream vectors. **Storage.** RF=3 uploads shrink 3× in the compactor, and downsampling *grows* storage at equal retention | ~5 s |

**Verification.**
- **Hash, lookup and dedup.** Line-by-line ports of `pkg/mimirpb/fnv.go`, `series_sharding.go`, dskit `ring/util.go`/`ring.go`, and Thanos `pkg/dedup/iter.go`, checked against upstream test vectors [M].
- **Mimir defaults.** Read from `cmd/mimir/config-descriptor.json` at `mimir-3.2.4` [D]; the YAML paths below are taken from it.
- **Ingest-storage behaviour.** From the 3.2.4 architecture docs [D].
- **Thanos flags and claims.** From the v0.42.5 component docs [D].
- **Not run.** No cluster was run.

---

## 0. Orientation

**What this file answers.**
- How a sample travels from `remote_write` to S3 in Mimir (classic and ingest-storage architectures) and in Thanos (sidecar and receive).
- Where it can be lost, duplicated or throttled.
- What the hash rings actually compute.
- What compaction and downsampling cost in object storage.

**Mimir 3 with ingest storage (the preferred architecture since 3.0 [D]):**

```text
 Prometheus / Alloy / OTel  ──remote_write / OTLP──►  distributor (stateless)
                                                       │ validate, limits (ingestion_rate, max_global_series_per_user…)
                                                       │ HA-tracker dedup (cluster/__replica__)
                                                       │ token = FNV-1(tenant, labels) → partition
                                                       ▼
                                             Kafka topic (N partitions) ── durability + replication live HERE
                                       ┌───────────────┼─────────────────────────┐
                                       ▼               ▼                         ▼
                           ingester-zone-a-7    ingester-zone-b-7         (one ingester per zone per partition;
                           consumes partition 7  consumes partition 7      partition = numeric suffix of instance ID)
                                       │  TSDB head + WAL, 2h blocks, kept 13h locally
                                       ▼
                               object storage (S3/GCS)  ◄── compactor (split-and-merge, vertical dedup, retention)
                                       ▲
                          store-gateway (blocks sharded RF=3) ◄── querier (MQE) ◄── query-frontend (split 24h, shard 16, cache)
                          ingesters (last ~13h) ◄──────────────────┘   X-Read-Consistency: strong → wait for offsets
```

**Mimir classic and Thanos, for contrast:**

```text
 Mimir classic:  distributor ──quorum write (2 of 3)──► ingesters (ring, RF=3, zone-aware) ──► S3
 Thanos sidecar: Prometheus (2h blocks, local compaction OFF) ── sidecar uploads ──► S3 ◄── compactor (SINGLETON per bucket)
                 querier fans out to sidecars (recent) + store gateways (historical); dedups by replica label
 Thanos receive: remote_write ──► receive hashring (ketama recommended, RF) ──► TSDB ──► S3
```

---

## 1. First principles

### 1.1 The series token: what decides placement [D][M]

Mimir's distributor computes `ShardByAllLabelAdapters(tenant, labels)`:

```text
 h = 2166136261                                 (FNV offset basis)
 for each byte b of tenant, then of name1, value1, name2, value2, …:
     h = (h × 16777619) mod 2^32 ;  h = h XOR b   (multiply THEN xor: FNV-1, not FNV-1a)
```

Three properties L2 §1 demonstrates:

| Property | Consequence |
|---|---|
| **Tenant is hashed first.** | The same series in two tenants lands on unrelated ingesters, so one tenant's hot series never co-locate by construction. |
| **Order-sensitive.** | Upstream `TestShardByAllLabelAdaptersReturnsWrongResultsForUnsortedLabels` asserts that unsorted labels yield a different token. Mimir sorts labels in a pre-push middleware; anything that bypasses it would misplace series. |
| **No separators.** | `{a="bc"}` and `{ab="c"}` collide. That is harmless for placement (they just share an ingester), but **never use the token as a series identity**. Series identity is the full sorted label set. |

**What this means for capacity.**
- One series always goes to the same ingesters (classic) or partition (ingest storage).
- One very high-rate series cannot be spread out. Mimir parallelises *across* series.
- A tenant's ingestion is spread across all ingesters (or its shuffle shard), so per-ingester series limits are a fraction of the global `max_global_series_per_user` (default **150,000** [D]: raise it per tenant deliberately).

### 1.2 The ring: tokens, ownership and the hottest ingester [D][M]

dskit's lookup, ported in L2:

```text
 tokens: each ingester registers num_tokens (default 128) uint32 tokens in the ring (memberlist KV)
 Get(key): i = first token > key (wrap)          ← searchToken: "first token > key, not >= key"
           walk clockwise; skip instances already chosen; with zone awareness skip zones already chosen
           stop at replication_factor (default 3) instances, one per zone
```

**Load balance is set by the hottest instance.** Ingester memory limits, and therefore pod sizes, are set for the max, not the mean. L2 §2 on 30 ingesters (3 zones × 10):

| Token strategy | Ring ownership max/mean | Series per ingester max/mean | min/mean |
|---|---|---|---|
| `random` (default) | 1.10 | **1.12** | 0.84 |
| even across all instances, zone-blind | 1.00 | **7.01** | 0.32 |
| even within each zone (≈ `spread-minimizing`) | 1.00 | **1.02** | 0.97 |

- **The middle row is the trap.** "Perfectly even" global tokens are catastrophic with zone-aware replication.
- With zone awareness each zone behaves as its own ring: the zone-b replica of a key is "the next zone-b token after the key".
- If zone-b's tokens all sit right after zone-a's, a handful of zone-b ingesters absorb everything.
- Mimir's `token_generation_strategy: spread-minimizing` (with `spread_minimizing_zones`) computes tokens **per zone** for exactly this reason [D].
- Random tokens cost ~10–15% of fleet headroom. That is free money at scale, and the reason to migrate.

### 1.3 Quorum, zone awareness, and what an AZ loss does [D][M]

In classic Mimir a write succeeds when **2 of 3** replicas ack (`(RF/2)+1`). L2 §3:

| Failure | Zone-aware | Zone-unaware |
|---|---|---|
| Whole zone (10 ingesters) down: AZ loss, or a zone-wide rollout | **0.0%** of series fail writes | 23.7% fail |
| 2 random ingesters down | 0.76% fail | 0.71% fail |

- **Zone awareness makes zone-sized failures free.** That is also why Grafana's rollout-operator can restart a *whole zone at once*: rollouts get N× faster.
- **It does not help against two concurrent failures in different zones.** Replica sets containing both lose quorum. Operational rule: **never roll zone b while zone a is degraded.** The rollout-operator enforces this by waiting for zone readiness.
- **Ingest storage moves write availability from ingesters to Kafka.**
  - A write succeeds when Kafka acks; ingesters can all be restarting and writes still succeed [D].
  - Read availability needs at least one healthy ingester per partition in some zone. That is why each partition is consumed by one ingester **per zone**.

### 1.4 Shuffle sharding: blast-radius math [D][M]

`ingestion_tenant_shard_size` (default 0 = all ingesters) gives each tenant a deterministic subset. With zone awareness the subset is spread evenly across zones.

- **Distinct shards.** L2 §4 with shard size 6 (2 per zone of 10): `C(10,2)^3 = 91,125` distinct shards. Among 1,000 tenants, none shares all 6 ingesters with a given noisy tenant.
- **Partial overlap is common.** 396 share one ingester and 265 share two.
- **Blast radius.** If a noisy tenant's 6 ingesters all crash, 33.1% of other tenants lose quorum for *some* of their series. Without shuffle sharding it is 100%.
- **Use it on the read path too.** Shuffle sharding pays off most in the queriers, store-gateways (`store_gateway_tenant_shard_size`) and ruler.
  - A query-of-death from one tenant then crashes only that tenant's querier subset.
  - `querier.shuffle_sharding_ingesters_enabled` defaults to true [D].

### 1.5 Ingest storage (Kafka) in Mimir 3 [D]

From the 3.2.4 architecture docs:

**Write path.**
- Distributors shard each push request across partitions of one Kafka topic.
- A push succeeds when **Kafka brokers confirm the records are replicated and persisted**. "The write path ends at Kafka."

**Consumption.**
- Ingesters consume continuously, **each ingester from exactly one partition**. Multiple ingesters across zones consume the same partition.
- The partition number comes from the instance ID's numeric suffix (`-([0-9]+)$`).
- A hostname that returns an FQDN breaks startup unless you set `-ingester.ring.instance-id`.

**Freshness and recovery.**
- Ingesters commit consumed offsets to a consumer group, replay their WAL on restart, and resume from the committed offset. They never miss a record and see records in partition order.
- Freshness is eventual by default; normal end-to-end ingestion delay is "below 1 second".
- `X-Read-Consistency: strong` makes the query-frontend fetch partition end offsets and ingesters wait to reach them. Use it for rule evaluation and read-after-write tests.

**Why it matters.**

| Concern | Classic | Ingest storage |
|---|---|---|
| A heavy query on an ingester | Can slow or OOM the write path on that ingester | Writes unaffected: they land in Kafka |
| Ingester rollout | Writes need 2/3 replicas up | Writes need Kafka only |
| Replication cost | 3 ingesters ingest every sample (3× CPU/memory) | Kafka replicates bytes; one ingester per zone ingests (zones × CPU) |
| New dependency | — | Kafka-compatible backend (Kafka, WarpStream, Redpanda…), its lag and its bill |
| Read-after-write | Quorum read | Eventual unless `strong` |
| Ingester sizing unit | Series per ingester via ring | Series per partition: plan partitions so a partition fits one ingester |

**Defaults that matter** [D]:
- `ingest_storage.enabled: false`, which must be set explicitly;
- `ingest_storage.kafka.producer_max_buffered_bytes` 1 GiB per distributor;
- `max_consumer_lag_at_startup` 15 s: an ingester is not ready until it is caught up;
- `fetch_concurrency_max` 12;
- `ingestion_concurrency_max` 8.

The mixin pages on `cortex_ingest_storage_reader_receive_delay_seconds` (consumption lag) and on produce-buffer saturation.

### 1.6 The read path [D]

| Stage | Default | Why it matters |
|---|---|---|
| query-frontend split by interval | 24h (`split_queries_by_interval`) | 30-day query → 30 sub-queries, each cacheable |
| query sharding | 16 total shards | Sub-queries run in parallel by series shard |
| results cache | off until configured (`frontend.cache_results`, backend memcached) | Dashboards re-run the same ranges every refresh |
| querier engine | `query_engine: mimir` (MQE, Mimir's streaming engine) | Lower peak memory than the Prometheus engine on wide queries |
| ingesters queried within | 13h (`query_ingesters_within`) | Ingesters hold recent data; TSDB retention in ingesters is 13h |
| store queried after | 12h (`query_store_after`) | Blocks need time to be uploaded, compacted and discovered |
| store-gateway | blocks sharded, RF=3 | Index-headers lazily loaded; tenant shard size limits blast radius |
| limits | `max_fetched_series_per_query` 0 (unlimited), `max_total_query_length` 0 | **Set them.** Unlimited is a query-of-death waiting to happen |

**The 12h/13h overlap is deliberate.** For one hour, data is queryable from both ingesters and blocks, and the querier deduplicates. Shrinking `blocks_storage.tsdb.retention_period` below `query_store_after` + upload + discovery time creates a read gap: data that is in neither place for the querier.

### 1.7 Blocks, compaction and the 3× that the compactor gives back [D][M]

```text
 ingester (each replica / each zone consumer) ── every 2h ──► uploads its OWN block of the tenant's series
          RF=3 (classic) or 3 zones (ingest storage) ⇒ 3 overlapping copies in the bucket
 compactor: block_ranges 2h → 12h → 24h (default)
   level 1: wait first_level_compaction_wait_period (25m) for all replicas' blocks to land
   split-and-merge: compactor_split_groups (1) × compactor_split_and_merge_shards (0 = off)
   VERTICAL compaction: overlapping replica blocks merged, identical samples deduplicated
   retention: compactor_blocks_retention_period (0 = forever); deletion_delay 12h (marks, then deletes)
```

L2 §6: 20M active series at 15 s and ~1.3 B/sample is **139 GiB/day** for one copy.
- The ingesters upload **418 GiB/day**; the compactor brings it back to 139 GiB/day.
- **The compactor is part of the cost model, not a background nicety.** If it falls behind (F4), you pay 3× storage and the store-gateways read 3× the blocks.
- Mimir does not downsample. Long-range queries rely on query sharding, splitting and caching.

### 1.8 Thanos: sidecar, receive, compactor, querier dedup [D][M]

**Sidecar.**
- Prometheus must run with `--storage.tsdb.min-block-duration=2h --storage.tsdb.max-block-duration=2h`. That disables local compaction so uploaded blocks are never rewritten underneath the Thanos compactor.
- The sidecar also exposes recent data via StoreAPI.

**Receive.**
- A remote-write endpoint with its own hashring.
- `ketama` (consistent hashing) "is the recommended algorithm for all new installations". `hashmod` is the historical default; it causes series churn and memory spikes when receivers are added.
- Ketama supports shuffle sharding per tenant.
- Note the retention semantics: `--tsdb.retention` in Receive is per-tenant idle decommission time, unlike Prometheus.

**Compactor.**
- "Must be deployed as a singleton against a bucket" (not concurrency-safe).
- Downsamples raw → 5m for blocks older than **40h**, and 5m → 1h older than **10 days**.
- Retention per resolution: `--retention.resolution-raw|5m|1h`. The default 0d keeps data forever.
- Retention shorter than the next downsampling age deletes data before it can be downsampled.

**Querier dedup.** It merges HA replicas with the **penalty algorithm** ported in L2 §5:

```text
 at each step pick the replica with the smaller next timestamp;
 penalise the OTHER replica: its next Seek starts at lastT + 1 + 2×(Δ of the last two picked samples)
   (5,000 ms before any delta is known)
 ⇒ stays on one replica while it is healthy; switches only when a gap exceeds ~2 scrape intervals
```

- Upstream vectors pass 5/5. The last vector shows a 30 s gap in replica A triggering a switch to B and **staying** on B.
- On an HA pair where A misses 2 minutes, the merged series has 39 samples against A's 32, and its largest gap is 30.7 s.
- Without `--query.replica-label`, every `sum()` counts both replicas (2×).

**The downsampling myth.** The Thanos docs are explicit: downsampling "doesn't save you **any** space". It adds blocks of each resolution, and its goal is fast long-range queries. L2 §6:
- Keeping raw, 5m and 1h for equal retention is **≥ 1.27×** raw storage. That is the sample-count lower bound; the docs warn of up to ~3×, because aggregates compress worse and every resolution carries an index.
- Savings come only from **cutting raw retention**: raw 30d + 5m 90d + 1h 1y is 6.1× cheaper than raw 1y.
- The cost is losing zoom-in on old data.

<!-- listing:ring_lab.py -->
```python
"""ring_lab.py - the scale-out metrics write and read path of Grafana Mimir 3.2 / Thanos 0.42, built
from ports of the upstream code:

  * Mimir's series token: FNV-1 32 over tenant + every label name and value, no separators
    (pkg/mimirpb/fnv.go + series_sharding.go @ mimir-3.2.4);
  * dskit's ring lookup: first token strictly greater than the key, walk clockwise collecting distinct
    instances, one per zone when zone awareness is on (ring/util.go searchToken, ring.go findInstancesForKey);
  * Thanos's penalty-based replica dedup iterator (pkg/dedup/iter.go @ v0.42.5), checked against the five
    upstream TestDedupSeriesIterator vectors.

On top of them it measures token-ownership skew, quorum loss under zone and random failures,
shuffle-sharding blast radius, why RF=3 uploads shrink 3x in the compactor, and what downsampling
really costs in storage. Deterministic, stdlib only.

Usage: python ring_lab.py [target.md]
"""
import bisect
import collections
import itertools
import math
import random
import sys

OFFSET32, PRIME32 = 2166136261, 16777619


def hash_add32(h, s):
    for b in s.encode():
        h = (h * PRIME32) & 0xFFFFFFFF
        h ^= b
    return h


def shard_by_all_labels(tenant, labels):
    """mimirpb.ShardByAllLabelAdapters: FNV-1 32 over tenant, then name, value, name, value..."""
    h = hash_add32(OFFSET32, tenant)
    for name, value in labels:
        h = hash_add32(h, name)
        h = hash_add32(h, value)
    return h


class DskitRing:
    def __init__(self, instances, tokens_per_instance=128, strategy="random", seed=1):
        """instances: list of (name, zone). strategy 'random' = the default token generator;
        'naive-even' = tokens evenly interleaved across ALL instances, ignoring zones;
        'spread' = tokens evenly interleaved within EACH zone (an idealisation of Mimir's
        spread-minimizing strategy, which spreads every zone's tokens independently)."""
        rng = random.Random(seed)
        self.zone = dict(instances)
        toks = []
        n = len(instances)
        by_zone = collections.defaultdict(list)
        for name, z in instances:
            by_zone[z].append(name)
        for idx, (name, z) in enumerate(instances):
            j, nz = by_zone[z].index(name), len(by_zone[z])
            zoff = sorted(by_zone).index(z) / (len(by_zone) * nz * tokens_per_instance)
            for t in range(tokens_per_instance):
                if strategy == "random":
                    tok = rng.getrandbits(32)
                elif strategy == "naive-even":
                    tok = int(((t * n + idx) + 0.5) * (2**32) / (n * tokens_per_instance))
                else:
                    tok = int((((t * nz + j) + 0.5) / (nz * tokens_per_instance) + zoff) * 2**32) % 2**32
                toks.append((tok, name))
        toks.sort()
        self.tokens = [t for t, _ in toks]
        self.owner = [o for _, o in toks]

    def get(self, key, rf=3, zone_aware=True):
        i = bisect.bisect_right(self.tokens, key) % len(self.tokens)     # first token > key
        out, zones = [], set()
        for k in range(len(self.tokens)):
            inst = self.owner[(i + k) % len(self.tokens)]
            if inst in out:
                continue
            if zone_aware and self.zone[inst] in zones:
                continue
            out.append(inst)
            zones.add(self.zone[inst])
            if len(out) == rf:
                break
        return out

    def ownership(self):
        own = collections.Counter()
        for k, tok in enumerate(self.tokens):
            prev = self.tokens[k - 1] if k else self.tokens[-1] - 2**32
            own[self.owner[k]] += (tok - prev) / 2**32
        return own


class Mocked:
    def __init__(self, samples):
        self.s, self.i = samples, -1

    def next(self):
        self.i += 1
        return self.i < len(self.s)

    def seek(self, t):
        if self.i < 0:
            self.i = 0
        while self.i < len(self.s) and self.s[self.i][0] < t:
            self.i += 1
        return self.i < len(self.s)

    def at(self):
        return self.s[self.i]


def thanos_dedup(a_samples, b_samples):
    """Port of dedupSeriesIterator.Next (penalty algorithm, float samples, no counter adjust)."""
    a, b = Mocked(a_samples), Mocked(b_samples)
    aval, bval = a.next(), b.next()
    last_t, pen_a, pen_b, out = None, 0, 0, []
    while True:
        lt = -(2**63) if last_t is None else last_t
        if aval:
            aval = a.seek(lt + 1 + pen_a)
        if bval:
            bval = b.seek(lt + 1 + pen_b)
        if not aval and not bval:
            return out
        if not aval:
            last_t, pen_b = b.at()[0], 0
            out.append(b.at())
            continue
        if not bval:
            last_t, pen_a = a.at()[0], 0
            out.append(a.at())
            continue
        ta, tb = a.at()[0], b.at()[0]
        if ta <= tb:
            pen_b = 5000 if last_t is None else 2 * (ta - last_t)
            pen_a, last_t = 0, ta
            out.append(a.at())
        else:
            pen_a = 5000 if last_t is None else 2 * (tb - last_t)
            pen_b, last_t = 0, tb
            out.append(b.at())


def make_series(n, seed=3):
    rng = random.Random(seed)
    metrics = ["http_server_requests_seconds_bucket", "jvm_memory_used_bytes", "kube_pod_status_phase",
               "container_cpu_usage_seconds_total", "node_network_receive_bytes_total"]
    out = []
    for _ in range(n):
        out.append(sorted([("__name__", rng.choice(metrics)), ("cluster", f"prod-{rng.randrange(4)}"),
                           ("namespace", f"ns-{rng.randrange(60)}"), ("pod", f"pod-{rng.getrandbits(40):010x}"),
                           ("le", rng.choice(["0.1", "0.5", "1", "+Inf"]))]))
    return out


def main():
    checks = []
    print("== 1. The series token (FNV-1 32 over tenant + labels) ==")
    vec = {"": 0x811C9DC5, "a": 0x050C5D7E, "foobar": 0x31F0B262}
    ok = all(hash_add32(OFFSET32, s) == v for s, v in vec.items())
    print(f"FNV-1 32 reference vectors ('', 'a', 'foobar'): {'match' if ok else 'MISMATCH'}")
    s1 = shard_by_all_labels("test", [("__name__", "foo"), ("bar", "baz"), ("sample", "1")])
    s2 = shard_by_all_labels("test", [("__name__", "foo"), ("sample", "1"), ("bar", "baz")])
    print(f"upstream test: same labels in a different order -> different token ({s1:#010x} vs {s2:#010x})")
    c1 = shard_by_all_labels("t", [("__name__", "up"), ("a", "bc")])
    c2 = shard_by_all_labels("t", [("__name__", "up"), ("ab", "c")])
    print(f"no separators: {{a=\"bc\"}} and {{ab=\"c\"}} hash identically ({c1 == c2}) - harmless for placement, "
          f"never use this token as a series ID")
    checks.append(("token port", ok and s1 != s2 and c1 == c2))
    print()

    print("== 2. Token ownership: 30 ingesters in 3 zones, 128 tokens each (Mimir defaults) ==")
    insts = [(f"ingester-zone-{z}-{i}", z) for z in "abc" for i in range(10)]
    rings = {s: DskitRing(insts, 128, s) for s in ("random", "naive-even", "spread")}
    series = make_series(30_000)
    keys = [shard_by_all_labels("tenant-1", s) for s in series]
    skew = {}
    for name, r in rings.items():
        own = r.ownership()
        load = collections.Counter(inst for k in keys for inst in r.get(k))
        mean = sum(load.values()) / len(insts)
        skew[name] = max(load.values()) / mean
        print(f"{name:>10} tokens: ring ownership max/mean {max(own.values()) * 30:.2f}; series per ingester "
              f"(RF=3, zone-aware) max/mean {skew[name]:.2f}, min/mean {min(load.values()) / mean:.2f}")
    checks.append(("per-zone spread beats random beats naive", skew["spread"] < skew["random"] < skew["naive-even"]))
    print("-> the hottest ingester sets the memory limit of the whole fleet. Random tokens leave ~10-15% on the")
    print("   table; tokens that are even globally but ignore zones are far WORSE (with zone-aware replication")
    print("   each zone is effectively its own ring, so the replica in zone b is 'the next zone-b token').")
    print("   Mimir's spread-minimizing strategy spreads each zone's tokens independently.")
    print()

    print("== 3. Quorum (RF=3, 2 of 3 must ack) under failures ==")
    r = rings["random"]
    sets_za = [r.get(k, zone_aware=True) for k in keys]
    sets_nz = [r.get(k, zone_aware=False) for k in keys]

    def lost(sets, down):
        return sum(sum(i in down for i in s) >= 2 for s in sets) / len(sets)
    zone_a = {n for n, z in insts if z == "a"}
    print(f"whole zone a down (10 ingesters, e.g. a rollout or AZ loss): zone-aware {lost(sets_za, zone_a):.1%} "
          f"of series fail writes; zone-unaware {lost(sets_nz, zone_a):.1%}")
    rng = random.Random(9)
    trials = [set(rng.sample([n for n, _ in insts], 2)) for _ in range(100)]
    two_za = sum(lost(sets_za, d) for d in trials) / len(trials)
    two_nz = sum(lost(sets_nz, d) for d in trials) / len(trials)
    print(f"2 random ingesters down: zone-aware {two_za:.2%} of series fail on average; zone-unaware {two_nz:.2%}")
    checks.append(("zone awareness survives an AZ", lost(sets_za, zone_a) == 0 and lost(sets_nz, zone_a) > 0.05))
    print("-> zone awareness turns 'an AZ is down' into a non-event, and lets you roll a whole zone at once")
    print("   (rollout-operator). Two failures in two different zones still lose quorum for the series whose")
    print("   replica sets contain both: never run a rollout in one zone while another zone is degraded.")
    print()

    print("== 4. Shuffle sharding: 1,000 tenants, shard size 6 (2 per zone) out of 30 ingesters ==")
    rng = random.Random(4)
    per_zone = {z: [n for n, zz in insts if zz == z] for z in "abc"}
    shards = [frozenset(x for z in "abc" for x in rng.sample(per_zone[z], 2)) for _ in range(1000)]
    distinct = math.comb(10, 2) ** 3
    victim = shards[0]
    overlap = collections.Counter(len(victim & s) for s in shards[1:])
    hit_quorum = sum(1 for s in shards[1:] if sum(1 for z in "abc" if victim & s & set(per_zone[z])) >= 2)
    print(f"possible shards C(10,2)^3 = {distinct:,}; tenants sharing ALL 6 ingesters with a noisy tenant: "
          f"{overlap.get(6, 0)}")
    print(f"overlap with the noisy tenant's shard: " + ", ".join(f"{k} ingesters: {v}" for k, v in sorted(overlap.items())))
    print(f"if the noisy tenant's 6 ingesters all crash, tenants that lose quorum somewhere (an overlapping")
    print(f"ingester in >= 2 zones): {hit_quorum} of 999 ({hit_quorum / 999:.1%}); without shuffle sharding: 999 of 999")
    checks.append(("shuffle sharding contains blast radius", overlap.get(6, 0) == 0 and hit_quorum < 400))
    print()

    print("== 5. Thanos querier dedup (port of the penalty iterator @ v0.42.5) ==")
    S = lambda *p: list(p)  # noqa: E731
    cases = [
        (S((10000, 10), (20000, 11), (30000, 12), (40000, 13)), S((10000, 20), (20000, 21), (30000, 22), (40000, 23)),
         S((10000, 10), (20000, 11), (30000, 12), (40000, 13))),
        (S((10100, 1), (20100, 1), (30100, 1), (40100, 1)), S((10000, 2), (20000, 2), (30000, 2), (40000, 2)),
         S((10000, 2), (20000, 2), (30000, 2), (40000, 2))),
        (S((10000, 1), (20000, 1), (40000, 1)), S((10000, 2), (20000, 2), (30000, 2), (40000, 2)),
         S((10000, 1), (20000, 1), (40000, 1))),
        (S((10000, 1), (20000, 1), (40000, 1)), S((15000, 2), (25000, 2), (35000, 2), (45000, 2)),
         S((10000, 1), (20000, 1), (40000, 1))),
        (S((10000, 1), (20000, 1), (30000, 1), (60000, 1), (70000, 1)),
         S((10100, 2), (20100, 2), (30100, 2), (40100, 2), (50100, 2), (60100, 2)),
         S((10000, 1), (20000, 1), (30000, 1), (50100, 2), (60100, 2))),
    ]
    passed = sum(thanos_dedup(a, b) == exp for a, b, exp in cases)
    print(f"upstream TestDedupSeriesIterator vectors: {passed}/{len(cases)}")
    checks.append(("thanos dedup vectors", passed == len(cases)))
    a = [(t * 15000, 1.0) for t in range(40) if not 10 <= t < 18]      # replica A misses 2 minutes (restart)
    b = [(t * 15000 + 700, 1.0) for t in range(40)]
    d = thanos_dedup(a, b)
    gaps = max(y[0] - x[0] for x, y in zip(d, d[1:]))
    print(f"HA pair, replica A down for 2 min: merged series has {len(d)} samples (A alone {len(a)}), largest gap "
          f"{gaps / 1000:.1f}s; without --query.replica-label every sum() counts both replicas (2x)")
    print()

    print("== 6. Object storage: RF=3 uploads, vertical compaction, and the downsampling myth ==")
    active, bytes_per_sample, scrape = 20_000_000, 1.3, 15
    raw_day = active * 86400 / scrape * bytes_per_sample / 2**30
    print(f"{active / 1e6:.0f}M active series @ {scrape}s, ~{bytes_per_sample} B/sample: one copy = {raw_day:,.0f} GiB/day")
    print(f"  ingesters upload RF=3 copies (2h blocks): {3 * raw_day:,.0f} GiB/day lands in the bucket;")
    print(f"  compactor vertical-compacts the replicas:  {raw_day:,.0f} GiB/day after dedup (3x saving)")
    per5m, per1h = 300 // scrape, 3600 // scrape
    agg = 5   # count, sum, min, max, counter per window
    ratio5, ratio1h = agg / per5m, agg / per1h
    keep_all = 1 + ratio5 + ratio1h
    print(f"Thanos downsampling stores {agg} aggregates per window: 5m blocks = {ratio5:.2f}x raw samples, "
          f"1h = {ratio1h:.3f}x")
    print(f"  keep raw + 5m + 1h for the same retention: >= {keep_all:.2f}x the storage of raw alone (it GROWS; this is")
    print(f"  the sample-count lower bound - aggregates compress worse and every resolution carries its own index,")
    print(f"  which is why the Thanos docs warn of up to ~3x)")
    raw30_5m90_1h1y = 30 + 90 * ratio5 + 365 * ratio1h
    print(f"  raw 30d + 5m 90d + 1h 1y = {raw30_5m90_1h1y:.0f} raw-day equivalents vs raw 1y = 365 -> "
          f"{365 / raw30_5m90_1h1y:.1f}x cheaper only because raw retention is cut")
    checks.append(("downsampling grows storage at equal retention", keep_all > 1.0 and 365 / raw30_5m90_1h1y > 5))
    print()

    failed = [n for n, ok in checks if not ok]
    print(f"checks: {len(checks) - len(failed)}/{len(checks)} passed")
    print("verdict: OK" if not failed else f"verdict: FAIL {failed}")
    return 0 if not failed else 1


if __name__ == "__main__":
    sys.exit(main())
```

<!-- output:ring_lab.py -->
```text
== 1. The series token (FNV-1 32 over tenant + labels) ==
FNV-1 32 reference vectors ('', 'a', 'foobar'): match
upstream test: same labels in a different order -> different token (0x348c3619 vs 0xd97c92ad)
no separators: {a="bc"} and {ab="c"} hash identically (True) - harmless for placement, never use this token as a series ID

== 2. Token ownership: 30 ingesters in 3 zones, 128 tokens each (Mimir defaults) ==
    random tokens: ring ownership max/mean 1.10; series per ingester (RF=3, zone-aware) max/mean 1.12, min/mean 0.84
naive-even tokens: ring ownership max/mean 1.00; series per ingester (RF=3, zone-aware) max/mean 7.01, min/mean 0.32
    spread tokens: ring ownership max/mean 1.00; series per ingester (RF=3, zone-aware) max/mean 1.02, min/mean 0.97
-> the hottest ingester sets the memory limit of the whole fleet. Random tokens leave ~10-15% on the
   table; tokens that are even globally but ignore zones are far WORSE (with zone-aware replication
   each zone is effectively its own ring, so the replica in zone b is 'the next zone-b token').
   Mimir's spread-minimizing strategy spreads each zone's tokens independently.

== 3. Quorum (RF=3, 2 of 3 must ack) under failures ==
whole zone a down (10 ingesters, e.g. a rollout or AZ loss): zone-aware 0.0% of series fail writes; zone-unaware 23.7%
2 random ingesters down: zone-aware 0.76% of series fail on average; zone-unaware 0.71%
-> zone awareness turns 'an AZ is down' into a non-event, and lets you roll a whole zone at once
   (rollout-operator). Two failures in two different zones still lose quorum for the series whose
   replica sets contain both: never run a rollout in one zone while another zone is degraded.

== 4. Shuffle sharding: 1,000 tenants, shard size 6 (2 per zone) out of 30 ingesters ==
possible shards C(10,2)^3 = 91,125; tenants sharing ALL 6 ingesters with a noisy tenant: 0
overlap with the noisy tenant's shard: 0 ingesters: 252, 1 ingesters: 396, 2 ingesters: 265, 3 ingesters: 74, 4 ingesters: 12
if the noisy tenant's 6 ingesters all crash, tenants that lose quorum somewhere (an overlapping
ingester in >= 2 zones): 331 of 999 (33.1%); without shuffle sharding: 999 of 999

== 5. Thanos querier dedup (port of the penalty iterator @ v0.42.5) ==
upstream TestDedupSeriesIterator vectors: 5/5
HA pair, replica A down for 2 min: merged series has 39 samples (A alone 32), largest gap 30.7s; without --query.replica-label every sum() counts both replicas (2x)

== 6. Object storage: RF=3 uploads, vertical compaction, and the downsampling myth ==
20M active series @ 15s, ~1.3 B/sample: one copy = 139 GiB/day
  ingesters upload RF=3 copies (2h blocks): 418 GiB/day lands in the bucket;
  compactor vertical-compacts the replicas:  139 GiB/day after dedup (3x saving)
Thanos downsampling stores 5 aggregates per window: 5m blocks = 0.25x raw samples, 1h = 0.021x
  keep raw + 5m + 1h for the same retention: >= 1.27x the storage of raw alone (it GROWS; this is
  the sample-count lower bound - aggregates compress worse and every resolution carries its own index,
  which is why the Thanos docs warn of up to ~3x)
  raw 30d + 5m 90d + 1h 1y = 60 raw-day equivalents vs raw 1y = 365 -> 6.1x cheaper only because raw retention is cut

checks: 6/6 passed
verdict: OK
```

---

## 2. Production-hardened configurations and code blueprints

### 2.1 Mimir 3.2 — ingest storage, zone-aware, spread-minimizing tokens (single YAML, microservices targets)

```yaml
# mimir.yaml — shared by all components; each Deployment/StatefulSet sets -target=<component>.
# Paths verified against cmd/mimir/config-descriptor.json @ mimir-3.2.4.
# ${ZONE} needs -config.expand-env=true and a per-zone StatefulSet that sets ZONE.
multitenancy_enabled: true
common:
  storage:
    backend: s3
    s3:
      endpoint: s3.us-east-1.amazonaws.com
      region: us-east-1
blocks_storage:
  s3:
    bucket_name: acme-mimir-blocks
  tsdb:
    dir: /data/tsdb
    retention_period: 13h
  bucket_store:
    sync_dir: /data/tsdb-sync
ruler_storage:
  s3:
    bucket_name: acme-mimir-ruler
alertmanager_storage:
  s3:
    bucket_name: acme-mimir-alertmanager
memberlist:
  join_members:
    - dns+mimir-gossip-ring.mimir.svc.cluster.local:7946
ingest_storage:
  enabled: true
  kafka:
    address: kafka-bootstrap.kafka.svc:9092
    topic: mimir-ingest
    auto_create_topic_enabled: false
ingester:
  ring:
    replication_factor: 3
    zone_awareness_enabled: true
    instance_availability_zone: ${ZONE}
    token_generation_strategy: spread-minimizing
    spread_minimizing_zones: [zone-a, zone-b, zone-c]
    spread_minimizing_join_ring_in_order: true
distributor:
  ha_tracker:
    enable_ha_tracker: true
    kvstore:
      store: memberlist
store_gateway:
  sharding_ring:
    replication_factor: 3
    zone_awareness_enabled: true
    instance_availability_zone: ${ZONE}
frontend:
  cache_results: true
  results_cache:
    backend: memcached
    memcached:
      addresses: dns+memcached-frontend.mimir.svc:11211
compactor:
  data_dir: /data/compactor
  block_ranges: [2h, 12h, 24h]
limits:
  ingestion_rate: 400000
  ingestion_burst_size: 4000000
  max_global_series_per_user: 3000000
  max_label_names_per_series: 30
  ingestion_tenant_shard_size: 0
  store_gateway_tenant_shard_size: 0
  accept_ha_samples: true
  ha_cluster_label: cluster
  ha_replica_label: __replica__
  out_of_order_time_window: 10m
  max_fetched_series_per_query: 250000
  max_total_query_length: 32d
  compactor_split_and_merge_shards: 4
  compactor_split_groups: 4
  compactor_blocks_retention_period: 400d
```

```yaml
# runtime.yaml — per-tenant overrides, reloaded without restart (-runtime-config.file).
overrides:
  team-checkout:
    ingestion_rate: 1500000
    ingestion_burst_size: 15000000
    max_global_series_per_user: 12000000
    ingestion_tenant_shard_size: 18
    store_gateway_tenant_shard_size: 6
    compactor_split_and_merge_shards: 8
  batch-analytics:
    max_global_series_per_user: 500000
    max_fetched_series_per_query: 50000
    max_total_query_length: 8d
    ingestion_tenant_shard_size: 6
    compactor_blocks_retention_period: 30d
```

**Why these lines.**
- **Shard sizes.** `ingestion_tenant_shard_size` and `store_gateway_tenant_shard_size` are zero globally (small tenants get everything) and set **per large or risky tenant** (§1.4).
- **HA tracker.** Its KV defaults to memberlist in 3.x [D]. `accept_ha_samples` plus the `cluster`/`__replica__` labels let one HA Prometheus pair write without doubling series.
- **Query limits.** `max_fetched_series_per_query` and `max_total_query_length` are set, because unlimited is the default.
- **Compactor sharding.** Split-and-merge shards scale it for tenants above roughly 8–10M series ⚠ (sizing guidance varies by release).
- **Ingester instance IDs.** They must end in `-<partition>` (§1.5). The StatefulSet names `ingester-zone-a`, `-zone-b` and `-zone-c` give `ingester-zone-a-7` and so on.

### 2.2 Prometheus → Mimir remote write (HA pair)

```yaml
# prometheus.yml (replica A; replica B identical except __replica__)
global:
  scrape_interval: 15s
  external_labels:
    cluster: prod-use1
    __replica__: prometheus-a
remote_write:
  - url: http://mimir-distributor.mimir.svc:8080/api/v1/push
    headers:
      X-Scope-OrgID: team-checkout
    send_native_histograms: true
    send_exemplars: true
    queue_config:
      capacity: 10000
      max_shards: 200
      min_shards: 4
      max_samples_per_send: 2000
      batch_send_deadline: 5s
      min_backoff: 30ms
      max_backoff: 5s
      retry_on_http_429: true
    write_relabel_configs:
      - source_labels: [__name__]
        regex: 'go_gc_.*|go_memstats_.*_total|scrape_.*'
        action: drop
```

- `retry_on_http_429: true`. Prometheus's default is false (Folder 01 file 04) [D]. Without it, 429s from Mimir's ingestion-rate limiter drop data instead of backing off.
- The HA tracker accepts samples from one replica per `cluster`. On failover after `ha_tracker_failover_timeout` (30 s), the other replica's samples are accepted.

### 2.3 Thanos — sidecar, compactor, querier, receive hashring

```yaml
# Prometheus container args (sidecar mode): local compaction OFF so uploaded blocks are immutable.
args:
  - --storage.tsdb.path=/prometheus
  - --storage.tsdb.retention.time=24h
  - --storage.tsdb.min-block-duration=2h
  - --storage.tsdb.max-block-duration=2h
  - --web.enable-lifecycle
---
# Thanos sidecar container args
sidecarArgs:
  - sidecar
  - --tsdb.path=/prometheus
  - --prometheus.url=http://localhost:9090
  - --objstore.config-file=/etc/thanos/objstore.yaml
  - --grpc-address=0.0.0.0:10901
---
# Thanos compactor: ONE replica per bucket, never two.
compactorArgs:
  - compact
  - --wait
  - --wait-interval=5m
  - --data-dir=/data
  - --objstore.config-file=/etc/thanos/objstore.yaml
  - --retention.resolution-raw=30d
  - --retention.resolution-5m=120d
  - --retention.resolution-1h=2y
  - --deduplication.replica-label=prometheus_replica
  - --compact.concurrency=4
  - --downsample.concurrency=2
  - --delete-delay=48h
---
# Thanos querier: dedup HA replicas at query time.
querierArgs:
  - query
  - --query.replica-label=prometheus_replica
  - --endpoint=dnssrv+_grpc._tcp.thanos-sidecar.monitoring.svc
  - --endpoint=dnssrv+_grpc._tcp.thanos-store.monitoring.svc
  - --query.auto-downsampling
```

```json
[
  {
    "hashring": "default",
    "algorithm": "ketama",
    "endpoints": [
      {"address": "thanos-receive-0.thanos-receive.monitoring.svc:10901", "az": "use1-az1"},
      {"address": "thanos-receive-1.thanos-receive.monitoring.svc:10901", "az": "use1-az2"},
      {"address": "thanos-receive-2.thanos-receive.monitoring.svc:10901", "az": "use1-az4"},
      {"address": "thanos-receive-3.thanos-receive.monitoring.svc:10901", "az": "use1-az1"},
      {"address": "thanos-receive-4.thanos-receive.monitoring.svc:10901", "az": "use1-az2"},
      {"address": "thanos-receive-5.thanos-receive.monitoring.svc:10901", "az": "use1-az4"}
    ]
  }
]
```

- `--deduplication.replica-label` in the compactor is **irreversible** vertical dedup of replica blocks [D]. Enable it only when you trust the replicas to be equivalent.
- Raw retention of 30d exceeds 40h, and 5m retention of 120d exceeds 10d, so every block is downsampled before deletion [D].

### 2.4 PromQL that runs the platform (metric names from the Mimir 3.2.4 mixin)

```promql
# Ingest-storage consumption lag per ingester (mixin pages above ~2 minutes)
histogram_avg(sum by (pod) (rate(cortex_ingest_storage_reader_receive_delay_seconds{phase="running"}[1m])))

# Samples rejected, by reason (rate limit, series limit, OOO, label validation)
sum by (reason, user) (rate(cortex_discarded_samples_total[5m]))

# Hottest ingester vs mean in-memory series (token skew; §1.2)
max(cortex_ingester_memory_series) / avg(cortex_ingester_memory_series)

# Compactor has not completed a run in 24h (3x storage and slow store-gateways follow)
time() - max(cortex_compactor_last_successful_run_timestamp_seconds) > 24 * 3600

# Ingester has not shipped a block for 4h (data stuck on local disk)
min by (pod) (time() - cortex_ingester_shipper_last_successful_upload_timestamp_seconds) > 4 * 3600

# Store-gateway not synced with the bucket for 30m (queries miss recent blocks)
time() - cortex_bucket_stores_blocks_last_successful_sync_timestamp_seconds{component="store-gateway"} > 1800

# Object-store failure ratio by operation
sum by (operation) (rate(thanos_objstore_bucket_operation_failures_total[5m]))
  / sum by (operation) (rate(thanos_objstore_bucket_operations_total[5m]))
```

The first expression assumes the delay metric is a native histogram (the mixin handles both classic and native variants) ⚠.

---

## 3. Failure modes and FinOps debugging

### F1. One ingester OOMs repeatedly while others idle

**Symptom.** The same ingester restarts with OOMKilled. The others sit at 60% memory.

**Signature.** `max(cortex_ingester_memory_series)/avg(...)` ≈ 1.2–1.4. Tokens are `random`. Or a custom token layout ignores zones (L2 §2: 7×).

**Root cause.** Ownership skew: the fleet is sized by the mean but fails at the max.

**Fix.** Migrate to `spread-minimizing` tokens with `spread_minimizing_zones` (rolling, zone by zone). Meanwhile, size limits for the max.

**Prevention.** Alert on skew above 1.15. Capacity-plan on p100 instance load.

### F2. A full-AZ outage still drops writes

**Symptom.** One AZ goes down and remote-write error rates hit 20–25%.

**Signature.** `zone_awareness_enabled: false`, or `instance_availability_zone` left empty on some pods so they register in the "" zone.

**Root cause.** Replica sets contain two instances in the failed zone (L2 §3: 23.7%).

**Fix.** Enable zone awareness with a correct zone on every pod. Use one StatefulSet per zone, each pinned by `nodeAffinity` to `topology.kubernetes.io/zone` and passing its zone in args. That is the layout the rollout-operator expects.

**Prevention.** Run a chaos test that drains a zone. Lint that `count by (zone)` of ring members is equal.

### F3. Writes rejected after a dashboard rollout (classic architecture)

**Symptom.** 5xx on push during a spike of heavy dashboard queries.

**Signature.** Ingester CPU is saturated by query load. Push latency rises, then quorum failures follow.

**Root cause.** In classic architecture ingesters serve both reads and writes, so reads starve writes.

**Fix.**
- Short term: query limits (`max_fetched_series_per_query`), results cache, query sharding, and querier shuffle sharding.
- Structural: migrate to ingest storage, where writes end at Kafka (§1.5).

**Prevention.** Load-test the query path. Track the push p99 SLO separately from the query SLO.

### F4. Bucket costs triple and long-range queries crawl

**Symptom.** The object-storage bill rises month over month. Store-gateway latency grows.

**Signature.**
- `cortex_compactor_last_successful_run_timestamp_seconds` is stale.
- The bucket index shows many overlapping 2h blocks per tenant.
- Compactor logs show halted or failed compactions (corrupt block, out-of-order chunks).

**Root cause.**
- The compactor is behind or halted, so RF=3 copies are never vertically compacted (L2 §6: 418 vs 139 GiB/day).
- Store-gateways scan 3× the blocks.

**Fix.**
- Investigate halted groups.
- Mark corrupt blocks no-compact (with the tooling, after inspection).
- Increase split-and-merge shards for large tenants.
- Give the compactor disk headroom: roughly 2× the largest group.

**Prevention.** Page on the compactor's last successful run. Track bucket bytes per tenant per day against `active_series × B/sample × 86400 / scrape_interval`.

### F5. Thanos: two compactors corrupt a bucket

**Symptom.** Overlapping blocks, query errors about duplicate series, and blocks vanishing.

**Signature.** Two compactor pods were running (rollout `maxSurge`, or two clusters pointing at one bucket).

**Root cause.** The compactor is not concurrency-safe and "must be deployed as a singleton against a bucket" [D].

**Fix.**
- Use `replicas: 1` with a `Recreate` strategy.
- Give each cluster a separate bucket or prefix.
- Repair with `thanos tools bucket verify` and the repair procedures.

**Prevention.** An admission policy forbids `replicas > 1` for the compactor. Alert on halted compaction.

### F6. Downsampling "to save money" increased the bill

**Symptom.** Storage grew 30–100% after enabling downsampling.

**Signature.** Equal retention for raw, 5m and 1h. New blocks appear at three resolutions.

**Root cause.** Downsampling adds blocks and never replaces raw (L2 §6: ≥ 1.27×, up to ~3× per the docs).

**Fix.** Decide on zoom-in requirements, then cut raw retention (e.g. raw 30d, 5m 120d, 1h 2y) while respecting the 40h/10d minimums.

**Prevention.** Run storage forecasts per resolution before changing retention flags. Document the zoom-in policy.

### F7. Ingest storage: ingesters "healthy" but data minutes stale

**Symptom.** Alerts evaluate on stale data. Dashboards lag by minutes during a write spike.

**Signature.** `cortex_ingest_storage_reader_receive_delay_seconds` is rising. Kafka partition lag grows on some partitions. An ingester recently restarted and is replaying.

**Root cause.**
- The read path is eventually consistent.
- An ingester consuming a hot partition can't keep up (`ingestion_concurrency_max`, CPU).
- Too few partitions for the series volume.

**Fix.**
- Scale partitions and ingesters together.
- Raise ingestion concurrency.
- Use `X-Read-Consistency: strong` for the ruler, which trades latency for correctness.

**Prevention.** Mixin alerts on receive delay. Partition planning: series per partition must fit one ingester with headroom.

### F8. HA pair doubles every series

**Symptom.** Active series doubled after adding a second Prometheus. Rates are 2× in Grafana.

**Signature.** Both replicas' series are present. They differ only by a replica label, or by none if `external_labels` are identical, which produces duplicate-sample errors instead.

**Root cause.** Neither HA dedup (Mimir HA tracker; Thanos `--query.replica-label`) nor compactor dedup is configured.

**Fix.** Mimir: `accept_ha_samples` with `cluster`/`__replica__` labels. Thanos: querier `--query.replica-label` plus compactor `--deduplication.replica-label`.

**Prevention.** Run a recording-rule check on `count by (cluster) (up)` against the expected target count per cluster.

---

## 4. L7 bar-raiser Q&A chains

<details><summary><b>Q1 · "Explain Mimir's write path and where a sample can be lost."</b></summary>

**Initial Prompt.** From Prometheus remote_write to S3.

**L5 Textbook Answer.** The distributor hashes the series to 3 ingesters, they write to the WAL and upload blocks to S3 every 2 hours.

**Why L5 Fails at 3 AM or on the Bill.** It misses:
- client-side drops (`retry_on_http_429` false by default, queue overflow);
- distributor rejects (rate and series limits, label validation; see `cortex_discarded_samples_total`);
- quorum failures during a zone event;
- WAL on non-persistent disks;
- ingester shipping stalls;
- a compactor that never runs.

**L7 Principal Defense.** I'd walk it hop by hop, with the counter that proves each hop.
- **Client.** WAL-backed queue; `prometheus_remote_storage_samples_failed_total`.
- **Distributor.** Validation and limits by reason; HA-tracker dedup.
- **Placement.** Token = FNV-1(tenant, sorted labels), then the ring, then a 2/3 quorum in classic. In ingest storage, Kafka ack is the commit point.
- **Ingester.** Persistent WAL (PVC); 2h block cut; shipper upload metric.
- **Compactor.** Vertical dedup of the 3 copies, which is the 3× storage lever.
- **Store-gateway.** Bucket sync.

Each hop has a "last successful" timestamp alert, and the per-tenant conservation check is samples received ≈ samples ingested + discarded.
</details>

<details><summary><b>Q2 · "Why would you move to Mimir's ingest storage?"</b></summary>

**Initial Prompt.** Classic architecture works fine.

**L5 Textbook Answer.** Kafka makes it more scalable.

**Why L5 Fails at 3 AM or on the Bill.** It's vague about what problem is solved, and it ignores the new failure surface: Kafka lag, partition planning, eventual reads and the Kafka bill.

**L7 Principal Defense.**
- **The problem.** In classic, ingesters serve reads and writes, so a query storm can fail pushes (F3). Rollouts also need quorum.
- **What ingest storage does.** It moves the write commit point to Kafka: writes succeed while every ingester restarts. Each partition is read by one ingester per zone, so ingestion work is zones× rather than RF× across a quorum, and queries can't hurt writes.
- **What I'd plan.**
  - partitions sized to series per ingester;
  - instance IDs ending in the partition number;
  - strong consistency for the ruler;
  - receive-delay alerts;
  - a Kafka-compatible backend whose cost I compare against the ingester memory/CPU saved.
- **Migration.** Follow the documented migration path with dual-write first (`distributor_send_to_ingesters_enabled` during migration [D]).
</details>

<details><summary><b>Q3 · "Our ingesters are unevenly loaded. Fix it."</b></summary>

**Initial Prompt.** Max is 1.3× mean.

**L5 Textbook Answer.** Increase `num_tokens` so the distribution evens out.

**Why L5 Fails at 3 AM or on the Bill.** More random tokens converge slowly: variance falls only as 1/√tokens. Changing tokens reshuffles ownership, a big rebalance. And a naïve "even" layout that ignores zones is far worse (L2 §2: 7×).

**L7 Principal Defense.**
- Measure the skew from `cortex_ingester_memory_series`.
- Move to `spread-minimizing` tokens computed per zone (1.02× in L2), rolling zone by zone with `spread_minimizing_join_ring_in_order`.
- Check for tenant-level hotspots that tokens can't fix: one tenant with a shard size of 3 holding 10M series. Raise that tenant's shard size.
- Under ingest storage, the unit is partitions: rebalance by partition count, not tokens.
</details>

<details><summary><b>Q4 · "How does shuffle sharding protect tenants, quantitatively?"</b></summary>

**Initial Prompt.** One tenant's cardinality bomb took down the cluster.

**L5 Textbook Answer.** Give each tenant a subset of ingesters.

**Why L5 Fails at 3 AM or on the Bill.** Without numbers you can't size shards or explain residual risk. Overlaps are common, and a crash of all of one tenant's shard still breaks others' quorum for some series.

**L7 Principal Defense.**
- With 30 ingesters (2 per zone per tenant) there are 91,125 distinct shards. In L2 §4 no tenant shared all 6 with the noisy one.
- If its 6 ingesters crash, 33% of tenants lose quorum on *some* series, versus 100% without shuffle sharding.
- Better still, limits prevent the crash: `max_global_series_per_user`, ingester instance limits, circuit breakers.
- Read-path shuffle sharding (queriers, store-gateways) is where query-of-death isolation really happens.
- I'd also set per-tenant OOO windows and label limits so one bad producer can't poison shared components.
</details>

<details><summary><b>Q5 · "Thanos or Mimir?"</b></summary>

**Initial Prompt.** We have 40 Prometheus servers in 12 clusters.

**L5 Textbook Answer.** Thanos because it's simpler: just add a sidecar.

**Why L5 Fails at 3 AM or on the Bill.**
- The sidecar model fans every query out to 40 sidecars plus stores, so tail latency follows the slowest cluster.
- The compactor singleton is a scaling ceiling.
- Multi-tenancy and limits are thin.
- Downsampling doesn't save space (F6).

**L7 Principal Defense.** Decide on operating model.
- **Thanos sidecar** fits when you want global view and long retention with minimal central infrastructure, and you accept fan-out query latency.
- **Mimir (or Thanos Receive)** fits when you want a central multi-tenant write path, per-tenant limits, query sharding, results caching and horizontal compaction (split-and-merge).
- **At 40 servers and growing**, I'd centralise: remote-write to Mimir with HA tracking, tenants per team, shuffle sharding for big tenants. I'd keep a short local retention for each Prometheus as an outage buffer.
</details>

<details><summary><b>Q6 · "Explain Thanos query dedup and its failure modes."</b></summary>

**Initial Prompt.** Two replicas scrape the same targets.

**L5 Textbook Answer.** Thanos removes the replica label and merges series.

**Why L5 Fails at 3 AM or on the Bill.** It doesn't say *how* samples are chosen. Naïve interleaving doubles the sample rate and makes `rate()` and counters noisy. Switching replicas on a counter can also make it appear to go backwards.

**L7 Principal Defense.**
- **Penalty algorithm** (ported in L2 §5): take the replica with the earliest next sample, and push the other replica's next seek out by 2× the last delta. You stay on one replica while it's healthy and switch only after a gap above ~2 intervals. A 30 s gap triggers a switch and you stay on the new replica.
- **Counters.** The counter iterator adds an offset when the newly chosen replica's value is lower, so `rate()` doesn't see a fake reset.
- **Residual issue.** Replicas scrape at different phases, so a switch shifts timestamps by up to one interval. Alerts with tight `for` windows should use recording rules evaluated on one replica (or Mimir's HA tracker, which dedups at ingest).
</details>

<details><summary><b>Q7 · "Estimate the object-storage bill for 50M active series."</b></summary>

**Initial Prompt.** 15 s scrape, 13 months retention, S3.

**L5 Textbook Answer.** 50M × 5,760 samples/day × 2 bytes × 395 days.

**Why L5 Fails at 3 AM or on the Bill.**
- It ignores RF=3 uploads before compaction, the index overhead and the compactor lag risk (F4).
- It ignores request costs (store-gateway GETs).
- It assumes downsampling helps.

**L7 Principal Defense.**
- **Samples.** 50M × 5,760/day × ~1.3 B/sample (Gorilla in practice) ≈ 349 GiB/day per copy. 13 months ≈ 135 TiB after compaction, plus ~10–20% for the index.
- **Transient.** About 3× for the 2h–24h window before vertical compaction: roughly 0.7 TiB/day of redundant uploads, which compaction removes.
- **Price.** At S3 Standard ~$0.023/GB-month ⚠ that is about $3.4k/month at steady state, and storage is the cheap part.
- **Watch instead.**
  - GET/LIST request volume from store-gateways (cache index-headers, postings and chunks in memcached);
  - cross-AZ transfer between zones;
  - compactor CPU.
- **Levers.** Retention per tenant (`compactor_blocks_retention_period`), dropping unused series at ingest (Folder 08), and native histograms instead of classic buckets.
</details>

<details><summary><b>Q8 · "Why does Mimir query the ingesters for 13h but the store after 12h?"</b></summary>

**Initial Prompt.** Seems redundant.

**L5 Textbook Answer.** For safety.

**Why L5 Fails at 3 AM or on the Bill.** Changing either value without understanding the block timeline creates a window where recent data is in neither place for the querier: a read gap that looks like an outage on dashboards.

**L7 Principal Defense.** I'd trace the block timeline.
- Head compaction cuts 2h blocks.
- Upload completes within minutes.
- Store-gateways discover it within their sync interval plus bucket-index update.
- Index-headers load.
- Ingesters keep blocks for `retention_period` (13h) so queriers can still read them from ingesters until store-gateways surely have them. The 1h overlap covers upload and discovery delays, and the querier deduplicates.
- **Rule:** `query_store_after` < ingester retention − (upload + sync + index-header load), with margin.
- If I shorten ingester retention to save disk, I move `query_store_after` down and verify store-gateway sync latency first.
</details>

<details><summary><b>Q9 · "Thanos Receive: hashmod or ketama, and how do you scale it?"</b></summary>

**Initial Prompt.** We need to add receivers.

**L5 Textbook Answer.** Add endpoints to the hashring file.

**Why L5 Fails at 3 AM or on the Bill.** With `hashmod`, adding a receiver remaps most series: L1 in file 01 measured 79–80% for `mod N`. Every receiver then creates new head series, and memory spikes cluster-wide; the docs call this out explicitly.

**L7 Principal Defense.**
- Use `ketama` (consistent hashing; about 1/N of series move) with AZ-aware endpoints and a replication factor.
- Scale in small steps, off-peak, watching head series and WAL size.
- Migrating from `hashmod` means a new receiver pool on ketama and moving writers over, as documented, rather than flipping the algorithm in place.
- Per-tenant shuffle sharding for large tenants comes through ketama's `shuffle_sharding_config`.
</details>

---

## 5. Invariants checklist

- [ ] Zone awareness is on, every pod carries its real zone, and `count by (zone)` of ring members is balanced.
- [ ] Tokens use the `spread-minimizing` strategy (per zone), or ingester skew is monitored and capacity is sized for the max.
- [ ] Large and risky tenants have explicit ingestion, store-gateway and query shard sizes and limits; global query limits are non-zero.
- [ ] HA pairs are deduplicated at ingest (HA tracker) or at query and compaction (Thanos replica labels).
- [ ] The compactor's last successful run pages at 24h; bucket bytes per tenant are reconciled against the active-series model.
- [ ] The Thanos compactor is a singleton per bucket (`replicas: 1`, `Recreate`).
- [ ] Downsampling retention honours 40h/10d, and the zoom-in policy is documented; nobody expects downsampling to save space.
- [ ] Ingest storage: instance IDs end in `-<partition>`, receive-delay alerts exist, the ruler uses strong consistency, and partitions are planned for series per ingester.
- [ ] `query_store_after` and ingester retention leave an overlap that covers upload + sync + index-header load.

---

## 6. References

- Mimir ingest storage architecture (3.2.4 docs source): <https://github.com/grafana/mimir/blob/mimir-3.2.4/docs/sources/mimir/get-started/about-grafana-mimir-architecture/about-ingest-storage-architecture/index.md>
- Mimir configuration descriptor (defaults): <https://github.com/grafana/mimir/blob/mimir-3.2.4/cmd/mimir/config-descriptor.json>
- Mimir series sharding and FNV: <https://github.com/grafana/mimir/blob/mimir-3.2.4/pkg/mimirpb/series_sharding.go> · <https://github.com/grafana/mimir/blob/mimir-3.2.4/pkg/mimirpb/fnv.go>
- dskit ring: <https://github.com/grafana/dskit/blob/aa16062bba48/ring/ring.go>
- Mimir zone-aware replication: <https://grafana.com/docs/mimir/latest/configure/configure-zone-aware-replication/>
- Mimir shuffle sharding: <https://grafana.com/docs/mimir/latest/configure/configure-shuffle-sharding/>
- Mimir mixin alerts (ingest storage, blocks, compactor): <https://github.com/grafana/mimir/tree/mimir-3.2.4/operations/mimir-mixin/alerts>
- Thanos compactor (singleton, downsampling, dedup): <https://github.com/thanos-io/thanos/blob/v0.42.5/docs/components/compact.md>
- Thanos receive (ketama, shuffle sharding): <https://github.com/thanos-io/thanos/blob/v0.42.5/docs/components/receive.md>
- Thanos dedup iterator: <https://github.com/thanos-io/thanos/blob/v0.42.5/pkg/dedup/iter.go>
- AWS Builders' Library, workload isolation using shuffle sharding: <https://aws.amazon.com/builders-library/workload-isolation-using-shuffle-sharding/>
