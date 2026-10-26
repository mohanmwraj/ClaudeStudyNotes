# 6.7 Redis in Production: Memory per Key, Eviction Policies, Client-Side Caching, Timeouts, Sentinel Failover, and Spring's Redis Cache (Real Redis 8.10.2)

> **Verified stack:** a real **Redis 8.10.2** server (the msys2 Windows build, x86-64), **Lettuce 7.9.0** for the standalone labs and **Lettuce 7.5.2** (the version Spring Boot 4.1.2 manages) inside **Spring Boot 4.1.2 / Spring Data Redis 4.1.2**, JDK **25**. Every block marked *verified* was produced by the code shown. Timings are *one run* on loopback on a Windows laptop: they show **ratios and mechanisms, not Redis performance**. Linux builds are faster in absolute terms.
>
> **Why this file exists:** [6.3](03-Caching-Caffeine-W-TinyLFU-and-Redis-Lettuce-L1-L2.md) and [6.4](04-Cache-Stampede-Penetration-Avalanche-Invalidation.md) ran their Redis experiments against **jedis-mock**, because a real Redis binary was blocked on this machine at the time. Now one starts, so this file (1) re-verifies those labs on real Redis, then (2) covers what only a real server can show.

---

## 0. What this file proves 🔥

| Claim | Evidence |
|---|---|
| The 6.3 two-level cache and the 6.4 lease fix behave identically on real Redis | §1: `diff` of jedis-mock vs Redis 8.10.2 output is empty |
| A 40-byte value costs 110 bytes as its own key, 44 bytes inside a listpack hash | §2 |
| `volatile-*` with keys that have no TTL behaves like `noeviction`: writes fail | §3: 14,760 failed `SET`s |
| `allkeys-lfu` beat `allkeys-lru` and `allkeys-random` on a Zipf workload | §3: 83.1 % vs 81.3 % vs 78.2 % |
| RESP3 client-side caching cut server reads 100× and is invalidated by the server | §4 |
| Pipelining is a ~13× round-trip win; `MSET` ~36× | §5 |
| Lettuce waits **60 s** by default when Redis stalls | §6 |
| A Sentinel failover **lost 38 acknowledged writes**; `WAIT` lost **0** confirmed ones | §7 |
| Failover took 1.75 s in one run and 17.5 s in another: a retried failover + client backoff | §7.3 |
| Spring Data Redis 4 writes cache entries **asynchronously**: 21–59 of 200 immediate re-reads missed | §8 |
| Without a `CacheErrorHandler`, a Redis stall **fails the request**; a `null` result **throws** | §8 |
| The `redis.conf`, ACL, Sentinel and Spring blueprints in §9 start, enforce, and validate | §9 |

---

## 1. Re-verifying the jedis-mock labs on real Redis (verified)

The 6.3 two-level-cache lab (L1 Caffeine + L2 Redis + pub/sub invalidation + owner-checked lock release) and the 6.4 invalidation-race lab (cache-aside race, then leases) were re-run unchanged, except that the client points at `redis://127.0.0.1:56379` (with `FLUSHALL` first):

```text
TwoLevelCacheLab: jedis-mock and real Redis 8.10.2 outputs IDENTICAL (lease id masked)
CacheRaceLab: jedis-mock and real Redis 8.10.2 outputs IDENTICAL (lease id masked)
```

One gotcha surfaced on the way: the first real-Redis run of the race lab printed `GET product:42 -> price=80 (miss)` because the *previous* lab had left that key in the same server. jedis-mock starts empty every time, a real server doesn't. Labs and integration tests against a shared Redis need an explicit `FLUSHDB`, a unique key prefix per test, or a database index per test.

---

## 2. What a key costs: encodings and memory (verified) ⚡

```text
== A. What a key costs: encodings and MEMORY USAGE
  key 'k:probe': values up to 34 bytes are embstr, 35+ bytes are raw
  config: hash-max-listpack-entries=512 hash-max-listpack-value=64
  k:int      encoding=int       MEMORY USAGE=   24 bytes
  k:short    encoding=embstr    MEMORY USAGE=   40 bytes
  k:long     encoding=raw       MEMORY USAGE=   74 bytes
  k:json     encoding=raw       MEMORY USAGE=  229 bytes
  k:hash8    encoding=listpack  MEMORY USAGE=  193 bytes
  k:hash513  encoding=hashtable MEMORY USAGE=23446 bytes
  10,000 x 200-byte values as STRING keys:  268 bytes/item | as 100 HASH buckets x 100 fields:  258 bytes/item (bucket encoding=hashtable)
  10,000 x  40-byte values as STRING keys:  110 bytes/item | as 100 HASH buckets x 100 fields:   44 bytes/item (bucket encoding=listpack)
```

**Reading it:**

