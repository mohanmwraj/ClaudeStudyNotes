# 06.1 · Classification Metrics: Precision, Recall, F1, PR-AUC vs ROC-AUC & Threshold Tuning

> **Folder 06 · Evaluation Statistics, Error Analysis & LLM-as-a-Judge**
> **Measured on:** NumPy 2.5.4 and scikit-learn 1.9.1 (metric definitions cross-checked against `sklearn.metrics`), a logistic-regression router on real CLINC150 MiniLM embeddings (02.3), Windows 11.
> **Design sources:** Hanley & McNeil (AUC = Mann-Whitney, 1982), Fawcett (ROC analysis, 2006), Davis & Goadrich (PR vs ROC, 2006), Saito & Rehmsmeier (PR for imbalanced data, 2015), Elkan (cost-sensitive thresholds, 2001), Ng (single-number metrics, satisficing vs optimizing). Full list in §8.

---

## 0. Orientation: A Metric Is a Product Decision Written as a Formula

Every guardrail, router and hallucination detector in this KB eventually reduces to **one score and one threshold**. The metric you report decides which threshold you pick, and the threshold decides what users see: blocked legitimate requests (false positives) or leaked bad ones (false negatives). Everything in this file has been measured on concrete numbers:

- **ROC-AUC is blind to prevalence; precision is not.** The *same* classifier, with fixed score distributions, has ROC-AUC 0.86 at every prevalence. But its PR-AUC falls from 0.85 (50% positives) to 0.016 (0.1% positives), and its precision at a fixed threshold falls from 0.88 to 0.0067. A PII or prompt-injection guardrail lives at the 0.1% end.
- **"The best threshold" is three different numbers.** On one score distribution at 5% prevalence: max-F1 picks t = 1.77 (recall 0.39), max-F2 picks 1.19 (recall 0.62), and minimum cost with FN = 20 × FP picks 0.61 (recall 0.81). The objective comes first; the threshold follows.
- **On the real CLINC150 router**, accuracy is 0.855, macro F1 is 0.898 and weighted F1 is 0.842, all from one prediction set. The OOS class has precision 0.981 but **recall 0.414**: 586 of the 798 errors are out-of-scope queries routed to an intent. No single summary number tells you that.

### The backend-engineer bridge

| You already know | Classification-metric equivalent |
|---|---|
| Alert precision vs alert recall (pager fatigue vs missed incidents) | **Precision** = TP / (TP + FP); **recall** = TP / (TP + FN) |
| An SLO that is a *constraint* (p99 < 200 ms), not the thing you maximize | **Satisficing metric**: precision ≥ 0.99, then maximize recall |
| Tuning an alert threshold on historical incidents | **Threshold selection on a validation set** |
| "Error rate looks fine" because 99.9% of requests are health checks | **Accuracy under class imbalance**: always-negative scores 99.9% |
| Weighting incident severities (SEV1 ≫ SEV3) | **Cost-sensitive thresholds**: FN cost ≠ FP cost |
| Reporting p50 *and* p99 *and* per-endpoint latency | **Micro / macro / per-class** metrics |

### Tier map

| Subtopic | Tier |
|---|---|
| 1.1 The confusion matrix and the four rates | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.2 F1, F-β, and why the harmonic mean | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.3 ROC curves and ROC-AUC as a ranking probability | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.4 PR curves, average precision, and the prevalence proof | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.5 Threshold selection: F-β, cost, and constraints | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.6 Multiclass: micro, macro, weighted, per-class | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.7 Uncertainty on a metric: Wilson intervals and paired tests | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.8 Prior shift: re-deriving precision and thresholds for a new base rate | `[GOOD-TO-KNOW: Architectural Literacy]` |
| 1.9 MCC, balanced accuracy, Cohen's κ | `[GOOD-TO-KNOW: Architectural Literacy]` |
| 1.10 Calibration metrics (ECE, Brier) and their link to thresholds | `[GOOD-TO-KNOW: Architectural Literacy]` |
| 1.11 ROC convex hulls, cost curves, proper-scoring-rule theory | `[SKIP: Academic/Research Only]` |

---

## 1. First-Principles Math & Geometric Intuition

### 1.1 The confusion matrix and the four rates `[MUST-KNOW: Core AI Engineer Edge]`

A binary classifier outputs a score s(x). A threshold t turns it into a decision ŷ = [s(x) ≥ t]. Counting decisions against labels gives four cells:

```text
                      predicted positive     predicted negative
actual positive (P)        TP                      FN             recall / TPR = TP / (TP + FN)
actual negative (N)        FP                      TN             FPR = FP / (FP + TN);  specificity = 1 − FPR
                     precision = TP / (TP + FP)
```

There are two kinds of rate, and the distinction drives the rest of this file:

- **Rates conditioned on the true class**: recall (TPR) and FPR. Each divides by one row, so it depends only on how the classifier treats *that class*. They do not move when the class mix changes.
- **Rates conditioned on the prediction**: precision. It divides by a column that mixes both classes, so it depends on how many negatives there are to make mistakes on.

Listing §3.1, section 1, at threshold 1.0 on 20,000 examples (20% positive): TP 2,867, FP 2,500, FN 1,197, TN 13,436. That gives precision 0.534, recall 0.706, FPR 0.157 and F1 0.608, identical to `sklearn.metrics`.

### 1.2 F1, F-β, and why the harmonic mean `[MUST-KNOW: Core AI Engineer Edge]`

```text
F1  = 2·P·R / (P + R)                                  (harmonic mean of precision and recall)
F_β = (1 + β²)·P·R / (β²·P + R)                        β > 1 weights recall β times as much as precision
```

Why the harmonic mean? It is dominated by the smaller value. A classifier that flags everything has R = 1 and P = prevalence. At 1% prevalence the arithmetic mean is ≈ 0.505, which looks respectable. F1 is ≈ 0.0198, which correctly says "useless". F-β comes from van Rijsbergen's effectiveness measure: β is the ratio R/P at which the user is indifferent to trading one for the other.

> **Production reading:** F1 implicitly says a false positive and a false negative cost the same. For a prompt-injection guardrail (a miss is a security incident) or a hallucination detector on medical answers, they don't. That is why §1.5 replaces F1 with an explicit cost or constraint.

### 1.3 ROC curves and ROC-AUC as a ranking probability `[MUST-KNOW: Core AI Engineer Edge]`

Sweep t from +∞ to −∞ and plot (FPR(t), TPR(t)). That is the ROC curve. Its area has an exact probabilistic meaning (Hanley & McNeil, 1982):

