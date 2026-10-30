# 02.2 · Decision Trees, Random Forests & Gradient-Boosted Trees (XGBoost, LightGBM)

> **Folder 02 · Classical Supervised ML for AI Engineers: Fast Routers & Rankers**
> **Measured on:** scikit-learn 1.9.1, XGBoost 3.4.1, LightGBM 4.7.0, NumPy 2.5.4, CPython 3.14.5, Intel i5-11260H (one thread unless stated), Windows 11. Real data: CLINC150 / MiniLM embeddings from 02.1. Other data is synthetic and seeded.
> **Design sources:** Breiman (2001), Friedman (2001), Chen & Guestrin (XGBoost, KDD 2016), Ke et al. (LightGBM, NeurIPS 2017), Grinsztajn et al. (NeurIPS 2022), the XGBoost and LightGBM parameter docs. Full list in §8.

---

## 0. Orientation: Trees Are for Features You Engineered, Linear Heads Are for Features You Learned

The Andrew Ng-style one-liner: **a decision tree asks a sequence of yes/no questions about individual features. Boosting builds hundreds of small trees, each one correcting the last. That's unbeatable on tabular data, and a poor fit for dense embeddings.** This file proves both halves:

- On tabular escalation-risk features with thresholds and interactions, LightGBM beats logistic regression (AUC **0.760 vs 0.718**).
- On 384-d MiniLM embeddings (20 CLINC intents), logistic regression beats LightGBM (**0.985 vs 0.952**), fitting in 0.1 s vs 46.5 s across 4,760 trees.

In an AI system, gradient-boosted trees (GBDTs) earn their place on the **meta-features around models**:

- risk scores built from counts, lengths, recency and user history;
- learning-to-rank over retrieval signals (BM25 score, cosine, freshness: LambdaMART, Folder 04);
- churn, escalation and fraud scoring;
- deciding *which* model should handle a request (Folder 07).

### The backend-engineer bridge

| You already know | Tree equivalent | Why it maps |
|---|---|---|
| A nested `if/else` rule set written by an SME | **A decision tree** | Same structure, but the thresholds are chosen to minimize impurity instead of by intuition |
| A committee or quorum (majority vote among replicas) | **A random forest** | Averaging independent-ish opinions cuts variance, *if* they don't fail together (the ρ term) |
| An incremental patch series, each fixing the previous build's bugs | **Gradient boosting** | Each tree fits the remaining errors (gradients) of the ensemble so far |
| A histogram index (bucketed column stats) | **Histogram binning (`max_bin`)** | Split search over 64–256 bucket boundaries instead of every distinct value: the core speed trick in XGBoost `hist` and LightGBM |

### Tier map

| Subtopic | Tier |
|---|---|
| 1.1 Impurity and greedy splits | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.2 Axis-aligned geometry: why trees struggle on embeddings | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.3 Depth as the bias/variance knob | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.4 Bagging and random forests: the ρσ² law | `[GOOD-TO-KNOW: Architectural Literacy]` |
| 1.5 Gradient boosting as functional gradient descent | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.6 Newton boosting: XGBoost's leaf weights and split gain | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.7 Shrinkage, early stopping, and histogram binning | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.8 LightGBM's leaf-wise growth, GOSS and EFB | `[GOOD-TO-KNOW: Architectural Literacy]` |
| 1.9 Categorical features, missing values, monotone constraints | `[GOOD-TO-KNOW: Architectural Literacy]` |
| 1.10 Serving trees: latency and compiled forms | `[GOOD-TO-KNOW: Architectural Literacy]` |
| 1.11 Boosting theory (AdaBoost margins, PAC bounds) | `[SKIP: Academic/Research Only]` |

---

## 1. First-Principles Math & Geometric Intuition

### 1.1 Impurity and greedy splits `[MUST-KNOW: Core AI Engineer Edge]`

A classification tree picks, at each node, the single feature j and threshold t that make the two children as "pure" as possible. For a node with positive fraction p:

```text
Gini           = 1 − p² − (1−p)² = 2p(1−p)
Entropy (bits) = −p log₂ p − (1−p) log₂(1−p)
Misclassification = min(p, 1−p)
split score = (n_L · I(L) + n_R · I(R)) / n          (choose the (j, t) that minimizes it)
```

```text
    p     gini 2p(1-p)  entropy (bits)  misclass
  0.5         0.5000          1.0000    0.5000
  0.1         0.1800          0.4690    0.1000
```

Gini and entropy are strictly concave in p, so a split that makes the children *more* skewed always scores better, even when both children would predict the same majority class. Misclassification rate is piecewise linear and often can't tell such splits apart, which is why it isn't used for growing trees.

**The search is exhaustive and greedy.** Sort each feature, sweep the threshold over midpoints between distinct values, update class counts incrementally (prefix sums), and take the best. That's O(d · n log n) per node. The listing implements it in 25 lines and gets **exactly scikit-learn's root split**: feature 0, threshold 0.192262. Greedy means no lookahead. The XOR target in §3.1 has *no* good first split (each feature alone is uninformative), so a depth-1 tree reaches only 0.624 test accuracy, while depth 2 jumps to 0.917.

### 1.2 Axis-aligned geometry: why trees struggle on embeddings `[MUST-KNOW: Core AI Engineer Edge]`

Every tree split is a hyperplane perpendicular to one feature axis. The decision regions are boxes:

```text
  depth 3 on the XOR target (o = class 0, x = class 1), from the listing:
  xxxxxxxxxxxxxxxxxxxxxxxxxxoooooooooooooooooo
  xxxxxxxxxxxxxxxxxxxxxxxxxxoooooooooooooooooo
  ooooooooooooooooooooooooooxxxxxxxxxxxxxxxxxx      ← boxes aligned with x1 and x2
  ooooooooooooooooooooooooooxxxxxxxxxxxxxxxxxx
```

This matches tabular data: "prior tickets ≥ 3", "account age > 1500 days", "hour < 6". Each feature means something on its own, and thresholds on it are natural. Embeddings are the opposite. Their information lies along *oblique* directions (any rotation of the space is equally valid, 01.1 §1.1), so one oblique boundary costs a tree a staircase of many axis-aligned splits:

```text
    oblique boundary w·x = 0           what a tree must build to approximate it
          \  x x x                         ┌─┐x x x
        o  \   x x                       o └─┼─┐ x x
      o o o \    x                     o o o └─┼─┐ x
    o o o o  \                       o o o o   └─┘      many splits, still jagged
```

That's why, on CLINC embeddings (20 intents), LightGBM needs 4,760 trees and 46.5 s to reach 0.952, while logistic regression reaches 0.985 in 0.1 s (§3.3). Grinsztajn et al. (2022) document the mirror-image result on tabular benchmarks: trees beat deep networks there, in part *because* tabular features are meaningful individually and rotations destroy them. **Put trees on engineered features and linear (or neural) heads on learned embeddings.**

### 1.3 Depth as the bias/variance knob `[MUST-KNOW: Core AI Engineer Edge]`

```text
depth train acc test acc leaves   (8% label noise -> best possible test acc ~0.92)
    1     0.638    0.624      2      ← bias: can't represent XOR
    2     0.923    0.917      4      ← right structure
    5     0.938    0.916     20
   12     0.997    0.863     72      ← variance: memorizes the 8% label noise
 None     1.000    0.864     74
```

An unconstrained tree drives training error to zero by giving noisy points their own leaves, and test accuracy falls 5 points. Production trees are constrained by `max_depth`, `min_samples_leaf` / `min_child_weight` or `num_leaves`. Ensembles (below) are the bigger fix.

### 1.4 Bagging and random forests: the ρσ² law `[GOOD-TO-KNOW: Architectural Literacy]`

Average B trees, each with prediction variance σ² (across possible training sets) and pairwise correlation ρ:

```text
Var(average) = ρσ² + (1 − ρ)σ²/B
```

As B grows, the second term vanishes, **but ρσ² doesn't**. Bagging (bootstrap samples) alone leaves trees correlated, because they all split on the same strong features. Random forests (Breiman, 2001) also sample a subset of features at each split (`max_features`). That makes each tree individually *worse* (higher σ²) but much less correlated (lower ρ). Measured over 40 independent training sets of Friedman #1:

```text
max_features sigma^2 (1 tree)    rho  Var(forest) measured  rho*s2+(1-rho)s2/B
         1.0           9.3429  0.111                1.2043              1.2043
         0.3          13.7661  0.040                0.8085              0.8085
```

With feature subsampling, single-tree variance rose 47% but ρ fell from 0.111 to 0.040, and the forest's variance fell 33%. (The measured and formula columns agree exactly because the formula, with ρ measured as the mean pairwise covariance, is the algebraic identity for the variance of a mean. The insight is in the ρ and σ² columns.) The same law governs any ensemble or voting scheme, LLM self-consistency voting included: **voters that fail together don't average away their errors.**

### 1.5 Gradient boosting as functional gradient descent `[MUST-KNOW: Core AI Engineer Edge]`

Boosting builds an additive model F(x) = Σₘ η·fₘ(x) one tree at a time (Friedman, 2001). At round m, the best direction to move F at each training point is the negative gradient of the loss:

```text
rᵢ = −∂L(yᵢ, F(xᵢ)) / ∂F(xᵢ)          (squared loss: the residual yᵢ − F(xᵢ); log-loss: yᵢ − pᵢ)
fit a small tree fₘ to the rᵢ;   F ← F + η·fₘ
```

It's gradient descent, but in *function space*: each tree is a step, constrained to piecewise-constant functions over a few boxes. The p − y gradient of 01.3 §1.11 appears again. For log-loss, every boosting round fits a tree to the classification errors of the current ensemble.

### 1.6 Newton boosting: XGBoost's leaf weights and split gain `[MUST-KNOW: Core AI Engineer Edge]`

Chen & Guestrin (2016) use a **second-order** Taylor expansion of the loss around the current predictions. With gᵢ = ∂L/∂F and hᵢ = ∂²L/∂F² (for log-loss, g = p − y and h = p(1 − p)), a tree that assigns weight w_j to all points in leaf j changes the regularized objective by

```text
Obj ≈ Σ_j [ G_j w_j + ½ (H_j + λ) w_j² ] + γ·T          G_j = Σ_{i∈j} gᵢ,  H_j = Σ_{i∈j} hᵢ,  T = #leaves
```

Each leaf is an independent quadratic in w_j, so:

```text
optimal leaf weight      w_j* = −G_j / (H_j + λ)                         (a Newton step per leaf)
objective at the optimum      = −½ Σ_j G_j² / (H_j + λ) + γT
split gain   = ½ [ G_L²/(H_L+λ) + G_R²/(H_R+λ) − (G_L+G_R)²/(H_L+H_R+λ) ] − γ
```

λ shrinks leaf weights (L2 on the leaves). γ is the minimum gain needed to make a split (pruning). H_j is what XGBoost reports as a leaf's **cover**. `min_child_weight` is a lower bound on H, *not* on the row count: for confident predictions h = p(1 − p) is tiny, so a leaf can hold many rows and still fail it.

**Verified against XGBoost** (§3.2). A depth-2 tree built from these formulas, from scratch, with exact split search on the same data:

```text
leaves (value, cover) ours:    [(-0.832501, 1251.25), (-0.073453, 1489.75), (0.626664, 1257.25), (1.188232, 1001.75)]
leaves (value, cover) xgboost: [(-0.832501, 1251.25), (-0.073453, 1489.75), (0.626664, 1257.25), (1.188232, 1001.75)]
max |margin difference| on 20,000 test rows = 5.83e-08
xgboost's reported gain / our 0.5*[...] gain = 2.0000 (it omits the 1/2)
```

Every leaf value and cover matches. One practical footnote: **XGBoost's reported `gain` omits the ½**, so it's twice the textbook formula. That matters if you compare `gain` feature importances against a hand calculation, or set γ from a formula.

### 1.7 Shrinkage, early stopping, and histogram binning `[MUST-KNOW: Core AI Engineer Edge]`

**Shrinkage (η, learning rate)** scales each tree's contribution. Smaller steps need more rounds but usually generalize better, because each tree corrects only part of the error and later trees can fix earlier mistakes:

```text
  eta best round test logloss
  1.0          4       0.5964
  0.3         22       0.5941
  0.1         67       0.5939
 0.03        234       0.5940
```

