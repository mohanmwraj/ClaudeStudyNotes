# 03.3 · Anomaly Detection: Isolation Forests & Mahalanobis Distance for Out-of-Distribution Queries

> **Folder 03 · Unsupervised Learning, Clustering & Anomaly Detection in AI Systems**
> **Measured on:** scikit-learn 1.9.1 (`LedoitWolf`, `OAS`, `IsolationForest`, `LocalOutlierFactor`), SciPy 1.18.1, NumPy 2.5.4, CPython 3.14.5, Intel i5-11260H (one BLAS thread), Windows 11.
> **Real data:** CLINC150 in-scope test (4,500) vs out-of-scope test (1,000) queries, MiniLM embeddings. Detectors are fitted on in-scope training data only.
> **Design sources:** Mahalanobis (1936), Ledoit & Wolf (2004), Lee et al. (NeurIPS 2018), Ren et al. (2021), Sun et al. (ICML 2022), Liu, Ting & Zhou (Isolation Forest, ICDM 2008), Breunig et al. (LOF, SIGMOD 2000), Hendrycks & Gimpel (2017), Liang et al. (ODIN, ICLR 2018). Full list in §8.

---

## 0. Orientation: The Gate in Front of Every Model

Every model in an AI system is reliable only on data like its training data. An **out-of-distribution (OOD) gate** decides, per request, whether the router, classifier or cache should be trusted at all. When it says no, the request escalates to an LLM, a human, or a polite refusal. This file measures eight gates on real out-of-scope traffic:

```text
detector                    AUROC  FPR@95%TPR  us/query (batch 256)
max softmax prob (LR)      0.9618       0.190                   5.2
max cosine to centroid     0.9656       0.173                   4.3
kNN cosine, k=1            0.9625       0.205                 523.2
kNN cosine, k=10           0.9564       0.200                 530.3
Mahalanobis (tied, LW)     0.9463       0.285                  17.7
relative Mahalanobis       0.9724       0.116                  19.1
Isolation Forest           0.7055       0.818                  83.6
LOF (novelty)              0.9378       0.364                 345.4
```

Three lessons:

1. **Relative Mahalanobis wins**: it lets through 11.6% of OOS at 95% in-scope recall, vs 17.3–28.5% for the next-best scores, at ~19 µs per query.
2. **Plain Mahalanobis is *worse* than a cosine to centroids.** The "relative" correction is what makes it good (§1.4).
3. **Isolation Forest, the default "anomaly detector" in many toolkits, nearly fails** (AUROC 0.706) on text embeddings. §1.6 shows precisely why.

### The backend-engineer bridge

| You already know | OOD equivalent |
|---|---|
| Input validation / schema checks before business logic | **OOD gate before the model** |
| Z-score alerts on a single metric | **Per-coordinate outlier checks**, which miss *correlation* anomalies (§1.6) |
| Normalizing metrics by their covariance (whitening) in anomaly detection | **Mahalanobis distance** |
| Baseline-relative alerting ("vs the global norm") | **Relative Mahalanobis**: class fit minus background fit |

### Tier map

| Subtopic | Tier |
|---|---|
| 1.1 What "OOD" means for an AI system | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.2 Mahalanobis distance: whitening and the χ² law | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.3 Covariance in high dimensions: rank, conditioning, shrinkage | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.4 Class-conditional and relative Mahalanobis | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.5 kNN distance and softmax-based scores (and temperature) | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.6 Isolation Forest: mechanics, strengths, and the correlation blind spot | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.7 Local Outlier Factor | `[GOOD-TO-KNOW: Architectural Literacy]` |
| 1.8 Thresholds: empirical quantiles, not χ² tables | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.9 Latency and memory of each gate | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.10 Extreme-value theory, conformal OOD guarantees | `[SKIP: Academic/Research Only]` |

---

## 1. First-Principles Math & Geometric Intuition

### 1.1 What "OOD" means for an AI system `[MUST-KNOW: Core AI Engineer Edge]`

- **Semantic shift (new content):** queries about things no class covers. CLINC's out-of-scope set ("a show on broadway", "who has the best record in the nfl") is this kind. It's what an intent router's gate must catch.
- **Covariate shift (same classes, new surface):** the same intents phrased differently, in another language, or from a new channel. A gate may flag these even though the model would cope, so measure model accuracy on flagged traffic before tuning the gate to reject it.
- **Near vs far OOD:** "set a warning for when my bank account starts running low" (a CLINC OOS example) is *near* banking intents. Near-OOD is the hard case, and it's where relative Mahalanobis earns its lead.

An OOD score is a function of x that is high for in-distribution inputs. It's judged by **AUROC** (threshold-free ranking quality) and by **FPR at 95% TPR** (the share of OOS let through when 95% of in-scope traffic passes), which is the operating-point number that matters.

### 1.2 Mahalanobis distance: whitening and the χ² law `[MUST-KNOW: Core AI Engineer Edge]`

```text
D_M(x)² = (x − μ)ᵀ Σ⁻¹ (x − μ)
with Σ = L Lᵀ (Cholesky):   D_M(x)² = ‖L⁻¹(x − μ)‖²
```

The whitening map z = L⁻¹(x − μ) turns the data's covariance into the identity, so **Mahalanobis distance is Euclidean distance in whitened coordinates.** Directions in which the data varies a lot count for little, and directions in which it barely varies count for a lot. The listing checks the identity to 9.95e-14, and the whitened covariance equals I to within 0.015.

```text
      raw space (correlated)                 whitened space (z = L⁻¹(x − μ))
         ╱‾‾‾‾‾‾╲                                ╭─────╮
       ╱   data   ╲    ● a                       │  ●  │   ● a  ← now clearly far
      ╱  ellipse   ╲                             │     │
      ╲            ╱  ● b                        ╰─────╯ ● b   ← now clearly near
        ╲________╱
   a and b are equally far from the centre in Euclidean terms; a breaks the correlation, b doesn't
```

For Gaussian data, D_M² ~ χ²_d, with mean d and variance 2d. In 20-d: mean **20.02**, variance **40.3**, and **1.04%** of points exceed the χ² 99th percentile (expected 1.00%). That's the textbook threshold, and §1.8 shows why it fails on real embeddings.