```text
ROC-AUC = P( s(x⁺) > s(x⁻) )  +  ½·P( s(x⁺) = s(x⁻) )       x⁺ a random positive, x⁻ a random negative
        = U / (n⁺·n⁻)                                         U = the Mann-Whitney statistic
        = (sum of positive ranks − n⁺(n⁺+1)/2) / (n⁺·n⁻)     computed from ranks in O(n log n)
```

**Proof sketch.** Order all examples by score. Each step down in t admits either one positive (TPR rises by 1/n⁺) or one negative (FPR moves right by 1/n⁻). The area under the staircase adds, for every negative, the fraction of positives scored above it. Summed over negatives and divided by n⁻, that is exactly the fraction of (positive, negative) pairs ordered correctly.

The listing computes it this way and matches `roc_auc_score` to six decimals (0.860721). For the listing's binormal model (positives ~ N(1.5, 1), negatives ~ N(0, 1)), the closed form is Φ(1.5/√2) = 0.856, and the measured values are 0.848–0.857.

```text
TPR
 1 ┤                 ●●●●●●●●●●●     each ● is one threshold
   │          ●●●●●●●                AUC = area under the staircase
   │      ●●●●                       = P(random positive outranks random negative)
   │   ●●●
   │ ●●                              diagonal = random ranking (AUC 0.5)
   │●
 0 ┼──────────────────────────── FPR
   0                            1
```

**Geometric reading:** the AUC measures *ranking quality*. That is why it is the right metric for a re-ranker or a router that hands its top-k to an LLM, and the wrong one for a deployed threshold at extreme imbalance.

### 1.4 PR curves, average precision, and the prevalence proof `[MUST-KNOW: Core AI Engineer Edge]`

The precision-recall curve plots (recall(t), precision(t)). Average precision (AP), sklearn's PR-AUC estimator, is the step-wise area:

```text
AP = Σₖ (Rₖ − Rₖ₋₁) · Pₖ          k over thresholds, in order of decreasing score
```

**The prevalence proof.** Let π be the positive base rate. Write precision with the class-conditional rates:

```text
precision(t) = TP / (TP + FP) = π·TPR(t) / ( π·TPR(t) + (1 − π)·FPR(t) )
```

TPR(t) and FPR(t) depend only on the two score distributions, so the ROC curve does not move when π changes. Precision has π in it, so the PR curve collapses as π → 0. The FPR term is multiplied by (1 − π)/π, which is 999 at 1-in-1,000.

Check against the listing at t = 1.5, where TPR = 0.5 and FPR = P(N(0,1) > 1.5) = 0.0668:

| Prevalence π | Precision predicted by the formula | Measured | ROC-AUC measured | AP measured |
|---|---|---|---|---|
| 0.5 | 0.5·0.5 / (0.25 + 0.0334) = 0.882 | 0.884 | 0.856 | 0.854 |
| 0.1 | 0.05 / (0.05 + 0.0601) = 0.454 | 0.451 | 0.857 | 0.473 |
| 0.01 | 0.005 / (0.005 + 0.0661) = 0.070 | 0.073 | 0.857 | 0.120 |
| 0.001 | 0.0005 / (0.0005 + 0.0667) = 0.0074 | 0.0067 | 0.848 | 0.016 |

**What this means in production.** A guardrail model validated on a balanced dataset ("ROC-AUC 0.86, precision 0.88 at our threshold") will deliver about **7 true alerts per 1,000 alerts** at a real base rate of 1 in 1,000. The model is unchanged; the traffic is different. Report PR-AUC or precision at the *deployment* prevalence. Use ROC-AUC to compare rankers, not to promise alert quality.

> A random classifier's AP equals π, not 0.5. So "AP 0.12" at π = 0.01 is 12× better than random, while "ROC-AUC 0.86" says nothing about the base rate. Always print the AP of the trivial baseline next to the model.

### 1.5 Threshold selection: F-β, cost, and constraints `[MUST-KNOW: Core AI Engineer Edge]`

There are three principled ways to choose t. On the same score distribution they give different answers (listing §3.1, section 3, 200,000 examples at 5% prevalence):

| Objective | Chosen t | Precision | Recall | When it's right |
|---|---|---|---|---|
| max F1 | 1.77 | 0.350 | 0.391 | FP and FN cost about the same, no constraints |
| max F2 | 1.19 | 0.219 | 0.623 | Misses cost more, but you can't price them |
| min expected cost, C_FN = 20·C_FP | 0.61 | 0.137 | 0.814 | You can price both errors (the right default) |

**The Bayes-optimal rule for calibrated probabilities** (Elkan, 2001; derived in 01.3 §1.3): predict positive when

```text
p(y=1 | x) · C_FN  >  (1 − p(y=1 | x)) · C_FP    ⇔    p > C_FP / (C_FP + C_FN)
```

With C_FN = 20·C_FP that's p > 1/21 ≈ 0.048. A calibrated model needs **no threshold search**, only the cost ratio, and the threshold moves automatically when costs change. With raw scores, convert through the likelihood ratio. For the listing's binormal model at π = 0.05: posterior odds = (π/(1−π))·exp(1.5s − 1.125) > 1/20 gives s > 0.716. The empirical grid search found 0.61, because the expected-cost curve is flat near its minimum and the search lands anywhere in that flat region. Report the cost curve, not just its argmin.

**Constraint-based selection** (the most common in production): "maximize recall subject to precision ≥ 0.95 on the validation set" or "keep FPR ≤ 0.5% so the block rate stays under the support team's budget". This is Ng's satisficing vs optimizing split (§4.1). Implement it as the smallest t whose validation precision meets the bar, with the bar checked on a confidence bound (§1.7), not a point estimate.

### 1.6 Multiclass: micro, macro, weighted, per-class `[MUST-KNOW: Core AI Engineer Edge]`

For K classes, compute one-vs-rest TP_k, FP_k, FN_k, then aggregate:

```text
micro-F1   : pool counts first  → F1(ΣTP, ΣFP, ΣFN)       = accuracy for single-label multiclass
macro-F1   : average per-class F1 equally                  every class counts 1/K
weighted-F1: average per-class F1 weighted by support      big classes dominate
```

**Why micro-F1 = accuracy.** In single-label multiclass, every error is exactly one FP (for the predicted class) and one FN (for the true class). So ΣFP = ΣFN = #errors, and micro-P = micro-R = ΣTP/n = accuracy.

On the real CLINC150 router (listing §3.2: LR head on MiniLM embeddings, OOS as a 151st class, test set 4,500 in-scope + 1,000 OOS):

