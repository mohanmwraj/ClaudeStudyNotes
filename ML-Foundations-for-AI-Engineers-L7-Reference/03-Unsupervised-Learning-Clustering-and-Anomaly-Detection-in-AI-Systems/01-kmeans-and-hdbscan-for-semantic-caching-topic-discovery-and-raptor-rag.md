# 03.1 · k-means & HDBSCAN for Semantic Caching, Topic Discovery & RAPTOR RAG

> **Folder 03 · Unsupervised Learning, Clustering & Anomaly Detection in AI Systems**
> **Measured on:** scikit-learn 1.9.1 (`KMeans`, `HDBSCAN`), NumPy 2.5.4, CPython 3.14.5, Intel i5-11260H (one BLAS thread), Windows 11.
> **Real data:** CLINC150 utterances embedded with `all-MiniLM-L6-v2` (Folder 02.1's cached pipeline).
> **Design sources:** Lloyd (1982), Arthur & Vassilvitskii (k-means++, 2007), Campello et al. (HDBSCAN, 2013), Grootendorst (BERTopic, 2022), Sarthi et al. (RAPTOR, ICLR 2024), Jégou et al. (IVF/PQ, 2011). Full list in §8.

---

## 0. Orientation: Clustering Is How You Learn What's in Traffic Nobody Labelled

Andrew Ng's framing for unsupervised learning is "find structure in data without labels". In an AI system, that structure answers concrete questions:

- **What are users asking that we don't handle?** Cluster the escalated traffic and look at the biggest clusters first. In §3.2, HDBSCAN surfaces **22 of 30** never-seen intents as clean clusters.
- **Have we answered this before?** A semantic cache is nearest-neighbour search with a threshold, and at scale it's partitioned by k-means (IVF).
- **How do we retrieve over a corpus at several levels of abstraction?** RAPTOR builds a tree by recursively clustering chunks and summarizing each cluster.
- **Which failures belong together?** Clustering the error set gives you the buckets for Ng's error-analysis spreadsheet.

### The backend-engineer bridge

| You already know | Clustering equivalent |
|---|---|
| Sharding keys by hash range | **IVF**: shard vectors by nearest k-means centroid, query only the nearest shards (`nprobe`) |
| Log clustering to triage incidents (grouping similar stack traces) | **Topic discovery on escalated queries** |
| A read-through cache keyed on the exact request | **Semantic cache** keyed on meaning, which adds a correctness risk exact caches don't have |
| A rollup table (daily → monthly aggregates) | **RAPTOR tree** of cluster summaries over leaf chunks |
| "Unknown" bucket in a classifier of log lines | **HDBSCAN noise label (−1)**: density clustering may refuse to cluster a point |

### Tier map

| Subtopic | Tier |
|---|---|
| 1.1 The k-means objective and Lloyd's algorithm | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.2 k-means++ initialization | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.3 Spherical k-means on unit vectors | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.4 Evaluating clusters and choosing k | `[GOOD-TO-KNOW: Architectural Literacy]` |
| 1.5 HDBSCAN: density, noise and stability | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.6 Reduce dimensions before density clustering | `[GOOD-TO-KNOW: Architectural Literacy]` |
| 1.7 Naming clusters with class-based TF-IDF | `[GOOD-TO-KNOW: Architectural Literacy]` |
| 1.8 Semantic caching: the threshold trade-off and the correctness trap | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.9 IVF partitioning: nprobe vs recall | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.10 RAPTOR: recursive cluster-summarize trees for RAG | `[GOOD-TO-KNOW: Architectural Literacy]` |
| 1.11 k-means hardness and consistency theory | `[SKIP: Academic/Research Only]` |

---

## 1. First-Principles Math & Geometric Intuition

### 1.1 The k-means objective and Lloyd's algorithm `[MUST-KNOW: Core AI Engineer Edge]`

k-means chooses k centroids to minimize the **inertia**, the within-cluster sum of squared distances:

```text
J(C, a) = Σᵢ ‖xᵢ − c_{a(i)}‖²
Lloyd's algorithm (repeat until assignments stop changing):
  assign:  a(i) ← argmin_j ‖xᵢ − c_j‖²          (Voronoi cells of the current centroids)
  update:  c_j ← mean of the points assigned to j
```

**Why it converges (monotonically).** The assign step can't increase J, because each point moves to a closer centroid. The update step can't either: for a fixed set of points, the mean is the unique minimizer of Σ‖x − c‖², since the gradient 2Σ(c − x) vanishes at c = mean. There are finitely many assignments, J never increases, so the algorithm stops at a local minimum. The listing checks "monotone non-increasing: True" on 15,000 real embeddings.

It's a *local* minimum, which is why initialization matters. Lloyd's algorithm is coordinate descent on a non-convex objective.

### 1.2 k-means++ initialization `[MUST-KNOW: Core AI Engineer Edge]`

Arthur & Vassilvitskii (2007): pick the first centroid uniformly, then each next one with probability proportional to D(x)², the squared distance to the nearest centroid chosen so far. This spreads the seeds out, and they prove the expected inertia is within O(log k) of optimal *before Lloyd even runs*. Measured at k = 150 on CLINC:

```text
random rows  inertia   7302.73 after  22 iterations
k-means++    inertia   7283.27 after  27 iterations
sklearn KMeans (k-means++, n_init=1): inertia   7138.81 after 23 iterations
```

scikit-learn's version is better still, because it uses *greedy* k-means++: at each step it samples several candidates (2 + ⌊ln k⌋ local trials) and keeps the one that reduces inertia most. On real embeddings the gap between initializations is small (2%), since the data has strong cluster structure. On data with uneven cluster sizes, random initialization can do much worse. Always use k-means++, and set `n_init` > 1 when cheap.

### 1.3 Spherical k-means on unit vectors `[MUST-KNOW: Core AI Engineer Edge]`

For unit vectors, ‖x − c‖² = ‖x‖² + ‖c‖² − 2x·c = 1 + ‖c‖² − 2x·c. This equals 2 − 2cos only if the *centroid* also has unit norm, and a mean of unit vectors is shorter than 1:

```text
centroid norms: min 0.419, median 0.737, max 0.915  (a tight cluster -> norm near 1)
```

The norm of a mean is a tightness measure: a cluster of near-duplicates has a centroid near the sphere, a diffuse cluster has a centroid near the origin. **Spherical k-means** renormalizes centroids after each update and assigns by maximum cosine, which is the right objective when you serve by cosine (01.1). On CLINC it agrees with plain k-means at ARI 0.931. In production the difference is small but real: use spherical k-means when the downstream consumer compares by cosine (IVF on unit vectors, semantic caches), and renormalize stored centroids either way.

### 1.4 Evaluating clusters and choosing k `[GOOD-TO-KNOW: Architectural Literacy]`

With labels (for offline validation), there are three standard measures:

- **ARI** (adjusted Rand index): agreement on pairs, corrected for chance. 0 = random, 1 = identical.
- **NMI** (normalized mutual information).
- **Purity**: the fraction of points in their cluster's majority class. It rises trivially with k.

```text
   k    ARI    NMI  purity
  50  0.349  0.787   0.326
 150  0.715  0.901   0.797
 300  0.632  0.881   0.879
```

k-means with k = 150 recovers CLINC's 150 intents at ARI 0.715, which is strong evidence that the embedding space carries the intent structure *without* supervision. Purity keeps rising at k = 300 because smaller clusters are purer, which is why purity alone can't choose k.

Without labels, the **silhouette** (per point: (b − a)/max(a, b), with a = mean distance to its own cluster and b = to the nearest other cluster) peaks at **k = 150** here (0.1391, vs 0.1384 at 200), while inertia decreases forever (the "elbow" is a judgment call). Absolute silhouette values on text embeddings are low (~0.1), because clusters touch in high dimensions. Compare silhouettes across k, and don't treat a low value as failure.

### 1.5 HDBSCAN: density, noise and stability `[MUST-KNOW: Core AI Engineer Edge]`

k-means assigns *every* point to *some* cluster, and assumes compact, similar-sized clusters. Real escalated traffic is a few dense topics plus a lot of one-off chatter. HDBSCAN (Campello et al., 2013) models it directly:

```text
1. core distance:  core_k(x) = distance to the k-th nearest neighbour (k = min_samples)
2. mutual reachability:  d_mr(a, b) = max(core_k(a), core_k(b), d(a, b))
      → points in sparse regions get pushed away from everything
3. minimum spanning tree over d_mr → single-linkage hierarchy
4. condense the hierarchy: drop splits that shed fewer than min_cluster_size points
5. select the clusters that persist longest across density levels ("stability");
   points not in a selected cluster are NOISE (label −1)
```

```text
   density
     ▲     ██                         ██
     │    ████          ██           ████      ← stable dense regions → clusters
     │   ██████        ████         ██████
     │ ·  ·  ·  ·  ·  ·  ·  ·  ·  ·  ·  ·  ·   ← sparse chatter → noise (−1)
     └──────────────────────────────────────►  embedding space (1-D sketch)
```

On the "unhandled traffic" scenario (900 utterances from 30 intents the router never saw, plus 1,000 generic out-of-scope queries):

```text
HDBSCAN on PCA-50: 31 clusters, noise 50.5% (noise among generic OOS 86.4%, among unseen intents 10.7%);
                   ARI on clustered intent points 0.849; 0.3 s
k-means with k=30 (told the right answer) assigns 100% of points incl. all 1000 generic OOS; ARI on intent points 0.712
```

HDBSCAN did what triage needs. It labelled 86% of the generic chatter as noise, kept 89% of the real new-intent traffic in clusters, and didn't need to be told k. k-means, even *given* the true k, forced all the chatter into clusters and recovered the intents worse (ARI 0.712 vs 0.849).

### 1.6 Reduce dimensions before density clustering `[GOOD-TO-KNOW: Architectural Literacy]`

Density estimates degrade in high dimensions (01.1 §1.6: distances concentrate). Raw 384-d vs PCA-50 on the same data:

```text
HDBSCAN on raw 384-d: 27 clusters, noise 57.4% ...; ARI on clustered intent points 0.797; 2.9 s
HDBSCAN on PCA-50:    31 clusters, noise 50.5% ...; ARI on clustered intent points 0.849; 0.3 s
```

PCA-50 is 10× faster *and* better. BERTopic's default pipeline reduces with UMAP (to ~5 dims) before HDBSCAN for the same reason. UMAP preserves local neighbourhoods better than PCA (03.2) but is slower and stochastic. PCA is deterministic and invertible, a sensible first choice.

### 1.7 Naming clusters with class-based TF-IDF `[GOOD-TO-KNOW: Architectural Literacy]`

A cluster id isn't actionable. Concatenate each cluster's texts into one "document", then score words by term frequency within the cluster × inverse frequency across clusters. That's BERTopic's c-TF-IDF (Grootendorst, 2022), a few lines in the listing:

```text
cluster size purity majority intent            top c-TF-IDF words
      0   30   1.00 whisper_mode               whisper mode change off
      1   20   1.00 jump_start                 jump car start starting
      5   31   0.97 w2                         form where tax taxes
      6   17   1.00 (generic OOS)              job look career funding
      7   12   0.83 jump_start                 battery dead car died
```

The labels are readable enough for a product manager to say "yes, we should support W-2 questions". Note cluster 7: `jump_start` split into two clusters ("jump start the car" vs "battery dead"), which is useful information about how users phrase one need. Generic-OOS clusters (cluster 6: job and career questions) are candidate intents too. An LLM can then write a polished name and description *per cluster* from a handful of representative members: 31 LLM calls instead of 1,900.

### 1.8 Semantic caching: the threshold trade-off and the correctness trap `[MUST-KNOW: Core AI Engineer Edge]`

A semantic cache returns a stored answer when a new prompt's embedding is within τ of a cached prompt's. With 15,000 cached CLINC prompts and the test set as traffic:

```text
  tau hit rate  hit precision (same intent)  OOS false-hit rate
 0.70    0.644                        0.928               0.032
 0.80    0.489                        0.961               0.005
 0.90    0.258                        0.984               0.002
 0.95    0.110                        0.985               0.000
```

The trade-off is steep: dropping τ from 0.90 to 0.80 almost doubles the hit rate while the wrong-intent rate goes from 1.6% to 3.9%. That's the measured version of 01.1 §1.7's rule that τ belongs to a model and a task.

**The trap that "hit precision" hides: same intent is not same answer.**

```text
11 of 1417 same-intent hits change a number (after 'four' -> '4' normalization). Examples:
  0.932  query 'can i put in a pto request for september 1st to september 8th'  ->  cached 'can you put in a pto request for march 7th to the 9th'
  0.934  query 'can i put in a pto request for january 4th to january 9th'  ->  cached 'would it be possible to make a pto request for january 15th and 16th'
```

At cosine 0.93, the cache would book the wrong dates. Embeddings capture *what kind* of request it is far better than *which parameters* it carries. (The first version of this listing flagged "4 minute timer" vs "four minute timer" as different, which is a false alarm. Normalizing number words fixed the check. Even detecting the trap needs care.) Production semantic caches therefore:

1. **Scope the key**: tenant, user (for personalized answers), locale, and the model/prompt version.
2. **Extract and compare parameters** (numbers, dates, entities, product IDs) exactly, and only serve a hit when they match. Otherwise, use the cache only for parameter-free requests (FAQs, policy questions).
3. **Apply freshness**: a TTL per answer type. Prices and stock levels expire fast.
4. **Re-derive τ per model**, and audit a sample of hits continuously.

### 1.9 IVF partitioning: nprobe vs recall `[MUST-KNOW: Core AI Engineer Edge]`

At millions of keys, exhaustive search is too slow. An **inverted file (IVF)** index runs k-means over the keys (nlist cells), stores each cell's vectors contiguously, and at query time scans only the `nprobe` cells whose centroids are nearest to the query (Jégou et al., 2011; FAISS `IndexIVFFlat`). Measured on 15,000 keys, nlist = 64:

```text
nprobe keys scanned recall of exact top-1  us/query
     1          284                 0.895      24.0
     2          571                 0.961      38.6
     4         1123                 0.980      82.4
    16         4210                 0.999     367.4
exhaustive        15000                 1.000    1361.4
```

- **Recall is a function of nprobe**: one cell misses the true nearest neighbour 10.5% of the time, because queries near a cell boundary have their neighbour in the adjacent cell. 16 cells (a quarter of the index) reach 0.999.
- **Cost scales with keys scanned**: 3.7× faster than exhaustive at 0.999 recall, and 57× faster at 0.895.
- **k-means cells are unequal** (61 to 559 keys here), so per-query latency varies with which cells get probed. That's a tail-latency concern, and why some systems use balanced k-means.
- The first version of this listing gathered `K[ids]` for every query, and the copy dominated the timing (nprobe = 2 looked slower than exhaustive). Storing each cell contiguously is not an optimization detail. It is the IVF data structure.

### 1.10 RAPTOR: recursive cluster-summarize trees for RAG `[GOOD-TO-KNOW: Architectural Literacy]`

Flat chunk retrieval struggles with questions that need the *gist* of many chunks ("what are the main themes of this report?"). RAPTOR (Sarthi et al., ICLR 2024) builds a tree:

```text
level 0: chunks ─► embed ─► cluster (the paper: UMAP + Gaussian mixture, soft assignment)
level 1: one LLM-written summary per cluster ─► embed ─► cluster again
...      until a few root nodes remain
retrieval ("collapsed tree"): search ALL nodes of all levels together and take the top-k by similarity,
         so a query can match a leaf (detail) or a summary (theme)
```

The listing builds the structure with k-means over 2,000 utterances. Each node's "summary" is a stand-in, the member nearest its centroid, because there's no LLM in this harness:

```text
level 0:  2000 nodes  (leaves = original chunks)
level 1:   200 nodes
level 2:    20 nodes
level 3:     2 nodes
collapsed-tree search scans 2,222 vectors vs 2,000 leaves (+11.1%); top hit level for specific queries: L0=0.67, L1=0.24, L2=0.09, L3=0.00
```

The cost of the collapsed tree is small at query time (+11% vectors). The real cost is **build time**: one LLM summarization call per internal node (222 here), redone whenever the corpus changes enough to alter the clusters. Even *specific* queries hit an internal node a third of the time (L1 + L2 = 0.33), because a centroid can be closer to a query than any single member. With real LLM summaries, those hits return synthesized context instead of one chunk. Whether that helps your questions is an eval question (Folder 06), not a default.

### 1.11 k-means hardness and consistency theory `[SKIP: Academic/Research Only]`

Exact k-means is NP-hard even for k = 2 in general dimension. Lloyd's algorithm can take exponentially many iterations in contrived cases. Consistency results describe when cluster recovery is possible. Production needs §1.1–1.2: local optima, good initialization, multiple restarts.

---

## 2. Where It Beats an LLM in Production

| Need | Clustering approach | LLM-only approach |
|---|---|---|
| Discover new intents in 10⁵ escalated queries | Embed (already done for routing) → PCA → HDBSCAN (0.3 s per 1,900 here) → c-TF-IDF labels → an LLM names ~30 clusters | Send every query to an LLM for open-ended labelling: 10⁵ calls, inconsistent label vocabulary |
| Avoid repeat LLM calls | Semantic cache with a model-specific τ, parameter checks and IVF lookup in tens of µs | Every request pays for generation |
| Corpus-level questions in RAG | RAPTOR-style tree (one LLM call per internal node at build time) | Stuffing many chunks into every prompt, every time |
| Triage a failure set | Cluster the failures, name the clusters, count them | Read 2,000 failures by hand, or ask an LLM to "summarize the errors" (unauditable) |

The pattern: **clustering does the cheap, consistent grouping, and the LLM is used once per group** for naming or summarizing.

---

## 3. Production Code Blueprint

### 3.1 k-means from scratch on real embeddings

```python
"""kmeans_on_embeddings.py - k-means from scratch on real sentence embeddings (CLINC150 / MiniLM), checked against sklearn.

  1. Lloyd's algorithm = alternate (assign to nearest centroid, move centroid to the mean); inertia never increases.
  2. Init matters: random vs k-means++ (inertia, iterations).
  3. On unit vectors, squared L2 = 2 - 2cos, so k-means is (almost) spherical k-means; renormalizing centroids.
  4. How well do unsupervised clusters recover the 150 labelled intents (ARI, NMI, purity)?
  5. Choosing k without labels: inertia elbow vs silhouette (sampled).
"""
import os
import time

import numpy as np
from sklearn.cluster import KMeans
from sklearn.metrics import adjusted_rand_score, normalized_mutual_info_score, silhouette_score

Z = np.load(os.path.join(os.environ["KB_DATA"], "clinc_minilm.npz"))
X, y = Z["X_train"].astype(np.float64), Z["y_train"]
rng = np.random.default_rng(71)


def sqdist(X, C):
    return np.maximum((X ** 2).sum(1)[:, None] + (C ** 2).sum(1)[None, :] - 2 * X @ C.T, 0)


def kmeans_pp(X, k, r):
    C = [X[r.integers(len(X))]]
    d2 = sqdist(X, np.array(C)).ravel()
    for _ in range(1, k):
        C.append(X[r.choice(len(X), p=d2 / d2.sum())])           # sample proportional to D(x)^2
        d2 = np.minimum(d2, sqdist(X, C[-1][None]).ravel())
    return np.array(C)


def lloyd(X, C, iters=100, spherical=False):
    hist = []
    for it in range(iters):
        D = sqdist(X, C)
        a = D.argmin(1)
        hist.append(D[np.arange(len(X)), a].sum())
        newC = np.stack([X[a == j].mean(0) if np.any(a == j) else C[j] for j in range(len(C))])
        if spherical:
            newC /= np.linalg.norm(newC, axis=1, keepdims=True)
        if np.allclose(newC, C, atol=1e-7):
            break
        C = newC
    return C, a, hist


print("== 1-2. Lloyd's algorithm, random vs k-means++ init (k=150, 15,000 x 384) ==")
k = 150
res = {}
for name, init in (("random rows", lambda r: X[r.choice(len(X), k, replace=False)]), ("k-means++", lambda r: kmeans_pp(X, k, r))):
    t0 = time.perf_counter()
    C, a, hist = lloyd(X, init(np.random.default_rng(1)))
    res[name] = (hist[-1], len(hist), a)
    mono = all(h2 <= h1 + 1e-6 for h1, h2 in zip(hist, hist[1:]))
    print(f"{name:12s} inertia {hist[-1]:9.2f} after {len(hist):3d} iterations ({time.perf_counter() - t0:.1f} s); "
          f"monotone non-increasing: {mono}")
    assert mono
sk = KMeans(n_clusters=k, n_init=1, random_state=1).fit(X)
print(f"sklearn KMeans (k-means++, n_init=1): inertia {sk.inertia_:9.2f} after {sk.n_iter_} iterations")
assert res["k-means++"][0] <= res["random rows"][0] * 1.02

print("\n== 3. unit vectors: ||x - c||^2 = 2 - 2 x.c only if ||c|| = 1; centroids of unit vectors are shorter ==")
cn = np.linalg.norm(sk.cluster_centers_, axis=1)
print(f"centroid norms: min {cn.min():.3f}, median {np.median(cn):.3f}, max {cn.max():.3f}  (a tight cluster -> norm near 1)")
Cs, a_s, _ = lloyd(X, kmeans_pp(X, k, np.random.default_rng(1)), spherical=True)
print(f"spherical k-means (renormalized centroids, assign by max cosine): agreement with plain k-means ARI "
      f"{adjusted_rand_score(res['k-means++'][2], a_s):.3f}")

print("\n== 4. do clusters recover the labelled intents? ==")


def purity(a, y):
    return sum(np.bincount(y[a == j]).max() for j in np.unique(a)) / len(y)


print(f"{'k':>4} {'ARI':>6} {'NMI':>6} {'purity':>7}")
for kk in (50, 150, 300):
    a = KMeans(n_clusters=kk, n_init=1, random_state=0).fit_predict(X)
    print(f"{kk:>4} {adjusted_rand_score(y, a):>6.3f} {normalized_mutual_info_score(y, a):>6.3f} {purity(a, y):>7.3f}")

print("\n== 5. choosing k without labels (silhouette on a 3,000-point sample) ==")
idx = rng.choice(len(X), 3000, replace=False)
print(f"{'k':>4} {'inertia':>10} {'silhouette':>10}")
sil = {}
for kk in (25, 50, 100, 150, 200, 300):
    m = KMeans(n_clusters=kk, n_init=1, random_state=0).fit(X)
    sil[kk] = silhouette_score(X[idx], m.labels_[idx])
    print(f"{kk:>4} {m.inertia_:>10.1f} {sil[kk]:>10.4f}")
print(f"silhouette's best k = {max(sil, key=sil.get)} (true number of intents = 150); inertia only ever decreases")
print("\nALL ASSERTIONS PASSED")
```

Output (verified; wall-clock seconds are one measured run):

```text
== 1-2. Lloyd's algorithm, random vs k-means++ init (k=150, 15,000 x 384) ==
random rows  inertia   7302.73 after  22 iterations (2.6 s); monotone non-increasing: True
k-means++    inertia   7283.27 after  27 iterations (8.4 s); monotone non-increasing: True
sklearn KMeans (k-means++, n_init=1): inertia   7138.81 after 23 iterations

== 3. unit vectors: ||x - c||^2 = 2 - 2 x.c only if ||c|| = 1; centroids of unit vectors are shorter ==
centroid norms: min 0.419, median 0.737, max 0.915  (a tight cluster -> norm near 1)
spherical k-means (renormalized centroids, assign by max cosine): agreement with plain k-means ARI 0.931

== 4. do clusters recover the labelled intents? ==
   k    ARI    NMI  purity
  50  0.349  0.787   0.326
 150  0.715  0.901   0.797
 300  0.632  0.881   0.879

== 5. choosing k without labels (silhouette on a 3,000-point sample) ==
   k    inertia silhouette
  25    10518.0     0.0648
  50     9366.2     0.0890
 100     7925.6     0.1226
 150     7105.9     0.1391
 200     6704.2     0.1384
 300     6179.0     0.1285
silhouette's best k = 150 (true number of intents = 150); inertia only ever decreases

ALL ASSERTIONS PASSED
```

### 3.2 HDBSCAN topic discovery on unhandled traffic

```python
"""hdbscan_topic_discovery.py - density-based clustering to discover NEW topics in traffic the router can't handle.

Scenario: the router knows 120 of CLINC's intents. Production also receives (a) 30 intents it was never trained on
and (b) generic out-of-scope chatter. Cluster the unhandled traffic to find candidate new intents.
  1. HDBSCAN (sklearn) finds a variable number of clusters and labels the rest as noise; k-means can't say "noise".
  2. Raw 384-d vs PCA-50 before clustering (speed and quality).
  3. Name each discovered cluster with class-based TF-IDF (the BERTopic labelling idea).
  4. How many of the 30 unseen intents surface as clean clusters?
"""
import json
import os
import re
import time
from collections import Counter

import numpy as np
from sklearn.cluster import HDBSCAN, KMeans
from sklearn.decomposition import PCA
from sklearn.metrics import adjusted_rand_score

DATA = os.environ["KB_DATA"]
Z = np.load(os.path.join(DATA, "clinc_minilm.npz"))
meta = json.load(open(os.path.join(DATA, "clinc_meta.json"), encoding="utf-8"))
labels, texts = meta["labels"], meta["texts"]
rng = np.random.default_rng(81)
unseen = rng.choice(150, 30, replace=False)                       # intents the router never saw

m_te = np.isin(Z["y_test"], unseen)
X = np.vstack([Z["X_test"][m_te], Z["X_oos_test"]])               # the escalated, unhandled traffic
y = np.r_[Z["y_test"][m_te], np.full(len(Z["X_oos_test"]), -1)]  # -1 = generic out-of-scope
T = [t for t, keep in zip(texts["test"], m_te) if keep] + texts["oos_test"]
print(f"unhandled traffic: {m_te.sum()} utterances from 30 unseen intents + {len(Z['X_oos_test'])} generic OOS = {len(X)}")

results = {}
for name, feats in (("raw 384-d", X), ("PCA-50", PCA(50, random_state=0).fit_transform(X))):
    t0 = time.perf_counter()
    h = HDBSCAN(min_cluster_size=12, min_samples=5, copy=True).fit(feats)
    dt = time.perf_counter() - t0
    lab = h.labels_
    inten = y >= 0
    ari = adjusted_rand_score(y[inten & (lab >= 0)], lab[inten & (lab >= 0)])
    results[name] = (lab, dt)
    print(f"\n== HDBSCAN on {name}: {lab.max() + 1} clusters, noise {np.mean(lab < 0):.1%} "
          f"(noise among generic OOS {np.mean(lab[~inten] < 0):.1%}, among unseen intents {np.mean(lab[inten] < 0):.1%}); "
          f"ARI on clustered intent points {ari:.3f}; {dt:.1f} s")

lab = results["PCA-50"][0]
km = KMeans(n_clusters=30, n_init=3, random_state=0).fit_predict(X)
print(f"\nk-means with k=30 (told the right answer) assigns 100% of points incl. all {np.sum(y < 0)} generic OOS; "
      f"ARI on intent points {adjusted_rand_score(y[y >= 0], km[y >= 0]):.3f}")

print("\n== 3. naming clusters with class-based TF-IDF (top words per cluster vs all clusters) ==")
tok = lambda s: [w for w in re.findall(r"[a-z']+", s.lower()) if len(w) > 2 and w not in
                 {"the", "and", "what", "how", "you", "can", "for", "my", "is", "are", "tell", "please", "with",
                  "that", "this", "does", "have", "would", "about", "need", "want", "know", "there", "your", "get"}]
clusters = sorted(set(lab) - {-1})
tf = {c: Counter(w for t, l in zip(T, lab) if l == c for w in tok(t)) for c in clusters}
df = Counter(w for c in clusters for w in tf[c])
avg_len = np.mean([sum(tf[c].values()) for c in clusters])
found = set()
print(f"{'cluster':>7} {'size':>4} {'purity':>6} {'majority intent':26s} top c-TF-IDF words")
for c in clusters:
    members = y[lab == c]
    maj, cnt = Counter(members).most_common(1)[0]
    pur = cnt / len(members)
    score = {w: n / sum(tf[c].values()) * np.log(1 + avg_len / df[w]) for w, n in tf[c].items()}
    top = " ".join(w for w, _ in sorted(score.items(), key=lambda kv: (-kv[1], kv[0]))[:4])
    name = labels[maj] if maj >= 0 else "(generic OOS)"
    if maj >= 0 and pur >= 0.8:
        found.add(maj)
    if c < 12:
        print(f"{c:>7} {len(members):>4} {pur:>6.2f} {name:26s} {top}")
print(f"... {len(clusters)} clusters in total")
print(f"\nunseen intents surfaced as a cluster with >= 80% purity: {len(found)} of 30")
assert len(found) >= 15 and results["PCA-50"][1] < results["raw 384-d"][1] * 2
print("\nALL ASSERTIONS PASSED")
```

Output (verified; clustering times are one measured run):

```text
unhandled traffic: 900 utterances from 30 unseen intents + 1000 generic OOS = 1900

== HDBSCAN on raw 384-d: 27 clusters, noise 57.4% (noise among generic OOS 92.9%, among unseen intents 17.9%); ARI on clustered intent points 0.797; 2.9 s

== HDBSCAN on PCA-50: 31 clusters, noise 50.5% (noise among generic OOS 86.4%, among unseen intents 10.7%); ARI on clustered intent points 0.849; 0.3 s

k-means with k=30 (told the right answer) assigns 100% of points incl. all 1000 generic OOS; ARI on intent points 0.712

== 3. naming clusters with class-based TF-IDF (top words per cluster vs all clusters) ==
cluster size purity majority intent            top c-TF-IDF words
      0   30   1.00 whisper_mode               whisper mode change off
      1   20   1.00 jump_start                 jump car start starting
      2   30   1.00 lost_luggage               luggage lost should has
      3   30   1.00 insurance                  health plan insurance benefits
      4   31   0.97 oil_change_how             oil change car changing
      5   31   0.97 w2                         form where tax taxes
      6   17   1.00 (generic OOS)              job look career funding
      7   12   0.83 jump_start                 battery dead car died
      8   15   1.00 (generic OOS)              much cost changed price
      9   35   0.80 car_rental                 car rent rental book
     10   31   0.97 do_you_have_pets           pets cats dogs own
     11   31   0.97 order_checks               checkbooks order more checks
... 31 clusters in total

unseen intents surfaced as a cluster with >= 80% purity: 22 of 30

ALL ASSERTIONS PASSED
```

How to read it: the "noise among generic OOS" vs "noise among unseen intents" split is the number to watch. A good triage clusterer rejects chatter (86.4% noise) and keeps real topics (10.7% noise). The last line, **22 of 30** unseen intents surfaced at ≥ 80% purity, is the business outcome: 22 candidate intents found without anyone labelling anything.

### 3.3 A semantic cache with IVF, and a RAPTOR-style tree

```python
"""semantic_cache_ivf_and_raptor_tree.py - k-means as infrastructure: an IVF-partitioned semantic cache and a RAPTOR-style tree.

Semantic cache: 15,000 previously answered prompts (CLINC train) are the cache keys. Queries are CLINC test
in-scope utterances plus out-of-scope queries. A "hit" is served when max cosine >= tau.
  1. Hit rate vs hit precision vs OOS false hits, as tau varies.
  2. Same intent is NOT the same answer: hits whose texts carry different numbers ("6am" vs "7am").
  3. IVF: k-means partitions the keys into nlist cells; probing nprobe cells trades recall for latency.
  4. RAPTOR-style tree: recursive k-means over chunks, a node vector per cluster; collapsed-tree search cost.
     (RAPTOR writes LLM summaries for each node; here the node "summary" is the member nearest its centroid.)
"""
import json
import os
import re
import time

import numpy as np
from sklearn.cluster import KMeans

DATA = os.environ["KB_DATA"]
Z = np.load(os.path.join(DATA, "clinc_minilm.npz"))
T = json.load(open(os.path.join(DATA, "clinc_meta.json"), encoding="utf-8"))["texts"]
K, yK = Z["X_train"], Z["y_train"]
Q = np.vstack([Z["X_test"], Z["X_oos_test"]])
yQ = np.r_[Z["y_test"], np.full(len(Z["X_oos_test"]), -1)]
TQ = T["test"] + T["oos_test"]

S = Q @ K.T
best = S.argmax(1)
top = S[np.arange(len(Q)), best]
print("== 1. exhaustive semantic cache over 15,000 keys ==")
print(f"{'tau':>5} {'hit rate':>8} {'hit precision (same intent)':>28} {'OOS false-hit rate':>19}")
for tau in (0.70, 0.80, 0.85, 0.90, 0.95):
    hit = top >= tau
    prec = np.mean(yK[best[hit]] == yQ[hit]) if hit.any() else float("nan")
    print(f"{tau:>5.2f} {hit.mean():>8.3f} {prec:>28.3f} {np.mean(hit[yQ < 0]):>19.3f}")

print("\n== 2. same intent, different answer: hits at tau = 0.90 whose numbers differ ==")
WORDS = {w: str(i) for i, w in enumerate("zero one two three four five six seven eight nine ten eleven twelve".split())}
num = lambda s: tuple(WORDS.get(t, t) for t in re.findall(r"[a-z]+|\d+", s.lower()) if t.isdigit() or t in WORDS)
hit = (top >= 0.90) & (yQ >= 0)
diff = [i for i in np.flatnonzero(hit) if yK[best[i]] == yQ[i] and num(TQ[i]) and num(T["train"][best[i]])
        and num(TQ[i]) != num(T["train"][best[i]])]
print(f"{len(diff)} of {hit.sum()} same-intent hits change a number (after 'four' -> '4' normalization). Examples:")
for i in diff[:4]:
    print(f"  {top[i]:.3f}  query '{TQ[i]}'  ->  cached '{T['train'][best[i]]}'")
assert len(diff) > 0

print("\n== 3. IVF partitioning (k-means, nlist = 64) vs exhaustive top-1 (one measured run for latency) ==")
km = KMeans(n_clusters=64, n_init=1, random_state=0).fit(K)
cells = [np.flatnonzero(km.labels_ == c) for c in range(64)]
cellK = [np.ascontiguousarray(K[ids]) for ids in cells]          # store each cell contiguously, like an IVF index
C = km.cluster_centers_ / np.linalg.norm(km.cluster_centers_, axis=1, keepdims=True)
sizes = np.array([len(c) for c in cells])
print(f"cell sizes: min {sizes.min()}, median {int(np.median(sizes))}, max {sizes.max()} (k-means cells are unequal)")
print(f"{'nprobe':>6} {'keys scanned':>12} {'recall of exact top-1':>21} {'us/query':>9}")
t0 = time.perf_counter()
for q in Q[:500]:
    (K @ q).argmax()
t_exh = (time.perf_counter() - t0) / 500
rec = {}
for nprobe in (1, 2, 4, 8, 16):
    found, scanned = 0, 0
    t0 = time.perf_counter()
    for i, q in enumerate(Q[:2000]):
        probe = np.argpartition(-(C @ q), nprobe)[:nprobe] if nprobe < 64 else np.arange(64)
        top_score, top_id = -2.0, -1
        for c in probe:                                            # score each probed cell in place
            s = cellK[c] @ q
            j = int(s.argmax())
            if s[j] > top_score:
                top_score, top_id = s[j], cells[c][j]
            scanned += len(s)
        found += top_id == best[i]
    dt = (time.perf_counter() - t0) / 2000
    rec[nprobe] = found / 2000
    print(f"{nprobe:>6} {scanned / 2000:>12.0f} {rec[nprobe]:>21.3f} {dt * 1e6:>9.1f}")
print(f"{'exhaustive':>6} {len(K):>12} {1.0:>21.3f} {t_exh * 1e6:>9.1f}")
assert rec[16] > rec[1] and rec[16] > 0.95

print("\n== 4. RAPTOR-style tree over 2,000 utterances (20 intents) ==")
sub = np.flatnonzero(yK < 20)
X0, txt0 = K[sub], [T["train"][i] for i in sub]
levels = [(X0, list(range(len(X0))))]
cur = X0
while len(cur) > 8:
    k = max(len(cur) // 10, 2)
    lab = KMeans(n_clusters=k, n_init=1, random_state=0).fit_predict(cur)
    nodes = np.stack([cur[lab == c].mean(0) for c in range(k)])
    nodes /= np.linalg.norm(nodes, axis=1, keepdims=True)
    levels.append((nodes, lab))
    cur = nodes
for li, (nodes, _) in enumerate(levels):
    print(f"level {li}: {len(nodes):>5} nodes" + ("  (leaves = original chunks)" if li == 0 else ""))
root_level = levels[-1][0]
rep = [txt0[int(np.argmax(X0 @ v))] for v in root_level]
print("top-level node 'summaries' (nearest member to each centroid):")
for r in rep[:4]:
    print(f"  '{r}'")
allnodes = np.vstack([n for n, _ in levels])
lvl_of = np.concatenate([np.full(len(n), i) for i, (n, _) in enumerate(levels)])
qsub = Z["X_test"][Z["y_test"] < 20]
hits = lvl_of[(qsub @ allnodes.T).argmax(1)]
print(f"collapsed-tree search scans {len(allnodes):,} vectors vs {len(X0):,} leaves (+{len(allnodes) / len(X0) - 1:.1%}); "
      f"top hit level for specific queries: " + ", ".join(f"L{l}={np.mean(hits == l):.2f}" for l in range(len(levels))))
print("\nALL ASSERTIONS PASSED")
```

Output (verified, except the µs/query column, which is one measured run):

```text
== 1. exhaustive semantic cache over 15,000 keys ==
  tau hit rate  hit precision (same intent)  OOS false-hit rate
 0.70    0.644                        0.928               0.032
 0.80    0.489                        0.961               0.005
 0.85    0.387                        0.973               0.003
 0.90    0.258                        0.984               0.002
 0.95    0.110                        0.985               0.000

== 2. same intent, different answer: hits at tau = 0.90 whose numbers differ ==
11 of 1417 same-intent hits change a number (after 'four' -> '4' normalization). Examples:
  0.932  query 'can i put in a pto request for september 1st to september 8th'  ->  cached 'can you put in a pto request for march 7th to the 9th'
  0.915  query 'can i put in a pto request for august 1st to august 10th'  ->  cached 'can you put in a pto request for march 7th to the 9th'
  0.934  query 'can i put in a pto request for january 4th to january 9th'  ->  cached 'would it be possible to make a pto request for january 15th and 16th'
  0.905  query 'can i put in a pto request for december 25th to january 1st'  ->  cached 'am i able to place a pto request for february 20-25'

== 3. IVF partitioning (k-means, nlist = 64) vs exhaustive top-1 (one measured run for latency) ==
cell sizes: min 61, median 220, max 559 (k-means cells are unequal)
nprobe keys scanned recall of exact top-1  us/query
     1          284                 0.895      24.0
     2          571                 0.961      38.6
     4         1123                 0.980      82.4
     8         2178                 0.989     165.1
    16         4210                 0.999     367.4
exhaustive        15000                 1.000    1361.4

== 4. RAPTOR-style tree over 2,000 utterances (20 intents) ==
level 0:  2000 nodes  (leaves = original chunks)
level 1:   200 nodes
level 2:    20 nodes
level 3:     2 nodes
top-level node 'summaries' (nearest member to each centroid):
  'book me a flight out of la to chicago on march 3rd for under $500'
  'give me the date my bill is due'
collapsed-tree search scans 2,222 vectors vs 2,000 leaves (+11.1%); top hit level for specific queries: L0=0.67, L1=0.24, L2=0.09, L3=0.00

ALL ASSERTIONS PASSED
```

---

## 4. The Andrew Ng Lens: Cluster the Errors, Then Count Them

### 4.1 Clustering builds the error-analysis buckets for you

Ng's error-analysis spreadsheet needs tags. For hundreds of failures, invent the tags by clustering: embed the failed queries (or the router's errors from 02.3), run HDBSCAN, name the clusters with c-TF-IDF, and use the cluster names as the initial tag vocabulary. Then review and merge by hand. The spreadsheet's first column becomes "cluster", and the count per cluster prioritizes the work. That's exactly how the 22 new-intent candidates in §3.2 would reach a roadmap.