### 1.3 Covariance in high dimensions: rank, conditioning, shrinkage `[MUST-KNOW: Core AI Engineer Edge]`

Σ⁻¹ is the problem. On CLINC (384-d):

```text
one intent: 100 samples -> covariance rank 99 of 384 (singular)
estimator              condition number shrinkage
empirical (tied)       18119004209037016.0    0.0000
Ledoit-Wolf                       267.8    0.0262
OAS                               305.5    0.0230
```

- **A per-class covariance from 100 samples has rank 99**, so it's singular and has no inverse. That's why Lee et al.'s Mahalanobis OOD detector uses a single **tied** (shared) covariance of the class-centred residuals.
- **Even the tied covariance from 15,000 residuals is numerically singular** (condition number 1.8 × 10¹⁶): some directions of the MiniLM space carry essentially no variance. Inverting it would amplify floating-point noise in those directions by ~10¹⁶.
- **Shrinkage fixes it:** Σ̂ = (1 − α)·S + α·(tr(S)/d)·I, blending the sample covariance with a scaled identity. Ledoit & Wolf (2004) derive the α that minimizes expected squared error in closed form. OAS (Chen et al., 2010) is a refinement for Gaussian data. Here α ≈ 0.026, a *small* blend, but enough to bring the condition number from 10¹⁶ to 268. Always shrink in high dimensions. `LedoitWolf().fit(X)` is one line.

### 1.4 Class-conditional and relative Mahalanobis `[MUST-KNOW: Core AI Engineer Edge]`

**Class-conditional (Lee et al., 2018).** Fit one mean per class and one shared shrunk covariance. Score = −min_c D_M(x; μ_c, Σ)². That is "distance to the nearest class, in whitened units". Computing it efficiently matters: expand the quadratic form as

```text
D_c(x)² = xᵀPx − 2 μ_cᵀ P x + μ_cᵀ P μ_c          (P = Σ⁻¹)
```

That's three matrix products for all classes at once. The first version of this listing looped over 150 classes with a three-operand `einsum`, about 10¹¹ scalar operations. It didn't finish in 10 minutes, and the expanded form runs in milliseconds (17.7 µs per query).

**Why plain Mahalanobis underperformed here (0.946 < 0.966 for cosine).** Whitening amplifies the low-variance directions. In text embeddings, those directions carry little class information and a lot of "generic text" variation, so *every* query (in-scope or not) looks far along them, which drowns the signal.

**Relative Mahalanobis (Ren et al., 2021)** subtracts a background model, one Gaussian fitted to *all* training data regardless of class:

```text
RMD(x) = min_c D_M(x; μ_c, Σ)²  −  D_M(x; μ_0, Σ_0)²
```

The background term removes the part of the distance that any text would have, leaving "how much closer to a specific intent than to text in general". Measured: AUROC **0.9724**, FPR@95% **0.116**, the best of all eight gates, and 59% less leaked OOS than plain Mahalanobis (0.285 → 0.116).

### 1.5 kNN distance and softmax-based scores (and temperature) `[MUST-KNOW: Core AI Engineer Edge]`

- **kNN** (Sun et al., 2022): the score is the cosine to the k-th nearest training embedding. It's non-parametric, with no Gaussian assumption, and competitive here (k = 1: 0.9625). But it scans the whole training set per query (523 µs, brute force), so in production it needs an ANN index (01.1, 03.1).
- **Max cosine to class centroids**: a 1-NN against 150 prototypes. 0.9656 at 4.3 µs is the best cost/quality point among the simple scores. It's the gate 02.3's hybrid router uses.
- **Max softmax probability (MSP)** (Hendrycks & Gimpel, 2017): 0.9618 for the LR head at T = 1. Note what calibration did: 02.3's *temperature-scaled* head (T = 0.62, sharpened for calibration) scored only **0.9451**. Temperature changes how confidence ranks *across* inputs, so the best temperature for calibration isn't the best for OOD detection. ODIN (Liang et al., 2018) actually *raises* T above 1 to improve OOD separation. If you use MSP as a gate, tune its temperature for the gate, separately from the calibration temperature.

### 1.6 Isolation Forest: mechanics, strengths, and the correlation blind spot `[MUST-KNOW: Core AI Engineer Edge]`

**Mechanics** (Liu, Ting & Zhou, 2008):

1. Build trees on random subsamples of ψ = 256 points. Each node picks a random feature and a random split between that feature's min and max, recursing until points are isolated or a depth limit (⌈log₂ψ⌉) is hit.
2. Anomalies are few and different, so they isolate in fewer splits. Their path length h(x) is short.
3. Normalize by c(n), the average path length of an unsuccessful search in a binary search tree:

```text
c(n) = 2·H(n−1) − 2(n−1)/n,   H(i) ≈ ln i + 0.5772     (c(256) = 10.245)
score s(x) = 2^(−E[h(x)] / c(ψ))      s → 1: anomaly;  s ≈ 0.5 or below: normal
```

Our from-scratch implementation ranks points like scikit-learn's (Spearman 0.939 on a 2-D test, AUROC 0.916 vs 0.926).

**The blind spot.** Every split is axis-aligned on *one* feature. An anomaly that's normal in every individual coordinate, but violates the *correlations*, is never isolated faster than a normal point. The listing builds exactly that case in 50-D (data near a 5-D subspace; anomalies with the same per-coordinate spread but independent coordinates):

```text
detector                            AUROC
max |z-score| over coordinates      0.766
Isolation Forest                    0.696
Mahalanobis (Ledoit-Wolf)           1.000
```

Mahalanobis catches all of them (it measures distance from the correlation structure), and Isolation Forest does *worse than a per-coordinate z-score*. Text embeddings are exactly this situation: meaning lives in oblique combinations of coordinates (01.1 §1.1), and an out-of-scope query differs in direction, not in any single coordinate's range. That explains CLINC's 0.706.

**Where Isolation Forest is the right tool:** tabular, individually meaningful features (request rate, payload size, error counts, account age). Anomalies there *are* extreme in some features, it handles mixed scales without normalization, it's fast, and it needs no distributional assumption. Use it for fraud, abuse and infrastructure telemetry, not on embeddings.

