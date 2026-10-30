# 03.2 · Dimensionality Reduction: PCA, t-SNE & UMAP for Embedding-Drift Visualization

> **Folder 03 · Unsupervised Learning, Clustering & Anomaly Detection in AI Systems**
> **Measured on:** scikit-learn 1.9.1 (`TSNE`, `PCA`, `trustworthiness`), umap-learn 0.5.12 (numba 0.68.1, one thread), NumPy 2.5.4, CPython 3.14.5, Intel i5-11260H, Windows 11.
> **Real data:** CLINC150 utterances embedded with `all-MiniLM-L6-v2`.
> **Design sources:** van der Maaten & Hinton (t-SNE, JMLR 2008), McInnes et al. (UMAP, 2018), Wattenberg et al. (Distill, 2016), Gretton et al. (kernel two-sample test, JMLR 2012), Lopez-Paz & Oquab (classifier two-sample tests, ICLR 2017), Rabanser et al. (*Failing Loudly*, NeurIPS 2019). Full list in §8.

---

## 0. Orientation: Look at 2-D Maps, but Decide in 384-D

Here's the Andrew Ng-style version. **2-D maps of embeddings are for building intuition and finding examples to read. They are not instruments.** t-SNE and UMAP preserve *who is near whom* and freely distort everything else: distances between clusters, cluster sizes, and how separated things look. This file measures exactly how much, and then shows how to detect drift properly, with statistical tests in the full embedding space and calibrated false-alarm rates.

Three numbers from §3 make the point:

1. **The maps exaggerate separation.** Intent silhouette is **0.335** in the real 384-d space, but **0.649** in a t-SNE map and **0.739–0.789** in UMAP maps. They look twice as clean as the data is.
2. **Global distances barely survive.** The rank correlation between 384-d and 2-D pairwise distances is **0.32–0.45** for every method, PCA included.
3. **A real drift (30% of traffic from new intents) is detected by a permutation test at p = 0.005** in the full space, with no picture required.

### The backend-engineer bridge

| You already know | Equivalent here |
|---|---|
| A dashboard sparkline vs the alerting rule behind it | **2-D embedding map vs a two-sample test** in the full space |
| Load-test baselines vs production traffic | **Reference window vs production window** |
| Alert fatigue from correlated alarms | **Correlated drift false alarms** when every window is compared to one fixed reference |
| Schema diffs between two table snapshots | **A domain classifier**: if a model can tell the two windows apart, they differ |

### Tier map

| Subtopic | Tier |
|---|---|
| 1.1 PCA recap: the linear baseline map | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.2 t-SNE: perplexity, heavy tails, the crowding problem | `[GOOD-TO-KNOW: Architectural Literacy]` |
| 1.3 UMAP: kNN graphs and fuzzy cross-entropy | `[GOOD-TO-KNOW: Architectural Literacy]` |
| 1.4 What 2-D maps preserve and what they invent | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.5 Run-to-run stability | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.6 Drift detectors in the full space, and what each catches | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.7 MMD: a kernel two-sample test with a permutation p-value | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.8 Classifier two-sample tests (the domain classifier) | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.9 False alarms: the null, correlated windows, multiple testing | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.10 Manifold-learning theory (Isomap, LLE, spectral embeddings) | `[SKIP: Academic/Research Only]` |

---

## 1. First-Principles Math & Geometric Intuition

### 1.1 PCA recap: the linear baseline map `[MUST-KNOW: Core AI Engineer Edge]`

PCA to 2 dims (01.2 §1.5) keeps the two directions of greatest variance: linear, deterministic and invertible. On 3,000 CLINC utterances from 30 intents, it keeps very little *local* structure:

```text
method                 trust@10 10-NN kept pairwise rho centroid rho silhouette
(original 384-d)          1.000      1.000        1.000        1.000      0.335
PCA-2                     0.789      0.099        0.431        0.588     -0.018
```

Only 9.9% of each point's 10 nearest neighbours are still its neighbours in 2-D, and intents overlap completely (silhouette −0.018). Text embeddings don't live near a 2-D plane: 01.2 measured ~32–48 dims for 96–99.8% of the variance on structured data. PCA-2 is still useful for one thing, as a *stable, comparable* coordinate system across weeks, because the same fitted projection can be applied to new data.

### 1.2 t-SNE: perplexity, heavy tails, the crowding problem `[GOOD-TO-KNOW: Architectural Literacy]`

t-SNE (van der Maaten & Hinton, 2008) turns distances into neighbour probabilities and matches them:

```text
high-d:  p_{j|i} = exp(−‖xᵢ − xⱼ‖²/2σᵢ²) / Σ_k exp(−‖xᵢ − x_k‖²/2σᵢ²),   σᵢ set so that 2^{H(P_i)} = perplexity
         p_ij = (p_{j|i} + p_{i|j}) / 2n
low-d:   q_ij ∝ (1 + ‖yᵢ − yⱼ‖²)⁻¹          (Student-t with one degree of freedom: heavy tails)
minimize KL(P ‖ Q) over the 2-D points y
```

- **Perplexity** is the effective number of neighbours each point "listens to" (5–100 is typical). Each σᵢ adapts to local density, so dense and sparse regions both look evenly spread. That's why **cluster sizes in t-SNE are meaningless**.
- **Heavy tails solve the crowding problem.** There isn't enough room in 2-D for all the moderately distant points of a high-d space. The t-distribution lets moderately distant pairs sit far apart in 2-D at little cost, which is why **gaps between clusters are exaggerated**.
- **KL(P‖Q) is forward KL** (01.3 §1.8). It heavily penalizes putting true neighbours far apart (large p, small q), and barely penalizes putting non-neighbours close. So local structure is protected, and global structure is not.

### 1.3 UMAP: kNN graphs and fuzzy cross-entropy `[GOOD-TO-KNOW: Architectural Literacy]`

