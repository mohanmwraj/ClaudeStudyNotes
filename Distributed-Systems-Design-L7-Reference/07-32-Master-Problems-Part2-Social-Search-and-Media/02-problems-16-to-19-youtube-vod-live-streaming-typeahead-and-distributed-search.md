# Problems 16–19: YouTube/Netflix VOD and ABR, Low-Latency Live Streaming, Typeahead, Distributed Search

> **Folder 07 · File 02** of the Distributed Systems & System Design L7 Reference.
> **Listing:** `media_search_lab.py` covers:
> - adaptive-bitrate policies (throughput, buffer-based BBA, BBA with download abandonment, throughput with a buffer
>   guard) over bursty bandwidth;
> - a typeahead trie with precomputed top-k;
> - posting-list intersection (linear vs galloping), BM25, and the sharding trade-off.
>
> The output is deterministic.

---

## Problem 16: Video transcoding and adaptive-bitrate VOD (YouTube/Netflix)

### 16.1 Scope, scale and SLAs

| Quantity | Target |
|---|---|
| Uploads | 500 hours of video per minute (YouTube-scale, ⚠ verify) ≈ 30,000 h/h of source |
| Catalog | Billions of videos; extreme popularity skew (a tiny fraction gets most views) |
| Playback | Hundreds of Tbps of egress at peak (mostly from CDNs/ISP caches) |
| QoE SLOs | Start-up time p50 < 1–2 s; **rebuffer ratio < 0.5%**; minimal quality switches |
| Time to publish | Upload → playable (low rungs) within minutes; full ladder later |

**Capacity math (transcoding).**
- Assume each output rendition takes ~0.5–2 CPU-seconds per second of source for H.264 at 1080p; far more for
  AV1/VP9 (⚠ codec-dependent).
- A 6-rung ladder × 2 codecs means ~10–30 CPU-s per source second.
- 30,000 source hours per hour = 30,000 × 3,600 = 1.08×10⁸ source-seconds per hour → ~10⁹–3×10⁹ CPU-s per hour →
  **~300k–900k cores busy continuously** for full ladders.
- **Popularity skew is the FinOps lever.** Transcode everything into H.264 at a few rungs quickly. Spend expensive
  codecs (AV1) and **per-title encoding** (Netflix's per-shot optimization) only on content likely to be watched.
  That trades encode CPU for egress bytes exactly where egress dominates.

### 16.2 Pipeline and schema

```
 upload (resumable, chunked, to object storage) → validate/probe → split source into GOP-aligned chunks (~2–10 s)
   → DAG of tasks: per chunk × per rendition encode (massively parallel, preemptible/spot CPUs or HW encoders)
   → assemble per rendition → package (fMP4/CMAF segments + HLS/DASH manifests) → DRM encryption → publish to origin
   → CDN/Open Connect pre-positioning for predicted-popular titles
 metadata: video_id → {state machine: UPLOADED→PROBED→LOW_RUNGS_READY→FULL_READY, renditions[], manifests, owner}
 tasks:    (video_id, chunk, rendition) → status, attempt, worker lease   (idempotent; outputs content-addressed)
```

- **Chunk-parallel encoding** turns a 2-hour movie into thousands of independent tasks. Latency to publish becomes
  ~minutes regardless of length.
- **Idempotent, content-addressed outputs** let tasks retry on preempted spot instances without corruption. This is
  the batch version of Folder 03 file 03's exactly-once effects.

### 16.3 Playback: ABR (§A of the output)

Setup: 50 sessions × 600 four-second segments; bursty cellular-like bandwidth with deep drops; ladder 235–8,000 kbps.

| ABR policy | Rebuffer (% of play time) | Mean bitrate | Switches/hour |
|---|---|---|---|
| Throughput-based (harmonic mean of the last 5) | 2.14% | 2,554 kbps | 172 |
| Buffer-based (BBA: 10 s reservoir, 30 s cushion) | **5.06%** | **3,596 kbps** | 279 |
| **BBA + download abandonment** | **0.00%** | **3,576 kbps** | 301 |
| Throughput + buffer guard | 1.82% | 2,544 kbps | 171 |

Reading it honestly:
1. **Buffer-based control (Huang et al., SIGCOMM 2014) delivers ~40% higher bitrate,** because it doesn't
   under-estimate bandwidth after brief dips.
2. **Pure BBA rebuffers more under *deep, sudden* drops.** With a full buffer it commits to an 8 Mbps segment, and if
   bandwidth then collapses to 500 kbps, that one segment takes ~64 s to download.
3. **Download abandonment** (cancel the in-flight segment when its projected finish exceeds the buffer, and refetch
   at the lowest rung) removes that failure mode. In this model, rebuffering drops to 0 with BBA's bitrate. Players
   like dash.js implement abandonment rules.
4. Production players use hybrids: **BOLA** (Lyapunov-optimized buffer-based), MPC (model-predictive control), and
   ML-tuned policies, all evaluated on real traces with A/B QoE metrics. This model is a teaching approximation; ⚠
   validate on your own traces.

### 16.4 The core L7 bottleneck: egress cost vs QoE

- **Egress dominates TCO.** The levers, in order:
  1. ISP-embedded caches / Open Connect (no transit);
  2. better codecs for popular titles (AV1 saves ~30% bits vs H.264 at equal quality, ⚠ content-dependent);
  3. per-title/per-shot ladders;
  4. ABR that doesn't waste bits (don't fetch 8 Mbps for a phone screen: cap by device and viewport).
