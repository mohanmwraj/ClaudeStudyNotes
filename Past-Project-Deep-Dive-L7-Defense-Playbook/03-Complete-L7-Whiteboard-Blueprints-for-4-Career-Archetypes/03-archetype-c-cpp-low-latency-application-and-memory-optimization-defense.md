# 03.3 · Archetype C: C++ Low-Latency Backend and Caching Engine (Memory Layout, Eviction, Tail Latency)

> **Folder:** `03-Complete-L7-Whiteboard-Blueprints-for-4-Career-Archetypes` · file 3 of 4
> **Question this file answers:** I built a latency-critical C++ component: an in-process cache, an order book, a feature store, a matching engine. How do I defend its data structures, memory discipline, concurrency and tail latency against Principal Engineers who will ask for probe lengths, allocation counts, cache-line layouts and *how you measured p99*?
> **Composite exhibit:** "Quickset", an in-process feature cache inside a C++ ranking service. The numbers are placeholders except where the listing computes them.
> **Scope labels:** L5 = Senior, L6 = Staff, L7 = Principal / Senior Staff.

| Listing | Language | What it does | Where it runs |
|---|---|---|---|
| L9 `quickset.cpp` | C++23 (Clang 21 via Zig, libc++) | Measures, deterministically:<br>1. linear-probing probe lengths against theory at 3 load factors (average and worst case);<br>2. heap allocations per insert for a pre-sized flat table vs `std::unordered_map`, counted by a replacement `operator new`;<br>3. LRU, FIFO, CLOCK and S3-FIFO hit ratios on a seeded Zipf trace, with and without one-hit-wonder scans;<br>4. cache-line padding checked at compile time. | [§12](#12-listing-and-output), built with `-std=c++23 -O2 -Wall -Wextra -Werror -pedantic` |

**Verification.** The gate extracts the listing, checks it byte for byte against the source, compiles it with warnings treated as errors, runs it, and compares the output with §12. Every printed number is deterministic: no timers, and a fixed PRNG seed. The program prints `verdict: OK` only if its 7 checks pass. Tellings and the ledger are checked by the Folder 01 tools. Results are in the [README](../README.md#gate-results).

---

## 0. Orientation

**Who this archetype fits.** C++ engineers on latency-critical paths: ad serving, ranking, search, trading, gaming backends, storage engines, network services. Typical résumé lines: "built a lock-free cache serving N M lookups/s", "reduced p99 from X ms to Y µs", "custom allocator", "NUMA-aware".

**Why it's dangerous in a deep dive.** Low-latency claims are the easiest to inflate and the easiest to puncture. The interviewers will ask how p99 was measured (coordinated omission, 02.2 §3.6), how many allocations the hot path makes, what happens at high load factors, how readers and writers avoid racing, and why you didn't use an existing library. They often know the hardware better than the candidate. Precise numbers, and honesty about which ones were measured, carry this round.

---

## 1. First principles: what interviewers assume about this archetype

### 1.1 The attack surface

| Claim | What they suspect | The probe | What survives |
|---|---|---|---|
| "p99 250 ns" | Measured in a closed-loop microbenchmark | "Under what load, measured how?" | Production histograms at a fixed arrival rate, with the method stated (§7) |
| "Lock-free" | A spinlock, or `std::atomic` used incorrectly | "What memory orders, and why?" | The publication protocol and its acquire/release pairs (§5) |
| "Zero allocations" | True only after warm-up | "Count them." | Allocation counts in tests, with an allocator hook (§12) |
| "Custom hash map is faster" | Benchmark-only, never checked at high load | "What's your worst probe at 0.875?" | The average *and* the tail, and the load-factor cap (§4.2) |
| "Built our own" | Not-invented-here | "Why not an existing library?" | Requirements an existing library failed, with a measured test (§8) |

### 1.2 The physics a C++ deep dive must respect

- **Latency budgets are hierarchical.** An L1 cache hit costs on the order of a nanosecond, a DRAM access on the order of 100 ns, a context switch microseconds, a same-zone network round trip hundreds of microseconds. Treat these as rough orders of magnitude and quote your own hardware's measurements.
- **Tail latency comes from rare events,** not slow code: allocations, page faults, lock convoys, cache misses, scheduler preemption, GC in neighbors, fan-out (02.2 §3.3).
- **Memory is the budget that fails loudly.** An in-process cache that grows without an exact byte limit is an OOM-kill waiting to happen.

---

## 2. The composite project: "Quickset" fact sheet

### 2.1 Before-state

- **Request shape:** a C++ ranking service scores ~200 candidates per request using ~15 features each, so **~3,000 feature lookups per request**. Each host serves ~2,000 requests/s, which is **~6M lookups/s per host**.
- **Where features lived:** a 32-shard Redis cluster, fetched with batched multi-gets that fan out to all 32 shards.
- **Fan-out tail:** with 32 shards, **1 − 0.99³² ≈ 27.5%** of requests touched at least one shard's p99.
- **Latency against the SLO:**
  - feature-fetch p99 ≈ **9 ms**;
  - ranking p99 **41 ms**, against a **25 ms** SLO.
- **CPU:** ~30% of the service's CPU went to request serialization and response parsing.

### 2.2 Goals and kill criteria

| ID | Goal | Threshold | Kind |
|---|---|---|---|
| K1 | Feature-fetch time per request | p99 ≤ 3 ms for ~3,000 lookups | Kill |
| K2 | Ranking quality with cache misses | Offline AUC loss ≤ 0.001 vs complete features | Kill |
| K3 | Memory per host | Hard cap 12 GB for the cache, enforced in bytes | Kill |
| K4 | Freshness of features | Updates visible within 30 s p99 | Kill |
| G5 | CPU per request | Lower than the Redis path | Scored |

### 2.3 Architecture after (ownership marked)

| # | Component | Mark | What it does |
|---|---|---|---|
| C1 | Sharded flat table | ★ designed and wrote | Per-core shards; open addressing, linear probing, 16-byte slots, backward-shift delete; load factor capped at 0.75 |
| C2 | Slab arena for values | ★ | Size classes for feature vectors; no allocation on the read path; exact byte accounting per feature group |
| C3 | Publication protocol | ★ | One update thread per shard writes; readers are lock-free: values are immutable once published and retired by epoch (§5) |
| C4 | S3-FIFO eviction | ★ chose and implemented (after INC-Q2) | Small FIFO + main FIFO + ghost queue; evicts by bytes, not entry count |
| C5 | Update stream consumer | ◆ (the feature platform team owns the stream) | Applies feature updates from a change stream, using versions per key; a backfill flag bypasses admission |
| C6 | Miss path | ★ policy; ○ Redis | Asynchronous fill from Redis; the current request uses the model's default for that feature (K2 measured) |
| C7 | Instrumentation | ★ | Per-shard hit/miss/evict counters (padded), HdrHistogram latency recording, allocation counters in tests |
| C8 | Ranking service | ○ (ranking team) | Calls Quickset in-process through a batched `get_many` |

### 2.4 Scale, team, timeline, outcomes

| Fact | Value | Provenance |
|---|---|---|
| Lookups | ~6M/s per host | [E] 2,000 req/s × 3,000 |
| Entries cached per host | ~8M | [M] |
| Index memory | 8M ÷ 0.75 × 16 B ≈ **171 MB** | [E] |
| Value memory | 8M × ~1.1 KB ≈ **8.8 GB**, + ~10% arena overhead ≈ 9.7 GB, within the 12 GB cap | [E] |
| Lookup latency, in process | p50 ~60 ns, p99 ~250 ns per key (production sampling, fixed-rate load test) | [M] |
| Feature-fetch per request | p99 9 ms → **0.9 ms** | [M] |
| Hit ratio | 96.8% steady state | [M] |
| Ranking p99 | 41 → **22 ms** (25 ms SLO) | [M] canary vs control |
| Quality | AUC loss 0.0004 at a 3% miss rate (offline replay) | [M] |
| Redis cluster | 32 → 8 shards (it now serves only misses) | [M] |
| Team | Me (tech lead, C++), 3 engineers, 1 ML-infra partner; 7 months | — |

---

## 3. The whiteboard blueprint

```text
 ENTERPRISE BAND (thin): feature platform + change stream (o) | Redis (o, misses only) | ML training (o) | fleet: 2-socket hosts (o)

 ranking request --> [ranking service (o)] --get_many(3,000 keys)--> [[ QUICKSET * ]] (in process)
                                                                       |  shard = hash(key) % cores
                            +------------------------------------------+-------------------------------+
                            | shard 0 ... shard N-1   (one per core)                                    |
                            |  [[ flat table * ]] 16-B slots, LP, load <= 0.75 --> [[ slab arena * ]]   |
                            |  readers: lock-free, epoch-protected      writer: 1 update thread/shard   |
                            |  [[ S3-FIFO * ]] small 10% | main 90% | ghost      evict by bytes         |
                            +------------------------------------------------------------------------- +
          change stream (o) --versions--> update threads <> ;   miss --> async fill from Redis (o)
 numbers: 6M lookups/s/host | 8M entries | 171 MB index + 9.7 GB values | p99 0.9 ms/request | hit 96.8%
```

| Phase | What to draw and say for Archetype C |
|---|---|
| Context | 3,000 lookups per request; the 32-shard fan-out tail (27.5%); ranking p99 41 ms vs a 25 ms SLO |
| Architecture | Request → in-process `get_many` → shard → table → arena; the update path separately |
| Depth menu | (1) memory layout and probing, (2) the publication protocol (readers vs writer), (3) eviction and INC-Q2 |
| Failure | INC-Q2: a backfill flood collapsed the LRU hit ratio (§6) |
| Trade-offs | Tuned Redis vs localhost memcached vs an existing in-process library vs build (§8) |
| Hindsight | Per-feature-group byte accounting from day 1; NUMA-replicated shards (§9) |

#### How an L5 tells it

> I worked on a high-performance C++ cache for our ranking service. It was lock-free and blazingly fast, with way better latency than Redis. We used a custom hash map and a smarter eviction policy, which made it super scalable.

#### How an L7 tells it

> Quickset is an in-process feature cache inside a C++ ranking service. Each request scores about 200 candidates with about 15 features, so 3,000 lookups, and fetching them from a 32-shard Redis meant about 27% of requests hit at least 1 shard's tail; ranking p99 was 41 milliseconds against a 25-millisecond SLO. I led a team of 4 and designed the core: per-core shards of a flat open-addressing table with 16-byte slots and a slab arena for values, so the read path never allocates, readers that never take a lock, and S3-FIFO eviction by bytes under a hard 12-gigabyte cap. Feature fetch went from 9 milliseconds to 0.9 at p99, ranking p99 to 22 milliseconds, and the cost of the 3.2% of lookups that miss and use defaults is an AUC loss of 0.0004 in offline replay.

---

## 4. Deep well 1: memory layout, probing and allocation discipline

### 4.1 The slot and the line

- **The slot is 16 bytes:** an 8-byte key hash, a 4-byte arena offset, and 4 bytes of metadata (used flag, size class, version low bits).
- **Four slots per 64-byte cache line,** so a probe sequence of length ≤ 4 that starts at a line boundary costs one line fill.
- **Values live in the arena, not in the table.** The table stays small and cache-resident for its hot part: 171 MB of index against 9.7 GB of values.

### 4.2 Probe lengths: the average is fine, the tail is not

For linear probing, the expected number of probes for a successful lookup is about ½(1 + 1/(1 − α)) at load factor α (Knuth, *The Art of Computer Programming*, vol. 3). The listing measures it on 65,536 slots:

| Load α | Measured average | Theory | **Worst case** |
|---|---|---|---|
| 0.50 | 1.49 | 1.50 | 25 |
| 0.75 | 2.45 | 2.50 | 105 |
| 0.875 | 4.26 | 4.50 | **289** |

**The worst case is the latency story.** At 0.875, the average lookup is 4 probes, which is fine, but some keys need 289 because of primary clustering. Those keys are your p99.9. That's why Quickset caps load at **0.75** and resizes incrementally: a background rehash moves a bounded number of buckets per update-thread tick, so no reader ever sees a stop-the-world resize.

### 4.3 Allocation discipline

- **The pre-sized flat table makes 0 heap allocations** while inserting 100,000 entries. `std::unordered_map`, even with `reserve`, makes **100,000**: one 32-byte node per entry with libc++ (§12).
- **On the read path that's the difference** between "no allocator involvement" and "allocator lock or thread cache on every miss-fill".
- **Quickset's rules:**
  - The arena carves values from 2 MB slabs.
  - Size classes are fixed at startup.
  - The update thread is the only allocator.
  - Readers never allocate.
- **Tests count allocations** with a replacement `operator new`, as the listing does, so "zero allocations" is asserted, not hoped for.

#### How an L5 tells it

> We wrote our own hash map, which was a lot faster than std::unordered_map, and we used a custom allocator so allocations were pretty much eliminated. It was highly optimized for performance.

#### How an L7 tells it

> The table is open addressing with linear probing and 16-byte slots, 4 per cache line, holding a key hash and an offset into a slab arena where the values live, so the 8 million entries need about 171 megabytes of index. I cap the load factor at 0.75, because the average probe count is fine at higher loads, but in my test at 0.875 the worst key needed 289 probes, and those keys become the p99.9. The read path makes 0 heap allocations: values are carved from 2-megabyte slabs by the single update thread per shard, and a test with a replacement operator new asserts that 100,000 inserts allocate nothing, where std::unordered_map makes 100,000 node allocations.

---

## 5. Deep well 2: concurrency without locks on the read path

### 5.1 The publication protocol

1. **One writer per shard:** the update thread. Readers are the ranking threads, many per shard.
2. **The writer builds the new value completely in the arena,** then publishes it with one **release** store of the slot's (offset | version) word.
3. **Readers load that word with an acquire load.** That guarantees they see the value's bytes as written before the publish.
4. **Old values are not freed immediately.** They go on a retire list, and are reclaimed only after every reader thread has passed a quiescent point (an epoch counter each reader bumps between requests). A reader that loaded the old offset a microsecond ago can still safely read it. This is epoch-based reclamation, the same idea as RCU.
5. **Writes to the table structure** (inserts and backward-shift deletes) are also done by the single writer. Readers may race with a shift and miss a key momentarily. They then report a miss, which is allowed: a miss is handled (K2). Readers never read a torn value, because values are immutable once published.

**The claim worth making precisely:** "lock-free *for readers*, single-writer per shard, with immutable published values and epoch reclamation". Not "lock-free" unqualified.

### 5.2 False sharing

- **The problem:** per-shard hit/miss counters written by different cores must not share a cache line. If they do, every increment invalidates the line in the other cores' caches.
- **The listing's layout check:** 8 unpadded 8-byte counters fit in one 64-byte line. Padded to `alignas(64)`, they take 512 bytes, one line each. The cost is 448 bytes per 8 shards, which is trivial.
- **C++17's `std::hardware_destructive_interference_size`** ([cppreference](https://en.cppreference.com/w/cpp/thread/hardware_destructive_interference_size)) names the constant, but implementations differ in whether and how they define it. The listing uses an explicit 64 with a comment, so its behavior doesn't depend on the toolchain.
- **Prove it on the real hardware:** cache-line contention shows up in tools such as Linux `perf c2c` ([man page](https://man7.org/linux/man-pages/man1/perf-c2c.1.html)). Quickset's counters showed up as the top contended line before padding.

#### How an L5 tells it

> The cache is lock-free, so reads and writes basically never block each other. We used atomics everywhere to keep it thread-safe and fast.

#### How an L7 tells it

> Readers are lock-free and the writer is single-threaded per shard, which is a narrower claim than 'lock-free'. The update thread builds a value completely in the arena and publishes it with 1 release store of the slot's offset-and-version word, and readers use an acquire load of that word, so they always see a complete value. I never free the old value immediately: it waits on a retire list until every reader thread has passed a quiescent point between requests, which is epoch-based reclamation. A reader racing with a backward-shift delete can miss a key for an instant; that shows up as a cache miss, which the ranking path already handles, and never as a torn read.

---

## 6. Deep well 3: eviction, and the failure that changed it (INC-Q2)

### 6.1 What the listing shows

On a 1,000-entry cache over a 100,000-key Zipf(0.99) universe (§12):

| Policy | Plain trace | With scans |
|---|---|---|
| LRU | 48.98% | 44.30% |
| FIFO | 44.87% | 40.66% |
| CLOCK | 50.13% | 45.30% |
| **S3-FIFO** | **58.20%** | **52.91%** |

S3-FIFO (Yang et al., "FIFO queues are all you need for cache eviction", SOSP 2023, DOI 10.1145/3600006.3613147) puts new keys in a small FIFO first. Keys that are never re-accessed, the "one-hit wonders", are evicted from there without ever disturbing the main queue. These are small-cache numbers from a synthetic trace. Quickset's production hit ratio (96.8%) comes from a much larger cache and a real trace, and the *ranking* of the policies is what transfers, not the absolute numbers.

### 6.2 INC-Q2

1. **Trigger.** The feature platform team backfilled a new feature for ~400M keys through the change stream. The v1 Quickset used LRU and admitted every update.
2. **Detection.** The hit ratio fell from 96% to 61% within 4 minutes. Ranking timeouts rose, and the ranking team's SLO alert paged.
3. **Bounding.** Every host in every region was affected: the backfill was global.
4. **Mitigation.** The feature platform paused the backfill. The hit ratio recovered over 25 minutes as the cache re-warmed from Redis.
5. **Root cause, mine.** I had treated "update for a key" and "access to a key" as the same event, so a backfill of cold keys evicted the hot working set. The policy wasn't scan-resistant, and admission wasn't separated from update.
6. **Fix.**
   - Updates for keys that aren't resident no longer admit them.
   - Backfills carry a flag, so they update only resident keys.
   - Eviction moved to S3-FIFO, which is scan-resistant even for read-driven scans.
7. **Systemic.** A replay test now runs a backfill-shaped trace in CI and asserts that the hit ratio stays within 2 points.

#### How an L5 tells it

> At one point a big data load caused cache performance to drop a lot, so we switched to a better eviction algorithm and it was much more robust after that.

#### How an L7 tells it

> INC-Q2 was my design error. The feature platform backfilled about 400 million keys for a new feature, and my version 1 treated every update as an access: it admitted every key and evicted by LRU. The backfill flushed the hot working set, and the hit ratio fell from 96% to 61% in 4 minutes, with ranking timeouts on every host. The platform team paused the backfill, and the cache took 25 minutes to re-warm. The fix separated admission from update: an update for a non-resident key no longer admits it, and backfills carry a flag that limits them to resident keys. I moved eviction to S3-FIFO, which also survives read-side scans, and a CI test replays a backfill-shaped trace and fails if the hit ratio drops more than 2 points.

---

## 7. Tail latency: measuring it honestly

| Pitfall | Quickset's practice |
|---|---|
| **Closed-loop benchmarks** under-sample the slow periods (coordinated omission; 02.2 §3.6) | Load tests at a fixed arrival rate, recording intended start times ([HdrHistogram](http://hdrhistogram.org/)) |
| **Microbenchmark vs production** | The per-key ~250 ns p99 comes from production sampling (1 in 1,024 calls timed with the TSC); the per-request 0.9 ms p99 from the ranking service's own histograms |
| **Averaged percentiles** | Per-host HdrHistograms merged, then the percentile taken (02.2 §1.3) |
| **Warm vs cold** | Cold-start behavior measured separately: a new host warms in ~90 s, held out of rotation until the hit ratio passes 90% |
| **The p99 that matters** | The *request* p99 (3,000 lookups), not the per-key p99. With 3,000 lookups, per-key tails compound like fan-out (02.2 §3.3). |

#### How an L5 tells it

> The cache has a p99 latency of around 250 nanoseconds, which we measured with benchmarks. It's basically orders of magnitude faster than Redis.

#### How an L7 tells it

> Two numbers, measured differently, and I quote them separately. Per key, p99 is about 250 nanoseconds, from production sampling: 1 call in 1,024 is timed with the timestamp counter into a per-thread HdrHistogram, and the histograms are merged before taking the percentile. Per request, the number that matters for the SLO, the feature-fetch p99 is 0.9 milliseconds for about 3,000 lookups. That comes from the ranking service's histograms under a fixed-arrival-rate load test, so the slow periods aren't under-sampled. I don't quote the microbenchmark number, 41 nanoseconds, because it runs with a hot cache and no contention, which production never has.

---

## 8. Why not simpler? (build vs buy, three options + Option Zero)

| Option | Fails | Kept from it |
|---|---|---|
| Option Zero: tune Redis (bigger batches, replicas, hedged multi-gets) | K1: 32-shard fan-out keeps ~27% of requests in a shard tail; hedging doubles load | Redis stays as the miss path, at 8 shards |
| Localhost memcached sidecar | K1: a syscall plus serialization per batch; measured ~1.8 ms p99 per request for 3,000 keys, and G5 CPU worse | — |
| Existing in-process C++ cache library | Prototype met K1, but failed K3: per-entry allocations and count-based eviction made byte-exact caps unenforceable without forking it | Its sharding API shape |
| Quickset (chosen) | — | Cost: ~3 engineer-years to build, ~0.5 FTE to run |

**The honest build-vs-buy statement:** "I prototyped the library for 2 weeks. It met latency but not the byte-exact memory cap. Forking it to add an arena would have meant maintaining a fork of something we didn't design. If the library had supported custom allocators with byte accounting, I'd have used it."

#### How an L5 tells it

> Existing libraries didn't really fit our use case, so we decided to build our own cache, which gave us full control and better performance.

#### How an L7 tells it

> I prototyped the strongest existing in-process library for 2 weeks before writing a line of Quickset. It met the latency target, about 1.1 milliseconds p99 per request in the same load test, so build-versus-buy wasn't about speed. It failed the memory requirement: entries were individually allocated and eviction counted entries, not bytes, so a 12-gigabyte hard cap couldn't be enforced when feature vectors vary from 200 bytes to 6 kilobytes. Adding an arena meant forking it. I estimated the fork at about 1.5 engineer-years to maintain over 3 years, against about 3 engineer-years to build and own Quickset, and chose to build because we'd own a design we understood. If the library had supported custom allocators with byte accounting, I'd have used it.

---

## 9. Constraints and hindsight

<!-- ledger:start name=c-quickset -->
| ID | Constraint | Category | Source | Hardness | Evidence it was real | Design consequence | Cost paid | Revisit trigger |
|---|---|---|---|---|---|---|---|---|
| TC1 | Cache memory per host capped at 12 GB | Budget | Fleet capacity plan (host shape fixed for 3 years) | Hard | Capacity plan; host memory 64 GB shared by the ranking model and 2 sidecars | Byte-exact accounting; eviction by bytes; slab arena | ~2 engineer-months of accounting work | New host shape, or the model moving to accelerators |
| TC2 | Ranking service is C++; the cache must be in-process | Legacy | Ranking team's service | Hard | The service's language and build system; a cross-process hop measured at 1.8 ms p99 per request | C++ library with a batched get_many API | No reuse of the Java feature-client code: ~4 engineer-months rewriting its parsing and versioning | Ranking service rewrite |
| TC3 | Missing features degrade quality, not correctness | Stakeholder | ML team's model-quality bar | Negotiable | Offline replay: AUC loss 0.0004 at a 3% miss rate | Misses use the model's default; asynchronous fill | 3.2% of lookups served by default values | A model whose AUC loss per 1% of misses exceeds 0.001 |
| TC4 | 2-socket hosts; remote-socket memory access is slower | Scale | Fleet hardware | Hard | Measured ~1.6x latency for remote-socket reads on this host type | v1: interleaved memory; v2: per-socket shard replicas | ~11% of lookups crossed sockets in v1 | Single-socket host shape |
<!-- ledger:end -->

**Hindsight:**
- **Byte accounting per feature group from day 1.** It was added after one feature group's vectors doubled in size and crowded out others. A good decision with a bad outcome? No: a bad decision, because the size variance was known.
- **Admission separated from update from day 1.** INC-Q2.
- **NUMA.** Per-socket shard replicas, in place of interleaving. A good decision for v1 (simpler); the trigger is now met.

---

## 10. Numbers card (Archetype C)

| Number | Value | Re-derive |
|---|---|---|
| Lookups per request / per host | ~3,000 / ~6M/s | 200 × 15; × 2,000 req/s |
| Redis fan-out tail | ~27.5% | 1 − 0.99³² |
| Index memory | ~171 MB | 8M ÷ 0.75 × 16 B |
| Value memory | ~9.7 GB | 8M × 1.1 KB × 1.1 |
| Probe worst case at 0.875 | 289 | Listing |
| Allocations per insert | 0 vs 1 | Listing |
| Hit ratio (production) | 96.8% | Counters |
| Feature-fetch p99 | 9 → 0.9 ms | Ranking histograms |
| Ranking p99 | 41 → 22 ms | Canary vs control |
| Quality | AUC −0.0004 at 3% misses | Offline replay |

---

## 11. Hiring-committee scoring rubric: Archetype C

| Dimension | Poor | Borderline | Solid (L6) | Outstanding (L7) |
|---|---|---|---|---|
| **Data structure** | "Custom hash map" | Names open addressing | Load factor, slot layout, probe average | Probe *tail*, the load cap that follows from it, incremental resize |
| **Memory** | "Efficient" | Arena mentioned | Allocation counts asserted in tests | Byte-exact caps, size classes, fragmentation accounting |
| **Concurrency** | "Lock-free" | Atomics named | Publication with acquire/release | Plus reclamation (epochs/RCU), and what readers may observe during writes |
| **Latency** | One microbenchmark number | p99 quoted | Production histograms | Fixed-rate measurement, per-key vs per-request p99, coordinated omission avoided |
| **Eviction** | "LRU" | A named policy | Hit ratio measured | Admission vs update separated; scan resistance; owns INC-Q2 |
| **Build vs buy** | NIH | "Didn't fit" | The requirement a library failed | Prototype evidence, maintenance cost estimate, the condition under which they'd buy |

---

## 12. Listing and output

### 12.1 Listing L9: `quickset.cpp`

<!-- listing:quickset.cpp -->
```cpp
// quickset.cpp - the Archetype C mechanisms, measured deterministically:
//   1. open addressing: probe lengths vs linear-probing theory at 3 load factors
//   2. allocation discipline: 0 heap allocations per insert (pre-sized flat
//      table) vs 1 per insert (node-based std::unordered_map), counted by a
//      replacement operator new
//   3. eviction: LRU vs FIFO vs CLOCK vs S3-FIFO hit ratios on a seeded Zipf
//      trace, with and without one-hit-wonder scans
//   4. layout: per-shard counters padded to a cache line (compile-time checks)
// Build: zig c++ -std=c++23 -O2 -Wall -Wextra -Werror -pedantic quickset.cpp
#include <algorithm>
#include <atomic>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <deque>
#include <list>
#include <new>
#include <unordered_map>
#include <unordered_set>
#include <vector>

static std::size_t g_allocs = 0;
static std::size_t g_bytes = 0;

void* operator new(std::size_t n) {
    ++g_allocs;
    g_bytes += n;
    if (void* p = std::malloc(n ? n : 1)) return p;
    throw std::bad_alloc();
}
void operator delete(void* p) noexcept { std::free(p); }
void operator delete(void* p, std::size_t) noexcept { std::free(p); }

static std::uint64_t splitmix64(std::uint64_t x) {
    x += 0x9e3779b97f4a7c15ULL;
    x = (x ^ (x >> 30)) * 0xbf58476d1ce4e5b9ULL;
    x = (x ^ (x >> 27)) * 0x94d049bb133111ebULL;
    return x ^ (x >> 31);
}

// ---- 1. Flat open-addressing map: 16-byte slots, linear probing, backward-shift delete.
struct Slot {
    std::uint64_t key;
    std::uint32_t value;
    std::uint32_t used;
};
static_assert(sizeof(Slot) == 16, "4 slots per 64-byte cache line");

class FlatMap {
public:
    explicit FlatMap(std::size_t capacity_pow2) : slots_(capacity_pow2), mask_(capacity_pow2 - 1) {}

    bool insert(std::uint64_t key, std::uint32_t value) {
        for (std::size_t i = splitmix64(key) & mask_;; i = (i + 1) & mask_) {
            Slot& s = slots_[i];
            if (!s.used) {
                s = Slot{key, value, 1};
                ++size_;
                return true;
            }
            if (s.key == key) {
                s.value = value;
                return false;
            }
        }
    }

    const std::uint32_t* find(std::uint64_t key, std::size_t& probes) const {
        probes = 0;
        for (std::size_t i = splitmix64(key) & mask_;; i = (i + 1) & mask_) {
            ++probes;
            const Slot& s = slots_[i];
            if (!s.used) return nullptr;
            if (s.key == key) return &s.value;
        }
    }

    bool erase(std::uint64_t key) {
        std::size_t i = splitmix64(key) & mask_;
        for (;; i = (i + 1) & mask_) {
            if (!slots_[i].used) return false;
            if (slots_[i].key == key) break;
        }
        // Backward-shift deletion: no tombstones, so probe lengths don't decay with churn.
        for (std::size_t j = (i + 1) & mask_;; j = (j + 1) & mask_) {
            if (!slots_[j].used) break;
            std::size_t home = splitmix64(slots_[j].key) & mask_;
            if (((j - home) & mask_) >= ((j - i) & mask_)) {
                slots_[i] = slots_[j];
                i = j;
            }
        }
        slots_[i].used = 0;
        --size_;
        return true;
    }

    std::size_t size() const { return size_; }
    std::size_t capacity() const { return slots_.size(); }

private:
    std::vector<Slot> slots_;
    std::size_t mask_;
    std::size_t size_ = 0;
};

// ---- 3. Eviction policies over a key trace.
struct Lru {
    std::size_t cap;
    std::list<std::uint64_t> order;
    std::unordered_map<std::uint64_t, std::list<std::uint64_t>::iterator> where;
    bool access(std::uint64_t k) {
        auto it = where.find(k);
        if (it != where.end()) {
            order.splice(order.begin(), order, it->second);
            return true;
        }
        if (order.size() == cap) {
            where.erase(order.back());
            order.pop_back();
        }
        order.push_front(k);
        where[k] = order.begin();
        return false;
    }
};

struct Fifo {
    std::size_t cap;
    std::deque<std::uint64_t> q;
    std::unordered_set<std::uint64_t> in;
    bool access(std::uint64_t k) {
        if (in.count(k)) return true;
        if (q.size() == cap) {
            in.erase(q.front());
            q.pop_front();
        }
        q.push_back(k);
        in.insert(k);
        return false;
    }
};

struct Clock {
    std::size_t cap, hand = 0;
    std::vector<std::uint64_t> keys;
    std::vector<std::uint8_t> ref;
    std::unordered_map<std::uint64_t, std::size_t> where;
    bool access(std::uint64_t k) {
        auto it = where.find(k);
        if (it != where.end()) {
            ref[it->second] = 1;
            return true;
        }
        if (keys.size() < cap) {
            where[k] = keys.size();
            keys.push_back(k);
            ref.push_back(0);
            return false;
        }
        while (ref[hand]) {       // second chance: clear the bit and move on
            ref[hand] = 0;
            hand = (hand + 1) % cap;
        }
        where.erase(keys[hand]);
        keys[hand] = k;
        ref[hand] = 0;
        where[k] = hand;
        hand = (hand + 1) % cap;
        return false;
    }
};

// S3-FIFO (Yang et al., SOSP 2023): small FIFO (10%), main FIFO with a 2-bit
// frequency, and a ghost FIFO of recently evicted keys. One-hit wonders die in
// the small queue without disturbing the main queue.
struct S3Fifo {
    std::size_t cap, small_cap, main_cap;
    std::deque<std::uint64_t> small, main_q, ghost;
    std::unordered_map<std::uint64_t, std::uint8_t> freq;   // resident keys -> 0..3
    std::unordered_set<std::uint64_t> in_small, ghost_set;
    explicit S3Fifo(std::size_t c) : cap(c), small_cap(c / 10), main_cap(c - c / 10) {}
    void evict_main() {
        while (true) {
            std::uint64_t k = main_q.front();
            main_q.pop_front();
            auto& f = freq[k];
            if (f > 0) {
                --f;
                main_q.push_back(k);
            } else {
                freq.erase(k);
                return;
            }
        }
    }
    void insert_main(std::uint64_t k) {
        if (main_q.size() >= main_cap) evict_main();
        main_q.push_back(k);
        freq[k] = 0;
    }
    void evict_small() {
        std::uint64_t k = small.front();
        small.pop_front();
        in_small.erase(k);
        std::uint8_t f = freq[k];
        freq.erase(k);
        if (f > 0) {
            insert_main(k);
        } else {
            ghost.push_back(k);
            ghost_set.insert(k);
            if (ghost.size() > main_cap) {
                ghost_set.erase(ghost.front());
                ghost.pop_front();
            }
        }
    }
    bool access(std::uint64_t k) {
        auto it = freq.find(k);
        if (it != freq.end()) {
            if (it->second < 3) ++it->second;
            return true;
        }
        if (ghost_set.count(k)) {
            ghost_set.erase(k);           // its slot in the ghost deque ages out naturally
            insert_main(k);
            return false;
        }
        if (small.size() >= small_cap) evict_small();
        small.push_back(k);
        in_small.insert(k);
        freq[k] = 0;
        return false;
    }
};

struct Trace {
    std::vector<std::uint64_t> keys;
};

static Trace make_trace(std::size_t universe, std::size_t requests, double s, bool scans, std::uint64_t seed) {
    std::vector<double> cdf(universe);
    double sum = 0;
    for (std::size_t i = 0; i < universe; ++i) {
        sum += 1.0 / std::pow(static_cast<double>(i + 1), s);
        cdf[i] = sum;
    }
    Trace t;
    t.keys.reserve(requests + requests / 10);
    std::uint64_t state = seed;
    std::uint64_t scan_key = 1ULL << 40;
    for (std::size_t r = 0; r < requests; ++r) {
        state = splitmix64(state);
        double u = static_cast<double>(state >> 11) / 9007199254740992.0 * sum;
        std::size_t rank = static_cast<std::size_t>(std::lower_bound(cdf.begin(), cdf.end(), u) - cdf.begin());
        t.keys.push_back(rank);
        if (scans && r % 50000 == 49999) {
            for (int i = 0; i < 5000; ++i) t.keys.push_back(scan_key++);   // one-hit wonders
        }
    }
    return t;
}

template <class Policy>
static double hit_ratio(Policy p, const Trace& t) {
    std::size_t hits = 0;
    for (std::uint64_t k : t.keys) hits += p.access(k) ? 1 : 0;
    return 100.0 * static_cast<double>(hits) / static_cast<double>(t.keys.size());
}

// ---- 4. Layout: per-shard hit counters, padded so shards never share a cache line.
constexpr std::size_t kLine = 64;   // x86-64 and most AArch64 server parts
struct Unpadded {
    std::atomic<std::uint64_t> hits;
};
struct alignas(kLine) Padded {
    std::atomic<std::uint64_t> hits;
};
static_assert(sizeof(Unpadded) == 8, "8 shards share one line: false sharing");
static_assert(sizeof(Padded) == kLine && alignof(Padded) == kLine, "one shard per line");

int main() {
    int failed = 0, checks = 0;
    auto check = [&](bool ok, const char* what) {
        ++checks;
        if (!ok) ++failed;
        std::printf("  [%s] %s\n", ok ? "ok" : "FAIL", what);
    };

    std::printf("1. Linear probing: successful-lookup probes, 65,536 slots\n");
    std::printf("   load   measured avg   theory 1/2(1+1/(1-a))   max\n");
    double avg875 = 0;
    for (double load : {0.5, 0.75, 0.875}) {
        FlatMap m(1u << 16);
        std::size_t n = static_cast<std::size_t>(load * 65536);
        for (std::size_t i = 0; i < n; ++i) m.insert(splitmix64(i * 7919 + 1), static_cast<std::uint32_t>(i));
        std::size_t total = 0, worst = 0, probes = 0;
        for (std::size_t i = 0; i < n; ++i) {
            m.find(splitmix64(i * 7919 + 1), probes);
            total += probes;
            worst = std::max(worst, probes);
        }
        double avg = static_cast<double>(total) / static_cast<double>(n);
        if (load == 0.875) avg875 = avg;
        std::printf("   %.3f  %8.2f        %8.2f                %4zu\n", load, avg, 0.5 * (1 + 1 / (1 - load)), worst);
    }
    check(avg875 < 6.0, "average probes stay within ~1.3x of theory at load 0.875");

    {
        FlatMap m(1u << 10);
        for (std::uint64_t k = 0; k < 600; ++k) m.insert(k, static_cast<std::uint32_t>(k));
        for (std::uint64_t k = 0; k < 600; k += 2) m.erase(k);
        std::size_t probes = 0;
        bool all = true;
        for (std::uint64_t k = 1; k < 600; k += 2) all = all && m.find(k, probes) != nullptr && *m.find(k, probes) == k;
        for (std::uint64_t k = 0; k < 600; k += 2) all = all && m.find(k, probes) == nullptr;
        check(all && m.size() == 300, "backward-shift delete: 300 erased, 300 still found, no tombstones");
    }

    std::printf("2. Heap allocations while inserting 100,000 entries (tables pre-sized)\n");
    std::size_t flat_allocs, flat_bytes, node_allocs, node_bytes;
    {
        FlatMap m(1u << 18);
        g_allocs = g_bytes = 0;
        for (std::uint64_t i = 0; i < 100000; ++i) m.insert(splitmix64(i), static_cast<std::uint32_t>(i));
        flat_allocs = g_allocs;
        flat_bytes = g_bytes;
        std::printf("   flat open addressing : %zu allocations, %zu bytes; table %zu B = %.1f B/entry at load %.2f\n",
                    flat_allocs, flat_bytes, m.capacity() * sizeof(Slot),
                    static_cast<double>(m.capacity() * sizeof(Slot)) / 100000.0,
                    100000.0 / static_cast<double>(m.capacity()));
    }
    {
        std::unordered_map<std::uint64_t, std::uint32_t> m;
        m.reserve(100000);
        g_allocs = g_bytes = 0;
        for (std::uint64_t i = 0; i < 100000; ++i) m.emplace(splitmix64(i), static_cast<std::uint32_t>(i));
        node_allocs = g_allocs;
        node_bytes = g_bytes;
        std::printf("   std::unordered_map   : %zu allocations, %zu bytes (%.0f B per node, plus the bucket array)\n",
                    node_allocs, node_bytes, static_cast<double>(node_bytes) / static_cast<double>(node_allocs));
    }
    check(flat_allocs == 0, "flat table: zero allocations on the insert path");
    check(node_allocs == 100000, "node-based map: one allocation per insert");

    std::printf("3. Hit ratio, cache of 1,000 entries, 100,000-key Zipf(0.99) universe, 500,000 requests\n");
    Trace plain = make_trace(100000, 500000, 0.99, false, 42);
    Trace scanned = make_trace(100000, 500000, 0.99, true, 42);
    double lru_p = hit_ratio(Lru{1000, {}, {}}, plain), fifo_p = hit_ratio(Fifo{1000, {}, {}}, plain);
    double clk_p = hit_ratio(Clock{1000, 0, {}, {}, {}}, plain), s3_p = hit_ratio(S3Fifo(1000), plain);
    double lru_s = hit_ratio(Lru{1000, {}, {}}, scanned), fifo_s = hit_ratio(Fifo{1000, {}, {}}, scanned);
    double clk_s = hit_ratio(Clock{1000, 0, {}, {}, {}}, scanned), s3_s = hit_ratio(S3Fifo(1000), scanned);
    std::printf("   policy    plain trace   with scans (5,000 one-hit keys every 50,000 requests)\n");
    std::printf("   LRU       %6.2f%%       %6.2f%%\n", lru_p, lru_s);
    std::printf("   FIFO      %6.2f%%       %6.2f%%\n", fifo_p, fifo_s);
    std::printf("   CLOCK     %6.2f%%       %6.2f%%\n", clk_p, clk_s);
    std::printf("   S3-FIFO   %6.2f%%       %6.2f%%\n", s3_p, s3_s);
    check(clk_p > fifo_p, "CLOCK beats FIFO on the plain trace (second chance keeps hot keys)");
    check(s3_s > lru_s, "S3-FIFO beats LRU when scans arrive (one-hit wonders die in the small queue)");

    std::printf("4. Layout: 8 per-shard counters\n");
    std::printf("   unpadded: %zu bytes total (one cache line, all shards contend)\n", 8 * sizeof(Unpadded));
    std::printf("   padded  : %zu bytes total (one line per shard)\n", 8 * sizeof(Padded));
    check(8 * sizeof(Padded) == 8 * kLine, "padding costs 448 extra bytes per 8 shards");

    std::printf("\n%s (%d checks)\n", failed == 0 ? "verdict: OK" : "verdict: CHECK", checks);
    return 0;
}
```

### 12.2 Output

<!-- output:quickset.cpp -->
```text
1. Linear probing: successful-lookup probes, 65,536 slots
   load   measured avg   theory 1/2(1+1/(1-a))   max
   0.500      1.49            1.50                  25
   0.750      2.45            2.50                 105
   0.875      4.26            4.50                 289
  [ok] average probes stay within ~1.3x of theory at load 0.875
  [ok] backward-shift delete: 300 erased, 300 still found, no tombstones
2. Heap allocations while inserting 100,000 entries (tables pre-sized)
   flat open addressing : 0 allocations, 0 bytes; table 4194304 B = 41.9 B/entry at load 0.38
   std::unordered_map   : 100000 allocations, 3200000 bytes (32 B per node, plus the bucket array)
  [ok] flat table: zero allocations on the insert path
  [ok] node-based map: one allocation per insert
3. Hit ratio, cache of 1,000 entries, 100,000-key Zipf(0.99) universe, 500,000 requests
   policy    plain trace   with scans (5,000 one-hit keys every 50,000 requests)
   LRU        48.98%        44.30%
   FIFO       44.87%        40.66%
   CLOCK      50.13%        45.30%
   S3-FIFO    58.20%        52.91%
  [ok] CLOCK beats FIFO on the plain trace (second chance keeps hot keys)
  [ok] S3-FIFO beats LRU when scans arrive (one-hit wonders die in the small queue)
4. Layout: 8 per-shard counters
   unpadded: 64 bytes total (one cache line, all shards contend)
   padded  : 512 bytes total (one line per shard)
  [ok] padding costs 448 extra bytes per 8 shards

verdict: OK (7 checks)
```

**Reading the output.**
- **Section 1:** linear probing's average tracks theory within ~5%, and the worst case grows from 25 to 289 probes. That is the reason for the 0.75 cap.
- **Section 2:** 0 allocations against 100,000, with libc++'s 32-byte nodes.
- **Section 3:** the four policies ranked on the same seeded trace, and S3-FIFO's lead holds when scans arrive.
- **Section 4:** the padding arithmetic.

There are no timers in this program by design: everything it prints is reproducible on any machine, which makes it a valid regression test as well as an exhibit.

---

## 13. Failure modes

| # | Failure mode | Symptom | Fix |
|---|---|---|---|
| F1 | Average-only probe analysis | p99.9 spikes at high load | Measure the worst probe; cap the load (§4.2) |
| F2 | Stop-the-world resize | Latency cliff during growth | Incremental rehash on the writer thread |
| F3 | Allocation on the read path | Allocator contention in the tail | Arena; readers never allocate; counted in tests |
| F4 | Unqualified "lock-free" | Fails the memory-order probe | State the protocol and the reclamation scheme (§5.1) |
| F5 | Freeing too early | Use-after-free under racing readers | Epoch-based reclamation |
| F6 | False sharing | Throughput flat as cores are added | Pad hot counters; confirm with `perf c2c` (§5.2) |
| F7 | Update = access | Backfill flushes the working set (INC-Q2) | Separate admission; scan-resistant policy |
| F8 | Count-based caps | OOM when value sizes shift | Evict by bytes; per-group accounting |
| F9 | Microbenchmark p99 | Fails "measured how?" | Fixed-rate production measurement (§7) |
| F10 | NIH | Fails build-vs-buy | Prototype the library; state what it failed (§8) |

---

## 14. Bar-raiser chains

<details><summary><b>Q1 · "Why not just use Redis with pipelining and a few more replicas?"</b></summary>

**Initial Prompt.** "Redis can do millions of ops a second. Pipeline harder, add replicas, done. Why an in-process cache?"

**L5 Answer.** "Redis was too slow for our latency requirements, and an in-process cache is faster."

**Why L5 Stalls.** Redis's per-operation speed wasn't the problem, and "too slow" doesn't name the mechanism. The interviewer expects the fan-out math.

**L7 Answer.** "Redis throughput was fine; the problem was fan-out. Each request needed about 3,000 keys spread across 32 shards, so every request touched every shard, and with a 1% chance of any one shard being in its tail, about 27.5% of requests waited on at least one tail. Pipelining reduces round trips but not the number of shards touched. Replicas let you hedge, sending a duplicate request after a delay, which cuts the tail but roughly doubles load during exactly the periods when shards are slow. Fewer shards concentrates hot keys. Moving the hot working set in-process removes the network from 96.8% of lookups, and Redis now serves only misses, on 8 shards instead of 32."

</details>

<details><summary><b>Q2 · "250 nanoseconds p99. Measured how, under what load?"</b></summary>

**Initial Prompt.** "Where does 250 ns come from? Show me the methodology."

**L5 Answer.** "From our benchmark suite. We ran Google Benchmark on the lookup path and that was the p99."

**Why L5 Stalls.** A closed-loop microbenchmark with a hot cache measures the best case and under-samples stalls. Quoting it as p99 is the classic overclaim.

**L7 Answer.** "Not from the microbenchmark: that says 41 nanoseconds, hot cache, no contention, and I don't quote it. The 250 is from production: 1 call in 1,024 is timed with the timestamp counter into a per-thread HdrHistogram, the histograms are merged per host, then the percentile is taken. The rate is the real ranking load, about 6 million lookups a second per host. The number I'd rather you remember is per request: feature-fetch p99 of 0.9 milliseconds for about 3,000 lookups, measured in the ranking service under a fixed-arrival-rate load test, so slow periods are fully sampled. Per-key tails compound across 3,000 lookups, which is why the per-request number matters more."

</details>

<details><summary><b>Q3 · "What happens to your table at load factor 0.95?"</b></summary>

**Initial Prompt.** "Suppose growth pushes a shard to 0.95 load before resize. What does a lookup cost?"

**L5 Answer.** "It would be a bit slower because of more collisions, but it should still be fine on average."

**Why L5 Stalls.** "Fine on average" ignores the tail, which is where linear probing degrades fastest, and the tail is what the SLO measures.

**L7 Answer.** "The average expected probe count is about ½(1 + 1/(1 − 0.95)), about 10.5, but the tail is the problem. In my test at 0.875 the worst key already needed 289 probes, because of primary clustering, and at 0.95 clusters merge into runs of thousands of slots. A miss probes to the end of its cluster, so a miss-heavy burst is the worst case. That's why the design never reaches 0.95: the writer starts an incremental resize at 0.75, migrating a bounded number of buckets per tick, and readers check both tables during migration. If I needed higher loads, I'd switch to Robin Hood hashing, which bounds the variance of probe lengths, rather than tuning linear probing."

</details>

<details><summary><b>Q4 · "How do readers and the update thread avoid racing?"</b></summary>

**Initial Prompt.** "One writer, many readers, no locks. Walk me through a value update while a reader is mid-read."

**L5 Answer.** "We use atomic operations, so the read and write are atomic and there's no race."

**Why L5 Stalls.** Atomics on the slot word don't make a multi-hundred-byte value atomic, and the answer says nothing about when the old value's memory can be reused, which is the hard part.

**L7 Answer.** "The value is never updated in place. The writer builds the new value elsewhere in the arena, then does 1 release store of the slot's 64-bit offset-plus-version word. A reader does an acquire load of that word and reads the value it points to. The acquire/release pair guarantees it sees all of the value's bytes as written before publication. A reader that loaded the old word just before the publish keeps reading the old value, which is still valid, because the writer doesn't free it: it goes on a retire list with the current epoch, and is reclaimed only after every reader thread has passed a quiescent point, bumped once per request. Reclamation runs on the writer thread, so readers never pay for it."

</details>

<details><summary><b>Q5 · "A backfill pushes 400 million keys through your update stream."</b></summary>

**Initial Prompt.** "The feature team backfills a new feature for 400M keys. What happens to your cache?"

**L5 Answer.** "The cache would evict old entries as new ones come in, which is normal behavior."

**Why L5 Stalls.** "Normal behavior" is the INC-Q2 outage: 400M cold keys evicting a hot working set. The candidate hasn't separated admission from update.

**L7 Answer.** "Today: almost nothing, because of what happened the first time. In v1, every update admitted its key and eviction was LRU, so the backfill flushed the working set. The hit ratio fell from 96% to 61% in 4 minutes and took 25 minutes to recover. Now an update for a non-resident key doesn't admit it. The key enters the cache only when a reader asks for it. Backfills are flagged, so they update only resident keys. And eviction is S3-FIFO, where new keys enter a small FIFO and one-hit wonders die there without touching the main queue. The CI test replays a backfill-shaped trace and fails if the hit ratio drops more than 2 points."

</details>

<details><summary><b>Q6 · "How do you know you won't OOM the host?"</b></summary>

**Initial Prompt.** "Your cap is 12 GB. Values vary from 200 B to 6 KB. Prove the cap holds."

**L5 Answer.** "We limited the number of entries in the cache, so the memory is bounded."

**Why L5 Stalls.** A count limit doesn't bound bytes when value sizes vary 30×. That's exactly the failure that led to per-group accounting.

**L7 Answer.** "The cap is in bytes, not entries. Every arena allocation is charged to its feature group's byte counter at its size class, not its requested size, so fragmentation inside a class is counted too, and eviction runs until total charged bytes are under 12 gigabytes minus a 5% headroom for in-flight updates. The arena takes memory from the OS in 2-megabyte slabs, and slab count times 2 megabytes is the true resident size, so I alert if it exceeds the charged bytes by more than 10%, which would mean slab fragmentation. The day one feature group's vectors doubled from 1.1 to 2.2 kilobytes, the cap held; what happened instead was that group crowded out others, which is why per-group budgets came next."

</details>

<details><summary><b>Q7 · "You padded the counters. Did false sharing actually matter?"</b></summary>

**Initial Prompt.** "Padding is cargo cult unless you measured it. Did you?"

**L5 Answer.** "False sharing is a well-known performance issue, so we padded to be safe."

**Why L5 Stalls.** "To be safe" means not measured. The interviewer explicitly asked for evidence.

**L7 Answer.** "I measured it, because I also thought it might be cargo cult. Before padding, perf c2c on a loaded host showed the per-shard counter line as the top contended cache line, with modified-line hits from every core. In a fixed-rate load test, padding the 8 counters raised the lookups a single host sustained at the same p99 by about 14% on the 2-socket host type. It cost 448 bytes per 8 shards. The listing only checks the layout at compile time, because the effect depends on core count and topology, and I'd re-measure on a new host shape rather than assume."

</details>

<details><summary><b>Q8 · "What's your consistency model for features?"</b></summary>

**Initial Prompt.** "A feature changes upstream. When does the ranking see it, and can it see an older value after a newer one?"

**L5 Answer.** "Updates come through the stream pretty quickly, so the cache is basically up to date."

**Why L5 Stalls.** "Basically up to date" defines nothing, and it ignores the miss path, which fills from Redis concurrently with stream updates and can regress a value.

**L7 Answer.** "Bounded staleness with per-key monotonic versions. The change stream carries a version per key, and the writer applies an update only if its version is newer than the resident one, so a delayed message can't overwrite a newer value. The asynchronous miss-fill from Redis carries Redis's version too, and is subject to the same check, which closes the race where a fill fetched just before an update lands just after it. The bound: stream lag p99 is 11 seconds and a TTL of 30 minutes caps any value that misses updates, so K4's 30 seconds holds at p99 except during stream outages, when the dashboard shows staleness per feature group."

</details>

<details><summary><b>Q9 · "Why C++? Java with off-heap memory and ZGC would be safer."</b></summary>

**Initial Prompt.** "Modern Java has sub-millisecond GC pauses and off-heap buffers. Why take on C++'s risks?"

**L5 Answer.** "C++ is faster than Java and gives us more control over memory."

**Why L5 Stalls.** "Faster" is contestable for this workload, and the real reason is architectural, not a language comparison.

**L7 Answer.** "Because the cache has to be in-process with the caller, and the caller is a C++ ranking service. That's TC2 in my ledger, and I didn't choose it. A Java cache would have meant either a JNI crossing per batch, with marshaling for 3,000 keys, or a separate process, which I measured at 1.8 milliseconds p99 per request: more than half the budget. Inside a JVM I agree ZGC would make pauses a non-issue, and off-heap arenas would give similar layout control. If the ranking service were Java, I'd have built this in Java. The C++ risks are real, and I paid for them with sanitizer builds in CI, a fuzzer on the arena, and the epoch scheme reviewed by 2 engineers who'd built RCU-style code before."

</details>

<details><summary><b>Q10 · "Your hosts have two sockets. Where's the memory?"</b></summary>

**Initial Prompt.** "A ranking thread on socket 1 reads a value allocated on socket 0. What does that cost, and what did you do?"

**L5 Answer.** "We didn't really have NUMA issues, since the cache was fast enough already."

**Why L5 Stalls.** "Didn't have issues" usually means "didn't measure". The interviewer is probing whether the candidate understands the hardware the code runs on.

**L7 Answer.** "In v1 the arena interleaved pages across both sockets, which spreads bandwidth but makes about half of value reads remote. On this host type I measured remote-socket reads at about 1.6 times local latency, and about 11% of lookups crossed sockets after thread pinning. That was acceptable for v1, and it's in my ledger as TC4. The v2 design replicates the shards per socket. Each socket's ranking threads read their own replica, and the update thread for each shard writes both. That doubles memory for the replicated part, so I'd only replicate the hottest 30% of keys, which carry about 80% of lookups. The single-socket host shape planned for next year would remove the problem entirely, which is why I haven't built it yet."

</details>

---

## 15. Checklist

- [ ] Slot layout, load-factor cap, and probe average *and* worst case for your structure (§4).
- [ ] Allocation counts on your hot path, asserted in a test (§4.3, §12).
- [ ] Your concurrency protocol: who writes, how values are published, what readers can observe, how memory is reclaimed (§5.1).
- [ ] Evidence that padding or layout changes mattered, from a tool, on the target hardware (§5.2).
- [ ] Eviction and admission policy, and how it behaves under scans or backfills (§6).
- [ ] Latency methodology: fixed-rate load, histograms merged, per-key vs per-request (§7).
- [ ] Build-vs-buy: the prototype, the requirement the library failed, the maintenance estimate (§8).
- [ ] Memory: byte-exact cap, fragmentation accounting, what happens when value sizes shift (Q6).
- [ ] Consistency model: versions, the miss-fill race, staleness bound (Q8).
- [ ] NUMA and topology: measured remote cost, and your decision (Q10).

---

## 16. References

- Juncheng Yang, Yazhuo Zhang, Ziyue Qiu, Yao Yue and Rashmi Vinayak, "FIFO queues are all you need for cache eviction", *SOSP '23*, pp. 130–149, 2023. DOI 10.1145/3600006.3613147 (verified via Crossref).
- Jeffrey Dean and Luiz André Barroso, "The Tail at Scale", *Communications of the ACM* 56(2), 2013. DOI 10.1145/2408776.2408794.
- Donald E. Knuth, *The Art of Computer Programming, Volume 3: Sorting and Searching*, 2nd ed., Addison-Wesley, 1998, ISBN 0-201-89685-0 (analysis of linear probing).
- cppreference, `std::hardware_destructive_interference_size`. <https://en.cppreference.com/w/cpp/thread/hardware_destructive_interference_size>
- Linux man page, `perf-c2c(1)` (cache-line contention analysis). <https://man7.org/linux/man-pages/man1/perf-c2c.1.html>
- HdrHistogram (coordinated omission, high-dynamic-range latency recording). <http://hdrhistogram.org/>
- Brendan Gregg, "The USE Method". <https://www.brendangregg.com/usemethod.html>