UMAP (McInnes et al., 2018) builds a weighted k-nearest-neighbour graph (`n_neighbors`), with edge weights that decay from each point's nearest-neighbour distance. It then optimizes a 2-D layout whose graph matches it under a fuzzy-set cross-entropy, using negative sampling. `min_dist` controls how tightly points pack. In practice:

- It's faster on big data, and supports `transform()` for new points (t-SNE in scikit-learn doesn't).
- A larger `n_neighbors` weights more global structure. In our run, the centroid-distance correlation rose from 0.601 at n_neighbors = 15 to **0.679 at 50**, the best of any method, while 10-NN preservation fell from 0.501 to 0.399.
- It's stochastic, and it uses a numba JIT. The first call compiles kernels (part of the 21.9 s here), and the compiled cache has to live under a short path on Windows, because numba's cache file names exceed MAX_PATH under a long temp directory (a failure we hit while building this listing).

### 1.4 What 2-D maps preserve and what they invent `[MUST-KNOW: Core AI Engineer Edge]`

The full measurement (§3.1):

```text
method                 trust@10 10-NN kept pairwise rho centroid rho silhouette
(original 384-d)          1.000      1.000        1.000        1.000      0.335
PCA-2                     0.789      0.099        0.431        0.588     -0.018
t-SNE perplexity 5        0.991      0.574        0.429        0.569      0.374
t-SNE perplexity 30       0.995      0.616        0.406        0.588      0.649
t-SNE perplexity 100      0.995      0.591        0.454        0.560      0.626
UMAP n_neighbors 15       0.992      0.501        0.324        0.601      0.739
UMAP n_neighbors 50       0.991      0.399        0.333        0.679      0.789
```

What each column means:

- **Trustworthiness@10** (Venna & Kaski) penalizes points that look close in 2-D but weren't close in 384-d. It's ≥ 0.991 for t-SNE and UMAP: when two points are neighbours on the map, they really are similar. You can trust *local reading*, i.e. "these points near each other are paraphrases".
- **10-NN kept** is the reverse direction. Only 40–62% of true neighbours remain neighbours in 2-D, so the map hides many real similarities.
- **Pairwise rho** (Spearman, 384-d vs 2-D distances) is 0.32–0.45 for all methods. **Do not read distances between far-apart points or clusters off any 2-D map.**
- **Silhouette** is 0.65–0.79 on the maps vs 0.335 in reality. The maps make intents look twice as separable as they are, so a router's confusion (02.3) is invisible on a pretty UMAP.

```text
  what the map shows                  what's true in 384-d
  ┌──────────┐      ┌──────────┐      clusters touch; distances concentrate;
  │  ●●●●    │      │    ▲▲▲   │      "far apart on the map" ≠ "far apart";
  │  ●●●●    │      │    ▲▲▲   │      big blob on the map ≠ many points or large spread
  └──────────┘      └──────────┘
   clean islands with empty gaps between them (heavy tails + per-point σᵢ)
```

### 1.5 Run-to-run stability `[MUST-KNOW: Core AI Engineer Edge]`

```text
t-SNE perplexity 30    10-NN overlap between seeds 0.963; intent-centroid distance rho between seeds 0.999
UMAP n_neighbors 15    10-NN overlap between seeds 0.628; intent-centroid distance rho between seeds 0.883
```

scikit-learn's t-SNE with `init="pca"` is nearly deterministic across seeds here, because the PCA initialization dominates. UMAP's layout changes materially with the seed: only 63% of 2-D neighbourhoods are shared between two runs. So **two weeks' UMAP plots fitted separately cannot be compared visually.** A cluster "moving" may just be the random seed. If you must compare maps over time, fit once on the reference and use `umap.transform()` (or the fixed PCA projection) for new windows, and still decide with the tests below.

### 1.6 Drift detectors in the full space, and what each catches `[MUST-KNOW: Core AI Engineer Edge]`

Rabanser et al. (*Failing Loudly*, 2019) benchmarked shift detectors and found two-sample tests on (reduced) representations effective. The practical lesson is to combine a few complementary detectors. We built five windows against a reference of 1,800 queries from 120 known intents, with every window drawn *without replacement* from a disjoint pool (§1.9 explains why that matters):

```text
window                       mean shift recon err x    MMD^2 p-value domain AUC  novelty
W0 same distribution            0.01326       1.030  0.00242   0.562      0.491    0.065
W1 +10% OOS                     0.01344       1.075  0.00250   0.448      0.487    0.138
W2 +30% OOS                     0.02345       1.134  0.00377   0.005      0.541    0.298
W3 mix shift (40 intents)       0.06415       1.003  0.00864   0.005      0.758    0.063
W4 30% unseen intents           0.02035       1.083  0.00351   0.005      0.516    0.168
```

| Detector | What it catches | What it misses |
|---|---|---|
| **Mean shift** (1 − cos of the means) | Mix shifts (W3: 0.064, 5× W0) | New content that averages out (W1 ≈ W0) |
| **PCA reconstruction error** (×reference) | Content outside the reference subspace (W2 1.134, W4 1.083) | Mix shifts within the subspace (W3 1.003) |
| **MMD² permutation test** | Any distribution difference with enough mass: W2, W3, W4 at p = 0.005 | Small fractions in small windows (W1, 10% OOS: p = 0.448) |
| **Domain-classifier AUC** | Mix shift (W3 0.758) | Diffuse new content (W2 only 0.541) |
| **Novelty rate** (share of queries far from every known intent centroid) | New content: W2 0.298, W4 0.168, W1 0.138 vs a 0.065 baseline. The most *sensitive* to OOS | Mix shift (W3 0.063 = baseline) |

**No single detector catches everything.** The two most useful in production are complementary:

- **Novelty rate**: interpretable ("29.8% of this window looks unlike anything we handle"), cheap, and it reuses the router's centroids.
- **MMD** (or the domain classifier): a calibrated p-value for *any* change, including the mix shifts that novelty can't see.