### 4.2 Data-centric: clusters reveal label problems

A cluster that mixes two labelled intents at ~50/50 purity is a candidate **label-definition problem** (two intents that users don't distinguish), not a model problem. Purity < 0.8 clusters are where to audit labels. CLINC's `jump_start` splitting into two clusters is the opposite signal: one intent with two distinct phrasings, which might deserve two exemplar sets.

### 4.3 Evaluation-driven caching

Before enabling a semantic cache, build its eval: a sample of (query, cached-hit) pairs at the candidate τ, labelled "same answer?" by a human (or by a calibrated LLM judge, Folder 06). The measured "same-intent precision" (0.984 at τ = 0.90) is an *upper bound* on answer correctness: the PTO examples are same-intent but wrong-answer. The cache's acceptance metric is answer correctness.

---

## 5. Failure Modes

| # | Symptom | Signature | Root cause | Fix | Prevention |
|---|---|---|---|---|---|
| F1 | Semantic cache serves the wrong dates/amounts | High cosine, same intent, different parameters (PTO examples) | Embeddings capture intent, not exact parameters | Parameter extraction + exact match; cache only parameter-free requests | Answer-correctness eval on sampled hits |
| F2 | Cache hit rate jumps after an encoder upgrade, errors follow | Score distribution shifted | τ not re-derived (01.1 §1.7) | Re-derive τ on labelled pairs | τ versioned with the encoder |
| F3 | Personalized answers leak across users | Cache key lacks user/tenant scope | Similarity-only keys | Scope keys by tenant/user/locale/version | Security review of cache key composition |
| F4 | IVF recall drops after corpus growth | New content lands in a few overfull cells | Centroids trained on old data | Retrain the IVF quantizer; rebalance | Monitor cell-size distribution and recall on a probe set |
| F5 | IVF p99 latency spikes | Very unequal cell sizes (61 vs 559) | k-means imbalance | More cells, balanced k-means, cap per-cell scans | Track scanned keys per query |
| F6 | Topic discovery produces one giant cluster and noise | HDBSCAN on raw high-d vectors with a small `min_samples` | Density estimation in high dimension | PCA/UMAP first; tune `min_cluster_size` | A labelled sample to sanity-check purity |
| F7 | k-means "topics" are full of junk | Every point forced into a cluster | k-means has no noise label | HDBSCAN, or a distance threshold for "unassigned" | Report the fraction of low-similarity members per cluster |
| F8 | Different clusters every run | Unseeded, single-init k-means | Local optima | k-means++, `n_init` > 1, fixed seeds | Cluster stability (ARI between runs) as a metric |
| F9 | RAPTOR index stale after document updates | Summaries reflect deleted content | Tree built once, never refreshed | Incremental re-clustering of affected branches; rebuild schedule | Track summary age vs source change time |
| F10 | Cluster centroids used with cosine scoring behave oddly | Centroid norms 0.42–0.92 | Means of unit vectors aren't unit | Renormalize centroids (spherical k-means) | Contract: stored centroids are normalized |

---

## 6. Bar-Raiser Q&A Chains

<details><summary><b>Q1 · "We want to find out what users ask that our bot can't handle. How?"</b></summary>

**Initial Prompt.** 100k escalated conversations per week, no labels.

**L5 Answer.** "Run k-means with k = 50 on the embeddings and look at the clusters."

**Why L5 Fails in Production.** k-means forces every query, including one-off chatter, into a cluster, so the clusters are polluted and k is a guess. We measured k-means *given the true k* recovering new intents worse (ARI 0.712) than HDBSCAN without being told k (0.849).

**L7 Principal Defense.** "Reuse the routing embeddings, reduce to ~50 dims with PCA (10× faster and better than raw 384-d here), run HDBSCAN with `min_cluster_size` set to the smallest topic worth building (say 12–50), and treat noise as noise. In our CLINC test, 86% of generic chatter became noise while 89% of genuinely new-intent traffic clustered, and 22 of 30 unseen intents surfaced at ≥ 80% purity. Name the clusters with c-TF-IDF, have an LLM polish ~30 names (not 100k labels), rank them by volume × business value, and feed the winners into the router's training set."

**Bar-Raiser Follow-ups.**
- *"How do you validate without labels?"* Label a sample per cluster (purity estimate), and check cluster stability across runs and weeks.
- *"Weekly drift?"* Cluster each week, match clusters across weeks by centroid cosine, and alert on new, persistent clusters.

</details>

<details><summary><b>Q2 · "Design a semantic cache for our support assistant."</b></summary>

**Initial Prompt.** 30% of questions look repetitive. Leadership wants a 30% LLM cost cut.

**L5 Answer.** "Embed each prompt, and if cosine > 0.9 with a cached prompt, return the cached answer."

**Why L5 Fails in Production.** "Similar" isn't "same answer". In our data, at τ = 0.90, PTO requests for different date ranges match at cosine 0.93. It also ignores tenant scoping, freshness, and the fact that τ is model-specific.

**L7 Principal Defense.** "Key = (tenant, locale, model and prompt version, normalized parameters) plus the embedding. A hit needs the parameters to match exactly *and* cosine ≥ τ, with τ derived per encoder from labelled pairs. Our CLINC sweep shows the trade-off: τ = 0.80 hits 48.9% at 96.1% same-intent precision, τ = 0.90 hits 25.8% at 98.4%. Answers carry TTLs by type. Lookup is an IVF index with nprobe chosen for ~0.99 recall (16 of 64 cells gave 0.999 at 3.7× less work). The acceptance metric is answer correctness on sampled hits, judged by humans or a calibrated LLM judge. Realistic savings come from parameter-free traffic (FAQs, policy), so measure that share before promising 30%."

**Bar-Raiser Follow-ups.**
- *"What about multi-turn context?"* Include a hash of the relevant prior turns in the key, or cache only first-turn, context-free questions.
- *"Invalidation?"* Version answers by the source documents they cite. A document update invalidates dependent entries.

</details>

<details><summary><b>Q3 · "Explain why Lloyd's algorithm converges and why it can still give a bad answer."</b></summary>

**Initial Prompt.** A theory check.

**L5 Answer.** "It converges because the centroids stop moving."

**Why L5 Fails in Production.** It doesn't explain *why* the centroids stop moving, or why restarts matter.

**L7 Principal Defense.** "The inertia J = Σ‖xᵢ − c_{a(i)}‖² never increases. Assignment moves each point to a nearer centroid, and the update sets each centroid to the mean, which is the unique minimizer of squared distance for fixed members. Finitely many assignments plus monotone J means termination, but only at a *local* minimum, since the objective is non-convex. k-means++ seeding gives an expected O(log k) approximation before Lloyd starts. scikit-learn's greedy variant (several candidate seeds per step) beat plain k-means++ in our run, 7,139 vs 7,283. So: k-means++, several `n_init` restarts, and keep the lowest inertia."

**Bar-Raiser Follow-ups.**
- *"Why squared distance?"* Because the mean minimizes it. With absolute distance you'd need medians (k-medians), and with arbitrary dissimilarities, medoids (k-medoids).

</details>

<details><summary><b>Q4 · "How do you pick nlist and nprobe for an IVF index?"</b></summary>

**Initial Prompt.** 50M vectors, 10 ms budget, recall@10 ≥ 0.95.

**L5 Answer.** "Use the FAISS defaults."

**Why L5 Fails in Production.** There are no meaningful defaults. Recall depends on data and nprobe, and cost on how many vectors you scan. Our 15k-key test went from recall 0.895 at nprobe = 1 to 0.999 at 16.

**L7 Principal Defense.** "Start from nlist ≈ √N to 4√N (for 50M, a few thousand to ~30k cells), so cells hold thousands of vectors. Then sweep nprobe on a held-out query set against exact search, and plot recall vs keys scanned. Pick the knee that meets recall ≥ 0.95, then check p99 with real cell-size skew, which reached 9× in our small test. Store cells contiguously, since gathering scattered rows dominated latency in our first implementation. For memory, combine IVF with PQ or binary codes and rescore (01.1 §1.10)."

**Bar-Raiser Follow-ups.**
- *"When IVF vs HNSW?"* IVF is simple, memory-light, easy to shard and rebuild, and works well with quantization. HNSW has better recall/latency at moderate scale but more memory. The Production AI Engineering KB, Folder 03, covers both.

</details>

<details><summary><b>Q5 · "Should we use RAPTOR for our RAG system?"</b></summary>

**Initial Prompt.** Users ask both specific questions and "summarize the themes" questions over a 10k-document corpus.

**L5 Answer.** "Yes, it improves retrieval on benchmarks."

**Why L5 Fails in Production.** It adds a build-time LLM cost per internal node and a staleness problem, and its benefit depends on the question mix. Benchmark gains don't transfer automatically.

**L7 Principal Defense.** "RAPTOR recursively clusters chunks, writes an LLM summary per cluster, and retrieves over all levels (the 'collapsed tree'). Query-time cost is small (+11% vectors in our structure test). Build cost is one LLM call per internal node, repeated whenever clusters change. Even specific queries hit internal nodes a third of the time in our test, so summary quality directly affects answers. I'd evaluate on our own question mix: tag questions as specific vs thematic, measure answer quality with flat retrieval vs collapsed tree, and only adopt it if thematic questions improve without hurting specific ones. Refresh affected branches incrementally when documents change."

**Bar-Raiser Follow-ups.**
- *"Cheaper alternative for thematic questions?"* Map-reduce summarization over retrieved chunks at query time, for rare thematic questions. Or precomputed per-document summaries (one level, not a tree).

</details>

<details><summary><b>Q6 · "Why does HDBSCAN label half our points as noise? Isn't that a failure?"</b></summary>

**Initial Prompt.** A stakeholder sees "noise: 50%" and worries.

**L5 Answer.** "Lower `min_cluster_size` until there's less noise."

**Why L5 Fails in Production.** Noise is often the correct answer: one-off queries aren't a topic. Forcing them into clusters reproduces k-means's pollution.

**L7 Principal Defense.** "Look at *what* is noise. In our test, 86% of generic out-of-scope chatter was noise and only 11% of the real new-intent traffic was. That's the behaviour we want. Noise means a point isn't in a region dense enough to persist across density levels (mutual reachability with `min_samples`). Tune `min_cluster_size` to the smallest topic worth acting on, not to hit a noise target. If real topics are being called noise, reduce dimensions first (PCA-50 cut noise among real intents from 17.9% to 10.7%) or lower `min_samples`."

**Bar-Raiser Follow-ups.**
- *"Can you assign noise points later?"* Yes. HDBSCAN supports approximate prediction and soft membership, or assign by nearest cluster centroid above a similarity threshold, and track how many stay unassigned.

</details>

<details><summary><b>Q7 · "How do you know the embedding space even has the structure you're clustering for?"</b></summary>

**Initial Prompt.** Before investing in topic discovery.

**L5 Answer.** "Embeddings capture semantics, so clusters will be meaningful."

**Why L5 Fails in Production.** That's an assumption, and a cheap test exists.

**L7 Principal Defense.** "Measure it on a labelled sample. On CLINC, k-means with k = 150 recovered the 150 labelled intents at ARI 0.715, NMI 0.901, and the label-free silhouette peaked exactly at k = 150. So the space carries intent structure. If a similar test on your own data shows low ARI, the encoder isn't separating your notion of 'topic', and the fix is a different or fine-tuned encoder (Folder 04), not a different clustering algorithm."

**Bar-Raiser Follow-ups.**
- *"Why is silhouette only 0.14?"* Clusters in high-dimensional text embeddings touch, and distances concentrate. Compare silhouettes across k rather than reading the absolute value.

</details>

<details><summary><b>Q8 · "Our IVF cluster centroids are used for cosine routing, and results look off."</b></summary>

**Initial Prompt.** The centroids from FAISS/sklearn k-means are reused as intent prototypes.

**L5 Answer.** "Centroids are means, so they're representative."

**Why L5 Fails in Production.** Means of unit vectors aren't unit vectors (norms 0.42–0.92 here), so dot-product scores against them mix tightness with similarity.

**L7 Principal Defense.** "‖x − c‖² = 1 + ‖c‖² − 2x·c for unit x, so the k-means geometry and cosine scoring disagree unless ‖c‖ = 1. Renormalize the centroids (spherical k-means), which agreed with plain k-means at ARI 0.931 here but scores correctly under cosine. Keep the original norm as a separate feature if you want 'cluster tightness'. Same contract as everything else: vectors served for cosine are unit length."

**Bar-Raiser Follow-ups.**
- *"Does FAISS do this?"* Spherical k-means is an option in FAISS's k-means (`spherical=True`). Set it explicitly for cosine/IP indexes.

</details>

---

## 7. Invariants Checklist

- [ ] k-means uses k-means++ seeding, multiple restarts and fixed seeds. Stability (ARI across runs) is tracked.
- [ ] Centroids used for cosine scoring are renormalized (spherical k-means).
- [ ] Topic discovery uses density clustering (HDBSCAN) on dimension-reduced embeddings. Noise is reported, not forced into clusters.
- [ ] Every discovered cluster gets a purity estimate from a labelled sample before it drives roadmap decisions.
- [ ] Semantic-cache keys are scoped (tenant, user, locale, model/prompt version) and include exact parameter matching.
- [ ] Cache τ is derived per encoder, and acceptance is measured as answer correctness on sampled hits.
- [ ] IVF nprobe is chosen from a recall-vs-scanned curve against exact search. Cell sizes and recall are monitored.
- [ ] RAPTOR-style trees have a refresh policy and are adopted only after an eval on your own specific vs thematic questions.

---

## 8. References

1. S. Lloyd, *Least squares quantization in PCM*, IEEE Trans. Information Theory 28(2), 1982. DOI 10.1109/TIT.1982.1056489.
2. D. Arthur, S. Vassilvitskii, *k-means++: The Advantages of Careful Seeding*, SODA 2007.
3. R. Campello, D. Moulavi, J. Sander, *Density-Based Clustering Based on Hierarchical Density Estimates*, PAKDD 2013. DOI 10.1007/978-3-642-37456-2_14.
4. L. McInnes, J. Healy, S. Astels, *hdbscan: Hierarchical density based clustering*, JOSS 2017. https://joss.theoj.org/papers/10.21105/joss.00205
5. M. Grootendorst, *BERTopic: Neural topic modeling with a class-based TF-IDF procedure*, 2022. https://arxiv.org/abs/2203.05794
6. P. Sarthi et al., *RAPTOR: Recursive Abstractive Processing for Tree-Organized Retrieval*, ICLR 2024. https://arxiv.org/abs/2401.18059
7. H. Jégou, M. Douze, C. Schmid, *Product Quantization for Nearest Neighbor Search* (IVF-ADC), IEEE TPAMI 33(1), 2011. DOI 10.1109/TPAMI.2010.57.
8. FAISS wiki, *Faiss indexes* (IndexIVFFlat, nlist/nprobe guidance). https://github.com/facebookresearch/faiss/wiki/Faiss-indexes
9. scikit-learn user guide, *Clustering* (KMeans, HDBSCAN, clustering metrics). https://scikit-learn.org/stable/modules/clustering.html
10. L. Hubert, P. Arabie, *Comparing partitions* (ARI), Journal of Classification 2, 1985. DOI 10.1007/BF01908075.
11. P. Rousseeuw, *Silhouettes: a graphical aid to the interpretation and validation of cluster analysis*, J. Comput. Appl. Math. 20, 1987. DOI 10.1016/0377-0427(87)90125-7.
12. S. Larson et al., *CLINC150*, EMNLP 2019. https://arxiv.org/abs/1909.02027
