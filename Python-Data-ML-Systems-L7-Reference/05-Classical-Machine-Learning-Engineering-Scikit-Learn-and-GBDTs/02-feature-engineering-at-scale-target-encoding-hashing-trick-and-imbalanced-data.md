# 05.2 · Feature Engineering at Scale: Target Encoding, the Hashing Trick & Imbalanced Data

> **Folder 05 · Classical Machine Learning Engineering: scikit-learn & GBDTs**
> **Measured on:** scikit-learn 1.9.1 (`OneHotEncoder`, `FeatureHasher`, `TargetEncoder`, `CalibratedClassifierCV`), SciPy sparse CSR, CPython 3.14.5, i5-11260H, Windows 11.
> **Design sources:** scikit-learn user guide (categorical encoding, TargetEncoder cross-fitting, calibration), and Weinberger et al. on feature hashing.

---

## 0. Orientation & the JVM/C++ Bridge

Two problems dominate tabular ML at scale. The first is **high-cardinality categoricals** (merchant, URL, device, SKU), where the representation decides memory, speed and whether the model leaks. The second is **rare positives** (fraud, churn, clicks), where the metric, the loss weighting and the probability calibration decide whether a model with "99 % accuracy" is useless. Both are engineering decisions with measurable physics.

| Technique | Representation | Memory per row | Handles unseen? | Leakage risk |
|---|---|---|---|---|
| One-hot (sparse CSR) | 1 non-zero per categorical | 4 B value + 4 B index (+ row pointer) | `handle_unknown="ignore"` → zeros | none |
| Hashing trick | `hash(value) % m` columns | same as one-hot; width fixed at m | yes (hashes anywhere) | none; collisions merge levels |
| Target / mean encoding | 1 float: P(y \| level) | 8 B | falls back to the prior | **high unless cross-fitted** |
| Embeddings (NN) | learned d-dim vector | 4·d B | OOV bucket | trained jointly |

🧊 The hashing trick is the same idea as a Count-Min sketch or Bloom filter column (fixed memory, collisions traded for boundedness). Target encoding is a group-by aggregate, and like any aggregate it leaks if it includes the row being predicted.

---

## 1. First Principles: C Memory Layout & Execution Architecture

### 1.1 Sparse one-hot in CSR

```text
 n rows, one categorical with L levels -> shape (n, L), one non-zero per row
 CSR: data[nnz] (float32: 4 B), indices[nnz] (int32: 4 B), indptr[n+1] (int32/64)
 140k rows x 7,838 levels: 1.6 MiB (measured), against 140k x 7,838 x 4 B = 4.1 GiB dense
 a linear model's matvec touches only the non-zeros: cost O(nnz), not O(n·L)
```

### 1.2 Hashing: fixed width, collisions by the birthday bound

```text
 column = murmurhash3(value) mod m   (FeatureHasher; alternate_sign optionally flips sign to cancel collisions)
 occupied buckets = m·(1 - exp(-L/m)); levels landing in an already-occupied bucket = L - occupied ≈ L²/(2m)
 L = 7,838 train levels, m = 2^16 -> 5.7 % predicted; 5.6 % measured (7,399 buckets used)
 no vocabulary to store or ship: the transform is stateless (works across services and languages)
```

### 1.3 Target encoding and cross-fitting

```text
 naive:   enc(level) = mean(y | level) over ALL training rows -> each row's own label is inside its feature
          rare levels: enc = that row's label exactly -> the model learns "feature == label"
 smoothed: enc = (n·mean + m·prior)/(n + m)      (shrinks rare levels toward the global rate)
 cross-fit (sklearn TargetEncoder.fit_transform): K folds; rows in fold k get encodings computed
          WITHOUT fold k -> no row sees its own label; transform() at serving uses all training data
```

