# 02 · DiskANN: Vamana, RobustPrune, PQ in RAM, and NVMe Beam Search

> **Folder:** `03-Vector-DB-Internals-HNSW-DiskANN-and-Hybrid-Index/` · **File 2 of 3**
> **Anchoring papers:** Subramanya, Devvrit, Kadekodi, Krishnaswamy & Simhadri, *DiskANN: Fast Accurate Billion-point
> Nearest Neighbor Search on a Single Node* (NeurIPS 2019) · Jégou, Douze & Schmid, *Product Quantization for Nearest
> Neighbor Search* (TPAMI 2011) · Singh et al., *FreshDiskANN* (2021) · Gollapudi et al., *Filtered-DiskANN* (WWW
> 2023) · Jayaram Subramanya et al. / Microsoft DiskANN repository · Linux `io_uring` (Axboe, 2019).
> **Code baseline:** Python 3.10+ (CPython 3.14.5 + NumPy 2.5.4) · Java 21 (JDK 25.0.4, `--release 21`).
> **Previous:** [01 · HNSW](01-hnsw-skip-list-graphs-memory-math-and-filtered-search-traps.md) ·
> **Next:** [03 · IVF-PQ, scalar/binary quantization, and engine comparison](03-ivf-pq-scalar-binary-quantization-and-pgvector-vs-qdrant-milvus.md)

---

## 0. The thesis in one paragraph

HNSW keeps everything in RAM. At a billion 768-d vectors that is ~3 TiB, a rack of memory-optimized servers for one
index. DiskANN's insight splits the data by **access pattern**:

- **RAM holds only what navigation needs:** a compressed sketch of every vector (product-quantized, 32–64 bytes), used
  to rank candidates.
- **The SSD holds what only the final hops need:** full-precision vectors and adjacency lists, co-located in 4 KB
  sectors so that **one read returns both**.
- **The graph (Vamana)** is built with RobustPrune and α > 1, which keeps long-range edges. A search therefore
  converges in a few dozen SSD hops.
- **The search issues several reads per hop in parallel** (beam width W), so latency is a handful of NVMe round trips.

The paper served a billion SIFT points on one 64 GB-RAM workstation at > 5,000 QPS with < 3 ms mean latency and
95%+ 1-recall@1. An L7 engineer knows each of the three choices (PQ in RAM, sector co-location, beam width) and what
breaks when any one is missing.

---

## 1. Vamana: building a graph you can walk on disk

### 1.1 RobustPrune and the role of α

For node $p$ with candidate set $V$:

```
RobustPrune(p, V, α, R):
    V ← V \ {p};  N_out(p) ← ∅
    while V ≠ ∅ and |N_out(p)| < R:
        p* ← argmin_{v ∈ V} d(p, v)                     # keep the closest remaining candidate
        N_out(p) ← N_out(p) ∪ {p*}
        for v' in V:
            if α · d(p*, v') ≤ d(p, v'):  remove v'      # v' is "covered" by p*: reachable through it
    return N_out(p)
```

With $\alpha = 1$ this is the HNSW-style diversity rule: drop $v'$ if $p^*$ is closer to it than $p$ is. With $\alpha > 1$
the condition is **harder** to meet, so fewer candidates are pruned. Longer edges survive, and each greedy step makes
at least a constant-factor ($\alpha$) progress toward the query. The paper proves this gives logarithmic-ish hop
counts and small diameter. Measured on the Python reference (5,000 × 32, R=24):

| Build | Mean degree | Mean edge length | Greedy hops to converge |
|-------|------------:|-----------------:|------------------------:|
| α = 1.0 only | 10.0 | 7.84 | 5.5 |
| α = 1.0, then **α = 1.2** (paper) | **18.7** | **8.15** | **5.0** |

The α = 1 graph is sparse (degree 10, well under R = 24) and short-edged. The second α = 1.2 pass roughly doubles the
degree with longer edges and cuts hops. On a billion points and an SSD, where every hop is a 100 µs read, that
difference is the product.

### 1.2 The build loop

```
initialize G as a random R-regular graph;  s ← medoid
for α_pass in (1.0, α):
    for p in random permutation:
        V_visited ← GreedySearch(s, x_p, L).expanded
        N_out(p) ← RobustPrune(p, V_visited ∪ N_out(p), α_pass, R)
        for j in N_out(p):                                 # make edges bidirectional...
            N_out(j) ← N_out(j) ∪ {p}
            if |N_out(j)| > R:  N_out(j) ← RobustPrune(j, N_out(j), α_pass, R)   # ...within degree R
```

Billion-scale builds don't fit in RAM either. DiskANN partitions the data into overlapping clusters (each point
assigned to its 2 closest k-means centers), builds a Vamana graph per partition in memory, and **merges** the edge
sets. Overlap keeps the merged graph navigable.

---

## 2. Product quantization: the RAM-resident sketch

### 2.1 The encoding

Split the $d$-dimensional space into $m$ sub-spaces of $d/m$ dimensions. Run k-means with 256 centroids in each, and
store each vector as $m$ bytes (one centroid id per sub-space):

$$
x \approx [\,c^{(1)}_{i_1};\, c^{(2)}_{i_2};\, \dots;\, c^{(m)}_{i_m}\,],\qquad \text{bytes/vector} = m .
$$

### 2.2 Asymmetric distance computation (ADC)

Per query, precompute a table $T[j][c] = \|q^{(j)} - c^{(j)}_c\|^2$ ($m \times 256$ floats). The approximate distance
to any database vector is then $m$ table lookups and adds:

$$
\hat d(q, x)^2 = \sum_{j=1}^{m} T\big[j\big]\big[i_j(x)\big],
$$

which costs $m$ byte loads instead of $d$ multiply-adds. It is cache-resident and SIMD-friendly (FAISS's "fast scan"
packs 4-bit codes into registers).

### 2.3 PQ steers; it does not decide

Ranking by PQ distance alone, **exhaustively** over all 5,000 vectors (m = 16, 6.2% reconstruction error), gives only
**0.770** recall@10. PQ is a navigation heuristic. The final answer must be **re-ranked with full-precision vectors**,
and DiskANN gets those vectors for free with every sector read. In the reference, beam search plus re-ranking reaches
1.000 recall while touching only ~53–68 sectors per query.

---

## 3. The on-disk layout and the beam search

### 3.1 Sector co-location

Each node's record is $[\text{full vector} \,|\, \text{degree} \,|\, R \text{ neighbor ids}]$, packed into 4 KB
sectors (the NVMe read unit):

| d | R | Record | Packing |
|--:|--:|-------:|---------|
| 96 | 32 | 516 B | 7 nodes/sector (484 B slack) |
| 128 | 64 | 772 B | 5 nodes/sector (236 B slack) |
| 768 | 64 | 3,332 B | 1 node/sector (764 B slack) |
| 1,536 | 64 | 6,404 B | **spans 2 sectors**: every hop is an 8 KB read |