### 1.7 Local Outlier Factor `[GOOD-TO-KNOW: Architectural Literacy]`

LOF (Breunig et al., 2000) compares a point's local density (inverse mean reachability distance to its k neighbours) with its neighbours' densities. A ratio well above 1 means the point sits in a sparser region than its neighbours. It adapts to clusters of different densities, which global methods can't. Here it reached 0.938 at 345 µs per query: a neighbour search per query, like kNN, and in high dimensions density ratios are noisy. Use `novelty=True` to score new points (the default mode scores only the training set).

### 1.8 Thresholds: empirical quantiles, not χ² tables `[MUST-KNOW: Core AI Engineer Edge]`

If embeddings were Gaussian, min-class D_M² would follow χ²_384, and the 95th percentile (430.7) would keep 95% of in-scope traffic. On real embeddings:

```text
in-scope test min-class D_M^2: median 365.6 (chi2_384 median 383.3)
threshold meant to keep 95% of in-scope traffic: chi2 430.7 keeps 0.645; empirical validation quantile 756.2 keeps 0.957
```

The χ² threshold would **reject 35.5% of legitimate traffic**, because real embeddings have heavier tails than a Gaussian, and the shrunk covariance isn't the true covariance. The **empirical 95th percentile of the score on in-scope validation data** keeps 95.7% on test. Rule: set every OOD threshold from validation quantiles at production prevalence (02.3 §1.5), never from a parametric table.

### 1.9 Latency and memory of each gate `[MUST-KNOW: Core AI Engineer Edge]`

| Gate | Per-query work | Memory | Measured |
|---|---|---|---|
| Max cosine to centroids | K·d dot products (150 × 384) | K·d floats (230 KB) | 4.3 µs |
| MSP (LR head) | Same as the head, which is already computed | Head weights | 5.2 µs |
| Mahalanobis / relative | d² (x·P) + K·d | P (d², 1.2 MB fp64) + means | 17.7–19.1 µs |
| kNN (brute force) | N·d (15,000 × 384) | All training embeddings | 523–530 µs; use ANN in production |
| LOF | Neighbour search + density lookups | Training set + neighbour stats | 345 µs |
| Isolation Forest | trees × depth comparisons | 200 small trees | 83.6 µs |

Relative Mahalanobis costs about 4× the cosine gate in time and adds a 1.2 MB precision matrix, for the best detection. Both fit any latency budget next to a 2 ms encoder (02.3).

### 1.10 Extreme-value theory, conformal OOD guarantees `[SKIP: Academic/Research Only]`

Extreme-value theory models the tail of the score distribution. Conformal prediction gives finite-sample guarantees on the false-rejection rate when calibration and test data are exchangeable. The empirical-quantile rule of §1.8 is the practical core of the conformal idea, and it's enough for production.

---

## 2. Where It Beats an LLM in Production

| Need | Geometric OOD gate | LLM-based scope check |
|---|---|---|
| Per-request "is this in scope?" | 4–19 µs on the embedding the router already computed; AUROC up to 0.972 | A full LLM call per request, just to decide whether to make another call |
| A calibrated operating point | Empirical-quantile thresholds with a measured FPR (0.116 at 95% TPR) | Prompt-dependent, hard to tune or audit |
| Monitoring | The same score's distribution over time *is* a drift monitor (03.2's novelty rate) | No natural continuous signal |
| Near-OOD with nuance ("is a mortgage question in scope for a credit-card bot?") | Weakest here | Strongest here: escalate the uncertain band to the LLM |

The design that falls out is a **two-threshold gate**: confidently in-scope (route locally), confidently out-of-scope (refuse or redirect without an LLM), and an uncertain band in between that goes to an LLM classifier. Folder 07 tunes the band against cost.

---

## 3. Production Code Blueprint

### 3.1 Mahalanobis from first principles, shrinkage, and thresholds

