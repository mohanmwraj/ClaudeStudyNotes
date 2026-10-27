# Distributed Systems & System Design: L7 Reference

A Principal-level (L6/L7) knowledge base on distributed systems and large-scale system design, built from first
principles. It is meant to work both as a permanent engineering reference and as a FAANG L7 interview playbook.

It covers:
- the physics and economics under every design: latency, bandwidth, write amplification, round trips, and dollars;
- consistency, consensus, clocks and transactions;
- storage engines, replication and sharding;
- edge, caching and traffic routing;
- resiliency: cells, shuffle sharding, metastable failures, static stability;
- 32 complete production design blueprints;
- decision matrices, plus an index of papers, engineering blogs and repositories.

Each topic carries an explicit **L5 vs L6 vs L7** evaluation lens.

**Status: complete.** All 10 folders are written: 30 files, ~146k words, and 32 runnable listings (30 Python
stdlib, 2 Java 21), all re-verified by a final gate on 2026-10-27 (see Verification method).

## Layout and build status

| # | Folder | Status |
|---|--------|--------|
| 01 | [`01-First-Principles-Physics-and-L5-L6-L7-Rubric/`](01-First-Principles-Physics-and-L5-L6-L7-Rubric/) | ✅ Written 2026-10-27 |
| 02 | [`02-Storage-Engines-Replication-and-Sharding-Internals/`](02-Storage-Engines-Replication-and-Sharding-Internals/) | ✅ Written 2026-10-27 |
| 03 | [`03-Consensus-Coordination-and-Distributed-Transactions/`](03-Consensus-Coordination-and-Distributed-Transactions/) | ✅ Written 2026-10-27 |
| 04 | [`04-Networking-Edge-Caching-and-Global-Traffic-Routing/`](04-Networking-Edge-Caching-and-Global-Traffic-Routing/) | ✅ Written 2026-10-27 |
| 05 | [`05-Resiliency-Multi-Region-and-Metastable-Failures/`](05-Resiliency-Multi-Region-and-Metastable-Failures/) | ✅ Written 2026-10-27 |
| 06 | [`06-32-Master-Problems-Part1-Data-Storage-and-Infra/`](06-32-Master-Problems-Part1-Data-Storage-and-Infra/) | ✅ Written 2026-10-27 |
| 07 | [`07-32-Master-Problems-Part2-Social-Search-and-Media/`](07-32-Master-Problems-Part2-Social-Search-and-Media/) | ✅ Written 2026-10-27 |
| 08 | [`08-32-Master-Problems-Part3-Commerce-Geo-and-FinTech/`](08-32-Master-Problems-Part3-Commerce-Geo-and-FinTech/) | ✅ Written 2026-10-27 |
| 09 | [`09-Deep-Dive-Architectural-Comparisons-and-Tradeoffs/`](09-Deep-Dive-Architectural-Comparisons-and-Tradeoffs/) | ✅ Written 2026-10-27 |
| 10 | [`10-Engineering-Blogs-Papers-and-GitHub-Reference-Index/`](10-Engineering-Blogs-Papers-and-GitHub-Reference-Index/) | ✅ Written 2026-10-27 |

### Folder 01 contents (~39k words, 9 runnable listings)

1. [L5 vs L6 vs L7: how system design interviews are graded](01-First-Principles-Physics-and-L5-L6-L7-Rubric/01-l5-vs-l6-vs-l7-interview-evaluation-rubric-and-signals.md)
   - The cross-company level ladder, normalized.
   - How Google HC, Meta focus areas and Amazon bar raisers turn a conversation into written evidence.
   - The scope cone and a 16-dimension master matrix.
   - The 45-minute anatomy as a state machine.
   - The quantification toolkit (`estimation_toolkit.py`), which shows:
     - shared fate capping redundancy at ~4 nines;
     - fan-out-100 medians exceeding leaf p99s;
     - hedging cutting p99 8.5×;
     - the Erlang-C "cell tax";
     - Little's-law pool exhaustion;
     - Zipf cache sizing.
   - A URL shortener answered at L5, L6 and L7: an edge data plane, a reputation-risk control plane, domain cells,
     and the negative-cache RYW trap.
   - The signals catalog, 8 generic three-step probing chains, opening/closing scripts, and a scoring sheet.
