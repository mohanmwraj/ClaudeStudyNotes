# NewSQL Internals: Spanner TrueTime, CockroachDB HLC, and Aurora Storage Quorums

> **Folder 02 · File 04** of the Distributed Systems & System Design L7 Reference.
> **Prerequisites:**
> - [Folder 01 file 03](../01-First-Principles-Physics-and-L5-L6-L7-Rubric/03-cap-pacelc-linearizability-serializability-and-causal-consistency.md)
>   (strict serializability, SI/SSI);
> - [file 02](02-replication-single-leader-multi-leader-and-leaderless-sloppy-quorums.md) (replication modes);
> - Folder 03 ([`03-Consensus-Coordination-and-Distributed-Transactions/`](../03-Consensus-Coordination-and-Distributed-Transactions/)) for Paxos/Raft and clocks in depth.
>
> **Listing:** `newsql_time_lab.py` covers TrueTime commit wait vs naive timestamps, CockroachDB-style uncertainty
> restarts, and Aurora's 6-copy quorum and segment-repair math. The output is deterministic.

---

## 0. What "NewSQL" had to solve

The goal is SQL with ACID transactions, scaled horizontally and replicated across zones or regions. Three hard
problems:

1. **Ordering transactions across machines whose clocks disagree.** Spanner spends money on bounded clocks.
   CockroachDB and YugabyteDB use hybrid logical clocks plus uncertainty windows. TiDB uses a central timestamp
   oracle.
2. **Replicating each shard** with consensus (Paxos/Raft groups per range), so failover is part of the protocol.
3. **Committing across shards**: 2PC whose participants are themselves replicated groups, so the coordinator can't
   block forever (Folder 03 file 03).

Aurora takes a different cut. It keeps a single-writer MySQL/PostgreSQL engine and re-architects **storage**
underneath it.

---

## 1. Spanner (Corbett et al., OSDI 2012)

### 1.1 Architecture

```
 universe ─► zones (unit of physical isolation) ─► spanservers (100s–1000s per zone)
   each spanserver hosts tablets; a "split" (key range) is replicated by a Paxos group across zones/regions
   each Paxos group has a LEADER holding a time-based lease (10 s in the paper) → serves strong reads, runs 2PL
 directories (placement units) move between groups for load/locality; the placement driver is the control plane
 TrueTime: GPS receivers + atomic clocks per datacenter (time masters); daemons poll masters (every 30 s in 2012);
           Marzullo-style interval intersection rejects liars
```

### 1.2 The TrueTime API

```
TT.now()      → TTinterval [earliest, latest]   guaranteed to contain absolute time
TT.after(t)   → true if t has definitely passed  (t < TT.now().earliest)
TT.before(t)  → true if t has definitely not arrived (t > TT.now().latest)
ε = (latest − earliest) / 2: a sawtooth of ~1–7 ms in the 2012 paper (assumed drift 200 µs/s between polls)
```

⚠ Google has since reported much tighter bounds. Use ε as a parameter in your math, not a constant.

### 1.3 Read-write transactions and commit wait

1. The client buffers writes. Reads take **read locks at the leaders** (2PL, wound-wait deadlock avoidance).
2. At commit, the coordinator leader picks the commit timestamp **s = TT.now().latest**. With multiple Paxos groups,
   this follows 2PC prepare: each participant logs a prepare record through Paxos, and s ≥ every participant's
   prepare timestamp.
3. **Commit wait:** the leader waits until **TT.after(s)** before making the commit visible and releasing locks.
4. Commit wait **overlaps** the Paxos replication round, so its *visible* cost is max(0, 2ε − Paxos latency).

