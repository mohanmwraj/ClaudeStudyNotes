# 6.4 Cache Failure Modes: Stampede, Penetration, Avalanche, Hot Keys, and Invalidation Races

> **Verified stack:** Caffeine **3.3.1**, Lettuce **7.9.0.RELEASE** against **jedis-mock 1.1.20** (an in-JVM Redis-protocol server; a real Redis binary was blocked by the sandbox here, see [6.3](03-Caching-Caffeine-W-TinyLFU-and-Redis-Lettuce-L1-L2.md)), JDK **25.0.4.1**. Experiments: `CacheLab.java` (sections B–E), `TwoLevelCacheLab.java`, `CacheRaceLab.java`. The XFetch comparison is a **deterministic simulation** (seeded, simulated clock), so it measures the algorithm, not a machine.
>
> **Prereqs:** [6.3 caching](03-Caching-Caffeine-W-TinyLFU-and-Redis-Lettuce-L1-L2.md). **Related:** [5.4 outbox / CDC](../05-Microservices-Patterns/04-Transactional-Outbox-and-Idempotent-Consumer-Complete-Implementation.md), [2.7 read replicas](../02-SQL-RDBMS-Internals/07-Scaling-Replicas-Partitioning-Pooling-Sharding.md).

---

## 0. First principles: every cache incident is correlated misses 🔥

A cache is safe when misses are **few and independent**. Each failure mode below is a way misses become **many and correlated**, so the source sees a burst it was never sized for:

| Failure mode | What correlates the misses | Typical trigger |
|---|---|---|
| **Stampede** (dogpile, thundering herd) | Many requests miss **the same hot key** at the same moment | A hot key expires or is evicted |
| **Penetration** | Requests for keys that **don't exist**, so the cache never fills | Bugs, scrapers, id enumeration attacks |
| **Avalanche** | **Many keys** expire together, or the cache tier disappears | Same TTL set at warm-up, Redis failover, a fleet restart |
| **Hot key** | One key takes a large share of traffic → one Redis shard, one thread | Flash sale item, a celebrity profile, a config key |
| **Stale data** | A slow reader writes old data **after** an invalidation | The cache-aside race (§5) |

And one design rule underneath all of them: **every entry gets a TTL.** The TTL bounds how long any bug, race or lost invalidation can serve wrong data.

---

## 1. Stampede: one key, many misses 🔥

### 1.1 Four layers of defense

| Layer | Mechanism | Scope | Verified |
|---|---|---|---|
| 1 | **Coalescing**: `cache.get(key, loader)`, one load per key | per JVM | 100 concurrent misses → **1** load |
| 2 | **Distributed single-flight**: `SET lock:k token NX PX`, others wait for L2 | fleet | 150 requests on 3 instances → **1** DB load |
| 3 | **Serve stale while refreshing**: `refreshAfterWrite` or soft/hard TTL | per key | stale value in 13 ms instead of a 303 ms block |
| 4 | **Refresh early, probabilistically** (XFetch) | per key, no coordination | below |

The first three outputs were shown in [6.3](03-Caching-Caffeine-W-TinyLFU-and-Redis-Lettuce-L1-L2.md):

```text
  check-then-load (map.get/put): loader ran 100 times
  Caffeine cache.get(key, loader): loader ran 1 time(s)
  database loads: 1   (150 requests)
  refreshAfterWrite  first read after TTL: price-v1  in  13 ms; a moment later: price-v2
```

### 1.2 XFetch: probabilistic early expiration 🧊

From *Optimal Probabilistic Cache Stampede Prevention* (Vattani, Chierichetti, Lowenstein, VLDB 2015). Store, with the value, how long it took to compute (`delta`). Every reader independently decides to recompute **before** expiry with a probability that rises as expiry approaches:

```text
recompute if   now − delta × beta × ln(random())  ≥  expiry        (ln(random()) < 0, so the term pushes "now" forward)

beta = 1 is the paper's default; beta > 1 refreshes earlier
expensive values (big delta) start refreshing earlier
```

```java
record Cached<V>(V value, long deltaMillis, long expiresAtMillis) {}

<V> V get(String key, Supplier<V> compute) {
    Cached<V> c = l2.get(key);
    long now = System.currentTimeMillis();
    if (c == null || now - c.deltaMillis() * BETA * Math.log(ThreadLocalRandom.current().nextDouble()) >= c.expiresAtMillis()) {
        long start = System.currentTimeMillis();
        V v = compute.get();                                    // ideally behind the single-flight lock too
        long delta = System.currentTimeMillis() - start;
        l2.set(key, new Cached<>(v, delta, now + TTL_MS), TTL_MS + GRACE_MS);   // physical TTL > logical expiry
        return v;
    }
    return c.value();
}
```

