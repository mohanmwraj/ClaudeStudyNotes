# 01.1 · Vector Spaces, Dot Product, Cosine Similarity & the L2-Distance Equivalence

> **Folder 01 · Linear Algebra, Probability & Embedding Geometry**
> **Measured on:** NumPy 2.5.4, scikit-learn 1.9.1, CPython 3.14.5, Intel i5-11260H (one BLAS thread), Windows 11. Embeddings are synthetic and seeded so that every number reproduces. Where a number depends on *your* model, the text says so.
> **Design sources:** the OpenAI embeddings guide, the Gemini API embeddings docs, the pgvector README (v0.8.7), the Hugging Face embedding-quantization study, Charikar (2002), Ethayarajh (2019), Steck et al. (2024), Bachrach et al. (2014). Full list in §8.

---

## 0. Orientation: Embedding Geometry Is the AI Engineer's Data Structure

Here's the idea in plain words. Almost every "smart" component you will put in front of, beside, or behind an LLM is a geometry problem in disguise:

- A **semantic router** asks which intent centroid a query is closest to.
- A **semantic cache** asks whether a new prompt falls within distance *r* of one already answered.
- **RAG retrieval** asks for the *k* nearest chunks.
- **Dedup** asks which pairs are within a near-duplicate radius.
- An **out-of-distribution guardrail** asks whether the query is far from everything you trained on.
- **Hybrid re-ranking** mixes a geometric score with a lexical one (Folder 04).

If you understand the geometry, each of these becomes a one-line kernel that runs in microseconds. If you don't, you ship thresholds copied from a blog post, indexes built with the wrong metric, and caches that serve wrong answers right after a model upgrade.

The good news is that you only need a small amount of math, as long as you understand it exactly. This file gives you that set: inner products, norms, the unit sphere, the cosine/dot/L2 equivalence and where it breaks, how high-dimensional space behaves, anisotropy, and quantization geometry. Each idea comes with a runnable proof and a production consequence.

### The backend-engineer bridge

| You already know (backend) | The embedding-geometry equivalent | Why the analogy matters |
|---|---|---|
| Canonicalize keys before hashing (lowercase, trim) | **L2-normalize vectors at ingest** | Two code paths that skip canonicalization produce silent mismatches, in caches and in vector indexes alike |
| B-tree / hash index | **ANN index (HNSW, IVF, DiskANN)** | An index is built for one comparison operator. Querying it with another one is a bug, not a tuning knob |
| A schema version on every row | **(model id, version, dim, dtype, normalized, metric) on every vector** | Vectors from two models are *not comparable*, like two incompatible schemas sharing one column |
| Join predicate `a.k = b.k` | **Similarity threshold `cos(a,b) ≥ τ`** | τ is data-dependent, like a selectivity estimate, and must be re-derived when the data or model changes |
| Fixed-width record: 4·d bytes | **float32 d-dim vector = 4d bytes** | 10M × 1024 × 4 B = 41 GB *before* index overhead. Compression is a capacity decision |
| Compression codecs (LZ4 vs ZSTD) | **fp16 / int8 / binary quantization** | Same trade-off shape: ratio vs fidelity vs CPU, plus "decompress the hot set" (rescoring) |
| p99 latency SLO | **recall@k at a latency budget** | ANN indexes trade recall for latency. You must measure both, against exact search |

### Tier map for this file

| Subtopic | Tier | One-line reason |
|---|---|---|
| 1.1 Inner products, norms, rotation invariance | `[MUST-KNOW: Core AI Engineer Edge]` | Everything else is built on it, and it kills the "dimension 17 means sentiment" myth |
| 1.2 Cosine = dot on the unit sphere | `[MUST-KNOW: Core AI Engineer Edge]` | Decides which operator your index uses and whether you pay for a division |
| 1.3 ‖a−b‖² = 2 − 2cos and rank equivalence | `[MUST-KNOW: Core AI Engineer Edge]` | Lets you use an L2-only index for cosine search, and converts thresholds between metrics |
| 1.4 Unnormalized vectors and MIPS | `[GOOD-TO-KNOW: Architectural Literacy]` | Dot-trained retrievers and two-tower recommenders. You will meet them |
| 1.5 Metric properties (triangle inequality) | `[GOOD-TO-KNOW: Architectural Literacy]` | Explains which algorithms accept "cosine distance" and which quietly misbehave |
| 1.6 Concentration of measure | `[MUST-KNOW: Core AI Engineer Edge]` | Why absolute similarity values mean nothing across models |
| 1.7 Anisotropy | `[MUST-KNOW: Core AI Engineer Edge]` | The "all my similarities are 0.7–0.9" incident, and the threshold-transfer bug |
| 1.8 Is cosine the right similarity at all? | `[GOOD-TO-KNOW: Architectural Literacy]` | Use the metric the model was trained with, plus query/document prefixes |
| 1.9 Johnson–Lindenstrauss | `[GOOD-TO-KNOW: Architectural Literacy]` | A data-oblivious bound on dimensions. It is loose, and knowing why is the insight |
| 1.10 Quantization geometry, SimHash law | `[MUST-KNOW: Core AI Engineer Edge]` | 4–32× memory cuts, and the rescoring pattern that keeps recall |
| 1.11 Router decision regions are Voronoi cells | `[MUST-KNOW: Core AI Engineer Edge]` | A nearest-centroid router *is* a linear classifier. Abstention is a margin band |
| Formal Hilbert-space theory, measure-theoretic proofs | `[SKIP: Academic/Research Only]` | Nothing in production depends on infinite-dimensional subtleties |

After this file, you should be able to defend, under bar-raiser questioning:

1. which operator your vector index uses and why,
2. why your semantic-cache threshold is model-specific and how you derived it,
3. how to cut vector memory 4–32× and what recall that costs,
4. why a 20 µs nearest-centroid router plus an LLM fallback can beat an all-LLM classifier on cost and accuracy at the same time.

---

## 1. First-Principles Math & Geometric Intuition

### 1.1 Vectors, inner products, norms, and why embedding axes mean nothing `[MUST-KNOW: Core AI Engineer Edge]`

An embedding model is a function `f: text → ℝᵈ`. Training shapes it so that texts with related meaning land near each other. A vector `x ∈ ℝᵈ` is just d coordinates, and the geometry comes from the **inner product**:

```text
⟨a, b⟩ = a·b = Σᵢ aᵢ bᵢ                         (the dot product)
‖a‖   = √⟨a, a⟩                                  (the L2 norm it induces)
d(a,b) = ‖a − b‖                                 (Euclidean distance)
```

An inner product is any operation that is symmetric (`a·b = b·a`), linear in each argument, and positive definite (`a·a > 0` unless `a = 0`). The dot product is the standard one. You will meet weighted ones later: Mahalanobis distance in Folder 03 is `‖a−b‖` under the inner product `aᵀ Σ⁻¹ b`.

**Rotation invariance kills the "interpretable dimensions" myth.** Take any orthogonal matrix Q (a rotation or reflection, `QᵀQ = I`) and apply it to every embedding:

```text
(Qa)·(Qb) = aᵀ QᵀQ b = aᵀ b = a·b
```

Every dot product, norm, and distance is unchanged. So a model whose outputs are rotated by an arbitrary Q is *exactly as good*, and gives identical search results, cache hits and routing decisions. Training never pins down "which axis is which", which is why individual coordinates of a general-purpose embedding carry no stable meaning. Two consequences you'll use:

- **Naive truncation of a non-Matryoshka embedding** (keep the first k coordinates) is no better than a random projection. 01.2 measures this: recall 0.535 for truncation vs 0.529 for a random projection at k = 64.
- **Vectors from two different models are not comparable**, even when the dimension matches. Each model's space is defined only up to its own arbitrary rotation (and worse, a nonlinear warp). Mixing them in one index is a schema violation.

**The geometric meaning of the dot product.** Put `a` and `b` tail-to-tail, with angle θ between them:

```text
                 b
                ↗
               /
              /  θ
             o────────────────→ a
             └────┘
             projection of b onto a = ‖b‖ cos θ

a·b = ‖a‖ ‖b‖ cos θ
```

*Proof via the law of cosines.* Expand `‖a − b‖² = (a−b)·(a−b) = ‖a‖² + ‖b‖² − 2 a·b`. Geometry says `‖a − b‖² = ‖a‖² + ‖b‖² − 2‖a‖‖b‖ cos θ` for the triangle with sides a, b, a−b. Equating the two gives `a·b = ‖a‖‖b‖ cos θ`. ∎

**Cauchy–Schwarz: why cosine lives in [−1, 1].** For any real t, `‖a − t b‖² ≥ 0`:

```text
‖a‖² − 2t(a·b) + t²‖b‖² ≥ 0   for all t
⇒ this quadratic in t has at most one real root
⇒ discriminant ≤ 0:  4(a·b)² − 4‖a‖²‖b‖² ≤ 0
⇒ |a·b| ≤ ‖a‖ ‖b‖  ⇒  −1 ≤ cos θ ≤ 1          ∎
```

That is true in exact arithmetic. In float32 it isn't, and that matters in production. Listing §3.1 finds that **21,259 of 100,000** float32 unit vectors have a self-similarity above 1.0 (max 1.000000358), and `np.arccos` returns NaN for every one of them. Any code that turns cosine into an angle, or into `sqrt(1 − cos²)`, needs a clip first.

### 1.2 The exact proof that cosine similarity equals the dot product on the unit sphere `[MUST-KNOW: Core AI Engineer Edge]`

**Definition.** `cos(a, b) = (a·b) / (‖a‖ ‖b‖)`, defined for non-zero a and b.

**Theorem.** If `‖a‖ = ‖b‖ = 1`, then `cos(a, b) = a·b`.

**Proof.** Substitute the norms: `cos(a,b) = (a·b)/(1·1) = a·b`. ∎

The theorem is trivial. What matters is how you use it.

**Corollary (normalize once, then dot forever).** Define `â = a/‖a‖`. Then for *any* non-zero a, b:

```text
cos(a, b) = (a·b)/(‖a‖‖b‖) = (a/‖a‖)·(b/‖b‖) = â·b̂
```

Cosine similarity is the dot product of normalized vectors. If you normalize **at ingest** (documents) and **at query time** (queries), the hot path is a pure dot product: a fused multiply-add stream with no square roots and no divisions. Per document, that saves two norms (or one, cached) and a division. BLAS and SIMD kernels run the matrix-vector product at memory bandwidth. This is why both OpenAI's guide and the pgvector README give the same advice:

- OpenAI: embeddings "are normalized to length 1", and cosine similarity "can be computed slightly faster using just a dot product".
- pgvector: "If vectors are normalized to length 1 (like OpenAI embeddings), use inner product for best performance."

```text
        unit circle (the 2-D slice of the unit sphere)
                  ·  ·  ·
              ·             ·
           ·        b̂ ↗       ·        â·b̂ = cos θ
          ·          /           ·      (both arrows have length 1,
          ·         / θ          ·       so the dot product is
          ·        o───────→ â   ·       exactly the cosine)
           ·                   ·
              ·             ·
                  ·  ·  ·
```

**When the corollary silently fails:**

| Situation | What breaks | How it shows up |
|---|---|---|
| Vendor returns non-unit vectors at some setting | `â·b̂ ≠ a·b` | Gemini: per the Gemini API docs, `gemini-embedding-001` returns normalized vectors only at the default 3072 dims and "you must manually normalize non-3072 dimensions", whereas `gemini-embedding-2` "introduces automatic renormalization for non-default dimensions" |
| You truncate an embedding yourself | Prefix norm < 1 | OpenAI's guide: "When you change the dimension manually, you need to be sure to normalize". The Matryoshka listing in 01.2 shows top-10 sets differ for **100%** of queries between raw-prefix dot and renormalized cosine |
| A zero vector (empty string, upstream failure) | Division by zero → NaN | NaN poisons top-k ordering. Reject at ingest (§3.1, claim 7) |
| float16 storage | The norm drifts from 1 by ~1e-3 | Usually harmless for ranking (§3.3: fp16 recall@10 = 1.000). It matters if you compare raw scores to a tight threshold |

### 1.3 The L2 equivalence: ‖a − b‖² = 2 − 2 cos(a, b), and why top-k is identical `[MUST-KNOW: Core AI Engineer Edge]`

**Theorem.** For unit vectors a and b, `‖a − b‖² = 2 − 2 (a·b) = 2 − 2 cos(a, b)`.

**Proof.**

```text
‖a − b‖² = (a − b)·(a − b)
         = a·a − 2 a·b + b·b
         = ‖a‖² − 2 a·b + ‖b‖²
         = 1 − 2 a·b + 1                        (unit norms)
         = 2 − 2 cos(a, b)                      ∎
```

**Corollary (rank equivalence).** For a fixed unit query q and a set of unit documents, sorting by descending `q·d`, by descending `cos(q,d)`, and by ascending `‖q − d‖` gives **the same order**.

*Proof.* `‖q − d‖ = √(2 − 2 q·d)`. The map `c ↦ √(2 − 2c)` is strictly decreasing on [−1, 1]. A strictly monotone transform preserves order (reversing it if decreasing), so the top-k by smallest distance is the top-k by largest dot product. ∎

That one line is why every serious vector database lets you build an L2 index and use it for cosine search. You normalize first, and the engine's L2 machinery (HNSW graphs, IVF centroids, PQ codebooks trained under L2) is valid as is.

**Chord vs arc: three distances, one ordering.**

```text
                       b̂
                      ●
                     /|\
          arc (θ)  /  |  \  chord ‖â − b̂‖ = 2 sin(θ/2) = √(2 − 2cos θ)
                 /    |    \
               /  θ   |      \
              o───────┴───────● â
              (both on the unit circle)

 angular distance   θ = arccos(cos)     metric, in [0, π]
 chord distance     √(2 − 2 cos)        metric, in [0, 2]  (this is L2 on the sphere)
 "cosine distance"  1 − cos             NOT a metric (§1.5), in [0, 2]
```

**The threshold conversion table you'll actually use** (unit vectors):

| cos | L2 = √(2−2cos) | L2² | angle | pgvector `<=>` (= 1 − cos) | pgvector `<#>` (= −cos) |
|---:|---:|---:|---:|---:|---:|
| 0.95 | 0.316 | 0.10 | 18.2° | 0.05 | −0.95 |
| 0.90 | 0.447 | 0.20 | 25.8° | 0.10 | −0.90 |
| 0.80 | 0.632 | 0.40 | 36.9° | 0.20 | −0.80 |
| 0.50 | 1.000 | 1.00 | 60.0° | 0.50 | −0.50 |
| 0.00 | 1.414 | 2.00 | 90.0° | 1.00 | 0.00 |