One read per expanded node delivers the vector (for re-ranking) **and** the neighbor ids (for the next hop). For
1,536-d embeddings each hop doubles its I/O. That is an argument for float16/int8 on-disk vectors, or for Matryoshka
truncation (File 03), at billion scale.

### 3.2 Beam search with W parallel reads

```
candidates ← {medoid: PQ-dist}          (RAM)
expanded   ← {}                         (full-precision distances, from sectors)
repeat:
    B ← up to W closest un-expanded candidates among the best L
    if B empty: break
    issue |B| sector reads concurrently          # one NVMe round trip (io_uring / async I/O)
    for p in B: expanded[p] ← exact d(q, x_p);  add N_out(p) to candidates with PQ distances
return top-k of expanded by exact distance       # implicit re-ranking
```

The **beam width W** trades a few extra reads for many fewer round trips. NVMe random-read latency is ~100 µs at low
queue depth, but an NVMe drive sustains hundreds of thousands of IOPS when queues are deep, so concurrency is nearly
free while serial round trips are expensive.

| Python reference (L=50) | Recall@10 | Round trips | 4 KB reads | Latency at 100 µs/round |
|------------------------:|----------:|------------:|-----------:|------------------------:|
| W = 1 | 1.000 | 53.1 | 53.1 | 5.31 ms |
| W = 2 | 1.000 | 28.1 | 54.8 | 2.81 ms |
| **W = 4** | 1.000 | **15.9** | 58.8 | **1.59 ms** |
| W = 8 | 1.000 | 9.9 | 67.8 | 0.99 ms |

The Java listing does it for real. It writes an 8,000 × 128-d Vamana index to a 5.5 MB sector file, keeps 32-byte PQ
codes in RAM (16× smaller than float32), and serves each round's reads as concurrent `FileChannel` positional reads on
virtual threads. It lands at recall 0.980, and **W = 4 needs 3.7× fewer round trips than W = 1** for 6% more reads.
Measured times are page-cache-hot. The 100 µs/round model is what an SSD would add.

### 3.3 Why PQ-in-RAM is not optional

The naive alternative keeps no compressed vectors in RAM, so scoring a candidate requires its full vector, which
means its sector. In the Java run that is **361 records fetched per query vs 106 reads** for the PQ design (3.4×). Two
things hide part of the cost in this run: 6 nodes share each sector at 128-d, so the naive search reads 24% of the
whole file *per query*, and the cache is warm. At 768-d (one node per sector) every fetched record is its own 4 KB
read. Worse, those reads are **serial dependencies**: the next hop can't be chosen until the candidates' distances are
known. PQ makes candidate scoring free (RAM) and leaves I/O only for expansion, which the beam parallelizes.

### 3.4 The billion-scale budget

| Component (10⁹ × 768-d) | Size |
|-------------------------|-----:|
| HNSW M=16, float32 in RAM | **~3,007 GiB RAM** |
| DiskANN PQ codes, 32 B/vector | **~30 GiB RAM** |
| DiskANN PQ codes, 64 B/vector | ~60 GiB RAM |
| DiskANN sector file (1 node/sector) | ~3.7 TiB NVMe |

RAM drops ~50–100×, and the bytes move to NVMe, which costs ~10–30× less per GB than DRAM and holds 4–8 drives per
server. The cost moves from DRAM to IOPS. A node must sustain QPS × reads/query × 4 KB: at 5,000 QPS and ~60 reads
that is 300K IOPS and ~1.2 GB/s, within a couple of modern NVMe drives. Size the drives on random-read IOPS at the
target queue depth, not on capacity.

---

## 4. Updates, filters, and the systems around it

- **FreshDiskANN.** Inserts go to an in-memory Vamana delta index. Deletes are tombstones. A background
  **StreamingMerge** periodically consolidates delta and deletes into the SSD index, repairing neighborhoods of deleted
  nodes. Query = SSD index ∪ delta, minus tombstones.
- **Filtered-DiskANN.** Labels are built into the graph. *FilteredVamana* guarantees that the subgraph for each label
  is navigable (label-aware RobustPrune). *StitchedVamana* builds per-label graphs and stitches them together. This is
  the disk-based counterpart to File 01's ACORN discussion. Filtering is solved at index-build time, not with a
  query-time patch.
- **Where it ships:** the open-source DiskANN library (Rust/C++), and DiskANN-family indexes in several databases and
  cloud services (Milvus offers a `DISKANN` index type; ⚠ verify the current engine list and parameters before
  quoting).
- **What the I/O path needs:** `O_DIRECT` reads (bypass the page cache, or it competes with RAM), 4 KB-aligned
  buffers, deep queues (`io_uring`), and NUMA-aware thread placement. Production profiles look like storage systems,
  not ML systems.

---

## 5. Production code blueprints

### 5.1 Python: Vamana, PQ/ADC, beam search with I/O accounting, layout and budget math