| Number | Value | What it's sensitive to |
|---|---|---|
| Accuracy = micro-F1 | 0.8549 | The OOS class is 18% of the test traffic |
| Macro-F1 | 0.8975 | The OOS class counts as 1/151 |
| Weighted-F1 | 0.8419 | The OOS class gets 18% of the weight, at F1 0.582 |
| OOS precision / recall | 0.981 / 0.414 | The real problem: OOS queries get answered as if in-scope |

The same predictions give three numbers spanning 5.6 points. **Pick the aggregate that matches the cost:** if every request is equally valuable, accuracy (micro). If every *intent* must work (a long tail of skills, each owned by a team), macro plus the per-class minimum. Either way, **report the worst classes**: per-intent F1 has mean 0.900 but 5th percentile 0.736 and minimum 0.630 (`order`).

### 1.7 Uncertainty on a metric: Wilson intervals and paired tests `[MUST-KNOW: Core AI Engineer Edge]`

A metric computed on n examples is an estimate. For a proportion p̂ (accuracy, precision, recall), the **Wilson score interval** behaves well near 0 and 1, where the textbook p̂ ± 1.96·√(p̂(1−p̂)/n) fails:

```text
center = (p̂ + z²/2n) / (1 + z²/n)
half   = z·√( p̂(1 − p̂)/n + z²/4n² ) / (1 + z²/n)          z = 1.96 for 95%
```

**Napkin numbers worth memorizing:**

- At p ≈ 0.9 and n = 1,000, the 95% half-width is ≈ ±1.9 points. So "90.1% vs 89.4%" on 1,000 examples is noise.
- **Rule of three:** if you observe 0 failures in n trials, the 95% upper bound on the failure rate is ≈ 3/n. Claiming "precision ≥ 99%" with no observed false positives needs n ≈ 300 flagged examples. Claiming 99.9% needs ≈ 3,000.
- Recall on a rare class is estimated from the *positives* only. 40 positives give a half-width of about ±14 points at recall 0.7.

**Comparing two classifiers on the same examples** (the common case: model A vs model B on one eval set): don't compare two independent intervals. Use a **paired** test on the disagreements. McNemar's test uses only b = (A right, B wrong) and c = (A wrong, B right): χ² = (|b − c| − 1)² / (b + c). Pairing removes example difficulty, the largest source of variance. 06.4 §1.3 shows the same effect for retrieval with a paired bootstrap: the CI width falls from 0.120 to 0.049.

### 1.8 Prior shift: re-deriving precision and thresholds for a new base rate `[GOOD-TO-KNOW: Architectural Literacy]`

If only the class mix changes (label shift: p(x|y) fixed, p(y) changes), you can **predict deployed precision without new labels**, using the §1.4 formula with the new π. For a calibrated model you can also **correct its probabilities**:

```text
p_new(y=1|x) = π_new·r / ( π_new·r + (1 − π_new) )    where  r = [p_old(y=1|x)/π_old] / [(1 − p_old(y=1|x))/(1 − π_old)]
```

This is Bayes' rule with the likelihood ratio held fixed (01.3 §1.2; 01.3 §1.4 derives and measures the correction). Estimating π_new itself without labels is possible from the confusion matrix (black-box shift estimation, Lipton et al., 2018) or by EM on the predicted probabilities (Saerens et al., 2002). It's useful for a guardrail whose attack rate changes by month. The assumption fails when *what* the attacks look like changes (covariate or concept drift, 07.3).

### 1.9 MCC, balanced accuracy, Cohen's κ `[GOOD-TO-KNOW: Architectural Literacy]`

- **Balanced accuracy** = (TPR + TNR)/2. It's prevalence-invariant like ROC, but at one threshold.
- **Matthews correlation coefficient** = (TP·TN − FP·FN)/√((TP+FP)(TP+FN)(TN+FP)(TN+FN)). It's the Pearson correlation between ŷ and y, symmetric in the classes, and 0 for any constant predictor. It's a good single number when both classes matter.
- **Cohen's κ** = (p_o − p_e)/(1 − p_e): agreement corrected for chance. It's the right number for *rater* agreement (human vs human, judge vs human; 06.3 §1.6), where "always pass" can score 41% raw agreement at κ = 0.

### 1.10 Calibration metrics (ECE, Brier) and their link to thresholds `[GOOD-TO-KNOW: Architectural Literacy]`

02.1 §1.7 covered calibration. The link to this file: **the cost-based threshold p > C_FP/(C_FP + C_FN) is only correct if p is calibrated.** A model with ROC-AUC 0.95 and bad calibration ranks well, but its probabilities can't be plugged into the cost rule. Either calibrate (Platt or isotonic on held-out data) or search thresholds empirically on validation data with the cost function. The Brier score is a proper scoring rule: it rewards both ranking and calibration, so it's a reasonable model-selection metric when thresholds will be derived from costs.

### 1.11 ROC convex hulls, cost curves, proper-scoring-rule theory `[SKIP: Academic/Research Only]`

The ROC convex hull shows which classifiers are optimal for *some* cost ratio. Drummond & Holte's cost curves plot expected cost against the operating condition. The theory of proper scoring rules characterizes which losses elicit calibrated probabilities. All are elegant. In practice, a cost-weighted threshold sweep on a validation set, with a confidence bound, captures what you need.

---

## 2. Where It Beats an LLM in Production

The metrics here matter in two ways: they are how you *prove* a cheap classifier can replace an LLM call, and they expose a structural advantage cheap scorers have over generative classifiers.

**1. A score is a whole operating curve; a label is one point.** A logistic-regression guardrail outputs p(unsafe | x), so one model gives every point on its ROC and PR curves. You can move the threshold per tenant, per surface or per incident without retraining: tighten during an attack, loosen for an internal tool. An LLM prompted to answer "SAFE/UNSAFE" gives one (FPR, TPR) point. Moving it means rewriting the prompt and re-running the eval, and many hosted LLM APIs don't expose token log-probabilities that would give you a score. (Asking the model for a "confidence 0–100" gives a poorly calibrated score; 01.3 §1.13.)

**2. Thresholds can be set from costs.** With a calibrated head, the cost rule p > C_FP/(C_FP + C_FN) (§1.5) turns a business decision ("a leaked injection costs 20× a blocked user") into a threshold in one line. With a label-only LLM there is nothing to threshold.

**3. Measuring at deployment prevalence is cheap.** A head scores 100,000 production requests in seconds on a CPU (02.3), so you can estimate the flag rate, sample flagged items for labelling, and compute deployed precision. The same audit with an LLM classifier costs real money per run.

**When the LLM is still the right tool:** low-volume, high-ambiguity decisions where the rubric keeps changing (policy review queues), or as the *expensive second stage* of a cascade that only sees what the cheap model is unsure about (07.1). Even then, every metric in this file applies to evaluating it.