- **QoE is measured, not assumed:**
  - client telemetry: start-up time, rebuffers, bitrate and switches;
  - QoE A/B tests for every ABR or encoding change;
  - regional dashboards that catch ISP congestion.

### 16.5 Failure defense

| Failure | Defense |
|---|---|
| Spot preemption mid-encode | Chunk tasks idempotent, leased, retried; outputs content-addressed |
| Bad encoder release (artifacts) | Canary encodes with automatic quality metrics (VMAF) before fleet rollout |
| Popular title not pre-positioned | Fill from shields; tiered caches; request collapsing on origin |
| Manifest/DRM service outage | Manifests cached at the edge with long TTL; license servers multi-region with cached policies |
| Upload storms | Resumable uploads, per-user quotas, async processing with priority (paid/creator tiers) |

### 16.6 L5 / L6 / L7 and probing chain

| | L5 | L6 | L7 |
|---|---|---|---|
| Design | Upload → transcode → store → CDN | Chunk-parallel DAG, HLS/DASH, ABR, CDN pre-positioning | Encode spend by predicted popularity; per-title ladders; ABR with abandonment validated by QoE A/B; egress as the dominant TCO |

1. **Probe:** "Transcode every upload into every resolution and codec." **L5:** "For best quality everywhere."
2. **Probe:** "That's a million cores." **L6:** "Prioritize: low rungs first, full ladder in the background; spot
   instances."
3. **Probe:** "Where's the real money?" **L7:**
   - "Egress, not encoding. A popular title's bits are served billions of times, so spending 10× CPU to save 30% of
     its bytes pays back instantly. Spending it on a video with 12 views never does."
   - "So encode cheaply first, re-encode up the cost curve as views accumulate, and pre-position the predicted hits
     in ISP caches off-peak."

---

## Problem 17: Low-latency live streaming (Twitch / sports)

### 17.1 Scope, scale and SLAs

| Quantity | Target |
|---|---|
| Concurrent viewers | 10M+ for major events; long tail of small streams |
| Glass-to-glass latency | Standard HLS ~15–30 s; **LL-HLS / LL-DASH ~2–5 s**; WebRTC **< 500 ms** |
| Ingest | Thousands of concurrent broadcasters (RTMP/SRT/WebRTC ingest) |
| Reliability | No stall at kickoff; graceful quality degradation |

### 17.2 Latency budget, by protocol

| Stage | Classic HLS (6 s segments, 3-segment buffer) | LL-HLS (partial segments ~0.33–1 s) | WebRTC |
|---|---|---|---|
| Encoder + packager | ~1–2 s (GOP) | ~0.5–1 s (short GOP, parts) | ~100 ms |
| CDN delivery | Segment must complete: 6 s | Parts pushed as produced; blocking playlist reload | Media over SFU, no segments |
| Player buffer | 3 × 6 s = 18 s | ~1–3 s | ~100–300 ms jitter buffer |
| **Total** | **~20–30 s** | **~2–5 s** | **~0.3–0.5 s** |
| Scale economics | CDN-cacheable, cheapest | CDN-cacheable (with LL support), cheap | SFU fan-out per viewer; expensive at millions |