* **Every top-level key costs ~68–70 bytes before its value** (268 − 200; 110 − 40), for the key object, the dictionary entry and allocator rounding. For small values the overhead *is* the cost: a 40-byte value took 110 bytes.
* **Small hashes are stored as a compact `listpack`.** Grouping 100 small values into one hash ("bucketing", the trick Instagram described) took **44 bytes per item instead of 110**, 2.5× less.
* **The trick has two thresholds**, and both bit:
  * 200-byte values exceed `hash-max-listpack-value=64`, so the bucket became a `hashtable` and saved almost nothing (258 vs 268);
  * 513 fields exceed `hash-max-listpack-entries=512`, which in **Redis 8.10.2 defaults to 512** (older guidance says 128: check your version), and memory jumped to 23 KB.
* **`embstr` ended at 34 bytes for this key name**, not the often-quoted 44: Redis 8 lays out small strings differently, and the cut-off depends on the key's own length. Don't plan capacity on encoding folklore; measure `MEMORY USAGE` on real samples.

**Sizing formula for a cache tier:** `memory ≈ keys × (≈70 B + key length + value size) × 1.2–1.5` (fragmentation and allocator slack), plus client output buffers and replication backlog, then set `maxmemory` to ~75 % of the instance.

---

## 3. Eviction policy *is* your cache algorithm (verified) 🔥

Cache-aside reads (`GET`, and on a miss `SET` the "database" value) over 20,000 keys with a Zipf(0.99) popularity distribution, 512-byte values, `maxmemory` sized for ~25 % of the keys. The first 30,000 requests warm up; 70,000 are measured.

```text
== B. Eviction policy vs hit rate (cache-aside, Zipf s=0.99 over 20,000 keys, 512-byte values, memory for ~25%)
  per key ~579 bytes; baseline used_memory 1,042,806; maxmemory 3,937,806
  noeviction      hit rate  81.6%   evicted_keys       0   failed SETs 14,760   keys  5,497   used_memory 3,987,372
  volatile-lru    hit rate  81.6%   evicted_keys       0   failed SETs 14,759   keys  5,497   used_memory 3,987,396
  allkeys-random  hit rate  78.2%   evicted_keys  17,373   failed SETs      0   keys  5,397   used_memory 3,937,816
  allkeys-lru     hit rate  81.3%   evicted_keys  15,014   failed SETs      0   keys  5,414   used_memory 3,937,720
  allkeys-lfu     hit rate  83.1%   evicted_keys  13,771   failed SETs      0   keys  5,432   used_memory 3,937,628
```

Across three runs the hit rates moved by at most 0.2 points (eviction samples keys randomly).

**Reading it:**

* **`volatile-lru` behaved exactly like `noeviction`.** No key had a TTL, so nothing was evictable, and **14,760 writes failed** with `OOM command not allowed when used memory > 'maxmemory'`. The hit rate looks fine only because the first keys inserted under Zipf were mostly hot ones. Any *other* write to that instance (a lock, a session, a rate-limit counter) now fails too. `volatile-*` is for mixed instances where **every evictable key has a TTL**.
* **`allkeys-lfu` won (83.1 %)**, because frequency beats recency for a stable popularity skew; `allkeys-lru` (81.3 %) was only modestly better than random eviction (78.2 %). Redis LRU and LFU are both *sampled approximations* (`maxmemory-samples`, default 5); the production blueprint uses 10.
* **The ceiling is set by the workload,** not the policy: with 25 % of keys in memory, a Zipf(0.99) workload tops out in the low 80s. Doubling memory moves that ceiling more than any policy change. Size first, then pick the policy.

| Instance role | Policy | Why |
|---|---|---|
| Pure cache (everything rebuildable) | `allkeys-lfu` (or `-lru`) | Any key may go; keep the hot set |
| Sessions / rate limits (all keys have TTLs) | `volatile-lru` / `volatile-ttl` | Evict only expiring keys; never evict a key without a TTL |
| Mixed cache + data you can't lose | **Don't**: two instances | One eviction policy can't serve both |
| Queues, locks, anything authoritative | `noeviction` + alerts on memory | A write error is better than silent data loss |

---

## 4. Client-side caching: Redis tells you when to drop a key (verified) 🧊

With RESP3, a connection can ask the server to **track** the keys it reads and push an invalidation when any client modifies them. Lettuce wraps this as `ClientSideCaching`:

```java
Map<String, String> local = new ConcurrentHashMap<>();
CacheFrontend<String, String> frontend = ClientSideCaching.enable(CacheAccessor.forMap(local), tracked, TrackingArgs.Builder.enabled());
frontend.get("hot:7");          // first read: GET from Redis, kept locally; later reads: no network
```