---

## 3. Production Code Blueprint

### 3.1 Binary metrics from first principles, prevalence, and three thresholds

```python
"""classification_metrics_from_scratch.py - precision, recall, F-beta, ROC-AUC and PR-AUC from first principles.

  1. Confusion-matrix metrics, and ROC-AUC as the Mann-Whitney rank statistic (== sklearn), AP (== sklearn).
  2. The SAME classifier at prevalence 50% / 10% / 1% / 0.1%: ROC-AUC does not move, PR-AUC collapses.
  3. Threshold tuning: the F1-optimal, F2-optimal and cost-optimal thresholds are different numbers.
"""
import numpy as np
from sklearn.metrics import average_precision_score, roc_auc_score

rng = np.random.default_rng(151)


def confusion(y, s, t):
    p = s >= t
    tp, fp = np.sum(p & y), np.sum(p & ~y)
    fn, tn = np.sum(~p & y), np.sum(~p & ~y)
    return tp, fp, fn, tn


def f_beta(prec, rec, beta):
    return (1 + beta ** 2) * prec * rec / (beta ** 2 * prec + rec) if prec + rec > 0 else 0.0


def auc_rank(y, s):
    """P(score of a random positive > score of a random negative); ties count 1/2 (Mann-Whitney U / (n+ n-))."""
    order = np.argsort(s, kind="mergesort")
    ranks = np.empty(len(s))
    sorted_s = s[order]
    i = 0
    while i < len(s):                                              # average ranks over ties
        j = i
        while j + 1 < len(s) and sorted_s[j + 1] == sorted_s[i]:
            j += 1
        ranks[order[i:j + 1]] = (i + j) / 2 + 1
        i = j + 1
    npos, nneg = y.sum(), (~y).sum()
    return (ranks[y].sum() - npos * (npos + 1) / 2) / (npos * nneg)


def average_precision(y, s):
    order = np.argsort(-s, kind="mergesort")
    hits = y[order]
    prec_at_hit = np.cumsum(hits)[hits] / (np.flatnonzero(hits) + 1)
    return prec_at_hit.mean()


def sample(n, prevalence):
    y = rng.random(n) < prevalence
    s = np.where(y, rng.normal(1.5, 1.0, n), rng.normal(0.0, 1.0, n))   # fixed class-conditional score distributions
    return y, s


print("== 1. definitions, checked against sklearn ==")
y, s = sample(20_000, 0.2)
tp, fp, fn, tn = confusion(y, s, 1.0)
prec, rec = tp / (tp + fp), tp / (tp + fn)
print(f"threshold 1.0: TP {tp} FP {fp} FN {fn} TN {tn}; precision {prec:.4f} recall {rec:.4f} "
      f"F1 {f_beta(prec, rec, 1):.4f} FPR {fp / (fp + tn):.4f}")
print(f"ROC-AUC ours {auc_rank(y, s):.6f} sklearn {roc_auc_score(y, s):.6f} | "
      f"AP ours {average_precision(y, s):.6f} sklearn {average_precision_score(y, s):.6f}")
assert abs(auc_rank(y, s) - roc_auc_score(y, s)) < 1e-12 and abs(average_precision(y, s) - average_precision_score(y, s)) < 1e-12

print("\n== 2. one classifier, four prevalences (the score distributions never change) ==")
print(f"{'prevalence':>10} {'ROC-AUC':>8} {'PR-AUC (AP)':>11} {'precision@t=1.5':>16} {'recall@t=1.5':>13}")
rows = {}
for prev in (0.5, 0.1, 0.01, 0.001):
    y, s = sample(400_000, prev)
    tp, fp, fn, tn = confusion(y, s, 1.5)
    rows[prev] = (roc_auc_score(y, s), average_precision_score(y, s))
    print(f"{prev:>10.3f} {rows[prev][0]:>8.4f} {rows[prev][1]:>11.4f} {tp / max(tp + fp, 1):>16.4f} {tp / (tp + fn):>13.4f}")
print("ROC-AUC conditions on the class (TPR, FPR are per-class rates); precision and AP depend on the base rate")
assert abs(rows[0.5][0] - rows[0.001][0]) < 0.01 and rows[0.001][1] < 0.3 * rows[0.5][1]

print("\n== 3. three 'best' thresholds on the same scores (prevalence 5%) ==")
y, s = sample(200_000, 0.05)
grid = np.linspace(-1, 4, 501)
stats = [confusion(y, s, t) for t in grid]
f1 = [f_beta(tp / max(tp + fp, 1), tp / (tp + fn), 1) for tp, fp, fn, tn in stats]
f2 = [f_beta(tp / max(tp + fp, 1), tp / (tp + fn), 2) for tp, fp, fn, tn in stats]
C_FP, C_FN = 1.0, 20.0
cost = [(C_FP * fp + C_FN * fn) / len(y) for tp, fp, fn, tn in stats]
for name, arr, best in (("max F1", f1, np.argmax), ("max F2 (recall weighted 2x)", f2, np.argmax), ("min cost (FN = 20 x FP)", cost, np.argmin)):
    i = int(best(arr))
    tp, fp, fn, tn = stats[i]
    print(f"{name:28s} threshold {grid[i]:.2f}: precision {tp / max(tp + fp, 1):.3f} recall {tp / (tp + fn):.3f}")
print("pick the objective from the product's costs FIRST; the threshold follows (01.3 s1.3)")
print("\nALL ASSERTIONS PASSED")
```

Output (verified):

```text
== 1. definitions, checked against sklearn ==
threshold 1.0: TP 2867 FP 2500 FN 1197 TN 13436; precision 0.5342 recall 0.7055 F1 0.6080 FPR 0.1569
ROC-AUC ours 0.860721 sklearn 0.860721 | AP ours 0.651159 sklearn 0.651159

== 2. one classifier, four prevalences (the score distributions never change) ==
prevalence  ROC-AUC PR-AUC (AP)  precision@t=1.5  recall@t=1.5
     0.500   0.8556      0.8540           0.8836        0.4999
     0.100   0.8565      0.4730           0.4505        0.4997
     0.010   0.8573      0.1204           0.0730        0.5036
     0.001   0.8479      0.0157           0.0067        0.4839
ROC-AUC conditions on the class (TPR, FPR are per-class rates); precision and AP depend on the base rate

== 3. three 'best' thresholds on the same scores (prevalence 5%) ==
max F1                       threshold 1.77: precision 0.350 recall 0.391
max F2 (recall weighted 2x)  threshold 1.19: precision 0.219 recall 0.623
min cost (FN = 20 x FP)      threshold 0.61: precision 0.137 recall 0.814
pick the objective from the product's costs FIRST; the threshold follows (01.3 s1.3)

ALL ASSERTIONS PASSED
```