pgvector's `<#>` returns the **negative** inner product, because Postgres index scans only support ascending order on operators. `ORDER BY embedding <#> $q` is therefore correct, and the similarity is `-(embedding <#> $q)`. A classic bug is writing `1 - (a <#> b)` as "similarity", which gives `1 + cos`.

**Where the equivalence breaks in production** (the bar-raiser will push on each one):

1. **Unnormalized vectors.** The identity needs unit norms. §3.1 claim 3 gives documents log-normal norms (σ = 0.5). Top-10 overlap is then **0.112** between dot and cosine, **0.262** between L2 and cosine, and **0.006** between dot and L2. Dot product's top-10 has mean norm **2.76** vs a corpus mean of 1.13 (it prefers long vectors). L2's top-10 has mean norm **0.50** (it prefers short vectors near the origin).
2. **Floating-point ties.** In exact math the orders match. In float32 they can differ only when two scores sit within rounding error (~1e-7) of each other at the rank-k boundary. Measured: the smallest rank-10/11 gap over 200 queries was 8.9e-6, and **200/200** top-10 sets agreed.
3. **Approximate search.** HNSW or IVF results depend on graph and partition structure, so a cosine-configured and an L2-configured ANN index can return different neighbors on the same normalized data (different build paths, different tie-breaking). The *exact* answers agree. The approximate ones agree only statistically.
4. **Quantized storage.** Int8 and binary codes are not unit vectors, so the identity holds only after dequantization and renormalization (§1.10).
5. **Thresholds.** The *ranking* transfers between metrics. A threshold must be converted with the table above, or your "0.8" becomes a different radius.

### 1.4 When vectors are not normalized: MIPS, popularity bias, and the one-coordinate reduction `[GOOD-TO-KNOW: Architectural Literacy]`

Some models are trained with a raw dot product, and their norms carry signal. Examples are two-tower recommenders, where a popular item's vector grows long, and some dense retrievers trained with dot-product contrastive loss. For those, the right search is **maximum inner product search (MIPS)**, `argmax_d q·d = argmax_d ‖d‖ cos θ`. A long document can beat a closer but shorter one. Sometimes that is the intent (popularity), sometimes it is a bias you'll want to cap.