```text
== C. Client-side caching (RESP3 CLIENT TRACKING): the server tells you when to drop a key
  10,000 reads of 100 hot keys through the frontend: server GET calls=100, local entries=100, 19 ms (one run)
  the same 10,000 reads as plain GETs:               server GET calls=10000, 1401 ms (one run)
  before write: frontend.get(hot:7)=v1  local has hot:7=true
  after another client SETs hot:7=v2: local has hot:7=false  frontend.get(hot:7)=v2
```

**Reading it:**

* **Load:** 100 server reads instead of 10,000 (one per key).
* **Latency:** 74× less wall time.
* **Correctness:** when *another* client wrote `hot:7`, the server's push invalidation removed the local copy, with no pub/sub channel and no TTL guessing.

Compared with 6.3's Caffeine L1 + pub/sub invalidation:

| | Caffeine L1 + pub/sub (6.3) | RESP3 client-side caching |
|---|---|---|
| Who publishes invalidations | Your code, on every write path (miss one, serve stale) | The server, for every modification by anyone |
| Eviction/size policy locally | W-TinyLFU, bounded | Whatever map you pass: **bound it yourself** (`forMap` over an unbounded map grows forever) |
| After a reconnect | You must flush L1 (messages may have been missed) | Same: tracking state is per connection; invalidations sent while disconnected are lost, so the local cache must be cleared on reconnect |
| Requirements | Any Redis | Redis 6+, RESP3 (`resp=3` was negotiated here) |

---

## 5. Round trips dominate (verified, one run) ⚡

```text
== D. Round trips: 10,000 SETs (one run, loopback)
  sync, one at a time: 1254 ms   pipelined (flush every 1,000): 94 ms   MSET x10 of 1,000: 35 ms
```

Each synchronous command pays a full network round trip. Pipelining (Lettuce `setAutoFlushCommands(false)` + `flushCommands()`) made it **13×** faster on *loopback*, and **36×** with `MSET`. Across availability zones (≈0.5–1 ms per round trip) the ratio grows. Batch warm-ups, bulk invalidations and multi-key reads (`MGET`, or pipelined `GET`s across cluster slots).

---

## 6. When Redis stalls: the timeout is your SLO budget (verified) 🔥

`CLIENT PAUSE 2000` freezes the server for 2 s, like a long fork, a `KEYS *` or a failover:

```text
== E. Redis stalls for 2 s (CLIENT PAUSE): what does a cache read cost?
  Lettuce default command timeout: PT1M
  timeout 60000ms GET took 2,063 ms: value=cached
  timeout 200ms  GET took   204 ms: RedisCommandTimeoutException -> fall back to the database
```

**Lettuce's default command timeout is 60 seconds** (`RedisURI.DEFAULT_TIMEOUT = 60`, also read from the jar). A cache read that normally takes 1 ms then held the request for the full stall. In a real outage that's 60 s of a Tomcat thread or a virtual-thread pinned connection, per request. Set `spring.data.redis.timeout` to what a *cache* is worth: if the database answers in 20 ms, a cache read that takes 250 ms has already failed. Then decide what a timeout *means* (§8: by default Spring turns it into a failed request).

---

## 7. Sentinel failover: what happens to acknowledged writes (verified) 🔥

### 7.1 The setup

One primary (`:56380`), one replica (`:56381`), three Sentinels (quorum 2, `down-after-milliseconds 1000`, `failover-timeout 5000`), all real Redis 8.10.2 processes. A Lettuce client connects through the Sentinels (`RedisURI.Builder.sentinel(...)`, 300 ms timeout, `REJECT_COMMANDS` while disconnected) and `INCR`s a counter every 10 ms. At +1.0 s the replica is stalled (`DEBUG SLEEP 2`, so replication falls behind); at +1.5 s the primary process is **killed** (`destroyForcibly`: no shutdown, no final sync).

### 7.2 Results

```text
== A. Plain INCR: acknowledged by the primary only (async replication)
  primary killed at +1504 ms (replica had been stalled for 500 ms); new primary: 127.0.0.1:56381
  last successful write before the crash: +1508 ms; first after failover: +3264 ms; writes failed in between: 157
      156 x RedisException: Currently not connected. Commands are rejected.                  +1537..+3254 ms
  sentinel :26390 events (primary killed at 21:15:33.584 wall clock):
    +sdown master mymaster 127.0.0.1 56380                                   (21:15:34.679)
    +odown master mymaster 127.0.0.1 56380 #quorum 2/2                      (21:15:34.772)
    +elected-leader master mymaster 127.0.0.1 56380                          (21:15:34.897)
    +selected-slave slave 127.0.0.1:56381 ...                                (21:15:34.959)
    +promoted-slave slave 127.0.0.1:56381 ...                                (21:15:35.129)
    +switch-master mymaster 127.0.0.1 56380 127.0.0.1 56381                  (21:15:35.254)
  highest acknowledged counter value before the crash: 121
  counter on the new primary before its first new INCR: 83
  => acknowledged writes lost: 38
== B. INCR + WAIT 1 200: count a write as done only when the replica has it
  primary killed at +1502 ms (replica had been stalled for 500 ms); new primary: 127.0.0.1:56381
  last successful write before the crash: +1474 ms; first after failover: +4655 ms; writes failed in between: 264
  highest replica-confirmed counter value before the crash: 78 (writes acknowledged by the primary but NOT confirmed by WAIT: 2)
  counter on the new primary before its first new INCR: 78
  => confirmed writes lost: 0
```