### 3.2 Multiclass metrics on the real CLINC150 router

```python
"""clinc_multiclass_metrics.py - multiclass metrics on a real router (CLINC150 + out-of-scope as class 151).

  1. Accuracy vs micro / macro / weighted F1 when one class (OOS) is large and hard.
  2. The per-intent F1 distribution: the mean hides the worst intents.
  3. The top confusion pairs: where to look first in error analysis (06.3).
"""
import json
import os
from collections import Counter

import numpy as np
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import accuracy_score, f1_score, precision_recall_fscore_support

DATA = os.environ["KB_DATA"]
Z = np.load(os.path.join(DATA, "clinc_minilm.npz"))
labels = json.load(open(os.path.join(DATA, "clinc_meta.json"), encoding="utf-8"))["labels"] + ["oos"]
OOS = 150
Xtr = np.vstack([Z["X_train"], Z["X_oos_train"]])
ytr = np.r_[Z["y_train"], np.full(len(Z["X_oos_train"]), OOS)]
Xte = np.vstack([Z["X_test"], Z["X_oos_test"]])
yte = np.r_[Z["y_test"], np.full(len(Z["X_oos_test"]), OOS)]
clf = LogisticRegression(C=10, max_iter=3000).fit(Xtr, ytr)
pred = clf.predict(Xte)

print("== 1. one prediction set, five summary numbers (test: 4,500 in-scope + 1,000 OOS) ==")
print(f"accuracy                {accuracy_score(yte, pred):.4f}")
for avg in ("micro", "macro", "weighted"):
    print(f"F1 {avg:20s} {f1_score(yte, pred, average=avg):.4f}")
p, r, f, sup = precision_recall_fscore_support(yte, pred, labels=range(151), zero_division=0)
print(f"OOS class: precision {p[OOS]:.3f} recall {r[OOS]:.3f} F1 {f[OOS]:.3f} (support {sup[OOS]})")
print("micro F1 == accuracy for single-label multiclass; macro averages classes equally, so the OOS class")
print("counts as 1/151 of macro F1 but 18% of accuracy")
assert abs(f1_score(yte, pred, average="micro") - accuracy_score(yte, pred)) < 1e-12

print("\n== 2. per-intent F1 (150 in-scope intents) ==")
fi = f[:150]
print(f"mean {fi.mean():.3f}, median {np.median(fi):.3f}, 5th percentile {np.percentile(fi, 5):.3f}, min {fi.min():.3f}")
print("worst five intents:")
for c in np.argsort(fi)[:5]:
    print(f"  {labels[c]:24s} F1 {fi[c]:.3f} (precision {p[c]:.3f}, recall {r[c]:.3f})")

print("\n== 3. top confusion pairs (true -> predicted) ==")
pairs = Counter((int(t), int(q)) for t, q in zip(yte, pred) if t != q)
for (t, q), n in sorted(pairs.items(), key=lambda kv: (-kv[1], kv[0]))[:8]:
    print(f"  {n:4d}  {labels[t]:24s} -> {labels[q]}")
oos_in = sum(n for (t, q), n in pairs.items() if t == OOS)
in_oos = sum(n for (t, q), n in pairs.items() if q == OOS and t != OOS)
print(f"errors: {sum(pairs.values())} total; OOS routed to an intent {oos_in}; in-scope sent to OOS {in_oos}")
assert oos_in > 0.5 * sum(pairs.values())
print("\nALL ASSERTIONS PASSED")
```

Output (verified):

```text
== 1. one prediction set, five summary numbers (test: 4,500 in-scope + 1,000 OOS) ==
accuracy                0.8549
F1 micro                0.8549
F1 macro                0.8975
F1 weighted             0.8419
OOS class: precision 0.981 recall 0.414 F1 0.582 (support 1000)
micro F1 == accuracy for single-label multiclass; macro averages classes equally, so the OOS class
counts as 1/151 of macro F1 but 18% of accuracy

== 2. per-intent F1 (150 in-scope intents) ==
mean 0.900, median 0.909, 5th percentile 0.736, min 0.630
worst five intents:
  order                    F1 0.630 (precision 0.535, recall 0.767)
  directions               F1 0.651 (precision 0.509, recall 0.900)
  travel_suggestion        F1 0.690 (precision 0.526, recall 1.000)
  change_user_name         F1 0.714 (precision 0.769, recall 0.667)
  change_ai_name           F1 0.716 (precision 0.649, recall 0.800)

== 3. top confusion pairs (true -> predicted) ==
    25  oos                      -> travel_suggestion
    23  oos                      -> directions
    19  oos                      -> smart_home
    18  oos                      -> order
    17  oos                      -> ingredients_list
    15  oos                      -> make_call
    15  oos                      -> weather
    14  oos                      -> calculator
errors: 798 total; OOS routed to an intent 586; in-scope sent to OOS 8

ALL ASSERTIONS PASSED
```

**Reading the output.** All eight of the top confusion pairs are `oos → some intent`. The router's biggest problem is not intent confusion but **accepting out-of-scope queries**: 586 of 798 errors. Macro-F1 (0.898) hides this almost completely, because the OOS class is 1 of 151. The fix lives in 02.3 (a cosine gate on top of the head) and 03.3 (OOD detectors), not in more intent training data. That is the core move of error analysis (06.3): find the bucket before choosing the fix.

### 3.3 A threshold-selection function worth putting in your library

```python
def pick_threshold(y_val, p_val, *, min_precision=None, c_fp=1.0, c_fn=1.0, z=1.96):
    """Constraint first (Wilson lower bound on precision >= min_precision, maximize recall), else min expected cost."""
    order = np.argsort(-p_val)
    ys, ps = y_val[order], p_val[order]
    tp = np.cumsum(ys); fp = np.cumsum(1 - ys); n_pos = ys.sum()
    if min_precision is not None:
        n = tp + fp
        prec = tp / n
        lower = (prec + z**2 / (2 * n) - z * np.sqrt(prec * (1 - prec) / n + z**2 / (4 * n**2))) / (1 + z**2 / n)
        ok = np.flatnonzero(lower >= min_precision)
        if len(ok) == 0:
            raise ValueError("no threshold meets the precision bar with confidence; collect more labels")
        k = ok[-1]                                    # the deepest cut that still meets the bar = max recall
        return float(ps[k]), {"precision": float(prec[k]), "precision_lower95": float(lower[k]), "recall": float(tp[k] / n_pos)}
    cost = c_fp * fp + c_fn * (n_pos - tp)
    k = int(np.argmin(cost))
    return float(ps[k]), {"expected_cost_per_item": float(cost[k] / len(ys)), "recall": float(tp[k] / n_pos)}
```

