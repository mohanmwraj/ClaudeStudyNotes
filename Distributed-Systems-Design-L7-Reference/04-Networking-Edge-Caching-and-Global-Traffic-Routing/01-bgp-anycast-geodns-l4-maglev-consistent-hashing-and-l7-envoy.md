# The Global Front Door: BGP Anycast, GeoDNS, L4 Maglev, and L7 Envoy

> **Folder 04 · File 01** of the Distributed Systems & System Design L7 Reference.
> **Prerequisites:**
> - [Folder 01 file 02 §4](../01-First-Principles-Physics-and-L5-L6-L7-Rubric/02-hardware-network-physics-latency-numbers-and-finops-math.md#4-network-physics-light-handshakes-windows-and-packets)
>   (RTTs, handshakes, packet budgets, anycast vs DNS physics);
> - [Folder 02 file 03](../02-Storage-Engines-Replication-and-Sharding-Internals/03-consistent-hashing-bounded-loads-virtual-nodes-and-range-splitting.md)
>   (consistent hashing).
>
> **Listing:** `lb_lab.py` builds a Maglev lookup table (balance and disruption vs mod-N and a ring). It also compares
> request-level policies (random, round-robin, least-outstanding fresh and stale, power-of-two-choices) on a
> heterogeneous fleet. The output is deterministic.

---

## 0. The layers between a user and your service

```
 user ──DNS──► resolver ──► authoritative DNS (GeoDNS / steering)       which PoP / region?
   │
   └──TCP/QUIC──► anycast VIP (same IP announced from many PoPs via BGP)   nearest edge by routing
                    │
                    ▼  ECMP across L4 load balancers (routers hash 5-tuples)
               L4 LB tier (Maglev / Katran / Unimog): consistent hash → backend, connection tracking, encap, DSR
                    │
                    ▼
               L7 proxy tier (Envoy / GFE / ALB): TLS, HTTP routing, retries, circuit breaking, LB per request
                    │
                    ▼  service mesh / internal LB (often Envoy again)
               services
```

Each layer has a **control plane**:
- BGP announcements;
- DNS records and health checks;
- LB backend sets;
- xDS configuration.

Each also has a **data plane** that must keep forwarding when its control plane fails. That is static stability,
Folder 05 file 03. Most famous internet outages are control-plane changes propagated to the data plane.

---

## 1. BGP and anycast

### 1.1 Mechanics you need

- Networks (autonomous systems, ASes) **announce IP prefixes** to their neighbors. Each router picks a best path by
  policy, then AS-path length, then other tie-breakers, and re-announces it.
- **Anycast** announces the *same* prefix from many locations. Each user's packets go to whichever announcement their
  ISP's routing prefers, called that PoP's **catchment**.
- The smallest prefix generally accepted on the global IPv4 internet is a **/24**, so anycast and traffic engineering
  operate in /24 units.
- **Traffic engineering knobs:**
  - AS-path prepending makes a PoP look farther away;
  - BGP communities tell neighbors how to propagate;
  - MED;
  - selectively withdrawing an announcement from overloaded PoPs.

### 1.2 Anycast's strengths and its traps

| Strength | Trap |
|---|---|
| Nearest-ish PoP with zero client logic | "Nearest by BGP" ≠ nearest by latency: AS-path length ignores geography |
| Natural DDoS absorption: attack traffic is spread over every PoP's capacity | Coarse control: you move whole catchments, not users |
| Fast failover: withdraw the route and traffic shifts in seconds to minutes | Route changes mid-connection can send a TCP flow's packets to a PoP with no state for it (rare; QUIC connection IDs and consistent L4 hashing across PoPs mitigate) |
| The standard for DNS, CDNs, and public resolvers like 1.1.1.1 / 8.8.8.8 | **BGP is a global control plane you don't own**: route leaks and hijacks can redirect your traffic |

Two outages every L7 should be able to narrate:

- **Route leak, June 2019.** A small ISP leaked thousands of more-specific routes, including Cloudflare's, to a
  transit provider that propagated them. Traffic for major services was funneled through a tiny network for hours.
  Defenses:
  - RPKI route origin validation (ROV);
  - max-prefix limits;
  - IRR filtering by transit providers.
- **Facebook, October 4, 2021.**
  - A maintenance command on the backbone disconnected the datacenters.
  - Facebook's DNS servers are designed to **withdraw their own anycast BGP announcements** when they can't reach the
    datacenters. They did, so facebook.com stopped resolving worldwide.
  - The tools to fix it depended on the same network, and physical access was slowed by security systems that
    depended on it too.
  - Lessons:
    - a health-check-driven *withdrawal* is a control-plane action with global blast radius;
    - break-glass paths must not share fate with the thing they fix.

---

## 2. DNS-based steering (GeoDNS)

The authoritative DNS answers differently per query. The inputs are:
- the resolver's IP;
- or, better, the **client subnet** via EDNS Client Subnet (ECS, RFC 7871);
- plus health, capacity and cost.

| Design choice | Trade-off |
|---|---|
| TTL 30–60 s | Faster steering and failover, more DNS QPS. Many resolvers and clients ignore low TTLs (JVMs historically cached forever) |
| TTL 300+ s | Cheaper and stable, slow failover |
| ECS on | Accurate mapping for users of distant public resolvers; less cacheable, privacy concerns |
| Answer with multiple A/AAAA records | Client-side failover, but clients choose poorly (often the first) |
| Weighted / latency-based / geoproximity records (Route 53, NS1, Cloudflare) | Capacity-aware steering; needs health checks with their own reliability |

**DNS is the slowest failover mechanism you have.** It is fine for region evacuation over minutes. It is not fine for
sub-minute recovery, which needs anycast plus L4 changes.

**Health-check fail-open:** if *all* targets look unhealthy, which often means the checker itself is broken, return
all of them rather than none. Route 53 behaves this way (⚠ verify). The same principle applies to every LB's health
checking.

---

## 3. L4 load balancing: ECMP, Maglev, connection tracking

### 3.1 The problem

Routers spread packets for a VIP across L4 LB machines with **ECMP** (equal-cost multi-path, a hash of the 5-tuple).
When an LB machine is added or removed, ECMP rehashes, and **packets of existing connections land on a different LB**.
That LB must send them to the *same backend* as before, or the connection breaks. So L4 LBs need:

1. **Consistent hashing** of the 5-tuple to a backend that all LB machines agree on without coordination;
2. **Connection tracking** per LB, to keep existing flows pinned even when the backend set changes.

Maglev (Eisenbud et al., NSDI 2016), Google's software L4 LB, solves (1) with a lookup table of prime size M
(65,537) that every LB computes identically from the backend list.

### 3.2 Maglev table population

```
for each backend i: offset_i = h1(name_i) mod M,  skip_i = h2(name_i) mod (M−1) + 1
permutation_i[j] = (offset_i + j·skip_i) mod M        # a full permutation of 0..M−1 because M is prime
fill: backends take turns; each claims the next slot in its own permutation that is still empty
lookup(packet) = table[hash(5-tuple) mod M]          # O(1)
```

§A of the output:

| N backends | Max/min table share | Flows moved when 1 is removed | …of which moved needlessly | mod-N moved | Ring (100 vnodes) moved | Ideal |
|---|---|---|---|---|---|---|
| 10 | **1.000** | 10.21% | **0.21%** | 90.05% | 10.35% | 10% |
| 100 | 1.002 | 1.68% | 0.64% | 99.02% | 0.95% | 1% |

- **Maglev's design point is near-perfect balance with O(1) lookup.** Shares differ by < 0.2%, against the ring's
  ±6–17% at reasonable vnode counts (Folder 02 file 03 §2).
- The price is a **small amount of extra disruption**. Removing 1 of 100 backends moves 1.68% of flows vs the ideal
  1%, so 0.64% are needless. Connection tracking covers that gap for existing flows.
- Other production L4 LBs:
  - Meta's **Katran** and Cloudflare's **Unimog** use XDP/eBPF (Folder 01 file 02 §4.7).
  - **Direct Server Return** (DSR): backends reply directly to clients, bypassing the LB. The LB handles only the
    (small) inbound direction.
  - **Encapsulation** (GRE/GUE/IPIP) carries the original VIP to the backend.

### 3.3 Health checking at L4

- LBs probe backends and remove failing ones. Remove them **gradually** (drain), and **cap the fraction removable at
  once**.
- If 50% of backends "fail" simultaneously, the checker or a dependency is more likely broken than the backends.
  Removing them all concentrates the full load on the survivors and turns a gray failure into a total one.
- This **panic threshold** idea is built into Envoy (healthy panic threshold, default 50%, ⚠ verify).

---

## 4. L7 proxies: Envoy as the reference architecture

### 4.1 Data plane vs control plane

```
            control plane (Istio / custom xDS server)
                 │  LDS listeners, RDS routes, CDS clusters, EDS endpoints, SDS secrets (gRPC streams)
                 ▼
 ┌──────────────────────────── Envoy (data plane) ─────────────────────────────┐
 │ listener → filter chain (TLS, HTTP conn manager → router filter)           │
 │   route match → cluster → LB policy picks endpoint → connection pool       │
 │   retries / timeouts / hedging · circuit breakers · outlier detection      │
 │   stats, access logs, tracing headers                                      │
 └──────────────────────────────────────────────────────────────────────────────┘
 if the xDS server dies: Envoy keeps serving with its LAST config (static stability); new changes wait
```

### 4.2 Per-request load balancing

§B of the output: 20 servers at 80% aggregate load. 5 are half-speed (older SKU) and one is degraded to 0.2×.

| Policy | Mean | p99 | p99.9 | Why |
|---|---|---|---|---|
| Random | **unstable** (9.3 s and growing) | 169 s | 202 s | Slow servers receive 1/20 of traffic each, above their capacity; their queues grow without bound |
| Round-robin | **unstable** (8.9 s) | 166 s | 204 s | Same: load-oblivious |
| Least-outstanding, fresh global view | 14.4 ms | 83 ms | 170 ms | The ideal: needs global, instant state |
| Least-outstanding, 50 ms stale view | 82.4 ms | 513 ms | 1,198 ms | **Herding**: every request goes to whichever server *looked* emptiest |
| **P2C, fresh** | 29.3 ms | 169 ms | 376 ms | Two random candidates, pick the less loaded |
| **P2C, 50 ms stale** | 42.2 ms | 254 ms | 544 ms | **Robust to staleness**: randomization prevents herding |

Lessons:

1. **Load-oblivious balancing is not "a bit worse". It is unstable on a heterogeneous fleet.** Every real fleet is
   heterogeneous: mixed SKUs, noisy neighbors, GC.
2. **"Pick the least loaded" with stale information is a herding machine.** It's the same pathology as all clients
   retrying at the same instant. Envoy's `LEAST_REQUEST` uses **P2C** by default for this reason.
3. **The theory:** with $n$ servers, random assignment gives a maximum load of $\Theta(\ln n / \ln\ln n)$ above the
   mean, and the power of two choices gives $\Theta(\ln\ln n / \ln 2)$, an exponential improvement (Azar et al. 1994;
   Mitzenmacher 2001).

### 4.3 Resilience features and their defaults (⚠ verify for your Envoy version)

| Feature | Mechanism | Design note |
|---|---|---|
| Timeouts | Route timeout, per-try timeout, idle timeouts | Per-try < overall; propagate deadlines downstream (gRPC `grpc-timeout`) |
| Retries | `retry_on` conditions, `num_retries`, backoff with jitter | Retry only idempotent requests and retryable errors |
| **Retry budget** | Retries capped at a percentage of active requests (20% default when enabled, with a minimum concurrency) | Prevents retry amplification (Folder 05 file 02) |
| Circuit breakers | Max connections, pending requests, requests, retries per cluster | Not the Hystrix pattern: these are concurrency caps that shed load immediately |
| Outlier detection | Eject hosts on consecutive 5xx, success-rate or latency outliers; max ejection % | Ejection caps prevent ejecting the fleet |
| Hedging | Send a second request after a delay | Only idempotent; budget it (Folder 01 file 01 §6.4) |
| Zone-aware routing | Prefer same-zone endpoints with spillover | Cuts cross-AZ cost and latency (Folder 01 file 02 §7.4) |
| Locality-weighted LB / priority failover | Spill to other localities when healthy capacity drops | Drives regional failover at L7 |

### 4.4 Long-lived connections break request balancing

HTTP/2 and gRPC multiplex many requests over a few long-lived connections. Two consequences:
- **L4 balancing distributes connections, not requests.** New backends get no traffic until clients reconnect.
- After a deploy, the oldest backends hold most connections.

The fixes:
- L7 balancing per request (a proxy or a client-side LB, gRPC `round_robin`/xDS);
- `max_connection_age` to force periodic reconnection;
- connection pools sized to many backends.

---

## 5. Global traffic management: putting it together

| Requirement | Mechanism |
|---|---|
| Nearest edge for every user | Anycast VIPs at PoPs |
| Region choice by capacity/cost/compliance | DNS steering and/or the edge → origin L7 routing table |
| Region evacuation in < 1 min | Edge L7 routing change (data-plane config pushed in seconds), **not** DNS |
| Overload spillover | Capacity-aware global LB: fill the nearest region to its target utilization, overflow to the next. Google's GSLB / Maglev papers describe this "waterfall" |
| Survive control-plane loss | Every layer serves its last-known-good config; routing changes are validated and staged |

---

## 6. The listing

```python
"""lb_lab.py - L4 Maglev hashing and L7 load-balancing policies, measured (Folder 04, file 01).

  A. Maglev lookup table (Eisenbud et al., NSDI 2016): balance across backends and disruption when one backend is
     removed, vs mod-N and a hash ring.
  B. Request-level policies on 20 heterogeneous servers at 80% load: random, round-robin, least-outstanding with
     fresh and with stale (50 ms) load info, and power-of-two-choices (P2C).
Standard library only; seeded, deterministic.
"""
import bisect
import collections
import hashlib
import random

M = 65_537                                                  # Maglev table size: prime, >> number of backends


def h(s: str, salt: str) -> int:
    return int.from_bytes(hashlib.blake2b((salt + s).encode(), digest_size=8).digest(), "big")


def maglev_table(backends: list[str]) -> list[str]:
    """Each backend walks its own permutation (offset + j * skip) mod M; backends take turns claiming the next free
    slot of their permutation until the table is full -> near-equal shares, minimal disruption."""
    perm = [(h(b, "off") % M, h(b, "skip") % (M - 1) + 1) for b in backends]
    nxt = [0] * len(backends)
    table: list = [None] * M
    filled = 0
    while True:
        for i, (off, skip) in enumerate(perm):
            c = (off + nxt[i] * skip) % M
            while table[c] is not None:
                nxt[i] += 1
                c = (off + nxt[i] * skip) % M
            table[c] = backends[i]
            nxt[i] += 1
            filled += 1
            if filled == M:
                return table


def ring_owner(backends: list[str], vnodes: int = 100):
    pts = sorted((h(f"{b}#{v}", "ring"), b) for b in backends for v in range(vnodes))
    keys = [p for p, _ in pts]
    return lambda x: pts[bisect.bisect_right(keys, x) % len(pts)][1]


def maglev_experiment(n: int) -> dict:
    backends = [f"be{i}" for i in range(n)]
    t1 = maglev_table(backends)
    share = collections.Counter(t1)
    t2 = maglev_table(backends[:-1])                        # remove the last backend
    flows = [h(str(i), "flow") for i in range(200_000)]
    mg = [t1[f % M] != t2[f % M] for f in flows]
    unnecessary = sum(1 for f, moved in zip(flows, mg) if moved and t1[f % M] != backends[-1]) / len(flows)
    modn = sum(1 for f in flows if f % n != f % (n - 1)) / len(flows)
    r1, r2 = ring_owner(backends), ring_owner(backends[:-1])
    ring = sum(1 for f in flows[:50_000] if r1(f) != r2(f)) / 50_000
    return {"max_over_min": max(share.values()) / min(share.values()), "moved": sum(mg) / len(flows),
            "unnecessary": unnecessary, "modn": modn, "ring": ring, "ideal": 1 / n}


def lb_sim(policy: str, n: int = 20, load: float = 0.8, reqs: int = 120_000, stale_ms: float = 0.0,
           seed: int = 5) -> dict:
    rng = random.Random(seed)
    speed = [1.0] * n
    for i in range(n // 4):
        speed[i] = 0.5                                       # a quarter of the fleet is an older, 2x slower SKU
    speed[n - 1] = 0.2                                       # one degraded host (noisy neighbour, failing disk)
    mean_service = 10.0                                      # ms at speed 1.0
    capacity = sum(speed) / mean_service                     # requests per ms
    rate = load * capacity
    busy_until = [0.0] * n
    finishes: list[collections.deque] = [collections.deque() for _ in range(n)]
    snapshot, snap_at = [0] * n, -1e9
    rr = 0
    t = 0.0
    lat = []

    def outstanding(i: int) -> int:
        q = finishes[i]
        while q and q[0] <= t:
            q.popleft()
        return len(q)

    for _ in range(reqs):
        t += rng.expovariate(rate)
        if stale_ms and t - snap_at >= stale_ms:
            snapshot, snap_at = [outstanding(i) for i in range(n)], t
        view = snapshot if stale_ms else None
        if policy == "random":
            s = rng.randrange(n)
        elif policy == "round-robin":
            s, rr = rr, (rr + 1) % n
        elif policy == "least-outstanding":
            loads = view if view else [outstanding(i) for i in range(n)]
            best = min(loads)
            s = rng.choice([i for i in range(n) if loads[i] == best])
        else:                                                # power of two choices
            a, b = rng.sample(range(n), 2)
            la = view[a] if view else outstanding(a)
            lb = view[b] if view else outstanding(b)
            s = a if la <= lb else b
        svc = rng.expovariate(1 / (mean_service / speed[s]))
        start = max(t, busy_until[s])
        busy_until[s] = start + svc
        finishes[s].append(busy_until[s])
        lat.append(busy_until[s] - t)
    lat.sort()
    return {"mean": sum(lat) / len(lat), "p99": lat[int(len(lat) * 0.99)], "p999": lat[int(len(lat) * 0.999)]}


def main() -> None:
    print("== A. Maglev table (M = 65,537) vs mod-N vs ring when 1 of N backends is removed")
    print(f"{'N':>4} {'max/min share':>14} {'flows moved':>12} {'moved needlessly':>17} {'mod-N moved':>12} "
          f"{'ring moved':>11} {'ideal 1/N':>10}")
    mg = {}
    for n in (10, 100):
        r = maglev_experiment(n)
        mg[n] = r
        print(f"{n:>4} {r['max_over_min']:>14.3f} {r['moved'] * 100:>11.2f}% {r['unnecessary'] * 100:>16.2f}% "
              f"{r['modn'] * 100:>11.2f}% {r['ring'] * 100:>10.2f}% {r['ideal'] * 100:>9.2f}%")

    print("\n== B. 20 servers (5 at half speed, 1 at 0.2x), 80% load, 120k requests, latency in ms")
    print(f"{'policy':<34} {'mean':>7} {'p99':>8} {'p99.9':>8}")
    pol = {}
    for label, p, stale in (("random", "random", 0), ("round-robin", "round-robin", 0),
                            ("least-outstanding (fresh, global)", "least-outstanding", 0),
                            ("least-outstanding (50 ms stale)", "least-outstanding", 50),
                            ("P2C (fresh)", "p2c", 0), ("P2C (50 ms stale)", "p2c", 50)):
        r = lb_sim(p, stale_ms=stale)
        pol[label] = r
        print(f"{label:<34} {r['mean']:>7.1f} {r['p99']:>8.1f} {r['p999']:>8.1f}")

    for r in mg.values():
        assert r["max_over_min"] < 1.06 and r["unnecessary"] < 0.03 and r["modn"] > 0.85
    assert pol["P2C (fresh)"]["p99"] < pol["round-robin"]["p99"] / 3
    assert pol["random"]["p99"] > 5 * pol["P2C (fresh)"]["p99"]
    assert pol["least-outstanding (50 ms stale)"]["p99"] > 2 * pol["P2C (50 ms stale)"]["p99"]
    print("\nself-test: all assertions passed")


if __name__ == "__main__":
    main()
```

Output (verified; deterministic):

```text
== A. Maglev table (M = 65,537) vs mod-N vs ring when 1 of N backends is removed
   N  max/min share  flows moved  moved needlessly  mod-N moved  ring moved  ideal 1/N
  10          1.000       10.21%             0.21%       90.05%      10.35%     10.00%
 100          1.002        1.68%             0.64%       99.02%       0.95%      1.00%

== B. 20 servers (5 at half speed, 1 at 0.2x), 80% load, 120k requests, latency in ms
policy                                mean      p99    p99.9
random                              9291.9 168643.3 202041.9
round-robin                         8891.4 166490.9 203650.4
least-outstanding (fresh, global)     14.4     83.4    170.0
least-outstanding (50 ms stale)       82.4    512.5   1197.8
P2C (fresh)                           29.3    168.8    375.8
P2C (50 ms stale)                     42.2    253.9    543.5

self-test: all assertions passed
```

---

## 7. L5 vs L6 vs L7

| Topic | L5 (Senior) | L6 (Staff) | L7 (Principal) |
|---|---|---|---|
| Front door | "DNS → load balancer → servers" | Anycast vs GeoDNS trade-offs; L4 vs L7 roles; TLS termination at the edge | Each layer's control plane vs data plane; failure narratives (route leaks, Facebook 2021); evacuation speed per mechanism |
| L4 | "Use an NLB" | ECMP rehashing, consistent hashing, connection tracking, DSR | Maglev table math (balance vs disruption); kernel-bypass economics; health-check panic thresholds |
| L7 policy | Round-robin | Least-request / P2C, outlier detection, retries with budgets | Proves load-oblivious policies are unstable on heterogeneous fleets; stale-information herding; HTTP/2 connection imbalance |
| Ops | Health checks | Draining, slow start, zone-aware routing | Fail-open health checking, capped ejection, staged config rollout, break-glass paths independent of the network they fix |

---

## 8. Bar-raiser probing chains

### Chain A: "Route users to the closest region."

1. **L5:** "GeoDNS by user location."
2. **Probe:** "A region fails; how fast do users move?" **L6:** "DNS TTL plus resolver caching: minutes, and some
   clients ignore TTLs. Use anycast to edges, with health-checked edge-to-origin routing."
3. **Probe:** "Your health-check system marks all regions unhealthy at once." **L7:**
   - "Fail open: if everything looks down, the checker is the likely fault. Keep serving the last-known-good mapping,
     and page."
   - "Cap how much capacity any automated action can remove per minute."
   - "Health signals come from multiple vantage points, with quorum."
   - "This is how you avoid the Facebook-2021 pattern, where an automated withdrawal amplified a backbone failure into
     a global outage."

### Chain B: "Our gRPC service's new pods get no traffic after scale-out."

1. **L5:** "The load balancer is broken."
2. **Probe:** "It's a TCP load balancer." **L6:** "L4 balances connections, and gRPC keeps them open. Use L7 or
   client-side balancing, or set `max_connection_age`."
3. **Probe:** "We switched to least-request in Envoy and p99 got worse during a GC storm." **L7:**
   - "Check whether it's using stale or aggregated load views. Herding onto 'emptiest' hosts mirrors the stale
     least-outstanding row: p99 513 vs 254 ms with P2C."
   - Use P2C with active-request counts local to each proxy.
   - Enable latency-based outlier ejection with a max-ejection cap.
   - Add slow-start for new hosts (ramp weight over 30–60 s) so cold JITs aren't flooded.

### Chain C: "Design the L4 load balancer for 10 Tbps of traffic."

1. **L5:** "Use hardware load balancers."
2. **Probe:** "We want commodity servers." **L6:** "ECMP to a fleet of software LBs (Maglev/Katran-style), each
   consistently hashing to backends, with DSR so only inbound traffic transits the LBs."
3. **Probe:** "Size it, and handle LB failures without breaking connections." **L7:**
   - "Inbound is typically ≪ outbound for web traffic; with DSR, the LBs carry maybe 1 Tbps."
   - "At ~1 KB average inbound packets, 1 Tbps is ~125 Mpps. With 100 Gbps NICs, that's ≥ 10 hosts by bandwidth, at
     ~12.5 Mpps per host, which is a few XDP cores (10–20 Mpps per core)."
   - "So the tier is NIC-bound, not CPU-bound: ~15 hosts with headroom, plus N+1 per PoP."
   - "Maglev tables are identical on every LB, so ECMP rehashes after an LB failure still map flows to the same
     backend. Only flows whose backend changed (≤ 1–2%) need connection-tracking state, and that state is local."

---

## 9. Invariants checklist

- [ ] Every routing layer's control plane can fail without stopping its data plane (last-known-good config).
- [ ] Automated withdrawals and ejections are capped and fail open; break-glass paths don't share fate.
- [ ] RPKI ROV, max-prefix limits and route monitoring are in place for your prefixes.
- [ ] L4: consistent hashing identical across LBs, connection tracking, DSR where applicable, drained removals.
- [ ] L7: P2C or least-request with local counts; outlier detection with an ejection cap; slow start; retry budgets;
      deadline propagation.
- [ ] Long-lived HTTP/2/gRPC connections are rebalanced (L7 LB, max connection age).
- [ ] Failover speed per mechanism is known: DNS minutes, anycast seconds to minutes, edge L7 seconds.

---

## 10. References

- D. Eisenbud et al. *Maglev: A Fast and Reliable Software Network Load Balancer.* NSDI 2016.
- Y. Azar, A. Broder, A. Karlin, E. Upfal. *Balanced Allocations.* STOC 1994. M. Mitzenmacher, *The Power of Two
  Choices in Randomized Load Balancing*, IEEE TPDS 2001.
- Envoy documentation: load balancing (`LEAST_REQUEST`/P2C, ring hash, Maglev), outlier detection, circuit breaking,
  retry budgets, panic threshold, xDS.
- Meta Engineering. *Open-sourcing Katran, a scalable network load balancer*, 2018. Cloudflare Blog. *Unimog:
  Cloudflare's edge load balancer*, 2020.
- Cloudflare Blog. *How Verizon and a BGP Optimizer Knocked Large Parts of the Internet Offline Today*, June 2019.
- Meta Engineering. *More details about the October 4 outage*, 2021.
- RFC 7871 (EDNS Client Subnet), RFC 6811 (BGP prefix origin validation / RPKI).
- AWS Builders' Library. *Implementing health checks*.