(Sentinel log lines abridged: timestamps moved to the end of each line.)

**Reading it:**

* **Redis replication is asynchronous.** The primary acknowledged counter values 84–121, but the replica (stalled) never received them. When the replica was promoted, **38 acknowledged writes were gone**. Nothing errored for those writes: the client was told "OK".
* **`WAIT 1 200` turns "acknowledged" into "acknowledged and replicated (or I know it wasn't)".** During the stall, `WAIT` returned 0 for 2 writes, so the client *knew* they weren't durable. The highest confirmed value (78) survived exactly. `WAIT` is **not** a transaction: the unconfirmed writes stayed on the old primary and were lost with it. Your code must retry or report them. It also costs latency on every write, and with several replicas Sentinel does not guarantee to promote one that has every `WAIT`-confirmed write. It narrows the window; it doesn't make Redis CP.
* **The failover itself** took ~1.7 s from the kill: 1.1 s to subjective-down (`down-after` 1000 ms), then odown, election, promotion and switch in ~0.6 s.

### 7.3 Why one failover took 1.75 s and another 17.5 s (verified)

Scenario A, repeated four times, with Lettuce's default reconnect delay and then with it capped at 500 ms:

```text
Lettuce default reconnect delays, attempts 1-16: 1, 2, 4, 8, 16, 32, 64, 128, 256, 512, 1024, 2048, 4096, 8192, 16384, 30000 ms
  RECOVERY default reconnect delay: writes failed for 1745 ms
  RECOVERY default reconnect delay: writes failed for 17485 ms
  RECOVERY default reconnect delay: writes failed for 17493 ms
  RECOVERY default reconnect delay: writes failed for 17505 ms
  RECOVERY reconnect delay capped at 500 ms: writes failed for 1754 ms
  RECOVERY reconnect delay capped at 500 ms: writes failed for 12605 ms
  RECOVERY reconnect delay capped at 500 ms: writes failed for 13195 ms
```

(Each mode ran four times; the fourth capped run, 12,592 ms, is omitted.)

The slow runs' Sentinel log explains the first ~10 s:

```text
+sdown slave 127.0.0.1:56381 ...          <- the replica was in DEBUG SLEEP, so Sentinel marked it down too
+sdown master mymaster 127.0.0.1 56380
+odown master mymaster 127.0.0.1 56380 #quorum 3/2
Next failover delay: I will not start a failover before Sun Oct 25 21:17:44 2026     <- 10 s later
+switch-master mymaster 127.0.0.1 56380 127.0.0.1 56381                               (at 21:17:44)
```

**The three terms of recovery time:**

* **Detection:** `down-after-milliseconds`.
* **Failover:** it can be **retried after 2 × `failover-timeout`** if the first attempt can't use a replica (here, a stalled one; in production, a lagging or unreachable one).
* **Client reconnect:** Lettuce's default backoff doubles up to **30 s**, so after a long outage the next attempt may come many seconds after the new primary is ready. Capping it at 500 ms recovered ~5 s sooner on the same slow failover.

The Spring blueprint (§9.4) bounds the backoff with a `ClientResourcesBuilderCustomizer`.

---

## 8. Spring's Redis cache on a real server: four behaviours to know (verified) 🔥

A Boot 4.1.2 app with `@Cacheable("products")`, the `application.yml` from §9.3 (the lab copy differs only in the connection), connecting as the ACL user `app`. It runs in three configurations: Spring's defaults, a tolerant `CacheErrorHandler`, and `immediateWrites()`.

