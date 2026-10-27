# Problems 20–21: Planet-Scale Web Crawler, and a Real-Time Collaborative Editor (CRDTs vs OT)

> **Folder 07 · File 03** of the Distributed Systems & System Design L7 Reference.
> **Listing:** `crawler_crdt_lab.py` covers:
> - a crawl frontier with politeness (single FIFO vs Mercator back queues) and URL-seen filter sizing;
> - an RGA sequence CRDT tested for convergence against naive index edits;
> - OT transform functions checked for TP1.
>
> The output is deterministic.

---

## Problem 20: A planet-scale web crawler

### 20.1 Scope, scale and SLAs

| Quantity | Target |
|---|---|
| Pages | 10B pages refreshed per month; 100B URLs known |
| Fetch rate | 10B / 30 days ≈ **3,900 pages/s** average; 10–20k/s peak |
| Bandwidth | ~100 KB per page → ~400 MB/s ≈ **3.2 Gbps** average (plus robots.txt, DNS, redirects) |
| Storage | 10B × 100 KB = 1 PB raw per crawl cycle; ~200 TB compressed |
| Politeness | ≤ 1 request per host per few seconds (or `Crawl-delay`); obey robots.txt |
| Freshness | Important/changing pages hourly–daily; long tail monthly |

### 20.2 The core L7 bottleneck: politeness turns a throughput problem into a scheduling problem

§A of the output: 200k URLs over 2,000 hosts (Zipf 1.2: a few huge sites, a long tail), 50 workers, 1 s politeness,
200 ms fetch time.