**Latency is bought with buffer, and buffer is what absorbs network jitter.** Lower latency means less buffer, which
means more rebuffering on bad networks. The L7 choice is per use case:
- **interactive** (auctions, betting, co-watching with chat): WebRTC or LL;
- **mass broadcast:** LL-HLS at ~3–5 s;
- **24×7 channels:** standard HLS.

### 17.3 Architecture

```
 broadcaster → ingest PoP (nearest; SRT/RTMP/WebRTC) → transcode ladder in real time (GPU/ASIC) →
   packager (CMAF chunks / LL-HLS parts) → origin (per stream, replicated ×2 in different AZs) →
   CDN shield → edges (hold-and-push of parts; request collapsing so 1M viewers ≈ 1 origin request per part per PoP)
 interactive tier: SFU cascade (WebRTC) for sub-second audiences, capped per stream
 control: stream registry, ingest routing, transcode capacity scheduling (pre-provisioned for scheduled events)
```

### 17.4 The core L7 bottleneck: the thundering herd on every new part

Every viewer requests the next part as soon as it exists. 10M viewers × a part every 0.5 s = 20M req/s, *synchronized
to the part boundary*. The defenses:
- **Request collapsing** at edges and shields: one upstream fetch per part per server.
- **Blocking playlist reloads / preload hints** (LL-HLS): the edge holds requests and answers all of them the instant
  the part arrives.
- **Shield tiers** so origins see one request per part per region.
- **Pre-provisioned capacity for scheduled events** (kickoff), and jittered player join.

### 17.5 Failure defense

| Failure | Defense |
|---|---|
| Ingest PoP failure | Broadcaster auto-reconnects to the next PoP; redundant ingest for premium events (two encoders, two PoPs) |
| Transcoder failure | Hot standby per premium stream; graceful ladder reduction (drop top rungs) |
| Origin failure | Dual origins with identical segment naming; edges fail over by manifest/redundant streams |
| Viewer surge | Edge request collapsing; shield; degrade top rung availability before refusing joins |

### 17.6 L5 / L6 / L7 and probing chain

| | L5 | L6 | L7 |
|---|---|---|---|
| Design | RTMP in, HLS out via CDN | LL-HLS parts, ladder transcode, CDN collapsing | Latency budget per stage; protocol per use case; synchronized part herds; pre-provisioned event capacity; redundant ingest |

1. **Probe:** "Make latency 1 second for 10M viewers." **L5:** "Use WebRTC."
2. **Probe:** "WebRTC SFUs at 10M viewers?" **L6:** "Too expensive; LL-HLS at ~3 s through the CDN."
3. **Probe:** "The product insists on sub-second for betting." **L7:**
   - "Split audiences. The betting UI gets a sub-second WebRTC feed with a capped audience (bettors), or, more
     cheaply, sub-second *data* (scores and odds) over a pub/sub channel, while the video stays on LL-HLS at ~3 s."
   - "The latency requirement is usually about the *event signal*, not the pixels."

---

## Problem 18: Typeahead search autocomplete (distributed trie)

### 18.1 Scope, scale and SLAs

| Quantity | Target |
|---|---|
| Queries | 10B searches/day; each keystroke may trigger a suggestion request → **~500k–1M suggestion req/s** peak |
| Latency | **p99 < 50 ms** end-to-end (perceived instant: < 100 ms) |
| Corpus | Top ~1B queries by popularity, refreshed daily; trending terms within minutes |
| Personalization | Recent own searches; locale/language |

### 18.2 The core idea: precompute the top-k at every prefix

§B of the output: 58,894 queries form **437,958 trie nodes**. Precomputing the top-5 at every node costs **2.2M
pointers (~8.8 MB as 4-byte IDs)**, and every keystroke reads exactly 5 entries. Scanning and ranking at query time
would touch **1,050 candidates on average and 4,020 at p99** for 1–4 character prefixes.