```python
"""diskann_ref.py - DiskANN from the paper (Subramanya et al., NeurIPS 2019), in NumPy.

* Vamana: random R-regular init, medoid entry, two passes (alpha = 1, then alpha > 1) of greedy search +
  RobustPrune, reverse edges re-pruned to degree R;
* product quantization: m sub-spaces x 256 centroids (k-means), ADC lookup tables per query;
* "SSD" beam search: PQ codes in RAM steer the search; every node expansion costs one sector read that returns
  the full vector (for re-ranking) and the adjacency list; W reads per round = one I/O round trip;
* RAM/SSD math for a billion points and the 4 KB sector layout.
"""
from __future__ import annotations

import heapq

import numpy as np


def l2(a: np.ndarray, b: np.ndarray) -> np.ndarray:
    d = b - a
    return np.einsum("ij,ij->i", d, d) if d.ndim == 2 else float(d @ d)


class Vamana:
    def __init__(self, x: np.ndarray, R: int = 24, L: int = 60, alpha: float = 1.2, seed: int = 0):
        self.x, self.R, self.L, self.alpha = x, R, L, alpha
        n = len(x)
        rng = np.random.default_rng(seed)
        self.nbrs = [list(rng.choice(n, R, replace=False)) for _ in range(n)]
        for i in range(n):
            self.nbrs[i] = [j for j in self.nbrs[i] if j != i]
        self.medoid = int(np.argmin(l2(x.mean(0), x)))
        self.evals = 0
        for a in (1.0, alpha):                                  # paper: first pass alpha=1, second alpha>1
            for p in rng.permutation(n):
                _, visited = self.greedy(x[p], 1, L)
                self.nbrs[p] = self.robust_prune(int(p), visited | set(self.nbrs[p]), a)
                for j in self.nbrs[p]:
                    if p not in self.nbrs[j]:
                        self.nbrs[j].append(int(p))
                        if len(self.nbrs[j]) > R:
                            self.nbrs[j] = self.robust_prune(j, set(self.nbrs[j]), a)

    def dist(self, q: np.ndarray, ids: list[int]) -> np.ndarray:
        self.evals += len(ids)
        return l2(q, self.x[ids])

    def greedy(self, q: np.ndarray, k: int, L: int) -> tuple[list[int], set[int]]:
        """GreedySearch(s, q, k, L): returns the k closest found and the set of expanded (visited) nodes."""
        start = self.medoid
        lst = {start: float(self.dist(q, [start])[0])}
        expanded: set[int] = set()
        while True:
            frontier = [i for i in sorted(lst, key=lst.get)[:L] if i not in expanded]
            if not frontier:
                break
            p = frontier[0]
            expanded.add(p)
            new = [j for j in self.nbrs[p] if j not in lst]
            if new:
                for j, dj in zip(new, self.dist(q, new)):
                    lst[j] = float(dj)
            if len(lst) > L:
                lst = dict(sorted(lst.items(), key=lambda kv: kv[1])[:L])
        return sorted(lst, key=lst.get)[:k], expanded

    def robust_prune(self, p: int, cand: set[int], alpha: float) -> list[int]:
        """RobustPrune: take the closest remaining v; drop every u with alpha * d(v, u) <= d(p, u)."""
        cand = [c for c in cand if c != p]
        dp = dict(zip(cand, self.dist(self.x[p], cand).tolist())) if cand else {}
        out: list[int] = []
        while dp and len(out) < self.R:
            v = min(dp, key=dp.get)
            out.append(v)
            del dp[v]
            if not dp:
                break
            rest = list(dp)
            dv = self.dist(self.x[v], rest)
            for u, duv in zip(rest, dv):
                if alpha * duv <= dp[u]:
                    del dp[u]
        return out


class PQ:
    def __init__(self, x: np.ndarray, m: int, iters: int = 12, seed: int = 0):
        n, d = x.shape
        assert d % m == 0
        self.m, self.ds = m, d // m
        rng = np.random.default_rng(seed)
        self.cent = np.zeros((m, 256, self.ds), dtype=np.float32)
        self.codes = np.zeros((n, m), dtype=np.uint8)
        for j in range(m):
            sub = x[:, j * self.ds:(j + 1) * self.ds]
            c = sub[rng.choice(n, 256, replace=False)].copy()
            for _ in range(iters):                               # Lloyd's k-means
                a = np.argmin(((sub[:, None, :] - c[None]) ** 2).sum(-1), axis=1)
                for k in range(256):
                    pts = sub[a == k]
                    if len(pts):
                        c[k] = pts.mean(0)
            self.cent[j] = c
            self.codes[:, j] = np.argmin(((sub[:, None, :] - c[None]) ** 2).sum(-1), axis=1)

    def table(self, q: np.ndarray) -> np.ndarray:
        """ADC: squared distance from each query sub-vector to all 256 centroids -> [m, 256]."""
        qs = q.reshape(self.m, 1, self.ds)
        return ((self.cent - qs) ** 2).sum(-1)

    def adc(self, tab: np.ndarray, ids) -> np.ndarray:
        return tab[np.arange(self.m), self.codes[ids]].sum(-1)


def disk_search(g: Vamana, pq: PQ, q: np.ndarray, k: int, L: int, W: int):
    """Beam search: PQ distances (RAM) rank candidates; each round reads <= W sectors (one round trip).
    Expanded nodes' full vectors (read with their sector) re-rank the final answer."""
    tab = pq.table(q)
    cand = {g.medoid: float(pq.adc(tab, [g.medoid])[0])}
    expanded: dict[int, float] = {}
    rounds = ios = 0
    while True:
        top = [i for i in sorted(cand, key=cand.get)[:L] if i not in expanded][:W]
        if not top:
            break
        rounds += 1
        ios += len(top)                                         # W parallel 4 KB reads
        for p in top:
            expanded[p] = l2(q, g.x[p])                         # full vector came with the sector
            new = [j for j in g.nbrs[p] if j not in cand]
            if new:
                for j, dj in zip(new, pq.adc(tab, new)):
                    cand[j] = float(dj)
        if len(cand) > 4 * L:
            cand = dict(sorted(cand.items(), key=lambda kv: kv[1])[:4 * L])
    ranked = sorted(expanded, key=expanded.get)[:k]
    return ranked, rounds, ios


def sector_layout(d: int, R: int, bytes_per_dim: int = 4, sector: int = 4096) -> tuple[int, int]:
    rec = d * bytes_per_dim + 4 + R * 4                         # vector + degree + R neighbor ids
    return rec, sector // rec                                   # 0 => one node spans several sectors


def main() -> None:
    rng = np.random.default_rng(1)
    n, d = 5000, 32
    centers = rng.standard_normal((25, d)).astype(np.float32) * 4
    x = centers[rng.integers(0, 25, n)] + rng.standard_normal((n, d)).astype(np.float32)
    queries = x[rng.choice(n, 100, replace=False)] + rng.standard_normal((100, d)).astype(np.float32) * 0.5
    truth = [set(np.argsort(l2(q, x))[:10].tolist()) for q in queries]

    graphs = {a: Vamana(x, R=24, L=60, alpha=a, seed=2) for a in (1.0, 1.2)}
    for a, g in graphs.items():
        deg = np.mean([len(v) for v in g.nbrs])
        edge = np.mean([np.sqrt(l2(x[i], x[g.nbrs[i]])).mean() for i in range(n)])
        hops = np.mean([len(g.greedy(q, 10, 1)[1]) for q in queries])
        print(f"Vamana alpha={a}: mean degree {deg:4.1f}, mean edge length {edge:5.2f}, "
              f"greedy hops to converge (L=1) {hops:5.1f}")
    assert np.mean([len(graphs[1.2].greedy(q, 10, 1)[1]) for q in queries]) <= \
        np.mean([len(graphs[1.0].greedy(q, 10, 1)[1]) for q in queries])

    pq = PQ(x, m=16)                                            # 16 bytes per vector in RAM (vs 128 B float32)
    recon = np.concatenate([pq.cent[j][pq.codes[:, j]] for j in range(pq.m)], axis=1)
    print(f"\nPQ m={pq.m} x 8 bits: {pq.m} B/vector in RAM vs {d * 4} B float32 ({d * 4 // pq.m}x); "
          f"relative reconstruction error {np.linalg.norm(recon - x) / np.linalg.norm(x):.3f}")

    g = graphs[1.2]
    print("\n== SSD beam search (alpha=1.2, L=50): recall@10, round trips and 4 KB reads per query ==")
    print(f"{'W':>3} {'recall@10':>10} {'rounds':>7} {'reads':>6} {'latency @100us/round':>21}")
    res = {}
    for W in (1, 2, 4, 8):
        rec, rounds, ios = [], [], []
        for q, t in zip(queries, truth):
            got, r, io = disk_search(g, pq, q, 10, 50, W)
            rec.append(len(set(got) & t) / 10)
            rounds.append(r)
            ios.append(io)
        res[W] = (np.mean(rec), np.mean(rounds), np.mean(ios))
        print(f"{W:3d} {res[W][0]:10.3f} {res[W][1]:7.1f} {res[W][2]:6.1f} {res[W][1] * 0.1:18.2f} ms")
    assert res[4][0] > 0.9 and res[4][1] < res[1][1] / 2.5, "beam width trades a few extra reads for 3x fewer round trips"
    pq_only = []
    for q, t in zip(queries, truth):
        tab = pq.table(q)
        pq_only.append(len(set(np.argsort(pq.adc(tab, np.arange(n)))[:10].tolist()) & t) / 10)
    print(f"  re-ranking matters: ranking by PQ distance alone (exhaustive!) gives recall@10 {np.mean(pq_only):.3f}")

    print("\n== Sector layout (4 KB sectors, float32 vectors + degree + R ids) ==")
    for dd, R in ((128, 64), (768, 64), (1536, 64), (96, 32)):
        rec_b, per = sector_layout(dd, R)
        if per:
            print(f"  d={dd:5d} R={R}: record {rec_b:5d} B -> {per} node(s)/sector, {4096 - per * rec_b:5d} B slack")
        else:
            spans = -(-rec_b // 4096)
            print(f"  d={dd:5d} R={R}: record {rec_b:5d} B -> spans {spans} sectors per node "
                  f"({spans * 4096 - rec_b} B slack; every hop is a {spans * 4} KB read)")

    print("\n== RAM at one billion vectors (768-d) ==")
    hnsw = (768 * 4 + 8 * 16 + 4 + 20 + 68 / 15) * 1e9
    for name, b in (("HNSW M=16, float32 in RAM", hnsw), ("DiskANN: PQ 32 B/vector in RAM", 32e9),
                    ("DiskANN: PQ 64 B/vector in RAM", 64e9)):
        print(f"  {name:32s} {b / 2**30:9,.0f} GiB")
    print(f"  DiskANN SSD footprint (768-d float32 + R=64 ids, 1 node/sector): {1e9 * 4096 / 2**40:,.1f} TiB")
    print("\nall DiskANN self-checks passed")


if __name__ == "__main__":
    main()
```