2. [Hardware & network physics, latency numbers, and FinOps math](01-First-Principles-Physics-and-L5-L6-L7-Rubric/02-hardware-network-physics-latency-numbers-and-finops-math.md)
   - **Measured on this laptop:**
     - a cache/DRAM ladder: L1 1.2–1.4 ns, L2 3.2–4.6 ns, L3 13–15 ns, DRAM 110–120 ns;
     - MLP of 11–12 misses in flight;
     - false sharing at ~3× and a shared counter at ~4–6× the padded case;
     - fsync at p50 ~1 ms with p99 1.5–2 ms (one run 102 ms) on consumer QLC;
     - group commit at 46–58× serial throughput;
     - 35–37 µs loopback RTT;
     - single-core CRC32C 15–20 GB/s, AES-GCM 5–6 GB/s, zlib-1 0.14–0.19 GB/s.
     - Ranges cover five runs. A warm laptop is ~30% slower.
   - **Simulated:** SSD FTL write amplification, validated against the analytic fixed point. "Data that dies together"
     placement halves WAF (5.25 → 2.63), and the stacked WAF gives 107-day drive lifetimes.
   - **Derived:**
     - light in fiber and route inflation;
     - slow-start round trips;
     - BDP and buffer caps (699 Mbps);
     - Mathis, CUBIC and BBR;
     - packet budgets and the TCO of kernel bypass;
     - consensus commit floors (12 ms US vs 70 ms transatlantic).
   - **FinOps:**
     - unit prices from instance-family deltas;
     - a cloud five-minute rule (gp3 7.6 min; S3 26 h for 4 KiB);
     - the Kafka cross-AZ bill ($175k → $5.6k/month diskless);
     - the DynamoDB vs Cassandra crossover with people cost;
     - static-stability multipliers.
3. [CAP, PACELC, linearizability, serializability, and causal consistency](01-First-Principles-Physics-and-L5-L6-L7-Rubric/03-cap-pacelc-linearizability-serializability-and-causal-consistency.md)
   - Formal definitions and the hierarchy with availability classes. Causal is the strongest sticky-available model.
   - A linearizability/SC checker showing SC is not composable and why timeouts are "unknown".
   - The anomaly matrix and what each database's isolation names actually mean.
   - An MVCC simulator running lost update, read skew, write skew, and the SI read-only anomaly under RC, SI and SSI.
   - CAP proved and its myths, PACELC with the |r| + |w| ≥ d bound.
   - A quorum simulator: new-old inversion and the ABD fix, sloppy quorums, LWW losing acknowledged writes, and PBS
     staleness set by the replication tail.
   - Linearizability in etcd, ZooKeeper, Spanner, DynamoDB, Redis and others; session tokens; a per-operation model
     guide.

### Folder 02 contents (~18.5k words, 4 runnable listings)

1. [B+tree vs LSM-tree, SSTables, compaction, Bloom filters](02-Storage-Engines-Replication-and-Sharding-Internals/01-b-plus-tree-vs-lsm-tree-sstable-compaction-and-bloom-filters.md)
   - The RUM conjecture and B+tree fan-out.
   - Write amplification including doublewrite and full-page writes.
   - Fill factor (69% random, 100% with rightmost-append splits).
   - UUIDv4 dirtying 809 leaves vs 17 for time-ordered keys.
   - Toy leveled vs size-tiered LSMs: WAF 13.6 vs 5.0, space 1.26 vs 2.15, 1.04 vs 1.13 I/Os per point read with
     filters.
   - Write stalls as compaction debt (ingest × WAF = disk bandwidth).
   - Tombstone resurrection.
   - Bloom math verified, blocked vs standard, Ribbon/cuckoo/xor, and Monkey.
2. [Replication: single-leader, multi-leader, leaderless](02-Storage-Engines-Replication-and-Sharding-Internals/02-replication-single-leader-multi-leader-and-leaderless-sloppy-quorums.md)
   - Async/semi-sync/quorum/consensus modes, priced in RPO and write availability (semi-sync lowers it; majority
     raises it).
   - Failover: fencing, max-LSN promotion, and the lag *tail* setting RPO.
   - The multi-leader LWW loss rate 1 − e^{−λd/2}, verified by simulation; a hot key loses 99.97% of increments while
     a CRDT loses none.
   - The Merkle anti-entropy cost model, chain replication and CRAQ, and CDC slot hazards.