This is a design sketch, not a gated listing. Its two properties matter: the precision bar is checked on a **lower confidence bound**, not the point estimate, and the function **refuses** rather than silently returning a threshold it can't support.

---

## 4. The Andrew Ng Lens: One Metric to Optimize, the Rest Satisficed

### 4.1 Single-number evaluation metric; optimizing vs satisficing

In *Machine Learning Yearning* and Course 3 of the Deep Learning Specialization (Structuring ML Projects), Ng's rule is to pick **one optimizing metric** and turn everything else into **satisficing constraints**. For example: "maximize recall on prompt injections, subject to precision ≥ 0.95 at deployment prevalence, p99 latency ≤ 10 ms, and ≤ 0.5% of benign traffic blocked." A team that argues F1 vs precision vs AUC in every review is missing this step. The metric is a *product* decision. Write it down before modelling, and put it in the eval harness so every experiment reports it the same way.

### 4.2 Change the metric when it stops matching the product

Ng's example is a cat classifier whose "better" model lets pornographic images through. The error metric was fine; it just weighted all errors equally. The fix was a **weighted metric**, not a new model. The AI-engineering equivalent: a router "improves" from 0.855 to 0.86 accuracy while OOS recall drops, so more off-topic queries get confidently wrong answers. If the metric doesn't punish that, change the metric (OOS-weighted error, or OOS recall as a satisficing floor) and re-rank your past experiments under it.

### 4.3 Dev and test sets from the deployment distribution

Ng insists dev and test sets come from the distribution you expect to see in production. §1.4 shows why that's not pedantry: a balanced dev set will overstate a 0.1%-prevalence guardrail's precision by more than 100×. Build the eval set by **sampling production traffic**, then enrich it with known hard cases in a *separate* slice. Report both, and never mix them into one number.

### 4.4 Evaluation-driven development (EDD)

These metrics are the first layer of Ng's evaluation-driven loop: build a quick system, measure it with a fixed metric on a fixed set, look at the errors (06.3), fix the biggest bucket, and re-measure. That only works if the metric and the threshold procedure are frozen *before* you iterate. Otherwise every iteration changes the ruler as well as the system.

---

## 5. Failure Modes

| # | Symptom | Signature | Root cause | Fix | Prevention |
|---|---|---|---|---|---|
| F1 | "Great offline, flood of false alarms in production" | Validation precision 0.88, deployed 0.007 | Validated at balanced prevalence; deployed at 0.1% | Report precision / AP at deployment prevalence (§1.4) | Eval set sampled from production traffic, plus a separate hard-case slice |
| F2 | Accuracy 99.9% on a guardrail | Always-negative baseline also 99.9% | Accuracy under extreme imbalance | Precision, recall, PR-AUC; print the trivial baseline | Metric spec reviewed before modelling |
| F3 | Threshold "0.5" in production | Default never revisited | Treating 0.5 as meaningful | Cost-based or constraint-based selection (§1.5) | `pick_threshold` in the library; threshold stored with the model version |
| F4 | ROC-AUC improved, users see more bad outputs | AUC up, precision at the operating point down | AUC integrates over thresholds you never use | Compare models at the operating point (or partial AUC in the low-FPR region) | Operating-point metrics in the dashboard |
| F5 | Macro-F1 looks great, one intent is broken | Mean 0.90, min 0.63 | Averages hide the tail | Per-class table, worst-k, confusion pairs | Per-class floors in the release gate |
| F6 | "Model B is better" on 1,000 examples | +0.7 points, overlapping intervals | No uncertainty estimate | Wilson CI; paired McNemar / bootstrap | Every reported delta has a CI |
| F7 | Precision SLA met in the test, violated in production | Point estimate exactly at the bar | Bar checked on the point estimate with few positives | Check the Wilson lower bound; collect more labels | Rule of three: n ≈ 3/(1 − bar) flagged examples minimum |
| F8 | Threshold drifts "on its own" | Same model, flag rate changing weekly | Prior shift or covariate drift | Recompute expected precision with the new π (§1.8); recalibrate | Monitor flag rate and score distribution (07.3) |
| F9 | Cost-based threshold gives absurd results | t far from the validated region | Uncalibrated probabilities used in the cost rule | Calibrate first (Platt or isotonic) or search empirically | Calibration check (ECE) in the release gate |

---

## 6. Bar-Raiser Q&A Chains

<details><summary><b>Q1 · "Our PII guardrail has ROC-AUC 0.95. Can we ship it?"</b></summary>

**Initial Prompt.** A team presents a guardrail classifier with ROC-AUC 0.95 on a balanced validation set.

**L5 Answer.** "0.95 is excellent; ship it at threshold 0.5."

**Why L5 Fails in Production.** ROC-AUC says nothing about precision at the deployment base rate, or about the threshold. At 1-in-1,000 prevalence, a classifier like the one in §1.4 delivers precision 0.0067 at a threshold that gave 0.88 on balanced data.

**L7 Principal Defense.** "AUC tells me it *ranks* well. It doesn't tell me what an alert is worth. I need four things. (1) The deployment prevalence, estimated from a production sample. (2) The cost or constraint: is a leak 20× a false block, or is there a block-rate budget? (3) Precision and recall *at the chosen threshold, at that prevalence*. I can predict precision from TPR, FPR and π with the §1.4 formula before labelling anything. (4) A Wilson lower bound on precision with enough flagged examples (rule of three: ~300 for a 99% claim). Then I'd ship in shadow mode, measure the flag rate, label a sample of flags, and only then enforce."

**Bar-Raiser Follow-ups.**
- *"What if the cost ratio is unknown?"* Ask for a block-rate budget instead (a constraint the support team can state), and maximize recall within it.
- *"Partial AUC?"* Yes, if you must compare rankers: AUC restricted to FPR ≤ 1% is far closer to what a high-precision guardrail experiences.

</details>

<details><summary><b>Q2 · "PR-AUC dropped 40% this month but ROC-AUC is flat. Is the model broken?"</b></summary>

**Initial Prompt.** A monthly eval report on a fresh labelled sample of production traffic.

**L5 Answer.** "PR-AUC is noisy; ROC-AUC is stable, so the model is fine."

**Why L5 Fails in Production.** Flat ROC with falling PR is the fingerprint of a **base-rate drop**, which is real and affects users: precision fell with it.