**Why the wait gives external consistency.** Suppose T1 commits before T2 starts in real time.
- T1 was not acknowledged until absolute time exceeded s₁. That is what TT.after guarantees.
- T2 starts after that acknowledgment, so its s₂ = TT.now().latest > (absolute time at T2's start) > s₁.
- So **s₁ < s₂**: timestamp order equals real-time order for *every* pair of transactions, on any machines. That is
  strict serializability, without any communication between T1's and T2's machines.

§A of the output tests this. T2 begins on another node a small gap after T1's acknowledgment:

| ε | Gap | Naive local-clock timestamps: T2 ordered before T1 | TrueTime + commit wait | Wait |
|---|---|---|---|---|
| 1 ms | 0.1 ms | **45.2%** | 0 | 2 ms |
| 4 ms | 1 ms | 38.6% | 0 | 8 ms |
| 7 ms | 5 ms | 20.7% | 0 | 14 ms |

Naive timestamps violate real-time order whenever the clock skew exceeds the causal gap. With ms-level skew and
sub-ms gaps, that is *routinely*. Commit wait makes violations impossible by paying ≈ 2ε. With a 5 ms Paxos round
overlapping it, ε = 1 ms costs nothing visible, ε = 4 ms adds 3 ms, and ε = 7 ms adds 9 ms. **Spanner's latency is a
clock-accuracy budget.** That is why Google invests in time infrastructure.

### 1.4 Reads without locks

- **Strong read-only transactions** read at s = TT.now().latest. A replica can serve the read once its **safe time**
  $t_\text{safe} \ge s$, which is bounded by its Paxos state and by pending prepared transactions. No locks are taken.
- **Bounded-staleness and exact-staleness reads** (e.g. "as of 10 s ago") can be served by the *nearest* replica
  without contacting the leader. This is the PACELC "else-latency" escape hatch for read-heavy global workloads.
- **Schema changes** are scheduled at a future timestamp, so every server switches atomically without blocking.

### 1.5 Latency anatomy (in-region, 3 replicas)

| Component | Typical (⚠ illustrative) |
|---|---|
| Read locks + buffered writes at the leader | RTT to the leader |
| Paxos majority commit | ~1 intra-region RTT + log fsync (~1–5 ms) |
| Multi-group 2PC prepare | +1 Paxos round per participant group (parallel) |
| Commit wait | max(0, 2ε − overlap) |
| Multi-region configuration | Paxos RTT becomes inter-region: ≥ 12 ms nearby, ~70 ms transatlantic (Folder 01 file 02 §4) |

---

## 2. CockroachDB: Spanner's design without atomic clocks

### 2.1 Architecture

```
 SQL layer (any node) ─► KV layer: key space split into RANGES (default max 512 MiB, ⚠ verify)
   each range = a Raft group (RF 3/5); one replica holds the LEASE (leaseholder) → serves reads, proposes writes
   timestamps = HLC (wall time + logical counter), Folder 03 file 02
   MVCC: every value is versioned by HLC timestamp; "write intents" are provisional values pointing to a txn record
```

### 2.2 Uncertainty instead of commit wait

- CockroachDB requires node clocks to stay within `--max-offset` of each other. The default is **500 ms** (⚠ verify).
- A node whose offset from a majority of peers exceeds a threshold of that bound (80% in the docs) **shuts itself
  down**. The safety of the protocol depends on this self-fencing.
- A transaction reading at timestamp $r$ that encounters a value with timestamp in the **uncertainty interval**
  $(r, r + \text{max\_offset}]$ cannot know whether that write happened before it in real time. It **restarts** at a
  higher timestamp: `ReadWithinUncertaintyIntervalError`, often retried transparently.
- Observed-timestamp optimizations shrink the interval after the first read at a node.

§B of the output models this. Node offsets are uniform within max_offset, Poisson writes on a key, one read:

| Writes/s on the key | max_offset | P(stale read without the interval) | P(restart with it) | Model $1-e^{-\lambda M}$ |
|---|---|---|---|---|
| 10 | 500 ms | **44.7%** | **99.3%** | 99.3% |
| 10 | 50 ms | 7.5% | 39.4% | 39.4% |
| 10 | 5 ms | 0.7% | 4.8% | 4.9% |
| 0.1 | 500 ms | 0.8% | 4.8% | 4.9% |
| 0.1 | 50 ms | 0.13% | 0.56% | 0.50% |

Reading the table:
1. **The interval is what makes reads correct.** Without it, a read on a hot key would miss real-time-earlier writes
   ~45% of the time at 500 ms offsets. With it, there are zero stale reads.
2. **Restarts are the price, and they scale with write rate × max_offset.** On hot keys with default offsets,
   essentially every read restarts at least once. Tightening clocks (AWS Time Sync / PTP to µs-level, then a lower
   `max-offset`) cuts restart rates proportionally.

   CockroachDB's later *non-blocking transactions* for **global tables** go the other way. They write at a future
   timestamp and use a *commit wait* like Spanner, so reads anywhere are fast and never block (⚠ verify the version
   semantics).
3. **Not strictly serializable across unrelated keys.** Two transactions on disjoint keys can be ordered by
   timestamps that invert real time by up to max_offset: the "causal reverse" anomaly (Folder 01 file 03 §3.3).
   Serializability holds; linearizability per key holds.

### 2.3 Transactions: intents, transaction records, parallel commits

```
 BEGIN ─► writes become INTENTS on each range (provisional MVCC values + pointer to the txn record)
 COMMIT (classic):   1) all intents replicated  2) txn record → COMMITTED (another consensus round)
 PARALLEL COMMIT:    txn record → STAGING (listing all intent keys) IN PARALLEL with the last writes;
                     the txn is implicitly committed once every listed intent is replicated → one consensus
                     latency instead of two; intents are resolved asynchronously
 conflicts: a reader meeting an intent checks the txn record → wait, push the txn's timestamp, or abort it
 serializable: timestamps can be "pushed"; a txn whose read timestamp moves must REFRESH its reads (re-validate
               that nothing changed) or restart → serializable without read locks
```

---

## 3. The timestamp-oracle alternative: TiDB / Percolator

TiDB (on TiKV) uses **Percolator-style** transactions (Folder 03 file 03):
- a central **timestamp oracle** (TSO) in the Placement Driver hands out monotonic timestamps;
- every transaction gets a start_ts and a commit_ts from it;
- **clock skew stops mattering**, because one server defines time.

The costs:
- **one round trip to the TSO per transaction**, plus the TSO's own failover (Raft-replicated, with batched
  timestamp allocation);
