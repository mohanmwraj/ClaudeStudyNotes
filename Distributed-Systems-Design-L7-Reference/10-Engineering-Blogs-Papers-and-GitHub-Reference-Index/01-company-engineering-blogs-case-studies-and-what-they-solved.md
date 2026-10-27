# Company Engineering Blogs and Case Studies: What Each One Solved

> **Folder 10 · File 01** of the Distributed Systems & System Design L7 Reference.
> **How to use it:** each entry maps a public engineering write-up to the problem it illustrates (Folders 06–08) and
> to the L7 concept it proves (Folders 01–05). Read the post, then explain it in the "trigger → mechanism → numbers →
> what I'd do differently" form an L7 interviewer expects.
> **Link policy:** every URL in Folder 10 is checked by `verify_reading_list.py` (file 03 §4). Entries without a
> link are cited by title and year; search the publisher's blog for them. They are marked (title only) rather than
> given a guessed URL.

---

## 0. Blog roots

| Publisher | Blog | Best for |
|---|---|---|
| AWS | [Amazon Builders' Library](https://aws.amazon.com/builders-library/) | Static stability, shuffle sharding, retries/backoff, load shedding, deployments, constant work |
| Netflix | [Netflix TechBlog](https://netflixtechblog.com/) | Resilience engineering, adaptive concurrency, video encoding, CDN (Open Connect), chaos |
| Uber | [Uber Engineering](https://www.uber.com/blog/engineering/) | Geo-indexing (H3), dispatch, ETA, multi-region, schemaless storage, observability |
| Meta | [Engineering at Meta](https://engineering.fb.com/) | TAO, memcache, load balancing (Katran), outage post-mortems, time sync (PTP) |
| Cloudflare | [The Cloudflare Blog](https://blog.cloudflare.com/) | Anycast, BGP incidents, DDoS, L4 load balancing, packet processing, outages |
| Discord | [Discord Engineering](https://discord.com/category/engineering) | Message storage at trillions scale, Cassandra → ScyllaDB, Elixir/Rust performance |
| Stripe | [Stripe Engineering](https://stripe.com/blog/engineering) | Idempotency, rate limiting, online migrations, API design |
| LinkedIn | [LinkedIn Engineering](https://www.linkedin.com/blog/engineering) | Kafka origins, the log abstraction, persistent connections, data infrastructure |
| Figma | [Figma Engineering](https://www.figma.com/blog/engineering/) | Multiplayer (CRDT-inspired) editing, Postgres vertical/horizontal sharding |
| Slack | [Slack Engineering](https://slack.engineering/) | Cellular architecture, Vitess, edge caching, real-time messaging |
| Google | [Google SRE books](https://sre.google/books/) | Error budgets, overload handling, cascading failures, release engineering |
| Marc Brooker | [brooker.co.za](https://brooker.co.za/blog/) | Queueing, retries, metastability, formal methods at AWS: compact and rigorous |

---

## 1. AWS Builders' Library and AWS papers

| Article | What it solved | Maps to | L7 lesson |
|---|---|---|---|
| [Workload isolation using shuffle-sharding](https://aws.amazon.com/builders-library/workload-isolation-using-shuffle-sharding/) | Poison/noisy tenants taking down shared fleets (Route 53) | Folder 05 file 01; problems 1, 5 | Combinatorial isolation: C(2048,4) ≈ 7.3×10¹¹ shards |
| [Static stability using Availability Zones](https://aws.amazon.com/builders-library/static-stability-using-availability-zones/) | Surviving AZ loss without control-plane actions | Folder 05 file 03; Folder 01 file 02 §7.7 | Pre-provisioned capacity; the data plane never waits for the control plane |
| [Timeouts, retries, and backoff with jitter](https://aws.amazon.com/builders-library/timeouts-retries-and-backoff-with-jitter/) | Retry amplification and synchronized retries | Folder 05 file 02 | Retry budgets, a single retrying layer, full jitter |
| [Using load shedding to avoid overload](https://aws.amazon.com/builders-library/using-load-shedding-to-avoid-overload/) | Goodput collapse at overload | Folder 05 file 02 | Shed early and cheaply; protect goodput |
| [Avoiding insurmountable queue backlogs](https://aws.amazon.com/builders-library/avoiding-insurmountable-queue-backlogs/) | Queues that never drain after an outage | Folder 05 file 02; problem 7 | LIFO/aging, per-tenant fairness, backlog-aware recovery |
| [Avoiding fallback in distributed systems](https://aws.amazon.com/builders-library/avoiding-fallback-in-distributed-systems/) | Untested fallback paths causing new failures | Folder 05 file 03 | Prefer "more of the same" degradation to bimodal behavior |
| [Reliability, constant work, and a good cup of coffee](https://aws.amazon.com/builders-library/reliability-and-constant-work/) | Load spikes during recovery from delta-based propagation | Folder 05 file 03 §3 | Constant work: worst case = normal case |
| [Implementing health checks](https://aws.amazon.com/builders-library/implementing-health-checks/) | Health checks causing outages (fail-open/fail-closed) | Folder 04 file 01 §3.3 | Fail open when everything looks unhealthy |
| [Automating safe, hands-off deployments](https://aws.amazon.com/builders-library/automating-safe-hands-off-deployments/) | Bad deploys with global blast radius | Folder 05 file 01 §5 | One-box → waves → regions, bake time, automatic rollback |
| [Making retries safe with idempotent APIs](https://aws.amazon.com/builders-library/making-retries-safe-with-idempotent-APIs/) | Duplicate side effects on retries | Problem 26 | Client request tokens, semantic equivalence of retries |
| [Leader election in distributed systems](https://aws.amazon.com/builders-library/leader-election-in-distributed-systems/) | Leases, fencing and their pitfalls | Folder 03 files 01, 03 | Leases + fencing; leader election is not mutual exclusion |
| DynamoDB paper, USENIX ATC 2022 ([talk/paper](https://www.usenix.org/conference/atc22/presentation/elhemali)) | A predictable-latency multi-tenant KV at scale | Problem 1 | Admission control, adaptive capacity, Multi-Paxos per partition |
| [How Amazon Web Services Uses Formal Methods](https://cacm.acm.org/research/how-amazon-web-services-uses-formal-methods/) (CACM 2015) | Rare-interleaving bugs in S3/DynamoDB designs | Folder 03 file 01 §3.3 | TLA+ finds what chaos testing misses (Figure 8 here) |

---

## 2. Netflix

| Post | What it solved | Maps to | L7 lesson |
|---|---|---|---|
| [Performance Under Load](https://netflixtechblog.com/performance-under-load-3e6fa9a60581) (2018) | Static concurrency limits mis-sized under changing latency | Folder 05 file 02 §3.3 | Adaptive concurrency limits (Vegas/gradient) |
| [Per-Title Encode Optimization](https://netflixtechblog.com/per-title-encode-optimization-7e99442b62a2) (2015) | One bitrate ladder for all content wasted bits | Problem 16 | Spend encode CPU where it saves egress |
| [Open Connect](https://openconnect.netflix.com/) | Transit cost and peak-hour delivery | Problem 4; Folder 04 file 03 §4 | ISP-embedded caches + proactive off-peak fill |
| [Chaos Monkey](https://netflix.github.io/chaosmonkey/) | Untested failure handling | Folder 05 file 02 §6 | Continuous failure injection as a design forcing function |
| [VMAF: The Journey Continues](https://netflixtechblog.com/vmaf-the-journey-continues-44b51ee9ed12) (2018) | Measuring perceptual quality at scale | Problem 16 | Automated quality gates for encoder rollouts |

---

## 3. Uber

| Post | What it solved | Maps to | L7 lesson |
|---|---|---|---|
| [H3: Uber's Hexagonal Hierarchical Spatial Index](https://www.uber.com/blog/h3/) (2018) | Uniform spatial aggregation for marketplace analytics | Problem 22 | Hexagons: uniform adjacency; −24% candidates for radius queries (here) |
| *DeepETA: How Uber Predicts Arrival Times Using Deep Learning* (2022) (title only) | ETA accuracy | Problems 22, 25 | ETA as an ML service with routing priors |
| *Schemaless* series (2016) (title only) | Scalable datastore on MySQL | Problems 1, 13 | Append-only cells + indexes on sharded MySQL |
| *Michelangelo* (2017) (title only) | ML platform with a feature store | Problem 31 | Shared offline/online feature definitions |

---

## 4. Meta

| Post / paper | What it solved | Maps to | L7 lesson |
|---|---|---|---|
| [More details about the October 4 outage](https://engineering.fb.com/2021/10/05/networking-traffic/outage-details/) (2021) | Backbone outage amplified by BGP self-withdrawal | Folder 04 file 01 §1.2; Folder 05 file 03 | Automated health actions with global blast radius; break-glass independence |
| [Open-sourcing Katran](https://engineering.fb.com/2018/05/22/open-source/open-sourcing-katran-a-scalable-network-load-balancer/) (2018) | Software L4 LB at line rate | Folder 04 file 01 §3; Folder 01 file 02 §4.7 | XDP/eBPF data planes; consistent hashing at L4 |
| Scaling Memcache at Facebook, [NSDI 2013](https://www.usenix.org/conference/nsdi13/technical-sessions/presentation/nishtala) | Look-aside caching at billions of ops/s | Folder 04 file 02 | Leases (stale sets 28% → 0% here), gutter pools, warmup |
| TAO, [USENIX ATC 2013](https://www.usenix.org/conference/atc13/technical-sessions/presentation/bronson) | Social-graph caching with write-through ownership | Folder 04 file 02 §5; problem 12 | Cache lists and counts; leader/follower tiers |
| *Fail at Scale* (Maurer, [ACM Queue 2015](https://queue.acm.org/detail.cfm?id=2839461)) | Queueing collapse under overload | Folder 05 file 02 | Adaptive LIFO + controlled delay |
| *How Precision Time Protocol is being deployed at Meta* (2022) (title only) | Sub-µs time across a fleet | Folder 03 file 02 §1.3 | Time as infrastructure with an error budget |

---

## 5. Cloudflare

| Post | What it solved | Maps to | L7 lesson |
|---|---|---|---|
| [Details of the Cloudflare outage on July 2, 2019](https://blog.cloudflare.com/details-of-the-cloudflare-outage-on-july-2-2019/) | A WAF regex backtracking globally | Folder 05 file 03 §2; problem 4 | Config is code: staged rollout, CPU guards |
| [How Verizon and a BGP Optimizer Knocked Large Parts of the Internet Offline Today](https://blog.cloudflare.com/how-verizon-and-a-bgp-optimizer-knocked-large-parts-of-the-internet-offline-today/) (2019) | Route leak | Folder 04 file 01 §1.2 | RPKI, max-prefix, IRR filtering |
| [How to receive a million packets per second](https://blog.cloudflare.com/how-to-receive-a-million-packets/) (2015) | Per-packet kernel costs | Folder 01 file 02 §4.7 | RSS, `SO_REUSEPORT`, packet budgets |
| [Unimog: Cloudflare's edge load balancer](https://blog.cloudflare.com/unimog-cloudflares-edge-load-balancer/) (2020) | L4 balancing inside PoPs | Folder 04 files 01, 03 | XDP L4 LB with consistent flow mapping |
| [How we built rate limiting capable of scaling to millions of domains](https://blog.cloudflare.com/counting-things-a-lot-of-different-things/) (2017) | Accurate, cheap distributed limits | Problem 5 | Sliding-window counters (116 max vs 198 for fixed windows here) |
| [How and why the leap second affected Cloudflare DNS](https://blog.cloudflare.com/how-and-why-the-leap-second-affected-cloudflare-dns/) (2017) | Negative durations from wall clocks | Folder 03 file 02 §1.1 | Monotonic clocks for durations |

---

## 6. Discord

| Post | What it solved | Maps to | L7 lesson |
|---|---|---|---|
| [How Discord Stores Billions of Messages](https://discord.com/blog/how-discord-stores-billions-of-messages) (2017) | Message storage on Cassandra by (channel, bucket) | Problem 13; Folder 02 file 01 | Partition keys bounded in size (time buckets); tombstone pitfalls |
| [How Discord Stores Trillions of Messages](https://discord.com/blog/how-discord-stores-trillions-of-messages) (2023) | Cassandra hot partitions and GC pain → ScyllaDB + a Rust data-services layer with request coalescing | Problem 13; Folder 04 file 02 | Request coalescing protects hot partitions; shard-per-core engines |
| [Why Discord is switching from Go to Rust](https://discord.com/blog/why-discord-is-switching-from-go-to-rust) (2020) | GC-induced latency spikes in a cache service | Folder 01 file 02 §2.5; Folder 05 file 02 §4 | Runtime pauses as a tail-latency source |

---

## 7. Stripe

| Post | What it solved | Maps to | L7 lesson |
|---|---|---|---|
| [Designing robust and predictable APIs with idempotency](https://stripe.com/blog/idempotency) (2017) | Duplicate charges from retries | Problem 26 | Idempotency keys; 9,848 → 0 double charges (here) |
| [Scaling your API with rate limiters](https://stripe.com/blog/rate-limiters) (2017) | Protecting the API from bursts and abuse | Problem 5 | Request limiters + concurrency limiters + load shedders by priority |
| [Online migrations at scale](https://stripe.com/blog/online-migrations) (2017) | Changing data models under live traffic | Folder 01 file 01 §9 Chain 4 | Dual-write → backfill → dual-read verify → cut over |
| [Implementing Stripe-like Idempotency Keys in Postgres](https://brandur.org/idempotency-keys) (Brandur Leach) | Recovery points for multi-step side effects | Problem 26 §26.2 | Atomic phases |

---

## 8. LinkedIn

| Post | What it solved | Maps to | L7 lesson |
|---|---|---|---|
| *The Log: What every software engineer should know about real-time data's unifying abstraction* (Kreps, 2013) (title only; the original LinkedIn URL now returns 404) | The log as the integration backbone | Problem 8; Folder 09 file 02 | Logs, not point-to-point pipes |
| *Instant Messaging at LinkedIn: Scaling to Hundreds of Thousands of Persistent Connections on One Machine* (2016) (title only) | Connection density for real-time features | Problems 13, 15 | Per-host connection math and kernel tuning |
| *Kafka: a Distributed Messaging System for Log Processing* (NetDB 2011) (title only) | Kafka's origins | Problem 8 | Sequential I/O, page cache, zero copy |

---

## 9. Figma

| Post | What it solved | Maps to | L7 lesson |
|---|---|---|---|
| [How Figma's multiplayer technology works](https://www.figma.com/blog/how-figmas-multiplayer-technology-works/) (2019) | Real-time collaborative editing of a scene graph | Problem 21 | Server-authoritative, CRDT-inspired properties; LWW per property; tree reparenting |
| [How Figma's databases team lived to tell the scale](https://www.figma.com/blog/how-figmas-databases-team-lived-to-tell-the-scale/) (2024) | Horizontal sharding of Postgres | Folder 09 file 01; Folder 02 file 03 | Sharding a relational system of record in place, with logical sharding before physical |

---

## 10. Slack, GitHub, Google and others

| Post | What it solved | Maps to | L7 lesson |
|---|---|---|---|
| [Slack's Migration to a Cellular Architecture](https://slack.engineering/slacks-migration-to-a-cellular-architecture/) (2023) | AZ-level gray failures with global impact | Folder 05 file 01 | AZ-aligned cells; draining a cell as the remediation primitive |
| [Scaling Datastores at Slack with Vitess](https://slack.engineering/scaling-datastores-at-slack-with-vitess/) (2020) | MySQL scaling | Folder 09 file 01 | Sharded MySQL via a proxy tier |
| [Flannel: An Application-Level Edge Cache to Make Slack Scale](https://slack.engineering/flannel-an-application-level-edge-cache-to-make-slack-scale/) (2017) | Client boot payload explosion | Problem 13 | Edge caches of per-team state; lazy loading |
| [October 21 post-incident analysis](https://github.blog/news-insights/company-news/oct21-post-incident-analysis/) (GitHub, 2018) | Cross-coast MySQL failover after a 43 s partition | Folder 02 file 02 §1.4 | Automatic cross-region failover can amplify short partitions |
| [Handling Overload](https://sre.google/sre-book/handling-overload/) (Google SRE book) | Overload and criticality | Folder 05 file 02 §3.3 | Client-side adaptive throttling; criticality levels |
| [Addressing Cascading Failures](https://sre.google/sre-book/addressing-cascading-failures/) (Google SRE book) | Cascades from overload | Folder 05 file 02 | Load shedding, retries, deadline propagation |
| [Embracing Risk](https://sre.google/sre-book/embracing-risk/) (Google SRE book) | Choosing availability targets | Folder 01 file 01 §6.2 | Error budgets as a decision tool |
| [Exponential Backoff and Jitter](https://aws.amazon.com/blogs/architecture/exponential-backoff-and-jitter/) (AWS Architecture Blog, 2015) | Synchronized retries | Folder 05 file 02 | Full jitter |
| [How to do distributed locking](https://martin.kleppmann.com/2016/02/08/how-to-do-distributed-locking.html) (Kleppmann, 2016) | Redlock's safety under pauses | Folder 03 file 03 | Fencing tokens (327–384 → 0 stale writes here) |
| [Is Redlock safe?](http://antirez.com/news/101) (antirez, 2016) | The counter-argument | Folder 03 file 03 §1.1 | Know both sides; choose by efficiency vs correctness |
| [Apache Kafka, Purgatory, and Hierarchical Timing Wheels](https://www.confluent.io/blog/apache-kafka-purgatory-hierarchical-timing-wheels/) (Confluent, 2015) | Millions of delayed operations | Problem 7 | Timing wheels (0 mismatches vs a heap here) |

---

## 11. How to turn a blog post into an L7 interview answer

1. **Trigger:** what changed (scale, a failure, a cost)?
2. **Mechanism:** which component failed or saturated, and why. Use the KB's vocabulary: sustaining loop, shared
   fate, hot key, write amplification.
3. **Numbers:** the post's numbers, plus your own back-of-envelope.
4. **Fix and its cost:** what they built and what it costs in latency, money and complexity.
5. **What you'd do differently** with what's known now. This is the step that reads as L7: it shows judgment, not
   recall.
