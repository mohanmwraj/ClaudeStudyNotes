# 03 · IVF-PQ, Scalar and Binary Quantization, SIMD Scans, and pgvector vs Qdrant vs Milvus

> **Folder:** `03-Vector-DB-Internals-HNSW-DiskANN-and-Hybrid-Index/` · **File 3 of 3**
> **Anchoring papers and systems:** Jégou, Douze & Schmid, *Product Quantization for Nearest Neighbor Search* (TPAMI
> 2011) · Ge et al., *Optimized Product Quantization* (TPAMI 2014) · Johnson, Douze & Jégou, *Billion-scale similarity
> search with GPUs* (FAISS, 2017) · Guo et al., *ScaNN: Accelerating Large-Scale Inference with Anisotropic Vector
> Quantization* (ICML 2020) · Gao & Long, *RaBitQ* (SIGMOD 2024) · Kusupati et al., *Matryoshka Representation
> Learning* (NeurIPS 2022) · OpenJDK *Vector API* incubator JEPs (JEP 508 in JDK 25) · pgvector, Qdrant and Milvus
> documentation.
> **Code baseline:** Python 3.10+ (CPython 3.14.5 + NumPy 2.5.4) · Java 21 (JDK 25.0.4, `--release 21`, `--add-modules
> jdk.incubator.vector`).
> **Previous:** [02 · DiskANN](02-diskann-vamana-robust-prune-pq-ram-and-nvme-beam-search.md) ·
> **Next folder:** `04-Enterprise-RAG-Pipelines-and-Retrieval-Mechanics/`

---

## 0. The thesis in one paragraph

Graphs (Files 01–02) are not the only way to avoid a full scan, and every scan, graph or not, is **memory-bound**.
That is the same physics as LLM decode in Folder 01: a distance computation does ~2d FLOPs per 4d bytes moved. Three
levers remain:

- **Partition** the space so a query scans a few cells (IVF: 3–7% of the corpus at ~0.99 recall here).
- **Compress** each vector so a scan moves fewer bytes: int8 is 4× smaller, PQ 30–60×, binary 32×.
- **Vectorize** the inner loop with SIMD. Panama measures 5.3× for float32, 11.6× for int8 and 79× for binary codes
  on one core of this laptop.

Every compressed representation trades recall, and recall is bought back the same way each time: **oversample a
shortlist with the cheap representation, then re-score it with full precision**. The databases you'll be asked to
choose between (pgvector, Qdrant, Milvus) are different packagings of these same levers plus HNSW and DiskANN, with
very different consistency, filtering and operational models.

---

## 1. IVF: inverted file over a coarse quantizer

### 1.1 Mechanics

Train k-means with `nlist` centroids. Assign every vector to its nearest centroid's **inverted list**. At query time,
find the `nprobe` nearest centroids and scan only their lists:

$$
\text{fraction scanned} \approx \frac{\text{nprobe}}{\text{nlist}} \times (\text{imbalance factor}),
\qquad \text{recall loss} = \text{neighbors that live in un-probed cells.}
$$

The loss is geometric. A query near a Voronoi boundary has true neighbors on the other side.

| nprobe (nlist = 128, 20K × 64-d) | Scanned | IVF-Flat recall@10 | IVF-PQ16 | IVF-PQ16 + re-rank 100 |
|---:|---:|---:|---:|---:|
| 1 | 1.2% | 0.747 | 0.551 | 0.745 |
| 2 | 1.9% | 0.926 | 0.639 | 0.924 |
| 4 | 3.4% | **0.994** | 0.671 | **0.992** |
| 8 | 6.8% | 1.000 | 0.674 | 0.998 |
| 16 | 13.2% | 1.000 | 0.674 | 0.998 |
| 32 | 25.7% | 1.000 | **0.674 (plateau)** | 0.998 |

### 1.2 Sizing rules

- **nlist ~ O(√N), commonly in the 4√N to 16√N range** (FAISS guidance, ⚠ verify for your library). It trades list
  length (scan cost) against centroid-search cost and boundary misses.
- **Train on a representative sample** (tens of points per centroid at minimum). This run's lists range from **0 to
  731** vectors (median 131). Imbalance makes some probes 5× more expensive and some cells empty: latency variance
  and hot partitions in a sharded deployment.
- **Re-tune `nprobe` as the corpus grows,** and retrain the coarse quantizer when the distribution drifts.

IVF's strengths are cheap builds and incremental adds (just append to a list), easy GPU parallelism (FAISS GPU and
cuVS IVF-PQ/CAGRA), and natural sharding by cell. Its weakness is boundary recall, which HNSW handles better at the
same scan fraction.

---

## 2. Product quantization, residuals, and the plateau

**IVF-PQ** encodes the **residual** $x - c_{\text{list}}$, not $x$ itself. Residuals have smaller variance, so the same
16 bytes buy more precision. ADC tables (File 02 §2.2) are built per probed list from the residual query
$q - c_{\text{list}}$.

The table's key lesson is the **plateau**. Without re-ranking, IVF-PQ16 saturates at **0.674** recall however many
cells you probe, because the quantization error of the codes, not the partitioning, is now the limit. Re-scoring the
best 100 PQ candidates with full-precision vectors lifts it to **0.998**. A production IVF-PQ deployment is therefore
always a two-stage funnel: PQ shortlist (RAM), then exact re-score (RAM or SSD).

Refinements worth naming:

- **OPQ** learns a rotation that balances variance across sub-spaces before PQ.
- **ScaNN** uses *anisotropic* quantization, penalizing error parallel to the query direction more than orthogonal
  error, since that is what corrupts inner-product ranking.
- **4-bit "fast scan" PQ** keeps the lookup tables in SIMD registers.
- **RaBitQ** gives binary-style codes with theoretical error bounds, used for confidence-aware re-ranking (⚠ verify
  adoption in your engine).

---

## 3. Scalar and binary quantization

### 3.1 SQ8: the safe default

Map each dimension's [min, max] onto 0..255 (or symmetric int8). That is 4× smaller with minimal recall loss: **0.974
at 64-d and 0.980 at 512-d** in exhaustive scans here. The danger is range: per-dimension min/max is set by outliers,
so production quantizers clip at percentiles (e.g. 99.9th) or calibrate on samples.