**L7 Principal Defense.** "ROC is conditioned on the class, so it ignores prevalence. PR isn't (§1.4). If the positive rate fell, say attacks went from 1% to 0.3% of traffic, the model is unchanged but each alert is worth less, and the on-call team sees more false alarms per true one. Confirm by computing π on both months and plugging it into precision = π·TPR / (π·TPR + (1 − π)·FPR). If that predicts the drop, it's prior shift: re-pick the threshold for the new π, or accept the lower precision. If it doesn't, the score distributions moved (covariate or concept drift), and that's a model problem (07.3)."

**Bar-Raiser Follow-ups.**
- *"Can you fix it without new labels?"* For pure label shift, yes: estimate π_new (BBSE or EM) and adjust calibrated probabilities with Bayes' rule (§1.8).
- *"Which number goes in the exec dashboard?"* Precision and recall at the operating point, with the base rate printed next to them.

</details>

<details><summary><b>Q3 · "How do you choose the threshold for a new guardrail?"</b></summary>

**Initial Prompt.** A design review for a prompt-injection detector.

**L5 Answer.** "Maximize F1 on the validation set."

**Why L5 Fails in Production.** F1 encodes "FP and FN cost the same", which is false for security, and it picks a different threshold from the cost-optimal one (1.77 vs 0.61 in §1.5, with recall 0.39 vs 0.81).

**L7 Principal Defense.** "Write the objective first. If we can price errors, I use the Bayes rule. With calibrated probabilities that's p > C_FP/(C_FP + C_FN), no search needed. If we can't price them, I ask for a constraint: precision ≥ x or block rate ≤ y. Then I maximize recall within it, checking the constraint on a Wilson lower bound. The threshold is stored with the model version, re-derived on every retrain, and monitored through the flag rate. I'd also report the whole cost curve, because the optimum is usually flat and the business may prefer a point near it with a rounder block rate."

**Bar-Raiser Follow-ups.**
- *"Per-tenant thresholds?"* Fine with a score-based model: same model, different operating points. Each tenant's validation slice needs enough positives for a meaningful bound.
- *"Two-threshold policy?"* Yes: block above t_high, escalate to an LLM or human between t_low and t_high, allow below (07.1).

</details>

<details><summary><b>Q4 · "Accuracy says 85%, macro-F1 says 90%. Which do we report for the router?"</b></summary>

**Initial Prompt.** The CLINC150 router from §3.2.

**L5 Answer.** "Macro-F1, because the data is imbalanced."

**Why L5 Fails in Production.** It picks the number that looks better without asking what it measures. Macro-F1 weights OOS (18% of traffic) at 1/151 and hides the router's main failure.

**L7 Principal Defense.** "Both numbers are right; they answer different questions. Accuracy (= micro-F1) weights every *request* equally, so it reflects user experience on this traffic mix. Macro-F1 weights every *intent* equally, so it reflects whether each skill works. The 4.3-point gap is almost entirely the OOS class: recall 0.414, so 586 of 798 errors are off-topic queries answered as if they were in scope. I'd report accuracy as the headline (it matches per-request cost), OOS recall as a satisficing floor, and the per-intent worst-5 table for the owning teams."

**Bar-Raiser Follow-ups.**
- *"Weighted F1 is lower than both. Why?"* It gives the OOS class 18% of the weight at F1 0.582, while macro gives it 0.7%.
- *"What fixes OOS recall?"* A gate on similarity or energy scores (02.3, 03.3), not more intent data.

</details>

<details><summary><b>Q5 · "The new LLM classifier scores 92% vs the head's 90%. Prove it's better."</b></summary>

**Initial Prompt.** A team wants to replace a head with an LLM call, citing a 1,000-example eval.

**L5 Answer.** "Two points higher is significant enough."

**Why L5 Fails in Production.** At n = 1,000 and p ≈ 0.9, each estimate is ±1.9 points (95%), and the claim ignores the 100–1000× cost difference.

**L7 Principal Defense.** "Both models ran on the same 1,000 examples, so I'd test the *paired* difference. McNemar on the disagreements: if the LLM is right and the head wrong on 45, and the reverse on 25, then χ² = (|45 − 25| − 1)²/70 = 5.2, p ≈ 0.02. That's evidence, but only on *this* distribution. Then the decision: is +2 points worth ~$68 per million requests vs a fraction of a cent (01.1), plus 500 ms of latency? Often the better answer is a cascade: the head handles what it's confident on, and the LLM sees the uncertain 10–30% (07.1), which captures most of the gain at a fraction of the cost."

**Bar-Raiser Follow-ups.**
- *"And if there are 30 disagreements total?"* Then neither the gain nor its absence is established. Get more labels on the disagreement region specifically, which is the cheapest place to label.
- *"Would you also check calibration?"* Yes, if the LLM's output feeds a threshold or a cascade gate.

</details>

<details><summary><b>Q6 · "Legal wants 99% precision on auto-blocking. How many labels do we need?"</b></summary>

**Initial Prompt.** A compliance requirement on an auto-moderation action.

**L5 Answer.** "Label 1,000 random requests and check the precision."

**Why L5 Fails in Production.** Precision is estimated from *flagged* items only. At a 0.5% flag rate, 1,000 random requests contain about 5 flags, which can't support any precision claim.

**L7 Principal Defense.** "The claim needs a lower confidence bound ≥ 0.99 on precision. With zero observed false positives, the rule of three says n ≈ 300 *flagged* items for a 95% bound. With one or two FPs observed, you need roughly 475–630 (one-sided Poisson bounds 4.74/n and 6.30/n). So I'd sample from the flagged stream, not the full stream: at a 0.5% flag rate that's ~60,000–130,000 requests to *collect* the flags, but only 300–630 human labels. I'd also stratify by surface and language, because the claim has to hold per segment if legal will cite it per segment. And the claim expires: re-validate on every model or threshold change, and keep a weekly sample flowing."

**Bar-Raiser Follow-ups.**
- *"What about recall?"* It needs labels from the *unflagged* stream, where positives are rare, so use stratified sampling by score band, then reweight.
- *"Can an LLM judge do the labelling?"* Only after measuring its agreement with humans on this task (06.3). Its errors would sit directly inside your precision estimate.

</details>

<details><summary><b>Q7 · "Our LLM classifier outputs only labels. How do we get a PR curve?"</b></summary>

**Initial Prompt.** A generative model returns `{"label": "unsafe"}` with no score.

**L5 Answer.** "We can't; just report precision and recall."

**Why L5 Fails in Production.** One operating point leaves you unable to trade precision for recall without re-prompting, and unable to compare fairly with a scored model.

