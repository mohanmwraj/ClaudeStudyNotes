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

The KB is generated **one folder per turn**, and this README tracks progress.

## Layout and build status

| # | Folder | Status |
|---|--------|--------|
| 01 | [`01-First-Principles-Physics-and-L5-L6-L7-Rubric/`](01-First-Principles-Physics-and-L5-L6-L7-Rubric/) | ✅ Written 2026-10-27 |
| 02 | `02-Storage-Engines-Replication-and-Sharding-Internals/` | ⏳ Planned: B+tree vs LSM math, replication, consistent hashing, NewSQL (Spanner, CockroachDB, Aurora) |
| 03 | `03-Consensus-Coordination-and-Distributed-Transactions/` | ⏳ Planned: Paxos/Raft/Zab, clocks (NTP, Lamport, vector, HLC, TrueTime), locks/fencing/2PC/Percolator/Saga |
| 04 | `04-Networking-Edge-Caching-and-Global-Traffic-Routing/` | ⏳ Planned: anycast/GeoDNS/Maglev/Envoy, TAO and lease tokens, CDN and QUIC |
| 05 | `05-Resiliency-Multi-Region-and-Metastable-Failures/` | ⏳ Planned: cells and shuffle sharding, metastability, static stability |
| 06 | `06-32-Master-Problems-Part1-Data-Storage-and-Infra/` | ⏳ Planned: problems 1–11 |
| 07 | `07-32-Master-Problems-Part2-Social-Search-and-Media/` | ⏳ Planned: problems 12–21 |
| 08 | `08-32-Master-Problems-Part3-Commerce-Geo-and-FinTech/` | ⏳ Planned: problems 22–32 |
| 09 | `09-Deep-Dive-Architectural-Comparisons-and-Tradeoffs/` | ⏳ Planned: database and messaging decision matrices |
| 10 | `10-Engineering-Blogs-Papers-and-GitHub-Reference-Index/` | ⏳ Planned: blogs, papers, repositories |

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
     - a cache/DRAM ladder: L1 1.2 ns, L2 4 ns, L3 15 ns, DRAM 111 ns;
     - MLP of ~12 misses in flight;
     - false sharing at 3× and a shared counter at 6.5× the padded case;
     - fsync at p50 ~1 ms with p99 up to 102 ms on consumer QLC;
     - group commit at 46× serial throughput;
     - 35 µs loopback RTT;
     - single-core CRC32C 20 GB/s, AES-GCM 6 GB/s, zlib 0.19 GB/s.
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
- **Forward references** to unwritten folders are given as folder names, not links, until those folders exist.

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

Folder 01 gate (2026-10-27):
- 9 listings extracted, all identical to their sources.
- All 9 pass their self-tests.
- The 7 deterministic outputs are identical; the 2 measured outputs differ only in timings.
- All relative links and anchors resolve.

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