**MIPS is not nearest-neighbour search**, and most index structures are designed for metrics. The classic reduction (Bachrach et al., RecSys 2014, as described by Vespa's MIPS write-up) adds one coordinate. Let `M = maxᵢ ‖xᵢ‖`:

```text
x̃ᵢ = [ xᵢ , √(M² − ‖xᵢ‖²) ]      (every augmented doc now has norm exactly M)
q̃  = [ q  , 0 ]

‖q̃ − x̃ᵢ‖² = ‖q‖² + ‖xᵢ‖² + (M² − ‖xᵢ‖²) − 2 q·xᵢ
           = ‖q‖² + M² − 2 q·xᵢ
```

`‖q‖²` and `M²` are constant for a given query, so ascending L2 on the augmented vectors is descending inner product on the originals. ∎ §3.1 claim 6 checks it on 200 queries: **200/200** exact MIPS top-10 sets are reproduced by an L2 search over augmented vectors.

**The catch (Neyshabur & Srebro, 2015).** The extra coordinate dominates. In our corpus its mean is **7.81**, while the mean |coordinate| is **0.046**. ANN structures and quantizers then spend their resolution on a nearly constant dimension, so speedups shrink. Production rules:

- If you control training, normalize (or train with cosine).
- If you don't, use an engine with native MIPS support. FAISS `METRIC_INNER_PRODUCT` and pgvector `<#>` / `vector_ip_ops` give exact inner-product ordering. ANN quality on unnormalized data must be measured, not assumed.

### 1.5 Metric properties: why "cosine distance" is not a metric `[GOOD-TO-KNOW: Architectural Literacy]`

A metric needs `d(x,x) = 0`, symmetry, and the **triangle inequality** `d(a,c) ≤ d(a,b) + d(b,c)`. Take a = (1,0), b = (√½, √½), c = (0,1), so the angles are 45° + 45° = 90°:

```text
1 − cos:        d(a,c) = 1.0000  >  d(a,b) + d(b,c) = 0.2929 + 0.2929 = 0.5858   → VIOLATED
angular θ:      π/2 = π/4 + π/4                                                    → holds (equality)
chord √(2−2c):  1.4142 ≤ 0.7654 + 0.7654 = 1.5307                                  → holds
```

§3.1 claim 5 also samples 30,000 random triples in 8-D: **937** violations for `1 − cos`, **0** for arccos and for the chord.

**Why you care.** Algorithms that *prune with the triangle inequality* (VP-trees, ball trees, some clustering accelerations) can return wrong answers or lose their guarantees when given `1 − cos`. Hand them the chord distance (L2 on normalized vectors) instead. It's the same ordering and it's a true metric. Density-based clustering (HDBSCAN, Folder 03) and k-means (which minimizes squared L2) should also be run on normalized vectors with L2, not on a "cosine distance" matrix.

### 1.6 High-dimensional geometry: concentration of measure `[MUST-KNOW: Core AI Engineer Edge]`

Two facts about high dimensions explain most "why is my similarity weird" questions.

**Fact 1: random directions are almost orthogonal.** Let u and v be independent and uniform on the unit sphere in ℝᵈ. By symmetry E[u·v] = 0. Fix v and rotate so that v = e₁. Then u·v = u₁, and because `Σᵢ uᵢ² = 1` with all coordinates exchangeable, `E[u₁²] = 1/d`. So:

```text
E[cos] = 0,   Var[cos] = 1/d,   std ≈ 1/√d      (and cos is ≈ Normal for large d)
```

§3.2 part A measures it. The std is **0.0516** at d = 384 (1/√384 = 0.0510), **0.0362** at d = 768, and **0.0180** at d = 3072. `P(|cos| > 0.1)` falls from 0.052 at d = 384 to **0.0000** at d = 3072. Two unrelated texts *should* have a cosine near 0, within about ±2/√d. When your model reports 0.3–0.7 for unrelated pairs, that is not noise. It is structure in the space (§1.7).

**Fact 2: distance contrast collapses for structureless data.** Beyer et al. (1999) showed that for many i.i.d. distributions, `(D_max − D_min)/D_min → 0` as d grows. All points become nearly equidistant from a query, and "nearest" stops meaning anything. §3.2 part B reproduces it: for uniform random points the relative contrast falls from **1.956** at d = 16 to **0.070** at d = 3072.

**So why does nearest-neighbour search work on 3072-d embeddings?** Because real embeddings are not structureless. They sit near a low-dimensional manifold (topics, intents, entities) embedded in the big space. The same listing embeds 40 clusters on a 16-D latent manifold into d dimensions, and the contrast stays high: **6.671** at d = 3072, about 95× the uniform case. What matters is the *intrinsic* dimension, not d. This also predicts results you'll see elsewhere:

- PCA to 64 dims can keep recall@10 ≈ 0.995 on such data (01.2).
- Random projection, which ignores the structure, needs far more dims (01.2 and §1.9).
- Anomaly detection becomes possible: an out-of-distribution query is far from the manifold (Folder 03).

### 1.7 Anisotropy: the "everything is 0.8" problem and the threshold-transfer bug `[MUST-KNOW: Core AI Engineer Edge]`

Ethayarajh (EMNLP 2019) found that contextual representations from ELMo, BERT and GPT-2 are **anisotropic** in every layer. They occupy a narrow cone instead of spreading in all directions. GPT-2's last layer is the extreme case, where two random words have nearly perfect cosine similarity on average. Modern sentence-embedding models are trained to reduce this, but most still have a **non-zero mean direction**. Random pairs then have a positive average cosine, and all scores get squeezed into a band.

**The algebra.** Write each unit embedding as `x = μ + r`, where μ is the corpus mean and r the residual (E[r] = 0). For two unrelated texts, `E[x·y] ≈ ‖μ‖²`. The common component adds roughly the same amount to every similarity, while the *useful* variation (r·r′) shrinks relative to it, because everything must still fit on the unit sphere.

§3.2 part C builds the same semantic structure in two geometries:

| space | random pair | same topic | same intent | usable band (intent − random) |
|---|---:|---:|---:|---:|
| A isotropic | −0.000 | 0.510 | 0.773 | **0.774** |
| B anisotropic (shared μ) | 0.718 | 0.862 | 0.936 | **0.218** |
| B mean-centred | −0.010 | 0.505 | 0.771 | **0.781** |

Model B is *not worse at ranking*. The ordering of pairs is almost unchanged. But every absolute number moved, and the band that separates "same intent" from "unrelated" shrank 3.5×. Subtracting the corpus mean and renormalizing restores the spread exactly.

**The production incident this causes (§3.2 part D).** You tune a semantic-cache threshold on model A for precision 0.95. It comes out at τ = 0.651 (recall 0.852, hit rate 0.227). Then you swap in model B and keep τ:

```text
A @ its own threshold    thr= 0.651  precision=0.950  recall=0.852  cache-hit rate=0.227
B @ A's threshold        thr= 0.651  precision=0.253  recall=1.000  cache-hit rate=1.000
B @ its own threshold    thr= 0.903  precision=0.950  recall=0.836  cache-hit rate=0.222
```

Every request now "hits" the cache, and **three out of four cached answers are wrong**. The dashboard reports a great hit rate. Re-derived on B, the threshold is 0.903. A difference of 0.25 in τ is the size of the bug.

**Rules:**

1. A similarity threshold belongs to a **(model, version, dims, normalization, task)** tuple. Store it with the index, never in a global constant.
2. Re-derive thresholds from a **labelled pair set** whenever any element of the tuple changes. Section 4 shows how to build that set cheaply.
3. Mean-centering is a legitimate fix for spread, but it changes the metric, so re-validate recall (01.2 shows the trade-off), and freeze the mean vector with the index version.

### 1.8 Is cosine even the right similarity? `[GOOD-TO-KNOW: Architectural Literacy]`

Steck, Ekanadham and Kallus (Netflix, arXiv 2403.05440, 2024) show analytically that for embeddings learned with regularized linear models, cosine similarities **can be arbitrary**. A degree of freedom in the learned embeddings (a per-dimension rescaling that leaves the training objective unchanged) changes the cosines, and in some setups they are not unique at all. They argue the same risk carries over to deep models with mixed regularizers, and recommend caution about applying cosine blindly.

The practical reading for an AI engineer is not to "stop using cosine". It is:

- **Use the similarity the model was trained with.** Model cards say "use cosine", "use dot product", or "normalize then dot". Some dense retrievers are trained with a raw dot product and their norms carry signal (§1.4).
- **Respect the model's asymmetry.** Many retrieval models embed queries and documents differently:
  - E5-style models want `"query: "` and `"passage: "` prefixes.
  - Gemini's `gemini-embedding-001` takes a `task_type` such as `RETRIEVAL_QUERY` vs `RETRIEVAL_DOCUMENT`. Per the Gemini docs, `gemini-embedding-2` drops the field in favour of an instruction inside the prompt, e.g. `task: search result | query: {content}`.
  - Embedding a query as a document (or skipping the prefix) is a quiet recall loss. Its size depends on the model, so measure it on your own eval set before and after fixing it (⚠ no universal number).
- **Validate on task labels, not on geometric intuition.** The arbiter is your eval set (recall@k, nDCG, routing accuracy; Folder 06), never "the cosines look reasonable".

### 1.9 Johnson–Lindenstrauss: how many dimensions do pairwise distances need? `[GOOD-TO-KNOW: Architectural Literacy]`

**JL lemma** (in the Dasgupta–Gupta form). For any n points and any 0 < ε < 1, a *random* linear map to k dimensions preserves every pairwise squared distance within a factor (1 ± ε) with positive probability, provided

```text
k ≥ 4 ln n / (ε²/2 − ε³/3)
```

Plug in production numbers. For n = 10M documents (ln n = 16.12):

| ε (distance distortion) | required k |
|---:|---:|
| 0.30 | 1,791 |
| 0.20 | 3,720 |
| 0.10 | 13,815 |

JL says a random projection of 10M points needs **13,815** dims for 10% distortion, which is more than the 3072 your model emits. Yet PCA to 64 dims keeps recall ≈ 0.995 on structured data (01.2). Both are true because JL is a **worst-case, data-oblivious** guarantee: it holds for *any* point set, including adversarial ones with no structure. Real embeddings have low intrinsic dimension (§1.6), so a *data-aware* method (PCA, or a model trained for truncation, i.e. Matryoshka) does far better. JL is the right tool when you can't look at the data (streaming sketches, privacy-preserving projections), and it is the floor that learned compression should beat.

### 1.10 Quantization geometry: float16, int8, binary, and the SimHash law `[MUST-KNOW: Core AI Engineer Edge]`

Memory is the first wall a vector system hits. For 10M × 1024-dim vectors (vectors only, no index overhead):

| precision | bytes/dim | total | compression |
|---|---:|---:|---:|
| float32 | 4 | 40.96 GB | 1× |
| float16 / bfloat16 (pgvector `halfvec`) | 2 | 20.48 GB | 2× |
| int8 scalar | 1 | 10.24 GB | 4× |
| binary (sign bit; pgvector `bit`) | 1/8 | 1.28 GB | 32× |

**float16** has a 10-bit mantissa, so relative rounding is ~5e-4. Ranking is essentially unaffected: §3.3 measures recall@10 = **1.000** on 20k × 384. Its range limit (max 65,504) only matters for un-normalized intermediate values. pgvector's HNSW indexes `halfvec` up to 4,000 dims vs 2,000 for `vector`, which makes halfvec the default for 3072-d models in Postgres.

**int8, the offset trap.** The common recipe (sentence-transformers) maps each dimension's calibration range [loⱼ, hiⱼ] onto 256 levels: `cⱼ = round((xⱼ − loⱼ)/sⱼ) − 128`. Now compute what an int8 kernel actually sums:

```text
cⱼ ≈ xⱼ/sⱼ + bⱼ        with bⱼ = −loⱼ/sⱼ − 128   (a per-dimension offset)

Σⱼ cⱼ(q) cⱼ(d) ≈ Σⱼ qⱼdⱼ/sⱼ²  +  Σⱼ bⱼ(qⱼ + dⱼ)/sⱼ  +  Σⱼ bⱼ²
                  ─────────      ───────────────      ─────
              re-weighted dot   a per-DOCUMENT bias   constant
```

The integer dot product is the true dot product **re-weighted per dimension (1/sⱼ²) plus a bias term that depends on the document**. The bias ranks documents by how large their coordinates are, independent of the query. §3.3 measures **recall@10 = 0.629** for that raw dot. Two fixes:

- **Symmetric quantization with one global scale** (`c = round(x/s)`, zero-point 0). The integer dot is then *proportional* to the float dot, up to rounding. Measured recall@10: **0.980**, with no rescoring.
- **Rescoring** (the HF recipe). Shortlist k × 4 with the int8 index, then rescore with the float32 query against the *dequantized* documents. Measured: **0.958**.

The Hugging Face study reports int8 keeping **~97%** of retrieval performance (NDCG@10) without rescoring and **~99.3%** with it, on real MTEB retrieval tasks with mxbai-embed-large-v1. Its numbers are task metrics and ours are neighbor recall, and the two are not the same (the bar-raiser chain in §6 covers why).

**Binary and the SimHash law.** Keep only the sign of each coordinate: 1 bit per dimension, compared by Hamming distance (`XOR` + `popcount`). Why does that preserve anything? Charikar (STOC 2002) gives the answer for *random* hyperplanes.

**Theorem.** If h is a uniformly random direction and `bit(x) = [h·x > 0]`, then `P[bit(u) ≠ bit(v)] = θ(u,v)/π`.

**Proof.** Only the component of h inside the 2-D plane spanned by u and v affects the two signs, and that component's direction is uniform on the circle. The hyperplane `h·x = 0` cuts the circle along a random diameter. The bits differ exactly when that diameter falls inside the angle between u and v (or its mirror image), which covers 2θ of the 2π circle. So the probability is 2θ/2π = θ/π. ∎

```text
          v
          ●            the random diameter (hyperplane) separates u and v
         /             iff it lands in the shaded wedge of angle θ
        / θ            (or its mirror image): probability 2θ / 2π = θ/π
       o──────● u
```

With K random hyperplanes, `Hamming/K` is an unbiased estimate of θ/π. §3.3 part 1 measures it with 2048 hyperplanes: θ = 30° gives **0.1667** (θ/π = 0.1667), and θ = 90° gives **0.5001**.

Sign-quantizing the *coordinates* of an embedding is SimHash with the coordinate axes as hyperplanes. It works to the extent that those axes behave like generic directions. Two production facts follow from the listing:

1. **Anisotropy wastes bits.** With a shared mean direction, **20.1%** of coordinate bits have P(1) outside [0.2, 0.8]: they are nearly constant and carry little information. Centering before taking signs makes every bit balanced (**0.0%** wasted). In our data the recall gain is modest (0.365 → 0.367 Hamming-only, 0.756 → 0.781 at ×4 rescoring), so measure it on yours before adding a centering step to the pipeline.
2. **Rescoring depth is the big lever.** Hamming-only recall@10 is **0.365**. Shortlisting top-100 by Hamming (×10) and rescoring with float32 documents gives **0.995**. A binary first stage is a *candidate generator*, not a ranker.

The HF study reports binary keeping **92.53%** of MTEB retrieval performance without rescoring and **96.45%** with it, for mxbai-embed-large-v1. It also cuts 250M embeddings from 953.67 GB to 29.80 GB and measures a **24.76×** average speedup with optimized popcount kernels. Our NumPy timing (binary 781 µs vs float32 BLAS 1,765 µs per 20k-vector scan) shows only ~2×, because NumPy's `bitwise_count` loop is no match for a SIMD popcount kernel. The 32× memory saving is the robust part, and the speedup depends on the engine.

### 1.11 Router decision regions are Voronoi cells, and a centroid router is a linear classifier `[MUST-KNOW: Core AI Engineer Edge]`

A nearest-centroid router assigns a query q (unit) to `argmaxᵢ q·cᵢ` over normalized intent centroids cᵢ. The boundary between intents i and j is the set where scores tie:

```text
q·cᵢ = q·cⱼ   ⇔   q·(cᵢ − cⱼ) = 0
```

That is a **hyperplane through the origin** with normal `cᵢ − cⱼ`. The decision regions are therefore Voronoi cells on the sphere, bounded by great-circle bisectors. The router is a **linear multiclass classifier** with weight matrix C (one row per intent) and zero bias. That has two consequences:

1. Anything a logistic-regression head can learn on frozen embeddings includes this router as a special case. Folder 02 trains that head, and it usually wins when you have more than a few dozen labelled examples per intent, because it learns *discriminative* directions instead of averages.
2. **Abstention is geometry, too.** "Escalate to the LLM when unsure" means two regions: (a) a **margin band** around each bisector, `top1 − top2 < δ`, and (b) a **far-from-everything cap**, `top1 < τ`, which catches out-of-domain queries that land in some cell only because every point on the sphere lands in some cell.

```text
           intent A cell          ╎          intent B cell
                                  ╎
        ● c_A          q₁ ●       ╎ ← bisector q·(c_A − c_B) = 0
                                ╎╎╎╎╎ ← margin band |q·c_A − q·c_B| < δ   → escalate
                                  ╎
   q₂ ●  (top1 < τ: far from every centroid → out-of-domain → escalate)
                                  ╎        ● c_B
```

§3.4 measures this trade-off on 12 synthetic intents with confusable siblings plus unseen out-of-domain topics. Never abstaining routes **100%** of OOD traffic to *some* intent. With τ = 0.70 and δ = 0.03, local accuracy rises from **0.912** to **0.991** on the 59.4% of in-domain traffic answered locally, and only **0.5%** of OOD is accepted. Section 2 turns that into dollars.

---

## 2. Where It Beats an LLM in Production

Each pattern below replaces an LLM call with a dot product, or puts a dot product in front of the call so the LLM only sees the traffic that needs it.

| Production task | Geometric primitive | What it replaces | Hot-path cost | Where it loses |
|---|---|---|---|---|
| Intent routing | `argmax q·C` over normalized centroids + abstain band (§1.11) | An LLM classification prompt per request | One embedding + ~19 µs kernel (measured, 12 intents) | Negation, compound requests, intents with no exemplars yet |
| Semantic cache | `max q·K ≥ τ_model` over cached prompt keys (§1.7) | A full LLM generation | One embedding + ANN lookup | Answers that depend on time, user or state; τ copied across models |
| Near-duplicate filter (ingest, dedup of eval sets) | SimHash / binary codes, Hamming ≤ r (§1.10) | LLM "are these the same?" judging | XOR + popcount, 32× less memory | Paraphrases with different facts: "same topic" is not "same claim" |
| OOD / "is this in scope?" guardrail | `max q·C < τ_ood` (§1.11) | An LLM scope check | Shares the router's computation | Adversarial prompts crafted to look in-scope (needs a classifier, Folder 02) |
| Retrieval first stage | Top-k by inner product (HNSW/IVF) | LLM re-reading the corpus (impossible at scale) | Sub-millisecond to milliseconds | Exact-identifier queries (SKUs, error codes), so you need BM25 hybrid (Folder 04) |

### The cost case, from the listing in §3.4

The listing computes per-call prices from published rates (as of 2026-10):

- An OpenAI `text-embedding-3-small` call on a 30-token query. The guide quotes 62,500 pages per dollar at ~800 tokens per page, which is $0.02 per million tokens.
- A Claude Haiku 5.5 classification call: 600 tokens of instructions and examples + the 30-token query in, 10 tokens out, at $0.10 / $0.50 per million input/output tokens.

```text
per call: embedding $0.0000006, LLM classification $0.000068  (ratio 113x)
```

That's the cheapest current model tier. The ratio grows linearly with the model you would otherwise call (same 630-in / 10-out call; prices from the Claude pricing page, cached 2026-10-06):

| LLM used as the classifier | $/MTok in / out | $ per classification call | × an embedding call |
|---|---:|---:|---:|
| Claude Haiku 5.5 | 0.10 / 0.50 | 0.000068 | 113× |
| Claude Sonnet 5.5 | 2.00 / 10.00 | 0.00136 | 2,267× |
| Claude Opus 5.5 | 4.00 / 20.00 | 0.00272 | 4,533× |

A self-hosted encoder takes the embedding's marginal price toward zero (you pay for CPU or GPU time instead). The cost ratio is not the most interesting result, though. This is:

```text
policy                         escalated  $ / 1M req  blended in-domain acc
LLM for everything                 1.000       68.00                  0.970
router never abstain               0.000        0.60                  0.912
router tau=0.65 delta=0.03         0.477       33.05                  0.982
```

The router with an abstain band answers the easy 61% of in-domain traffic locally, at **0.990** accuracy, and escalates the ambiguous rest. Its blended accuracy (**0.982**) *beats* the all-LLM baseline (0.970) at **49%** of the cost. The listing *assumes* the LLM fallback is 97% accurate; replace that with your measured number. The structure of the result holds whenever the cheap model is very accurate on the cases it is confident about, which is exactly what calibrated abstention selects. Folders 02 and 07 build this into a full cascade.

The "never abstain" row is the trap: cheapest by far (**$0.60** per 1M requests), but it routes 100% of out-of-domain traffic to *some* intent, and it is 6 points less accurate.

**Latency.** The routing kernel measured **19 µs** for one query against 12 centroids and **0.75 µs per query** in a 256-query batch (one BLAS thread). End-to-end, the query embedding dominates: an API round trip or a local encoder forward pass. Measure yours. It is usually well below a generation round trip (TTFT plus decode for even a 10-token answer), but the gap depends on your provider, region and load (⚠ measure, don't assume).

### When the geometry is the wrong tool

- **Negation and constraints.** "Cancel my order but *not* the subscription" sits close to "cancel my subscription" in most embedding spaces. Route negation-heavy or multi-clause requests to the LLM, or detect them with a cheap classifier first.
- **Compositional queries** ("orders over $500 shipped to Texas last month") are structured retrieval, not similarity. Use SQL or tools.
- **Day-0 intents** with no exemplars. Let the LLM handle them, *log its decisions as labels*, and promote the intent into the router once you have a few dozen examples. That's a data flywheel in the data-centric spirit: the expensive model labels data for the cheap one, and you audit a sample of those labels before trusting them.
- **Long, multi-intent messages.** A single vector averages several intents into a point that matches none. Split first (by sentence or clause), or let the LLM decompose.

---

## 3. Production Code Blueprint

All four listings run on CPU with one BLAS thread, in seconds. Seeded outputs reproduce exactly. Timing lines are "one measured run" and will differ on your machine.

### 3.1 Proving the identities your index depends on

What it checks: cosine = dot on the sphere; ‖a−b‖² = 2 − 2cos and identical top-k; how badly unnormalized vectors disagree; the float32 ulp past ±1; the triangle-inequality counterexample; the MIPS→L2 reduction; zero vectors.

```python
"""unit_sphere_identities.py - the geometry identities every vector index silently relies on, checked numerically.

  1. On the unit sphere cosine similarity IS the dot product.
  2. ||a-b||^2 = 2 - 2cos(a,b) for unit vectors, so L2, cosine and dot return the same top-k.
  3. Without normalization the three metrics disagree, and dot product prefers long vectors.
  4. Cauchy-Schwarz bounds cosine to [-1, 1] in exact math; float32 can overshoot by an ulp.
  5. Cosine *distance* (1 - cos) breaks the triangle inequality; angular and chord distance do not.
  6. One extra coordinate turns inner-product search (MIPS) into L2 nearest-neighbour search.
  7. A zero vector makes cosine NaN, so it has to be rejected at ingest.
"""
import numpy as np

rng = np.random.default_rng(7)
N, D, Q, K = 20_000, 384, 200, 10


def l2n(x):
    return x / np.linalg.norm(x, axis=-1, keepdims=True)


def topk(scores, k, largest=True):
    s = -scores if largest else scores
    idx = np.argpartition(s, k, axis=1)[:, :k]                    # O(N) selection, then sort the k
    order = np.take_along_axis(s, idx, axis=1).argsort(axis=1, kind="stable")
    return np.take_along_axis(idx, order, axis=1)


def same_sets(a, b):
    return np.array([set(x) == set(y) for x, y in zip(a, b)])


# clustered corpus: 100 topic centres, docs scattered around them (structure like real embeddings)
centres = rng.standard_normal((100, D))
topic = rng.integers(0, 100, N)
raw = (centres[topic] + 0.9 * rng.standard_normal((N, D))).astype(np.float32)
docs = l2n(raw).astype(np.float32)
qs = l2n(docs[rng.integers(0, N, Q)] + 0.05 * rng.standard_normal((Q, D))).astype(np.float32)

print("== 1. cosine == dot on the unit sphere ==")
dot = qs @ docs.T
cos = (qs @ docs.T) / (np.linalg.norm(qs, axis=1)[:, None] * np.linalg.norm(docs, axis=1)[None, :])
print(f"max |cos - dot| (float32, {Q}x{N} pairs) = {np.abs(cos - dot).max():.2e}")
nrm = np.linalg.norm(docs.astype(np.float64), axis=1)
print(f"float32 unit vectors: max | ||x|| - 1 | = {np.abs(nrm - 1).max():.2e}")
assert np.abs(cos - dot).max() < 1e-6

print("\n== 2. ||a-b||^2 = 2 - 2 cos  =>  identical top-k ==")
q64, d64 = qs.astype(np.float64), docs.astype(np.float64)
l2sq = (q64 ** 2).sum(1)[:, None] + (d64 ** 2).sum(1)[None, :] - 2 * q64 @ d64.T
print(f"max |L2^2 - (2 - 2cos)| (float64) = {np.abs(l2sq - (2 - 2 * (q64 @ d64.T))).max():.2e}")
t_dot, t_cos = topk(dot, K), topk(cos, K)
l2sq32 = (qs ** 2).sum(1)[:, None] + (docs ** 2).sum(1)[None, :] - 2 * dot   # how FAISS/most engines expand L2
t_l2 = topk(l2sq32, K, largest=False)
print(f"queries whose top-{K} SET agrees  dot vs cos: {same_sets(t_dot, t_cos).sum()}/{Q}   "
      f"dot vs L2: {same_sets(t_dot, t_l2).sum()}/{Q}")
gap = np.sort(dot, axis=1)[:, ::-1]
print(f"smallest score gap between rank {K} and {K + 1} over queries = {np.min(gap[:, K - 1] - gap[:, K]):.2e}"
      "  (float32 ties below ~1e-7 are the only way the sets can differ)")
assert same_sets(t_dot, t_cos).mean() > 0.99 and same_sets(t_dot, t_l2).mean() > 0.99

print("\n== 3. NOT normalized: the metrics disagree ==")
norms = np.exp(0.5 * rng.standard_normal(N)).astype(np.float32)        # log-normal lengths
un = docs * norms[:, None]
s_dot = qs @ un.T
s_cos = s_dot / (np.linalg.norm(un, axis=1)[None, :])
s_l2 = (un ** 2).sum(1)[None, :] - 2 * s_dot                              # ||q||^2 is constant per query
a, b, c = topk(s_dot, K), topk(s_cos, K), topk(s_l2, K, largest=False)
ov = lambda x, y: np.mean([len(set(i) & set(j)) / K for i, j in zip(x, y)])
print(f"mean top-{K} overlap  dot~cos {ov(a, b):.3f}   L2~cos {ov(c, b):.3f}   dot~L2 {ov(a, c):.3f}")
print(f"mean doc norm: corpus {norms.mean():.2f} | dot top-{K} {norms[a].mean():.2f} | "
      f"cos top-{K} {norms[b].mean():.2f} | L2 top-{K} {norms[c].mean():.2f}")
assert ov(a, b) < 0.9 and norms[a].mean() > norms.mean() > norms[c].mean()

print("\n== 4. Cauchy-Schwarz and the float32 ulp ==")
x = l2n(rng.standard_normal((100_000, D)).astype(np.float32)).astype(np.float32)
self_cos = np.einsum("ij,ij->i", x, x)
print(f"self-similarity in float32: max {self_cos.max():.9f}, count > 1.0: {(self_cos > 1).sum()}")
with np.errstate(invalid="ignore"):
    bad = np.isnan(np.arccos(self_cos)).sum()
print(f"np.arccos(cos) -> NaN for {bad} of 100000 self-pairs; np.clip(cos, -1, 1) fixes all of them")
assert np.isnan(np.arccos(np.clip(self_cos, -1, 1))).sum() == 0

print("\n== 5. triangle inequality ==")
pa, pb, pc = np.array([1.0, 0.0]), np.array([np.sqrt(0.5), np.sqrt(0.5)]), np.array([0.0, 1.0])
dc = lambda u, v: 1 - u @ v
da = lambda u, v: np.arccos(np.clip(u @ v, -1, 1))
dl = lambda u, v: np.linalg.norm(u - v)
for name, f in (("cosine distance 1-cos", dc), ("angular distance", da), ("chord (L2) distance", dl)):
    lhs, rhs = f(pa, pc), f(pa, pb) + f(pb, pc)
    print(f"{name:22s} d(a,c)={lhs:.4f}  d(a,b)+d(b,c)={rhs:.4f}  -> {'VIOLATED' if lhs > rhs + 1e-12 else 'holds'}")
trip = l2n(rng.standard_normal((30_000, 3, 8)))              # random triples in 8-D (near-ish points)
u, v, w = trip[:, 0], trip[:, 1], trip[:, 2]
cuv, cvw, cuw = (u * v).sum(1), (v * w).sum(1), (u * w).sum(1)
viol = lambda f: int(np.sum(f(cuw) > f(cuv) + f(cvw) + 1e-12))
print(f"violations in 30000 random 8-D triples: 1-cos {viol(lambda z: 1 - z)} | "
      f"arccos {viol(lambda z: np.arccos(np.clip(z, -1, 1)))} | chord {viol(lambda z: np.sqrt(np.maximum(2 - 2 * z, 0)))}")
assert dc(pa, pc) > dc(pa, pb) + dc(pb, pc) and viol(lambda z: np.sqrt(np.maximum(2 - 2 * z, 0))) == 0

print("\n== 6. MIPS -> L2 nearest neighbour with one extra coordinate ==")
M = np.linalg.norm(un, axis=1).max()
ext = np.sqrt(np.maximum(M ** 2 - (un.astype(np.float64) ** 2).sum(1), 0))
aug_docs = np.hstack([un.astype(np.float64), ext[:, None]])
aug_q = np.hstack([q64, np.zeros((Q, 1))])
l2_aug = (aug_docs ** 2).sum(1)[None, :] - 2 * aug_q @ aug_docs.T       # = M^2 - 2 q.x  (+||q||^2)
t_mips, t_aug = topk(q64 @ un.astype(np.float64).T, K), topk(l2_aug, K, largest=False)
print(f"exact MIPS top-{K} reproduced by L2 on augmented vectors: {same_sets(t_mips, t_aug).sum()}/{Q} queries")
print(f"extra coordinate: mean {ext.mean():.3f} vs mean |x_j| {np.abs(un).mean():.3f}  "
      f"(it dominates the vector -> ANN graphs/quantizers degrade; normalize at training time if you can)")
assert same_sets(t_mips, t_aug).all()

print("\n== 7. zero vectors ==")
z = np.zeros(D, dtype=np.float32)
with np.errstate(invalid="ignore", divide="ignore"):
    c0 = (z @ docs[0]) / (np.linalg.norm(z) * np.linalg.norm(docs[0]))
print(f"cos(zero, doc) = {c0}  -> NaN sorts unpredictably and poisons top-k; reject ||x|| < 1e-6 at ingest")
assert np.isnan(c0)
print("\nALL ASSERTIONS PASSED")
```

Output (verified):

```text
== 1. cosine == dot on the unit sphere ==
max |cos - dot| (float32, 200x20000 pairs) = 8.94e-08
float32 unit vectors: max | ||x|| - 1 | = 9.63e-08

== 2. ||a-b||^2 = 2 - 2 cos  =>  identical top-k ==
max |L2^2 - (2 - 2cos)| (float64) = 2.05e-07
queries whose top-10 SET agrees  dot vs cos: 200/200   dot vs L2: 200/200
smallest score gap between rank 10 and 11 over queries = 8.91e-06  (float32 ties below ~1e-7 are the only way the sets can differ)

== 3. NOT normalized: the metrics disagree ==
mean top-10 overlap  dot~cos 0.112   L2~cos 0.262   dot~L2 0.006
mean doc norm: corpus 1.13 | dot top-10 2.76 | cos top-10 1.13 | L2 top-10 0.50

== 4. Cauchy-Schwarz and the float32 ulp ==
self-similarity in float32: max 1.000000358, count > 1.0: 21259
np.arccos(cos) -> NaN for 21259 of 100000 self-pairs; np.clip(cos, -1, 1) fixes all of them

== 5. triangle inequality ==
cosine distance 1-cos  d(a,c)=1.0000  d(a,b)+d(b,c)=0.5858  -> VIOLATED
angular distance       d(a,c)=1.5708  d(a,b)+d(b,c)=1.5708  -> holds
chord (L2) distance    d(a,c)=1.4142  d(a,b)+d(b,c)=1.5307  -> holds
violations in 30000 random 8-D triples: 1-cos 937 | arccos 0 | chord 0

== 6. MIPS -> L2 nearest neighbour with one extra coordinate ==
exact MIPS top-10 reproduced by L2 on augmented vectors: 200/200 queries
extra coordinate: mean 7.812 vs mean |x_j| 0.046  (it dominates the vector -> ANN graphs/quantizers degrade; normalize at training time if you can)

== 7. zero vectors ==
cos(zero, doc) = nan  -> NaN sorts unpredictably and poisons top-k; reject ||x|| < 1e-6 at ingest

ALL ASSERTIONS PASSED
```

How to read it:

- **Claim 2.** The top-10 *sets* agree on 200/200 queries between dot, cosine and expanded L2 (`‖q‖² + ‖d‖² − 2q·d`, the form FAISS and most engines compute). The smallest gap at the rank-10/11 boundary is 8.9e-6, two orders of magnitude above float32 rounding, so no tie could flip.
- **Claim 3** is the reason for the "normalize at ingest" invariant. With log-normal norms, the three metrics share almost nothing (overlap 0.112 / 0.262 / 0.006), and each is biased in its own direction: dot toward long vectors (mean norm 2.76), L2 toward short ones (0.50).
- **Claim 4.** 21% of float32 self-similarities exceed 1.0. Always `np.clip(cos, -1, 1)` before `arccos`, `sqrt(1 − c²)` or `log(1 − c)`.

### 3.2 Concentration, anisotropy, and why thresholds don't transfer

```python
"""high_dim_concentration.py - why "cosine > 0.8" means nothing until you calibrate it for one model.

  A. Random directions in R^d are nearly orthogonal: cos ~ N(0, 1/d).
  B. Distance contrast (Dmax - Dmin)/Dmin collapses for structureless data as d grows,
     but survives for data with low intrinsic dimension (which is what real embeddings have).
  C. Anisotropy: a shared direction squeezes every cosine into a narrow band near the top.
  D. A semantic-cache threshold tuned on one embedding space is wrong for another.
"""
import numpy as np

rng = np.random.default_rng(11)


def l2n(x):
    return x / np.linalg.norm(x, axis=-1, keepdims=True)


print("== A. random unit vectors: cosine concentrates at 0 with std 1/sqrt(d) ==")
print(f"{'d':>6} {'mean cos':>9} {'std cos':>8} {'1/sqrt(d)':>9} {'P(|cos|>0.1)':>13}")
for d in (2, 8, 32, 128, 384, 768, 1536, 3072):
    a, b = l2n(rng.standard_normal((20_000, d))), l2n(rng.standard_normal((20_000, d)))
    c = (a * b).sum(1)
    print(f"{d:>6} {c.mean():>9.4f} {c.std():>8.4f} {1 / np.sqrt(d):>9.4f} {np.mean(np.abs(c) > 0.1):>13.4f}")
    if d >= 128:
        assert abs(c.std() * np.sqrt(d) - 1) < 0.05

print("\n== B. relative contrast (Dmax - Dmin)/Dmin, 2000 points, mean over 50 queries ==")
print(f"{'d':>6} {'uniform cube':>13} {'16-D latent in d-D':>19}")
contrast = {}
for d in (2, 16, 128, 768, 3072):
    out = []
    for kind in ("uniform", "latent"):
        if kind == "uniform":
            x = rng.random((2050, d))
        else:                                                   # 40 clusters on a 16-D manifold, embedded in d dims
            basis = np.linalg.qr(rng.standard_normal((d, 16)))[0] if d >= 16 else np.eye(d)
            z = rng.standard_normal((40, basis.shape[1]))[rng.integers(0, 40, 2050)] \
                + 0.15 * rng.standard_normal((2050, basis.shape[1]))
            x = z @ basis.T + 0.01 * rng.standard_normal((2050, d))
        q, p = x[:50], x[50:]
        dist = np.sqrt(np.maximum((q ** 2).sum(1)[:, None] + (p ** 2).sum(1)[None] - 2 * q @ p.T, 0))
        out.append(np.mean((dist.max(1) - dist.min(1)) / dist.min(1)))
    contrast[d] = out
    print(f"{d:>6} {out[0]:>13.3f} {out[1]:>19.3f}")
assert contrast[3072][0] < 0.2 * contrast[16][0] and contrast[3072][1] > 5 * contrast[3072][0]

print("\n== C. anisotropy: same semantics, two geometries ==")
D, T, PER = 384, 60, 40
topics = rng.standard_normal((T, D))
spread = rng.uniform(0.35, 1.1, (3 * T, 1))                                     # how far each intent sits from its topic
intents = topics.repeat(3, axis=0) + spread * rng.standard_normal((3 * T, D))   # 3 intents per topic
noise = rng.uniform(0.35, 1.0, (3 * T, 1)).repeat(PER, axis=0)                  # how varied each intent's phrasings are
base = intents.repeat(PER, axis=0) + noise * rng.standard_normal((3 * T * PER, D))
label_int = np.arange(3 * T).repeat(PER)
label_top = label_int // 3
A = l2n(base)                                                                    # "model A": isotropic-ish
mu = l2n(rng.standard_normal(D))
B = l2n(A + 1.6 * mu)                                                            # "model B": shared direction
C = l2n(B - B.mean(0))                                                           # model B after mean-centering
n = len(A)
i, j = rng.integers(0, n, 60_000), rng.integers(0, n, 60_000)
keep = i != j
i, j = i[keep], j[keep]
same_int = label_int[i] == label_int[j]
same_top = (label_top[i] == label_top[j]) & ~same_int
rand = label_top[i] != label_top[j]
print(f"{'space':28s} {'random pair':>12} {'same topic':>11} {'same intent':>12} {'band width':>11}")
stats = {}
for name, E in (("A isotropic", A), ("B anisotropic (shared mu)", B), ("B mean-centred", C)):
    s = (E[i] * E[j]).sum(1)
    r, t_, p = s[rand].mean(), s[same_top].mean(), s[same_int].mean()
    stats[name] = (r, t_, p)
    print(f"{name:28s} {r:>12.3f} {t_:>11.3f} {p:>12.3f} {p - r:>11.3f}")
assert stats["B anisotropic (shared mu)"][0] > 0.6 and stats["B mean-centred"][2] - stats["B mean-centred"][0] > 0.3

print("\n== D. semantic-cache threshold transfer (positive = same intent) ==")
def pr_at(s, y, thr):
    hit = s >= thr
    prec = (y & hit).sum() / max(hit.sum(), 1)
    rec = (y & hit).sum() / y.sum()
    return prec, rec, hit.mean()

# evaluation pairs enriched with hard negatives: half same-topic, a quarter same-intent, a quarter random
pairs_i, pairs_j = [], []
for _ in range(40_000):
    a = rng.integers(0, n)
    kind = rng.random()
    if kind < 0.25:
        pool = np.flatnonzero(label_int == label_int[a])
    elif kind < 0.75:
        pool = np.flatnonzero((label_top == label_top[a]) & (label_int != label_int[a]))
    else:
        pool = np.flatnonzero(label_top != label_top[a])
    b = rng.choice(pool[pool != a])
    pairs_i.append(a), pairs_j.append(b)
pi, pj = np.array(pairs_i), np.array(pairs_j)
y = label_int[pi] == label_int[pj]
sA, sB = (A[pi] * A[pj]).sum(1), (B[pi] * B[pj]).sum(1)

def thr_for_precision(s, y, target):
    for thr in np.linspace(-1, 1, 4001):
        p, r, _ = pr_at(s, y, thr)
        if p >= target and (s >= thr).sum() > 0:
            return thr
    return 1.0

tA = thr_for_precision(sA, y, 0.95)
tB = thr_for_precision(sB, y, 0.95)
for name, s, thr in (("A @ its own threshold", sA, tA), ("B @ A's threshold", sB, tA), ("B @ its own threshold", sB, tB)):
    p, r, h = pr_at(s, y, thr)
    print(f"{name:24s} thr={thr:6.3f}  precision={p:.3f}  recall={r:.3f}  cache-hit rate={h:.3f}")
pB_bad = pr_at(sB, y, tA)[0]
assert pB_bad < 0.5 and tB - tA > 0.15
print("\nALL ASSERTIONS PASSED")
```

Output (verified):

```text
== A. random unit vectors: cosine concentrates at 0 with std 1/sqrt(d) ==
     d  mean cos  std cos 1/sqrt(d)  P(|cos|>0.1)
     2   -0.0032   0.7065    0.7071        0.9362
     8   -0.0036   0.3545    0.3536        0.7973
    32   -0.0011   0.1755    0.1768        0.5754
   128   -0.0005   0.0883    0.0884        0.2591
   384   -0.0000   0.0516    0.0510        0.0520
   768   -0.0001   0.0362    0.0361        0.0060
  1536   -0.0000   0.0256    0.0255        0.0001
  3072    0.0003   0.0180    0.0180        0.0000

== B. relative contrast (Dmax - Dmin)/Dmin, 2000 points, mean over 50 queries ==
     d  uniform cube  16-D latent in d-D
     2       115.743             214.058
    16         1.956              13.731
   128         0.390              12.320
   768         0.145              10.722
  3072         0.070               6.671

== C. anisotropy: same semantics, two geometries ==
space                         random pair  same topic  same intent  band width
A isotropic                        -0.000       0.510        0.773       0.774
B anisotropic (shared mu)           0.718       0.862        0.936       0.218
B mean-centred                     -0.010       0.505        0.771       0.781

== D. semantic-cache threshold transfer (positive = same intent) ==
A @ its own threshold    thr= 0.651  precision=0.950  recall=0.852  cache-hit rate=0.227
B @ A's threshold        thr= 0.651  precision=0.253  recall=1.000  cache-hit rate=1.000
B @ its own threshold    thr= 0.903  precision=0.950  recall=0.836  cache-hit rate=0.222

ALL ASSERTIONS PASSED
```

How to read it:

- **Part A** is the 1/√d law. The `P(|cos| > 0.1)` column is the practical version: at d ≥ 768, unrelated random directions almost never exceed 0.1. If your unrelated pairs sit at 0.3+, your model is anisotropic, not noisy.
- **Part B.** Uniform data loses its distance contrast (0.070 at d = 3072). Data on a 16-D manifold keeps it (6.671). Intrinsic dimension, not ambient dimension, decides whether nearest-neighbour search is meaningful.
- **Parts C–D** are the threshold-transfer incident in numbers. The same semantics, but a different geometry: A's precision-0.95 threshold (0.651) applied to B gives precision 0.253 with a 100% "hit rate". The threshold is a property of the space.

### 3.3 Quantization: memory, recall, and rescoring

```python
"""embedding_quantization_recall.py - float16 / int8 / binary embeddings: memory, recall@10, rescoring, and why centering matters.

  1. SimHash law: with random hyperplanes, P(bit differs) = angle / pi, so Hamming distance estimates angle.
  2. Recall@10 vs exact float32 search for float16, int8 (calibrated ranges) and 1-bit sign codes,
     with and without rescoring the shortlist.
  3. Sign codes on an anisotropic space waste bits; subtracting the corpus mean first recovers recall.
  4. Memory for 10M x 1024 vectors at each precision.
"""
import time

import numpy as np

rng = np.random.default_rng(3)
N, D, Q, K, MULT = 20_000, 384, 300, 10, 4


def l2n(x):
    return x / np.linalg.norm(x, axis=-1, keepdims=True)


def topk(s, k):
    idx = np.argpartition(-s, k, axis=1)[:, :k]
    return np.take_along_axis(idx, np.take_along_axis(-s, idx, axis=1).argsort(axis=1, kind="stable"), axis=1)


def recall(found, truth):
    return np.mean([len(set(f[:K]) & set(t)) / K for f, t in zip(found, truth)])


print("== 1. SimHash: Hamming fraction vs angle/pi (2048 random hyperplanes, 2000 pairs per angle) ==")
H = rng.standard_normal((D, 2048))
print(f"{'angle':>6} {'theta/pi':>9} {'measured':>9}")
for deg in (10, 30, 60, 90, 120):
    th = np.deg2rad(deg)
    u = l2n(rng.standard_normal((2000, D)))
    w = l2n(rng.standard_normal((2000, D)))
    w = l2n(w - (w * u).sum(1, keepdims=True) * u)                   # orthogonal to u
    v = np.cos(th) * u + np.sin(th) * w
    frac = np.mean((u @ H > 0) != (v @ H > 0))
    print(f"{deg:>5}d {th / np.pi:>9.4f} {frac:>9.4f}")
    assert abs(frac - th / np.pi) < 0.01

# anisotropic, clustered corpus (mean pairwise cosine ~0.3, like many real text-embedding models)
mu = l2n(rng.standard_normal(D))
topics = rng.standard_normal((200, D))
docs = l2n(l2n(topics[rng.integers(0, 200, N)] + 0.8 * rng.standard_normal((N, D))) + 0.65 * mu).astype(np.float32)
qs = l2n(docs[rng.integers(0, N, Q)] + 0.04 * rng.standard_normal((Q, D))).astype(np.float32)
pair = rng.integers(0, N, (5000, 2))
print(f"\ncorpus: {N} x {D}, mean random-pair cosine {np.mean((docs[pair[:, 0]] * docs[pair[:, 1]]).sum(1)):.3f}")
truth = topk(qs @ docs.T, K)

results = {}
# float16 storage ("halfvec"): upcast to float32 for the arithmetic
d16, q16 = docs.astype(np.float16), qs.astype(np.float16)
results["float16"] = recall(topk(q16.astype(np.float32) @ d16.astype(np.float32).T, K), truth)

# int8 with per-dimension ranges from a calibration sample (the sentence-transformers recipe)
cal = docs[rng.choice(N, 2000, replace=False)]
lo, hi = cal.min(0), cal.max(0)
step = (hi - lo) / 255.0
to_i8 = lambda x: np.clip(np.round((x - lo) / step) - 128, -128, 127).astype(np.int8)
deq = lambda c: (c.astype(np.float32) + 128) * step + lo
d8, q8 = to_i8(docs), to_i8(qs)
s8 = q8.astype(np.int32) @ d8.astype(np.int32).T                      # what an int8 kernel computes
results["int8 raw dot"] = recall(topk(s8.astype(np.float64), K), truth)
short = topk(s8.astype(np.float64), K * MULT)
resc = np.array([sh[np.argsort(-(deq(d8[sh]) @ q), kind="stable")] for sh, q in zip(short, qs)])
results["int8 + rescore (fp32 q . deq doc)"] = recall(resc, truth)
# symmetric int8 with ONE global scale: the integer dot is proportional to the float dot (up to rounding)
g = np.abs(cal).max() / 127.0
sym = lambda x: np.clip(np.round(x / g), -127, 127).astype(np.int8)
results["int8 symmetric (global scale) raw dot"] = recall(
    topk((sym(qs).astype(np.int32) @ sym(docs).astype(np.int32).T).astype(np.float64), K), truth)


def binary_run(center):
    shift = cal.mean(0) if center else np.zeros(D, dtype=np.float32)
    bits_d = (docs - shift) > 0
    bits_q = (qs - shift) > 0
    pd = np.packbits(bits_d, axis=1).view(np.uint64)                   # 384 bits = 6 x uint64 per vector
    pq = np.packbits(bits_q, axis=1).view(np.uint64)
    ham = np.stack([np.bitwise_count(pd ^ p).sum(1) for p in pq]).astype(np.float64)
    r_raw = recall(topk(-ham, K), truth)
    out = {}
    for mult in (MULT, 10):
        sh = topk(-ham, K * mult)
        signs = np.where(bits_d, 1.0, -1.0).astype(np.float32)
        hf = np.array([s[np.argsort(-(signs[s] @ (q - shift)), kind="stable")] for s, q in zip(sh, qs)])
        full = np.array([s[np.argsort(-(docs[s] @ q), kind="stable")] for s, q in zip(sh, qs)])
        out[mult] = (recall(hf, truth), recall(full, truth))
    p1 = bits_d.mean(0)
    wasted = np.mean((p1 < 0.2) | (p1 > 0.8))
    return r_raw, out, wasted, pd, pq


for center in (False, True):
    tag = "binary (centred)" if center else "binary (sign at 0)"
    r_raw, out, wasted, pd, pq = binary_run(center)
    results[f"{tag} hamming only"] = r_raw
    results[f"{tag} + rescore x{MULT} vs +-1 codes"] = out[MULT][0]
    results[f"{tag} + rescore x{MULT} vs fp32 docs"] = out[MULT][1]
    results[f"{tag} + rescore x10 vs fp32 docs"] = out[10][1]
    print(f"{tag}: bits with P(1) outside [0.2, 0.8] = {wasted:.1%}")

print(f"\n{'variant':48s} {'recall@10':>9}")
for k_, v in results.items():
    print(f"{k_:48s} {v:>9.3f}")
assert results["float16"] > 0.99 and results["int8 + rescore (fp32 q . deq doc)"] > 0.95
assert results["int8 symmetric (global scale) raw dot"] > results["int8 raw dot"] + 0.2
assert results["binary (centred) + rescore x10 vs fp32 docs"] > results["binary (centred) + rescore x4 vs fp32 docs"] > 0.7

print("\n== 4. memory for 10M vectors x 1024 dims (vectors only, no index overhead) ==")
n, d = 10_000_000, 1024
for name, bytes_per in (("float32", 4), ("float16 / bfloat16", 2), ("int8", 1), ("binary (1 bit)", 1 / 8)):
    print(f"{name:20s} {n * d * bytes_per / 1e9:8.2f} GB   (compression vs float32: {4 / bytes_per:.0f}x)")

print("\n== 5. brute-force scan of one query over 20k vectors (NumPy, one measured run, 1 thread) ==")
_, _, _, pd, pq = binary_run(True)
for name, fn in (("float32 BLAS matvec", lambda: docs @ qs[0]),
                 ("int8 -> int32 matvec", lambda: d8.astype(np.int32) @ q8[0].astype(np.int32)),
                 ("binary XOR + popcount", lambda: np.bitwise_count(pd ^ pq[0]).sum(1))):
    fn()
    t0 = time.perf_counter()
    for _ in range(50):
        fn()
    print(f"{name:24s} {(time.perf_counter() - t0) / 50 * 1e6:9.0f} us/query")
print("\nALL ASSERTIONS PASSED")
```

Output (verified recall; timing lines are one measured run):

```text
== 1. SimHash: Hamming fraction vs angle/pi (2048 random hyperplanes, 2000 pairs per angle) ==
 angle  theta/pi  measured
   10d    0.0556    0.0554
   30d    0.1667    0.1667
   60d    0.3333    0.3335
   90d    0.5000    0.5001
  120d    0.6667    0.6670

corpus: 20000 x 384, mean random-pair cosine 0.299
binary (sign at 0): bits with P(1) outside [0.2, 0.8] = 20.1%
binary (centred): bits with P(1) outside [0.2, 0.8] = 0.0%

variant                                          recall@10
float16                                              1.000
int8 raw dot                                         0.629
int8 + rescore (fp32 q . deq doc)                    0.958
int8 symmetric (global scale) raw dot                0.980
binary (sign at 0) hamming only                      0.365
binary (sign at 0) + rescore x4 vs +-1 codes         0.423
binary (sign at 0) + rescore x4 vs fp32 docs         0.756
binary (sign at 0) + rescore x10 vs fp32 docs        0.994
binary (centred) hamming only                        0.367
binary (centred) + rescore x4 vs +-1 codes           0.434
binary (centred) + rescore x4 vs fp32 docs           0.781
binary (centred) + rescore x10 vs fp32 docs          0.995

== 4. memory for 10M vectors x 1024 dims (vectors only, no index overhead) ==
float32                 40.96 GB   (compression vs float32: 1x)
float16 / bfloat16      20.48 GB   (compression vs float32: 2x)
int8                    10.24 GB   (compression vs float32: 4x)
binary (1 bit)           1.28 GB   (compression vs float32: 32x)

== 5. brute-force scan of one query over 20k vectors (NumPy, one measured run, 1 thread) ==
float32 BLAS matvec           1765 us/query
int8 -> int32 matvec         13797 us/query
binary XOR + popcount          781 us/query

ALL ASSERTIONS PASSED
```

How to read it:

- **float16 is free** for ranking (recall 1.000). Use it whenever the engine supports it (pgvector `halfvec`, FAISS `IndexHNSWSQ` fp16, most vector DBs).
- **int8 affine without offset correction (0.629) is a trap.** The per-document bias term derived in §1.10 dominates. Symmetric int8 with one global scale (0.980), or rescoring (0.958), fixes it.
- **Binary needs a rescoring stage.** Hamming alone gives 0.365. Rescoring top-100 against float32 originals gives 0.995. The ±1-code rescoring (the HF-style "float query · binary doc") recovers only part of the loss on this strict neighbor-recall metric.
- **Our metric is stricter than the HF study's.** We measure recall against the *exact* float32 neighbors among near-duplicates, which is the hardest case for 384 bits. Task metrics such as NDCG against human relevance labels degrade less, because swapping two near-identical relevant documents costs nothing there. Report both, and decide on the task metric.

### 3.4 A semantic router with an abstain-to-LLM policy

```python
"""semantic_router_kernel.py - a nearest-centroid semantic router with an abstain-to-LLM policy, plus its cost model.

The router is one matrix-vector product: unit-normalized query . unit-normalized intent centroids.
It answers locally when it is confident (top-1 score >= tau AND top1 - top2 >= delta) and escalates
everything else, including out-of-domain traffic, to an LLM classifier.
Embeddings are synthetic (12 intents in 4 domains, plus unseen OOD topics), so accuracy numbers show
the *shape* of the trade-off. Calibrate tau/delta on your own labelled traffic.
"""
import time

import numpy as np

rng = np.random.default_rng(5)
D, DOMAINS, PER_DOMAIN, TRAIN, TEST = 384, 4, 3, 40, 300


def l2n(x):
    return x / np.linalg.norm(x, axis=-1, keepdims=True)


class CentroidRouter:
    """Prototype router. Invariant: every stored and incoming vector has unit L2 norm."""

    def __init__(self, tau, delta):
        self.tau, self.delta = tau, delta

    @staticmethod
    def _check(X):
        n = np.linalg.norm(X, axis=1)
        if np.any(n < 1e-6):
            raise ValueError("zero/empty embedding at ingest")      # empty strings, failed upstream calls
        return (X / n[:, None]).astype(np.float32)                # normalize once, at the boundary

    def fit(self, X, y):
        X = self._check(X)
        self.labels = np.unique(y)
        self.C = l2n(np.stack([X[y == c].mean(0) for c in self.labels])).astype(np.float32)
        return self

    def scores(self, Q):
        return self._check(Q) @ self.C.T                           # cos == dot on the unit sphere

    def route(self, Q):
        s = self.scores(Q)
        top2 = np.sort(s, axis=1)[:, -2:]
        best = self.labels[s.argmax(1)]
        escalate = (top2[:, 1] < self.tau) | (top2[:, 1] - top2[:, 0] < self.delta)
        return best, escalate


# --- synthetic intent space. Meaning lives in a 12-D latent subspace (real embeddings have low intrinsic
# dimension); phrasing noise lives in that same subspace, so confusable intents genuinely overlap.
L = 12
P = np.linalg.qr(rng.standard_normal((D, L)))[0]                      # latent -> embedding basis
mu = rng.standard_normal(D) / np.sqrt(D)
dom = 3.0 * rng.standard_normal((DOMAINS, L))
nI = DOMAINS * PER_DOMAIN
cent = dom.repeat(PER_DOMAIN, 0) + rng.uniform(0.8, 1.3, (nI, 1)) * rng.standard_normal((nI, L))
spread = rng.uniform(0.8, 1.2, nI)


def embed(z):
    return z @ P.T + 0.35 * rng.standard_normal((len(z), D)) + 2.0 * mu


def utter(i, n):
    return embed(cent[i] + spread[i] * rng.standard_normal((n, L)))


Xtr = np.vstack([utter(i, TRAIN) for i in range(nI)])
ytr = np.arange(nI).repeat(TRAIN)
Xte = np.vstack([utter(i, TEST) for i in range(nI)])
yte = np.arange(nI).repeat(TEST)
ood_topics = 3.0 * rng.standard_normal((30, L))
Xood = embed(ood_topics[rng.integers(0, 30, 2000)] + 1.0 * rng.standard_normal((2000, L)))

print(f"{nI} intents x {TRAIN} exemplars; test {len(Xte)} in-domain + {len(Xood)} out-of-domain")
base = CentroidRouter(tau=-1, delta=0).fit(Xtr, ytr)
pred, _ = base.route(Xte)
print(f"no abstention: in-domain accuracy {np.mean(pred == yte):.3f}; every OOD query is force-routed to some intent")

# kNN baseline over all exemplars (k=5, similarity-weighted vote)
Xn, Tn = base._check(Xtr), base._check(Xte)
sims = Tn @ Xn.T
nn = np.argpartition(-sims, 5, axis=1)[:, :5]
votes = np.zeros((len(Tn), nI))
np.add.at(votes, (np.arange(len(Tn))[:, None].repeat(5, 1), ytr[nn]), np.take_along_axis(sims, nn, 1))
print(f"5-NN over {len(Xtr)} exemplars: in-domain accuracy {np.mean(votes.argmax(1) == yte):.3f}")

print("\n== abstain policy grid; traffic mix 85% in-domain / 15% OOD ==")
print(f"{'policy (tau, delta)':22s} {'coverage':>9} {'local acc':>9} {'OOD accepted':>12} {'escalated':>9}")
s_in, s_ood = base.scores(Xte), base.scores(Xood)
rows = []
for tau, delta in ((-1.0, 0.0), (0.55, 0.0), (0.60, 0.0), (0.60, 0.01), (0.65, 0.01), (0.65, 0.03), (0.70, 0.03)):
    r = CentroidRouter(tau, delta).fit(Xtr, ytr)
    p_in, e_in = r.route(Xte)
    _, e_ood = r.route(Xood)
    cov = 1 - e_in.mean()
    acc = np.mean(p_in[~e_in] == yte[~e_in]) if cov > 0 else float("nan")
    esc = 0.85 * e_in.mean() + 0.15 * e_ood.mean()
    name = "never abstain" if tau < 0 else f"tau={tau:.2f} delta={delta:.2f}"
    rows.append((name, cov, acc, 1 - e_ood.mean(), esc))
    print(f"{name:22s} {cov:>9.3f} {acc:>9.3f} {1 - e_ood.mean():>12.3f} {esc:>9.3f}")
print(f"score ranges: in-domain top-1 p5..p95 = {np.percentile(s_in.max(1), 5):.3f}..{np.percentile(s_in.max(1), 95):.3f}, "
      f"OOD top-1 p5..p95 = {np.percentile(s_ood.max(1), 5):.3f}..{np.percentile(s_ood.max(1), 95):.3f}")
assert rows[0][3] == 1.0 and rows[-1][3] < 0.1 and rows[-1][2] > rows[0][2] + 0.05

print("\n== cost per 1M requests (prices as of 2026-10; tokens are assumptions - measure yours) ==")
EMB_PER_MTOK = 0.02                 # OpenAI text-embedding-3-small (62,500 pages/$ at ~800 tokens/page)
LLM_IN, LLM_OUT = 0.10, 0.50        # Claude Haiku 5.5 $/MTok (prompts <= 100K tokens)
Q_TOK, PROMPT_TOK, OUT_TOK = 30, 600, 10
LLM_ACC = 0.97                      # assumption: the fallback LLM's accuracy on escalated traffic
emb = Q_TOK * EMB_PER_MTOK / 1e6
llm = (Q_TOK + PROMPT_TOK) * LLM_IN / 1e6 + OUT_TOK * LLM_OUT / 1e6
print(f"per call: embedding ${emb:.7f}, LLM classification ${llm:.6f}  (ratio {llm / emb:.0f}x)")
print(f"{'policy':30s} {'escalated':>9} {'$ / 1M req':>11} {'blended in-domain acc':>22}")
print(f"{'LLM for everything':30s} {1.0:>9.3f} {1e6 * llm:>11.2f} {LLM_ACC:>22.3f}")
for name, cov, acc, ood_acc, esc in rows:
    cost = 1e6 * (emb + esc * llm)
    blended = cov * acc + (1 - cov) * LLM_ACC
    print(f"{'router ' + name:30s} {esc:>9.3f} {cost:>11.2f} {blended:>22.3f}")

print("\n== latency of the routing kernel itself (one measured run, 1 BLAS thread) ==")
q1 = Xte[:1].astype(np.float32)
qb = Xte[:256].astype(np.float32)
for name, fn, n in (("1 query vs 12 centroids", lambda: base.route(q1), 1),
                    ("1 query vs 480 exemplars (kNN)", lambda: (base._check(q1) @ Xn.T).argmax(), 1),
                    ("256-query batch vs centroids", lambda: base.route(qb), 256)):
    fn()
    t0 = time.perf_counter()
    for _ in range(200):
        fn()
    dt = (time.perf_counter() - t0) / 200
    print(f"{name:32s} {dt * 1e6:8.1f} us/call  ({dt / n * 1e6:6.2f} us/query)")
print("\nALL ASSERTIONS PASSED")
```

Output (verified accuracy and costs; latency lines are one measured run):

```text
12 intents x 40 exemplars; test 3600 in-domain + 2000 out-of-domain
no abstention: in-domain accuracy 0.912; every OOD query is force-routed to some intent
5-NN over 480 exemplars: in-domain accuracy 0.811

== abstain policy grid; traffic mix 85% in-domain / 15% OOD ==
policy (tau, delta)     coverage local acc OOD accepted escalated
never abstain              1.000     0.912        1.000     0.000
tau=0.55 delta=0.00        1.000     0.912        0.085     0.137
tau=0.60 delta=0.00        0.998     0.912        0.057     0.143
tau=0.60 delta=0.01        0.877     0.956        0.054     0.246
tau=0.65 delta=0.01        0.872     0.956        0.025     0.255
tau=0.65 delta=0.03        0.611     0.990        0.023     0.477
tau=0.70 delta=0.03        0.594     0.991        0.005     0.494
score ranges: in-domain top-1 p5..p95 = 0.702..0.906, OOD top-1 p5..p95 = 0.019..0.610

== cost per 1M requests (prices as of 2026-10; tokens are assumptions - measure yours) ==
per call: embedding $0.0000006, LLM classification $0.000068  (ratio 113x)
policy                         escalated  $ / 1M req  blended in-domain acc
LLM for everything                 1.000       68.00                  0.970
router never abstain               0.000        0.60                  0.912
router tau=0.55 delta=0.00         0.137        9.95                  0.912
router tau=0.60 delta=0.00         0.143       10.34                  0.912
router tau=0.60 delta=0.01         0.246       17.32                  0.958
router tau=0.65 delta=0.01         0.255       17.93                  0.958
router tau=0.65 delta=0.03         0.477       33.05                  0.982
router tau=0.70 delta=0.03         0.494       34.20                  0.983

== latency of the routing kernel itself (one measured run, 1 BLAS thread) ==
1 query vs 12 centroids              19.0 us/call  ( 19.03 us/query)
1 query vs 480 exemplars (kNN)       21.5 us/call  ( 21.50 us/query)
256-query batch vs centroids        191.0 us/call  (  0.75 us/query)

ALL ASSERTIONS PASSED
```

How to read it:

- **Centroids beat 5-NN here (0.912 vs 0.811).** Individual exemplars carry phrasing noise. A centroid averages 40 of them, which cuts the noise variance by about 40×. That is Andrew Ng's variance lever (more data per class, or a lower-variance estimator) in its simplest form. kNN wins when an intent is multi-modal (several unrelated phrasings), which is the signal to split the intent or move to a learned head (Folder 02).
- **τ controls out-of-domain acceptance, δ controls in-domain confusion.** Raising τ from 0.55 to 0.70 cuts OOD acceptance from 8.5% to 0.5% while barely touching in-domain coverage (the in-domain top-1 p5 is 0.702). Raising δ from 0 to 0.03 lifts local accuracy from 0.912 to 0.990 by escalating confusable-sibling queries. Tune each on its own failure set.
- **Score ranges overlap** (OOD p95 = 0.610 vs in-domain p5 = 0.702). No single τ gives zero OOD acceptance and full coverage, so the abstain policy has to be tuned against costs, not "fixed".

### 3.5 Production schema: make the invariants impossible to violate

The listings prove the math. Production safety comes from making the contract explicit and enforced. The SQL below is **illustrative and was not executed here** (this harness has no pgvector); the syntax follows the pgvector 0.8.7 README.

```sql
-- One table per (model, version, dims): vectors from different models are different types.
CREATE TABLE chunk_emb_te3l_1536 (
    chunk_id   bigint PRIMARY KEY REFERENCES chunks(id),
    embedding  halfvec(1536) NOT NULL,       -- halfvec: 2 bytes/dim; HNSW supports halfvec up to 4,000 dims
    created_at timestamptz NOT NULL DEFAULT now()
);
-- Unit vectors -> inner product is the cheapest exact operator (pgvector README advice).
CREATE INDEX ON chunk_emb_te3l_1536 USING hnsw (embedding halfvec_ip_ops) WITH (m = 16, ef_construction = 64);

-- <#> is the NEGATIVE inner product: order ascending, negate for the similarity.
SELECT chunk_id, -(embedding <#> $1) AS cos
FROM chunk_emb_te3l_1536
ORDER BY embedding <#> $1
LIMIT 10;

-- Binary first stage (32x smaller index) + exact rerank on the original vectors.
CREATE INDEX ON chunk_emb_te3l_1536 USING hnsw ((binary_quantize(embedding)::bit(1536)) bit_hamming_ops);
SELECT chunk_id FROM (
    SELECT chunk_id, embedding FROM chunk_emb_te3l_1536
    ORDER BY binary_quantize(embedding)::bit(1536) <~> binary_quantize($1)
    LIMIT 100                                  -- rescoring depth: the lever measured in 3.3
) c
ORDER BY embedding <#> $1
LIMIT 10;
```

The application-side contract, in prose (the same fields belong in your index metadata):

| Field | Example | Enforced where |
|---|---|---|
| `model_id`, `model_version` | `text-embedding-3-large`, provider snapshot | Table or index name; refuse writes from other models |
| `dims` | 1536 (with `dimensions=1536`) | Column type `halfvec(1536)` |
| `normalized` | true | Ingest: `assert abs(norm − 1) < 1e-3`, reject zero vectors |
| `metric` | inner product on unit vectors | Operator class `halfvec_ip_ops` |
| `query_prefix` / `task_type` | `RETRIEVAL_QUERY` vs `RETRIEVAL_DOCUMENT` | The embedding client wrapper, never the call site |
| `thresholds` | cache τ = 0.903, router τ/δ | Stored with the index version and re-derived on any change |

---

## 4. The Andrew Ng Lens: Error Analysis for Retrieval Geometry

Andrew Ng's letter in *The Batch* (October 15, 2025) names the ability to drive a disciplined process for evals and error analysis as "the single biggest predictor of how rapidly a team makes progress building an AI agent." His recipe: build evals first (you can't analyze errors you haven't defined), look at real outputs, find where the system falls short, and focus there. He points out that this practice is long-established in supervised learning and still underused in generative AI. The geometry in this file is where that discipline pays off fastest, because every component has a measurable ceiling.

### 4.1 The error-analysis spreadsheet for a router or semantic cache

Pull 100–200 misrouted (or wrongly cached) production examples and tag each one. The columns:

| query | expected | predicted | top-1 score | margin | nearest exemplar | tag |
|---|---|---|---:|---:|---|---|

The tag vocabulary for geometric systems, and the fix each bucket points to:

| Tag | What you see | Fix |
|---|---|---|
| `boundary` | Small margin between sibling intents | Raise δ, merge the intents, or train a discriminative head (Folder 02) |
| `ood-accepted` | Low-ish top-1, query unlike any intent | Raise τ; add an explicit "other" class with exemplars |
| `label-noise` | The "expected" label is itself wrong or ambiguous | Fix labels first. Ng's data-centric rule: clean data beats a bigger model |
| `multi-intent` | Two requests in one message | Split before routing, or escalate |
| `negation` | "…but not X" routed to X | Escalate on negation cues; embeddings are weak at negation |
| `normalization/contract` | Scores out of [−1, 1], NaNs, model mismatch | A bug, not a tuning problem: enforce the contract in §3.5 |
| `stale-threshold` | Everything above τ after a model change | Re-derive τ (§1.7) |

Count the tags. The biggest bucket gets the next sprint. That's the whole method, and it reliably beats "try a bigger embedding model" because it tells you *which* of these problems you have.

### 4.2 Ceiling analysis for a retrieval pipeline

In his Machine Learning course, Ng's photo-OCR example has three components: text detection, character segmentation and recognition. He swaps in a *perfect* version of each component, one at a time, and measures the end-to-end gain. In the course numbers, perfect detection lifted accuracy from 72% to 89%, while perfect segmentation added only 1 point. Do the same for vector search:

| Replace with "perfect" | How, cheaply | What the gain tells you |
|---|---|---|
| ANN index → exact search | Brute-force float32 on a sample | Index approximation error. If small, stop tuning `ef_search` |
| Quantized vectors → float32 | Rescore with originals (§3.3) | Quantization loss. If small, keep the 32× compression |
| Truncated dims → full dims | Re-embed the sample at full dimension | Compression loss (01.2) |
| Embedding model → oracle relevance | Have humans or an LLM judge the true top-k | Representation ceiling: is a better or fine-tuned model worth it? |
| Retriever → perfect retriever | Feed gold passages to the LLM | Whether retrieval is the bottleneck at all, or generation is |

### 4.3 Bias and variance, translated

| Ng's concept | In an embedding router or cache | Lever |
|---|---|---|
| **Avoidable bias** (training error well above the achievable level) | The representation can't separate two intents: even training exemplars are confused | A better embedding model, a fine-tuned embedding (Folder 04), or a learned head (Folder 02) |
| **Variance** (training fine, held-out worse) | Centroids or thresholds estimated from too few or unrepresentative examples. 5-NN is worse than centroids here (0.811 vs 0.912) | More exemplars per intent, lower-variance estimators (centroids), threshold confidence intervals (Folder 06) |
| **Data mismatch** (dev ≠ production) | Thresholds tuned on synthetic or old traffic; the production query mix drifts | Tune on sampled production traffic; monitor score distributions (Folder 07) |

### 4.4 Evaluation-driven development for thresholds

1. **Write the eval before the threshold.** Build labelled pairs (cache) or labelled queries (router), including *hard negatives*: same topic, different intent. That's where the errors live, as §3.2 part D shows.
2. **Baseline:** choose τ (and δ) for a target precision. Record recall, coverage and the confidence interval.
3. **Error analysis:** run the spreadsheet on the false positives and false negatives.
4. **Change one thing** (a model, a threshold, normalization, centering) and re-measure the whole eval.
5. **Gate** model or dimension upgrades on re-derived thresholds, not on MTEB scores.

---

## 5. Failure Modes

| # | Symptom | Signature | Root cause | Fix | Prevention |
|---|---|---|---|---|---|
| F1 | Retrieval quality drops after a "harmless" refactor | Scores outside [−1, 1]; top-k dominated by long documents | One code path stopped normalizing (queries or docs) while the index uses inner product | Normalize at the boundary (ingest and query), assert ‖x‖ ≈ 1 | The contract in §3.5; a unit test with a deliberately long vector |
| F2 | Semantic cache hit rate jumps to ~100% after a model upgrade, answers go wrong | Score histogram shifted up and compressed (§1.7) | Threshold copied from the old model | Re-derive τ on labelled pairs for the new model | Store τ with the index version; block deploys without a re-derived τ |
| F3 | `NaN` similarities, random-looking top-k | `‖x‖ = 0` rows; empty strings or failed embedding calls stored as zeros | Missing ingest validation | Reject or quarantine ‖x‖ < 1e-6; re-embed | Ingest assertion + alert on zero-vector rate |
| F4 | `arccos` / angle features produce NaN on near-duplicates | cos = 1.0000004 in float32 | Rounding past the Cauchy–Schwarz bound (§1.1) | `np.clip(c, -1, 1)` | Lint rule: no `arccos` without a clip |
| F5 | Gemini (or any vendor) vectors at a reduced dimension rank oddly | Norms ≠ 1 at non-default dims | `gemini-embedding-001` normalizes only the 3072-d output; other dims must be normalized manually (`gemini-embedding-2` renormalizes) | Normalize after every truncation | Contract field `normalized`, checked at ingest |
| F6 | pgvector "similarity" values above 1 | `1 - (a <#> b)` in the query | `<#>` is the *negative* inner product | Similarity = `-(a <#> b)`; or cosine = `1 - (a <=> b)` | Wrap the operators in a SQL function with tests |
| F7 | Binary-quantized index recall collapses (≈0.37 recall@10 vs exact) | Hamming-only ranking, no rescoring | Binary codes are a candidate generator (§1.10) | Rescore the top 4–10× with float or int8 vectors | Ceiling analysis in CI: quantized vs float recall on a fixed sample |
| F8 | int8 index loses ~37 points of recall | Raw int8 dot with per-dimension affine ranges | The offset term adds a per-document bias (§1.10) | Symmetric (zero-point 0) quantization, or rescoring | Unit test: int8 ranking vs float ranking on a sample |
| F9 | Mixed results during a model migration; some queries return garbage | Two models' vectors in one index | Spaces of different models are not comparable (§1.1) | Dual-write to a new index; switch reads atomically | One index per (model, version, dims) |
| F10 | Router confidently routes off-topic requests | Top-1 below in-domain p5 but no abstention | No τ / δ band; every point lands in some Voronoi cell (§1.11) | Add τ (OOD) and δ (margin) escalation; add an "other" class | Track OOD acceptance on a labelled OOD set |
| F11 | Retrieval misses for queries, fine for document-to-document similarity | Asymmetric model used without its query/document prefixes or task type | Query embedded as a document (§1.8) | Use the model's `query:`/`passage:` prefixes or `task_type` | The embedding wrapper owns the prefix; call sites never format text |
| F12 | Triangle-inequality-based index or clustering returns wrong neighbors | "Cosine distance" passed as the metric | 1 − cos violates the triangle inequality (§1.5) | Use L2 on normalized vectors (the chord), same ordering | Ban `1 - cos` as a metric in shared libraries |

---

## 6. Bar-Raiser Q&A Chains

<details><summary><b>Q1 · "Cosine, dot product, or L2 for our vector index?"</b></summary>

**Initial Prompt.** You're standing up pgvector (or any vector DB) for a RAG service using OpenAI `text-embedding-3-large`. Pick the operator.

**L5 Answer.** "Cosine similarity. It's the standard for text embeddings."

**Why L5 Fails in Production.** It's not wrong, but it isn't a decision either. It doesn't say whether vectors are normalized, which operator is cheapest, or what happens when a code path forgets to normalize. On unit vectors, cosine, dot and L2 return identical rankings (§1.3), so the real question is *which invariant you enforce* and *which operator the hot path pays for*. Picking cosine also tends to leave the normalization implicit, so that one unnormalized path (F1) becomes invisible.

**L7 Principal Defense.** "The model returns unit vectors (OpenAI documents it). I'll *enforce* that at ingest and at query time, and then use **inner product**: it's the cheapest exact operator on unit vectors, which is the pgvector README's own advice. Rankings are provably identical to cosine and L2 (2 − 2cos is strictly decreasing). The index stores `halfvec` (2 bytes per dim, recall unaffected per §3.3), and the contract (model, dims, normalized, metric, thresholds) lives with the index. If we ever adopt a dot-trained model whose norms carry signal, that's a different index type: MIPS with its own validation (§1.4)."

**Bar-Raiser Follow-ups.**
- *"What if a query path forgets to normalize?"* With IP, scores scale with ‖q‖, so rankings within that query are unchanged (q's norm is a common factor), but thresholds break. Document norms are what corrupt rankings. Assert both, and alert on norm drift.
- *"Why not let the DB's cosine operator normalize for us?"* You can, at the cost of norm computations per comparison (or cached norms). The bigger risk is leaving the contract implicit: other consumers (caches, routers) then see unnormalized vectors.
- *"Does the operator choice change ANN recall?"* Exact results match. HNSW results can differ slightly between operator classes because graph construction differs, so measure recall@k against brute force for the configuration you ship.

</details>

<details><summary><b>Q2 · "We upgraded the embedding model and the semantic cache started serving wrong answers. Walk me through it."</b></summary>

**Initial Prompt.** Cache hit rate went from 22% to 97% overnight after switching models. Customer complaints followed.

**L5 Answer.** "The new model is worse at similarity. Roll back."

**Why L5 Fails in Production.** The new model may well be *better* at ranking. The bug is that a threshold is a property of a geometry, and the geometry changed. Rolling back hides the process failure: thresholds were global constants, not versioned artifacts, and the next upgrade will repeat the incident.

**L7 Principal Defense.** "A hit-rate jump plus wrong answers is the anisotropy signature: the new space has a stronger common direction, so every similarity moved up and the band between 'same intent' and 'unrelated' compressed (§1.7). Our reproduction: A's precision-0.95 threshold of 0.651 gives precision 0.253 at a 100% hit rate on B, and the re-derived threshold is 0.903. The fix is mechanical: (1) freeze cache writes; (2) re-derive τ on a labelled pair set with hard negatives (same topic, different intent); (3) version τ with the index; (4) add a deploy gate requiring a re-derived τ for any change to model, dims or normalization. Optionally mean-center the new model's vectors, which restores the spread but changes the metric, so it needs its own validation."

**Bar-Raiser Follow-ups.**
- *"How big a labelled pair set?"* Enough to pin precision at the operating point: ~300–500 positives near the threshold for a ±2–3-point interval (Folder 06 covers bootstrap CIs). Hard negatives matter more than volume.
- *"Can you detect this before customers do?"* Yes. Monitor the score distribution of cache lookups (p5/p50/p95) and the hit rate per deploy. A step change at deploy time is an alarm (Folder 07 drift detection).
- *"Isn't a cache hit on a slightly different question fine?"* Only if the answers are invariant to the difference. For transactional or user-specific prompts, scope the cache key (user, tenant, freshness) before similarity is even considered.

</details>

<details><summary><b>Q3 · "Prove that top-k under L2 equals top-k under cosine. When is it false?"</b></summary>

**Initial Prompt.** A whiteboard question. The interviewer wants the proof and the production caveats.

**L5 Answer.** "They're both distance measures, so they rank similarly."

**Why L5 Fails in Production.** "Similarly" is not a proof, and it hides exactly the cases that cause incidents: unnormalized vectors, quantized codes, ANN approximations and threshold conversion.

**L7 Principal Defense.** "For unit vectors, ‖q − d‖² = ‖q‖² + ‖d‖² − 2q·d = 2 − 2q·d. The map c ↦ √(2 − 2c) is strictly decreasing on [−1, 1], so ascending L2 is descending dot product, which is descending cosine because cosine equals dot on the sphere. The equality is exact in real arithmetic. It fails when: (1) vectors aren't unit (our log-normal test: top-10 overlap 0.112 dot vs cosine); (2) float ties at the k-boundary (we measured a minimum gap of 8.9e-6 with 200/200 agreement, so in practice this is rare); (3) ANN search, where different index builds give different approximations; (4) quantized storage, where codes aren't unit vectors; (5) thresholds, where ranking transfers but values don't (cos 0.8 ↔ L2 0.632)."

**Bar-Raiser Follow-ups.**
- *"And for inner product without normalization?"* Not a metric, and not equivalent. Use the MIPS reduction (one extra coordinate) if you must reuse an L2 index (§1.4).
- *"Why do engines compute L2 as ‖q‖² + ‖d‖² − 2q·d?"* It turns the scan into one matrix multiply (BLAS) plus cached norms, the same kernel as inner product.
- *"What's the angular distance of cos 0.8?"* arccos 0.8 = 36.9°.

</details>

<details><summary><b>Q4 · "Our retriever was trained with dot product and the norms carry signal, but our vector DB only supports L2/cosine. What do you do?"</b></summary>

**Initial Prompt.** A two-tower model (or a dot-trained dense retriever) where popular or authoritative documents have larger norms by design.

**L5 Answer.** "Normalize everything and use cosine."

**Why L5 Fails in Production.** Normalizing throws away the signal the model was trained to put in the norm, so offline metrics computed with dot product won't reproduce. It's a silent model change dressed up as an infrastructure choice.

**L7 Principal Defense.** "Two options. (a) Reduce MIPS to nearest neighbour exactly: append √(M² − ‖x‖²) to each document and 0 to each query, and then L2 order equals inner-product order. We reproduced 200/200 exact top-10 sets. The cost: the extra coordinate dominates (mean 7.81 vs 0.046 per coordinate), which degrades ANN graphs and quantizers (Neyshabur & Srebro), so I'd measure ANN recall, not assume it. (b) Prefer an engine with native inner product (FAISS `METRIC_INNER_PRODUCT`, pgvector `<#>`). Longer term, I'd ask whether the norm should be a separate feature. Popularity as an explicit re-ranking feature (Folder 04) is more controllable than popularity baked into geometry."

**Bar-Raiser Follow-ups.**
- *"Why does M have to be the global max norm?"* So that M² − ‖x‖² ≥ 0 for every document. New, longer documents require recomputing M and re-augmenting, which is an operational cost of the trick.
- *"Can you cap popularity bias?"* Clip norms at a percentile, or normalize and add a separate prior term, then A/B the two (Folder 06).

</details>

<details><summary><b>Q5 · "Cut our vector memory 32× without losing recall."</b></summary>

**Initial Prompt.** 10M chunks × 1024 dims in float32 (41 GB of vectors) no longer fit the RAM budget.

**L5 Answer.** "Use binary quantization. It's 32× smaller."

**Why L5 Fails in Production.** Binary *alone* is a ranking disaster on strict metrics: Hamming-only recall@10 was 0.365 in our test. The claim "32× smaller with no loss" only holds with a rescoring stage, and that stage has its own memory and IO cost, which the L5 answer leaves out.

**L7 Principal Defense.** "Tiered representation. A binary HNSW (1.28 GB for 10M × 1024) generates the top 4–10× candidates. Rescoring uses int8 or fp16 vectors, kept on SSD or in a cheaper tier, fetched only for the candidates. Measured: ×10 rescoring against float originals gives recall@10 0.995. HF's study on real retrieval tasks reports 96.45% of float performance with binary + rescoring, and a ~25× faster search with optimized popcount. I'd centre vectors before binarizing if the space is anisotropic (bits go from 20.1% nearly-constant to balanced), but measure that gain. Then I'd run a ceiling analysis (exact float vs quantized) on a fixed eval sample in CI, so quantization loss is a tracked number."

**Bar-Raiser Follow-ups.**
- *"What's the rescoring IO cost?"* ×10 candidates × k = 10 → 100 vectors per query. At fp16 × 1024 dims that's 200 KB per query, which is fine from local NVMe and painful over a network. Size the tier accordingly.
- *"Combine with Matryoshka?"* Yes: binary on a 256-d MRL prefix for the first stage, full-dim rescoring (01.2 funnel retrieval).
- *"Why not product quantization?"* PQ (Folder 04) gives finer trade-offs (e.g., 8–64 bytes per vector) at the cost of codebook training and drift. Binary is training-free and robust. Pick by measured recall per byte.

</details>

<details><summary><b>Q6 · "All our cosine similarities are between 0.7 and 0.9. Is the model broken?"</b></summary>

**Initial Prompt.** A team reports that the similarity scores are "useless" because everything looks similar.

**L5 Answer.** "The model isn't discriminative enough. Switch models."

**Why L5 Fails in Production.** A compressed score range is anisotropy, not necessarily bad ranking. Ranking can be nearly unchanged (our B space has the same pair ordering). Switching models costs a re-embed, changes every threshold, and may not fix anything.

**L7 Principal Defense.** "First, separate ranking quality from score calibration. Measure recall@k or routing accuracy on labelled data: if ranking is fine, the model isn't broken. Then explain the range: random unit vectors in 768+ dims have cos ≈ 0 ± 0.036 (1/√d), so unrelated pairs at 0.7 mean a strong common direction (Ethayarajh's narrow cone). Our reproduction: random pairs at 0.718 and same-intent pairs at 0.936, a usable band of only 0.218. Mean-centering restores a 0.781 band. Fixes: centre and renormalize (version the mean vector with the index and re-validate recall), or simply calibrate thresholds within the compressed band. The real bug would be any *absolute* threshold that was chosen by intuition."

**Bar-Raiser Follow-ups.**
- *"Does centering change retrieval results?"* Cosines in the centred space are a different metric, so yes, slightly. 01.2 shows that a k + 1 representation keeps the original geometry when you need both.
- *"Why do models end up anisotropic?"* Training objectives don't penalize a shared offset, and token-frequency effects push representations into a cone. Contrastive training with in-batch negatives reduces it (Folder 04).

</details>

<details><summary><b>Q7 · "Can we mix embeddings from the old and new model in one index during the migration?"</b></summary>

**Initial Prompt.** Re-embedding 50M documents takes a week. The PM asks to write new documents with the new model and keep the old ones as they are.

**L5 Answer.** "Yes, if the dimensions match."

**Why L5 Fails in Production.** Matching dimensions mean nothing: each model's space is defined only up to its own rotation and warp (§1.1). Old-model and new-model vectors aren't comparable, so a new-model query against old-model documents returns noise, silently, with plausible-looking scores.

**L7 Principal Defense.** "No mixing. Dual-write: new documents get both embeddings, and a backfill job re-embeds old documents into a new index. Reads stay on the old index until the backfill completes *and* the eval suite (recall@k, thresholds re-derived) passes on the new one. Then switch atomically via an alias, keeping the old index for rollback. During the window, the new-model index is incomplete, so it isn't queried. If the timeline is unacceptable, an orthogonal-Procrustes alignment between the spaces (fit on paired embeddings) can bridge them temporarily, but that's an approximation with its own eval gate, not a default."

**Bar-Raiser Follow-ups.**
- *"What does Procrustes buy you?"* The best rotation R minimizing ‖XR − Y‖, solved by one SVD of XᵀY (01.2 §3.1). It aligns only the linear part: in our listing, recall@10 of new-model queries on the old index goes from 0.000 (no bridge) to 0.936 when the spaces differ by a rotation, but only to 0.859 under a nonlinear warp. Measure retrieval across the bridge before using it.
- *"Cost of the backfill?"* Tokens × price: 50M chunks × 300 tokens × $0.13/MTok (`text-embedding-3-large`, 9,615 pages per dollar at 800 tokens per page) ≈ $1,950. Usually cheaper than an incident.

</details>

<details><summary><b>Q8 · "Is cosine distance a metric, and why would that matter?"</b></summary>

**Initial Prompt.** A clustering library or a metric-tree index accepts `metric="cosine"`.

**L5 Answer.** "Yes, it's a distance."

**Why L5 Fails in Production.** 1 − cos violates the triangle inequality (a = 0°, b = 45°, c = 90°: 1 > 0.586). Algorithms that prune with the triangle inequality can then discard true neighbors. We counted 937 violations in 30,000 random 8-D triples.

**L7 Principal Defense.** "1 − cos is a dissimilarity, not a metric. Angular distance θ and the chord √(2 − 2cos), which is L2 on normalized vectors, are metrics with the same ordering. So for anything that relies on metric properties (VP-trees, ball trees, triangle-pruned k-means, some density-based clustering), I normalize and use L2. k-means specifically minimizes squared L2, so on normalized data it's spherical k-means up to the centroid renormalization step."

**Bar-Raiser Follow-ups.**
- *"Does HNSW need a metric?"* HNSW's greedy search doesn't need the triangle inequality for correctness, but its quality guarantees and heuristics assume metric-like behavior. With normalized vectors it's moot, because IP, cosine and L2 coincide.

</details>

<details><summary><b>Q9 · "Design an intent router: embedding + nearest centroid, or an LLM classifier?"</b></summary>

**Initial Prompt.** 12 support intents, 1M requests per day, strict latency, and some out-of-scope traffic.

**L5 Answer.** "LLM classification. It's more accurate and handles everything."

**Why L5 Fails in Production.** It pays a full LLM call per request (113× to 4,533× an embedding call, depending on the model tier), adds generation latency, and gives you no calibrated confidence to threshold. "More accurate" is untested: our cascade *beats* the all-LLM baseline on blended accuracy.

**L7 Principal Defense.** "A cascade. Embed, then score against normalized centroids (19 µs kernel), and answer locally when top-1 ≥ τ and margin ≥ δ, escalating the rest to the LLM. τ catches out-of-domain traffic and δ catches confusable siblings. In our measurement, τ = 0.65 and δ = 0.03 answered 61% of in-domain traffic locally at 0.990 accuracy, accepted 2.3% of OOD, and blended to 0.982 at $33 per 1M requests vs 0.970 at $68 for all-LLM (with the LLM's accuracy as a stated assumption). The centroid router is a linear classifier (§1.11), so the upgrade path is a trained logistic-regression head on the same embeddings (Folder 02), with LLM escalations logged as labels for the next training run."

**Bar-Raiser Follow-ups.**
- *"How do you set τ and δ?"* On labelled in-domain plus labelled OOD sets, minimizing expected cost: escalation price × escalation rate + error cost × local errors (01.3 derives the cost-optimal threshold).
- *"What if intents drift?"* Monitor the top-1 score distribution and the escalation rate per intent. Recompute centroids from recent labelled traffic on a schedule (Folder 07).
- *"Why not kNN?"* Here it's worse (0.811 vs 0.912) because single exemplars are noisy. kNN only helps for multi-modal intents, and those are better split.

</details>

<details><summary><b>Q10 · "How many dimensions do we actually need?"</b></summary>

**Initial Prompt.** The model emits 3072 dims. Storage wants 256.

**L5 Answer.** "Use PCA to 256. Or just keep the first 256 coordinates."

**Why L5 Fails in Production.** Keeping the first 256 coordinates of a non-Matryoshka model is just a random projection (rotation invariance, §1.1). PCA works on structured data but must be fitted, versioned and re-fitted on drift. Neither answer starts from a measurement.

**L7 Principal Defense.** "JL gives the data-oblivious answer: ~13.8k dims for 10% distortion at 10M points, which is useless here. The real answer is the intrinsic dimension of *our* data, measured as recall@k against full-dim exact search as dims shrink. If the model is Matryoshka-trained (OpenAI `text-embedding-3` via `dimensions`, Gemini `output_dimensionality`), truncate through the API and renormalize. Otherwise PCA fitted on a representative sample, centred, with the mean handled correctly (01.2 measures 0.995 recall at 64 dims on our structured corpus). In both cases I'd pick the smallest dims that hold the task metric within an agreed tolerance, and keep full-dim vectors in a cold tier for rescoring."

**Bar-Raiser Follow-ups.**
- *"Why is JL so pessimistic?"* It's worst-case over all point sets and uses a random map that ignores structure. Learned or data-fitted maps exploit low intrinsic dimension.
- *"Cheapest experiment?"* 10k sampled documents plus 500 labelled queries: compute recall@10 at 64/128/256/512 dims. An afternoon of work that saves months of storage spend.

</details>

<details><summary><b>Q11 · "Our int8 index lost 37 points of recall. The blog said int8 keeps ~97%. Why?"</b></summary>

**Initial Prompt.** A team quantized with per-dimension min/max ranges and computes raw int8 dot products.

**L5 Answer.** "Int8 just doesn't work for this model. Go back to float."

**Why L5 Fails in Production.** It gives up a 4× memory saving because of an implementation detail. The loss comes from the quantizer's offset, not from int8's precision.

**L7 Principal Defense.** "Affine int8 codes are x/s + b per dimension, so the integer dot product expands into a re-weighted dot plus a term linear in the document's codes. That term is a per-document bias that ranks by coordinate size, independent of the query (§1.10). We reproduce 0.629 recall@10 with that recipe. Fixes, in order of preference: symmetric quantization with a global scale (zero-point 0), which gives 0.980 with no rescoring; or keep affine codes and rescore the shortlist with the float32 query against dequantized documents, which gives 0.958. The blog's ~97% is a task metric (NDCG) on real data, and it includes design choices (calibration set, rescoring) that matter."

**Bar-Raiser Follow-ups.**
- *"Why not per-dimension symmetric scales?"* Then the dot product is re-weighted by 1/sⱼ² per dimension, a mild distortion. A global scale keeps proportionality, and per-dimension scales trade proportionality for resolution. Measure both.
- *"Where do engines handle this for you?"* Most production scalar quantizers either use symmetric codes or correct the offset algebraically (store per-vector sums). Read the engine's docs, then verify with a ranking test.

</details>

---

## 7. Invariants Checklist

- [ ] Every stored vector carries (model id, version, dims, dtype, normalized, metric), and one index holds one model.
- [ ] Vectors are L2-normalized at ingest *and* at query time. ‖x‖ ≈ 1 is asserted, and zero vectors are rejected.
- [ ] The index operator matches the contract: inner product on unit vectors (or L2, which is equivalent). Cosine distance is never used as a metric for triangle-inequality algorithms.
- [ ] Every similarity threshold (cache τ, router τ/δ, dedup radius) is versioned with the index and re-derived from labelled pairs on any change.
- [ ] Every truncation (Matryoshka prefix, manual slicing) is followed by renormalization. Vendor behavior per dimension is documented (Gemini 001 vs 2).
- [ ] Every `arccos`, `sqrt(1 − c²)` and `log(1 − c)` is preceded by `clip(c, −1, 1)`.
- [ ] Every quantized index has a measured ceiling (quantized vs float recall on a fixed sample) and a rescoring stage sized from that measurement.
- [ ] Int8 uses symmetric codes or offset-corrected scoring. Raw affine dot products are never used for ranking.
- [ ] Every router has τ (OOD) and δ (margin) escalation and a labelled OOD set, with OOD acceptance tracked.
- [ ] Asymmetric models get their query/document prefix or task type from the embedding wrapper, not from call sites.
- [ ] Model migrations dual-write to a new index and switch reads atomically after the eval gate passes. Spaces are never mixed.
- [ ] Error analysis runs on tagged failures before any "bigger model" decision.

---

## 8. References

1. OpenAI, *Embeddings guide*: normalization to length 1, the `dimensions` parameter, manual truncation needs renormalization, pages per dollar, MTEB table. https://developers.openai.com/api/docs/guides/embeddings
2. Google, *Gemini API embeddings*: MRL training, `output_dimensionality` (128–3072, recommended 768/1536/3072), manual normalization for non-3072 dims on `gemini-embedding-001`, automatic renormalization on `gemini-embedding-2`, task types. https://ai.google.dev/gemini-api/docs/embeddings
3. pgvector README (v0.8.7): operators `<->` `<#>` `<=>` `<~>`, inner-product advice for normalized vectors, `halfvec`/`bit` HNSW limits, `binary_quantize` with re-ranking, subvector indexing. https://github.com/pgvector/pgvector
4. FAISS wiki, *MetricType and distances*: inner product, cosine via normalization. https://github.com/facebookresearch/faiss/wiki/MetricType-and-distances
5. Shakir, Aarsen, Lee (Hugging Face), *Binary and Scalar Embedding Quantization for Significantly Faster & Cheaper Retrieval* (2024): 92.53% → 96.45% binary with rescoring, int8 ~97% → ~99.3%, 24.76× speedup, 953.67 GB → 29.80 GB. https://huggingface.co/blog/embedding-quantization
6. M. Charikar, *Similarity Estimation Techniques from Rounding Algorithms*, STOC 2002 (random-hyperplane hashing, P = θ/π). DOI 10.1145/509907.509965.
7. K. Ethayarajh, *How Contextual are Contextualized Word Representations?*, EMNLP 2019 (anisotropy). https://arxiv.org/abs/1909.00512
8. H. Steck, C. Ekanadham, N. Kallus, *Is Cosine-Similarity of Embeddings Really About Similarity?*, 2024. https://arxiv.org/abs/2403.05440
9. K. Beyer, J. Goldstein, R. Ramakrishnan, U. Shaft, *When Is "Nearest Neighbor" Meaningful?*, ICDT 1999. DOI 10.1007/3-540-49257-7_15.
10. S. Dasgupta, A. Gupta, *An Elementary Proof of a Theorem of Johnson and Lindenstrauss*, Random Structures & Algorithms 22(1), 2003. DOI 10.1002/rsa.10073.
11. Y. Bachrach et al., *Speeding Up the Xbox Recommender System Using a Euclidean Transformation for Inner-Product Spaces*, RecSys 2014. DOI 10.1145/2645710.2645741.
12. Vespa, *Announcing maximum inner product search* (the extra-dimension reduction explained). https://blog.vespa.ai/announcing-maximum-inner-product-search/
13. B. Neyshabur, N. Srebro, *On Symmetric and Asymmetric LSHs for Inner Product Search*, ICML 2015. https://arxiv.org/abs/1410.5410
14. Y. Malkov, D. Yashunin, *Efficient and Robust Approximate Nearest Neighbor Search Using HNSW Graphs*. https://arxiv.org/abs/1603.09320
15. A. Ng, *Improve Agentic Performance with Evals and Error Analysis, Part 1*, The Batch, 2025-10-15. https://www.deeplearning.ai/the-batch/improve-agentic-performance-with-evals-and-error-analysis-part-1/
16. Anthropic, *Claude pricing* (Haiku 5.5 / Sonnet 5.5 / Opus 5.5 rates used in §2; cached 2026-10-06). https://platform.claude.com/docs/en/about-claude/pricing