A mix shift (W3) isn't necessarily bad: traffic concentrating on 40 intents may be a marketing campaign. It still changes per-intent error rates and thresholds, so it deserves a look.

### 1.7 MMD: a kernel two-sample test with a permutation p-value `[MUST-KNOW: Core AI Engineer Edge]`

The maximum mean discrepancy between distributions P and Q under a kernel k (Gretton et al., 2012):

```text
MMD²(P, Q) = E[k(x, x′)] + E[k(y, y′)] − 2 E[k(x, y)]        x, x′ ~ P;  y, y′ ~ Q
```

With a characteristic kernel such as the RBF, `exp(−‖a − b‖²/h)`, MMD² = 0 iff P = Q. The estimate uses kernel-matrix block means. For the bandwidth h, the **median heuristic** (median pairwise squared distance) is the standard default.

**The p-value comes from permutations, not a formula.** Pool both samples, shuffle the labels 200 times, recompute MMD² each time, and the p-value is the fraction of shuffles at least as extreme as the observed value. It needs no distributional assumption, and it's valid for 384-d embeddings. The minimum achievable p is 1/(n_perm + 1) = 0.005 with 200 permutations, which is why every detected window shows exactly 0.005. Use more permutations if you need finer p-values. Cost is O((n + m)²) kernel entries: subsample to ~500 per window, as the listing does.

### 1.8 Classifier two-sample tests (the domain classifier) `[MUST-KNOW: Core AI Engineer Edge]`

Train a classifier to tell reference rows from window rows, with cross-validation. If the distributions are identical, held-out AUC ≈ 0.5 (W0: 0.491). The further above 0.5, the more distinguishable they are. Lopez-Paz & Oquab (2017) formalize this as a two-sample test. It's attractive in production because:

- it scales to large samples better than kernel MMD;
- its **coefficients or feature importances explain *what* changed**, i.e. which directions or features separate the windows;
- it reuses familiar tooling (a logistic regression).