**Output (verified, deterministic simulation):** one reader per ms for 2,000 ms, the value expires at t = 1,000 ms, recomputing takes 100 ms (readers during a recompute still see the old entry), averaged over 1,000 seeded trials:

```text
== D. One reader per ms, value expires at t=1000 ms, recompute takes 100 ms (1,000 simulated trials)
  plain TTL            recomputations per expiry: 100.0   readers that hit an expired value: 100.0
  XFetch (beta = 1)    recomputations per expiry: 7.5   readers that hit an expired value: 0.0
```

(The label says "per expiry"; precisely, it's per 2-second trial.) With a plain TTL, every reader in the 100 ms recompute window recomputes: that's 100 recomputations and 100 users who waited. XFetch spread **7.5** early recomputations over the trial and **no reader ever saw an expired value**. XFetch alone doesn't guarantee *one* recompute. Pair it with the single-flight lock and you get one early refresh with zero waiting readers.

---

## 2. Penetration: keys that don't exist 🔥

A request for `product:999999999` misses the cache, misses the database, and caches nothing, so the next identical request does it all again. An attacker enumerating ids turns your cache into a pass-through.

### 2.1 Defenses, cheapest first

1. **Validate the input**: id format, ranges, authentication. Rejecting malformed ids costs nothing.
2. **Negative caching**: cache a `NOT_FOUND` marker with a **short** TTL (30–120 s). This works for repeated misses. Random ids defeat it and can fill memory with markers, so cap it (a bounded Caffeine cache for negatives).
3. **Bloom filter of existing ids** in front of the cache: "definitely not present" or "maybe present".
4. **Rate-limit clients** whose miss ratio is abnormal ([6.2](02-Bulkheads-Rate-Limiters-Retries-Jitter-Decorator-Order.md)).

### 2.2 Bloom filter math and a verified run

```text
bits    m = −n · ln(p) / (ln 2)²          n = items, p = target false-positive rate
hashes  k = (m / n) · ln 2

n = 1,000,000, p = 1 %  →  m ≈ 9.59 million bits (≈ 1.1 MB), k = 7
```

```text
== E. Bloom filter: 1,000,000 real product ids, 1% target false-positive rate; 100,000 lookups of ids that don't exist
  bits=9,585,059 (1.1 MB) hashes=7  -> lookups that still hit the database: 959 of 100,000 (0.96%)
```

So 99 % of the attack traffic stopped at 1.1 MB of memory. Operational facts to mention:

* **No deletes** in a classic Bloom filter. Use a counting Bloom filter or a cuckoo filter, or rebuild it periodically from the source of truth.
* **New ids must be added before anyone queries them**, so add on create, in the same flow that publishes the creation event. Otherwise a brand-new product is "definitely absent" for a while.
* Shared across pods: Redis Bloom commands (`BF.RESERVE`, `BF.ADD`, `BF.EXISTS`) from the probabilistic module (Redis Stack, bundled in recent Redis distributions), or rebuild a local copy per pod from a snapshot.

---

## 3. Avalanche: many keys at once 🔥

### 3.1 Synchronized expiry

If a warm-up job loaded 200,000 keys at 09:00 with `EX 3600`, all 200,000 expire at 10:00. Spread them:

```java
long ttl = BASE_TTL_SECONDS + ThreadLocalRandom.current().nextLong(BASE_TTL_SECONDS / 10);   // ±10 % jitter
redis.set(key, value, SetArgs.Builder.ex(ttl));
```

The two-level lab uses `600 + random(60)` seconds for exactly this reason.

### 3.2 Losing the cache tier

Redis fails over, gets flushed, or the whole fleet restarts with empty L1s. Now 100 % of reads are misses, and by the arithmetic in [6.3 §0](03-Caching-Caffeine-W-TinyLFU-and-Redis-Lettuce-L1-L2.md) the database sees 10–100× its normal load.

| Defense | How |
|---|---|
| **L1 shields L2** | Even a 5–30 s L1 TTL absorbs most hot-key traffic while L2 is cold or down |
| **Breaker + timeout on Redis** | A sick Redis must fail **fast** (ms), not slow, so requests fall through or degrade instead of piling up |
| **Miss bulkhead** 🧊 | A **concurrency limit on cache-miss loads** (for example 20 per pod). When the cache is gone, this caps the DB load at `pods × 20` concurrent queries; the excess gets stale data, a degraded response, or a 503 |
| **HA + persistence** | Replicas with Sentinel or Cluster for failover; RDB/AOF so a restart isn't a cold start |
| **Staggered rollouts** | `maxSurge`/`maxUnavailable` so only a few pods start with empty L1s at once |
| **Warm-up** | Pre-load known hot keys at startup, but don't make readiness depend on a remote cache ([7.3](../07-Docker-JVM-Kubernetes/03-Kubernetes-Probes-and-Graceful-Shutdown.md)) |

---

## 4. Hot keys ⚡

Redis executes commands on one thread per shard, so one key at 200k reads/s saturates its shard no matter how big the cluster is.

* **Detect it**: client-side metrics per key prefix, `redis-cli --hotkeys` (needs an LFU `maxmemory-policy`), or Redis keyspace analysis. Avoid `MONITOR` in production; it's expensive.
* **L1 is the best fix**: with 50 pods and a 1 s L1 TTL on that key, Redis sees at most about 50 reads/s for it, whatever the user traffic.
* **Key replication**: write `product:42#0` … `product:42#7`, read a random one. That spreads load across slots (and shards). Writes and invalidations must touch all copies.
* **Read from replicas** (Lettuce `ReadFrom.REPLICA_PREFERRED`): spreads reads, but adds replication lag to your staleness.
* **Big keys** (a 2 MB JSON, a 1M-member set) are a related problem. Split them; a single `GET` of a huge value blocks the shard.

---

## 5. Invalidation races: the cache-aside bug most designs have 🧊

### 5.1 The race

Cache-aside with "update the DB, then delete the key" still has a window. A reader that **read the database before the update** can **write the cache after the delete**:

```text
reader                                  writer                        cache        db
GET k → miss
SELECT → price=100                                                    (empty)      100
   … stalls (GC, slow network) …        UPDATE → 80; COMMIT                        80
                                        DEL k                         (empty)
SET k price=100 EX 600                                                100  ← stale  80
```

**Output (verified, interleaving forced step by step, Lettuce 7.9.0 → jedis-mock):**

```text
== 1. Cache-aside with delete-on-write (forced interleaving)
  reader: GET product:42 -> null (miss), reads DB -> price=100 ... then stalls (GC pause, slow network)
  writer: UPDATE db -> price=80; DEL product:42
  reader resumes: SET product:42 price=100 EX 600
  every later read: cache=price=100  db=price=80  -> stale for up to 600 s
```

The window is small, but at scale small windows happen every day. Read replicas make it much wider: a reader that fills the cache from a replica 2 s behind can cache pre-update data long after the writer's `DEL`.

### 5.2 The fix: leases (Facebook memcache, NSDI 2013)

In *Scaling Memcache at Facebook* (Nishtala et al.), a miss returns a **lease token**. A fill is accepted only if the lease is still valid, and **an invalidation revokes outstanding leases**. The same idea in Redis is one extra key and a Lua script:

```lua
-- KEYS[1] = value key, KEYS[2] = lease key; ARGV[1] = my lease token, ARGV[2] = value, ARGV[3] = ttl seconds
if redis.call('get', KEYS[2]) == ARGV[1] then
  redis.call('set', KEYS[1], ARGV[2], 'EX', ARGV[3]); redis.call('del', KEYS[2]); return 1
else return 0 end
```

```text
on miss:     SET lease:k <token> NX PX 10000      (only one reader gets the lease, which also gives single-flight)
writer:      UPDATE …; COMMIT; DEL k lease:k      (invalidation revokes the lease)
fill:        EVAL fill-with-lease                 (rejected if the lease was revoked)
```

**Output (verified):**

```text
== 2. Same interleaving with leases (Facebook memcache, NSDI 2013)
  reader: GET miss, takes lease 06e8d798, reads DB -> price=100 ... stalls
  writer: UPDATE db -> price=80; DEL product:42 and lease:product:42
  reader resumes: fill-with-lease returned 0 (rejected)
  next read: cache=null -> miss, loads db=price=80
```

### 5.3 The other options, compared

| Technique | Removes the race? | Cost |
|---|---|---|
| Short TTL only | No, bounds it | More misses |
| **Delete after commit** (not inside the transaction) | Necessary, not sufficient | None |
| Delayed double delete (delete, wait ~lag + read time, delete again) | Mostly | A scheduled task per write; the window is narrowed, not closed |
| **Leases** | Yes, for fills racing a delete | One key + Lua per miss |
| **Versioned fills**: store `(version, value)`, a Lua `SET` only if the new version ≥ the stored one, writers write a version tombstone instead of `DEL` | Yes | Version column in the source (for example `updated_at` or an optimistic-lock `@Version`) |
| **CDC-driven invalidation** (Debezium reads committed changes, then deletes keys) | Removes "invalidated before commit" and "forgot to invalidate"; combine with leases for the fill race | A CDC pipeline; invalidations arrive after replication lag |
| Write-through (set the new value in the cache in the write path) | Introduces the *set-order* race between writers | Use only with versioned sets |

### 5.4 Decide the staleness budget per use case

A cache is a consistency decision. Write it down per data type:

| Data | Staleness budget | Design |
|---|---|---|
| Product description | minutes | L1 + L2, TTL + refresh-ahead |
| Price on the listing page | seconds | L2 with leases + CDC invalidation, short L1 |
| Price at checkout | **zero** | Read the source of truth (or a versioned check), never the cache |
| Stock "in stock / low stock" badge | seconds | Cache with short TTL |
| Stock reservation | zero | Database (row lock / conditional update), never the cache |

---

## 6. Blueprint: a cache read path that survives all five 🧊

```text
get(key):
  validate(key)                                    ── penetration: reject malformed ids
  if !bloom.mightContain(key) → NOT_FOUND          ── penetration
  v = L1.get(key)              (Caffeine, refreshAfterWrite 30 s, expireAfterWrite 2 min)
      on L1 miss / refresh, inside Caffeine's single per-key load:
        c = L2.get(key)        (Redis, command timeout 50 ms, behind a circuit breaker)
        if c present and not XFetch-early → return c.value
        if c is a NOT_FOUND marker        → return NOT_FOUND        (negative cache, TTL 60 s)
        if lease = L2.set("lease:"+key, token, NX, PX 5000):        ── stampede: one loader fleet-wide
            missBulkhead.acquire()      (≤ 20 concurrent DB loads per pod)   ── avalanche
              row = db.find(key)
            L2.fillWithLease(key, row or NOT_FOUND, ttl = base ± 10 % jitter)  ── race + avalanche
            return row
        else if c present → return c.value (stale but fine)   ── stampede: serve stale while one refreshes
        else wait briefly for L2, then degrade (stale L1 / 503) ── never pile onto the DB
  on Redis breaker OPEN: skip L2, still go through missBulkhead to the DB

on write (after COMMIT, or from CDC):
  DEL key, lease:key in L2;  publish invalidation (L1)           ── stale data
```

---

## 7. ❌ Naïve vs ✅ production-hardened

| ❌ Naïve | ✅ Production-hardened |
|---|---|
| Every miss loads | Per-JVM coalescing + distributed single-flight |
| Readers block at expiry | Serve stale while one refreshes; XFetch for expensive values |
| Non-existent ids hit the DB every time | Input validation, bounded negative cache, Bloom filter, client rate limits |
| Same TTL for everything loaded together | TTL jitter |
| "Redis is HA, so the cache can't disappear" | L1 shield, fast-failing Redis client, **miss bulkhead**, staggered rollouts |
| Hot key on one shard | L1 with a short TTL, key replication, replica reads |
| Update DB, then `DEL`, and assume consistency | Delete after commit + leases or versioned fills, or CDC invalidation |
| Fill the cache from a lagging replica | Fill from the primary for recently written keys, or account for lag in the staleness budget |
| Cache everything with one policy | A staleness budget per data type; never cache values that need zero staleness |

---

## 8. Source to read

| Source | What to look for |
|---|---|
| [Scaling Memcache at Facebook (NSDI 2013)](https://www.usenix.org/conference/nsdi13/technical-sessions/presentation/nishtala) | §3.2.1 leases (stale sets and thundering herds), regional invalidation via the commit log (McSqueal) |
| [Optimal Probabilistic Cache Stampede Prevention (VLDB 2015)](https://www.vldb.org/pvldb/vol8/p886-vattani.pdf) | The XFetch rule and why the exponential is optimal |
| [ben-manes/caffeine wiki: Refresh](https://github.com/ben-manes/caffeine/wiki/Refresh) | Refresh semantics, coalescing, interaction with expiry |
| [debezium/debezium-examples](https://github.com/debezium/debezium-examples) | CDC pipelines you can adapt for cache invalidation |

---

## 9. Interview soundbites

* "Every cache incident is correlated misses: one key (stampede), keys that don't exist (penetration), many keys or the whole tier (avalanche), or one shard (hot key)."
* "For stampedes I layer per-JVM coalescing, a fleet-wide lease, stale-while-revalidate, and XFetch for expensive values. In simulation XFetch took expired reads from 100 to 0."
* "A Bloom filter of 1 million ids at 1 % is 1.1 MB and 7 hashes. In my run 0.96 % of fake ids still reached the database."
* "The defense people forget is a concurrency limit on cache-miss loads. When the cache disappears, it's what keeps the database alive."
* "Delete-after-update still has a race: a slow reader re-caches the old value after the delete. I reproduced it, and leases fix it: the delete revokes the reader's lease, and its fill is rejected."
* "I set a staleness budget per data type. Checkout prices and stock reservations never come from a cache."

**Next:** [6.5 Kafka producers: batching, idempotence, ordering →](05-Kafka-Producers-Batching-Idempotence-Ordering.md)
