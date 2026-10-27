# Seminal Distributed-Systems Papers: The Cheat Sheet

> **Folder 10 · File 02** of the Distributed Systems & System Design L7 Reference.
> **Format:** each paper has its venue and year, the one idea, the *interview sentence* (how to use it in a design
> discussion without sounding like you're name-dropping), and where the KB uses it. Links were checked by
> `verify_reading_list.py` (file 03 §4). Papers without a stable public link are cited by title.

---

## 1. Foundations: time, order, consensus, impossibility

| Paper | Venue / year | The one idea | Interview sentence | KB |
|---|---|---|---|---|
| [Time, Clocks, and the Ordering of Events](https://lamport.azurewebsites.net/pubs/time-clocks.pdf) (Lamport) | CACM 1978 | Happens-before; logical clocks; state-machine replication | "Physical clocks can't order events; I'll use per-entity sequence numbers or Lamport/HLC timestamps." | F03 f02 |
| [Impossibility of Distributed Consensus with One Faulty Process](https://groups.csail.mit.edu/tds/papers/Lynch/jacm85.pdf) (FLP) | JACM 1985 | No deterministic async consensus guarantees termination | "Consensus is always safe and only live under partial synchrony, which is why timeouts and leaders exist." | F03 f01 |
| [Paxos Made Simple](https://lamport.azurewebsites.net/pubs/paxos-simple.pdf) (Lamport) | 2001 | Two-phase quorum agreement; a chosen value never changes | "Quorum intersection is the invariant; everything else is optimization." | F03 f01 |
| [In Search of an Understandable Consensus Algorithm](https://raft.github.io/raft.pdf) (Raft) | USENIX ATC 2014 | Leader election + log replication + safety rules | "Only current-term entries commit by counting: the Figure 8 rule." | F03 f01 |
| Paxos Made Live (Chandra, Griesemer, Redstone) (title only) | PODC 2007 | The gap between the algorithm and a production system | "Snapshots, membership, disk corruption and testing are most of the work." | F03 f01 |
| Viewstamped Replication Revisited (Liskov, Cowling) (title only) | MIT TR 2012 | Primary-backup consensus with view changes | "Equivalent to Raft; different vocabulary." | F03 f01 |
| [Flexible Paxos](https://arxiv.org/abs/1608.06696) (Howard et al.) | OPODIS 2016 | Only phase-1 and phase-2 quorums must intersect | "Small replication quorums, large election quorums." | F03 f01 |
| [There Is More Consensus in Egalitarian Parliaments (EPaxos)](https://dl.acm.org/doi/10.1145/2517349.2517350) | SOSP 2013 | Leaderless, commutativity-aware consensus | "One-RTT commits from any replica when commands commute." | F03 f01 |
| [Linearizability](https://cs.brown.edu/~mph/HerlihyW90/p463-herlihy.pdf) (Herlihy & Wing) | TOPLAS 1990 | Real-time-respecting atomicity; locality | "Linearizability composes; sequential consistency doesn't." | F01 f03 |
| Brewer's Conjecture… (Gilbert & Lynch) (title only) | SIGACT News 2002 | CAP, formally: linearizable register vs availability under partitions | "CAP's C is one register's linearizability, not ACID." | F01 f03 |
| [Consistency Tradeoffs in Modern Distributed Database System Design (PACELC)](https://www.cs.umd.edu/~abadi/papers/abadi-pacelc.pdf) (Abadi) | IEEE Computer 2012 | Else: latency vs consistency | "The latency cost of consistency is paid every day, not just in partitions." | F01 f03 |
| [A Critique of the CAP Theorem](https://arxiv.org/abs/1509.05393) (Kleppmann) | 2015 | CAP's definitions are too narrow to classify systems | "I'll describe the model per operation instead of CP/AP." | F01 f03 |

## 2. Consistency, isolation and transactions

| Paper | Venue / year | The one idea | Interview sentence | KB |
|---|---|---|---|---|
| [A Critique of ANSI SQL Isolation Levels](https://www.microsoft.com/en-us/research/wp-content/uploads/2016/02/tr-95-51.pdf) (Berenson et al.) | SIGMOD 1995 | Snapshot isolation; anomalies P0–P4, A5A/B | "SI allows write skew, so booking needs materialized conflicts." | F01 f03, problem 24 |
| Weak Consistency (Adya, PhD thesis) (title only) | MIT 1999 | Dependency-graph definitions of isolation levels | "Isolation is defined by forbidden cycles." | F01 f03 |
| Serializable Isolation for Snapshot Databases (Cahill et al.) (title only) | SIGMOD 2008 | SSI: abort the pivot of rw-antidependencies | "PostgreSQL SERIALIZABLE is SSI; budget its aborts." | F01 f03 |
| [Highly Available Transactions](https://www.vldb.org/pvldb/vol7/p181-bailis.pdf) (Bailis et al.) | VLDB 2014 | Which isolation levels survive partitions | "Read committed and causal are achievable with availability; SI isn't." | F01 f03 |
| [Probabilistically Bounded Staleness](https://vldb.org/pvldb/vol5/p776_peterbailis_vldb2012.pdf) (Bailis et al.) | VLDB 2012 | Staleness as a distribution | "I'd state a freshness SLO like 'p99.9 fresh within 50 ms'." | F01 f03 |
| [Don't Settle for Eventual (COPS)](https://www.cs.cmu.edu/~dga/papers/cops-sosp2011.pdf) | SOSP 2011 | Scalable causal+ consistency | "Causal is the strongest model that stays available." | F01 f03 |
| Session Guarantees for Weakly Consistent Replicated Data (Terry et al.) (title only) | PDIS 1994 | RYW, monotonic reads/writes, WFR | "Session tokens give read-your-writes across regions." | F01 f03 |
| [Conflict-free Replicated Data Types](https://hal.inria.fr/inria-00609399) (Shapiro et al.) | SSS 2011 | Convergence by commutativity | "Counters and sets merge without consensus." | F02 f02, problem 21 |
| Large-scale Incremental Processing… (Percolator) (title only) | OSDI 2010 | SI transactions over Bigtable via a primary lock | "The transaction's fate lives in one row." | F03 f03 |
| Consensus on Transaction Commit (Gray & Lamport) (title only) | TODS 2006 | Paxos Commit: non-blocking 2PC | "Replicate the coordinator's decision." | F03 f03 |
| Sagas (Garcia-Molina & Salem) (title only) | SIGMOD 1987 | Long transactions as compensable steps | "Compensations plus semantic locks, with idempotent steps." | F03 f03 |

## 3. Storage engines and data structures

| Paper | Venue / year | The one idea | Interview sentence | KB |
|---|---|---|---|---|
| The Log-Structured Merge-Tree (O'Neil et al.) (title only) | Acta Informatica 1996 | Batch random writes into sequential merges | "Writes become sequential; reads pay per level." | F02 f01 |
| Designing Access Methods: The RUM Conjecture (title only) | EDBT 2016 | Read, update, memory: pick two | "Which overhead does this workload need minimized?" | F02 f01 |
| [WiscKey](https://www.usenix.org/conference/fast16/technical-sessions/presentation/lu) | FAST 2016 | Separate keys from values in LSMs | "Large values out of the LSM cut compaction WAF." | F02 f01 |
| Monkey (Dayan et al.) (title only) | SIGMOD 2017 | Optimal Bloom bits per level | "Fewer bits in deeper levels minimizes total FPR." | F02 f01 |
| [Ribbon Filter](https://arxiv.org/abs/2103.02515) | 2021 | ~30% smaller than Bloom at equal FPR | "Static filters for SSTs can be Ribbon." | F02 f01 |
| [ZNS: Avoiding the Block Interface Tax](https://www.usenix.org/conference/atc21/presentation/bjorling) | USENIX ATC 2021 | Host-managed zones remove FTL GC | "Data that dies together lives together (WAF 5.25 → 2.63 here)." | F01 f02 |
| Bigtable (Chang et al.) (title only) | OSDI 2006 | Sorted, range-partitioned, LSM tablets | "Range partitioning with a metadata hierarchy." | F02 f03, problem 1 |
| [Dynamo](https://www.allthingsdistributed.com/files/amazon-dynamo-sosp2007.pdf) (DeCandia et al.) | SOSP 2007 | Leaderless quorums, sloppy quorums, vector clocks | "R+W>N is overlap, not linearizability." | F01 f03, F02 f02 |
| [Amazon DynamoDB](https://www.usenix.org/conference/atc22/presentation/elhemali) | USENIX ATC 2022 | Predictable latency at multi-tenant scale | "Admission control is the product." | Problem 1 |
| [Spanner](https://www.usenix.org/conference/osdi12/technical-sessions/presentation/corbett) (Corbett et al.) | OSDI 2012 | TrueTime + commit wait = external consistency | "Strictness costs ~2ε; the clocks make ε small." | F02 f04 |
| [CockroachDB](https://dl.acm.org/doi/10.1145/3318464.3386134) (Taft et al.) | SIGMOD 2020 | HLC + uncertainty restarts; parallel commits | "Restarts scale with write rate × max offset." | F02 f04 |
| [Amazon Aurora](https://www.amazon.science/publications/amazon-aurora-design-considerations-for-high-throughput-cloud-native-relational-databases) (Verbitski et al.) | SIGMOD 2017 | Ship redo, not pages; 6-copy quorums | "AZ+1 durability with 10 GB segments for fast repair." | F02 f04 |
| [Chain Replication](https://www.usenix.org/legacy/event/osdi04/tech/full_papers/renesse/renesse.pdf) (van Renesse & Schneider) | OSDI 2004 | Head writes, tail reads | "One copy of outbound bandwidth per node." | F02 f02 |
| [Erasure Coding in Windows Azure Storage](https://www.usenix.org/conference/atc12/technical-sessions/presentation/huang) (LRC) | USENIX ATC 2012 | Local parities cut repair reads | "Durability is a repair-bandwidth problem." | Problem 2 |
| [Gorilla](https://www.vldb.org/pvldb/vol8/p1816-teller.pdf) (Pelkonen et al.) | VLDB 2015 | Delta-of-delta + XOR float compression | "~1.4 bytes/point makes in-memory TSDBs feasible." | Problem 9 |
| [Monarch](https://www.vldb.org/pvldb/vol13/p3181-adams.pdf) (Adams et al.) | VLDB 2020 | Regional, in-memory, planet-scale TSDB | "Monitoring must survive the outages it watches." | Problem 9 |

## 4. Caching, networking, load balancing

| Paper | Venue / year | The one idea | Interview sentence | KB |
|---|---|---|---|---|
| [Scaling Memcache at Facebook](https://www.usenix.org/conference/nsdi13/technical-sessions/presentation/nishtala) | NSDI 2013 | Leases, gutter pools, regional pools | "Leases fix stale sets and herds." | F04 f02 |
| [TAO](https://www.usenix.org/conference/atc13/technical-sessions/presentation/bronson) | USENIX ATC 2013 | A graph-aware write-through cache | "Cache associations and counts, not just objects." | F04 f02 |
| Consistent Hashing and Random Trees (Karger et al.) (title only) | STOC 1997 | Minimal movement on resize | "≈ 1/N keys move, not ≈ all." | F02 f03 |
| [A Fast, Minimal Memory, Consistent Hash Algorithm (Jump)](https://arxiv.org/abs/1406.2294) | 2014 | O(ln n), no memory | "For numbered partitions, not arbitrary nodes." | F02 f03 |
| [Consistent Hashing with Bounded Loads](https://arxiv.org/abs/1608.01350) | SODA 2018 | Capacity (1+ε)·mean; spill clockwise | "Bounds hot-object load at 1.25× (here)." | F02 f03, problem 32 |
| [Maglev](https://www.usenix.org/conference/nsdi16/technical-sessions/presentation/eisenbud) | NSDI 2016 | Lookup-table consistent hashing for L4 LB | "Near-perfect balance, minimal disruption." | F04 f01 |
| [BBR: Congestion-Based Congestion Control](https://queue.acm.org/detail.cfm?id=3022184) | ACM Queue 2016 | Model bottleneck bandwidth and RTT, don't react to loss | "On long lossy paths, loss-based CC collapses." | F01 f02 |
| [The QUIC Transport Protocol](https://dl.acm.org/doi/10.1145/3098822.3098842) | SIGCOMM 2017 | User-space transport, 0-RTT, no TCP HOL | "Gains show up on lossy mobile tails." | F04 f03 |
| [FIFO Queues are All You Need for Cache Eviction (S3-FIFO)](https://dl.acm.org/doi/10.1145/3600006.3613147) | SOSP 2023 | Quick demotion of one-hit wonders | "Admission matters as much as eviction." | F04 f03 |
| The Tail at Scale (Dean & Barroso) (title only) | CACM 2013 | Fan-out amplifies tails; hedging | "At fan-out 100, the leaf p99 becomes the median." | F01 f01 |
| [A Buffer-Based Approach to Rate Adaptation](https://dl.acm.org/doi/10.1145/2619239.2626296) (BBA) | SIGCOMM 2014 | ABR from buffer occupancy | "Buffer-based raises bitrate; add download abandonment for deep drops." | Problem 16 |

## 5. Coordination, authorization, operations, reliability

| Paper | Venue / year | The one idea | Interview sentence | KB |
|---|---|---|---|---|
| The Chubby Lock Service (Burrows) (title only) | OSDI 2006 | Coarse-grained locks with sequencers | "Usage patterns, not Paxos, determine reliability." | Problem 3 |
| ZooKeeper: Wait-free Coordination (Hunt et al.) (title only) | USENIX ATC 2010 | Znodes, watches, ephemeral sequential nodes | "Locks via sequential nodes, with the sequence as a fencing token." | Problem 3 |
| [Zanzibar](https://www.usenix.org/conference/atc19/presentation/pang) (Pang et al.) | USENIX ATC 2019 | Relation tuples, zookies, Leopard | "Zookies solve the new-enemy problem without strong reads everywhere." | Problem 11 |
| Dapper (Sigelman et al.) (title only) | Google TR 2010 | Low-overhead distributed tracing | "Sampling strategy decides what you can debug." | Problem 10 |
| Large-scale cluster management at Google with Borg (title only) | EuroSys 2015 | Cell-based cluster scheduling | "Cells bound blast radius for the scheduler too." | F05 f01 |
| [Metastable Failures in Distributed Systems](https://sigops.org/s/conferences/hotos/2021/papers/hotos21-s11-bronson.pdf) (Bronson et al.) | HotOS 2021 | Trigger vs sustaining effect | "Backoff alone doesn't recover; budgets and deadlines do." | F05 f02 |
| [Metastable Failures in the Wild](https://www.usenix.org/conference/osdi22/presentation/huang-lexiang) (Huang et al.) | OSDI 2022 | An empirical taxonomy of sustaining effects | "Retry policy is the usual sustaining loop." | F05 f02 |
| Controlling Queue Delay (CoDel) (Nichols & Jacobson) (title only) | ACM Queue 2012 | Drop based on the minimum sojourn time | "A standing queue is the signal, not queue length." | F05 f02 |
| [The Dataflow Model](https://www.vldb.org/pvldb/vol8/p1792-Akidau.pdf) (Akidau et al.) | VLDB 2015 | Event time, watermarks, triggers | "Billing uses event time with late updates." | Problem 29 |
| Mercator: A Scalable, Extensible Web Crawler (title only) | WWW 1999 | Front/back queues for politeness | "Throughput = ready hosts / politeness interval." | Problem 20 |
| Replicated Abstract Data Types (RGA) (title only) | JPDC 2011 | Sequence CRDT by unique ordered IDs | "Converges under any causal delivery order." | Problem 21 |
| Hidden Technical Debt in ML Systems (Sculley et al.) (title only) | NeurIPS 2015 | ML systems are mostly glue and data dependencies | "Training–serving skew is a system design problem." | Problem 31 |
| [Efficient Memory Management for LLM Serving (PagedAttention / vLLM)](https://arxiv.org/abs/2309.06180) | SOSP 2023 | Paged KV cache; prefix sharing | "Prefix-aware routing turns cache hits into capacity." | Problem 32 |

---

## 6. A 12-week reading path

| Week | Read | Then do |
|---|---|---|
| 1 | Lamport 1978; Herlihy & Wing; Gilbert & Lynch; Abadi | Run `linearizability_checker.py`; explain H3 and H4 aloud |
| 2 | Berenson et al.; Bailis HAT; Kleppmann CAP critique | Run `mvcc_isolation_sim.py`; whiteboard write skew in booking |
| 3 | Paxos Made Simple; Raft | Run `raft_sim.py`; explain Figure 8 without notes |
| 4 | Dynamo; DynamoDB 2022 | Problem 1 end to end in 45 minutes |
| 5 | Spanner; CockroachDB; Aurora | Price commit latency from the RTT matrix |
| 6 | LSM paper; WiscKey; RUM; ZNS | Run `lsm_btree_lab.py` and `ftl_waf_sim.py`; compute drive lifetime |
| 7 | Memcache; TAO; Maglev | Problems 4 and 12 |
| 8 | Metastable failures ×2; Fail at Scale; CoDel | Run `metastability_sim.py`; design a retry policy |
| 9 | Builders' Library: shuffle sharding, static stability, constant work | Problems 3 and 5; a cell design for a SaaS |
| 10 | Zanzibar; Percolator; Sagas | Problems 11, 26, 27 |
| 11 | Gorilla; Monarch; Dapper; Dataflow Model | Problems 9, 10, 29 |
| 12 | Mock interviews using Folder 01 file 01's scoring sheet | Two problems per day from Folders 06–08 |