Past η ≈ 0.1 the quality plateaus while the tree count keeps growing, and **tree count is serving latency** (§1.10). The practical recipe: η around 0.05–0.1, a large round budget, and **early stopping on a validation set** (stop when validation loss hasn't improved for, say, 30–50 rounds).

**Histogram binning.** Instead of scanning every distinct value, bucket each feature into `max_bin` quantile bins once. Then each node's split search builds per-bin sums of g and h (`np.bincount` in our implementation) and scans bin boundaries: O(bins) per feature instead of O(n). Our 64-bin NumPy booster, XGBoost `hist` and LightGBM all stop at **round 67 with validation log-loss 0.5943** on the same data. When features have fewer distinct values than bins (20 here), binning is lossless. With 16 bins on 20-valued features it costs 0.0016 log-loss.

### 1.8 LightGBM's leaf-wise growth, GOSS and EFB `[GOOD-TO-KNOW: Architectural Literacy]`

- **Leaf-wise (best-first) growth.** XGBoost's default grows level by level. LightGBM splits whichever leaf has the highest gain anywhere in the tree, controlled by `num_leaves`. That reaches lower loss with fewer leaves, but grows deep, narrow branches that overfit small data. Constrain it with `max_depth`, `min_data_in_leaf` and `min_sum_hessian_in_leaf`. (Our comparison sets `max_depth=3, num_leaves=8`, which forces the same structure as XGBoost.)
- **GOSS (gradient-based one-side sampling)** keeps the rows with large gradients and subsamples the small-gradient (already well-fitted) rows, re-weighting them. It speeds up training on big data.
- **EFB (exclusive feature bundling)** merges sparse features that are rarely non-zero together into one histogram. It's a big win on one-hot-heavy data.

### 1.9 Categorical features, missing values, monotone constraints `[GOOD-TO-KNOW: Architectural Literacy]`

- **Missing values:** both libraries learn a default direction per split, sending NaNs wherever the gain is best. Don't impute with 0 unless 0 means "missing".
- **Categoricals:** LightGBM (`categorical_feature`) and XGBoost (`enable_categorical`) can split on category *sets* directly, which avoids one-hot explosion for high-cardinality fields (tenant id, product category). Target encoding is the alternative, with the leakage caveats of any target-derived feature.
- **Monotone constraints** (`monotone_constraints`) force the prediction to be non-decreasing in a feature: risk can't go *down* as failed-login count goes up. They're essential for guardrail and risk models that auditors will read, and they often regularize usefully.

### 1.10 Serving trees: latency and compiled forms `[GOOD-TO-KNOW: Architectural Literacy]`

Prediction walks every tree from root to leaf: O(trees × depth) comparisons, with branches that are hard to predict. Measured with LightGBM `Booster.predict`, one thread:

```text
 trees      1 row  batch 256 (per row)
    50       37 us               1.9 us
   200       42 us               8.2 us
   800       62 us              32.1 us
```

A single-row call is dominated by fixed per-call overhead (~35 µs), and batching exposes the true per-tree cost (~40 ns per tree per row here). For hot paths, batch requests; cap the tree count with early stopping; or compile the model (Treelite, `lleaves`, or an ONNX conversion via `onnxmltools` served by ONNX Runtime) so the trees become straight-line code. These figures are tiny next to an LLM call, but they *add up* in a cascade that scores every request (Folder 07).

### 1.11 Boosting theory `[SKIP: Academic/Research Only]`

AdaBoost as exponential-loss minimization, margin-based generalization bounds, and the consistency of boosting are elegant, and you won't need them to ship. The production facts are §1.5–1.7: function-space gradient steps, Newton leaf weights, shrinkage and early stopping.

---

## 2. Where It Beats an LLM in Production

| Task | GBDT on engineered features | LLM alternative |
|---|---|---|
| Ticket escalation / churn / fraud risk from counts, recency, amounts | AUC 0.760 vs LR 0.718 on threshold-and-interaction data; 37–62 µs per single row | An LLM can't read 10⁶ rows of history per request at any reasonable cost |
| Learning-to-rank over retrieval signals (Folder 04) | LambdaMART on BM25, cosine, freshness, click priors | A cross-encoder or LLM reranker is far costlier per candidate |
| Choosing a model per request (cascade routing, Folder 07) | A GBDT on request meta-features predicts "the small model will fail" | Asking an LLM whether to call an LLM defeats the purpose |
| Monotone, auditable risk scores | `monotone_constraints` + SHAP explanations | LLM rationales aren't stable or auditable |

**Measure before you stack.** §3.3 trains a LightGBM over five meta-features of the CLINC router (max probability, margin, entropy, nearest-neighbour cosine, mean top-5 cosine) to predict when the router is wrong. AUC **0.9640** vs **0.9644** for 1 − max probability alone. The free signal from a well-regularized LR head was already as good. Stackers pay off when the meta-features carry *information the base model doesn't have* (user history, request metadata, upstream latency), not when they re-describe its own confidence.

---

## 3. Production Code Blueprint

### 3.1 Tree splits, decision regions, depth, and forest variance

```python
"""tree_split_and_forest_variance.py - how a tree partitions space, and why averaging decorrelated trees works.

  1. Impurity: Gini, entropy and misclassification for a binary node.
  2. An exhaustive best-split search from scratch returns the same (feature, threshold) as sklearn's root split.
  3. Axis-aligned decision regions at depth 1 / 3 / 12 (ASCII), and the depth sweep (bias -> variance).
  4. Random-forest variance: over 40 independent training sets, Var(forest) == rho*sigma^2 + (1-rho)*sigma^2/B,
     and feature subsampling (max_features) lowers rho.
"""
import numpy as np
from sklearn.datasets import make_friedman1
from sklearn.ensemble import RandomForestRegressor
from sklearn.tree import DecisionTreeClassifier

rng = np.random.default_rng(41)

print("== 1. impurity of a node with positive fraction p ==")
print(f"{'p':>5} {'gini 2p(1-p)':>13} {'entropy (bits)':>15} {'misclass':>9}")
for p in (0.5, 0.3, 0.1, 0.01):
    ent = -(p * np.log2(p) + (1 - p) * np.log2(1 - p))
    print(f"{p:>5} {2 * p * (1 - p):>13.4f} {ent:>15.4f} {min(p, 1 - p):>9.4f}")


def best_split(X, y):
    """Minimize the weighted Gini of the two children over every feature and every midpoint threshold."""
    best = (np.inf, None, None)
    n = len(y)
    for j in range(X.shape[1]):
        order = np.argsort(X[:, j], kind="stable")
        xs, ys = X[order, j], y[order]
        pos_left = np.cumsum(ys)[:-1]
        n_left = np.arange(1, n)
        g_left = 1 - (pos_left / n_left) ** 2 - (1 - pos_left / n_left) ** 2
        pos_right = ys.sum() - pos_left
        n_right = n - n_left
        g_right = 1 - (pos_right / n_right) ** 2 - (1 - pos_right / n_right) ** 2
        w = (n_left * g_left + n_right * g_right) / n
        valid = xs[1:] > xs[:-1]                                    # only between distinct values
        w[~valid] = np.inf
        k = int(np.argmin(w))
        if w[k] < best[0]:
            best = (w[k], j, (xs[k] + xs[k + 1]) / 2)
    return best


X = rng.uniform(-1, 1, (600, 2))
y = ((X[:, 0] > 0.2) ^ (X[:, 1] > -0.3)).astype(int)              # an XOR of two thresholds
flip = rng.random(600) < 0.08
y[flip] = 1 - y[flip]
imp, feat, thr = best_split(X, y)
sk = DecisionTreeClassifier(max_depth=1).fit(X, y).tree_
print(f"\n== 2. root split: ours feature {feat}, threshold {thr:.6f}, weighted gini {imp:.6f} | "
      f"sklearn feature {sk.feature[0]}, threshold {sk.threshold[0]:.6f}")
assert feat == sk.feature[0] and abs(thr - sk.threshold[0]) < 1e-6

print("\n== 3. decision regions (o = class 0, x = class 1), x1 horizontal, x2 vertical ==")
gx, gy = np.meshgrid(np.linspace(-1, 1, 44), np.linspace(1, -1, 11))
G = np.c_[gx.ravel(), gy.ravel()]
panels = []
for depth in (1, 3, 12):
    pred = DecisionTreeClassifier(max_depth=depth, random_state=0).fit(X, y).predict(G).reshape(gx.shape)
    panels.append([f"depth {depth:<2}".ljust(44)] + ["".join("x" if v else "o" for v in row) for row in pred])
for rows in zip(*panels):
    print("   ".join(rows))
Xt = rng.uniform(-1, 1, (4000, 2))
yt = ((Xt[:, 0] > 0.2) ^ (Xt[:, 1] > -0.3)).astype(int)
ft = rng.random(4000) < 0.08
yt[ft] = 1 - yt[ft]
print(f"\n{'depth':>5} {'train acc':>9} {'test acc':>8} {'leaves':>6}   (8% label noise -> best possible test acc ~0.92)")
accs = {}
for depth in (1, 2, 3, 5, 8, 12, None):
    t = DecisionTreeClassifier(max_depth=depth, random_state=0).fit(X, y)
    accs[depth] = t.score(Xt, yt)
    print(f"{str(depth):>5} {t.score(X, y):>9.3f} {accs[depth]:>8.3f} {t.get_n_leaves():>6}")
assert accs[2] > accs[1] + 0.2 and accs[None] < accs[2]

print("\n== 4. random-forest variance over 40 independent training sets (Friedman #1, n=300, B=50) ==")
Xq, _ = make_friedman1(n_samples=200, noise=0.0, random_state=1)


def forest_stats(max_features):
    T = np.zeros((40, 50, len(Xq)))
    for r in range(40):
        Xr, yr = make_friedman1(n_samples=300, noise=1.0, random_state=100 + r)
        f = RandomForestRegressor(n_estimators=50, max_features=max_features, random_state=r).fit(Xr, yr)
        T[r] = np.stack([e.predict(Xq) for e in f.estimators_])
    sigma2 = T.var(axis=0).mean()                                   # variance of ONE tree across training sets
    mean_b = T.mean(axis=1)
    var_forest = mean_b.var(axis=0).mean()
    Tc = T - T.mean(axis=0, keepdims=True)
    tot = Tc.sum(axis=1)
    cov = ((tot ** 2).mean(axis=0) - (Tc ** 2).sum(axis=1).mean(axis=0)) / (50 * 49)   # mean pairwise covariance
    rho = cov.mean() / sigma2
    return sigma2, rho, var_forest, rho * sigma2 + (1 - rho) * sigma2 / 50


print(f"{'max_features':>12} {'sigma^2 (1 tree)':>16} {'rho':>6} {'Var(forest) measured':>21} {'rho*s2+(1-rho)s2/B':>19}")
out = {}
for mf in (1.0, 0.3):
    s2, rho, vf, formula = forest_stats(mf)
    out[mf] = (rho, vf)
    print(f"{mf:>12} {s2:>16.4f} {rho:>6.3f} {vf:>21.4f} {formula:>19.4f}")
    assert abs(vf - formula) / vf < 0.02
assert out[0.3][0] < out[1.0][0]
print("\nALL ASSERTIONS PASSED")
```

Output (verified):

```text
== 1. impurity of a node with positive fraction p ==
    p  gini 2p(1-p)  entropy (bits)  misclass
  0.5        0.5000          1.0000    0.5000
  0.3        0.4200          0.8813    0.3000
  0.1        0.1800          0.4690    0.1000
 0.01        0.0198          0.0808    0.0100

== 2. root split: ours feature 0, threshold 0.192262, weighted gini 0.461388 | sklearn feature 0, threshold 0.192262

== 3. decision regions (o = class 0, x = class 1), x1 horizontal, x2 vertical ==
depth 1                                        depth 3                                        depth 12                                    
xxxxxxxxxxxxxxxxxxxxxxxxxxoooooooooooooooooo   xxxxxxxxxxxxxxxxxxxxxxxxxxoooooooooooooooooo   xxxxxxxxxxxxxxxxoooxxxxxxxooooxoooooooooooox
xxxxxxxxxxxxxxxxxxxxxxxxxxoooooooooooooooooo   xxxxxxxxxxxxxxxxxxxxxxxxxxoooooooooooooooooo   xxxxxxxxxxxxxxxxxxxxxxxxxxooooxoooooooooooox
xxxxxxxxxxxxxxxxxxxxxxxxxxoooooooooooooooooo   xxxxxxxxxxxxxxxxxxxxxxxxxxoooooooooooooooooo   xxxxxxxxxxxxxxxxxxxxxxxxxxooooxoooooooooooox
xxxxxxxxxxxxxxxxxxxxxxxxxxoooooooooooooooooo   xxxxxxxxxxxxxxxxxxxxxxxxxxoooooooooooooooooo   xxxxxxxxxxxxxxxxxxxxxxxooooooooooooooooooooo
xxxxxxxxxxxxxxxxxxxxxxxxxxoooooooooooooooooo   xxxxxxxxxxxxxxxxxxxxxxxxxxoooooooooooooooooo   xxxxxxxxxxxxxxxxxxxxxxxxxxoooooooooooooooooo
xxxxxxxxxxxxxxxxxxxxxxxxxxoooooooooooooooooo   xxxxxxxxxxxxxxxxxxxxxxxxxxoooooooooooooooooo   ooxxxxxxxxxxxxxxxxxxxxxxxxoooooooooooooooooo
xxxxxxxxxxxxxxxxxxxxxxxxxxoooooooooooooooooo   xxxxxxxxxxxxxxxxxxxxxxxxxxoooooooooooooooooo   xxxxxxxxxxxxxxxxxxxxxxxxxxoooooooooooooooooo
xxxxxxxxxxxxxxxxxxxxxxxxxxoooooooooooooooooo   ooooooooooooooooooooooooooxxxxxxxxxxxxxxxxxx   ooooooooooooooooxoooooxxxxxxxxxxxxxxxxxxxxxx
xxxxxxxxxxxxxxxxxxxxxxxxxxoooooooooooooooooo   ooooooooooooooooooooooooooxxxxxxxxxxxxxxxxxx   ooooooooooooooooooooooooooxxxxxxxxxxxxxxxxxx
xxxxxxxxxxxxxxxxxxxxxxxxxxoooooooooooooooooo   ooooooooooooooooooooooooooxxxxxxxxxxxxxxxxxx   ooooooooooooooooooooooooooxxxxxxxxxxxooxxxxx
xxxxxxxxxxxxxxxxxxxxxxxxxxoooooooooooooooooo   ooooooooooooooooooooooooooxxxxxxxxxxxxxxxxxx   ooooooooooooooooooooooooxoxxxxxxxxxxxooxxxxx

depth train acc test acc leaves   (8% label noise -> best possible test acc ~0.92)
    1     0.638    0.624      2
    2     0.923    0.917      4
    3     0.928    0.919      8
    5     0.938    0.916     20
    8     0.978    0.893     52
   12     0.997    0.863     72
 None     1.000    0.864     74

== 4. random-forest variance over 40 independent training sets (Friedman #1, n=300, B=50) ==
max_features sigma^2 (1 tree)    rho  Var(forest) measured  rho*s2+(1-rho)s2/B
         1.0           9.3429  0.111                1.2043              1.2043
         0.3          13.7661  0.040                0.8085              0.8085

ALL ASSERTIONS PASSED
```

How to read it:

- **The three panels** are the axis-aligned partition growing: one cut, then the four XOR boxes, then deep trees carving noise islands (the stray `x`s in the depth-12 panel are memorized label noise).
- **The forest table** shows that decorrelation, not more trees, is the lever. B = 50 makes the (1 − ρ)σ²/B term small, and what's left is ρσ².

### 3.2 Newton boosting from scratch, checked against XGBoost and LightGBM

```python
"""gbdt_second_order_from_scratch.py - XGBoost-style (Newton) gradient boosting written from scratch, checked against XGBoost.

  For log-loss: g = p - y, h = p(1 - p). A leaf's optimal weight is w* = -G / (H + lambda), and a split's gain is
      0.5 * [G_L^2/(H_L+lambda) + G_R^2/(H_R+lambda) - G^2/(H+lambda)] - gamma.
  1. A depth-2 tree built with those formulas reproduces XGBoost's leaf values, covers (= sum of h) and predictions.
  2. Our 64-bin histogram booster vs XGBoost and LightGBM with matched settings: same quality.
  3. Shrinkage: smaller learning rates need more rounds and generalize better (early stopping on validation).
  4. Histogram resolution (max_bin): 16 vs 64 vs 256 bins.
"""
import json
import time

import lightgbm as lgb
import numpy as np
import xgboost as xgb
from sklearn.metrics import log_loss, roc_auc_score

rng = np.random.default_rng(51)


def make(n, seed):
    r = np.random.default_rng(seed)
    X = r.integers(0, 20, (n, 8)).astype(np.float64)              # integer features: exact split candidates are unambiguous
    z = 0.4 * (X[:, 0] > 12) * (X[:, 1] < 6) * 3 + 0.15 * X[:, 2] - 0.2 * (X[:, 3] > 10) + 0.05 * X[:, 4] * (X[:, 5] > 9) - 1.5
    return X, (r.random(n) < 1 / (1 + np.exp(-z))).astype(float)


Xtr, ytr = make(20_000, 1)
Xva, yva = make(5_000, 2)
Xte, yte = make(20_000, 3)
sig = lambda z: 1 / (1 + np.exp(-z))
LAM = 1.0


def build_tree(X, g, h, depth, lam=LAM, min_h=1e-3):
    """Exact greedy split search on raw values; returns nested dict and leaf assignment function."""
    G, Hs = g.sum(), h.sum()
    if depth == 0:
        return {"leaf": -G / (Hs + lam), "cover": Hs}
    best = (0.0, None, None)
    for j in range(X.shape[1]):
        vals = np.unique(X[:, j])
        for v in (vals[:-1] + vals[1:]) / 2:
            m = X[:, j] < v
            GL, HL = g[m].sum(), h[m].sum()
            GR, HR = G - GL, Hs - HL
            if HL < min_h or HR < min_h:
                continue
            gain = 0.5 * (GL ** 2 / (HL + lam) + GR ** 2 / (HR + lam) - G ** 2 / (Hs + lam))
            if gain > best[0]:
                best = (gain, j, v)
    if best[1] is None:
        return {"leaf": -G / (Hs + lam), "cover": Hs}
    _, j, v = best
    m = X[:, j] < v
    return {"feat": j, "thr": v, "gain": best[0], "cover": Hs,
            "yes": build_tree(X[m], g[m], h[m], depth - 1, lam), "no": build_tree(X[~m], g[~m], h[~m], depth - 1, lam)}


def predict_tree(t, X):
    if "leaf" in t:
        return np.full(len(X), t["leaf"])
    m = X[:, t["feat"]] < t["thr"]
    out = np.empty(len(X))
    out[m], out[~m] = predict_tree(t["yes"], X[m]), predict_tree(t["no"], X[~m])
    return out


def leaves(t):
    return [(round(float(t["leaf"]), 6), round(float(t["cover"]), 3))] if "leaf" in t else leaves(t["yes"]) + leaves(t["no"])


print("== 1. one depth-2 Newton tree from scratch vs XGBoost (exact, base_score 0.5, eta 1, lambda 1) ==")
p0 = np.full(len(ytr), 0.5)
ours = build_tree(Xtr, p0 - ytr, p0 * (1 - p0), depth=2)
bst = xgb.train({"objective": "binary:logistic", "tree_method": "exact", "max_depth": 2, "eta": 1.0, "lambda": LAM,
                 "min_child_weight": 0, "base_score": 0.5, "seed": 0}, xgb.DMatrix(Xtr, label=ytr), num_boost_round=1)
dump = json.loads(bst.get_dump(dump_format="json", with_stats=True)[0])


def xgb_leaves(n):
    return [(round(n["leaf"], 6), round(n["cover"], 3))] if "leaf" in n else sum((xgb_leaves(c) for c in n["children"]), [])


ml, xl = sorted(leaves(ours)), sorted(xgb_leaves(dump))
print(f"root split: ours f{ours['feat']} < {ours['thr']}, gain {ours['gain']:.4f}; "
      f"xgboost {dump['split']} < {dump['split_condition']}, gain {dump['gain']:.4f}")
print(f"leaves (value, cover) ours:    {ml}")
print(f"leaves (value, cover) xgboost: {xl}")
margin_ours = predict_tree(ours, Xte)
margin_xgb = bst.predict(xgb.DMatrix(Xte), output_margin=True)
print(f"max |margin difference| on 20,000 test rows = {np.abs(margin_ours - margin_xgb).max():.2e}")
assert np.allclose([a for a, _ in ml], [a for a, _ in xl], atol=1e-5) and np.abs(margin_ours - margin_xgb).max() < 1e-5
print(f"xgboost's reported gain / our 0.5*[...] gain = {dump['gain'] / ours['gain']:.4f} (it omits the 1/2)")

print("\n== 2. full boosters, 300 rounds max, depth 3, eta 0.1, lambda 1, early stopping on validation ==")


def hist_gbdt(Xtr, ytr, Xva, yva, rounds=300, eta=0.1, depth=3, bins=64, patience=30):
    edges = [np.unique(np.quantile(Xtr[:, j], np.linspace(0, 1, bins + 1)[1:-1])) for j in range(Xtr.shape[1])]
    Btr = np.stack([np.searchsorted(edges[j], Xtr[:, j], side="right") for j in range(Xtr.shape[1])], 1)
    Bva = np.stack([np.searchsorted(edges[j], Xva[:, j], side="right") for j in range(Xva.shape[1])], 1)
    base = np.log(ytr.mean() / (1 - ytr.mean()))
    ftr, fva = np.full(len(ytr), base), np.full(len(yva), base)
    best, best_it, trees, hist = np.inf, 0, [], []
    for it in range(rounds):
        p = sig(ftr)
        g, h = p - ytr, p * (1 - p)
        node_tr, node_va = np.zeros(len(ytr), int), np.zeros(len(yva), int)
        splits = {}
        for level in range(depth):                                   # level-wise growth with histograms
            for nd in np.unique(node_tr):
                m = node_tr == nd
                best_gain, best_split = 0.0, None
                G, Hn = g[m].sum(), h[m].sum()
                for j in range(Btr.shape[1]):
                    nb = len(edges[j]) + 1
                    Gb = np.bincount(Btr[m, j], weights=g[m], minlength=nb)
                    Hb = np.bincount(Btr[m, j], weights=h[m], minlength=nb)
                    GL, HL = np.cumsum(Gb)[:-1], np.cumsum(Hb)[:-1]
                    gain = 0.5 * (GL ** 2 / (HL + LAM) + (G - GL) ** 2 / (Hn - HL + LAM) - G ** 2 / (Hn + LAM))
                    gain[(HL < 1e-3) | (Hn - HL < 1e-3)] = 0
                    k = int(np.argmax(gain))
                    if gain[k] > best_gain:
                        best_gain, best_split = gain[k], (j, k)
                if best_split:
                    splits[nd] = best_split
            new_tr, new_va = node_tr * 2, node_va * 2
            for nd, (j, k) in splits.items():
                new_tr[(node_tr == nd) & (Btr[:, j] > k)] += 1
                new_va[(node_va == nd) & (Bva[:, j] > k)] += 1
            node_tr, node_va = new_tr, new_va
            splits = {}
        for nd in np.unique(node_tr):
            m = node_tr == nd
            w = -g[m].sum() / (h[m].sum() + LAM)
            ftr[m] += eta * w
            fva[node_va == nd] += eta * w
        vl = log_loss(yva, sig(fva))
        hist.append(vl)
        if vl < best - 1e-6:
            best, best_it = vl, it + 1
        elif it + 1 - best_it >= patience:
            break
    return best_it, best, hist


t0 = time.perf_counter()
it_ours, ll_ours, _ = hist_gbdt(Xtr, ytr, Xva, yva)
t_ours = time.perf_counter() - t0
params = {"objective": "binary:logistic", "tree_method": "hist", "max_depth": 3, "eta": 0.1, "lambda": 1.0,
          "max_bin": 64, "nthread": 1, "seed": 0}
t0 = time.perf_counter()
bx = xgb.train(params, xgb.DMatrix(Xtr, label=ytr), 300, evals=[(xgb.DMatrix(Xva, label=yva), "va")],
               early_stopping_rounds=30, verbose_eval=False)
t_x = time.perf_counter() - t0
t0 = time.perf_counter()
bl = lgb.train({"objective": "binary", "max_depth": 3, "num_leaves": 8, "learning_rate": 0.1, "lambda_l2": 1.0,
                "max_bin": 64, "min_data_in_leaf": 1, "min_sum_hessian_in_leaf": 1e-3, "num_threads": 1,
                "verbose": -1, "seed": 0},
               lgb.Dataset(Xtr, ytr), 300, valid_sets=[lgb.Dataset(Xva, yva)],
               callbacks=[lgb.early_stopping(30, verbose=False)])
t_l = time.perf_counter() - t0
px = bx.predict(xgb.DMatrix(Xte), iteration_range=(0, bx.best_iteration + 1))
pl = bl.predict(Xte, num_iteration=bl.best_iteration)
print(f"{'booster':18s} {'best round':>10} {'val logloss':>11} {'test logloss':>12} {'test AUC':>9} {'fit s':>6}")
print(f"{'ours (NumPy)':18s} {it_ours:>10} {ll_ours:>11.4f} {'-':>12} {'-':>9} {t_ours:>6.1f}")
print(f"{'xgboost hist':18s} {bx.best_iteration + 1:>10} {bx.best_score:>11.4f} {log_loss(yte, px):>12.4f} "
      f"{roc_auc_score(yte, px):>9.4f} {t_x:>6.2f}")
print(f"{'lightgbm':18s} {bl.best_iteration:>10} {bl.best_score['valid_0']['binary_logloss']:>11.4f} "
      f"{log_loss(yte, pl):>12.4f} {roc_auc_score(yte, pl):>9.4f} {t_l:>6.2f}")
assert abs(ll_ours - bx.best_score) < 0.005

print("\n== 3. shrinkage (xgboost, early stopping on validation) ==")
print(f"{'eta':>5} {'best round':>10} {'test logloss':>12}")
res = {}
for eta in (1.0, 0.3, 0.1, 0.03):
    b = xgb.train({**params, "eta": eta}, xgb.DMatrix(Xtr, label=ytr), 3000, evals=[(xgb.DMatrix(Xva, label=yva), "va")],
                  early_stopping_rounds=50, verbose_eval=False)
    res[eta] = log_loss(yte, b.predict(xgb.DMatrix(Xte), iteration_range=(0, b.best_iteration + 1)))
    print(f"{eta:>5} {b.best_iteration + 1:>10} {res[eta]:>12.4f}")
assert res[0.1] < res[1.0]

print("\n== 4. histogram resolution (xgboost hist, eta 0.1; features have 20 distinct values) ==")
for bins in (16, 64, 256):
    b = xgb.train({**params, "max_bin": bins}, xgb.DMatrix(Xtr, label=ytr), 3000,
                  evals=[(xgb.DMatrix(Xva, label=yva), "va")], early_stopping_rounds=50, verbose_eval=False)
    print(f"max_bin {bins:>3}: test logloss {log_loss(yte, b.predict(xgb.DMatrix(Xte), iteration_range=(0, b.best_iteration + 1))):.4f}")
print("\nALL ASSERTIONS PASSED")
```

Output (verified, except the fit-time column, which is one measured run):

```text
== 1. one depth-2 Newton tree from scratch vs XGBoost (exact, base_score 0.5, eta 1, lambda 1) ==
root split: ours f2 < 10.5, gain 1040.7961; xgboost f2 < 10.5, gain 2081.5920
leaves (value, cover) ours:    [(-0.832501, 1251.25), (-0.073453, 1489.75), (0.626664, 1257.25), (1.188232, 1001.75)]
leaves (value, cover) xgboost: [(-0.832501, 1251.25), (-0.073453, 1489.75), (0.626664, 1257.25), (1.188232, 1001.75)]
max |margin difference| on 20,000 test rows = 5.83e-08
xgboost's reported gain / our 0.5*[...] gain = 2.0000 (it omits the 1/2)

== 2. full boosters, 300 rounds max, depth 3, eta 0.1, lambda 1, early stopping on validation ==
booster            best round val logloss test logloss  test AUC  fit s
ours (NumPy)               67      0.5943            -         -    3.0
xgboost hist               67      0.5943       0.5939    0.7453   0.16
lightgbm                   67      0.5943       0.5939    0.7453   0.16

== 3. shrinkage (xgboost, early stopping on validation) ==
  eta best round test logloss
  1.0          4       0.5964
  0.3         22       0.5941
  0.1         67       0.5939
 0.03        234       0.5940

== 4. histogram resolution (xgboost hist, eta 0.1; features have 20 distinct values) ==
max_bin  16: test logloss 0.5955
max_bin  64: test logloss 0.5939
max_bin 256: test logloss 0.5939

ALL ASSERTIONS PASSED
```

How to read it:

- **Part 1** proves the formulas: identical splits, leaf values and covers, and margins equal to 6e-8.
- **Part 2:** three independent implementations agree on the best round (67) and the validation loss (0.5943). Our NumPy version is ~15× slower than the C++ libraries, which is the expected price of clarity.
- **Part 3:** the η sweep shows the quality plateau from 0.1 down, while the round count (and thus latency) grows 3.5× from η = 0.1 to 0.03.

### 3.3 When trees win, when linear heads win, and what trees cost to serve

```python
"""gbdt_vs_linear_and_latency.py - when trees win, when linear heads win, and what a GBDT costs at serving time.

  1. Tabular features with thresholds and interactions (ticket-escalation risk): LightGBM >> logistic regression.
  2. Dense, rotation-invariant embedding features (CLINC, 20 intents): logistic regression >= LightGBM, far cheaper.
  3. A GBDT over *meta-features* of the router (confidence, margin, entropy, kNN similarity) to predict when it is
     wrong - measured against the free baseline (1 - max probability). Measure before you stack.
  4. Serving latency of LightGBM: one row vs batches, and how it scales with the number of trees.
"""
import os
import time

import lightgbm as lgb
import numpy as np
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import roc_auc_score
from sklearn.preprocessing import StandardScaler

rng = np.random.default_rng(61)
LGB = {"verbose": -1, "num_threads": 1, "seed": 0}

print("== 1. tabular escalation risk (thresholds + interactions) ==")


def tickets(n, r):
    length = r.lognormal(4, 1, n)                    # characters
    prior = r.poisson(1.5, n)                        # prior tickets in 30 days
    age = r.uniform(0, 2000, n)                      # account age (days)
    vip = r.random(n) < 0.1
    hour = r.integers(0, 24, n)
    sent = r.normal(0, 1, n)                         # upstream sentiment score
    z = (-2.5 + 1.8 * (prior >= 3) + 1.2 * ((sent < -1) & (length > 150)) + 1.5 * (vip & (prior >= 1))
         - 1.0 * (age > 1500) + 0.8 * ((hour < 6) | (hour > 21)))
    X = np.c_[length, prior, age, vip, hour, sent]
    return X, (r.random(n) < 1 / (1 + np.exp(-z))).astype(int)


Xa, ya = tickets(30_000, np.random.default_rng(1))
Xb, yb = tickets(30_000, np.random.default_rng(2))
sc = StandardScaler().fit(Xa)
lr = LogisticRegression(max_iter=2000).fit(sc.transform(Xa), ya)
gb = lgb.LGBMClassifier(n_estimators=300, learning_rate=0.05, num_leaves=15, **LGB).fit(Xa, ya)
auc_lr, auc_gb = roc_auc_score(yb, lr.predict_proba(sc.transform(Xb))[:, 1]), roc_auc_score(yb, gb.predict_proba(Xb)[:, 1])
print(f"test AUC: logistic regression {auc_lr:.4f} | LightGBM {auc_gb:.4f}")
assert auc_gb > auc_lr + 0.03

print("\n== 2. dense embedding features: CLINC, first 20 intents, MiniLM 384-d ==")
Z = np.load(os.path.join(os.environ["KB_DATA"], "clinc_minilm.npz"))
mtr, mte = Z["y_train"] < 20, Z["y_test"] < 20
Xtr, ytr, Xte, yte = Z["X_train"][mtr], Z["y_train"][mtr], Z["X_test"][mte], Z["y_test"][mte]
t0 = time.perf_counter()
lr2 = LogisticRegression(C=10, max_iter=3000).fit(Xtr, ytr)
t_lr = time.perf_counter() - t0
t0 = time.perf_counter()
gb2 = lgb.LGBMClassifier(n_estimators=300, learning_rate=0.05, num_leaves=15, **LGB).fit(Xtr, ytr)
t_gb = time.perf_counter() - t0
acc_lr, acc_gb = lr2.score(Xte, yte), gb2.score(Xte, yte)
print(f"test accuracy: logistic regression {acc_lr:.4f} (fit {t_lr:.1f} s) | LightGBM {acc_gb:.4f} (fit {t_gb:.1f} s, "
      f"{gb2.booster_.num_trees():,} trees)")
assert acc_lr >= acc_gb

print("\n== 3. GBDT over meta-features: predicting when the 150-intent router is wrong ==")
full = LogisticRegression(C=10, max_iter=3000).fit(Z["X_train"], Z["y_train"])


def meta(X):
    p = full.predict_proba(X)
    top2 = np.sort(p, 1)[:, -2:]
    cos_nn = np.sort(X @ Z["X_train"].T, 1)[:, -5:]
    return np.c_[top2[:, 1], top2[:, 1] - top2[:, 0], -(p * np.log(p + 1e-12)).sum(1), cos_nn[:, -1], cos_nn.mean(1)], \
        p.argmax(1)


# 'wrong' = misrouted in-scope query OR any out-of-scope query (both should escalate)
Xv = np.vstack([Z["X_val"], Z["X_oos_val"]])
yv = np.r_[Z["y_val"], np.full(len(Z["X_oos_val"]), -1)]
Xt = np.vstack([Z["X_test"], Z["X_oos_test"]])
yt = np.r_[Z["y_test"], np.full(len(Z["X_oos_test"]), -1)]
Mv, pv = meta(Xv)
Mt, pt = meta(Xt)
wrong_v, wrong_t = pv != yv, pt != yt
esc = lgb.LGBMClassifier(n_estimators=200, learning_rate=0.05, num_leaves=7, **LGB).fit(Mv, wrong_v)
auc_maxp = roc_auc_score(wrong_t, -Mt[:, 0])
auc_meta = roc_auc_score(wrong_t, esc.predict_proba(Mt)[:, 1])
print(f"router errors on test (in-scope misroutes + OOS): {wrong_t.mean():.3f} of {len(yt):,} queries")
print(f"AUC for detecting them: 1 - max prob {auc_maxp:.4f} | LightGBM on 5 meta-features {auc_meta:.4f}")
print("-> on this data the stacker adds nothing: a well-regularized LR's max probability is already the signal")
assert auc_maxp > 0.9 and abs(auc_meta - auc_maxp) < 0.01

print("\n== 4. LightGBM serving latency (Booster.predict, 1 thread, one measured run) ==")
print(f"{'trees':>6} {'1 row':>10} {'batch 256 (per row)':>20}")
for n_trees in (50, 200, 800):
    m = lgb.LGBMClassifier(n_estimators=n_trees, learning_rate=0.05, num_leaves=31, **LGB).fit(Xa, ya)
    bst, one, batch = m.booster_, Xb[:1], Xb[:256]
    for _ in range(20):
        bst.predict(one, num_threads=1)
    t0 = time.perf_counter()
    for _ in range(300):
        bst.predict(one, num_threads=1)
    t1 = (time.perf_counter() - t0) / 300
    t0 = time.perf_counter()
    for _ in range(30):
        bst.predict(batch, num_threads=1)
    t2 = (time.perf_counter() - t0) / 30 / 256
    print(f"{n_trees:>6} {t1 * 1e6:>8.0f} us {t2 * 1e6:>17.1f} us")
print("\nALL ASSERTIONS PASSED")
```

Output (verified; fit times and the latency table are one measured run):

```text
== 1. tabular escalation risk (thresholds + interactions) ==
test AUC: logistic regression 0.7175 | LightGBM 0.7599

== 2. dense embedding features: CLINC, first 20 intents, MiniLM 384-d ==
test accuracy: logistic regression 0.9850 (fit 0.1 s) | LightGBM 0.9517 (fit 45.5 s, 4,760 trees)

== 3. GBDT over meta-features: predicting when the 150-intent router is wrong ==
router errors on test (in-scope misroutes + OOS): 0.219 of 5,500 queries
AUC for detecting them: 1 - max prob 0.9644 | LightGBM on 5 meta-features 0.9640
-> on this data the stacker adds nothing: a well-regularized LR's max probability is already the signal

== 4. LightGBM serving latency (Booster.predict, 1 thread, one measured run) ==
 trees      1 row  batch 256 (per row)
    50       37 us               1.9 us
   200       42 us               8.2 us
   800       62 us              32.1 us

ALL ASSERTIONS PASSED
```

---

## 4. The Andrew Ng Lens: Feature Engineering Is Data-Centric Work

### 4.1 For tabular models, the features *are* the data work

Ng's data-centric argument is that improving the data often beats improving the model. For GBDTs on business data, "the data" is largely the feature set: the right aggregation windows, the right joins, the right definitions. The error-analysis spreadsheet (one row per high-loss example, with the feature values that drove the prediction) usually points to a missing or mis-defined feature, not to a hyperparameter:

| High-loss example | Prediction | Truth | Top SHAP features | Hypothesis | Action |
|---|---|---|---|---|---|
| A VIP's first ticket at 3 a.m. | low risk | escalated | `prior=0`, `vip=1`, `hour=3` | The model never saw VIP × night interactions | Add an interaction feature, or more data for that slice |

### 4.2 Bias and variance for trees

- **High bias:** shallow trees, too few rounds, too strong λ/γ. Training loss stays high.
- **High variance:** deep trees or many leaves, a large η without early stopping, a small `min_child_weight`. The train/validation gap grows. Early stopping is the cheapest variance control, and it also bounds serving latency.
- **Data mismatch:** tabular features drift silently (a new product line, a schema change in an upstream table). Folder 07 covers training–serving skew and PSI monitoring.

### 4.3 Evaluation-driven development for tree models

Freeze a time-based split *before* tuning (train on the past, validate on the next period), because random splits leak the future through time-correlated features. Report the metric at the decision threshold the business will use, not only AUC.

---

## 5. Failure Modes

| # | Symptom | Signature | Root cause | Fix | Prevention |
|---|---|---|---|---|---|
| F1 | GBDT on embeddings is slow and worse than LR | Thousands of trees, lower accuracy (0.952 vs 0.985) | Axis-aligned splits vs oblique information (§1.2) | Linear/MLP head on embeddings; trees on engineered features | Baseline LR before any GBDT on dense features |
| F2 | Train AUC 0.99, production 0.70 | Deep trees, no early stopping, random split on time-ordered data | Variance + leakage | Time-based validation, early stopping, depth/leaf limits | Validation protocol frozen before tuning |
| F3 | Leaf counts look fine but `min_child_weight` blocks splits | Few splits on confident regions | `min_child_weight` bounds the hessian sum, not rows | Lower it, or understand that H = Σp(1−p) is small there | Read the parameter docs. Covers are hessian sums |
| F4 | Feature-importance "gain" doesn't match a hand calculation | Off by 2× | XGBoost's reported gain omits the ½ | Compare like with like | Use SHAP values for explanations |
| F5 | Latency creeps up after each retrain | Tree count grows when η is lowered without a cap | Shrinkage without early stopping | Early stopping + a max rounds budget | A latency test on the exported model in CI |
| F6 | Risk score goes down as a risk factor goes up | Non-monotone partial dependence | No monotone constraint; noise in sparse regions | `monotone_constraints` | Policy review of every guardrail/risk feature's direction |
| F7 | Missing values misrouted | NaN imputed as 0 | 0 is a real value for the feature | Leave NaNs: GBDTs learn default directions | A schema-level null policy |
| F8 | Forest doesn't improve when adding trees | Var plateau at ρσ² | Trees highly correlated (all use the same top feature) | Lower `max_features`, add feature diversity | Track the tree correlation diagnostic |
| F9 | LightGBM overfits a small dataset badly | Deep leaf-wise branches | `num_leaves` too large, no `max_depth` | Constrain `max_depth`, raise `min_data_in_leaf` | Defaults reviewed for small-n problems |
| F10 | A meta-model "improves" offline but not in production | It was trained on the base model's training-set predictions | Overconfident in-sample base predictions | Train stackers on out-of-fold or validation predictions | Stacking always uses held-out base predictions |

---

## 6. Bar-Raiser Q&A Chains

<details><summary><b>Q1 · "Derive XGBoost's leaf weight and split gain."</b></summary>

**Initial Prompt.** A whiteboard question for an ML-infra candidate.

**L5 Answer.** "Each leaf predicts the average residual, and gain is the reduction in loss."

**Why L5 Fails in Production.** That's first-order boosting with squared loss. It doesn't explain λ, the hessian-based cover, `min_child_weight`, or why XGBoost converges faster on log-loss.

**L7 Principal Defense.** "Expand the loss to second order around the current predictions: Σ[gᵢ f(xᵢ) + ½hᵢ f(xᵢ)²] + ½λΣw_j² + γT. A tree gives each leaf a constant w_j, so the objective separates per leaf into G_j w_j + ½(H_j + λ)w_j². The minimum is at w_j* = −G_j/(H_j + λ), a Newton step, and the objective there is −½G_j²/(H_j + λ). The gain of a split is the improvement ½[G_L²/(H_L+λ) + G_R²/(H_R+λ) − G²/(H+λ)] − γ. For log-loss, g = p − y and h = p(1 − p). We built a depth-2 tree from exactly these formulas and matched XGBoost's leaf values and covers, with margins equal to 6e-8. XGBoost reports twice our gain because it drops the ½."

**Bar-Raiser Follow-ups.**
- *"What does `min_child_weight` bound?"* H_j, the hessian sum, not the row count. Confident regions have tiny h, so leaves need many rows to pass it.
- *"Role of λ?"* L2 on leaf weights. It shrinks w* toward 0 most for leaves with small H (few or confident rows): built-in regularization.

</details>

<details><summary><b>Q2 · "Should we use XGBoost on our sentence embeddings for intent classification?"</b></summary>

**Initial Prompt.** A team reads that GBDTs win Kaggle and proposes LightGBM on 384-d MiniLM vectors.

**L5 Answer.** "Yes, GBDTs are state of the art for classification."

**Why L5 Fails in Production.** They're state of the art on *tabular* data. Embeddings are dense, rotation-invariant, and their information is oblique, which is the worst case for axis-aligned splits.

**L7 Principal Defense.** "On 20 CLINC intents, LightGBM reached 0.952 with 4,760 trees and a 46.5 s fit. Logistic regression reached 0.985 in 0.1 s. The reason is geometric: each split is perpendicular to one coordinate, and a single oblique class boundary needs a staircase of splits. Use a linear (or small MLP) head on the embeddings, and keep GBDTs for features with individual meaning: counts, recency, amounts, model scores."

**Bar-Raiser Follow-ups.**
- *"Ever a good idea?"* On a *few* derived scalars from embeddings (cosine to a prototype, a cluster id, a distance-to-centroid), mixed with tabular features. Those are meaningful individually.

</details>

<details><summary><b>Q3 · "Why does a random forest generalize better than one deep tree, and why do more trees eventually stop helping?"</b></summary>

**Initial Prompt.** An interviewer probing ensemble intuition.

**L5 Answer.** "Averaging reduces overfitting; more trees are always better."

**Why L5 Fails in Production.** It misses the correlation floor, so it can't explain the plateau, or why `max_features` matters more than `n_estimators`.

**L7 Principal Defense.** "Var(average of B trees) = ρσ² + (1 − ρ)σ²/B. More trees kill only the second term, so the floor is ρσ². Feature subsampling lowers ρ at the cost of a higher per-tree σ². In our 40-training-set experiment, max_features = 0.3 raised σ² from 9.34 to 13.77 but cut ρ from 0.111 to 0.040, and forest variance fell from 1.20 to 0.81. So tune `max_features` (diversity) first, then add trees until validation plateaus. The same law explains why LLM self-consistency voting helps less than you'd hope: samples from one model are correlated."

**Bar-Raiser Follow-ups.**
- *"Bias of a forest?"* About the bias of one tree. Averaging doesn't fix a structural inability to represent the target. Boosting attacks bias instead.

</details>

<details><summary><b>Q4 · "How do you choose the learning rate and number of trees?"</b></summary>

**Initial Prompt.** Tuning a LightGBM risk model.

**L5 Answer.** "Grid search both."

**Why L5 Fails in Production.** It treats them as independent, when they trade off directly. It also ignores that the tree count is serving latency.

**L7 Principal Defense.** "Fix η around 0.05–0.1, give a generous round budget, and early-stop on a time-based validation split. Our sweep: η = 1.0 stopped at 4 rounds (test log-loss 0.5964), 0.1 at 67 (0.5939), 0.03 at 234 (0.5940). Quality plateaus from 0.1 down, while the round count grows 3.5× from 0.1 to 0.03, and so does prediction cost (per-row batch cost grew from 1.9 µs at 50 trees to 32 µs at 800). So pick the largest η on the plateau, and write the tree count into the latency budget."

**Bar-Raiser Follow-ups.**
- *"Then tune what?"* `num_leaves` or `max_depth`, `min_child_weight`/`min_data_in_leaf`, and feature subsampling, with early stopping on, against the business metric.

</details>

<details><summary><b>Q5 · "Our team built a GBDT that predicts when the router is wrong. Offline it's great. Should we deploy it?"</b></summary>

**Initial Prompt.** A stacker over router meta-features (confidence, margin, entropy, neighbour similarity).

**L5 Answer.** "Yes, a better error predictor means a better escalation policy."

**Why L5 Fails in Production.** It's "great" compared to what? Without the free baseline, you can't tell whether the stacker adds anything, and a stacker trained on in-sample base predictions is overconfident.

**L7 Principal Defense.** "Compare it to 1 − max probability of the calibrated router, which is free. On CLINC, a LightGBM over five meta-features gave AUC 0.9640 vs 0.9644 for max probability alone: no gain, and an extra model to maintain. Stackers win when they bring *new information* (user history, request channel, upstream latency, retrieval scores), not when they re-describe the base model's confidence. And they must be trained on out-of-fold or validation predictions, never the base model's training-set outputs."

**Bar-Raiser Follow-ups.**
- *"What would you add to make it worth it?"* Signals the router can't see: conversation turn, user tier, whether the query contains entities absent from training data, and time since the last intent schema change.

</details>

<details><summary><b>Q6 · "Serve a 500-tree LightGBM model at p99 < 1 ms inside a Python API."</b></summary>

**Initial Prompt.** A fraud/risk score called on every request.

**L5 Answer.** "Load the model and call predict per request."

**Why L5 Fails in Production.** It probably works, but leaves headroom on the table and ignores the per-call overhead and tail effects.

**L7 Principal Defense.** "Our single-row `Booster.predict` was 37–62 µs for 50–800 trees, most of it fixed overhead. 500 trees is comfortably under 1 ms. To harden the tail: num_threads = 1 per call (thread fan-out hurts small batches), micro-batch where traffic allows (the per-row cost falls to ~1.9–32 µs), cap the trees with early stopping, and, if it's on a very hot path, compile it (Treelite or lleaves) or convert to ONNX and serve it next to the encoder. Then load-test p99 with production feature vectors, not synthetic ones."

**Bar-Raiser Follow-ups.**
- *"What dominates end-to-end?"* Usually the feature fetch (an online-store lookup, Folder 07), not the trees.

</details>

<details><summary><b>Q7 · "Explain gradient boosting to a backend engineer in one minute."</b></summary>

**Initial Prompt.** A communication question.

**L5 Answer.** "It's an ensemble of trees that are trained sequentially."

**Why L5 Fails in Production.** It's accurate and has no mechanism. The listener can't reason about learning rate, early stopping or overfitting.

**L7 Principal Defense.** "Think of patches. Start from a constant prediction. Compute, for each training row, how the loss would like that row's prediction to move: the gradient, which for classification is literally 'predicted probability minus label'. Fit a small tree that approximates those desired moves, apply a fraction of it (the learning rate), and repeat. Each tree patches the remaining errors. XGBoost also uses the curvature, so each leaf takes a Newton step, −G/(H + λ). Early stopping is 'stop shipping patches when the validation set stops improving'."

**Bar-Raiser Follow-ups.**
- *"Why small trees?"* Each patch should be simple and only partly trusted (shrinkage). Deep trees overfit within a single round.

</details>

<details><summary><b>Q8 · "Why do tree models still beat deep learning on tabular data?"</b></summary>

**Initial Prompt.** A design debate about replacing a GBDT churn model with a neural network.

**L5 Answer.** "Neural networks need more data."

**Why L5 Fails in Production.** Partly true, but it misses the inductive-bias argument that also tells you when a neural network *would* win.

**L7 Principal Defense.** "Tabular features are individually meaningful and often have irregular, threshold-like effects. Trees model exactly that with axis-aligned splits. Neural networks are biased toward smooth, rotation-invariant functions. Grinsztajn et al. (2022) document trees outperforming deep models on medium-sized tabular benchmarks, attributing it partly to uninformative features and irregular target functions. Our own split shows both sides: GBDT wins on threshold/interaction tabular data (AUC 0.760 vs LR 0.718), LR wins on embeddings (0.985 vs 0.952). A neural network wins when the input is unstructured (text, images) or when you need learned representations of high-cardinality entities. Then the usual pattern is embeddings from the network, fed as features to a GBDT, or the reverse."

**Bar-Raiser Follow-ups.**
- *"Hybrid?"* Yes: text embeddings → a small linear head → its probability as one feature in the GBDT next to the tabular ones.

</details>

---

## 7. Invariants Checklist

- [ ] GBDTs consume engineered features (counts, recency, amounts, model scores). Dense embeddings go to linear or MLP heads.
- [ ] Every GBDT uses early stopping on a time-based (or otherwise leakage-safe) validation split, with a hard round cap.
- [ ] The tree count and depth are part of the latency budget, measured on the exported model in CI.
- [ ] Risk and guardrail models declare monotone constraints for features with a known direction.
- [ ] NaNs are left as NaN (learned default directions) unless the schema says otherwise.
- [ ] Stackers are trained on out-of-fold or validation base predictions and beat the free baseline (max probability) before deployment.
- [ ] Explanations use SHAP or another documented method, not raw split "gain" (which is scaled 2× in XGBoost).
- [ ] Forests tune `max_features` (decorrelation) before `n_estimators`.

---

## 8. References

1. L. Breiman, *Random Forests*, Machine Learning 45, 2001. DOI 10.1023/A:1010933404324.
2. J. Friedman, *Greedy Function Approximation: A Gradient Boosting Machine*, Annals of Statistics 29(5), 2001. DOI 10.1214/aos/1013203451.
3. T. Chen, C. Guestrin, *XGBoost: A Scalable Tree Boosting System*, KDD 2016. https://arxiv.org/abs/1603.02754
4. G. Ke et al., *LightGBM: A Highly Efficient Gradient Boosting Decision Tree*, NeurIPS 2017. https://papers.nips.cc/paper/6907-lightgbm-a-highly-efficient-gradient-boosting-decision-tree
5. L. Grinsztajn, E. Oyallon, G. Varoquaux, *Why do tree-based models still outperform deep learning on tabular data?*, NeurIPS 2022 Datasets & Benchmarks. https://arxiv.org/abs/2207.08815
6. XGBoost documentation, *Parameters* and *Introduction to Boosted Trees*. https://xgboost.readthedocs.io/en/stable/tutorials/model.html
7. LightGBM documentation, *Parameters* and *Features* (leaf-wise growth, GOSS, EFB, categorical splits). https://lightgbm.readthedocs.io/en/stable/Features.html
8. scikit-learn user guide, *Decision Trees* and *Ensembles*. https://scikit-learn.org/stable/modules/tree.html
9. S. Lundberg, S.-I. Lee, *A Unified Approach to Interpreting Model Predictions* (SHAP), NeurIPS 2017. https://arxiv.org/abs/1705.07874
10. Treelite (compiled tree-model inference). https://treelite.readthedocs.io/