Its weakness here: a linear classifier struggles when the new content is diffuse and spread across many directions (W2's OOS chatter: AUC 0.541), even though MMD flags it.

### 1.9 False alarms: the null, correlated windows, multiple testing `[MUST-KNOW: Core AI Engineer Edge]`

The first version of this listing drew the reference **with replacement** (2,400 points sampled as 3,000). The duplicates made the "same-distribution" window look different to both MMD and the cross-validated domain classifier (duplicated rows end up on both sides of the CV folds), and the null fired 10 of 20 times. After fixing that, the final listing runs the null experiment two ways:

```text
false-alarm check under the null, 20 trials at alpha = 0.05:
  one fixed reference, 20 overlapping windows: 7 of 20 fire (trials share one draw -> correlated)
  fresh split per trial:                        1 of 20 fire (expected about 1)
```

The test is calibrated: 1 of 20 with independent splits. But **production uses one fixed reference**, and every weekly window is compared to it. If that one reference sample happens to differ slightly from the population, every comparison inherits the same bias, and the alarms *cluster*: 7 of 20 here. Production rules:

1. Use a **large reference** (all of a stable period, not a small sample), and refresh it deliberately (versioned), not silently.
2. **Alert on effect size and persistence**, not on a single p < 0.05. For example: novelty rate above baseline + 5 points for 3 consecutive windows, or MMD significant in 3 of the last 4.
3. With many monitored slices, **correct for multiple testing** (Bonferroni, or control the false-discovery rate). Twenty slices at α = 0.05 give one false alarm per run even when nothing changed.
4. Calibrate every detector's false-alarm rate on **known-stable periods** (re-split as in the listing) before trusting its alerts.

### 1.10 Manifold-learning theory `[SKIP: Academic/Research Only]`

Isomap (geodesic distances), LLE (local linear reconstructions), Laplacian eigenmaps and the topological foundations of UMAP explain *why* local-structure methods behave as measured. None changes the production rule: decide in the full space, visualize in 2-D.

---

## 2. Where It Beats an LLM in Production

| Need | Statistical approach | "Ask an LLM" approach |
|---|---|---|
| "Has user traffic changed this week?" | Novelty rate + MMD permutation test in 384-d: a calibrated yes/no with an effect size | Ask an LLM to compare two samples of 1,000 queries: unquantified, unrepeatable |
| "What changed?" | The domain classifier's top-weighted directions → nearest example queries; HDBSCAN on the novel slice (03.1) | Useful *after* the statistics, to name the clusters the tests found |
| Exploring a corpus or a failure set | t-SNE/UMAP map for browsing, with clicks to read examples | Reading thousands of examples by hand |

The division of labour holds again: statistics decide *whether* and *where*, maps help humans *look*, and an LLM *names* what was found.

---

## 3. Production Code Blueprint

### 3.1 Measuring what 2-D maps preserve

```python
"""tsne_umap_neighborhood_preservation.py - what PCA, t-SNE and UMAP 2-D maps of embeddings preserve, and what they invent.

3,000 CLINC utterances from 30 intents (MiniLM, 384-d) mapped to 2-D.
  1. Local structure: trustworthiness and 10-NN preservation.
  2. Global structure: Spearman correlation of pairwise distances (384-d vs 2-D) and of intent-centroid distances.
  3. Intent separation in the map (silhouette) vs in the original space.
  4. Run-to-run stability: two seeds of the same method.
  5. An ASCII scatter of six intents, to see the picture the metrics describe.
"""
import os
import time
import warnings

import numpy as np
from scipy.stats import spearmanr
from sklearn.decomposition import PCA
from sklearn.manifold import TSNE, trustworthiness
from sklearn.metrics import silhouette_score

warnings.filterwarnings("ignore")
import umap  # noqa: E402

Z = np.load(os.path.join(os.environ["KB_DATA"], "clinc_minilm.npz"))
rng = np.random.default_rng(101)
intents = rng.choice(150, 30, replace=False)
m = np.isin(Z["y_train"], intents)
X, y = Z["X_train"][m].astype(np.float64), Z["y_train"][m]
print(f"{len(X)} utterances, {len(intents)} intents, 384-d")


def knn_sets(A, k=10):
    d = ((A ** 2).sum(1)[:, None] + (A ** 2).sum(1)[None] - 2 * A @ A.T)
    np.fill_diagonal(d, np.inf)
    return np.argsort(d, axis=1)[:, :k]


hi_nn = knn_sets(X)
sub = rng.choice(len(X), 400, replace=False)
hi_d = np.sqrt(np.maximum(2 - 2 * X[sub] @ X[sub].T, 0))[np.triu_indices(400, 1)]
cent_hi = np.stack([X[y == c].mean(0) for c in intents])


def evaluate(E):
    lo_nn = knn_sets(E)
    pres = np.mean([len(set(a) & set(b)) / 10 for a, b in zip(hi_nn, lo_nn)])
    lo_d = np.sqrt(((E[sub][:, None] - E[sub][None]) ** 2).sum(-1))[np.triu_indices(400, 1)]
    cent_lo = np.stack([E[y == c].mean(0) for c in intents])
    cd_hi = np.linalg.norm(cent_hi[:, None] - cent_hi[None], axis=-1)[np.triu_indices(30, 1)]
    cd_lo = np.linalg.norm(cent_lo[:, None] - cent_lo[None], axis=-1)[np.triu_indices(30, 1)]
    return (trustworthiness(X, E, n_neighbors=10), pres, spearmanr(hi_d, lo_d).correlation,
            spearmanr(cd_hi, cd_lo).correlation, silhouette_score(E, y))


methods = {
    "PCA-2": lambda s: PCA(2, random_state=s).fit_transform(X),
    "t-SNE perplexity 5": lambda s: TSNE(2, perplexity=5, init="pca", random_state=s).fit_transform(X),
    "t-SNE perplexity 30": lambda s: TSNE(2, perplexity=30, init="pca", random_state=s).fit_transform(X),
    "t-SNE perplexity 100": lambda s: TSNE(2, perplexity=100, init="pca", random_state=s).fit_transform(X),
    "UMAP n_neighbors 15": lambda s: umap.UMAP(n_neighbors=15, min_dist=0.1, random_state=s, n_jobs=1).fit_transform(X),
    "UMAP n_neighbors 50": lambda s: umap.UMAP(n_neighbors=50, min_dist=0.1, random_state=s, n_jobs=1).fit_transform(X),
}
print(f"\n{'method':22s} {'trust@10':>8} {'10-NN kept':>10} {'pairwise rho':>12} {'centroid rho':>12} {'silhouette':>10} {'s':>6}")
print(f"{'(original 384-d)':22s} {1.0:>8.3f} {1.0:>10.3f} {1.0:>12.3f} {1.0:>12.3f} {silhouette_score(X, y, metric='cosine'):>10.3f} {'-':>6}")
emb, res = {}, {}
for name, f in methods.items():
    t0 = time.perf_counter()
    E = f(0)
    dt = time.perf_counter() - t0
    emb[name] = E
    res[name] = evaluate(E)
    tr, pres, rho, crho, sil = res[name]
    print(f"{name:22s} {tr:>8.3f} {pres:>10.3f} {rho:>12.3f} {crho:>12.3f} {sil:>10.3f} {dt:>6.1f}")
assert res["t-SNE perplexity 30"][1] > res["PCA-2"][1] and res["PCA-2"][2] > res["t-SNE perplexity 30"][2] - 0.3

print("\n== 4. run-to-run stability (seed 0 vs seed 1) ==")
for name in ("t-SNE perplexity 30", "UMAP n_neighbors 15"):
    E1 = methods[name](1)
    a, b = knn_sets(emb[name]), knn_sets(E1)
    c0 = np.stack([emb[name][y == c].mean(0) for c in intents])
    c1 = np.stack([E1[y == c].mean(0) for c in intents])
    d0 = np.linalg.norm(c0[:, None] - c0[None], axis=-1)[np.triu_indices(30, 1)]
    d1 = np.linalg.norm(c1[:, None] - c1[None], axis=-1)[np.triu_indices(30, 1)]
    print(f"{name:22s} 10-NN overlap between seeds {np.mean([len(set(p) & set(q)) / 10 for p, q in zip(a, b)]):.3f}; "
          f"intent-centroid distance rho between seeds {spearmanr(d0, d1).correlation:.3f}")

print("\n== 5. UMAP n_neighbors 15, six intents (letters a-f) ==")
E = emb["UMAP n_neighbors 15"]
six = intents[:6]
W, H = 60, 18
lo, hi = E.min(0), E.max(0)
grid = [[" "] * W for _ in range(H)]
for letter, c in zip("abcdef", six):
    for p in E[y == c][::3]:
        gx = int((p[0] - lo[0]) / (hi[0] - lo[0]) * (W - 1))
        gy = int((hi[1] - p[1]) / (hi[1] - lo[1]) * (H - 1))
        grid[gy][gx] = letter
print("\n".join(("  |" + "".join(r)).rstrip() for r in grid if "".join(r).strip()))
print("\nALL ASSERTIONS PASSED")
```

Output (verified, except the `s` seconds column, which is one measured run):

```text
3000 utterances, 30 intents, 384-d

method                 trust@10 10-NN kept pairwise rho centroid rho silhouette      s
(original 384-d)          1.000      1.000        1.000        1.000      0.335      -
PCA-2                     0.789      0.099        0.431        0.588     -0.018    0.0
t-SNE perplexity 5        0.991      0.574        0.429        0.569      0.374    9.7
t-SNE perplexity 30       0.995      0.616        0.406        0.588      0.649   11.4
t-SNE perplexity 100      0.995      0.591        0.454        0.560      0.626   19.6
UMAP n_neighbors 15       0.992      0.501        0.324        0.601      0.739   21.9
UMAP n_neighbors 50       0.991      0.399        0.333        0.679      0.789   16.5

== 4. run-to-run stability (seed 0 vs seed 1) ==
t-SNE perplexity 30    10-NN overlap between seeds 0.963; intent-centroid distance rho between seeds 0.999
UMAP n_neighbors 15    10-NN overlap between seeds 0.628; intent-centroid distance rho between seeds 0.883

== 5. UMAP n_neighbors 15, six intents (letters a-f) ==
  |                bb
  |            bb                  a
  |                                aa
  |                              cccc
  |                  f
  |                     fffff
  |                                             d
  |                                           d
  |                                         ddd   deee

ALL ASSERTIONS PASSED
```

How to read the ASCII map: six intents, each a letter. They appear as tight, well-separated islands, which is the "exaggerated separation" of §1.4 in picture form. In 384-d these intents' silhouette is a third of what the map suggests.

### 3.2 Drift detection with calibrated false alarms

```python
"""embedding_drift_detectors.py - detecting embedding drift in production query traffic, with false-alarm control.

Reference: 1,800 queries from 120 known intents (one half of CLINC's test pool). Each window: 600 queries from the
other half, sampled WITHOUT replacement (duplicates leak into kernel and classifier tests and fake a drift):
  W0 same distribution | W1 +10% out-of-scope | W2 +30% out-of-scope
  W3 traffic concentrated on 40 intents (a mix shift, nothing new) | W4 30% from 30 never-seen intents
Detectors (computed in the full 384-d space, never on a 2-D picture):
  mean shift | PCA-50 reconstruction error | MMD^2 (RBF) with a permutation p-value
  domain-classifier AUC (cross-validated) | novelty rate (max cosine to known centroids below the 5% quantile)
"""
import os

import numpy as np
from sklearn.decomposition import PCA
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import roc_auc_score
from sklearn.model_selection import cross_val_predict

Z = np.load(os.path.join(os.environ["KB_DATA"], "clinc_minilm.npz"))
rng = np.random.default_rng(103)
unseen = rng.choice(150, 30, replace=False)
known = np.setdiff1d(np.arange(150), unseen)
Xt, yt = Z["X_test"].astype(np.float64), Z["y_test"]
pool_known = rng.permutation(np.flatnonzero(np.isin(yt, known)))
ref_idx, win_idx = pool_known[:1800], pool_known[1800:]
REF = Xt[ref_idx]
te_unseen = np.flatnonzero(np.isin(yt, unseen))
OOS = Z["X_oos_test"].astype(np.float64)
NW = 600


def window(kind, r):
    if kind.startswith("W0"):
        return Xt[r.choice(win_idx, NW, replace=False)]
    if kind.startswith("W1"):
        return np.vstack([Xt[r.choice(win_idx, 540, replace=False)], OOS[r.choice(len(OOS), 60, replace=False)]])
    if kind.startswith("W2"):
        return np.vstack([Xt[r.choice(win_idx, 420, replace=False)], OOS[r.choice(len(OOS), 180, replace=False)]])
    if kind.startswith("W3"):
        few = r.choice(known, 40, replace=False)
        return Xt[win_idx[np.isin(yt[win_idx], few)]][:NW]
    return np.vstack([Xt[r.choice(win_idx, 420, replace=False)], Xt[r.choice(te_unseen, 180, replace=False)]])


pca = PCA(50, random_state=0).fit(REF)
rec = lambda A: np.linalg.norm(A - pca.inverse_transform(pca.transform(A)), axis=1)
ref_rec = rec(REF).mean()
cents = np.stack([Z["X_train"][Z["y_train"] == c].mean(0) for c in known])   # router centroids, from TRAIN
cents /= np.linalg.norm(cents, axis=1, keepdims=True)
nov_thr = np.quantile((REF @ cents.T).max(1), 0.05)


def mmd_test(A, B, r, n_perm=200):
    A, B = A[r.permutation(len(A))[:500]], B[r.permutation(len(B))[:500]]
    XY = np.vstack([A, B])
    d2 = np.maximum((XY ** 2).sum(1)[:, None] + (XY ** 2).sum(1)[None] - 2 * XY @ XY.T, 0)
    Kx = np.exp(-d2 / np.median(d2[d2 > 0]))                      # median-heuristic bandwidth
    n = len(A)

    def stat(idx):
        a, b = idx[:n], idx[n:]
        return Kx[np.ix_(a, a)].mean() + Kx[np.ix_(b, b)].mean() - 2 * Kx[np.ix_(a, b)].mean()

    s0 = stat(np.arange(2 * n))
    perms = np.array([stat(r.permutation(2 * n)) for _ in range(n_perm)])
    return s0, (1 + np.sum(perms >= s0)) / (n_perm + 1)


def domain_auc(A, B):
    Xd = np.vstack([A, B])
    yd = np.r_[np.zeros(len(A)), np.ones(len(B))]
    p = cross_val_predict(LogisticRegression(C=1.0, max_iter=2000), Xd, yd, cv=5, method="predict_proba")[:, 1]
    return roc_auc_score(yd, p)


kinds = ["W0 same distribution", "W1 +10% OOS", "W2 +30% OOS", "W3 mix shift (40 intents)", "W4 30% unseen intents"]
print(f"{'window':28s} {'mean shift':>10} {'recon err x':>11} {'MMD^2':>8} {'p-value':>7} {'domain AUC':>10} {'novelty':>8}")
out = {}
for kind in kinds:
    r = np.random.default_rng(7)
    W = window(kind, r)
    mref, mw = REF.mean(0), W.mean(0)
    shift = 1 - mref @ mw / (np.linalg.norm(mref) * np.linalg.norm(mw))
    mmd, p = mmd_test(REF, W, r)
    auc = domain_auc(REF[r.permutation(len(REF))[:NW]], W)
    nov = np.mean((W @ cents.T).max(1) < nov_thr)
    out[kind] = (p, auc, nov)
    print(f"{kind:28s} {shift:>10.5f} {rec(W).mean() / ref_rec:>11.3f} {mmd:>8.5f} {p:>7.3f} {auc:>10.3f} {nov:>8.3f}")

print("\nfalse-alarm check under the null, 20 trials at alpha = 0.05:")
same_ref = sum(mmd_test(REF, window(kinds[0], np.random.default_rng(1000 + s)), np.random.default_rng(s), n_perm=100)[1] < 0.05
               for s in range(20))
fires = 0
for s in range(20):                                               # a fresh reference/window split per trial
    r = np.random.default_rng(2000 + s)
    perm = r.permutation(pool_known)
    fires += mmd_test(Xt[perm[:1800]], Xt[r.choice(perm[1800:], NW, replace=False)], r, n_perm=100)[1] < 0.05
print(f"  one fixed reference, 20 overlapping windows: {same_ref} of 20 fire (trials share one draw -> correlated)")
print(f"  fresh split per trial:                        {fires} of 20 fire (expected about 1)")
assert out[kinds[0]][0] > 0.05 and out[kinds[2]][0] < 0.01 and fires <= 4
assert out[kinds[4]][2] > out[kinds[0]][2] + 0.1 and out[kinds[3]][1] > out[kinds[0]][1] + 0.1
print("\nALL ASSERTIONS PASSED")
```

Output (verified):

```text
window                       mean shift recon err x    MMD^2 p-value domain AUC  novelty
W0 same distribution            0.01326       1.030  0.00242   0.562      0.491    0.065
W1 +10% OOS                     0.01344       1.075  0.00250   0.448      0.487    0.138
W2 +30% OOS                     0.02345       1.134  0.00377   0.005      0.541    0.298
W3 mix shift (40 intents)       0.06415       1.003  0.00864   0.005      0.758    0.063
W4 30% unseen intents           0.02035       1.083  0.00351   0.005      0.516    0.168

false-alarm check under the null, 20 trials at alpha = 0.05:
  one fixed reference, 20 overlapping windows: 7 of 20 fire (trials share one draw -> correlated)
  fresh split per trial:                        1 of 20 fire (expected about 1)

ALL ASSERTIONS PASSED
```

---

## 4. The Andrew Ng Lens: Data Mismatch Is a Measurable Quantity

### 4.1 Train–dev–production mismatch, quantified

Ng's bias/variance analysis separates a **data-mismatch** term: performance lost because production data differs from training data. Drift detection is how you *measure* that term continuously instead of discovering it from complaints. The novelty rate is a direct proxy: the share of production traffic that looks unlike anything trained on (W4: 16.8% vs a 6.5% baseline). It translates into "this fraction of traffic is at risk".

### 4.2 Drift alerts start error analysis, they don't replace it

A drift alarm is the *trigger*. The next steps follow Ng's error-analysis loop:

1. Pull the window's novel queries (or the domain classifier's most confident "window" rows).
2. Cluster them (03.1) and read 20 from each cluster.
3. Tag them: a new intent, a new phrasing of a known intent, a new language, bot traffic, a logging bug.
4. Count the tags, and only then decide whether to collect labels, retrain, or fix an upstream pipeline.