- **a single global ordering point**, which makes cross-region deployments pay TSO latency on every transaction.

Async-commit and 1PC optimizations cut commit latency (⚠ verify the version semantics).

---

## 4. Amazon Aurora: "the log is the database" (Verbitski et al., SIGMOD 2017)

### 4.1 The insight

In a traditional MySQL-on-EBS deployment with replicas, one transaction generates many network writes: redo log,
binlog, data pages, double-write pages, and their mirrored copies. Aurora ships **only redo log records** from the
single writer instance to a distributed storage service. The storage nodes apply redo to materialize pages in the
background, and serve page reads.

```
             ┌──────────────── writer instance (MySQL/PG engine, buffer pool) ────────────────┐
             │ commit = redo records reach a write quorum; no page writes from the instance   │
             └──────┬──────────────┬──────────────┬──────────────┬──────────────┬──────────────┘
          AZ-a: seg copy 1, 2   AZ-b: seg copy 3, 4   AZ-c: seg copy 5, 6        (per 10 GB protection group)
             │ storage nodes: append redo → ack → (async) apply, gossip to fill gaps, backup to S3
             └─► readers: replica instances receive the redo stream and update cached pages (lag ~10s of ms)
 write quorum 4/6, read quorum 3/6; normal reads need NO quorum: the writer knows which copies are complete
```

### 4.2 Why six copies and these quorums

The requirement was to survive **"AZ + 1"**: a whole AZ down *plus* one more node.
- Reads must stay available, so no data is lost.
- Writes must survive the loss of a whole AZ.

With 2 copies in each of 3 AZs:
- **Losing an AZ** leaves 4 copies, so writes (4/6) still succeed.
- **Losing an AZ plus one node** leaves 3, so reads (3/6) still work and the data can be rebuilt.
- Write quorum 4 + read quorum 3 > 6 gives overlap; 4 + 4 > 6 prevents conflicting writes.

§C of the output, during an AZ outage, with other nodes down with probability p:

| p | 3 copies (1/AZ), 2/3 quorum: write / read | 6 copies (2/AZ): write 4/6 / read 3/6 |
|---|---|---|
| 0.1% | 99.80% / 99.80% | 99.60% / **99.9994%** |
| 1% | 98.01% / 98.01% | 96.06% / **99.94%** |
| 5% | 90.25% / 90.25% | 81.45% / **98.60%** |

The honest read: **six copies buy read availability and durability under AZ + 1, and slightly *lower* write
availability during an AZ outage** (all 4 survivors must be up). Aurora's answer to the write side is speed:
segments are small, so a failed copy is replaced in seconds.

### 4.3 Small segments shrink the double-fault window

The probability that another copy of the same segment fails during repair, at an annual failure rate of 4%:

| Repair unit | MTTR | P(double fault during repair) |
|---|---|---|
| **10 GB segment over 10 Gb/s** | ~10 s | **6.3×10⁻⁸** |
| 1 TB volume | ~15 min | 5.7×10⁻⁶ |
| 10 TB node rebuild | ~3 h | 6.8×10⁻⁵ |

That is **~1,000× smaller** risk per repair from repairing small units. The paper's design rationale is the same:
make MTTR so short that the probability of a correlated second failure inside it is negligible. The same lever
appears in file 03 §7, many-to-many recovery.

### 4.4 Other Aurora mechanics worth knowing

- **Consistency points:**
  - **VCL** (volume complete LSN) is the highest LSN with all prior records durable.
  - **VDL** (volume durable LSN) is the highest *consistency point* (end of a mini-transaction) ≤ VCL.
  - On crash recovery, storage truncates above the VDL. There is no redo replay at the instance, so recovery takes
    seconds.
- **Read replicas** share the same storage volume and apply the redo stream to cached pages. They need no second copy
  of the data and see lag in the tens of milliseconds.
- **Aurora Global Database** replicates at the storage layer across regions, typically < 1 s lag. **Aurora DSQL**
  (announced 2024) is a distinct, multi-region active-active design with optimistic concurrency. ⚠ Verify the
  current semantics and limits for both.

---

## 5. Comparison

| | Spanner | CockroachDB | YugabyteDB | TiDB | Aurora (MySQL/PG) |
|---|---|---|---|---|---|
| Time | TrueTime (bounded ε) | HLC + max-offset uncertainty | HLC + uncertainty | Central TSO | Single writer (LSN order) |
| Isolation (default) | Strict serializable | Serializable (RC available) | Snapshot / serializable (⚠ verify) | SI (RR) | Engine's (RR for MySQL, RC for PG) |
| Replication unit | Paxos group per split | Raft per range | Raft per tablet | Raft per region (TiKV) | 6-copy quorum per 10 GB segment |
| Multi-shard txn | 2PC over Paxos groups | Parallel commits, intents | 2PC with provisional records | Percolator 2PC | n/a (single writer) |
| Write scaling | Horizontal | Horizontal | Horizontal | Horizontal | **Vertical** (one writer) |
| Strong reads served by | Leader or replica at safe time | Leaseholder | Leader | Leader | Writer; replicas lag ms |
| Clock dependence | Bounded ε (hardware) | max-offset (self-fencing) | max-offset | None (TSO) | None |
| Typical cross-region write latency | Majority RTT + commit wait | Majority RTT | Majority RTT | Majority RTT + TSO RTT | Async global replicas |

---

## 6. The listing