```python
"""mahalanobis_shrinkage_math.py - Mahalanobis distance from first principles, and why embeddings need shrinkage.

  1. D_M(x)^2 = (x - mu)^T S^-1 (x - mu) equals the squared Euclidean norm after whitening with S = L L^T.
  2. For Gaussian data D_M^2 ~ chi^2_d (mean d, variance 2d), so chi^2 quantiles give thresholds.
  3. Real 384-d embeddings: per-class covariances from 100 samples are singular; the tied covariance is
     ill-conditioned; Ledoit-Wolf / OAS shrinkage fixes the conditioning.
  4. Real embeddings are not Gaussian: the chi^2 threshold misfires, the empirical validation quantile doesn't.
"""
import os

import numpy as np
from scipy import stats
from sklearn.covariance import OAS, EmpiricalCovariance, LedoitWolf

rng = np.random.default_rng(91)

print("== 1-2. synthetic Gaussian, d = 20 ==")
d = 20
A = rng.standard_normal((d, d))
S = A @ A.T / d + 0.1 * np.eye(d)
mu = rng.standard_normal(d)
X = rng.multivariate_normal(mu, S, size=50_000)
L = np.linalg.cholesky(S)
diff = X - mu
dm2 = np.einsum("ij,jk,ik->i", diff, np.linalg.inv(S), diff)
white = np.linalg.solve(L, diff.T).T                              # z = L^-1 (x - mu): identity covariance
print(f"max |D_M^2 - ||L^-1 (x-mu)||^2| = {np.abs(dm2 - (white ** 2).sum(1)).max():.2e}; "
      f"covariance of whitened data: max |cov - I| = {np.abs(np.cov(white.T) - np.eye(d)).max():.3f}")
print(f"D_M^2: mean {dm2.mean():.2f} (chi2 mean {d}), variance {dm2.var():.1f} (chi2 variance {2 * d}); "
      f"P(D_M^2 > chi2_0.99) = {np.mean(dm2 > stats.chi2.ppf(0.99, d)):.4f} (expected 0.0100)")
assert abs(dm2.mean() - d) < 0.2 and abs(np.mean(dm2 > stats.chi2.ppf(0.99, d)) - 0.01) < 0.002

print("\n== 3. CLINC MiniLM embeddings, d = 384 ==")
Z = np.load(os.path.join(os.environ["KB_DATA"], "clinc_minilm.npz"))
Xtr, ytr = Z["X_train"].astype(np.float64), Z["y_train"]
one = Xtr[ytr == 0]
print(f"one intent: {len(one)} samples -> covariance rank {np.linalg.matrix_rank(np.cov(one.T))} of 384 (singular)")
cen = Xtr - np.stack([Xtr[ytr == c].mean(0) for c in range(150)])[ytr]   # class-centred residuals (tied covariance)
print(f"{'estimator':22s} {'condition number':>16} {'shrinkage':>9}")
ests = {}
for name, est in (("empirical (tied)", EmpiricalCovariance()), ("Ledoit-Wolf", LedoitWolf()), ("OAS", OAS())):
    est.fit(cen)
    ests[name] = est
    ev = np.linalg.eigvalsh(est.covariance_)
    shr = getattr(est, "shrinkage_", 0.0)
    print(f"{name:22s} {ev.max() / ev.min():>16.1f} {shr:>9.4f}")
assert np.linalg.cond(ests["Ledoit-Wolf"].covariance_) < np.linalg.cond(ests["empirical (tied)"].covariance_)

print("\n== 4. chi^2 vs empirical thresholds on real (non-Gaussian) embeddings ==")
P = ests["Ledoit-Wolf"].precision_
means = np.stack([Xtr[ytr == c].mean(0) for c in range(150)])


def min_md2(X):
    """min_c (x - mu_c)^T P (x - mu_c), expanded so it is three matrix products instead of a loop over classes."""
    XP = X @ P
    return ((XP * X).sum(1)[:, None] - 2 * XP @ means.T + ((means @ P) * means).sum(1)[None, :]).min(1)


val, test = min_md2(Z["X_val"].astype(np.float64)), min_md2(Z["X_test"].astype(np.float64))
chi_thr = stats.chi2.ppf(0.95, 384)
emp_thr = np.quantile(val, 0.95)
print(f"in-scope test min-class D_M^2: median {np.median(test):.1f} (chi2_384 median {stats.chi2.ppf(0.5, 384):.1f})")
print(f"threshold meant to keep 95% of in-scope traffic: chi2 {chi_thr:.1f} keeps {np.mean(test <= chi_thr):.3f}; "
      f"empirical validation quantile {emp_thr:.1f} keeps {np.mean(test <= emp_thr):.3f}")
assert abs(np.mean(test <= emp_thr) - 0.95) < 0.02
print("\nALL ASSERTIONS PASSED")
```

Output (verified):

```text
== 1-2. synthetic Gaussian, d = 20 ==
max |D_M^2 - ||L^-1 (x-mu)||^2| = 9.95e-14; covariance of whitened data: max |cov - I| = 0.015
D_M^2: mean 20.02 (chi2 mean 20), variance 40.3 (chi2 variance 40); P(D_M^2 > chi2_0.99) = 0.0104 (expected 0.0100)

== 3. CLINC MiniLM embeddings, d = 384 ==
one intent: 100 samples -> covariance rank 99 of 384 (singular)
estimator              condition number shrinkage
empirical (tied)       18119004209037016.0    0.0000
Ledoit-Wolf                       267.8    0.0262
OAS                               305.5    0.0230

== 4. chi^2 vs empirical thresholds on real (non-Gaussian) embeddings ==
in-scope test min-class D_M^2: median 365.6 (chi2_384 median 383.3)
threshold meant to keep 95% of in-scope traffic: chi2 430.7 keeps 0.645; empirical validation quantile 756.2 keeps 0.957

ALL ASSERTIONS PASSED
```

### 3.2 Eight OOD gates on real out-of-scope traffic

```python
"""ood_detectors_clinc.py - eight out-of-distribution detectors for a router, on real CLINC150 OOS queries.

All detectors are fit on the 15,000 in-scope training embeddings only (no OOS data used for fitting).
Score convention: higher = more in-distribution. Metrics on in-scope test (4,500) vs OOS test (1,000).
  max softmax probability (LR) | max cosine to centroids | kNN (k = 1, 10) | class-conditional Mahalanobis
  (tied, Ledoit-Wolf) | relative Mahalanobis | Isolation Forest | Local Outlier Factor
Plus per-query scoring cost, because the gate runs on every request.
"""
import os
import time

import numpy as np
from sklearn.covariance import LedoitWolf
from sklearn.ensemble import IsolationForest
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import roc_auc_score
from sklearn.neighbors import LocalOutlierFactor

Z = np.load(os.path.join(os.environ["KB_DATA"], "clinc_minilm.npz"))
Xtr, ytr = Z["X_train"].astype(np.float64), Z["y_train"]
Xin, Xood = Z["X_test"].astype(np.float64), Z["X_oos_test"].astype(np.float64)
K = 150

means = np.stack([Xtr[ytr == c].mean(0) for c in range(K)])
cents = means / np.linalg.norm(means, axis=1, keepdims=True)
lr = LogisticRegression(C=10, max_iter=3000).fit(Xtr, ytr)
lw = LedoitWolf().fit(Xtr - means[ytr])
P = lw.precision_
g = LedoitWolf().fit(Xtr)                                         # one global Gaussian: the "background"
Pg, mug = g.precision_, g.location_
iso = IsolationForest(n_estimators=200, random_state=0).fit(Xtr)
lof = LocalOutlierFactor(n_neighbors=20, novelty=True).fit(Xtr)


MPM = ((means @ P) * means).sum(1)                                # mu_c^T P mu_c, once


def md2_min(X):
    """min over classes of (x - mu_c)^T P (x - mu_c) = x^T P x - 2 mu_c^T P x + mu_c^T P mu_c (three BLAS calls)."""
    XP = X @ P
    return ((XP * X).sum(1)[:, None] - 2 * XP @ means.T + MPM[None, :]).min(1)


def rel_md(X):
    dg = X - mug
    return md2_min(X) - ((dg @ Pg) * dg).sum(1)


def knn(X, k):
    s = X @ Xtr.T
    return np.sort(s, axis=1)[:, -k]                              # k-th nearest cosine (unit vectors)


detectors = {
    "max softmax prob (LR)": lambda X: lr.predict_proba(X).max(1),
    "max cosine to centroid": lambda X: (X @ cents.T).max(1),
    "kNN cosine, k=1": lambda X: knn(X, 1),
    "kNN cosine, k=10": lambda X: knn(X, 10),
    "Mahalanobis (tied, LW)": lambda X: -md2_min(X),
    "relative Mahalanobis": lambda X: -rel_md(X),
    "Isolation Forest": lambda X: iso.score_samples(X),
    "LOF (novelty)": lambda X: lof.score_samples(X),
}
print(f"{'detector':26s} {'AUROC':>6} {'FPR@95%TPR':>11} {'us/query (batch 256)':>21}")
auc = {}
for name, f in detectors.items():
    si, so = f(Xin), f(Xood)
    auc[name] = roc_auc_score(np.r_[np.ones(len(si)), np.zeros(len(so))], np.r_[si, so])
    thr = np.quantile(si, 0.05)
    t0 = time.perf_counter()
    f(Xin[:256])
    dt = (time.perf_counter() - t0) / 256
    print(f"{name:26s} {auc[name]:>6.4f} {np.mean(so >= thr):>11.3f} {dt * 1e6:>21.1f}")
best = max(auc, key=auc.get)
print(f"\nbest: {best}. Isolation Forest trails every geometric score: its random axis-aligned cuts rarely")
print("isolate a point that is unusual only along oblique directions (see isolation_forest_mechanics.py).")
assert auc["Isolation Forest"] < auc["max cosine to centroid"] and auc[best] > 0.96
print("\nALL ASSERTIONS PASSED")
```