### 4.3 Evaluation-driven monitoring

Treat each detector like a model with its own eval: measure its false-alarm rate on stable periods (re-split as in §1.9) and its detection rate on *injected* drift (mix in known OOS at 5%, 10%, 30%, like W1–W2). A detector that can't see 10% injected OOS in a window of 600 (MMD, p = 0.448) needs bigger windows or a more sensitive statistic (the novelty rate rose from 0.065 to 0.138). Knowing that is the point of the eval.

---

## 5. Failure Modes

| # | Symptom | Signature | Root cause | Fix | Prevention |
|---|---|---|---|---|---|
| F1 | "The clusters are clearly separated, so the router should be easy" | UMAP silhouette 0.74 vs 0.335 in 384-d | Maps exaggerate separation (§1.4) | Measure confusion in the full space (02.3) | Never cite 2-D separation as evidence |
| F2 | "Cluster A moved far from cluster B this week" | Separately fitted UMAP maps | Seed-dependent layout (10-NN overlap 0.63 between seeds) | Fit once, `transform()` new data, or use a fixed PCA | Comparisons over time use fixed projections and tests |
| F3 | A same-distribution window flags drift | Reference sampled with replacement (duplicates) | Duplicates leak into kernel and CV classifier tests | Sample without replacement from disjoint pools | A null-calibration test for each detector |
| F4 | Drift alarms fire week after week, then stop when the reference is refreshed | One fixed reference | Correlated comparisons (7/20 vs 1/20) | Large, versioned references; persistence rules | Calibrate on stable periods with re-splits |
| F5 | 20 monitored slices → constant alerts | Uncorrected multiple testing | α per test × number of slices | Bonferroni / FDR control; effect-size thresholds | A monitoring design review |
| F6 | Drift missed until users complain | Only mean-shift monitoring | New content averages out (W1 mean shift ≈ W0) | Add novelty rate and MMD | Detection eval with injected drift |
| F7 | Mix shift breaks per-intent thresholds unnoticed | Novelty rate flat, but traffic concentrated | Novelty can't see mix shifts (W3) | Domain classifier / MMD; per-intent volume monitors | Detector portfolio covers mix and novelty |
| F8 | MMD test too slow on a full day of traffic | O(n²) kernel matrices | No subsampling | Subsample ~500 per window; or linear-time MMD; or a domain classifier | Detector cost budgeted per window |
| F9 | UMAP crashes on Windows with FileNotFoundError in numba's cache | Cache path > MAX_PATH | Long temp directory | Set `NUMBA_CACHE_DIR` to a short (8.3) path | Short cache path in the job config |