```python
"""newsql_time_lab.py - why Spanner waits, why CockroachDB restarts, why Aurora uses 6 copies (Folder 02, file 04).

  A. External consistency: T2 starts after T1's commit is acknowledged, on another node with a skewed clock.
     Naive local-clock timestamps can order T2 before T1; TrueTime (s = TT.now().latest, then commit wait until
     TT.after(s)) never does, at a cost of ~2*epsilon.
  B. HLC + uncertainty interval (CockroachDB-style): reads that see a value in (read_ts, read_ts + max_offset] must
     restart; without the interval those reads would have been stale. Restart rate vs max_offset.
  C. Aurora-style quorums: 6 copies in 3 AZs (write 4/6, read 3/6) vs 3 copies (2/3) under "AZ + 1" failures,
     and why 10 GB segments (fast repair) shrink the double-fault window.
Standard library only; seeded, deterministic.
"""
import math
import random


# ---------------------------------------------------------------- A. TrueTime
def external_consistency(eps_ms: float, gap_ms: float, trials: int, rng: random.Random) -> dict:
    naive_viol = tt_viol = 0
    for _ in range(trials):
        t = rng.uniform(0, 1e6)                                   # true commit time of T1
        th_a, th_b = rng.uniform(-eps_ms, eps_ms), rng.uniform(-eps_ms, eps_ms)   # |clock error| <= eps
        # naive: timestamp = local clock, acknowledge immediately
        s1, ack = t + th_a, t
        s2 = ack + gap_ms + th_b
        naive_viol += s2 <= s1
        # TrueTime: s1 = TT.now().latest; wait until TT.now().earliest > s1 (local - eps > s1)
        s1 = t + th_a + eps_ms
        ack = s1 + eps_ms - th_a                                  # true time when local_A - eps passes s1
        s2 = (ack + gap_ms) + th_b + eps_ms
        tt_viol += s2 <= s1
    return {"naive": naive_viol / trials, "truetime": tt_viol / trials, "wait": 2 * eps_ms}


# ---------------------------------------------------------------- B. HLC uncertainty
def poisson(mean: float, rng: random.Random) -> int:
    n, acc, limit = 0, rng.random(), math.exp(-mean)
    while acc > limit:
        n += 1
        acc *= rng.random()
    return n


def uncertainty(max_offset_ms: float, writes_per_s: float, reads: int, rng: random.Random) -> dict:
    """Node clocks are offset uniformly in [-M/2, M/2] (pairwise skew <= M = max_offset). A read at true time T
    on node R uses read_ts r = T + off_R. A write at true time t gets ts = t + off_writer.
      stale (no interval): a write that committed BEFORE T has ts > r, so a plain snapshot read misses it;
      restart (interval):  any write with ts in (r, r + M] is "uncertain" and forces a read restart.
    Every would-be-stale write lands inside (r, r + M], so the interval eliminates stale reads; it also
    restarts on concurrent writes that came after T (false positives)."""
    m = max_offset_ms
    lam = writes_per_s / 1000.0
    stale = restarts = 0
    for _ in range(reads):
        r = rng.uniform(-m / 2, m / 2)                            # true read time T = 0
        is_stale = is_restart = False
        for _ in range(poisson(lam * 4 * m, rng)):                # writes with true time in [-2M, +2M]
            t = rng.uniform(-2 * m, 2 * m)
            ts = t + rng.uniform(-m / 2, m / 2)
            is_stale |= t < 0 and ts > r
            is_restart |= r < ts <= r + m
        stale += is_stale
        restarts += is_restart
    return {"stale_without_interval": stale / reads, "restart_rate": restarts / reads,
            "model_restart": 1 - math.exp(-lam * m)}


# ---------------------------------------------------------------- C. Aurora quorums
def at_least(k: int, n: int, up: float) -> float:
    return sum(math.comb(n, i) * up ** i * (1 - up) ** (n - i) for i in range(k, n + 1))


def quorum_table(p_node_down: float) -> dict:
    up = 1 - p_node_down
    return {
        "3 copies (1/AZ), 2/3 quorum": {"write": at_least(2, 2, up), "read": at_least(2, 2, up)},
        "6 copies (2/AZ), write 4/6, read 3/6": {"write": at_least(4, 4, up), "read": at_least(3, 4, up)},
    }


def double_fault(afr: float, copies: int, mttr_s: float) -> float:
    """P(at least one more copy of a segment fails while one is being repaired)."""
    lam = afr / (365.25 * 86400)
    return 1 - math.exp(-(copies - 1) * lam * mttr_s)


def main() -> None:
    rng = random.Random(2012)
    print("== A. external consistency: T2 begins gap ms after T1's commit is acknowledged")
    print(f"{'epsilon':>8} {'gap':>6} {'naive violations':>17} {'TrueTime violations':>20} {'commit wait':>12}")
    ec = {}
    for eps in (1.0, 4.0, 7.0):
        for gap in (0.1, 1.0, 5.0):
            r = external_consistency(eps, gap, 50_000, rng)
            ec[(eps, gap)] = r
            print(f"{eps:>6.1f}ms {gap:>4.1f}ms {r['naive'] * 100:>16.2f}% {r['truetime'] * 100:>19.2f}% "
                  f"{r['wait']:>10.1f}ms")
    paxos = 5.0
    for eps in (1.0, 4.0, 7.0):
        print(f"  with a {paxos:.0f} ms in-region Paxos round overlapping the wait, eps={eps:.0f} ms adds "
              f"{max(0.0, 2 * eps - paxos):.0f} ms of visible commit latency")

    print("\n== B. HLC uncertainty interval: P(read would be stale) vs P(read restarts), by key write rate")
    print(f"{'writes/s':>9} {'max_offset':>11} {'stale w/o interval':>19} {'restart rate':>13} {'1-exp(-lam*M)':>14}")
    hl = {}
    for wps in (10.0, 0.1):
        for mo in (500.0, 250.0, 50.0, 5.0):
            r = uncertainty(mo, wps, 20_000, rng)
            hl[(wps, mo)] = r
            print(f"{wps:>9.1f} {mo:>9.0f}ms {r['stale_without_interval'] * 100:>18.2f}% "
                  f"{r['restart_rate'] * 100:>12.2f}% {r['model_restart'] * 100:>13.2f}%")

    print("\n== C. Aurora-style quorums during an AZ outage, other nodes down w.p. p")
    qt = {}
    for p in (0.001, 0.01, 0.05):
        qt[p] = quorum_table(p)
        for name, v in qt[p].items():
            print(f"  p={p:<6} {name:<40} write {v['write'] * 100:8.4f}%   read {v['read'] * 100:8.4f}%")
    print("  P(another copy of the same segment fails during repair), AFR 4%:")
    df = {}
    for label, mttr in (("10 GB segment over 10 Gb/s (~10 s)", 10), ("1 TB volume over 10 Gb/s (~15 min)", 900),
                        ("10 TB node rebuild (~3 h)", 3 * 3600)):
        df[label] = double_fault(0.04, 6, mttr)
        print(f"    {label:<38} {df[label]:.3e}")

    # self-test
    assert all(r["truetime"] == 0 for r in ec.values())
    assert ec[(4.0, 0.1)]["naive"] > 0.2 and ec[(1.0, 5.0)]["naive"] == 0
    for r in hl.values():
        assert r["restart_rate"] >= r["stale_without_interval"]
        assert abs(r["restart_rate"] - r["model_restart"]) < 0.02
    assert hl[(10.0, 500.0)]["restart_rate"] > 0.95 and hl[(0.1, 50.0)]["restart_rate"] < 0.01
    six, three = qt[0.01]["6 copies (2/AZ), write 4/6, read 3/6"], qt[0.01]["3 copies (1/AZ), 2/3 quorum"]
    assert six["read"] > three["read"] and six["write"] < three["write"]          # AZ+1 for reads; writes pay
    vals = list(df.values())
    assert vals[0] < vals[1] < vals[2] and vals[2] / vals[0] > 1000
    print("\nself-test: all assertions passed")


if __name__ == "__main__":
    main()
```