Output (verified, except the µs/query column, which is one measured run):

```text
detector                    AUROC  FPR@95%TPR  us/query (batch 256)
max softmax prob (LR)      0.9618       0.190                   4.3
max cosine to centroid     0.9656       0.173                   2.6
kNN cosine, k=1            0.9625       0.205                 379.5
kNN cosine, k=10           0.9564       0.200                 405.4
Mahalanobis (tied, LW)     0.9463       0.285                   9.4
relative Mahalanobis       0.9724       0.116                  15.3
Isolation Forest           0.7055       0.818                  50.3
LOF (novelty)              0.9378       0.364                 309.1

best: relative Mahalanobis. Isolation Forest trails every geometric score: its random axis-aligned cuts rarely
isolate a point that is unusual only along oblique directions (see isolation_forest_mechanics.py).

ALL ASSERTIONS PASSED
```

How to read it: compare the FPR@95%TPR column, not AUROC. Going from 0.173 (cosine) to 0.116 (relative Mahalanobis) means a third fewer out-of-scope queries misrouted at the same in-scope pass rate.

### 3.3 Isolation Forest from scratch, and its blind spot

```python
"""isolation_forest_mechanics.py - Isolation Forest from scratch, checked against sklearn, and where it breaks.

  1. An isolation tree splits a random feature at a random value until points are alone; anomalies isolate early.
     score s(x) = 2^(-E[h(x)] / c(psi)), c(n) = 2 H(n-1) - 2(n-1)/n  (average unsuccessful-search path in a BST).
  2. Our implementation ranks points like sklearn's (Spearman) and finds the same planted anomalies.
  3. The failure mode that matters for embeddings: anomalies that are normal in every single coordinate but
     violate the CORRELATION structure (off the data's low-dimensional subspace). Axis-aligned isolation misses
     them; Mahalanobis distance does not.
"""
import numpy as np
from scipy.stats import spearmanr
from sklearn.covariance import LedoitWolf
from sklearn.ensemble import IsolationForest
from sklearn.metrics import roc_auc_score

rng = np.random.default_rng(97)
EULER = 0.5772156649


def c(n):
    return 2 * (np.log(n - 1) + EULER) - 2 * (n - 1) / n if n > 2 else (1.0 if n == 2 else 0.0)


def grow(X, depth, limit, r):
    if depth >= limit or len(X) <= 1:
        return ("leaf", len(X))
    j = r.integers(X.shape[1])
    lo, hi = X[:, j].min(), X[:, j].max()
    if lo == hi:
        return ("leaf", len(X))
    t = r.uniform(lo, hi)
    m = X[:, j] < t
    return ("node", j, t, grow(X[m], depth + 1, limit, r), grow(X[~m], depth + 1, limit, r))


def path(tree, x, depth=0):
    if tree[0] == "leaf":
        return depth + c(tree[1])                                  # unresolved subtree: add its expected depth
    _, j, t, left, right = tree
    return path(left if x[j] < t else right, x, depth + 1)


def iforest_scores(X, n_trees=100, psi=256, seed=0):
    r = np.random.default_rng(seed)
    limit = int(np.ceil(np.log2(psi)))
    trees = [grow(X[r.choice(len(X), psi, replace=False)], 0, limit, r) for _ in range(n_trees)]
    h = np.array([[path(t, x) for t in trees] for x in X]).mean(1)
    return 2 ** (-h / c(psi))


print("== 1. c(n): expected path length normalizer ==")
print("  " + "  ".join(f"c({n})={c(n):.3f}" for n in (2, 16, 256, 4096)))

print("\n== 2. 2-D: two blobs + 10 planted anomalies ==")
X = np.vstack([rng.normal([0, 0], 0.5, (300, 2)), rng.normal([4, 4], 0.8, (300, 2)), rng.uniform(-4, 8, (10, 2))])
truth = np.r_[np.zeros(600), np.ones(10)].astype(bool)
ours = iforest_scores(X)
sk = -IsolationForest(n_estimators=100, max_samples=256, random_state=0).fit(X).score_samples(X)
rho = spearmanr(ours, sk).correlation
top_ours, top_sk = set(np.argsort(-ours)[:10]), set(np.argsort(-sk)[:10])
print(f"Spearman(ours, sklearn) = {rho:.3f}; planted anomalies in top-10: ours {len(top_ours & set(range(600, 610)))}, "
      f"sklearn {len(top_sk & set(range(600, 610)))}; AUROC ours {roc_auc_score(truth, ours):.3f}, sklearn {roc_auc_score(truth, sk):.3f}")
assert rho > 0.9 and abs(roc_auc_score(truth, ours) - roc_auc_score(truth, sk)) < 0.05   # uniform "anomalies" can land inside a blob

print("\n== 3. correlation-structure anomalies in 50-D (data lives near a 5-D subspace) ==")
d, k = 50, 5
B = rng.standard_normal((d, k))
normal = rng.standard_normal((4000, k)) @ B.T + 0.3 * rng.standard_normal((4000, d))
sd = normal.std(0)
anom = rng.standard_normal((200, d)) * sd                           # same per-coordinate spread, wrong correlations
test = np.vstack([normal[3000:], anom])
y = np.r_[np.zeros(1000), np.ones(200)].astype(bool)
iso = IsolationForest(n_estimators=200, random_state=0).fit(normal[:3000])
lw = LedoitWolf().fit(normal[:3000])
md = lw.mahalanobis(test)
z_max = np.abs((test - normal[:3000].mean(0)) / sd).max(1)          # "any coordinate unusual?"
print(f"{'detector':34s} {'AUROC':>6}")
for name, s in (("max |z-score| over coordinates", z_max), ("Isolation Forest", -iso.score_samples(test)),
                ("Mahalanobis (Ledoit-Wolf)", md)):
    print(f"{name:34s} {roc_auc_score(y, s):>6.3f}")
assert roc_auc_score(y, md) > roc_auc_score(y, -iso.score_samples(test)) + 0.2
print("\nALL ASSERTIONS PASSED")
```