**Precompute shifts all the work to the offline build, where it's cheap,** and makes the online path O(prefix
length). At 1B queries the trie is too big for one host, so:

```
 offline (daily + streaming deltas): query logs → normalize/dedupe/filter (safety) → counts with time decay →
   build trie shards with top-k per node (k ~ 10–20) → serialize (succinct/FST format) → push to serving hosts
 online: client debounce (~50–100 ms) → edge cache (prefix → suggestions, short TTL; most traffic is short prefixes)
   → serving shard chosen by PREFIX (first 1–2 characters) → read top-k → merge with personalized recent
   searches (client- or user-store side) → respond
 trending: streaming counts over 5-minute windows → small "trending overlay" trie merged at query time
```

**Partition key:**
- shard by prefix range (`a…`, `ab…`), with **replicas proportional to traffic**: short prefixes are hot;
- or shard by hash of the first two characters, replicating hot shards.

Every shard is read-only and rebuilt offline, so serving is trivially scalable and statically stable. A failed build
leaves yesterday's trie serving.

### 18.3 Failure defense

| Failure | Defense |
|---|---|
| Bad build (offensive suggestions, broken trie) | Safety filters + automatic diff checks vs the previous build before promotion; instant rollback to LKG |
| Hot prefix shard | Replicas by traffic; edge caching of 1–3 char prefixes (they are few and hot) |
| Trending manipulation | Per-source rate limits on counts; anomaly detection; human review for top suggestions |
| Latency spikes | Client debounce + cancel in-flight; hedged requests to replicas |

### 18.4 L5 / L6 / L7 and probing chain

| | L5 | L6 | L7 |
|---|---|---|---|
| Design | Trie in memory, search on each keystroke | Precomputed top-k per node, sharded by prefix, edge caching, offline builds | Offline/online split with LKG; trending overlay; safety gates on builds; replicas by prefix heat; client debounce as capacity planning |

1. **Probe:** "Query the search index with a prefix match for every keystroke." **L5:** "With an index on prefix."
2. **Probe:** "1M req/s at p99 < 50 ms." **L6:** "Precompute top-k at each trie node; shard by prefix; cache short
   prefixes at the edge."
3. **Probe:** "A news event makes a new query explode, but the trie is built daily." **L7:**
   - "Add a streaming trending overlay: windowed counts feed a small overlay trie updated every minute, merged with
     the base top-k at query time, behind safety filters."
   - "The base stays immutable and statically stable; only the overlay is dynamic, and it can be switched off."

---

## Problem 19: A distributed inverted-index search engine

### 19.1 Scope, scale and SLAs

| Quantity | Target |
|---|---|
| Corpus | 100B documents (web-scale) or 1B (product/enterprise) |
| Queries | 100k QPS |
| Latency | p99 < 200 ms including ranking |
| Freshness | Seconds to minutes for news/products; days for the long tail |

### 19.2 Index structure and the intersection cost (§C of the output)

- **Inverted index:** term → posting list of doc IDs (delta + varint/PForDelta compressed), plus positions and term
  frequencies.
- **Conjunctive (AND) queries intersect posting lists.** Intersecting a common term (19,931 postings) with a rare one
  (572) took **19,932 comparisons by linear merge** vs **5,490 by galloping from the short list**.