Output (verified; deterministic):

```text
== A. external consistency: T2 begins gap ms after T1's commit is acknowledged
 epsilon    gap  naive violations  TrueTime violations  commit wait
   1.0ms  0.1ms            45.15%                0.00%        2.0ms
   1.0ms  1.0ms            12.57%                0.00%        2.0ms
   1.0ms  5.0ms             0.00%                0.00%        2.0ms
   4.0ms  0.1ms            48.77%                0.00%        8.0ms
   4.0ms  1.0ms            38.59%                0.00%        8.0ms
   4.0ms  5.0ms             7.13%                0.00%        8.0ms
   7.0ms  0.1ms            49.77%                0.00%       14.0ms
   7.0ms  1.0ms            43.17%                0.00%       14.0ms
   7.0ms  5.0ms            20.68%                0.00%       14.0ms
  with a 5 ms in-region Paxos round overlapping the wait, eps=1 ms adds 0 ms of visible commit latency
  with a 5 ms in-region Paxos round overlapping the wait, eps=4 ms adds 3 ms of visible commit latency
  with a 5 ms in-region Paxos round overlapping the wait, eps=7 ms adds 9 ms of visible commit latency

== B. HLC uncertainty interval: P(read would be stale) vs P(read restarts), by key write rate
 writes/s  max_offset  stale w/o interval  restart rate  1-exp(-lam*M)
     10.0       500ms              44.70%        99.30%         99.33%
     10.0       250ms              30.20%        91.94%         91.79%
     10.0        50ms               7.52%        39.41%         39.35%
     10.0         5ms               0.72%         4.75%          4.88%
      0.1       500ms               0.80%         4.79%          4.88%
      0.1       250ms               0.40%         2.33%          2.47%
      0.1        50ms               0.13%         0.56%          0.50%
      0.1         5ms               0.02%         0.07%          0.05%

== C. Aurora-style quorums during an AZ outage, other nodes down w.p. p
  p=0.001  3 copies (1/AZ), 2/3 quorum              write  99.8001%   read  99.8001%
  p=0.001  6 copies (2/AZ), write 4/6, read 3/6     write  99.6006%   read  99.9994%
  p=0.01   3 copies (1/AZ), 2/3 quorum              write  98.0100%   read  98.0100%
  p=0.01   6 copies (2/AZ), write 4/6, read 3/6     write  96.0596%   read  99.9408%
  p=0.05   3 copies (1/AZ), 2/3 quorum              write  90.2500%   read  90.2500%
  p=0.05   6 copies (2/AZ), write 4/6, read 3/6     write  81.4506%   read  98.5981%
  P(another copy of the same segment fails during repair), AFR 4%:
    10 GB segment over 10 Gb/s (~10 s)     6.338e-08
    1 TB volume over 10 Gb/s (~15 min)     5.704e-06
    10 TB node rebuild (~3 h)              6.844e-05

self-test: all assertions passed
```