Output (verified):

```text
== 1. c(n): expected path length normalizer ==
  c(2)=1.000  c(16)=4.696  c(256)=10.245  c(4096)=15.790

== 2. 2-D: two blobs + 10 planted anomalies ==
Spearman(ours, sklearn) = 0.939; planted anomalies in top-10: ours 7, sklearn 5; AUROC ours 0.916, sklearn 0.926

== 3. correlation-structure anomalies in 50-D (data lives near a 5-D subspace) ==
detector                            AUROC
max |z-score| over coordinates      0.766
Isolation Forest                    0.696
Mahalanobis (Ledoit-Wolf)           1.000

ALL ASSERTIONS PASSED
```

---

## 4. The Andrew Ng Lens: Measure the Gate Like a Model

### 4.1 The gate has its own bias and variance

An OOD gate is a binary classifier (in vs out), and Ng's diagnostics apply:

- **Bias:** the score family can't separate the classes (Isolation Forest on embeddings: 0.706, even with ample data). Change the *score*, not its parameters.
- **Variance:** covariance estimated from too little data (a per-class covariance of rank 99 in 384-d). Use tied covariance plus shrinkage.
- **Data mismatch:** thresholds set on a validation set with a different OOS prevalence or OOS *type* (far vs near). Collect OOS validation examples from real escalated traffic.

### 4.2 Error analysis on the gate's mistakes

Pull the OOS queries that passed the gate and the in-scope queries it rejected. Tag them: *near-OOD* (adjacent domain), *ambiguous* (could be either), *phrasing* (an in-scope intent in unusual words), *label error*. Near-OOD leakage argues for an explicit "other" class or LLM escalation of the uncertain band. Phrasing rejections argue for more training-phrase diversity, since the gate is only as good as the in-distribution data it measures against.

### 4.3 Evaluation-driven gate design

Write the gate's eval first: in-scope validation plus labelled OOS at production prevalence, reporting FPR@95%TPR (or at your chosen TPR), the rejection rate of in-scope traffic, and µs per query. Compare the cheap candidates (cosine, MSP, relative Mahalanobis) on that eval *before* adopting a heavier method.

---

## 5. Failure Modes

| # | Symptom | Signature | Root cause | Fix | Prevention |
|---|---|---|---|---|---|
| F1 | Mahalanobis scores explode or are NaN | Inverting a singular or ill-conditioned covariance (cond ~10¹⁶) | Per-class covariances from few samples; no shrinkage | Tied covariance + Ledoit-Wolf/OAS | Log the condition number at fit time |
| F2 | Gate rejects a third of legitimate traffic | Threshold from a χ² table | Embeddings aren't Gaussian (χ² threshold kept 64.5%) | Empirical validation quantile | Thresholds documented with their provenance |
| F3 | Plain Mahalanobis underperforms a simple cosine gate | 0.946 vs 0.966 | Whitening amplifies generic low-variance directions | Relative Mahalanobis (background-corrected) | Benchmark against the cosine gate |
| F4 | Isolation Forest "detects nothing" on embeddings | AUROC ~0.7 | Axis-aligned splits can't see correlation anomalies | Distance-based gates; keep iForest for tabular telemetry | Choose detectors by feature type |
| F5 | Gate latency blows the budget | Brute-force kNN or LOF per request (345–530 µs) | Neighbour search over the training set | ANN index, or centroid/Mahalanobis gates | Latency budget per gate |
| F6 | Mahalanobis scoring job runs for hours | Python loop over classes with a three-operand einsum | O(n·d²·K) naive contraction | Expanded quadratic form (three matmuls) | Code review for O(n·d²) loops |
| F7 | MSP gate quality changed after recalibration | T = 0.62 for calibration lowered OOD AUROC (0.962 → 0.945) | Temperature changes cross-input confidence ranking | Separate temperatures for calibration and the gate | Gate eval rerun after any calibration change |
| F8 | Gate flags a new channel's legitimate traffic | Covariate shift, not semantic shift | Gate fitted on one channel's phrasing | Add the channel's in-scope examples to the fit | Slice metrics by channel |
| F9 | LOF scores of new points look wrong | `novelty=False` (the default) | Default LOF only scores training data | `LocalOutlierFactor(novelty=True)` | Library-default review |

---

## 6. Bar-Raiser Q&A Chains

<details><summary><b>Q1 · "Pick an OOD detector for our intent router, and defend it."</b></summary>

**Initial Prompt.** 150 intents, MiniLM embeddings, a latency budget of tens of microseconds for the gate.

**L5 Answer.** "Isolation Forest. It's the standard anomaly detector."

**Why L5 Fails in Production.** On text embeddings it nearly fails (AUROC 0.706, letting 81.8% of OOS through at 95% TPR). Axis-aligned isolation can't see anomalies that differ only in direction.