3. [Consistent hashing, bounded loads, vnodes, range splitting](02-Storage-Engines-Replication-and-Sharding-Internals/03-consistent-hashing-bounded-loads-virtual-nodes-and-range-splitting.md)
   - mod-N moves 91% of keys on resize; ring, rendezvous and jump hash move ~9%.
   - Vnode imbalance: 4.38 → 1.17 max/mean.
   - Bounded loads cap load at 1.25× under Zipf 1.1, at the cost of 30% affinity.
   - Monotonic keys send 100% of writes to one range; hash prefixes give 6.6%.
   - Hot-key toolbox, rebalancing math, and epoch-fenced routing.
4. [NewSQL internals: Spanner, CockroachDB, Aurora](02-Storage-Engines-Replication-and-Sharding-Internals/04-newsql-internals-spanner-truetime-cockroachdb-and-aurora-quorums.md)
   - TrueTime commit wait gives 0 real-time violations, against up to 50% for naive timestamps, at a cost of 2ε.
   - CockroachDB uncertainty restarts = 1 − e^{−λ·max_offset}, verified; parallel commits.
   - The TiDB TSO alternative.
   - Aurora's 6-copy, 4/6 write, 3/6 read quorums under AZ+1, and 10 GB segments cutting double-fault risk ~1,000×.
   - A comparison matrix.

### Folder 03 contents (~13.8k words, 3 runnable listings)

1. [Paxos, Multi-Paxos, Raft, Zab, membership changes](03-Consensus-Coordination-and-Distributed-Transactions/01-paxos-multi-paxos-raft-zab-and-dynamic-membership-changes.md)
   - FLP and quorum intersection; basic and Multi-Paxos.
   - Raft's safety rules in a compact simulator:
     - **Figure 8 reproduced.** The naive commit rule lets a committed entry be overwritten.
     - 60 random chaos seeds did *not* find it, which is why model checking matters.
     - Narrow election timeouts give a p99 failover of 4.4 s vs 0.41 s.
   - Zab, joint consensus vs single-server changes (and the 2015 fix), Flexible Paxos.
   - Throughput/latency math, Multi-Raft, and production failure modes.
2. [Time and clocks: NTP, Lamport, vector, HLC, TrueTime](03-Consensus-Coordination-and-Distributed-Transactions/02-time-clocks-ntp-skew-lamport-vector-clocks-and-hlc.md)
   - Drift and NTP asymmetry error.
   - Wall clocks stamp 3.2% of replies before their requests at 10 ms skew, and 33.7% at 50 ms.
   - Lamport and HLC never invert; vector clocks classify concurrency exactly; HLC stays within the skew bound.
   - The design space for real-time order.
3. [Locking, fencing tokens, 2PC, Percolator, sagas](03-Consensus-Coordination-and-Distributed-Transactions/03-distributed-locking-fencing-tokens-2pc-percolator-and-saga.md)
   - Leases alone apply 327–384 stale writes per 20k grants; fencing applies 0. The Redlock debate.
   - 2PC lock holds reach 1,586 s with a single coordinator vs 3 s replicated.
   - Percolator survives 365 client crashes with 0 bad snapshots (roll-forward/back).
   - Saga idempotency keys remove 858 double charges; outbox vs XA.

### Folder 04 contents (~10.8k words, 3 runnable listings)

1. [The global front door: BGP anycast, GeoDNS, Maglev, Envoy](04-Networking-Edge-Caching-and-Global-Traffic-Routing/01-bgp-anycast-geodns-l4-maglev-consistent-hashing-and-l7-envoy.md)
   - Anycast traps (the 2019 route leak; Facebook 2021) and DNS TTL limits.
   - The Maglev table: max/min share 1.000–1.002, ~0.2–0.6% needless disruption.
   - Random and round-robin are **unstable** on a heterogeneous fleet; stale least-loaded herds (p99 513 ms) while
     P2C stays robust (254 ms).
   - Envoy resilience features; HTTP/2 connection imbalance.
2. [Distributed caching: TAO, leases, herds, hot keys](04-Networking-Edge-Caching-and-Global-Traffic-Routing/02-distributed-caching-tao-lease-tokens-thundering-herds-and-hotkey-salting.md)
   - The Memcache-at-Facebook playbook.
   - The stale-set race: 28% stale time vs 0% with lease tokens.
   - Stampede: 369 DB calls per expiry vs ~1 with leases, SWR or XFetch.
   - TAO's leader/follower tiers.
   - Hot shard 13.7× → 1.7× with salting; an L1 absorbs 73%.