---

## 7. L5 vs L6 vs L7

| Topic | L5 (Senior) | L6 (Staff) | L7 (Principal) |
|---|---|---|---|
| Spanner | "Globally consistent DB using atomic clocks" | TrueTime intervals, commit wait ≈ 2ε, Paxos per split, lock-free snapshot reads | Proves why commit wait gives external consistency; prices latency as clock budget minus Paxos overlap; uses bounded-staleness reads to escape PACELC-E costs |
| CockroachDB | "Open-source Spanner" | HLC, ranges, leaseholders, uncertainty restarts | Restart rate = f(write rate × max_offset); self-fencing on clock offset as a safety mechanism; causal-reverse anomaly; global tables trade write latency for fast reads |
| Aurora | "Faster MySQL on AWS" | Log-shipping storage, 6 copies, 4/6 and 3/6 quorums | AZ+1 reasoning; segment size → MTTR → double-fault probability; why writes are slightly *less* available under AZ loss; single-writer scaling limit |
| Choosing | "Use Spanner for scale" | Picks by write scaling and geography | Picks by invariant scope (single-shard vs global), clock infrastructure available, write-scaling need, and TCO; often "Aurora/PG for 95% of services, distributed SQL only where one writer can't keep up or multi-region RPO=0 is required" |

---

## 8. Bar-raiser probing chains

### Chain A: "Why does Spanner need atomic clocks?"

1. **L5:** "To keep timestamps in sync."
2. **Probe:** "What happens if clocks are off by 5 ms?" **L6:** "TrueTime exposes the uncertainty as ε; commits wait
   out 2ε, so ordering is still correct, just slower."