Measured on a Zipf-distributed 50 k-level merchant column (9.8 k levels seen): the naive encoder gave train AUC 0.845 against holdout 0.700, a **0.145 gap** and the *worst* holdout of all four methods. Cross-fitted `TargetEncoder` gave 0.766 / 0.728 (gap 0.038), matching one-hot and hashing with a 2-column feature matrix.

### 1.4 Imbalanced classes: what changes and what doesn't

```text
 class_weight / resampling change the TRAINING objective's prior:
   ranking (ROC-AUC, PR-AUC): nearly unchanged
   probabilities: shifted toward the reweighted prior -> miscalibrated
 undersampling negatives by beta: p_true = beta·p / (beta·p - p + 1)   (Bayes prior correction)
 calibration: isotonic or sigmoid fit on held-out folds (CalibratedClassifierCV)
 decision: choose the threshold from the PR curve for the business constraint, never 0.5 by default
```

---

## 2. The Slow Pythonic Trap vs. the L7 Production Pattern

### 2.1 A 50,000-level categorical, four ways

```python
"""target_encoding_hashing.py - a 50,000-level categorical four ways: one-hot, hashing, leaky and cross-fitted target encoding.

Merchants follow a Zipf distribution (a few huge, a long tail of rare ones); each has a latent fraud rate.
Reports feature width, bytes, fit time and train vs holdout ROC-AUC. The leaky encoder computes each merchant's
mean label on the same rows the model trains on; sklearn's TargetEncoder cross-fits (out-of-fold means) + smooths.
"""
import time
import warnings

import numpy as np
import pandas as pd
from sklearn.ensemble import HistGradientBoostingClassifier
from sklearn.feature_extraction import FeatureHasher
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import roc_auc_score
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import OneHotEncoder, TargetEncoder

warnings.filterwarnings("ignore")
rng = np.random.default_rng(0)
N, LEVELS = 200_000, 50_000
merchant = np.minimum(rng.zipf(1.3, N), LEVELS) - 1
risk = rng.beta(1, 30, LEVELS)                            # latent per-merchant fraud rate, mean ~3%
amount = rng.lognormal(3, 1, N)
p = np.clip(risk[merchant] * (1 + 0.3 * (amount > 60)), 0, 1)
y = (rng.random(N) < p).astype(int)
df = pd.DataFrame({"merchant": merchant.astype(str), "amount": amount})
Xtr, Xte, ytr, yte = train_test_split(df, y, test_size=0.3, random_state=0, stratify=y)
print(f"{N:,} rows, {LEVELS:,} possible merchants ({df['merchant'].nunique():,} seen), positive rate {y.mean():.3%}")
seen_test = Xte["merchant"].isin(set(Xtr["merchant"])).mean()
print(f"holdout rows whose merchant appears in train: {seen_test:.1%}")


def nbytes_sparse(m):
    return m.data.nbytes + m.indices.nbytes + m.indptr.nbytes


def evaluate(label, fit_fn, train_X, test_X, width, nbytes):
    t0 = time.perf_counter()
    model = fit_fn(train_X)
    dt = time.perf_counter() - t0
    auc_tr = roc_auc_score(ytr, model.predict_proba(train_X)[:, 1])
    auc_te = roc_auc_score(yte, model.predict_proba(test_X)[:, 1])
    print(f"  {label:36} {width:>8,} {nbytes / 2**20:8.1f} {dt:7.2f}s {auc_tr:8.3f} {auc_te:8.3f} {auc_tr - auc_te:+7.3f}")
    return auc_tr, auc_te


print(f"  {'encoding':36} {'features':>8} {'MiB':>8} {'fit':>8} {'trainAUC':>8} {'testAUC':>8} {'gap':>7}")
res = {}
ohe = OneHotEncoder(handle_unknown="ignore", sparse_output=True, dtype=np.float32).fit(Xtr[["merchant"]])
A, B = ohe.transform(Xtr[["merchant"]]), ohe.transform(Xte[["merchant"]])
res["onehot"] = evaluate("one-hot (sparse CSR) + logistic", lambda X: LogisticRegression(C=0.1, max_iter=300).fit(X, ytr),
                         A, B, A.shape[1], nbytes_sparse(A))
fh = FeatureHasher(n_features=2**16, input_type="string", alternate_sign=False)
H = fh.transform(Xtr[["merchant"]].to_numpy().tolist())
Ht = fh.transform(Xte[["merchant"]].to_numpy().tolist())
distinct = Xtr["merchant"].nunique()
used = np.unique(H.indices).size
res["hash"] = evaluate("hashing 2^16 + logistic", lambda X: LogisticRegression(C=0.1, max_iter=300).fit(X, ytr),
                       H, Ht, 2**16, nbytes_sparse(H))
print(f"    hashing: {distinct:,} train levels landed in {used:,} buckets ({1 - used / distinct:.1%} collided)")


def leaky_encode(train, test):
    means = pd.Series(ytr, index=train.index).groupby(train["merchant"]).mean()
    enc = lambda d: np.column_stack([d["merchant"].map(means).fillna(ytr.mean()), d["amount"]])
    return enc(train), enc(test)


Ltr, Lte = leaky_encode(Xtr, Xte)
hgb = lambda X: HistGradientBoostingClassifier(max_iter=200, random_state=0).fit(X, ytr)
res["leaky"] = evaluate("naive mean-target encoding + HGB", hgb, Ltr, Lte, 2, Ltr.nbytes)
te = TargetEncoder(target_type="binary", smooth="auto", cv=5, random_state=0)
Ttr = np.column_stack([te.fit_transform(Xtr[["merchant"]], ytr), Xtr["amount"]])   # out-of-fold encodings
Tte = np.column_stack([te.transform(Xte[["merchant"]]), Xte["amount"]])
res["cross"] = evaluate("TargetEncoder (cross-fit) + HGB", hgb, Ttr, Tte, 2, Ttr.nbytes)
assert res["leaky"][0] - res["leaky"][1] > res["cross"][0] - res["cross"][1] + 0.05
print("ALL ASSERTIONS PASSED")
```