```text
== CacheErrorHandler: none (Spring's default) | cache writes: default
  read-after-write: 200 cold keys read twice -> database calls 221 (21 second reads missed the entry the first read had just written)
  find(42) x2 -> database calls 1; Redis key cache:order-service:products::42  TTL 600 s  value {"id":42,"name":"book","price":12.50}
  find(-1) returned null -> THREW IllegalArgumentException: Cache 'products' does not allow 'null' values; Avo...
  statistics: gets=405 hits=182 misses=223 puts=222
  Redis paused 2 s, find(7): 261 ms, THREW QueryTimeoutException (cause RedisCommandTimeoutException); cache errors handled: 0
== CacheErrorHandler: tolerant (treat failures as misses) | cache writes: default
  read-after-write: 200 cold keys read twice -> database calls 246 (46 second reads missed the entry the first read had just written)
  find(42) x2 -> database calls 1; ...
  database calls so far: 2; keys in Redis: 1
  Redis paused 2 s, find(7): 257 ms, returned Product[id=7, name=book, price=12.50]; cache errors handled: 2
== CacheErrorHandler: none (Spring's default) | cache writes: immediateWrites()
  read-after-write: 200 cold keys read twice -> database calls 200 (0 second reads missed the entry the first read had just written)
```

A second full run gave 26 and 59 read-after-write misses with default writes, and **0** with `immediateWrites()` again.

**1. Spring Data Redis 4 writes cache entries asynchronously.** With a Lettuce connection factory, `DefaultRedisCacheWriter` defaults to asynchronous writes (`RedisCacheWriterConfigurer.immediateWrites()` is the opt-out), so the `@Cacheable` method returns before its `SET` reaches Redis. `MONITOR` caught it in a single run:

```text
...786016 [127.0.0.1:50398] "GET" "cache:order-service:products::42"        <- 2nd call's read...
...786347 [127.0.0.1:50399] "SET" "cache:order-service:products::42" ...    <- ...overtook the 1st call's write
...797684 [127.0.0.1:50399] "SET" "cache:order-service:products::42" ...    <- so the database was hit twice
```

That is **10–30 % duplicate loads** for read-right-after-miss patterns. For an expensive loader under burst it's a stampede amplifier ([6.4 §1](04-Cache-Stampede-Penetration-Avalanche-Invalidation.md#1-stampede-one-key-many-misses-)). Use `immediateWrites()` when read-after-write matters (§9.4); keep the default when the loader is cheap and write latency matters more.

**2. A Redis stall fails the request.** With no `CacheErrorHandler`, the 250 ms command timeout surfaced as `QueryTimeoutException` from the `@Cacheable` method. A cache meant to *reduce* load became a hard dependency. A tolerant `CacheErrorHandler` returned the database value in 257 ms. The latency remains (each get *and* put waits for its timeout), so for a sustained outage put a circuit breaker in front of the cache calls ([6.1](01-Resilience4j-Circuit-Breaker-Internals-Sliding-Windows.md)).

