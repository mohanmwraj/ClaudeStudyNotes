# Time and Clocks: NTP Skew, Lamport and Vector Clocks, HLC, and TrueTime

> **Folder 03 · File 02** of the Distributed Systems & System Design L7 Reference.
> **Prerequisites:**
> - [Folder 02 file 04](../02-Storage-Engines-Replication-and-Sharding-Internals/04-newsql-internals-spanner-truetime-cockroachdb-and-aurora-quorums.md)
>   (TrueTime commit wait, uncertainty restarts);
> - [Folder 01 file 03 §6.3](../01-First-Principles-Physics-and-L5-L6-L7-Rubric/03-cap-pacelc-linearizability-serializability-and-causal-consistency.md#63-last-writer-wins-with-clocks-loses-acknowledged-writes)
>   (LWW loses writes under skew).
>
> **Listing:** `clocks_lab.py` puts wall clocks, Lamport, vector and hybrid logical clocks on the same message history,
> with exact happens-before ground truth. It also covers NTP asymmetry and drift arithmetic. The output is
> deterministic.

---

## 0. Why time is the hardest "simple" problem

Distributed systems use time for four different jobs, and they need different clocks:

| Job | Example | What it needs |
|---|---|---|
| **Ordering** causally related events | Replies after posts; versions of a key | Logical clocks (Lamport/vector/HLC): no physical accuracy needed |
| **Detecting concurrency** | Multi-leader conflicts, siblings | Vector/version clocks |
| **Real-time ordering** across unrelated clients | External consistency (Spanner), "the payment was recorded before the audit started" | Bounded physical uncertainty (TrueTime/ClockBound) plus waiting, or a central sequencer |
| **Durations** | Timeouts, leases, rate limits, TTLs | **Monotonic** local clocks, never wall clocks |

The most common production bug is using the wrong one: wall-clock time for ordering (LWW), or for durations (a lease
computed from `System.currentTimeMillis()` breaks when NTP steps the clock).

---

## 1. Physical clocks and why they lie

### 1.1 Drift, skew, steps

- **Drift.** Quartz oscillators run 10–100 ppm off nominal and vary with temperature. From §E of the output:
  - 50 ppm is **4.32 s/day**.
  - Two clocks at ±50 ppm stay within 1 ms of each other only if resynced every **10 s**.
- **Skew** is the instantaneous difference between two clocks.
- **NTP slews** small offsets: it speeds up or slows down the clock, typically by at most 500 ppm. It **steps**
  large ones: the clock jumps, possibly backwards. Code that measures intervals with the wall clock sees negative or
  huge durations.
- **Leap seconds.** The classic ones caused outages: the 2012 Linux hrtimer livelock that hit many sites, and
  Cloudflare's 2017 RRDNS bug, when a negative duration panicked Go code. Google and AWS **smear** the leap second
  over ~24 h instead. The CGPM resolved in 2022 to abandon leap seconds by 2035 (⚠ verify the status).
- **VM pauses and migrations** freeze a guest's sense of time and then jump it.

### 1.2 NTP's accuracy limit is path asymmetry

NTP estimates the offset as $\theta = \frac{(t_2 - t_1) + (t_3 - t_4)}{2}$, which assumes equal one-way delays. Any
asymmetry $(d_\text{out} - d_\text{back})/2$ becomes **undetectable offset error**:

| Path out / back | NTP offset error | Bound (RTT/2) |
|---|---|---|
| 10 / 10 ms | 0 | 10 ms |
| 30 / 10 ms | **10 ms** | 20 ms |
| 80 / 5 ms | **37.5 ms** | 42.5 ms |

The error is bounded only by RTT/2. Over the internet, that is tens of milliseconds. In a datacenter with a nearby
stratum-1 server, it is sub-millisecond.

### 1.3 Better time sources

| Source | Typical accuracy (⚠ verify for your environment) | Notes |
|---|---|---|
| Public NTP over WAN | 1–50 ms | Asymmetry-bound |
| Datacenter NTP / chrony to local servers | ~0.1–1 ms | Good enough for logs, not for ordering |
| **PTP (IEEE 1588)** with hardware timestamping | ~µs to sub-µs | Meta deployed PTP fleet-wide (2022). AWS Time Sync Service offers µs-level accuracy via PTP hardware clocks on supported instances |
| GPS + atomic references (Spanner time masters) | ε ≈ 1–7 ms in 2012; much tighter later | The cost is infrastructure plus a bound you can *trust* |
| **ClockBound** (AWS) | Exposes [earliest, latest] like TrueTime | Makes commit-wait designs possible outside Google |

**What matters is the bound, not the precision.** A clock that is usually within 100 µs but occasionally off by 2 s,
undetected, is useless for correctness. A clock with a *guaranteed* 1 ms bound is gold.

---

## 2. Lamport clocks (1978)

**Rules:**
- Increment before each event.
- Attach the counter to each sent message.
- On receive, set `L = max(L, L_msg) + 1`.

**Guarantee:** if a → b (happens-before), then L(a) < L(b). Ties broken by process ID give a **total order consistent
with causality**. That is enough for mutual-exclusion algorithms and for totally ordered logs.

**The limit:** L(a) < L(b) does *not* imply a → b. Lamport clocks cannot detect concurrency. In the lab, they impose
an order on **93.8%** of truly concurrent pairs. Those orders mean nothing, and an LWW rule based on them silently
drops one of two concurrent writes.

---

## 3. Vector clocks (Fidge, Mattern 1988)

**Rules:**
- Each process keeps a vector $V[1..n]$. It increments its own entry on each event, and on receive takes the
  element-wise max and then increments.
- $a \to b \iff V(a) < V(b)$: ≤ element-wise, and unequal.
- Two events are **concurrent** iff neither vector dominates.

The lab classifies **all 40,000 sampled pairs exactly** against the ground truth from DAG reachability. Vector clocks
are the only mechanism in the table that can say "concurrent".

**Costs and variants:**
- **Size:** O(n) per event. With thousands of clients, you track **replicas** instead. *Version vectors*, one entry per
  server, tag the versions of a key (Riak, Dynamo).
- **Sibling explosion:** clients writing through different coordinators create false concurrency. *Dotted version
  vectors* fix it (Folder 02 file 02 §4.3).
- **Pruning:** dropping old entries can create false conflicts or lose causality. Bound it by entry count *and* age,
  and accept occasional spurious siblings.

---

## 4. Hybrid Logical Clocks (Kulkarni, Demirbas et al., 2014)

HLC keeps **(l, c)**: $l$ is the maximum physical time seen, and $c$ is a logical counter.

```
send/local event:   l' = max(l, pt);  c = (l' == l) ? c + 1 : 0;  l = l'
receive (lm, cm):   l' = max(l, lm, pt)
                    c = l'==l==lm ? max(c, cm)+1 : l'==l ? c+1 : l'==lm ? cm+1 : 0
                    l = l'
```

**Properties:**
1. a → b ⇒ HLC(a) < HLC(b), like Lamport.
2. $l$ stays within the clock skew ε of physical time, so HLC timestamps are *close to real time*. That makes them
   usable for snapshot reads "as of 10:05:00" and for TTLs.
3. It fits in 64 bits (e.g. 48 bits of physical ms + 16 bits of counter). This is the timestamp CockroachDB,
   YugabyteDB and MongoDB's cluster time use.

The lab measured three skew settings:

| Clock skew / drift | Messages whose receive is stamped *before* the send (wall clock) | Close event pairs wall-clock inverted | Lamport inversions | HLC inversions | Vector-clock errors | max(l − pt) | max c |
|---|---|---|---|---|---|---|---|
| 1 ms / 20 ppm | 0.00% | 0.00% | 0 | 0 | 0 | 0.00 ms | 0 |
| 10 ms / 50 ppm | **3.22%** | 0.85% | 0 | 0 | 0 | 12.96 ms | 6 |
| 50 ms / 100 ppm | **33.69%** | 3.62% | 0 | 0 | 0 | 71.05 ms | 17 |

- **Wall-clock ordering breaks causality in proportion to skew ÷ message delay.** At 50 ms of skew, a third of all
  replies are stamped before their requests. Any "sort by timestamp" (logs, LWW, event sourcing) shows effects before
  causes.
- **HLC never inverts**, and its $l$ stays within the measured clock spread: 12.96 ms against 14.6 ms of spread at
  10 ms skew.
- **HLC is not TrueTime.** It does not tell you the *uncertainty* of real time, so it cannot give external
  consistency across unrelated clients. Systems layer an **uncertainty interval** (max offset) on top and pay with
  read restarts (Folder 02 file 04 §2.2). Or they enforce bounded skew by **self-fencing** nodes whose clocks drift
  out of bounds.
- **A node with a wildly fast clock drags everyone's $l$ forward.** HLC implementations reject or clamp remote
  timestamps more than max-offset ahead of local physical time. Otherwise one bad clock poisons the cluster's
  timestamps "forever" (until physical time catches up).

---

## 5. TrueTime and the commit-wait family

Folder 02 file 04 §1 derived it: with `TT.now() = [earliest, latest]` and a guaranteed bound ε, assign s =
`latest`, then **wait until `TT.after(s)`** before acknowledging. Every transaction that starts later, anywhere, gets
a larger timestamp. Strict serializability costs ≈ 2ε of latency, partly hidden behind replication.

The **design space for real-time order**:

| Approach | Coordination | Latency cost | Failure mode |
|---|---|---|---|
| TrueTime / ClockBound commit wait | None between unrelated txns | 2ε per write | Clock-bound violation breaks safety, so the bound must be trustworthy |
| Central sequencer / TSO (Percolator, TiDB) | 1 RTT to the oracle | RTT to the TSO (high cross-region) | The TSO is an availability-critical single point; batch allocation helps |
| HLC + uncertainty restarts (CockroachDB) | None | Restarts ∝ write rate × max_offset | Not strict across unrelated keys; nodes self-fence on skew |
| Lamport/HLC alone | None | 0 | No real-time guarantee |

---

## 6. Ordering in practice: patterns

- **Per-entity sequence numbers from the entity's owner** (partition leader): chat messages per conversation, ledger
  entries per account. They are total within the entity, need no clocks, and are the most common correct answer in
  interviews.
- **Snowflake-style IDs** (Folder 06 problem 6): time-ordered *roughly*. Ordering across generators is only as good as
  clock sync. They are never a causality mechanism.
- **Event-sourcing logs:** order by log offset (single writer per stream), never by event wall-clock timestamps. Keep
  event time as data for business logic and windowing; watermarks handle lateness. The companion Dataflow/Flink KB
  covers this.
- **Leases and timeouts:** use monotonic clocks (`CLOCK_MONOTONIC`, `System.nanoTime()`). Add a safety margin for
  drift: the lease holder assumes the lease ends earlier, the grantor that it ends later. Use **fencing tokens**
  (file 03) for anything that must be correct when a pause outlasts the margin.

---

## 7. The listing

```python
"""clocks_lab.py - physical clocks vs Lamport, vector and hybrid logical clocks on one message history (Folder 03, file 02).

Four processes with skewed, drifting quartz clocks exchange messages. Ground truth happens-before is computed
exactly from the event DAG (ancestor bitsets). Then:
  A. wall-clock timestamps: how often an effect is stamped BEFORE its cause
  B. Lamport clocks: never inverted, but cannot tell concurrent from ordered
  C. vector clocks: classify every sampled pair exactly
  D. hybrid logical clocks (Kulkarni et al. 2014): never inverted, stay within the skew bound of physical time
  E. NTP's asymmetry error and drift arithmetic
Standard library only; seeded, deterministic.
"""
import random

N = 4


def simulate(events: int, skew_ms: float, drift_ppm: float, seed: int = 9):
    rng = random.Random(seed)
    offset = [rng.uniform(-skew_ms, skew_ms) for _ in range(N)]
    drift = [rng.uniform(-drift_ppm, drift_ppm) * 1e-6 for _ in range(N)]
    pt = lambda p, t: t * (1 + drift[p]) + offset[p]        # local physical clock reading at true time t
    t_now = [0.0] * N
    lam = [0] * N
    vc = [[0] * N for _ in range(N)]
    hlc = [(0.0, 0)] * N
    in_flight: list = []                                    # (arrival true time, dst, src event id, lam, vc, hlc)
    ev = []                                                 # per event: dict
    anc: list[int] = []                                     # ancestor bitset per event (exact happens-before)
    last_on = [-1] * N
    edges: list = []                                        # (send event, receive event)
    for i in range(events):
        p = rng.randrange(N)
        t_now[p] += rng.uniform(0.5, 5.0)
        msg = None
        deliverable = [m for m in in_flight if m[1] == p and m[0] <= t_now[p]]
        if deliverable and rng.random() < 0.7:
            msg = min(deliverable)
            in_flight.remove(msg)
            t_now[p] = max(t_now[p], msg[0])
        t = t_now[p]
        phys = pt(p, t)
        bits = (anc[last_on[p]] | 1 << last_on[p]) if last_on[p] >= 0 else 0
        if msg:
            _, _, src, m_lam, m_vc, m_hlc = msg
            bits |= anc[src] | 1 << src
            edges.append((src, i))
            lam[p] = max(lam[p], m_lam) + 1
            vc[p] = [max(a, b) for a, b in zip(vc[p], m_vc)]
            l_old, c_old = hlc[p]
            l = max(l_old, m_hlc[0], phys)
            c = (max(c_old, m_hlc[1]) + 1 if l == l_old == m_hlc[0] else
                 c_old + 1 if l == l_old else m_hlc[1] + 1 if l == m_hlc[0] else 0)
            hlc[p] = (l, c)
        else:
            lam[p] += 1
            l_old, c_old = hlc[p]
            l = max(l_old, phys)
            hlc[p] = (l, c_old + 1 if l == l_old else 0)
        vc[p] = vc[p][:]
        vc[p][p] += 1
        ev.append({"p": p, "true": t, "wall": phys, "lam": lam[p], "vc": vc[p][:], "hlc": hlc[p]})
        anc.append(bits)
        last_on[p] = i
        if rng.random() < 0.5:                              # send a message from this event
            dst = rng.choice([q for q in range(N) if q != p])
            in_flight.append((t + rng.uniform(1, 20), dst, i, lam[p], vc[p][:], hlc[p]))
    return ev, anc, offset, edges


def vc_rel(a: list, b: list) -> str:
    if a == b:
        return "eq"
    if all(x <= y for x, y in zip(a, b)):
        return "before"
    if all(x >= y for x, y in zip(a, b)):
        return "after"
    return "concurrent"


def analyze(ev, anc, edges, pairs: int, rng: random.Random) -> dict:
    """Samples pairs of events CLOSE in true time (within 20 positions in true-time order), where skew matters."""
    hb_pairs = inverted_wall = inverted_lam = inverted_hlc = conc = vc_wrong = lam_orders_conc = 0
    by_time = sorted(range(len(ev)), key=lambda k: ev[k]["true"])
    for _ in range(pairs):
        k = rng.randrange(len(by_time) - 20)
        i, j = sorted((by_time[k], by_time[k + rng.randint(1, 20)]))
        a, b = ev[i], ev[j]
        i_before_j = bool(anc[j] >> i & 1)                  # exact ground truth
        truth = "before" if i_before_j else "concurrent"
        vc_wrong += vc_rel(a["vc"], b["vc"]) != truth
        if i_before_j:
            hb_pairs += 1
            inverted_wall += a["wall"] >= b["wall"]
            inverted_lam += a["lam"] >= b["lam"]
            inverted_hlc += a["hlc"] >= b["hlc"]
        else:
            conc += 1
            lam_orders_conc += a["lam"] != b["lam"]         # Lamport imposes an order that means nothing
    drift = max(e["hlc"][0] - e["wall"] for e in ev)
    msg_inv = sum(ev[a]["wall"] >= ev[b]["wall"] for a, b in edges) / len(edges)
    return {"msg_inv": msg_inv, "msgs": len(edges), "hb": hb_pairs, "conc": conc, "wall_inv": inverted_wall / hb_pairs, "lam_inv": inverted_lam,
            "hlc_inv": inverted_hlc, "vc_wrong": vc_wrong, "lam_orders_conc": lam_orders_conc / conc,
            "hlc_minus_pt_max": drift, "hlc_c_max": max(e["hlc"][1] for e in ev)}


def main() -> None:
    rng = random.Random(1978)
    print("pairs = 40,000 samples of events close in true time; 'inverted' = cause stamped >= effect")
    print(f"{'skew':>6} {'drift':>6} {'recv<send':>10} {'hb pairs':>9} {'concurrent':>11} {'wall inv':>9} "
          f"{'Lamport inv':>12} {'HLC inv':>8} {'VC errors':>10} {'HLC-pt max':>11} {'HLC c max':>10}")
    res = {}
    for skew, drift in ((1.0, 20), (10.0, 50), (50.0, 100)):
        ev, anc, offs, edges = simulate(3000, skew, drift)
        r = analyze(ev, anc, edges, 40_000, rng)
        r["max_offset_spread"] = max(offs) - min(offs)
        res[skew] = r
        print(f"{skew:>4.0f}ms {drift:>4}pp {r['msg_inv'] * 100:>9.2f}% {r['hb']:>9} {r['conc']:>11} "
              f"{r['wall_inv'] * 100:>8.2f}% "
              f"{r['lam_inv']:>12} {r['hlc_inv']:>8} {r['vc_wrong']:>10} {r['hlc_minus_pt_max']:>9.2f}ms "
              f"{r['hlc_c_max']:>10}")
    r10 = res[10.0]
    print(f"\nLamport clocks put an order on {r10['lam_orders_conc'] * 100:.1f}% of truly concurrent pairs "
          f"(they cannot say 'concurrent'); vector clocks classify all {r10['hb'] + r10['conc']} sampled pairs exactly.")
    print("HLC never inverts causality, and l - pt stays below the clock spread "
          f"({r10['max_offset_spread']:.1f} ms at 10 ms skew).")

    print("\n== E. NTP and drift arithmetic")
    for fwd, back in ((10, 10), (30, 10), (80, 5)):
        print(f"  path {fwd:>2} ms out / {back:>2} ms back: NTP assumes symmetry -> offset error "
              f"{(fwd - back) / 2:5.1f} ms (invisible to NTP; bounded only by RTT/2 = {(fwd + back) / 2:.1f} ms)")
    for ppm in (10, 50, 100):
        print(f"  {ppm:>3} ppm drift = {ppm * 86400 / 1e6:5.2f} s/day; two clocks at +/-{ppm} ppm stay within 1 ms "
              f"only if resynced every {1e-3 / (2 * ppm * 1e-6):5.1f} s")

    for r in res.values():
        assert r["lam_inv"] == 0 and r["hlc_inv"] == 0 and r["vc_wrong"] == 0
        assert r["hlc_minus_pt_max"] <= r["max_offset_spread"] + 1.0
    assert res[1.0]["msg_inv"] < res[10.0]["msg_inv"] < res[50.0]["msg_inv"] and res[10.0]["msg_inv"] > 0.02
    assert res[50.0]["wall_inv"] > res[1.0]["wall_inv"]
    assert r10["lam_orders_conc"] > 0.9
    print("\nself-test: all assertions passed")


if __name__ == "__main__":
    main()
```

Output (verified; deterministic):

```text
pairs = 40,000 samples of events close in true time; 'inverted' = cause stamped >= effect
  skew  drift  recv<send  hb pairs  concurrent  wall inv  Lamport inv  HLC inv  VC errors  HLC-pt max  HLC c max
   1ms   20pp      0.00%     10221       29779     0.00%            0        0          0      0.00ms          0
  10ms   50pp      3.22%     10130       29870     0.85%            0        0          0     12.96ms          6
  50ms  100pp     33.69%     10267       29733     3.62%            0        0          0     71.05ms         17

Lamport clocks put an order on 93.8% of truly concurrent pairs (they cannot say 'concurrent'); vector clocks classify all 40000 sampled pairs exactly.
HLC never inverts causality, and l - pt stays below the clock spread (14.6 ms at 10 ms skew).

== E. NTP and drift arithmetic
  path 10 ms out / 10 ms back: NTP assumes symmetry -> offset error   0.0 ms (invisible to NTP; bounded only by RTT/2 = 10.0 ms)
  path 30 ms out / 10 ms back: NTP assumes symmetry -> offset error  10.0 ms (invisible to NTP; bounded only by RTT/2 = 20.0 ms)
  path 80 ms out /  5 ms back: NTP assumes symmetry -> offset error  37.5 ms (invisible to NTP; bounded only by RTT/2 = 42.5 ms)
   10 ppm drift =  0.86 s/day; two clocks at +/-10 ppm stay within 1 ms only if resynced every  50.0 s
   50 ppm drift =  4.32 s/day; two clocks at +/-50 ppm stay within 1 ms only if resynced every  10.0 s
  100 ppm drift =  8.64 s/day; two clocks at +/-100 ppm stay within 1 ms only if resynced every   5.0 s

self-test: all assertions passed
```

---

## 8. L5 vs L6 vs L7

| Topic | L5 (Senior) | L6 (Staff) | L7 (Principal) |
|---|---|---|---|
| Physical time | "Servers use NTP" | Drift, steps vs slews, leap smearing; monotonic clocks for durations | NTP asymmetry error; bound vs precision; PTP/ClockBound; time as infrastructure with an SLO and alerts on offset |
| Ordering | "Sort by timestamp" | Lamport for causal order; per-entity sequence numbers | Picks per requirement: causal (HLC/vector), concurrency detection (version vectors), real-time (commit wait / TSO) and prices each |
| HLC | — | Knows CockroachDB uses it | The (l, c) rules; the bounded-l property; uncertainty restarts; clamping remote timestamps; self-fencing on skew |
| Failure | — | Leap-second incidents | Clock faults as a correctness risk class: fencing tokens for leases, timestamp clamping, detection and quarantine of bad clocks |

---

## 9. Bar-raiser probing chains

### Chain A: "Order user events by their timestamp."

1. **L5:** "Use the server's current time."
2. **Probe:** "Events come from many servers." **L6:** "Skew reorders them; use a per-user sequence from the user's
   partition leader, or HLC."
3. **Probe:** "We also need 'everything before 10:00' snapshots for audit." **L7:**
   - "HLC gives causally consistent snapshots close to real time. Its l stays within skew, so a snapshot at HLC 10:00
     is consistent and off from wall time by at most max-offset."
   - "If auditors need *real-time* guarantees (nothing committed before 10:00 is missing), use commit-wait timestamps
     on ClockBound, or an audit cutoff that waits max-offset past 10:00 before reading."
   - Quantifies: with 10 ms skew, ~3% of messages would be mis-ordered by wall clock.

### Chain B: "Our lease-based leader occasionally has two leaders."

1. **L5:** "Make the lease shorter."
2. **Probe:** "We use 10 s leases and see overlaps." **L6:**
   - "A GC or VM pause longer than the remaining lease means the old leader acts after expiry."
   - "Also check whether lease durations are measured with wall clocks; NTP steps break them."
   - Use monotonic clocks and margins.
3. **Probe:** "Pauses can be 30 s; we can't prevent them." **L7:**
   - "Then leases can't be the safety mechanism, only the liveness mechanism. Every action must carry a **fencing
     token** (lease epoch) that the resource validates."
   - "The lab shows 0 stale writes with fencing vs ~330 per 20k grants without."
   - "Where the resource can't validate tokens, use its own compare-and-set on a version."

### Chain C: "Can we use HLC instead of TrueTime and get the same guarantees?"

1. **L5:** "Yes, HLC is close to physical time."
2. **Probe:** "Same guarantees?" **L6:** "No. HLC gives causal order, not external consistency, because it doesn't
   know the uncertainty."
3. **Probe:** "What exactly do we lose, and how do we compensate?" **L7:**
   - "Real-time order between transactions that never communicate: the causal-reverse anomaly."
   - Compensation:
     - uncertainty intervals with restarts for reads;
     - commit wait for the subset of tables that need strictness;
     - or causality tokens passed between clients that do communicate (session tokens).
   - "The cost is restarts ≈ 1 − e^{−λ·max_offset} on hot keys. Tighter clocks shrink it."

---

## 10. Invariants checklist

- [ ] Durations, timeouts and leases use monotonic clocks plus drift margins.
- [ ] No correctness depends on wall-clock ordering across machines; LWW on wall clocks is restricted to loss-tolerant
      data.
- [ ] Causal order uses per-entity sequences, Lamport/HLC, or vector clocks as required; concurrency detection uses
      version vectors.
- [ ] Real-time guarantees come from a trustworthy bound (commit wait) or a sequencer, with the latency priced.
- [ ] HLC implementations clamp remote timestamps and self-fence on offset violations.
- [ ] Clock offset is monitored as an SLI; leap seconds are smeared; NTP/PTP sources are redundant.

---

## 11. References

- L. Lamport. *Time, Clocks, and the Ordering of Events in a Distributed System.* CACM 21(7), 1978.
- C. Fidge. *Timestamps in Message-Passing Systems that Preserve the Partial Ordering.* ACSC 1988. F. Mattern,
  *Virtual Time and Global States of Distributed Systems*, 1988.
- S. Kulkarni, M. Demirbas, D. Madappa, B. Avva, M. Leone. *Logical Physical Clocks and Consistent Snapshots in
  Globally Distributed Databases.* OPODIS 2014.
- D. Mills. *Internet Time Synchronization: the Network Time Protocol.* IEEE Trans. Comm. 1991. RFC 5905 (NTPv4).
  IEEE 1588 (PTP).
- J. Corbett et al. *Spanner.* OSDI 2012 (TrueTime). K. Marzullo, *Maintaining the Time in a Distributed System*, PhD
  thesis 1984.
- Meta Engineering. *How Precision Time Protocol is being deployed at Meta*, 2022. AWS. *Amazon Time Sync Service*;
  ClockBound (github.com/aws/clock-bound).
- Cloudflare Blog. *How and why the leap second affected Cloudflare DNS*, 2017.
- M. Kleppmann. *Designing Data-Intensive Applications*, ch. 8 (unreliable clocks).