Output (one measured run):

```text
200,000 rows, 50,000 possible merchants (9,854 seen), positive rate 2.454%
holdout rows whose merchant appears in train: 96.3%
  encoding                             features      MiB      fit trainAUC  testAUC     gap
  one-hot (sparse CSR) + logistic         7,838      1.6    0.11s    0.753    0.729  +0.024
  hashing 2^16 + logistic                65,536      2.1    0.23s    0.753    0.728  +0.024
    hashing: 7,838 train levels landed in 7,399 buckets (5.6% collided)
  naive mean-target encoding + HGB            2      2.1    0.40s    0.845    0.700  +0.145
  TargetEncoder (cross-fit) + HGB             2      2.1    0.25s    0.766    0.728  +0.038
ALL ASSERTIONS PASSED
```

* One-hot (1.6 MiB CSR) and 2^16 hashing (2.1 MiB) reach the same holdout AUC (0.728–0.729). Hashing needs no vocabulary and handles unseen merchants by construction.
* The **naive target encoding is the trap**: best training score, worst holdout, the classic overfit-by-construction.
* Cross-fitted `TargetEncoder` + gradient boosting matches the sparse models with 2 dense features, a good fit for tree models, which handle a single informative numeric feature far better than 8 k sparse columns.

### 2.2 1 % positives: metrics, weighting, resampling, calibration, thresholds