---

## 6. Bar-Raiser Q&A Chains

<details><summary><b>Q1 · "Our UMAP plot shows a new island of points this week. Do we have drift?"</b></summary>

**Initial Prompt.** A data scientist shares two UMAP plots, last week vs this week.

**L5 Answer.** "Yes, a new island means new content."

**Why L5 Fails in Production.** Separately fitted UMAP layouts differ by seed alone (only 63% of 10-NN neighbourhoods shared between two seeds in our run), and maps exaggerate separation. The island might be a layout artifact, or a small, harmless shift that looks dramatic.

**L7 Principal Defense.** "Decide in the full space. Run a novelty rate (the share of queries far from every known intent centroid) and an MMD permutation test against a fixed reference. In our CLINC simulation, 30% new-intent traffic gave novelty 0.168 vs a 0.065 baseline and MMD p = 0.005. If either flags, pull the novel queries, cluster them with HDBSCAN, and read them. Use the map afterwards, fitted once with `transform()` for the new week, to *show* the finding, never to *establish* it."

**Bar-Raiser Follow-ups.**
- *"Why does t-SNE look stable across seeds then?"* scikit-learn's PCA initialization dominates (10-NN overlap 0.963 between seeds), but distances between clusters are still distorted (pairwise ρ 0.41). Stability doesn't make it accurate.