Output (verified, deterministic):

```text
Vamana alpha=1.0: mean degree 10.0, mean edge length  7.84, greedy hops to converge (L=1)   5.5
Vamana alpha=1.2: mean degree 18.7, mean edge length  8.15, greedy hops to converge (L=1)   5.0

PQ m=16 x 8 bits: 16 B/vector in RAM vs 128 B float32 (8x); relative reconstruction error 0.062

== SSD beam search (alpha=1.2, L=50): recall@10, round trips and 4 KB reads per query ==
  W  recall@10  rounds  reads  latency @100us/round
  1      1.000    53.1   53.1               5.31 ms
  2      1.000    28.1   54.8               2.81 ms
  4      1.000    15.9   58.8               1.59 ms
  8      1.000     9.9   67.8               0.99 ms
  re-ranking matters: ranking by PQ distance alone (exhaustive!) gives recall@10 0.770

== Sector layout (4 KB sectors, float32 vectors + degree + R ids) ==
  d=  128 R=64: record   772 B -> 5 node(s)/sector,   236 B slack
  d=  768 R=64: record  3332 B -> 1 node(s)/sector,   764 B slack
  d= 1536 R=64: record  6404 B -> spans 2 sectors per node (1788 B slack; every hop is a 8 KB read)
  d=   96 R=32: record   516 B -> 7 node(s)/sector,   484 B slack

== RAM at one billion vectors (768-d) ==
  HNSW M=16, float32 in RAM            3,007 GiB
  DiskANN: PQ 32 B/vector in RAM          30 GiB
  DiskANN: PQ 64 B/vector in RAM          60 GiB
  DiskANN SSD footprint (768-d float32 + R=64 ids, 1 node/sector): 3.7 TiB

all DiskANN self-checks passed
```

### 5.2 Java 21: a real sector file, PQ in RAM, concurrent positional reads on virtual threads

Points to notice in the code:

- **One `FileChannel`, many virtual threads.** Positional `read(buf, position)` calls are thread-safe and don't move a
  shared file pointer, so each round's W reads run concurrently. That is the JDK-level analogue of submitting W SQEs
  to `io_uring`. On Linux, a production engine adds `O_DIRECT` and aligned buffers. The JDK exposes
  `ExtendedOpenOption.DIRECT` (⚠ platform support varies).
- **A per-query sector cache** deduplicates reads when neighbors share a sector.
- **Little-endian fixed-width records** at `id % perSector × recBytes`: no pointers, no serialization framework, and
  byte-compatible with a C++/Rust reader.
- The naive `searchNaive` is the same algorithm without RAM-resident PQ.

The listing reuses `HnswFilteredSearch.recall` from File 01, so compile both together.