3. [CDN internals: tiering, hash rings, QUIC/HTTP3](04-Networking-Edge-Caching-and-Global-Traffic-Routing/03-cdn-internals-tiered-caching-consistent-hash-rings-and-quic-http3.md)
   - In-PoP owner hashing gives a 2.5× edge hit ratio; the shield cuts origin load from 64% to 36%.
   - Second-hit admission: +23%.
   - Freshness/purge strategy and Open Connect.
   - HOL blocking at 1% loss: 30% of streams stalled on TCP vs 4% on QUIC.

### Folder 05 contents (~10.5k words, 3 runnable listings)

1. [Cellular architecture, shuffle sharding, blast radius](05-Resiliency-Multi-Region-and-Metastable-Failures/01-cellular-architecture-shuffle-sharding-and-blast-radius-isolation.md)
   - Failure domains and cell design rules: a boring router, max size, no cross-cell paths, migration.
   - Exact hypergeometric shuffle-sharding math, checked by Monte Carlo. With 5 of 100 workers, 0.06% of tenants lose
     a majority (vs 5% with fixed cells), which **meets the brief's < 0.5% target**. C(2048,4) = 7.3×10¹¹.
   - Deployment waves: 1,000 → 10 cell-minutes; small early waves catch partial-manifestation defects.
2. [Metastable failures, retry storms, load shedding, adaptive LIFO](05-Resiliency-Multi-Region-and-Metastable-Failures/02-metastable-failures-retry-storms-load-shedding-and-adaptive-lifo.md)
   - A 10 s capacity drop leaves naive retries **and backoff alone** at goodput 0 indefinitely.
   - A 10% retry budget recovers in 11 s; deadline-aware dropping and adaptive LIFO + CoDel recover instantly.
   - Retry multiplication across layers (4⁵ = 1,024×).
   - Adaptive concurrency limits, client-side throttling, criticality shedding, and a catalog of sustaining effects.
3. [Control plane vs data plane, static stability, graceful degradation](05-Resiliency-Multi-Region-and-Metastable-Failures/03-control-plane-vs-data-plane-static-stability-and-graceful-degradation.md)
   - Through a 4 h control-plane outage, fetch-at-boot falls to 69% capacity (59% after 1 h during a deploy), while
     last-known-good stays at 100%.
   - Reconnect storm of 10,000 req/s vs 192 jittered vs constant work's 359 peak (equal to steady state).
   - A bad config: 5,000 → 50 host-minutes with waves.
   - Config outages (Cloudflare 2019, Facebook 2021, CrowdStrike 2024, Google Cloud 2025), Kubernetes through the
     plane lens, and degradation ladders.

### Folder 06 contents (~16k words, 3 runnable listings): problems 1–11

Each problem follows the same blueprint:
- (a) scale/SLA;
- (b) data/control planes and the write/read/recovery paths;
- (c) the core L7 bottleneck;
- (d) schema and partition key;
- (e) failure defense;
- plus an L5/L6/L7 table and a probing chain.

1. [Problems 1–4: KV store, S3 object storage, lock service, CDN](06-32-Master-Problems-Part1-Data-Storage-and-Infra/01-problems-01-to-04-kv-store-blob-storage-s3-distributed-lock-and-cdn.md)
   - KV store: multi-tenant admission and adaptive capacity.
   - Object storage: a working RS(10,4) GF(256) codec, and MTTDL showing 13.4 nines and that repair speed is worth
     3–5 orders of magnitude.
   - Lock service: session-expiry storms and quotas.
   - CDN: hit-ratio economics and config safety.
2. [Problems 5–8: rate limiter, ID generator, delayed jobs, message broker](06-32-Master-Problems-Part1-Data-Storage-and-Infra/02-problems-05-to-08-rate-limiter-id-generator-job-scheduler-and-message-broker.md)
   - Rate limiter: fixed window admits 198 vs limit 100; a static split rejects 18% under the limit; async sync
     overshoots +5–7%.
   - IDs: naive Snowflake gives 5,000 duplicates on a 5 ms clock step back, the safe one 0.
   - Delayed jobs: the timing wheel matches the heap exactly; jobs use sharded time buckets.
   - Message broker: the cross-AZ bill as Kafka's dominant cost.