```python
"""imbalanced_metrics.py - 1% positives: which metrics lie, what class weights and resampling really do, and calibration.

A: the accuracy paradox and ROC-AUC vs PR-AUC (average precision) for a weak and a good model.
B: class_weight='balanced' and 10x undersampling: ranking barely changes, probabilities do.
C: restoring probabilities: prior correction for undersampling, and isotonic calibration (Brier, ECE).
D: choosing a threshold for a precision target instead of 0.5.
"""
import time
import warnings

import numpy as np
from sklearn.calibration import CalibratedClassifierCV
from sklearn.datasets import make_classification
from sklearn.ensemble import HistGradientBoostingClassifier
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import accuracy_score, average_precision_score, brier_score_loss, precision_recall_curve, roc_auc_score
from sklearn.model_selection import train_test_split

warnings.filterwarnings("ignore")
X, y = make_classification(n_samples=300_000, n_features=30, n_informative=8, weights=[0.99], flip_y=0.002,
                           class_sep=0.8, random_state=0)
Xtr, Xte, ytr, yte = train_test_split(X, y, test_size=0.3, stratify=y, random_state=0)
print(f"{len(y):,} rows, positive rate {y.mean():.2%}")


def ece(y_true, p, bins=15):
    edges = np.quantile(p, np.linspace(0, 1, bins + 1))
    idx = np.clip(np.searchsorted(edges, p, side="right") - 1, 0, bins - 1)
    return sum(abs(y_true[idx == b].mean() - p[idx == b].mean()) * (idx == b).mean() for b in range(bins) if (idx == b).any())


def report(label, p, extra=""):
    print(f"  {label:40} ROC-AUC {roc_auc_score(yte, p):.3f}  PR-AUC {average_precision_score(yte, p):.3f}  "
          f"Brier {brier_score_loss(yte, p):.4f}  ECE {ece(yte, p):.4f}  mean p {p.mean():.4f}{extra}")


print("== A. metrics on 1% positives")
print(f"  always predict 0: accuracy {accuracy_score(yte, np.zeros_like(yte)):.3f} (useless model, 'great' accuracy)")
weak = LogisticRegression(max_iter=1000).fit(Xtr[:, 20:], ytr)          # linear model on 10 of the 30 features
good = HistGradientBoostingClassifier(max_iter=300, random_state=0).fit(Xtr, ytr)
p_weak, p_good = weak.predict_proba(Xte[:, 20:])[:, 1], good.predict_proba(Xte)[:, 1]
report("logistic on 10 of 30 features", p_weak)
report("HistGradientBoosting", p_good)

print("== B. class_weight='balanced' and undersampling (same model family)")
t0 = time.perf_counter()
bal = HistGradientBoostingClassifier(max_iter=300, class_weight="balanced", random_state=0).fit(Xtr, ytr)
t_bal = time.perf_counter() - t0
p_bal = bal.predict_proba(Xte)[:, 1]
rng = np.random.default_rng(0)
neg = np.flatnonzero(ytr == 0)
keep = np.concatenate([np.flatnonzero(ytr == 1), rng.choice(neg, neg.size // 10, replace=False)])
t0 = time.perf_counter()
under = HistGradientBoostingClassifier(max_iter=300, random_state=0).fit(Xtr[keep], ytr[keep])
t_under = time.perf_counter() - t0
p_under = under.predict_proba(Xte)[:, 1]
report("class_weight='balanced'", p_bal, f"  fit {t_bal:.1f}s")
report("10x undersampled negatives", p_under, f"  fit {t_under:.1f}s on {keep.size:,} rows")

print("== C. getting calibrated probabilities back")
beta = 0.1                                                               # fraction of negatives kept
p_fixed = beta * p_under / (beta * p_under - p_under + 1)                # Bayes prior correction
report("undersampled + prior correction", p_fixed)
iso = CalibratedClassifierCV(HistGradientBoostingClassifier(max_iter=300, class_weight="balanced", random_state=0),
                             method="isotonic", cv=3).fit(Xtr, ytr)
report("balanced + isotonic calibration (cv=3)", iso.predict_proba(Xte)[:, 1])

print("== D. pick the threshold for a business constraint, not 0.5")
prec, rec, thr = precision_recall_curve(yte, p_good)
ok = np.flatnonzero(prec[:-1] >= 0.80)
i = ok[np.argmax(rec[ok])]
print(f"  threshold 0.5        : precision {((p_good >= .5) & (yte == 1)).sum() / max((p_good >= .5).sum(), 1):.3f}, "
      f"recall {((p_good >= .5) & (yte == 1)).sum() / yte.sum():.3f}")
print(f"  precision >= 0.80    : threshold {thr[i]:.3f}, recall {rec[i]:.3f}")
assert average_precision_score(yte, p_good) > average_precision_score(yte, p_weak)
assert brier_score_loss(yte, p_fixed) < brier_score_loss(yte, p_under)
print("ALL ASSERTIONS PASSED")
```