```java
// DiskBeamSearch.java - Java 21 DiskANN-style search over a REAL sector file: a Vamana graph (RobustPrune, alpha),
// full-precision vectors + adjacency packed into 4 KB sectors on disk, PQ codes in RAM, and beam search that issues
// W concurrent positional reads per round on virtual threads (the io_uring pattern). A naive variant without PQ in
// RAM must read a sector for every candidate it scores.
// Build & self-test:  javac --release 21 -Xlint:all -Werror -d out DiskBeamSearch.java
//                     java -ea -cp out dev.l7.ai.inference.DiskBeamSearch
package dev.l7.ai.inference;

import java.io.IOException;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.channels.FileChannel;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardOpenOption;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Random;
import java.util.Set;
import java.util.concurrent.Callable;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;

public final class DiskBeamSearch implements AutoCloseable {

    static final int SECTOR = 4096;

    static float l2(float[] a, int ao, float[] b, int bo, int d) {
        float s = 0;
        for (int i = 0; i < d; i++) {
            float t = a[ao + i] - b[bo + i];
            s += t * t;
        }
        return s;
    }

    // ------------------------------------------------------------------ Vamana build (in RAM, offline)
    static int[][] vamana(float[] x, int n, int d, int r, int l, double alpha, long seed) {
        Random rnd = new Random(seed);
        int[][] g = new int[n][];
        for (int i = 0; i < n; i++) {
            Set<Integer> s = new HashSet<>();
            while (s.size() < r) {
                int j = rnd.nextInt(n);
                if (j != i) s.add(j);
            }
            g[i] = s.stream().mapToInt(Integer::intValue).toArray();
        }
        int medoid = medoid(x, n, d);
        for (double a : new double[] {1.0, alpha}) {
            int[] perm = new int[n];
            for (int i = 0; i < n; i++) perm[i] = i;
            for (int i = n - 1; i > 0; i--) {
                int j = rnd.nextInt(i + 1);
                int t = perm[i]; perm[i] = perm[j]; perm[j] = t;
            }
            for (int p : perm) {
                Set<Integer> cand = greedyVisited(x, d, g, medoid, x, p * d, l);
                for (int j : g[p]) cand.add(j);
                g[p] = robustPrune(x, d, p, cand, a, r);
                for (int j : g[p]) {
                    if (Arrays.stream(g[j]).noneMatch(v -> v == p)) {
                        int[] grown = Arrays.copyOf(g[j], g[j].length + 1);
                        grown[g[j].length] = p;
                        if (grown.length > r) {
                            Set<Integer> s = new HashSet<>();
                            for (int v : grown) s.add(v);
                            grown = robustPrune(x, d, j, s, a, r);
                        }
                        g[j] = grown;
                    }
                }
            }
        }
        return g;
    }

    static int medoid(float[] x, int n, int d) {
        float[] mean = new float[d];
        for (int i = 0; i < n; i++) for (int j = 0; j < d; j++) mean[j] += x[i * d + j] / n;
        int best = 0;
        float bd = Float.MAX_VALUE;
        for (int i = 0; i < n; i++) {
            float dd = l2(mean, 0, x, i * d, d);
            if (dd < bd) { bd = dd; best = i; }
        }
        return best;
    }

    static Set<Integer> greedyVisited(float[] x, int d, int[][] g, int start, float[] q, int qo, int l) {
        Map<Integer, Float> lst = new HashMap<>();
        lst.put(start, l2(q, qo, x, start * d, d));
        Set<Integer> expanded = new HashSet<>();
        while (true) {
            Integer next = lst.entrySet().stream().sorted(Map.Entry.comparingByValue()).limit(l)
                    .map(Map.Entry::getKey).filter(i -> !expanded.contains(i)).findFirst().orElse(null);
            if (next == null) return expanded;
            expanded.add(next);
            for (int j : g[next]) lst.computeIfAbsent(j, k -> l2(q, qo, x, k * d, d));
            if (lst.size() > 2 * l) {
                List<Map.Entry<Integer, Float>> keep = lst.entrySet().stream().sorted(Map.Entry.comparingByValue())
                        .limit(l).toList();
                Map<Integer, Float> trimmed = new HashMap<>();
                for (var e : keep) trimmed.put(e.getKey(), e.getValue());
                for (int e : expanded) trimmed.computeIfAbsent(e, k -> l2(q, qo, x, k * d, d));
                lst = trimmed;
            }
        }
    }

    /** RobustPrune: repeatedly keep the closest v, discard every u with alpha * d(v,u) <= d(p,u). */
    static int[] robustPrune(float[] x, int d, int p, Set<Integer> cand, double alpha, int r) {
        List<Integer> c = new ArrayList<>(cand);
        c.remove(Integer.valueOf(p));
        Map<Integer, Float> dp = new HashMap<>();
        for (int v : c) dp.put(v, l2(x, p * d, x, v * d, d));
        List<Integer> out = new ArrayList<>();
        while (!dp.isEmpty() && out.size() < r) {
            int v = dp.entrySet().stream().min(Map.Entry.comparingByValue()).orElseThrow().getKey();
            out.add(v);
            dp.remove(v);
            dp.entrySet().removeIf(e -> alpha * l2(x, v * d, x, e.getKey() * d, d) <= e.getValue());
        }
        return out.stream().mapToInt(Integer::intValue).toArray();
    }

    // ------------------------------------------------------------------ PQ (RAM-resident codes)
    final int m, ds;
    final float[] cent;      // [m][256][ds]
    final byte[] codes;      // [n][m]

    // ------------------------------------------------------------------ on-disk layout
    final int n, d, r, recBytes, perSector, medoid;
    final FileChannel ch;
    final Path file;

    DiskBeamSearch(float[] x, int n, int d, int r, int[][] g, int m, Path file, long seed) throws IOException {
        this.n = n;
        this.d = d;
        this.r = r;
        this.m = m;
        this.ds = d / m;
        this.file = file;
        this.recBytes = d * 4 + 4 + r * 4;
        this.perSector = SECTOR / recBytes;
        if (perSector < 1) throw new IllegalArgumentException("record larger than a sector");
        this.medoid = medoid(x, n, d);
        this.cent = new float[m * 256 * ds];
        this.codes = new byte[n * m];
        trainPq(x, seed);
        try (FileChannel w = FileChannel.open(file, StandardOpenOption.CREATE, StandardOpenOption.TRUNCATE_EXISTING,
                StandardOpenOption.WRITE)) {
            int sectors = (n + perSector - 1) / perSector;
            for (int s = 0; s < sectors; s++) {
                ByteBuffer buf = ByteBuffer.allocate(SECTOR).order(ByteOrder.LITTLE_ENDIAN);
                for (int k = 0; k < perSector && s * perSector + k < n; k++) {
                    int id = s * perSector + k;
                    buf.position(k * recBytes);
                    for (int j = 0; j < d; j++) buf.putFloat(x[id * d + j]);
                    buf.putInt(g[id].length);
                    for (int j = 0; j < r; j++) buf.putInt(j < g[id].length ? g[id][j] : -1);
                }
                buf.position(0).limit(SECTOR);
                w.write(buf, (long) s * SECTOR);
            }
        }
        this.ch = FileChannel.open(file, StandardOpenOption.READ);
    }

    private void trainPq(float[] x, long seed) {
        Random rnd = new Random(seed);
        int sample = Math.min(n, 4000);
        for (int j = 0; j < m; j++) {
            for (int c = 0; c < 256; c++) {
                int src = rnd.nextInt(n);
                System.arraycopy(x, src * d + j * ds, cent, (j * 256 + c) * ds, ds);
            }
            for (int it = 0; it < 8; it++) {
                float[] sum = new float[256 * ds];
                int[] cnt = new int[256];
                for (int i = 0; i < sample; i++) {
                    int a = nearest(x, i * d + j * ds, j);
                    cnt[a]++;
                    for (int t = 0; t < ds; t++) sum[a * ds + t] += x[i * d + j * ds + t];
                }
                for (int c = 0; c < 256; c++) {
                    if (cnt[c] == 0) continue;
                    for (int t = 0; t < ds; t++) cent[(j * 256 + c) * ds + t] = sum[c * ds + t] / cnt[c];
                }
            }
            for (int i = 0; i < n; i++) codes[i * m + j] = (byte) nearest(x, i * d + j * ds, j);
        }
    }

    private int nearest(float[] x, int off, int sub) {
        int best = 0;
        float bd = Float.MAX_VALUE;
        for (int c = 0; c < 256; c++) {
            float dd = l2(x, off, cent, (sub * 256 + c) * ds, ds);
            if (dd < bd) { bd = dd; best = c; }
        }
        return best;
    }

    float[] adcTable(float[] q) {
        float[] t = new float[m * 256];
        for (int j = 0; j < m; j++) for (int c = 0; c < 256; c++) t[j * 256 + c] = l2(q, j * ds, cent, (j * 256 + c) * ds, ds);
        return t;
    }

    float adc(float[] t, int id) {
        float s = 0;
        for (int j = 0; j < m; j++) s += t[j * 256 + (codes[id * m + j] & 0xFF)];
        return s;
    }

    /** One node's record parsed from its sector. */
    record Node(int id, float[] vec, int[] nbrs) {}

    ByteBuffer readSector(int sector) throws IOException {
        ByteBuffer b = ByteBuffer.allocate(SECTOR).order(ByteOrder.LITTLE_ENDIAN);
        long pos = (long) sector * SECTOR;
        while (b.hasRemaining()) if (ch.read(b, pos + b.position()) < 0) break;
        return b.flip();
    }

    Node parse(ByteBuffer b, int id) {
        int base = (id % perSector) * recBytes;
        float[] v = new float[d];
        for (int j = 0; j < d; j++) v[j] = b.getFloat(base + j * 4);
        int deg = b.getInt(base + d * 4);
        int[] nb = new int[deg];
        for (int j = 0; j < deg; j++) nb[j] = b.getInt(base + d * 4 + 4 + j * 4);
        return new Node(id, v, nb);
    }

    record Stats(int[] ids, int rounds, int reads) {}

    /** DiskANN beam search: PQ ranks candidates in RAM; each round reads <= W sectors concurrently. */
    Stats search(float[] q, int k, int l, int w, ExecutorService io) throws Exception {
        float[] tab = adcTable(q);
        Map<Integer, Float> cand = new HashMap<>();
        Map<Integer, Float> exact = new HashMap<>();
        Map<Integer, ByteBuffer> sectors = new HashMap<>();        // per-query sector cache
        cand.put(medoid, adc(tab, medoid));
        int rounds = 0, reads = 0;
        while (true) {
            List<Integer> top = cand.entrySet().stream().sorted(Map.Entry.comparingByValue()).limit(l)
                    .map(Map.Entry::getKey).filter(i -> !exact.containsKey(i)).limit(w).toList();
            if (top.isEmpty()) break;
            rounds++;
            List<Integer> need = top.stream().map(i -> i / perSector).distinct().filter(s -> !sectors.containsKey(s)).toList();
            List<Future<ByteBuffer>> fs = new ArrayList<>();
            for (int s : need) fs.add(io.submit((Callable<ByteBuffer>) () -> readSector(s)));
            for (int i = 0; i < need.size(); i++) sectors.put(need.get(i), fs.get(i).get());
            reads += need.size();
            for (int id : top) {
                Node nd = parse(sectors.get(id / perSector), id);
                exact.put(id, l2(q, 0, nd.vec(), 0, d));               // full precision came with the sector
                for (int j : nd.nbrs()) cand.computeIfAbsent(j, x -> adc(tab, x));
            }
        }
        int[] ids = exact.entrySet().stream().sorted(Map.Entry.comparingByValue()).limit(k)
                .mapToInt(Map.Entry::getKey).toArray();
        return new Stats(ids, rounds, reads);
    }

    /** Records fetched by the last naive search (= sector reads when one node fills a sector, e.g. 768-d). */
    int lastNaiveRecords;

    /** Naive: no PQ in RAM, so every candidate's distance needs its full vector, i.e. its sector. */
    Stats searchNaive(float[] q, int k, int l) throws IOException {
        Map<Integer, Float> cand = new HashMap<>();
        Set<Integer> expanded = new HashSet<>();
        Map<Integer, ByteBuffer> sectors = new HashMap<>();
        Set<Integer> records = new HashSet<>();
        int[] reads = {0};
        java.util.function.IntFunction<Node> load = id -> {
            try {
                records.add(id);
                ByteBuffer b = sectors.get(id / perSector);
                if (b == null) {
                    b = readSector(id / perSector);
                    sectors.put(id / perSector, b);
                    reads[0]++;
                }
                return parse(b, id);
            } catch (IOException e) {
                throw new java.io.UncheckedIOException(e);
            }
        };
        cand.put(medoid, l2(q, 0, load.apply(medoid).vec(), 0, d));
        int rounds = 0;
        while (true) {
            Integer next = cand.entrySet().stream().sorted(Map.Entry.comparingByValue()).limit(l)
                    .map(Map.Entry::getKey).filter(i -> !expanded.contains(i)).findFirst().orElse(null);
            if (next == null) break;
            rounds++;
            expanded.add(next);
            for (int j : load.apply(next).nbrs()) cand.computeIfAbsent(j, x -> l2(q, 0, load.apply(x).vec(), 0, d));
        }
        int[] ids = cand.entrySet().stream().sorted(Map.Entry.comparingByValue()).limit(k)
                .mapToInt(Map.Entry::getKey).toArray();
        lastNaiveRecords = records.size();
        return new Stats(ids, rounds, reads[0]);
    }

    @Override
    public void close() throws IOException {
        ch.close();
        Files.deleteIfExists(file);
    }

    private static void check(boolean ok, String what) {
        if (!ok) throw new AssertionError(what);
    }

    public static void main(String[] args) throws Exception {
        int n = 8_000, d = 128, r = 32, clusters = 40;
        Random rnd = new Random(1);
        float[][] centers = new float[clusters][d];
        for (float[] c : centers) for (int j = 0; j < d; j++) c[j] = (float) (rnd.nextGaussian() * 3);
        float[] x = new float[n * d];
        for (int i = 0; i < n; i++) {
            float[] c = centers[rnd.nextInt(clusters)];
            for (int j = 0; j < d; j++) x[i * d + j] = c[j] + (float) rnd.nextGaussian();
        }
        long t0 = System.nanoTime();
        int[][] g = vamana(x, n, d, r, 48, 1.2, 2);
        System.out.printf("Vamana (R=%d, L=48, alpha=1.0 then 1.2) on %,d x %d built in %.1f s; mean degree %.1f%n",
                r, n, d, (System.nanoTime() - t0) / 1e9, Arrays.stream(g).mapToInt(a -> a.length).average().orElse(0));
        Path file = Files.createTempFile("diskann-", ".sectors");
        try (DiskBeamSearch idx = new DiskBeamSearch(x, n, d, r, g, 32, file, 3);
             ExecutorService io = Executors.newVirtualThreadPerTaskExecutor()) {
            System.out.printf("sector file: record %d B, %d nodes/sector, %,d sectors (%.1f MB); RAM: PQ %d B/vector "
                    + "(vs %d B float32)%n", idx.recBytes, idx.perSector, (n + idx.perSector - 1) / idx.perSector,
                    Files.size(file) / 1e6, idx.m, d * 4);
            float[][] queries = new float[100][d];
            int[][] truth = new int[100][];
            for (int qi = 0; qi < 100; qi++) {
                int b = rnd.nextInt(n);
                for (int j = 0; j < d; j++) queries[qi][j] = x[b * d + j] + (float) (rnd.nextGaussian() * 0.3);
                final float[] q = queries[qi];
                truth[qi] = java.util.stream.IntStream.range(0, n).boxed()
                        .sorted((a, c) -> Float.compare(l2(q, 0, x, a * d, d), l2(q, 0, x, c * d, d)))
                        .limit(10).mapToInt(Integer::intValue).toArray();
            }
            System.out.printf("%n%-28s %9s %8s %8s %12s %12s%n", "mode", "recall@10", "rounds", "reads",
                    "model @100us", "measured");
            double[] recW = new double[9];
            double[] roundsW = new double[9];
            double[] readsW = new double[9];
            for (int w : new int[] {1, 2, 4, 8}) {
                double rec = 0, rounds = 0, reads = 0;
                long t1 = System.nanoTime();
                for (int qi = 0; qi < 100; qi++) {
                    Stats s = idx.search(queries[qi], 10, 100, w, io);
                    rec += HnswFilteredSearch.recall(s.ids(), truth[qi]);
                    rounds += s.rounds();
                    reads += s.reads();
                }
                double ms = (System.nanoTime() - t1) / 1e6 / 100;
                recW[w] = rec / 100;
                roundsW[w] = rounds / 100;
                readsW[w] = reads / 100;
                System.out.printf("%-28s %9.3f %8.1f %8.1f %9.2f ms %9.2f ms%n", "PQ in RAM, beam W=" + w,
                        recW[w], roundsW[w], reads / 100, roundsW[w] * 0.1, ms);
            }
            double rec = 0, rounds = 0, reads = 0, records = 0;
            for (int qi = 0; qi < 100; qi++) {
                Stats s = idx.searchNaive(queries[qi], 10, 100);
                rec += HnswFilteredSearch.recall(s.ids(), truth[qi]);
                rounds += s.rounds();
                reads += s.reads();
                records += idx.lastNaiveRecords;
            }
            System.out.printf("%-28s %9.3f %8.1f %8.1f %9.2f ms %12s%n", "naive: no PQ, read to score",
                    rec / 100, rounds / 100, reads / 100, rounds / 100 * 0.1, "-");
            System.out.printf("  naive fetched %.0f records/query: %.0f%% of the file's %d sectors per query thanks to "
                    + "%d nodes/sector; at 768-d (1 node/sector) every record is its own 4 KB read%n",
                    records / 100, 100.0 * reads / 100 / ((n + idx.perSector - 1) / idx.perSector),
                    (n + idx.perSector - 1) / idx.perSector, idx.perSector);
            check(recW[4] >= 0.9, "beam search recall");
            check(roundsW[4] < roundsW[1] / 2.5, "W=4 cuts round trips ~3-4x");
            check(records / 100 > 3 * readsW[1], "without PQ in RAM, every scored candidate must be fetched");
        }
        System.out.println("all DiskBeamSearch self-checks passed");
    }
}
```