3. **Probe:** "Could you build it on NTP?" **L7:**
   - "Yes, correctness only needs a *trustworthy bound*. NTP's bound is ~10–100 ms in bad cases, so commit wait would
     add 20–200 ms per write, unacceptable for OLTP."
   - "The clocks exist to make ε small, not to make correctness possible."
   - "Alternatives: HLC + uncertainty (pay with read restarts, lose strictness across keys), or a TSO (pay one RTT to
     a central server, and it's a global chokepoint)."
   - "Today PTP-based cloud time services give µs-level bounds (AWS ClockBound exposes them), shrinking every one of
     these costs."

### Chain B: "Our CockroachDB cluster shows high transaction retry rates on a hot table."

1. **L5:** "Increase retries in the client."
2. **Probe:** "Errors are `ReadWithinUncertaintyIntervalError`." **L6:** "Reads are hitting recent writes inside the
   max-offset window. Reduce contention on the hot keys, or use AS OF SYSTEM TIME for reads that tolerate staleness."
3. **Probe:** "Quantify and fix structurally." **L7:**
   - "Restart probability ≈ 1 − e^{−λ·max_offset}. At 10 writes/s and 500 ms that's 99%."
   - Improve clock sync and lower max-offset, which is safe only with monitored offsets.
   - Route stale-tolerant reads to follower reads.
   - Split the hot row (counters → sharded rows).
   - Batch writes to reduce λ.
   - "Retries are a metastability risk at peak (Folder 05 file 02), so budget them."

### Chain C: "Should we move our main PostgreSQL to Aurora, Spanner, or CockroachDB?"

1. **L5:** "Spanner, it scales infinitely."
2. **Probe:** "We're at 20k writes/s, one region, growing 50%/year." **L6:** "Aurora gives us a managed single-writer
   with fast failover and read replicas; distributed SQL when we outgrow one writer."
3. **Probe:** "Make the decision." **L7:**
   - Compute the runway: when does peak write load cross the single-writer ceiling, measured on our own workload?
   - Price the migration risk: distributed SQL changes latency per statement (every write is a consensus round), and
     transaction retry semantics.
   - Identify the invariants that truly need cross-shard transactions. Often few; the rest can be partitioned by
     tenant.
   - Recommendation: "Aurora now. Design tenant-partitioned schemas so a later move to per-tenant shards or
     distributed SQL is a data migration, not a rewrite. Revisit when write peak reaches 60% of the measured ceiling."

---

## 9. Invariants checklist

- [ ] The clock assumption is explicit: bounded ε (TrueTime/ClockBound), max-offset with self-fencing, or none (TSO).
- [ ] Commit-path latency is decomposed: lock + consensus RTT + 2PC rounds + commit wait.
- [ ] Read paths are chosen per query: strong (leader), safe-time (replica), bounded-staleness (nearest).
- [ ] Retry-producing mechanisms (uncertainty, serialization failures) are budgeted and monitored.
- [ ] Quorum geometry is justified by the failure model (AZ+1) and by MTTR (segment size).
- [ ] Single-writer ceilings are measured, and the migration path is designed before they are reached.

---

## 10. References

- J. Corbett et al. *Spanner: Google's Globally-Distributed Database.* OSDI 2012 (TOCS 2013).
- E. Brewer. *Spanner, TrueTime and the CAP Theorem.* Google whitepaper, 2017.
- R. Taft et al. *CockroachDB: The Resilient Geo-Distributed SQL Database.* SIGMOD 2020.
- S. Kulkarni et al. *Logical Physical Clocks and Consistent Snapshots in Globally Distributed Databases.* OPODIS 2014
  (HLC).
- D. Peng, F. Dabek. *Large-scale Incremental Processing Using Distributed Transactions and Notifications.* OSDI 2010
  (Percolator).
- D. Huang et al. *TiDB: A Raft-based HTAP Database.* VLDB 2020.
- A. Verbitski et al. *Amazon Aurora: Design Considerations for High Throughput Cloud-Native Relational Databases.*
  SIGMOD 2017. *Amazon Aurora: On Avoiding Distributed Consensus for I/Os, Commits, and Membership Changes.* SIGMOD
  2018.
- CockroachDB documentation: *Transaction Layer*, *Parallel Commits*, clock synchronization and `--max-offset`, global
  tables. AWS: *Amazon Time Sync Service* and ClockBound (github.com/aws/clock-bound).