- Production engines use **skip lists/blocks** in postings (Lucene's multi-level skip data, block-max indexes) to
  jump similarly. **WAND / block-max WAND** skip documents that cannot enter the top-k.
- **BM25** scores documents by term frequency, inverse document frequency and length normalization. Learned ranking
  (an LTR model) re-ranks the top few hundred.

### 19.3 Partitioning: by document or by term

| | Document-partitioned (each shard indexes a subset of docs) | Term-partitioned (each shard holds the full postings of some terms) |
|---|---|---|
| Query fan-out | **All shards** (p99 = max of N shards; Folder 01 file 01 §6.4) | Only the shards holding the query's terms |
| Data shipped per query | Top-k per shard (small) | **Whole posting lists** between shards: 78 KiB for one pair in the lab; far more at web scale |
| Load balance | Even | Skewed by term popularity |
| Updates | Local to one shard | Touch many shards per document |
| Industry choice | **Almost universal** (Lucene/Elasticsearch, web search) | Rare |

Document partitioning wins because shipping posting lists is too expensive. The fan-out tail is then managed with:
- **replicas and hedged requests;**
- **tiering:** a small "top-quality" tier is searched first, and the full index only if needed;
- **partial results on deadline:** return what arrived, and mark the result "approximate".

### 19.4 Architecture

```
 crawl/ingest (problem 20, CDC from product DB) → document processing (parse, tokenize, embed) →
   index builders: near-real-time segments (Lucene-style: in-memory buffer → small segments → merged, like an LSM)
 serving: query frontend (parse, spell, rewrite, cache) → root aggregator → shard replicas (doc-partitioned,
   each: postings + doc values + optional vector index) → top-k per shard → merge → re-rank (LTR model, features)
   → snippets/hydration
 freshness: two tiers — realtime index (minutes, small) + base index (rebuilt/merged), merged at query time
```

### 19.5 The core L7 bottleneck: tail latency at fan-out, and freshness vs merge cost

- **Fan-out to hundreds of shards puts p99 at the shard p99.9.** Use replicas with **hedging after p95**, per-shard
  deadlines with partial results, and tiered retrieval.
- **Segment merges are compaction.** Near-real-time indexing creates many small segments. Merges cost I/O and CPU
  (write amplification, as in Folder 02 file 01 §2.6) and cause latency spikes. Rate-limit merges and separate
  realtime and base tiers.
- **Hybrid lexical + vector retrieval** (BM25 + ANN, fused) is the modern default. The companion AI KB covers fusion
  (RRF's failure on exact-code queries) and ANN internals.

### 19.6 Failure defense

| Failure | Defense |
|---|---|
| Slow shard | Hedged requests to another replica; outlier ejection |
| Shard unavailable | Partial results with a quality flag; replicas across AZs |
| Query of death (very expensive query) | Per-query cost limits, timeouts, circuit-break query patterns |
| Index corruption / bad build | Versioned index snapshots; roll back to LKG; canary shards |
| Merge storms | Merge throttling; off-peak scheduling; tiered indexing |

### 19.7 L5 / L6 / L7 and probing chain

| | L5 | L6 | L7 |
|---|---|---|---|
| Design | Elasticsearch cluster | Doc-partitioned shards, replicas, BM25 + LTR, NRT segments | Fan-out tail math (hedging, partial results, tiers); why term partitioning loses (postings shipping); merge cost as compaction; hybrid retrieval |

1. **Probe:** "Shard the index by term so each query hits fewer shards." **L5:** "Fewer shards, faster."
2. **Probe:** "What moves over the network for an AND query?" **L6:** "Entire posting lists for every term but one;
   for common terms that's megabytes per query."
3. **Probe:** "Then how do you control the p99 of a 500-shard fan-out?" **L7:**
   - "Document partitioning with 2–3 replicas per shard, and hedge after the shard p95 (budgeted)."
   - "A small top tier answers most queries without touching the full index."
   - "Per-shard deadlines with partial results flagged."
   - "The p99 target is set against the shard p99.9, since 1 − 0.999⁵⁰⁰ ≈ 39% of queries see at least one shard's
     p99.9."

---

## 20. The listing

```python
"""media_search_lab.py - adaptive bitrate, typeahead tries, and inverted-index intersection (Folder 07, file 02).

  A. ABR over a bursty bandwidth trace: throughput-based vs buffer-based (BBA, Huang et al. SIGCOMM 2014) with and
     without download abandonment vs throughput-with-buffer-guard. Rebuffer ratio, mean bitrate, switches.
  B. Typeahead: a trie with precomputed top-k per node vs scanning the subtree at query time.
  C. Search: AND-intersection of posting lists by linear merge vs galloping (exponential) search; BM25 top-10;
     document- vs term-partitioned sharding costs.
Standard library only; seeded, deterministic.
"""
import bisect
import collections
import math
import random
import sys

LADDER = [235, 750, 1750, 3000, 5800, 8000]                      # kbps (a typical H.264 ladder)
SEG = 4.0                                                        # seconds per segment


# ---------------------------------------------------------------- A. ABR
def bandwidth_trace(n: int, rng: random.Random) -> list[float]:
    states = [1500, 3000, 6000, 10000]
    s, out, outage = 2, [], 0
    for _ in range(n):
        if outage:
            outage -= 1
            out.append(rng.uniform(300, 700))
            continue
        if rng.random() < 0.03:
            outage = rng.randint(2, 5)                           # tunnel / congested cell: deep drop
        if rng.random() < 0.15:
            s = max(0, min(3, s + rng.choice((-1, 1))))
        out.append(states[s] * rng.uniform(0.7, 1.3))
    return out


def harmonic_estimate(history: list[float], n: int = 5) -> float:
    recent = history[-n:]
    return len(recent) / sum(1 / h for h in recent) if recent else 1000.0


def abr(policy: str, trace: list[float]) -> dict:
    buf, rebuf, history, last, switches, bits = 0.0, 0.0, [], None, 0, 0.0
    for i, bw in enumerate(trace):
        if policy == "throughput":                               # harmonic mean of the last 5 segments
            q = max([b for b in LADDER if b <= 0.8 * harmonic_estimate(history)], default=LADDER[0])
        elif policy.startswith("buffer (BBA)"):
            reservoir, cushion = 10.0, 30.0
            if buf <= reservoir:
                q = LADDER[0]
            elif buf >= reservoir + cushion:
                q = LADDER[-1]
            else:
                target = LADDER[0] + (LADDER[-1] - LADDER[0]) * (buf - reservoir) / cushion
                q = max(b for b in LADDER if b <= target)
        else:                                                    # throughput with buffer guard
            q = max([b for b in LADDER if b <= 0.8 * harmonic_estimate(history)], default=LADDER[0])
            if buf < 8:
                q = min(q, LADDER[1])
        dl = q * SEG / bw                                         # seconds to download the segment
        if policy == "buffer (BBA) + abandonment" and i > 0 and dl > buf and q > LADDER[0]:
            dl = 0.5 * buf + LADDER[0] * SEG / bw                 # give up mid-download, refetch at the lowest rung
            q = LADDER[0]
        if i > 0:
            buf -= dl
            if buf < 0:
                rebuf += -buf
                buf = 0.0
        buf = min(buf + SEG, 60.0)
        history.append(bw)
        switches += last is not None and q != last
        last = q
        bits += q
    play = len(trace) * SEG
    return {"rebuffer_ratio": rebuf / play, "mean_kbps": bits / len(trace), "switches_per_h": switches / play * 3600}


# ---------------------------------------------------------------- B. typeahead
def typeahead(rng: random.Random) -> dict:
    letters = "etaoinshrdlucmfwypvbgkjqxz"
    words = sorted({"".join(rng.choice(letters[:16]) for _ in range(rng.randint(3, 7))) for _ in range(6000)})
    queries = sorted({" ".join(rng.sample(words, rng.randint(1, 3))) for _ in range(80_000)})
    queries.sort()
    pop = {q: 1 / (r + 1) for r, q in enumerate(rng.sample(queries, len(queries)))}      # Zipf(1) popularity
    k = 5
    root: dict = {}
    nodes = 0
    for q in queries:
        node = root
        for ch in q:
            if ch not in node:
                node[ch] = {}
                nodes += 1
            node = node[ch]
        node["$"] = q
    def topk(node) -> list:                                       # post-order: merge children's top-k
        cands = [node["$"]] if "$" in node else []
        for ch, child in node.items():
            if ch not in ("$", "#"):
                cands += topk(child)
        node["#"] = sorted(cands, key=lambda x: -pop[x])[:k]
        return node["#"]
    topk(root)
    tests = [rng.choice(queries)[:rng.randint(1, 4)] for _ in range(2000)]
    scanned = []
    for p in tests:
        lo, hi = bisect.bisect_left(queries, p), bisect.bisect_right(queries, p + "￿")
        scanned.append(hi - lo)                                   # candidates a scan-at-query-time must rank
    scanned.sort()
    return {"queries": len(queries), "nodes": nodes, "precomputed_pointers": nodes * k,
            "scan_mean": sum(scanned) / len(scanned), "scan_p99": scanned[int(len(scanned) * 0.99)], "k": k}


# ---------------------------------------------------------------- C. inverted index
def build_index(docs: int, vocab: int, doc_len: int, rng: random.Random):
    cum, acc = [], 0.0
    for r in range(1, vocab + 1):
        acc += 1 / r
        cum.append(acc)
    postings = collections.defaultdict(list)
    tf = collections.defaultdict(dict)
    lengths = []
    for d in range(docs):
        terms = [bisect.bisect_left(cum, rng.random() * acc) for _ in range(doc_len)]
        lengths.append(len(terms))
        for t, c in collections.Counter(terms).items():
            postings[t].append(d)
            tf[t][d] = c
    return postings, tf, lengths


def linear_intersect(a: list, b: list) -> tuple[list, int]:
    i = j = cmp = 0
    out = []
    while i < len(a) and j < len(b):
        cmp += 1
        if a[i] == b[j]:
            out.append(a[i]); i += 1; j += 1
        elif a[i] < b[j]:
            i += 1
        else:
            j += 1
    return out, cmp


def gallop_intersect(short: list, long: list) -> tuple[list, int]:
    out, cmp, lo = [], 0, 0
    for x in short:
        step = 1
        while lo + step < len(long) and long[lo + step] < x:
            cmp += 1
            step *= 2
        hi = min(lo + step, len(long))
        pos = bisect.bisect_left(long, x, lo, hi)
        cmp += max(1, int(math.log2(max(2, hi - lo))))
        if pos < len(long) and long[pos] == x:
            out.append(x)
        lo = pos
    return out, cmp


def bm25(terms: list, docs: list, tf, postings, lengths, k1: float = 1.2, b: float = 0.75) -> list:
    n, avg = len(lengths), sum(lengths) / len(lengths)
    scores = collections.Counter()
    for t in terms:
        idf = math.log(1 + (n - len(postings[t]) + 0.5) / (len(postings[t]) + 0.5))
        for d in docs:
            f = tf[t][d]
            scores[d] += idf * f * (k1 + 1) / (f + k1 * (1 - b + b * lengths[d] / avg))
    return scores.most_common(10)


def main() -> None:
    sys.setrecursionlimit(10_000)                                 # trie depth = longest query length
    rng = random.Random(16)
    print("== A. ABR: 50 sessions x 600 segments (4 s), bursty cellular-like bandwidth, ladder 235-8000 kbps")
    totals = {p: collections.Counter() for p in ("throughput", "buffer (BBA)", "buffer (BBA) + abandonment",
                                                 "throughput + buffer guard")}
    for s in range(50):
        trace = bandwidth_trace(600, random.Random(1000 + s))
        for p in totals:
            for k, v in abr(p, trace).items():
                totals[p][k] += v / 50
    for p, r in totals.items():
        print(f"  {p:<26} rebuffer {r['rebuffer_ratio'] * 100:5.2f}% of play time   mean {r['mean_kbps']:6.0f} kbps   "
              f"switches {r['switches_per_h']:5.0f}/h")

    print("\n== B. typeahead trie with top-5 precomputed per node")
    ta = typeahead(rng)
    print(f"  {ta['queries']:,} queries -> {ta['nodes']:,} trie nodes, {ta['precomputed_pointers']:,} precomputed "
          f"pointers (~{ta['precomputed_pointers'] * 4 / 1e6:.1f} MB as 4-byte IDs)")
    print(f"  per keystroke: precomputed = read {ta['k']} entries; scan-and-rank would touch "
          f"mean {ta['scan_mean']:,.0f}, p99 {ta['scan_p99']:,} candidates for 1-4 character prefixes")

    print("\n== C. inverted index: 20,000 docs x 120 tokens, Zipf vocabulary of 30,000 terms")
    postings, tf, lengths = build_index(20_000, 30_000, 120, rng)
    common, rare = postings[1], postings[400]
    lin_res, lin_cmp = linear_intersect(common, rare)
    gal_res, gal_cmp = gallop_intersect(rare, common)
    print(f"  AND(common term: {len(common):,} postings, rare term: {len(rare):,} postings) -> {len(lin_res)} docs")
    print(f"  comparisons: linear merge {lin_cmp:,} vs galloping from the short list {gal_cmp:,}")
    top = bm25([1, 400], lin_res, tf, postings, lengths)
    print(f"  BM25 top-3 (doc, score): {[(d, round(s, 3)) for d, s in top[:3]]}")
    shards = 16
    print(f"  {shards} document-partitioned shards: every query fans out to {shards} shards (p99 = max of {shards}); "
          f"term-partitioned: 2 shards, but {len(common) * 4 / 1024:.0f} KiB of postings shipped per query for this pair")

    bba, thr, aban = totals["buffer (BBA)"], totals["throughput"], totals["buffer (BBA) + abandonment"]
    assert bba["mean_kbps"] > thr["mean_kbps"] and aban["rebuffer_ratio"] < bba["rebuffer_ratio"]
    assert totals["throughput + buffer guard"]["rebuffer_ratio"] < thr["rebuffer_ratio"]
    assert ta["scan_mean"] > 50 * ta["k"]
    assert lin_res == gal_res and gal_cmp < lin_cmp / 3
    print("\nself-test: all assertions passed")


if __name__ == "__main__":
    main()
```

Output (verified; deterministic):

```text
== A. ABR: 50 sessions x 600 segments (4 s), bursty cellular-like bandwidth, ladder 235-8000 kbps
  throughput                 rebuffer  2.14% of play time   mean   2554 kbps   switches   172/h
  buffer (BBA)               rebuffer  5.06% of play time   mean   3596 kbps   switches   279/h
  buffer (BBA) + abandonment rebuffer  0.00% of play time   mean   3576 kbps   switches   301/h
  throughput + buffer guard  rebuffer  1.82% of play time   mean   2544 kbps   switches   171/h

== B. typeahead trie with top-5 precomputed per node
  58,894 queries -> 437,958 trie nodes, 2,189,790 precomputed pointers (~8.8 MB as 4-byte IDs)
  per keystroke: precomputed = read 5 entries; scan-and-rank would touch mean 1,050, p99 4,020 candidates for 1-4 character prefixes

== C. inverted index: 20,000 docs x 120 tokens, Zipf vocabulary of 30,000 terms
  AND(common term: 19,931 postings, rare term: 572 postings) -> 571 docs
  comparisons: linear merge 19,932 vs galloping from the short list 5,490
  BM25 top-3 (doc, score): [(7698, 4.893), (14755, 4.892), (14822, 4.892)]
  16 document-partitioned shards: every query fans out to 16 shards (p99 = max of 16); term-partitioned: 2 shards, but 78 KiB of postings shipped per query for this pair

self-test: all assertions passed
```

---

## 21. References for problems 16–19

- T.-Y. Huang et al. *A Buffer-Based Approach to Rate Adaptation: Evidence from a Large Video Streaming Service.*
  SIGCOMM 2014.
- K. Spiteri, R. Urgaonkar, R. Sitaraman. *BOLA: Near-Optimal Bitrate Adaptation for Online Videos.* INFOCOM 2016.
- X. Yin et al. *A Control-Theoretic Approach for Dynamic Adaptive Video Streaming over HTTP (MPC).* SIGCOMM 2015.
- Netflix TechBlog. *Per-Title Encode Optimization*, 2015; *Dynamic optimizer — a perceptual video encoding
  optimization framework*, 2018. VMAF (github.com/Netflix/vmaf).
- RFC 8216bis / Apple LL-HLS specification; CMAF (ISO/IEC 23000-19).
- S. Brin, L. Page. *The Anatomy of a Large-Scale Hypertextual Web Search Engine.* WWW 1998. J. Dean, *Challenges
  in Building Large-Scale Information Retrieval Systems*, WSDM 2009 keynote.
- S. Robertson, H. Zaragoza. *The Probabilistic Relevance Framework: BM25 and Beyond.* FnTIR 2009. A. Broder et al.,
  *Efficient query evaluation using a two-level retrieval process (WAND)*, CIKM 2003.
- LinkedIn Engineering, *Typeahead* (Cleo), and Elastic/Lucene documentation on segments, merges and skip lists.