3. [Problems 9–11: TSDB, tracing, Zanzibar](06-32-Master-Problems-Part1-Data-Storage-and-Infra/03-problems-09-to-11-metrics-tsdb-distributed-tracing-and-global-auth-zanzibar.md)
   - TSDB: bit-exact Gorilla at 0.29–8.07 B/point, with cardinality as the DoS axis.
   - Tracing: tail sampling keeps 100% of errors at 2.3% storage.
   - Zanzibar: zookies cut new-enemy leaks from 2,490 to 0; Leopard flattening.

### Folder 07 contents (~12.6k words, 3 runnable listings): problems 12–21

1. [Problems 12–15: news feed, chat, notifications, live comments](07-32-Master-Problems-Part2-Social-Search-and-Media/01-problems-12-to-15-news-feed-whatsapp-chat-notification-engine-and-live-comments.md)
   - Feed: on a Pareto graph, the hybrid's real win is a bounded per-post fan-out (2.17M → < 10k), not average writes
     (−36%).
   - Chat: client IDs + per-conversation sequences give 2,983 → 0 duplicates.
   - Notifications: OTP p99 39 s behind a marketing burst vs < 1 ms with priority lanes.
   - Live comments: 10¹⁰ msgs/s naive → sampled, batched hierarchical fan-out.
2. [Problems 16–19: VOD/ABR, live streaming, typeahead, search](07-32-Master-Problems-Part2-Social-Search-and-Media/02-problems-16-to-19-youtube-vod-live-streaming-typeahead-and-distributed-search.md)
   - VOD/ABR: BBA streams at +40% bitrate but rebuffers on deep drops until download abandonment is added (0%);
     encode spend by popularity.
   - Live: latency budgets per protocol.
   - Typeahead: precomputed top-k reads 5 entries vs scanning 1,050.
   - Search: galloping intersection, doc vs term partitioning, fan-out tails.
3. [Problems 20–21: web crawler, collaborative editor](07-32-Master-Problems-Part2-Social-Search-and-Media/03-problems-20-to-21-web-crawler-and-collaborative-editor-crdt-ot.md)
   - Crawler: Mercator back queues give 199 vs 4.8 pages/s; hash(host) sharding; Bloom vs exact URL-seen.
   - Editor: RGA CRDT converges 200/200 vs naive 0/200; OT TP1 holds; GC, tree moves, per-doc session servers.

### Folder 08 contents (~14k words, 3 runnable listings): problems 22–32

1. [Problems 22–25: geo-dispatch, flash sale, booking, food-delivery ETA](08-32-Master-Problems-Part3-Commerce-Geo-and-FinTech/01-problems-22-to-25-uber-geo-dispatch-ticketmaster-flash-sale-and-hotel-booking.md)
   - Geo: hex rings examine 24% fewer candidates than squares at 100% recall.
   - Dispatch: batching lowers the mean pickup but can raise the p95 (objective design).
   - Flash sale: naive writes oversell 210 seats vs 0 with CAS/escrow; the waiting room as admission control.
   - Booking: SI check-then-insert gives 48 double bookings vs 0 with room-night rows.
   - Food delivery: switchback experiments.
2. [Problems 26–28: payments, ledger, exchange](08-32-Master-Problems-Part3-Commerce-Geo-and-FinTech/02-problems-26-to-28-payment-gateway-double-entry-ledger-and-stock-exchange.md)
   - Payments: idempotency keys + recovery give 0 double charges vs 9,848.
   - Ledger: duplicates are *balanced* (0/197 caught by Σ = 0) and caught only by reconciliation (197/197).
   - Exchange: journal replay is bit-identical, and 5% reordering changes 8,294 trades (why a sequencer).
3. [Problems 29–32: ad clicks, leaderboard, feature store, LLM/agentic gateway](08-32-Master-Problems-Part3-Commerce-Geo-and-FinTech/03-problems-29-to-32-ad-click-aggregator-leaderboard-feature-store-and-ai-gateway.md)
   - Ad clicks: error 36k → 2.9k → 0 with event time + dedupe + late updates.
   - Leaderboard: a skip list with spans gives exact ranks; tiered exactness.
   - Feature store: leaked "latest" features score F1 0.913 offline → 0.061 in production.
   - LLM gateway: token-based fairness; prefix-aware bounded-load routing lifts cache hits 52% → 89%.