**L7 Principal Defense.** "There are four options, in order of preference. (1) A score from the model itself: token log-probabilities of the label tokens if the API exposes them. (2) Self-consistency: sample k times and use the vote share as a score, which costs k× and is coarse but works through any API. (3) Prompt-family thresholds: a family of prompts ('flag only if certain', 'flag if any doubt') traces out a few operating points, each needing its own eval run. (4) Put the LLM *behind* a scored model: the cheap head's score defines the curve, and the LLM adjudicates a band. To compare an LLM with a head fairly, compare at the head's operating point that matches the LLM's flag rate."

**Bar-Raiser Follow-ups.**
- *"Verbalized confidence?"* Measure its calibration before trusting it. It's usually overconfident (01.3 §1.13).
- *"Cost of option 2?"* k = 5 samples at Haiku-class prices is still far above a head, so it's justified only for the adjudication band.

</details>

<details><summary><b>Q8 · "Per-intent F1 ranges from 0.63 to 1.0. What do you do next?"</b></summary>

**Initial Prompt.** The CLINC per-intent table from §3.2.

**L5 Answer.** "Add training data for the worst intents."

**Why L5 Fails in Production.** It picks a fix before diagnosing. The worst intents (`order`, `directions`, `travel_suggestion`) have *low precision, high recall*: travel_suggestion has precision 0.526, recall 1.000. They're failing because other queries (mostly OOS) get dumped into them, not because they're under-trained.

**L7 Principal Defense.** "Low precision with high recall means the class is an attractor. The confusion pairs confirm it: `oos → travel_suggestion` (25), `oos → directions` (23), `oos → order` (18). More positive training data for those intents would make them *bigger* attractors. The fix is to strengthen the OOS decision (a gate, more diverse OOS training examples, a calibrated threshold) and re-measure. For the genuinely low-recall intents (`change_user_name`, recall 0.667), I'd look for sibling confusion with `change_ai_name` and fix it with contrastive examples or a merged intent with a slot. That's error analysis (06.3): tag the errors, count the buckets, fix the biggest one."

**Bar-Raiser Follow-ups.**
- *"Would macro-F1 have shown you this?"* No. It averaged the attractors into 0.898.
- *"How do you prevent regressions?"* Per-intent F1 floors (and an OOS recall floor) in the release gate.

</details>

<details><summary><b>Q9 · "Why does micro-F1 equal accuracy exactly?"</b></summary>

**Initial Prompt.** A candidate notices accuracy and micro-F1 are both 0.8549.

**L5 Answer.** "Coincidence on this dataset."

**Why L5 Fails in Production.** It's an identity for single-label multiclass, and not knowing it leads to reporting redundant numbers as independent evidence.

**L7 Principal Defense.** "Each misclassified example contributes exactly one FP (to the predicted class) and one FN (to the true class). So ΣFP = ΣFN = number of errors, micro-precision = micro-recall = ΣTP / n = accuracy, and their harmonic mean is the same number. It breaks for multi-label problems (an example can have 2 true labels and 3 predicted), which is the guardrail case with independent sigmoid heads (01.3 §1.15). There, micro-F1 and subset accuracy really differ."

**Bar-Raiser Follow-ups.**
- *"Then what does micro-F1 add in multiclass?"* Nothing over accuracy. Report accuracy plus macro and per-class instead.

</details>

---

## 7. Invariants Checklist

- [ ] The metric spec (one optimizing metric, explicit satisficing constraints) is written before modelling and encoded in the eval harness.
- [ ] Eval sets are sampled from production traffic; hard-case slices are reported separately, never pooled.
- [ ] Every precision or AP number is reported at the **deployment prevalence**, next to the trivial-baseline value (AP of random = π).
- [ ] Thresholds come from a cost rule or a constraint checked on a **Wilson lower bound**, never from a default 0.5.
- [ ] The threshold is versioned with the model and re-derived on every retrain.
- [ ] Multiclass reports include accuracy, macro-F1, the per-class worst-k, and the top confusion pairs.
- [ ] Every comparison between models on the same eval set uses a paired test (McNemar or paired bootstrap) and reports a CI.
- [ ] Probabilities used in cost rules are calibrated (ECE checked).
- [ ] Production dashboards show the flag rate and the score distribution, so prior shift is visible (07.3).

---

## 8. References

1. J. Hanley, B. McNeil, *The meaning and use of the area under a ROC curve*, Radiology 143(1), 1982. https://doi.org/10.1148/radiology.143.1.7063747
2. T. Fawcett, *An introduction to ROC analysis*, Pattern Recognition Letters 27(8), 2006. https://doi.org/10.1016/j.patrec.2005.10.010
3. J. Davis, M. Goadrich, *The Relationship Between Precision-Recall and ROC Curves*, ICML 2006. https://doi.org/10.1145/1143844.1143874
4. T. Saito, M. Rehmsmeier, *The Precision-Recall Plot Is More Informative than the ROC Plot When Evaluating Binary Classifiers on Imbalanced Datasets*, PLOS ONE, 2015. https://doi.org/10.1371/journal.pone.0118432
5. C. Elkan, *The Foundations of Cost-Sensitive Learning*, IJCAI 2001.
6. E. B. Wilson, *Probable Inference, the Law of Succession, and Statistical Inference*, JASA 22, 1927. https://doi.org/10.1080/01621459.1927.10502953
7. Q. McNemar, *Note on the sampling error of the difference between correlated proportions or percentages*, Psychometrika 12, 1947. https://doi.org/10.1007/BF02295996
8. Z. Lipton, Y.-X. Wang, A. Smola, *Detecting and Correcting for Label Shift with Black Box Predictors*, ICML 2018. https://arxiv.org/abs/1802.03916
9. M. Saerens, P. Latinne, C. Decaestecker, *Adjusting the Outputs of a Classifier to New a Priori Probabilities*, Neural Computation 14(1), 2002. https://doi.org/10.1162/089976602753284446
10. S. Larson et al., *An Evaluation Dataset for Intent Classification and Out-of-Scope Prediction* (CLINC150), EMNLP 2019. https://aclanthology.org/D19-1131/
11. scikit-learn, *Metrics and scoring: quantifying the quality of predictions*. https://scikit-learn.org/stable/modules/model_evaluation.html
12. A. Ng, *Machine Learning Yearning* (single-number metrics, optimizing vs satisficing, dev/test distributions). https://www.deeplearning.ai/resources/
13. A. Ng, *Deep Learning Specialization*, Course 3: Structuring Machine Learning Projects. https://www.deeplearning.ai/courses/deep-learning-specialization/