Output (one measured run; recall, round trips and reads are deterministic, build and measured times are not):

```text
Vamana (R=32, L=48, alpha=1.0 then 1.2) on 8,000 x 128 built in 13.2 s; mean degree 29.0
sector file: record 644 B, 6 nodes/sector, 1,334 sectors (5.5 MB); RAM: PQ 32 B/vector (vs 512 B float32)

mode                         recall@10   rounds    reads model @100us     measured
PQ in RAM, beam W=1              0.980    109.3    105.9     10.93 ms      7.80 ms
PQ in RAM, beam W=2              0.980     56.2    107.4      5.62 ms      4.87 ms
PQ in RAM, beam W=4              0.980     29.8    112.0      2.98 ms      3.34 ms
PQ in RAM, beam W=8              0.980     17.2    121.2      1.71 ms      2.71 ms
naive: no PQ, read to score      1.000    108.2    322.6     10.82 ms            -
  naive fetched 361 records/query: 24% of the file's 1334 sectors per query thanks to 6 nodes/sector; at 768-d (1 node/sector) every record is its own 4 KB read
all DiskBeamSearch self-checks passed
```

---

## 6. Production failure modes and P99 debugging

### F1 · p99 latency tracks SSD queue depth, not query complexity

- **Symptom:** latency is fine at low QPS and degrades sharply past a load threshold.
- **Signature:** NVMe queue depth and device latency (iostat `await`, `aqu-sz`) rise, while CPU is moderate.
- **Root cause:** QPS × reads/query has exceeded the drive's random-read IOPS at acceptable latency.
- **Fix:** add drives (stripe sectors), cache hot sectors (the medoid's neighborhood, upper hops) in RAM, reduce reads
  (smaller L, better PQ), or replicate.
- **Prevention:** a capacity model in IOPS (QPS × reads × 4 KB) with headroom, plus load tests at deep queue depth.

### F2 · The page cache silently doubles as the index

- **Symptom:** benchmarks are great on a fresh node and degrade after a co-located workload warms up, or
  inconsistently across nodes.
- **Root cause:** buffered I/O lets the OS cache sectors, so the "disk" index is partly a RAM index whose hit rate
  depends on everything else on the box.
- **Fix:** `O_DIRECT` with an explicit, sized sector cache (hot nodes by BFS level from the medoid), and benchmarks with
  a cold cache.

### F3 · Recall drops after switching to a larger embedding model

- **Symptom:** same L and W, lower recall and higher latency after moving from 768-d to 1,536-d.
- **Root cause:** the record now spans 2 sectors (8 KB per hop). The PQ code budget per dimension halved if `m` was
  kept, so navigation quality dropped.
- **Fix:** re-derive `m` (bytes/vector) for the new dimension. Store float16/int8 vectors on disk, or truncate
  Matryoshka embeddings. Re-tune L.

### F4 · A PQ codebook trained on stale data

- **Symptom:** recall erodes as the corpus evolves (new languages, new product categories) with no index changes.
- **Root cause:** k-means codebooks no longer fit the distribution, so ADC distances misrank new regions.
- **Fix:** retrain codebooks on recent samples and re-encode (cheap in RAM). Monitor per-segment recall with a canary.

### F5 · Delete-heavy workloads degrade the graph

- **Symptom:** recall falls and latency rises as tombstones accumulate, since search keeps routing through deleted
  nodes.
- **Fix:** FreshDiskANN-style consolidation (repair the neighborhoods of deleted nodes with RobustPrune), scheduled by
  tombstone ratio. Alert above ~10–20% tombstones.

### F6 · Beam width tuned on a laptop SSD

- **Symptom:** W=8 was best in testing, but production latency is worse than W=4.
- **Root cause:** on a contended production drive, extra reads per round cost queueing delay. The optimal W depends on
  the device's latency/IOPS curve and on concurrent query load.
- **Fix:** tune W under production-like concurrency, and adapt it to measured device latency.

---

## 7. FAANG L7 bar-raiser Q&A chains

### Q1 · "Explain how DiskANN serves a billion vectors from SSD with millisecond latency."

- **L5 answer:** "It stores the index on disk and uses a graph."
- **Why L5 fails at scale:** no mechanism. It can't say why each choice is needed or what latency results.
- **L7 principal defense:**
  1. PQ codes in RAM (30–60 GiB for 10⁹ vectors) score candidates for free.
  2. Full vectors and adjacency are co-located per 4 KB sector, so one read gives both re-ranking data and the next
     hop.
  3. Vamana with α > 1 keeps long edges, so convergence takes tens of hops.
  4. Beam width W turns hops into round trips: ~16 rounds at W=4 vs 53 at W=1 in the reference. At ~100 µs per round
     that is ~1.6 ms.
  5. Implicit re-ranking with exact vectors fixes PQ's errors (0.77 → 1.0 recall here).
  6. Budget: IOPS = QPS × reads/query.

### Q2 · "What does α in RobustPrune do? What happens at α = 1?"

- **L5 answer:** "It's a pruning threshold."
- **Why L5 fails:** it misses the geometric guarantee and the measured effect.
- **L7 defense:**
  - The pruning condition is $\alpha\, d(p^*, v') \le d(p, v')$. With α > 1, $v'$ is pruned only if $p^*$ is
    *substantially* closer to it, so longer edges survive and each greedy step makes multiplicative progress. That
    bounds hop count and diameter.
  - With α = 1 you get a sparse, short-edged graph: degree 10 vs 18.7, and more hops. In RAM that is tolerable. On SSD,
    every extra hop is a 100 µs round trip.
  - The paper builds with α = 1 first (quality of local structure), then α > 1 (long-range edges).

### Q3 · "HNSW or DiskANN for 300M vectors? We have budget for big-RAM servers."

- **L5 answer:** "HNSW, it's faster."
- **Why L5 fails:** it ignores cost per QPS, updates, filters, and the RAM math (300M × 768-d ≈ 900 GiB for HNSW).
- **L7 defense:** compare on (a) **cost**: HNSW needs ~1 TiB RAM per replica, DiskANN ~10–20 GiB RAM plus ~1.1 TiB
  NVMe; (b) **latency**: HNSW sub-ms vs DiskANN ~1–3 ms; (c) **updates**: both need consolidation; (d) **filters**:
  Filtered-DiskANN vs ACORN/planners; (e) **operations**: DiskANN needs I/O expertise. If p99 must be sub-millisecond
  at high QPS and the budget allows, use HNSW, possibly with int8 vectors and full-precision re-score. Otherwise use
  DiskANN, or IVF-PQ with re-ranking (File 03), at a fraction of the cost.

### Q4 · "Why not just put HNSW on an SSD with mmap?"

- **L5 answer:** "That works, the OS will cache it."
- **Why L5 fails:** HNSW scores every neighbor with a full-precision distance, so each candidate is a random read. The
  access pattern is the naive variant in §3.3: 3.4× more fetched records, all serially dependent, at 4 KB per record
  for 768-d.
- **L7 defense:** a disk-resident graph needs **separation of navigation from verification**: compressed RAM sketches
  for scoring, sector-packed records for expansion, and a search that batches reads per round. Without that, mmap
  turns the index into a page-fault storm whose performance depends on whatever the page cache happens to hold (F2).

### Q5 · "Your DiskANN deployment's p99 doubled after a traffic increase of 30%. Walk me through it."

- **L5 answer:** "Add more CPU."
- **Why L5 fails:** the bottleneck is likely device IOPS and queueing, not CPU.
- **L7 defense:**
  1. Compute the IOPS demand: QPS × reads/query (~60) × 1.3. Compare with the drive's latency-vs-IOPS curve, since
     queueing makes latency superlinear near saturation.
  2. Check device await, queue depth and the page-cache hit rate.
  3. Mitigate: a sized RAM sector cache for the hot upper hops, more drives, a lower L for low-priority traffic, or
     W adapted to device latency.
  4. Plan with a headroom model, and alert on device await before user latency.

---

## 8. Invariants checklist

- [ ] RAM holds only navigation data (PQ codes, codebooks, a sized hot-sector cache). Full vectors and adjacency live
      on NVMe, co-located per sector.
- [ ] Final results are always re-ranked with full-precision vectors.
- [ ] Vamana is built with α > 1 (after an α = 1 pass); degree R and L are tuned for target recall and reads.
- [ ] Beam width W is tuned under production concurrency on production drives.
- [ ] I/O uses direct, aligned reads with deep queues. Benchmarks run cold-cache.
- [ ] Capacity is planned in IOPS (QPS × reads/query × 4 KB) with headroom, and alerts fire on device await.
- [ ] PQ codebooks are retrained as data drifts. Tombstones are consolidated by ratio.
- [ ] The record layout is re-derived on every embedding-dimension change (sectors per node, PQ `m`).

## 9. References

1. S. Jayaram Subramanya, Devvrit, R. Kadekodi, R. Krishnaswamy, H. V. Simhadri. *DiskANN: Fast Accurate Billion-point
   Nearest Neighbor Search on a Single Node.* NeurIPS 2019.
2. H. Jégou, M. Douze, C. Schmid. *Product Quantization for Nearest Neighbor Search.* IEEE TPAMI 33(1), 2011.
3. A. Singh, S. J. Subramanya, R. Krishnaswamy, H. V. Simhadri. *FreshDiskANN: A Fast and Accurate Graph-Based ANN
   Index for Streaming Similarity Search.* arXiv:2105.09613, 2021.
4. S. Gollapudi et al. *Filtered-DiskANN: Graph Algorithms for Approximate Nearest Neighbor Search with Filters.*
   WWW 2023.
5. Microsoft DiskANN repository (github.com/microsoft/DiskANN) (⚠ pin a release when reading the code).
6. J. Axboe. *Efficient IO with io_uring* (kernel.dk), 2019.