### 3.2 Binary: 32× smaller, only as a first stage

Keep the sign of each (centered) dimension: 1 bit, Hamming distance, one XOR + POPCNT per 64 dims. Alone it is a weak
ranker. As a **first stage with oversampled float re-scoring** it works, and it works better with more dimensions:

| Dimensions | Re-score top 10 | top 40 | top 100 | top 300 |
|-----------:|----------------:|-------:|--------:|--------:|
| 64 | 0.184 | 0.383 | 0.637 | 0.983 |
| 512 | 0.262 | 0.531 | 0.771 | **0.993** |

The Java run (768-d unit vectors) needs a 1,000-candidate shortlist (5% of the corpus) to reach 1.000. 200 gives 0.785.
These synthetic sets have noise-dominated neighborhoods, the hardest case for sign bits. Embedding models trained or
evaluated for binary quantization report much better retention (⚠ verify the vendor's numbers on *your* corpus). The
rule stands either way: **measure the oversampling factor on your data**, and budget for the re-score reads.

### 3.3 Matryoshka truncation

Matryoshka-trained embeddings concentrate information in the leading dimensions, so the first 256 of 1,024 dims are a
valid lower-resolution embedding. A three-stage funnel results:

1. binary codes of the truncated prefix;
2. re-rank with the full binary or int8 code;
3. final re-rank in float.

Each stage multiplies bytes by 4–32×. Truncation requires a Matryoshka-trained model; truncating an ordinary
embedding destroys it.

### 3.4 Bytes at 100M × 768-d (vectors only)

| Representation | Bytes/vector | Total |
|----------------|-------------:|------:|
| float32 | 3,072 | 286.1 GiB |
| float16 (`halfvec`) | 1,536 | 143.1 GiB |
| int8 (SQ8) | 768 | 71.5 GiB |
| PQ m = 96 | 96 | 8.9 GiB |
| binary (1 bit/dim) | 96 | 8.9 GiB |
| PQ m = 48 | 48 | 4.5 GiB |

A typical design keeps the compressed codes plus the graph in RAM, and full-precision vectors on SSD or object
storage for re-scoring. That is DiskANN's split again, packaged by Qdrant (quantization with on-disk originals),
Milvus (DiskANN, IVF variants) and pgvector (expression indexes on quantized casts, with re-ranking in SQL).

---

## 4. SIMD: the inner loop is memory-bound, so bytes per vector is the lever

A distance kernel does ~2d FLOPs per vector and reads $d \times$ (bytes per element). Arithmetic intensity is ≤ 0.5
FLOP/B for float32, which is memory-bound on every CPU (Folder 01 measured this laptop's ridge at ~3–4 FLOP/B). SIMD
helps compute-bound inner loops, and **smaller codes** help memory-bound ones. Measured with the Panama Vector API on
one core (AVX-512: 16 float lanes, 20,000 × 768-d, one measured run):

| Kernel | Bytes/vector | Throughput | vs scalar |
|--------|-------------:|-----------:|----------:|
| float32 L2, scalar loop | 3,072 | 1.40 M vectors/s | 1.0× |
| float32 L2, SIMD + FMA | 3,072 | 7.39 M/s | **5.3×** |
| int8 dot, SIMD (widened to int lanes) | 768 | 16.23 M/s | **11.6×** |
| binary Hamming, `Long.bitCount` (POPCNT) | 96 | 110.48 M/s | **79.1×** |

Correctness is asserted. Float SIMD differs from scalar by ≤ 1.3e-6 relative (different summation order), and the
int8 kernel is bit-exact. The int8 kernel **widens before multiplying**, because int8 × int8 overflows int8. Lucene's
Panama-backed vector utilities follow the same patterns. The planner's exact fallback from File 01 (score only the
rows a filter admits) costs **0.019 ms per query for a 200-row tenant**, which is why "brute force" is the right plan
for small filters.

---

## 5. Choosing an engine: pgvector vs Qdrant vs Milvus

| Dimension (⚠ verify against current releases) | **pgvector** (PostgreSQL extension) | **Qdrant** (Rust, dedicated) | **Milvus** (Go/C++, distributed) |
|-----------|-----------|--------|--------|
| Architecture | inside Postgres: WAL, MVCC, replication, backups for free | single binary; collections → shards → segments; Raft for cluster metadata | disaggregated: proxies, query/data/index nodes, object storage, a log/streaming layer |
| ANN indexes | HNSW, IVFFlat | HNSW per segment (+ quantized variants) | FLAT, IVF_FLAT/SQ8/PQ, HNSW, DISKANN, SCANN, GPU (CAGRA, IVF-PQ) |
| Quantization | `halfvec`, `bit` + `binary_quantize()` expression indexes; re-rank in SQL | scalar / binary / product, with `oversampling` + `rescore` and originals on disk | per-index (SQ8, PQ, binary variants) |
| Dimension limits | storage up to 16,000; **HNSW index up to 2,000** (`vector`), 4,000 (`halfvec`), 64,000 (`bit`) | large | large |
| Filtering | SQL `WHERE` + planner; iterative index scans (≥ 0.8) with `max_scan_tuples`; partial indexes | payload indexes, cardinality-based planning, filterable HNSW, tenant-keyed payloads | scalar indexes, bitset pre-filtering, partition keys |
| Hybrid / sparse | `sparsevec` + Postgres FTS (`tsvector`, not BM25) in one SQL query | sparse vectors; Query API with prefetch + fusion (RRF / DBSF) | sparse vectors (incl. BM25 functions), hybrid search with rankers (RRF / weighted) |
| Consistency | **transactional** (read-your-writes, joins with ACL tables, FKs) | eventually consistent replicas; write ordering per shard | tunable: Strong / Bounded / Session / Eventually |
| Multi-tenancy | row filters, partitioned tables, partial indexes, RLS | payload `is_tenant` indexing, shard keys | databases / collections / partitions / partition keys |
| Scale-out | vertical first; read replicas; sharding via Citus or app-level | horizontal sharding + replication | horizontal by design (billions) |
| Operations | your Postgres team already runs it | one service to run | many components (or the managed Zilliz Cloud) |
| Sweet spot | ≤ tens of millions of vectors, strong consistency, relational joins and ACLs | tens to hundreds of millions, rich filtering and multi-tenancy, low ops | hundreds of millions to billions, GPU indexes, independent scaling of ingest and query |

**pgvector patterns** (DDL and queries follow the pgvector README; **not executed here**, since no pgvector build
exists for this Windows environment. Folder 07 File 03 verifies the hybrid query logic on PostgreSQL 18 with an
emulated operator):

```sql
CREATE EXTENSION IF NOT EXISTS vector;
CREATE TABLE chunks (
  id         bigserial PRIMARY KEY,
  tenant_id  int    NOT NULL,
  doc_id     bigint NOT NULL,
  body       text   NOT NULL,
  embedding  vector(768) NOT NULL
);
-- HNSW on cosine distance; build memory matters: SET maintenance_work_mem = '8GB';
CREATE INDEX chunks_hnsw ON chunks USING hnsw (embedding vector_cosine_ops) WITH (m = 16, ef_construction = 64);

-- Query-time recall dial and filtered-search behavior (pgvector >= 0.8):
SET hnsw.ef_search = 100;
SET hnsw.iterative_scan = relaxed_order;       -- keep scanning until LIMIT rows pass the WHERE clause...
SET hnsw.max_scan_tuples = 20000;              -- ...but never beyond this many tuples (File 01, F3)
SELECT id, doc_id FROM chunks WHERE tenant_id = $1 ORDER BY embedding <=> $2 LIMIT 10;

-- Small tenants: let the planner use a B-tree and score exactly (File 01 planner, in SQL):
CREATE INDEX chunks_tenant ON chunks (tenant_id);

-- Binary quantization with float re-ranking (oversample 10x):
CREATE INDEX chunks_bq ON chunks USING hnsw ((binary_quantize(embedding)::bit(768)) bit_hamming_ops);
SELECT id FROM (
  SELECT id, embedding FROM chunks
  ORDER BY binary_quantize(embedding)::bit(768) <~> binary_quantize($1::vector(768)) LIMIT 100
) shortlist
ORDER BY embedding <=> $1::vector(768) LIMIT 10;

-- Half-precision index on full-precision storage (2x smaller index; dimensions up to 4,000 indexable):
CREATE INDEX chunks_half ON chunks USING hnsw ((embedding::halfvec(768)) halfvec_cosine_ops);
```

---

## 6. Production code blueprints

### 6.1 Python: IVF, IVF-PQ with residuals, SQ8, binary + re-scoring, and the byte budget

```python
"""ivf_pq_lab.py - IVF, IVF-PQ (residual PQ), scalar int8 and binary quantization, with re-scoring (NumPy).

Measures recall@10 against exact search and the fraction of the corpus scanned, then prices each layout at
100M x 768-d. Synthetic clustered data; the mechanisms, not the absolute numbers, transfer.
"""
from __future__ import annotations

import numpy as np


def kmeans(x: np.ndarray, k: int, iters: int, rng: np.random.Generator) -> tuple[np.ndarray, np.ndarray]:
    c = x[rng.choice(len(x), k, replace=False)].copy()
    for _ in range(iters):
        a = assign(x, c)
        for j in range(k):
            pts = x[a == j]
            if len(pts):
                c[j] = pts.mean(0)
    return c, assign(x, c)


def assign(x: np.ndarray, c: np.ndarray) -> np.ndarray:
    d = (x * x).sum(1)[:, None] - 2 * x @ c.T + (c * c).sum(1)[None, :]
    return np.argmin(d, axis=1)


def topk(dist: np.ndarray, k: int) -> np.ndarray:
    k = min(k, len(dist))
    idx = np.argpartition(dist, k - 1)[:k]
    return idx[np.argsort(dist[idx])]


class IVF:
    """Coarse quantizer + inverted lists; optional residual PQ codes per list."""

    def __init__(self, x: np.ndarray, nlist: int, pq_m: int = 0, seed: int = 0):
        rng = np.random.default_rng(seed)
        self.x = x
        self.cent, self.lab = kmeans(x, nlist, 10, rng)
        self.lists = [np.flatnonzero(self.lab == j) for j in range(nlist)]
        self.pq_m = pq_m
        if pq_m:
            res = x - self.cent[self.lab]                       # encode residuals: finer than raw vectors
            self.ds = x.shape[1] // pq_m
            self.cb = np.zeros((pq_m, 256, self.ds), dtype=np.float32)
            self.codes = np.zeros((len(x), pq_m), dtype=np.uint8)
            for j in range(pq_m):
                sub = res[:, j * self.ds:(j + 1) * self.ds]
                self.cb[j], self.codes[:, j] = kmeans(sub, 256, 8, rng)

    def search(self, q: np.ndarray, k: int, nprobe: int, rerank: int = 0) -> tuple[np.ndarray, int]:
        probe = topk(((self.cent - q) ** 2).sum(1), nprobe)
        ids = np.concatenate([self.lists[j] for j in probe])
        if not self.pq_m:
            return ids[topk(((self.x[ids] - q) ** 2).sum(1), k)], len(ids)
        approx = np.empty(len(ids), dtype=np.float32)
        pos = 0
        for j in probe:                                         # ADC table per probed list (residual query)
            lst = self.lists[j]
            rq = (q - self.cent[j]).reshape(self.pq_m, 1, self.ds)
            tab = ((self.cb - rq) ** 2).sum(-1)
            approx[pos:pos + len(lst)] = tab[np.arange(self.pq_m), self.codes[lst]].sum(-1)
            pos += len(lst)
        if not rerank:
            return ids[topk(approx, k)], len(ids)
        cand = ids[topk(approx, rerank)]                        # re-score the shortlist with full precision
        return cand[topk(((self.x[cand] - q) ** 2).sum(1), k)], len(ids)


def sq8(x: np.ndarray):
    lo, hi = x.min(0), x.max(0)
    scale = (hi - lo) / 255.0
    codes = np.clip(np.round((x - lo) / scale), 0, 255).astype(np.uint8)
    return codes, lo, scale


def binarize(x: np.ndarray, mean: np.ndarray) -> np.ndarray:
    return np.packbits(x > mean, axis=1)                         # 1 bit per dimension


def hamming(codes: np.ndarray, qcode: np.ndarray) -> np.ndarray:
    return np.bitwise_count(np.bitwise_xor(codes, qcode)).sum(1)


def recall(got, truth) -> float:
    return len(set(map(int, got)) & set(map(int, truth))) / len(truth)


def main() -> None:
    rng = np.random.default_rng(7)
    n, d = 20_000, 64
    centers = rng.standard_normal((60, d)).astype(np.float32) * 3
    x = (centers[rng.integers(0, 60, n)] + rng.standard_normal((n, d)).astype(np.float32))
    q = x[rng.choice(n, 100, replace=False)] + 0.3 * rng.standard_normal((100, d)).astype(np.float32)
    truth = [topk(((x - qi) ** 2).sum(1), 10) for qi in q]

    ivf = IVF(x, nlist=128, seed=1)
    ivfpq = IVF(x, nlist=128, pq_m=16, seed=1)
    print(f"IVF nlist=128 over {n:,} x {d}; list sizes min/median/max "
          f"{min(map(len, ivf.lists))}/{int(np.median(list(map(len, ivf.lists))))}/{max(map(len, ivf.lists))}")
    print(f"{'nprobe':>6} {'scanned':>8} {'IVF-Flat':>9} {'IVF-PQ16':>9} {'IVF-PQ16+rerank100':>19}")
    rows = {}
    for nprobe in (1, 2, 4, 8, 16, 32):
        r_flat, r_pq, r_rr, scanned = [], [], [], []
        for qi, t in zip(q, truth):
            ids, s = ivf.search(qi, 10, nprobe)
            r_flat.append(recall(ids, t))
            scanned.append(s / n)
            r_pq.append(recall(ivfpq.search(qi, 10, nprobe)[0], t))
            r_rr.append(recall(ivfpq.search(qi, 10, nprobe, rerank=100)[0], t))
        rows[nprobe] = (np.mean(scanned), np.mean(r_flat), np.mean(r_pq), np.mean(r_rr))
        print(f"{nprobe:6d} {rows[nprobe][0]:7.1%} {rows[nprobe][1]:9.3f} {rows[nprobe][2]:9.3f} {rows[nprobe][3]:19.3f}")
    assert rows[16][1] > 0.95 and rows[16][3] > rows[16][2] + 0.1
    assert rows[1][1] < rows[16][1], "nprobe=1 misses neighbors that sit across a Voronoi boundary"

    print("\n== Exhaustive quantized scans (no IVF), by dimensionality ==")
    bq_rows = {}
    for dim in (64, 512):
        if dim == 64:
            xs, qs, ts = x, q, truth
        else:                                                   # binary codes need many dimensions
            c2 = rng.standard_normal((60, dim)).astype(np.float32) * 0.6
            xs = c2[rng.integers(0, 60, n)] + rng.standard_normal((n, dim)).astype(np.float32)
            qs = xs[rng.choice(n, 100, replace=False)] + 0.3 * rng.standard_normal((100, dim)).astype(np.float32)
            ts = [topk(((xs - qi) ** 2).sum(1), 10) for qi in qs]
        codes, lo, scale = sq8(xs)
        deq = codes * scale + lo
        r_sq = np.mean([recall(topk(((deq - qi) ** 2).sum(1), 10), t) for qi, t in zip(qs, ts)])
        mean = xs.mean(0)
        bcodes = binarize(xs, mean)
        r_bq = {}
        for over in (1, 4, 10, 30):
            rs = []
            for qi, t in zip(qs, ts):
                ham = hamming(bcodes, binarize(qi[None], mean))
                cand = topk(ham.astype(np.float32), 10 * over)
                rs.append(recall(cand[topk(((xs[cand] - qi) ** 2).sum(1), 10)], t))
            r_bq[over] = np.mean(rs)
        bq_rows[dim] = (r_sq, r_bq)
        print(f"  d={dim:3d}: SQ8 (4x smaller) recall@10 {r_sq:.3f} | binary (32x smaller) + float re-score of top "
              + ", ".join(f"{10 * o}: {r:.3f}" for o, r in r_bq.items()))
    assert bq_rows[64][0] > 0.9 and bq_rows[512][0] > 0.9
    assert bq_rows[512][1][10] > bq_rows[64][1][10] + 0.1, "more dimensions -> more informative sign bits"
    assert bq_rows[512][1][30] > 0.95, "binary codes work as a first stage with oversampled float re-scoring"

    print("\n== Bytes at 100M x 768-d (vectors only; graph or list overhead excluded) ==")
    for name, b in (("float32", 768 * 4), ("float16 / halfvec", 768 * 2), ("int8 SQ", 768), ("PQ m=96 (8 dims/code)", 96),
                    ("PQ m=48", 48), ("binary (1 bit/dim)", 768 // 8)):
        print(f"  {name:24s} {b:5d} B/vector -> {b * 100e6 / 2**30:8,.1f} GiB")
    print("\nall IVF / quantization self-checks passed")


if __name__ == "__main__":
    main()
```

Output (verified, deterministic):

```text
IVF nlist=128 over 20,000 x 64; list sizes min/median/max 0/131/731
nprobe  scanned  IVF-Flat  IVF-PQ16  IVF-PQ16+rerank100
     1    1.2%     0.747     0.551               0.745
     2    1.9%     0.926     0.639               0.924
     4    3.4%     0.994     0.671               0.992
     8    6.8%     1.000     0.674               0.998
    16   13.2%     1.000     0.674               0.998
    32   25.7%     1.000     0.674               0.998

== Exhaustive quantized scans (no IVF), by dimensionality ==
  d= 64: SQ8 (4x smaller) recall@10 0.974 | binary (32x smaller) + float re-score of top 10: 0.184, 40: 0.383, 100: 0.637, 300: 0.983
  d=512: SQ8 (4x smaller) recall@10 0.980 | binary (32x smaller) + float re-score of top 10: 0.262, 40: 0.531, 100: 0.771, 300: 0.993

== Bytes at 100M x 768-d (vectors only; graph or list overhead excluded) ==
  float32                   3072 B/vector ->    286.1 GiB
  float16 / halfvec         1536 B/vector ->    143.1 GiB
  int8 SQ                    768 B/vector ->     71.5 GiB
  PQ m=96 (8 dims/code)       96 B/vector ->      8.9 GiB
  PQ m=48                     48 B/vector ->      4.5 GiB
  binary (1 bit/dim)          96 B/vector ->      8.9 GiB

all IVF / quantization self-checks passed
```

### 6.2 Java 21: Panama Vector API kernels and the filtered exact scan

The kernels use `SPECIES_PREFERRED`, so the same bytecode runs 16 float lanes on AVX-512, 8 on AVX2 and 4 on NEON.
Loops are written as `loopBound` + scalar tail. The int8 kernel picks a byte species with the *same lane count* as
the preferred int species, so `convertShape(B2I, …, part 0)` widens without splitting. The Vector API is still an
incubator module in JDK 21–25: compile with `--add-modules jdk.incubator.vector -Xlint:all,-incubating` and run with
`--add-modules jdk.incubator.vector`. Forgetting the flag at runtime is a startup failure, not a silent fallback,
which is the behavior you want.

```java
// VectorKernels.java - Java 21 SIMD distance kernels with the Panama Vector API (the approach Lucene uses for its
// vector search): float32 L2 with FMA, int8 dot product with widening to int lanes, binary Hamming with POPCNT, and
// the filtered exact scan that File 01's planner falls back to. Each SIMD kernel is checked against a scalar one.
// Build & self-test:  javac --release 21 --add-modules jdk.incubator.vector -Xlint:all,-incubating -Werror -d out VectorKernels.java
//                     java -ea --add-modules jdk.incubator.vector -cp out dev.l7.ai.inference.VectorKernels
package dev.l7.ai.inference;

import java.util.Arrays;
import java.util.BitSet;
import java.util.PriorityQueue;
import java.util.Random;

import jdk.incubator.vector.ByteVector;
import jdk.incubator.vector.FloatVector;
import jdk.incubator.vector.IntVector;
import jdk.incubator.vector.VectorOperators;
import jdk.incubator.vector.VectorShape;
import jdk.incubator.vector.VectorSpecies;

public final class VectorKernels {

    private VectorKernels() {}

    static final VectorSpecies<Float> F = FloatVector.SPECIES_PREFERRED;
    static final VectorSpecies<Integer> I = IntVector.SPECIES_PREFERRED;
    /** Byte species with as many lanes as the preferred int species (widen B2I without changing lane count). */
    static final VectorSpecies<Byte> B = VectorSpecies.of(byte.class, VectorShape.forBitSize(I.length() * 8));

    // ------------------------------------------------------------------ float32 squared L2
    static float l2Scalar(float[] a, int ao, float[] b, int bo, int d) {
        float s = 0;
        for (int i = 0; i < d; i++) {
            float t = a[ao + i] - b[bo + i];
            s += t * t;
        }
        return s;
    }

    static float l2Simd(float[] a, int ao, float[] b, int bo, int d) {
        FloatVector acc = FloatVector.zero(F);
        int i = 0;
        for (int bound = F.loopBound(d); i < bound; i += F.length()) {
            FloatVector diff = FloatVector.fromArray(F, a, ao + i).sub(FloatVector.fromArray(F, b, bo + i));
            acc = diff.fma(diff, acc);                                   // one fused multiply-add per lane
        }
        float s = acc.reduceLanes(VectorOperators.ADD);
        for (; i < d; i++) {                                             // scalar tail
            float t = a[ao + i] - b[bo + i];
            s += t * t;
        }
        return s;
    }

    // ------------------------------------------------------------------ int8 dot product (SQ8 / int8 embeddings)
    static int dotInt8Scalar(byte[] a, int ao, byte[] b, int bo, int d) {
        int s = 0;
        for (int i = 0; i < d; i++) s += a[ao + i] * b[bo + i];
        return s;
    }

    static int dotInt8Simd(byte[] a, int ao, byte[] b, int bo, int d) {
        IntVector acc = IntVector.zero(I);
        int i = 0;
        for (int bound = B.loopBound(d); i < bound; i += B.length()) {
            IntVector va = (IntVector) ByteVector.fromArray(B, a, ao + i).convertShape(VectorOperators.B2I, I, 0);
            IntVector vb = (IntVector) ByteVector.fromArray(B, b, bo + i).convertShape(VectorOperators.B2I, I, 0);
            acc = acc.add(va.mul(vb));                                   // widen first: int8*int8 overflows int8
        }
        int s = acc.reduceLanes(VectorOperators.ADD);
        for (; i < d; i++) s += a[ao + i] * b[bo + i];
        return s;
    }

    // ------------------------------------------------------------------ binary codes: Hamming via POPCNT
    static int hamming(long[] a, int ao, long[] b, int bo, int words) {
        int s = 0;
        for (int i = 0; i < words; i++) s += Long.bitCount(a[ao + i] ^ b[bo + i]);   // JIT intrinsic: POPCNT
        return s;
    }

    // ------------------------------------------------------------------ quantizers
    /** Symmetric int8 with one global scale (embeddings are roughly zero-centred after normalization). */
    static byte[] toInt8(float[] x, float scale) {
        byte[] out = new byte[x.length];
        for (int i = 0; i < x.length; i++) out[i] = (byte) Math.max(-127, Math.min(127, Math.round(x[i] / scale)));
        return out;
    }

    static long[] toBinary(float[] x, int n, int d) {
        int words = d / 64;
        long[] out = new long[n * words];
        for (int i = 0; i < n; i++)
            for (int j = 0; j < d; j++) if (x[i * d + j] > 0) out[i * words + j / 64] |= 1L << (j % 64);
        return out;
    }

    // ------------------------------------------------------------------ exact top-k over a filter bitmap
    record Hit(int id, float score) {}

    /** The planner's exact path: score only the rows the filter admits; O(|filter| * d), SIMD per row. */
    static int[] exactTopK(float[] x, int d, float[] q, int k, BitSet filter) {
        PriorityQueue<Hit> heap = new PriorityQueue<>((p, r) -> Float.compare(r.score(), p.score()));
        for (int i = filter.nextSetBit(0); i >= 0; i = filter.nextSetBit(i + 1)) {
            float s = l2Simd(q, 0, x, i * d, d);
            if (heap.size() < k) heap.add(new Hit(i, s));
            else if (s < heap.peek().score()) {
                heap.poll();
                heap.add(new Hit(i, s));
            }
        }
        return heap.stream().sorted((p, r) -> Float.compare(p.score(), r.score())).mapToInt(Hit::id).toArray();
    }

    private static void check(boolean ok, String what) {
        if (!ok) throw new AssertionError(what);
    }

    interface Kernel { double run(); }

    static double time(Kernel k) {
        k.run();                                                         // warm up (JIT C2 + vector intrinsics)
        long t0 = System.nanoTime();
        double sink = k.run();
        double secs = (System.nanoTime() - t0) / 1e9;
        if (sink == 42.4242) System.out.print("");                     // keep the result live
        return secs;
    }

    public static void main(String[] args) {
        int n = 20_000, d = 768, nq = 20;
        System.out.printf("species: float x%d (%d-bit), int x%d, byte x%d%n", F.length(), F.vectorBitSize(),
                I.length(), B.length());
        Random rnd = new Random(5);
        float[][] centers = new float[40][d];
        for (float[] c : centers) for (int j = 0; j < d; j++) c[j] = (float) (rnd.nextGaussian() * 0.08);
        float[] x = new float[n * d];
        for (int i = 0; i < n; i++) {
            float[] c = centers[rnd.nextInt(40)];
            double norm = 0;
            for (int j = 0; j < d; j++) {
                x[i * d + j] = c[j] + (float) (rnd.nextGaussian() * 0.04);
                norm += x[i * d + j] * x[i * d + j];
            }
            float inv = (float) (1 / Math.sqrt(norm));
            for (int j = 0; j < d; j++) x[i * d + j] *= inv;                // unit vectors, like embeddings
        }
        float[][] qs = new float[nq][];
        for (int t = 0; t < nq; t++) {
            int b = rnd.nextInt(n);
            qs[t] = Arrays.copyOfRange(x, b * d, b * d + d);
            for (int j = 0; j < d; j++) qs[t][j] += (float) (rnd.nextGaussian() * 0.01);
        }

        // correctness: SIMD == scalar
        float maxRel = 0;
        for (int i = 0; i < 1000; i++) {
            float s = l2Scalar(qs[0], 0, x, i * d, d), v = l2Simd(qs[0], 0, x, i * d, d);
            maxRel = Math.max(maxRel, Math.abs(s - v) / Math.max(1e-9f, s));
        }
        float scale = 0;
        for (float v : x) scale = Math.max(scale, Math.abs(v));
        scale /= 127f;
        byte[] x8 = toInt8(x, scale);
        byte[][] q8 = new byte[nq][];
        for (int t = 0; t < nq; t++) q8[t] = toInt8(qs[t], scale);
        for (int i = 0; i < 1000; i++) check(dotInt8Scalar(q8[0], 0, x8, i * d, d) == dotInt8Simd(q8[0], 0, x8, i * d, d),
                "int8 SIMD must be bit-exact");
        System.out.printf("float L2 SIMD vs scalar: max relative difference %.1e (summation order); int8 dot: bit-exact%n", maxRel);
        check(maxRel < 1e-4, "float SIMD agrees with scalar");

        long[] xb = toBinary(x, n, d);
        long[][] qb = new long[nq][];
        for (int t = 0; t < nq; t++) qb[t] = toBinary(qs[t], 1, d);
        int words = d / 64;

        double tScalar = time(() -> {
            double acc = 0;
            for (float[] q : qs) for (int i = 0; i < n; i++) acc += l2Scalar(q, 0, x, i * d, d);
            return acc;
        });
        double tSimd = time(() -> {
            double acc = 0;
            for (float[] q : qs) for (int i = 0; i < n; i++) acc += l2Simd(q, 0, x, i * d, d);
            return acc;
        });
        double tInt8 = time(() -> {
            double acc = 0;
            for (byte[] q : q8) for (int i = 0; i < n; i++) acc += dotInt8Simd(q, 0, x8, i * d, d);
            return acc;
        });
        double tBin = time(() -> {
            double acc = 0;
            for (long[] q : qb) for (int i = 0; i < n; i++) acc += hamming(q, 0, xb, i * words, words);
            return acc;
        });
        double evals = (double) n * nq;
        System.out.printf("%n%-26s %12s %12s %10s%n", "kernel (d=768, 1 thread)", "M vectors/s", "bytes/vector", "speedup");
        System.out.printf("%-26s %12.2f %12d %9.1fx%n", "float32 L2, scalar", evals / tScalar / 1e6, d * 4, 1.0);
        System.out.printf("%-26s %12.2f %12d %9.1fx%n", "float32 L2, SIMD+FMA", evals / tSimd / 1e6, d * 4, tScalar / tSimd);
        System.out.printf("%-26s %12.2f %12d %9.1fx%n", "int8 dot, SIMD", evals / tInt8 / 1e6, d, tScalar / tInt8);
        System.out.printf("%-26s %12.2f %12d %9.1fx%n", "binary Hamming, POPCNT", evals / tBin / 1e6, d / 8, tScalar / tBin);
        check(tSimd < tScalar, "SIMD beats scalar");

        // quality: int8 and binary(+re-score) vs exact float
        BitSet all = new BitSet(n);
        all.set(0, n);
        double r8 = 0, rb = 0, rb1000 = 0;
        for (int t = 0; t < nq; t++) {
            int[] truth = exactTopK(x, d, qs[t], 10, all);
            final int tt = t;
            Integer[] by8 = new Integer[n];
            for (int i = 0; i < n; i++) by8[i] = i;
            int[] d8 = new int[n];
            for (int i = 0; i < n; i++) d8[i] = -dotInt8Simd(q8[tt], 0, x8, i * d, d);   // unit vectors: max dot = min L2
            Arrays.sort(by8, (p, r) -> Integer.compare(d8[p], d8[r]));
            r8 += HnswFilteredSearch.recall(Arrays.stream(by8).limit(10).mapToInt(Integer::intValue).toArray(), truth);
            int[] hb = new int[n];
            for (int i = 0; i < n; i++) hb[i] = hamming(qb[tt], 0, xb, i * words, words);
            Integer[] byB = new Integer[n];
            for (int i = 0; i < n; i++) byB[i] = i;
            Arrays.sort(byB, (p, r) -> Integer.compare(hb[p], hb[r]));
            BitSet shortlist = new BitSet(n);
            for (int i = 0; i < 1000; i++) {                                           // oversample, then re-score
                shortlist.set(byB[i]);
                if (i == 199) rb += HnswFilteredSearch.recall(exactTopK(x, d, qs[t], 10, shortlist), truth);
            }
            rb1000 += HnswFilteredSearch.recall(exactTopK(x, d, qs[t], 10, shortlist), truth);
        }
        System.out.printf("%nrecall@10: int8 scan %.3f | binary Hamming + float re-score of top-200 %.3f, top-1000 %.3f%n",
                r8 / nq, rb / nq, rb1000 / nq);
        check(r8 / nq > 0.9 && rb1000 / nq > 0.9 && rb1000 > rb, "quantized scans with re-scoring keep recall");

        BitSet tenant = new BitSet(n);
        for (int i = 0; i < n; i += 100) tenant.set(i);                                // a 1% tenant filter
        double tFilt = time(() -> {
            double acc = 0;
            for (float[] q : qs) acc += exactTopK(x, d, q, 10, tenant).length;
            return acc;
        });
        System.out.printf("exact filtered scan of a 1%% tenant (%d rows): %.3f ms/query - the planner's fallback%n",
                tenant.cardinality(), tFilt / nq * 1e3);
        System.out.println("all VectorKernels self-checks passed");
    }
}
```

Output (one measured run; throughput varies by machine, correctness and recall checks are deterministic):

```text
species: float x16 (512-bit), int x16, byte x16
float L2 SIMD vs scalar: max relative difference 1.3e-06 (summation order); int8 dot: bit-exact

kernel (d=768, 1 thread)    M vectors/s bytes/vector    speedup
float32 L2, scalar                 1.40         3072       1.0x
float32 L2, SIMD+FMA               7.39         3072       5.3x
int8 dot, SIMD                    16.23          768      11.6x
binary Hamming, POPCNT           110.48           96      79.1x

recall@10: int8 scan 0.955 | binary Hamming + float re-score of top-200 0.785, top-1000 1.000
exact filtered scan of a 1% tenant (200 rows): 0.019 ms/query - the planner's fallback
all VectorKernels self-checks passed
```

---

## 7. Production failure modes and P99 debugging

### F1 · Hot IVF partitions

- **Symptom:** latency variance across queries, and one shard's CPU much hotter than its peers.
- **Signature:** a skewed inverted-list size distribution (0 to 731 around a median of 131 here). Queries landing in
  fat lists scan 5× more.
- **Root cause:** coarse quantizer trained on a small or unrepresentative sample, or data drift since training.
- **Fix:** retrain on a fresh, larger sample. Balanced k-means or splitting of fat lists. Re-tune `nprobe`.

### F2 · Recall stuck no matter what you tune

- **Symptom:** raising `nprobe` (or `ef`) stops improving recall at ~0.67–0.8.
- **Root cause:** compressed-code error dominates (the IVF-PQ plateau). The partitioning isn't the limit.
- **Fix:** re-score a shortlist with full precision (0.674 → 0.998). Increase PQ bytes, or use OPQ or anisotropic
  quantization.

### F3 · Binary quantization launched, relevance tanked

- **Symptom:** after enabling BQ to cut RAM 32×, users report worse results.
- **Root cause:** a low-dimensional or BQ-unfriendly embedding, or too little oversampling. At 64-d, re-scoring the
  top 100 gave 0.637.
- **Fix:** measure recall versus oversampling on your corpus and model before launch, and budget re-score I/O. Use
  SQ8 if BQ can't reach the target.

### F4 · Scalar quantization clipped by one outlier

- **Symptom:** SQ8 recall far below expectations on one dataset.
- **Root cause:** min/max range set by rare extreme values, which compresses everything else into a few levels.
- **Fix:** percentile clipping and calibration, or per-segment ranges.

### F5 · pgvector silently does sequential scans

- **Symptom:** vector queries take seconds and `EXPLAIN` shows `Seq Scan`.
- **Root cause:** the embedding exceeds the indexable dimension limit (> 2,000 for `vector`); the operator doesn't
  match the index opclass (`<->` against a `vector_cosine_ops` index); `ORDER BY` uses an expression the index
  doesn't cover; or the planner prefers the B-tree for a selective filter. The last is sometimes correct (File 01).
- **Fix:** match the operator to the opclass. Use a `halfvec` index for 2,001–4,000 dims. Read `EXPLAIN ANALYZE` per
  tenant-size class.

### F6 · "I wrote it and immediately searched; it's not there"

- **Symptom:** read-after-write failures in RAG ingestion tests on a distributed vector DB.
- **Root cause:** eventual or bounded consistency (Milvus' default levels, Qdrant replicas, Elasticsearch refresh
  intervals).
- **Fix:** choose the consistency level per operation (Strong or Session for user-visible writes), or confirm
  visibility with a write token. pgvector is transactional by construction.

### F7 · SIMD path not taken

- **Symptom:** a Java service's scans are 5–10× slower than the benchmark.
- **Root cause:** a scalar fallback library build, or a JVM without the Vector API module or C2. Also: on ARM, the
  preferred species is 128-bit (4 floats), so throughput tuned on AVX-512 halves.
- **Fix:** log the species at startup, as the listing prints. Benchmark on the deployment architecture.

---

## 8. FAANG L7 bar-raiser Q&A chains

### Q1 · "IVF-PQ or HNSW for 1B vectors?"

- **L5 answer:** "HNSW has better recall, so HNSW."
- **Why L5 fails at scale:** HNSW at 1B × 768-d is ~3 TiB of RAM per replica. It ignores build time, update patterns
  and GPU availability.
- **L7 principal defense:**
  - **IVF-PQ:** ~48–96 B/vector of codes (45–90 GiB) plus full vectors on SSD for re-scoring. Fast to build (GPU
    k-means), naturally sharded by list, and recall ~0.99 with re-rank at a few percent scanned. The weak spot is
    boundary misses, so tune `nprobe`.
  - **HNSW:** the best recall/latency in RAM, but expensive at this scale.
  - **DiskANN:** HNSW-like recall with PQ in RAM.
  - **The answer is a two-stage funnel either way** (compressed shortlist, exact re-score), chosen by the latency SLO
    (sub-ms points to HNSW or GPU CAGRA; a few ms to DiskANN or IVF-PQ) and by cost per QPS.

### Q2 · "We want to cut vector RAM 32× with binary quantization. Risks?"

- **L5 answer:** "Slight accuracy loss."
- **Why L5 fails:** it's not slight without re-scoring (0.18–0.26 alone), and it depends on dimensionality and the
  model.
- **L7 defense:**
  1. BQ only as a first stage, with an oversampling factor *measured on our corpus*. Here 30× gave 0.993 at 512-d and
     100× was needed at 768-d on noisy synthetic data.
  2. Re-score with float or int8 from SSD, and budget those reads into IOPS.
  3. Prefer models trained or evaluated for BQ. Consider Matryoshka truncation as a cascade.
  4. Fall back to SQ8 (0.97+ recall, 4×) if BQ can't hit the target.

### Q3 · "Why is a brute-force scan sometimes the right plan?"

- **L5 answer:** "For small datasets."
- **Why L5 fails:** it misses filtered search, where brute force over the *filter set* is the correct plan at any
  corpus size.
- **L7 defense:** an exact scan costs |filter| × d with SIMD: 0.019 ms for 200 rows at 768-d (int8 or binary even
  less). Graph traversal over a sparse filter either disconnects or approaches $N$ visits (File 01). Planners switch
  on cardinality: Lucene's exact fallback, Qdrant's full-scan threshold, Postgres choosing the B-tree.

### Q4 · "pgvector, Qdrant, or Milvus for our enterprise RAG?"

- **L5 answer:** "Milvus, it scales the most."
- **Why L5 fails:** scale is one axis. RAG needs ACL joins, transactional visibility, multi-tenancy and modest ops.
- **L7 defense:** decide on corpus size per tenant, filter and ACL complexity, consistency needs, update rate, and
  team.
  - **pgvector** up to tens of millions of vectors with heavy relational ACLs and read-your-writes (Folder 04 File 03),
    accepting the 2,000-dim HNSW limit and vertical scaling.
  - **Qdrant** for rich filtering and multi-tenancy at hundreds of millions with low ops.
  - **Milvus** for billions, GPU indexes, and independent scaling of ingest and query.
  - Prototype the top two with stratified recall (by filter selectivity) and p99 under realistic writes.

### Q5 · "Your Java retrieval service's p99 doubled after moving to ARM instances. Why?"

- **L5 answer:** "ARM CPUs are slower."
- **Why L5 fails:** the specific mechanism is vector width.
- **L7 defense:** the Panama `SPECIES_PREFERRED` is 512-bit on AVX-512 but 128-bit on NEON (most ARM servers;
  SVE-capable parts differ), so float L2 throughput per core drops ~2–4×, while bandwidth per core may be fine.
  Verify by logging the species and re-running the kernel benchmark. Mitigate with int8 or binary codes (fewer bytes,
  more lanes per byte), more cores, or keep the scan-heavy tier on x86.

### Q6 · "Explain the IVF-PQ recall plateau."

- **L5 answer:** "PQ is lossy."
- **Why L5 fails:** it doesn't explain why probing more lists doesn't help, or what fixes it.
- **L7 defense:**
  - Recall = P(neighbor's cell is probed) × P(neighbor ranks in the top-k by approximate distance).
  - The first factor goes to 1 as `nprobe` grows. The second is capped by PQ distortion: 16 bytes for 64 dims → 0.674
    here.
  - Only re-scoring with full precision or a finer code lifts the cap: re-rank 100 → 0.998. Residual encoding, OPQ
    and anisotropic losses raise the cap at a fixed byte budget.

---

## 9. Invariants checklist

- [ ] Every compressed index is a two-stage funnel: compressed shortlist, then full-precision re-score, with the
      oversampling factor measured on the production corpus and model.
- [ ] IVF coarse quantizers are trained on representative samples, list-size skew is monitored, and `nprobe` is
      re-tuned as data grows.
- [ ] SQ ranges are clipped and calibrated. BQ is used only with sufficient dimensionality and re-scoring.
- [ ] Bytes per vector is the primary cost lever for scans (memory-bound). SIMD species and kernels are logged and
      benchmarked on the deployment architecture.
- [ ] The engine choice is documented against size, filtering/ACL, consistency, multi-tenancy, scale-out and
      operations, with stratified recall and p99 prototypes.
- [ ] pgvector: operators match opclasses, dimensions are within index limits, iterative scans are capped, and
      `EXPLAIN ANALYZE` is checked per tenant-size class.
- [ ] Read-after-write semantics are explicit (consistency level or transactional store).

## 10. References

1. H. Jégou, M. Douze, C. Schmid. *Product Quantization for Nearest Neighbor Search.* IEEE TPAMI 33(1), 2011.
2. T. Ge, K. He, Q. Ke, J. Sun. *Optimized Product Quantization.* IEEE TPAMI 36(4), 2014.
3. J. Johnson, M. Douze, H. Jégou. *Billion-scale similarity search with GPUs.* IEEE TBD, 2019 (arXiv:1702.08734).
4. R. Guo et al. *Accelerating Large-Scale Inference with Anisotropic Vector Quantization (ScaNN).* ICML 2020.
5. J. Gao, C. Long. *RaBitQ: Quantizing High-Dimensional Vectors with a Theoretical Error Bound for Approximate
   Nearest Neighbor Search.* SIGMOD 2024.
6. A. Kusupati et al. *Matryoshka Representation Learning.* NeurIPS 2022.
7. OpenJDK. *Vector API* JEPs (incubator; JEP 469 in JDK 23, JEP 489 in JDK 24, JEP 508 in JDK 25) (⚠ verify the
   current JEP).
8. pgvector README (types, index limits, iterative scans, quantization); Qdrant documentation (quantization,
   filtering, multitenancy, hybrid queries); Milvus documentation (index types, consistency levels, partition keys)
   (⚠ pin versions).