**3. `cache-null-values: false` makes a `null` result *throw*.** The method ran (database call counted), then `IllegalArgumentException: Cache 'products' does not allow 'null' values` failed the caller. Use `@Cacheable(unless = "#result == null")`, or cache an explicit "not found" marker with a short TTL, which is also the penetration defense of [6.4 §2](04-Cache-Stampede-Penetration-Avalanche-Invalidation.md#2-penetration-keys-that-dont-exist-). The tolerant error handler swallowed it silently, which is worse: a design decision hidden as an error count.

**4. Keys, TTL and payloads are what you configured.**

* **Key:** `cache:order-service:products::42` (prefix + cache name + `::` + key).
* **TTL:** 600 s (`time-to-live: 10m`).
* **Value:** JSON with the money scale intact (`12.50`, via `USE_BIG_DECIMAL_FOR_FLOATS`).
* **Statistics:** available (`enable-statistics: true`).

The key prefix matches the ACL pattern `~cache:*`, so the application user can't touch anything else.

---

## 9. Blueprints (all started or validated) 🔥

### 9.1 `redis.conf` for a cache (started on Redis 8.10.2; settings read back)

```conf
# Redis 8 as a CACHE: every value can be rebuilt from the database.
# NOTE: redis.conf has no inline comments; a trailing "# ..." is parsed as arguments and the server refuses to start.
port 6379
protected-mode yes
aclfile /etc/redis/users.acl

# ~75% of the memory limit: leave room for fragmentation, client output buffers, replication buffers and the OS.
maxmemory 1536mb
maxmemory-policy allkeys-lfu
maxmemory-samples 10
lazyfree-lazy-eviction yes
lazyfree-lazy-expire yes
lazyfree-lazy-server-del yes
lazyfree-lazy-user-del yes

# A cache doesn't persist: no fork, no copy-on-write memory spike, no disk.
save ""
appendonly no

timeout 0
tcp-keepalive 60
maxclients 10000
latency-monitor-threshold 50
slowlog-log-slower-than 10000
slowlog-max-len 1024
```

The first version had inline comments (`aclfile users.acl   # no anonymous access`) and **Redis refused to start**: `Reading the configuration file, at line 7 ... wrong number of arguments`. Comments must be on their own lines. (The lab copy binds `127.0.0.1:56390`; production binds the pod/VM address behind a NetworkPolicy, see [7.8](../07-Docker-JVM-Kubernetes/08-Kubernetes-Platform-Blueprints-II-Kustomize-Guardrails-Consumers-Jobs-Canary.md).)

### 9.2 ACL users (enforced, verified)

```text
user default off
user app on >app-secret-change-me ~cache:* ~lock:* &cache-invalidation +@all -@dangerous -@admin
user metrics on >metrics-secret-change-me -@all +ping +info +slowlog|get +latency|latest
user ops on >ops-secret-change-me ~* &* +@all
```

**What the server answered (verified):**

| Who | Command | Result |
|---|---|---|
| anonymous | `PING` | `NOAUTH Authentication required.` |
| app | `SET cache:product:1 v` / `GET` | `OK` / `v` |
| app | `SET other:1 v` | `NOPERM No permissions to access a key` |
| app | `FLUSHALL`, `KEYS cache:*`, `CONFIG GET` | `NOPERM … has no permissions to run the 'flushall'` / `'keys'` / `'config|get' command` |
| app | `SCAN 0 MATCH cache:*`, `UNLINK`, `EVAL` reading `cache:product:1` | allowed |
| app | `PUBLISH cache-invalidation …` / `PUBLISH other-channel x` | allowed / `NOPERM No permissions to access a channel` |
| metrics | `INFO memory` / `GET cache:product:1` | `maxmemory_human:1.50G`, `maxmemory_policy:allkeys-lfu` / `NOPERM` |
| app | `DEBUG SLEEP 0` | `ERR DEBUG command not allowed` (Redis 7+ disables `DEBUG` unless `enable-debug-command`) |

In production, store `#<sha256>` password hashes in the ACL file and mount it from a secret. `-@dangerous` removes `KEYS`, `FLUSHALL`, `CONFIG`, `DEBUG` and friends from the application user. A forgotten `KEYS *` in a hot path is a classic Redis outage.

### 9.3 Variants (started; settings read back)

* **Session or rate-limit store:** `maxmemory-policy volatile-lru`, `appendonly yes`, `appendfsync everysec`, `aof-use-rdb-preamble yes`. Every key must have a TTL (§3).
* **Sentinel** (one of three, one per zone):
  ```conf
  sentinel monitor cache-primary 10.0.1.10 6379 2
  sentinel down-after-milliseconds cache-primary 5000
  sentinel failover-timeout cache-primary 30000
  sentinel parallel-syncs cache-primary 1
  ```
  The Sentinel reported back `down-after-milliseconds 5000`, `quorum 2`, `failover-timeout 30000`. A 5 s detection is a deliberate trade-off against false failovers on GC or network blips. Remember the §7.3 rule: a failed attempt waits 2 × `failover-timeout` (60 s here) before retrying.

### 9.4 Spring Boot 4.1.2 (`application.yml` validated: 20 keys, 0 problems; the Java ran in §8)

```yaml
spring:
  data:
    redis:
      sentinel:
        master: cache-primary
        nodes:
          - redis-sentinel-0.redis-sentinel.cache.svc:26379
          - redis-sentinel-1.redis-sentinel.cache.svc:26379
          - redis-sentinel-2.redis-sentinel.cache.svc:26379
        username: sentinel-client
        password: ${REDIS_SENTINEL_PASSWORD}
      username: app
      password: ${REDIS_PASSWORD}
      client-name: order-service
      timeout: 250ms                 # a cache read slower than this has already failed (§6)
      connect-timeout: 500ms
      ssl:
        enabled: true
        bundle: redis
      lettuce:
        shutdown-timeout: 200ms
  ssl:
    bundle:
      pem:
        redis:
          truststore:
            certificate: file:/etc/redis-tls/ca.crt
  cache:
    type: redis
    cache-names: products
    redis:
      time-to-live: 10m
      cache-null-values: false       # then use unless = "#result == null" (§8.3)
      key-prefix: "cache:order-service:"
      use-key-prefix: true
      enable-statistics: true
```

Checked key by key against the configuration metadata of the Boot 4.1.2 modules (73 metadata files, 1,658 properties): `20 keys, 0 problems`. The lab copy (host/port instead of Sentinel/TLS) also passed: 18 keys, 0 problems.

```java
@Configuration(proxyBeanMethods = false)
class RedisTuning {
    @Bean       // bounded reconnect backoff: Lettuce's default doubles to 30 s (§7.3)
    ClientResourcesBuilderCustomizer boundedReconnectBackoff() {
        return builder -> builder.reconnectDelay(Delay.exponential(Duration.ofMillis(10), Duration.ofMillis(500), 2, TimeUnit.MILLISECONDS));
    }

    @Bean       // fail fast while disconnected instead of buffering commands
    LettuceClientOptionsBuilderCustomizer failFastWhileDisconnected() {
        return builder -> builder.disconnectedBehavior(ClientOptions.DisconnectedBehavior.REJECT_COMMANDS);
    }

    @Bean       // JSON values (not JDK serialization), money keeps its scale; TTL/prefix still come from the properties
    RedisCacheManagerBuilderCustomizer jsonValues() {
        JsonMapper mapper = JsonMapper.builder().enable(DeserializationFeature.USE_BIG_DECIMAL_FOR_FLOATS).build();
        return builder -> builder.withCacheConfiguration("products", builder.cacheDefaults()
                .serializeValuesWith(SerializationPair.fromSerializer(new JacksonJsonRedisSerializer<>(mapper, Product.class))));
    }

    @Bean       // write before the @Cacheable method returns (§8.1); keeps statistics
    RedisCacheManagerBuilderCustomizer immediateCacheWrites(RedisConnectionFactory connectionFactory) {
        return builder -> builder.cacheWriter(RedisCacheWriter.create(connectionFactory, w -> w.immediateWrites().collectStatistics()));
    }
}

@Configuration(proxyBeanMethods = false)
class TolerateCacheFailures implements CachingConfigurer {      // a cache failure becomes a miss, not a failed request (§8.2)
    @Override
    public CacheErrorHandler errorHandler() {
        return new CacheErrorHandler() {
            @Override public void handleCacheGetError(RuntimeException e, Cache cache, Object key) { /* count + log at debug */ }
            @Override public void handleCachePutError(RuntimeException e, Cache cache, Object key, Object value) { }
            @Override public void handleCacheEvictError(RuntimeException e, Cache cache, Object key) { /* evict failures = staleness: alert */ }
            @Override public void handleCacheClearError(RuntimeException e, Cache cache) { }
        };
    }
}
```

Boot 4.1.2's customizer types live in `org.springframework.boot.data.redis.autoconfigure` (`ClientResourcesBuilderCustomizer`, `LettuceClientOptionsBuilderCustomizer`) and `org.springframework.boot.cache.autoconfigure` (`RedisCacheManagerBuilderCustomizer`). An *evict* failure is not like a get failure: it leaves stale data behind, so count it and alert rather than silently swallowing it.

---

## 10. ❌ Naïve vs ✅ production-hardened

| ❌ Naïve | ✅ Hardened |
|---|---|
| Lettuce's 60 s default timeout | `spring.data.redis.timeout` sized as a cache budget (§6) |
| `@Cacheable` with no error handler | `CacheErrorHandler` (treat failures as misses) + a breaker for sustained outages (§8.2) |
| `cache-null-values: false` and methods that can return `null` | `unless = "#result == null"` or a cached "not found" marker (§8.3) |
| Default async cache writes for expensive loaders | `immediateWrites()` (§8.1: 21–59 of 200 duplicate loads → 0) |
| `volatile-lru` on a cache whose keys have no TTL | `allkeys-lfu` for caches; `volatile-*` only where every key expires (§3) |
| One instance for cache + sessions + locks | Separate instances per durability and eviction need |
| "Redis replicates, so acknowledged writes are safe" | Async replication lost 38 acknowledged writes; `WAIT` for writes that matter, or don't store them only in Redis (§7) |
| Default reconnect backoff | Capped backoff; recovery = detection + (retried) failover + reconnect (§7.3) |
| Millions of tiny top-level keys | Listpack hash buckets for small values (110 → 44 B/item), within the encoding thresholds (§2) |
| `KEYS *`, `FLUSHALL` reachable from the app | ACL user with `-@dangerous` and a key-prefix pattern (§9.2) |
| Inline comments in `redis.conf` | Comments on their own lines (the server refused to start) |
| Tests against a shared Redis without isolation | `FLUSHDB` or a unique prefix per test (§1) |

---

## 11. Bar-raiser Q&A 🔥

🎤 *"We put Redis in front of the product database. If Redis is down we just hit the database."*

🔍 **Is that what your code actually does?**

<details><summary>🛡️ Defense</summary>

Not by default in Spring. Verified:

* **No error handler:** a 2 s Redis stall made `@Cacheable` throw `QueryTimeoutException` after the 250 ms command timeout, so the request *failed*.
* **With Lettuce's default timeout:** the same read would have blocked for the entire stall (60 s maximum).

"Fall back to the database" needs three things:

* a short command timeout;
* a `CacheErrorHandler` that turns failures into misses;
* a circuit breaker around the cache, so a dead Redis doesn't cost 250 ms of timeout on every get *and* put.

Then the database must be sized to take the full miss traffic, or the fallback converts a Redis outage into a database outage ([6.4 §3.2](04-Cache-Stampede-Penetration-Avalanche-Invalidation.md#32-losing-the-cache-tier)).
</details>

🔍 **The cache uses `volatile-lru`. Good choice?**

<details><summary>🛡️ Defense</summary>

Only if every evictable key has a TTL. Verified: with no TTLs, `volatile-lru` evicted nothing and **14,760 writes failed** with OOM, exactly like `noeviction`. Worse, other writes on that instance (locks, rate limits) fail too. For a pure cache, `allkeys-lfu` had the best hit rate on a Zipf workload (83.1 % vs LRU 81.3 %, random 78.2 %). The bigger lever is memory: the workload, not the policy, set the ~80 % ceiling.
</details>

🔍 **We store rate-limit counters and idempotency keys in Redis with a replica and Sentinel. Are they safe through a failover?**

<details><summary>🛡️ Defense</summary>

No. Replication is asynchronous: in my failover test the primary had acknowledged values up to 121, and the promoted replica had 83, so **38 acknowledged writes vanished** with no error. For rate limits that's usually acceptable (a brief over-allowance). For idempotency keys it's a double-charge risk, so they belong in the database transaction ([5.9 §8.3](../05-Microservices-Patterns/09-Microservices-Patterns-Catalog-Flows-Failure-Modes-Spring-Code.md)). If Redis must hold them, `WAIT 1 <ms>` after the write, treating a 0 reply as "not durable": that test lost 0 confirmed writes. Even then, Sentinel doesn't guarantee to promote the most up-to-date replica when there are several, so `WAIT` narrows the window rather than making Redis strongly consistent.
</details>

🔍 **How long is a Redis failover, end to end?**

<details><summary>🛡️ Defense</summary>

It has three terms, and I measured both a fast and a slow case:

* **Detection:** `down-after-milliseconds`.
* **Failover:** retried after **2 × `failover-timeout`** if the first attempt can't use a replica.
* **Client reconnect:** Lettuce backs off exponentially to 30 s by default.

The fast case was 1.75 s with a 1 s detection window. When the replica was briefly unresponsive, Sentinel waited 10 s to retry (`Next failover delay: …`), and the client's backoff added ~5 s more: 17.5 s. Capping the reconnect delay at 500 ms brought that to 12.6 s. The production levers are healthy replicas, a `failover-timeout` you've consciously chosen, a bounded reconnect backoff, and an alert on `+switch-master`.
</details>

🔍 **We read a product right after loading it and still see two database queries. Why?**

<details><summary>🛡️ Defense</summary>

Spring Data Redis 4 writes cache entries asynchronously with Lettuce: the `@Cacheable` method returns before its `SET` reaches Redis. `MONITOR` showed the second call's `GET` arriving before the first call's `SET`. Measured: 21–59 of 200 immediate re-reads missed and reloaded. `RedisCacheWriter.create(cf, w -> w.immediateWrites())` made it 0. Whether to pay the write latency depends on how expensive the loader is: for a 500 ms query or a burst of identical requests, pay it.
</details>

🔍 **Client-side caching or a Caffeine L1?**

<details><summary>🛡️ Defense</summary>

* **RESP3 tracking:** the server invalidates the keys *you read* whenever *anyone* writes them. Verified: 100 server reads instead of 10,000, and another client's `SET` removed the local copy. That beats a hand-built pub/sub scheme that misses a write path.
* **What it costs:** Redis 6+, RESP3, a bounded local map (the Lettuce example map is unbounded), and a full local flush on reconnect, because invalidations sent while disconnected are lost.
* **When I'd still use Caffeine + pub/sub:** for computed objects that aren't one-to-one with Redis keys.
</details>

---

## Summary

| Topic | Key point | Evidence |
|---|---|---|
| Re-verification | 6.3/6.4 labs identical on real Redis 8.10.2 | §1 |
| Memory | ~70 B overhead per key; listpack buckets 2.5× smaller for small values; thresholds 512 / 64 in 8.10.2 | §2 |
| Eviction | `allkeys-lfu` best on Zipf; `volatile-*` without TTLs = failed writes | §3 |
| Client-side caching | Server-pushed invalidation; 100× fewer reads; bound the map, flush on reconnect | §4 |
| Round trips | Pipelining 13×, `MSET` 36× (loopback) | §5 |
| Timeouts | Lettuce default 60 s; set a cache-sized timeout | §6 |
| Failover | Async replication lost 38 acked writes; `WAIT` 0; recovery = detect + failover (×retry) + reconnect | §7 |
| Spring cache | Async writes (dup loads), stall → exception, `null` → exception, all fixable | §8 |
| Blueprints | `redis.conf`, ACLs, sessions, Sentinel, Spring config: started/validated | §9 |

**Next:** [6.5 Bar-raiser drill-downs (Round 2 covers 6.6–6.7) →](05-Bar-Raiser-Drill-Downs.md)