Output (one measured run):

```text
300,000 rows, positive rate 1.09%
== A. metrics on 1% positives
  always predict 0: accuracy 0.989 (useless model, 'great' accuracy)
  logistic on 10 of 30 features            ROC-AUC 0.866  PR-AUC 0.427  Brier 0.0080  ECE 0.0019  mean p 0.0108
  HistGradientBoosting                     ROC-AUC 0.954  PR-AUC 0.790  Brier 0.0041  ECE 0.0006  mean p 0.0109
== B. class_weight='balanced' and undersampling (same model family)
  class_weight='balanced'                  ROC-AUC 0.950  PR-AUC 0.814  Brier 0.0210  ECE 0.0768  mean p 0.0877  fit 13.7s
  10x undersampled negatives               ROC-AUC 0.951  PR-AUC 0.833  Brier 0.0048  ECE 0.0124  mean p 0.0233  fit 0.7s on 23,065 rows
== C. getting calibrated probabilities back
  undersampled + prior correction          ROC-AUC 0.951  PR-AUC 0.833  Brier 0.0034  ECE 0.0020  mean p 0.0091
  balanced + isotonic calibration (cv=3)   ROC-AUC 0.949  PR-AUC 0.815  Brier 0.0036  ECE 0.0003  mean p 0.0110
== D. pick the threshold for a business constraint, not 0.5
  threshold 0.5        : precision 0.854, recall 0.660
  precision >= 0.80    : threshold 0.352, recall 0.691
ALL ASSERTIONS PASSED
```

* **Accuracy is meaningless here**: predicting "never fraud" scores 0.989. ROC-AUC flatters too: the weaker model's ROC-AUC 0.866 hides a PR-AUC of 0.427, while a good model shows 0.954 / 0.790. Use PR-AUC (average precision), precision@k or cost-weighted metrics for rare positives.
* `class_weight="balanced"` barely moved ranking (ROC-AUC 0.950) but **wrecked calibration**: mean predicted probability 0.088 against a true rate of 0.011, Brier 0.021 vs 0.004. It also took ~14 s versus well under 1 s on the undersampled set.
* **10× undersampling** trained ~20× faster on 23 k rows with the best PR-AUC here (0.833), and its probabilities are fixed exactly by the prior correction (mean p 0.0091, Brier 0.0034, the best calibration of any variant). Isotonic calibration on the balanced model also recovered calibration (ECE 0.0003).
* **Thresholds:** 0.5 gave precision 0.854 and recall 0.660. Requiring precision ≥ 0.80 moved the threshold to 0.35 and recall to 0.69.

---

## 3. Production Failure Modes & Debugging