</details>

<details><summary><b>Q2 · "Explain what t-SNE optimizes, and why cluster sizes and gaps in t-SNE are meaningless."</b></summary>

**Initial Prompt.** A technical deep-dive.

**L5 Answer.** "t-SNE keeps similar points close together in 2-D."

**Why L5 Fails in Production.** It's true, but it doesn't explain the specific distortions people misread.

**L7 Principal Defense.** "It converts high-d distances into neighbour probabilities, a Gaussian per point with σᵢ chosen so the perplexity (2^entropy) hits a target, effectively a fixed number of neighbours. Low-d similarities use a heavy-tailed Student-t, and it minimizes KL(P‖Q). Per-point σᵢ equalizes density, so dense and sparse clusters render the same size: sizes are meaningless. The heavy tail lets moderately distant points spread far apart, solving crowding but inflating gaps: our intent silhouette went from 0.335 in 384-d to 0.649 on the map. Forward KL punishes separating true neighbours but not merging non-neighbours, so local structure is reliable (trustworthiness 0.995) and global distances aren't (Spearman 0.41)."

**Bar-Raiser Follow-ups.**
- *"Perplexity choice?"* 5–100. Low perplexity fragments clusters, high perplexity merges them. We saw 10-NN preservation peak at 30 (0.616). Run a few and only trust structure that persists across them.

</details>

<details><summary><b>Q3 · "Design embedding-drift monitoring for our RAG and routing system."</b></summary>

**Initial Prompt.** Weekly, per tenant, with a small on-call team.

**L5 Answer.** "Track the average embedding each week and alert if it moves."

**Why L5 Fails in Production.** Mean shift misses new content that averages out. In our simulation, 10% out-of-scope traffic moved the mean by about as much as noise (0.01344 vs 0.01326).

**L7 Principal Defense.** "Use a portfolio, each detector calibrated on stable periods. (1) Novelty rate against the router's known-intent centroids: interpretable and the most sensitive to new content (0.065 → 0.138 at 10% OOS, 0.298 at 30%). (2) MMD with a permutation p-value, or a domain classifier for large windows: they catch mix shifts novelty can't see (W3: domain AUC 0.758, MMD p = 0.005). (3) PCA reconstruction error against the reference basis: cheap, catches off-subspace content. Use a large versioned reference, alert on persistence (3 consecutive windows) and effect size, and apply FDR control across tenants. Every alert opens an error-analysis ticket with clustered examples attached."

**Bar-Raiser Follow-ups.**
- *"Window size?"* Large enough that the detection eval catches injected drift at the level you care about. Our 600-query windows didn't catch 10% OOS with MMD (p = 0.448), but the novelty rate did.

</details>

<details><summary><b>Q4 · "Your drift detector fires on a window that should be identical to the reference. Debug it."</b></summary>

**Initial Prompt.** The null fires 50% of the time.

**L5 Answer.** "The test is too sensitive. Raise α to 0.01."

**Why L5 Fails in Production.** It treats a broken experiment as a threshold problem. In our first build, the cause was duplicates from sampling the reference with replacement: they leak into kernel statistics and across cross-validation folds of the domain classifier.

**L7 Principal Defense.** "Check the sampling first: disjoint pools, without replacement, no shared rows between the reference and the window. Then calibrate the null properly. With a fresh reference/window split per trial, our MMD test fired 1 of 20 at α = 0.05, as designed. Then explain the production subtlety: with *one fixed* reference, comparisons are correlated, and it fired 7 of 20 because a single reference draw biases every comparison. The fix is a large reference, persistence rules and effect-size thresholds, not a smaller α."

**Bar-Raiser Follow-ups.**
- *"Why can duplicates fool a cross-validated classifier?"* The same row appears in both a training fold and a test fold, so the classifier 'recognizes' it. That's leakage, the same mechanism as near-duplicate leakage in model evaluation.

</details>

<details><summary><b>Q5 · "MMD or a domain classifier for drift detection?"</b></summary>

**Initial Prompt.** A design choice for a monitoring service.

**L5 Answer.** "The domain classifier. It's simpler."

**Why L5 Fails in Production.** Simpler, yes, but our measurement shows they detect *different* shifts, so the choice depends on which shifts matter.

**L7 Principal Defense.** "MMD with an RBF kernel and median bandwidth is a calibrated nonparametric test that caught both diffuse new content (W2: p = 0.005) and mix shift (W3). It costs O(n²), so subsample. A linear domain classifier scales better and *explains* what changed through its weights, but it missed diffuse OOS chatter (AUC 0.541 at 30% OOS) while catching the mix shift (0.758). In production: novelty rate for new content, a domain classifier for scale and explanation, and MMD on subsamples as the calibrated tie-breaker."

**Bar-Raiser Follow-ups.**
- *"Nonlinear domain classifier?"* A GBDT or MLP domain classifier would likely catch more, but test it for calibration under the null first. Flexible classifiers find spurious differences in small windows.