**L7 Principal Defense.** "I benchmarked eight gates on CLINC's labelled out-of-scope set. Relative Mahalanobis is best: AUROC 0.972, FPR@95%TPR 0.116, 19 µs per query. Max cosine to centroids is the best cheap option (0.966, 0.173, 4 µs). Implementation: per-class means, one tied Ledoit-Wolf covariance (the empirical one has condition number ~10¹⁶), a global background Gaussian, and scoring with the expanded quadratic form. The threshold is the empirical 95th percentile on in-scope validation, not χ², which would reject 35% of good traffic. The uncertain band between two thresholds escalates to an LLM."

**Bar-Raiser Follow-ups.**
- *"Why does relative beat plain Mahalanobis?"* Whitening inflates low-variance generic directions, so every query looks far along them. Subtracting the background model's distance removes the 'any text is this far' component.
- *"Memory?"* A 384 × 384 precision matrix (1.2 MB in fp64) plus 150 means. Trivial.

</details>

<details><summary><b>Q2 · "Derive Mahalanobis distance and say when it reduces to Euclidean."</b></summary>

**Initial Prompt.** Whiteboard.

**L5 Answer.** "It's distance divided by the standard deviation."

**Why L5 Fails in Production.** That's per-coordinate standardization, which ignores correlations, and correlations are the whole point.

**L7 Principal Defense.** "D² = (x − μ)ᵀΣ⁻¹(x − μ). With Σ = LLᵀ, D² = ‖L⁻¹(x − μ)‖²: Euclidean distance after whitening, the transform that makes the covariance the identity. We verified the identity to 1e-13. It reduces to Euclidean when Σ = σ²I (isotropic), and to standardized Euclidean when Σ is diagonal. For Gaussian data D² ~ χ²_d (we measured mean 20.02 and variance 40.3 for d = 20), which motivates χ² thresholds. On real embeddings, use empirical quantiles instead."

**Bar-Raiser Follow-ups.**
- *"Why does it catch correlation anomalies?"* Directions with little variance in the data get a large weight in Σ⁻¹, so a point that moves along them is far, even if every coordinate is in range. Our 50-D test: Mahalanobis AUROC 1.000 vs 0.766 for per-coordinate z-scores.

</details>

<details><summary><b>Q3 · "Why do you need shrinkage? We have 15,000 training examples."</b></summary>

**Initial Prompt.** An engineer argues the sample covariance is fine with this much data.

**L5 Answer.** "Shrinkage is for small data; we have plenty."

**Why L5 Fails in Production.** Our tied covariance from 15,000 class-centred residuals still had condition number 1.8 × 10¹⁶. Some directions carry essentially no variance, so the inverse amplifies noise in them by about 10¹⁶.

**L7 Principal Defense.** "What matters is the spectrum, not just n vs d. Embeddings can have near-degenerate directions however much data you have. Ledoit-Wolf picks the blend toward a scaled identity analytically: α ≈ 0.026 here, which brought the condition number to 268 and costs one line of code. Per-class covariances are worse: 100 samples in 384-d give rank 99, which is singular by construction. Hence a tied covariance plus shrinkage."

**Bar-Raiser Follow-ups.**
- *"Ledoit-Wolf vs OAS?"* Both shrink toward a scaled identity. OAS is derived for Gaussian data and was slightly less aggressive here (α 0.023, cond 306). The choice rarely matters next to *whether* you shrink.

</details>

<details><summary><b>Q4 · "Our anomaly team uses Isolation Forest everywhere. Should the AI platform use it for embedding OOD?"</b></summary>

**Initial Prompt.** Standardization pressure across teams.

**L5 Answer.** "Yes, consistency across the company is good."

**Why L5 Fails in Production.** Consistency doesn't help if the tool fits one kind of data and not the other. Isolation Forest suits tabular telemetry and fails on embeddings.

**L7 Principal Defense.** "Isolation Forest isolates points with random axis-aligned splits, so it finds points extreme in *some feature*. That's perfect for request rates, payload sizes and error counts, where anomalies are extreme on meaningful axes. Embedding anomalies differ in *direction*, with every coordinate in range: our 50-D correlation test gave iForest 0.696 vs Mahalanobis 1.000, and on CLINC iForest scored 0.706 vs 0.972 for relative Mahalanobis. So: standardize the *evaluation protocol* (FPR at a fixed TPR on labelled anomalies), and let it pick the detector per data type."

**Bar-Raiser Follow-ups.**
- *"Extended Isolation Forest (random oblique splits)?"* It addresses the axis-aligned bias in part. Benchmark it against the distance gates on the same eval before adopting it.

</details>

<details><summary><b>Q5 · "We calibrated the router with temperature scaling and the OOD gate got worse. Why?"</b></summary>

**Initial Prompt.** The gate uses max softmax probability.

**L5 Answer.** "Calibration shouldn't affect OOD; it must be a bug."

**Why L5 Fails in Production.** Temperature scaling preserves the argmax *per input*, but changes how confidence *ranks across inputs*, and that ranking is what an OOD gate thresholds.

**L7 Principal Defense.** "Measured: the LR head's MSP had OOD AUROC 0.9618 at T = 1, and 0.9451 at T = 0.62, the calibration-optimal temperature that sharpens the distribution. Sharpening pushes many inputs, OOS ones included, toward confidence 1, so they're harder to rank. ODIN goes the other way and raises T for OOD detection. So use separate temperatures: one fitted for calibration (for thresholds on probabilities), one tuned on the OOS eval for the gate. Or switch to a distance-based gate that calibration doesn't touch (cosine 0.966, relative Mahalanobis 0.972)."

**Bar-Raiser Follow-ups.**
- *"Does that mean calibration was wrong?"* No. It serves a different consumer. Each consumer gets the transform tuned for its metric.

</details>

<details><summary><b>Q6 · "How do you set the OOD threshold?"</b></summary>

**Initial Prompt.** The gate score is a Mahalanobis distance.

**L5 Answer.** "Use the χ² 95th percentile for d = 384."

**Why L5 Fails in Production.** The χ² threshold assumes Gaussian embeddings and a known covariance. On CLINC it kept only 64.5% of in-scope traffic instead of 95%.