| # | Symptom | Signature | Root cause | Fix | Prevention |
|---|---|---|---|---|---|
| F1 🔥 | Model great in training, poor on holdout or production | Large train–test gap; high-cardinality feature dominates importances | Target encoding without cross-fitting | `TargetEncoder` (cross-fit) or out-of-fold encoding in the pipeline | Inspect train vs CV gaps per feature |
| F2 🔥 | Probabilities 5–10× too high; downstream expected-loss calculations wrong | Mean prediction ≫ base rate | class weights or resampling without correction | Prior correction or calibration on unweighted held-out data | Track ECE / Brier / mean p vs base rate |
| F3 | "99.9 % accurate" fraud model catches nothing | Recall ~0 at threshold 0.5 | Accuracy metric + default threshold on rare positives | PR-AUC, precision@k; tune the threshold to the constraint | Metric spec per use case |
| F4 | Memory blow-up building features | Dense one-hot matrix | `sparse_output=False` with thousands of levels | Keep CSR sparse; hashing for unbounded vocabularies | Assert sparsity of wide features |
| F5 | New categories crash serving | Unknown-category errors | Vocabulary-based encoder without unknown handling | `handle_unknown="ignore"`, hashing, `"infrequent_if_exist"` | Contract tests with unseen values |
| F6 | Silent quality loss as the vocabulary grows | Hash buckets saturated | Collisions rise as L approaches m | Increase m (2^20+), use signed hashing, monitor bucket occupancy | Re-estimate L²/2m quarterly |
| F7 | Encodings drift between batch and online | Mismatched means for the same level | Separate implementations or update schedules | One fitted encoder artifact (or a feature store) for both | Training/serving parity tests |
| F8 ⚡ | Weighted training too slow | Long fits with `class_weight` | All negatives still processed | Undersample negatives + prior correction (~20× fewer rows here) | Compare PR-AUC and calibration, not just speed |

**Debugging toolkit.** `X.nnz`, `X.data.nbytes + X.indices.nbytes + X.indptr.nbytes` for sparse memory. `TargetEncoder.encodings_`, `categories_` and `target_mean_`. `average_precision_score`, `precision_recall_curve`, `brier_score_loss`, and `sklearn.calibration.calibration_curve` for reliability diagrams. Bucket occupancy (`np.unique(H.indices).size`) for hashing.

---

## 4. L7 Bar-Raiser Q&A Chains

<details><summary><b>Q1 · "How do you encode a categorical with 10 million distinct values?"</b></summary>

**Initial Prompt.** Ad-click prediction with `url` (10 M values, long tail) and `advertiser_id` (50 k).

**L5 Answer.** "One-hot encode everything."

**Why L5 Crashes at Scale.** A 10 M-column vocabulary must be stored, shipped to every server and updated as new URLs appear, and unseen URLs at serving time either crash or are silently ignored. With a dense matrix, memory explodes.

**L7 Principal Defense.** Use the hashing trick for `url`: fixed width (2^20–2^24), stateless (any service in any language computes the same columns), unseen values handled by construction. Size m from the birthday bound (measured 5.6 % of levels in an occupied bucket at L/m ≈ 0.12, consistent with L/(2m)). Use cross-fitted target encoding or learned embeddings for `advertiser_id`, plus count features and "rare" bucketing. Keep everything sparse (CSR) for linear models, or dense low-dimensional encodings for GBDTs. Monitor bucket occupancy as the vocabulary grows.

</details>

<details><summary><b>Q2 · "Target encoding improved validation AUC by 5 points. Why are you suspicious?"</b></summary>

**Initial Prompt.** A Kaggle-style notebook computes `df.groupby('merchant').label.mean()` and maps it back as a feature.

**L5 Answer.** "Target encoding is a known good technique."

**Why L5 Crashes at Scale.** Computed on the same rows the model trains on, each row's encoding contains its own label, and for rare levels it *is* the label. The model learns a shortcut that doesn't exist at serving time. Measured: train AUC 0.845 against holdout 0.700, worse than plain one-hot.

**L7 Principal Defense.** Cross-fit. For training rows, encodings come from the other folds (`TargetEncoder.fit_transform`), with smoothing toward the prior for rare levels. At serving time, use encodings computed on all training data (`transform`). Validate with the train–holdout gap (0.038 cross-fitted vs 0.145 naive, measured). For temporal data, compute encodings only from past data (point-in-time, 03.4), or the leak returns through time.

</details>

<details><summary><b>Q3 · "We used `class_weight='balanced'` and now the probabilities are useless for pricing. Explain."</b></summary>

**Initial Prompt.** An insurer prices risk as `premium = p(claim) × cost`.

**L5 Answer.** "The model is underfit; add features."

