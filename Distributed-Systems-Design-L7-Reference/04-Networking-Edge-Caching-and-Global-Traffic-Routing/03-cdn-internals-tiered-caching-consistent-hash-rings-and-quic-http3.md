# CDN Internals: Tiered Caching, Consistent-Hash Rings, and QUIC/HTTP/3

> **Folder 04 · File 03** of the Distributed Systems & System Design L7 Reference.
> **Prerequisites:**
> - [file 01](01-bgp-anycast-geodns-l4-maglev-consistent-hashing-and-l7-envoy.md) (anycast, L4/L7);
> - [file 02](02-distributed-caching-tao-lease-tokens-thundering-herds-and-hotkey-salting.md) (stampedes, hot keys);
> - [Folder 01 file 02 §4.3](../01-First-Principles-Physics-and-L5-L6-L7-Rubric/02-hardware-network-physics-latency-numbers-and-finops-math.md#43-handshakes-and-slow-start-why-the-edge-exists)
>   (why edges exist).
>
> **Listing:** `cdn_lab.py` covers:
> - edge topology (random server vs consistent hashing within a PoP vs a regional shield);
> - second-hit admission against one-hit wonders;
> - head-of-line blocking in HTTP/2 over TCP vs HTTP/3 over QUIC.
>
> The output is deterministic.

---

## 0. What a CDN is, physically

A CDN is a hierarchy of caches and TLS terminators placed close to users:

```
 users ──anycast/DNS──► EDGE PoP (city, IXP, or inside an ISP)       100s of PoPs
                          L4 LB → edge servers (RAM + NVMe caches)
                          request → owner server inside the PoP (consistent hash)
                              │ miss
                              ▼
                        REGIONAL TIER / SHIELD (a few large PoPs)     collapses misses from many edges
                              │ miss
                              ▼
                        ORIGIN (your object store / app), ideally behind an origin shield
```

It buys:
- **Latency.** Handshakes and slow start over a short RTT; Folder 01 file 02 §4.3 measured 3–4× for mid-size objects.
- **Origin offload,** which is the FinOps win.
- **Egress cost:** CDN egress is cheaper than cloud internet egress at volume, and ISP-embedded caches avoid transit
  entirely.
- **DDoS absorption.**

---

## 1. Inside a PoP: consistent hashing across servers

If the L4 load balancer sprays requests randomly across a PoP's servers, *every* server caches the same popular
objects. A PoP of 16 servers then has the effective capacity of **one** server. Hashing each object to an **owner
server** inside the PoP makes the PoP's caches **additive**.

§A of the output (4 PoPs × 16 servers × 2k objects each, Zipf 0.8 + 20% one-hit wonders):

| Topology | Edge hit ratio | Shield hit | Origin fetches |
|---|---|---|---|
| Random server per request | 14.0% | — | **86.0%** of requests |
| Consistent hash within the PoP | **35.6%** | — | 64.4% |
| Hash within the PoP + regional shield (64k objects, shared by 4 PoPs) | 35.6% | 28.6% | **35.9%** |

- **Owner hashing raises the edge hit ratio 2.5×** at zero hardware cost.
- **The shield is the second big lever.** Edges in four PoPs miss on the same objects, and the shield collapses those
  misses into one origin fetch, so origin load falls from 64% to 36% of requests. With N PoPs behind a shield, the
  origin sees each object roughly once per shield TTL, not once per PoP.

How production systems implement owner hashing:
- the L4 tier hashes on the URL (Maglev/rendezvous over servers);
- or edge servers forward misses to the owner peer: "cache hierarchy within the PoP", ICP/HTCP historically;
  consistent-hash peering today.

**Hot objects break owner hashing**, because one server owns a viral object. The fixes are the hot-key playbook from
file 02:
- replicate the top objects to all servers in the PoP (detected by request-rate sketches);
- or use bounded-load consistent hashing (Folder 02 file 03 §4).

---

## 2. Cache keys, freshness, and purge

### 2.1 The cache key

The default key is (scheme, host, path, query). Every variation multiplies objects and destroys hit ratios:
- `Vary` headers;
- cookies;
- device classes;
- unnormalized query parameters (`?utm_source=` tracking parameters).

Normalize aggressively: strip tracking parameters, sort query parameters, and `Vary` only on what changes the bytes.

### 2.2 Freshness controls (RFC 9111, RFC 5861)

| Directive | Meaning | Use |
|---|---|---|
| `Cache-Control: max-age=N` | Browser and CDN may cache for N s | Static assets with content-hashed names: a year, `immutable` |
| `s-maxage=N` | CDN-only TTL (overrides max-age for shared caches) | Long at the CDN, short in browsers, plus purge on change |
| `stale-while-revalidate=N` | Serve stale for N s while refreshing in the background | The default for dynamic-but-cacheable content |
| `stale-if-error=N` | Serve stale if the origin errors | **Origin outage protection**: the CDN keeps serving |
| `no-store` / `private` | Never cache / browser only | Personalized responses |

### 2.3 Purge and invalidation

- **Content-addressed URLs** (hash in the filename) make purging unnecessary for static assets. This is the best
  invalidation strategy: never invalidate.
- **Purge by URL, or by tag/surrogate key** (`Surrogate-Key: product-123`) for dynamic content. Fastly reports
  global purges in well under a second (⚠ verify), and others take seconds.
- **Soft purge** marks the object stale rather than evicting it. Combined with stale-while-revalidate, a purge never
  causes a stampede.
- **A purge-all is a self-inflicted origin DDoS.** Gate it, rate-limit it, and pre-warm the shield.

---

## 3. Eviction and admission: the one-hit-wonder problem

A large fraction of objects on real CDNs are requested only once. Akamai has reported roughly three-quarters of
objects as one-hit wonders on some workloads (Maggs & Sitaraman 2015, ⚠ verify the figure). Admitting them evicts
useful objects for nothing.

§B of the output (a 5k-object cache, Zipf 0.9 + 35% one-hit wonders):

| Policy | Hit ratio |
|---|---|
| LRU, admit everything | 28.7% |
| **LRU + admit on second request** (a seen-once filter) | **35.3%** |

That is +23% relative hit ratio from a filter. In production it is a rotating Bloom filter: memory-bounded, aging out
old entries. Modern eviction policies make the same point:

| Policy | Idea | Note |
|---|---|---|
| LRU / CLOCK | Recency | Scan- and one-hit-wonder-vulnerable |
| LFU / TinyLFU (Caffeine; Einziger, Friedman & Manes) | Frequency sketch as the admission filter | Near-optimal on skewed workloads |
| ARC / LIRS | Adaptive recency+frequency | ARC has patent history; LIRS is in some DBs |
| **S3-FIFO** (Yang et al., SOSP 2023) | Small FIFO probation queue + main FIFO + ghost queue | Simple, lock-free-friendly; competitive or better hit ratios; "quick demotion" of one-hit wonders |
| SIEVE (Zhang et al., NSDI 2024) | FIFO with a hand and visited bits | Simpler than LRU, often better |
| Byte-hit vs object-hit optimization | Size-aware admission (AdaptSize, LHD, LRB) | CDNs pay for bytes; small-object hit ratio ≠ byte hit ratio |

---

## 4. Large objects and video

- **Range requests and slicing.** Fetch and cache large objects in fixed slices (e.g. 1–10 MB), so a seek doesn't
  fetch the whole file, and slices of popular content are cached independently.
- **Segmented streaming** (HLS/DASH, Folder 07 problems 16–17) turns video into many small, independently cacheable
  objects. Cacheability is a design input to the media pipeline.
- **Netflix Open Connect:**
  - Netflix places its own caching appliances *inside ISPs and at IXPs*.
  - It **fills them proactively during off-peak hours** with what its popularity models predict will be watched.
  - Peak traffic is served almost entirely from cache with no transit cost.
  - It is the L7 version of a CDN: compute the demand forecast, and move bytes when bandwidth is cheap.

---

## 5. QUIC and HTTP/3

### 5.1 What QUIC changes

| Property | TCP + TLS 1.3 + HTTP/2 | QUIC + HTTP/3 |
|---|---|---|
| Handshake | TCP 1 RTT + TLS 1 RTT | **1 RTT combined; 0-RTT resumption** (replayable: idempotent requests only) |
| Head-of-line blocking | One lost TCP segment stalls *every* stream on the connection | Loss stalls only the affected stream |
| Connection identity | 5-tuple: breaks when the client's IP changes (Wi-Fi → cellular) | **Connection IDs**: migration across networks |
| Implementation | Kernel TCP, mature offloads (TSO/GRO) | Mostly user space: faster evolution, historically more CPU per byte (UDP GSO/GRO and batching narrow the gap) |
| Middleboxes | Universally passed | Some networks block or throttle UDP, so clients race TCP and fall back |
| Header compression | HPACK | QPACK (designed for out-of-order delivery) |

### 5.2 Head-of-line blocking, quantified

§C of the output (10 multiplexed streams, 40 packets per RTT):

| Loss rate | Streams stalled per RTT: HTTP/2 over TCP | HTTP/3 over QUIC |
|---|---|---|
| 0.1% | 3.5% | 0.4% |
| 1% | **30.0%** | 4.0% |
| 2% | 51.2% | 7.8% |
| 5% | 83.9% | 18.6% |

On clean wired networks, the difference is small. **On lossy mobile networks (1–2% loss), HTTP/2 stalls a third to a
half of in-flight streams every round trip,** and QUIC removes most of that. Combined with connection migration and
0-RTT, that is why HTTP/3 matters most for mobile apps and video start-up times, and why its benefits show up in
tail latency (p95/p99), not in medians.

### 5.3 Operational notes

- QUIC load balancing must route by **connection ID**, not 5-tuple: QUIC-LB, RFC drafts (⚠ verify the status). This
  is so migrated connections still reach the same server.
- UDP at scale needs the kernel tuned: socket buffers, GSO/GRO, and `SO_REUSEPORT` with eBPF steering.
- Keep TCP+TLS as the fallback, and measure the HTTP/3 success rate per network.

---

## 6. Edge compute and edge data

- **Edge functions** (Workers, Lambda@Edge, Compute@Edge) run code at the PoP: auth checks, A/B assignment,
  personalization of cached shells, redirects (the URL shortener in Folder 01 file 01 §7).
- **Edge KV stores** are typically **eventually consistent** with propagation in seconds to a minute (⚠ verify per
  provider). Design for read-mostly data, and keep read-your-writes paths at the origin.
- **Durable, strongly consistent edge state** exists in some offerings (e.g. per-object single-location actors). Each
  object lives in *one* location, so latency is low only for users near it. The physics from Folder 01 still applies.

---

## 7. Security at the edge

| Concern | Mechanism |
|---|---|
| L3/L4 DDoS | Anycast spreading; XDP drop at the NIC; SYN cookies; upstream scrubbing |
| L7 DDoS | Rate limiting per client/key at the edge; challenges; request-cost-aware shedding |
| TLS keys | Certificates automated (ACME); "keyless" designs keep private keys at the customer, with the edge calling out for signatures |
| Cache poisoning | Normalize keys; never cache on unkeyed headers that change responses; `Vary` correctly |
| Origin exposure | Allow-list CDN IPs or authenticate edge → origin (mTLS, signed headers); never expose the origin directly |

---

## 8. The listing

```python
"""cdn_lab.py - CDN cache topology, admission, and head-of-line blocking (Folder 04, file 03).

  A. One PoP with 16 edge servers: random server per request (every server caches everything) vs consistent
     hashing inside the PoP (each object has one owner), then a regional shield tier shared by 4 PoPs.
  B. One-hit wonders: LRU vs "cache on second request" admission (a seen-once filter) for a small cache.
  C. Head-of-line blocking: with loss rate p, the fraction of multiplexed streams stalled per round trip on one TCP
     connection (HTTP/2) vs QUIC streams (HTTP/3).
Standard library only; seeded, deterministic.
"""
import bisect
import collections
import random


class LRU:
    def __init__(self, cap: int):
        self.cap, self.d = cap, collections.OrderedDict()

    def get(self, k) -> bool:
        if k in self.d:
            self.d.move_to_end(k)
            return True
        return False

    def put(self, k) -> None:
        self.d[k] = True
        self.d.move_to_end(k)
        if len(self.d) > self.cap:
            self.d.popitem(last=False)


def workload(n_objects: int, reqs: int, s: float, one_hit_frac: float, rng: random.Random) -> list:
    acc, cdf = 0.0, []
    for k in range(1, n_objects + 1):
        acc += k ** -s
        cdf.append(acc)
    out, unique = [], n_objects
    for _ in range(reqs):
        if rng.random() < one_hit_frac:
            unique += 1
            out.append(unique)                               # requested exactly once, ever
        else:
            out.append(bisect.bisect_left(cdf, rng.random() * acc))
    return out


def topology(rng: random.Random) -> dict:
    pops, servers, per_server = 4, 16, 2_000
    streams = [workload(200_000, 100_000, 0.8, 0.2, random.Random(100 + p)) for p in range(pops)]
    res = {}
    for mode in ("random-server", "hash-in-pop", "hash-in-pop + shield"):
        edges = [[LRU(per_server) for _ in range(servers)] for _ in range(pops)]
        shield = LRU(servers * per_server * 2)
        hits = shield_hits = origin = total = 0
        for i in range(len(streams[0])):
            for p in range(pops):
                k = streams[p][i]
                total += 1
                srv = rng.randrange(servers) if mode == "random-server" else (((k * 0x9E3779B97F4A7C15) & 0xFFFFFFFFFFFFFFFF) >> 40) % servers
                c = edges[p][srv]
                if c.get(k):
                    hits += 1
                    continue
                c.put(k)
                if mode.endswith("shield"):
                    if shield.get(k):
                        shield_hits += 1
                        continue
                    shield.put(k)
                origin += 1
        res[mode] = {"edge_hit": hits / total, "origin_frac": origin / total, "shield_hit": shield_hits / total}
    return res


def admission(rng: random.Random) -> dict:
    reqs = workload(100_000, 300_000, 0.9, 0.35, rng)
    out = {}
    for mode in ("LRU", "LRU + second-hit admission"):
        cache, seen = LRU(5_000), set()
        hits = 0
        for k in reqs:
            if cache.get(k):
                hits += 1
                continue
            if mode == "LRU" or k in seen:
                cache.put(k)
            else:
                seen.add(k)                                  # production: a rotating Bloom filter, not a set
        out[mode] = hits / len(reqs)
    return out


def hol(p: float, streams: int, pkts_per_rtt: int, rounds: int, rng: random.Random) -> tuple[float, float]:
    """Per RTT round, packets are spread round-robin over streams. TCP: one loss stalls every stream whose data is
    later in the byte stream (approximated as all streams) until retransmission. QUIC: a loss stalls only its stream."""
    tcp = quic = 0
    for _ in range(rounds):
        lost = [rng.random() < p for _ in range(pkts_per_rtt)]
        if any(lost):
            first = lost.index(True)
            tcp += len({j % streams for j in range(first, pkts_per_rtt)} | {first % streams})
        quic += len({j % streams for j, l in enumerate(lost) if l})
    return tcp / (rounds * streams), quic / (rounds * streams)


def main() -> None:
    rng = random.Random(7)
    print("== A. 4 PoPs x 16 edge servers (2k objects each), shield = 64k objects, Zipf 0.8 + 20% one-hit wonders")
    topo = topology(rng)
    for mode, r in topo.items():
        print(f"  {mode:<22} edge hit {r['edge_hit'] * 100:5.1f}%   shield hit {r['shield_hit'] * 100:5.1f}%   "
              f"origin fetches {r['origin_frac'] * 100:5.1f}% of requests")

    print("\n== B. small cache (5k objects), Zipf 0.9 + 35% one-hit wonders")
    adm = admission(rng)
    for mode, hr in adm.items():
        print(f"  {mode:<28} hit ratio {hr * 100:5.1f}%")

    print("\n== C. head-of-line blocking: 10 streams, 40 packets per RTT")
    print(f"{'loss':>6} {'TCP/HTTP2 streams stalled':>26} {'QUIC/HTTP3 streams stalled':>27}")
    hb = {}
    for p in (0.001, 0.01, 0.02, 0.05):
        hb[p] = hol(p, 10, 40, 20_000, rng)
        print(f"{p * 100:>5.1f}% {hb[p][0] * 100:>25.1f}% {hb[p][1] * 100:>26.1f}%")

    a, b, c = topo["random-server"], topo["hash-in-pop"], topo["hash-in-pop + shield"]
    assert b["edge_hit"] > a["edge_hit"] + 0.1 and c["origin_frac"] < b["origin_frac"] * 0.85
    assert adm["LRU + second-hit admission"] > adm["LRU"]
    for p, (t, q) in hb.items():
        assert t > 2 * q
    print("\nself-test: all assertions passed")


if __name__ == "__main__":
    main()
```

Output (verified; deterministic):

```text
== A. 4 PoPs x 16 edge servers (2k objects each), shield = 64k objects, Zipf 0.8 + 20% one-hit wonders
  random-server          edge hit  14.0%   shield hit   0.0%   origin fetches  86.0% of requests
  hash-in-pop            edge hit  35.6%   shield hit   0.0%   origin fetches  64.4% of requests
  hash-in-pop + shield   edge hit  35.6%   shield hit  28.6%   origin fetches  35.9% of requests

== B. small cache (5k objects), Zipf 0.9 + 35% one-hit wonders
  LRU                          hit ratio  28.7%
  LRU + second-hit admission   hit ratio  35.3%

== C. head-of-line blocking: 10 streams, 40 packets per RTT
  loss  TCP/HTTP2 streams stalled  QUIC/HTTP3 streams stalled
  0.1%                       3.5%                        0.4%
  1.0%                      30.0%                        4.0%
  2.0%                      51.2%                        7.8%
  5.0%                      83.9%                       18.6%

self-test: all assertions passed
```

---

## 9. L5 vs L6 vs L7

| Topic | L5 (Senior) | L6 (Staff) | L7 (Principal) |
|---|---|---|---|
| Topology | "Put a CDN in front" | Edge + shield, cache keys, TTLs, purge | In-PoP owner hashing (2.5× hit ratio); shield math for origin load; ISP-embedded caches and proactive fill as cost levers |
| Freshness | "Set max-age" | s-maxage, SWR, stale-if-error, tag purge | Content-addressed assets (never invalidate); soft purge + SWR to make purges stampede-free; purge-all as an origin-DDoS risk |
| Eviction | LRU | One-hit wonders, TinyLFU | Admission filters (+23% hit ratio); byte- vs object-hit trade-offs; S3-FIFO/SIEVE |
| Protocols | "Use HTTP/2" | HTTP/3 benefits: 0-RTT, HOL, migration | Quantifies HOL under loss (30% vs 4% of streams stalled at 1%); CID-based load balancing; UDP fallback and measurement |
| Edge compute | — | Edge functions for auth and redirects | Consistency limits of edge KV; placement physics for stateful edge objects |

---

## 10. Bar-raiser probing chains

### Chain A: "Our CDN hit ratio is 60%, and origin egress costs $200k/month."

1. **L5:** "Increase TTLs."
2. **Probe:** "TTLs are already long." **L6:** "Check cache-key fragmentation (query params, cookies, Vary) and add an
   origin shield."
3. **Probe:** "Done; it's at 75%. Where's the rest?" **L7:**
   - Measure *per-PoP* duplication: is the in-PoP load balancer spraying? Owner hashing is worth 2.5×.
   - Look at one-hit wonders: add admission filters at the edges so they stop evicting useful objects.
   - Byte hit vs object hit: large objects need slicing.
   - For the predictable top-N (video, software updates), pre-position during off-peak.
   - Price each lever in $/month of origin egress against the cost of more edge storage.

### Chain B: "Deploy a new site version without users seeing a mix of old and new assets."

1. **L5:** "Purge the CDN after deploying."
2. **Probe:** "During the purge, some PoPs serve old HTML referencing new assets." **L6:** "Content-hash asset
   filenames; HTML gets a short TTL; old assets stay available."
3. **Probe:** "Purges cause origin spikes." **L7:**
   - "Assets never need purging. HTML uses soft purge + stale-while-revalidate, so each PoP refreshes once, from the
     shield."
   - Keep N previous versions' assets for rollbacks.
   - Roll out the deploy by PoP group (canary PoPs first), so a bad HTML push is a partial incident.

### Chain C: "Should we enable HTTP/3?"

1. **L5:** "Yes, it's faster."
2. **Probe:** "For which users, by how much?" **L6:** "Mostly mobile and lossy networks: 0-RTT, no head-of-line
   blocking, connection migration."
3. **Probe:** "Make the decision with data." **L7:**
   - A/B by connection: compare p95/p99 time-to-first-byte and rebuffer rates on mobile ASNs. The lab predicts big
     gains where loss ≥ 1%.
   - Measure the CPU cost per Gbps on our edge servers (user-space QUIC) and UDP blocking rates.
   - Enable with TCP fallback.
   - Make the LB route by connection ID before enabling migration.

---

## 11. Invariants checklist

- [ ] In-PoP owner hashing (with hot-object replication) and a shield tier; origin authenticated, not exposed.
- [ ] Cache keys normalized; `Vary` minimal; personalized content not cached in shared caches.
- [ ] Static assets content-addressed; dynamic content SWR + stale-if-error; purges soft and rate-limited.
- [ ] Admission/eviction chosen for one-hit wonders and byte hit ratio.
- [ ] HTTP/3 with TCP fallback; LB by connection ID; benefits measured on lossy networks.
- [ ] Edge KV used only for read-mostly, staleness-tolerant data.

---

## 12. References

- B. Maggs, R. Sitaraman. *Algorithmic Nuggets in Content Delivery.* ACM SIGCOMM CCR 45(3), 2015.
- E. Nygren, R. Sitaraman, J. Sun. *The Akamai Network: A Platform for High-Performance Internet Applications.* ACM
  SIGOPS OSR 44(3), 2010.
- J. Yang et al. *FIFO Queues are All You Need for Cache Eviction (S3-FIFO).* SOSP 2023. Y. Zhang et al., *SIEVE is
  Simpler than LRU*, NSDI 2024.
- G. Einziger, R. Friedman, B. Manes. *TinyLFU: A Highly Efficient Cache Admission Policy.* ACM TOS 2017.
- D. Berger, R. Sitaraman, M. Harchol-Balter. *AdaptSize: Orchestrating the Hot Object Memory Cache in a Content
  Delivery Network.* NSDI 2017.
- RFC 9000/9001/9002 (QUIC), RFC 9114 (HTTP/3), RFC 9204 (QPACK), RFC 9111 (HTTP caching), RFC 5861 (SWR,
  stale-if-error).
- A. Langley et al. *The QUIC Transport Protocol: Design and Internet-Scale Deployment.* SIGCOMM 2017.
- Netflix TechBlog / Open Connect overview (openconnect.netflix.com).