**L7 Principal Defense.** "Take the score's empirical quantile on in-scope validation data at the in-scope pass rate the product wants: the 95th percentile kept 95.7% on test. Then check the FPR on labelled OOS, ideally a validation set whose OOS prevalence and type (near vs far) match production. If the product needs two thresholds (route / escalate / refuse), set both from quantiles and price the middle band with the LLM-escalation cost (Folder 07). Re-derive on any encoder change."

**Bar-Raiser Follow-ups.**
- *"Finite-sample guarantee?"* Use the split-conformal version of the quantile: with n in-scope calibration scores, take the ⌈(n+1)(1−α)⌉-th smallest as the threshold. Then, if calibration and production in-scope data are exchangeable, the false-rejection rate is at most α (and above α − 1/(n+1)).

</details>

<details><summary><b>Q7 · "kNN distance is state of the art for OOD in the literature. Why not use it?"</b></summary>

**Initial Prompt.** A paper review suggests deep kNN.

**L5 Answer.** "Use it if it's state of the art."

**Why L5 Fails in Production.** It ignores the cost: brute-force kNN scanned all 15,000 training embeddings per query (523 µs), and on this data it didn't win (0.9625 vs 0.9724).

**L7 Principal Defense.** "On CLINC, kNN (k = 1) reached 0.9625. That's competitive, but behind relative Mahalanobis (0.9724) and essentially tied with the 4 µs centroid gate (0.9656). In production it needs an ANN index over the training set, which adds an index to build, version and monitor. Literature rankings come from vision benchmarks with different encoders. Our measurement on our encoder and our OOS traffic decides. I'd keep kNN as a candidate in the eval suite, since it shines when classes are multi-modal and centroids misrepresent them."

**Bar-Raiser Follow-ups.**
- *"Which k?"* Small k is more local. k = 1 beat k = 10 here (0.9625 vs 0.9564). Tune it on the OOS validation set.

</details>

<details><summary><b>Q8 · "Design a gate that never misroutes OOS and rarely annoys users."</b></summary>

**Initial Prompt.** The product wants both.

**L5 Answer.** "Set a very strict threshold."

**Why L5 Fails in Production.** A single strict threshold rejects lots of legitimate traffic: at the strict end, our best gate still trades in-scope rejection against OOS leakage.

**L7 Principal Defense.** "Use two thresholds on relative Mahalanobis. Above the upper one, route locally (only ~5% of in-scope traffic falls below it). Below the lower one, it's confidently out of scope: refuse or redirect without an LLM call. Between them, escalate to an LLM classifier, which handles near-OOD nuance best. Pick both thresholds by minimizing expected cost: misroute cost × leaked OOS + annoyance cost × false rejections + LLM cost × band volume, on validation data at production prevalence. Monitor the band's volume as a drift signal: a growing middle band means traffic is moving away from what we trained on."

**Bar-Raiser Follow-ups.**
- *"What do you do with confidently-OOS traffic?"* Log and cluster it (03.1). The biggest clusters are candidate new intents.

</details>

---

## 7. Invariants Checklist

- [ ] Every model in the request path has an OOD gate, evaluated on labelled OOS data at production prevalence (FPR at a fixed TPR, plus µs per query).
- [ ] Mahalanobis gates use class means, a tied covariance and Ledoit-Wolf/OAS shrinkage. The condition number is logged at fit time.
- [ ] Relative (background-corrected) Mahalanobis is benchmarked whenever plain Mahalanobis is used.
- [ ] Quadratic forms are computed in expanded matrix form, never with per-class loops.
- [ ] Thresholds are empirical validation quantiles, never χ² tables, and are re-derived on any encoder change.
- [ ] MSP-based gates have their own temperature, separate from the calibration temperature.
- [ ] Isolation Forest is used for tabular telemetry, not embeddings.
- [ ] Gate scores are logged and monitored as a drift signal. The escalation band's volume is tracked.

---

## 8. References

1. P. C. Mahalanobis, *On the Generalized Distance in Statistics*, Proc. National Institute of Sciences of India 2(1), 1936.
2. O. Ledoit, M. Wolf, *A well-conditioned estimator for large-dimensional covariance matrices*, J. Multivariate Analysis 88(2), 2004. DOI 10.1016/S0047-259X(03)00096-4.
3. Y. Chen, A. Wiesel, Y. Eldar, A. Hero, *Shrinkage Algorithms for MMSE Covariance Estimation* (OAS), IEEE Trans. Signal Processing 58(10), 2010. DOI 10.1109/TSP.2010.2053029.
4. K. Lee, K. Lee, H. Lee, J. Shin, *A Simple Unified Framework for Detecting Out-of-Distribution Samples and Adversarial Attacks*, NeurIPS 2018. https://arxiv.org/abs/1807.03888
5. J. Ren et al., *A Simple Fix to Mahalanobis Distance for Improving Near-OOD Detection*, 2021. https://arxiv.org/abs/2106.09022
6. Y. Sun, Y. Ming, X. Zhu, Y. Li, *Out-of-Distribution Detection with Deep Nearest Neighbors*, ICML 2022. https://arxiv.org/abs/2204.06507
7. F. T. Liu, K. M. Ting, Z.-H. Zhou, *Isolation Forest*, ICDM 2008. DOI 10.1109/ICDM.2008.17.
8. M. Breunig, H.-P. Kriegel, R. Ng, J. Sander, *LOF: Identifying Density-Based Local Outliers*, SIGMOD 2000. DOI 10.1145/342009.335388.
9. D. Hendrycks, K. Gimpel, *A Baseline for Detecting Misclassified and Out-of-Distribution Examples in Neural Networks*, ICLR 2017. https://arxiv.org/abs/1610.02136
10. S. Liang, Y. Li, R. Srikant, *Enhancing the Reliability of Out-of-Distribution Image Detection in Neural Networks* (ODIN), ICLR 2018. https://arxiv.org/abs/1706.02690
11. J. Yang, K. Zhou, Y. Li, Z. Liu, *Generalized Out-of-Distribution Detection: A Survey*, 2021. https://arxiv.org/abs/2110.11334
12. scikit-learn user guide, *Covariance estimation* and *Novelty and Outlier Detection*. https://scikit-learn.org/stable/modules/outlier_detection.html