| Frontier design | Throughput |
|---|---|
| Single FIFO queue (a worker blocks on the head URL's host) | **4.8 pages/s** |
| **Per-host back queues ordered by next-allowed time** (Mercator) | **199.1 pages/s** |

With a FIFO frontier, the queue is dominated by the few huge hosts. Every worker ends up waiting for the same
politeness timers: head-of-line blocking, again. The **Mercator design** (Heydon & Najork 1999):
- **Front queues** prioritize by importance and freshness (PageRank-ish, change rate).
- **Back queues** hold one queue per host (or IP), with a heap keyed by each host's next allowed fetch time.
- Workers pick the host whose timer has expired, so they are never blocked on politeness.
- Throughput then scales with the **number of distinct ready hosts**, not with the URL count.

**Partition key:** URLs are sharded across crawler nodes by **hash(host)**, so each host's politeness state lives on
exactly one node. A distributed crawler that shards by URL hash would need cross-node coordination for every host's
rate limit.

### 20.3 Architecture and paths

```
 seed + discovered URLs → URL normalizer (canonicalize, strip session params) → URL-SEEN filter (Bloom / exact store)
   → frontier: front queues (priority) → back queues (per host, politeness heap)   [sharded by hash(host)]
   → fetchers: robots.txt cache (per host, TTL), DNS cache (local resolvers!), HTTP with timeouts, size limits
   → content store (compressed WARC-like blobs, content-hash dedupe: simhash for near-duplicates)
   → parser/extractor: links → back to normalizer; text → indexer (problem 19); change detection → recrawl schedule
 control: priority models, recrawl policy, per-domain overrides, blocklists, politeness config (validated, staged)
```

### 20.4 Deep-dive mechanics

- **URL-seen at 100B URLs:**
  - A Bloom filter at 1% FPR needs 9.6 bits per URL. For 10B URLs that is **11.2 GiB**, against **75 GiB** for exact
    8-byte fingerprints (§A).
  - The cost of the Bloom filter is that **1% of genuinely new URLs are wrongly skipped**. For a search engine,
    missing 1% of new pages may be acceptable for low-priority domains and not for important ones.
  - So use exact fingerprint stores (a sorted LSM keyed by hash) for important domains, and Bloom filters for the
    long tail, sharded by host along with the frontier.
- **DNS is a hidden bottleneck.** At 10k fetches/s, public resolvers rate-limit and add latency. Run local caching
  resolvers per crawler node.
- **Traps and dedupe:**
  - Calendars, infinite URL spaces and session IDs: cap depth and URL counts per host, normalize, detect URL-pattern
    explosions.
  - Mirror sites: near-duplicate detection with **SimHash** (Charikar 2002; Manku et al. WWW 2007) on content.
- **Recrawl scheduling:** estimate each page's change rate (Poisson model from past observations) and allocate
  fetches to maximize freshness per fetch (Cho & Garcia-Molina 2003). Frequently changing, important pages get
  revisited often, and static pages rarely.

### 20.5 Failure defense

| Failure | Defense |
|---|---|
| Overloading a site (complaints, blocks) | Per-host and per-IP politeness; adaptive back-off on 429/503 and slow responses; honor robots.txt |
| Crawler trap | Depth/URL caps per host; pattern detection; dedupe |
| Node failure | Host-sharded frontiers are checkpointed; another node takes over the shard (lease) and replays from the checkpoint |
| Bad parser release | Canary on a sample; content store keeps raw bytes so you can re-parse without re-fetching |
| Bloom filter saturation | Rotate/size by expected inserts; monitor fill ratio |

### 20.6 L5 / L6 / L7 and probing chain

| | L5 | L6 | L7 |
|---|---|---|---|
| Design | BFS queue + workers + seen set | Politeness, robots.txt, Bloom URL-seen, content dedupe, host-sharded crawlers | Mercator front/back queues (4.8 → 199 pages/s); hash(host) partitioning; Bloom vs exact by domain value; change-rate recrawl optimization; DNS as a bottleneck |

1. **Probe:** "Use a distributed queue of URLs and many workers." **L5:** "Scale workers to go faster."
2. **Probe:** "Adding workers doesn't increase throughput." **L6:** "Politeness: workers block on the same few hosts.
   Use per-host queues."
3. **Probe:** "Throughput is now bound by ready hosts; how do you get to 20k pages/s?" **L7:**
   - "Throughput = number of ready hosts ÷ politeness interval. We need ~20k–100k hosts ready at any moment."
   - "So the front-queue priority must interleave domains, not just rank pages."
   - "Shard by host so each node owns enough distinct hosts."
   - "Fetch from big sites in parallel only where they publish higher allowed rates (sitemaps, Crawl-delay)."
   - "It's a scheduling problem over hosts, not a queue of URLs."

---

## Problem 21: A real-time collaborative editor (Google Docs / Figma): CRDTs vs OT

### 21.1 Scope, scale and SLAs

| Quantity | Target |
|---|---|
| Documents | Billions; active collaborative sessions: millions |
| Editors per document | Typically 2–10; up to ~100 concurrently; viewers in the thousands |
| Latency | Local edit visible instantly (optimistic); remote edits within ~100–300 ms |
| Correctness | All replicas **converge** to the same document; user intent preserved; no lost edits |
| Offline | Edits while offline merge on reconnect |

### 21.2 The two families

| | Operational Transformation (OT) | CRDTs (sequence CRDTs: RGA, YATA/Yjs, Automerge) |
|---|---|---|
| Idea | Operations carry positions; concurrent ops are *transformed* against each other before applying | Each character has a **unique, ordered ID**; inserts reference neighbors' IDs; merges are commutative by construction |
| Server | Practical systems use a **central server** that orders operations (Jupiter, Google Docs) | Works peer-to-peer or via a relay; a server is optional |
| Correctness burden | The transform functions must satisfy TP1, and TP2 without a central order. Many published algorithms were later shown incorrect | Convergence follows from commutativity and idempotence of merges |
| Metadata | Small | IDs per character and **tombstones** (needs compaction/GC) |
| Offline | Hard (long divergent histories to transform) | Natural |
| Used by | Google Docs, (historically) Google Wave | Figma (a CRDT-inspired, server-authoritative design), Yjs, Automerge, Apple Notes (⚠ verify) |

§B and §C of the output:
- **RGA (Roh et al. 2011) converged in 200/200 trials:** 3 sites × 60 random concurrent inserts and deletes,
  delivered in different causal orders.
- **Naive index-based edits agreed in 0/200** when applied in different orders.
- **OT transforms passed TP1 in 20,000/20,000 random concurrent pairs.** Pairwise TP1 is not enough for peer-to-peer
  OT, which also needs TP2, a property many OT algorithms failed. Production OT avoids the problem with a **central
  server that serializes operations**.

### 21.3 RGA mechanics (as implemented in the listing)

```
element = (id = (lamport_counter, site_id), char, tombstone?)
insert(after_id = origin, new_id): start right after origin; skip over elements whose id > new_id
                                   (concurrent inserts after the same origin are ordered by id, deterministically)
delete(id): mark tombstone (never physically removed until GC is safe)
delivery: causal (an insert waits until its origin exists); duplicates ignored (idempotent)
```

### 21.4 Architecture (server-assisted, the design most products use)

```
 client: local document model (CRDT or OT client state) — apply edit instantly → send op to session server
 session server (one per active document, chosen by consistent hash of doc_id; sticky):
   • orders/broadcasts ops to connected editors (and, for OT, transforms against concurrent ops)
   • batches ops; persists to an append-only op log (doc_id, seq) → durable store
   • periodically snapshots the document (compaction: tombstone GC, op-log truncation)
 presence/cursors: ephemeral pub/sub channel (lossy, not persisted)
 load: open doc → latest snapshot + ops since snapshot; offline client → sends its op backlog (CRDT merge)
 failure: session server dies → clients reconnect (jitter) → new server rebuilds state from snapshot + log
```

**Partition key: `doc_id`.** One active session server per document gives a natural serialization point: ordering is
per document, with no global coordination. This is the same pattern as chat (problem 13) and per-account ledgers.

### 21.5 The core L7 bottleneck: metadata growth and the "single document" hot spot

1. **Tombstones and IDs grow without bound** in CRDTs. GC is safe only once every replica has seen the delete: a
   causal stability condition. Production systems:
   - snapshot periodically on the server and drop history before the snapshot for online clients;
   - give offline clients beyond a horizon a fresh snapshot plus a three-way merge of their local changes.

   Yjs and Automerge use run-length encoding of consecutive inserts by one site to keep metadata small.
2. **A popular document (company all-hands notes, 1,000 editors) concentrates on one session server.** Mitigations:
   - batch ops (e.g. 50 ms frames);
   - split viewers (read-only, served from a fan-out tier with snapshots plus a delta stream) from editors;
   - coarsen presence updates.
3. **Rich structure.** Spreadsheets, trees (outlines) and Figma's scene graph need CRDTs for maps, trees and moves.
   **Concurrent moves can create cycles**, which needs dedicated algorithms (Kleppmann et al. 2021, a highly-available
   move operation for replicated trees). Figma's published approach uses server authority with
   last-writer-wins per property, plus careful handling of tree reparenting (⚠ verify the details).

### 21.6 Failure defense

| Failure | Defense |
|---|---|
| Session server crash | Snapshot + op log; clients reconnect and resend unacked ops (idempotent by op ID) |
| Client offline for days | CRDT merge of its backlog; beyond the GC horizon, snapshot + three-way merge |
| Divergence bug | Periodic checksum of document state across clients/server; force a resync from the server snapshot |
| Hot document | Batching, viewer/editor split, presence throttling |
| Malicious/invalid ops | Server validates ops (permissions per Zanzibar check, schema), rejects them, and resyncs the client |

### 21.7 L5 / L6 / L7 and probing chain

| | L5 | L6 | L7 |
|---|---|---|---|
| Design | WebSocket + last-write-wins on the whole doc | OT with a central server, or a CRDT; per-doc session servers; op log + snapshots | CRDT vs OT trade-offs (TP2, metadata, offline); causal-stability GC; tree-move cycles; per-doc serialization point; divergence detection |

1. **Probe:** "Two users type at the same position simultaneously." **L5:** "Last write wins."
2. **Probe:** "One user's text disappears." **L6:** "OT: transform the second insert's position against the first;
   tie-break by site ID."
3. **Probe:** "Now support offline editing for days, then merge." **L7:**
   - "OT with long divergent histories means transforming thousands of operations against each other; it's fragile."
   - "A sequence CRDT merges naturally (the lab converged 200/200 under arbitrary causal orders)."
   - "The cost is metadata: per-character IDs and tombstones. We keep the server as the snapshot authority, GC
     tombstones once causally stable, and give long-offline clients a three-way merge against a recent snapshot."
   - "Session servers per doc still exist for fan-out, presence and persistence, just not for correctness."

---

## 22. The listing

```python
"""crawler_crdt_lab.py - crawler politeness scheduling, a sequence CRDT, and operational transformation
(Folder 07, file 03).

  A. Crawl frontier with a 1 s per-host politeness delay and skewed URLs per host: one FIFO queue (head-of-line
     blocking) vs per-host back queues ordered by next-allowed time (Mercator). Plus URL-seen filter sizing.
  B. RGA sequence CRDT (Roh et al. 2011): three replicas edit concurrently; operations are delivered in different
     causal orders; do the replicas converge? Compared with naive index-based edits.
  C. Operational transformation for insert/delete: check the TP1 convergence property over random concurrent pairs.
Standard library only; seeded, deterministic.
"""
import collections
import heapq
import math
import random


# ---------------------------------------------------------------- A. crawler frontier
def crawl(mode: str, rng: random.Random, workers: int = 50, seconds: int = 300) -> dict:
    hosts = 2000
    weights = [1 / (h + 1) ** 1.2 for h in range(hosts)]                 # a few huge sites, a long tail
    urls = rng.choices(range(hosts), weights=weights, k=200_000)
    delay, fetch = 1.0, 0.2                                              # politeness gap, fetch time
    next_ok = [0.0] * hosts
    fetched = 0
    if mode == "single FIFO":
        q = collections.deque(urls)
        free = [0.0] * workers
        heapq.heapify(free)
        while q:
            t = heapq.heappop(free)
            h = q.popleft()
            start = max(t, next_ok[h])                                   # the worker blocks on the head URL's host
            if start > seconds:
                break
            next_ok[h] = start + delay
            fetched += 1
            heapq.heappush(free, start + fetch)
    else:                                                                # Mercator back queues
        back = collections.defaultdict(collections.deque)
        for h in urls:
            back[h].append(h)
        ready = [(0.0, h) for h in back]
        heapq.heapify(ready)
        free = [0.0] * workers
        heapq.heapify(free)
        while ready:
            t = heapq.heappop(free)
            ok_at, h = heapq.heappop(ready)
            start = max(t, ok_at)
            if start > seconds:
                break
            back[h].popleft()
            fetched += 1
            heapq.heappush(free, start + fetch)
            if back[h]:
                heapq.heappush(ready, (start + delay, h))
    return {"pages_per_s": fetched / seconds}


# ---------------------------------------------------------------- B. RGA
class RGA:
    def __init__(self, site: int):
        self.site, self.clock = site, 0
        self.seq: list = [((0, -1), None, False)]                        # (id, char, deleted); head sentinel
        self.index = {(0, -1): 0}

    def _reindex(self) -> None:
        self.index = {e[0]: i for i, e in enumerate(self.seq)}

    def visible(self) -> str:
        return "".join(c for _, c, d in self.seq[1:] if not d)

    def local_insert(self, pos: int, ch: str) -> tuple:
        vis = [i for i, e in enumerate(self.seq) if i == 0 or not e[2]]
        origin = self.seq[vis[pos]][0]                                   # insert after the pos-th visible element
        self.clock += 1
        op = ("ins", (self.clock, self.site), origin, ch)
        self.apply(op)
        return op

    def local_delete(self, pos: int) -> tuple:
        vis = [i for i, e in enumerate(self.seq) if i > 0 and not e[2]]
        op = ("del", self.seq[vis[pos]][0])
        self.apply(op)
        return op

    def ready(self, op: tuple) -> bool:
        return (op[2] in self.index) if op[0] == "ins" else (op[1] in self.index)

    def apply(self, op: tuple) -> None:
        if op[0] == "ins":
            _, oid, origin, ch = op
            if oid in self.index:
                return                                                   # idempotent
            self.clock = max(self.clock, oid[0])
            i = self.index[origin] + 1
            while i < len(self.seq) and self.seq[i][0] > oid:            # skip concurrent inserts with higher IDs
                i += 1
            self.seq.insert(i, (oid, ch, False))
            self._reindex()
        else:
            i = self.index[op[1]]
            oid, ch, _ = self.seq[i]
            self.seq[i] = (oid, ch, True)                                # tombstone


def crdt_trial(rng: random.Random, ops_per_site: int = 60) -> tuple[bool, bool]:
    sites = [RGA(s) for s in range(3)]
    log: list = []
    naive = ["", "", ""]
    naive_log: list = []
    for _ in range(ops_per_site * 3):
        s = rng.randrange(3)
        r = sites[s]
        if r.visible() and rng.random() < 0.3:
            pos = rng.randrange(len(r.visible()))
            log.append(r.local_delete(pos))
            naive_log.append(("del", pos))
        else:
            pos = rng.randint(0, len(r.visible()))
            ch = rng.choice("abcdefgh")
            log.append(r.local_insert(pos, ch))
            naive_log.append(("ins", pos, ch))
        if rng.random() < 0.2:                                           # occasional partial sync to a random peer
            peer = sites[rng.randrange(3)]
            for op in log:
                if peer.ready(op):
                    peer.apply(op)
    for r in sites:                                                      # deliver everything, in a random causal order
        pending = log[:]
        rng.shuffle(pending)
        while pending:
            rest = []
            for op in pending:
                (r.apply(op) if r.ready(op) else rest.append(op))
            pending = rest
    converged = len({r.visible() for r in sites}) == 1
    # naive: each replica applies the same index-based ops in a different order
    outs = set()
    for _ in range(3):
        order = naive_log[:]
        rng.shuffle(order)
        text = []
        for op in order:
            if op[0] == "ins":
                text.insert(min(op[1], len(text)), op[2])
            elif text:
                del text[min(op[1], len(text) - 1)]
        outs.add("".join(text))
    return converged, len(outs) == 1


# ---------------------------------------------------------------- C. OT
def apply_op(s: str, op: tuple) -> str:
    if op[0] == "noop":
        return s
    if op[0] == "ins":
        return s[:op[1]] + op[2] + s[op[1]:]
    return s[:op[1]] + s[op[1] + 1:] if op[1] < len(s) else s


def transform(a: tuple, b: tuple, a_site: int, b_site: int) -> tuple:
    """Transform a against concurrent b (both defined on the same document state)."""
    if a[0] == "ins" and b[0] == "ins":
        if a[1] < b[1] or (a[1] == b[1] and a_site < b_site):
            return a
        return ("ins", a[1] + 1, a[2])
    if a[0] == "ins" and b[0] == "del":
        return a if a[1] <= b[1] else ("ins", a[1] - 1, a[2])
    if a[0] == "del" and b[0] == "ins":
        return a if a[1] < b[1] else ("del", a[1] + 1)
    if a[1] < b[1]:
        return a
    if a[1] > b[1]:
        return ("del", a[1] - 1)
    return ("noop", 0)                                                   # both deleted the same character


def ot_tp1(trials: int, rng: random.Random) -> int:
    violations = 0
    for _ in range(trials):
        s = "".join(rng.choice("xyz") for _ in range(rng.randint(1, 8)))

        def rand_op():
            if rng.random() < 0.5:
                return ("ins", rng.randint(0, len(s)), rng.choice("AB"))
            return ("del", rng.randrange(len(s)))
        a, b = rand_op(), rand_op()
        left = apply_op(apply_op(s, a), transform(b, a, 2, 1))          # site 1 applied a, then receives b'
        right = apply_op(apply_op(s, b), transform(a, b, 1, 2))         # site 2 applied b, then receives a'
        violations += left != right
    return violations


def main() -> None:
    rng = random.Random(21)
    print("== A. crawler: 200k URLs over 2,000 hosts (Zipf 1.2), 50 workers, 1 s politeness, 200 ms fetch")
    cr = {m: crawl(m, rng) for m in ("single FIFO", "per-host back queues")}
    for m, r in cr.items():
        print(f"  {m:<22} {r['pages_per_s']:7.1f} pages/s")
    n = 10e9
    bits = -math.log(0.01) / math.log(2) ** 2
    print(f"  URL-seen for 10B URLs: Bloom at 1% FPR = {bits:.1f} bits/URL = {n * bits / 8 / 2 ** 30:.1f} GiB "
          f"(1% of NEW URLs wrongly skipped); exact 8-byte fingerprints = {n * 8 / 2 ** 30:.0f} GiB")

    print("\n== B. RGA sequence CRDT vs naive index edits: 3 sites x 60 random ops, 200 trials")
    results = [crdt_trial(rng) for _ in range(200)]
    rga_ok = sum(r[0] for r in results)
    naive_ok = sum(r[1] for r in results)
    print(f"  RGA replicas converged in {rga_ok}/200 trials; naive index-based replicas agreed in {naive_ok}/200")

    print("\n== C. OT transform functions: TP1 over 20,000 random concurrent (insert|delete) pairs")
    v = ot_tp1(20_000, rng)
    print(f"  TP1 violations: {v}  (TP1 holds pairwise; multi-site convergence additionally needs TP2 or a central "
          f"server ordering operations, as in Jupiter / Google Docs)")

    assert cr["per-host back queues"]["pages_per_s"] > 5 * cr["single FIFO"]["pages_per_s"]
    assert rga_ok == 200 and naive_ok < 20 and v == 0
    print("\nself-test: all assertions passed")


if __name__ == "__main__":
    main()
```

Output (verified; deterministic):

```text
== A. crawler: 200k URLs over 2,000 hosts (Zipf 1.2), 50 workers, 1 s politeness, 200 ms fetch
  single FIFO                4.8 pages/s
  per-host back queues     199.1 pages/s
  URL-seen for 10B URLs: Bloom at 1% FPR = 9.6 bits/URL = 11.2 GiB (1% of NEW URLs wrongly skipped); exact 8-byte fingerprints = 75 GiB

== B. RGA sequence CRDT vs naive index edits: 3 sites x 60 random ops, 200 trials
  RGA replicas converged in 200/200 trials; naive index-based replicas agreed in 0/200

== C. OT transform functions: TP1 over 20,000 random concurrent (insert|delete) pairs
  TP1 violations: 0  (TP1 holds pairwise; multi-site convergence additionally needs TP2 or a central server ordering operations, as in Jupiter / Google Docs)

self-test: all assertions passed
```

---

## 23. References for problems 20–21

- A. Heydon, M. Najork. *Mercator: A Scalable, Extensible Web Crawler.* WWW 1999. M. Najork, A. Heydon,
  *High-Performance Web Crawling*, 2001.
- J. Cho, H. Garcia-Molina. *Effective Page Refresh Policies for Web Crawlers.* ACM TODS 2003.
- M. Charikar. *Similarity Estimation Techniques from Rounding Algorithms.* STOC 2002. G. Manku, A. Jain, A. Das
  Sarma, *Detecting Near-Duplicates for Web Crawling*, WWW 2007.
- C. Ellis, S. Gibbs. *Concurrency Control in Groupware Systems.* SIGMOD 1989 (OT). D. Nichols et al.,
  *High-latency, low-bandwidth windowing in the Jupiter collaboration system*, UIST 1995.
- H.-G. Roh, M. Jeon, J.-S. Kim, J. Lee. *Replicated Abstract Data Types: Building Blocks for Collaborative
  Applications (RGA).* JPDC 2011.
- M. Shapiro et al. *Conflict-free Replicated Data Types.* SSS 2011. M. Kleppmann, A. Beresford, *A
  Conflict-Free Replicated JSON Datatype*, IEEE TPDS 2017. M. Kleppmann et al., *A highly-available move operation
  for replicated trees*, IEEE TPDS 2021.
- Figma Engineering. *How Figma's multiplayer technology works*, 2019. Yjs (github.com/yjs/yjs), Automerge
  (automerge.org).