</details>

<details><summary><b>Q6 · "Can we just compute drift on the 2-D UMAP coordinates? It's cheaper."</b></summary>

**Initial Prompt.** An engineer proposes running KS tests on UMAP x and y.

**L5 Answer.** "Yes, two 1-D KS tests are fast and easy."

**Why L5 Fails in Production.** UMAP's 2-D coordinates are a stochastic, nonlinear compression that keeps only local structure (10-NN kept 0.50) and distorts global distances (Spearman 0.32). A shift can disappear in the projection, or appear purely from the projection's randomness.

**L7 Principal Defense.** "Do the statistics in the space the models use. If cost matters, use a *fixed linear* reduction (a PCA basis fitted on the reference, 50 dims) and run the tests there: deterministic, comparable over time, and it keeps most of the variance. Reconstruction error against that basis is itself a detector (W2: 1.134× reference). Keep UMAP for the human-facing view."

**Bar-Raiser Follow-ups.**
- *"PSI on PCA components?"* Workable for a dashboard (Folder 07 covers PSI's binning pitfalls), but it's per-dimension and misses joint changes. Keep a multivariate test too.

</details>

<details><summary><b>Q7 · "UMAP or t-SNE for exploring our corpus?"</b></summary>

**Initial Prompt.** Building an internal embedding explorer.

**L5 Answer.** "UMAP, it's faster and preserves global structure."

**Why L5 Fails in Production.** "Preserves global structure" is weak in our measurement (pairwise ρ 0.32–0.33 for UMAP vs 0.41–0.45 for t-SNE), and UMAP was less stable across seeds.

**L7 Principal Defense.** "UMAP for scale and for `transform()` on new points, which matters for an explorer that ingests data continuously. Use n_neighbors around 50 if inter-cluster layout matters: it gave the best centroid-distance correlation, 0.679. t-SNE (perplexity ~30) when local neighbourhoods matter most (10-NN kept 0.616) and the dataset is static. Either way, show trustworthiness and a 'distances are not to scale' note in the UI, link every point to its text, and compute any metric in the original space."

**Bar-Raiser Follow-ups.**
- *"Pre-reduce with PCA?"* Yes, to ~50 dims before t-SNE/UMAP on large corpora. It's faster and denoises.

</details>

<details><summary><b>Q8 · "How do you tell harmless drift from harmful drift?"</b></summary>

**Initial Prompt.** The detectors fire after a marketing campaign.

**L5 Answer.** "Retrain whenever drift is detected."

**Why L5 Fails in Production.** Retraining on every alarm is expensive and can be wrong: a campaign that concentrates traffic on 40 known intents (W3) is a mix shift with no new content, and the model may handle it perfectly.

**L7 Principal Defense.** "Classify the drift. A novelty-rate increase means new content: the at-risk share of traffic. Cluster it and decide whether to add intents. A mix shift (domain AUC up, novelty flat) means re-checking per-intent metrics and thresholds, especially if escalation rates by intent change. Then check model outcomes on a labelled sample from the window: if accuracy and calibration hold, the drift is harmless and the reference should be refreshed deliberately. Retrain when *outcome* metrics degrade, not when *input* statistics move. Folder 07 automates this loop."

**Bar-Raiser Follow-ups.**
- *"No labels in production?"* Use proxies (escalation rate, user rephrasing, thumbs-down), plus a small weekly labelling budget targeted at the novel and shifted slices.

</details>

---

## 7. Invariants Checklist

- [ ] No decision (drift, separability, cluster distance) is made from 2-D map coordinates. Maps are for browsing, with trustworthiness reported.
- [ ] Maps compared over time use a projection fitted once (PCA, or UMAP `transform`), not separately fitted layouts.
- [ ] Drift monitoring runs in the full (or fixed-PCA-reduced) space, with at least a novelty rate and one multivariate two-sample test.
- [ ] Every detector's false-alarm rate is calibrated on stable periods with independent re-splits, and its detection power on injected drift.
- [ ] References are large and versioned, and windows are sampled without replacement from disjoint pools.
- [ ] Alerts require effect size and persistence, with multiple-testing control across slices.
- [ ] Every alert links to clustered example queries for error analysis.
- [ ] numba-based tools on Windows use a short cache path.

---

## 8. References

1. L. van der Maaten, G. Hinton, *Visualizing Data using t-SNE*, JMLR 9, 2008. https://www.jmlr.org/papers/v9/vandermaaten08a.html
2. L. McInnes, J. Healy, J. Melville, *UMAP: Uniform Manifold Approximation and Projection for Dimension Reduction*, 2018. https://arxiv.org/abs/1802.03426
3. M. Wattenberg, F. Viégas, I. Johnson, *How to Use t-SNE Effectively*, Distill, 2016. https://distill.pub/2016/misread-tsne/
4. A. Gretton et al., *A Kernel Two-Sample Test*, JMLR 13, 2012. https://www.jmlr.org/papers/v13/gretton12a.html
5. D. Lopez-Paz, M. Oquab, *Revisiting Classifier Two-Sample Tests*, ICLR 2017. https://arxiv.org/abs/1610.06545
6. S. Rabanser, S. Günnemann, Z. Lipton, *Failing Loudly: An Empirical Study of Methods for Detecting Dataset Shift*, NeurIPS 2019. https://arxiv.org/abs/1810.11953
7. J. Venna, S. Kaski, *Neighborhood Preservation in Nonlinear Projection Methods*, ICANN 2001 (trustworthiness).
8. scikit-learn, `sklearn.manifold.TSNE` and `trustworthiness`. https://scikit-learn.org/stable/modules/manifold.html
9. umap-learn documentation (parameters, `transform`). https://umap-learn.readthedocs.io/
10. Y. Benjamini, Y. Hochberg, *Controlling the False Discovery Rate*, JRSS-B 57(1), 1995. DOI 10.1111/j.2517-6161.1995.tb02031.x.