**Why L5 Crashes at Scale.** The model is fine at *ranking* (ROC-AUC 0.950 measured), but balanced weights trained it as if positives were 50 % of the data. Predicted probabilities average 0.088 against a true rate of 0.011, so every premium is ~8× too high.

**L7 Principal Defense.** Separate ranking from probability. If you reweight or resample, correct the prior: p_true = βp/(βp − p + 1) for undersampling at rate β (measured: Brier 0.0048 → 0.0034, mean p 0.0091 against base 0.0109). Or calibrate on unweighted held-out data with isotonic or sigmoid calibration (ECE 0.0003). Monitor calibration (Brier, ECE, mean prediction vs base rate) as a production SLI, because pricing, expected-loss and bidding systems consume probabilities, not ranks.

</details>

<details><summary><b>Q4 · "Which metric do you put on the dashboard for a 0.5 % fraud rate?"</b></summary>

**Initial Prompt.** Leadership wants one number for the fraud model.

**L5 Answer.** "Accuracy, or ROC-AUC."

**Why L5 Crashes at Scale.** Accuracy rewards predicting "not fraud" (0.989 measured at a 1 % rate). ROC-AUC is dominated by the huge negative class and looks excellent even when precision at operating thresholds is poor (0.866 ROC-AUC with 0.427 PR-AUC measured).

**L7 Principal Defense.** Report the operating point the business uses: precision and recall at the chosen threshold (or recall at a fixed precision, e.g. "at ≥ 80 % precision we catch 69 %", measured), plus PR-AUC for threshold-free comparison, plus calibration error if probabilities drive money. Add cost-weighted metrics (fraud loss prevented vs review cost). Track them per segment and over time, since a rare-event model can degrade in one segment without moving the global number.

</details>

<details><summary><b>Q5 · "Undersample, oversample (SMOTE), or reweight?"</b></summary>

**Initial Prompt.** 2 B transactions per month, 0.2 % fraud.

**L5 Answer.** "SMOTE, because it creates more positive examples."

**Why L5 Crashes at Scale.** SMOTE interpolates synthetic positives, which can blur decision boundaries in high-dimensional, categorical-heavy data, and it inflates training data further. It also miscalibrates, like any rebalancing. At 2 B rows the bottleneck is processing the negatives, not a shortage of positives.

**L7 Principal Defense.** Undersample the negatives (measured: ~20× faster fits with equal or better PR-AUC), apply the prior correction or calibrate, and validate on untouched data at the true base rate. Use class weights when data is small and speed doesn't matter, and calibrate after. Reserve SMOTE-style methods for small, low-dimensional numeric problems, and prove gains on PR-AUC at the true rate. Whatever the method, pick thresholds on the PR curve.

</details>

<details><summary><b>Q6 · "Design online and offline feature computation for a high-cardinality encoding."</b></summary>

**Initial Prompt.** A target-encoded `merchant_risk` feature must be identical in training and in the 10 ms scoring path.

**L5 Answer.** "Compute it in SQL for training and in Java for serving."

**Why L5 Crashes at Scale.** Two implementations drift in smoothing constants, priors, update cadence and unseen-level handling, which shows up as training/serving skew in exactly the feature the model relies on most.

**L7 Principal Defense.** Compute encodings in one place: an offline job produces a versioned table (level → smoothed rate, count) with point-in-time correctness for training (03.4), loaded into an online key-value store for serving. The model artifact references the table version. Unseen levels map to the prior with count 0, identical in both paths. A parity job scores a sample through both paths daily and alerts on differences. A stateless alternative is hashing plus learned weights, which needs no shared table at all.

</details>

<details><summary><b>Q7 · "How big should the hash space be?"</b></summary>

**Initial Prompt.** Pick `n_features` for hashing 3 M distinct tokens.

**L5 Answer.** "2^16 is the default."

**Why L5 Crashes at Scale.** With L = 3 M and m = 65 536, nearly every bucket holds dozens of tokens, so the model can't distinguish them and quality collapses silently. Defaults are tuned for small vocabularies.