### Folder 09 contents (~4.8k words of dense matrices)

1. [Database selection matrix](09-Deep-Dive-Architectural-Comparisons-and-Tradeoffs/01-database-selection-matrix-postgres-cassandra-dynamodb-spanner-clickhouse.md)
   - 14 engines by storage engine, replication, partitioning, isolation, sweet spot and anti-patterns.
   - A decision flowchart, cost crossovers (reusing Folder 01's TCO math), and bad-day failure behavior per engine.
   - The system of record + derived stores used by all 32 problems.
2. [Async messaging and stream processing decision matrix](09-Deep-Dive-Architectural-Comparisons-and-Tradeoffs/02-async-messaging-and-stream-processing-decision-matrix.md)
   - Queue vs log vs pub/sub vs stream processor vs workflow engine.
   - Kafka/Redpanda/Pulsar/Kinesis/Pub/Sub/SQS/RabbitMQ/diskless compared.
   - Delivery semantics precisely (exactly-once *effects*); Flink/Kafka Streams/Spark/Beam/streaming DBs.
   - Patterns and anti-patterns.

### Folder 10 contents (~6.1k words, 1 listing)

1. [Engineering blogs and case studies](10-Engineering-Blogs-Papers-and-GitHub-Reference-Index/01-company-engineering-blogs-case-studies-and-what-they-solved.md)
   - AWS Builders' Library, Netflix, Uber, Meta, Cloudflare, Discord, Stripe, LinkedIn, Figma, Slack, GitHub,
     Google SRE and more.
   - Each post is mapped to the problem it illustrates and the L7 concept it proves.
2. [Seminal papers cheat sheet](10-Engineering-Blogs-Papers-and-GitHub-Reference-Index/02-seminal-distributed-systems-papers-cheat-sheet.md)
   - ~65 papers, each with "the one idea", an interview sentence, and its KB location.
   - A 12-week reading path tied to the listings.
3. [Curated GitHub architectures](10-Engineering-Blogs-Papers-and-GitHub-Reference-Index/03-curated-open-source-github-architectures-to-study.md)
   - ~65 repositories, each with what to read for.
   - `verify_reading_list.py` checked all 161 Folder 10 URLs: 0 broken; 12 publisher pages refuse automated
     clients and are flagged for a manual click.

## Conventions

- **The level scale is normalized.** L5 = Senior, L6 = Staff, L7 = Principal / Senior Staff. Company ladders differ:
  Amazon's L6 is Senior and its L7 is Principal; Google's L7 is Senior Staff. See file 01 §1.
- **Per-file spine** (the brief's mandate):
  1. first-principles math and capacity estimation;
  2. ASCII/Mermaid diagrams of the data plane, control plane, write, read and failure-recovery paths, where
     applicable;
  3. deep-dive internals;
  4. an L5/L6/L7 comparison table;
  5. three-step bar-raiser probing chains;
  6. an invariants checklist and references.
- **⚠ verify** marks anything release-, price- or company-dependent: prices, version semantics, published figures
  quoted from memory.
- **Output labels:**
  - "Output (verified)": deterministic; reproduced byte-for-byte by the gate.
  - "One measured run": hardware timings; invariants asserted, values vary.
- **Diagrams** use Mermaid fenced blocks, which render natively on GitHub. In VS Code, install a Mermaid preview
  extension. ASCII diagrams are used where layout matters.
- **Cross-references** are relative links with in-file anchors, all checked by the gate.

## Running the listings

- **Python:** 3.10+ with the standard library only. Run each `*.py` from the folder you extract it to.
  `quorum_sim.py` imports `linearizability_checker.py` from the same folder.
- **Java:** 21+.

  ```bash
  javac --release 21 -d out LatencyLadder.java IoCostProbe.java
  java -Xmx512m -cp out dev.l7.dsd.physics.LatencyLadder
  java -Xmx512m -cp out dev.l7.dsd.physics.IoCostProbe /path/to/scratch-dir   # the fsync file goes here
  ```

- **Measured runs** used an Intel i5-11260H with DDR4-3200 and a Micron 2400 QLC NVMe, on Windows 11 with JDK 25.0.4.
  Expect different absolute values and the same ratios on your machine. Server parts with PLP SSDs will show fsync
  10–50× faster.

## Verification method

Every listing in the KB is spliced from a source file that was compiled and run. For Java that means
`javac --release 21 -Xlint:all -Werror`.

The gate then:
1. extracts every listing back out of the markdown;
2. checks it is byte-identical to its source;
3. reruns all of them sequentially;
4. diffs deterministic outputs byte-for-byte;
5. checks every relative link and in-file anchor.

Final gate over the whole KB (2026-10-27):
- 32 listings extracted, all byte-identical to their sources.
- All 32 pass their self-tests (invariants asserted).
- The 29 deterministic outputs are byte-identical on rerun, and hash-seed independent (checked under several
  `PYTHONHASHSEED` values).
- The 2 hardware benchmarks and the network link check differ only in measured values.
- All relative links and anchors resolve, and all Folder 10 URLs are reachable.

## Where this KB refines the brief

- **"L7 = Principal" is company-specific.** Normalized above. Preparing for Amazon L7 means the Principal Engineering
  Tenets. Preparing for Google L7 means Senior Staff, not Principal (L8).
- **"Speed of light in fiber ~200 km/ms" is correct** (204 km/ms). The usual errors are forgetting round trips, and
  route inflation of 1.2–2.5× over the great circle. File 02 §4.1 measures both.
- **"BBR vs CUBIC" is not "BBR wins".**
  - BBR wins on long, lossy paths.
  - BBRv1 has fairness and retransmission problems in shallow buffers.
  - Datacenter traffic wants DCTCP or delay-based CC.
- **Kernel bypass is a TCO and operability decision**, with polling cores and lost kernel tooling, not a free speedup.
  io_uring also carries a documented security cost.
- **LSM vs B+tree cannot be decided at the application layer alone.** Write amplification multiplies with the SSD's
  FTL amplification, and placement can halve the latter (file 02 §3.2–3.3).
- **CAP's C is linearizability of one register, not ACID consistency. "CA" does not exist**, and CP/AP labels are
  replaced by per-operation models (file 03 §4).
- **R + W > N is overlap, not linearizability** (file 03 §6, demonstrated by simulation and checker).
- **"Shuffle sharding limits a poison pill to < 0.5% of tenants"** holds, and the math makes it precise: with 5 of
  100 workers, 0.06% of tenants lose a majority and ~10⁻⁸ are fully down. But 23% see *some* impact, absorbed only
  if clients retry across shard members (Folder 05 file 01).
- **"Jittered backoff budgets" are two different things.** Backoff + jitter alone did *not* recover from a
  metastable state (goodput stayed 0). The retry *budget* and deadline-aware dropping did (Folder 05 file 02).
- **"TrueTime ε ≤ 7 ms"** is the 2012 paper's sawtooth (1–7 ms). The KB treats ε as a parameter: commit wait =
  2ε, with visible cost = 2ε − Paxos overlap (Folder 02 file 04).
- **Hybrid fan-out's win is bounding per-post fan-out, not average writes.** On a heavy-tailed graph, inbox writes
  fell only 36%, while the worst post went from 2.17M to < 10k writes (Folder 07 problem 12).
- **Batched dispatch** improves mean pickup distance but can *worsen* the tail, so the matching objective must
  encode fairness (Folder 08 problem 22).
- **Pure buffer-based ABR** streams higher bitrate but rebuffers on deep drops until download abandonment is added
  (Folder 07 problem 16).

## Notation

| Symbol | Meaning |
|---|---|
| RTT | Round-trip time |
| BDP | Bandwidth-delay product |
| MSS, IW | TCP maximum segment size; initial window |
| $p$ | Packet loss rate (Mathis); or per-replica unavailability (availability math) |
| $\rho$ | Utilization (queueing); or shared-fate fraction (availability) |
| $\lambda$, $S$, $W$, $L$ | Arrival rate, service time, time in system, items in system (Little: $L = \lambda W$) |
| $c$ | Servers in a pool (Erlang C) |
| $s$ | Zipf exponent |
| WAF, OP | Write amplification factor; over-provisioning ratio |
| $N, R, W$ | Replicas, read quorum, write quorum |
| $\epsilon$ | TrueTime uncertainty bound (Folder 02/03) |
| $d$ | Minimum one-way message delay (consistency lower bound) |