**L7 Principal Defense.** Use the birthday math with explicit definitions. The fraction of levels landing in an already-occupied bucket is ≈ L/(2m) for L ≪ m (measured 5.6 % at L/m = 0.12). The fraction of levels sharing a bucket with *any* other is ≈ 1 − e^(−L/m) ≈ L/m. For 3 M tokens, m = 2^24 gives ~8.5 % and ~16 % respectively. Weigh that against model size (a linear model's weight vector is m floats: 64 MB at 2^24 × 4 B). Use signed hashing so collisions partially cancel, and measure the quality curve across m on a validation set rather than guessing.

</details>

<details><summary><b>Q8 · "Explain why rebalancing doesn't change ROC-AUC much but changes probabilities a lot."</b></summary>

**Initial Prompt.** A reviewer is surprised that ROC-AUC stayed at 0.95 after balancing while the mean prediction rose eightfold.

**L5 Answer.** "Balancing helps the model learn the minority class better."

**Why L5 Crashes at Scale.** It conflates ranking with calibration, which leads to deploying miscalibrated probabilities into systems that need true probabilities.

**L7 Principal Defense.** Reweighting multiplies the likelihood ratio by a constant, which for a well-specified model shifts the logit by log(weight ratio): a monotone transformation of scores. Monotone transformations preserve the ordering, so ROC-AUC and PR-AUC barely move (0.954 → 0.950 measured). They move every probability toward the reweighted prior (mean p 0.011 → 0.088). Hence the prior-correction formula restores probabilities exactly for undersampling, and calibration fixes reweighting empirically. Tree ensembles aren't perfectly well-specified, so always verify calibration after the fix.

</details>

---

## 5. Invariants Checklist

- [ ] Keep one-hot sparse (CSR): bytes ≈ nnz × 8 + indptr. Never densify wide categoricals.
- [ ] Hashing gives fixed width, statelessness and unseen-value safety; ≈ L/(2m) of levels land in an occupied bucket. Size m deliberately.
- [ ] Target encoding must be cross-fitted (out-of-fold) and smoothed. Naive mean encoding leaks (0.145 AUC gap here).
- [ ] For rare positives, report PR-AUC, precision/recall at the operating threshold and calibration; never accuracy.
- [ ] Class weights and resampling preserve ranking and distort probabilities. Prior-correct or calibrate.
- [ ] Undersampling negatives is the fastest route at scale (~20× fewer rows here) when prior-corrected.
- [ ] Choose thresholds from the PR curve to meet business constraints.

---

## 6. References

- scikit-learn, encoding categorical features — https://scikit-learn.org/stable/modules/preprocessing.html#encoding-categorical-features
- scikit-learn `TargetEncoder` (cross-fitting) — https://scikit-learn.org/stable/modules/preprocessing.html#target-encoder
- scikit-learn feature hashing — https://scikit-learn.org/stable/modules/feature_extraction.html#feature-hashing
- scikit-learn probability calibration — https://scikit-learn.org/stable/modules/calibration.html
- K. Weinberger et al., "Feature Hashing for Large Scale Multitask Learning", ICML 2009 — https://arxiv.org/abs/0902.2206
- D. Micci-Barreca, "A preprocessing scheme for high-cardinality categorical attributes", SIGKDD Explorations 3(1), 2001, DOI 10.1145/507533.507538.
- T. Saito, M. Rehmsmeier, "The Precision-Recall Plot Is More Informative than the ROC Plot When Evaluating Binary Classifiers on Imbalanced Datasets", PLOS ONE 2015, DOI 10.1371/journal.pone.0118432.
- C. Elkan, "The Foundations of Cost-Sensitive Learning", IJCAI 2001 — https://www.ijcai.org/Proceedings/01/IJCAI-2001-e.pdf
- A. Dal Pozzolo et al., "Calibrating Probability with Undersampling for Unbalanced Classification", IEEE SSCI 2015, DOI 10.1109/SSCI.2015.33.
